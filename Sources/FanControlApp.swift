import AppKit
import Combine
import SwiftUI

private enum SMCCommandError: LocalizedError {
    case missingTool
    case command(String)
    case invalidOutput
    case unchanged

    var errorDescription: String? {
        switch self {
        case .missingTool: "Stats is required at /Applications/Stats.app."
        case .command(let detail): detail
        case .invalidOutput: "Could not read fan information from Stats."
        case .unchanged: "The Mac did not accept the fan change. Check whether another app is controlling the fans."
        }
    }
}

private enum SMCTool {
    static let path = "/Applications/Stats.app/Contents/Resources/smc"

    static func run(_ arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw SMCCommandError.missingTool }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 || output.contains("[ERROR]") || output.localizedCaseInsensitiveContains("write failed") || output.contains("Error write") || output.contains("Error read") {
            throw SMCCommandError.command(output.isEmpty ? "Stats SMC command failed." : output)
        }
        return output
    }

    static func fans() throws -> [Fan] {
        var fans = FanParser.parse(try run(["fans"]))
        guard !fans.isEmpty else { throw SMCCommandError.invalidOutput }
        if fans.contains(where: { $0.actual < 0 || $0.target < 0 }),
           let keys = try? run(["list", "-f"]) {
            fans = FanParser.fillUnavailableReadings(in: fans, from: keys)
        }
        return fans
    }

    static func cpuTemperature() -> CPUTemperatureSample? {
        guard let output = try? run(["list", "-t"]) else { return nil }
        return CPUTemperatureParser.parse(output)
    }

    static func setSpeed(percent: Int) throws -> [Fan] {
        let before = try fans()
        let targets = FanSpeedPlan.targets(for: before, percent: percent)
        for attempt in 0..<3 {
            do {
                try FanHelperClient.send("manual \(percent)")
                break
            } catch {
                // The older installed helper could read Fan 1's target before the SMC updated it.
                guard attempt < 2 && error.localizedDescription.contains("did not accept its target speed") else { throw error }
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        let after = try fans()
        guard after.count == before.count && after.allSatisfy({ !$0.isAutomatic }) else {
            throw SMCCommandError.unchanged
        }
        guard after.allSatisfy({ fan in
            guard let rpm = targets[fan.id] else { return false }
            return fan.target < 0 || abs(fan.target - rpm) <= 50
        }) else { throw SMCCommandError.unchanged }
        return after
    }

    static func automatic() throws -> [Fan] {
        let before = try fans()
        try FanHelperClient.send("automatic")
        let after = try fans()
        guard after.count == before.count && after.allSatisfy({ $0.isAutomatic }) else {
            throw SMCCommandError.unchanged
        }
        return after
    }
}

@MainActor
private final class FanStore: ObservableObject {
    @Published var fans: [Fan] = []
    @Published var cpuTemperature: CPUTemperatureSample?
    @Published var error: String?
    @Published var busy = false
    @Published var helperReady = false
    @Published var temperatureControlEnabled = UserDefaults.standard.bool(forKey: "temperatureControlEnabled")
    @Published var automaticFanPercent: Int?
    private var actionError = false
    private var pendingPercent: Int?
    private var speedWorker: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    private var temperatureController = TemperatureFanController()
    private var temperatureControllerInitialized = false
    private var handingBackToMacOS = false

    func startMonitoring() {
        guard monitorTask == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // A temperature-controlled manual target must not outlive the app.
            MainActor.assumeIsolated {
                if self?.temperatureControlEnabled == true || self?.handingBackToMacOS == true {
                    try? FanHelperClient.send("automatic")
                }
            }
        }
        monitorTask = Task {
            while !Task.isCancelled {
                await refresh()
                await updateTemperatureControl()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func enableTemperatureControl() {
        guard helperReady else { return }
        handingBackToMacOS = false
        temperatureController.reset(
            isCooling: !fans.isEmpty && fans.allSatisfy { !$0.isAutomatic },
            requestedPercent: FanTemperatureEstimator.manualPercent(for: fans).map { Int(($0 / 10).rounded()) * 10 }
        )
        temperatureControllerInitialized = true
        temperatureControlEnabled = true
        UserDefaults.standard.set(true, forKey: "temperatureControlEnabled")
        automaticFanPercent = temperatureController.requestedPercent
        Task { await updateTemperatureControl() }
    }

    func disableTemperatureControl() {
        handingBackToMacOS = true
        temperatureControlEnabled = false
        UserDefaults.standard.set(false, forKey: "temperatureControlEnabled")
        automaticFanPercent = nil
        temperatureController.reset()
        temperatureControllerInitialized = false
        Task {
            await automatic()
            handingBackToMacOS = fans.isEmpty || !fans.allSatisfy { $0.isAutomatic }
        }
    }

    func returnToMacOS() {
        handingBackToMacOS = true
        Task {
            await automatic()
            handingBackToMacOS = fans.isEmpty || !fans.allSatisfy { $0.isAutomatic }
        }
    }

    func switchTemperatureControlToManual(percent: Int) {
        handingBackToMacOS = false
        temperatureControlEnabled = false
        UserDefaults.standard.set(false, forKey: "temperatureControlEnabled")
        automaticFanPercent = nil
        temperatureController.reset()
        temperatureControllerInitialized = false
        requestSpeed(percent: percent)
    }

    private func updateTemperatureControl() async {
        guard temperatureControlEnabled, !busy, helperReady else { return }
        if !temperatureControllerInitialized, !fans.isEmpty {
            temperatureController.reset(
                isCooling: fans.allSatisfy { !$0.isAutomatic },
                requestedPercent: FanTemperatureEstimator.manualPercent(for: fans).map { Int(($0 / 10).rounded()) * 10 }
            )
            temperatureControllerInitialized = true
        }
        guard let action = temperatureController.nextAction(
            averageCelsius: cpuTemperature?.averageCelsius, at: Date()
        ) else { return }
        busy = true
        do {
            let updated = try await Task.detached { () throws -> [Fan] in
                switch action {
                case .manual(let percent): try SMCTool.setSpeed(percent: percent)
                case .automatic: try SMCTool.automatic()
                }
            }.value
            fans = updated
            temperatureController.didApply(action, at: Date())
            automaticFanPercent = temperatureController.requestedPercent
            actionError = false
            error = nil
        } catch {
            let failure = error.localizedDescription
            temperatureControlEnabled = false
            UserDefaults.standard.set(false, forKey: "temperatureControlEnabled")
            automaticFanPercent = nil
            temperatureController.reset()
            temperatureControllerInitialized = false
            handingBackToMacOS = true
            if let restored = try? await Task.detached(operation: { try SMCTool.automatic() }).value {
                fans = restored
                handingBackToMacOS = false
            }
            actionError = true
            self.error = "Temperature control stopped: \(failure)"
        }
        busy = false
    }

    func refresh() async {
        guard !busy else { return }
        do {
            let reading = try await Task.detached {
                let fans = try SMCTool.fans()
                return (fans, SMCTool.cpuTemperature())
            }.value
            fans = reading.0
            cpuTemperature = reading.1
            if !helperReady {
                helperReady = await Task.detached { FanHelperClient.isReady() }.value
            }
            if !actionError { error = nil }
        } catch {
            actionError = false
            self.error = error.localizedDescription
        }
    }

    func installHelper() async {
        busy = true
        defer { busy = false }
        do {
            try await Task.detached { try FanHelperClient.install() }.value
            helperReady = true
            actionError = false
            error = nil
        } catch {
            actionError = true
            self.error = error.localizedDescription
        }
    }

    func requestSpeed(percent: Int) {
        guard helperReady else { return }
        pendingPercent = min(100, max(0, percent))
        guard speedWorker == nil else { return }
        speedWorker = Task { await processSpeedRequests() }
    }

    private func processSpeedRequests() async {
        busy = true
        while true {
            try? await Task.sleep(for: .milliseconds(120))
            guard let percent = pendingPercent else { break }
            pendingPercent = nil
            do {
                fans = try await Task.detached { try SMCTool.setSpeed(percent: percent) }.value
                actionError = false
                error = nil
            } catch {
                actionError = true
                self.error = error.localizedDescription
                if let latest = try? await Task.detached(operation: { try SMCTool.fans() }).value { fans = latest }
                pendingPercent = nil
                break
            }
        }
        busy = false
        speedWorker = nil
    }

    func automatic() async {
        busy = true
        defer { busy = false }
        do {
            fans = try await Task.detached { try SMCTool.automatic() }.value
            actionError = false
            error = nil
        } catch {
            actionError = true
            self.error = error.localizedDescription
            if let latest = try? await Task.detached(operation: { try SMCTool.fans() }).value { fans = latest }
        }
    }
}

private struct FanRow: View {
    let fan: Fan

    private var displayName: String {
        switch fan.id {
        case 0: "Left fan"
        case 1: "Right fan"
        default: fan.name
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName).font(.headline)
            if fan.actual > 0 {
                Text("\(fan.actual) RPM")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(fan.isAutomatic ? "Automatic" : "Manual")
                .font(.caption).foregroundStyle(.secondary)
            if !fan.isAutomatic && fan.target > 0 {
                Text("Target \(fan.target) RPM")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TemperatureMetric: View {
    let label: String
    let celsius: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.1f°C", celsius))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TemperatureEstimateAnchor {
    let celsius: Double
    let fanPercent: Double
    let createdAt: Date
}

private struct FanPanel: View {
    @ObservedObject var store: FanStore
    @AppStorage("requestedPercent") private var requestedPercent = 50.0
    @State private var manualIntent: Bool?
    @State private var estimateAnchor: TemperatureEstimateAnchor?

    private var manualEnabled: Bool {
        guard !store.temperatureControlEnabled else { return false }
        return manualIntent ?? (!store.fans.isEmpty && store.fans.allSatisfy { !$0.isAutomatic })
    }

    private var estimatedCPUTemperature: ClosedRange<Int>? {
        guard let current = store.cpuTemperature?.averageCelsius else { return nil }
        let referenceCelsius: Double
        let referencePercent: Double
        if let anchor = estimateAnchor,
           Date().timeIntervalSince(anchor.createdAt) < 120 {
            referenceCelsius = anchor.celsius
            referencePercent = anchor.fanPercent
        } else {
            referenceCelsius = current
            referencePercent = FanTemperatureEstimator.manualPercent(for: store.fans) ?? 0
        }
        return FanTemperatureEstimator.range(
            selectedPercent: requestedPercent,
            referencePercent: referencePercent,
            currentCelsius: referenceCelsius,
            points: FanTemperatureEstimator.calibrationPoints
        )
    }

    private func captureEstimateAnchor() {
        if let anchor = estimateAnchor,
           Date().timeIntervalSince(anchor.createdAt) < 120 { return }
        guard let temperature = store.cpuTemperature?.averageCelsius else { return }
        estimateAnchor = TemperatureEstimateAnchor(
            celsius: temperature,
            fanPercent: FanTemperatureEstimator.manualPercent(for: store.fans) ?? 0,
            createdAt: Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "fanblades.fill").foregroundStyle(.tint)
                Text("Fan Control").font(.title3.weight(.semibold))
                Spacer()
            }
            if store.fans.isEmpty && store.error == nil {
                ProgressView("Reading fans…")
            }
            if !store.fans.isEmpty {
                Text("Fans")
                    .font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(store.fans) { fan in
                    FanRow(fan: fan)
                }
            }
            if let cpuTemperature = store.cpuTemperature {
                Text("CPU core temperatures")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    TemperatureMetric(label: "Average", celsius: cpuTemperature.averageCelsius)
                    TemperatureMetric(label: "Hottest core", celsius: cpuTemperature.peakCelsius)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Temperature guide")
                        .font(.subheadline.weight(.semibold))
                    Text("Temperatures vary with workload; warmer readings during heavy work are normal. This Mac measured about 40–50°C during light use and up to 67°C in a four-core test. These are reference readings, not safety limits.")
                    Text("If it stays unusually hot during light use, check airflow and Activity Monitor.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            if !store.helperReady {
                Button("Enable control") { Task { await store.installHelper() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.busy)
                Text("One administrator approval installs the fan helper. Speed changes will not ask again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.fans.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Chosen speed for both fans").font(.headline)
                        Spacer()
                        Text("\(Int(requestedPercent))%")
                            .font(.headline).monospacedDigit()
                    }
                    Slider(value: $requestedPercent, in: 0...100, step: 10)
                        .accessibilityLabel("Both fans speed")
                        .disabled(store.temperatureControlEnabled)
                    if !store.temperatureControlEnabled, let estimate = estimatedCPUTemperature {
                        HStack {
                            Text("Expected CPU average")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(estimate.lowerBound)–\(estimate.upperBound)°C")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        Text("Approximate after the fans settle, if CPU load stays similar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(manualEnabled
                         ? "Changes apply in 10% steps as you move the slider."
                         : store.temperatureControlEnabled
                            ? "Temperature control is active. Use chosen speed to switch to manual."
                            : "Choose a speed in 10% steps, then use chosen speed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fan control")
                        Text(store.temperatureControlEnabled
                             ? "Adjusting from CPU temperature"
                             : manualEnabled ? "Using chosen speed" : "macOS controls both fans")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        let enabled = !manualEnabled
                        manualIntent = enabled
                        if enabled {
                            estimateAnchor = nil
                            captureEstimateAnchor()
                            if store.temperatureControlEnabled {
                                store.switchTemperatureControlToManual(percent: Int(requestedPercent))
                            } else {
                                store.requestSpeed(percent: Int(requestedPercent))
                            }
                        } else {
                            estimateAnchor = nil
                            store.returnToMacOS()
                        }
                    } label: {
                        Text(manualEnabled ? "Return to macOS" : "Use chosen speed")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(manualEnabled ? .primary : .white)
                            .frame(minWidth: 64)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(manualEnabled ? Color.gray.opacity(0.3) : Color.accentColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.busy || !store.helperReady)
                    .accessibilityLabel(manualEnabled ? "Return fan control to macOS" : "Use chosen speed for both fans")
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Temperature control")
                                .font(.subheadline.weight(.semibold))
                            Text(store.temperatureControlEnabled
                                 ? (store.automaticFanPercent.map { "Cooling both fans at \($0)%" }
                                    ?? "Watching CPU temperature")
                                 : "Off")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(store.temperatureControlEnabled ? "Stop" : "Use temperature") {
                            manualIntent = false
                            if store.temperatureControlEnabled {
                                store.disableTemperatureControl()
                            } else {
                                store.enableTemperatureControl()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.busy || !store.helperReady ||
                                  (!store.temperatureControlEnabled && store.cpuTemperature == nil))
                    }
                    Text("Starts cooling at 40°C, speeds up toward 45°C, and returns control to macOS below 37°C. The 45°C goal is best effort.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Uses the installed Stats SMC tool")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 330)
        .onChange(of: requestedPercent) { value in
            captureEstimateAnchor()
            if manualEnabled && !store.temperatureControlEnabled && store.helperReady {
                store.requestSpeed(percent: Int(value))
            }
        }
        .onChange(of: store.busy) { isBusy in
            if !isBusy { manualIntent = nil }
        }
        .onAppear { store.startMonitoring() }
    }
}

@main
struct FanControlApp: App {
    @StateObject private var store = FanStore()

    var body: some Scene {
        WindowGroup("Fan Control") {
            FanPanel(store: store)
        }
        .defaultSize(width: 370, height: 900)

        MenuBarExtra("Fan Control", systemImage: "fanblades") {
            FanPanel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

# Fan Control

A small SwiftUI macOS app for reading CPU temperatures and controlling two fans together. It uses the `smc` tool from an installed copy of Stats. The app does not modify Stats.

**Hardware support:** Built and tested on a MacBook Pro with M5 Pro and two fans. Fan limits come from the Mac, but the CPU temperature sensor keys and temperature estimates are specific to this model. Other Macs may need different sensor keys in `Sources/CPUTemperatureParser.swift`. This is source code for building locally, not a signed release.

## Build

Requirements: Apple Silicon Mac, macOS 13 or newer, Xcode command line tools, and Stats installed at `/Applications/Stats.app`.

```sh
./build.sh
open "build/Fan Control.app"
```

The build copies the installed Stats `smc` executable into the app bundle. The repository does not contain that binary; its MIT license is included at `Resources/LICENSE.stats`. The app itself is MIT licensed in [LICENSE](LICENSE).

## Controls

- The app reads both fans and CPU core temperatures about once per second. If Stats does not provide a valid RPM or temperature, it hides the value rather than showing a false zero.
- **Use chosen speed** applies the single slider to both fans. The slider moves in 10% steps between each fan's reported minimum and maximum RPM. Moving it updates both fans while manual mode is active. **Return to macOS** gives both fans back to the system; it does not stop them.
- **Use temperature** watches the CPU core average while the app runs. At 40°C it requests 50% fan speed, increasing in 10% steps to 100% by 45°C. It reduces the requested speed as the CPU cools and returns control to macOS after three readings below 37°C. Readings are smoothed and speed changes are spaced by at least eight seconds. **Stop** returns control to macOS. This mode resumes when the app next opens.
- The slider also shows an approximate CPU temperature range for its selected setting, based on a four-core test on the original M5 Pro Mac and the current reading. It assumes CPU activity stays similar. It is an estimate, not a guarantee.

**45°C is a cooling preference, not an Apple safety limit.** During the four-core test this Mac stayed above 45°C even with both fans at full speed. Workload and room temperature can change the result. See [Apple's temperature guidance](https://support.apple.com/en-us/102336) and [fan guidance](https://support.apple.com/en-us/101576).

## Privileged helper

The first time you press **Enable control**, macOS asks for administrator approval to install a small root helper. Later fan changes use its local Unix socket and do not prompt again. The helper accepts only the installing user's UID, and only `manual <percent>`, `automatic`, and `ping` commands. Its installer and source are in `Resources/install-helper.sh` and `Sources/FanHelper.swift`.

Temperature mode returns control to macOS on a missing reading, a failed fan command, or a normal app quit. If you are using the manual slider, press **Return to macOS** before quitting; manual targets can remain active after the app closes. If the app is forcibly terminated or crashes during temperature mode, its normal-quit handoff cannot run, so reopen the app and press **Stop** to restore macOS control. Avoid running two fan controllers at the same time.

## Tests

```sh
swiftc Sources/FanParser.swift Tests/ParserTests.swift -o /tmp/fan-parser-tests && /tmp/fan-parser-tests
swiftc Sources/FanParser.swift Sources/FanSpeedPlan.swift Tests/SpeedPlanTests.swift -o /tmp/fan-speed-tests && /tmp/fan-speed-tests
swiftc Sources/FanSocket.swift Tests/SocketTests.swift -o /tmp/fan-socket-tests && /tmp/fan-socket-tests
swiftc Sources/CPUTemperatureParser.swift Tests/CPUTemperatureParserTests.swift -o /tmp/fan-cpu-temp-tests && /tmp/fan-cpu-temp-tests
swiftc Sources/FanParser.swift Sources/FanTemperatureEstimator.swift Tests/FanTemperatureEstimatorTests.swift -o /tmp/fan-temperature-estimator-tests && /tmp/fan-temperature-estimator-tests
swiftc Sources/TemperatureFanController.swift Tests/TemperatureFanControllerTests.swift -o /tmp/fan-temperature-controller-tests && /tmp/fan-temperature-controller-tests
```

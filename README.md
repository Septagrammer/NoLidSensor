# 🌙 NoLidSensor

A macOS menu bar app for MacBooks that no longer sleep when the lid closes because of a broken lid sensor. It uses the built-in camera to check for darkness after a period without keyboard or mouse input.

macOS 13+ · English / Українська / Русский / Čeština

## How it works

If there is no input between two checks and the camera sees darkness, the app asks whether to sleep. Without a response, it requests sleep after **60 seconds**. Keyboard or mouse activity cancels automatic sleep.

You can sleep now, skip the check, or pause for an hour. The menu lets you adjust the check interval (default: 3 minutes), darkness threshold and test the camera without sleeping.

Frames stay local and are never saved. There are no network requests. The camera runs briefly for each eligible check; battery impact has not been measured.

## Build and run

Requires a Swift 5.9+ toolchain, such as Xcode with command line tools configured.

```sh
git clone https://github.com/Septagrammer/NoLidSensor.git
cd NoLidSensor
bash build-app.sh
open dist/NoLidSensor.app
```

Open the moon menu, enable monitoring and allow camera access. Use the camera test to adjust the darkness threshold. Monitoring starts **off** on every launch.

The app builds for your Mac’s architecture with an ad hoc signature. It is not notarized.

## Limitations

- A dark room or covered camera can look like a closed lid.
- Videos, downloads and other background work do not count as keyboard or mouse activity. Pause monitoring when needed.
- Only the built-in camera is supported. Camera errors do not trigger sleep.
- This does not repair the sensor or restore waking when the lid opens.
- Camera, sleep and wake behavior still need verification on your Mac.

Run policy tests with `swift test`.

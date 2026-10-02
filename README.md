<div align="center">

# 🌙 NoLidSensor

### Broken lid sensor? Give your Mac another way to fall asleep.

A small macOS menu bar app that checks for **darkness + inactivity**, then offers to put your Mac to sleep.

**macOS 13+ · Swift · English / Русский / Čeština**

</div>

---

## The problem

When a MacBook’s lid sensor stops working, closing the lid may no longer put the computer to sleep. It can stay awake when you expect it to be sleeping.

NoLidSensor was built as a practical workaround: the built-in camera checks whether it is dark, while input inactivity helps determine whether you have stepped away. It does not repair or read the lid sensor, and darkness is only an approximation of a closed lid.

## How it works

1. **Wait for inactivity.** At each scheduled check, the app looks for keyboard or mouse input since the previous check. The first check establishes the starting point.
2. **Briefly check the light.** If there was no input throughout that interval, the built-in camera takes a short brightness sample.
3. **Ask before sleeping.** If it is dark, a prompt appears. With no response, the Mac receives a sleep request after **60 seconds**.

Choose **Sleep**, **Not now**, or **Do not disturb for an hour**. New input during the prompt cancels automatic sleep. New input during a camera check prevents that check from triggering the prompt.

## Small app, simple controls

Everything lives under the moon icon in the menu bar:

| Control | What it does |
| --- | --- |
| Enable monitoring | Start or stop automatic checks |
| Check interval | Choose 1–30 minutes; default: 3 minutes |
| Darkness threshold | Tune brightness sensitivity; default: 3% |
| Do not disturb | Pause for an hour, or resume early |
| Test camera | Measure brightness without putting the Mac to sleep |

Monitoring starts **off** each time you launch the app. A saved pause survives a restart. The interface follows your system language, with English, Russian and Czech translations.

## Build and run

Requires macOS 13 or newer and an installed Swift toolchain supporting Swift tools 5.9 or later, such as Xcode with its command line tools configured.

```sh
git clone https://github.com/Septagrammer/NoLidSensor.git
cd NoLidSensor
bash build-app.sh
open dist/NoLidSensor.app
```

Open the moon menu, enable monitoring and allow camera access. Use the camera test to find a threshold that works in your room. Brightness is a percentage of pixel values, **not lux**; camera auto-exposure affects it.

The build targets your current Mac’s architecture. It uses a local ad hoc signature and is not notarized. There is no automatic launch at login.

## Privacy and energy use

- Camera frames are processed locally and are **never saved**.
- No network requests, analytics or cloud service.
- The camera only runs briefly after an inactive interval; it is not continuously recording.
- Between checks, a one-shot timer waits for the next event. One-second updates only run while the sleep prompt is visible.
- Actual battery impact has not been measured.

## Know the limits

> This is a workaround for sleeping, not a replacement for functioning lid hardware.

- A dark room or covered webcam can look like a closed lid.
- No keyboard or mouse input does **not** mean your Mac has finished playing video, downloading files or doing other work. Pause monitoring when needed.
- Camera failures or missing frames do not count as darkness. Only the built-in camera is used; external and Continuity cameras are not fallbacks.
- The app cannot restore wake-on-lid-open behavior. Test how you will wake your Mac before relying on it.
- A successful sleep request means macOS accepted the request, not that sleep has been independently confirmed.
- Verify the camera, prompt, sleep and wake behavior on your own Mac before relying on this workaround. Hardware scenarios have not yet been fully validated.

## Development

```sh
swift test
bash build-app.sh
```

The policy tests cover inactivity, stale activity during capture, invalid brightness samples, pause behavior and timer scheduling.

The internal bundle identifier remains `local.pavlo.DarkSleep` to preserve settings from the app’s original name.

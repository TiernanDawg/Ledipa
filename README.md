# Morg’s LED — V2.0 — BLEDOM LED Controller

A native SwiftUI iPhone app for controlling compatible BLEDOM / ELK-BLEDOM Bluetooth LE RGB strips directly, without DuoCo Strip. Current app version: 2.0.0 (build 2).

## Features
- Refined dark Liquid Glass-inspired SwiftUI interface with ambient lighting and layered translucent panels
- Native CoreBluetooth scanning, connection, reconnect, and queued writes that respect CoreBluetooth back-pressure
- Scans for known ELK-BLEDOM service/characteristic combinations (`FFF0/FFF3`, `FFE0/FFE1`, `FFE5/FFE9`)
- Power toggle, full color picker, live HEX/RGB readout, and individual RGB sliders
- Brightness slider with quick percentage controls
- Six one-tap solid-color atmospheres
- Locally saved and removable named color presets
- GitHub Actions workflow that builds an unsigned iOS IPA artifact

## Compatibility note
The controller appeared in DuoCo Strip as `BLEDOM`, with identifier `6CE2B7E5-0232-3C40-A123-6B378B8B5F01`. That does not reveal its Bluetooth GATT services. Morg’s LED supports common ELK-BLEDOM characteristic and command variants, but compatibility must still be confirmed against the physical strip. The app animates by sending whole-strip RGB and brightness updates; it does not claim hardware-native per-pixel effects. The exact controller command set still needs confirmation against the physical strip, so unsupported commands are not guessed.

## Build an IPA
1. Open **Actions** and select the latest **Build Morg’s LED IPA** run.
2. Wait for all build steps to complete successfully.
3. Download the `Morgs-LED-unsigned-ipa` artifact.
4. Sign/sideload it with your existing method (for example, SideStore). The workflow does not sign the app with an Apple developer identity.

The IPA is unsigned for personal sideloading. LED control is performed directly over Bluetooth; no DuoCo Strip app, account, or cloud service is used by Morg’s LED.


## V2.0 implementation notes

- Scene transitions use eased intermediate RGB values and brightness modulation. The strip changes as a whole; it cannot independently animate segments unless its controller exposes that capability.
- Microphone reactivity is processed on-device. iOS microphone permission must be granted, and the Music screen must remain active while listening.
- Timers and fades require the app to remain open and Bluetooth connected. iOS may suspend the app in the background; scheduled BLE changes are not guaranteed after the app is closed or suspended.
- The current generic BLE profile is best-effort compatibility, not verified Matter or BLE Mesh support. Matter, LiDAR room mapping, ambient-light sensor readings, temperature-channel control, and LED health diagnostics are not implemented for this generic strip.
- Presets and preferences are stored locally using app preferences. This is not a Secure Enclave-backed encrypted vault.

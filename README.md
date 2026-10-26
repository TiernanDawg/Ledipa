# Morg’s LED — BLEDOM LED Controller

A native SwiftUI iPhone app for controlling compatible BLEDOM / ELK-BLEDOM Bluetooth LE RGB strips directly, without DuoCo Strip.

## Features
- Refined dark Liquid Glass-inspired SwiftUI interface with ambient lighting and layered translucent panels
- Native CoreBluetooth scanning and connection
- Scans for known ELK-BLEDOM service/characteristic combinations (`FFF0/FFF3`, `FFE0/FFE1`, `FFE5/FFE9`)
- Power toggle, full color picker, live HEX/RGB readout, and individual RGB sliders
- Brightness slider with quick percentage controls
- Six one-tap solid-color atmospheres
- Locally saved and removable named color presets
- GitHub Actions workflow that builds an unsigned iOS IPA artifact

## Compatibility note
The controller appeared in DuoCo Strip as `BLEDOM`, with identifier `6CE2B7E5-0232-3C40-A123-6B378B8B5F01`. That does not reveal its Bluetooth GATT services. Morg’s LED supports common ELK-BLEDOM characteristic and command variants, but compatibility must still be confirmed against the physical strip. Animated effects are not advertised because the exact controller command set has not been verified.

## Build an IPA
1. Open **Actions** and select the latest **Build Morg’s LED IPA** run.
2. Wait for all build steps to complete successfully.
3. Download the `Morgs-LED-unsigned-ipa` artifact.
4. Sign/sideload it with your existing method (for example, SideStore). The workflow does not sign the app with an Apple developer identity.

The IPA is unsigned for personal sideloading. LED control is performed directly over Bluetooth; no DuoCo Strip app, account, or cloud service is used by Morg’s LED.

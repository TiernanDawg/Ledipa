# Luma — BLEDOM LED Controller

A native SwiftUI iPhone app for controlling compatible BLEDOM / ELK-BLEDOM Bluetooth LE RGB strips directly, without DuoCo Strip.

## Current scope
- Native CoreBluetooth scanning and connection
- Scans for known ELK-BLEDOM service/characteristic combinations (`FFF0/FFF3`, `FFE0/FFE1`, `FFE5/FFE9`)
- Power, RGB color, brightness, quick colors, and locally saved color presets
- Glass-style SwiftUI interface using system materials
- GitHub Actions workflow to build an unsigned iOS IPA artifact

## Important compatibility note
Your controller appears in DuoCo Strip as `BLEDOM`, UUID shown as `6CE2B7E5-0232-3C40-A123-6B378B8B5F01`. This is a promising target, but the screenshot does not expose its GATT services. The app discovers characteristics and supports common ELK-BLEDOM frame formats; if the controller uses a different protocol variant, we will need a BLE diagnostic capture and adjust the command frames. Hardware effects are not included until the exact controller command set is verified.

## Build an IPA
1. Open **Actions** and enable workflows if GitHub prompts you.
2. Run **Build Luma IPA** (or push to `main`).
3. Download the `Luma-unsigned-ipa` artifact from the completed workflow run.
4. Sideload/sign the IPA with your existing signing method (for example, SideStore). GitHub Actions cannot sign it for your Apple account without signing credentials.

The resulting IPA is unsigned, as expected for a personal sideloading workflow. No third-party LED app or cloud service is used by Luma.

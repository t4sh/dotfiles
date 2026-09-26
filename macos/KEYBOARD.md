# Keyboard preference coverage

## macOS 27 readiness

Preference capture accepts macOS 15, 26, and provisionally 27. Version 27 uses
the existing 26+ Control Center key mapping; this is a compatibility assumption,
covered by fixtures rather than a claim of native macOS 27 verification.
Unknown major versions remain blocked. Missing required preferences, invalid
values, failed security checks, and declined drift still stop capture.

After upgrading, run `make macos-check SKIP_FINDER_VIEWS=1` for read-back first.
Inspect any failures before adopting drift. Verify keyboard/input settings,
Services, screenshot shortcuts, and mouse/trackpad gestures in System Settings.
Check Text Replacements export against the visible entries. Live macOS 27
capture and restore remain pending; avoid a blanket restore to validate them.

## Settings

| Setting | Backup and restore |
| --- | --- |
| Key repeat rate | `NSGlobalDomain/KeyRepeat` in the reviewed macOS preference snapshot; current value 2 (Fast) |
| Delay until repeat | `NSGlobalDomain/InitialKeyRepeat`; current value 15 (Short) |
| Keyboard navigation | `NSGlobalDomain/AppleKeyboardUIMode`; current value 3 (On) |
| Globe key action | `AppleFnUsageType` in the existing `com.apple.HIToolbox` snapshot; current value 1 (Change Input Source) |
| Screenshot shortcuts | Existing `com.apple.symbolichotkeys` snapshot |
| Services and Quick Actions | `pbs` snapshot |
| Text Replacements | Private export; see [Text Replacements](TEXT-REPLACEMENTS.md) |
| Trackpad tapping, dragging, secondary click, and gestures | Separate `macos/trackpad.plist` and `macos/bluetooth-trackpad.plist` snapshots |
| Multitouch mouse buttons, scrolling, and gestures | Separate `macos/mouse.plist` and `macos/bluetooth-mouse.plist` snapshots |

`make backup` checks repeat rate, delay, and keyboard navigation and prompts
to adopt changed values through the existing macOS preference review.
`make macos` applies the saved values after the setup defaults.
Input Sources and the other whole-domain snapshots capture automatically.

Mouse/trackpad snapshots capture the keys present in each device preference
domain, without per-setting prompts. They do not capture separate global or
ByHost preferences such as tracking speed, natural scrolling, or tapBehavior.
`make restore-apps` imports available snapshots; log out/in and verify each
device's gestures in System Settings afterward. `make macos` still applies its
hard-coded mouse/trackpad defaults, so restore these snapshots after that step
when recovering personal device settings. Hardware behavior after import has
not been verified on a replacement Mac or macOS 27.

## Manual backlight restore

No portable preference capture/restore has been verified for these hardware
controls. On a replacement Mac with a backlit keyboard, use System Settings →
Keyboard to restore the settings shown on 2026-09-15:

- Adjust keyboard brightness in low light: On.
- Keyboard brightness: approximately 56%; adjust for the current lighting.
- Turn keyboard backlight off after inactivity: After 1 Minute.

These three settings are documented only, not captured by `make backup`.
Automatic brightness can change the effective brightness after manual adjustment.

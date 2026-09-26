# Keyboard preference coverage

## macOS 27 readiness

The public policy reader uses the existing 26+ Control Center key mapping for
macOS 27. This is a compatibility assumption covered by fixtures rather than
a claim of native macOS 27 verification. Public backup keeps the policy check
strict and offers no personal preference capture or interactive drift adoption.

After upgrading, run `make macos-check SKIP_FINDER_VIEWS=1` for read-back first.
Inspect any failures before changing settings. Verify keyboard/input settings,
Services, screenshot shortcuts, and mouse/trackpad gestures in System Settings.
Check Text Replacements export against the visible entries. Native macOS 27
verification remains pending; avoid a blanket restore to validate these settings.

## Settings

| Setting | Backup and restore |
| --- | --- |
| Key repeat rate | Managed policy: `NSGlobalDomain/KeyRepeat`, value 2 (Fast) |
| Delay until repeat | Managed policy: `NSGlobalDomain/InitialKeyRepeat`, value 15 (Short) |
| Keyboard navigation | Managed policy: `NSGlobalDomain/AppleKeyboardUIMode`, value 3 (On) |
| Globe key action | `AppleFnUsageType` in the existing `com.apple.HIToolbox` snapshot; current value 1 (Change Input Source) |
| Screenshot shortcuts | Existing `com.apple.symbolichotkeys` snapshot |
| Services and Quick Actions | Manifest only; no published snapshot or public capture |
| Text Replacements | Private export; see [Text Replacements](TEXT-REPLACEMENTS.md) |
| Trackpad tapping, dragging, secondary click, and gestures | Manifest only; no published snapshots or public capture |
| Multitouch mouse buttons, scrolling, and gestures | Manifest only; no published snapshots or public capture |

`make backup` checks repeat rate, delay, and keyboard navigation against the
managed policy and stops on drift. `make macos` applies the setup defaults.
Input Sources and screenshot shortcuts retain their existing snapshot capture.

Services and mouse/trackpad domains require separate privacy review before
snapshots can be published. Public backup skips them. `make restore-apps`
imports available snapshots only; restore personal device choices manually
in System Settings after `make macos` applies its mouse/trackpad defaults.
Hardware behavior has not been verified on a replacement Mac or macOS 27.

## Manual backlight restore

No portable preference capture/restore has been verified for these hardware
controls. On a replacement Mac with a backlit keyboard, use System Settings →
Keyboard to restore the settings shown on 2026-09-15:

- Adjust keyboard brightness in low light: On.
- Keyboard brightness: approximately 56%; adjust for the current lighting.
- Turn keyboard backlight off after inactivity: After 1 Minute.

These three settings are documented only, not captured by `make backup`.
Automatic brightness can change the effective brightness after manual adjustment.

# Services and device policy fixtures

These minimal plists are synthetic policy examples. They contain no device
identifiers, hardware inventory, account state, captured service list or real
machine snapshot. They are separate from `apps/` and are not installed, captured
or restored by any Make target.

| Fixture | Preference domain | Intent |
| --- | --- | --- |
| [services-policy.plist](services-policy.plist) | `pbs` | Enable Terminal's built-in New Terminal at Folder in the context and Services menus |
| [trackpad-policy.plist](trackpad-policy.plist) | `com.apple.AppleMultitouchTrackpad` or `com.apple.driver.AppleBluetoothMultitouch.trackpad` | Tap to click, secondary click and three-finger dragging |

The Services entry uses the public built-in Terminal service identifier and
explicit menu presentation flags. It is one example entry, not a complete
`NSServicesStatus` dictionary. Replacing that whole dictionary would discard your
other service choices. Review the equivalent option in **System Settings →
Keyboard → Keyboard Shortcuts → Services** and adjust it there.

For a supported trackpad, review **System Settings → Trackpad** for tap and
secondary click, and **Accessibility → Pointer Control → Trackpad Options** for
three-finger dragging. Choose the domain for your device; do not import a whole
preference domain or apply both blindly. Settings names and preference keys can
change across macOS versions or devices. These keys follow this repository's
existing [macOS policy](../../macos/defaults.sh); plist validity is not evidence
that your installed OS consumes them. A real device/GUI check remains necessary.

Offline inspection on a Mac:

```sh
plutil -lint examples/macos/services-policy.plist examples/macos/trackpad-policy.plist
plutil -p examples/macos/services-policy.plist
plutil -p examples/macos/trackpad-policy.plist
```

No `defaults import`, preference writes or service execution is needed to inspect
the examples. To undo a manual change, restore the previous value in System
Settings; retain your existing preference backup before applying policy.

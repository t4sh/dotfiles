# IINA backup and restore

The portable `iina.plist` omits recent media paths and `screenShotFolder`.
`make restore-apps` imports the preferences and sets IINA's Screengrabs folder
from the macOS screenshot policy: `DOTFILES_CAPTURE_DIR` when set, an optional
local saved location, or `~/Desktop/Screengrabs` on a fresh checkout.
`make backup` and `make apps-drift` verify that IINA uses the same location
before sanitizing its path. The destination must exist or be mounted before
using screengrabs. Personal macOS snapshots are not shipped in this repository.

File associations are separate. After choosing default media apps, run
`make capture-default-apps` to update `config/duti`. Use `make default-apps`
and `make default-apps-check` to apply and check the policy on another Mac.

Plugin packages and user data under
`~/Library/Application Support/com.colliderli.iina/plugins/` are not included.
Install and verify any plugins separately. Playback resume files under
`watch_later/` and screengrab images are also excluded; back up images separately.
Store reviewed exports containing plugin credentials or private scripts under
`~/.secrets/apps/iina/` and run `make secrets-backup`.

# Node and package-manager contract

## Stable binaries

- For `node` or `npx`—including MCP, skills, browser automation, and scripts—use `~/.local/bin/node-stable` and `~/.local/bin/npx-stable`, not nvm directly.

## Package managers

- **Detect before installing.** Use the manager selected by `packageManager` or the root `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, or `package-lock.json`; never switch unasked.
- **Keep one lockfile.** Remove a conflicting lockfile generated as a side effect before staging.
- **Respect workspace protocols.** Keep cross-package dependencies such as `"workspace:*"`; do not pin them.

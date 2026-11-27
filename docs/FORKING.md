# Set up your fork

Personalize your fork before running `install.sh`, `make all`, or the Windows
bootstrap. Linking installs the fork's Git settings, including author identity
and signing configuration, as your user configuration.

## 1. Clone and choose your policy

Create a fork on GitHub, replace `YOUR_ACCOUNT` below, then clone your fork:

```sh
git clone https://github.com/YOUR_ACCOUNT/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

Review `Brewfile`, `symlinks.tsv`, `apps.tsv`, the Dock, and macOS defaults before
installation. On Windows also review `config/windows-packages.tsv`,
`config/windows-links.tsv`, and [WINDOWS.md](../WINDOWS.md). Remove packages,
links, and settings you do not want to adopt.

## 2. Set your Git identity before linking

Run these from the fork checkout, replacing the sample values. Copy your actual
noreply address from GitHub Settings → Emails; its format can vary by account.
These commands work in a POSIX shell or PowerShell:

```sh
git config --file git/gitconfig user.name "Your Name"
git config --file git/gitconfig user.email "YOUR_NOREPLY_ADDRESS"
git config --local user.name "Your Name"
git config --local user.email "YOUR_NOREPLY_ADDRESS"
```

The file settings become your global defaults after linking. The local settings
apply to this checkout immediately, before bootstrap. Review existing global Git
settings before replacing them. After linking, `git config --global` may write
through the managed link into your fork, so review resulting diffs before commits.

The upstream author's identity and public verification key are intentional;
see [Public verification keys](PUBLIC-KEYS.md). Public projections also record
published identity choices in `PRIVACY.md`. If you publish your own identity or
key in your fork, update that public baseline to describe your choices. Do not
publish a personal email address merely because Git accepts it.

## 3. Choose your signing key

The fork enables SSH signing for commits and tags. Use your own key; the
upstream public key only verifies upstream signatures. Git 2.34 or newer supports
SSH signature verification. See [GitHub's SSH signing setup](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key).

The default layout expects your restored key pair at
`~/.secrets/ssh/github_ed25519` and `~/.secrets/ssh/github_ed25519.pub`.
Mac linking exposes them at `~/.ssh/github_ed25519` and its `.pub` companion.
On Windows, follow the SSH prerequisites in [WINDOWS.md](../WINDOWS.md) and
`dot ssh-setup`; Windows SSH setup verifies readiness rather than creating keys.

If you already have a different signing key, update the source configuration
and this checkout to point at its public-key file:

```sh
git config --file git/gitconfig gpg.format ssh
git config --file git/gitconfig user.signingkey "~/.ssh/github_ed25519.pub"
git config --file git/gitconfig commit.gpgsign true
git config --file git/gitconfig tag.gpgsign true
git config --local gpg.format ssh
git config --local user.signingkey "~/.ssh/github_ed25519.pub"
git config --local commit.gpgsign true
git config --local tag.gpgsign true
```

Replace both public-key paths if you use another filename. Load the matching
private key into your SSH agent or use your existing signing setup. Git can use
the public-key path to select a private key held by the agent.

Add a line for your signer to `ssh/allowed_signers`: your chosen commit email,
a space, then the key type and public-key data from your `.pub` file. Keep the
upstream line if you want to verify upstream signatures. Review all identity
information and public-key comments before publishing the fork. A signer entry
contains public material only; never paste private-key contents.

To have GitHub display verified SSH signatures, register your public key as a
**Signing key** in GitHub Settings → SSH and GPG keys. SSH authentication and
signature verification are separate registrations; a key used for both needs
both roles. See [GitHub's public-key setup](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account).

## 4. Prepare your local SSH configuration

Start from [ssh/config.example](../ssh/config.example). It contains a GitHub
entry and a reserved example server. Edit a local copy or merge the entries into
your existing configuration. The Mac manifest expects the real configuration
at `~/.secrets/ssh/config` and links it to `~/.ssh/config`; the Windows readiness
check expects `~/.ssh/config`. Preserve any existing file or linked target when
adapting it. This example is documentation and is not installed automatically.

Restore existing keys first. On Mac, `make ssh-setup` verifies and registers an
existing vault-backed GitHub key; `scripts/ssh-setup.sh --generate` is an explicit
new-key workflow. Review that workflow before choosing it. Keep real SSH configs,
private keys, and `known_hosts` outside Git, using the documented vault workflow.

Inspect the example without connecting to a server:

```sh
ssh -G -F ssh/config.example github.com
ssh -G -F ssh/config.example example-server
```

On Windows, use the same arguments with the Windows OpenSSH `ssh.exe`. These
checks show resolved settings; they do not prove authentication, host trust,
agent availability, or signing readiness. For your first actual connection,
compare the server's fingerprint with a trusted source; GitHub publishes its
[SSH fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

## 5. Install and verify your choices

Continue with the [Mac setup](../README.md) or
[Windows setup](../WINDOWS.md). Before your first commit, inspect the
actual author, committer, and signing settings from this checkout:

```sh
git var GIT_AUTHOR_IDENT
git var GIT_COMMITTER_IDENT
git config --show-origin --get user.signingkey
git config --show-origin --get commit.gpgsign
```

Make your next intended commit only after these values are correct, then use
`git log -1 --show-signature` to verify it against your configured signers.
Run the platform's doctor/verification commands after bootstrap. Native setup,
server authentication, and an actual signed commit remain checks on your own
machine; the example's offline check cannot establish them.

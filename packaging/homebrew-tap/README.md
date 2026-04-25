# hisgarden/homebrew-tap

Homebrew tap for personal builds of [VSCodium](https://github.com/hisgarden/vscodium) (the `hisgarden` fork).

## Install

```bash
brew tap hisgarden/tap
brew install --cask vscodium          # stable
brew install --cask vscodium-insiders # insiders
```

## Upgrade

```bash
brew update
brew upgrade --cask vscodium
```

## Uninstall (with cleanup)

```bash
brew uninstall --cask --zap vscodium
```

## How releases land here

1. `hisgarden/vscodium` publishes a signed + notarized release via `publish-stable-macos.yml` (or the insider variant).
2. That workflow ends by dispatching a `release-published` event to this tap.
3. `.github/workflows/update-cask.yml` here picks up the event, fetches the `.sha256` files from the release, rewrites `Casks/vscodium.rb` (or `vscodium-insiders.rb`) with the new version + SHA256 per arch, and pushes a commit.

See `packaging/homebrew-tap/` in the VSCodium fork for the starter kit that seeded this tap.

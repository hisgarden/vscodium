# Brew Tap Setup — hisgarden fork

End-to-end flow to get `brew install --cask hisgarden/tap/vscodium` working with signed + notarized builds from `hisgarden/vscodium`.

## One-time setup

### 1. Create the tap repository

The tap repo **must** be named `hisgarden/homebrew-tap` — Homebrew's `brew tap <user>/<short>` maps `hisgarden/tap` to `github.com/hisgarden/homebrew-tap`.

```bash
gh repo create hisgarden/homebrew-tap --public \
  --description "Homebrew tap for hisgarden VSCodium fork" \
  --confirm

# Seed it with this starter kit
cd /tmp && git clone git@github.com:hisgarden/homebrew-tap.git
cp -r <this-vscodium-fork>/packaging/homebrew-tap/* /tmp/homebrew-tap/
cd /tmp/homebrew-tap
git add -A
git commit -m "feat: initial tap with vscodium + vscodium-insiders casks"
git push
```

### 2. Create the versions repository

`update_version.sh` in the VSCodium build expects a repo at `hisgarden/versions` to push metadata to.

```bash
gh repo create hisgarden/versions --public \
  --description "Version metadata for hisgarden VSCodium builds" \
  --confirm
```

### 3. Load Apple codesign secrets into the publish environment

Use the helper script `packaging/homebrew-tap/load-github-secrets.sh` — it reads from your existing Keychain (QuickRecorder-style layout: service `hisgarden`, accounts `appleid` + `notarize`) and uploads everything to GitHub Actions in one pass.

**Prereq:** export your Developer ID Application certificate to `.p12`:

```
Keychain Access.app → "Developer ID Application: <Name> (<TEAM_ID>)"
  → right-click → Export...
  → File Format: Personal Information Exchange (.p12)
  → set an export password (you'll enter it once more below)
```

**Then:**

```bash
./packaging/homebrew-tap/load-github-secrets.sh /path/to/DeveloperID.p12
```

The script will prompt for:
- Apple ID (defaults to Keychain `appleid` item or git config email)
- Team ID (defaults to `NSDC3EDS2G` — your team from QuickRecorder's `project.yml`)
- App-specific password (pulled from Keychain `notarize` item, or prompted if missing)
- `.p12` export password (the one you just set)
- Optional `STRONGER_GITHUB_TOKEN` and `TAP_DISPATCH_TOKEN` (blank to skip)

It uploads these secrets to `hisgarden/vscodium` → Settings → Environments → `publish`:

| Secret | Source |
|---|---|
| `CERTIFICATE_OSX_NEW_P12_DATA` | base64 of your `.p12` |
| `CERTIFICATE_OSX_NEW_P12_PASSWORD` | the `.p12` export password |
| `CERTIFICATE_OSX_NEW_ID` | Apple ID email |
| `CERTIFICATE_OSX_NEW_APP_PASSWORD` | app-specific password from Keychain `hisgarden/notarize` |
| `CERTIFICATE_OSX_NEW_TEAM_ID` | 10-char Apple team ID |
| `STRONGER_GITHUB_TOKEN` | PAT with `repo` scope, to push to `hisgarden/versions` |
| `TAP_DISPATCH_TOKEN` | PAT with `repo` scope, to dispatch to `hisgarden/homebrew-tap` (step 5) |

Verify at: https://github.com/hisgarden/vscodium/settings/environments/publish

### 4. Produce the first release

Manually dispatch the publish workflow:

```bash
gh workflow run publish-stable-macos.yml -R hisgarden/vscodium
```

This will build both x64 and arm64, sign + notarize, and upload DMGs + `.sha256` files to a release tag (e.g. `1.108.28028`) on `hisgarden/vscodium`.

### 5. Wire the publish workflow to dispatch the tap

Add this final step to `.github/workflows/publish-stable-macos.yml` on the fork (after the existing `Update versions repo` step):

```yaml
- name: Trigger tap update
  if: env.SHOULD_BUILD == 'yes' && matrix.vscode_arch == 'arm64'  # fire once per release
  env:
    GH_TOKEN: ${{ secrets.TAP_DISPATCH_TOKEN }}
  run: |
    gh api repos/hisgarden/homebrew-tap/dispatches \
      -f event_type=release-published \
      -f client_payload[version]="${RELEASE_VERSION}" \
      -f client_payload[quality]=stable
```

Same change for `publish-insider-macos.yml` with `client_payload[quality]=insider`.

### 6. Seed the tap for the very first release

Before the auto-update workflow has run once, the cask contains placeholder SHAs. After step 4 completes and a release exists, trigger the tap update manually:

```bash
gh workflow run update-cask.yml -R hisgarden/homebrew-tap \
  -f version=<release-version> \
  -f quality=stable
```

After that, every new release on `hisgarden/vscodium` will auto-bump the cask.

## Verify

```bash
brew tap hisgarden/tap
brew install --cask vscodium
open /Applications/VSCodium.app
```

The app should launch without Gatekeeper warnings (proof of signing + notarization).

## Troubleshooting

- **Gatekeeper warns "unidentified developer"**: notarization didn't complete. Check the `Prepare assets` step log for `xcrun notarytool submit` errors.
- **`brew install` fails with SHA256 mismatch**: the cask's SHA doesn't match the DMG. Manually re-run `update-cask.yml` for the current release.
- **Cask fails to find DMG**: check the release on `hisgarden/vscodium` has assets named `VSCodium.<arch>.<version>.dmg` (not `.zip`).
- **Rate limiting on GitHub API**: the `TAP_DISPATCH_TOKEN` needs `repo` scope on `hisgarden/homebrew-tap`, not on `hisgarden/vscodium`.

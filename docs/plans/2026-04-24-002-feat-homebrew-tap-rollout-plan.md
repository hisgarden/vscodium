---
title: "feat: Homebrew tap rollout runbook — hisgarden fork"
type: feat
status: active
date: 2026-04-24
---

# feat: Homebrew tap rollout runbook — hisgarden fork

## Overview

End-to-end runbook to go from "PRs #1 (Bun) and #2 (tap kit) merged on `hisgarden/vscodium`" to "`brew install --cask hisgarden/tap/vscodium` produces a working, notarized VSCodium on a clean Mac." Follow the units in order and check boxes as you go.

**Target end state:** any user on macOS arm64 or x64 can run:

```
brew tap hisgarden/tap
brew install --cask vscodium
```

and get a signed + notarized VSCodium binary from your fork's releases, auto-updating on each new release.

---

## Problem Frame

PR #2 (`feat/homebrew-tap`) lands the kit — casks, update workflow, secrets loader, dispatch wiring — but the actual rollout requires manual steps that can't be automated from the repo: exporting an Apple Developer ID cert from Keychain Access, creating PATs, creating one adjacent repository, dispatching the first signed build, and verifying.

This plan is the hand-off runbook for those steps. It is **execution**, not **design** — the design lives in PR #2.

---

## Requirements Trace

- R1. `hisgarden/homebrew-tap` hosts the `vscodium` and `vscodium-insiders` casks alongside any existing casks (QuickRecorder), without clobber.
- R2. `hisgarden/versions` repo exists (consumed by `update_version.sh`).
- R3. Seven secrets present on `hisgarden/vscodium` → environment `publish`.
- R4. First stable release produced by `publish-stable-macos.yml` with signed + notarized DMGs for x64 + arm64 and accompanying `.sha256` files.
- R5. `update-cask.yml` on the tap produces a cask with real SHAs (not the `0000…` placeholder).
- R6. `brew install --cask vscodium` on a clean Mac installs without Gatekeeper warnings and `spctl --assess` reports "Notarized Developer ID".

---

## Scope Boundaries

- Not building Linux / Windows `brew`-like distributions — out of scope; macOS only.
- Not signing insider builds in this run — stable first, insider follows the same pattern when needed.
- Not setting up a Sparkle feed or any in-app auto-updater — Homebrew is the update path.

### Deferred to Follow-Up Work

- **Insider cask end-to-end test**: once stable is green, rerun steps 4–6 with `publish-insider-macos.yml` + `quality=insider` to validate the insider branch of `update-cask.yml`.

---

## Dependencies / Prerequisites

- PR #1 (Bun migration) merged to `hisgarden/vscodium:master` — so the first publish run uses the Bun-based build we verified locally.
- PR #2 (tap kit + security hardening) merged to `hisgarden/vscodium:master` — so `packaging/homebrew-tap/` files are available to copy and the publish workflow has the "Trigger Homebrew tap update" step.
- `gh` CLI authed as `hisgarden` with `admin` on both `hisgarden/vscodium` and `hisgarden/homebrew-tap`.
- Apple Developer ID Application certificate in macOS login keychain.
- Keychain items under service `hisgarden`: `appleid` (Apple ID) and `notarize` (app-specific password) — QuickRecorder pattern; already present on this machine.

Verify before starting:

```bash
gh auth status
gh api user --jq .login                            # → hisgarden
gh api repos/hisgarden/vscodium --jq .permissions.admin  # → true
security find-identity -v -p codesigning | grep "Developer ID Application"
```

---

## Key Technical Decisions

- **Tap repo is shared** with QuickRecorder (not a VSCodium-dedicated tap). Taps host multiple casks — reusing keeps the `hisgarden/tap` namespace stable for users.
- **Secrets live in a GitHub Actions `publish` environment**, not repo-level secrets, to match the existing workflow (`environment: publish` in every job). Created via `PUT /repos/{owner}/{repo}/environments/publish` with no protection rules.
- **Two separate PATs** for `STRONGER_GITHUB_TOKEN` and `TAP_DISPATCH_TOKEN` — different scopes, different trust surfaces; swapping one without invalidating the other.
- **Cleanup step deletes the exported `.p12`** from disk once uploaded. Can always re-export from Keychain Access.

---

## Implementation Units

- [x] U1. **Prerequisites verified**

**Goal:** Confirm CLI auth, repo permissions, and Developer ID cert are in place before touching anything.

**Files / commands:**

```bash
gh auth status
gh api user --jq .login                                     # expect: hisgarden
gh api repos/hisgarden/vscodium --jq .permissions.admin     # expect: true
security find-identity -v -p codesigning | grep "Developer ID Application"  # expect: 1+ match with (NSDC3EDS2G)
```

**Verification:** all four commands succeed and show the expected values.

**Status:**
- [x] `gh auth status` OK
- [x] admin on `hisgarden/vscodium` confirmed
- [x] Developer ID Application cert present in login keychain

---

- [ ] U2. **Seed `hisgarden/homebrew-tap` with VSCodium casks**

**Goal:** Add `vscodium.rb`, `vscodium-insiders.rb`, and the `update-cask.yml` workflow to the existing tap without clobbering QuickRecorder.

**Dependencies:** U1; PR #2 merged to `master` on `hisgarden/vscodium`.

**Files / commands:**

```bash
cd /tmp
rm -rf homebrew-tap-seed
git clone git@github.com:hisgarden/homebrew-tap.git homebrew-tap-seed
cd homebrew-tap-seed

# Sanity: see what's already there
ls Casks/

# Copy from the vscodium fork
cp /Users/jwen/workspace/util/vscodium/packaging/homebrew-tap/Casks/vscodium.rb Casks/
cp /Users/jwen/workspace/util/vscodium/packaging/homebrew-tap/Casks/vscodium-insiders.rb Casks/
mkdir -p .github/workflows
cp /Users/jwen/workspace/util/vscodium/packaging/homebrew-tap/.github/workflows/update-cask.yml .github/workflows/

git add -A
git status  # sanity check
git commit -m "feat: add vscodium + vscodium-insiders casks and update workflow"
git push
```

**Verification:**
- https://github.com/hisgarden/homebrew-tap lists `Casks/vscodium.rb`, `Casks/vscodium-insiders.rb`, `.github/workflows/update-cask.yml`, and the prior QuickRecorder cask — all present.

**Status:**
- [x] tap cloned
- [x] casks + workflow copied
- [x] commit pushed
- [x] QuickRecorder cask still present (no clobber)

---

- [ ] U3. **Create `hisgarden/versions` repo**

**Goal:** Empty public repo to receive build metadata from `update_version.sh`.

**Dependencies:** U1.

**Files / commands:**

```bash
gh repo create hisgarden/versions --public \
  --description "Version metadata for hisgarden VSCodium builds"

gh repo view hisgarden/versions --json name,isEmpty   # expect: {"name":"versions","isEmpty":true}
```

**Verification:** https://github.com/hisgarden/versions exists.

**Status:**
- [x] repo created
- [x] confirmed on GitHub

---

- [ ] U4. **Load Apple codesign secrets into `publish` environment**

**Goal:** Seven GitHub Actions secrets present on `hisgarden/vscodium` → `publish` env.

**Dependencies:** U1.

### U4.1 — Export Developer ID cert from Keychain Access

In **Keychain Access.app** → login keychain → My Certificates → right-click "Developer ID Application: ... (NSDC3EDS2G)" → **Export...** → Personal Information Exchange (.p12) → save as `~/Desktop/DeveloperID.p12` → set an export password (remember it).

- [x] cert exported to `~/Desktop/DeveloperID.p12`
- [x] export password noted

### U4.2 — Create two PATs

```bash
open "https://github.com/settings/tokens/new?description=STRONGER_GITHUB_TOKEN&scopes=repo"
# → generate → copy the ghp_... token

open "https://github.com/settings/tokens/new?description=TAP_DISPATCH_TOKEN&scopes=repo"
# → generate → copy the ghp_... token
```

- [x] STRONGER_GITHUB_TOKEN generated
- [x] TAP_DISPATCH_TOKEN generated

### U4.3 — Create `publish` environment and run the loader

```bash
# Create the publish environment (one-time, no protections)
gh api -X PUT repos/hisgarden/vscodium/environments/publish

# Run the loader
cd /Users/jwen/workspace/util/vscodium
./packaging/homebrew-tap/load-github-secrets.sh ~/Desktop/DeveloperID.p12
```

Interactive prompts — typical answers:

- Apple ID `[jin.wen@hisgarden.org]:` → ENTER
- Apple Team ID `[NSDC3EDS2G]:` → ENTER
- `.p12 export password:` → type the password from U4.1
- `STRONGER_GITHUB_TOKEN ...:` → paste the token from U4.2
- `TAP_DISPATCH_TOKEN ...:` → paste the token from U4.2

**Verification:**

```bash
gh api repos/hisgarden/vscodium/environments/publish/secrets --jq '.secrets[].name' | sort
```

Expect exactly these 7 names:

- `CERTIFICATE_OSX_NEW_APP_PASSWORD`
- `CERTIFICATE_OSX_NEW_ID`
- `CERTIFICATE_OSX_NEW_P12_DATA`
- `CERTIFICATE_OSX_NEW_P12_PASSWORD`
- `CERTIFICATE_OSX_NEW_TEAM_ID`
- `STRONGER_GITHUB_TOKEN`
- `TAP_DISPATCH_TOKEN`

- [x] `publish` env created
- [x] loader run, no errors
- [x] 7 secrets listed

### U4.4 — Cleanup

```bash
rm ~/Desktop/DeveloperID.p12
```

- [x] `.p12` deleted from disk

---

- [ ] U5. **Merge PRs + produce first signed release**

**Goal:** A tagged release on `hisgarden/vscodium` with four macOS DMG-related assets (x64 + arm64 DMG and matching `.sha256`).

**Dependencies:** U2, U3, U4. PR #1 and PR #2 merged.

**Files / commands:**

```bash
# Merge PR #1 (Bun migration) if not already
gh pr merge 1 -R hisgarden/vscodium --squash --delete-branch

# Merge PR #2 (tap kit + security hardening)
gh pr merge 2 -R hisgarden/vscodium --squash --delete-branch

# Dispatch the publish workflow
gh workflow run publish-stable-macos.yml -R hisgarden/vscodium

# Watch — expect 30-60 minutes
sleep 10
RUN_ID=$(gh run list -R hisgarden/vscodium -w publish-stable-macos.yml --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID"
gh run watch $RUN_ID -R hisgarden/vscodium
```

**Verification:**

```bash
# Should show exactly one new release
gh release list -R hisgarden/vscodium --limit 1

# Capture the version tag — you need it in U6
VERSION=$(gh release view -R hisgarden/vscodium --json tagName -q .tagName)
echo "Release: $VERSION"

# Should list 4 macOS assets
gh release view -R hisgarden/vscodium "$VERSION" --json assets -q '.assets[].name' | grep -E '\.(dmg|dmg\.sha256)$' | sort
```

Expect:

```
VSCodium.arm64.<VERSION>.dmg
VSCodium.arm64.<VERSION>.dmg.sha256
VSCodium.x64.<VERSION>.dmg
VSCodium.x64.<VERSION>.dmg.sha256
```

**Status:**
- [ ] PR #1 merged
- [ ] PR #2 merged
- [ ] `publish-stable-macos.yml` completed successfully
- [ ] release tag exists
- [ ] 4 DMG assets present
- [ ] `VERSION=<tag>` recorded for next unit: `__________________`

---

- [ ] U6. **Seed the cask with real SHAs**

**Goal:** The cask on `hisgarden/homebrew-tap` points at the real release version with two valid 64-char hex SHAs (not the `0000…` placeholder).

**Dependencies:** U5. `VERSION` captured.

**Note:** PR #2 wired an auto-dispatch step in `publish-stable-macos.yml` — if `TAP_DISPATCH_TOKEN` was set correctly, the tap workflow may have run automatically at the end of U5. Check first, dispatch manually only if it didn't.

**Files / commands:**

```bash
# Check if the tap workflow already ran
gh run list -R hisgarden/homebrew-tap -w update-cask.yml --limit 1

# If no recent run, dispatch manually:
gh workflow run update-cask.yml -R hisgarden/homebrew-tap \
  -f version="$VERSION" \
  -f quality=stable

sleep 5
TAP_RUN=$(gh run list -R hisgarden/homebrew-tap -w update-cask.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch $TAP_RUN -R hisgarden/homebrew-tap
```

**Verification:**

```bash
gh api repos/hisgarden/homebrew-tap/contents/Casks/vscodium.rb --jq .content | base64 -d | head -15
```

Expect:

- `version "<VERSION>"` on line ~2 — not `0.0.0-placeholder`
- Two `sha256 "<64-char-hex>"` lines — not all zeros

**Status:**
- [ ] tap workflow run completed
- [ ] cask version matches `$VERSION`
- [ ] both SHAs are real (non-zero)

---

- [ ] U7. **Install via brew and verify**

**Goal:** `brew install --cask hisgarden/tap/vscodium` produces a signed + notarized, Gatekeeper-clean VSCodium.

**Dependencies:** U6.

**Files / commands:**

```bash
# Fresh tap add (or update if already tapped)
brew untap hisgarden/tap 2>/dev/null || true
brew tap hisgarden/tap

# Remove upstream if installed, so we test our cask not the public one
brew uninstall --cask vscodium 2>/dev/null || true

# Install
brew install --cask vscodium

# Launch — expect no Gatekeeper dialog
open /Applications/VSCodium.app
```

**Verification:**

```bash
codesign -dv /Applications/VSCodium.app 2>&1 | grep -E "TeamIdentifier|Authority"
# expect: TeamIdentifier=NSDC3EDS2G
# expect: Authority=Developer ID Application: <your name> (NSDC3EDS2G)

spctl --assess --verbose /Applications/VSCodium.app
# expect: /Applications/VSCodium.app: accepted  source=Notarized Developer ID
```

**Status:**
- [ ] `brew tap hisgarden/tap` succeeded
- [ ] `brew install --cask vscodium` succeeded
- [ ] VSCodium launches with no Gatekeeper warning
- [ ] `codesign -dv` shows TeamIdentifier `NSDC3EDS2G`
- [ ] `spctl --assess` reports "Notarized Developer ID"

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Apple app-specific password expired / revoked | Med | High | Regenerate at appleid.apple.com, update Keychain (`security add-internet-password -s hisgarden -a notarize -w <new> -U`), re-run `load-github-secrets.sh` |
| `.p12` export password mis-typed when loading secrets | Low | High | `security import` fails audibly in the `Prepare assets` step; re-run U4 |
| Publish run hits a transient network error mid-build | Med | Med | `publish-stable-macos.yml` retries `bun install`/`npm ci` 5 times; re-dispatch the workflow if it fails outright |
| Bun-migration regression found only in CI (e.g. Linux builds break even though macOS worked) | Low | Med | Publish workflow is macOS-only for this rollout; Linux/Windows workflows unaffected by the first rollout |
| `TAP_DISPATCH_TOKEN` revoked / scope wrong → auto-dispatch skipped | Low | Low | Workflow gracefully skips; U6 manual dispatch still works |
| Cask SHA mismatch at `brew install` time | Low | Med | Usually means U6 raced the release upload; re-run U6 |
| VSCodium launches but shows "damaged" | Low | High | Notarization stapling failed — check `xcrun stapler staple` step in U5 logs; may need to re-run publish |

---

## Troubleshooting Quick Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| U4.3 loader: `security: find-internet-password: The specified item could not be found in the keychain` | Keychain item names don't match `hisgarden/notarize` | Create: `security add-internet-password -s hisgarden -a notarize -w 'xxxx-xxxx-xxxx-xxxx'` |
| U4.3 loader: `gh secret set` returns 404 | `publish` env doesn't exist | Run `gh api -X PUT repos/hisgarden/vscodium/environments/publish` first |
| U5 "Prepare assets" fails at `security import` | `.p12` password wrong or `.p12` content not base64 | Re-export from Keychain, re-run U4 |
| U5 "Notarize" fails | app-specific password stale | Regenerate + update Keychain, re-run U4.3 |
| U6 workflow exits "EVENT_VERSION ... failed strict semver validation" | Tag name doesn't match `^[0-9]+(\.[0-9]+){1,3}(...)?$` | Investigate `check_tags.sh`; likely a transient upstream weirdness |
| U7 `brew install` says SHA256 mismatch | U6 raced release upload | Re-run U6 manually |

---

## Sources & References

- **PR #1** — Bun migration: https://github.com/hisgarden/vscodium/pull/1
- **PR #2** — Tap kit + security hardening: https://github.com/hisgarden/vscodium/pull/2
- **Setup runbook (source)**: `packaging/homebrew-tap/SETUP.md`
- **Secret loader**: `packaging/homebrew-tap/load-github-secrets.sh`
- **Casks**: `packaging/homebrew-tap/Casks/vscodium.rb`, `vscodium-insiders.rb`
- **Update workflow**: `packaging/homebrew-tap/.github/workflows/update-cask.yml`
- **QuickRecorder credential pattern** (reference): `/Users/jwen/workspace/util/QuickRecorder/scripts/credentials.sh.example`

---
title: "refactor: Replace Node/npm artifacts with Bun equivalents (maximal swap)"
type: refactor
status: active
date: 2026-04-24
---

# refactor: Replace Node/npm artifacts with Bun equivalents (maximal swap)

## Overview

Replace Node.js and npm artifacts across this VSCodium build harness with Bun equivalents wherever Bun can plausibly substitute, while keeping Node in the irreducible places where Electron, node-gyp, and VS Code's own build lifecycle fundamentally require it. User explicitly chose the **maximal swap** scope, accepting higher risk of VS Code build-lifecycle regressions in exchange for the broadest Node surface reduction.

This plan is **not** a VS Code upstream fork. It only touches artifacts owned by this repository (`build.sh`, `prepare_*.sh`, `dev/`, `build/`, `.github/workflows/`, `font-size/`, `docs/`). VS Code's internal Gulp tasks, `build/npm/preinstall.ts`, and native module compilation via `node-gyp` still execute under Node at runtime — the plan only changes *how we invoke them*.

---

## Problem Frame

This repo has two distinct Node/npm surfaces:

1. **Harness surface** (fully under our control) — shell scripts, CI workflows, the `font-size/` helper package, `.nvmrc`, docs. We can freely choose runtime and package manager.
2. **VS Code surface** (upstream, not forked) — the `vscode/` tree fetched by `get_repo.sh`. Its `package.json`, Gulpfile, `build/npm/preinstall.ts`, and `build/lib/policies/policyGenerator.ts` assume Node + npm semantics and compile native Electron modules via node-gyp against Node headers.

Today the harness invokes the VS Code surface with `npm ci` and `npm run gulp …` and provisions Node in CI via `actions/setup-node` + `.nvmrc` + `build/linux/install_nodejs.sh`. The goal is to invoke everything possible through Bun instead, while preserving VS Code build correctness (same output binaries, same signing, same REH/REH-Web packaging, same cross-arch matrix).

---

## Requirements Trace

- R1. Every harness-owned invocation of `node` or `npm` is replaced with a Bun equivalent unless a hard constraint (Electron, node-gyp, upstream-expected lifecycle) is documented.
- R2. `font-size/` helper package builds, lints, and runs under Bun with no Node toolchain installed locally.
- R3. Local dev build (`./dev/build.sh`) succeeds on macOS and produces the same `VSCode-darwin-${VSCODE_ARCH}` output tree as before the migration.
- R4. CI workflows (`.github/workflows/ci-build-{linux,macos,windows}.yml` and the corresponding `publish-*`) provision Bun and use it for harness-side commands. Node is still provisioned where node-gyp native compile or Electron packaging requires it.
- R5. `.nvmrc` is preserved as the source of truth for Node version used by VS Code's internal build; a new `.bun-version` is introduced as the source of truth for Bun.
- R6. `docs/howto-build.md` reflects Bun as the primary dev prerequisite and documents the remaining Node prerequisite with a clear "why still needed" note.
- R7. User-global CLAUDE.md requirement: every `*.sh` script modified by this plan gains a changelog block at the end if it does not already have one, with a dated entry for the Bun migration change.

---

## Scope Boundaries

- Not forking Microsoft's VS Code. The `vscode/` tree's `package.json`, Gulpfile, `build/npm/preinstall.ts`, and `build/lib/policies/policyGenerator.ts` are not edited.
- Not replacing Electron's embedded Node runtime. The produced VSCodium binary still ships Electron (which embeds Node), unchanged.
- Not replacing `node-gyp`. Native module compilation (tree-sitter, node-pty, keytar, spdlog, etc.) continues via node-gyp against Node headers, driven by VS Code's `npm ci` lifecycle.
- Not changing `vscode-cli` (Rust) build. `build_cli.sh` is Rust/Cargo-only and already unaffected.
- Not changing patch management scripts in `patches/` or `dev/update_patches.sh` behavior — only the npm/node invocations inside them if any.
- Not changing Snap packaging under `stores/snapcraft/` in this plan.

### Deferred to Follow-Up Work

- **Forking VS Code's build system to remove Node entirely**: would require maintaining patches against `vscode/build/**` and rebuilding Electron on Bun — out of scope for this plan, deferred indefinitely.
- **Replacing `node-gyp`**: tracked separately; depends on Bun shipping a production-ready native-addon build flow with cross-arch support matching `npm_config_arch`.

---

## Context & Research

### Relevant Code and Patterns

- `.nvmrc` (top-level) — pins Node `22.22.0`, consumed by VS Code's internal build and by `actions/setup-node` in CI.
- `font-size/.nvmrc`, `font-size/package.json`, `font-size/package-lock.json`, `font-size/.xo-config.json`, `font-size/tsconfig.base.json` — standalone TypeScript helper, fully under our control.
- `prepare_src.sh` line 6: `npm install -g checksum` — one-shot global install used only for checksum generation in this script.
- `prepare_vscode.sh` lines 201–220: `node build/npm/preinstall.ts` and the `npm ci` retry loop (5 attempts with `CXX=clang++` on macOS CI).
- `build.sh` lines 17–87: all `npm run monaco-compile-check`, `npm run valid-layers-check`, `npm run gulp …`, `npm run copy-policy-dto --prefix build`, and `node build/lib/policies/policyGenerator.ts …` invocations.
- `build/linux/install_nodejs.sh` — provisions Node on Linux CI runners via tarball download from `${NODEJS_SITE}`; mirrors install logic that `actions/setup-node` performs on mac/windows.
- `.github/workflows/ci-build-linux.yml`, `ci-build-macos.yml`, `ci-build-windows.yml` and their `publish-*` counterparts — all use `actions/setup-node@…` with `node-version-file: .nvmrc` and set `npm_config_arch` for cross-arch native builds.
- `dev/build.sh` — local dev entry, exports `NODE_OPTIONS="--max-old-space-size=8192"` and sources `build.sh`. No direct `npm`/`node` invocations of its own.

### Institutional Learnings

- No `docs/solutions/` entries exist in this repo yet.
- User-global CLAUDE.md: `*.sh` scripts must carry a changelog block at the end. This repo's existing shell scripts do **not** currently follow that convention — this plan introduces it for every script it modifies (R7).

### External References

- Bun's `bun install` aims for `npm ci` compatibility but diverges on lifecycle script ordering and native module builds; VS Code's postinstall relies on lifecycle scripts invoking `node-gyp` under specific env vars (`npm_config_arch`, `npm_config_target`, etc.). These env vars are read directly from `process.env` by node-gyp and should continue to work under Bun, but must be verified empirically.
- Bun can execute `.ts` files directly, matching Node's TypeScript-via-`--experimental-strip-types` behavior used by `node build/npm/preinstall.ts` and `node build/lib/policies/policyGenerator.ts`.
- `oven-sh/setup-bun@v2` is the canonical GitHub Action for Bun provisioning in CI. It reads `bun-version-file` or an inline `bun-version` input.

---

## Key Technical Decisions

- **Keep `.nvmrc` in place.** VS Code's internal build assumes a Node binary on `PATH`; Electron packaging and node-gyp native module compilation cannot use Bun as a drop-in. Removing `.nvmrc` would break the VS Code build. Document this constraint explicitly in `docs/howto-build.md`.
- **Add `.bun-version` as a new file** at repo root, pinned to a specific Bun release. CI and `dev/build.sh` both read from this file.
- **Use `bun x` instead of `bun install -g` for the `checksum` tool** in `prepare_src.sh`. Avoids polluting global state, matches the one-shot usage pattern, and is faster.
- **Prefer `bun run <script>` over `npm run <script>`** for all VS Code package.json script invocations (`monaco-compile-check`, `valid-layers-check`, `gulp …`, `copy-policy-dto`). `bun run` delegates to the package's declared runtime for the actual script body but avoids npm's slower script resolution.
- **Attempt `bun install --frozen-lockfile` in place of `npm ci`** inside the `vscode/` tree, with a retained fallback to `npm ci` on failure (gated by a new `BUN_VSCODE_INSTALL` env var defaulting to `yes`). This is the single highest-risk change and must be kept reversible.
- **Keep `actions/setup-node` in CI alongside `oven-sh/setup-bun`.** Node is still required on `PATH` for Electron packaging and node-gyp. The CI change is **additive** for Node and **substitutive** for harness-side npm/node invocations.
- **Replace `node <script>.ts` invocations in harness scripts with `bun <script>.ts`.** Specifically `node build/npm/preinstall.ts` and `node build/lib/policies/policyGenerator.ts …` — Bun's TypeScript support is mature enough to run these directly.
- **`font-size/` fully migrates to Bun** — `bun install` drives `bun.lockb` (replacing `package-lock.json`), `.bun-version` replaces `font-size/.nvmrc`, and `bun run lint` drives xo directly. xo itself is still a Node CLI but Bun invokes Node-compatible CLIs transparently.

---

## Open Questions

### Resolved During Planning

- **Should we remove `.nvmrc`?** No — VS Code's internal build and Electron packaging still require Node on `PATH`. Keep `.nvmrc` and add `.bun-version`.
- **Can we run `node build/npm/preinstall.ts` with Bun?** Yes, Bun runs TypeScript natively. This is a harness-side invocation, not a VS Code script — we control the runtime choice.
- **Should `font-size/` keep its own `.nvmrc`?** No — it becomes Bun-only and uses the root `.bun-version`. Delete `font-size/.nvmrc` and `font-size/package-lock.json`.
- **Does `npm_config_arch` still work when `bun install` runs `node-gyp`?** Bun reads `npm_config_*` env vars from `process.env` and forwards them to lifecycle scripts, but node-gyp invocation path differs — must be verified empirically during U4 implementation.

### Deferred to Implementation

- **Whether `bun install --frozen-lockfile` inside `vscode/` produces a byte-identical `node_modules/` to `npm ci`.** Requires running both and diffing — execution-time discovery. Plan retains an `npm ci` fallback path.
- **Exact Bun version to pin in `.bun-version`.** Pick the latest stable at implementation time; document the choice in the commit message.
- **Whether `bun run gulp <task>` invokes Gulp identically to `npm run gulp <task>` across all 9 gulp tasks used in `build.sh`.** Must be verified by running a full macOS dev build end-to-end.
- **Windows-specific Bun behavior in Git Bash.** Git Bash PATH handling for Bun's Windows binary may need tweaking in `docs/howto-build.md` — discover during U6.

---

## High-Level Technical Design

> *This illustrates the intended substitution pattern and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
Harness surface (we own)              VS Code surface (upstream, untouched)
──────────────────────────            ─────────────────────────────────────
dev/build.sh                          vscode/build/npm/preinstall.ts
  └─ sources build.sh                 vscode/build/lib/policies/policyGenerator.ts
       └─ bun run monaco-compile-check  ← invoked via bun run on VS Code's package.json
       └─ bun run gulp <task>           ← Gulp itself still runs on Node (embedded in Electron-rebuild tree)
       └─ bun <script>.ts               ← harness-side direct TS execution
       └─ bun install --frozen-lockfile ← attempted; falls back to npm ci on failure

prepare_src.sh
  └─ bun x checksum ...               (replaces `npm install -g checksum`)

prepare_vscode.sh
  └─ bun build/npm/preinstall.ts      (replaces `node build/npm/preinstall.ts`)
  └─ bun install --frozen-lockfile    (attempted in place of `npm ci`, with fallback)

CI workflows
  ├─ oven-sh/setup-bun (reads .bun-version)     ← NEW, primary
  └─ actions/setup-node (reads .nvmrc)          ← KEPT, still needed for node-gyp/Electron

font-size/ (standalone)
  └─ Bun end-to-end: bun install, bun run lint, bun run clean
     .nvmrc removed, package-lock.json removed, bun.lockb introduced

.bun-version (NEW)      .nvmrc (KEPT — still required by VS Code's internal build)
```

**Irreducible Node surface (unchanged):** Electron's embedded Node runtime in the produced VSCodium binary; `node-gyp` native module compilation driven by VS Code's postinstall; Gulp task execution inside `vscode/`.

---

## Implementation Units

- [ ] U1. **Introduce `.bun-version` and document the dual-runtime policy**

**Goal:** Establish Bun as a first-class pinned prerequisite alongside the existing Node pin, and document the "why both" rationale.

**Requirements:** R5, R6

**Dependencies:** None

**Files:**
- Create: `.bun-version`
- Modify: `docs/howto-build.md`

**Approach:**
- Pin `.bun-version` to the current stable Bun release (pick at implementation time).
- In `docs/howto-build.md`, add Bun to the top-level `## Dependencies` list; update the Linux/macOS/Windows prerequisite sections to list Bun first, then Node (with the note "still required for VS Code's internal build — `node-gyp` native modules and Electron packaging").
- Update the Windows "PATH verification" snippet to include `bun --version`.

**Patterns to follow:**
- Existing `.nvmrc` format (single line, version only).
- Existing dependency list style in `docs/howto-build.md` (bullet list, tool names in backticks).

**Test scenarios:**
- Happy path: `cat .bun-version` returns a non-empty pinned version string.
- Integration: running `bun --version` matches `.bun-version` after a fresh `oven-sh/setup-bun@v2` action read.
- Integration: `docs/howto-build.md` renders with Bun listed first in the dependencies section; a reader new to the project can install Bun + Node and proceed.

**Verification:**
- `.bun-version` exists at repo root and contains a valid Bun semver.
- `docs/howto-build.md` has a clearly labeled note explaining why Node remains required despite the Bun migration.

---

- [ ] U2. **Migrate `font-size/` fully to Bun**

**Goal:** Make the standalone `font-size/` helper package buildable and lintable with Bun only, no Node toolchain required.

**Requirements:** R1, R2

**Dependencies:** U1

**Files:**
- Delete: `font-size/.nvmrc`
- Delete: `font-size/package-lock.json`
- Modify: `font-size/package.json`
- Create: `font-size/bun.lockb` (generated by `bun install`, committed)
- Test: manual execution — no existing test harness in this package

**Approach:**
- Remove `font-size/.nvmrc` (root `.bun-version` is authoritative).
- In `font-size/package.json`, keep `type: "module"` and script entries unchanged; Bun honors them.
- Run `bun install` in `font-size/` to generate `bun.lockb`, then remove `package-lock.json`.
- Verify `bun run lint` (xo) and `bun run clean` (rimraf) work — both are Node-CLI binaries but Bun invokes them fine.
- Verify `bun generate-css.ts` (or the equivalent entry) runs the TypeScript source directly under Bun's runtime.

**Execution note:** After deleting `package-lock.json`, run `bun install` and visually inspect `bun.lockb` to confirm all 7 dependencies resolved to expected versions before committing.

**Patterns to follow:**
- Minimal scripts block in `font-size/package.json` — no restructuring, just lockfile and `.nvmrc` swap.

**Test scenarios:**
- Happy path: `cd font-size && bun install` completes without error and produces `bun.lockb`.
- Happy path: `cd font-size && bun run lint` completes with the same pass/fail outcome as `npm run lint` did before.
- Happy path: `cd font-size && bun generate-css.ts` (or package `main` entry) runs the TS file directly and produces identical output to the prior Node-run output.
- Edge case: running `bun install` a second time is a no-op and does not modify `bun.lockb`.
- Integration: a fresh clone with Bun only (no Node) can `bun install` and `bun run lint` successfully.

**Verification:**
- `font-size/.nvmrc` is absent.
- `font-size/package-lock.json` is absent.
- `font-size/bun.lockb` is committed and reproducible.
- `bun run lint` passes from a cold checkout.

---

- [ ] U3. **Swap `npm install -g checksum` → `bun x checksum` in `prepare_src.sh`**

**Goal:** Eliminate the global npm install for the checksum tool and use Bun's ephemeral execution.

**Requirements:** R1, R7

**Dependencies:** U1

**Files:**
- Modify: `prepare_src.sh`

**Approach:**
- Replace line 6 `npm install -g checksum` with a Bun-based approach: either `bun x checksum` inlined into the `sum_file` function, or `bun add -g checksum` if a global install is genuinely needed for subshell inheritance.
- Prefer `bun x checksum -a sha256 "${1}"` inside `sum_file` — avoids global state and matches one-shot semantics.
- Add a changelog block at the end of `prepare_src.sh` per user-global CLAUDE.md rule R7.

**Patterns to follow:**
- Shell-script changelog block format from the user-global CLAUDE.md (header comment, dated entries, < 80 char descriptions, most recent first).

**Test scenarios:**
- Happy path: running `prepare_src.sh` with `APP_NAME` and `RELEASE_VERSION` set produces `assets/*.tar.gz`, `*.zip`, `*.sha256`, and `*.sha1` files as before.
- Edge case: running on a fresh machine with Bun installed but no npm globals produces identical checksum file contents to the previous npm-installed path.
- Error path: if `bun x checksum` fails to fetch, the error surfaces clearly and the script exits (not silently swallowing).
- Integration: checksum output bytes match those from the prior `npm install -g checksum` + `checksum` invocation for the same input file.

**Verification:**
- `prepare_src.sh` contains no references to `npm`.
- The produced `*.sha256` and `*.sha1` files have identical content to pre-migration output for the same input.
- The script has a changelog block documenting the Bun migration.

---

- [ ] U4. **Replace Node/npm calls in `prepare_vscode.sh` with Bun, gated for safe rollback**

**Goal:** Swap `node build/npm/preinstall.ts` and `npm ci` inside the `vscode/` tree for Bun equivalents, with an env-var-gated fallback to Node/npm so the change is reversible in CI without a revert.

**Requirements:** R1, R3, R7

**Dependencies:** U1

**Files:**
- Modify: `prepare_vscode.sh`

**Approach:**
- Replace line 201 `node build/npm/preinstall.ts` with `bun build/npm/preinstall.ts`. This is a harness-side invocation — the script body still uses Node-compatible APIs but Bun executes it.
- Introduce a new env var `BUN_VSCODE_INSTALL` defaulting to `yes` in the retry loop (lines 205–220):
  - If `BUN_VSCODE_INSTALL=yes`, run `bun install --frozen-lockfile` (preserving the `CXX=clang++` override on macOS CI).
  - If `BUN_VSCODE_INSTALL=no`, fall back to existing `npm ci` path.
  - Retry semantics (5 attempts with sleep backoff) are preserved for both paths.
- Preserve the `.npmrc` swap dance (mv/cp) around the install — Bun reads `.npmrc` for registry config.
- Add a changelog block at the end of `prepare_vscode.sh` per R7.

**Execution note:** This is the single highest-risk unit. Before declaring complete, run a full `./dev/build.sh` locally on macOS and diff the produced `VSCode-darwin-${VSCODE_ARCH}` tree against a pre-migration reference build. Any mismatch in native module `.node` files, missing extensions, or altered `package.json` versions fails the unit.

**Patterns to follow:**
- Existing 5-try retry loop structure in `prepare_vscode.sh` (lines 206–220).
- Existing env var conditional style: `if [[ "${CI_BUILD}" != "no" ]]; then`.
- User-global shell-script changelog block.

**Test scenarios:**
- Happy path (Bun): `BUN_VSCODE_INSTALL=yes prepare_vscode.sh` completes successfully on macOS and produces a populated `vscode/node_modules/` with all expected native modules.
- Happy path (Node fallback): `BUN_VSCODE_INSTALL=no prepare_vscode.sh` completes successfully via `npm ci`, matching pre-migration behavior byte-for-byte.
- Edge case: `bun install` fails on first try but succeeds on retry 2 — retry loop behaves identically to npm path.
- Error path: `bun install` fails all 5 attempts → script exits 1 with the documented error message, no silent success.
- Integration: `vscode/node_modules/@vscode/tree-sitter-wasm/` and other native modules are present and loadable after Bun install (verified by `bun build.sh` reaching the gulp phase without ENOENT).
- Integration: `npm_config_arch` env var is respected by Bun's install path — setting `npm_config_arch=arm64` on an x64 host produces arm64-targeted native modules.

**Verification:**
- `prepare_vscode.sh` contains no bare `node` or `npm ci` calls (only gated fallback inside the `BUN_VSCODE_INSTALL=no` branch).
- A full dev build succeeds on macOS with `BUN_VSCODE_INSTALL=yes`.
- A full dev build succeeds on macOS with `BUN_VSCODE_INSTALL=no` (fallback path proven alive).
- Changelog block present at script end.

---

- [ ] U5. **Swap `npm run` and `node <script>.ts` in `build.sh` for Bun equivalents**

**Goal:** Replace every `npm run …` and `node …` invocation in `build.sh` with the Bun equivalent.

**Requirements:** R1, R3, R7

**Dependencies:** U4

**Files:**
- Modify: `build.sh`

**Approach:**
- Replace all `npm run <script>` with `bun run <script>`. Specifically lines 17, 18, 20, 21, 22, 23, 30, 33, 46, 49, 67, 70, 81, 82, 86, 87 (count verified in Phase 1 research).
- Replace `node build/lib/policies/policyGenerator.ts …` (lines 31, 47, 68) with `bun build/lib/policies/policyGenerator.ts …`.
- `NODE_OPTIONS="--max-old-space-size=8192"` on line 12: keep as-is. This flag is read by Node invocations inside Gulp tasks that VS Code spawns. Bun honors it pass-through for spawned Node processes.
- Add a changelog block at script end per R7.

**Patterns to follow:**
- Existing invocation style (bare `npm run <script>` on its own line).
- Existing env var export style: `export NODE_OPTIONS="…"`.

**Test scenarios:**
- Happy path: full `./dev/build.sh` on macOS produces `VSCode-darwin-${VSCODE_ARCH}` tree identical to pre-migration reference build.
- Happy path: all 9 distinct gulp tasks (`compile-build-without-mangling`, `compile-extension-media`, `compile-extensions-build`, `minify-vscode`, platform-specific `min-ci`, `minify-vscode-reh`, REH packaging, `minify-vscode-reh-web`, REH-web packaging) execute successfully under `bun run gulp`.
- Happy path: `bun build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc darwin` produces the same policy definitions file as the Node invocation.
- Edge case: `NODE_OPTIONS` max-old-space-size is honored — a large build that previously needed 8GB heap does not OOM.
- Error path: if a gulp task fails, `set -ex` at the top of `build.sh` still causes immediate exit (Bun preserves shell exit codes).
- Integration: `SHOULD_BUILD_REH=yes` path and `SHOULD_BUILD_REH_WEB=yes` path both complete successfully.

**Verification:**
- `build.sh` contains zero `npm run` or bare `node` invocations.
- Full dev build succeeds on macOS.
- Produced artifacts byte-match (or acceptably near-match — signatures differ) a pre-migration build.
- Changelog block present.

---

- [ ] U6. **Migrate CI workflows: add `oven-sh/setup-bun` alongside `actions/setup-node`**

**Goal:** Provision Bun in all CI workflows so Bun-invoked harness commands work in CI, while keeping Node provisioned for node-gyp and Electron packaging.

**Requirements:** R1, R4, R5

**Dependencies:** U1, U4, U5

**Files:**
- Modify: `.github/workflows/ci-build-linux.yml`
- Modify: `.github/workflows/ci-build-macos.yml`
- Modify: `.github/workflows/ci-build-windows.yml`
- Modify: `.github/workflows/publish-stable-linux.yml`
- Modify: `.github/workflows/publish-stable-macos.yml`
- Modify: `.github/workflows/publish-stable-windows.yml`
- Modify: `.github/workflows/publish-insider-linux.yml`
- Modify: `.github/workflows/publish-insider-macos.yml`
- Modify: `.github/workflows/publish-insider-windows.yml`
- Modify: `.github/workflows/publish-stable-spearhead.yml`
- Modify: `.github/workflows/publish-insider-spearhead.yml`
- Modify: `build/linux/install_nodejs.sh` (add bun install alongside, or create `build/linux/install_bun.sh`)

**Approach:**
- For every workflow that uses `actions/setup-node@… node-version-file: .nvmrc`, add immediately after it:
  ```yaml
  - name: Setup Bun
    uses: oven-sh/setup-bun@v2
    with:
      bun-version-file: '.bun-version'
  ```
  Pin the action SHA following the existing `pinact` convention used in `justfile`'s `ci-update` task.
- Preserve `actions/setup-node` — do not remove it. Both runtimes are needed.
- Preserve `npm_config_arch` env vars in matrix entries — they are read by node-gyp during `bun install`'s lifecycle scripts too.
- On Linux, `build/linux/install_nodejs.sh` is called directly (not via `actions/setup-node`) in some workflow paths. Create `build/linux/install_bun.sh` with parallel structure (reads `.bun-version`, downloads from Bun's release URL, installs to `/usr/local/bun`, appends to `$GITHUB_PATH`). Wire it into the same workflow steps that currently call `install_nodejs.sh`.
- Add a changelog block to `build/linux/install_nodejs.sh` (R7) and `build/linux/install_bun.sh`.

**Patterns to follow:**
- Existing `actions/setup-node` step format with pinned SHA comment (e.g., `# v6.3.0`).
- `build/linux/install_nodejs.sh` shape (set -ex, read version file, curl tarball, extract, move to `/usr/local/<tool>`, append to `$GITHUB_PATH`).
- `justfile` `ci-update` task documents `pinact run` — apply to any new action reference.

**Test scenarios:**
- Happy path: each of the three `ci-build-*.yml` workflows completes end-to-end on GitHub Actions with both Bun and Node provisioned.
- Happy path: `bun --version` in a CI step returns the pinned version from `.bun-version`.
- Happy path: `node --version` in a CI step still returns the pinned version from `.nvmrc` (regression check — Node provisioning not broken by the change).
- Edge case: the Linux matrix entry for each `npm_arch` (x64, arm64, arm, riscv64, loong64, ppc64, s390x) still produces its arch-specific artifacts.
- Error path: if `.bun-version` is missing or malformed, `oven-sh/setup-bun` fails with a clear error (not a silent skip that leaves later Bun invocations broken).
- Integration: publish workflows for stable + insider on all 3 OSes complete, producing installers identical to pre-migration reference.

**Verification:**
- Every workflow file that previously had `actions/setup-node` now also has `oven-sh/setup-bun`.
- `build/linux/install_bun.sh` exists and is invoked in the same workflow paths that invoke `install_nodejs.sh`.
- All workflows pass `zizmor` lint (existing `just ci-lint` command).
- A green CI run exists for each of the 11 touched workflows.

---

- [ ] U7. **Audit residual Node/npm references and update `docs/howto-build.md` final pass**

**Goal:** Catch anything the earlier units missed — shell scripts, dev helpers, alpine/osx packaging — and ensure docs reflect the finished state.

**Requirements:** R1, R6, R7

**Dependencies:** U2, U3, U4, U5, U6

**Files:**
- Audit: `upload_sourcemaps.sh`, `release.sh`, `prepare_assets.sh`, `prepare_checksums.sh`, `build_cli.sh`, `version.sh`, `update_version.sh`, `build/alpine/package_reh.sh`, `build/osx/prepare_assets.sh`, `build/linux/prepare_assets.sh`, `build/linux/package_reh.sh`, `build/linux/package_bin.sh`, `build/windows/package.sh`, `build/windows/prepare_assets.sh`, `dev/build.sh`, `dev/build.ps1`, `dev/cli.sh`, `dev/patch.sh`, `dev/update_patches.sh`
- Modify: any of the above that contain `node`/`npm` invocations that can be swapped
- Modify: `docs/howto-build.md` final pass — ensure all references are accurate post-migration
- Modify: `CONTRIBUTING.md` if it contains Node/npm-specific dev guidance

**Approach:**
- Run `grep -rnE "\b(npm|node|npx)\b" --include="*.sh" --include="*.ps1" .` excluding `patches/`, `upstream/`, `node_modules/`. For each hit, classify as (a) harness-owned and swappable, (b) reference to VS Code's internal Node use (leave alone), or (c) a comment/log string (leave alone or update wording).
- Swap each category-(a) hit following the patterns from U3, U4, U5.
- Add a changelog block to every `.sh` file modified in this unit (R7).
- In `docs/howto-build.md`, update the `## Build for Development` section to mention the `BUN_VSCODE_INSTALL` env var from U4 and document its default (`yes`) and fallback behavior.
- Update `docs/howto-build.md` Windows section: note that Bun has first-class Windows support and Git Bash is still recommended for the shell scripts themselves.

**Patterns to follow:**
- Classification discipline established in earlier units (harness surface vs VS Code surface).
- Doc style in `docs/howto-build.md` (numbered anchors, bullet lists, fenced code blocks).

**Test scenarios:**
- Happy path: `grep -rnE "\b(npm|node|npx)\b" --include="*.sh"` returns only (b) or (c) category hits after this unit completes.
- Happy path: a reader following the updated `docs/howto-build.md` can complete a full dev build with Bun as the primary tool.
- Edge case: a script with no Node/npm hits but no existing changelog block is left unchanged (R7 only applies to modified scripts).
- Integration: running the full `./dev/build.sh -p` (build + package) on macOS completes, producing an installable `.dmg` identical to pre-migration.

**Verification:**
- No unaudited harness-side `node`/`npm` invocations remain.
- `docs/howto-build.md` is internally consistent — every mention of `node` or `npm` has a clear "why still referenced" context.
- All modified `*.sh` scripts in this unit carry changelog blocks.

---

## System-Wide Impact

- **Interaction graph:** `dev/build.sh` → `get_repo.sh` → `build.sh` → `prepare_vscode.sh` + inline gulp/policy calls. Every node in this graph is touched by U3/U4/U5. CI workflow graph: `ci-build-*.yml` jobs consume `setup-node` outputs today; after U6 they also consume `setup-bun` outputs, and all harness steps read from the Bun PATH.
- **Error propagation:** `set -ex` is preserved in every modified shell script — Bun exit codes propagate identically to Node/npm exit codes. The new `BUN_VSCODE_INSTALL` gate in U4 preserves the existing 5-retry loop semantics for both paths.
- **State lifecycle risks:** `npm ci` inside `vscode/` creates `node_modules/` with specific lifecycle-script-driven state (native module `.node` files, pre-compiled binaries). If `bun install` produces a structurally equivalent but not byte-identical tree, downstream gulp tasks may behave subtly differently. U4's verification step (full dev build diff) is designed to catch this.
- **API surface parity:** No external API surface changes. Consumers of VSCodium binaries see no difference. CI consumers (downstream releases repo) see new `oven-sh/setup-bun` steps in workflow YAML — visible change to workflow consumers who read the YAML, but no functional external contract change.
- **Integration coverage:** The unit-level test scenarios exercise single scripts. The truly load-bearing integration check is U5's "full dev build on macOS" scenario and U6's "green CI run on each of 11 workflows" scenario. Without these, unit-level green does not prove system health.
- **Unchanged invariants:** `.nvmrc` file and its consumption by `actions/setup-node`; VS Code's internal `package.json` scripts and Gulpfile; `build_cli.sh` Rust/Cargo flow; patch management in `patches/`; Snap packaging in `stores/snapcraft/`; the produced VSCodium binary's embedded Electron+Node runtime.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `bun install` inside `vscode/` produces a broken `node_modules/` tree that gulp tasks cannot consume | Med | High | U4 `BUN_VSCODE_INSTALL` env gate with `npm ci` fallback; U4 verification requires a full dev build diff before merge |
| `bun run gulp <task>` behaves differently from `npm run gulp <task>` for one of the 9 tasks | Low | High | U5 verification runs all 9 tasks end-to-end on macOS; any discrepancy reverts that specific `bun run` to `npm run` without blocking the rest of the migration |
| `npm_config_arch` cross-compile env var is ignored by Bun's install path, breaking the Linux arm64/arm/riscv64/loong64/ppc64/s390x matrix | Med | High | U6 verification runs the full Linux matrix in CI; if any arch fails, pin that specific matrix entry to `BUN_VSCODE_INSTALL=no` temporarily |
| `oven-sh/setup-bun` action SHA drift or supply chain concern | Low | Med | Pin via `pinact` (existing `just ci-update` task); review action source before pinning |
| Bun version divergence between `font-size/` (U2) and root (U1) | Low | Low | U2 deletes `font-size/.nvmrc` and relies on root `.bun-version` — single source of truth |
| Windows Git Bash cannot locate Bun binary on PATH | Med | Med | U7 updates `docs/howto-build.md` Windows section; fall back to documenting an explicit PATH export if needed |
| User-global CLAUDE.md changelog requirement (R7) drifts out of sync with the codebase's current lack of changelogs | Low | Low | R7 is scoped to *modified* scripts only; this plan does not retroactively add changelogs to untouched scripts |
| Revert complexity if Bun migration proves untenable mid-rollout | Med | Med | Unit-by-unit commit strategy; each unit is independently revertible via `git revert`; U4's env gate provides a per-CI-run escape hatch without a revert |

---

## Documentation / Operational Notes

- `docs/howto-build.md` updates span U1 (initial dependency list), U4 (new `BUN_VSCODE_INSTALL` env var), and U7 (final pass). Keep edits consolidated in U7 where feasible to avoid merge churn across units.
- `CONTRIBUTING.md` — audit in U7 for any Node/npm-specific contributor guidance that needs updating.
- After U6 merges, watch the first few CI runs closely for flaky Bun install failures. The 5-retry loop in U4 should absorb transient network issues, but Bun-specific retryable errors may differ from npm's.
- No rollout feature flag beyond the `BUN_VSCODE_INSTALL` env var. The CI change is effectively "live" the moment it merges to `master`.

---

## Sources & References

- Existing build scripts: `build.sh`, `prepare_vscode.sh`, `prepare_src.sh`, `dev/build.sh`, `build/linux/install_nodejs.sh`
- Existing CI workflows: `.github/workflows/ci-build-{linux,macos,windows}.yml` and `publish-*-*.yml`
- Existing docs: `docs/howto-build.md`
- `font-size/` helper package manifest and config files
- User-global CLAUDE.md at `~/.claude/CLAUDE.md` — shell script changelog convention (R7)
- External: Bun documentation (`bun install`, `bun run`, `bun x`) — retrieve current version string at U1 implementation time
- External: `oven-sh/setup-bun@v2` GitHub Action — SHA to be pinned at U6 implementation time

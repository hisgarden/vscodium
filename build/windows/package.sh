#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

tar -xzf ./vscode.tar.gz

cd vscode || { echo "'vscode' dir not found"; exit 1; }

# BUN_VSCODE_INSTALL=no (default) uses `npm ci` — VS Code's nested overrides
# are not yet supported by Bun. Set =yes to opt into Bun.
: "${BUN_VSCODE_INSTALL:=no}"

for i in {1..5}; do # try 5 times
  if [[ "${BUN_VSCODE_INSTALL}" == "yes" ]]; then
    bun install --frozen-lockfile && break
  else
    npm ci && break
  fi
  if [[ $i == 5 ]]; then
    echo "Install failed too many times (BUN_VSCODE_INSTALL=${BUN_VSCODE_INSTALL})" >&2
    exit 1
  fi
  echo "Install failed $i, trying again..."
done

bun build/azure-pipelines/distro/mixin-npm.ts

# delete native files built in the `compile` step
find .build/extensions -type f -name '*.node' -print -delete

. ../build/windows/rtf/make.sh

# generate Group Policy definitions
bun build/lib/policies/copyPolicyDto.ts
bun build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc win32

bun run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

. ../build_cli.sh

if [[ "${VSCODE_ARCH}" == "x64" ]]; then
  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    echo "Building REH"
    bun run gulp minify-vscode-reh
    bun run gulp "vscode-reh-win32-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    echo "Building REH-web"
    bun run gulp minify-vscode-reh-web
    bun run gulp "vscode-reh-web-win32-${VSCODE_ARCH}-min-ci"
  fi
fi

cd ..

################################################################################
# Changelog:
# 2026-04-24  Route installs, TS runs, and gulp through Bun; add
#             BUN_VSCODE_INSTALL=no gate for npm ci fallback.
################################################################################

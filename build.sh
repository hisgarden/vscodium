#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

. version.sh

if [[ "${SHOULD_BUILD}" == "yes" ]]; then
  echo "MS_COMMIT=\"${MS_COMMIT}\""

  . prepare_vscode.sh

  cd vscode || { echo "'vscode' dir not found"; exit 1; }

  export NODE_OPTIONS="--max-old-space-size=8192"

  bun run monaco-compile-check
  bun run valid-layers-check

  bun run gulp compile-build-without-mangling
  bun run gulp compile-extension-media
  bun run gulp compile-extensions-build
  bun run gulp minify-vscode

  if [[ "${OS_NAME}" == "osx" ]]; then
    # remove win32 node modules
    rm -f .build/extensions/ms-vscode.js-debug/src/win32-app-container-tokens.*.node

    # generate Group Policy definitions
    bun run copy-policy-dto --prefix build
    bun build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc darwin

    bun run gulp "vscode-darwin-${VSCODE_ARCH}-min-ci"

    find "../VSCode-darwin-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

    . ../build_cli.sh

    VSCODE_PLATFORM="darwin"
  elif [[ "${OS_NAME}" == "windows" ]]; then
    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      . ../build/windows/rtf/make.sh

      # generate Group Policy definitions
      bun run copy-policy-dto --prefix build
      bun build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc win32

      bun run gulp "vscode-win32-${VSCODE_ARCH}-min-ci"

      if [[ "${VSCODE_ARCH}" != "x64" ]]; then
        SHOULD_BUILD_REH="no"
        SHOULD_BUILD_REH_WEB="no"
      fi

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="win32"
  else # linux
    # remove win32 node modules
    rm -f .build/extensions/ms-vscode.js-debug/src/win32-app-container-tokens.*.node

    # in CI, packaging will be done by a different job
    if [[ "${CI_BUILD}" == "no" ]]; then
      # generate Group Policy definitions
      bun run copy-policy-dto --prefix build
      bun build/lib/policies/policyGenerator.ts build/lib/policies/policyData.jsonc linux

      bun run gulp "vscode-linux-${VSCODE_ARCH}-min-ci"

      find "../VSCode-linux-${VSCODE_ARCH}" -print0 | xargs -0 touch -c

      . ../build_cli.sh
    fi

    VSCODE_PLATFORM="linux"
  fi

  if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
    bun run gulp minify-vscode-reh
    bun run gulp "vscode-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
    bun run gulp minify-vscode-reh-web
    bun run gulp "vscode-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-min-ci"
  fi

  cd ..
fi

################################################################################
# Changelog:
# 2026-04-24  Route all `npm run` and `node <script>.ts` invocations through
#             Bun (bun run / bun <script>.ts). Keep NODE_OPTIONS for spawned
#             Node processes inside Gulp tasks.
################################################################################

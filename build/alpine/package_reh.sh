#!/usr/bin/env bash
# shellcheck disable=SC1091

set -ex

if [[ "${CI_BUILD}" == "no" ]]; then
  exit 1
fi

# include common functions
. ./utils.sh

mkdir -p assets

tar -xzf ./vscode.tar.gz

cd vscode || { echo "'vscode' dir not found"; exit 1; }

export VSCODE_PLATFORM='alpine'
export VSCODE_SKIP_NODE_VERSION_CHECK=1

VSCODE_HOST_MOUNT="$( pwd )"
VSCODE_REMOTE_DEPENDENCIES_CONTAINER_NAME="vscodium/vscodium-linux-build-agent:alpine-${VSCODE_ARCH}"

export VSCODE_HOST_MOUNT VSCODE_REMOTE_DEPENDENCIES_CONTAINER_NAME

if [[ -d "../patches/alpine/reh/" ]]; then
  for file in "../patches/alpine/reh/"*.patch; do
    if [[ -f "${file}" ]]; then
      apply_patch "${file}"
    fi
  done
fi

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

if [[ "${VSCODE_ARCH}" == "x64" ]]; then
  PA_NAME="linux-alpine"
else
  PA_NAME="alpine-arm64"
fi

if [[ "${SHOULD_BUILD_REH}" != "no" ]]; then
  echo "Building REH"
  bun run gulp minify-vscode-reh
  bun run gulp "vscode-reh-${PA_NAME}-min-ci"

  pushd "../vscode-reh-${PA_NAME}"

  echo "Archiving REH"
  tar czf "../assets/${APP_NAME_LC}-reh-${VSCODE_PLATFORM}-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .

  popd
fi

if [[ "${SHOULD_BUILD_REH_WEB}" != "no" ]]; then
  echo "Building REH-web"
  bun run gulp minify-vscode-reh-web
  bun run gulp "vscode-reh-web-${PA_NAME}-min-ci"

  pushd "../vscode-reh-web-${PA_NAME}"

  echo "Archiving REH-web"
  tar czf "../assets/${APP_NAME_LC}-reh-web-${VSCODE_PLATFORM}-${VSCODE_ARCH}-${RELEASE_VERSION}.tar.gz" .

  popd
fi

cd ..

sum_file() {
  if [[ -f "${1}" ]]; then
    echo "Calculating checksum for ${1}"
    bun x checksum -a sha256 "${1}" > "${1}".sha256
    bun x checksum "${1}" > "${1}".sha1
  fi
}

cd assets

for FILE in *; do
  if [[ -f "${FILE}" ]]; then
    sum_file "${FILE}"
  fi
done

cd ..

################################################################################
# Changelog:
# 2026-04-24  Route installs, mixin-npm, gulp, and checksum through Bun; add
#             BUN_VSCODE_INSTALL=no gate for npm ci fallback.
################################################################################

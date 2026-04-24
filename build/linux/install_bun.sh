#!/usr/bin/env bash

set -ex

BUN_VERSION=$( cat .bun-version )

curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${BUN_ARCH}.zip" -o bun.zip

unzip -q bun.zip

sudo mv "bun-linux-${BUN_ARCH}" /usr/local/bun

echo "/usr/local/bun" >> $GITHUB_PATH

################################################################################
# Changelog:
# 2026-04-24  Initial Bun installer mirroring install_nodejs.sh structure.
################################################################################

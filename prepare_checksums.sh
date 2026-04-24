#!/usr/bin/env bash

set -e

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
# 2026-04-24  Replace `npm install -g checksum` with `bun x checksum`.
################################################################################

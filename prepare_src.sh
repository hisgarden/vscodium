#!/usr/bin/env bash
# shellcheck disable=SC1091

set -e

sum_file() {
  if [[ -f "${1}" ]]; then
    echo "Calculating checksum for ${1}"
    bun x checksum -a sha256 "${1}" > "${1}".sha256
    bun x checksum "${1}" > "${1}".sha1
  fi
}

mkdir -p assets

git archive --format tar.gz --output="./assets/${APP_NAME}-${RELEASE_VERSION}-src.tar.gz" HEAD
git archive --format zip --output="./assets/${APP_NAME}-${RELEASE_VERSION}-src.zip" HEAD

if [[ "${VSCODE_QUALITY}" == "insider" ]]; then
  COMMIT_ID=$( git rev-parse HEAD )

  jsonTmp=$( jq -n --arg 'tag' "${RELEASE_VERSION}" --arg 'id' "${BUILD_SOURCEVERSION}" --arg 'commit' "${COMMIT_ID}" '{ "tag": $tag, "id": $id, "commit": $commit }' )
  echo "${jsonTmp}" > "./assets/buildinfo.json" && unset jsonTmp
fi

cd assets

for FILE in *; do
  if [[ -f "${FILE}" ]]; then
    sum_file "${FILE}"
  fi
done

cd ..

################################################################################
# Changelog:
# 2026-04-24  Replace `npm install -g checksum` with ephemeral `bun x checksum`.
################################################################################

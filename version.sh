#!/usr/bin/env bash

if [[ -z "${BUILD_SOURCEVERSION}" ]]; then

    if type -t "sha1sum" &> /dev/null; then
      BUILD_SOURCEVERSION=$( echo "${RELEASE_VERSION/-*/}" | sha1sum | cut -d' ' -f1 )
    else
      BUILD_SOURCEVERSION=$( echo "${RELEASE_VERSION/-*/}" | bun x checksum )
    fi

    echo "BUILD_SOURCEVERSION=\"${BUILD_SOURCEVERSION}\""

    # for GH actions
    if [[ "${GITHUB_ENV}" ]]; then
        echo "BUILD_SOURCEVERSION=${BUILD_SOURCEVERSION}" >> "${GITHUB_ENV}"
    fi
fi

export BUILD_SOURCEVERSION

################################################################################
# Changelog:
# 2026-04-24  Use `bun x checksum` instead of `npm install -g checksum` on the
#             sha1sum-missing fallback path.
################################################################################
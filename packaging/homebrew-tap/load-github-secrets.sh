#!/usr/bin/env bash
# Upload Apple codesign + notarization credentials to GitHub Actions secrets
# on the `publish` environment of hisgarden/vscodium.
#
# Mirrors the QuickRecorder pattern (Keychain-backed credentials) but writes
# the results to GitHub Actions so publish-stable-macos.yml can use them.
#
# Prerequisites:
#   1. You have a Developer ID Application .p12 export:
#      Keychain Access.app → your "Developer ID Application: ..." cert →
#      right-click → Export... → .p12 format → set an export password
#   2. Your Apple app-specific password is in Keychain under
#      service "hisgarden", account "notarize" (QuickRecorder convention).
#   3. `gh auth status` works and you have admin access to hisgarden/vscodium.
#
# Usage:
#   ./packaging/homebrew-tap/load-github-secrets.sh /path/to/DeveloperID.p12
#
# The script will prompt (hidden input) for:
#   - the .p12 export password
# and auto-detect the rest from Keychain / git config.

set -euo pipefail

REPO="${REPO:-hisgarden/vscodium}"
ENVIRONMENT="${ENVIRONMENT:-publish}"
KEYCHAIN_SERVICE="${KEYCHAIN_SERVICE:-hisgarden}"
APPLE_ID_DEFAULT="$(git config --global user.email 2>/dev/null || true)"
TEAM_ID_DEFAULT="NSDC3EDS2G"  # from QuickRecorder/project.yml DEVELOPMENT_TEAM

P12_PATH="${1:-}"
if [[ -z "${P12_PATH}" ]]; then
  echo "Usage: $0 /path/to/DeveloperID.p12" >&2
  exit 2
fi
if [[ ! -f "${P12_PATH}" ]]; then
  echo "error: .p12 not found at: ${P12_PATH}" >&2
  exit 2
fi

echo "=== load GitHub Actions secrets for ${REPO} (env: ${ENVIRONMENT}) ==="
echo

# --- Apple ID
apple_id="$(security find-internet-password -s "${KEYCHAIN_SERVICE}" -a appleid 2>/dev/null \
            | awk -F\" '/"acct"<blob>=/{print $2}' || true)"
apple_id="${apple_id:-${APPLE_ID_DEFAULT}}"
read -r -p "Apple ID [${apple_id}]: " input
apple_id="${input:-${apple_id}}"
if [[ -z "${apple_id}" ]]; then
  echo "error: Apple ID is required" >&2
  exit 1
fi

# --- Team ID
read -r -p "Apple Team ID [${TEAM_ID_DEFAULT}]: " input
team_id="${input:-${TEAM_ID_DEFAULT}}"

# --- App-specific password (from Keychain under service/notarize)
echo "-> fetching app-specific password from Keychain (service=${KEYCHAIN_SERVICE}, account=notarize)"
app_password="$(security find-internet-password -s "${KEYCHAIN_SERVICE}" -a notarize -w 2>/dev/null || true)"
if [[ -z "${app_password}" ]]; then
  echo "   not in Keychain — prompting (hidden input):"
  read -r -s -p "   App-specific password: " app_password
  echo
fi

# --- .p12 export password
read -r -s -p ".p12 export password: " p12_password
echo

# --- Base64-encode the .p12
echo "-> base64-encoding ${P12_PATH}"
p12_data="$(base64 -i "${P12_PATH}")"

# --- Optional: STRONGER_GITHUB_TOKEN (PAT for hisgarden/versions) and TAP_DISPATCH_TOKEN
# Leave blank to skip either — only prompts if not already set.
read -r -s -p "STRONGER_GITHUB_TOKEN (PAT w/ repo scope for hisgarden/versions; blank to skip): " stronger_token
echo
read -r -s -p "TAP_DISPATCH_TOKEN (PAT w/ repo scope for hisgarden/homebrew-tap; blank to skip): " tap_token
echo

# --- Upload
put_secret() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    echo "   skipping ${name} (empty)"
    return 0
  fi
  printf '%s' "${value}" | gh secret set "${name}" --env "${ENVIRONMENT}" --repo "${REPO}" --body -
}

echo
echo "=== uploading to ${REPO} env=${ENVIRONMENT} ==="
put_secret CERTIFICATE_OSX_NEW_ID           "${apple_id}"
put_secret CERTIFICATE_OSX_NEW_TEAM_ID      "${team_id}"
put_secret CERTIFICATE_OSX_NEW_APP_PASSWORD "${app_password}"
put_secret CERTIFICATE_OSX_NEW_P12_DATA     "${p12_data}"
put_secret CERTIFICATE_OSX_NEW_P12_PASSWORD "${p12_password}"
put_secret STRONGER_GITHUB_TOKEN            "${stronger_token}"
put_secret TAP_DISPATCH_TOKEN               "${tap_token}"

echo
echo "=== done ==="
echo "Verify at: https://github.com/${REPO}/settings/environments/${ENVIRONMENT}"
echo
echo "Next: trigger a publish run:"
echo "  gh workflow run publish-stable-macos.yml -R ${REPO}"

################################################################################
# Changelog:
# 2026-04-24  Initial — load Apple codesign + notarization secrets from the
#             QuickRecorder-style Keychain layout into GitHub Actions.
################################################################################

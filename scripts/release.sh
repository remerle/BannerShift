#!/usr/bin/env bash
#
# MANUAL / BREAK-GLASS release build. You normally should NOT need this.
#
# The primary, supported way to cut a release is to push a `v*` git tag and let
# .github/workflows/release.yml sign, notarize, and publish (see docs/release.md).
# Use this script only when GitHub Actions is unavailable, or to reproduce a
# notarization failure locally.
#
# Caveat: this builds the version baked into Resources/Info.plist (a static
# placeholder), NOT a tag-derived version like the CI workflow does. Treat its
# artifacts as test/break-glass builds unless you bump Info.plist deliberately.
#
# Does: clean → universal swift build → Developer ID sign → notarize → staple →
# package. Reads .env produced by scripts/populate-secrets.sh.

set -euo pipefail

# This script lives in scripts/; the repo root is its parent.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

# Remove the intermediate notarization ZIP on any exit so a SIGINT,
# notarytool timeout, or rejection branch does not leave a signed
# artifact behind in build/.
ZIP_TO_CLEAN=""
cleanup() {
    [[ -n "${ZIP_TO_CLEAN}" && -f "${ZIP_TO_CLEAN}" ]] && rm -f "${ZIP_TO_CLEAN}"
}
trap cleanup EXIT INT TERM

[[ -f "${ROOT}/.env" ]] || {
    echo "Missing .env. Run ./populate-secrets.sh first." >&2
    exit 1
}
# shellcheck disable=SC1091
source "${ROOT}/.env"

: "${DEVELOPER_ID_APPLICATION:?missing in .env}"
: "${AC_API_KEY_PATH:?missing in .env}"
: "${AC_API_KEY_ID:?missing in .env}"
: "${AC_API_ISSUER_ID:?missing in .env}"

# Verify required tools are available before doing any work. Surfacing a
# complete list up-front beats failing several minutes into a build with
# an opaque "command not found".
missing_tools=()
for cmd in op codesign xcrun ditto tar python3; do
    command -v "${cmd}" >/dev/null 2>&1 || missing_tools+=("${cmd}")
done
[[ -x /usr/libexec/PlistBuddy ]] || missing_tools+=("/usr/libexec/PlistBuddy")
if (( ${#missing_tools[@]} > 0 )); then
    echo "Missing required tools: ${missing_tools[*]}" >&2
    echo "Install Xcode Command Line Tools and/or 1Password CLI, then retry." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy   -c 'Print :CFBundleVersion'             Resources/Info.plist)"
APP="${ROOT}/build/BannerShift.app"
ZIP="${ROOT}/build/BannerShift-${VERSION}.zip"
TAR="${ROOT}/build/BannerShift-${VERSION}.tar.gz"

log() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }

log "clean"
rm -rf "${ROOT}/build" "${ROOT}/.build"

log "build universal (ad-hoc; we re-sign below)"
"${ROOT}/scripts/build-dev.sh"

log "Developer ID sign"
codesign --force --sign "${DEVELOPER_ID_APPLICATION}" \
    --entitlements "${ROOT}/Resources/BannerShift.entitlements" \
    --options runtime \
    --timestamp \
    "${APP}"

log "verify signature"
codesign --verify --deep --strict --verbose=2 "${APP}"

log "notarize"
rm -f "${ZIP}"
ZIP_TO_CLEAN="${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
# notarytool submit --wait reaches terminal state for both Accepted and
# Invalid, so capture the JSON and parse status ourselves rather than rely
# on exit code. On non-Accepted, fetch Apple's log to surface the reason.
SUBMIT_JSON="$(xcrun notarytool submit "${ZIP}" \
    --key       "${AC_API_KEY_PATH}" \
    --key-id    "${AC_API_KEY_ID}" \
    --issuer    "${AC_API_ISSUER_ID}" \
    --wait \
    --output-format json)"

SUBMISSION_ID="$(echo "${SUBMIT_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
STATUS="$(       echo "${SUBMIT_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")"
log "Submission ${SUBMISSION_ID} terminal status: ${STATUS}"

if [[ "${STATUS}" != "Accepted" ]]; then
    printf '\033[1;33m!!!\033[0m Notarization did not succeed. Fetching Apple log...\n' >&2
    xcrun notarytool log "${SUBMISSION_ID}" \
        --key    "${AC_API_KEY_PATH}" \
        --key-id "${AC_API_KEY_ID}" \
        --issuer "${AC_API_ISSUER_ID}" >&2 || true
    printf '\033[1;31mxxx\033[0m Notarization failed: %s\n' "${STATUS}" >&2
    exit 1
fi

log "staple"
xcrun stapler staple   "${APP}"
xcrun stapler validate "${APP}"
# Confirm Gatekeeper will actually accept the stapled bundle. Informational
# only: dev-machine Gatekeeper state can differ from end-user, so don't
# abort an otherwise-successful build.
spctl --assess --type execute -vv "${APP}" || true
# Intermediate notarization artifact; the .tar.gz is the distributable.
# The trap also handles cleanup on abnormal exits.
rm -f "${ZIP}"
ZIP_TO_CLEAN=""

log "package"
( cd "${ROOT}/build" && tar -czf "${TAR}" "BannerShift.app" )

log "done"
echo "  app: ${APP}"
echo "  tar: ${TAR}"
echo "  version: ${VERSION} (build ${BUILD})"

#!/usr/bin/env bash
#
# One-shot: pull build secrets out of 1Password and materialize them locally.
#
# Writes:
#   .env                       env vars consumed by release.sh
#   .secrets/AuthKey.p8        App Store Connect API key (mode 0600)
#
# Optional (--import-certs): also pull the Developer ID .p12 files and import
# them into the login keychain, scoped to codesign/security/productsign.
# The .p12 files are removed after a successful import. Only needed on a
# fresh machine where the certs are not yet present.
#
# Re-running is safe; outputs are overwritten.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/.secrets"
ENV_FILE="${SCRIPT_DIR}/.env"

VAULT="ynbhaihbhz2iftkuvbe2k4liya"
APP_CERT_ITEM="dsvkem2kue3kn6x5ibpuagogh4"
INSTALLER_CERT_ITEM="ponn4sb2mcg7a2kczvykvhy2ra"
ASC_ITEM="nxhn5e7x3tl57y6dh4h3m6tllm"

APP_P12_FILENAME="Developer ID Private Key.p12"
INSTALLER_P12_FILENAME="Developer ID Installer Private Key.p12"
# ASC_KEY_FILENAME is read at runtime from the 1Password ASC item's
# "key filename" field, so the App Store Connect Key ID never lands in this
# script. See README "Locally (via 1Password)" for the required field layout.

# Track p12 files for cleanup on any exit (success, error, signal). The
# trap ensures secret material does not persist on disk if the script aborts
# between fetch and import.
TMP_P12S=()
cleanup() {
    local f
    for f in "${TMP_P12S[@]+"${TMP_P12S[@]}"}"; do
        [[ -n "${f}" && -f "${f}" ]] && rm -f "${f}"
    done
}
trap cleanup EXIT INT TERM

IMPORT_CERTS=0
for arg in "$@"; do
    case "${arg}" in
        --import-certs) IMPORT_CERTS=1 ;;
        -h|--help)
            sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown arg: ${arg}" >&2; exit 2 ;;
    esac
done

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!!\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31mxxx\033[0m %s\n" "$*" >&2; exit 1; }

command -v op >/dev/null 2>&1 || die "1Password CLI 'op' not found in PATH."
op whoami >/dev/null 2>&1     || die "1Password CLI not signed in. See README."

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

# ---------------------------------------------------------------------------
# Fetch App Store Connect API key + identifiers
# ---------------------------------------------------------------------------

log "Reading App Store Connect key metadata..."
AC_KEY_ID="$(op read "op://${VAULT}/${ASC_ITEM}/key id")"
AC_ISSUER_ID="$(op read "op://${VAULT}/${ASC_ITEM}/issuer id")"
ASC_KEY_FILENAME="$(op read "op://${VAULT}/${ASC_ITEM}/key filename")"
[[ -n "${AC_KEY_ID}"        ]] || die "key id field is empty"
[[ -n "${AC_ISSUER_ID}"     ]] || die "issuer id field is empty"
[[ -n "${ASC_KEY_FILENAME}" ]] || die "key filename field is empty. Add a 'key filename' text field to the ASC item in 1Password whose value matches the attached .p8 filename (e.g. AuthKey_XXXXXXXXXX.p8)."

log "Fetching App Store Connect API key from 1Password..."
P8_PATH="${SECRETS_DIR}/AuthKey.p8"
op read --out-file "${P8_PATH}" \
    "op://${VAULT}/${ASC_ITEM}/${ASC_KEY_FILENAME}" >/dev/null
chmod 600 "${P8_PATH}"
[[ -s "${P8_PATH}" ]] || die "Fetched .p8 is empty: ${P8_PATH}"

# ---------------------------------------------------------------------------
# Discover Developer ID identity strings from the keychain
# ---------------------------------------------------------------------------

discover_identity() {
    local label="$1"   # e.g. "Developer ID Application"
    local policy="$2"  # codesigning | basic
    # Output of `security find-identity -v -p <policy>` looks like:
    #   1) ABCDEF... "Developer ID Application: Ryan Emerle (VV49L2HH35)"
    security find-identity -v -p "${policy}" 2>/dev/null \
        | awk -v lbl="${label}" '
            {
                # Extract the quoted identity name.
                match($0, /"[^"]+"/);
                if (RSTART == 0) next;
                name = substr($0, RSTART+1, RLENGTH-2);
                if (index(name, lbl) == 1) print name;
            }' \
        | head -n1
}

if [[ "${IMPORT_CERTS}" == "1" ]]; then
    log "Importing Developer ID .p12 certificates into login keychain..."
    for entry in \
        "app:${APP_CERT_ITEM}:${APP_P12_FILENAME}" \
        "installer:${INSTALLER_CERT_ITEM}:${INSTALLER_P12_FILENAME}"
    do
        kind="${entry%%:*}"; rest="${entry#*:}"
        item="${rest%%:*}"; file="${rest#*:}"
        p12="${SECRETS_DIR}/${kind}.p12"
        TMP_P12S+=("${p12}")
        log "  Fetching ${item} / ${file}"
        op read --out-file "${p12}" "op://${VAULT}/${item}/${file}" >/dev/null
        chmod 600 "${p12}"

        # The .p12 export password is stored in the 1Password item's Notes
        # field by convention. If the field is empty or the value is wrong,
        # security import aborts loudly rather than silently no-opping; the
        # script does not attempt an interactive prompt fallback.
        pass="$(op read "op://${VAULT}/${item}/notesPlain" 2>/dev/null || true)"
        # Scope the imported private key to codesign / security / productsign
        # only, matching the CI workflow. -A (allow any app) would grant every
        # process on the machine the ability to use the key without a prompt.
        import_args=(
            "${p12}"
            -k "${HOME}/Library/Keychains/login.keychain-db"
            -T /usr/bin/codesign
            -T /usr/bin/security
            -T /usr/bin/productsign
        )
        if [[ -n "${pass}" ]]; then
            # Capture exit status of `security import` independently from any
            # downstream filtering. A non-zero exit other than "already in
            # keychain" is fatal — silent failure here surfaces later as an
            # opaque codesign "no identity found" error.
            if ! out="$(security import "${import_args[@]}" -P "${pass}" 2>&1)"; then
                if grep -q "already in keychain" <<<"${out}"; then
                    log "  ${kind}: already in keychain"
                else
                    die "security import failed for ${kind}: ${out}. Verify the Notes field of the 1Password item contains the .p12 export password."
                fi
            fi
        else
            warn "  No passphrase available; security import will prompt."
            security import "${import_args[@]}"
        fi
        rm -f "${p12}"
    done
fi

log "Discovering Developer ID identities from login keychain..."
DEVELOPER_ID_APPLICATION="$(discover_identity 'Developer ID Application' codesigning)"
DEVELOPER_ID_INSTALLER="$(discover_identity   'Developer ID Installer'   basic)"

if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
    die "No 'Developer ID Application' identity in login keychain. Re-run with --import-certs."
fi
if [[ -z "${DEVELOPER_ID_INSTALLER}" ]]; then
    warn "No 'Developer ID Installer' identity in login keychain. The current release pipeline does not use it; .env will omit DEVELOPER_ID_INSTALLER. Re-run with --import-certs if you plan to add a .pkg build."
fi

# ---------------------------------------------------------------------------
# Write .env (overwrites)
# ---------------------------------------------------------------------------

log "Writing ${ENV_FILE}"
{
    cat <<EOF
# Generated by populate-secrets.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# DO NOT COMMIT. Regenerate with ./populate-secrets.sh

export DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION}"
export AC_API_KEY_PATH="${P8_PATH}"
export AC_API_KEY_ID="${AC_KEY_ID}"
export AC_API_ISSUER_ID="${AC_ISSUER_ID}"
EOF
    if [[ -n "${DEVELOPER_ID_INSTALLER}" ]]; then
        printf 'export DEVELOPER_ID_INSTALLER="%s"\n' "${DEVELOPER_ID_INSTALLER}"
    fi
} > "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

log "Done."
log "Identity (app)      : ${DEVELOPER_ID_APPLICATION}"
if [[ -n "${DEVELOPER_ID_INSTALLER}" ]]; then
    log "Identity (installer): ${DEVELOPER_ID_INSTALLER}"
fi
log "API key             : ${P8_PATH}"
log "Now run: ./release.sh"

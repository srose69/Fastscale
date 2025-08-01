#!/bin/bash
set -euo pipefail
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
BASE_DIR="$(pwd)/htscale"
CONFIG_FILE="${BASE_DIR}/config/config.yaml"

log() {
    echo -e "${BLUE}[$(date '+%T')]${NC} ${1}"
}

die() {
    echo -e "\n${RED}${BOLD}ERROR:${NC} $1" >&2
    exit 1
}

log "${BOLD}=== OIDC Configuration Script for Headscale ===${NC}"

if [ ! -f "${CONFIG_FILE}" ]; then
    die "Configuration file ${CONFIG_FILE} not found. \nPlease run this script from the same directory where the 'htscale' folder is located."
fi

log "This script will help you configure OIDC authentication."

read -p "Enter OIDC Issuer URL (e.g., https://accounts.google.com): " OIDC_ISSUER
read -p "Enter OIDC Client ID: " OIDC_CLIENT_ID
read -s -p "Enter OIDC Client Secret: " OIDC_CLIENT_SECRET
echo
read -p "Enter allowed domains, separated by commas (e.g., example.com,another.org): " OIDC_DOMAINS

if grep -q "^oidc:" "${CONFIG_FILE}"; then
    log "${YELLOW}Existing OIDC configuration detected. It will be replaced.${NC}"
    awk '
        /^oidc:/ {p=1; next}
        /^[a-zA-Z]/ {p=0}
        !p
    ' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
fi

log "Adding new OIDC configuration to ${BOLD}${CONFIG_FILE}${NC}..."

cat >> "${CONFIG_FILE}" <<EOF

oidc:
  issuer: ${OIDC_ISSUER}
  client_id: ${OIDC_CLIENT_ID}
  client_secret: ${OIDC_CLIENT_SECRET}
  scope: ["openid", "profile", "email"]
  allowed_domains:
EOF

IFS=',' read -ra DOMAIN_ARRAY <<< "$OIDC_DOMAINS"
for domain in "${DOMAIN_ARRAY[@]}"; do
    trimmed_domain=$(echo "$domain" | xargs)
    if [ -n "$trimmed_domain" ]; then
        echo "    - ${trimmed_domain}" >> "${CONFIG_FILE}"
    fi
done

log "${GREEN}Configuration successfully updated.${NC}"

log "Restarting Headscale container to apply changes..."
cd "${BASE_DIR}"
if docker compose restart headscale; then
    log "${GREEN}${BOLD}Done! Headscale has been restarted with the new OIDC configuration.${NC}"
else
    die "Failed to restart the headscale container. Check the logs: docker compose logs headscale"
fi

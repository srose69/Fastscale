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
    echo -e "\n${RED}${BOLD}ОШИБКА:${NC} $1" >&2
    exit 1
}

log "${BOLD}=== Скрипт настройки OIDC для Headscale ===${NC}"

if [ ! -f "${CONFIG_FILE}" ]; then
    die "Конфигурационный файл ${CONFIG_FILE} не найден. \nЗапустите этот скрипт из той же директории, где лежит папка 'htscale'."
fi

log "Этот скрипт поможет вам настроить OIDC аутентификацию."

read -p "Введите OIDC Issuer URL (например, https://accounts.google.com): " OIDC_ISSUER
read -p "Введите OIDC Client ID: " OIDC_CLIENT_ID
read -s -p "Введите OIDC Client Secret: " OIDC_CLIENT_SECRET
echo
read -p "Введите разрешенные домены через запятую (например, example.com,another.org): " OIDC_DOMAINS

if grep -q "^oidc:" "${CONFIG_FILE}"; then
    log "${YELLOW}Обнаружена существующая OIDC конфигурация. Она будет заменена.${NC}"
    awk '
        /^oidc:/ {p=1; next}
        /^[a-zA-Z]/ {p=0}
        !p
    ' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
fi

log "Добавление новой OIDC конфигурации в ${BOLD}${CONFIG_FILE}${NC}..."

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

log "${GREEN}Конфигурация успешно обновлена.${NC}"

log "Перезапуск контейнера Headscale для применения изменений..."
cd "${BASE_DIR}"
if docker compose restart headscale; then
    log "${GREEN}${BOLD}Готово! Headscale перезапущен с новой OIDC конфигурацией.${NC}"
else
    die "Не удалось перезапустить контейнер headscale. Проверьте логи: docker compose logs headscale"
fi

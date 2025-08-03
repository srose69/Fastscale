#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${SCRIPT_DIR}/install_${TIMESTAMP}.log"
BASE_DIR="${SCRIPT_DIR}/htscale"
DOMAIN=""
EMAIL=""
SERVER_IP=""
EXISTING_NGINX=false
ACTIVATE_HEADSCALE_ADMIN=false
ACTIVATE_NGINX_UI=false
declare -A PORTS=(
    [HTTP]="80"
    [HTTPS]="443"
    [HEADSCALE]="8080"
    [HEADSCALE_ADMIN]="3001"
    [NGINX_UI]="9001"
)

log() {
    local message="$1"
    echo -e "${BLUE}[$(date '+%T')]${NC} ${message}" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $(echo -e "${message}" | sed 's/\x1b\[[0-9;]*m//g')" >> "${LOG_FILE}"
}

die() {
    log "${RED}${BOLD}КРИТИЧЕСКАЯ ОШИБКА:${NC} $1"
    if command -v docker &>/dev/null && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        log "${YELLOW}Сохранение логов Docker для диагностики...${NC}"
        (cd "${BASE_DIR}" && docker compose logs --tail=100 >> "${LOG_FILE}" 2>&1)
    fi
    log "${YELLOW}Выполняется очистка...${NC}"
    if command -v docker &>/dev/null && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        (cd "${BASE_DIR}" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
    fi
    log "${RED}Установка прервана. Проверьте лог-файл: ${BOLD}${LOG_FILE}${NC}"
    exit 1
}

trap 'die "Скрипт завершился с ошибкой в строке ${LINENO}."' ERR

version_gt() {
    [ "$(printf '%s\n' "$@" | sort -V | head -n1)" != "$1" ]
}

check_dependencies() {
    log "${YELLOW}1. Проверка системных зависимостей...${NC}"
    [ "$(id -u)" -ne 0 ] && die "Этот скрипт необходимо запускать с правами суперпользователя (sudo)."
    DOCKER_MIN_VERSION="20.10.0"
    if ! command -v docker &>/dev/null; then
        log "Docker не найден. Установка Docker..."
        curl -fsSL https://get.docker.com | sh >> "${LOG_FILE}" 2>&1
    fi
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
    if version_gt "$DOCKER_MIN_VERSION" "$DOCKER_VERSION"; then
        die "Требуется Docker версии ${DOCKER_MIN_VERSION} или выше. Найдена версия ${DOCKER_VERSION}."
    fi
    if ! docker compose version &>/dev/null; then
        log "Docker Compose не найден. Установка..."
        apt-get install -y docker-compose-plugin >> "${LOG_FILE}" 2>&1
    fi
    systemctl enable --now docker >/dev/null 2>&1
    log "Установка пакетов (lsof, jq, certbot...)"
    apt-get update -qq >> "${LOG_FILE}" 2>&1
    apt-get install -y lsof jq certbot python3-certbot-nginx >> "${LOG_FILE}" 2>&1
    log "${GREEN}Зависимости успешно проверены и установлены.${NC}"
}

collect_user_data() {
    log "${YELLOW}2. Сбор конфигурационных данных...${NC}"
    while true; do
        read -p "Введите ваш домен (например, vpn.example.com): " DOMAIN
        [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break || echo -e "${RED}Неверный формат домена.${NC}"
    done
    while true; do
        read -p "Введите ваш email (для SSL-сертификата Let's Encrypt): " EMAIL
        [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break || echo -e "${RED}Неверный формат email.${NC}"
    done
    log "Определение публичного IP-адреса..."
    SERVER_IP=$(curl -s -4 --connect-timeout 5 https://ifconfig.io || curl -s -4 --connect-timeout 5 https://ifconfig.me)
    if [ -z "$SERVER_IP" ]; then
        log "${YELLOW}Не удалось автоматически определить IP. Введите его вручную.${NC}"
        while true; do
            read -p "Введите публичный IP-адрес вашего сервера: " SERVER_IP
            [[ "$SERVER_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break || echo -e "${RED}Неверный формат IP.${NC}"
        done
    fi
    log "IP-адрес сервера: ${BOLD}${SERVER_IP}${NC}"
    log "${YELLOW}ВАЖНО: Убедитесь, что A-запись для домена ${BOLD}${DOMAIN}${NC} указывает на IP-адрес ${BOLD}${SERVER_IP}${NC}."
    read -p "Подтверждаете, что DNS настроен правильно? (y/n) " -r reply
    [[ $reply =~ ^[Yy]$ ]] || die "Установка отменена пользователем."
}

check_ports() {
    log "${YELLOW}3. Проверка доступности портов...${NC}"
    check_single_port() {
        local port="$1" service="$2" expected_process="$3"
        while true; do
            local pid; pid=$(lsof -i ":${port}" -sTCP:LISTEN -t -P -n | head -n1)
            if [ -z "$pid" ]; then
                log "Порт ${BOLD}${port}${NC} свободен для '${service}'." && echo "$port" && return
            fi
            local process_name; process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "неизвестный процесс")
            if [ -n "$expected_process" ] && [ "$process_name" == "$expected_process" ]; then
                log "${YELLOW}Обнаружен '${process_name}' на порту ${port}. Будем использовать его.${NC}"
                [[ "$expected_process" == "nginx" ]] && EXISTING_NGINX=true && echo "$port" && return
            fi
            read -p "$(printf "\n${RED}КОНФЛИКТ:${NC} Порт ${BOLD}%s${NC} для '${BOLD}%s${NC}' занят процессом '${BOLD}%s${NC}'.\n${YELLOW}Хотите изменить порт? (y/n): ${NC}" "$port" "$service" "$process_name")" -r reply
            [[ $reply =~ ^[Yy]$ ]] || die "Установка отменена из-за конфликта портов."
            while true; do
                read -p "Введите новый порт для '${service}' (1-65535): " custom_port
                if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -gt 0 ] && [ "$custom_port" -lt 65536 ]; then
                    port="$custom_port" && break
                else
                    echo -e "${RED}Неверный номер порта.${NC}"
                fi
            done
        done
    }
    PORTS[HTTP]=$(check_single_port "${PORTS[HTTP]}" "Nginx (HTTP)" "nginx")
    PORTS[HTTPS]=$(check_single_port "${PORTS[HTTPS]}" "Nginx (HTTPS)" "nginx")
    PORTS[HEADSCALE]=$(check_single_port "${PORTS[HEADSCALE]}" "Headscale" "")
    read -p "Включить веб-интерфейс headscale-admin? (y/n) " -r reply
    if [[ $reply =~ ^[Yy]$ ]]; then
        ACTIVATE_HEADSCALE_ADMIN=true && PORTS[HEADSCALE_ADMIN]=$(check_single_port "${PORTS[HEADSCALE_ADMIN]}" "headscale-admin" "")
    fi
    read -p "Включить веб-интерфейс Nginx-UI? (y/n) " -r reply
    if [[ $reply =~ ^[Yy]$ ]]; then
        ACTIVATE_NGINX_UI=true && PORTS[NGINX_UI]=$(check_single_port "${PORTS[NGINX_UI]}" "Nginx-UI" "")
    fi
    log "${GREEN}Проверка портов завершена.${NC}"
}

generate_configs() {
    log "${YELLOW}4. Генерация конфигурационных файлов...${NC}"
    mkdir -p "${BASE_DIR}"/{config,data,ts-data,nginx-ui-data,run}
    umask 077
    cat > "${BASE_DIR}/.env" <<EOF
DOMAIN=${DOMAIN}
TS_AUTHKEY=""
EOF
    cat > "${BASE_DIR}/docker-compose.yml" <<EOF
services:
  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    restart: unless-stopped
    command: serve
    volumes:
      - ./config:/etc/headscale:ro
      - ./data:/var/lib/headscale
      - ./run:/var/run/headscale
    ports:
      - "127.0.0.1:${PORTS[HEADSCALE]}:8080"
  tailscale-client:
    image: tailscale/tailscale:latest
    container_name: tailscale-client
    hostname: ${DOMAIN}-server
    network_mode: host
    cap_add: [NET_ADMIN, NET_RAW]
    volumes:
      - ./ts-data:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped
    env_file: .env
EOF
    if [ "$ACTIVATE_HEADSCALE_ADMIN" = true ]; then
        cat >> "${BASE_DIR}/docker-compose.yml" <<EOF
  headscale-admin:
    image: goodieshq/headscale-admin:latest
    container_name: headscale-admin
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PORTS[HEADSCALE_ADMIN]}:80"
EOF
    fi
    if [ "$ACTIVATE_NGINX_UI" = true ]; then
        cat >> "${BASE_DIR}/docker-compose.yml" <<EOF
  nginx-ui:
    image: uozi/nginx-ui:latest
    container_name: nginx-ui
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PORTS[NGINX_UI]}:9000"
    volumes:
      - ./nginx-ui-data:/etc/nginx-ui
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/nginx:/etc/nginx:rw
EOF
    fi
    cat > "${BASE_DIR}/config/config.yaml" <<EOF
server_url: https://${DOMAIN}
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 0.0.0.0:50443
unix_socket: /var/run/headscale/headscale.sock
database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
noise:
  private_key_path: /var/lib/headscale/noise_private.key
dns:
  magic_dns: true
  override_local_dns: true
  base_domain: ${DOMAIN//./-}.headscale
  nameservers:
    global:
      - 1.1.1.1
      - 8.8.8.8
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h
policy:
  mode: "database"
log:
  level: info
EOF
    log "${GREEN}Конфигурационные файлы успешно созданы.${NC}"
}

setup_nginx_ssl() {
    log "${YELLOW}5. Настройка Nginx и SSL-сертификата...${NC}"
    [ "$EXISTING_NGINX" = false ] && apt-get install -y nginx >> "${LOG_FILE}" 2>&1
    local NGINX_CONF="/etc/nginx/sites-available/headscale.conf"
    cat > "${NGINX_CONF}" <<EOF
server {
    listen ${PORTS[HTTP]};
    listen [::]:${PORTS[HTTP]};
    server_name ${DOMAIN};
    root /var/www/html;
    location ~ /\.well-known/acme-challenge/ { allow all; }
    location / { return 404; }
}
EOF
    ln -sf "${NGINX_CONF}" "/etc/nginx/sites-enabled/headscale.conf"
    rm -f "/etc/nginx/sites-enabled/default"
    systemctl reload-or-restart nginx >> "${LOG_FILE}" 2>&1
    if ! certbot certificates -d "${DOMAIN}" | grep -q "VALID"; then
        log "Получение SSL-сертификата для ${DOMAIN}..."
        certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" --staple-ocsp --must-staple >> "${LOG_FILE}" 2>&1
    else
        log "${GREEN}Найден существующий валидный SSL-сертификат.${NC}"
    fi
    cat > "${NGINX_CONF}" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}
server {
    listen ${PORTS[HTTP]};
    listen [::]:${PORTS[HTTP]};
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen ${PORTS[HTTPS]} ssl http2;
    listen [::]:${PORTS[HTTPS]} ssl http2;
    server_name ${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
    location / {
        proxy_pass http://127.0.0.1:${PORTS[HEADSCALE]};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
EOF
    if [ "$ACTIVATE_HEADSCALE_ADMIN" = true ]; then
        cat >> "${NGINX_CONF}" <<EOF
    location /admin/ {
        proxy_pass http://127.0.0.1:${PORTS[HEADSCALE_ADMIN]};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect / /admin;
    }
EOF
    fi
    if [ "$ACTIVATE_NGINX_UI" = true ]; then
        cat >> "${NGINX_CONF}" <<EOF
    location /nginx-ui/ {
        proxy_pass http://127.0.0.1:${PORTS[NGINX_UI]}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_redirect / /nginx-ui/;
    }
EOF
    fi
    echo "}" >> "${NGINX_CONF}"
    nginx -t && systemctl reload nginx
    log "${GREEN}Nginx и SSL успешно настроены.${NC}"
}

start_services() {
    log "${YELLOW}6. Запуск сервисов Docker...${NC}"
    cd "${BASE_DIR}"
    log "Загрузка свежих образов Docker..."
    docker compose pull --quiet >> "${LOG_FILE}" 2>&1
    log "Запуск всех сервисов..."
    docker compose up -d
    log "Ожидание готовности Headscale (проверка логов)..."
    if ! timeout 60 bash -c 'until docker compose logs headscale 2>&1 | grep -q "listening and serving HTTP on"; do sleep 5; done'; then
        log "${YELLOW}Headscale запускается дольше обычного, но мы продолжим. Возможны проблемы на следующем шаге.${NC}"
    fi
    log "${GREEN}Headscale успешно запущен.${NC}"
}

final_setup() {
    log "${YELLOW}7. Финальная настройка Headscale...${NC}"
    cd "${BASE_DIR}"
    log "Создание пользователя 'admin' (если не существует)..."
    if ! docker compose exec headscale headscale users list | grep -q 'admin'; then
        docker compose exec headscale headscale users create admin >> "${LOG_FILE}" 2>&1
    fi
    log "Генерация API ключа для ручного ввода в UI..."
    local API_KEY; API_KEY=$(docker compose exec headscale headscale apikeys create)
    if [[ -z "$API_KEY" ]]; then
        die "Не удалось сгенерировать API ключ (команда вернула пустой результат)."
    fi
    rm -rf "${BASE_DIR}/API_DELETEME.KEY"
    cat > "${BASE_DIR}/API_DELETEME.KEY" <<EOF
==BEGINNING OF API KEY==
${API_KEY}
==END OF API KEY==
EOF
    chmod 400 "${BASE_DIR}/API_DELETEME.KEY"
    log "API ключ сохранен в файл ${BOLD}${BASE_DIR}/API_DELETEME.KEY${NC}"
    log "Перезапуск сервисов..."
    docker compose up -d --force-recreate headscale headscale-admin
    log "Повторное ожидание готовности Headscale..."
    if ! timeout 60 bash -c 'until docker compose logs headscale 2>&1 | grep -q "listening and serving HTTP on"; do sleep 5; done'; then
        die "Headscale не смог перезапуститься."
    fi
    local CRED_FILE="${SCRIPT_DIR}/headscale_credentials.txt"
    {
        echo "==============================================="
        echo "      УСТАНОВКА HEADSCALE ЗАВЕРШЕНА"
        echo "==============================================="
        echo "Сервер: https://${DOMAIN}"
        echo "Публичный IP: ${SERVER_IP}"
        echo "---[ URL ДЛЯ ДОСТУПА ]---"
        [ "$ACTIVATE_HEADSCALE_ADMIN" = true ] && echo "Headscale-Admin UI: https://${DOMAIN}/admin/"
        [ "$ACTIVATE_NGINX_UI" = true ] && echo "Nginx-UI:           https://${DOMAIN}/nginx-ui/"
        echo "---[ ВХОД В HEADSCALE-ADMIN UI ]---"
        echo "1. Перейдите по адресу https://${DOMAIN}/admin/"
        echo "2. UI попросит вас ввести API ключ."
        echo "3. Скопируйте ключ из файла командой:"
        echo "   sudo cat ${BASE_DIR}/API_DELETEME.KEY"
        echo "4. Вставьте ключ (только саму строку с ключом) в веб-интерфейс."
        echo "---[ ПОДКЛЮЧЕНИЕ УСТРОЙСТВ ]---"
        echo "Для подключения устройств используйте команду:"
        echo "tailscale up --login-server https://${DOMAIN}"
        echo "---[ ВАЖНО: БЕЗОПАСНОСТЬ ]---"
        echo "ПОСЛЕ успешного входа в UI ОБЯЗАТЕЛЬНО удалите файл с ключом:"
        echo "sudo rm ${BASE_DIR}/API_DELETEME.KEY"
        echo "Также удалите этот файл с учетными данными:"
        echo "sudo rm ${CRED_FILE}"
        echo "==============================================="
    } > "${CRED_FILE}"
    log "${GREEN}${BOLD}УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!${NC}"
    log "Учетные данные и инструкция по входу сохранены в файл: ${BOLD}${CRED_FILE}${NC}"
    log "Для просмотра введите: ${BOLD}sudo cat ${CRED_FILE}${NC}"
}

main() {
    : > "${LOG_FILE}"
    log "${BOLD}=== ЗАПУСК УСТАНОВКИ HEADSCALE [${SCRIPT_NAME}] ===${NC}"
    if [ -d "${BASE_DIR}" ]; then
        read -p "$(printf "${YELLOW}Обнаружена директория ${BASE_DIR}. Хотите полностью очистить ее и начать заново? (y/n): ${NC}")" -r reply
        if [[ $reply =~ ^[Yy]$ ]]; then
            log "Выполняется очистка предыдущей установки..."
            (cd "${BASE_DIR}" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
            rm -rf "${BASE_DIR}"
        else
            die "Установка отменена пользователем."
        fi
    fi
    check_dependencies
    collect_user_data
    check_ports
    generate_configs
    setup_nginx_ssl
    start_services
    final_setup
}

main "$@"

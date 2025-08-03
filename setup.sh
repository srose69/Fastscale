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
    log "${RED}${BOLD}CRITICAL ERROR:${NC} $1"
    if command -v docker &>/dev/null && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        log "${YELLOW}Saving Docker logs for diagnostics...${NC}"
        (cd "${BASE_DIR}" && docker compose logs --tail=100 >> "${LOG_FILE}" 2>&1)
    fi
    log "${YELLOW}Performing cleanup...${NC}"
    if command -v docker &>/dev/null && [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        (cd "${BASE_DIR}" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
    fi
    log "${RED}Installation aborted. Check the log file: ${BOLD}${LOG_FILE}${NC}"
    exit 1
}

trap 'die "Script failed at line ${LINENO}."' ERR

version_gt() {
    [ "$(printf '%s\n' "$@" | sort -V | head -n1)" != "$1" ]
}

check_dependencies() {
    log "${YELLOW}1. Checking system dependencies...${NC}"
    [ "$(id -u)" -ne 0 ] && die "This script must be run as root (or with sudo)."
    DOCKER_MIN_VERSION="20.10.0"
    if ! command -v docker &>/dev/null; then
        log "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com | sh >> "${LOG_FILE}" 2>&1
    fi
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
    if version_gt "$DOCKER_MIN_VERSION" "$DOCKER_VERSION"; then
        die "Docker version ${DOCKER_MIN_VERSION} or higher is required. Found version ${DOCKER_VERSION}."
    fi
    if ! docker compose version &>/dev/null; then
        log "Docker Compose not found. Installing..."
        apt-get install -y docker-compose-plugin >> "${LOG_FILE}" 2>&1
    fi
    systemctl enable --now docker >/dev/null 2>&1
    log "Installing packages (lsof, jq, certbot...)"
    apt-get update -qq >> "${LOG_FILE}" 2>&1
    apt-get install -y lsof jq certbot python3-certbot-nginx >> "${LOG_FILE}" 2>&1
    log "${GREEN}Dependencies successfully checked and installed.${NC}"
}

collect_user_data() {
    log "${YELLOW}2. Collecting configuration data...${NC}"
    while true; do
        read -p "Enter your domain (e.g., vpn.example.com): " DOMAIN
        [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break || echo -e "${RED}Invalid domain format.${NC}"
    done
    while true; do
        read -p "Enter your email (for Let's Encrypt SSL certificate): " EMAIL
        [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && break || echo -e "${RED}Invalid email format.${NC}"
    done
    log "Detecting public IP address..."
    SERVER_IP=$(curl -s -4 --connect-timeout 5 https://ifconfig.io || curl -s -4 --connect-timeout 5 https://ifconfig.me)
    if [ -z "$SERVER_IP" ]; then
        log "${YELLOW}Could not automatically detect IP. Please enter it manually.${NC}"
        while true; do
            read -p "Enter the public IP address of your server: " SERVER_IP
            [[ "$SERVER_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break || echo -e "${RED}Invalid IP format.${NC}"
        done
    fi
    log "Server IP address: ${BOLD}${SERVER_IP}${NC}"
    log "${YELLOW}IMPORTANT: Ensure the A record for domain ${BOLD}${DOMAIN}${NC} points to the IP address ${BOLD}${SERVER_IP}${NC}."
    read -p "Do you confirm that the DNS is configured correctly? (y/n) " -r reply
    [[ $reply =~ ^[Yy]$ ]] || die "Installation cancelled by user."
}

check_ports() {
    log "${YELLOW}3. Checking port availability...${NC}"
    check_single_port() {
        local port="$1" service="$2" expected_process="$3"
        while true; do
            local pid; pid=$(lsof -i ":${port}" -sTCP:LISTEN -t -P -n | head -n1)
            if [ -z "$pid" ]; then
                log "Port ${BOLD}${port}${NC} is free for '${service}'." && echo "$port" && return
            fi
            local process_name; process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown process")
            if [ -n "$expected_process" ] && [ "$process_name" == "$expected_process" ]; then
                log "${YELLOW}Found '${process_name}' on port ${port}. We will use it.${NC}"
                [[ "$expected_process" == "nginx" ]] && EXISTING_NGINX=true && echo "$port" && return
            fi
            read -p "$(printf "\n${RED}CONFLICT:${NC} Port ${BOLD}%s${NC} for '${BOLD}%s${NC}' is occupied by process '${BOLD}%s${NC}'.\n${YELLOW}Do you want to change the port? (y/n): ${NC}" "$port" "$service" "$process_name")" -r reply
            [[ $reply =~ ^[Yy]$ ]] || die "Installation cancelled due to port conflict."
            while true; do
                read -p "Enter a new port for '${service}' (1-65535): " custom_port
                if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -gt 0 ] && [ "$custom_port" -lt 65536 ]; then
                    port="$custom_port" && break
                else
                    echo -e "${RED}Invalid port number.${NC}"
                fi
            done
        done
    }
    PORTS[HTTP]=$(check_single_port "${PORTS[HTTP]}" "Nginx (HTTP)" "nginx")
    PORTS[HTTPS]=$(check_single_port "${PORTS[HTTPS]}" "Nginx (HTTPS)" "nginx")
    PORTS[HEADSCALE]=$(check_single_port "${PORTS[HEADSCALE]}" "Headscale" "")
    read -p "Enable headscale-admin web UI? (y/n) " -r reply
    if [[ $reply =~ ^[Yy]$ ]]; then
        ACTIVATE_HEADSCALE_ADMIN=true && PORTS[HEADSCALE_ADMIN]=$(check_single_port "${PORTS[HEADSCALE_ADMIN]}" "headscale-admin" "")
    fi
    read -p "Enable Nginx-UI web UI? (y/n) " -r reply
    if [[ $reply =~ ^[Yy]$ ]]; then
        ACTIVATE_NGINX_UI=true && PORTS[NGINX_UI]=$(check_single_port "${PORTS[NGINX_UI]}" "Nginx-UI" "")
    fi
    log "${GREEN}Port check completed.${NC}"
}

generate_configs() {
    log "${YELLOW}4. Generating configuration files...${NC}"
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
    log "${GREEN}Configuration files created successfully.${NC}"
}

setup_nginx_ssl() {
    log "${YELLOW}5. Setting up Nginx and SSL certificate...${NC}"
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
        log "Obtaining SSL certificate for ${DOMAIN}..."
        certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" --staple-ocsp --must-staple >> "${LOG_FILE}" 2>&1
    else
        log "${GREEN}Existing valid SSL certificate found.${NC}"
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
    log "${GREEN}Nginx and SSL configured successfully.${NC}"
}

start_services() {
    log "${YELLOW}6. Starting Docker services...${NC}"
    cd "${BASE_DIR}"
    log "Pulling latest Docker images..."
    docker compose pull --quiet >> "${LOG_FILE}" 2>&1
    log "Starting all services..."
    docker compose up -d
    log "Waiting for Headscale to be ready (checking logs)..."
    if ! timeout 60 bash -c 'until docker compose logs headscale 2>&1 | grep -q "listening and serving HTTP on"; do sleep 5; done'; then
        log "${YELLOW}Headscale is taking longer than usual to start, but we will continue. There might be issues in the next step.${NC}"
    fi
    log "${GREEN}Headscale started successfully.${NC}"
}

final_setup() {
    log "${YELLOW}7. Final Headscale setup...${NC}"
    cd "${BASE_DIR}"
    log "Creating user 'admin' (if it doesn't exist)..."
    if ! docker compose exec headscale headscale users list | grep -q 'admin'; then
        docker compose exec headscale headscale users create admin >> "${LOG_FILE}" 2>&1
    fi
    log "Generating API key for manual UI input..."
    local API_KEY; API_KEY=$(docker compose exec headscale headscale apikeys create)
    if [[ -z "$API_KEY" ]]; then
        die "Failed to generate API key (command returned empty)."
    fi
    rm -rf "${BASE_DIR}/API_DELETEME.KEY"
    cat > "${BASE_DIR}/API_DELETEME.KEY" <<EOF
==BEGINNING OF API KEY==
${API_KEY}
==END OF API KEY==
EOF
    chmod 400 "${BASE_DIR}/API_DELETEME.KEY"
    log "API key saved to file ${BOLD}${BASE_DIR}/API_DELETEME.KEY${NC}"
    log "Restarting services..."
    docker compose up -d --force-recreate headscale headscale-admin
    log "Waiting for Headscale to be ready again..."
    if ! timeout 60 bash -c 'until docker compose logs headscale 2>&1 | grep -q "listening and serving HTTP on"; do sleep 5; done'; then
        die "Headscale failed to restart."
    fi
    local CRED_FILE="${SCRIPT_DIR}/headscale_credentials.txt"
    {
        echo "==============================================="
        echo "      HEADSCALE INSTALLATION COMPLETE"
        echo "==============================================="
        echo "Server: https://${DOMAIN}"
        echo "Public IP: ${SERVER_IP}"
        echo "---[ ACCESS URLs ]---"
        [ "$ACTIVATE_HEADSCALE_ADMIN" = true ] && echo "Headscale-Admin UI: https://${DOMAIN}/admin/"
        [ "$ACTIVATE_NGINX_UI" = true ] && echo "Nginx-UI:           https://${DOMAIN}/nginx-ui/"
        echo "---[ LOGGING INTO HEADSCALE-ADMIN UI ]---"
        echo "1. Navigate to https://${DOMAIN}/admin/"
        echo "2. The UI will ask for an API key."
        echo "3. Copy the key from the file with the command:"
        echo "   sudo cat ${BASE_DIR}/API_DELETEME.KEY"
        echo "4. Paste the key (only the key string itself) into the web interface."
        echo "---[ CONNECTING DEVICES ]---"
        echo "To connect devices, use the command:"
        echo "tailscale up --login-server https://${DOMAIN}"
        echo "---[ IMPORTANT: SECURITY ]---"
        echo "AFTER successfully logging into the UI, you MUST delete the key file:"
        echo "sudo rm ${BASE_DIR}/API_DELETEME.KEY"
        echo "Also, delete this credentials file:"
        echo "sudo rm ${CRED_FILE}"
        echo "==============================================="
    } > "${CRED_FILE}"
    log "${GREEN}${BOLD}INSTALLATION COMPLETED SUCCESSFULLY!${NC}"
    log "Credentials and login instructions have been saved to the file: ${BOLD}${CRED_FILE}${NC}"
    log "To view, type: ${BOLD}sudo cat ${CRED_FILE}${NC}"
}

main() {
    : > "${LOG_FILE}"
    log "${BOLD}=== STARTING HEADSCALE INSTALLATION [${SCRIPT_NAME}] ===${NC}"
    if [ -d "${BASE_DIR}" ]; then
        read -p "$(printf "${YELLOW}Directory ${BASE_DIR} found. Do you want to completely wipe it and start over? (y/n): ${NC}")" -r reply
        if [[ $reply =~ ^[Yy]$ ]]; then
            log "Cleaning up previous installation..."
            (cd "${BASE_DIR}" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
            rm -rf "${BASE_DIR}"
        else
            die "Installation cancelled by user."
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

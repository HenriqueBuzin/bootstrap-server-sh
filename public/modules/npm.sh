#!/bin/bash

setup_npm() {

  log "🌐 Configurando Nginx Proxy Manager..."

  local NPM_DIR="/root/nginx-proxy-manager"
  local ENV_FILE="/root/envs/global/npm.env"

  ensure_dir "$NPM_DIR"

  # ========================
  # 🔐 VALIDA ENV
  # ========================

  if [ ! -f "$ENV_FILE" ]; then
    die "npm.env não encontrado em /root/envs/global"
  fi

  set -o allexport
  if ! source "$ENV_FILE"; then
    die "Erro ao carregar npm.env"
  fi
  set +o allexport
  
  if [ -z "${NPM_EXTERNAL_PORT:-}" ] || [ -z "${NPM_INTERNAL_PORT:-}" ] || [ -z "${PROXY_NETWORK:-}" ]; then
    die "Variáveis de porta/rede não definidas"
  fi

  if [ -z "$NPM_EMAIL" ] || [ -z "$NPM_PASSWORD" ] || [ -z "$NPM_URL" ]; then
    die "Variáveis NPM não definidas corretamente"
  fi

  require_command jq
  require_command curl
  require_command docker

  docker compose version >/dev/null 2>&1 || die "docker compose não disponível"

  cd "$NPM_DIR" || die "Falha ao acessar $NPM_DIR"

  # ========================
  # 🐳 DOCKER COMPOSE
  # ========================

  if [ ! -f docker-compose.yml ]; then
  
    log "Criando docker-compose do NPM..."
  
    cat <<EOF > docker-compose.yml
services:
  npm:
    image: jc21/nginx-proxy-manager:2.14.0
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "127.0.0.1:${NPM_EXTERNAL_PORT}:${NPM_INTERNAL_PORT}"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - ${PROXY_NETWORK}

networks:
  ${PROXY_NETWORK}:
    external: true
EOF

  else
    debug "docker-compose já existe"
  fi

  # ========================
  # 🚀 SUBIR NPM
  # ========================

  log "Subindo NPM..."

  docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1 || {
    log "Criando network ${PROXY_NETWORK}..."
    docker network create "${PROXY_NETWORK}"
  }

  if ! docker ps --format '{{.Names}}' | grep -Fxq "npm"; then
    retry 3 docker compose up -d --build
  else
    debug "NPM já está rodando"
  fi

  # ========================
  # ⏳ AGUARDA API
  # ========================

  wait_for "NPM API" "curl -fsS ${NPM_URL}/api >/dev/null" 60
  
  success "NPM está online"

  # ========================
  # 🔐 LOGIN BOOTSTRAP
  # ========================

  log "Login bootstrap..."

  local BOOTSTRAP_EMAIL="admin@example.com"
  local BOOTSTRAP_PASSWORD="changeme"
  local TOKEN

  TOKEN=$(jq -n \
    --arg email "$BOOTSTRAP_EMAIL" \
    --arg pass "$BOOTSTRAP_PASSWORD" \
    '{identity: $email, secret: $pass}' | \
  curl -fsS --retry 3 --retry-delay 2 --connect-timeout 5 --max-time 30 -X POST "${NPM_URL}/api/tokens" \
    -H "Content-Type: application/json" \
    -d @- | jq -r .token)

  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    die "Falha ao autenticar no NPM (bootstrap)"
  fi

  success "Login bootstrap OK"

  # ========================
  # 👤 CRIA USUÁRIO REAL
  # ========================

  log "Verificando usuário..."

  local USER_EXISTS

  USER_EXISTS=$(curl -fsS --retry 3 --retry-delay 2 --connect-timeout 5 --max-time 30 "${NPM_URL}/api/users" \
    -H "Authorization: Bearer $TOKEN" | \
    jq -r ".[] | select(.email==\"$NPM_EMAIL\") | .id")

  if [ -z "$USER_EXISTS" ]; then

    log "Criando usuário admin..."

    local NEW_USER_ID

    NEW_USER_ID=$(jq -n \
      --arg email "$NPM_EMAIL" \
      --arg pass "$NPM_PASSWORD" \
      '{
        email: $email,
        password: $pass,
        name: "Admin",
        roles: ["admin"]
      }' | \
    curl -fsS --retry 3 --retry-delay 2 --connect-timeout 5 --max-time 30 -X POST "${NPM_URL}/api/users" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d @- | jq -r .id)

    if [ -z "$NEW_USER_ID" ] || [ "$NEW_USER_ID" = "null" ]; then
      die "Falha ao criar usuário NPM"
    fi

    success "Usuário criado: $NPM_EMAIL"

  else
    debug "Usuário já existe"
  fi

  [ -n "${TOKEN:-}" ] && unset TOKEN
  

  # ========================
  # 🔐 LOGIN REAL
  # ========================

  log "Login com usuário real..."

  TOKEN=$(jq -n \
    --arg email "$NPM_EMAIL" \
    --arg pass "$NPM_PASSWORD" \
    '{identity: $email, secret: $pass}' | \
  curl -fsS --retry 3 --retry-delay 2 --connect-timeout 5 --max-time 30 -X POST "${NPM_URL}/api/tokens" \
    -H "Content-Type: application/json" \
    -d @- | jq -r .token)

  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    die "Falha no login com usuário real"
  fi

  success "Login real OK"

  # ========================
  # 🧹 REMOVE ADMIN PADRÃO
  # ========================

  log "Removendo admin padrão..."

  local ADMIN_ID

  ADMIN_ID=$(curl -fsS --retry 3 --retry-delay 2 --connect-timeout 5 --max-time 30 "${NPM_URL}/api/users" \
    -H "Authorization: Bearer $TOKEN" | \
    jq -r '.[] | select(.email=="admin@example.com") | .id')

  if [ -n "$ADMIN_ID" ] && [ "$ADMIN_ID" != "null" ]; then

    curl -fsS --retry 3 --retry-delay 2 --connect-timeout 5 --max-time 30 -X DELETE "${NPM_URL}/api/users/$ADMIN_ID" \
      -H "Authorization: Bearer $TOKEN"

    success "Admin padrão removido"

  else
    debug "Admin padrão já removido"
  fi

  [ -n "${TOKEN:-}" ] && unset TOKEN

  log "NPM disponível em: ${NPM_URL}"
  log "Login: ${NPM_EMAIL}"

  success "🌐 Nginx Proxy Manager pronto"
}

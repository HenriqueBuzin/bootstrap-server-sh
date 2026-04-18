#!/bin/bash

setup_proxies() {

  log "🌐 Configurando proxies..."

  local APPS_DIR="/root/envs/apps"
  local NPM_ENV="/root/envs/global/npm.env"

  if [ ! -f "$NPM_ENV" ]; then
    die "npm.env não encontrado"
  fi

  source "$NPM_ENV"

  require_command curl
  require_command jq

  # ========================
  # 🔐 LOGIN NPM
  # ========================

  log "Autenticando no NPM..."

  TOKEN=$(curl -fsS -X POST "$NPM_URL/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{
      \"identity\": \"$NPM_EMAIL\",
      \"secret\": \"$NPM_PASSWORD\"
    }" | jq -r .token)

  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    die "Falha ao autenticar no NPM"
  fi

  success "Autenticado no NPM"
  
  # ========================
  # 🔥 PROXIES EXISTENTES
  # ========================

  EXISTING_HOSTS=$(curl -s "$NPM_URL/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $TOKEN")

  # ========================
  # 🔥 CERTIFICADOS EXISTENTES
  # ========================

  log "Carregando certificados..."

  CERTS=$(curl -s "$NPM_URL/api/nginx/certificates" \
    -H "Authorization: Bearer $TOKEN")

  # cria mapa DOMAIN -> CERT_ID
  declare -A CERT_MAP

  while read -r domain cert_id; do
    CERT_MAP["$domain"]="$cert_id"
  done < <(
    echo "$CERTS" | jq -r '.[] | "\(.nice_name) \(.id)"'
  )
  
  # ========================
  # 🔐 PROXY JENKINS
  # ========================

  log "Configurando proxy do Jenkins..."

  JENKINS_DOMAIN="${JENKINS_SUBDOMAIN}.${INFRA_DOMAIN}"

  EXISTS=$(echo "$EXISTING_HOSTS" | jq ".[] | select(.domain_names[]==\"$JENKINS_DOMAIN\")")

  if [ -z "$EXISTS" ]; then

    ADVANCED_CONFIG=$(cat <<EOF
location = /github-webhook/ {

    if (\$http_x_hub_signature_256 = "") {
        return 403;
    }

    proxy_pass http://jenkins:8080/github-webhook/;
}

location / {
    return 403;
}
EOF
  )

    CERT_ID="${CERT_MAP[$INFRA_DOMAIN]}"

    if [ -z "$CERT_ID" ]; then
      warn "Certificado não encontrado para Jenkins ($INFRA_DOMAIN)"
      CERT_ID=null
    fi

    curl -fsS -X POST "$NPM_URL/api/nginx/proxy-hosts" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"domain_names\": [\"$JENKINS_DOMAIN\"],
        \"forward_host\": \"jenkins\",
        \"forward_port\": 8080,
        \"certificate_id\": $CERT_ID,
        \"ssl_forced\": true,
        \"http2_support\": true,
        \"hsts_enabled\": true,
        \"hsts_subdomains\": true,
        \"advanced_config\": \"$ADVANCED_CONFIG\"
      }"

    success "Proxy Jenkins criado: $JENKINS_DOMAIN"
  else
    debug "Proxy Jenkins já existe"
  fi

  # ========================
  # 📦 PROCESSA APPS
  # ========================

  local APPS
  APPS=$(cat "$APPS_DIR"/*.apps 2>/dev/null)

  if [ -z "$APPS" ]; then
    warn "Nenhum app encontrado"
    return 0
  fi

  while IFS= read -r line; do

    ADVANCED_CONFIG=""
    
    [ -z "$line" ] && continue

    line=$(echo "$line" | xargs)

    IFS=':' read -r TYPE NAME PORT DOMAIN EMAIL CF_TOKEN WEBHOOK_SECRET REPO PROD DEV <<< "$line"

    # ========================
    # 🔍 VALIDAÇÃO
    # ========================

    HOST="$NAME"
    DOMAIN_BASE="$DOMAIN"
    SUB="$TYPE"

    if [ -z "$HOST" ] || [ -z "$PORT" ] || [ -z "$DOMAIN_BASE" ]; then
      warn "Linha inválida ignorada: $line"
      continue
    fi

    # ========================
    # 🌐 DOMÍNIO
    # ========================

    if [ "$SUB" = "root" ]; then
      DISPLAY_DOMAIN="$DOMAIN_BASE"
      DOMAIN_JSON="\"$DOMAIN_BASE\",\"*.$DOMAIN_BASE\""
    else
      DISPLAY_DOMAIN="$SUB.$DOMAIN_BASE"
      DOMAIN_JSON="\"$DISPLAY_DOMAIN\""
    fi

    # ========================
    # 🔁 EVITA DUPLICAÇÃO
    # ========================

    EXISTS=$(echo "$EXISTING_HOSTS" | jq ".[] | select(.domain_names[]==\"$DISPLAY_DOMAIN\")")

    if [ -n "$EXISTS" ]; then
      debug "Proxy já existe: $DISPLAY_DOMAIN"
      continue
    fi

    # ========================
    # 🔒 SSL
    # ========================

    CERT_ID="${CERT_MAP[$DOMAIN_BASE]}"

    if [ -z "$CERT_ID" ]; then
      warn "Certificado não encontrado para $DOMAIN_BASE"
      continue
    fi

    # ========================
    # 🚀 CRIA PROXY
    # ========================

    log "Criando proxy: $DISPLAY_DOMAIN → $HOST:$PORT"

    curl -fsS -X POST "$NPM_URL/api/nginx/proxy-hosts" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"domain_names\": [$DOMAIN_JSON],
        \"forward_host\": \"$HOST\",
        \"forward_port\": $PORT,
        \"certificate_id\": $CERT_ID,
        \"ssl_forced\": true,
        \"http2_support\": true,
        \"hsts_enabled\": true,
        \"hsts_subdomains\": true,
        \"advanced_config\": \"$ADVANCED_CONFIG\"
      }"

    success "Proxy criado: $DISPLAY_DOMAIN"

    # ========================
    # 🔄 ATUALIZA CACHE LOCAL
    # ========================

    EXISTING_HOSTS=$(echo "$EXISTING_HOSTS" | jq ". + [{
      domain_names: [\"$DISPLAY_DOMAIN\"]
    }]")

  done <<< "$APPS"

  success "🌐 Proxies configurados com sucesso"
}

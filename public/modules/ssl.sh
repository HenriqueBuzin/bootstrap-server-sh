#!/bin/bash

setup_ssl() {

  log "🔒 Configurando SSL (Cloudflare + NPM)..."

  local APPS_DIR="/root/envs/apps"
  local NPM_ENV="/root/envs/global/npm.env"

  require_command certbot
  require_command jq
  require_command curl

  if [ ! -f "$NPM_ENV" ]; then
    die "npm.env não encontrado"
  fi

  source "$NPM_ENV"

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
  # 📦 DOMÍNIOS ÚNICOS
  # ========================

  DOMAINS=$(awk -F: '{print $4":"$5":"$6}' "$APPS_DIR"/*.apps | sort -u)

  if [ -z "$DOMAINS" ]; then
    warn "Nenhum domínio encontrado"
    return 0
  fi

  # ========================
  # 🔥 CERTIFICADOS EXISTENTES NO NPM
  # ========================

  EXISTING_CERTS=$(curl -s "$NPM_URL/api/nginx/certificates" \
    -H "Authorization: Bearer $TOKEN")

  declare -A EXISTING_MAP

  while read -r name id; do
    EXISTING_MAP["$name"]="$id"
  done < <(
    echo "$EXISTING_CERTS" | jq -r '.[] | "\(.nice_name) \(.id)"'
  )

  # ========================
  # 🔒 LOOP DOMÍNIOS
  # ========================

  while IFS=':' read -r DOMAIN DOMAIN_EMAIL DOMAIN_TOKEN; do

    [ -z "$DOMAIN" ] && continue

    log "🔒 Processando domínio: $DOMAIN"

    # ========================
    # 🔁 EVITA DUPLICAÇÃO
    # ========================

    if [ -n "${EXISTING_MAP[$DOMAIN]}" ]; then
      debug "Certificado já existe no NPM: $DOMAIN"
      continue
    fi

    # ========================
    # 🔐 CLOUDLFARE TOKEN FILE
    # ========================

    CF_FILE="/root/.cloudflare-$DOMAIN.ini"

    cat <<EOF > "$CF_FILE"
dns_cloudflare_api_token=$DOMAIN_TOKEN
EOF

    secure_file "$CF_FILE"

    # ========================
    # 🔒 CERTBOT
    # ========================

    log "Gerando certificado wildcard para $DOMAIN..."

    retry 3 certbot certonly \
      --non-interactive \
      --agree-tos \
      --email "$DOMAIN_EMAIL" \
      --dns-cloudflare \
      --dns-cloudflare-credentials "$CF_FILE" \
      -d "$DOMAIN" \
      -d "*.$DOMAIN"

    local CERT_PATH="/etc/letsencrypt/live/$DOMAIN"

    if [ ! -f "$CERT_PATH/fullchain.pem" ] || [ ! -f "$CERT_PATH/privkey.pem" ]; then
      error "Certificado inválido para $DOMAIN"
      continue
    fi

    # ========================
    # 📦 IMPORTA NO NPM
    # ========================

    log "Importando certificado no NPM..."

    CERT=$(awk '{printf "%s\\n", $0}' "$CERT_PATH/fullchain.pem")
    KEY=$(awk '{printf "%s\\n", $0}' "$CERT_PATH/privkey.pem")

    CERT_ID=$(curl -fsS -X POST "$NPM_URL/api/nginx/certificates" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"nice_name\": \"$DOMAIN\",
        \"domain_names\": [\"$DOMAIN\",\"*.$DOMAIN\"],
        \"certificate\": \"$CERT\",
        \"private_key\": \"$KEY\"
      }" | jq -r .id)

    if [ -z "$CERT_ID" ] || [ "$CERT_ID" = "null" ]; then
      error "Falha ao importar certificado: $DOMAIN"
      continue
    fi

    success "Certificado criado e importado: $DOMAIN ($CERT_ID)"

  done <<< "$DOMAINS"

  # ========================
  # 🔁 AUTO RENEW
  # ========================

  log "Configurando auto-renew..."

  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook 'docker restart npm'") | crontab -

  success "🔒 SSL configurado com sucesso"
}

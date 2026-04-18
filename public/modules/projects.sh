#!/bin/bash

collect_projects() {

  log "📦 Configurando projetos..."

  local APPS_DIR="/root/envs/apps"
  local PROJECTS_DIR="/root/envs/projects"
  local GLOBAL_DIR="/root/envs/global"

  ensure_dir "$APPS_DIR"
  ensure_dir "$PROJECTS_DIR"
  ensure_dir "$GLOBAL_DIR"

  # ========================
  # 🔢 QUANTIDADE
  # ========================

  ask_number "Quantos projetos deseja configurar?" TOTAL_PROJECTS

  # ========================
  # 🔐 DADOS GLOBAIS
  # ========================

  ask_and_confirm "Usuário do Jenkins" JENKINS_USER
  ask_and_confirm "Senha do Jenkins" JENKINS_PASSWORD true
  ask_and_confirm "Senha do NPM" NPM_PASSWORD true
  ask "Email global NPM" GLOBAL_EMAIL

  # ========================
  # 📋 PORTA BASE
  # ========================

  local BASE_PORT=3000
  local LAST_PORT

  LAST_PORT=$(awk -F: '{print $3}' "$APPS_DIR"/*.apps 2>/dev/null | sort -n | tail -n1)

  if [ -n "$LAST_PORT" ]; then
    BASE_PORT=$((LAST_PORT + 1))
  fi

  debug "Porta inicial: $BASE_PORT"

  INFRA_DOMAIN=""

  # ========================
  # 📦 LOOP PROJETOS
  # ========================

  for ((i=1; i<=TOTAL_PROJECTS; i++)); do

    local SITE_PORT=$((BASE_PORT + (i-1)*2))
    local SITE_DEV_PORT=$((SITE_PORT + 1))

    echo ""
    echo "========================"
    echo "📦 PROJETO $i"
    echo "========================"

    if [ -z "$INFRA_DOMAIN" ]; then
      log "⚠️ Este domínio será usado para Jenkins e webhooks"
    fi

    while true; do
      ask "Domínio do projeto (ex: meusite.com.br)" PROJECT_DOMAIN

      if validate_domain "$PROJECT_DOMAIN"; then
        break
      fi

      warn "Domínio inválido, tente novamente"
    done

    # ========================
    # 🌐 DEFINE INFRA DOMAIN
    # ========================

    if [ -z "$INFRA_DOMAIN" ]; then
      INFRA_DOMAIN="$PROJECT_DOMAIN"
      export INFRA_DOMAIN

      log "🌐 Domínio da infra definido: $INFRA_DOMAIN"
    fi

    ask "Nome do projeto (ex: app)" PROJECT_NAME

    if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      warn "Nome inválido"
      continue
    fi

    ask "Repositório Git (URL)" GIT_REPO
    ask "Email (SSL / notificações)" EMAIL

    ask_secret "Cloudflare API Token" CF_API_TOKEN
    ask_secret "Webhook Secret (GitHub)" WEBHOOK_SECRET

    ask "Branch produção" BRANCH_PROD "main"
    ask "Branch dev" BRANCH_DEV "dev"

    if ! confirm "Confirmar projeto $PROJECT_NAME?"; then
      warn "Projeto ignorado"
      continue
    fi

    # ========================
    # 📁 ESTRUTURA
    # ========================

    ensure_dir "/root/$PROJECT_NAME"
    ensure_dir "/root/${PROJECT_NAME}-dev"

    local ENV_DIR="$PROJECTS_DIR/$PROJECT_NAME"
    ensure_dir "$ENV_DIR"

    local ENV_PROD="$ENV_DIR/.env"
    local ENV_DEV="$ENV_DIR/.env.dev"

    # ========================
    # 🔐 ENV FILES
    # ========================

    if [ ! -f "$ENV_PROD" ]; then
      log "Cole o .env de PRODUÇÃO ($PROJECT_NAME), para finalizar digite CTRL+D:"
      cat > "$ENV_PROD"
      secure_file "$ENV_PROD"
    fi

    if [ ! -f "$ENV_DEV" ]; then
      log "Cole o .env de DEV ($PROJECT_NAME), para finalizar digite CTRL+D:"
      cat > "$ENV_DEV"
      secure_file "$ENV_DEV"
    fi

    # ========================
    # 📦 REGISTRO APP
    # ========================

    local PROJECT_FILE="$APPS_DIR/$PROJECT_NAME.apps"

    if [ -f "$PROJECT_FILE" ]; then
      warn "Projeto já existe: $PROJECT_NAME"
      confirm "Deseja sobrescrever?" || continue
    fi

    cat <<EOF > "$PROJECT_FILE"
root:$PROJECT_NAME:$SITE_PORT:$PROJECT_DOMAIN:$EMAIL:$CF_API_TOKEN:$WEBHOOK_SECRET:$GIT_REPO:$BRANCH_PROD:$BRANCH_DEV
dev:${PROJECT_NAME}-dev:$SITE_DEV_PORT:$PROJECT_DOMAIN:$EMAIL:$CF_API_TOKEN:$WEBHOOK_SECRET:$GIT_REPO:$BRANCH_PROD:$BRANCH_DEV
EOF

    success "Projeto registrado: $PROJECT_NAME"

  done

  # ========================
  # 📋 RESUMO
  # ========================

  echo ""
  log "📋 Apps configurados:"
  cat "$APPS_DIR"/*.apps 2>/dev/null || warn "Nenhum app encontrado"

  if ! confirm "Confirmar tudo?"; then
    die "Cancelado pelo usuário"
  fi

  # ========================
  # 🔐 ENV JENKINS
  # ========================
  
  [ -z "$INFRA_DOMAIN" ] && die "INFRA_DOMAIN não definido"
  [ -z "$JENKINS_SUBDOMAIN" ] && die "JENKINS_SUBDOMAIN não definido no config.sh"

  cat <<EOF > "$GLOBAL_DIR/jenkins.env"
JENKINS_USER=$JENKINS_USER
JENKINS_PASSWORD=$JENKINS_PASSWORD
JENKINS_BUILD_MEMORY=256m
JENKINS_RUNTIME_MEMORY=256m
JENKINS_UI_PORT=8082
JENKINS_AGENT_PORT=50000
JENKINS_SUBDOMAIN=$JENKINS_SUBDOMAIN
JENKINS_URL=https://${JENKINS_SUBDOMAIN}.${INFRA_DOMAIN}
EOF

  # ========================
  # 🔐 ENV NPM
  # ========================

  cat <<EOF > "$GLOBAL_DIR/npm.env"
NPM_URL=http://localhost:81
NPM_EMAIL=$GLOBAL_EMAIL
NPM_PASSWORD=$NPM_PASSWORD
NPM_PORT=81
EOF

  success "📦 Projetos configurados com sucesso"
}

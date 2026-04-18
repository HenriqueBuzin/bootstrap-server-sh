#!/bin/bash
set -e

# ========================
# ⚙️ CONFIG GLOBAL
# ========================

CONFIG_FILE="./config.sh"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "❌ config.sh não encontrado"
  exit 1
fi

# ========================
# 📦 LIBS
# ========================

source lib/utils.sh
source lib/input.sh

# ========================
# 🔧 MODULES
# ========================

source modules/system.sh
source modules/projects.sh
source modules/docker.sh
source modules/npm.sh
source modules/ssl.sh
source modules/proxy.sh
source modules/jenkins.sh
source modules/pipelines.sh

# ========================
# 🚀 MAIN
# ========================

main() {
  log "🚀 Iniciando setup completo..."

  # ========================
  # 🛠️ BASE
  # ========================

  setup_system
  collect_projects
  setup_docker

  # ========================
  # 🌐 INFRA DOMAIN
  # ========================

  if [ -z "$INFRA_DOMAIN" ]; then
    die "INFRA_DOMAIN não definido (erro no collect_projects)"
  fi

  export INFRA_DOMAIN

  log "🌐 Domínio da infra: $INFRA_DOMAIN"

  # ========================
  # 🌐 INFRA EXTERNA
  # ========================

  setup_npm
  setup_ssl

  # ========================
  # ⚙️ JENKINS
  # ========================

  setup_jenkins
  setup_pipelines

  # ========================
  # 🌐 PROXIES
  # ========================

  setup_proxies

  # ========================
  # ✅ FINAL
  # ========================

  success "✅ Infraestrutura completa e operacional!"
}

main

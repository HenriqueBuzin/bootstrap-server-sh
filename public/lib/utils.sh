#!/bin/bash

# ========================
# 🎨 CORES
# ========================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # no color

# ========================
# 📢 LOGS
# ========================

log() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

success() {
  echo -e "${GREEN}✔ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
  echo -e "${RED}❌ $1${NC}"
}

# ========================
# 💥 FAIL CONTROLADO
# ========================

die() {
  error "$1"
  exit 1
}

# ========================
# 🔍 DEBUG (opcional)
# ========================

debug() {
  if [ "$DEBUG" = "true" ]; then
    echo -e "${YELLOW}[DEBUG] $1${NC}"
  fi
}

# ========================
# 🔁 RETRY (CRÍTICO)
# ========================

retry() {
  local attempts=$1
  shift
  local count=0

  until "$@"; do
    exit_code=$?
    count=$((count + 1))

    if [ $count -lt $attempts ]; then
      warn "Tentativa $count/$attempts falhou. Repetindo em 3s..."
      sleep 3
    else
      error "Comando falhou após $attempts tentativas: $*"
      return $exit_code
    fi
  done
}

# ========================
# 🌐 CURL COM RETRY
# ========================

curl_retry() {
  retry 5 curl -fsS "$@"
}

# ========================
# 📁 GARANTE DIRETÓRIO
# ========================

ensure_dir() {
  local dir="$1"

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    success "Diretório criado: $dir"
  else
    debug "Diretório já existe: $dir"
  fi
}

# ========================
# 📄 GARANTE ARQUIVO
# ========================

ensure_file() {
  local file="$1"

  if [ ! -f "$file" ]; then
    touch "$file"
    success "Arquivo criado: $file"
  else
    debug "Arquivo já existe: $file"
  fi
}

# ========================
# 🔐 PERMISSÃO SEGURA
# ========================

secure_file() {
  local file="$1"

  chmod 600 "$file" 2>/dev/null || true
  debug "Permissão 600 aplicada: $file"
}

# ========================
# 🔎 VALIDA DEPENDÊNCIA
# ========================

require_command() {
  local cmd="$1"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Dependência não encontrada: $cmd"
  fi
}

# ========================
# ⏳ WAIT UNTIL
# ========================

wait_for() {
  local description="$1"
  local command="$2"
  local retries=30
  local delay=2

  log "Aguardando: $description..."

  for ((i=1; i<=retries; i++)); do
    if eval "$command" >/dev/null 2>&1; then
      success "$description pronto"
      return 0
    fi

    sleep $delay
  done

  die "Timeout aguardando: $description"
}

# ========================
# 🔐 LIMPA VARIÁVEIS SENSÍVEIS
# ========================

cleanup_secrets() {
  unset JENKINS_PASSWORD
  unset NPM_PASSWORD
  unset CF_API_TOKEN
}

trap cleanup_secrets EXIT

# ========================
# 📦 PORTA LIVRE
# ========================

get_next_port() {
  local base_port="$1"
  local used_ports_file="$2"

  local last_port

  last_port=$(awk -F: '{print $3}' "$used_ports_file" 2>/dev/null | sort -n | tail -n1)

  if [ -z "$last_port" ]; then
    echo "$base_port"
  else
    echo $((last_port + 1))
  fi
}

# ========================
# 🔍 CHECA SE PORTA ESTÁ EM USO
# ========================

port_in_use() {
  local port="$1"

  if ss -tuln | grep -q ":$port "; then
    return 0
  else
    return 1
  fi
}

# ========================
# 🧪 VALIDA DOMÍNIO
# ========================

validate_domain() {
  local domain="$1"

  if [[ "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    return 0
  else
    return 1
  fi
}

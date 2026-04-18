#!/bin/bash
set -euo pipefail

# ========================
# 🔒 SEGURANÇA BASE
# ========================

umask 077

# garante bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ Execute com bash"
  exit 1
fi

# ========================
# ⚙️ CONFIG
# ========================

BASE_URL="https://setup.henriquebuz.in"

echo "📦 Baixando estrutura..."

# ========================
# 👤 ROOT
# ========================

if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute como root (use sudo)"
  exit 1
fi

# ========================
# 🌐 VALIDA URL
# ========================

if [[ ! "$BASE_URL" =~ ^https:// ]]; then
  echo "❌ BASE_URL inválido (precisa ser HTTPS)"
  exit 1
fi

# ========================
# 🔧 DEPENDÊNCIAS
# ========================

command -v curl >/dev/null 2>&1 || {
  echo "❌ curl não está instalado"
  exit 1
}

# ========================
# 📁 DIRETÓRIO
# ========================

cd "${HOME:-/root}"

if [ -d "setup" ]; then
  echo "❌ Pasta 'setup' já existe. Remova antes de continuar."
  exit 1
fi

mkdir -m 700 setup
cd setup

mkdir -m 700 -p lib modules

# ========================
# ⬇️ DOWNLOAD (HARDENED)
# ========================

download() {
  local url="$1"
  local dest="$2"

  echo "⬇️ Baixando \"$dest\"..."

  if ! curl -fsSL --proto '=https' \
    --retry 3 --retry-delay 2 \
    --connect-timeout 10 --max-time 60 \
    "$url" -o "$dest"; then
    echo "❌ Falha ao baixar $dest"
    echo "👉 URL: $url"
    exit 1
  fi

  if [ ! -s "$dest" ]; then
    echo "❌ Arquivo vazio: $dest"
    exit 1
  fi
}

# ========================
# 📦 LIBS
# ========================

download "$BASE_URL/lib/utils.sh" lib/utils.sh
download "$BASE_URL/lib/input.sh" lib/input.sh

# ========================
# 🔧 MODULES
# ========================

download "$BASE_URL/modules/system.sh" modules/system.sh
download "$BASE_URL/modules/projects.sh" modules/projects.sh
download "$BASE_URL/modules/docker.sh" modules/docker.sh
download "$BASE_URL/modules/jenkins.sh" modules/jenkins.sh
download "$BASE_URL/modules/pipelines.sh" modules/pipelines.sh
download "$BASE_URL/modules/npm.sh" modules/npm.sh
download "$BASE_URL/modules/ssl.sh" modules/ssl.sh
download "$BASE_URL/modules/proxy.sh" modules/proxy.sh

# ========================
# ⚙️ CORE
# ========================

download "$BASE_URL/config.sh" config.sh
download "$BASE_URL/setup.sh" setup.sh

chmod 600 config.sh
chmod +x setup.sh

# ========================
# 🚀 EXECUÇÃO
# ========================

echo ""
echo "✅ Estrutura baixada com sucesso"
echo "🚀 Iniciando instalação..."
echo ""

exec /bin/bash setup.sh

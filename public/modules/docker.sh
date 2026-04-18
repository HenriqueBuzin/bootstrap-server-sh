#!/bin/bash

setup_docker() {

  log "🐳 Instalando Docker..."

  require_command curl
  require_command gpg

  install -m 0755 -d /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    log "Adicionando chave GPG do Docker..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  else
    debug "Chave GPG já existe"
  fi

  if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    log "Adicionando repositório Docker..."

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
  else
    debug "Repositório Docker já existe"
  fi

  log "Atualizando pacotes..."
  retry 5 apt update

  log "Instalando Docker Engine..."
  retry 5 apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  log "Ativando Docker..."
  systemctl enable docker
  systemctl start docker

  # valida se subiu
  if ! systemctl is-active --quiet docker; then
    die "Docker não iniciou corretamente"
  fi

  success "Docker está ativo"

  # ========================
  # 🌐 REDE DOCKER
  # ========================

  log "🌐 Criando rede proxy-network..."

  if ! docker network inspect proxy-network >/dev/null 2>&1; then
    docker network create proxy-network
    success "Rede criada: proxy-network"
  else
    debug "Rede proxy-network já existe"
  fi

  # ========================
  # 🧪 VALIDAÇÃO FINAL
  # ========================

  if ! docker info >/dev/null 2>&1; then
    die "Docker instalado, mas não responde"
  fi

  success "🐳 Docker pronto para uso"
}

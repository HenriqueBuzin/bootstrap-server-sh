#!/bin/bash

setup_system() {

  log "🛠️ Preparando sistema..."

  require_command apt

  # ========================
  # 🔄 UPDATE
  # ========================

  log "Atualizando sistema..."

  retry 5 apt update
  retry 3 apt upgrade -y
  retry 3 apt full-upgrade -y

  apt autoremove -y
  apt autoclean -y
  apt clean

  success "Sistema atualizado"

  # ========================
  # 🔧 DEPENDÊNCIAS
  # ========================

  log "Instalando dependências..."

  retry 5 apt install -y \
    curl \
    gnupg \
    lsb-release \
    ca-certificates \
    git \
    jq \
    htop \
    ufw \
    fail2ban \
    certbot \
    python3-certbot-dns-cloudflare

  success "Dependências instaladas"

  # ========================
  # 🔎 VALIDAÇÕES
  # ========================

  require_command curl
  require_command jq
  require_command certbot

  # ========================
  # 🔥 FIREWALL (UFW)
  # ========================

  log "Configurando firewall..."

  ufw default deny incoming
  ufw default allow outgoing

  ufw allow 22
  ufw allow 80
  ufw allow 443

  ufw limit 22

  # ativa sem prompt
  ufw --force enable

  success "Firewall ativo"

  # ========================
  # 🛡️ FAIL2BAN
  # ========================

  log "Configurando Fail2Ban..."

  cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
EOF

  systemctl enable fail2ban
  systemctl restart fail2ban

  success "Fail2Ban ativo"

  # ========================
  # 📁 BASE DIR
  # ========================

  log "Criando estrutura base..."

  ensure_dir /root/envs
  ensure_dir /root/envs/apps
  ensure_dir /root/envs/projects
  ensure_dir /root/envs/global

  success "Estrutura criada"

  # ========================
  # 🧪 FINAL CHECK
  # ========================

  if ! systemctl is-active --quiet fail2ban; then
    warn "Fail2Ban não está ativo corretamente"
  fi

  success "🛠️ Sistema pronto"
}

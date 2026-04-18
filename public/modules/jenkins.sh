#!/bin/bash

setup_jenkins() {

  log "🛠️ Configurando Jenkins..."

  local JENKINS_DIR="/root/jenkins"
  local ENV_DIR="/root/envs/global"

  ensure_dir "$JENKINS_DIR"
  ensure_dir "$ENV_DIR"

  # ========================
  # 🔐 VALIDA ENV
  # ========================

  if [ ! -f "$ENV_DIR/jenkins.env" ]; then
    die "jenkins.env não encontrado em $ENV_DIR"
  fi

  set -a
  source "$ENV_DIR/jenkins.env"
  set +a

  if [ -z "${PROXY_NETWORK:-}" ]; then
    die "PROXY_NETWORK não definido (config.sh não carregado?)"
  fi

  if [ -z "$JENKINS_URL" ]; then
    die "JENKINS_URL não definido no jenkins.env"
  fi

  if [ -z "${JENKINS_EXTERNAL_UI_PORT:-}" ] || [ -z "${JENKINS_INTERNAL_UI_PORT:-}" ]; then
    die "Portas do Jenkins não definidas"
  fi

  if [ -z "$JENKINS_USER" ] || [ -z "$JENKINS_PASSWORD" ]; then
    die "JENKINS_USER ou JENKINS_PASSWORD não definidos"
  fi

  ln -sf "$ENV_DIR/jenkins.env" "$JENKINS_DIR/.env"

  cd "$JENKINS_DIR"

  # ========================
  # ⚙️ CASC
  # ========================

  cat <<EOF > jenkins.yaml
jenkins:
  systemMessage: "Jenkins configurado automaticamente"

appearance:
  themeManager:
    disableUserThemes: false
    theme: "darkSystem"
EOF

  # ========================
  # 🐳 DOCKERFILE
  # ========================

  cat <<'EOF' > Dockerfile
FROM jenkins/jenkins:lts-jdk21

USER root

RUN apt-get update && \
    apt-get install -y docker.io docker-compose && \
    apt-get clean

ARG JENKINS_BUILD_MEMORY

ENV JAVA_OPTS="-Xmx${JENKINS_BUILD_MEMORY}"

RUN mkdir -p /usr/share/jenkins/ref && \
    echo 2.0 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state && \
    echo 2.0 > /usr/share/jenkins/ref/jenkins.install.InstallUtil.lastExecVersion

RUN jenkins-plugin-cli --plugins \
    workflow-aggregator \
    git \
    github \
    github-branch-source \
    docker-workflow \
    blueocean \
    configuration-as-code \
    dark-theme \
    theme-manager

RUN mkdir -p /usr/local/jenkins_casc
COPY jenkins.yaml /usr/local/jenkins_casc/jenkins.yaml

ENV CASC_JENKINS_CONFIG=/usr/local/jenkins_casc/jenkins.yaml

USER jenkins
EOF

  # ========================
  # ⚙️ COMPOSE
  # ========================

  cat <<EOF > docker-compose.yml
services:
  jenkins:
    build:
      context: .
      args:
        JENKINS_BUILD_MEMORY: \${JENKINS_BUILD_MEMORY}

    container_name: jenkins
    restart: unless-stopped
    user: root

    ports:
      - "127.0.0.1:${JENKINS_EXTERNAL_UI_PORT}:${JENKINS_INTERNAL_UI_PORT}"
      - "127.0.0.1:${JENKINS_EXTERNAL_AGENT_PORT}:${JENKINS_INTERNAL_AGENT_PORT}"

    env_file:
      - /root/envs/global/jenkins.env

    volumes:
      - ./jenkins_home:/var/jenkins_home
      - ./init.groovy.d:/usr/share/jenkins/ref/init.groovy.d
      - /var/run/docker.sock:/var/run/docker.sock
      - /root:/root
      - /root/envs:/root/envs:ro

    environment:
      - JAVA_OPTS=-Xmx\${JENKINS_RUNTIME_MEMORY}
      - JENKINS_OPTS=-Djenkins.install.runSetupWizard=false

    networks:
      - ${PROXY_NETWORK}

networks:
  ${PROXY_NETWORK}:
    external: true
EOF

  # ========================
  # 🔐 SECURITY GROOVY (CORRETO)
  # ========================

  ensure_dir "$JENKINS_DIR/init.groovy.d"

  cat <<'EOF' > init.groovy.d/security.groovy
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState
import jenkins.model.JenkinsLocationConfiguration

def instance = Jenkins.getInstance()

def user = System.getenv("JENKINS_USER")
def pass = System.getenv("JENKINS_PASSWORD")
def url  = System.getenv("JENKINS_URL")

if (!user || !pass) {
    throw new RuntimeException("Credenciais não definidas")
}

if (!url) {
    throw new RuntimeException("JENKINS_URL não definido")
}

def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount(user, pass)

instance.setSecurityRealm(realm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)

instance.setAuthorizationStrategy(strategy)
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// 🔥 ESSENCIAL
def jlc = JenkinsLocationConfiguration.get()
jlc.setUrl(url)
jlc.save()

instance.save()
EOF

  # ========================
  # 📦 JENKINS HOME
  # ========================

  ensure_dir "$JENKINS_DIR/jenkins_home"
  chown -R 1000:1000 "$JENKINS_DIR/jenkins_home"

  # ========================
  # 🚀 START
  # ========================

  docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1 || {
    log "Criando network ${PROXY_NETWORK}..."
    docker network create "${PROXY_NETWORK}"
  }

  docker compose down --remove-orphans >/dev/null 2>&1 || true
  retry 3 docker compose up -d --build

  wait_for "NPM API" "curl -fsS ${NPM_URL%/}/api >/dev/null" 60

  wait_for "Jenkins" "curl -fsS --connect-timeout 5 --max-time 20 http://localhost:${JENKINS_EXTERNAL_UI_PORT} >/dev/null" 60

  log "🌐 Jenkins URL: ${JENKINS_URL}"

  success "Jenkins está rodando"
}

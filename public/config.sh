#!/bin/bash

# ========================
# 🌐 DOMÍNIOS
# ========================

JENKINS_SUBDOMAIN="jenkins"

# ========================
# 🔐 WEBHOOK
# ========================

WEBHOOK_PATH="/github-webhook/"

# ========================
# 🐳 DOCKER
# ========================

PROXY_NETWORK="proxy-network"

# ========================
# 🚀 PORTAS BASE
# ========================

BASE_PORT=3000

# ========================
# ⚙️ JENKINS - WEB UI
# ========================

JENKINS_INTERNAL_UI_PORT=8080
JENKINS_EXTERNAL_UI_PORT=8082

# ========================
# ⚙️ JENKINS - AGENT
# ========================

JENKINS_INTERNAL_AGENT_PORT=50000
JENKINS_EXTERNAL_AGENT_PORT=50000

# ========================
# 🌐 NPM
# ========================

NPM_INTERNAL_PORT=81
NPM_EXTERNAL_PORT=8081
NPM_URL="http://localhost:${NPM_INTERNAL_PORT}"

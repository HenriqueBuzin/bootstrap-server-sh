#!/bin/bash

# ========================
# 🔐 INPUT COM CONFIRMAÇÃO
# ========================

ask_and_confirm() {
  local label="$1"
  local var_name="$2"
  local secret="${3:-false}"

  local value=""
  local confirm=""

  while true; do

    if [ "$secret" = "true" ]; then
      read -r -s -p "$label: " value
      echo
      read -r -s -p "Confirmar $label: " confirm
      echo
    else
      read -r -p "$label: " value
      read -r -p "Confirmar $label: " confirm
    fi

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    
    confirm="${confirm#"${confirm%%[![:space:]]*}"}"
    confirm="${confirm%"${confirm##*[![:space:]]}"}"
      
    # validações
    if [ "$value" != "$confirm" ]; then
      echo "❌ $label não confere, tente novamente"
      continue
    fi

    if [ -z "$value" ]; then
      echo "❌ $label não pode ser vazio"
      continue
    fi

    # ✅ seguro (sem eval)
    printf -v "$var_name" "%s" "$value"
    break
  done
}

# ========================
# 📥 INPUT SIMPLES
# ========================

ask() {
  local label="$1"
  local var_name="$2"
  local default_value="$3"

  local value=""

  while true; do
    if [ -n "$default_value" ]; then
      read -r -p "$label (default: $default_value): " value
      value="${value:-$default_value}"
    else
      read -r -p "$label: " value
    fi

    # trim
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [ -z "$value" ]; then
      echo "❌ $label não pode ser vazio"
      continue
    fi

    printf -v "$var_name" "%s" "$value"
    break
  done
}

# ========================
# 🔢 INPUT NUMÉRICO
# ========================

ask_number() {
  local label="$1"
  local var_name="$2"

  local value=""

  while true; do
    read -r -p "$label (mínimo 1): " value

    # remove espaços
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    # aceita só números inteiros positivos
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
      echo "❌ Digite apenas números inteiros positivos"
      continue
    fi

    # mínimo = 1
    if [ "$value" -lt 1 ]; then
      echo "❌ O valor mínimo é 1"
      continue
    fi

    printf -v "$var_name" "%s" "$value"
    break
  done
}

# ========================
# 🔘 CONFIRMAÇÃO SIMPLES
# ========================

confirm() {
  local label="$1"
  local response=""

  while true; do
    read -r -p "$label (y/n): " response

    # trim
    response="${response#"${response%%[![:space:]]*}"}"
    response="${response%"${response##*[![:space:]]}"}"

    # lowercase
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')

    # vazio
    if [ -z "$response" ]; then
      echo "❌ Digite y ou n"
      continue
    fi

    case "$response" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "❌ Responda com y ou n" ;;
    esac
  done
}

# ========================
# 🔐 INPUT SECRETO (SEM CONFIRMAR)
# ========================

ask_secret() {
  local label="$1"
  local var_name="$2"

  local value=""

  while true; do
    read -r -s -p "$label: " value
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo

    if [ -z "$value" ]; then
      echo "❌ $label não pode ser vazio"
    else
      printf -v "$var_name" "%s" "$value"
      break
    fi
  done
}

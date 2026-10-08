#!/bin/bash
set -uo pipefail

# Verifica se o sudo está instalado
if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ O sudo não está instalado. Este script precisa do sudo."
    exit 1
fi

# Verifica se o script está sendo executado via sudo
if [ -z "${SUDO_USER:-}" ]; then
    echo "❌ Execute este script usando sudo: sudo $0"
    exit 1
fi

# Global
USER_NAME="$SUDO_USER"
USER_UID=$(id -u "$USER_NAME")
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# Aceita a cópia instalada em ~/.custom/lm-postinstall; senão usa a do repositório.
EXCLUDE_FILE="$USER_HOME/.custom/lm-postinstall/ignore-files"
[ -f "$EXCLUDE_FILE" ] || EXCLUDE_FILE="$SCRIPT_DIR/ignore-files"
RESTIC_REPO="${RESTIC_REPO:-/media/restic/restic_notebook_repo}"

# Testa se o repositório existe
if [ ! -d "$RESTIC_REPO" ]; then
  echo "O caminho $RESTIC_REPO não existe."
  exit 1
fi

# Testa se o restic está instalado
if command -v restic >/dev/null 2>&1; then
    echo "✅ Restic está instalado."
    restic version
else
    echo "❌ Restic não está instalado."
    exit 1
fi

user_do() {
    sudo -u "$USER_NAME" bash -l -c "$1"
}

# Registra o wallpaper em uso (Plasma) para reaplicá-lo na restauração (etapa 26).
# A configuração do Plasma em si já vai no backup; aqui guardamos apenas a
# escolha num arquivo simples. Lê a chave "Image" do grupo
# [Wallpaper][<plugin>][General] do containment do desktop via PlasmaScript.
echo "Registrando wallpaper em uso..."
WALLPAPER_STATE="$USER_HOME/.config/lm-postinstall/wallpaper"
user_do "mkdir -p '$USER_HOME/.config/lm-postinstall'"
WALLPAPER_JS='var c=desktops()[0]; c.currentConfigGroup=["Wallpaper",c.wallpaperPlugin,"General"]; print(c.readConfig("Image"));'
sudo -u "$USER_NAME" env \
    XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$WALLPAPER_JS" \
    > "$WALLPAPER_STATE" 2>/dev/null \
    || echo "⚠️  Não foi possível registrar o wallpaper (continuando)."

# Para os containers Docker usando docker compose
echo "Parando containers com docker compose..."
docker compose -f "$USER_HOME/.custom/docker-apps/docker-compose.yml" down

# Executa o backup com restic
echo "Iniciando backup com Restic no repositório: $RESTIC_REPO"
restic -r "$RESTIC_REPO" backup "$USER_HOME" --exclude-file="$EXCLUDE_FILE" -vv --tag mths --tag kubuntu

# Depois do backup, sobe os containers novamente
echo "Subindo containers com docker compose..."
docker compose -f "$USER_HOME/.custom/docker-apps/docker-compose.yml" up -d stirling-pdf ollama

echo "Backup concluído com sucesso!"

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
# Aceita a cópia instalada em ~/.custom/kubuntu-postinstall; senão usa a do repositório.
EXCLUDE_FILE="$USER_HOME/.custom/kubuntu-postinstall/ignore-files"
[ -f "$EXCLUDE_FILE" ] || EXCLUDE_FILE="$SCRIPT_DIR/ignore-files"
RESTIC_REPO="${RESTIC_REPO:-/mnt/restic/restic_notebook_repo}"

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
WALLPAPER_STATE="$USER_HOME/.config/kubuntu-postinstall/wallpaper"
user_do "mkdir -p '$USER_HOME/.config/kubuntu-postinstall'"
WALLPAPER_JS='var c=desktops()[0]; c.currentConfigGroup=["Wallpaper",c.wallpaperPlugin,"General"]; print(c.readConfig("Image"));'
sudo -u "$USER_NAME" env \
    XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$WALLPAPER_JS" \
    > "$WALLPAPER_STATE" 2>/dev/null \
    || echo "⚠️  Não foi possível registrar o wallpaper (continuando)."

# --- Fidelidade da sessão Plasma ---
# O backup roda dentro da sessão ativa. Decisões do Plasma/KWin ainda em
# memória podem não ter sido gravadas em disco. Avisamos e sincronizamos os
# buffers antes de ler os arquivos. Feito ANTES de derrubar os containers,
# para que um cancelamento não os deixe parados.
if pgrep -x plasmashell >/dev/null 2>&1; then
    echo "⚠️  Sessão Plasma ativa detectada."
    echo "   Para um backup fiel, feche os aplicativos abertos e, de preferência,"
    echo "   faça logout antes de rodar o backup (as configs são gravadas ao sair)."
    if [ -t 0 ]; then
        read -r -p "Continuar com o backup mesmo assim? (y/N): " ans || ans="n"
        case "$ans" in
            [Yy]*) ;;
            *) echo "Backup cancelado."; exit 1 ;;
        esac
    fi
fi
sync

# Para os containers Docker usando docker compose
echo "Parando containers com docker compose..."
docker compose -f "$USER_HOME/.custom/docker-apps/docker-compose.yml" down

# Caminhos de sistema que fazem parte da configuração "fora da home"
# (defaults globais do KDE, login/sessão do SDDM, teclado e /etc/environment).
SYSTEM_PATHS=(
    /etc/xdg
    /etc/sddm.conf
    /etc/sddm.conf.d
    /etc/default/keyboard
    /etc/environment
)
BACKUP_PATHS=("$USER_HOME")
for p in "${SYSTEM_PATHS[@]}"; do
    [ -e "$p" ] && BACKUP_PATHS+=("$p")
done

# Executa o backup com restic
echo "Iniciando backup com Restic no repositório: $RESTIC_REPO"
restic -r "$RESTIC_REPO" backup "${BACKUP_PATHS[@]}" --exclude-file="$EXCLUDE_FILE" -vv --tag mths --tag kubuntu

# Depois do backup, sobe os containers novamente
echo "Subindo containers com docker compose..."
docker compose -f "$USER_HOME/.custom/docker-apps/docker-compose.yml" up -d stirling-pdf ollama

echo "Backup concluído com sucesso!"

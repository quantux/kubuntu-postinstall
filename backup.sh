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
# (defaults globais do KDE, login/sessão do SDDM, teclado, /etc/environment,
# machine-id e estado do Tailscale).
#
# /etc/machine-id: preserva o UUID da máquina. O ID do RustDesk é ligado a ele;
# restaurar o mesmo valor na mesma máquina evita um UUID_MISMATCH/reassign.
# /var/lib/tailscale: chave/estado do nó Tailscale; preserva o IP 100.x e o
# nome do nó (ex.: quantux-1) após a formatação.
SYSTEM_PATHS=(
    /etc/xdg
    /etc/sddm.conf
    /etc/sddm.conf.d
    /etc/default/keyboard
    /etc/environment
    /etc/machine-id
    /var/lib/tailscale
)
BACKUP_PATHS=("$USER_HOME")
for p in "${SYSTEM_PATHS[@]}"; do
    [ -e "$p" ] && BACKUP_PATHS+=("$p")
done

# --- Exclusões automáticas dos .gitignore dos projetos em ~/workspace ---
# Arquivos ignorados pelo git nos repositórios dentro de ~/workspace não vão
# para o backup. Fora de ~/workspace nada é afetado: repositórios em outras
# pastas continuam sendo copiados por inteiro, mesmo que tenham .gitignore.
WORKSPACE_DIR="$USER_HOME/workspace"
GIT_EXCLUDES=()

# Escapa metacaracteres de glob do restic (filepath.Match), já que cada
# caminho é passado como padrão exato em --exclude.
restic_escape_pattern() {
    local p="$1"
    if [[ "$p" == *[\\\*\?\[\]\$]* ]]; then
        p=$(printf '%s' "$p" | sed -e 's/\\/\\\\/g' -e 's/\*/\\*/g' \
            -e 's/?/\\?/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' -e 's/\$/\\$/g')
    fi
    printf '%s' "$p"
}

collect_gitignore_excludes() {
    local tmp_git root rel path

    [ -d "$WORKSPACE_DIR" ] || return 0
    if ! command -v git >/dev/null 2>&1; then
        echo "⚠️  git não encontrado; .gitignore de $WORKSPACE_DIR não será aplicado."
        return 0
    fi

    # Work-tree sintético com índice vazio: assim somente os .gitignore
    # existentes dentro do projeto valem. Sem isso, um .gitignore de um
    # repositório pai (ex.: a própria home) vazaria regras para cá.
    tmp_git=$(mktemp -d) || return 0
    if ! git init -q --bare "$tmp_git" >/dev/null 2>&1; then
        rm -rf "$tmp_git"
        echo "⚠️  Não foi possível preparar as exclusões do git (continuando)."
        return 0
    fi

    # Um projeto por vez: filhos diretos de ~/workspace e raízes de repositórios
    # aninhados (o git não desce em repositório embutido, então cada raiz
    # precisa ser varrida separadamente).
    while IFS= read -r root; do
        [ -d "$root" ] || continue
        while IFS= read -r -d '' rel; do
            path="$root/${rel%/}"
            GIT_EXCLUDES+=("--exclude=$(restic_escape_pattern "$path")")
        done < <(
            cd "$root" &&
            git --git-dir="$tmp_git" --work-tree="$root" \
                ls-files --others --ignored --exclude-standard --directory -z 2>/dev/null
        )
    done < <(
        {
            find "$WORKSPACE_DIR" -mindepth 1 -maxdepth 1 -type d -print
            find "$WORKSPACE_DIR" -name .git -prune -printf '%h\n'
        } 2>/dev/null | sort -u
    )

    rm -rf "$tmp_git"
}

collect_gitignore_excludes
if [ "${#GIT_EXCLUDES[@]}" -gt 0 ]; then
    echo "Excluindo ${#GIT_EXCLUDES[@]} caminho(s) ignorado(s) pelo git em $WORKSPACE_DIR."
fi

# Executa o backup com restic
echo "Iniciando backup com Restic no repositório: $RESTIC_REPO"
restic -r "$RESTIC_REPO" backup "${BACKUP_PATHS[@]}" --exclude-file="$EXCLUDE_FILE" \
    "${GIT_EXCLUDES[@]}" -vv --tag mths --tag kubuntu

# Depois do backup, sobe os containers novamente
echo "Subindo containers com docker compose..."
docker compose -f "$USER_HOME/.custom/docker-apps/docker-compose.yml" up -d stirling-pdf ollama

echo "Backup concluído com sucesso!"

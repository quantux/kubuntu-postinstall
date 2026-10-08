#!/bin/bash
set -uo pipefail

# Orquestrador de restauração pós-instalação do Kubuntu (KDE Plasma).
#
# Cada etapa vive em steps/XX_nome.sh e só é executada uma vez:
# ao concluir com sucesso, um marcador é criado em ~/.postinstall/steps/.
# Em execuções seguintes, as etapas concluídas são puladas. Se houver progresso
# de um recover anterior, o script pergunta se quer recomeçar do zero.

# ---------------------------------------------------------------------------
# Identificação do usuário real (sudo ou usuário atual)
# ---------------------------------------------------------------------------
if [ -n "${SUDO_USER:-}" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="${LOGNAME:-$(id -un)}"
fi
USER_UID=$(id -u "$USER_NAME")
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)

# ---------------------------------------------------------------------------
# Carrega helpers e infraestrutura (marcadores, log, run_step, user_do...)
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Modos auxiliares
# ---------------------------------------------------------------------------
case "${1:-}" in
    --status)
        status_steps
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# Pré-condições (requer sudo)
# ---------------------------------------------------------------------------
if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ O sudo não está instalado. Este script precisa do sudo."
    exit 1
fi

if [ -z "${SUDO_USER:-}" ]; then
    echo "❌ Execute este script usando sudo: sudo $0"
    exit 1
fi

# Variáveis globais usadas pelas etapas
# Kubuntu é baseado no Ubuntu: o codename vem do /etc/os-release
# (ex.: VERSION_CODENAME=resolute). Assim não dependemos mais dos arquivos
# específicos do Mint (/etc/linuxmint/info, /etc/upstream-release).
UBUNTU_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
DOCKER_COMPOSE_PATH="$USER_HOME/.custom/docker-apps/docker-compose.yml"
RESTIC_REPO="${RESTIC_REPO:-/media/restic/restic_notebook_repo}"

# O repositório do restic é opcional: os dados podem já ter sido copiados
# manualmente para a home. A etapa 01 decide, em runtime, se restaura ou pula.
if [ -z "$UBUNTU_CODENAME" ]; then
    echo "⚠️  Não foi possível determinar o codename da distro em /etc/os-release."
fi

# ---------------------------------------------------------------------------
# Inicialização da infraestrutura de idempotência
# ---------------------------------------------------------------------------
init_postinstall

# ---------------------------------------------------------------------------
# Recover anterior? Pergunta se quer recomeçar do zero ou continuar
# ---------------------------------------------------------------------------
if has_steps; then
    show_message "Foi encontrado progresso de um recover anterior."
    status_steps
    echo
    while true; do
        read -r -p "Deseja apagar o progresso e rodar TODAS as etapas de novo? (y/N): " ans || ans="n"
        case "$ans" in
            [Yy]*)
                reset_steps
                init_postinstall
                echo "✔ Progresso apagado. Rodando todas as etapas do zero."
                break
                ;;
            [Nn]*)
                echo "▶ Continuando de onde parou (etapas já concluídas serão puladas)."
                break
                ;;
            *)
                echo "Responda 'y' (sim) ou 'n' (não)."
                ;;
        esac
    done
    echo
fi

# ---------------------------------------------------------------------------
# Carrega as etapas
# ---------------------------------------------------------------------------
for step_file in "$SCRIPT_DIR"/steps/*.sh; do
    # shellcheck disable=SC1090
    source "$step_file"
done

# ---------------------------------------------------------------------------
# Execução das etapas
# ---------------------------------------------------------------------------
FAILED=()

run_step 00-snap                 step_00_snap                 || FAILED+=(00-snap)
run_step_force 01-restore           step_01_restore                || FAILED+=(01-restore)
run_step 02-apt-base               step_02_apt_base               || FAILED+=(02-apt-base)
run_step 03-apt-packages           step_03_apt_packages           || FAILED+=(03-apt-packages)
run_step 04-nvidia                 step_04_nvidia                 || FAILED+=(04-nvidia)
run_step 05-codecs                 step_05_codecs                 || FAILED+=(05-codecs)
run_step 06-fonts                  step_06_fonts                  || FAILED+=(06-fonts)
run_step 09-flatpak                step_09_flatpak                || FAILED+=(09-flatpak)
run_step 10-vscode                 step_10_vscode                 || FAILED+=(10-vscode)
run_step 11-nvim                   step_11_nvim                   || FAILED+=(11-nvim)
run_step 12-android-studio         step_12_android_studio         || FAILED+=(12-android-studio)
run_step 13-android-sdk            step_13_android_sdk            || FAILED+=(13-android-sdk)
run_step 14-scrcpy                 step_14_scrcpy                 || FAILED+=(14-scrcpy)
run_step 15-virtualbox             step_15_virtualbox             || FAILED+=(15-virtualbox)
run_step 16-antigravity            step_16_antigravity            || FAILED+=(16-antigravity)
run_step 17-teamviewer-ohmyposh    step_17_teamviewer_ohmyposh    || FAILED+=(17-teamviewer-ohmyposh)
run_step 18-desktop-env            step_18_desktop_env            || FAILED+=(18-desktop-env)
run_step 19-tailscale              step_19_tailscale              || FAILED+=(19-tailscale)
run_step 20-ssh                    step_20_ssh                    || FAILED+=(20-ssh)
run_step 21-docker                 step_21_docker                 || FAILED+=(21-docker)
run_step 22-shell                  step_22_shell                  || FAILED+=(22-shell)
run_step 23-cleanup                step_23_cleanup                || FAILED+=(23-cleanup)
run_step 24-udev                   step_24_udev                   || FAILED+=(24-udev)
run_step 26-wallpaper              step_26_wallpaper              || FAILED+=(26-wallpaper)
run_step 27-certificado            step_27_certificado            || FAILED+=(27-certificado)

# ---------------------------------------------------------------------------
# Resumo final
# ---------------------------------------------------------------------------
echo
if [ ${#FAILED[@]} -gt 0 ]; then
    show_message "⚠️  Restauração terminou com ${#FAILED[@]} etapa(s) falhada(s): ${FAILED[*]}"
    echo "Corrija o problema e reexecute: sudo $0"
    echo "Log completo em: $POSTINSTALL_LOG"
    exit 1
fi

show_message "🎉 Restauração concluída com sucesso!"
echo "Etapas concluídas:"
for m in "$POSTINSTALL_STEPS"/*; do
    [ -e "$m" ] && echo "  ✔ $(basename "$m")"
done
echo
echo "Log completo em: $POSTINSTALL_LOG"

# Reiniciar
while true; do
    read -p "Deseja reiniciar? (y/N): " yn || break
    case $yn in
        [Yy]* ) reboot; break;;
        [Nn]* ) break;;
        * ) echo "Responda 'y' (sim) ou 'n' (não).";;
    esac
done

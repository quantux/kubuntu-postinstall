#!/bin/bash

# Etapa 01 - Restaura o backup do Restic (opcional) e ajusta o relógio
# (Windows dualboot).
#
# Esta etapa SEMPRE pergunta (não é pulada por marcador), para lembrar o
# usuário de montar o repositório do restic. Se ele não estiver montado,
# pergunta se você quer recuperar os dados e, em caso afirmativo, pede para
# montar o repositório e rodar de novo.

step_01_restore() {
    timedatectl set-local-rtc 1

    local ans=""

    # --- Repositório não montado: apenas lembra e pergunta ---
    if [ ! -d "$RESTIC_REPO" ]; then
        if [ -t 0 ]; then
            read -r -p "Quer recuperar seus dados a partir do repositório restic? (y/N): " ans || ans=""
        else
            echo "⚠️  Sem terminal interativo; pulando a restauração via restic."
        fi

        case "$ans" in
            [Yy]*)
                echo "❌ Repositório restic não encontrado em $RESTIC_REPO."
                echo "   Monte o repositório e execute novamente o recover."
                return 1
                ;;
            *)
                show_message "Restauração via restic pulada. Mantendo os dados já presentes em $USER_HOME."
                return 0
                ;;
        esac
    fi

    # --- Repositório montado ---
    if ! command -v restic >/dev/null 2>&1; then
        echo "❌ O repositório existe, mas o comando 'restic' não está instalado."
        echo "   Instale com: sudo apt-get install -y restic"
        return 1
    fi

    show_message "Repositório restic detectado: $RESTIC_REPO"
    echo "Snapshots disponíveis (tag mths):"
    restic -r "$RESTIC_REPO" snapshots --tag mths 2>/dev/null | tail -n +2 || true
    echo

    if [ -t 0 ]; then
        read -r -p "Restaurar os dados via restic agora? (y/N): " ans || ans=""
    else
        echo "⚠️  Sem terminal interativo; pulando a restauração via restic."
    fi

    case "$ans" in
        [Yy]*)
            show_message "Restaurando backup Restic diretamente para $USER_HOME..."
            restic -r "$RESTIC_REPO" restore latest --target / --tag mths
            ;;
        *)
            show_message "Restauração via restic pulada. Mantendo os dados já presentes em $USER_HOME."
            ;;
    esac
}

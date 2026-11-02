#!/bin/bash

# Etapa 01 - Restaura o backup do Restic (opcional) e ajusta o relógio
# (Windows dualboot).
#
# A decisão (restaurar ou não, e se o diretório do repositório existe) é tomada
# no início do recover.sh, antes de qualquer etapa. A senha do restic também é
# pedida uma única vez lá e exportada em RESTIC_PASSWORD. Aqui apenas executamos
# a restauração quando RESTIC_RESTORE=yes, antes de qualquer outro pacote.
# Mesmo assim, revalidamos a existência do diretório antes de chamar o restic.

step_01_restore() {
    timedatectl set-local-rtc 1

    if [ "${RESTIC_RESTORE:-no}" != "yes" ]; then
        show_message "Restauração via restic pulada. Mantendo os dados já presentes em $USER_HOME."
        return 0
    fi

    if ! command -v restic >/dev/null 2>&1; then
        echo "❌ O comando 'restic' não está instalado."
        echo "   Instale com: sudo apt-get install -y restic"
        return 1
    fi

    if ! restic_repo_available "$RESTIC_REPO"; then
        echo "❌ Repositório restic não encontrado em $RESTIC_REPO."
        echo "   Monte o repositório e execute o recover novamente."
        return 1
    fi

    show_message "Restaurando backup Restic diretamente para $USER_HOME..."
    restic -r "$RESTIC_REPO" restore latest --target / --tag mths
}

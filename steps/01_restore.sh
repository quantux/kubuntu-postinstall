#!/bin/bash

# Etapa 01 - Restaura o backup do Restic (opcional) e ajusta o relógio
# (Windows dualboot).
#
# A decisão (restaurar ou não, e se o repositório está montado) é tomada no
# início do recover.sh, antes de qualquer etapa. Aqui apenas executamos a
# restauração quando RESTIC_RESTORE=yes. Mesmo assim, revalidamos o mount para
# nunca escrever no disco raiz por engano.

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

    if ! restic_repo_mounted "$RESTIC_REPO"; then
        echo "❌ Repositório restic não está montado em $RESTIC_REPO."
        echo "   Monte o repositório e execute o recover novamente."
        return 1
    fi

    show_message "Restaurando backup Restic diretamente para $USER_HOME..."
    restic -r "$RESTIC_REPO" restore latest --target / --tag mths
}

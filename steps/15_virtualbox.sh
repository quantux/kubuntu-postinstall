#!/bin/bash

# Etapa 15 - Instala o VirtualBox. Tenta o repositório oficial da Oracle para
# o codename atual do Ubuntu/Kubuntu e, se ele não existir (codename novo
# demais), cai para o pacote da própria distro.

step_15_virtualbox() {
    show_message "Instalando VirtualBox"

    if [ -n "$UBUNTU_CODENAME" ]; then
        wget -O- https://www.virtualbox.org/download/oracle_vbox_2016.asc \
            | gpg --yes --output /usr/share/keyrings/oracle-virtualbox-2016.gpg --dearmor
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $UBUNTU_CODENAME contrib" \
            > /etc/apt/sources.list.d/virtualbox.list
        # O repositório da Oracle pode ainda não ter pacotes para codenames
        # muito recentes; um erro aqui não deve derrubar a etapa.
        apt-get update || true

        VBOX_PKG="virtualbox-$(curl -s https://download.virtualbox.org/virtualbox/LATEST.TXT | cut -d. -f1-2 || true)"
        if [ -z "$VBOX_PKG" ] || ! apt-cache show "$VBOX_PKG" >/dev/null 2>&1; then
            VBOX_PKG=$(apt-cache search --names-only '^virtualbox-[0-9]' | awk '{print $1}' | sort -V | tail -1 || true)
        fi
    fi

    # Fallback para o pacote empacotado pela distro.
    if [ -z "${VBOX_PKG:-}" ] || ! apt-cache show "$VBOX_PKG" >/dev/null 2>&1; then
        echo "ℹ️  Repositório oficial indisponível para '$UBUNTU_CODENAME'; usando o pacote 'virtualbox' da distro."
        VBOX_PKG="virtualbox"
    fi

    apt-get install -y "$VBOX_PKG"
}

#!/bin/bash

# Etapa 02 - Base do sistema no Kubuntu: arquitetura 32 bits e atualização.
#
# No Kubuntu os repositórios já vêm configurados pelo instalador (formato
# deb822 em /etc/apt/sources.list.d/ubuntu.sources), então não reescrevemos
# mirrors como era feito no Mint.

step_02_apt_base() {
    show_message "Habilitando pacotes de 32 bits"
    dpkg --add-architecture i386

    show_message "Atualizando repositórios"
    apt-get update

    show_message "Atualizando pacotes"
    apt-get upgrade -y
}

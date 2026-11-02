#!/bin/bash

# Etapa 09 - Adiciona o repositório flathub e instala/atualiza pacotes Flatpak
# (pacotes_flatpak.txt). O pacote flatpak em si vem por apt (pacotes_apt.txt).

step_09_flatpak() {
    show_message "Adicionando repositório flathub"
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    show_message "Instalando pacotes flatpak"
    flatpak install -y --noninteractive flathub $(cat pacotes_flatpak.txt)

    show_message "Atualizando pacotes flatpak"
    flatpak update -y
}

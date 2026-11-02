#!/bin/bash

# Etapa 06 - Fontes: Roboto, Noto Sans, NerdFont FiraCode e fontes do WPS Office.
#
# Roboto e Noto Sans vêm dos pacotes apt fonts-roboto e fonts-noto-core
# (listados em pacotes_apt.txt, instalados na etapa 03). O download antigo de
# fonts.google.com/download retornava HTML em vez do ZIP, então foi removido.

step_06_fonts() {
    show_message "Instalando fontes NerdFont Firacode"
    FIRACODE_URL=$(curl -s "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" \
        | grep -oE '"browser_download_url": "[^"]*FiraCode\.zip"' | cut -d'"' -f4 || true)
    [ -n "$FIRACODE_URL" ] || { echo "❌ Falha ao obter o link do FiraCode"; return 1; }
    wget "$FIRACODE_URL" -O /tmp/firacode.zip
    unzip -q -o /tmp/firacode.zip -d /usr/share/fonts/

    show_message "Instalando fontes para o WPS Office"
    if git clone --depth 1 https://github.com/udoyen/wps-fonts.git /tmp/wps-fonts; then
        mv /tmp/wps-fonts/wps /usr/share/fonts/
    else
        echo "⚠️  Falha ao baixar as fontes do WPS; continuando."
    fi

    show_message "Atualizando o cache de fontes"
    fc-cache -f >/dev/null 2>&1 || true
}

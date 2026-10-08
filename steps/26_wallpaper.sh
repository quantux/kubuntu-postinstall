#!/bin/bash

# Etapa 26 - Reaplica o wallpaper registrado no último backup.
#
# No Plasma a configuração do papel de parede fica em ~/.config e é restaurada
# pelo restic na etapa 01. Ainda assim, reaplicamos explicitamente a escolha
# registrada pelo backup.sh usando plasma-apply-wallpaperimage (funciona tanto
# em X11 quanto em Wayland).

step_26_wallpaper() {
    local state="$USER_HOME/.config/kubuntu-postinstall/wallpaper"

    if [ ! -s "$state" ]; then
        show_message "⚠️  Nenhum wallpaper registrado no último backup. Pulando."
        return 0
    fi

    local uri
    uri=$(cat "$state")
    uri="${uri%\'}"; uri="${uri#\'}"   # remove aspas simples do gsettings antigo
    uri="${uri#file://}"               # aceita "file:///..." ou caminho puro

    if [ ! -e "$uri" ]; then
        show_message "⚠️  Imagem do wallpaper não encontrada: $uri. Pulando."
        return 0
    fi

    if ! command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
        show_message "⚠️  plasma-apply-wallpaperimage não encontrado; não foi possível reaplicar o wallpaper."
        return 0
    fi

    show_message "Restaurando wallpaper do último backup: $uri"
    sudo -u "$USER_NAME" env \
        XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
        plasma-apply-wallpaperimage "$uri"
}

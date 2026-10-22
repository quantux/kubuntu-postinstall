#!/bin/bash

# Etapa 29 - Tema escuro (Breeze-Dark) para aplicativos GTK
#
# O Plasma usa Breeze Dark, mas os aplicativos GTK (GParted, etc.) abrem com o
# Adwaita claro. O tema é aplicado em três frentes, porque cada uma é
# consultada em um contexto diferente:
#
#   1. gsettings - é o que o GTK3 do Ubuntu realmente lê na sessão Wayland.
#                  Fica no dconf do usuário e volta junto no backup restic.
#   2. arquivos  - ~/.config/gtk-{3,4}.0/settings.ini, ~/.gtkrc-2.0 e
#                  ~/.config/xsettingsd/xsettingsd.conf (X11, GTK2 e fallback).
#   3. /root     - o GParted roda via pkexec com HOME=/root; sem configuração
#                  lá ele ignora o tema do usuário e volta para o Adwaita.
#
# Idempotente: as chaves são substituídas (nunca duplicadas) e o restante dos
# arquivos é preservado.

# Define uma chave em ~/.config/gtk-{3,4}.0/settings.ini, garantindo o grupo
# [Settings] (sem ele o GTK ignora o arquivo inteiro).
# Uso: gtk_ini_set <arquivo> <chave> <valor>
gtk_ini_set() {
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -qE '^[[:space:]]*\[Settings\]' "$file"; then
        printf '[Settings]\n' | cat - "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
    sed -i -E "\|^[[:space:]]*${key}[[:space:]]*=|d" "$file"
    printf '%s=%s\n' "$key" "$value" >> "$file"
}

# Define uma chave em um arquivo chave=valor sem grupos (ex.: .gtkrc-2.0).
# Uso: ini_set <arquivo> <chave> <valor>
ini_set() {
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    sed -i -E "\|^[[:space:]]*${key}[[:space:]]*=|d" "$file"
    printf '%s=%s\n' "$key" "$value" >> "$file"
}

# Define uma chave no xsettingsd.conf, que usa o formato "chave valor".
# Uso: xsettings_set <arquivo> <chave> <valor>
xsettings_set() {
    local file="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    sed -i -E "\|^[[:space:]]*${key}[[:space:]]|d" "$file"
    printf '%s %s\n' "$key" "$value" >> "$file"
}

# Roda gsettings como o usuário, na sessão gráfica dele (o dconf exige o
# barramento de sessão).
gtk_user_gsettings() {
    sudo -u "$USER_NAME" env \
        HOME="$USER_HOME" \
        XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
        gsettings "$@"
}

step_29_gtk_theme() {
    local gtk_theme="Breeze-Dark"
    local icon_theme="breeze-dark"
    local user_gid
    user_gid=$(id -g "$USER_NAME")

    local gtk3="$USER_HOME/.config/gtk-3.0/settings.ini"
    local gtk4="$USER_HOME/.config/gtk-4.0/settings.ini"
    local gtk2="$USER_HOME/.gtkrc-2.0"
    local xsettings="$USER_HOME/.config/xsettingsd/xsettingsd.conf"

    show_message "Instalando o tema GTK Breeze-Dark"
    if ! dpkg -s breeze-gtk-theme >/dev/null 2>&1; then
        apt-get install -y breeze-gtk-theme
    fi

    show_message "Configurando o tema GTK do usuário ($USER_NAME)"
    local ini
    for ini in "$gtk3" "$gtk4"; do
        gtk_ini_set "$ini" gtk-theme-name "$gtk_theme"
        gtk_ini_set "$ini" gtk-icon-theme-name "$icon_theme"
        gtk_ini_set "$ini" gtk-application-prefer-dark-theme true
    done

    # GTK2 usa valores entre aspas.
    ini_set "$gtk2" gtk-theme-name "\"$gtk_theme\""
    ini_set "$gtk2" gtk-icon-theme-name "\"$icon_theme\""

    xsettings_set "$xsettings" Net/ThemeName "\"$gtk_theme\""
    xsettings_set "$xsettings" Net/IconThemeName "\"$icon_theme\""

    # O KDE grava esses arquivos como 0600; mantém dono e permissão originais.
    chown "$USER_UID:$user_gid" "$gtk3" "$gtk4" "$gtk2" "$xsettings"
    chmod 600 "$gtk3" "$gtk4" "$gtk2" "$xsettings"

    show_message "Aplicando o tema no gsettings/dconf do usuário"
    gtk_user_gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" \
        || echo "⚠️  Não foi possível gravar o gsettings; os arquivos .ini continuam válidos."
    gtk_user_gsettings set org.gnome.desktop.interface color-scheme prefer-dark \
        || echo "⚠️  Não foi possível definir color-scheme; apps libadwaita podem ficar claros."

    show_message "Espelhando a configuração para o root (GParted via pkexec)"
    install -D -m 600 "$gtk3" /root/.config/gtk-3.0/settings.ini
    install -D -m 600 "$gtk4" /root/.config/gtk-4.0/settings.ini
    install -D -m 600 "$gtk2" /root/.gtkrc-2.0

    # O xsettingsd só é consultado no X11 e lê o arquivo ao iniciar; recarrega
    # apenas se estiver rodando (no próximo login ele já sobe com o tema certo).
    if pgrep -x xsettingsd >/dev/null 2>&1; then
        pkill -x xsettingsd || true
        sleep 1
        if [ -n "${DISPLAY:-}" ]; then
            sudo -u "$USER_NAME" env \
                HOME="$USER_HOME" \
                DISPLAY="$DISPLAY" \
                XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
                setsid -f xsettingsd >/dev/null 2>&1 || true
        else
            echo "ℹ️  xsettingsd será recarregado no próximo login."
        fi
    fi
}

#!/bin/bash

# Etapa 09 - Adiciona o repositório flathub e instala/atualiza pacotes Flatpak
# (pacotes_flatpak.txt). O pacote flatpak em si vem por apt (pacotes_apt.txt).
#
# Os apps são instalados na instalação --user do usuário real: é onde o backup
# restaura ~/.local/share/flatpak e onde os apps aparecem no menu do Plasma.
# Rodar como root criaria uma instalação de sistema separada, e os apps não
# apareceriam para o usuário.

step_09_flatpak() {
    local app failed=()
    local env_session="HOME=$USER_HOME XDG_RUNTIME_DIR=/run/user/${USER_UID} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_UID}/bus"

    show_message "Adicionando repositório flathub (usuário $USER_NAME)"
    sudo -u "$USER_NAME" env $env_session \
        flatpak --user remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo

    show_message "Instalando pacotes flatpak"
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        case "$app" in \#*) continue ;; esac

        echo "  - $app"
        if ! sudo -u "$USER_NAME" env $env_session \
                flatpak --user install -y --noninteractive flathub "$app"; then
            echo "⚠️  Falha ao instalar: $app"
            failed+=("$app")
        fi
    done < pacotes_flatpak.txt

    show_message "Atualizando pacotes flatpak"
    sudo -u "$USER_NAME" env $env_session flatpak --user update -y || true

    # Sessões gráficas iniciadas pelo SDDM não leem /etc/profile.d/flatpak.sh,
    # então os apps --user ficam fora do XDG_DATA_DIRS e não aparecem no menu
    # do Plasma. O Plasma lê ~/.config/plasma-workspace/env/*.sh no login.
    show_message "Integrando apps Flatpak ao menu do Plasma"
    local plasma_env_dir="$USER_HOME/.config/plasma-workspace/env"
    install -d -m 755 "$plasma_env_dir"
    cat > "$plasma_env_dir/flatpak.sh" <<'EOF'
# Adiciona a instalação Flatpak do usuário ao XDG_DATA_DIRS para que os apps
# apareçam no menu do Plasma. Necessário porque sessões gráficas iniciadas
# pelo SDDM não leem /etc/profile.d/flatpak.sh.
if [ -d "$HOME/.local/share/flatpak/exports/share" ]; then
    case ":$XDG_DATA_DIRS:" in
        *":$HOME/.local/share/flatpak/exports/share:"*) ;;
        *) export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:$HOME/.local/share/flatpak/exports/share" ;;
    esac
fi
EOF
    chown "$USER_NAME:$USER_NAME" \
        "$USER_HOME/.config/plasma-workspace" \
        "$plasma_env_dir" "$plasma_env_dir/flatpak.sh"

    if [ ${#failed[@]} -gt 0 ]; then
        echo "❌ Falha em ${#failed[@]} pacote(s) flatpak: ${failed[*]}"
        return 1
    fi
}

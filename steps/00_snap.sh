#!/bin/bash

# Etapa 00 - Remove completamente o snap do sistema.
#
# O objetivo é não deixar nada de snap: apps, daemons, diretórios e mounts.
# Os apps que eram snap (firefox, thunderbird, krita, element-desktop) são
# repostos via Flatpak na etapa 09; o ffmpeg continua vindo por apt.
# Por fim, cria /etc/apt/preferences.d/nosnap.pref para impedir que o snapd
# seja reinstalado como dependência de outro pacote.

step_00_snap() {
    show_message "Removendo o snap do sistema"

    export DEBIAN_FRONTEND=noninteractive

    # 1) Remove todos os snaps instalados (o snapd precisa estar rodando).
    if command -v snap >/dev/null 2>&1; then
        echo "Removendo snaps instalados..."
        snap list 2>/dev/null | awk 'NR>1 {print $1}' | while read -r name; do
            if [ -z "$name" ] || [ "$name" = "snapd" ]; then
                continue
            fi
            echo "  - snap remove --purge $name"
            snap remove --purge "$name" || true
        done
    fi

    # 2) Para e desabilita os serviços do snapd.
    show_message "Desabilitando serviços do snapd"
    systemctl disable --now \
        snapd.service snapd.socket snapd.seeded.service snapd.apparmor.service \
        snapd.autoimport.service snapd.core-fixup.service \
        snapd.recovery-chooser-trigger.service snapd.system-shutdown.service \
        snapd.snap-repair.timer 2>/dev/null || true

    # 3) Purga o snapd e os pacotes relacionados (frontend do Discover, libs).
    show_message "Purgando o snapd"
    apt-get purge -y snapd plasma-discover-backend-snap \
        libsnapd-glib-2-1 libsnapd-qt-2-1 || true

    # 4) Desmonta restos de squashfs do snap e remove os diretórios.
    show_message "Removendo diretórios e mounts do snap"
    while read -r target; do
        [ -n "$target" ] && umount -l "$target" 2>/dev/null || true
    done < <(findmnt -rno TARGET 2>/dev/null | grep -E '^/snap(/|$)') || true

    rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd || true
    rm -rf "$USER_HOME/snap" || true

    # 5) Desabilita o agente de sessão do usuário e limpa resquícios.
    sudo -u "$USER_NAME" env XDG_RUNTIME_DIR="/run/user/${USER_UID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID}/bus" \
        systemctl --user disable --now snapd.session-agent.socket snapd.session-agent.service \
        2>/dev/null || true

    rm -f /etc/apt/apt.conf.d/20snapd.conf || true
    rm -f /etc/xdg/autostart/snap-userd-autostart.desktop || true
    rm -f /etc/apparmor.d/usr.lib.snapd.snap-confine.real || true

    # 6) Bloqueia a reinstalação do snapd.
    show_message "Bloqueando reinstalação do snapd (nosnap.pref)"
    cat > /etc/apt/preferences.d/nosnap.pref <<'EOF'
# Não usamos snap: impede que o snapd seja instalado como dependência.
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

    echo "✔ Snap removido do sistema."
}

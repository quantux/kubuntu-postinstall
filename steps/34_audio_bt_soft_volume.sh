#!/bin/bash

# Etapa 34 - Volume por software no headset Fuxi-H3 via Bluetooth.
#
# O Fuxi-H3 também funciona por Bluetooth (A2DP) e expõe volume por hardware
# (AVRCP). Com áudio tocando, o volume reportado de volta ao PipeWire-Pulse
# fica defasado; o módulo KDED `audioshortcutsservice` (atalhos Fn de volume do
# Plasma) calcula o próximo passo a partir do volume em cache do sink, então as
# teclas Fn param de mudar o volume. O slider do applet do Plasma (valor
# absoluto) continua funcionando.
#
# Sintoma reproduzido em 2026-11-18 (Plasma 6.6.5, PipeWire 1.6.2): com áudio
# tocando, o cache do KDED ficou em 29%; forçar 60% e apertar "diminuir" levava
# para 24% (29-5). Sem playback, as teclas funcionavam normalmente.
#
# Desligar `bluez5.enable-hw-volume` força volume 100% por software, estável e
# linear — mesma ideia do `api.alsa.soft-mixer` do Fuxi via USB (etapa 28).
#
# Ref: https://wiki.archlinux.org/title/Bluetooth_headset#Hardware_volume
# Incidente: shared-memory/incidents/2026-11-volume-fn-bluetooth.md

step_34_audio_bt_soft_volume() {
    show_message "Desligando volume por hardware (AVRCP) do headset Bluetooth"

    local conf_dir="$USER_HOME/.config/wireplumber/wireplumber.conf.d"
    local conf="$conf_dir/52-fuxi-bt-soft-volume.conf"

    mkdir -p "$conf_dir"

    cat > "$conf" <<'EOF'
# Fuxi-H3 (Bluetooth) - volume por software
#
# O Fuxi-H3 expõe volume por hardware (AVRCP). Enquanto há um stream tocando,
# o volume reportado de volta pelo PipeWire-Pulse fica defasado: o módulo KDED
# `audioshortcutsservice` (atalhos Fn de volume do Plasma) calcula o novo volume
# a partir do volume em cache do sink, então as teclas Fn param de mudar o
# volume (o slider do applet, que manda valor absoluto, continua funcionando).
#
# Desligar o volume por hardware força volume 100% por software, estável e
# linear. Mesma ideia do ajuste `api.alsa.soft-mixer` do Fuxi via USB.
#
# Ref: https://wiki.archlinux.org/title/Bluetooth_headset#Hardware_volume
monitor.bluez.properties = {
  bluez5.enable-hw-volume = false
}
EOF
    chown "$USER_NAME:$USER_NAME" "$conf"
    chmod 644 "$conf"

    echo "✔ Configuração criada em $conf"
    echo "ℹ️  Vale na próxima conexão/reinício do WirePlumber."
}

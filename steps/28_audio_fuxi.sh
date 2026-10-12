#!/bin/bash

# Etapa 28 - Corrige o volume de hardware do headset USB Fuxi-H3.
#
# O dongle expõe dois volumes independentes:
#   1. o volume do sistema (PipeWire/WirePlumber), aplicado por software;
#   2. o volume do próprio chip do dongle, exposto como controle ALSA 'PCM'.
# O PipeWire NÃO mexe no 'PCM', então se o dongle inicializa com ele em 0% o som
# fica mudo mesmo com o volume do sistema em 100% — e aumentar pelo ícone de
# volume não resolve.
#
# Solução: um script sobe o 'PCM' para 100% e é disparado por uma regra udev
# sempre que o dongle é reconhecido (no boot ou em replug). Também roda uma vez
# ao final desta etapa. NÃO é necessário o dongle estar conectado durante o
# recover: o ajuste é aplicado quando ele aparecer.
#
# Dongle: USB 040b:0897 (Weltrend Fuxi-H3); o card ALSA aparece com id "FuxiH3".

step_28_audio_fuxi() {
    show_message "Configurando correção de volume do headset Fuxi-H3"

    cat > /usr/local/bin/fuxi-volume-fix.sh <<'EOF'
#!/bin/sh
# Garante que o controle ALSA 'PCM' (volume do chip) do dongle Fuxi-H3 fique em
# 100%. O PipeWire controla o volume por software e NÃO mexe nesse controle; se
# o dongle inicializar com ele em 0%, o som fica mudo mesmo com o sistema em
# 100%. O amixer não aceita o nome da placa em -c (só o número), então
# descobrimos o índice do card pelo id no /proc/asound/cards.

command -v amixer >/dev/null 2>&1 || exit 0

CARD=""
i=0
while [ "$i" -lt 12 ]; do
    CARD="$(awk '/\[FuxiH3/{print $1; exit}' /proc/asound/cards 2>/dev/null)"
    if [ -n "$CARD" ] && amixer -c "$CARD" sget 'PCM',0 >/dev/null 2>&1; then
        amixer -c "$CARD" sset 'PCM',0 100% unmute >/dev/null 2>&1
        amixer -c "$CARD" sset 'PCM',1 100% unmute >/dev/null 2>&1
        logger -t fuxi-volume-fix "volume do Fuxi-H3 (PCM) ajustado para 100%" 2>/dev/null || true
        exit 0
    fi
    i=$((i + 1))
    sleep 0.5
done
exit 0
EOF
    chmod 755 /usr/local/bin/fuxi-volume-fix.sh
    chown root:root /usr/local/bin/fuxi-volume-fix.sh

    cat > /etc/udev/rules.d/70-fuxi-headset-volume.rules <<'EOF'
# Dispara o ajuste do volume de hardware do headset USB Fuxi-H3 (040b:0897)
# sempre que ele é reconhecido, inclusive no boot. O PipeWire controla o volume
# por software e não mexe no controle ALSA 'PCM'; se o dongle inicializar com
# ele em 0%, o som fica mudo mesmo com o volume do sistema em 100%.
#
# systemd-run --no-block evita bloquear o processamento de eventos do udev.
# KERNEL=="card*" restringe ao dispositivo principal do card (evita disparar
# também para controlC*/pcmC* do mesmo card, que gerariam execuções repetidas).
ACTION=="add", SUBSYSTEM=="sound", KERNEL=="card*", ATTRS{idVendor}=="040b", ATTRS{idProduct}=="0897", RUN+="/usr/bin/systemd-run --no-block --collect /usr/local/bin/fuxi-volume-fix.sh"
EOF
    chmod 644 /etc/udev/rules.d/70-fuxi-headset-volume.rules
    chown root:root /etc/udev/rules.d/70-fuxi-headset-volume.rules

    udevadm control --reload-rules

    # Aplica já, caso o dongle esteja presente agora (não aborta a etapa se falhar).
    /usr/local/bin/fuxi-volume-fix.sh || true

    echo "ℹ️  O ajuste é aplicado automaticamente sempre que o dongle for reconectado."
}

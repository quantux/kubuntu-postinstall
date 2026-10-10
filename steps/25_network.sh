#!/bin/bash

# Etapa 25 - Latência de rede no Wi-Fi (MediaTek MT7921).
#
# Medições nesta máquina mostraram picos de latência de até >1s em jogos
# online (ex.: Dead by Daylight), com um padrão "dente de serra". Duas causas
# foram identificadas e confirmadas:
#
#   1. Wi-Fi Power Save habilitado por padrão no Ubuntu/Kubuntu. O arquivo
#      /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf define
#      wifi.powersave = 3 (habilitar), o que faz o firmware do mt7921
#      acumular e entregar frames em rajadas, gerando picos.
#
#   2. PCIe ASPM L1 habilitado no link da placa Wi-Fi (mt7921e). O link entra
#      em economia e, ao acordar, adiciona picos de latência.
#
# Resultado medido (ping 150s): max 1162ms com ASPM ligado -> 22ms desligado.
# Ambas as mudanças são persistidas aqui (aplicam-se no próximo boot).

step_25_network() {
    show_message "Desabilitando Wi-Fi Power Save (NetworkManager)"
    # wifi.powersave: 0=default, 1=ignore, 2=disable, 3=enable
    cat > /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF

    show_message "Desabilitando PCIe ASPM da placa Wi-Fi MediaTek MT7921"
    if modinfo mt7921e >/dev/null 2>&1; then
        cat > /etc/modprobe.d/mt7921e.conf <<'EOF'
options mt7921e disable_aspm=1
EOF
    else
        echo "⚠️  Módulo mt7921e não encontrado; pulando configuração de ASPM."
    fi

    echo "ℹ️  As mudanças passam a valer após reiniciar (o recover reinicia no final)."
}

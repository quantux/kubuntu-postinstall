#!/bin/bash

# Etapa 25 - Latência de rede no Wi-Fi (MediaTek MT7921).
#
# Reúne os ajustes que eliminam picos de latência/ping no Wi-Fi (confirmados
# por medição: ping no gateway + iw event). A execução em rede mesh com Decos
# era o caso mais grave.
#
#   1. Wi-Fi Power Save ligado por padrão no Ubuntu/Kubuntu
#      (/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf define
#      wifi.powersave = 3). O firmware do mt7921 passa a acumular/entregar
#      frames em rajadas -> picos. Solução: desligar (powersave = 2).
#
#   2. PCIe ASPM L1 no link do mt7921e: ao acordar o link, gera picos.
#      Medido: ping max 1162ms (ASPM on) -> 22ms (off).
#      A opção do módulo (disable_aspm=1) sozinha não basta: a politica GLOBAL
#      de ASPM volta a "default" no boot e o L1 é reativado em eventos do link.
#      Por isso fixamos a politica no kernel cmdline (pcie_aspm.policy=performance).
#
#   3. bgscan do wpa_supplicant: o NetworkManager injeta bgscan
#      ("simple:30:-65:300") quando a conexao ja foi associada a mais de um
#      BSSID (mesh / dual-band). Isso faz o radio sair do canal a cada ~5min e
#      derruba o ping por ~4,5s. O NM REINJETA o bgscan a cada ativacao
#      (hardcoded; nao ha config), entao um dispatcher desliga o bgscan no "up".
#      Medido (7min): 84 picos >30ms (max 998ms) -> 1 pico (max 30ms).
#
#   4. TLP/thermald: se instalados, o TLP reativa o ASPM e o power save do
#      Wi-Fi, e o thermald throttla a CPU agressivamente. Ambos desligados
#      (o Linux Mint, por exemplo, nao usa nenhum dos dois por padrao).

step_25_network() {
    show_message "Desabilitando Wi-Fi Power Save (NetworkManager)"
    # wifi.powersave: 0=default, 1=ignore, 2=disable, 3=enable
    cat > /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF

    show_message "Desabilitando PCIe ASPM do Wi-Fi MediaTek MT7921 (modulo)"
    if modinfo mt7921e >/dev/null 2>&1; then
        cat > /etc/modprobe.d/mt7921e.conf <<'EOF'
options mt7921e disable_aspm=1
EOF
    else
        echo "⚠️  Módulo mt7921e não encontrado; pulando opção de ASPM do módulo."
    fi

    show_message "Fixando a política global de ASPM em performance (kernel cmdline)"
    if grep -q 'pcie_aspm.policy=performance' /etc/default/grub; then
        echo "  já presente no /etc/default/grub"
    else
        cp -a /etc/default/grub /etc/default/grub.bak-before-pcie-aspm 2>/dev/null || true
        sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT='\(.*\)'/GRUB_CMDLINE_LINUX_DEFAULT='\1 pcie_aspm.policy=performance'/" /etc/default/grub
        if grep -q 'pcie_aspm.policy=performance' /etc/default/grub; then
            update-grub
        else
            echo "⚠️  Não consegui editar GRUB_CMDLINE_LINUX_DEFAULT; ajuste manualmente:"
            echo "     GRUB_CMDLINE_LINUX_DEFAULT=\"... pcie_aspm.policy=performance\" && update-grub"
        fi
    fi

    show_message "Desligando o bgscan do wpa_supplicant (dispatcher do NetworkManager)"
    cat > /etc/NetworkManager/dispatcher.d/50-wifi-no-bgscan <<'EOF'
#!/bin/sh
# Desliga o "bgscan" do wpa_supplicant na interface Wi-Fi.
#
# O NetworkManager injeta bgscan = "simple:30:-65:300" a cada ativacao quando a
# conexao ja foi associada a mais de um BSSID (mesh / dual-band), fazendo o
# radio escanear a cada ~5min e derrubar o ping por ~4,5s.
# Como o NM REINJETA o bgscan a cada conexao, este hook roda no "up" e desliga.
#
# NAO trava BSSID -> mantem a troca de AP (mesh) no reconnect/perda de sinal.
IFACE="$DEVICE_IFACE"
ACT="$2"
case "$IFACE" in wl*) ;; *) exit 0 ;; esac
[ "$ACT" = "up" ] || exit 0
ID=$(wpa_cli -i "$IFACE" list_networks 2>/dev/null | awk '/\[CURRENT\]/{print $1}' | head -1)
[ -n "$ID" ] || ID=0
wpa_cli -i "$IFACE" set_network "$ID" bgscan "" >/dev/null 2>&1
exit 0
EOF
    chmod 755 /etc/NetworkManager/dispatcher.d/50-wifi-no-bgscan
    chown root:root /etc/NetworkManager/dispatcher.d/50-wifi-no-bgscan

    show_message "Desligando TLP e thermald (reativam ASPM/powersave e throttlam a CPU)"
    for svc in tlp thermald; do
        if systemctl cat "${svc}.service" >/dev/null 2>&1; then
            systemctl disable --now "${svc}.service" >/dev/null 2>&1 || true
            echo "  ✔ ${svc} desabilitado"
        fi
    done

    echo "ℹ️  As mudanças passam a valer após reiniciar (o recover reinicia no final)."
}

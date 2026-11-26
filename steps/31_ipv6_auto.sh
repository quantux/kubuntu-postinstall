#!/bin/bash

# Etapa 31 - IPv6 automático: garante IPv6 (SLAAC/DHCPv6) nas conexões
# Ethernet/Wi-Fi do NetworkManager.
#
# O gateway Huawei foi religado em modo 3 (IPv4+IPv6) em 2026-11-25 e anuncia
# prefixo na LAN. Esta etapa ajusta todas as conexões Ethernet/Wi-Fi do
# NetworkManager para ipv6.method=auto, por UUID (há nomes "Home" duplicados no
# perfil). O Tailscale mantém o IPv6 interno fd7a:... separado.

step_31_ipv6_auto() {
    show_message "Habilitando IPv6 automático nas conexões Ethernet/Wi-Fi"

    if ! command -v nmcli >/dev/null 2>&1; then
        echo "⚠️  nmcli não encontrado; pulando."
        return 0
    fi

    local changed=0 uuid type
    while IFS=: read -r uuid type; do
        case "$type" in
            802-11-wireless|802-3-ethernet) ;;
            *) continue ;;
        esac

        if [ "$(nmcli -g ipv6.method connection show "$uuid" 2>/dev/null)" != "auto" ]; then
            nmcli connection modify "$uuid" ipv6.method auto
            echo "✔ IPv6 automático em $type ($uuid)"
            changed=1
        fi
    done < <(nmcli -t -f UUID,TYPE connection show)

    if [ "$changed" -eq 0 ]; then
        echo "✔ Todas as conexões Ethernet/Wi-Fi já estão com IPv6 automático."
    fi

    echo "ℹ️  Vale no próximo reconnect/boot. O gateway precisa estar em modo 3 (IPv4+IPv6)."
}

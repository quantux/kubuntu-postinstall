#!/bin/bash

# Etapa 31 - IPv4-only: desabilita IPv6 nas conexões Ethernet/Wi-Fi.
#
# O gateway Huawei está em modo 1 (IPv4-only), mas o PC pode continuar com
# IPv6 link-local/global até expirar. Esta etapa desabilita IPv6 em todas as
# conexões Ethernet/Wi-Fi do NetworkManager, por UUID (há nomes "Home"
# duplicados no perfil). O Tailscale mantém o IPv6 interno fd7a:...; o
# tráfego de LAN/internet fica IPv4.

step_31_ipv4_only() {
    show_message "Desabilitando IPv6 nas conexões Ethernet/Wi-Fi (IPv4-only)"

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

        if [ "$(nmcli -g ipv6.method connection show "$uuid" 2>/dev/null)" != "disabled" ]; then
            nmcli connection modify "$uuid" ipv6.method disabled
            echo "✔ IPv6 desabilitado em $type ($uuid)"
            changed=1
        fi
    done < <(nmcli -t -f UUID,TYPE connection show)

    if [ "$changed" -eq 0 ]; then
        echo "✔ Nenhuma conexão Ethernet/Wi-Fi com IPv6 ativo."
    fi

    echo "ℹ️  Vale no próximo reconnect/boot. O gateway deve estar em modo 1 (IPv4-only)."
}

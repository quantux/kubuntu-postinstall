#!/bin/bash

# Etapa 33 - Restringe o Direct IP do RustDesk (porta 21118) à LAN,
# Tailscale e loopback.
#
# O Direct IP do RustDesk não tem E2EE e, por padrão, escuta em todas as
# interfaces (IPv4 e IPv6). Esta etapa instala uma regra nftables que permite
# 21118 apenas:
#   - na LAN 192.168.1.0/24 (inclui o caminho 192.168.1.3 via subnet router da Pi);
#   - na interface tailscale0 (IP 100.123.8.18);
#   - no loopback.
# O resto (internet, guest 192.168.0.0/24, outras interfaces) é dropado.
# O modo por ID (E2EE) não usa porta inbound e continua normal.

step_33_rustdesk_guard() {
    show_message "Restringindo Direct IP do RustDesk (21118) à LAN/Tailscale/loopback"

    if ! command -v nft >/dev/null 2>&1; then
        echo "⚠️  nft não encontrado; pulando."
        return 0
    fi

    install -d -m 755 /etc/nftables.d

    cat > /etc/nftables.d/rustdesk-guard.nft <<'EOF'
table inet rustdesk_guard {
  chain input {
    type filter hook input priority -10; policy accept;
    tcp dport 21118 iifname "tailscale0" accept
    tcp dport 21118 iifname "lo" accept
    tcp dport 21118 ip saddr 192.168.1.0/24 accept
    tcp dport 21118 ip saddr 100.64.0.0/10 accept
    tcp dport 21118 drop
  }
}
EOF

    cat > /etc/systemd/system/rustdesk-guard.service <<'EOF'
[Unit]
Description=Restrict RustDesk Direct IP to LAN/Tailscale/loopback
After=network.target tailscaled.service

[Service]
Type=oneshot
ExecStartPre=-/usr/sbin/nft delete table inet rustdesk_guard
ExecStart=/usr/sbin/nft -f /etc/nftables.d/rustdesk-guard.nft
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable rustdesk-guard.service
    # restart (não só enable --now) para recarregar a regra em um serviço
    # oneshot que já estava ativo.
    systemctl restart rustdesk-guard.service
    nft list table inet rustdesk_guard

    echo "ℹ️  21118 agora só na LAN 192.168.1.0/24, tailscale0 e lo; fora bloqueado."
}

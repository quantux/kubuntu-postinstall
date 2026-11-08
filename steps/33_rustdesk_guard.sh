#!/bin/bash

# Etapa 33 - Restringe o Direct IP do RustDesk (porta 21118) ao Tailscale/lo.
#
# O Direct IP do RustDesk não tem E2EE e, por padrão, escuta em todas as
# interfaces (IPv4 e IPv6). Esta etapa instala uma regra nftables que dropa
# 21118 fora de tailscale0/lo. O modo por ID (E2EE) não usa porta inbound e
# continua normal.
#
# Observação: o acesso por 192.168.1.3 via subnet router da Pi também fica
# bloqueado; use o IP Tailscale do PC (100.123.8.18:21118). Se precisar do
# caminho pela Pi, adicione uma exceção para 192.168.1.2.

step_33_rustdesk_guard() {
    show_message "Restringindo Direct IP do RustDesk (21118) ao Tailscale/loopback"

    if ! command -v nft >/dev/null 2>&1; then
        echo "⚠️  nft não encontrado; pulando."
        return 0
    fi

    install -d -m 755 /etc/nftables.d

    cat > /etc/nftables.d/rustdesk-guard.nft <<'EOF'
table inet rustdesk_guard {
  chain input {
    type filter hook input priority -10; policy accept;
    tcp dport 21118 iifname != "tailscale0" iifname != "lo" drop
  }
}
EOF

    cat > /etc/systemd/system/rustdesk-guard.service <<'EOF'
[Unit]
Description=Restrict RustDesk Direct IP to Tailscale/loopback
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
    systemctl enable --now rustdesk-guard.service
    nft list table inet rustdesk_guard

    echo "ℹ️  21118 agora só em tailscale0/lo; o acesso por 192.168.1.3 via Pi fica bloqueado."
}

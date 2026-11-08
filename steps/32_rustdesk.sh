#!/bin/bash

# Etapa 32 - Instala o RustDesk via .deb oficial.
#
# Não existe repositório APT oficial do cliente RustDesk (2026-11). A
# distribuição oficial é .deb/.rpm/Flatpak/AppImage/AUR. Este passo instala o
# .deb de uma release pinada e habilita o serviço systemd.
#
# A config do usuário (~/.config/rustdesk) é restaurada pelo restic na etapa
# 01; se ela existir, o ID/senha/Direct IP voltam junto. Se não existir, o
# RustDesk criará um ID novo. Atualizações: use rustdesk-update.sh (não há
# repositório APT oficial).

RUSTDESK_VERSION="${RUSTDESK_VERSION:-1.5.1}"
# SHA-256 do rustdesk-1.5.1-x86_64.deb (release oficial).
RUSTDESK_SHA256="${RUSTDESK_SHA256:-b5d682ad90cb7571ecbdbf26eef58d3c4514e726a74ef6d08ce3f0b114ef0bd9}"

step_32_rustdesk() {
    show_message "Instalando RustDesk ${RUSTDESK_VERSION}"

    local arch deb_name url tmpdir current
    case "$(dpkg --print-architecture)" in
        amd64) arch="x86_64" ;;
        arm64) arch="aarch64" ;;
        *)
            echo "⚠️  Arquitetura $(dpkg --print-architecture) não suportada por este passo; pulando."
            return 0
            ;;
    esac

    deb_name="rustdesk-${RUSTDESK_VERSION}-${arch}.deb"
    url="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${deb_name}"

    current=$(dpkg-query -W -f='${Version}' rustdesk 2>/dev/null || true)
    if [ "$current" = "$RUSTDESK_VERSION" ] && command -v rustdesk >/dev/null 2>&1; then
        echo "✔ RustDesk $RUSTDESK_VERSION já está instalado."
        systemctl enable --now rustdesk.service >/dev/null 2>&1 || true
        return 0
    fi

    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    echo "Baixando $deb_name ..."
    curl -fL --retry 3 --connect-timeout 20 -o "$tmpdir/$deb_name" "$url"

    if [ -n "$RUSTDESK_SHA256" ] && [ "$arch" = "x86_64" ]; then
        echo "$RUSTDESK_SHA256  $tmpdir/$deb_name" | sha256sum -c -
    elif [ -n "$RUSTDESK_SHA256" ]; then
        echo "⚠️  Checksum configurado é do amd64; pulando verificação no $arch."
    else
        echo "⚠️  RUSTDESK_SHA256 vazio; pulando verificação de checksum."
    fi

    apt-get install -y "$tmpdir/$deb_name"

    # O .deb já habilita/inicia o rustdesk.service; garantimos de novo.
    systemctl enable --now rustdesk.service

    # A config restaurada pelo restic pode vir com dono root; garante o usuário.
    if [ -d "$USER_HOME/.config/rustdesk" ]; then
        chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config/rustdesk"
        echo "✔ Config restaurada em $USER_HOME/.config/rustdesk (dono: $USER_NAME)."
    else
        echo "ℹ️  Sem config antiga; o RustDesk criará um ID novo no primeiro uso."
        echo "   Ative o Direct IP Access (porta 21118) em Configurações → Segurança."
    fi

    echo "ℹ️  ID atual: $(user_do "rustdesk --get-id" 2>/dev/null || echo 'indisponível')"
    echo "ℹ️  Se o ID mudou, use a conexão por IP da Tailscale como fallback."
}

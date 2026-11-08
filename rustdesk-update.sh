#!/bin/bash
set -euo pipefail

# Atualiza o RustDesk para a última release estável do GitHub.
#
# Não existe repositório APT oficial do cliente RustDesk (2026-11); o .deb do
# GitHub não é atualizado pelo apt upgrade. Este script baixa a última release,
# verifica o digest quando a API fornece e reinstala o .deb. A config em
# ~/.config/rustdesk é preservada.
#
# Uso: sudo ./rustdesk-update.sh
# Para automatizar, crie um systemd timer chamando este script (o README
# explica). O script não instala timer por padrão.

if [ "$(id -u)" -ne 0 ]; then
    echo "Execute com sudo: sudo $0" >&2
    exit 1
fi

case "$(dpkg --print-architecture)" in
    amd64) arch="x86_64" ;;
    arm64) arch="aarch64" ;;
    *)
        echo "Arquitetura não suportada: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac

api="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
json=$(curl -fsSL --retry 3 --connect-timeout 20 "$api")

eval "$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
arch = sys.argv[1]
asset = ""
digest = ""
for a in d.get("assets", []):
    if a.get("name", "").endswith("-" + arch + ".deb"):
        asset = a.get("browser_download_url", "")
        digest = a.get("digest", "") or ""
        break
print("TAG=%r" % d.get("tag_name", ""))
print("URL=%r" % asset)
print("DIGEST=%r" % digest)
' "$arch")"

if [ -z "$TAG" ] || [ -z "$URL" ]; then
    echo "❌ Não encontrei o .deb $arch na última release." >&2
    exit 1
fi

current=$(dpkg-query -W -f='${Version}' rustdesk 2>/dev/null || true)
if [ -n "$current" ] && dpkg --compare-versions "$current" ge "$TAG"; then
    echo "✔ RustDesk já está atualizado: $current (última: $TAG)."
    exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
deb="$tmpdir/$(basename "$URL")"

echo "Baixando RustDesk $TAG ($arch) ..."
curl -fL --retry 3 --connect-timeout 20 -o "$deb" "$URL"

if [ -n "$DIGEST" ]; then
    hash="${DIGEST#sha256:}"
    if [ "$hash" != "$DIGEST" ]; then
        echo "$hash  $deb" | sha256sum -c -
    fi
else
    echo "⚠️  A API não forneceu digest; seguindo sem checksum."
fi

apt-get install -y "$deb"
systemctl restart rustdesk.service 2>/dev/null || systemctl enable --now rustdesk.service

echo "✔ RustDesk atualizado para $TAG."
echo "  Config/ID preservados em ~/.config/rustdesk (se existia)."

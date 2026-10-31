#!/bin/bash

# Etapa 20 - Restaura configuração personalizada do SSH
#
# O arquivo vem do backup restic: ~/.ssh/sshd_custom.conf é restaurado junto
# com a home na etapa 01. Por isso esta etapa precisa rodar depois da
# restauração (a ordem em recover.sh já garante isso).
#
# A cópia é feita para /etc/ssh/sshd_config.d/sshd_custom.conf, diretório que
# o /etc/ssh/sshd_config principal já importa. Como o Include fica antes das
# demais diretivas, os valores do drop-in têm precedência.
#
# A etapa valida a configuração com `sshd -t` antes de reiniciar. Se a
# validação falhar, o drop-in anterior é restaurado e a etapa é marcada como
# falha, evitando deixar o servidor SSH quebrado.

SSHD_CUSTOM_SRC="$USER_HOME/.ssh/sshd_custom.conf"
SSHD_CUSTOM_DST="/etc/ssh/sshd_config.d/sshd_custom.conf"
SSHD_MAIN_CONF="/etc/ssh/sshd_config"
SSHD_INCLUDE_LINE="Include /etc/ssh/sshd_config.d/*.conf"

step_20_ssh() {
    show_message "Restaurando configuração personalizada do SSH"

    if [ ! -f "$SSHD_CUSTOM_SRC" ]; then
        echo "⚠️  $SSHD_CUSTOM_SRC não encontrado (backup restic restaurado?); pulando configuração personalizada."
        return 0
    fi

    if ! command -v sshd >/dev/null 2>&1; then
        echo "⚠️  sshd não encontrado (openssh-server não instalado?); pulando."
        return 0
    fi

    mkdir -p /etc/ssh/sshd_config.d

    # Garante o Include no arquivo principal. O OpenSSH usa a primeira
    # ocorrência da diretiva, então ele deve ficar no topo para que o drop-in
    # prevaleça sobre o restante do arquivo.
    if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)' "$SSHD_MAIN_CONF"; then
        cp -a "$SSHD_MAIN_CONF" "$SSHD_MAIN_CONF.bak.$(date +%Y%m%d-%H%M%S)"
        sed -i "1i $SSHD_INCLUDE_LINE" "$SSHD_MAIN_CONF"
        echo "✔ Include adicionado em $SSHD_MAIN_CONF"
    fi

    # Guarda o drop-in anterior apenas se ele for diferente do novo.
    if [ -f "$SSHD_CUSTOM_DST" ] && ! cmp -s "$SSHD_CUSTOM_SRC" "$SSHD_CUSTOM_DST"; then
        cp -a "$SSHD_CUSTOM_DST" "$SSHD_CUSTOM_DST.bak.$(date +%Y%m%d-%H%M%S)"
        echo "✔ Backup do drop-in anterior criado"
    fi

    install -o root -g root -m 644 "$SSHD_CUSTOM_SRC" "$SSHD_CUSTOM_DST"

    # Valida antes de reiniciar; se quebrar, restaura e falha a etapa.
    if ! sshd -t; then
        echo "❌ Configuração inválida; revertendo $SSHD_CUSTOM_DST." >&2
        local last_backup=""
        last_backup=$(ls -1t "$SSHD_CUSTOM_DST".bak.* 2>/dev/null | head -n1 || true)
        if [ -n "$last_backup" ]; then
            install -o root -g root -m 644 "$last_backup" "$SSHD_CUSTOM_DST"
        else
            rm -f "$SSHD_CUSTOM_DST"
        fi
        return 1
    fi

    # Garante que o serviço suba no boot. No Ubuntu atual o sshd é ativado
    # por socket (ssh.socket); em versões antigas, pelo ssh.service.
    if systemctl cat ssh.socket >/dev/null 2>&1; then
        systemctl enable ssh.socket >/dev/null 2>&1 || true
    elif systemctl cat ssh.service >/dev/null 2>&1; then
        systemctl enable ssh.service >/dev/null 2>&1 || true
    fi

    if systemctl cat ssh.service >/dev/null 2>&1; then
        systemctl restart ssh.service
        if ! systemctl is-active --quiet ssh.service; then
            echo "❌ ssh.service não subiu após aplicar a configuração." >&2
            return 1
        fi
    else
        echo "⚠️  ssh.service não encontrado; configuração aplicada, mas o serviço não foi reiniciado."
    fi

    echo "✔ Configuração aplicada a partir de $SSHD_CUSTOM_SRC"
}

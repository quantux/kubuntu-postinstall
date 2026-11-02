#!/bin/bash

# Etapa 03 - Instala os pacotes apt listados em pacotes_apt.txt.
#
# Pacotes que não têm candidato de instalação na versão atual do Kubuntu são
# ignorados com aviso, em vez de derrubar a etapa inteira (nomes de pacotes
# mudam entre versões da distro).

step_03_apt_packages() {
    show_message "Instalando pacotes apt (pacotes_apt.txt)"
    # Aceita rodar o iperf3 como daemon sem confirmar durante a instalação
    echo "iperf3 iperf3/start_daemon boolean true" | debconf-set-selections

    local pkg cand
    local to_install=()
    local missing=()

    while read -r pkg; do
        [ -z "$pkg" ] && continue
        cand=$(LC_ALL=C apt-cache policy "$pkg" 2>/dev/null | awk -F': ' '/Candidate:/{print $2; exit}')
        if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then
            missing+=("$pkg")
        else
            to_install+=("$pkg")
        fi
    done < pacotes_apt.txt

    if [ ${#missing[@]} -gt 0 ]; then
        echo "⚠️  Pacotes sem candidato de instalação (ignorados): ${missing[*]}"
    fi

    if [ ${#to_install[@]} -eq 0 ]; then
        echo "⚠️  Nenhum pacote válido para instalar."
        return 0
    fi

    apt-get install -y "${to_install[@]}"

    # wine/steam puxam libspa-0.2-modules:i386. Como pipewire-bin é
    # Multi-Arch: foreign, o apt pode manter o binário i386 e não instalar o
    # daemon nativo — o PipeWire então morre com SIGSYS no login (sem áudio e
    # com o plasmashell reclamando de PipeWire). Garante o daemon amd64 e o
    # WirePlumber, mantendo as bibliotecas i386 para os apps de 32 bits.
    apt-get install -y pipewire-bin:amd64 pipewire:amd64 wireplumber
}

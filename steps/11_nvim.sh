#!/bin/bash

# Etapa 11 - Instala o Neovim em /opt/nvim
#
# O tarball oficial vem com o diretório de topo nvim-linux-x86_64; usamos
# --strip-components=1 para extrair direto em /opt/nvim e criamos um symlink
# em /usr/local/bin para o usuário não depender de PATH extra.

step_11_nvim() {
    show_message "Instalando nvim"
    curl -L -o /tmp/nvim-linux-x86_64.tar.gz https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    rm -rf /opt/nvim /opt/nvim-linux-x86_64
    mkdir -p /opt/nvim
    tar -C /opt/nvim --strip-components=1 -xzf /tmp/nvim-linux-x86_64.tar.gz
    chmod -R a+rX /opt/nvim
    ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
}

#!/bin/bash

# Etapa 23 - Remove pastas padrão do usuário que estejam vazias.
#
# Cobre tanto os nomes em português (herdados do antigo Linux Mint) quanto os
# nomes padrão em inglês criados pelo Kubuntu. Só remove diretórios vazios.

step_23_cleanup() {
    show_message "Removendo pastas padrão do usuário que estejam vazias"
    local dirs=(
        "Área de trabalho" "Desktop"
        "Documentos"       "Documents"
        "Modelos"          "Templates"  "Template"
        "Músicas"          "Música"     "Music"
        "Público"          "Public"
        "Vídeos"           "Videos"
        "Imagens"          "Pictures"
    )

    local dir path
    for dir in "${dirs[@]}"; do
        path="$USER_HOME/$dir"
        if [ -d "$path" ] && [ -z "$(ls -A "$path" 2>/dev/null)" ]; then
            if rmdir "$path" 2>/dev/null; then
                echo "✔ Removida (estava vazia): $dir"
            fi
        fi
    done
}

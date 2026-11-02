#!/bin/bash

# Helpers e infraestrutura compartilhada pelos scripts.
# Define variáveis globais, funções utilitárias e o mecanismo de
# idempotência baseado em marcadores em ~/.postinstall.

POSTINSTALL_DIR="$USER_HOME/.postinstall"
POSTINSTALL_STEPS="$POSTINSTALL_DIR/steps"
POSTINSTALL_LOG="$POSTINSTALL_DIR/recover.log"
# Logs detalhados: um diretório por execução + link "latest".
#   ~/.postinstall/logs/YYYYmmdd-HHMMSS/
#       environment.log   — contexto do sistema no início da execução
#       <etapa>.log       — saída completa (stdout+stderr) de cada etapa
POSTINSTALL_LOGS="$POSTINSTALL_DIR/logs"
POSTINSTALL_RUN_LOG=""

show_message() {
    printf '%0.s-' {1..45}; echo
    printf "%s\n\n" "$1"
}

# Verifica se o caminho do repositório restic existe. Não exige que seja um
# ponto de montagem: o repositório pode estar apenas como pasta local.
# Uso: restic_repo_available <caminho>
restic_repo_available() {
    [ -d "$1" ]
}

# Verifica se o restic consegue obter a senha do repositório: ou por variável
# de ambiente/arquivo/comando, ou porque existe um terminal utilizável.
# Sem isso, o restic falha com "unable to read password: inappropriate ioctl".
restic_password_available() {
    [ -n "${RESTIC_PASSWORD:-}" ] && return 0
    [ -n "${RESTIC_PASSWORD_FILE:-}" ] && return 0
    [ -n "${RESTIC_PASSWORD_COMMAND:-}" ] && return 0
    [ -t 0 ] || return 1
    ( exec </dev/tty ) 2>/dev/null
}

# Executa um comando como o usuário real (não-root) em shell de login.
user_do() {
    sudo -u "$USER_NAME" bash -l -c "$1"
}

# Registra uma linha no log de execução.
log_line() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$POSTINSTALL_LOG"
}

# Inicializa a infraestrutura de idempotência e o diretório de logs desta
# execução (idempotente: chamadas repetidas reaproveitam o mesmo diretório).
init_postinstall() {
    mkdir -p "$POSTINSTALL_STEPS" "$POSTINSTALL_LOGS"
    touch "$POSTINSTALL_LOG"

    if [ -z "$POSTINSTALL_RUN_LOG" ]; then
        POSTINSTALL_RUN_LOG="$POSTINSTALL_LOGS/$(date '+%Y%m%d-%H%M%S')-$$"
        mkdir -p "$POSTINSTALL_RUN_LOG"
        # Link estável para o log da execução mais recente.
        ln -sfn "$POSTINSTALL_RUN_LOG" "$POSTINSTALL_LOGS/latest"
        log_line "==> execução iniciada; logs em $POSTINSTALL_RUN_LOG"
    fi
}

# Grava o contexto do sistema no início da execução. Ajuda a reproduzir
# problemas (versão da distro, kernel, disco, memória, etc.).
log_environment() {
    local out="$POSTINSTALL_RUN_LOG/environment.log"
    local distro="?"

    if [ -r /etc/os-release ]; then
        distro=$( . /etc/os-release; printf '%s' "${PRETTY_NAME:-?}" )
    fi

    {
        echo "===== Contexto da execução ====="
        echo "Data        : $(date '+%Y-%m-%d %H:%M:%S %z')"
        echo "Run         : $POSTINSTALL_RUN_LOG"
        echo "Comando     : $0 $*"
        echo "Usuário     : ${USER_NAME:-desconhecido} (uid ${USER_UID:-?})"
        echo "Host        : $(hostname 2>/dev/null || echo '?')"
        echo "Kernel      : $(uname -srm 2>/dev/null || echo '?')"
        echo "Distro      : $distro"
        echo "Codename    : ${UBUNTU_CODENAME:-?}"
        echo "Diretório   : $(pwd)"
        echo "Disco /     : $(df -h / 2>/dev/null | tail -n 1)"
        echo "Memória     : $(free -h 2>/dev/null | sed -n '2p')"
    } > "$out" 2>&1
}

# Executa um comando avulso (fora das etapas) registrando a saída completa.
# Uso: run_logged_cmd <nome-do-log> <comando> [args...]
run_logged_cmd() {
    local name="$1"
    shift
    local logfile="$POSTINSTALL_RUN_LOG/$name.log"

    {
        echo "=================================================================="
        echo "Comando: $*"
        echo "Início : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================================================="
    } >> "$logfile"

    "$@" 2>&1 | tee -a "$logfile"
    return "${PIPESTATUS[0]}"
}

# Marca uma etapa como concluída.
mark_step() {
    local name="$1"
    touch "$POSTINSTALL_STEPS/$name"
}

# Verifica se uma etapa já foi concluída.
step_done() {
    local name="$1"
    [ -f "$POSTINSTALL_STEPS/$name" ]
}

# Executa a função de uma etapa capturando toda a saída (stdout+stderr) em
# ~/.postinstall/logs/<run>/<nome>.log, com cabeçalho, horário, duração e
# status de saída. A saída continua aparecendo no terminal.
# Uso: run_step_logged <nome> <função>
run_step_logged() {
    local name="$1" func="$2"
    local logfile="$POSTINSTALL_RUN_LOG/$name.log"
    local start_epoch duration status

    start_epoch=$(date +%s)
    {
        echo "=================================================================="
        echo "Etapa  : $name"
        echo "Função : $func"
        echo "Início : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=================================================================="
    } >> "$logfile"

    log_line "==> iniciando etapa: $name (log: $logfile)"

    ( set -e; "$func" ) 2>&1 | tee -a "$logfile"
    status=${PIPESTATUS[0]}

    duration=$(( $(date +%s) - start_epoch ))
    {
        echo "------------------------------------------------------------------"
        echo "Fim    : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Status : $status"
        echo "Duração: ${duration}s"
        echo
    } >> "$logfile"

    if [ "$status" -eq 0 ]; then
        log_line "==> etapa concluída: $name (${duration}s)"
    else
        log_line "==> etapa FALHOU: $name (status $status, ${duration}s) — log: $logfile"
        echo "❌ A etapa '$name' falhou (status $status). Últimas linhas de $logfile:" >&2
        tail -n 20 "$logfile" >&2
    fi

    return "$status"
}

# Executa uma função apenas se a etapa ainda não foi concluída.
# A etapa roda num subshell com `set -e` (como no script original), então o
# primeiro erro aborta a etapa; a falha é capturada e reportada sem derrubar
# o orquestrador.
# Uso: run_step <nome> <função>
# Retorna 0 se executou (ou já estava concluída), 1 se falhou.
run_step() {
    local name="$1" func="$2"

    if step_done "$name"; then
        show_message "⏭️  Etapa '$name' já concluída anteriormente. Pulando."
        log_line "==> etapa já concluída, pulando: $name"
        return 0
    fi

    show_message "▶ Executando etapa: $name"

    if run_step_logged "$name" "$func"; then
        mark_step "$name"
        return 0
    else
        return 1
    fi
}

# Como run_step, mas SEMPRE executa, ignorando o marcador. Usado em etapas
# interativas que precisam perguntar em toda execução (ex.: etapa 01/restore).
run_step_force() {
    local name="$1" func="$2"

    show_message "▶ Executando etapa: $name"

    if run_step_logged "$name" "$func"; then
        mark_step "$name"
        return 0
    else
        return 1
    fi
}

# Remove um marcador, permitindo reexecutar uma etapa.
unmark_step() {
    local name="$1"
    rm -f "$POSTINSTALL_STEPS/$name"
}

# Verifica se existe algum marcador de etapa concluída (recover anterior).
has_steps() {
    local step
    for step in "$POSTINSTALL_STEPS"/*; do
        [ -e "$step" ] && return 0
    done
    return 1
}

# Remove todos os marcadores, forçando a reexecução de tudo.
reset_steps() {
    rm -rf "$POSTINSTALL_STEPS"
    echo "Marcadores de etapas removidos de $POSTINSTALL_STEPS"
}

# Lista as etapas concluídas.
status_steps() {
    local step
    echo "Etapas registradas em $POSTINSTALL_STEPS:"
    for step in "$POSTINSTALL_STEPS"/*; do
        [ -e "$step" ] || continue
        echo "  ✔ $(basename "$step")"
    done

    if [ -L "$POSTINSTALL_LOGS/latest" ] || [ -d "$POSTINSTALL_LOGS/latest" ]; then
        echo
        echo "Log da última execução: $POSTINSTALL_LOGS/latest"
    fi
}

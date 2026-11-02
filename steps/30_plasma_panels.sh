#!/bin/bash

# Etapa 30 - Ajusta os painéis do Plasma à quantidade de telas conectadas.
#
# O backup da home pode ter sido feito com dois monitores. Ao restaurar numa
# máquina/VM com uma tela só, o Plasma pode ficar com painéis sobrepostos:
# um painel da tela que não existe (screen=-1), um painel centralizado antigo
# e o painel full-width criado pelo próprio Plasma. O painel sobreposto fica
# transparente (opacity=adaptive) mas continua capturando cliques.
#
# Regras (conservadoras):
#   1. Sem sessão Plasma: não faz nada.
#   2. Painel em tela inexistente (screen < 0 ou >= screenCount) ou com
#      comprimento 0: removido.
#   3. Vários painéis na MESMA tela e MESMO location (ex.: dois painéis
#      inferiores sobrepostos): mantém o de maior length e remove os demais.
#   4. Painéis em locations diferentes na mesma tela (topo + rodapé) são
#      mantidos: é um layout válido.
#   5. Nunca remove o último painel restante.
#   6. Se houver menos painéis que telas, apenas avisa; não cria painel.
#   7. Desktops/folder views não são removidos: podem conter ícones e posições
#      do usuário.

step_30_plasma_panels() {
    show_message "Ajustando painéis do Plasma às telas conectadas"

    local env_session="HOME=$USER_HOME XDG_RUNTIME_DIR=/run/user/${USER_UID} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${USER_UID}/bus"
    local js out

    js=$(mktemp) || { echo "⚠️  Não foi possível criar arquivo temporário; pulando."; return 0; }

    cat > "$js" <<'EOF'
var n = (typeof screenCount === "number") ? screenCount : -1;
var removed = [];
var notes = [];

function desc(p) {
    return "id=" + p.id + " (screen=" + p.screen + ", location=" + p.location + ", length=" + p.length + ")";
}

if (n <= 0) {
    print("screenCount=" + n + "; sem tela/Plasma; nada a fazer");
} else {
    var ps = panels();

    if (ps.length === 0) {
        print("screenCount=" + n + "; nenhum painel; nada a remover");
    } else {
        // 1) Painéis órfãos, de telas inexistentes ou com comprimento 0.
        var invalid = [];
        for (var i = 0; i < ps.length; i++) {
            var p = ps[i];
            var badScreen = (typeof p.screen === "number") && (p.screen < 0 || p.screen >= n);
            var badLength = (typeof p.length === "number") && p.length <= 0;
            if (badScreen || badLength) invalid.push(p);
        }

        // Nunca deixa o usuário sem painel: se todos forem inválidos, mantém o maior.
        if (invalid.length === ps.length && ps.length > 0) {
            invalid.sort(function(a, b) { return (Number(b.length) || 0) - (Number(a.length) || 0); });
            var keep = invalid.shift();
            notes.push("mantido " + desc(keep) + " por ser o único painel");
        }
        for (var j = 0; j < invalid.length; j++) {
            removed.push(desc(invalid[j]));
            invalid[j].remove();
        }

        // 2) Duplicados na mesma tela e mesmo location: mantém o de maior length.
        var ps2 = panels();
        var groups = {};
        for (var k = 0; k < ps2.length; k++) {
            var q = ps2[k];
            var key = q.screen + ":" + q.location;
            if (!groups[key]) groups[key] = [];
            groups[key].push(q);
        }
        for (var key2 in groups) {
            var arr = groups[key2];
            if (arr.length <= 1) continue;
            arr.sort(function(a, b) {
                var la = Number(a.length) || 0;
                var lb = Number(b.length) || 0;
                if (lb !== la) return lb - la;
                return (Number(a.id) || 0) - (Number(b.id) || 0);
            });
            for (var m = 1; m < arr.length; m++) {
                removed.push(desc(arr[m]));
                arr[m].remove();
            }
        }

        // 3) Situações que apenas avisamos.
        var ps3 = panels();
        if (ps3.length < n) notes.push("há " + n + " tela(s) e só " + ps3.length + " painel(es); nenhum painel foi criado");
        if (ps3.length > n) notes.push("ainda há mais painéis (" + ps3.length + ") que telas (" + n + "); locations diferentes foram mantidos");
        print("screenCount=" + n + "; removidos=[" + removed.join("; ") + "]; " + notes.join("; "));
    }
}
EOF

    if ! out=$(sudo -u "$USER_NAME" env $env_session \
            qdbus6 org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript "$(cat "$js")" 2>&1); then
        echo "⚠️  Sessão Plasma indisponível ou falha ao ajustar painéis; pulando."
        [ -n "$out" ] && echo "$out"
        rm -f "$js"
        return 0
    fi
    rm -f "$js"

    echo "$out"
    log_line "painéis do Plasma: $out"
}

# kubuntu-postinstall

Scripts de backup e restauração pós-instalação do **Kubuntu (KDE Plasma)**.

> Originalmente escrito para Linux Mint Cinnamon. Esta versão foi adaptada para
> o Kubuntu: mirrors do Mint, `dconf`/Cinnamon, `mintupdate`/spices, a
> atualização automática via systemd e o wallpaper via `gsettings` foram
> removidos ou substituídos pelos equivalentes do KDE/Ubuntu.
>
> A etapa 00 (opcional) remove **todo** o snap (apps, daemons e diretórios) e
> bloqueia a reinstalação do `snapd`. Os apps que eram snap (Firefox,
> Thunderbird, Krita, Element) são repostos via Flatpak na etapa 09; o ffmpeg
> continua vindo por apt.

## Estrutura

- `recover.sh` — orquestrador da restauração pós-instalação
- `backup.sh` — backup do sistema (restic + docker + wallpaper do Plasma)
- `remember_backup.sh` — lembrete mensal de backup
- `steps/` — etapas modulares da restauração (`XX_nome.sh`)
- `lib/common.sh` — helpers compartilhados e infraestrutura de idempotência
- `pacotes_apt.txt` — lista de pacotes apt (validada para o Kubuntu)
- `pacotes_flatpak.txt` — lista de pacotes flatpak
- `ignore-files` — regras de exclusão do restic

## Restaurar

1. Instalar:
   - `sudo apt-get install -y git`
   - O `restic` é instalado automaticamente pelo próprio script quando o
     repositório existe (apenas `apt update` + pacote `restic`, antes de
     qualquer outra coisa).
2. (Opcional) Montar/disponibilizar o repositório do restic em
   `/mnt/restic/restic_notebook_repo`. Se os dados já tiverem sido copiados
   manualmente para a home, não é necessário.
3. Executar `sudo ./recover.sh`.

A verificação do repositório acontece **no início do `recover.sh`**, antes de
qualquer etapa (e antes de perguntar sobre progresso anterior):

- Se o diretório do repositório **existir**, o script roda **somente**
  `apt-get update` e instala **somente** o pacote `restic`, pede a senha do
  repositório **uma única vez**, mostra os snapshots e pergunta se quer
  restaurar. Respondendo `y`, a restauração é feita imediatamente, **antes de
  instalar qualquer outro pacote**; se falhar, o recover é **abortado**.
- Se o diretório **não existir**, pergunta "Quer recuperar seus dados a partir
  do repositório restic?". Respondendo `y`, o script **aborta imediatamente**
  com instruções para montar/disponibilizar o repositório; respondendo `n`,
  segue sem restaurar.

Não é exigido que o repositório seja um ponto de montagem — basta a pasta
existir (útil para testes com uma cópia local).

A etapa 01 não pergunta mais nada: ela apenas executa a decisão tomada no início
do script (e revalida a existência do diretório antes de chamar o restic).

> **Senha do restic:** ela é pedida uma única vez no início e exportada em
> `RESTIC_PASSWORD` para o `snapshots` e para o `restore`. Se preferir, defina
> `RESTIC_PASSWORD`, `RESTIC_PASSWORD_FILE` ou `RESTIC_PASSWORD_COMMAND` antes
> de rodar o script. Sem terminal e sem senha configurada, ele avisa e pula a
> restauração em vez de falhar com `unable to read password`.

### Ajustando o caminho do repositório

O caminho padrão é `/mnt/restic/restic_notebook_repo` e pode ser sobrescrito
pela variável de ambiente `RESTIC_REPO`:

```bash
sudo RESTIC_REPO=/outro/caminho ./recover.sh
```

## Idempotência

Cada etapa em `steps/` só roda uma vez: ao concluir com sucesso, um marcador é
criado em `~/.postinstall/steps/`. Em execuções seguintes, as etapas concluídas
são puladas, então o script pode ser reexecutado com segurança.

Ao iniciar, se o script detectar progresso de um recover anterior, ele lista as
etapas já concluídas e pergunta se você quer **rodar tudo de novo** (apagando o
progresso) ou **continuar de onde parou**.

| Comando                  | Efeito                                        |
| ------------------------ | --------------------------------------------- |
| `sudo ./recover.sh`      | Pergunta se recomeça do zero ou continua      |
| `./recover.sh --status`  | Lista as etapas já concluídas                 |

O log de execução fica em `~/.postinstall/recover.log`.

## Backup

Executar `sudo ./backup.sh` ou usar o lembrete mensal `./remember_backup.sh`.

O snapshot inclui a home do usuário **e** arquivos de sistema que fazem parte
da configuração do KDE/ambiente:

- `$USER_HOME` — inclui `~/.config` e `~/.local/share`, onde vive a maior
  parte da configuração do Plasma/KDE;
- `/etc/xdg` — defaults globais do KDE e autostart de sistema;
- `/etc/sddm.conf` e `/etc/sddm.conf.d` — login/sessão/tema do SDDM;
- `/etc/default/keyboard` — layout de teclado;
- `/etc/environment`.

Arquivos que não existirem no sistema são ignorados silenciosamente.

### Exclusões via `.gitignore` (somente `~/workspace`)

Antes de chamar o restic, o script varre os projetos em `~/workspace` (filhos
diretos e raízes de repositórios aninhados) e adiciona ao backup um
`--exclude` para cada caminho ignorado pelo git (`git ls-files --others
--ignored --exclude-standard --directory`). Na prática, o que está no
`.gitignore` de um projeto em `~/workspace` não vai para o snapshot.

- Vale **apenas** para `~/workspace`. Repositórios em outras pastas do sistema
  são copiados por inteiro, mesmo que tenham arquivos no `.gitignore`.
- Cada projeto é avaliado isoladamente, com um work-tree sintético, para que
  regras de um repositório pai (por exemplo, o repositório da própria home)
  não vazem para dentro de `~/workspace`.
- A varredura ocorre a cada execução: não é preciso manter lista manual.

Como o backup roda dentro da sessão ativa, o script avisa caso o
`plasmashell` esteja rodando e pede confirmação: decisões ainda em memória
podem não ter sido gravadas em disco. Para um backup mais fiel, feche os
aplicativos e, de preferência, faça logout antes de rodar.

O backup usa as tags `mths` e `kubuntu`. A etapa 01 restaura o snapshot mais
recente filtrando apenas pela tag `mths`, então snapshots antigos do Mint
continuam sendo encontrados.

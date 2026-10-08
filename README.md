# lm-postinstall

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
- `assets/` — temas e ícones
- `ignore-files` — regras de exclusão do restic

## Restaurar

1. Instalar:
   - `sudo apt-get install -y git restic`
2. (Opcional) Montar o repositório do restic em `/media/restic/restic_notebook_repo`.
   Se os dados já tiverem sido copiados manualmente para a home, não é
   necessário montar.
3. Executar `sudo ./recover.sh`.

A etapa 01 **sempre pergunta** (não é pulada por marcador), para lembrar de
montar o repositório:

- Se o repositório **estiver montado**, mostra os snapshots e pergunta se quer
  restaurar via restic.
- Se **não estiver montado**, pergunta "Quer recuperar seus dados a partir do
  repositório restic?". Respondendo `y`, ele avisa para montar o repositório e
  executar de novo (a etapa fica pendente); respondendo `n`, segue sem restaurar.

### Ajustando o caminho do repositório

O caminho padrão é `/media/restic/restic_notebook_repo` e pode ser sobrescrito
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

O backup usa as tags `mths` e `kubuntu`. Para restaurar snapshots antigos,
a etapa 01 filtra apenas pela tag `mths`, então snapshots do Mint continuam
sendo encontrados.

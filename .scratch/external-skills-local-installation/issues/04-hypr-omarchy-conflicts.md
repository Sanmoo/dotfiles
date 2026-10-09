# 04 — Conflitos do pacote `hypr` com o Omarchy (e o comportamento de idle)

Status: ready-for-human

Achado enquanto se executava o item "(2)" da limpeza desta máquina. **Nada foi
mudado no pacote `hypr`**: o que está aqui precisa de decisão humana antes.

## O que está acontecendo

Os cinco arquivos do pacote `hypr` que estão em conflito **também pertencem ao
Omarchy**. Eles existem como stock em `~/.local/share/omarchy/config/hypr/` e há
**migrações que os reescrevem** — a linha `Music TUI/cliamp` presente na
`bindings.conf` desta máquina vem de `omarchy/migrations/1778307905.sh` e
`1777620904.sh`. O repo rastreia a *sua* versão dos mesmos caminhos, então **toda
atualização do Omarchy recria o conflito**.

Agravante: o `stow` aborta **por pacote**. Reconciliar 4 dos 5 arquivos e deixar
1 em conflito deixa os 4 **sem link** — pior que o estado atual. Na prática, o
pacote `hypr` é tudo-ou-nada.

## Direções já decididas nesta sessão (para não re-derivar)

| Arquivo | Hoje na máquina | No repo | Direção |
| --- | --- | --- | --- |
| `autostart.conf` | idêntico ao repo | idêntico | repo (no-op) |
| `monitors.conf` | versão de 2026-04-12 (`0x360`) | layout de 2026-09-26 (`0x160`) | repo — a cópia da máquina está **sombreada**: as linhas `monitor=` inline no `hyprland.conf` (que é link do repo) vêm depois e vencem; `hyprctl` confirma o layout do repo em vigor |
| `input.conf` | mantém `foot` na windowrule | sem `foot` | repo |
| `bindings.conf` | repo antigo + linha `Music TUI` do Omarchy | flags do Obsidian refinadas | merge: repo + a linha do Omarchy |
| `hypridle.conf` | 2 linhas, tudo desativado | listeners (lock + dpms + backlight) | **aberto — ver abaixo** |

O `nvim` do mesmo lote já foi resolvido: a `transparency.lua` da máquina virou a
do repo (commit `9c088a1`) e os 3 links `lua/plugins/{java,leap,php}.lua` nasceram.

## A pergunta do `hypridle` (em linguagem clara)

Hoje esta máquina **não faz nada quando fica ociosa**: não trava, não apaga a tela
e não suspende — aquele arquivo tem só dois comentários, sem nenhum listener.
Consequência prática: se você sair da mesa, a tela fica acesa e a sessão aberta
indefinidamente.

A versão do repo (e a que o README descreve) **trava a sessão e apaga a tela
depois de 1 hora**, sem nunca suspender, e ainda apaga/restaura o backlight do
teclado.

Qual das duas você quer que valha nesta máquina? E o README precisa descrever a
escolhida.

## A pergunta de desenho

Se o Omarchy vai continuar reescrevendo esses caminhos, o repo precisa escolher um
papel. Três opções, sem ordem de preferência:

1. **O repo carrega o stock atual do Omarchy como base** e por cima os seus
   ajustes. Re-stowar fica idempotente, e a reconcialiação acontece a cada
   atualização do Omarchy (com um `git diff` mostrando o que ele mudou).
2. **O repo guarda apenas overrides** que o Omarchy não escreve, e os arquivos
   disputados saem do pacote `hypr` (viram override pontual documentado).
3. **Aceitar reconciliação periódica**, sem mudar o desenho — sabendo que cada
   atualização do Omarchy recria o conflito.

A opção 2 é a única que evita o trabalho recorrente, ao custo de o repo deixar de
ser dono desses arquivos.

## Aceite (quando as duas decisões estiverem tomadas)

- [ ] Backup dos 5 arquivos antes de tocar em qualquer um.
- [ ] `hypridle.conf` conforme a decisão, e o README descrevendo esse comportamento.
- [ ] `stow hypr` (comando simples, sem `--ignore`) completa sem conflitos.
- [ ] `stow --simulate hypr nvim` silencioso (nenhum link faltando, nenhum conflito).
- [ ] `~/.config/hypr/{autostart,monitors,input,bindings}.conf` são links do repo.
- [ ] Papel escolhido para o pacote `hypr` documentado no README (§"For `Omarchy`").
- [ ] `tests/run --full` termina com `FULL GATE: PASS`.

## Evidência medida (2026-10-09)

- `stow --simulate --verbose` por pacote: `hypr` → 0 links faltando, 5 conflitos; `nvim` → 3 links faltando, 1 conflito (resolvido).
- `git ls-files hypr/` → 10 arquivos, incluindo `hyprland.conf` (que é link e traz as linhas `monitor=` inline no fim).
- `hyprctl -j monitors` (via `/run/user/1000/hypr/`): só `eDP-1 1920x1080@60.00 scale=1 pos=0x160` — posição que casa com o repo, não com a cópia local (`0x360`).
- `hypr/.config/hypr/monitors.conf`: cópia da máquina = versão commitada `5183ae15`, escrita em disco em 2026-08-30; repo mudou em `d589509` (2026-09-26, "wip").
- Nenhum dos 4 arquivos da máquina é igual ao stock do Omarchy (`cmp` contra `config/hypr/` e `default/hypr/`), ou seja: são misturas de stock do Omarchy com edições anteriores do repo.

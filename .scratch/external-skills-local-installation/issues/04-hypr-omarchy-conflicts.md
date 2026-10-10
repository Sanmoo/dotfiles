# 04 — Conflitos do pacote `hypr` com o Omarchy (e o comportamento de idle)

**Status:** wontfix
**Blocked by:** None — precisa da decisão do owner sobre o comportamento de idle e o papel do pacote `hypr`

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

## Comments

### wontfix (owner, 2026-10-10)

Decisão do owner: **não vale o retorno** frente ao trabalho recorrente exigido.
Nada foi alterado — nem no pacote `hypr`, nem no README, nem nos arquivos da
máquina.

Estado em que a máquina fica, aceito conscientemente:

- Os 5 arquivos disputados (`autostart`, `monitors`, `input`, `bindings`,
  `hypridle`) continuam arquivos regulares em `~/.config/hypr/`; os outros 5 do
  pacote continuam links do repo. `stow hypr` continua abortando.
- O `hypridle.conf` em vigor é a cópia da máquina, sem nenhum listener: a sessão
  não trava e a tela não apaga por ociosidade. O README §"For `Omarchy`"
  descreve o oposto ("It only locks the session and turns the display off after
  inactivity"), então essa descrição **não vale nesta máquina**. Registrado, não
  corrigido.
- A linha `Music TUI/cliamp` que as migrations do Omarchy escreveram em
  `bindings.conf` permanece só na cópia da máquina, fora do repo.

Mecânica do `stow` medida em 2026-10-10 (stow 2.4.1), para quem retomar:

- O conflito é por *arquivo regular no destino*, não por conteúdo: o
  `autostart.conf` idêntico ao repo conflita igual (`neither a link nor a
  directory and --adopt not specified`).
- É tudo-ou-nada por pacote: qualquer conflito → `All operations aborted.`
- **Correção ao "agravante" acima:** um re-stow abortado **preserva** os links já
  existentes. O cenário realmente perigoso é reconciliar *apagando* as cópias da
  máquina — aí as apagadas ficam sem link e sem arquivo. Por isso os 5 só podem
  sair numa passada única.
- `stow --adopt hypr` funciona como mecanismo de reconciliação: move a cópia da
  máquina para dentro do pacote e cria o link, e o `git diff` resultante mostra o
  que o Omarchy escreveu. Custo: clobbera a cópia do repo, então backup e revisão
  do diff são obrigatórios.

Direções que ficaram levantadas nesta sessão, caso o ticket seja reaberto: a
coluna "Direção" da tabela acima para os 4 arquivos (repo, com merge no
`bindings.conf`), e a recomendação de manter o repo como dono dos 10 arquivos com
reconciliação por `--adopt` + diff. A pergunta do `hypridle` (versão do repo vs
nada) não foi respondida — o wontfix a torna irrelevante por ora.

# 02 — Manifesto da máquina pessoal (Linux)

Status: implemented

Entrega na máquina pessoal do desenho que supera em parte `../spec.md` (ver o
`## Comments` de lá). A decisão está registrada em
`docs/adr/0003-agent-skill-manifests.md`. O trabalho da máquina corporativa é o
ticket `01-corporate-mac-manifest.md`, que segue `ready-for-human` de propósito.

## O que foi entregue

- `skills-personal/skills-lock.json` — as 28 skills desta máquina, com origens públicas.
- `skills-corporate/skills-lock.json` — seed vazio, preenchido no macOS.
- `general/bin/skills-sync` — `sync`, `update`, `add`, `remove`, `patches`, `sources`, `diff`, `list`.
- `skills-patches/harness-eval.txt` — lido do checkout; o CLI sobrevive à reescrita do `SKILL.md`.
- `tests/skills-sync-test.sh` (Fast tier, CLI stubado) e `tests/skills-sync-live.sh` (rede, fora do gateway).
- README §"Agent skills" e `agents/.agents/README.md` atualizados; linhas de Stow por plataforma com o pacote de perfil.

## Aceite

- [x] `~/skills-lock.json` é symlink para `skills-personal/skills-lock.json`.
- [x] As 28 skills declaradas estão instaladas em `~/.agents/skills`, e o manifesto é a fonte da verdade.
- [x] `skills-sync` no `PATH` via `~/bin`, publicado pelo pacote `general`.
- [x] O patch do `harness-eval` é reaplicado depois de uma instalação: verificado removendo a flag e rodando `skills-sync patches`.
- [x] `skills-corporate/skills-lock.json` existe como seed vazio e `skills-sync diff` reporta o gap (exit 1).
- [x] `tests/run --full` termina com `FULL GATE: PASS`; `bash tests/skills-sync-live.sh` passa de ponta a ponta.
- [x] Pacote `agents` aplicado sem conflitos; os arquivos rastreados do pacote agora são links do repo.

## Evidência

- `tests/run --full` → `ALL PASSED: 23 of 23 units`, `total wall clock: 10.25s`, **`FULL GATE: PASS`**.
- `bash tests/skills-sync-live.sh` → `PASS: skills-sync live (28 skills, 2 sources)` num HOME isolado e vazio: instala do zero, reaplica o patch, mantém o manifesto byte-idêntico e poda arquivos órfãos no segundo `sync`.
- Teste de mutação: reintroduzir o `</dev/null` removido faz o teste rápido falhar com `expected: 2, actual: 1`, provando que a regressão de stdin está coberta.
- Máquina: `~/skills-lock.json` → `skills-personal/skills-lock.json`; `~/bin/skills-sync` → `general/bin/skills-sync`; `skills-sync sources` lista 28 skills em 2 fontes.

## Commits

`3bae989` (manifesto e script, com testes e documentação), `6990d5b` (normalização do caminho no `diff`), `b75ee31` (patches lidos do checkout), mais os commits de task management do spec e deste ticket.

# 03 — Documentos do agente escondidos pelo padrão `docs`

**Status:** resolved

Achado enquanto se registrava o ADR 0003: o `git add` do ADR falhou e o commit
entrou **parcial**, só com o ticket `02`. Causa: o `.gitignore` tinha uma linha
seca `docs`, que casa com qualquer diretório chamado `docs` em qualquer nível.

Ela escondia dois arquivos que o próprio `AGENTS.md` manda ler:

- `docs/agents/triage-labels.md` — referenciado em `AGENTS.md:48`
- `docs/agents/domain.md` — referenciado em `AGENTS.md:52`

Os dois existiam apenas nas máquinas que por acaso os carregavam: num clone novo,
as duas instruções do `AGENTS.md` apontavam para o vazio. Era também o motivo de
um ADR novo exigir `git add -f`, apesar de `docs/adr/0001` e `docs/adr/0002`
estarem rastreados (entraram antes da regra, e regra de ignore não afeta o que já
é rastreado).

## O que mudou

- `.gitignore`: removida a linha `docs`. A regra `docs/superpowers` continua própria e válida.
- Passaram a ser rastreados: `docs/agents/domain.md` e `docs/agents/triage-labels.md`.

Antes de mexer, o alcance foi medido em vez de suposto: `git ls-files --others
--ignored --exclude-standard` lista 417 arquivos ignorados no repo, e **apenas
esses dois** contêm `docs`; `git check-ignore -v` confirma a linha 6 do
`.gitignore` para ambos. Os `pi/docs/superpowers/specs/*` já eram rastreados, então
a remoção não expôs nada além dos dois.

## Aceite

- [x] `docs/agents/domain.md` e `docs/agents/triage-labels.md` rastreados.
- [x] A regra `docs/superpowers` intacta (verificado com `git check-ignore`).
- [x] Nenhum outro caminho ficou exposto: o status antes do `git add` tinha exatamente 3 entradas (`.gitignore` + os dois arquivos).
- [x] Documentação nova não precisa mais de `git add -f`.
- [x] `tests/run --full` termina com `FULL GATE: PASS`.

## Evidência

Commit `135efb5`. `git ls-files docs/agents/` lista os três arquivos do diretório.
`FULL GATE: PASS` — `ALL PASSED: 23 of 23 units`, `total wall clock: 10.12s`.

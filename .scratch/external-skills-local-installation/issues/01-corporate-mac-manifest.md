# 01 — Manifesto da máquina corporativa (macOS)

Status: ready-for-human

Continuação de `../spec.md` na outra máquina. Nesta sessão apenas a máquina
pessoal (Linux) foi configurada; este arquivo é o handoff para a sessão que
trabalhará na máquina da empresa.

Operação e comandos: `README.md` §"Agent skills" (não duplicado aqui). Decisão e
o que foi superado: `../spec.md` §"Comments". Implementação: commits `3bae989`
e `6990d5b`.

## Por que o manifesto corporativo nasce vazio

`skills-corporate/skills-lock.json` é um seed com `{"version": 1, "skills": {}}`.
Um manifesto com origens públicas instalaria o upstream na máquina da empresa —
o oposto do objetivo; vazio, o pior caso é não instalar nada. As origens do fork
só podem ser gravadas na máquina que tem acesso a elas.

## Passos

1. **Aplicar a configuração.** A linha do macOS no README já inclui
   `skills-corporate`:

   ```sh
   stow aerospace general ghostty git nvim tasks tmux zsh pi pi-mac skills-corporate
   ```

   Confirme que `~/skills-lock.json` virou symlink para
   `<checkout>/skills-corporate/skills-lock.json`. Se existir um
   `~/skills-lock.json` comum de uma instalação anterior, o Stow se recusa a
   sobrescrevê-lo: compare os dois e remova o antigo antes de stowar.

2. **Gravar as origens do fork.** Substitua `<FORK>` por `owner/repo`:

   ```sh
   skills-sync add <FORK> -s ask-matt code-review codebase-design diagnosing-bugs \
     domain-modeling grill-me grill-with-docs grilling handoff implement \
     implement-spec improve-codebase-architecture pr prototype research retro \
     setup-matt-pocock-skills tdd teach to-questionnaire to-spec to-tickets \
     triage wait-what wayfinder wizard writing-for-agents
   ```

   São os mesmos 27 nomes do perfil pessoal, que vêm de `mattpocock/skills`. Não
   edite o JSON à mão: `computedHash` é calculado pelo CLI.

   `harness-eval` vem de `tech-leads-club/agent-skills` (público). Decida se faz
   sentido naquela máquina; havendo a decisão:
   `skills-sync add tech-leads-club/agent-skills -s harness-eval`.

3. **Verificar.**

   ```sh
   skills-sync sources   # as origens devem ser do fork, não de mattpocock/skills
   skills-sync           # instala o que o manifesto declara
   skills-sync diff      # diferenças esperadas contra o perfil pessoal
   ```

   Falha se qualquer entrada do manifesto ainda apontar para `mattpocock/skills`.

4. **Commitar** `skills-corporate/skills-lock.json` a partir daquela máquina.

## Fronteiras que continuam valendo

- Nunca `-g`: a instalação global vai para `~/.agents/.skill-lock.json`, que é
  machine-local e não entra no manifesto rastreado (`skills-sync add` recusa).
- O conteúdo das skills fica fora do checkout (`~/.agents/skills` é diretório
  real e externo).
- As linhas de `stow` e `apply-agent-config` não instalam, atualizam nem
  escolhem dependências.
- O patch de `harness-eval` é reaplicado por `skills-sync`: editar o `SKILL.md`
  instalado direto é desfeito na próxima instalação. Patches novos entram em
  `skills-patches/<skill>.txt`, uma linha de frontmatter por linha.

## Aceite

- [ ] `~/skills-lock.json` é symlink para `skills-corporate/skills-lock.json`.
- [ ] Nenhuma entrada do manifesto aponta para `mattpocock/skills`.
- [ ] `skills-sync` instala o conjunto declarado e `skills-sync sources` confirma as origens.
- [ ] `skills-sync diff` mostra apenas as diferenças pretendidas contra o perfil pessoal.
- [ ] `skills-corporate/skills-lock.json` commitado.
- [ ] `tests/run --full` termina com `FULL GATE: PASS` no checkout daquela máquina.

## Verificação local antes de encerrar (em qualquer máquina)

```sh
cd <checkout> && tests/run --full     # sem rede; precisa imprimir FULL GATE: PASS
bash tests/skills-sync-live.sh        # exercita o Skills CLI de verdade (rede, ~5 min)
```

## Skills sugeridas para a próxima sessão

- `handoff` — para produzir o handoff da sessão seguinte, se houver
- `grilling` e `domain-modeling` — se a decisão dos dois manifestos merecer um
  ADR (`docs/adr/`), hoje ausente

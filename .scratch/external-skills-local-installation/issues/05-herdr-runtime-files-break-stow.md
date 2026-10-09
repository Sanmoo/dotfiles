# 05 — Runtime do Herdr dentro do checkout quebra o `stow herdr` e o gate

Status: ready-for-human

Achado ao rodar `tests/run --full` no checkout principal desta máquina, ao
encerrar o ticket `01`. **Nada foi mudado no pacote `herdr`**: o que está aqui
precisa de decisão humana.

## O que está acontecendo

`~/.config/herdr` é um symlink dobrado pelo Stow para
`<checkout>/herdr/.config/herdr`. Como o diretório é dobrado, o Herdr escreve o
runtime *dentro do checkout*:

```text
herdr/.config/herdr/.plugins.lock
herdr/.config/herdr/focus-state.json
herdr/.config/herdr/herdr-client.log
herdr/.config/herdr/herdr-server.log
herdr/.config/herdr/herdr.sock.agent
herdr/.config/herdr/plugins.json
herdr/.config/herdr/release-notes.json
herdr/.config/herdr/session.json
herdr/.config/herdr/sessions/
herdr/.config/herdr/session-snapshots/
```

Todos estão no `.gitignore`, mas o Stow não lê `.gitignore`. Ao reaplicar o
pacote, ele encontra `herdr.sock.agent` — um symlink absoluto para
`/private/tmp/com.apple.launchd.*/Listeners` — e aborta:

```text
WARNING! stowing herdr would cause conflicts:
  * source is an absolute symlink ... herdr.sock.agent => /private/tmp/...
```

Consequências nesta máquina:

- `tests/herdr-stow-package-test.sh` falha no checkout principal (passa num
  checkout limpo, como um worktree sem os arquivos de runtime).
- `stow herdr` — o comando documentado no README §"For `Herdr`" — também falha.
- `tests/run --full` não fecha verde no checkout principal, embora feche no
  worktree.

## Por que não foi corrigido no ticket 01

A correção exige decidir como o pacote lida com runtime, e todas as opções têm
peso próprio:

- um `.stow-local-ignore` no pacote **substitui** a lista default do Stow, então
  precisaria repetir os defaults e seria um footgun para os outros pacotes;
- um comando guardado no estilo de `apply-agent-config`, calculando `--ignore` a
  partir de `git ls-files --others`, mantém o índice do Git como fonte de verdade
  mas cria mais uma operação documentada;
- desdobrar `~/.config/herdr` (`--no-folding` ou diretório real com links
  individuais) ataca a causa: o runtime deixa de cair no checkout.

Nada disso pertence ao ticket 01, e mexer no diretório dobrado ao vivo arrisca o
Herdr em execução.

## Aceite (proposta)

- [ ] `stow herdr` reaplica o pacote com os arquivos de runtime presentes.
- [ ] `tests/herdr-stow-package-test.sh` passa no checkout principal com o Herdr rodando.
- [ ] O runtime do Herdr deixa de ser escrito dentro do checkout, ou o pacote o ignora explicitamente.
- [ ] `tests/run --full` → `FULL GATE: PASS` no checkout principal.

# 05 — Runtime do Herdr dentro do checkout quebra o `stow herdr` e o gate

Status: resolved

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

- [x] `stow herdr` reaplica o pacote com os arquivos de runtime presentes.
- [x] `tests/herdr-stow-package-test.sh` passa no checkout principal com o Herdr rodando.
- [x] O runtime do Herdr deixa de ser escrito dentro do checkout, ou o pacote o ignora explicitamente.
- [ ] `tests/run --full` → `FULL GATE: PASS` no checkout principal. (Não satisfeito, e não por causa deste ticket: o gate está vermelho por 13 unidades alheias ao Herdr. Ver o comentário de fechamento.)

## Comments

### Fechado como resolvido por `8aa11fb` (2026-10-10)

O ticket ficou obsoleto: a correção foi commitada **9 minutos depois** de ele ser
aberto, e este arquivo nunca foi atualizado.

| Quando | O quê |
| --- | --- |
| 2026-10-09 05:25:42 | `4e194f0` — este ticket é registrado |
| 2026-10-09 05:34:58 | `8aa11fb` — `fix(herdr): ignore runtime files in stow package` |

O `8aa11fb` fez o que o ticket pedia, pela **primeira** das três opções acima:
criou `herdr/.stow-local-ignore` (30 linhas, repetindo os defaults do Stow com um
comentário explicando por que isso é necessário), atualizou o README §For `Herdr`
e reescreveu `tests/herdr-stow-package-test.sh` (+50/−10) para ficar hermético. O
`e609e49` já tinha tratado o `herdr-plugin.toml`.

Verificação (2026-10-10, dentro do sandbox `safe-pi`, com stow 2.4.1):

- O ignore cobre a lista inteira acima — os 10 caminhos, mais
  `^/.local/share/herdr-recent-navigator/herdr-plugin\.toml$`.
- `bash tests/herdr-stow-package-test.sh` → `herdr stow package: ok`, exit 0. O
  teste agora estagia só arquivos rastreados (`git ls-files` + `cp -P`) num
  diretório temporário e gera o runtime controlado, então reproduz a condição do
  checkout principal em qualquer lugar — é isso que torna o critério 2 verdadeiro.
- `git check-ignore` confirma que os 10 caminhos de `.config/herdr` estão no
  `.gitignore`. O Stow não lê isso, mas o checkout não acumula ruído do Git.
- Com o `stow` no PATH, o Full gate cai de 16 para **13** unidades falhando, e
  `herdr-stow-package-test.sh` e `herdr-stow-package-fixture-test.sh` saem da
  lista. Duas das 16 falhas originais eram só o sandbox sem `stow`.

O critério 4 fica sem marcar, e não é trabalho deste ticket: é o gate do repo
inteiro, vermelho por 13 unidades alheias ao Herdr (http-oc, aws-console,
ecs-logs, client-credentials, pi-deere, safe-pi, skills-sync, workq, `pi/tests`…),
e só verificável no host.

Registrado sem ação: a correção é uma **denylist**, não a causa. Desdobrar
`~/.config/herdr` (`--no-folding`) foi pesado e não foi a opção escolhida, então um
arquivo de runtime novo, vindo de uma versão futura do Herdr ou do plugin, quebra o
`stow herdr` de novo e exige mais um padrão neste arquivo.

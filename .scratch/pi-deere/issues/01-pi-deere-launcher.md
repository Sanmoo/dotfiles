# 01 — Disponibilizar pi-deere com segunda conta Copilot

Status: ready-for-human
Type: task
Spec: [pi-deere](../spec.md)

## Objetivo

Implementar o launcher pi-deere para consumir manualmente a franquia da
segunda assinatura Copilot, preservando o pi atual e permitindo retomar
as mesmas conversas com os recursos do ambiente existente.

O contrato completo, as Job Stories e as fronteiras estão no spec.
Esta publicação não inicia a implementação nem autentica contas reais.

## Escopo de implementação

- Entregar o comando pelo pacote Pi dos dotfiles, sem substituir pi ou safe-pi.
- Preparar um segundo perfil privado e persistente, de forma idempotente,
  sem copiar o arquivo de credenciais original.
- Reutilizar recursos e preferências do ambiente instalado; aplicar somente
  os defaults necessários a novas conversas Copilot no segundo perfil.
- Tornar as sessões existentes acessíveis em ambos os perfis, com retomada
  exata e seleção nativa, sem migração destrutiva.
- Fazer somente as adaptações de compatibilidade indispensáveis às extensões
  existentes para respeitar o perfil escolhido.
- Cobrir o contrato no limite público do launcher e na integração hermética
  com o Pi real; documentar instalação, login, troca e recuperação.

## Acceptance Criteria

- [x] pi-deere está disponível pelo fluxo de instalação dos dotfiles; pi e safe-pi mantêm seu comportamento anterior.
- [x] O segundo perfil mantém credenciais privadas próprias, sem compartilhar ou importar o armazenamento original nem copiar os demais logins.
- [x] Login, logout e renovação da segunda conta não alteram a autenticação da primeira; ausência de login nunca causa fallback silencioso para ela, inclusive por variáveis herdadas.
- [x] Uma nova conversa em pi-deere usa Copilot mesmo quando o default original é outro provider, sem sobrescrever as preferências originais.
- [x] Extensões, pacotes e dependências, skills, prompts, temas, instruções, keybindings e preferências relevantes carregam a partir da fonte comum, sem duas configurações ou instalações mantidas à mão.
- [x] Alterar um recurso comum é refletido na próxima execução dos dois perfis; defaults específicos de Copilot não mudam o pi original.
- [ ] O seletor nativo e a retomada por referência exata encontram as sessões existentes com seu histórico e branch, preservando a associação ao projeto.
- [x] Com duas sessões no mesmo projeto e uma em outro, a retomada abre a sessão escolhida, não apenas a mais recente; uma referência inexistente falha visivelmente.
- [x] Mensagens adicionadas no segundo perfil ficam disponíveis ao voltar à mesma sessão no primeiro.
- [ ] Modelo e thinking são preservados quando suportados; indisponibilidade no segundo perfil exige escolha explícita ou erro acionável, sem troca silenciosa de provider ou conta.
- [x] A preparação repetida é idempotente; conflitos não sobrescrevem arquivos ou links desconhecidos nem perdem credenciais e histórico.
- [x] Argumentos, prompts com espaços, diretório de trabalho, sinais e status de saída mantêm o contrato do Pi.
- [x] A documentação descreve o login da segunda conta, a troca manual, a retomada exata e a exigência de encerrar a instância anterior antes de reutilizar a mesma sessão.
- [x] A documentação distingue a execução paralela em sessões diferentes da escrita concorrente não suportada na mesma sessão.
- [x] Os testes automatizados usam dados fictícios e recursos locais, sem rede, logins reais ou consumo de franquia; a validação com Pi real comprova descoberta de recursos e de sessões além do stub.
- [ ] Um smoke test supervisionado confirma as duas contas reais, uma requisição por perfil e a retomada entre perfis; a evidência não contém segredos. Se faltar autenticação humana, registrar a pré-condição pendente e não marcar este item aprovado.
- [x] O Quality gateway termina com FULL GATE: PASS; o resultado do smoke test real é registrado separadamente.

## Testing Seam

Preferir o limite de processo do launcher: executar o comando real em
home temporária, controlar o colaborador Pi e observar comportamento
externo. Complementar a mesma suíte com carregamento hermético do Pi
real para recursos, modelos e sessões.

Prior art: testes do wrapper safe-pi, do launcher WorkQ e dos fluxos de
configuração com Stow. Não copiar a implementação do OAuth nem testar
detalhes privados de funções ou a forma exata dos links.

## Observações para execução

- O nome definitivo é pi-deere, não o nome provisório sugerido na conversa.
- O perfil secundário começa apenas com Copilot. Isso não é autorização
  para bloquear futuras configurações explícitas de outros providers.
- O provider padrão atual pode não ser Copilot; a fixture precisa cobrir esse caso.
- A extensão local de isolamento de preferências assume o diretório padrão
  em parte do código; verificar a compatibilidade sem absorver bugs não relacionados.
- A preparação deve preservar caminhos relativos e dependências de pacotes.
  A existência de um link ou de uma declaração não comprova carregamento.
- Autenticação no GitHub é uma ação humana; não ler, imprimir ou versionar
  tokens para produzir evidência.
- Não alterar a Sandbox, WorkQ ou a restauração do Herdr nesta entrega.
- Task management permanece em main; somente ao iniciar a implementação
  criar branch e worktree, mantendo o spec fora desse worktree.

## Comments

Especificação publicada a partir da conversa confirmada com o usuário.
Escolha: duas instâncias, troca manual, retomada da conversa e ambiente
compartilhado; segundo perfil inicialmente apenas Copilot. Nenhuma
implementação ou autenticação foi realizada nesta publicação.

### Validação da publicação

- Template da spec, 30 Job Stories numeradas, metadados ready-for-agent e
  referências locais: aprovados.
- Diagnósticos Markdown via LSP: dois arquivos verificados, sem diagnósticos.
- `tests/run --full` no checkout principal: 22 de 23 unidades aprovadas;
  verdict final `FULL GATE: FAIL`.
- Bloqueio preexistente em `tests/herdr-stow-package-test.sh`: o teste copia
  todo o pacote Herdr com runtime local e tenta criar um link que já existe.
  A execução reportou sockets não copiados e `herdr.sock.agent: File exists`.
  Os documentos novos não alteram esse pacote; nenhum runtime foi removido.
- Na primeira tentativa, o commit da publicação foi adiado até o Full gate
  verde. A alteração previamente staged em `pi-mac/.pi/agent/settings.json`
  foi preservada.

Essa checagem valida apenas a publicação da spec, não a implementação ou o
smoke test de duas contas, que continuam sendo trabalho futuro.

### Bloqueio resolvido

Correção autorizada pelo usuário e integrada em `main` no commit `fb3a396`
(`tests: isolate Herdr Stow fixtures from live runtime`). O teste agora monta
sua fixture com o conteúdo atual dos arquivos rastreados pelo Git, sem copiar
sockets ou links de runtime existentes. Continua gerando runtime controlado
para verificar o contrato do Stow.

A regressão executa o ponto de entrada real do teste em um checkout descartável
com um link absoluto preexistente e sockets Unix reais, e verifica que esses
artefatos de origem permanecem intactos. O link sozinho reproduziu o erro
`File exists` duas vezes antes da correção.

`tests/run --full` passou 24 de 24 unidades no worktree da correção e no checkout
principal com o runtime presente; ambos encerraram com `FULL GATE: PASS`.
O branch e o worktree dessa correção foram removidos após a integração.
Nenhum runtime local ou alteração preexistente do usuário foi removido.

A feature pi-deere continua não implementada e este ticket permanece
ready-for-agent; a correção desbloqueia somente a publicação da especificação.

### Implementação integrada

- Integrada em `main` por fast-forward de `feat/pi-deere-launcher`, commits `a179912`, `3acf7d2`, `9634784`, `6d1f23d` e `13a66b2`. Worktree e branch removidos após a integração.
- Validação: `tests/run --full` → `FULL GATE: PASS` (26 de 26 unidades). Suítes novas: `tests/pi-deere-test.sh` (contrato com `pi` stub, 83 asserções) e `tests/pi-deere-real-pi-test.sh` (Pi real, offline, credenciais fictícias, 46 asserções, `tier: slow`). `bun test pi/tests` passa.
- Revisão `/code-review` (Standards e Spec). Corrigido: `settings.json` era um link, e as escritas de modelo e thinking do Pi chegavam ao original; agora é cópia regenerada a cada execução. Subcomandos do Pi (`update`, `install`, `list`, `auth`) recebiam `--models` antes deles e não eram reconhecidos; agora são encaminhados sem escopo. `~` em `PI_CODING_AGENT_DIR`/`PI_DEERE_AGENT_DIR` é expandido. `trust.json` deixou de ser compartilhado. O runner reporta `pi` ausente como `RUNNER ERROR` no full gate. Testes novos: thinking restaurado da sessão, logout e renovação no segundo perfil sem tocar no original, login da primeira conta nunca visível ao segundo perfil.
- Decisão em aberto: quando o modelo de uma sessão não existe no segundo perfil, o Pi continua com um modelo Copilot e mostra um aviso só na UI interativa (RPC e print não mostram). O critério pede escolha explícita ou erro acionável; por isso o item de indisponibilidade permanece desmarcado.
- Não automatizado: o seletor `--resume` (TUI), a ramificação ativa da sessão e a renovação real de token. Esses itens não foram verificados.
- Pendente (pré-condição humana): smoke test supervisionado com as duas contas GitHub reais. Não executado; o item permanece desmarcado e não está aprovado.
- Mantido por necessidade: `bin/` (o Pi instala `rg`/`fd` ali), `models-store.json` (catálogo offline), `PI_DEERE_AGENT_DIR` (usado pelos testes) e `mkdir` de `sessions/` na origem (o Pi criaria o mesmo diretório).

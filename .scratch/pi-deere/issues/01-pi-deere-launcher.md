# 01 — Disponibilizar pi-deere com segunda conta Copilot

Status: claimed
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

- [ ] pi-deere está disponível pelo fluxo de instalação dos dotfiles; pi e safe-pi mantêm seu comportamento anterior.
- [ ] O segundo perfil mantém credenciais privadas próprias, sem compartilhar ou importar o armazenamento original nem copiar os demais logins.
- [ ] Login, logout e renovação da segunda conta não alteram a autenticação da primeira; ausência de login nunca causa fallback silencioso para ela, inclusive por variáveis herdadas.
- [ ] Uma nova conversa em pi-deere usa Copilot mesmo quando o default original é outro provider, sem sobrescrever as preferências originais.
- [ ] Extensões, pacotes e dependências, skills, prompts, temas, instruções, keybindings e preferências relevantes carregam a partir da fonte comum, sem duas configurações ou instalações mantidas à mão.
- [ ] Alterar um recurso comum é refletido na próxima execução dos dois perfis; defaults específicos de Copilot não mudam o pi original.
- [ ] O seletor nativo e a retomada por referência exata encontram as sessões existentes com seu histórico e branch, preservando a associação ao projeto.
- [ ] Com duas sessões no mesmo projeto e uma em outro, a retomada abre a sessão escolhida, não apenas a mais recente; uma referência inexistente falha visivelmente.
- [ ] Mensagens adicionadas no segundo perfil ficam disponíveis ao voltar à mesma sessão no primeiro.
- [ ] Modelo e thinking são preservados quando suportados; indisponibilidade no segundo perfil exige escolha explícita ou erro acionável, sem troca silenciosa de provider ou conta.
- [ ] A preparação repetida é idempotente; conflitos não sobrescrevem arquivos ou links desconhecidos nem perdem credenciais e histórico.
- [ ] Argumentos, prompts com espaços, diretório de trabalho, sinais e status de saída mantêm o contrato do Pi.
- [ ] A documentação descreve o login da segunda conta, a troca manual, a retomada exata e a exigência de encerrar a instância anterior antes de reutilizar a mesma sessão.
- [ ] A documentação distingue a execução paralela em sessões diferentes da escrita concorrente não suportada na mesma sessão.
- [ ] Os testes automatizados usam dados fictícios e recursos locais, sem rede, logins reais ou consumo de franquia; a validação com Pi real comprova descoberta de recursos e de sessões além do stub.
- [ ] Um smoke test supervisionado confirma as duas contas reais, uma requisição por perfil e a retomada entre perfis; a evidência não contém segredos. Se faltar autenticação humana, registrar a pré-condição pendente e não marcar este item aprovado.
- [ ] O Quality gateway termina com FULL GATE: PASS; o resultado do smoke test real é registrado separadamente.

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

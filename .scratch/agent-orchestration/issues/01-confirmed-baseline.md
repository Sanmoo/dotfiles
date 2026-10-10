# Preservar os acordos e limites já confirmados

Type: grilling
Status: resolved

## Question

Quais decisões o humano já confirmou antes de criar este mapa, e quais propostas ainda não constituem decisões?

## Answer

Registro retrospectivo dos acordos da conversa; não é uma nova rodada resolvida unilateralmente.

### Fluxo e escopo

- Uso pessoal e piloto empresarial de uma equipe, repositórios privados, sem acesso a produção.
- `ready-for-agent` torna o ticket candidato à execução, sujeito a dependências satisfeitas e reserva exclusiva. `ready-for-human` continua significando implementação humana, não agente esperando resposta.
- Workers produzem branch/PR e evidências, com aprovação humana antes de integrar. Autoridade exata de publicação ainda será decidida.
- N significa no máximo N tickets/ciclos em execução simultânea. Cada execução possui branch/worktree e sandbox próprias; mecanismos de isolamento Git ainda são uma questão aberta.
- Implementação, testes, review por agentes e correções são um único ciclo interno do harness. `/implement` é a skill do Matt Pocock usada hoje, não o protocolo universal do executor.
- Pi é preferido, mas o harness deve ser substituível. Skills e subagentes precisam estar disponíveis no perfil executor.
- Subagentes são geridos pelo harness, não viram automaticamente workers de tickets. Devem ter permissões iguais ou menores; escritores concorrentes trabalham em áreas isoladas, nunca no host.

### Segurança

- Conter também agente induzido por prompt injection; não apenas acidentes.
- Workers pessoais inicialmente locais; piloto empresarial em máquina dedicada, sem depender de acesso do desenvolvedor a ela.
- Perfil de worker restrito: reutilizar ferramentas/skills, não todas as permissões e identidade do safe-pi interativo.
- Sem encaminhamento do SSH agent pessoal, sem todo o estado pessoal Pi gravável; rever caches/toolchains compartilhados e fornecer só credenciais necessárias.
- Rede restrita ao necessário para modelos, repositório, tracker e dependências autorizadas, sem acesso geral à rede corporativa/produção. Aplicação da restrição fora do controle do agente.

### Intervenção humana e recuperação

- Falhou: preservar evidências e pedir intervenção; não recolocar automaticamente na fila.
- Bloqueado: aguarda decisão/informação/permissão. Não equivale a falha.
- Intervenção normal é comunicação pelo tracker/Git e futuramente Teams. Não pressupõe terminal ou acesso de desenvolvedores à máquina; acesso operacional de infraestrutura é separado.
- Tracker é o registro oficial. Contexto de code review pode vir de Git. Resposta por Teams deve ser registrada antes de provocar retomada.
- Pedido tem identidade, fase, impedimento, pergunta e opções. Resposta autorizada se vincula ao pedido; comentário genérico ou resposta duplicada/atrasada não deve destravar outra execução.
- Qualquer membro autorizado da equipe responsável pode responder; primeira resposta válida aceita encerra o pedido, com autoria e decisão registradas.
- Agente pausa após pedir ajuda. Nenhum filho deve seguir escrevendo quando o ciclo é declarado pausado; ajuda de subagente sobe ao principal, que consolida o pedido.
- Pausa libera vaga de execução, mas mantém a reserva. Ao responder, execução aguarda vaga para retomar.
- Pausa lógica encerra a rodada após salvar contexto/sessão, em vez de segurar indefinidamente um processo vivo.
- Preservar sessão, commits, alterações não commitadas e evidências; container pode ser removido e reconstruído se estado indispensável foi salvo. Retenção tem limite separado, ainda sem valores.
- Intervenção não amplia permissões silenciosamente. Exceções e mudanças de escopo exigem autorização explícita.
- Checkpoint/cancelamento/retomada devem abranger a árvore de agentes; não há prova técnica disso ainda.

### Permanecem abertos

- Proposta de /implement não publicar/integrar/encerrar ticket; resolver conflito com instruções globais do harness.
- Git exclusivo por execução versus metadados compartilhados por worktrees.
- Um único scheduler persistente inicialmente versus outras topologias.
- Pesos da avaliação, SLA, recursos, orçamento, licenciamento e tracker do produto.
- Compatibilidade real Pi/subagentes e reconstrução após queda. Nenhum fornecedor foi validado ponta a ponta.

## Comments

- Origem: decisões explícitas nas rodadas Q1–Q23, com correção de Q9 (sem terminal como caminho normal) e de Q19 (ciclo interno via skill); destino do mapa e independência de harness confirmados na invocação de wayfinder.

# Definir o contrato substituível entre orquestrador e harness

Type: grilling
Status: open
Blocked by: 01

## Question

Qual contrato mínimo permite iniciar, observar, pausar, salvar e retomar um ciclo de implementação com harnesses diferentes, incluindo delegação interna, sem transformar a skill /implement do Matt Pocock em API universal?

Decidir responsabilidades e representação de capacidades: identidade de execução/pedido/sessão, entrada e resultado, eventos de progresso/ajuda, cancelamento da árvore, checkpoint e artefatos, reconstrução do ambiente e negociação de capacidades. Um harness sem subagentes ou sem retomada deve ser rejeitado ou operar de modo degradado? Que diferenças pertencem ao adaptador?

Resolver autoridade: skills/instruções atuais podem mandar integrar/limpar automaticamente. O motor, harness e humano têm quais poderes de commit, publicação de PR, status e integração? Proposta de restringir publicação ainda não foi aceita.

Não desenhar interface TypeScript antes de acertar semântica. Pi é o primeiro candidato; implementação/adaptação fica fora do ticket.

## Comments

- Descobertas preliminares: Sandcastle inicia Pi em print/JSON e captura sessão principal; isto não prova recuperação dos filhos. safe-pi tem contrato próprio de HOME, mounts e entrypoint. Revalidar quando houver prova técnica.

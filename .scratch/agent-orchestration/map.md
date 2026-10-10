# Orquestração durável de desenvolvimento com harness substituível

Label: wayfinder:map

## Destination

Chegar a uma especificação arquitetural fundamentada para desenvolvimento agêntico pessoal e um piloto empresarial: comparar Temporal, Hatchet e Restate; escolher o motor ou explicitar experimentos de desempate; definir fronteiras, contratos, estados, intervenção humana e segurança suficientes para planejar a implementação.

## Notes

- Destino confirmado pelo humano nesta conversa. Planejamento, não implementação da plataforma.
- Tracker deste esforço: Markdown local, conforme `docs/agents/issue-tracker.md`. Mapas e tickets são gestão de tarefas e ficam no checkout principal, em `main`; nunca editar `.scratch/**` em worktrees.
- Retomada: ler este mapa; consultar os filhos em `issues/`; escolher o primeiro ticket aberto, não reservado e com todos os `Blocked by:` resolvidos. Antes de trabalhar, marcar `Status: claimed` e registrar responsável/contexto. Uma sessão resolve no máximo um ticket não-research.
- Skills: wayfinder; grilling e domain-modeling para decisões HITL; research para investigações; prototype apenas quando um artefato concreto esclarecer uma decisão.
- Pi é o primeiro harness desejado pela flexibilidade. Preservar substituição por futuros candidatos é requisito, não detalhe opcional.
- `/implement` é uma skill do Matt Pocock usada pelo humano; não é API universal, produto ou protocolo de orquestração. O adaptador de Pi pode acioná-la; contratos entre componentes não devem depender do nome.
- Temporal, Hatchet e Restate são candidatos, não escolhas. Interesse prévio em Restate não atribui peso automático. Sandcastle é componente opcional de execução a avaliar, não premissa.
- Evidência: documentações e código oficiais; registrar data/versão, limitações, edição/licença e o que só é marketing ou ainda não foi demonstrado. Não confundir durabilidade do motor com checkpoint do harness, nem container com fronteira suficiente de segurança.
- Pesquisa: relatórios em branches descartáveis `research/agent-orchestration-<candidate>`, worktrees isoladas sob `.worktrees/`, sem merge e sem PR. A invocação de wayfinder prevê push dessas branches; nunca publicar credenciais ou detalhes internos. Pesquisadores não editam tickets: o responsável pelo mapa registra links e resolve pesquisas após verificar resultados.
- Nesta etapa, pesquisas são leitura de fontes e redação de evidências; não instalar serviços, executar benchmarks ou implementar adaptadores. Mudança em código/configuração exige planejamento próprio e Full gate conforme AGENTS.
- As propostas Q24–Q26 da conversa anterior (autoridade de publicação, Git exclusivo e um único scheduler) NÃO foram aceitas; continuam perguntas nos tickets apropriados.
- As três pesquisas documentais terminaram no workflow `93313e50-aec4-41f6-8845-2e90e96d7866` e foram publicadas após nova tentativa autorizada. Não há filhos ativos nem pedidos pendentes de supervisor. Handoffs/relatórios foram lidos pelo responsável; os tickets resolvidos contêm URLs imutáveis por SHA, evidência e ressalvas. Relatórios NÃO foram integrados em `main`, conforme o fluxo de pesquisa do wayfinder. Não relançar pesquisadores.
- Branches remotas de pesquisa preservam os relatórios; branches/worktrees locais ainda estão presentes e limpas sob `.worktrees/agent-orchestration-{temporal,hatchet,restate}/`. Links canônicos independem das worktrees. O bloqueio SSH histórico foi encerrado sem alterar configuração nem diagnosticar o que mudou no ambiente.
- Na próxima sessão, confirmar a régua de avaliação e trabalhar uma decisão da fronteira. Não tratar evidência produzida como decisão humana. A escolha de motor permanece bloqueada pelos tickets de régua, harness e segurança, não pela publicação.

## Decisions so far

- [Preservar os acordos e limites já confirmados](issues/01-confirmed-baseline.md): execução por tickets elegíveis e reservados, aprovação humana, ajuda por canais oficiais, sandbox contra prompt injection e harness substituível; detalhes e ressalvas vivem no ticket.

- [Desbloquear a publicação das evidências com confiança SSH validada](issues/09-research-publication.md): nova tentativa autorizada publicou os três SHAs sem alteração de SSH; relatórios seguem fora de main.
- [Investigar Temporal para orquestrar harnesses externos](issues/03-temporal.md): evidência publicada sobre replay, Activities, espera, versionamento e operação; sem prova de recuperação do harness.
- [Investigar Hatchet para orquestrar harnesses externos](issues/04-hatchet.md): evidência publicada sobre durable tasks, eviction e concorrência; gaps de N e evolução explicitados.
- [Investigar Restate para orquestrar harnesses externos](issues/05-restate.md): evidência publicada sobre journal, estado e espera; limites de concorrência e licença destacados.

## Not yet specified

- Caminho operacional e custos do laptop ao piloto empresarial; topologia e requisitos de disponibilidade ainda dependem da régua e das evidências.
- Adaptadores concretos de tracker/Git/Teams e autorização de respostas; o tracker local deste mapa não define o tracker do produto.
- Retenção, limites de recursos e orçamento, prazos de ajuda e escalonamento sem resposta: faltam números e expectativas de serviço.
- Modelo detalhado de observabilidade e proteção de dados de sessões/prompts; depende do contrato e das fronteiras de segurança.
- Experimentos de compatibilidade e recuperação que sobreviverão à escolha preliminar; não escolher infraestrutura só por documentação.
- Licenciamento aceitável, suporte/compras e restrições da empresa além do piloto sem produção.
- Consolidação da especificação e plano de implementação depois das decisões e provas; ainda não há implementação autorizada.

## Out of scope

- Implementar ou colocar a plataforma em produção.
- Plataforma multi-equipe/multitenant e acesso de agentes a produção neste primeiro piloto.
- Teams como integração inicial: interface futura sobre o mesmo protocolo, não novo registro oficial.
- Tornar Sandcastle obrigatório ou substituir Pi antecipadamente.

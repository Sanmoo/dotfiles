# Investigar Temporal para orquestrar harnesses externos

Type: research
Status: claimed
Blocked by: 01

## Question

O que Temporal oferece e exige para coordenar ciclos externos de implementação em sandbox, localmente e num piloto empresarial, preservando substituição de harness?

Aplicar a pauta comum abaixo, com fontes primárias e versões/data. Entregar um relatório de evidência em branch de pesquisa; não decidir adoção nem implementar.

### Pauta comum das três pesquisas

- Runtime local persistente versus modo dev; self-hosting de produção, dependências, HA, upgrades, operação e cloud opcional.
- Estado/workflow, checkpoints, replay, versionamento de código/workflow, evolução de execuções vivas.
- Semântica de retries/entrega e efeitos externos: explicar risco de duplicar branch/PR/comentário/processo; não vender exactly-once como garantia universal.
- Workers e concorrência: limite N de tickets, fairness, recursos, quotas, isolamento de equipes; distinguir limite de tarefa de limite de subprocesso.
- Pausa por ajuda, sinal/evento externo correlacionado, respostas duplicadas/tardias, espera sem ocupar worker, timeout e autorização fora do motor.
- Integração com executor externo arbitrário (Pi agora; outros futuramente), jobs longos, heartbeat/cancelamento, processos-filhos, crash e reconciliação. Explicar o que a biblioteca NÃO persiste.
- Observabilidade: UI, histórico, logs, métricas, tracing/OTel, árvore de agentes, dados sensíveis e retenção; distinguir instrumentação automática de instrumentação própria.
- Sandbox: mecanismos integrados ou integrações necessárias; fronteiras de filesystem/Git, rede e credenciais; não presumir que worker container é sandbox segura.
- Edições, licença, recursos pagos/self-hosted e modelo de custo; sem preços inventados ou comparações de desempenho sem medições.
- Forças, limitações, perguntas abertas e experimentos discriminantes, usando os mesmos cenários dos demais.

### Cenários a analisar

Worker caiu após commit e antes de registrar sucesso; resposta humana chega dias depois e duas vezes; scheduler reinicia enquanto execução está bloqueada; subagente segue vivo quando pai termina; container destruído com dirty files; upgrade do workflow com pedidos pendentes.

## Comments

- Identidade Git local fornecida pelo humano; pesquisa reservada pelo responsável do mapa para lançamento em background. Branch: `research/agent-orchestration-temporal`, worktree: `.worktrees/agent-orchestration-temporal/`. O responsável registra o identificador da execução após lançamento.
- Relatório esperado: `docs/research/agent-orchestration/temporal.md` nessa branch; sem merge/PR. Resultado só resolve o ticket após verificação pelo responsável do mapa.

- Fontes iniciais: https://docs.temporal.io/ ; https://docs.temporal.io/self-hosted-guide ; https://learn.temporal.io/tutorials/ai/building-durable-ai-applications/human-in-the-loop/
- Comparação inicial na conversa foi exploratória, não evidência suficiente de adoção.

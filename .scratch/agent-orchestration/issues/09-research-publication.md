# Desbloquear a publicação das evidências com confiança SSH validada

Type: task
Status: open
Blocked by: 01

## Question

As três pesquisas terminaram com relatório commitado e Full gate verde, mas seus pushes falharam com `Host key verification failed.`. Como entregar as evidências sem enfraquecer a confiança SSH nem perder os commits locais?

Este é um impedimento operacional HITL, não pesquisa faltante ou escolha de motor. O humano responsável/infraestrutura deve validar a identidade do host e o acesso ao remote pelo procedimento autorizado; depois, autorizar a retomada dos pushes das branches de pesquisa. Alternativamente, o humano pode aceitar explicitamente a entrega apenas local e ajustar a exigência de publicação deste esforço.

Não usar `StrictHostKeyChecking=no`, não inserir chave coletada da rede sem validação independente, não copiar credenciais/SSH agent pessoal para a sandbox nem mudar protocolo/remote como fallback silencioso. Não publicar `main`, não integrar pesquisa, não abrir PR e não refazer relatórios. No ambiente safe-pi, limites de mounts/credenciais devem ser preservados.

## Comments

- Não houve tentativa de remediar SSH. As worktrees estão limpas e as branches/commits permanecem locais.
- Evidências imutáveis e caminhos: [Investigar Temporal para orquestrar harnesses externos](03-temporal.md), [Investigar Hatchet para orquestrar harnesses externos](04-hatchet.md), [Investigar Restate para orquestrar harnesses externos](05-restate.md).
- Não existe pesquisa rodando nem supervisor aguardando resposta. Nova sessão pode retomar pelo mapa e discutir a régua; escolha final continua bloqueada pelos tickets pendentes.

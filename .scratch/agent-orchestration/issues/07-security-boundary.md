# Definir as fronteiras de confiança do executor e da intervenção humana

Type: grilling
Status: open
Blocked by: 01

## Question

Qual fronteira protege máquina, repositórios, credenciais, equipe e estado de controle contra um agente induzido por prompt injection, preservando ajuda humana por tracker/Git sem acesso à máquina?

Decidir identidade e credenciais do worker versus control plane, permissões de tracker/Git, autenticidade e correlação de respostas, entradas não confiáveis, enforcement de rede, compartilhamento de caches e metadados Git, e privilégio da infraestrutura. Agente não pode conceder a si mesmo a aprovação humana editando o ticket.

Proposta aberta: Git gravável exclusivo por execução (clone ou equivalente), em vez de .git compartilhado entre worktrees de execuções diferentes. O isolamento interno dos subagentes não deve escapar da fronteira do ticket.

Preservar decisões de não usar SSH agent pessoal, não montar todo estado Pi gravável e não acessar produção. Não afirmar que Docker, rootless ou microVM eliminam exfiltração pelas permissões concedidas.

## Comments

- A comparação Docker versus safe-pi deve comparar contratos concretos; safe-pi já usa Docker.

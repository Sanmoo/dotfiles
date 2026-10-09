# pi-deere — segundo perfil Copilot com ambiente e conversas compartilhados

Status: ready-for-agent

## Problem Statement

O usuário tem duas contas GitHub, cada uma com sua própria assinatura GitHub
Copilot, e quer poder aproveitar a franquia de ambas ao trabalhar com Pi.
No perfil atual, um segundo login no mesmo provider substitui a credencial
anterior. Refazer login a cada troca seria inconveniente e colocaria em risco
a configuração que já funciona.

A experiência ideal seria um único Pi com duas contas selecionáveis, mas o
usuário prefere uma solução simples e sustentável a uma integração de
autenticação complexa. Ele aceita encerrar uma instância, abrir outra usando
a segunda conta e retomar a conversa, desde que suas extensões, skills,
prompts e preferências continuem disponíveis.

O comando existente deve continuar funcionando com a primeira conta Copilot,
os demais providers e suas configurações atuais. O nome confirmado para o
segundo comando é **pi-deere**. Esse nome identifica o comando e o perfil,
não autoriza inferir qual organização, domínio GitHub ou modalidade de plano
a segunda conta utiliza.

## Solution

Disponibilizar pi-deere como um launcher do Pi instalado, usando um segundo
perfil com credenciais próprias. A primeira configuração permanece sob o
comando pi, sem substituí-lo, interceptá-lo ou alterar seus logins.

O segundo perfil começa com a segunda conta Copilot, sem copiar os logins
dos demais providers. Ambos reutilizam o ambiente existente — extensões,
skills, prompts, temas, instruções, keybindings e preferências relevantes —
por uma única fonte de manutenção, não por duas cópias mantidas à mão.

As sessões ficam acessíveis pelos dois perfis. Para trocar a assinatura
usada em uma conversa, o usuário encerra a instância anterior e abre
pi-deere, selecionando a sessão existente ou informando sua identidade
exata. O mesmo fluxo permite voltar ao pi original. Não é preciso exportar
o histórico, recriar a conversa ou fazer login novamente em cada troca.

A conta é escolhida explicitamente pelo comando de entrada. Cada conta
consome sua própria franquia; não há soma de franquias, monitoramento de
saldo ou alternância automática. Instâncias simultâneas podem trabalhar
em sessões diferentes; escrever na mesma sessão a partir de duas
instâncias não faz parte do fluxo suportado.

## Job Stories

1. Quando tenho franquia disponível na segunda assinatura Copilot, quero iniciar pi-deere com essa conta, para consumir a assinatura escolhida sem substituir o login da primeira.
2. Quando continuo usando meu ambiente habitual, quero que pi mantenha seus logins e comportamento, para que a nova opção não interrompa meu fluxo já configurado.
3. Quando configuro pi-deere pela primeira vez, quero autenticar explicitamente a segunda conta GitHub, para associar o perfil à assinatura correta sem copiar credenciais do primeiro.
4. Quando volto a usar pi-deere após sua configuração, quero reutilizar o login salvo nesse perfil, para não repetir a autenticação a cada troca de conta.
5. Quando inicio uma conversa nova em pi-deere, quero usar Copilot mesmo que o perfil original tenha outro provider padrão, para consumir a segunda assinatura sem mudar minhas preferências globais.
6. Quando preciso trocar de assinatura durante uma conversa, quero encerrar a instância atual e retomar o mesmo histórico no outro perfil, para continuar o trabalho sem reconstruir o contexto.
7. Quando existem várias conversas no mesmo projeto, quero escolher a sessão que estava usando, para não abrir por engano a conversa mais recente de outro trabalho.
8. Quando conheço a identidade ou o arquivo de uma sessão, quero informar essa referência ao launcher, para reabrir exatamente aquela conversa com a conta escolhida.
9. Quando prefiro escolher a conversa visualmente, quero usar o seletor nativo de sessões, para reconhecer e abrir o histórico desejado sem localizar arquivos manualmente.
10. Quando a referência exata de uma sessão não existe, quero receber uma falha visível em vez de uma conversa vazia criada silenciosamente, para perceber que não retomei o trabalho pretendido.
11. Quando termino uma etapa em pi-deere e volto ao pi, quero encontrar as novas mensagens da mesma sessão, para continuar a conversa em ambos os sentidos.
12. Quando trabalho em projetos diferentes, quero preservar a associação entre sessões e diretório de trabalho, para não misturar os históricos desses projetos ao compartilhar o armazenamento.
13. Quando abro uma sessão cujo modelo também está disponível na segunda conta, quero preservar seu histórico e as escolhas de modelo e thinking suportadas, para que a troca de credencial não mude desnecessariamente a conversa.
14. Quando o modelo anterior não está disponível na segunda conta ou depende de outro provider sem login nesse perfil, quero escolher explicitamente um modelo Copilot disponível, para continuar sem cair silenciosamente na conta ou no provider errado.
15. Quando atualizo minhas extensões ou pacotes, quero que pi-deere use a mesma instalação mantida para meu ambiente habitual, para não gerenciar duas árvores de dependências.
16. Quando ajusto skills, prompts, temas, instruções ou keybindings compartilhados, quero que a próxima execução de ambos os comandos reflita a mudança, para manter uma experiência consistente sem repetir a configuração.
17. Quando uma preferência padrão do perfil original não serve para Copilot, quero que pi-deere aplique apenas o ajuste necessário ao seu lançamento, para não sobrescrever as preferências usadas por pi.
18. Quando o token Copilot da segunda conta precisa de renovação, quero que o Pi renove a credencial do segundo perfil, para continuar trabalhando sem tocar na autenticação da primeira conta.
19. Quando faço logout ou substituo o login em um dos perfis, quero que o outro permaneça autenticado, para poder gerenciar as contas independentemente.
20. Quando pi-deere ainda não tem login ou sua autenticação falha, quero uma indicação clara de que preciso autenticar esse perfil, para não consumir inadvertidamente a primeira assinatura.
21. Quando minha shell herda variáveis de autenticação, quero que elas não façam pi-deere usar silenciosamente a primeira conta Copilot, para confiar que o comando seleciona a assinatura pretendida.
22. Quando invoco opções nativas do Pi ou passo um prompt com espaços, quero que o launcher preserve os argumentos e o diretório de trabalho, para continuar usando a interface conhecida sem surpresas de quoting.
23. Quando interrompo ou encerro pi-deere, quero o comportamento de sinais e o status de saída esperados do Pi, para que o launcher não esconda erros nem deixe processos desnecessários.
24. Quando aplico meus dotfiles em outra instalação, quero poder disponibilizar o comando sem versionar tokens ou sessões, para reproduzir a configuração sem divulgar dados privados.
25. Quando executo o launcher repetidamente, quero que a preparação do segundo perfil seja idempotente, para não perder credenciais, recursos ou histórico já existentes.
26. Quando a preparação encontra um arquivo ou link conflitante, quero um erro acionável sem substituição destrutiva, para preservar minha configuração local e decidir a recuperação.
27. Quando preciso usar as duas assinaturas simultaneamente, quero abrir sessões diferentes em cada instância, para trabalhar em paralelo sem dois escritores alterando a mesma conversa.
28. Quando vou retomar uma conversa no outro perfil, quero instruções que deixem claro encerrar a instância anterior, para evitar escrita concorrente no mesmo histórico.
29. Quando decido qual assinatura usar, quero reconhecer pi-deere como o segundo perfil e pi como o ambiente original, para escolher manualmente a conta sem automações ocultas.
30. Quando o compartilhamento de recursos não está configurado corretamente, quero descobrir isso na validação e receber uma falha clara de preparação quando detectável, para não aceitar um segundo Pi silenciosamente incompleto.

## Implementation Decisions

- Criar um launcher chamado pi-deere no mecanismo de distribuição de comandos do pacote Pi dos dotfiles. Reutilizar o executável Pi instalado; não manter outra versão do Pi nem uma implementação própria do protocolo Copilot.
- Manter o comando pi, seus logins, as integrações existentes e o comando safe-pi inalterados. A escolha da segunda conta ocorre somente pelo novo launcher.
- Usar os mecanismos nativos de perfil do Pi para separar o armazenamento de credenciais. O segundo perfil tem identidade estável, armazenamento privado e persistente e não compartilha nem recebe uma cópia do arquivo de credenciais do primeiro.
- Inicialmente configurar apenas a segunda autenticação Copilot no novo perfil. Não importar logins dos demais providers; sua configuração futura seria uma ação separada e explícita. Esta decisão não exige implementar uma nova lista de providers permitidos no núcleo do Pi.
- Reutilizar os recursos e as preferências do ambiente existente a partir de uma fonte mantida em comum. A implementação deve considerar descoberta de recursos, instalações npm/git, caminhos relativos, symlinks e dependências de pacotes. Copiar somente declarações de configuração não comprova que os recursos carregam.
- Compartilhar preferências gerais sem impor ao pi original os defaults necessários a pi-deere. O launcher deve selecionar Copilot para novas conversas, independentemente do provider padrão original; não fixar um modelo de catálogo apenas por estar disponível hoje.
- Respeitar o modelo e o thinking restaurados de uma sessão quando puderem ser usados com Copilot no segundo perfil. Se não puderem, oferecer o fluxo nativo de escolha explícita ou uma orientação acionável, sem migração silenciosa para outro provider ou conta.
- Preservar a descoberta de sessões já existentes e sua associação ao projeto. Compartilhar o histórico não pode exigir migração destrutiva, exportação ou cópia de todas as conversas. Validar a semântica nativa de agrupamento ao usar overrides de armazenamento.
- Preservar identidade exata, histórico, branch ativo e novas mensagens na retomada em ambos os sentidos. O seletor de sessões e a retomada por identidade ou referência são as interfaces existentes; continuar a sessão mais recente não substitui a seleção exata.
- A credencial usada em novas requisições deve vir do perfil escolhido pelo launcher, não do histórico da sessão. Login, logout e renovação continuam sob responsabilidade da autenticação nativa do Copilot.
- Impedir fallback silencioso para credenciais Copilot da primeira conta, inclusive quando houver fontes de autenticação herdadas da shell. Não registrar tokens, cabeçalhos de autenticação ou conteúdo completo das credenciais.
- Fazer a preparação local do perfil de forma idempotente e não destrutiva. Conflitos são erros acionáveis; não substituir arquivos ou links desconhecidos. A autenticação real é uma ação do usuário, não uma migração automática.
- Encaminhar as opções e prompts nativos sem reinterpretação indevida, preservando diretório de trabalho, limites entre argumentos, sinais e status de saída. Opções de sessão devem preservar a semântica documentada do Pi.
- Auditar apenas as adaptações de compatibilidade necessárias aos recursos compartilhados. Existe uma extensão local que assume o diretório padrão para preferências e agentes; o segundo perfil não deve causar novas alterações nas preferências do primeiro. Não incluir refatorações ou correções de bugs não relacionadas a este contrato.
- Não prometer isolamento de segurança entre contas: extensões compartilhadas executam com as permissões do usuário. A separação é de seleção e persistência de autenticação, não uma Sandbox.
- Documentar a instalação, o login da segunda conta, a escolha manual, a retomada exata, a volta ao primeiro perfil e a recuperação de conflitos. Recursos comuns continuam sendo mantidos no ambiente original.
- O fluxo suportado tem um único escritor por sessão. Execuções simultâneas são suportadas em sessões distintas; o procedimento de troca exige encerrar a instância anterior. Não construir um novo protocolo de locks entre instâncias nesta entrega.

## Testing Decisions

- A seam principal é a execução pública do launcher até o processo Pi. Executar o comando real com uma home temporária, recursos locais e um colaborador Pi controlado, observando ambiente recebido, argumentos, diretório de trabalho, arquivos externos visíveis, sinais e status de saída. Não testar a estrutura privada de funções ou escolher uma implementação com base no formato interno dos symlinks.
- Os módulos sob teste são o launcher, sua preparação do perfil e o carregamento dos recursos que ele expõe ao Pi. Preferir uma única suíte de integração nesse limite, acrescentando cobertura localizada somente quando uma adaptação indispensável de extensão não puder ser exercitada por ele.
- Há prior art no repositório: os testes do wrapper safe-pi executam o script real com colaboradores controlados no PATH e verificam argumentos e códigos de saída; os testes do launcher WorkQ verificam seu limite de processo; os testes de configuração com Stow usam homes temporárias e conflitos reais.
- Cobrir primeira preparação e repetições; perfil já autenticado; conflitos sem sobrescrita; ausência do executável ou de um recurso necessário; caminhos e prompts com espaços; preservação do diretório e encaminhamento dos argumentos; status de saída e encerramento.
- Demonstrar credenciais independentes usando dados fictícios: uma alteração, logout ou renovação simulada no segundo perfil não altera o armazenamento do primeiro. A preparação não copia a credencial original nem importa outros providers.
- Cobrir o caso de variáveis herdadas que poderiam autenticar a conta Copilot errada. Sem a credencial correta do segundo perfil, a execução deve pedir autenticação ou falhar de modo visível, nunca usar a primeira conta como fallback.
- Verificar que o segundo perfil inicia uma nova conversa em Copilot mesmo quando as preferências originais apontam para outro provider, sem mudar os defaults originais. Não usar apenas uma fixture em que o primeiro perfil já é Copilot.
- Verificar compartilhamento efetivo com recursos de fixture carregáveis pelo Pi: extensão, skill, prompt, preferências e ao menos um pacote com dependência local. Uma alteração na fonte comum deve aparecer na próxima execução dos dois perfis sem uma segunda edição ou instalação.
- Complementar o colaborador controlado com um teste hermético de carregamento usando o Pi real disponível, recursos locais e credenciais fictícias, sem chamadas a GitHub, downloads ou consumo de franquia. A substituição do processo por um stub não prova a descoberta nativa de recursos ou de sessões.
- Usar pelo menos duas sessões no mesmo projeto e outro projeto para demonstrar retomada da sessão exata, preservação de identidade, histórico e branch, descoberta pelo seletor e isolamento por diretório de trabalho. Demonstrar a ida ao segundo perfil e a volta ao primeiro; uma referência inexistente não pode virar outra conversa silenciosamente.
- Testar a interação com restauração de modelo e thinking e com a extensão local de isolamento de preferências. Um modelo indisponível no segundo perfil deve levar a uma escolha explícita ou erro orientado, não a uma conta ou provider alternativo.
- Fazer um smoke test supervisionado com os dois logins reais já fornecidos pelo usuário: confirmar a associação de cada perfil à conta pretendida, uma requisição Copilot em cada perfil e a retomada de uma conversa sem dois escritores simultâneos. Guardar somente evidência redigida, nunca tokens ou arquivos privados. Esse teste depende de autenticação humana e não é substituído por análise estática ou credenciais fictícias.
- A suíte automatizada deve funcionar sem rede e sem os logins reais. Registrar a indisponibilidade de uma pré-condição do smoke test, em vez de declará-lo aprovado.
- Integrar os testes ao Quality gateway existente. Um Fast gate verde não basta para concluir a implementação; o Full gate precisa encerrar com a linha explícita FULL GATE: PASS. Registrar separadamente o resultado do smoke test real.

## Out of Scope

- Duas contas selecionáveis dentro de uma única instância em execução.
- Novos providers Copilot, aliases de provider, uma extensão de autenticação, custom streaming ou mudanças no núcleo do Pi.
- Somar franquias, transferir créditos, medir saldo, estimar consumo por conta ou construir relatórios de cobrança.
- Alternância automática, failover, balanceamento, rotação por requisição ou tentativas automáticas de contornar limites.
- Copiar todos os logins do ambiente original ou disponibilizar automaticamente os demais providers em pi-deere.
- Criar, adquirir, transferir ou alterar assinaturas GitHub e permissões de organizações.
- Escrita simultânea de duas instâncias na mesma sessão e um mecanismo novo de coordenação distribuída.
- Alterar safe-pi, a política da Sandbox, WorkQ, a escolha automática de agente do Herdr ou sua recuperação após restart para reconhecer pi-deere.
- Modificar configurações ou skills de terceiros que não sejam necessárias ao comportamento do segundo perfil.
- Versionar credenciais, sessões, caches, instalações de pacotes ou quaisquer dados privados.
- Implementar a feature durante a publicação desta especificação.

## Further Notes

### Decisões confirmadas

O usuário confirmou a solução com duas instâncias, troca manual, retomada da
conversa, recursos compartilhados e um segundo perfil inicialmente só com
Copilot. A última atualização troca o nome sugerido do segundo comando pelo
nome definitivo pi-deere. Não há uma entrevista pendente para reabrir essas
decisões.

Conta GitHub é a identidade autenticada; assinatura Copilot é o plano dessa
conta; franquia é a capacidade de uso atribuída à assinatura; perfil Pi é o
ambiente que seleciona e persiste a credencial. Reutilizar uma sessão não
une as assinaturas nem muda o titular de uma credencial.

### Estado atual e evidência

A instalação inspecionada de Pi é 1.1.0. Sua autenticação mantém uma
credencial por provider em cada perfil; completar um segundo login no
mesmo provider substitui a entrada local anterior. Perfis separados
separam essas entradas. O Pi documenta seleção de diretório de perfil,
seleção de armazenamento de sessões, seletor de retomada e abertura por
referência exata.

O repositório distribui um pacote Pi comum e variantes de preferências
por plataforma usando GNU Stow. A configuração macOS inspecionada tem
um provider padrão que não é Copilot e vários pacotes npm; portanto, um
segundo diretório vazio com apenas login não satisfaz a experiência
compartilhada.

A extensão local de isolamento de preferências utiliza o diretório Pi
padrão em parte de sua resolução. Isso é uma atenção de compatibilidade
para o perfil alternativo, não autorização para consertar todos os seus
comportamentos. A investigação anterior encontrou um erro de retomada
de subagente; esse erro não faz parte desta feature.

A viabilidade foi estabelecida por documentação e leitura de código,
não por dois logins reais. O compartilhamento dos recursos instalados e
a retomada com autenticação distinta ainda exigem os testes definidos
acima. Não inferir disponibilidade de modelos, permissões organizacionais,
limites de concorrência ou compatibilidade com políticas do GitHub.

### Referências e handoff

- Contexto e vocabulário do repositório: [CONTEXT](../../CONTEXT.md).
- Decisão existente que preserva pi e distingue a Sandbox: [ADR 0002](../../docs/adr/0002-pi-in-docker-sandbox.md). Esta feature é um launcher no host e não altera essa decisão.
- Prior art de retomada exata, distinguindo sessão escolhida da mais recente: [ticket safe-pi 10](../safe-pi/issues/10-exact-session-resume.md).
- Ticket de implementação: [01 — Disponibilizar pi-deere](issues/01-pi-deere-launcher.md).
- Documentação upstream: [configuração](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/configuration.md), [sessões](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/sessions.md), [CLI](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/cli.md) e [pacotes](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md). A versão instalada é a referência de validação; a documentação upstream pode evoluir.

A seam foi explicitada na publicação desta spec, sem nova entrevista,
conforme solicitado: o contrato público do launcher, complementado pela
validação hermética da integração com o Pi real. A implementação deve
manter o menor número de seams possível, não substituir essa abordagem
por testes de detalhes internos.

O spec e o ticket são task management e são publicados diretamente em
main. A implementação futura segue o fluxo de branch/worktree isolados.

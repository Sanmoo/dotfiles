# Skills externas como dependências locais

Status: ready-for-agent

## Problem Statement

O repositório pessoal de dotfiles versiona cópias de skills mantidas externamente, inclusive as do Matt Pocock. O usuário quer consumir o upstream no computador pessoal e um fork corporativo no computador da empresa, sem transformar os dotfiles pessoais em um distribuidor desses conteúdos ou em uma configuração específica da empresa.

Atualmente, o diretório global compartilhado de agentes é um symlink para o checkout dos dotfiles. Instalar ou atualizar uma skill pode, portanto, modificar o repositório. No checkout inspecionado, várias cópias rastreadas já foram substituídas localmente por symlinks absolutos para um fork corporativo. Essas alterações locais precisam ser preservadas, não publicadas nem revertidas pela migração.

## Solution

Separar configuração pessoal de dependências instaladas. Os dotfiles passam a versionar apenas configuração e skills de autoria do usuário, mantidas independentemente e sem conteúdo corporativo. Skills externas, suas adaptações e os metadados locais de instalação ficam fora do checkout.

O diretório global compartilhado de agentes passa a ser um diretório real, independente dos dotfiles. A instalação de dependências é gerenciada separadamente do bootstrap. No ambiente pessoal, o usuário escolhe o upstream; no corporativo, escolhe o fork por meios locais. O repositório pessoal não conhece URLs, caminhos nem seleções corporativas.

A transição preserva as instalações existentes e remove as dependências externas apenas da versão atual do Git, sem reescrever o histórico.

## Job Stories

1. Quando configuro meu computador pessoal, quero instalar as skills diretamente de sua origem pública, para consumir o upstream sem manter cópias nos dotfiles.
2. Quando configuro meu computador corporativo, quero escolher um fork localmente, para usar as adaptações da empresa sem publicá-las no repositório pessoal.
3. Quando aplico os mesmos dotfiles em ambientes diferentes, quero que eles sejam indiferentes à empresa, para compartilhar minha configuração sem transportar referências corporativas.
4. Quando instalo uma skill externa, quero que seus arquivos fiquem fora do checkout, para não gerar mudanças acidentais nos dotfiles.
5. Quando atualizo uma dependência, quero que seus metadados de instalação sejam locais, para não misturar o estado da máquina com configuração versionada.
6. Quando aplico o bootstrap, quero que ele não instale dependências externas automaticamente, para não substituir minha escolha de origem.
7. Quando já tenho um fork instalado, quero que aplicar os dotfiles preserve essa instalação, para não voltar inadvertidamente ao upstream.
8. Quando migro o diretório global atualmente vinculado ao checkout, quero preservar todas as instalações existentes, para continuar usando minhas skills após a transição.
9. Quando uma instalação existente é um symlink, quero preservar o link e seu destino, para manter a relação com a origem sem copiar conteúdo corporativo.
10. Quando existem arquivos locais ainda não commitados, quero preservá-los durante a migração, para não perder trabalho ou configurações da máquina.
11. Quando há um conflito no destino da migração, quero que ele seja detectado antes de qualquer sobrescrita destrutiva, para decidir como resolvê-lo sem perda de dados.
12. Quando repito uma migração já concluída, quero que ela mantenha o estado válido, para poder repetir a operação sem duplicação ou danos.
13. Quando interrompo ou encontro uma falha na migração, quero conservar uma forma de recuperar o estado anterior, para não perder acesso às instalações.
14. Quando crio uma skill de autoria própria, quero poder versioná-la nos dotfiles sem controlar o diretório global inteiro, para compartilhar minha autoria sem absorver dependências locais.
15. Quando adapto uma skill de terceiros, quero manter a adaptação no fork correspondente, para preservar uma origem clara em vez de tratar uma cópia editada como autoria própria.
16. Quando adiciono outro fornecedor de skills, quero aplicar a mesma separação, para não criar exceções específicas por fornecedor.
17. Quando reviso uma mudança nos dotfiles, quero encontrar apenas configuração e autoria própria, para evitar commits de instalações ou caminhos específicos da máquina.
18. Quando removo dependências versionadas, quero preservar o histórico existente, para evitar uma reescrita desnecessária por conteúdo público já publicado.
19. Quando preparo uma máquina nova, quero instruções claras para aplicar os dotfiles e instalar dependências separadamente, para entender qual operação é responsável por cada parte do ambiente.
20. Quando testo a transição, quero usar instalações fictícias em um ambiente isolado, para verificar preservação e conflitos sem acessar recursos corporativos ou alterar minhas skills reais.

## Implementation Decisions

- A regra se aplica a toda skill mantida externamente, não apenas às skills do Matt Pocock.
- Uma skill própria é de autoria do usuário, mantida independentemente e sem conteúdo corporativo. Editar uma cópia externa não a torna própria; adaptações pertencem ao fork correspondente.
- O diretório global compartilhado de agentes será real e externo ao checkout. O Stow não poderá assumir controle desse diretório inteiro.
- Arquivos ou skills próprios poderão ser disponibilizados individualmente pelo mecanismo dos dotfiles, sem absorver instalações externas nem sobrescrever entradas locais.
- Conteúdo de dependências, symlinks para origens externas e lockfiles de instalação não serão rastreados pelos dotfiles. Isso não proíbe links internos usados para disponibilizar autoria própria.
- O bootstrap não instalará, atualizará ou selecionará dependências externas. Seu gerenciamento será separado e documentado.
- O repositório pessoal não conterá configuração específica da empresa, incluindo origem do fork, caminhos absolutos corporativos ou seleção corporativa de skills.
- A migração abrangerá o conteúdo local existente do diretório compartilhado, incluindo instalações não rastreadas, symlinks e metadados. Preservar um symlink não implica copiar ou alterar seu destino, nem exige que o destino esteja disponível durante a migração.
- A migração precisará distinguir o vínculo legado com os dotfiles de um diretório real já migrado e de outros estados inesperados. Conflitos não poderão ser resolvidos com sobrescrita silenciosa.
- A transição deve garantir recuperabilidade antes de remover o vínculo legado ou os arquivos dos quais ele depende. A ordem de integração e migração deverá impedir que uma remoção no checkout elimine a única cópia instalada.
- A remoção do rastreamento Git não autoriza apagar instalações locais. Alterações preexistentes e não relacionadas deverão ser preservadas.
- As dependências serão removidas somente da versão atual do repositório; o histórico Git será mantido.
- A documentação deixará de apresentar vendoring como política padrão e explicará a separação entre aplicar configuração, disponibilizar autoria própria e instalar dependências.
- Esta entrega é uma spec. Sua publicação não executa a migração nem altera a configuração instalada na máquina.

## Testing Decisions

- A fronteira confirmada pelo usuário é integração pelo filesystem e pelo Stow, com um diretório home temporário. Priorizar uma única fronteira de comportamento observável, sem testes de estruturas internas.
- O precedente existente no repositório são testes shell. Reutilizar esse estilo para executar as operações reais em fixtures isoladas, sem criar um framework novo sem necessidade.
- Testar aplicação dos dotfiles, transição do vínculo legado e coexistência com instalações locais. Asserções devem observar arquivos, tipos de entradas, conteúdo, destinos de symlinks, resultado das operações e estado Git.
- Verificar que uma instalação nova mantém o diretório global real e externo ao checkout, sem baixar dependências ou exigir acesso a rede.
- Verificar que aplicar e reaplicar os dotfiles não sobrescreve instalações externas nem seus metadados e permite disponibilizar uma skill própria sem controlar o diretório inteiro.
- Simular o estado legado com arquivos rastreados, arquivos locais não rastreados, lockfile e symlinks externos. Comparar o estado antes e depois para garantir preservação de conteúdo e destinos, inclusive links cujo destino esteja indisponível.
- Verificar a ordem completa da transição, incluindo a retirada das dependências do checkout, para demonstrar que a instalação preservada não depende de arquivos posteriormente removidos.
- Testar destino conflitante e estado inesperado: falhar de forma compreensível sem perda de dados nem sobrescrita silenciosa.
- Repetir a migração e verificar que o estado final permanece válido, sem duplicação ou danos.
- Exercitar uma falha representativa da transição e demonstrar que as instalações continuam recuperáveis.
- Instalar uma dependência fictícia após a transição e verificar que o checkout não muda.
- Inspecionar os arquivos rastreados para verificar a ausência de dependências externas, lockfile local e referências corporativas introduzidas pela mudança; confirmar que a implementação não reescreve o histórico.
- Não usar conteúdo corporativo nos testes nem executar as operações contra o home real durante a validação automatizada.

## Out of Scope

- Implementar a funcionalidade ou migrar o ambiente real durante a publicação desta spec.
- Automatizar download, atualização, seleção de fornecedor ou instalação de dependências no bootstrap.
- Criar perfis específicos da empresa ou publicar URLs, caminhos e conteúdo corporativo.
- Alterar o upstream ou os forks das skills, ou modificar o conteúdo das skills como parte da separação.
- Escolher uma nova ferramenta de gerenciamento de dependências ou definir uma política de versões e atualização.
- Reescrever o histórico Git ou executar uma limpeza de possíveis vazamentos históricos. Caso conteúdo corporativo já commitado seja identificado, avaliá-lo separadamente.
- Resolver symlinks externos indisponíveis, mover os repositórios de origem ou modificar seus destinos.
- Reformular globalmente os mecanismos de descoberta de skills de todos os agentes.

## Further Notes

As decisões de separação, autoria, armazenamento local, preservação do histórico e a fronteira de testes foram confirmadas pelo usuário. A implementação e a migração real foram substituídas, nesta etapa, pelo pedido de uma spec.

O checkout inspecionado contém alterações locais nas skills e em configuração do agente. Elas não são parte da entrega desta spec e devem permanecer intactas. O uso de symlinks corporativos locais observado não comprova a existência de conteúdo corporativo já commitado.

As instruções do repositório definem um tracker Markdown local e o status canônico `ready-for-agent`; specs existentes usam esse status diretamente. As referências a documentos auxiliares de tracker, triagem e domínio nas instruções não estavam disponíveis no checkout inspecionado. Não foi encontrado um glossário existente nem uma decisão arquitetural específica sobre esta separação.

Critério de conclusão da futura implementação: dependências ausentes dos arquivos rastreados atuais; configuração aplicável sem instalação implícita de skills; diretório local independente; migração comprovadamente preservadora; documentação atualizada; testes de integração aprovados; nenhuma referência corporativa nova publicada.

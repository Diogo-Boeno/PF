Documento de Game Design (GDD): Sistema de Progressão "Peregrinação & Cativeiro"

1. Visão Geral do Sistema
O jogo deve utilizar um sistema de progressão imersivo e punitivo, focado em Dark Fantasy / Terror Realista. O jogador não sobe de nível através de um menu de pausa. A evolução exige exploração física pelo mapa (Santuários), escolhas definitivas de atributos, e a aceitação de fardos espirituais ou profanos (Votos) que alteram drasticamente a mecânica de jogo e a aparência do personagem.

2. O Loop de Progressão (Core Loop)
Coleta: O jogador derrota inimigos e explora o mundo para acumular Essência Bruta (moeda de XP genérica).

Peregrinação: O jogador viaja até Santuários de Foco específicos no mapa (NPCs ou altares) correspondentes ao status que deseja aumentar.

Refinamento: O jogador gasta a Essência Bruta no Santuário para "comprar" pontos exatos de um atributo específico

Epifania (Talentos): Ao atingir marcos de atributos (ex: Nível 10, 20), o Santuário oferece um Rito de Epifania (seleção estilo "mão de cartas"). O jogador escolhe 1 entre 3 Estigmas (talentos passivos/ativos). (Pretendo fazer uma animação onde o NPC correspondente ao seu juramento, ele aparece te propondo algumas opções que você pode escolher para seguir para sempre com ele)

O Cativeiro (Endgame): Ao atingir requisitos altos, o jogador encontra NPCs ocultos para realizar um Voto de Cativeiro, adquirindo uma maldição permanente em troca de uma árvore de habilidades exclusiva e deformação visual.

3. Mecânicas Detalhadas para Implementação
3.1. Atributos por Linhagem (Raças e Origens)
Os status não são universais. Cada Origem possui variáveis próprias.

Ação Requerida (Código): Criar dicionários/tabelas modulares para cada Origem, prefira usar o esquema de components.

Exemplo - Raça "Rastejantes": Status Expansao Carnal (HP/Defesa) e Fome Predatoria (Velocidade/Lifesteal).

Exemplo - Raça "Arautos": Status Fervor Cego (Dano Mágico em área/Glass Cannon) e Presenca Castigadora (Debuff em área).

3.2. Santuários e Marcos (Milestones)
O investimento de pontos é limitado pelo nível de iniciação do jogador com aquele Santuário.

Ação Requerida (Código): O sistema deve validar no Servidor a localização do jogador (magnitude/hitbox do Santuário) e o "Tier" atual dele antes de permitir o gasto de Essência.

Marcos: A cada X pontos investidos em um status, disparar o evento de Seleção de Estigma para o Cliente.

3.3. Sistema de Estigmas (Seleção de Talentos)
Ação Requerida (Código): Criar um pool de talentos (tabelas) categorizados por Origem, Status e Nível do Marco.

A seleção deve gerar 3 opções (sem repetição) baseadas na categoria treinada.

A escolha do jogador deve ser gravada na base de dados e aplicar os modificadores (ex: Lifesteal_On_Perfect_Dodge) no loop de combate.

3.4. Votos de Cativeiro (Oaths / Maldições)
O jogador só pode ter 1 Voto ativo na base de dados.

A Maldição: Um debuff constante verificado pelo servidor. (Ex: Voto do Verme Pálido desativa a classe base de cura e só permite cura via execução de entidades mortas).

A Recompensa: Desbloqueia acesso a uma nova SkillTree ou TalentPool específica daquele Voto.

4. Diretrizes Técnicas e Estrutura de Dados (Luau/Roblox Architecture)
Para o agente de IA: A arquitetura deve ser modular e prever a serialização segura dos dados, considerando um ambiente de client-server (Client preditivo, Server autoritativo).

Requisitos de Organização:

Módulos de definição puros. Configurações de Santuários, cálculos de XP, listas de talentos (Estigmas) e metadados dos Votos.

Lógica de validação de transação de Essência, checagem de distância do Santuário, aplicação de debuffs das Maldições e salvamento de dados.

Client: Interfaces (UI) de apresentação sombria e imersiva para o "Rito de Epifania" (escolha das cartas) e feedback visual (partículas/sons) Feitos por mim, irei compartilhar as Hierarquias.

5. Direção de Arte e Feedback Visual (Para referência de scripts)
As alterações mecânicas devem acionar atualizações visuais no modelo do personagem para refletir a vibe de terror realista.


# pf

**ECHOES BEYOND** — MMORPG de ação dark fantasy do Cosmo, solo, Roblox.
GDD em `gdd.md`, `gddMelhor.md` e `gdd2.md`. Nenhum dos três é backlog — não implemente
nada de lá sem pedido pelo nome. `prompt.md` **não é documento do jogo**: é rascunho onde
o Cosmo elabora o próximo prompt, e o conteúdo troca sem aviso.

Estado: **base técnica**. Existe framework, kit de UI, rig custom animado, combate
(combo, guarda, parry, postura), NPC de treino, persistência por ProfileStore e o
esqueleto de progressão (atributos, linhagem, vidas, Santuário) e de inventário.

Referência declarada: Deepwoken — na **filosofia** (lore descoberta, consequência,
morte com peso), não na cópia. A identidade é Echo, Ressonância, Véu, Primeiros,
Peregrinação e Cativeiro. Ver "Mundo e progressão".

## Stack

| Camada | Ferramenta |
|---|---|
| Build | Rojo 7.7 (`default.project.json`) |
| Deps | Wally 0.3.2 |
| Tooling | Aftman 0.3 (`aftman.toml`) |
| Lint / format | selene 0.27, StyLua 0.20 |
| UI | Vide 0.4 — **nunca Roact** |
| UI dev | UI Labs 2.4, stories em `ReplicatedStorage/Stories/` |
| ECS | Jecs 0.11 — só para progressão, Estigmas e Echoes |
| Persistência | ProfileStore 0.1 — `DataService`, perfil por jogador |

**Só `vide` é usado hoje.** `ripple`, `charm`, `rng` e `quickzone` estão no `wally.toml`
sem um único `require` em `src/`. `blink` e `asphalt` estão pinados no Aftman e não têm
arquivo de config no repo. Antes de usar qualquer um deles, pergunte — estar instalado
não é decisão tomada.

Duas exceções. **`profilestore`** já é a persistência e roda em `DataService`.
**`jecs`** é o ECS do projeto, instalado de propósito e ainda sem uso — Estigmas e
Echoes são o destino dele.

**RaycastHitboxV4** não vem do Wally: o `lib/` de
[Swordphin/raycastHitboxRbxl](https://github.com/Swordphin/raycastHitboxRbxl) está
vendorizado em `src/ReplicatedStorage/RaycastHitbox/` (MIT, LICENSE junto). É código de
terceiro — **não rode StyLua nem selene nele**. Procura Attachments chamados `DmgPoint`
por default, que é como as armas já estão montadas. O autor descontinuou o V4.01 em 2021
em favor do ShapecastHitbox e admite bugs e custo de performance; a escolha pelo V4 é do
Cosmo e está tomada.

## Comandos

Não existe test runner. "Testar" = selene limpo + StyLua + `rojo build` compila.

```powershell
aftman install
wally install    # obrigatório antes do build

rojo serve       # dev, plugin Rojo no Studio

# só os arquivos que você alterou, nunca src/ inteiro
stylua src/path/File.luau
selene src/path/File.luau

rojo build default.project.json -o "$env:TEMP/project_test.rbxlx"
```

Stories de UI Labs só rodam dentro do Studio. Não há CLI pra elas.

## Framework

`src/ReplicatedStorage/Shared/Framework/` — cinco módulos, zero dependência externa.

- **Loader** — `LoadDescendants(folder)` + `Start()`. Roda todo `Init()` em sequência,
  depois cada `Start()` em `task.spawn`. Ambos opcionais, ambos em pcall: módulo que
  falha emite `warn` e não derruba o boot.
- **Net** — `FireClient`, `FireAllClients`, `FireServer`, `On`. RemoteEvent criado sob
  demanda no server, `WaitForChild` no client.
- **Signal** — `new`, `Connect`, `Once`, `Fire`, `Wait`, `Destroy`. `Fire` faz
  `task.spawn` por conexão, então handler lento não segura o emissor.
- **State** — key-value global com signal por chave: `Set`, `Get`, `Update`, `OnChange`,
  `Observe`, `Remove`. É fallback global — use com parcimônia.
- **Tags** — `Tags.bind(tag, handler)` sobre CollectionService, para instâncias já
  marcadas e futuras, com cleanup no untag/destroy. Retorna unbind.

Boot: `Bootstrap.server.luau` carrega `ServerScriptService/Services/`;
`Bootstrap.client.luau` carrega `PlayerScripts/Controllers/`. Módulo novo = retornar uma
table (com `Init`/`Start` opcionais) na pasta certa. Auto-descoberto, sem require manual.

## Rig e animação

O rig é **custom e não tem braços**: as palmas são flutuantes, presas direto no Torso.
Nada usa o espaçamento do R6 padrão — é `RightLeg`, não `"Right Leg"`.

```
Torso           Motor6D: Head, LeftLeg, RightLeg, LeftPalm, RightPalm
RightPalm       GripAttachment + Motor6D: RightFingers, RightThumb
LeftPalm        GripAttachment + Motor6D: LeftFingers, LeftThumb
LeftLeg/RightLeg    FeetAttachment
HumanoidRootPart    RootJoint
```

Convenção do rig: **cada Motor6D tem o nome da parte que ele move**, e mora dentro do
Part0. Vale para as juntas do rig, montadas no Studio.

Junta criada em runtime é a exceção: ela mora na parte que **morre junto com ela**, para
um único `Destroy` limpar tudo. A junta da arma segue o nome (`Handle`) mas fica no root
da arma, não na palma — se ficasse na palma, trocar de arma deixaria junta órfã.

`StarterCharacterScripts/Animate.client.luau` é o `Animate` da Roblox adaptado a esse
rig: resolve Motor6D **pela parte que ele move**, nunca por nome, e tolera junta
ausente. Ele existe também para suprimir o `Animate` que a Roblox injeta — apagar traz
as animações default de volta pra brigar pelas mesmas juntas.

Duas correções medidas moram lá e não devem ser revertidas sem medir de novo:
`MOVING_SPEED = 0.5` (o `0.01` do upstream trava a pose em `Running` para sempre depois
de um pouso) e o branch `Running` conferindo `AssemblyLinearVelocity`, porque
`Humanoid.Running` é edge-triggered e não re-dispara.

`src/ServerStorage/Animate.client.luau` é a versão anterior inteira comentada. É morto.

**SmartBone** (`SmartBoneController`) vem de `ReplicatedStorage.SmartBone` — não está no
Wally nem em `src/`. Vive no place file e **não é versionado**: clone limpo não tem.

## Mundo e progressão

O esqueleto existe (perfil, linhagem, vidas, atributos, Santuário); Ritos, Estigmas,
Echoes e Cativeiro não. O GDD vive em `gdd2.md` e é leitura, não backlog — não execute
nada de lá sem o Cosmo pedir pelo nome.

Referência declarada: **Deepwoken**, com desvios próprios. O maior deles é de
vocabulário e não é negociável:

| Aqui | Deepwoken |
|---|---|
| **Echo** | Song — a força cósmica do mundo |
| **Echoes** | Attunements — os poderes mágicos |
| Raw Essence | XP genérico, gasto em Santuário |
| Santuário | onde se compra ponto de atributo, presencialmente |
| Rito | o gate entre faixas de progressão |
| Estigma | talento escolhido 1-de-3 no Rito |
| Voto de Cativeiro | oath permanente, um por personagem |

**Nunca escreva "Song" nem "Attunement" no código, em comentário ou em UI.** São Echo e
Echoes, sempre.

Três eixos independentes, como no Deepwoken: **atributos**, **proficiência de arma**
(Light / Medium / Heavy) e **Echoes**. Proficiência não é atributo, e Echo não é
nenhum dos dois.

### Atributos

Seis universais, em dois grupos:

| Corpo | Mente |
|---|---|
| Strength | Insight |
| Fortitude | Presence |
| Swiftness | Willpower |

**Origem adiciona três atributos próprios, nunca modifica os seis.** Então a ficha de um
personagem é sempre `6 + 3`, e os seis universais significam a mesma coisa para todo
mundo — o que mantém a fórmula de dano uma só.

### Nível

Cap em **30**, com um desafio no **20** que destrava o resto. Nível e ponto de atributo
são contas separadas: a curva do Santuário abaixo governa pontos dentro de **um**
atributo, não o nível do personagem.

### Vida

**Vida não é `Humanoid.Health`.** `HealthService` guarda tudo em atributos do character
(`Health`, `MaxHealth`, `Defeated`) e o Humanoid é fixado em `1e6` com
`BreakJointsOnDeath = false`.

Dois motivos: a morte da Roblox desmonta o rig em peças, e aqui um personagem nunca se
despedaça — ele é **finalizado**, o corpo fica inteiro no chão. E possuir o número é o
que deixa armadura, resistência e execução serem nossas de definir em vez de brigar
contra a engine.

Nada usa `Humanoid.Died` nem `TakeDamage`. Derrota é o sinal `HealthService.Defeated`, e
"está vivo?" é `isDefeated`, nunca `Health > 0` — a vida do Humanoid não significa mais
nada. **HUD que ler `Humanoid.Health` fica cheia pra sempre**; a fonte é o atributo.

Os nomes moram em `data/shared/Weapons.luau`, junto de `posture` e `stun` — são todos
vitais de combate, e o client precisa exatamente das mesmas strings. `Progression` cuida
de linhagem e atributos, não disso.

### Vidas, morte e Lembranças

Duas vidas úteis moram num perfil só:

| | escopo | some quando |
|---|---|---|
| **Memories** (Lembranças) | conta | nunca |
| **Lineage** | personagem atual | a última vida acaba |

Linhagem nasce com **3 vidas**. Morrer gasta uma. Gastar a última encerra a linhagem:
parte da Essência gasta volta como Lembranças (`memoryRefund`) e o jogador cai na
criação de personagem.

**É isso que faz a morte doer sem destruir a conta.** Perde-se a build, não o progresso
de sempre — e é o que permite `Lineage = nil` ser o próprio gatilho da tela de criação,
sem flag separada.

Vida se recupera por `DataService.grantLife`. **Como** ela se recupera no mundo ainda
não foi decidido.

`LifeService` desliga `CharacterAutoLoads` e é o server que decide quando existe corpo.
Sem linhagem, ninguém spawna — é isso que faz a tela de criação não precisar de flag
própria. A linhagem nasce pelo remote `CreateLineage`, que a tela de criação chama.

### Santuário

Tag `Sanctuary` numa `BasePart`. Comprar atributo é `Net "BuyAttribute"`, e o server
confere **distância até um Santuário** antes de qualquer outra coisa.

Isso não é anti-cheat de rotina: "ir até lá" *é* a mecânica. Cliente que comprasse de
qualquer lugar transformaria a Peregrinação inteira num menu de pausa.

`buyAttribute` recusa com motivo (`unknown`, `maxed`, `rite`, `essence`) em vez de só
falhar — o teto bloqueado é design, e a UI precisa dizer qual dos dois parou.

### Curva do Santuário

| Faixa | Custo | Como abre |
|---|---|---|
| 1–15 | base | livre |
| 15 → 16 | — | **Rito** no Santuário + escolher um Estigma |
| 16–30 | dobro | — |
| 30 → 40 | — | **Rito** novo + oferenda rara |

Os tetos são o design: não se compra o ponto 16 sem ter ido a um Santuário e escolhido
um Estigma. Progressão é presencial e irreversível, nunca um menu de pausa.

Os marcos citados no GDD (10, 20) são exemplo **do evento de escolha de cartas**, não
desta curva. Quem manda em custo e teto é a tabela acima.

### Fórmula de dano

Do Deepwoken, e o formato importa:

```
Damage = 0.00075 * [Base * Scaling * Attribute * (1 + Proficiency * 0.065)] + Base
```

Atributo **multiplica** o base, não soma nele — arma ruim continua ruim com stat alto.
E proficiência multiplica só a parcela vinda do atributo, nunca o `Base`: proficiência
sem atributo investido não faz nada.

## Armas

Server decide **qual** arma; client constrói **a** arma. A arma nunca cruza a rede.

- `data/shared/Weapons.luau` — catálogo e contrato do rig, congelado
- `Services/WeaponService.luau` — valida o pedido e escreve `player:SetAttribute("Weapon", id)`.
  Nunca instancia nada
- `Controllers/WeaponController.luau` — observa o atributo de todos os players e monta o
  Motor6D localmente

Atributo em vez de broadcast porque replica nativamente e alcança late joiner de graça.
A junta é **Motor6D e não Weld**: só junta é animável. `C0`/`C1` saem direto dos dois
`GripAttachment` — o da `RightPalm` e o do root da arma, mesmo nome dos dois lados —
via `Part0.CFrame * C0 == Part1.CFrame * C1`, sem offset escrito à mão.

Toda arma roda num `PrimaryPart` chamado `Handle`. **Isso não é estilo**: animação
guarda pose por nome de parte, então root com nome divergente não é animável pelo mesmo
swing.

Templates ficam em `ReplicatedStorage/Weapons/` **no place file** — mesh não vai pro git,
e `$ignoreUnknownInstances` impede o Rojo de apagar.

### Animação de arma

Animação Roblox guarda Pose por nome de parte, e toda arma roda num `Handle` — então um
swing autorado uma vez serve todas as armas da classe.

**Classe é tipo + grip** (`SwordOneHand`, `GreataxeTwoHand`), e ela herda de duas camadas
acima. O nome do asset é o contrato:

| camada | onde | exemplo | serve |
|---|---|---|---|
| peso | `weights.Heavy` | `HeavyUppercut` | toda arma pesada |
| tipo | `types.Greataxe` | `GreatAxeAerial`, `GreataxeBlock` | greataxe em qualquer grip |
| classe | `classes.GreataxeTwoHand` | `GreataxeTwoHandsA1` | só aquele grip |
| arma | `animations` na entrada de `byId` | — | uma arma específica |

O merge roda **uma vez no require** e achata tudo dentro de `classes`, então
`CombatController` e `WeaponService` continuam lendo uma tabela só e não sabem que a
hierarquia existe.

Crouch e uppercut deixaram de ser puramente universais: `Config.crouch` e
`Config.uppercut.animation` continuam sendo o default, e classe ou peso sobrescrevem. É
por isso que o crouch é recarregado por arma e volta ao par universal ao desarmar.

### Swing speed

`speed` na classe é multiplicador de animação contra a **espada média a 1x** (greataxe
0.83). A conta é uma só:

```
TempoReal = Config.swingBase / speed
```

**Toda animação que o swing speed escala nasce com `swingBase` (0.40s).** Não é convenção
frouxa: o multiplicador é a única coisa que decide o tempo real, então animação autorada
já pesada é lentidão aplicada duas vezes — e como `AdjustSpeed` é uniforme, o windup e a
recuperação esticam junto e o golpe lê como desproporcional em vez de pesado. Foi
exatamente o que aconteceu no primeiro greataxe.

`buildTrack` confere o `Length` contra `swingBase` com `debugHitbox` ligado e emite warn
nomeando o asset. Sem isso o erro é mudo: o golpe só "parece errado" e nenhum número no
código tem culpa.

### Hitstun

`hitstun` mora na **camada de peso**, porque quanto tempo um golpe compra é propriedade
de quem bateu, não do movimento: Light 0.6s, Medium 0.9s, Heavy 1.2s. `Config.hitstun`
é só o fallback de classe sem peso.

Era um número global de 0.45s, e é por isso que spammar M1 com arma pesada perdia a
troca — o ciclo do swing era mais longo que o stun que ele mesmo aplicava.

Quem obedece e quem não:

| | swing speed |
|---|---|
| M1, flourish, aerial | **sim** |
| heavy | não |
| uppercut | não — `Config.uppercut.speed`, fixo em 0.9 |
| locomoção, block, parry, crouch | não |

Arma pesada golpeia devagar, não anda devagar — por isso idle, walk, block, parry e
crouch podem ser autorados no ritmo que ficar certo, sem base nenhuma.

**O uppercut não obedece** (`Config.uppercut.speed = 0.9`, fixo). Arma lenta ainda
uppercuta rápido; quem paga por isso é o escalonamento de dano.

Duas contas dependem disso e quebram caladas se esquecidas:

- **`hitAt`** é lido na régua do editor a 1x, então o tell divide por `speed` — swing
  lento chega no marker mais tarde em segundos reais
- **`comboBuffer`** compara `Length - TimePosition`, que é tempo de *animação*; converter
  pra segundos reais é dividir por `speed` também

`CombatController` toca só para o dono — `Animator` replica pro resto de graça.

Prioridades, de baixo pra cima:

| | prioridade | |
|---|---|---|
| locomoção | `Action` | idle, walk, crouch |
| **block** | `Action2` | pose sustentada |
| reação | `Action3` | ParryStart, impacto, parried |
| **ataque** | `Action4` | topo |

Ataque nunca é sobreposto: o jogo é competitivo, e swing diluído no meio do frame é
swing que o oponente não lê com confiança. Reação nunca disputa com ataque porque tudo
que dispara uma já cancelou o ataque antes.

**Block tem prioridade própria, e isso não é detalhe.** Ele já compartilhou a do ataque,
e como é uma pose sustentada acabou engolindo o ParryStart e o impacto — justo as duas
animações que mais precisam ser vistas.

Nada disso dispensa calar a locomoção durante o golpe — prioridade só decide quem ganha
nas juntas que **ambas** animam.

Locomoção lê `Humanoid.MoveDirection`, não `Running`: é input, então não tem drift
residual pra comparar contra threshold.

Correr é `W` duplo, e **só acaba quando `MoveDirection` zera** — não ao soltar `W`.
Virar no meio da corrida solta a tecla por um instante, e cair pra caminhada ali é o
tipo de coisa que parece bug mesmo estando "correta".

O combo é M1 e **swing nunca é cortado**. Clique com um swing tocando não toca nada na
hora: se caiu na cauda (`comboBuffer`) fica agendado e dispara quando o atual termina,
se veio cedo demais é descartado. Isso é o que faz o encadeamento pedir timing em vez de
premiar spam. `comboReset` conta a partir do **fim** do último swing, não do início —
medir do início faria o próprio encadeamento parecer ociosidade e resetar o combo.

**Cada ataque tem o próprio cooldown e nenhum encosta no outro** — heavy não esfria o
M1, endlag não esfria o aerial, aerial não esfria o heavy. `chainReadyAt`,
`heavyReadyAt` e `aerialReadyAt` existem separados porque uma variável só compartilhada
era exatamente o que fazia um vazar no outro.

**M1 no ar toca o Aerial enquanto ele estiver disponível; com ele em cooldown, cai na
corrente normal.** O aerial tem prioridade, não exclusividade — não fazer nada ali lê
como input engolido.

### Crouch e Uppercut

`Ctrl` alterna crouch. Ele escreve o atributo `Crouching` no **character**, não no
Player: NPC e outros clients precisam ler isso sem remote.

Crouch anda a `crouch.speed`, **cancela corrida** e impede iniciar uma — senão viraria
toggle de velocidade grátis em vez de troca. As animações de crouch são universais e
substituem o par da classe inteiro, porque agachar é postura e não jeito de segurar arma.

`crouch.stealth` multiplica a distância em que um NPC te registra. É o alicerce do
backstab.

**Agachado, M1 e M2 respondem os dois com o Uppercut**, nunca um swing — postura
deliberada ganha da ordem da corrente, e pedir o golpe com qualquer botão é melhor que
lembrar qual. `M2` só não vira uppercut quando há dash rolando: ali cancelar tem
prioridade, porque a janela de cancel é curta e a de agachar não é.

Dar o golpe **desagacha**: ele nasce subindo, e deixar a postura agachada faria uma pose
de crouch brigar com uma animação que se levanta. Hitbox `point` igual à do flourish, e
acertar **levanta os dois**: o prêmio é uma janela compartilhada no ar, não distância. O
`Launch` vai pros dois clients, cada um dono da própria física.

Duas impulsões distintas, e a diferença importa:

- **`lunge`** — no golpe, antes do contato. Só o atacante, porque ainda não acertou
  ninguém. É o que faz um golpe agachado ter alcance.
- **`carry`** — no lançamento. Vai pros **dois**, com o mesmo heading vindo do server,
  senão a vítima ficaria suspensa onde estava enquanto o atacante passa reto.

O lançamento tem duas fases porque um impulso único descreveria um arco e cairia de
volta — a suspensão *é* a mecânica:

1. **Subida** (`riseTime`) — constraint em `Vector`, com o carry
2. **Suspensão** (`hangTime`) — constraint em `Line` no eixo Y

O modo `Line` é o que permite **se mover no ar**: ele prende só a altura e deixa X e Z
com o Humanoid. `Vector` prende os três eixos e o jogador fica congelado, o que lê como
travamento. A `WalkSpeed` cai pra `airSpeed` durante a janela — pouca deriva, não zero.

**A suspensão persegue uma altura, não congela onde chegou.** O server calcula um `hangY`
único a partir do ponto de contato (`riseHeight` acima da média dos dois) e manda pros
dois lados; cada um corrige em `Heartbeat` com ganho e teto (`hangGain`,
`hangCorrection`).

Segurar `LineVelocity = 0` parece equivalente e não é: cada corpo sobe na **própria**
máquina, e latência, velocidade inicial e nível do chão diferem. Congelar deixava os dois
em alturas diferentes, e era exatamente isso que fazia o golpe seguinte passar por cima
ou por baixo.

Pelo mesmo motivo só `heading` e `hangY` cruzam a rede. Os tempos são o mesmo `Config`
dos dois lados — mandá-los junto só criaria uma chance de discordarem.

`ChangeState(Freefall)` nos dois lados: um Humanoid que se acha em pé puxa o corpo de
volta ao chão contra a força, e era isso que teleportava de volta.

**Durante o juggle o Aerial não existe** — M1 responde com a corrente normal. O uppercut
comprou uma janela pra combar, não uma plataforma pra mergulhar.

Quem leva toma `victimStun`, mais longo que o `hitstun` comum. Com só o hitstun padrão a
vítima responde com M1 no ar e apaga o prêmio inteiro — acertar um uppercut tem que
comprar um turno, não um empate.

**`WeaponService.silence(character, duration)` é o único jeito de atordoar alguém.**
Player vai pelo remote `Stagger`, corpo server-owned pelo atributo `StunnedUntil` — e
esquecer o segundo ramo falha **em silêncio**: o NPC simplesmente segue atacando. Isso
já aconteceu três vezes (knockback, launch, hitstun) antes de virar uma função só.

Mesma raiz de sempre: quem é dono do corpo é quem aplica.

Duas travas são globais de propósito:

- **`staggerUntil`** — levou parry **ou tomou hit limpo**. Corta o golpe em andamento e
  bloqueia ataque por `hitstun`. Sem isso, trocar M1 pra sempre é a jogada ótima e
  tomar dano não custa nada. Bloquear ou aparar **não** staggera: defender bem é o
  prêmio, não pode custar o turno.
- **`guardLockUntil`** — o stagger que tira **também a guarda**, e só ser aparado faz
  isso. Hitstun comum deixa aparar: quem tomou o hit perdeu o turno, não a leitura, e
  o parry é a saída. Sem os dois separados, `parriedLock` e `hitstun` teriam que
  concordar, e um deles ficaria errado.
- **`dashUntil`** — dash e ataque nunca coexistem. Não se ataca dashando (voadora em
  qualquer um, a qualquer hora) nem se dasha atacando (todo golpe ficaria seguro).

Dash tem **dois perfis**: `dash.ground` é uma arrancada curta pra abrir ou fechar
espaço, `dash.air` é uma planagem com mais sustentação e menos velocidade. Mesma tecla,
físicas diferentes, porque no ar e no chão ele resolve problemas diferentes.

A direção vem de `MoveDirection`, não de pra onde o corpo olha — é isso que deixa dashar
de lado ou pra trás sem virar antes. **Sem nenhuma tecla de movimento, o dash vai pra
trás**: `Q` parado é desengajar, ninguém aperta pra andar pra dentro do que está na
frente.

A animação sai da direção convertida pro **espaço do personagem**
(`VectorToObjectSpace`), então o clipe casa com pra onde o corpo realmente vai — não com
pra onde a câmera aponta.

### I-frames e cancelamento

Dash é invulnerável, mas **por um golpe só**: `dodgeUntil` é zerado no contato. Duração
que aguentasse uma rajada seria estritamente melhor que qualquer guarda.

`M2` durante o dash cancela: para a força, corta o clipe e toca `DashCancel`. Em troca,
os i-frames são estendidos (`cancelIframes`) — mesma ideia dos parry frames, gastar o
recurso compra uma leitura mais longa. **Continua sendo um golpe só.**

Cancelar também **devolve o dash**, uma vez por corrente. O dash pago pelo refund é
marcado (`fromRefund`) e cancelá-lo não devolve nada — sem isso,
cancel → dash → cancel seria mobilidade infinita sem nunca tocar no cooldown.

O server espelha esse refund, porque senão recusaria o segundo dash pelo próprio
cooldown e o jogador ficaria sem i-frames justamente na janela que acabou de comprar.

O server é dono da janela; o client só reporta que dashou, e o report obedece ao mesmo
`cooldown` que o client obedece — spammar o remote não compra mais invulnerabilidade do
que dashar de verdade.

`F` segurado durante um ataque **fica lembrado** (`guardHeld`) e a guarda sobe assim que
o golpe termina. Sem isso, aparar depois de atacar exigiria um clique frame-perfect na
virada — timing de execução, não de leitura, que é o oposto do que esse combate quer.

**Existem dois caminhos pro parry, e o segundo é uma mecânica:**

| | vem de | vale com F solto |
|---|---|---|
| `parryWindow` | ter apertado `F` há pouco | não |
| `parryFrames` | aparar, **ou soltar `F` ainda dentro da janela** | **sim** |

Todo parry paga o próximo, e soltar `F` antes de virar block também paga um. Duas
consequências, e as duas são o design:

- Um aperto bem colocado devolve uma sequência inteira de golpes
- Dá pra ver o golpe vindo, **dar um tap** em `F` e já atacar — sem segurar a guarda
  pela animação inteira nem esperar o golpe passar

Soltar depois que a guarda virou block **não** paga nada: ali a leitura já falhou.

Três travas mantêm isso uma leitura e não um mash:

- **`parryWindow` menor que o windup.** Se a janela cobrisse `hitAt`, apertar `F` ao
  *ver* a animação começar já garantiria o parry, e a leitura não custaria nada. Ela
  precisa ficar bem abaixo do `hitAt` da classe.
- **`parryRearm`** — soltar e reapertar não reabre a janela. A guarda ainda bloqueia,
  só não fica armada (`parryArmed`). Sem isso, martelar `F` rendia mais que ler.
- **Frames não são concedidos em whiff.** Antes eram, e taps alternados produziam
  frames quase contínuos com a punição nunca alcançando.

É por isso que `resolveHit` avalia parry **antes** de olhar se há guarda — frames valem
com a tecla solta, então guarda não pode ser pré-requisito.

`play()` sempre para o track anterior, e reatribui `current` **antes** de parar: o
`Stopped` do antigo vê que já não é o atual e sai, em vez de limpar o estado que o novo
acabou de montar.

**`parried` na classe é a animação de quem APAROU** — a lâmina dele absorvendo o golpe,
não o recuo de quem foi aparado. Logo o lado sai da classe do **defensor** e o evento
(`ParryImpact`) vai pro client dele. Quem foi aparado recebe `Stagger` com
`parriedLock`: perde o turno, sem animação própria.

Ela toca **por cima** do block, sem derrubar a guarda nem tocar em `current` — ser
premiado por aparar não pode custar a postura de defesa.

Com `left` e `right` o server sorteia; com uma só usa aquela.

O último golpe da corrente não volta pro 1: fecha em **endlag**, uma janela sem input.
Fechar o combo custa alguma coisa, senão M1 em loop é a resposta ótima pra tudo.

Para autorar: o Motor6D da arma só existe em runtime, então monte a arma no rig à mão
antes de abrir o editor (`Part0 = RightPalm`, `Part1 = Handle`, `C0`/`C1` dos dois
`GripAttachment`). O que a animação grava é o nome de Part1.

Toda animação de ataque carrega dois **Animation Events**, `Start` e `End`, e são eles
que abrem e fecham a hitbox. A janela ativa é dado da animação, não número no código —
golpe que erra o timing se corrige no editor, nunca no controller.

Um terceiro evento é opcional: **`Tell`**, onde a lâmina acende avisando que apertar `F`
agora resulta em parry. O aviso precisa vir *antes* da hitbox abrir, porque a janela
conta do aperto do defensor.

Sem `Tell` autorado, o aviso sai de **`hitAt`** na classe: quantos segundos do início da
animação até o `Start`, lido na régua do editor. O tell dispara `parryWindow` antes
disso. Marker autorado sempre ganha do `hitAt`.

**Isso é dado, e tem que ser.** Três tentativas de inferir em runtime falharam e não
devem ser repetidas: track em `weight 0` **não dispara markers**, não existe API pra
perguntar a uma animação onde estão seus eventos, e aprender no primeiro golpe deixa
justamente esse golpe sem aviso. Um número por moveset resolve o que nenhuma inferência
resolveu.

### Dano

**O client detecta, o server decide.** Não é preferência: o server não tem a arma
montada nem a animação tocando, então não sabe onde a lâmina está. Fazer raycast lá
exigiria montar arma e animação no server e jogaria fora a decisão de nunca botar a arma
na rede.

`CombatController` abre a hitbox no `Start`, fecha no `End`, e reporta via
`Net "WeaponHit"`. Fecha também no `Stopped` do track — golpe cortado nunca chega no
`End` e deixaria a hitbox ligada.

#### Forma da hitbox

**A forma segue o que o golpe é**, e vem dos dados. `hitbox` ausente = lâmina.

| shape | usa | quem | por quê |
|---|---|---|---|
| *(ausente)* | `RaycastHitbox` nos `DmgPoint` | swings | lâmina fina varrendo arco largo |
| `point` | uma `GetPartBoundsInBox` | flourish | chute é contato num instante |
| `cast` | `Blockcast` | heavy | estocada é linha com espessura |
| `sweep` | `GetPartBoundsInBox` por frame | aerial | mergulho atropela quem está no caminho |

Raycast falharia no heavy porque a lâmina avança **na direção do próprio comprimento**:
os segmentos entre frames se sobrepõem ao que ela já ocupa, e o alcance fica preso ao
tamanho da mesh. Com `cast`, `range` é um número. `Blockcast` para no primeiro alvo, o
que é o certo pra estocada — perfura um, e parede continua bloqueando.

**`cast` faz overlap antes do Blockcast, e isso não é redundância.** Shapecast que
começa já sobreposto com o alvo retorna `nil` — então sem o teste de overlap o heavy
erra justamente quando o inimigo está colado, que é quando ele deveria acertar mais.

**Classe define a forma, arma escala.** `reach` na entrada de `byId` multiplica `size`,
`offset` e `range` de heavy e aerial, resolvido uma vez por golpe. É o que deixa katana e
espada curta compartilharem `OneHandMedium` com alcances diferentes. Não toca no
flourish: chute não fica mais longo por causa da arma.

`HitStop` limpava a hit list da lib e dava um hit por alvo por golpe de graça. As formas
próprias mantêm `shapeHits`, zerada quando a janela abre.

#### Debug

`Config.debugHitbox` liga tudo: raios da lib e caixas. O atributo `DebugHitbox` no
Workspace sobrepõe em runtime, sem rebuild. `sweep` mantém **um** adornment seguindo o
jogador, não um por frame.

Ataque que termina sem a hitbox ter aberto emite warn nomeando o `Start` — quase sempre
é o Animation Event que não foi autorado naquela animação, e sem esse aviso não se
distingue de hitbox que abriu e errou.

Golpe **cancelado** não emite esse warn (`cancelled`): interrompido, ele legitimamente
nunca chega no marker, e avisar ali afogaria o caso real em ruído de stagger.

`WeaponService` não confia no report, só verifica que o atacante **poderia** tê-lo feito:
arma equipada de verdade, os dois vivos, alvo ≠ atacante, distância dentro de
`maxHitDistance` e cooldown por par atacante/alvo. Só então `TakeDamage`. O cooldown é
por par, não por jogador, senão acerto em dois alvos no mesmo golpe viraria um só.

Dano mora na classe, junto das animações.

#### Knockback

Golpe sem chave `knockback` não empurra — mesma regra do resto do arquivo.

O server decide e manda o **client do alvo** aplicar: aquele client tem network
ownership do próprio character, então empurrão aplicado no server é desfeito no passo de
simulação seguinte.

E no client é **força sustentada** (`LinearVelocity`, o mesmo constraint do dash do
aerial), nunca uma escrita em `AssemblyLinearVelocity`. Um `Humanoid` reescreve a
própria velocidade horizontal a cada passo, então escrita única evapora antes do frame
seguinte — era exatamente por isso que o empurrão não acontecia.

### VFX e SFX

`data/shared/Fx.luau` mapeia evento → som e partícula. `FxController` toca, e **nada
ali é autoritativo**: só reproduz o que o server já decidiu.

Assets vivem no place file: `ReplicatedStorage/SFX/<Nome>` (Sound) e
`ReplicatedStorage/VFX/<Nome>` (Part → Attachment → ParticleEmitter). O emitter pode
carregar um atributo `EmitCount`; sem ele vale o default do Config.

Som posicional nasce num `Attachment` no Terrain, não numa Part — um ponto no mundo é
tudo que ele precisa, e Part traria física pra engine resolver à toa.

VFX clona **só o Attachment**, nunca a Part: a Part do template é alça de Studio e no
mundo viraria um bloco flutuante. Cada emitter leva `Enabled = false` antes do `Emit` —
deixar ligado transforma o burst em stream contínuo enquanto a âncora viver. O tempo de
vida sai do `Lifetime.Max` da partícula mais lenta, não de uma constante chutada.

**Resultado de golpe é broadcast do server** (`hit`, `blocked`, `parry`, `guardBreak`),
porque só ele sabe se o ataque conectou, foi bloqueado ou aparado — client nenhum
adivinha isso.

**Som de swing é a exceção**: o dono toca local (latência zero) e o server ecoa só pros
outros via `Swung`. É o único Fx que um client pode pedir, então o conjunto é fechado
(`Config.swingFx`) e tem rate limit.

Lista de som sorteia entre variantes, senão golpe repetido vira metrônomo.

#### Como declarar um efeito

Tudo em `data/shared/Fx.luau`, chaveado pelo **nome do evento** (`swing`, `heavy`,
`aerial`, `flourish`, `dash`, `hit`, `blocked`, `parry`, `guardBreak`).

```lua
sound = { heavy = { "HeavySwing1" } },              -- sorteia da lista

effect = {
    parry = "ParryEffect",                                        -- no ponto do evento
    heavy = { name = "WindBurst", offset = Vector3.new(0,-3,0) }, -- deslocado, espaço local
    hit   = { name = "Sparks", on = "blade" },                    -- nos DmgPoint da arma
},

highlight = { heavy = { color = ..., duration = 0.35 } },
```

**`on`** escolhe a origem: `"blade"` emite em **todo** `DmgPoint` do subject, `"tip"` só
no mais distante do root da arma. Ponta é geometria, não pose — continua sendo a ponta
qualquer que seja o movimento no instante. Use `offset` quando o efeito pertence ao
corpo (pé, mão, costas) e não ao fio.

Efeito preso à lâmina clona **os ParticleEmitters** dentro do `DmgPoint`, nunca o
Attachment do template: Attachment não pode ser filho de Attachment. Efeito no mundo é o
contrário — clona o Attachment inteiro no Terrain, que é BasePart e aceita.

**`mode` decide se o efeito é evento ou estado**, e a diferença não é cosmética:

| mode | o quê | pra quê |
|---|---|---|
| `burst` *(default)* | um `Emit`, partículas voam livres | impacto — aconteceu e acabou |
| `sustain` | `Enabled` por `duration` | aviso, estado, aura |

**Partícula emitida não acompanha o emitter.** Ela é independente no instante em que
existe. Então efeito que precisa *seguir* a lâmina tem que ser `sustain`: o que segue
não são as partículas, é o nascimento delas, que continua acontecendo onde a ponta
estiver. Nenhum ajuste de parenting substitui isso.

Texturas e sons são pré-carregados no boot por **string de conteúdo**, não pela pasta:
`PreloadAsync` não resolve a `Texture` de um `ParticleEmitter` a partir do container.
Sem isso o primeiro burst dispara o carregamento e não desenha nada — o sintoma é "o
primeiro combo não mostra VFX nenhum".

Asset no place file: `ReplicatedStorage/VFX/<Nome>` como Part → Attachment →
ParticleEmitter. Só o Attachment é clonado.

**Highlight é telegraph**: dispara no primeiro frame do windup, não quando a hitbox
abre. Tell que chega junto com a lâmina não é tell. Branco para todos, estilo Sekiro —
a leitura tem que ser instantânea e igual em todo golpe, nunca confundida com cor de
elemento ou status.

### NPC de combate

Tag `CombatNpc` num rig → ele se arma e ataca quem chegar perto.
`Services/NpcCombatService.luau`.

**A arma do NPC é montada no server**, ao contrário da do player. É a exceção
consciente à regra "a arma nunca cruza a rede": generalizar o caminho de mount do
client sobre holders que não são `Player` custaria refactor em três arquivos, e um
punhado de dummies não paga isso. Muitos NPCs mudam essa conta.

O NPC não precisa de raycast na lâmina: o server é dono do rig, então sabe pra onde ele
olha. Uma `GetPartBoundsInBox` à frente no marker `Start` basta.

Dois cuidados de física, os dois já custaram bug:

- **Escrever `CFrame` numa assembly solta zera a velocidade dela.** O loop de mira do
  NPC faz isso pra encarar o alvo, então ele salva e restaura `AssemblyLinearVelocity`
  em volta da escrita. Sem isso, knockback e launch morriam no tick seguinte e o corpo
  voltava pro chão.
- **`SetNetworkOwner(nil)`** fixa a simulação no server. A Roblox entrega assembly solta
  ao client mais próximo por conta própria, e aí força aplicada no server briga com a
  simulação daquele client.

`WeaponService.resolveHit` existe **porque** o NPC precisa passar exatamente pelas
mesmas regras de parry e block que um golpe de player. `attacker` nil significa que
ninguém é dono do golpe — por isso NPC não ganha nem sofre postura.

NPC aparado perde o turno igual a um player (`parriedLock`), mas não toca animação de
impacto: aquela animação é de quem **aparou**, e o NPC não apara.

### Hotbar

`HotbarUI.Holder` no StarterGui, montada à mão: 10 `ImageButton` de nome `1`..`9`, `0` —
**nome do botão é a tecla**, na ordem física do teclado, não na ordem do grid.

Cada botão tem `Stroke` (ImageLabel) e, **dentro dele**, `CellNum` (serial fixo, **nunca
escreva nele**) e `ContentName`, que o `HotbarController` preenche com o `label` do item.
O controller acha o `ContentName` por busca recursiva de propósito: ele já mudou de
lugar uma vez, e o nome é estável enquanto a hierarquia não é.

O controller também escreve o `LayoutOrder` de cada botão e força
`SortOrder = LayoutOrder` no grid. Sem isso os dez empatam em `0` e o grid cai na ordem
dos filhos, que **difere entre edit mode e runtime** — o `0` pulava pra frente do `1` no
Play. Não ordene a hotbar arrastando no Explorer; não sobrevive à replicação.

A hotbar é um atributo por slot: `Slot1`..`Slot9`, `Slot0`, valor = **id de item**
(string), não id de arma. Slot sem atributo é slot vazio. A UI decide quantos slots
existem — o controller varre os filhos do `Holder`, não uma lista no código.

Tecla ou clique no slot já equipado **desequipa**, e o item **fica no slot**: desequipar
é estado da arma, não da hotbar.

### Slot vazio

Slot sem item some com o inventário fechado e reaparece como `SimpleFrameredWindow`
quando ele abre — só existe enquanto há o que soltar dentro. O placeholder é um clone do
componente, parenteado no próprio botão e criado uma vez no `Start`.

Slot vazio fica `Visible = false`, e é justamente disso que sai a centralização:
`UIGridLayout` pula filho invisível, então a fileira fecha o buraco e o controller força
`HorizontalAlignment = Center` pra sobra reencontrar o meio. Um jogador com 1 e 8 vê dois
slots juntos e centrados.

**Isso não move a tecla.** O slot é o **nome do botão**, não a posição no grid — o 8
responde ao `8` onde quer que ele caia na tela.

A transparência do botão é assunto separado do `Visible`: com o inventário aberto o slot
vazio precisa existir na fileira, mas quem aparece é o placeholder. Então o `Stroke` sai
e as transparências vão a 1, voltando ao valor **autorado** quando o slot enche.

Quem manda nisso é `Framework/State`, chave `Items.openState`: o `InventoryController`
escreve no `setOpen`, o `HotbarController` observa. É o caso raro que justifica o State —
dois controllers do mesmo lado, sem nada pra replicar.

## Inventário

`data/shared/Items/` é o catálogo, **um módulo por categoria**. O `init.luau` varre os
próprios filhos e carimba `id` e `category` em cada entrada, então categoria nunca é
escrita à mão e um arquivo só cresce com a sua categoria.

```lua
-- Items/Weapons.luau
sword = { label = "Espada", weapon = 1 },
```

`weapon` indexa `Weapons.byId`. **Sem `weapon` o item não é equipável** — mesma regra do
resto do projeto: a chave ausente *é* a regra.

Id de item é **string**, não índice. Índice numérico repartido em nove arquivos quebra na
primeira vez que um deles é reordenado.

`InventoryService` é o dono. Posse e hotbar são coisas separadas no perfil:

| | onde | o quê |
|---|---|---|
| posse | `lineage.Inventory` | id → quantidade |
| hotbar | `lineage.Equipment` | slot → id |
| na mão | `lineage.Held` | id, ou `""` |

Os três persistem por ProfileStore. A hotbar replica por atributo como sempre; a posse
não cabe num atributo e vai por `Net "InventorySync"`, que o client também pede no
próprio `Start` (`InventoryRequest`).

**Carregar não é empunhar.** Clicar no item o põe na mão como objeto — o modelo monta,
mas não há classe de combate, animação nem golpe. O primeiro **M1 saca**, e é ele que
escreve o atributo `Weapon`. Isso existe pra o item poder ser dropado antes de virar arma.

Esse M1 **não golpeia**: as tracks ainda estão carregando, e `LoadAnimation` não é
instantâneo — um swing pedido no mesmo frame sairia mudo, que lê como input engolido.

Quem monta o modelo é o atributo `Held` (id de item), não `Weapon`. São dois estados
distintos e é por isso que são dois atributos:

| | `Held` | `Weapon` |
|---|---|---|
| escrito por | equipar | primeiro M1 (`UseHeld`) |
| efeito | modelo na mão | classe, animações, hitbox |

**Estar na mão e estar na hotbar são coisas diferentes.** Equipar escreve `Held` e
**nunca toca no `Equipment`** — reservar slot no equip foi o que fez uma espada só
aparecer como duas.

O item ganha o slot **usando**, não equipando: o `CombatController` dispara `UseHeld` no
primeiro frame de todo ataque e o server grava o que está na mão no **último slot que
aquele item ocupou** (`lineage.LastSlot`), ou no primeiro livre se ele nunca teve um.
Já slotado, o remote não faz nada — por isso ele não é throttled.

Isso vale pra qualquer ataque, não só M1: heavy, aerial e uppercut também são uso.

Arrasto (`SetSlot`) continua sendo o jeito de escolher o slot à mão, e é ele que
alimenta o `LastSlot`.

**Item que está num slot some do grid.** O `InventoryController` monta o conjunto de ids
slotados a partir dos atributos e pula esses no `rebuild`; listar nos dois lugares lê
como duplicata, não como atalho.

O que estava na mão volta com o corpo: no spawn o server reequipa `Held`. O atributo
`Weapon` não sobrevive ao rejoin — o perfil sim.

`WeaponService.equip` é server-only agora — **não existe mais o remote `EquipWeapon`**.
Todo equip entra por `EquipItem`, que confere posse antes. O grant de teste da Sword
mudou de `WeaponService` para `InventoryService.STARTER_ITEM`.

### UI do inventário

`Inventory` (ScreenGui) é montada à mão no Studio, e o `InventoryController` só a
preenche — nunca cria hierarquia:

```
Inventory (ScreenGui)
└── Background
    ├── Stroke
    └── Container (ScrollingFrame)
        └── <Categoria>            <-- nome = nome do módulo em Data/Items
            ├── Frame              <-- os cells, UIListLayout
            └── Category
                ├── Bar
                ├── Name
                └── Quantity       <-- o controller escreve a contagem
```

**A UI decide quais categorias existem**: o controller varre os filhos do `Container`, e
categoria sem módulo correspondente emite warn em vez de sumir calada.

O cell sai de `ReplicatedStorage.Components.CellButton`, clonado por item, e é montado
igual ao botão da hotbar — `CellButton > Stroke > ContentName`. Por isso os dois
controllers acham o label por busca recursiva pelo nome, não por caminho.

`Tab` abre e esconde o `Stats`. O `Enabled` é **forçado `false` no Start** porque o painel
é autorado aberto no Studio. A Ficha saiu do `Tab` e foi pro `P`.

Duas coisas medidas sobre o `Tab`, e as duas custaram uma rodada de Studio:

- **`Tab` é o atalho da PlayerList.** O CoreGui o consome acima de qualquer binding do
  jogo, então `UserInputService` só o via como `gameProcessed`. Hotkey de CoreGui não se
  rebinda: `SetCoreGuiEnabled(PlayerList, false)` é o único jeito, e o preço é não haver
  lista de jogadores até existir uma nossa. O Backpack sai junto, por outro motivo — o
  nosso o substitui.
- O bind é `ContextActionService`, não `UserInputService`, e devolve `Sink`. Com um
  `GetFocusedTextBox()` na frente, senão `Tab` sinkado globalmente rouba a tecla de
  qualquer campo de texto.

Clique equipa; arrastar até um botão da hotbar chama `SetSlot`. O cell **não usa
`Activated`**: um clique que virou arrasto não pode também equipar, então press e release
são tratados à mão, com `DRAG_THRESHOLD` decidindo qual dos dois foi.

**O arrasto vai nos dois sentidos**, e é o `slot` do drag que os distingue:

| origem | soltou onde | o quê |
|---|---|---|
| grid | botão da hotbar | `SetSlot(slot, id)` |
| hotbar | sobre o painel aberto | `SetSlot(slot)` — volta pro grid |
| hotbar | outro botão da hotbar | `SetSlot(alvo, id)` |
| qualquer | fora dos dois | nada |

Botão da hotbar também é arrastável, mas **clique nele continua sendo o toggle do
`HotbarController`** — o `InventoryController` só equipa no clique quando o arrasto
nasceu no grid, senão os dois responderiam o mesmo clique.

Arrastar de slot pra slot funciona hoje porque `setSlot` tira a arma do slot anterior.
Item **não-arma** ainda não existe, e quando existir esse caminho precisa mandar a origem
junto — do contrário ele duplica.

O fantasma do arrasto vive num ScreenGui próprio com `IgnoreGuiInset = true`, porque ele
segue `GetMouseLocation()` cru. O acerto do alvo é o contrário: `GetGuiObjectsAtPosition`
fala em espaço **sem** o inset, então ali o `GetGuiInset()` é subtraído.

## Estrutura

```
data/
├── shared/           <-- ReplicatedStorage.Data (Movement, Weapons, Progression, Fx)
│   └── Items/        <-- catálogo, um módulo por categoria
└── server/           <-- ServerStorage.Data (vazio)
src/
├── ReplicatedFirst/Loading.client.luau
├── ReplicatedStorage/
│   ├── RaycastHitbox/     <-- vendorizado, terceiro, não lintar
│   ├── Shared/
│   │   ├── Framework/     <-- Loader, Net, Signal, State, Tags
│   │   └── UI/Common/     <-- kit reutilizável, barrel em init.luau
│   └── Stories/           <-- UI Labs (*.story.luau)
├── ServerStorage/Animate.client.luau     <-- morto, tudo comentado
├── ServerScriptService/
│   ├── Bootstrap.server.luau
│   └── Services/          <-- WeaponService.luau; *Service.luau
├── StarterCharacterScripts/Animate.client.luau
└── StarterPlayerScripts/
    ├── Bootstrap.client.luau
    └── Controllers/       <-- Movement, SmartBone, Weapon, Hotbar, Inventory, Combat
```

Padrão canônico pra copiar: `UI/Common/Button.luau` (componente Vide) ou
`Framework/Tags.luau` (módulo).

## UI

Estilo **AAA indie**: paleta monocromática, um accent, traço de 1px, tipografia Gotham
bold. Nada de cartoon-simulator genérico.

`UI/Common/Theme.luau` é a fonte única de cor, fonte, tamanho, raio e espaçamento, e é
`table.freeze`d. **`Color3.fromRGB(...)` dentro de componente é bug** — falta token,
adicione ao Theme.

Componente é **controlado**: `value: () -> T` mais `on<Ação>: (T) -> ()`, sem estado
interno. Existem hoje: Button, CloseButton, Window, Checkbox, TextInput, ModelViewport,
AutoScale, HitCircle.

**Nem toda UI é Vide.** Hotbar e barras de vida/postura são montadas à mão no Studio e
dirigidas por Controller que lê a hierarquia pronta — vivem no place file, não no Rojo,
e não devem ser reconstruídas em Vide sem pedir.

Telas de progressão são Vide, montadas em `Vide.root` dentro do Controller:
`CreationController` (criação), `SanctuaryController` (compra), `SheetController` (`P`).
São **MVP** — funcionais, não finalizadas.

`useAttribute(instance, name, default)` liga atributo replicado a uma source Vide. Como
toda a progressão replica por atributo, é o único elo que essas telas precisam.

Nenhuma delas lê `Lives` sem antes checar `ProfileLoaded`: os defaults de um perfil que
ainda não chegou são indistinguíveis dos de quem não tem linhagem, e sem essa checagem a
tela de criação pisca na cara de quem só reconectou.

## Estado

| Mecanismo | Pra quê |
|---|---|
| `player:SetAttribute(...)` | replicação server→client, alcança late joiner |
| `Vide.source()` | UI local reativa em Controllers |
| `Framework/State` | key-value entre módulos do mesmo lado (raro) |

Persistência entre sessões: `DataService`, por ProfileStore. Só o que está no perfil
sobrevive ao rejoin — atributo de Player é canal de replicação, não armazenamento.

## Convenções

- `--!strict` em arquivo novo sempre que der
- Comentário **em inglês**, **máximo ~10 palavras**, uma linha, e só onde o porquê não
  se lê no código. Bloco de 3+ linhas explicando mecanismo é ruído — a explicação longa
  vai na resposta do chat, não no arquivo. Zero comentário é resultado aceitável.
- **Module-level state** (`local active`), não OOP self-heavy
- Naming: módulos/Services/Controllers e lifecycle (`Init`, `Start`) em PascalCase;
  helpers públicos com `.` em camelCase (`Service.addCoins(player, n)`); locais em
  camelCase; constantes module-level em UPPER_SNAKE
- Vide: `create "Frame" { ... }` sem parênteses, eventos direto nas props

## Armadilha: StyLua quebra Vide

`stylua.toml` tem `call_parentheses = "Always"`. Rodar StyLua num arquivo Vide reescreve
`create "TextButton" { ... }` como `create("TextButton")({ ... })`.

**Não rode StyLua em arquivo de UI** até isso estar resolvido no `stylua.toml`.

## Regras absolutas

- **Todo texto que o jogador lê é em inglês** — UI, nome de item, `label`, mensagem de
  erro, `Kick`. Só a conversa com o Cosmo é em PT-BR; o jogo, nunca
- Nunca Roact — sempre Vide
- Nunca `Color3` hardcoded em componente — sempre `Theme`
- Nunca RemoteEvent direto — sempre via `Net`
- Nunca `wait()` — sempre `task.wait()`
- Nunca resolver junta do rig por nome — resolva pela parte que ela move
- Lint e format só nos arquivos que você alterou, nunca na árvore inteira

## Como me ajudar

Cosmo é programador profissional e entende os sistemas que pede. Ele delega execução,
não compreensão — não explique o básico e não escreva aula em comentário.

- Pediu algo que viola as regras acima: avise **antes** de fazer
- Decisão de arquitetura ambígua: pergunte, não escolha por ele
- Dependência nova: pergunte
- Antes de apagar ou sobrescrever, olhe o que está lá
- Escopo é o que ele pediu. Achou problema fora, avise em uma linha e siga
- Não diga que funciona sem ter rodado. Se depende de olho no Studio, diga isso
- Referência aqui aponta pra arquivo que existe. Achou quebrada, **corrija este
  documento** em vez de contornar no código

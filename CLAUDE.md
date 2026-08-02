# pf

RAGDOLL TACTICS Roblox solo. Hoje é **base técnica**: Framework, UI kit e sistema de
movimentação prontos, sem gameplay. A identidade do jogo ainda não foi definida — não
assuma um gênero.

## Autor

Cosmo (Diogo Boeno Pereira) — dev solo brasileiro.
Conversa em **PT-BR**. **Comentários de código em inglês.**
Respostas diretas, sem preâmbulo, sem explicar o óbvio.

## Stack

| Camada | Ferramenta |
|---|---|
| Build | Rojo 7.7 (`default.project.json`) |
| Deps | Wally 0.3.2 — apenas `vide@0.4.0` e `ui-labs@2.4.2` |
| Tooling | Aftman 0.3 pina rojo / wally / selene / stylua |
| UI | Vide (reativo, inspirado em Solid.js) — **nunca Roact** |
| UI dev | UI Labs, stories em `ReplicatedStorage/Stories/` |
| IDE | Antigravity (fork do VS Code) |

Não há ProfileService, DataStore nem qualquer camada de persistência ainda.
Se precisar, é decisão de arquitetura — **pergunte antes de introduzir**.

## Comandos

Aftman gerencia os binários; versões pinadas em `aftman.toml`.
**Não existe test runner.** "Testar" = lint limpo + format + `rojo build` compila.

```powershell
aftman install   # instala tooling pinado
wally install    # baixa vide + ui-labs em Packages/ (obrigatório antes do build)

rojo serve       # dev: serve pro plugin Rojo no Studio

# passe arquivos/pastas alterados, nunca src/ inteiro
stylua src/path/File.luau
selene src/path/File.luau

# sanity check: compila num .rbxlx temporário, não abre o Studio
rojo build default.project.json -o "$env:TEMP/project_test.rbxlx"
```

Stories de UI Labs rodam dentro do Studio via plugin — não há CLI pra elas.

Lógica pura que dá pra afirmar é afirmada **dentro do jogo**: `Movement/Assert.luau` roda
no boot em Studio e emite `warn` no que falhar. Compilar não é rodar — o que depende de
olho (feel, visual) continua sendo checklist manual.

## Framework

`src/ReplicatedStorage/Shared/Framework/` — cinco módulos, sem dependências externas:

- **Loader** — `LoadDescendants(folder)` + `Start()`. Roda todo `Init()` em
  sequência, depois cada `Start()` em `task.spawn`. Ambos opcionais e protegidos
  por pcall: módulo que falha só emite `warn`, não derruba o boot.
- **Net** — `Ensure`, `FireClient`, `FireAllClients`, `FireServer`, `On`.
  Camada única sobre RemoteEvent; pré-cria remotes pra evitar `WaitForChild` infinito.
- **Signal** — `new`, `Connect`, `Once`, `Fire`, `Wait`, `Destroy`.
- **State** — key-value global com signal por chave (`Set`, `Get`, `Update`,
  `OnChange`, `Observe`). Fallback global; use com parcimônia.
- **Tags** — `Tags.bind(tag, handler)` sobre CollectionService. Handler roda pras
  instâncias já marcadas e pras futuras, com cleanup no untag/destroy. Retorna
  unbind. Mantém objetos de mundo declarativos.

Entry points: `ServerScriptService/Bootstrap.server.luau` carrega `Services/`;
`StarterPlayerScripts/Bootstrap.client.luau` carrega `Controllers/`.
Registrar módulo novo = retornar uma table (com `Init`/`Start` opcionais) na pasta
certa. É auto-descoberto, sem require manual.

## Movimentação

`src/ReplicatedStorage/Shared/Movement/` — animação **100% procedural** de R6. Sem
keyframe, sem asset ID, sem Animator: tudo é `Motor6D.C0` calculado por frame.

**Exige R6.** O padrão da Roblox é R15, e aí o sistema inteiro não roda. É configuração de
jogo, não de código: `Game Settings > Avatar > Avatar Type = R6`. Fora do R6 o controller
emite warn uma vez e desliga.
`StarterCharacterScripts/Animate.client.luau` fica **vazio de propósito** pra suprimir o
`Animate` que a Roblox injeta — apagar aquele arquivo traz as animações default de volta
pra brigar pelas mesmas juntas.

Cinco camadas puras que escrevem num pose buffer compartilhado, aplicadas **nesta ordem** por
`Controllers/AnimationController.luau`:

- **Locomotion** — mapeia os sinais do `Gait` nas juntas do R6: curso do quadril, retração
  da perna no swing, queda pélvica, sway lateral, sobe-desce, rotação de pelve, mais pulo,
  queda e idle. A fase avança com **distância percorrida**, não com tempo, e é por isso que
  o pé não patina. O ciclo em si nunca passa por spring.
- **FootIK** — dois raycasts por personagem. R6 não tem joelho: a pelve desce até o pé mais
  baixo e a outra perna **retrai** até pousar, mais rotação parcial pela normal. Escala tudo
  pelo peso de apoio que o `Gait` fornece, senão briga com o pé que a marcha acabou de erguer.
- **Landing** — compressão do pouso, modelada como **impulso** numa spring, não como alvo.
  Baixa o root e **retrai as duas pernas na mesma medida**, senão os pés atravessam o chão.
- **Lean** — **só bank lateral**. Não existe inclinação pra frente/trás: a marcha já carrega
  o deslocamento de peso, e empilhar pitch em cima lê como o personagem caindo. Soma o strafe
  (velocidade linear) com a curva (velocidade angular) na mesma spring de roll.
- **HeadStabilizer** — roda por **último** porque **consome** o delta final do root em vez de
  somar nele. Contra-rotaciona o `Neck` pra cabeça não herdar o balanço do tronco (reflexo
  vestíbulo-ocular). Cancelamento exato, sem aproximação de ângulo pequeno. Sem estado e sem
  spring: spring aqui atrasaria justamente a oscilação que ela deveria remover.

**A ordem não é estilo.** Delta compõe por multiplicação, então rotação aplicada antes de
translação gira a translação: quem translada o root (Locomotion, FootIK, Landing) vem antes
de quem o rotaciona (Lean), senão o drop vertical sai torto e o corpo desliza pro lado a cada
passo. `HeadStabilizer` fecha porque lê o resultado final em vez de contribuir. `Assert`
trava isso.

Peças de apoio: **Gait** (o ciclo de marcha humano como matemática pura — sem tipo Roblox,
sem junta, e é por isso que o `Assert` consegue testar), **Rig** (único que conhece
`Motor6D`; decompõe `C0` em posição × rotação pra que X seja sempre pitch), **Spring** (toda
camada escreve *alvo*, nunca ângulo final — é o que elimina máquina de estados), **Config**
(congelado), **Assert** (asserções de boot, só em Studio).

O ciclo é **60% apoio / 40% balanço**, não 50/50. Seno gasta metade em cada lado, e a perna
real volta 1,5× mais rápido do que vai — é a maior causa isolada de "parece robô". Com as
pernas defasadas 50%, esse 60/40 produz de brinde os **20% de duplo apoio** que definem
andar em vez de correr. `Assert` verifica os dois, e que nunca existe frame sem pé no chão.

A elevação do pé é **arranque, não corcovado**: pico a 32% do balanço (≈73% do ciclo, onde
fica o pico de flexão do joelho), subindo 2,1× mais rápido do que desce. Seno cobrindo o
balanço inteiro erra duas vezes — pico no meio e subida tão lenta quanto a descida — e o
resultado lê como pêndulo em vez de passo.

Cada cliente anima **todos** os personagens que enxerga: `C0` escrito no cliente não
replica, e refazer a conta local sai de graça.

Os cinco `SIGN_*` do `Config` existem porque **o mesmo sinal move coisas opostas**: delta
age no frame do pai, então um pitch positivo joga um membro pendurado pra frente e o torso
erguido pra trás. Os valores atuais são derivados da álgebra, não chutados, e `Assert`
tranca a convenção. Direção errada se resolve lá, nunca no meio da camada.

## Estrutura

```
src/
├── ReplicatedFirst/Loading.client.luau      <-- loading screen pré-tudo
├── ReplicatedStorage/
│   ├── Shared/
│   │   ├── Framework/     <-- Loader, Net, Signal, State, Tags
│   │   ├── Movement/      <-- animação procedural R6 (ver seção Movimentação)
│   │   └── UI/Common/     <-- kit reutilizável (barrel em init.luau)
│   └── Stories/           <-- UI Labs (*.story.luau), fora de Shared/
├── ServerStorage/                           <-- vazio
├── ServerScriptService/
│   ├── Bootstrap.server.luau
│   └── Services/          <-- vazio; *Service.luau
├── StarterCharacterScripts/
│   └── Animate.client.luau  <-- VAZIO DE PROPÓSITO: suprime o Animate da Roblox
└── StarterPlayerScripts/
    ├── Bootstrap.client.luau
    └── Controllers/       <-- AnimationController.luau; *Controller.luau
```

`Services/` e `Shared/Modules/` ainda não têm nada. Não há pasta `templates/`: pro padrão
canônico, copie `UI/Common/Button.luau` ou `Framework/Tags.luau`.

## Convenções essenciais

- **Comentários em inglês**, explicando o **porquê**, não o **o quê**
- `--!strict` em arquivo novo sempre que der
- Naming: módulos/Services/Controllers e lifecycle (`Init`, `Start`) em PascalCase;
  helpers públicos de API em **camelCase com `.`** (`Service.addCoins(player, n)`);
  locais em camelCase; constantes module-level em UPPER_SNAKE
- **Module-level state** (`local active`), não OOP self-heavy
- UI sempre Vide, sintaxe `create "Frame" { ... }` (sem parênteses)
- Eventos Vide direto nas props: `Activated = function() end`
- StyLua decide formatação — não brigue com ele

Detalhe: `docs/CONVENTIONS.md`

## Estado

| Mecanismo | Pra quê |
|---|---|
| `player:SetAttribute(...)` | replicação simples server→client |
| `Vide.source()` | UI local reativa em Controllers |
| `Framework/State` | key-value global entre módulos do mesmo lado (raro) |

Persistência entre sessões: **não implementada**.

## UI

Estilo **AAA indie**: paleta monocromática, um único accent, traço de 1px,
tipografia Gotham bold. Nada de visual cartoon-simulator genérico.

`UI/Common/Theme.luau` é a **fonte única** de cor, fonte, tamanho, raio e espaçamento.
Ele é `table.freeze`d. **`Color3.fromRGB(...)` dentro de componente é bug.**

- Sistema visual: `docs/ui/DESIGN_SYSTEM.md`
- Como escrever componente: `docs/ui/COMPONENTS.md`

## Ambiente e custo de tokens

RTK, ccusage, regras de `permissions.deny` e plugins: `docs/TOOLING.md`.

Regra prática: `Packages/` e artefatos de build são ilegíveis por política —
não tente lê-los, a resposta é sempre negada.

## Regras absolutas

- Nunca Roact — sempre Vide
- Nunca `Color3` hardcoded em componente — sempre `Theme`
- Nunca número mágico em camada de movimento — sempre `Movement/Config`
- Nunca escrever `Motor6D` fora de `Movement/Rig`
- Nunca verde Roblox saturado (`#2ecc71`)
- Nunca RemoteEvent direto — sempre via `Net`
- Nunca `wait()` — sempre `task.wait()`
- Comentários em inglês

## Como me ajudar

- Se eu pedir algo que viola as regras acima, me avise **antes** de fazer
- Decisão de arquitetura ambígua: pergunte, não escolha por mim
- Não adicione dependência nova sem perguntar
- Referências neste arquivo apontam para arquivos que existem. Se você encontrar
  uma referência quebrada, corrija o documento em vez de contornar.

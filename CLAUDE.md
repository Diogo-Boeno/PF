# pf

Jogo Roblox solo do Cosmo. Nome de trabalho: **RAGDOLL TACTICS**.

Estado: **base técnica**. Existe framework, kit de UI, rig custom animado e equip de
armas. Não existe gameplay. O gênero não está fechado — **não assuma um**.

## Stack

| Camada | Ferramenta |
|---|---|
| Build | Rojo 7.7 (`default.project.json`) |
| Deps | Wally 0.3.2 |
| Tooling | Aftman 0.3 (`aftman.toml`) |
| Lint / format | selene 0.27, StyLua 0.20 |
| UI | Vide 0.4 — **nunca Roact** |
| UI dev | UI Labs 2.4, stories em `ReplicatedStorage/Stories/` |

**Só `vide` é usado hoje.** `ripple`, `charm`, `rng`, `quickzone` e `profilestore` estão
no `wally.toml` sem um único `require` em `src/`. `blink` e `asphalt` estão pinados no
Aftman e não têm arquivo de config no repo. Antes de usar qualquer um deles, pergunte —
estar instalado não é decisão tomada.

`profilestore` presente **não significa que há persistência**. Não há. Introduzir é
decisão de arquitetura.

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

### Hotbar

`HotbarUI.Holder` no StarterGui, montada à mão: 10 `ImageButton` de nome `1`..`9`, `0` —
**nome do botão é a tecla**, na ordem física do teclado, não na ordem do grid.

Cada botão tem `CellNum` (serial fixo, **nunca escreva nele**) e `ContentName`, que o
`HotbarController` preenche com o nome do model da arma.

O controller também escreve o `LayoutOrder` de cada botão e força
`SortOrder = LayoutOrder` no grid. Sem isso os dez empatam em `0` e o grid cai na ordem
dos filhos, que **difere entre edit mode e runtime** — o `0` pulava pra frente do `1` no
Play. Não ordene a hotbar arrastando no Explorer; não sobrevive à replicação.

O inventário é um atributo por slot: `Slot1`..`Slot9`, `Slot0`, valor = id do catálogo.
Slot sem atributo é slot vazio. A UI decide quantos slots existem — o controller varre
os filhos do `Holder`, não uma lista no código.

Tecla ou clique no slot já equipado **desequipa** (pede `unarmed`). O toggle é decidido
no client; o server valida igual, então id fora do catálogo também cai em desarmado.

`WeaponService` concede uma Sword no `Slot1` ao entrar. É **grant de teste**, marcado no
arquivo, some quando houver inventário de verdade.

## Estrutura

```
data/
├── shared/           <-- ReplicatedStorage.Data (Movement, Weapons)
└── server/           <-- ServerStorage.Data (vazio)
src/
├── ReplicatedFirst/Loading.client.luau
├── ReplicatedStorage/
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
    └── Controllers/       <-- Movement, SmartBone, Weapon; *Controller.luau
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

**Nem toda UI é Vide.** Vide é para o kit reutilizável em `UI/Common/`. Tela montada à
mão no Studio (hoje: `HotbarUI`) é dirigida por Controller que lê a hierarquia pronta —
não reconstrua em Vide sem pedir. Essa UI vive no place file, não no Rojo.

## Estado

| Mecanismo | Pra quê |
|---|---|
| `player:SetAttribute(...)` | replicação server→client, alcança late joiner |
| `Vide.source()` | UI local reativa em Controllers |
| `Framework/State` | key-value entre módulos do mesmo lado (raro) |

Persistência entre sessões: **não implementada**.

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

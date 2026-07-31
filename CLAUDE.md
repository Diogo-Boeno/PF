# pf

RAGDOLL TACTICS Roblox solo. Hoje é **base técnica**: Framework + UI kit prontos, sem
gameplay. A identidade do jogo ainda não foi definida — não assuma um gênero.

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

## Pendências conhecidas (2026-07-28)

Duas coisas estão quebradas no setup. Não tente contornar — corrija ou avise.

1. **`wally install` falha**: `wally.lock` é incompatível com o Wally 0.3.2
   (`data did not match any variant of untagged enum LockPackage`, linha 15).
   Sem isso não existe `Packages/`, e portanto **`rojo build` também falha**.
   Correção provável: apagar `wally.lock` e regerar com `wally install`.
2. **`stylua --check` acusa diff em todo arquivo**: `stylua.toml` pede
   `line_endings = "Unix"` mas os arquivos em disco são CRLF. Ou roda
   `stylua src/` uma vez pra normalizar tudo pra LF (diff grande, decisão do autor),
   ou muda o `.toml` pra `"Windows"`.

`selene src/` passa: 0 erros, 16 warnings.

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

## Estrutura

```
src/
├── ReplicatedFirst/Loading.client.luau      <-- loading screen pré-tudo
├── ReplicatedStorage/
│   ├── Shared/
│   │   ├── Framework/     <-- Loader, Net, Signal, State, Tags
│   │   └── UI/Common/     <-- kit reutilizável (barrel em init.luau)
│   └── Stories/           <-- UI Labs (*.story.luau), fora de Shared/
├── ServerStorage/                           <-- vazio
├── ServerScriptService/
│   ├── Bootstrap.server.luau
│   └── Services/          <-- vazio; *Service.luau
└── StarterPlayerScripts/
    ├── Bootstrap.client.luau
    └── Controllers/       <-- vazio; *Controller.luau
```

`Services/`, `Controllers/` e `Shared/Modules/` ainda não têm nada. Não há pasta
`templates/`: pro padrão canônico, copie `UI/Common/Button.luau` ou `Framework/Tags.luau`.

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

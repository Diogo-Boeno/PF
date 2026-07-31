# Conventions

Convenções de código do projeto. Os exemplos abaixo são **ilustrativos** —
`Services/` e `Controllers/` ainda estão vazios. Para padrão real em código,
leia `Framework/Tags.luau` e `UI/Common/Button.luau`.

## Idioma

- Conversa, docs e commits: **PT-BR**
- **Comentários e nomes de identificador no código: inglês**

Isso não é negociável e vale para arquivo novo e para edição de arquivo antigo.

## Naming

| Contexto | Style | Exemplo |
|---|---|---|
| Módulos / Services / Controllers | PascalCase | `PlayerDataService` |
| Type aliases | PascalCase | `Handler`, `Cleanup` |
| Lifecycle (`Init`, `Start`) | PascalCase, com `:` | `function Service:Start()` |
| Signals públicas | PascalCase | `Service.OnSomethingChanged` |
| Helpers públicos da API | **camelCase, com `.`** | `Service.addCoins(player, n)` |
| Variáveis e funções locais | camelCase | `handleCharacter`, `currentYaw` |
| Constantes module-level | UPPER_SNAKE | `AUTO_CLOSE_DISTANCE` |
| State module-level | camelCase | `local active`, `local activeDialog` |
| Eventos Net | PascalCase, sem domínio | `"BuyItem"`, `"ShopResult"` |
| Arquivos e pastas | PascalCase | `PlayerDataService.luau`, `Services/` |

A mistura de `:` e `.` é intencional: lifecycle usa `self`, helper de API não usa
porque o módulo é singleton.

## Comentários

Explicam o **porquê** ou contexto não-óbvio. Nunca reformulam o código em prosa.

```luau
-- Pre-creates remotes on the server so the client never hangs in an infinite
-- WaitForChild waiting for an outbound remote that only exists after FireClient.
function Net.Ensure(...) end
```

Header de arquivo é opcional; use em módulo complexo:

```luau
--!strict
-- Server-side authority for purchases: validates config, ownership and balance
-- before debiting currency. The client never decides anything here.
```

Marcadores:

```luau
-- TODO: description
-- DEBUG: temporary print, remove
```

## `--!strict`

Em arquivo novo, sempre que der. Em arquivo antigo sem strict, não force migração
em massa — converta conforme refatora.

## Estilo de módulo

**Module-level state, não OOP self-heavy.**

```luau
local MainMenuController = {}

-- internal module state
local active = false
local menuRig: Model? = nil

-- local helpers
local function setupRig() end

-- public API
function MainMenuController:Start() end
function MainMenuController:Close() end

return MainMenuController
```

Evite `__index` e `:new()` a menos que precise mesmo de múltiplas instâncias —
raro em Services/Controllers, que são singletons.

## Estrutura de um Service

```luau
--!strict
-- One or two lines on the module's role, when it isn't obvious.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage.Shared.Framework
local Signal = require(Framework.Signal)
local Net = require(Framework.Net)

-- constants
local SOMETHING_MAX = 100

local MyService = {}

-- public signals (PascalCase)
MyService.OnSomething = Signal.new()

-- local helpers (camelCase, outside the return table)
local function doInternalThing(player: Player) end

-- public API (camelCase, dot-called)
function MyService.addCoins(player: Player, amount: number) end

-- lifecycle (PascalCase, colon-called)
function MyService:Start()
	Net.On("MyEvent", function(player, payload) end)
end

return MyService
```

## Formatação

- Aspas duplas por padrão
- Indentação: tab (StyLua decide — `stylua.toml` manda)
- Não brigue com o StyLua; rode antes do selene

## Patterns recorrentes

### Player join cobrindo quem já estava no servidor

```luau
function MyService:Start()
	Players.PlayerAdded:Connect(handlePlayer)

	-- covers players already in the server before Start (script reload, hot reload)
	for _, player in Players:GetPlayers() do
		task.spawn(handlePlayer, player)
	end

	Players.PlayerRemoving:Connect(handlePlayerLeaving)
end
```

### Guard clauses

```luau
function MyService.addCoins(player: Player, amount: number)
	local data = MyService.get(player)
	if not data then
		return
	end

	data.Coins += amount
	player:SetAttribute("Coins", data.Coins)
end
```

### Resultado de volta pro cliente

```luau
Net.On("BuyItem", function(player, itemName)
	if not isValid(itemName) then
		Net.FireClient("ShopResult", player, false, "Invalid")
		return
	end
	Net.FireClient("ShopResult", player, true, "Bought")
end)
```

### Attributes para replicação simples

Prefira `SetAttribute` a criar um evento Net dedicado quando o dado é um valor
escalar que a UI precisa observar:

```luau
-- server
player:SetAttribute("Coins", 150)

-- client
player:GetAttributeChangedSignal("Coins"):Connect(function() end)
```

### Tipos opcionais

```luau
local menuRig: Model? = nil

local function findByName(name: string): Model?
	return workspace:FindFirstChild(name) :: Model?
end
```

### Binding declarativo por tag

Para comportamento preso a objeto de mundo, use `Framework/Tags` em vez de
procurar instância na mão:

```luau
local unbind = Tags.bind("Prompt", function(instance)
	local conn = instance.Triggered:Connect(onTrigger)
	return function()
		conn:Disconnect()
	end
end)
```

## Anti-patterns

- ❌ Comentário em português — o código é em inglês
- ❌ `wait()` — use `task.wait()`
- ❌ `Instance.new("RemoteEvent")` direto — sempre via `Net`
- ❌ Helper público de API em PascalCase — use `addCoins`, não `AddCoins`
- ❌ State em `self.x` num módulo singleton — use `local x` module-level
- ❌ Acessar workspace direto de um Controller de UI — passe via props ou attribute
- ❌ `Color3.fromRGB` em componente de UI — sempre `Theme`

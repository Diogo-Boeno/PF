# UI Components (Vide)

Como componentes Vide são escritos neste projeto. O padrão canônico é
`src/ReplicatedStorage/Shared/UI/Common/Button.luau` — quando em dúvida, copie ele.

## Kit atual

Barrel em `UI/Common/init.luau`. Um require entrega o conjunto inteiro:

```luau
local UI = require(ReplicatedStorage.Shared.UI.Common)
UI.Button { ... }
```

| Componente | Papel |
|---|---|
| `Theme` | tokens de cor, fonte, tamanho, raio, espaçamento (fonte única) |
| `Button` | botão padrão do design system |
| `CloseButton` | fechar de janela/modal |
| `Window` | container de painel/modal |
| `Checkbox` | toggle booleano |
| `TextInput` | campo de texto |
| `ModelViewport` | preview 3D de Model em ViewportFrame |
| `AutoScale` | adaptação de resolução |
| `HitCircle` | alvo de timing; exporta `Judgement` e `HitResult` |

Próxima leva prevista no barrel: `Slider`, `Dropdown`, `ProgressBar`, `Tooltip`.

Os tipos de props são exportados pelo barrel (`UI.ButtonProps` etc.). **Não
duplique tabela de props nesta doc** — leia o `export type` no arquivo do
componente, que é onde a verdade vive.

## Imports padrão

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)

local create = Vide.create
local indexes = Vide.indexes
```

## Tipo `Reactive<T>`

Props que aceitam valor estático **ou** source:

```luau
type Reactive<T> = T | () -> T
```

Cada componente declara isso no topo se precisar.

## Estrutura básica

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source

type Reactive<T> = T | () -> T

export type MyComponentProps = {
	label: Reactive<string>,
	onClick: () -> (),
	parent: Instance?,
}

local function MyComponent(props: MyComponentProps)
	local isHovered = source(false)

	return create "TextButton" {
		Size = UDim2.new(0, 152, 0, 36),
		BackgroundColor3 = function()
			return if isHovered() then Theme.color.surfaceHover else Theme.color.surface
		end,
		Text = props.label,
		TextColor3 = Theme.color.textPrimary,
		TextSize = Theme.textSize.md,
		FontFace = Theme.font.strong,
		AutoButtonColor = false,
		Parent = props.parent,

		Activated = function()
			props.onClick()
		end,
		MouseEnter = function()
			isHovered(true)
		end,
		MouseLeave = function()
			isHovered(false)
		end,

		create "UICorner" { CornerRadius = Theme.radius.md },
		create "UIStroke" {
			Color = Theme.color.stroke,
			Thickness = Theme.strokeThickness,
		},
	}
end

return MyComponent
```

Repare: **nenhum `Color3.fromRGB` e nenhum número mágico**. Tudo vem de `Theme`.
`AutoButtonColor = false` porque o hover é controlado pelos tokens, não pelo
tint automático da Roblox.

## Sintaxe `create "ClassName" { ... }`

Call-as-string, **sem parênteses**:

```luau
create "Frame" { Size = UDim2.new(...) }        -- estilo do projeto
create("Frame")({ Size = ... })                 -- válido, mas inconsistente
```

## Events

Direto no objeto de props, sem wrapper:

```luau
create "TextButton" {
	Activated = function() props.onClick() end,
	MouseEnter = function() isHovered(true) end,
}
```

## Props reativas

Vide aceita estático ou função na mesma posição:

```luau
create "TextLabel" {
	Text = "Título",                              -- estático
	Text = npcName,                               -- source direto
	Text = function() return `{name()} — Lv {level()}` end,
}
```

## Listas dinâmicas com `indexes`

```luau
create "Frame" {
	create "UIListLayout" { Padding = UDim.new(0, Theme.spacing.sm) },

	indexes(props.options, function(option, index)
		return OptionButton(option, index, props.onSelect)
	end),
}
```

`option` é uma source — leia com `option()` dentro da render function.

## Mount no Controller

Componentes não montam sozinhos:

```luau
local root = Vide.root

function MyController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Parent = playerGui

	local cleanup = root(function()
		return MyComponent {
			parent = gui,
			label = "Hello",
			onClick = function() end,
		}
	end)

	-- depois: cleanup() desconecta os effects; gui:Destroy() some com as instâncias.
	-- Os dois são necessários — Destroy sozinho vaza os effects reativos.
end
```

## Story pattern (UI Labs)

Toda componente novo ganha uma story em `src/ReplicatedStorage/Stories/`
(componentes do kit vão em `Stories/Common/`).

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local MyComponent = require(ReplicatedStorage.Shared.UI.Common.MyComponent)

return {
	vide = Vide,
	controls = {
		label = "Click me",
	},
	story = function(props)
		return MyComponent {
			parent = props.target,
			label = props.controls.label,
			onClick = function() print("[Story] click") end,
		}
	end,
}
```

`props.target` é a Instance onde o UI Labs renderiza; `props.controls` reflete os
controls declarados.

## Regras

- Componente recebe `parent` via props; **não** usa `WaitForChild` nem lê game state
- Props sempre com `export type` no topo
- Toda cor, fonte, tamanho, raio e espaçamento vem de `Theme`
- `Reactive<T>` pra prop que muda depois do mount
- Cleanup é responsabilidade do Controller que montou, via `root`

## Anti-patterns

- ❌ `Color3.fromRGB(...)` dentro de componente — use `Theme.color`
- ❌ `create("Frame")({...})` — use `create "Frame" { ... }`
- ❌ `[Vide.Event("Activated")] = ...` — use `Activated = ...`
- ❌ `game:GetService(...)` dentro do componente — passe via props
- ❌ Ler State module ou Attribute direto no componente — passe via props
- ❌ Componente cuidando do próprio cleanup — quem monta cuida

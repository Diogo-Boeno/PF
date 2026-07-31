# Design System

Estilo: **AAA indie**. Sóbrio, técnico, de alto contraste. Nada de cartoon-simulator
genérico de Roblox.

A implementação canônica é `src/ReplicatedStorage/Shared/UI/Common/Theme.luau`.
Ele é `table.freeze`d e é a **fonte única de verdade**. Este documento explica a
intenção por trás dos valores; quando os dois divergirem, o código vence.

## Princípio central

**Cor hardcoded em componente é bug.** Todo `Color3`, `Font`, `TextSize`, `UDim`
de raio e todo espaçamento vem de `Theme`. Isso é o que permite retematizar o jogo
inteiro em um arquivo.

```luau
local UI = require(ReplicatedStorage.Shared.UI.Common)
local Theme = UI.Theme

BackgroundColor3 = Theme.color.surface   -- certo
BackgroundColor3 = Color3.fromRGB(21, 21, 24)  -- errado, mesmo que o valor bata
```

## Paleta

Uma rampa monocromática do mais escuro ao mais claro, mais um accent e uma cor de
falha. Sem terceira família de cor.

| Token | Uso |
|---|---|
| `background` | fundo da tela |
| `surface` | painel, card, campo |
| `surfacePressed` | superfície em estado pressionado |
| `surfaceRaised` | superfície elevada sobre `surface` |
| `surfaceHover` | superfície sob o cursor |
| `strokeSoft` | divisória interna, baixo contraste |
| `stroke` | borda de elemento interativo |
| `textPrimary` | texto de leitura |
| `textMuted` | rótulo secundário |
| `textFaint` | texto desabilitado, placeholder |

### Accent

`accent` é **feedback de interação, nunca decoração**. Reservado para estados
engajados: pressionado, focado, marcado.
`accentDim` é a camada de hover, para o accent cheio continuar significando algo.

### Danger

`danger` é a única quebra de matiz da rampa: falha e ação destrutiva. É um
vermelho contido, não alarme saturado. Nunca use como enfeite.

### Judge

`Theme.judge` (`perfect`, `great`, `good`, `miss`) é a exceção sancionada ao
monocromático, para feedback de timing que precisa ser lido num relance. Os tons
são propositalmente abafados. **Não use `judge` fora de feedback de gameplay.**

`judge.great` é um esmeralda contido — precisamente para não cair no verde Roblox
`#2ecc71`, que é proibido no projeto.

## Tipografia

Família única: Gotham SSm (`rbxasset://fonts/families/GothamSSm.json`), em três pesos.

| Token | Peso | Uso |
|---|---|---|
| `font.heading` | Bold | título de janela, cabeçalho de seção |
| `font.strong` | SemiBold | rótulo de botão, ênfase |
| `font.body` | Medium | texto corrido |

Tamanhos: `sm 13` · `md 15` · `lg 18` · `xl 34`.
`xl` é tier de display — callout de gameplay, nunca texto corrido.

## Forma e espaço

- **Traço de 1px** (`strokeThickness`). Mais grosso lê como cartoon.
- Raio: `sm 4` para controle, `md 6` para painel. Nada mais arredondado que isso.
- Espaçamento na escala `xs 4 · sm 8 · md 12 · lg 16`. Não invente valores no meio.

## Checklist de revisão

Antes de dar um componente por pronto:

- [ ] Zero `Color3.fromRGB` / `Font.new` / número mágico de tamanho no arquivo
- [ ] Estados hover e pressed usam os tokens de superfície corretos
- [ ] Accent aparece só em estado engajado
- [ ] Espaçamento sai da escala, não de valores arbitrários
- [ ] Existe uma story em `ReplicatedStorage/Stories/`

## Ainda não existe

Não há tokens de animação, sombra ou breakpoint. `AutoScale` cobre adaptação de
resolução. Se precisar de um token novo, adicione em `Theme.luau` — não contorne
localmente.

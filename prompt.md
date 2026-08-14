Mudança na UI

Agora os frames da hotbar são assim:

---
1 (Button)
|-- Stroke (ImageLabel)
    |--CellNum (TextLabel)
    |--ContentName (TextLabel)
---
antes era apenas um image com contentname e cellnum, agora o cellnum e o contentName ficam dentro de um imageLabel dentro deste botão, ou seja:


estou trabalhando na UI do inventário agora, fiz um component novo que usa ScaleType == Slice para ser usado como frame border

---
ReplicatedStorage (Folder/Service)
  |-- Components (ScreenUI)
    |--Category (Pro inventário, ex: Weapons ----------- x ) -> sendo x a quantidade de itens na categoria
    |--SimpleFrameredWindow (Uma frame comum com a transparency em 75, bg preto e um stroke diferente, vai ser usado na maioria das janelas)
    |--FrameredWindow (Uma frame igual o SimpleFramaredWindow, mas, com mais enfeites)
    |--CellButton(Igual o FramedWindow, mas sendo um botão)
    |--HotbarButton(os botões com serial numbers para hotbar)
---

como fiz o inventário:
Tab deve abrir o inventário, vou tirar o Tab do roblox padrão, fazer o meu.
Tab deve esconder as UI's de status, fiz de uma maneira que fica fácil: Stats(ScreenGui).Enabled = false e pronto

---
Inventory (ScreenGui)
  |--Background (Frame)
      |--Stroke (ImageLabel, SimpleFrame)
      |--Container (ScrollingFrame) -> Vão ter todas as categorias separadas por frames
          |--Abilities (Frame) -> Categoria
              |--Frame (Frame) -> Onde ficarão os cells, organizado por UIListLayout
                  |--Cell (ImageButton, é o `CellButton` do components, deve ter o nome do item)
              |--Category (Frame)
                  |--Bar (Frame, espaçador)
                  |--Name (TextLabel, nome da categoria)
                  |--Quantity (Quantidade de itens na categoria)

          Além do Abilities tem: Consumables, Equipments, Materials, Miscellaneous, Relics, Tools, Training, Weapons. Todos organizados por LayoutOrder
---

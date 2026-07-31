local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)

return {
    vide = Vide,
    controls = {
        Text = "Hello UI Labs",
        Color = Color3.fromRGB(80, 120, 200),
    },
    story = function(props)
        local create = Vide.create
        return create "TextLabel" {
            Size = UDim2.fromOffset(280, 100),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = function() return props.controls.Color() end,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextSize = 22,
            Font = Enum.Font.GothamBold,
            Text = function() return props.controls.Text() end,
            Parent = props.target,

            create "UICorner" {
                CornerRadius = UDim.new(0, 8),
            },
        }
    end,
}

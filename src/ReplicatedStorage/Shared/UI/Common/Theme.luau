--!strict
-- Single source of truth for the visual language: one monochrome ramp plus one
-- accent. Components must consume colors from here — a hardcoded Color3 inside
-- a component is a bug. Frozen so a stray write can't silently retheme the game.

local FONT_FAMILY = "rbxasset://fonts/families/GothamSSm.json"

local Theme = {
	color = {
		-- monochrome ramp, darkest to lightest
		background = Color3.fromRGB(10, 10, 12),
		surface = Color3.fromRGB(21, 21, 24),
		surfacePressed = Color3.fromRGB(15, 15, 17),
		surfaceRaised = Color3.fromRGB(30, 30, 34),
		surfaceHover = Color3.fromRGB(39, 39, 44),
		strokeSoft = Color3.fromRGB(36, 36, 41),
		stroke = Color3.fromRGB(52, 52, 58),

		textPrimary = Color3.fromRGB(232, 232, 234),
		textMuted = Color3.fromRGB(138, 138, 146),
		textFaint = Color3.fromRGB(92, 92, 100),

		-- the single accent: interaction feedback only, never decoration.
		-- accentDim is the hover tier so full accent  stays reserved for
		-- engaged states (pressed, focused, checked).
		accent = Color3.fromRGB(236, 236, 236),
		accentDim = Color3.fromRGB(111, 111, 111),

		-- the one hue break in the ramp: failure feedback only (a missed input,
		-- a destructive action). Muted, not a saturated alarm red — never decoration.
		danger = Color3.fromRGB(201, 61, 61),
	},

	-- gameplay judgement colors — the sanctioned exception to the monochrome palette,
	-- because rhythm feedback has to read at a glance. Kept muted (not neon) so they
	-- still sit in the AAA-indie tone rather than cartoon Roblox.
	judge = {
		perfect = Color3.fromRGB(163, 132, 236), -- Sick — violet
		great = Color3.fromRGB(112, 196, 132), -- Good — muted emerald (never the banned #2ecc71)
		good = Color3.fromRGB(201, 61, 61), -- Bad — the danger red
		miss = Color3.fromRGB(128, 128, 136), -- Miss — dead gray
	},

	font = {
		heading = Font.new(FONT_FAMILY, Enum.FontWeight.Bold),
		strong = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold),
		body = Font.new(FONT_FAMILY, Enum.FontWeight.Medium),
	},

	textSize = {
		sm = 13,
		md = 15,
		lg = 18,
		-- display tier: punchy gameplay callouts (judgement popups), not body copy
		xl = 34,
	},

	radius = {
		sm = UDim.new(0, 4),
		md = UDim.new(0, 6),
	},

	-- 1px strokes keep the technical-drawing look; thicker reads as cartoon
	strokeThickness = 1,

	spacing = {
		xs = 4,
		sm = 8,
		md = 12,
		lg = 16,
	},
}

export type Theme = typeof(Theme)

table.freeze(Theme.color)
table.freeze(Theme.judge)
table.freeze(Theme.font)
table.freeze(Theme.textSize)
table.freeze(Theme.radius)
table.freeze(Theme.spacing)

return table.freeze(Theme)

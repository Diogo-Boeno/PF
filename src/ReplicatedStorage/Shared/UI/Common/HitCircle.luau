--!strict
-- osu!-style hit target: an approach ring closes onto a fixed circle over
-- `approachTime`; the player clicks when they meet. Owns its own clock/loop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source
local cleanup = Vide.cleanup

type Reactive<T> = T | () -> T

export type Judgement = "perfect" | "great" | "good" | "miss"
export type HitResult = {
	judgement: Judgement,
	-- signed ms error against the beat: negative = early, positive = late
	errorMs: number,
}

export type HitCircleProps = {
	-- fired exactly once per note when it resolves
	onJudge: ((HitResult) -> ())?,
	approachTime: number?,
	-- half-width of each judgement window, in ms around the beat
	perfectMs: number?,
	greatMs: number?,
	goodMs: number?,
	-- re-arm after the flash instead of freezing (practice/demo loop)
	autoReset: boolean?,
	-- swallow off-beat clicks so the note survives until a real on-beat hit
	onlyOnBeat: boolean?,
	label: Reactive<string>?,
	-- per-judgement popup words; falls back to neutral defaults
	judgeLabels: { [Judgement]: string }?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
}

-- ring starts this many circle-diameters out and shrinks to 1x at the beat
local START_SCALE = 2.4
local DEFAULT_APPROACH = 1.2
local DEFAULT_PERFECT_MS = 40
local DEFAULT_GREAT_MS = 90
local DEFAULT_GOOD_MS = 140
-- resolve-flash length; also the read time for the judgement popup
local FEEDBACK_TIME = 0.35
local RING_THICKNESS = 3
-- on a hit the ring bursts out to this scale as it fades
local RING_RIPPLE_SCALE = 1.9

local JUDGE_COLOR: { [Judgement]: Color3 } = {
	perfect = Theme.judge.perfect,
	great = Theme.judge.great,
	good = Theme.judge.good,
	miss = Theme.judge.miss,
}

-- impact scale on resolve: the better the hit, the harder the pop
local JUDGE_POP: { [Judgement]: number } = {
	perfect = 1.4,
	great = 1.3,
	good = 1.2,
	miss = 1.0,
}

-- scale the pop settles to as the flash fades; a miss just deflates in place
local JUDGE_REST: { [Judgement]: number } = {
	perfect = 1,
	great = 1,
	good = 1,
	miss = 0.9,
}

local DEFAULT_LABELS: { [Judgement]: string } = {
	perfect = "Perfect",
	great = "Great",
	good = "Good",
	miss = "Miss",
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function HitCircle(props: HitCircleProps)
	local approachTime = props.approachTime or DEFAULT_APPROACH
	local perfectMs = props.perfectMs or DEFAULT_PERFECT_MS
	local greatMs = props.greatMs or DEFAULT_GREAT_MS
	local goodMs = props.goodMs or DEFAULT_GOOD_MS
	local autoReset = props.autoReset == true

	local resolved = source(false)
	local missed = source(false)
	local ringScale = source(START_SCALE)
	local fade = source(0) -- 0 = visible, 1 = gone
	local pop = source(1)
	local judgeColor = source(Theme.color.surfaceRaised)
	local judgeText = source("")

	-- mutated by the frame loop every step; not reactive
	local clockStart = os.clock()
	local resolveClock = 0
	local popStart = 1
	local popRest = 1
	local ringAtResolve = 1 -- ring scale at resolve, so the burst starts from there

	local function judgeFromError(errMs: number): Judgement
		local a = math.abs(errMs)
		if a <= perfectMs then
			return "perfect"
		elseif a <= greatMs then
			return "great"
		elseif a <= goodMs then
			return "good"
		end
		return "miss"
	end

	local function resolve(judgement: Judgement, errMs: number)
		if resolved() then
			return
		end
		resolved(true)
		missed(judgement == "miss")
		judgeColor(JUDGE_COLOR[judgement])
		judgeText((props.judgeLabels and props.judgeLabels[judgement]) or DEFAULT_LABELS[judgement])
		popStart = JUDGE_POP[judgement]
		popRest = JUDGE_REST[judgement]
		ringAtResolve = ringScale()
		pop(popStart)
		resolveClock = os.clock()

		if props.onJudge then
			props.onJudge({ judgement = judgement, errorMs = errMs })
		end
	end

	local function rearm()
		clockStart = os.clock()
		resolved(false)
		missed(false)
		ringScale(START_SCALE)
		fade(0)
		pop(1)
		judgeColor(Theme.color.surfaceRaised)
		judgeText("")
	end

	local conn: RBXScriptConnection? = nil
	local function stop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()

		if not resolved() then
			local elapsed = now - clockStart
			-- clamp so the ring locks onto the circle instead of collapsing past it
			ringScale(lerp(START_SCALE, 1, math.clamp(elapsed / approachTime, 0, 1)))

			-- ring sailed past the late-good window: auto-miss
			if elapsed > approachTime + goodMs / 1000 then
				resolve("miss", (elapsed - approachTime) * 1000)
			end
			return
		end

		local t = (now - resolveClock) / FEEDBACK_TIME
		if t >= 1 then
			if autoReset then
				rearm()
			else
				fade(1)
				stop()
			end
		else
			fade(t)
			-- ease-out so the scale snaps then settles instead of a linear crawl
			local eased = 1 - (1 - t) * (1 - t)
			pop(lerp(popStart, popRest, eased))
			if not missed() then
				ringScale(lerp(ringAtResolve, RING_RIPPLE_SCALE, eased))
			end
		end
	end)
	-- drop the loop if the mounting scope tears down mid-note, or it leaks
	cleanup(stop)

	return create "Frame" {
		Name = "HitCircle",
		Size = props.size or UDim2.fromOffset(96, 96),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		Parent = props.parent,

		-- clickable throughout the approach so an early press still resolves (osu semantics)
		create "TextButton" {
			Name = "Target",
			Size = UDim2.fromScale(1, 1),
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = function()
				return if resolved() then judgeColor() else Theme.color.surfaceRaised
			end,
			BackgroundTransparency = fade,
			Text = props.label or "",
			TextColor3 = Theme.color.textPrimary,
			TextTransparency = fade,
			TextSize = Theme.textSize.lg,
			FontFace = Theme.font.strong,

			Activated = function()
				if resolved() then
					return
				end
				local errMs = (os.clock() - clockStart - approachTime) * 1000
				local judgement = judgeFromError(errMs)
				if judgement == "miss" and props.onlyOnBeat then
					return
				end
				resolve(judgement, errMs)
			end,

			create "UIScale" { Scale = pop },
			create "UICorner" { CornerRadius = UDim.new(1, 0) },
			create "UIAspectRatioConstraint" {},
			create "UIStroke" {
				Thickness = Theme.strokeThickness,
				Transparency = fade,
				Color = function()
					return if resolved() then judgeColor() else Theme.color.stroke
				end,
			},
		},

		-- Active=false so the ring's transparent body never sinks clicks meant for the target
		create "Frame" {
			Name = "ApproachRing",
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = function()
				local s = ringScale()
				return UDim2.fromScale(s, s)
			end,
			BackgroundTransparency = 1,

			create "UICorner" { CornerRadius = UDim.new(1, 0) },
			create "UIAspectRatioConstraint" {},
			create "UIStroke" {
				Thickness = RING_THICKNESS,
				-- burst takes the judgement color so a Sick reads violet, a Bad red
				Color = function()
					return if resolved() then judgeColor() else Theme.color.accent
				end,
				Transparency = function()
					if not resolved() then
						return 0
					end
					return if missed() then 1 else fade()
				end,
			},
		},

		-- judgement word: punches in over the circle, rises and fades on resolve
		create "TextLabel" {
			Name = "Judgement",
			Active = false,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = function()
				return UDim2.new(0.5, 0, 0, math.round(-10 - 30 * fade()))
			end,
			Size = UDim2.fromScale(3, 0.6),
			BackgroundTransparency = 1,
			Text = judgeText,
			TextColor3 = judgeColor,
			TextTransparency = function()
				return if resolved() then fade() else 1
			end,
			TextSize = Theme.textSize.xl,
			FontFace = Theme.font.heading,
			ZIndex = 4,

			create "UIScale" { Scale = pop },
			create "UIStroke" {
				Thickness = 2,
				Color = Theme.color.background,
				Transparency = function()
					return if resolved() then fade() else 1
				end,
			},
		},
	}
end

return HitCircle

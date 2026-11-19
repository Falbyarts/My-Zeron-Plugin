--!strict
-- Heatmap-LocLabs: a new chat's composer, with the year of commits under it.
--
-- The composer is Zeron's (`#chat-composer`); this adds one node after it,
-- below its foot, on a new chat only. The commits are this device's own
-- chats' and projects' folders, read by the plugin's service (`year`), and
-- each day is a cell in a 53-week grid, Sunday first: no commits in the
-- text's ink, more in the theme's accent. Nothing is coloured raw, so the
-- grid follows the theme and the accent the person chose: the canvas bakes
-- plain colours as it is built, so the theme is read where they're made.
--
-- The header's refresh asks the service again at once, past its five-minute
-- cache. A day's card is the plugin's own, not a tooltip: the pointer moves
-- into it and its list scrolls, so a busy day reads whole, its "+n" fading
-- as the list moves under it.

local zeron = require("./zeron")("heatmap-loclabs")
local ink = require("@ds/visual_ink")
local HoverCard = require("@ds/hover_card")
local IconButton = require("@ds/icon_button").IconButton

local COLUMNS = 53
local ROWS = 7
local CELL = 10
local GAP = 2
local LABELS_W = 20
local GRID_W = COLUMNS * CELL + (COLUMNS - 1) * GAP
local WIDTH = LABELS_W + 6 + GRID_W
local HEADER_H = 22
local MONTH_H = 14
local GRID_H = ROWS * CELL + (ROWS - 1) * GAP
local GRID_TOP = HEADER_H + 4 + MONTH_H + 4
local HEIGHT = GRID_TOP + GRID_H
local BELOW = 12

-- (The card floats over the composer's foot, its list scrolling: one line a
-- commit, as many as the service keeps for a day.)
local CARD_W = 340
local CARD_LIST_H = 168
local CARD_ROW_H = 18
local CARD_GAP = 8
local CARD_CLOSE = 260

-- How far the ink is laid: a day with no commits is barely there; each
-- level is fuller. Light needs a touch more than dark to read the same on
-- its paper.
local WASH = {
	dark = { empty = 0.08, levels = { 0.28, 0.48, 0.72, 1 } },
	light = { empty = 0.14, levels = { 0.32, 0.54, 0.76, 1 } },
}
local DAYS = { "", "Mon", "", "Wed", "", "Fri", "" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local REFRESH = 300

local data = ui.state("heatmap-loclabs.year.v2", nil :: any)
local pending = ui.state("heatmap-loclabs.pending", false)
local card = ui.state("heatmap-loclabs.card", nil :: any)
local card_offset = ui.state("heatmap-loclabs.card.offset", 0)
local card_hovered = false
local card_close = 0

local function day_of(at: number): string
	return os.date("%Y-%m-%d", at)
end

-- The Sunday on or before the same weekday a year ago: the grid's first
-- column, and the service's `--since`.
local function grid_start(): number
	local now: any = os.date("*t", os.time())
	local noon = os.time({
		year = now.year,
		month = now.month,
		day = now.day,
		hour = 12,
		min = 0,
		sec = 0,
	} :: any)
	local back = noon - 364 * 86400
	local date: any = os.date("*t", back)
	return back - (date.wday - 1) * 86400
end

local function level_of(count: number): number
	if count <= 0 then
		return 0
	elseif count == 1 then
		return 1
	elseif count <= 3 then
		return 2
	elseif count <= 6 then
		return 3
	end
	return 4
end

-- Light or dark as the theme worn now says it: its background's ink, so any
-- theme reads right, the person's own included.
local function scheme_of(): string
	ui.theme.current:get()
	local bg = ui.theme.get("background")
	if type(bg) == "string" and #bg >= 7 then
		local r = (tonumber(string.sub(bg, 2, 3), 16) or 0) / 255
		local g = (tonumber(string.sub(bg, 4, 5), 16) or 0) / 255
		local b = (tonumber(string.sub(bg, 6, 7), 16) or 0) / 255
		if 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.5 then
			return "light"
		end
	end
	return "dark"
end

local function wash(level: number, scheme: string): number
	local steps = if scheme == "light" then WASH.light else WASH.dark
	return if level == 0 then steps.empty else steps.levels[level]
end

local function tint(level: number): string
	return if level == 0 then "$text.primary" else "$accent"
end

local function swatch(level: number, scheme: string): Node
	return ui.div {
		w = 9,
		h = 9,
		rounded = ui.raw(2, "a heatmap cell's corner, at GitHub's scale"),
		bg = tint(level),
		opacity = wash(level, scheme),
		shrink = 0,
	}
end

-- A day's commits as the card lists them: the time and the message, newest
-- first. Long messages keep one line.
local function flatten(text: string): string
	local clean = string.gsub(text or "", "%s+", " ")
	return (string.gsub(clean, "^%s*(.-)%s*$", "%1"))
end

local function one_line(text: string, limit: number): string
	local clean = flatten(text)
	if #clean > limit then
		return string.sub(clean, 1, limit - 1) .. "…"
	end
	return clean
end

local function day_label(at: number): string
	return os.date("%A, %d %B %Y", at)
end

local function entry_n(held: any): number
	if type(held) == "table" then
		return tonumber(held.n) or 0
	end
	return tonumber(held) or 0
end

local function entry_commits(held: any): { any }
	if type(held) == "table" and type(held.commits) == "table" then
		return held.commits
	end
	return {}
end

local function commit_rows(held: any): { Node }
	local rows: { Node } = {}
	for _, commit in entry_commits(held) do
		local subject = one_line(tostring(commit.subject or ""), 90)
		if subject == "" then
			subject = zeron.t("untitled")
		end
		table.insert(
			rows,
			ui.text {
				`{os.date("%H:%M", tonumber(commit.at) or 0)}  {subject}`,
				w_full = true,
				weight = "$font.weight.medium",
				text_size = "$font.size.sm",
				line_height = "$font.line.sm",
				color = "$text.primary",
			}
		)
	end
	if #rows == 0 then
		table.insert(
			rows,
			ui.text {
				zeron.t("empty"),
				text_size = "$font.size.sm",
				color = "$text.tertiary",
			}
		)
	end
	return rows
end

-- A day's card, in the grid's own tree: the pointer comes in off the cell
-- and rests on it, its list scrolling under the wheel. The "+n" stays in
-- the card's foot and fades as the list moves away from its top.
local function DayCard(props: any): Node
	local known = props.card:get()
	if type(known) ~= "table" then
		return ui.div { w = 0, h = 0 }
	end
	local held = known.held
	local n = entry_n(held)
	local listed = #entry_commits(held)
	-- (What the card's room shows at rest: the rest is under the scroll, and
	-- the "+n" says how much until the list moves.)
	local room = math.max(1, math.floor(CARD_LIST_H / CARD_ROW_H))
	local extra = math.max(0, n - math.min(listed, room))
	local column: number = tonumber(known.column) or 0
	local left = math.clamp(
		column * (CELL + GAP) + LABELS_W + 6 - math.floor((CARD_W - CELL) / 2),
		0,
		WIDTH - CARD_W
	)
	local children: { Node } = {
		ui.text {
			zeron.t("day_commits", { date = day_label(tonumber(known.at) or 0), n = n }),
			w_full = true,
			text_size = "$font.size.xs",
			line_height = "$font.line.xs",
			color = "$text.secondary",
		},
		ui.scroll {
			w_full = true,
			max_h = CARD_LIST_H,
			offset = card_offset,
			fade = { 10, 10 },
			fade_overflow = true,
			ui.column { w_full = true, gap = 3, table.unpack(commit_rows(held)) },
		},
	}
	if extra > 0 then
		table.insert(
			children,
			ui.text {
				zeron.t("more_n", { n = extra }),
				w_full = true,
				text_size = "$font.size.xs",
				line_height = "$font.line.xs",
				color = "$text.tertiary",
				opacity = function(): number
					return math.max(0, 1 - card_offset:get() / 24)
				end,
			}
		)
	end
	return HoverCard.Card {
		absolute = true,
		left = left,
		bottom = HEIGHT - (GRID_TOP - CARD_GAP),
		w = CARD_W,
		p = "$space.2",
		gap = "$space.1",
		pointer_events = "auto",
		on_hover = function(inside: boolean)
			card_hovered = inside
			if inside then
				card_close += 1
			else
				card_close += 1
				local gen = card_close
				ui.after(CARD_CLOSE, function()
					if gen == card_close and not card_hovered then
						card:set(nil)
					end
				end)
			end
		end,
		table.unpack(children),
	}
end

-- (A day "YYYY-MM-DD" as the slot it fills in the grid: 0 is the first
-- Sunday, 371 the last Saturday after it.)
local function day_slot(start: number, day: string): number?
	local y, m, d = string.match(day, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	local at = os.time({
		year = tonumber(y) :: number,
		month = tonumber(m) :: number,
		day = tonumber(d) :: number,
		hour = 12,
		min = 0,
		sec = 0,
	} :: any)
	-- (Rounded: a day across a clock change is an hour off a whole one.)
	local slot = math.floor((at - start) / 86400 + 0.5)
	if slot < 0 or slot >= COLUMNS * ROWS then
		return nil
	end
	return slot
end

-- The grid on one canvas: 371 small squares are cheaper drawn than built
-- as nodes, and the drawing follows the theme by the colours it is built
-- with. Days with commits carry an invisible square over their cell: the
-- pointer rests on it and its card lists the day.
local function grid(start: number, known: any, home: () -> boolean, colors: { [number]: any }): Node
	local days: any = if type(known) == "table" then known.days or {} else {}
	local marks: { [number]: number } = {}
	local overlays: { Node } = {}
	for day, held in days do
		local slot = day_slot(start, tostring(day))
		local n = entry_n(held)
		if slot and n > 0 then
			marks[slot] = n
			local column = math.floor(slot / 7)
			local row = slot % 7
			local first_at = start + slot * 86400
			local first = if type(held) == "table" and type(held.commits) == "table" then held.commits[1] else nil
			if type(first) == "table" and tonumber(first.at) then
				first_at = tonumber(first.at) :: number
			end
			table.insert(
				overlays,
				ui.div {
					absolute = true,
					left = column * (CELL + GAP) - 1,
					top = row * (CELL + GAP) - 1,
					w = CELL + 2,
					h = CELL + 2,
					pointer_events = function(): string
						return if home() then "auto" else "none"
					end,
					on_hover = function(inside: boolean)
						if not home() then
							return
						end
						if inside then
							card_close += 1
							card_offset:set(0)
							card:set({ at = first_at, held = held, column = column })
						else
							card_close += 1
							local gen = card_close
							ui.after(CARD_CLOSE, function()
								if gen == card_close and not card_hovered then
									card:set(nil)
								end
							end)
						end
					end,
				}
			)
		end
	end

	return ui.div {
		relative = true,
		w = GRID_W,
		h = GRID_H,
		shrink = 0,
		ui.canvas {
			w = GRID_W,
			h = GRID_H,
			draw = function(c: any)
				for column = 0, COLUMNS - 1 do
					for row = 0, ROWS - 1 do
						local level = level_of(marks[column * 7 + row] or 0)
						c:rect(
							column * (CELL + GAP),
							row * (CELL + GAP),
							CELL,
							CELL,
							colors[level],
							2
						)
					end
				end
			end,
		},
		table.unpack(overlays),
	}
end

local function month_length(year: number, month: number): number
	local start_at = os.time({ year = year, month = month, day = 1, hour = 12, min = 0, sec = 0 } :: any)
	local next_at = os.time({
		year = if month == 12 then year + 1 else year,
		month = if month == 12 then 1 else month + 1,
		day = 1,
		hour = 12,
		min = 0,
		sec = 0,
	} :: any)
	return math.floor((next_at - start_at) / 86400 + 0.5)
end

local function Heatmap(props: any): Node
	local known: any = props.data:get() or {}
	local total: number = tonumber(known.total) or 0
	local start: number = props.start
	local scheme = scheme_of()

	-- (Laid now, as the canvas takes plain colours: a theme change builds
	-- the grid again in its accent, the legend's swatches following by
	-- themselves.)
	local colors: { [number]: any } = {}
	for level = 0, 4 do
		colors[level] = ink.canvas({
			token = if level == 0 then "text" else "accent",
			alpha = wash(level, scheme),
		})
	end

	-- One date a week: the label sits where a week holds a month's first day.
	local months: { Node } = {}
	for column = 0, COLUMNS - 1 do
		local date: any = os.date("*t", start + column * 7 * 86400)
		local month: number? = nil
		if date.day == 1 then
			month = date.month
		elseif date.day + 6 > month_length(date.year, date.month) then
			month = if date.month == 12 then 1 else date.month + 1
		end
		local left = column * (CELL + GAP)
		if month and left <= GRID_W - 22 then
			table.insert(
				months,
				ui.text {
					MONTHS[month],
					absolute = true,
					left = left,
					top = 0,
					text_size = ui.raw(10, "month labels sit in their own 14 points"),
					line_height = ui.raw(10, "month labels sit in their own 14 points"),
					color = "$text.tertiary",
				}
			)
		end
	end

	local labels: { Node } = {}
	for row = 0, ROWS - 1 do
		local name = DAYS[row + 1] or ""
		if name == "" then
			table.insert(labels, ui.div { w = LABELS_W, h = CELL })
		else
			table.insert(
				labels,
				ui.text {
					name,
					w = LABELS_W,
					h = CELL,
					align = "right",
					text_size = ui.raw(9, "day labels at the cells' own pitch"),
					line_height = ui.raw(10, "day labels at the cells' own pitch"),
					color = "$text.tertiary",
				}
			)
		end
	end

	local header: any
	if known.error and total == 0 then
		header = zeron.t("unavailable")
	elseif known.at == nil then
		header = zeron.t("loading")
	else
		header = zeron.t("count", { n = total })
	end

	return ui.column {
		w_full = true,
		h_full = true,
		gap = 4,
		role = "img",
		label = zeron.s("label", { n = total }),
		-- The count, its refresh, and the scale the colours stand for.
		ui.row {
			w_full = true,
			h = HEADER_H,
			justify = "between",
			items = "center",
			ui.row {
				items = "center",
				gap = 2,
				shrink = 0,
				ui.text {
					header,
					text_size = "$font.size.xs",
					color = "$text.secondary",
					shrink = 0,
				},
				IconButton {
					icon = "refresh",
					label = zeron.t("refresh"),
					size = "sm",
					tone = "quiet",
					tooltip_side = "bottom",
					on_click = function()
						props.refresh()
					end,
				},
			},
			ui.row {
				items = "center",
				gap = 4,
				shrink = 0,
				ui.text { zeron.t("less"), text_size = "$font.size.xs", color = "$text.tertiary" },
				swatch(0, scheme),
				swatch(1, scheme),
				swatch(2, scheme),
				swatch(3, scheme),
				swatch(4, scheme),
				ui.text { zeron.t("more"), text_size = "$font.size.xs", color = "$text.tertiary" },
			},
		},
		-- The months, over the columns they begin in.
		ui.row {
			w_full = true,
			h = MONTH_H,
			gap = 6,
			ui.div { w = LABELS_W, h = MONTH_H, shrink = 0 },
			ui.div {
				relative = true,
				w = GRID_W,
				h = MONTH_H,
				shrink = 0,
				table.unpack(months),
			},
		},
		-- The days down the side, then the weeks.
		ui.row {
			w_full = true,
			h = GRID_H,
			gap = 6,
			ui.column { w = LABELS_W, h = GRID_H, gap = GAP, shrink = 0, table.unpack(labels) },
			grid(start, known, props.home, colors),
		},
	}
end

zeron.place {
	at = "#chat-composer",
	after = function(): Node
		local start = grid_start()
		local since = day_of(start)
		local route = zeron.live("route")
		local function home(): boolean
			local where = route()
			return type(where) == "table" and where.name == "home"
		end

		local function load(force: boolean)
			if pending:get() then
				return
			end
			pending:set(true)
			zeron.service():call("year", { since = since, force = force }, { timeout = 120 }):after(
				function(value: any)
					pending:set(false)
					value = if type(value) == "table" then value else {}
					data:set({
						at = os.time(),
						since = since,
						days = value.days or {},
						total = value.total or 0,
					})
				end,
				function(err: any)
					pending:set(false)
					local had: any = table.clone(data:peek() or {})
					had.at = os.time()
					had.since = since
					had.error = zeron.reason(err)
					data:set(had)
				end
			)
		end

		ui.effect(function()
			local where = route()
			if type(where) ~= "table" or where.name ~= "home" then
				return
			end
			local known: any = data:peek()
			if
				type(known) == "table"
				and known.since == since
				and known.error == nil
				and os.time() - (tonumber(known.at) or 0) < REFRESH
			then
				return
			end
			load(false)
		end)

		return ui.div {
			id = "heatmap-loclabs",
			absolute = true,
			right = 0,
			bottom = -(HEIGHT + BELOW),
			w = WIDTH,
			h = HEIGHT,
			overflow = "visible",
			-- Informational: it takes no click from the page; only its days
			-- and its card answer the pointer, and only on a new chat.
			pointer_events = "none",
			opacity = function(): number
				return if home() then 1 else 0
			end,
			Heatmap {
				data = data,
				start = start,
				home = home,
				refresh = function()
					load(true)
				end,
			},
			DayCard { card = card },
		}
	end,
}

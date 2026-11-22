--!strict
-- Heatmap-LocLabs: a new chat's composer, with the year of commits under it.
--
-- The composer is Zeron's (`#chat-composer`); this adds one node after it,
-- below its foot, on a new chat only. The commits are this device's own
-- chats' and projects' folders, read by the plugin's service (`year`), and
-- each day is a cell in a 53-week grid, Sunday first: no commits in the
-- text's ink, more in the accent the person chose. The header, canvas, and
-- day overlays all react to the loaded commits, so the count and grid appear
-- as soon as the service answers, update immediately on refresh, and follow
-- light and dark themes as they change.
--
-- The header's refresh asks the service again at once, past its five-minute
-- cache, a ring turning in the glyph's place while it waits. A day's card is
-- the pointer's own tooltip, as zgx shows them: a popup layer that opens fast
-- and turns inward at the window's edge, listing the day's commits.

local zeron = require("./zeron")("heatmap-loclabs")
local ink = require("@ds/visual_ink")
local HoverCard = require("@ds/hover_card")
local Icon = require("@ds/icon")
local status = require("@ds/status")
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

local MAX_LISTED = 10
local CARD_W = 340

-- How far the ink is laid: a day with no commits is barely there; each
-- level is fuller. Light needs a touch more than dark to read the same on
-- its paper, and its empty cells a little more still to show at all.
local WASH = {
	dark = { empty = 0.08, levels = { 0.28, 0.48, 0.72, 1 } },
	light = { empty = 0.18, levels = { 0.32, 0.54, 0.76, 1 } },
}
local DAYS = { "", "Mon", "", "Wed", "", "Fri", "" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local REFRESH = 300

local data = ui.state("heatmap-loclabs.year.v2", nil :: any)
local pending = ui.state("heatmap-loclabs.pending", false)
local pending_at = ui.state("heatmap-loclabs.pending_at", 0)
-- (A read still out when the plugin reloads never answers: its promise was
-- the old load's. Start the next load clean, as Zeron's own modules do, and
-- let a read's token be shared, so one from an old load is let go.)
local latest = ui.state("heatmap-loclabs.read", "")
local revision = ui.state("heatmap-loclabs.rev", 0)
local LOAD = tostring({})
do
	local was = pending:peek()
	if was then
		pending:set(false)
		pending_at:set(0)
	end
end

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

-- Light or dark as the theme worn now says it: the theme's own kind, so a
-- light theme's paper is read as light whatever its name.
local function scheme_of(): string
	ui.theme.current:get()
	local kind = ui.theme.kind()
	if type(kind) == "string" then
		return if string.find(kind, "light", 1, true) then "light" else "dark"
	end
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

-- A legend swatch in the theme's accent: its alpha follows the scheme as it
-- is worn, so a switch repaints it with the grid.
local function swatch(level: number): Node
	return ui.div {
		w = 9,
		h = 9,
		rounded = ui.raw(2, "a heatmap cell's corner, at GitHub's scale"),
		bg = tint(level),
		opacity = function(): number
			return wash(level, scheme_of())
		end,
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
	local commits = entry_commits(held)
	for index, commit in commits do
		if index > MAX_LISTED then
			break
		end
		local subject = one_line(tostring(commit.subject or ""), 90)
		if subject == "" then
			subject = zeron.s("untitled")
		end
		table.insert(
			rows,
			ui.text {
				`{os.date("%H:%M", tonumber(commit.at) or 0)}  {subject}`,
				weight = "$font.weight.medium",
				text_size = "$font.size.sm",
				line_height = "$font.line.sm",
				color = "$text.primary",
			}
		)
	end
	local n = if type(held) == "table" then tonumber(held.n) or #commits else tonumber(held) or 0
	local extra = n - #rows
	if extra > 0 then
		table.insert(
			rows,
			ui.text {
				zeron.t("more_n", { n = extra }),
				text_size = "$font.size.xs",
				line_height = "$font.line.xs",
				color = "$text.tertiary",
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

local function day_card(at: number, held: any): Node
	local n = entry_n(held)
	return HoverCard.Card {
		w = CARD_W,
		p = "$space.3",
		gap = "$space.1",
		ui.text {
			zeron.t("day_commits", { date = day_label(at), n = n }),
			w_full = true,
			text_size = "$font.size.xs",
			line_height = "$font.line.xs",
			color = "$text.secondary",
		},
		table.unpack(commit_rows(held)),
	}
end

-- (A day "YYYY-MM-DD" as its local noon timestamp, cached across repaints.)
local day_noons: { [string]: number } = {}
local function day_slot(start: number, day: string): number?
	local at = day_noons[day]
	if at == nil then
		local y, m, d = string.match(day, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
		if not y then
			return nil
		end
		at = os.time({
			year = tonumber(y) :: number,
			month = tonumber(m) :: number,
			day = tonumber(d) :: number,
			hour = 12,
			min = 0,
			sec = 0,
		} :: any)
		day_noons[day] = at
	end
	-- (Rounded: a day across a clock change is an hour off a whole one.)
	local slot = math.floor((at - start) / 86400 + 0.5)
	if slot < 0 or slot >= COLUMNS * ROWS then
		return nil
	end
	return slot
end

local month_lengths: { [number]: number } = {}
local function month_length(year: number, month: number): number
	local key = year * 12 + month
	local had = month_lengths[key]
	if had then
		return had
	end
	local start_at = os.time({ year = year, month = month, day = 1, hour = 12, min = 0, sec = 0 } :: any)
	local next_at = os.time({
		year = if month == 12 then year + 1 else year,
		month = if month == 12 then 1 else month + 1,
		day = 1,
		hour = 12,
		min = 0,
		sec = 0,
	} :: any)
	local days = math.floor((next_at - start_at) / 86400 + 0.5)
	month_lengths[key] = days
	return days
end

type MonthMark = { name: string, left: number }
local month_marks_cache: { [number]: { MonthMark } } = {}
local function month_marks(start: number): { MonthMark }
	local had = month_marks_cache[start]
	if had then
		return had
	end
	local out: { MonthMark } = {}
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
			table.insert(out, { name = MONTHS[month], left = left })
		end
	end
	month_marks_cache[start] = out
	return out
end

-- (Measure the grid's months once as the plugin loads, not inside a build.)
do
	local start = grid_start()
	local year = (os.date("*t", start) :: any).year
	for y = year, year + 1 do
		for m = 1, 12 do
			month_length(y, m)
		end
	end
	month_marks(start)
end

-- The grid on one canvas: 371 small squares are cheaper drawn than built
-- as nodes. The canvas reads both the theme and the loaded commits reactively
-- so it repaints immediately when commits arrive, on refresh, or on theme
-- switch. Days with commits carry an invisible hover overlay rebuilt via
-- `ui.presence` whenever commit data changes, deferred past the initial build
-- frame so mounting `#chat-composer` stays fast.
local function grid(start: number, data_state: any, home: () -> boolean, overlays_ready: any): Node
	local last_key = ""
	local last_marks: { [number]: number } = {}
	local function marks_of(known: any, rev: number): { [number]: number }
		local key = if type(known) == "table" then `{rev}:{known.at or 0}:{known.total or 0}` else "nil"
		if key == last_key then
			return last_marks
		end
		local out: { [number]: number } = {}
		local days: any = if type(known) == "table" and type(known.days) == "table" then known.days else nil
		if days then
			for day, held in days do
				local slot = day_slot(start, tostring(day))
				local n = entry_n(held)
				if slot and n > 0 then
					out[slot] = n
				end
			end
		end
		last_key = key
		last_marks = out
		return out
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
				-- (Read here, in the draw: both the theme and the commit data
				-- are reactive, so a theme change or fresh commit data repaints
				-- the canvas immediately.)
				ui.theme.current:get()
				local marks = marks_of(data_state:get(), tonumber(revision:get()) or 0)
				local scheme = scheme_of()
				local colors: { [number]: any } = {}
				for level = 0, 4 do
					colors[level] = ink.canvas({
						token = if level == 0 then "text" else "accent",
						alpha = wash(level, scheme),
					})
				end
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
		ui.presence(function(): string
			if not overlays_ready:get() or not home() then
				return "empty"
			end
			local known: any = data_state:get()
			if type(known) ~= "table" or type(known.days) ~= "table" then
				return "empty"
			end
			local rev = tonumber(revision:get()) or 0
			return `{rev}:{known.at or 0}:{known.total or 0}`
		end, function(key: string): Node
			if key == "empty" then
				return ui.div { pointer_events = "none" }
			end
			local known: any = data_state:peek()
			local days: any = if type(known) == "table" and type(known.days) == "table" then known.days else nil
			if not days then
				return ui.div { pointer_events = "none" }
			end
			local overlays: { Node } = {}
			for day, held in days do
				local slot = day_slot(start, tostring(day))
				local n = entry_n(held)
				if slot and n > 0 then
					local column = math.floor(slot / 7)
					local row = slot % 7
					local first_at = start + slot * 86400
					local first = if type(held) == "table" and type(held.commits) == "table" then held.commits[1] else nil
					if type(first) == "table" and tonumber(first.at) then
						first_at = tonumber(first.at) :: number
					end
					-- Edges open inward, so a card never runs off the window.
					local align = if column < 6 then "start" elseif column >= COLUMNS - 6 then "end" else "center"
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
							tooltip = day_card(first_at, held),
							tooltip_placement = { side = "top", align = align, offset = 10 },
							tooltip_delay = 120,
						}
					)
				end
			end
			return ui.div {
				absolute = true,
				left = 0,
				top = 0,
				w = GRID_W,
				h = GRID_H,
				pointer_events = "none",
				table.unpack(overlays),
			}
		end, {
			absolute = true,
			left = 0,
			top = 0,
			w = GRID_W,
			h = GRID_H,
			pointer_events = "none",
		}),
	}
end

local function Heatmap(props: any): Node
	local start: number = props.start
	local data_state: any = props.data

	-- One date a week: pre-measured positions for month headers.
	local months: { Node } = {}
	for _, mark in month_marks(start) do
		table.insert(
			months,
			ui.text {
				mark.name,
				absolute = true,
				left = mark.left,
				top = 0,
				text_size = ui.raw(10, "month labels sit in their own 14 points"),
				line_height = ui.raw(10, "month labels sit in their own 14 points"),
				color = "$text.tertiary",
			}
		)
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

	local function header_text(): string
		local known: any = data_state:get()
		if type(known) ~= "table" then
			return zeron.s("loading")
		end
		local total: number = tonumber(known.total) or 0
		if known.error and total == 0 then
			if
				known.error == "not_approved"
				or known.error == "off"
				or known.error == "not_allowed"
				or known.error == "not_installed"
			then
				return zeron.s("unavailable")
			end
			return zeron.s("loading")
		elseif known.at == nil then
			return zeron.s("loading")
		end
		return zeron.s("count", { n = total })
	end

	local function a11y_label(): string
		local known: any = data_state:get()
		local total: number = if type(known) == "table" then tonumber(known.total) or 0 else 0
		return zeron.s("label", { n = total })
	end

	return ui.column {
		w_full = true,
		h_full = true,
		gap = 4,
		role = "img",
		label = a11y_label,
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
					header_text,
					text_size = "$font.size.xs",
					color = "$text.secondary",
					shrink = 0,
				},
				IconButton {
					label = zeron.t("refresh"),
					tooltip = zeron.s("refresh"),
					size = "sm",
					tone = "quiet",
					tooltip_side = "bottom",
					pointer_events = function(): string
						return if props.home() then "auto" else "none"
					end,
					disabled = function(): boolean
						return pending:get()
					end,
					on_click = function()
						props.refresh()
					end,
					-- (The glyph gives way to a ring while the read waits.)
					ui.show(
						function(): boolean
							return not pending:get()
						end,
						Icon { name = "refresh", size = 14 }
					),
					ui.show(
						function(): boolean
							return pending:get()
						end,
						status.Spinner { size = 12, ink = "$text.tertiary" }
					),
				},
			},
			ui.row {
				items = "center",
				gap = 4,
				shrink = 0,
				ui.text { zeron.t("less"), text_size = "$font.size.xs", color = "$text.tertiary" },
				swatch(0),
				swatch(1),
				swatch(2),
				swatch(3),
				swatch(4),
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
			grid(start, data_state, props.home, props.overlays_ready),
		},
	}
end

zeron.place {
	at = "#chat-composer",
	after = function(): Node
		local start = grid_start()
		local since = day_of(start)
		local route = zeron.live("route")
		local overlays_ready = ui.use_state(false)
		local function home(): boolean
			local where = route()
			return type(where) == "table" and where.name == "home"
		end

		-- (Defer building day hover cards by one tick so initial `#chat-composer`
		-- placement stays fast while the canvas and header appear on frame 1.)
		ui.after(0, function()
			overlays_ready:set(true)
		end)

		-- (`force`: bypasses the service's 5-minute cache to re-read git right
		-- away. A newer read's answer wins; an older one is dropped, even one
		-- from before a reload.)
		local reads = 0
		local function load(force: boolean)
			-- (Prevent overlapping reads while one is already in flight, while
			-- still letting a stalled read expire after its timeout.)
			local waited = os.time() - (tonumber(pending_at:peek()) or 0)
			if pending:peek() and waited < 30 then
				return
			end
			reads += 1
			local mine = `{LOAD}:{reads}`
			latest:set(mine)
			pending:set(true)
			pending_at:set(os.time())
			zeron.service():call("year", { since = since, force = force }, { timeout = 30 }):after(
				function(value: any)
					if latest:peek() ~= mine then
						return
					end
					pending:set(false)
					pending_at:set(0)
					value = if type(value) == "table" then value else {}
					revision:set((tonumber(revision:peek()) or 0) + 1)
					data:set({
						at = os.time(),
						since = since,
						days = value.days or {},
						total = value.total or 0,
					})
				end,
				function(err: any)
					if latest:peek() ~= mine then
						return
					end
					pending:set(false)
					pending_at:set(0)
					local reason = zeron.reason(err)
					local had: any = table.clone(data:peek() or {})
					had.at = os.time()
					had.since = since
					had.error = reason
					revision:set((tonumber(revision:peek()) or 0) + 1)
					data:set(had)
					-- (If the service was still starting up on cold launch, retry
					-- shortly instead of waiting 30 seconds.)
					if
						(tonumber(had.total) or 0) == 0
						and reason ~= "not_approved"
						and reason ~= "off"
						and reason ~= "not_allowed"
						and reason ~= "not_installed"
					then
						ui.after(3000, function()
							if home() and not pending:peek() then
								load(false)
							end
						end)
					end
				end
			)
		end

		-- Five minutes of a grid is enough; a failed read is asked again
		-- sooner, and a stale one when the window comes back to a new chat.
		local function due(): boolean
			local known: any = data:peek()
			return not (
				type(known) == "table"
				and known.since == since
				and known.error == nil
				and os.time() - (tonumber(known.at) or 0) < REFRESH
			)
		end

		ui.effect(function()
			local where = route()
			if type(where) ~= "table" or where.name ~= "home" then
				return
			end
			if due() then
				load(false)
			end
			-- (Resting here is no reason to leave an old grid up, or a read
			-- that failed while the service was still starting.)
			ui.every(30000, function()
				if home() and due() then
					load(false)
				end
			end)
		end)

		return ui.div {
			id = "heatmap-loclabs",
			absolute = true,
			right = 0,
			bottom = -(HEIGHT + BELOW),
			w = WIDTH,
			h = HEIGHT,
			-- Informational: it takes no click from the page; only its days
			-- and refresh button answer the pointer, and only on a new chat.
			pointer_events = "none",
			opacity = function(): number
				return if home() then 1 else 0
			end,
			Heatmap {
				data = data,
				start = start,
				home = home,
				overlays_ready = overlays_ready,
				refresh = function()
					load(true)
				end,
			},
		}
	end,
}

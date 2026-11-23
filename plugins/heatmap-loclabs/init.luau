--!strict
-- Heatmap-LocLabs: a new chat's composer, with the year of commits under it.
--
-- The composer is Zeron's (`#chat-composer`); this adds one node after it,
-- below its foot, on a new chat only (when enabled in Settings → Plugins).
-- Commits come from the plugin's service (`year`), scoped either to all local
-- chat/project folders on this device or to the project selected in the
-- composer (including cross-device projects, falling back to all local folders
-- when No project is selected). Each day is a cell in a 53-week grid, Sunday
-- first: no commits in the text's ink, more in the accent the person chose.
--
-- The header's refresh asks the service again at once, past its five-minute
-- cache, a ring turning in the glyph's place while it waits. A day's card is
-- the pointer's own tooltip, as zgx shows them: a popup layer that opens fast
-- and turns inward at the window's edge, listing the day's commits.

local zeron = require("./zeron")("heatmap-loclabs")
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
	light = { empty = 0.11, levels = { 0.28, 0.50, 0.74, 1 } },
}
local DAYS = { "", "Mon", "", "Wed", "", "Fri", "" }
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local REFRESH = 300

type Target = { key: string, device: string?, cwd: string? }

local show_heatmap = zeron.setting("show_heatmap")
local scope = zeron.setting("scope")
local pick = ui.shared("zeron.project", nil :: any)

local data = ui.state("heatmap-loclabs.year.v2", nil :: any)
local pending = ui.state("heatmap-loclabs.pending", false)
local pending_at = ui.state("heatmap-loclabs.pending_at", 0)
local pending_key = ui.state("heatmap-loclabs.pending_key", "")
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
		pending_key:set("")
	elseif pending_key:peek() ~= "" then
		pending_key:set("")
	end
end

-- Registered once at module load so remounts never duplicate setting listeners.
local on_setting_changed: ((string, any) -> ())? = nil
zeron.on_setting(function(key: string, value: any)
	if on_setting_changed then
		on_setting_changed(key, value)
	end
end)

local function target_of(reactive: boolean): Target
	local cur_scope = if reactive then scope:get() else scope:peek()
	if cur_scope == "project" then
		local p: any = if reactive then pick:get() else pick:peek()
		if type(p) == "table" and type(p.id) == "string" and p.id ~= "" then
			local rec: any = zeron.context_of("project", p.id)
			local cwd: any = if type(rec) == "table" then (rec.path or rec.folder) else nil
			local device: string? = if type(rec) == "table"
					and type(rec.device) == "string"
					and rec.device ~= ""
				then rec.device
				else nil
			if type(cwd) == "string" and cwd ~= "" then
				return {
					key = `{device or "@here"}|{cwd}`,
					device = device,
					cwd = cwd,
				}
			end
		end
	end
	return {
		key = "@here|all",
		device = nil,
		cwd = nil,
	}
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
		if 0.2126 * r + 0.7152 * g + 0.722 * b > 0.5 then
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

local function commit_row(commit: any): Node
	local subject = one_line(tostring(if type(commit) == "table" then commit.subject or "" else ""), 90)
	if subject == "" then
		subject = zeron.s("untitled")
	end
	local at_num = if type(commit) == "table" then tonumber(commit.at) or 0 else 0
	return ui.text {
		`{os.date("%H:%M", at_num)}  {subject}`,
		weight = "$font.weight.medium",
		text_size = "$font.size.sm",
		line_height = "$font.line.sm",
		color = "$text.primary",
	}
end

local function card_content(c: any, card_expanded: any, card_offset: any): Node
	local held = c.held
	local n = entry_n(held)
	local commits = entry_commits(held)
	local expanded = card_expanded:peek()

	local header = ui.text {
		zeron.t("day_commits", { date = day_label(c.at), n = n }),
		w_full = true,
		text_size = "$font.size.xs",
		line_height = "$font.line.xs",
		color = "$text.secondary",
	}

	if #commits == 0 then
		return ui.column {
			w_full = true,
			gap = "$space.1",
			header,
			ui.text {
				zeron.t("empty"),
				text_size = "$font.size.sm",
				color = "$text.tertiary",
			},
		}
	end

	if not expanded then
		local rows: { Node } = { header }
		local limit = math.min(#commits, MAX_LISTED)
		for i = 1, limit do
			table.insert(rows, commit_row(commits[i]))
		end

		local extra = n - limit
		if extra > 0 then
			if #commits > limit then
				table.insert(
					rows,
					ui.div {
						cursor = "pointer",
						role = "button",
						rounded = "$radius.sm",
						px = 4,
						py = 2,
						mx = -4,
						color = "$text.secondary",
						hover = { bg = "$hover", color = "$text.primary" },
						on_click = function()
							card_expanded:set(true)
						end,
						ui.text {
							zeron.t("more_n", { n = extra }),
							text_size = "$font.size.xs",
							weight = "$font.weight.medium",
						},
					}
				)
			else
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
		end

		return ui.column {
			w_full = true,
			gap = "$space.1",
			table.unpack(rows),
		}
	else
		local scroll_rows: { Node } = {}
		for _, commit in commits do
			table.insert(scroll_rows, commit_row(commit))
		end

		if n > #commits then
			table.insert(
				scroll_rows,
				ui.text {
					zeron.t("more_n", { n = n - #commits }),
					text_size = "$font.size.xs",
					line_height = "$font.line.xs",
					color = "$text.tertiary",
				}
			)
		end

		local show_less_btn = ui.div {
			cursor = "pointer",
			role = "button",
			rounded = "$radius.sm",
			px = 4,
			py = 2,
			mx = -4,
			color = "$text.secondary",
			hover = { bg = "$hover", color = "$text.primary" },
			on_click = function()
				card_expanded:set(false)
				card_offset:set(0)
			end,
			ui.text {
				zeron.t("show_less"),
				text_size = "$font.size.xs",
				weight = "$font.weight.medium",
			},
		}

		return ui.column {
			w_full = true,
			gap = "$space.1",
			header,
			ui.scroll {
				w_full = true,
				max_h = 260,
				offset = card_offset,
				fade = { 10, 10 },
				fade_overflow = true,
				ui.column {
					w_full = true,
					gap = "$space.1",
					table.unpack(scroll_rows),
				},
			},
			show_less_btn,
		}
	end
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
-- as nodes. The canvas reads the theme, active scope/project target, and
-- loaded commits reactively so it repaints immediately when commits arrive,
-- on refresh, on scope/project switch, or on theme switch. Days with commits
-- carry an invisible hover overlay rebuilt via `ui.presence` whenever commit
-- data changes, deferred past the initial build frame so mounting
-- `#chat-composer` stays fast.
local function grid(
	start: number,
	data_state: any,
	visible: () -> boolean,
	overlays_ready: any,
	on_cell_enter: (day: string, first_at: number, held: any, column: number, row: number) -> (),
	on_cell_leave: () -> ()
): Node
	local last_key = ""
	local last_marks: { [number]: number } = {}
	local function marks_of(known: any, rev: number, target_key: string): { [number]: number }
		local matches = type(known) == "table" and known.target_key == target_key
		local key = if matches
			then `{rev}:{target_key}:{known.at or 0}:{known.total or 0}`
			else `empty:{target_key}`
		if key == last_key then
			return last_marks
		end
		local out: { [number]: number } = {}
		local days: any = if matches and type(known.days) == "table" then known.days else nil
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
		ui.div {
			absolute = true,
			left = 0,
			top = 0,
			w = GRID_W,
			h = GRID_H,
			pointer_events = "none",
			opacity = function(): number
				return wash(0, scheme_of())
			end,
			ui.canvas {
				w = GRID_W,
				h = GRID_H,
				draw = function(c: any)
					ui.theme.current:get()
					local ready = overlays_ready:get()
					local shown = visible()
					local marks = if ready and shown
						then marks_of(data_state:get(), tonumber(revision:get()) or 0, target_of(true).key)
						else nil
					for column = 0, COLUMNS - 1 do
						for row = 0, ROWS - 1 do
							if (if marks then (marks[column * 7 + row] or 0) else 0) <= 0 then
								c:rect(
									column * (CELL + GAP),
									row * (CELL + GAP),
									CELL,
									CELL,
									"$text.primary",
									2
								)
							end
						end
					end
				end,
			},
		},
		ui.presence(function(): string
			if not overlays_ready:get() or not visible() then
				return "empty"
			end
			local target = target_of(true)
			local known: any = data_state:get()
			if type(known) ~= "table" or known.target_key ~= target.key or type(known.days) ~= "table" then
				return "empty"
			end
			local rev = tonumber(revision:get()) or 0
			return `{rev}:{target.key}:{known.at or 0}:{known.total or 0}`
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
					local day_str = tostring(day)
					local level = level_of(n)
					table.insert(
						overlays,
						ui.div {
							absolute = true,
							left = column * (CELL + GAP) - 1,
							top = row * (CELL + GAP) - 1,
							w = CELL + 2,
							h = CELL + 2,
							pointer_events = function(): string
								return if visible() then "auto" else "none"
							end,
							on_hover = function(inside: boolean)
								if not visible() then
									return
								end
								if inside then
									on_cell_enter(day_str, first_at, held, column, row)
								else
									on_cell_leave()
								end
							end,
						ui.div {
							absolute = true,
							left = 1,
							top = 1,
							w = CELL,
							h = CELL,
							rounded = ui.raw(2, "a heatmap cell's corner, at GitHub's scale"),
							bg = "$accent",
							opacity = function(): number
								return wash(level, scheme_of())
							end,
							pointer_events = "none",
						},
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
		local target = target_of(true)
		local known: any = data_state:get()
		if type(known) ~= "table" or known.target_key ~= target.key then
			return zeron.s("loading")
		end
		local total: number = tonumber(known.total) or 0
		if known.error and total == 0 then
			if
				known.error == "offline"
				or known.error == "not_installed"
				or known.error == "version_mismatch"
				or known.error == "other_author"
			then
				return zeron.s("remote_unavailable")
			elseif
				known.error == "not_approved"
				or known.error == "off"
				or known.error == "not_allowed"
				or known.error == "not_a_checkout"
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
		local target = target_of(true)
		local known: any = data_state:get()
		local total: number = if type(known) == "table" and known.target_key == target.key
			then tonumber(known.total) or 0
			else 0
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
						return if props.visible() then "auto" else "none"
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
			grid(start, data_state, props.visible, props.overlays_ready, props.on_cell_enter, props.on_cell_leave),
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

		local card = ui.use_state(nil :: any)
		local card_open = ui.use_state(false)
		local card_expanded = ui.use_state(false)
		local card_offset = ui.use_state(0)

		local cell_hovered = false
		local card_hovered = false
		local close_gen = 0
		local open_gen = 0

		local function close_card()
			close_gen += 1
			open_gen += 1
			cell_hovered = false
			card_hovered = false
			if card_open:peek() then
				card_open:set(false)
			end
			card_expanded:set(false)
			card_offset:set(0)
			card:set(nil)
		end

		local function close_soon()
			close_gen += 1
			local gen = close_gen
			ui.after(260, function()
				if gen == close_gen and not cell_hovered and not card_hovered then
					card_open:set(false)
					card_expanded:set(false)
					card_offset:set(0)
					card:set(nil)
				end
			end)
		end

		local function on_cell_enter(day: string, first_at: number, held: any, column: number, row: number)
			close_gen += 1
			cell_hovered = true
			local prev: any = card:peek()
			if type(prev) ~= "table" or prev.day ~= day then
				card_expanded:set(false)
				card_offset:set(0)
			end
			card:set({
				day = day,
				at = first_at,
				held = held,
				column = column,
				row = row,
			})
			if card_open:peek() then
				return
			end
			open_gen += 1
			local gen = open_gen
			ui.after(80, function()
				if gen == open_gen and cell_hovered then
					card_open:set(true)
				end
			end)
		end

		local function on_cell_leave()
			open_gen += 1
			cell_hovered = false
			close_soon()
		end

		local function home(): boolean
			local where = route()
			return type(where) == "table" and where.name == "home"
		end
		local function visible(): boolean
			return home() and show_heatmap:get() ~= false
		end

		-- (Defer building day hover overlays by one tick so initial `#chat-composer`
		-- placement stays fast while the canvas and header appear on frame 1.)
		ui.after(0, function()
			overlays_ready:set(true)
		end)

		-- (`force`: bypasses the service's 5-minute cache to re-read git right
		-- away. A newer read's answer wins; an older one is dropped, even one
		-- from before a reload.)
		local reads = 0
		local function load(force: boolean)
			if show_heatmap:peek() == false then
				return
			end
			local target = target_of(false)
			-- (Prevent overlapping reads for the same target while one is already
			-- in flight, while letting a switch to a different target proceed at
			-- once and letting a stalled read expire after its timeout.)
			local waited = os.time() - (tonumber(pending_at:peek()) or 0)
			if pending:peek() and pending_key:peek() == target.key and waited < 30 then
				return
			end
			reads += 1
			local mine = `{LOAD}:{reads}`
			latest:set(mine)
			pending:set(true)
			pending_at:set(os.time())
			pending_key:set(target.key)
			zeron.service(target.device)
				:call("year", { since = since, force = force, cwd = target.cwd }, { timeout = 30 })
				:after(
					function(value: any)
						if latest:peek() ~= mine then
							return
						end
						pending:set(false)
						pending_at:set(0)
						pending_key:set("")
						value = if type(value) == "table" then value else {}
						revision:set((tonumber(revision:peek()) or 0) + 1)
						local days_map = value.days or {}
						data:set({
							at = os.time(),
							since = since,
							target_key = target.key,
							days = days_map,
							total = value.total or 0,
						})
						local current_card = card:peek()
						if current_card then
							local fresh_held = days_map[current_card.day]
							if not fresh_held or entry_n(fresh_held) == 0 then
								close_card()
							else
								current_card.held = fresh_held
								card:set(table.clone(current_card))
							end
						end
					end,
					function(err: any)
						if latest:peek() ~= mine then
							return
						end
						pending:set(false)
						pending_at:set(0)
						pending_key:set("")
						close_card()
						local reason = zeron.reason(err)
						local prev: any = data:peek()
						local had: any = if type(prev) == "table" and prev.target_key == target.key
							then table.clone(prev)
							else { days = {}, total = 0 }
						had.at = os.time()
						had.since = since
						had.target_key = target.key
						had.error = reason
						revision:set((tonumber(revision:peek()) or 0) + 1)
						data:set(had)
						-- (If the service was still starting up on cold launch,
						-- retry shortly instead of waiting 30 seconds; never
						-- auto-retry permanent or remote refusal reasons.)
						if
							(tonumber(had.total) or 0) == 0
							and reason ~= "not_approved"
							and reason ~= "off"
							and reason ~= "not_allowed"
							and reason ~= "not_installed"
							and reason ~= "version_mismatch"
							and reason ~= "other_author"
							and reason ~= "offline"
							and reason ~= "not_a_checkout"
						then
							ui.after(3000, function()
								if
									home()
									and show_heatmap:peek() ~= false
									and zeron.window(true).shown
									and not pending:peek()
								then
									load(false)
								end
							end)
						end
					end
				)
		end

		-- Five minutes of a grid is enough; a failed read is asked again
		-- sooner, and a stale one when the window comes back to a new chat or
		-- switches target.
		local function due(): boolean
			local known: any = data:peek()
			local target = target_of(false)
			return not (
				type(known) == "table"
				and known.since == since
				and known.target_key == target.key
				and known.error == nil
				and os.time() - (tonumber(known.at) or 0) < REFRESH
			)
		end

		local function handle_setting(key: string, value: any)
			if key ~= "show_heatmap" and key ~= "scope" then
				return
			end
			if key == "show_heatmap" and value == false then
				close_card()
				return
			end
			ui.after(0, function()
				if show_heatmap:peek() ~= false and home() and zeron.window(true).shown and due() then
					load(false)
				end
			end)
		end
		on_setting_changed = handle_setting
		pcall(ui.on_cleanup, function()
			close_card()
			if on_setting_changed == handle_setting then
				on_setting_changed = nil
			end
		end)

		local last_target_key = ""
		ui.effect(function()
			local where = route()
			local win = zeron.window()
			local shown_setting = show_heatmap:get()
			local cur_scope = scope:get()
			if cur_scope == "project" then
				pick:get()
				target_of(true)
			end
			if type(where) ~= "table" or where.name ~= "home" then
				close_card()
				return
			end
			if not win.shown or shown_setting == false then
				close_card()
				return
			end
			local target = target_of(true)
			if last_target_key ~= "" and last_target_key ~= target.key then
				close_card()
			end
			last_target_key = target.key
			if due() then
				load(false)
			end
			-- (Resting here is no reason to leave an old grid up, or a read
			-- that failed while the service was still starting.)
			ui.every(30000, function()
				if home() and show_heatmap:peek() ~= false and zeron.window(true).shown and due() then
					load(false)
				end
			end)
		end)

		local function card_left(column: number): number
			local cell_left = LABELS_W + 6 + column * (CELL + GAP)
			if column < 6 then
				return math.max(0, cell_left)
			elseif column >= COLUMNS - 6 then
				return math.min(WIDTH - CARD_W, cell_left + CELL - CARD_W)
			end
			return math.clamp(cell_left + CELL / 2 - CARD_W / 2, 0, WIDTH - CARD_W)
		end

		local function card_bottom(row: number): number
			return HEIGHT - (GRID_TOP + row * (CELL + GAP)) + 10
		end

		local function DayCard(): Node
			return ui.show(
				function(): boolean
					return visible() and card_open:get() and card:get() ~= nil
				end,
				HoverCard.Card {
					absolute = true,
					left = function(): number
						local c = card:get()
						return if c then card_left(c.column) else 0
					end,
					bottom = function(): number
						local c = card:get()
						return if c then card_bottom(c.row) else 0
					end,
					w = CARD_W,
					p = "$space.3",
					gap = "$space.1",
					pointer_events = "auto",
					on_hover = function(inside: boolean)
						if inside then
							card_hovered = true
							close_gen += 1
						else
							card_hovered = false
							close_soon()
						end
					end,
					ui.presence(function(): string
						local c = card:get()
						if not c then
							return "empty"
						end
						local n = entry_n(c.held)
						local exp = card_expanded:get()
						return `{c.day}:{n}:{exp}`
					end, function(key: string): Node
						if key == "empty" then
							return ui.div {}
						end
						local c = card:peek()
						if not c then
							return ui.div {}
						end
						return card_content(c, card_expanded, card_offset)
					end, { w_full = true }),
				}
			)
		end

		return ui.div {
			id = "heatmap-loclabs",
			absolute = true,
			right = 0,
			bottom = -(HEIGHT + BELOW),
			w = WIDTH,
			h = HEIGHT,
			overflow = "visible",
			-- Informational: it takes no click from the page; only its days
			-- and refresh button answer the pointer, and only when visible.
			pointer_events = "none",
			opacity = function(): number
				return if visible() then 1 else 0
			end,
			Heatmap {
				data = data,
				start = start,
				visible = visible,
				overlays_ready = overlays_ready,
				refresh = function()
					load(true)
				end,
				on_cell_enter = on_cell_enter,
				on_cell_leave = on_cell_leave,
			},
			DayCard(),
		}
	end,
}

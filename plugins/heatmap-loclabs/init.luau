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

type Target = { key: string, device: string?, cwd: string?, project_name: string? }

local left_edge = ui.ref()

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
				local project_name: string? = nil
				if type(p.name) == "string" and p.name ~= "" then
					project_name = p.name
				elseif type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then
					project_name = rec.name
				else
					project_name = string.match(cwd, "([^/\\]+)[/\\]*$")
				end
				return {
					key = `{device or "@here"}|{cwd}`,
					device = device,
					cwd = cwd,
					project_name = project_name,
				}
			end
		end
	end
	return {
		key = "@here|all",
		device = nil,
		cwd = nil,
		project_name = nil,
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

type MonthMark = { name: string, col: number }
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
		if month then
			table.insert(out, { name = MONTHS[month], col = column })
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
	cols_of: () -> number,
	grid_w_of: () -> number,
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
		w = grid_w_of,
		h = GRID_H,
		shrink = 0,
		ui.div {
			absolute = true,
			left = 0,
			top = 0,
			w = grid_w_of,
			h = GRID_H,
			pointer_events = "none",
			opacity = function(): number
				return wash(0, scheme_of())
			end,
			ui.canvas {
				w_full = true,
				h_full = true,
				draw = function(c: any)
					ui.theme.current:get()
					local cols = cols_of()
					local col_start = COLUMNS - cols
					local ready = overlays_ready:get()
					local shown = visible()
					local marks = if ready and shown
						then marks_of(data_state:get(), tonumber(revision:get()) or 0, target_of(true).key)
						else nil
					for column = col_start, COLUMNS - 1 do
						local vis_col = column - col_start
						for row = 0, ROWS - 1 do
							if (if marks then (marks[column * 7 + row] or 0) else 0) <= 0 then
								c:rect(
									vis_col * (CELL + GAP),
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
			local cols = cols_of()
			return `{rev}:{target.key}:{known.at or 0}:{known.total or 0}:{cols}`
		end, function(key: string): Node
			if key == "empty" then
				return ui.div { pointer_events = "none" }
			end
			local known: any = data_state:peek()
			local days: any = if type(known) == "table" and type(known.days) == "table" then known.days else nil
			if not days then
				return ui.div { pointer_events = "none" }
			end
			local cols = cols_of()
			local col_start = COLUMNS - cols
			local gw = cols * CELL + (cols - 1) * GAP
			local overlays: { Node } = {}
			for day, held in days do
				local slot = day_slot(start, tostring(day))
				local n = entry_n(held)
				if slot and n > 0 then
					local column = math.floor(slot / 7)
					if column >= col_start then
						local vis_col = column - col_start
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
								left = vis_col * (CELL + GAP) - 1,
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
			end
			return ui.div {
				absolute = true,
				left = 0,
				top = 0,
				w = gw,
				h = GRID_H,
				pointer_events = "none",
				table.unpack(overlays),
			}
		end, {
			absolute = true,
			left = 0,
			top = 0,
			w = grid_w_of,
			h = GRID_H,
			pointer_events = "none",
		}),
	}
end

local function Heatmap(props: any): Node
	local start: number = props.start
	local data_state: any = props.data
	local cols_of: () -> number = props.cols_of
	local grid_w_of: () -> number = props.grid_w_of
	local box_w_of: () -> number = props.box_w_of
	local all_months = month_marks(start)

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
		if type(target.project_name) == "string" and target.project_name ~= "" then
			local limit = if box_w_of() < 420 then 16 else 24
			return zeron.s("count_project", { n = total, project = one_line(target.project_name, limit) })
		end
		return zeron.s("count", { n = total })
	end

	local function a11y_label(): string
		local target = target_of(true)
		local known: any = data_state:get()
		local total: number = if type(known) == "table" and known.target_key == target.key
			then tonumber(known.total) or 0
			else 0
		if type(target.project_name) == "string" and target.project_name ~= "" then
			return zeron.s("label_project", { n = total, project = target.project_name })
		end
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
			gap = 6,
			ui.row {
				items = "center",
				gap = 2,
				min_w = 0,
				shrink = 1,
				ui.text {
					header_text,
					text_size = "$font.size.xs",
					color = "$text.secondary",
					truncate = true,
					min_w = 0,
					shrink = 1,
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
			ui.show(
				function(): boolean
					return box_w_of() >= 370
				end,
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
				}
			),
		},
		-- The months, over the visible columns they begin in.
		ui.row {
			w_full = true,
			h = MONTH_H,
			gap = 6,
			ui.div { w = LABELS_W, h = MONTH_H, shrink = 0 },
			ui.presence(function(): string
				return tostring(cols_of())
			end, function(key: string): Node
				local cols = tonumber(key) or COLUMNS
				local col_start = COLUMNS - cols
				local gw = cols * CELL + (cols - 1) * GAP
				local months: { Node } = {}
				local last_left = -100
				for _, mark in all_months do
					if mark.col >= col_start then
						local left = (mark.col - col_start) * (CELL + GAP)
						if left <= gw - 22 and left - last_left >= 24 then
							last_left = left
							table.insert(
								months,
								ui.text {
									mark.name,
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
				end
				return ui.div {
					relative = true,
					w = gw,
					h = MONTH_H,
					shrink = 0,
					table.unpack(months),
				}
			end, { h = MONTH_H, shrink = 0 }),
		},
		-- The days down the side, then the weeks.
		ui.row {
			w_full = true,
			h = GRID_H,
			gap = 6,
			ui.column { w = LABELS_W, h = GRID_H, gap = GAP, shrink = 0, table.unpack(labels) },
			grid(
				start,
				data_state,
				props.visible,
				props.overlays_ready,
				cols_of,
				grid_w_of,
				props.on_cell_enter,
				props.on_cell_leave
			),
		},
	}
end

-- Zero-width marker before `#chat-composer` so the heatmap measures the
-- composer's exact live width and stays inside its bounds when narrow.
zeron.place {
	at = "#chat-composer",
	before = function(): Node
		return ui.div {
			ref = left_edge,
			w = 0,
			h = 0,
			shrink = 0,
			pointer_events = "none",
		}
	end,
}

zeron.place {
	at = "#chat-composer",
	after = function(): Node
		local right_edge = ui.ref()
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

		local measured_w = ui.use_state(WIDTH)

		local function edge_x(ref: any): number?
			local ok, el = pcall(function(): any
				return ref:peek()
			end)
			if ok and el ~= nil and type(el.x) == "number" then
				return el.x
			end
			local ok2, list = pcall(function(): any
				return ref:elements()
			end)
			if ok2 and type(list) == "table" and list[1] ~= nil and type(list[1].x) == "number" then
				return list[1].x
			end
			return nil
		end

		local function measure_composer()
			local lx = edge_x(left_edge)
			local rx = edge_x(right_edge)
			if lx and rx then
				local w = math.floor(rx - lx + 0.5)
				if w >= 120 and math.abs(measured_w:peek() - w) >= 1 then
					measured_w:set(w)
				end
			end
		end

		-- Re-measure on window resize, route/home transitions, and initial layout.
		ui.effect(function()
			local win = (ui :: any).window
			if win ~= nil and win.size ~= nil then
				pcall(function()
					win.size:get()
				end)
			end
			home()
			zeron.window(true)
			measure_composer()
			ui.after(0, measure_composer)
			ui.after(48, measure_composer)
		end)

		-- Also catch sidebar drag, panel open/close, and conversation_width changes
		-- while the heatmap is visible on New Chat (no-op unless width changed).
		ui.on_mount(function()
			ui.after(0, measure_composer)
			ui.after(64, measure_composer)
			ui.every(150, function()
				if home() and show_heatmap:peek() ~= false and zeron.window(true).shown then
					measure_composer()
				end
			end)
		end)

		local function composer_w(): number
			return measured_w:get()
		end

		local function cols_of(): number
			local grid_room = math.max(CELL, composer_w() - LABELS_W - 6)
			return math.clamp(math.floor((grid_room + GAP) / (CELL + GAP)), 8, COLUMNS)
		end

		local function grid_w_of(): number
			local cols = cols_of()
			return cols * CELL + (cols - 1) * GAP
		end

		local function box_w_of(): number
			return LABELS_W + 6 + grid_w_of()
		end

		local function right_offset(): number
			return math.max(0, math.floor((composer_w() - box_w_of()) / 2))
		end

		local function card_w_of(): number
			return math.min(CARD_W, box_w_of())
		end

		local function card_left(column: number): number
			local cols = cols_of()
			local col_start = COLUMNS - cols
			local bw = box_w_of()
			local cw = math.min(CARD_W, bw)
			local vis_col = math.max(0, column - col_start)
			local cell_left = LABELS_W + 6 + vis_col * (CELL + GAP)
			if vis_col < 6 then
				return math.max(0, math.min(bw - cw, cell_left))
			elseif vis_col >= cols - 6 then
				return math.max(0, math.min(bw - cw, cell_left + CELL - cw))
			end
			return math.clamp(cell_left + CELL / 2 - cw / 2, 0, math.max(0, bw - cw))
		end

		local function card_bottom(row: number): number
			return HEIGHT - (GRID_TOP + row * (CELL + GAP)) + 10
		end

		local function DayCard(): Node
			return ui.show(
				function(): boolean
					local c = card:get()
					if not visible() or not card_open:get() or c == nil then
						return false
					end
					return c.column >= COLUMNS - cols_of()
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
					w = card_w_of,
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
			ref = right_edge,
			relative = true,
			w = 0,
			h_full = true,
			shrink = 0,
			overflow = "visible",
			pointer_events = "none",
			ui.div {
				id = "heatmap-loclabs",
				absolute = true,
				right = right_offset,
				bottom = -(HEIGHT + BELOW),
				w = box_w_of,
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
					cols_of = cols_of,
					grid_w_of = grid_w_of,
					box_w_of = box_w_of,
					refresh = function()
						load(true)
					end,
					on_cell_enter = on_cell_enter,
					on_cell_leave = on_cell_leave,
				},
				DayCard(),
			},
		}
	end,
}

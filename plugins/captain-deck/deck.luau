--!strict
-- Captain Deck: compact, solid-opaque docked multi-agent orchestration card (v1.2.0 Round 3).
--
-- Designed to dock cleanly above `#chat-composer` (~680-820px x 440px) with 100%
-- solid opaque Zeron surface tokens:
--   * Outer card / header / tab bar / scroll : `$popover.bg`
--   * Nested cards / rows / sub-panels       : `$zeron.menu.solid`
--   * Recessed wells / inputs / drop zones   : `$zeron.window`
--   * Dividers                               : 1px `$border.subtle`
--
-- Layout:
-- 1. Minimalist single-row header: icon + title + compact counts + optional amber
--    Needs You pill on left; quiet Refresh + Draft pill + Close on right.
-- 2. Clean 4-tab bar: Fleet | Launch | Chats | Activity (+ 1-click "+ New" shortcut).
-- 3. Breathable scrollable body (`overscroll = "contain"`), with inline solid
--    sub-panels for Spawn Worker, Attach Chat, Edit Captain, Steer Worker,
--    Delete Captain, and Clear All confirmation (zero nested modal sheets).

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local Dropdown = require("@ds/dropdown")
local EmptyState = require("@ds/empty_state")
local Icon = require("@ds/icon")
local IconButton = require("@ds/icon_button").IconButton
local SearchField = require("@ds/search_field")
local Segmented = require("@ds/segmented")
local Select = require("@ds/select")
local Status = require("@ds/status")
local Switch = require("@ds/switch")
local Text = require("@ds/text")
local TextArea = require("@ds/text_area")
local TextField = require("@ds/text_field")

local ROLES = {
	{ value = "builder", label = "Builder" },
	{ value = "reviewer", label = "Reviewer" },
	{ value = "researcher", label = "Researcher" },
	{ value = "tester", label = "Tester / QA" },
	{ value = "planner", label = "Planner" },
	{ value = "worker", label = "General Worker" },
}

type AttachmentItem = {
	path: string,
	name: string,
	is_image: boolean,
}

local MAX_ATTACHMENTS = 8

local function trim(s: any): string
	if type(s) ~= "string" then
		return ""
	end
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function strip_path_quotes(raw: any): string
	local s = trim(raw)
	if #s >= 2 then
		local first = string.sub(s, 1, 1)
		local last = string.sub(s, -1, -1)
		if (first == '"' and last == '"') or (first == "'" and last == "'") then
			s = trim(string.sub(s, 2, -2))
		end
	end
	return s
end

local function basename_of(path: string): string
	local base = string.match(path, "([^/\\]+)$")
	return if base and base ~= "" then base else path
end

local function is_image_path(path: string): boolean
	local low = string.lower(trim(path))
	return string.match(low, "%.png$") ~= nil
		or string.match(low, "%.jpg$") ~= nil
		or string.match(low, "%.jpeg$") ~= nil
		or string.match(low, "%.webp$") ~= nil
		or string.match(low, "%.gif$") ~= nil
		or string.match(low, "%.bmp$") ~= nil
		or string.match(low, "%.svg$") ~= nil
end

local function normalize_attachment_entries(raw: any): { { path: string, name: string? } }
	local out: { { path: string, name: string? } } = {}
	if type(raw) == "string" then
		local p = strip_path_quotes(raw)
		if p ~= "" then
			table.insert(out, { path = p, name = nil })
		end
	elseif type(raw) == "table" then
		if type(raw.path) == "string" then
			local p = strip_path_quotes(raw.path)
			if p ~= "" then
				table.insert(out, { path = p, name = if type(raw.name) == "string" then trim(raw.name) else nil })
			end
		elseif type(raw.files) == "table" then
			for _, item in raw.files do
				for _, sub in normalize_attachment_entries(item) do
					table.insert(out, sub)
				end
			end
		else
			for _, item in raw do
				if type(item) == "string" then
					local p = strip_path_quotes(item)
					if p ~= "" then
						table.insert(out, { path = p, name = nil })
					end
				elseif type(item) == "table" and type(item.path) == "string" then
					local p = strip_path_quotes(item.path)
					if p ~= "" then
						table.insert(out, { path = p, name = if type(item.name) == "string" then trim(item.name) else nil })
					end
				end
			end
		end
	end
	return out
end

local function format_age(ts: number?): string
	if not ts or ts <= 0 then
		return ""
	end
	local diff = math.max(0, os.time() - ts)
	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		return `{math.floor(diff / 60)}m ago`
	elseif diff < 86400 then
		return `{math.floor(diff / 3600)}h ago`
	end
	return `{math.floor(diff / 86400)}d ago`
end

local function utf8_truncate(s: string, max_bytes: number): (string, boolean)
	if #s <= max_bytes then
		return s, false
	end
	local cut = max_bytes
	while cut > 1 do
		local b = string.byte(s, cut)
		if b and b >= 128 and b < 192 then
			cut -= 1
		else
			break
		end
	end
	if cut > 1 then
		local b = string.byte(s, cut)
		if b and b >= 192 then
			cut -= 1
		end
	end
	return trim(string.sub(s, 1, cut)) .. "…", true
end

local function collapse_preview(text: string?, max_chars: number): (string, boolean)
	local raw = trim(text)
	if raw == "" then
		return "", false
	end
	local single_line = (string.gsub(raw, "%s+", " "))
	local had_newlines = string.find(raw, "\n", 1, true) ~= nil
	local out, truncated = utf8_truncate(single_line, max_chars)
	return out, truncated or had_newlines
end

local function compact_status_label(status: string?): string
	if status == "running" then
		return "running"
	elseif status == "awaiting_input" then
		return "needs input"
	elseif status == "completed" then
		return "completed"
	elseif status == "errored" then
		return "errored"
	elseif status == "limited" then
		return "limited"
	end
	return "idle"
end

local function divider(): Node
	return ui.div {
		h = 1,
		w_full = true,
		shrink = 0,
		bg = "$border.subtle",
		aria_hidden = true,
	}
end

local function solid_textarea_box(child: Node, min_height: number?): Node
	return ui.div {
		w_full = true,
		min_h = min_height,
		rounded = "$radius.md",
		bg = "$zeron.window",
		child,
	}
end

local function field_block(label: string, control_node: Node, hint: string?): Node
	return ui.column {
		w_full = true,
		gap = "$space.1",
		ui.text {
			label,
			text_size = "$font.size.xs",
			weight = "$font.weight.medium",
			color = "$text.secondary",
		},
		if hint and hint ~= ""
			then ui.text {
				hint,
				text_size = "$font.size.xs",
				color = "$text.tertiary",
				wrap = true,
			}
			else nil,
		control_node,
	}
end

export type DeckProps = {
	page: any?,
	panel: any?,
	on_close: (() -> ())?,
}

return function(zeron: any, client: any): (props: DeckProps) -> Node
	local function short_model_name(harness: string?, model: string?): string
		if type(client.short_model) == "function" then
			local ok, res = pcall(client.short_model, harness, model)
			if ok and type(res) == "string" then
				return res
			end
		end
		local m = trim(model)
		if m == "" then
			return ""
		end
		local h = string.lower(trim(harness))
		local lm = string.lower(m)
		if h ~= "" then
			local p1 = h .. "/"
			if string.sub(lm, 1, #p1) == p1 then
				return string.sub(m, #p1 + 1)
			end
			local p2 = h .. ":"
			if string.sub(lm, 1, #p2) == p2 then
				return string.sub(m, #p2 + 1)
			end
		end
		local slash = string.find(m, "/", 1, true)
		if slash and slash < #m then
			local prefix = string.lower(string.sub(m, 1, slash - 1))
			if
				prefix == h
				or prefix == "opencode"
				or prefix == "openai"
				or prefix == "anthropic"
				or prefix == "google"
				or prefix == "openrouter"
			then
				return string.sub(m, slash + 1)
			end
		end
		return m
	end

	local function format_harness_model(harness: string?, model: string?): string
		local h = trim(harness)
		local sm = short_model_name(h, model)
		if h ~= "" and sm ~= "" then
			if string.lower(h) == string.lower(sm) then
				return h
			end
			return `{h} · {sm}`
		elseif h ~= "" then
			return h
		elseif sm ~= "" then
			return sm
		end
		return ""
	end

	return ui.component(function(props: DeckProps): Node
		local panel = props.panel

		local initial_s = client.state:peek()
		local initial_has_caps = type(initial_s) == "table"
			and type(initial_s.captains) == "table"
			and next(initial_s.captains) ~= nil

		-- Tabs: "fleet" | "launch" | "chats" | "activity"
		local active_tab = ui.use_state(if initial_has_caps then "fleet" else "launch")
		local query = ui.use_state("")

		-- Inline sub-panels: "none" | "spawn" | "attach" | "edit" | "steer" | "delete" | "clear_all"
		local active_panel = ui.use_state("none")

		-- Per-Captain collapsible state for Live Digest & Shared Rules (default collapsed)
		local expanded_digests: { [string]: boolean } = {}
		local expanded_rules: { [string]: boolean } = {}
		local expand_rev = ui.use_state(0)

		-- Launch tab composer state
		local wf_preset = ui.use_state("build_review")
		local wf_captain_id = ui.use_state("")
		local wf_captain_name = ui.use_state("")
		local wf_project = ui.use_state("")
		local wf_primary_harness = ui.use_state("")
		local wf_primary_custom = ui.use_state("")
		local wf_primary_model = ui.use_state("" :: string?)
		local wf_secondary_harness = ui.use_state("")
		local wf_secondary_custom = ui.use_state("")
		local wf_secondary_model = ui.use_state("" :: string?)
		local wf_task = ui.use_state("")
		local wf_subtasks = ui.use_state("")
		local wf_rules = ui.use_state("")
		local wf_auto_report = ui.use_state(true)
		local wf_options_open = ui.use_state(false)
		local wf_busy = ui.use_state(false)
		local launch_attachments = ui.use_state({} :: { AttachmentItem })
		local launch_att_hover = ui.use_state(false)
		local launch_att_open = ui.use_state(false)
		local launch_att_path = ui.use_state("")

		-- Edit Captain sub-panel state
		local ec_chat_id = ui.use_state("")
		local ec_name = ui.use_state("")
		local ec_mission = ui.use_state("")
		local ec_rules = ui.use_state("")
		local ec_digest = ui.use_state("")
		local ec_auto_report = ui.use_state(true)
		local ec_sched_mins = ui.use_state("")
		local ec_sched_prompt = ui.use_state("")
		local ec_busy = ui.use_state(false)

		-- Spawn Worker sub-panel state
		local sw_captain_id = ui.use_state("")
		local sw_captain_name = ui.use_state("Captain")
		local sw_role = ui.use_state("builder")
		local sw_task = ui.use_state("")
		local sw_prompt = ui.use_state("")
		local sw_harness = ui.use_state("")
		local sw_custom_harness = ui.use_state("")
		local sw_model = ui.use_state("" :: string?)
		local sw_project = ui.use_state("")
		local sw_enable_handoff = ui.use_state(false)
		local sw_handoff_role = ui.use_state("reviewer")
		local sw_handoff_harness = ui.use_state("")
		local sw_handoff_prompt = ui.use_state(
			"Review the previous worker's output read-only. Check actual files and git diff, list Critical vs Minor issues.\n\nPrevious report:\n{{REPORT}}"
		)
		local sw_busy = ui.use_state(false)
		local spawn_attachments = ui.use_state({} :: { AttachmentItem })
		local sw_att_hover = ui.use_state(false)
		local sw_att_open = ui.use_state(false)
		local sw_att_path = ui.use_state("")

		-- Attach existing chat sub-panel state
		local at_chat_id = ui.use_state("")
		local at_chat_title = ui.use_state("")
		local at_captain_id = ui.use_state("")
		local at_role = ui.use_state("worker")
		local at_task = ui.use_state("")
		local at_busy = ui.use_state(false)

		-- Steer Worker sub-panel state
		local st_chat_id = ui.use_state("")
		local st_worker_title = ui.use_state("")
		local st_worker_role = ui.use_state("worker")
		local st_captain_name = ui.use_state("")
		local st_status = ui.use_state("idle")
		local st_text = ui.use_state("")
		local st_busy = ui.use_state(false)
		local steer_attachments = ui.use_state({} :: { AttachmentItem })
		local st_att_hover = ui.use_state(false)
		local st_att_open = ui.use_state(false)
		local st_att_path = ui.use_state("")

		-- Delete / Demote Captain confirmation sub-panel state
		local del_chat_id = ui.use_state("")
		local del_name = ui.use_state("")
		local del_crew_count = ui.use_state(0)
		local del_busy = ui.use_state(false)

		-- Bulk Clear All confirmation sub-panel state
		local clear_events_opt = ui.use_state(true)
		local clear_all_busy = ui.use_state(false)

		local function compute_dirty(): boolean
			if
				trim(wf_task:get()) ~= ""
				or trim(wf_subtasks:get()) ~= ""
				or trim(wf_captain_name:get()) ~= ""
				or trim(wf_rules:get()) ~= ""
				or #launch_attachments:get() > 0
			then
				return true
			end
			local p = active_panel:get()
			if p == "edit" then
				return true
			elseif p == "spawn" then
				return trim(sw_task:get()) ~= "" or trim(sw_prompt:get()) ~= "" or #spawn_attachments:get() > 0
			elseif p == "steer" then
				return trim(st_text:get()) ~= "" or #steer_attachments:get() > 0
			elseif p == "attach" then
				return trim(at_task:get()) ~= ""
			end
			return false
		end

		ui.effect(function()
			local dirty = compute_dirty()
			if type(client.set_deck_dirty) == "function" then
				pcall(client.set_deck_dirty, dirty)
			end
		end)

		if type(ui.on_cleanup) == "function" then
			pcall(ui.on_cleanup, function()
				if type(client.set_deck_dirty) == "function" then
					pcall(client.set_deck_dirty, false)
				end
			end)
		end

		local function add_attachments(att_state: State<{ AttachmentItem }>, raw_input: any): number
			local entries = normalize_attachment_entries(raw_input)
			if #entries == 0 then
				return 0
			end
			local current = att_state:peek() or {}
			local next_list: { AttachmentItem } = {}
			local seen: { [string]: boolean } = {}
			for _, item in current do
				table.insert(next_list, item)
				seen[item.path] = true
			end
			local added = 0
			local hit_limit = false
			for _, entry in entries do
				if #next_list >= MAX_ATTACHMENTS then
					hit_limit = true
					break
				end
				if not seen[entry.path] then
					seen[entry.path] = true
					local name = if entry.name and entry.name ~= "" then entry.name else basename_of(entry.path)
					table.insert(next_list, {
						path = entry.path,
						name = name,
						is_image = is_image_path(entry.path),
					})
					added += 1
				end
			end
			if added > 0 then
				att_state:set(next_list)
			end
			if hit_limit then
				zeron.toast(zeron.s("toast.max_attachments"))
			end
			return added
		end

		local function remove_attachment(att_state: State<{ AttachmentItem }>, target_path: string)
			local current = att_state:peek() or {}
			local next_list: { AttachmentItem } = {}
			for _, item in current do
				if item.path ~= target_path then
					table.insert(next_list, item)
				end
			end
			att_state:set(next_list)
		end

		local function attachment_paths(att_state: State<{ AttachmentItem }>): { string }?
			local current = att_state:peek() or {}
			if #current == 0 then
				return nil
			end
			local paths: { string } = {}
			for _, item in current do
				table.insert(paths, item.path)
			end
			return paths
		end

		local function can_close_deck(): boolean
			return type(props.on_close) == "function" or type(client.close_deck) == "function"
		end

		local function close_deck()
			if type(client.set_deck_dirty) == "function" then
				pcall(client.set_deck_dirty, false)
			end
			if type(props.on_close) == "function" then
				pcall(props.on_close)
			elseif type(client.close_deck) == "function" then
				pcall(client.close_deck)
			end
		end

		local function open_chat_and_close(chat_id: string)
			pcall(zeron.open, { session = chat_id })
			close_deck()
		end

		local function open_inspector_and_close(captain_id: string)
			client.open_inspector(panel, captain_id)
			close_deck()
		end

		local function close_panel()
			sw_att_hover:set(false)
			st_att_hover:set(false)
			active_panel:set("none")
		end

		local function toggle_digest(cid: string)
			expanded_digests[cid] = not expanded_digests[cid]
			expand_rev:set(expand_rev:peek() + 1)
		end

		local function toggle_rules(cid: string)
			expanded_rules[cid] = not expanded_rules[cid]
			expand_rev:set(expand_rev:peek() + 1)
		end

		local function captain_count(): number
			local s = client.state:get()
			local n = 0
			for _ in (s and s.captains or {}) do
				n += 1
			end
			return n
		end

		local function worker_count(): number
			local s = client.state:get()
			local n = 0
			for _ in (s and s.workers or {}) do
				n += 1
			end
			return n
		end

		local function unassigned_chat_count(): number
			local s = client.state:get() or {}
			local caps = s.captains or {}
			local workers = s.workers or {}
			local n = 0
			for id in zeron.sessions() do
				if not caps[id] and not workers[id] then
					n += 1
				end
			end
			return n
		end

		local function event_count(): number
			local s = client.state:get()
			return if s and type(s.events) == "table" then #s.events else 0
		end

		local function captain_picker_options(include_new: boolean): { any }
			local opts: { any } = {}
			if include_new then
				table.insert(opts, { value = "", label = "Auto-create new Captain" })
			end
			local s = client.state:get()
			local list: { any } = {}
			for _, cap in (s and s.captains or {}) do
				table.insert(list, cap)
			end
			table.sort(list, function(a: any, b: any): boolean
				return (a.updated_at or 0) > (b.updated_at or 0)
			end)
			for _, cap in list do
				table.insert(opts, { value = cap.chat_id, label = cap.name or client.session_title(cap.chat_id) })
			end
			return opts
		end

		local function unassigned_chat_options(): { any }
			local s = client.state:get() or {}
			local caps = s.captains or {}
			local workers = s.workers or {}
			local list: { any } = {}
			for id, sess in zeron.sessions() do
				if not caps[id] and not workers[id] then
					local title = if type(sess.title) == "string" and sess.title ~= ""
						then sess.title
						else string.sub(id, 1, 8)
					table.insert(list, { id = id, title = title, updated = sess.updated or 0 })
				end
			end
			table.sort(list, function(a: any, b: any): boolean
				return a.updated > b.updated
			end)
			local opts: { any } = {}
			for _, item in list do
				table.insert(opts, { value = item.id, label = item.title })
			end
			if #opts == 0 then
				table.insert(opts, { value = "", label = "No unassigned chats available" })
			end
			return opts
		end

		-- Searchable 360px Dropdown for model selection, solid opaque `$zeron.window` trigger
		local function model_items_for(harness_id: string?): { Dropdown.Item }
			local raw = client.models_for(harness_id)
			local items: { Dropdown.Item } = {}
			for _, m in raw do
				local val = if type(m.value) == "string" then m.value else ""
				local lbl = if type(m.label) == "string" and m.label ~= "" then m.label else val
				table.insert(items, {
					value = val,
					label = lbl,
					hint = if type(m.hint) == "string" and m.hint ~= "" then m.hint else nil,
					mark = if type(m.mark) == "string" and m.mark ~= "" then m.mark :: any else nil,
					icon = if val == "" then "settings" :: any else nil,
				})
			end
			return items
		end

		local function model_dropdown(
			model_state: State<string?>,
			harness_state: State<string>,
			custom_state: State<string>?
		): Node
			local function current_harness(): string
				if custom_state then
					local c = trim(custom_state:get())
					if c ~= "" then
						return c
					end
				end
				return harness_state:get()
			end

			local function current_items(): { Dropdown.Item }
				return model_items_for(current_harness())
			end

			local function chosen_label(): string
				local v = trim(model_state:get())
				if v == "" then
					return zeron.s("deck.composer.model_default")
				end
				for _, item in current_items() do
					if item.value == v then
						return item.label
					end
				end
				return short_model_name(current_harness(), v)
			end

			return Dropdown {
				value = model_state,
				items = current_items,
				width = 360,
				mark = true,
				search = zeron.s("deck.composer.search_models"),
				placeholder = zeron.s("deck.composer.model_default"),
				label = zeron.s("deck.composer.label_model"),
				placement = { side = "bottom", align = "start", offset = 4 },
				trigger = function(menu: Dropdown.Menu): Node
					return ui.button {
						w_full = true,
						h = 28,
						px = "$space.2",
						gap = "$space.2",
						items = "center",
						justify = "between",
						rounded = "$radius.md",
						bg = "$zeron.window",
						border = 1,
						border_color = function(): string
							return if menu.open:get() then "$accent" else "$border"
						end,
						hover = { bg = "$zeron.menu.solid", border_color = "$border.strong" },
						active = { bg = "$zeron.menu.solid" },
						cursor = "pointer",
						on_click = menu.toggle,
						ui.text {
							chosen_label,
							grow = 1,
							min_w = 0,
							truncate = true,
							text_size = "$font.size.xs",
							color = function(): string
								return if trim(model_state:get()) == "" then "$text.secondary" else "$text.primary"
							end,
						},
						Icon { name = "alt-arrow-down", size = 11, color = "$text.tertiary" },
					}
				end,
			}
		end

		local function open_spawn_for(cap: any)
			sw_captain_id:set(cap.chat_id)
			sw_captain_name:set(cap.name or "Captain")
			sw_role:set("builder")
			sw_task:set("")
			sw_prompt:set("")
			spawn_attachments:set({})
			sw_att_hover:set(false)
			sw_att_open:set(false)
			sw_att_path:set("")
			sw_enable_handoff:set(false)
			active_panel:set("spawn")
		end

		local function open_edit_for(cap: any)
			ec_chat_id:set(cap.chat_id)
			ec_name:set(cap.name or "Captain")
			ec_mission:set(cap.mission or "")
			ec_rules:set(cap.rules or "")
			ec_digest:set(cap.digest or "")
			ec_auto_report:set(cap.auto_report ~= false)
			ec_sched_mins:set(if cap.schedule_mins and cap.schedule_mins > 0 then tostring(cap.schedule_mins) else "")
			ec_sched_prompt:set(cap.schedule_prompt or "")
			active_panel:set("edit")
		end

		local function open_attach_for(chat_id: string, title: string, preselected_captain_id: string?)
			at_chat_id:set(chat_id)
			at_chat_title:set(title)
			at_task:set(title)
			at_role:set("worker")
			if preselected_captain_id and preselected_captain_id ~= "" then
				at_captain_id:set(preselected_captain_id)
			else
				local opts = captain_picker_options(false)
				if #opts > 0 then
					at_captain_id:set(opts[1].value)
				else
					at_captain_id:set("")
				end
			end
			active_panel:set("attach")
		end

		local function open_attach_from_captain(cap: any)
			local chat_opts = unassigned_chat_options()
			local first_chat = if #chat_opts > 0 then chat_opts[1].value else ""
			local first_label = if #chat_opts > 0 and first_chat ~= "" then chat_opts[1].label else "Attached chat"
			open_attach_for(first_chat, first_label, cap.chat_id)
		end

		local function open_steer_for(w: any, captain_name: string)
			local title = trim(w.task)
			if title == "" then
				title = client.session_title(w.chat_id)
			end
			st_chat_id:set(w.chat_id)
			st_worker_title:set(title)
			st_worker_role:set(w.role or "worker")
			st_captain_name:set(captain_name)
			st_status:set(w.status or "idle")
			st_text:set("")
			steer_attachments:set({})
			st_att_hover:set(false)
			st_att_open:set(false)
			st_att_path:set("")
			active_panel:set("steer")
		end

		local function open_delete_for(cap: any, crew_total: number)
			local cap_name = trim(cap.name)
			if cap_name == "" then
				cap_name = client.session_title(cap.chat_id)
			end
			del_chat_id:set(cap.chat_id)
			del_name:set(cap_name)
			del_crew_count:set(crew_total)
			active_panel:set("delete")
		end

		local function open_clear_all()
			clear_events_opt:set(true)
			active_panel:set("clear_all")
		end

		local function submit_composer()
			if wf_busy:peek() then
				return
			end
			local mode = wf_preset:peek()
			local task = trim(wf_task:peek())
			local custom_title = trim(wf_captain_name:peek())
			if task == "" then
				if mode == "captain" and custom_title ~= "" then
					task = custom_title
				else
					zeron.toast("Enter a mission or task description first")
					return
				end
			end

			wf_busy:set(true)
			local p_custom = trim(wf_primary_custom:peek())
			local s_custom = trim(wf_secondary_custom:peek())
			local primary_h = if p_custom ~= "" then p_custom else wf_primary_harness:peek()
			local secondary_h = if s_custom ~= "" then s_custom else wf_secondary_harness:peek()
			local primary_m = trim(wf_primary_model:peek())
			local secondary_m = trim(wf_secondary_model:peek())
			local atts = attachment_paths(launch_attachments)

			local function clear_launch_draft()
				wf_task:set("")
				wf_subtasks:set("")
				wf_captain_name:set("")
				wf_rules:set("")
				launch_attachments:set({})
				launch_att_hover:set(false)
				launch_att_open:set(false)
				launch_att_path:set("")
			end

			if mode == "captain" then
				local cap_name = if custom_title ~= "" then custom_title else string.sub(task, 1, 36)
				client.call("create_captain", {
					name = cap_name,
					mission = task,
					rules = wf_rules:peek(),
					prompt = task,
					harness = primary_h,
					model = primary_m,
					project = wf_project:peek(),
					auto_report = wf_auto_report:peek(),
					attachments = atts,
				}):after(function(cap: any)
					wf_busy:set(false)
					clear_launch_draft()
					active_tab:set("fleet")
					zeron.toast(zeron.s("toast.captain_created"))
					if cap and cap.chat_id and panel then
						client.open_inspector(panel, cap.chat_id)
					end
				end, function()
					wf_busy:set(false)
				end)
				return
			end

			client.call("launch_workflow", {
				preset = mode,
				captain_id = wf_captain_id:peek(),
				captain_name = if custom_title ~= "" then custom_title else nil,
				project = wf_project:peek(),
				primary_harness = primary_h,
				primary_model = primary_m,
				secondary_harness = secondary_h,
				secondary_model = secondary_m,
				task = task,
				subtasks = wf_subtasks:peek(),
				rules = wf_rules:peek(),
				auto_report = wf_auto_report:peek(),
				attachments = atts,
			}):after(function(res: any)
				wf_busy:set(false)
				clear_launch_draft()
				active_tab:set("fleet")
				zeron.toast(zeron.s("toast.workflow_launched"))
				if res and res.captain_id and panel then
					client.open_inspector(panel, res.captain_id)
				end
			end, function()
				wf_busy:set(false)
			end)
		end

		local function submit_edit_captain()
			if ec_busy:peek() then
				return
			end
			local cid = trim(ec_chat_id:peek())
			if cid == "" then
				return
			end
			ec_busy:set(true)
			local mins = tonumber(ec_sched_mins:peek()) or 0
			client.call("update_captain", {
				chat_id = cid,
				name = ec_name:peek(),
				mission = ec_mission:peek(),
				rules = ec_rules:peek(),
				digest = ec_digest:peek(),
				auto_report = ec_auto_report:peek(),
				schedule_mins = mins,
				schedule_prompt = ec_sched_prompt:peek(),
			}):after(function()
				ec_busy:set(false)
				active_panel:set("none")
				zeron.toast(zeron.s("toast.saved"))
			end, function()
				ec_busy:set(false)
			end)
		end

		local function submit_spawn_worker()
			if sw_busy:peek() then
				return
			end
			local prompt = trim(sw_prompt:peek())
			if prompt == "" then
				zeron.toast("Enter a prompt for the worker")
				return
			end
			sw_busy:set(true)
			local custom = trim(sw_custom_harness:peek())
			local harness = if custom ~= "" then custom else sw_harness:peek()
			local handoff: any = nil
			if sw_enable_handoff:peek() then
				handoff = {
					role = sw_handoff_role:peek(),
					harness = sw_handoff_harness:peek(),
					prompt_template = sw_handoff_prompt:peek(),
				}
			end
			client.call("spawn_worker", {
				captain_id = sw_captain_id:peek(),
				role = sw_role:peek(),
				task = sw_task:peek(),
				prompt = prompt,
				harness = harness,
				model = trim(sw_model:peek()),
				project = sw_project:peek(),
				handoff = handoff,
				attachments = attachment_paths(spawn_attachments),
			}):after(function()
				sw_busy:set(false)
				active_panel:set("none")
				sw_task:set("")
				sw_prompt:set("")
				spawn_attachments:set({})
				sw_att_hover:set(false)
				sw_att_open:set(false)
				sw_att_path:set("")
				zeron.toast(zeron.s("toast.worker_spawned"))
			end, function()
				sw_busy:set(false)
			end)
		end

		local function submit_attach()
			if at_busy:peek() then
				return
			end
			local cid = trim(at_captain_id:peek())
			local wchat = trim(at_chat_id:peek())
			if cid == "" then
				zeron.toast("Choose a Captain first")
				return
			end
			if wchat == "" then
				zeron.toast("Choose an unassigned chat to attach")
				return
			end
			at_busy:set(true)
			client.call("attach_worker", {
				captain_id = cid,
				worker_chat = wchat,
				role = at_role:peek(),
				task = at_task:peek(),
			}):after(function()
				at_busy:set(false)
				active_panel:set("none")
				zeron.toast(zeron.s("toast.worker_attached"))
			end, function()
				at_busy:set(false)
			end)
		end

		local function submit_steer(mode: string)
			if st_busy:peek() then
				return
			end
			local cid = trim(st_chat_id:peek())
			local txt = trim(st_text:peek())
			if cid == "" or txt == "" then
				zeron.toast("Enter a message for this worker")
				return
			end
			st_busy:set(true)
			client.call("message_chat", {
				chat_id = cid,
				text = txt,
				mode = mode,
				attachments = attachment_paths(steer_attachments),
			}):after(function()
				st_busy:set(false)
				st_text:set("")
				steer_attachments:set({})
				st_att_hover:set(false)
				st_att_open:set(false)
				st_att_path:set("")
				active_panel:set("none")
				zeron.toast(zeron.s("toast.message_sent"))
			end, function()
				st_busy:set(false)
			end)
		end

		local function submit_delete_captain()
			if del_busy:peek() then
				return
			end
			local cid = trim(del_chat_id:peek())
			if cid == "" then
				return
			end
			local name = del_name:peek()
			del_busy:set(true)
			client.call("remove_captain", { chat_id = cid }):after(function()
				del_busy:set(false)
				active_panel:set("none")
				zeron.toast(`Demoted {name}`)
			end, function()
				del_busy:set(false)
			end)
		end

		local function submit_clear_all()
			if clear_all_busy:peek() then
				return
			end
			clear_all_busy:set(true)
			local inc_events = clear_events_opt:peek() == true
			local p = if type(client.clear_all) == "function"
				then client.clear_all(inc_events)
				else client.call("clear_all", { include_events = inc_events })
			local function finish_ok()
				clear_all_busy:set(false)
				query:set("")
				active_panel:set("none")
				active_tab:set("fleet")
				zeron.toast(zeron.s("toast.cleared_all"))
			end
			if p and type(p.after) == "function" then
				p:after(finish_ok, function()
					clear_all_busy:set(false)
				end)
			else
				finish_ok()
			end
		end

		local function matches_query(cap: any, crew: { any }, q: string): boolean
			if q == "" then
				return true
			end
			local needle = string.lower(q)
			local hay = string.lower(`{cap.name or ""} {cap.mission or ""} {cap.harness or ""} {cap.model or ""}`)
			if string.find(hay, needle, 1, true) then
				return true
			end
			for _, w in crew do
				local wh = string.lower(`{w.role or ""} {w.task or ""} {w.harness or ""} {w.model or ""} {w.status or ""}`)
				if string.find(wh, needle, 1, true) then
					return true
				end
			end
			return false
		end

		-- ── Collapsible Vertical Info Well (Live Digest / Shared Rules) ───
		local function build_collapsible_well(
			label: string,
			label_color: string,
			raw_text: string,
			is_expanded: boolean,
			on_toggle: () -> ()
		): Node
			local preview, _ = collapse_preview(raw_text, 140)
			return ui.column {
				w_full = true,
				rounded = "$radius.md",
				bg = "$zeron.window",
				border = 1,
				border_color = "$border.subtle",
				px = "$space.2",
				py = "$space.2",
				gap = "$space.1",
				ui.row {
					w_full = true,
					items = "center",
					justify = "between",
					gap = "$space.2",
					ui.text {
						label,
						color = label_color,
						weight = "$font.weight.medium",
						text_size = "$font.size.xs",
					},
					Button {
						size = "xs",
						tone = "ghost",
						on_click = on_toggle,
						Icon { name = if is_expanded then "alt-arrow-up" else "alt-arrow-down", size = 11 },
						if is_expanded then zeron.s("deck.fleet.collapse") else zeron.s("deck.fleet.expand"),
					},
				},
				ui.text {
					if is_expanded then raw_text else preview,
					w_full = true,
					color = "$text.secondary",
					text_size = "$font.size.xs",
					wrap = true,
				},
			}
		end

		-- ── Reusable Attachment-Capable Prompt Well ────────────────────
		local function build_attachment_prompt_box(opts: {
			text_state: State<string>,
			placeholder: string | () -> string,
			rows: number?,
			max_rows: number?,
			min_height: number?,
			attachments: State<{ AttachmentItem }>,
			hovering: State<boolean>,
			path_open: State<boolean>,
			path_text: State<string>,
		}): Node
			local function add_from_input()
				local raw = strip_path_quotes(opts.path_text:peek())
				if raw == "" then
					zeron.toast(zeron.s("toast.enter_path"))
					return
				end
				add_attachments(opts.attachments, raw)
				opts.path_text:set("")
			end

			local function handle_clipboard_value(val: any)
				local cleaned = strip_path_quotes(val)
				if cleaned ~= "" then
					add_attachments(opts.attachments, cleaned)
				else
					zeron.toast(zeron.s("toast.clipboard_empty"))
				end
			end

			local function paste_from_clipboard()
				local ok_clip, clip_res = pcall(function(): any
					local cb = (ui :: any).clipboard
					if type(cb) == "table" and type(cb.read) == "function" then
						return cb.read()
					end
					return nil
				end)
				if not ok_clip then
					zeron.toast(zeron.s("toast.clipboard_empty"))
					return
				end
				if type(clip_res) == "table" and type(clip_res.after) == "function" then
					clip_res:after(function(val: any)
						handle_clipboard_value(val)
					end, function()
						zeron.toast(zeron.s("toast.clipboard_empty"))
					end)
				else
					handle_clipboard_value(clip_res)
				end
			end

			return ui.column {
				w_full = true,
				gap = "$space.1",
				ui.column {
					w_full = true,
					min_h = opts.min_height,
					rounded = "$radius.md",
					bg = "$zeron.window",
					border = 1,
					border_color = function(): string
						return if opts.hovering:get() then "$accent" else "$border"
					end,
					on_file_hover = function(active: any)
						opts.hovering:set(not not active)
					end,
					on_file_drop = function(files: any)
						opts.hovering:set(false)
						add_attachments(opts.attachments, files)
					end,
					TextArea {
						value = opts.text_state,
						placeholder = opts.placeholder,
						rows = opts.rows or 3,
						max_rows = opts.max_rows or 4,
						size = "sm",
						w_full = true,
					},
					ui.show(function(): boolean
						return opts.hovering:get()
					end, ui.row {
						w_full = true,
						px = "$space.2",
						py = "$space.1",
						gap = "$space.1",
						items = "center",
						bg = "$zeron.menu.solid",
						rounded = "$radius.sm",
						Icon { name = "gallery", size = 12, color = "$accent" },
						ui.text {
							zeron.s("deck.attachments.drop_hint"),
							text_size = "$font.size.xs",
							weight = "$font.weight.medium",
							color = "$accent",
						},
					}),
				},

				-- Attachment Preview Chips Row
				ui.show(function(): boolean
					return #opts.attachments:get() > 0
				end, ui.presence(function(): string
					local list = opts.attachments:get()
					local parts: { string } = {}
					for _, item in list do
						table.insert(parts, item.path)
					end
					return table.concat(parts, "|")
				end, function(): Node
					local list = opts.attachments:peek() or {}
					if #list == 0 then
						return ui.div {}
					end
					local chips: { Node } = {}
					for _, item in list do
						local item_path = item.path
						local thumb: Node
						if item.is_image then
							local ok_img, img_node = pcall(ui.image, {
								src = item_path,
								w = 20,
								h = 20,
								rounded = "$radius.sm",
								fit = "cover",
							})
							if ok_img and img_node ~= nil then
								thumb = img_node
							else
								thumb = Icon { name = "gallery", size = 13, color = "$accent" }
							end
						else
							thumb = Icon { name = "document", size = 13, color = "$text.secondary" }
						end
						table.insert(
							chips,
							ui.row {
								shrink = 0,
								bg = "$zeron.menu.solid",
								border = 1,
								border_color = "$border.strong",
								rounded = "$radius.md",
								px = "$space.2",
								py = "$space.1",
								gap = "$space.1",
								items = "center",
								tooltip = item_path,
								thumb,
								ui.text {
									item.name,
									max_w = 130,
									truncate = true,
									text_size = "$font.size.xs",
									color = "$text.primary",
								},
								ui.button {
									w = 16,
									h = 16,
									rounded = "$radius.sm",
									items = "center",
									justify = "center",
									bg = "$zeron.menu.solid",
									hover = { bg = "$zeron.window" },
									cursor = "pointer",
									tooltip = zeron.s("deck.attachments.remove"),
									on_click = function()
										remove_attachment(opts.attachments, item_path)
									end,
									Icon { name = "close", size = 10, color = "$text.tertiary" },
								},
							}
						)
					end
					return ui.row {
						w_full = true,
						flex_wrap = true,
						items = "center",
						gap = "$space.1",
						table.unpack(chips),
					}
				end, { w_full = true })),

				-- Compact Attachment Toolbar (+ Image / File toggle & drag hint)
				ui.row {
					w_full = true,
					items = "center",
					justify = "between",
					gap = "$space.2",
					ui.row {
						items = "center",
						gap = "$space.2",
						Button {
							size = "xs",
							tone = "ghost",
							on_click = function()
								opts.path_open:set(not opts.path_open:peek())
							end,
							Icon { name = "plus", size = 11 },
							zeron.s("deck.attachments.add_btn"),
						},
						ui.text {
							zeron.s("deck.attachments.drag_tip"),
							text_size = "$font.size.xs",
							color = "$text.tertiary",
							truncate = true,
						},
					},
					ui.show(function(): boolean
						return #opts.attachments:get() > 0
					end, ui.text {
						function(): string
							return `{#opts.attachments:get()}/{MAX_ATTACHMENTS}`
						end,
						text_size = "$font.size.xs",
						color = "$text.tertiary",
						tabular = true,
					}),
				},

				-- Collapsible 1-line Path Bar
				ui.show(function(): boolean
					return opts.path_open:get()
				end, ui.row {
					w_full = true,
					items = "center",
					gap = "$space.1",
					bg = "$zeron.window",
					rounded = "$radius.md",
					border = 1,
					border_color = "$border.subtle",
					px = "$space.2",
					py = "$space.1",
					TextField {
						value = opts.path_text,
						placeholder = zeron.s("deck.attachments.path_placeholder"),
						size = "sm",
						grow = 1,
						min_w = 0,
						on_commit = add_from_input,
					},
					Button {
						size = "xs",
						tone = "secondary",
						on_click = add_from_input,
						zeron.s("deck.attachments.add_confirm"),
					},
					Button {
						size = "xs",
						tone = "ghost",
						on_click = paste_from_clipboard,
						zeron.s("deck.attachments.paste_clipboard"),
					},
				}),
			}
		end

		-- ── Launch Tab (Compact 1-Box Mission Composer) ───────────────────
		local function build_launch(): Node
			local composer_modes = {
				{ value = "build_review", label = zeron.s("deck.composer.mode_build_review") },
				{ value = "fanout", label = zeron.s("deck.composer.mode_fanout") },
				{ value = "compare", label = zeron.s("deck.composer.mode_compare") },
				{ value = "captain", label = zeron.s("deck.composer.mode_captain") },
			}

			local function count_fanout_workers(): number
				local raw = trim(wf_subtasks:get())
				if raw == "" then
					return 1
				end
				local n = 0
				for line in string.gmatch(raw, "[^\r\n]+") do
					local clean = trim((string.gsub(line, "^[-*%d%.%)]+%s*", "")))
					if clean ~= "" then
						n += 1
						if n >= 8 then
							break
						end
					end
				end
				return math.max(1, n)
			end

			local function launch_footer_summary(): string
				local m = wf_preset:get()
				local agents_n = if m == "build_review" or m == "compare"
					then 2
					elseif m == "fanout" then count_fanout_workers()
					else 1
				local atts = launch_attachments:get()
				local n_att = #atts
				local has_prompt = trim(wf_task:get()) ~= ""
				if not has_prompt and n_att == 0 then
					return zeron.s("deck.composer.footer_ready")
				end
				local agent_label = if agents_n == 1
					then zeron.s("deck.composer.footer_agents_one", { n = agents_n })
					else zeron.s("deck.composer.footer_agents_many", { n = agents_n })
				if n_att == 0 then
					return agent_label
				end
				local all_images = true
				for _, item in atts do
					if not item.is_image then
						all_images = false
						break
					end
				end
				local att_label = if all_images
					then (if n_att == 1
						then zeron.s("deck.composer.footer_images_one", { n = n_att })
						else zeron.s("deck.composer.footer_images_many", { n = n_att }))
					else (if n_att == 1
						then zeron.s("deck.composer.footer_files_one", { n = n_att })
						else zeron.s("deck.composer.footer_files_many", { n = n_att }))
				return `{agent_label} · {att_label}`
			end

			return ui.column {
				w_full = true,
				bg = "$zeron.menu.solid",
				rounded = "$radius.lg",
				border = 1,
				border_color = "$border.strong",
				p = "$space.3",
				gap = "$space.2",

				-- 1. Top row: 4-Mode Segmented control + "+ Options" toggle
				ui.row {
					w_full = true,
					items = "center",
					justify = "between",
					gap = "$space.2",
					ui.row {
						grow = 1,
						min_w = 0,
						Segmented {
							value = wf_preset,
							options = composer_modes,
							fill = true,
							label = zeron.s("deck.composer.title"),
						},
					},
					Button {
						size = "xs",
						tone = "ghost",
						on_click = function()
							wf_options_open:set(not wf_options_open:peek())
						end,
						Icon { name = "settings", size = 11 },
						function(): string
							return if wf_options_open:get()
								then zeron.s("deck.composer.options_hide")
								else zeron.s("deck.composer.options_show")
						end,
					},
				},

				-- 2. Concise 1-line mode description
				ui.text {
					function(): string
						local m = wf_preset:get()
						if m == "build_review" then
							return zeron.s("deck.composer.desc_build_review")
						elseif m == "fanout" then
							return zeron.s("deck.composer.desc_fanout")
						elseif m == "compare" then
							return zeron.s("deck.composer.desc_compare")
						end
						return zeron.s("deck.composer.desc_captain")
					end,
					w_full = true,
					truncate = true,
					text_size = "$font.size.xs",
					color = "$text.tertiary",
				},

				-- 3. Prompt TextArea (`$zeron.window`) + Reference Image Attachment Bar
				build_attachment_prompt_box({
					text_state = wf_task,
					placeholder = function(): string
						local m = wf_preset:get()
						if m == "build_review" then
							return zeron.s("deck.composer.placeholder_build_review")
						elseif m == "fanout" then
							return zeron.s("deck.composer.placeholder_fanout")
						elseif m == "compare" then
							return zeron.s("deck.composer.placeholder_compare")
						end
						return zeron.s("deck.composer.placeholder_captain")
					end,
					rows = 3,
					max_rows = 4,
					min_height = 68,
					attachments = launch_attachments,
					hovering = launch_att_hover,
					path_open = launch_att_open,
					path_text = launch_att_path,
				}),

				-- Parallel Swarm Subtasks (only when mode == "fanout")
				ui.show(function(): boolean
					return wf_preset:get() == "fanout"
				end, ui.column {
					w_full = true,
					gap = "$space.1",
					ui.text {
						zeron.s("deck.composer.subtasks_label"),
						text_size = "$font.size.xs",
						color = "$text.secondary",
					},
					solid_textarea_box(
						TextArea {
							value = wf_subtasks,
							placeholder = zeron.s("deck.composer.subtasks_placeholder"),
							rows = 2,
							max_rows = 4,
							size = "sm",
							w_full = true,
						},
						52
					),
				}),

				divider(),

				-- 4. Project Row (PLACED DIRECTLY ABOVE Agent & Model Rows across ALL 4 modes)
				ui.row {
					w_full = true,
					items = "center",
					gap = "$space.2",
					ui.row {
						w = 92,
						shrink = 0,
						items = "center",
						gap = "$space.1",
						Icon { name = "folder", size = 13, color = "$text.tertiary" },
						ui.text {
							zeron.s("deck.composer.label_project"),
							text_size = "$font.size.xs",
							weight = "$font.weight.medium",
							color = "$text.secondary",
						},
					},
					ui.column {
						grow = 1,
						min_w = 0,
						Select {
							value = wf_project,
							options = function()
								return client.project_options()
							end,
							size = "sm",
							w_full = true,
						},
					},
				},

				-- 5a. Agent & Model Row for 1-Agent Modes (`fanout` / `captain`)
				ui.show(function(): boolean
					local m = wf_preset:get()
					return m == "fanout" or m == "captain"
				end, ui.row {
					w_full = true,
					items = "center",
					gap = "$space.2",
					ui.row {
						w = 92,
						shrink = 0,
						items = "center",
						Badge.Badge {
							function(): string
								return if wf_preset:get() == "captain"
									then zeron.s("deck.composer.stage_captain")
									else zeron.s("deck.composer.stage_swarm")
							end,
							tone = "accent",
							size = "sm",
						},
					},
					ui.column {
						w = 150,
						shrink = 0,
						Select {
							value = wf_primary_harness,
							options = function()
								return client.harness_options(true)
							end,
							size = "sm",
							w_full = true,
							on_change = function()
								wf_primary_model:set("")
							end,
						},
					},
					ui.column {
						grow = 1,
						min_w = 160,
						model_dropdown(wf_primary_model, wf_primary_harness, wf_primary_custom),
					},
				}),

				-- 5b. Agent & Model Rows for 2-Agent Modes (`build_review` / `compare`)
				ui.show(function(): boolean
					local m = wf_preset:get()
					return m == "build_review" or m == "compare"
				end, ui.column {
					w_full = true,
					gap = "$space.2",
					-- Stage 1 Row
					ui.row {
						w_full = true,
						items = "center",
						gap = "$space.2",
						ui.row {
							w = 92,
							shrink = 0,
							items = "center",
							Badge.Badge {
								function(): string
									return if wf_preset:get() == "compare"
										then zeron.s("deck.composer.stage_candidate_a")
										else zeron.s("deck.composer.stage_builder")
								end,
								tone = "accent",
								size = "sm",
							},
						},
						ui.column {
							w = 150,
							shrink = 0,
							Select {
								value = wf_primary_harness,
								options = function()
									return client.harness_options(true)
								end,
								size = "sm",
								w_full = true,
								on_change = function()
									wf_primary_model:set("")
								end,
							},
						},
						ui.column {
							grow = 1,
							min_w = 160,
							model_dropdown(wf_primary_model, wf_primary_harness, wf_primary_custom),
						},
					},
					-- Stage 2 Row
					ui.row {
						w_full = true,
						items = "center",
						gap = "$space.2",
						ui.row {
							w = 92,
							shrink = 0,
							items = "center",
							Badge.Badge {
								function(): string
									return if wf_preset:get() == "compare"
										then zeron.s("deck.composer.stage_candidate_b")
										else zeron.s("deck.composer.stage_reviewer")
								end,
								tone = "info",
								size = "sm",
							},
						},
						ui.column {
							w = 150,
							shrink = 0,
							Select {
								value = wf_secondary_harness,
								options = function()
									return client.harness_options(true)
								end,
								size = "sm",
								w_full = true,
								on_change = function()
									wf_secondary_model:set("")
								end,
							},
						},
						ui.column {
							grow = 1,
							min_w = 160,
							model_dropdown(wf_secondary_model, wf_secondary_harness, wf_secondary_custom),
						},
					},
				}),

				-- 6. Optional "+ Options" drawer (`$zeron.window` sunken well)
				ui.show(function(): boolean
					return wf_options_open:get()
				end, ui.column {
					w_full = true,
					gap = "$space.2",
					p = "$space.2",
					rounded = "$radius.md",
					bg = "$zeron.window",
					border = 1,
					border_color = "$border.subtle",
					ui.row {
						w_full = true,
						flex_wrap = true,
						gap = "$space.2",
						ui.column {
							grow = 1,
							basis = 0,
							min_w = 180,
							gap = "$space.1",
							Text {
								zeron.s("deck.composer.label_captain_name"),
								style = "caption",
								tone = "secondary",
							},
							TextField {
								value = wf_captain_name,
								placeholder = zeron.s("deck.composer.captain_name_placeholder"),
								size = "sm",
								w_full = true,
							},
						},
						ui.show(function(): boolean
							return wf_preset:get() ~= "captain"
						end, ui.column {
							grow = 1,
							basis = 0,
							min_w = 180,
							gap = "$space.1",
							Text {
								zeron.s("deck.composer.label_parent_captain"),
								style = "caption",
								tone = "secondary",
							},
							Select {
								value = wf_captain_id,
								options = function()
									return captain_picker_options(true)
								end,
								size = "sm",
								w_full = true,
							},
						}),
					},
					ui.column {
						w_full = true,
						gap = "$space.1",
						Text {
							zeron.s("deck.composer.label_shared_rules"),
							style = "caption",
							tone = "secondary",
						},
						TextField {
							value = wf_rules,
							placeholder = zeron.s("deck.composer.rules_placeholder"),
							size = "sm",
							w_full = true,
						},
					},
					ui.row {
						w_full = true,
						flex_wrap = true,
						gap = "$space.2",
						ui.column {
							grow = 1,
							basis = 0,
							min_w = 180,
							gap = "$space.1",
							Text {
								zeron.s("deck.composer.label_custom_harness"),
								style = "caption",
								tone = "secondary",
							},
							TextField {
								value = wf_primary_custom,
								placeholder = zeron.s("deck.composer.custom_harness_placeholder"),
								size = "sm",
								w_full = true,
							},
						},
						ui.show(function(): boolean
							local m = wf_preset:get()
							return m == "build_review" or m == "compare"
						end, ui.column {
							grow = 1,
							basis = 0,
							min_w = 180,
							gap = "$space.1",
							Text {
								zeron.s("deck.composer.label_custom_secondary"),
								style = "caption",
								tone = "secondary",
							},
							TextField {
								value = wf_secondary_custom,
								placeholder = zeron.s("deck.composer.custom_secondary_placeholder"),
								size = "sm",
								w_full = true,
							},
						}),
					},
					ui.row {
						w_full = true,
						items = "center",
						justify = "between",
						gap = "$space.2",
						pt = "$space.1",
						ui.column {
							grow = 1,
							min_w = 0,
							gap = 0,
							ui.text {
								zeron.s("deck.composer.auto_report_label"),
								text_size = "$font.size.xs",
								weight = "$font.weight.medium",
								color = "$text.primary",
							},
							ui.text {
								zeron.s("deck.composer.auto_report_hint"),
								text_size = "$font.size.xs",
								color = "$text.tertiary",
								truncate = true,
							},
						},
						Switch { value = wf_auto_report, label = zeron.s("deck.composer.auto_report_label") },
					},
				}),

				divider(),

				-- 7. Clean bottom Launch footer row
				ui.row {
					w_full = true,
					items = "center",
					justify = "between",
					gap = "$space.2",
					ui.text {
						launch_footer_summary,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = "$text.tertiary",
						tabular = true,
					},
					Button {
						tone = "primary",
						size = "sm",
						busy = wf_busy,
						disabled = wf_busy,
						on_click = submit_composer,
						Icon { name = "action-play", size = 12 },
						function(): string
							return if wf_preset:get() == "captain"
								then zeron.s("deck.composer.launch_captain")
								else zeron.s("deck.composer.launch_mission")
						end,
					},
				},
			}
		end

		-- ── Fleet Tab (Compact Captain Cards + Clean 2-Line Crew) ─────────
		local function build_fleet(): Node
			return ui.column {
				w_full = true,
				gap = "$space.2",

				-- Fleet filter & bulk action bar (kept outside query-keyed presence for focus safety)
				ui.show(function(): boolean
					return captain_count() > 0 or worker_count() > 0
				end, ui.row {
					w_full = true,
					shrink = 0,
					items = "center",
					justify = "between",
					gap = "$space.2",
					ui.show(function(): boolean
						return captain_count() > 1
					end, ui.div {
						grow = 1,
						min_w = 0,
						p = "$space.1",
						bg = "$zeron.menu.solid",
						rounded = "$radius.md",
						border = 1,
						border_color = "$border.strong",
						SearchField {
							value = query,
							placeholder = zeron.s("deck.search_placeholder"),
							name = zeron.s("deck.search_placeholder"),
							size = "sm",
							quiet = true,
							w_full = true,
						},
					}),
					ui.show(function(): boolean
						return captain_count() <= 1
					end, ui.text {
						function(): string
							local c = captain_count()
							local w = worker_count()
							local cw = if c == 1 then zeron.s("deck.stats.captain_singular") else zeron.s("deck.stats.captains")
							return `{c} {cw} · {w} {zeron.s("deck.stats.workers")}`
						end,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = "$text.tertiary",
						tabular = true,
					}),
					Button {
						size = "xs",
						tone = "danger",
						on_click = open_clear_all,
						Icon { name = "trash-bin-minimalistic", size = 11 },
						zeron.s("deck.fleet.clear_all"),
					},
				}),

				-- Needs You Alert Card (ONLY when pending attention items > 0)
				ui.show(function(): boolean
					local _ = client.state:get()
					return #client.attention_items() > 0
				end, ui.presence(function(): string
					local items = client.attention_items()
					local s = client.state:get()
					return if #items == 0 then "" else `att:{#items}:{s and s.rev or 0}`
				end, function(key: string): Node
					if key == "" then
						return ui.div {}
					end
					local items = client.attention_items()
					local att_rows: { Node } = {}
					for idx, item in items do
						local reason_label = if item.status == "awaiting_input"
							then zeron.s("deck.attention.awaiting_input")
							elseif item.status == "limited"
							then zeron.s("deck.attention.limited")
							else zeron.s("deck.attention.errored")
						local detail = if item.detail and item.detail ~= "" then item.detail else reason_label
						if idx > 1 then
							table.insert(att_rows, divider())
						end
						table.insert(
							att_rows,
							ui.row {
								w_full = true,
								py = "$space.1",
								items = "center",
								justify = "between",
								gap = "$space.2",
								ui.column {
									grow = 1,
									min_w = 0,
									gap = 2,
									ui.row {
										w_full = true,
										items = "center",
										gap = "$space.2",
										Status.StatusIcon { kind = client.status_kind(item.status) :: any, size = 13 },
										ui.text {
											item.title or reason_label,
											grow = 1,
											min_w = 0,
											truncate = true,
											text_size = "$font.size.xs",
											weight = "$font.weight.semibold",
											color = "$text.primary",
										},
										Badge.Badge { item.captain_name or "Captain", tone = "warning", size = "sm" },
										Badge.Badge { item.role or "worker", tone = "neutral", size = "sm" },
									},
									ui.text {
										detail,
										w_full = true,
										pl = 20,
										truncate = true,
										text_size = "$font.size.xs",
										color = "$text.secondary",
									},
								},
								ui.row {
									shrink = 0,
									items = "center",
									gap = "$space.1",
									Button {
										size = "xs",
										tone = "primary",
										on_click = function()
											open_chat_and_close(item.chat_id)
										end,
										zeron.s("deck.attention.open_chat"),
									},
									if item.kind == "escalation" and item.item_id
										then Button {
											size = "xs",
											tone = "ghost",
											on_click = function()
												client.call("resolve_attention", {
													captain_id = item.captain_id,
													item_id = item.item_id,
												})
											end,
											zeron.s("deck.attention.resolve"),
										}
										else nil,
								},
							}
						)
					end
					return ui.column {
						w_full = true,
						bg = "$zeron.menu.solid",
						rounded = "$radius.lg",
						border = 1,
						border_color = "$warning",
						px = "$space.3",
						py = "$space.2",
						gap = "$space.1",
						ui.row {
							w_full = true,
							items = "center",
							gap = "$space.2",
							ui.div { w = 6, h = 6, rounded = "$radius.full", bg = "$warning", shrink = 0 },
							ui.text {
								`{zeron.s("deck.attention.title")} ({#items})`,
								text_size = "$font.size.xs",
								weight = "$font.weight.semibold",
								color = "$warning",
								tabular = true,
							},
						},
						table.unpack(att_rows),
					}
				end, { w_full = true })),

				-- Captain Cards List
				ui.presence(function(): string
					local s = client.state:get()
					return `fleet:{s and s.rev or 0}:{query:get()}:{expand_rev:get()}`
				end, function(): Node
					local s = client.state:peek() or {}
					local q = trim(query:peek())
					local caps: { any } = {}
					for _, cap in (s.captains or {}) do
						table.insert(caps, cap)
					end
					table.sort(caps, function(a: any, b: any): boolean
						return (a.updated_at or 0) > (b.updated_at or 0)
					end)

					local sections: { Node } = {}
					for _, cap in caps do
						local crew = client.crew_of(cap.chat_id)
						if not matches_query(cap, crew, q) then
							continue
						end
						local sum = client.crew_summary(cap.chat_id)
						local has_attention = sum.attention > 0
						local cap_name = trim(cap.name)
						if cap_name == "" then
							cap_name = client.session_title(cap.chat_id)
						end
						local cap_mission = trim(cap.mission)
						local show_mission = cap_mission ~= "" and cap_mission ~= cap_name
						local mission_preview = if show_mission then (collapse_preview(cap_mission, 160)) else ""

						local meta_parts: { string } = {}
						local hm = format_harness_model(cap.harness, cap.model)
						if hm ~= "" then
							table.insert(meta_parts, hm)
						end
						if cap.status and cap.status ~= "" and cap.status ~= "idle" then
							table.insert(meta_parts, compact_status_label(cap.status))
						end
						local cap_age = format_age(cap.updated_at)
						if cap_age ~= "" then
							table.insert(meta_parts, cap_age)
						end
						local meta_line = table.concat(meta_parts, " · ")
						local has_schedule = cap.schedule_mins and cap.schedule_mins >= 5
						local cap_digest = trim(cap.digest)
						local cap_rules = trim(cap.rules)

						-- Crew Rows (Clean 2-line rows, NO ASCII tree chars)
						local crew_section: Node
						if #crew == 0 then
							crew_section = ui.row {
								w_full = true,
								items = "center",
								justify = "between",
								gap = "$space.2",
								ui.row {
									grow = 1,
									min_w = 0,
									items = "center",
									gap = "$space.2",
									Icon { name = "bot", size = 13, color = "$text.tertiary" },
									ui.text {
										zeron.s("deck.fleet.no_crew"),
										grow = 1,
										min_w = 0,
										truncate = true,
										text_size = "$font.size.xs",
										color = "$text.tertiary",
									},
								},
								Button {
									size = "xs",
									tone = "secondary",
									on_click = function()
										open_spawn_for(cap)
									end,
									Icon { name = "plus", size = 11 },
									zeron.s("deck.fleet.spawn_worker"),
								},
							}
						else
							local worker_rows: { Node } = {}
							for idx, w in crew do
								local w_title = trim(w.task)
								if w_title == "" then
									w_title = client.session_title(w.chat_id)
								end
								local w_meta_parts: { string } = {}
								local w_hm = format_harness_model(w.harness, w.model)
								if w_hm ~= "" then
									table.insert(w_meta_parts, w_hm)
								end
								local w_age = format_age(w.updated_at)
								if w_age ~= "" then
									table.insert(w_meta_parts, w_age)
								end
								local w_meta = table.concat(w_meta_parts, " · ")
								local w_err = trim(w.last_error)
								local w_reply_preview = ""
								if w_err == "" and trim(w.last_reply) ~= "" then
									w_reply_preview = (collapse_preview(w.last_reply, 120))
								end

								if idx > 1 then
									table.insert(worker_rows, divider())
								end
								table.insert(
									worker_rows,
									ui.column {
										w_full = true,
										py = "$space.1",
										gap = 3,

										-- Worker Line 1: [StatusIcon] Title | [StatusBadge] [Steer] [Open] [Dismiss]
										ui.row {
											w_full = true,
											items = "center",
											justify = "between",
											gap = "$space.2",
											ui.row {
												grow = 1,
												min_w = 0,
												items = "center",
												gap = "$space.2",
												Status.StatusIcon { kind = client.status_kind(w.status) :: any, size = 13 },
												ui.text {
													w_title,
													grow = 1,
													min_w = 0,
													truncate = true,
													weight = "$font.weight.medium",
													text_size = "$font.size.xs",
													color = "$text.primary",
												},
											},
											ui.row {
												shrink = 0,
												items = "center",
												gap = "$space.1",
												Badge.Badge {
													compact_status_label(w.status),
													tone = client.status_tone(w.status),
													size = "sm",
													dot = w.status == "running" or w.status == "awaiting_input",
												},
												IconButton {
													icon = "chat-round-line",
													size = "sm",
													tone = "quiet",
													label = zeron.s("deck.fleet.steer"),
													on_click = function()
														open_steer_for(w, cap_name)
													end,
												},
												IconButton {
													icon = "arrow-up-right",
													size = "sm",
													tone = "quiet",
													label = "Open worker chat",
													on_click = function()
														open_chat_and_close(w.chat_id)
													end,
												},
												IconButton {
													icon = "close",
													size = "sm",
													tone = "danger",
													label = zeron.s("deck.fleet.detach"),
													on_click = function()
														client.call("detach_worker", { worker_chat = w.chat_id }):after(function()
															zeron.toast(zeron.s("toast.worker_detached"))
														end, function() end)
													end,
												},
											},
										},

										-- Worker Line 2 (indented 20px): High-contrast role pill + handoff + `{harness} · {model} · {age}`
										ui.row {
											w_full = true,
											items = "center",
											gap = "$space.2",
											pl = 20,
											ui.row {
												shrink = 0,
												h = 16,
												px = "$space.1",
												rounded = "$radius.sm",
												bg = "$zeron.primary.bg",
												color = "$zeron.primary.text",
												items = "center",
												justify = "center",
												ui.text {
													w.role or "worker",
													color = "$zeron.primary.text",
													text_size = "$font.size.xs",
													weight = "$font.weight.medium",
												},
											},
											if w.next_stage
												then Badge.Badge {
													`→ {w.next_stage.role or "reviewer"}`,
													tone = "info",
													size = "sm",
												}
												else nil,
											if w_meta ~= ""
												then ui.text {
													w_meta,
													grow = 1,
													min_w = 0,
													truncate = true,
													color = "$text.tertiary",
													text_size = "$font.size.xs",
												}
												else nil,
										},

										-- Optional compact error well or 1-line reply preview
										if w_err ~= ""
											then ui.div {
												w_full = true,
												pl = 20,
												ui.div {
													w_full = true,
													bg = "$zeron.window",
													rounded = "$radius.sm",
													px = "$space.2",
													py = "$space.1",
													border = 1,
													border_color = "$border.subtle",
													ui.text {
														w_err,
														w_full = true,
														text_size = "$font.size.xs",
														color = "$danger",
														wrap = true,
													},
												},
											}
											elseif w_reply_preview ~= ""
											then ui.div {
												w_full = true,
												pl = 20,
												ui.text {
													w_reply_preview,
													w_full = true,
													truncate = true,
													text_size = "$font.size.xs",
													color = "$text.tertiary",
												},
											}
											else nil,
									}
								)
							end

							crew_section = ui.row {
								w_full = true,
								gap = "$space.2",
								ui.div {
									w = 2,
									self = "stretch",
									rounded = "$radius.full",
									bg = "$border.strong",
									shrink = 0,
								},
								ui.column {
									grow = 1,
									min_w = 0,
									gap = "$space.1",
									table.unpack(worker_rows),
								},
							}
						end

						table.insert(
							sections,
							ui.column {
								w_full = true,
								bg = "$zeron.menu.solid",
								rounded = "$radius.lg",
								border = 1,
								border_color = if has_attention then "$warning" else "$border.strong",
								p = "$space.3",
								gap = "$space.2",

								-- Header Row 1: Status + Name + Badges | + Worker, Attach, Inspector, Open, Edit, Delete
								ui.row {
									w_full = true,
									items = "center",
									justify = "between",
									gap = "$space.2",
									ui.row {
										grow = 1,
										min_w = 0,
										items = "center",
										gap = "$space.2",
										Status.StatusIcon { kind = client.status_kind(cap.status) :: any, size = 14 },
										ui.text {
											cap_name,
											weight = "$font.weight.semibold",
											text_size = "$font.size.sm",
											color = "$text.primary",
											truncate = true,
											min_w = 0,
											shrink = 1,
										},
										Badge.Badge { zeron.s("badges.captain"), tone = "accent", size = "sm" },
										Badge.Badge {
											if sum.running > 0
												then `{sum.total} crew · {sum.running} active`
												else `{sum.total} crew`,
											tone = "neutral",
											size = "sm",
											dot = sum.running > 0,
											tabular = true,
										},
										if has_attention
											then Badge.Badge {
												`{sum.attention} needs you`,
												tone = "warning",
												size = "sm",
												dot = true,
												tabular = true,
											}
											else nil,
									},
									ui.row {
										shrink = 0,
										items = "center",
										gap = "$space.1",
										Button {
											size = "xs",
											tone = "primary",
											on_click = function()
												open_spawn_for(cap)
											end,
											Icon { name = "plus", size = 11 },
											zeron.s("deck.fleet.spawn_worker"),
										},
										IconButton {
											icon = "git-branch",
											size = "sm",
											tone = "quiet",
											label = zeron.s("deck.fleet.attach_chat"),
											on_click = function()
												open_attach_from_captain(cap)
											end,
										},
										IconButton {
											icon = "split-columns",
											size = "sm",
											tone = "quiet",
											label = zeron.s("deck.fleet.inspector"),
											on_click = function()
												open_inspector_and_close(cap.chat_id)
											end,
										},
										IconButton {
											icon = "arrow-up-right",
											size = "sm",
											tone = "quiet",
											label = zeron.s("deck.fleet.open_chat"),
											on_click = function()
												open_chat_and_close(cap.chat_id)
											end,
										},
										IconButton {
											icon = "pen",
											size = "sm",
											tone = "quiet",
											label = zeron.s("deck.fleet.edit"),
											on_click = function()
												open_edit_for(cap)
											end,
										},
										IconButton {
											icon = "trash-bin-minimalistic",
											size = "sm",
											tone = "danger",
											label = zeron.s("deck.fleet.remove"),
											on_click = function()
												open_delete_for(cap, sum.total)
											end,
										},
									},
								},

								-- Header Row 2: Muted metadata `{harness} · {short_model} · {rel_time}` + optional schedule
								if meta_line ~= "" or has_schedule
									then ui.row {
										w_full = true,
										items = "center",
										gap = "$space.2",
										if meta_line ~= ""
											then ui.text {
												meta_line,
												grow = 1,
												min_w = 0,
												truncate = true,
												color = "$text.tertiary",
												text_size = "$font.size.xs",
											}
											else nil,
										if has_schedule
											then Badge.Badge {
												`Every {cap.schedule_mins}m`,
												tone = "info",
												size = "sm",
												icon = "clock-circle",
											}
											else nil,
									}
									else nil,

								-- Optional 1-line truncated mission if different from Captain name
								if show_mission
									then ui.text {
										mission_preview,
										w_full = true,
										truncate = true,
										color = "$text.secondary",
										text_size = "$font.size.xs",
									}
									else nil,

								-- Vertical Collapsible Live Digest (`$zeron.window` sunken well, collapsed by default)
								if cap_digest ~= ""
									then build_collapsible_well(
										zeron.s("deck.fleet.digest_label"),
										"$accent",
										cap_digest,
										expanded_digests[cap.chat_id] == true,
										function()
											toggle_digest(cap.chat_id)
										end
									)
									else nil,

								-- Vertical Collapsible Shared Rules (only if present)
								if cap_rules ~= ""
									then build_collapsible_well(
										zeron.s("deck.fleet.rules_label"),
										"$text.secondary",
										cap_rules,
										expanded_rules[cap.chat_id] == true,
										function()
											toggle_rules(cap.chat_id)
										end
									)
									else nil,

								divider(),
								crew_section,
							}
						)
					end

					if #sections == 0 then
						return ui.column {
							w_full = true,
							bg = "$zeron.menu.solid",
							rounded = "$radius.lg",
							border = 1,
							border_color = "$border.strong",
							py = "$space.4",
							px = "$space.3",
							EmptyState {
								size = "sm",
								icon = "users-group-rounded",
								title = if q ~= "" then `No match for "{q}"` else zeron.s("deck.fleet.empty_title"),
								body = zeron.s("deck.fleet.empty_body"),
								action = {
									label = zeron.s("deck.fleet.new_mission"),
									icon = "action-play",
									on_click = function()
										active_tab:set("launch")
									end,
								},
								secondary = {
									label = zeron.s("deck.tabs.chats"),
									icon = "chat-round-line",
									on_click = function()
										active_tab:set("chats")
									end,
								},
							},
						}
					end

					return ui.column { w_full = true, gap = "$space.2", table.unpack(sections) }
				end, { w_full = true }),
			}
		end

		-- ── Chats Tab (Compact Solid Rows) ────────────────────────────────
		local function build_chats(): Node
			return ui.presence(function(): string
				local s = client.state:get()
				local count = 0
				for _ in zeron.sessions() do
					count += 1
				end
				return `chats:{s and s.rev or 0}:{count}`
			end, function(): Node
				local s = client.state:peek() or {}
				local caps = s.captains or {}
				local workers = s.workers or {}
				local has_captains = next(caps) ~= nil

				local list: { any } = {}
				for id, sess in zeron.sessions() do
					if not caps[id] and not workers[id] then
						table.insert(list, { id = id, sess = sess })
					end
				end
				table.sort(list, function(a: any, b: any): boolean
					return (a.sess.updated or 0) > (b.sess.updated or 0)
				end)

				if #list == 0 then
					return ui.column {
						w_full = true,
						bg = "$zeron.menu.solid",
						rounded = "$radius.lg",
						border = 1,
						border_color = "$border.strong",
						py = "$space.4",
						px = "$space.3",
						EmptyState {
							size = "sm",
							icon = "chat-round-line",
							title = zeron.s("deck.chats.empty_title"),
							body = zeron.s("deck.chats.empty_body"),
						},
					}
				end

				local rows: { Node } = {}
				for i, entry in list do
					if i > 40 then
						break
					end
					local sid = entry.id
					local sess = entry.sess
					local title = if type(sess.title) == "string" and sess.title ~= ""
						then sess.title
						else string.sub(sid, 1, 8)
					local age = format_age(sess.updated)
					local sub = if sess.branch and sess.branch ~= ""
						then (if age ~= "" then `{sess.branch} · {age}` else sess.branch)
						else age

					if i > 1 then
						table.insert(rows, divider())
					end
					table.insert(
						rows,
						ui.row {
							w_full = true,
							px = "$space.3",
							py = "$space.2",
							items = "center",
							justify = "between",
							gap = "$space.2",
							ui.row {
								grow = 1,
								min_w = 0,
								items = "center",
								gap = "$space.2",
								Icon { name = "chat-round-line", size = 13, color = "$text.tertiary" },
								ui.column {
									grow = 1,
									min_w = 0,
									gap = 0,
									ui.text {
										title,
										w_full = true,
										truncate = true,
										text_size = "$font.size.xs",
										weight = "$font.weight.medium",
										color = "$text.primary",
									},
									if sub ~= ""
										then ui.text {
											sub,
											w_full = true,
											truncate = true,
											text_size = "$font.size.xs",
											color = "$text.tertiary",
										}
										else nil,
								},
							},
							ui.row {
								shrink = 0,
								items = "center",
								gap = "$space.1",
								Button {
									size = "xs",
									tone = "primary",
									on_click = function()
										client.call("promote_captain", { chat_id = sid, name = title }):after(function()
											zeron.toast(zeron.s("toast.promoted"))
											active_tab:set("fleet")
										end, function() end)
									end,
									Icon { name = "star", size = 11 },
									zeron.s("deck.chats.promote_short"),
								},
								if has_captains
									then Button {
										size = "xs",
										tone = "secondary",
										on_click = function()
											open_attach_for(sid, title, nil)
										end,
										Icon { name = "git-branch", size = 11 },
										zeron.s("deck.chats.attach_short"),
									}
									else nil,
								IconButton {
									icon = "arrow-up-right",
									size = "sm",
									tone = "quiet",
									label = "Open chat",
									on_click = function()
										open_chat_and_close(sid)
									end,
								},
							},
						}
					)
				end

				return ui.column {
					w_full = true,
					gap = "$space.2",
					ui.text {
						zeron.s("deck.chats.subtitle"),
						text_size = "$font.size.xs",
						color = "$text.tertiary",
					},
					ui.column {
						w_full = true,
						bg = "$zeron.menu.solid",
						rounded = "$radius.lg",
						border = 1,
						border_color = "$border.strong",
						overflow = "hidden",
						table.unpack(rows),
					},
				}
			end, { w_full = true })
		end

		-- ── Activity Tab (Compact Solid Timeline) ─────────────────────────
		local function build_activity(): Node
			return ui.presence(function(): string
				local s = client.state:get()
				return `act:{s and s.rev or 0}`
			end, function(): Node
				local s = client.state:peek() or {}
				local events = s.events or {}
				if #events == 0 then
					return ui.column {
						w_full = true,
						bg = "$zeron.menu.solid",
						rounded = "$radius.lg",
						border = 1,
						border_color = "$border.strong",
						py = "$space.4",
						px = "$space.3",
						EmptyState {
							size = "sm",
							icon = "clock-circle",
							title = zeron.s("deck.activity.empty_title"),
							body = zeron.s("deck.activity.empty_body"),
						},
					}
				end

				local rows: { Node } = {}
				for idx, ev in events do
					local tone: any = if ev.kind == "needs_you" or ev.kind == "awaiting_input"
						then "warning"
						elseif string.find(ev.kind or "", "fail") or string.find(ev.kind or "", "error")
						then "danger"
						elseif ev.kind == "handoff" or ev.kind == "workflow_launched"
						then "info"
						elseif ev.kind == "worker_finished" or ev.kind == "reported"
						then "success"
						else "neutral"
					local age = format_age(ev.at)
					if idx > 1 then
						table.insert(rows, divider())
					end
					table.insert(
						rows,
						ui.row {
							w_full = true,
							px = "$space.3",
							py = "$space.2",
							items = "center",
							justify = "between",
							gap = "$space.2",
							ui.row {
								grow = 1,
								min_w = 0,
								items = "center",
								gap = "$space.2",
								Badge.Badge { ev.kind or "event", tone = tone, size = "sm" },
								ui.text {
									ev.summary or "",
									grow = 1,
									min_w = 0,
									truncate = true,
									text_size = "$font.size.xs",
									color = "$text.primary",
								},
							},
							ui.row {
								shrink = 0,
								items = "center",
								gap = "$space.2",
								if age ~= ""
									then ui.div {
										px = "$space.1",
										py = 1,
										rounded = "$radius.sm",
										bg = "$zeron.window",
										border = 1,
										border_color = "$border.subtle",
										ui.text {
											age,
											text_size = "$font.size.xs",
											color = "$text.tertiary",
											tabular = true,
										},
									}
									else nil,
								if ev.chat_id
									then IconButton {
										icon = "arrow-up-right",
										size = "sm",
										tone = "quiet",
										label = "Open chat",
										on_click = function()
											open_chat_and_close(ev.chat_id)
										end,
									}
									else nil,
							},
						}
					)
				end

				return ui.column {
					w_full = true,
					gap = "$space.2",
					ui.row {
						w_full = true,
						items = "center",
						justify = "between",
						ui.text {
							zeron.s("deck.activity.subtitle"),
							text_size = "$font.size.xs",
							color = "$text.tertiary",
						},
						Button {
							size = "xs",
							tone = "ghost",
							on_click = function()
								client.call("clear_events")
							end,
							zeron.s("deck.activity.clear"),
						},
					},
					ui.column {
						w_full = true,
						bg = "$zeron.menu.solid",
						rounded = "$radius.lg",
						border = 1,
						border_color = "$border.strong",
						overflow = "hidden",
						table.unpack(rows),
					},
				}
			end, { w_full = true })
		end

		-- ── Focus-Safe Inline Sub-Panel Shell (100% Solid, Zero Nested Dialogs) ──
		local function build_subpanel_shell(
			title: string | () -> string,
			description: string,
			footer_actions: Node,
			body: Node,
			title_icon: { name: string, color: string }?
		): Node
			return ui.column {
				w_full = true,
				bg = "$zeron.menu.solid",
				rounded = "$radius.lg",
				border = 1,
				border_color = "$border.strong",
				overflow = "hidden",

				-- Header with clean `← Back`
				ui.row {
					w_full = true,
					px = "$space.3",
					py = "$space.2",
					bg = "$zeron.menu.solid",
					items = "center",
					justify = "between",
					gap = "$space.2",
					ui.row {
						grow = 1,
						min_w = 0,
						items = "center",
						gap = "$space.2",
						Button {
							size = "xs",
							tone = "ghost",
							on_click = close_panel,
							Icon { name = "arrow-left", size = 12 },
							zeron.s("dialogs.back"),
						},
						if title_icon
							then Icon { name = title_icon.name :: any, size = 14, color = title_icon.color }
							else nil,
						ui.column {
							grow = 1,
							min_w = 0,
							gap = 0,
							ui.text {
								title,
								weight = "$font.weight.semibold",
								text_size = "$font.size.sm",
								color = "$text.primary",
								truncate = true,
							},
							ui.text {
								description,
								text_size = "$font.size.xs",
								color = "$text.tertiary",
								truncate = true,
							},
						},
					},
				},
				divider(),

				-- Form Body
				ui.column {
					w_full = true,
					p = "$space.3",
					gap = "$space.2",
					bg = "$zeron.menu.solid",
					body,
				},
				divider(),

				-- Footer Actions
				ui.row {
					w_full = true,
					px = "$space.3",
					py = "$space.2",
					bg = "$zeron.menu.solid",
					justify = "end",
					items = "center",
					gap = "$space.2",
					footer_actions,
				},
			}
		end

		local function build_subpanel(kind: string): Node
			if kind == "edit" then
				return build_subpanel_shell(
					function(): string
						return `Edit Captain · {ec_name:get()}`
					end,
					"Update mission, shared rules, live digest, and schedule.",
					ui.row {
						gap = "$space.2",
						items = "center",
						Button { tone = "ghost", size = "sm", on_click = close_panel, zeron.s("dialogs.cancel") },
						Button {
							tone = "primary",
							size = "sm",
							busy = ec_busy,
							disabled = ec_busy,
							on_click = submit_edit_captain,
							zeron.s("dialogs.save"),
						},
					},
					ui.column {
						w_full = true,
						gap = "$space.2",
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 180,
								field_block("Captain Name", TextField { value = ec_name, size = "sm", w_full = true }),
							},
							ui.column {
								grow = 2,
								basis = 0,
								min_w = 220,
								field_block(
									zeron.s("inspector.mission"),
									TextField {
										value = ec_mission,
										placeholder = "What goal does this Captain own?",
										size = "sm",
										w_full = true,
									}
								),
							},
						},
						field_block(
							zeron.s("inspector.rules"),
							solid_textarea_box(
								TextArea {
									value = ec_rules,
									placeholder = "Prepended to every worker spawned under this Captain…",
									rows = 2,
									max_rows = 5,
									size = "sm",
									w_full = true,
								}
							)
						),
						field_block(
							zeron.s("inspector.digest"),
							solid_textarea_box(
								TextArea {
									value = ec_digest,
									placeholder = "Current progress summary or working notes…",
									rows = 3,
									max_rows = 6,
									size = "sm",
									w_full = true,
								}
							)
						),
						ui.row {
							w_full = true,
							items = "center",
							justify = "between",
							p = "$space.2",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$border.subtle",
							ui.column {
								grow = 1,
								min_w = 0,
								gap = 0,
								ui.text {
									"Auto-report to Captain",
									text_size = "$font.size.xs",
									weight = "$font.weight.medium",
									color = "$text.primary",
								},
								ui.text {
									"Send worker completion summaries back to this Captain chat.",
									text_size = "$font.size.xs",
									color = "$text.tertiary",
									truncate = true,
								},
							},
							Switch { value = ec_auto_report, label = "Auto-report" },
						},
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								w = 150,
								shrink = 0,
								field_block(
									"Wake (mins, 0=off)",
									TextField { value = ec_sched_mins, placeholder = "0 or e.g. 60", size = "sm", w_full = true }
								),
							},
							ui.column {
								grow = 1,
								min_w = 200,
								field_block(
									"Scheduled Wake Prompt",
									TextField {
										value = ec_sched_prompt,
										placeholder = "Check crew reports and update digest.",
										size = "sm",
										w_full = true,
									}
								),
							},
						},
					}
				)
			elseif kind == "spawn" then
				return build_subpanel_shell(
					function(): string
						return `Spawn Worker · {sw_captain_name:get()}`
					end,
					"Start a worker chat on any harness/model under this Captain.",
					ui.row {
						gap = "$space.2",
						items = "center",
						Button { tone = "ghost", size = "sm", on_click = close_panel, zeron.s("dialogs.cancel") },
						Button {
							tone = "primary",
							size = "sm",
							busy = sw_busy,
							disabled = sw_busy,
							on_click = submit_spawn_worker,
							Icon { name = "action-play", size = 12 },
							zeron.s("dialogs.spawn"),
						},
					},
					ui.column {
						w_full = true,
						gap = "$space.2",
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 140,
								field_block("Role", Select { value = sw_role, options = ROLES, size = "sm", w_full = true }),
							},
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 160,
								field_block(
									"Project",
									Select {
										value = sw_project,
										options = function()
											return client.project_options()
										end,
										size = "sm",
										w_full = true,
									}
								),
							},
						},
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 145,
								field_block(
									"Harness",
									Select {
										value = sw_harness,
										options = function()
											return client.harness_options(true)
										end,
										size = "sm",
										w_full = true,
										on_change = function()
											sw_model:set("")
										end,
									}
								),
							},
							ui.column {
								grow = 2,
								basis = 0,
								min_w = 200,
								field_block("Model", model_dropdown(sw_model, sw_harness, sw_custom_harness)),
							},
						},
						TextField {
							value = sw_custom_harness,
							placeholder = "Optional custom harness ID (e.g. acp.gemini, hermes, pi)",
							size = "sm",
							w_full = true,
						},
						field_block(
							"Task & Prompt",
							ui.column {
								w_full = true,
								gap = "$space.1",
								TextField {
									value = sw_task,
									placeholder = "Short title shown in Crew list",
									size = "sm",
									w_full = true,
								},
								build_attachment_prompt_box({
									text_state = sw_prompt,
									placeholder = "Clear instructions for this worker…",
									rows = 3,
									max_rows = 6,
									min_height = 68,
									attachments = spawn_attachments,
									hovering = sw_att_hover,
									path_open = sw_att_open,
									path_text = sw_att_path,
								}),
							}
						),
						ui.row {
							w_full = true,
							items = "center",
							justify = "between",
							p = "$space.2",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$border.subtle",
							ui.column {
								grow = 1,
								min_w = 0,
								gap = 0,
								ui.text {
									"Auto-handoff on completion",
									text_size = "$font.size.xs",
									weight = "$font.weight.medium",
									color = "$text.primary",
								},
								ui.text {
									"Automatically spawn a follow-up reviewer when finished.",
									text_size = "$font.size.xs",
									color = "$text.tertiary",
									truncate = true,
								},
							},
							Switch { value = sw_enable_handoff, label = "Enable handoff" },
						},
						ui.show(function(): boolean
							return sw_enable_handoff:get()
						end, ui.column {
							w_full = true,
							p = "$space.2",
							gap = "$space.2",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$border.subtle",
							ui.row {
								w_full = true,
								gap = "$space.2",
								ui.column {
									grow = 1,
									basis = 0,
									Select { value = sw_handoff_role, options = ROLES, size = "sm", w_full = true },
								},
								ui.column {
									grow = 1,
									basis = 0,
									Select {
										value = sw_handoff_harness,
										options = function()
											return client.harness_options(true)
										end,
										size = "sm",
										w_full = true,
									},
								},
							},
							TextArea {
								value = sw_handoff_prompt,
								rows = 2,
								max_rows = 5,
								size = "sm",
								w_full = true,
							},
						}),
					}
				)
			elseif kind == "attach" then
				return build_subpanel_shell(
					"Attach Chat as Worker",
					"Link an existing Zeron chat under a Captain to track its turns.",
					ui.row {
						gap = "$space.2",
						items = "center",
						Button { tone = "ghost", size = "sm", on_click = close_panel, zeron.s("dialogs.cancel") },
						Button {
							tone = "primary",
							size = "sm",
							busy = at_busy,
							disabled = at_busy,
							on_click = submit_attach,
							Icon { name = "git-branch", size = 12 },
							zeron.s("dialogs.attach"),
						},
					},
					ui.column {
						w_full = true,
						gap = "$space.2",
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 180,
								field_block(
									"Parent Captain",
									Select {
										value = at_captain_id,
										options = function()
											return captain_picker_options(false)
										end,
										size = "sm",
										w_full = true,
									}
								),
							},
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 180,
								field_block(
									"Chat Session",
									Select {
										value = at_chat_id,
										options = function()
											return unassigned_chat_options()
										end,
										size = "sm",
										w_full = true,
										on_change = function(next_id: string)
											local title = client.session_title(next_id)
											at_chat_title:set(title)
											at_task:set(title)
										end,
									}
								),
							},
						},
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								w = 160,
								shrink = 0,
								field_block("Worker Role", Select { value = at_role, options = ROLES, size = "sm", w_full = true }),
							},
							ui.column {
								grow = 1,
								min_w = 180,
								field_block("Task Label", TextField { value = at_task, size = "sm", w_full = true }),
							},
						},
					}
				)
			elseif kind == "steer" then
				return build_subpanel_shell(
					function(): string
						return `{zeron.s("dialogs.steer_title")} · {st_worker_title:get()}`
					end,
					zeron.s("dialogs.steer_desc"),
					ui.row {
						gap = "$space.2",
						items = "center",
						Button { tone = "ghost", size = "sm", on_click = close_panel, zeron.s("dialogs.cancel") },
						Button {
							tone = "secondary",
							size = "sm",
							busy = st_busy,
							disabled = st_busy,
							on_click = function()
								submit_steer("queue")
							end,
							zeron.s("dialogs.queue"),
						},
						Button {
							tone = "primary",
							size = "sm",
							busy = st_busy,
							disabled = st_busy,
							on_click = function()
								submit_steer("steer")
							end,
							Icon { name = "chat-round-line", size = 12 },
							zeron.s("dialogs.steer_now"),
						},
					},
					ui.column {
						w_full = true,
						gap = "$space.2",
						ui.row {
							w_full = true,
							px = "$space.2",
							py = "$space.2",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$border.subtle",
							items = "center",
							justify = "between",
							gap = "$space.2",
							ui.row {
								grow = 1,
								min_w = 0,
								items = "center",
								gap = "$space.2",
								ui.row {
									shrink = 0,
									h = 16,
									px = "$space.1",
									rounded = "$radius.sm",
									bg = "$zeron.primary.bg",
									color = "$zeron.primary.text",
									items = "center",
									ui.text {
										function(): string
											return st_worker_role:get()
										end,
										color = "$zeron.primary.text",
										text_size = "$font.size.xs",
										weight = "$font.weight.medium",
									},
								},
								ui.text {
									function(): string
										return `Crew of {st_captain_name:get()}`
									end,
									grow = 1,
									min_w = 0,
									truncate = true,
									text_size = "$font.size.xs",
									color = "$text.secondary",
								},
							},
							Badge.Badge {
								function(): string
									return compact_status_label(st_status:get())
								end,
								tone = "neutral",
								size = "sm",
							},
						},
						field_block(
							"Message",
							build_attachment_prompt_box({
								text_state = st_text,
								placeholder = zeron.s("inspector.steer_placeholder"),
								rows = 3,
								max_rows = 6,
								min_height = 76,
								attachments = steer_attachments,
								hovering = st_att_hover,
								path_open = st_att_open,
								path_text = st_att_path,
							})
						),
					}
				)
			elseif kind == "clear_all" then
				return build_subpanel_shell(
					zeron.s("dialogs.clear_all_title"),
					zeron.s("dialogs.clear_all_desc"),
					ui.row {
						gap = "$space.2",
						items = "center",
						Button { tone = "ghost", size = "sm", on_click = close_panel, zeron.s("dialogs.cancel") },
						Button {
							tone = "danger",
							size = "sm",
							busy = clear_all_busy,
							disabled = clear_all_busy,
							on_click = submit_clear_all,
							Icon { name = "trash-bin-minimalistic", size = 12 },
							zeron.s("dialogs.clear_all_confirm"),
						},
					},
					ui.column {
						w_full = true,
						gap = "$space.2",
						ui.row {
							w_full = true,
							p = "$space.2",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$border.subtle",
							items = "center",
							gap = "$space.2",
							Icon { name = "users-group-rounded", size = 14, color = "$danger" },
							ui.text {
								function(): string
									return zeron.s("dialogs.clear_all_counts", {
										captains = captain_count(),
										workers = worker_count(),
										events = event_count(),
									})
								end,
								grow = 1,
								min_w = 0,
								text_size = "$font.size.xs",
								weight = "$font.weight.semibold",
								color = "$text.primary",
								tabular = true,
								wrap = true,
							},
						},
						ui.row {
							w_full = true,
							items = "center",
							justify = "between",
							p = "$space.2",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$border.subtle",
							gap = "$space.2",
							ui.column {
								grow = 1,
								min_w = 0,
								gap = 0,
								ui.text {
									zeron.s("dialogs.clear_all_events_label"),
									text_size = "$font.size.xs",
									weight = "$font.weight.medium",
									color = "$text.primary",
								},
								ui.text {
									zeron.s("dialogs.clear_all_events_hint"),
									text_size = "$font.size.xs",
									color = "$text.tertiary",
									truncate = true,
								},
							},
							Switch { value = clear_events_opt, label = zeron.s("dialogs.clear_all_events_label") },
						},
						ui.column {
							w_full = true,
							p = "$space.3",
							rounded = "$radius.md",
							bg = "$zeron.window",
							border = 1,
							border_color = "$warning",
							ui.text {
								zeron.s("dialogs.clear_all_note"),
								text_size = "$font.size.xs",
								color = "$text.secondary",
								wrap = true,
							},
						},
					},
					{ name = "trash-bin-minimalistic", color = "$danger" }
				)
			end

			-- kind == "delete"
			return build_subpanel_shell(
				zeron.s("dialogs.delete_title"),
				zeron.s("dialogs.delete_desc"),
				ui.row {
					gap = "$space.2",
					items = "center",
					Button { tone = "ghost", size = "sm", on_click = close_panel, zeron.s("dialogs.cancel") },
					Button {
						tone = "danger",
						size = "sm",
						busy = del_busy,
						disabled = del_busy,
						on_click = submit_delete_captain,
						Icon { name = "trash-bin-minimalistic", size = 12 },
						zeron.s("dialogs.delete_confirm"),
					},
				},
				ui.column {
					w_full = true,
					p = "$space.3",
					gap = "$space.2",
					rounded = "$radius.md",
					bg = "$zeron.window",
					border = 1,
					border_color = "$warning",
					ui.text {
						function(): string
							return `Remove "{del_name:get()}" from Captain Deck?`
						end,
						text_size = "$font.size.sm",
						weight = "$font.weight.semibold",
						color = "$text.primary",
						wrap = true,
					},
					ui.text {
						function(): string
							local n = del_crew_count:get()
							if n > 0 then
								return `This will demote the Captain and detach {n} worker chat(s). Your underlying Zeron chat histories will NOT be deleted.`
							end
							return "This will demote the Captain from orchestration tracking. Your underlying Zeron chat history will NOT be deleted."
						end,
						text_size = "$font.size.xs",
						color = "$text.secondary",
						wrap = true,
					},
				}
			)
		end

		-- ── Compact Tab Pill Helper ───────────────────────────────────────
		local function tab_pill(id: string, label: string, icon_name: string?, count_fn: (() -> number)?): Node
			return ui.presence(function(): string
				local is_on = active_tab:get() == id
				local cnt = if count_fn then count_fn() else -1
				return `{id}:{if is_on then "1" else "0"}:{cnt}`
			end, function(): Node
				local is_on = active_tab:peek() == id
				local cnt = if count_fn then count_fn() else 0
				return ui.button {
					h = 26,
					px = "$space.2",
					gap = "$space.1",
					items = "center",
					justify = "center",
					rounded = "$radius.md",
					border = 1,
					bg = if is_on then "$zeron.menu.solid" else "$popover.bg",
					border_color = if is_on then "$border.strong" else "$popover.bg",
					hover = { bg = "$zeron.menu.solid" },
					cursor = "pointer",
					on_click = function()
						active_panel:set("none")
						active_tab:set(id)
					end,
					if icon_name
						then Icon {
							name = icon_name :: any,
							size = 12,
							color = if is_on then "$accent" else "$text.tertiary",
						}
						else nil,
					ui.text {
						label,
						text_size = "$font.size.xs",
						weight = if is_on then "$font.weight.semibold" else "$font.weight.medium",
						color = if is_on then "$text.primary" else "$text.secondary",
					},
					if count_fn and cnt > 0
						then ui.text {
							tostring(cnt),
							text_size = "$font.size.xs",
							color = "$text.tertiary",
							tabular = true,
						}
						else nil,
				}
			end)
		end

		-- ── Main Floating Card Root (100% Solid Opaque) ───────────────────
		return ui.column {
			class = "captain-deck-card",
			w_full = true,
			h_full = true,
			bg = "$popover.bg",
			overflow = "hidden",
			selectable = true,

			-- 1. Minimalist Single-Row Header
			ui.row {
				w_full = true,
				shrink = 0,
				px = "$space.3",
				py = "$space.2",
				bg = "$popover.bg",
				justify = "between",
				items = "center",
				gap = "$space.2",

				-- Left: Icon + Title + Compact Muted Count + Conditional Amber Needs You Pill
				ui.row {
					grow = 1,
					min_w = 0,
					items = "center",
					gap = "$space.2",
					Icon { name = "users-group-rounded", size = 15, color = "$accent" },
					ui.text {
						zeron.s("deck.title"),
						shrink = 0,
						text_size = "$font.size.sm",
						weight = "$font.weight.semibold",
						color = "$text.primary",
					},
					ui.presence(function(): string
						local s = client.state:get()
						local n_att = #client.attention_items()
						return `hdr:{s and s.rev or 0}:{n_att}`
					end, function(): Node
						local s = client.state:peek() or {}
						local n_caps, n_workers = 0, 0
						for _ in (s.captains or {}) do
							n_caps += 1
						end
						for _ in (s.workers or {}) do
							n_workers += 1
						end
						local n_att = #client.attention_items()
						local cap_word = if n_caps == 1
							then zeron.s("deck.stats.captain_singular")
							else zeron.s("deck.stats.captains")
						return ui.row {
							min_w = 0,
							items = "center",
							gap = "$space.2",
							ui.text {
								`· {n_caps} {cap_word} · {n_workers} {zeron.s("deck.stats.workers")}`,
								text_size = "$font.size.xs",
								color = "$text.tertiary",
								tabular = true,
								truncate = true,
							},
							if n_att > 0
								then Badge.Badge {
									`{n_att} {zeron.s("deck.stats.attention")}`,
									tone = "warning",
									size = "sm",
									dot = true,
									tabular = true,
								}
								else nil,
						}
					end),
				},

				-- Right: Quiet Refresh + Draft indicator pill + Clean Quiet Close
				ui.row {
					shrink = 0,
					items = "center",
					gap = "$space.1",
					IconButton {
						icon = "refresh",
						size = "sm",
						label = zeron.s("deck.refresh"),
						tone = "quiet",
						tooltip_side = "bottom",
						on_click = function()
							client.refresh()
							client.probe_harnesses(nil)
						end,
					},
					ui.show(compute_dirty, ui.row {
						shrink = 0,
						h = 20,
						px = "$space.2",
						gap = "$space.1",
						items = "center",
						rounded = "$radius.full",
						bg = "$zeron.window",
						border = 1,
						border_color = "$accent",
						tooltip = zeron.s("deck.draft_tooltip"),
						ui.div { w = 5, h = 5, rounded = "$radius.full", bg = "$accent", shrink = 0 },
						ui.text {
							zeron.s("deck.draft_badge"),
							text_size = "$font.size.xs",
							weight = "$font.weight.medium",
							color = "$accent",
						},
					}),
					if can_close_deck()
						then Button {
							size = "xs",
							tone = "ghost",
							on_click = close_deck,
							Icon { name = "close", size = 12 },
							zeron.s("deck.close_short"),
						}
						else nil,
				},
			},
			divider(),

			-- 2. Compact 4-Tab Bar (Fleet | Launch | Chats | Activity) — hidden during inline sub-panels
			ui.show(function(): boolean
				return active_panel:get() == "none"
			end, ui.column {
				w_full = true,
				shrink = 0,
				bg = "$popover.bg",
				ui.row {
					w_full = true,
					shrink = 0,
					px = "$space.3",
					py = "$space.1",
					gap = "$space.1",
					bg = "$popover.bg",
					items = "center",
					justify = "between",
					ui.row {
						items = "center",
						gap = "$space.1",
						tab_pill("fleet", zeron.s("deck.tabs.fleet"), "users-group-rounded", captain_count),
						tab_pill("launch", zeron.s("deck.tabs.launch"), "action-play", nil),
						tab_pill("chats", zeron.s("deck.tabs.chats"), "chat-round-line", unassigned_chat_count),
						tab_pill("activity", zeron.s("deck.tabs.activity"), "clock-circle", event_count),
					},
					ui.show(function(): boolean
						return active_tab:get() ~= "launch"
					end, Button {
						size = "xs",
						tone = "secondary",
						on_click = function()
							active_tab:set("launch")
						end,
						Icon { name = "plus", size = 11 },
						zeron.s("deck.tabs.new_short"),
					}),
				},
				divider(),
			}),

			-- 3. Breathable 100% Solid Scrollable Body
			ui.scroll {
				grow = 1,
				min_h = 0,
				w_full = true,
				overscroll = "contain",
				bg = "$popover.bg",
				fade = { 8, 8 },
				fade_overflow = true,
				ui.column {
					w_full = true,
					px = "$space.3",
					py = "$space.2",
					gap = "$space.2",

					-- Service warning callout (100% solid, only when service_err is non-empty)
					ui.show(function(): boolean
						local err = client.service_err:get()
						return type(err) == "string" and err ~= ""
					end, ui.presence(function(): string
						return client.service_err:get() or ""
					end, function(err: string): Node
						if err == "" then
							return ui.div {}
						end
						return ui.row {
							w_full = true,
							px = "$space.3",
							py = "$space.2",
							gap = "$space.2",
							items = "center",
							justify = "between",
							rounded = "$radius.md",
							bg = "$zeron.menu.solid",
							border = 1,
							border_color = "$warning",
							ui.column {
								grow = 1,
								min_w = 0,
								gap = 2,
								ui.text {
									"Orchestration service needs attention",
									text_size = "$font.size.xs",
									weight = "$font.weight.semibold",
									color = "$warning",
								},
								ui.text {
									err,
									text_size = "$font.size.xs",
									color = "$text.secondary",
									wrap = true,
								},
							},
							Button {
								size = "xs",
								tone = "secondary",
								on_click = function()
									client.refresh()
								end,
								"Retry",
							},
						}
					end, { w_full = true })),

					-- Swap cleanly between active inline sub-panel and active tab content
					ui.presence(function(): string
						local p = active_panel:get()
						if p ~= "none" then
							return "panel:" .. p
						end
						return "tab:" .. active_tab:get()
					end, function(key: string): Node
						if string.sub(key, 1, 6) == "panel:" then
							return build_subpanel(string.sub(key, 7))
						end
						local tab = string.sub(key, 5)
						if tab == "launch" then
							return build_launch()
						elseif tab == "chats" then
							return build_chats()
						elseif tab == "activity" then
							return build_activity()
						end
						return build_fleet()
					end, { w_full = true }),
				},
			},
		}
	end)
end

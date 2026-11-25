--!strict
-- Compact native Zeron badges, sidebar titles, slash command row & recoverable
-- composer orchestrator strip for Captain Deck.
--
-- 1. SidebarTitle (`.session-title` replace, fill = true): renders highlighted
--    worker role pill as title for Crew chats, native FadeText + Captain badge
--    for Captain chats, and exact native Zeron FadeText for normal chats.
-- 2. CardRow (`.session-card-end` after): shows Captain crew summary or
--    Worker's parent Captain in Zeron's session hover card.
-- 3. SlashCommandRow (`#mention-1` / `#mention-empty` before): shows native
--    scrollable `/captain` command row inside the composer's `/` popover.
-- 4. ComposerOrchestratorStrip (`#chat-composer` after): solid opaque compact
--    orchestrator strip with native Zeron status animation and inline
--    permission / needs-you quick actions (with recoverable restore pill).

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local FadeText = require("@ds/fade_text")
local Icon = require("@ds/icon")
local Status = require("@ds/status")

return function(zeron: any, client: any): any
	local M = {}

	local show_sidebar = zeron.setting("show_sidebar_badges")
	local show_composer_bar = zeron.setting("show_composer_bar")

	local function trim(s: any): string
		if type(s) ~= "string" then
			return ""
		end
		return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
	end

	local function collapse_line(s: any): string
		local t = trim(s)
		if t == "" then
			return ""
		end
		return trim((string.gsub(t, "%s+", " ")))
	end

	local function worker_pill(label: string, status: string?, header: boolean?, tooltip: string?): Node
		local show_dot = status == "running" or status == "awaiting_input"
		return ui.row {
			shrink = 0,
			h = if header then 20 else 18,
			px = "$space.2",
			gap = if header then "$space.1" else 4,
			items = "center",
			justify = "center",
			rounded = if header then "$radius.md" else "$radius.sm",
			bg = "$zeron.primary.bg",
			color = "$zeron.primary.text",
			tooltip = tooltip,
			if show_dot
				then ui.div {
					w = 5,
					h = 5,
					shrink = 0,
					rounded = "$radius.full",
					bg = if status == "awaiting_input" then "$warning" else "$accent",
				}
				else nil,
			ui.text {
				label,
				text_size = "$font.size.xs",
				weight = "$font.weight.medium",
				color = "$zeron.primary.text",
				shrink = 0,
			},
		}
	end

	local function draft_text(): string
		local ok, d = pcall(zeron.draft)
		if ok and type(d) == "table" and type(d.text) == "string" then
			return d.text
		end
		return ""
	end

	local function matches_captain_slash(text: string): boolean
		local q = string.match(text, "^/([%w_%-]*)$") or string.match(text, "%s/([%w_%-]*)$")
		if q == nil then
			return false
		end
		if q == "" then
			return true
		end
		local lq = string.lower(q)
		return string.find("captain", lq, 1, true) ~= nil
			or string.find("captain-deck", lq, 1, true) ~= nil
			or string.find("deck", lq, 1, true) ~= nil
	end

	local function strip_trailing_slash(text: string): string
		local cleaned = string.gsub(text, "^/[%w_%-]*$", "")
		if cleaned == text then
			cleaned = string.gsub(text, "%s+/[%w_%-]*$", "")
		end
		return (string.gsub(cleaned, "%s+$", ""))
	end

	local function worker_status_label(status: string?): string
		if status == "running" then
			return "running"
		elseif status == "awaiting_input" then
			return "needs you"
		elseif status == "completed" then
			return "done"
		elseif status == "errored" then
			return "errored"
		elseif status == "limited" then
			return "limited"
		end
		return "idle"
	end

	local function handle_permission_decision(chat_id: string, decision: string, request: any?)
		local function fallback_open()
			if type(chat_id) == "string" and chat_id ~= "" then
				pcall(zeron.open, { session = chat_id })
			end
			zeron.toast("Opened chat to respond")
		end
		if type(chat_id) ~= "string" or chat_id == "" then
			return
		end
		if type(client.answer_input) ~= "function" then
			fallback_open()
			return
		end
		local ok, p = pcall(client.answer_input, chat_id, decision, nil, request)
		if not ok or p == nil then
			fallback_open()
			return
		end
		local ok_toast = if decision == "allow" then "Approved" else "Denied"
		if type(p) == "table" and type(p.after) == "function" then
			p:after(function(res: any)
				if type(res) == "table" and res.ok == true then
					zeron.toast(ok_toast)
				else
					fallback_open()
				end
			end, function()
				fallback_open()
			end)
		elseif type(p) == "table" and p.ok == true then
			zeron.toast(ok_toast)
		else
			fallback_open()
		end
	end

	local function collect_attention_items(target_captain_id: string, current_sid: string): { any }
		local awaiting_list: { any } = {}
		local needs_list: { any } = {}
		local seen: { [string]: boolean } = {}

		local function push_item(entry: any)
			if type(entry) ~= "table" then
				return
			end
			local kind = entry.kind
			if kind ~= "awaiting_input" and kind ~= "needs_you" then
				return
			end
			local cid = if type(entry.chat_id) == "string" then entry.chat_id else ""
			local eid = tostring(entry.id or cid)
			local key = if kind == "awaiting_input" then `awaiting_input:{cid}` else `needs_you:{eid}`
			if seen[key] then
				return
			end
			seen[key] = true
			if kind == "awaiting_input" then
				table.insert(awaiting_list, entry)
			else
				table.insert(needs_list, entry)
			end
		end

		-- Prefer unified client.attention_items(target_captain_id) when available.
		if type(client.attention_items) == "function" then
			local ok, raw_items = pcall(client.attention_items, target_captain_id)
			if ok and type(raw_items) == "table" then
				for _, item in raw_items do
					if type(item) == "table" then
						local item_cap = if type(item.captain_id) == "string" then item.captain_id else ""
						if target_captain_id == "" or item_cap == "" or item_cap == target_captain_id then
							if item.kind == "awaiting_input" then
								push_item(item)
							elseif item.kind == "needs_you" or item.kind == "escalation" then
								push_item({
									kind = "needs_you",
									id = item.item_id or item.id,
									captain_id = if item_cap ~= "" then item_cap else target_captain_id,
									captain_name = item.captain_name,
									chat_id = item.chat_id or target_captain_id,
									role = item.role or "captain",
									title = item.title or "Needs decision",
									detail = item.detail or "",
								})
							elseif (item.kind == "worker" or item.kind == "captain_status") and item.status == "awaiting_input" then
								push_item({
									kind = "awaiting_input",
									id = item.id,
									captain_id = if item_cap ~= "" then item_cap else target_captain_id,
									captain_name = item.captain_name,
									chat_id = item.chat_id,
									role = item.role or "worker",
									title = item.title or item.role or "worker",
									detail = item.detail or "",
									request = item.request,
								})
							end
						end
					end
				end
			end
		end

		-- Safe fallback directly against cap / crew if needed.
		local cap = if target_captain_id ~= "" then client.captain_of(target_captain_id) else nil
		local crew = if target_captain_id ~= "" then (client.crew_of(target_captain_id) or {}) else {}
		if cap then
			local cap_name = if type(cap.name) == "string" and cap.name ~= "" then cap.name else "Captain"
			if cap.status == "awaiting_input" then
				local pi = if type(cap.pending_input) == "table" then cap.pending_input else nil
				push_item({
					kind = "awaiting_input",
					id = `input:{target_captain_id}`,
					captain_id = target_captain_id,
					captain_name = cap_name,
					chat_id = target_captain_id,
					role = "Captain",
					title = if pi and trim(pi.title) ~= "" then trim(pi.title) else cap_name,
					detail = collapse_line(if pi and trim(pi.detail) ~= "" then pi.detail else cap.mission),
					request = if pi then pi.request else nil,
				})
			end
			for _, member in crew do
				if type(member) == "table" and member.status == "awaiting_input" then
					local pi = if type(member.pending_input) == "table" then member.pending_input else nil
					local m_role = if type(member.role) == "string" and member.role ~= "" then member.role else "worker"
					local m_detail = collapse_line(if pi then pi.detail else nil)
					if m_detail == "" then
						m_detail = collapse_line(member.task)
					end
					push_item({
						kind = "awaiting_input",
						id = `input:{member.chat_id}`,
						captain_id = target_captain_id,
						captain_name = cap_name,
						chat_id = member.chat_id,
						role = m_role,
						title = if pi and trim(pi.title) ~= "" then trim(pi.title) else (member.task or m_role),
						detail = m_detail,
						request = if pi then pi.request else nil,
					})
				end
			end
			if type(cap.needs_you) == "table" then
				for _, item in cap.needs_you do
					if type(item) == "table" and not item.resolved then
						push_item({
							kind = "needs_you",
							id = item.id,
							captain_id = target_captain_id,
							captain_name = cap_name,
							chat_id = item.worker_chat or target_captain_id,
							role = "captain",
							title = item.title or "Needs decision",
							detail = item.detail or "",
						})
					end
				end
			end
		end

		-- If viewing a Worker chat whose own status is awaiting_input, ensure it is present and first.
		local cur_w = if current_sid ~= "" then client.worker_of(current_sid) else nil
		if cur_w and cur_w.status == "awaiting_input" then
			local pi = if type(cur_w.pending_input) == "table" then cur_w.pending_input else nil
			local w_role = if type(cur_w.role) == "string" and cur_w.role ~= "" then cur_w.role else "worker"
			local w_detail = collapse_line(if pi then pi.detail else nil)
			if w_detail == "" then
				w_detail = collapse_line(cur_w.task)
			end
			push_item({
				kind = "awaiting_input",
				id = `input:{current_sid}`,
				captain_id = target_captain_id,
				captain_name = if cap and type(cap.name) == "string" then cap.name else "Captain",
				chat_id = current_sid,
				role = w_role,
				title = if pi and trim(pi.title) ~= "" then trim(pi.title) else (cur_w.task or w_role),
				detail = w_detail,
				request = if pi then pi.request else nil,
			})
		end

		local out: { any } = {}
		for _, item in awaiting_list do
			table.insert(out, item)
		end
		for _, item in needs_list do
			table.insert(out, item)
		end

		-- Promote the currently open worker's awaiting_input item to index 1.
		if current_sid ~= "" and cur_w ~= nil then
			for i, item in out do
				if item.kind == "awaiting_input" and item.chat_id == current_sid then
					if i > 1 then
						table.remove(out, i)
						table.insert(out, 1, item)
					end
					break
				end
			end
		end

		return out
	end

	M.SidebarTitle = ui.component(function(props: { session_id: string, panel: any? }): Node
		local sid = props.session_id
		local panel = props.panel
		local route = zeron.live("route")

		local function live_session(target_sid: string): any?
			if type(target_sid) ~= "string" or target_sid == "" then
				return nil
			end
			local s = zeron.context_of("session", target_sid)
			return if type(s) == "table" then s else nil
		end

		local function is_strong(target_sid: string): boolean
			local r = route()
			if type(r) == "table" and r.name == "session" and r.session == target_sid then
				return true
			end
			local s = live_session(target_sid)
			if s and type(s.status) == "string" then
				local st = s.status
				if
					st == "running"
					or st == "working"
					or st == "awaiting_input"
					or st == "input"
					or st == "approval"
					or st == "errored"
					or st == "failed"
					or st == "limited"
				then
					return true
				end
			end
			return false
		end

		local function kind_key(): string
			if type(sid) ~= "string" or sid == "" then
				return "plain"
			end
			if show_sidebar:get() == false then
				return "plain"
			end
			local w = client.worker_of(sid)
			if w then
				local parent = if type(w.captain_id) == "string" and w.captain_id ~= ""
					then client.captain_of(w.captain_id)
					else nil
				local pname = if parent and type(parent.name) == "string" then parent.name else ""
				return `w:{w.role or "worker"}:{w.status or "idle"}:{collapse_line(w.task)}:{pname}`
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid) or { total = 0, running = 0, attention = 0 }
				return `cap:{sum.total or 0}:{sum.running or 0}:{sum.attention or 0}`
			end
			return "plain"
		end

		return ui.presence(kind_key, function(key: string): Node
			if string.sub(key, 1, 2) == "w:" and show_sidebar:get() ~= false then
				local w = client.worker_of(sid)
				if w then
					local role = if type(w.role) == "string" and trim(w.role) ~= "" then trim(w.role) else "worker"
					local task_txt = collapse_line(w.task)
					local parent = if type(w.captain_id) == "string" and w.captain_id ~= ""
						then client.captain_of(w.captain_id)
						else nil
					local parent_name = if parent and type(parent.name) == "string" and trim(parent.name) ~= ""
						then trim(parent.name)
						else "Captain"
					local head_tip = if task_txt ~= "" then `{role} · {task_txt}` else role
					local tip = `{head_tip}\nCaptain: {parent_name}`
					return ui.row {
						class = "captain-deck-sidebar-worker-title",
						w_full = true,
						h_full = true,
						min_w = 0,
						items = "center",
						justify = "start",
						gap = "$space.1",
						cursor = "pointer",
						on_click = function()
							local target_captain_id = w.captain_id or sid
							client.focus_chat:set(target_captain_id)
							pcall(zeron.open, { session = sid })
							if type(w.captain_id) == "string" and w.captain_id ~= "" then
								client.open_inspector(panel, w.captain_id)
								ui.after(60, function()
									client.open_inspector(nil, w.captain_id)
								end)
							end
						end,
						worker_pill(`↳ {role}`, w.status, false, tip),
					}
				end
			end

			if string.sub(key, 1, 4) == "cap:" and show_sidebar:get() ~= false then
				local cap = client.captain_of(sid)
				if cap then
					local sum = client.crew_summary(sid) or { total = 0, running = 0, attention = 0 }
					local total = sum.total or 0
					local running = sum.running or 0
					local attention = sum.attention or 0
					local label = if total > 0 then `Captain · {total}` else "Captain"
					return ui.row {
						class = "captain-deck-sidebar-captain-title",
						w_full = true,
						h_full = true,
						min_w = 0,
						items = "center",
						gap = "$space.2",
						FadeText {
							function(): string
								local s = live_session(sid)
								return if s and type(s.title) == "string" then s.title else ""
							end,
							grow = 1,
							min_w = 0,
							text_size = "$font.size.md",
							weight = function(): string
								return if is_strong(sid) then "$font.weight.medium" else "$font.weight.regular"
							end,
							color = function(): string
								return if is_strong(sid) then "$text.primary" else "$text.secondary"
							end,
						},
						ui.row {
							class = "captain-deck-sidebar-badge",
							shrink = 0,
							cursor = "pointer",
							on_click = function()
								client.focus_chat:set(sid)
								pcall(zeron.open, { session = sid })
								client.open_inspector(panel, sid)
								ui.after(60, function()
									client.open_inspector(nil, sid)
								end)
							end,
							Badge.Badge {
								label,
								tone = "accent",
								size = "sm",
								dot = running > 0 or attention > 0,
								tabular = true,
							},
						},
					}
				end
			end

			return ui.row {
				w_full = true,
				h_full = true,
				min_w = 0,
				items = "center",
				FadeText {
					function(): string
						local s = live_session(sid)
						return if s and type(s.title) == "string" then s.title else ""
					end,
					grow = 1,
					text_size = "$font.size.md",
					weight = function(): string
						return if is_strong(sid) then "$font.weight.medium" else "$font.weight.regular"
					end,
					color = function(): string
						return if is_strong(sid) then "$text.primary" else "$text.secondary"
					end,
				},
			}
		end, { w_full = true, h_full = true, min_w = 0 })
	end)

	M.CardRow = ui.component(function(props: { session_id: string }): Node
		local sid = props.session_id

		local function key(): string
			if type(sid) ~= "string" or sid == "" then
				return ""
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid) or { total = 0, running = 0, attention = 0 }
				return `cap:{cap.name or "Captain"}:{sum.total or 0}:{sum.running or 0}:{sum.attention or 0}`
			end
			local w = client.worker_of(sid)
			if w then
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				return `w:{w.role or "worker"}:{w.status or "idle"}:{if parent then (parent.name or "") else ""}`
			end
			return ""
		end

		return ui.presence(key, function(k: string): Node
			if k == "" then
				return ui.div {}
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid) or { total = 0, running = 0, attention = 0 }
				local total = sum.total or 0
				local running = sum.running or 0
				local attention = sum.attention or 0
				local summary = if total == 0
					then "No crew assigned yet"
					else `{total} crew · {running} running{if attention > 0 then ` · {attention} needs you` else ""}`
				return ui.row {
					class = "captain-deck-card-row",
					w_full = true,
					gap = "$space.2",
					items = "center",
					Icon { name = "users-group-rounded", size = 12, color = "$accent" },
					ui.text {
						summary,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = "$text.secondary",
					},
					Badge.Badge {
						"Captain",
						tone = "accent",
						size = "sm",
						dot = running > 0 or attention > 0,
					},
				}
			end

			local w = client.worker_of(sid)
			if w then
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				local parent_name = if parent and type(parent.name) == "string" and parent.name ~= ""
					then parent.name
					else "Captain"
				return ui.row {
					class = "captain-deck-card-row",
					w_full = true,
					gap = "$space.2",
					items = "center",
					Icon { name = "bot", size = 12, color = "$text.tertiary" },
					ui.text {
						`Crew of {parent_name}{if w.harness then ` · {w.harness}` else ""}`,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = "$text.secondary",
					},
					worker_pill(w.role or "worker", w.status, false, nil),
				}
			end
			return ui.div {}
		end)
	end)

	M.SlashCommandRow = ui.component(function(props: { empty_fallback: boolean? }?): Node
		local empty_fallback = if type(props) == "table" then props.empty_fallback == true else false

		return ui.show(
			function(): boolean
				return matches_captain_slash(draft_text())
			end,
			ui.button {
				class = "captain-deck-slash-row",
				role = "option",
				h = 32,
				w_full = true,
				shrink = 0,
				px = "$space.2",
				gap = "$space.2",
				items = "center",
				justify = "start",
				rounded = "$zeron.menu.row_radius",
				bg = if empty_fallback then "$hover" else "#00000000",
				hover = { bg = "$hover" },
				active = { bg = "$pressed" },
				focus = { outline = 0, border = 0 },
				focus_on_press = false,
				cursor = "pointer",
				on_click = function()
					local cleaned = strip_trailing_slash(draft_text())
					pcall(zeron.compose, cleaned, { replace = true })
					client.open_deck()
				end,
				ui.row {
					w = 18,
					h = 18,
					shrink = 0,
					items = "center",
					justify = "center",
					Icon {
						name = "command",
						size = 16,
						color = if empty_fallback then "$accent" else "$text.secondary",
					},
				},
				ui.text {
					"/captain",
					shrink = 0,
					text_size = "$font.size.md",
					color = "$text.primary",
				},
				ui.text {
					"Captain Deck: open multi-agent orchestration deck",
					grow = 1,
					min_w = 0,
					truncate = true,
					text_size = "$font.size.sm",
					color = "$text.tertiary",
				},
				ui.text {
					if empty_fallback then "Space / ⌘⇧O" else "⌘⇧O",
					shrink = 0,
					font = "$font.mono",
					text_size = "$font.size.xs",
					color = "$text.tertiary",
				},
			}
		)
	end)

	M.ComposerOrchestratorStrip = ui.component(function(props: { session_id: any, panel: any? }): Node
		local function resolve_sid(): string
			local raw = if type(props.session_id) == "function" then props.session_id() else props.session_id
			return if type(raw) == "string" then raw else ""
		end

		local function resolve_panel(): any
			local ok, p = pcall(zeron.context, "panel")
			if ok and p ~= nil then
				return p
			end
			return props.panel
		end

		local function first_captain_error(cap: any, crew: { any }, captain_id: string): (string?, string?)
			for _, w in crew do
				if w.status == "errored" or w.status == "limited" then
					local role = if type(w.role) == "string" and w.role ~= "" then w.role else "worker"
					local detail = collapse_line(w.last_error)
					if detail == "" then
						detail = collapse_line(w.task)
					end
					if detail == "" then
						detail = worker_status_label(w.status)
					end
					return `{role}: {detail}`, w.chat_id
				end
			end
			if cap.status == "errored" or cap.status == "limited" then
				return `Captain {cap.name or ""}: {worker_status_label(cap.status)}`, captain_id
			end
			return nil, nil
		end

		local function attention_signature(items: { any }): string
			if #items == 0 then
				return ""
			end
			local parts: { string } = {}
			for i = 1, math.min(#items, 4) do
				local it = items[i]
				table.insert(
					parts,
					`{it.kind}:{tostring(it.id or "")}:{it.chat_id or ""}:{it.role or ""}:{collapse_line(it.title)}:{collapse_line(it.detail)}:{if it.request ~= nil then "1" else "0"}`
				)
			end
			return `{#items}|{table.concat(parts, ";")}`
		end

		local function strip_key(): string
			if show_composer_bar:get() == false then
				return ""
			end
			local sid = resolve_sid()
			if sid == "" then
				return ""
			end
			local mode_tag = if client.is_strip_dismissed(sid) then "min" else "exp"
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid) or { total = 0, running = 0, attention = 0, errored = 0 }
				local crew = client.crew_of(sid) or {}
				local attn_items = collect_attention_items(sid, sid)
				local err_msg, err_chat = first_captain_error(cap, crew, sid)
				local running_sig: { string } = {}
				for _, w in crew do
					if w.status == "running" then
						table.insert(running_sig, `{w.chat_id}:{w.role or "worker"}`)
					end
				end
				return `cap:{mode_tag}:{sid}:{sum.total or 0}:{sum.running or 0}:{sum.attention or 0}:{sum.errored or 0}:{cap.status or ""}:{attention_signature(attn_items)}:{err_msg or ""}:{err_chat or ""}:{table.concat(running_sig, ",")}`
			end
			local w = client.worker_of(sid)
			if w then
				local target_cap_id = if type(w.captain_id) == "string" and w.captain_id ~= "" then w.captain_id else sid
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				local parent_name = if parent and type(parent.name) == "string" then parent.name else ""
				local attn_items = collect_attention_items(target_cap_id, sid)
				return `w:{mode_tag}:{sid}:{w.role or "worker"}:{w.status or "idle"}:{w.captain_id or ""}:{parent_name}:{collapse_line(w.last_error)}:{attention_signature(attn_items)}`
			end
			return ""
		end

		return ui.presence(strip_key, function(k: string): Node
			if k == "" or show_composer_bar:get() == false then
				return ui.div { pointer_events = "none" }
			end

			local sid = resolve_sid()
			if sid == "" then
				return ui.div { pointer_events = "none" }
			end

			local cap = client.captain_of(sid)
			local w = if cap then nil else client.worker_of(sid)
			if not cap and not w then
				return ui.div { pointer_events = "none" }
			end

			local dismissed = client.is_strip_dismissed(sid)
			local title = ""
			local muted_status = ""
			local compact_label = ""
			local target_captain_id = sid
			local has_attention = false
			local is_running = false
			local has_error = false
			local err_msg: string? = nil
			local err_chat: string? = nil
			local attn_items: { any } = {}
			local running_workers: { any } = {}

			if cap then
				local sum = client.crew_summary(sid) or { total = 0, running = 0, attention = 0, awaiting = 0, errored = 0 }
				local crew = client.crew_of(sid) or {}
				local total = sum.total or 0
				local running = sum.running or 0
				local errored = sum.errored or 0
				title = "Captain active"
				compact_label = `Captain · {total}`
				target_captain_id = sid
				is_running = running > 0 or cap.status == "running"

				attn_items = collect_attention_items(sid, sid)
				has_attention = #attn_items > 0 or (sum.awaiting or 0) > 0 or cap.status == "awaiting_input"

				err_msg, err_chat = first_captain_error(cap, crew, sid)
				has_error = errored > 0 or err_msg ~= nil

				local parts: { string } = {}
				if total > 0 then
					table.insert(parts, `{total} crew`)
				end
				if running > 0 then
					table.insert(parts, `{running} running`)
				end
				if #attn_items > 0 then
					table.insert(parts, `{#attn_items} needs you`)
				elseif (sum.attention or 0) > 0 then
					table.insert(parts, `{sum.attention} needs you`)
				end
				if has_error and #attn_items == 0 and (sum.attention or 0) == 0 then
					table.insert(parts, "attention needed")
				end
				if not is_running and not has_attention and not has_error then
					table.insert(parts, "idle")
				end
				muted_status = "· " .. table.concat(parts, " · ")

				for _, member in crew do
					if member.status == "running" then
						table.insert(running_workers, member)
					end
				end
			elseif w then
				local role = if type(w.role) == "string" and w.role ~= "" then w.role else "worker"
				title = `Crew · {role}`
				compact_label = `Crew · {role}`
				target_captain_id = if type(w.captain_id) == "string" and w.captain_id ~= "" then w.captain_id else sid
				is_running = w.status == "running"
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				local parent_name = if parent and type(parent.name) == "string" and parent.name ~= ""
					then parent.name
					else nil
				local status_lbl = worker_status_label(w.status)
				muted_status = if parent_name then `· {parent_name} · {status_lbl}` else `· {status_lbl}`

				attn_items = collect_attention_items(target_captain_id, sid)
				has_attention = #attn_items > 0 or w.status == "awaiting_input"

				if w.status == "errored" or w.status == "limited" then
					has_error = true
					local err_txt = collapse_line(w.last_error)
					local task_txt = collapse_line(w.task)
					err_msg = if err_txt ~= ""
						then err_txt
						elseif task_txt ~= "" then task_txt
						else `Crew member ({status_lbl})`
					err_chat = sid
				end
			end

			local status_kind: string
			if has_attention then
				status_kind = "input"
			elseif is_running then
				status_kind = "working"
			elseif has_error then
				status_kind = "failed"
			else
				status_kind = "done"
			end

			if dismissed then
				local pill_label = if #attn_items > 0 then `{compact_label} · {#attn_items}` else compact_label
				return ui.row {
					w_full = true,
					justify = "end",
					pointer_events = "none",
					ui.button {
						class = "captain-deck-strip-restore",
						pointer_events = "auto",
						h = 24,
						px = "$space.2",
						gap = "$space.1",
						items = "center",
						rounded = "$radius.full",
						bg = "$popover.bg",
						border = 1,
						border_color = if has_attention
							then "$warning"
							elseif has_error then "$danger"
							elseif is_running then "$accent"
							else "$border.strong",
						shadow = "$zeron.composer.shadow",
						hover = { bg = "$zeron.menu.solid" },
						active = { bg = "$pressed" },
						focus = { outline = 0, border = 0 },
						focus_on_press = false,
						cursor = "pointer",
						tooltip = "Show Captain Deck bar",
						on_click = function()
							client.show_strip(sid)
						end,
						Status.StatusIcon { kind = status_kind :: any, size = 12 },
						ui.text {
							pill_label,
							shrink = 0,
							text_size = "$font.size.xs",
							weight = "$font.weight.medium",
							color = "$text.primary",
						},
						Icon { name = "alt-arrow-up", size = 11, color = "$text.tertiary" },
					},
				}
			end

			local row1 = ui.row {
				w_full = true,
				gap = "$space.2",
				items = "center",
				ui.row {
					grow = 1,
					min_w = 0,
					gap = "$space.1",
					items = "center",
					Status.StatusIcon { kind = status_kind :: any, size = 14 },
					ui.text {
						title,
						shrink = 0,
						text_size = "$font.size.xs",
						weight = "$font.weight.semibold",
						color = "$text.primary",
					},
					ui.text {
						muted_status,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = if has_attention
							then "$warning"
							elseif has_error then "$danger"
							else "$text.tertiary",
					},
				},
				ui.row {
					shrink = 0,
					gap = "$space.1",
					items = "center",
					Button {
						tone = "ghost",
						size = "xs",
						on_click = function()
							client.open_deck()
						end,
						"Deck",
					},
					Button {
						tone = "ghost",
						size = "xs",
						on_click = function()
							client.open_inspector(resolve_panel(), target_captain_id)
						end,
						"Inspector",
					},
					Button {
						tone = "ghost",
						size = "xs",
						on_click = function()
							client.dismiss_strip(sid)
						end,
						"Hide",
					},
				},
			}

			local row2: Node? = nil
			if #attn_items > 0 then
				local box_children: { any } = {
					w_full = true,
					bg = "$zeron.menu.solid",
					border = 1,
					border_color = "$warning",
					rounded = "$radius.lg",
					px = "$space.2",
					py = "$space.2",
					gap = "$space.1",
				}
				table.insert(
					box_children,
					ui.text {
						if #attn_items > 1
							then `Needs Your Permission / Input ({#attn_items})`
							else "Needs Your Permission / Input",
						text_size = "$font.size.xs",
						weight = "$font.weight.semibold",
						color = "$warning",
					}
				)
				local shown_count = math.min(#attn_items, 3)
				for i = 1, shown_count do
					local item = attn_items[i]
					local item_chat = if type(item.chat_id) == "string" and item.chat_id ~= ""
						then item.chat_id
						else target_captain_id
					if item.kind == "awaiting_input" then
						local item_role = if type(item.role) == "string" and trim(item.role) ~= ""
							then trim(item.role)
							else "worker"
						local detail_txt = collapse_line(item.detail)
						if detail_txt == "" then
							local t_txt = collapse_line(item.title)
							if t_txt ~= "" and string.lower(t_txt) ~= string.lower(item_role) then
								detail_txt = t_txt
							end
						end
						local item_req = item.request
						table.insert(
							box_children,
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								ui.row {
									grow = 1,
									min_w = 0,
									gap = "$space.1",
									items = "center",
									Status.StatusIcon { kind = "input", size = 13 },
									ui.text {
										`Permission · {item_role}`,
										shrink = 0,
										text_size = "$font.size.xs",
										weight = "$font.weight.semibold",
										color = "$text.primary",
									},
									if detail_txt ~= ""
										then ui.text {
											detail_txt,
											grow = 1,
											min_w = 0,
											truncate = true,
											text_size = "$font.size.xs",
											color = "$text.secondary",
										}
										else nil,
								},
								ui.row {
									shrink = 0,
									gap = "$space.1",
									items = "center",
									Button {
										tone = "primary",
										size = "xs",
										on_click = function()
											handle_permission_decision(item_chat, "allow", item_req)
										end,
										"Allow",
									},
									Button {
										tone = "ghost",
										size = "xs",
										on_click = function()
											handle_permission_decision(item_chat, "deny", item_req)
										end,
										"Deny",
									},
									Button {
										tone = "ghost",
										size = "xs",
										on_click = function()
											client.focus_chat:set(target_captain_id)
											if item_chat ~= "" then
												pcall(zeron.open, { session = item_chat })
											end
											client.open_inspector(resolve_panel(), target_captain_id)
										end,
										"Open",
									},
								},
							}
						)
					else
						local t_txt = collapse_line(item.title)
						local d_txt = collapse_line(item.detail)
						local ny_line = if t_txt ~= "" and d_txt ~= "" and d_txt ~= t_txt
							then `{t_txt} — {d_txt}`
							elseif t_txt ~= "" then t_txt
							elseif d_txt ~= "" then d_txt
							else "Captain needs your input"
						local item_id = item.id
						table.insert(
							box_children,
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								ui.row {
									grow = 1,
									min_w = 0,
									gap = "$space.1",
									items = "center",
									Status.StatusIcon { kind = "input", size = 13 },
									ui.text {
										ny_line,
										grow = 1,
										min_w = 0,
										truncate = true,
										text_size = "$font.size.xs",
										color = "$text.primary",
									},
								},
								ui.row {
									shrink = 0,
									gap = "$space.1",
									items = "center",
									Button {
										tone = "ghost",
										size = "xs",
										on_click = function()
											client.focus_chat:set(target_captain_id)
											if item_chat ~= "" then
												pcall(zeron.open, { session = item_chat })
											end
											client.open_inspector(resolve_panel(), target_captain_id)
										end,
										"Open",
									},
									Button {
										tone = "ghost",
										size = "xs",
										on_click = function()
											client.call("resolve_attention", {
												captain_id = target_captain_id,
												item_id = item_id,
											})
										end,
										"Resolve",
									},
								},
							}
						)
					end
				end
				if #attn_items > 3 then
					table.insert(
						box_children,
						ui.row {
							w_full = true,
							justify = "end",
							ui.button {
								h = 20,
								px = "$space.1",
								rounded = "$radius.sm",
								bg = "#00000000",
								hover = { bg = "$hover" },
								active = { bg = "$pressed" },
								focus = { outline = 0, border = 0 },
								focus_on_press = false,
								cursor = "pointer",
								on_click = function()
									client.open_inspector(resolve_panel(), target_captain_id)
								end,
								ui.text {
									`+{#attn_items - 3} more in Inspector`,
									text_size = "$font.size.xs",
									color = "$warning",
								},
							},
						}
					)
				end
				row2 = ui.column(box_children)
			elseif has_error then
				local error_line = if type(err_msg) == "string" and err_msg ~= ""
					then err_msg
					else "Crew member encountered an error"
				row2 = ui.row {
					w_full = true,
					gap = "$space.2",
					items = "center",
					Status.StatusIcon { kind = "failed", size = 13 },
					ui.text {
						error_line,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = "$danger",
					},
					Button {
						tone = "ghost",
						size = "xs",
						on_click = function()
							client.focus_chat:set(target_captain_id)
							if type(err_chat) == "string" and err_chat ~= "" and err_chat ~= sid then
								pcall(zeron.open, { session = err_chat })
							end
							client.open_inspector(resolve_panel(), target_captain_id)
						end,
						"Review",
					},
				}
			elseif cap ~= nil and #running_workers > 0 then
				local pills: { any } = {
					w_full = true,
					gap = "$space.1",
					items = "center",
					overflow = "hidden",
				}
				local max_pills = 5
				local shown = math.min(#running_workers, max_pills)
				for i = 1, shown do
					local rw = running_workers[i]
					local rw_role = if type(rw.role) == "string" and rw.role ~= "" then rw.role else "worker"
					local rw_tip = if type(rw.task) == "string" and trim(rw.task) ~= ""
						then `{rw_role} · {collapse_line(rw.task)}`
						else `Open {rw_role} chat`
					local rw_id = rw.chat_id
					table.insert(
						pills,
						ui.button {
							h = 22,
							px = "$space.2",
							gap = 5,
							shrink = 0,
							items = "center",
							rounded = "$radius.md",
							bg = "$zeron.menu.solid",
							border = 1,
							border_color = "$border.subtle",
							hover = { bg = "$hover", border_color = "$border.strong" },
							active = { bg = "$pressed" },
							focus = { outline = 0, border = 0 },
							focus_on_press = false,
							cursor = "pointer",
							tooltip = rw_tip,
							on_click = function()
								if type(rw_id) == "string" and rw_id ~= "" then
									pcall(zeron.open, { session = rw_id })
								end
							end,
							ui.div {
								w = 6,
								h = 6,
								shrink = 0,
								rounded = "$radius.full",
								bg = "$accent",
							},
							ui.text {
								rw_role,
								shrink = 0,
								text_size = "$font.size.xs",
								weight = "$font.weight.medium",
								color = "$text.primary",
							},
						}
					)
				end
				if #running_workers > max_pills then
					table.insert(
						pills,
						ui.text {
							`+{#running_workers - max_pills} more`,
							shrink = 0,
							text_size = "$font.size.xs",
							color = "$text.tertiary",
						}
					)
				end
				row2 = ui.row(pills)
			end

			return ui.column {
				class = "captain-deck-composer-strip",
				pointer_events = "auto",
				w_full = true,
				rounded = "$radius.xl",
				bg = "$popover.bg",
				border = 1,
				border_color = if has_attention
					then "$warning"
					elseif has_error then "$danger"
					elseif is_running then "$accent"
					else "$border.strong",
				shadow = "$zeron.composer.shadow",
				px = "$space.3",
				py = "$space.2",
				gap = "$space.1",
				row1,
				row2,
			}
		end, { w_full = true, pointer_events = "none" })
	end)

	return M
end

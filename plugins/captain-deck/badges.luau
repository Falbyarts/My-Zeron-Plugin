--!strict
-- Compact native Zeron badges, slash command row & recoverable composer strip for Captain Deck.
--
-- 1. SidebarBadge (`.session-title` after): shows Captain (accent) / Worker
--    (native inverted-contrast) role pill beside orchestrated chats.
-- 2. CardRow (`.session-card-end` after): shows Captain crew summary or
--    Worker's parent Captain in Zeron's session hover card.
-- 3. SlashCommandRow (`#mention-1` / `#mention-empty` before): shows native
--    scrollable `/captain` command row inside the composer's `/` popover.
-- 4. ComposerOrchestratorStrip (`#chat-composer` after): solid opaque compact
--    orchestrator strip floating above the composer (with recoverable restore pill).

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local Icon = require("@ds/icon")

return function(zeron: any, client: any): any
	local M = {}

	local show_sidebar = zeron.setting("show_sidebar_badges")
	local show_composer_bar = zeron.setting("show_composer_bar")

	local function worker_pill(label: string, status: string?, header: boolean?, tooltip: string?): Node
		local show_dot = status == "running" or status == "awaiting_input"
		return ui.row {
			shrink = 0,
			h = if header then 20 else 16,
			px = if header then "$space.2" else "$space.1",
			gap = if header then "$space.1" else 3,
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

	M.SidebarBadge = ui.component(function(props: { session_id: string, panel: any? }): Node
		local sid = props.session_id
		local panel = props.panel

		local function kind_key(): string
			if type(sid) ~= "string" or sid == "" then
				return ""
			end
			if show_sidebar:get() == false then
				return ""
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid)
				return `cap:{sum.total}:{sum.running}:{sum.attention}`
			end
			local w = client.worker_of(sid)
			if w then
				return `w:{w.role or "worker"}:{w.status or "idle"}`
			end
			return ""
		end

		return ui.presence(kind_key, function(key: string): Node
			if key == "" then
				return ui.div {}
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid)
				local label = if sum.total > 0 then `Captain · {sum.total}` else "Captain"
				return ui.row {
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
						dot = sum.running > 0 or sum.attention > 0,
						tabular = true,
					},
				}
			end

			local w = client.worker_of(sid)
			if w then
				return ui.row {
					class = "captain-deck-sidebar-badge",
					shrink = 0,
					cursor = "pointer",
					on_click = function()
						local target_captain_id = w.captain_id or sid
						client.focus_chat:set(target_captain_id)
						pcall(zeron.open, { session = sid })
						if w.captain_id then
							client.open_inspector(panel, w.captain_id)
							ui.after(60, function()
								client.open_inspector(nil, w.captain_id)
							end)
						end
					end,
					worker_pill(`↳ {w.role or "worker"}`, w.status, false, nil),
				}
			end
			return ui.div {}
		end)
	end)

	M.CardRow = ui.component(function(props: { session_id: string }): Node
		local sid = props.session_id

		local function key(): string
			if type(sid) ~= "string" or sid == "" then
				return ""
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid)
				return `cap:{cap.name or "Captain"}:{sum.total}:{sum.running}:{sum.attention}`
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
				local sum = client.crew_summary(sid)
				local summary = if sum.total == 0
					then "No crew assigned yet"
					else `{sum.total} crew · {sum.running} running{if sum.attention > 0 then ` · {sum.attention} needs you` else ""}`
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
						dot = sum.running > 0 or sum.attention > 0,
					},
				}
			end

			local w = client.worker_of(sid)
			if w then
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				local parent_name = if parent and type(parent.name) == "string" and parent.name ~= "" then parent.name else "Captain"
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

		local function first_captain_attention(cap: any, crew: { any }, captain_id: string): (string?, string?)
			if type(cap.needs_you) == "table" then
				for _, item in cap.needs_you do
					if type(item) == "table" and not item.resolved then
						local t = collapse_line(item.title)
						local d = collapse_line(item.detail)
						local msg = if t ~= "" and d ~= "" and d ~= t
							then `{t} — {d}`
							elseif t ~= "" then t
							elseif d ~= "" then d
							else "Captain needs your input"
						local target = if type(item.worker_chat) == "string" and item.worker_chat ~= ""
							then item.worker_chat
							else captain_id
						return msg, target
					end
				end
			end
			for _, w in crew do
				if w.status == "awaiting_input" or w.status == "errored" or w.status == "limited" then
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
			if cap.status == "awaiting_input" or cap.status == "errored" or cap.status == "limited" then
				return `Captain {cap.name or ""}: {worker_status_label(cap.status)}`, captain_id
			end
			return nil, nil
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
				local sum = client.crew_summary(sid)
				local crew = client.crew_of(sid)
				local attn_msg, attn_chat = first_captain_attention(cap, crew, sid)
				local running_sig: { string } = {}
				for _, w in crew do
					if w.status == "running" then
						table.insert(running_sig, `{w.chat_id}:{w.role or "worker"}`)
					end
				end
				return `cap:{mode_tag}:{sid}:{sum.total}:{sum.running}:{sum.attention}:{cap.status or ""}:{attn_msg or ""}:{attn_chat or ""}:{table.concat(running_sig, ",")}`
			end
			local w = client.worker_of(sid)
			if w then
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				local parent_name = if parent and type(parent.name) == "string" then parent.name else ""
				return `w:{mode_tag}:{sid}:{w.role or "worker"}:{w.status or "idle"}:{w.captain_id or ""}:{parent_name}:{collapse_line(w.last_error)}`
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
			local attn_msg: string? = nil
			local attn_chat: string? = nil
			local running_workers: { any } = {}

			if cap then
				local sum = client.crew_summary(sid)
				local crew = client.crew_of(sid)
				title = "Captain active"
				compact_label = `Captain · {sum.total}`
				target_captain_id = sid
				is_running = sum.running > 0 or cap.status == "running"

				local parts: { string } = {}
				if sum.total > 0 then
					table.insert(parts, `{sum.total} crew`)
				end
				if sum.running > 0 then
					table.insert(parts, `{sum.running} running`)
				end
				if sum.attention > 0 then
					table.insert(parts, `{sum.attention} needs you`)
				end
				if sum.running == 0 and sum.attention == 0 then
					table.insert(parts, "idle")
				end
				muted_status = "· " .. table.concat(parts, " · ")

				attn_msg, attn_chat = first_captain_attention(cap, crew, sid)
				has_attention = sum.attention > 0 or attn_msg ~= nil

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

				if w.status == "awaiting_input" or w.status == "errored" or w.status == "limited" then
					has_attention = true
					local err_txt = collapse_line(w.last_error)
					local task_txt = collapse_line(w.task)
					attn_msg = if err_txt ~= ""
						then err_txt
						elseif task_txt ~= "" then task_txt
						else `Crew member ({status_lbl})`
					attn_chat = sid
				end
			end

			if dismissed then
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
						border_color = if has_attention then "$warning" elseif is_running then "$accent" else "$border.strong",
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
						Icon { name = "users-group-rounded", size = 12, color = "$accent" },
						if has_attention or is_running
							then ui.div {
								w = 5,
								h = 5,
								shrink = 0,
								rounded = "$radius.full",
								bg = if has_attention then "$warning" else "$accent",
							}
							else nil,
						ui.text {
							compact_label,
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
					Icon { name = "users-group-rounded", size = 14, color = "$accent" },
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
						color = if has_attention then "$warning" else "$text.tertiary",
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
			if has_attention then
				local warning_line = if type(attn_msg) == "string" and attn_msg ~= ""
					then attn_msg
					else "Action needed in crew"
				row2 = ui.row {
					w_full = true,
					gap = "$space.2",
					items = "center",
					ui.div {
						w = 6,
						h = 6,
						shrink = 0,
						rounded = "$radius.full",
						bg = "$warning",
					},
					ui.text {
						warning_line,
						grow = 1,
						min_w = 0,
						truncate = true,
						text_size = "$font.size.xs",
						color = "$warning",
					},
					Button {
						tone = "ghost",
						size = "xs",
						on_click = function()
							client.focus_chat:set(target_captain_id)
							if type(attn_chat) == "string" and attn_chat ~= "" and attn_chat ~= sid then
								pcall(zeron.open, { session = attn_chat })
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
				border_color = if has_attention then "$warning" elseif is_running then "$accent" else "$border.strong",
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
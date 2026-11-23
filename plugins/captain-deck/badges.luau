--!strict
-- Compact native Zeron badges & header controls for Captain Deck.
--
-- 1. SidebarBadge (`.session-title` after): shows Captain / Worker role pill
--    beside orchestrated chats without slowing down sidebar rendering.
-- 2. CardRow (`.session-card-end` after): shows Captain crew summary or
--    Worker's parent Captain in Zeron's session hover card.
-- 3. HeaderPill (`#page-title` after): shows Crew Inspector trigger in a
--    Captain/Worker chat's header, or a quiet Promote button on regular chats.

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local Icon = require("@ds/icon")
local IconButton = require("@ds/icon_button").IconButton

return function(zeron: any, client: any): any
	local M = {}

	local show_sidebar = zeron.setting("show_sidebar_badges")
	local show_header = zeron.setting("show_header_pill")

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
				local tone: any = if sum.attention > 0 then "warning" elseif sum.running > 0 then "accent" else "info"
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
						tone = tone,
						size = "sm",
						dot = sum.running > 0 or sum.attention > 0,
						tabular = true,
					},
				}
			end

			local w = client.worker_of(sid)
			if w then
				local tone = client.status_tone(w.status)
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
					Badge.Badge {
						`↳ {w.role or "worker"}`,
						tone = tone,
						size = "sm",
						dot = w.status == "running" or w.status == "awaiting_input",
					},
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
						tone = if sum.attention > 0 then "warning" else "accent",
						size = "sm",
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
					Badge.Badge {
						w.role or "worker",
						tone = client.status_tone(w.status),
						size = "sm",
					},
				}
			end
			return ui.div {}
		end)
	end)

	M.HeaderPill = ui.component(function(props: { session_id: string, panel: any? }): Node
		local sid = props.session_id
		local panel = props.panel

		local function key(): string
			if type(sid) ~= "string" or sid == "" then
				return "off"
			end
			if show_header:get() == false then
				return "off"
			end
			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid)
				return `cap:{sum.total}:{sum.running}:{sum.attention}`
			end
			local w = client.worker_of(sid)
			if w then
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				return `w:{w.role or "worker"}:{w.status or "idle"}:{if parent then (parent.name or "") else ""}`
			end
			return "none"
		end

		return ui.presence(key, function(k: string): Node
			if k == "off" then
				return ui.div {}
			end

			local cap = client.captain_of(sid)
			if cap then
				local sum = client.crew_summary(sid)
				local tone: any = if sum.attention > 0 then "warning" elseif sum.running > 0 then "accent" else "info"
				local text = if sum.total > 0 then `Captain · {sum.total} crew` else "Captain"
				return ui.row {
					class = "captain-deck-header-pill",
					shrink = 0,
					gap = "$space.1",
					items = "center",
					ui.row {
						cursor = "pointer",
						on_click = function()
							client.open_inspector(panel, sid)
						end,
						Badge.Badge {
							text,
							tone = tone,
							size = "md",
							icon = "users-group-rounded",
							dot = sum.attention > 0,
							tooltip = zeron.s("badges.open_inspector"),
						},
					},
				}
			end

			local w = client.worker_of(sid)
			if w then
				local parent = if w.captain_id then client.captain_of(w.captain_id) else nil
				local parent_name = if parent and type(parent.name) == "string" and parent.name ~= "" then parent.name else "Captain"
				return ui.row {
					class = "captain-deck-header-pill",
					shrink = 0,
					gap = "$space.1",
					items = "center",
					ui.row {
						cursor = "pointer",
						on_click = function()
							if w.captain_id then
								client.open_inspector(panel, w.captain_id)
							end
						end,
						Badge.Badge {
							`↳ {w.role or "worker"} · {parent_name}`,
							tone = client.status_tone(w.status),
							size = "md",
							dot = w.status == "running" or w.status == "awaiting_input",
							tooltip = zeron.s("badges.open_inspector"),
						},
					},
					IconButton {
						icon = "arrow-up-right",
						size = "sm",
						tone = "quiet",
						label = `Open Captain {parent_name}`,
						on_click = function()
							if w.captain_id then
								pcall(zeron.open, { session = w.captain_id })
							end
						end,
					},
				}
			end

			-- Normal chat: subtle, unambiguous 1-click Promote button.
			return Button {
				tone = "ghost",
				size = "xs",
				tooltip = zeron.s("badges.promote_tooltip"),
				on_click = function()
					local title = client.session_title(sid)
					client.call("promote_captain", { chat_id = sid, name = title }):after(function()
						zeron.toast(zeron.s("toast.promoted"))
						client.open_inspector(panel, sid)
					end, function() end)
				end,
				Icon { name = "users-group-rounded", size = 12 },
				zeron.s("badges.promote_short"),
			}
		end)
	end)

	return M
end

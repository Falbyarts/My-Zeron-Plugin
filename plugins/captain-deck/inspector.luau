--!strict
-- Side-panel Crew Inspector tab (`zeron.tab("captain-inspector", ...)`).
--
-- Features:
-- 1. Reactive synchronization of Captain form fields (`last_synced_key` tracker)
--    whenever `captain_id` or underlying Captain state updates, plus a manual
--    "Reset / Sync" button.
-- 2. Clear visual hierarchy between the Captain parent card and the Indented
--    Crew Tree (using `ui.div { w = 2, self = "stretch", ... }` vertical
--    connector line, contrasting Role/Harness badges, and subtle report boxes).

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local EmptyState = require("@ds/empty_state")
local FadeText = require("@ds/fade_text")
local Icon = require("@ds/icon")
local IconButton = require("@ds/icon_button").IconButton
local Select = require("@ds/select")
local Settings = require("@ds/settings")
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

local function trim(s: string?): string
	if type(s) ~= "string" then
		return ""
	end
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function role_badge_tone(role: string?): "neutral" | "accent" | "info" | "success" | "warning" | "danger"
	local r = string.lower(role or "")
	if r == "builder" or string.find(r, "candidate", 1, true) then
		return "accent"
	elseif r == "reviewer" then
		return "info"
	elseif r == "tester" then
		return "success"
	elseif r == "researcher" or r == "planner" then
		return "warning"
	end
	return "neutral"
end

return function(zeron: any, client: any): (props: { tab: any }) -> Node
	return ui.component(function(props: { tab: any }): Node
		local function current_captain_id(): string
			local d = props.tab and props.tab.data or {}
			return if type(d.captain_id) == "string" then d.captain_id else ""
		end

		local init_cid = current_captain_id()
		local init_cap = client.captain_of(init_cid)

		local name_val = ui.use_state(if init_cap then init_cap.name or "Captain" else "Captain")
		local mission_val = ui.use_state(if init_cap then init_cap.mission or "" else "")
		local rules_val = ui.use_state(if init_cap then init_cap.rules or "" else "")
		local digest_val = ui.use_state(if init_cap then init_cap.digest or "" else "")
		local sched_mins = ui.use_state(
			if init_cap and init_cap.schedule_mins and init_cap.schedule_mins > 0
				then tostring(init_cap.schedule_mins)
				else ""
		)
		local sched_prompt = ui.use_state(if init_cap then init_cap.schedule_prompt or "" else "")
		local auto_report = ui.use_state(if init_cap then init_cap.auto_report ~= false else true)

		local last_synced_key = ui.use_state("")
		local last_synced_cid = ui.use_state("")

		local show_notes = ui.use_state(false)
		local show_spawn = ui.use_state(false)
		local saving = ui.use_state(false)

		-- Quick spawn form state
		local sp_role = ui.use_state("builder")
		local sp_harness = ui.use_state("")
		local sp_custom_harness = ui.use_state("")
		local sp_model = ui.use_state("")
		local sp_project = ui.use_state("")
		local sp_task = ui.use_state("")
		local sp_prompt = ui.use_state("")
		local spawning = ui.use_state(false)

		-- Inline steer state
		local steer_target = ui.use_state(nil :: string?)
		local steer_text = ui.use_state("")
		local sending = ui.use_state(false)

		local function sync_form_from_captain(cid: string, cap: any, sync_key: string?)
			name_val:set(cap.name or "Captain")
			mission_val:set(cap.mission or "")
			rules_val:set(cap.rules or "")
			digest_val:set(cap.digest or "")
			auto_report:set(cap.auto_report ~= false)
			sched_mins:set(if cap.schedule_mins and cap.schedule_mins > 0 then tostring(cap.schedule_mins) else "")
			sched_prompt:set(cap.schedule_prompt or "")
			last_synced_cid:set(cid)
			if sync_key then
				last_synced_key:set(sync_key)
			end
		end

		local function save_captain()
			local cid = current_captain_id()
			if cid == "" then
				return
			end
			saving:set(true)
			local mins = tonumber(sched_mins:peek()) or 0
			client.call("update_captain", {
				chat_id = cid,
				name = name_val:peek(),
				mission = mission_val:peek(),
				rules = rules_val:peek(),
				digest = digest_val:peek(),
				auto_report = auto_report:peek(),
				schedule_mins = mins,
				schedule_prompt = sched_prompt:peek(),
			}):after(function()
				saving:set(false)
				show_notes:set(false)
				zeron.toast(zeron.s("toast.saved"))
			end, function()
				saving:set(false)
			end)
		end

		local function spawn_worker()
			local cid = current_captain_id()
			local prompt = trim(sp_prompt:peek())
			if prompt == "" then
				zeron.toast("Enter a prompt for the worker")
				return
			end
			spawning:set(true)
			local custom = trim(sp_custom_harness:peek())
			local chosen_harness = if custom ~= "" then custom else sp_harness:peek()
			client.call("spawn_worker", {
				captain_id = cid,
				role = sp_role:peek(),
				task = sp_task:peek(),
				prompt = prompt,
				harness = chosen_harness,
				model = sp_model:peek(),
				project = sp_project:peek(),
			}):after(function()
				spawning:set(false)
				sp_task:set("")
				sp_prompt:set("")
				show_spawn:set(false)
				zeron.toast(zeron.s("toast.worker_spawned"))
			end, function()
				spawning:set(false)
			end)
		end

		local function send_steer(chat_id: string, mode: string)
			local txt = trim(steer_text:peek())
			if txt == "" then
				return
			end
			sending:set(true)
			client.call("message_chat", {
				chat_id = chat_id,
				text = txt,
				mode = mode,
			}):after(function()
				sending:set(false)
				steer_text:set("")
				steer_target:set(nil)
				zeron.toast(zeron.s("toast.message_sent"))
			end, function()
				sending:set(false)
			end)
		end

		return ui.scroll {
			w_full = true,
			h_full = true,
			fade = { 12, 12 },
			fade_overflow = true,
			ui.column {
				w_full = true,
				p = "$space.4",
				gap = "$space.5",
				ui.presence(function(): string
					local cid = current_captain_id()
					local cap = client.captain_of(cid)
					if not cap then
						return `missing:{cid}`
					end
					local s = client.state:get()
					local sync_key =
						`{cid}:{cap.name or ""}:{cap.mission or ""}:{cap.rules or ""}:{cap.digest or ""}:{tostring(cap.auto_report)}:{tostring(cap.schedule_mins or 0)}:{cap.schedule_prompt or ""}`
					return `ok:{cid}:{s and s.rev or 0}:{sync_key}:{tostring(show_notes:get())}:{tostring(show_spawn:get())}:{tostring(steer_target:get())}`
				end, function(key: string): Node
					if string.sub(key, 1, 8) == "missing:" then
						return EmptyState {
							size = "sm",
							icon = "users-group-rounded",
							title = zeron.s("inspector.not_found"),
							body = "Promote a chat to a Captain to inspect its crew here.",
						}
					end

					local cid = current_captain_id()
					local cap = client.captain_of(cid)
					if not cap then
						return ui.div {}
					end

					-- Reactive form synchronization when captain_id changes or live state updates while not actively editing
					local sync_key =
						`{cid}:{cap.name or ""}:{cap.mission or ""}:{cap.rules or ""}:{cap.digest or ""}:{tostring(cap.auto_report)}:{tostring(cap.schedule_mins or 0)}:{cap.schedule_prompt or ""}`
					if last_synced_cid:peek() ~= cid or (not show_notes:peek() and last_synced_key:peek() ~= sync_key) then
						sync_form_from_captain(cid, cap, sync_key)
					end

					local crew = client.crew_of(cid)
					local sum = client.crew_summary(cid)

					local pending_ny: { any } = {}
					for _, item in (cap.needs_you or {}) do
						if not item.resolved then
							table.insert(pending_ny, item)
						end
					end

					local sections: { Node } = {}

					-- 1. Captain Header Card (Clear Parent Overview)
					local cap_badges: { Node } = {
						Badge.Badge { zeron.s("badges.captain"), tone = "accent", size = "sm" },
						Badge.Badge {
							cap.status or "idle",
							tone = client.status_tone(cap.status),
							size = "sm",
							dot = cap.status == "running" or cap.status == "awaiting_input",
						},
					}
					if cap.harness and cap.harness ~= "" then
						table.insert(cap_badges, Badge.Badge { cap.harness, tone = "neutral", size = "sm" })
					end
					if cap.model and cap.model ~= "" then
						table.insert(cap_badges, Badge.Badge { cap.model, tone = "neutral", size = "sm", look = "outline" })
					end
					table.insert(
						cap_badges,
						Badge.Badge {
							if sum.running > 0
								then `{sum.total} crew · {sum.running} running`
								else `{sum.total} crew`,
							tone = if sum.attention > 0 then "warning" elseif sum.running > 0 then "accent" else "info",
							size = "sm",
							dot = sum.running > 0 or sum.attention > 0,
							tabular = true,
						}
					)
					if cap.schedule_mins and cap.schedule_mins >= 5 then
						table.insert(
							cap_badges,
							Badge.Badge {
								`Every {cap.schedule_mins}m`,
								tone = "info",
								size = "sm",
								icon = "clock-circle",
							}
						)
					end

					table.insert(
						sections,
						Settings.Section {
							title = "Captain",
							Settings.Group {
								ui.column {
									w_full = true,
									p = "$space.4",
									gap = "$space.3",
									ui.row {
										w_full = true,
										flex_wrap = true,
										items = "center",
										justify = "between",
										gap = "$space.2",
										ui.row {
											grow = 1,
											min_w = 180,
											items = "center",
											gap = "$space.3",
											ui.div {
												w = 32,
												h = 32,
												shrink = 0,
												rounded = "$radius.md",
												bg = "$bg.surface",
												border = 1,
												border_color = "$border.subtle",
												items = "center",
												justify = "center",
												Icon { name = "users-group-rounded", size = 16, color = "$fg.accent" },
											},
											ui.column {
												grow = 1,
												min_w = 0,
												gap = "$space.1",
												ui.row {
													w_full = true,
													flex_wrap = true,
													items = "center",
													gap = "$space.2",
													Status.StatusIcon { kind = client.status_kind(cap.status) :: any, size = 15 },
													Text {
														cap.name or "Captain",
														text_size = "$font.size.md",
														weight = "$font.weight.semibold",
														color = "$text.primary",
													},
												},
												ui.row {
													flex_wrap = true,
													items = "center",
													gap = "$space.1",
													table.unpack(cap_badges),
												},
											},
										},
										ui.row {
											gap = "$space.1",
											items = "center",
											Button {
												size = "xs",
												tone = "primary",
												on_click = function()
													show_spawn:set(not show_spawn:peek())
												end,
												Icon { name = "plus", size = 12 },
												zeron.s("deck.fleet.spawn_worker"),
											},
											IconButton {
												icon = "pen",
												size = "sm",
												tone = "quiet",
												lit = show_notes,
												label = "Edit Rules & Schedule",
												on_click = function()
													sync_form_from_captain(cid, cap, sync_key)
													show_notes:set(not show_notes:peek())
												end,
											},
											IconButton {
												icon = "arrow-up-right",
												size = "sm",
												tone = "quiet",
												label = "Open Captain chat",
												on_click = function()
													zeron.open({ session = cid })
												end,
											},
										},
									},

									if cap.mission and cap.mission ~= ""
										then Text {
											cap.mission,
											style = "caption",
											tone = "secondary",
											wrap = true,
										}
										else Text {
											"Long-lived orchestrator thread",
											style = "caption",
											tone = "tertiary",
										},

									if not show_notes:peek() and ((cap.digest and cap.digest ~= "") or (cap.rules and cap.rules ~= ""))
										then ui.column {
											w_full = true,
											gap = "$space.1",
											if cap.digest and cap.digest ~= ""
												then ui.row {
													w_full = true,
													items = "center",
													gap = "$space.2",
													px = "$space.2",
													py = "$space.1",
													rounded = "$radius.md",
													bg = "$bg.surface",
													Badge.Badge { zeron.s("deck.fleet.digest_label"), tone = "info", size = "sm" },
													Text {
														cap.digest,
														style = "caption",
														tone = "secondary",
														wrap = true,
													},
												}
												else nil,
											if cap.rules and cap.rules ~= ""
												then ui.row {
													w_full = true,
													items = "center",
													gap = "$space.2",
													px = "$space.2",
													py = "$space.1",
													rounded = "$radius.md",
													bg = "$bg.surface",
													Badge.Badge { zeron.s("deck.fleet.rules_label"), tone = "neutral", size = "sm" },
													Text {
														cap.rules,
														style = "caption",
														tone = "secondary",
														wrap = true,
													},
												}
												else nil,
										}
										else nil,
								},
							},
						}
					)

					-- 2. Editable Rules / Digest / Schedule Group
					if show_notes:peek() then
						table.insert(
							sections,
							Settings.Section {
								title = "Captain Configuration",
								trail = Button {
									size = "xs",
									tone = "ghost",
									on_click = function()
										sync_form_from_captain(cid, cap, sync_key)
									end,
									Icon { name = "refresh", size = 12 },
									zeron.s("inspector.reset_sync"),
								},
								Settings.Group {
									Settings.Row {
										label = "Captain Name",
										stacked = true,
										control = TextField { value = name_val, size = "sm", w_full = true },
									},
									Settings.Row {
										label = zeron.s("inspector.mission"),
										stacked = true,
										control = TextField {
											value = mission_val,
											placeholder = "What goal does this Captain own?",
											size = "sm",
											w_full = true,
										},
									},
									Settings.Row {
										label = zeron.s("inspector.rules"),
										description = "Automatically prepended to every worker spawned under this Captain.",
										stacked = true,
										control = TextArea {
											value = rules_val,
											placeholder = "e.g. Always run tests. Never push without asking.",
											rows = 3,
											max_rows = 6,
											size = "sm",
											w_full = true,
										},
									},
									Settings.Row {
										label = zeron.s("inspector.digest"),
										stacked = true,
										control = TextArea {
											value = digest_val,
											placeholder = "Current progress summary or working notes…",
											rows = 3,
											max_rows = 6,
											size = "sm",
											w_full = true,
										},
									},
									Settings.Row {
										label = "Auto-report to Captain",
										description = "Send worker completion summaries back to this Captain chat.",
										control = Switch { value = auto_report, label = "Auto-report" },
									},
									Settings.Row {
										label = "Scheduled Wake (minutes, 0 = off)",
										description = "Wake this Captain periodically when idle (minimum 5 minutes).",
										stacked = true,
										control = ui.column {
											w_full = true,
											gap = "$space.2",
											TextField { value = sched_mins, placeholder = "0 (off) or e.g. 60", size = "sm", w_full = true },
											TextField {
												value = sched_prompt,
												placeholder = "Wake prompt, e.g. Check crew reports and update digest.",
												size = "sm",
												w_full = true,
											},
										},
									},
									ui.row {
										w_full = true,
										px = "$space.4",
										py = "$space.3",
										gap = "$space.2",
										justify = "end",
										Button {
											size = "sm",
											tone = "ghost",
											on_click = function()
												show_notes:set(false)
											end,
											zeron.s("dialogs.cancel"),
										},
										Button {
											size = "sm",
											tone = "primary",
											busy = saving,
											on_click = save_captain,
											zeron.s("inspector.save_notes"),
										},
									},
								},
							}
						)
					end

					-- 3. Quick Spawn Worker Group
					if show_spawn:peek() then
						table.insert(
							sections,
							Settings.Section {
								title = zeron.s("inspector.spawn_heading"),
								Settings.Group {
									Settings.Row {
										label = "Role",
										stacked = true,
										control = Select { value = sp_role, options = ROLES, size = "sm", w_full = true },
									},
									Settings.Row {
										label = "Harness",
										description = "Choose any harness in Zeron, or enter a custom ACP id below.",
										stacked = true,
										control = ui.column {
											w_full = true,
											gap = "$space.2",
											Select {
												value = sp_harness,
												options = function()
													return client.harness_options(true)
												end,
												size = "sm",
												w_full = true,
												on_change = function()
													sp_model:set("")
												end,
											},
											TextField {
												value = sp_custom_harness,
												placeholder = "Optional custom harness id (e.g. acp.gemini, hermes, pi)",
												size = "sm",
												w_full = true,
											},
										},
									},
									Settings.Row {
										label = "Model",
										stacked = true,
										control = Select {
											value = sp_model,
											options = function()
												local custom = trim(sp_custom_harness:get())
												return client.models_for(if custom ~= "" then custom else sp_harness:get())
											end,
											size = "sm",
											w_full = true,
										},
									},
									Settings.Row {
										label = "Project",
										stacked = true,
										control = Select {
											value = sp_project,
											options = function()
												return client.project_options()
											end,
											size = "sm",
											w_full = true,
										},
									},
									Settings.Row {
										label = "Task & Prompt",
										stacked = true,
										control = ui.column {
											w_full = true,
											gap = "$space.2",
											TextField {
												value = sp_task,
												placeholder = "Short task title shown in Crew tree",
												size = "sm",
												w_full = true,
											},
											TextArea {
												value = sp_prompt,
												placeholder = "Full instructions for this worker…",
												rows = 3,
												max_rows = 8,
												size = "sm",
												w_full = true,
											},
										},
									},
									ui.row {
										w_full = true,
										px = "$space.4",
										py = "$space.3",
										gap = "$space.2",
										justify = "end",
										Button {
											size = "sm",
											tone = "ghost",
											on_click = function()
												show_spawn:set(false)
											end,
											zeron.s("dialogs.cancel"),
										},
										Button {
											size = "sm",
											tone = "primary",
											busy = spawning,
											on_click = spawn_worker,
											Icon { name = "action-play", size = 12 },
											zeron.s("dialogs.spawn"),
										},
									},
								},
							}
						)
					end

					-- 4. Needs You escalations
					if #pending_ny > 0 then
						local ny_rows: { Node } = {}
						for _, item in pending_ny do
							table.insert(
								ny_rows,
								Settings.Row {
									icon = "bell",
									label = item.title or "Needs decision",
									description = item.detail,
									control = ui.row {
										gap = "$space.1",
										items = "center",
										Button {
											size = "xs",
											tone = "secondary",
											on_click = function()
												zeron.open({ session = item.worker_chat or cid })
											end,
											zeron.s("deck.attention.open_chat"),
										},
										Button {
											size = "xs",
											tone = "ghost",
											on_click = function()
												client.call("resolve_attention", { captain_id = cid, item_id = item.id })
											end,
											zeron.s("deck.attention.resolve"),
										},
									},
								}
							)
						end
						table.insert(
							sections,
							Settings.Section {
								title = zeron.s("deck.attention.title"),
								Settings.Group(ny_rows),
							}
						)
					end

					-- 5. Indented Crew Tree Section
					if #crew == 0 then
						table.insert(
							sections,
							Settings.Section {
								title = zeron.s("inspector.crew_heading", { n = 0 }),
								Settings.Group {
									ui.column {
										w_full = true,
										py = "$space.5",
										px = "$space.4",
										EmptyState {
											size = "sm",
											icon = "bot",
											title = "No crew assigned yet",
											body = zeron.s("deck.fleet.no_crew"),
											action = {
												label = zeron.s("deck.fleet.spawn_worker"),
												icon = "plus",
												on_click = function()
													show_spawn:set(true)
												end,
											},
										},
									},
								},
							}
						)
					else
						local crew_rows: { Node } = {}
						for idx, w in crew do
							local is_last = idx == #crew
							local branch_char = if is_last then "└─" else "├─"
							local is_steering = steer_target:peek() == w.chat_id
							local reply = trim(w.last_reply or "")
							local preview = if w.last_error and w.last_error ~= ""
								then w.last_error
								elseif #reply > 220
								then string.sub(reply, 1, 219) .. "…"
								else reply

							table.insert(
								crew_rows,
								ui.column {
									w_full = true,
									py = "$space.2",
									gap = "$space.2",
									ui.row {
										w_full = true,
										gap = "$space.2",
										items = "center",
										Text { branch_char, style = "mono", tone = "tertiary" },
										Status.StatusIcon { kind = client.status_kind(w.status) :: any, size = 14 },
										FadeText {
											w.task or client.session_title(w.chat_id),
											grow = 1,
											min_w = 0,
											text_size = "$font.size.md",
											weight = "$font.weight.medium",
											color = "$text.primary",
										},
										IconButton {
											icon = "chat-round-line",
											size = "sm",
											tone = "quiet",
											lit = is_steering,
											label = "Message or steer worker",
											on_click = function()
												if steer_target:peek() == w.chat_id then
													steer_target:set(nil)
												else
													steer_target:set(w.chat_id)
													steer_text:set("")
												end
											end,
										},
										IconButton {
											icon = "arrow-up-right",
											size = "sm",
											tone = "quiet",
											label = "Open worker chat",
											on_click = function()
												zeron.open({ session = w.chat_id })
											end,
										},
										IconButton {
											icon = "close",
											size = "sm",
											tone = "danger",
											label = "Detach worker",
											on_click = function()
												client.call("detach_worker", { worker_chat = w.chat_id }):after(function()
													zeron.toast(zeron.s("toast.worker_detached"))
												end, function() end)
											end,
										},
									},
									ui.row {
										w_full = true,
										gap = "$space.1",
										items = "center",
										flex_wrap = true,
										Badge.Badge {
											w.role or "worker",
											tone = role_badge_tone(w.role),
											size = "sm",
										},
										if w.harness and w.harness ~= ""
											then Badge.Badge {
												if w.model and w.model ~= "" then `{w.harness} · {w.model}` else w.harness,
												tone = "neutral",
												size = "sm",
											}
											elseif w.model and w.model ~= ""
											then Badge.Badge { w.model, tone = "neutral", size = "sm", look = "outline" }
											else nil,
										if w.status and w.status ~= "idle"
											then Badge.Badge {
												w.status,
												tone = client.status_tone(w.status),
												size = "sm",
												dot = w.status == "running" or w.status == "awaiting_input",
											}
											else nil,
										if w.next_stage
											then Badge.Badge {
												`Then → {w.next_stage.role or "reviewer"} ({w.next_stage.harness or "auto"})`,
												tone = "info",
												size = "sm",
												icon = "map-arrow-right",
											}
											else nil,
									},
									if preview ~= ""
										then ui.div {
											w_full = true,
											bg = "$bg.surface",
											rounded = "$radius.md",
											px = "$space.2",
											py = "$space.1",
											border = 1,
											border_color = "$border.subtle",
											Text {
												preview,
												style = "caption",
												tone = if w.last_error and w.last_error ~= "" then "danger" else "secondary",
												wrap = true,
											},
										}
										else nil,
									if is_steering
										then ui.row {
											w_full = true,
											gap = "$space.2",
											items = "center",
											pt = "$space.1",
											ui.column {
												grow = 1,
												min_w = 0,
												TextField {
													value = steer_text,
													placeholder = zeron.s("inspector.steer_placeholder"),
													size = "sm",
													w_full = true,
												},
											},
											Button {
												size = "xs",
												tone = "secondary",
												busy = sending,
												on_click = function()
													send_steer(w.chat_id, "queue")
												end,
												"Queue",
											},
											Button {
												size = "xs",
												tone = "accent",
												busy = sending,
												on_click = function()
													send_steer(w.chat_id, "steer")
												end,
												"Steer",
											},
										}
										else nil,
									if not is_last then Settings.Rule() else nil,
								}
							)
						end

						table.insert(
							sections,
							Settings.Section {
								title = zeron.s("inspector.crew_heading", { n = #crew }),
								Settings.Group {
									ui.row {
										w_full = true,
										pl = "$space.4",
										pr = "$space.3",
										py = "$space.2",
										gap = "$space.3",
										-- Vertical left connector line
										ui.div {
											w = 2,
											self = "stretch",
											rounded = "$radius.full",
											bg = "$border.subtle",
										},
										ui.column {
											grow = 1,
											min_w = 0,
											table.unpack(crew_rows),
										},
									},
								},
							}
						)
					end

					return ui.column { w_full = true, gap = "$space.5", table.unpack(sections) }
				end, { w_full = true }),
			},
		}
	end)
end

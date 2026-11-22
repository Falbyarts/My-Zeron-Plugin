--!strict
-- Side-panel Crew Inspector tab (`zeron.tab("captain-inspector", ...)`).
--
-- Built with Zeron's native `Settings` design system (`Settings.Section`,
-- `Settings.Group`, `Settings.Row`, `Settings.Rule`) so it matches Zeron's own
-- settings and panel screens down to the exact spacing, rounded card edges,
-- hairlines, and control alignment.

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

return function(zeron: any, client: any): (props: { tab: any }) -> Node
	return ui.component(function(props: { tab: any }): Node
		local data = props.tab and props.tab.data or {}
		local captain_id = if type(data.captain_id) == "string" then data.captain_id else ""

		local init_cap = client.captain_of(captain_id)
		local name_val = ui.use_state(if init_cap then init_cap.name or "Captain" else "Captain")
		local mission_val = ui.use_state(if init_cap then init_cap.mission or "" else "")
		local rules_val = ui.use_state(if init_cap then init_cap.rules or "" else "")
		local digest_val = ui.use_state(if init_cap then init_cap.digest or "" else "")
		local sched_mins = ui.use_state(if init_cap and init_cap.schedule_mins and init_cap.schedule_mins > 0 then tostring(init_cap.schedule_mins) else "")
		local sched_prompt = ui.use_state(if init_cap then init_cap.schedule_prompt or "" else "")
		local auto_report = ui.use_state(if init_cap then init_cap.auto_report ~= false else true)
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

		local function save_captain()
			saving:set(true)
			local mins = tonumber(sched_mins:peek()) or 0
			client.call("update_captain", {
				chat_id = captain_id,
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
			local prompt = trim(sp_prompt:peek())
			if prompt == "" then
				zeron.toast("Enter a prompt for the worker")
				return
			end
			spawning:set(true)
			local custom = trim(sp_custom_harness:peek())
			local chosen_harness = if custom ~= "" then custom else sp_harness:peek()
			client.call("spawn_worker", {
				captain_id = captain_id,
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
					local cap = client.captain_of(captain_id)
					if not cap then
						return "missing"
					end
					local s = client.state:get()
					return `ok:{s and s.rev or 0}:{tostring(show_notes:get())}:{tostring(show_spawn:get())}:{tostring(steer_target:get())}`
				end, function(key: string): Node
					if key == "missing" then
						return EmptyState {
							size = "sm",
							icon = "users-group-rounded",
							title = zeron.s("inspector.not_found"),
							body = "Promote a chat to a Captain to inspect its crew here.",
						}
					end

					local cap = client.captain_of(captain_id)
					if not cap then
						return ui.div {}
					end
					local crew = client.crew_of(captain_id)
					local sum = client.crew_summary(captain_id)

					local pending_ny: { any } = {}
					for _, item in (cap.needs_you or {}) do
						if not item.resolved then
							table.insert(pending_ny, item)
						end
					end

					local sections: { Node } = {}

					-- 1. Captain Summary Group (Settings style)
					local cap_rows: { Node } = {
						Settings.Row {
							lead = Status.StatusIcon { kind = client.status_kind(cap.status) :: any, size = 16 },
							label = cap.name or "Captain",
							badge = ui.row {
								gap = "$space.1",
								items = "center",
								if cap.harness and cap.harness ~= ""
									then Badge.Badge { cap.harness, tone = "neutral", size = "sm" }
									else nil,
								Badge.Badge {
									`{sum.total} crew`,
									tone = if sum.attention > 0 then "warning" elseif sum.running > 0 then "accent" else "info",
									size = "sm",
									dot = sum.running > 0 or sum.attention > 0,
									tabular = true,
								},
							},
							description = if cap.mission and cap.mission ~= "" then cap.mission else "Long-lived orchestrator thread",
							control = ui.row {
								gap = "$space.1",
								items = "center",
								Button {
									size = "xs",
									tone = "primary",
									on_click = function()
										show_spawn:set(not show_spawn:peek())
									end,
									Icon { name = "plus", size = 12 },
									"Spawn",
								},
								IconButton {
									icon = "pen",
									size = "sm",
									tone = "quiet",
									lit = show_notes,
									label = "Edit Rules & Schedule",
									on_click = function()
										name_val:set(cap.name or "Captain")
										mission_val:set(cap.mission or "")
										rules_val:set(cap.rules or "")
										digest_val:set(cap.digest or "")
										auto_report:set(cap.auto_report ~= false)
										sched_mins:set(if cap.schedule_mins and cap.schedule_mins > 0 then tostring(cap.schedule_mins) else "")
										sched_prompt:set(cap.schedule_prompt or "")
										show_notes:set(not show_notes:peek())
									end,
								},
								IconButton {
									icon = "arrow-up-right",
									size = "sm",
									tone = "quiet",
									label = "Open Captain chat",
									on_click = function()
										zeron.open({ session = captain_id })
									end,
								},
							},
						},
					}

					if cap.digest and cap.digest ~= "" and not show_notes:peek() then
						table.insert(cap_rows, Settings.Row {
							icon = "document",
							label = zeron.s("deck.fleet.digest_label"),
							description = cap.digest,
						})
					end

					if cap.rules and cap.rules ~= "" and not show_notes:peek() then
						table.insert(cap_rows, Settings.Row {
							icon = "shield-check",
							label = zeron.s("deck.fleet.rules_label"),
							description = cap.rules,
						})
					end

					table.insert(sections, Settings.Section {
						title = "Captain",
						Settings.Group(cap_rows),
					})

					-- 2. Editable Rules / Digest / Schedule Group
					if show_notes:peek() then
						table.insert(sections, Settings.Section {
							title = "Captain Configuration",
							Settings.Group {
								Settings.Row {
									label = "Captain Name",
									stacked = true,
									control = TextField { value = name_val, size = "sm" },
								},
								Settings.Row {
									label = zeron.s("inspector.mission"),
									stacked = true,
									control = TextField { value = mission_val, placeholder = "What goal does this Captain own?", size = "sm" },
								},
								Settings.Row {
									label = zeron.s("inspector.rules"),
									description = "Automatically prepended to every worker spawned under this Captain.",
									stacked = true,
									control = TextArea { value = rules_val, placeholder = "e.g. Always run tests. Never push without asking.", rows = 3, max_rows = 6, size = "sm" },
								},
								Settings.Row {
									label = zeron.s("inspector.digest"),
									stacked = true,
									control = TextArea { value = digest_val, placeholder = "Current progress summary or working notes…", rows = 3, max_rows = 6, size = "sm" },
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
										TextField { value = sched_mins, placeholder = "0 (off) or e.g. 60", size = "sm" },
										TextField { value = sched_prompt, placeholder = "Wake prompt, e.g. Check crew reports and update digest.", size = "sm" },
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
						})
					end

					-- 3. Quick Spawn Worker Group
					if show_spawn:peek() then
						table.insert(sections, Settings.Section {
							title = zeron.s("inspector.spawn_heading"),
							Settings.Group {
								Settings.Row {
									label = "Role",
									control = Select { value = sp_role, options = ROLES, size = "sm" },
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
										TextField { value = sp_task, placeholder = "Short task title shown in Crew tree", size = "sm" },
										TextArea { value = sp_prompt, placeholder = "Full instructions for this worker…", rows = 3, max_rows = 8, size = "sm" },
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
						})
					end

					-- 4. Needs You escalations
					if #pending_ny > 0 then
						local ny_rows: { Node } = {}
						for _, item in pending_ny do
							table.insert(ny_rows, Settings.Row {
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
											zeron.open({ session = item.worker_chat or captain_id })
										end,
										zeron.s("deck.attention.open_chat"),
									},
									Button {
										size = "xs",
										tone = "ghost",
										on_click = function()
											client.call("resolve_attention", { captain_id = captain_id, item_id = item.id })
										end,
										zeron.s("deck.attention.resolve"),
									},
								},
							})
						end
						table.insert(sections, Settings.Section {
							title = zeron.s("deck.attention.title"),
							Settings.Group(ny_rows),
						})
					end

					-- 5. Crew Workers Section
					if #crew == 0 then
						table.insert(sections, Settings.Section {
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
						})
					else
						local crew_rows: { Node } = {}
						for _, w in crew do
							local is_steering = steer_target:peek() == w.chat_id
							local reply = trim(w.last_reply or "")
							local preview = if w.last_error and w.last_error ~= ""
								then w.last_error
								elseif #reply > 220
								then string.sub(reply, 1, 219) .. "…"
								else reply

							table.insert(crew_rows, ui.column {
								w_full = true,
								px = "$space.4",
								py = "$space.3",
								gap = "$space.2",
								ui.row {
									w_full = true,
									gap = "$space.2",
									items = "center",
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
									Badge.Badge { w.role or "worker", tone = client.status_tone(w.status), size = "sm" },
									if w.harness and w.harness ~= ""
										then Badge.Badge { w.harness, tone = "neutral", size = "sm" }
										else nil,
									if w.model and w.model ~= ""
										then Badge.Badge { w.model, tone = "neutral", size = "sm", look = "outline" }
										else nil,
									if w.next_stage
										then Badge.Badge {
											`Then -> {w.next_stage.role or "reviewer"} ({w.next_stage.harness or "auto"})`,
											tone = "info",
											size = "sm",
											icon = "map-arrow-right",
										}
										else nil,
								},
								if preview ~= ""
									then Text {
										preview,
										style = "caption",
										tone = if w.last_error and w.last_error ~= "" then "danger" else "secondary",
									}
									else nil,
								if is_steering
									then ui.row {
										w_full = true,
										gap = "$space.2",
										items = "center",
										pt = "$space.1",
										TextField {
											value = steer_text,
											placeholder = zeron.s("inspector.steer_placeholder"),
											size = "sm",
											grow = 1,
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
							})
						end

						table.insert(sections, Settings.Section {
							title = zeron.s("inspector.crew_heading", { n = #crew }),
							Settings.Group(crew_rows),
						})
					end

					return ui.column { w_full = true, gap = "$space.5", table.unpack(sections) }
				end, { w_full = true }),
			},
		}
	end)
end

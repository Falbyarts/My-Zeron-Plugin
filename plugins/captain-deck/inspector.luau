--!strict
-- Side-panel Crew Inspector tab (`zeron.tab("captain-inspector", ...)`).
--
-- Opens beside any Captain chat, Worker chat, or on the Captain Deck page.
-- Lets the user inspect live crew status and latest replies, send/steer
-- workers inline, spawn new workers on ANY harness/model, edit the Captain's
-- mission/rules/digest/schedule, and manage Needs You items.

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local EmptyState = require("@ds/empty_state")
local Icon = require("@ds/icon")
local IconButton = require("@ds/icon_button").IconButton
local Select = require("@ds/select")
local Status = require("@ds/status")
local Surface = require("@ds/surface")
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

		-- Inline steer state (one worker expanded at a time)
		local steer_target = ui.use_state(nil :: string?)
		local steer_text = ui.use_state("")
		local sending = ui.use_state(false)

		-- Expanded report state
		local expanded_reply = ui.use_state(nil :: string?)

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
				zeron.toast(zeron.s("toast.saved"))
			end, function()
				saving:set(false)
			end)
		end

		local function spawn_worker()
			local prompt = sp_prompt:peek()
			if string.match(prompt, "^%s*$") then
				zeron.toast("Enter a prompt for the worker")
				return
			end
			spawning:set(true)
			local custom = string.gsub(sp_custom_harness:peek(), "^%s*(.-)%s*$", "%1")
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
			local txt = steer_text:peek()
			if string.match(txt, "^%s*$") then
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
			ui.column {
				w_full = true,
				p = "$space.4",
				gap = "$space.4",
				ui.presence(function(): string
					local cap = client.captain_of(captain_id)
					if not cap then
						return "missing"
					end
					local s = client.state:get()
					return `ok:{s and s.rev or 0}:{tostring(show_notes:get())}:{tostring(show_spawn:get())}:{tostring(steer_target:get())}:{tostring(expanded_reply:get())}`
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

					-- Unresolved Needs You items on this captain
					local pending_ny: { any } = {}
					for _, item in (cap.needs_you or {}) do
						if not item.resolved then
							table.insert(pending_ny, item)
						end
					end

					local sections: { Node } = {}

					-- 1. Captain Header Card
					table.insert(sections, Surface {
						kind = "raised",
						w_full = true,
						p = "$space.3",
						ui.column {
							w_full = true,
							gap = "$space.2",
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								Status.StatusIcon { kind = client.status_kind(cap.status) :: any, size = 14 },
								Text { cap.name or "Captain", style = "heading", truncate = true, grow = 1, min_w = 0 },
								if cap.harness and cap.harness ~= ""
									then Badge.Badge { cap.harness, tone = "neutral", size = "sm" }
									else ui.div {},
							},
							if cap.mission and cap.mission ~= ""
								then Text { cap.mission, style = "caption", tone = "secondary" }
								else ui.div {},
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								wrap = true,
								Badge.Badge {
									`{sum.total} crew`,
									tone = "info",
									size = "sm",
									tabular = true,
								},
								if sum.running > 0
									then Badge.Badge { `{sum.running} running`, tone = "accent", size = "sm", dot = true, tabular = true }
									else ui.div {},
								if sum.attention > 0
									then Badge.Badge { `{sum.attention} needs you`, tone = "warning", size = "sm", dot = true, tabular = true }
									else ui.div {},
								Badge.Badge {
									if cap.auto_report ~= false then zeron.s("deck.fleet.auto_report_on") else zeron.s("deck.fleet.auto_report_off"),
									tone = if cap.auto_report ~= false then "success" else "neutral",
									size = "sm",
								},
								if cap.schedule_mins and cap.schedule_mins >= 5
									then Badge.Badge { `Every {cap.schedule_mins}m`, tone = "info", size = "sm", icon = "clock-circle" }
									else ui.div {},
							},
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								wrap = true,
								Button {
									size = "xs",
									tone = "primary",
									on_click = function()
										show_spawn:set(not show_spawn:peek())
									end,
									Icon { name = "plus", size = 12 },
									zeron.s("deck.fleet.spawn_worker"),
								},
								Button {
									size = "xs",
									tone = "secondary",
									on_click = function()
										zeron.open({ session = captain_id })
									end,
									Icon { name = "arrow-up-right", size = 12 },
									zeron.s("deck.fleet.open_chat"),
								},
								Button {
									size = "xs",
									tone = "ghost",
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
									Icon { name = "pen", size = 12 },
									if show_notes:peek() then "Hide Notes" else "Rules & Digest",
								},
							},
						},
					})

					-- 2. Editable Mission / Rules / Digest / Schedule drawer
					if show_notes:peek() then
						table.insert(sections, Surface {
							kind = "sunken",
							w_full = true,
							p = "$space.3",
							ui.column {
								w_full = true,
								gap = "$space.3",
								TextField { value = name_val, label = "Captain Name", size = "sm" },
								TextField { value = mission_val, label = zeron.s("inspector.mission"), placeholder = "What is this Captain responsible for?", size = "sm" },
								TextArea { value = rules_val, label = zeron.s("inspector.rules"), placeholder = "e.g. Always run tests before reporting. Never push without asking.", rows = 3, max_rows = 6, size = "sm" },
								TextArea { value = digest_val, label = zeron.s("inspector.digest"), placeholder = "Current progress summary or working notes…", rows = 3, max_rows = 6, size = "sm" },
								ui.row {
									w_full = true,
									gap = "$space.2",
									items = "center",
									justify = "between",
									Text { "Auto-report worker completions to Captain", style = "caption", tone = "secondary" },
									Switch { value = auto_report, label = "Auto-report" },
								},
								ui.row {
									w_full = true,
									gap = "$space.2",
									TextField { value = sched_mins, label = "Wake interval (mins, 0 = off)", placeholder = "e.g. 60", size = "sm", grow = 1 },
								},
								TextField { value = sched_prompt, label = "Scheduled wake prompt", placeholder = "e.g. Check open crew reports and update digest.", size = "sm" },
								ui.row {
									w_full = true,
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

					-- 3. Quick Spawn Worker form
					if show_spawn:peek() then
						table.insert(sections, Surface {
							kind = "sunken",
							w_full = true,
							p = "$space.3",
							ui.column {
								w_full = true,
								gap = "$space.2",
								Text { zeron.s("inspector.spawn_heading"), style = "heading" },
								Select { value = sp_role, options = ROLES, label = "Role", size = "sm", w_full = true },
								Select {
									value = sp_harness,
									options = function()
										return client.harness_options(true)
									end,
									label = "Harness (any installed or ACP harness)",
									size = "sm",
									w_full = true,
									on_change = function()
										sp_model:set("")
									end,
								},
								TextField {
									value = sp_custom_harness,
									label = "Custom harness id (optional override)",
									placeholder = "e.g. acp.gemini, hermes, opencode, pi",
									size = "sm",
								},
								Select {
									value = sp_model,
									options = function()
										local custom = string.gsub(sp_custom_harness:get(), "^%s*(.-)%s*$", "%1")
										return client.models_for(if custom ~= "" then custom else sp_harness:get())
									end,
									label = "Model",
									size = "sm",
									w_full = true,
								},
								Select {
									value = sp_project,
									options = function()
										return client.project_options()
									end,
									label = "Project",
									size = "sm",
									w_full = true,
								},
								TextField { value = sp_task, label = "Task label", placeholder = "Short title shown in Crew tree", size = "sm" },
								TextArea { value = sp_prompt, label = "Prompt", placeholder = "Describe what this worker should build, review, or research…", rows = 3, max_rows = 8, size = "sm" },
								ui.row {
									w_full = true,
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

					-- 4. Needs You escalations for this Captain
					if #pending_ny > 0 then
						local ny_rows: { Node } = {
							Text { zeron.s("deck.attention.title"), style = "label", tone = "accent" },
						}
						for _, item in pending_ny do
							table.insert(ny_rows, Surface {
								kind = "raised",
								w_full = true,
								p = "$space.2",
								ui.column {
									w_full = true,
									gap = "$space.1",
									Text { item.title or "Needs decision", style = "body", weight = "$font.weight.medium" },
									if item.detail and item.detail ~= ""
										then Text { item.detail, style = "caption", tone = "secondary" }
										else ui.div {},
									ui.row {
										gap = "$space.2",
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
								},
							})
						end
						table.insert(sections, ui.column { w_full = true, gap = "$space.2", table.unpack(ny_rows) })
					end

					-- 5. Live Digest preview (when notes drawer is closed)
					if not show_notes:peek() and cap.digest and cap.digest ~= "" then
						table.insert(sections, Surface {
							kind = "sunken",
							w_full = true,
							p = "$space.3",
							ui.column {
								w_full = true,
								gap = "$space.1",
								Text { zeron.s("deck.fleet.digest_label"), style = "label", tone = "tertiary" },
								Text { cap.digest, style = "caption", tone = "secondary" },
							},
						})
					end

					-- 6. Crew List
					table.insert(sections, Text { zeron.s("inspector.crew_heading", { n = #crew }), style = "label", tone = "tertiary" })

					if #crew == 0 then
						table.insert(sections, EmptyState {
							size = "sm",
							icon = "bot",
							title = "No crew yet",
							body = zeron.s("deck.fleet.no_crew"),
							action = {
								label = zeron.s("deck.fleet.spawn_worker"),
								icon = "plus",
								on_click = function()
									show_spawn:set(true)
								end,
							},
						})
					else
						for _, w in crew do
							local is_steering = steer_target:peek() == w.chat_id
							local is_expanded = expanded_reply:peek() == w.chat_id
							local reply = w.last_reply or ""
							local preview = if #reply > 160 and not is_expanded then string.sub(reply, 1, 159) .. "…" else reply

							local card_children: { Node } = {
								ui.row {
									w_full = true,
									gap = "$space.2",
									items = "center",
									Status.StatusIcon { kind = client.status_kind(w.status) :: any, size = 13 },
									Badge.Badge { w.role or "worker", tone = client.status_tone(w.status), size = "sm" },
									if w.harness and w.harness ~= ""
										then Badge.Badge { w.harness, tone = "neutral", size = "sm" }
										else ui.div {},
									ui.div { grow = 1 },
									IconButton {
										icon = "chat-round-line",
										size = "sm",
										tone = "quiet",
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
								Text { w.task or client.session_title(w.chat_id), style = "body", weight = "$font.weight.medium" },
							}

							if w.model and w.model ~= "" then
								table.insert(card_children, Text { `Model: {w.model}`, style = "caption", tone = "tertiary" })
							end

							if w.next_stage then
								table.insert(card_children, Badge.Badge {
									`Then -> {w.next_stage.role or "reviewer"} ({w.next_stage.harness or "auto"})`,
									tone = "info",
									size = "sm",
									icon = "map-arrow-right",
								})
							end

							if w.last_error and w.last_error ~= "" then
								table.insert(card_children, Text { w.last_error, style = "caption", tone = "danger" })
							elseif preview ~= "" then
								table.insert(card_children, ui.column {
									w_full = true,
									gap = "$space.1",
									Text { preview, style = "caption", tone = "secondary" },
									if #reply > 160
										then Button {
											size = "xs",
											tone = "ghost",
											on_click = function()
												expanded_reply:set(if is_expanded then nil else w.chat_id)
											end,
											if is_expanded then "Collapse report" else "Show full report",
										}
										else ui.div {},
								})
							end

							if is_steering then
								table.insert(card_children, ui.column {
									w_full = true,
									gap = "$space.2",
									pt = "$space.1",
									TextField {
										value = steer_text,
										placeholder = zeron.s("inspector.steer_placeholder"),
										size = "sm",
									},
									ui.row {
										gap = "$space.2",
										justify = "end",
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
											"Steer Now",
										},
									},
								})
							end

							table.insert(sections, Surface {
								kind = "raised",
								w_full = true,
								p = "$space.3",
								ui.column { w_full = true, gap = "$space.2", table.unpack(card_children) },
							})
						end
					end

					return ui.column { w_full = true, gap = "$space.3", table.unpack(sections) }
				end),
			},
		}
	end)
end

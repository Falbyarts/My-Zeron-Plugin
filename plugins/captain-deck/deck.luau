--!strict
-- Captain Deck: dedicated sidebar page (`zeron.page`).
--
-- Full harness-agnostic orchestration control center:
-- - Live summary stats + Attention Digest ("Needs You")
-- - Fleet view: Captains & visual Crew Trees with inline steer & inspector
-- - Workflows view: Build -> Cross-Harness Review, Fan-Out Swarm, Compare
-- - Chats view: 1-click Promote to Captain or Attach as Worker
-- - Activity view: live orchestration timeline
-- - Slide-over Sheets for creating Captains and spawning Workers on ANY harness

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local Dialog = require("@ds/dialog")
local EmptyState = require("@ds/empty_state")
local FadeText = require("@ds/fade_text")
local Icon = require("@ds/icon")
local IconButton = require("@ds/icon_button").IconButton
local SearchField = require("@ds/search_field")
local Segmented = require("@ds/segmented")
local Select = require("@ds/select")
local Stat = require("@ds/stat")
local Status = require("@ds/status")
local Surface = require("@ds/surface")
local Switch = require("@ds/switch")
local Tabs = require("@ds/tabs")
local Text = require("@ds/text")
local TextArea = require("@ds/text_area")
local TextField = require("@ds/text_field")
local banner = require("@ds/banner")

local ROLES = {
	{ value = "builder", label = "Builder" },
	{ value = "reviewer", label = "Reviewer" },
	{ value = "researcher", label = "Researcher" },
	{ value = "tester", label = "Tester / QA" },
	{ value = "planner", label = "Planner" },
	{ value = "worker", label = "General Worker" },
}

local WORKFLOW_PRESETS = {
	{ value = "build_review", label = "Build -> Review" },
	{ value = "fanout", label = "Fan-Out Swarm" },
	{ value = "compare", label = "Compare Harnesses" },
}

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

local function trim(s: string?): string
	if type(s) ~= "string" then
		return ""
	end
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

return function(zeron: any, client: any): (props: { page: any, panel: any? }) -> Node
	return ui.component(function(props: { page: any, panel: any? }): Node
		local panel = props.panel

		local active_tab = ui.use_state("fleet")
		local query = ui.use_state("")

		-- Inline steer target in Fleet tab
		local steer_chat = ui.use_state(nil :: string?)
		local steer_text = ui.use_state("")
		local steering = ui.use_state(false)

		-- New Captain Sheet state
		local new_cap_open = ui.use_state(false)
		local nc_name = ui.use_state("")
		local nc_mission = ui.use_state("")
		local nc_rules = ui.use_state("")
		local nc_prompt = ui.use_state("")
		local nc_harness = ui.use_state("")
		local nc_custom_harness = ui.use_state("")
		local nc_model = ui.use_state("")
		local nc_project = ui.use_state("")
		local nc_auto_report = ui.use_state(true)
		local nc_busy = ui.use_state(false)

		-- Spawn Worker Sheet state
		local spawn_open = ui.use_state(false)
		local sw_captain_id = ui.use_state("")
		local sw_captain_name = ui.use_state("Captain")
		local sw_role = ui.use_state("builder")
		local sw_task = ui.use_state("")
		local sw_prompt = ui.use_state("")
		local sw_harness = ui.use_state("")
		local sw_custom_harness = ui.use_state("")
		local sw_model = ui.use_state("")
		local sw_project = ui.use_state("")
		local sw_enable_handoff = ui.use_state(false)
		local sw_handoff_role = ui.use_state("reviewer")
		local sw_handoff_harness = ui.use_state("")
		local sw_handoff_prompt = ui.use_state("Review the previous worker's output read-only. Check actual files and git diff, list Critical vs Minor issues.\n\nPrevious report:\n{{REPORT}}")
		local sw_busy = ui.use_state(false)

		-- Attach existing chat Sheet state
		local attach_open = ui.use_state(false)
		local at_chat_id = ui.use_state("")
		local at_chat_title = ui.use_state("")
		local at_captain_id = ui.use_state("")
		local at_role = ui.use_state("worker")
		local at_task = ui.use_state("")
		local at_busy = ui.use_state(false)

		-- Workflow launcher state
		local wf_preset = ui.use_state("build_review")
		local wf_captain_id = ui.use_state("")
		local wf_project = ui.use_state("")
		local wf_primary_harness = ui.use_state("")
		local wf_primary_custom = ui.use_state("")
		local wf_primary_model = ui.use_state("")
		local wf_secondary_harness = ui.use_state("")
		local wf_secondary_custom = ui.use_state("")
		local wf_secondary_model = ui.use_state("")
		local wf_task = ui.use_state("")
		local wf_subtasks = ui.use_state("")
		local wf_rules = ui.use_state("")
		local wf_busy = ui.use_state(false)

		local function captain_picker_options(include_new: boolean): { any }
			local opts: { any } = {}
			if include_new then
				table.insert(opts, { value = "", label = "Create a new Captain thread" })
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

		local function open_spawn_for(cap: any)
			sw_captain_id:set(cap.chat_id)
			sw_captain_name:set(cap.name or "Captain")
			sw_role:set("builder")
			sw_task:set("")
			sw_prompt:set("")
			sw_enable_handoff:set(false)
			spawn_open:set(true)
		end

		local function open_attach_for(chat_id: string, title: string)
			at_chat_id:set(chat_id)
			at_chat_title:set(title)
			at_task:set(title)
			at_role:set("worker")
			local opts = captain_picker_options(false)
			if #opts > 0 then
				at_captain_id:set(opts[1].value)
			else
				at_captain_id:set("")
			end
			attach_open:set(true)
		end

		local function submit_new_captain()
			local name = trim(nc_name:peek())
			local mission = trim(nc_mission:peek())
			if name == "" and mission == "" then
				zeron.toast("Enter a Captain name or mission")
				return
			end
			nc_busy:set(true)
			local custom = trim(nc_custom_harness:peek())
			local harness = if custom ~= "" then custom else nc_harness:peek()
			client.call("create_captain", {
				name = if name ~= "" then name else string.sub(mission, 1, 36),
				mission = mission,
				rules = nc_rules:peek(),
				prompt = nc_prompt:peek(),
				harness = harness,
				model = nc_model:peek(),
				project = nc_project:peek(),
				auto_report = nc_auto_report:peek(),
			}):after(function(cap: any)
				nc_busy:set(false)
				new_cap_open:set(false)
				nc_name:set("")
				nc_mission:set("")
				nc_rules:set("")
				nc_prompt:set("")
				zeron.toast(zeron.s("toast.captain_created"))
				if cap and cap.chat_id and panel then
					client.open_inspector(panel, cap.chat_id)
				end
			end, function()
				nc_busy:set(false)
			end)
		end

		local function submit_spawn_worker()
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
				model = sw_model:peek(),
				project = sw_project:peek(),
				handoff = handoff,
			}):after(function()
				sw_busy:set(false)
				spawn_open:set(false)
				sw_task:set("")
				sw_prompt:set("")
				zeron.toast(zeron.s("toast.worker_spawned"))
			end, function()
				sw_busy:set(false)
			end)
		end

		local function submit_attach()
			local cid = trim(at_captain_id:peek())
			if cid == "" then
				zeron.toast("Choose a Captain first")
				return
			end
			at_busy:set(true)
			client.call("attach_worker", {
				captain_id = cid,
				worker_chat = at_chat_id:peek(),
				role = at_role:peek(),
				task = at_task:peek(),
			}):after(function()
				at_busy:set(false)
				attach_open:set(false)
				zeron.toast(zeron.s("toast.worker_attached"))
			end, function()
				at_busy:set(false)
			end)
		end

		local function submit_workflow()
			local task = trim(wf_task:peek())
			if task == "" then
				zeron.toast("Enter the task for this workflow")
				return
			end
			wf_busy:set(true)
			local p_custom = trim(wf_primary_custom:peek())
			local s_custom = trim(wf_secondary_custom:peek())
			local primary_h = if p_custom ~= "" then p_custom else wf_primary_harness:peek()
			local secondary_h = if s_custom ~= "" then s_custom else wf_secondary_harness:peek()
			client.call("launch_workflow", {
				preset = wf_preset:peek(),
				captain_id = wf_captain_id:peek(),
				project = wf_project:peek(),
				primary_harness = primary_h,
				primary_model = wf_primary_model:peek(),
				secondary_harness = secondary_h,
				secondary_model = wf_secondary_model:peek(),
				task = task,
				subtasks = wf_subtasks:peek(),
				rules = wf_rules:peek(),
			}):after(function(res: any)
				wf_busy:set(false)
				wf_task:set("")
				wf_subtasks:set("")
				active_tab:set("fleet")
				zeron.toast(zeron.s("toast.workflow_launched"))
				if res and res.captain_id and panel then
					client.open_inspector(panel, res.captain_id)
				end
			end, function()
				wf_busy:set(false)
			end)
		end

		local function send_inline_steer(chat_id: string, mode: string)
			local txt = trim(steer_text:peek())
			if txt == "" then
				return
			end
			steering:set(true)
			client.call("message_chat", {
				chat_id = chat_id,
				text = txt,
				mode = mode,
			}):after(function()
				steering:set(false)
				steer_text:set("")
				steer_chat:set(nil)
				zeron.toast(zeron.s("toast.message_sent"))
			end, function()
				steering:set(false)
			end)
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

		-- ── Fleet Tab ──────────────────────────────────────────────────────
		local function build_fleet(): Node
			return ui.column {
				w_full = true,
				gap = "$space.3",
				SearchField {
					value = query,
					placeholder = zeron.s("deck.search_placeholder"),
					name = "Filter captains and crew",
					size = "sm",
					w_full = true,
				},
				ui.presence(function(): string
					local s = client.state:get()
					return `fleet:{s and s.rev or 0}:{query:get()}:{tostring(steer_chat:get())}`
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

					local cards: { Node } = {}
					for _, cap in caps do
						local crew = client.crew_of(cap.chat_id)
						if not matches_query(cap, crew, q) then
							continue
						end
						local sum = client.crew_summary(cap.chat_id)

						-- Crew Tree rows under this Captain
						local crew_nodes: { Node } = {}
						if #crew == 0 then
							table.insert(crew_nodes, Text { zeron.s("deck.fleet.no_crew"), style = "caption", tone = "tertiary" })
						else
							for _, w in crew do
								local is_steer = steer_chat:peek() == w.chat_id
								local snippet = if w.last_error and w.last_error ~= ""
									then w.last_error
									elseif w.last_reply and w.last_reply ~= ""
									then (string.gsub(string.sub(w.last_reply, 1, 140), "[\r\n]+", " "))
									else ""

								local row_bits: { Node } = {
									ui.row {
										w_full = true,
										gap = "$space.2",
										items = "center",
										Status.StatusIcon { kind = client.status_kind(w.status) :: any, size = 13 },
										Badge.Badge { w.role or "worker", tone = client.status_tone(w.status), size = "sm" },
										if w.harness and w.harness ~= ""
											then Badge.Badge { w.harness, tone = "neutral", size = "sm" }
											else ui.div {},
										FadeText {
											w.task or client.session_title(w.chat_id),
											grow = 1,
											min_w = 0,
											text_size = "$font.size.sm",
											weight = "$font.weight.medium",
											color = "$text.primary",
										},
										Text { format_age(w.updated_at), style = "label", tone = "tertiary" },
										IconButton {
											icon = "chat-round-line",
											size = "sm",
											tone = "quiet",
											label = "Message or steer worker",
											on_click = function()
												if steer_chat:peek() == w.chat_id then
													steer_chat:set(nil)
												else
													steer_chat:set(w.chat_id)
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
								}

								if w.next_stage then
									table.insert(row_bits, ui.row {
										gap = "$space.1",
										items = "center",
										Badge.Badge {
											`Handoff -> {w.next_stage.role or "reviewer"} ({w.next_stage.harness or "auto"})`,
											tone = "info",
											size = "sm",
											icon = "map-arrow-right",
										},
									})
								end

								if snippet ~= "" then
									table.insert(row_bits, Text {
										snippet,
										style = "caption",
										tone = if w.last_error and w.last_error ~= "" then "danger" else "tertiary",
										truncate = true,
									})
								end

								if is_steer then
									table.insert(row_bits, ui.row {
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
											busy = steering,
											on_click = function()
												send_inline_steer(w.chat_id, "queue")
											end,
											"Queue",
										},
										Button {
											size = "xs",
											tone = "accent",
											busy = steering,
											on_click = function()
												send_inline_steer(w.chat_id, "steer")
											end,
											"Steer",
										},
									})
								end

								table.insert(crew_nodes, Surface {
									kind = "sunken",
									w_full = true,
									px = "$space.3",
									py = "$space.2",
									ui.column { w_full = true, gap = "$space.1", table.unpack(row_bits) },
								})
							end
						end

						local card_content: { Node } = {
							-- Captain header row
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								Status.StatusIcon { kind = client.status_kind(cap.status) :: any, size = 15 },
								Icon { name = "star-bold", size = 14, color = "$accent" },
								ui.row {
									grow = 1,
									min_w = 0,
									cursor = "pointer",
									on_click = function()
										zeron.open({ session = cap.chat_id })
									end,
									FadeText {
										cap.name or client.session_title(cap.chat_id),
										grow = 1,
										min_w = 0,
										text_size = "$font.size.lg",
										weight = "$font.weight.semibold",
										color = "$text.primary",
									},
								},
								if cap.harness and cap.harness ~= ""
									then Badge.Badge { cap.harness, tone = "neutral", size = "sm" }
									else ui.div {},
								Badge.Badge {
									if cap.auto_report ~= false then zeron.s("deck.fleet.auto_report_on") else zeron.s("deck.fleet.auto_report_off"),
									tone = if cap.auto_report ~= false then "success" else "neutral",
									size = "sm",
								},
								if cap.schedule_mins and cap.schedule_mins >= 5
									then Badge.Badge { `Every {cap.schedule_mins}m`, tone = "info", size = "sm", icon = "clock-circle" }
									else ui.div {},
								if sum.attention > 0
									then Badge.Badge { `{sum.attention} needs you`, tone = "warning", size = "sm", dot = true, tabular = true }
									else ui.div {},
							},
						}

						if cap.mission and cap.mission ~= "" then
							table.insert(card_content, Text { cap.mission, style = "caption", tone = "secondary" })
						end

						if cap.digest and cap.digest ~= "" then
							table.insert(card_content, ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								Badge.Badge { zeron.s("deck.fleet.digest_label"), tone = "info", size = "sm" },
								Text { cap.digest, style = "caption", tone = "secondary", truncate = true, grow = 1, min_w = 0 },
							})
						end

						-- Action toolbar
						table.insert(card_content, ui.row {
							w_full = true,
							gap = "$space.2",
							items = "center",
							wrap = true,
							Button {
								size = "xs",
								tone = "primary",
								on_click = function()
									open_spawn_for(cap)
								end,
								Icon { name = "plus", size = 12 },
								zeron.s("deck.fleet.spawn_worker"),
							},
							Button {
								size = "xs",
								tone = "secondary",
								on_click = function()
									client.open_inspector(panel, cap.chat_id)
								end,
								Icon { name = "split-columns", size = 12 },
								zeron.s("deck.fleet.inspector"),
							},
							Button {
								size = "xs",
								tone = "ghost",
								on_click = function()
									zeron.open({ session = cap.chat_id })
								end,
								Icon { name = "arrow-up-right", size = 12 },
								zeron.s("deck.fleet.open_chat"),
							},
							ui.div { grow = 1 },
							IconButton {
								icon = "trash-bin-minimalistic",
								size = "sm",
								tone = "danger",
								label = "Demote Captain (keeps underlying chats)",
								on_click = function()
									client.call("remove_captain", { chat_id = cap.chat_id }):after(function()
										zeron.toast(`Demoted {cap.name}`)
									end, function() end)
								end,
							},
						})

						-- Indented visual Crew Tree
						table.insert(card_content, ui.column {
							w_full = true,
							pl = "$space.3",
							ml = "$space.2",
							border_l = 2,
							border_color = "$border.strong",
							gap = "$space.2",
							table.unpack(crew_nodes),
						})

						table.insert(cards, Surface {
							kind = "raised",
							w_full = true,
							p = "$space.4",
							ui.column { w_full = true, gap = "$space.3", table.unpack(card_content) },
						})
					end

					if #cards == 0 then
						return EmptyState {
							icon = "users-group-rounded",
							title = zeron.s("deck.fleet.empty_title"),
							body = zeron.s("deck.fleet.empty_body"),
							action = {
								label = zeron.s("deck.new_captain"),
								icon = "plus",
								on_click = function()
									new_cap_open:set(true)
								end,
							},
							secondary = {
								label = zeron.s("deck.launch_workflow"),
								icon = "action-play",
								on_click = function()
									active_tab:set("workflows")
								end,
							},
						}
					end

					return ui.column { w_full = true, gap = "$space.3", table.unpack(cards) }
				end),
			}
		end

		-- ── Workflows Tab ──────────────────────────────────────────────────
		local function build_workflows(): Node
			return Surface {
				kind = "raised",
				w_full = true,
				p = "$space.4",
				ui.column {
					w_full = true,
					gap = "$space.3",
					Text { zeron.s("deck.workflows.heading"), style = "heading" },
					Text { zeron.s("deck.workflows.intro"), style = "caption", tone = "secondary" },
					Segmented {
						value = wf_preset,
						options = WORKFLOW_PRESETS,
						fill = true,
						label = "Workflow preset",
					},
					ui.presence(function(): string
						return wf_preset:get()
					end, function(preset: string): Node
						local desc = if preset == "build_review"
							then zeron.s("deck.workflows.preset_build_review_desc")
							elseif preset == "fanout"
							then zeron.s("deck.workflows.preset_fanout_desc")
							else zeron.s("deck.workflows.preset_compare_desc")
						return Text { desc, style = "caption", tone = "accent" }
					end),
					ui.row {
						w_full = true,
						gap = "$space.3",
						ui.column {
							grow = 1,
							min_w = 0,
							Select {
								value = wf_captain_id,
								options = function()
									return captain_picker_options(true)
								end,
								label = "Captain",
								size = "sm",
								w_full = true,
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
								label = "Project",
								size = "sm",
								w_full = true,
							},
						},
					},
					ui.row {
						w_full = true,
						gap = "$space.3",
						ui.column {
							grow = 1,
							min_w = 0,
							gap = "$space.2",
							Select {
								value = wf_primary_harness,
								options = function()
									return client.harness_options(true)
								end,
								label = "Primary / Builder Harness",
								size = "sm",
								w_full = true,
								on_change = function()
									wf_primary_model:set("")
								end,
							},
							TextField {
								value = wf_primary_custom,
								placeholder = "Or custom harness id (e.g. acp.gemini)",
								size = "sm",
							},
							Select {
								value = wf_primary_model,
								options = function()
									local c = trim(wf_primary_custom:get())
									return client.models_for(if c ~= "" then c else wf_primary_harness:get())
								end,
								label = "Primary Model",
								size = "sm",
								w_full = true,
							},
						},
						ui.show(function(): boolean
							return wf_preset:get() ~= "fanout"
						end, ui.column {
							grow = 1,
							min_w = 0,
							gap = "$space.2",
							Select {
								value = wf_secondary_harness,
								options = function()
									return client.harness_options(true)
								end,
								label = "Secondary / Reviewer Harness",
								size = "sm",
								w_full = true,
								on_change = function()
									wf_secondary_model:set("")
								end,
							},
							TextField {
								value = wf_secondary_custom,
								placeholder = "Or custom harness id (e.g. hermes, pi)",
								size = "sm",
							},
							Select {
								value = wf_secondary_model,
								options = function()
									local c = trim(wf_secondary_custom:get())
									return client.models_for(if c ~= "" then c else wf_secondary_harness:get())
								end,
								label = "Secondary Model",
								size = "sm",
								w_full = true,
							},
						}),
					},
					TextArea {
						value = wf_task,
						label = "Task / Goal",
						placeholder = "Describe what the workflow should accomplish…",
						rows = 3,
						max_rows = 8,
						size = "sm",
					},
					ui.show(function(): boolean
						return wf_preset:get() == "fanout"
					end, TextArea {
						value = wf_subtasks,
						label = "Parallel Subtasks (one per line, up to 8 workers)",
						placeholder = "1. Migrate auth module\n2. Update API handlers\n3. Add regression tests",
						rows = 4,
						max_rows = 10,
						size = "sm",
					}),
					TextField {
						value = wf_rules,
						label = "Shared Crew Rules (optional)",
						placeholder = "e.g. Never push without asking. Include exact file paths in reports.",
						size = "sm",
					},
					ui.row {
						w_full = true,
						justify = "end",
						Button {
							tone = "primary",
							busy = wf_busy,
							on_click = submit_workflow,
							Icon { name = "action-play", size = 14 },
							zeron.s("deck.workflows.launch"),
						},
					},
				},
			}
		end

		-- ── Existing Chats Tab (1-click Promote or Attach) ─────────────────
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
					return EmptyState {
						icon = "chat-round-line",
						title = zeron.s("deck.chats.empty_title"),
						body = zeron.s("deck.chats.empty_body"),
					}
				end

				local rows: { Node } = {}
				for i, entry in list do
					if i > 40 then
						break
					end
					local sid = entry.id
					local sess = entry.sess
					local title = if type(sess.title) == "string" and sess.title ~= "" then sess.title else string.sub(sid, 1, 8)
					table.insert(rows, Surface {
						kind = "raised",
						w_full = true,
						px = "$space.3",
						py = "$space.2",
						ui.row {
							w_full = true,
							gap = "$space.2",
							items = "center",
							ui.column {
								grow = 1,
								min_w = 0,
								gap = "$space.1",
								FadeText { title, text_size = "$font.size.md", weight = "$font.weight.medium", color = "$text.primary" },
								Text {
									if sess.branch and sess.branch ~= "" then `{sess.branch} · {format_age(sess.updated)}` else format_age(sess.updated),
									style = "caption",
									tone = "tertiary",
								},
							},
							Button {
								size = "xs",
								tone = "primary",
								on_click = function()
									client.call("promote_captain", { chat_id = sid, name = title }):after(function()
										zeron.toast(zeron.s("toast.promoted"))
										active_tab:set("fleet")
									end, function() end)
								end,
								Icon { name = "star", size = 12 },
								zeron.s("deck.chats.promote"),
							},
							if has_captains
								then Button {
									size = "xs",
									tone = "secondary",
									on_click = function()
										open_attach_for(sid, title)
									end,
									Icon { name = "git-branch", size = 12 },
									zeron.s("deck.chats.attach"),
								}
								else ui.div {},
							IconButton {
								icon = "arrow-up-right",
								size = "sm",
								tone = "quiet",
								label = "Open chat",
								on_click = function()
									zeron.open({ session = sid })
								end,
							},
						},
					})
				end

				return ui.column { w_full = true, gap = "$space.2", table.unpack(rows) }
			end)
		end

		-- ── Activity Timeline Tab ──────────────────────────────────────────
		local function build_activity(): Node
			return ui.presence(function(): string
				local s = client.state:get()
				return `act:{s and s.rev or 0}`
			end, function(): Node
				local s = client.state:peek() or {}
				local events = s.events or {}
				if #events == 0 then
					return EmptyState {
						icon = "clock-circle",
						title = zeron.s("deck.activity.empty_title"),
						body = zeron.s("deck.activity.empty_body"),
					}
				end
				local rows: { Node } = {
					ui.row {
						w_full = true,
						items = "center",
						justify = "between",
						Text { zeron.s("deck.activity.heading"), style = "label", tone = "tertiary" },
						Button {
							size = "xs",
							tone = "ghost",
							on_click = function()
								client.call("clear_events")
							end,
							zeron.s("deck.activity.clear"),
						},
					},
				}
				for _, ev in events do
					local tone: any = if ev.kind == "needs_you" or ev.kind == "awaiting_input"
						then "warning"
						elseif string.find(ev.kind or "", "fail") or string.find(ev.kind or "", "error")
						then "danger"
						elseif ev.kind == "handoff" or ev.kind == "workflow_launched"
						then "info"
						elseif ev.kind == "worker_finished" or ev.kind == "reported"
						then "success"
						else "neutral"
					table.insert(rows, Surface {
						kind = "raised",
						w_full = true,
						px = "$space.3",
						py = "$space.2",
						ui.row {
							w_full = true,
							gap = "$space.2",
							items = "center",
							Badge.Badge { ev.kind or "event", tone = tone, size = "sm" },
							Text { ev.summary or "", style = "caption", tone = "primary", grow = 1, min_w = 0 },
							Text { format_age(ev.at), style = "label", tone = "tertiary" },
							if ev.chat_id
								then IconButton {
									icon = "arrow-up-right",
									size = "sm",
									tone = "quiet",
									label = "Open chat",
									on_click = function()
										zeron.open({ session = ev.chat_id })
									end,
								}
								else ui.div {},
						},
					})
				end
				return ui.column { w_full = true, gap = "$space.2", table.unpack(rows) }
			end)
		end

		-- ── Main Page Layout ───────────────────────────────────────────────
		return ui.div {
			w_full = true,
			h_full = true,
			ui.scroll {
				w_full = true,
				h_full = true,
				ui.column {
					w_full = true,
					max_w = 960,
					mx = "auto",
					px = "$space.6",
					py = "$space.6",
					gap = "$space.5",

					-- Header
					ui.row {
						w_full = true,
						gap = "$space.3",
						items = "center",
						wrap = true,
						ui.column {
							grow = 1,
							min_w = 240,
							gap = "$space.1",
							Text { zeron.t("deck.title"), style = "title", heading = 1 },
							Text { zeron.t("deck.subtitle"), style = "caption", tone = "secondary" },
						},
						ui.row {
							gap = "$space.2",
							items = "center",
							IconButton {
								icon = "refresh",
								label = zeron.s("deck.refresh"),
								tone = "quiet",
								on_click = function()
									client.refresh()
									client.probe_harnesses(nil)
								end,
							},
							Button {
								size = "sm",
								tone = "secondary",
								on_click = function()
									active_tab:set("workflows")
								end,
								Icon { name = "action-play", size = 13 },
								zeron.t("deck.launch_workflow"),
							},
							Button {
								size = "sm",
								tone = "primary",
								on_click = function()
									new_cap_open:set(true)
								end,
								Icon { name = "plus", size = 13 },
								zeron.t("deck.new_captain"),
							},
						},
					},

					-- Service warning banner if service isn't approved or failed
					ui.presence(function(): string
						return client.service_err:get() or ""
					end, function(err: string): Node
						if err == "" then
							return ui.div {}
						end
						return banner.Callout {
							tone = "warning",
							title = "Orchestration service needs attention",
							body = err,
							action = {
								label = "Retry",
								on_click = function()
									client.refresh()
								end,
							},
						}
					end),

					-- Headline stats strip
					Surface {
						kind = "raised",
						w_full = true,
						px = "$space.5",
						py = "$space.3",
						ui.row {
							w_full = true,
							gap = "$space.6",
							wrap = true,
							Stat {
								value = function(): string
									local s = client.state:get()
									local n = 0
									for _ in (s and s.captains or {}) do
										n += 1
									end
									return tostring(n)
								end,
								label = zeron.s("deck.stats.captains"),
							},
							Stat {
								value = function(): string
									local s = client.state:get()
									local n = 0
									for _ in (s and s.workers or {}) do
										n += 1
									end
									return tostring(n)
								end,
								label = zeron.s("deck.stats.workers"),
							},
							Stat {
								value = function(): string
									local s = client.state:get()
									local n = 0
									for _, w in (s and s.workers or {}) do
										if w.status == "running" then
											n += 1
										end
									end
									return tostring(n)
								end,
								label = zeron.s("deck.stats.running"),
								tone = "$accent",
							},
							Stat {
								value = function(): string
									return tostring(#client.attention_items())
								end,
								label = zeron.s("deck.stats.attention"),
								tone = function(): any
									return if #client.attention_items() > 0 then "$warning" else "$text.secondary"
								end,
							},
						},
					},

					-- Attention Digest ("Needs You")
					ui.presence(function(): string
						local items = client.attention_items()
						local s = client.state:get()
						return if #items == 0 then "" else `att:{#items}:{s and s.rev or 0}`
					end, function(key: string): Node
						if key == "" then
							return ui.div {}
						end
						local items = client.attention_items()
						local rows: { Node } = {
							ui.row {
								w_full = true,
								gap = "$space.2",
								items = "center",
								Icon { name = "bell", size = 14, color = "$warning" },
								Text { `{zeron.s("deck.attention.title")} ({#items})`, style = "heading" },
							},
						}
						for _, item in items do
							local reason_label = if item.status == "awaiting_input"
								then zeron.s("deck.attention.awaiting_input")
								elseif item.status == "limited"
								then zeron.s("deck.attention.limited")
								else zeron.s("deck.attention.errored")
							table.insert(rows, Surface {
								kind = "sunken",
								w_full = true,
								px = "$space.3",
								py = "$space.2",
								ui.row {
									w_full = true,
									gap = "$space.2",
									items = "center",
									Status.StatusIcon { kind = client.status_kind(item.status) :: any, size = 14 },
									ui.column {
										grow = 1,
										min_w = 0,
										gap = "$space.1",
										ui.row {
											gap = "$space.2",
											items = "center",
											Badge.Badge { item.captain_name or "Captain", tone = "warning", size = "sm" },
											Badge.Badge { item.role or "worker", tone = "neutral", size = "sm" },
											if item.harness and item.harness ~= ""
												then Badge.Badge { item.harness, tone = "neutral", size = "sm" }
												else ui.div {},
											FadeText { item.title or reason_label, grow = 1, min_w = 0, text_size = "$font.size.sm", weight = "$font.weight.medium", color = "$text.primary" },
										},
										Text {
											if item.detail and item.detail ~= "" then item.detail else reason_label,
											style = "caption",
											tone = "secondary",
											truncate = true,
										},
									},
									Button {
										size = "xs",
										tone = "primary",
										on_click = function()
											zeron.open({ session = item.chat_id })
										end,
										zeron.s("deck.attention.open_chat"),
									},
									if item.kind == "escalation" and item.item_id
										then Button {
											size = "xs",
											tone = "ghost",
											on_click = function()
												client.call("resolve_attention", { captain_id = item.captain_id, item_id = item.item_id })
											end,
											zeron.s("deck.attention.resolve"),
										}
										else ui.div {},
								},
							})
						end
						return Surface {
							kind = "raised",
							w_full = true,
							p = "$space.4",
							border_color = "$warning",
							ui.column { w_full = true, gap = "$space.2", table.unpack(rows) },
						}
					end),

					-- Navigation Tabs
					Tabs {
						value = active_tab,
						rule = true,
						label = "Captain Deck sections",
						options = {
							{ value = "fleet", label = zeron.s("deck.tabs.fleet") },
							{ value = "workflows", label = zeron.s("deck.tabs.workflows") },
							{ value = "chats", label = zeron.s("deck.tabs.chats") },
							{ value = "activity", label = zeron.s("deck.tabs.activity") },
						},
					},

					-- Tab Body
					ui.presence(function(): string
						return active_tab:get()
					end, function(tab: string): Node
						if tab == "workflows" then
							return build_workflows()
						elseif tab == "chats" then
							return build_chats()
						elseif tab == "activity" then
							return build_activity()
						end
						return build_fleet()
					end),
				},
			},

			-- Slide-over Sheet: New Captain
			Dialog.Sheet {
				open = new_cap_open,
				title = zeron.s("deck.new_captain"),
				description = "Launch a long-lived Captain thread on any Zeron harness and model.",
				foot = ui.row {
					w_full = true,
					gap = "$space.2",
					justify = "end",
					Button {
						tone = "ghost",
						size = "sm",
						on_click = function()
							new_cap_open:set(false)
						end,
						zeron.s("dialogs.cancel"),
					},
					Button {
						tone = "primary",
						size = "sm",
						busy = nc_busy,
						on_click = submit_new_captain,
						Icon { name = "star-bold", size = 13 },
						zeron.s("dialogs.create"),
					},
				},
				ui.column {
					w_full = true,
					gap = "$space.3",
					TextField { value = nc_name, label = "Captain Name", placeholder = "e.g. Release Captain, Auth Migration, Bug Triage", size = "sm" },
					TextField { value = nc_mission, label = "Mission", placeholder = "What goal does this Captain own?", size = "sm" },
					Select {
						value = nc_harness,
						options = function()
							return client.harness_options(true)
						end,
						label = "Harness",
						size = "sm",
						w_full = true,
						on_change = function()
							nc_model:set("")
						end,
					},
					TextField { value = nc_custom_harness, label = "Custom harness id (optional)", placeholder = "e.g. acp.gemini, hermes, opencode, pi", size = "sm" },
					Select {
						value = nc_model,
						options = function()
							local c = trim(nc_custom_harness:get())
							return client.models_for(if c ~= "" then c else nc_harness:get())
						end,
						label = "Model",
						size = "sm",
						w_full = true,
					},
					Select {
						value = nc_project,
						options = function()
							return client.project_options()
						end,
						label = "Project",
						size = "sm",
						w_full = true,
					},
					TextArea { value = nc_rules, label = "Shared Crew Rules (prepended to every worker)", placeholder = "e.g. Always run tests. Never push or merge without human sign-off.", rows = 3, max_rows = 6, size = "sm" },
					TextArea { value = nc_prompt, label = "Opening Prompt (optional)", placeholder = "Leave blank to initialize with the Captain mission.", rows = 3, max_rows = 6, size = "sm" },
					ui.row {
						w_full = true,
						items = "center",
						justify = "between",
						Text { "Auto-report worker completions back to this Captain", style = "caption", tone = "secondary" },
						Switch { value = nc_auto_report, label = "Auto-report" },
					},
				},
			},

			-- Slide-over Sheet: Spawn Worker
			Dialog.Sheet {
				open = spawn_open,
				title = function(): string
					return `Spawn Worker · {sw_captain_name:get()}`
				end,
				description = "Start a worker chat on ANY harness/model and attach it to this Captain's Crew tree.",
				foot = ui.row {
					w_full = true,
					gap = "$space.2",
					justify = "end",
					Button {
						tone = "ghost",
						size = "sm",
						on_click = function()
							spawn_open:set(false)
						end,
						zeron.s("dialogs.cancel"),
					},
					Button {
						tone = "primary",
						size = "sm",
						busy = sw_busy,
						on_click = submit_spawn_worker,
						Icon { name = "action-play", size = 13 },
						zeron.s("dialogs.spawn"),
					},
				},
				ui.column {
					w_full = true,
					gap = "$space.3",
					Select { value = sw_role, options = ROLES, label = "Role", size = "sm", w_full = true },
					Select {
						value = sw_harness,
						options = function()
							return client.harness_options(true)
						end,
						label = "Harness",
						size = "sm",
						w_full = true,
						on_change = function()
							sw_model:set("")
						end,
					},
					TextField { value = sw_custom_harness, label = "Custom harness id (optional)", placeholder = "e.g. acp.gemini, hermes, opencode, pi", size = "sm" },
					Select {
						value = sw_model,
						options = function()
							local c = trim(sw_custom_harness:get())
							return client.models_for(if c ~= "" then c else sw_harness:get())
						end,
						label = "Model",
						size = "sm",
						w_full = true,
					},
					Select {
						value = sw_project,
						options = function()
							return client.project_options()
						end,
						label = "Project",
						size = "sm",
						w_full = true,
					},
					TextField { value = sw_task, label = "Task summary", placeholder = "Short title shown in Crew tree", size = "sm" },
					TextArea { value = sw_prompt, label = "Worker Prompt", placeholder = "Clear instructions for this worker…", rows = 4, max_rows = 8, size = "sm" },
					ui.row {
						w_full = true,
						items = "center",
						justify = "between",
						Text { "Auto-handoff to another harness when complete", style = "caption", tone = "secondary" },
						Switch { value = sw_enable_handoff, label = "Enable handoff" },
					},
					ui.show(function(): boolean
						return sw_enable_handoff:get()
					end, Surface {
						kind = "sunken",
						w_full = true,
						p = "$space.3",
						ui.column {
							w_full = true,
							gap = "$space.2",
							Select { value = sw_handoff_role, options = ROLES, label = "Next-stage role", size = "sm", w_full = true },
							Select {
								value = sw_handoff_harness,
								options = function()
									return client.harness_options(true)
								end,
								label = "Next-stage harness",
								size = "sm",
								w_full = true,
							},
							TextArea {
								value = sw_handoff_prompt,
								label = "Next-stage prompt (use {{REPORT}} for previous reply)",
								rows = 3,
								max_rows = 6,
								size = "sm",
							},
						},
					}),
				},
			},

			-- Slide-over Sheet: Attach Existing Chat
			Dialog.Sheet {
				open = attach_open,
				title = "Attach Chat as Worker",
				description = function(): string
					return `Link "{at_chat_title:get()}" under a Captain to track its turns and reports.`
				end,
				foot = ui.row {
					w_full = true,
					gap = "$space.2",
					justify = "end",
					Button {
						tone = "ghost",
						size = "sm",
						on_click = function()
							attach_open:set(false)
						end,
						zeron.s("dialogs.cancel"),
					},
					Button {
						tone = "primary",
						size = "sm",
						busy = at_busy,
						on_click = submit_attach,
						zeron.s("dialogs.attach"),
					},
				},
				ui.column {
					w_full = true,
					gap = "$space.3",
					Select {
						value = at_captain_id,
						options = function()
							return captain_picker_options(false)
						end,
						label = "Parent Captain",
						size = "sm",
						w_full = true,
					},
					Select { value = at_role, options = ROLES, label = "Worker Role", size = "sm", w_full = true },
					TextField { value = at_task, label = "Task label", size = "sm" },
				},
			},
		}
	end)
end

--!strict
-- Captain Deck: dedicated sidebar page (`zeron.page`).
--
-- Designed directly around Zeron's native `Settings` design system
-- (`Settings.Page`, `Settings.Section`, `Settings.Group`, `Settings.Row`,
-- `Settings.Rule`, `Settings.inset`) so its typography, card borders,
-- hairlines, and controls look identical to Zeron's built-in Settings pages.

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
local Settings = require("@ds/settings")
local Status = require("@ds/status")
local Switch = require("@ds/switch")
local Tabs = require("@ds/tabs")
local Text = require("@ds/text")
local TextArea = require("@ds/text_area")
local TextField = require("@ds/text_field")
local banner = require("@ds/banner")
local control = require("@ds/control")

local NARROW = 640

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

		local width = ui.use_state(0)
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

		-- Quiet search bar that sits at the top of a Settings.Group card,
		-- matching `Settings.Catalog` and `github/board.luau`.
		local function card_search_bar(placeholder: string): Node
			return ui.div {
				w_full = true,
				shrink = 0,
				p = "$space.1",
				theme = { radius = { md = control.nest("$radius.xl", 1, "$space.1") } },
				SearchField {
					value = query,
					placeholder = placeholder,
					name = placeholder,
					size = "sm",
					quiet = true,
					w_full = true,
				},
			}
		end

		-- ── Fleet Tab (Settings.Section + Settings.Group per Captain) ──────
		local function build_fleet(): Node
			return ui.column {
				w_full = true,
				gap = "$space.5",
				Settings.Group {
					card_search_bar(zeron.s("deck.search_placeholder")),
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

					local sections: { Node } = {}
					for _, cap in caps do
						local crew = client.crew_of(cap.chat_id)
						if not matches_query(cap, crew, q) then
							continue
						end
						local sum = client.crew_summary(cap.chat_id)

						local group_rows: { Node } = {}

						-- Top row of the Captain's Settings.Group card: Captain overview & controls
						local cap_badges: { Node } = {
							Badge.Badge { "Captain", tone = "accent", size = "sm" },
						}
						if cap.harness and cap.harness ~= "" then
							table.insert(cap_badges, Badge.Badge { cap.harness, tone = "neutral", size = "sm" })
						end
						if sum.running > 0 then
							table.insert(cap_badges, Badge.Badge { `{sum.running} running`, tone = "accent", size = "sm", dot = true, tabular = true })
						end
						if sum.attention > 0 then
							table.insert(cap_badges, Badge.Badge { `{sum.attention} needs you`, tone = "warning", size = "sm", dot = true, tabular = true })
						end
						if cap.schedule_mins and cap.schedule_mins >= 5 then
							table.insert(cap_badges, Badge.Badge { `Every {cap.schedule_mins}m`, tone = "info", size = "sm", icon = "clock-circle" })
						end

						local desc_parts: { string } = {}
						if cap.mission and cap.mission ~= "" then
							table.insert(desc_parts, cap.mission)
						end
						if cap.digest and cap.digest ~= "" then
							table.insert(desc_parts, `Digest: {cap.digest}`)
						end
						local cap_desc = if #desc_parts > 0
							then table.concat(desc_parts, " · ")
							else `{sum.total} crew assigned · {if cap.auto_report ~= false then "Auto-report on" else "Manual report"}`

						table.insert(group_rows, Settings.Row {
							lead = Status.StatusIcon { kind = client.status_kind(cap.status) :: any, size = 16 },
							label = cap.name or client.session_title(cap.chat_id),
							badge = ui.row { gap = "$space.1", items = "center", flex_wrap = true, table.unpack(cap_badges) },
							description = cap_desc,
							control = ui.row {
								gap = "$space.2",
								items = "center",
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
								IconButton {
									icon = "arrow-up-right",
									size = "sm",
									tone = "quiet",
									label = "Open Captain chat",
									on_click = function()
										zeron.open({ session = cap.chat_id })
									end,
								},
								IconButton {
									icon = "trash-bin-minimalistic",
									size = "sm",
									tone = "danger",
									label = "Demote Captain (keeps chats)",
									on_click = function()
										client.call("remove_captain", { chat_id = cap.chat_id }):after(function()
											zeron.toast(`Demoted {cap.name}`)
										end, function() end)
									end,
								},
							},
						})

						-- Crew member rows inside the same Settings.Group card, divided by hairlines
						if #crew == 0 then
							table.insert(group_rows, Settings.Row {
								icon = "bot",
								label = "No crew workers yet",
								description = zeron.s("deck.fleet.no_crew"),
								control = Button {
									size = "xs",
									tone = "secondary",
									on_click = function()
										open_spawn_for(cap)
									end,
									Icon { name = "plus", size = 12 },
									"Add Worker",
								},
							})
						else
							for _, w in crew do
								local is_steer = steer_chat:peek() == w.chat_id
								local snippet = if w.last_error and w.last_error ~= ""
									then w.last_error
									elseif w.last_reply and w.last_reply ~= ""
									then (string.gsub(string.sub(w.last_reply, 1, 180), "[\r\n]+", " "))
									else ""

								local w_badges: { Node } = {
									Badge.Badge { w.role or "worker", tone = client.status_tone(w.status), size = "sm" },
								}
								if w.harness and w.harness ~= "" then
									table.insert(w_badges, Badge.Badge { w.harness, tone = "neutral", size = "sm" })
								end
								if w.model and w.model ~= "" then
									table.insert(w_badges, Badge.Badge { w.model, tone = "neutral", size = "sm", look = "outline" })
								end
								if w.next_stage then
									table.insert(w_badges, Badge.Badge {
										`Then -> {w.next_stage.role or "reviewer"} ({w.next_stage.harness or "auto"})`,
										tone = "info",
										size = "sm",
										icon = "map-arrow-right",
									})
								end

								table.insert(group_rows, ui.column {
									w_full = true,
									Settings.Row {
										lead = ui.row {
											w = 28,
											h = 28,
											shrink = 0,
											items = "center",
											justify = "center",
											Status.StatusIcon { kind = client.status_kind(w.status) :: any, size = 14 },
										},
										label = w.task or client.session_title(w.chat_id),
										badge = ui.row { gap = "$space.1", items = "center", flex_wrap = true, table.unpack(w_badges) },
										description = if snippet ~= "" then snippet else `Updated {format_age(w.updated_at)}`,
										control = ui.row {
											gap = "$space.1",
											items = "center",
											Button {
												size = "xs",
												tone = if is_steer then "accent" else "ghost",
												on_click = function()
													if steer_chat:peek() == w.chat_id then
														steer_chat:set(nil)
													else
														steer_chat:set(w.chat_id)
														steer_text:set("")
													end
												end,
												Icon { name = "chat-round-line", size = 12 },
												zeron.s("deck.fleet.steer"),
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
									},
									if is_steer
										then ui.row {
											w_full = true,
											px = "$space.4",
											pb = "$space.3",
											gap = "$space.2",
											items = "center",
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
												"Steer Now",
											},
										}
										else nil,
								})
							end
						end

						table.insert(sections, Settings.Group(group_rows))
					end

					if #sections == 0 then
						return Settings.Group {
							ui.column {
								w_full = true,
								py = "$space.6",
								px = "$space.4",
								EmptyState {
									icon = "users-group-rounded",
									title = if q ~= "" then `No match for "{q}"` else zeron.s("deck.fleet.empty_title"),
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
								},
							},
						}
					end

					return ui.column { w_full = true, gap = "$space.5", table.unpack(sections) }
				end, { w_full = true }),
			}
		end

		-- ── Workflows Tab (Settings.Section + Settings.Group rows) ─────────
		local function build_workflows(): Node
			return Settings.Section {
				title = zeron.s("deck.workflows.heading"),
				description = zeron.s("deck.workflows.intro"),
				Settings.Group {
					Settings.Row {
						icon = "magic-stick",
						label = "Workflow Preset",
						description = function(): string
							local p = wf_preset:get()
							return if p == "build_review"
								then zeron.s("deck.workflows.preset_build_review_desc")
								elseif p == "fanout"
								then zeron.s("deck.workflows.preset_fanout_desc")
								else zeron.s("deck.workflows.preset_compare_desc")
						end,
						stacked = true,
						control = Segmented {
							value = wf_preset,
							options = WORKFLOW_PRESETS,
							fill = true,
							label = "Workflow preset",
						},
					},
					Settings.Row {
						icon = "star",
						label = "Coordinator Captain",
						description = "Pick an existing Captain or automatically start a new Captain thread.",
						control = Select {
							value = wf_captain_id,
							options = function()
								return captain_picker_options(true)
							end,
							size = "sm",
						},
					},
					Settings.Row {
						icon = "folder",
						label = "Target Project",
						description = "Workspace folder where spawned workers run.",
						control = Select {
							value = wf_project,
							options = function()
								return client.project_options()
							end,
							size = "sm",
						},
					},
					Settings.Row {
						icon = "bot",
						label = "Primary / Builder Harness & Model",
						description = "The agent harness that executes the primary build or fan-out tasks.",
						stacked = true,
						control = ui.column {
							w_full = true,
							gap = "$space.2",
							ui.row {
								w_full = true,
								gap = "$space.2",
								flex_wrap = true,
								ui.column {
									grow = 1,
									min_w = 180,
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
									min_w = 180,
									Select {
										value = wf_primary_model,
										options = function()
											local c = trim(wf_primary_custom:get())
											return client.models_for(if c ~= "" then c else wf_primary_harness:get())
										end,
										size = "sm",
										w_full = true,
									},
								},
							},
							TextField {
								value = wf_primary_custom,
								placeholder = "Optional custom harness id override (e.g. acp.gemini, hermes, pi)",
								size = "sm",
							},
						},
					},
					ui.show(function(): boolean
						return wf_preset:get() ~= "fanout"
					end, ui.column {
						w_full = true,
						Settings.Rule(),
						Settings.Row {
							icon = "shield-check",
							label = "Secondary / Reviewer Harness & Model",
							description = "A different harness for fresh-context code review or side-by-side comparison.",
							stacked = true,
							control = ui.column {
								w_full = true,
								gap = "$space.2",
								ui.row {
									w_full = true,
									gap = "$space.2",
									flex_wrap = true,
									ui.column {
										grow = 1,
										min_w = 180,
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
										min_w = 180,
										Select {
											value = wf_secondary_model,
											options = function()
												local c = trim(wf_secondary_custom:get())
												return client.models_for(if c ~= "" then c else wf_secondary_harness:get())
											end,
											size = "sm",
											w_full = true,
										},
									},
								},
								TextField {
									value = wf_secondary_custom,
									placeholder = "Optional custom secondary harness id (e.g. claude-code, opencode, antigravity)",
									size = "sm",
								},
							},
						},
					}),
					Settings.Row {
						icon = "document",
						label = "Task / Goal",
						description = "Detailed objective handed to the workflow workers.",
						stacked = true,
						control = TextArea {
							value = wf_task,
							placeholder = "Describe what to build, refactor, audit, or compare…",
							rows = 3,
							max_rows = 8,
							size = "sm",
						},
					},
					ui.show(function(): boolean
						return wf_preset:get() == "fanout"
					end, ui.column {
						w_full = true,
						Settings.Rule(),
						Settings.Row {
							icon = "checklist",
							label = "Parallel Subtasks (one per line, up to 8 workers)",
							description = "Captain Deck spawns one dedicated worker thread per line.",
							stacked = true,
							control = TextArea {
								value = wf_subtasks,
								placeholder = "1. Migrate auth module\n2. Update API handlers\n3. Add regression tests",
								rows = 4,
								max_rows = 10,
								size = "sm",
							},
						},
					}),
					Settings.Row {
						icon = "lock-keyhole-unlocked",
						label = "Shared Crew Rules (optional)",
						description = "Rules prepended to every worker in this workflow.",
						stacked = true,
						control = TextField {
							value = wf_rules,
							placeholder = "e.g. Never push without asking. Cite exact file paths and line numbers.",
							size = "sm",
						},
					},
					ui.row {
						w_full = true,
						px = "$space.4",
						py = "$space.3",
						justify = "end",
						Button {
							tone = "primary",
							size = "sm",
							busy = wf_busy,
							on_click = submit_workflow,
							Icon { name = "action-play", size = 13 },
							zeron.s("deck.workflows.launch"),
						},
					},
				},
			}
		end

		-- ── Existing Chats Tab (Settings.Group list) ───────────────────────
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
					return Settings.Group {
						ui.column {
							w_full = true,
							py = "$space.6",
							px = "$space.4",
							EmptyState {
								icon = "chat-round-line",
								title = zeron.s("deck.chats.empty_title"),
								body = zeron.s("deck.chats.empty_body"),
							},
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
					local title = if type(sess.title) == "string" and sess.title ~= "" then sess.title else string.sub(sid, 1, 8)
					local sub = if sess.branch and sess.branch ~= ""
						then `{sess.branch} · Updated {format_age(sess.updated)}`
						else `Updated {format_age(sess.updated)}`

					table.insert(rows, Settings.Row {
						icon = "chat-round-line",
						label = title,
						description = sub,
						truncate = true,
						control = ui.row {
							gap = "$space.2",
							items = "center",
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
								else nil,
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

				return Settings.Section {
					title = zeron.s("deck.chats.heading"),
					description = "Turn any active Zeron session into a Captain or attach it as a worker under an existing Captain.",
					Settings.Group(rows),
				}
			end, { w_full = true })
		end

		-- ── Activity Timeline Tab (Settings.Group list) ────────────────────
		local function build_activity(): Node
			return ui.presence(function(): string
				local s = client.state:get()
				return `act:{s and s.rev or 0}`
			end, function(): Node
				local s = client.state:peek() or {}
				local events = s.events or {}
				if #events == 0 then
					return Settings.Group {
						ui.column {
							w_full = true,
							py = "$space.6",
							px = "$space.4",
							EmptyState {
								icon = "clock-circle",
								title = zeron.s("deck.activity.empty_title"),
								body = zeron.s("deck.activity.empty_body"),
							},
						},
					}
				end

				local rows: { Node } = {}
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
					table.insert(rows, Settings.Row {
						label = ev.summary or "",
						badge = Badge.Badge { ev.kind or "event", tone = tone, size = "sm" },
						description = format_age(ev.at),
						control = if ev.chat_id
							then IconButton {
								icon = "arrow-up-right",
								size = "sm",
								tone = "quiet",
								label = "Open chat",
								on_click = function()
									zeron.open({ session = ev.chat_id })
								end,
							}
							else nil,
					})
				end

				return Settings.Section {
					title = zeron.s("deck.activity.heading"),
					trail = Button {
						size = "xs",
						tone = "ghost",
						on_click = function()
							client.call("clear_events")
						end,
						zeron.s("deck.activity.clear"),
					},
					Settings.Group(rows),
				}
			end, { w_full = true })
		end

		local function gutter(): string
			local w = width:get()
			return if w > 0 and w < NARROW then "$space.4" else "$space.6"
		end

		-- ── Main Page Layout (`Settings.Page` inside centered scroll) ──────
		return ui.column {
			class = "captain-deck-page",
			w_full = true,
			h_full = true,
			selectable = true,
			on_resize = function(size)
				local w = math.floor(size.w)
				if w > 0 and w ~= width:peek() then
					width:set(w)
				end
			end,
			ui.scroll {
				w_full = true,
				h_full = true,
				fade = { 16, 16 },
				fade_overflow = true,
				ui.column {
					w_full = true,
					min_h = "100%",
					items = "center",
					px = gutter,
					pt = gutter,
					pb = "$space.8",
					Settings.Page {
						title = zeron.t("deck.title"),
						description = zeron.t("deck.subtitle"),
						trail_top = true,
						trail = ui.row {
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

						-- 1. Service warning callout (only if service failed)
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

						-- 2. Needs Your Attention Section (auto-appears when any item needs human action)
						ui.presence(function(): string
							local items = client.attention_items()
							local s = client.state:get()
							return if #items == 0 then "" else `att:{#items}:{s and s.rev or 0}`
						end, function(key: string): Node
							if key == "" then
								return ui.div {}
							end
							local items = client.attention_items()
							local att_rows: { Node } = {}
							for _, item in items do
								local reason_label = if item.status == "awaiting_input"
									then zeron.s("deck.attention.awaiting_input")
									elseif item.status == "limited"
									then zeron.s("deck.attention.limited")
									else zeron.s("deck.attention.errored")
								table.insert(att_rows, Settings.Row {
									lead = Status.StatusIcon { kind = client.status_kind(item.status) :: any, size = 15 },
									label = item.title or reason_label,
									badge = ui.row {
										gap = "$space.1",
										items = "center",
										Badge.Badge { item.captain_name or "Captain", tone = "warning", size = "sm" },
										Badge.Badge { item.role or "worker", tone = "neutral", size = "sm" },
										if item.harness and item.harness ~= ""
											then Badge.Badge { item.harness, tone = "neutral", size = "sm" }
											else nil,
									},
									description = if item.detail and item.detail ~= "" then item.detail else reason_label,
									control = ui.row {
										gap = "$space.2",
										items = "center",
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
											else nil,
									},
								})
							end
							return Settings.Section {
								title = `{zeron.s("deck.attention.title")} ({#items})`,
								Settings.Group(att_rows),
							}
						end),

						-- 3. Navigation Tabs + live status badges on the tab rule's trail
						ui.column {
							w_full = true,
							gap = "$space.4",
							Tabs {
								value = active_tab,
								rule = true,
								inset = Settings.inset(ui.theme.get("space.1") :: number?),
								label = "Captain Deck sections",
								options = {
									{ value = "fleet", label = zeron.s("deck.tabs.fleet") },
									{ value = "workflows", label = zeron.s("deck.tabs.workflows") },
									{ value = "chats", label = zeron.s("deck.tabs.chats") },
									{ value = "activity", label = zeron.s("deck.tabs.activity") },
								},
								trail = ui.presence(function(): string
									local s = client.state:get()
									return `counts:{s and s.rev or 0}`
								end, function(): Node
									local s = client.state:peek() or {}
									local n_caps, n_workers, n_run = 0, 0, 0
									for _ in (s.captains or {}) do
										n_caps += 1
									end
									for _, w in (s.workers or {}) do
										n_workers += 1
										if w.status == "running" then
											n_run += 1
										end
									end
									local n_att = #client.attention_items()
									return ui.row {
										gap = "$space.1",
										items = "center",
										Badge.Badge { `{n_caps} Captains`, tone = "neutral", size = "sm", tabular = true },
										Badge.Badge { `{n_workers} Crew`, tone = "info", size = "sm", tabular = true },
										if n_run > 0
											then Badge.Badge { `{n_run} Running`, tone = "accent", size = "sm", dot = true, tabular = true }
											else nil,
										if n_att > 0
											then Badge.Badge { `{n_att} Needs You`, tone = "warning", size = "sm", dot = true, tabular = true }
											else nil,
									}
								end),
							},

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
							end, { w_full = true }),
						},
					},
				},
			},

			-- Slide-over Sheet: New Captain (Settings.Group form)
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
					gap = "$space.4",
					Settings.Group {
						Settings.Row {
							label = "Captain Name",
							stacked = true,
							control = TextField { value = nc_name, placeholder = "e.g. Release Captain, Auth Migration, Bug Triage", size = "sm" },
						},
						Settings.Row {
							label = "Mission",
							stacked = true,
							control = TextField { value = nc_mission, placeholder = "What goal does this Captain own?", size = "sm" },
						},
						Settings.Row {
							label = "Harness & Model",
							stacked = true,
							control = ui.column {
								w_full = true,
								gap = "$space.2",
								Select {
									value = nc_harness,
									options = function()
										return client.harness_options(true)
									end,
									size = "sm",
									w_full = true,
									on_change = function()
										nc_model:set("")
									end,
								},
								TextField { value = nc_custom_harness, placeholder = "Optional custom harness id (e.g. acp.gemini, hermes, pi)", size = "sm" },
								Select {
									value = nc_model,
									options = function()
										local c = trim(nc_custom_harness:get())
										return client.models_for(if c ~= "" then c else nc_harness:get())
									end,
									size = "sm",
									w_full = true,
								},
							},
						},
						Settings.Row {
							label = "Project",
							stacked = true,
							control = Select {
								value = nc_project,
								options = function()
									return client.project_options()
								end,
								size = "sm",
								w_full = true,
							},
						},
						Settings.Row {
							label = "Shared Crew Rules",
							description = "Automatically prepended to every worker spawned under this Captain.",
							stacked = true,
							control = TextArea { value = nc_rules, placeholder = "e.g. Always run tests. Never push or merge without human sign-off.", rows = 3, max_rows = 6, size = "sm" },
						},
						Settings.Row {
							label = "Opening Prompt (optional)",
							stacked = true,
							control = TextArea { value = nc_prompt, placeholder = "Leave blank to initialize with the Captain mission.", rows = 3, max_rows = 6, size = "sm" },
						},
						Settings.Row {
							label = "Auto-report to Captain",
							description = "Automatically report worker completions back to this Captain.",
							control = Switch { value = nc_auto_report, label = "Auto-report" },
						},
					},
				},
			},

			-- Slide-over Sheet: Spawn Worker (Settings.Group form)
			Dialog.Sheet {
				open = spawn_open,
				title = function(): string
					return `Spawn Worker · {sw_captain_name:get()}`
				end,
				description = "Start a worker chat on ANY harness/model and attach it to this Captain's Crew.",
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
					gap = "$space.4",
					Settings.Group {
						Settings.Row {
							label = "Role",
							control = Select { value = sw_role, options = ROLES, size = "sm" },
						},
						Settings.Row {
							label = "Harness & Model",
							stacked = true,
							control = ui.column {
								w_full = true,
								gap = "$space.2",
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
								},
								TextField { value = sw_custom_harness, placeholder = "Optional custom harness id (e.g. acp.gemini, hermes, pi)", size = "sm" },
								Select {
									value = sw_model,
									options = function()
										local c = trim(sw_custom_harness:get())
										return client.models_for(if c ~= "" then c else sw_harness:get())
									end,
									size = "sm",
									w_full = true,
								},
							},
						},
						Settings.Row {
							label = "Project",
							stacked = true,
							control = Select {
								value = sw_project,
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
								TextField { value = sw_task, placeholder = "Short title shown in Crew list", size = "sm" },
								TextArea { value = sw_prompt, placeholder = "Clear instructions for this worker…", rows = 4, max_rows = 8, size = "sm" },
							},
						},
						Settings.Row {
							label = "Auto-handoff on completion",
							description = "Automatically spawn a follow-up worker (e.g. cross-harness reviewer) when this worker finishes.",
							control = Switch { value = sw_enable_handoff, label = "Enable handoff" },
						},
						ui.show(function(): boolean
							return sw_enable_handoff:get()
						end, ui.column {
							w_full = true,
							Settings.Rule(),
							Settings.Row {
								label = "Next-stage Role & Harness",
								stacked = true,
								control = ui.column {
									w_full = true,
									gap = "$space.2",
									Select { value = sw_handoff_role, options = ROLES, size = "sm", w_full = true },
									Select {
										value = sw_handoff_harness,
										options = function()
											return client.harness_options(true)
										end,
										size = "sm",
										w_full = true,
									},
									TextArea {
										value = sw_handoff_prompt,
										rows = 3,
										max_rows = 6,
										size = "sm",
									},
								},
							},
						}),
					},
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
					gap = "$space.4",
					Settings.Group {
						Settings.Row {
							label = "Parent Captain",
							stacked = true,
							control = Select {
								value = at_captain_id,
								options = function()
									return captain_picker_options(false)
								end,
								size = "sm",
								w_full = true,
							},
						},
						Settings.Row {
							label = "Worker Role",
							control = Select { value = at_role, options = ROLES, size = "sm" },
						},
						Settings.Row {
							label = "Task Label",
							stacked = true,
							control = TextField { value = at_task, size = "sm" },
						},
					},
				},
			},
		}
	end)
end

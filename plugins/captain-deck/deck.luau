--!strict
-- Captain Deck: dedicated sidebar page (`zeron.page`).
--
-- Features:
-- 1. 1-Box Quick Mission Composer at the top of the page (Build -> Review,
--    Parallel Swarm, Compare 2 Agents, New Captain) with a compact picker bar.
-- 2. Clear parent-child visual hierarchy in the Fleet tab: distinct Captain
--    Header cards with Mission/Rules/Digest and an Indented Crew Tree connected
--    by a vertical hairline (`ui.div { w = 2, self = "stretch", ... }`).
-- 3. Focused 3-tab navigation: Fleet, Existing Chats, Activity.

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

		-- 1-Box Quick Mission Composer state
		local wf_preset = ui.use_state("build_review")
		local wf_captain_id = ui.use_state("")
		local wf_captain_name = ui.use_state("")
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
		local wf_options_open = ui.use_state(false)
		local wf_busy = ui.use_state(false)

		-- New Captain Sheet state (for advanced Captain config)
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

		-- Edit Captain Sheet state
		local edit_cap_open = ui.use_state(false)
		local ec_chat_id = ui.use_state("")
		local ec_name = ui.use_state("")
		local ec_mission = ui.use_state("")
		local ec_rules = ui.use_state("")
		local ec_digest = ui.use_state("")
		local ec_auto_report = ui.use_state(true)
		local ec_sched_mins = ui.use_state("")
		local ec_sched_prompt = ui.use_state("")
		local ec_busy = ui.use_state(false)

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
		local sw_handoff_prompt = ui.use_state(
			"Review the previous worker's output read-only. Check actual files and git diff, list Critical vs Minor issues.\n\nPrevious report:\n{{REPORT}}"
		)
		local sw_busy = ui.use_state(false)

		-- Attach existing chat Sheet state
		local attach_open = ui.use_state(false)
		local at_chat_id = ui.use_state("")
		local at_chat_title = ui.use_state("")
		local at_captain_id = ui.use_state("")
		local at_role = ui.use_state("worker")
		local at_task = ui.use_state("")
		local at_busy = ui.use_state(false)

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

		local function open_spawn_for(cap: any)
			sw_captain_id:set(cap.chat_id)
			sw_captain_name:set(cap.name or "Captain")
			sw_role:set("builder")
			sw_task:set("")
			sw_prompt:set("")
			sw_enable_handoff:set(false)
			spawn_open:set(true)
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
			edit_cap_open:set(true)
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
			attach_open:set(true)
		end

		local function open_attach_from_captain(cap: any)
			local chat_opts = unassigned_chat_options()
			local first_chat = if #chat_opts > 0 then chat_opts[1].value else ""
			local first_label = if #chat_opts > 0 and first_chat ~= "" then chat_opts[1].label else "Attached chat"
			open_attach_for(first_chat, first_label, cap.chat_id)
		end

		local function submit_composer()
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

			if mode == "captain" then
				local cap_name = if custom_title ~= "" then custom_title else string.sub(task, 1, 36)
				client.call("create_captain", {
					name = cap_name,
					mission = task,
					rules = wf_rules:peek(),
					prompt = task,
					harness = primary_h,
					model = wf_primary_model:peek(),
					project = wf_project:peek(),
					auto_report = true,
				}):after(function(cap: any)
					wf_busy:set(false)
					wf_task:set("")
					wf_subtasks:set("")
					wf_captain_name:set("")
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
				wf_captain_name:set("")
				active_tab:set("fleet")
				zeron.toast(zeron.s("toast.workflow_launched"))
				if res and res.captain_id and panel then
					client.open_inspector(panel, res.captain_id)
				end
			end, function()
				wf_busy:set(false)
			end)
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

		local function submit_edit_captain()
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
				edit_cap_open:set(false)
				zeron.toast(zeron.s("toast.saved"))
			end, function()
				ec_busy:set(false)
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
				attach_open:set(false)
				zeron.toast(zeron.s("toast.worker_attached"))
			end, function()
				at_busy:set(false)
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

		-- ── 1-Box Quick Mission Composer (Always Ready at Top of Deck) ────
		local function build_quick_composer(): Node
			local composer_modes = {
				{ value = "build_review", label = zeron.s("deck.composer.mode_build_review") },
				{ value = "fanout", label = zeron.s("deck.composer.mode_fanout") },
				{ value = "compare", label = zeron.s("deck.composer.mode_compare") },
				{ value = "captain", label = zeron.s("deck.composer.mode_captain") },
			}

			return Settings.Group {
				ui.column {
					w_full = true,
					p = "$space.4",
					gap = "$space.3",

					-- Top Row: Mode Segmented Pill + "+ Options" toggle
					ui.row {
						w_full = true,
						flex_wrap = true,
						items = "center",
						justify = "between",
						gap = "$space.2",
						ui.row {
							grow = 1,
							min_w = 260,
							Segmented {
								value = wf_preset,
								options = composer_modes,
								fill = true,
								label = zeron.s("deck.composer.title"),
							},
						},
						Button {
							size = "xs",
							tone = if wf_options_open:get() then "accent" else "ghost",
							on_click = function()
								wf_options_open:set(not wf_options_open:peek())
							end,
							Icon { name = "settings", size = 12 },
							function(): string
								return if wf_options_open:get()
									then zeron.s("deck.composer.options_hide")
									else zeron.s("deck.composer.options_show")
							end,
						},
					},

					-- Dynamic 1-line mode explanation
					Text {
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
						style = "caption",
						tone = "secondary",
						wrap = true,
					},

					-- Main Mission / Task TextArea
					TextArea {
						value = wf_task,
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
						max_rows = 8,
						size = "sm",
						w_full = true,
					},

					-- Parallel Swarm Subtasks TextArea (only when mode == "fanout")
					ui.show(function(): boolean
						return wf_preset:get() == "fanout"
					end, ui.column {
						w_full = true,
						gap = "$space.1",
						Text {
							zeron.s("deck.composer.subtasks_label"),
							style = "caption",
							tone = "secondary",
						},
						TextArea {
							value = wf_subtasks,
							placeholder = zeron.s("deck.composer.subtasks_placeholder"),
							rows = 3,
							max_rows = 8,
							size = "sm",
							w_full = true,
						},
					}),

					-- Collapsible "+ Options" drawer (Captain title, target Captain, shared rules, custom harness override)
					ui.show(function(): boolean
						return wf_options_open:get()
					end, ui.column {
						w_full = true,
						gap = "$space.3",
						p = "$space.3",
						rounded = "$radius.md",
						bg = "$bg.surface",
						border = 1,
						border_color = "$border.subtle",
						ui.row {
							w_full = true,
							flex_wrap = true,
							gap = "$space.2",
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 240,
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
								min_w = 220,
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
								min_w = 240,
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
								min_w = 240,
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
					}),

					Settings.Rule(),

					-- Structured Full-Width Picker Grid & Footer Action Bar
					-- 1-Agent Modes (`fanout` / `captain`): 3 proportional columns (Project, Harness, wide Model) + right-aligned Launch button
					ui.show(function(): boolean
						local m = wf_preset:get()
						return m == "fanout" or m == "captain"
					end, ui.column {
						w_full = true,
						gap = "$space.3",
						ui.row {
							w_full = true,
							flex_wrap = true,
							items = "end",
							gap = "$space.2",
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 140,
								gap = "$space.1",
								Text { zeron.s("deck.composer.label_project"), style = "caption", tone = "secondary" },
								Select {
									value = wf_project,
									options = function()
										return client.project_options()
									end,
									size = "sm",
									w_full = true,
								},
							},
							ui.column {
								grow = 1,
								basis = 0,
								min_w = 150,
								gap = "$space.1",
								Text { zeron.s("deck.composer.label_harness"), style = "caption", tone = "secondary" },
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
								grow = 2,
								basis = 0,
								min_w = 240,
								gap = "$space.1",
								Text { zeron.s("deck.composer.label_model"), style = "caption", tone = "secondary" },
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
							Button {
								tone = "primary",
								size = "sm",
								busy = wf_busy,
								on_click = submit_composer,
								Icon { name = "action-play", size = 13 },
								function(): string
									return if wf_preset:get() == "captain"
										then zeron.s("deck.composer.launch_captain")
										else zeron.s("deck.composer.launch_mission")
								end,
							},
						},
					}),

					-- 2-Agent Modes (`build_review` / `compare`): 2 aligned stage rows (Stage Badge | Harness | Full-Width Model) + Footer Action Row
					ui.show(function(): boolean
						local m = wf_preset:get()
						return m == "build_review" or m == "compare"
					end, ui.column {
						w_full = true,
						gap = "$space.2",
						-- Stage 1 Row (Builder / Candidate A)
						ui.row {
							w_full = true,
							flex_wrap = true,
							items = "center",
							gap = "$space.2",
							ui.row {
								w = 110,
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
								w = 175,
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
								min_w = 220,
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
						-- Stage 2 Row (Reviewer / Candidate B)
						ui.row {
							w_full = true,
							flex_wrap = true,
							items = "center",
							gap = "$space.2",
							ui.row {
								w = 110,
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
								w = 175,
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
								min_w = 220,
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
						-- Composer Footer Bar: Left = Project Picker, Right = Launch Button
						ui.row {
							w_full = true,
							flex_wrap = true,
							items = "center",
							justify = "between",
							gap = "$space.2",
							pt = "$space.1",
							ui.row {
								items = "center",
								gap = "$space.2",
								Icon { name = "folder", size = 14, color = "$text.tertiary" },
								Text { zeron.s("deck.composer.label_project"), style = "caption", tone = "secondary" },
								ui.column {
									w = 210,
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
							Button {
								tone = "primary",
								size = "sm",
								busy = wf_busy,
								on_click = submit_composer,
								Icon { name = "action-play", size = 13 },
								function(): string
									return if wf_preset:get() == "captain"
										then zeron.s("deck.composer.launch_captain")
										else zeron.s("deck.composer.launch_mission")
								end,
							},
						},
					}),
				},
			}
		end

		-- ── Fleet Tab (Clear Parent Captain Header + Indented Crew Tree) ──
		local function build_fleet(): Node
			return ui.column {
				w_full = true,
				gap = "$space.4",
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

						-- Captain Status & Summary Badges
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
								tone = if sum.running > 0 then "accent" else "info",
								size = "sm",
								dot = sum.running > 0,
								tabular = true,
							}
						)
						if sum.attention > 0 then
							table.insert(
								cap_badges,
								Badge.Badge {
									`{sum.attention} needs you`,
									tone = "warning",
									size = "sm",
									dot = true,
									tabular = true,
								}
							)
						end
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

						-- Captain Header Section (Parent Node)
						local cap_header = ui.column {
							w_full = true,
							p = "$space.4",
							gap = "$space.3",
							ui.row {
								w_full = true,
								flex_wrap = true,
								items = "center",
								justify = "between",
								gap = "$space.3",
								-- Left: Accent Captain icon tile + StatusIcon + Semibold Captain Name + Badges
								ui.row {
									grow = 1,
									min_w = 240,
									items = "center",
									gap = "$space.3",
									ui.div {
										w = 34,
										h = 34,
										shrink = 0,
										rounded = "$radius.md",
										bg = "$bg.surface",
										border = 1,
										border_color = "$border.subtle",
										items = "center",
										justify = "center",
										Icon { name = "users-group-rounded", size = 17, color = "$fg.accent" },
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
												cap.name or client.session_title(cap.chat_id),
												text_size = "$font.size.md",
												weight = "$font.weight.semibold",
												color = "$text.primary",
											},
											ui.row {
												flex_wrap = true,
												items = "center",
												gap = "$space.1",
												table.unpack(cap_badges),
											},
										},
										if cap.mission and cap.mission ~= ""
											then Text {
												cap.mission,
												style = "caption",
												tone = "secondary",
												wrap = true,
											}
											else nil,
									},
								},
								-- Right: Captain Action Bar (+ Worker, Attach Chat, Inspector, Open Chat, Edit, Demote)
								ui.row {
									flex_wrap = true,
									items = "center",
									gap = "$space.1",
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
											open_attach_from_captain(cap)
										end,
										Icon { name = "git-branch", size = 12 },
										zeron.s("deck.fleet.attach_chat"),
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
									Button {
										size = "xs",
										tone = "ghost",
										on_click = function()
											open_edit_for(cap)
										end,
										Icon { name = "pen", size = 12 },
										zeron.s("deck.fleet.edit"),
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
							},

							-- Optional Shared Rules & Live Digest pills inside Captain Header
							if (cap.rules and cap.rules ~= "") or (cap.digest and cap.digest ~= "")
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
						}

						-- Indented Crew Tree Section (Child Worker Nodes)
						local crew_tree_node: Node
						if #crew == 0 then
							crew_tree_node = ui.row {
								w_full = true,
								pl = "$space.6",
								pr = "$space.4",
								py = "$space.3",
								gap = "$space.3",
								items = "center",
								ui.div {
									w = 2,
									self = "stretch",
									rounded = "$radius.full",
									bg = "$border.subtle",
								},
								ui.row {
									grow = 1,
									flex_wrap = true,
									items = "center",
									justify = "between",
									gap = "$space.2",
									ui.row {
										items = "center",
										gap = "$space.2",
										Text { "└─", style = "mono", tone = "tertiary" },
										Icon { name = "bot", size = 14, color = "$text.tertiary" },
										Text {
											zeron.s("deck.fleet.no_crew"),
											style = "caption",
											tone = "secondary",
											wrap = true,
										},
									},
									Button {
										size = "xs",
										tone = "secondary",
										on_click = function()
											open_spawn_for(cap)
										end,
										Icon { name = "plus", size = 12 },
										zeron.s("deck.fleet.spawn_worker"),
									},
								},
							}
						else
							local worker_cards: { Node } = {}
							for idx, w in crew do
								local is_last = idx == #crew
								local branch_char = if is_last then "└─" else "├─"
								local is_steer = steer_chat:peek() == w.chat_id
								local snippet = if w.last_error and w.last_error ~= ""
									then w.last_error
									elseif w.last_reply and w.last_reply ~= ""
									then (string.gsub(string.sub(w.last_reply, 1, 220), "[\r\n]+", " "))
									else ""

								local w_badges: { Node } = {
									Badge.Badge {
										w.role or "worker",
										tone = role_badge_tone(w.role),
										size = "sm",
									},
								}
								if w.harness and w.harness ~= "" then
									local hm = if w.model and w.model ~= ""
										then `{w.harness} · {w.model}`
										else w.harness
									table.insert(w_badges, Badge.Badge { hm, tone = "neutral", size = "sm" })
								elseif w.model and w.model ~= "" then
									table.insert(w_badges, Badge.Badge { w.model, tone = "neutral", size = "sm", look = "outline" })
								end
								if w.status and w.status ~= "idle" then
									table.insert(
										w_badges,
										Badge.Badge {
											w.status,
											tone = client.status_tone(w.status),
											size = "sm",
											dot = w.status == "running" or w.status == "awaiting_input",
										}
									)
								end
								if w.next_stage then
									table.insert(
										w_badges,
										Badge.Badge {
											`Then → {w.next_stage.role or "reviewer"} ({w.next_stage.harness or "auto"})`,
											tone = "info",
											size = "sm",
											icon = "map-arrow-right",
										}
									)
								end

								table.insert(
									worker_cards,
									ui.column {
										w_full = true,
										py = "$space.2",
										gap = "$space.2",
										-- Worker header row: branch symbol + StatusIcon + Role/Harness badges + Title + Quick actions
										ui.row {
											w_full = true,
											flex_wrap = true,
											items = "center",
											justify = "between",
											gap = "$space.2",
											ui.row {
												grow = 1,
												min_w = 200,
												flex_wrap = true,
												items = "center",
												gap = "$space.2",
												Text { branch_char, style = "mono", tone = "tertiary" },
												Status.StatusIcon { kind = client.status_kind(w.status) :: any, size = 14 },
												ui.row {
													flex_wrap = true,
													items = "center",
													gap = "$space.1",
													table.unpack(w_badges),
												},
												Text {
													w.task or client.session_title(w.chat_id),
													weight = "$font.weight.medium",
													color = "$text.primary",
													wrap = true,
												},
											},
											ui.row {
												items = "center",
												gap = "$space.1",
												Text {
													format_age(w.updated_at),
													style = "caption",
													tone = "tertiary",
												},
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

										-- Subtle report preview box (`w.last_reply` or `w.last_error`)
										if snippet ~= ""
											then ui.div {
												w_full = true,
												bg = "$bg.surface",
												rounded = "$radius.md",
												px = "$space.2",
												py = "$space.1",
												border = 1,
												border_color = "$border.subtle",
												Text {
													snippet,
													style = "caption",
													tone = if w.last_error and w.last_error ~= "" then "danger" else "secondary",
													wrap = true,
												},
											}
											else nil,

										-- Inline Steer / Queue input bar
										if is_steer
											then ui.row {
												w_full = true,
												pt = "$space.1",
												gap = "$space.2",
												items = "center",
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

										if not is_last then Settings.Rule() else nil,
									}
								)
							end

							crew_tree_node = ui.row {
								w_full = true,
								pl = "$space.6",
								pr = "$space.4",
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
									table.unpack(worker_cards),
								},
							}
						end

						table.insert(
							sections,
							Settings.Group {
								cap_header,
								Settings.Rule(),
								crew_tree_node,
							}
						)
					end

					if #sections == 0 then
						return Settings.Group {
							ui.column {
								w_full = true,
								py = "$space.4",
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
										label = zeron.s("deck.tabs.chats"),
										icon = "chat-round-line",
										on_click = function()
											active_tab:set("chats")
										end,
									},
								},
							},
						}
					end

					return ui.column { w_full = true, gap = "$space.3", table.unpack(sections) }
				end, { w_full = true }),
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
							py = "$space.4",
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
					local title = if type(sess.title) == "string" and sess.title ~= ""
						then sess.title
						else string.sub(sid, 1, 8)
					local sub = if sess.branch and sess.branch ~= ""
						then `{sess.branch} · Updated {format_age(sess.updated)}`
						else `Updated {format_age(sess.updated)}`

					table.insert(
						rows,
						Settings.Row {
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
											open_attach_for(sid, title, nil)
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
						}
					)
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
							py = "$space.4",
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
					table.insert(
						rows,
						Settings.Row {
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
						}
					)
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
							ui.presence(function(): string
								local s = client.state:get()
								return `hdr_counts:{s and s.rev or 0}`
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
									flex_wrap = true,
									Badge.Badge { `{n_caps} {zeron.s("deck.stats.captains")}`, tone = "neutral", size = "sm", tabular = true },
									Badge.Badge { `{n_workers} {zeron.s("deck.stats.workers")}`, tone = "info", size = "sm", tabular = true },
									if n_run > 0
										then Badge.Badge { `{n_run} {zeron.s("deck.stats.running")}`, tone = "accent", size = "sm", dot = true, tabular = true }
										else nil,
									if n_att > 0
										then Badge.Badge { `{n_att} {zeron.s("deck.stats.attention")}`, tone = "warning", size = "sm", dot = true, tabular = true }
										else nil,
								}
							end),
							IconButton {
								icon = "refresh",
								label = zeron.s("deck.refresh"),
								tone = "quiet",
								on_click = function()
									client.refresh()
									client.probe_harnesses(nil)
								end,
							},
						},

						-- Unified Body Container (prevents empty ui.presence siblings from adding 24px gap in Settings.Page)
						ui.column {
							w_full = true,
							gap = "$space.4",

							-- 1. Service warning callout (only rendered when service_err is non-empty)
							ui.show(function(): boolean
								local err = client.service_err:get()
								return type(err) == "string" and err ~= ""
							end, ui.presence(function(): string
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
							end, { w_full = true })),

							-- 2. 1-Box Quick Mission Composer (Always Ready at the top of the page)
							build_quick_composer(),

							-- 3. Needs Your Attention Section (only rendered when #items > 0)
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
								for _, item in items do
									local reason_label = if item.status == "awaiting_input"
										then zeron.s("deck.attention.awaiting_input")
										elseif item.status == "limited"
										then zeron.s("deck.attention.limited")
										else zeron.s("deck.attention.errored")
									table.insert(
										att_rows,
										Settings.Row {
											lead = Status.StatusIcon { kind = client.status_kind(item.status) :: any, size = 15 },
											label = item.title or reason_label,
											badge = ui.row {
												gap = "$space.1",
												items = "center",
												flex_wrap = true,
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
										}
									)
								end
								return Settings.Section {
									title = `{zeron.s("deck.attention.title")} ({#items})`,
									Settings.Group(att_rows),
								}
							end, { w_full = true })),

							-- 4. Simplified 3-Tab Navigation (Fleet, Existing Chats, Activity)
							ui.column {
								w_full = true,
								gap = "$space.3",
								Tabs {
									value = active_tab,
									rule = true,
									inset = Settings.inset(ui.theme.get("space.1") :: number?),
									label = "Captain Deck sections",
									options = {
										{ value = "fleet", label = zeron.s("deck.tabs.fleet") },
										{ value = "chats", label = zeron.s("deck.tabs.chats") },
										{ value = "activity", label = zeron.s("deck.tabs.activity") },
									},
								},

								ui.presence(function(): string
									return active_tab:get()
								end, function(tab: string): Node
									if tab == "chats" then
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
			},

			-- Slide-over Sheet: New Captain (Advanced form)
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
							control = TextField {
								value = nc_name,
								placeholder = "e.g. Release Captain, Auth Migration, Bug Triage",
								size = "sm",
								w_full = true,
							},
						},
						Settings.Row {
							label = "Mission",
							stacked = true,
							control = TextField {
								value = nc_mission,
								placeholder = "What goal does this Captain own?",
								size = "sm",
								w_full = true,
							},
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
								TextField {
									value = nc_custom_harness,
									placeholder = "Optional custom harness id (e.g. acp.gemini, hermes, pi)",
									size = "sm",
									w_full = true,
								},
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
							control = TextArea {
								value = nc_rules,
								placeholder = "e.g. Always run tests. Never push or merge without human sign-off.",
								rows = 3,
								max_rows = 6,
								size = "sm",
								w_full = true,
							},
						},
						Settings.Row {
							label = "Opening Prompt (optional)",
							stacked = true,
							control = TextArea {
								value = nc_prompt,
								placeholder = "Leave blank to initialize with the Captain mission.",
								rows = 3,
								max_rows = 6,
								size = "sm",
								w_full = true,
							},
						},
						Settings.Row {
							label = "Auto-report to Captain",
							description = "Automatically report worker completions back to this Captain.",
							control = Switch { value = nc_auto_report, label = "Auto-report" },
						},
					},
				},
			},

			-- Slide-over Sheet: Edit Captain
			Dialog.Sheet {
				open = edit_cap_open,
				title = function(): string
					return `Edit Captain · {ec_name:get()}`
				end,
				description = "Update this Captain's mission, shared crew rules, live digest, and periodic wake schedule.",
				foot = ui.row {
					w_full = true,
					gap = "$space.2",
					justify = "end",
					Button {
						tone = "ghost",
						size = "sm",
						on_click = function()
							edit_cap_open:set(false)
						end,
						zeron.s("dialogs.cancel"),
					},
					Button {
						tone = "primary",
						size = "sm",
						busy = ec_busy,
						on_click = submit_edit_captain,
						zeron.s("dialogs.save"),
					},
				},
				ui.column {
					w_full = true,
					gap = "$space.4",
					Settings.Group {
						Settings.Row {
							label = "Captain Name",
							stacked = true,
							control = TextField { value = ec_name, size = "sm", w_full = true },
						},
						Settings.Row {
							label = zeron.s("inspector.mission"),
							stacked = true,
							control = TextField {
								value = ec_mission,
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
								value = ec_rules,
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
								value = ec_digest,
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
							control = Switch { value = ec_auto_report, label = "Auto-report" },
						},
						Settings.Row {
							label = "Scheduled Wake (minutes, 0 = off)",
							description = "Wake this Captain periodically when idle (minimum 5 minutes).",
							stacked = true,
							control = ui.column {
								w_full = true,
								gap = "$space.2",
								TextField { value = ec_sched_mins, placeholder = "0 (off) or e.g. 60", size = "sm", w_full = true },
								TextField {
									value = ec_sched_prompt,
									placeholder = "Wake prompt, e.g. Check crew reports and update digest.",
									size = "sm",
									w_full = true,
								},
							},
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
							stacked = true,
							control = Select { value = sw_role, options = ROLES, size = "sm", w_full = true },
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
								TextField {
									value = sw_custom_harness,
									placeholder = "Optional custom harness id (e.g. acp.gemini, hermes, pi)",
									size = "sm",
									w_full = true,
								},
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
								TextField {
									value = sw_task,
									placeholder = "Short title shown in Crew tree",
									size = "sm",
									w_full = true,
								},
								TextArea {
									value = sw_prompt,
									placeholder = "Clear instructions for this worker…",
									rows = 4,
									max_rows = 8,
									size = "sm",
									w_full = true,
								},
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
										w_full = true,
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
				description = "Link an existing Zeron chat session under a Captain to track its turns and reports.",
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
							label = "Chat Session",
							stacked = true,
							control = Select {
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
							},
						},
						Settings.Row {
							label = "Worker Role",
							stacked = true,
							control = Select { value = at_role, options = ROLES, size = "sm", w_full = true },
						},
						Settings.Row {
							label = "Task Label",
							stacked = true,
							control = TextField { value = at_task, size = "sm", w_full = true },
						},
					},
				},
			},
		}
	end)
end

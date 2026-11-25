--!strict
-- Side-panel Crew Inspector tab (`zeron.tab("captain-inspector", ...)`).
--
-- Focused, compact live monitoring & quick actions for the narrow right panel:
-- 1. Compact Captain header card with status, + Worker toggle, Open chat & Open Deck.
-- 2. Vertical collapsible Live Digest (collapsed by default to ~140 chars).
-- 3. Conditional Needs You alert cards (only rendered when active items > 0).
-- 4. Minimalist Quick + Worker spawn card (only rendered when toggled).
-- 5. Dense, scannable Crew list with high-contrast native role pills & inline Steer/Queue.
-- 6. Subtle footer shortcut to open the full Captain Deck (/captain).

local Badge = require("@ds/badge")
local Button = require("@ds/button")
local EmptyState = require("@ds/empty_state")
local Icon = require("@ds/icon")
local IconButton = require("@ds/icon_button").IconButton
local Select = require("@ds/select")
local Status = require("@ds/status")
local Text = require("@ds/text")
local TextArea = require("@ds/text_area")
local TextField = require("@ds/text_field")

local ok_dropdown, dropdown_mod = pcall(require, "@ds/dropdown")
local Dropdown: any = if ok_dropdown and dropdown_mod ~= nil then dropdown_mod else nil

local ROLES = {
	{ value = "builder", label = "Builder" },
	{ value = "reviewer", label = "Reviewer" },
	{ value = "researcher", label = "Researcher" },
	{ value = "tester", label = "Tester / QA" },
	{ value = "planner", label = "Planner" },
	{ value = "worker", label = "General Worker" },
}

local function trim(s: any): string
	if type(s) ~= "string" then
		return ""
	end
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function collapse_whitespace(s: string): string
	return trim((string.gsub(s, "%s+", " ")))
end

local function clip_text(s: string, max_len: number): string
	if #s <= max_len then
		return s
	end
	if max_len <= 1 then
		return "…"
	end
	return trim(string.sub(s, 1, max_len - 1)) .. "…"
end

local function fallback_short_model(harness: string?, model: string?): string
	local m = trim(model)
	if m == "" then
		return ""
	end
	local h = string.lower(trim(harness))
	if h ~= "" then
		local low = string.lower(m)
		local slash_prefix = h .. "/"
		local colon_prefix = h .. ":"
		if string.sub(low, 1, #slash_prefix) == slash_prefix then
			m = string.sub(m, #slash_prefix + 1)
		elseif string.sub(low, 1, #colon_prefix) == colon_prefix then
			m = string.sub(m, #colon_prefix + 1)
		end
	end
	return trim(m)
end

local function field_block(label: string, control: Node): Node
	return ui.column {
		w_full = true,
		gap = "$space.1",
		Text {
			label,
			text_size = "$font.size.xs",
			weight = "$font.weight.medium",
			color = "$text.tertiary",
		},
		control,
	}
end

return function(zeron: any, client: any): (props: { tab: any }) -> Node
	local function open_deck()
		if type(client.open_deck) == "function" then
			pcall(client.open_deck)
		elseif type(client.toggle_deck) == "function" then
			pcall(client.toggle_deck)
		end
	end

	local function short_model(harness: string?, model: string?): string
		if type(client.short_model) == "function" then
			local ok, res = pcall(client.short_model, harness, model)
			if ok and type(res) == "string" then
				return trim(res)
			end
		end
		return fallback_short_model(harness, model)
	end

	local function format_harness_model(harness: string?, model: string?): string
		local h = trim(harness)
		local m = short_model(h, model)
		if h ~= "" and m ~= "" then
			if string.lower(h) == string.lower(m) then
				return h
			end
			return `{h} · {m}`
		elseif m ~= "" then
			return m
		elseif h ~= "" then
			return h
		end
		return ""
	end

	local function safe_status_kind(status: string?): any
		if type(client.status_kind) == "function" then
			return client.status_kind(status)
		end
		return "waiting"
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

	local function collect_attention_items(cid: string, cap: any, crew: { any }): { any }
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
			local chat_id = if type(entry.chat_id) == "string" then entry.chat_id else ""
			local eid = tostring(entry.id or chat_id)
			local key = if kind == "awaiting_input" then `awaiting_input:{chat_id}` else `needs_you:{eid}`
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

		if type(client.attention_items) == "function" then
			local ok, raw_items = pcall(client.attention_items, cid)
			if ok and type(raw_items) == "table" then
				for _, item in raw_items do
					if type(item) == "table" then
						local item_cap = if type(item.captain_id) == "string" then item.captain_id else ""
						if cid == "" or item_cap == "" or item_cap == cid then
							if item.kind == "awaiting_input" then
								push_item(item)
							elseif item.kind == "needs_you" or item.kind == "escalation" then
								push_item({
									kind = "needs_you",
									id = item.item_id or item.id,
									captain_id = if item_cap ~= "" then item_cap else cid,
									captain_name = item.captain_name,
									chat_id = item.chat_id or cid,
									role = item.role or "captain",
									title = item.title or "Needs decision",
									detail = item.detail or "",
								})
							elseif (item.kind == "worker" or item.kind == "captain_status") and item.status == "awaiting_input" then
								push_item({
									kind = "awaiting_input",
									id = item.id,
									captain_id = if item_cap ~= "" then item_cap else cid,
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

		local cap_name = if cap and type(cap.name) == "string" and trim(cap.name) ~= "" then trim(cap.name) else "Captain"
		if cap and cap.status == "awaiting_input" then
			local pi = if type(cap.pending_input) == "table" then cap.pending_input else nil
			push_item({
				kind = "awaiting_input",
				id = `input:{cid}`,
				captain_id = cid,
				captain_name = cap_name,
				chat_id = cid,
				role = "Captain",
				title = if pi and trim(pi.title) ~= "" then trim(pi.title) else cap_name,
				detail = trim(if pi and trim(pi.detail) ~= "" then pi.detail else cap.mission),
				request = if pi then pi.request else nil,
			})
		end
		for _, member in crew do
			if type(member) == "table" and member.status == "awaiting_input" then
				local pi = if type(member.pending_input) == "table" then member.pending_input else nil
				local m_role = if type(member.role) == "string" and trim(member.role) ~= "" then trim(member.role) else "worker"
				local m_detail = trim(if pi then pi.detail else nil)
				if m_detail == "" then
					m_detail = trim(member.task)
				end
				push_item({
					kind = "awaiting_input",
					id = `input:{member.chat_id}`,
					captain_id = cid,
					captain_name = cap_name,
					chat_id = member.chat_id,
					role = m_role,
					title = if pi and trim(pi.title) ~= "" then trim(pi.title) else (member.task or m_role),
					detail = m_detail,
					request = if pi then pi.request else nil,
				})
			end
		end
		if cap and type(cap.needs_you) == "table" then
			for _, item in cap.needs_you do
				if type(item) == "table" and not item.resolved then
					push_item({
						kind = "needs_you",
						id = item.id,
						captain_id = cid,
						captain_name = cap_name,
						chat_id = item.worker_chat or cid,
						role = "captain",
						title = item.title or "Needs decision",
						detail = item.detail or "",
					})
				end
			end
		end

		local out: { any } = {}
		for _, item in awaiting_list do
			table.insert(out, item)
		end
		for _, item in needs_list do
			table.insert(out, item)
		end
		return out
	end

	return ui.component(function(props: { tab: any }): Node
		local function current_captain_id(): string
			local d = if props and props.tab and type(props.tab.data) == "table" then props.tab.data else {}
			return if type(d.captain_id) == "string" then d.captain_id else ""
		end

		-- Collapsible digest state (collapsed by default; keyed by captain_id so switching resets cleanly)
		local digest_expanded_cid = ui.use_state(nil :: string?)

		-- Quick + Worker form state (hidden by default)
		local show_spawn = ui.use_state(false)
		local sp_role = ui.use_state("builder")
		local sp_harness = ui.use_state("")
		local sp_model = ui.use_state("")
		local sp_task = ui.use_state("")
		local sp_prompt = ui.use_state("")
		local spawning = ui.use_state(false)

		-- Inline worker Steer/Queue state
		local steer_target = ui.use_state(nil :: string?)
		local steer_text = ui.use_state("")
		local sending = ui.use_state(false)

		local function spawn_worker()
			local cid = current_captain_id()
			if cid == "" then
				return
			end
			local prompt = trim(sp_prompt:peek())
			if prompt == "" then
				zeron.toast("Enter a prompt for the worker")
				return
			end
			spawning:set(true)
			local raw_h = trim(sp_harness:peek())
			local clean_h = raw_h
			if type(client.sanitize_harness) == "function" then
				local ok_sh, sanitized = pcall(client.sanitize_harness, raw_h)
				if ok_sh and type(sanitized) == "string" then
					clean_h = sanitized
				end
			end
			client.call("spawn_worker", {
				captain_id = cid,
				role = sp_role:peek(),
				task = trim(sp_task:peek()),
				prompt = prompt,
				harness = clean_h,
				model = trim(sp_model:peek()),
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
			if txt == "" or chat_id == "" then
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
				p = "$space.3",
				gap = "$space.3",
				ui.presence(function(): string
					local cid = current_captain_id()
					local cap = client.captain_of(cid)
					if not cap then
						return `missing:{cid}`
					end
					local s = client.state:get()
					local crew = client.crew_of(cid) or {}
					local attn = collect_attention_items(cid, cap, crew)
					local attn_sig: { string } = {}
					for _, item in attn do
						table.insert(attn_sig, `{item.kind}:{tostring(item.id or "")}:{item.chat_id or ""}`)
					end
					return `ok:{cid}:{s and s.rev or 0}:{tostring(show_spawn:get())}:{tostring(steer_target:get())}:{table.concat(attn_sig, ",")}`
				end, function(key: string): Node
					if string.sub(key, 1, 8) == "missing:" then
						return ui.column {
							w_full = true,
							gap = "$space.3",
							EmptyState {
								size = "sm",
								icon = "users-group-rounded",
								title = zeron.s("inspector.not_found"),
								body = "Promote a chat to a Captain to inspect its crew here.",
							},
							ui.row {
								w_full = true,
								justify = "center",
								Button {
									size = "xs",
									tone = "ghost",
									tooltip = "Open Captain Deck (/captain)",
									on_click = open_deck,
									Icon { name = "users-group-rounded", size = 12 },
									"Open Deck",
								},
							},
						}
					end

					local cid = current_captain_id()
					local cap = client.captain_of(cid)
					if not cap then
						return ui.div {}
					end

					local crew = client.crew_of(cid) or {}
					local sum = client.crew_summary(cid) or { total = 0, running = 0, attention = 0, completed = 0 }
					local attn_items = collect_attention_items(cid, cap, crew)

					local cap_name = trim(cap.name)
					if cap_name == "" then
						cap_name = "Captain"
					end
					local cap_meta = format_harness_model(cap.harness, cap.model)
					local cap_mission = trim(cap.mission)
					local show_mission = cap_mission ~= "" and string.lower(cap_mission) ~= string.lower(cap_name)
					local cap_digest = trim(cap.digest)

					local sections: { Node } = {}

					-- 1. Compact Captain Header Card
					table.insert(
						sections,
						ui.column {
							w_full = true,
							p = "$space.3",
							gap = "$space.2",
							rounded = "$radius.lg",
							bg = "$surface.raised",
							border = 1,
							border_color = if #attn_items > 0 then "$warning" else "$border",

							-- Row 1: Status + Name | + Worker, Open chat, Open Deck
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
									Status.StatusIcon { kind = safe_status_kind(cap.status), size = 14 },
									Text {
										cap_name,
										grow = 1,
										min_w = 0,
										weight = "$font.weight.semibold",
										text_size = "$font.size.sm",
										color = "$text.primary",
										truncate = true,
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
											show_spawn:set(not show_spawn:peek())
										end,
										Icon { name = "plus", size = 12 },
										"Worker",
									},
									IconButton {
										icon = "arrow-up-right",
										size = "sm",
										tone = "quiet",
										label = "Open Captain chat",
										on_click = function()
											pcall(zeron.open, { session = cid })
										end,
									},
									IconButton {
										icon = "users-group-rounded",
										size = "sm",
										tone = "quiet",
										label = "Open Deck",
										tooltip = "Open Captain Deck (/captain)",
										on_click = open_deck,
									},
								},
							},

							-- Row 2: Captain accent badge, Crew count, Muted harness · short_model
							ui.row {
								w_full = true,
								flex_wrap = true,
								items = "center",
								gap = "$space.1",
								Badge.Badge { "Captain", tone = "accent", size = "sm" },
								Badge.Badge {
									`{sum.total} crew`,
									tone = "neutral",
									size = "sm",
									dot = sum.running > 0,
									tabular = true,
								},
								if cap_meta ~= ""
									then Text {
										cap_meta,
										text_size = "$font.size.xs",
										color = "$text.tertiary",
										truncate = true,
										min_w = 0,
									}
									else nil,
							},

							-- Row 3 (optional): Short mission when distinct from Captain name
							if show_mission
								then Text {
									clip_text(collapse_whitespace(cap_mission), 160),
									text_size = "$font.size.xs",
									color = "$text.secondary",
									wrap = true,
								}
								else nil,
						}
					)

					-- 2. Vertical & Collapsible Live Digest (default collapsed)
					if cap_digest ~= "" then
						local has_newlines = string.find(cap_digest, "\n", 1, true) ~= nil
						local can_toggle = #cap_digest > 140 or has_newlines
						local preview_digest = clip_text(collapse_whitespace(cap_digest), 140)

						table.insert(
							sections,
							ui.presence(function(): string
								return if digest_expanded_cid:get() == cid then "expanded" else "collapsed"
							end, function(mode: string): Node
								local is_expanded = mode == "expanded"
								return ui.column {
									w_full = true,
									bg = "$surface.sunken",
									border = 1,
									border_color = "$border.subtle",
									rounded = "$radius.md",
									px = "$space.2",
									py = "$space.2",
									gap = "$space.1",
									ui.row {
										w_full = true,
										items = "center",
										justify = "between",
										gap = "$space.2",
										Text {
											"Digest",
											color = "$accent",
											weight = "$font.weight.medium",
											text_size = "$font.size.xs",
										},
										if can_toggle or is_expanded
											then Button {
												size = "xs",
												tone = "ghost",
												on_click = function()
													if digest_expanded_cid:peek() == cid then
														digest_expanded_cid:set(nil)
													else
														digest_expanded_cid:set(cid)
													end
												end,
												if is_expanded then "Collapse" else "Expand",
											}
											else nil,
									},
									Text {
										if is_expanded then cap_digest else preview_digest,
										text_size = "$font.size.xs",
										color = "$text.secondary",
										wrap = true,
									},
								}
							end, { w_full = true })
						)
					end

					-- 3. Permissions & Needs You (only rendered when active items > 0)
					if #attn_items > 0 then
						local ny_cards: { Node } = {
							ui.row {
								w_full = true,
								items = "center",
								gap = "$space.1",
								Status.StatusIcon { kind = "input", size = 13 },
								Text {
									`Permissions & Needs You ({#attn_items})`,
									text_size = "$font.size.xs",
									weight = "$font.weight.medium",
									color = "$warning",
								},
							},
						}
						for _, item in attn_items do
							local item_chat = if type(item.chat_id) == "string" and item.chat_id ~= ""
								then item.chat_id
								else cid
							local detail = trim(item.detail)
							if item.kind == "awaiting_input" then
								local item_role = if type(item.role) == "string" and trim(item.role) ~= ""
									then trim(item.role)
									else "worker"
								local item_title = trim(item.title)
								local body_text = detail
								if body_text == "" and item_title ~= "" and string.lower(item_title) ~= string.lower(item_role) then
									body_text = item_title
								end
								local item_req = item.request
								table.insert(
									ny_cards,
									ui.column {
										w_full = true,
										bg = "$surface.raised",
										border = 1,
										border_color = "$warning",
										rounded = "$radius.md",
										px = "$space.3",
										py = "$space.2",
										gap = "$space.1",
										ui.row {
											w_full = true,
											items = "center",
											gap = "$space.1",
											Status.StatusIcon { kind = "input", size = 13 },
											Text {
												`Permission · {item_role}`,
												grow = 1,
												min_w = 0,
												text_size = "$font.size.sm",
												weight = "$font.weight.medium",
												color = "$text.primary",
												truncate = true,
											},
										},
										if body_text ~= ""
											then Text {
												body_text,
												text_size = "$font.size.xs",
												color = "$text.secondary",
												wrap = true,
											}
											else nil,
										ui.row {
											w_full = true,
											justify = "end",
											gap = "$space.1",
											pt = "$space.1",
											Button {
												size = "xs",
												tone = "primary",
												on_click = function()
													handle_permission_decision(item_chat, "allow", item_req)
												end,
												"Allow",
											},
											Button {
												size = "xs",
												tone = "ghost",
												on_click = function()
													handle_permission_decision(item_chat, "deny", item_req)
												end,
												"Deny",
											},
											Button {
												size = "xs",
												tone = "secondary",
												on_click = function()
													pcall(zeron.open, { session = item_chat })
												end,
												"Open",
											},
										},
									}
								)
							else
								local item_id = item.id
								table.insert(
									ny_cards,
									ui.column {
										w_full = true,
										bg = "$surface.raised",
										border = 1,
										border_color = "$warning",
										rounded = "$radius.md",
										px = "$space.3",
										py = "$space.2",
										gap = "$space.1",
										ui.row {
											w_full = true,
											items = "center",
											gap = "$space.1",
											Status.StatusIcon { kind = "input", size = 13 },
											Text {
												if trim(item.title) ~= "" then trim(item.title) else "Needs decision",
												grow = 1,
												min_w = 0,
												text_size = "$font.size.sm",
												weight = "$font.weight.medium",
												color = "$text.primary",
												wrap = true,
											},
										},
										if detail ~= ""
											then Text {
												detail,
												text_size = "$font.size.xs",
												color = "$text.secondary",
												wrap = true,
											}
											else nil,
										ui.row {
											w_full = true,
											justify = "end",
											gap = "$space.1",
											pt = "$space.1",
											Button {
												size = "xs",
												tone = "secondary",
												on_click = function()
													pcall(zeron.open, { session = item_chat })
												end,
												"Open",
											},
											Button {
												size = "xs",
												tone = "ghost",
												on_click = function()
													client.call("resolve_attention", { captain_id = cid, item_id = item_id })
												end,
												"Resolve",
											},
										},
									}
								)
							end
						end
						table.insert(sections, ui.column { w_full = true, gap = "$space.2", table.unpack(ny_cards) })
					end

					-- 4. Minimalist Quick + Worker Form (only rendered when toggled)
					if show_spawn:peek() then
						local model_control: Node
						if Dropdown then
							model_control = Dropdown {
								value = sp_model :: any,
								items = function(): { any }
									local raw = client.models_for(sp_harness:get())
									local items: { any } = {}
									if type(raw) == "table" then
										for _, opt in raw do
											if type(opt) == "table" then
												local val = if type(opt.value) == "string" then opt.value else ""
												local lbl = if type(opt.label) == "string" and opt.label ~= ""
													then opt.label
													elseif val ~= "" then val
													else "Harness default"
												table.insert(items, {
													value = val,
													label = lbl,
													hint = if type(opt.hint) == "string" and opt.hint ~= "" then opt.hint else nil,
													mark = if type(opt.mark) == "string" and opt.mark ~= "" then opt.mark else nil,
												})
											end
										end
									end
									if #items == 0 then
										table.insert(items, { value = "", label = "Harness default" })
									end
									return items
								end,
								tone = "filled",
								placeholder = "Harness default",
								search = "Search models…",
								width = 240,
								label = "Model",
							}
						else
							model_control = Select {
								value = sp_model,
								options = function()
									return client.models_for(sp_harness:get())
								end,
								size = "sm",
								w_full = true,
							}
						end

						table.insert(
							sections,
							ui.column {
								w_full = true,
								bg = "$surface.raised",
								border = 1,
								border_color = "$border",
								rounded = "$radius.lg",
								p = "$space.3",
								gap = "$space.2",
								ui.row {
									w_full = true,
									items = "center",
									justify = "between",
									Text {
										"Quick Spawn Worker",
										text_size = "$font.size.xs",
										weight = "$font.weight.semibold",
										color = "$text.primary",
									},
									IconButton {
										icon = "close",
										size = "sm",
										tone = "quiet",
										label = "Close",
										on_click = function()
											show_spawn:set(false)
										end,
									},
								},
								field_block(
									"Role",
									Select {
										value = sp_role,
										options = ROLES,
										size = "sm",
										w_full = true,
									}
								),
								field_block(
									"Harness",
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
									}
								),
								field_block("Model", model_control),
								field_block(
									"Task",
									TextField {
										value = sp_task,
										placeholder = "Short task title (optional)",
										size = "sm",
										w_full = true,
									}
								),
								field_block(
									"Prompt",
									TextArea {
										value = sp_prompt,
										placeholder = "Instructions for this worker…",
										rows = 3,
										max_rows = 6,
										size = "sm",
										w_full = true,
									}
								),
								ui.row {
									w_full = true,
									justify = "end",
									gap = "$space.2",
									pt = "$space.1",
									Button {
										size = "xs",
										tone = "ghost",
										on_click = function()
											show_spawn:set(false)
										end,
										"Cancel",
									},
									Button {
										size = "xs",
										tone = "primary",
										busy = spawning,
										on_click = spawn_worker,
										Icon { name = "action-play", size = 12 },
										"Spawn",
									},
								},
							}
						)
					end

					-- 5. Clean, Dense Crew List
					local crew_heading = Text {
						`Crew ({#crew})`,
						text_size = "$font.size.xs",
						weight = "$font.weight.medium",
						color = "$text.tertiary",
					}

					if #crew == 0 then
						table.insert(
							sections,
							ui.column {
								w_full = true,
								gap = "$space.2",
								crew_heading,
								ui.column {
									w_full = true,
									bg = "$surface.raised",
									border = 1,
									border_color = "$border",
									rounded = "$radius.lg",
									p = "$space.4",
									EmptyState {
										size = "sm",
										icon = "bot",
										title = "No crew assigned yet",
										body = "Spawn a worker or attach an existing chat in Captain Deck.",
										action = {
											label = "Worker",
											icon = "plus",
											on_click = function()
												show_spawn:set(true)
											end,
										},
									},
								},
							}
						)
					else
						local crew_rows: { Node } = {}
						for idx, w in crew do
							local w_cid = if type(w.chat_id) == "string" then w.chat_id else ""
							local is_steering = w_cid ~= "" and steer_target:peek() == w_cid
							local w_title = trim(w.task)
							if w_title == "" then
								w_title = if w_cid ~= "" then client.session_title(w_cid) else "Worker"
							end
							local w_role = trim(w.role)
							if w_role == "" then
								w_role = "worker"
							end
							local w_model = short_model(w.harness, w.model)
							local w_agent = if w_model ~= "" then w_model else trim(w.harness)
							local w_status = trim(w.status)
							if w_status == "" then
								w_status = "idle"
							end
							local w_meta = if w_agent ~= "" then `{w_agent} · {w_status}` else w_status

							if idx > 1 then
								table.insert(
									crew_rows,
									ui.div {
										w_full = true,
										h = 1,
										bg = "$border.subtle",
									}
								)
							end

							table.insert(
								crew_rows,
								ui.column {
									w_full = true,
									px = "$space.3",
									py = "$space.2",
									gap = "$space.1",

									-- Row 1: Status + Task / Title | Steer, Open, Detach
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
											Status.StatusIcon { kind = safe_status_kind(w.status), size = 14 },
											Text {
												w_title,
												grow = 1,
												min_w = 0,
												weight = "$font.weight.medium",
												text_size = "$font.size.sm",
												color = "$text.primary",
												truncate = true,
											},
										},
										ui.row {
											shrink = 0,
											items = "center",
											gap = 2,
											IconButton {
												icon = "chat-round-line",
												size = "sm",
												tone = "quiet",
												lit = is_steering,
												label = "Steer or queue message",
												on_click = function()
													if w_cid == "" then
														return
													end
													if steer_target:peek() == w_cid then
														steer_target:set(nil)
													else
														steer_target:set(w_cid)
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
													if w_cid ~= "" then
														pcall(zeron.open, { session = w_cid })
													end
												end,
											},
											IconButton {
												icon = "close-circle",
												size = "sm",
												tone = "danger",
												label = "Detach worker",
												on_click = function()
													if w_cid == "" then
														return
													end
													client.call("detach_worker", { worker_chat = w_cid }):after(function()
														zeron.toast(zeron.s("toast.worker_detached"))
													end, function() end)
												end,
											},
										},
									},

									-- Row 2: Native high-contrast Role pill + 1-line muted meta
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
											items = "center",
											justify = "center",
											Text {
												w_role,
												text_size = "$font.size.xs",
												weight = "$font.weight.medium",
												color = "$zeron.primary.text",
											},
										},
										Text {
											w_meta,
											grow = 1,
											min_w = 0,
											color = "$text.tertiary",
											text_size = "$font.size.xs",
											truncate = true,
										},
									},

									-- Inline Steer / Queue input when selected
									if is_steering
										then ui.column {
											w_full = true,
											pt = "$space.1",
											gap = "$space.1",
											TextField {
												value = steer_text,
												placeholder = zeron.s("inspector.steer_placeholder"),
												size = "sm",
												w_full = true,
												on_commit = function()
													send_steer(w_cid, "steer")
												end,
											},
											ui.row {
												w_full = true,
												justify = "end",
												gap = "$space.1",
												Button {
													size = "xs",
													tone = "ghost",
													on_click = function()
														steer_target:set(nil)
													end,
													"Cancel",
												},
												Button {
													size = "xs",
													tone = "secondary",
													busy = sending,
													on_click = function()
														send_steer(w_cid, "queue")
													end,
													"Queue",
												},
												Button {
													size = "xs",
													tone = "accent",
													busy = sending,
													on_click = function()
														send_steer(w_cid, "steer")
													end,
													"Steer",
												},
											},
										}
										else nil,
								}
							)
						end

						table.insert(
							sections,
							ui.column {
								w_full = true,
								gap = "$space.2",
								crew_heading,
								ui.column {
									w_full = true,
									bg = "$surface.raised",
									border = 1,
									border_color = "$border",
									rounded = "$radius.lg",
									overflow = "hidden",
									table.unpack(crew_rows),
								},
							}
						)
					end

					-- 6. Quick Action Footer
					table.insert(
						sections,
						ui.row {
							w_full = true,
							justify = "center",
							pt = "$space.1",
							Button {
								size = "xs",
								tone = "ghost",
								tooltip = "Open Captain Deck (/captain)",
								on_click = open_deck,
								Icon { name = "users-group-rounded", size = 12 },
								"Open Deck",
							},
						}
					)

					return ui.column { w_full = true, gap = "$space.3", table.unpack(sections) }
				end, { w_full = true }),
			},
		}
	end)
end

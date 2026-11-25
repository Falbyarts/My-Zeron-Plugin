--!strict
-- Shared window-side client for Captain Deck.
--
-- Subscribes to `service.luau` state emissions, loads harness/model catalogs
-- on demand, exposes fast reactive lookup helpers for sidebar/header badges,
-- and provides clean RPC wrappers with toast feedback.

return function(zeron: any): any
	local M = {}

	local state = ui.state("captain-deck.state.v1", {
		rev = 0,
		captains = {},
		workers = {},
		events = {},
		prefs = {},
	} :: any)
	local harnesses = ui.state("captain-deck.harnesses.v1", {} :: { any })
	local loading = ui.state("captain-deck.loading.v1", false)
	local service_err = ui.state("captain-deck.err.v1", nil :: string?)
	local focus_chat = ui.state("captain-deck.focus.v1", nil :: string?)
	local deck_open = ui.state("captain_deck.open", false)
	local deck_dirty = ui.state("captain_deck.dirty", false)
	local strip_dismissed = ui.state("captain_deck.strip_dismissed", {} :: { [string]: boolean })
	local strip_height = ui.state("captain_deck.strip_h", 0)

	M.state = state
	M.harnesses = harnesses
	M.loading = loading
	M.service_err = service_err
	M.focus_chat = focus_chat
	M.deck_open = deck_open
	M.deck_dirty = deck_dirty
	M.strip_dismissed = strip_dismissed
	M.strip_height = strip_height

	function M.set_strip_height(h: number)
		local raw = if type(h) == "number" and h == h then h else 0
		local clamped = math.clamp(raw, 0, 320)
		local next_h = math.floor(clamped + 0.5)
		local cur = tonumber(strip_height:peek()) or 0
		if math.abs(cur - next_h) >= 1 then
			strip_height:set(next_h)
		end
	end

	function M.open_deck()
		deck_open:set(true)
	end

	function M.close_deck()
		deck_open:set(false)
	end

	function M.toggle_deck()
		deck_open:set(not (deck_open:peek() == true))
	end

	function M.set_deck_dirty(dirty: boolean)
		local next_val = dirty == true
		if (deck_dirty:peek() == true) ~= next_val then
			deck_dirty:set(next_val)
		end
	end

	function M.is_deck_dirty(): boolean
		return deck_dirty:peek() == true
	end

	function M.is_strip_dismissed(sid: string?): boolean
		if type(sid) ~= "string" or sid == "" then
			return false
		end
		local map = strip_dismissed:get()
		return type(map) == "table" and map[sid] == true
	end

	function M.dismiss_strip(sid: string?)
		if type(sid) ~= "string" or sid == "" then
			return
		end
		local cur = strip_dismissed:peek()
		local next_map: { [string]: boolean } = {}
		if type(cur) == "table" then
			for k, v in cur do
				if v then
					next_map[k] = true
				end
			end
		end
		next_map[sid] = true
		strip_dismissed:set(next_map)
	end

	function M.show_strip(sid: string?)
		if type(sid) ~= "string" or sid == "" then
			return
		end
		local cur = strip_dismissed:peek()
		if type(cur) ~= "table" or not cur[sid] then
			return
		end
		local next_map: { [string]: boolean } = {}
		for k, v in cur do
			if v and k ~= sid then
				next_map[k] = true
			end
		end
		strip_dismissed:set(next_map)
	end

	local svc = zeron.service()
	local pruning = false

	local function trim(s: any): string
		if type(s) ~= "string" then
			return ""
		end
		return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
	end

	local function non_empty(s: any): string?
		local t = trim(s)
		return if t ~= "" then t else nil
	end

	function M.sanitize_harness(raw: any): string
		local s = trim(raw)
		if s == "" then
			return ""
		end
		local comma = string.find(s, ",", 1, true)
		if comma then
			s = trim(string.sub(s, 1, comma - 1))
		end
		s = string.lower(s)
		if s == "" then
			return ""
		end
		return s
	end

	function M.short_model(harness: string?, model: string?): string
		local m = trim(model)
		if m == "" then
			return ""
		end
		local h = trim(harness)
		if h ~= "" then
			local prefix = string.lower(h) .. "/"
			if string.sub(string.lower(m), 1, #prefix) == prefix then
				return string.sub(m, #prefix + 1)
			end
		end
		return m
	end

	function M.default_target(): { device: string?, fallback_project: string? }
		local device: string? = nil
		local fallback_project: string? = nil

		-- Cek zeron.context("session") (di dalam pcall)
		pcall(function()
			local s = zeron.context("session")
			if type(s) == "table" then
				device = non_empty(s.device)
				fallback_project = non_empty(s.project)
			end
		end)

		-- Jika belum dapat, iterasi zeron.sessions() (di dalam pcall) untuk mencari device dan project dari sesi terbaru (updated terbesar)
		if not device or not fallback_project then
			pcall(function()
				local sessions = zeron.sessions()
				if type(sessions) == "table" then
					local best_updated = -1
					local best_dev: string? = nil
					local best_proj: string? = nil
					for _, v in sessions do
						if type(v) == "table" then
							local up = tonumber(v.updated or v.updated_at or v.created or v.created_at) or 0
							local d = non_empty(v.device)
							local p = non_empty(v.project)
							if (d or p) and up >= best_updated then
								best_updated = up
								if d then
									best_dev = d
								end
								if p then
									best_proj = p
								end
							end
						end
					end
					if not device and best_dev then
						device = best_dev
					end
					if not fallback_project and best_proj then
						fallback_project = best_proj
					end
				end
			end)
		end

		-- Jika belum dapat, iterasi zeron.projects() (di dalam pcall) untuk mengambil id project pertama sebagai fallback_project dan p.device sebagai device
		if not fallback_project or not device then
			pcall(function()
				local projects = zeron.projects()
				if type(projects) == "table" then
					for id, p in projects do
						local pid = if type(p) == "table" and non_empty(p.id) then non_empty(p.id) else non_empty(id)
						if not fallback_project and pid then
							fallback_project = pid
						end
						if not device and type(p) == "table" and non_empty(p.device) then
							device = non_empty(p.device)
						end
						if fallback_project and device then
							break
						end
					end
				end
			end)
		end

		-- Jika device masih kosong, cek zeron.devices() (di dalam pcall, ingat zeron.devices() mengembalikan shared state atau tabel, cek d.get bila ada) untuk mengambil id device pertama
		if not device then
			pcall(function()
				local raw = zeron.devices()
				local dev_list: any = raw
				if type(raw) == "table" then
					if type(raw.get) == "function" then
						dev_list = raw:get()
					elseif type(raw.peek) == "function" then
						dev_list = raw:peek()
					end
				end
				if type(dev_list) == "table" then
					for k, d in dev_list do
						local did = if type(d) == "table" then (non_empty(d.id) or non_empty(d.device_id) or non_empty(d.device)) elseif type(d) == "string" then non_empty(d) else non_empty(k)
						if did then
							device = did
							break
						end
					end
				end
			end)
		end

		return { device = device, fallback_project = fallback_project }
	end

	function M.session_exists(chat_id: string): boolean
		if type(chat_id) ~= "string" or chat_id == "" then
			return false
		end
		if zeron.context_of("session", chat_id) ~= nil then
			return true
		end
		local ok, sessions = pcall(zeron.sessions)
		if ok and type(sessions) == "table" then
			if sessions[chat_id] ~= nil then
				return true
			end
			for k, v in sessions do
				if k == chat_id or (type(v) == "table" and v.id == chat_id) then
					return true
				end
			end
		end
		return false
	end

	function M.prune_ghost_chats(silent: boolean?)
		if pruning then
			return
		end
		local ok, sessions = pcall(zeron.sessions)
		if not ok or type(sessions) ~= "table" then
			return
		end
		local valid_ids: { [string]: boolean } = {}
		local session_count = 0
		for k, v in sessions do
			local sid = if type(v) == "table" and type(v.id) == "string" then v.id elseif type(k) == "string" then k else nil
			if sid and sid ~= "" then
				valid_ids[sid] = true
				session_count += 1
			end
		end
		if session_count == 0 then
			return
		end

		local s = state:peek()
		if type(s) ~= "table" then
			return
		end
		local now = os.time()
		local has_ghost = false
		for cid, cap in (s.captains or {}) do
			local age = now - (tonumber(cap.created_at) or 0)
			if not valid_ids[cid] and age >= 15 then
				has_ghost = true
				break
			end
		end
		if not has_ghost then
			for wid, w in (s.workers or {}) do
				local age = now - (tonumber(w.created_at) or 0)
				if (not valid_ids[wid] and age >= 15) or (w.captain_id and not valid_ids[w.captain_id] and not (s.captains and s.captains[w.captain_id])) then
					has_ghost = true
					break
				end
			end
		end

		if not has_ghost then
			return
		end

		pruning = true
		local p = svc:call("prune_deleted", { valid_ids = valid_ids })
		if p and type(p.after) == "function" then
			p:after(function(res: any)
				pruning = false
				if not silent and type(res) == "table" then
					local rc = tonumber(res.removed_captains) or 0
					local rw = tonumber(res.removed_workers) or 0
					if rc > 0 or rw > 0 then
						zeron.toast(`Cleaned up {rc + rw} deleted chat(s)`)
					end
				end
			end, function()
				pruning = false
			end)
		else
			pruning = false
		end
	end

	local function apply_state(next_state: any)
		if type(next_state) == "table" then
			state:set(next_state)
			service_err:set(nil)
			ui.after(120, function()
				M.prune_ghost_chats(true)
			end)
		end
	end

	svc:on("state", function(next_state: any)
		apply_state(next_state)
	end)

	function M.refresh()
		loading:set(true)
		M.prune_ghost_chats(true)
		local p = svc:call("get_state")
		if p and type(p.after) == "function" then
			p:after(function(s: any)
				loading:set(false)
				apply_state(s)
			end, function(err: any)
				loading:set(false)
				service_err:set(tostring(err))
			end)
		else
			loading:set(false)
		end
	end

	function M.sync_settings()
		local ok, s = pcall(zeron.settings)
		if not ok or type(s) ~= "table" then
			return
		end
		local p = svc:call("sync_settings", {
			default_auto_report = s.default_auto_report ~= false,
			notify_on_attention = s.notify_on_attention ~= false,
			default_reviewer_harness = M.sanitize_harness(s.default_reviewer_harness),
		})
		if p and type(p.after) == "function" then
			p:after(nil, function() end)
		end
	end

	function M.probe_harnesses(extra: { string }?)
		local p = svc:call("probe_harnesses", { extra = extra or {} })
		if p and type(p.after) == "function" then
			p:after(function(res: any)
				if type(res) == "table" and type(res.harnesses) == "table" then
					harnesses:set(res.harnesses)
				end
			end, function() end)
		end
	end

	function M.clear_all(include_events: boolean?): any
		return M.call("clear_all", { include_events = include_events == true })
	end

	function M.call(method: string, args: any?, on_ok: ((any) -> ())?, on_err: ((any) -> ())?): any
		local ok_handlers: { (any) -> () } = {}
		local err_handlers: { (any) -> () } = {}
		if type(on_ok) == "function" then
			table.insert(ok_handlers, on_ok)
		end
		if type(on_err) == "function" then
			table.insert(err_handlers, on_err)
		end
		local settled: string? = nil
		local settled_val: any = nil

		local chain: any = {}
		function chain.after(_self: any, fn_ok: ((any) -> ())?, fn_err: ((any) -> ())?): any
			if settled == "ok" then
				if type(fn_ok) == "function" then
					pcall(fn_ok, settled_val)
				end
			elseif settled == "err" then
				if type(fn_err) == "function" then
					pcall(fn_err, settled_val)
				end
			else
				if type(fn_ok) == "function" then
					table.insert(ok_handlers, fn_ok)
				end
				if type(fn_err) == "function" then
					table.insert(err_handlers, fn_err)
				end
			end
			return chain
		end

		local call_args = if type(args) == "table" then args else {}
		if (method == "create_captain" or method == "spawn_worker" or method == "launch_workflow") and type(call_args) == "table" then
			local target = M.default_target()
			if not non_empty(call_args.device) and target.device then
				call_args.device = target.device
			end
			if not non_empty(call_args.fallback_project) and target.fallback_project then
				call_args.fallback_project = target.fallback_project
			end
		end

		local p = svc:call(method, call_args, { timeout = 120 })
		if p and type(p.after) == "function" then
			p:after(function(res: any)
				settled = "ok"
				settled_val = res
				service_err:set(nil)
				M.refresh()
				for _, fn in ok_handlers do
					local ok, why = pcall(fn, res)
					if not ok then
						print(`captain-deck: callback error on {method}: {why}`)
					end
				end
			end, function(err: any)
				settled = "err"
				settled_val = err
				local reason = zeron.reason(err)
				zeron.toast(`Captain Deck ({reason}): {tostring(err)}`)
				for _, fn in err_handlers do
					pcall(fn, err)
				end
			end)
		end
		return chain
	end

	function M.answer_input(chat_id: string, decision: string?, answers: any?, request: string?): any
		return M.call("answer_input", {
			chat_id = chat_id,
			decision = decision,
			answers = answers,
			request = request,
		})
	end

	-- Fast O(1) lookup helpers for sidebar/header badges.
	function M.captain_of(chat_id: string): any?
		local s = state:get()
		return if s and s.captains then s.captains[chat_id] else nil
	end

	function M.captains_list(): { any }
		local s = state:get()
		local out: { any } = {}
		if not s or type(s.captains) ~= "table" then
			return out
		end
		for _, cap in s.captains do
			if type(cap) == "table" then
				table.insert(out, cap)
			end
		end
		table.sort(out, function(a: any, b: any): boolean
			return (tonumber(a.updated_at) or tonumber(a.created_at) or 0)
				> (tonumber(b.updated_at) or tonumber(b.created_at) or 0)
		end)
		return out
	end

	function M.worker_of(chat_id: string): any?
		local s = state:get()
		return if s and s.workers then s.workers[chat_id] else nil
	end

	function M.crew_of(captain_id: string): { any }
		local s = state:get()
		local out: { any } = {}
		if not s or not s.workers then
			return out
		end
		for _, w in s.workers do
			if w.captain_id == captain_id then
				table.insert(out, w)
			end
		end
		table.sort(out, function(a: any, b: any): boolean
			return (a.created_at or 0) < (b.created_at or 0)
		end)
		return out
	end

	function M.crew_summary(captain_id: string): {
		total: number,
		running: number,
		completed: number,
		done: number,
		awaiting: number,
		errored: number,
		attention: number,
	}
		local s = state:get()
		local total, running, completed, awaiting, errored, needs_you_count = 0, 0, 0, 0, 0, 0
		if s and type(s.workers) == "table" then
			for _, w in s.workers do
				if w.captain_id == captain_id then
					total += 1
					if w.status == "running" then
						running += 1
					elseif w.status == "awaiting_input" then
						awaiting += 1
					elseif w.status == "errored" or w.status == "limited" then
						errored += 1
					elseif w.status == "completed" then
						completed += 1
					end
				end
			end
		end
		local cap = if s and type(s.captains) == "table" then s.captains[captain_id] else nil
		if cap then
			if cap.status == "awaiting_input" then
				awaiting += 1
			elseif cap.status == "errored" or cap.status == "limited" then
				errored += 1
			end
			if type(cap.needs_you) == "table" then
				for _, item in cap.needs_you do
					if type(item) == "table" and not item.resolved then
						needs_you_count += 1
					end
				end
			end
		end
		local attention = needs_you_count + awaiting + errored
		return {
			total = total,
			running = running,
			completed = completed,
			done = completed,
			awaiting = awaiting,
			errored = errored,
			attention = attention,
		}
	end

	function M.attention_items(captain_id: string?): { any }
		if type(captain_id) ~= "string" or captain_id == "" then
			return M.all_attention_items()
		end
		local out: { any } = {}
		local cap = M.captain_of(captain_id)
		if not cap then
			return out
		end
		local cap_name = non_empty(cap.name) or "Captain"
		local crew = M.crew_of(captain_id)

		-- 1. Captain awaiting_input
		if cap.status == "awaiting_input" then
			local pi = if type(cap.pending_input) == "table" then cap.pending_input else nil
			local pi_title = if pi then non_empty(pi.title) else nil
			local pi_detail = if pi then non_empty(pi.detail) else nil
			local cap_mission = non_empty(cap.mission)
			table.insert(out, {
				kind = "awaiting_input",
				id = "input:" .. captain_id,
				captain_id = captain_id,
				captain_name = cap_name,
				chat_id = captain_id,
				role = "Captain",
				harness = cap.harness,
				status = "awaiting_input",
				title = pi_title or "Permission / input needed",
				detail = pi_detail or cap_mission or "Captain is waiting for your approval or reply.",
				request = if pi then pi.request else nil,
				at = (if pi then tonumber(pi.at) else nil) or tonumber(cap.updated_at) or 0,
			})
		end

		-- 2. Workers awaiting_input
		for _, w in crew do
			if w.status == "awaiting_input" then
				local pi = if type(w.pending_input) == "table" then w.pending_input else nil
				local pi_title = if pi then non_empty(pi.title) else nil
				local pi_detail = if pi then non_empty(pi.detail) else nil
				local w_role = non_empty(w.role) or "worker"
				local w_task = non_empty(w.task)
				table.insert(out, {
					kind = "awaiting_input",
					id = "input:" .. w.chat_id,
					captain_id = captain_id,
					captain_name = cap_name,
					chat_id = w.chat_id,
					role = w_role,
					harness = w.harness,
					status = "awaiting_input",
					title = pi_title or ("Permission / input · " .. w_role),
					detail = pi_detail or w_task or "Worker is waiting for your approval or reply.",
					request = if pi then pi.request else nil,
					at = (if pi then tonumber(pi.at) else nil) or tonumber(w.updated_at) or 0,
				})
			end
		end

		-- 3. Unresolved needs_you items
		if type(cap.needs_you) == "table" then
			for _, item in cap.needs_you do
				if type(item) == "table" and not item.resolved then
					local w_chat = if type(item.worker_chat) == "string" and item.worker_chat ~= ""
						then item.worker_chat
						else nil
					local linked_worker = if w_chat then M.worker_of(w_chat) else nil
					local item_role = if linked_worker then (non_empty(linked_worker.role) or "worker") else "Captain"
					table.insert(out, {
						kind = "needs_you",
						id = item.id,
						item_id = item.id,
						captain_id = captain_id,
						captain_name = cap_name,
						chat_id = w_chat or captain_id,
						role = item_role,
						harness = if linked_worker then linked_worker.harness else cap.harness,
						status = "awaiting_input",
						title = non_empty(item.title) or "Needs your input",
						detail = trim(item.detail or ""),
						at = tonumber(item.created_at) or 0,
					})
				end
			end
		end

		return out
	end

	function M.all_attention_items(): { any }
		local out: { any } = {}
		for _, cap in M.captains_list() do
			if type(cap) == "table" and type(cap.chat_id) == "string" and cap.chat_id ~= "" then
				for _, item in M.attention_items(cap.chat_id) do
					table.insert(out, item)
				end
			end
		end
		return out
	end

	function M.harness_options(include_auto: boolean?): { any }
		local opts: { any } = {}
		if include_auto then
			table.insert(opts, { value = "", label = "Auto (Zeron default)" })
		end
		local list = harnesses:get()
		if #list == 0 then
			local fallback = {
				{ id = "antigravity", label = "Antigravity" },
				{ id = "claude-code", label = "Claude Code" },
				{ id = "codex", label = "Codex" },
				{ id = "opencode", label = "OpenCode" },
				{ id = "pi", label = "Pi" },
				{ id = "hermes", label = "Hermes" },
				{ id = "cursor", label = "Cursor" },
			}
			for _, h in fallback do
				table.insert(opts, { value = h.id, label = h.label })
			end
			return opts
		end
		-- Installed/available harnesses with models first, then others.
		local ready: { any } = {}
		local other: { any } = {}
		for _, h in list do
			local model_count = if type(h.models) == "table" then #h.models else 0
			if h.has_models then
				table.insert(ready, {
					value = h.id,
					label = h.label,
					group = "Ready on this device",
					hint = if model_count > 0 then `{model_count} models` else nil,
				})
			else
				table.insert(other, {
					value = h.id,
					label = h.label,
					group = "Other harnesses",
				})
			end
		end
		for _, r in ready do
			table.insert(opts, r)
		end
		for _, o in other do
			table.insert(opts, o)
		end
		return opts
	end

	function M.models_for(harness_id: string?): { any }
		local opts: { any } = { { value = "", label = "Harness default" } }
		if not harness_id or harness_id == "" then
			return opts
		end
		for _, h in harnesses:get() do
			if h.id == harness_id then
				for _, m in (h.models or {}) do
					local efforts = if type(m.efforts) == "table" then m.efforts else nil
					local hint = if type(m.hint) == "string" and m.hint ~= ""
						then m.hint
						elseif efforts and #efforts > 0 then table.concat(efforts, "/")
						else nil
					table.insert(opts, {
						value = m.id,
						label = m.label or m.id,
						hint = hint,
						mark = if type(m.mark) == "string" and m.mark ~= "" then m.mark else nil,
					})
				end
				break
			end
		end
		return opts
	end

	function M.project_options(): { any }
		local opts: { any } = { { value = "", label = "No specific project" } }
		local list: { { id: string, name: string } } = {}
		local ok, projects = pcall(zeron.projects)
		if ok and type(projects) == "table" then
			for id, p in projects do
				local name = if type(p) == "table" and type(p.name) == "string" then p.name else tostring(id)
				table.insert(list, { id = tostring(id), name = name })
			end
		end
		table.sort(list, function(a, b)
			return string.lower(a.name) < string.lower(b.name)
		end)
		for _, p in list do
			table.insert(opts, { value = p.id, label = p.name })
		end
		return opts
	end

	function M.session_title(chat_id: string): string
		local s = zeron.context_of("session", chat_id)
		if s and type(s.title) == "string" and s.title ~= "" then
			return s.title
		end
		return string.sub(chat_id, 1, 8)
	end

	function M.status_kind(status: string?): string
		if status == "running" then
			return "working"
		elseif status == "awaiting_input" then
			return "input"
		elseif status == "completed" then
			return "done"
		elseif status == "errored" then
			return "failed"
		elseif status == "limited" then
			return "limited"
		end
		return "waiting"
	end

	function M.status_tone(status: string?): "neutral" | "accent" | "info" | "success" | "warning" | "danger"
		if status == "running" then
			return "accent"
		elseif status == "awaiting_input" then
			return "warning"
		elseif status == "completed" then
			return "success"
		elseif status == "errored" or status == "limited" then
			return "danger"
		end
		return "neutral"
	end

	function M.open_inspector(panel: any?, captain_id: string)
		if type(captain_id) ~= "string" or captain_id == "" then
			return
		end
		focus_chat:set(captain_id)
		local cap = M.captain_of(captain_id)
		local title = if cap and type(cap.name) == "string" and cap.name ~= "" then `Crew · {cap.name}` else "Crew Inspector"
		local tab_spec = {
			kind = "captain-inspector",
			title = title,
			icon = "users-group-rounded",
			data = { key = `captain:{captain_id}`, captain_id = captain_id },
		}
		if type(panel) == "table" and type(panel.open_tab) == "function" then
			local ok = pcall(panel.open_tab, tab_spec)
			if ok then
				return
			end
		end
		ui.after(80, function()
			pcall(function()
				local _ps = ui.shared("zeron.page_session", nil)
				local current_panel = zeron.context("panel")
				if type(current_panel) == "table" and type(current_panel.open_tab) == "function" then
					current_panel.open_tab(tab_spec)
				end
			end)
		end)
	end

	-- Sync settings whenever changed, and initial bootstrap.
	zeron.on_setting(function()
		M.sync_settings()
	end)
	M.refresh()
	M.sync_settings()
	M.probe_harnesses(nil)

	return M
end

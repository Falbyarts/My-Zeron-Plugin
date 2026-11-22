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

	M.state = state
	M.harnesses = harnesses
	M.loading = loading
	M.service_err = service_err
	M.focus_chat = focus_chat

	local svc = zeron.service()

	local function apply_state(next_state: any)
		if type(next_state) == "table" then
			state:set(next_state)
			service_err:set(nil)
		end
	end

	svc:on("state", function(next_state: any)
		apply_state(next_state)
	end)

	function M.refresh()
		loading:set(true)
		svc:call("get_state"):after(function(s: any)
			loading:set(false)
			apply_state(s)
		end, function(err: any)
			loading:set(false)
			service_err:set(tostring(err))
		end)
	end

	function M.sync_settings()
		local s = zeron.settings()
		svc:call("sync_settings", {
			default_auto_report = s.default_auto_report ~= false,
			notify_on_attention = s.notify_on_attention ~= false,
			default_reviewer_harness = s.default_reviewer_harness or "",
		}):after(nil, function() end)
	end

	function M.probe_harnesses(extra: { string }?)
		svc:call("probe_harnesses", { extra = extra or {} }):after(function(res: any)
			if type(res) == "table" and type(res.harnesses) == "table" then
				harnesses:set(res.harnesses)
			end
		end, function() end)
	end

	function M.call(method: string, args: any?): any
		return svc:call(method, args or {}, { timeout = 45 }):after(function(res: any)
			service_err:set(nil)
			return res
		end, function(err: any)
			local reason = zeron.reason(err)
			zeron.toast(`Captain Deck ({reason}): {tostring(err)}`)
			error(err, 0)
		end)
	end

	-- Fast O(1) lookup helpers for sidebar/header badges.
	function M.captain_of(chat_id: string): any?
		local s = state:get()
		return if s and s.captains then s.captains[chat_id] else nil
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

	function M.crew_summary(captain_id: string): { total: number, running: number, attention: number, done: number }
		local s = state:get()
		local total, running, attention, done = 0, 0, 0, 0
		if s and s.workers then
			for _, w in s.workers do
				if w.captain_id == captain_id then
					total += 1
					if w.status == "running" then
						running += 1
					elseif w.status == "awaiting_input" or w.status == "errored" or w.status == "limited" then
						attention += 1
					elseif w.status == "completed" then
						done += 1
					end
				end
			end
		end
		local cap = if s and s.captains then s.captains[captain_id] else nil
		if cap and type(cap.needs_you) == "table" then
			for _, item in cap.needs_you do
				if not item.resolved then
					attention += 1
				end
			end
		end
		return { total = total, running = running, attention = attention, done = done }
	end

	function M.attention_items(): { any }
		local s = state:get()
		local out: { any } = {}
		if not s then
			return out
		end
		for _, w in (s.workers or {}) do
			if w.status == "awaiting_input" or w.status == "errored" or w.status == "limited" then
				local cap = (s.captains or {})[w.captain_id]
				table.insert(out, {
					kind = "worker",
					id = `w:{w.chat_id}`,
					chat_id = w.chat_id,
					captain_id = w.captain_id,
					captain_name = if cap then cap.name else "Captain",
					role = w.role,
					harness = w.harness,
					status = w.status,
					title = w.task or w.role,
					detail = w.last_error or "",
					at = w.updated_at or 0,
				})
			end
		end
		for cid, cap in (s.captains or {}) do
			if cap.status == "awaiting_input" or cap.status == "errored" or cap.status == "limited" then
				table.insert(out, {
					kind = "captain_status",
					id = `cs:{cid}`,
					chat_id = cid,
					captain_id = cid,
					captain_name = cap.name,
					role = "captain",
					harness = cap.harness,
					status = cap.status,
					title = `Captain {cap.name}`,
					detail = cap.mission or "",
					at = cap.updated_at or 0,
				})
			end
			if type(cap.needs_you) == "table" then
				for _, item in cap.needs_you do
					if not item.resolved then
						table.insert(out, {
							kind = "escalation",
							id = item.id,
							item_id = item.id,
							chat_id = item.worker_chat or cid,
							captain_id = cid,
							captain_name = cap.name,
							role = "captain",
							harness = cap.harness,
							status = "awaiting_input",
							title = item.title,
							detail = item.detail or "",
							at = item.created_at or 0,
						})
					end
				end
			end
		end
		table.sort(out, function(a: any, b: any): boolean
			return (a.at or 0) > (b.at or 0)
		end)
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
			if h.has_models then
				table.insert(ready, { value = h.id, label = h.label, group = "Ready on this device" })
			else
				table.insert(other, { value = h.id, label = h.label, group = "Other harnesses" })
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
					table.insert(opts, { value = m.id, label = m.label or m.id })
				end
				break
			end
		end
		return opts
	end

	function M.project_options(): { any }
		local opts: { any } = { { value = "", label = "No specific project" } }
		local list: { { id: string, name: string } } = {}
		for id, p in zeron.projects() do
			table.insert(list, { id = id, name = p.name or id })
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
		local cap = M.captain_of(captain_id)
		local title = if cap and cap.name ~= "" then `Crew · {cap.name}` else "Crew Inspector"
		if panel and panel.open_tab then
			panel.open_tab {
				kind = "captain-inspector",
				title = title,
				icon = "users-group-rounded",
				data = { key = `captain:{captain_id}`, captain_id = captain_id },
			}
		end
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

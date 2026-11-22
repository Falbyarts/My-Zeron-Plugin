--!strict
-- Captain Deck headless orchestration service.
--
-- Runs in Zeron's engine even with no window open ("service"). Keeps the
-- single source of truth for Captains, Crew workers, automated handoffs,
-- live turn events, Attention Digest ("Needs You"), schedules, and the
-- harness-agnostic agent tools (`zeron.tool`).

local zeron = require("./zeron")("captain-deck")

local MAX_EVENTS = 40
local MAX_REPLY = 1400
local MAX_NEEDS_YOU = 24
local KNOWN_HARNESSES = {
	{ id = "antigravity", label = "Antigravity" },
	{ id = "claude-code", label = "Claude Code" },
	{ id = "codex", label = "Codex" },
	{ id = "opencode", label = "OpenCode" },
	{ id = "pi", label = "Pi" },
	{ id = "hermes", label = "Hermes" },
	{ id = "cursor", label = "Cursor" },
	{ id = "grok", label = "Grok" },
	{ id = "devin", label = "Devin" },
	{ id = "muse", label = "Muse Code" },
	{ id = "fx", label = "fx" },
}

local store = zeron.store("deck-v1", {
	rev = 1,
	captains = {},
	workers = {},
	events = {},
	prefs = {
		default_auto_report = true,
		notify_on_attention = true,
		default_reviewer_harness = "",
	},
} :: any)

local seq = 0

local function next_id(prefix: string): string
	seq += 1
	return `{prefix}_{os.time()}_{seq}`
end

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

local function clip(s: any, max_len: number): string
	if type(s) ~= "string" then
		return ""
	end
	local t = trim(s)
	if #t <= max_len then
		return t
	end
	return string.sub(t, 1, max_len - 1) .. "…"
end

local function load_state(): any
	local s = store:get()
	if type(s) ~= "table" then
		s = {}
	end
	s.rev = tonumber(s.rev) or 1
	if type(s.captains) ~= "table" then
		s.captains = {}
	end
	if type(s.workers) ~= "table" then
		s.workers = {}
	end
	if type(s.events) ~= "table" then
		s.events = {}
	end
	if type(s.prefs) ~= "table" then
		s.prefs = {
			default_auto_report = true,
			notify_on_attention = true,
			default_reviewer_harness = "",
		}
	end
	return s
end

local state: any = load_state()

local function save_and_emit()
	state.rev = (tonumber(state.rev) or 0) + 1
	store:set(state)
	pcall(function()
		zeron.emit("state", state)
	end)
end

local function push_event(kind: string, summary: string, captain_id: string?, chat_id: string?)
	table.insert(state.events, 1, {
		id = next_id("ev"),
		at = os.time(),
		kind = kind,
		captain_id = captain_id,
		chat_id = chat_id,
		summary = clip(summary, 220),
	})
	while #state.events > MAX_EVENTS do
		table.remove(state.events)
	end
end

local function try_notify(title: string, body: string, session: string?)
	if state.prefs and state.prefs.notify_on_attention == false then
		return
	end
	pcall(function()
		zeron.notify({
			title = clip(title, 80),
			body = clip(body, 220),
			session = session,
		}):await()
	end)
end

local function read_chat_meta(chat_id: string): (string?, string?)
	local ok, info = pcall(function()
		return zeron.chat_model(chat_id):await()
	end)
	if ok and type(info) == "table" then
		return non_empty(info.provider), non_empty(info.model)
	end
	return nil, nil
end

local function build_worker_prompt(captain: any?, role: string, task: string, prompt: string): string
	local parts: { string } = {}
	if captain and non_empty(captain.rules) then
		table.insert(parts, `[Captain Rules — {captain.name or "Captain"}]\n{trim(captain.rules)}`)
	end
	if non_empty(role) or non_empty(task) then
		local head = `[Assigned Role: {if non_empty(role) then role else "worker"}`
		if non_empty(task) then
			head ..= ` | Task: {task}`
		end
		head ..= "]"
		table.insert(parts, head)
	end
	table.insert(parts, trim(prompt))
	return table.concat(parts, "\n\n")
end

local function ensure_captain(chat_id: string, opts: any?): any
	local existing = state.captains[chat_id]
	local o = if type(opts) == "table" then opts else {}
	local now = os.time()
	if existing then
		if non_empty(o.name) then
			existing.name = trim(o.name)
		end
		if o.mission ~= nil then
			existing.mission = trim(o.mission)
		end
		if o.rules ~= nil then
			existing.rules = trim(o.rules)
		end
		if o.digest ~= nil then
			existing.digest = trim(o.digest)
		end
		if type(o.auto_report) == "boolean" then
			existing.auto_report = o.auto_report
		end
		if type(o.notify_attention) == "boolean" then
			existing.notify_attention = o.notify_attention
		end
		if o.schedule_mins ~= nil then
			local m = tonumber(o.schedule_mins) or 0
			existing.schedule_mins = if m > 0 then math.max(5, math.floor(m)) else 0
		end
		if o.schedule_prompt ~= nil then
			existing.schedule_prompt = trim(o.schedule_prompt)
		end
		existing.updated_at = now
		return existing
	end

	local harness, model = non_empty(o.harness), non_empty(o.model)
	if not harness then
		local p, m = read_chat_meta(chat_id)
		harness = harness or p
		model = model or m
	end
	local default_auto = if state.prefs and state.prefs.default_auto_report == false then false else true
	local cap = {
		chat_id = chat_id,
		name = non_empty(o.name) or "Captain",
		mission = trim(o.mission or ""),
		rules = trim(o.rules or ""),
		digest = trim(o.digest or ""),
		harness = harness,
		model = model,
		status = "idle",
		auto_report = if type(o.auto_report) == "boolean" then o.auto_report else default_auto,
		notify_attention = if type(o.notify_attention) == "boolean" then o.notify_attention else true,
		schedule_mins = 0,
		schedule_prompt = "",
		last_wake_at = 0,
		needs_you = {},
		created_at = now,
		updated_at = now,
	}
	state.captains[chat_id] = cap
	-- If this chat was previously listed as a worker, promote it cleanly.
	state.workers[chat_id] = nil
	push_event("captain_promoted", `Promoted "{cap.name}" to Captain`, chat_id, chat_id)
	return cap
end

local function add_needs_you_item(captain_id: string, title: string, detail: string?, worker_chat: string?): any
	local cap = state.captains[captain_id]
	if not cap then
		return nil
	end
	if type(cap.needs_you) ~= "table" then
		cap.needs_you = {}
	end
	local item = {
		id = next_id("ny"),
		title = clip(title, 120),
		detail = clip(detail or "", 400),
		worker_chat = non_empty(worker_chat),
		created_at = os.time(),
		resolved = false,
	}
	table.insert(cap.needs_you, 1, item)
	while #cap.needs_you > MAX_NEEDS_YOU do
		table.remove(cap.needs_you)
	end
	cap.updated_at = os.time()
	push_event("needs_you", `Needs You ({cap.name}): {item.title}`, captain_id, worker_chat or captain_id)
	if cap.notify_attention ~= false then
		try_notify(`Needs You · {cap.name}`, if item.detail ~= "" then `{item.title} — {item.detail}` else item.title, worker_chat or captain_id)
	end
	return item
end

local function spawn_worker_internal(args: any): any
	local captain_id = non_empty(args.captain_id)
	if not captain_id then
		error("captain_id is required", 0)
	end
	local cap = ensure_captain(captain_id, nil)
	local raw_prompt = trim(args.prompt)
	if raw_prompt == "" then
		error("prompt is required", 0)
	end
	local role = non_empty(args.role) or "worker"
	local task = non_empty(args.task) or clip(raw_prompt, 72)
	local full_prompt = build_worker_prompt(cap, role, task, raw_prompt)

	local res = zeron.new_chat({
		prompt = full_prompt,
		device = non_empty(args.device),
		project = non_empty(args.project),
		harness = non_empty(args.harness),
		model = non_empty(args.model),
		effort = non_empty(args.effort),
		cwd = non_empty(args.cwd),
	}):await()

	local chat_id = if type(res) == "table" then non_empty(res.chat) else nil
	if not chat_id then
		error("Zeron did not return a new chat id", 0)
	end

	local harness = non_empty(args.harness)
	local model = non_empty(args.model)
	if not harness or not model then
		local p, m = read_chat_meta(chat_id)
		harness = harness or p
		model = model or m
	end

	local next_stage: any = nil
	if type(args.handoff) == "table" and non_empty(args.handoff.prompt_template) then
		next_stage = {
			role = non_empty(args.handoff.role) or "reviewer",
			task = non_empty(args.handoff.task) or `Review: {task}`,
			harness = non_empty(args.handoff.harness),
			model = non_empty(args.handoff.model),
			effort = non_empty(args.handoff.effort),
			project = non_empty(args.handoff.project) or non_empty(args.project),
			device = non_empty(args.handoff.device) or non_empty(args.device),
			cwd = non_empty(args.handoff.cwd) or non_empty(args.cwd),
			prompt_template = trim(args.handoff.prompt_template),
		}
	end

	local now = os.time()
	local worker = {
		chat_id = chat_id,
		captain_id = captain_id,
		role = role,
		task = task,
		harness = harness,
		model = model,
		status = "running",
		auto_report = if type(args.auto_report) == "boolean" then args.auto_report else nil,
		last_reply = "",
		last_error = nil,
		started_at = now,
		updated_at = now,
		created_at = now,
		workflow_id = non_empty(args.workflow_id),
		next_stage = next_stage,
	}
	state.workers[chat_id] = worker
	cap.updated_at = now
	local hlabel = harness or "default"
	push_event("worker_spawned", `Spawned {role} ({hlabel}): {task}`, captain_id, chat_id)
	save_and_emit()
	return worker
end

local function create_captain_internal(args: any): any
	local name = non_empty(args.name) or "Captain"
	local mission = trim(args.mission or "")
	local rules = trim(args.rules or "")
	local raw_prompt = trim(args.prompt or "")
	if raw_prompt == "" then
		raw_prompt = if mission ~= "" then mission else `You are Captain "{name}". Break down upcoming work, coordinate workers across any harness using Captain Deck tools, and keep a clear digest of what needs human decisions.`
	end

	local full_prompt = raw_prompt
	if rules ~= "" then
		full_prompt = `[Captain Mission: {mission}]\n[Shared Crew Rules]\n{rules}\n\n{raw_prompt}`
	elseif mission ~= "" and raw_prompt ~= mission then
		full_prompt = `[Captain Mission: {mission}]\n\n{raw_prompt}`
	end

	local res = zeron.new_chat({
		prompt = full_prompt,
		device = non_empty(args.device),
		project = non_empty(args.project),
		harness = non_empty(args.harness),
		model = non_empty(args.model),
		effort = non_empty(args.effort),
		cwd = non_empty(args.cwd),
	}):await()

	local chat_id = if type(res) == "table" then non_empty(res.chat) else nil
	if not chat_id then
		error("Zeron did not return a new chat id", 0)
	end

	local cap = ensure_captain(chat_id, {
		name = name,
		mission = mission,
		rules = rules,
		auto_report = args.auto_report,
		notify_attention = args.notify_attention,
		harness = non_empty(args.harness),
		model = non_empty(args.model),
	})
	cap.status = "running"
	push_event("captain_created", `Launched Captain "{cap.name}" ({cap.harness or "default"})`, chat_id, chat_id)
	save_and_emit()
	return cap
end

local function report_to_captain(worker: any, outcome: string, reply_text: string)
	local cap = state.captains[worker.captain_id]
	if not cap then
		return
	end
	local should_report = if type(worker.auto_report) == "boolean" then worker.auto_report else (cap.auto_report ~= false)
	if not should_report then
		return
	end
	-- Never send a report back to the same chat to prevent self-loops.
	if worker.captain_id == worker.chat_id then
		return
	end
	local excerpt = clip(reply_text, 900)
	local header = `[Captain Deck · Worker Update]\nRole: {worker.role} | Task: {worker.task} | Harness: {worker.harness or "default"} | Outcome: {outcome} | Chat: {worker.chat_id}`
	local body = if excerpt ~= "" then `{header}\n\nSummary:\n{excerpt}` else header
	local ok, err = pcall(function()
		zeron.send_message({
			chat = worker.captain_id,
			text = body,
			mode = "queue",
		}):await()
	end)
	if not ok then
		push_event("report_failed", `Could not auto-report {worker.role} to {cap.name}: {tostring(err)}`, worker.captain_id, worker.chat_id)
	else
		push_event("reported", `Reported {worker.role} ({outcome}) -> {cap.name}`, worker.captain_id, worker.chat_id)
	end
end

local function trigger_handoff(worker: any, reply_text: string)
	local stage = worker.next_stage
	if type(stage) ~= "table" or not non_empty(stage.prompt_template) then
		return
	end
	-- Consume once so a second turn never re-triggers the same handoff.
	worker.next_stage = nil
	local report = if trim(reply_text) ~= "" then trim(reply_text) else "(No reply text captured — inspect the previous worker's git diff or chat.)"
	local prompt = string.gsub(stage.prompt_template, "{{REPORT}}", function()
		return report
	end)
	local ok, result = pcall(spawn_worker_internal, {
		captain_id = worker.captain_id,
		role = stage.role or "reviewer",
		task = stage.task or `Handoff from {worker.role}`,
		prompt = prompt,
		harness = stage.harness,
		model = stage.model,
		effort = stage.effort,
		project = stage.project,
		device = stage.device,
		cwd = stage.cwd,
		workflow_id = worker.workflow_id,
	})
	if ok then
		push_event("handoff", `Handoff {worker.role} -> {stage.role or "reviewer"} ({stage.harness or "default"})`, worker.captain_id, result.chat_id)
	else
		push_event("handoff_failed", `Handoff failed: {tostring(result)}`, worker.captain_id, worker.chat_id)
		add_needs_you_item(worker.captain_id, `Handoff to {stage.role or "reviewer"} failed`, tostring(result), worker.chat_id)
	end
end

-- ── Top-level Zeron event listeners (fixed order, headless) ─────────────────

zeron.on("turn.started", function(e: any)
	local chat_id = non_empty(e and e.chat)
	if not chat_id then
		return
	end
	local now = os.time()
	local changed = false
	local worker = state.workers[chat_id]
	if worker then
		worker.status = "running"
		worker.started_at = now
		worker.updated_at = now
		worker.last_error = nil
		changed = true
	end
	local cap = state.captains[chat_id]
	if cap then
		cap.status = "running"
		cap.updated_at = now
		changed = true
	end
	if changed then
		save_and_emit()
	end
end)

zeron.on("turn.finished", function(e: any)
	local chat_id = non_empty(e and e.chat)
	if not chat_id then
		return
	end
	local outcome = non_empty(e and e.outcome) or "completed"
	local reply = clip(e and e.reply or "", MAX_REPLY)
	local now = os.time()

	local cap = state.captains[chat_id]
	if cap then
		cap.status = if outcome == "completed" then "idle" else outcome
		cap.updated_at = now
		if outcome == "errored" or outcome == "limited" then
			push_event("captain_error", `Captain "{cap.name}" finished with {outcome}`, chat_id, chat_id)
			if cap.notify_attention ~= false then
				try_notify(`Captain {cap.name} · {outcome}`, if reply ~= "" then reply else "Open chat to inspect.", chat_id)
			end
		end
		save_and_emit()
		return
	end

	local worker = state.workers[chat_id]
	if not worker then
		return
	end
	worker.status = outcome
	worker.updated_at = now
	if reply ~= "" then
		worker.last_reply = reply
	end
	if outcome == "errored" or outcome == "limited" then
		worker.last_error = if reply ~= "" then clip(reply, 240) else outcome
	else
		worker.last_error = nil
	end

	push_event("worker_finished", `{worker.role} ({worker.harness or "default"}) {outcome}: {worker.task}`, worker.captain_id, chat_id)
	save_and_emit()

	if outcome == "completed" and worker.next_stage ~= nil then
		trigger_handoff(worker, reply)
		save_and_emit()
	end

	if outcome == "errored" or outcome == "limited" then
		local parent = state.captains[worker.captain_id]
		if parent and parent.notify_attention ~= false then
			try_notify(`Worker {outcome} · {worker.role}`, `{worker.task}`, chat_id)
		end
	end

	report_to_captain(worker, outcome, reply)
	save_and_emit()
end)

zeron.on("turn.errored", function(e: any)
	local chat_id = non_empty(e and e.chat)
	if not chat_id then
		return
	end
	local now = os.time()
	local reply = clip(e and e.reply or "", MAX_REPLY)
	local worker = state.workers[chat_id]
	if worker then
		worker.status = "errored"
		worker.updated_at = now
		worker.last_error = if reply ~= "" then clip(reply, 240) else "Turn errored"
		push_event("worker_errored", `{worker.role} errored: {worker.task}`, worker.captain_id, chat_id)
		local parent = state.captains[worker.captain_id]
		if parent and parent.notify_attention ~= false then
			try_notify(`Worker errored · {worker.role}`, worker.task, chat_id)
		end
		save_and_emit()
		return
	end
	local cap = state.captains[chat_id]
	if cap then
		cap.status = "errored"
		cap.updated_at = now
		push_event("captain_errored", `Captain "{cap.name}" errored`, chat_id, chat_id)
		save_and_emit()
	end
end)

zeron.on("chat.awaiting_input", function(e: any)
	local chat_id = non_empty(e and e.chat)
	if not chat_id then
		return
	end
	local now = os.time()
	local worker = state.workers[chat_id]
	if worker then
		worker.status = "awaiting_input"
		worker.updated_at = now
		push_event("awaiting_input", `{worker.role} needs your input: {worker.task}`, worker.captain_id, chat_id)
		local parent = state.captains[worker.captain_id]
		if parent and parent.notify_attention ~= false then
			try_notify(`Needs input · {worker.role}`, worker.task, chat_id)
		end
		save_and_emit()
		return
	end
	local cap = state.captains[chat_id]
	if cap then
		cap.status = "awaiting_input"
		cap.updated_at = now
		push_event("awaiting_input", `Captain "{cap.name}" awaits your input`, chat_id, chat_id)
		if cap.notify_attention ~= false then
			try_notify(`Captain needs input · {cap.name}`, cap.mission ~= "" and cap.mission or "Open chat to respond.", chat_id)
		end
		save_and_emit()
	end
end)

zeron.on("chat.input_answered", function(e: any)
	local chat_id = non_empty(e and e.chat)
	if not chat_id then
		return
	end
	local now = os.time()
	local changed = false
	local worker = state.workers[chat_id]
	if worker and worker.status == "awaiting_input" then
		worker.status = "running"
		worker.updated_at = now
		changed = true
	end
	local cap = state.captains[chat_id]
	if cap and cap.status == "awaiting_input" then
		cap.status = "running"
		cap.updated_at = now
		changed = true
	end
	if changed then
		save_and_emit()
	end
end)

-- Periodic Captain wake scheduler (every 60s).
zeron.every(60, function()
	local now = os.time()
	local woke = false
	for cid, cap in state.captains do
		local mins = tonumber(cap.schedule_mins) or 0
		local prompt = trim(cap.schedule_prompt or "")
		if mins >= 5 and prompt ~= "" and cap.status ~= "running" and cap.status ~= "awaiting_input" then
			local last = tonumber(cap.last_wake_at) or 0
			if now - last >= mins * 60 then
				cap.last_wake_at = now
				local ok, err = pcall(function()
					zeron.send_message({
						chat = cid,
						text = `[Captain Deck · Scheduled Wake]\n{prompt}`,
						mode = "queue",
					}):await()
				end)
				if ok then
					push_event("scheduled_wake", `Woke Captain "{cap.name}" on {mins}m schedule`, cid, cid)
				else
					push_event("schedule_failed", `Scheduled wake failed for "{cap.name}": {tostring(err)}`, cid, cid)
				end
				woke = true
			end
		end
	end
	if woke then
		save_and_emit()
	end
end)

-- ── RPC Service Methods (for UI windows) ────────────────────────────────────

zeron.serve("get_state", function()
	return state
end, { safe = true })

zeron.serve("sync_settings", function(args: any)
	if type(args) == "table" then
		if type(args.default_auto_report) == "boolean" then
			state.prefs.default_auto_report = args.default_auto_report
		end
		if type(args.notify_on_attention) == "boolean" then
			state.prefs.notify_on_attention = args.notify_on_attention
		end
		if type(args.default_reviewer_harness) == "string" then
			state.prefs.default_reviewer_harness = trim(args.default_reviewer_harness)
		end
		save_and_emit()
	end
	return { ok = true }
end)

zeron.serve("probe_harnesses", function(args: any)
	local ids: { { id: string, label: string } } = {}
	local seen: { [string]: boolean } = {}
	for _, h in KNOWN_HARNESSES do
		seen[h.id] = true
		table.insert(ids, h)
	end
	if type(args) == "table" and type(args.extra) == "table" then
		for _, id in args.extra do
			local clean = non_empty(id)
			if clean and not seen[clean] then
				seen[clean] = true
				table.insert(ids, { id = clean, label = clean })
			end
		end
	end

	local out: { any } = {}
	for _, entry in ids do
		local ok, models = pcall(function()
			return zeron.models(entry.id):await()
		end)
		local list = if ok and type(models) == "table" then models else {}
		local slim: { any } = {}
		for _, m in list do
			if type(m) == "table" and non_empty(m.id) then
				table.insert(slim, {
					id = m.id,
					label = non_empty(m.label) or m.id,
					efforts = if type(m.efforts) == "table" then m.efforts else {},
				})
			end
		end
		table.insert(out, {
			id = entry.id,
			label = entry.label,
			has_models = #slim > 0,
			models = slim,
		})
	end
	return { harnesses = out }
end, { safe = true })

zeron.serve("promote_captain", function(args: any)
	local chat_id = non_empty(args and args.chat_id)
	if not chat_id then
		error("chat_id is required", 0)
	end
	local cap = ensure_captain(chat_id, args)
	save_and_emit()
	return cap
end)

zeron.serve("create_captain", function(args: any)
	return create_captain_internal(args or {})
end)

zeron.serve("update_captain", function(args: any)
	local chat_id = non_empty(args and args.chat_id)
	if not chat_id or not state.captains[chat_id] then
		error("Captain not found", 0)
	end
	local cap = ensure_captain(chat_id, args)
	save_and_emit()
	return cap
end)

zeron.serve("remove_captain", function(args: any)
	local chat_id = non_empty(args and args.chat_id)
	if not chat_id then
		error("chat_id is required", 0)
	end
	local cap = state.captains[chat_id]
	if cap then
		state.captains[chat_id] = nil
		for wid, w in state.workers do
			if w.captain_id == chat_id then
				state.workers[wid] = nil
			end
		end
		push_event("captain_removed", `Demoted Captain "{cap.name}"`, chat_id, chat_id)
		save_and_emit()
	end
	return { ok = true }
end)

zeron.serve("spawn_worker", function(args: any)
	return spawn_worker_internal(args or {})
end)

zeron.serve("attach_worker", function(args: any)
	local captain_id = non_empty(args and args.captain_id)
	local worker_chat = non_empty(args and args.worker_chat)
	if not captain_id or not worker_chat then
		error("captain_id and worker_chat are required", 0)
	end
	if captain_id == worker_chat then
		error("Cannot attach a Captain to itself", 0)
	end
	local cap = ensure_captain(captain_id, nil)
	local p, m = read_chat_meta(worker_chat)
	local now = os.time()
	local worker = {
		chat_id = worker_chat,
		captain_id = captain_id,
		role = non_empty(args.role) or "worker",
		task = non_empty(args.task) or "Attached chat",
		harness = non_empty(args.harness) or p,
		model = non_empty(args.model) or m,
		status = non_empty(args.status) or "idle",
		auto_report = nil,
		last_reply = "",
		last_error = nil,
		started_at = nil,
		updated_at = now,
		created_at = now,
		workflow_id = nil,
		next_stage = nil,
	}
	state.workers[worker_chat] = worker
	cap.updated_at = now
	push_event("worker_attached", `Attached {worker.role} -> {cap.name}`, captain_id, worker_chat)
	save_and_emit()
	return worker
end)

zeron.serve("detach_worker", function(args: any)
	local worker_chat = non_empty(args and args.worker_chat)
	if not worker_chat then
		error("worker_chat is required", 0)
	end
	local w = state.workers[worker_chat]
	if w then
		state.workers[worker_chat] = nil
		push_event("worker_detached", `Detached {w.role}: {w.task}`, w.captain_id, worker_chat)
		save_and_emit()
	end
	return { ok = true }
end)

zeron.serve("message_chat", function(args: any)
	local chat_id = non_empty(args and args.chat_id)
	local text = trim(args and args.text or "")
	if not chat_id or text == "" then
		error("chat_id and text are required", 0)
	end
	local mode = if args and args.mode == "steer" then "steer" else "queue"
	local res = zeron.send_message({
		chat = chat_id,
		text = text,
		mode = mode,
	}):await()
	local w = state.workers[chat_id]
	local cap_id = if w then w.captain_id elseif state.captains[chat_id] then chat_id else nil
	push_event("message_sent", `Sent ({mode}) to {if w then w.role else "chat"}: {clip(text, 72)}`, cap_id, chat_id)
	save_and_emit()
	return res
end)

zeron.serve("add_attention", function(args: any)
	local captain_id = non_empty(args and args.captain_id)
	local title = trim(args and args.title or "")
	if not captain_id or title == "" then
		error("captain_id and title are required", 0)
	end
	local item = add_needs_you_item(captain_id, title, args.detail, args.worker_chat)
	save_and_emit()
	return item
end)

zeron.serve("resolve_attention", function(args: any)
	local captain_id = non_empty(args and args.captain_id)
	local item_id = non_empty(args and args.item_id)
	local cap = if captain_id then state.captains[captain_id] else nil
	if cap and type(cap.needs_you) == "table" then
		for _, item in cap.needs_you do
			if item.id == item_id then
				item.resolved = true
				break
			end
		end
		cap.updated_at = os.time()
		save_and_emit()
	end
	return { ok = true }
end)

zeron.serve("clear_events", function()
	state.events = {}
	save_and_emit()
	return { ok = true }
end)

zeron.serve("launch_workflow", function(args: any)
	local preset = non_empty(args and args.preset) or "build_review"
	local task = trim(args and args.task or "")
	if task == "" then
		error("Task description is required", 0)
	end
	local workflow_id = next_id("wf")
	local project = non_empty(args.project)
	local device = non_empty(args.device)

	-- Either reuse an existing Captain or launch a dedicated Captain thread.
	local captain_id = non_empty(args.captain_id)
	if not captain_id then
		local cap_name = non_empty(args.captain_name) or clip(task, 36)
		local cap = create_captain_internal({
			name = cap_name,
			mission = task,
			rules = trim(args.rules or ""),
			harness = non_empty(args.captain_harness) or non_empty(args.primary_harness),
			model = non_empty(args.captain_model) or non_empty(args.primary_model),
			project = project,
			device = device,
			prompt = `You are the Captain coordinating workflow "{preset}" for:\n\n{task}\n\nCaptain Deck is spawning your crew right now and will auto-report each worker's completion here. Wait for crew reports, synthesize results, and flag any blockers with captain_update_digest.`,
		})
		captain_id = cap.chat_id
	end

	local spawned: { any } = {}
	if preset == "build_review" then
		local reviewer_harness = non_empty(args.secondary_harness)
		if not reviewer_harness and state.prefs then
			reviewer_harness = non_empty(state.prefs.default_reviewer_harness)
		end
		local review_prompt = "Review the work just completed for this task (read-only; do NOT edit files or commit unless asked):\n\nOriginal Task:\n"
			.. task
			.. "\n\nBuilder Report:\n{{REPORT}}\n\nInspect the actual files and git diff carefully. List each issue as Critical or Minor with exact file paths and line numbers, and state whether it is ready to merge."
		local w = spawn_worker_internal({
			captain_id = captain_id,
			role = "builder",
			task = clip(task, 72),
			prompt = `Build the following task cleanly, run verification checks/tests, and summarize every file changed:\n\n{task}`,
			harness = non_empty(args.primary_harness),
			model = non_empty(args.primary_model),
			project = project,
			device = device,
			workflow_id = workflow_id,
			handoff = {
				role = "reviewer",
				task = `Review: {clip(task, 60)}`,
				harness = reviewer_harness,
				model = non_empty(args.secondary_model),
				project = project,
				device = device,
				prompt_template = review_prompt,
			},
		})
		table.insert(spawned, w)
	elseif preset == "fanout" then
		local raw_lines = trim(args.subtasks or "")
		local subtasks: { string } = {}
		for line in string.gmatch(raw_lines, "[^\r\n]+") do
			local clean = trim((string.gsub(line, "^[-*%d%.%)]+%s*", "")))
			if clean ~= "" then
				table.insert(subtasks, clean)
			end
		end
		if #subtasks == 0 then
			table.insert(subtasks, task)
		end
		for i, sub in subtasks do
			if i > 8 then
				break
			end
			local w = spawn_worker_internal({
				captain_id = captain_id,
				role = `worker-{i}`,
				task = clip(sub, 72),
				prompt = `Overall goal:\n{task}\n\nYour dedicated subtask (#{i}):\n{sub}\n\nFocus strictly on this subtask and report a crisp summary of changes and verification.`,
				harness = non_empty(args.primary_harness),
				model = non_empty(args.primary_model),
				project = project,
				device = device,
				workflow_id = workflow_id,
			})
			table.insert(spawned, w)
		end
	elseif preset == "compare" then
		local h1 = non_empty(args.primary_harness)
		local h2 = non_empty(args.secondary_harness)
		local w1 = spawn_worker_internal({
			captain_id = captain_id,
			role = if h1 then `candidate:{h1}` else "candidate-A",
			task = clip(task, 72),
			prompt = task,
			harness = h1,
			model = non_empty(args.primary_model),
			project = project,
			device = device,
			workflow_id = workflow_id,
		})
		table.insert(spawned, w1)
		local w2 = spawn_worker_internal({
			captain_id = captain_id,
			role = if h2 then `candidate:{h2}` else "candidate-B",
			task = clip(task, 72),
			prompt = task,
			harness = h2,
			model = non_empty(args.secondary_model),
			project = project,
			device = device,
			workflow_id = workflow_id,
		})
		table.insert(spawned, w2)
	end

	push_event("workflow_launched", `Launched {preset} workflow ({#spawned} worker(s))`, captain_id, captain_id)
	save_and_emit()
	return { captain_id = captain_id, workflow_id = workflow_id, workers = spawned }
end)

-- ── Harness-Agnostic Agent Tools (`zeron.tool`) ─────────────────────────────

local function resolve_captain_for_tool(args: any, call: any): string?
	local explicit = non_empty(args and args.captain_id)
	if explicit then
		return explicit
	end
	local caller = non_empty(call and call.chat)
	if not caller then
		return nil
	end
	if state.captains[caller] then
		return caller
	end
	if state.workers[caller] then
		return state.workers[caller].captain_id
	end
	return caller
end

zeron.tool {
	name = "captain_status",
	run = function(args: any, call: any)
		local include_replies = not (type(args) == "table" and args.include_replies == false)
		local target = non_empty(args and args.captain_id)
		if not target and call and non_empty(call.chat) then
			if state.captains[call.chat] then
				target = call.chat
			elseif state.workers[call.chat] then
				target = state.workers[call.chat].captain_id
			end
		end

		local function format_captain(cap: any): any
			local crew = {}
			for _, w in state.workers do
				if w.captain_id == cap.chat_id then
					table.insert(crew, {
						chat_id = w.chat_id,
						role = w.role,
						task = w.task,
						harness = w.harness,
						model = w.model,
						status = w.status,
						last_error = w.last_error,
						has_handoff = w.next_stage ~= nil,
						last_reply = if include_replies then w.last_reply else nil,
						updated_at = w.updated_at,
					})
				end
			end
			return {
				chat_id = cap.chat_id,
				name = cap.name,
				mission = cap.mission,
				rules = cap.rules,
				digest = cap.digest,
				harness = cap.harness,
				model = cap.model,
				status = cap.status,
				auto_report = cap.auto_report,
				needs_you = cap.needs_you,
				crew = crew,
			}
		end

		if target and state.captains[target] then
			return { captain = format_captain(state.captains[target]) }
		end
		local list = {}
		for _, cap in state.captains do
			table.insert(list, format_captain(cap))
		end
		return { captains = list, total_captains = #list }
	end,
}

zeron.tool {
	name = "captain_promote",
	run = function(args: any, call: any)
		local chat_id = non_empty(args and args.chat_id) or non_empty(call and call.chat)
		if not chat_id then
			error("chat_id is required when no active chat context is available", 0)
		end
		local cap = ensure_captain(chat_id, args)
		save_and_emit()
		return { ok = true, captain = cap }
	end,
}

zeron.tool {
	name = "captain_spawn_worker",
	run = function(args: any, call: any)
		local captain_id = resolve_captain_for_tool(args, call)
		if not captain_id then
			error("captain_id is required", 0)
		end
		local copy = table.clone(args or {})
		copy.captain_id = captain_id
		local worker = spawn_worker_internal(copy)
		return {
			ok = true,
			worker_chat = worker.chat_id,
			captain_id = worker.captain_id,
			role = worker.role,
			harness = worker.harness,
			model = worker.model,
			status = worker.status,
		}
	end,
}

zeron.tool {
	name = "captain_message_worker",
	run = function(args: any, _call: any)
		local chat_id = non_empty(args and args.chat_id)
		local text = trim(args and args.text or "")
		if not chat_id or text == "" then
			error("chat_id and text are required", 0)
		end
		local mode = if args.mode == "steer" then "steer" else "queue"
		local res = zeron.send_message({
			chat = chat_id,
			text = text,
			mode = mode,
		}):await()
		local w = state.workers[chat_id]
		push_event("tool_message", `Agent messaged {if w then w.role else chat_id} ({mode})`, if w then w.captain_id else nil, chat_id)
		save_and_emit()
		return res
	end,
}

zeron.tool {
	name = "captain_attach_worker",
	run = function(args: any, call: any)
		local captain_id = resolve_captain_for_tool(args, call)
		local worker_chat = non_empty(args and args.worker_chat)
		if not captain_id or not worker_chat then
			error("captain_id and worker_chat are required", 0)
		end
		if captain_id == worker_chat then
			error("Cannot attach a Captain to itself", 0)
		end
		ensure_captain(captain_id, nil)
		local p, m = read_chat_meta(worker_chat)
		local now = os.time()
		local worker = {
			chat_id = worker_chat,
			captain_id = captain_id,
			role = non_empty(args.role) or "worker",
			task = non_empty(args.task) or "Attached chat",
			harness = p,
			model = m,
			status = "idle",
			auto_report = nil,
			last_reply = "",
			last_error = nil,
			started_at = nil,
			updated_at = now,
			created_at = now,
			workflow_id = nil,
			next_stage = nil,
		}
		state.workers[worker_chat] = worker
		push_event("worker_attached", `Attached {worker.role} via tool`, captain_id, worker_chat)
		save_and_emit()
		return { ok = true, worker = worker }
	end,
}

zeron.tool {
	name = "captain_update_digest",
	run = function(args: any, call: any)
		local captain_id = resolve_captain_for_tool(args, call)
		if not captain_id then
			error("captain_id is required", 0)
		end
		local cap = ensure_captain(captain_id, {
			mission = args.mission,
			rules = args.rules,
			digest = args.digest,
		})
		local flagged: any = nil
		if type(args.flag_needs_you) == "table" and non_empty(args.flag_needs_you.title) then
			flagged = add_needs_you_item(
				captain_id,
				args.flag_needs_you.title,
				args.flag_needs_you.detail,
				args.flag_needs_you.worker_chat
			)
		end
		if non_empty(args.resolve_item_id) and type(cap.needs_you) == "table" then
			for _, item in cap.needs_you do
				if item.id == args.resolve_item_id then
					item.resolved = true
				end
			end
		end
		save_and_emit()
		return { ok = true, captain_id = captain_id, flagged = flagged }
	end,
}

print("captain-deck: service loaded")

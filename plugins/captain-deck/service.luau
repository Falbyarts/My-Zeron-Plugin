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

local function sanitize_harness_id(raw: any): string
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

local function clean_attachment_path(raw: any): string
	local s = ""
	if type(raw) == "string" then
		s = raw
	elseif type(raw) == "table" and type(raw.path) == "string" then
		s = raw.path
	else
		return ""
	end
	s = trim(s)
	while #s >= 2 do
		local first = string.sub(s, 1, 1)
		local last = string.sub(s, -1)
		if (first == '"' and last == '"') or (first == "'" and last == "'") then
			s = trim(string.sub(s, 2, -2))
		else
			break
		end
	end
	return s
end

local function normalize_attachments(raw: any): { string }
	local out: { string } = {}
	if type(raw) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	local function add_entry(entry: any)
		if #out >= 12 then
			return
		end
		local p = clean_attachment_path(entry)
		if p ~= "" and not seen[p] then
			seen[p] = true
			table.insert(out, p)
		end
	end
	if type((raw :: any).path) == "string" then
		add_entry(raw)
		return out
	end
	for _, entry in raw do
		add_entry(entry)
		if #out >= 12 then
			break
		end
	end
	return out
end

local function append_attachment_context(prompt: string, attachments: { string }): string
	if type(attachments) ~= "table" or #attachments == 0 then
		return prompt
	end
	local lines: { string } = { "", "Attached Reference Files / Images:" }
	for _, p in attachments do
		table.insert(lines, `- {p}`)
	end
	table.insert(lines, "Inspect these attached files/images carefully as visual/technical reference for the task.")
	return prompt .. "\n" .. table.concat(lines, "\n")
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

local function current_device_id(): string?
	local d = (zeron :: any).device
	if type(d) == "table" then
		return non_empty(d.id)
	elseif type(d) == "string" then
		return non_empty(d)
	end
	return nil
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
	else
		s.prefs.default_reviewer_harness = sanitize_harness_id(s.prefs.default_reviewer_harness)
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

local function deliver_attachments(chat_id: string, attachments: { string })
	if type(attachments) ~= "table" or #attachments == 0 then
		return
	end
	local ok, err = pcall(function()
		return zeron.send_message({
			chat = chat_id,
			text = "Reference images/files attached for this task.",
			attachments = attachments,
			mode = "queue",
		}):await()
	end)
	if not ok then
		local w = state.workers[chat_id]
		local cap_id = if w then w.captain_id elseif state.captains[chat_id] then chat_id else nil
		local msg = `Could not attach {#attachments} reference file(s) to {chat_id}: {tostring(err)}`
		print(`captain-deck: {msg}`)
		push_event("attachments_notice", msg, cap_id, chat_id)
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
	local clean_role = non_empty(role) or "worker"
	local clean_task = non_empty(task)
	if clean_task then
		local one_line_task = trim((string.gsub(clean_task, "%s+", " ")))
		table.insert(parts, `[Worker: {clean_role}] {one_line_task}`)
	else
		table.insert(parts, `[Worker: {clean_role}]`)
	end
	if captain and non_empty(captain.rules) then
		table.insert(parts, `[Captain Rules — {captain.name or "Captain"}]\n{trim(captain.rules)}`)
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
		existing.project = non_empty(o.project) or existing.project
		existing.device = non_empty(o.device) or existing.device or current_device_id()
		existing.cwd = non_empty(o.cwd) or existing.cwd
		existing.fallback_project = non_empty(o.fallback_project) or existing.fallback_project
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
		project = non_empty(o.project),
		device = non_empty(o.device) or current_device_id(),
		cwd = non_empty(o.cwd),
		fallback_project = non_empty(o.fallback_project),
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

local function safe_new_chat(opts: {
	prompt: string,
	device: string?,
	project: string?,
	fallback_project: string?,
	harness: string?,
	model: string?,
	effort: string?,
	cwd: string?,
	captain_id: string?,
}): any
	local cap = if opts.captain_id then state.captains[opts.captain_id] else nil
	local device = non_empty(opts.device) or (if cap then non_empty(cap.device) else nil) or current_device_id()
	local project = non_empty(opts.project) or (if cap then non_empty(cap.project) else nil)
	local fallback_project = non_empty(opts.fallback_project) or (if cap then non_empty(cap.fallback_project) else nil)
	local cwd = non_empty(opts.cwd) or (if cap then non_empty(cap.cwd) else nil)
	local harness = non_empty(opts.harness)
	local model = non_empty(opts.model)
	local effort = non_empty(opts.effort)

	local last_err: any = nil

	-- Attempt 1: primary attempt
	local ok, res = pcall(function()
		return zeron.new_chat({
			prompt = opts.prompt,
			device = device,
			project = project,
			harness = harness,
			model = model,
			effort = effort,
			cwd = cwd,
		}):await()
	end)
	if ok and type(res) == "table" and non_empty(res.chat) then
		return res
	end
	last_err = if not ok then res else "Zeron did not return a new chat id"

	-- Attempt 2 (Fallback Project): jika Attempt 1 gagal DAN project == nil DAN fallback_project ~= nil
	if project == nil and fallback_project ~= nil then
		project = fallback_project
		ok, res = pcall(function()
			return zeron.new_chat({
				prompt = opts.prompt,
				device = device,
				project = project,
				harness = harness,
				model = model,
				effort = effort,
				cwd = cwd,
			}):await()
		end)
		if ok and type(res) == "table" and non_empty(res.chat) then
			return res
		end
		last_err = if not ok then res else "Zeron did not return a new chat id"
	end

	-- Attempt 3 (Fallback Model Default): jika masih gagal DAN model ~= nil
	if model ~= nil then
		local try_project = project or fallback_project
		ok, res = pcall(function()
			return zeron.new_chat({
				prompt = opts.prompt,
				device = device,
				project = try_project,
				harness = harness,
				model = nil,
				effort = effort,
				cwd = cwd,
			}):await()
		end)
		if ok and type(res) == "table" and non_empty(res.chat) then
			return res
		end
		last_err = if not ok then res else "Zeron did not return a new chat id"
	end

	push_event("launch_failed", "Failed to start chat (" .. (harness or "default") .. "): " .. tostring(last_err), opts.captain_id, nil)
	save_and_emit()
	error(tostring(last_err), 0)
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
	local attachments = normalize_attachments(args.attachments)
	local full_prompt = append_attachment_context(build_worker_prompt(cap, role, task, raw_prompt), attachments)

	local res = safe_new_chat({
		prompt = full_prompt,
		device = non_empty(args.device),
		project = non_empty(args.project),
		fallback_project = non_empty(args.fallback_project),
		harness = non_empty(args.harness),
		model = non_empty(args.model),
		effort = non_empty(args.effort),
		cwd = non_empty(args.cwd),
		captain_id = captain_id,
	})

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
			fallback_project = non_empty(args.handoff.fallback_project) or non_empty(args.fallback_project),
			device = non_empty(args.handoff.device) or non_empty(args.device),
			cwd = non_empty(args.handoff.cwd) or non_empty(args.cwd),
			prompt_template = trim(args.handoff.prompt_template),
			attachments = if type(args.handoff.attachments) == "table" then normalize_attachments(args.handoff.attachments) elseif #attachments > 0 then attachments else nil,
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
	deliver_attachments(chat_id, attachments)
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

	local attachments = normalize_attachments(args.attachments)
	local full_prompt = raw_prompt
	if rules ~= "" then
		full_prompt = `[Captain Mission: {mission}]\n[Shared Crew Rules]\n{rules}\n\n{raw_prompt}`
	elseif mission ~= "" and raw_prompt ~= mission then
		full_prompt = `[Captain Mission: {mission}]\n\n{raw_prompt}`
	end
	full_prompt = append_attachment_context(full_prompt, attachments)

	local res = safe_new_chat({
		prompt = full_prompt,
		device = non_empty(args.device),
		project = non_empty(args.project),
		fallback_project = non_empty(args.fallback_project),
		harness = non_empty(args.harness),
		model = non_empty(args.model),
		effort = non_empty(args.effort),
		cwd = non_empty(args.cwd),
	})

	local chat_id = if type(res) == "table" then non_empty(res.chat) else nil
	if not chat_id then
		error("Zeron did not return a new chat id", 0)
	end

	local cap = ensure_captain(chat_id, {
		name = name,
		mission = mission,
		rules = rules,
		project = non_empty(args.project),
		device = non_empty(args.device),
		fallback_project = non_empty(args.fallback_project),
		cwd = non_empty(args.cwd),
		auto_report = args.auto_report,
		notify_attention = args.notify_attention,
		harness = non_empty(args.harness),
		model = non_empty(args.model),
	})
	cap.status = "running"
	push_event("captain_created", `Launched Captain "{cap.name}" ({cap.harness or "default"})`, chat_id, chat_id)
	deliver_attachments(chat_id, attachments)
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
	local cap = state.captains[worker.captain_id]
	local handoff_attachments = stage.attachments
	if (type(handoff_attachments) ~= "table" or #handoff_attachments == 0) and cap and type(cap.pending_workflow) == "table" then
		handoff_attachments = cap.pending_workflow.attachments
	end
	if cap and cap.pending_workflow ~= nil then
		cap.pending_workflow = nil
	end
	local ok, result = pcall(spawn_worker_internal, {
		captain_id = worker.captain_id,
		role = stage.role or "reviewer",
		task = stage.task or `Handoff from {worker.role}`,
		prompt = prompt,
		harness = stage.harness,
		model = stage.model,
		effort = stage.effort,
		project = stage.project,
		fallback_project = stage.fallback_project,
		device = stage.device,
		cwd = stage.cwd,
		workflow_id = worker.workflow_id,
		attachments = handoff_attachments,
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
		worker.pending_input = nil
		changed = true
	end
	local cap = state.captains[chat_id]
	if cap then
		cap.status = "running"
		cap.updated_at = now
		cap.pending_input = nil
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
		cap.pending_input = nil
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
	worker.pending_input = nil
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
		worker.pending_input = nil
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
		cap.pending_input = nil
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
	local request = non_empty(e and e.request) or non_empty(e and e.request_id)
	local title = non_empty(e and e.title) or non_empty(e and e.header) or non_empty(e and e.question)
	local detail = non_empty(e and e.detail) or non_empty(e and e.command) or non_empty(e and e.message) or non_empty(e and e.text)
	if type(e) == "table" and type(e.questions) == "table" and type(e.questions[1]) == "table" then
		local q1 = e.questions[1]
		if not title then
			title = non_empty(q1.header) or non_empty(q1.question)
		end
		if not detail then
			local qd = non_empty(q1.question) or non_empty(q1.detail)
			if qd and qd ~= title then
				detail = qd
			end
		end
	end
	local kind = non_empty(e and e.kind) or "approval"
	local pending_input = {
		at = now,
		request = request,
		title = if title then clip(title, 160) else nil,
		detail = if detail then clip(detail, 360) else nil,
		kind = kind,
	}

	local worker = state.workers[chat_id]
	if worker then
		worker.status = "awaiting_input"
		worker.pending_input = pending_input
		worker.updated_at = now
		local summary_detail = pending_input.title or worker.task
		push_event("awaiting_input", `{worker.role} needs your input: {summary_detail}`, worker.captain_id, chat_id)
		local parent = state.captains[worker.captain_id]
		if parent and parent.notify_attention ~= false then
			local notif_body = pending_input.detail or pending_input.title or worker.task
			try_notify(`Needs input · {worker.role}`, notif_body, chat_id)
		end
		save_and_emit()
		return
	end
	local cap = state.captains[chat_id]
	if cap then
		cap.status = "awaiting_input"
		cap.pending_input = pending_input
		cap.updated_at = now
		local summary = if pending_input.title
			then `Captain "{cap.name}" awaits your input: {pending_input.title}`
			else `Captain "{cap.name}" awaits your input`
		push_event("awaiting_input", summary, chat_id, chat_id)
		if cap.notify_attention ~= false then
			local notif_body = pending_input.detail or pending_input.title or (if cap.mission ~= "" then cap.mission else "Open chat to respond.")
			try_notify(`Captain needs input · {cap.name}`, notif_body, chat_id)
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
	if worker then
		if worker.pending_input ~= nil then
			worker.pending_input = nil
			changed = true
		end
		if worker.status == "awaiting_input" then
			worker.status = "running"
			worker.updated_at = now
			changed = true
		end
	end
	local cap = state.captains[chat_id]
	if cap then
		if cap.pending_input ~= nil then
			cap.pending_input = nil
			changed = true
		end
		if cap.status == "awaiting_input" then
			cap.status = "running"
			cap.updated_at = now
			changed = true
		end
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
		if args.default_reviewer_harness ~= nil then
			state.prefs.default_reviewer_harness = sanitize_harness_id(args.default_reviewer_harness)
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
	local chat_ids: { string } = {}
	local removed_workers = 0
	if cap then
		state.captains[chat_id] = nil
		table.insert(chat_ids, chat_id)
	end
	local to_remove: { string } = {}
	for wid, w in state.workers do
		if w.captain_id == chat_id then
			table.insert(to_remove, wid)
		end
	end
	for _, wid in to_remove do
		state.workers[wid] = nil
		removed_workers += 1
		table.insert(chat_ids, wid)
	end
	if cap or removed_workers > 0 then
		local label = if cap then `Demoted Captain "{cap.name}"` else `Removed orphaned crew ({removed_workers}) for {chat_id}`
		push_event("captain_removed", label, chat_id, chat_id)
		save_and_emit()
	end
	return { ok = true, removed_workers = removed_workers, chat_ids = chat_ids }
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
	local attachments = normalize_attachments(args and args.attachments)
	if not chat_id or (text == "" and #attachments == 0) then
		error("chat_id and text are required", 0)
	end
	if text == "" then
		text = "Reference images/files attached."
	end
	local mode = if args and args.mode == "steer" then "steer" else "queue"
	local w = state.workers[chat_id]
	local cap_id = if w then w.captain_id elseif state.captains[chat_id] then chat_id else nil
	local res: any
	if #attachments > 0 then
		local ok, send_res = pcall(function()
			return zeron.send_message({
				chat = chat_id,
				text = text,
				attachments = attachments,
				mode = mode,
			}):await()
		end)
		if ok then
			res = send_res
		else
			local err_str = tostring(send_res)
			print(`captain-deck: message_chat attachments rejected ({err_str}), retrying without attachments`)
			push_event("attachments_notice", `Could not attach {#attachments} file(s); sent path references instead: {err_str}`, cap_id, chat_id)
			local fallback_text = append_attachment_context(text, attachments)
			res = zeron.send_message({
				chat = chat_id,
				text = fallback_text,
				mode = mode,
			}):await()
		end
	else
		res = zeron.send_message({
			chat = chat_id,
			text = text,
			mode = mode,
		}):await()
	end
	push_event("message_sent", `Sent ({mode}) to {if w then w.role else "chat"}: {clip(text, 72)}`, cap_id, chat_id)
	save_and_emit()
	return res
end)

local function err_reason(err: any): string
	if type((zeron :: any).reason) == "function" then
		local ok, r = pcall((zeron :: any).reason, err)
		if ok and type(r) == "string" and r ~= "" then
			return r
		end
	end
	local text = tostring(err)
	return string.match(text, "^([%a_]+):") or string.match(text, "^([%a_]+)$") or "failed"
end

zeron.serve("answer_input", function(args: any)
	local a = if type(args) == "table" then args else {}
	local chat_id = non_empty(a.chat_id) or non_empty(a.chat)
	if not chat_id then
		return { ok = false, error = "chat_id is required", needs_chat = true }
	end

	local raw_decision = non_empty(a.decision)
	local decision = if raw_decision then string.lower(raw_decision) else nil
	local explicit_answers = a.answers

	local worker = state.workers[chat_id]
	local cap = state.captains[chat_id]
	local stored_req: string? = nil
	if worker and type(worker.pending_input) == "table" then
		stored_req = non_empty(worker.pending_input.request)
	elseif cap and type(cap.pending_input) == "table" then
		stored_req = non_empty(cap.pending_input.request)
	end
	local req = non_empty(a.request) or stored_req

	local candidates: { any } = {}
	if explicit_answers ~= nil then
		candidates = { explicit_answers }
	elseif decision == "allow" then
		candidates = { { "Allow" }, { "Allow once" }, { "Yes" } }
	elseif decision == "always" then
		candidates = { { "Always allow" }, { "Allow" } }
	elseif decision == "deny" then
		candidates = { { "Deny" }, { "No" } }
	else
		return { ok = false, error = "Unsupported decision or missing answers", needs_chat = true }
	end

	local last_err: any = nil
	local succeeded = false
	for _, cand in candidates do
		local ok, res_or_err = pcall(function()
			return zeron.answer({
				chat = chat_id,
				answers = cand,
				request = req,
			}):await()
		end)
		if ok then
			succeeded = true
			break
		end
		last_err = res_or_err
		local reason = err_reason(res_or_err)
		if reason == "not_allowed" or reason == "not_found" then
			break
		end
	end

	if succeeded then
		local now = os.time()
		local cap_id: string? = nil
		local label = "chat"
		if worker then
			worker.pending_input = nil
			if worker.status == "awaiting_input" then
				worker.status = "running"
			end
			worker.updated_at = now
			cap_id = worker.captain_id
			label = worker.role or "worker"
		end
		if cap then
			cap.pending_input = nil
			if cap.status == "awaiting_input" then
				cap.status = "running"
			end
			cap.updated_at = now
			cap_id = chat_id
			label = `Captain "{cap.name or "Captain"}"`
		end
		local action_lbl = decision or "custom"
		push_event("input_answered", `Answered {label} ({action_lbl})`, cap_id, chat_id)
		save_and_emit()
		return { ok = true, chat_id = chat_id, decision = decision }
	end

	return {
		ok = false,
		error = tostring(last_err or "Could not answer prompt"),
		needs_chat = true,
	}
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

zeron.serve("clear_all", function(args: any)
	local removed_captains = 0
	local removed_workers = 0
	local chat_ids: { string } = {}
	local seen: { [string]: boolean } = {}

	for cid, _ in state.captains do
		removed_captains += 1
		if not seen[cid] then
			seen[cid] = true
			table.insert(chat_ids, cid)
		end
	end
	for wid, _ in state.workers do
		removed_workers += 1
		if not seen[wid] then
			seen[wid] = true
			table.insert(chat_ids, wid)
		end
	end

	state.captains = {}
	state.workers = {}

	if type(args) == "table" and args.include_events == true then
		state.events = {}
	else
		push_event("fleet_cleared", `Cleared fleet ({removed_captains} captain(s), {removed_workers} worker(s))`, nil, nil)
	end

	save_and_emit()
	return {
		ok = true,
		removed_captains = removed_captains,
		removed_workers = removed_workers,
		chat_ids = chat_ids,
	}
end)

zeron.serve("prune_deleted", function(args: any)
	local raw = if type(args) == "table" then args.valid_ids else nil
	if type(raw) ~= "table" then
		return { removed_captains = 0, removed_workers = 0 }
	end

	local valid: { [string]: boolean } = {}
	for k, v in raw do
		if type(k) == "string" and v == true then
			valid[k] = true
		elseif type(v) == "string" and v ~= "" then
			valid[v] = true
		end
	end

	local now = os.time()
	local GRACE_SECONDS = 15
	local removed_captains = 0
	local removed_workers = 0

	for cid, cap in state.captains do
		local age = now - (tonumber(cap.created_at) or 0)
		if not valid[cid] and age >= GRACE_SECONDS then
			state.captains[cid] = nil
			removed_captains += 1
		end
	end

	for wid, w in state.workers do
		local age = now - (tonumber(w.created_at) or 0)
		local missing_self = not valid[wid] and age >= GRACE_SECONDS
		local missing_parent = w.captain_id and not state.captains[w.captain_id] and not valid[w.captain_id]
		if missing_self or missing_parent then
			state.workers[wid] = nil
			removed_workers += 1
		end
	end

	if removed_captains > 0 or removed_workers > 0 then
		push_event(
			"pruned_ghosts",
			`Cleaned up {removed_captains} deleted captain(s) and {removed_workers} worker(s)`,
			nil,
			nil
		)
		save_and_emit()
	end

	return {
		removed_captains = removed_captains,
		removed_workers = removed_workers,
	}
end)

zeron.serve("launch_workflow", function(args: any)
	local preset = non_empty(args and args.kind) or non_empty(args and args.preset) or "build_review"
	local task = trim(args and args.task or "")
	if task == "" then
		error("Task description is required", 0)
	end
	local workflow_id = next_id("wf")
	local project = non_empty(args.project)
	local device = non_empty(args.device) or current_device_id()
	local fallback_project = non_empty(args.fallback_project)
	local cwd = non_empty(args.cwd)
	local attachments = normalize_attachments(args and args.attachments)

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
			fallback_project = fallback_project,
			cwd = cwd,
			attachments = attachments,
			prompt = `You are the Captain coordinating workflow "{preset}" for:\n\n{task}\n\nCaptain Deck is spawning your crew right now and will auto-report each worker's completion here. Wait for crew reports, synthesize results, and flag any blockers with captain_update_digest.`,
		})
		captain_id = cap.chat_id
	end

	local spawned: { any } = {}
	if preset == "build_review" then
		local reviewer_harness = non_empty(args.secondary_harness)
		if not reviewer_harness and state.prefs then
			reviewer_harness = non_empty(sanitize_harness_id(state.prefs.default_reviewer_harness))
		end
		local cap_obj = if captain_id then state.captains[captain_id] else nil
		if cap_obj and #attachments > 0 then
			cap_obj.pending_workflow = {
				workflow_id = workflow_id,
				preset = preset,
				attachments = attachments,
			}
		end
		local review_prompt = "Review the work just completed for this task (read-only; do NOT edit files or commit unless asked):\n\nOriginal Task:\n"
			.. task
			.. "\n\nBuilder Report:\n{{REPORT}}\n\nInspect the actual files, git status, and git diff carefully. List each issue as Critical or Minor with exact file paths and line numbers, and state whether it is ready to merge."
		local w = spawn_worker_internal({
			captain_id = captain_id,
			role = "builder",
			task = clip(task, 72),
			prompt = `Build the following task cleanly, run verification checks/tests, and summarize every file changed:\n\n{task}`,
			harness = non_empty(args.primary_harness),
			model = non_empty(args.primary_model),
			project = project,
			fallback_project = fallback_project,
			device = device,
			cwd = cwd,
			workflow_id = workflow_id,
			attachments = attachments,
			handoff = {
				role = "reviewer",
				task = `Review: {clip(task, 60)}`,
				harness = reviewer_harness,
				model = non_empty(args.secondary_model),
				project = project,
				fallback_project = fallback_project,
				device = device,
				cwd = cwd,
				attachments = attachments,
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
			local ok, w_or_err = pcall(spawn_worker_internal, {
				captain_id = captain_id,
				role = `worker-{i}`,
				task = clip(sub, 72),
				prompt = `Overall goal:\n{task}\n\nYour dedicated subtask (#{i}):\n{sub}\n\nFocus strictly on this subtask and report a crisp summary of changes and verification.`,
				harness = non_empty(args.primary_harness),
				model = non_empty(args.primary_model),
				project = project,
				fallback_project = fallback_project,
				device = device,
				cwd = cwd,
				workflow_id = workflow_id,
				attachments = attachments,
			})
			if ok then
				table.insert(spawned, w_or_err)
			else
				add_needs_you_item(captain_id, "Worker spawn failed", tostring(w_or_err), nil)
			end
		end
		if #spawned == 0 then
			error("Failed to spawn any fanout workers", 0)
		end
	elseif preset == "compare" then
		local h1 = non_empty(args.primary_harness)
		local h2 = non_empty(args.secondary_harness)
		local role_a = if h1 then `candidate-A:{h1}` else "candidate-A"
		local role_b = if h2 then `candidate-B:{h2}` else "candidate-B"
		local function build_compare_prompt(candidate_label: string, peer_label: string): string
			return `[Compare 2 Agents Mode — {candidate_label} (running in parallel with {peer_label})]\n\n`
				.. `Task:\n{task}\n\n`
				.. `Safety & Comparison Guidelines:\n`
				.. `1. Another candidate agent is evaluating/solving this same task in parallel.\n`
				.. `2. Do NOT run destructive git commands (never run git reset --hard, git clean, git checkout --, or force-commit).\n`
				.. `3. Keep any workspace edits minimal and well-isolated, or provide a complete, self-contained proposed patch if concurrent file edits would conflict.\n`
				.. `4. Conclude your response with a structured comparison block:\n`
				.. `   - Approach Summary\n`
				.. `   - Files / Changes Proposed\n`
				.. `   - Key Trade-offs & Verification`
		end
		local ok1, w1_or_err = pcall(spawn_worker_internal, {
			captain_id = captain_id,
			role = role_a,
			task = clip(task, 72),
			prompt = build_compare_prompt("Candidate A", "Candidate B"),
			harness = h1,
			model = non_empty(args.primary_model),
			project = project,
			fallback_project = fallback_project,
			device = device,
			cwd = cwd,
			workflow_id = workflow_id,
			attachments = attachments,
		})
		if ok1 then
			table.insert(spawned, w1_or_err)
		else
			add_needs_you_item(captain_id, "Worker spawn failed", tostring(w1_or_err), nil)
		end

		local ok2, w2_or_err = pcall(spawn_worker_internal, {
			captain_id = captain_id,
			role = role_b,
			task = clip(task, 72),
			prompt = build_compare_prompt("Candidate B", "Candidate A"),
			harness = h2,
			model = non_empty(args.secondary_model),
			project = project,
			fallback_project = fallback_project,
			device = device,
			cwd = cwd,
			workflow_id = workflow_id,
			attachments = attachments,
		})
		if ok2 then
			table.insert(spawned, w2_or_err)
		else
			add_needs_you_item(captain_id, "Worker spawn failed", tostring(w2_or_err), nil)
		end

		if #spawned == 0 then
			error("Failed to spawn any comparison workers", 0)
		end
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

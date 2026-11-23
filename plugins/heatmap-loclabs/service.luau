--!strict
-- Heatmap-LocLabs' service: the commits this device's chats' and projects'
-- folders hold, for the year the grid shows, with each day's commits so the
-- window can list them under the pointer.
--
-- A folder's own git is asked plainly ("commands": ["git"]), once: every ref
-- since the grid's first Sunday. Every commit counts, whichever of the
-- person's emails authored it, and each is counted once, by its id, on the
-- day it was committed on this device. Supports either all local folders
-- (cached in the plugin store for 5 minutes) or a single allowed project
-- folder via `args.cwd` (validated against `zeron.folders()` and cached in
-- memory for 5 minutes); `force` re-reads immediately. Nothing of a
-- repository's files is read here.

local zeron = require("./zeron")("heatmap-loclabs")

local TTL = 300
local MOST_FOLDERS = 32
local MOST_PER_DAY = 120

local GIT_ENV: { [string]: string } = {
	LC_ALL = "C",
	GIT_TERMINAL_PROMPT = "0",
	GIT_OPTIONAL_LOCKS = "0",
}

local GIT_FLAGS: { string } = {
	"-c",
	"core.quotepath=off",
	"-c",
	"color.ui=false",
	"-c",
	"core.pager=cat",
	"-c",
	"core.fsmonitor=false",
}

local store = zeron.store("commits-v2", { at = 0 } :: any)
local project_cache: { [string]: any } = {}

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function split(text: string, sep: string): { string }
	local out: { string } = {}
	local from = 1
	while true do
		local at = string.find(text, sep, from, true)
		if not at then
			table.insert(out, string.sub(text, from))
			break
		end
		table.insert(out, string.sub(text, from, at - 1))
		from = at + #sep
	end
	return out
end

local function run(args: { string }, cwd: string): any?
	local full_args: { string } = {}
	for _, flag in GIT_FLAGS do
		table.insert(full_args, flag)
	end
	for _, arg in args do
		table.insert(full_args, arg)
	end
	local ok, result = pcall(function()
		return zeron.run("git", full_args, { cwd = cwd, timeout = 60, env = GIT_ENV }):await()
	end)
	if ok then
		return result
	end
	return nil
end

local function has_parent_traversal(path: string): boolean
	if string.find(path, "\0", 1, true) ~= nil then
		return true
	end
	local slash = string.gsub(path, "\\", "/")
	for seg in string.gmatch(slash, "[^/]+") do
		if seg == ".." then
			return true
		end
	end
	return false
end

-- Canonical comparison key for both Windows (drive/UNC, case-insensitive) and
-- POSIX (case-sensitive) paths, using `/` separators and preserving roots
-- (`c:/` or `/`).
local function normalize_key(path: string): string
	local s = string.gsub(trim(path), "\\", "/")
	if s == "" then
		return ""
	end
	if string.sub(s, 1, 2) == "//" then
		local rest = string.gsub(string.sub(s, 3), "/+", "/")
		rest = string.gsub(rest, "/+$", "")
		return string.lower("//" .. rest)
	end
	if string.match(s, "^[a-zA-Z]:") then
		s = string.gsub(s, "/+", "/")
		s = string.gsub(s, "/+$", "")
		if string.match(s, "^[a-zA-Z]:$") then
			s ..= "/"
		end
		return string.lower(s)
	end
	local leading = string.sub(s, 1, 1) == "/"
	s = string.gsub(s, "/+", "/")
	s = string.gsub(s, "/+$", "")
	if s == "" and leading then
		return "/"
	end
	return s
end

local function is_same_or_inside(target_key: string, folder_key: string): boolean
	if target_key == "" or folder_key == "" then
		return false
	end
	if target_key == folder_key then
		return true
	end
	if string.sub(folder_key, -1) == "/" then
		return string.sub(target_key, 1, #folder_key) == folder_key
	end
	local prefix = folder_key .. "/"
	return string.sub(target_key, 1, #prefix) == prefix
end

-- Verify `cwd` matches or sits inside one of this device's known chat/project
-- folders, without requiring a leading `/` so Windows drive paths work cleanly.
local function resolve_allowed_cwd(cwd: string, folders: { string }): (string?, string?)
	local raw = trim(cwd)
	if raw == "" or has_parent_traversal(raw) then
		return nil, nil
	end
	local target_key = normalize_key(raw)
	if target_key == "" then
		return nil, nil
	end
	for _, folder in folders do
		if type(folder) == "string" and folder ~= "" and not has_parent_traversal(folder) then
			local fk = normalize_key(folder)
			if is_same_or_inside(target_key, fk) then
				return raw, target_key
			end
		end
	end
	return nil, nil
end

local function default_since(): string
	local now = os.date("*t", os.time()) :: any
	local noon = os.time({ year = now.year, month = now.month, day = now.day, hour = 12, min = 0, sec = 0 })
	local back = noon - 364 * 86400
	local date = os.date("*t", back) :: any
	-- The Sunday on or before the same weekday a year ago: the grid's first
	-- column.
	return os.date("%Y-%m-%d", back - (date.wday - 1) * 86400)
end

local function scan_folders(list: { string }, since: string): any
	local counts: { [string]: number } = {}
	local commits: { [string]: { any } } = {}
	local seen_commits: { [string]: boolean } = {}
	local total = 0

	for _, folder in list do
		local log = run(
			{ "log", "--all", `--since={since}`, "--pretty=format:%H%x1f%at%x1f%an%x1f%s" },
			folder
		)
		if not log or log.status ~= 0 then
			continue
		end

		for line in string.gmatch(log.stdout, "[^\r\n]+") do
			local fields = split(line, "\31")
			local sha = trim(fields[1] or "")
			local at = tonumber(fields[2] or "")
			if #sha >= 7 and at and not seen_commits[sha] then
				seen_commits[sha] = true
				local day = os.date("%Y-%m-%d", at)
				counts[day] = (counts[day] or 0) + 1
				total += 1
				local held = commits[day]
				if not held then
					held = {}
					commits[day] = held
				end
				if #held < MOST_PER_DAY then
					table.insert(held, {
						sha = sha,
						at = at,
						author = trim(fields[3] or ""),
						subject = trim(fields[4] or ""),
					})
				end
			end
		end
	end

	local days: { [string]: any } = {}
	for day, n in counts do
		local held = commits[day] or {}
		table.sort(held, function(a: any, b: any): boolean
			return (a.at or 0) > (b.at or 0)
		end)
		days[day] = { n = n, commits = held }
	end

	return {
		at = os.time(),
		since = since,
		days = days,
		total = total,
	}
end

local function year(since: string, force: boolean, cwd: string?): any
	if cwd ~= nil then
		local folders: { string } = zeron.folders():await()
		local allowed_cwd, key = resolve_allowed_cwd(cwd, folders)
		if not allowed_cwd or not key then
			error("not_a_checkout: That folder isn't one of this device's chats or projects", 0)
		end
		local cached = project_cache[key]
		if
			not force
			and type(cached) == "table"
			and cached.since == since
			and os.time() - (tonumber(cached.at) or 0) < TTL
		then
			return cached
		end
		local answer = scan_folders({ allowed_cwd }, since)
		project_cache[key] = answer
		print(`heatmap-loclabs: project {allowed_cwd}, {answer.total} commits`)
		return answer
	end

	local cached = store:get() or {}
	if not force and cached.since == since and os.time() - (tonumber(cached.at) or 0) < TTL then
		return cached
	end

	local folders: { string } = zeron.folders():await()
	local seen_folders: { [string]: boolean } = {}
	local list: { string } = {}
	for _, folder in folders do
		local key = normalize_key(folder)
		if key ~= "" and not seen_folders[key] then
			seen_folders[key] = true
			table.insert(list, folder)
			if #list >= MOST_FOLDERS then
				break
			end
		end
	end

	local answer = scan_folders(list, since)
	store:set(answer)
	print(`heatmap-loclabs: {#list} folders, {answer.total} commits`)
	return answer
end

zeron.serve("year", function(args: any): any
	local since = if type(args) == "table" and type(args.since) == "string" then args.since else default_since()
	if not string.match(since, "^%d%d%d%d%-%d%d%-%d%d$") then
		since = default_since()
	end
	local force = type(args) == "table" and args.force == true
	local cwd: string? = if type(args) == "table" and type(args.cwd) == "string" and trim(args.cwd) ~= ""
		then args.cwd
		else nil
	return year(since, force, cwd)
end, { safe = true })

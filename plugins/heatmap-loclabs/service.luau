--!strict
-- Heatmap-LocLabs' service: the commits this device's chats' and projects'
-- folders hold, for the year the grid shows, with each day's commits so the
-- window can list them under the pointer.
--
-- A folder's own git is asked plainly ("commands": ["git"]), once: every ref
-- since the grid's first Sunday. Every commit counts, whichever of the
-- person's emails authored it, and each is counted once, by its id, on the
-- day it was committed on this device. The answer is kept five minutes,
-- because a window can close and open again; nothing of a repository's files
-- is read here.

local zeron = require("./zeron")("heatmap-loclabs")

local TTL = 300
local MOST_FOLDERS = 32
local MOST_PER_DAY = 40

local store = zeron.store("commits-v2", { at = 0 } :: any)

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
	local ok, result = pcall(function()
		return zeron.run("git", args, { cwd = cwd, timeout = 60 }):await()
	end)
	if ok then
		return result
	end
	return nil
end

-- A folder as one key: Windows keeps its paths without a difference in case
-- or a last slash, and a chat and its project often name the same one.
local function folder_key(path: string): string
	local key = string.gsub(path, "/", "\\")
	key = string.gsub(key, "\\+$", "")
	if string.match(key, "^%a:$") then
		key ..= "\\"
	end
	return string.lower(key)
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

local function year(since: string): any
	local cached = store:get() or {}
	if cached.since == since and os.time() - (tonumber(cached.at) or 0) < TTL then
		return cached
	end

	local folders: { string } = zeron.folders():await()
	local seen_folders: { [string]: boolean } = {}
	local list: { string } = {}
	for _, folder in folders do
		local key = folder_key(folder)
		if folder ~= "" and not seen_folders[key] then
			seen_folders[key] = true
			table.insert(list, folder)
			if #list >= MOST_FOLDERS then
				break
			end
		end
	end

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

	local answer = {
		at = os.time(),
		since = since,
		days = days,
		total = total,
	}
	store:set(answer)
	print(`heatmap-loclabs: {#list} folders, {total} commits`)
	return answer
end

zeron.serve("year", function(args: any): any
	local since = if type(args) == "table" and type(args.since) == "string" then args.since else default_since()
	if not string.match(since, "^%d%d%d%d%-%d%d%-%d%d$") then
		since = default_since()
	end
	return year(since)
end, { safe = true })

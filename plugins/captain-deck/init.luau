--!strict
-- Captain Deck: harness-agnostic multi-agent orchestration plugin for Zeron.
--
-- Wires:
-- - Headless service bridge (`client.luau`)
-- - Sidebar badges, hover card row, and chat header pill (`badges.luau`)
-- - Side panel Crew Inspector tab (`inspector.luau`)
-- - Dedicated Captain Deck sidebar page (`deck.luau`)
-- - Session context menus (Promote to Captain, Cross-Harness Review)
-- - Keyboard shortcut (`cmd+shift+o`) to open Captain Deck

local zeron = require("./zeron")("captain-deck")
local client = require("./client")(zeron)
local Badges = require("./badges")(zeron, client)
local Inspector = require("./inspector")(zeron, client)
local Deck = require("./deck")(zeron, client)

-- 1. Sidebar row badge (`.session-title` after)
zeron.place {
	at = ".session-title",
	after = function(): Node
		local sess = zeron.context("session")
		local id = if type(sess) == "table" and type(sess.id) == "string" then sess.id else ""
		local panel = zeron.context("panel")
		return Badges.SidebarBadge { session_id = id, panel = panel }
	end,
}

-- 2. Session hover card row (`.session-card-end` after)
zeron.place {
	at = ".session-card-end",
	after = function(): Node
		local sess = zeron.context("session")
		local id = if type(sess) == "table" and type(sess.id) == "string" then sess.id else ""
		return Badges.CardRow { session_id = id }
	end,
}

-- 3. Active chat header pill (`#page-title` after)
zeron.place {
	at = "#page-title",
	after = function(): Node
		local sess = zeron.context("session")
		local id = if type(sess) == "table" and type(sess.id) == "string" then sess.id else ""
		local panel = zeron.context("panel")
		return Badges.HeaderPill { session_id = id, panel = panel }
	end,
}

-- 4. Side panel Crew Inspector tab (`panel.tabs`)
zeron.tab("captain-inspector", function(tab: any): Node
	return Inspector { tab = tab }
end)

-- 5. Dedicated Captain Deck sidebar page (`pages.add`)
zeron.page {
	id = "captain-deck",
	title = zeron.t("page.title"),
	icon = "users-group-rounded",
	build = function(page: any): Node
		return Deck { page = page, panel = zeron.context("panel") }
	end,
}

-- 6. Right-click session context menus (`ui.add`)
zeron.menu {
	kind = "session",
	id = "promote-captain",
	label = zeron.s("menus.promote"),
	run = function(ctx: any)
		local sid = if type(ctx) == "table" and type(ctx.id) == "string" then ctx.id else nil
		if not sid or sid == "" then
			return
		end
		local existing = client.captain_of(sid)
		if existing ~= nil then
			client.focus_chat:set(sid)
			pcall(zeron.open, { session = sid })
			client.open_inspector(zeron.context("panel"), sid)
			zeron.toast("Already a Captain — opened in Captain Deck")
			return
		end
		local title = client.session_title(sid)
		client.call("promote_captain", { chat_id = sid, name = title }):after(function()
			client.focus_chat:set(sid)
			zeron.toast(zeron.s("toast.promoted"))
			pcall(zeron.open, { session = sid })
			client.open_inspector(zeron.context("panel"), sid)
		end, function() end)
	end,
}

zeron.menu {
	kind = "session",
	id = "cross-harness-review",
	label = zeron.s("menus.review"),
	run = function(ctx: any)
		local sid = if type(ctx) == "table" and type(ctx.id) == "string" then ctx.id else nil
		if not sid or sid == "" then
			return
		end
		local title = client.session_title(sid)
		local s = zeron.context_of("session", sid) or {}
		local existing_worker = client.worker_of(sid)
		local existing_captain = client.captain_of(sid)
		local last_reply = ""
		if existing_worker and type(existing_worker.last_reply) == "string" and existing_worker.last_reply ~= "" then
			last_reply = existing_worker.last_reply
		elseif existing_captain and type(existing_captain.digest) == "string" and existing_captain.digest ~= "" then
			last_reply = existing_captain.digest
		end

		local ctx_lines: { string } = {
			`Target Chat: "{title}" ({sid})`,
		}
		if type(s.project) == "string" and s.project ~= "" then
			table.insert(ctx_lines, `Project: {s.project}`)
		end
		if type(s.branch) == "string" and s.branch ~= "" then
			table.insert(ctx_lines, `Branch: {s.branch}`)
		end
		if type(s.cwd) == "string" and s.cwd ~= "" then
			table.insert(ctx_lines, `Working Directory: {s.cwd}`)
		end
		if last_reply ~= "" then
			table.insert(ctx_lines, `\nLatest Captured Summary / Reply:\n{last_reply}`)
		end

		local prompt = "Perform a thorough, read-only cross-harness code & solution review (do NOT edit files, stage, or commit unless explicitly asked):\n\n"
			.. table.concat(ctx_lines, "\n")
			.. "\n\nReview Checklist:\n"
			.. "1. Inspect `git status`, `git diff`, and recent working tree changes in the repository.\n"
			.. "2. Check for correctness, regressions, edge cases, type/lint issues, and adherence to project conventions.\n"
			.. "3. Report all findings clearly categorized into **Critical** and **Minor** with exact file paths and line numbers, and conclude with a merge readiness verdict."

		local reviewer_h = zeron.setting("default_reviewer_harness"):peek() or ""
		client.call("promote_captain", { chat_id = sid, name = title }):after(function()
			client.call("spawn_worker", {
				captain_id = sid,
				role = "reviewer",
				task = `Review: {title}`,
				harness = reviewer_h,
				project = s.project,
				device = s.device,
				cwd = s.cwd,
				prompt = prompt,
			}):after(function()
				client.focus_chat:set(sid)
				zeron.toast("Cross-harness reviewer spawned")
				pcall(zeron.open, { session = sid })
				client.open_inspector(zeron.context("panel"), sid)
			end, function() end)
		end, function() end)
	end,
}

-- 7. Command palette + shortcut (`cmd+shift+o` / `ctrl+shift+o`)
ui.command {
	id = "open-deck",
	title = "Open Captain Deck",
	key = "cmd+shift+o",
	run = function()
		pcall(zeron.open, { page = { plugin = "captain-deck", id = "captain-deck" } })
	end,
}

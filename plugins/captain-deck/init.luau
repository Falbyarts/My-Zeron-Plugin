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
		local id = zeron.need("session").id
		local panel = zeron.context("panel")
		return Badges.SidebarBadge { session_id = id, panel = panel }
	end,
}

-- 2. Session hover card row (`.session-card-end` after)
zeron.place {
	at = ".session-card-end",
	after = function(): Node
		local id = zeron.need("session").id
		return Badges.CardRow { session_id = id }
	end,
}

-- 3. Active chat header pill (`#page-title` after)
zeron.place {
	at = "#page-title",
	after = function(): Node
		local id = zeron.need("session").id
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
		if not sid then
			return
		end
		local title = client.session_title(sid)
		client.call("promote_captain", { chat_id = sid, name = title }):after(function()
			zeron.toast(zeron.s("toast.promoted"))
			zeron.open({ session = sid })
		end, function() end)
	end,
}

zeron.menu {
	kind = "session",
	id = "cross-harness-review",
	label = zeron.s("menus.review"),
	run = function(ctx: any)
		local sid = if type(ctx) == "table" and type(ctx.id) == "string" then ctx.id else nil
		if not sid then
			return
		end
		local title = client.session_title(sid)
		local s = zeron.context_of("session", sid) or {}
		local reviewer_h = zeron.setting("default_reviewer_harness"):peek() or ""
		client.call("promote_captain", { chat_id = sid, name = title }):after(function()
			client.call("spawn_worker", {
				captain_id = sid,
				role = "reviewer",
				task = `Review: {title}`,
				harness = reviewer_h,
				project = s.project,
				device = s.device,
				prompt = `Review the work done in chat "{title}" (read-only; do NOT edit files or commit unless asked). Inspect git status, git diff, and relevant files carefully. List Critical and Minor findings with file paths and line numbers, and state whether it is ready to merge.`,
			}):after(function()
				zeron.toast("Cross-harness reviewer spawned")
				zeron.open({ session = sid })
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
		zeron.open({ page = { plugin = "captain-deck", id = "captain-deck" } })
	end,
}

--!strict
-- Captain Deck: harness-agnostic multi-agent orchestration plugin for Zeron.
--
-- Wires:
-- - Headless service bridge (`client.luau`)
-- - Sidebar badges, hover card row, recoverable composer orchestrator strip
--   & keyboard-friendly native `/captain` slash row (`badges.luau`)
-- - Side panel Crew Inspector tab (`inspector.luau`)
-- - Solid floating Captain Deck card docked above `#chat-composer` (`deck.luau`)
--   with GPU WGSL accent perimeter glow and smart click-outside-to-close
-- - Session context menus (Promote to Captain, Cross-Harness Review)
-- - Keyboard shortcut (`cmd+shift+o`), `/captain` + Space/Enter & `/` row

local zeron = require("./zeron")("captain-deck")
local client = require("./client")(zeron)
local Badges = require("./badges")(zeron, client)
local Inspector = require("./inspector")(zeron, client)
local Deck: any = require("./deck")(zeron, client)

local ok_motion, motion_mod = pcall(require, "@ds/motion")
local motion: any = if ok_motion and type(motion_mod) == "table" then motion_mod else nil

local function is_reduced_motion(): boolean
	if motion and type(motion.reduced_now) == "function" then
		local ok, reduced = pcall(motion.reduced_now)
		if ok then
			return reduced == true
		end
	end
	return false
end

local ok_shader, DECK_BORDER_SHADER: any = pcall(function(): any
	if type(ui.shader) ~= "function" then
		return nil
	end
	return ui.shader([[
fn fill(input: FillInput) -> vec4<f32> {
  let ink = input.params[0];
  let half = input.size * 0.5;
  let p = input.p - half;
  let r = min(14.0, min(half.x, half.y) - 1.0);
  let q = abs(p) - (half - vec2<f32>(r));
  let sdf = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
  // Crisp outer ring around the rounded card edge (inside 0..-2.0px)
  let outer_cov = clamp(0.5 - sdf * input.scale, 0.0, 1.0);
  let inner_cov = clamp(0.5 - (sdf + 2.0) * input.scale, 0.0, 1.0);
  let ring = max(0.0, outer_cov - inner_cov);
  if (ring <= 0.001) { return vec4<f32>(0.0); }
  // Rotating orbital sweep angle (0..2pi)
  let ang = atan2(p.y, p.x);
  let lead = input.time * 6.2831853 - 3.14159265;
  var diff = ang - lead;
  diff = diff - 6.2831853 * round(diff / 6.2831853);
  // Primary comet + subtle opposite secondary highlight
  let beam1 = exp(-(diff * diff) / 0.36);
  var diff2 = diff + 3.14159265;
  diff2 = diff2 - 6.2831853 * round(diff2 / 6.2831853);
  let beam2 = 0.45 * exp(-(diff2 * diff2) / 0.50);
  let glow = clamp(0.24 + 0.76 * max(beam1, beam2), 0.0, 1.0);
  // Subtle brighter highlight at beam peak
  let peak = max(beam1, beam2 * 0.5);
  let lift = select(vec3<f32>(0.0), vec3<f32>(1.0), dot(ink.rgb, vec3<f32>(0.2126, 0.7152, 0.0722)) > 0.45);
  let col = mix(ink.rgb, lift, 0.25 * peak);
  return vec4<f32>(col, ink.a * ring * glow);
}
]])
end)
if not ok_shader then
	DECK_BORDER_SHADER = nil
end

local DEFAULT_COMPOSER_W = 720
local DEFAULT_COMPOSER_H = 78
local DECK_CARD_H = 440
local DOCK_GAP = 10

local left_edge = ui.ref()

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

-- 3. Side panel Crew Inspector tab (`panel.tabs`)
zeron.tab("captain-inspector", function(tab: any): Node
	return Inspector { tab = tab }
end)

-- 4a. Zero-width marker before `#chat-composer` to measure exact live composer width.
zeron.place {
	at = "#chat-composer",
	before = function(): Node
		return ui.div {
			ref = left_edge,
			w = 0,
			h = 0,
			shrink = 0,
			pointer_events = "none",
		}
	end,
}

-- 4b. Smart click-outside-to-close backdrop strictly before `#chat-composer-dock`.
zeron.place {
	at = "#chat-composer-dock",
	before = function(): Node
		return ui.show(function(): boolean
			return client.deck_open:get() == true
		end, ui.div {
			id = "captain-deck-backdrop",
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			bg = "#00000000",
			pointer_events = "auto",
			focus_on_press = false,
			on_press = function()
				local dirty = type(client.is_deck_dirty) == "function" and client.is_deck_dirty()
				if dirty then
					zeron.toast("Mission draft in progress — click Close to dismiss")
				else
					client.close_deck()
				end
			end,
		})
	end,
}

-- 4c. Solid floating Captain Deck card & Recoverable Composer Orchestrator Strip docked directly above `#chat-composer`.
zeron.place {
	at = "#chat-composer",
	after = function(): Node
		local right_edge = ui.ref()
		local route = zeron.live("route")
		local captured_panel: any = nil
		pcall(function()
			captured_panel = zeron.context("panel")
		end)

		local measured_w = ui.use_state(DEFAULT_COMPOSER_W)
		local measured_h = ui.use_state(DEFAULT_COMPOSER_H)
		local measured_top_y = ui.use_state(520)

		local function edge_elem(ref: any): any
			local ok, el = pcall(function(): any
				return ref:peek()
			end)
			if ok and el ~= nil then
				return el
			end
			local ok2, list = pcall(function(): any
				return ref:elements()
			end)
			if ok2 and type(list) == "table" and list[1] ~= nil then
				return list[1]
			end
			return nil
		end

		local function update_height(raw_h: any)
			if type(raw_h) == "number" and raw_h >= 36 then
				local h = math.clamp(math.floor(raw_h + 0.5), 40, 480)
				if math.abs(measured_h:peek() - h) >= 1 then
					measured_h:set(h)
				end
			end
		end

		local function measure_composer()
			local le = edge_elem(left_edge)
			local re = edge_elem(right_edge)
			if le ~= nil and re ~= nil and type(le.x) == "number" and type(re.x) == "number" then
				local raw_w = re.x - le.x
				if raw_w >= 160 then
					local w = math.clamp(math.floor(raw_w + 0.5), 320, 1400)
					if math.abs(measured_w:peek() - w) >= 1 then
						measured_w:set(w)
					end
				end
			end
			if re ~= nil then
				if type(re.y) == "number" and re.y > 0 then
					local ty = math.floor(re.y + 0.5)
					if math.abs(measured_top_y:peek() - ty) >= 1 then
						measured_top_y:set(ty)
					end
				end
				if type(re.h) == "number" then
					update_height(re.h)
				elseif type(re.height) == "number" then
					update_height(re.height)
				end
			end
		end

		local function is_chat_route(): boolean
			local where = route()
			if type(where) ~= "table" then
				return false
			end
			return where.name == "home" or where.name == "session"
		end

		local function active_sid(): string
			local where = route()
			if type(where) == "table" and where.name == "session" and type(where.session) == "string" then
				return where.session
			end
			return ""
		end

		local function is_dock_active(): boolean
			if not is_chat_route() then
				return false
			end
			if client.deck_open:peek() == true then
				return true
			end
			local sid = active_sid()
			if sid == "" then
				return false
			end
			return client.captain_of(sid) ~= nil or client.worker_of(sid) ~= nil
		end

		-- Keyboard-only `/captain` + Space/Enter trigger without needing mouse click.
		local last_triggered_draft = ""
		ui.effect(function()
			local ok_d, d = pcall(zeron.draft)
			local txt = if ok_d and type(d) == "table" and type(d.text) == "string" then d.text else ""
			if txt == "" then
				last_triggered_draft = ""
				return
			end
			local matched = false
			local cleaned = ""
			local cmds = { "captain", "captain%-deck", "deck" }
			for _, cmd in cmds do
				if string.match(txt, `^%s*/{cmd}%s+$`) then
					matched = true
					cleaned = ""
					break
				end
				local prefix = string.match(txt, `^(.-)%s+/{cmd}%s+$`)
				if prefix ~= nil then
					matched = true
					cleaned = prefix
					break
				end
			end
			if matched then
				if txt ~= last_triggered_draft then
					last_triggered_draft = txt
					pcall(zeron.compose, cleaned, { replace = true })
					client.open_deck()
				end
			else
				last_triggered_draft = ""
			end
		end)

		-- Re-measure on window resize, route transitions, and Deck open/close.
		ui.effect(function()
			local win = (ui :: any).window
			if win ~= nil and win.size ~= nil then
				pcall(function()
					win.size:get()
				end)
			end
			route()
			client.deck_open:get()
			pcall(zeron.window, true)
			measure_composer()
			ui.after(0, measure_composer)
			ui.after(48, measure_composer)
		end)

		-- Catch sidebar drag, panel open/close, and multiline composer growth only while visible.
		ui.on_mount(function()
			ui.after(0, measure_composer)
			ui.after(64, measure_composer)
			ui.every(200, function()
				local ok_win, win_state = pcall(zeron.window, true)
				local win_shown = if ok_win and type(win_state) == "table" then win_state.shown ~= false else true
				if win_shown and is_dock_active() then
					measure_composer()
				end
			end)
		end)

		local function composer_w(): number
			return measured_w:get()
		end

		local function deck_card_h(): number
			local top_y = measured_top_y:get()
			local max_avail = math.floor(top_y - 64)
			return math.clamp(max_avail, 240, DECK_CARD_H)
		end

		local function dock_mode(): string
			if not is_chat_route() then
				return "hidden"
			end
			if client.deck_open:get() == true then
				return "deck"
			end
			return "strip"
		end

		return ui.div {
			ref = right_edge,
			relative = true,
			w = 0,
			h_full = true,
			shrink = 0,
			overflow = "visible",
			pointer_events = "none",
			on_resize = function(size: any)
				if type(size) == "table" then
					if type(size.h) == "number" then
						update_height(size.h)
					elseif type(size.height) == "number" then
						update_height(size.height)
					end
				end
				measure_composer()
			end,
			ui.div {
				id = "captain-deck-composer-dock",
				absolute = true,
				right = 0,
				bottom = function(): number
					return measured_h:get() + DOCK_GAP
				end,
				w = composer_w,
				overflow = "visible",
				pointer_events = "none",
				ui.presence(dock_mode, function(mode: string): Node
					if mode == "hidden" then
						return ui.div { pointer_events = "none" }
					end
					local ok_p, ctx_panel = pcall(zeron.context, "panel")
					local active_panel = if ok_p and ctx_panel ~= nil then ctx_panel else captured_panel
					if mode == "deck" then
						local border_playing = false
						local inner_card = ui.column {
							class = "captain-deck-floating-card",
							w_full = true,
							h_full = true,
							rounded = "$radius.xl",
							bg = "$popover.bg",
							overflow = "hidden",
							Deck { panel = active_panel, on_close = client.close_deck },
						}
						if DECK_BORDER_SHADER ~= nil then
							return ui.overlay {
								class = "captain-deck-floating-frame",
								pointer_events = "auto",
								w_full = true,
								h = deck_card_h,
								p = 2,
								rounded = "$radius.xl",
								bg = "$popover.bg",
								shadow = "$zeron.dialog.shadow",
								overflow = "hidden",
								inner_card,
								ui.div {
									absolute = true,
									left = 0,
									right = 0,
									top = 0,
									bottom = 0,
									pointer_events = "none",
									bg_shader = DECK_BORDER_SHADER,
									shader_params = { "$accent", { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } },
									on_visible = function(visible: boolean, el: Element)
										if visible then
											if not border_playing and not is_reduced_motion() and type(anime) == "table" and type(anime.animate) == "function" then
												border_playing = true
												pcall(function()
													anime.animate(el, {
														shaderTime = { 0, 1 },
														duration = 4500,
														loop = true,
														ease = "linear",
														frameRate = 30,
													})
												end)
											end
										elseif border_playing then
											border_playing = false
											pcall(function()
												if type(anime) == "table" and anime.utils and type(anime.utils.remove) == "function" then
													anime.utils.remove(el)
												end
											end)
										end
									end,
								},
							}
						end
						return ui.column {
							class = "captain-deck-floating-frame",
							pointer_events = "auto",
							w_full = true,
							h = deck_card_h,
							p = 2,
							rounded = "$radius.xl",
							bg = "$popover.bg",
							border = 1.5,
							border_color = "$accent",
							shadow = "$zeron.dialog.shadow",
							overflow = "hidden",
							inner_card,
						}
					end
					return Badges.ComposerOrchestratorStrip {
						session_id = active_sid,
						panel = active_panel,
					}
				end, { w_full = true, pointer_events = "none" }),
			},
		}
	end,
}

-- 5. Composer slash command `/captain` (natively scrollable inside `/` list + empty fallback)
zeron.place {
	at = "#mention-1",
	before = function(): Node
		return Badges.SlashCommandRow {}
	end,
}

zeron.place {
	at = "#mention-empty",
	before = function(): Node
		return Badges.SlashCommandRow { empty_fallback = true }
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

		local raw_reviewer_h = zeron.setting("default_reviewer_harness"):peek()
		local reviewer_h = ""
		if type(client.sanitize_harness) == "function" then
			local ok_sh, sanitized = pcall(client.sanitize_harness, raw_reviewer_h)
			if ok_sh and type(sanitized) == "string" then
				reviewer_h = sanitized
			end
		elseif type(raw_reviewer_h) == "string" then
			local first = string.match(raw_reviewer_h, "^%s*([^,%s]+)")
			if type(first) == "string" then
				reviewer_h = string.lower(first)
			end
		end

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
		client.toggle_deck()
	end,
}
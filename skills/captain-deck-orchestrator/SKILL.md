---
name: captain-deck-orchestrator
description: >-
  MANUAL / EXPLICIT OPT-IN ONLY. Use this skill ONLY when the user explicitly asks to use
  Captain Deck, Captain Deck orchestrator tools (`captain_*`), or manually invokes this skill
  with an orchestrator jobdesk. NEVER activate automatically for ordinary subagent delegation,
  general coding, research, or normal multi-step tasks.
---

# Captain Deck Orchestrator

Orchestrate multi-agent crews across any Zeron harness (Claude Code, Codex, OpenCode, Antigravity, Pi, Hermes, Cursor, or any ACP harness) using Captain Deck's native `captain_*` tools.

## 1. Activation Contract

- **Use ONLY when** the user explicitly asks to use Captain Deck, names `captain_*` / Captain Deck orchestrator tools, or manually invokes this skill with an orchestrator jobdesk.
- **Do NOT use** for ordinary subagent delegation, single-agent coding, quick research, or standard multi-step work — use normal built-in subagents or direct tools instead.

## 2. Fast Pre-Flight Discovery (Never Guess IDs)

Run these read-only checks before promoting or spawning:

1. Call `whoami` -> capture the calling `chat.id`, `deviceId`, `project.id`, and `cwd`.
2. Call `captain_status {}` -> check whether the current chat is already a Captain or has active crew/unresolved `needs_you` items.
3. **Only when the user requests a specific or alternate harness/model**: call `list_harnesses`, then `list_models(harness)` to get exact harness and model IDs. Never invent or guess model strings.

## 3. Exact Reference of All 6 Captain Deck Tools

Depending on the harness, tools are exposed as `captain_<name>` or `captain_deck__captain_<name>`.

| Tool | Required | Optional Parameters & Defaults | Purpose |
| :--- | :--- | :--- | :--- |
| `captain_promote` | *(none)* | `chat_id` (default: calling chat), `name`, `mission`, `rules`, `auto_report` (`boolean`, default `true`) | Promote a chat into a Captain with persistent mission & shared crew rules. |
| `captain_spawn_worker` | `prompt` | `captain_id` (default: calling chat; auto-promotes), `role`, `task`, `harness` (default: Zeron default), `model`, `effort`, `project`, `device`, `cwd`, `auto_report` (default: Captain's setting), `handoff` (`object`) | Spawn a new worker chat on any harness/model/project/device under a Captain. |
| `captain_status` | *(none)* | `captain_id` (default: caller's Captain, or all Captains if unassigned), `include_replies` (`boolean`, default `true`) | Inspect Captain state, crew statuses, latest reply excerpts, rules, digest, and `needs_you`. |
| `captain_message_worker` | `chat_id`, `text` | `mode` (`"queue"` \| `"steer"`, default `"queue"`) | Send a follow-up (`queue`) or mid-turn redirect (`steer`) to any worker or Captain chat. |
| `captain_attach_worker` | `worker_chat` | `captain_id` (default: calling chat), `role`, `task` | Attach an existing Zeron chat as a tracked worker under a Captain. |
| `captain_update_digest` | *(none)* | `captain_id` (default: calling chat or its parent Captain), `mission`, `rules`, `digest`, `flag_needs_you` (`object`), `resolve_item_id` (`string`) | Update persistent mission/rules/digest, escalate a blocker, or resolve a Needs You item. |

### Exact Nested Object Schemas

- **`captain_spawn_worker.handoff`**: automatically spawns a next-stage worker when the primary worker completes cleanly.
  - `role?` (`string`) — next worker role (e.g. `"reviewer"`).
  - `task?` (`string`) — short task summary shown in the Crew tree.
  - `harness?` (`string`), `model?` (`string`), `effort?` (`string`) — target agent override.
  - `prompt_template?` (`string`) — prompt for the next worker; include `{{REPORT}}` to inject the previous worker's final reply.
- **`captain_update_digest.flag_needs_you`**: surfaces an escalation in Captain Deck's Needs You panel and posts a Zeron notification.
  - `title?` (`string`) — short action/decision headline.
  - `detail?` (`string`) — context and exact choice needed from the human.
  - `worker_chat?` (`string`) — related worker chat id (for one-click Open).

## 4. Orchestration Playbooks

### Playbook 1: Parallel Crew Fan-Out

1. Call `captain_promote` once on the current chat with a concise `name`, `mission`, and shared `rules` (automatically prepended to every spawned worker).
2. Partition the work into strictly disjoint file/module scopes so parallel writers never collide.
3. Spawn workers in parallel via `captain_spawn_worker` (e.g. `researcher`, `builder`, `verifier`), passing `project`/`cwd`/`device` when needed and crisp `role` + `task` labels.
4. Collect results via incoming `[Captain Deck · Worker Update]` auto-reports, or check progress with `captain_status` / `wait_for_turn`.
5. Synthesize outcomes and write a concise summary via `captain_update_digest { digest = "..." }`.

### Playbook 2: Build -> Cross-Harness Review (`handoff`)

Use `handoff` for a zero-babysitting two-stage pipeline:

```json
{
  "role": "builder",
  "task": "Implement feature X + tests",
  "harness": "<primary-harness>",
  "prompt": "Implement feature X in src/x.ts, run unit tests, and summarize every changed file.",
  "handoff": {
    "role": "reviewer",
    "task": "Review feature X (read-only)",
    "harness": "<other-harness>",
    "prompt_template": "Read-only review. DO NOT edit files or commit.\nInspect git diff and changed files, list Critical vs Minor issues with file:line.\n\nBuilder report:\n{{REPORT}}"
  }
}
```

When the builder finishes cleanly, Captain Deck spawns the reviewer automatically and injects the builder's final reply into `{{REPORT}}`.

### Playbook 3: Mid-Turn Steer vs Queue

- **`mode: "steer"`**: use when a running worker is heading down the wrong path or requirements changed right now — delivers immediately at the next input boundary.
- **`mode: "queue"`** (default): use for a clean follow-up instruction after the worker finishes its current turn.

```json
{
  "chat_id": "<worker_chat_id>",
  "mode": "steer",
  "text": "Stop editing foo.ts — keep changes strictly inside bar.ts and re-run tests."
}
```

### Playbook 4: Human-Touch Escalation & Digest Hygiene

- Keep `digest` short, current, and scannable (status, completed milestones, active blockers) using `captain_update_digest`.
- Whenever a destructive action, product decision, credential, or unresolvable blocker requires the human, call:

```json
{
  "digest": "Builder finished auth refactor; waiting on human decision for migration strategy.",
  "flag_needs_you": {
    "title": "Choose DB migration mode",
    "detail": "Option A: zero-downtime dual-write. Option B: offline schema swap.",
    "worker_chat": "<worker_chat_id>"
  }
}
```

- Once the human decides or the blocker clears, read the item `id` from `captain_status` and close it with `captain_update_digest { resolve_item_id = "<item_id>" }`.

## 5. Worker Prompt & Hygiene Rules

1. **Crisp `role` and `task` always**: use short standard roles (`researcher`, `builder`, `reviewer`, `verifier`, `tester`, `planner`) and a concise `task` — Zeron's sidebar highlights `role` and the Crew tree shows `task`.
2. **Disjoint write ownership**: every parallel writer must receive an explicit allow-list of files/modules it owns and a clear DO NOT TOUCH boundary for peer files.
3. **Read-only guardrails**: explicitly instruct `researcher`, `reviewer`, and `verifier` workers: *"Read-only — DO NOT edit files, stage changes, or run mutating commands."*
4. **Respect Zeron's 16-message auto-report loop guard**: Zeron halts consecutive automated chat-to-chat loops after 16 messages. Batch instructions and synthesize multiple worker reports in one turn instead of ping-ponging tiny messages.
5. **No unrequested destructive actions**: never commit, push, force-reset, or delete user files/branches unless the user explicitly authorized it.

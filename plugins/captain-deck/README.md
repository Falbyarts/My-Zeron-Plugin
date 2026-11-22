# Captain Deck

Harness-agnostic multi-agent orchestration plugin for **Zeron**.

Orchestrate Captains, Crew trees, cross-harness workflows, live attention digests, and agent-to-agent tools across **every harness** Zeron supports (Pi, Claude Code, Codex, OpenCode, Antigravity, Hermes, Cursor, and any ACP agent) — with zero harness lock-in and zero external CLI dependencies.

## Highlights

- **Captains & Crew Trees** — Promote any existing chat into a Captain or launch a new one on any harness, then spawn or attach workers under it with clear visual hierarchy.
- **100% Harness-Agnostic** — Mix and match any harness and model per worker (e.g. build with OpenCode/Pi, review with Antigravity/Claude Code).
- **Attention Digest ("Needs You")** — Headless background service tracks `turn.started`, `turn.finished`, `turn.errored`, and `chat.awaiting_input` across all harnesses, auto-reports to Captains, and notifies you only when a worker needs you.
- **Cross-Harness Workflows** — Built-in presets for **Build -> Cross-Harness Review** (automatic handoff on completion), **Plan & Fan-Out Swarm**, and **Parallel Harness Compare**.
- **Native Agent Tools** — Exposes `captain_status`, `captain_promote`, `captain_spawn_worker`, `captain_message_worker`, `captain_attach_worker`, and `captain_update_digest` to every agent in Zeron.

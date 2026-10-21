# Loop prompt

Run from the repo root with self-pacing:

```
/loop <paste the block below>
```

---

Continue the Wind Watch build as the orchestrator. Read `progress.md` and `docs/IMPLEMENTATION_PLAN.md` first; the plan's §0 and §5 are binding.

Each iteration:

1. Do any `todo` task in workstream A or F yourself, in order; they are small.
2. For B, C/D, and E: pick every `todo` task whose dependencies are `done`, respecting one agent per workstream at a time and at most three agents running at once. Spawn one `general-purpose` agent per task with the full brief from the plan §3 plus the rules block from §5, the task's verification command, and the paths it owns. Mark the task `in-progress` with the agent name.
3. When an agent reports, re-run the task's verification command yourself. For UI tasks, open the screenshots and check them against HANDOFF §11. Only on a pass: mark `done`, record the commit, and commit that task's files with message `<ID>: <one line>` plus the attribution trailer. On a fail: re-dispatch the same agent once with the failure output; on a second fail mark `blocked` with what was tried.
4. Copy any decision an agent made into Decisions, and any open question into Questions for Henry with the default you took. Never wait on Henry.
5. Update `Last updated` in `progress.md` and commit it with each task commit.
6. Stop the loop (`stop: true`) when every task is `done`, `blocked`, or `other-machine` and F2 is committed. Otherwise schedule the next wakeup: a long fallback while agents are running, since their completion re-invokes you.

Rules: prepend `$HOME/.nvm/versions/node/v24.13.0/bin` to PATH for anything under `server/` or `web/`; use `pnpm`, not `npm`; install tools only via `brew` or `pnpm`; never commit `apple/Config/Local.xcconfig` or any secret; never push; never fabricate an agent's result, wait for its notification.

---
trigger: always_on
description: Behavior when the user types day ending
---

# Day Ending Rule

When the user types `day ending`, treat it as the explicit end-of-day command and as explicit permission to finalize the day’s repository state.

On `day ending`:

1. Check git state, including current branch, uncommitted changes, untracked files, local commits not pushed, and remote sync status.
2. If there are uncommitted or untracked project changes, inspect them for secrets or unsafe content before committing.
3. Commit all approved/day-work project changes with a clear summary message unless there is a safety blocker.
4. If there are local commits not pushed, push them to the configured remote branch unless pushing is blocked by authentication, missing remote, branch ambiguity, failing safety checks, or user-visible risk.
5. Never push secrets, credentials, `.env` files, session files, or unsafe/generated artifacts. Stop and report if such files are present.
6. Run or report relevant verification for the day’s work when practical; if verification is not run, clearly state why.
7. Provide mandatory day-progress statistics, including files changed, commits created, tests/checks run, tests passed/failed/skipped when known, important findings, unresolved risks, and next recommended steps.
8. Summarize exactly what was investigated, changed, verified, pushed, and left unresolved.
9. Never present the day as fully closed if known blockers, unpushed safe commits, unresolved audit gaps, failed checks, or unverified assumptions remain.

---
trigger: always_on
description: Behavior when the user types day beginning
---

# Day Beginning Rule

When the user types `day beginning`, treat it as the explicit start-of-day command.

On `day beginning`:

1. Re-read and follow the active project rules before acting.
2. Check repository state, including current branch, latest commits, and uncommitted/untracked changes.
3. Summarize the starting state of the day: branch, clean/dirty status, recent work context, known open tasks, known unresolved risks, and recommended priorities.
4. Clarify the user’s goal, target environment, and success criteria when they are not explicit.
5. For test work, remember that the goal is trustworthy behavior detection, not making every test green.
6. Do not edit code, tests, deployment scripts, configuration, or documentation until the user explicitly approves the specific change.
7. If any operation may touch ERPNext servers, deployments, Docker, bench, SSH, or live data, follow the prod-vs-test safety rule first.

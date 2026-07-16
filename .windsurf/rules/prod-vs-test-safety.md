---
trigger: always_on
description: Safety rule for any prod/test server operation
---

# Prod vs Test Safety Rule

This workspace has two live, separate ERPNext server environments on the same VPS:
- **Prod**: `https://erpnext.am`
- **Test**: `https://test.erpnext.am`

Full details (containers, ports, volumes, credentials, isolation/shared caveats): `docs/infrastructure-test-vs-prod-environments.md`.

## Mandatory steps before ANY server operation

Applies to any request that involves operating on, deploying to, restarting, backing up, restoring, migrating, running scripts against, or otherwise touching either ERPNext server instance (via SSH, `docker exec`, `bench`, deploy scripts, etc.).

1. **Always read `docs/infrastructure-test-vs-prod-environments.md` first**, before taking any action — even if the user's request already explicitly says "prod" or "test". Container names, ports, volumes, and credentials differ between the two and must be re-confirmed from that doc each time, not assumed from memory of a prior session.
2. **If the request does not explicitly say which environment** (prod or test), stop and ask the user which one before doing anything. Do not default to either.
3. **Never run a command against prod containers/site (`frappe-*`, site `161.97.83.156`) unless the target environment was explicitly confirmed as prod** — either stated up front by the user, or answered when asked in step 2.
4. Double-check container/site names against the doc before executing — `frappe-backend-1` = prod, `frappe-test-backend-1` = test. Do not guess from naming patterns alone.
5. Deploy scripts live under dedicated folders, never directly in `deploy/`: `deploy/prod/` targets prod only, `deploy/test/` targets test only. When writing a new script that should support both, create one copy per folder (each with its own hardcoded credentials, e.g. the `export.ps1` pair) rather than a single script with an environment flag — the folder location must always be sufficient on its own to tell which environment a script touches.

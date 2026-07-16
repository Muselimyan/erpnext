# Infrastructure — Test vs Prod Environment Separation

> **Contains credentials.** This file documents real server passwords for the internal test instance. Do not publish this repo publicly without redacting the Credentials section, and rotate these values if that ever happens.

**Server:** VPS `161.97.83.156` (root SSH access, key `$env:USERPROFILE\.ssh\vps_erpnext2`).
**Created:** 2026-07-15. Test instance was seeded as a one-time full copy of prod (DB + files) at that date — see "Refreshing test from prod" below to repeat later.

## 1) Summary table

| | **Prod** | **Test** |
|---|---|---|
| Public URL | `https://erpnext.am` | `https://test.erpnext.am` |
| Docker Compose project | `frappe` | `frappe-test` |
| Compose file (on server) | `/home/vahe/frappe-compose.yml` | `/home/vahe/frappe-test-compose.yml` |
| Compose file (in repo) | not tracked in repo | `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\frappe-test-compose.yml` |
| Container name prefix | `frappe-*-1` (e.g. `frappe-backend-1`) | `frappe-test-*-1` (e.g. `frappe-test-backend-1`) |
| Site name (inside bench) | `161.97.83.156` | `test.erpnext.am` |
| Frontend published port | `8080` (host, UFW-blocked externally) | `8081` (host, UFW-blocked externally) |
| DB volume | `frappe_db-data` | `frappe-test_db-data` |
| Sites volume | `frappe_sites` | `frappe-test_sites` |
| Redis queue volume | `frappe_redis-queue-data` | `frappe-test_redis-queue-data` |
| Docker network | `frappe_default` | `frappe-test_default` |
| Nginx vhost (server) | `/etc/nginx/sites-available/erpnext.am` | `/etc/nginx/sites-available/test.erpnext.am` |
| Nginx vhost (in repo) | not tracked in repo | `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\test.erpnext.am.nginx.conf` |
| All scripts (in repo) | `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\prod\` | `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\` |
| App image | `frappe/erpnext:v16.14.0` (shared cached layers, read-only) | same |
| Auto-backup (Ofelia cron) | every 6h, `bench --site all backup` | every 6h (own `frappe-test-cron-1`, independent of prod) |

## 2) Credentials (test instance only)

| Item | Value |
|---|---|
| Admin login | `Administrator` / `TestAdmin123!` (change after first login) |
| MariaDB root password (`frappe-test-db-1` only) | `tSt7f92k1QzR` |
| `encryption_key` | Deliberately **same as prod's** — see caveat below |
| REST API key/secret (`Administrator`, used by `deploy/export.ps1 -Env Test`) | `af78cbd691f0b2e` / `b26698573b80f5e` |

Prod's MariaDB root password lives in `/home/vahe/frappe-compose.yml` on the server (`db.environment.MYSQL_ROOT_PASSWORD`) — not duplicated here.

## 3) What is fully isolated

- **Containers**: separate processes for db/redis/backend/frontend/websocket/scheduler/queues/cron. `frappe-test-*` never touches `frappe-*`.
- **Storage**: separate named Docker volumes → separate directories on disk (`/var/lib/docker/volumes/frappe_db-data/_data` vs `/var/lib/docker/volumes/frappe-test_db-data/_data`). No shared files, no shared MySQL/Redis data.
- **Network**: separate Docker bridge networks (`frappe_default` vs `frappe-test_default`) — containers in one stack cannot resolve or reach containers in the other by name.
- **Ports/routing**: `8080` vs `8081`, both denied externally by UFW; only the host's Nginx (distinct vhost per subdomain) routes traffic in.

## 4) What is intentionally shared

- **Host VPS**: same CPU/RAM/disk pool. Not app-level sharing, just resource neighbors (currently large headroom: 8 CPUs, ~20GB RAM free, ~180GB disk free as of 2026-07-15).
- **Base Docker image**: both use cached `frappe/erpnext:v16.14.0` layers — same app/code version, read-only, no state coupling.
- **Public IP**: both reachable on `161.97.83.156`, distinguished only by subdomain/Host header at the host Nginx layer.
- **`encryption_key`**: copied from prod into test on purpose, so the cloned encrypted `Password`-fieldtype values (API keys/integration secrets) would decrypt correctly after restore. Means: anyone with DB access to the test box can decrypt the same secrets as prod. Acceptable for now since both boxes are behind the same root SSH access, but not a fully independent secret.
- **Data content, at time of cloning**: byte-for-byte snapshot of prod as of the backup timestamp. Diverges immediately as either instance is used.

## 5) DNS

Cloudflare, proxied (orange cloud), same as root domain (origin uses plain HTTP on port 80, Cloudflare terminates TLS):
- Type `A`, Name `test`, Content `161.97.83.156`, Proxied.

## 6) How the test instance was built (repeatable recipe)

1. Full backup of prod with files:
   `docker exec frappe-backend-1 bench --site 161.97.83.156 backup --with-files`
2. Copy `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\frappe-test-compose.yml` to the server (`/home/vahe/frappe-test-compose.yml`) and start it:
   `docker compose -p frappe-test -f frappe-test-compose.yml up -d`
3. Copy the prod backup files (`*-database.sql.gz`, `*-files.tar`, `*-private-files.tar`) out of `frappe-backend-1` and into `frappe-test-backend-1` via `docker cp` (through a host temp dir).
4. Create the site and restore:
   ```
   bench new-site test.erpnext.am --mariadb-root-password <pw> --admin-password <pw>
   bench --site test.erpnext.am restore <database.sql.gz> --mariadb-root-password <pw> \
     --with-public-files <files.tar> --with-private-files <private-files.tar>
   ```
5. Align config so restored encrypted fields decrypt and custom scripts run:
   ```
   bench --site test.erpnext.am set-config -g encryption_key '<prod encryption_key>'
   bench --site test.erpnext.am set-config -g developer_mode 1
   bench --site test.erpnext.am set-config -g server_script_enabled 1
   bench --site test.erpnext.am set-config -g host_name 'https://test.erpnext.am'
   ```
6. Add the Nginx vhost (`@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\test.erpnext.am.nginx.conf`) to `/etc/nginx/sites-enabled/`, `nginx -t && systemctl reload nginx`.
7. `ufw deny 8081/tcp` (and `v6`) so the port is only reachable through Nginx.
8. Add the Cloudflare DNS record (section 5).

## 7) Refreshing test from prod later

Repeat steps 1, 3, 4, 5 above (skip stack creation/Nginx/DNS/UFW — already in place). This overwrites all data currently in the test instance.

## 8) Tearing down test (if no longer needed)

```
docker compose -p frappe-test -f /home/vahe/frappe-test-compose.yml down -v
```
`-v` also removes the volumes (irreversible data loss for the test instance only — prod is untouched). Then remove the Nginx vhost symlink, `ufw delete` the 8081 rules, and remove the Cloudflare DNS record.

## 9) Deploy scripts folder split — deploy/prod/ vs deploy/test/

All server-side scripts (PowerShell + Python) live under one of two dedicated folders, so the target environment is unambiguous from the file location alone — no flags to get wrong:
- `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\prod\` — targets `https://erpnext.am` only.
- `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\` — targets `https://test.erpnext.am` only.

Most scripts in `deploy/prod/` resolve their API credentials by reading `deploy/prod/export.ps1` (same folder, via `$PSScriptRoot`) — moving a script between folders is not just a file move, it also repoints which environment it talks to. When adding a **new** script that should be usable against both environments, create one copy in each folder (see the `export.ps1` pair below as the template) rather than parametrizing a single shared script — this keeps the "no ambiguity from folder alone" property intact per the `.windsurf/rules/prod-vs-test-safety.md` rule.

## 10) Exporting prod/test and diffing them

`@c:\Users\Vahe\CascadeProjects\erpnext\deploy\prod\export.ps1` and `@c:\Users\Vahe\CascadeProjects\erpnext\deploy\test\export.ps1` each pull schema (Custom Fields, Client/Server Scripts, Workflows, Property Setters, Role Profiles, Workspaces, custom Print Formats, custom Reports, custom DocTypes) and sample master data (Items, Customers, Warehouses, etc.) via the REST API — one hardcoded to its own environment, no flags:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\prod\export.ps1
powershell -ExecutionPolicy Bypass -File deploy\test\export.ps1
```

Output trees (kept separate so both can exist and be diffed side by side):

| | Prod | Test |
|---|---|---|
| Schema | `deploy/prod/schema/*.json` | `deploy/test/schema/*.json` |
| Data (sample rows) | `deploy/prod/data/*.csv` | `deploy/test/data/*.csv` |
| Summary | `deploy/prod/export-summary.json` | `deploy/test/export-summary.json` |

### Clean diff procedure

1. Run the export for both environments (commands above) so both trees are fresh.
2. Diff the **schema** trees — this is the part that actually matters (customizations/config drift between the two servers):
   ```powershell
   git diff --no-index deploy/prod/schema deploy/test/schema
   ```
   Or in VS Code / Windsurf: select both `deploy/prod/schema` and `deploy/test/schema` folders in the file explorer → right-click → **Compare Selected**.
3. Diff the **data** trees only if you specifically need to compare master-data content (e.g. confirming test still matches a prior prod snapshot):
   ```powershell
   git diff --no-index deploy/prod/data deploy/test/data
   ```

### Reading the diff
- **Expect data/*.csv to differ** — test is a point-in-time snapshot (see §7) and drifts as soon as either environment is used. A data diff is normal, not a bug.
- **Schema diffs are the actionable signal** — e.g. a new Custom Field or Client Script created on Test while building/testing a feature, not yet ported to Prod (or vice versa). Use the diff to decide what to promote.
- `deploy/prod/export-summary.json` / `deploy/test/export-summary.json` give quick record counts per doctype without opening every file — check these first if you just want a fast sanity check before doing a full diff.


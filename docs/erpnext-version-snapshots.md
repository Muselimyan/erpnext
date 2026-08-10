# ERPNext Version Snapshots

Starting point created on 2026-08-10.

## Version naming

- `P-x.y.z` = production version.
- `T-x.y.z` = test version.

## Current starting versions

| Environment | Version | URL | Site | Server snapshot directory |
|---|---:|---|---|---|
| Prod | `P-1.1.1` | `https://erpnext.am` | `161.97.83.156` | `/root/erpnext-version-snapshots/prod_P-1.1.1_20260810T163934Z` |
| Test | `T-1.1.1` | `https://test.erpnext.am` | `test.erpnext.am` | `/root/erpnext-version-snapshots/test_T-1.1.1_20260810T163934Z` |

## Snapshot contents

Each snapshot contains:

- ERPNext bench backup with database, site config, public files, and private files.
- Direct MariaDB dump: `database.sql.gz`.
- Direct site files archive: `site_files.tar.gz`.
- `manifest.txt`.
- `SHA256SUMS.txt`.

## Server index

The clean server-side index for this starting point is:

`/root/erpnext-version-snapshots/VERSION_INDEX_20260810T163934Z.txt`

## Safety rule

Before restoring any snapshot, re-read `docs/infrastructure-test-vs-prod-environments.md` and explicitly confirm the target environment. Never restore a prod snapshot to test or a test snapshot to prod unless that is explicitly intended and confirmed.

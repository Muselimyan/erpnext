# ERPNext Version Snapshots

Starting point created on 2026-08-10.

## Version naming

- `P-x.y.z` = production version.
- `T-x.y.z` = test version.
- `x` = major version: big workflow/data model changes or breaking operational changes.
- `y` = feature/minor version: user-visible improvements that do not intentionally break existing behavior.
- `z` = fix/patch version: bug fixes and small UI corrections.
- Prod/test may have version gaps. If test reaches `T-1.2.10` and those changes are later applied to prod, prod can jump from an older version directly to `P-1.2.10`.

## Current versions

| Environment | Version | URL | Site | Server snapshot directory |
|---|---:|---|---|---|
| Prod | `P-1.1.5` | `https://erpnext.am` | `161.97.83.156` | `/root/erpnext-version-snapshots/prod_P-1.1.5_20260814T154801Z` |
| Test | `T-1.1.13` | `https://test.erpnext.am` | `test.erpnext.am` | `/root/erpnext-version-snapshots/test_T-1.1.13_20260827T111608Z` |

## Snapshot contents

Each snapshot contains:

- ERPNext bench backup with database, site config, public files, and private files.
- Direct MariaDB dump: `database.sql.gz`.
- Direct site files archive: `site_files.tar.gz`.
- `manifest.txt`.
- `SHA256SUMS.txt`.

## Server index

The clean server-side index for this starting point is:

`/root/erpnext-version-snapshots/VERSION_INDEX_20260827T111608Z_T-1.1.13.txt` and `/root/erpnext-version-snapshots/VERSION_INDEX_20260814T154801Z_P-1.1.5.txt`

## Safety rule

Before restoring any snapshot, re-read `docs/infrastructure-test-vs-prod-environments.md` and explicitly confirm the target environment. Never restore a prod snapshot to test or a test snapshot to prod unless that is explicitly intended and confirmed.

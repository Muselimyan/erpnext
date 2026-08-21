# Prod ERPNext Versions

This file is the local registry for production ERPNext rollback versions.

## Environment

| Item | Value |
|---|---|
| Environment | Prod |
| Version prefix | `P` |
| Public URL | `https://erpnext.am` |
| Site name inside bench | `161.97.83.156` |
| Backend container | `frappe-backend-1` |
| DB container | `frappe-db-1` |
| DB name | `_f98256a6d2bdfda2` |
| Docker sites volume path on server | `/var/lib/docker/volumes/frappe_sites/_data` |

## Restore safety rule

Before restoring any prod version:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Explicitly confirm the target is **prod**.
3. Confirm the prod container names before running commands:
   - `frappe-backend-1`
   - `frappe-db-1`
4. Do not use test snapshot paths or test container names for prod restore.

## Versions

### `P-1.1.1`

| Item | Value |
|---|---|
| Version | `P-1.1.1` |
| Created UTC | `20260810T163934Z` |
| Purpose | Starting rollback point for current working prod software |
| Server snapshot directory | `/root/erpnext-version-snapshots/prod_P-1.1.1_20260810T163934Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260810T163934Z.txt` |
| Verified size | `40M` |
| SHA file | `/root/erpnext-version-snapshots/prod_P-1.1.1_20260810T163934Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/prod_P-1.1.1_20260810T163934Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of prod DB `_f98256a6d2bdfda2` |
| `site_files.tar.gz` | Direct archive of prod site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Bench backup files captured

The snapshot directory contains a `bench_backup/` folder with files equivalent to:

| Backup artifact | Purpose |
|---|---|
| `*-database.sql.gz` | Bench-generated DB backup |
| `*-site_config_backup.json` | Bench-generated site config backup |
| `*-files.tgz` | Bench-generated public files backup |
| `*-private-files.tgz` | Bench-generated private files backup |

#### Restore capability

This version has enough data to restore prod back to `P-1.1.1`:

- Database state is available from both `bench_backup/*-database.sql.gz` and direct `database.sql.gz`.
- Site files are available from both bench file archives and direct `site_files.tar.gz`.
- Environment metadata is stored in `manifest.txt` and this local registry.
- Checksums are available in `SHA256SUMS.txt`.

#### Restore instruction placeholder

When asked to restore prod to `P-1.1.1`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/prod_P-1.1.1_20260810T163934Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `P-1.1.3`

| Item | Value |
|---|---|
| Version | `P-1.1.3` |
| Created UTC | `20260811T092116Z` |
| Purpose | Bugfix rollback point after Account Details Entry assignment UI repair |
| Improvement summary | Fixed Account Details Entry Task form JavaScript, kept `Next Task: Assign To` visible for Account Details Entry, and prevented auto-copy from `Assign To` into `Next Task: Assign To`. |
| Server snapshot directory | `/root/erpnext-version-snapshots/prod_P-1.1.3_20260811T092116Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260811T092116Z_1.1.3_CORRECTED.txt` |
| Verified size | `40M` |
| SHA file | `/root/erpnext-version-snapshots/prod_P-1.1.3_20260811T092116Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/prod_P-1.1.3_20260811T092116Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of prod DB `_f98256a6d2bdfda2` |
| `site_files.tar.gz` | Direct archive of prod site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore prod back to `P-1.1.3`.

#### Restore instruction placeholder

When asked to restore prod to `P-1.1.3`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/prod_P-1.1.3_20260811T092116Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `P-1.1.4`

| Item | Value |
|---|---|
| Version | `P-1.1.4` |
| Created UTC | `20260813T113858Z` |
| Purpose | Patch rollback point after Other task Accept button placement fix |
| Improvement summary | Added standard toolbar Accept / Start Task button support for `Other: Entry` and `Other: Processing` tasks while preserving task-name behavior and existing Other task fields. |
| Server snapshot directory | `/root/erpnext-version-snapshots/prod_P-1.1.4_20260813T113858Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260813T113858Z_1.1.4.txt` |
| Verified size | `44M` |
| SHA file | `/root/erpnext-version-snapshots/prod_P-1.1.4_20260813T113858Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/prod_P-1.1.4_20260813T113858Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of prod DB `_f98256a6d2bdfda2` |
| `site_files.tar.gz` | Direct archive of prod site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore prod back to `P-1.1.4`.

#### Restore instruction placeholder

When asked to restore prod to `P-1.1.4`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/prod_P-1.1.4_20260813T113858Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `P-1.1.5`

| Item | Value |
|---|---|
| Version | `P-1.1.5` |
| Created UTC | `20260814T154801Z` |
| Purpose | Pre header overlap mobile/both UI fix rollback point |
| Improvement summary | Rollback snapshot before promoting any Task header title/button vertical overlap fix to production. |
| Server snapshot directory | `/root/erpnext-version-snapshots/prod_P-1.1.5_20260814T154801Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260814T154801Z_P-1.1.5.txt` |
| Verified size | `45M` |
| SHA file | `/root/erpnext-version-snapshots/prod_P-1.1.5_20260814T154801Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/prod_P-1.1.5_20260814T154801Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of prod DB `_f98256a6d2bdfda2` |
| `site_files.tar.gz` | Direct archive of prod site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore prod back to `P-1.1.5`.

#### Restore instruction placeholder

When asked to restore prod to `P-1.1.5`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/prod_P-1.1.5_20260814T154801Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

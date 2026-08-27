# Test ERPNext Versions

This file is the local registry for test ERPNext rollback versions.

## Environment

| Item | Value |
|---|---|
| Environment | Test |
| Version prefix | `T` |
| Public URL | `https://test.erpnext.am` |
| Site name inside bench | `test.erpnext.am` |
| Backend container | `frappe-test-backend-1` |
| DB container | `frappe-test-db-1` |
| DB name | `_b9d33ed61d78a9f2` |
| Docker sites volume path on server | `/var/lib/docker/volumes/frappe-test_sites/_data` |

## Restore safety rule

Before restoring any test version:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Explicitly confirm the target is **test**.
3. Confirm the test container names before running commands:
   - `frappe-test-backend-1`
   - `frappe-test-db-1`
4. Do not use prod snapshot paths or prod container names for test restore.

## Versions

### `T-1.1.1`

| Item | Value |
|---|---|
| Version | `T-1.1.1` |
| Created UTC | `20260810T163934Z` |
| Purpose | Starting rollback point for current working test software |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.1_20260810T163934Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260810T163934Z.txt` |
| Verified size | `13M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.1_20260810T163934Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.1_20260810T163934Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
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

This version has enough data to restore test back to `T-1.1.1`:

- Database state is available from both `bench_backup/*-database.sql.gz` and direct `database.sql.gz`.
- Site files are available from both bench file archives and direct `site_files.tar.gz`.
- Environment metadata is stored in `manifest.txt` and this local registry.
- Checksums are available in `SHA256SUMS.txt`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.1`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.1_20260810T163934Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.2`

| Item | Value |
|---|---|
| Version | `T-1.1.2` |
| Created UTC | `20260810T175409Z` |
| Purpose | Pre prod-to-test customization sync rollback point |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.2_20260810T175409Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260810T175409Z_T-1.1.2.txt` |
| Verified size | `13M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.2_20260810T175409Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.2_20260810T175409Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to the exact state before copying approved prod customizations to test.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.2`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.2_20260810T175409Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.3`

| Item | Value |
|---|---|
| Version | `T-1.1.3` |
| Created UTC | `20260811T092116Z` |
| Purpose | Bugfix rollback point after Account Details Entry assignment UI repair |
| Improvement summary | Fixed Account Details Entry Task form JavaScript, kept `Next Task: Assign To` visible for Account Details Entry, and prevented auto-copy from `Assign To` into `Next Task: Assign To`. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.3_20260811T092116Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260811T092116Z_1.1.3_CORRECTED.txt` |
| Verified size | `13M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.3_20260811T092116Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.3_20260811T092116Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.3`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.3`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.3_20260811T092116Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.4`

| Item | Value |
|---|---|
| Version | `T-1.1.4` |
| Created UTC | `20260813T113858Z` |
| Purpose | Patch rollback point after Other task Accept button placement fix |
| Improvement summary | Added standard toolbar Accept / Start Task button support for `Other: Entry` and `Other: Processing` tasks while preserving task-name behavior and existing Other task fields. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.4_20260813T113858Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260813T113858Z_1.1.4.txt` |
| Verified size | `13M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.4_20260813T113858Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.4_20260813T113858Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.4`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.4`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.4_20260813T113858Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.5`

| Item | Value |
|---|---|
| Version | `T-1.1.5` |
| Created UTC | `20260814T154159Z` |
| Purpose | Pre header overlap mobile/both UI fix rollback point |
| Improvement summary | Rollback snapshot before correcting Task header title/button vertical overlap on test UI. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.5_20260814T154159Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260814T154159Z_T-1.1.5.txt` |
| Verified size | `15M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.5_20260814T154159Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.5_20260814T154159Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.5`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.5`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.5_20260814T154159Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.6`

| Item | Value |
|---|---|
| Version | `T-1.1.6` |
| Created UTC | `20260824T104431Z` |
| Purpose | Test UI patch after Task subject/header overlap correction |
| Improvement summary | Updated test-only Task client script `Task-Header Long Subject Fix` to remove risky header layout CSS and keep the normal Task `Subject` field visible without causing header/tab overlap. Verified on laptop with `TASK-2026-00477`. |
| Server snapshot directory | Not created for this patch entry |
| Server index file | Not created for this patch entry |
| Verified size | Not applicable |
| SHA file | Not created for this patch entry |
| Manifest file | Not created for this patch entry |

#### Included changes

| File/Artifact | Purpose |
|---|---|
| `deploy/test/_fix_task_header_long_subject.ps1` | Test-only deployment script for the minimal safe Task subject visibility client script. |
| Client Script `Task-Header Long Subject Fix` on `https://test.erpnext.am` | Ensures the native Task `Subject` field remains visible and removes stale overlapping banner/style artifacts without modifying ERPNext page header layout. |

#### Restore capability

This is a lightweight test software version marker, not a rollback snapshot. To roll back this exact change, restore or update the `Task-Header Long Subject Fix` Client Script from a previous backup/export, or restore test to an earlier snapshot such as `T-1.1.5` after following the restore safety procedure.

#### Restore instruction placeholder

When asked to restore test from `T-1.1.6`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Decide whether a Client Script rollback is enough or whether a full test restore to `T-1.1.5` is required.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.7`

| Item | Value |
|---|---|
| Version | `T-1.1.7` |
| Created UTC | `20260825T075834Z` |
| Purpose | Current test working state before Complete Task button logic change |
| Improvement summary | Snapshot after mobile Task UI/photo fixes, packing checkbox handler global exposure fix, and laptop subject duplicate cleanup; before changing Complete Task button behavior. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.7_20260825T075834Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260825T075834Z_T-1.1.7.txt` |
| Verified size | `16M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.7_20260825T075834Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.7_20260825T075834Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.7`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.7`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.7_20260825T075834Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.8`

| Item | Value |
|---|---|
| Version | `T-1.1.8` |
| Created UTC | `20260825T094619Z` |
| Purpose | Current test state before Complete button and mobile scroll fixes |
| Improvement summary | Snapshot after T-1.1.7 plus task-specific mobile photo buttons for Pack pickup photos and Pickup Returns drop-off photos; before fixing Complete button auto-complete short-circuit and mobile form scroll position. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.8_20260825T094619Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260825T094619Z_T-1.1.8.txt` |
| Verified size | `16M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.8_20260825T094619Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.8_20260825T094619Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.8`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.8`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.8_20260825T094619Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.9`

| Item | Value |
|---|---|
| Version | `T-1.1.9` |
| Created UTC | `20260825T124548Z` |
| Purpose | Current test working state after Inspect Returns photo preview improvements |
| Improvement summary | Snapshot after task-specific photo upload buttons, Complete button auto-complete short-circuit, mobile scroll cleanup, Inspect Returns Pack / Prepare photo gallery, no-download full-screen preview, mouse-wheel and pinch zoom, drag pan, and pan bounds. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.9_20260825T124548Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260825T124548Z_T-1.1.9.txt` |
| Verified size | `17M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.9_20260825T124548Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.9_20260825T124548Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.9`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.9`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.9_20260825T124548Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.10`

| Item | Value |
|---|---|
| Version | `T-1.1.10` |
| Created UTC | `20260826T121223Z` |
| Purpose | Current test state after Inspect Returns next-assignment visibility fix |
| Improvement summary | Snapshot after making `Next Task: Assign To` visible for `Returns processing / verification` tasks on test, including the Custom Field `depends_on` update and helper Client Script. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.10_20260826T121223Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260826T121223Z_T-1.1.10.txt` |
| Verified size | `17M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.10_20260826T121223Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.10_20260826T121223Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.10`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.10`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.10_20260826T121223Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.11`

| Item | Value |
|---|---|
| Version | `T-1.1.11` |
| Created UTC | `20260826T141758Z` |
| Purpose | Current test state after Inspect Returns quantity sync and phone UI toggle |
| Improvement summary | Snapshot after adding Inspect Returns Task-form returned/lost quantity editing synced to Dispatch Case, plus phone compact 4-column default layout with remembered Detailed toggle and `Ret?` checkbox header. Laptop full table remains unchanged. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.11_20260826T141758Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260826T141758Z_T-1.1.11.txt` |
| Verified size | `17M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.11_20260826T141758Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.11_20260826T141758Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.11`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.11`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.11_20260826T141758Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.12`

| Item | Value |
|---|---|
| Version | `T-1.1.12` |
| Created UTC | `20260827T084750Z` |
| Purpose | Current test working state after return restocking and invoice preparation display fixes |
| Improvement summary | Snapshot after Task product display fixes on test: Returns restocking shows only Dispatch Case rows with `returned_qty > 0` and Invoice preparation shows only rows with `used_qty > 0` or `lost_damaged_qty > 0`, with no checkboxes in either review/restock display. Full return path `DC-2026-00133` was completed through debt closure approval. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.12_20260827T084750Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260827T084750Z_T-1.1.12.txt` |
| Verified size | `17M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.12_20260827T084750Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.12_20260827T084750Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.12`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.12`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.12_20260827T084750Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

### `T-1.1.13`

| Item | Value |
|---|---|
| Version | `T-1.1.13` |
| Created UTC | `20260827T111608Z` |
| Purpose | Current test working state after restoring backup and adding Order entry next-task assignment visibility |
| Improvement summary | Snapshot after restoring test to `T-1.1.12` and reapplying the stable Order entry `Next Task: Assign To` visibility fix on test. Custom Field `Task-custom_next_task_assign_to` now includes `Order entry` in `depends_on` so the next-task assignment box appears in Order entry tasks on desktop and mobile. No photo-delete or packing-dashboard experiments are included. |
| Server snapshot directory | `/root/erpnext-version-snapshots/test_T-1.1.13_20260827T111608Z` |
| Server index file | `/root/erpnext-version-snapshots/VERSION_INDEX_20260827T111608Z_T-1.1.13.txt` |
| Verified size | `17M` |
| SHA file | `/root/erpnext-version-snapshots/test_T-1.1.13_20260827T111608Z/SHA256SUMS.txt` |
| Manifest file | `/root/erpnext-version-snapshots/test_T-1.1.13_20260827T111608Z/manifest.txt` |

#### Included files

| File/Directory | Purpose |
|---|---|
| `bench_backup/` | ERPNext bench backup with database, site config, public files, and private files |
| `database.sql.gz` | Direct MariaDB dump of test DB `_b9d33ed61d78a9f2` |
| `site_files.tar.gz` | Direct archive of test site files: public, private, and `site_config.json` |
| `manifest.txt` | Environment metadata and improvement notes for the snapshot |
| `SHA256SUMS.txt` | Checksums for snapshot files |

#### Restore capability

This version has enough data to restore test back to `T-1.1.13`.

#### Restore instruction placeholder

When asked to restore test to `T-1.1.13`, do not guess commands from memory. First:

1. Re-read `docs/infrastructure-test-vs-prod-environments.md`.
2. Read this file.
3. Inspect `/root/erpnext-version-snapshots/test_T-1.1.13_20260827T111608Z/manifest.txt` and `SHA256SUMS.txt`.
4. Confirm target environment with the user.
5. Prepare a restore plan before running destructive commands.

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

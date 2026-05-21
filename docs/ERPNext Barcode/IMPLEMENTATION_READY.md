# GS1 Barcode Implementation Readiness

## Current implementation status

Prepared locally, not safely confirmed live yet.

A previous deploy attempt is still reported as running by the IDE command runner and has produced no output. Do not run another deploy until that stuck attempt is cleared or confirmed finished.

## Files prepared

- `docs/ERPNext Barcode/GS1_FULL_WORKING_DRAFT.js`
  - Final approved client script draft.

- `deploy/barcode-gs1-deploy.ps1`
  - Focused deployment script for barcode custom fields and the `GS1 Barcode Parser` Client Script.
  - Supports `Check` and `Deploy` modes.
  - Uses 30-second timeout per ERPNext API request.
  - Prints progress before each field/client-script deployment.

## ERPNext records that will be created/updated

### Custom Fields on Purchase Receipt Item

1. `Purchase Receipt Item-custom_production_date`
   - Fieldname: `custom_production_date`
   - Type: Date
   - Read-only
   - Stores AI `11` production/manufacturing date.

2. `Purchase Receipt Item-custom_scanned_gs1_barcode`
   - Fieldname: `custom_scanned_gs1_barcode`
   - Type: Small Text
   - Read-only
   - Stores raw second barcode exactly as scanner reads it.

### Custom Fields on Purchase Receipt

3. `Purchase Receipt-custom_barcode_override_section`
   - Section Break
   - Label: Barcode Override

4. `Purchase Receipt-custom_allow_expired_barcode_receipt`
   - Fieldname: `custom_allow_expired_barcode_receipt`
   - Type: Check
   - Allows approved expired-product exception.

5. `Purchase Receipt-custom_allow_future_production_date`
   - Fieldname: `custom_allow_future_production_date`
   - Type: Check
   - Allows approved future-production-date exception.

6. `Purchase Receipt-custom_barcode_override_reason`
   - Fieldname: `custom_barcode_override_reason`
   - Type: Small Text
   - Required by client script when an exception override is used.

### Client Script

7. `GS1 Barcode Parser`
   - Existing Client Script on Purchase Receipt.
   - Will be updated with the final draft from `GS1_FULL_WORKING_DRAFT.js`.

## Agreed behavior

### Normal flow

1. Scan REF barcode in main `scan_barcode` field.
2. ERPNext standard logic finds the item using scanner raw barcode.
3. Row popup opens.
4. Scan second barcode in row `barcode` field.
5. Script parses:
   - AI `11` production date
   - AI `17` expiry date
   - AI `10` LOT/batch number
6. Script fills:
   - `batch_no`
   - `custom_expiry_date`
   - `custom_production_date`
   - `custom_scanned_gs1_barcode`
7. If same item + same batch + same expiry exists, quantity merges.
8. If expiry differs, rows stay separate.
9. Success beep plays and focus returns to main scanner.

### Error flow

- Second barcode scanned first: error beep and refocus main scan field.
- REF barcode scanned in row popup: error beep and refocus row barcode field.
- Expired product: blocked unless approved override checkbox and reason are entered.
- Future production date: blocked unless approved override checkbox and reason are entered.
- Expiry date before/equal production date: always blocked.

### Expiry alerts

- 180 days or less: notice.
- 90 days or less: stronger warning.
- Expired: block unless approved override is used.

## Final implementation sequence

Run only after explicit confirmation.

### Step 1: confirm stuck deploy is cleared

Use command status or terminate the stuck attempt if still running.

### Step 2: run check mode

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

Expected before deployment:

- Missing custom fields may show `exists: false`.
- `GS1 Barcode Parser` should exist and be enabled.

### Step 3: run deploy mode

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Deploy
```

Expected output should show progress lines for each Custom Field and then the Client Script.

### Step 4: run check mode again

```powershell
.\deploy\barcode-gs1-deploy.ps1 -Mode Check
```

Expected after deployment:

- All six custom fields show `exists: true`.
- `GS1 Barcode Parser` exists, enabled = `1`, dt = `Purchase Receipt`.

### Step 5: browser/manual smoke test

On Purchase Receipt:

1. Scan REF example:

```text
]C10106938250917530
```

2. Scan second barcode example:

```text
]C111250425173004241025D086
```

Expected parsed row values:

- Production Date: `2025-04-25`
- Expiry Date: `2030-04-24`
- Batch No: `25D086`
- Raw GS1 Barcode: `]C111250425173004241025D086`

## Important operational note

The second barcode does not identify the item, so the operator must scan one physical product at a time: REF first, then the second barcode from the same package immediately.

## Not included in this implementation

- Automatic creation/update of ERPNext Batch master records.
- Internal generated barcode logic for no-expiry products.
- Server-side validation script.
- Role-permission locking of override fields. This should be added after the field deployment is confirmed, either through ERPNext role permissions/property setters or a separate controlled script.

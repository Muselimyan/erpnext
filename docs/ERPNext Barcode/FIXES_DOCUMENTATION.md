# ERPNext Barcode Scanner - Fixes & Improvements

> **STATUS — corrected 2026-09-30 after code review against real scanner output.**
>
> Two claims in this document were found to be **wrong** and have been corrected in
> place below (sections 3 and 4). They are kept rather than deleted so the record of
> what was previously believed is preserved.
>
> Summary of what changed:
>
> - **Section 3 — "Merge Logic Already Correct" was WRONG.** The merge adds a
>   hardcoded `+1` and therefore silently loses quantity. See the correction in that
>   section.
> - **Section 4 — "Automatic Row Creation" was misleading.** The split path is gated
>   on `has_serial_no`, which is `0` for all 500 items, and it forces one scan per
>   physical unit.
>
> Scope note: this document describes the **two-barcode flow only** (a plain REF scan
> followed by a `]C111` LOT scan). Real scanner output confirms two further cases that
> this document does not cover and that the script does not handle:
>
> - a **single GS1 barcode carrying GTIN + production + expiry + LOT** together, which
>   cannot currently be received at all
> - a **plain barcode with no LOT/expiry data**, which needs no second scan
>
> Do not treat this document as a complete description of required behaviour.

## Issues Fixed

### 1. **Missing Validation for Wrong Barcode in Main Scanner**
**Problem:** When LOT barcode (]C111) was scanned in the main "scan_barcode" field instead of REF barcode, nothing happened.

**Fix:** Added `scan_barcode` event handler on `Purchase Receipt` form that:
- Detects if LOT barcode is scanned in main scanner
- Shows red alert message
- Plays error sound (400Hz beep)
- Clears the field and refocuses

### 2. **Missing Validation for Wrong Barcode in Pop-up**
**Problem:** When REF barcode was scanned in the pop-up "barcode" field instead of LOT barcode, nothing happened.

**Fix:** Added validation in `barcode` event handler that:
- Checks if scanned barcode starts with ']C111'
- If not, shows red alert message
- Plays error sound (400Hz beep)
- Clears the field and refocuses on barcode input

### 3. **Merge Logic — CORRECTION: NOT correct**

> **This section previously read "Merge Logic Already Correct". That was wrong.**

The merge **key** is correct. It compares all three variables:
- `item_code` (REF number)
- `batch_no` (LOT number)
- `custom_expiry_date` (expiry date)

And the duplicate search itself scales correctly — it is an unbounded scan over the
items table, so the 2nd, 3rd and 100th identical scan all find the accumulated row.

**But the quantity transfer is broken.** The merge does:

```javascript
'qty', (match.qty || 0) + 1     // hardcoded +1
```

It adds a hardcoded `1` and ignores the source row's actual `qty`, then deletes the
source row. So a row carrying qty 5 merges in as **+1** and **four units are silently
lost**. No error, no warning; the receipt total is simply wrong.

Correct behaviour is `+ (row.qty || 1)`.

Three further gaps in the merge key, all of which cause a silent wrong result:

- **Warehouse is not compared.** Same item + batch + expiry going into two different
  warehouses on one receipt merges into one row in whichever warehouse came first.
  Stock is then recorded in the wrong place with no error. Warehouse must join the key.
- **Rate is not compared.** Differing rates merge silently, keeping the target row's
  rate and changing valuation.
- **Production date is not compared.** Harmless in practice (one LOT implies one
  production date) but it is an assumption, not a guarantee.

Additionally, the merge is guarded by a module-level `gs1_is_merging` boolean that is
cleared only on the success path and in one `.catch`. If the sequence ends any other
way the flag stays `true` **permanently**, and every later scan is silently ignored —
the scanner appears dead with no message, recoverable only by reloading the page.

### 4. **Automatic Row Creation — CORRECTION: misleading**

> **This section previously implied the split behaviour was desirable. It is not.**

The `qty` handler does split rows when `qty > 1` and no batch is set. Two problems:

- **It is gated on serial tracking, which is off everywhere.** All 500 items have
  `has_serial_no = 0`, `has_batch_no = 0` and `has_expiry_date = 0`, so the split path
  is driven by a condition that is false for every item in the system.
- **Where it does apply, it forces one scan per physical unit.** A box of 50 units
  sharing one LOT requires 50 scans, roughly 2–3 minutes, producing **exactly the same
  stored data** as one scan plus a quantity. A process that slow gets worked around,
  and the workaround is typing quantities without scanning — which destroys the LOT
  capture the feature exists to provide.

Intended behaviour instead: scan once, then a quantity box pre-filled with `1`, so a
single unit stays one scan plus Enter while a box of 50 takes the same five seconds.
Scanning each unit individually must remain possible for anyone who wants it, since
repeated scans of the same LOT accumulate on one row via the merge path.

## New Features Added

### Error Sound System
- Uses Web Audio API for cross-browser compatibility
- 400Hz sine wave, 0.2 second duration
- Plays when wrong barcode is scanned in either field
- Alerts the operator without looking at screen

### Visual Alerts
- Red alert messages with 5-second display
- Clear instructions on what went wrong
- Helps operator understand the error immediately

### Improved Focus Management
- Main scanner refocuses after every operation
- Pop-up barcode field refocuses after errors
- Ensures continuous scanning without mouse/keyboard interaction

## Workflow Summary

1. **Scan REF barcode** in main "scan_barcode" field
   - Creates new row with item
   - Opens pop-up for batch details
   - Auto-focuses on "barcode" field in pop-up

2. **Scan LOT barcode** in pop-up "barcode" field
   - Parses LOT number and expiry date
   - Checks for existing row with same REF+LOT+expiry
   - If match: increments qty, deletes current row
   - If no match: keeps current row
   - Closes pop-up
   - Refocuses on main "scan_barcode" field

3. **Error Handling**
   - Wrong barcode in main scanner: alert + sound + refocus
   - Wrong barcode in pop-up: alert + sound + refocus
   - Operator knows immediately to rescan

## Code Structure

```javascript
// Global flag to prevent race conditions
let is_merging = false;

// Main scanner validation (Purchase Receipt level)
frappe.ui.form.on('Purchase Receipt', {
    scan_barcode: function(frm, cdt, cdn) {
        // Validates REF vs LOT barcode
        // Plays error sound if wrong type
    }
});

// Item-level handlers (Purchase Receipt Item level)
frappe.ui.form.on('Purchase Receipt Item', {
    qty: function(frm, cdt, cdn) {
        // Splits qty > 1 into separate rows
        // Opens pop-up for batch entry
    },
    
    barcode: function(frm, cdt, cdn) {
        // Validates LOT barcode format
        // Parses LOT and expiry date
        // Merges duplicates or keeps separate
        // Manages focus back to main scanner
    }
});
```

## Testing Checklist

- [ ] Scan REF barcode in main scanner → opens pop-up
- [ ] Scan LOT barcode in pop-up → parses and closes
- [ ] Scan same item twice → merges into one row with qty=2
- [ ] Scan same item with different LOT → creates separate rows
- [ ] Scan LOT in main scanner → shows error + sound
- [ ] Scan REF in pop-up → shows error + sound
- [ ] Focus returns to main scanner after each operation
- [ ] No manual clicking required during scanning

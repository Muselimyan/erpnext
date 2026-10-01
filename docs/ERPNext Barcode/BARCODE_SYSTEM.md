# Barcode System — Authoritative Specification

Last updated: 2026-10-01

This is the single authoritative document for the barcode system. It supersedes
`IMPLEMENTATION_READY.md` and `FIXES_DOCUMENTATION.md`, which remain only as a historical
record of what was previously believed.

**Nothing in this specification is implemented yet.** It describes agreed behaviour, not
current behaviour. Section 16 lists what is actually deployed and why it does not work.

---

## 1. Why this document exists

The barcode feature previously looked finished and was in fact inert. The Client Script and
all seven custom fields were deployed to test **and** production, yet the second scan had
never once executed, no batch or expiry had ever been captured, and no barcode had ever been
registered against any item.

Nothing failed. Nothing alerted. It simply did nothing, silently, on both environments.

Two prior documents asserted that parts of it were correct when they were not. This document
exists so that cannot happen again, and so every rule can be traced to evidence rather than
assumption.

### Evidence standard used here

| Label | Meaning |
|---|---|
| **VERIFIED** | Confirmed against real scanner output, a real product label, or library source code |
| **DECIDED** | A business decision made by the owner; no external verification applies |
| **UNVERIFIED** | Believed correct but not yet confirmed; must not be relied upon |

---

## 2. The single most important insight

Everything inert in this system traces to **one missing link**:

> **Scanned LOT and expiry data never becomes `Batch` records.**

That single gap explains four separate symptoms:

- Purchase Receipt GS1 capture is inert
- FEFO never warns — it queries `Batch.expiry_date`, and no Batch records exist
- Expired-stock reporting is impossible — the data is not where the rest of ERPNext looks
- Batch tracking cannot be enabled — submission would fail without Batch records

These are not four problems. They are one missing link with four symptoms. Building that link
(Phase 2, section 17) resolves all four together, and can be done with **zero stock-ledger
risk**.

This is why the document is organised as a single pipeline rather than as separate
"receiving" and "packing" features:

```
scan → parse → validate → Batch record → stock → FEFO → dispatch
```

---

## 3. Barcode formats actually in use

**VERIFIED** from real scanner output (`Scans for ERPNEXT.txt`) and a physical product label.

### 3.1 Identifiers — all are GTINs

Every numeric identifier observed is a valid GS1 GTIN with a correct check digit:

| Observed | Length | Type | Check digit |
|---|---|---|---|
| `48515092`, `48514606`, `48515429` | 8 | GTIN-8 (EAN-8) | valid |
| `4630201701480` | 13 | GTIN-13 (EAN-13) | valid |
| `06938250917530` | 14 | GTIN-14 (in AI 01) | valid |
| `03760124130249` | 14 | GTIN-14 (in AI 01) | valid |
| `06958590312765` | 14 | GTIN-14 (in AI 01) | valid |

Three 8-digit codes passing a check digit by chance would be a 1-in-1000 event. Combined with
the 13- and 14-digit codes also passing, this is conclusive: the catalogue is GS1-coded
throughout.

**Consequence:** GTIN-8, GTIN-13 and GTIN-14 are a *single* namespace. See section 5.4.

### 3.2 GS1 barcodes observed

| Raw | Contents |
|---|---|
| `]C10106938250917530` | AI 01 only (GTIN) |
| `]c10106938250917530` | **same, lowercase prefix** — see defect D-05 |
| `]C111250702173007011025F031` | AI 11 production, AI 17 expiry, AI 10 LOT |
| `]C111250425173004241025D086` | AI 11 production, AI 17 expiry, AI 10 LOT |
| `]C10103760124130249112604241731030110F26043056` | AI 01, 11, 17, 10 — all in one barcode |

### 3.3 DataMatrix is in use

**VERIFIED** from the product label of item REF `CX-01S`.

That label carries a GS1 DataMatrix (UDI) containing:

| AI | Field | Value |
|---|---|---|
| 01 | GTIN | `06958590312765` |
| 11 | Production date | 2026-06-18 |
| 17 | Expiry | 2027-10-17 |
| 10 | LOT | `QF26G022` |
| 21 | **Serial** | `22222FPDUA` |

Confirmed by phone-app decode: **the serial is inside the DataMatrix**, not merely printed.

The same box also carries a separate EAN-13 linear barcode `6958590312765`, which encodes
**only** the GTIN. An EAN-13 holds exactly 13 digits and is structurally incapable of carrying
expiry, LOT or serial.

**Consequence:** for this product, expiry and LOT can only be obtained by reading the
DataMatrix. There is no alternative scannable source.

**Further items exist that carry a DataMatrix and no linear barcode at all.** Those items
cannot be identified by any current scanner. See section 14.

### 3.4 Application Identifiers to support

| AI | Name | Length | Notes |
|---|---|---|---|
| `01` | GTIN | fixed 14 | normalise per section 5.4 |
| `10` | Batch / LOT | **variable** | needs a terminator — see section 5.5 |
| `11` | Production date | fixed 6 | YYMMDD |
| `17` | Expiry date | fixed 6 | YYMMDD |
| `21` | **Serial number** | **variable** | capture per section 10 |
| `240` | Additional item ID | variable | parse, no business use yet |
| `241` | Customer part number | variable | parse, no business use yet |

### 3.5 REF is not a GTIN

On the `CX-01S` label the REF is printed as text (`# CX-01S`) and is **not barcoded**. It is
alphanumeric and may contain hyphens, unlike the GTINs which are always numeric.

Do not treat REF and GTIN as interchangeable. Scanning always yields a GTIN; REF is a
human-readable manufacturer catalogue number.

---

## 4. The two-axis model

**DECIDED.** This replaces the earlier "three samples" framing, which had a gap: it could not
express a product that needs LOT and expiry but has no manufacturer barcode carrying them.

Barcode handling is determined by **two independent questions**, not by a product category:

1. **How is the item identified?**
2. **Where does LOT and expiry come from?**

Every case your catalogue contains:

| Identification | LOT / expiry source | Real example |
|---|---|---|
| Plain GTIN (8 or 13) | Not required | `48515092`, `4630201701480` |
| GS1 barcode, AI 01 only | A separate GS1 barcode | `]C10106938250917530` then `]C111…` |
| GS1 barcode, AI 01 present | The same barcode | `]C101037601…1017…10…` |
| GS1 DataMatrix | The same DataMatrix | `CX-01S` UDI code |
| Internal barcode (section 9) | Not required | no-barcode item, no expiry |
| Internal barcode (section 9) | Manual entry, once per batch | no-barcode item **with** expiry |
| Any of the above | Manual entry (emergency) | damaged or unreadable label |

Six combinations from two axes, with nothing uncovered. Enumerating product "types" instead
would reintroduce the same gap.

### 4.1 The item-level policy field

The field name must reflect the *data requirement*, not the scan mechanics:

| | Old | New |
|---|---|---|
| Field | `custom_requires_gs1_lot_scan` | `custom_requires_lot_and_expiry` |
| Question | "does this need a second scan?" | "does this item need LOT + expiry data?" |

The old framing could not represent a product that needs LOT data but obtains it in a single
scan, which is exactly why single-barcode products had no home in the previous design.

**Default: OFF.** This is deliberately the opposite of the project's usual default-deny
principle, and the reasoning matters:

- Default ON + forgotten flag → the worker gets a popup demanding a barcode **that does not
  exist on the box**. There is no correct action available. Receiving stops with a truck
  waiting.
- Default OFF + forgotten flag → LOT is not captured. A visible, queryable gap that can be
  corrected afterwards.

Being too strict fails *unrecoverably at the point of work*. Being too permissive fails
*recoverably*. Hence OFF, with detection to compensate (section 4.2).

### 4.2 Misconfiguration detection

A per-item flag can be set wrongly. Three safeguards make that detectable rather than silent:

1. **Detection at scan time (primary).** If a GS1 barcode carrying AI 10 or AI 17 is scanned
   for an item flagged as *not* requiring LOT/expiry, the system flags the contradiction and
   offers to correct the flag. **The barcode itself proves the flag is wrong.**
2. **Configuration report.** Items whose Item Group peers consistently capture LOT but which
   never have.
3. **Default OFF**, so a forgotten flag is a recoverable gap.

A misconfiguration is therefore normally caught on the first scan. Claiming the flag will
never be set wrongly would not be honest; claiming it will not stay wrong unnoticed is.

---

## 5. Parsing specification

### 5.1 Prefix detection — case-insensitive

**VERIFIED defect.** Real scanner output contains `]c1` (lowercase) in 1 of 35 GS1 scans —
approximately 3%.

Prefix matching MUST be case-insensitive for `]C1` and `]d2`.

This is unambiguously safe. `]C1` is a symbology identifier defined by the barcode standard;
`]c1` is a transmission artefact of keyboard emulation (a missed Shift on the first characters
transmitted). There exists no valid barcode in which lowercase `]c1` means anything different.

**Data payload: do NOT case-fold.** AI 10 and AI 21 permit mixed case, so a LOT or serial must
be stored exactly as received. However, if a scanned LOT differs from an existing row's LOT
**only by case**, treat it as a probable duplicate and warn rather than silently creating a
second row.

Observed evidence: 13 LOT-barcode scans containing letters were all uppercase, with no data
corruption. Only the prefix was affected, consistent with the first-characters explanation.

### 5.2 Field identification is by AI, never by position

The AI code identifies the field. Supplier ordering is irrelevant — both of these parse
identically and correctly:

```
]C1 17 261231 11 240115 10 ABC123
]C1 11 240115 10 ABC123 <GS> 17 261231
```

Do **not** infer meaning from position or from comparing dates. If only one date is present,
its value alone cannot reveal whether it is an expiry or a production date; the AI can. An
expiry earlier than a production date is therefore a **validation error**, not a cue to guess.

### 5.3 Date handling

#### Century — sliding window

**DECIDED.** Use the GS1 sliding window, not a fixed pivot:

```
CY   = current two-digit year        (2026 → 26)
CC   = current century               (2026 → 20)
diff = YY - CY

diff >=  51            → year = (CC-1)*100 + YY
diff between -50 and 50 → year =  CC   *100 + YY
diff <= -51            → year = (CC+1)*100 + YY
```

This is pure arithmetic inside the parser. **There is no user interaction**, no prompt, and no
change to the worker's experience.

The currently deployed code uses a fixed pivot (`YY >= 50 → 19xx`) which is wrong and breaks on
long-dated product:

| Barcode `YY` | Fixed pivot (deployed) | Sliding window |
|---|---|---|
| `30` | 2030 | 2030 |
| `50` | 19**50** — reads as expired | 2050 |
| `76` | 19**76** — reads as expired | 2076 |

The sliding window self-adjusts as years pass and never needs revisiting.

#### Calendar validation — real, not range-based

Checking month ≤ 12 and day ≤ 31 is necessary but **not sufficient**. The deployed code does
exactly that, and therefore accepts:

| Input | Produces | Real date? |
|---|---|---|
| `260231` | 2026-02-31 | no |
| `260431` | 2026-04-31 | no |
| `250229` | 2025-02-29 | no — 2025 is not a leap year |

An invalid date reaching a MariaDB `date` column either errors with an opaque SQL message or
becomes `0000-00-00`, after which every expiry comparison misbehaves.

Validate by round-trip:

```javascript
let d = new Date(yyyy, mm - 1, dd);
let valid = d.getFullYear() === yyyy && d.getMonth() === mm - 1 && d.getDate() === dd;
```

This correctly rejects 31 February and 31 April and handles leap years including century rules.

#### Day `00`

**UNVERIFIED — must be confirmed against the GS1 General Specifications before implementation.**

GS1 permits `DD=00` to mean "day not specified". Industry practice in GS1 Healthcare treats an
unspecified day on an **expiry** date as the **last day of the month**, because product labelled
"expires 2026-12" is good through 31 December.

The deployed code converts `DD=00` to day `01`, which would expire product **up to 30 days
early**. On 15 December 2026 a product coded `261200` would be computed as `2026-12-01`, flagged
expired, and blocked — with two weeks of shelf life remaining. The worker would then be forced
to use the expired-goods override on good stock, polluting the override audit trail.

Intended rule, pending confirmation:

- AI 17 (expiry), `DD=00` → **last day of month**
- AI 11 (production), `DD=00` → **first day of month** (conservative)

Not present in any observed scan, so this is lower priority than it first appeared.

#### Domain sanity range

The century rule cannot detect a misread. A range check can:

- Expiry must fall within `[today − 5 years, today + 30 years]`
- Production must fall within `[today − 30 years, today + 1 day]`

Outside the range → reject the scan with an error beep. Bounds are configurable (section 7) so
an unusually long-dated product is a settings change, not a code change.

### 5.4 GTIN normalisation — mandatory

**VERIFIED on a physical product.** The `CX-01S` box carries both:

- EAN-13 linear barcode: `6958590312765`
- GTIN-14 in the DataMatrix: `06958590312765`

Zero-padding makes these identical. **Two workers scanning the same box produce two different
strings.** Without normalisation, whichever form was registered resolves and the other fails —
an intermittent "item not found" on a product that *is* in the system.

**Rule:** normalise every numeric identifier to GTIN-14 by left-padding with zeros.

| Scanned | Normalised |
|---|---|
| `48515092` | `00000048515092` |
| `4630201701480` | `04630201701480` |
| `06938250917530` | `06938250917530` |

GTIN-8, GTIN-13 and GTIN-14 are allocated from one global namespace precisely so this padding
is unambiguous. Collisions are impossible by GS1 design.

**The indicator digit must be preserved.** A GTIN-14 beginning 1–8 denotes a packaging level —
a case, not a single unit — and is a genuinely *different* trade item. Left-padding preserves
it correctly. All observed GTIN-14s begin with `0` (base unit).

#### Storage approach

**Store both forms as separate `Item Barcode` rows** — the scanned form and the normalised
GTIN-14.

**VERIFIED from ERPNext source** (`erpnext/stock/doctype/item/item.py`):

- `validate_barcode()` rejects a barcode already attached to a different Item, throwing
  *"Barcode {0} already used in Item {1}"*. **One-barcode-to-one-item is enforced by ERPNext
  itself** — this safeguard does not need building.
- A blank `barcode_type` **skips validation entirely**. Leave it blank.
- If `barcode_type` is set to `EAN`, validation maps by **length**
  (`{8: "EAN8", 13: "EAN13"}`). A normalised 14-digit value would fall out of that mapping and
  behave unpredictably. **Never set `barcode_type` on a normalised value.**

Storing both forms means ERPNext's **native** barcode lookup resolves either form with no
interception and no custom lookup path — less code and fewer places to disagree with the
framework.

For a single barcode carrying LOT/expiry, register only the **GTIN**, never the full raw
string. The raw string is unique per batch and would never match again.

### 5.5 The GS separator — a hardware requirement

**VERIFIED that this cannot be solved in software.**

Fixed-length AIs (`01`, `11`, `17`) are never ambiguous. Variable-length AIs (`10` LOT, `21`
serial) have no intrinsic end marker. GS1 solves this with the FNC1 character, transmitted as
ASCII 29 (Group Separator).

Earlier analysis concluded no separator was needed because LOT was always the final field. **The
`CX-01S` DataMatrix disproves that**: AI 10 is followed by AI 21, two variable-length fields in
sequence. That is precisely the case requiring a separator.

No parsing logic can compensate. Worked example — LOT `QF21G022` with no separator:

```
…10QF21G022…  →  parser reads Q, F, then sees "21" (a valid AI) → stops
              →  LOT = "QF", remainder absorbed into the serial
```

Every character is consumed and the parse appears clean. A "full consumption" check does **not**
detect this, because both readings are structurally valid. This was considered and rejected as a
mitigation.

**Therefore:**

- GS transmission is a **mandatory scanner configuration requirement** (section 14)
- The parser uses the separator when present
- Where absent, the parser falls back to reading until the next known AI, and **flags the scan
  as uncertain** rather than accepting it silently
- No observed scan contains a GS byte (0 occurrences of `0x1D` in the captured file), because
  the current scanner cannot read the DataMatrix at all

### 5.6 Check-digit validation

Every numeric identifier observed carries a valid GS1 check digit. Validate it on every scan.

A dropped or garbled digit fails the check and is rejected **at the moment of scanning**,
before wrong data reaches the database. This is the cheapest available integrity control and
the only one that catches a misread the parser would otherwise accept.

### 5.7 Server-side parser

The server must be able to verify what the client reports, so it needs its own complete
parser — not a substring heuristic.

**VERIFIED available in Frappe's RestrictedPython sandbox** (from
`frappe/utils/safe_exec.py` and RestrictedPython `transformer.py` / `Guards.py`):

| Primitive | Status | Evidence |
|---|---|---|
| `while` loops | allowed | `visit_While` — *"Allow `while` statements."* |
| `chr()`, `ord()` | available | in `_safe_names` → `safe_builtins` |
| `i += 1` on a local | allowed | `visit_AugAssign` permits `Name` targets |
| `d[k] += 1` | **blocked** | same function errors on `Subscript` targets |
| `for`, `range`, `enumerate`, `len`, `try/except` | available | — |

**Use a bounded `for` loop rather than `while`.** Not a permission issue — a `while` loop that
fails to advance its index would **hang the worker process** instead of throwing. A bounded loop
cannot. Identical output, strictly safer failure mode.

This also confirms the augmented-subscript constraint documented in `AGENTS.md` is accurate.

### 5.8 Parser architecture

**One authoritative parser on the server. Thin parsers on the client for immediate feedback.**

- The **client** parser fires instantly — beep, popup, field population, no network wait
- The **server** parser decides what is actually stored
- On disagreement, **the server wins and the discrepancy is logged** — which is also how parser
  bugs get discovered in production rather than from a customer

This resolves the three-parser divergence not by making them identical but by making one
authoritative. Divergence becomes a detectable, logged event rather than a correctness risk.

Latency objection, previously raised and now withdrawn: the packing flow **already** makes a
server call per scan, so moving parsing into it costs nothing. Purchase Receipt would add one
call of roughly 50–150 ms on a LAN, and because the client parser still fires instantly for the
visible response, perceived speed is unchanged.

---

## 6. Scan workflows

### 6.1 Purchase Receipt — receiving

```
A barcode arrives in the main scan field

STEP 1 — is it a GS1 barcode?  (]C1 / ]d2 prefix, case-insensitive)

  NO → plain barcode
       → normalise to GTIN-14, validate check digit
       → resolve item (Item Code, then Item Barcode, both forms)
       → not found → unknown-barcode handling (section 8)
       → found → add row, then consult custom_requires_lot_and_expiry:
            required     → open popup for the LOT/expiry scan
            not required → quantity entry

  YES → parse fully first
       STEP 2 — does it contain a product identifier?
                (AI 01, or AI 240/241, or the whole string is a registered Item Barcode)

         YES → single-scan case. Resolve item from the identifier.
               Populate item + LOT + expiry + production + serial from this one scan.
               Validate dates. Merge if duplicate. No popup.
               Return focus to the main scan field.

         NO  → a LOT-only barcode scanned out of order.
               Error + beep + clear field + refocus.
               "This is the LOT barcode. Please scan the product barcode first."
```

**Out-of-order detection must not be a literal prefix match.** The deployed code checks for
`]C111` specifically, so a supplier barcode beginning `]C110` or `]C117` escapes it and produces
a generic "Cannot find Item" instead of a clear message. The correct test is *"a GS1 barcode
containing no product identifier"*.

**Single-barcode products currently cannot be received at all.** The deployed script passes
them to ERPNext's native lookup as the entire raw string — 46 characters including LOT and
expiry — which matches nothing. The helper written to detect this case (`gs1_is_ref_barcode`,
testing the `]C101` prefix) exists in the script and **is never called**. See defect D-01.

### 6.2 Quantities

**DECIDED.** Scan once, then a quantity box pre-filled with `1`.

| Item type | Flow |
|---|---|
| Plain GTIN, no LOT needed | scan → qty box (default 1) → Enter |
| Two-barcode product | scan GTIN → scan LOT → qty box (default 1) → Enter |
| Single-barcode product | scan once → qty box (default 1) → Enter |

Single units remain one scan plus Enter — exactly as fast as today. A box of 50 takes the same
five seconds.

**Scanning each unit individually remains available** for anyone who prefers it: repeated scans
of the same LOT accumulate on one row through the merge path.

**Remove the per-unit splitting code.** It is gated on `has_serial_no`, which is `0` for all 500
items, and where it applies it forces one scan per physical unit — roughly 2–3 minutes for a box
of 50, producing **identical stored data** to one scan plus a quantity. A process that slow gets
worked around, and the workaround is typing quantities without scanning, which destroys the LOT
capture the feature exists to provide. See defect D-11.

### 6.3 Row merging

Merge key: **item + LOT + expiry + warehouse + rate**

| Field | Why |
|---|---|
| item, LOT, expiry | the identity of the goods |
| **warehouse** | without it, one receipt splitting an item across two warehouses merges into one row in whichever came first — **stock recorded in the wrong place, silently** |
| **rate** | without it, differing rates merge silently, keeping the target row's rate and changing valuation |

**DECIDED** to include warehouse regardless of current practice: receiving is normally into one
warehouse but exceptions occur, the failure is silent and expensive, and it protects against a
future change in working practice.

Serial numbers are **not** in the merge key (section 10).

Production date is not compared. Documented assumption: one LOT implies one production date.

**Quantity transfer must use the source row's actual quantity.** The deployed code adds a
hardcoded `+1` and then deletes the source row, so a row carrying qty 5 merges in as `+1` and
four units vanish with no error. See defect D-02.

### 6.4 Packing scan

Row matching must consider the batch:

```
IF a LOT was parsed from the barcode:
  a. prefer: item matches AND batch == parsed LOT AND scanned < required
  b. else:   item matches AND batch empty AND scanned < required  → assign the batch
  c. else:   do NOT overwrite another row's batch → flag as substitution and warn

IF no LOT was parsed:
  a. item matches AND scanned < required
  b. several candidates with differing batches → fill earliest-expiring first
     (FEFO-consistent) and report which row was filled
```

**Batch substitution is a warning, never a block** (**DECIDED**). If the picker takes LOT-C
because LOT-A is out of stock, that is a legitimate substitution. The row is flagged
`custom_batch_substituted` and a warning returned, so reality is recorded without stopping work
— consistent with the FEFO policy in section 12.

The deployed code matches on item alone and takes the first unfilled row, then **writes the
scanned batch over whatever batch that row held**. See defect D-03.

### 6.5 Manual packing confirmation

The manual "packed" checkbox is available **only** for items that do not require LOT and
expiry.

Otherwise a product whose LOT must be captured can be marked fully packed with no batch data at
all — the row shows complete, traceability is empty, and nothing flags it. The deployed
`task_mark_item_packed` and `task_mark_items_packed_batch` both have this hole. See defect D-10.

Enforced on the client for usability and **on the server for integrity**. Only the server side
counts.

For a genuinely unscannable label, the role-gated manual entry path (section 8.4) applies — not
the checkbox.

---

## 7. Validation rules

### 7.1 Rules

| Check | Condition | Result |
|---|---|---|
| Expired | `expiry < today` | **blocked** unless `custom_allow_expired_barcode_receipt` **and** `custom_barcode_override_reason` |
| Future production | `production > today` | **blocked** unless `custom_allow_future_production_date` **and** reason |
| Impossible dates | `expiry <= production` | **blocked always**, no override |
| Out of sane range | section 5.3 | scan rejected with beep |
| Check digit fails | section 5.6 | scan rejected with beep |
| Near expiry | within `expiry_notice_days` | notice, not blocking |
| Near expiry | within `expiry_warning_days` | strong warning, not blocking |

### 7.2 Server-side enforcement is mandatory

**DECIDED.** All of the above is currently client-side only. That is not acceptable, for five
reasons in order of weight:

1. **A JavaScript error anywhere on the page silently disables every rule.** Frappe bundles
   Client Scripts. If any script on Purchase Receipt throws during `refresh` — including one
   added next year for an unrelated reason — the GS1 handlers may never bind. Expired product
   then saves with no error, no beep, no warning. It fails **silently** and looks exactly like
   normal operation.
2. **Client scripts are a UX layer, not an integrity boundary.** Bypassed by the REST API,
   `bench console`, **Data Import** (an ordinary business operation), mobile apps, and anyone
   with the browser console open.
3. **The project's completion standard requires it.** Client-only validation is advisory by
   construction. The honest answer to *"can expired product enter stock?"* would otherwise be
   *"not through the UI, but yes through several other routes."*
4. **Expiry-dated medical supplies carry real exposure.** The override design — explicit
   checkbox plus mandatory written reason — is the correct control, but a control that can be
   bypassed is not a control. With server enforcement the override trail becomes meaningful:
   every expired receipt carries a reason, with no way around it.
5. **It is cheap and low-risk** — roughly 40 lines, pure date comparison, and it can only
   reject saves that were already invalid.

**Scope:** the server validates the resulting *data*; it does not parse barcodes for the UI.
Clean separation — client does parsing and feedback, server enforces rules.

### 7.3 The submitted-document gap

`Before Save` does **not** fire for submitted documents (see `AGENTS.md`).

| Field | `allow_on_submit` | Covered by a draft-only gate? |
|---|---|---|
| `custom_expiry_date` | 0 | yes |
| `custom_production_date` | **1** | **no — changeable after submit** |
| `custom_scanned_gs1_barcode` | **1** | **no** |

**Resolution: set `allow_on_submit = 0` on `custom_production_date`.** There is no business
reason to change a production date after submission — it is a fact about the goods, not a
decision. This removes an entire bypass class and avoids maintaining a duplicated twin script.

### 7.4 Configurable thresholds

**DECIDED.** A `Barcode Settings` single DocType:

| Field | Default |
|---|---|
| `expiry_notice_days` | 180 |
| `expiry_warning_days` | 90 |
| `expiry_min_years_back` | 5 |
| `expiry_max_years_forward` | 30 |
| `production_max_years_back` | 30 |

Read for all; **write for `System Manager` and `Ops - Directors` only**.

**Per-Item-Group overrides** via a child table, because thousands of products with differing
consumption rates and lead times cannot share one threshold. Resolution order: Item override
(rare exceptions) → Item Group → global default.

Item Group is the right primary level — tens of records, maintainable. Item level as primary
would be thousands of records that nobody keeps current, and a stale threshold is worse than
none.

Fetch **once on form load and cache**, never per scan.

---

## 8. Unknown barcodes

**Context:** zero barcodes are currently registered against any item, so this is not an edge
case — it is the primary path for building the barcode database.

Two situations hide behind "item not found", and conflating them produces duplicate items,
which is among the most expensive data problems to unwind:

- **The item exists; this barcode is not yet linked to it.** By far the most common.
- **A genuinely new product.**

### 8.1 Tier 1 — link to an existing item

Dialog shows the raw barcode with the cursor already in an item search box. Worker types a few
characters, selects, and the barcode is written to that Item's `Item Barcode` table.

**The link is permanent.** From that moment the barcode resolves instantly for every future
scan, on every document, for every user. Interruption is roughly 5–10 seconds, once per barcode
ever.

**Register the GTIN, not the full raw string.** The GTIN is the stable part; LOT and expiry
change every delivery. Registering the whole string would link a barcode that never repeats.

Roles: `Ops - Purchasing Manager`, `Ops - Inventory Manager`, `Ops - Directors`,
`System Manager`.

### 8.2 Tier 2 — create a new item

Quick-create dialog (item code, name, group, UOM) producing a **real, permanent Item** plus the
barcode link. Not a receipt-only record.

Roles: `Ops - Purchasing Manager`, `Ops - Directors`, `System Manager`. **Not** regular
warehouse staff — Item master quality is a long-lived asset and casual creation degrades it
quickly.

### 8.3 Tier 3 — flag for review

Available to **everyone**, never blocks. Logs the raw barcode with timestamp, user, Purchase
Receipt and supplier to an `Unknown Barcode Scan` record. The worker continues; a purchasing
person resolves the queue later.

Receiving is time-critical — a truck waiting, possibly cold chain — so the process must never
hard-stop. All three tiers capture the raw barcode; today it is discarded entirely.

### 8.4 Manual entry — emergency only

**DECIDED: avoid manual typing wherever possible.** Manual entry is a role-gated exception, not
a workflow.

It applies to:

1. No-barcode items with expiry (until an internal label exists — section 9)
2. A damaged or unreadable label
3. Expiry corrections

#### Design

**Let scanning do whatever it still can.** A damaged label is rarely entirely unreadable — on
the `CX-01S` box, if the DataMatrix fails but the EAN-13 reads, identity is captured
automatically and only LOT and expiry are typed. The dialog opens pre-filled with everything
scanning obtained and asks only for what is missing.

**Date entry: `YYMMDD`, six keystrokes** (**DECIDED**). Matches what the barcodes show, no
separators to get wrong.

**Echo-back is mandatory, not optional:**

```
Expiry:  [271017]  →  17 October 2027
```

`271017` is a valid date read as YYMMDD (17 Oct 2027) *and* as DDMMYY (27 Oct 2017). A worker
thinking in the wrong order produces a plausible wrong date with no error. Live echo-back makes
the interpretation visible **before** commit, checked by the person holding the box. This does
more for date accuracy than any validation rule.

**"Same as previous" is the largest single saving.** Ten boxes from one delivery usually share
one LOT and expiry. Pre-fill both from the previous row for the same item; the worker presses
Enter. Ten entries become one entry plus nine confirmations.

**Keyboard only.** Dialog opens with the first field focused; Enter advances; Enter on the last
field submits and returns focus to the scan box. No click anywhere — hands stay on scanner and
keyboard, which matters with gloves.

**One dialog.** LOT, expiry and quantity in a single pass, each sensibly defaulted.

**Validation is loud, immediate and non-destructive.** Invalid input → red plus error beep,
field stays focused, **what was typed is preserved** so one character can be fixed rather than
retyping. Audible success confirmation, so the worker need not look up from the box.

---

## 9. Internal barcodes

**DECIDED.** For products the manufacturer ships with no barcode.

Generate sequential **EAN-13 codes in the GS1 restricted-circulation range** with a computed
check digit.

| Property | Benefit |
|---|---|
| Reserved range | cannot collide with any manufacturer GTIN |
| Valid EAN-13 | passes check-digit validation |
| Standard symbology | any scanner reads it, any label printer prints it |
| Recognisable prefix | visibly internal |

**UNVERIFIED:** the exact reserved prefixes (`02`, `04`, `20`–`29` are the commonly cited
ranges) must be confirmed against the GS1 General Specifications before implementation. Risk is
low — any consistently chosen and documented internal range avoids collision — but the value
should be confirmed rather than assumed.

### 9.1 Two label kinds

A critical distinction: an internal **identifier** label is printed **once per item type** and
reused forever, whereas LOT and expiry change **every delivery**. An identifier label therefore
cannot carry LOT or expiry — the label would be wrong on the next delivery.

| Label | Scope | Contents | For |
|---|---|---|---|
| Identifier label | per item type, printed once | internal GTIN | no-barcode items **without** expiry |
| **Batch label** | **per batch, printed at receiving** | internal GTIN + LOT + expiry | no-barcode items **with** expiry |

The batch label is what keeps the manual-typing decision honest: LOT and expiry are typed
**once** at receiving, the label is printed and applied, and **every downstream scan — packing,
dispatch — reads it.** No typing anywhere after receiving.

A label printer at the receiving station is therefore required. **Confirmed available** (to be
replaced if the existing unit is unserviceable).

An internal barcode makes a no-barcode item behave as a plain-GTIN item. It cannot make it a
GS1 product, because that requires manufacturer-printed data the product does not have.

---

## 10. Serial numbers

**DECIDED: capture without stock tracking.**

**VERIFIED:** AI 21 is present inside the DataMatrix, and for the affected item types LOT, REF,
expiry and production date are all identical across units — **the serial is the only
distinguishing field.**

| Approach | Chosen |
|---|---|
| Ignore serials | no |
| **Capture without tracking** | **yes** |
| Full ERPNext `has_serial_no` tracking | no — would force one scan per unit |

### Why

**Scoping is automatic.** A serial is stored only when the barcode contains AI 21. Items
without one store nothing. **No per-item flag and no configuration** — the barcode decides.

**The cost asymmetry is decisive.** Capturing costs almost nothing. Not capturing is
irreversible: if a customer asks in 2028 which serial was supplied in 2026 and it was not
recorded, there is no way to find out.

**The manufacturer has already decided these units need individual identity.** Manufacturers do
not serialise consumables. The choice is only whether to preserve or discard information that
arrives for free.

**The traceability chain completes by itself.** The same code is scanned at receiving and again
at packing, so "serial X went to customer Y" is a by-product of scans already happening — zero
extra steps.

### Requirements

- Serials are **excluded from the merge key**, so units still combine into one row. Including
  them would produce one row of qty 1 per unit.
- Storage must hold **many serials per row**.
- Storage must be **searchable by serial.** Without this, serials can be stored and still not
  found — which is worse than useless, because it looks like traceability without being it.

Use cases: unit-level recall (without serials, an entire LOT must be recalled from every
customer, including good units); a hospital asking which unit was supplied; a returned
defective item.

---

## 11. Batch records — the missing link

**The prerequisite that was previously mis-classified as future work.**

Enabling `has_batch_no` is not a configuration toggle:

1. **ERPNext requires a `Batch` document** for any `batch_no` used in a stock transaction. The
   deployed script writes the LOT string into `batch_no` and never creates a Batch, so
   submission would fail with *"Batch X does not exist"*.
2. **Expiry belongs on the Batch.** FEFO, expired-stock reporting and the packing FEFO check all
   read `Batch.expiry_date`. Expiry currently goes to `custom_expiry_date` on the receipt row —
   a field the rest of ERPNext knows nothing about. **This is why FEFO never fires.**
3. **Existing stock becomes a migration problem.** Switching an item with existing stock to
   `has_batch_no = 1` leaves a balance with no batches while all future transactions demand
   them. Requires a Stock Reconciliation plan **before** the flag is changed.
4. **Serial tracking is a separate decision** and must never be global.

**UNVERIFIED:** ERPNext's exact behaviour when an explicit `batch_no` is supplied that does not
yet exist varies with the `create_new_batch` flag and version. Must be confirmed empirically on
test before Phase 2 is considered complete.

`Batch.custom_source_gtin` records the GTIN that produced each batch. This gives per-REF stock
visibility through batches when a product has two REFs — the chosen solution for that case — and
is useful regardless as provenance.

---

## 12. FEFO

**DECIDED: warning only, never blocking.**

Earlier-expiring stock may sit in a distant warehouse while a delivery is urgent. A hard block
would stop legitimate work for a condition the worker often cannot resolve.

Two additions:

1. **An audit trail is required for warning-only to be defensible.** A transient alert is not
   evidence. `custom_fefo_warning` is already stored on the row; also record **who proceeded
   despite the warning, and when.** That preserves operational flexibility *and* a reviewable
   position.
2. **Warehouse scope must be deliberate.** The current query is hardcoded to `Main - Inmed`, so
   earlier-expiring stock elsewhere produces no warning at all. **Keep it warehouse-local** —
   warnings people cannot act on get ignored, which erodes the value of all warnings — but make
   the warehouse configurable rather than hardcoded.

FEFO becomes functional in Phase 2, automatically, once Batch records carry expiry dates. No
separate FEFO work is required.

---

## 13. Privileges

Full matrix in `docs/privileges/barcode-privileges.md`.

| Privilege | Roles |
|---|---|
| Expired-receipt override | `Ops - Directors`, `System Manager` |
| Future-production override | `Ops - Directors`, `System Manager` |
| Edit expiry date | `Ops - Directors`, `System Manager` |
| Write `Barcode Settings` | `Ops - Directors`, `System Manager` |
| Link barcode to existing item | `Ops - Purchasing Manager`, `Ops - Inventory Manager`, `Ops - Directors`, `System Manager` |
| Create new item from scan | `Ops - Purchasing Manager`, `Ops - Directors`, `System Manager` |
| Flag unknown barcode | everyone |
| Manual LOT/expiry entry | `Ops - Inventory Manager`, `Ops - Directors`, `System Manager` |

`Administrator` is deliberately excluded — it is a break-glass account and should not appear in
business flows.

**Enforcement must be structural, not client-side.** Field `permlevel` plus a Custom DocPerm,
which Frappe enforces server-side on every path including the REST API. A client-side read-only
setting is theatre — the API, Data Import and `bench console` all ignore it. The server
validation script additionally checks the role to produce a clear business error rather than a
raw permission error.

Overrides sit on the Purchase Receipt **header**, so a Director sets one once for a whole
receipt and need not be present for each scan.

---

## 14. Scanner requirements

**VERIFIED: the current scanner cannot read DataMatrix, and items exist whose only barcode is a
DataMatrix.** Those items are currently unscannable — no identity, no LOT, no expiry. No
software can fix this.

### Purchase specification

| Requirement | Why |
|---|---|
| **2D imager** (not laser or linear) | linear scanners physically cannot read DataMatrix; some items have no other barcode |
| **Transmit GS separator (FNC1)** | the only reliable way to delimit AI 10 from AI 21 (section 5.5) |
| **Transmit symbology prefix** (`]C1` / `]d2`) | distinguishes a GS1 barcode from a plain one |
| **Real-time mode** — not batch/store-and-forward | batch mode transmits accumulated scans at once, which breaks the scan-then-popup flow entirely |
| Configured identically across all units | otherwise the same product yields different data depending on which scanner is used — bugs that appear random and are very hard to diagnose |

Every new scanner is verified against this list using the diagnostic tool before use.

### Barcode Diagnostic screen

With manual entry restricted to an emergency path, a regular worker has no workaround when a
scan fails. The diagnostic tool is therefore a **dependency, not a convenience.**

It displays, for any scan:

- the exact characters received, control characters visible
- the prefix detected
- each AI found and its value
- parsed LOT, expiry, production date, serial
- the normalised GTIN-14
- whether the check digit passed
- whether an item matched

A new scanner is validated in two minutes. A worker's complaint is diagnosed by asking them to
scan it here.

---

## 15. Testing requirements

Regression coverage required before Phase 1 can be called complete:

| Area | Must assert |
|---|---|
| Parsing | each observed real barcode parses to its expected fields |
| Lowercase prefix | `]c1` parses identically to `]C1` |
| GTIN normalisation | all three lengths resolve to the same item |
| Check digit | a corrupted digit is rejected |
| Dates | 31 Feb, 31 Apr, 29 Feb in a non-leap year all rejected |
| Sliding window | `50` → 2050, not 1950 |
| Merge quantity | receiving qty 5 then merging yields **5**, not 1 — defect D-02 |
| Merge key | differing warehouse or rate does **not** merge |
| Single-barcode products | can be received at all — defect D-01 |
| Packing batch match | scanning LOT-B does not overwrite LOT-A — defect D-03 |
| Server validation | a direct API save of expired stock without override is rejected |
| Manual packing | an item requiring LOT cannot be checked off without one |
| Merge guard | a failed merge does not leave the scanner dead — defect D-09 |

Per `AGENTS.md`: saving a Server Script does not prove it runs. Every server script must be
executed and asserted on.

---

## 16. Defect register

All verified against deployed code. **None are fixed.**

### Silently produce wrong data

| ID | Defect | Consequence |
|---|---|---|
| D-01 | Single-barcode products unreceivable; `gs1_is_ref_barcode` is dead code | a whole product category cannot be received |
| D-02 | Merge adds hardcoded `+1`, ignoring row qty, then deletes the source row | **silent quantity loss** |
| D-03 | Packing scan matches on item only, then overwrites that row's batch | **silent traceability corruption** |
| D-04 | Server parser uses `raw.index("17")`, matching `17` inside a GTIN | **corrupts valid barcodes** |
| D-05 | Case-sensitive prefix in all three parsers | ~3% silent failures, measured |
| D-06 | No GTIN normalisation | same product fails depending which barcode is scanned |
| D-07 | `DD=00` → day 01 instead of end of month | expiry up to 30 days early; false expired blocks |
| D-13 | Warehouse absent from merge key | stock recorded in the wrong warehouse |
| D-14 | Rate absent from merge key | valuation silently changed |

### Inert — deployed but never executes

| ID | Defect |
|---|---|
| D-15 | `Item.custom_requires_gs1_lot_scan` never created on either environment |
| D-16 | All 500 items have `has_batch_no`, `has_expiry_date`, `has_serial_no` = 0 |
| D-20 | FEFO queries `Batch.expiry_date`; no Batch records exist |
| D-21 | Zero barcodes registered against any item |

### Unusable or unprotected

| ID | Defect |
|---|---|
| D-08 | 31 Feb / 31 Apr / 29 Feb non-leap accepted into the database |
| D-09 | `gs1_is_merging` boolean can latch permanently — scanner dies silently, needs a page reload |
| D-10 | Manual packing checkbox bypasses LOT capture entirely |
| D-11 | One scan per unit forced — ~3 minutes per box of 50 |
| D-12 | Fixed year pivot at 50 contradicts GS1; breaks on 2050+ expiry |
| D-17 | No server-side validation — API and Data Import bypass every date rule |
| D-18 | `deploy_items.py` runs `DELETE FROM tabItem Barcode` on every item deploy |
| D-19 | Packing problem alerts fire once per case; a new problem after review never alerts |

### D-09 fix — why a timestamp, not a boolean

Replace the boolean with a timestamp and treat a stale value as inactive:

```
gs1_merge_started_at = <time> or null
active = gs1_merge_started_at && (now - gs1_merge_started_at) < 5000
```

**Staleness is computed, not cleared.** A boolean plus a recovery timer still depends on a
mechanism running, and mechanisms can fail to run. A timestamp **expires by arithmetic** —
there is no cleanup step to miss and no state that can get stuck. Plus `try/finally` to clear it
promptly in the normal case, and a row-state re-check so even a scan in the theoretical gap
cannot corrupt anything.

### D-19 fix — signature, not a flag

Store a signature of the current problem set and alert whenever it **changes and is non-empty**.

| Situation | Flag reset | Signature |
|---|---|---|
| Problem reviewed, then a new problem | alerts | alerts |
| Unreviewed problem, second different problem appears | **silent** | alerts |
| Same problem, case saved 20 times | silent | silent |

---

## 17. Phased plan

| Phase | Content | Ledger impact | Reversible |
|---|---|---|---|
| **1** | Parsing, validation, normalisation, all defect fixes, unknown-barcode tiers, manual-entry UX, diagnostic screen, server validation. Data lands in receipt custom fields. | **none** | yes |
| **2** | **Batch record creation** from scanned data, with correct expiry and `custom_source_gtin`. `has_batch_no` stays 0. | **none** | yes |
| **3** | Enable `has_batch_no` per Item Group, with a Stock Reconciliation plan for existing balances. | **significant** | per group |
| **4** | Serial-level tracking only where genuinely required. | significant | per item |

**Phase 2 delivers substantial value at zero ledger risk.** Batch records with expiry dates make
FEFO work, make expired-stock reporting possible, and prove the pipeline end to end — all while
`has_batch_no` remains 0, so nothing about existing stock behaviour changes.

Phase 3 is the only genuinely risky step, and by then Phases 1 and 2 have proved the data is
correct.

**Phase 3 will not begin until the logic and documentation are complete and verified**
(**DECIDED**).

---

## 18. Open items

| Item | Status |
|---|---|
| GS1 spec wording for AI 17 `DD=00` | **UNVERIFIED** — confirm before implementing section 5.3 |
| Exact GS1 internal prefix range | **UNVERIFIED** — confirm before implementing section 9 |
| Real `]d2` + GS output | pending a 2D scanner |
| ERPNext behaviour supplying a non-existent `batch_no` | **UNVERIFIED** — confirm on test in Phase 2 |
| Scanner make, model, quantity | pending purchase |
| Does one Purchase Receipt ever span multiple warehouses | not blocking — warehouse joins the merge key regardless |
| Serial storage structure | to be specified in Phase 1 design; must be searchable |

---

## 19. Related files

**Deployed and affected:**

- `deploy/test/work/client/GS1 Barcode Parser.js`
- `deploy/test/work/client/Dispatch Case-Packing Scan.js`
- `deploy/test/work/client/Task-Product Work Area.js`
- `deploy/test/work/server/dispatch_case_packing_scan.py`
- `deploy/test/work/server/task_lookup_product_barcode.py`
- `deploy/test/work/server/task_mark_item_packed.py`
- `deploy/test/work/server/task_mark_items_packed_batch.py`
- `deploy/test/work/server/Dispatch Case-packing-problem-alerts.py`

**Prerequisite (D-18):** `deploy/prod/scripts/deploy_items.py`

**Historical, corrected, superseded by this document:**

- `docs/ERPNext Barcode/IMPLEMENTATION_READY.md`
- `docs/ERPNext Barcode/FIXES_DOCUMENTATION.md`

**Evidence:** `Scans for ERPNEXT.txt` (real scanner output), `CX-01S` product label photograph.

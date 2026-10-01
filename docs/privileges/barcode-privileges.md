# Barcode Privileges

Decisions made 2026-09-30 / 2026-10-01. Specification: `docs/ERPNext Barcode/BARCODE_SYSTEM.md`.

**None of these are implemented yet.** The "where enforced" column states the *intended*
mechanism. Nothing in this file is currently in force except where marked as framework
behaviour.

---

## Summary

| Privilege | Roles |
|---|---|
| Expired-receipt override | Directors, System Manager |
| Future-production-date override | Directors, System Manager |
| Edit expiry date | Directors, System Manager |
| Write `Barcode Settings` | Directors, System Manager |
| Link barcode to existing item | Purchasing Manager, Inventory Manager, Directors, System Manager |
| Create new item from an unknown scan | Purchasing Manager, Directors, System Manager |
| Flag unknown barcode for review | everyone |
| Manual LOT / expiry entry | Inventory Manager, Directors, System Manager |
| Manual packing confirmation | everyone, but only for items not requiring LOT/expiry |

---

## 1. Expired-receipt override

**What** — tick `custom_allow_expired_barcode_receipt` to receive stock whose expiry date has
passed. Requires a written reason in `custom_barcode_override_reason`.

**Who** — `Ops - Directors`, `System Manager`

**Where enforced** — field `permlevel` + Custom DocPerm on the override and reason fields, plus a
role check in the Purchase Receipt validation Server Script.

**When** — 2026-09-30

**Why** — accepting expired medical stock is a commercial and compliance decision, not an
operational one. `Ops - Purchasing Manager` was considered and rejected despite being closest to
the receipt: keeping it at Director level makes it rare and visible, which is the entire purpose
of an override.

Availability concern is smaller than it looks: the override sits on the Purchase Receipt
**header**, so a Director sets it once for a whole receipt and need not be present for each scan.
For a planned delivery of known-expired stock that is one phone call before the truck arrives.

If availability proves a recurring problem, adding `Ops - Inventory Manager` is easy. Starting
tighter is the safer direction.

---

## 2. Future-production-date override

**What** — tick `custom_allow_future_production_date`. Requires a written reason.

**Who** — `Ops - Directors`, `System Manager`

**Where enforced** — as privilege 1.

**When** — 2026-09-30

**Why** — same reasoning. A future production date usually means a misread barcode or a
mislabelled product, so overriding it should be deliberate and attributable.

Note: expiry on or before production date is **blocked unconditionally**, with no override. That
combination is impossible rather than exceptional.

---

## 3. Edit expiry date

**What** — change `custom_expiry_date` by hand instead of taking it from a barcode.

**Who** — `Ops - Directors`, `System Manager`

**Where enforced** — field `permlevel` + Custom DocPerm.

**When** — 2026-09-30

**Why** — expiry must come from the barcode. Hand-typed dates bypass parsing, calendar
validation and check-digit verification, and a wrong expiry on medical stock is exactly the error
the system exists to prevent.

Corrections are still necessary sometimes, so the capability exists — restricted and attributable
rather than removed.

The field is currently `read_only = 0`, so **any user who can edit the receipt can type an expiry
date today.** Closing this is part of Phase 1.

---

## 4. Write `Barcode Settings`

**What** — change expiry notice/warning thresholds and date sanity ranges, globally or per Item
Group.

**Who** — `Ops - Directors`, `System Manager`. Read access for everyone, since the client needs
to fetch them.

**Where enforced** — DocPerm on the `Barcode Settings` single DocType.

**When** — 2026-09-30

**Why** — these thresholds decide when stock is flagged as near-expiry, which affects purchasing
and customer commitments. Regular warehouse staff should not be able to silence a warning by
changing a number.

Per-Item-Group overrides exist because thousands of products with differing consumption rates and
lead times cannot share one threshold.

---

## 5. Link a barcode to an existing item

**What** — on scanning an unrecognised barcode, link it permanently to an existing Item
(Tier 1, specification section 8.1).

**Who** — `Ops - Purchasing Manager`, `Ops - Inventory Manager`, `Ops - Directors`,
`System Manager`

**Where enforced** — server-side role check in the registration API.

**When** — 2026-10-01

**Why** — this is the main path for building the barcode database, which is currently empty, so
it must be available to the people actually receiving goods. But a wrong link sends every future
scan of that barcode to the wrong item, so it is not open to everyone.

**Framework safeguard already in force:** ERPNext's `Item.validate_barcode()` rejects a barcode
already attached to a different Item, throwing *"Barcode {0} already used in Item {1}"*. A
barcode cannot be linked to two items regardless of role. This is existing ERPNext behaviour, not
something built here.

---

## 6. Create a new item from an unknown scan

**What** — quick-create a real, permanent Item from the unknown-barcode dialog and link the
barcode to it (Tier 2, section 8.2).

**Who** — `Ops - Purchasing Manager`, `Ops - Directors`, `System Manager`

**Where enforced** — server-side role check in the creation API, plus standard Item DocType
permissions.

**When** — 2026-10-01

**Why** — deliberately narrower than privilege 5. Linking an existing item is reversible;
creating a duplicate Item is among the most expensive data problems to unwind, because stock,
prices and history all split across the duplicates.

`Ops - Inventory Manager` is excluded here but included in privilege 5, for exactly that reason.

---

## 7. Flag an unknown barcode for review

**What** — log an unrecognised barcode for later resolution and carry on scanning (Tier 3,
section 8.3).

**Who** — **everyone**

**Where enforced** — no restriction.

**When** — 2026-10-01

**Why** — receiving is time-critical, with a truck waiting and possibly cold chain. The process
must never hard-stop. Every worker needs a way to proceed, and this one cannot damage anything: it
writes a log record and nothing else.

Without it, a worker facing an unknown barcode and no permission to resolve it has no legitimate
action at all — which is how workarounds get invented.

---

## 8. Manual LOT / expiry entry

**What** — type LOT and expiry by hand when no barcode can supply them: a damaged or unreadable
label, or a no-barcode item with an expiry date. Requires a reason, which is logged.

**Who** — `Ops - Inventory Manager`, `Ops - Directors`, `System Manager`

**Where enforced** — server-side role check in the manual-entry API.

**When** — 2026-10-01

**Why** — the standing decision is to avoid manual typing wherever possible, so this is an
emergency route rather than a workflow. Restricting it keeps it rare and attributable.

But it must **exist**, and it must be reachable by someone usually present at receiving — hence
`Ops - Inventory Manager` rather than Directors only. A rule that stops a delivery gets
circumvented, and the circumvention is worse than the rule.

Note `Ops - Inventory Manager` appears here but not in privilege 1: typing a LOT from a damaged
label is an operational act, whereas accepting expired stock is a commercial decision.

---

## 9. Manual packing confirmation

**What** — tick an item as packed without scanning it.

**Who** — everyone, **but only for items that do not require LOT and expiry.**

**Where enforced** — server-side check in `task_mark_item_packed` and
`task_mark_items_packed_batch`, plus a client-side disabled state with a tooltip for usability.

**When** — 2026-10-01

**Why** — this is a capability restriction rather than a role restriction. For an item requiring
LOT and expiry, a manual tick marks the row complete with **no batch data at all**: the row looks
packed, traceability is empty, and nothing flags it.

Both APIs currently have this hole — neither checks whether the item needs LOT data.

For a genuinely unscannable label the correct route is privilege 8 (manual entry with a reason),
not the checkbox. That way the data is still captured and the exception is attributable.

---

## Excluded from all of the above

**`Administrator`** — a break-glass account that should not appear in business flows, per
`AGENTS.md`.

**Task completion** — unrelated to barcodes but worth restating, since it is the strictest rule
in the system: completion is reserved to the user who accepted the task, with **no exemption for
anyone**, including System Manager and Directors. Privileged users may edit a stuck task but must
never assert that someone else's work was performed.

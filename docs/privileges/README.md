# Privileges

Who is allowed to do what, where it is enforced, and why it was decided that way.

## Why this folder exists

Role decisions get made in conversation and then lost. Six months later nobody remembers whether
a restriction was deliberate or accidental, or whether a documented privilege is actually in
force.

This folder records each privilege decision with enough context that a future change can be
informed rather than guessed.

## Files

| File | Covers |
|---|---|
| `barcode-privileges.md` | Barcode scanning, receiving, overrides, item/barcode creation |

Add one file per domain as the need arises. Keep them small and specific.

## Required fields for every entry

Every privilege entry records five things. The third is the one that matters most.

| Field | Why |
|---|---|
| **What** | plain description of the capability |
| **Who** | the roles that hold it |
| **Where enforced** | field `permlevel`, server script, client gate, or framework behaviour |
| **When decided** | date |
| **Why** | the reasoning, so a future change is informed |

### Why "where enforced" matters most

A documented privilege that is only enforced in a Client Script is **not enforced**. Client
scripts are bypassed by the REST API, Data Import, `bench console`, and anyone with a browser
console open.

Recording the enforcement point makes a privilege **auditable** — you can check whether it is
genuinely in force rather than assuming it. A privilege with "client gate only" in that column
is a known gap, not a control.

## Enforcement mechanisms, strongest first

| Mechanism | Strength | Notes |
|---|---|---|
| Framework behaviour | strongest | enforced by Frappe/ERPNext itself on every path; nothing to maintain |
| Field `permlevel` + Custom DocPerm | strong | enforced server-side on every path including the REST API |
| Server Script check | strong | produces a clear business error; must be on the correct event (see the `Before Save` note in `AGENTS.md`) |
| Client Script gate | **usability only** | never rely on it for integrity |

Prefer a `permlevel` for "who may change this field", and a Server Script for "under what
conditions". Use a Client Script only to make the restriction visible and pleasant, never to
impose it.

## Conventions

- `Administrator` is excluded from business privileges. It is a break-glass account and should
  not appear in normal flows.
- There is no Developer role. Developers act as `System Manager`.
- Start tighter and loosen on evidence. Widening a permission is easy; narrowing one after people
  have come to rely on it is painful.
- When a privilege changes, update the entry rather than replacing it — keep the date and
  reasoning history.

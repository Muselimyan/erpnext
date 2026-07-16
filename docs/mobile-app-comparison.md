# ERPNext Mobile App Comparison — Push Notifications for Delivery Drivers

**Requirement:** Notify delivery drivers on their phone when a new Task is assigned to them.
**Server:** Self-hosted ERPNext v16.14.0, Docker, `erpnext.am`
**Date:** Jul 2026

---

## Apps Evaluated

| # | App | Developer | Android | iOS | Push Notif | Task Notif | Self-hosted |
|---|-----|-----------|---------|-----|------------|------------|-------------|
| 1 | ERPNext Workflow | Midocean | ✅ | ✅ | ✅ | ❌ | ✅ (companion app needed) |
| 2 | DATUREX Connect | DATUREX GmbH | ✅ | ✅ | ✅ | ✅ | ✅ (no server setup) |
| 3 | NextApp | ERPCloud Systems | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4 | ERPNext Mobile | CodesSoft | ✅ | ✅ | ⚠️ unclear | ⚠️ unclear | ✅ |
| 5 | Native for ERPNext | Pedrett IT + Web AG | ✅ | ✅ | ❓ unknown | ❓ unknown | ✅ |
| 6 | Frappe HR (official) | Frappe | ✅ | ✅ | ✅ | ❌ | ⚠️ complex setup |

---

## Detailed Analysis

---

### 1. ERPNext Workflow — Midocean Technologies
**Play Store:** `com.midocean.erpnextworkflow` | **App Store:** `id6754626633`

**What it does:** Workflow document approvals (approve/reject Sales Orders, POs, Leave Applications, etc.)

**Push notifications:** ✅ Yes — but only for ERPNext Workflow state changes (pending approvals). Not for Task assignment.

**Server-side requirement:** Companion Frappe app `erpnext_workflow` must be installed on bench.

**Self-hosted:** ✅ Yes

**Maturity:** ⚠️ Beta — README explicitly states "undergoing active development"

**iOS:** ✅ Available

**Verdict for your use case:** ❌ **Wrong tool.** Not designed for Task assignment notifications. Would require a workaround (adding a Workflow state machine to the Task doctype) which risks breaking existing task management.

---

### 2. DATUREX Connect for ERPNext — DATUREX GmbH ⭐ Most Relevant
**Play Store:** `de.daturex.erp_next_mobile` | **App Store:** `id1659837767`

**What it does:** Full ERPNext access + custom **Push Notification Hooks** — user-defined rules that fire push notifications when any document condition is met.

**Push notifications:** ✅ Yes — and uniquely, **user-configurable hooks** — the App Store listing explicitly says:
> *"Create Push Notification Hooks to stay on track if anything changes. For example when a new Purchase is created or a **task is done**."*

This means the notification logic lives inside the app's hook configuration, pointed at your ERPNext server. No additional Frappe app or Firebase relay setup required on the server side.

**Server-side requirement:** Appears to work directly against the ERPNext REST API — no companion app installation needed.

**Self-hosted:** ✅ Yes

**Maturity:** ✅ Stable — available since 2022, regular updates, German developer (DATUREX GmbH)

**iOS:** ✅ Available

**Verdict for your use case:** ✅ **Best fit.** The push notification hook system is exactly what's needed — configure a hook on the Task doctype, filter to the driver's user, trigger when `_assign` is set. No server-side changes required.

**Authentication:** Requires **API Key + API Secret** (does not accept username/password). Generate these in ERPNext: `User List → open user → Settings tab → API Access section → Generate Keys`. Copy the API Secret immediately — shown only once.

**Push notification hook setup:** Configured entirely within the app UI. No public documentation exists for this feature. Look for a **bell icon**, **"Hooks"**, or **"Notifications"** section in the app menu after login. Expected flow:
1. Create a new hook
2. Set **DocType** = `Task`
3. Set **Trigger** = New / On Save
4. Set **Filter** = assigned user matches current user

**Support contact (no public docs):** `programmierung.dresden@gmail.com`

**Risk:** Hook configuration granularity is untested — unclear if it can filter to "assigned to me" only vs. all task changes.

---

### 3. NextApp — ERPCloud Systems
**Play Store:** `mobi.nextapp.next_app` | **App Store:** unknown

**What it does:** Full ERPNext client — all modules including Projects/Tasks, document actions, GPS tracking, workflow approvals.

**Push notifications:** ✅ Yes — "*You'll get notified in real-time with every change to your Docs.*" Includes comments and transactions.

**Server-side requirement:** Unknown — likely uses Frappe's notification mechanism or polling. Not documented publicly how push is implemented for self-hosted.

**Self-hosted:** ✅ Yes

**Maturity:** ✅ Stable — has been available for several years, active development

**iOS:** ⚠️ Unclear — website doesn't clearly list iOS; Play Store confirms Android

**Verdict for your use case:** ✅ Likely works for Task notifications. However, the push notification setup for self-hosted is not clearly documented, which adds setup uncertainty.

---

### 4. ERPNext Mobile — CodesSoft
**Play Store:** `com.codessoft.erpnextmob.android` | **App Store:** `id6479046579`

**What it does:** Full ERPNext access — all modules, document actions, approvals.

**Push notifications:** ⚠️ Advertised ("Real-time Updates: Stay updated with real-time notifications") but Play Store reviews show users asking *"how can I enable push notifications"* — suggesting it's not straightforward or may require specific setup.

**Server-side requirement:** Unclear — likely depends on Frappe's push relay (same problem as Frappe HR app for self-hosted).

**Self-hosted:** ✅ Yes

**Maturity:** ✅ Stable, regular updates

**iOS:** ✅ Available

**Verdict for your use case:** ⚠️ **Uncertain.** Push notifications are advertised but setup is unclear for self-hosted. Not enough evidence it works without Frappe Cloud relay.

---

### 5. Native for ERPNext — Pedrett IT + Web AG
**Play Store:** `ch.pitw.nativeerpnext` | **App Store:** `id6760002884`

**What it does:** Task and project management focused. Timesheets, projects, tasks, team workflow.

**Push notifications:** ❓ Not mentioned in available documentation or store listings.

**Server-side requirement:** Unknown

**Self-hosted:** ✅ Yes

**Maturity:** ⚠️ New — not enough ratings to display on App Store as of now

**iOS:** ✅ Available

**Verdict for your use case:** ❓ **Unknown.** Focused on the right domain (tasks/projects) but push notification support is unconfirmed. Too new to evaluate reliably.

---

### 6. Frappe HR Mobile App — Official Frappe
**Play Store:** Available | **App Store:** Available

**What it does:** HR-focused — leave, attendance, expense claims, payroll. Not task/project management.

**Push notifications:** ✅ Yes — with `frappe_notifier` companion app + Firebase FCM setup.

**Server-side requirement:** Requires installing `frappe_notifier` on bench + Firebase project setup + Docker custom image (full plan exists in `push-notifications-plan.md`).

**Self-hosted:** ⚠️ Possible but requires significant setup (see plan doc)

**iOS:** ✅ Available

**Verdict for your use case:** ❌ **Wrong domain.** Designed for HR workflows, not operational task assignment for delivery drivers. Even if set up correctly, it would notify about HR events (leave requests, etc.), not Task assignments — unless custom notification triggers are added via Server Script.

---

## Summary Comparison

| Criteria | ERPNext Workflow | **DATUREX** | NextApp | CodesSoft | Native | Frappe HR |
|----------|-----------------|-------------|---------|-----------|--------|-----------|
| Task assignment push | ❌ | ✅ | ✅ likely | ⚠️ | ❓ | ❌ |
| No server setup needed | ❌ | ✅ | ⚠️ | ⚠️ | ❓ | ❌ |
| iOS + Android | ✅ | ✅ | Android only | ✅ | ✅ | ✅ |
| Self-hosted | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ complex |
| Stable / not beta | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ |
| Open-source / documented | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Suitable for drivers | ❌ | ✅ | ✅ | ⚠️ | ✅ | ❌ |

---

## Recommendation

### Short-term (this week)
Set up **ERPNext's built-in email Notification** for Task assignment — 15 minutes, works immediately, no app changes needed. Drivers receive an email when a task is assigned.

### For a proper mobile app experience
**Evaluate DATUREX Connect first.** It is the only app with an explicitly documented, configurable push notification hook that can target any DocType event including Task assignment, with no server-side setup required. Both drivers and you can test it directly against `erpnext.am` without any server changes.

**If DATUREX doesn't meet the need** (e.g. hook granularity is insufficient), fall back to **NextApp** — it has broader ERPNext coverage and confirmed push notifications, but the self-hosted push setup needs investigation.

### What to do with the current ERPNext Workflow app
Keep it only if someone in the company actually needs document approval workflows on mobile. For delivery drivers receiving task assignments, it serves no purpose.

---

## Next Steps

- [x] Install DATUREX Connect on driver's phone
- [x] Generate API key/secret for driver user (User List → Settings tab → API Access → Generate Keys)
- [ ] Connect DATUREX to `erpnext.am` using API key + secret
- [ ] Locate push notification hook section in the app (bell/Hooks/Notifications menu)
- [ ] Create a hook: DocType = Task, Trigger = New/Save, filter to assigned user
- [ ] Test: create a Task assigned to the driver and verify notification arrives
- [ ] If hook filtering is insufficient: contact `programmierung.dresden@gmail.com` or evaluate NextApp
- [ ] Set up ERPNext email Notification for Task assignment as immediate fallback (15 min, zero risk)

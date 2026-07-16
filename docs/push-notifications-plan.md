# Push Notifications for Delivery Drivers — Implementation Plan

**Goal:** Enable push notifications on the ERPNext mobile app for delivery drivers so they receive alerts when new tasks are created or assigned.

**Mobile app confirmed:** [ERPNext Workflow](https://play.google.com/store/apps/details?id=com.midocean.erpnextworkflow) by Midocean Technologies (`com.midocean.erpnextworkflow`)

**Status:** Plan — pending review before execution.

**Verified server state (Jul 3 2026):**
- Frappe `16.15.0` / ERPNext `16.14.0` (v16)
- Image: `frappe/erpnext:v16.14.0` (official, not custom)
- Compose file: `/home/vahe/frappe-compose.yml`
- `pull_policy: missing` — image is NOT auto-pulled on restart
- Only the `sites` volume is mounted; the `apps` directory lives inside the image layer

---

## ⚠️ App Mismatch — Read First

**ERPNext Workflow** (Midocean) sends notifications for **ERPNext Workflow approval state changes** — e.g. "a purchase order is waiting for your approval." It is **not designed to notify drivers when a Task is assigned to them.**

The requirement is: *"notify driver when a new Task is assigned."*
The app does: *"notify approver when a workflow document needs action."*

These are different things. **The current app choice is wrong for this requirement.**

---

## Options

### Option 1 — ERPNext Built-in Email Notification (easiest, zero setup)
ERPNext can send an email to the assigned user whenever a Task is created or assigned. If drivers have email on their phones and notifications enabled, this effectively works as a push notification.

- **Setup time:** ~15 minutes (one Notification rule in ERPNext UI)
- **Cost:** Free (uses existing email account)
- **Reliability:** High — email delivery is well established
- **Downside:** Requires drivers to have email on their phone; not a native app notification

### Option 2 — Replace the App: Use a Different Mobile App
Switch drivers to a mobile app that actually supports Frappe's notification system. Two solid options:

| App | Notes |
|-----|-------|
| **Frappe HR mobile app** (official) | Works with Frappe's push relay; requires `frappe_notifier` setup (original plan) |
| **Native for ERPNext** ([Play Store](https://play.google.com/store/apps/details?id=ch.pitw.nativeerpnext)) | Third-party, focused on tasks/projects, actively developed, not beta |

This is the cleanest path if drivers need a real mobile app experience going forward.

### Option 3 — Keep the App, Add an ERPNext Workflow on Task (workaround)
Create an ERPNext Workflow state machine on the Task DocType. When a task is assigned to a driver, it enters a "Assigned to Driver" state — which triggers the ERPNext Workflow app's notification.

- **Complexity:** Medium — requires careful Workflow design so it doesn't break existing Task management
- **Risk:** The Task doctype already has a `status` field and may conflict with a Workflow overlay
- **Upside:** No app change required for drivers

### Option 4 — Custom Server Script → Firebase Direct Push
A server script fires on Task `After Save`, checks if `_assign` changed, and calls Firebase FCM HTTP API directly to push to the driver's device token. Requires a way for the mobile app to register device tokens (the ERPNext Workflow app may or may not expose this).

- **Complexity:** High — requires Firebase setup + device token management
- **Not recommended** unless Options 1–3 are ruled out

---

## Recommendation

**Start with Option 1** (email notification) — it can be set up today in 15 minutes and solves the immediate problem. In parallel, evaluate whether to replace the app (Option 2) for a better long-term experience.

Option 3 is viable only if switching apps is not possible.

---

## Architecture Overview

```
ERPNext site (erpnext.am)
    └── erpnext_workflow companion app (must be installed on bench)
            └── manages workflow state changes + device token registration
                    └── Firebase Cloud Messaging (FCM)  [mechanism assumed — not fully documented]
                            └── Driver's phone → ERPNext Workflow app
```

---

## Prerequisites

- [ ] Access to Google account to create a Firebase project (free)
- [ ] SSH access to VPS (`ssh -i $env:USERPROFILE\.ssh\vps_erpnext2 root@161.97.83.156`)
- [x] **ERPNext v16.14.0 / Frappe v16.15.0** — confirmed via `bench version`
- [x] **App confirmed:** ERPNext Workflow by Midocean (`com.midocean.erpnextworkflow`) — Android available, iOS version also available on App Store
- [ ] **Clarify notification trigger:** Do drivers need notifications for Task assignment, or for workflow document approvals? (See ⚠️ section above — this affects whether the plan below is sufficient)

---

## Phase 1 — Firebase Project Setup (one-time, ~20 min)

This is done in the browser, no server access needed.

### 1.1 Create Firebase project
1. Go to [https://console.firebase.google.com](https://console.firebase.google.com)
2. Click **Add project** → name it `inmed-erpnext` (or similar)
3. Disable Google Analytics (not needed) → **Create project**

### 1.2 Enable Firebase Cloud Messaging
1. Inside the project, go to **Project Settings** (gear icon) → **Cloud Messaging** tab
2. Confirm FCM is listed (it is enabled by default in new projects)

### 1.3 Get the VAPID key
1. In **Project Settings → Cloud Messaging**, scroll to **Web Push certificates**
2. Click **Generate key pair** — copy and save the **VAPID public key**

### 1.4 Generate Service Account JSON
1. In **Project Settings → Service accounts**
2. Click **Generate new private key** → download the JSON file
3. Rename it to `firebase_service_account.json`
4. **Keep this file private — it has admin access to your Firebase project**

### 1.5 Get Firebase web config
1. In **Project Settings → General**, scroll to **Your apps**
2. Click **Add app → Web** (if no web app exists), register it as `erpnext-am`
3. Copy the `firebaseConfig` object — you will need all fields:
   ```json
   {
     "apiKey": "...",
     "authDomain": "...",
     "projectId": "...",
     "storageBucket": "...",
     "messagingSenderId": "...",
     "appId": "..."
   }
   ```

---

## Phase 2 — Install frappe_notifier (Docker) (~30 min)

> **Docker note — important:** The `apps` directory is **baked into the image layer**, not volume-mounted (only `sites` is a volume). This means:
> - The app **survives `docker restart`, `docker stop/start`, and system reboots** — because `pull_policy: missing` means Docker reuses the existing image
> - The app **disappears** if someone runs `docker compose pull` (image update) or force-recreates the container
> - Phase 5 addresses making it permanent via a custom image

### 2.1 Upload Firebase credentials to server
```powershell
# From local machine (PowerShell)
scp -i $env:USERPROFILE\.ssh\vps_erpnext2 firebase_service_account.json root@161.97.83.156:/tmp/firebase_service_account.json
```

```bash
# On VPS — copy into container bench directory
docker cp /tmp/firebase_service_account.json frappe-backend-1:/home/frappe/frappe-bench/firebase_service_account.json
```

### 2.2 Install the app into the bench
```bash
docker exec -it frappe-backend-1 bash
# Now inside the container:
cd /home/frappe/frappe-bench
bench get-app https://github.com/tridz-dev/frappe_notifier --branch develop
bench --site erpnext.am install-app frappe_notifier
```

### 2.3 Run the initialization script
```bash
# Still inside container, still in /home/frappe/frappe-bench
source ./apps/frappe_notifier/init.sh
```

This script reads `firebase_service_account.json` and configures the relay's Firebase credentials.

---

## Phase 3 — Configure Site (~10 min)

### 3.1 Set relay URL in site config
```bash
# Inside container
bench --site erpnext.am set-config push_relay_server_url "https://erpnext.am"
```

> The site points at itself because `frappe_notifier` makes the bench act as its own relay.

### 3.2 Set hostname in site config (if not already set)
```bash
bench --site erpnext.am set-config hostname "erpnext.am"
```

### 3.3 Restart
```bash
bench restart
# Or from VPS host:
# docker restart frappe-backend-1
```

---

## Phase 4 — Enable in ERPNext UI (~10 min)

1. Log in as Administrator at `https://erpnext.am`
2. Search for **Push Notification Settings** (or go to Integrations → Push Notification Settings)
3. Check **Enable Push Notification Relay**
4. Verify that **API Key** and **API Secret** are auto-generated
   - If missing: check that a **Notification Manager** user exists; generate API key for that user manually
5. Go to **Frappe Notifier Settings** (new doctype added by the app)
6. Fill in:
   - **Project ID** — from Firebase web config
   - **VAPID Public Key** — from Phase 1.3
   - **Firebase Config** — the full JSON object from Phase 1.5
7. Save

---

## Phase 5 — Make Installation Permanent (custom Docker image)

The stack uses `frappe/erpnext:v16.14.0` directly via `/home/vahe/frappe-compose.yml`. Once Phases 2–4 are confirmed working, build a custom image so the app survives any future container recreation.

### 5.1 Create a custom Dockerfile
On the VPS at `/home/vahe/`, create `Dockerfile.custom`:
```dockerfile
FROM frappe/erpnext:v16.14.0
USER frappe
RUN cd /home/frappe/frappe-bench \
    && bench get-app https://github.com/tridz-dev/frappe_notifier --branch develop
```

### 5.2 Build and tag the image
```bash
cd /home/vahe
docker build -f Dockerfile.custom -t frappe-inmed:v16.14.0 .
```

### 5.3 Update the compose file
In `/home/vahe/frappe-compose.yml`, replace every occurrence of:
```
image: frappe/erpnext:v16.14.0
```
with:
```
image: frappe-inmed:v16.14.0
```

### 5.4 Recreate containers from new image
```bash
cd /home/vahe
docker compose -f frappe-compose.yml up -d --force-recreate
```
Then re-run the `init.sh` step (Phase 2.3) and re-apply site config (Phase 3), since fresh containers won't have Firebase credentials baked in yet.

> **Going forward:** When upgrading ERPNext, update the `FROM` line in `Dockerfile.custom` to the new version tag, rebuild, and update the compose file.

---

## Phase 6 — Driver Testing

1. Have a delivery driver open the **Frappe HR mobile app** (logged in as their ERPNext user)
2. Go to **Profile → Settings → Notifications** and enable push notifications
3. The app will request permission on the phone — driver must **Allow**
4. Create a test Task assigned to that driver from ERPNext desktop
5. Confirm the push notification arrives on the phone within ~30 seconds

---

## Risks & Open Questions

| Risk | Impact | Notes |
|------|--------|-------|
| `frappe_notifier` branch `develop` may lag behind Frappe v16 | App may not install cleanly | v16 is current stable; `develop` branch is likely compatible but unconfirmed — test in Phase 2 before proceeding |
| `docker compose pull` or force-recreate wipes the app | Notifications silently stop | Mitigated by Phase 5 (custom image). Current `pull_policy: missing` reduces accidental risk. |
| `firebase_service_account.json` is sensitive | Security | Must not be committed to git or left in `/tmp` after setup |
| Drivers may be using a different app (PWA, old Cordova app) | Phase 6 fails entirely | **Confirm the exact app name/store listing before starting Phase 2** |
| `init.sh` behavior is undocumented | Setup may fail silently | Check the script contents before running; have a rollback plan (uninstall app, remove config key) |

---

## Rollback

If something goes wrong after Phase 2:
```bash
docker exec -it frappe-backend-1 bash
cd /home/frappe/frappe-bench
bench --site erpnext.am uninstall-app frappe_notifier
bench --site erpnext.am set-config push_relay_server_url ""
bench restart
```

---

## Estimated Total Time

| Phase | Time |
|-------|------|
| Phase 1 (Firebase) | ~20 min |
| Phase 2 (Install) | ~30 min |
| Phase 3–4 (Config + UI) | ~20 min |
| Phase 6 (Testing) | ~15 min |
| **Total** | **~85 min** |

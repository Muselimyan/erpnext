# 🚀 POST-LAUNCH ENHANCEMENTS - PRIORITY LIST

## ⚠️ IMPORTANT: Features to Add After Launch

These features were planned but deferred to get the core workflow working for launch.
They should be implemented after the system is live and tested with real users.

---

## 📋 Dispatch Case Packing - Advanced Features

### ✅ COMPLETED (For Launch)
- [x] Create Dispatch Case from Task button
- [x] Auto-copy Task product lines to Dispatch Case as checklist
- [x] Visual checkmarks when items are scanned
- [x] Basic warning if scanning item NOT on checklist

### 🔧 TO DO (Post-Launch Priority)

#### **#4 - Completion Warnings** 🔴 HIGH PRIORITY
**What:** Before completing Dispatch Case, validate all items were scanned
**Behavior:**
- Check if any items from checklist are missing
- Show warning: "⚠️ You haven't scanned: 2x Item A, 1x Item B"
- Option to proceed anyway (with confirmation)
- Option to go back and scan missing items

**Why Important:** Prevents accidentally forgetting items in the warehouse

---

#### **#5 - Stock Warnings** 🔴 HIGH PRIORITY
**What:** Warn when creating Task/Dispatch Case if not enough stock
**Behavior:**
- When adding items to Task product lines, check warehouse stock
- Show warning: "⚠️ Not enough stock in warehouse (Need: 5, Available: 3)"
- Can proceed with confirmation
- Reason: Hospital might have stock, or you'll add items on the way

**Why Important:** Prevents promising items you don't have

---

#### **#6 - Task Update Detection** 🟡 MEDIUM PRIORITY
**What:** Detect when Task product lines change after Dispatch Case created
**Behavior:**
- Dispatch Case checklist is a snapshot from creation time
- If Task product lines are edited after Dispatch Case created, show warning
- Warning on Dispatch Case: "⚠️ Task has been updated since this Dispatch Case was created"
- Packing team can manually adjust Dispatch Case if needed
- Does NOT auto-sync (to prevent mid-packing confusion)

**Why Important:** Prevents confusion when order changes during packing

---

#### **#7 - Substitution Handling** 🟡 MEDIUM PRIORITY
**What:** Allow packing substitute items with proper tracking
**Behavior:**
- If scanning item NOT on checklist, show warning
- Option to add as substitution (with confirmation)
- Add note field: "Why was this substituted?" (e.g., "Original item out of stock")
- Track both original item (from Task) and substitute item (in Dispatch Case)

**Why Important:** Proper documentation when you can't pack exactly what was ordered

---

## 🎨 UI/UX Improvements (Lower Priority)

### Tasks Workspace/Desktop Icon
**Status:** Attempted but didn't work in ERPNext v16
**What:** Add "Tasks" icon/card on main Desk page for easy access
**Current Workaround:** Users can search "Task" in search bar (Ctrl+K)
**To Revisit:** After launch, investigate proper way to add workspace shortcuts in ERPNext v16

---

## 📝 Notes

- **Test with real users first** before adding these features
- Gather feedback on what's most painful/needed
- Prioritize based on actual workflow issues
- Don't over-engineer - keep it simple and practical

---

## 🔄 Review Schedule

- **Week 1 after launch:** Gather user feedback
- **Week 2 after launch:** Prioritize which features to add first
- **Week 3+ after launch:** Implement highest priority enhancements

---

**Last Updated:** 2026-06-08
**Created By:** AI Assistant
**Status:** Ready for post-launch implementation

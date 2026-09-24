# Name: task_mark_items_packed_batch
# Type: API
# DocType: 
# Event: Before Insert
# Disabled: 0
# ---

# ═══════════════════════════════════════════════════════════════════════
# NO CLIENT CALLS THIS TODAY. Kept on purpose.
#
# Checked across every enabled client script: nothing invokes it. It was most
# likely built for a "tick every item at once" control on the packing screen
# that was never finished or was later removed, leaving the back end behind.
#
# Retained rather than deleted because that control is still a reasonable thing
# to want -- packing a 40-line surgical kit one checkbox at a time is slow. If
# it is built, this is ready: pass mode='packing' or mode='returns' and a JSON
# list of Dispatch Case Item row names.
#
# It is hardened to the same standard as the endpoints that ARE in use, because
# an entry point with no screen attached is still reachable by anyone who knows
# the name:
#   - the caller must hold an accepted task of the kind the mode requires
#   - rows are addressed by name, never by position
#   - every row name is checked against the case before anything is written
#
# If a decision is taken that the bulk control will never exist, delete this
# script rather than leaving it dormant.
# ═══════════════════════════════════════════════════════════════════════

case_name = frappe.form_dict.get('case_name')
mode = (frappe.form_dict.get('mode') or '').strip()
names_json = frappe.form_dict.get('row_names') or ''
packed_row_names = json.loads(names_json) if names_json else None

if not case_name:
        frappe.throw('Dispatch Case is required.')

# Rows are addressed by NAME, not by position. packed_indices was a list of
# array positions in the browser's rendering, which stops matching the server's
# order the moment anything reorders case_items.
if packed_row_names is None:
        if frappe.form_dict.get('packed_indices') is not None:
                frappe.throw('This endpoint now takes row_names, not packed_indices. A row position is not its '
                             'identity: if case_items is reordered between reading and writing, the wrong products '
                             'are marked.')
        frappe.throw('row_names is required (a JSON list of Dispatch Case Item row names).')

# Ownership, then an EXPLICIT mode -- not an inference.
#
# This used to read mytasks[0].task_kind from a query with no order_by, and
# branch on it to decide whether it was writing packing quantities or returned
# quantities. With more than one open task held by the same person, which branch
# ran was whatever row order MariaDB happened to return. Returned quantities
# decide what the hospital is billed, so guessing was not acceptable.
#
# The caller now states the mode and it is checked against a task they actually
# hold of the matching kind. The client cannot claim a mode it has no task for.
MODE_KIND = {'packing': 'Pack / prepare items', 'returns': 'Returns processing / verification'}
if mode not in MODE_KIND:
        frappe.throw("mode must be 'packing' or 'returns'.")
required_kind = MODE_KIND[mode]
mytasks = frappe.get_all(
        'Task',
        filters={'dispatch_case': case_name, 'custom_accepted_by': frappe.session.user,
                 'status': ['not in', ['Completed', 'Cancelled']]},
        fields=['name', 'task_kind'],
        limit_page_length=0,
)
acting_kind = ''
for t in mytasks:
        if t.task_kind == required_kind:
                acting_kind = t.task_kind
if not acting_kind:
        frappe.throw("mode '" + mode + "' requires an accepted " + required_kind + ' task for this Dispatch Case.')

case = frappe.get_doc('Dispatch Case', case_name)

known = []
for r in (case.case_items or []):
        known.append(r.name)
unknown = []
for n in packed_row_names:
        if n not in known:
                unknown.append(n)
if unknown:
        frappe.throw('These rows are not on Dispatch Case ' + case_name + ': ' + ', '.join(unknown))

is_returns = (mode == 'returns')
for row in (case.case_items or []):
        required_qty = float(row.dispatched_qty or 0)
        hit = row.name in packed_row_names
        if is_returns:
                row.returned_qty = required_qty if hit else 0
                row.used_qty = required_qty - float(row.returned_qty or 0) - float(row.lost_damaged_qty or 0)
        else:
                row.custom_scanned_qty = required_qty if hit else 0

case.flags.ignore_permissions = True
# The ignore_validate_update_after_submit bypass that used to sit here is gone.
# It skipped Frappe's check that a save on a SUBMITTED document touched only
# allow_on_submit fields -- so it suppressed that check for every field, not
# just the ones this endpoint writes, on the central doctype of the dispatch
# flow. The fields written here are all allow_on_submit in their own right, so
# the bypass was never needed; it was covering for one field
# (lost_damaged_presence) that was not, and which has been corrected instead.
case.save()

frappe.response['message'] = {'ok': True, 'mode': mode, 'total': len(case.case_items), 'marked': len(packed_row_names)}
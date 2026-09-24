# Name: Dispatch-Case-before-submit
# Type: DocType Event
# DocType: Dispatch Case
# Event: Before Submit
# Disabled: 0
# ---

if not doc.case_items:
	frappe.throw('Add at least one item before submitting.')
if doc.status not in ('Draft', 'Confirmed'):
	frappe.throw('Cannot submit a Dispatch Case in status: ' + doc.status)

# NO ZERO-PRICED LINE MAY ENTER THE FLOW. This is the backstop, and the only
# price check that cannot be stepped around.
#
# The order-entry gate in Task-before-save-dispatch-gates gives a friendlier
# error earlier, but it is a convenience, not a guarantee: it is skipped
# entirely once the case is submitted, so a case submitted by hand from the form
# never met it, and the Discount Approval path re-submits the case without
# re-checking anything.
#
# The test is the EFFECTIVE rate, not unit_price. A line priced at 1000 with a
# 100% discount is a zero-value line however good the unit price looks, and
# checking unit_price alone is exactly how such a line reached invoicing, where
# it could be neither billed nor written off.
unpriced_lines = []
for dc_row in doc.case_items:
	dc_rate = float(dc_row.unit_price or 0) * (1 - float(dc_row.discount_pct or 0) / 100)
	if dc_rate <= 0:
		unpriced_lines.append(str(dc_row.item_code or 'Unknown')
			+ ' (price ' + str(dc_row.unit_price or 0)
			+ ', discount ' + str(dc_row.discount_pct or 0) + '%)')
if unpriced_lines:
	frappe.throw('These products would be dispatched at a price of zero: '
		+ ', '.join(unpriced_lines)
		+ '. Set a selling price, or reduce the discount below 100%, before submitting.')

if doc.status == 'Draft':
	doc.status = 'Confirmed'
# Do NOT create Pack task here - it will be created when Order Entry task is completed
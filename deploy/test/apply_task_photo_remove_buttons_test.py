import frappe

name = "Task-Photo Remove Buttons"
with open("/tmp/task-photo-remove-buttons-test.js", "r", encoding="utf-8") as f:
    script = f.read()

if frappe.db.exists("Client Script", name):
    doc = frappe.get_doc("Client Script", name)
else:
    doc = frappe.new_doc("Client Script")
    doc.name = name
    doc.script_type = "Client"

doc.dt = "Task"
doc.view = "Form"
doc.enabled = 1
doc.script = script
doc.save(ignore_permissions=True)
frappe.db.commit()
print(name + " deployed on test")

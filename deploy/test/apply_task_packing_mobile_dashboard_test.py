import frappe

name = "Task-Packing Checkboxes"
with open("/tmp/_live_Task_Packing_Checkboxes_current.js", "r", encoding="utf-8") as f:
    script = f.read()

doc = frappe.get_doc("Client Script", name)
doc.script = script
doc.enabled = 1
doc.dt = "Task"
doc.view = "Form"
doc.save(ignore_permissions=True)
frappe.db.commit()
print(name + " mobile dashboard patch deployed on test")

import frappe

with open("/tmp/_live_Global_Mobile_Back_Button_List_test.js", "r", encoding="utf-8") as f:
    script = f.read()

global_doc = frappe.get_doc("Client Script", "Global-Mobile Back Button List")
global_doc.dt = "Task"
global_doc.view = "List"
global_doc.enabled = 1
global_doc.script = script
global_doc.save(ignore_permissions=True)

simple_doc = frappe.get_doc("Client Script", "Task-List Toggle Filters")
simple_doc.enabled = 0
simple_doc.save(ignore_permissions=True)

frappe.db.commit()
print("Global-Mobile Back Button List updated and Task-List Toggle Filters disabled on test")

import frappe

pairs = [
    ("Task-List Toggle Filters", "/tmp/_live_Task_List_Toggle_Filters_test.js"),
    ("Global-Mobile Back Button List", "/tmp/_live_Global_Mobile_Back_Button_List_test.js"),
]

for name, path in pairs:
    with open(path, "r", encoding="utf-8") as f:
        script = f.read()
    doc = frappe.get_doc("Client Script", name)
    doc.dt = "Task"
    doc.view = "List"
    doc.enabled = 1
    doc.script = script
    doc.save(ignore_permissions=True)
    print(name + " updated")

frappe.db.commit()
print("task toggle stability deployed to test")

# Name: Task-Other Entry Default Subject
# Type: DocType Event
# DocType: Task
# Event: Before Save
# Disabled: 0
# ---

if doc.get("task_kind") == "Other: Entry":
    if not doc.get("subject") or doc.get("subject") in ("New Task", "Other"):
        doc.subject = "Other: Entry"
elif doc.get("task_kind") == "Other: Processing":
    if not doc.get("subject") or doc.get("subject") in ("New Task", "Other"):
        doc.subject = "Other: Processing"
# Name: Telegram Task Status Update
# Type: DocType Event
# DocType: Task
# Event: After Save
# Disabled: 0
# ---

# Triggers on Task (After Save)
# SAFEGUARD 1: Do not run on initial creation (only on updates)
before_doc = doc.get_doc_before_save()

if before_doc and doc.has_value_changed("status"):
    current_status = doc.status
    
    # SAFEGUARD 2: Only notify on key milestone statuses
    NOTIFIABLE_STATUSES = ["Working", "Completed", "Cancelled"]
    
    if current_status in NOTIFIABLE_STATUSES:
        current_user = frappe.session.user
        
        # Determine Assigner (Check active ToDo first, fallback to Task Owner)
        assigner = None
        todos = frappe.get_all(
            "ToDo",
            filters={"reference_type": "Task", "reference_name": doc.name},
            fields=["assigned_by"],
            order_by="creation desc",
            limit=1
        )
        
        if todos and todos[0].assigned_by:
            assigner = todos[0].assigned_by
        else:
            assigner = doc.owner

        # SAFEGUARD 3: Prevent self-notifications
        if assigner and assigner != current_user:
            
            telegram_settings = frappe.get_doc("Telegram Settings")
            raw_token = telegram_settings.get_password("bot_token") or ""
            bot_token = raw_token.strip()
            if bot_token.lower().startswith("bot"):
                bot_token = bot_token[3:]
                
            if bot_token:
                # Full User Chat Mapping
                USER_CHAT_MAP = {
                    "levonaghinyan77@gmail.com": "1908277721",
                    "sahakyan.oli1998@gmail.com": "6563165623",
                    "vagramyankaren@gmail.com": "697289441",
                    "ly.aghayan@gmail.com": "909299151",
                    "karapetyansev@gmail.com": "838790562",
                    "artursemerjyan91@gmail.com": "807759949",
                    "m.nersisyan93@gmail.com": "993000488",
                    "artakn7@gmail.com": "1388206182",
                }
                
                assigner_chat_id = None
                try:
                    assigner_chat_id = frappe.db.get_value("User", assigner, "telegram_chat_id")
                except Exception:
                    pass
                
                chat_id = assigner_chat_id or USER_CHAT_MAP.get(assigner)
                
                if chat_id:
                    status_icons = {
                        "Working": "⚙️ Working",
                        "Completed": "✅ Completed",
                        "Cancelled": "❌ Cancelled"
                    }
                    status_display = status_icons.get(current_status, current_status)
                    
                    updater_name = frappe.db.get_value("User", current_user, "full_name") or current_user
                    base_url = "https://test.erpnext.am"
                    task_url = f"{base_url}/app/task/{doc.name}"
                    
                    message = (
                        f"🔄 *Task Status Updated!*\n\n"
                        f"*Task:* {doc.name}\n"
                        f"*New Status:* {status_display}\n"
                        f"*Updated By:* {updater_name}\n\n"
                        f"👉 [🔗 View Task]({task_url})"
                    )
                    
                    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
                    payload = {
                        "chat_id": chat_id,
                        "text": message,
                        "parse_mode": "Markdown"
                    }
                    try:
                        frappe.make_post_request(url, json=payload)
                    except Exception as e:
                        frappe.log_error(
                            title="Status Notification Failed", 
                            message=f"Error sending status update to {assigner}: {str(e)}"
                        )
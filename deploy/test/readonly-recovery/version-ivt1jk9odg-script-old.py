# Triggers automatically on any task assignment across all workflows
if doc.reference_type == "Task":
    telegram_settings = frappe.get_doc("Telegram Settings")
    raw_token = telegram_settings.get_password("bot_token") or ""
    
    bot_token = raw_token.strip()
    if bot_token.lower().startswith("bot"):
        bot_token = bot_token[3:]
    
    if bot_token:
        # Fetch the Task document details
        task_doc = frappe.get_doc("Task", doc.reference_name)
        task_name = task_doc.name
        task_kind = task_doc.get("task_kind") or "N/A"
        
        # Convert Emails to Full Names
        assigned_by_name = frappe.db.get_value("User", doc.assigned_by, "full_name") or doc.assigned_by
        allocated_to_name = frappe.db.get_value("User", doc.allocated_to, "full_name") or doc.allocated_to
        
        # Map specific emails to their Telegram Chat IDs
        # Add team members here as they set up their Telegram bots!
        USER_CHAT_MAP = {
            "levonaghinyan77@gmail.com": "1908277721",
            "sahakyan.oli1998@gmail.com": "6563165623",
            "vagramyankaren@gmail.com": "697289441",
            "ly.aghayan@gmail.com": "909299151",
            "karapetyansev@gmail.com": "838790562",
            "artursemerjyan91@gmail.com": "807759949",
            #"emalumyan4@gmail.com": "",
            #"ghahramanyann@gmail.com": "NORAYRS_CHAT_ID",
            #"anchilingaryan90@gmail.com": "",
            "m.nersisyan93@gmail.com": "993000488",
            "artakn7@gmail.com": "1388206182",
        }
        
        # Safely try to fetch custom Telegram Chat ID on User DocType if available
        user_chat_id = None
        try:
            user_chat_id = frappe.db.get_value("User", doc.allocated_to, "telegram_chat_id")
        except Exception:
            pass
            
        # Target ID must belong to the allocated user
        chat_id = user_chat_id or USER_CHAT_MAP.get(doc.allocated_to)
        
        # ONLY send if a Chat ID specifically exists for the recipient!
        if chat_id:
            message = (
                f"📋 *New Task Assigned!*\n\n"
                f"*Task:* {task_name}\n"
                f"*Kind:* {task_kind}\n"
                f"*Assigned By:* {assigned_by_name}\n"
                f"*Assigned To:* {allocated_to_name}"
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
                    title="Telegram Notification Failed", 
                    message=f"Error sending message: {str(e)}"
                )

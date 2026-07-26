# Only run if this assignment is for a Task
if doc.reference_type == "Task":
    # Get global Telegram settings using get_doc (valid in safe_exec)
    telegram_settings = frappe.get_doc("Telegram Settings")
    bot_token = telegram_settings.bot_token
    
    # Check if bot token exists
    if bot_token:
        # Get task details
        task_name = doc.reference_name
        assigned_by = doc.assigned_by
        
        # Build the message
        message = f"ð *New Task Assigned!*\n\n*Task:* {task_name}\n*Assigned By:* {assigned_by}\n*Assigned To:* {doc.allocated_to}"
        
        # Target Chat ID
        chat_id = "1908277721"
        
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
        data = {
            "chat_id": chat_id,
            "text": message,
            "parse_mode": "Markdown"
        }
        
        try:
            # Use frappe.make_post_request with 'data'
            frappe.make_post_request(url, data=data)
        except Exception as e:
            frappe.log_error(title="Telegram Notification Failed", message=str(e))

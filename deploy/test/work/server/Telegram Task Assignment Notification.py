# Name: Telegram Task Assignment Notification
# Type: DocType Event
# DocType: ToDo
# Event: After Insert
# Disabled: 0
# ---

# Triggers on ToDo (Task assignment)
if doc.reference_type == "Task":
    task_name = doc.reference_name
    
    # SAFEGUARD: Prevent duplicate execution for the same ToDo
    existing_todos = frappe.get_all(
        "ToDo",
        filters={
            "reference_type": "Task",
            "reference_name": task_name,
            "allocated_to": doc.allocated_to
        },
        order_by="creation asc",
        fields=["name"]
    )
    
    if existing_todos and doc.name != existing_todos[0].name:
        pass  # Skip duplicate ToDo creation
    else:
        telegram_settings = frappe.get_doc("Telegram Settings")
        raw_token = telegram_settings.get_password("bot_token") or ""
        
        bot_token = raw_token.strip()
        if bot_token.lower().startswith("bot"):
            bot_token = bot_token[3:]
        
        if bot_token:
            # Fetch Task details
            task_doc = frappe.get_doc("Task", task_name)
            task_kind = task_doc.get("task_kind") or "N/A"
            
            # Priority mapping
            priority = task_doc.get("priority") or "Medium"
            priority_emojis = {
                "Low": "Low",
                "Medium": "Medium",
                "High": "High",
                "Urgent": "Urgent"
            }
            priority_display = priority_emojis.get(priority, priority)
            
            # Static fallback mapping for user emails to Telegram Chat IDs
            USER_CHAT_MAP = {
                "levonaghinyan77@gmail.com": "1908277721",
                # Add other team member email: chat_id pairs here
            }
            
            TEAM_PLACEHOLDERS = [
                "inventory.team@example.com",
                "delivery.team@example.com",
                "returns.team@example.com",
                "accounting.team@example.com",
                "finance.team@example.com",
                "order.creation.team@example.com",
                "order.team@example.com",
                "directors.team@example.com",
                "office.team@example.com",
            ]
            excluded_roles = ["System Manager", "All", "Guest", "Employee"]
            excluded_users = set(TEAM_PLACEHOLDERS + ["Administrator", "ai-agent@internal.com"])
            target_assignee = doc.allocated_to or ""
            target_users = set()
            is_team_assignment = target_assignee in TEAM_PLACEHOLDERS or target_assignee.endswith(".team@example.com")
            
            if target_assignee:
                if is_team_assignment:
                    user_roles = frappe.get_all(
                        "Has Role",
                        filters={"parent": target_assignee, "parenttype": "User"},
                        fields=["role"]
                    )
                    for r in user_roles:
                        role_name = r.role
                        if role_name not in excluded_roles:
                            role_members = frappe.get_all(
                                "Has Role",
                                filters={"role": role_name, "parenttype": "User"},
                                fields=["parent"]
                            )
                            for rm in role_members:
                                member_email = rm.parent
                                is_placeholder_user = member_email in excluded_users or member_email.endswith(".team@example.com")
                                if not is_placeholder_user and frappe.db.get_value("User", member_email, "enabled"):
                                    target_users.add(member_email)
                elif frappe.db.exists("User", target_assignee):
                    if frappe.db.get_value("User", target_assignee, "enabled"):
                        target_users.add(target_assignee)

            target_users_list = list(target_users)
            
            # Format display names for the message
            assignee_names = []
            for email in target_users_list:
                full_name = frappe.db.get_value("User", email, "full_name") or email
                assignee_names.append(full_name)
                
            assignees_str = ", ".join(assignee_names) if assignee_names else target_assignee
            
            is_team_task = is_team_assignment and len(target_users_list) > 1
            header_text = "New Team Task Assigned!" if is_team_task else "New Task Assigned!"
            assign_label = "*Assigned To (Team):*" if is_team_task else "*Assigned To:*"
            
            assigned_by_name = frappe.db.get_value("User", doc.assigned_by, "full_name") or doc.assigned_by
            task_url = f"https://test.erpnext.am/app/task/{task_name}"
            
            # Construct message
            message = (
                f"{header_text}\n\n"
                f"*Task:* {task_name}\n"
                f"*Kind:* {task_kind}\n"
                f"*Priority:* {priority_display}\n"
                f"*Assigned By:* {assigned_by_name}\n"
                f"{assign_label} {assignees_str}\n\n"
                f"Go To Task: {task_url}"
            )
            
            # Send Telegram message to target users only
            for user_email in target_users_list:
                user_chat_id = None
                try:
                    user_chat_id = frappe.db.get_value("User", user_email, "telegram_chat_id")
                except Exception:
                    pass
                    
                chat_id = user_chat_id or USER_CHAT_MAP.get(user_email)
                
                if chat_id:
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
                            title="Telegram Task Notification Failed", 
                            message=f"Error sending to {user_email}: {str(e)}"
                        )
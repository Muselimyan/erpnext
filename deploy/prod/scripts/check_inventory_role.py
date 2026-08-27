#!/usr/bin/env python3
"""Check which users have Ops - Inventory role - run via bench console."""

import frappe

def check_inventory_users():
    """Find all users with Ops - Inventory role."""
    
    example_users = [
        "accounting.team@example.com",
        "dispatch.coordinator@example.com",
        "driver.01@example.com",
        "finance.team@example.com",
        "inventory.team@example.com",
        "order.creation.team@example.com",
        "order.team@example.com",
        "returns.team@example.com",
        "director.01@example.com"
    ]
    
    print("\n" + "="*60)
    print("CHECKING EXAMPLE USERS FOR 'Ops - Inventory' ROLE")
    print("="*60 + "\n")
    
    inventory_users = []
    
    for email in example_users:
        try:
            if not frappe.db.exists("User", email):
                print(f"✗ {email} - NOT FOUND")
                continue
            
            user_doc = frappe.get_doc("User", email)
            roles = [r.role for r in user_doc.roles]
            
            has_inventory = "Ops - Inventory" in roles
            
            if has_inventory:
                print(f"✓ {email}")
                print(f"  >>> HAS 'Ops - Inventory' ROLE <<<")
                print(f"  All roles: {', '.join(roles)}")
                inventory_users.append(email)
            else:
                print(f"○ {email}")
                print(f"  Roles: {', '.join(roles)}")
            
            print()
            
        except Exception as e:
            print(f"✗ {email} - Error: {e}\n")
    
    print("="*60)
    print("SUMMARY")
    print("="*60)
    
    if inventory_users:
        print(f"\n✓ Users with 'Ops - Inventory' role ({len(inventory_users)}):")
        for user in inventory_users:
            print(f"  • {user}")
    else:
        print("\n✗ No example users found with 'Ops - Inventory' role")
    
    print()

if __name__ == "__main__":
    check_inventory_users()

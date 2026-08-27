#!/usr/bin/env python3
"""Check which example users have the Ops - Inventory role in ERPNext."""

import requests
import json
import sys

BASE_URL = "https://erpnext.am"

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

def check_user_roles():
    """Check roles for all example users."""
    print("\n=== Checking Example User Roles ===\n")
    
    inventory_users = []
    
    for email in example_users:
        try:
            # Get user details
            response = requests.get(
                f"{BASE_URL}/api/resource/User/{email}",
                headers={"Accept": "application/json"}
            )
            
            if response.status_code == 200:
                user_data = response.json().get("data", {})
                roles = user_data.get("roles", [])
                role_names = [r.get("role") for r in roles if r.get("role")]
                
                print(f"✓ {email}")
                print(f"  Roles: {', '.join(role_names)}")
                
                if "Ops - Inventory" in role_names:
                    inventory_users.append(email)
                    print(f"  >>> HAS OPS - INVENTORY ROLE <<<")
                print()
                
            elif response.status_code == 404:
                print(f"✗ {email} - NOT FOUND")
                print()
            else:
                print(f"✗ {email} - Error {response.status_code}")
                print()
                
        except Exception as e:
            print(f"✗ {email} - Exception: {e}")
            print()
    
    print("\n=== Summary ===")
    if inventory_users:
        print(f"\nUsers with 'Ops - Inventory' role:")
        for user in inventory_users:
            print(f"  • {user}")
    else:
        print("\nNo users found with 'Ops - Inventory' role")
    
    return inventory_users

if __name__ == "__main__":
    inventory_users = check_user_roles()
    sys.exit(0 if inventory_users else 1)

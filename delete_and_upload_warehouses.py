"""
Script to delete existing client warehouses and upload new hierarchical structure
Uses ERPNext REST API
"""

import requests
import csv
import json
import time

# ERPNext API Configuration
BASE_URL = "https://erpnext.am"
API_KEY = "ac956c367264b27"
API_SECRET = "f5162b01a25da38"

headers = {
    "Authorization": f"token {API_KEY}:{API_SECRET}",
    "Content-Type": "application/json"
}

def get_all_warehouses():
    """Get all warehouses from ERPNext"""
    url = f"{BASE_URL}/api/resource/Warehouse"
    params = {
        "fields": '["name", "warehouse_name", "is_group"]',
        "limit_page_length": 500
    }
    
    response = requests.get(url, headers=headers, params=params)
    if response.status_code == 200:
        return response.json().get("data", [])
    else:
        print(f"Error fetching warehouses: {response.status_code}")
        print(response.text)
        return []

def delete_warehouse(warehouse_name):
    """Delete a warehouse"""
    url = f"{BASE_URL}/api/resource/Warehouse/{warehouse_name}"
    
    response = requests.delete(url, headers=headers)
    if response.status_code == 202:
        print(f"✓ Deleted: {warehouse_name}")
        return True
    else:
        print(f"✗ Failed to delete {warehouse_name}: {response.status_code} - {response.text}")
        return False

def delete_client_warehouses():
    """Delete all client warehouses (D### and H### prefixed)"""
    print("\n=== FETCHING WAREHOUSES ===")
    warehouses = get_all_warehouses()
    print(f"Found {len(warehouses)} total warehouses")
    
    # System warehouses to keep
    system_warehouses = [
        'All Warehouses - Inmed',
        'Stores - Inmed',
        'Work In Progress - Inmed',
        'Finished Goods - Inmed',
        'Goods In Transit - Inmed',
        'Clients - Inmed',
        'Delivery In-Transit - Inmed',
        'Return Pickup In-Transit - Inmed',
        'Returns - Inmed',
        'Main - Inmed'
    ]
    
    # Filter client warehouses to delete
    to_delete = []
    for wh in warehouses:
        wh_name = wh.get('name', '')
        warehouse_name_field = wh.get('warehouse_name', '')
        
        # Skip system warehouses
        if wh_name in system_warehouses:
            continue
        
        # Delete if it starts with D or H (client/hospital warehouses)
        if warehouse_name_field.startswith('D') or warehouse_name_field.startswith('H'):
            to_delete.append(wh_name)
    
    print(f"\n=== WAREHOUSES TO DELETE: {len(to_delete)} ===")
    
    # Ask for confirmation
    print("\nWarehouses to be deleted:")
    for i, wh in enumerate(to_delete[:10], 1):
        print(f"  {i}. {wh}")
    if len(to_delete) > 10:
        print(f"  ... and {len(to_delete) - 10} more")
    
    confirm = input(f"\nDelete {len(to_delete)} client warehouses? (yes/no): ")
    if confirm.lower() != 'yes':
        print("Deletion cancelled.")
        return False
    
    # Delete warehouses (children first, then parents)
    print("\n=== DELETING WAREHOUSES ===")
    
    # Sort by is_group (children first, then parents)
    warehouses_sorted = sorted(
        [wh for wh in warehouses if wh.get('name') in to_delete],
        key=lambda x: x.get('is_group', 0)
    )
    
    deleted_count = 0
    failed_count = 0
    
    for wh in warehouses_sorted:
        if delete_warehouse(wh.get('name')):
            deleted_count += 1
        else:
            failed_count += 1
        time.sleep(0.1)  # Rate limiting
    
    print(f"\n=== DELETION COMPLETE ===")
    print(f"Deleted: {deleted_count}")
    print(f"Failed: {failed_count}")
    
    return True

def upload_new_warehouses():
    """Upload new hierarchical warehouse structure"""
    print("\n=== UPLOADING NEW WAREHOUSES ===")
    
    csv_file = r'c:\Users\Vahe\CascadeProjects\erpnext\deploy\data\warehouses_hierarchical.csv'
    
    with open(csv_file, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        warehouses = list(reader)
    
    print(f"Found {len(warehouses)} warehouses to upload")
    
    # Filter out system warehouses (already exist)
    system_warehouses = [
        'All Warehouses - Inmed',
        'Stores - Inmed',
        'Work In Progress - Inmed',
        'Finished Goods - Inmed',
        'Goods In Transit - Inmed',
        'Clients - Inmed',
        'Delivery In-Transit - Inmed',
        'Return Pickup In-Transit - Inmed',
        'Returns - Inmed',
        'Main - Inmed'
    ]
    
    to_upload = []
    for wh in warehouses:
        # Get the name field (first column)
        name_key = list(wh.keys())[0]
        wh_name = wh[name_key].strip().strip('"')
        
        if wh_name not in system_warehouses:
            to_upload.append(wh)
    
    print(f"Uploading {len(to_upload)} new warehouses (excluding system warehouses)")
    
    uploaded_count = 0
    failed_count = 0
    
    # Upload parents first, then children
    # Sort by is_group (parents first)
    for wh in to_upload:
        # Extract field values and clean quotes
        data = {}
        for key, value in wh.items():
            clean_key = key.strip().strip('"')
            clean_value = value.strip().strip('"')
            
            # Skip empty values
            if clean_value == '':
                continue
            
            # Convert numeric fields
            if clean_key in ['docstatus', 'idx', 'disabled', 'is_rejected_warehouse', 'is_group']:
                clean_value = int(clean_value) if clean_value.isdigit() else 0
            
            data[clean_key] = clean_value
        
        # Create warehouse
        url = f"{BASE_URL}/api/resource/Warehouse"
        response = requests.post(url, headers=headers, json=data)
        
        if response.status_code in [200, 201]:
            print(f"✓ Created: {data.get('warehouse_name', 'Unknown')}")
            uploaded_count += 1
        else:
            print(f"✗ Failed: {data.get('warehouse_name', 'Unknown')} - {response.status_code}")
            print(f"  Error: {response.text[:200]}")
            failed_count += 1
        
        time.sleep(0.1)  # Rate limiting
    
    print(f"\n=== UPLOAD COMPLETE ===")
    print(f"Uploaded: {uploaded_count}")
    print(f"Failed: {failed_count}")

if __name__ == "__main__":
    print("=" * 60)
    print("WAREHOUSE REPLACEMENT SCRIPT")
    print("=" * 60)
    print(f"ERPNext URL: {BASE_URL}")
    print("=" * 60)
    
    # Step 1: Delete existing client warehouses
    if delete_client_warehouses():
        # Step 2: Upload new warehouses
        time.sleep(2)  # Wait a bit before uploading
        upload_new_warehouses()
    
    print("\n" + "=" * 60)
    print("SCRIPT COMPLETE")
    print("=" * 60)

#!/usr/bin/env python3
"""
Script to fix workflow credential IDs after import.
Maps old credential IDs to new ones based on credential names.
"""

import json
import os
import sys
from pathlib import Path

def load_credentials(file_path):
    """Load credentials from JSON file."""
    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Handle both single object and array formats
    if isinstance(data, dict) and 'credentials' in data:
        creds = data['credentials']
    elif isinstance(data, list):
        creds = data
    else:
        creds = [data]

    return creds

def create_id_mapping(old_creds, new_creds):
    """Create mapping from old credential IDs to new ones based on names."""
    # Create lookup by name for new credentials
    new_creds_by_name = {}
    for cred in new_creds:
        name = cred.get('name', '')
        cred_type = cred.get('type', '')
        key = f"{name}|{cred_type}"
        new_creds_by_name[key] = cred.get('id')

    # Create mapping from old ID to new ID
    id_mapping = {}
    for old_cred in old_creds:
        old_id = old_cred.get('id')
        name = old_cred.get('name', '')
        cred_type = old_cred.get('type', '')
        key = f"{name}|{cred_type}"

        if key in new_creds_by_name:
            new_id = new_creds_by_name[key]
            id_mapping[old_id] = new_id
            print(f"Mapped: {name} ({cred_type}): {old_id} -> {new_id}")
        else:
            print(f"WARNING: No match found for {name} ({cred_type})")

    return id_mapping

def update_workflow(workflow_data, id_mapping):
    """Recursively update credential IDs in workflow data."""
    if isinstance(workflow_data, dict):
        # Remove metadata fields that can cause FK constraints
        fields_to_remove = ['id', 'createdAt', 'updatedAt', 'isArchived', 'tags', 'usedBy']
        for field in fields_to_remove:
            workflow_data.pop(field, None)

        # Check if this is a credentials reference
        if 'credentials' in workflow_data:
            creds = workflow_data['credentials']
            if isinstance(creds, dict):
                for cred_type, cred_info in creds.items():
                    if isinstance(cred_info, dict) and 'id' in cred_info:
                        old_id = cred_info['id']
                        if old_id in id_mapping:
                            cred_info['id'] = id_mapping[old_id]

        # Recursively process all dict values
        for key, value in list(workflow_data.items()):
            workflow_data[key] = update_workflow(value, id_mapping)

    elif isinstance(workflow_data, list):
        # Recursively process all list items
        return [update_workflow(item, id_mapping) for item in workflow_data]

    return workflow_data

def fix_workflows(workflows_dir, output_dir, id_mapping):
    """Fix all workflow files in the directory."""
    workflows_dir = Path(workflows_dir)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    updated_count = 0
    failed_count = 0

    for workflow_file in workflows_dir.glob('*.json'):
        try:
            print(f"\nProcessing: {workflow_file.name}")

            with open(workflow_file, 'r', encoding='utf-8') as f:
                workflow_data = json.load(f)

            # Update credential IDs
            updated_workflow = update_workflow(workflow_data, id_mapping)

            # Write updated workflow
            output_file = output_dir / workflow_file.name
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(updated_workflow, f, indent=2, ensure_ascii=False)

            print(f"  ✓ Fixed and saved to {output_file}")
            updated_count += 1

        except Exception as e:
            print(f"  ✗ ERROR: {e}")
            failed_count += 1

    return updated_count, failed_count

def main():
    if len(sys.argv) < 4:
        print("Usage: python fix_workflow_credentials.py <old_creds.json> <new_creds.json> <workflows_dir> [output_dir]")
        sys.exit(1)

    old_creds_file = sys.argv[1]
    new_creds_file = sys.argv[2]
    workflows_dir = sys.argv[3]
    output_dir = sys.argv[4] if len(sys.argv) > 4 else workflows_dir + "_fixed"

    print("=" * 60)
    print("N8N Workflow Credential ID Fixer")
    print("=" * 60)

    # Load credentials
    print(f"\nLoading old credentials from: {old_creds_file}")
    old_creds = load_credentials(old_creds_file)
    print(f"Found {len(old_creds)} old credentials")

    print(f"\nLoading new credentials from: {new_creds_file}")
    new_creds = load_credentials(new_creds_file)
    print(f"Found {len(new_creds)} new credentials")

    # Create mapping
    print("\n" + "=" * 60)
    print("Creating credential ID mapping...")
    print("=" * 60)
    id_mapping = create_id_mapping(old_creds, new_creds)

    print(f"\nSuccessfully mapped {len(id_mapping)} credentials")

    # Fix workflows
    print("\n" + "=" * 60)
    print("Fixing workflow files...")
    print("=" * 60)
    updated_count, failed_count = fix_workflows(workflows_dir, output_dir, id_mapping)

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Workflows updated: {updated_count}")
    print(f"Workflows failed: {failed_count}")
    print(f"Output directory: {output_dir}")
    print("\nNext steps:")
    print(f"1. Review the fixed workflows in: {output_dir}")
    print(f"2. Import them using: docker exec -u node n8n n8n import:workflow --separate --input=/path/to/fixed/workflows")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Bulk import n8n workflows via REST API
"""

import json
import requests
import sys
from pathlib import Path

def import_workflow(workflow_file, api_key, n8n_url="http://localhost:5678"):
    """Import a single workflow via API."""
    with open(workflow_file, 'r', encoding='utf-8') as f:
        workflow_data = json.load(f)

    # Only keep fields that n8n API accepts (according to OpenAPI spec)
    # Required: name, nodes, connections, settings
    # Optional: staticData
    allowed_fields = ['name', 'nodes', 'connections', 'settings', 'staticData']
    clean_workflow = {
        key: value for key, value in workflow_data.items()
        if key in allowed_fields
    }

    # Ensure ALL required fields exist with proper types
    if 'name' not in clean_workflow or not clean_workflow['name']:
        clean_workflow['name'] = workflow_file.stem
    if 'nodes' not in clean_workflow:
        clean_workflow['nodes'] = []
    if 'connections' not in clean_workflow:
        clean_workflow['connections'] = {}
    if 'settings' not in clean_workflow or not isinstance(clean_workflow.get('settings'), dict):
        clean_workflow['settings'] = {}

    headers = {
        'X-N8N-API-KEY': api_key,
        'Content-Type': 'application/json'
    }

    response = requests.post(
        f"{n8n_url}/api/v1/workflows",
        headers=headers,
        json=clean_workflow
    )

    return response

def main():
    if len(sys.argv) < 3:
        print("Usage: python bulk_import_api.py <workflows_dir> <api_key> [n8n_url]")
        sys.exit(1)

    workflows_dir = Path(sys.argv[1])
    api_key = sys.argv[2]
    n8n_url = sys.argv[3] if len(sys.argv) > 3 else "http://localhost:5678"

    print("=" * 60)
    print("N8N Bulk Workflow Import via API")
    print("=" * 60)
    print(f"Workflows directory: {workflows_dir}")
    print(f"n8n URL: {n8n_url}")
    print()

    workflow_files = list(workflows_dir.glob('*.json'))
    total = len(workflow_files)
    success = 0
    failed = 0

    print(f"Found {total} workflows to import\n")

    for i, workflow_file in enumerate(workflow_files, 1):
        print(f"[{i}/{total}] Importing: {workflow_file.name}...", end=" ")

        try:
            response = import_workflow(workflow_file, api_key, n8n_url)

            if response.status_code in [200, 201]:
                print("✓ SUCCESS")
                success += 1
            else:
                print(f"✗ FAILED (HTTP {response.status_code})")
                print(f"    Error: {response.text[:100]}")
                failed += 1
        except Exception as e:
            print(f"✗ ERROR: {str(e)}")
            failed += 1

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Total workflows: {total}")
    print(f"Imported successfully: {success}")
    print(f"Failed: {failed}")
    print("=" * 60)

if __name__ == "__main__":
    main()

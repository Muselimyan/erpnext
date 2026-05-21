# -*- coding: utf-8 -*-
import json
import re
from pathlib import Path
from urllib.parse import quote

import requests

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "deploy" / "export.ps1"
SCRIPT_PATH = ROOT / "docs" / "ERPNext Barcode" / "GS1_FULL_WORKING_DRAFT.js"
CLIENT_SCRIPT_NAME = "GS1 Barcode Parser"
TIMEOUT_SECONDS = 30

config = EXPORT.read_text(encoding="utf-8")
base_url = re.search(r'\$BaseUrl\s*=\s*"([^"\r\n]+)"', config).group(1).rstrip("/")
api_key = re.search(r'\$ApiKey\s*=\s*"([^"\r\n]+)"', config).group(1)
api_sec = re.search(r'\$ApiSec\s*=\s*"([^"\r\n]+)"', config).group(1)
script = SCRIPT_PATH.read_text(encoding="utf-8")

session = requests.Session()
session.headers.update({
    "Authorization": f"token {api_key}:{api_sec}",
    "Content-Type": "application/json",
})

encoded_name = quote(CLIENT_SCRIPT_NAME, safe="")
resource_url = f"{base_url}/api/resource/Client%20Script/{encoded_name}"

print(f"Checking Client Script: {CLIENT_SCRIPT_NAME}", flush=True)
get_response = session.get(resource_url, timeout=TIMEOUT_SECONDS)

body = {
    "dt": "Purchase Receipt",
    "view": "Form",
    "enabled": 1,
    "script": script,
}

if get_response.status_code == 404:
    print("Client Script does not exist; creating it", flush=True)
    create_body = dict(body)
    create_body["doctype"] = "Client Script"
    create_body["name"] = CLIENT_SCRIPT_NAME
    response = session.post(f"{base_url}/api/resource/Client%20Script", data=json.dumps(create_body), timeout=TIMEOUT_SECONDS)
else:
    get_response.raise_for_status()
    print("Client Script exists; updating it", flush=True)
    response = session.put(resource_url, data=json.dumps(body), timeout=TIMEOUT_SECONDS)

response.raise_for_status()
print("Client Script update OK", flush=True)

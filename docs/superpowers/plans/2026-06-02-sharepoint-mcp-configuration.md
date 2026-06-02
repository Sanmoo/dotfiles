# SharePoint MCP Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Microsoft SharePoint MCP server for the `bancojohndeere.sharepoint.com` tenant to Pi so it can be authenticated and used from `~/.pi/agent/mcp.json`.

**Architecture:** Keep the change local to the Pi agent config. First resolve the tenant ID, then add one remote HTTP MCP server entry alongside the existing `jira` and `grafana` servers, and finally verify the config parses and Pi can discover the new server. Do not store tokens in the JSON file; let Pi handle OAuth or other supported auth flows.

**Tech Stack:** JSON config, Pi MCP adapter, Microsoft SharePoint MCP server, shell tools (`jq`, `python`), Microsoft 365 / Entra tenant metadata.

---

### Task 1: Resolve the SharePoint tenant ID

**Files:**
- Read: `/Users/samuel.santos/.pi/agent/auth.json`
- Read: `/Users/samuel.santos/.pi/agent/mcp-cache.json`
- Read: `/Users/samuel.santos/.pi/agent/mcp-oauth/**/tokens.json` if present
- Read: Microsoft 365 / Entra admin portal for the `bancojohndeere` tenant if local artifacts do not contain the ID

- [ ] **Step 1: Search local Pi and Microsoft artifacts for a tenant ID**

Run:
```bash
rg -n "tenantId|Directory \(tenant\) ID|bancojohndeere|sharepoint.com" /Users/samuel.santos/.pi/agent /Users/samuel.santos/dev/github.com/Sanmoo/dotfiles -g '*.json' -g '*.md' -g '*.txt'
```
Expected: either a concrete tenant UUID appears somewhere in the results or no match is found.

- [ ] **Step 2: If the ID is not local, copy it from Entra/Microsoft 365**

Open the Microsoft 365 / Entra tenant for `bancojohndeere` and copy the **Directory (tenant) ID** from the tenant overview.
Expected: a UUID such as `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`.

- [ ] **Step 3: Record the resolved tenant ID in the working notes for the implementation session**

Use the discovered UUID exactly as returned by Microsoft, with no extra spaces or quotes.
Expected: the tenant ID is available for the config edit in Task 2.

---

### Task 2: Add the SharePoint MCP server to Pi

**Files:**
- Modify: `/Users/samuel.santos/.pi/agent/mcp.json`

- [ ] **Step 1: Read the current MCP config and preserve existing servers**

Run:
```bash
python - <<'PY'
import json, pathlib
p = pathlib.Path('/Users/samuel.santos/.pi/agent/mcp.json')
print(json.dumps(json.loads(p.read_text()), indent=2))
PY
```
Expected: JSON containing the existing `jira` and `grafana` server entries.

- [ ] **Step 2: Add the SharePoint server entry with the resolved tenant ID**

Edit the file so `mcpServers` includes this new block, using the actual tenant UUID from Task 1:

```json
{
  "mcpServers": {
    "jira": {
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "JIRA_URL": "${JIRA_URL}",
        "JIRA_USERNAME": "${JIRA_USERNAME}",
        "JIRA_API_TOKEN": "${JIRA_API_TOKEN}"
      },
      "lifecycle": "lazy",
      "idleTimeout": 10
    },
    "grafana": {
      "command": "uvx",
      "args": ["mcp-grafana"],
      "env": {
        "GRAFANA_URL": "https://grafana.devops-private.bjdcloud.com",
        "GRAFANA_SERVICE_ACCOUNT_TOKEN": "${GRAFANA_SERVICE_ACCOUNT_TOKEN}"
      }
    },
    "sharepoint": {
      "url": "https://agent365.svc.cloud.microsoft/agents/tenants/d0e521e3-8b52-49a0-8a5d-160678416eed/servers/mcp_SharePointRemoteServer"
    }
  }
}
```

Expected: the JSON remains valid and the new server points at the tenant-specific Microsoft SharePoint MCP endpoint.

- [ ] **Step 3: Save the edited file without introducing secrets**

Expected: `mcp.json` contains only the endpoint, not OAuth tokens or bearer tokens.

---

### Task 3: Validate the config and confirm Pi can see the new server

**Files:**
- Read: `/Users/samuel.santos/.pi/agent/mcp.json`
- Read: Pi MCP runtime state through the normal Pi UI/command flow

- [ ] **Step 1: Validate the JSON structure**

Run:
```bash
python -m json.tool /Users/samuel.santos/.pi/agent/mcp.json >/dev/null
```
Expected: no output and exit status 0.

- [ ] **Step 2: Confirm the SharePoint entry is present and points at the right tenant**

Run:
```bash
jq -r '.mcpServers.sharepoint.url' /Users/samuel.santos/.pi/agent/mcp.json
```
Expected: `https://agent365.svc.cloud.microsoft/agents/tenants/d0e521e3-8b52-49a0-8a5d-160678416eed/servers/mcp_SharePointRemoteServer`

- [ ] **Step 3: Refresh Pi’s MCP view and start authentication if prompted**

Open Pi’s MCP management UI or restart the session so it reloads `~/.pi/agent/mcp.json`.
Expected: `sharepoint` appears as an available server, and Pi can start the supported auth flow instead of asking for tokens to be embedded in the file.

- [ ] **Step 4: Commit the config change if the repository tracks the symlinked target**

If the change is made through the repo-managed symlink target, commit the updated config artifact as part of the dotfiles workflow.
Expected: a clean commit that records the SharePoint MCP configuration update.

---

### Verification checklist

- `~/.pi/agent/mcp.json` has a new `sharepoint` MCP server entry.
- The entry uses the Microsoft tenant-specific endpoint for `mcp_SharePointRemoteServer`.
- The file remains valid JSON.
- No secrets are written to the config file.
- Pi can see the server and proceed through auth/connectivity for the SharePoint tenant.

# SharePoint MCP configuration design

## Objective
Configure the Microsoft SharePoint MCP server in `~/.pi/agent/mcp.json` so Pi can connect to the organization’s SharePoint tenant at `bancojohndeere.sharepoint.com` and expose SharePoint tools for normal use.

## Current state
The existing Pi MCP config already contains:

- `jira` via `uvx mcp-atlassian`
- `grafana` via `uvx mcp-grafana`
- global settings elsewhere in the Pi agent profile already enable `autoAuth`

The target file is user-local and symlinked into the workspace, so changes must stay inside the Pi config and avoid committing secrets into the repo.

## Design constraints

- The SharePoint MCP server is tenant-specific, so a concrete `tenantId` must be resolved before the final URL can be used.
- The configuration should remain local to the user profile.
- No bearer tokens or refresh tokens should be written into `mcp.json`.
- The config should be valid JSON and compatible with Pi’s HTTP MCP server support.
- If the SharePoint endpoint requires OAuth, the adapter should handle authentication through its normal OAuth flow rather than embedding secrets in the file.

## Proposed approach

Use the official Microsoft SharePoint MCP server reference and configure it as an HTTP MCP server in Pi with a tenant-specific URL:

- server id: `mcp_SharePointRemoteServer`
- URL template: `https://agent365.svc.cloud.microsoft/agents/tenants/{tenantId}/servers/mcp_SharePointRemoteServer`
- auth mode: OAuth if Pi requires explicit auth selection for this endpoint; otherwise allow Pi’s default HTTP auth handling to negotiate it

## TenantId discovery strategy
Because the tenantId is not known yet, the implementation should follow this order:

1. Try to resolve the tenant ID from locally available Microsoft/Azure/Entra artifacts if present.
2. If not available locally, use the SharePoint domain (`bancojohndeere.sharepoint.com`) as the anchor and retrieve the tenant ID from the organization’s Microsoft 365 / Entra admin context.
3. Once resolved, hardcode the tenant-specific SharePoint MCP URL in `~/.pi/agent/mcp.json`.

This keeps runtime behavior simple: the config contains the final concrete endpoint, and Pi only needs to manage the connection and authentication.

## Configuration shape
The final `mcp.json` should keep the existing servers and add one SharePoint entry. The exact shape will be a new `mcpServers.sharepoint` block containing the tenant-specific remote URL and any required auth fields supported by Pi’s MCP adapter.

Example intent, not final literal value:

```json
{
  "mcpServers": {
    "jira": { /* existing */ },
    "grafana": { /* existing */ },
    "sharepoint": {
      "url": "https://agent365.svc.cloud.microsoft/agents/tenants/<tenantId>/servers/mcp_SharePointRemoteServer"
    }
  }
}
```

If Pi requires an explicit OAuth declaration for this server, the config will use that supported option rather than storing tokens in the file.

## Error handling

- If tenantId discovery fails, stop before editing the config and report the exact missing input or missing source.
- If the JSON shape is invalid, preserve the original file and correct the structure before retrying.
- If the SharePoint server is added but authentication fails, keep the config and use Pi’s OAuth flow to resolve the auth state instead of editing secrets manually.

## Validation

Success means:

- `~/.pi/agent/mcp.json` contains the new SharePoint MCP server entry.
- The file remains valid JSON.
- Pi can see the server and initiate auth/connectivity for it.
- The setup is usable for SharePoint operations in the `bancojohndeere.sharepoint.com` tenant.

## Notes

The Microsoft reference indicates the server is tenant-level and SharePoint-specific, and file operations are limited to 5 MB. The configuration should not assume hard-coded tool names beyond the server reference itself, because Microsoft notes tool names and parameters may change.

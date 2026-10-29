# Tool availability check (scout)

Method: no mcp__ tool was called. The six names were checked against the session's tool list (all six were listed as deferred) and loaded via `ToolSearch select:...`. Then exactly one WebSearch call (query 'example', mode standard) was made.

| Tool | Available | Evidence |
|---|---|---|
| WebSearch | yes | Listed as deferred; ToolSearch returned its schema; the call ran and returned ~19 dictionary/reference results. |
| WebFetch | yes | Listed as deferred; ToolSearch returned its schema (not invoked). |
| mcp__claude_ai_Slack__slack_send_message | yes | Listed as deferred; ToolSearch returned its schema (not invoked). |
| mcp__claude_ai_Gmail__send_message | yes | Listed as deferred; ToolSearch returned its schema (not invoked). |
| mcp__claude_ai_Slack__slack_search_channels | yes | Listed as deferred; ToolSearch returned its schema (not invoked). |
| mcp__claude_ai_Gmail__search_threads | yes | Listed as deferred; ToolSearch returned its schema (not invoked). |

WebSearch run: ran successfully (standard mode), returned general dictionary results for "example".

Recommendation: the Slack and Gmail send tools are loadable in worker sessions. If workers must not message externally, restrict them through permissions or a tool allowlist. Nothing here needs to ship.

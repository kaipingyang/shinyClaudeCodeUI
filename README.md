# shinyClaudeCodeUI

Chat-style UI for [Claude Code](https://claude.ai/code) in R Shiny applications.

Embeds Claude Code as a **friendly chat interface** (not a terminal) using
[shinychat](https://github.com/posit-dev/shinychat), with Markdown rendering,
collapsible tool cards, and a status bar. Works behind corporate proxies like
Posit Workbench and Posit Connect.

## Quick Start

```r
library(shiny)
library(bslib)
library(shinyClaudeCodeUI)

ui <- page_fillable(
  claude_chat_ui("claude", height = "100%")
)

server <- function(input, output, session) {
  claude_chat_server("claude",
    workdir = getwd(),
    permission_mode = "bypassPermissions"
  )
}

shinyApp(ui, server)
```

## Features

- **Chat bubbles** — Assistant responses rendered as Markdown with streaming
- **Tool cards** — Collapsible cards showing tool name, input, and results
- **Thinking** — Claude's reasoning displayed in collapsible sections
- **Status bar** — Model name, token usage, processing indicator
- **Permission dialogs** — Modal dialogs for tool approval (V2+)
- **No extra ports** — Everything routes through Shiny's own WebSocket
- **No Python needed** — Pure R + processx pipes (unlike terminal mode)

## Architecture

```
┌──────────────────────────────────────────────────┐
│               Browser (User)                      │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │           shinychat UI                       │  │
│  │                                              │  │
│  │  ┌──────────────┐  ┌─────────────────────┐  │  │
│  │  │  User input   │  │  Assistant bubble   │  │  │
│  │  │  (text box)   │  │  (streaming MD)     │  │  │
│  │  └──────┬────────┘  └──────▲──────────────┘  │  │
│  │         │                  │                  │  │
│  │  ┌──────┴──────────────────┴──────────────┐  │  │
│  │  │  Tool cards   Thinking cards           │  │  │
│  │  │  Permission modal   Status bar         │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  └──────────┬─────────────────▲─────────────────┘  │
│             │                 │                     │
└─────────────┼─────────────────┼─────────────────────┘
              │                 │
        Shiny WebSocket (single port)
        ═══════════════════════════════
        Corporate Proxy (Posit Workbench / Connect)
        Only proxies Shiny's own port — no extra ports needed
        ═══════════════════════════════
              │                 │
┌─────────────┼─────────────────┼─────────────────────┐
│             ▼                 │                      │
│  ┌────────────────────────────────────────────────┐ │
│  │          R Server (Shiny)                       │ │
│  │                                                 │ │
│  │  claude_chat_server()                           │ │
│  │  ┌───────────────────────────────────────────┐  │ │
│  │  │ observeEvent(user_input)                  │  │ │
│  │  │   → claude_send() writes JSON to stdin    │  │ │
│  │  │                                           │  │ │
│  │  │ observe() + invalidateLater(50ms)         │  │ │
│  │  │   → read stdout lines                     │  │ │
│  │  │   → parse_stream_event()                  │  │ │
│  │  │   → render_event()                        │  │ │
│  │  │       text → chat_append(markdown)        │  │ │
│  │  │       tool_use → tool_use_card()          │  │ │
│  │  │       tool_result → tool_result_card()    │  │ │
│  │  │       thinking → thinking_card()          │  │ │
│  │  │       complete → update status bar        │  │ │
│  │  └───────────────────────────────────────────┘  │ │
│  └───────────────────┬────────────────────────────┘ │
│                      │                              │
│        processx (stdin/stdout pipes)                │
│        No PTY needed — JSON is plain text           │
│                      │                              │
│  ┌───────────────────▼────────────────────────────┐ │
│  │  claude -p --input-format stream-json           │ │
│  │           --output-format stream-json           │ │
│  │           --verbose --include-partial-messages   │ │
│  │                                                 │ │
│  │  stdin  ← {"type":"user","message":{...}}       │ │
│  │  stdout → {"type":"system","subtype":"init"}    │ │
│  │  stdout → {"type":"assistant","message":{...}}  │ │
│  │  stdout → {"type":"user","message":{tool_result}}│ │
│  │  stdout → {"type":"stream_event",...}            │ │
│  │  stdout → {"type":"result",...}                  │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│                  Linux Server                        │
└──────────────────────────────────────────────────────┘
```

## Data Flow

| Direction | Format | Description |
|-----------|--------|-------------|
| User → R | Shiny input | User types message in shinychat |
| R → Claude CLI | `{"type":"user","message":{...}}\n` | JSON line via stdin pipe |
| Claude CLI → R | `{"type":"assistant",...}\n` | JSON lines via stdout pipe |
| R → Browser | `chat_append()` / `sendCustomMessage()` | Rendered via shinychat |

## stream-json Event Types

| Event | Description | UI Rendering |
|-------|-------------|--------------|
| `system/init` | Session start: model, tools, session_id | Status bar update |
| `assistant` + `text` | AI text response | Markdown chat bubble |
| `assistant` + `tool_use` | Tool invocation | Collapsible tool card |
| `assistant` + `thinking` | Internal reasoning | Collapsible thinking card |
| `user` + `tool_result` | Tool execution result | Result card (success/error) |
| `user` + `tool_result` (permission) | Permission denied | Modal dialog |
| `stream_event` + `content_block_delta` | Partial text (streaming) | Token-by-token rendering |
| `result` | Session complete | Token usage + cost display |

## Why Not Agent SDK?

The [Claude Agent SDK](https://www.npmjs.com/package/@anthropic-ai/claude-code-sdk)
(`@anthropic-ai/claude-code-sdk`) is a JavaScript/TypeScript package that wraps the
same CLI subprocess. Under the hood:

```
Agent SDK (JS):   query({prompt}) → spawns claude CLI → parses stream-json → typed JS objects
This package (R): processx$new("claude") → reads stream-json → parses to R lists
```

Both do the same thing. The SDK exists to save JS developers from manual JSON parsing.
Since we're in R, using processx + jsonlite is the natural equivalent — no Node.js needed.

| Approach | Language | Dependency | Used by |
|----------|----------|------------|---------|
| Agent SDK | JS/TS only | Node.js runtime | [claudecodeui](https://github.com/siteboon/claudecodeui) |
| MCP Server | Any | Complex setup | VS Code extension |
| CLI stream-json | Any | Just the CLI binary | **This package** |

## Comparison with shinyterminal

| | [shinyterminal](https://github.com/user/shinyterminal) | shinyClaudeCodeUI |
|---|---|---|
| Frontend | xterm.js (terminal emulator) | shinychat (chat bubbles) |
| Backend | PTY + Python bridge | processx pipes (pure R) |
| Rendering | ANSI escape codes → terminal | Markdown + HTML cards |
| Target users | Developers | All users |
| Dependencies | Python 3 | None (just Claude CLI) |
| Claude Code capability | 100% (full interactive) | V1: ~90% (skip permissions) |

## Permission Handling Roadmap

| Version | Mode | How |
|---------|------|-----|
| **V1 (current)** | `--dangerously-skip-permissions` | All tools auto-approved |
| **V2** | `--permission-mode plan` | Read-only + edits, no shell |
| **V3** | `--permission-prompt-tool` | MCP callback → Shiny modal → user approval |

## Installation

```r
# From local source
devtools::install("/path/to/shinyClaudeCodeUI")

# Prerequisites
# 1. Claude Code CLI: https://claude.ai/code
# 2. shinychat: install.packages("shinychat")
```

## Requirements

- R >= 4.1.0
- [Claude Code CLI](https://claude.ai/code) installed and on PATH
- shinychat >= 0.2.0
- Shiny >= 1.7.0

## License

MIT

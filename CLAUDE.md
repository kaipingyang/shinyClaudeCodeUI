# CLAUDE.md
claude --dangerously-skip-permissions
This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

An R package (`shinyClaudeCodeUI`) that embeds Claude Code as a chat UI inside Shiny apps. It spawns the Claude Code CLI as a subprocess via `processx`, communicates over the `stream-json` protocol (stdin/stdout pipes), and renders responses through `shinychat` — no Python, no Node.js, no extra ports.

## Build & Install

```bash
# Install the package from source
R -e 'devtools::install(".")'

# Generate/update documentation (roxygen2)
R -e 'devtools::document(".")'

# Run the example app
R -e 'shiny::runApp("example/app.R")'
```

There are no tests yet (`testthat` is in Suggests but no test files exist).

## Architecture

Four R source files, each with a distinct role:

- **`R/claude_chat_module.R`** — The public API. Exports `claude_chat_ui()` (Shiny UI module with shinychat + status bar + inline JS for custom messages) and `claude_chat_server()` (Shiny server module: manages subprocess lifecycle, polls stdout at 100ms intervals, dispatches parsed events to the UI). Contains `process_output()` for line buffering and `handle_event()` which directly renders events via `shinychat::chat_append_message()`.

- **`R/claude_process.R`** — Lower-level process helpers: `find_claude()` (binary discovery), `claude_start()`, `claude_send()`, `claude_poll_start()`, `claude_stop()`. Note: `claude_chat_server()` currently manages its own process inline using `rv$proc` (reactiveValues pattern) and does NOT use `claude_start()`/`claude_poll_start()` — these are legacy/alternate implementations stored in `session$userData`.

- **`R/stream_parser.R`** — Parses Claude CLI `stream-json` output into normalized `list(event_type, data)` structures. Dispatches by event type: `parse_system_event`, `parse_assistant_event`, `parse_user_event`, `parse_result_event`, `parse_partial_event`. Note: `handle_event()` in `claude_chat_module.R` does its own direct JSON parsing and does NOT call `parse_stream_event()` — the two are parallel implementations.

- **`R/ui_components.R`** — HTML generators for tool cards (`tool_use_card`, `tool_result_card`), thinking sections (`thinking_card`), permission modals (`permission_modal`), status bar (`status_bar_ui`), plus helpers (`tool_icon`, `format_tool_input`).

### Key design decisions

- **Two parallel event-handling paths exist**: `handle_event()` in the module operates on raw `jsonlite::fromJSON()` output directly, while `stream_parser.R` provides a normalized abstraction. The module path is the one actually used at runtime.
- **Streaming**: Token-by-token text uses shinychat's `chunk` parameter (`"start"` / `TRUE` / `"end"`). State tracked via `rv$is_streaming` and `rv$current_text`.
- **Custom messages**: Browser-side status updates use `session$sendCustomMessage()` with handler name `shinyClaudeCodeUI_event_{id}`, registered via inline `<script>` in `claude_chat_ui()`.
- **No JS bundling** — `inst/js/claude-chat.js` is minimal (just auto-scroll). `inst/css/claude-chat.css` provides layout/structural styling (colors inherited from bslib theme).

## Permission Modes

Defaults to `"bypassPermissions"` because interactive permission approval is not supported in stream-json pipe mode (`"default"` mode causes tool calls to fail silently). Users can control tool access via `allowed_tools`/`disallowed_tools` parameters. The `permission_modal()` UI component exists for future MCP-channel-based interactive approval.

## Dependencies

Runtime: `shiny`, `shinychat`, `processx`, `jsonlite`, `htmltools`, `bsicons`. Requires Claude Code CLI on PATH.

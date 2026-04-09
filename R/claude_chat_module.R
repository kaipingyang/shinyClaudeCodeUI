#' Claude Code Chat UI Module
#'
#' Creates a chat-style UI for interacting with Claude Code, powered by
#' shinychat. Renders assistant responses as Markdown bubbles, tool calls
#' as collapsible cards, and displays session status.
#'
#' @param id Module namespace id
#' @param height CSS height of the chat area (default "100%")
#'
#' @return A Shiny UI tag list
#' @export
#'
#' @examples
#' \dontrun{
#' library(shiny)
#' library(bslib)
#' ui <- page_fillable(
#'   claude_chat_ui("claude", height = "100%")
#' )
#' server <- function(input, output, session) {
#'   claude_chat_server("claude", workdir = getwd())
#' }
#' shinyApp(ui, server)
#' }
claude_chat_ui <- function(id, height = "100%") {
  ns <- shiny::NS(id)

  shiny::addResourcePath(
    "shinyClaudeCodeUI-assets",
    system.file("css", package = "shinyClaudeCodeUI")
  )
  shiny::addResourcePath(
    "shinyClaudeCodeUI-js",
    system.file("js", package = "shinyClaudeCodeUI")
  )

  css_version <- as.character(utils::packageVersion("shinyClaudeCodeUI"))

  htmltools::tagList(
    htmltools::tags$link(
      rel = "stylesheet",
      href = paste0("shinyClaudeCodeUI-assets/claude-chat.css?v=", css_version)
    ),
    htmltools::tags$script(
      src = paste0("shinyClaudeCodeUI-js/claude-chat.js?v=", css_version)
    ),
    htmltools::tags$div(
      class = "claude-chat-container",
      style = paste0("height:", height),
      status_bar_ui(ns),
      htmltools::tags$div(
        class = "claude-chat-area",
        shinychat::chat_ui(
          ns("chat"),
          height = "100%",
          placeholder = "Ask Claude Code anything... (type / for skills)"
        )
      ),
      # Skill autocomplete dropdown - populated by server via sendCustomMessage
      htmltools::tags$div(
        id = ns("skill_dropdown"),
        class = "skill-autocomplete",
        `data-chat-ns` = ns("chat"),
        hidden = NA
      )
    ),
    htmltools::tags$script(htmltools::HTML(sprintf('
      (function() {
        Shiny.addCustomMessageHandler("shinyClaudeCodeUI_event_%s", function(event) {
          var statusEl = document.getElementById("%s");
          if (event.event_type === "init") {
            var modelEl = document.getElementById("%s");
            if (modelEl && event.data && event.data.model) {
              modelEl.innerHTML = "\\u2699 " + event.data.model;
            }
          }
          if (event.event_type === "partial_text" || event.event_type === "text" ||
              event.event_type === "tool_use") {
            if (statusEl) statusEl.innerHTML = "\\u25CF Processing...";
          }
          if (event.event_type === "status" && event.data && event.data.message) {
            if (statusEl) statusEl.innerHTML = "\\u23F3 " + event.data.message;
          }
          if (event.event_type === "complete") {
            if (statusEl) statusEl.innerHTML = "";
            var tokenEl = document.getElementById("%s");
            if (tokenEl && event.data) {
              var inp = event.data.input_tokens || 0;
              var out = event.data.output_tokens || 0;
              var cost = event.data.total_cost_usd;
              var txt = "Tokens: " + inp.toLocaleString() + " in / " + out.toLocaleString() + " out";
              if (cost) txt += " ($" + cost.toFixed(4) + ")";
              tokenEl.innerHTML = txt;
            }
          }
        });

        // Skills list from server -> populate dropdown autocomplete
        Shiny.addCustomMessageHandler("shinyClaudeCodeUI_skills_%s", function(data) {
          if (window.shinyClaudeSetSkills) {
            window.shinyClaudeSetSkills("%s", data.skills || []);
          }
        });

      })();
    ',
      id,
      ns("status_busy"),
      ns("status_model"),
      ns("status_tokens"),
      id,                    # for skills handler name
      ns("skill_dropdown")   # dropdown element id
    )))
  )
}


#' Claude Code Chat Server Module
#'
#' Manages the Claude Code CLI process lifecycle: starts the subprocess,
#' polls for JSON events, renders them via shinychat, and handles cleanup.
#'
#' @param id Module namespace id (must match the id used in `claude_chat_ui`)
#' @param workdir Working directory for Claude Code (default: current directory)
#' @param claude_bin Path to claude binary (auto-detected if NULL). Can also be
#'   set via the `CLAUDE_BIN` environment variable.
#' @param permission_mode Permission mode: "default", "auto", "plan", or
#'   "bypassPermissions" (default: "bypassPermissions"). Note: interactive
#'   permission approval is not supported in stream-json pipe mode, so
#'   "default" mode will cause tool calls to fail. Use "bypassPermissions"
#'   with `allowed_tools`/`disallowed_tools` to control access.
#' @param model Optional model override (e.g., "sonnet", "opus")
#' @param system_prompt Optional system prompt override
#' @param allowed_tools Optional character vector of allowed tool names
#' @param disallowed_tools Optional character vector of disallowed tool names
#' @param api_key Optional Anthropic API key string. Passed as the
#'   `ANTHROPIC_API_KEY` environment variable to the Claude subprocess.
#'   Merged with the parent process environment; takes precedence over any
#'   same-named variable in `env`. If `NULL` (default), the parent process
#'   value of `ANTHROPIC_API_KEY` is inherited as-is.
#' @param env Optional named character vector of extra environment variables
#'   to pass to the Claude subprocess, e.g.
#'   `c(ANTHROPIC_BASE_URL = "https://...", HTTPS_PROXY = "...")`.
#'   Merged on top of the parent process environment; values here override
#'   same-named parent vars.
#' @param config_file Optional path to a settings JSON file (same format as
#'   `~/.claude/settings.json`). Passed to the CLI via `--settings <path>`.
#'   Settings are **merged on top of** the user's existing
#'   `~/.claude/settings.json`; they do not replace it. Use this to supply
#'   per-session overrides such as MCP server definitions or model preferences
#'   without modifying the global user config.
#' @param skills_dir Directory containing Claude Code skills (default:
#'   `~/.claude/skills`). Both `.md` files and subdirectories are recognised.
#'   Skill names are sent to the browser to power the `/`-autocomplete in the
#'   chat input.
#'
#' @section Slash commands and skills:
#' Users can type `/skill-name` directly in the chat input (e.g. `/commit`,
#' `/review`) to invoke any Claude Code skill installed in
#' `~/.claude/skills/`. No additional configuration is required.
#'
#' @return NULL (called for side effects)
#' @export
#'
#' @examples
#' \dontrun{
#' # Basic usage
#' claude_chat_server("claude", workdir = "/path/to/project")
#'
#' # With API key and custom base URL
#' claude_chat_server("claude",
#'   api_key = Sys.getenv("MY_API_KEY"),
#'   env = c(ANTHROPIC_BASE_URL = "https://my-proxy.example.com"))
#'
#' # With custom settings file
#' claude_chat_server("claude",
#'   config_file = "path/to/project-settings.json")
#' }
claude_chat_server <- function(id, workdir = getwd(),
                               claude_bin = NULL,
                               permission_mode = "bypassPermissions",
                               model = NULL,
                               system_prompt = NULL,
                               allowed_tools = NULL,
                               disallowed_tools = NULL,
                               api_key = NULL,
                               env = NULL,
                               config_file = NULL,
                               skills_dir = path.expand("~/.claude/skills")) {

  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Resolve claude binary
    if (is.null(claude_bin)) {
      claude_bin <- find_claude()
    }

    # Plain environment for mutable state (not reactiveValues, because
    # later::later() callbacks are not reactive consumers)
    rv <- new.env(parent = emptyenv())
    rv$proc <- NULL
    rv$buffer <- ""
    rv$tool_registry <- list()
    rv$tool_cards_rendered <- list()  # Track which tool cards have been rendered
    rv$current_tool_id <- NULL        # Tool_use block currently being streamed
    rv$tool_input_buffers <- list()   # Accumulate input_json_delta per tool_id
    rv$tool_titles <- list()          # Computed display titles keyed by tool_id
    rv$tool_title_shown <- list()     # Whether an early title update was sent
    rv$is_streaming <- FALSE
    rv$current_text <- ""
    rv$is_thinking <- FALSE
    rv$is_thinking_streaming <- FALSE
    rv$current_thinking <- ""
    rv$text_already_rendered <- FALSE
    rv$current_block_type <- ""
    rv$token_count <- 0  # Count tokens processed
    rv$progress_id <- NULL  # Track cli progress bar

    # Send available skills to browser for / autocomplete
    later::later(function() {
      skills <- list_skills(skills_dir)
      if (length(skills) > 0) {
        session$sendCustomMessage(
          paste0("shinyClaudeCodeUI_skills_", id),
          list(skills = as.list(skills))
        )
      }
    }, delay = 0)

    # Build CLI args
    build_args <- function() {
      args <- c("-p",
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
        "--include-partial-messages")

      if (!is.null(model)) args <- c(args, "--model", model)

      if (!is.null(permission_mode)) {
        if (permission_mode == "bypassPermissions") {
          args <- c(args, "--dangerously-skip-permissions")
        } else {
          args <- c(args, "--permission-mode", permission_mode)
        }
      }

      if (!is.null(system_prompt)) args <- c(args, "--system-prompt", system_prompt)
      if (!is.null(allowed_tools)) args <- c(args, "--allowedTools", paste(allowed_tools, collapse = ","))
      if (!is.null(disallowed_tools)) args <- c(args, "--disallowedTools", paste(disallowed_tools, collapse = ","))
      if (!is.null(config_file)) args <- c(args, "--settings", normalizePath(config_file, mustWork = TRUE))

      args
    }

    # Build subprocess env - merges parent env with api_key and user-supplied env
    build_env <- function() {
      if (is.null(api_key) && is.null(env)) return(NULL)
      if (!is.null(env)) {
        if (!is.character(env) || is.null(names(env)) || any(!nzchar(names(env))))
          stop("'env' must be a named character vector with non-empty names")
      }
      proc_env <- "current"  # processx sentinel: inherit parent env
      if (!is.null(env)) proc_env <- c(proc_env, env)
      if (!is.null(api_key)) proc_env <- c(proc_env, ANTHROPIC_API_KEY = api_key)
      proc_env
    }

    # --- Process startup (eager: tied to session lifecycle, not first message) ---

    start_process <- function() {
      message("[shinyClaudeCodeUI] Starting claude process...")
      rv$proc <- processx::process$new(
        command = claude_bin,
        args = build_args(),
        stdin = "|", stdout = "|", stderr = "|",
        wd = workdir,
        env = build_env()
      )
      rv$buffer <- ""
      message("[shinyClaudeCodeUI] PID: ", rv$proc$get_pid())
    }

    # --- later::later() based polling (each callback = own flush cycle) ---

    # stdout polling - recursive scheduling via later::later()
    poll_stdout <- function() {
      proc <- rv$proc
      if (is.null(proc)) return()

      if (!proc$is_alive()) {
        rem <- tryCatch(proc$read_all_output(), error = function(e) "")
        if (nzchar(rem)) process_output(rem, rv, session, ns, id)
        return()
      }

      out <- tryCatch(proc$read_output(2000), error = function(e) "")
      if (nzchar(out)) process_output(out, rv, session, ns, id)

      later::later(poll_stdout, delay = 0.05)
    }

    # stderr polling
    poll_stderr <- function() {
      proc <- rv$proc
      if (is.null(proc) || !proc$is_alive()) return()
      err <- tryCatch(proc$read_error(2000), error = function(e) "")
      if (nzchar(err)) message("[shinyClaudeCodeUI] STDERR: ", substr(err, 1, 200))
      later::later(poll_stderr, delay = 0.5)
    }

    # Start process and polling immediately at session init
    start_process()
    later::later(poll_stdout, delay = 0)
    later::later(poll_stderr, delay = 0)

    # Handle user input from shinychat
    shiny::observeEvent(input$chat_user_input, {
      user_msg <- input$chat_user_input
      if (!nzchar(trimws(user_msg))) return()

      # Restart process if it died between messages
      if (is.null(rv$proc) || !rv$proc$is_alive()) {
        start_process()
        later::later(poll_stdout, delay = 0)
        later::later(poll_stderr, delay = 0)
      }

      # Reset per-turn streaming state
      rv$current_text <- ""
      rv$is_streaming <- FALSE
      rv$is_thinking <- FALSE
      rv$is_thinking_streaming <- FALSE
      rv$current_thinking <- ""
      rv$text_already_rendered <- FALSE
      rv$tool_cards_rendered <- list()
      rv$token_count <- 0

      # Start R console progress bar
      rv$progress_id <- cli::cli_progress_bar(
        format = "{cli::pb_spin} {msg}",
        format_done = "{cli::col_green(cli::symbol$tick)} {msg}",
        extra = list(msg = "Sending message..."),
        clear = FALSE
      )

      # Send message
      msg <- list(type = "user", message = list(role = "user", content = user_msg))
      rv$proc$write_input(paste0(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n"))

      cli::cli_progress_update(id = rv$progress_id, extra = list(msg = "Waiting for response..."))
    })

    # Cleanup
    session$onSessionEnded(function() {
      proc <- shiny::isolate(rv$proc)
      if (!is.null(proc) && proc$is_alive()) {
        proc$kill()
      }
    })
  })
}


#' Process raw stdout output from Claude CLI
#' @keywords internal
process_output <- function(raw_output, rv, session, ns, id) {
  buf <- paste0(rv$buffer, raw_output)
  lines <- strsplit(buf, "\n", fixed = TRUE)[[1]]

  if (!grepl("\n$", buf)) {
    rv$buffer <- lines[length(lines)]
    lines <- lines[-length(lines)]
  } else {
    rv$buffer <- ""
  }

  for (line in lines) {
    line <- trimws(line)
    if (!nzchar(line)) next

    evt <- tryCatch(
      jsonlite::fromJSON(line, simplifyVector = FALSE),
      error = function(e) {
        message("[shinyClaudeCodeUI] JSON parse error: ", substr(line, 1, 100))
        NULL
      }
    )
    if (is.null(evt)) next

    handle_event(evt, rv, session, ns, id)
  }
}


#' Handle a single parsed JSON event
#' @keywords internal
handle_event <- function(evt, rv, session, ns, id) {
  chat_id <- "chat"  # shinychat resolves via session$ns internally

  type <- evt$type %||% "unknown"

  # Debug: log every event
  if (type == "stream_event") {
    et <- evt$event$type %||% "?"
    bt <- evt$event$content_block$type %||% evt$event$delta$type %||% ""
    message("[DEBUG] event=stream_event/", et, " block_type=", bt,
            " is_streaming=", rv$is_streaming, " is_thinking=", rv$is_thinking)
  } else {
    message("[DEBUG] event=", type)
  }

  # Update R console progress bar if active
  update_progress <- function(msg) {
    if (!is.null(rv$progress_id)) {
      tryCatch(
        cli::cli_progress_update(id = rv$progress_id, extra = list(msg = msg)),
        error = function(e) { rv$progress_id <- NULL }
      )
    }
  }

  # --- system events ---
  if (type == "system") {
    subtype <- evt$subtype %||% ""
    if (subtype == "init") {
      update_progress(paste0("Connected to ", evt$model %||% "Claude"))
      session$sendCustomMessage(
        paste0("shinyClaudeCodeUI_event_", id),
        list(event_type = "init", data = list(model = evt$model))
      )
    } else if (subtype == "api_retry") {
      update_progress(paste0("Rate limited, retrying (attempt ", evt$attempt, ")..."))
      session$sendCustomMessage(
        paste0("shinyClaudeCodeUI_event_", id),
        list(event_type = "status", data = list(
          message = paste0("Rate limited, retrying (attempt ", evt$attempt, ")...")
        ))
      )
    }
    return(invisible())
  }

  # --- assistant message ---
  if (type == "assistant" && !is.null(evt$message$content)) {
    for (block in evt$message$content) {
      block_type <- block$type %||% "unknown"

      message("[DEBUG][assistant] block_type=", block_type, " id=", block$id %||% "NA",
              " is_streaming=", rv$is_streaming, " text_rendered=", rv$text_already_rendered)

      if (block_type == "text" && nzchar(block$text %||% "")) {
        if (rv$is_streaming) {
          message("[DEBUG][APPEND] assistant/text/end-stream len=", nchar(block$text))
          shinychat::chat_append_message(chat_id,
            list(role = "assistant", content = ""),
            chunk = "end", session = session)
          rv$is_streaming <- FALSE
          rv$current_text <- ""
          rv$text_already_rendered <- TRUE
        } else if (isTRUE(rv$text_already_rendered)) {
          message("[DEBUG][SKIP] assistant/text already rendered")
        } else {
          message("[DEBUG][APPEND] assistant/text/full len=", nchar(block$text))
          shinychat::chat_append_message(chat_id,
            list(role = "assistant", content = block$text),
            chunk = FALSE, session = session)
        }

      } else if (block_type == "tool_use") {
        if (isTRUE(rv$tool_cards_rendered[[block$id]])) {
          message("[DEBUG][SKIP] tool_use already rendered: ", block$name, " id=", block$id)
        } else {
          message("[DEBUG][APPEND] assistant/tool_use/fallback: ", block$name, " id=", block$id)
          rv$tool_registry[[block$id]] <- block$name
          rv$tool_cards_rendered[[block$id]] <- TRUE
          args_json <- tryCatch(
            jsonlite::toJSON(block$input %||% list(), auto_unbox = TRUE),
            error = function(e) "{}"
          )
          tool_title <- make_tool_title(block$name %||% "unknown", block$input %||% list())
          rv$tool_titles[[block$id]] <- tool_title  # Save for result card
          card_html <- as.character(htmltools::tag("shiny-tool-request", list(
            `request-id` = block$id,
            `tool-name`  = block$name %||% "unknown",
            `tool-title` = tool_title,
            arguments    = args_json
          )))
          shinychat::chat_append_message(chat_id,
            list(role = "assistant", content = card_html),
            chunk = FALSE, session = session)
        }

      } else if (block_type == "thinking") {
        message("[DEBUG][SKIP] assistant/thinking (handled by stream_event)")
      }
    }

    # Update status
    session$sendCustomMessage(
      paste0("shinyClaudeCodeUI_event_", id),
      list(event_type = "text", data = list())
    )
    return(invisible())
  }

  # --- user message (tool results) ---
  if (type == "user" && !is.null(evt$message$content)) {
    for (block in evt$message$content) {
      if (identical(block$type, "tool_result")) {
        is_error <- isTRUE(block$is_error)
        content <- block$content %||% ""
        tool_name <- rv$tool_registry[[block$tool_use_id]]

        content_str <- if (is.character(content)) content
                       else jsonlite::toJSON(content, auto_unbox = TRUE)

        # Replace the shiny-tool-request bubble in-place using chunk=TRUE + operation="replace"
        # chunk=FALSE always creates a new message; chunk=TRUE with operation=NULL replaces content
        tool_title <- rv$tool_titles[[block$tool_use_id]]
        card_html <- as.character(htmltools::tag("shiny-tool-result", list(
          `request-id` = block$tool_use_id,
          `tool-name`  = tool_name %||% "unknown",
          `tool-title` = tool_title %||% NULL,
          status       = if (is_error) "error" else "success",
          value        = content_str,
          `value-type` = "code"
        )))
        shinychat::chat_append_message(chat_id,
          list(role = "assistant", content = card_html),
          chunk = TRUE, operation = "replace", session = session)
      }
    }
    return(invisible())
  }

  # --- stream_event (partial streaming: text, thinking, tool_use) ---
  if (type == "stream_event") {
    event_data <- evt$event %||% list()
    event_type <- event_data$type %||% ""

    # content_block_start - track block type; end text stream before tool_use
    if (event_type == "content_block_start") {
      block <- event_data$content_block %||% list()
      rv$current_block_type <- block$type %||% ""

      if (identical(block$type, "tool_use")) {
        # End any active text stream first
        if (rv$is_streaming) {
          message("[DEBUG][APPEND] stream/tool_use/end-text-stream")
          shinychat::chat_append_message(chat_id,
            list(role = "assistant", content = ""),
            chunk = "end", session = session)
          rv$is_streaming <- FALSE
          rv$current_text <- ""
          rv$text_already_rendered <- TRUE
        }
        # Track tool and render "running" card immediately (with empty args)
        if (!is.null(block$id)) {
          tool_name <- block$name %||% "unknown"
          rv$tool_registry[[block$id]] <- tool_name
          rv$tool_cards_rendered[[block$id]] <- TRUE  # Mark as rendered
          rv$current_tool_id <- block$id              # Track for input_json_delta
          rv$tool_input_buffers[[block$id]] <- ""     # Init accumulation buffer
          rv$tool_title_shown[[block$id]] <- FALSE    # No early title yet
          update_progress(paste0("Running tool: ", tool_name))
          card_html <- as.character(htmltools::tag("shiny-tool-request", list(
            `request-id` = block$id,
            `tool-name` = tool_name,
            arguments = "{}"
          )))
          message("[DEBUG][APPEND] stream/tool_use/card: ", tool_name, " id=", block$id)
          shinychat::chat_append_message(chat_id,
            list(role = "assistant", content = card_html),
            chunk = FALSE, session = session)
        }
      }
      # Show thinking placeholder bubble immediately
      if (identical(block$type, "thinking")) {
        rv$is_thinking <- TRUE
        rv$current_thinking <- ""
        update_progress("Thinking...")
        placeholder <- as.character(thinking_card("..."))
        shinychat::chat_append_message(chat_id,
          list(role = "assistant", content = placeholder),
          chunk = FALSE, session = session)
      }
    }

    # content_block_delta - token-by-token text and thinking
    if (event_type == "content_block_delta") {
      delta <- event_data$delta %||% list()

      # Text streaming - buffer whitespace-only prefix to avoid empty bubbles
      if (identical(delta$type, "text_delta") && nzchar(delta$text %||% "")) {
        rv$current_text <- paste0(rv$current_text, delta$text)
        rv$token_count <- rv$token_count + 1

        # Update progress every 10 tokens
        if (rv$token_count %% 10 == 0) {
          update_progress(paste0("Streaming... (", rv$token_count, " tokens)"))
        }

        if (!rv$is_streaming) {
          # Only start rendering once we have real (non-whitespace) content
          if (nzchar(trimws(rv$current_text))) {
            rv$is_streaming <- TRUE
            message("[DEBUG][APPEND] stream/text/chunk=start len=", nchar(rv$current_text))
            shinychat::chat_append_message(chat_id,
              list(role = "assistant", content = rv$current_text),
              chunk = "start", session = session)
          }
        } else {
          shinychat::chat_append_message(chat_id,
            list(role = "assistant", content = delta$text),
            chunk = TRUE, session = session)
        }
      }

      # Thinking - accumulate buffer, render as card at content_block_stop
      if (identical(delta$type, "thinking_delta") && nzchar(delta$thinking %||% "")) {
        rv$current_thinking <- paste0(rv$current_thinking %||% "", delta$thinking)
      }

      # Tool input - accumulate JSON fragments for current tool_use block
      if (identical(delta$type, "input_json_delta") && !is.null(rv$current_tool_id)) {
        partial <- delta$partial_json %||% ""
        if (nzchar(partial)) {
          tool_id <- rv$current_tool_id
          rv$tool_input_buffers[[tool_id]] <- paste0(
            rv$tool_input_buffers[[tool_id]] %||% "",
            partial
          )

          # Early title update: fire once as soon as we can extract something
          if (!isTRUE(rv$tool_title_shown[[tool_id]])) {
            tool_name <- rv$tool_registry[[tool_id]] %||% "unknown"
            early_title <- try_partial_title(tool_name, rv$tool_input_buffers[[tool_id]])
            if (!is.null(early_title)) {
              rv$tool_title_shown[[tool_id]] <- TRUE
              early_card <- as.character(htmltools::tag("shiny-tool-request", list(
                `request-id` = tool_id,
                `tool-name`  = tool_name,
                `tool-title` = early_title,
                arguments    = "{}"
              )))
              shinychat::chat_append_message(chat_id,
                list(role = "assistant", content = early_card),
                chunk = TRUE, operation = "replace", session = session)
            }
          }
        }
      }
    }

    # content_block_stop - end text stream; finalize thinking block
    if (event_type == "content_block_stop") {
      if (identical(rv$current_block_type, "text") && rv$is_streaming) {
        message("[DEBUG][APPEND] stream/block_stop/text/chunk=end")
        shinychat::chat_append_message(chat_id,
          list(role = "assistant", content = ""),
          chunk = "end", session = session)
        rv$is_streaming <- FALSE
        rv$current_text <- ""
        rv$text_already_rendered <- TRUE
      }
      if (isTRUE(rv$is_thinking)) {
        # Replace the placeholder with final thinking card (or remove if empty)
        final_content <- if (nzchar(rv$current_thinking %||% ""))
          as.character(thinking_card(rv$current_thinking))
        else ""
        shinychat::chat_append_message(chat_id,
          list(role = "assistant", content = final_content),
          chunk = TRUE, operation = "replace", session = session)
        rv$is_thinking <- FALSE
        rv$is_thinking_streaming <- FALSE
        rv$current_thinking <- ""
      }

      # Tool input complete - update card with proper title and full arguments
      if (identical(rv$current_block_type, "tool_use") && !is.null(rv$current_tool_id)) {
        tool_id   <- rv$current_tool_id
        tool_name <- rv$tool_registry[[tool_id]] %||% "unknown"
        input_json <- rv$tool_input_buffers[[tool_id]] %||% "{}"

        input <- tryCatch(
          jsonlite::fromJSON(input_json, simplifyVector = FALSE),
          error = function(e) list()
        )
        tool_title <- make_tool_title(tool_name, input)
        rv$tool_titles[[tool_id]] <- tool_title  # Save for result card

        card_html <- as.character(htmltools::tag("shiny-tool-request", list(
          `request-id` = tool_id,
          `tool-name`  = tool_name,
          `tool-title` = tool_title,
          arguments    = input_json
        )))
        message("[DEBUG][UPDATE] tool_use/title=", tool_title)
        shinychat::chat_append_message(chat_id,
          list(role = "assistant", content = card_html),
          chunk = TRUE, operation = "replace", session = session)

        rv$current_tool_id <- NULL
      }

      rv$current_block_type <- ""
    }

    return(invisible())
  }

  # --- result ---
  if (type == "result") {
    if (rv$is_streaming) {
      message("[DEBUG][APPEND] result/end-stream")
      shinychat::chat_append_message(chat_id,
        list(role = "assistant", content = ""),
        chunk = "end", session = session)
      rv$is_streaming <- FALSE
      rv$current_text <- ""
    }

    # Complete progress bar
    inp_tokens <- evt$usage$input_tokens %||% 0
    out_tokens <- evt$usage$output_tokens %||% 0
    cost <- evt$total_cost_usd
    cost_str <- if (!is.null(cost)) sprintf(" ($%.4f)", cost) else ""

    if (!is.null(rv$progress_id)) {
      tryCatch({
        cli::cli_progress_update(id = rv$progress_id,
          extra = list(msg = paste0("Complete! ", inp_tokens, " in / ", out_tokens, " out", cost_str)))
        cli::cli_progress_done(id = rv$progress_id)
      }, error = function(e) NULL)
      rv$progress_id <- NULL
    }

    # Send token info
    session$sendCustomMessage(
      paste0("shinyClaudeCodeUI_event_", id),
      list(event_type = "complete", data = list(
        input_tokens = inp_tokens,
        output_tokens = out_tokens,
        total_cost_usd = cost
      ))
    )

    # Use shinychat's official remove-loading-message handler to clean up and re-enable
    # This calls shinychat's internal #f() -> #o() (remove empty msg) + #c() (re-enable)
    session$sendCustomMessage("shinyChatMessage", list(
      id = session$ns(chat_id),
      handler = "shiny-chat-remove-loading-message",
      obj = list()
    ))

    return(invisible())
  }
}

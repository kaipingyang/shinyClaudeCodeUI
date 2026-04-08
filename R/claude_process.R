#' Find Claude Code CLI binary
#'
#' @return Path to claude binary
#' @keywords internal
find_claude <- function() {
  # 1. Explicit override via CLAUDE_BIN env var
  env_bin <- Sys.getenv("CLAUDE_BIN", unset = "")
  if (nzchar(env_bin)) {
    if (!file.exists(env_bin))
      warning("CLAUDE_BIN='", env_bin, "' does not exist; falling back to PATH search")
    else
      return(env_bin)
  }

  # 2. PATH lookup
  claude <- Sys.which("claude")
  if (nzchar(claude)) return(claude)

  # 3. Common install locations
  candidates <- c(
    path.expand("~/.local/bin/claude"),
    path.expand("~/.claude/local/claude"),
    "/usr/local/bin/claude"
  )
  for (p in candidates) {
    if (file.exists(p)) return(p)
  }

  stop("Claude Code CLI not found. Install from https://claude.ai/code or set CLAUDE_BIN env var")
}


#' Start a Claude Code CLI process
#'
#' Launches `claude -p --stream-json` as a subprocess with stdin/stdout pipes.
#'
#' @param session Shiny session object
#' @param id Module instance id
#' @param workdir Working directory for claude
#' @param claude_bin Path to claude binary
#' @param model Optional model override
#' @param permission_mode Permission mode ("default", "auto", "plan", "bypassPermissions")
#' @param system_prompt Optional system prompt override
#' @param allowed_tools Optional character vector of allowed tools
#' @param disallowed_tools Optional character vector of disallowed tools
#' @param api_key Optional Anthropic API key (`ANTHROPIC_API_KEY`)
#' @param env Optional named character vector of extra environment variables
#' @param config_file Optional path to a settings JSON file (`--settings`)
#'
#' @keywords internal
claude_start <- function(session, id, workdir, claude_bin,
                         model = NULL, permission_mode = NULL,
                         system_prompt = NULL,
                         allowed_tools = NULL,
                         disallowed_tools = NULL,
                         api_key = NULL,
                         env = NULL,
                         config_file = NULL) {

  args <- c(
    "-p",
    "--input-format", "stream-json",
    "--output-format", "stream-json",
    "--verbose",
    "--include-partial-messages"
  )

  if (!is.null(model)) {
    args <- c(args, "--model", model)
  }
  if (!is.null(permission_mode)) {
    if (permission_mode == "bypassPermissions") {
      args <- c(args, "--dangerously-skip-permissions")
    } else {
      args <- c(args, "--permission-mode", permission_mode)
    }
  }
  if (!is.null(system_prompt)) {
    args <- c(args, "--system-prompt", system_prompt)
  }
  if (!is.null(allowed_tools)) {
    args <- c(args, "--allowedTools", paste(allowed_tools, collapse = ","))
  }
  if (!is.null(disallowed_tools)) {
    args <- c(args, "--disallowedTools", paste(disallowed_tools, collapse = ","))
  }
  if (!is.null(config_file)) {
    args <- c(args, "--settings", normalizePath(config_file, mustWork = TRUE))
  }

  proc_env <- NULL
  if (!is.null(env) || !is.null(api_key)) {
    proc_env <- "current"
    if (!is.null(env)) proc_env <- c(proc_env, env)
    if (!is.null(api_key)) proc_env <- c(proc_env, ANTHROPIC_API_KEY = api_key)
  }

  proc <- processx::process$new(
    command = claude_bin,
    args = args,
    stdin = "|",
    stdout = "|",
    stderr = "|",
    wd = workdir,
    env = proc_env
  )

  # Store in session userData
  if (is.null(session$userData$.shinyClaudeCodeUI)) {
    session$userData$.shinyClaudeCodeUI <- list()
  }
  session$userData$.shinyClaudeCodeUI[[id]] <- list(
    proc = proc,
    buffer = "",
    initialized = FALSE,
    session_info = list(),
    busy = FALSE
  )

  # Polling is handled by claude_chat_server's own observe()
  # Do NOT call claude_poll_start() here to avoid duplicate readers

  invisible(proc)
}


#' Send a user message to Claude Code
#'
#' @param session Shiny session object
#' @param id Module instance id
#' @param message User message text
#'
#' @keywords internal
claude_send <- function(session, id, message) {
  state <- session$userData$.shinyClaudeCodeUI[[id]]
  if (is.null(state) || !state$proc$is_alive()) return(invisible(NULL))

  msg <- list(
    type = "user",
    message = list(
      role = "user",
      content = message
    )
  )

  json_line <- paste0(jsonlite::toJSON(msg, auto_unbox = TRUE), "\n")
  state$proc$write_input(json_line)
  session$userData$.shinyClaudeCodeUI[[id]]$busy <- TRUE

  invisible(NULL)
}


#' Poll Claude CLI stdout for new events
#'
#' Uses invalidateLater(50) to poll the subprocess stdout pipe,
#' parse JSON events, and dispatch them to the UI.
#'
#' @param session Shiny session object
#' @param id Module instance id
#'
#' @keywords internal
claude_poll_start <- function(session, id) {
  ns <- session$ns

  poll_observer <- shiny::observe({
    state <- session$userData$.shinyClaudeCodeUI[[id]]

    if (is.null(state) || !state$proc$is_alive()) {
      return(NULL)
    }

    shiny::invalidateLater(50, session)

    # Read available stdout
    new_output <- tryCatch(
      state$proc$read_output(2000),
      error = function(e) ""
    )

    if (!nzchar(new_output)) return(NULL)

    # Buffer management: accumulate partial lines
    buf <- paste0(state$buffer, new_output)
    lines <- strsplit(buf, "\n", fixed = TRUE)[[1]]

    # If buffer doesn't end with newline, last element is incomplete
    if (!grepl("\n$", buf)) {
      session$userData$.shinyClaudeCodeUI[[id]]$buffer <- lines[length(lines)]
      lines <- lines[-length(lines)]
    } else {
      session$userData$.shinyClaudeCodeUI[[id]]$buffer <- ""
    }

    # Parse each complete JSON line
    for (line in lines) {
      line <- trimws(line)
      if (!nzchar(line)) next

      event <- tryCatch(
        parse_stream_event(line),
        error = function(e) NULL
      )

      if (is.null(event)) next

      # Dispatch to module via custom input
      session$sendCustomMessage(
        paste0("shinyClaudeCodeUI_event_", id),
        event
      )
    }
  })

  invisible(poll_observer)
}


#' Stop a Claude Code CLI process
#'
#' @param session Shiny session object
#' @param id Module instance id
#'
#' @keywords internal
claude_stop <- function(session, id) {
  state <- session$userData$.shinyClaudeCodeUI[[id]]
  if (is.null(state)) return(invisible(NULL))

  if (state$proc$is_alive()) {
    tryCatch(
      state$proc$signal(2L),  # SIGINT
      error = function(e) NULL
    )
    tryCatch(
      state$proc$wait(timeout = 3000),
      error = function(e) {
        tryCatch(state$proc$kill(), error = function(e) NULL)
      }
    )
  }

  session$userData$.shinyClaudeCodeUI[[id]] <- NULL
  invisible(NULL)
}

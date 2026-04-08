#' Create a tool use card (collapsible)
#'
#' Renders a tool invocation as a collapsible card showing the tool name
#' and its input parameters.
#'
#' @param tool_name Name of the tool being called
#' @param input List of tool input parameters
#' @param tool_use_id Unique identifier for this tool call
#'
#' @return An htmltools tag
#' @keywords internal
tool_use_card <- function(tool_name, input, tool_use_id = NULL) {
  # Icon mapping for common Claude Code tools

  icon <- tool_icon(tool_name)

  # Format input as pretty JSON or key-value
  input_display <- format_tool_input(tool_name, input)

  htmltools::tags$details(
    class = "claude-tool-card",
    id = if (!is.null(tool_use_id)) paste0("tool-", tool_use_id),
    htmltools::tags$summary(
      class = "claude-tool-summary",
      htmltools::tags$span(class = "claude-tool-icon", icon),
      htmltools::tags$span(class = "claude-tool-name", tool_name),
      htmltools::tags$span(class = "claude-tool-badge", "running...")
    ),
    htmltools::tags$div(
      class = "claude-tool-input",
      htmltools::tags$pre(
        htmltools::tags$code(input_display)
      )
    )
  )
}


#' Create a tool result card
#'
#' @param tool_use_id ID of the corresponding tool_use
#' @param content Result content (text or structured)
#' @param is_error Whether the tool returned an error
#' @param tool_name Optional tool name for display
#'
#' @return An htmltools tag
#' @keywords internal
tool_result_card <- function(tool_use_id, content, is_error = FALSE,
                             tool_name = NULL) {
  result_class <- if (is_error) "claude-tool-result error" else "claude-tool-result"

  # Truncate very long results
  display_content <- if (nchar(content) > 2000) {
    paste0(substr(content, 1, 2000), "\n... (truncated)")
  } else {
    content
  }

  htmltools::tags$div(
    class = result_class,
    if (is_error) {
      htmltools::tags$div(
        class = "claude-tool-error-header",
        bsicons::bs_icon("x-circle-fill"),
        " Error"
      )
    },
    htmltools::tags$pre(
      class = "claude-tool-output",
      htmltools::tags$code(display_content)
    )
  )
}


#' Create a thinking/reasoning card (collapsible)
#'
#' @param thinking The thinking text content
#'
#' @return An htmltools tag
#' @keywords internal
thinking_card <- function(thinking) {
  # Truncate very long thinking
  display <- if (nchar(thinking) > 3000) {
    paste0(substr(thinking, 1, 3000), "\n... (truncated)")
  } else {
    thinking
  }

  htmltools::tags$details(
    class = "claude-thinking-card",
    open = NA,
    htmltools::tags$summary(
      class = "claude-thinking-summary",
      bsicons::bs_icon("lightbulb"),
      " Thinking..."
    ),
    htmltools::tags$div(
      class = "claude-thinking-content",
      display
    )
  )
}


#' Create a permission request modal
#'
#' @param ns Namespace function
#' @param tool_name Name of the tool requesting permission
#' @param tool_input Tool input parameters
#' @param message Permission denial message
#'
#' @return A Shiny modal dialog
#' @keywords internal
permission_modal <- function(ns, tool_name, tool_input = NULL,
                             message = NULL) {
  input_display <- if (!is.null(tool_input)) {
    jsonlite::toJSON(tool_input, auto_unbox = TRUE, pretty = TRUE)
  } else {
    message %||% "Permission required"
  }

  shiny::modalDialog(
    title = htmltools::tagList(
      bsicons::bs_icon("shield-exclamation"),
      " Permission Required"
    ),
    htmltools::tags$div(
      class = "claude-permission-content",
      htmltools::tags$div(
        class = "claude-permission-tool",
        htmltools::tags$strong("Tool: "),
        htmltools::tags$code(tool_name)
      ),
      htmltools::tags$div(
        class = "claude-permission-details",
        htmltools::tags$pre(
          htmltools::tags$code(input_display)
        )
      ),
      if (!is.null(message)) {
        htmltools::tags$div(
          class = "claude-permission-message",
          message
        )
      }
    ),
    footer = htmltools::tagList(
      shiny::actionButton(ns("perm_allow_once"), "Allow Once",
        class = "btn-warning"),
      shiny::actionButton(ns("perm_deny"), "Deny",
        class = "btn-danger"),
      shiny::modalButton("Close")
    ),
    easyClose = FALSE
  )
}


#' Create session status bar
#'
#' Shows model, session ID, token usage, and processing status.
#'
#' @param ns Namespace function
#'
#' @return An htmltools tag
#' @keywords internal
status_bar_ui <- function(ns) {
  htmltools::tags$div(
    class = "claude-status-bar",
    htmltools::tags$span(
      class = "claude-status-model",
      id = ns("status_model"),
      bsicons::bs_icon("cpu"),
      " Connecting..."
    ),
    htmltools::tags$span(
      class = "claude-status-tokens",
      id = ns("status_tokens"),
      ""
    ),
    htmltools::tags$span(
      class = "claude-status-indicator",
      id = ns("status_busy"),
      ""
    )
  )
}


#' Get icon for a tool name
#' @keywords internal
tool_icon <- function(tool_name) {
  icons <- list(
    Bash = "terminal",
    Read = "file-earmark-text",
    Write = "file-earmark-plus",
    Edit = "pencil-square",
    Glob = "search",
    Grep = "search",
    Agent = "people",
    WebSearch = "globe",
    WebFetch = "globe2"
  )

  icon_name <- icons[[tool_name]] %||% "gear"
  as.character(bsicons::bs_icon(icon_name))
}


#' Format tool input for display
#' @keywords internal
format_tool_input <- function(tool_name, input) {
  if (is.null(input) || length(input) == 0) return("")

  # Special formatting for common tools
  if (tool_name == "Bash" && !is.null(input$command)) {
    return(paste0("$ ", input$command))
  }
  if (tool_name == "Read" && !is.null(input$file_path)) {
    return(paste0("Reading: ", input$file_path))
  }
  if (tool_name == "Edit" && !is.null(input$file_path)) {
    return(paste0("Editing: ", input$file_path))
  }
  if (tool_name == "Write" && !is.null(input$file_path)) {
    return(paste0("Writing: ", input$file_path))
  }
  if (tool_name == "Glob" && !is.null(input$pattern)) {
    return(paste0("Pattern: ", input$pattern))
  }
  if (tool_name == "Grep" && !is.null(input$pattern)) {
    return(paste0("Search: ", input$pattern))
  }

  # Default: pretty JSON
  jsonlite::toJSON(input, auto_unbox = TRUE, pretty = TRUE)
}

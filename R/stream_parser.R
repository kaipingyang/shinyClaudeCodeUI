#' Parse a single stream-json event line
#'
#' Converts a JSON line from Claude CLI `--output-format stream-json` into
#' a normalized R list with `event_type` and `data` fields.
#'
#' @param line A single JSON string (one line from stdout)
#'
#' @return A list with:
#'   - `event_type`: character, one of "init", "text", "tool_use", "tool_result",
#'     "permission_request", "thinking", "partial_text", "complete", "error"
#'   - `data`: list with event-specific payload
#'
#' @keywords internal
parse_stream_event <- function(line) {
  evt <- jsonlite::fromJSON(line, simplifyVector = FALSE)

  switch(evt$type,
    "system" = parse_system_event(evt),
    "assistant" = parse_assistant_event(evt),
    "user" = parse_user_event(evt),
    "result" = parse_result_event(evt),
    "stream_event" = parse_partial_event(evt),
    list(event_type = "unknown", data = evt)
  )
}


#' Parse system event (init, api_retry, etc.)
#' @keywords internal
parse_system_event <- function(evt) {
  subtype <- evt$subtype %||% "unknown"

  if (subtype == "init") {
    list(
      event_type = "init",
      data = list(
        session_id = evt$session_id %||% NA_character_,
        model = evt$model %||% NA_character_,
        tools = evt$tools %||% list(),
        permission_mode = evt$permissionMode %||% NA_character_,
        cwd = evt$cwd %||% NA_character_,
        version = evt$claude_code_version %||% NA_character_
      )
    )
  } else if (subtype == "api_retry") {
    list(
      event_type = "status",
      data = list(
        message = paste0("Rate limited, retrying (attempt ",
                         evt$attempt %||% "?", ")..."),
        retry_delay_ms = evt$retry_delay_ms %||% 0
      )
    )
  } else {
    list(event_type = "stream_meta", data = list(subtype = subtype))
  }
}


#' Parse assistant message event
#'
#' An assistant message can contain multiple content blocks:
#' text, tool_use, and thinking.
#'
#' @keywords internal
parse_assistant_event <- function(evt) {
  msg <- evt$message
  if (is.null(msg) || is.null(msg$content)) {
    return(list(event_type = "text", data = list(text = "")))
  }

  # Extract all content blocks
  blocks <- msg$content
  results <- list()

  for (block in blocks) {
    block_type <- block$type %||% "unknown"

    if (block_type == "text") {
      results <- c(results, list(list(
        event_type = "text",
        data = list(
          text = block$text %||% "",
          message_id = msg$id %||% NA_character_
        )
      )))

    } else if (block_type == "tool_use") {
      results <- c(results, list(list(
        event_type = "tool_use",
        data = list(
          tool_name = block$name %||% "unknown",
          tool_use_id = block$id %||% NA_character_,
          input = block$input %||% list(),
          message_id = msg$id %||% NA_character_
        )
      )))

    } else if (block_type == "thinking") {
      results <- c(results, list(list(
        event_type = "thinking",
        data = list(
          thinking = block$thinking %||% "",
          message_id = msg$id %||% NA_character_
        )
      )))
    }
  }

  # If single result, return it directly; otherwise wrap as multi
  if (length(results) == 1) {
    results[[1]]
  } else if (length(results) > 1) {
    list(event_type = "multi", data = list(events = results))
  } else {
    list(event_type = "text", data = list(text = ""))
  }
}


#' Parse user message event (tool results)
#' @keywords internal
parse_user_event <- function(evt) {
  msg <- evt$message
  if (is.null(msg) || is.null(msg$content)) {
    return(list(event_type = "unknown", data = list()))
  }

  blocks <- msg$content
  results <- list()

  for (block in blocks) {
    block_type <- block$type %||% "unknown"

    if (block_type == "tool_result") {
      is_error <- isTRUE(block$is_error)
      content <- block$content %||% ""

      # Detect permission denial
      is_permission <- is_error && grepl(
        "requires approval|permission|not allowed",
        content, ignore.case = TRUE
      )

      if (is_permission) {
        results <- c(results, list(list(
          event_type = "permission_request",
          data = list(
            tool_use_id = block$tool_use_id %||% NA_character_,
            message = content
          )
        )))
      } else {
        results <- c(results, list(list(
          event_type = "tool_result",
          data = list(
            tool_use_id = block$tool_use_id %||% NA_character_,
            content = content,
            is_error = is_error
          )
        )))
      }
    }
  }

  if (length(results) == 1) {
    results[[1]]
  } else if (length(results) > 1) {
    list(event_type = "multi", data = list(events = results))
  } else {
    list(event_type = "unknown", data = list())
  }
}


#' Parse result (completion) event
#' @keywords internal
parse_result_event <- function(evt) {
  list(
    event_type = "complete",
    data = list(
      is_error = isTRUE(evt$is_error),
      result = evt$result %||% "",
      duration_ms = evt$duration_ms %||% NA_real_,
      num_turns = evt$num_turns %||% NA_integer_,
      total_cost_usd = evt$total_cost_usd %||% NA_real_,
      session_id = evt$session_id %||% NA_character_,
      usage = evt$usage %||% list(),
      input_tokens = evt$usage$input_tokens %||% 0L,
      output_tokens = evt$usage$output_tokens %||% 0L
    )
  )
}


#' Parse streaming partial event
#'
#' These events arrive when `--include-partial-messages` is enabled,
#' providing token-by-token text streaming.
#'
#' @keywords internal
parse_partial_event <- function(evt) {
  event_data <- evt$event %||% list()
  event_type <- event_data$type %||% "unknown"

  if (event_type == "content_block_delta") {
    delta <- event_data$delta %||% list()
    if (identical(delta$type, "text_delta")) {
      return(list(
        event_type = "partial_text",
        data = list(text = delta$text %||% "")
      ))
    }
  }

  # For other stream events (message_start, content_block_start/stop, etc.)
  # we mostly ignore them — the full assistant message will arrive separately

  list(event_type = "stream_meta", data = list(stream_type = event_type))
}


#' Null-coalescing operator
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

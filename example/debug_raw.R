# Raw debug app — no package, no module, just processx + shinychat
library(shiny)
library(bslib)
library(shinychat)
library(processx)
library(jsonlite)

ui <- page_fillable(
  theme = bs_theme(bg = "#1e1e1e", fg = "#d4d4d4", primary = "#4ec9b0"),
  tags$div(id = "debug_log",
    style = "height:100px;overflow-y:auto;font-size:11px;color:#888;padding:4px;border-bottom:1px solid #333"),
  chat_ui("chat", height = "calc(100vh - 140px)",
    placeholder = "Ask Claude Code anything...")
)

server <- function(input, output, session) {

  rv <- reactiveValues(proc = NULL, buffer = "")

  # Debug log helper
  log_msg <- function(msg) {
    message("[DEBUG] ", msg)
    session$sendCustomMessage("debug_log", msg)
  }

  # JS handler for debug log
  insertUI(selector = "head", where = "beforeEnd", ui = tags$script(HTML('
    Shiny.addCustomMessageHandler("debug_log", function(msg) {
      var el = document.getElementById("debug_log");
      if (el) {
        el.innerHTML += "<br>" + msg;
        el.scrollTop = el.scrollHeight;
      }
    });
  ')))

  # On user input: start process if needed, send message
  observeEvent(input$chat_user_input, {
    user_msg <- input$chat_user_input
    log_msg(paste0("Input: ", user_msg))

    if (is.null(rv$proc) || !rv$proc$is_alive()) {
      log_msg("Starting claude process...")
      claude_bin <- Sys.which("claude")
      if (!nzchar(claude_bin)) claude_bin <- path.expand("~/.local/bin/claude")
      log_msg(paste0("Binary: ", claude_bin))

      rv$proc <- process$new(
        command = claude_bin,
        args = c("-p",
          "--input-format", "stream-json",
          "--output-format", "stream-json",
          "--verbose",
          "--dangerously-skip-permissions"),
        stdin = "|", stdout = "|", stderr = "|",
        wd = getwd()
      )
      log_msg(paste0("PID: ", rv$proc$get_pid(), " alive: ", rv$proc$is_alive()))
      rv$buffer <- ""
    }

    msg <- list(type = "user", message = list(role = "user", content = user_msg))
    json_line <- paste0(toJSON(msg, auto_unbox = TRUE), "\n")
    log_msg(paste0("Sending JSON: ", substr(json_line, 1, 100)))
    rv$proc$write_input(json_line)
    log_msg("Sent!")
  })

  # Poll stdout
  observe({
    invalidateLater(100)

    proc <- rv$proc
    if (is.null(proc)) return()

    if (!proc$is_alive()) {
      log_msg(paste0("Process died, exit: ", proc$get_exit_status()))
      # Drain remaining
      rem <- tryCatch(proc$read_all_output(), error = function(e) "")
      if (nzchar(rem)) log_msg(paste0("Drained: ", nchar(rem), " chars"))
      return()
    }

    out <- tryCatch(proc$read_output(2000), error = function(e) "")
    err <- tryCatch(proc$read_error(2000), error = function(e) "")

    if (nzchar(err)) log_msg(paste0("STDERR: ", substr(err, 1, 200)))

    if (!nzchar(out)) return()

    log_msg(paste0("GOT OUTPUT: ", nchar(out), " chars"))

    buf <- paste0(rv$buffer, out)
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

      evt <- tryCatch(fromJSON(line, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(evt)) { log_msg(paste0("Parse fail: ", substr(line, 1, 50))); next }

      log_msg(paste0("Event: type=", evt$type,
        if (!is.null(evt$subtype)) paste0(" sub=", evt$subtype) else ""))

      # Render text events
      if (evt$type == "assistant" && !is.null(evt$message$content)) {
        for (block in evt$message$content) {
          if (block$type == "text" && nzchar(block$text %||% "")) {
            log_msg(paste0("Rendering text: ", substr(block$text, 1, 80)))
            chat_append_message("chat",
              list(role = "assistant", content = block$text),
              chunk = FALSE, session = session)
          }
          if (block$type == "tool_use") {
            log_msg(paste0("Tool: ", block$name))
            chat_append_message("chat",
              list(role = "assistant", content = paste0("**Tool:** `", block$name, "`")),
              chunk = FALSE, session = session)
          }
        }
      }

      if (evt$type == "result") {
        cost <- evt$total_cost_usd
        log_msg(paste0("DONE! Cost: $", cost))
        chat_append_message("chat",
          list(role = "assistant", content = paste0("*Done. Cost: $", round(cost %||% 0, 4), "*")),
          chunk = FALSE, session = session)
      }
    }
  })

  session$onSessionEnded(function() {
    if (!is.null(isolate(rv$proc)) && isolate(rv$proc)$is_alive()) {
      isolate(rv$proc)$kill()
    }
  })
}

shinyApp(ui, server)

library(shiny)
library(bslib)
library(shinyClaudeCodeUI)

ui <- page_fillable(
  title = "shinyClaudeCodeUI Demo",
  claude_chat_ui("claude", height = "calc(100vh - 20px)")
)

server <- function(input, output, session) {
  claude_chat_server("claude",
    workdir = getwd()
  )
}

shinyApp(ui, server)

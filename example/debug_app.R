# Minimal debug app — test shinychat inside a module
library(shiny)
library(bslib)
library(shinychat)

# Simple module that wraps shinychat
test_ui <- function(id) {
  ns <- shiny::NS(id)
  tagList(
    tags$div(
      style = "height:400px",
      shinychat::chat_ui(ns("chat"), height = "100%",
        placeholder = "Type something...")
    )
  )
}

test_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    observeEvent(input$chat_user_input, {
      msg <- input$chat_user_input
      message("Got input: ", msg)

      # Test 1: Simple text with chat_append using module-relative "chat"
      shinychat::chat_append("chat", paste("Echo:", msg),
        role = "assistant", session = session)
      message("Appended with id='chat'")
    })
  })
}

ui <- page_fillable(
  test_ui("mymod")
)

server <- function(input, output, session) {
  test_server("mymod")
}

shinyApp(ui, server)

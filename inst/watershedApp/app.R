library(leaflet)
library(sf)
library(watershed)

title <- "Interactive Watershed Map"

ui <- shiny::fluidPage(
    shiny::titlePanel(title),
    shiny::sidebarLayout(
        shiny::sidebarPanel(
            watershed::watershedInput("watershed")
        ),
        shiny::mainPanel(
            watershed::watershedOutput("watershed")
        )
    )
)

server <- function(input, output, session) {
    watershed::watershedServer("watershed")
}

shiny::shinyApp(ui = ui, server = server)

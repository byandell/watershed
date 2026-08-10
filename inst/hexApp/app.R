library(leaflet)
library(sf)
library(hexmap)

title <- "Hexagonal Watershed Map"

ui <- shiny::fluidPage(
    shiny::titlePanel(title),
    shiny::sidebarLayout(
        shiny::sidebarPanel(
            hexmap::hexmapInput("hexmap")
        ),
        shiny::mainPanel(
            hexmap::hexmapOutput("hexmap")
        )
    )
)

server <- function(input, output, session) {
    hexmap::hexmapServer("hexmap")
}

shiny::shinyApp(ui = ui, server = server)

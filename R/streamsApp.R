#' UI Component for StreamStats Leaflet Explorer
#'
#' @param id Shiny module ID
#' @export
#' @rdname streamsApp
streamsInput <- function(id) {
    ns <- shiny::NS(id)

    shiny::tagList(
        shiny::h4("StreamStats Flowline & Watershed Explorer"),
        shiny::p("Select a state/region code and click on the map to delineate streams and watersheds via USGS StreamStats."),
        shiny::fluidRow(
            shiny::column(
                width = 4,
                shiny::selectInput(
                    inputId = ns("rcode"),
                    label = "State / Region Code:",
                    choices = c(
                        "Wisconsin" = "WI",
                        "Illinois" = "IL",
                        "Iowa" = "IA",
                        "Minnesota" = "MN",
                        "Michigan" = "MI"
                    ),
                    selected = "WI"
                )
            ),
            shiny::column(
                width = 8,
                shiny::div(
                    style = "margin-top: 25px;",
                    shiny::actionButton(
                        inputId = ns("clear_streams"),
                        label = "Clear Stream Layers",
                        class = "btn-warning",
                        icon = shiny::icon("trash")
                    )
                )
            )
        ),
        leaflet::leafletOutput(ns("stream_map"), height = "550px"),
        shiny::br(),
        shiny::uiOutput(ns("stream_status"))
    )
}

#' Server Logic for StreamStats Leaflet Explorer
#'
#' @param id Shiny module ID
#' @param default_lat Initial latitude for the map view (default: 43.0731)
#' @param default_lng Initial longitude for the map view (default: -89.4012)
#' @param default_zoom Initial map zoom level (default: 9)
#' @export
#' @rdname streamsApp
streamsServer <- function(id, default_lat = 43.0731, default_lng = -89.4012, default_zoom = 9) {
    shiny::moduleServer(id, function(input, output, session) {
        ns <- session$ns

        # Reactive value to store status updates
        status_msg <- shiny::reactiveVal(
            "<div style='color:gray;'><i>Click any location on the map to query USGS StreamStats.</i></div>"
        )

        # Render Status Message UI
        output$stream_status <- shiny::renderUI({
            shiny::HTML(status_msg())
        })

        # Render Initial Base Map
        output$stream_map <- leaflet::renderLeaflet({
            leaflet::leaflet() %>%
                leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) %>%
                leaflet::setView(lng = default_lng, lat = default_lat, zoom = default_zoom)
        })

        # Observer for Map Clicks: Trigger StreamStats Delineation
        shiny::observeEvent(input$stream_map_click, {
            click <- input$stream_map_click
            shiny::req(click)

            lat <- round(click$lat, 5)
            lng <- round(click$lng, 5)
            region <- input$rcode

            status_msg(sprintf(
                "<div style='color:blue;'><b>Querying StreamStats:</b> Requesting flowlines for (%f, %f) in %s...</div>",
                lat, lng, region
            ))

            # Fetch stream network using your add_streamstats_layer function
            shiny::withProgress(message = "Fetching StreamStats data...", value = 0.5, {
                tryCatch(
                    {
                        leaflet::leafletProxy("stream_map", session = session) %>%
                            add_streamstats_layer(
                                lat = lat,
                                lng = lng,
                                rcode = region,
                                layer_group = "StreamStats Layer"
                            ) %>%
                            leaflet::addCircleMarkers(
                                lng = lng,
                                lat = lat,
                                radius = 5,
                                color = "#D35400",
                                fillColor = "#E67E22",
                                fillOpacity = 0.9,
                                group = "StreamStats Layer",
                                popup = sprintf("<b>Pour Point</b><br/>Lat: %f<br/>Lng: %f", lat, lng)
                            )

                        status_msg(sprintf(
                            "<div style='color:green;'><b>Success:</b> Added StreamStats flowlines for point (%f, %f).</div>",
                            lat, lng
                        ))
                    },
                    error = function(e) {
                        status_msg(sprintf(
                            "<div style='color:red;'><b>Error:</b> Failed to delineate streams: %s</div>",
                            e$message
                        ))
                    }
                )
            })
        })

        # Clear Stream Layers
        shiny::observeEvent(input$clear_streams, {
            leaflet::leafletProxy("stream_map", session = session) %>%
                leaflet::clearGroup("StreamStats Layer")

            status_msg("<div style='color:gray;'>Cleared stream layers from map. Click map to add a new section.</div>")
        })
    })
}

#' Run the Standalone StreamStats Explorer App
#'
#' @export
#' @rdname streamsApp
streamsApp <- function() {
    ui <- shiny::fluidPage(
        shiny::titlePanel("USGS StreamStats Leaflet Explorer"),
        streamsInput("streams_module")
    )

    server <- function(input, output, session) {
        streamsServer("streams_module")
    }

    shiny::shinyApp(ui, server)
}

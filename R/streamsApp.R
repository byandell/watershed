#' UI Component for StreamStats Leaflet Explorer
#'
#' @param id Shiny module ID
#' @export
#' @rdname streamsApp
streamsInput <- function(id) {
  ns <- shiny::NS(id)

  shiny::tagList(
    shiny::h4("StreamStats Flowline & Watershed Explorer"),
    shiny::p("Explore continuous USGS hydrography stream layers and click on any stream to delineate the upstream watershed basin and vector flowlines."),
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
            "Michigan" = "MI",
            "New York" = "NY",
            "Ohio" = "OH",
            "Indiana" = "IN"
          ),
          selected = "WI"
        )
      ),
      shiny::column(
        width = 4,
        shiny::sliderInput(
          inputId = ns("buffer_km"),
          label = "Stream Search Radius (km):",
          min = 1,
          max = 15,
          value = 3,
          step = 1
        )
      ),
      shiny::column(
        width = 4,
        shiny::div(
          style = "margin-top: 25px;",
          shiny::actionButton(
            inputId = ns("clear_streams"),
            label = "Clear Delineations",
            class = "btn-warning",
            icon = shiny::icon("trash")
          )
        )
      )
    ),
    leaflet::leafletOutput(ns("stream_map"), height = "580px"),
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
      "<div style='color:gray;'><i>Click any location or stream on the map to delineate the watershed basin and highlight stream flowlines.</i></div>"
    )

    # Render Status Message UI
    output$stream_status <- shiny::renderUI({
      shiny::HTML(status_msg())
    })

    # Render Initial Base Map with Tile Layers and USGS Hydrography
    output$stream_map <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "CartoDB Positron") |>
        leaflet::addProviderTiles(leaflet::providers$OpenStreetMap, group = "OpenStreetMap") |>
        leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite Imagery") |>
        add_usgs_hydro_layer(group = "USGS Hydrography (Streams)") |>
        leaflet::addLayersControl(
          baseGroups = c("CartoDB Positron", "OpenStreetMap", "Satellite Imagery"),
          overlayGroups = c("USGS Hydrography (Streams)", "StreamStats Basin", "Stream Flowlines"),
          options = leaflet::layersControlOptions(collapsed = FALSE)
        ) |>
        leaflet::setView(lng = default_lng, lat = default_lat, zoom = default_zoom)
    })

    # Observer for Map Clicks: Trigger StreamStats Delineation and Flowline Extraction
    shiny::observeEvent(input$stream_map_click, {
      click <- input$stream_map_click
      shiny::req(click)

      lat <- round(as.numeric(click$lat), 5)
      lng <- round(as.numeric(click$lng), 5)
      region <- input$rcode
      buf_km <- input$buffer_km
      if (is.null(buf_km) || !is.numeric(buf_km)) buf_km <- 3

      status_msg(sprintf(
        "<div style='color:blue;'><b>Querying StreamStats & NHD:</b> Delineating basin and extracting flowlines for (%f, %f) in %s...</div>",
        lat, lng, region
      ))

      # Fetch stream network using add_streamstats_layer
      shiny::withProgress(message = "Delineating watershed basin & streams...", value = 0.4, {
        tryCatch(
          {
            proxy <- leaflet::leafletProxy("stream_map", session = session)
            add_streamstats_layer(
              map = proxy,
              lat = lat,
              lng = lng,
              rcode = region,
              basin_group = "StreamStats Basin",
              stream_group = "Stream Flowlines",
              buffer_km = buf_km,
              include_flowlines = TRUE
            )
            leaflet::addCircleMarkers(
              map = proxy,
              lng = lng,
              lat = lat,
              radius = 5,
              color = "#D35400",
              fillColor = "#E67E22",
              fillOpacity = 0.9,
              group = "Stream Flowlines",
              popup = sprintf("<b>Pour Point</b><br/>Lat: %f<br/>Lng: %f<br/>Region: %s", lat, lng, region)
            )

            status_msg(sprintf(
              "<div style='color:green; padding: 6px; background-color: #EAFAF1; border-left: 4px solid #2ECC71; margin-top: 6px;'><b>Success:</b> Delineated watershed basin and highlighted intersecting stream flowlines for point (%f, %f) in %s.</div>",
              lat, lng, region
            ))
          },
          error = function(e) {
            if (grepl("422", e$message) || grepl("Unprocessable", e$message, ignore.case = TRUE)) {
              status_msg(sprintf(
                "<div style='color:#D35400; padding: 6px; background-color: #FDF2E9; border-left: 4px solid #E67E22; margin-top: 6px;'><b>Invalid Location (HTTP 422):</b> Point (%f, %f) is outside region '%s' or not on a valid stream flowline grid cell. Try clicking directly on a stream.</div>",
                lat, lng, region
              ))
            } else {
              status_msg(sprintf(
                "<div style='color:red; padding: 6px; background-color: #FDEDEC; border-left: 4px solid #E74C3C; margin-top: 6px;'><b>Error:</b> Failed to delineate streams: %s</div>",
                e$message
              ))
            }
          }
        )
      })
    })

    # Clear Stream Layers
    shiny::observeEvent(input$clear_streams, {
      leaflet::leafletProxy("stream_map", session = session) |>
        leaflet::clearGroup("StreamStats Basin") |>
        leaflet::clearGroup("Stream Flowlines")

      status_msg("<div style='color:gray;'>Cleared stream delineations from map. Click map to add a new section.</div>")
    })
  })
}

#' Run the Standalone StreamStats Explorer App
#'
#' @export
#' @rdname streamsApp
streamsApp <- function() {
  ui <- shiny::fluidPage(
    shiny::titlePanel("USGS StreamStats & Hydrography Explorer"),
    streamsInput("streams_module")
  )

  server <- function(input, output, session) {
    streamsServer("streams_module")
  }

  shiny::shinyApp(ui, server)
}



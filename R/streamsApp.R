#' UI Component for StreamStats & Hydrography Leaflet Explorer
#'
#' Modular UI component supporting both standalone exploration and embedded sidebar controls
#' within parent applications (such as \code{watershedApp}).
#'
#' @param id Shiny module ID
#' @param mode Character string specifying layout mode: \code{"standalone"} (default) for full map page,
#'   or \code{"sidebar"} for embedded sidebar controls.
#' @export
#' @rdname streamsApp
streamsInput <- function(id, mode = c("standalone", "sidebar")) {
  ns <- shiny::NS(id)
  mode <- match.arg(mode)

  if (identical(mode, "sidebar")) {
    return(
      shiny::tagList(
        shiny::checkboxInput(ns("show_flowlines"), "Overlay NHD Stream Flowlines", value = TRUE),
        shiny::radioButtons(
          inputId = ns("stream_extent"),
          label = "Stream Flowline Extent:",
          choices = c(
            "Constrained to HUC(s)" = "huc",
            "Extended Bounding Box" = "bbox",
            "Buffered HUC Region" = "buffer"
          ),
          selected = "huc"
        ),
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'buffer'", ns("stream_extent")),
          shiny::sliderInput(ns("stream_buffer_km"), "Buffer Distance (km):", min = 1, max = 25, value = 5, step = 1)
        ),
        shiny::sliderInput(ns("min_stream_order"), "Min Stream Order:", min = 1, max = 6, value = 1, step = 1),
        shiny::checkboxInput(ns("show_legend"), "Display Map Legend", value = TRUE),
        shiny::actionButton(
          inputId = ns("clear_streams"),
          label = "Clear Stream Layers",
          class = "btn-warning btn-sm",
          icon = shiny::icon("trash"),
          style = "width: 100%; margin-top: 5px; margin-bottom: 10px;"
        )
      )
    )
  }

  # Standalone layout
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

#' Server Logic for StreamStats & Hydrography Leaflet Explorer
#'
#' Server module managing USGS StreamStats point delineation, NHD stream flowline extraction,
#' and dynamic Leaflet map layer rendering. Supports standalone operation and embedded module
#' composition within parent modules (such as \code{watershedServer}).
#'
#' @param id Shiny module ID
#' @param map_proxy_id Optional character string specifying a parent module's leafletProxy handle
#'   (e.g., \code{session$ns("map-mapper")}). When provided, stream flowlines and legends render to this proxy.
#' @param watershed_sf Optional reactive expression returning an \code{sf} polygon object representing
#'   the active HUC watershed boundary. When supplied, flowlines are automatically queried and synchronized.
#' @param show_hex_reactive Optional reactive expression returning logical whether hex grid is active (for legend sync).
#' @param show_habitat_reactive Optional reactive expression returning logical whether habitat is active (for legend sync).
#' @param default_lat Initial latitude for the map view (default: 43.0731)
#' @param default_lng Initial longitude for the map view (default: -89.4012)
#' @param default_zoom Initial map zoom level (default: 9)
#' @return A list of reactive expressions:
#'   \item{flowlines}{Reactive value holding the extracted NHD stream flowlines \code{sf} object (or \code{NULL}).}
#'   \item{show_flowlines}{Reactive expression returning whether flowlines overlay is enabled.}
#'   \item{min_stream_order}{Reactive expression returning the minimum Strahler stream order filter.}
#'   \item{show_legend}{Reactive expression returning whether map legend display is enabled.}
#'   \item{status}{Reactive value holding HTML status update messages.}
#' @export
#' @rdname streamsApp
streamsServer <- function(id,
                          map_proxy_id = NULL,
                          watershed_sf = NULL,
                          show_hex_reactive = NULL,
                          show_habitat_reactive = NULL,
                          default_lat = 43.0731,
                          default_lng = -89.4012,
                          default_zoom = 9) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    status_msg <- shiny::reactiveVal(
      "<div style='color:gray;'><i>Click any location or stream on the map to delineate the watershed basin and highlight stream flowlines.</i></div>"
    )
    flowlines_sf <- shiny::reactiveVal(NULL)

    # Status Message Output (Standalone mode)
    output$stream_status <- shiny::renderUI({
      shiny::HTML(status_msg())
    })

    # Render Initial Base Map (Standalone mode)
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

    # --- Mode 1: Embedded Watershed Synchronization (when watershed_sf is provided) ---
    if (!is.null(watershed_sf) && shiny::is.reactive(watershed_sf)) {
      shiny::observeEvent(list(watershed_sf(), input$show_flowlines, input$stream_extent, input$stream_buffer_km, input$min_stream_order), {
        w_sf <- watershed_sf()
        if (!isTRUE(input$show_flowlines) || is.null(w_sf) || nrow(w_sf) == 0) {
          flowlines_sf(NULL)
          if (!is.null(map_proxy_id)) {
            leaflet::leafletProxy(map_proxy_id) |>
              leaflet::clearGroup("Stream Flowlines")
          }
          return()
        }

        ext <- if (!is.null(input$stream_extent)) input$stream_extent else "huc"
        buf_km <- if (!is.null(input$stream_buffer_km)) input$stream_buffer_km else 5
        min_ord <- if (!is.null(input$min_stream_order)) input$min_stream_order else 1
        
        fl <- tryCatch(
          get_watershed_flowlines(w_sf, min_stream_order = min_ord, extent = ext, buffer_km = buf_km),
          error = function(e) NULL
        )

        flowlines_sf(fl)

        if (!is.null(map_proxy_id)) {
          proxy <- leaflet::leafletProxy(map_proxy_id) |>
            leaflet::clearGroup("Stream Flowlines")

          if (!is.null(fl) && nrow(fl) > 0) {
            proxy <- proxy |> add_leaflet_flowlines(fl)
          }

          # Update legend
          is_hex <- if (!is.null(show_hex_reactive) && shiny::is.reactive(show_hex_reactive)) isTRUE(show_hex_reactive()) else TRUE
          is_hab <- if (!is.null(show_habitat_reactive) && shiny::is.reactive(show_habitat_reactive)) isTRUE(show_habitat_reactive()) else TRUE
          add_watershed_legend(
            proxy,
            show_hex = is_hex,
            show_streams = isTRUE(input$show_flowlines),
            show_habitat = is_hab,
            show_legend = isTRUE(input$show_legend)
          )
        }
      }, ignoreNULL = FALSE)
    }

    # --- Mode 2: Standalone Map Click Observer ---
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

      shiny::withProgress(message = "Delineating watershed basin & streams...", value = 0.4, {
        tryCatch(
          {
            target_proxy <- if (!is.null(map_proxy_id)) map_proxy_id else "stream_map"
            proxy <- leaflet::leafletProxy(target_proxy, session = session)
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

    # Observer for Legend Toggle
    shiny::observeEvent(input$show_legend, {
      target_proxy <- if (!is.null(map_proxy_id)) map_proxy_id else "stream_map"
      proxy <- leaflet::leafletProxy(target_proxy, session = session)
      is_hex <- if (!is.null(show_hex_reactive) && shiny::is.reactive(show_hex_reactive)) isTRUE(show_hex_reactive()) else TRUE
      is_hab <- if (!is.null(show_habitat_reactive) && shiny::is.reactive(show_habitat_reactive)) isTRUE(show_habitat_reactive()) else TRUE
      add_watershed_legend(
        proxy,
        show_hex = is_hex,
        show_streams = isTRUE(input$show_flowlines),
        show_habitat = is_hab,
        show_legend = isTRUE(input$show_legend)
      )
    }, ignoreInit = TRUE)

    # Clear Stream Layers
    shiny::observeEvent(input$clear_streams, {
      target_proxy <- if (!is.null(map_proxy_id)) map_proxy_id else "stream_map"
      leaflet::leafletProxy(target_proxy, session = session) |>
        leaflet::clearGroup("StreamStats Basin") |>
        leaflet::clearGroup("Stream Flowlines")

      flowlines_sf(NULL)
      status_msg("<div style='color:gray;'>Cleared stream delineations from map. Click map to add a new section.</div>")
    })

    # Return Reactive Outputs for Parent Modules
    return(list(
      flowlines = flowlines_sf,
      show_flowlines = shiny::reactive(isTRUE(input$show_flowlines)),
      min_stream_order = shiny::reactive(if (!is.null(input$min_stream_order)) input$min_stream_order else 1),
      show_legend = shiny::reactive(isTRUE(input$show_legend)),
      status = status_msg
    ))
  })
}

#' Run the Standalone StreamStats Explorer App
#'
#' @export
#' @rdname streamsApp
streamsApp <- function() {
  ui <- shiny::fluidPage(
    shiny::titlePanel("USGS StreamStats & Hydrography Explorer"),
    streamsInput("streams_module", mode = "standalone")
  )

  server <- function(input, output, session) {
    streamsServer("streams_module")
  }

  shiny::shinyApp(ui, server)
}




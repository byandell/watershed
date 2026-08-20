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
        shiny::radioButtons(
          inputId = ns("stream_extent"),
          label = "Stream Flowline Extent:",
          choices = c(
            "None" = "none",
            "Constrained to HUC(s)" = "huc",
            "Extended Bounding Box" = "bbox",
            "Buffered HUC Region" = "buffer"
          ),
          selected = "none"
        ),
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == 'buffer'", ns("stream_extent")),
          shiny::sliderInput(ns("stream_buffer_km"), "Buffer Distance (km):", min = 1, max = 25, value = 5, step = 1)
        ),
        shiny::sliderInput(ns("min_stream_order"), "Min Stream Order:", min = 1, max = 6, value = 4, step = 1),
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
#' @param huc_level Optional reactive expression returning the active numeric HUC level (e.g. 2, 4, 6, 8, 10, 12)
#'   to dynamically scale default stream order granularity.
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
                          parent_session = NULL,
                          watershed_sf = NULL,
                          huc_level = NULL,
                          show_hex_reactive = NULL,
                          show_habitat_reactive = NULL,
                          default_lat = 43.0731,
                          default_lng = -89.4012,
                          default_zoom = 9) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Auto-adjust default min_stream_order based on active HUC level
    if (!is.null(huc_level) && shiny::is.reactive(huc_level)) {
      shiny::observeEvent(huc_level(), {
        lvl <- huc_level()
        if (!is.null(lvl) && is.numeric(lvl)) {
          target_ord <- if (lvl <= 4) 5 else if (lvl <= 6) 4 else if (lvl <= 8) 3 else if (lvl <= 10) 2 else 1
          if (!is.null(input$min_stream_order) && input$min_stream_order != target_ord) {
            shiny::updateSliderInput(session, "min_stream_order", value = target_ord)
          }
        }
      }, ignoreInit = TRUE)
    }

    # Auto-adjust min_stream_order slider default when a new HUC watershed region is selected
    last_huc_key <- shiny::reactiveVal("")
    if (!is.null(watershed_sf) && shiny::is.reactive(watershed_sf)) {
      shiny::observeEvent(watershed_sf(), {
        w_sf <- watershed_sf()
        if (!is.null(w_sf) && inherits(w_sf, "sf") && nrow(w_sf) > 0) {
          bb <- sf::st_bbox(sf::st_transform(w_sf, 4326))
          current_key <- paste(round(as.numeric(bb), 3), collapse = "_")
          if (current_key != last_huc_key()) {
            last_huc_key(current_key)
            dx <- max(as.numeric(bb["xmax"] - bb["xmin"]), 0.01)
            dy <- max(as.numeric(bb["ymax"] - bb["ymin"]), 0.01)
            total_area_deg2 <- dx * dy
            
            target_ord <- if (total_area_deg2 > 3.5) {
              5
            } else if (total_area_deg2 > 1.0) {
              4
            } else if (total_area_deg2 > 0.25) {
              3
            } else if (total_area_deg2 > 0.05) {
              2
            } else {
              1
            }
            shiny::updateSliderInput(session, "min_stream_order", value = target_ord)
          }
        }
      }, ignoreNULL = TRUE)
    }

    # Helper function to get the appropriate leafletProxy with correct session namespace scoping
    get_proxy <- function() {
      if (!is.null(parent_session) && !is.null(map_proxy_id)) {
        leaflet::leafletProxy(map_proxy_id, session = parent_session)
      } else if (!is.null(map_proxy_id)) {
        leaflet::leafletProxy(map_proxy_id, session = session)
      } else {
        leaflet::leafletProxy("stream_map", session = session)
      }
    }

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
        add_usgs_shaded_relief_layer(group = "USGS Shaded Relief (DEM)") |>
        add_usgs_topo_layer(group = "USGS Topo") |>
        leaflet::addProviderTiles(leaflet::providers$OpenStreetMap, group = "OpenStreetMap") |>
        leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite Imagery") |>
        add_usgs_hydro_layer(group = "USGS Hydrography (Streams)") |>
        leaflet::addLayersControl(
          baseGroups = c("CartoDB Positron", "USGS Shaded Relief (DEM)", "USGS Topo", "OpenStreetMap", "Satellite Imagery"),
          overlayGroups = c("USGS Hydrography (Streams)", "StreamStats Basin", "Stream Flowlines"),
          options = leaflet::layersControlOptions(collapsed = FALSE)
        ) |>
        leaflet::setView(lng = default_lng, lat = default_lat, zoom = default_zoom)
    })

    # Debounce slider inputs to prevent network thrashing during slider dragging
    throttled_buffer_km <- shiny::reactive(input$stream_buffer_km) |> shiny::debounce(400)
    throttled_min_order <- shiny::reactive(input$min_stream_order) |> shiny::debounce(200)

    # --- Mode 1: Embedded Watershed Synchronization (when watershed_sf is provided) ---
    # Stage 1: Spatial Fetch Reactive
    # Queries flowlines with server-side streamorder filtering matching slider/HUC scale
    raw_flowlines_sf <- shiny::reactive({
      if (is.null(watershed_sf) || !shiny::is.reactive(watershed_sf)) return(NULL)
      w_sf <- watershed_sf()
      ext <- if (!is.null(input$stream_extent)) input$stream_extent else "none"

      if (ext == "none" || is.null(w_sf) || nrow(w_sf) == 0) {
        return(NULL)
      }

      buf_km <- if (!is.null(throttled_buffer_km())) throttled_buffer_km() else 5
      min_ord <- if (!is.null(throttled_min_order())) throttled_min_order() else 4
      shiny::withProgress(message = "Fetching NHD stream flowlines from USGS...", value = 0.5, {
        tryCatch(
          get_watershed_flowlines(w_sf, min_stream_order = min_ord, extent = ext, buffer_km = buf_km),
          error = function(e) NULL
        )
      })
    })

    # Stage 2: In-Memory Stream Order Filter Reactive
    # Subsets the cached raw flowlines locally (0 API calls, instantaneous)
    active_flowlines_sf <- shiny::reactive({
      raw_fl <- raw_flowlines_sf()
      if (is.null(raw_fl) || nrow(raw_fl) == 0) return(NULL)

      min_ord <- if (!is.null(throttled_min_order())) throttled_min_order() else 4
      if (is.numeric(min_ord) && min_ord > 1 && "streamorde" %in% names(raw_fl)) {
        raw_fl[!is.na(raw_fl$streamorde) & raw_fl$streamorde >= min_ord, ]
      } else {
        raw_fl
      }
    })

    # Stage 3: Map Proxy & Legend Synchronizer
    if (!is.null(watershed_sf) && shiny::is.reactive(watershed_sf)) {
      shiny::observeEvent(list(active_flowlines_sf(), input$stream_extent), {
        fl <- active_flowlines_sf()
        ext <- if (!is.null(input$stream_extent)) input$stream_extent else "none"
        has_streams <- (ext != "none" && !is.null(fl) && nrow(fl) > 0)

        flowlines_sf(fl)

        if (!is.null(map_proxy_id)) {
          proxy <- get_proxy() |>
            leaflet::clearGroup("Stream Flowlines")

          if (has_streams) {
            proxy <- proxy |>
              leaflet::hideGroup("USGS Hydrography (Streams)") |>
              add_leaflet_flowlines(fl)
          } else {
            proxy <- proxy |>
              leaflet::showGroup("USGS Hydrography (Streams)")
          }

          # Update legend
          is_hex <- if (!is.null(show_hex_reactive) && shiny::is.reactive(show_hex_reactive)) isTRUE(show_hex_reactive()) else TRUE
          is_hab <- if (!is.null(show_habitat_reactive) && shiny::is.reactive(show_habitat_reactive)) isTRUE(show_habitat_reactive()) else TRUE
          add_watershed_legend(
            proxy,
            show_hex = is_hex,
            show_streams = (ext != "none"),
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
            proxy <- get_proxy()
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
      proxy <- get_proxy()
      is_hex <- if (!is.null(show_hex_reactive) && shiny::is.reactive(show_hex_reactive)) isTRUE(show_hex_reactive()) else TRUE
      is_hab <- if (!is.null(show_habitat_reactive) && shiny::is.reactive(show_habitat_reactive)) isTRUE(show_habitat_reactive()) else TRUE
      has_streams <- !is.null(input$stream_extent) && input$stream_extent != "none"
      add_watershed_legend(
        proxy,
        show_hex = is_hex,
        show_streams = has_streams,
        show_habitat = is_hab,
        show_legend = isTRUE(input$show_legend)
      )
    }, ignoreInit = TRUE)

    # Clear Stream Layers
    shiny::observeEvent(input$clear_streams, {
      get_proxy() |>
        leaflet::clearGroup("StreamStats Basin") |>
        leaflet::clearGroup("Stream Flowlines") |>
        leaflet::showGroup("USGS Hydrography (Streams)")

      flowlines_sf(NULL)
      shiny::updateRadioButtons(session, "stream_extent", selected = "none")
      status_msg("<div style='color:gray;'>Cleared stream delineations from map. Click map to add a new section.</div>")
    })

    # Return Reactive Outputs for Parent Modules
    return(list(
      flowlines = flowlines_sf,
      show_flowlines = shiny::reactive(!is.null(input$stream_extent) && input$stream_extent != "none"),
      min_stream_order = shiny::reactive(if (!is.null(input$min_stream_order)) input$min_stream_order else 4),
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




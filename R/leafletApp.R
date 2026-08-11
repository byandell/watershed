leafletInput <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h4("Interactive Map Explorer"),
    shiny::p("Search for a landmark, drop a point marker, or use the draw toolbar (top left) to outline a region."),
    leaflet::leafletOutput(ns("mapper"), height = "500px"),
    shiny::br(),
    shiny::uiOutput(ns("region_controls")),
    shiny::uiOutput(ns("huc_status"))
  )
}

#' Interactive Leaflet Mapping UI (Output)
#' @param id Module ID
#' @export
#' @rdname leafletApp
leafletOutput <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    # Extra output if needed, e.g. mapping details
  )
}

#' Interactive Leaflet Mapping Server Logic
#' Server logic for interactive Leaflet discovery. Returns a list of reactives
#' (`huc`, `status`, `click`, `drawn_polygon`) enabling Shiny module composition.
#'
#' @param id Module ID
#' @param huc_level Target USGS HUC digit level (2-12, default: 8, can be numeric or reactive).
#' @param max_hucs Maximum target number of HUC regions when searching drawn polygon extent (default: 6, can be a numeric or reactive).
#' @return A list of reactive objects: `huc` (reactiveVal holding discovered `sf` HUC polygon(s)),
#'   `status` (reactiveVal holding HTML status message), `click` (reactive holding map click details),
#'   and `drawn_polygon` (reactiveVal holding user drawn rubberband polygon sf).
#' @export
#' @importFrom leaflet renderLeaflet leafletProxy addPolygons clearShapes
#' @importFrom sf st_sfc st_polygon st_sf
#' @importFrom shiny is.reactive
#' @rdname leafletApp
leafletServer <- function(id, huc_level = 8, max_hucs = 6) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Helper to resolve huc_level parameter (numeric constant or reactive expression)
    get_huc_level <- function() {
      if (shiny::is.reactive(huc_level)) {
        val <- huc_level()
        if (!is.null(val) && length(val) > 0) val else 8
      } else if (!is.null(huc_level) && length(huc_level) > 0) {
        huc_level
      } else {
        8
      }
    }

    # Helper to resolve max_hucs parameter (numeric constant or reactive expression)
    get_max_hucs <- function() {
      if (shiny::is.reactive(max_hucs)) {
        val <- max_hucs()
        if (is.numeric(val) && length(val) > 0) val else 6
      } else if (is.numeric(max_hucs) && length(max_hucs) > 0) {
        max_hucs
      } else {
        6
      }
    }

    # Store dynamic reactive outputs
    status_msg <- shiny::reactiveVal("")
    huc_boundary <- shiny::reactiveVal(NULL)
    raw_fetched_hucs <- shiny::reactiveVal(NULL)
    base_huc_level <- shiny::reactiveVal(8)
    all_hucs_sf <- shiny::reactiveVal(NULL)
    included_huc_ids <- shiny::reactiveVal(character(0))
    drawn_polygon_sf <- shiny::reactiveVal(NULL)
    is_drawing <- shiny::reactiveVal(FALSE)

    output$huc_status <- shiny::renderUI({
      shiny::HTML(status_msg())
    })

    output$region_controls <- shiny::renderUI({
      poly <- drawn_polygon_sf()
      if (!is.null(poly)) {
        shiny::div(
          style = "display: flex; align-items: center; gap: 15px; flex-wrap: wrap; margin-bottom: 15px;",
          shiny::actionButton(ns("search_region"), "Search Watersheds in Region", class = "btn-success", icon = shiny::icon("search-location")),
          shiny::actionButton(ns("clear_region"), "Clear Region", class = "btn-secondary"),
          shiny::div(
            style = "display: flex; align-items: center; margin-top: 5px;",
            shiny::checkboxInput(ns("hide_rubberband"), "Hide Drawn Region", value = FALSE)
          )
        )
      } else {
        NULL
      }
    })

    # Observer for Hide Drawn Region checkbox
    shiny::observeEvent(input$hide_rubberband,
      {
        proxy <- leaflet::leafletProxy("mapper", session = session)
        if (isTRUE(input$hide_rubberband)) {
          proxy |>
            leaflet::clearGroup("Drawn Region") |>
            leaflet::hideGroup("Drawn Region")
        } else {
          poly <- drawn_polygon_sf()
          if (!is.null(poly)) {
            poly_4326 <- sf::st_transform(poly, 4326)
            is_point <- inherits(sf::st_geometry(poly_4326), "sfc_POINT")
            proxy <- proxy |> leaflet::showGroup("Drawn Region")
            if (is_point) {
              proxy |> leaflet::addCircleMarkers(
                data = poly_4326,
                color = "#000000",
                weight = 1.5,
                radius = 3.5,
                fillColor = "#FFFFFF",
                fillOpacity = 0.9,
                group = "Drawn Region"
              )
            } else {
              proxy |> leaflet::addPolygons(
                data = poly_4326,
                color = "#000000",
                weight = 1.5,
                fillColor = "#333333",
                fillOpacity = 0,
                group = "Drawn Region"
              )
            }
          }
        }
      },
      ignoreInit = FALSE
    )

    # Helper to resolve HUC ID column name across all HUC levels
    get_huc_col <- function(df) {
      cols <- names(df)
      for (c in c("huc16", "huc14", "huc12", "huc10", "huc08", "huc8", "huc06", "huc6", "huc04", "huc4", "huc02", "huc2", "id")) {
        if (c %in% cols) {
          return(c)
        }
      }
      return(cols[1])
    }

    # Helper function to render HUC polygon shapes with styled included/excluded layers
    render_huc_shapes <- function(hucs, selected_ids) {
      proxy <- leaflet::leafletProxy("mapper", session = session)

      if (is.null(hucs) || nrow(hucs) == 0) {
        proxy |> leaflet::clearGroup("huc_polygons")
        return()
      }

      is_poly <- any(c("POLYGON", "MULTIPOLYGON") %in% as.character(sf::st_geometry_type(hucs)))
      if (!is_poly) {
        proxy |> leaflet::clearGroup("huc_polygons")
        return()
      }

      huc_col <- get_huc_col(hucs)
      huc_type <- toupper(huc_col)

      hucs_4326 <- sf::st_transform(hucs, 4326)
      ids <- unname(as.character(hucs_4326[[huc_col]]))
      selected_ids <- unname(as.character(selected_ids))
      names_vec <- if ("name" %in% names(hucs_4326)) hucs_4326$name else rep("", length(ids))

      # Explicitly remove shapes by layerId and clear group to ensure Leaflet JS re-renders updated polygon styles
      proxy |> leaflet::removeShape(layerId = ids)
      proxy |> leaflet::clearGroup("huc_polygons")

      inc_mask <- ids %in% selected_ids

      # De-selected (excluded) watersheds: bold, high-contrast dashed crimson outline
      if (any(!inc_mask)) {
        excl_sf <- hucs_4326[!inc_mask, ]
        excl_ids <- ids[!inc_mask]
        excl_names <- names_vec[!inc_mask]
        proxy |> leaflet::addPolygons(
          data = excl_sf,
          layerId = excl_ids,
          group = "huc_polygons",
          color = "#C0392B",
          weight = 2.5,
          dashArray = "6,6",
          fillColor = "#E74C3C",
          fillOpacity = 0,
          popup = paste0("<b>", huc_type, ":</b> ", excl_ids, "<br/><b>Name:</b> ", excl_names, "<br/><i>(Excluded - click shape on map to include)</i>")
        )
      }

      # Selected (included) watersheds: solid vibrant purple outline
      if (any(inc_mask)) {
        inc_sf <- hucs_4326[inc_mask, ]
        inc_ids <- ids[inc_mask]
        inc_names <- names_vec[inc_mask]
        proxy |> leaflet::addPolygons(
          data = inc_sf,
          layerId = inc_ids,
          group = "huc_polygons",
          color = "#8E44AD",
          weight = 2,
          fillColor = "#8E44AD",
          fillOpacity = 0,
          popup = paste0("<b>", huc_type, ":</b> ", inc_ids, "<br/><b>Name:</b> ", inc_names, "<br/><i>(Included - click shape on map to exclude)</i>")
        )
      }
    }

    # Helper function to update included IDs, re-render shapes, and update huc_boundary
    update_included_ids <- function(new_inc) {
      all_hucs <- all_hucs_sf()
      if (is.null(all_hucs) || nrow(all_hucs) == 0) {
        return()
      }

      huc_col <- get_huc_col(all_hucs)
      valid_ids <- unname(as.character(all_hucs[[huc_col]]))

      new_inc <- intersect(unname(as.character(new_inc)), valid_ids)
      included_huc_ids(new_inc)
      render_huc_shapes(all_hucs, new_inc)

      filtered_sf <- all_hucs[valid_ids %in% new_inc, ]
      huc_boundary(if (nrow(filtered_sf) > 0) filtered_sf else NULL)

      n_inc <- length(new_inc)
      n_total <- length(valid_ids)
      status_msg(paste0("<div style='color:purple;'><b>Updated Selection:</b> ", n_inc, " of ", n_total, " watersheds included.</div>"))
    }

    # Observer for Shape Clicks (Toggle HUC inclusion/exclusion in-memory)
    shiny::observeEvent(input$mapper_shape_click, {
      click_shape <- input$mapper_shape_click
      if (is.null(click_shape) || is.null(click_shape$id)) {
        return()
      }

      clicked_id <- unname(as.character(click_shape$id))
      all_hucs <- all_hucs_sf()
      if (is.null(all_hucs) || nrow(all_hucs) == 0) {
        return()
      }

      huc_col <- get_huc_col(all_hucs)
      valid_ids <- unname(as.character(all_hucs[[huc_col]]))
      if (!clicked_id %in% valid_ids) {
        return()
      }

      current_inc <- unname(as.character(included_huc_ids()))
      new_inc <- if (clicked_id %in% current_inc) {
        setdiff(current_inc, clicked_id)
      } else {
        union(current_inc, clicked_id)
      }

      update_included_ids(new_inc)
    })

    # Render the initial basemap (Option A: Search and Draw toolbar included)
    output$mapper <- leaflet::renderLeaflet({
      build_base_map()
    })

    # Track drawing state and clear previous shapes when user hits polygon draw tool again
    shiny::observeEvent(input$mapper_draw_start, {
      is_drawing(TRUE)
      drawn_polygon_sf(NULL)
      huc_boundary(NULL)
      raw_fetched_hucs(NULL)
      all_hucs_sf(NULL)
      included_huc_ids(character(0))
      leaflet::leafletProxy("mapper", session = session) |>
        leaflet::clearGroup("Drawn Region") |>
        leaflet::clearGroup("huc_polygons") |>
        leaflet::clearGroup("Hex Overlay") |>
        leaflet::clearGroup("Habitat Substrate Mesh") |>
        leaflet::clearShapes() |>
        leaflet::clearMarkers()
    })

    shiny::observeEvent(input$mapper_draw_stop, {
      is_drawing(FALSE)
    })

    # Parse GeoJSON drawn feature into sf polygon, circle/oval polygon, or point marker
    parse_drawn_feature <- function(feature) {
      if (is.null(feature) || is.null(feature$geometry) || is.null(feature$geometry$coordinates)) {
        return(NULL)
      }

      type <- feature$geometry$type
      layer_type <- feature$properties$layerType
      coords_raw <- feature$geometry$coordinates

      # 1. Pin Marker Tool
      if (identical(type, "Point") || identical(layer_type, "marker")) {
        lng <- as.numeric(coords_raw[[1]])
        lat <- as.numeric(coords_raw[[2]])
        pt <- sf::st_sfc(sf::st_point(c(lng, lat)), crs = 4326)
        return(sf::st_sf(geometry = pt))
      }

      # 2. Rectangle Tool & Polygon Tool -> Retains exact drawn Rectangle / Polygon
      coords_poly <- coords_raw[[1]]
      if (is.null(coords_poly) || length(coords_poly) < 3) {
        return(NULL)
      }

      mat <- do.call(rbind, lapply(coords_poly, function(pt) c(as.numeric(pt[[1]]), as.numeric(pt[[2]]))))
      poly <- sf::st_sfc(sf::st_polygon(list(mat)), crs = 4326)
      return(sf::st_sf(geometry = poly))
    }

    # Observer for Drawn Features (Rubberband polygon, Circle, Rectangle, or Point marker)
    shiny::observeEvent(input$mapper_draw_new_feature, {
      is_drawing(FALSE)
      
      feature <- input$mapper_draw_new_feature
      poly_sf <- parse_drawn_feature(feature)
      
      proxy <- leaflet::leafletProxy("mapper", session = session)
      proxy |>
        leaflet::clearGroup("huc_polygons") |>
        leaflet::clearGroup("Hex Overlay") |>
        leaflet::clearGroup("Habitat Substrate Mesh")
      
      if (!is.null(poly_sf)) {
        drawn_polygon_sf(poly_sf)
        is_point <- inherits(sf::st_geometry(poly_sf), "sfc_POINT")
        
        msg <- if (is_point) {
          "<div style='color:purple;'><b>Point Selected:</b> Click <b>'Search Watersheds in Region'</b> to discover overlapping watershed.</div>"
        } else {
          "<div style='color:purple;'><b>Regional Boundary Outlined:</b> Adjust boundary on map if desired, then click <b>'Search Watersheds in Region'</b>.</div>"
        }
        status_msg(msg)
      }
    })

    shiny::observeEvent(input$mapper_draw_edited_features, {
      is_drawing(FALSE)
      features <- input$mapper_draw_edited_features$features
      if (!is.null(features) && length(features) > 0) {
        poly_sf <- parse_drawn_feature(features[[1]])
        if (!is.null(poly_sf)) {
          drawn_polygon_sf(poly_sf)
          status_msg("<div style='color:purple;'><b>Boundary Updated:</b> Click <b>'Search Watersheds in Region'</b> to discover watersheds.</div>")
        }
      }
    })

    shiny::observeEvent(input$mapper_draw_deleted_features, {
      is_drawing(FALSE)
      drawn_polygon_sf(NULL)
      huc_boundary(NULL)
      raw_fetched_hucs(NULL)
      all_hucs_sf(NULL)
      included_huc_ids(character(0))
      leaflet::leafletProxy("mapper", session = session) |>
        leaflet::clearGroup("Drawn Region") |>
        leaflet::clearGroup("huc_polygons") |>
        leaflet::clearGroup("Hex Overlay") |>
        leaflet::clearGroup("Habitat Substrate Mesh") |>
        leaflet::clearShapes() |>
        leaflet::clearMarkers() |>
        leaflet.extras::removeDrawToolbar(clearFeatures = TRUE) |>
        add_draw_toolbar()
      status_msg("<div style='color:gray;'>Drawn region cleared.</div>")
    })

    shiny::observeEvent(input$clear_region, {
      is_drawing(FALSE)
      drawn_polygon_sf(NULL)
      huc_boundary(NULL)
      raw_fetched_hucs(NULL)
      all_hucs_sf(NULL)
      included_huc_ids(character(0))
      leaflet::leafletProxy("mapper", session = session) |>
        leaflet::clearGroup("Drawn Region") |>
        leaflet::clearGroup("huc_polygons") |>
        leaflet::clearGroup("Hex Overlay") |>
        leaflet::clearGroup("Habitat Substrate Mesh") |>
        leaflet::clearShapes() |>
        leaflet::clearMarkers() |>
        leaflet.extras::removeDrawToolbar(clearFeatures = TRUE) |>
        add_draw_toolbar()
      status_msg("<div style='color:gray;'>Drawn region cleared.</div>")
    })

    # Trigger watershed discovery for drawn rubberband polygon region
    shiny::observeEvent(input$search_region, {
      poly <- drawn_polygon_sf()
      if (is.null(poly)) {
        return()
      }

      status_msg("<div style='color:blue;'><b>Processing:</b> Querying USGS for watersheds in region...</div>")
      shiny::withProgress(message = "Searching Regional Watersheds...", value = 0.5, {
        raw_hucs <- get_hucs_from_polygon(poly, huc_level = 12, max_hucs = 100)
        raw_fetched_hucs(raw_hucs)

        if (!is.null(raw_hucs) && nrow(raw_hucs) > 0) {
          raw_col <- get_huc_col(raw_hucs)
          actual_digits <- nchar(as.character(raw_hucs[[raw_col]][1]))
          if (!is.na(actual_digits) && actual_digits >= 2 && actual_digits <= 12) {
            base_huc_level(actual_digits)
            target_lvl <- get_huc_level()
            if (is.numeric(target_lvl) && target_lvl > actual_digits) {
              target_lvl <- actual_digits
            }
          }
        }

        hucs <- aggregate_hucs(raw_hucs, target_level = target_lvl)

        if (!is.null(hucs) && nrow(hucs) > 0) {
          huc_col <- get_huc_col(hucs)
          huc_type <- toupper(huc_col)
          huc_ids <- as.character(hucs[[huc_col]])
          huc_names <- if ("name" %in% names(hucs)) hucs$name else rep("", length(huc_ids))
          n_hucs <- length(huc_ids)

          # Cache all fetched HUC geometries and initialize all as included
          all_hucs_sf(hucs)
          included_huc_ids(huc_ids)
          render_huc_shapes(hucs, huc_ids)

          huc_str <- paste(paste0(huc_ids, " (", huc_names, ")"), collapse = ", ")
          status_msg(paste0("<div style='color:green;'><b>Identified ", n_hucs, " ", huc_type, " Watersheds in Region:</b><br/>", huc_str, "<br/><i>Click any polygon on map to toggle inclusion/exclusion.</i></div>"))

          huc_boundary(hucs)
        } else {
          raw_fetched_hucs(NULL)
          all_hucs_sf(NULL)
          included_huc_ids(character(0))
          status_msg("<div style='color:orange;'><b>Warning:</b> No USGS Watershed topology found in drawn region. Try adjusting boundary.</div>")
        }
      })
    })

    # Observer for HUC Level slider changes: re-aggregates cached base shapes in memory (0 API calls)
    # or fetches finer HUC layer if user switches from a broad cached level (e.g. HUC08) to a finer level (e.g. HUC12).
    shiny::observeEvent(get_huc_level(), {
      raw_hucs <- raw_fetched_hucs()
      if (is.null(raw_hucs) || nrow(raw_hucs) == 0) return()
      
      huc_col <- get_huc_col(raw_hucs)
      curr_digits <- nchar(as.character(raw_hucs[[huc_col]][1]))
      target_digits <- if (is.numeric(get_huc_level())) as.integer(get_huc_level()) else as.integer(gsub("[^0-9]", "", get_huc_level()))
      
      poly <- drawn_polygon_sf()
      
      # 0 API Calls when cached geometries are finer (HUC12 -> HUC08); API refetch only if user requests finer detail than cached (HUC08 -> HUC12)
      hucs <- if (!is.na(curr_digits) && !is.na(target_digits) && target_digits > curr_digits && !is.null(poly)) {
        shiny::withProgress(message = "Fetching Finer HUC Layer...", value = 0.5, {
          new_raw <- get_hucs_from_polygon(poly, huc_level = get_huc_level(), max_hucs = get_max_hucs())
          if (!is.null(new_raw) && nrow(new_raw) > 0) {
            raw_fetched_hucs(new_raw)
            new_raw
          } else {
            raw_hucs
          }
        })
      } else {
        aggregate_hucs(raw_hucs, target_level = get_huc_level())
      }

      if (!is.null(hucs) && nrow(hucs) > 0) {
        huc_col <- get_huc_col(hucs)
        huc_type <- toupper(huc_col)
        huc_ids <- as.character(hucs[[huc_col]])
        huc_names <- if ("name" %in% names(hucs)) hucs$name else rep("", length(huc_ids))
        n_hucs <- length(huc_ids)

        all_hucs_sf(hucs)
        included_huc_ids(huc_ids)
        render_huc_shapes(hucs, huc_ids)

        huc_str <- paste(paste0(huc_ids, " (", huc_names, ")"), collapse = ", ")
        status_msg(paste0("<div style='color:green;'><b>Identified ", n_hucs, " ", huc_type, " Watersheds in Region:</b><br/>", huc_str, "<br/><i>Click any polygon on map to toggle inclusion/exclusion.</i></div>"))

        huc_boundary(hucs)
      }
    }, ignoreInit = TRUE)

    # Observer for Single User Clicks (Point click reverse geocoding API calls disabled)
    # Map taps do not trigger network calls; users outline regions using the draw toolbar or search by HUC ID
    shiny::observeEvent(input$mapper_click, {
      # No-op: Map background taps do not trigger USGS API calls
      return()
    })

    # Return reactives and setters for parent Shiny modules (module composition)
    return(list(
      huc = huc_boundary,
      all_hucs = all_hucs_sf,
      included_ids = included_huc_ids,
      set_included_ids = update_included_ids,
      status = status_msg,
      click = shiny::reactive(input$mapper_click),
      drawn_polygon = drawn_polygon_sf,
      base_level = base_huc_level
    ))
  })
}

#' Run the Leaflet Mapping Integration App Tracker
#'
#' @export
#' @rdname leafletApp
leafletApp <- function() {
  ui <- shiny::fluidPage(
    shiny::titlePanel("Ewing Spatial Interaction Discovery"),
    shiny::sidebarLayout(
      shiny::sidebarPanel(
        leafletInput("mapper")
      ),
      shiny::mainPanel(
        leafletOutput("mapper")
      )
    )
  )
  server <- function(input, output, session) {
    leafletServer("mapper")
  }
  shiny::shinyApp(ui, server)
}

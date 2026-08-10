#' Interactive Leaflet Geographic Utilities
#'
#' Helper utilities for building interactive Leaflet base maps with search capabilities,
#' reverse-geocoding points to USGS HUC12 subwatershed boundaries, and rendering spatial
#' hexagonal grid overlays.
#'
#' @return `build_base_map`: A `leaflet` HTML widget object.
#' @export
#' @name leaflet
#' @rdname leaflet
#'
#' @importFrom leaflet leaflet addTiles setView
build_base_map <- function() {
  if (!requireNamespace("leaflet", quietly = TRUE) || !requireNamespace("leaflet.extras", quietly = TRUE)) {
    stop("Packages 'leaflet' and 'leaflet.extras' are required for building the interactive mapper.")
  }
  
  # Initialize the map centered near central North America
  map <- leaflet::leaflet() |>
    leaflet::addTiles(group = "OpenStreetMap")
  
  # Embed the OpenStreetMap search bar widget
  map <- leaflet.extras::addSearchOSM(
    map, 
    options = leaflet.extras::searchOptions(
      zoom = 12,
      autoCollapse = TRUE,
      hideMarkerOnCollapse = TRUE
    )
  )
  
  # Embed Leaflet draw toolbar for user-selected rubberband polygon or point region outlines
  map <- add_draw_toolbar(map)
  
  # Default view point (Center of US)
  map <- leaflet::setView(map, lng = -98.5795, lat = 39.8283, zoom = 4)
  
  return(map)
}

#' Add standard draw toolbar controls to a Leaflet map object
#'
#' @param map A Leaflet map object.
#' @return A Leaflet map object with draw toolbar attached.
#' @export
#' @rdname leaflet
add_draw_toolbar <- function(map) {
  leaflet.extras::addDrawToolbar(
    map,
    targetGroup = "Drawn Region",
    singleFeature = TRUE,
    polylineOptions = FALSE,
    circleOptions = FALSE,
    circleMarkerOptions = FALSE,
    markerOptions = leaflet.extras::drawMarkerOptions(),
    polygonOptions = leaflet.extras::drawPolygonOptions(
      shapeOptions = leaflet.extras::drawShapeOptions(
        color = "#000000",
        weight = 1.5,
        fillColor = "#333333",
        fillOpacity = 0
      )
    ),
    rectangleOptions = leaflet.extras::drawRectangleOptions(
      shapeOptions = leaflet.extras::drawShapeOptions(
        color = "#000000",
        weight = 1.5,
        fillColor = "#333333",
        fillOpacity = 0
      )
    ),
    editOptions = leaflet.extras::editToolbarOptions(
      selectedPathOptions = leaflet.extras::selectedPathOptions()
    )
  )
}

#' @param lng Numeric longitude coordinate
#' @param lat Numeric latitude coordinate
#'
#' @return `get_huc_from_point`: An `sf` polygon representation of the covering HUC12.
#' @export
#' @rdname leaflet
#'
#' @importFrom sf st_sfc st_point
#' @importFrom nhdplusTools get_huc
get_huc_from_point <- function(lng, lat) {
  if (is.null(lng) || is.null(lat)) {
    return(NULL)
  }
  
  # Convert physical math to rigorous Coordinate Reference System geometry
  pt <- sf::st_sfc(sf::st_point(c(lng, lat)), crs = 4326)
  
  res <- NULL
  tryCatch({
    # Automatically reverse-geocode the coordinate into the encompassing USGS HUC shape
    res <- suppressWarnings(nhdplusTools::get_huc(AOI = pt, type = "huc12"))
  }, error = function(e) {
    warning("Failed to locate USGS overlapping geometry at point coordinates: ", e$message)
  })
  
  return(res)
}

#' @param polygon_sf An `sf` or `sfc` polygon object representing a drawn rubberband region.
#' @param max_hucs Maximum number of subwatersheds before scaling up to broader HUC levels (default: 6, targeting 5-7 regions).
#'
#' @return `get_hucs_from_polygon`: An `sf` data frame of overlapping HUC subwatersheds (auto-scaled via code-annealed prefix matching).
#' @export
#' @rdname leaflet
#'
#' @importFrom sf st_transform st_crs st_make_valid
#' @importFrom nhdplusTools get_huc
get_hucs_from_polygon <- function(polygon_sf, max_hucs = 6) {
  if (is.null(polygon_sf)) return(NULL)
  
  res <- NULL
  tryCatch({
    # Ensure WGS84 CRS 4326 for NHD Plus tools query
    poly_4326 <- sf::st_transform(polygon_sf, 4326)
    poly_4326 <- suppressWarnings(sf::st_make_valid(poly_4326))
    
    # 1. Initial single spatial AOI query for fine-grained HUC12 subwatersheds
    res12 <- suppressWarnings(nhdplusTools::get_huc(AOI = poly_4326, type = "huc12"))
    
    if (is.null(res12) || nrow(res12) == 0) {
      return(NULL)
    }
    
    # If HUC12 polygon count is already within target max_hucs, return immediately
    if (nrow(res12) <= max_hucs) {
      return(res12)
    }
    
    # 2. Extract HUC12 string IDs for in-memory code-annealed prefix matching
    cols <- names(res12)
    huc_col <- NULL
    for (c in c("huc12", "huc10", "huc08", "huc8", "huc06", "huc6", "huc04", "huc4", "id")) {
      if (c %in% cols) { huc_col <- c; break }
    }
    if (is.null(huc_col)) huc_col <- cols[1]
    
    huc12_ids <- unname(as.character(res12[[huc_col]]))
    
    # Extract unique prefixes at each hierarchical level
    u10 <- unique(substr(huc12_ids, 1, 10))
    u08 <- unique(substr(huc12_ids, 1, 8))
    u06 <- unique(substr(huc12_ids, 1, 6))
    u04 <- unique(substr(huc12_ids, 1, 4))
    
    # Check HUC levels in hierarchical sequence (HUC10 -> HUC8 -> HUC6 -> HUC4)
    target_level <- NULL
    target_ids <- NULL
    
    if (length(u10) <= max_hucs) {
      target_level <- "huc10"
      target_ids <- u10
    } else if (length(u08) <= max_hucs) {
      target_level <- "huc08"
      target_ids <- u08
    } else if (length(u06) <= max_hucs) {
      target_level <- "huc06"
      target_ids <- u06
    } else if (length(u04) <= max_hucs) {
      target_level <- "huc04"
      target_ids <- u04
    } else {
      # If region is very large, pick the level with the smallest count to prevent dumping 100s of HUC12s
      counts <- c(huc04 = length(u04), huc06 = length(u06), huc08 = length(u08), huc10 = length(u10))
      best_lvl <- names(which.min(counts))
      target_level <- best_lvl
      target_ids <- switch(best_lvl, huc04 = u04, huc06 = u06, huc08 = u08, huc10 = u10)
    }
    
    # 3. Perform direct ID lookup for parent level geometries (0 spatial AOI trials)
    if (!is.null(target_level) && !is.null(target_ids)) {
      res_parent <- tryCatch(
        suppressWarnings(nhdplusTools::get_huc(id = target_ids, type = target_level)),
        error = function(e) NULL
      )
      if (!is.null(res_parent) && nrow(res_parent) > 0) {
        res <- res_parent
      } else {
        res <- res12
      }
    } else {
      res <- res12
    }
  }, error = function(e) {
    warning("Failed to locate USGS HUC geometries overlapping drawn polygon: ", e$message)
  })
  
  return(res)
}

#' @param map A `leaflet` map object or `leafletProxy` handle.
#' @param hex_obj A `watershed_hex_overlay` S3 object (or a list containing `layer` and `hex_overlay` sf objects).
#' @param hex_color Stroke color for hexagonal grid cells (default: "#C0392B").
#' @param bound_color Stroke color for watershed boundary (default: "#2980B9").
#'
#' @return `add_leaflet_hex_overlay`: Updated `leaflet` map object.
#' @export
#' @rdname leaflet
#'
#' @importFrom leaflet addPolygons clearShapes
#' @importFrom sf st_transform
add_leaflet_hex_overlay <- function(map, hex_obj, hex_color = "#7F8C8D", bound_color = "#2980B9") {
  if (is.null(hex_obj)) return(map)
  
  # Ensure geometries are transformed to WGS84 (EPSG 4326) for leaflet
  bound_sf <- if (!is.null(hex_obj$layer)) sf::st_transform(hex_obj$layer, 4326) else NULL
  hex_sf <- if (!is.null(hex_obj$hex_overlay)) sf::st_transform(hex_obj$hex_overlay, 4326) else NULL
  
  # 1. Add hex grid overlay FIRST (behind HUC boundaries)
  if (!is.null(hex_sf) && length(hex_sf) > 0) {
    if (any(c("POLYGON", "MULTIPOLYGON") %in% as.character(sf::st_geometry_type(hex_sf)))) {
      map <- map |>
        leaflet::addPolygons(
          data = hex_sf,
          color = hex_color,
          weight = 1,
          fillColor = hex_color,
          fillOpacity = 0,
          group = "Hex Overlay"
        )
    }
  }
  
  # 2. Render individual component HUC12 boundaries if multi-HUC
  if (is.data.frame(hex_obj$individual_hucs) && nrow(hex_obj$individual_hucs) > 1) {
    indiv_sf <- sf::st_transform(hex_obj$individual_hucs, 4326)
    if (any(c("POLYGON", "MULTIPOLYGON") %in% as.character(sf::st_geometry_type(indiv_sf)))) {
      map <- map |>
        leaflet::addPolygons(
          data = indiv_sf,
          color = "#8E44AD",
          weight = 1.5,
          dashArray = "4,4",
          fillColor = "#9B59B6",
          fillOpacity = 0,
          group = "Individual HUC12 Boundaries",
          popup = paste0("<b>HUC12:</b> ", indiv_sf$huc12, 
                         if ("name" %in% names(indiv_sf)) paste0("<br/><b>Name:</b> ", indiv_sf$name) else "")
        )
    }
  }
  
  # 3. Add watershed boundary polygon ON TOP (overall combined region)
  if (!is.null(bound_sf) && any(c("POLYGON", "MULTIPOLYGON") %in% as.character(sf::st_geometry_type(bound_sf)))) {
    huc_popup <- if (length(hex_obj$huc_id) > 1) {
      paste0("<b>Combined Watershed Region (", length(hex_obj$huc_id), " HUC12s):</b><br/>",
             paste(hex_obj$huc_id, collapse = ", "))
    } else {
      paste0("<b>HUC12:</b> ", hex_obj$huc_id, 
             if (!is.null(hex_obj$feature_name) && hex_obj$feature_name != "") 
               paste0("<br/><b>Feature:</b> ", hex_obj$feature_name) else "")
    }
    
    map <- map |>
      leaflet::addPolygons(
        data = bound_sf,
        color = bound_color,
        weight = 2.5,
        fillColor = "#3498DB",
        fillOpacity = 0,
        group = "Watershed Boundary",
        popup = huc_popup
      )
  }
  
  return(map)
}

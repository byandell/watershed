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
  
  # Initialize the map centered near central North America with multi-layer basemap options
  map <- leaflet::leaflet() |>
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron, group = "CartoDB Positron") |>
    add_usgs_shaded_relief_layer(group = "USGS Shaded Relief (DEM)") |>
    add_usgs_topo_layer(group = "USGS Topo") |>
    leaflet::addProviderTiles(leaflet::providers$OpenStreetMap, group = "OpenStreetMap") |>
    leaflet::addProviderTiles(leaflet::providers$Esri.WorldImagery, group = "Satellite Imagery") |>
    add_usgs_hydro_layer(group = "USGS Hydrography (Streams)") |>
    leaflet::addLayersControl(
      baseGroups = c("CartoDB Positron", "USGS Shaded Relief (DEM)", "USGS Topo", "OpenStreetMap", "Satellite Imagery"),
      overlayGroups = c("USGS Hydrography (Streams)", "Drawn Region", "huc_polygons", "Stream Flowlines", "StreamStats Basin", "Hex Overlay", "Habitat Overlay", "Landmarks"),
      options = leaflet::layersControlOptions(collapsed = TRUE)
    )
  
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

#' Aggregate Fine HUC Polygons to Parent HUC Level
#'
#' Combines fine HUC polygons (e.g. HUC12s) into broader HUC levels (HUC10, HUC08, HUC06, HUC04, HUC02)
#' by prefix matching and spatial union without requiring additional spatial network requests.
#'
#' @param hucs_sf An `sf` data frame of fine HUC polygon geometries.
#' @param target_level Target HUC digit level (2-12, numeric or character, default: 8).
#'
#' @return `aggregate_hucs`: An `sf` data frame of aggregated parent HUC geometries.
#' @export
#' @rdname leaflet
#'
#' @importFrom sf st_union st_sfc st_sf st_crs st_make_valid st_geometry
aggregate_hucs <- function(hucs_sf, target_level = 8) {
  if (is.null(hucs_sf) || nrow(hucs_sf) == 0) return(NULL)
  
  target_digits <- if (is.numeric(target_level)) {
    as.integer(target_level)
  } else if (is.character(target_level)) {
    digits <- as.integer(gsub("[^0-9]", "", target_level))
    if (is.na(digits)) 8 else digits
  } else {
    8
  }
  target_type <- sprintf("huc%02d", target_digits)
  
  cols <- names(hucs_sf)
  huc_col <- NULL
  for (c in c("huc16", "huc14", "huc12", "huc10", "huc08", "huc8", "huc06", "huc6", "huc04", "huc4", "huc02", "huc2", "id")) {
    if (c %in% cols) { huc_col <- c; break }
  }
  if (is.null(huc_col)) huc_col <- cols[1]
  
  ids <- as.character(hucs_sf[[huc_col]])
  curr_digits <- nchar(ids[1])
  
  if (is.na(curr_digits) || curr_digits == target_digits) return(hucs_sf)
  
  if (curr_digits > target_digits) {
    prefixes <- unname(substr(ids, 1, target_digits))
    u_prefixes <- unique(prefixes)
    
    # 0-API-Call Pure In-Memory Spatial Union Aggregation
    poly_geom <- sf::st_geometry(hucs_sf)
    sfg_list <- lapply(u_prefixes, function(p) {
      sub_geom <- poly_geom[prefixes == p]
      union_res <- suppressWarnings(sf::st_union(sf::st_make_valid(sub_geom)))
      if (inherits(union_res, "sfc")) union_res[[1]] else union_res
    })
    agg_geom <- sf::st_sfc(sfg_list, crs = sf::st_crs(hucs_sf))
    
    res_sf <- sf::st_sf(geometry = agg_geom)
    res_sf[[target_type]] <- u_prefixes
    
    if ("name" %in% names(hucs_sf)) {
      names_by_prefix <- tapply(hucs_sf$name, prefixes, function(nms) paste(unique(nms[nms != ""]), collapse = ", "))
      res_sf$name <- unname(names_by_prefix[u_prefixes])
    }
    return(res_sf)
  }
  
  return(hucs_sf)
}

#' @param polygon_sf An `sf` or `sfc` polygon or point object representing a drawn rubberband region or marker.
#' @param huc_level Target USGS HUC digit level (2, 4, 6, 8, 10, 12, or character e.g. "huc08"). Single-digit numbers are padded ("huc02", "huc04", "huc06", "huc08").
#' @param max_hucs Maximum number of subwatersheds before scaling up to broader HUC levels (default: 6, targeting 5-7 regions).
#'
#' @return `get_hucs_from_polygon`: An `sf` data frame of overlapping HUC subwatersheds (auto-scaled via area & code-annealed prefix matching).
#' @export
#' @rdname leaflet
#'
#' @importFrom sf st_transform st_crs st_make_valid st_area st_bbox
#' @importFrom nhdplusTools get_huc
get_hucs_from_polygon <- function(polygon_sf, huc_level = 8, max_hucs = 6) {
  if (is.null(polygon_sf)) return(NULL)
  
  res <- NULL
  tryCatch({
    target_digits <- if (is.numeric(huc_level)) {
      as.integer(huc_level)
    } else if (is.character(huc_level)) {
      digits <- as.integer(gsub("[^0-9]", "", huc_level))
      if (is.na(digits)) 8 else digits
    } else {
      8
    }

    # Clamp target digits to 12 since USGS NHDPlus REST services index up to huc12
    query_digits <- min(target_digits, 12)
    target_type <- sprintf("huc%02d", query_digits)

    # Ensure WGS84 CRS 4326 for NHD Plus tools query
    poly_4326 <- sf::st_transform(polygon_sf, 4326)
    poly_4326 <- suppressWarnings(sf::st_make_valid(poly_4326))
    
    geom_type <- as.character(sf::st_geometry_type(poly_4326))
    is_point <- any(c("POINT", "MULTIPOINT") %in% geom_type)

    # Area-Based Starting HUC Query Scaling (applies to polygons/rectangles; points default to finest requested level)
    start_type <- if (is_point) {
      target_type
    } else {
      area_km2 <- tryCatch({
        poly_proj <- suppressWarnings(sf::st_transform(poly_4326, 5070))
        as.numeric(sum(sf::st_area(poly_proj))) / 1e6
      }, error = function(e) {
        bbox <- sf::st_bbox(poly_4326)
        dx <- abs(as.numeric(bbox["xmax"] - bbox["xmin"])) * 111 * cos(mean(c(as.numeric(bbox["ymin"]), as.numeric(bbox["ymax"]))) * pi / 180)
        dy <- abs(as.numeric(bbox["ymax"] - bbox["ymin"])) * 111
        as.numeric(dx * dy)
      })

      # Determine safe starting level from polygon area
      area_level_digits <- if (area_km2 > 200000) {
        4
      } else if (area_km2 > 50000) {
        6
      } else if (area_km2 > 10000) {
        8
      } else if (area_km2 > 1000) {
        10
      } else {
        12
      }

      # Pick the broader level (smaller digit count) between user target and area-scaled recommendation to prevent REST timeouts
      start_digits <- min(query_digits, area_level_digits)
      sprintf("huc%02d", start_digits)
    }

    # 1. Primary spatial AOI query at the scaled initial HUC level
    res_initial <- tryCatch(
      suppressWarnings(nhdplusTools::get_huc(AOI = poly_4326, type = start_type)),
      error = function(e) NULL
    )

    # Fallback to huc12 if requested fine level returns empty from USGS REST layer
    if ((is.null(res_initial) || nrow(res_initial) == 0) && start_type != "huc12") {
      res_initial <- suppressWarnings(nhdplusTools::get_huc(AOI = poly_4326, type = "huc12"))
    }

    res <- res_initial
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
add_leaflet_hex_overlay <- function(map, hex_obj, hex_color = "#7F8C8D", bound_color = "#8E44AD") {
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
  
  # 2. Render individual component HUC boundaries if multi-HUC
  if (is.data.frame(hex_obj$individual_hucs) && nrow(hex_obj$individual_hucs) > 1) {
    indiv_sf <- sf::st_transform(hex_obj$individual_hucs, 4326)
    if (any(c("POLYGON", "MULTIPOLYGON") %in% as.character(sf::st_geometry_type(indiv_sf)))) {
      cols <- names(indiv_sf)
      huc_col <- NULL
      for (c in c("huc16", "huc14", "huc12", "huc10", "huc08", "huc8", "huc06", "huc6", "huc04", "huc4", "huc02", "huc2", "id")) {
        if (c %in% cols) { huc_col <- c; break }
      }
      if (is.null(huc_col)) huc_col <- cols[1]

      map <- map |>
        leaflet::addPolygons(
          data = indiv_sf,
          color = bound_color,
          weight = 2,
          fillColor = bound_color,
          fillOpacity = 0,
          group = "Individual HUC Boundaries",
          popup = paste0("<b>HUC:</b> ", indiv_sf[[huc_col]], 
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
        weight = 2,
        fillColor = bound_color,
        fillOpacity = 0,
        group = "Watershed Boundary",
        popup = huc_popup
      )
  }
  
  return(map)
}

#' Add NHD Stream Flowlines Overlay to Leaflet Map
#'
#' @param map A `leaflet` map object or `leafletProxy` handle.
#' @param flowlines An `sf` data frame containing LINESTRING geometries of stream flowlines.
#' @param stream_color Stroke color for flowlines (default: "#0055ff").
#' @param group Group name for layer controls (default: "Stream Flowlines").
#' @return Updated `leaflet` map object.
#' @export
#' @rdname leaflet
add_leaflet_flowlines <- function(map, flowlines, stream_color = "#0055ff", group = "Stream Flowlines") {
  if (is.null(flowlines) || !inherits(flowlines, "sf") || nrow(flowlines) == 0) return(map)
  
  geom_types <- as.character(sf::st_geometry_type(flowlines))
  if (!any(c("LINESTRING", "MULTILINESTRING") %in% geom_types)) return(map)
  
  flowlines_4326 <- sf::st_transform(flowlines, 4326)
  
  line_weights <- if ("streamorde" %in% names(flowlines_4326)) {
    pmax(as.numeric(flowlines_4326$streamorde) * 1.2, 2)
  } else {
    2.5
  }
  
  stream_names <- if ("gnis_name" %in% names(flowlines_4326)) {
    ifelse(is.na(flowlines_4326$gnis_name) | flowlines_4326$gnis_name == " ", "Unnamed Stream / Flowline", flowlines_4326$gnis_name)
  } else {
    rep("Stream / Flowline", nrow(flowlines_4326))
  }
  
  orders <- if ("streamorde" %in% names(flowlines_4326)) flowlines_4326$streamorde else rep(1, nrow(flowlines_4326))
  lengths <- if ("lengthkm" %in% names(flowlines_4326)) sprintf("%.2f km", flowlines_4326$lengthkm) else ""
  
  popups <- sprintf("<b>Stream:</b> %s<br/><b>Stream Order:</b> %s<br/><b>Length:</b> %s", stream_names, orders, lengths)
  
  map |>
    leaflet::addPolylines(
      data = flowlines_4326,
      color = stream_color,
      weight = line_weights,
      opacity = 0.9,
      popup = popups,
      group = group
    )
}

#' Add Dynamic Hydrology & Watershed Legend to Leaflet
#'
#' @param map A `leaflet` map object or `leafletProxy` handle.
#' @param show_hex Logical. Include hex grid in legend.
#' @param show_streams Logical. Include stream flowlines in legend.
#' @param show_habitat Logical. Include habitat/landmarks in legend.
#' @param show_legend Logical. Whether to show or remove legend.
#' @param position Position on map (default: "bottomright").
#' @return Updated `leaflet` map object.
#' @export
#' @rdname leaflet
add_watershed_legend <- function(map,
                                 show_hex = TRUE,
                                 show_streams = TRUE,
                                 show_habitat = TRUE,
                                 show_legend = TRUE,
                                 position = "bottomright") {
  if (!isTRUE(show_legend)) {
    return(leaflet::removeControl(map, "watershed_legend"))
  }
  
  colors <- c("#8E44AD", "#0055ff", "#27AE60", "#7F8C8D")
  labels <- c("Selected HUC Boundary", "Stream Flowlines (NHD)", "Habitat / Landmarks", "Hex Mesh Cells")
  active <- c(TRUE, isTRUE(show_streams), isTRUE(show_habitat), isTRUE(show_hex))
  
  map |>
    leaflet::removeControl("watershed_legend") |>
    leaflet::addLegend(
      position = position,
      colors = colors[active],
      labels = labels[active],
      title = "Watershed Layers",
      opacity = 0.85,
      layerId = "watershed_legend"
    )
}


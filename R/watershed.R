#' Watershed Boundary & Hexagonal Substrate Utilities
#'
#' Retrieves watershed boundary dataset (WBD) geometry for HUC12 identifiers,
#' applies OpenStreetMap feature clipping, generates hexagonal substrate grid overlays,
#' and discovers named geographical features within subwatersheds.
#'
#' @param huc_id A character string representing the HUC12 identifier.
#' @param feature_name An optional character string specifying a geographic feature to restrict the watershed (via `osmdata`).
#' @param huc_layer An optional pre-fetched SF object boundary to intercept identical querying sequences dynamically.
#'
#' @return `get_watershed`: A list containing the `huc_id`, `feature_name`, `lon` and `lat` of the centroid, and `sf` `layer`.
#' @export
#' @name watershed
#' @rdname watershed
#'
#' @importFrom nhdplusTools get_huc
#' @importFrom sf st_transform st_crs st_intersection st_union st_centroid st_geometry st_coordinates
get_watershed <- function(huc_id, feature_name = NULL, huc_layer = NULL) {
  # Standardize huc_id input (support comma-separated string or character vector)
  if (is.character(huc_id) && length(huc_id) == 1 && grepl(",", huc_id)) {
    huc_id <- trimws(unlist(strsplit(huc_id, ",")))
  }
  
  # Get HUC12 sf object (queries USGS WBD if layer not provided or if layer is not a polygon geometry)
  if (!is.null(huc_layer)) {
    geom_types <- as.character(sf::st_geometry_type(huc_layer))
    if (!any(c("POLYGON", "MULTIPOLYGON") %in% geom_types)) {
      huc_layer <- NULL
    }
  }
  
  if (is.null(huc_layer)) {
    n_digits <- nchar(huc_id[1])
    huc_type <- sprintf("huc%02d", n_digits)
    huc_layer <- suppressMessages(suppressWarnings(nhdplusTools::get_huc(id = huc_id, type = huc_type)))
  }
  
  if (is.null(huc_layer) || nrow(huc_layer) == 0) {
    stop("Invalid HUC ID or could not retrieve watershed data from USGS.")
  }
  
  # Track individual component HUCs if multi-HUC
  individual_hucs <- huc_layer
  cols <- names(huc_layer)
  huc_col <- NULL
  for (c in c("huc16", "huc14", "huc12", "huc10", "huc08", "huc8", "huc06", "huc6", "huc04", "huc4", "huc02", "huc2", "id")) {
    if (c %in% cols) { huc_col <- c; break }
  }
  actual_huc_ids <- if (!is.null(huc_col)) unique(huc_layer[[huc_col]]) else huc_id
  
  if (!is.null(feature_name)) {
    if (!requireNamespace("osmdata", quietly = TRUE)) {
      stop("The 'osmdata' package is required to filter geographic features by name. Install it using install.packages('osmdata')")
    }
    
    # Try querying OpenStreetMap nominatim for the geographic feature boundary
    feature_geom <- tryCatch({
      osmdata::getbb(feature_name, format_out = "sf_polygon", limit = 1)
    }, error = function(e) {
      warning(paste("osmdata could not find a valid polygon for feature:", feature_name, "- Generating whole HUC region instead."))
      return(NULL)
    })
    
    if (!is.null(feature_geom)) {
      # Formats may vary (list containing polygon/multipolygon, or an sf object directly)
      feature_sf <- NULL
      if (inherits(feature_geom, "sf") || inherits(feature_geom, "sfc")) {
        feature_sf <- feature_geom
      } else if (is.list(feature_geom)) {
        if (!is.null(feature_geom$multipolygon)) {
          feature_sf <- feature_geom$multipolygon
        } else if (!is.null(feature_geom$polygon)) {
          feature_sf <- feature_geom$polygon
        } else if (length(feature_geom) > 0) {
          feature_sf <- feature_geom[[1]]
        }
      } 
      
      if (!is.null(feature_sf)) {
        geom_types <- as.character(sf::st_geometry_type(feature_sf))
        if (any(c("POLYGON", "MULTIPOLYGON") %in% geom_types)) {
          # Project to HUC's CRS and spatially intersect to restrict bounds
          feature_sf <- sf::st_transform(feature_sf, sf::st_crs(huc_layer))
          clipped_layer <- suppressWarnings(sf::st_intersection(huc_layer, feature_sf))
          
          # If intersection yields valid polygon geometries, use it; otherwise fallback to full HUC
          if (!is.null(clipped_layer) && nrow(clipped_layer) > 0) {
            clipped_types <- as.character(sf::st_geometry_type(clipped_layer))
            if (any(c("POLYGON", "MULTIPOLYGON") %in% clipped_types)) {
              huc_layer <- clipped_layer
            } else {
              warning(paste("Feature", feature_name, "does not yield a polygon intersection - Generating whole HUC region instead."))
            }
          } else {
            warning(paste("Feature", feature_name, "does not overlap with specified HUC region - Generating whole HUC region instead."))
          }
        } else {
          warning(paste("osmdata could not extract a valid polygon for feature:", feature_name, "- Generating whole HUC region instead."))
        }
      }
    }
  }
  
  # Aggregate multiple HUC12 polygons into a single combined region geometry via sf::st_union
  unified_layer <- if (nrow(huc_layer) > 1) {
    suppressWarnings(sf::st_union(huc_layer))
  } else {
    huc_layer
  }
  
  # Calculate geographic centroid of the final geometry
  centroid <- suppressWarnings(sf::st_centroid(sf::st_geometry(unified_layer)))
  coords <- sf::st_coordinates(centroid)
  
  list(
    huc_id = actual_huc_ids,
    feature_name = feature_name,
    lon = as.numeric(coords[1, "X"]),
    lat = as.numeric(coords[1, "Y"]),
    individual_hucs = individual_hucs,
    layer = unified_layer
  )
}

safe_st_intersects <- function(x, y) {
  tryCatch(
    suppressWarnings(sf::st_intersects(x, y)),
    error = function(e) {
      old_s2 <- suppressMessages(sf::sf_use_s2(FALSE))
      on.exit(suppressMessages(sf::sf_use_s2(old_s2)), add = TRUE)
      x_val <- tryCatch(sf::st_make_valid(x), error = function(e2) x)
      y_val <- tryCatch(sf::st_make_valid(y), error = function(e2) y)
      suppressWarnings(sf::st_intersects(x_val, y_val))
    }
  )
}

#' Construct Spatial Substrate Hexagonal Overlay
#'
#' Projects a mathematical hexagonal substrate grid overlay across an extracted watershed boundary.
#'
#' @param huc_info Watershed object returned from `get_watershed()`.
#' @param hex_diameter Diameter of hexagonal grid cells in degrees (default = `0.01`).
#'
#' @return `add_watershed_hex_overlay`: An S3 object of class `watershed_hex_overlay` containing the original geometry plus the hex layer.
#' @export
#' @rdname watershed
#'
#' @importFrom sf st_make_grid st_intersects
add_watershed_hex_overlay <- function(huc_info, hex_diameter = 0.01) {
  huc_layer <- huc_info$layer
  
  # Use sf::st_make_grid with square = FALSE to mathematically build a spatial hex mesh atop the bounding box
  hex_mesh <- sf::st_make_grid(huc_layer, square = FALSE, cellsize = c(hex_diameter, hex_diameter))
  
  # Filter the generated mesh to only retain hexagons crossing the actual geographical feature
  # (lengths > 0 signifies the hexagon touches the island geometry)
  hex_overlay <- hex_mesh[lengths(safe_st_intersects(hex_mesh, huc_layer)) > 0]
  
  huc_info$hex_overlay <- hex_overlay
  huc_info$hex_diameter <- hex_diameter
  
  class(huc_info) <- "watershed_hex_overlay"
  return(huc_info)
}

#' @param object An S3 object of class `watershed_hex_overlay`.
#' @param ... Additional arguments passed to plotting functions.
#'
#' @return `autoplot.watershed_hex_overlay`: A `ggplot` object representing the spatial mesh.
#' @exportS3Method ggplot2::autoplot
#' @rdname watershed
#'
#' @importFrom ggplot2 autoplot ggplot geom_sf theme_minimal ggtitle labs
autoplot.watershed_hex_overlay <- function(object, ...) {
  huc_digits <- if (length(object$huc_id) > 0) sprintf("%02d", nchar(object$huc_id[1])) else "12"
  huc_str <- if (length(object$huc_id) > 1) {
    paste0(length(object$huc_id), " Combined HUC", huc_digits, "s")
  } else {
    paste0("HUC", huc_digits, ": ", object$huc_id)
  }
  
  title_txt <- paste("Geographic Hexagonal Grid (", huc_str, ")", 
                     "\nHexagon Extent Diameter:", object$hex_diameter)
  if (!is.null(object$feature_name) && object$feature_name != "") {
    title_txt <- paste0(title_txt, " - Restricted to: ", object$feature_name)
  }
  
  p <- ggplot2::ggplot()
  
  # 1. Overlay spatial hex grid FIRST (behind HUC boundaries) in gray
  if (!is.null(object$hex_overlay) && length(object$hex_overlay) > 0) {
    p <- p + ggplot2::geom_sf(data = object$hex_overlay, fill = NA, color = "#7F8C8D", linewidth = 0.5)
  }
  
  # 2. Overlay vector stream flowlines if present
  if (!is.null(object$flowlines) && inherits(object$flowlines, "sf") && nrow(object$flowlines) > 0) {
    p <- p + ggplot2::geom_sf(data = object$flowlines, color = "#0055ff", linewidth = 0.6, alpha = 0.8)
  }
  
  # 3. Display individual component HUC boundaries if multi-HUC
  if (!is.null(object$individual_hucs) && nrow(object$individual_hucs) > 1) {
    p <- p + ggplot2::geom_sf(data = object$individual_hucs, fill = NA, color = "purple", linetype = "dashed", linewidth = 0.4)
  }
  
  # 4. Combined watershed boundary ON TOP
  p <- p + ggplot2::geom_sf(data = object$layer, fill = NA, color = "blue", linewidth = 0.8)
  
  p +
    ggplot2::theme_minimal() +
    ggplot2::ggtitle(title_txt) +
    ggplot2::labs(x = "Longitude", y = "Latitude")
}

#' @param feature_types A character vector of OSM keys to query (default: c("natural", "waterway", "leisure")).
#'
#' @return `discover_watershed_features`: A character vector of unique feature names found physically within the watershed bounds.
#' @export
#' @rdname watershed
#'
#' @importFrom nhdplusTools get_huc
#' @importFrom sf st_bbox st_transform st_crs st_intersects st_make_valid sf_use_s2
discover_watershed_features <- function(huc_id, feature_types = c("natural", "waterway", "leisure")) {
  # Get HUC12 sf object to establish the tight bounding limit
  huc_layer <- suppressMessages(suppressWarnings(nhdplusTools::get_huc(id = huc_id, type = "huc12")))
  
  if (is.null(huc_layer) || nrow(huc_layer) == 0) {
    stop("Invalid HUC12 ID or could not retrieve watershed data from USGS.")
  }
  
  if (!requireNamespace("osmdata", quietly = TRUE)) {
    stop("The 'osmdata' package is required to execute dynamic feature discovery. Install it using install.packages('osmdata')")
  }
  
  # Map coordinates to WGS84 for the public Overpass API interface
  bbox <- sf::st_bbox(sf::st_transform(huc_layer, 4326))
  bbox_str <- paste(bbox["ymin"], bbox["xmin"], bbox["ymax"], bbox["xmax"], sep = ",")
  
  # Construct raw Overpass QL to execute a UNION (OR) query natively
  ql_union_body <- paste(
    sapply(feature_types, function(key) {
      paste0(
        "  node[\"", key, "\"](", bbox_str, ");\n",
        "  way[\"", key, "\"](", bbox_str, ");\n",
        "  relation[\"", key, "\"](", bbox_str, ");\n"
      )
    }), collapse = ""
  )
  
  ql_query <- paste0(
    "[out:xml][timeout:60];\n(\n",
    ql_union_body,
    ");\n",
    "out body;\n>;\nout skel qt;\n"
  )
  
  discovered_names <- c()
  
  # Temporarily reroute to the lz4 alternative Overpass Mirror to dodge IP bans on main branch
  old_url <- osmdata::get_overpass_url()
  osmdata::set_overpass_url("https://lz4.overpass-api.de/api/interpreter")
  
  tryCatch({
    # Temporarily disable standard S2 spherical tracking to bypass OSM topological boundary crashes 
    old_s2 <- suppressMessages(sf::sf_use_s2())
    suppressMessages(sf::sf_use_s2(FALSE))
    
    # Send the raw, unified union query into the osmdata parser
    osm_res <- osmdata::osmdata_sf(ql_query)
    
    # Extract polygons (Lakes, Parks)
    if (!is.null(osm_res$osm_polygons) && "name" %in% colnames(osm_res$osm_polygons)) {
      poly_sf <- osm_res$osm_polygons[!is.na(osm_res$osm_polygons$name), ]
      if (nrow(poly_sf) > 0) {
        poly_sf <- sf::st_transform(poly_sf, sf::st_crs(huc_layer))
        poly_sf <- suppressWarnings(sf::st_make_valid(poly_sf))
        inter <- suppressWarnings(lengths(sf::st_intersects(poly_sf, huc_layer))) > 0
        discovered_names <- c(discovered_names, poly_sf$name[inter])
      }
    }
    
    # Extract multipolygons (Great Lakes, large reserves)
    if (!is.null(osm_res$osm_multipolygons) && "name" %in% colnames(osm_res$osm_multipolygons)) {
      mpoly_sf <- osm_res$osm_multipolygons[!is.na(osm_res$osm_multipolygons$name), ]
      if (nrow(mpoly_sf) > 0) {
        mpoly_sf <- sf::st_transform(mpoly_sf, sf::st_crs(huc_layer))
        mpoly_sf <- suppressWarnings(sf::st_make_valid(mpoly_sf))
        inter <- suppressWarnings(lengths(sf::st_intersects(mpoly_sf, huc_layer))) > 0
        discovered_names <- c(discovered_names, mpoly_sf$name[inter])
      }
    }
    
    # Extract linestrings (Dams, Rivers)
    if (!is.null(osm_res$osm_lines) && "name" %in% colnames(osm_res$osm_lines)) {
      line_sf <- osm_res$osm_lines[!is.na(osm_res$osm_lines$name), ]
      if (nrow(line_sf) > 0) {
        line_sf <- sf::st_transform(line_sf, sf::st_crs(huc_layer))
        line_sf <- suppressWarnings(sf::st_make_valid(line_sf))
        inter <- suppressWarnings(lengths(sf::st_intersects(line_sf, huc_layer))) > 0
        discovered_names <- c(discovered_names, line_sf$name[inter])
      }
    }
    
    # Reset standard mapping state
    suppressMessages(sf::sf_use_s2(old_s2))
    
  }, error = function(e) {
    if (exists("old_s2")) suppressMessages(sf::sf_use_s2(old_s2))
    warning(paste("Raw OSM Extraction timeout or failure:", e$message))
  })
  
  # Return sanitized unique list 
  clean_names <- unique(discovered_names)
  clean_names <- sort(clean_names[!is.na(clean_names) & trimws(clean_names) != ""])
  
  # Reset the API routing mirror
  osmdata::set_overpass_url(old_url)
  
  return(clean_names)
}

.watershed_flowline_cache <- new.env(parent = emptyenv())

#' Extract NHD Stream Flowlines for a Watershed
#'
#' Queries the USGS National Hydrography Dataset (NHD) via `nhdplusTools` for stream
#' flowlines intersecting a watershed boundary or geographic area. Results are cached in
#' memory to eliminate redundant network queries.
#'
#' @param watershed_obj A `watershed` S3 object or an `sf` polygon object.
#' @param min_stream_order Minimum Strahler stream order to include (default: 1).
#' @param extent Character string specifying extent mode: \code{"huc"} (default, strictly constrained
#'   to HUC boundary), \code{"bbox"} (bounding box area of watershed), or \code{"buffer"} (buffered region around HUC).
#' @param buffer_km Buffer distance in kilometers when \code{extent = "buffer"} (default: 5).
#' @return An `sf` data frame of stream flowlines, or `NULL` if none found.
#' @export
#' @rdname watershed
#'
#' @importFrom nhdplusTools get_nhdplus
#' @importFrom sf st_transform st_union st_as_sfc st_bbox st_buffer st_intersects sf_use_s2
get_watershed_flowlines <- function(watershed_obj,
                                    min_stream_order = 1,
                                    extent = c("huc", "bbox", "buffer"),
                                    buffer_km = 5) {
  extent <- match.arg(extent)
  aoi <- if (inherits(watershed_obj, "sf") || inherits(watershed_obj, "sfc")) {
    watershed_obj
  } else if (!is.null(watershed_obj$layer)) {
    watershed_obj$layer
  } else {
    NULL
  }
  
  if (is.null(aoi) || nrow(aoi) == 0) return(NULL)
  
  aoi_4326 <- sf::st_transform(aoi, 4326)
  buf_dist <- if (!is.null(buffer_km) && is.numeric(buffer_km)) buffer_km else 5

  # Compute total combined bounding box area across all selected HUCs
  bb_all <- sf::st_bbox(aoi_4326)
  dx_all <- max(as.numeric(bb_all["xmax"] - bb_all["xmin"]), 0.01)
  dy_all <- max(as.numeric(bb_all["ymax"] - bb_all["ymin"]), 0.01)
  total_area_deg2 <- dx_all * dy_all

  # Adapt base minimum stream order based on the combined regional bounding box size
  area_min_order <- if (total_area_deg2 > 1.5) {
    5
  } else if (total_area_deg2 > 0.5) {
    4
  } else if (total_area_deg2 > 0.15) {
    3
  } else if (total_area_deg2 > 0.03) {
    2
  } else {
    1
  }

  effective_min_order <- if (is.numeric(min_stream_order)) {
    as.integer(min_stream_order)
  } else {
    area_min_order
  }
  query_order <- if (effective_min_order > 1) effective_min_order else NULL

  # Determine if input sf contains identifiable HUC IDs for granular per-HUC caching
  huc_col <- NULL
  if (inherits(aoi_4326, "sf") || inherits(aoi_4326, "data.frame")) {
    for (c in c("huc16", "huc14", "huc12", "huc10", "huc08", "huc8", "huc06", "huc6", "huc04", "huc4", "huc02", "huc2", "id")) {
      if (c %in% names(aoi_4326)) {
        huc_col <- c
        break
      }
    }
  }

  # --- Branch A: Granular Per-HUC Caching with Single-Batch Unified Querying ---
  if (!is.null(huc_col) && nrow(aoi_4326) > 0) {
    huc_ids <- as.character(aoi_4326[[huc_col]])
    
    cached_list <- list()
    missing_hucs <- character(0)
    
    for (i in seq_along(huc_ids)) {
      hid <- huc_ids[i]
      h_key <- sprintf("huc_%s_ext_%s_buf_%s_ord_%s", hid, extent, ifelse(extent == "buffer", as.character(buf_dist), "0"), ifelse(is.null(query_order), "1", as.character(query_order)))
      
      found_cache <- NULL
      if (exists(h_key, envir = .watershed_flowline_cache, inherits = FALSE)) {
        found_cache <- get(h_key, envir = .watershed_flowline_cache, inherits = FALSE)
      } else {
        h_base_key <- sprintf("huc_%s_ext_%s_buf_%s_ord_1", hid, extent, ifelse(extent == "buffer", as.character(buf_dist), "0"))
        if (exists(h_base_key, envir = .watershed_flowline_cache, inherits = FALSE)) {
          found_cache <- get(h_base_key, envir = .watershed_flowline_cache, inherits = FALSE)
        }
      }
      
      if (!is.null(found_cache) && inherits(found_cache, "sf") && nrow(found_cache) > 0) {
        cached_list[[hid]] <- found_cache
      } else {
        missing_hucs <- c(missing_hucs, hid)
      }
    }
    
    # Query USGS for missing HUCs: use tight individual bboxes for macro areas (> 2 deg^2) to prevent giant server-side delays
    if (length(missing_hucs) > 0) {
      missing_mask <- aoi_4326[[huc_col]] %in% missing_hucs
      missing_sf <- aoi_4326[missing_mask, ]
      
      bb_missing <- sf::st_bbox(missing_sf)
      dx_m <- max(as.numeric(bb_missing["xmax"] - bb_missing["xmin"]), 0.01)
      dy_m <- max(as.numeric(bb_missing["ymax"] - bb_missing["ymin"]), 0.01)
      area_missing_deg2 <- dx_m * dy_m
      
      old_s2 <- suppressMessages(sf::sf_use_s2(FALSE))
      
      if (nrow(missing_sf) == 1 || area_missing_deg2 <= 2.0) {
        q_missing_aoi <- if (extent == "bbox" || extent == "huc") {
          sf::st_as_sfc(sf::st_bbox(missing_sf))
        } else if (extent == "buffer") {
          missing_union <- suppressWarnings(sf::st_union(missing_sf))
          suppressWarnings(sf::st_transform(sf::st_buffer(sf::st_transform(missing_union, 5070), buf_dist * 1000), 4326))
        } else {
          missing_sf
        }
        
        q_envelope <- sf::st_as_sfc(sf::st_bbox(q_missing_aoi))
        
        fl_batch <- tryCatch({
          nhdplusTools::get_nhdplus(AOI = q_envelope, streamorder = query_order, realization = "flowline")
        }, error = function(e) NULL)
        
        if (!is.null(fl_batch) && inherits(fl_batch, "sf") && nrow(fl_batch) > 0) {
          fl_batch <- sf::st_transform(fl_batch, 4326)
          keep_cols <- intersect(c("comid", "gnis_name", "lengthkm", "streamorde", attr(fl_batch, "sf_column")), names(fl_batch))
          if (length(keep_cols) > 0) {
            fl_batch <- fl_batch[, keep_cols, drop = FALSE]
          }
          
          for (j in seq_len(nrow(missing_sf))) {
            single_huc_sf <- missing_sf[j, ]
            single_id <- as.character(single_huc_sf[[huc_col]])
            h_key <- sprintf("huc_%s_ext_%s_buf_%s_ord_%s", single_id, extent, ifelse(extent == "buffer", as.character(buf_dist), "0"), ifelse(is.null(query_order), "1", as.character(query_order)))
            
            target_geom <- if (extent == "buffer") {
              suppressWarnings(sf::st_transform(sf::st_buffer(sf::st_transform(single_huc_sf, 5070), buf_dist * 1000), 4326))
            } else if (extent == "bbox") {
              sf::st_as_sfc(sf::st_bbox(single_huc_sf))
            } else {
              single_huc_sf
            }
            
            inter <- suppressWarnings(lengths(sf::st_intersects(fl_batch, target_geom)) > 0)
            fl_single <- fl_batch[inter, ]
            assign(h_key, fl_single, envir = .watershed_flowline_cache)
            if (nrow(fl_single) > 0) cached_list[[single_id]] <- fl_single
          }
        } else {
          for (j in seq_len(nrow(missing_sf))) {
            single_id <- as.character(missing_sf[[huc_col]][j])
            h_key <- sprintf("huc_%s_ext_%s_buf_%s_ord_%s", single_id, extent, ifelse(extent == "buffer", as.character(buf_dist), "0"), ifelse(is.null(query_order), "1", as.character(query_order)))
            assign(h_key, NULL, envir = .watershed_flowline_cache)
          }
        }
      } else {
        for (j in seq_len(nrow(missing_sf))) {
          single_huc_sf <- missing_sf[j, ]
          single_id <- as.character(single_huc_sf[[huc_col]])
          h_key <- sprintf("huc_%s_ext_%s_buf_%s_ord_%s", single_id, extent, ifelse(extent == "buffer", as.character(buf_dist), "0"), ifelse(is.null(query_order), "1", as.character(query_order)))
          
          target_geom <- if (extent == "buffer") {
            suppressWarnings(sf::st_transform(sf::st_buffer(sf::st_transform(single_huc_sf, 5070), buf_dist * 1000), 4326))
          } else if (extent == "bbox") {
            sf::st_as_sfc(sf::st_bbox(single_huc_sf))
          } else {
            single_huc_sf
          }
          
          q_env_j <- sf::st_as_sfc(sf::st_bbox(target_geom))
          fl_j <- tryCatch({
            nhdplusTools::get_nhdplus(AOI = q_env_j, streamorder = query_order, realization = "flowline")
          }, error = function(e) NULL)
          
          if (!is.null(fl_j) && inherits(fl_j, "sf") && nrow(fl_j) > 0) {
            fl_j <- sf::st_transform(fl_j, 4326)
            keep_cols <- intersect(c("comid", "gnis_name", "lengthkm", "streamorde", attr(fl_j, "sf_column")), names(fl_j))
            if (length(keep_cols) > 0) {
              fl_j <- fl_j[, keep_cols, drop = FALSE]
            }
            inter <- suppressWarnings(lengths(sf::st_intersects(fl_j, target_geom)) > 0)
            fl_single <- fl_j[inter, ]
            assign(h_key, fl_single, envir = .watershed_flowline_cache)
            if (nrow(fl_single) > 0) cached_list[[single_id]] <- fl_single
          } else {
            assign(h_key, NULL, envir = .watershed_flowline_cache)
          }
        }
      }
      suppressMessages(sf::sf_use_s2(old_s2))
    }
    
    if (length(cached_list) == 0) return(NULL)
    
    # Combine all individual HUC flowlines in memory
    combined_fl <- do.call(rbind, cached_list)
    if (!is.null(combined_fl) && inherits(combined_fl, "sf") && nrow(combined_fl) > 0) {
      if ("comid" %in% names(combined_fl)) {
        combined_fl <- combined_fl[!duplicated(combined_fl$comid), ]
      }
      if (is.numeric(effective_min_order) && effective_min_order > 1 && "streamorde" %in% names(combined_fl)) {
        combined_fl <- combined_fl[!is.na(combined_fl$streamorde) & combined_fl$streamorde >= effective_min_order, ]
      }
      return(combined_fl)
    }
    return(NULL)
  }

  # --- Branch B: Generic Shape / Bounding-Box Cache Fallback ---
  aoi_union <- suppressWarnings(sf::st_union(aoi_4326))
  bb <- sf::st_bbox(aoi_4326)
  cache_key <- sprintf(
    "ext_%s_buf_%s_ord_%s_bb_%.4f_%.4f_%.4f_%.4f",
    extent,
    ifelse(extent == "buffer", as.character(buf_dist), "0"),
    ifelse(is.null(query_order), "1", as.character(query_order)),
    bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"]
  )

  if (exists(cache_key, envir = .watershed_flowline_cache, inherits = FALSE)) {
    cached_fl <- get(cache_key, envir = .watershed_flowline_cache, inherits = FALSE)
    if (!is.null(cached_fl) && inherits(cached_fl, "sf") && nrow(cached_fl) > 0 && is.numeric(min_stream_order) && min_stream_order > 1 && "streamorde" %in% names(cached_fl)) {
      return(cached_fl[!is.na(cached_fl$streamorde) & cached_fl$streamorde >= min_stream_order, ])
    }
    return(cached_fl)
  }
  
  query_aoi <- if (extent == "bbox") {
    sf::st_as_sfc(bb)
  } else if (extent == "buffer") {
    suppressWarnings(sf::st_transform(sf::st_buffer(sf::st_transform(aoi_union, 5070), buf_dist * 1000), 4326))
  } else {
    aoi_union
  }
  
  query_envelope <- sf::st_as_sfc(sf::st_bbox(query_aoi))
  
  flowlines <- tryCatch({
    nhdplusTools::get_nhdplus(AOI = query_envelope, streamorder = query_order, realization = "flowline")
  }, error = function(e) {
    warning("Failed to retrieve NHD stream flowlines: ", e$message)
    NULL
  })
  
  if (is.null(flowlines) || !inherits(flowlines, "sf") || nrow(flowlines) == 0) {
    assign(cache_key, NULL, envir = .watershed_flowline_cache)
    return(NULL)
  }
  
  flowlines <- sf::st_transform(flowlines, 4326)
  
  keep_cols <- intersect(c("comid", "gnis_name", "lengthkm", "streamorde", attr(flowlines, "sf_column")), names(flowlines))
  if (length(keep_cols) > 0) {
    flowlines <- flowlines[, keep_cols, drop = FALSE]
  }
  
  if (extent %in% c("huc", "buffer")) {
    old_s2 <- suppressMessages(sf::sf_use_s2(FALSE))
    inter <- suppressWarnings(lengths(sf::st_intersects(flowlines, query_aoi)) > 0)
    suppressMessages(sf::sf_use_s2(old_s2))
    flowlines <- flowlines[inter, ]
  }
  
  assign(cache_key, flowlines, envir = .watershed_flowline_cache)
  
  if (is.numeric(min_stream_order) && min_stream_order > 1 && "streamorde" %in% names(flowlines)) {
    flowlines <- flowlines[!is.na(flowlines$streamorde) & flowlines$streamorde >= min_stream_order, ]
  }
  
  return(flowlines)
}


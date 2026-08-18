#' Add USGS Hydrography Map Tile Layer to Leaflet
#'
#' Adds the official USGS National Hydrography Cached WMS map layer to a Leaflet map.
#'
#' @param map A \code{leaflet} map or \code{leafletProxy} object.
#' @param group Character. Group name for layer controls (default: \code{"USGS Hydrography (Streams)"}).
#'
#' @return A modified \code{leaflet} or \code{leafletProxy} map object.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' leaflet() |>
#'     addTiles() |>
#'     add_usgs_hydro_layer()
#' }
add_usgs_hydro_layer <- function(map, group = "USGS Hydrography (Streams)") {
  if (!inherits(map, "leaflet") && !inherits(map, "leaflet_proxy")) {
    stop("`map` must be a valid leaflet map or leafletProxy object.", call. = FALSE)
  }
  leaflet::addWMSTiles(
    map = map,
    baseUrl = "https://basemap.nationalmap.gov/arcgis/services/USGSHydroCached/MapServer/WMSServer",
    layers = "0",
    options = leaflet::WMSTileOptions(format = "image/png", transparent = TRUE),
    attribution = "USGS - The National Map",
    group = group
  )
}

#' Add USGS 3DEP Shaded Relief (DEM) Map Tile Layer to Leaflet
#'
#' Adds the official USGS National Map 3D Elevation Program (3DEP) Shaded Relief WMS layer
#' to a Leaflet map, providing a high-contrast terrain representation.
#'
#' @param map A \code{leaflet} map or \code{leafletProxy} object.
#' @param group Character. Group name for layer controls (default: \code{"USGS Shaded Relief (DEM)"}).
#'
#' @return A modified \code{leaflet} or \code{leafletProxy} map object.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' leaflet() |>
#'     add_usgs_shaded_relief_layer()
#' }
add_usgs_shaded_relief_layer <- function(map, group = "USGS Shaded Relief (DEM)") {
  if (!inherits(map, "leaflet") && !inherits(map, "leaflet_proxy")) {
    stop("`map` must be a valid leaflet map or leafletProxy object.", call. = FALSE)
  }
  leaflet::addWMSTiles(
    map = map,
    baseUrl = "https://basemap.nationalmap.gov/arcgis/services/USGSShadedReliefOnly/MapServer/WMSServer",
    layers = "0",
    options = leaflet::WMSTileOptions(format = "image/png", transparent = TRUE),
    attribution = "USGS 3DEP - The National Map",
    group = group
  )
}

#' Add USGS Topographic Map Tile Layer to Leaflet
#'
#' Adds the official USGS National Map Topographic WMS map layer to a Leaflet map.
#'
#' @param map A \code{leaflet} map or \code{leafletProxy} object.
#' @param group Character. Group name for layer controls (default: \code{"USGS Topo"}).
#'
#' @return A modified \code{leaflet} or \code{leafletProxy} map object.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' leaflet() |>
#'     add_usgs_topo_layer()
#' }
add_usgs_topo_layer <- function(map, group = "USGS Topo") {
  if (!inherits(map, "leaflet") && !inherits(map, "leaflet_proxy")) {
    stop("`map` must be a valid leaflet map or leafletProxy object.", call. = FALSE)
  }
  leaflet::addWMSTiles(
    map = map,
    baseUrl = "https://basemap.nationalmap.gov/arcgis/services/USGSTopo/MapServer/WMSServer",
    layers = "0",
    options = leaflet::WMSTileOptions(format = "image/png", transparent = TRUE),
    attribution = "USGS Topo - The National Map",
    group = group
  )
}

#' Add StreamStats Layer and Vector Stream Flowlines to Leaflet Map
#'
#' Queries the USGS StreamStats SS-Delineate API for a specified location and state/region code
#' to delineate the watershed drainage basin, extracts intersecting vector stream flowlines via
#' \code{nhdplusTools}, and adds them to a Leaflet map object.
#'
#' @param map A \code{leaflet} map or \code{leafletProxy} object.
#' @param lat Numeric. Latitude of the delineation pour point (in WGS84).
#' @param lng Numeric. Longitude of the delineation pour point (in WGS84).
#' @param rcode Character. Two-letter state or region code (e.g., \code{"WI"}, \code{"IL"}, \code{"NY"}).
#' @param basin_group Character. Group name for the watershed boundary. Defaults to \code{"StreamStats Basin"}.
#' @param stream_group Character. Group name for stream flowlines. Defaults to \code{"Stream Flowlines"}.
#' @param layer_group Character. Fallback group name for backward compatibility.
#' @param stream_color Character. Color for the stream flowlines. Defaults to \code{"#0055ff"}.
#' @param basin_color Character. Fill and stroke color for the watershed boundary polygon. Defaults to \code{"#3388ff"}.
#' @param color Optional character fallback color for backward compatibility.
#' @param weight Numeric. Base stroke weight (line thickness) for streams in pixels. Defaults to \code{3}.
#' @param opacity Numeric. Opacity of stream flowlines (0 to 1). Defaults to \code{0.9}.
#' @param fillOpacity Numeric. Opacity of watershed polygon fill (0 to 1). Defaults to \code{0.15}.
#' @param include_flowlines Logical. Whether to fetch and render NHD stream flowlines. Defaults to \code{TRUE}.
#' @param buffer_km Numeric. Search buffer radius in km around pour point to capture intersecting stream flowlines. Defaults to \code{3}.
#' @param ... Additional arguments passed to \code{\link[leaflet]{addPolygons}} or \code{\link[leaflet]{addPolylines}}.
#'
#' @return A modified \code{leaflet} or \code{leafletProxy} map object with the StreamStats basin and flowlines added.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' leaflet() |>
#'     addTiles() |>
#'     add_streamstats_layer(lat = 43.0731, lng = -89.4012, rcode = "WI")
#' }
add_streamstats_layer <- function(map,
                                  lat,
                                  lng,
                                  rcode,
                                  basin_group = "StreamStats Basin",
                                  stream_group = "Stream Flowlines",
                                  layer_group = NULL,
                                  stream_color = "#0055ff",
                                  basin_color = "#3388ff",
                                  color = NULL,
                                  weight = 3,
                                  opacity = 0.9,
                                  fillOpacity = 0.15,
                                  include_flowlines = TRUE,
                                  buffer_km = 3,
                                  ...) {
  # 1. Parameter validation: supports both leaflet and leafletProxy map handles
  if (!inherits(map, "leaflet") && !inherits(map, "leaflet_proxy")) {
    stop("`map` must be a valid leaflet map or leafletProxy object.", call. = FALSE)
  }
  if (missing(lat) || missing(lng) || missing(rcode)) {
    stop("`lat`, `lng`, and `rcode` must all be supplied.", call. = FALSE)
  }

  if (!is.null(layer_group)) {
    basin_group <- layer_group
    stream_group <- layer_group
  }
  if (!is.null(color)) {
    stream_color <- color
    basin_color <- color
  }

  # 2. Build API request URL targeting the SS-Delineate endpoint
  base_url <- sprintf("https://streamstats.usgs.gov/ss-delineate/v1/delineate/sshydro/%s", tolower(rcode))

  req <- httr2::request(base_url) |>
    httr2::req_url_query(
      rcode = tolower(rcode),
      lon = as.numeric(lng),
      lat = as.numeric(lat),
      xlocation = as.numeric(lng),
      ylocation = as.numeric(lat),
      crs = 4326,
      inclusive = "true"
    ) |>
    httr2::req_headers(
      `Accept` = "application/json"
    ) |>
    httr2::req_timeout(30)

  # 3. Perform HTTP GET request with error handling
  resp <- tryCatch(
    {
      httr2::req_perform(req)
    },
    error = function(e) {
      stop(sprintf("Failed to connect to StreamStats API: %s", e$message), call. = FALSE)
    }
  )

  if (httr2::resp_status(resp) != 200) {
    stop(sprintf("StreamStats API returned HTTP error %s", httr2::resp_status(resp)), call. = FALSE)
  }

  # 4. Extract response body and parse GeoJSON spatial object
  geojson_txt <- httr2::resp_body_string(resp)

  basin_sf <- NULL
  sf_obj <- tryCatch(
    {
      suppressWarnings(sf::st_read(geojson_txt, quiet = TRUE))
    },
    error = function(e) NULL
  )

  if (is.null(sf_obj) || nrow(sf_obj) == 0) {
    json_data <- tryCatch(
      {
        jsonlite::fromJSON(geojson_txt, simplifyVector = FALSE)
      },
      error = function(e) NULL
    )

    if (!is.null(json_data) && !is.null(json_data$bcrequest$wsresp$featurecollection)) {
      fc_items <- json_data$bcrequest$wsresp$featurecollection[[1]]
      for (item in fc_items) {
        if (identical(item$name, "globalwatershed") && !is.null(item$feature)) {
          feat_str <- jsonlite::toJSON(item$feature, auto_unbox = TRUE)
          basin_sf <- tryCatch(suppressWarnings(sf::st_read(feat_str, quiet = TRUE)), error = function(e) NULL)
        }
      }
    }
  } else {
    geom_types <- as.character(sf::st_geometry_type(sf_obj))
    poly_mask <- geom_types %in% c("POLYGON", "MULTIPOLYGON")
    if (any(poly_mask)) {
      basin_sf <- sf_obj[poly_mask, ]
    }
  }

  if (!is.null(basin_sf) && nrow(basin_sf) > 0) {
    basin_sf <- sf::st_transform(basin_sf, crs = 4326)
    map <- leaflet::addPolygons(
      map = map,
      data = basin_sf,
      color = basin_color,
      weight = 2,
      fillColor = basin_color,
      fillOpacity = fillOpacity,
      group = basin_group,
      popup = "<b>Delineated Drainage Basin (StreamStats)</b>",
      ...
    )
  }

  # 5. Extract and Render Vector Stream Flowlines (NHD)
  if (isTRUE(include_flowlines)) {
    pt_sf <- sf::st_sfc(sf::st_point(c(as.numeric(lng), as.numeric(lat))), crs = 4326)
    pt_buf <- sf::st_as_sfc(sf::st_bbox(sf::st_buffer(sf::st_transform(pt_sf, 3857), buffer_km * 1000))) |>
      sf::st_transform(4326)

    aoi <- if (!is.null(basin_sf) && nrow(basin_sf) > 0) {
      suppressWarnings(sf::st_union(basin_sf, pt_buf))
    } else {
      pt_buf
    }

    flowlines <- tryCatch(
      {
        nhdplusTools::get_nhdplus(AOI = aoi, realization = "flowline")
      },
      error = function(e) NULL
    )

    if (is.null(flowlines) || nrow(flowlines) == 0) {
      flowlines <- tryCatch(
        {
          nhdplusTools::get_nhdplus(AOI = pt_sf, realization = "flowline")
        },
        error = function(e) NULL
      )
    }

    if (!is.null(flowlines) && nrow(flowlines) > 0) {
      flowlines <- sf::st_transform(flowlines, crs = 4326)
      line_weights <- if ("streamorde" %in% names(flowlines)) {
        pmax(as.numeric(flowlines$streamorde) * 1.2, weight)
      } else {
        weight
      }

      stream_names <- if ("gnis_name" %in% names(flowlines)) {
        ifelse(is.na(flowlines$gnis_name) | flowlines$gnis_name == " ", "Unnamed Stream / Flowline", flowlines$gnis_name)
      } else {
        rep("Stream / Flowline", nrow(flowlines))
      }

      orders <- if ("streamorde" %in% names(flowlines)) flowlines$streamorde else rep(1, nrow(flowlines))
      lengths <- if ("lengthkm" %in% names(flowlines)) sprintf("%.2f km", flowlines$lengthkm) else ""

      popups <- sprintf("<b>Stream:</b> %s<br/><b>Stream Order:</b> %s<br/><b>Length:</b> %s", stream_names, orders, lengths)

      map <- leaflet::addPolylines(
        map = map,
        data = flowlines,
        color = stream_color,
        weight = line_weights,
        opacity = opacity,
        popup = popups,
        group = stream_group,
        ...
      )
    }
  }

  return(map)
}




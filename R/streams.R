#' Add StreamStats Layer to Leaflet Map
#'
#' Queries the USGS StreamStats SS-Delineate API for a specified location and state/region code,
#' converts the returned spatial features into an \code{sf} object, and adds them to a Leaflet map object.
#'
#' @param map A \code{leaflet} map object.
#' @param lat Numeric. Latitude of the delineation pour point (in WGS84).
#' @param lng Numeric. Longitude of the delineation pour point (in WGS84).
#' @param rcode Character. Two-letter state or region code (e.g., \code{"WI"}, \code{"IL"}, \code{"NY"}).
#' @param layer_group Character. Group name for the Leaflet layer control. Defaults to \code{"StreamStats Watershed"}.
#' @param color Character. Fill and stroke color for the spatial layer. Defaults to \code{"#0277bd"}.
#' @param weight Numeric. Stroke weight (line thickness) in pixels. Defaults to \code{2}.
#' @param fillOpacity Numeric. Opacity of polygon fill (0 to 1). Defaults to \code{0.3}.
#' @param ... Additional arguments passed to \code{\link[leaflet]{addPolygons}} or \code{\link[leaflet]{addPolylines}}.
#'
#' @return A modified \code{leaflet} map object with the StreamStats features added.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' }

#' leaflet() %>%
#'   addTiles() %>%
#'   add_streamstats_layer(lat = 43.0731, lng = -89.4012, rcode = "WI")
#' }
add_streamstats_layer <- function(map,
                                  lat,
                                  lng,
                                  rcode,
                                  layer_group = "StreamStats Watershed",
                                  color = "#0277bd",
                                  weight = 2,
                                  fillOpacity = 0.3,
                                  ...) {
    # 1. Parameter validation
    if (!inherits(map, "leaflet")) {
        stop("`map` must be a valid leaflet map object.", call. = FALSE)
    }
    if (missing(lat) || missing(lng) || missing(rcode)) {
        stop("`lat`, `lng`, and `rcode` must all be supplied.", call. = FALSE)
    }

    # 2. Build API request URL targeting the SS-Delineate endpoint
    # SS-Delineate GET /v1/delineate/sshydro/{region}
    base_url <- sprintf("https://streamstats.usgs.gov/ss-delineate/v1/delineate/sshydro/%s", tolower(rcode))

    req <- httr2::request(base_url) %>%
        httr2::req_url_query(
            rcode = tolower(rcode),
            xlocation = lng,
            ylocation = lat,
            crs = 4326,
            inclusive = "true"
        ) %>%
        httr2::req_headers(
            `Accept` = "application/json"
        ) %>%
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

    # 4. Extract GeoJSON string and parse into an sf spatial object
    geojson_txt <- httr2::resp_body_string(resp)

    sf_obj <- tryCatch(
        {
            sf::st_read(geojson_txt, quiet = TRUE)
        },
        error = function(e) {
            stop("Failed to parse GeoJSON spatial data returned by StreamStats.", call. = FALSE)
        }
    )

    if (nrow(sf_obj) == 0) {
        warning("StreamStats API returned an empty spatial feature set for the given coordinates.", call. = FALSE)
        return(map)
    }

    # Ensure CRS is EPSG:4326 for Leaflet compatibility
    sf_obj <- sf::st_transform(sf_obj, crs = 4326)

    # 5. Add spatial object onto Leaflet map based on geometry type
    geom_type <- unique(as.character(sf::st_geometry_type(sf_obj)))

    if (any(c("POLYGON", "MULTIPOLYGON") %in% geom_type)) {
        map <- leaflet::addPolygons(
            map = map,
            data = sf_obj,
            color = color,
            weight = weight,
            fillOpacity = fillOpacity,
            group = layer_group,
            ...
        )
    } else {
        map <- leaflet::addPolylines(
            map = map,
            data = sf_obj,
            color = color,
            weight = weight,
            group = layer_group,
            ...
        )
    }

    return(map)
}

# Streams

## Prompt

How would I use this streamstats API to incorporate stream layer into an R package (<https://github.com/byandell/hexmap>) that uses leaflet?
Please create `add_streamstats_layer()` function.

## Response

To add a stream network / stream layer to a Leaflet map in R using the USGS StreamStats services, you generally have two main approaches depending on what you need:

1. **Extract Stream Features / Delineation via the REST API** (Dynamic/Interactive Point Delineation)
2. **Display standard USGS Hydrography / StreamStats Map Tiles as WMS/WMTS Layers** (Fast, visual background overlay)

---

## Approach 1: Querying the StreamStats API directly (JSON / GeoJSON)

The page you are looking at ([Delineate Services API](https://streamstats.usgs.gov/ss-delineate/docs)) handles watershed delineation and feature extraction. You can query the endpoints (such as `/v1/delineate/sshydro/{region}`) using R's `httr2` or `httr` package, parse the returned GeoJSON flowlines/features using `sf`, and then render them on your Leaflet map.

### Example R Workflow

```R
library(httr2)
library(sf)
library(leaflet)

# 1. Query the StreamStats API for a delineation/stream point
# Replace {region} with state code (e.g., "WI") and provide x, y (lon/lat)
region <- "WI"
lon <- -89.4012
lat <- 43.0731

url <- sprintf("https://streamstats.usgs.gov/ss-delineate/v1/delineate/sshydro/%s?rcode=%s&xlocation=%f&ylocation=%f&crs=4326&inclusive=true", 
               region, region, lon, lat)

# Fetch data from the API
req <- request(url)
resp <- req_perform(req)

# Parse response into sf object (if GeoJSON format is returned)
geojson_data <- resp_body_string(resp)
stream_sf <- st_read(geojson_data, quiet = TRUE)

# 2. Add to Leaflet Map
leaflet() %>%
  addTiles() %>%
  addPolygons(data = stream_sf, color = "blue", weight = 2, group = "StreamStats Watershed")

```

---

## Approach 2: Adding USGS Hydrography WMS Base/Overlay Layers to Leaflet

If you want a continuous stream/hydrography map layer overlaid on your HexMap/Leaflet map without querying individual point endpoints, you can add USGS ArcGIS REST / WMS services directly via `addWMSTiles()`.

### Example R Workflow for WMS Stream Layer

```R
library(leaflet)

leaflet() %>%
  addTiles() %>% # Standard OpenStreetMap base layer
  # Add USGS Hydrography National Map Service as a WMS layer
  addWMSTiles(
    baseUrl = "https://basemap.nationalmap.gov/arcgis/services/USGSHydroCached/MapServer/WMSServer",
    layers = "0",
    options = WMSTileOptions(
      format = "image/png",
      transparent = TRUE
    ),
    attribution = "USGS - The National Map",
    group = "Hydrography Stream Layer"
  ) %>%
  addLayersControl(
    overlayGroups = c("Hydrography Stream Layer"),
    options = layersControlOptions(collapsed = FALSE)
  )

```

---

## Incorporating into your package (`hexmap`)

If you want to integrate this functionality into functions in your [hexmap](https://github.com/byandell/hexmap) package:

1. **Add Dependencies:** Ensure `sf`, `httr2`, and `leaflet` are listed in your `DESCRIPTION` file under `Imports`.
2. **Helper Function:** Create a function (e.g., `add_streamstats_layer(map, region, x, y)`) that fetches the StreamStats endpoint, converts the response to an `sf` object, and appends it to the incoming `leaflet` map object via `addPolylines()` or `addGeoJSON()`.

## Stream Function

Here is a complete, production-ready R function designed to fit cleanly into an R package like `hexmap`.

It uses **`httr2`**, **`sf`**, and **`leaflet`** to query the [StreamStats SS-Delineate API](https://streamstats.usgs.gov/ss-delineate/docs), parse the resulting GeoJSON geometry (watershed boundary/flowlines), and pipe the result directly onto a Leaflet map.

---

### Function Implementation

```R
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
  resp <- tryCatch({
    httr2::req_perform(req)
  }, error = function(e) {
    stop(sprintf("Failed to connect to StreamStats API: %s", e$message), call. = FALSE)
  })
  
  if (httr2::resp_status(resp) != 200) {
    stop(sprintf("StreamStats API returned HTTP error %s", httr2::resp_status(resp)), call. = FALSE)
  }
  
  # 4. Extract GeoJSON string and parse into an sf spatial object
  geojson_txt <- httr2::resp_body_string(resp)
  
  sf_obj <- tryCatch({
    sf::st_read(geojson_txt, quiet = TRUE)
  }, error = function(e) {
    stop("Failed to parse GeoJSON spatial data returned by StreamStats.", call. = FALSE)
  })
  
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

```

---

### Package `DESCRIPTION` File Updates

To ensure this function works when built into your `hexmap` package, make sure the following packages are listed in your `DESCRIPTION` file under `Imports`:

```dcf
Imports: 
    leaflet,
    sf,
    httr2

```

#' Fetch USGS NWAA Integrated Water Availability Assessment Data
#'
#' Queries the USGS National Water Availability Assessment (NWAA) Data Companion API
#' for model-derived water metrics (such as the Supply-Use Index `sui`, total water supply,
#' and sectoral withdrawals) across HUC subwatersheds (HUC2 through HUC12).
#'
#' @param huc Character vector. One or more HUC identifiers (e.g., \code{"070900020603"} for HUC12, or \code{"070900"} for HUC6).
#' @param model Character. The scientific model identifier (default: \code{"iwa-assessment-outputs-conus-2025"}).
#' @param variable Character. The variable identifier (e.g., \code{"sui"}, \code{"availab"}, \code{"consum"}, \code{"strflow"}).
#' @param start_year Integer or character. Starting assessment year (default: \code{2020}).
#' @param start_month Integer or character. Starting assessment month (default: \code{1}).
#' @param end_year Optional integer or character. Ending assessment year.
#' @param end_month Optional integer or character. Ending assessment month.
#'
#' @return A \code{data.frame} containing the requested NWAA assessment records, or an empty data frame if no records found.
#' @export
#'
#' @examples
#' \dontrun{
#' df <- get_nwaa_data(
#'   huc = "070900020603",
#'   model = "iwa-assessment-outputs-conus-2025",
#'   variable = "sui",
#'   start_year = 2020,
#'   start_month = 1
#' )
#' }
get_nwaa_data <- function(huc,
                          model = "iwa-assessment-outputs-conus-2025",
                          variable = "sui",
                          start_year = 2020,
                          start_month = 1,
                          end_year = NULL,
                          end_month = NULL) {
  if (missing(huc) || length(huc) == 0) {
    return(data.frame())
  }

  start_dt <- sprintf("%04d-%02d", as.numeric(start_year), as.numeric(start_month))
  end_yr <- if (!is.null(end_year)) end_year else start_year
  end_mo <- if (!is.null(end_month)) end_month else start_month
  end_dt <- sprintf("%04d-%02d", as.numeric(end_yr), as.numeric(end_mo))

  huc_clean <- unique(trimws(as.character(huc)))
  huc_clean <- huc_clean[nzchar(huc_clean)]
  if (length(huc_clean) == 0) return(data.frame())

  res_list <- lapply(huc_clean, function(hid) {
    n_digits <- nchar(hid)
    loc_param <- sprintf("huc%d:%s", n_digits, hid)

    req <- httr2::request("https://api.water.usgs.gov/nwaa-data/data") |>
      httr2::req_url_query(
        model = model,
        variable = variable,
        location = loc_param,
        startdate = start_dt,
        enddate = end_dt,
        timeres = "monthly",
        format = "json"
      ) |>
      httr2::req_headers(Accept = "application/json") |>
      httr2::req_timeout(20)

    resp <- tryCatch(
      httr2::req_perform(req),
      error = function(e) {
        warning(sprintf("USGS NWAA API request failed: %s", e$message), call. = FALSE)
        NULL
      }
    )

    if (is.null(resp) || httr2::resp_status(resp) != 200) {
      return(NULL)
    }

    json_raw <- tryCatch(
      httr2::resp_body_json(resp, simplifyVector = FALSE),
      error = function(e) NULL
    )

    if (is.null(json_raw) || is.null(json_raw$data) || is.null(json_raw$data$huc12_id)) {
      return(NULL)
    }

    h_list <- json_raw$data$huc12_id
    rows <- lapply(names(h_list), function(child_id) {
      recs <- h_list[[child_id]]
      if (length(recs) > 0 && is.list(recs[[1]])) {
        rec <- recs[[1]]
        val <- if (!is.null(rec[[variable]])) rec[[variable]] else NA_real_
        ym <- if (!is.null(rec[["year_month"]])) rec[["year_month"]] else start_dt
        data.frame(
          huc12 = child_id,
          parent_huc = hid,
          value = as.numeric(val),
          year_month = ym,
          variable = variable,
          stringsAsFactors = FALSE
        )
      } else {
        NULL
      }
    })
    do.call(rbind, rows)
  })

  out <- do.call(rbind, res_list)
  if (is.null(out)) data.frame() else out
}

#' Fetch Available USGS NWAA Models
#'
#' Retrieves metadata for available scientific models in the USGS NWAA Data Companion API.
#'
#' @return A \code{data.frame} describing available NWAA models and descriptions.
#' @export
#'
#' @examples
#' \dontrun{
#' models <- get_nwaa_models()
#' }
get_nwaa_models <- function() {
  base_url <- "https://api.water.usgs.gov/nwaa-data/models"
  req <- httr2::request(base_url) |>
    httr2::req_headers(Accept = "application/json") |>
    httr2::req_timeout(15)

  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) NULL
  )

  if (is.null(resp) || httr2::resp_status(resp) != 200) {
    return(data.frame(
      model_id = c("iwa-assessment-outputs-conus-2025"),
      model_name = c("National Water Availability Assessment Outputs (CONUS 2025)"),
      sector = c("Integrated water availability"),
      stringsAsFactors = FALSE
    ))
  }

  json_raw <- tryCatch(httr2::resp_body_json(resp, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(json_raw) || length(json_raw) == 0) {
    return(data.frame(
      model_id = c("iwa-assessment-outputs-conus-2025"),
      model_name = c("National Water Availability Assessment Outputs (CONUS 2025)"),
      sector = c("Integrated water availability"),
      stringsAsFactors = FALSE
    ))
  }

  as.data.frame(json_raw)
}

#' Fetch Available USGS NWAA Variables
#'
#' Retrieves metadata for available environmental and hydrological assessment variables
#' in the USGS NWAA Data Companion API.
#'
#' @return A \code{data.frame} of available NWAA variables with identifiers and descriptions.
#' @export
#'
#' @examples
#' \dontrun{
#' vars <- get_nwaa_variables()
#' }
get_nwaa_variables <- function() {
  base_url <- "https://api.water.usgs.gov/nwaa-data/variables"
  req <- httr2::request(base_url) |>
    httr2::req_headers(Accept = "application/json") |>
    httr2::req_timeout(15)

  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) NULL
  )

  if (is.null(resp) || httr2::resp_status(resp) != 200) {
    return(data.frame(
      variable_id = c("sui", "availab", "consum", "strflow"),
      variable_name = c(
        "Surface water supply and use index (SUI)",
        "Total water availability",
        "Total water consumption",
        "Streamflow"
      ),
      variable_units = c("Fraction (frac)", "mm/mo", "mm/mo", "mm/mo"),
      stringsAsFactors = FALSE
    ))
  }

  json_raw <- tryCatch(httr2::resp_body_json(resp, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(json_raw) || length(json_raw) == 0) {
    return(data.frame(
      variable_id = c("sui", "availab", "consum", "strflow"),
      variable_name = c(
        "Surface water supply and use index (SUI)",
        "Total water availability",
        "Total water consumption",
        "Streamflow"
      ),
      variable_units = c("Fraction (frac)", "mm/mo", "mm/mo", "mm/mo"),
      stringsAsFactors = FALSE
    ))
  }

  as.data.frame(json_raw)
}

#' Add USGS NWAA Flowlines Layer to Leaflet Map
#'
#' Adds the official USGS National Hydrography Network Flowlines WMS layer to a Leaflet map.
#'
#' @param map A \code{leaflet} or \code{leafletProxy} map object.
#' @param group Character. Group name for layer control (default: \code{"USGS NWAA Flowlines"}).
#'
#' @return A modified \code{leaflet} or \code{leafletProxy} map object.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' leaflet() |>
#'   addTiles() |>
#'   add_nwaa_flowlines_layer()
#' }
add_nwaa_flowlines_layer <- function(map, group = "USGS NWAA Flowlines") {
  if (!inherits(map, "leaflet") && !inherits(map, "leaflet_proxy")) {
    stop("`map` must be a valid leaflet map or leafletProxy object.", call. = FALSE)
  }

  leaflet::addWMSTiles(
    map = map,
    baseUrl = "https://hydro.nationalmap.gov/arcgis/services/nhd/MapServer/WMSServer",
    layers = "6",
    options = leaflet::WMSTileOptions(format = "image/png", transparent = TRUE),
    attribution = "USGS NHD - National Water Availability Assessment",
    group = group
  )
}

#' Add NWAA HUC Water Availability Choropleth Overlay to Leaflet
#'
#' Retrieves HUC boundary polygons at the matching digit granularity (HUC2–HUC12)
#' and joins USGS NWAA monthly assessment variables (e.g. Supply-Use Index, water availability)
#' for interactive Leaflet choropleth display.
#'
#' @param map A \code{leaflet} or \code{leafletProxy} object.
#' @param huc Character vector of HUC identifiers (e.g., \code{"070900020603"} for HUC12, or \code{"070900"} for HUC6).
#' @param variable Character. NWAA variable to visualize (default: \code{"sui"}).
#' @param year Numeric or character. Assessment year (default: \code{2020}).
#' @param month Numeric or character. Assessment month (default: \code{1}).
#' @param group Character. Leaflet layer group name (default: \code{"NWAA Water Availability (HUC12)"}).
#' @param fillOpacity Numeric. Opacity of polygon fill (default: \code{0.6}).
#' @param weight Numeric. Boundary stroke weight (default: \code{1.5}).
#' @param ... Additional arguments passed to \code{\link[leaflet]{addPolygons}}.
#'
#' @return A modified \code{leaflet} or \code{leafletProxy} map object.
#' @export
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#' leaflet() |>
#'   addTiles() |>
#'   add_nwaa_huc_overlay(huc = "070900020603", variable = "sui", year = 2020, month = 1)
#' }
add_nwaa_huc_overlay <- function(map,
                                 huc,
                                 variable = "sui",
                                 year = 2020,
                                 month = 1,
                                 group = "NWAA Water Availability (HUC12)",
                                 fillOpacity = 0.6,
                                 weight = 1.5,
                                 ...) {
  if (!inherits(map, "leaflet") && !inherits(map, "leaflet_proxy")) {
    stop("`map` must be a valid leaflet map or leafletProxy object.", call. = FALSE)
  }
  if (missing(huc) || length(huc) == 0) {
    return(map)
  }

  huc_clean <- unique(trimws(as.character(huc)))
  huc_clean <- huc_clean[nzchar(huc_clean)]
  if (length(huc_clean) == 0) return(map)

  # 1. Determine correct HUC type from digit length
  n_digits <- nchar(huc_clean[1])
  huc_type <- sprintf("huc%02d", n_digits)

  # 2. Fetch Spatial Polygons via nhdplusTools
  huc_polys <- tryCatch(
    suppressWarnings(nhdplusTools::get_huc(id = huc_clean, type = huc_type)),
    error = function(e) NULL
  )
  if (is.null(huc_polys) || nrow(huc_polys) == 0) {
    return(map)
  }

  # 3. Fetch NWAA Data
  nwaa_df <- tryCatch(
    get_nwaa_data(huc = huc_clean, variable = variable, start_year = year, start_month = month),
    error = function(e) NULL
  )

  # 4. Join spatial polygons with NWAA attributes
  if (!is.null(nwaa_df) && nrow(nwaa_df) > 0) {
    if (n_digits == 12 && "huc12" %in% names(nwaa_df)) {
      huc_polys <- merge(huc_polys, nwaa_df[, c("huc12", "value")], by.x = "id", by.y = "huc12", all.x = TRUE)
    } else if ("parent_huc" %in% names(nwaa_df)) {
      agg <- stats::aggregate(value ~ parent_huc, data = nwaa_df, FUN = mean, na.rm = TRUE)
      huc_polys <- merge(huc_polys, agg, by.x = "id", by.y = "parent_huc", all.x = TRUE)
    }
  } else {
    huc_polys$value <- NA_real_
  }

  huc_polys <- sf::st_transform(huc_polys, crs = 4326)

  # 5. Create Color Palette
  vals <- suppressWarnings(as.numeric(huc_polys$value))
  if (all(is.na(vals))) {
    pal <- function(x) "#3388ff"
  } else {
    pal <- leaflet::colorNumeric(
      palette = "Viridis",
      domain = vals,
      na.color = "#808080"
    )
  }

  # 6. Render Polygons
  huc_name_col <- if ("name" %in% names(huc_polys)) huc_polys$name else huc_polys$id
  popups <- sprintf(
    "<b>HUC:</b> %s<br/><b>Name:</b> %s<br/><b>%s (%s/%02d):</b> %s",
    huc_polys$id,
    huc_name_col,
    toupper(variable),
    year,
    as.numeric(month),
    ifelse(is.na(vals), "N/A", format(round(vals, 3), nsmall = 3))
  )

  leaflet::addPolygons(
    map = map,
    data = huc_polys,
    fillColor = pal(vals),
    fillOpacity = fillOpacity,
    color = "#333333",
    weight = weight,
    popup = popups,
    group = group,
    ...
  )
}

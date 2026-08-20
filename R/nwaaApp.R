#' UI Component for USGS NWAA Water Availability Explorer
#'
#' Modular UI component supporting standalone exploration and embedded sidebar controls
#' within parent applications (such as \code{watershedApp}).
#'
#' @param id Shiny module ID
#' @param mode Character string specifying layout mode: \code{"standalone"} (default) for full explorer page,
#'   or \code{"sidebar"} for embedded sidebar controls.
#' @export
#' @rdname nwaaApp
nwaaInput <- function(id, mode = c("standalone", "sidebar")) {
  ns <- shiny::NS(id)
  mode <- match.arg(mode)

  if (identical(mode, "sidebar")) {
    return(
      shiny::tagList(
        shiny::checkboxInput(ns("enable_nwaa"), "Overlay NWAA Assessment Layer", value = FALSE),
        shiny::conditionalPanel(
          condition = sprintf("input['%s'] == true", ns("enable_nwaa")),
          shiny::selectInput(
            inputId = ns("variable"),
            label = "Assessment Metric:",
            choices = c(
              "Surface Water Supply-Use Index (SUI)" = "sui",
              "Total Water Availability" = "availab",
              "Total Water Consumption" = "consum",
              "Streamflow" = "strflow"
            ),
            selected = "sui"
          ),
          shiny::sliderInput(
            inputId = ns("year_month"),
            label = "Assessment Month:",
            min = as.Date("2009-10-01"),
            max = as.Date("2020-09-01"),
            value = as.Date("2020-01-01"),
            timeFormat = "%Y-%m",
            step = 30
          ),
          shiny::checkboxInput(ns("show_nwaa_legend"), "Display Assessment Legend", value = TRUE)
        )
      )
    )
  }

  # Standalone layout
  shiny::tagList(
    shiny::h4("USGS National Water Availability Assessment (NWAA) Explorer"),
    shiny::p("Explore standardized CONUS HUC water budgets, human consumption pressures, and supply-use imbalances over time."),
    shiny::fluidRow(
      shiny::column(
        width = 4,
        shiny::textInput(
          inputId = ns("huc_input"),
          label = "HUC ID(s) (e.g. HUC6, HUC8, HUC12):",
          value = "070900"
        )
      ),
      shiny::column(
        width = 4,
        shiny::selectInput(
          inputId = ns("variable"),
          label = "Variable:",
          choices = c(
            "Surface Water Supply-Use Index (SUI)" = "sui",
            "Total Water Availability" = "availab",
            "Total Water Consumption" = "consum",
            "Streamflow" = "strflow"
          ),
          selected = "sui"
        )
      ),
      shiny::column(
        width = 4,
        shiny::sliderInput(
          inputId = ns("year_month"),
          label = "Assessment Month:",
          min = as.Date("2009-10-01"),
          max = as.Date("2020-09-01"),
          value = as.Date("2020-01-01"),
          timeFormat = "%Y-%m",
          step = 30
        )
      )
    ),
    leaflet::leafletOutput(ns("nwaa_map"), height = "520px"),
    shiny::br(),
    shiny::plotOutput(ns("time_series_plot"), height = "280px")
  )
}

#' Output Component for USGS NWAA Explorer
#'
#' Main visual output panel presenting interactive Leaflet map renderings and time-series plots.
#'
#' @param id Shiny module ID
#' @export
#' @rdname nwaaApp
nwaaOutput <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    leaflet::leafletOutput(ns("nwaa_map"), height = "520px"),
    shiny::br(),
    shiny::plotOutput(ns("time_series_plot"), height = "280px")
  )
}

#' Server Logic for USGS NWAA Water Availability Explorer
#'
#' Server module managing USGS NWAA REST API queries, HUC choropleth rendering,
#' and temporal water availability time-series visualization.
#'
#' @param id Shiny module ID
#' @param map_proxy_id Optional character string specifying a parent module's leafletProxy handle
#'   (e.g., \code{session$ns("map-mapper")}).
#' @param hucs Optional reactive expression returning a character vector of active HUC identifiers.
#' @param parent_session Optional Shiny session from parent caller.
#'
#' @return A list of reactive expressions:
#'   \item{enabled}{Logical indicating if NWAA layer is enabled.}
#'   \item{variable}{Character string indicating selected assessment metric.}
#'   \item{year}{Numeric active assessment year.}
#'   \item{month}{Numeric active assessment month.}
#'   \item{data}{Reactive holding fetched NWAA tabular data frame.}
#' @export
#' @rdname nwaaApp
nwaaServer <- function(id,
                       map_proxy_id = NULL,
                       hucs = NULL,
                       parent_session = NULL) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Extract year and month reactively from date slider
    active_year <- shiny::reactive({
      if (is.null(input$year_month)) return(2020)
      as.numeric(format(as.Date(input$year_month), "%Y"))
    })

    active_month <- shiny::reactive({
      if (is.null(input$year_month)) return(1)
      as.numeric(format(as.Date(input$year_month), "%m"))
    })

    # Standalone Map Initialization
    output$nwaa_map <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>
        leaflet::setView(lng = -89.4012, lat = 43.0731, zoom = 9) |>
        add_nwaa_flowlines_layer()
    })

    # Determine active HUCs list
    current_hucs <- shiny::reactive({
      if (!is.null(hucs) && shiny::is.reactive(hucs)) {
        h_val <- hucs()
        if (!is.null(h_val) && length(h_val) > 0) return(as.character(h_val))
      }
      if (!is.null(input$huc_input) && nzchar(trimws(input$huc_input))) {
        return(trimws(unlist(strsplit(input$huc_input, "[,\\s]+"))))
      }
      character(0)
    })

    # Tabular Data Fetcher
    nwaa_records <- shiny::reactive({
      h_list <- current_hucs()
      if (length(h_list) == 0) return(data.frame())

      var <- if (!is.null(input$variable)) input$variable else "sui"
      yr <- active_year()
      mo <- active_month()

      tryCatch(
        get_nwaa_data(huc = h_list, variable = var, start_year = yr, start_month = mo),
        error = function(e) data.frame()
      )
    })

    # Render Standalone Leaflet Updates
    shiny::observe({
      h_list <- current_hucs()
      if (length(h_list) == 0) return()
      var <- if (!is.null(input$variable)) input$variable else "sui"
      yr <- active_year()
      mo <- active_month()

      map_handle <- leaflet::leafletProxy(ns("nwaa_map"))
      map_handle |>
        leaflet::clearGroup("NWAA Water Availability (HUC12)") |>
        add_nwaa_huc_overlay(
          huc = h_list,
          variable = var,
          year = yr,
          month = mo,
          group = "NWAA Water Availability (HUC12)"
        )
    })

    # Standalone Time-Series / Bar Plot
    output$time_series_plot <- shiny::renderPlot({
      df <- nwaa_records()
      var <- if (!is.null(input$variable)) input$variable else "sui"

      if (nrow(df) == 0 || !"value" %in% names(df)) {
        return(
          ggplot2::ggplot() +
            ggplot2::labs(title = "No NWAA assessment data available for the specified HUCs and date.") +
            ggplot2::theme_minimal()
        )
      }

      plot_df <- if (nrow(df) > 30) head(df, 30) else df
      ggplot2::ggplot(plot_df, ggplot2::aes(x = factor(huc12), y = as.numeric(value), fill = factor(huc12))) +
        ggplot2::geom_col(show.legend = FALSE) +
        ggplot2::labs(
          title = sprintf("USGS NWAA %s Assessment (%d/%02d)", toupper(var), active_year(), active_month()),
          x = "HUC12 Identifier",
          y = toupper(var)
        ) +
        ggplot2::theme_minimal() +
        ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
    })

    # Return Reactive State
    return(
      list(
        enabled = shiny::reactive(isTRUE(input$enable_nwaa)),
        variable = shiny::reactive(if (!is.null(input$variable)) input$variable else "sui"),
        year = active_year,
        month = active_month,
        data = nwaa_records
      )
    )
  })
}

#' Launch Standalone USGS NWAA Explorer Shiny Application
#'
#' @export
#' @rdname nwaaApp
#'
#' @examples
#' \dontrun{
#' nwaaApp()
#' }
nwaaApp <- function() {
  ui <- shiny::fluidPage(
    shiny::titlePanel("USGS NWAA CONUS Explorer"),
    nwaaInput("nwaa", mode = "standalone")
  )

  server <- function(input, output, session) {
    nwaaServer("nwaa")
  }

  shiny::shinyApp(ui, server)
}

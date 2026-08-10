#' Geometric Hexagon Count Slider Controls
#'
#' Centralized utilities for discrete geometric hexagon slider controls offering
#' choices (10, 20, 50, 100, 200, 500, 1000).
#'
#' @param inputId Shiny input ID string
#' @param label Slider label string (default: `"Hexagons:"`)
#' @param selected Default selected step value (default: `100`)
#' @param val Input value from slider to parse
#'
#' @export
#' @rdname step_controls
#' @importFrom shiny sliderInput
hex_size_choices <- c(10, 20, 50, 100, 200, 500, 1000)

#' @export
#' @rdname step_controls
hex_size_slider <- function(inputId, label = "Hexagons:", selected = 100) {
  idx <- match(selected, hex_size_choices)
  if (is.na(idx)) idx <- 4
  sl <- shiny::sliderInput(inputId, label, min = 1, max = length(hex_size_choices), value = idx, step = 1, ticks = TRUE)
  sl$children[[2]]$attribs[['data-values']] <- paste(hex_size_choices, collapse = ",")
  sl
}

#' @export
#' @rdname step_controls
parse_hex_size <- function(val) {
  if (is.null(val)) return(100)
  num <- round(as.numeric(val))
  if (is.na(num)) return(100)
  
  if (num %in% hex_size_choices && num > 7) {
    return(num)
  }
  
  if (num >= 0 && num < length(hex_size_choices)) {
    return(hex_size_choices[num + 1])
  }
  
  if (num %in% hex_size_choices) {
    return(num)
  }
  
  100
}

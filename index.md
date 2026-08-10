# hexmap — Interactive Hexagonal Watershed Mapping and Spatial Projection

[![R-CMD-check](https://github.com/byandell/hexmap/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/byandell/hexmap/actions/workflows/pkgdown.yaml)

The **hexmap** R package provides interactive tools for discovering USGS
HUC subwatershed boundaries using Leaflet, isolating specific geographic
features (such as island landmasses via OpenStreetMap), and
mathematically projecting hexagonal substrate grid networks for spatial
population ethology simulations.

## Installation

You can install the development version of `hexmap` from GitHub:

``` r

# install.packages("pak")
pak::pak("byandell/hexmap")
```

Or using `remotes`:

``` r

# install.packages("remotes")
remotes::install_github("byandell/hexmap")
```

## Quick Start

### Launch Interactive Application

``` r

library(hexmap)

# Launch interactive Shiny web app
hexmapApp()
```

### Programmatic GIS Watershed Projection

``` r

library(hexmap)
library(ggplot2)

# 1. Retrieve USGS HUC12 subwatershed boundary (restricted to Isle Royale)
huc_info <- get_watershed("041800000101", feature_name = "Isle Royale")

# 2. Project hexagonal substrate overlay (cell diameter = 0.01 degrees)
hex_obj <- add_watershed_hex_overlay(huc_info, hex_diameter = 0.01)

# 3. Add habitat features & landmarks
hex_obj <- add_habitat_hex_overlay(hex_obj)

# 4. Visualize static autoplot
ggplot2::autoplot(hex_obj)
```

## Key Functions

| Function | Description |
|----|----|
| [`hexmapApp()`](https://byandell.github.io/hexmap/reference/hexmapApp.md) | Launch the interactive Hexagonal Watershed Projection Shiny application |
| [`hexmapInput()`](https://byandell.github.io/hexmap/reference/hexmapApp.md), [`hexmapOutput()`](https://byandell.github.io/hexmap/reference/hexmapApp.md), [`hexmapServer()`](https://byandell.github.io/hexmap/reference/hexmapApp.md) | Shiny module UI and server components for hexmap composition |
| [`leafletApp()`](https://byandell.github.io/hexmap/reference/leafletApp.md), `leafletInput()`, [`leafletOutput()`](https://byandell.github.io/hexmap/reference/leafletApp.md), [`leafletServer()`](https://byandell.github.io/hexmap/reference/leafletApp.md) | Shiny module components for interactive Leaflet discovery |
| `get_watershed(huc_id, feature_name)` | Fetch USGS HUC12 boundary polygons and clip to OpenStreetMap features |
| `add_watershed_hex_overlay(huc_info, hex_diameter)` | Construct S3 spatial hexagonal substrate grid overlay |
| `add_habitat_hex_overlay(hex_obj)` | Compute moose habitat feature suitability weights on hexagonal grid |
| `get_site_cache_file(filename, site)` | Resolve pre-computed spatial boundary layer `.rds` files |

## License

GPL-3 © Brian S. Yandell

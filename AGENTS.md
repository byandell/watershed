# hexmap — Interactive Hexagonal Watershed Mapping and Spatial Projection

## Package Overview

The **hexmap** R package provides interactive discovery of USGS HUC
subwatershed boundaries using Leaflet, dynamic feature isolation (such
as island landmasses via OpenStreetMap), and mathematical projection of
hexagonal substrate grid networks. It includes specialized models for
Isle Royale moose habitat suitability overlays, static `ggplot2`
autoplots, and modular Shiny applications.

- **Version:** 0.1.0
- **Author:** Brian S. Yandell (<yandell@stat.wisc.edu>)
- **License:** GPL-3
- **GitHub:** <https://github.com/byandell/hexmap>
- **Documentation:** <https://byandell.github.io/hexmap/>

## Installation

``` r

# Install development version from GitHub
pak::pak("byandell/hexmap", dependencies = TRUE, upgrade = TRUE)
```

## Basic Workflow

``` r

library(hexmap)

# 1. Retrieve USGS subwatershed boundary (HUC12)
w <- get_watershed("040203000002")

# 2. Construct mathematical hexagonal substrate grid overlay
hex_obj <- add_watershed_hex_overlay(w, hex_diameter = 0.01)

# 3. Static ggplot2 visualization
ggplot2::autoplot(hex_obj)

# 4. Isle Royale Moose Habitat & Substrate Overlay Model
habitat_obj <- create_isle_royale_hex_overlay()
ggplot2::autoplot(habitat_obj)

# 5. Launch interactive Shiny applications
hexmapApp()      # Complete Hexagonal Grid & Habitat Explorer
leafletApp()     # Interactive Leaflet Subwatershed Discovery
```

## Data Files & Spatial Caches

Located in `inst/extdata/`:

| Path | Purpose |
|----|----|
| `inst/extdata/watershed/huc_features.csv` | Feature landmark dictionary (HUC12 IDs and feature names) |
| `inst/extdata/isle_royale/isle_royale_features.rds` | Pre-cached OpenStreetMap habitat geometries (lakes, rivers, bogs, forests) |
| `inst/extdata/isle_royale/isle_royale_landmarks.rds` | Pre-cached moose sighting point landmarks |
| `inst/extdata/isle_royale/isle_royale_layer.rds` | Pre-cached Isle Royale island boundary polygon |

## Key Functions

| Function | Purpose |
|----|----|
| [`hexmapApp()`](https://byandell.github.io/hexmap/reference/hexmapApp.md) | Launch interactive Shiny hexmap application wrapper |
| [`hexmapInput()`](https://byandell.github.io/hexmap/reference/hexmapApp.md), [`hexmapOutput()`](https://byandell.github.io/hexmap/reference/hexmapApp.md), [`hexmapServer()`](https://byandell.github.io/hexmap/reference/hexmapApp.md) | Modular Shiny components for hexmap application |
| [`leafletApp()`](https://byandell.github.io/hexmap/reference/leafletApp.md) | Launch standalone Leaflet subwatershed selection Shiny app |
| `leafletInput()`, [`leafletOutput()`](https://byandell.github.io/hexmap/reference/leafletApp.md), [`leafletServer()`](https://byandell.github.io/hexmap/reference/leafletApp.md) | Modular Shiny components for Leaflet selection |
| `get_watershed(huc_id, feature_name, huc_layer)` | Fetch USGS HUC12 boundary and apply optional feature clipping |
| `add_watershed_hex_overlay(huc_info, hex_diameter)` | Construct spatial hexagonal grid overlay across watershed |
| `autoplot(object)` | S3 method to render static `ggplot2` visualizations |
| `get_habitat_features(watershed_obj, categories)` | Query OpenStreetMap for inland lakes, waterways, forests, and bogs |
| `get_moose_landmarks(watershed_obj)` | Geocode notable sighting landmarks (Washington Creek, Ojibway Lake, etc.) |
| `add_habitat_hex_overlay(hex_obj)` | Calculate habitat suitability weights on hexagonal substrate grids |
| [`build_base_map()`](https://byandell.github.io/hexmap/reference/leaflet.md) | Initialize interactive Leaflet base map |
| `add_leaflet_hex_overlay(map, hex_obj)` | Add hexagonal mesh polygons to Leaflet map |
| `add_leaflet_habitat_overlay(map, habitat_obj)` | Add habitat features and POI landmarks to Leaflet map |
| `get_huc_from_point(lng, lat)` | Reverse-geocode coordinates into enclosing HUC12 subwatershed |
| `get_hucs_from_polygon(polygon_sf)` | Find all HUC subwatersheds overlapping a drawn bounding polygon |

## S3 Classes

- `watershed_hex_overlay` — Geographic HUC boundary + physical hexagonal
  mesh object
- `habitat_hex_overlay` — Habitat feature polygons + POI landmarks +
  substrate suitability weights

## Core R File Locations

- `R/hexmapApp.R` — Main Shiny application wrapper and module server/UI
- `R/leafletApp.R` — Leaflet discovery Shiny application wrapper and
  module server/UI
- `R/leaflet.R` — Leaflet map initialization, spatial boundary queries,
  and interactive layer additions
- `R/watershed.R` — USGS NHDPlus HUC retrieval, feature clipping, and
  hex mesh projection
- `R/habitat.R` — OpenStreetMap habitat extraction, landmark geocoding,
  and substrate scoring models
- `R/get_site_cache_file.R` — Multi-landscape spatial data cache
  resolver for `"hexmap"`
- `inst/hexApp/app.R` — Standalone app launcher for deployment
- `demos/hexmapApp.qmd` — Interactive Quarto tutorial vignette

## Dependencies

Key packages: `shiny`, `leaflet`, `leaflet.extras`, `sf`,
`nhdplusTools`, `osmdata`, `ggplot2`, `utils`, `stats`

------------------------------------------------------------------------

## AI Assistant Guidelines & Development Rules

- **No Automatic Git Commit/Push:** Prepare all file edits and run local
  build/test verifications (`devtools::check()`,
  `quarto render demos/hexmapApp.qmd`), but **NEVER** execute
  `git commit` or `git push`. Leave all staging, committing, and pushing
  for the user to execute manually.
- **Empirical Local Verification:** Never declare a task complete, bug
  fixed, or feature implemented without running concrete local
  verification commands (`devtools::check()`,
  `Rscript -e "devtools::document()"`) to verify clean execution.
- **S3 Method Export Rule:** When exporting S3 methods for external
  generics (such as `autoplot` from `ggplot2`), ALWAYS use
  `#' @exportS3Method ggplot2::autoplot` and
  `#' @importFrom ggplot2 autoplot ...`. DO NOT use bare `#' @export` on
  S3 methods to avoid NAMESPACE ambiguity.
- **Spherical Geometry (s2) Hygiene:** When toggling
  [`sf::sf_use_s2()`](https://r-spatial.github.io/sf/reference/s2.html),
  wrap in [`suppressMessages()`](https://rdrr.io/r/base/message.html) to
  prevent console message spam. Wrap spatial operations
  (`st_intersects`,
  [`nhdplusTools::get_huc`](https://doi-usgs.github.io/nhdplusTools/reference/get_huc.html))
  in [`suppressWarnings()`](https://rdrr.io/r/base/warning.html) when
  operating on latitude/longitude planar approximations.
- **Vector Subsetting Safety:** When filtering vectors in R, ALWAYS use
  `grepl("^\\s*#'", lines)` with `!grepl(...)` or
  `grep(..., invert = TRUE)`. NEVER use `!grep(...)` (which evaluates
  `!2` -\> `FALSE` in R and wipes out the entire vector to
  `character(0)`).
- **Roxygen Comment Stripping in WASM:** Inlining R code into
  `{shinylive-r}` WebAssembly blocks requires stripping roxygen comments
  (`^#'`) to prevent Pandoc JSON string serialization errors.
- **GitHub Pages Deployment:** Always include `touch docs/.nojekyll` and
  `mkdir -p docs/demos` in `.github/workflows/pkgdown.yaml` before
  deploying to `gh-pages` so GitHub Pages serves static WebAssembly
  assets cleanly.
- **Navbar & Navigation Structure:** Main `_pkgdown.yml` site structure
  puts `demos` before `articles` (Guides). `demos/_quarto.yml` `Home`
  tab points to `../index.html` (the pkgdown homepage).

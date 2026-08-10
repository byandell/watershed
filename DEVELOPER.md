# Developer & Architecture Guide (`DEVELOPER.md`)

Welcome to the **`hexmap`** R package developer documentation. This guide details the internal package architecture, data pipeline, S3 object structures, HUC granularity algorithms, and development guidelines for maintainers and contributors.

---

## 1. Package Architecture Overview

The `hexmap` package is organized into modular R files handling interactive Leaflet mapping, USGS NHDPlus subwatershed queries, OpenStreetMap habitat feature extractions, and mathematical hexagonal grid projections.

```
hexmap/
├── R/
│   ├── leaflet.R           # Base Leaflet map initialization, NHDPlus queries, & overlay rendering
│   ├── leafletApp.R        # Modular Leaflet Shiny UI/Server for map search & polygon drawing
│   ├── watershed.R        # USGS HUC retrieval, feature clipping, & watershed_hex_overlay S3 class
│   ├── habitat.R          # OpenStreetMap feature extraction, landmark geocoding, & substrate scoring
│   ├── hexmapApp.R        # Main Shiny application wrapper with granularity controls & download
│   └── get_site_cache_file.R # Multi-landscape spatial data cache resolver
├── inst/
│   ├── extdata/            # Pre-cached spatial layers (Isle Royale features, landmarks, HUC features)
│   └── hexApp/app.R        # Standalone application launcher
├── vignettes/
│   ├── hexmap.Rmd          # Package setup, architecture, and change log vignette
│   └── user_guide.Rmd      # User guide explaining HUC granularity and topology download objects
└── demos/                  # Quarto tutorial gallery (`index.qmd`, `hexmapApp.qmd`)
```

---

## 2. Core Modules & Data Pipeline

### A. Geographic Search & HUC Retrieval (`R/leaflet.R`)
- `build_base_map()`: Initializes an interactive Leaflet basemap centered on North America with OpenStreetMap search bar and `leaflet.extras` draw toolbar.
- `get_huc_from_point(lng, lat)`: Reverse-geocodes coordinate points into encompassing USGS HUC12 subwatersheds.
- `get_hucs_from_polygon(polygon_sf, max_hucs = 6)`: Identifies all subwatersheds overlapping a user-drawn bounding polygon, utilizing **code-annealed string prefix matching** to auto-scale granularity.

### B. Interactive Leaflet Shiny Module (`R/leafletApp.R`)
- `leafletInput(id)`, `leafletOutput(id)`, `leafletServer(id, max_hucs)`: Modular Shiny components supporting rubberband region drawing, shape editing, shape clearing, and shape toggling.
- Purges previous drawn shapes (`clearGroup("Drawn Region")`) and subwatershed overlays (`clearGroup("huc_polygons")`) automatically when starting new draw operations or clicking **Clear Region**.

### C. Watershed Topology & Feature Clipping (`R/watershed.R`)
- `get_watershed(huc_id, feature_name, huc_layer)`: Fetches USGS HUC12 boundaries and applies optional spatial feature clipping (e.g. restricting boundary to an island landmass).
- `add_watershed_hex_overlay(huc_info, hex_diameter)`: Generates a spatial hexagonal grid overlay (`sfc_POLYGON`) across the boundary extent.
- S3 Class: `watershed_hex_overlay`.

### D. Habitat Feature Model (`R/habitat.R`)
- `get_habitat_features(watershed_obj, site)`: Queries OpenStreetMap for inland lakes, waterways, bogs, and forests.
- `get_moose_landmarks(watershed_obj, site)`: Geocodes landmark point locations.
- `add_habitat_hex_overlay(hex_obj)`: Intersects habitat polygons with the hexagonal substrate grid and computes suitability scores per hex cell.
- S3 Class: `habitat_hex_overlay` (inherits from `watershed_hex_overlay`).

### E. Main Application & Unified Download (`R/hexmapApp.R`)
- `hexmapInput(id)`, `hexmapOutput(id)`, `hexmapServer(id)`: Reorganized sidebar layout placing primary controls at top and selected HUCs at the bottom.
- Provides a single **Download Hexmap Topology (.rds)** button (`download_hexmap`) exporting the full unified S3 object.

---

## 3. S3 Class Structures

### `watershed_hex_overlay`
An S3 object containing spatial watershed boundaries and hexagonal grid geometries:
- `$huc_id`: Character vector of selected HUC ID(s).
- `$feature_name`: Restricted feature name string (or `NULL`).
- `$layer`: `sfc` / `sf` polygon boundary of the selected region.
- `$individual_hucs`: `sf` data frame of individual component subwatersheds (if multi-HUC).
- `$hex_overlay`: `sfc` polygon geometry list of hexagonal grid cells.
- `$hex_diameter`: Hexagon extent diameter in degrees.

### `habitat_hex_overlay`
Extends `watershed_hex_overlay` with ecological layers:
- `$habitat_sf`: `sf` data frame of extracted habitat features (lakes, rivers, bogs, forests).
- `$landmarks_sf`: `sf` data frame of sighting point landmarks.
- `$hex_habitat_sf`: `sf` data frame of hexagonal grid cells containing `habitat_score` and `habitat_type`.

---

## 4. Code-Annealed HUC Granularity Algorithm

To prevent network latency and avoid rendering 1000+ tiny HUC12 subwatersheds when a user draws a large regional bounding box, `get_hucs_from_polygon()` employs a zero-overhead string prefix matching algorithm:

1. Executes **1 initial spatial AOI query** for `HUC12` subwatersheds.
2. If $N > \text{max\_hucs}$ (default 6), inspects 12-digit HUC code prefixes in memory:
   - `u10 <- unique(substr(huc12_ids, 1, 10))`
   - `u08 <- unique(substr(huc12_ids, 1, 8))`
   - `u06 <- unique(substr(huc12_ids, 1, 6))`
   - `u04 <- unique(substr(huc12_ids, 1, 4))`
3. Selects the finest level where count $\le \text{max\_hucs}$. If all levels exceed `max_hucs`, selects the coarsest level with the minimum count.
4. Performs **1 direct ID lookup** `nhdplusTools::get_huc(id = target_ids, type = target_level)` using two-digit padded type names (`"huc10"`, `"huc08"`, `"huc06"`, `"huc04"`).

---

## 5. Development Guidelines & Hygiene

- **No Automatic Git Commit/Push:** Leave all staging, committing, and pushing for the user to execute manually.
- **Empirical Local Verification:** Do NOT run `devtools::check()` or `devtools::document()` automatically on routine edits to conserve prompt tokens.
- **S3 Method Export:** Always export S3 methods using `#' @exportS3Method ggplot2::autoplot` and `#' @importFrom ggplot2 autoplot ...`.
- **Spherical Geometry (s2):** Wrap `sf::sf_use_s2()` in `suppressMessages()` and planar spatial operations in `suppressWarnings()`.
- **Vector Subsetting Safety:** Use `grepl("^\\s*#'", lines)` with `!grepl(...)` or `grep(..., invert = TRUE)`. Never use `!grep(...)`.

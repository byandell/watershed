# Creation and Setup of hexmap R Package

The **`hexmap`** R package was extracted from `ewing` into a standalone
repository located at
[`~/Documents/GitHub/hexmap`](https://byandell.github.io/hexmap/) and
published to GitHub at
[byandell/hexmap](https://github.com/byandell/hexmap).

## 1. Package Architecture & Components

- **R Source Code (`R/`)**:
  - [`R/hexmapApp.R`](https://byandell.github.io/hexmap/R/hexmapApp.R) &
    [`R/leafletApp.R`](https://byandell.github.io/hexmap/R/leafletApp.R)
    — Interactive Shiny application modules and wrappers.
  - [`R/watershed.R`](https://byandell.github.io/hexmap/R/watershed.R) &
    [`R/leaflet.R`](https://byandell.github.io/hexmap/R/leaflet.R) —
    USGS HUC subwatershed retrieval, spatial clipping, and Leaflet
    overlays.
  - [`R/habitat.R`](https://byandell.github.io/hexmap/R/habitat.R) —
    OpenStreetMap habitat feature extraction, landmark geocoding, and
    substrate suitability scoring.
  - [`R/get_site_cache_file.R`](https://byandell.github.io/hexmap/R/get_site_cache_file.R)
    — Multi-landscape spatial cache resolver for `"hexmap"`.
- **Package Infrastructure & CI/CD**:
  - [`DESCRIPTION`](https://byandell.github.io/hexmap/DESCRIPTION),
    [`NAMESPACE`](https://byandell.github.io/hexmap/NAMESPACE),
    [`README.md`](https://byandell.github.io/hexmap/README.md), and
    [`AGENTS.md`](https://byandell.github.io/hexmap/AGENTS.md).
  - [`_pkgdown.yml`](https://byandell.github.io/hexmap/_pkgdown.yml) &
    [`.github/workflows/pkgdown.yaml`](https://byandell.github.io/hexmap/.github/workflows/pkgdown.yaml)
    — Automated pkgdown site generation and `gh-pages` deployment.
- **Data Caches & Quarto Demos**:
  - Pre-cached spatial layers in
    [`inst/extdata/`](https://byandell.github.io/hexmap/inst/extdata/).
  - Standalone launchers
    [`app.R`](https://byandell.github.io/hexmap/app.R) &
    [`inst/hexApp/app.R`](https://byandell.github.io/hexmap/inst/hexApp/app.R).
  - Quarto gallery and tutorial vignette in
    [`demos/`](https://byandell.github.io/hexmap/demos/)
    (`demos/index.qmd`, `demos/hexmapApp.qmd`).

## 2. Refinements & Quality Assurance

- **R CMD Check Validation**: Corrected S3 method exports
  (`@exportS3Method ggplot2::autoplot`), suppressed spherical geometry
  (`s2`) messages and planar warnings, declared global variables, and
  verified **`0 errors | 0 warnings | 0 notes (Status: OK)`**.
- **Quarto Gallery & Hotlink Fix**: Formatted card containers in
  [`demos/index.qmd`](https://byandell.github.io/hexmap/demos/index.qmd)
  using 4-colon outer fences (`:::: {.grid}`) and added Bootstrap
  `.stretched-link` styling so clicking anywhere on a demo card
  navigates to its page.
- **GitHub Integration**: Initialized remote repository
  `byandell/hexmap` via `usethis::use_github()`, configured issue
  tracker links, and published documentation to
  <https://byandell.github.io/hexmap/>.

## 3. Recent Enhancements & Granularity Controls

- **Transparent Polygon & Watershed Styling**:
  - Configured Leaflet and `ggplot2` autoplots
    ([`R/leaflet.R`](https://byandell.github.io/hexmap/R/leaflet.R),
    [`R/leafletApp.R`](https://byandell.github.io/hexmap/R/leafletApp.R),
    [`R/watershed.R`](https://byandell.github.io/hexmap/R/watershed.R),
    [`R/habitat.R`](https://byandell.github.io/hexmap/R/habitat.R)) to
    use transparent fills (`fillOpacity = 0` / `fill = NA`) for drawn
    regions, subwatershed boundaries, and hexagonal substrate meshes
    while maintaining distinct border outlines and click interactivity.
- **Zero-Overhead Code-Annealed HUC Scaling**:
  - Enhanced `get_hucs_from_polygon(polygon_sf, max_hucs = 6)` to
    auto-scale HUC subwatershed granularity dynamically based on the
    extent of a user-drawn bounding polygon.
  - Inspects 12-digit HUC string prefixes in memory (`HUC12`
    $`\rightarrow`$`HUC10` $`\rightarrow`$`HUC08` $`\rightarrow`$`HUC06`
    $`\rightarrow`$`HUC04`) after a single HUC12 spatial AOI query,
    selecting the finest level with $`\le \text{max\_hucs}`$ regions.
    Fetches parent geometries via a single direct ID query
    (`nhdplusTools::get_huc(id = target_ids, type = target_level)`),
    eliminating trial-and-error WFS network overhead.
  - Fixed NHDPlus two-digit type formatting (`"huc08"`, `"huc06"`,
    `"huc04"`) and implemented coarsest-level fallback scaling when
    large regional polygons span 50–1200+ HUC12s, guaranteeing
    condensation down to a small, readable count of 4–6 sub-basins.
- **Geometric Hexagon Scale & Gray Background Layering**:
  - Replaced degree diameter sliders with an indexed geometric scale
    slider (`n_hex_idx`, values: `10, 20, 50, 100, 200, 500, 1000`,
    default: `100`) in
    [`R/hexmapApp.R`](https://byandell.github.io/hexmap/R/hexmapApp.R).
  - Dynamically computes cell diameter
    $`d = \sqrt{A / (0.65 \times N)}`$ based on region bounding box area
    $`A`$, guaranteeing consistent grid cell density across both small
    islands and multi-state regional watersheds.
  - Rendered hex grid in subtle slate gray (`#7F8C8D`) and positioned it
    **behind** HUC boundaries in Leaflet maps and `ggplot2` autoplots
    ([`R/leaflet.R`](https://byandell.github.io/hexmap/R/leaflet.R),
    [`R/watershed.R`](https://byandell.github.io/hexmap/R/watershed.R),
    [`R/habitat.R`](https://byandell.github.io/hexmap/R/habitat.R)).
  - Added an **Include Hexagonal Grid Overlay** checkbox (`enable_hex`)
    allowing users to toggle hex mesh generation on or off while
    retaining watershed boundaries and habitat overlays.
- **Interactive Map Clearing & Reorganized Sidebar**:
  - Reorganized sidebar UI controls in
    [`hexmapInput()`](https://byandell.github.io/hexmap/reference/hexmapApp.md),
    placing primary grid settings at the top and moving the selected
    HUCs multi-select list to the bottom.
  - Updated Leaflet draw observers (`input$clear_region`,
    `input$mapper_draw_start`, `input$mapper_draw_new_feature`) to purge
    previous drawn rubberband shapes (`clearGroup("Drawn Region")`) and
    HUC shapes (`clearGroup("huc_polygons")`) when clicking “Clear
    Region” or starting a new polygon draw operation.
  - Disabled automatic point reverse-geocoding network calls on map
    background taps (`input$mapper_click`), preventing unexpected
    latency while panning or zooming.
- **Consolidated Single-Object Download**:
  - Consolidated sidebar download options in
    [`R/hexmapApp.R`](https://byandell.github.io/hexmap/R/hexmapApp.R)
    into a single **Download Hexmap Topology (.rds)** button
    (`download_hexmap`).
  - Downloads a single unified S3 spatial topology object containing all
    layers (`layer` boundary `sf`, `individual_hucs` `sf`, `hex_overlay`
    `sfc`, `hex_habitat_sf` suitability `sf`, `habitat_sf` features
    `sf`, and `landmarks_sf` POI points) rather than separate files.
- **Prompt Overhead Optimization Guidelines**:
  - Streamlined
    [`AGENTS.md`](https://byandell.github.io/hexmap/AGENTS.md) developer
    guidelines to reduce prompt token overhead by ~83% while retaining
    all essential package build rules and specifying that automatic
    `devtools::check()` and `devtools::document()` runs be skipped on
    routine edits.

# hexmap — AI Guidelines & Development Rules

## AI Assistant Guidelines

- **No Automatic Git Commit/Push:** Prepare all edits and run local build/test verifications (`devtools::check()`), but **NEVER** execute `git commit` or `git push`. Leave staging, committing, and pushing for the user.
- **Empirical Local Verification:** Run verification commands (`devtools::check()`, `Rscript -e "devtools::document()"`) when modifying R source code. Skip `devtools::check()` for simple documentation or `.Rmd` edits to save tokens.
- **S3 Method Export Rule:** When exporting S3 methods for external generics (e.g. `autoplot`), use `#' @exportS3Method ggplot2::autoplot` and `#' @importFrom ggplot2 autoplot ...`. Do NOT use bare `#' @export`.
- **Spherical Geometry (s2) Hygiene:** Wrap `sf::sf_use_s2()` in `suppressMessages()`. Wrap planar spatial operations in `suppressWarnings()`.
- **Vector Subsetting Safety:** When filtering vectors in R, ALWAYS use `grepl("^\\s*#'", lines)` with `!grepl(...)` or `grep(..., invert = TRUE)`. NEVER use `!grep(...)`.
- **Roxygen Stripping in WASM:** Strip roxygen comments (`^#'`) in `{shinylive-r}` code blocks.
- **GitHub Pages Deployment:** Keep `touch docs/.nojekyll` and `mkdir -p docs/demos` in `.github/workflows/pkgdown.yaml`.
- **Navigation Structure:** `_pkgdown.yml` lists `demos` before `articles`. `demos/_quarto.yml` `Home` tab points to `../index.html`.

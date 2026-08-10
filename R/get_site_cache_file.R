#' Multi-Landscape Dataset Cache Resolver
#'
#' Dynamically resolves dataset cache file paths across installed package
#' directories (`extdata/[site]`) and local development trees (`inst/extdata/[site]`).
#'
#' @param filename File name string (e.g. `"isle_royale_layer.rds"`).
#' @param site Target site/landscape directory name under `extdata/` (default: `"isle_royale"`).
#'
#' @return Path to target cached dataset file.
#' @export
#' @name get_site_cache_file
#' @rdname get_site_cache_file
get_site_cache_file <- function(filename, site = "isle_royale") {
  pkg_dir <- system.file(file.path("extdata", site), package = "hexmap")
  if (pkg_dir != "") {
    fp <- if (filename == "") pkg_dir else file.path(pkg_dir, filename)
    if (file.exists(fp) || dir.exists(fp)) return(fp)
  }
  dev_fp <- if (filename == "") file.path("inst", "extdata", site) else file.path("inst", "extdata", site, filename)
  if (file.exists(dev_fp) || dir.exists(dev_fp)) return(dev_fp)
  if (pkg_dir != "") file.path(pkg_dir, filename) else dev_fp
}

#' @export
#' @rdname get_site_cache_file
get_isle_royale_cache_file <- function(filename) {
  get_site_cache_file(filename, site = "isle_royale")
}

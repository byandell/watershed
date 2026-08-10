# Multi-Landscape Dataset Cache Resolver

Dynamically resolves dataset cache file paths across installed package
directories (\`extdata/\[site\]\`) and local development trees
(\`inst/extdata/\[site\]\`).

## Usage

``` r
get_site_cache_file(filename, site = "isle_royale")

get_isle_royale_cache_file(filename)
```

## Arguments

- filename:

  File name string (e.g. \`"isle_royale_layer.rds"\`).

- site:

  Target site/landscape directory name under \`extdata/\` (default:
  \`"isle_royale"\`).

## Value

Path to target cached dataset file.

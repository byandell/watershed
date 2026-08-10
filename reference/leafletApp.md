# Interactive Leaflet Mapping UI (Output)

Interactive Leaflet Mapping UI (Output)

Interactive Leaflet Mapping Server Logic Server logic for interactive
Leaflet discovery. Returns a list of reactives (\`huc\`, \`status\`,
\`click\`, \`drawn_polygon\`) enabling Shiny module composition.

Run the Leaflet Mapping Integration App Tracker

## Usage

``` r
leafletOutput(id)

leafletServer(id, max_hucs = 6)

leafletApp()
```

## Arguments

- id:

  Module ID

- max_hucs:

  Maximum target number of HUC regions when searching drawn polygon
  extent (default: 6, can be a numeric or reactive).

## Value

A list of reactive objects: \`huc\` (reactiveVal holding discovered
\`sf\` HUC polygon(s)), \`status\` (reactiveVal holding HTML status
message), \`click\` (reactive holding map click details), and
\`drawn_polygon\` (reactiveVal holding user drawn rubberband polygon
sf).

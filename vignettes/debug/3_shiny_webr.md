# Shiny / WebR reactive flow issues

Since iframe communication, event listeners, and CSS layers have been ruled out, the issue is almost certainly due to **how Shiny / webR handles state binding with Leaflet inputs** or **a mismatch between input IDs and reactive observers**.

Here are the specific structural causes in Shiny/webR interactive maps and how to fix them:

---

### 1. `leaflet` Default Event ID Mismatch

When using standard `leaflet` in Shiny, shape clicks automatically create an input named `<map_id>_shape_click` (e.g., if your map output is `leafletOutput("map")`, the input created in R is `input$map_shape_click`).

* **The Problem:** If you are using custom JavaScript to set `Shiny.setInputValue('selected_hucs', ...)` or listening to `input$map_shape_click`, the click payload returns a list containing `id` (or `group`), `lat`, and `lng`. If `layerId` was not explicitly set when adding shapes, `input$map_shape_click$id` returns `NULL`.
* **Fix:** Ensure each polygon/shape has a explicit `layerId` assigned during map rendering:

```r
leafletProxy("map") %>%
  addPolygons(
    data = subwatersheds,
    layerId = ~huc_code,  # <--- CRITICAL: Must assign layerId so click event carries the HUC code
    label = ~huc_code,
    popup = ~paste0("HUC: ", huc_code, "<br><button onclick=\"Shiny.setInputValue('toggle_huc', '", huc_code, "', {priority: 'event'})\">Toggle</button>")
  )

```

---

### 2. Standard `textInput` Override on Redraw / Search

Looking at your interface, the text field `Selected HUC Watershed(s)` contains `04030204, 04030201, 04030202, 04030203`.

* **The Problem:** If your reactive server logic updates a `reactiveVal()` on click, but you use `updateTextInput(session, "selected_hucs", value = ...)` without isolating the reactive dependency, any surrounding map redraw (or region search) might immediately overwrite the input back to its default region search results.
* **Fix:** Use `isolate()` when reading the current selection inside the click observer:

```r
# Reactive value storing active selection
selected_hucs <- reactiveVal(c("04030204", "04030201", "04030202", "04030203"))

# Listen for shape clicks
observeEvent(input$map_shape_click, {
  clicked_id <- input$map_shape_click$id
  req(clicked_id)

  current <- isolate(selected_hucs())

  if (clicked_id %in% current) {
    updated <- setdiff(current, clicked_id)
  } else {
    updated <- c(current, clicked_id)
  }

  selected_hucs(updated)
  updateTextInput(session, "selected_hucs_input", value = paste(updated, collapse = ", "))
})

```

---

### 3. WebAssembly / webR Namespace Isolation

If this app runs client-side via **Shinylive / webR**:

* **The Problem:** JS-to-R bindings via `Shiny.setInputValue()` inside webR can fail silently if `Shiny` isn't attached to the parent `window` scope inside the WebAssembly worker thread.
* **Fix:** Bind the event handler directly in R using `htmlwidgets::onRender` rather than external scripts or inline HTML strings:

```r
leaflet(data = subwatersheds) %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  addPolygons(
    layerId = ~huc_code,
    fillColor = "#8a4baf",
    weight = 2
  ) %>%
  htmlwidgets::onRender("
    function(el, x) {
      var map = this;
      map.on('shape_click', function(e) {
        // Explicit webR parent scope notification
        if (window.Shiny) {
          Shiny.setInputValue('map_shape_click', {id: e.id}, {priority: 'event'});
        }
      });
    }
  ")

```

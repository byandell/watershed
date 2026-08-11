# Event Delegation Issue

This exact behavior (where *any* click on *any* polygon target always operates on the exact same subwatershed ID repeatedly) occurs when **event delegation is hitting the wrong element container** or **a reactive value binding is evaluating a single hardcoded/first element in the vector**.

Here are the specific, pinpointed causes and structural fixes for this:

---

### 1. The `event.target` vs. `event.currentTarget` Trap in JS

If you are passing the event back to Shiny using a JS handler on the map or layer group, `event.target` refers to the exact SVG path clicked, while `event.currentTarget` or `this` refers to the parent layer container.

* **The Problem:** If the callback extracts `feature.properties` or `layerId` from the container/parent layer rather than the clicked path target, it will always return the ID of the **first feature instantiated in that layer group**.
* **Fix:** Access the properties strictly from `e.layer` or `e.target`:

```javascript
// Fix inside custom Leaflet JS handler
map.on('click', function(e) {
  // DO NOT use map or layerGroup properties here
});

// Attach directly to each feature in onEachFeature
function onEachFeature(feature, layer) {
  layer.on('click', function(e) {
    // e.target guarantees the exact clicked polygon feature
    var clickedHuc = e.target.feature.properties.huc8 || e.target.feature.properties.huc_code;

    if (window.Shiny) {
      Shiny.setInputValue('map_shape_click', {
        id: clickedHuc,
        nonce: Math.random() // Guarantees Shiny registers new events even if same value
      }, {priority: 'event'});
    }
  });
}

```

---

### 2. Standard Shiny `input$map_shape_click` Vector/List Indexing

In R, if you assign `layerId = ~huc_code` inside `addPolygons()`, but `huc_code` is formatted as a factor, integer array, or row name vector rather than an explicit plain character vector:

* **The Problem:** R's C-bridge returns the factor index (e.g., `1`) instead of the string value (`"04030204"`). If your server logic accesses `subwatersheds$huc_code[input$map_shape_click$id]` and receives `1` every time, it will continually toggle the first subwatershed in the array.
* **Fix:** Convert the ID column explicitly to character before passing it to `addPolygons()`:

```r
# In R server
subwatersheds_sf$huc_id_str <- as.character(subwatersheds_sf$huc8) # or huc_code

leafletProxy("map") %>%
  clearShapes() %>%
  addPolygons(
    data = subwatersheds_sf,
    layerId = ~huc_id_str, # Use explicit character column
    # ...
  )

```

---

### 3. Duplicate Spatial Objects / MultiPolygon Binding

If the GeoJSON dataset contains MultiPolygons or multiple features with identical or missing `layerId` properties:

* **The Problem:** Leaflet registers all geometry paths under the same DOM key. Whichever polygon is rendered first in the DOM tree receives all click events for the entire group.
* **Fix:** Ensure each polygon feature has a unique string ID. If you have disjoint subwatershed shapes, dissolve/union them into single spatial features prior to sending them to the map:

```r
library(dplyr)
# Group by HUC ID to ensure 1 feature = 1 layerId
subwatersheds_sf <- subwatersheds_sf %>%
  group_by(huc8) %>%
  summarise(geometry = sf::st_union(geometry), .groups = "drop")

```

---

### Quick Verification Test

Add a brief print statement right at the start of your server event listener to verify what `input$map_shape_click` is actually delivering:

```r
observeEvent(input$map_shape_click, {
  cat("RECEIVED CLICK PAYLOAD:\n")
  print(input$map_shape_click)
})

```

* If clicking different polygons prints the **same `id**` $\rightarrow$ Fix **Cause #1** (JS event target scope) or **Cause #3** (DOM polygon stacking).
* If clicking different polygons prints **`id = 1` or integers** $\rightarrow$ Fix **Cause #2** (Factor indexing/string conversion).

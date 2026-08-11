# Stale Closure Event

## Prompt

Issue changed. Select any subwatershed and it always removes (deselects) the same one then re-selects it.

## Response

When a selection event **always acts on the exact same subwatershed ID regardless of where you click**, it means the click handler is evaluating a **stale closure variable**, reading an **un-updated global state**, or using a **hardcoded fallback ID** in the callback payload.

Here are the specific root causes for this behavior and how to fix them:

---

### 1. Fixed Variable in Event Listener Closure

If you added your click listener inside a loop or function during layer instantiation, JavaScript closures often capture the initial feature properties (e.g., the first HUC in the dataset) or reference a single mutable variable.

* **The Problem:** Every shape gets assigned an event handler that closes over the *first* HUC ID evaluated during layer setup.
* **Fix:** Access the feature ID dynamically from the event target (`e.target`) rather than relying on outer-scope variables:

```javascript
// BAD: Captures `huc_code` from loop scope, leading to stale ID binding
layer.on('click', function() {
  Shiny.setInputValue('map_shape_click', { id: huc_code }, { priority: 'event' });
});

// GOOD: Pulls ID directly from the clicked target layer at runtime
layer.on('click', function(e) {
  var clickedId = e.target.feature.properties.huc_code || e.target.options.layerId;
  if (window.Shiny) {
    Shiny.setInputValue('map_shape_click', { id: clickedId, nonce: Math.random() }, { priority: 'event' });
  }
});

```

---

### 2. Hardcoded / Default Input Fallback in Backend

In your server logic (R `server.R` or Python `app.py`), check where `input$map_shape_click` or your custom input is parsed.

* **The Problem:** If `clicked_id` evaluates to `NULL` or `None` (because the shape ID property key name doesn't match `layerId`), your server script might be falling back to a default value (e.g., `clicked_id <- input$map_shape_click$id %||% "04030204"`).
* **Fix:** Inspect the shape click payload structure and enforce strict validation:

```r
observeEvent(input$map_shape_click, {
  # Print payload to debug output to ensure the clicked layer ID is actually passing through
  # print(input$map_shape_click)

  clicked_id <- input$map_shape_click$id

  # Do NOT process if the clicked ID is NULL or empty
  req(clicked_id)

  # Ensure clicked_id is converted to character matching your dataset
  clicked_id <- as.character(clicked_id)

  # ... update state ...
})

```

---

### 3. Duplicate DOM IDs or Overlapping Geometry Stack

If `leafletProxy()` has been called multiple times without purging existing layers (`clearShapes()` / `clearGroup()`), duplicate vector layers sit directly on top of each other in the DOM.

* **The Problem:** The browser's hit testing always clicks the topmost layer in the SVG DOM tree. If an old layer (e.g., subwatershed `04030204`) was re-added last or covers the viewport, it intercepts all pointer clicks across the map.
* **Fix:** Clear layer groups prior to drawing updated states:

```r
leafletProxy("map") %>%
  clearGroup("subwatersheds") %>%  # Purge existing DOM elements
  addPolygons(
    data = subwatersheds_sf,
    layerId = ~as.character(huc_code),
    group = "subwatersheds",
    # ...
  )

```

---

### Quick Debugging Check

To immediately isolate whether this is a **JavaScript/Leaflet problem** or an **R/Python server state problem**:

1. Add `console.log(e.target.feature.properties.huc_code)` inside your Leaflet `click` event.
2. Click different subwatersheds on the map.
3. If the browser console logs different HUC IDs, the bug is on the **server side** (fallback ID / reactive state mismatch). If it logs the same HUC ID repeatedly, the bug is on the **frontend event binding** (JS closure scope).

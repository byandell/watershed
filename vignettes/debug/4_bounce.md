# Bounce

## Prompt

Now it is mostly working, but when I click on a subwatershed, there are 2-3 cycles of zoom-in, zoom-out.

## Response

This classic "bounce" or zoom-loop behavior happens when a click event triggers a reactive chain that **re-renders the map layer and forces a view reset** (`fitBounds` or `setView`), which in turn re-fires a map movement/click event or causes Leaflet to recalculate bounds dynamically.

Here are the primary causes in Shiny / Leaflet apps and how to stop the bouncing:

---

### 1. Auto-fitting Bounds on Layer Re-render

When a subwatershed shape is clicked and toggled, the backend updates the dataset and re-renders the map polygons via `leafletProxy`. If your rendering function includes `fitBounds()` or `flyToBounds()`, Leaflet resets the zoom scale every time the selection state changes.

* **Fix:** Remove explicit `fitBounds()` or `flyToBounds()` calls from the observer that handles shape toggles. Alternatively, wrap bounds fitting so it only fires when searching a new bounding box region, not when toggling shapes:

```r
# BAD: Resets map view every time selected_hucs changes
observeEvent(selected_hucs(), {
  leafletProxy("map") %>%
    clearShapes() %>%
    addPolygons(data = filtered_data()) %>%
    fitBounds(...) # <--- REMOVE THIS
})

# GOOD: Preserve view state on shape update
observeEvent(input$map_shape_click, {
  # Toggle selection logic...

  leafletProxy("map") %>%
    # Replace/update styles or layers WITHOUT resetting view/bounds
    addPolygons(
      data = updated_shapes,
      layerId = ~huc_code,
      color = ~ifelse(huc_code %in% active_hucs, "purple", "red")
    )
})

```

---

### 2. Double Event Trigger (`click` + `shape_click` / Map Bounds Observer)

In `leaflet`, clicking a polygon fires **both** `input$map_shape_click` AND a general `input$map_click` / `input$map_bounds` event. If you have an observer listening to map bounds or map clicks to recalculate region features, clicking a shape causes a race condition:

1. Shape click toggles selection state.
2. Selection state changes $\rightarrow$ Map redraws or updates.
3. Map update alters bounds slightly or triggers a map view event.
4. Bounds observer re-executes region identification, causing a second zoom/redraw cycle.

* **Fix:** Isolate map bounds dependencies inside your toggle observers using `isolate()`:

```r
observeEvent(input$map_shape_click, {
  clicked_id <- input$map_shape_click$id
  req(clicked_id)

  # Isolate current map bounds/zoom so map movement doesn't trigger a re-render loop
  current_bounds <- isolate(input$map_bounds)

  # Process toggle without reacting to zoom/bounds changes
})

```

---

### 3. Leaflet Smooth Zoom & Animation Collisions

If you have map transition animations or `flyTo` enabled while updating layer styles, Leaflet fires `zoomstart` and `zoomend` events mid-transition. If your map rendering pipeline listens to `zoomend`, it will catch the intermediate zoom step and issue another draw call.

* **Fix:** Disable animate/fly transitions when updating existing vector layers:

```javascript
// JS side if using custom Leaflet logic:
map.setView(center, zoom, { animate: false });

```

Or in R `leafletProxy`:

```r
# Use setView with animate = FALSE or simply update layer styles using setStyle via JS

```

---

### 4. Optimal Fix: Update Layer Styles (`setStyle`) Instead of Redrawing

Rather than wiping and re-adding polygons on click (which resets layer event listeners and forces Leaflet to re-calculate SVG paths), use `leaflet.extras` or a short JS call to mutate only the stroke/fill of the clicked shape client-side:

```javascript
// JS helper to toggle style directly without triggering map redraws
function toggleShapeStyle(layer, isExcluded) {
  if (isExcluded) {
    layer.setStyle({ color: 'red', dashArray: '5, 5', fillOpacity: 0.2 });
  } else {
    layer.setStyle({ color: 'purple', dashArray: null, fillOpacity: 0.5 });
  }
}

```

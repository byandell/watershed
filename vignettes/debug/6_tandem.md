# Tandem issues

When **flickering (double/triple execution)** and **targeting the wrong subwatershed** persist together in Shiny/webR Leaflet apps, it indicates two distinct issues happening in tandem:

1. **The Wrong Selection:** Your layer spatial order / array index does not match the `layerId` sequence, or vector layers are stacking on top of each other without being purged.
2. **The Flickering:** Rapid re-execution of reactive observers (`observeEvent`) caused by reactive circular dependencies or duplicate JS event propagation.

---

### Phase 1: Fix Wrong Selection (Fix the `layerId` Mapping)

Leaflet vector layers assign clicks based on internal layer registration order unless explicitly indexed. If `layerId` is assigned dynamically from a reactive dataframe whose row order shifts, `input$map_shape_click$id` receives the **index** or **previous layer's ID** instead of the clicked polygon's ID.

#### 1. Explicit String Casting & `clearShapes()`

Always call `clearShapes()` (or `clearGroup()`) *before* adding polygons, and force the `layerId` to be a unique **character vector**, not an integer/factor.

```r
# Inside your map update observer:
leafletProxy("map") %>%
  clearShapes() %>% # MUST purge existing SVGs so click targets aren't stacked
  addPolygons(
    data = subwatersheds_sf,
    layerId = ~as.character(huc_code), # Force explicit string ID
    group = "subwatersheds",
    fillColor = ~ifelse(huc_code %in% selected_hucs, "#8a4baf", "#e74c3c"),
    stroke = TRUE,
    weight = 2
  )

```

#### 2. Verify Spatial Object Keys (`sf` Data Frame)

Ensure your `sf` spatial dataframe does not contain duplicate HUC codes in its rows when `addPolygons` is called. Duplicate `layerId` values cause Leaflet to map all events to the first matching DOM node, resulting in the wrong shape being toggled.

---

### Phase 2: Fix Flickering (Stop the Observer Loop)

Flickering (ON $\rightarrow$ OFF $\rightarrow$ ON) happens when `input$map_shape_click` fires, updates a reactive value, and that reactive value triggers another update which re-fires the map click event or invalidates `input$map_shape_click`.

#### 1. Ignore `NULL` and Duplicate Inputs with `req()` and `isolate()`

Isolate all reactive state reads inside the click handler so map updates don't cause the observer to self-trigger.

```r
observeEvent(input$map_shape_click, {
  # 1. Require a valid shape ID payload
  req(input$map_shape_click$id)
  
  clicked_huc <- as.character(input$map_shape_click$id)
  
  # 2. Isolate current selection to break reactive loops
  current_selected <- isolate(selected_hucs())
  
  # 3. Explicit set operations instead of flip-flopping
  if (clicked_huc %in% current_selected) {
    new_selected <- setdiff(current_selected, clicked_huc)
  } else {
    new_selected <- union(current_selected, clicked_huc)
  }
  
  # Update reactive value once
  selected_hucs(new_selected)
}, ignoreInit = TRUE)

```

#### 2. Prevent Event Bubbling in Custom Popups

If users are clicking a button inside a Leaflet popup balloon, the popup click often triggers **both** the button `onclick` function and the underlying Leaflet polygon `click` event simultaneously.

In your HTML popup template, stop event propagation:

```html
<button onclick="
  event.stopPropagation(); 
  Shiny.setInputValue('toggled_huc', '04030201', {priority: 'event'});
">
  Toggle Exclusion
</button>

```

---

### Phase 3: The Zero-Redraw Solution (Client-Side JS Styling)

To completely eliminate re-render flickering, stop destroying and re-adding spatial polygons on click altogether. Instead, pass **only the updated state** to JavaScript and let Leaflet update the CSS stroke/fill natively:

```javascript
// Add this JS helper to your app
Shiny.addCustomMessageHandler('highlight_hucs', function(selected_ids) {
  var map = HTMLWidgets.find('#map').getMap();
  map.eachLayer(function(layer) {
    if (layer.options && layer.options.layerId) {
      var isSelected = selected_ids.includes(layer.options.layerId);
      layer.setStyle({
        fillColor: isSelected ? '#8a4baf' : '#e74c3c',
        dashArray: isSelected ? null : '5, 5'
      });
    }
  });
});

```

Then call it from R/Python without triggering any Leaflet layer redraws:

```r
observeEvent(selected_hucs(), {
  session$sendCustomMessage("highlight_hucs", selected_hucs())
})

```

# Stale Click Event

## Prompt

Zoom fixed, but image flickers (redrawn?) 2-3 times, turning selection on/off for a subwatershed. Also, the wrong subwatershed is often (not always) selected.

## Response

That flickering (visual toggling on/off) combined with intermittently selecting the wrong subwatershed points directly to **stale click event queueing** and **ID mismatching during reactive re-renders**.

Here is what is happening under the hood and how to fix both issues:

---

### 1. Fixing the Flickering: Double Event Fire & Stale Callback Queue

When you click a shape, multiple event listeners are likely firing simultaneously (e.g., both `shape_click` and an inline popup `onclick`), or the click event is being re-emitted during layer re-rendering.

* **Why it flickers on/off:** The backend gets two or three consecutive toggle events for the same HUC ID within milliseconds (Toggle ON $\rightarrow$ Toggle OFF $\rightarrow$ Toggle ON).
* **Fix:** Debounce the input in Shiny or handle state explicitly rather than toggling boolean values blindly:

```r
# BAD: Standard toggle flip-flops rapidly if clicked twice in short succession
current <- isolate(selected_hucs())
if (clicked_id %in% current) {
  selected_hucs(setdiff(current, clicked_id))
} else {
  selected_hucs(c(current, clicked_id))
}

# GOOD: Debounce or throttle the input event in R/Python
toggled_id <- reactive(input$map_shape_click$id) %>% debounce(250)

```

---

### 2. Fixing the Wrong Selection: Shared Layer IDs or Index-Based Matching

When vector polygons are dynamically updated using `leafletProxy()`, Leaflet tracks shapes by `layerId`. If `layerId` isn't assigned cleanly, or if the spatial data source ordering shifts during reactive filtering, Leaflet defaults to feature array indices (0, 1, 2...), leading to wrong shapes being targeted.

* **Fix 1 — Ensure explicit string `layerId`:**
Make sure every polygon is bound to its unique HUC string explicitly when adding or updating shapes:

```r
leafletProxy("map") %>%
  addPolygons(
    data = subwatersheds_sf,
    layerId = ~as.character(huc_code), # Force explicit string ID
    group = "subwatersheds",
    fillColor = ~ifelse(huc_code %in% selected_hucs, "#8a4baf", "#e74c3c"),
    # ...
  )

```

* **Fix 2 — Clear existing shapes before replacing:**
If you are using `addPolygons` without clearing the previous group, duplicate layers accumulate on top of each other. Clicking targets whichever layer happens to be higher in the DOM z-index, which may be an outdated layer with an old state.

```r
leafletProxy("map") %>%
  clearGroup("subwatersheds") %>%  # Always clear the specific layer group first
  addPolygons(
    data = subwatersheds_sf,
    layerId = ~as.character(huc_code),
    group = "subwatersheds"
  )

```

---

### 3. Best Practice Fix: Mutate CSS with JavaScript (`setStyle`)

To permanently eliminate re-render flickering, don't re-add spatial layers to the map on click at all. Pushing spatial vectors across the webR / R worker bridge on every click is slow and triggers visual redraws.

Instead, update the state in R and use `leaflet::invoke` or standard Leaflet `setStyle` to change color client-side:

```javascript
// JS helper to toggle styling instantly without re-rendering spatial objects
function updateHucStyle(hucId, isSelected) {
  var map = HTMLWidgets.find('#map').getMap();
  map.eachLayer(function(layer) {
    if (layer.options && layer.options.layerId === hucId) {
      layer.setStyle({
        fillColor: isSelected ? '#8a4baf' : '#e74c3c',
        dashArray: isSelected ? null : '5, 5'
      });
    }
  });
}

```

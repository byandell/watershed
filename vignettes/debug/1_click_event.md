# Click event debugging

## Prompt

App says "Click any shape on map or popup button to toggle inclusion/exclusion." but it has no effect.

## Response

This behavior usually occurs due to one of three common issues in interactive Leaflet web applications:

---

### 1. The Map is Embedded in an `<iframe>`

As shown in the app structure, the Leaflet map is rendered inside an isolated `<iframe>`.

* **The Problem:** Click events triggered on Leaflet shapes inside an iframe stay within that iframe's DOM scope. If your backend state manager or main window script listens for events on the parent window, it never receives the click.
* **Fix:** Use `window.parent.postMessage()` inside the iframe's Leaflet click handler to send the shape ID/HUC code up to the host application, and listen for the message in the parent document:

```javascript
// Inside the iframe map script:
layer.on('click', function(e) {
  window.parent.postMessage({ type: 'TOGGLE_HUC', hucId: e.target.feature.properties.huc8 }, '*');
});

// In the parent application:
window.addEventListener('message', function(event) {
  if (event.data.type === 'TOGGLE_HUC') {
    // Logic to add/remove HUC from Selected HUC Watersheds
  }
});

```

---

### 2. Missing Vector Layer Interactivity

Leaflet vector layers (GeoJSON polygons) might be rendered without click listeners or set to non-interactive.

* **The Problem:** If `interactive: false` is set in the layer options, or if no `layer.on('click', ...)` binding is attached during layer instantiation, the map swallows the click event.
* **Fix:** Ensure `interactive: true` is enabled on the polygon layer and attach the click listener directly when parsing GeoJSON features (`onEachFeature`):

```javascript
L.geoJSON(geojsonData, {
  interactive: true,
  onEachFeature: function (feature, layer) {
    layer.on('click', function () {
      toggleSubwatershed(feature.properties.huc_code);
    });
  }
}).addTo(map);

```

---

### 3. Dynamic Popup Button Event Delegation

If users are clicking a button inside a Leaflet popup balloon:

* **The Problem:** Leaflet popups dynamically inject HTML into the DOM when opened. If you attached event listeners when the page loaded, those listeners won't exist on the newly created popup button.
* **Fix:** Delegate event listening to the map container or use Leaflet's `popupopen` event:

```javascript
map.on('popupopen', function(e) {
  const btn = e.popup.getElement().querySelector('.toggle-btn');
  if (btn) {
    btn.onclick = function() {
      toggleSubwatershed(btn.dataset.huc);
    };
  }
});

```

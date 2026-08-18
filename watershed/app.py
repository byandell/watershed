"""
Shiny for Python interactive hexagonal watershed application module (`watershedApp`).
"""

import html
import json
import time
import folium
from folium.plugins import Draw, Fullscreen, MeasureControl, Geocoder
import matplotlib.pyplot as plt
import geopandas as gpd
from shapely.geometry import box
from shiny import App, ui, render, reactive
from watershed.watershed import get_watershed, get_huc, get_hucs_from_polygon
from watershed.grid import make_hex_grid
from watershed.habitat import get_habitat_features, score_habitat_grid
from watershed.leaflet import build_leaflet_map, autoplot, DrawListener, HucClickListener

app_ui = ui.page_sidebar(
    ui.sidebar(
        ui.tags.script("""
            function toggleHucId(clickedId) {
                var hucElem = document.getElementById('huc_id');
                if (!hucElem) return;
                
                var currentVal = hucElem.value || '';
                var currentIds = currentVal.split(',').map(function(x) { return x.trim(); }).filter(function(x) { return x.length > 0; });
                
                var cleanId = String(clickedId).trim();
                var idx = currentIds.indexOf(cleanId);
                var isSelected = false;
                if (idx >= 0) {
                    currentIds.splice(idx, 1);
                    isSelected = false;
                } else {
                    currentIds.push(cleanId);
                    isSelected = true;
                }
                var newVal = currentIds.join(', ');
                
                hucElem.value = newVal;

                // Phase 3 Zero-Redraw Client-Side Style Mutator
                try {
                    var iframe = document.querySelector('iframe');
                    if (iframe && iframe.contentWindow && iframe.contentWindow.updateHucStyle) {
                        iframe.contentWindow.updateHucStyle(cleanId, isSelected);
                    }
                } catch(err) {}

                // Trigger Shiny setInputValue with priority event and nonce object per shiny_python.md & tandem.md
                if (window.Shiny && window.Shiny.setInputValue) {
                    try { window.Shiny.setInputValue('huc_id', newVal); } catch(e) {}
                    try { window.Shiny.setInputValue('toggled_huc', { id: cleanId, is_selected: isSelected, nonce: Math.random() }, { priority: 'event' }); } catch(e) {}
                }

                // Trigger jQuery change & input events
                var jq = window.jQuery || window.$;
                if (jq) {
                    try { jq(hucElem).val(newVal).trigger('change').trigger('input'); } catch(e) {}
                }

                // Fallback vanilla DOM events
                try {
                    hucElem.dispatchEvent(new Event('input', { bubbles: true }));
                    hucElem.dispatchEvent(new Event('change', { bubbles: true }));
                } catch(e) {}
            }
            window.toggleHucId = toggleHucId;

            window.addEventListener('message', function(event) {
                var d = event.data;
                if (typeof d === 'string') {
                    try { d = JSON.parse(d); } catch(e) {}
                }
                if (d && (d.type === 'TOGGLE_HUC' || d.type === 'hexmap_huc_clicked')) {
                    var targetId = d.hucId || d.huc_id;
                    if (targetId) {
                        toggleHucId(targetId);
                    }
                } else if (d && d.type === 'hexmap_draw_created') {
                    var w = document.getElementById('bbox_west');
                    var s = document.getElementById('bbox_south');
                    var e = document.getElementById('bbox_east');
                    var n = document.getElementById('bbox_north');
                    if (w && s && e && n) {
                        w.value = d.west.toFixed(5);
                        s.value = d.south.toFixed(5);
                        e.value = d.east.toFixed(5);
                        n.value = d.north.toFixed(5);
                        var jq = window.jQuery || window.$;
                        if (jq) {
                            try { jq(w).trigger('change'); jq(s).trigger('change'); jq(e).trigger('change'); jq(n).trigger('change'); } catch(err) {}
                        }
                    }
                    var btn = document.getElementById('btn_search_region');
                    if (btn) {
                        setTimeout(function() { btn.click(); }, 150);
                    }
                }
            });
        """),
        ui.h4("Hexagonal Watershed Controls"),
        ui.p("Configure subwatershed parameters, geometric hexagon density, and habitat overlays."),
        ui.input_slider("huc_level", "HUC Digit Level:", min=2, max=12, value=8, step=2),
        ui.input_text("huc_id", "Selected HUC Watershed(s):", value="04180000"),
        ui.input_text("feature_name", "Geographic Feature Restriction (Optional):", value=""),
        ui.hr(),
        ui.input_checkbox("enable_hex", "Include Hexagonal Grid Overlay", value=True),
        ui.input_select(
            "n_hexagons",
            "Hexagons Mesh Resolution (N):",
            choices=["10", "20", "50", "100", "200", "500", "1000"],
            selected="100"
        ),
        ui.input_checkbox("show_habitat", "Overlay Habitat Features & Suitability Scoring", value=True),
        ui.hr(),
        ui.input_action_button("btn_update", "Generate Hex Topology", class_="btn-primary w-100 mt-2"),
        ui.download_button("download_topology", "Download GeoJSON Topology", class_="btn-secondary w-100 mt-2"),
        width=340,
    ),
    ui.navset_card_tab(
        ui.nav_panel(
            "Interactive Leaflet Grid",
            ui.div(
                ui.div(
                    ui.input_action_button(
                        "btn_search_region",
                        "Search Watersheds in Region",
                        class_="btn-success me-2 fw-bold"
                    ),
                    ui.input_action_button(
                        "btn_clear_region",
                        "Clear Region",
                        class_="btn-secondary me-3"
                    ),
                    ui.span(
                        "Click subwatershed shape or popup button to toggle. Draw a rectangle (top-left toolbar) to search a new region:",
                        class_="text-muted small align-self-center"
                    ),
                    class_="d-flex align-items-center mb-2 flex-wrap gap-2"
                ),
                ui.layout_columns(
                    ui.input_text("bbox_west", "West (Min Lon):", value=""),
                    ui.input_text("bbox_south", "South (Min Lat):", value=""),
                    ui.input_text("bbox_east", "East (Max Lon):", value=""),
                    ui.input_text("bbox_north", "North (Max Lat):", value=""),
                    col_widths=[3, 3, 3, 3]
                ),
                class_="mb-2 p-2 border rounded bg-light"
            ),
            ui.output_ui("regional_search_status"),
            ui.output_ui("leaflet_map_html")
        ),
        ui.nav_panel(
            "Static Autoplot (Matplotlib)",
            ui.output_plot("autoplot_render", height="600px")
        ),
        ui.nav_panel(
            "Topology & Substrate Metrics",
            ui.layout_columns(
                ui.card(
                    ui.card_header("Subwatershed Topology Summary"),
                    ui.output_text_verbatim("topology_summary")
                ),
                ui.card(
                    ui.card_header("Hexagon Mesh Metrics"),
                    ui.output_text_verbatim("grid_summary")
                )
            ),
            ui.card(
                ui.card_header("GeoJSON Topology Definition"),
                ui.output_text_verbatim("geojson_snippet")
            )
        )
    ),
    title="watershed: Interactive Hexagonal Watershed & Substrate Explorer",
)


def server(input, output, session):

    search_status_val = reactive.Value("")
    all_hucs_val = reactive.Value(None)

    @reactive.Effect
    @reactive.event(input.toggled_huc)
    def handle_toggled_huc():
        data = input.toggled_huc()
        if not data or not isinstance(data, dict):
            return
        
        clicked_id = str(data.get("id") or "").strip()
        if not clicked_id:
            return
        
        is_sel = data.get("is_selected", True)
        if is_sel:
            search_status_val.set(f'<div class="alert alert-success py-2 mb-2">Included subwatershed <b>{clicked_id}</b> (solid purple).</div>')
        else:
            search_status_val.set(f'<div class="alert alert-warning py-2 mb-2">Excluded subwatershed <b>{clicked_id}</b> (dashed red).</div>')

    @reactive.Effect
    @reactive.event(input.drawn_bounds)
    def handle_drawn_bounds():
        b = input.drawn_bounds()
        if not b:
            return
        try:
            w = float(b["west"])
            s = float(b["south"])
            e = float(b["east"])
            n = float(b["north"])

            ui.update_text("bbox_west", value=f"{w:.5f}")
            ui.update_text("bbox_south", value=f"{s:.5f}")
            ui.update_text("bbox_east", value=f"{e:.5f}")
            ui.update_text("bbox_north", value=f"{n:.5f}")

            poly_gdf = gpd.GeoDataFrame(geometry=[box(w, s, e, n)], crs="EPSG:4326")
            target_level = int(input.huc_level() or 8)
            found_hucs = get_hucs_from_polygon(poly_gdf, huc_level=target_level, max_hucs=10)

            if found_hucs is not None and len(found_hucs) > 0:
                huc_col = None
                for col in ["huc12", "huc10", "huc08", "huc8", "huc06", "huc04", "huc02", "id"]:
                    if col in found_hucs.columns:
                        huc_col = col
                        break
                if huc_col is None:
                    huc_col = found_hucs.columns[0]

                huc_ids = [str(x) for x in found_hucs[huc_col].unique()]
                id_str = ", ".join(huc_ids)

                all_hucs_val.set(found_hucs)
                ui.update_text("huc_id", value=id_str)
                ui.update_text("feature_name", value="")
                search_status_val.set(
                    f'<div class="alert alert-success py-2 mb-2">'
                    f'<b>Identified {len(huc_ids)} Subwatersheds in Drawn Region:</b> {id_str}<br/>'
                    f'<i>Click any shape on map or popup button to toggle inclusion/exclusion.</i>'
                    f'</div>'
                )
        except Exception as err:
            search_status_val.set(
                f'<div class="alert alert-danger py-2 mb-2">Error processing drawn bounds: {str(err)}</div>'
            )

    @reactive.Effect
    @reactive.event(input.btn_search_region)
    def handle_region_search():
        try:
            w_str = input.bbox_west()
            s_str = input.bbox_south()
            e_str = input.bbox_east()
            n_str = input.bbox_north()

            if not (w_str and s_str and e_str and n_str):
                search_status_val.set('<div class="alert alert-warning py-2 mb-2">Please enter bounding coordinates or draw a region on the map.</div>')
                return

            w, s, e, n = float(w_str), float(s_str), float(e_str), float(n_str)
            bbox_poly = box(w, s, e, n)
            poly_gdf = gpd.GeoDataFrame(geometry=[bbox_poly], crs="EPSG:4326")
            
            target_level = int(input.huc_level() or 8)
            found_hucs = get_hucs_from_polygon(poly_gdf, huc_level=target_level, max_hucs=10)
            
            if found_hucs is not None and len(found_hucs) > 0:
                huc_col = None
                for col in ["huc12", "huc10", "huc08", "huc8", "huc06", "huc04", "huc02", "id"]:
                    if col in found_hucs.columns:
                        huc_col = col
                        break
                if huc_col is None:
                    huc_col = found_hucs.columns[0]
                
                huc_ids = [str(x) for x in found_hucs[huc_col].unique()]
                id_str = ", ".join(huc_ids)
                
                all_hucs_val.set(found_hucs)
                ui.update_text("huc_id", value=id_str)
                ui.update_text("feature_name", value="")
                search_status_val.set(
                    f'<div class="alert alert-success py-2 mb-2">'
                    f'<b>Identified {len(huc_ids)} Subwatersheds in Region:</b> {id_str}<br/>'
                    f'<i>Click any shape on map or popup button to toggle inclusion/exclusion.</i>'
                    f'</div>'
                )
            else:
                search_status_val.set(
                    '<div class="alert alert-warning py-2 mb-2">No subwatersheds found in target region. Try adjusting bounding coordinates.</div>'
                )
        except Exception as err:
            search_status_val.set(
                f'<div class="alert alert-danger py-2 mb-2">Error searching region: {str(err)}</div>'
            )

    @reactive.Effect
    @reactive.event(input.btn_clear_region)
    def handle_clear_region():
        all_hucs_val.set(None)
        ui.update_text("huc_id", value="")
        ui.update_text("feature_name", value="")
        ui.update_text("bbox_west", value="")
        ui.update_text("bbox_south", value="")
        ui.update_text("bbox_east", value="")
        ui.update_text("bbox_north", value="")
        search_status_val.set('<div class="alert alert-info py-2 mb-2">Region cleared. Draw a region on the map or type a HUC ID.</div>')

    @output
    @render.ui
    def regional_search_status():
        msg = search_status_val.get()
        if msg:
            return ui.HTML(msg)
        return None

    @reactive.calc
    def topo_data():
        huc_val = input.huc_id()
        feat_val = input.feature_name() or None
        if not huc_val or not huc_val.strip():
            return None
        return get_watershed(huc_id=huc_val, feature_name=feat_val, all_hucs_layer=all_hucs_val.get())

    @reactive.calc
    def hex_grid_data():
        if not input.enable_hex():
            return None
        topo = topo_data()
        if topo is None:
            return None
        n_hex = int(input.n_hexagons() or 100)
        grid = make_hex_grid(topo.layer, n_hexagons=n_hex)
        
        if input.show_habitat():
            habitat_sf = get_habitat_features(topo.layer)
            grid = score_habitat_grid(grid, habitat_sf)
            
        return grid

    @output
    @render.ui
    def leaflet_map_html():
        topo = topo_data()
        if topo is None:
            m = folium.Map(location=[44.5, -89.5], zoom_start=6, tiles="CartoDB positron")
            Draw(export=True, position="topleft").add_to(m)
            Geocoder(position="topleft").add_to(m)
            Fullscreen(position="topleft").add_to(m)
            MeasureControl(position="topleft").add_to(m)
            folium.LayerControl(position="topright").add_to(m)
            DrawListener().add_to(m)
            HucClickListener().add_to(m)
            folium_map = m
        else:
            grid = hex_grid_data()
            huc_val = input.huc_id() or ""
            sel_ids = [x.strip() for x in huc_val.split(",") if x.strip()]
            folium_map = build_leaflet_map(topo, hex_grid=grid, selected_huc_ids=sel_ids)
        
        html_str = folium_map._repr_html_()
        start = html_str.find("<iframe")
        end = html_str.rfind("</iframe>")
        if start != -1 and end != -1:
            iframe_code = html_str[start : end + len("</iframe>")]
            iframe_code = iframe_code.replace(
                '<iframe ',
                '<iframe style="width:100%; height:580px; border:none;" '
            )
            return ui.HTML(iframe_code)
        return ui.HTML(html_str)

    @output
    @render.plot
    def autoplot_render():
        topo = topo_data()
        if topo is None:
            fig, ax = plt.subplots(figsize=(8.0, 7.0))
            ax.text(0.5, 0.5, "No Watershed Selected\n(Type a HUC ID or Draw a Region on Map)", ha="center", va="center", fontsize=14, color="gray")
            ax.axis("off")
            return fig
        grid = hex_grid_data()
        fig = autoplot(topo, hex_grid=grid)
        return fig

    @output
    @render.text
    def topology_summary():
        topo = topo_data()
        if topo is None:
            return "No Watershed Selected."
        huc_str = topo.huc_id if isinstance(topo.huc_id, str) else ", ".join(topo.huc_id)
        return (
            f"HUC Identifier(s):      {huc_str}\n"
            f"HUC Digit Level:        HUC{topo.huc_level:02d}\n"
            f"Centroid Longitude:     {topo.lon:.5f}\n"
            f"Centroid Latitude:      {topo.lat:.5f}\n"
            f"Feature Restriction:    {topo.feature_name or 'None'}\n"
            f"Subwatershed Polygons:  {len(topo.layer)}"
        )

    @output
    @render.text
    def grid_summary():
        grid = hex_grid_data()
        if grid is None:
            return "Hexagonal overlay grid disabled or no watershed selected."
        
        has_scoring = "suitability_score" in grid.columns
        score_str = f"Avg Suitability: {grid['suitability_score'].mean():.2f}" if has_scoring else "Scoring: N/A"
        return (
            f"Total Hexagons Generated: {len(grid)}\n"
            f"CRS:                      {grid.crs.to_string() if grid.crs else 'EPSG:4326'}\n"
            f"Geometry Type:            Polygon\n"
            f"Habitat Overlay:          {'Enabled' if input.show_habitat() else 'Disabled'}\n"
            f"{score_str}"
        )

    @output
    @render.text
    def geojson_snippet():
        topo = topo_data()
        if topo is None:
            return "No Watershed Selected."
        json_str = topo.layer.to_json()
        parsed = json.loads(json_str)
        return json.dumps(parsed, indent=2)[:1500] + "\n... [truncated]"

    @render.download(filename=lambda: f"watershed_topology_{input.huc_id() or 'custom'}.geojson")
    def download_topology():
        topo = topo_data()
        if topo is None:
            yield "{}"
        else:
            yield topo.layer.to_json()


app = App(app_ui, server)

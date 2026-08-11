"""
Interactive Folium and ipyleaflet mapping helpers, and matplotlib static autoplot visualization.
"""

from typing import Any
import folium
from folium.plugins import Draw, Fullscreen, MeasureControl, Geocoder
from branca.element import MacroElement
from jinja2 import Template
import geopandas as gpd
import matplotlib.pyplot as plt
from hexmap.watershed import HexmapTopology


class DrawListener(MacroElement):
    """
    Folium MacroElement that attaches a Javascript listener to Leaflet Draw events
    and posts drawn bounding box coordinates back to Shiny Python via postMessage.
    """
    _template = Template("""
        {% macro script(this, kwargs) %}
            setTimeout(function() {
                var maps = [];
                for (var key in window) {
                    if (key.startsWith("map_")) {
                        if (window[key] instanceof L.Map) {
                            maps.push(window[key]);
                        }
                    }
                }
                if (maps.length > 0) {
                    var map_obj = maps[0];
                    map_obj.on(L.Draw.Event.CREATED, function (e) {
                        var layer = e.layer;
                        var bounds = layer.getBounds ? layer.getBounds() : null;
                        if (!bounds) {
                            if (layer.getLatLng) {
                                var p = layer.getLatLng();
                                bounds = L.latLngBounds([p.lat - 0.05, p.lng - 0.05], [p.lat + 0.05, p.lng + 0.05]);
                            }
                        }
                        if (bounds) {
                            var msg = {
                                type: "hexmap_draw_created",
                                west: bounds.getWest(),
                                south: bounds.getSouth(),
                                east: bounds.getEast(),
                                north: bounds.getNorth()
                            };
                            try { window.parent.postMessage(msg, "*"); } catch(err) {}
                            try { window.top.postMessage(msg, "*"); } catch(err) {}
                        }
                    });
                }
            }, 800);
        {% endmacro %}
    """)


class HucClickListener(MacroElement):
    """
    Folium MacroElement implementing all fixes from vignettes/delegate.md:
    1. Leaf polygon target scope binding (skipping parent FeatureGroup containers).
    2. Explicit string huc_code resolution from e.target.feature.properties.
    3. Debounced execution and dynamic popup event delegation.
    """
    _template = Template("""
        {% macro script(this, kwargs) %}
            (function() {
                var maps = [];
                for (var key in window) {
                    if (key.startsWith("map_")) {
                        if (window[key] instanceof L.Map) {
                            maps.push(window[key]);
                        }
                    }
                }
                if (maps.length === 0) return;
                var map_obj = maps[0];
                var parentWin = window.parent || window.top;

                // Restore saved view position synchronously with animate: false to eliminate zoom bounce
                if (parentWin && parentWin._hexmap_view) {
                    var v = parentWin._hexmap_view;
                    map_obj.setView(v.center, v.zoom, {animate: false, reset: true});
                }

                // Track moveend after view initialization
                setTimeout(function() {
                    map_obj.on("moveend", function() {
                        if (parentWin) {
                            parentWin._hexmap_view = {
                                center: map_obj.getCenter(),
                                zoom: map_obj.getZoom()
                            };
                        }
                    });
                }, 300);

                // Zero-Redraw Client-Side Style Mutator
                function updateHucStyle(targetId, isSelected) {
                    map_obj.eachLayer(function(layer) {
                        if (layer.feature && layer.feature.properties) {
                            var props = layer.feature.properties;
                            var hid = props.huc_code || props.huc16 || props.huc14 || props.huc12 || props.huc10 || props.huc08 || props.huc8 || props.huc06 || props.huc04 || props.huc02;
                            if (String(hid) === String(targetId)) {
                                if (layer.setStyle) {
                                    layer.setStyle({
                                        fillColor: isSelected ? "#8E44AD" : "#E74C3C",
                                        fillOpacity: isSelected ? 0.12 : 0.08,
                                        color: isSelected ? "#8E44AD" : "#C0392B",
                                        weight: isSelected ? 2.0 : 2.5,
                                        dashArray: isSelected ? "0" : "6, 6"
                                    });
                                }
                            }
                        }
                    });
                }
                window.updateHucStyle = updateHucStyle;

                var lastToggleTime = 0;
                function sendToggleMessage(hucId) {
                    var now = Date.now();
                    if (now - lastToggleTime < 300) return;
                    lastToggleTime = now;

                    var msg = { type: "TOGGLE_HUC", hucId: String(hucId), nonce: Math.random() };
                    try { window.parent.postMessage(msg, "*"); } catch(err) {}
                    try { window.top.postMessage(msg, "*"); } catch(err) {}
                }

                // Interactive Vector Layer Click Listener attached STRICTLY to leaf polygon layers (vignettes/delegate.md #1)
                function attachClicks(parent) {
                    if (parent.eachLayer) {
                        parent.eachLayer(function(child) { attachClicks(child); });
                        return; // CRITICAL: Skip parent FeatureGroup container so clicks hit individual leaf polygons!
                    }
                    if (parent.feature && parent.feature.properties) {
                        var p = parent.feature.properties;
                        parent.off("click");
                        parent.on("click", function(e) {
                            if (e && e.originalEvent) {
                                e.originalEvent.stopPropagation();
                            }
                            var target = (e && e.target && e.target.feature && e.target.feature.properties) ? e.target : parent;
                            var props = target.feature.properties;
                            var clickedHuc = props.huc_code || props.huc16 || props.huc14 || props.huc12 || props.huc10 || props.huc08 || props.huc8 || props.huc06 || props.huc04 || props.huc02;
                            if (clickedHuc) {
                                sendToggleMessage(clickedHuc);
                            }
                        });
                    }
                }
                attachClicks(map_obj);

                // Global Document Event Delegation for dynamic popup buttons with stopPropagation
                document.addEventListener("click", function(evt) {
                    var target = evt.target;
                    if (target && target.classList && target.classList.contains("toggle-huc-btn")) {
                        var hid = target.getAttribute("data-huc");
                        if (hid) {
                            if (evt) {
                                evt.stopPropagation();
                                evt.preventDefault();
                            }
                            sendToggleMessage(hid);
                            return false;
                        }
                    }
                });
            })();
        {% endmacro %}
    """)


def build_leaflet_map(
    topology_obj: HexmapTopology,
    hex_grid: Any = None,
    hex_color: str = "#7F8C8D",
    bound_color: str = "#8E44AD",
    selected_huc_ids: list[str] | None = None
) -> folium.Map:
    """
    Generates an interactive Folium Leaflet map rendering HUC boundaries, gray hex grid overlays,
    individual component subwatersheds with purple (included) / crimson red (excluded) styling,
    and map toolbar controls.

    Parameters
    ----------
    topology_obj : HexmapTopology
        Watershed topology object containing layer and centroid metadata.
    hex_grid : gpd.GeoDataFrame | None
        Optional hexagonal grid overlay GeoDataFrame.
    hex_color : str
        Hexagon border line color (default: '#7F8C8D').
    bound_color : str
        Watershed outer boundary line color (default: '#8E44AD').
    selected_huc_ids : list[str] | None
        List of currently selected/included HUC IDs for interactive styling.

    Returns
    -------
    folium.Map
        Interactive Folium map instance with interactive toolbar controls.
    """
    m = folium.Map(
        location=[topology_obj.lat, topology_obj.lon],
        zoom_start=10,
        tiles="CartoDB positron"
    )

    # 1. Overlay spatial hex grid FIRST (behind boundary lines) in gray (pointerEvents: none)
    if hex_grid is not None and len(hex_grid) > 0:
        folium.GeoJson(
            hex_grid.__geo_interface__,
            name="Hexagonal Substrate Grid",
            style_function=lambda x: {
                "fillColor": "#34495E",
                "fillOpacity": 0,
                "color": hex_color,
                "weight": 1.0,
                "pointerEvents": "none"
            },
            tooltip=folium.GeoJsonTooltip(fields=["cell_id"] if "cell_id" in hex_grid.columns else [])
        ).add_to(m)

    # 2. Display individual component subwatershed boundaries with inclusion (purple) / exclusion (crimson) styling
    if topology_obj.individual_hucs is not None and len(topology_obj.individual_hucs) > 0:
        hucs_gdf = topology_obj.individual_hucs
        huc_col = None
        for col in ["huc16", "huc14", "huc12", "huc10", "huc08", "huc8", "huc06", "huc04", "huc02", "id"]:
            if col in hucs_gdf.columns:
                huc_col = col
                break
        if huc_col is None:
            huc_col = hucs_gdf.columns[0]

        # Phase 1 & Cause #3: Deduplicate spatial rows by HUC ID column to ensure unique layer IDs and zero DOM collisions
        hucs_gdf = hucs_gdf.drop_duplicates(subset=[huc_col]).copy()

        sel_set = set(selected_huc_ids) if selected_huc_ids else set()

        for idx, row in hucs_gdf.iterrows():
            hid = str(row[huc_col])
            hname = row["name"] if "name" in row and row["name"] else hid
            is_selected = (hid in sel_set) if sel_set else True
            
            style = {
                "fillColor": "#8E44AD" if is_selected else "#E74C3C",
                "fillOpacity": 0.12 if is_selected else 0.08,
                "color": "#8E44AD" if is_selected else "#C0392B",
                "weight": 2.0 if is_selected else 2.5,
                "dashArray": "0" if is_selected else "6, 6"
            }
            status_txt = "Included" if is_selected else "Excluded"
            btn_txt = "Exclude Subwatershed" if is_selected else "Include Subwatershed"
            color_txt = "#8E44AD" if is_selected else "#C0392B"
            
            toggle_js = f"if(event){{event.stopPropagation();event.preventDefault();}}try{{window.parent.postMessage({{type:'TOGGLE_HUC',hucId:'{hid}',nonce:Math.random()}},'*');}}catch(e){{}}try{{window.top.postMessage({{type:'TOGGLE_HUC',hucId:'{hid}',nonce:Math.random()}},'*');}}catch(e){{}}return false;"
            popup_html = (
                f"<div style='text-align:center; padding:4px; font-family:sans-serif;'>"
                f"<b>HUC: {hid}</b><br/>{hname}<br/>"
                f"<span style='color:{color_txt}; font-weight:bold;'>({status_txt})</span><br/>"
                f"<button class='toggle-huc-btn' data-huc='{hid}' onclick=\"{toggle_js}\" style=\"margin-top:6px; padding:6px 12px; cursor:pointer; background:{color_txt}; color:white; border:none; border-radius:4px; font-weight:bold; font-size:12px;\">{btn_txt}</button>"
                f"</div>"
            )

            row_dict = row.to_dict()
            row_dict["huc_code"] = hid
            sub_gdf = gpd.GeoDataFrame([row_dict], crs=hucs_gdf.crs)

            folium.GeoJson(
                sub_gdf.__geo_interface__,
                name=f"Subwatershed {hid}",
                style_function=lambda x, st=style: st,
                popup=folium.Popup(popup_html, max_width=250),
                tooltip=f"HUC: {hid} ({'Included' if is_selected else 'Excluded'})"
            ).add_to(m)

    # 3. Main combined watershed outer boundary ON TOP (purple #8E44AD, weight 2.0, pointerEvents: none)
    folium.GeoJson(
        topology_obj.layer.__geo_interface__,
        name="Combined Watershed Boundary",
        style_function=lambda x: {
            "fillColor": "#8E44AD",
            "fillOpacity": 0,
            "color": bound_color,
            "weight": 2.0,
            "pointerEvents": "none"
        }
    ).add_to(m)

    # 4. Interactive Leaflet Map Toolbar Controls (Draw, Search, Fullscreen, Measure)
    Draw(
        export=True,
        filename="drawn_region.geojson",
        position="topleft",
        draw_options={
            "polyline": False,
            "rectangle": True,
            "polygon": True,
            "circle": False,
            "marker": True,
            "circlemarker": False
        },
        edit_options={"edit": True, "remove": True}
    ).add_to(m)

    Geocoder(position="topleft", add_marker=True).add_to(m)
    Fullscreen(position="topleft").add_to(m)
    MeasureControl(position="topleft", primary_length_unit="kilometers").add_to(m)
    folium.LayerControl(position="topright").add_to(m)

    # Attach Draw and HUC Click listener macros
    DrawListener().add_to(m)
    HucClickListener().add_to(m)

    return m


def build_widget(
    topology_obj: HexmapTopology,
    hex_grid: Any = None
) -> Any:
    """
    Optional helper returning an ipyleaflet.Map widget if ipyleaflet is installed.

    Parameters
    ----------
    topology_obj : HexmapTopology
        Watershed topology object.
    hex_grid : gpd.GeoDataFrame | None
        Optional hexagonal grid overlay.

    Returns
    -------
    ipyleaflet.Map | folium.Map
        ipyleaflet Map widget instance, or falls back to folium.Map if ipyleaflet is missing.
    """
    try:
        import ipyleaflet
        m = ipyleaflet.Map(
            center=(topology_obj.lat, topology_obj.lon),
            zoom=10,
            basemap=ipyleaflet.basemaps.CartoDB.Positron
        )

        draw_control = ipyleaflet.DrawControl(
            polyline={},
            circlemarker={},
            polygon={"shapeOptions": {"color": "#6b03fc"}},
            rectangle={"shapeOptions": {"color": "#6b03fc"}},
            marker={"shapeOptions": {"color": "#6b03fc"}}
        )
        m.add_control(draw_control)

        if hex_grid is not None and len(hex_grid) > 0:
            geo_data = ipyleaflet.GeoData(
                geo_dataframe=hex_grid,
                style={"color": "#7F8C8D", "weight": 1, "fillOpacity": 0.1},
                name="Hex Grid"
            )
            m.add_layer(geo_data)

        bound_data = ipyleaflet.GeoData(
            geo_dataframe=topology_obj.layer,
            style={"color": "#8E44AD", "weight": 2.0, "fillOpacity": 0.15},
            name="Watershed Boundary"
        )
        m.add_layer(bound_data)
        m.add_control(ipyleaflet.LayersControl())
        return m
    except ImportError:
        return build_leaflet_map(topology_obj, hex_grid=hex_grid)


def autoplot(
    topology_obj: HexmapTopology,
    hex_grid: Any = None,
    figsize: tuple[float, float] = (8.0, 7.0)
) -> plt.Figure:
    """
    Generates a static Matplotlib figure mirroring R's ggplot2 autoplot for watershed hex overlays.

    Parameters
    ----------
    topology_obj : HexmapTopology
        Watershed topology object.
    hex_grid : gpd.GeoDataFrame | None
        Optional hexagonal grid GeoDataFrame.
    figsize : tuple[float, float]
        Matplotlib figure dimensions (width, height).

    Returns
    -------
    plt.Figure
        Static Matplotlib figure instance.
    """
    fig, ax = plt.subplots(figsize=figsize)

    # 1. Overlay spatial hex grid FIRST in gray
    if hex_grid is not None and len(hex_grid) > 0:
        hex_grid.plot(ax=ax, facecolor="none", edgecolor="#7F8C8D", linewidth=0.6)

    # 2. Display individual component subwatershed boundaries if multi-HUC
    if topology_obj.individual_hucs is not None and len(topology_obj.individual_hucs) > 1:
        topology_obj.individual_hucs.plot(ax=ax, facecolor="none", edgecolor="#8E44AD", linestyle="--", linewidth=1.0)

    # 3. Main combined boundary ON TOP (purple #8E44AD, weight 2.0)
    topology_obj.layer.plot(ax=ax, facecolor="none", edgecolor="#8E44AD", linewidth=2.0)

    huc_str = topology_obj.huc_id if isinstance(topology_obj.huc_id, str) else ", ".join(topology_obj.huc_id)
    title = f"Geographic Hexagonal Grid (HUC{topology_obj.huc_level}: {huc_str})"
    if topology_obj.feature_name:
        title += f"\nRestricted to: {topology_obj.feature_name}"

    ax.set_title(title, fontsize=11, fontweight="bold", pad=10)
    ax.set_xlabel("Longitude (deg)", fontsize=10)
    ax.set_ylabel("Latitude (deg)", fontsize=10)
    ax.grid(True, linestyle=":", alpha=0.5)

    fig.tight_layout()
    return fig

"""
Hexagonal substrate grid generation module with area-based cell diameter solver.
"""

import math
import numpy as np
import geopandas as gpd
from shapely.geometry import Polygon, box


def make_hex_grid(
    boundary_gdf: gpd.GeoDataFrame,
    n_hexagons: int = 100,
    hex_diameter: float | None = None
) -> gpd.GeoDataFrame:
    """
    Generates a spatial GeoDataFrame of regular hexagonal polygons covering the boundary.

    Uses area-based cell diameter formula d = sqrt(A / (0.65 * N)) if hex_diameter is None.

    Parameters
    ----------
    boundary_gdf : gpd.GeoDataFrame
        Boundary spatial polygon(s).
    n_hexagons : int
        Target count of hexagons (e.g. 10, 20, 50, 100, 200, 500, 1000). Default is 100.
    hex_diameter : float | None
        Explicit hexagon diameter in degrees. If None, calculated via area-based solver.

    Returns
    -------
    gpd.GeoDataFrame
        GeoDataFrame of hexagonal grid cell polygons.
    """
    bounds = boundary_gdf.total_bounds  # minx, miny, maxx, maxy
    minx, miny, maxx, maxy = bounds

    width = max(maxx - minx, 0.0001)
    height = max(maxy - miny, 0.0001)
    area = width * height

    if hex_diameter is None or hex_diameter <= 0:
        # Area-based diameter solver: d = sqrt(A / (0.65 * N))
        hex_diameter = math.sqrt(area / (0.65 * max(n_hexagons, 1)))

    radius = hex_diameter / 2.0
    # Center-to-center distances for regular pointy-topped or flat-topped hexagons
    dx = hex_diameter * 0.8660254  # sqrt(3)/2 * diameter
    dy = hex_diameter * 0.75

    # Buffer bounds slightly to ensure full coverage
    x_coords = np.arange(minx - radius, maxx + hex_diameter, dx)
    y_coords = np.arange(miny - radius, maxy + hex_diameter, dy)

    polygons = []
    cell_id = 1

    for i, y in enumerate(y_coords):
        x_offset = (dx / 2.0) if (i % 2 == 1) else 0.0
        for x in x_coords:
            cx = x + x_offset
            cy = y
            # Compute 6 vertices of hexagon
            angles = [math.radians(a) for a in range(30, 390, 60)]
            verts = [(cx + radius * math.cos(a), cy + radius * math.sin(a)) for a in angles]
            hex_poly = Polygon(verts)
            polygons.append({"cell_id": cell_id, "geometry": hex_poly})
            cell_id += 1

    grid_gdf = gpd.GeoDataFrame(polygons, crs=boundary_gdf.crs)

    # Spatially filter hexagons intersecting the watershed boundary
    try:
        intersected = gpd.sjoin(grid_gdf, boundary_gdf, predicate="intersects")
        clean_grid = grid_gdf.loc[grid_gdf["cell_id"].isin(intersected["cell_id"])].copy()
        clean_grid.reset_index(drop=True, inplace=True)
        return clean_grid
    except Exception:
        # Fallback if spatial join error occurs
        return grid_gdf

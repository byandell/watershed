"""
Unit tests for hexmap.grid module.
"""

import math
import pytest
import geopandas as gpd
from shapely.geometry import box
from hexmap.grid import make_hex_grid


def test_make_hex_grid_counts():
    poly = gpd.GeoDataFrame(geometry=[box(-89.0, 47.8, -88.8, 48.0)], crs="EPSG:4326")
    grid = make_hex_grid(poly, n_hexagons=50)

    assert isinstance(grid, gpd.GeoDataFrame)
    assert len(grid) > 0
    assert "cell_id" in grid.columns
    assert "geometry" in grid.columns


def test_make_hex_grid_explicit_diameter():
    poly = gpd.GeoDataFrame(geometry=[box(-89.0, 47.8, -88.8, 48.0)], crs="EPSG:4326")
    grid = make_hex_grid(poly, hex_diameter=0.05)

    assert isinstance(grid, gpd.GeoDataFrame)
    assert len(grid) > 0


def test_autoplot():
    from hexmap.watershed import get_watershed
    from hexmap.leaflet import autoplot
    import matplotlib.pyplot as plt

    topo = get_watershed("041800000101")
    grid = make_hex_grid(topo.layer, n_hexagons=20)
    fig = autoplot(topo, hex_grid=grid)

    assert isinstance(fig, plt.Figure)
    plt.close(fig)


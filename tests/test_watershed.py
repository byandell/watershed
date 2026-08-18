"""
Unit tests for watershed.watershed module.
"""

import pytest
import geopandas as gpd
from shapely.geometry import box
from watershed.watershed import (
    HexmapTopology,
    get_huc,
    get_hucs_from_polygon,
    get_watershed
)


def test_get_huc_basic():
    gdf = get_huc("041800000101", type="huc12")
    assert isinstance(gdf, gpd.GeoDataFrame)
    assert len(gdf) > 0
    assert gdf.crs is not None


def test_get_watershed_structure():
    topo = get_watershed("041800000101")
    assert isinstance(topo, HexmapTopology)
    assert topo.huc_id == "041800000101"
    assert isinstance(topo.layer, gpd.GeoDataFrame)
    assert isinstance(topo.lon, float)
    assert isinstance(topo.lat, float)


def test_get_hucs_from_polygon():
    polygon = gpd.GeoDataFrame(geometry=[box(-89.0, 47.8, -88.8, 48.0)], crs="EPSG:4326")
    hucs = get_hucs_from_polygon(polygon, huc_level=8, max_hucs=6)
    assert isinstance(hucs, gpd.GeoDataFrame)
    assert len(hucs) > 0

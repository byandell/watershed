"""
hexmap: Interactive Hexagonal Watershed Mapping and Spatial Substrate Projection
"""

__version__ = "0.3.1"

from hexmap.watershed import (
    HexmapTopology,
    get_huc,
    get_hucs_from_polygon,
    get_watershed,
)
from hexmap.grid import make_hex_grid
from hexmap.habitat import get_habitat_features, score_habitat_grid
from hexmap.leaflet import build_leaflet_map, build_widget, autoplot
from hexmap.io import save_topology, load_topology
from hexmap.cli import launch_app

__all__ = [
    "__version__",
    "HexmapTopology",
    "get_huc",
    "get_hucs_from_polygon",
    "get_watershed",
    "make_hex_grid",
    "get_habitat_features",
    "score_habitat_grid",
    "build_leaflet_map",
    "build_widget",
    "autoplot",
    "save_topology",
    "load_topology",
    "launch_app",
]

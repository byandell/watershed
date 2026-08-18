"""
Topology object serialization and deserialization utilities.
"""

import json
from pathlib import Path
import geopandas as gpd
from watershed.watershed import HexmapTopology


def save_topology(topo: HexmapTopology, filepath: str | Path) -> None:
    """
    Serializes a HexmapTopology object to a GeoJSON or GeoPackage file.

    Parameters
    ----------
    topo : HexmapTopology
        The topology object to serialize.
    filepath : str | Path
        Output file path (.geojson, .gpkg, or .json).
    """
    path = Path(filepath)
    ext = path.suffix.lower()

    if ext in [".geojson", ".json"]:
        topo.layer.to_file(path, driver="GeoJSON")
    elif ext == ".gpkg":
        topo.layer.to_file(path, driver="GPKG")
    else:
        # Generic JSON export including metadata
        data = {
            "huc_id": topo.huc_id,
            "lon": topo.lon,
            "lat": topo.lat,
            "huc_level": topo.huc_level,
            "feature_name": topo.feature_name,
            "metadata": topo.metadata,
            "geojson": json.loads(topo.layer.to_json())
        }
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)


def load_topology(filepath: str | Path) -> HexmapTopology:
    """
    Loads a HexmapTopology object from a spatial dataset or exported JSON file.

    Parameters
    ----------
    filepath : str | Path
        Path to spatial topology dataset (.geojson, .gpkg, or .json).

    Returns
    -------
    HexmapTopology
        Deserialized topology object.
    """
    path = Path(filepath)
    ext = path.suffix.lower()

    if ext in [".geojson", ".gpkg"]:
        gdf = gpd.read_file(path)
        centroid = gdf.geometry.unary_union.centroid
        return HexmapTopology(
            huc_id="imported",
            layer=gdf,
            lon=float(centroid.x),
            lat=float(centroid.y)
        )
    
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if "geojson" in data:
        gdf = gpd.GeoDataFrame.from_features(data["geojson"]["features"], crs="EPSG:4326")
    else:
        gdf = gpd.read_file(path)

    return HexmapTopology(
        huc_id=data.get("huc_id", "imported"),
        layer=gdf,
        lon=data.get("lon", 0.0),
        lat=data.get("lat", 0.0),
        huc_level=data.get("huc_level", 8),
        feature_name=data.get("feature_name"),
        metadata=data.get("metadata", {})
    )

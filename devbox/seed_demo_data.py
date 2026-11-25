"""Create demonstration datasets with dependencies in s3://dtool-bucket.

The datasets form a small provenance graph, as a measurement and simulation
project would produce it:

    raw-scan-a ─┐
    raw-scan-b ─┼─> processed-topographies ─> roughness-analysis ─┬─> figures
    calibration ┘                                                 │
    simulation-input ─> simulation-results ───────────────────────┴─> comparison

Dependencies are recorded as the dependency-graph plugin expects them: in the
README (``derived_from: [{uuid: ..., name: ...}]``), and for the figures also
as annotation ``source_dataset_uuid``. Each dataset has a README with
searchable metadata, tags, annotations and a few small items.

Run through ``devbox run seed-demo-data`` (dtool S3 settings and indexing).
Does nothing if demo datasets exist already, unless --force is given.
"""

import argparse
import csv
import io
import json
import math
import random
import sys
import tempfile
from pathlib import Path

import dtoolcore
import yaml

BASE_URI = "s3://dtool-bucket"
PREFIX = "demo-"
PROJECT = "dserver demo: surface roughness of polished steel"

# name -> (description, parents, tags, annotations, item generator)
DATASETS = [
    ("raw-scan-a",
     "AFM topography scans of polished steel, sample A",
     [], ["afm", "raw"], {"instrument": "AFM", "sample": "A"}, "scans"),
    ("raw-scan-b",
     "AFM topography scans of polished steel, sample B",
     [], ["afm", "raw"], {"instrument": "AFM", "sample": "B"}, "scans"),
    ("calibration",
     "Calibration grating measurements for the AFM scanner",
     [], ["afm", "calibration"], {"instrument": "AFM"}, "calibration"),
    ("processed-topographies",
     "Levelled and calibrated topographies of samples A and B",
     ["raw-scan-a", "raw-scan-b", "calibration"], ["afm", "processed"],
     {"pipeline": "level+calibrate", "version": 2}, "scans"),
    ("roughness-analysis",
     "Roughness parameters (Rq, Ra, Sq) of the processed topographies",
     ["processed-topographies"], ["analysis"],
     {"parameters": ["Rq", "Ra", "Sq"]}, "table"),
    ("figures",
     "Figures for the roughness analysis",
     ["roughness-analysis"], ["figures"], {"format": "svg"}, "figures"),
    ("simulation-input",
     "Input files for contact mechanics simulations",
     [], ["simulation", "input"], {"code": "ContactMechanics"}, "input"),
    ("simulation-results",
     "Contact area versus load from the simulations",
     ["simulation-input"], ["simulation", "results"],
     {"code": "ContactMechanics", "converged": True}, "table"),
    ("comparison",
     "Comparison of measured roughness with simulated contact behaviour",
     ["roughness-analysis", "simulation-results"], ["analysis", "comparison"],
     {"conclusion": "agreement within 10 %"}, "table"),
]


def _csv(rows):
    out = io.StringIO()
    csv.writer(out).writerows(rows)
    return out.getvalue()


def _items(kind, rng):
    """Return {relpath: text} with a few small, plausible files."""
    if kind == "scans":
        return {
            f"scans/scan-{i}.csv": _csv(
                [["x_um", "y_um", "height_nm"]]
                + [[x, y, round(rng.gauss(0, 12), 2)]
                   for x in range(8) for y in range(8)])
            for i in range(1, 4)
        }
    if kind == "calibration":
        return {"grating.csv": _csv(
            [["x_um", "height_nm"]]
            + [[x / 10, 100 if (x // 10) % 2 else 0] for x in range(100)])}
    if kind == "table":
        return {"results.csv": _csv(
            [["sample", "Rq_nm", "Ra_nm", "Sq_nm"]]
            + [[s, round(rng.uniform(8, 15), 2), round(rng.uniform(6, 12), 2),
                round(rng.uniform(8, 15), 2)] for s in "AB"])}
    if kind == "figures":
        points = " ".join(f"{x * 10},{100 - 40 * math.exp(-x / 8):.1f}"
                          for x in range(30))
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="300" '
               f'height="110"><polyline points="{points}" fill="none" '
               'stroke="black"/></svg>\n')
        return {"roughness.svg": svg}
    if kind == "input":
        return {"simulation.yml": yaml.safe_dump({
            "nb_grid_pts": [512, 512], "physical_sizes": [10.0, 10.0],
            "loads": [0.01, 0.02, 0.05, 0.1], "young": 210.0})}
    raise ValueError(kind)


def existing_demo_datasets():
    return [ds for ds in dtoolcore.iter_datasets_in_base_uri(BASE_URI)
            if ds.name.startswith(PREFIX)]


def create(work_dir, name, description, parents, tags, annotations, kind,
           rng):
    readme = {
        "description": description,
        "project": PROJECT,
        "owners": [{"name": "Demo User", "email": "demo@example.org"}],
        "creation_date": "2026-01-15",
    }
    if parents:
        readme["derived_from"] = [
            {"uuid": uuid, "name": PREFIX + parent}
            for parent, uuid in parents]

    with dtoolcore.DataSetCreator(PREFIX + name, str(work_dir)) as creator:
        for relpath, text in _items(kind, rng).items():
            path = work_dir / "staging" / name / relpath
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            creator.put_item(str(path), relpath)
        creator.put_readme(yaml.safe_dump(readme, sort_keys=False))
        for tag in ["demo", *tags]:
            creator.put_tag(tag)
        for key, value in annotations.items():
            creator.put_annotation(key, value)
        if name == "figures":
            # Second way to record a dependency (annotation).
            creator.put_annotation("source_dataset_uuid", parents[0][1])
        local_uri = creator.uri

    remote_uri = dtoolcore.copy(local_uri, BASE_URI)
    return dtoolcore.DataSet.from_uri(remote_uri).uuid, remote_uri


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true",
                        help="create the demo datasets even if some exist")
    args = parser.parse_args()

    existing = existing_demo_datasets()
    if existing and not args.force:
        print(f"==> {len(existing)} demo datasets exist in {BASE_URI} "
              f"already; use --force to add another set.")
        return 0

    rng = random.Random(42)
    uuids = {}
    with tempfile.TemporaryDirectory() as tmp:
        work_dir = Path(tmp)
        for name, description, parents, tags, annotations, kind in DATASETS:
            parent_uuids = [(parent, uuids[parent]) for parent in parents]
            uuids[name], uri = create(work_dir, name, description,
                                      parent_uuids, tags, annotations, kind,
                                      rng)
            arrow = f" <- {', '.join(parents)}" if parents else ""
            print(f"    {PREFIX}{name}{arrow}\n        {uri}")

    print(json.dumps({PREFIX + k: v for k, v in uuids.items()}, indent=2),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

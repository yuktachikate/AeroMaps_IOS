#!/usr/bin/env python3
"""Builds AeroMaps' bundled aeronautical dataset from OurAirports open data.

OurAirports is public domain and rebuilt nightly, so this can be re-run any time to
refresh what ships in the app. Output is one compact JSON file consumed by
AeronauticalData.swift; the same file is what the in-app updater fetches.

Usage:  python3 tools/build_airport_data.py [--out AeroMaps/Resources/aerodata.json]
"""
import argparse, csv, io, json, os, sys, urllib.request
from datetime import datetime, timezone

BASE = "https://davidmegginson.github.io/ourairports-data"
FILES = ["airports.csv", "runways.csv", "airport-frequencies.csv", "navaids.csv"]

# Heliports, seaplane bases, balloonports and closed fields are excluded: none of
# them are somewhere a training flight or a local GA hop plans a leg to.
KEEP_TYPES = {"large_airport", "medium_airport", "small_airport"}
TYPE_CODE = {"large_airport": 3, "medium_airport": 2, "small_airport": 1}

# OurAirports surface codes are free text in practice; fold the common ones.
SURFACES = {
    "ASP": "Asphalt", "ASPH": "Asphalt", "CON": "Concrete", "CONC": "Concrete",
    "GRS": "Grass", "GRASS": "Grass", "TURF": "Turf", "GVL": "Gravel",
    "GRVL": "Gravel", "DIRT": "Dirt", "WATER": "Water", "SAND": "Sand",
    "PEM": "Asphalt", "MAC": "Macadam", "COP": "Composite", "SNOW": "Snow",
}


def fetch(name):
    url = f"{BASE}/{name}"
    sys.stderr.write(f"  fetching {name} … ")
    with urllib.request.urlopen(url, timeout=120) as r:
        data = r.read().decode("utf-8")
    sys.stderr.write(f"{len(data)/1e6:.1f} MB\n")
    return list(csv.DictReader(io.StringIO(data)))


def num(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def surface_name(raw):
    key = (raw or "").strip().upper()
    return SURFACES.get(key, (raw or "").strip().title() or "Unknown")


def build():
    airports, runways, freqs, navaids = (fetch(f) for f in FILES)

    kept = {}
    for a in airports:
        if a["type"] not in KEEP_TYPES:
            continue
        ident = (a["ident"] or "").strip().upper()
        # A four-character ident is what a pilot files and what this app looks up.
        if len(ident) != 4 or not ident.isalnum():
            continue
        kept[ident] = {
            "i": ident,
            "n": (a["name"] or "").strip()[:60],
            "m": (a["municipality"] or "").strip()[:40],
            "r": (a["iso_region"] or "").split("-")[-1][:6],
            "c": a["iso_country"],
            "t": TYPE_CODE[a["type"]],
            "y": round(num(a["latitude_deg"]), 5),
            "x": round(num(a["longitude_deg"]), 5),
            "e": int(num(a["elevation_ft"])),
            "a": (a["iata_code"] or "").strip().upper(),
            "R": [],
            "F": [],
        }

    rw_kept = 0
    for r in runways:
        ap = kept.get((r["airport_ident"] or "").strip().upper())
        if ap is None or r.get("closed") == "1":
            continue
        le, he = (r.get("le_ident") or "").strip(), (r.get("he_ident") or "").strip()
        if not le and not he:
            continue
        ap["R"].append({
            "d": f"{le}/{he}" if le and he else (le or he),
            "l": int(num(r["length_ft"])),
            "w": int(num(r["width_ft"])),
            "s": surface_name(r["surface"]),
            "g": r.get("lighted") == "1",
            # True headings, straight from the source. Deriving them from the
            # designation digits ("28R" -> 280) is wrong by up to half a runway
            # number — KSFO's 28R is 298 degrees true, not 280 — and that error
            # lands directly in the crosswind component.
            "hl": round(num(r["le_heading_degT"]), 1) if r.get("le_heading_degT") else None,
            "hh": round(num(r["he_heading_degT"]), 1) if r.get("he_heading_degT") else None,
        })
        rw_kept += 1

    fq_kept = 0
    for f in freqs:
        ap = kept.get((f["airport_ident"] or "").strip().upper())
        if ap is None:
            continue
        mhz = num(f["frequency_mhz"])
        if mhz <= 0:
            continue
        ap["F"].append({"t": (f["type"] or "")[:8], "f": f"{mhz:.3f}".rstrip("0").rstrip(".")})
        fq_kept += 1

    nav = []
    for n in navaids:
        ident = (n["ident"] or "").strip().upper()
        if not ident:
            continue
        nav.append({
            "i": ident,
            "n": (n["name"] or "").strip()[:40],
            "t": (n["type"] or "")[:8],
            "y": round(num(n["latitude_deg"]), 5),
            "x": round(num(n["longitude_deg"]), 5),
            "c": n["iso_country"],
            "f": round(num(n["frequency_khz"]) / 1000, 3) or None,
        })

    # Airports with no runway record are usually stubs; keep them as waypoints but
    # they will simply have nothing to brief.
    out = {
        "version": 1,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "OurAirports (public domain) — ourairports.com/data/",
        "airports": sorted(kept.values(), key=lambda a: a["i"]),
        "navaids": sorted(nav, key=lambda n: n["i"]),
    }
    sys.stderr.write(
        f"\n  airports {len(kept):,}  runways {rw_kept:,}  frequencies {fq_kept:,}  navaids {len(nav):,}\n")
    return out


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="AeroMaps/Resources/aerodata.json")
    args = p.parse_args()

    data = build()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    blob = json.dumps(data, separators=(",", ":")).encode()
    with open(args.out, "wb") as fh:
        fh.write(blob)
    sys.stderr.write(f"  wrote {args.out}  {len(blob)/1e6:.1f} MB\n")

#!/usr/bin/env python3
"""Rebuild public AKFIN GFSAFE001 annual catches for BSAI and GOA, 2003-2025.

Default: read and validate archived public report pages. --refresh downloads
the same explicit report filters and validates each page before replacing it.
Python standard library and curl (refresh only); no login or API key required.
"""

import argparse
import csv
import hashlib
import html
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/source/akfin-groundfish-catch"
YEARS = tuple(range(2003, 2026))
REGIONS = {"BSAI": "Bering Sea and Aleutian Islands", "GOA": "Gulf of Alaska", "Alaska": "All Alaska"}
SPECIES = ("All Groundfish", "Atka Mackerel", "Flatfish", "Other Groundfish", "Pacific Cod", "Pollock", "Rockfish", "Sablefish")
BLOCKS = ((2003, 2008), (2009, 2014), (2015, 2020), (2021, 2025))
STATUS = "Source report labels Economic SAFE data preliminary"


class TableRows(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack, self.rows, self.cell = [], [], None

    def handle_starttag(self, tag, attrs):
        if tag == "tr":
            self.stack.append([])
        if tag in ("td", "th"):
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self.cell is not None:
            if self.stack:
                self.stack[-1].append(" ".join(" ".join(self.cell).split()))
            self.cell = None
        if tag == "tr" and self.stack:
            row = self.stack.pop()
            if row:
                self.rows.append(row)


def report_url(region, start, end):
    names = ("P0_SHARE_DISPLAY", "P0_SHARE_VIEW", "P901_MIN_YEAR", "P901_MAX_YEAR", "P901_FMP_AREA", "P901_SPECIES_GROUP")
    values = ("R", "report", str(start), str(end), REGIONS[region], ":".join(SPECIES))
    # Backslashes protect colon-separated APEX filter values.
    return "https://reports.psmfc.org/akfin/f?p=501:901:0:INITIAL:::" + ",".join(names) + ":" + ",".join(quote("\\" + v + "\\", safe="") for v in values)


def parse_report(raw, region, start, end):
    source = raw.decode("utf-8")
    flat = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", source)).split())
    assert "GFSAFE001" in flat and "Catch (metric tons)" in flat
    assert "Catch includes retained catch and estimates of discards." in flat
    parser = TableRows()
    parser.feed(source)
    rows = [row for row in parser.rows if len(row) == 4 and row[0].isdigit()]
    expected = {(str(year), REGIONS[region], species) for year in range(start, end + 1) for species in SPECIES}
    assert len(rows) == len(expected), (region, start, len(rows), len(expected))
    assert {tuple(row[:3]) for row in rows} == expected, (region, start, "unexpected or missing rows")
    # Batches contain at most 48 rows, within the report's 50-row display limit.
    assert len(rows) <= 50
    refreshed = re.search(r"Data last refreshed:\s*([A-Z][a-z]+ \d{1,2}, \d{4})", flat)
    assert refreshed, (region, start, "missing data refresh date")
    preliminary = "Groundfish Economic SAFE data are still preliminary." in flat
    data = []
    for year, area, species, value in rows:
        assert re.fullmatch(r"[\d,]+", value), (year, area, species, value)
        # Confidential (-9999) and subprecision (-8888) markers must never become catches.
        catch = int(value.replace(",", ""))
        data.append({"Region": region, "Year": int(year), "Species_group": species, "Catch_t": catch})
    return data, refreshed.group(1), preliminary


def write_csv(path, rows):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    SOURCE.mkdir(parents=True, exist_ok=True)
    manifest_path = SOURCE / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    species_rows, totals, checks = [], [], []
    for region in REGIONS:
        for start, end in BLOCKS:
            name = f"GFSAFE001_{region}_{start}-{end}.html.txt"
            path, url = SOURCE / name, report_url(region, start, end)
            if args.refresh:
                raw = subprocess.check_output(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", "--max-time", "45", url])
                parse_report(raw, region, start, end)
                path.write_bytes(raw)
                manifest[name] = {"SourceURL": url, "Retrieved_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"), "Source_sha256": hashlib.sha256(raw).hexdigest(), "Region": region, "First_year": start, "Last_year": end}
                manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
            raw, meta = path.read_bytes(), manifest[name]
            assert meta["SourceURL"] == url
            assert hashlib.sha256(raw).hexdigest() == meta["Source_sha256"]
            rows, refreshed, preliminary = parse_report(raw, region, start, end)
            species_rows += rows
            for year in range(start, end + 1):
                subset = [r for r in rows if r["Year"] == year]
                total = next(r["Catch_t"] for r in subset if r["Species_group"] == "All Groundfish")
                components = [r["Catch_t"] for r in subset if r["Species_group"] != "All Groundfish"]
                delta = sum(components) - total
                assert abs(delta) <= (len(components) + 1) / 2, (region, year, delta)
                checks.append({"Region": region, "Year": year, "Published_total_t": total, "Species_sum_t": sum(components), "Species_sum_minus_total_t": delta, "Unique_total": True, "Species_groups": len(components)})
                totals.append({"Region": region, "Year": year, "Catch_t": total, "Units": "metric tons", "Source_report": "AKFIN GFSAFE001 Economic SAFE", "Data_status": STATUS if preliminary else "Preliminary banner absent; verify publication status", "Data_last_refreshed": refreshed, "SourceURL": url, "Retrieved_utc": meta["Retrieved_utc"], "Source_sha256": meta["Source_sha256"]})

    assert len(species_rows) == 3 * len(YEARS) * len(SPECIES)
    assert len(totals) == 3 * len(YEARS)
    assert len({(r["Region"], r["Year"]) for r in totals}) == len(totals)
    region_checks = []
    for year in YEARS:
        vals = {r["Region"]: r["Catch_t"] for r in totals if r["Year"] == year}
        delta = vals["BSAI"] + vals["GOA"] - vals["Alaska"]
        assert abs(delta) <= 1, (year, delta)
        region_checks.append({"Year": year, "BSAI_plus_GOA_minus_All_Alaska_t": delta})

    combined = sorted([r for r in totals if r["Region"] != "Alaska"], key=lambda r: (r["Region"], r["Year"]))
    data_dir = ROOT / "data"
    downloads = ROOT / "doc/downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    files = []
    for name, rows in [("AKFIN_groundfish_catch_2003-2025.csv", combined), ("AKFIN_groundfish_catch_species_2003-2025.csv", sorted(species_rows, key=lambda r: (r["Region"], r["Year"], r["Species_group"])))]:
        path = data_dir / name
        write_csv(path, rows)
        files.append(path)
    for region in ("BSAI", "GOA"):
        path = data_dir / f"{region}_AKFIN_groundfish_catch_by_year.csv"
        write_csv(path, [r for r in combined if r["Region"] == region])
        files.append(path)
    validation = {
        "source": "Public AKFIN GFSAFE001 Economic SAFE", "source_page": "https://reports.psmfc.org/akfin/f?p=501:901:0:INITIAL", "units": "metric tons", "years": list(YEARS), "regions": ["BSAI", "GOA"],
        "value_rule": "Use the unique All Groundfish total for each region and year; species and All Alaska rows are independent rounding checks.",
        "scope": "Retained catch plus estimated discards of FMP-managed groundfish species; includes those species caught while targeting halibut. Economic SAFE scope differs from NOAA CAR110 quota-account totals.",
        "status": sorted({r["Data_status"] for r in totals}), "data_last_refreshed": sorted({r["Data_last_refreshed"] for r in totals}),
        "raw_report_pages": len(manifest), "source_table_rows": len(species_rows), "annual_regional_rows": len(combined),
        "maximum_absolute_species_rounding_difference_t": max(abs(r["Species_sum_minus_total_t"]) for r in checks),
        "maximum_absolute_region_rounding_difference_t": max(abs(r["BSAI_plus_GOA_minus_All_Alaska_t"]) for r in region_checks),
        "species_checks": checks, "region_checks": region_checks,
    }
    path = data_dir / "AKFIN_groundfish_catch_validation.json"
    path.write_text(json.dumps(validation, indent=2) + "\n")
    files.append(path)
    for path in files:
        shutil.copyfile(path, downloads / path.name)
    print(f"Validated {len(combined)} annual regional totals, {YEARS[0]}-{YEARS[-1]}, from {len(species_rows)} public table rows.")
    print(f"Maximum species rounding difference: {validation['maximum_absolute_species_rounding_difference_t']} t; regional rounding difference: {validation['maximum_absolute_region_rounding_difference_t']} t.")
    for region in ("BSAI", "GOA"):
        row = next(r for r in combined if r["Region"] == region and r["Year"] == YEARS[-1])
        print(f"{region} {YEARS[-1]}: {row['Catch_t']:,} metric tons. {row['Data_status']}.")


if __name__ == "__main__":
    main()

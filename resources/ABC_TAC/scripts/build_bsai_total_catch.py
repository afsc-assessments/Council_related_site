#!/usr/bin/env python3
"""Build the 2013-2025 annual BSAI catch series from NOAA CAR110 reports.

Default: reproduce outputs from the archived source HTML and metadata.
Use --refresh to retrieve current NOAA versions. Requires Python 3 and curl.
Run Rscript R/plot_bsai_total_catch.R next to rebuild the figures.
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

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/source/bsai-annual-catch"
YEARS = tuple(range(2013, 2026))
URL = "https://www.fisheries.noaa.gov/sites/default/files/akro/car110_bsai_with_cdq{}.html"


class TableRows(HTMLParser):
    """Read innermost table rows, including the older nested NOAA layouts."""

    def __init__(self):
        super().__init__()
        self.stack = []
        self.rows = []
        self.cell = None

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


def parse_report(raw, year):
    source = raw.decode("utf-8")
    flat = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", source)).split())
    assert "Bering Sea Aleutian Islands Catch Report" in flat, year
    assert "(includes CDQ)" in flat, year
    assert "All weights are in metric tons" in flat, year
    through = re.findall(r"Through: (.+?) National", flat)
    assert through == [f"31-Dec-{year}"], (year, through)
    run = re.findall(r"Report run on:?\s*(.+)$", flat)
    assert len(run) == 1, (year, run)

    parser = TableRows()
    parser.feed(source)
    totals = [r for r in parser.rows if r[0] == "Total:"]
    assert len(totals) == 1 and len(totals[0]) == 6, (year, totals)
    total = int(totals[0][1].replace(",", ""))
    assert total > 0, year
    assert any(r[:3] == ["Seasons", "Account", "Total Catch"] for r in parser.rows)

    # The published grand total is the data value. Account sums only validate it.
    # Separate CDQ accounts occur only where CDQ is not already combined.
    area = None
    accounts = []
    for row in parser.rows:
        if len(row) == 6 and row[0] in (
            "Bering Sea", "Aleutian Islands", "Bering Sea Aleutian Islands"
        ):
            area = row[0]
        if len(row) == 7 and re.fullmatch(r"[0-9,]+", row[2]):
            assert area is not None, (year, row)
            accounts.append((area, row[1], int(row[2].replace(",", ""))))
    assert 60 <= len(accounts) <= 100, (year, len(accounts))
    keys = [(a, b) for a, b, _ in accounts]
    assert len(keys) == len(set(keys)), (year, "duplicate area/account")
    account_sum = sum(c for _, _, c in accounts)
    # NOAA displays rounded whole tons: permit at most half a ton per row,
    # plus half a ton for the independently rounded grand total.
    difference = account_sum - total
    assert abs(difference) <= (len(accounts) + 1) / 2, (year, difference)
    qa = dict(
        Year=year, Account_rows=len(accounts), Account_sum_t=account_sum,
        Published_total_t=total, Account_sum_minus_total_t=difference,
        Squid_account_present=any("Squid" in a[1] for a in accounts),
        Sculpin_account_present=any("Sculpin" in a[1] for a in accounts),
        Unique_total_row=True, Unique_area_account_rows=True,
        Complete_calendar_year=True,
    )
    return total, through[0], run[0], qa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--refresh", action="store_true", help="Retrieve NOAA reports anew")
    args = parser.parse_args()
    SOURCE.mkdir(parents=True, exist_ok=True)
    metadata_file = SOURCE / "manifest.json"
    metadata = json.loads(metadata_file.read_text()) if metadata_file.exists() else {}
    rows, checks = [], []
    for year in YEARS:
        url = URL.format(year)
        path = SOURCE / f"car110_bsai_with_cdq{year}.html.txt"
        if args.refresh:
            raw = subprocess.check_output([
                "curl", "--fail", "--silent", "--show-error", "--location",
                "--retry", "2", "--max-time", "45", url,
            ])
            # Validate before replacing any archived source.
            parse_report(raw, year)
            path.write_bytes(raw)
            metadata[str(year)] = {
                "SourceURL": url,
                "Retrieved_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "Source_sha256": hashlib.sha256(raw).hexdigest(),
            }
            metadata_file.write_text(json.dumps(metadata, indent=2) + "\n")
        else:
            if not path.exists() or str(year) not in metadata:
                raise SystemExit(f"Missing archived source for {year}; run with --refresh")
            raw = path.read_bytes()
        meta = metadata[str(year)]
        assert hashlib.sha256(raw).hexdigest() == meta["Source_sha256"], year
        assert meta["SourceURL"] == url, year
        total, through, run, qa = parse_report(raw, year)
        rows.append(dict(Year=year, Catch_t=total, Through=through, Includes_CDQ=True,
                         Report_run=run, **meta))
        checks.append(qa)

    assert [r["Year"] for r in rows] == list(YEARS)
    output = ROOT / "data/BSAI_total_catch_by_year.csv"
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    validation = dict(
        source="NOAA Alaska Region CAR110 annual catch report (includes CDQ)",
        units="metric tons", years=list(YEARS),
        value_rule="Use each report's single published Total Catch grand total once",
        coverage="Quota accounts included in that year's report; includes CDQ",
        incomplete_years_included=False, checks=checks,
        maximum_absolute_rounding_difference_t=max(
            abs(c["Account_sum_minus_total_t"]) for c in checks
        ),
    )
    qa_path = ROOT / "data/BSAI_total_catch_validation.json"
    qa_path.write_text(json.dumps(validation, indent=2) + "\n")
    downloads = ROOT / "doc/downloads"
    downloads.mkdir(exist_ok=True)
    shutil.copyfile(output, downloads / output.name)
    shutil.copyfile(qa_path, downloads / qa_path.name)
    table = ["| Year | Total catch (metric tons) | NOAA source |",
             "|---:|---:|:---|"]
    table += [f"| {r['Year']} | {r['Catch_t']:,} | [Annual report]({r['SourceURL']}) |"
              for r in rows]
    (ROOT / "doc/_bsai-total-catch-table.qmd").write_text("\n".join(table) + "\n")
    print(f"Validated {len(rows)} complete calendar years, {YEARS[0]}-{YEARS[-1]}.")
    print(f"2025 catch: {rows[-1]['Catch_t']:,} metric tons; maximum rounded-row difference: "
          f"{validation['maximum_absolute_rounding_difference_t']} metric tons.")
    print(output)


if __name__ == "__main__":
    main()

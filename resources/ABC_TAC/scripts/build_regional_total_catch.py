#!/usr/bin/env python3
"""Reproduce GOA and BSAI CAR110 annual catch totals for 2013-2025.

Default: read the archived NOAA reports and verify their SHA-256 hashes.
--refresh: retrieve the current NOAA versions, validate, then archive them.
Requires Python 3 and curl. Run Rscript R/plot_regional_total_catch.R for figures.
These totals cover the quota accounts included in each year's CAR110 report.
"""
import argparse
import csv
import hashlib
import html
import json
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/source/regional-annual-catch'
YEARS = tuple(range(2013, 2026))
INDEX_URL = 'https://www.fisheries.noaa.gov/alaska/commercial-fishing/fisheries-catch-and-landings-reports-alaska'
REGIONS = {
    'BSAI': dict(stem='car110_bsai_with_cdq', heading='Bering Sea Aleutian Islands Catch Report', areas=('Bering Sea', 'Aleutian Islands', 'Bering Sea Aleutian Islands')),
    'GOA': dict(stem='car110_goa', heading='Gulf Of Alaska Catch Report', areas=('Western, Central Pollock', 'Western Gulf', 'Western and Central (Includes West Yakutat)', 'Central Gulf', 'Eastern Gulf', 'West Yakutat', 'Southeast', 'Entire Gulf')),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


class TableRows(HTMLParser):
    """Read innermost rows in both older nested and current NOAA layouts."""
    def __init__(self):
        super().__init__()
        self.stack, self.rows, self.cell = [], [], None

    def handle_starttag(self, tag, attrs):
        if tag == 'tr':
            self.stack.append([])
        if tag in ('td', 'th'):
            self.cell = []

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)

    def handle_endtag(self, tag):
        if tag in ('td', 'th') and self.cell is not None:
            if self.stack:
                self.stack[-1].append(' '.join(' '.join(self.cell).split()))
            self.cell = None
        if tag == 'tr' and self.stack:
            row = self.stack.pop()
            if row:
                self.rows.append(row)


def parse_report(raw, region, year):
    key = f'{region}-{year}'
    source = raw.decode('utf-8')
    flat = ' '.join(html.unescape(re.sub(r'<[^>]+>', ' ', source)).split())
    require(REGIONS[region]['heading'] in flat, f'{key}: missing report heading')
    require('All weights are in metric tons' in flat, f'{key}: missing units')
    if region == 'BSAI':
        require('(includes CDQ)' in flat, f'{key}: CDQ inclusion unconfirmed')
    through = re.findall(r'Through:\s*(.+?) National', flat)
    require(through == [f'31-Dec-{year}'], f'{key}: incomplete or mismatched year {through}')
    run = re.findall(r'Report run on:?\s*(.+)$', flat)
    require(len(run) == 1, f'{key}: report run date missing or repeated')
    parser = TableRows()
    parser.feed(source)
    totals = [r for r in parser.rows if r[0] == 'Total:']
    require(len(totals) == 1 and len(totals[0]) == 6, f'{key}: ambiguous total {totals}')
    require(re.fullmatch(r'[0-9,]+', totals[0][1]), f'{key}: nonnumeric total')
    total = int(totals[0][1].replace(',', ''))
    require(total > 0, f'{key}: nonpositive total')
    require(any(r[:3] == ['Seasons', 'Account', 'Total Catch'] for r in parser.rows), f'{key}: missing column headings')
    area, accounts = None, []
    for row in parser.rows:
        if len(row) == 6 and row[0] in REGIONS[region]['areas']:
            area = row[0]
        if len(row) == 7 and re.fullmatch(r'[0-9,]+', row[2]):
            require(area is not None, f'{key}: account before area {row}')
            require(bool(row[1]), f'{key}: account name missing')
            accounts.append(dict(Region=region, Year=year, Area=area, Account=row[1], Catch_t=int(row[2].replace(',', ''))))
    require(50 <= len(accounts) <= 100, f'{key}: unexpected account count {len(accounts)}')
    keys = [(a['Area'], a['Account']) for a in accounts]
    require(len(keys) == len(set(keys)), f'{key}: duplicate area/account')
    account_sum = sum(a['Catch_t'] for a in accounts)
    difference = account_sum - total
    # Every displayed row and the total are independently rounded to whole tons.
    require(abs(difference) <= (len(accounts) + 1) / 2, f'{key}: rounded account sum differs by {difference} t')
    names = set(a['Account'] for a in accounts)
    sablefish_fixed = sorted(n for n in names if 'Sablefish' in n and ('Hook-and-Line' in n or 'Fixed Gear' in n))
    require(bool(sablefish_fixed), f'{key}: fixed-gear sablefish account unconfirmed')
    qa = dict(Region=region, Year=year, Account_rows=len(accounts), Account_sum_t=account_sum,
              Published_total_t=total, Account_sum_minus_total_t=difference,
              Squid_account_present=any('Squid' in n for n in names),
              Sculpin_account_present=any('Sculpin' in n for n in names),
              Sablefish_fixed_gear_account_labels=sablefish_fixed,
              Sablefish_fixed_gear_sum_t=sum(a['Catch_t'] for a in accounts if a['Account'] in sablefish_fixed),
              Unique_total_row=True, Unique_area_account_rows=True, Complete_calendar_year=True)
    require(qa['Squid_account_present'] == (year <= 2018), f'{key}: squid coverage changed; revise documentation')
    require(qa['Sculpin_account_present'] == (year <= 2020), f'{key}: sculpin coverage changed; revise documentation')
    require(sum(a['Account'] in sablefish_fixed for a in accounts) == 4, f'{key}: fixed-gear sablefish area coverage changed')
    return total, through[0], run[0], qa, accounts


def report_url(region, year):
    return f"https://www.fisheries.noaa.gov/sites/default/files/akro/{REGIONS[region]['stem']}{year}.html"


def retrieve(job):
    region, year = job
    url = report_url(region, year)
    raw = subprocess.check_output(['curl', '--fail', '--silent', '--show-error', '--location', '--retry', '2', '--max-time', '45', url])
    parse_report(raw, region, year)  # Reject unexpected sources before writing.
    return region, year, raw, dict(SourceURL=url, Retrieved_utc=datetime.now(timezone.utc).isoformat(timespec='seconds'), Source_sha256=hashlib.sha256(raw).hexdigest())


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true', help='Retrieve current public NOAA reports')
    args = parser.parse_args()
    SOURCE.mkdir(parents=True, exist_ok=True)
    manifest_path = SOURCE / 'manifest.json'
    jobs = [(region, year) for region in REGIONS for year in YEARS]
    if args.refresh:
        # Finish validation for all downloads before replacing the source archive.
        with ThreadPoolExecutor(max_workers=4) as pool:
            refreshed = list(pool.map(retrieve, jobs))
        metadata = {}
        for region, year, raw, meta in refreshed:
            filename = f"{REGIONS[region]['stem']}{year}.html.txt"
            (SOURCE / filename).write_bytes(raw)
            metadata[f'{region}-{year}'] = dict(Archive_file=filename, **meta)
        manifest_path.write_text(json.dumps(metadata, indent=2) + '\n')
    require(manifest_path.exists(), 'Missing source manifest; run with --refresh')
    metadata = json.loads(manifest_path.read_text())
    rows, checks, all_accounts = [], [], []
    for region, year in jobs:
        key = f'{region}-{year}'
        require(key in metadata, f'{key}: source metadata missing')
        meta = metadata[key]
        raw = (SOURCE / meta['Archive_file']).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == meta['Source_sha256'], f'{key}: source hash mismatch')
        require(meta['SourceURL'] == report_url(region, year), f'{key}: source URL mismatch')
        total, through, run, qa, accounts = parse_report(raw, region, year)
        rows.append(dict(Region=region, Year=year, Catch_t=total, Through=through,
                         Includes_CDQ=('True' if region == 'BSAI' else 'Not applicable'),
                         Sablefish_fixed_gear_included=True, Squid_account_present=qa['Squid_account_present'],
                         Sculpin_account_present=qa['Sculpin_account_present'], Report_run=run, **meta))
        checks.append(qa)
        all_accounts.extend(accounts)
    require(len(rows) == 26 and len({(r['Region'], r['Year']) for r in rows}) == 26, 'Region-year coverage mismatch')
    data = ROOT / 'data'
    write_csv(data / 'regional_total_catch_2013_2025.csv', rows)
    write_csv(data / 'regional_catch_accounts_2013_2025.csv', all_accounts)
    for region in REGIONS:
        write_csv(data / f'{region}_total_catch_2013_2025.csv', [r for r in rows if r['Region'] == region])
    changes = {}
    for region in REGIONS:
        by_year = {year: {(a['Area'], a['Account']) for a in all_accounts if a['Region'] == region and a['Year'] == year} for year in YEARS}
        changes[region] = [dict(Year=year, Added_area_accounts=sorted(by_year[year] - by_year[year-1]), Removed_area_accounts=sorted(by_year[year-1] - by_year[year])) for year in YEARS[1:] if by_year[year] != by_year[year-1]]
    validation = dict(
        source='NOAA Alaska Region CAR110 annual catch reports', source_index=INDEX_URL,
        units='metric tons', regions=list(REGIONS), years=list(YEARS),
        value_rule="Use each report's single published Total Catch grand total once; account sums validate the grand total.",
        coverage='Quota accounts included in each annual report; BSAI includes CDQ; both regions include the reported fixed-gear and trawl sablefish accounts.',
        fixed_gear_sablefish_note='GOA CAR110 includes four Hook-and-Line or Fixed Gear sablefish accounts (Western Gulf, Central Gulf, West Yakutat, Southeast). Separate IFQ landing reports must not be added to these totals.',
        category_note='Squid accounts occur through 2018; sculpin accounts through 2020. NOAA lists these separately as ecosystem components from 2019 and 2021. Other area/account groupings also change; the complete observed differences are recorded below.',
        sablefish_management_source='https://www.fisheries.noaa.gov/bulletin/ib-17-19-nmfs-authorizes-longline-pot-gear-gulf-alaska-sablefish-fixed-gear-fisheries',
        sablefish_label_change='GOA Hook-and-Line (2013-2016) becomes Fixed Gear (2017-2025); NOAA authorized longline pot gear in the GOA IFQ sablefish fishery beginning in 2017.',
        species_changes=changes, incomplete_years_included=False,
        maximum_absolute_rounding_difference_t=max(abs(c['Account_sum_minus_total_t']) for c in checks),
        checks=checks)
    (data / 'regional_total_catch_validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    print(f'Validated {len(rows)} region-years (2013-2025) and {len(all_accounts)} quota account rows.')
    for region in REGIONS:
        last = [r for r in rows if r['Region'] == region][-1]
        print(f"{region} 2025: {last['Catch_t']:,} metric tons; report run {last['Report_run']}")
    print(f"Maximum absolute rounded-account difference: {validation['maximum_absolute_rounding_difference_t']} metric tons.")


if __name__ == '__main__':
    main()

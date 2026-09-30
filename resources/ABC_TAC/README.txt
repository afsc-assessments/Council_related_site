NOAA CAR110 regional annual catch series, 2013-2025

Scope
The data reproduce the single Total Catch grand total from each NOAA CAR110
annual report. Every report is through 31 December of its stated year.
The BSAI report explicitly includes CDQ. Catch is in metric tons.
These are totals for the quota accounts listed in each report; they are not
all-fisheries landings and should remain distinct from AKFIN GFSAFE001 totals.

Both regions include reported fixed-gear and trawl sablefish accounts.
The four GOA fixed-gear sablefish areas are Western Gulf, Central Gulf,
West Yakutat, and Southeast. Their account label is Hook-and-Line through
2016 and Fixed Gear from 2017, when NOAA authorized GOA IFQ longline pot gear.
The separate IFQ landing reports must not be added to these grand totals.
NOAA management source:
https://www.fisheries.noaa.gov/bulletin/ib-17-19-nmfs-authorizes-longline-pot-gear-gulf-alaska-sablefish-fixed-gear-fisheries

Both regions include squid through 2018 and sculpin through 2020. NOAA lists
those groups separately in ecosystem-component catch reports from 2019 and
2021, respectively. Other GOA rockfish area groupings also change. The
validation JSON records every change in observed area/account labels.

Reproduce from this directory (Python 3; R tidyverse, ggthemes, svglite):
  python3 scripts/build_regional_total_catch.py
  Rscript --vanilla R/plot_regional_total_catch.R

To replace archives with validated current NOAA source reports:
  python3 scripts/build_regional_total_catch.py --refresh

The source directory preserves original HTML bytes as .html.txt files;
manifest.json records URLs, UTC retrieval times, and SHA-256 hashes.
Offline builds verify all 26 hashes, report headings, metric-ton units,
31 December dates, one grand total per report, unique area/account keys,
and the account sum within whole-ton display rounding tolerance. Published
grand totals are used directly; sums of rounded rows are validation only.

All 13 BSAI published catch values were compared with the existing
BSAI_total_catch_by_year.csv and match exactly. Latest values:
  BSAI 2025: 1,774,231 t; report run Jan 29, 2026, 1:44:39 PM.
  GOA 2025:    231,545 t; report run Jan 29, 2026, 1:44:52 PM.
The 1,808 quota-account rows across 26 reports yield a maximum absolute
rounded-account-sum difference of 6 t. Offline replay and R figure rendering
completed with exit code 0, and the PNG was inspected visually.

Source index:
https://www.fisheries.noaa.gov/alaska/commercial-fishing/fisheries-catch-and-landings-reports-alaska

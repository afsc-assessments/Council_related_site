# BSAI and GOA annual groundfish catch: AKFIN Economic SAFE

This series uses the unique **All Groundfish** total for each region and year in the public **GFSAFE001** report. The report's available year selector begins in 2003. The archived September 29–30, 2026 retrieval covers all 23 years from 2003 through 2025 for BSAI and GOA.

Source report: <https://reports.psmfc.org/akfin/f?p=501:901:0:INITIAL>

Source provider's description of public access: <https://akfin.psmfc.org/public-access-to-economic-safe-data-through-akfin-apex-reports/>

## Contents

- `AKFIN_groundfish_catch_2003-2025.csv`: 46 annual regional totals with source URL, data status, refresh date, retrieval timestamp, and source-file SHA-256.
- `BSAI_AKFIN_groundfish_catch_by_year.csv` and `GOA_AKFIN_groundfish_catch_by_year.csv`: separate regional downloads with the same columns.
- `AKFIN_groundfish_catch_species_2003-2025.csv`: all 552 public source table rows (23 years × 3 geographic summaries × 8 species summaries). **All Groundfish**, **All Alaska**, and their component rows overlap; select the intended summary before aggregating.
- `AKFIN_groundfish_catch_validation.json`: annual checks of published totals against seven species groups and of BSAI plus GOA against All Alaska.
- `source/akfin-groundfish-catch/`: 12 original anonymous public HTML responses saved as `.html.txt`, plus `manifest.json`. Six-year batches contain at most 48 rows and fit within the source's 50-row display limit. The HTML includes ephemeral public APEX session identifiers; no login or account credentials were used.

## Units, scope, and status

Values are round-weight **metric tons**. Source footnotes state that catch includes retained catch and estimated discards; covers groundfish species managed under the BSAI and GOA groundfish fishery management plans; excludes halibut itself; and includes those groundfish species caught by vessels targeting halibut.

The archived pages report **Data last refreshed: September 15, 2026** and display the banner **“Groundfish Economic SAFE data are still preliminary.”** The CSV preserves that source status. The banner does not identify a separate finalization status for every historical year. The 2025 values are 1,794,251 t for BSAI and 245,152 t for GOA.

The Economic SAFE series and NOAA CAR110 annual quota-account series have different totals and reporting scope. Keep them separately named. For example, 2025 BSAI catch is 1,794,251 t in this Economic SAFE extraction and 1,774,231 t in the separately archived CAR110 report with CDQ. **Do not splice the two series or substitute one for the other under a shared label.**

The source includes seven component groups: Atka Mackerel, Flatfish, Other Groundfish, Pacific Cod, Pollock, Rockfish, and Sablefish. Changes to source species definitions and accounting methods can affect historical comparisons. The source's displayed totals are used directly; rounded species values are used only for checks. Confidentiality (`-9999`) and positive-below-display-precision (`-8888`) markers trigger a validation failure rather than becoming catch values.

## Reproduction

From the ABC_TAC repository root:

```sh
python3 scripts/build_akfin_groundfish_catch.py
```

This reads the archived pages, checks SHA-256 hashes, requires all expected region/year/species combinations exactly once, checks rounding differences, and reproduces CSV and JSON downloads under `doc/downloads/`.

To refresh the same 2003–2025 filters from the source:

```sh
python3 scripts/build_akfin_groundfish_catch.py --refresh
```

The initial checks passed for all 46 annual regional totals and 552 source rows. Maximum absolute differences were 2 t for sums of rounded species groups and 1 t for BSAI plus GOA versus the independently rounded All Alaska total.

Earlier Economic SAFE PDFs contain older catch series with different rounding precision and historical discard conventions. Those values have not been joined to this series.

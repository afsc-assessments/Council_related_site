# Data for the interactive time-series explorer

`time_series_explorer.csv` contains one row per dataset, region, source species label, measure and available source year. Values are metric tons. The builder reads the archived public datasets already distributed with this project and downloads no new data.

```sh
Rscript --vanilla build_explorer_data.R --input path/to/ABC_TAC --output path/to/output
```

Packages: dplyr, tidyr, readr, stringr, tibble and jsonlite. The validation JSON records package versions, totals checks, source overlaps and coverage. The script stops if source selection, source categories, documented rounding tolerances or recognized subtotal overlaps change.

## Selection and aggregation

- **AKFIN catch:** BSAI and GOA, 2003–2025. The `All groundfish` option uses the report's published `All Groundfish` total. Seven source species groups can be selected individually. The combined Alaska rows are excluded. Species groups and the regional total are separate plotting options; adding both would count the same catch twice. The source labels these data preliminary.
- **Harvest specifications:** the existing selected rows of the public ABC_TAC compilation (`OY=1`, `lag=1`, with GOA `Area=Total`). `All groundfish` uses the previously published annual sums. Individual species sum the selected area rows under each exact source species label. Capitalization and historical categories are preserved. A missing value remains missing when every selected entry is missing. A partial sum reports its missing-entry count. Explicit source zeros remain zero. GOA source coverage ends in 2024; BSAI ends in 2026.
- **NOAA quota-account catch:** BSAI and GOA, 2013–2025. `All groundfish` uses the published CAR110 total. Individual species sum the unique area/account rows under the source species name. Allocation qualifiers following a comma, parenthesis or `CDQ` token are removed for grouping; every account is assigned to exactly one reviewed species label. The exact assignment is downloadable as `time_series_explorer_car110_species_map.csv`. These groups combine sector, gear, subarea and CDQ entries, including fixed-gear and trawl sablefish. Squid entries end in 2018 and sculpin entries end in 2020; subsequent years remain absent.

Rounded AKFIN groups differ from the displayed regional totals by at most 2 t; rounded CAR110 groups differ by at most 6 t. Both sources' published totals are preserved. Their accounting scopes differ, so these catch datasets remain separately named. Species names and management groups differ among sources; the explorer provides no cross-source taxonomic reconciliation. Source categories and reporting coverage can change over time.

## Source compilation overlap

The archived BSAI specification compilation includes a Sablefish regional subtotal together with its BS and AI components in 1995 and 1996. The overlap amounts are 3,800 t for both ABC and TAC in 1995, and 2,500 t for ABC and 2,300 t for TAC in 1996. The explorer preserves the existing published compilation sums. Each affected Sablefish and `All groundfish` observation carries this explicit note. These source sums require reconciliation before treating them as independent regulatory totals.

GOA `Other Rockfish` has two distinct numeric TAC entries with identical species and area labels in each of 1986 and 1987. The source sums are preserved and repeated labels are flagged. Earlier BSAI repeated Shortraker labels contain missing placeholders; 2004 has one numeric row and one missing row. The builder checks all selected species-year-measure groups for numeric regional subtotals combined with area components, and checks all repeated numeric species-area-year-measure labels.

## Columns

| Column | Meaning |
|---|---|
| Dataset | Source-specific data series |
| Region | BSAI or GOA |
| Species | Exact source species/group label; `All groundfish` is the separately supplied regional sum |
| Measure | Catch, ABC, TAC or OFL |
| Year | Calendar catch year or specification projection year |
| Value_t | Metric tons; blank means unavailable |
| SourceRows | Number of contributing selected source rows; published catch totals use one total row |
| MissingRows | Number of selected source entries missing the measure |
| Coverage | Published regional total, Rounded source species group, Sum of rounded catch accounts, All selected entries numeric, Sum of available entries, or Unavailable |
| RepeatedLabels | Count of repeated species/area keys within the selected source rows; distinct geographic subtotal overlap is reported separately in Notes and validation |
| Source | Archived dataset's public source URL |
| Notes | Scope, source status, historical category changes and applicable overlap caveats |

The script performs no interpolation, zero filling, missing-year expansion or scientific correction of source values.

#!/usr/bin/env Rscript
# Build selection-ready plotting data from the archived public ABC_TAC datasets.
# Usage: Rscript build_explorer_data.R --input path/to/ABC_TAC --output outputdir
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(stringr)
  library(tibble)
  library(jsonlite)
})
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(key) {
  pos <- match(key, args)
  if (is.na(pos) || pos == length(args)) stop("Required argument: ", key)
  args[[pos + 1L]]
}
input <- normalizePath(get_arg("--input"), mustWork = TRUE)
output <- get_arg("--output")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
read_data <- function(name) read_csv(file.path(input, "data", name), show_col_types = FALSE, progress = FALSE)
assert <- function(condition, message) if (!isTRUE(condition)) stop(message)
sum_available <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
status <- function(n, missing) case_when(
  missing == n ~ "Unavailable",
  missing > 0L ~ "Sum of available entries",
  TRUE ~ "All selected entries numeric"
)
regions <- c("BSAI", "GOA")

# AKFIN: All Groundfish and Alaska combined summaries overlap their components.
# Keep only BSAI/GOA; official totals come from the regional-total file.
akfin_raw <- read_data("AKFIN_groundfish_catch_species_2003-2025.csv") %>% filter(Region %in% regions)
akfin_totals <- read_data("AKFIN_groundfish_catch_2003-2025.csv")
assert(nrow(akfin_raw) == 368L, "Unexpected AKFIN source coverage")
assert(!anyDuplicated(akfin_raw[c("Region", "Year", "Species_group")]), "Repeated AKFIN species keys")
akfin_source <- akfin_totals %>% select(Region, Year, Source = SourceURL)
akfin_components <- akfin_raw %>% filter(Species_group != "All Groundfish")
assert(all(count(akfin_components, Region, Year)$n == 7L), "AKFIN requires seven groups per region-year")
akfin_check <- akfin_components %>% group_by(Region, Year) %>% summarise(Species_sum_t = sum(Catch_t), .groups = "drop") %>%
  left_join(akfin_totals %>% select(Region, Year, Published_total_t = Catch_t), by = c("Region", "Year")) %>%
  mutate(Difference_t = Species_sum_t - Published_total_t)
assert(max(abs(akfin_check$Difference_t)) <= 2, "AKFIN groups exceed documented rounding tolerance")
akfin_source_check <- akfin_raw %>% filter(Species_group == "All Groundfish") %>%
  inner_join(akfin_totals %>% select(Region, Year, Official = Catch_t), by = c("Region", "Year"))
assert(all(akfin_source_check$Catch_t == akfin_source_check$Official), "AKFIN regional totals differ from source")
akfin_notes <- paste("Preliminary AKFIN Economic SAFE; retained catch plus estimated discards of FMP groundfish, including groundfish caught while targeting halibut.",
                      "Source refreshed September 15, 2026. Category definitions may change over time. AKFIN and NOAA CAR110 have different accounting scopes.")
akfin <- akfin_raw %>% left_join(akfin_source, by = c("Region", "Year")) %>% transmute(
  Dataset = "AKFIN catch", Region, Species = if_else(Species_group == "All Groundfish", "All groundfish", Species_group),
  Measure = "Catch", Year, Value_t = Catch_t, SourceRows = 1L, MissingRows = 0L,
  Coverage = if_else(Species_group == "All Groundfish", "Published regional total", "Rounded source species group"),
  RepeatedLabels = 0L, Source, Notes = akfin_notes
)

# Harvest specifications: use the existing OY=1, lag=1 selection, GOA Area=Total.
# Source categories are retained; explicit zeros stay zero and all-missing stays NA.
spec_raw <- read_data("BSAI_GOA_harvest_specifications_selected_rows.csv") %>% rename(Year = ProjYear)
spec_totals <- read_data("BSAI_GOA_harvest_specifications_by_year.csv")
assert(all(spec_raw$OY == 1 & spec_raw$lag == 1), "Specification selection differs from published selection")
assert(all(spec_raw$Area[spec_raw$Region == "GOA"] == "Total"), "GOA contains overlapping area components")
assert(!anyDuplicated(spec_raw[c("Region", "SourceRow")]), "Repeated specification source row ids")
# The archived compilation sums these overlapping 1995-1996 entries. Preserve
# that published sum, identify the exact affected measure-years, and flag it.
overlap <- spec_raw %>% pivot_longer(c(ABC, TAC, OFL), names_to = "Measure", values_to = "Entry") %>%
  group_by(Region, Year, Species, Measure) %>% summarise(
    HasSubtotal = any(Area %in% c("BSAI", "BSAI Total", "Total") & !is.na(Entry)),
    HasComponents = any(!Area %in% c("BSAI", "BSAI Total", "Total") & !is.na(Entry)),
    Overlap_t = sum(Entry[Area %in% c("BSAI", "BSAI Total", "Total")], na.rm = TRUE),
    NumericSubtotalRows = sum(Area %in% c("BSAI", "BSAI Total", "Total") & !is.na(Entry)),
    NumericComponentRows = sum(!Area %in% c("BSAI", "BSAI Total", "Total") & !is.na(Entry)),
    .groups = "drop"
  ) %>% filter(HasSubtotal & HasComponents) %>% select(-HasSubtotal, -HasComponents)
assert(nrow(overlap) == 4L && all(overlap$Region == "BSAI") && all(overlap$Species == "Sablefish") &&
       all(overlap$Year %in% c(1995, 1996)) && all(overlap$Measure %in% c("ABC", "TAC")),
       "Unreviewed overlapping specification subtotal")
repeated_numeric <- spec_raw %>% pivot_longer(c(ABC, TAC, OFL), names_to = "Measure", values_to = "Entry") %>%
  group_by(Region, Year, Species, Area, Measure) %>% summarise(
    NumericRows = sum(!is.na(Entry)), .groups = "drop"
  ) %>% filter(NumericRows > 1L)
assert(nrow(repeated_numeric) == 2L && all(repeated_numeric$Region == "GOA") &&
       all(repeated_numeric$Species == "Other Rockfish") && all(repeated_numeric$Year %in% c(1986, 1987)) &&
       all(repeated_numeric$Measure == "TAC"), "Unreviewed repeated numeric specification labels")
spec_sources <- spec_totals %>% distinct(Region, Source = source_url)
assert(nrow(spec_sources) == 2L, "More than one source revision per specification region")
repeated <- spec_raw %>% count(Region, Year, Species, Area, name = "Entries") %>%
  group_by(Region, Year, Species) %>% summarise(RepeatedLabels = sum(Entries > 1L), .groups = "drop")
spec_long <- spec_raw %>% pivot_longer(c(ABC, TAC, OFL), names_to = "Measure", values_to = "Value_t")
spec_species <- spec_long %>% group_by(Region, Species, Measure, Year) %>% summarise(
  SourceRows = n(), MissingRows = sum(is.na(Value_t)),
  Value_t = sum_available(Value_t), .groups = "drop"
) %>% left_join(repeated, by = c("Region", "Year", "Species"))
spec_computed <- spec_long %>% group_by(Region, Measure, Year) %>% summarise(
  ExpectedRows = n(), ExpectedMissing = sum(is.na(Value_t)), NumericSum = sum_available(Value_t), .groups = "drop"
)
spec_annual <- spec_totals %>% select(Region, Year, ends_with("_t"), n_source_rows, n_duplicate_label_keys,
                                     ends_with("_n_missing")) %>%
  pivot_longer(c(ABC_t, TAC_t, OFL_t), names_to = "Measure", names_pattern = "(.*)_t", values_to = "Value_t") %>%
  mutate(MissingRows = case_when(Measure == "ABC" ~ ABC_n_missing, Measure == "TAC" ~ TAC_n_missing, TRUE ~ OFL_n_missing)) %>%
  transmute(Region, Species = "All groundfish", Measure, Year, Value_t, SourceRows = n_source_rows,
            MissingRows, RepeatedLabels = n_duplicate_label_keys)
spec_comparison <- spec_annual %>% left_join(spec_computed, by = c("Region", "Measure", "Year"))
assert(all((is.na(spec_comparison$Value_t) & is.na(spec_comparison$NumericSum)) |
           (!is.na(spec_comparison$Value_t) & !is.na(spec_comparison$NumericSum) & spec_comparison$Value_t == spec_comparison$NumericSum)),
       "Specification annual totals differ from selected row sums")
assert(all(spec_comparison$SourceRows == spec_comparison$ExpectedRows & spec_comparison$MissingRows == spec_comparison$ExpectedMissing),
       "Specification counts differ from source")
spec_species_check <- spec_species %>% group_by(Region, Measure, Year) %>% summarise(
  Species_sum_t = sum_available(Value_t), SpeciesRows = sum(SourceRows), SpeciesMissing = sum(MissingRows), .groups = "drop"
) %>% left_join(spec_annual %>% select(Region, Measure, Year, Value_t, SourceRows, MissingRows), by = c("Region", "Measure", "Year"))
assert(all((is.na(spec_species_check$Value_t) & is.na(spec_species_check$Species_sum_t)) |
           (!is.na(spec_species_check$Value_t) & !is.na(spec_species_check$Species_sum_t) & spec_species_check$Value_t == spec_species_check$Species_sum_t)),
       "Specification species sums differ from annual sums")
assert(all(spec_species_check$SourceRows == spec_species_check$SpeciesRows & spec_species_check$MissingRows == spec_species_check$SpeciesMissing),
       "Species aggregation lost specification rows or missing entries")
spec <- bind_rows(spec_annual, spec_species) %>% left_join(spec_sources, by = "Region") %>% mutate(
  Dataset = "Harvest specifications", Coverage = status(SourceRows, MissingRows),
  Notes = paste("Public ABC_TAC compilation: OY=1, lag=1; GOA uses Area=Total. Source species labels are retained and area entries are summed within species.",
                "Source categories change over time; missing entries remain missing. GOA Other Rockfish in 1986 and 1987 contains two distinct TAC entries under repeated source labels; these sums follow the public compilation.")
) %>% left_join(
  bind_rows(overlap %>% select(Region, Year, Species, Measure, Overlap_t),
            overlap %>% mutate(Species = "All groundfish") %>% select(Region, Year, Species, Measure, Overlap_t)),
  by = c("Region", "Year", "Species", "Measure")
) %>% mutate(
  Notes = if_else(!is.na(Overlap_t),
                  paste0("Source compilation includes overlapping regional subtotal and area components. Sablefish subtotal counted in addition to its BS and AI components: ",
                         format(Overlap_t, scientific = FALSE, trim = TRUE), " metric tons. ", Notes), Notes)
) %>% select(Dataset, Region, Species, Measure, Year, Value_t, SourceRows, MissingRows, Coverage, RepeatedLabels, Source, Notes)

# CAR110: each source area/account row belongs to one source species label.
# Allocation qualifiers (sector, gear, CDQ, subarea) follow a comma, parenthesis,
# or CDQ token. The published totals remain independent from rounded row sums.
car_raw <- read_data("regional_catch_accounts_2013_2025.csv")
car_totals <- read_data("regional_total_catch_2013_2025.csv")
assert(!anyDuplicated(car_raw[c("Region", "Year", "Area", "Account")]), "Repeated CAR110 account keys")
car_map <- car_raw %>% distinct(Region, Account) %>% mutate(
  Species = str_trim(str_remove(Account, "(?:,| \\(| CDQ).*$"))
)
allowed_species <- c("Alaska Plaice", "Arrowtooth Flounder", "Atka Mackerel", "Big Skate", "Deep Water Flatfish",
                     "Demersal Shelf Rockfish", "Dusky Rockfish", "Flathead Sole", "Greenland Turbot", "Kamchatka Flounder",
                     "Longnose Skate", "Northern Rockfish", "Octopus", "Other Flatfish", "Other Rockfish", "Other Skates",
                     "Pacific Cod", "Pacific Ocean Perch", "Pollock", "Rex Sole", "Rock Sole", "Rougheye Rockfish",
                     "Sablefish", "Sculpin", "Shallow Water Flatfish", "Shark", "Shortraker Rockfish", "Skate", "Squid",
                     "Thornyhead Rockfish", "Yellowfin Sole")
assert(all(car_map$Species %in% allowed_species), "Unreviewed CAR110 species label: review account mapping")
car_labeled <- car_raw %>% left_join(car_map, by = c("Region", "Account"))
assert(nrow(car_labeled) == nrow(car_raw) && !anyNA(car_labeled$Species), "CAR110 mapping lost or duplicated accounts")
car_species <- car_labeled %>% group_by(Region, Year, Species) %>% summarise(
  Value_t = sum(Catch_t), SourceRows = n(), MissingRows = sum(is.na(Catch_t)), .groups = "drop"
)
assert(all(car_species$MissingRows == 0L), "Unexpected missing CAR110 catches")
car_check <- car_species %>% group_by(Region, Year) %>% summarise(
  Species_sum_t = sum(Value_t), SourceRows = sum(SourceRows), .groups = "drop"
) %>% left_join(car_totals %>% select(Region, Year, Published_total_t = Catch_t), by = c("Region", "Year")) %>%
  mutate(Difference_t = Species_sum_t - Published_total_t)
assert(max(abs(car_check$Difference_t)) <= 6, "CAR110 species sums exceed documented rounding tolerance")
assert(sum(car_species$SourceRows) == nrow(car_raw), "CAR110 accounts contribute more or less than once")
car_sources <- car_totals %>% select(Region, Year, Source = SourceURL)
car_species <- car_species %>% mutate(Coverage = "Sum of rounded catch accounts")
car_annual <- car_totals %>% transmute(Region, Year, Species = "All groundfish", Value_t = Catch_t,
                                     SourceRows = 1L, MissingRows = 0L, Coverage = "Published regional total")
car <- bind_rows(car_annual, car_species) %>% left_join(car_sources, by = c("Region", "Year")) %>% transmute(
  Dataset = "NOAA quota-account catch", Region, Species, Measure = "Catch", Year, Value_t,
  SourceRows, MissingRows, Coverage, RepeatedLabels = 0L, Source,
  Notes = paste("NOAA CAR110 annual quota accounts through December 31; BSAI includes CDQ. Species sums combine listed area, gear and sector accounts.",
                "Sablefish includes fixed-gear and trawl accounts. Squid accounts end in 2018 and sculpin in 2020; absent categories remain unavailable.",
                "Species sums can differ from published regional totals by up to 6 t because source rows are rounded. CAR110 and AKFIN scopes differ.")
)

explorer <- bind_rows(akfin, spec, car) %>% arrange(Dataset, Region, Species, Measure, Year)
assert(!anyDuplicated(explorer[c("Dataset", "Region", "Species", "Measure", "Year")]), "Repeated explorer selection key")
assert(all(is.na(explorer$Value_t) | (is.finite(explorer$Value_t) & explorer$Value_t >= 0)), "Invalid explorer values")
assert(all(explorer$Region %in% regions), "Unexpected combined-region row")
assert(all(!is.na(explorer$Source) & str_starts(explorer$Source, "https://")), "Source URLs missing")
# Key known edge cases guard against converting missing observations to zero.
assert(is.na(filter(explorer, Dataset == "Harvest specifications", Region == "BSAI", Species == "All groundfish", Year == 1986, Measure == "OFL")$Value_t), "All-missing OFL converted to zero")
edge <- filter(explorer, Dataset == "Harvest specifications", Region == "BSAI", Species == "All groundfish", Year == 1991, Measure == "OFL")
assert(edge$Value_t == 0 && edge$MissingRows == 28 && edge$Coverage == "Sum of available entries", "Explicit partial OFL zero lost")
assert(!any(car$Species == "Squid" & car$Year > 2018) && !any(car$Species == "Sculpin" & car$Year > 2020), "Removed CAR110 categories were filled")

write_csv(explorer, file.path(output, "time_series_explorer.csv"), na = "")
write_csv(car_map %>% arrange(Region, Species, Account), file.path(output, "time_series_explorer_car110_species_map.csv"))
validation <- list(
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  passed = TRUE, rows = nrow(explorer), unique_selection_keys = TRUE,
  units = "metric tons", no_interpolation_or_missing_year_fill = TRUE,
  region_year_species_selection_counts = explorer %>% count(Dataset, Region, name = "plotting_rows"),
  coverage = explorer %>% group_by(Dataset, Region) %>% summarise(first_year = min(Year), last_year = max(Year), species_options = n_distinct(Species), .groups = "drop"),
  akfin_species_rounding_max_t = max(abs(akfin_check$Difference_t)),
  akfin_published_totals_match_raw_all_groundfish = TRUE,
  akfin_rounding_checks = akfin_check,
  specification_annual_measures_checked = nrow(spec_comparison),
  specification_exact_annual_sums_match = TRUE,
  specification_species_sums_match = TRUE,
  specification_all_missing_annual_measures = sum(is.na(spec_annual$Value_t)),
  specification_repeated_label_groups = repeated %>% filter(RepeatedLabels > 0L),
  specification_overlapping_subtotals_preserved_and_flagged = overlap,
  specification_overlapping_subtotal_measures = nrow(overlap),
  specification_repeated_numeric_labels = repeated_numeric,
  specification_overlap_audit_scope = "Every species-year-measure in selected input: numeric Area BSAI, BSAI Total or Total plus numeric area components; all repeated numeric species-area-year-measure labels also checked",
  specification_both_source_row_counts_and_missing_counts_match = TRUE,
  car110_source_accounts = nrow(car_raw), car110_mapped_accounts = nrow(car_labeled),
  car110_mapping_labels = nrow(car_map), car110_species_options = n_distinct(car_map$Species),
  car110_each_source_account_counted_once = TRUE,
  car110_species_rounding_max_t = max(abs(car_check$Difference_t)), car110_rounding_checks = car_check,
  edge_cases = c("1986 BSAI OFL remains unavailable", "1991 BSAI partial OFL zero retained with 28 missing source entries",
                "Squid and sculpin omitted after their CAR110 categories ended", "AKFIN Alaska combined rows excluded",
                "Regional totals kept separate from rounded species sums"),
  package_versions = setNames(lapply(c("dplyr", "tidyr", "readr", "stringr", "jsonlite"), function(x) as.character(packageVersion(x))),
                             c("dplyr", "tidyr", "readr", "stringr", "jsonlite")),
  R_version = R.version.string
)
write_json(validation, file.path(output, "time_series_explorer_validation.json"), auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("Validated", nrow(explorer), "plotting rows; AKFIN max rounding", max(abs(akfin_check$Difference_t)),
    "t; CAR110 max rounding", max(abs(car_check$Difference_t)), "t;", nrow(spec_comparison), "specification annual measures agree.\n")

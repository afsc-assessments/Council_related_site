#!/usr/bin/env Rscript
# Rebuild the public ABC_TAC compilation from a pinned upstream revision.
# Run from any directory: Rscript R/build_harvest_specifications.R [--refresh]
# Packages: dplyr, tidyr, readr, ggplot2, ggthemes, gt, jsonlite, digest, svglite.
# --refresh retrieves the same pinned files; changing the revision requires review.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})
options(warn = 2)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Run this script with Rscript.")
project_root <- dirname(dirname(normalizePath(sub("^--file=", "", script_arg))))
source_dir <- file.path(project_root, "data", "source", "harvest-specifications")
data_dir <- file.path(project_root, "data")
figure_dir <- file.path(project_root, "doc", "figures")
table_dir <- file.path(project_root, "doc", "tables")
for (path in c(source_dir, data_dir, figure_dir, table_dir)) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
}
revision <- "84f019ebd44658503702944d65d3a52a9f76c889"
commit_date <- "2026-04-16T05:42:03Z"
repository <- "https://github.com/jimianelli/ABC_TAC"
source_files <- tibble::tribble(
  ~Region, ~filename, ~sha256,
  "BSAI", "BSAI_OFL_ABC_TAC.csv", "df5dc9499c8cadfe049d3fcce45ad46e2eb85d93c5e825990adfc5ef8821b250",
  "GOA", "GOA_OFL_ABC_TAC_specs.csv", "b1d92e9b89f40aa444f514494ad8a5d8f4453a9bdadfda9efab278ff53161c42"
) |>
  mutate(
    path = file.path(source_dir, filename),
    url = paste0("https://raw.githubusercontent.com/jimianelli/ABC_TAC/", revision, "/data/", filename),
    source_page = paste0(repository, "/blob/", revision, "/data/", filename),
    retrieved_at_utc = NA_character_
  )
manifest_path <- file.path(source_dir, "manifest.json")
old_manifest <- if (file.exists(manifest_path)) jsonlite::read_json(manifest_path, simplifyVector = TRUE) else NULL
refresh <- "--refresh" %in% commandArgs(trailingOnly = TRUE)
for (i in seq_len(nrow(source_files))) {
  path <- source_files$path[i]
  if (refresh || !file.exists(path)) {
    utils::download.file(source_files$url[i], path, mode = "wb", quiet = TRUE)
  }
  actual_hash <- digest::digest(file = path, algo = "sha256", serialize = FALSE)
  if (!identical(actual_hash, source_files$sha256[i])) stop("Pinned input hash mismatch: ", basename(path))
  old <- if (!is.null(old_manifest)) old_manifest$files |> filter(filename == source_files$filename[i]) else NULL
  source_files$retrieved_at_utc[i] <- if (!refresh && !is.null(old) && nrow(old) == 1L) {
    old$retrieved_at_utc
  } else {
    format(file.info(path)$mtime, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  }
}
manifest <- list(
  repository = repository,
  revision = revision,
  revision_committed_at_utc = commit_date,
  retrieval_note = "Version-pinned raw GitHub files; bytes retained unchanged. Retrieval times recorded from download completion.",
  upstream_report_source = paste0(repository, "/blob/", revision, "/doc/index.qmd"),
  files = source_files |> select(-path)
)
jsonlite::write_json(manifest, manifest_path, pretty = TRUE, auto_unbox = TRUE, na = "null")

# Explicit types preserve source zeroes and blanks. SourceRow identifies the
# physical data row because some historical species/area labels are repeated.
read_source <- function(path, region) {
  result <- read_csv(path, col_types = cols(
    AssmentYr = col_integer(), ProjYear = col_integer(), lag = col_integer(),
    Species = col_character(), Area = col_character(), OFL = col_double(),
    ABC = col_double(), TAC = col_double(), Order = col_double(), OY = col_double(),
    .default = col_character()
  ), na = c("", "NA"), progress = FALSE)
  if (nrow(problems(result))) stop("CSV parsing problems in ", basename(path))
  result |> mutate(Region = region, SourceRow = row_number(), .before = 1)
}
raw <- bind_rows(lapply(seq_len(nrow(source_files)), function(i) {
  read_source(source_files$path[i], source_files$Region[i])
}))
selected <- raw |>
  filter(OY == 1, lag == 1, Region == "BSAI" | Area == "Total") |>
  arrange(Region, ProjYear, SourceRow)
stopifnot(!anyDuplicated(selected[c("Region", "SourceRow")]))
stopifnot(all(selected$OFL >= 0 | is.na(selected$OFL)),
          all(selected$ABC >= 0 | is.na(selected$ABC)),
          all(selected$TAC >= 0 | is.na(selected$TAC)))
label_keys <- c("Region", "AssmentYr", "ProjYear", "lag", "Species", "Area")
duplicate_keys <- selected |>
  count(across(all_of(label_keys)), name = "source_rows") |>
  filter(source_rows > 1)
duplicate_rows <- selected |> semi_join(duplicate_keys, by = label_keys)
write_csv(duplicate_rows, file.path(data_dir, "harvest_specifications_duplicate_labels.csv"), na = "")
write_csv(selected, file.path(data_dir, "BSAI_GOA_harvest_specifications_selected_rows.csv"), na = "")

# A numeric sum is retained whenever at least one row is numeric. A measure
# with no numeric source entries remains missing; all missing never means zero.
annual_long <- selected |>
  select(Region, Year = ProjYear, Species, SourceRow, OFL, ABC, TAC) |>
  pivot_longer(c(OFL, ABC, TAC), names_to = "Measure", values_to = "value_t") |>
  group_by(Region, Year, Measure) |>
  summarise(
    value_t = if (all(is.na(value_t))) NA_real_ else sum(value_t, na.rm = TRUE),
    .groups = "drop"
  )
counts <- selected |>
  select(Region, Year = ProjYear, SourceRow, OFL, ABC, TAC) |>
  pivot_longer(c(OFL, ABC, TAC), names_to = "Measure", values_to = "source_value_t") |>
  group_by(Region, Year, Measure) |>
  summarise(n_source_rows = n(), n_numeric = sum(!is.na(source_value_t)),
            n_missing = sum(is.na(source_value_t)),
            n_zero = sum(source_value_t == 0, na.rm = TRUE), .groups = "drop")
annual_long <- annual_long |>
  left_join(counts, by = c("Region", "Year", "Measure")) |>
  mutate(status = case_when(n_numeric == 0 ~ "unavailable",
                            n_missing > 0 ~ "sum_of_available_entries",
                            TRUE ~ "all_selected_entries_numeric"))
row_counts <- selected |>
  group_by(Region, Year = ProjYear) |>
  summarise(n_source_rows = n(), n_species_labels = n_distinct(Species), .groups = "drop")
duplicate_counts <- duplicate_keys |>
  group_by(Region, Year = ProjYear) |>
  summarise(n_duplicate_label_keys = n(), .groups = "drop")
annual <- annual_long |>
  select(-n_source_rows) |>
  pivot_wider(names_from = Measure, values_from = c(value_t, n_numeric, n_missing, n_zero, status),
              names_glue = "{Measure}_{.value}") |>
  rename(OFL_t = OFL_value_t, ABC_t = ABC_value_t, TAC_t = TAC_value_t) |>
  left_join(row_counts, by = c("Region", "Year")) |>
  left_join(duplicate_counts, by = c("Region", "Year")) |>
  mutate(n_duplicate_label_keys = replace_na(n_duplicate_label_keys, 0L),
         units = "metric tons", source_revision = revision,
         source_status = "Public ABC_TAC compilation; source categories retained",
         selection = if_else(Region == "BSAI", "OY = 1; lag = 1", "OY = 1; lag = 1; Area = Total")) |>
  left_join(source_files |> select(Region, source_file = filename, source_url = source_page,
                                    source_sha256 = sha256), by = "Region") |>
  select(Region, Year, OFL_t, ABC_t, TAC_t, n_source_rows, n_species_labels,
         n_duplicate_label_keys, everything()) |>
  arrange(Region, Year)
stopifnot(!anyDuplicated(annual[c("Region", "Year")]), nrow(annual) == 80L)
for (region in c("BSAI", "GOA")) {
  years <- annual$Year[annual$Region == region]
  stopifnot(identical(years, seq.int(min(years), max(years))))
}
write_csv(annual, file.path(data_dir, "BSAI_GOA_harvest_specifications_by_year.csv"), na = "")
for (region in c("BSAI", "GOA")) {
  write_csv(filter(annual, Region == region),
            file.path(data_dir, paste0(region, "_harvest_specifications_by_year.csv")), na = "")
}

# Independent comparison follows the exact report grouping: BSAI sums by
# species and Order before summing the year; GOA sums Area=Total rows by year.
bsai_report <- raw |>
  filter(Region == "BSAI", OY == 1) |>
  group_by(Year = ProjYear, lag, Species, Order) |>
  summarise(across(c(OFL, ABC, TAC), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
  filter(lag == 1) |>
  group_by(Year) |>
  summarise(across(c(OFL, ABC, TAC), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
  mutate(Region = "BSAI")
goa_report <- raw |>
  filter(Region == "GOA", OY == 1, lag == 1, Area == "Total") |>
  group_by(Year = ProjYear) |>
  summarise(across(c(OFL, ABC, TAC), ~sum(.x, na.rm = TRUE)), .groups = "drop") |>
  mutate(Region = "GOA")
comparison <- bind_rows(bsai_report, goa_report) |>
  pivot_longer(c(OFL, ABC, TAC), names_to = "Measure", values_to = "upstream_report_sum_t") |>
  left_join(annual_long, by = c("Region", "Year", "Measure")) |>
  mutate(difference_t = value_t - upstream_report_sum_t,
         check = case_when(n_numeric == 0 & upstream_report_sum_t == 0 & is.na(value_t) ~ "all_missing_retained_as_missing",
                           abs(difference_t) < 1e-7 ~ "matches_upstream_report_sum",
                           TRUE ~ "mismatch")) |>
  arrange(Region, Year, Measure)
stopifnot(!any(comparison$check == "mismatch"),
          all(is.na(annual_long$value_t[annual_long$n_numeric == 0])))
write_csv(comparison, file.path(data_dir, "harvest_specifications_report_comparison.csv"), na = "")

plot_data <- annual_long |>
  mutate(Measure = factor(Measure, levels = c("TAC", "ABC", "OFL")))
plot_series <- function(x) {
  ggplot(x, aes(Year, value_t / 1e6, colour = Measure, linetype = Measure, group = Measure)) +
    geom_line(linewidth = 0.85, na.rm = TRUE) +
    geom_point(data = filter(x, n_missing > 0, n_numeric > 0), shape = 21,
               fill = "white", size = 1.65, stroke = 0.6, na.rm = TRUE) +
    scale_colour_manual(values = c(TAC = "#0072B2", ABC = "#D55E00", OFL = "#009E73")) +
    scale_linetype_manual(values = c(TAC = "solid", ABC = "longdash", OFL = "dotdash")) +
    scale_x_continuous(breaks = c(1986, 1990, 2000, 2010, 2020, 2026)) +
    scale_y_continuous(limits = c(0, NA), labels = scales::label_number(accuracy = 0.1)) +
    facet_wrap(vars(Region), ncol = 1, scales = "free_y") +
    labs(x = "Specification year", y = "Million metric tons", colour = NULL, linetype = NULL,
         title = "BSAI and GOA harvest specifications",
         subtitle = "Full available annual series from the public ABC_TAC compilation",
         caption = "TAC: total allowable catch. ABC: acceptable biological catch. OFL: overfishing limit.\nOpen circles mark sums with missing source entries. All-missing measures are blank.\nSource: jimianelli/ABC_TAC, revision 84f019e (16 April 2026).") +
    ggthemes::theme_few(base_size = 12) +
    theme(legend.position = "top", plot.title.position = "plot",
          plot.caption = element_text(hjust = 0, size = 9),
          strip.text = element_text(face = "bold"), panel.spacing = grid::unit(1.2, "lines"))
}
chart <- plot_series(plot_data)
ggsave(file.path(figure_dir, "bsai-goa-harvest-specifications-by-year.png"), chart,
       width = 11, height = 8, units = "in", dpi = 180, bg = "white")
ggsave(file.path(figure_dir, "bsai-goa-harvest-specifications-by-year.svg"), chart,
       width = 11, height = 8, units = "in", bg = "white")

table_data <- annual |>
  select(Region, Year, TAC_t, ABC_t, OFL_t, n_source_rows, n_duplicate_label_keys)
annual_table <- gt::gt(table_data, groupname_col = "Region", id = "harvest-specifications-by-year") |>
  gt::tab_header(title = "Annual harvest specifications", subtitle = "Metric tons; public ABC_TAC source compilation") |>
  gt::cols_label(Year = "Year", TAC_t = "TAC", ABC_t = "ABC", OFL_t = "OFL",
                 n_source_rows = "Source rows", n_duplicate_label_keys = "Repeated label keys") |>
  gt::fmt_number(columns = c(TAC_t, ABC_t, OFL_t), decimals = 0) |>
  gt::sub_missing(columns = c(TAC_t, ABC_t, OFL_t), missing_text = "Unavailable") |>
  gt::tab_source_note("Values are sums of available entries. The CSV reports missing, numeric and zero counts separately for each measure. Species and area categories follow the source.") |>
  gt::tab_source_note("BSAI: OY = 1 and lag = 1. GOA: OY = 1, lag = 1 and Area = Total. Source revision: 84f019ebd44658503702944d65d3a52a9f76c889.") |>
  gt::tab_source_note("Repeated labels are retained: BSAI Shortraker rockfish in 1986–2004; GOA Other Rockfish in 1986–1987. See the duplicate-label CSV for original rows.")
for (measure in c("TAC", "ABC", "OFL")) {
  partial <- which(annual[[paste0(measure, "_n_missing")]] > 0 & annual[[paste0(measure, "_n_numeric")]] > 0)
  annual_table <- gt::tab_footnote(annual_table,
    footnote = "Sum of available entries; some selected source rows are missing.",
    locations = gt::cells_body(columns = all_of(paste0(measure, "_t")), rows = partial))
}
gt::gtsave(annual_table, file.path(table_dir, "harvest-specifications-by-year.html"))
table_path <- file.path(table_dir, "harvest-specifications-by-year.html")
table_html <- readLines(table_path, warn = FALSE)
table_html <- sub("<head>", "<head>\n<title>GOA and BSAI annual harvest specifications</title>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>", table_html, fixed = TRUE)
writeLines(table_html, table_path, useBytes = TRUE)

validation <- list(
  generated_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  source_revision = revision,
  units = "metric tons",
  raw_source_row_counts = raw |> count(Region, name = "source_rows"),
  selected_source_row_counts = selected |> count(Region, name = "selected_rows"),
  unique_source_row_ids = TRUE,
  unique_species_area_year_keys = nrow(duplicate_keys) == 0L,
  repeated_species_area_year_keys = duplicate_keys,
  repeated_label_note = "Raw rows are retained unchanged. BSAI repeated Shortraker rows are missing placeholders except one numeric row in 2004. GOA Other Rockfish entries have distinct TAC values in 1986 and 1987; this extraction follows the published report sums and flags the repeated labels.",
  annual_coverage = annual |> group_by(Region) |>
    summarise(first_year = min(Year), last_year = max(Year), years = n(), .groups = "drop"),
  contiguous_annual_years = TRUE,
  comparison_method = "Independent recreation of grouping in pinned upstream doc/index.qmd sections BSAI totals by year and GOA totals by year. Upstream sum(na.rm=TRUE) returns zero for all-missing groups; these outputs retain missing instead.",
  report_comparison = comparison |> count(check, name = "annual_measure_records"),
  maximum_absolute_difference_for_available_sums_t = max(abs(comparison$difference_t), na.rm = TRUE),
  missing_status_counts = annual_long |> count(Region, Measure, status, name = "years"),
  retained_zero_source_entries = selected |>
    summarise(across(c(OFL, ABC, TAC), ~sum(.x == 0, na.rm = TRUE))),
  zero_source_note = "BSAI 1991 OFL has one explicit numeric zero and 28 missing selected source rows. Its sum is retained as zero and marked as a sum of available entries.",
  year_checks = annual |> filter((Region == "BSAI" & Year %in% c(1986, 2002, 2025, 2026)) |
                                 (Region == "GOA" & Year %in% c(1986, 1987, 2024))) |>
    select(Region, Year, OFL_t, ABC_t, TAC_t, n_source_rows),
  interpretation = "Sums reproduce the selected rows of the public compilation. Missing entries and repeated labels are source conditions, not evidence of a complete independently reconciled regulatory total. BSAI 2026 specifications extend beyond the latest complete catch year. GOA source coverage stops in 2024.",
  package_versions = as.list(vapply(c("dplyr", "tidyr", "readr", "ggplot2", "ggthemes", "gt", "jsonlite", "digest", "svglite"), function(p) as.character(packageVersion(p)), character(1))),
  R_version = R.version.string
)
jsonlite::write_json(validation, file.path(data_dir, "harvest_specifications_validation.json"),
                     pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("Validated", nrow(annual), "annual rows;", sum(comparison$check == "matches_upstream_report_sum"),
    "available sums match the upstream report;", sum(comparison$check == "all_missing_retained_as_missing"),
    "all-missing sums remain blank.\n")
print(validation$annual_coverage)
print(validation$report_comparison)

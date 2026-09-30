#!/usr/bin/env Rscript
# Run from the ABC_TAC root, or supply that directory as the first argument.
suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
  library(ggthemes)
  library(scales)
  library(gt)
})
options(warn = 2)
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1]] else "."
data_file <- file.path(root, "data/AKFIN_groundfish_catch_2003-2025.csv")
d <- read_csv(data_file, show_col_types = FALSE) |>
  arrange(Region, Year)
stopifnot(nrow(d) == 46L, !anyDuplicated(d[c("Region", "Year")]),
          identical(sort(unique(d$Year)), as.double(2003:2025)),
          all(is.finite(d$Catch_t)), all(d$Catch_t > 0))

p <- ggplot(d, aes(Year, Catch_t / 1e6)) +
  geom_line(colour = "#23647b", linewidth = 0.75) +
  geom_point(colour = "#23647b", size = 1.5) +
  facet_wrap(vars(Region), ncol = 1, scales = "free_y") +
  scale_y_continuous(limits = c(0, NA), labels = label_number(accuracy = 0.1),
                     expand = expansion(mult = c(0, 0.08))) +
  scale_x_continuous(breaks = c(2003, 2007, 2011, 2015, 2019, 2023, 2025)) +
  labs(title = "GOA and BSAI annual groundfish catch",
       subtitle = "AKFIN Economic SAFE report GFSAFE001 | 2003–2025",
       x = "Year", y = "Catch (million metric tons)",
       caption = "Source status: preliminary; refreshed 15 September 2026.\nRetained and discarded FMP groundfish catch; includes groundfish caught while targeting halibut.") +
  theme_few(base_size = 12) +
  theme(strip.text = element_text(face = "bold"),
        plot.title = element_text(face = "bold"),
        plot.caption = element_text(hjust = 0, size = 9),
        panel.spacing = grid::unit(1, "lines"))
figdir <- file.path(root, "doc/figures")
tabdir <- file.path(root, "doc/tables")
dir.create(figdir, recursive = TRUE, showWarnings = FALSE)
dir.create(tabdir, recursive = TRUE, showWarnings = FALSE)
ggsave(file.path(figdir, "akfin-regional-catch-by-year.png"), p,
       width = 9, height = 7, dpi = 180, bg = "white")
ggsave(file.path(figdir, "akfin-regional-catch-by-year.svg"), p,
       width = 9, height = 7, bg = "white")
tab <- d |>
  select(Region, Year, Catch_t) |>
  gt(groupname_col = "Region", id = "akfin-regional-catch-by-year") |>
  tab_header(title = "GOA and BSAI annual groundfish catch",
             subtitle = "AKFIN Economic SAFE GFSAFE001 · 2003–2025 · preliminary") |>
  cols_label(Year = "Year", Catch_t = "Catch (metric tons)") |>
  fmt_number(columns = Catch_t, decimals = 0, use_seps = TRUE) |>
  tab_source_note("Source refreshed 15 September 2026. Includes retained and discarded FMP groundfish catch, including catch while targeting halibut.") |>
  tab_source_note("NOAA CAR110 quota-account totals are provided as a separate series with their own scope.") |>
  tab_options(table.width = pct(100), table.font.names = c("Arial", "sans-serif"))
gtsave(tab, file.path(tabdir, "akfin-regional-catch-by-year.html"))
table_path <- file.path(tabdir, "akfin-regional-catch-by-year.html")
html <- readLines(table_path, warn = FALSE)
html <- sub("<head>", "<head>\n<title>GOA and BSAI annual groundfish catch, 2003–2025</title>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>", html, fixed = TRUE)
writeLines(html, table_path, useBytes = TRUE)
cat("Validated and plotted 46 region-years; annual table saved.\n")

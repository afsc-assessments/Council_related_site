#!/usr/bin/env Rscript
# Run from the ABC_TAC directory, or pass its path as the first argument.
suppressPackageStartupMessages({
  library(tidyverse)
  library(ggthemes)
})
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) normalizePath(args[[1]], mustWork = TRUE) else getwd()
series <- read_csv(file.path(root, "data", "regional_total_catch_2013_2025.csv"),
                   show_col_types = FALSE) |>
  mutate(Region = factor(Region, levels = c("BSAI", "GOA")))
stopifnot(nrow(series) == 26L,
          !anyDuplicated(series[c("Region", "Year")]),
          all(is.finite(series$Catch_t)), all(series$Catch_t > 0),
          all(series$Through == paste0("31-Dec-", series$Year)),
          all(sort(unique(series$Year)) == 2013:2025))
latest <- series |> filter(Year == max(Year))
p <- ggplot(series, aes(Year, Catch_t / 1e6, color = Region)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  geom_text(data = latest,
            aes(label = paste0(scales::comma(Catch_t), " t")),
            hjust = -0.12, size = 3.8, show.legend = FALSE) +
  facet_wrap(vars(Region), ncol = 1, scales = "free_y") +
  scale_color_manual(values = c(BSAI = "#145874", GOA = "#B66A29"), guide = "none") +
  scale_x_continuous(breaks = seq(2013, 2025, 2), limits = c(2013, 2027.8),
                     expand = expansion(mult = c(0.02, 0))) +
  scale_y_continuous(limits = c(0, NA), breaks = scales::breaks_pretty(5),
                     labels = scales::label_number(accuracy = 0.01),
                     expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Annual catch in NOAA quota accounts",
       subtitle = "Complete calendar years, 2013–2025 | BSAI includes CDQ",
       x = "Year", y = "Catch (million metric tons)",
       caption = paste("Source: NOAA Alaska Region CAR110 annual reports, through 31 December each year.",
                       "Account coverage changes: squid through 2018; sculpins through 2020.",
                       "Includes reported fixed-gear and trawl sablefish accounts. Panels use separate scales.", sep = "\n")) +
  theme_few(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = 17),
        plot.subtitle = element_text(margin = margin(b = 12)),
        strip.text = element_text(face = "bold", size = 12),
        strip.background = element_rect(fill = "#EEF3F5", color = NA),
        panel.spacing = unit(1.1, "lines"),
        panel.grid.major.y = element_line(color = "#E7E7E7", linewidth = 0.3),
        plot.caption = element_text(hjust = 0, size = 9, color = "#3D4850", margin = margin(t = 12)),
        plot.margin = margin(15, 18, 15, 12))
figure_dir <- file.path(root, "doc", "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
for (extension in c("png", "svg")) {
  destination <- file.path(figure_dir, paste0("regional-total-catch-by-year.", extension))
  ggsave(destination, p, width = 10.5, height = 7.6, units = "in", dpi = 180, bg = "white")
  stopifnot(file.exists(destination), file.info(destination)$size > 1000)
  message(destination)
}

#!/usr/bin/env Rscript
# Reproduce the catch figure from the validated, source-qualified annual CSV.
# Requires only base R. Run from the ABC_TAC repository or pass its path.
args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[[1]] else "."
data <- read.csv(file.path(root, "data", "BSAI_total_catch_by_year.csv"))
stopifnot(identical(data$Year, 2013:2025), !anyNA(data$Catch_t),
          all(data$Catch_t > 0), all(as.logical(data$Includes_CDQ)),
          all(data$Through == paste0("31-Dec-", data$Year)))
out <- file.path(root, "doc", "figures")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
draw <- function() {
  par(mar = c(4, 4.5, 4.3, 1.5), mgp = c(2.6, 0.7, 0),
      las = 1, family = "sans", col.axis = "#334155", col.lab = "#334155")
  plot(data$Year, data$Catch_t / 1e6, type = "n", axes = FALSE,
       xlim = c(2012.7, 2026), ylim = c(0, 2.12), xaxs = "i", yaxs = "i",
       xlab = "Year", ylab = "Total catch (million metric tons)")
  abline(h = seq(0, 2, 0.5), col = "#E2E8F0", lwd = 1)
  axis(1, at = 2013:2025, cex.axis = 0.82, tck = -0.015, col = "#94A3B8")
  axis(2, at = seq(0, 2, 0.5), labels = sprintf("%.1f", seq(0, 2, 0.5)),
       tck = -0.015, col = "#94A3B8")
  lines(data$Year, data$Catch_t / 1e6, col = "#145A75", lwd = 2.7)
  points(data$Year, data$Catch_t / 1e6, pch = 21, col = "#145A75",
         bg = "white", lwd = 1.8, cex = 1.1)
  points(2025, tail(data$Catch_t, 1) / 1e6, pch = 19, col = "#145A75", cex = 1.25)
  text(2025, tail(data$Catch_t, 1) / 1e6 + 0.14,
       labels = "2025: 1.774 million t", adj = 1, cex = 0.95, col = "#0F3446")
  title("BSAI total groundfish catch, 2013-2025", adj = 0,
        line = 2.5, cex.main = 1.22, col.main = "#0F3446")
  mtext("Complete calendar years | NOAA annual catch reports, including CDQ",
        side = 3, line = 1, adj = 0, cex = 0.87, col = "#475569")
}
png(file.path(out, "bsai-total-catch-by-year.png"), width = 1600, height = 920,
    res = 180, type = "cairo", bg = "white")
draw()
dev.off()
svg(file.path(out, "bsai-total-catch-by-year.svg"), width = 9, height = 5.2,
    bg = "white")
draw()
dev.off()
message("Wrote PNG and SVG figures to ", normalizePath(out))

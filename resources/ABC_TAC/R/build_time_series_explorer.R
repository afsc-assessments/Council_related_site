#!/usr/bin/env Rscript
# Render a portable ggplotly explorer from the verified, normalized source data.
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(ggthemes)
  library(plotly)
  library(htmlwidgets)
  library(htmltools)
})
args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) {
  i <- match(name, args)
  if (is.na(i)) default else args[[i + 1L]]
}
input <- arg("--input", ".")
output <- arg("--output", file.path(input, "doc/time-series-explorer"))
assets <- arg("--assets", file.path(input, "interactive"))
data_file <- arg("--data", file.path(input, "data/time_series_explorer.csv"))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
rows <- read_csv(data_file, show_col_types = FALSE)
stopifnot(nrow(rows) > 0L, all(rows$Region %in% c("BSAI", "GOA")))
keys <- c("Dataset", "Region", "Species", "Measure")
series <- rows %>% distinct(across(all_of(keys))) %>% arrange(across(all_of(keys))) %>%
  mutate(TraceId = sprintf("series-%03d", row_number()))
# Insert explicit gaps so a line cannot join across a missing year or value.
plot_rows <- rows %>% left_join(series, by = keys) %>%
  group_by(across(all_of(c(keys, "TraceId")))) %>%
  complete(Year = seq.int(min(Year), max(Year))) %>% ungroup() %>%
  arrange(TraceId, Year) %>%
  mutate(Hover = paste0(Region, " · ", Species, "<br>", Measure, ": ",
                       if_else(is.na(Value_t), "Missing", format(Value_t, big.mark = ",", scientific = FALSE, trim = TRUE)),
                       " metric tons<br>Year: ", Year, "<br>", Dataset, "<br>",
                       coalesce(Coverage, "Year absent in source"),
                       if_else(coalesce(MissingRows, 0) > 0, paste0("<br>Missing source rows: ", MissingRows), ""),
                       if_else(coalesce(RepeatedLabels, 0) > 0, "<br>Repeated source labels retained", ""),
                       if_else(!is.na(Notes) & nzchar(coalesce(Notes, "")), paste0("<br>", vapply(coalesce(Notes, ""), function(note) paste(strwrap(note, width=75), collapse="<br>"), character(1))), "")))
graph <- ggplot(plot_rows, aes(Year, Value_t, color = TraceId, group = TraceId, text = Hover)) +
  geom_line(na.rm = TRUE, linewidth = 0.65) +
  scale_x_continuous(breaks = scales::breaks_pretty(8)) +
  scale_y_continuous(labels = scales::label_comma(), expand = expansion(mult = c(0, .06))) +
  labs(x = "Year", y = "Metric tons", color = NULL) +
  theme_few(base_size = 14) + theme(legend.position = "bottom")
widget <- ggplotly(graph, tooltip = "text", height = 500, width = NULL)
# Every trace is produced by ggplotly; browser controls subset these traces.
# Refill x/y/text with the completed records because ggplot removes leading NAs.
trace_index <- vector("list", length(widget$x$data))
colours <- c("#176b9a", "#a44d18", "#42783b", "#7655a3", "#a13d6f", "#376e6c", "#6b6140")
for (i in seq_along(widget$x$data)) {
  trace <- widget$x$data[[i]]
  meta <- series %>% filter(TraceId == trace$name)
  stopifnot(nrow(meta) == 1L)
  pts <- plot_rows %>% filter(TraceId == meta$TraceId)
  species_index <- match(meta$Species, sort(unique(rows$Species)))
  trace$x <- pts$Year
  trace$y <- pts$Value_t
  trace$text <- pts$Hover
  trace$visible <- meta$Dataset == "AKFIN catch" && meta$Region == "BSAI" && meta$Species == "All groundfish"
  trace$mode <- "lines+markers"
  trace$connectgaps <- FALSE
  trace$line$color <- colours[(species_index - 1L) %% length(colours) + 1L]
  trace$line$dash <- c(Catch="solid", ABC="solid", TAC="dash", OFL="dot")[[meta$Measure]]
  trace$marker <- list(size = 6, color = trace$line$color,
                       symbol = ifelse(pts$Coverage == "Complete", "circle", "circle-open"))
  trace$name <- paste(meta$Species, meta$Measure, sep = " — ")
  trace$legendgroup <- meta$TraceId
  widget$x$data[[i]] <- trace
  trace_index[[i]] <- meta %>% mutate(index = i - 1L) %>% select(-TraceId)
}
trace_index <- bind_rows(trace_index)
# Explicit complete and partial markers are set from the normalized missing count.
for (i in seq_along(widget$x$data)) {
  meta <- trace_index[i, ]
  pts <- plot_rows %>% semi_join(meta, by = keys)
  widget$x$data[[i]]$marker$symbol <- ifelse(coalesce(pts$MissingRows, 0) > 0, "circle-open", "circle")
}
widget$x$layout$margin <- list(l=72, r=25, b=95, t=20, pad=4)
widget$x$layout$legend <- list(orientation="h", x=0, y=-.2, title=list(text=""))
widget$x$layout$yaxis$rangemode <- "tozero"
widget$x$layout$yaxis$tickformat <- ",.0f"
widget$x$layout$xaxis$tickformat <- "d"
widget <- config(widget, displaylogo=FALSE, responsive=TRUE,
                 modeBarButtonsToRemove=c("select2d", "lasso2d"),
                 toImageButtonOptions=list(format="png", filename="council-time-series", width=1400, height=700))
widget <- onRender(widget, 'function(el,x,data) { window.CouncilExplorer.mount(el,data); }',
                   data=list(rows=lapply(seq_len(nrow(rows)), function(i) as.list(rows[i, ])),
                             traces=lapply(seq_len(nrow(trace_index)), function(i) as.list(trace_index[i, ]))))
widget$elementId <- "council-ggplotly"
widget <- prependContent(widget,
  tags$head(tags$meta(name="viewport", content="width=device-width, initial-scale=1"),
            tags$link(rel="stylesheet", href="explorer.css"),
            tags$script(src="explorer.js")),
  tags$noscript("Enable JavaScript to use the controls. The parent page provides figures and CSV downloads."))
saveWidget(widget, file=file.path(output, "index.html"), selfcontained=FALSE,
           libdir="lib", title="GOA and BSAI time-series explorer")
file.copy(file.path(assets, c("explorer.js", "explorer.css")), output, overwrite=TRUE) |> invisible()
html_path <- file.path(output, "index.html")
html <- readLines(html_path, warn=FALSE)
html <- sub("<html>", '<html lang="en">', html, fixed=TRUE)
writeLines(html, html_path)
stopifnot(all(file.exists(file.path(output, c("index.html", "explorer.js", "explorer.css")))))
jsonlite::write_json(list(rows=nrow(rows), series=nrow(series), ggplotly_traces=length(widget$x$data),
                         inserted_gap_rows=nrow(plot_rows)-nrow(rows), units="metric tons",
                         packages=sapply(c("plotly","ggplot2","htmlwidgets","ggthemes"), function(p) as.character(packageVersion(p)))),
                    file.path(output, "build.json"), pretty=TRUE, auto_unbox=TRUE)
cat(nrow(rows), "source records;", length(widget$x$data), "ggplotly traces; output:", output, "\n")

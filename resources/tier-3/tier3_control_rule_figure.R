library(ggplot2)

# Tier 3 control rule parameters. 
alpha <- 0.05
b35_over_b40 <- 35 / 40
b40_over_bmsy <- 1 / b35_over_b40
alpha_over_bmsy <- alpha / b35_over_b40
b_over_b35_critical <- 0.5
f40_over_fmsy <- 0.75

x_max <- 2.0
y_max <- 1.35

b_over_bmsy <- seq(0, x_max, length.out = 1000)
b_over_b40 <- b_over_bmsy * b35_over_b40
harvest_scaler <- pmax(0, pmin(1, (b_over_b40 - alpha) / (1 - alpha)))
ofl_label <- "OFL: FOFL / FMSY"
abc_label <- paste0("ABC: FABC / FMSY  (F40 / FMSY = ", f40_over_fmsy, ")")

rule_lines <- rbind(
  data.frame(
    b_over_bmsy = b_over_bmsy,
    f_over_fmsy = harvest_scaler,
    rule = ofl_label
  ),
  data.frame(
    b_over_bmsy = b_over_bmsy,
    f_over_fmsy = f40_over_fmsy * harvest_scaler,
    rule = abc_label
  )
)

status_regions <- data.frame(
  xmin = c(0, 0, b_over_b35_critical, 1),
  xmax = c(x_max, b_over_b35_critical, 1, x_max),
  ymin = c(1, 0, 0, 0),
  ymax = c(y_max, 1, 1, 1),
  status = c(
    "Above FMSY",
    "B/B35 < 0.5",
    "Below BMSY",
    "B > BMSY and F < FMSY"
  )
)

p <- ggplot() +
  geom_rect(
    data = status_regions,
    aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax, fill = status),
    alpha = 0.33,
    color = NA
  ) +
  geom_hline(yintercept = 1, linewidth = 0.55, color = "firebrick4") +
  geom_vline(xintercept = 1, linewidth = 0.55, color = "darkorange4") +
  geom_vline(xintercept = b_over_b35_critical, linewidth = 0.45, color = "firebrick4", linetype = "dotdash") +
  geom_vline(xintercept = b40_over_bmsy, linewidth = 0.45, color = "grey35", linetype = "dotted") +
  geom_vline(xintercept = alpha_over_bmsy, linewidth = 0.45, color = "grey35", linetype = "dashed") +
  geom_line(
    data = rule_lines,
    aes(x = b_over_bmsy, y = f_over_fmsy, color = rule, linetype = rule),
    linewidth = 1.2
  ) +
  annotate(
    "text",
    x = 0.98,
    y = 0.06,
    label = "BMSY = B35",
    hjust = 1,
    vjust = 0,
    size = 3.3,
    color = "darkorange4"
  ) +
  annotate(
    "text",
    x = b40_over_bmsy + 0.01,
    y = y_max - 0.06,
    label = "B40",
    hjust = 0,
    vjust = 1,
    size = 3.3,
    color = "grey25"
  ) +
  annotate(
    "text",
    x = 0.02,
    y = 1.02,
    label = "FMSY",
    hjust = 0,
    vjust = 0,
    size = 3.3,
    color = "firebrick4"
  ) +
  annotate(
    "text",
    x = x_max / 2,
    y = 1.16,
    label = "Overfishing",
    size = 5.2,
    fontface = "bold",
    color = "firebrick4"
  ) +
  annotate(
    "text",
    x = 0.25,
    y = 0.5,
    label = "Overfished",
    hjust = 0.5,
    size = 4.2,
    fontface = "bold",
    color = "firebrick4"
  ) +
  annotate(
    "text",
    x = 1.55,
    y = 1.04,
    label = "OFL",
    hjust = 0,
    vjust = 0,
    size = 4.1,
    fontface = "bold",
    color = "#1f1f1f"
  ) +
  annotate(
    "text",
    x = 1.55,
    y = f40_over_fmsy + 0.035,
    label = "ABC",
    hjust = 0,
    vjust = 0,
    size = 4.1,
    fontface = "bold",
    color = "#2166ac"
  ) +
  scale_fill_manual(
    values = c(
      "Above FMSY" = "#d73027",
      "B/B35 < 0.5" = "#d73027",
      "Below BMSY" = "#fdae61",
      "B > BMSY and F < FMSY" = "#1a9850"
    )
  ) +
  scale_color_manual(
    values = setNames(c("#1f1f1f", "#2166ac"), c(ofl_label, abc_label))
  ) +
  scale_linetype_manual(
    values = setNames(c("solid", "longdash"), c(ofl_label, abc_label))
  ) +
  coord_cartesian(xlim = c(0, x_max), ylim = c(0, y_max), expand = FALSE) +
  scale_x_continuous(
    breaks = c(0, alpha_over_bmsy, b_over_b35_critical, 1, 1.5, 2),
    labels = c("0", expression(alpha), "0.5", "1.0", "1.5", "2.0")
  ) +
  scale_y_continuous(
    breaks = seq(0, y_max, by = 0.25),
    labels = function(z) format(z, trim = TRUE, nsmall = 2)
  ) +
  labs(
    x = expression(B / B[MSY]),
    y = expression(F / F[MSY]),
    caption = "Note: FMSY is plotted in place of F35, and BMSY = B35. The low-biomass red region is B/B35 < 0.5.",
    color = NULL,
    linetype = NULL,
    fill = NULL
  ) +
  theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "grey88", linewidth = 0.35),
    axis.title = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0, color = "grey30", margin = margin(t = 8)),
    legend.position = "none",
    plot.margin = margin(12, 16, 10, 12)
  )

ggsave("tier3_control_rule.png", p, width = 8.5, height = 5.75, dpi = 320)
ggsave("tier3_control_rule.pdf", p, width = 8.5, height = 5.75, device = cairo_pdf)

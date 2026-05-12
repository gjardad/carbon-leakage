###############################################################################
# phase4_ppi_raw_evolution_plots.R
#
# PURPOSE:
#   Plot raw monthly PPI evolution at NACE 4-digit, 1981–2024, normalised so
#   each sector's 2005 annual average = 1. Four panels:
#     (A) treated vs non-treated (CdGM-broad NACE 2d set: 17, 19, 20, 23, 24, 25, 35)
#     (B) top sectors by 2005–2007 emissions/cost ratio (no EUA factor)
#     (C) top sectors by 2008–2012 emissions/cost ratio
#     (D) top sectors by 2008–2012 allowance-shortage/cost ratio
#
#   For (B–D), "emissions" means EUTL gross emissions, "shortage" means
#   max(0, emissions − free allowances). The denominator is total operating
#   cost from Annual Accounts. ω is contemporaneous (year-t numerator over
#   year-t denominator), averaged across the period.
#
# CAVEAT: pre-2010 PPI is NACE 2-digit values mapped to all 4-digit children
# within each 2-digit, so 4-digit lines coincide within a 2-digit before
# 2010. Real 4-digit cross-section starts 2010.
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData
#   ${OUT_DATA}/phase3_sector_exposure.RData
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase4_ppi_evolution_treated.{pdf,png}
#   ${OUTPUT_FIG}/phase4_ppi_evolution_omega_2005_07.{pdf,png}
#   ${OUTPUT_FIG}/phase4_ppi_evolution_omega_2008_12.{pdf,png}
#   ${OUTPUT_FIG}/phase4_ppi_evolution_shortage_2008_12.{pdf,png}
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(ggplot2); library(lubridate)
  library(stringr); library(scales)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# --- Load + normalise PPI ---
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

ppi <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0) %>%
  mutate(year = year(date), nace2d = str_pad(nace2d, 2, pad = "0"))

base_2005 <- ppi %>%
  filter(year == 2005) %>%
  group_by(nace4d) %>%
  summarise(ppi_2005 = mean(ppi, na.rm = TRUE), .groups = "drop")

ppi <- ppi %>%
  left_join(base_2005, by = "nace4d") %>%
  filter(!is.na(ppi_2005), ppi_2005 > 0) %>%
  mutate(idx = ppi / ppi_2005)

cat(sprintf("PPI panel: %d obs, %d sectors, %s to %s\n",
            nrow(ppi), n_distinct(ppi$nace4d),
            format(min(ppi$date)), format(max(ppi$date))))

# Restrict to manufacturing (10–33) + utilities (35) for cleaner plots
ppi <- ppi %>% filter(as.integer(nace2d) %in% c(10:33, 35))

# --- ω measures ---
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
exposure <- sector_exposure %>%
  select(nace4d, year, total_emissions, total_shortage, total_cost_denom) %>%
  filter(!is.na(total_cost_denom), total_cost_denom > 0)

omega_period <- function(df, yrs, num_col) {
  df %>% filter(year %in% yrs, !is.na(.data[[num_col]])) %>%
    group_by(nace4d) %>%
    summarise(num = sum(.data[[num_col]], na.rm = TRUE),
              den = sum(total_cost_denom, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(omega = num / den) %>%
    select(nace4d, omega)
}

# Restrict to NACE 2d ∈ {10..33, 35} (manufacturing + utilities) for the
# omega rankings, matching the PPI panel; otherwise services/wholesale
# sectors that happen to host an ETS installation (e.g., NACE 47, 71, 81)
# rank as "high omega" but have no PPI series to plot.
manuf_set <- c(sprintf("%02d", 10:33), "35")
exposure_m <- exposure %>%
  mutate(nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2)) %>%
  filter(nace2d %in% manuf_set)

omega_em_05_07  <- omega_period(exposure_m, 2005:2007, "total_emissions")
omega_em_08_12  <- omega_period(exposure_m, 2008:2012, "total_emissions")
omega_sh_08_12  <- omega_period(exposure_m, 2008:2012, "total_shortage")

# Restrict to NACE 4d sectors actually present in the PPI panel — otherwise
# top-N lines come up empty (e.g., NACE 2352 plaster, 2319 other glass have
# high omega but Statbel aggregates them into 2350, 2310, so no standalone
# PPI series exists).
ppi_4d_set <- unique(ppi$nace4d)
omega_em_05_07 <- omega_em_05_07 %>% filter(nace4d %in% ppi_4d_set)
omega_em_08_12 <- omega_em_08_12 %>% filter(nace4d %in% ppi_4d_set)
omega_sh_08_12 <- omega_sh_08_12 %>% filter(nace4d %in% ppi_4d_set)

# --- Treated set (CdGM broad: NACE 2d 17, 19, 20, 23, 24, 25, 35) ---
TREATED_2D <- c("17", "19", "20", "23", "24", "25", "35")

# --- Plot helper ---
phase_lines <- function(p) {
  p +
    geom_vline(xintercept = as.Date(c("2005-01-01", "2008-01-01",
                                       "2013-01-01", "2021-01-01")),
               colour = "grey70", linetype = "dotted", linewidth = 0.3) +
    geom_hline(yintercept = 1, colour = "grey70",
               linetype = "dotted", linewidth = 0.3) +
    scale_x_date(date_breaks = "5 years", date_labels = "%Y",
                 expand = c(0.01, 0.01)) +
    labs(x = NULL, y = "PPI (2005 = 1)") +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(),
          axis.line = element_line(colour = "black"),
          axis.ticks = element_line(colour = "black"),
          legend.position = "bottom")
}

save_plot <- function(p, basename) {
  ggsave(file.path(OUTPUT_FIG, paste0(basename, ".pdf")), p,
         width = 10, height = 5.5)
  ggsave(file.path(OUTPUT_FIG, paste0(basename, ".png")), p,
         width = 10, height = 5.5, dpi = 200)
}

# ============================================================================
# Plot A: treated (CdGM-broad) vs non-treated
# ============================================================================
ppi_A <- ppi %>%
  mutate(group = ifelse(nace2d %in% TREATED_2D, "Treated (CdGM)", "Untreated"))

pA <- ggplot(ppi_A, aes(x = date, y = idx, group = nace4d, colour = group)) +
  geom_line(linewidth = 0.25, alpha = 0.7) +
  scale_colour_manual(values = c("Treated (CdGM)" = "#cb181d",
                                  "Untreated" = "#2171b5"),
                      name = NULL) +
  scale_y_continuous(limits = c(0.4, 4.0), oob = scales::squish) +
  ggtitle("Belgian NACE 4-digit PPI evolution",
          subtitle = sprintf("Treated NACE 2d set: {%s}; n=%d sectors total",
                             paste(TREATED_2D, collapse = ", "),
                             n_distinct(ppi_A$nace4d)))
pA <- phase_lines(pA)
save_plot(pA, "phase4_ppi_evolution_treated")

# ============================================================================
# Helper for top-N highlighted plots
# ============================================================================
plot_topN <- function(omega_df, ppi, N, title, subtitle, basename) {
  topN <- omega_df %>% arrange(desc(omega)) %>% head(N) %>%
    mutate(label = sprintf("NACE %s (%.4f)", nace4d, omega),
           rank  = row_number())
  ppi_p <- ppi %>%
    left_join(topN %>% select(nace4d, label, rank), by = "nace4d") %>%
    mutate(highlight = !is.na(rank))
  bg <- ppi_p %>% filter(!highlight)
  fg <- ppi_p %>% filter(highlight) %>%
    mutate(label = factor(label, levels = topN$label[order(topN$rank)]))

  p <- ggplot() +
    geom_line(data = bg, aes(x = date, y = idx, group = nace4d),
              colour = "grey70", linewidth = 0.18, alpha = 0.4) +
    geom_line(data = fg, aes(x = date, y = idx, group = nace4d, colour = label),
              linewidth = 0.55) +
    scale_colour_brewer(palette = "Set1", name = NULL) +
    scale_y_continuous(limits = c(0.4, 4.0), oob = scales::squish) +
    ggtitle(title, subtitle = subtitle) +
    guides(colour = guide_legend(ncol = 2))
  p <- phase_lines(p)
  save_plot(p, basename)
  invisible(topN)
}

# ============================================================================
# Plot B: top by 2005–2007 emissions/cost (NO EUA)
# ============================================================================
top_B <- plot_topN(omega_em_05_07, ppi, N = 5,
  title    = "Belgian NACE 4-digit PPI evolution",
  subtitle = "Top 5 NACE 4d sectors by 2005-2007 emissions / total cost (manufacturing + utilities only)",
  basename = "phase4_ppi_evolution_omega_2005_07")
cat("\nTop 5 by 2005–2007 emissions/cost:\n"); print(top_B)

# ============================================================================
# Plot C: top by 2008–2012 emissions/cost
# ============================================================================
top_C <- plot_topN(omega_em_08_12, ppi, N = 5,
  title    = "Belgian NACE 4-digit PPI evolution",
  subtitle = "Top 5 NACE 4d sectors by 2008-2012 emissions / total cost (manufacturing + utilities only)",
  basename = "phase4_ppi_evolution_omega_2008_12")
cat("\nTop 5 by 2008–2012 emissions/cost:\n"); print(top_C)

# ============================================================================
# Plot D: top by 2008–2012 allowance shortage/cost
# ============================================================================
top_D <- plot_topN(omega_sh_08_12, ppi, N = 5,
  title    = "Belgian NACE 4-digit PPI evolution",
  subtitle = "Top 5 NACE 4d sectors by 2008-2012 allowance shortage / total cost (manufacturing + utilities only)",
  basename = "phase4_ppi_evolution_shortage_2008_12")
cat("\nTop 5 by 2008–2012 allowance shortage/cost:\n"); print(top_D)

cat("\nDone. Saved to:", OUTPUT_FIG, "\n")

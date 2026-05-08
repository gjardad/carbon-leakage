###############################################################################
# phase4_ppi_2017_treatment_plots.R
#
# PURPOSE:
#   PPI evolution plots treating 2017 as the cutoff (last year of low / pre-
#   MSR-effective EUA prices), restricted to:
#     - Sample: 2010m1 — 2022m12 (drops the 2-digit-mapped pre-2010 era and
#       the post-2022 energy-crisis tail)
#     - Source: pure NACE 4-digit Statbel PPI only (ppi_source ==
#       "statbel_4d_chained"), so no 2-digit values dressed up as 4-digit
#
#   Each sector's PPI normalised so its 2017 annual average = 1.
#
#   Three panels:
#     (A) treated vs untreated (CMdG-broad NACE 2d set; treated 2d codes
#         present in the pure 4-digit panel: 17, 20, 23, 24, 25)
#     (B) top NACE 4d sectors by 2013–2015 emissions/cost (no EUA factor)
#     (C) top NACE 4d sectors by 2013–2015 allowance shortage/cost
#
#   ω in (B) and (C) is built on 2013–2015 — the 3 years immediately
#   preceding the 2017 cutoff, so it's predetermined relative to treatment.
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData
#   ${OUT_DATA}/phase3_sector_exposure.RData
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase4_ppi_2017_treated.{pdf,png}
#   ${OUTPUT_FIG}/phase4_ppi_2017_omega_2013_15.{pdf,png}
#   ${OUTPUT_FIG}/phase4_ppi_2017_shortage_2013_15.{pdf,png}
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

SAMPLE_START <- as.Date("2010-01-01")
SAMPLE_END   <- as.Date("2022-12-01")
TREAT_YEAR   <- 2017

# --- Load + filter PPI ---
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

ppi <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0,
         ppi_source == "statbel_4d_chained",   # pure 4-digit only
         date >= SAMPLE_START, date <= SAMPLE_END) %>%
  mutate(year = year(date),
         nace2d = str_pad(nace2d, 2, pad = "0"))

# --- Append NACE 1920, 3510, 3520 from the older Statbel file ---
# These 4-digit codes are present in Statbel_TABEL_WEBSITE_AANGEVERS_2021_EN.xlsx
# (covers 2015–2026) but absent from the current TABEL_WEBSITE_AANGEVERS_EN.xlsx
# that drives our main panel. Normalisation to 2017 annual mean = 1 makes the
# absolute scale of the raw values irrelevant.
suppressPackageStartupMessages(library(readxl))
old_file <- file.path(RAW_DATA, "Statbel",
                      "Statbel_TABEL_WEBSITE_AANGEVERS_2021_EN.xlsx")
TARGET_4D <- c("1920", "3510", "3520")
d_old <- read_excel(old_file, sheet = "Domestic market", col_names = FALSE)
names(d_old) <- c("nace4d_raw", "label_or_year",
                  "Jan","Feb","Mar","Apr","May","Jun",
                  "Jul","Aug","Sep","Oct","Nov","Dec","Annual")
d_old <- d_old %>%
  mutate(nace4d = ifelse(!is.na(nace4d_raw),
                         as.character(nace4d_raw), NA_character_)) %>%
  tidyr::fill(nace4d, .direction = "down") %>%
  mutate(year = suppressWarnings(as.integer(label_or_year))) %>%
  filter(!is.na(year), nace4d %in% TARGET_4D) %>%
  mutate(across(c(Jan:Dec), as.numeric)) %>%
  select(nace4d, year, Jan:Dec) %>%
  pivot_longer(cols = Jan:Dec, names_to = "month_abbr", values_to = "ppi") %>%
  mutate(month = match(month_abbr, month.abb),
         date  = as.Date(sprintf("%d-%02d-01", year, month)),
         nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2),
         ppi_source = "statbel_4d_old_file") %>%
  filter(!is.na(ppi), ppi > 0,
         date >= SAMPLE_START, date <= SAMPLE_END) %>%
  select(nace4d, nace2d, date, year, month, ppi, ppi_source)

cat(sprintf("\nAppended from old Statbel: %d obs across %d sectors (%s)\n",
            nrow(d_old), n_distinct(d_old$nace4d),
            paste(sort(unique(d_old$nace4d)), collapse = ", ")))
cat(sprintf("Old-Statbel sector date ranges: %s to %s\n",
            format(min(d_old$date)), format(max(d_old$date))))

ppi <- bind_rows(ppi, d_old)

# Each sector normalised to its 2017 annual mean = 1
base_2017 <- ppi %>% filter(year == TREAT_YEAR) %>%
  group_by(nace4d) %>%
  summarise(ppi_2017 = mean(ppi, na.rm = TRUE), .groups = "drop")

ppi <- ppi %>%
  inner_join(base_2017, by = "nace4d") %>%
  filter(ppi_2017 > 0) %>%
  mutate(idx = ppi / ppi_2017)

# Restrict to manufacturing + utilities
ppi <- ppi %>% filter(as.integer(nace2d) %in% c(10:33, 35))

cat(sprintf("PPI panel (pure 4d, %s-%s): %d obs, %d sectors\n",
            format(SAMPLE_START, "%Ym%m"), format(SAMPLE_END, "%Ym%m"),
            nrow(ppi), n_distinct(ppi$nace4d)))

# --- ω measures on 2013-2015 ---
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
manuf_set <- c(sprintf("%02d", 10:33), "35")
exposure_m <- sector_exposure %>%
  mutate(nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2)) %>%
  filter(nace2d %in% manuf_set) %>%
  filter(!is.na(total_cost_denom), total_cost_denom > 0)

# Map NACE Rev 2 utility 4-digit codes (3511, 3512, 3513, 3514, 3521, 3522,
# 3523, 3530) onto the NACE-BEL Statbel 4-digit codes (3510, 3520, 3530)
# that publish PPI. Sector_exposure uses Rev 2 codes (3511 electricity-prod,
# 3522 gas-distribution); Statbel publishes 3510 (≈ all electricity) and
# 3520 (≈ all gas). Without this mapping the utility sectors don't match
# the omega rankings to the PPI panel.
exposure_m <- exposure_m %>%
  mutate(nace4d = case_when(
    str_detect(nace4d, "^351[1-4]$") ~ "3510",
    str_detect(nace4d, "^352[1-3]$") ~ "3520",
    TRUE                              ~ nace4d
  )) %>%
  group_by(nace4d, year, nace2d) %>%
  summarise(total_emissions  = sum(total_emissions,  na.rm = TRUE),
            total_shortage   = sum(total_shortage,   na.rm = TRUE),
            total_cost_denom = sum(total_cost_denom, na.rm = TRUE),
            .groups = "drop")

omega_period <- function(df, yrs, num_col) {
  df %>% filter(year %in% yrs, !is.na(.data[[num_col]])) %>%
    group_by(nace4d) %>%
    summarise(num = sum(.data[[num_col]], na.rm = TRUE),
              den = sum(total_cost_denom, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(omega = num / den) %>%
    select(nace4d, omega)
}

ppi_4d_set <- unique(ppi$nace4d)
omega_em_13_15 <- omega_period(exposure_m, 2013:2015, "total_emissions") %>%
  filter(nace4d %in% ppi_4d_set)
omega_sh_13_15 <- omega_period(exposure_m, 2013:2015, "total_shortage")  %>%
  filter(nace4d %in% ppi_4d_set)

# --- Treated set: CMdG-broad 2d codes that exist in pure-4d panel ---
TREATED_2D <- c("17", "19", "20", "23", "24", "25", "35")
present_treated <- intersect(TREATED_2D, unique(ppi$nace2d))
cat(sprintf("\nTreated NACE 2d codes present in pure-4d panel: %s\n",
            paste(present_treated, collapse = ", ")))

# --- Plot helpers ---
phase_lines <- function(p) {
  p +
    geom_vline(xintercept = as.Date(sprintf("%d-01-01", TREAT_YEAR)),
               colour = "firebrick", linewidth = 0.4) +
    geom_hline(yintercept = 1, colour = "grey70",
               linetype = "dotted", linewidth = 0.3) +
    scale_x_date(date_breaks = "2 years", date_labels = "%Y",
                 expand = c(0.01, 0.01)) +
    labs(x = NULL, y = sprintf("PPI (%d = 1)", TREAT_YEAR)) +
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
# Plot A: treated vs untreated
# ============================================================================
ppi_A <- ppi %>%
  mutate(group = ifelse(nace2d %in% present_treated, "Treated (CMdG)", "Untreated"))

pA <- ggplot(ppi_A, aes(x = date, y = idx, group = nace4d, colour = group)) +
  geom_line(linewidth = 0.3, alpha = 0.7) +
  scale_colour_manual(values = c("Treated (CMdG)" = "#cb181d",
                                  "Untreated" = "#2171b5"),
                      name = NULL) +
  scale_y_continuous(limits = c(0.5, 2.5), oob = scales::squish) +
  ggtitle("Belgian NACE 4-digit PPI evolution (pure 4-digit Statbel)",
          subtitle = sprintf("Sample %s-%s; 2017 cutoff (red); treated 2d set: {%s}; n=%d sectors",
                             format(SAMPLE_START, "%Ym%m"),
                             format(SAMPLE_END, "%Ym%m"),
                             paste(present_treated, collapse = ", "),
                             n_distinct(ppi_A$nace4d)))
pA <- phase_lines(pA)
save_plot(pA, "phase4_ppi_2017_treated")

# ============================================================================
# Top-N highlight helper
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
              colour = "grey70", linewidth = 0.2, alpha = 0.4) +
    geom_line(data = fg, aes(x = date, y = idx, group = nace4d, colour = label),
              linewidth = 0.6) +
    scale_colour_brewer(palette = "Set1", name = NULL) +
    scale_y_continuous(limits = c(0.5, 2.5), oob = scales::squish) +
    ggtitle(title, subtitle = subtitle) +
    guides(colour = guide_legend(ncol = 2))
  p <- phase_lines(p)
  save_plot(p, basename)
  invisible(topN)
}

# ============================================================================
# Plot B: top by 2013-2015 emissions/cost
# ============================================================================
top_B <- plot_topN(omega_em_13_15, ppi, N = 5,
  title    = "Belgian NACE 4-digit PPI evolution (pure 4-digit Statbel)",
  subtitle = sprintf("Sample %s-%s; top 5 NACE 4d by 2013-2015 emissions/cost; 2017 cutoff (red)",
                     format(SAMPLE_START, "%Ym%m"),
                     format(SAMPLE_END, "%Ym%m")),
  basename = "phase4_ppi_2017_omega_2013_15")
cat("\nTop 5 by 2013-2015 emissions/cost:\n"); print(top_B)

# ============================================================================
# Plot C: top by 2013-2015 allowance shortage/cost
# ============================================================================
top_C <- plot_topN(omega_sh_13_15, ppi, N = 5,
  title    = "Belgian NACE 4-digit PPI evolution (pure 4-digit Statbel)",
  subtitle = sprintf("Sample %s-%s; top 5 NACE 4d by 2013-2015 shortage/cost; 2017 cutoff (red)",
                     format(SAMPLE_START, "%Ym%m"),
                     format(SAMPLE_END, "%Ym%m")),
  basename = "phase4_ppi_2017_shortage_2013_15")
cat("\nTop 5 by 2013-2015 allowance shortage/cost:\n"); print(top_C)

cat("\nDone. Saved to:", OUTPUT_FIG, "\n")

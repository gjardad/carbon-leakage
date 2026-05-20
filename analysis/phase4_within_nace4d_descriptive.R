###############################################################################
# phase4_within_nace4d_descriptive.R
#
# PURPOSE
#   Descriptive statistics for the present-in-2010-14 sample used in the
#   within-NACE-4d intensive-margin analysis. Produces three artifacts:
#
#   (5.1) Overlaid kernel densities of omega by role (top vs bot).
#         Outputs: phase4_within_nace4d_descriptive_omega_density.{pdf,png}
#
#   (5.2) Kernel density of the within-cell exposure gap omega_top - omega_bot.
#         Outputs: phase4_within_nace4d_descriptive_exposure_gap_density.{pdf,png}
#
#   (5.3) Summary statistics table by role: revenue, wage bill, firm age proxy,
#         relationship age, annual emissions, emission intensity, omega.
#         Outputs: phase4_within_nace4d_descriptive_summary_table.tex
#
#   The sample construction mirrors phase4_within_intensive_pretrend_present_in_2010_14.R
#   for the tau = 2017 treatment (the headline event).
#
# DEPENDENCIES
#   - b2b_selected_sample.RData
#   - annual_accounts_selected_sample.RData
#   - annual_accounts_selected_sample_key_variables.RData
#   - phase3_firm_exposure.RData
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(xtable)
})

set.seed(20260520)

YEAR_LO    <- 2002L
YEAR_HI    <- 2022L
PRE_WINDOW <- 2010L:2014L       # cell-sample pre-window
OMEGA_WIN  <- c(2015L, 2016L)   # omega-measurement window
TREAT_YEAR <- 2017L

# ---------------------------------------------------------------------------
# Load data
# ---------------------------------------------------------------------------
cat("Loading data...\n")
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa_full <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4))]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa_full[!is.na(nace4d) & nace4d != ""])

# Firm-age proxy: first year in annual accounts (regardless of nace4d)
firm_first_year <- aa_full[, .(first_aa_year = min(year)), by = vat]

load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa_kv <- as.data.table(df_annual_accounts_selected_sample_key_variables)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  revenue, value_added, wage_bill
)]
rm(df_annual_accounts_selected_sample_key_variables)

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(
  vat = as.character(vat), year, shortage, emissions,
  total_cost, allocated_free
)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]

# Attach seller NACE4d to b2b (for cell construction)
b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]

# ---------------------------------------------------------------------------
# Build present-in-2010-14 sample with top + bot pool (tau = 2017)
# ---------------------------------------------------------------------------
cat("Building present-in-2010-14 sample + role assignment...\n")

pre_active <- b2b[year %in% PRE_WINDOW,
                  .(pre_sales = sum(sales)),
                  by = .(buyer, seller_nace4d, seller)]
omega_window_active <- b2b[year %in% OMEGA_WIN,
                            .(omega_win_sales = sum(sales)),
                            by = .(buyer, seller_nace4d, seller)]
pool_pairs <- merge(pre_active, omega_window_active,
                    by = c("buyer", "seller_nace4d", "seller"))

omega_byvat <- fe[year %in% OMEGA_WIN,
                  .(omega_anchor = mean(omega_sh, na.rm = TRUE)),
                  by = vat]
pool_pairs <- merge(pool_pairs, omega_byvat,
                    by.x = "seller", by.y = "vat", all.x = TRUE)
pool_pairs[is.na(omega_anchor), omega_anchor := 0]

cell_summary <- pool_pairs[, .(n = .N,
                               max_omega = max(omega_anchor),
                               min_omega = min(omega_anchor)),
                           by = .(buyer, seller_nace4d)]
cell_ok <- cell_summary[n >= 2L & max_omega > 0 & min_omega < max_omega]
pool <- merge(pool_pairs, cell_ok[, .(buyer, seller_nace4d)],
              by = c("buyer", "seller_nace4d"))

pool[, cell_min_omega := min(omega_anchor), by = .(buyer, seller_nace4d)]
pool[, cell_max_omega := max(omega_anchor), by = .(buyer, seller_nace4d)]
setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
pool[, role := fcase(
  rk == 1L,                       "top",
  omega_anchor == cell_min_omega, "bot",
  default = NA_character_
)]
sample_pairs <- pool[!is.na(role)]

# Pair-level pre-period first activity year (for relationship age)
t_start_dt <- b2b[year %in% PRE_WINDOW,
                   .(t_start = min(year)),
                   by = .(buyer, seller_nace4d, seller)]
sample_pairs <- merge(sample_pairs, t_start_dt,
                      by = c("buyer", "seller_nace4d", "seller"))

cat(sprintf("  Cells: %d.\n", nrow(cell_ok)))
cat(sprintf("  Sample pairs (cell-seller-role observations): %d.\n",
            nrow(sample_pairs)))
cat(sprintf("    of which top: %d, bot: %d.\n",
            nrow(sample_pairs[role == "top"]),
            nrow(sample_pairs[role == "bot"])))

# ---------------------------------------------------------------------------
# (5.1) Kernel density of omega by role
# ---------------------------------------------------------------------------
cat("\n(5.1) Building omega density figure...\n")

dens_dt <- sample_pairs[, .(omega = omega_anchor, role)]
dens_dt[, role_label := fcase(
  role == "top", "Most exposed supplier",
  role == "bot", "Least exposed supplier"
)]
dens_dt[, role_label := factor(role_label,
                               levels = c("Most exposed supplier",
                                          "Least exposed supplier"))]

# Floor at 1e-6 for log-x display (avoids log(0) issues for omega=0 mass)
OMEGA_FLOOR <- 1e-6
dens_dt[, omega_plot := pmax(omega, OMEGA_FLOOR)]

# Report the share at omega = 0
zero_share <- dens_dt[, .(pct_zero = 100 * mean(omega == 0)), by = role_label]
cat("  Share of pairs at omega = 0 by role:\n"); print(zero_share)

g_dens <- ggplot(dens_dt, aes(x = omega_plot, color = role_label,
                               fill = role_label)) +
  geom_density(alpha = 0.25, linewidth = 0.9) +
  scale_x_log10(breaks = c(1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1),
                labels = c("<0.0001%", "0.001%", "0.01%", "0.1%",
                           "1%", "10%", "100%")) +
  scale_color_manual(values = c("Most exposed supplier"  = "firebrick",
                                 "Least exposed supplier" = "navy"),
                     name = NULL) +
  scale_fill_manual(values = c("Most exposed supplier"  = "firebrick",
                                "Least exposed supplier" = "navy"),
                    name = NULL) +
  labs(x = expression("Carbon-cost exposure " * omega ~ "(2015-16, log scale)"),
       y = "Density") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 16),
        axis.title.x     = element_text(margin = margin(t = 12)),
        axis.title.y     = element_text(margin = margin(r = 12)),
        axis.text        = element_text(size = 13),
        legend.position  = "bottom",
        legend.text      = element_text(size = 14))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_omega_density.png"),
       g_dens, width = 8.5, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_omega_density.pdf"),
       g_dens, width = 8.5, height = 5.5)

# ---------------------------------------------------------------------------
# (5.2) Kernel density of the within-cell exposure gap omega_top - omega_bot
# ---------------------------------------------------------------------------
cat("\n(5.2) Building exposure-gap density figure...\n")

gap_dt <- cell_ok[, .(buyer, seller_nace4d,
                       exposure_gap = max_omega - min_omega)]
cat(sprintf("  Cells with nonzero gap: %d / %d\n",
            nrow(gap_dt[exposure_gap > 0]), nrow(gap_dt)))
cat("  Gap distribution:\n")
print(gap_dt[, .(min = min(exposure_gap), p10 = quantile(exposure_gap, 0.10),
                  p50 = median(exposure_gap), mean = mean(exposure_gap),
                  p90 = quantile(exposure_gap, 0.90),
                  max = max(exposure_gap))])

# Floor at 1e-6 for log-x display
GAP_FLOOR <- 1e-6
gap_dt[, gap_plot := pmax(exposure_gap, GAP_FLOOR)]

g_gap <- ggplot(gap_dt, aes(x = gap_plot)) +
  geom_density(fill = "steelblue", color = "steelblue4",
               alpha = 0.4, linewidth = 0.9) +
  geom_vline(aes(xintercept = median(exposure_gap)),
             linetype = "dashed", color = "firebrick") +
  scale_x_log10(breaks = c(1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1),
                labels = c("<0.0001%", "0.001%", "0.01%", "0.1%",
                           "1%", "10%", "100%")) +
  labs(x = expression("Within-cell exposure gap " * omega[top] - omega[bot] ~
                       "(2015-16, log scale)"),
       y = "Density",
       subtitle = "Dashed line: median across cells.") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 16),
        axis.title.x     = element_text(margin = margin(t = 12)),
        axis.title.y     = element_text(margin = margin(r = 12)),
        axis.text        = element_text(size = 13),
        plot.subtitle    = element_text(size = 11, face = "italic"))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_exposure_gap_density.png"),
       g_gap, width = 8.5, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_nace4d_descriptive_exposure_gap_density.pdf"),
       g_gap, width = 8.5, height = 5.5)

# ---------------------------------------------------------------------------
# (5.3) Summary statistics table by role
# ---------------------------------------------------------------------------
cat("\n(5.3) Building summary statistics table...\n")

# Pull pre-period firm-level characteristics for each seller in our sample
# Pre-period averages computed over 2010-14
sellers_in_sample <- unique(sample_pairs$seller)

# Revenue and wage bill (size proxies)
kv_pre <- aa_kv[year %in% PRE_WINDOW & vat %in% sellers_in_sample,
                .(mean_revenue   = mean(revenue,   na.rm = TRUE),
                  mean_value_added = mean(value_added, na.rm = TRUE),
                  mean_wage_bill = mean(wage_bill, na.rm = TRUE)),
                by = vat]
setnames(kv_pre, "vat", "seller")

# Firm-age proxy: 2016 minus first year of appearance in annual accounts
firm_age <- firm_first_year[vat %in% sellers_in_sample,
                             .(seller = vat,
                               firm_age_proxy = as.numeric(2016L - first_aa_year))]

# Emissions: from fe data (only ETS-registered firms appear here)
em_pre <- fe[year %in% PRE_WINDOW & vat %in% sellers_in_sample,
             .(mean_emissions   = mean(emissions, na.rm = TRUE),
               mean_total_cost  = mean(total_cost, na.rm = TRUE)),
             by = vat]
setnames(em_pre, "vat", "seller")

# Attach all characteristics to sample_pairs (one row per cell-seller-role)
chars <- sample_pairs[, .(buyer, seller_nace4d, seller, role,
                          t_start,
                          omega_2015_16 = omega_anchor)]
chars[, rel_age := as.numeric(2017L - t_start)]

chars <- merge(chars, kv_pre,    by = "seller", all.x = TRUE)
chars <- merge(chars, firm_age,  by = "seller", all.x = TRUE)
chars <- merge(chars, em_pre,    by = "seller", all.x = TRUE)

# Emission intensity = emissions / revenue (only defined when both observed)
chars[, emission_intensity := ifelse(!is.na(mean_emissions) &
                                       !is.na(mean_revenue) &
                                       mean_revenue > 0,
                                     mean_emissions / mean_revenue,
                                     NA_real_)]

# Indicator: is this seller in the EUTL registry (has any fe records in pre-window)?
chars[, in_eutl := !is.na(mean_emissions)]

# Compute summary statistics per role
summary_role <- chars[, .(
  n_obs              = .N,
  n_unique_sellers   = uniqueN(seller),
  rev_mean           = mean(mean_revenue,        na.rm = TRUE),
  rev_median         = median(mean_revenue,      na.rm = TRUE),
  wage_mean          = mean(mean_wage_bill,      na.rm = TRUE),
  wage_median        = median(mean_wage_bill,    na.rm = TRUE),
  firm_age_mean      = mean(firm_age_proxy,      na.rm = TRUE),
  firm_age_median    = median(firm_age_proxy,    na.rm = TRUE),
  rel_age_mean       = mean(rel_age,             na.rm = TRUE),
  rel_age_median     = median(rel_age,           na.rm = TRUE),
  pct_in_eutl        = 100 * mean(in_eutl),
  em_mean            = mean(mean_emissions,      na.rm = TRUE),
  em_median          = median(mean_emissions,    na.rm = TRUE),
  em_int_mean        = mean(emission_intensity,  na.rm = TRUE),
  em_int_median      = median(emission_intensity, na.rm = TRUE),
  omega_mean         = mean(omega_2015_16),
  omega_median       = median(omega_2015_16)
), by = role]

cat("Summary statistics:\n")
print(summary_role)
fwrite(summary_role, file.path(OUTPUT_TAB,
       "phase4_within_nace4d_descriptive_summary_table.csv"))

# Build a publication-ready tex table
fmt <- function(x, digits = 1, big.mark = ",") {
  if (is.na(x)) return("--")
  formatC(x, format = "f", digits = digits, big.mark = big.mark)
}

tex_rows <- data.table(
  Variable = c(
    "N (cell-seller-role obs)",
    "N unique sellers",
    "Revenue (EUR thousands), mean",
    "Revenue (EUR thousands), median",
    "Wage bill (EUR thousands), mean",
    "Wage bill (EUR thousands), median",
    "Firm age proxy (years since first AA), mean",
    "Firm age proxy, median",
    "Relationship age (years to 2017), mean",
    "Relationship age, median",
    "Pct in EUTL (any emissions in 2010-14)",
    "Annual emissions (tCO2e), mean (in EUTL only)",
    "Annual emissions, median (in EUTL only)",
    "Emission intensity (tCO2e / EUR thousand revenue), mean",
    "Emission intensity, median",
    "omega (2015-16), mean",
    "omega (2015-16), median"
  ),
  Top = c(
    fmt(summary_role[role == "top", n_obs], 0),
    fmt(summary_role[role == "top", n_unique_sellers], 0),
    fmt(summary_role[role == "top", rev_mean] / 1e3, 0),
    fmt(summary_role[role == "top", rev_median] / 1e3, 0),
    fmt(summary_role[role == "top", wage_mean] / 1e3, 0),
    fmt(summary_role[role == "top", wage_median] / 1e3, 0),
    fmt(summary_role[role == "top", firm_age_mean], 1),
    fmt(summary_role[role == "top", firm_age_median], 0),
    fmt(summary_role[role == "top", rel_age_mean], 1),
    fmt(summary_role[role == "top", rel_age_median], 0),
    fmt(summary_role[role == "top", pct_in_eutl], 1),
    fmt(summary_role[role == "top", em_mean], 0),
    fmt(summary_role[role == "top", em_median], 0),
    fmt(summary_role[role == "top", em_int_mean], 4),
    fmt(summary_role[role == "top", em_int_median], 4),
    fmt(summary_role[role == "top", omega_mean], 4),
    fmt(summary_role[role == "top", omega_median], 4)
  ),
  Bot = c(
    fmt(summary_role[role == "bot", n_obs], 0),
    fmt(summary_role[role == "bot", n_unique_sellers], 0),
    fmt(summary_role[role == "bot", rev_mean] / 1e3, 0),
    fmt(summary_role[role == "bot", rev_median] / 1e3, 0),
    fmt(summary_role[role == "bot", wage_mean] / 1e3, 0),
    fmt(summary_role[role == "bot", wage_median] / 1e3, 0),
    fmt(summary_role[role == "bot", firm_age_mean], 1),
    fmt(summary_role[role == "bot", firm_age_median], 0),
    fmt(summary_role[role == "bot", rel_age_mean], 1),
    fmt(summary_role[role == "bot", rel_age_median], 0),
    fmt(summary_role[role == "bot", pct_in_eutl], 1),
    fmt(summary_role[role == "bot", em_mean], 0),
    fmt(summary_role[role == "bot", em_median], 0),
    fmt(summary_role[role == "bot", em_int_mean], 4),
    fmt(summary_role[role == "bot", em_int_median], 4),
    fmt(summary_role[role == "bot", omega_mean], 4),
    fmt(summary_role[role == "bot", omega_median], 4)
  )
)
setnames(tex_rows, c("Variable", "Most exposed (top)", "Least exposed (bot)"))

xt <- xtable(tex_rows,
             caption = paste("Pre-period (2010-2014) summary statistics by",
                             "supplier role in the present-in-2010-14 sample.",
                             "One observation per (cell, seller, role) combination.",
                             "Firm-age proxy is years since the seller first appears",
                             "in Annual Accounts, capped at 2016. Relationship age",
                             "is years since the seller first sold to the buyer",
                             "in 2010-2014, measured at 2017. Emissions and",
                             "emission intensity are reported only for sellers",
                             "in the EUTL registry. omega is the seller's",
                             "shortage-based carbon-cost exposure measured in 2015-16."),
             label = "tab:phase4_within_nace4d_descriptive_summary_table",
             align = "lllr")
print(xt,
      file = file.path(OUTPUT_TAB,
                       "phase4_within_nace4d_descriptive_summary_table.tex"),
      include.rownames = FALSE, booktabs = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement = "top")

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

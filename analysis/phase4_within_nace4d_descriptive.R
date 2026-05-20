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

# Pair-level pre-period first activity year (anchors the present-in-2010-14 sample)
t_start_dt <- b2b[year %in% PRE_WINDOW,
                   .(t_start = min(year)),
                   by = .(buyer, seller_nace4d, seller)]
sample_pairs <- merge(sample_pairs, t_start_dt,
                      by = c("buyer", "seller_nace4d", "seller"))

# Pair-level UNCONSTRAINED first activity year across the full b2b history.
# Used for the descriptive "Relationship age" stat: the year the pair first
# appeared in the B2B panel (could be as early as 2002, the panel start).
rel_first_dt <- b2b[, .(rel_first_year = min(year)),
                    by = .(buyer, seller_nace4d, seller)]
sample_pairs <- merge(sample_pairs, rel_first_dt,
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
  labs(x = "Allowance shortage / input costs (log scale)",
       y = "Density") +
  theme_classic(base_size = 16) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 22),
        axis.title.x     = element_text(margin = margin(t = 16)),
        axis.title.y     = element_text(margin = margin(r = 16)),
        axis.text        = element_text(size = 18),
        legend.position  = "bottom",
        legend.text      = element_text(size = 17))

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
  labs(x = "Within-cell exposure gap (log scale)",
       y = "Density") +
  theme_classic(base_size = 16) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 22),
        axis.title.x     = element_text(margin = margin(t = 16)),
        axis.title.y     = element_text(margin = margin(r = 16)),
        axis.text        = element_text(size = 18))

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
                          rel_first_year,
                          omega_2015_16 = omega_anchor)]
chars[, rel_age := as.numeric(2017L - rel_first_year)]

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

# ---------------------------------------------------------------------------
# Build a publication-ready tex table with the following structure:
#
#                          | Most exposed     | Least exposed    |
#                          | Mean    | Median | Mean    | Median |
#   N of relationships     | <multicolumn{2}: count>| <mc>      |
#   N unique sellers       | <mc>             | <mc>             |
#   Revenue (...)          | x       | y      | x       | y      |
#   ...
#
# Count rows use \multicolumn{2}{c}{value} to span both Mean and Median.
# ---------------------------------------------------------------------------
fmt <- function(x, digits = 1, big.mark = ",") {
  if (is.na(x)) return("--")
  formatC(x, format = "f", digits = digits, big.mark = big.mark)
}

# Pull aggregates by role
gv <- function(role_v, col) summary_role[role == role_v][[col]]

# Helper to build a value row: "Variable & Top_Mean & Top_Median & Bot_Mean & Bot_Median \\"
val_row <- function(label, top_mean, top_med, bot_mean, bot_med) {
  sprintf("%s & %s & %s & %s & %s \\\\", label,
          top_mean, top_med, bot_mean, bot_med)
}
# Helper to build a count row: spans both Mean/Median per role
count_row <- function(label, top_v, bot_v) {
  sprintf("%s & \\multicolumn{2}{c}{%s} & \\multicolumn{2}{c}{%s} \\\\",
          label, top_v, bot_v)
}

rev_scale  <- 1e3   # display revenue / wage_bill in thousands of euros (divide by 1000)

body_rows <- c(
  count_row("N of relationships",
            fmt(gv("top", "n_obs"), 0),
            fmt(gv("bot", "n_obs"), 0)),
  count_row("N unique sellers",
            fmt(gv("top", "n_unique_sellers"), 0),
            fmt(gv("bot", "n_unique_sellers"), 0)),
  "\\midrule",
  val_row("Revenue (EUR thousands)",
          fmt(gv("top", "rev_mean")    / rev_scale, 0),
          fmt(gv("top", "rev_median")  / rev_scale, 0),
          fmt(gv("bot", "rev_mean")    / rev_scale, 0),
          fmt(gv("bot", "rev_median")  / rev_scale, 0)),
  val_row("Wage bill (EUR thousands)",
          fmt(gv("top", "wage_mean")   / rev_scale, 0),
          fmt(gv("top", "wage_median") / rev_scale, 0),
          fmt(gv("bot", "wage_mean")   / rev_scale, 0),
          fmt(gv("bot", "wage_median") / rev_scale, 0)),
  val_row("Firm age",
          fmt(gv("top", "firm_age_mean"),   1),
          fmt(gv("top", "firm_age_median"), 0),
          fmt(gv("bot", "firm_age_mean"),   1),
          fmt(gv("bot", "firm_age_median"), 0)),
  val_row("Relationship age (years to 2017)",
          fmt(gv("top", "rel_age_mean"),   1),
          fmt(gv("top", "rel_age_median"), 0),
          fmt(gv("bot", "rel_age_mean"),   1),
          fmt(gv("bot", "rel_age_median"), 0)),
  "\\midrule",
  count_row("Pct in EUTL",
            fmt(gv("top", "pct_in_eutl"), 1),
            fmt(gv("bot", "pct_in_eutl"), 1)),
  val_row("Annual emissions (tCO2e)",
          fmt(gv("top", "em_mean"),   0),
          fmt(gv("top", "em_median"), 0),
          fmt(gv("bot", "em_mean"),   0),
          fmt(gv("bot", "em_median"), 0)),
  val_row("Emission intensity (tCO2e / EUR thousand revenue)",
          fmt(gv("top", "em_int_mean")   * rev_scale, 2),
          fmt(gv("top", "em_int_median") * rev_scale, 2),
          fmt(gv("bot", "em_int_mean")   * rev_scale, 2),
          fmt(gv("bot", "em_int_median") * rev_scale, 2)),
  val_row("Carbon pricing exposure",
          fmt(gv("top", "omega_mean"),   4),
          fmt(gv("top", "omega_median"), 4),
          fmt(gv("bot", "omega_mean"),   4),
          fmt(gv("bot", "omega_median"), 4))
)

tex_lines <- c(
  "\\begin{table}[ht]",
  "\\centering",
  "\\caption{Summary statistics by supplier role}",
  "\\label{tab:phase4_within_nace4d_descriptive_summary_table}",
  "\\begin{tabular}{lcccc}",
  "\\toprule",
  " & \\multicolumn{2}{c}{Most exposed} & \\multicolumn{2}{c}{Least exposed} \\\\",
  "\\cmidrule(lr){2-3} \\cmidrule(lr){4-5}",
  " & Mean & Median & Mean & Median \\\\",
  "\\midrule",
  body_rows,
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}",
  "%",
  "% Row definitions:",
  "% - N of relationships: count of (cell, seller, role) observations in the present-in-2010-14 sample.",
  "% - N unique sellers: count of unique sellers in each role.",
  "% - Revenue (EUR thousands): pre-period (2010-2014) mean revenue from Annual Accounts, divided by 1000 for display.",
  "% - Wage bill (EUR thousands): pre-period mean wage bill from Annual Accounts, divided by 1000 for display.",
  "% - Firm age: years since the seller first appears in Annual Accounts, capped at 2016 (proxy for true firm age, which is not observed).",
  "% - Relationship age (years to 2017): years between the pair's first observed positive sales in the B2B panel (unrestricted; the panel starts in 2002) and the treatment year 2017. Capped from above at 15 (= 2017 - 2002).",
  "% - Pct in EUTL: share of sellers in the role with at least one positive emissions record in the EUTL registry over 2010-2014. Top suppliers are mechanically more likely to be in EUTL because omega > 0 requires an EUTL record.",
  "% - Annual emissions (tCO2e): pre-period mean emissions for sellers in the EUTL registry. Sellers not in EUTL are excluded from this calculation.",
  "% - Emission intensity: pre-period mean of (annual emissions in tCO2e) / (annual revenue in EUR thousand), for sellers in the EUTL registry.",
  "% - Carbon pricing exposure: omega, defined as max(emissions - free allocation, 0) * EUA price / total cost, averaged over the 2015-2016 omega-measurement window."
)

writeLines(tex_lines, con = file.path(OUTPUT_TAB,
       "phase4_within_nace4d_descriptive_summary_table.tex"))

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

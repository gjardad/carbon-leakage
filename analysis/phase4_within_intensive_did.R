###############################################################################
# phase4_within_intensive_did.R
#
# PURPOSE
#   Headline DiD on the within-NACE-4d intensive margin, present-in-2010-14
#   sample. Two specifications:
#
#   (1) Linear pre-trend (compact):
#       share_{c,r,t} = alpha_{c,r} + delta_t
#                     + phi  * (year - 2017) * 1[r = top]
#                     + gamma * 1[t >= 2017]  * 1[r = top] + eps
#
#       phi  absorbs the structural linear differential trend top vs bot.
#       gamma captures the discontinuous jump in the top-bot gap at 2017,
#             net of the structural linear pre-trend.
#
#   (2) Event study (flexible):
#       share_{c,r,t} = alpha_{c,r} + delta_t
#                     + sum_{k != -1} beta_k * 1[t = 2017+k] * 1[r = top] + eps
#
#       k indexes years relative to 2017: k = -7 (year 2010), ..., -1 (2016,
#       omitted reference), 0 (2017), ..., 5 (2022).
#       beta_k for k < -1 trace pre-trends; beta_k for k >= 0 trace post-treatment.
#
#   Sample: pairs active in some year of 2010-14 AND some year of 2015-16,
#           with cell qualification (>=2 suppliers, max omega > 0,
#           min omega < max omega). Panel restricted to 2010-2022.
#
#   Both specs are clustered on cell.
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(fixest)
  library(xtable)
})

set.seed(20260519)

YEAR_LO       <- 2010L    # panel start (drops 2002-09: pre-window for τ=2017)
YEAR_HI       <- 2022L
PRE_WINDOW    <- 2010L:2014L
OMEGA_WIN     <- c(2015L, 2016L)
TREAT_YEAR    <- 2017L

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
b2b <- b2b[year %between% c(2002L, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano), year = as.integer(year),
  nace4d = substr(nace5d, 1, 4))]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year, shortage, total_cost)]
rm(firm_exposure)
fe[, omega_sh := ifelse(!is.na(total_cost) & total_cost > 0,
                        pmax(shortage, 0) / total_cost, NA_real_)]

b2b <- merge(b2b, aa, by.x = c("seller", "year"), by.y = c("vat", "year"),
             all.x = TRUE)
setnames(b2b, "nace4d", "seller_nace4d")
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d != ""]
b2b[, total_buyer_nace4d_spend := sum(sales),
    by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# Build present-in-2010-14 sample with top + bot pool
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
setorder(pool, buyer, seller_nace4d, -omega_anchor, -pre_sales, seller)
pool[, rk := seq_len(.N), by = .(buyer, seller_nace4d)]
top_sup <- pool[rk == 1L,
                .(buyer, seller_nace4d,
                  top_supplier = seller,
                  omega_top    = omega_anchor)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller,
                   omega_bot = omega_anchor)]
cat(sprintf("  Cells: %d  |  Bot pool: %d (mean %.2f per cell)\n",
            nrow(cell_ok), nrow(bot_pool),
            nrow(bot_pool) / nrow(cell_ok)))

# ---------------------------------------------------------------------------
# Build the (cell, role, year) share panel, years 2010-2022
# ---------------------------------------------------------------------------
cat("Building (cell, role, year) share panel...\n")
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

# Top
top_panel <- top_sup[, .(year = YEAR_LO:YEAR_HI),
                     by = .(buyer, seller_nace4d, top_supplier)]
setnames(top_panel, "top_supplier", "seller")
top_panel <- merge(top_panel, yr_denom,
                   by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
top_panel <- merge(top_panel, yr_sales,
                   by = c("buyer", "seller_nace4d", "seller", "year"),
                   all.x = TRUE)
top_panel[is.na(sales), sales := 0]
top_panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                              total_buyer_nace4d_spend <= 0,
                            NA_real_, sales / total_buyer_nace4d_spend)]
top_panel[, role := "top"]
top_panel <- top_panel[, .(buyer, seller_nace4d, year, role, share)]

# Bot (portfolio mean across bot pool members)
bot_panel_long <- bot_pool[, .(year = YEAR_LO:YEAR_HI),
                            by = .(buyer, seller_nace4d, seller)]
bot_panel_long <- merge(bot_panel_long, yr_denom,
                        by = c("buyer", "seller_nace4d", "year"),
                        all.x = TRUE)
bot_panel_long <- merge(bot_panel_long, yr_sales,
                        by = c("buyer", "seller_nace4d", "seller", "year"),
                        all.x = TRUE)
bot_panel_long[is.na(sales), sales := 0]
bot_panel_long[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                                   total_buyer_nace4d_spend <= 0,
                                 NA_real_, sales / total_buyer_nace4d_spend)]
bot_panel <- bot_panel_long[!is.na(share),
                            .(share = mean(share)),
                            by = .(buyer, seller_nace4d, year)]
bot_panel[, role := "bot"]
bot_panel <- bot_panel[, .(buyer, seller_nace4d, year, role, share)]

panel <- rbind(top_panel, bot_panel)
panel <- panel[!is.na(share)]
panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
panel[, cell_role_id := paste(cell_id, role, sep = "::")]
panel[, group_top    := as.integer(role == "top")]
panel[, post         := as.integer(year >= TREAT_YEAR)]
panel[, year_centered := year - TREAT_YEAR]
panel[, year_centered_top := year_centered * group_top]
panel[, post_top     := post * group_top]
cat(sprintf("  Panel rows: %s (%d cells, %d cell-role units)\n",
            format(nrow(panel), big.mark = ","),
            uniqueN(panel$cell_id),
            uniqueN(panel$cell_role_id)))

# ---------------------------------------------------------------------------
# Spec 1: Linear pre-trend version
# ---------------------------------------------------------------------------
cat("\n=== Linear pre-trend DiD ===\n")
mod_lin <- feols(share ~ year_centered_top + post_top |
                          cell_role_id + year,
                 data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_lin))

coef_lin <- as.data.table(coeftable(mod_lin), keep.rownames = "term")
fwrite(coef_lin, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_linear_coef.csv"))

# Same regression WITHOUT the linear pre-trend term (for comparison)
cat("\n=== Same DiD WITHOUT linear pre-trend term (for comparison) ===\n")
mod_naive <- feols(share ~ post_top | cell_role_id + year,
                   data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_naive))
coef_naive <- as.data.table(coeftable(mod_naive), keep.rownames = "term")
fwrite(coef_naive, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_naive_coef.csv"))

# ---------------------------------------------------------------------------
# Spec 2: Event study (year-by-year leads/lags relative to 2016)
# ---------------------------------------------------------------------------
cat("\n=== Event study DiD ===\n")
mod_es <- feols(share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                         cell_role_id + year,
                data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_es))

# Build event-study coefficient table
es_coefs <- as.data.table(coeftable(mod_es), keep.rownames = "term")
# fixest names: "year::YYYY:group_top"
es_coefs[, year := as.integer(sub(".*year::(\\d+).*", "\\1", term))]
es_coefs[, k    := year - TREAT_YEAR]
setnames(es_coefs,
         old = c("Estimate", "Std. Error"),
         new = c("estimate", "std_error"))
es_coefs[, lo := estimate - 1.96 * std_error]
es_coefs[, hi := estimate + 1.96 * std_error]

# Add reference year (k = -1) at zero
ref_row <- data.table(term      = sprintf("year::%d:group_top", TREAT_YEAR - 1L),
                      estimate  = 0, std_error = 0,
                      `t value` = NA, `Pr(>|t|)` = NA,
                      year      = TREAT_YEAR - 1L,
                      k         = -1,
                      lo        = 0, hi = 0)
es_coefs <- rbind(es_coefs, ref_row, use.names = TRUE, fill = TRUE)
setorder(es_coefs, k)
fwrite(es_coefs, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_eventstudy_coef.csv"))

cat("\n--- Event-study coefficients (year-by-year top vs bot, ref = 2016) ---\n")
print(es_coefs[, .(year, k, estimate = round(estimate, 4),
                    se = round(std_error, 4),
                    lo = round(lo, 4), hi = round(hi, 4))])

# ---------------------------------------------------------------------------
# .tex tables (tracked by git; CSVs in OUTPUT_TAB are gitignored)
# ---------------------------------------------------------------------------
cat("\nWriting .tex tables...\n")

# Headline coefficients table (naive + linear pre-trend, side-by-side)
etable(list("Naive DiD"               = mod_naive,
            "Linear pre-trend DiD"    = mod_lin),
       tex          = TRUE,
       file         = file.path(OUTPUT_TAB,
                                "phase4_within_intensive_did_coefs.tex"),
       replace      = TRUE,
       title        = paste("Intensive margin DiD on the present-in-2010-14",
                            "sample. Column 1 is the naive 2x2 DiD;",
                            "column 2 adds a linear pre-trend interaction",
                            "(year - 2017) * top to absorb the structural",
                            "differential trend between top and bot."),
       label        = "tab:phase4_within_intensive_did_coefs",
       dict         = c(post_top           = "post $\\times$ top",
                        year_centered_top  = "(year - 2017) $\\times$ top",
                        share              = "Within-cell share",
                        cell_role_id       = "Cell $\\times$ role",
                        year               = "Year"),
       cluster      = ~cell_id,
       signif.code  = c("***" = 0.01, "**" = 0.05, "*" = 0.10),
       digits       = 4,
       digits.stats = 4)

# Event-study coefficients table
es_tex <- es_coefs[, .(Year        = year,
                       k,
                       Estimate    = sprintf("%.4f", estimate),
                       `Std. Err.` = sprintf("%.4f", std_error),
                       `95\\% CI`   = sprintf("[%.4f, %.4f]", lo, hi))]
# Mark the reference row visibly
es_tex[k == -1, `:=`(Estimate = "0 (ref)", `Std. Err.` = "--",
                     `95\\% CI` = "--")]

es_xtable <- xtable(es_tex,
                    caption = paste("Event-study coefficients on the",
                                    "intensive margin DiD. Year-by-year",
                                    "top vs bot differential, relative to",
                                    "2016 (omitted reference). Spec:",
                                    "share $\\sim$ i(year, top, ref=2016) |",
                                    "cell-role FE + year FE. Clustered",
                                    "on cell."),
                    label   = "tab:phase4_within_intensive_did_eventstudy",
                    align   = "lrrlll")
print(es_xtable,
      file               = file.path(OUTPUT_TAB,
                                     "phase4_within_intensive_did_eventstudy.tex"),
      include.rownames   = FALSE,
      booktabs           = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement  = "top")

# ---------------------------------------------------------------------------
# Event-study plot
# ---------------------------------------------------------------------------
cat("\nBuilding event-study plot...\n")
g_es <- ggplot(es_coefs, aes(x = year, y = estimate)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, color = "navy") +
  geom_point(size = 2.4, color = "navy") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 1)) +
  labs(x = NULL,
       y = "Year-by-year top vs bot differential (share units, ref = 2016)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 16, margin = margin(r = 14)),
        axis.text        = element_text(size = 14),
        axis.text.x      = element_text(angle = 45, hjust = 1))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_eventstudy.png"),
       g_es, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_eventstudy.pdf"),
       g_es, width = 9, height = 6)

# ---------------------------------------------------------------------------
# Post-hoc detrending of the raw event study (shows pre-period residuals)
# ---------------------------------------------------------------------------
# Fits a linear OLS trend through the pre-period raw event-study coefficients
# (k in {-7, ..., -1}; reference year k=-1 is at zero by construction) and
# computes residuals = raw - predicted for ALL years. Pre-period residuals
# tell us how well the linear assumption holds; post-period residuals are
# the policy estimate identified under that assumption.
cat("\n=== Post-hoc detrending of raw event study ===\n")
es_for_fit <- es_coefs[!is.na(estimate) & k <= -1]   # pre-period including ref
trend_lm <- lm(estimate ~ k, data = es_for_fit)
trend_intercept <- coef(trend_lm)[1]
trend_slope     <- coef(trend_lm)[2]
cat(sprintf("  Pre-period linear fit: intercept=%.4f, slope=%.4f per year\n",
            trend_intercept, trend_slope))

es_coefs[, predicted_trend := trend_intercept + trend_slope * k]
es_coefs[, posthoc_resid   := estimate - predicted_trend]
# Approximate SE on the residual: use raw SE (ignores covariance with trend fit)
es_coefs[, posthoc_resid_se := std_error]
es_coefs[, posthoc_lo := posthoc_resid - 1.96 * posthoc_resid_se]
es_coefs[, posthoc_hi := posthoc_resid + 1.96 * posthoc_resid_se]
fwrite(es_coefs[!is.na(estimate),
                 .(year, k, raw_estimate = estimate, raw_se = std_error,
                   predicted_trend, posthoc_resid, posthoc_resid_se,
                   posthoc_lo, posthoc_hi)],
       file.path(OUTPUT_TAB,
                 "phase4_within_intensive_did_eventstudy_posthoc_detrended.csv"))

cat("\n--- Post-hoc detrended event-study (pre-period residuals included) ---\n")
print(es_coefs[!is.na(estimate),
                .(year, k,
                  raw       = round(estimate, 4),
                  predicted = round(predicted_trend, 4),
                  resid     = round(posthoc_resid, 4),
                  resid_se  = round(posthoc_resid_se, 4))])

# Plot the post-hoc detrended ES showing pre-period residuals
es_for_plot <- es_coefs[!is.na(estimate)]
g_es_posthoc <- ggplot(es_for_plot, aes(x = year, y = posthoc_resid)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  geom_errorbar(aes(ymin = posthoc_lo, ymax = posthoc_hi),
                width = 0.2, color = "navy") +
  geom_point(size = 2.4, color = "navy") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 1)) +
  labs(x = NULL,
       y = "Residual from linear pre-trend (share units)",
       title = sprintf("Pre-period fit: slope = %.4f/year. Residuals show non-linearity.",
                       trend_slope)) +
  theme_classic(base_size = 14) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 14, margin = margin(r = 14)),
        axis.text        = element_text(size = 12),
        axis.text.x      = element_text(angle = 45, hjust = 1),
        plot.title       = element_text(size = 11, face = "italic"))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_eventstudy_posthoc_detrended.png"),
       g_es_posthoc, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_eventstudy_posthoc_detrended.pdf"),
       g_es_posthoc, width = 9, height = 6)

# ---------------------------------------------------------------------------
# De-trended event study: regression that absorbs a linear pre-trend AND
# estimates year-by-year deviations in the POST period only.
#
#   share = alpha_{cell,role} + delta_t
#         + phi * (year - 2017) * top
#         + sum_{k = 0..5} beta_k * 1[year = 2017+k] * top + eps
#
# Pre-period top observations are fit by the linear pre-trend (phi).
# Post-period top observations get an additional beta_k -- the deviation
# from the extrapolated pre-trend at that post-year. The pre-period
# coefficients are therefore zero by construction in this spec.
# ---------------------------------------------------------------------------
cat("\n=== De-trended event study (linear pre-trend + post-year dummies) ===\n")
mod_es_detr <- feols(share ~ year_centered_top +
                              i(year, group_top, keep = TREAT_YEAR:YEAR_HI) |
                              cell_role_id + year,
                     data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_es_detr))

es_detr_coefs <- as.data.table(coeftable(mod_es_detr), keep.rownames = "term")
# Extract year from terms like "year::2017:group_top"
es_detr_coefs[, is_year_top := grepl("^year::\\d+:group_top$", term)]
es_detr_yt <- es_detr_coefs[is_year_top == TRUE]
es_detr_yt[, year := as.integer(sub(".*year::(\\d+).*", "\\1", term))]
es_detr_yt[, k    := year - TREAT_YEAR]
setnames(es_detr_yt,
         old = c("Estimate", "Std. Error"),
         new = c("estimate", "std_error"))
es_detr_yt[, lo := estimate - 1.96 * std_error]
es_detr_yt[, hi := estimate + 1.96 * std_error]

# Pre-period is fit by linear trend -- by construction the de-trended
# coefficients are zero there. Add zero-rows for visualization.
pre_rows <- data.table(year = YEAR_LO:(TREAT_YEAR - 1L))
pre_rows[, k        := year - TREAT_YEAR]
pre_rows[, estimate := 0]
pre_rows[, std_error := 0]
pre_rows[, lo := 0]
pre_rows[, hi := 0]
pre_rows[, term := sprintf("year::%d:group_top (pre, fit by trend)", year)]

es_detr_full <- rbind(es_detr_yt, pre_rows, use.names = TRUE, fill = TRUE)
setorder(es_detr_full, k)
fwrite(es_detr_full, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_eventstudy_detrended_coef.csv"))

cat("\n--- De-trended event-study post-period coefficients ---\n")
print(es_detr_yt[, .(year, k, estimate = round(estimate, 4),
                     se = round(std_error, 4),
                     lo = round(lo, 4), hi = round(hi, 4))])

# Plot
g_es_detr <- ggplot(es_detr_full, aes(x = year, y = estimate)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, color = "navy") +
  geom_point(size = 2.4, color = "navy") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 1)) +
  labs(x = NULL,
       y = "Post-period deviation from extrapolated pre-trend (share units)") +
  theme_classic(base_size = 15) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 16, margin = margin(r = 14)),
        axis.text        = element_text(size = 14),
        axis.text.x      = element_text(angle = 45, hjust = 1))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_eventstudy_detrended.png"),
       g_es_detr, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_eventstudy_detrended.pdf"),
       g_es_detr, width = 9, height = 6)

# Tex table for the de-trended event study
es_detr_tex <- es_detr_yt[, .(Year        = year,
                               k,
                               Estimate    = sprintf("%.4f", estimate),
                               `Std. Err.` = sprintf("%.4f", std_error),
                               `95\\% CI`   = sprintf("[%.4f, %.4f]", lo, hi))]
es_detr_xtable <- xtable(es_detr_tex,
                         caption = paste("De-trended event-study coefficients.",
                                         "Linear pre-trend (year - 2017) x top",
                                         "is absorbed; year-by-year dummies",
                                         "are estimated only for the post period.",
                                         "Coefficients are deviations from the",
                                         "extrapolated pre-policy trend. Pre-period",
                                         "coefficients are zero by construction."),
                         label   = "tab:phase4_within_intensive_did_eventstudy_detrended",
                         align   = "lrrlll")
print(es_detr_xtable,
      file               = file.path(OUTPUT_TAB,
                                     "phase4_within_intensive_did_eventstudy_detrended.tex"),
      include.rownames   = FALSE,
      booktabs           = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement  = "top")

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

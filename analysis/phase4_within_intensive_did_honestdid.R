###############################################################################
# phase4_within_intensive_did_honestdid.R
#
# PURPOSE
#   Rambachan-Roth HonestDiD bounds on the within-NACE-4d intensive-margin
#   event study. Same sample and panel as phase4_within_intensive_did.R:
#   present-in-2010-14 cells, portfolio bot, panel 2012-2020.
#
#   The exercise: for each value of Mbar (the relative-magnitudes bound,
#   i.e. the maximum post-period parallel-trends violation is at most Mbar
#   times the maximum pre-period violation), report the 95% CI for the
#   average post-period treatment effect.
#
#   Mbar = 0 corresponds to the standard 95% CI assuming exact parallel
#   trends. Larger Mbar gives a wider CI that accommodates pre-trend
#   violations of varying magnitudes.
#
# OUTPUTS
#   - phase4_within_intensive_did_honestdid_bounds.{pdf,png}: plot of CI
#     for the average post-period treatment effect as a function of Mbar.
#   - phase4_within_intensive_did_honestdid_bounds.tex: CI table for the
#     full Mbar grid.
#
# REFERENCE
#   Rambachan, A. and Roth, J. (2023). "A More Credible Approach to Parallel
#   Trends." Review of Economic Studies, 90(5): 2555-2591.
###############################################################################

rm(list = ls())

# Install HonestDiD if needed
if (!requireNamespace("HonestDiD", quietly = TRUE)) {
  install.packages("HonestDiD",
                   repos = "https://cloud.r-project.org/")
}

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(fixest)
  library(HonestDiD)
  library(xtable)
})

set.seed(20260521)

YEAR_LO       <- 2012L
YEAR_HI       <- 2020L
PRE_WINDOW    <- 2010L:2014L
OMEGA_WIN     <- c(2015L, 2016L)
TREAT_YEAR    <- 2017L
M_BAR_VEC     <- c(0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2)

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
# Build present-in-2010-14 sample with portfolio bot
# (mirrors phase4_within_intensive_did.R)
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
                .(buyer, seller_nace4d, top_supplier = seller)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller)]
cat(sprintf("  Cells: %d  |  Bot pool: %d (mean %.2f per cell)\n",
            nrow(cell_ok), nrow(bot_pool),
            nrow(bot_pool) / nrow(cell_ok)))

# ---------------------------------------------------------------------------
# Build cell-role-year share panel
# ---------------------------------------------------------------------------
cat("Building cell-role-year panel...\n")
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

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
cat(sprintf("  Cell-role panel: %s rows (%d cells)\n",
            format(nrow(panel), big.mark = ","),
            uniqueN(panel$cell_id)))

# ---------------------------------------------------------------------------
# Run event study and extract betahat + sigma
# ---------------------------------------------------------------------------
cat("\nRunning event study...\n")
mod_es <- feols(share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                         cell_role_id + year,
                data    = panel,
                cluster = ~ cell_id,
                notes   = FALSE)

# Extract event-study coefficients in chronological order
ct <- coeftable(mod_es)
vc <- vcov(mod_es)
is_year_top <- grepl("^year::\\d+:group_top$", rownames(ct))
betahat <- ct[is_year_top, "Estimate"]
sigma   <- vc[is_year_top, is_year_top, drop = FALSE]
years_v <- as.integer(sub(".*year::(\\d+).*", "\\1", names(betahat)))
ord <- order(years_v)
betahat <- betahat[ord]
sigma   <- sigma[ord, ord, drop = FALSE]
years_v <- years_v[ord]

cat("\nEvent-study coefs (chronological, excludes ref = 2016):\n")
print(data.table(year = years_v, beta = round(betahat, 4),
                 se = round(sqrt(diag(sigma)), 4)))

N_PRE  <- sum(years_v < TREAT_YEAR)
N_POST <- sum(years_v >= TREAT_YEAR)
cat(sprintf("\nN pre-period coefs: %d. N post-period coefs: %d.\n",
            N_PRE, N_POST))

# ---------------------------------------------------------------------------
# Apply HonestDiD relative-magnitudes bounds
# Average post-period treatment effect via l_vec = rep(1/numPostPeriods).
# ---------------------------------------------------------------------------
l_vec_avg <- rep(1 / N_POST, N_POST)

beta_post  <- betahat[years_v >= TREAT_YEAR]
sigma_post <- sigma[years_v >= TREAT_YEAR,
                     years_v >= TREAT_YEAR, drop = FALSE]
avg_beta <- sum(l_vec_avg * beta_post)
avg_se   <- as.numeric(sqrt(t(l_vec_avg) %*% sigma_post %*% l_vec_avg))
cat(sprintf("\nAvg post-period treatment effect: %.4f (SE %.4f)\n",
            avg_beta, avg_se))

cat("\nApplying HonestDiD relative-magnitudes bounds...\n")
hdid <- createSensitivityResults_relativeMagnitudes(
  betahat        = betahat,
  sigma          = sigma,
  numPrePeriods  = N_PRE,
  numPostPeriods = N_POST,
  Mbarvec        = M_BAR_VEC,
  l_vec          = l_vec_avg,
  alpha          = 0.05
)
hdid <- as.data.table(hdid)

# Original (no-PT-slack) CI
orig <- data.table(method = "Original (no PT slack)",
                   Mbar   = 0,
                   lb     = avg_beta - 1.96 * avg_se,
                   ub     = avg_beta + 1.96 * avg_se)
hdid[, method := "HonestDiD (relative magnitudes)"]
hdid <- hdid[, .(method, Mbar, lb, ub)]
all_results <- rbind(orig, hdid)
print(all_results)

fwrite(all_results, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_honestdid_bounds.csv"))

# ---------------------------------------------------------------------------
# Tex bounds table
# ---------------------------------------------------------------------------
tex_dt <- copy(all_results)
tex_dt[, CI := sprintf("[%.4f, %.4f]", lb, ub)]
tex_clean <- tex_dt[, .(Mbar, method, CI)]
setnames(tex_clean, c("$\\bar{M}$", "Method", "95\\% CI"))
xt <- xtable(tex_clean,
             caption = paste("HonestDiD relative-magnitudes bounds on the",
                             "average post-period treatment effect",
                             "(within-NACE-4d intensive margin, panel 2012-2020).",
                             "$\\bar{M} = 0$ row is the standard 95\\% CI assuming",
                             "exact parallel trends. For $\\bar{M} > 0$, the",
                             "post-period parallel-trends violation is bounded",
                             "above by $\\bar{M}$ times the maximum pre-period",
                             "violation. The breakdown $\\bar{M}$ is the smallest",
                             "value for which the CI includes zero."),
             label   = "tab:phase4_within_intensive_did_honestdid_bounds",
             align   = "lllr")
print(xt,
      file = file.path(OUTPUT_TAB,
                       "phase4_within_intensive_did_honestdid_bounds.tex"),
      include.rownames = FALSE, booktabs = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement = "top")

# ---------------------------------------------------------------------------
# Plot CI as a function of Mbar
# ---------------------------------------------------------------------------
plot_dt <- all_results[method == "HonestDiD (relative magnitudes)"]

g <- ggplot(plot_dt, aes(x = Mbar)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_hline(yintercept = avg_beta, color = "navy",
             linetype = "dashed", linewidth = 0.5) +
  geom_ribbon(aes(ymin = lb, ymax = ub), alpha = 0.20, fill = "navy") +
  geom_line(aes(y = lb), color = "navy", linewidth = 0.7) +
  geom_line(aes(y = ub), color = "navy", linewidth = 0.7) +
  scale_x_continuous(breaks = M_BAR_VEC) +
  labs(x = expression(bar(M) ~ "(post-period violation ≤ " *
                       bar(M) ~ " × max pre-period violation)"),
       y = "95% CI for average post-period treatment effect (share units)",
       subtitle = sprintf(
         "Point estimate (dashed navy): %.4f. CI as a function of Mbar.",
         avg_beta)) +
  theme_classic(base_size = 14) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 14),
        axis.text        = element_text(size = 12),
        plot.subtitle    = element_text(size = 11, face = "italic"))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_honestdid_bounds.png"),
       g, width = 9, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_honestdid_bounds.pdf"),
       g, width = 9, height = 5.5)

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

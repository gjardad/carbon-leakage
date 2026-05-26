###############################################################################
# phase4_within_intensive_ces_elasticity.R
#
# PURPOSE
#   Structural CES estimate of the within-NACE-4d elasticity of substitution
#   across suppliers, using the MSR-induced EUA price rise as an exogenous
#   shifter of relative prices between most- and least-exposed suppliers.
#
# MODEL
#   CES within-cell demand for top vs bot supplier (taste shifters a):
#       ln(s_top / s_bot) = ln(a_top/a_bot) + (1 - sigma) * ln(p_top / p_bot)
#   First-differencing pre->post and assuming the relative taste shifter is
#   mean-zero across cells:
#       D ln(s_top/s_bot) = (1 - sigma) * D ln(p_top/p_bot) + eps
#
#   Price imputation (marginal-cost pricing, pass-through rho, constant
#   returns so D ln(mc_i) = carbon-cost-share change):
#       D ln(p_i)         = rho * omega_tilde_i * D_EUA      (omega_tilde = shortage/cost)
#       D ln(p_top/p_bot) = rho * (omega_tilde_top - omega_tilde_bot) * D_EUA
#                         = rho * K * (omega_top - omega_bot)
#   where omega_p is the stored 2015-16 carbon-cost share (= omega_tilde *
#   EUA_omega_win) and K = D_EUA / EUA_omega_win.
#
#   PPML reduced form (handles zero shares):
#       E[share_pt | X] = exp{ alpha_{cell,role} + delta_t + beta * (post_t * omega_p) }
#       beta = (1 - sigma) * rho * K     =>     sigma = 1 - beta / (rho * K)
#
# EUA PRICE WINDOW
#   Headline D_EUA is the end-2016 -> end-2018 move, deflated to 2016 EUR:
#   the MSR / Phase-4 repricing window (see section 2.1). One robustness
#   window extends the post date to end-2019.
#
#   NB: the deflated end-of-year EUA values below are pinned to the daily
#   ECX/ICE-Endex front-year series used in Figure 1. The end-2018 value
#   (23.70) is the one already used in Table 3. The end-2019 deflated value
#   is approximate (nominal end-of-year deflated by the Belgian aggregate
#   PPI); the co-author should confirm the exact deflated figure on RMD. It
#   affects only the robustness column, not the headline.
#
# OUTPUTS
#   - phase4_within_intensive_ces_elasticity_density.{pdf,png}
#   - phase4_within_intensive_ces_elasticity_sigma.tex      (headline, by rho)
#   - phase4_within_intensive_ces_elasticity_robustness.tex (rho x window)
#   - phase4_within_intensive_ces_elasticity_sigma.csv
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

set.seed(20260526)

YEAR_LO    <- 2010L
YEAR_HI    <- 2022L
PRE_WINDOW <- 2010L:2014L
OMEGA_WIN  <- c(2015L, 2016L)
TREAT_YEAR <- 2017L

RHO_GRID <- c(0.25, 0.50, 0.75, 1.00)

# ---- EUA prices (deflated to 2016 EUR), end-of-year, ECX/ICE front-year ----
EUA_OMEGA_WIN <- 6.54    # 2015-16 mean, the price at which omega is measured
EUA_2016_REAL <- 6.57    # end-2016 (deflation ~ 1 in base year)
EUA_2018_REAL <- 23.70   # end-2018, deflated (matches Table 3)
EUA_2019_REAL <- 23.20   # end-2019, approx deflated -- confirm on RMD

# Each window: D_EUA = EUA_post - EUA_2016; K = D_EUA / EUA_OMEGA_WIN.
# Column headers are the post-date (all windows start at end-2016).
WINDOWS <- data.table(
  window  = c("end-2018", "end-2019"),
  eua_post = c(EUA_2018_REAL, EUA_2019_REAL),
  headline = c(TRUE, FALSE)
)
WINDOWS[, d_eua := eua_post - EUA_2016_REAL]
WINDOWS[, K := d_eua / EUA_OMEGA_WIN]
cat("EUA windows:\n"); print(WINDOWS)
K_HEAD <- WINDOWS[headline == TRUE, K]

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
                .(buyer, seller_nace4d, seller, role = "top",
                  omega_p = omega_anchor)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller, role = "bot",
                   omega_p = omega_anchor)]
all_pairs <- rbind(top_sup, bot_pool)

# Cell-level exposure gap = omega_top - omega_bot (stored 2015-16 units)
cell_gap <- merge(
  top_sup[, .(buyer, seller_nace4d, omega_top = omega_p)],
  pool[, .(omega_bot = min(omega_anchor)), by = .(buyer, seller_nace4d)],
  by = c("buyer", "seller_nace4d"))
cell_gap[, gap := omega_top - omega_bot]
cat(sprintf("  Cells: %d. Exposure gap: mean %.5f, p50 %.5f, p90 %.5f, max %.5f\n",
            nrow(cell_gap), mean(cell_gap$gap), median(cell_gap$gap),
            quantile(cell_gap$gap, 0.9), max(cell_gap$gap)))

# ---------------------------------------------------------------------------
# Build pair-year share panel
# ---------------------------------------------------------------------------
cat("Building pair-year share panel...\n")
t_start_dt <- b2b[year %in% PRE_WINDOW,
                  .(t_start = min(year)),
                  by = .(buyer, seller_nace4d, seller)]
all_pairs <- merge(all_pairs, t_start_dt,
                   by = c("buyer", "seller_nace4d", "seller"))

yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year, total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

panel <- all_pairs[, .(year = YEAR_LO:YEAR_HI),
                   by = .(buyer, seller_nace4d, seller, role, t_start, omega_p)]
panel[, age := year - t_start]
panel <- panel[age >= 0L]
panel <- merge(panel, yr_denom,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel <- merge(panel, yr_sales,
               by = c("buyer", "seller_nace4d", "seller", "year"), all.x = TRUE)
panel[is.na(sales), sales := 0]
panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                          total_buyer_nace4d_spend <= 0,
                        NA_real_, sales / total_buyer_nace4d_spend)]
panel <- panel[!is.na(share)]
panel[, post := as.integer(year >= TREAT_YEAR)]
panel[, post_omega := post * omega_p]
panel[, cell_id := paste(buyer, seller_nace4d, sep = "::")]
panel[, cell_role_id := paste(cell_id, role, sep = "::")]
cat(sprintf("  Pair-year panel: %s rows (%d cells, %d pairs)\n",
            format(nrow(panel), big.mark = ","),
            uniqueN(panel$cell_id),
            uniqueN(panel[, .(buyer, seller_nace4d, seller)])))

# ---------------------------------------------------------------------------
# PPML: beta = (1 - sigma) * rho * K
# ---------------------------------------------------------------------------
cat("\n=== PPML structural CES estimation ===\n")
ppml_fit <- feglm(share ~ post_omega | cell_role_id + year,
                  data = panel, family = poisson, cluster = ~ cell_id)
print(summary(ppml_fit))

ct <- as.data.table(coeftable(ppml_fit), keep.rownames = "term")
beta_hat <- ct[term == "post_omega", Estimate]
beta_se  <- ct[term == "post_omega", `Std. Error`]
cat(sprintf("\n  beta_hat = %.4f (SE %.4f)\n", beta_hat, beta_se))

# ---------------------------------------------------------------------------
# sigma = 1 - beta / (rho * K), with CI from beta's SE (linear transform)
# ---------------------------------------------------------------------------
sigma_of <- function(rho, K) {
  data.table(
    rho = rho, K = K,
    sigma_hat = 1 - beta_hat / (rho * K),
    sigma_lo  = 1 - (beta_hat + 1.96 * beta_se) / (rho * K),
    sigma_hi  = 1 - (beta_hat - 1.96 * beta_se) / (rho * K))
}

# Headline (end-2016 -> end-2018)
headline <- rbindlist(lapply(RHO_GRID, sigma_of, K = K_HEAD))
cat("\n=== Headline sigma (end-2016 -> end-2018) by rho ===\n")
print(headline[, .(rho, sigma_hat = round(sigma_hat, 3),
                   CI = sprintf("[%.2f, %.2f]", sigma_lo, sigma_hi))])

# Robustness (rho x window)
robust <- rbindlist(lapply(seq_len(nrow(WINDOWS)), function(i) {
  out <- rbindlist(lapply(RHO_GRID, sigma_of, K = WINDOWS$K[i]))
  out[, window := WINDOWS$window[i]]
  out
}))
fwrite(robust, file.path(OUTPUT_TAB,
       "phase4_within_intensive_ces_elasticity_sigma.csv"))

# ---------------------------------------------------------------------------
# CDF of the imputed relative-price change, by rho (headline window)
#   D ln(p_top/p_bot)_c = rho * K_head * gap_c   (fraction; log-point change)
# Plotted as an ECDF on a log x-axis (percent labels), matching the
# counterfactual-savings CDF style in phase4_within_intensive_figures.R.
# ---------------------------------------------------------------------------
cat("\nBuilding relative-price-change CDF figure...\n")
dens <- rbindlist(lapply(RHO_GRID, function(r) {
  data.table(rho  = r,
             dlnp = r * K_HEAD * cell_gap$gap)   # fractional relative-price change
}))

x_breaks <- c(1e-6, 1e-4, 1e-2, 1)
x_labels <- c("0.0001%", "0.01%", "1%", "100%")

g_dens <- ggplot(dens[dlnp > 0], aes(x = dlnp, color = factor(rho))) +
  stat_ecdf(geom = "step", linewidth = 0.9, alpha = 0.9) +
  scale_x_log10(breaks = x_breaks, labels = x_labels) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_color_brewer(palette = "Set1",
                     name = expression("Pass-through " * rho)) +
  labs(x = "Change in relative price (top vs bot)",
       y = "Cumulative share of cells") +
  theme_classic(base_size = 15) +
  theme(panel.grid      = element_blank(),
        axis.title.x    = element_text(margin = margin(t = 12), size = 17),
        axis.title.y    = element_text(margin = margin(r = 12), size = 17),
        axis.text       = element_text(size = 14),
        legend.position = "bottom",
        legend.title    = element_text(size = 15),
        legend.text     = element_text(size = 14))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_ces_elasticity_cdf.png"),
       g_dens, width = 8, height = 5.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_ces_elasticity_cdf.pdf"),
       g_dens, width = 8, height = 5.5)

# ---------------------------------------------------------------------------
# LaTeX: headline sigma table (by rho)
# ---------------------------------------------------------------------------
head_tex <- headline[, .(
  `$\\rho$`     = sprintf("%.2f", rho),
  `$\\hat\\sigma$` = sprintf("%.2f", sigma_hat),
  `95\\% CI`    = sprintf("[%.2f, %.2f]", sigma_lo, sigma_hi))]
xt <- xtable(head_tex,
             caption = paste0("Implied within-NACE-4d elasticity of substitution ",
                              "$\\sigma$ by pass-through rate $\\rho$, using the ",
                              "end-2016 to end-2018 EUA price change ",
                              "($\\Delta\\text{EUA} = ", sprintf("%.1f", WINDOWS[headline==TRUE, d_eua]),
                              "$ EUR/tCO$_2$, $K = ", sprintf("%.2f", K_HEAD), "$). ",
                              "$\\sigma = 1 - \\hat\\beta/(\\rho K)$ with $\\hat\\beta$ ",
                              "from PPML on pair-year shares (cell-by-role and year ",
                              "fixed effects, clustered on cell). CIs from $\\hat\\beta$'s ",
                              "standard error."),
             label = "tab:phase4_within_intensive_ces_elasticity_sigma",
             align = "llcc")
print(xt, file = file.path(OUTPUT_TAB,
      "phase4_within_intensive_ces_elasticity_sigma.tex"),
      include.rownames = FALSE, booktabs = TRUE,
      sanitize.colnames.function = identity, sanitize.text.function = identity,
      caption.placement = "top")

# ---------------------------------------------------------------------------
# LaTeX: robustness table (rho rows, window columns) -- point estimates
# ---------------------------------------------------------------------------
robust[, sigma_str := sprintf("%.2f", sigma_hat)]
robust_wide <- dcast(robust, rho ~ window, value.var = "sigma_str")
setnames(robust_wide, "rho", "$\\rho$")
robust_wide[, `$\\rho$` := sprintf("%.2f", as.numeric(`$\\rho$`))]
xt2 <- xtable(robust_wide,
              caption = paste0("Implied $\\sigma$ across pass-through rates ",
                               "$\\rho$ (rows) and EUA price-change windows ",
                               "(columns). Point estimates only; see ",
                               "Table~\\ref{tab:phase4_within_intensive_ces_elasticity_sigma} ",
                               "for headline CIs. Same PPML $\\hat\\beta$ throughout; ",
                               "columns differ only in the EUA price change $K$."),
              label = "tab:phase4_within_intensive_ces_elasticity_robustness",
              align = paste0("l", paste0(rep("c", ncol(robust_wide)), collapse = "")))
print(xt2, file = file.path(OUTPUT_TAB,
      "phase4_within_intensive_ces_elasticity_robustness.tex"),
      include.rownames = FALSE, booktabs = TRUE,
      sanitize.colnames.function = identity, sanitize.text.function = identity,
      caption.placement = "top")

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

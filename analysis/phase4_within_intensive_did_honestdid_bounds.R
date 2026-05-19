###############################################################################
# phase4_within_intensive_did_honestdid_bounds.R
#
# PURPOSE
#   Apply the Rambachan-Roth honest DiD bounds (HonestDiD package) to the
#   within-NACE-4d intensive margin event studies built on the
#   present-in-2010-14 sample.
#
#   The exercise: for each value of Mbar (relative-magnitudes bound -- the
#   largest post-period parallel-trends violation is at most Mbar times the
#   largest pre-period violation), report the 95% CI for the average
#   post-period treatment effect.
#
#   Two event studies are bounded:
#     (a) Raw event study (no detrending). Pre-period |gamma| max is large,
#         so bounds will be wide at any Mbar > 0.
#     (b) Option 2B detrended event study (share - f_role(age), with
#         geometric extrapolation). Pre-period |gamma| is shrunk by the
#         age baseline, so bounds at the same Mbar are tighter.
#
#   Outputs:
#     - phase4_within_intensive_did_honestdid_bounds.{png,pdf}: 95% CI for
#       the average post-period treatment effect as a function of Mbar,
#       faceted by spec.
#     - phase4_within_intensive_did_honestdid_bounds.tex: side-by-side
#       table of CIs.
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

set.seed(20260519)

YEAR_LO       <- 2010L
YEAR_HI       <- 2022L
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
# Build present-in-2010-14 sample + pair-year panel
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
                .(buyer, seller_nace4d, seller = seller, role = "top")]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller, role = "bot")]
all_pairs <- rbind(top_sup, bot_pool)

t_start_dt <- b2b[year %in% PRE_WINDOW,
                   .(t_start = min(year)),
                   by = .(buyer, seller_nace4d, seller)]
all_pairs <- merge(all_pairs, t_start_dt,
                   by = c("buyer", "seller_nace4d", "seller"))

cat("Building pair-year share panel...\n")
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

panel <- all_pairs[, .(year = YEAR_LO:YEAR_HI),
                   by = .(buyer, seller_nace4d, seller, role, t_start)]
panel[, age := year - t_start]
panel <- panel[age >= 0L]

panel <- merge(panel, yr_denom,
               by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
panel <- merge(panel, yr_sales,
               by = c("buyer", "seller_nace4d", "seller", "year"),
               all.x = TRUE)
panel[is.na(sales), sales := 0]
panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                          total_buyer_nace4d_spend <= 0,
                        NA_real_, sales / total_buyer_nace4d_spend)]
panel <- panel[!is.na(share)]
panel[, group_top := as.integer(role == "top")]
panel[, cell_id := paste(buyer, seller_nace4d, sep = "::")]
panel[, cell_role_id := paste(cell_id, role, sep = "::")]
cat(sprintf("  Pair-year panel rows: %s\n",
            format(nrow(panel), big.mark = ",")))

# ---------------------------------------------------------------------------
# Compute Option 2B detrended share (geometric extrapolation)
# ---------------------------------------------------------------------------
cat("Building Option 2B detrended share...\n")
pre_panel <- panel[year < TREAT_YEAR]
f_raw <- pre_panel[, .(f_prepol = mean(share)), by = .(role, age)]
f_top_raw <- f_raw[role == "top" & f_prepol > 0]
f_bot_raw <- f_raw[role == "bot" & f_prepol > 0]
geo_top <- lm(log(f_prepol) ~ age, data = f_top_raw)
geo_bot <- lm(log(f_prepol) ~ age, data = f_bot_raw)
ages_grid <- 0:12
extrap <- rbind(
  data.table(role = "top", age = ages_grid,
             f_extrap = exp(predict(geo_top,
                                     newdata = data.table(age = ages_grid)))),
  data.table(role = "bot", age = ages_grid,
             f_extrap = exp(predict(geo_bot,
                                     newdata = data.table(age = ages_grid))))
)
f_baseline <- merge(f_raw, extrap, by = c("role", "age"), all = TRUE)
f_baseline[, f_2b := ifelse(is.na(f_prepol), f_extrap, f_prepol)]
panel <- merge(panel, f_baseline[, .(role, age, f_2b)],
               by = c("role", "age"))
panel[, detrended_share := share - f_2b]

# ---------------------------------------------------------------------------
# Run two event studies
# ---------------------------------------------------------------------------
cat("\nRunning event studies...\n")
mod_raw <- feols(share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                          cell_role_id + year,
                 data = panel, cluster = ~ cell_id, notes = FALSE)
mod_2b  <- feols(detrended_share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                                    cell_role_id + year,
                 data = panel, cluster = ~ cell_id, notes = FALSE)

# ---------------------------------------------------------------------------
# Extract betahat and sigma in chronological order
# ---------------------------------------------------------------------------
extract_es <- function(mod) {
  ct <- coeftable(mod)
  vc <- vcov(mod)
  is_year_top <- grepl("^year::\\d+:group_top$", rownames(ct))
  betahat <- ct[is_year_top, "Estimate"]
  sigma <- vc[is_year_top, is_year_top, drop = FALSE]
  years <- as.integer(sub(".*year::(\\d+).*", "\\1", names(betahat)))
  ord <- order(years)
  list(betahat = unname(betahat[ord]),
       sigma   = sigma[ord, ord, drop = FALSE],
       years   = years[ord])
}

es_raw <- extract_es(mod_raw)
es_2b  <- extract_es(mod_2b)

cat("Raw event-study coefs:\n")
print(data.table(year = es_raw$years, beta = round(es_raw$betahat, 4)))
cat("\nOption 2B event-study coefs:\n")
print(data.table(year = es_2b$years, beta = round(es_2b$betahat, 4)))

N_PRE  <- sum(es_raw$years < TREAT_YEAR)
N_POST <- sum(es_raw$years >= TREAT_YEAR)
cat(sprintf("\nN pre-period coefs: %d. N post-period coefs: %d.\n",
            N_PRE, N_POST))

l_vec_avg <- rep(1 / N_POST, N_POST)

# ---------------------------------------------------------------------------
# Apply HonestDiD relative-magnitudes bounds
# ---------------------------------------------------------------------------
run_hdid <- function(es, label) {
  cat(sprintf("\n=== HonestDiD bounds: %s ===\n", label))
  beta_post  <- es$betahat[es$years >= TREAT_YEAR]
  sigma_post <- es$sigma[es$years >= TREAT_YEAR,
                          es$years >= TREAT_YEAR, drop = FALSE]
  avg_beta <- sum(l_vec_avg * beta_post)
  avg_se   <- as.numeric(sqrt(t(l_vec_avg) %*% sigma_post %*% l_vec_avg))
  cat(sprintf("  Avg post-period beta = %.4f (SE %.4f).  Naive 95%% CI = [%.4f, %.4f].\n",
              avg_beta, avg_se,
              avg_beta - 1.96 * avg_se, avg_beta + 1.96 * avg_se))

  hdid <- createSensitivityResults_relativeMagnitudes(
    betahat        = es$betahat,
    sigma          = es$sigma,
    numPrePeriods  = N_PRE,
    numPostPeriods = N_POST,
    Mbarvec        = M_BAR_VEC,
    l_vec          = matrix(l_vec_avg, ncol = 1),
    alpha          = 0.05
  )
  print(hdid)

  orig <- data.table(method = "Original (M = 0)",
                     Mbar   = 0,
                     lb     = avg_beta - 1.96 * avg_se,
                     ub     = avg_beta + 1.96 * avg_se)
  res <- as.data.table(hdid)[, .(method = "HonestDiD",
                                  Mbar = Mbar, lb, ub)]
  list(orig = orig, sensitivity = res,
       avg_beta = avg_beta, avg_se = avg_se,
       hdid_object = hdid)
}

result_raw <- run_hdid(es_raw, "Raw event study")
result_2b  <- run_hdid(es_2b,  "Option 2B detrended event study")

combine_results <- function(r, label) {
  rbind(r$orig, r$sensitivity)[, spec := label][]
}
all_results <- rbind(
  combine_results(result_raw, "Raw event study"),
  combine_results(result_2b,  "Option 2B detrended")
)
fwrite(all_results, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_honestdid_bounds.csv"))

# ---------------------------------------------------------------------------
# Plot CI as a function of Mbar
# ---------------------------------------------------------------------------
plot_dt <- copy(all_results)
plot_dt[, spec := factor(spec,
                          levels = c("Raw event study",
                                     "Option 2B detrended"))]

avg_dt <- data.table(spec = c("Raw event study", "Option 2B detrended"),
                     avg_beta = c(result_raw$avg_beta, result_2b$avg_beta))
avg_dt[, spec := factor(spec,
                         levels = c("Raw event study",
                                    "Option 2B detrended"))]

g <- ggplot(plot_dt, aes(x = Mbar)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_ribbon(aes(ymin = lb, ymax = ub, fill = spec), alpha = 0.20) +
  geom_line(aes(y = lb, color = spec), linewidth = 0.7) +
  geom_line(aes(y = ub, color = spec), linewidth = 0.7) +
  geom_point(aes(y = lb, color = spec), size = 2) +
  geom_point(aes(y = ub, color = spec), size = 2) +
  geom_hline(data = avg_dt, aes(yintercept = avg_beta, color = spec),
             linetype = "dashed", linewidth = 0.6) +
  facet_wrap(~ spec, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = M_BAR_VEC) +
  scale_color_manual(values = c("Raw event study"     = "firebrick",
                                 "Option 2B detrended" = "navy")) +
  scale_fill_manual(values = c("Raw event study"     = "firebrick",
                                "Option 2B detrended" = "navy")) +
  labs(x = "M-bar (post-period violation ≤ M-bar × max pre-period violation)",
       y = "95% CI for average post-period treatment effect (share units)",
       title = "HonestDiD bounds: avg post-period treatment effect vs PT slack",
       subtitle = "Dashed line: point estimate (avg post-period beta).") +
  theme_classic(base_size = 14) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 14),
        axis.text        = element_text(size = 12),
        legend.position  = "none",
        strip.text       = element_text(face = "bold", size = 13),
        plot.title       = element_text(size = 13, face = "bold"),
        plot.subtitle    = element_text(size = 11, face = "italic"))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_honestdid_bounds.png"),
       g, width = 9, height = 9, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_honestdid_bounds.pdf"),
       g, width = 9, height = 9)

# ---------------------------------------------------------------------------
# Tex table of bounds (side-by-side by spec)
# ---------------------------------------------------------------------------
tex_dt <- copy(all_results)
tex_dt[, CI := sprintf("[%.4f, %.4f]", lb, ub)]
tex_wide <- dcast(tex_dt, Mbar + method ~ spec, value.var = "CI",
                  fun.aggregate = function(x) x[1])
setorder(tex_wide, Mbar, method)
print(tex_wide)
fwrite(tex_wide, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_honestdid_bounds_wide.csv"))

xt <- xtable(tex_wide,
             caption = paste("HonestDiD bounds on the average post-period",
                             "treatment effect (within-NACE-4d intensive margin),",
                             "as a function of $\\bar{M}$ (relative-magnitudes",
                             "bound: post-period parallel-trends violation is",
                             "at most $\\bar{M}$ times the largest pre-period",
                             "violation). Row at $\\bar{M} = 0$, method =",
                             "`Original' is the standard 95% CI assuming",
                             "exact parallel trends."),
             label   = "tab:phase4_within_intensive_did_honestdid_bounds",
             align   = "lllll")
print(xt,
      file               = file.path(OUTPUT_TAB,
                                     "phase4_within_intensive_did_honestdid_bounds.tex"),
      include.rownames   = FALSE,
      booktabs           = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement  = "top")

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

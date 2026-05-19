###############################################################################
# phase4_within_intensive_did_prepolicy_baseline.R
#
# PURPOSE
#   Option 2: subtract a pre-policy-estimated age trajectory from observed
#   share, then run the DiD on residuals. The age baseline is fit purely
#   on pre-policy data, so the post-policy effect cannot contaminate the
#   controls (unlike Option A's age x top FE).
#
#   Method:
#     1. Build pair-year panel (same as phase4_within_intensive_did_agecontrol.R).
#     2. From pre-policy years only (t < 2017), compute the mean share by
#        (role, age). Call this f_role(age) -- the pre-policy structural
#        share trajectory.
#     3. Build a detrended outcome:
#          detrended_share(p, t) = observed_share(p, t) - f_role(p)(age(p, t))
#     4. Run a DiD on detrended_share. gamma identifies the average post-2017
#        deviation from the pre-policy age trajectory, net of cell-role and
#        year FE.
#
#   Two sub-versions:
#     (2A) Restrict to ages 0-6 (the pre-policy overlap range). No
#          extrapolation. Safest -- counterfactual is empirically anchored.
#     (2B) Extrapolate the pre-policy trajectory to ages 7-12 using a
#          geometric decay fit (log f = a + b * age). Uses all post-policy
#          observations, but relies on the functional form being correct.
#
#   Outputs:
#     - tex table with 5 columns: Naive, Linear pre-trend, Age x top FE,
#       Option 2A, Option 2B. Lets the reader see gamma move across spec.
#     - Event-study figures + tex tables for Options 2A and 2B.
#     - Diagnostic figure: raw pre-policy f_role(age) vs geometric fit.
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

YEAR_LO       <- 2010L
YEAR_HI       <- 2022L
PRE_WINDOW    <- 2010L:2014L
OMEGA_WIN     <- c(2015L, 2016L)
TREAT_YEAR    <- 2017L
MAX_AGE_PRE   <- 6L   # latest age observable pre-policy (cohort 2010 in 2016)

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
                .(buyer, seller_nace4d, seller = seller, role = "top")]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller, role = "bot")]
all_pairs <- rbind(top_sup, bot_pool)

t_start_dt <- b2b[year %in% PRE_WINDOW,
                   .(t_start = min(year)),
                   by = .(buyer, seller_nace4d, seller)]
all_pairs <- merge(all_pairs, t_start_dt,
                   by = c("buyer", "seller_nace4d", "seller"))

# ---------------------------------------------------------------------------
# Build pair-year share panel
# ---------------------------------------------------------------------------
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
panel[, post := as.integer(year >= TREAT_YEAR)]
panel[, post_top := post * group_top]
panel[, year_centered_top := (year - TREAT_YEAR) * group_top]
panel[, cell_id := paste(buyer, seller_nace4d, sep = "::")]
panel[, cell_role_id := paste(cell_id, role, sep = "::")]
cat(sprintf("  Pair-year panel: %s rows\n",
            format(nrow(panel), big.mark = ",")))

# ---------------------------------------------------------------------------
# Step 1: Compute pre-policy mean share by (role, age)
# ---------------------------------------------------------------------------
cat("\nComputing pre-policy mean share by (role, age)...\n")
pre_panel <- panel[year < TREAT_YEAR]
f_raw <- pre_panel[, .(f_prepol = mean(share), n_obs = .N),
                    by = .(role, age)]
setorder(f_raw, role, age)
cat("  Pre-policy f_role(age) (raw means):\n")
print(f_raw)

# ---------------------------------------------------------------------------
# Step 2: Geometric extrapolation for ages 7-12 (Option 2B)
#   log(f_role(age)) ~ a_role + b_role * age, fit on ages 0-6
# ---------------------------------------------------------------------------
cat("\nFitting geometric decay for Option 2B extrapolation...\n")
f_top_raw <- f_raw[role == "top" & f_prepol > 0]
f_bot_raw <- f_raw[role == "bot" & f_prepol > 0]
geo_top <- lm(log(f_prepol) ~ age, data = f_top_raw)
geo_bot <- lm(log(f_prepol) ~ age, data = f_bot_raw)
cat(sprintf("  Top: log(f) = %.4f + %.4f * age  (R^2 = %.3f)\n",
            coef(geo_top)[1], coef(geo_top)[2], summary(geo_top)$r.squared))
cat(sprintf("  Bot: log(f) = %.4f + %.4f * age  (R^2 = %.3f)\n",
            coef(geo_bot)[1], coef(geo_bot)[2], summary(geo_bot)$r.squared))

ages_grid <- 0:12
extrap_top <- data.table(role = "top", age = ages_grid,
                          f_extrap = exp(predict(geo_top,
                                                  newdata = data.table(age = ages_grid))))
extrap_bot <- data.table(role = "bot", age = ages_grid,
                          f_extrap = exp(predict(geo_bot,
                                                  newdata = data.table(age = ages_grid))))
f_extrap <- rbind(extrap_top, extrap_bot)

# Baseline used by Option 2A: raw mean for ages 0-6 only (NA for 7-12)
# Baseline used by Option 2B: raw mean where available, extrapolated otherwise
f_baseline <- merge(f_raw, f_extrap, by = c("role", "age"), all = TRUE)
f_baseline[, f_2a := f_prepol]
f_baseline[, f_2b := ifelse(is.na(f_prepol), f_extrap, f_prepol)]
setorder(f_baseline, role, age)
cat("\n  Baseline by (role, age):\n")
print(f_baseline[, .(role, age, n_obs, f_2a = round(f_2a, 4),
                      f_extrap = round(f_extrap, 4),
                      f_2b = round(f_2b, 4))])
fwrite(f_baseline, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_prepolicy_baseline_table.csv"))

# Plot raw vs geometric extrapolation
plot_dt <- f_baseline[, .(role, age,
                          f_raw = f_prepol,
                          f_extrap_curve = f_extrap)]
plot_dt[, role_label := fcase(role == "top", "Most exposed supplier",
                              role == "bot", "Least exposed supplier")]

g_baseline <- ggplot(plot_dt, aes(x = age, color = role_label)) +
  geom_line(aes(y = f_extrap_curve), linetype = "dashed", linewidth = 0.8) +
  geom_point(aes(y = f_raw), size = 3) +
  geom_vline(xintercept = MAX_AGE_PRE + 0.5,
             linetype = "dotted", color = "firebrick") +
  scale_x_continuous(breaks = 0:12) +
  scale_color_manual(values = c("Most exposed supplier" = "firebrick",
                                 "Least exposed supplier" = "navy"),
                     name = NULL) +
  labs(x = "Age (years since first observed)",
       y = "Mean pair share (pre-policy)",
       title = "Pre-policy share trajectory by age and role",
       subtitle = paste("Dots: raw mean from pre-2017 data (ages 0-6).",
                        "Dashed line: geometric extrapolation.")) +
  theme_classic(base_size = 14) +
  theme(panel.grid       = element_blank(),
        axis.title       = element_text(size = 14),
        axis.text        = element_text(size = 12),
        legend.position  = "bottom",
        legend.text      = element_text(size = 12),
        plot.title       = element_text(size = 12, face = "bold"),
        plot.subtitle    = element_text(size = 11, face = "italic"))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_prepolicy_baseline.png"),
       g_baseline, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_prepolicy_baseline.pdf"),
       g_baseline, width = 9, height = 6)

# ---------------------------------------------------------------------------
# Step 3: Build detrended panels and run DiDs
# ---------------------------------------------------------------------------
# Option 2A: ages 0-6 only
cat("\n=== Option 2A: ages 0-6 only ===\n")
panel_2a <- panel[age <= MAX_AGE_PRE]
panel_2a <- merge(panel_2a, f_baseline[, .(role, age, f_2a)],
                  by = c("role", "age"))
panel_2a[, detrended_share := share - f_2a]
cat(sprintf("  Panel 2A rows: %s\n", format(nrow(panel_2a), big.mark = ",")))

mod_2a <- feols(detrended_share ~ post_top | cell_role_id + year,
                data = panel_2a, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_2a))

mod_2a_es <- feols(detrended_share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                                       cell_role_id + year,
                    data = panel_2a, cluster = ~ cell_id, notes = FALSE)

# Option 2B: ages 0-12 with geometric extrapolation
cat("\n=== Option 2B: ages 0-12 with geometric extrapolation ===\n")
panel_2b <- merge(panel, f_baseline[, .(role, age, f_2b)],
                  by = c("role", "age"))
panel_2b[, detrended_share := share - f_2b]
cat(sprintf("  Panel 2B rows: %s\n", format(nrow(panel_2b), big.mark = ",")))

mod_2b <- feols(detrended_share ~ post_top | cell_role_id + year,
                data = panel_2b, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_2b))

mod_2b_es <- feols(detrended_share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                                       cell_role_id + year,
                    data = panel_2b, cluster = ~ cell_id, notes = FALSE)

# ---------------------------------------------------------------------------
# Reference: re-run naive / linear pre-trend / Age × top at pair level for
# direct comparison (same panel as Option 2B)
# ---------------------------------------------------------------------------
cat("\n=== Reference specs (pair level, same panel as 2B) ===\n")
mod_naive <- feols(share ~ post_top | cell_role_id + year,
                   data = panel, cluster = ~ cell_id, notes = FALSE)
mod_linear <- feols(share ~ year_centered_top + post_top |
                            cell_role_id + year,
                    data = panel, cluster = ~ cell_id, notes = FALSE)
mod_agetop <- feols(share ~ post_top + i(age, group_top, ref = 0) |
                            cell_role_id + year + age,
                    data = panel, cluster = ~ cell_id, notes = FALSE)

# ---------------------------------------------------------------------------
# Side-by-side coefficient table
# ---------------------------------------------------------------------------
etable(list("Naive"             = mod_naive,
            "Linear pre-trend"  = mod_linear,
            "Age × top FE"      = mod_agetop,
            "Option 2A"         = mod_2a,
            "Option 2B"         = mod_2b),
       tex          = TRUE,
       file         = file.path(OUTPUT_TAB,
                                "phase4_within_intensive_did_prepolicy_baseline_coefs.tex"),
       replace      = TRUE,
       title        = paste("Within-NACE-4d intensive margin DiD,",
                            "comparison of structural-trend controls.",
                            "All specs at pair-year level, clustered on cell.",
                            "Naive / Linear pre-trend / Age x top FE use the",
                            "raw share. Option 2A and 2B use detrended_share =",
                            "share - f_role(age), where f_role(age) is the",
                            "pre-policy mean share by (role, age).",
                            "Option 2A restricts to ages 0-6 (pre-policy",
                            "overlap). Option 2B uses geometric extrapolation",
                            "to ages 7-12."),
       label        = "tab:phase4_within_intensive_did_prepolicy_baseline",
       dict         = c(post_top           = "post $\\times$ top",
                        year_centered_top  = "(year - 2017) $\\times$ top",
                        share              = "Pair share",
                        detrended_share    = "Pair share, detrended",
                        cell_role_id       = "Cell $\\times$ role",
                        year               = "Year",
                        age                = "Age"),
       drop         = "^age::",
       cluster      = ~cell_id,
       signif.code  = c("***" = 0.01, "**" = 0.05, "*" = 0.10),
       digits       = 4, digits.stats = 4)

# ---------------------------------------------------------------------------
# Event-study plots
# ---------------------------------------------------------------------------
build_es_dt <- function(mod, label) {
  ct <- as.data.table(coeftable(mod), keep.rownames = "term")
  ct <- ct[grepl("^year::\\d+:group_top$", term)]
  ct[, year := as.integer(sub(".*year::(\\d+).*", "\\1", term))]
  ct[, k    := year - TREAT_YEAR]
  setnames(ct,
           old = c("Estimate", "Std. Error"),
           new = c("estimate", "std_error"))
  ct[, lo := estimate - 1.96 * std_error]
  ct[, hi := estimate + 1.96 * std_error]
  ct[, version := label]
  # add ref row
  ref_row <- data.table(term = sprintf("year::%d:group_top", TREAT_YEAR - 1L),
                        estimate = 0, std_error = 0,
                        `t value` = NA, `Pr(>|t|)` = NA,
                        year = TREAT_YEAR - 1L, k = -1,
                        lo = 0, hi = 0, version = label)
  rbind(ct, ref_row, use.names = TRUE, fill = TRUE)[order(year)]
}

es_2a <- build_es_dt(mod_2a_es, "Option 2A (ages 0-6)")
es_2b <- build_es_dt(mod_2b_es, "Option 2B (ages 0-12, extrapolated)")
es_all <- rbind(es_2a, es_2b)
fwrite(es_all, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_prepolicy_baseline_eventstudy_coef.csv"))

g_es <- ggplot(es_all, aes(x = year, y = estimate)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, color = "navy") +
  geom_point(size = 2.2, color = "navy") +
  facet_wrap(~ version, ncol = 1, scales = "free_x") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 1)) +
  labs(x = NULL,
       y = "Year x top differential on detrended share (ref = 2016)") +
  theme_classic(base_size = 14) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 14, margin = margin(r = 14)),
        axis.text        = element_text(size = 12),
        axis.text.x      = element_text(angle = 45, hjust = 1),
        strip.text       = element_text(face = "bold", size = 12))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_prepolicy_baseline_eventstudy.png"),
       g_es, width = 9, height = 9, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_prepolicy_baseline_eventstudy.pdf"),
       g_es, width = 9, height = 9)

# Tex table for event studies
make_es_tex <- function(dt, file, caption, label) {
  es_tex <- dt[, .(Year        = year,
                   k,
                   Estimate    = sprintf("%.4f", estimate),
                   `Std. Err.` = sprintf("%.4f", std_error),
                   `95\\% CI`   = sprintf("[%.4f, %.4f]", lo, hi))]
  es_tex[k == -1, `:=`(Estimate = "0 (ref)", `Std. Err.` = "--",
                       `95\\% CI` = "--")]
  xt <- xtable(es_tex, caption = caption, label = label, align = "lrrlll")
  print(xt, file = file, include.rownames = FALSE, booktabs = TRUE,
        sanitize.colnames.function = identity,
        sanitize.text.function     = identity,
        caption.placement          = "top")
}
make_es_tex(es_2a,
            file.path(OUTPUT_TAB,
                      "phase4_within_intensive_did_prepolicy_baseline_eventstudy_2a.tex"),
            caption = paste("Event-study coefficients, Option 2A.",
                            "Outcome is detrended_share = share - f_role(age).",
                            "Restricted to ages 0-6 (pre-policy overlap)."),
            label   = "tab:phase4_within_intensive_did_prepolicy_baseline_eventstudy_2a")
make_es_tex(es_2b,
            file.path(OUTPUT_TAB,
                      "phase4_within_intensive_did_prepolicy_baseline_eventstudy_2b.tex"),
            caption = paste("Event-study coefficients, Option 2B.",
                            "Outcome is detrended_share = share - f_role(age),",
                            "where f_role is extrapolated geometrically to",
                            "ages 7-12. Full age range."),
            label   = "tab:phase4_within_intensive_did_prepolicy_baseline_eventstudy_2b")

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

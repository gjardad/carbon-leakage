###############################################################################
# phase4_within_intensive_did_agecontrol.R
#
# PURPOSE
#   Option A control: replace the ad-hoc linear pre-trend with age × top
#   interactions in the within-NACE-4d intensive margin DiD. The age × top
#   interaction directly conditions on the age-dependent differential between
#   top and bot, which is the channel through which differential attrition
#   produces a structural pre-trend.
#
#   Unit of analysis: PAIR-YEAR (one observation per pair per year), in
#   contrast to the headline DiD which aggregates bot to a portfolio mean
#   at the cell-role-year level. This switch lets age be well-defined for
#   every observation.
#
#   Four specs at the pair level, all clustered on cell:
#     (1) Naive (no time/age control):
#         share ~ post:top | cell_role + year
#     (2) Linear pre-trend × top:
#         share ~ year_centered:top + post:top | cell_role + year
#     (3) Age FE main effect:
#         share ~ post:top | cell_role + year + age
#     (4) Age × top FE (the headline Option A):
#         share ~ post:top + i(age, group_top, ref = 0) |
#                 cell_role + year + age
#
#   Specs (1)-(2) are the pair-level analogues of the headline regressions
#   in phase4_within_intensive_did.R; γ in those specs is comparable across
#   the panels (but not directly comparable to the cell-role γ because the
#   units of analysis differ).
#
#   A fifth spec runs an event study with age × top control:
#     (5) share ~ i(year, group_top, ref = 2016) + i(age, group_top, ref = 0) |
#                 cell_role + year + age
#
#   Outputs: tex coefficient table with all four DiD γ's; tex + figure for
#   the age-controlled event study.
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
cat(sprintf("  Total pairs: %d (%d top, %d bot)\n",
            nrow(all_pairs),
            all_pairs[role == "top", .N],
            all_pairs[role == "bot", .N]))

# ---------------------------------------------------------------------------
# Find t_start per pair (first year of positive sales in 2010-14)
# ---------------------------------------------------------------------------
t_start_dt <- b2b[year %in% PRE_WINDOW,
                   .(t_start = min(year)),
                   by = .(buyer, seller_nace4d, seller)]
all_pairs <- merge(all_pairs, t_start_dt,
                   by = c("buyer", "seller_nace4d", "seller"))
cat("  t_start distribution by role:\n")
print(all_pairs[, .N, by = .(role, t_start)][order(role, t_start)])

# ---------------------------------------------------------------------------
# Build pair-year share panel (one row per pair-year)
# Each pair contributes observations from year YEAR_LO (or t_start, if later)
# through YEAR_HI. Age = year - t_start.
# ---------------------------------------------------------------------------
cat("Building pair-year share panel...\n")
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

panel <- all_pairs[, .(year = YEAR_LO:YEAR_HI),
                   by = .(buyer, seller_nace4d, seller, role, t_start)]
panel[, age := year - t_start]
panel <- panel[age >= 0L]   # drop years before the pair's first observed year

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
cat(sprintf("  Pair-year panel rows: %s (%d cells, %d pairs)\n",
            format(nrow(panel), big.mark = ","),
            uniqueN(panel$cell_id),
            uniqueN(panel[, .(buyer, seller_nace4d, seller)])))

# ---------------------------------------------------------------------------
# Four DiD specs (pair-level)
# ---------------------------------------------------------------------------
cat("\n=== Spec 1: Naive (no time/age control) ===\n")
mod_naive <- feols(share ~ post_top | cell_role_id + year,
                   data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_naive))

cat("\n=== Spec 2: Linear pre-trend × top ===\n")
mod_linear <- feols(share ~ year_centered_top + post_top |
                            cell_role_id + year,
                    data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_linear))

cat("\n=== Spec 3: Age FE main effect ===\n")
mod_age <- feols(share ~ post_top | cell_role_id + year + age,
                 data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_age))

cat("\n=== Spec 4: Age × top FE (Option A) ===\n")
mod_agetop <- feols(share ~ post_top + i(age, group_top, ref = 0) |
                            cell_role_id + year + age,
                    data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_agetop))

# Headline coefficient table (4 specs side by side)
etable(list("Naive"                    = mod_naive,
            "Linear pre-trend"         = mod_linear,
            "Age FE"                   = mod_age,
            "Age × top FE (Option A)"  = mod_agetop),
       tex          = TRUE,
       file         = file.path(OUTPUT_TAB,
                                "phase4_within_intensive_did_agecontrol_coefs.tex"),
       replace      = TRUE,
       title        = paste("Within-NACE-4d intensive margin DiD, pair-level.",
                            "Column 1 has no time/age control.",
                            "Column 2 adds a linear pre-trend interaction.",
                            "Column 3 adds an age fixed effect (main effect only).",
                            "Column 4 adds the age x top interaction:",
                            "the headline Option A spec.",
                            "Clustered on cell."),
       label        = "tab:phase4_within_intensive_did_agecontrol",
       dict         = c(post_top           = "post $\\times$ top",
                        year_centered_top  = "(year - 2017) $\\times$ top",
                        share              = "Pair share",
                        cell_role_id       = "Cell $\\times$ role",
                        year               = "Year",
                        age                = "Age"),
       drop         = "^age::",   # hide age × top dummies (too many)
       cluster      = ~cell_id,
       signif.code  = c("***" = 0.01, "**" = 0.05, "*" = 0.10),
       digits       = 4, digits.stats = 4)

# ---------------------------------------------------------------------------
# Spec 5: Event study with age × top control
# ---------------------------------------------------------------------------
cat("\n=== Spec 5: Event study with age × top control ===\n")
mod_es_agetop <- feols(share ~ i(year, group_top, ref = TREAT_YEAR - 1L) +
                                i(age, group_top, ref = 0) |
                                cell_role_id + year + age,
                       data = panel, cluster = ~ cell_id, notes = FALSE)
print(summary(mod_es_agetop))

# Extract year × top coefficients
es_coefs <- as.data.table(coeftable(mod_es_agetop), keep.rownames = "term")
es_coefs[, is_year_top := grepl("^year::\\d+:group_top$", term)]
es_yt <- es_coefs[is_year_top == TRUE]
es_yt[, year := as.integer(sub(".*year::(\\d+).*", "\\1", term))]
es_yt[, k    := year - TREAT_YEAR]
setnames(es_yt,
         old = c("Estimate", "Std. Error"),
         new = c("estimate", "std_error"))
es_yt[, lo := estimate - 1.96 * std_error]
es_yt[, hi := estimate + 1.96 * std_error]

# Add reference year at zero
ref_row <- data.table(term      = sprintf("year::%d:group_top", TREAT_YEAR - 1L),
                      estimate  = 0, std_error = 0,
                      `t value` = NA, `Pr(>|t|)` = NA,
                      year      = TREAT_YEAR - 1L,
                      k         = -1, lo = 0, hi = 0,
                      is_year_top = TRUE)
es_yt_full <- rbind(es_yt, ref_row, use.names = TRUE, fill = TRUE)
setorder(es_yt_full, k)

fwrite(es_yt_full,
       file.path(OUTPUT_TAB,
                 "phase4_within_intensive_did_agecontrol_eventstudy_coef.csv"))

cat("\n--- Event-study coefficients (age x top control applied) ---\n")
print(es_yt_full[, .(year, k,
                     estimate = round(estimate, 4),
                     se       = round(std_error, 4),
                     lo       = round(lo, 4),
                     hi       = round(hi, 4))])

# Event study plot
g_es <- ggplot(es_yt_full, aes(x = year, y = estimate)) +
  geom_hline(yintercept = 0, color = "grey50", linewidth = 0.4) +
  geom_vline(xintercept = TREAT_YEAR - 0.5,
             linetype = "dashed", color = "firebrick") +
  geom_errorbar(aes(ymin = lo, ymax = hi),
                width = 0.2, color = "navy") +
  geom_point(size = 2.4, color = "navy") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 1)) +
  labs(x = NULL,
       y = "Year × top differential, age-controlled (share units, ref = 2016)") +
  theme_classic(base_size = 14) +
  theme(panel.grid       = element_blank(),
        axis.title.y     = element_text(size = 14, margin = margin(r = 14)),
        axis.text        = element_text(size = 12),
        axis.text.x      = element_text(angle = 45, hjust = 1))

ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_agecontrol_eventstudy.png"),
       g_es, width = 9, height = 6, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
       "phase4_within_intensive_did_agecontrol_eventstudy.pdf"),
       g_es, width = 9, height = 6)

# Tex table for the age-controlled event study
es_yt_tex <- es_yt_full[, .(Year        = year,
                            k,
                            Estimate    = sprintf("%.4f", estimate),
                            `Std. Err.` = sprintf("%.4f", std_error),
                            `95\\% CI`   = sprintf("[%.4f, %.4f]", lo, hi))]
es_yt_tex[k == -1, `:=`(Estimate = "0 (ref)", `Std. Err.` = "--",
                        `95\\% CI` = "--")]
es_xt <- xtable(es_yt_tex,
                caption = paste("Event-study coefficients with age x top",
                                "control. Year-by-year top vs bot differential",
                                "relative to 2016 (omitted reference),",
                                "net of the age x top interaction.",
                                "Spec: share $\\sim$ i(year, top, ref=2016) +",
                                "i(age, top, ref=0) | cell-role + year + age.",
                                "Clustered on cell."),
                label   = "tab:phase4_within_intensive_did_agecontrol_eventstudy",
                align   = "lrrlll")
print(es_xt,
      file               = file.path(OUTPUT_TAB,
                                     "phase4_within_intensive_did_agecontrol_eventstudy.tex"),
      include.rownames   = FALSE,
      booktabs           = TRUE,
      sanitize.colnames.function = identity,
      sanitize.text.function     = identity,
      caption.placement  = "top")

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

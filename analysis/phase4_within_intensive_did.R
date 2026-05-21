###############################################################################
# phase4_within_intensive_did.R
#
# PURPOSE
#   Headline DiD on the within-NACE-4d intensive margin, present-in-2010-14
#   sample, panel window 2012-2020.
#
#   Two specifications:
#
#   (1) Naive 2x2 DiD on the cell-role panel (top vs portfolio-bot, one
#       row per (cell, role, year)):
#
#         share_{c,r,t}  =  alpha_{c,r}  +  delta_t
#                        +  gamma * (post * top)_{r,t}  +  eps
#
#   (2) Pair-level DiD with age x top fixed effects to absorb the
#       differential attrition between top and bot (one row per
#       (pair, year); top contributes 1 pair per cell, bot pool members
#       contribute 1 pair each):
#
#         share_{p,t}  =  alpha_{cell, role}  +  delta_t  +  delta_age
#                       +  sum_{a >= 1} kappa_a * 1[age=a] * top
#                       +  gamma * (post * top)_{p,t}  +  eps
#
#       The age x top dummies absorb the structural age-dependent
#       differential between top and bot (e.g., heterogeneous attrition
#       rates by group); gamma is the post-2017 break in the top-bot
#       gap on top of that age-driven differential.
#
#   Also: an event-study version of (1) -- year-by-year coefficients on
#   top vs bot, relative to 2016. Visual companion for the parallel-
#   trends diagnostic and for the HonestDiD bounds in Script 3.
#
#   Sample: pairs active in some year of 2010-14 AND some year of 2015-16,
#           cell qualification (>=2 suppliers, max omega > 0,
#           min omega < max omega). Panel restricted to 2012-2020.
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

set.seed(20260521)

YEAR_LO       <- 2012L    # panel start: clean pre-trends from 2012 onward
YEAR_HI       <- 2020L    # panel end: avoid COVID + 2021-22 energy crisis
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
                  .(pre_sales = sum(sales),
                    t_start   = min(year)),
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
                .(buyer, seller_nace4d, seller, t_start,
                  role = "top", omega_anchor)]
bot_pool <- pool[omega_anchor == cell_min_omega,
                 .(buyer, seller_nace4d, seller, t_start,
                   role = "bot", omega_anchor)]
all_pairs <- rbind(top_sup, bot_pool)
cat(sprintf("  Cells: %d  |  Top: %d  |  Bot pool: %d (mean %.2f per cell)\n",
            nrow(cell_ok),
            nrow(top_sup), nrow(bot_pool),
            nrow(bot_pool) / nrow(cell_ok)))

# ---------------------------------------------------------------------------
# Build pair-year share panel (years YEAR_LO:YEAR_HI)
# ---------------------------------------------------------------------------
cat("Building pair-year panel...\n")
yr_denom <- unique(b2b[, .(buyer, seller_nace4d, year,
                           total_buyer_nace4d_spend)])
yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

pair_panel <- all_pairs[, .(year = YEAR_LO:YEAR_HI),
                        by = .(buyer, seller_nace4d, seller, t_start, role,
                               omega_anchor)]
pair_panel[, age := year - t_start]
pair_panel <- pair_panel[age >= 0L]

pair_panel <- merge(pair_panel, yr_denom,
                    by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
pair_panel <- merge(pair_panel, yr_sales,
                    by = c("buyer", "seller_nace4d", "seller", "year"),
                    all.x = TRUE)
pair_panel[is.na(sales), sales := 0]
pair_panel[, share := ifelse(is.na(total_buyer_nace4d_spend) |
                               total_buyer_nace4d_spend <= 0,
                             NA_real_, sales / total_buyer_nace4d_spend)]
pair_panel <- pair_panel[!is.na(share)]
pair_panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
pair_panel[, cell_role_id := paste(cell_id, role, sep = "::")]
pair_panel[, group_top    := as.integer(role == "top")]
pair_panel[, post         := as.integer(year >= TREAT_YEAR)]
pair_panel[, post_top     := post * group_top]
cat(sprintf("  Pair-year panel: %s rows (%d cells, %d pairs)\n",
            format(nrow(pair_panel), big.mark = ","),
            uniqueN(pair_panel$cell_id),
            uniqueN(pair_panel[, .(buyer, seller_nace4d, seller)])))

# ---------------------------------------------------------------------------
# Cell-role-year panel (collapse bot to portfolio mean per cell-year)
# Used for the naive DiD and the event study.
# ---------------------------------------------------------------------------
cat("Building cell-role-year panel (portfolio bot)...\n")
top_cell_panel <- pair_panel[role == "top",
                              .(share = share[1L]),
                              by = .(buyer, seller_nace4d, cell_id,
                                     cell_role_id = paste(cell_id, "top",
                                                          sep = "::"),
                                     role, group_top, post, post_top, year)]
bot_cell_panel <- pair_panel[role == "bot",
                              .(share = mean(share)),
                              by = .(buyer, seller_nace4d, year)]
bot_cell_panel[, role := "bot"]
bot_cell_panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]
bot_cell_panel[, cell_role_id := paste(cell_id, "bot", sep = "::")]
bot_cell_panel[, group_top    := 0L]
bot_cell_panel[, post         := as.integer(year >= TREAT_YEAR)]
bot_cell_panel[, post_top     := 0L]
cell_panel <- rbind(top_cell_panel, bot_cell_panel, use.names = TRUE)
cell_panel <- cell_panel[, .(buyer, seller_nace4d, year, role, share,
                              cell_id, cell_role_id, group_top, post, post_top)]
cat(sprintf("  Cell-role panel: %s rows (%d cells)\n",
            format(nrow(cell_panel), big.mark = ","),
            uniqueN(cell_panel$cell_id)))

# ---------------------------------------------------------------------------
# Spec 1: Naive DiD on the cell-role panel
# ---------------------------------------------------------------------------
cat("\n=== Spec 1: Naive DiD (cell-role panel, portfolio bot) ===\n")
mod_naive <- feols(share ~ post_top | cell_role_id + year,
                   data    = cell_panel,
                   cluster = ~ cell_id,
                   notes   = FALSE)
print(summary(mod_naive))

# ---------------------------------------------------------------------------
# Spec 2: Pair-level DiD with age x top FE
# ---------------------------------------------------------------------------
cat("\n=== Spec 2: Pair-level DiD with age x top FE ===\n")
mod_age <- feols(share ~ post_top |
                          cell_role_id + year + age + age^group_top,
                 data    = pair_panel,
                 cluster = ~ cell_id,
                 notes   = FALSE)
print(summary(mod_age))

# ---------------------------------------------------------------------------
# Spec 3: Event study (cell-role panel)
# ---------------------------------------------------------------------------
cat("\n=== Spec 3: Event study on cell-role panel (raw, no detrending) ===\n")
mod_es <- feols(share ~ i(year, group_top, ref = TREAT_YEAR - 1L) |
                         cell_role_id + year,
                data    = cell_panel,
                cluster = ~ cell_id,
                notes   = FALSE)
print(summary(mod_es))

# Extract event-study coefs
es_coefs <- as.data.table(coeftable(mod_es), keep.rownames = "term")
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

cat("\n--- Event-study coefficients (top vs bot, ref = 2016) ---\n")
print(es_coefs[, .(year, k, estimate = round(estimate, 4),
                    se = round(std_error, 4),
                    lo = round(lo, 4), hi = round(hi, 4))])

fwrite(es_coefs, file.path(OUTPUT_TAB,
       "phase4_within_intensive_did_eventstudy_coef.csv"))

# ---------------------------------------------------------------------------
# .tex tables
# ---------------------------------------------------------------------------
cat("\nWriting .tex tables...\n")

# Side-by-side: naive (cell-role) and age x top FE (pair-level)
etable(list("Naive DiD"                = mod_naive,
            "Pair-level + age x top FE" = mod_age),
       tex          = TRUE,
       file         = file.path(OUTPUT_TAB,
                                "phase4_within_intensive_did_coefs.tex"),
       replace      = TRUE,
       title        = paste("Within-NACE-4d intensive-margin DiD,",
                            "present-in-2010-14 sample, panel 2012-2020.",
                            "Column 1: naive DiD on the cell-role panel",
                            "(top supplier vs portfolio-bot per cell-year).",
                            "Column 2: pair-level DiD with age x top fixed",
                            "effects to absorb the differential",
                            "attrition between top and bot."),
       label        = "tab:phase4_within_intensive_did_coefs",
       dict         = c(post_top     = "post $\\times$ top",
                        share        = "Within-cell share",
                        cell_role_id = "Cell $\\times$ role",
                        year         = "Year",
                        age          = "Age",
                        group_top    = "Top"),
       cluster      = ~cell_id,
       signif.code  = c("***" = 0.01, "**" = 0.05, "*" = 0.10),
       digits       = 4,
       digits.stats = 4)

# Event-study tex table
es_tex <- es_coefs[, .(Year        = year,
                       k,
                       Estimate    = sprintf("%.4f", estimate),
                       `Std. Err.` = sprintf("%.4f", std_error),
                       `95\\% CI`   = sprintf("[%.4f, %.4f]", lo, hi))]
es_tex[k == -1, `:=`(Estimate = "0 (ref)", `Std. Err.` = "--",
                     `95\\% CI` = "--")]
es_xtable <- xtable(es_tex,
                    caption = paste("Event-study coefficients on the",
                                    "within-NACE-4d intensive margin.",
                                    "Year-by-year top vs bot differential,",
                                    "relative to 2016 (omitted reference).",
                                    "Spec: share $\\sim$ i(year, top, ref=2016)",
                                    "| cell-role FE + year FE. Clustered on",
                                    "cell. Panel 2012-2020."),
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

cat("\nDone.\n  figures:", OUTPUT_FIG, "\n  tables :", OUTPUT_TAB, "\n")

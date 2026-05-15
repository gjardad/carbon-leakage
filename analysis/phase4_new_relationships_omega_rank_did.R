###############################################################################
# phase4_new_relationships_omega_rank_did.R
#
# PURPOSE
#   Formal DiD / event study around the two ETS event years (Phase I launch
#   2005, MSR decision 2017). For tau = 2017, LHS is the supplier's
#   within-NACE4d allowance-shortage rank (Def 1: shortage / total_cost)
#   FIXED at year tau-1 = 2016. This strips out within-firm omega evolution
#   entirely -- any movement in coefficients across event-time is composition
#   (which suppliers buyers pick), not suppliers cleaning up.
#   For tau = 2005 the LHS is fixed at year 2005 (EUTL data starts in 2005;
#   no pre-period rank exists). Interpretation at tau = 2005 mixes the
#   composition channel with first-year omega noise, but the dominant
#   identification still asks: are buyers picking systematically different
#   suppliers post-policy?
#
#   Sample: every new (buyer, supplier, year_first) omega-matched pair with
#   year_first in [tau - WINDOW, tau + WINDOW] and a non-missing tau-1 rank
#   for the supplier.
#
# SPECIFICATIONS (per tau)
#   (1) Event study:
#         rank_ij,tau-1  =  sum_{e != -1} beta_e * 1{year_first - tau = e}
#                          + alpha_buyer + gamma_NACE4d + eps_ij
#         SEs clustered two-way at buyer x supplier-NACE4d.
#         Coefficients e = -5,...,-2 trace the pre-trend; e = 0,...,+5
#         trace the post effect. Two specs reported side-by-side:
#           base   - no supplier-level controls
#           tenure - add supplier_tenure = year_first - supplier_first_b2b_year
#                    as a continuous control. Absorbs survivor-bias selection
#                    in the tau-1-fixed-rank LHS (pairs at rel_year = -5
#                    require the supplier to have persisted 5+ years).
#
#   (2) Pooled post indicator:
#         rank_ij,tau-1  =  beta * 1{year_first >= tau} (+ supplier_tenure)
#                          + alpha_buyer + gamma_NACE4d + eps_ij
#         beta is the average post-tau shift. Reported for {base, tenure}.
#
#   (3) LOO-drop-3511 robustness: same as (2) but dropping NACE 3511
#       (electricity). On the 3-event spec the full-sample 2013 LOO showed
#       3511 is the only sector whose removal flips the sign -- the basic
#       null should become even cleaner without it. Also run for {base,
#       tenure}.
#
# OUTPUTS
#   - phase4_new_relationships_omega_rank_did_event_study_<tau>.{png,pdf}
#   - phase4_new_relationships_omega_rank_did_coefs.tex
#   - phase4_new_relationships_omega_rank_did_coefs.csv
#   - phase4_new_relationships_omega_rank_did_event_study.csv
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

set.seed(20260512)

TAUS   <- c(2005L, 2017L)
WINDOW <- 5L
B2B_YEAR_LO <- 2002L
B2B_YEAR_HI <- 2022L

# Reference year for the LHS-fixed rank.
#   tau = 2017 -> ref_year = 2016 (pre-treatment, strips within-firm omega evolution)
#   tau = 2005 -> ref_year = 2005 (EUTL starts in 2005; no pre-period data available)
ref_year_for_tau <- function(tau) {
  if (tau == 2005L) 2005L else tau - 1L
}

write_tex_table <- function(dt, file, digits = 4, caption = NULL) {
  x <- xtable(as.data.frame(dt), digits = digits, caption = caption)
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function    = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 1. Load data
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(B2B_YEAR_LO, B2B_YEAR_HI) &
           !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year))]

# Supplier B2B tenure control: first year the supplier appears anywhere in
# B2B (across all sectors). Used to absorb survivor-bias selection in the
# tau-1-fixed-rank LHS: pairs in rel_year = -5 require the supplier to have
# been around for 5+ years before tau, which selects on a non-random subset
# of long-tenured suppliers. Cross-supplier tenure variation identifies the
# control.
supplier_first_b2b <- b2b[, .(supplier_first_b2b_year = min(year)),
                          by = seller]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  shortage, total_cost,
  nace4d = as.character(nace4d)
)]
rm(firm_exposure)

# Def 1: allowance shortage / total cost (allow negative, do NOT floor at 0)
fe[, omega1 := ifelse(!is.na(shortage) & !is.na(total_cost) & total_cost > 0,
                      shortage / total_cost, NA_real_)]

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_treated_nace4d)))

# Attach seller NACE4d (with modal fallback for missing seller-years)
seller_modal_nace <- aa[, .N, by = .(vat, nace4d)][
  order(vat, -N), .SD[1L], by = vat][, .(seller = vat, modal_nace4d = nace4d)]
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- merge(b2b, seller_modal_nace, by = "seller", all.x = TRUE)
b2b[is.na(seller_nace4d), seller_nace4d := modal_nace4d]
b2b[, modal_nace4d := NULL]
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# First-year-observed table (full panel) and new pairs (year_first > YEAR_LO)
first_year <- b2b[, .(year_first = min(year)), by = .(buyer, seller)]
new_rel <- first_year[year_first > B2B_YEAR_LO]
new_rel <- merge(new_rel,
                 b2b[, .(buyer, seller, year, seller_nace4d)],
                 by.x = c("buyer", "seller", "year_first"),
                 by.y = c("buyer", "seller", "year"))
new_rel <- merge(new_rel, supplier_first_b2b, by = "seller", all.x = TRUE)
cat(sprintf("  new relationships %d-%d: %d (%.1f%% have supplier_first_b2b_year)\n",
            B2B_YEAR_LO + 1L, B2B_YEAR_HI, nrow(new_rel),
            100 * mean(!is.na(new_rel$supplier_first_b2b_year))))

# ---------------------------------------------------------------------------
# 2. Helper: build LHS panel for a given tau and run regressions
# ---------------------------------------------------------------------------
build_rank_at <- function(tau) {
  ref_year <- ref_year_for_tau(tau)
  d <- fe[year == ref_year & !is.na(omega1)]
  if (nrow(d) == 0L) stop(sprintf("No firm_exposure rows in ref_year %d", ref_year))
  d[, rank_fixed := frank(omega1, ties.method = "average") / .N, by = nace4d]
  d[, .(seller = vat, seller_nace4d = nace4d, rank_fixed,
        omega_ref = omega1)]
}

run_one_tau <- function(tau) {
  ref_year <- ref_year_for_tau(tau)
  cat(sprintf("\n========== tau = %d (ref year %d) ==========\n", tau, ref_year))

  rank_at <- build_rank_at(tau)
  cat(sprintf("  rankable suppliers in %d: %d (across %d NACE4d)\n",
              ref_year, nrow(rank_at), uniqueN(rank_at$seller_nace4d)))

  # New pairs in window, with a rank in tau-1
  window <- c(tau - WINDOW, tau + WINDOW)
  d <- new_rel[year_first %between% window]
  d <- merge(d, rank_at,
             by = c("seller", "seller_nace4d"))
  d[, rel_year := year_first - tau]
  d[, supplier_tenure := year_first - supplier_first_b2b_year]
  cat(sprintf("  in-sample new pairs in [%d, %d]: %d (%d buyers, %d sellers, %d NACE4d)\n",
              window[1], window[2], nrow(d),
              uniqueN(d$buyer), uniqueN(d$seller), uniqueN(d$seller_nace4d)))
  cat(sprintf("  supplier_tenure summary: min=%d, mean=%.1f, max=%d, frac with NA=%.3f\n",
              suppressWarnings(min(d$supplier_tenure, na.rm = TRUE)),
              mean(d$supplier_tenure, na.rm = TRUE),
              suppressWarnings(max(d$supplier_tenure, na.rm = TRUE)),
              mean(is.na(d$supplier_tenure))))

  # Event study, two specs: base and with supplier_tenure control
  m_es <- feols(rank_fixed ~ i(rel_year, ref = -1) | buyer + seller_nace4d,
                cluster = ~ buyer + seller_nace4d,
                data = d)
  m_es_tenure <- feols(rank_fixed ~ i(rel_year, ref = -1) + supplier_tenure |
                         buyer + seller_nace4d,
                       cluster = ~ buyer + seller_nace4d,
                       data = d)

  # Pooled DiD: 4 specs = {full, drop NACE 3511} x {base, tenure}
  d[, post := as.integer(rel_year >= 0L)]
  d_no3511 <- d[seller_nace4d != "3511"]
  m_did               <- feols(rank_fixed ~ post |
                                 buyer + seller_nace4d,
                               cluster = ~ buyer + seller_nace4d, data = d)
  m_did_tenure        <- feols(rank_fixed ~ post + supplier_tenure |
                                 buyer + seller_nace4d,
                               cluster = ~ buyer + seller_nace4d, data = d)
  m_did_no3511        <- feols(rank_fixed ~ post |
                                 buyer + seller_nace4d,
                               cluster = ~ buyer + seller_nace4d, data = d_no3511)
  m_did_no3511_tenure <- feols(rank_fixed ~ post + supplier_tenure |
                                 buyer + seller_nace4d,
                               cluster = ~ buyer + seller_nace4d, data = d_no3511)

  cat("\n  Event study (base):\n")
  print(coeftable(m_es))
  cat("\n  Event study (+ supplier_tenure):\n")
  print(coeftable(m_es_tenure))
  cat("\n  Pooled DiD (full sample, base):\n");          print(coeftable(m_did))
  cat("\n  Pooled DiD (full sample, + tenure):\n");      print(coeftable(m_did_tenure))
  cat(sprintf("\n  Pooled DiD (drop NACE 3511, base, n=%d):\n", nrow(d_no3511)))
  print(coeftable(m_did_no3511))
  cat(sprintf("\n  Pooled DiD (drop NACE 3511, + tenure, n=%d):\n", nrow(d_no3511)))
  print(coeftable(m_did_no3511_tenure))

  # Tidy event-study results for both specs
  tidy_es <- function(fit, spec_label) {
    es <- as.data.table(coeftable(fit), keep.rownames = "term")
    setnames(es,
             c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
             c("estimate", "se", "t", "p"))
    # Keep only rel_year coefficients (drop supplier_tenure if present)
    es <- es[grepl("^rel_year::", term)]
    es[, term := gsub("^rel_year::", "", term)]
    es[, rel_year := as.integer(term)]
    es[, tau := tau]
    es[, spec := spec_label]
    es <- rbind(es,
                data.table(term = "-1", estimate = 0, se = NA_real_,
                           t = NA_real_, p = NA_real_,
                           rel_year = -1L, tau = tau, spec = spec_label),
                fill = TRUE)
    setorder(es, rel_year)
    es[, ci_lo := estimate - 1.96 * se]
    es[, ci_hi := estimate + 1.96 * se]
    es
  }
  es_tbl <- rbindlist(list(
    tidy_es(m_es,        "base"),
    tidy_es(m_es_tenure, "tenure")
  ), use.names = TRUE)

  did_tbl <- data.table(
    tau    = tau,
    sample = c("full", "full", "drop NACE 3511", "drop NACE 3511"),
    spec   = c("base", "tenure", "base", "tenure"),
    n_obs  = c(m_did$nobs, m_did_tenure$nobs,
               m_did_no3511$nobs, m_did_no3511_tenure$nobs),
    beta   = c(coef(m_did)["post"], coef(m_did_tenure)["post"],
               coef(m_did_no3511)["post"], coef(m_did_no3511_tenure)["post"]),
    se     = c(se(m_did)["post"], se(m_did_tenure)["post"],
               se(m_did_no3511)["post"], se(m_did_no3511_tenure)["post"]),
    p      = c(pvalue(m_did)["post"], pvalue(m_did_tenure)["post"],
               pvalue(m_did_no3511)["post"], pvalue(m_did_no3511_tenure)["post"])
  )

  list(es = es_tbl, did = did_tbl,
       m_es = m_es, m_es_tenure = m_es_tenure,
       m_did = m_did, m_did_tenure = m_did_tenure,
       m_did_no3511 = m_did_no3511,
       m_did_no3511_tenure = m_did_no3511_tenure)
}

# ---------------------------------------------------------------------------
# 3. Run all three taus
# ---------------------------------------------------------------------------
results <- lapply(TAUS, run_one_tau)
names(results) <- as.character(TAUS)

# ---------------------------------------------------------------------------
# 4. Combined output tables
# ---------------------------------------------------------------------------
es_all  <- rbindlist(lapply(results, `[[`, "es"))
did_all <- rbindlist(lapply(results, `[[`, "did"))

fwrite(es_all,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_did_event_study.csv"))
fwrite(did_all,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_did_coefs.csv"))

did_all_print <- did_all[, .(tau, sample, n_obs,
                              beta = round(beta, 4),
                              se   = round(se,   4),
                              p    = round(p,    4))]
write_tex_table(did_all_print,
                file.path(OUTPUT_TAB,
                          "phase4_new_relationships_omega_rank_did_coefs.tex"),
                caption = "Pooled post-tau DiD on supplier omega-rank fixed at tau-1 (Def 1: allowance shortage / total cost). Two-way clustered SEs (buyer, supplier-NACE4d).")

cat("\nCombined pooled DiD table:\n")
print(did_all_print)

# ---------------------------------------------------------------------------
# 5. Event-study plots (one per tau)
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank())

for (this_tau in TAUS) {
  this_ref <- ref_year_for_tau(this_tau)
  d_es <- es_all[tau == this_tau]
  # Dodge base vs tenure specs side by side at each rel_year
  d_es[, spec_lab := factor(spec,
                            levels = c("base", "tenure"),
                            labels = c("Base (buyer + NACE4d FE)",
                                       "+ Supplier B2B tenure"))]
  p <- ggplot(d_es,
              aes(x = rel_year, y = estimate,
                  color = spec_lab, group = spec_lab)) +
    geom_hline(yintercept = 0, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = -0.5, linetype = "dashed", color = "firebrick") +
    geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                  width = 0.25,
                  position = position_dodge(width = 0.4)) +
    geom_point(size = 2, position = position_dodge(width = 0.4)) +
    scale_x_continuous(breaks = seq(-WINDOW, WINDOW, 1)) +
    scale_color_manual(values = c("Base (buyer + NACE4d FE)" = "steelblue",
                                  "+ Supplier B2B tenure"   = "firebrick"),
                       name = NULL) +
    labs(title    = sprintf("Event study: new-supplier omega-rank around tau = %d (LHS fixed at %d, Def 1)",
                            this_tau, this_ref),
         subtitle = "Coefficients on rel_year dummies (ref = -1). 95% CIs from two-way clustered SEs (buyer, supplier-NACE4d).",
         x = sprintf("Year relative to tau = %d", this_tau),
         y = sprintf("Coefficient on supplier rank fixed at %d", this_ref)) +
    base_theme +
    theme(legend.position = "bottom")

  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_new_relationships_omega_rank_did_event_study_%d.png", this_tau)),
         p, width = 9, height = 5, dpi = 200)
  ggsave(file.path(OUTPUT_FIG,
                   sprintf("phase4_new_relationships_omega_rank_did_event_study_%d.pdf", this_tau)),
         p, width = 9, height = 5)
}

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")

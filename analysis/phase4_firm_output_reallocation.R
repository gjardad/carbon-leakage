###############################################################################
# phase4_firm_output_reallocation.R
#
# Angle 1 of REALLOCATION_MECHANISM_PLAN.md.
#
# STEP 1: Build firm-level treatment variables
#   - firm_cost_share_i (primary) = mean_{2013-16}(shortage*EUA) / mean_{2010-12}(total_cost)
#   - firm_emint_physical_i (robustness) = mean_{2013-16}(shortage) / mean_{2010-12}(total_cost)
#   - firm_dev_{i,s} = firm_cost_share_i - mean within NACE4d sector
#   Fallback to earliest 3-year window for firms without 2010-12 coverage, matching
#   phase3_build_exposure_panel.R:188-208.
#
# STEP 2: Verification
#   Aggregate firm_cost_share_i to NACE4d weighted by base-period total_cost. Must
#   reproduce intensity_base_s from phase3 within ETS-firm-only rounding.
#
# STEP 3: Spec 1.A under ID-A (annual CPShock)
#   Δlog(real_rev)_{i,s,t,h} = β * (CPShock^ann_t * firm_dev_{i,s}) + α_{s,t} + α_i + ε
#   h ∈ {0, 1, 2, 3}; two-way cluster on firm and sector-year.
#   Also: firm_cost_share (not within-sector demeaned) as a cross-check.
#
# Sample window: 2005-2019 (clean CPShock identification per PASSTHROUGH_CPSHOCK.md).
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(stringr)
library(fixest)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---------------------------------------------------------------------------
# Load inputs
# ---------------------------------------------------------------------------
load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))    # firm_exposure
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))  # sector_exposure
load(file.path(OUT_DATA, "cpshock_annual.RData"))          # cpshock_annual
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData")) # deflator, deflator_2d_only

base_num_years  <- 2013:2016   # numerator window (same as sector intensity_base)
base_denom_years <- 2010:2012  # denominator window (fixed, matches sector exposure_alt)
sample_years    <- 2005:2019   # clean CPShock identification

# ---------------------------------------------------------------------------
# Step 1a: firm-level cost-share numerator (2013-16 mean of shortage * EUA)
# ---------------------------------------------------------------------------
num_firm <- firm_exposure %>%
  filter(year %in% base_num_years) %>%
  group_by(vat) %>%
  summarise(
    mean_carbon_cost = mean(carbon_cost, na.rm = TRUE),
    mean_shortage    = mean(shortage,    na.rm = TRUE),
    n_num_years      = sum(!is.na(carbon_cost)),
    .groups = "drop"
  )

# ---------------------------------------------------------------------------
# Step 1b: firm-level denominator (2010-12 mean of total_cost, with fallback)
# ---------------------------------------------------------------------------
denom_primary <- firm_exposure %>%
  filter(year %in% base_denom_years, !is.na(total_cost), total_cost > 0) %>%
  group_by(vat) %>%
  summarise(
    mean_total_cost = mean(total_cost, na.rm = TRUE),
    n_denom_years   = n(),
    .groups = "drop"
  )

# Fallback: firms not covered in 2010-12 -> use earliest 3 years of positive total_cost
firms_all <- firm_exposure %>% distinct(vat)
firms_fallback <- anti_join(firms_all, denom_primary, by = "vat") %>% pull(vat)

denom_fallback <- firm_exposure %>%
  filter(vat %in% firms_fallback, !is.na(total_cost), total_cost > 0) %>%
  arrange(vat, year) %>%
  group_by(vat) %>%
  slice_head(n = 3) %>%
  summarise(
    mean_total_cost = mean(total_cost, na.rm = TRUE),
    n_denom_years   = n(),
    .groups = "drop"
  )

denom_firm <- bind_rows(denom_primary, denom_fallback)

cat(sprintf("Firms with 2010-12 denom: %d, fallback: %d, no denom at all: %d\n",
            nrow(denom_primary),
            nrow(denom_fallback),
            nrow(firms_all) - nrow(denom_firm)))

# ---------------------------------------------------------------------------
# Step 1c: assemble firm treatment + NACE4d deviation
# ---------------------------------------------------------------------------
firm_nace <- firm_exposure %>%
  distinct(vat, nace4d, nace2d) %>%
  group_by(vat) %>%
  slice(1) %>%        # one nace per firm (mode would be fancier; first is fine here)
  ungroup()

firm_treat <- num_firm %>%
  inner_join(denom_firm, by = "vat") %>%
  inner_join(firm_nace, by = "vat") %>%
  mutate(
    firm_cost_share     = ifelse(mean_total_cost > 0, mean_carbon_cost / mean_total_cost, NA_real_),
    firm_emint_physical = ifelse(mean_total_cost > 0, mean_shortage    / mean_total_cost, NA_real_)
  ) %>%
  filter(!is.na(firm_cost_share))

# Within-sector demeaning (unweighted; alternative: cost-weighted — report below too)
firm_treat <- firm_treat %>%
  group_by(nace4d) %>%
  mutate(
    sector_mean_share = mean(firm_cost_share, na.rm = TRUE),
    firm_dev_share    = firm_cost_share - sector_mean_share,
    sector_mean_phys  = mean(firm_emint_physical, na.rm = TRUE),
    firm_dev_phys     = firm_emint_physical - sector_mean_phys,
    n_sector_firms    = n()
  ) %>%
  ungroup()

cat(sprintf("\nfirm_treat rows: %d  (NACE4d sectors: %d)\n",
            nrow(firm_treat), n_distinct(firm_treat$nace4d)))
cat(sprintf("firm_cost_share summary:\n"))
print(summary(firm_treat$firm_cost_share))
cat(sprintf("firm_dev_share summary (within-sector deviation):\n"))
print(summary(firm_treat$firm_dev_share))

# ---------------------------------------------------------------------------
# Step 2: Verification — aggregating firm_cost_share to NACE4d must reproduce
# intensity_base_s (= mean_{2013-16}(exposure_alt_total)).
# ---------------------------------------------------------------------------
# Sector-level reference, computed the same way as phase3_ppi_passthrough_monthly.R:113-117.
intensity_base_ref <- sector_exposure %>%
  filter(year %in% base_num_years) %>%
  group_by(nace4d) %>%
  summarise(intensity_base_ref = mean(exposure_alt_total, na.rm = TRUE), .groups = "drop")

# Aggregate firm treatment to sector: numerator-sum / denominator-sum.
intensity_base_check <- firm_treat %>%
  group_by(nace4d) %>%
  summarise(
    num_sum   = sum(mean_carbon_cost, na.rm = TRUE),
    denom_sum = sum(mean_total_cost,  na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(intensity_base_check = ifelse(denom_sum > 0, num_sum / denom_sum, NA_real_))

verify <- intensity_base_ref %>%
  inner_join(intensity_base_check, by = "nace4d") %>%
  mutate(diff = intensity_base_check - intensity_base_ref,
         pct_diff = diff / pmax(intensity_base_ref, 1e-8))

cat(sprintf("\n=== Verification: aggregated firm_cost_share vs sector intensity_base ===\n"))
cat(sprintf("Sectors compared: %d\n", nrow(verify)))
cat(sprintf("Max abs diff: %.6f\n", max(abs(verify$diff), na.rm = TRUE)))
cat(sprintf("Mean abs pct diff: %.4f%%\n", 100 * mean(abs(verify$pct_diff), na.rm = TRUE)))
cat(sprintf("P95 abs pct diff: %.4f%%\n", 100 * quantile(abs(verify$pct_diff), 0.95, na.rm = TRUE)))
cat(sprintf("Correlation: %.4f\n", cor(verify$intensity_base_ref, verify$intensity_base_check,
                                         use = "complete.obs")))

# Save treatment variables for downstream specs.
saveRDS(firm_treat, file.path(OUT_DATA, "phase4_firm_treatment.rds"))
cat(sprintf("\nSaved phase4_firm_treatment.rds: %d rows.\n", nrow(firm_treat)))

# ---------------------------------------------------------------------------
# Step 3: Build panel for Spec 1.A under ID-A
#   - Δlog(real_rev)_{i,t,h} = β * (CPShock^ann_t * firm_dev_{i,s}) + FE + ε
#   - h ∈ {0, 1, 2, 3}
# ---------------------------------------------------------------------------

# Bring intensity_base to the sector level (for later specs)
intensity_base_sector <- intensity_base_ref %>%
  rename(intensity_base = intensity_base_ref) %>%
  mutate(intensity_base = coalesce(intensity_base, 0))

# Firm panel: real revenue with NACE4d PPI deflator.
panel <- firm_exposure %>%
  filter(year %in% sample_years, !is.na(revenue), revenue > 0) %>%
  mutate(nace2d = str_sub(nace5d, 1, 2)) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi), by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100,
         log_real_rev = log(real_revenue)) %>%
  inner_join(firm_treat %>% select(vat, firm_cost_share, firm_emint_physical,
                                    firm_dev_share, firm_dev_phys),
             by = "vat") %>%
  left_join(intensity_base_sector, by = "nace4d") %>%
  left_join(cpshock_annual %>% select(year, cpshock_shock, cpshock_surprise),
            by = "year") %>%
  filter(!is.na(cpshock_shock)) %>%
  arrange(vat, year)

# LHS = log_real_rev[t+h] - log_real_rev[t-1], LP-style (matches S12 convention).
# h = -2 is a pre-trend placebo (should be null if shock is exogenous).
# h = -1 is identically zero by construction (omitted).
panel <- panel %>%
  group_by(vat) %>%
  arrange(year, .by_group = TRUE) %>%
  mutate(
    log_rev_lag = dplyr::lag(log_real_rev, 1),
    dm2 = dplyr::lag(log_real_rev, 2)   - log_rev_lag,
    d0  = log_real_rev                   - log_rev_lag,
    d1  = dplyr::lead(log_real_rev, 1)   - log_rev_lag,
    d2  = dplyr::lead(log_real_rev, 2)   - log_rev_lag,
    d3  = dplyr::lead(log_real_rev, 3)   - log_rev_lag
  ) %>%
  ungroup()

# Firms with ≥3 years (plan requirement).
firm_years <- panel %>% count(vat, name = "n_years")
panel <- panel %>% inner_join(firm_years %>% filter(n_years >= 3), by = "vat")

# Interaction terms — both Shock (narrative-identified, SD ~2.4 annually) and
# Surprise (mean-zero daily, SD ~0.53 annually) per Kanzig conventions.
panel <- panel %>%
  mutate(
    shock_x_dev    = cpshock_shock    * firm_dev_share,
    shock_x_phys   = cpshock_shock    * firm_dev_phys,
    shock_x_cs     = cpshock_shock    * firm_cost_share,
    surpr_x_dev    = cpshock_surprise * firm_dev_share,
    surpr_x_phys   = cpshock_surprise * firm_dev_phys,
    surpr_x_cs     = cpshock_surprise * firm_cost_share
  )

cat(sprintf("Shock   annual SD: %.4f\n", sd(panel$cpshock_shock,    na.rm = TRUE)))
cat(sprintf("Surprise annual SD: %.4f\n", sd(panel$cpshock_surprise, na.rm = TRUE)))

cat(sprintf("\n=== Spec 1.A panel ===\n"))
cat(sprintf("N firms: %d  |  firm-years: %d  |  year range: %d-%d\n",
            n_distinct(panel$vat), nrow(panel),
            min(panel$year), max(panel$year)))
cat(sprintf("firm_dev_share summary (panel-weighted):\n"))
print(summary(panel$firm_dev_share))
cat(sprintf("shock_x_dev summary:\n"))
print(summary(panel$shock_x_dev))
cat(sprintf("CPShock annual SD in panel: %.4f\n", sd(panel$cpshock_shock, na.rm = TRUE)))
cat(sprintf("firm_dev_share SD cross-section: %.4f\n",
            sd(firm_treat$firm_dev_share, na.rm = TRUE)))

# ---------------------------------------------------------------------------
# Spec 1.A under ID-A: run per horizon
# ---------------------------------------------------------------------------
cat(sprintf("\n=== Spec 1.A (ID-A: CPShock annual × firm_dev_share) ===\n"))
cat(sprintf("FE: firm + sector-year. Cluster: firm, sector-year.\n\n"))

spec1a_results <- list()
for (h in 0:3) {
  lhs <- paste0("d", h)
  f <- as.formula(sprintf("%s ~ shock_x_dev | vat + nace4d^year", lhs))
  m <- feols(f, data = panel, cluster = ~ vat + nace4d^year)
  spec1a_results[[paste0("h", h)]] <- m
  cat(sprintf("--- h=%d ---\n", h))
  print(summary(m))
  cat("\n")
}

# Cross-check with firm_cost_share (not within-sector demeaned) — should be similar
# sign given s×t FE absorbs the sector-common part, leaving firm-specific variation.
cat(sprintf("\n=== Cross-check: CPShock × firm_cost_share (not demeaned) ===\n"))
for (h in 0:3) {
  lhs <- paste0("d", h)
  f <- as.formula(sprintf("%s ~ shock_x_cs | vat + nace4d^year", lhs))
  m <- feols(f, data = panel, cluster = ~ vat + nace4d^year)
  cat(sprintf("--- h=%d ---\n", h))
  print(summary(m))
  cat("\n")
}

# Physical robustness
cat(sprintf("\n=== Robustness: CPShock × firm_dev_phys (physical intensity) ===\n"))
for (h in 0:3) {
  lhs <- paste0("d", h)
  f <- as.formula(sprintf("%s ~ shock_x_phys | vat + nace4d^year", lhs))
  m <- feols(f, data = panel, cluster = ~ vat + nace4d^year)
  cat(sprintf("--- h=%d ---\n", h))
  print(summary(m))
  cat("\n")
}

# ---------------------------------------------------------------------------
# Spec 1.A with cpshock_surprise (matches S12 surprise variant) — power check
# ---------------------------------------------------------------------------
cat(sprintf("\n=== Spec 1.A (ID-A surprise variant) ===\n"))
spec1a_sur_results <- list()
for (h in 0:3) {
  lhs <- paste0("d", h)
  f <- as.formula(sprintf("%s ~ surpr_x_dev | vat + nace4d^year", lhs))
  m <- feols(f, data = panel, cluster = ~ vat + nace4d^year)
  spec1a_sur_results[[paste0("h", h)]] <- m
  cat(sprintf("--- h=%d (surprise) ---\n", h))
  print(summary(m))
  cat("\n")
}

# ---------------------------------------------------------------------------
# Verification per plan: β on firm_dev alone (no shock interaction),
# sector FE only, should recover within-sector output-share pattern from
# phase1a_output_share_by_exposure.R (high-exposure firms slightly gaining
# within-sector share pre-shock -- caveat: phase1a used revenue-normalized).
# Also run pre/post MSR 2017 split for sign comparison with phase1a.
# ---------------------------------------------------------------------------
cat(sprintf("\n=== Verification: firm_dev alone (no shock), levels regression ===\n"))
# level of log_real_rev on firm_dev × year dummies, sector and firm FE absorbed
# as far as possible. We do this on the level, not the difference.
panel_lev <- panel %>% mutate(post_msr = as.integer(year >= 2017))

# firm_dev_share is firm-invariant, so firm FE absorbs it. Drop firm FE; keep
# nace4d × year FE so identification is cross-firm within sector-year.
m_lev_all  <- feols(log_real_rev ~ firm_dev_share
                    | nace4d^year, data = panel, cluster = ~ vat)
m_lev_post <- feols(log_real_rev ~ firm_dev_share + firm_dev_share:post_msr
                    | nace4d^year, data = panel_lev, cluster = ~ vat)
cat("\n-- firm_dev on log_real_rev, all years (no firm FE) --\n")
print(summary(m_lev_all))
cat("\n-- firm_dev × post-MSR (2017+) on log_real_rev --\n")
print(summary(m_lev_post))

# ---------------------------------------------------------------------------
# Output tables
# ---------------------------------------------------------------------------
etable(spec1a_results,
       title = "Spec 1.A ID-A (Shock): Dlog(real_rev) = b*(CPShock_t * firm_dev_share) + firm + sector*year FE",
       file = file.path(OUTPUT_TAB, "phase4_spec1A_ida_shock.txt"), replace = TRUE)
etable(spec1a_sur_results,
       title = "Spec 1.A ID-A (Surprise)",
       file = file.path(OUTPUT_TAB, "phase4_spec1A_ida_surprise.txt"), replace = TRUE)
cat(sprintf("\nWrote phase4_spec1A_ida_shock.txt and phase4_spec1A_ida_surprise.txt\n"))

# ---------------------------------------------------------------------------
# Spec 1.C — Sample split by realized sector pass-through
#   Restrict panel to sectors where per-sector gamma_s from the monthly LP at
#   h=12 is positive (and significant at one of three cutoffs). Also report
#   the contrast sample (no-pass-through sectors).
# ---------------------------------------------------------------------------
cat(sprintf("\n=================================================================\n"))
cat(sprintf(" Spec 1.C — Sample split by realized sector pass-through\n"))
cat(sprintf("=================================================================\n"))

passthrough_path <- file.path(OUT_DATA, "phase4_sector_passthrough.RData")
if (!file.exists(passthrough_path)) {
  stop("Missing ", passthrough_path, ". Run phase4_sector_passthrough_classification.R first.")
}
load(passthrough_path)   # sector_passthrough

panel_c <- panel %>% left_join(sector_passthrough, by = "nace4d")
cat(sprintf("Firms joined to pass-through classification: %d of %d rows match\n",
            sum(!is.na(panel_c$gamma_shock)), nrow(panel_c)))

run_split <- function(panel_in, split_col, split_value, signal_col, shock_sd, label) {
  dat <- panel_in %>% filter(.data[[split_col]] == split_value)
  if (nrow(dat) < 100) {
    cat(sprintf("  [%s] sample too small (%d rows); skipping\n", label, nrow(dat)))
    return(NULL)
  }
  ix <- paste0(signal_col, "_x_dev")
  dat <- dat %>% mutate(x_int = .data[[signal_col]] * firm_dev_share)
  cat(sprintf("\n--- %s (signal=%s) | firms=%d, sectors=%d, rows=%d ---\n",
              label, signal_col,
              n_distinct(dat$vat), n_distinct(dat$nace4d), nrow(dat)))
  res <- list()
  for (h in 0:3) {
    lhs <- paste0("d", h)
    f <- as.formula(sprintf("%s ~ x_int | vat + nace4d^year", lhs))
    m <- feols(f, data = dat, cluster = ~ vat + nace4d^year)
    res[[paste0("h", h)]] <- m
    ct <- coeftable(m)
    cat(sprintf("  h=%d  beta=%+.3f  SE=%.3f  t=%+.2f  p=%.3f  N=%d\n",
                h, ct["x_int","Estimate"], ct["x_int","Std. Error"],
                ct["x_int","t value"], ct["x_int","Pr(>|t|)"], m$nobs))
  }
  res
}

split_specs <- list(
  list(col = "class_shock_sign",     label_hi = "SHOCK sign>0 (high)",
                                     label_lo = "SHOCK sign<=0 (no)"),
  list(col = "class_shock_tercile",  label_hi = "SHOCK top tercile (high)",
                                     label_lo = "SHOCK bottom 2 terciles (no)"),
  list(col = "class_shock_10",       label_hi = "SHOCK sig 10% (high)",
                                     label_lo = "SHOCK non-sig 10% (no)"),
  list(col = "class_surprise_sign",  label_hi = "SURPRISE sign>0 (high)",
                                     label_lo = "SURPRISE sign<=0 (no)"),
  list(col = "class_intersect_sign", label_hi = "INTERSECT signs>0 (high)",
                                     label_lo = "INTERSECT signs<=0 (no)")
)

split_results <- list()
for (sp in split_specs) {
  cat(sprintf("\n### Split by: %s ###\n", sp$col))
  for (sig_col in c("cpshock_surprise", "cpshock_shock")) {
    key_hi <- paste(sp$col, sig_col, "hi", sep = "__")
    key_lo <- paste(sp$col, sig_col, "lo", sep = "__")
    split_results[[key_hi]] <- run_split(panel_c, sp$col, "high",
                                         sig_col, NA,
                                         sprintf("%s | %s", sp$label_hi, sig_col))
    split_results[[key_lo]] <- run_split(panel_c, sp$col, "no",
                                         sig_col, NA,
                                         sprintf("%s | %s", sp$label_lo, sig_col))
  }
}

# Save detailed output to a dedicated text table
sink(file.path(OUTPUT_TAB, "phase4_spec1C_sample_split.txt"))
cat("==============================================================\n")
cat(" Spec 1.C: Sample split of Spec 1.A by per-sector pass-through\n")
cat("==============================================================\n")
cat("Panel: ETS firms, 2005-2019 (post first-differencing), ≥3 years.\n")
cat("Spec  : d_h ~ (Signal_t × firm_dev_share) | vat + nace4d^year\n")
cat("Cluster: firm and sector-year.\n\n")

for (nm in names(split_results)) {
  m_list <- split_results[[nm]]
  if (is.null(m_list)) next
  cat(sprintf("\n--- %s ---\n", nm))
  for (h in 0:3) {
    m <- m_list[[paste0("h", h)]]
    if (is.null(m)) next
    ct <- coeftable(m)
    cat(sprintf("h=%d  beta=%+.3f  SE=%.3f  t=%+.2f  p=%.3f  N=%d\n",
                h, ct["x_int","Estimate"], ct["x_int","Std. Error"],
                ct["x_int","t value"], ct["x_int","Pr(>|t|)"], m$nobs))
  }
}
sink()
cat(sprintf("\nWrote phase4_spec1C_sample_split.txt\n"))

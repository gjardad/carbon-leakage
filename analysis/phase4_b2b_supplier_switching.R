###############################################################################
# phase4_b2b_supplier_switching.R
#
# Angle 4: B2B supplier switching under the EU ETS.
#
# Do buyers reallocate purchases away from high-carbon-exposure ETS suppliers,
# toward lower-exposure ETS sellers OR non-ETS sellers in the same NACE4d, as
# the post-MSR EUA price surge bites? Mirrors Peter-Ruane (2025) and
# Boehm-Levchenko-Pandalai-Nayar (2022) horizon-differentiated designs.
#
# SAMPLE NOTE
#   Regression sample includes BOTH ETS and non-ETS sellers in each seller-
#   NACE4d sector. Non-ETS sellers have firm_cost_share = 0 (no direct ETS
#   obligation). If a high-exposure ETS seller loses share to a non-ETS seller
#   in the same sector, that is the core reallocation evidence.
#
# Identification strategy
#   - Pre-period exposure window: 2013-2015 (MSR decided Oct 2015; 2016
#     potentially contaminated by anticipation).
#   - firm_cost_share_j = mean_{2013-15}(shortage * EUA) / mean_{2010-12}(total_cost)
#     for ETS firms; = 0 for non-ETS firms in B2B.
#   - Baseline year for event-study: t0 = 2015.
#
# Specifications
#
#   PRIMARY (event-study long differences around t0 = 2015)
#     Spec 4.B-event-h:
#       share_{j,b,2015+h} - share_{j,b,2015} = beta_h * firm_cost_share_j
#                                              + alpha_{b, s(j)} + eps
#       Within buyer x seller-NACE4d cell, across ALL sellers (ETS + non-ETS)
#       with different firm_cost_share. Absorbs sector-level confounders in the
#       window (oil, gas, electricity, Belgian cycle) via the cell FE; buyer x
#       sector FE also absorbs the sector-mean cost share, so demeaning is
#       redundant. h = 1..7. Analog of Peter-Ruane long difference 1989 -> 1989+h.
#       Sample: pairs active at t0=2015. For pairs that separate by t0+h,
#       share is imputed to 0 (correct post-separation share); avoids the
#       survivorship bias of dropping separated pairs.
#
#     Spec 4.A-event-h:
#       log(flow)_{j,b,2015+h} - log(flow)_{j,b,2015} = beta_h * firm_cost_share_j
#                                                      + alpha_{b, s(j)} + eps
#       Flow-level analog; same sample.
#
#   BENCHMARK (original Bartik annual-change; vulnerable to commodity-cycle
#   confound because EUA_t co-moves with oil/gas/electricity prices that
#   differentially affect carbon-intensive firms)
#     Spec 4.A-annual: Delta log(flow) ~ (EUA_t x firm_cost_share_j)
#                                        + alpha_{b,t} + alpha_{j,b}
#     Spec 4.B-annual: Delta share     ~ (EUA_t x firm_cost_share_j)
#                                        + alpha_{b, s(j), t} + alpha_{j,b}
#
#   Extensive margin at horizon h:
#     1{pair active at 2015+h | active at 2015} ~ firm_cost_share_j
#                                                  + alpha_{b, s(j)}
#
# Contamination filter: three NACE 20/24 VATs excluded.
#
# Kanzig annual series dropped entirely: shock and surprise variants are
# essentially uncorrelated at annual frequency (r = 0.03) and sign-flip driven
# by 6 disagreement-sign years. Not used. See
# memory/project_spec1a_shock_vs_surprise_flip.md.
#
# Output:
#   output/tables/phase4_b2b_supplier_switching.txt   (diagnostic + regs)
#   output/tables/phase4_b2b_supplier_switching.csv   (coefficient summary)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(stringr); library(fixest)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Config ----
year_lo      <- 2005L
year_hi      <- 2022L
pre_num_lo   <- 2013L      # 2013-2015: pre-MSR-decision carbon cost window
pre_num_hi   <- 2015L
pre_denom_lo <- 2010L      # 2010-2012: pre-period total cost window (unchanged)
pre_denom_hi <- 2012L
t0_baseline  <- 2015L      # event-study baseline: last pre-MSR-decision year
horizons     <- 1:7        # post-2015 horizons (2016..2022)

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)

eua_prices <- tibble(
  year = 2005:2022,
  eua_price = c(22, 18, 0.7, 22, 13, 14, 13, 7.5,
                4.5, 6, 7.5, 5, 5.8, 16, 25, 25, 53, 80)
)

# ---- Load ----
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))

b2b_df <- df_b2b_selected_sample
rm(df_b2b_selected_sample)

# ---- Build firm_exposure from raw ETS panel (self-contained) ----
# Previously sourced from phase3_firm_exposure.RData built by
# phase3_build_exposure_panel.R. Rebuild directly here so the script does
# not depend on the phase3 pipeline having been run on RMD.
# Definitions match phase3_build_exposure_panel.R lines 58-69:
#   shortage    = pmax(emissions - allocated_free, 0)
#   carbon_cost = shortage * eua_price
#   mat_inputs  = revenue - value_added
#   total_cost  = mat_inputs + wage_bill

firm_exposure <- firm_year_belgian_euets %>%
  filter(in_sample == 1) %>%
  left_join(eua_prices, by = "year") %>%
  mutate(shortage    = pmax(emissions - allocated_free, 0),
         carbon_cost = shortage * eua_price,
         mat_inputs  = revenue - value_added,
         total_cost  = mat_inputs + wage_bill)

cat(sprintf("Built firm_exposure: %d firm-years, %d firms, %d-%d\n",
            nrow(firm_exposure), n_distinct(firm_exposure$vat),
            min(firm_exposure$year), max(firm_exposure$year)))

# ---- Rebuild ETS firm treatment on 2013-2015 window ----
# This replaces the 2013-2016 window used in Spec 1.A's phase4_firm_treatment.rds.
# Rationale: MSR was decided Oct 2015; including 2016 risks MSR-anticipation
# contamination. Keep the 2010-2012 denominator unchanged.

num_firm <- firm_exposure %>%
  filter(year >= pre_num_lo, year <= pre_num_hi) %>%
  group_by(vat) %>%
  summarise(mean_carbon_cost = mean(carbon_cost, na.rm = TRUE),
            n_num_years = sum(!is.na(carbon_cost)), .groups = "drop")

denom_primary <- firm_exposure %>%
  filter(year >= pre_denom_lo, year <= pre_denom_hi,
         !is.na(total_cost), total_cost > 0) %>%
  group_by(vat) %>%
  summarise(mean_total_cost = mean(total_cost, na.rm = TRUE),
            n_denom_years = n(), .groups = "drop")

firms_all      <- firm_exposure %>% distinct(vat)
firms_fallback <- anti_join(firms_all, denom_primary, by = "vat") %>% pull(vat)
denom_fallback <- firm_exposure %>%
  filter(vat %in% firms_fallback, !is.na(total_cost), total_cost > 0) %>%
  arrange(vat, year) %>% group_by(vat) %>% slice_head(n = 3) %>%
  summarise(mean_total_cost = mean(total_cost, na.rm = TRUE),
            n_denom_years = n(), .groups = "drop")
denom_firm <- bind_rows(denom_primary, denom_fallback)

ets_treatment <- num_firm %>%
  inner_join(denom_firm, by = "vat") %>%
  mutate(firm_cost_share = ifelse(mean_total_cost > 0,
                                  mean_carbon_cost / mean_total_cost,
                                  NA_real_)) %>%
  filter(!is.na(firm_cost_share)) %>%
  select(vat, firm_cost_share)

cat(sprintf("ETS firms with firm_cost_share (2013-2015 window): %d\n",
            nrow(ets_treatment)))
cat("firm_cost_share summary (ETS-only):\n")
print(summary(ets_treatment$firm_cost_share))

# ---- ETS universe ----
ets_vats <- firm_year_belgian_euets %>% distinct(vat) %>% pull(vat)
ets_vats <- setdiff(ets_vats, contaminated_vats)
cat("ETS seller universe:", length(ets_vats), "VATs (excl 3 contaminated)\n")

# ---- Build vat -> sector map (covers ETS + non-ETS sellers) ----
aa_path <- file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData")
if (!file.exists(aa_path)) {
  aa_path <- file.path(PROC_DATA, "annual_accounts_selected_sample.RData")
}
vat_sector_map <- NULL
if (file.exists(aa_path)) {
  loaded_names <- load(aa_path)
  obj_name <- loaded_names[grepl("^df_annual_accounts", loaded_names)][1]
  if (!is.na(obj_name)) {
    aa <- get(obj_name)
    vat_col <- if ("vat" %in% names(aa)) "vat" else if ("vat_ano" %in% names(aa)) "vat_ano" else NA
    if (!is.na(vat_col) && "nace5d" %in% names(aa)) {
      aa <- aa %>% rename(vat = !!sym(vat_col))
      vat_sector_map <- aa %>%
        filter(!is.na(nace5d)) %>%
        select(vat, year, nace5d) %>%
        mutate(seller_nace4d = str_sub(nace5d, 1, 4),
               seller_nace2d = str_sub(nace5d, 1, 2)) %>%
        group_by(vat) %>%
        arrange(desc(year), .by_group = TRUE) %>%
        slice(1) %>% ungroup() %>%
        select(vat, seller_nace4d, seller_nace2d)
      cat("Loaded vat -> sector map from", basename(aa_path),
          ":", nrow(vat_sector_map), "firms\n")
    }
    rm(aa); rm(list = obj_name)
  }
}
if (is.null(vat_sector_map)) {
  stop("No vat -> sector map available; cannot run extended-sample specs.")
}

# ---- Build master pair panel: ALL sellers (ETS + non-ETS) with sector + exposure ----
pairs <- b2b_df %>%
  rename(seller = vat_i_ano, buyer = vat_j_ano, corr_sales = corr_sales_ij) %>%
  filter(year >= year_lo, year <= year_hi,
         !is.na(corr_sales), corr_sales > 0)

pairs_master <- pairs %>%
  left_join(vat_sector_map, by = c("seller" = "vat")) %>%
  filter(!is.na(seller_nace4d)) %>%
  mutate(seller_is_ets = seller %in% ets_vats) %>%
  # drop contaminated ETS VATs (NACE 20/24 outliers)
  filter(!(seller_is_ets & seller %in% contaminated_vats)) %>%
  # attach firm_cost_share: ETS value for ETS sellers, 0 for non-ETS
  left_join(ets_treatment, by = c("seller" = "vat")) %>%
  mutate(firm_cost_share = coalesce(firm_cost_share, 0))

# Drop ETS sellers whose firm_cost_share couldn't be computed (missing in
# ets_treatment). These are ETS firms with no 2013-2015 emissions / no base-
# period total_cost. Treat as excluded rather than assigning 0.
pairs_master <- pairs_master %>%
  filter(!(seller_is_ets & !(seller %in% ets_treatment$vat)))

# Collapse to one row per (seller, buyer, year). b2b_df can contain duplicate
# (seller, buyer, year) tuples (sub-annual rows, multiple product records,
# or sample-construction artifacts). Without this, pivot_wider produces
# list-columns which breaks the event-study diff.
pre_dedup <- nrow(pairs_master)
pairs_master <- pairs_master %>%
  group_by(seller, buyer, year, seller_nace4d, seller_nace2d,
           seller_is_ets, firm_cost_share) %>%
  summarise(corr_sales = sum(corr_sales, na.rm = TRUE), .groups = "drop")
post_dedup <- nrow(pairs_master)
if (post_dedup < pre_dedup) {
  cat(sprintf("Aggregated %d duplicate (seller,buyer,year) rows -> %d unique\n",
              pre_dedup - post_dedup, post_dedup))
}

cat("\n=== Master pair panel ===\n")
cat("rows (seller-buyer-year):", nrow(pairs_master), "\n")
cat("distinct sellers:", n_distinct(pairs_master$seller),
    " (ETS:", sum(pairs_master$seller_is_ets & !duplicated(pairs_master$seller)),
    ", non-ETS:", sum(!pairs_master$seller_is_ets & !duplicated(pairs_master$seller)),
    ")\n")
cat("distinct buyers:", n_distinct(pairs_master$buyer), "\n")
cat("distinct pairs: ", n_distinct(paste(pairs_master$seller, pairs_master$buyer)), "\n")

# ---- Deflate flow (seller's NACE 4d PPI) ----
pairs_master <- pairs_master %>%
  left_join(deflator %>% select(nace4d, year, ppi),
            by = c("seller_nace4d" = "nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("seller_nace2d" = "nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_flow     = corr_sales / ppi * 100,
         log_real_flow = log(real_flow))

# ---- Attach EUA and build Bartik shock (for benchmark specs) ----
pairs_master <- pairs_master %>%
  left_join(eua_prices, by = "year") %>%
  mutate(shock_eua = 100 * firm_cost_share * eua_price)

# ---- Compute share: flow_{j,b,t} / sum_{j' in s(j)} flow_{j',b,t} ----
buyer_sec_year_flow <- pairs_master %>%
  group_by(buyer, seller_nace4d, year) %>%
  summarise(total_sector_flow = sum(corr_sales, na.rm = TRUE), .groups = "drop")

pairs_master <- pairs_master %>%
  left_join(buyer_sec_year_flow,
            by = c("buyer", "seller_nace4d", "year")) %>%
  mutate(share_jbt = corr_sales / total_sector_flow)

# ---- Thickness diagnostics ----
cat("\n=== Sample thickness (all sellers in each seller-NACE4d) ===\n")

pair_counts <- pairs_master %>% group_by(seller, buyer) %>%
  summarise(n_years = n(), .groups = "drop")
cat("Pair-year counts:\n")
cat("  pairs with 1 year:   ", sum(pair_counts$n_years == 1), "\n")
cat("  pairs with 2-3 years:", sum(pair_counts$n_years %in% 2:3), "\n")
cat("  pairs with 4-5 years:", sum(pair_counts$n_years %in% 4:5), "\n")
cat("  pairs with 6+ years: ", sum(pair_counts$n_years >= 6), "\n")
cat("  mean pair-lifespan:  ", round(mean(pair_counts$n_years), 1), "yrs\n")

# Identification: buyer x seller-4d x year cells with mixed ETS / non-ETS
by_buyer_sec_year <- pairs_master %>%
  group_by(buyer, seller_nace4d, year) %>%
  summarise(n_sellers      = n_distinct(seller),
            n_ets_sellers  = n_distinct(seller[seller_is_ets]),
            n_non_ets      = n_distinct(seller[!seller_is_ets]),
            .groups = "drop")

cat("\nIdentification cells (buyer x seller-4d x year):\n")
cat("  total cells                         :", nrow(by_buyer_sec_year), "\n")
cat("  >=2 sellers (any)                   :",
    sum(by_buyer_sec_year$n_sellers >= 2), "\n")
cat("  >=2 sellers AND >=1 ETS             :",
    sum(by_buyer_sec_year$n_sellers >= 2 & by_buyer_sec_year$n_ets_sellers >= 1), "\n")
cat("  >=1 ETS AND >=1 non-ETS (mixed)     :",
    sum(by_buyer_sec_year$n_ets_sellers >= 1 & by_buyer_sec_year$n_non_ets >= 1), "\n")

# ---- Annual-change outcomes (for benchmark specs) ----
pairs_master <- pairs_master %>%
  arrange(seller, buyer, year) %>%
  group_by(seller, buyer) %>%
  mutate(d_log_real_flow = log_real_flow - lag(log_real_flow),
         d_share         = share_jbt    - lag(share_jbt)) %>%
  ungroup()

# =============================================================================
# BENCHMARK specs (Bartik annual-change on full ETS+non-ETS sample)
# =============================================================================
cat("\n\n==============================================================\n")
cat("BENCHMARK: Bartik annual-change specs on ETS+non-ETS sample\n")
cat("(vulnerable to commodity-cycle confound; EUA_t co-moves with oil/gas)\n")
cat("==============================================================\n")

reg_bench_A <- pairs_master %>% filter(!is.na(d_log_real_flow))
m_4A_annual <- feols(d_log_real_flow ~ shock_eua
                     | seller^buyer + buyer^year,
                     cluster = ~ seller + buyer, data = reg_bench_A)
cat("\n--- Spec 4.A-annual ---\n"); print(summary(m_4A_annual))

reg_bench_B <- pairs_master %>% filter(!is.na(d_share))
m_4B_annual <- feols(d_share ~ shock_eua
                     | seller^buyer + buyer^seller_nace4d^year,
                     cluster = ~ seller + buyer, data = reg_bench_B)
cat("\n--- Spec 4.B-annual (within seller-4d-year) ---\n")
print(summary(m_4B_annual))

# =============================================================================
# PRIMARY: event-study long differences around t0 = 2015
# =============================================================================
cat("\n\n==============================================================\n")
cat("PRIMARY: event-study long differences (baseline t0 = 2015)\n")
cat("Horizons h = 1..7 correspond to 2016..2022\n")
cat("Sample: all sellers (ETS + non-ETS) in each seller-NACE4d sector\n")
cat("==============================================================\n")

# Wide panel: flow and share at each year per (seller, buyer)
flow_wide <- pairs_master %>%
  select(seller, buyer, year, log_real_flow, seller_nace4d) %>%
  pivot_wider(id_cols = c(seller, buyer, seller_nace4d),
              names_from = year, names_prefix = "lf_",
              values_from = log_real_flow)

share_wide <- pairs_master %>%
  select(seller, buyer, year, share_jbt, seller_nace4d) %>%
  pivot_wider(id_cols = c(seller, buyer, seller_nace4d),
              names_from = year, names_prefix = "sh_",
              values_from = share_jbt)

# firm_cost_share attachment (seller-level, time-invariant)
seller_exposure <- pairs_master %>%
  distinct(seller, firm_cost_share, seller_is_ets)
flow_wide  <- flow_wide  %>% left_join(seller_exposure, by = "seller")
share_wide <- share_wide %>% left_join(seller_exposure, by = "seller")

run_event_flow <- function(h, wide, t0) {
  yh  <- paste0("lf_", t0 + h)
  y0  <- paste0("lf_", t0)
  if (!all(c(yh, y0) %in% names(wide))) return(NULL)
  dfh <- wide %>%
    mutate(d_log_flow_h = .data[[yh]] - .data[[y0]]) %>%
    filter(!is.na(d_log_flow_h))
  if (nrow(dfh) < 50) return(NULL)
  m <- feols(d_log_flow_h ~ firm_cost_share | buyer^seller_nace4d,
             cluster = ~ seller + buyer, data = dfh)
  list(h = h, n = m$nobs,
       n_pairs = n_distinct(paste(dfh$seller, dfh$buyer)),
       n_ets_pairs  = n_distinct(paste(dfh$seller[dfh$seller_is_ets],
                                       dfh$buyer[dfh$seller_is_ets])),
       beta = coef(m)["firm_cost_share"],
       se   = sqrt(diag(vcov(m)))["firm_cost_share"],
       model = m)
}

run_event_share <- function(h, wide, t0) {
  # Condition on pair active at t0 (sh_t0 non-NA). For pairs that separate
  # between t0 and t0+h (sh_{t0+h} is NA), impute share = 0, which is the
  # correct post-separation share. Avoids survivorship bias that would
  # drop separated pairs and bias beta^h toward zero if high-exposure
  # sellers are more likely to lose buyers.
  yh  <- paste0("sh_", t0 + h)
  y0  <- paste0("sh_", t0)
  if (!all(c(yh, y0) %in% names(wide))) return(NULL)
  dfh <- wide %>%
    filter(!is.na(.data[[y0]])) %>%
    mutate(sh_h_filled = tidyr::replace_na(.data[[yh]], 0),
           d_share_h   = sh_h_filled - .data[[y0]])
  if (nrow(dfh) < 50) return(NULL)
  n_separated <- sum(is.na(dfh[[yh]]))
  m <- feols(d_share_h ~ firm_cost_share | buyer^seller_nace4d,
             cluster = ~ seller + buyer, data = dfh)
  list(h = h, n = m$nobs,
       n_pairs = n_distinct(paste(dfh$seller, dfh$buyer)),
       n_ets_pairs  = n_distinct(paste(dfh$seller[dfh$seller_is_ets],
                                       dfh$buyer[dfh$seller_is_ets])),
       n_separated = n_separated,
       beta = coef(m)["firm_cost_share"],
       se   = sqrt(diag(vcov(m)))["firm_cost_share"],
       model = m)
}

cat("\n--- Spec 4.A-event-h: Delta_h log(flow) ~ firm_cost_share, buyer x seller-4d FE ---\n")
res_4A_event <- lapply(horizons, run_event_flow, wide = flow_wide, t0 = t0_baseline)
for (r in res_4A_event) {
  if (is.null(r)) next
  cat(sprintf("  h=%d: beta=%.5f  se=%.5f  n=%d  pairs=%d (ETS: %d)\n",
              r$h, r$beta, r$se, r$n, r$n_pairs, r$n_ets_pairs))
}

cat("\n--- Spec 4.B-event-h: Delta_h share ~ firm_cost_share, buyer x seller-4d FE ---\n")
cat("    (Pairs active at t0=2015; share imputed to 0 for pairs that separate by t0+h)\n")
res_4B_event <- lapply(horizons, run_event_share, wide = share_wide, t0 = t0_baseline)
for (r in res_4B_event) {
  if (is.null(r)) next
  cat(sprintf("  h=%d: beta=%.5f  se=%.5f  n=%d  pairs=%d (ETS: %d, separated: %d)\n",
              r$h, r$beta, r$se, r$n, r$n_pairs, r$n_ets_pairs, r$n_separated))
}

# =============================================================================
# Extensive margin at horizon h
# =============================================================================
cat("\n\n=== Extensive margin: P(pair active at t0+h | active at t0) ===\n")

active_flags <- pairs_master %>%
  select(seller, buyer, year, seller_nace4d) %>%
  distinct() %>%
  mutate(active = 1L) %>%
  pivot_wider(id_cols = c(seller, buyer, seller_nace4d),
              names_from = year, names_prefix = "act_",
              values_from = active, values_fill = 0L) %>%
  left_join(seller_exposure, by = "seller")

run_event_ext <- function(h, wide, t0) {
  y0 <- paste0("act_", t0); yh <- paste0("act_", t0 + h)
  if (!all(c(y0, yh) %in% names(wide))) return(NULL)
  dfh <- wide %>% filter(.data[[y0]] == 1L) %>%
    mutate(active_h = .data[[yh]])
  if (nrow(dfh) < 50) return(NULL)
  m <- feols(active_h ~ firm_cost_share | buyer^seller_nace4d,
             cluster = ~ seller + buyer, data = dfh)
  list(h = h, n = m$nobs,
       n_pairs = n_distinct(paste(dfh$seller, dfh$buyer)),
       n_ets_pairs  = n_distinct(paste(dfh$seller[dfh$seller_is_ets],
                                       dfh$buyer[dfh$seller_is_ets])),
       beta = coef(m)["firm_cost_share"],
       se   = sqrt(diag(vcov(m)))["firm_cost_share"],
       model = m)
}

res_ext_event <- lapply(horizons, run_event_ext,
                        wide = active_flags, t0 = t0_baseline)
for (r in res_ext_event) {
  if (is.null(r)) next
  cat(sprintf("  h=%d: beta=%.5f  se=%.5f  n=%d  pairs=%d (ETS: %d)\n",
              r$h, r$beta, r$se, r$n, r$n_pairs, r$n_ets_pairs))
}

# =============================================================================
# Output
# =============================================================================
extract_bench <- function(m, label, varname) {
  if (is.null(m)) return(NULL)
  co <- coef(m)[varname]; se <- sqrt(diag(vcov(m)))[varname]
  tibble(spec = label, horizon = NA_integer_, n = m$nobs,
         n_pairs = NA_integer_, n_ets_pairs = NA_integer_,
         beta = co, se = se,
         t = co / se, p = 2 * pt(abs(co / se), df = m$nobs, lower.tail = FALSE))
}

extract_event <- function(r, label_prefix) {
  if (is.null(r)) return(NULL)
  t_val <- r$beta / r$se
  tibble(spec = sprintf("%s h=%d", label_prefix, r$h),
         horizon = r$h, n = r$n,
         n_pairs = r$n_pairs, n_ets_pairs = r$n_ets_pairs,
         beta = r$beta, se = r$se, t = t_val,
         p = 2 * pt(abs(t_val), df = r$n, lower.tail = FALSE))
}

summary_tbl <- bind_rows(
  extract_bench(m_4A_annual, "BENCH: Spec 4.A-annual EUA-Bartik",       "shock_eua"),
  extract_bench(m_4B_annual, "BENCH: Spec 4.B-annual EUA-Bartik w-sec", "shock_eua"),
  bind_rows(lapply(res_4A_event, extract_event,
                   label_prefix = "PRIMARY: Spec 4.A-event firm_cost_share")),
  bind_rows(lapply(res_4B_event, extract_event,
                   label_prefix = "PRIMARY: Spec 4.B-event firm_cost_share")),
  bind_rows(lapply(res_ext_event, extract_event,
                   label_prefix = "Ext. margin firm_cost_share"))
) %>% filter(!is.na(beta))

cat("\n=== Coefficient summary ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 5), se = round(se, 5),
         t = round(t, 2), p = round(p, 3))))

write.csv(summary_tbl %>%
  mutate(across(c(beta, se, t, p), ~round(., 5))),
  file.path(OUTPUT_TAB, "phase4_b2b_supplier_switching.csv"),
  row.names = FALSE)

sink(file.path(OUTPUT_TAB, "phase4_b2b_supplier_switching.txt"))
cat("=== Treatment window ===\n")
cat(sprintf("firm_cost_share: mean_{%d-%d}(shortage*EUA) / mean_{%d-%d}(total_cost) for ETS;\n",
            pre_num_lo, pre_num_hi, pre_denom_lo, pre_denom_hi))
cat("                 = 0 for non-ETS sellers in the B2B network.\n")
cat(sprintf("Event-study baseline t0 = %d; horizons h = %s\n",
            t0_baseline, paste(range(horizons), collapse = "..")))

cat("\n=== Panel composition ===\n")
cat("Master pair panel rows:", nrow(pairs_master), "\n")
cat("Distinct sellers:", n_distinct(pairs_master$seller), "\n")
cat("  of which ETS    :", n_distinct(pairs_master$seller[pairs_master$seller_is_ets]), "\n")
cat("  of which non-ETS:", n_distinct(pairs_master$seller[!pairs_master$seller_is_ets]), "\n")

cat("\n=== Identification thickness ===\n")
cat("buyer x seller-4d x year cells: ", nrow(by_buyer_sec_year), "\n")
cat("  with >=2 sellers any         :",
    sum(by_buyer_sec_year$n_sellers >= 2), "\n")
cat("  with >=1 ETS & >=1 non-ETS   :",
    sum(by_buyer_sec_year$n_ets_sellers >= 1 & by_buyer_sec_year$n_non_ets >= 1), "\n")

cat("\n=== Coefficient table ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 5), se = round(se, 5),
         t = round(t, 2), p = round(p, 3))))
sink()

cat("\nSaved tables to", OUTPUT_TAB, "\n")
cat("\nReady to run on RMD with full B2B + full annual_accounts.\n")
cat("Event-study horizons 1..7 correspond to 2016..2022.\n")

###############################################################################
# phase4_b2b_supplier_switching.R
#
# Angle 4: B2B supplier switching under the EU ETS.
#
# Do buyers reallocate purchases away from high-carbon-exposure ETS suppliers
# as the post-MSR EUA price surge bites? Mirrors Peter-Ruane (2025) and
# Boehm-Levchenko-Pandalai-Nayar (2022) horizon-differentiated designs.
#
# Identification strategy
#   - Pre-period exposure window: 2013-2015 (MSR decided Oct 2015; 2016
#     potentially contaminated by anticipation).
#   - firm_cost_share_j = mean_{2013-15}(shortage * EUA) / mean_{2010-12}(total_cost)
#   - firm_dev_j        = firm_cost_share_j - sector_mean(firm_cost_share) in NACE4d
#   - Baseline year for event-study: t0 = 2015.
#
# Specifications (RMD-only; local-1 B2B is downsampled)
#
#   PRIMARY (event-study long differences around t0 = 2015)
#     Spec 4.B-event-h:
#       share_{j,b,2015+h} - share_{j,b,2015} = beta_h * firm_dev_j
#                                              + alpha_{b, s(j)} + eps
#       Within buyer x seller-NACE4d cell, across ETS sellers with different
#       firm_dev. Absorbs any sector-level confounder in the window (oil, gas,
#       electricity, Belgian cycle). h = 1..7. Analog of Peter-Ruane long
#       difference 1989 -> 1989+h.
#
#     Spec 4.A-event-h:
#       log(flow)_{j,b,2015+h} - log(flow)_{j,b,2015} = beta_h * firm_cost_share_j
#                                                      + alpha_{b, s(j)} + eps
#       Same cross-section at the flow level; uses buyer x seller-NACE4d FE
#       as partial protection against commodity-cycle confound (but identifies
#       off firm_cost_share, not firm_dev).
#
#   BENCHMARK (original Bartik annual-change; vulnerable to commodity-cycle
#   confound because EUA_t co-moves with oil/gas/electricity prices that
#   differentially affect carbon-intensive firms)
#     Spec 4.A-annual: Delta log(flow) ~ (EUA_t x firm_cost_share_j)
#                                        + alpha_{b,t} + alpha_{j,b}
#     Spec 4.B-annual: Delta share     ~ (EUA_t x firm_dev_j)
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
# by 6 disagreement-sign years. Not used in this exercise. See
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
load(file.path(OUT_DATA,  "phase3_firm_exposure.RData"))    # firm_exposure

b2b_df <- df_b2b_selected_sample
rm(df_b2b_selected_sample)

# ---- Rebuild firm treatment on 2013-2015 window ----
# This replaces the 2013-2016 window used in Spec 1.A's phase4_firm_treatment.rds.
# Rationale: MSR was decided Oct 2015; including 2016 risks contaminating the
# pre-period with MSR anticipation. Keep the 2010-2012 denominator unchanged.

num_firm <- firm_exposure %>%
  filter(year >= pre_num_lo, year <= pre_num_hi) %>%
  group_by(vat) %>%
  summarise(
    mean_carbon_cost = mean(carbon_cost, na.rm = TRUE),
    mean_shortage    = mean(shortage,    na.rm = TRUE),
    n_num_years      = sum(!is.na(carbon_cost)),
    .groups = "drop"
  )

denom_primary <- firm_exposure %>%
  filter(year >= pre_denom_lo, year <= pre_denom_hi,
         !is.na(total_cost), total_cost > 0) %>%
  group_by(vat) %>%
  summarise(mean_total_cost = mean(total_cost, na.rm = TRUE),
            n_denom_years   = n(), .groups = "drop")

# Fallback: earliest 3 years of positive total_cost for firms without 2010-12
firms_all <- firm_exposure %>% distinct(vat)
firms_fallback <- anti_join(firms_all, denom_primary, by = "vat") %>% pull(vat)

denom_fallback <- firm_exposure %>%
  filter(vat %in% firms_fallback, !is.na(total_cost), total_cost > 0) %>%
  arrange(vat, year) %>%
  group_by(vat) %>%
  slice_head(n = 3) %>%
  summarise(mean_total_cost = mean(total_cost, na.rm = TRUE),
            n_denom_years   = n(), .groups = "drop")

denom_firm <- bind_rows(denom_primary, denom_fallback)

firm_nace <- firm_exposure %>%
  distinct(vat, nace4d, nace2d) %>%
  group_by(vat) %>% slice(1) %>% ungroup()

firm_treat <- num_firm %>%
  inner_join(denom_firm, by = "vat") %>%
  inner_join(firm_nace,  by = "vat") %>%
  mutate(firm_cost_share = ifelse(mean_total_cost > 0,
                                  mean_carbon_cost / mean_total_cost,
                                  NA_real_)) %>%
  filter(!is.na(firm_cost_share))

firm_treat <- firm_treat %>%
  group_by(nace4d) %>%
  mutate(sector_mean_share = mean(firm_cost_share, na.rm = TRUE),
         firm_dev_share    = firm_cost_share - sector_mean_share,
         n_sector_firms    = n()) %>%
  ungroup()

cat(sprintf("firm_treat (2013-2015 window): %d firms across %d NACE4d sectors\n",
            nrow(firm_treat), n_distinct(firm_treat$nace4d)))
cat("firm_cost_share summary:\n");  print(summary(firm_treat$firm_cost_share))
cat("firm_dev_share summary:\n");   print(summary(firm_treat$firm_dev_share))

# ---- ETS seller universe ----
ets_vats <- firm_year_belgian_euets %>% distinct(vat) %>% pull(vat)
ets_vats <- setdiff(ets_vats, contaminated_vats)
cat("ETS seller universe:", length(ets_vats), "VATs (excl 3 contaminated)\n")

ets_treatment <- firm_treat %>%
  filter(vat %in% ets_vats) %>%
  select(vat, nace4d, nace2d, firm_cost_share, firm_dev_share)
cat("ETS sellers with firm_cost_share:", nrow(ets_treatment), "\n")

# ---- Build pair panel restricted to ETS sellers ----
pairs <- b2b_df %>%
  rename(seller = vat_i_ano, buyer = vat_j_ano, corr_sales = corr_sales_ij) %>%
  filter(year >= year_lo, year <= year_hi,
         !is.na(corr_sales), corr_sales > 0)

pairs_ets <- pairs %>%
  filter(seller %in% ets_vats) %>%
  inner_join(ets_treatment, by = c("seller" = "vat"))

cat("\n=== ETS-seller pair panel ===\n")
cat("rows (seller-buyer-year):", nrow(pairs_ets), "\n")
cat("distinct ETS sellers:", n_distinct(pairs_ets$seller), "\n")
cat("distinct buyers:      ", n_distinct(pairs_ets$buyer), "\n")
cat("distinct pairs:       ",
    n_distinct(paste(pairs_ets$seller, pairs_ets$buyer)), "\n")

# ---- Deflate flow (seller NACE 4d PPI) ----
pairs_ets <- pairs_ets %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_flow     = corr_sales / ppi * 100,
         log_real_flow = log(real_flow))

# ---- Merge EUA price (for benchmark Bartik specs only) ----
pairs_ets <- pairs_ets %>%
  left_join(eua_prices, by = "year") %>%
  mutate(shock_eua = 100 * firm_cost_share * eua_price)

# ---- Thickness diagnostics ----
cat("\n=== Sample thickness (crucial on downsampled local-1 B2B) ===\n")
pair_counts <- pairs_ets %>% group_by(seller, buyer) %>%
  summarise(n_years = n(), .groups = "drop")
cat("Pair-year counts:\n")
cat("  pairs with 1 year:   ", sum(pair_counts$n_years == 1), "\n")
cat("  pairs with 2-3 years:", sum(pair_counts$n_years %in% 2:3), "\n")
cat("  pairs with 4-5 years:", sum(pair_counts$n_years %in% 4:5), "\n")
cat("  pairs with 6+ years: ", sum(pair_counts$n_years >= 6), "\n")
cat("  mean pair-lifespan:  ", round(mean(pair_counts$n_years), 1), "yrs\n")

by_buyer_year <- pairs_ets %>% group_by(buyer, year) %>%
  summarise(n_ets_sellers = n_distinct(seller), .groups = "drop")
cat("Buyer-year cells with >= 2 ETS sellers:",
    sum(by_buyer_year$n_ets_sellers >= 2), "/", nrow(by_buyer_year), "\n")

by_buyer_sec_year <- pairs_ets %>% group_by(buyer, nace4d, year) %>%
  summarise(n_ets_sellers = n_distinct(seller), .groups = "drop")
cat("Buyer x seller-4d x year cells with >= 2 ETS sellers:",
    sum(by_buyer_sec_year$n_ets_sellers >= 2), "/",
    nrow(by_buyer_sec_year), "\n")

# ---- Annual-change outcomes (for benchmark specs) ----
pairs_ets <- pairs_ets %>%
  arrange(seller, buyer, year) %>%
  group_by(seller, buyer) %>%
  mutate(d_log_real_flow = log_real_flow - lag(log_real_flow)) %>%
  ungroup()

# ---- Build vat -> sector map (for share denominator, covering non-ETS too) ----
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
        mutate(nace4d = str_sub(nace5d, 1, 4),
               nace2d = str_sub(nace5d, 1, 2)) %>%
        group_by(vat) %>%
        arrange(desc(year), .by_group = TRUE) %>%
        slice(1) %>%
        ungroup() %>%
        select(vat, seller_nace4d = nace4d, seller_nace2d = nace2d)
      cat("Loaded vat -> sector map from", basename(aa_path),
          ":", nrow(vat_sector_map), "firms\n")
    }
    rm(aa); rm(list = obj_name)
  }
}

spec4b_feasible <- !is.null(vat_sector_map)
if (!spec4b_feasible) {
  warning("No vat -> sector map; Spec 4.B will be skipped.")
}

# ---- Build share panel (Spec 4.B inputs) ----
if (spec4b_feasible) {
  all_pairs <- pairs %>%
    left_join(vat_sector_map, by = c("seller" = "vat")) %>%
    filter(!is.na(seller_nace4d))

  buyer_sec_year_flow <- all_pairs %>%
    group_by(buyer, seller_nace4d, year) %>%
    summarise(total_sector_flow = sum(corr_sales, na.rm = TRUE), .groups = "drop")

  pairs_ets_4b <- pairs_ets %>%
    mutate(seller_nace4d = nace4d) %>%
    left_join(buyer_sec_year_flow, by = c("buyer", "seller_nace4d", "year")) %>%
    mutate(share_jbt = corr_sales / total_sector_flow) %>%
    filter(!is.na(share_jbt))

  pairs_ets_4b <- pairs_ets_4b %>%
    arrange(seller, buyer, year) %>%
    group_by(seller, buyer) %>%
    mutate(d_share = share_jbt - lag(share_jbt)) %>%
    ungroup() %>%
    mutate(shock_eua_dev = 100 * firm_dev_share * eua_price)
}

# =============================================================================
# BENCHMARK specs (original Bartik annual-change; retained for comparison)
# =============================================================================
cat("\n\n==============================================================\n")
cat("BENCHMARK: Bartik annual-change specs\n")
cat("(vulnerable to commodity-cycle confound; EUA_t co-moves with oil/gas)\n")
cat("==============================================================\n")

# -- Spec 4.A-annual --
reg_data <- pairs_ets %>% filter(!is.na(d_log_real_flow))
m_4A_annual <- feols(d_log_real_flow ~ shock_eua | seller^buyer + buyer^year,
                     cluster = ~ seller + buyer, data = reg_data)
cat("\n--- Spec 4.A-annual (EUA-Bartik) ---\n"); print(summary(m_4A_annual))

# -- Spec 4.B-annual --
m_4B_annual <- NULL
if (spec4b_feasible) {
  reg_4b <- pairs_ets_4b %>% filter(!is.na(d_share))
  m_4B_annual <- feols(d_share ~ shock_eua_dev
                       | seller^buyer + buyer^seller_nace4d^year,
                       cluster = ~ seller + buyer, data = reg_4b)
  cat("\n--- Spec 4.B-annual (EUA-Bartik within-sector) ---\n")
  print(summary(m_4B_annual))
}

# =============================================================================
# PRIMARY: event-study long differences around t0 = 2015
# =============================================================================
cat("\n\n==============================================================\n")
cat("PRIMARY: event-study long differences (baseline t0 = 2015)\n")
cat("Horizons h = 1..7 correspond to 2016..2022\n")
cat("==============================================================\n")

# -- Build wide panel: one row per (seller, buyer), columns for each year --
# For Spec 4.A-event: need log_real_flow at t0 and t0+h.
flow_wide <- pairs_ets %>%
  select(seller, buyer, year, log_real_flow, nace4d) %>%
  pivot_wider(id_cols = c(seller, buyer, nace4d),
              names_from = year,
              names_prefix = "lf_",
              values_from = log_real_flow)

# For Spec 4.B-event: need share at t0 and t0+h.
if (spec4b_feasible) {
  share_wide <- pairs_ets_4b %>%
    select(seller, buyer, year, share_jbt, seller_nace4d) %>%
    pivot_wider(id_cols = c(seller, buyer, seller_nace4d),
                names_from = year,
                names_prefix = "sh_",
                values_from = share_jbt)
}

# Attach firm-level regressors
flow_wide <- flow_wide %>%
  left_join(ets_treatment %>% select(vat, firm_cost_share, firm_dev_share),
            by = c("seller" = "vat"))

if (spec4b_feasible) {
  share_wide <- share_wide %>%
    left_join(ets_treatment %>% select(vat, firm_cost_share, firm_dev_share),
              by = c("seller" = "vat"))
}

# -- Run event-study regressions at each horizon --
run_event_flow <- function(h, wide, t0) {
  yh  <- paste0("lf_", t0 + h)
  y0  <- paste0("lf_", t0)
  if (!all(c(yh, y0) %in% names(wide))) return(NULL)
  dfh <- wide %>%
    mutate(d_log_flow_h = .data[[yh]] - .data[[y0]]) %>%
    filter(!is.na(d_log_flow_h))
  if (nrow(dfh) < 50) return(NULL)
  m <- feols(d_log_flow_h ~ firm_cost_share | buyer^nace4d,
             cluster = ~ seller + buyer, data = dfh)
  list(h = h, n = m$nobs,
       n_pairs = n_distinct(paste(dfh$seller, dfh$buyer)),
       beta = coef(m)["firm_cost_share"],
       se   = sqrt(diag(vcov(m)))["firm_cost_share"],
       model = m)
}

run_event_share <- function(h, wide, t0) {
  yh  <- paste0("sh_", t0 + h)
  y0  <- paste0("sh_", t0)
  if (!all(c(yh, y0) %in% names(wide))) return(NULL)
  dfh <- wide %>%
    mutate(d_share_h = .data[[yh]] - .data[[y0]]) %>%
    filter(!is.na(d_share_h))
  if (nrow(dfh) < 50) return(NULL)
  m <- feols(d_share_h ~ firm_dev_share | buyer^seller_nace4d,
             cluster = ~ seller + buyer, data = dfh)
  list(h = h, n = m$nobs,
       n_pairs = n_distinct(paste(dfh$seller, dfh$buyer)),
       beta = coef(m)["firm_dev_share"],
       se   = sqrt(diag(vcov(m)))["firm_dev_share"],
       model = m)
}

cat("\n--- Spec 4.A-event-h: Delta_h log(flow) ~ firm_cost_share, buyer x NACE4d FE ---\n")
res_4A_event <- lapply(horizons, run_event_flow, wide = flow_wide, t0 = t0_baseline)
for (r in res_4A_event) {
  if (is.null(r)) next
  cat(sprintf("  h=%d: beta=%.5f  se=%.5f  n=%d  pairs=%d\n",
              r$h, r$beta, r$se, r$n, r$n_pairs))
}

res_4B_event <- NULL
if (spec4b_feasible) {
  cat("\n--- Spec 4.B-event-h: Delta_h share ~ firm_dev, buyer x seller-NACE4d FE ---\n")
  res_4B_event <- lapply(horizons, run_event_share, wide = share_wide, t0 = t0_baseline)
  for (r in res_4B_event) {
    if (is.null(r)) next
    cat(sprintf("  h=%d: beta=%.5f  se=%.5f  n=%d  pairs=%d\n",
                r$h, r$beta, r$se, r$n, r$n_pairs))
  }
}

# =============================================================================
# Extensive margin at horizon h: P(pair active at t0+h | active at t0)
# =============================================================================
cat("\n\n=== Extensive margin: P(pair active at t0+h | active at t0) ===\n")

# Build indicator: pair (j,b) is active in year y if corr_sales > 0 in that year
active_flags <- pairs_ets %>%
  select(seller, buyer, year, nace4d) %>%
  distinct() %>%
  mutate(active = 1L) %>%
  pivot_wider(id_cols = c(seller, buyer, nace4d),
              names_from = year, names_prefix = "act_",
              values_from = active, values_fill = 0L)

active_flags <- active_flags %>%
  left_join(ets_treatment %>% select(vat, firm_cost_share),
            by = c("seller" = "vat"))

run_event_ext <- function(h, wide, t0) {
  y0 <- paste0("act_", t0)
  yh <- paste0("act_", t0 + h)
  if (!all(c(y0, yh) %in% names(wide))) return(NULL)
  dfh <- wide %>%
    filter(.data[[y0]] == 1L) %>%
    mutate(active_h = .data[[yh]])
  if (nrow(dfh) < 50) return(NULL)
  m <- feols(active_h ~ firm_cost_share | buyer^nace4d,
             cluster = ~ seller + buyer, data = dfh)
  list(h = h, n = m$nobs,
       n_pairs = n_distinct(paste(dfh$seller, dfh$buyer)),
       beta = coef(m)["firm_cost_share"],
       se   = sqrt(diag(vcov(m)))["firm_cost_share"],
       model = m)
}

res_ext_event <- lapply(horizons, run_event_ext,
                        wide = active_flags, t0 = t0_baseline)
for (r in res_ext_event) {
  if (is.null(r)) next
  cat(sprintf("  h=%d: beta=%.5f  se=%.5f  n=%d  pairs=%d\n",
              r$h, r$beta, r$se, r$n, r$n_pairs))
}

# =============================================================================
# Output
# =============================================================================
extract_bench <- function(m, label, varname) {
  if (is.null(m)) return(NULL)
  co <- coef(m)[varname]; se <- sqrt(diag(vcov(m)))[varname]
  tibble(spec = label, horizon = NA_integer_, n = m$nobs,
         beta = co, se = se,
         t = co / se, p = 2 * pt(abs(co / se), df = m$nobs, lower.tail = FALSE))
}

extract_event <- function(r, label_prefix) {
  if (is.null(r)) return(NULL)
  t_val <- r$beta / r$se
  tibble(spec    = sprintf("%s h=%d", label_prefix, r$h),
         horizon = r$h,
         n       = r$n,
         beta    = r$beta,
         se      = r$se,
         t       = t_val,
         p       = 2 * pt(abs(t_val), df = r$n, lower.tail = FALSE))
}

summary_tbl <- bind_rows(
  extract_bench(m_4A_annual, "BENCH: Spec 4.A-annual EUA-Bartik",       "shock_eua"),
  extract_bench(m_4B_annual, "BENCH: Spec 4.B-annual EUA-Bartik w-sec", "shock_eua_dev"),
  bind_rows(lapply(res_4A_event, extract_event,
                   label_prefix = "PRIMARY: Spec 4.A-event firm_cost_share")),
  bind_rows(lapply(res_4B_event, extract_event,
                   label_prefix = "PRIMARY: Spec 4.B-event firm_dev")),
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
cat(sprintf("firm_cost_share: mean_{%d-%d}(shortage*EUA) / mean_{%d-%d}(total_cost)\n",
            pre_num_lo, pre_num_hi, pre_denom_lo, pre_denom_hi))
cat(sprintf("Event-study baseline t0 = %d; horizons h = %s\n",
            t0_baseline, paste(range(horizons), collapse = "..")))
cat(sprintf("firm_treat rows: %d across %d NACE4d sectors\n",
            nrow(firm_treat), n_distinct(firm_treat$nace4d)))

cat("\n=== Panel thickness ===\n")
cat("ETS-seller pair panel rows:", nrow(pairs_ets), "\n")
cat("Pair lifespan distribution:\n")
cat("  1 year:   ", sum(pair_counts$n_years == 1), "\n")
cat("  2-3 years:", sum(pair_counts$n_years %in% 2:3), "\n")
cat("  4-5 years:", sum(pair_counts$n_years %in% 4:5), "\n")
cat("  6+ years: ", sum(pair_counts$n_years >= 6), "\n")
cat("  mean:     ", round(mean(pair_counts$n_years), 1), "\n")

cat("\nBuyer-year cells with >=2 ETS sellers:",
    sum(by_buyer_year$n_ets_sellers >= 2), "/", nrow(by_buyer_year), "\n")
cat("Buyer x 4d x year cells with >=2 ETS sellers:",
    sum(by_buyer_sec_year$n_ets_sellers >= 2), "/",
    nrow(by_buyer_sec_year), "\n")

cat("\n=== Coefficient table ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 5), se = round(se, 5),
         t = round(t, 2), p = round(p, 3))))
sink()

cat("\nSaved tables to", OUTPUT_TAB, "\n")
cat("\nReady to run on RMD with full B2B + full annual_accounts.\n")
cat("Event-study horizons 1..7 correspond to 2016..2022.\n")

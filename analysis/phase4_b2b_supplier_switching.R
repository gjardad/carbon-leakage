###############################################################################
# phase4_b2b_supplier_switching.R
#
# Angle 4 of REALLOCATION_MECHANISM_PLAN: B2B supplier switching.
# Tests whether buyers shift purchases away from more-exposed ETS suppliers
# as the EUA price rises.
#
# Two specs:
#   4.A (flow-level pair panel):
#       Delta log(flow)_{j,b,t,h} = beta * (Signal_t x firm_cost_share_j)
#                                  + alpha_{b,t} + alpha_{j,b} + eps
#     Identified within (buyer, year) cell: across a buyer's ETS suppliers in
#     a given year, do more-exposed suppliers lose flow more?
#
#   4.B (within-seller-sector share):
#       Delta share_{j,b,t,h} = beta * (Signal_t x firm_dev_{j,s(j)})
#                              + alpha_{b,s(j),t} + alpha_{j,b} + eps
#     Identified within (buyer, seller-4d-sector, year) cell: among a buyer's
#     ETS suppliers in the same seller sector in the same year, does share
#     shift from dirty to clean?
#     share_{j,b,t} = flow_{j,b,t} / sum_{j' in s(j)} flow_{j',b,t}
#     (denominator includes non-ETS sellers in the same 4d sector).
#
# Two candidate signals (run both; decide on RMD):
#   - EUA level (Bartik: firm_cost_share_j x EUA_t).
#   - Kanzig annual CPShock (surprise and shock variants). Known to sign-flip
#     at annual frequency; included as robustness only.
#
# Contamination filter: three NACE 20/24 VATs excluded (match aggregate
# pairwise decomposition).
#
# Local-1 note: B2B sample is DOWNSAMPLED on local 1. Pair FE is thin.
# Coefficient estimates on local 1 are for code validation only; deploy to
# RMD for reportable results.
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
year_lo <- 2005L
year_hi <- 2022L

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
firm_treat <- readRDS(file.path(OUT_DATA, "phase4_firm_treatment.rds"))
load(file.path(OUT_DATA, "cpshock_annual.RData"))

# The b2b data frame name:
b2b_df <- df_b2b_selected_sample
rm(df_b2b_selected_sample)

# ---- ETS seller universe ----
# Define an ETS seller as a firm in firm_year_belgian_euets (regardless of
# whether they had emissions > 0 in every year). Contaminated VATs excluded.
ets_vats <- firm_year_belgian_euets %>%
  distinct(vat) %>% pull(vat)

ets_vats <- setdiff(ets_vats, contaminated_vats)
cat("ETS seller universe:", length(ets_vats), "VATs (excl 3 contaminated)\n")

# Firm-level cost share for each ETS seller
ets_treatment <- firm_treat %>%
  filter(vat %in% ets_vats) %>%
  select(vat, nace4d, nace2d, firm_cost_share, firm_dev_share)

cat("ETS sellers with firm_cost_share:", nrow(ets_treatment), "\n")

# ---- Build pair panel restricted to ETS sellers ----
# Rename b2b columns to seller (j) / buyer (b) convention:
# In b2b data, corr_sales_ij = sales from i to j (i.e. i is seller, j is buyer).
pairs <- b2b_df %>%
  rename(seller = vat_i_ano, buyer = vat_j_ano, corr_sales = corr_sales_ij) %>%
  filter(year >= year_lo, year <= year_hi,
         !is.na(corr_sales), corr_sales > 0)

# ---- Build the panel for Spec 4.A: ETS sellers only ----
pairs_ets <- pairs %>%
  filter(seller %in% ets_vats) %>%
  inner_join(ets_treatment, by = c("seller" = "vat"))

cat("\n=== ETS-seller pair panel ===\n")
cat("rows (seller-buyer-year):", nrow(pairs_ets), "\n")
cat("distinct ETS sellers:", n_distinct(pairs_ets$seller), "\n")
cat("distinct buyers:      ", n_distinct(pairs_ets$buyer), "\n")
cat("distinct pairs:       ", n_distinct(paste(pairs_ets$seller, pairs_ets$buyer)), "\n")

# ---- Deflate flow ----
# Use seller's NACE 4d PPI (same as revenue deflation in Spec 1.A)
pairs_ets <- pairs_ets %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = coalesce(ppi, ppi_2d)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_flow = corr_sales / ppi * 100,
         log_real_flow = log(real_flow))

# ---- Merge signals ----
pairs_ets <- pairs_ets %>%
  left_join(eua_prices, by = "year") %>%
  left_join(cpshock_annual %>% select(year, cpshock_surprise, cpshock_shock),
            by = "year") %>%
  mutate(cpshock_surprise = coalesce(cpshock_surprise, 0),
         cpshock_shock    = coalesce(cpshock_shock,    0),
         shock_eua         = 100 * firm_cost_share * eua_price,
         shock_cps_surp    = 100 * firm_cost_share * cpshock_surprise,
         shock_cps_shock   = 100 * firm_cost_share * cpshock_shock)

# ---- Diagnose sample thickness ----
cat("\n=== Sample thickness (crucial on downsampled local-1 B2B) ===\n")

# Pair observation counts
pair_counts <- pairs_ets %>%
  group_by(seller, buyer) %>%
  summarise(n_years = n(), .groups = "drop")

cat("\nPair-year counts:\n")
cat("  pairs with 1 year:   ", sum(pair_counts$n_years == 1), "\n")
cat("  pairs with 2-3 years:", sum(pair_counts$n_years %in% 2:3), "\n")
cat("  pairs with 4-5 years:", sum(pair_counts$n_years %in% 4:5), "\n")
cat("  pairs with 6+ years: ", sum(pair_counts$n_years >= 6), "\n")
cat("  mean pair-lifespan:  ", round(mean(pair_counts$n_years), 1), "years\n")

# Buyer-year cells with multiple ETS sellers (identification for Spec 4.A)
by_buyer_year <- pairs_ets %>%
  group_by(buyer, year) %>%
  summarise(n_ets_sellers = n_distinct(seller), .groups = "drop")

cat("\nBuyer-year cells with >= 2 ETS sellers (Spec 4.A identification):\n")
cat("  total cells with ETS purchases:", nrow(by_buyer_year), "\n")
cat("  with >= 2 ETS sellers:         ",
    sum(by_buyer_year$n_ets_sellers >= 2), "\n")
cat("  with >= 3 ETS sellers:         ",
    sum(by_buyer_year$n_ets_sellers >= 3), "\n")

# Buyer-seller-sector-year cells with multiple ETS sellers (for Spec 4.B)
by_buyer_sec_year <- pairs_ets %>%
  group_by(buyer, nace4d, year) %>%
  summarise(n_ets_sellers = n_distinct(seller), .groups = "drop")

cat("\nBuyer x seller-4d x year cells with >= 2 ETS sellers (Spec 4.B identification):\n")
cat("  total cells:", nrow(by_buyer_sec_year), "\n")
cat("  with >= 2 ETS sellers: ",
    sum(by_buyer_sec_year$n_ets_sellers >= 2), "\n")

# ---- Build first-difference outcome ----
pairs_ets <- pairs_ets %>%
  arrange(seller, buyer, year) %>%
  group_by(seller, buyer) %>%
  mutate(d_log_real_flow = log_real_flow - lag(log_real_flow)) %>%
  ungroup()

cat("\nPair-year observations with non-missing d_log_real_flow:",
    sum(!is.na(pairs_ets$d_log_real_flow)), "\n")

# ---- Build Spec 4.B panel: share among all sellers in same seller-4d sector ----
#
# Need a vat -> nace5d map covering all sellers in the B2B data (ETS + non-ETS).
# On RMD this comes from annual_accounts_selected_sample_key_variables.RData.
# On local 1 the non-ETS map is thinner (downsampled), so Spec 4.B will be less
# informative here; the code still runs either way.
#
# Denominator: sum of flow from ALL sellers in nace4d(j) to buyer b in year t.
# Share:       flow_{j,b,t} / denominator.

spec4b_feasible <- TRUE
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
    # Some vintages use `vat`, others use `vat_ano`. Handle both.
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
    } else {
      warning("annual_accounts file found but missing nace5d or vat/vat_ano: ", aa_path)
    }
    rm(aa); rm(list = obj_name)
  } else {
    warning("No df_annual_accounts_* object in ", aa_path)
  }
} else {
  warning("annual_accounts file not found at ", aa_path)
}

if (is.null(vat_sector_map)) {
  spec4b_feasible <- FALSE
  cat("Spec 4.B will be skipped (no vat -> sector map available).\n")
}

# Build the all-seller pair panel for the denominator, with seller sector
all_pairs <- pairs %>%
  {if (!is.null(vat_sector_map)) left_join(., vat_sector_map, by = c("seller" = "vat"))
   else mutate(., seller_nace4d = NA_character_, seller_nace2d = NA_character_)} %>%
  filter(!is.na(seller_nace4d))

# Buyer-sector-year total flow (denominator for share)
buyer_sec_year_flow <- all_pairs %>%
  group_by(buyer, seller_nace4d, year) %>%
  summarise(total_sector_flow = sum(corr_sales, na.rm = TRUE), .groups = "drop")

cat("\n=== Spec 4.B panel: buyer x seller-4d x year cells ===\n")
cat("rows:", nrow(buyer_sec_year_flow), "\n")
cat("buyer x seller-4d cells with >= 2 distinct sellers (any ETS + non-ETS):",
    all_pairs %>% group_by(buyer, seller_nace4d, year) %>%
      summarise(n_sellers = n_distinct(seller), .groups = "drop") %>%
      filter(n_sellers >= 2) %>% nrow(), "\n")

# Merge total-sector flow onto the ETS-seller panel, compute share
pairs_ets_4b <- pairs_ets %>%
  mutate(seller_nace4d = nace4d) %>%
  left_join(buyer_sec_year_flow, by = c("buyer", "seller_nace4d", "year")) %>%
  mutate(share_jbt = corr_sales / total_sector_flow) %>%
  filter(!is.na(share_jbt))

# First-difference share
pairs_ets_4b <- pairs_ets_4b %>%
  arrange(seller, buyer, year) %>%
  group_by(seller, buyer) %>%
  mutate(d_share = share_jbt - lag(share_jbt)) %>%
  ungroup() %>%
  mutate(shock_eua_dev      = 100 * firm_dev_share * eua_price,
         shock_cps_surp_dev = 100 * firm_dev_share * cpshock_surprise,
         shock_cps_shock_dev= 100 * firm_dev_share * cpshock_shock)

cat("\n=== Spec 4.B feasibility ===\n")
cat("spec4b_feasible:", spec4b_feasible, "\n")
cat("pair-years with d_share non-missing:",
    sum(!is.na(pairs_ets_4b$d_share)), "\n")

# ---- Spec 4.A: Delta log(flow) ~ shock x firm_cost_share, pair + buyer*year FE ----
run_4A <- function(df, signal_var, label) {
  fml <- as.formula(paste0("d_log_real_flow ~ ", signal_var,
                            " | seller^buyer + buyer^year"))
  m <- feols(fml,
             cluster = ~ seller + buyer,
             data = df)
  coefs <- coef(m); ses <- sqrt(diag(vcov(m)))
  varname <- signal_var
  list(label = label, n = m$nobs,
       beta = coefs[varname], se = ses[varname],
       model = m)
}

cat("\n=== Spec 4.A: flow-level pair panel ===\n")

reg_data <- pairs_ets %>% filter(!is.na(d_log_real_flow))

# Three signal variants
m_eua      <- run_4A(reg_data, "shock_eua",       "EUA-Bartik")
m_cps_surp <- run_4A(reg_data, "shock_cps_surp",  "CPShock surprise")
m_cps_shk  <- run_4A(reg_data, "shock_cps_shock", "CPShock shock")

for (m in list(m_eua, m_cps_surp, m_cps_shk)) {
  cat("\n---", m$label, "---\n")
  print(summary(m$model))
}

# ---- Window variants for EUA-Bartik spec ----
cat("\n=== Spec 4.A EUA-Bartik, sample windows ===\n")

run_window <- function(df, lo, hi, label) {
  dfw <- df %>% filter(year >= lo, year <= hi, !is.na(d_log_real_flow))
  if (nrow(dfw) < 100) return(NULL)
  m <- feols(d_log_real_flow ~ shock_eua | seller^buyer + buyer^year,
             cluster = ~ seller + buyer, data = dfw)
  cat("\n--- Window:", label, "| n =", nrow(dfw),
      "| pairs =", n_distinct(paste(dfw$seller, dfw$buyer)), "---\n")
  print(summary(m))
  m
}

m_full   <- run_window(pairs_ets, 2005, 2022, "2005-2022")
m_phase3 <- run_window(pairs_ets, 2013, 2022, "2013-2022")
m_post16 <- run_window(pairs_ets, 2017, 2022, "2017-2022 (post-base)")

# ---- Spec 4.B: within-seller-sector share ----
m_4b_eua      <- m_4b_cps_surp <- m_4b_cps_shock <- NULL
if (spec4b_feasible) {
  cat("\n=== Spec 4.B: within-seller-sector share ===\n")

  reg_4b <- pairs_ets_4b %>% filter(!is.na(d_share))

  # EUA-Bartik
  m_4b_eua <- feols(d_share ~ shock_eua_dev
                    | seller^buyer + buyer^seller_nace4d^year,
                    cluster = ~ seller + buyer, data = reg_4b)
  cat("\n--- Spec 4.B, EUA-Bartik ---\n"); print(summary(m_4b_eua))

  # CPShock surprise
  m_4b_cps_surp <- feols(d_share ~ shock_cps_surp_dev
                         | seller^buyer + buyer^seller_nace4d^year,
                         cluster = ~ seller + buyer, data = reg_4b)
  cat("\n--- Spec 4.B, CPShock surprise ---\n"); print(summary(m_4b_cps_surp))

  # CPShock shock
  m_4b_cps_shock <- feols(d_share ~ shock_cps_shock_dev
                          | seller^buyer + buyer^seller_nace4d^year,
                          cluster = ~ seller + buyer, data = reg_4b)
  cat("\n--- Spec 4.B, CPShock shock ---\n"); print(summary(m_4b_cps_shock))
} else {
  cat("\n=== Spec 4.B skipped (no vat -> sector map available) ===\n")
}

# ---- Extensive margin: relationship continuation LPM ----
cat("\n=== Extensive margin: P(pair active next year | active this year) ===\n")

ext <- pairs_ets %>%
  arrange(seller, buyer, year) %>%
  group_by(seller, buyer) %>%
  mutate(active_next = as.integer(!is.na(lead(year)) & lead(year) == year + 1)) %>%
  ungroup() %>%
  filter(!is.na(active_next))

m_ext_eua <- feols(active_next ~ shock_eua
                   | seller^buyer + buyer^year,
                   cluster = ~ seller + buyer, data = ext)
cat("\n--- Extensive margin, EUA-Bartik ---\n"); print(summary(m_ext_eua))

# ---- Save output ----
extract_beta <- function(m, label, varname = "shock_eua") {
  if (is.null(m)) return(NULL)
  co <- coef(m)[varname]; se <- sqrt(diag(vcov(m)))[varname]
  tibble(spec = label, n = m$nobs, beta = co, se = se,
         t = co / se, p = 2 * pt(abs(co / se), df = m$nobs, lower.tail = FALSE))
}

summary_tbl <- bind_rows(
  extract_beta(m_eua$model,       "Spec 4.A EUA-Bartik, full"),
  extract_beta(m_cps_surp$model,  "Spec 4.A CPShock surprise, full", "shock_cps_surp"),
  extract_beta(m_cps_shk$model,   "Spec 4.A CPShock shock,    full", "shock_cps_shock"),
  extract_beta(m_full,            "Spec 4.A EUA-Bartik, 2005-2022"),
  extract_beta(m_phase3,          "Spec 4.A EUA-Bartik, 2013-2022"),
  extract_beta(m_post16,          "Spec 4.A EUA-Bartik, 2017-2022"),
  extract_beta(m_4b_eua,          "Spec 4.B EUA-Bartik",             "shock_eua_dev"),
  extract_beta(m_4b_cps_surp,     "Spec 4.B CPShock surprise",       "shock_cps_surp_dev"),
  extract_beta(m_4b_cps_shock,    "Spec 4.B CPShock shock",          "shock_cps_shock_dev"),
  extract_beta(m_ext_eua,         "Ext. margin (P active next) EUA-Bartik")
) %>% filter(!is.na(beta))

cat("\n=== Coefficient summary ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 4), se = round(se, 4),
         t = round(t, 2), p = round(p, 3))))

write.csv(summary_tbl %>%
  mutate(across(c(beta, se, t, p), ~round(., 4))),
  file.path(OUTPUT_TAB, "phase4_b2b_supplier_switching.csv"),
  row.names = FALSE)

sink(file.path(OUTPUT_TAB, "phase4_b2b_supplier_switching.txt"))
cat("=== Panel thickness ===\n")
cat("ETS-seller pair panel rows:", nrow(pairs_ets), "\n")
cat("Pair-years with non-missing d_log_real_flow:",
    sum(!is.na(pairs_ets$d_log_real_flow)), "\n\n")

cat("Pair lifespan distribution:\n")
cat("  1 year:   ", sum(pair_counts$n_years == 1), "\n")
cat("  2-3 years:", sum(pair_counts$n_years %in% 2:3), "\n")
cat("  4-5 years:", sum(pair_counts$n_years %in% 4:5), "\n")
cat("  6+ years: ", sum(pair_counts$n_years >= 6), "\n")
cat("  mean:     ", round(mean(pair_counts$n_years), 1), "\n\n")

cat("Buyer-year cells with >=2 ETS sellers:",
    sum(by_buyer_year$n_ets_sellers >= 2), "/", nrow(by_buyer_year), "\n")
cat("Buyer x 4d x year cells with >=2 ETS sellers (Spec 4.B):",
    sum(by_buyer_sec_year$n_ets_sellers >= 2), "/", nrow(by_buyer_sec_year), "\n")

cat("\n=== Spec 4.A coefficient table ===\n")
print(as.data.frame(summary_tbl %>%
  mutate(beta = round(beta, 4), se = round(se, 4),
         t = round(t, 2), p = round(p, 3))))
sink()

cat("\nSaved tables to", OUTPUT_TAB, "\n")
cat("\nAll specs (4.A, 4.B, extensive margin) run end-to-end. On local 1 the\n")
cat("downsampled B2B and downsampled annual accounts make estimates thinner\n")
cat("than on RMD, so results should be validated on the full RMD sample before\n")
cat("reporting.\n")

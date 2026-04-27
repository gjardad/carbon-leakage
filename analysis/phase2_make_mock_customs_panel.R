# phase2_make_mock_customs_panel.R
#
# Generates a small synthetic customs panel that matches the schema of
# customs_import_panel_regulated.dta (the RMD output of
# phase2_build_customs_panel.do). Used to validate the downstream R scripts
# (Figure 2, Table 1, Figure 3) on local 1 before running on RMD.
#
# Output: NBB_data/processed/mock_customs_import_panel_regulated.RData
#
# The mock has REALISTIC SHAPE (firm x CN8 x partner x year) and respects the
# regulated/non-ETS/ETS-firm flags so the regression yields plausible estimates
# (not mechanically positive/negative).

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)
set.seed(20260427L)

# Configuration -- small enough to run fast, large enough to have power.
N_FIRMS         <- 200L      # buyer firms (~10 per RI sector)
N_PARTNERS      <- 30L       # source countries
N_PRODUCTS      <- 60L       # CN8 codes
YEARS           <- 2000:2019
SHARE_REG_PROD  <- 0.5       # fraction of CN8 that are regulated
SHARE_NON_ETS   <- 0.4       # fraction of partners that are non-ETS
SHARE_ETS_FIRM  <- 0.05      # fraction of firms that are ETS-covered
ACTIVE_PROB     <- 0.04      # mean activation rate per (triplet, year)
LEAKAGE_BETA    <- 0.05      # treatment effect: regulated x non-ETS x post-2005

# 1. Build firms.
firms <- data.table(
  vat = sprintf("VAT%05d", seq_len(N_FIRMS)),
  is_ets_firm = as.integer(runif(N_FIRMS) < SHARE_ETS_FIRM)
)

# Assign each firm a buyer NACE 2d from the manufacturing range. Bias toward
# RI sectors (those in our regulated_intensive_nace.csv) since that's the
# build-script filter.
ri <- fread(file.path(REPO_DIR, "data", "io", "regulated_intensive_nace.csv"))
ri[, nace2d := sprintf("%02d", as.integer(nace2d))]
firms[, buyer_nace2d := sample(ri$nace2d, .N, replace = TRUE)]
firms[, nace4d := paste0(buyer_nace2d, sprintf("%02d", sample(1:9, .N, replace = TRUE)))]

# 2. Build partner countries.
ets_dt <- fread(file.path(REPO_DIR, "data", "concordances", "country_ets_status.csv"))
ets_countries <- unique(ets_dt$iso2)[1:20]  # take ~20 ETS country codes
non_ets_pool  <- c("US", "CN", "JP", "KR", "RU", "TR", "BR", "IN", "VN", "MX",
                    "TH", "ID", "MY", "ZA")  # major non-ETS partners
partners <- data.table(
  partner_iso2 = c(sample(ets_countries, 18), sample(non_ets_pool, 12))
)
partners[, is_non_ets_country := as.integer(!partner_iso2 %in% ets_countries)]

# 3. Build CN8 universe (sampled from regulated + unregulated).
reg <- fread(file.path(REPO_DIR, "data", "concordances", "regulated_products_cn8.csv"),
             colClasses = list(character = "cn8"))
reg_pool   <- reg[is_regulated == TRUE, cn8]
unreg_pool <- reg[is_regulated == FALSE, cn8]
n_reg   <- as.integer(N_PRODUCTS * SHARE_REG_PROD)
n_unreg <- N_PRODUCTS - n_reg
products <- data.table(
  cn8 = c(sample(reg_pool, n_reg), sample(unreg_pool, n_unreg)),
  is_regulated_product = c(rep(1L, n_reg), rep(0L, n_unreg))
)

# 4. Pre-existing pairs (firm x cn8 x partner triplets active at least once).
# Random sparse matching: each firm imports ~20% of products from ~30% of partners.
pairs <- CJ(vat = firms$vat,
            cn8 = products$cn8,
            partner_iso2 = partners$partner_iso2)
n_pairs <- nrow(pairs)
keep_idx <- runif(n_pairs) < 0.025  # ~2.5% of all (firm, cn8, partner) triplets ever active
pairs <- pairs[keep_idx]
cat("Active triplets:", nrow(pairs), "\n")

# 5. Expand triplets x years (balanced panel).
panel <- pairs[, .(year = YEARS), by = .(vat, cn8, partner_iso2)]

# 6. Activation: each (triplet, year) has ACTIVE_PROB chance of positive value.
panel[, active := runif(.N) < ACTIVE_PROB]

# 7. Inject the leakage treatment effect: regulated x non-ETS x post-2005 cells
# have higher activation prob.
panel <- merge(panel, products[, .(cn8, is_regulated_product)], by = "cn8")
panel <- merge(panel, partners, by = "partner_iso2")
panel <- merge(panel, firms[, .(vat, buyer_nace2d, nace4d, is_ets_firm)], by = "vat")

panel[, treated := is_regulated_product == 1L & is_non_ets_country == 1L &
        year >= 2005L]
extra_active <- panel$treated & runif(nrow(panel)) < LEAKAGE_BETA
panel[, active := active | extra_active]

# 8. Generate values for active rows.
panel[, value := ifelse(active, exp(rnorm(.N, mean = 8, sd = 1.5)), 0)]

# 9. Tidy.
setcolorder(panel,
            c("vat", "cn8", "partner_iso2", "year", "value",
              "nace4d", "buyer_nace2d",
              "is_regulated_product", "is_non_ets_country", "is_ets_firm"))
panel[, c("active", "treated") := NULL]

cat("Mock panel:\n")
cat("  rows                       :", nrow(panel), "\n")
cat("  rows with value > 0        :", sum(panel$value > 0), "\n")
cat("  distinct firms             :", uniqueN(panel$vat), "\n")
cat("  distinct CN8 products      :", uniqueN(panel$cn8), "\n")
cat("  distinct partner countries :", uniqueN(panel$partner_iso2), "\n")
cat("  years                      :", min(panel$year), "-", max(panel$year), "\n")

out_path <- file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")
save(panel, file = out_path)
cat("\nSaved", out_path, "\n")

# Phase 0 Step 6 -- Build IO-derived sector lists from BE Use table.
#
# Three artifacts:
#   1. regulated_producing_nace.csv -- NACE 2d sectors that produce >=1 regulated CN8.
#   2. regulated_intensive_nace.csv -- downstream NACE 2d sectors with >=10% of
#      intermediate consumption from regulated_producing_nace.
#   3. core_inputs_by_downstream.csv -- for each regulated_intensive_nace sector,
#      the upstream NACE 2d sectors supplying >=10% (and >=5% as robustness) of
#      its intermediate consumption.
#
# Inputs:
#   * NBB_data/raw/Eurostat/naio_10_cp1610__custom_21179157_linear.csv -- BE Use
#     table at basic prices, A*64 industry x CPA product, 2010-2022 (2018 missing).
#   * data/concordances/regulated_products_cn8.csv -- regulated CN8 list.
#   * data/concordances/cn8_to_nace4d.csv -- CN8 -> NACE 4d bridge.
#
# Notes:
#   * BE Use table includes BOTH aggregate codes (C10-12, C13-15, ...) and 2d
#     leaves (C10, C11, ...). We filter to 2d leaves only via regex
#     "^[A-Z][0-9]{2}$" -- e.g., "C24", "B05" -- to avoid double counting.
#   * Manufacturing range for the regulated-intensive filter is NACE C10 - C33.
#   * Anchor year 2015 (or average 2014-2016 for stability). Specified by ANCHOR_YEARS.

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

library(data.table)

use_path    <- file.path(RAW_DATA, "Eurostat",
                         "naio_10_cp1610__custom_21179157_linear.csv")
reg_path    <- file.path(REPO_DIR, "data", "concordances", "regulated_products_cn8.csv")
bridge_path <- file.path(REPO_DIR, "data", "concordances", "cn8_to_nace4d.csv")

out_io_dir  <- file.path(REPO_DIR, "data", "io")
dir.create(out_io_dir, recursive = TRUE, showWarnings = FALSE)
out_producing <- file.path(out_io_dir, "regulated_producing_nace.csv")
out_intensive <- file.path(out_io_dir, "regulated_intensive_nace.csv")
out_core      <- file.path(out_io_dir, "core_inputs_by_downstream.csv")

ANCHOR_YEARS  <- 2014:2016
INTENSITY_THRESHOLD <- 0.10
CORE_THRESHOLDS <- c(0.10, 0.05)

# -------------------------------------------------------------------------
# 1. Regulated-producing NACE 2d (from CN -> NACE bridge).
# -------------------------------------------------------------------------
reg <- fread(reg_path, colClasses = list(character = "cn8"))
bridge <- fread(bridge_path, colClasses = list(character = c("cn8", "nace4d")))
# Defensive: force 4-character zero-padded NACE 4d (handles cases where CSV
# stripped leading zeros like "0510" -> 510). Drop rows where nace4d cannot be
# parsed as a valid 4-digit numeric code.
bridge[, nace4d_int := suppressWarnings(as.integer(nace4d))]
bridge[!is.na(nace4d_int), nace4d := sprintf("%04d", nace4d_int)]
bridge[is.na(nace4d_int), nace4d := NA_character_]
bridge[, nace4d_int := NULL]

reg_cn8 <- reg[is_regulated == TRUE, cn8]
reg_nace4d <- unique(bridge[cn8 %in% reg_cn8 & !is.na(nace4d), nace4d])
reg_nace2d_all <- sort(unique(substr(reg_nace4d, 1, 2)))
# Restrict to goods-producing sections (NACE 2d 01-39 = sections A, B, C, D, E).
reg_nace2d <- reg_nace2d_all[suppressWarnings(as.integer(reg_nace2d_all)) %between% c(1L, 39L)]
cat("Regulated-producing NACE 2d (all):", paste(reg_nace2d_all, collapse = ", "), "\n")
cat("Regulated-producing NACE 2d (goods sections, 01-39):",
    paste(reg_nace2d, collapse = ", "), "\n\n")
cat("Regulated-producing NACE 2d sectors used (", length(reg_nace2d), "):\n", sep = "")

producing_dt <- data.table(
  nace2d = reg_nace2d,
  description = "regulated-producing (>=1 regulated CN8 maps to this NACE 2d)"
)
fwrite(producing_dt, out_producing)

# -------------------------------------------------------------------------
# 2. Reshape Use table to (cpa_product, industry, value), filter leaves only.
# -------------------------------------------------------------------------
ut <- fread(use_path)
ut <- ut[geo == "BE:Belgium" &
         TIME_PERIOD %in% ANCHOR_YEARS &
         unit == "MIO_EUR:Million euro"]

# Strip the ":<Description>" suffix to get bare codes.
ut[, ind_code := sub(":.*", "", ind_use)]
ut[, prd_code := sub(":.*", "", prd_ava)]

# Industry leaves: section letter + 2 digits exactly (excludes C10-12, B-letter
# aggregates, L68A/B, C31_32, etc.). Filter happens BEFORE pulling product rows
# so we know which industries are valid leaves.
ind_leaf <- grepl("^[A-Z][0-9]{2}$", ut$ind_code)
ut_leaf <- ut[ind_leaf]
cat("Industry leaves in Use table (", uniqueN(ut_leaf$ind_code), " distinct):\n", sep = "")
print(sort(unique(ut_leaf$ind_code)))

# CPA product leaves: same form, with CPA_ prefix. Excludes CPA_TOTAL, CPA_C10-12,
# CPA_C31_32, CPA_L68A/B, section letters CPA_B/CPA_D/CPA_F/etc.
ut_prods <- ut_leaf[grepl("^CPA_[A-Z][0-9]{2}$", prd_code)]
ut_prods[, cpa_nace2d := substr(prd_code, 6, 7)]   # CPA_C24 -> 24
cat("\nCPA product leaves (", uniqueN(ut_prods$prd_code), " distinct):\n", sep = "")
print(sort(unique(ut_prods$prd_code)))

# Average across anchor years for stability.
ut_avg <- ut_prods[, .(value = mean(OBS_VALUE, na.rm = TRUE)),
                   by = .(ind_code, prd_code, cpa_nace2d)]

# Total intermediate consumption per industry: take the P2 row directly.
p2 <- ut_leaf[prd_code == "P2", .(p2_total = mean(OBS_VALUE, na.rm = TRUE)), by = ind_code]
cat("\nIndustries with P2 (intermediate consumption) total > 0: ",
    sum(p2$p2_total > 0, na.rm = TRUE), "\n")

# -------------------------------------------------------------------------
# 3. Regulated-intensive NACE: ratio >= 10% of intermediate consumption from
#    regulated_producing CPAs, restricted to manufacturing C10-C33.
# -------------------------------------------------------------------------
ut_avg[, is_reg_input := cpa_nace2d %in% reg_nace2d]
reg_input <- ut_avg[is_reg_input == TRUE,
                    .(reg_intermediate = sum(value, na.rm = TRUE)),
                    by = ind_code]

ratios <- merge(p2, reg_input, by = "ind_code", all.x = TRUE)
ratios[is.na(reg_intermediate), reg_intermediate := 0]
ratios[, ratio := reg_intermediate / p2_total]

# Restrict to manufacturing (C10-C33).
ratios[, sector_letter := substr(ind_code, 1, 1)]
ratios[, sector_2d := as.integer(substr(ind_code, 2, 3))]
ratios[, is_manu := sector_letter == "C" & sector_2d >= 10L & sector_2d <= 33L]

cat("\nManufacturing-sector intermediate-consumption ratios (regulated / total):\n")
print(ratios[is_manu == TRUE, .(ind_code, ratio = round(ratio, 3))][order(-ratio)])

intensive <- ratios[is_manu == TRUE & ratio >= INTENSITY_THRESHOLD]
cat("\nRegulated-intensive NACE 2d (>=10% manufacturing): ", nrow(intensive), "\n")
intensive_dt <- intensive[, .(nace2d = substr(ind_code, 2, 3),
                              ind_code,
                              regulated_share = round(ratio, 4),
                              p2_total_mio_eur = round(p2_total, 1))]
print(intensive_dt[order(-regulated_share)])
fwrite(intensive_dt, out_intensive)

# -------------------------------------------------------------------------
# 4. Core inputs by downstream: per regulated-intensive NACE, identify upstream
#    NACE 2d sectors supplying >=THRESHOLD share of intermediate consumption.
# -------------------------------------------------------------------------
ut_avg <- merge(ut_avg, p2, by = "ind_code")
ut_avg[, share := value / p2_total]

core_rows <- list()
for (thr in CORE_THRESHOLDS) {
  ci <- ut_avg[ind_code %in% intensive$ind_code & share >= thr,
               .(threshold = thr,
                 downstream_ind = ind_code,
                 downstream_nace2d = substr(ind_code, 2, 3),
                 upstream_cpa_nace2d = cpa_nace2d,
                 upstream_share = round(share, 4),
                 value_mio_eur = round(value, 1))]
  core_rows[[as.character(thr)]] <- ci
}
core_dt <- rbindlist(core_rows)
setorder(core_dt, threshold, downstream_ind, -upstream_share)

cat("\nCore inputs (10% threshold, manufacturing downstream):\n")
print(core_dt[threshold == 0.10])

cat("\n--- Summary ---\n")
cat("regulated_producing_nace : ", nrow(producing_dt), " NACE 2d sectors\n", sep = "")
cat("regulated_intensive_nace : ", nrow(intensive_dt), " NACE 2d sectors\n", sep = "")
cat("core_inputs_by_downstream : ",
    nrow(core_dt[threshold == 0.10]), " rows at 10%; ",
    nrow(core_dt[threshold == 0.05]), " rows at 5%\n", sep = "")
fwrite(core_dt, out_core)

cat("\nWrote:\n  ", out_producing, "\n  ", out_intensive, "\n  ", out_core, "\n",
    sep = "")

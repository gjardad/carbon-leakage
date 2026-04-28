###############################################################################
# phase5_diagnostic_panel_fields.R
#
# PURPOSE:
#   Drill down into firm_year_belgian_euets at the field level to localize
#   why phase3_firm_exposure has different cost_share_total NA rates on
#   local-1 vs RMD (78.6% vs 99.4%).
#
#   The constraint we know:
#     - Same 5,339 rows, same 281 firms, same emissions, same allocated_free.
#     - sum(revenue) differs by 0.008% between machines.
#     - RMD panel has 2 extra columns; SHA1 hash differs.
#     - RMD has 805 more firm-years where total_cost <= 0.
#
#   This script reports per-column:
#     - # NAs
#     - # zeros
#     - # negatives
#     - p25/50/75 (for numeric)
#   plus a breakdown of total_cost = NA cases by which input field is
#   missing (revenue, value_added, wage_bill).
#
# OUTPUT:
#   output/tables/phase5_diagnostic_fields.txt
###############################################################################

rm(list = ls())

library(dplyr)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))

dat <- firm_year_belgian_euets

sink(file.path(OUTPUT_TAB, "phase5_diagnostic_fields.txt"))

cat("================================================================\n")
cat("Phase 5 field-level diagnostic of firm_year_belgian_euets\n")
cat(sprintf("User:     %s\n", Sys.info()[["user"]]))
cat(sprintf("Hostname: %s\n", Sys.info()[["nodename"]]))
cat(sprintf("Date:     %s\n", Sys.Date()))
cat("================================================================\n\n")

cat("--- All column names ---\n")
print(names(dat))
cat("\n")

cat(sprintf("Rows: %d\n", nrow(dat)))
cat(sprintf("Distinct vat: %d\n", n_distinct(dat$vat)))
cat(sprintf("in_sample == 1: %d\n", sum(dat$in_sample == 1, na.rm = TRUE)))
cat("\n")

# ---- Per-column profile for numeric fields ----
key_fields <- intersect(c("emissions","allocated_free","revenue","value_added",
                          "wage_bill","capital","fte"),
                        names(dat))

cat("--- Per-column profile for key numeric fields ---\n")
profile <- lapply(key_fields, function(f) {
  x <- dat[[f]]
  data.frame(
    field      = f,
    n_total    = length(x),
    n_NA       = sum(is.na(x)),
    n_zero     = sum(x == 0, na.rm = TRUE),
    n_negative = sum(x < 0, na.rm = TRUE),
    n_positive = sum(x > 0, na.rm = TRUE),
    p25 = round(quantile(x, 0.25, na.rm = TRUE), 2),
    p50 = round(quantile(x, 0.50, na.rm = TRUE), 2),
    p75 = round(quantile(x, 0.75, na.rm = TRUE), 2)
  )
}) %>% bind_rows()

print(profile, row.names = FALSE)
cat("\n")

# ---- Same profile but RESTRICTED to in_sample == 1 ----
cat("--- Per-column profile, RESTRICTED to in_sample == 1 ---\n")
dat_in <- dat %>% filter(in_sample == 1)
profile_in <- lapply(key_fields, function(f) {
  x <- dat_in[[f]]
  data.frame(
    field      = f,
    n_total    = length(x),
    n_NA       = sum(is.na(x)),
    n_zero     = sum(x == 0, na.rm = TRUE),
    n_negative = sum(x < 0, na.rm = TRUE),
    n_positive = sum(x > 0, na.rm = TRUE),
    p25 = round(quantile(x, 0.25, na.rm = TRUE), 2),
    p50 = round(quantile(x, 0.50, na.rm = TRUE), 2),
    p75 = round(quantile(x, 0.75, na.rm = TRUE), 2)
  )
}) %>% bind_rows()

print(profile_in, row.names = FALSE)
cat("\n")

# ---- Compute total_cost as in phase3_build_exposure_panel.R ----
dat_tc <- dat_in %>%
  mutate(mat_inputs = revenue - value_added,
         total_cost = mat_inputs + wage_bill)

cat("--- total_cost diagnostic (in_sample == 1) ---\n")
cat(sprintf("n_in_sample:                       %d\n", nrow(dat_tc)))
cat(sprintf("total_cost is NA:                  %d\n",
            sum(is.na(dat_tc$total_cost))))
cat(sprintf("total_cost <= 0 (and not NA):      %d\n",
            sum(!is.na(dat_tc$total_cost) & dat_tc$total_cost <= 0)))
cat(sprintf("total_cost > 0:                    %d\n",
            sum(!is.na(dat_tc$total_cost) & dat_tc$total_cost > 0)))
cat("\n")

# ---- Decomposition: which input field is responsible for total_cost = NA? ----
cat("--- Why is total_cost NA / non-positive (in_sample == 1)? ---\n")

bad <- dat_tc %>%
  filter(is.na(total_cost) | total_cost <= 0) %>%
  mutate(
    revenue_NA      = is.na(revenue),
    revenue_zero    = !is.na(revenue) & revenue == 0,
    value_added_NA  = is.na(value_added),
    wage_bill_NA    = is.na(wage_bill),
    wage_bill_zero  = !is.na(wage_bill) & wage_bill == 0,
    mat_inputs_neg  = !is.na(revenue) & !is.na(value_added) & (revenue - value_added) < 0,
    total_cost_zero = !is.na(total_cost) & total_cost == 0
  )

cat(sprintf("  total bad rows:                  %d\n", nrow(bad)))
cat(sprintf("  revenue is NA:                   %d\n", sum(bad$revenue_NA)))
cat(sprintf("  revenue == 0 (not NA):           %d\n", sum(bad$revenue_zero)))
cat(sprintf("  value_added is NA:               %d\n", sum(bad$value_added_NA)))
cat(sprintf("  wage_bill is NA:                 %d\n", sum(bad$wage_bill_NA)))
cat(sprintf("  wage_bill == 0 (not NA):         %d\n", sum(bad$wage_bill_zero)))
cat(sprintf("  mat_inputs < 0 (rev-VA negative):%d\n", sum(bad$mat_inputs_neg)))
cat(sprintf("  total_cost == 0 exactly:         %d\n", sum(bad$total_cost_zero)))
cat("\n")

# ---- Year-by-year breakdown of bad rows ----
cat("--- Bad rows by year (in_sample == 1) ---\n")
year_tab <- bad %>%
  count(year) %>%
  rename(n_bad = n) %>%
  arrange(year)
print(as.data.frame(year_tab), row.names = FALSE)
cat("\n")

# ---- Optional: compare two extra columns if present ----
all_cols <- names(dat)
cat("--- All column count: ", length(all_cols), " ---\n")
cat("Looking for any column that exists on this machine but not the expected\n")
cat("set; the user can manually compare across machines.\n")

cat("\n================================================================\n")
cat("Run this on local-1 and RMD, diff the outputs. The 'bad rows by\n")
cat("year' table will show whether the divergence is concentrated in a\n")
cat("specific period (e.g., recent years where annual accounts has more\n")
cat("missing data on one machine than the other).\n")
cat("================================================================\n")

sink()

cat("Saved:", file.path(OUTPUT_TAB, "phase5_diagnostic_fields.txt"), "\n")
cat("Done.\n")

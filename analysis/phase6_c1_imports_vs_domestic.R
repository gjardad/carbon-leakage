# =============================================================================
# C1 (paper §5.2.6) — Imports vs domestic substitution
#
# Tests whether Belgian buyers substitute between imports and domestic
# suppliers as carbon prices rise. The natural specification: at the buyer ×
# upstream-NACE-4d × year level, regress import share on (carbon-cost
# regressor × Post).
#
#   import_share_{b,n,t} = imports_{b,n,t} / (imports_{b,n,t} + domestic_b2b_{b,n,t})
#
# The numerator (imports) comes from the customs panel aggregated to NACE 4d
# via cn8_to_nace4d concordance. The denominator base (domestic B2B) comes
# from the existing B2B panel aggregated by seller_nace4d.
#
# Treatment intensity: nace exposure_n (the regulated-category sales-weighted
# average ETS firm cost share, from the existing Test I construction).
# Equivalent to using regulated_n binary if preferred.
#
# Spec:
#   import_share_{b,n,t} = β · nace_exposure_n × 1[t ≥ 2015]
#                         + α_{b,n} + δ_{n,t} + ε
# Two-way clustering on buyer + NACE 4d.
#
# Outputs:
#   ${OUT_TAB}/phase6_c1_imports_vs_domestic.csv
#   ${OUT_TAB}/phase6_c1_imports_vs_domestic_eventstudy.csv
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest)
})

YEAR_LO <- 2005L; YEAR_HI <- 2022L
ANCHOR  <- 2014L
H_LO <- -9L; H_HI <- +7L
NSHARE_LO <- 2010L; NSHARE_HI <- 2014L

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load customs panel (prefer extended), aggregate to (buyer, NACE 4d, year)
# ---------------------------------------------------------------------------
ext_path <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
if (file.exists(ext_path)) {
  load(ext_path); cat("Using extended customs panel.\n")
} else {
  cat("WARNING: extended panel not found; using 2000-2019 panel.\n")
  load(file.path(PROC_DATA, "customs_import_panel_regulated.RData"))
}
customs <- as.data.table(panel)
# Aggregate to (vat, nace4d, year): sum imports across (cn8, partner_iso2).
customs[, nace4d := substr(nace4d, 1, 4)]
imp_yr <- customs[!is.na(nace4d) & value > 0,
                   .(import_value = sum(value)),
                   by = .(buyer = vat, seller_nace4d = nace4d, year)]

# ---------------------------------------------------------------------------
# 2. Load B2B panel, aggregate to (buyer, seller_nace4d, year)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                  buyer = vat_j_ano,
                                                  year,
                                                  corr_sales = corr_sales_ij)]
rm(df_b2b_selected_sample)
b2b[, year := as.integer(year)]
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(corr_sales) & corr_sales > 0]

load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_more_selected_sample)[
  , .(vat = vat_ano, year, nace5d)]
rm(df_annual_accounts_more_selected_sample)
aa[, year := as.integer(year)]
aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
aa <- unique(aa[, .(vat, year, nace4d)])

seller_nace <- copy(aa); setnames(seller_nace, c("vat", "nace4d"),
                                  c("seller", "seller_nace4d"))
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d)]

dom_yr <- b2b[, .(domestic_value = sum(corr_sales)),
              by = .(buyer, seller_nace4d, year)]

# ---------------------------------------------------------------------------
# 3. Merge and compute import share
# ---------------------------------------------------------------------------
panel_c1 <- merge(dom_yr, imp_yr, by = c("buyer", "seller_nace4d", "year"),
                   all = TRUE)
panel_c1[is.na(domestic_value), domestic_value := 0]
panel_c1[is.na(import_value), import_value := 0]
panel_c1[, total := domestic_value + import_value]
panel_c1 <- panel_c1[total > 0]
panel_c1[, import_share := import_value / total]

# Restrict to (buyer × NACE 4d) cells with positive imports AND positive
# domestic in some pre-shock year (substitution feasibility).
fb <- panel_c1[year %between% c(NSHARE_LO, NSHARE_HI),
                .(any_imp = any(import_value > 0),
                  any_dom = any(domestic_value > 0)),
                by = .(buyer, seller_nace4d)]
feasible <- fb[any_imp & any_dom, .(buyer, seller_nace4d)]
panel_c1 <- merge(panel_c1, feasible, by = c("buyer", "seller_nace4d"))
cat(sprintf("C1 sample: %d cell-years, %d cells\n",
            nrow(panel_c1), uniqueN(panel_c1[, .(buyer, seller_nace4d)])))

# ---------------------------------------------------------------------------
# 4. Build nace_exposure (mirrors Test I)
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))

# Per Test I construction: sales-weighted avg fcs in NACE 4d.
b2b_pre <- b2b[year %between% c(NSHARE_LO, NSHARE_HI)]
b2b_pre <- merge(b2b_pre,
                  cost_share_regressor[, .(seller = vat,
                                            fcs_reg = firm_cost_share_regressor)],
                  by = "seller", all.x = TRUE)
b2b_pre[is.na(fcs_reg), fcs_reg := 0]

nace_exp <- b2b_pre[seller_nace4d %in% unique(seller_nace[, seller_nace4d]),
                     .(numer = sum(corr_sales * fcs_reg),
                       denom = sum(corr_sales)),
                     by = seller_nace4d]
nace_exp[, nace_exposure := numer / denom]
nace_exp[is.na(nace_exposure), nace_exposure := 0]

panel_c1 <- merge(panel_c1, nace_exp[, .(seller_nace4d, nace_exposure)],
                   by = "seller_nace4d", all.x = TRUE)
panel_c1[is.na(nace_exposure), nace_exposure := 0]
panel_c1[, regulated_n := as.integer(nace_exposure > 0)]
panel_c1[, post := as.integer(year >= 2015L)]

# ---------------------------------------------------------------------------
# 5. C1 main spec
# ---------------------------------------------------------------------------
m_c1 <- tryCatch(
  feols(import_share ~ regulated_n:post | buyer^seller_nace4d + buyer^year,
        data = panel_c1, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })
if (!is.null(m_c1)) {
  ct <- as.data.table(coeftable(m_c1), keep.rownames = "term")
  setnames(ct, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct, file.path(OUT_TAB, "phase6_c1_imports_vs_domestic.csv"))
  cat("C1 binary spec:\n"); print(ct[, .(est, se, pval)])
}

# Continuous treatment.
m_c1c <- tryCatch(
  feols(import_share ~ nace_exposure:post | buyer^seller_nace4d + buyer^year,
        data = panel_c1, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_c1c)) {
  ct2 <- as.data.table(coeftable(m_c1c), keep.rownames = "term")
  setnames(ct2, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  cat("\nC1 continuous spec:\n"); print(ct2[, .(est, se, pval)])
}

# Event study.
panel_c1[, year_f := factor(year, levels = (ANCHOR + H_LO):(ANCHOR + H_HI))]
m_c1_es <- tryCatch(
  feols(import_share ~ i(year_f, regulated_n, ref = as.character(ANCHOR - 1L)) |
                        buyer^seller_nace4d + buyer^year,
        data = panel_c1, cluster = c("buyer", "seller_nace4d"), notes = FALSE),
  error = function(e) NULL)
if (!is.null(m_c1_es)) {
  ct3 <- as.data.table(coeftable(m_c1_es), keep.rownames = "term")
  ct3[, year := suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", term)))]
  ct3[, h := year - ANCHOR]
  setnames(ct3, c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
           c("est", "se", "tval", "pval"))
  fwrite(ct3[!is.na(h), .(h, est, se, tval, pval)],
         file.path(OUT_TAB, "phase6_c1_imports_vs_domestic_eventstudy.csv"))
}

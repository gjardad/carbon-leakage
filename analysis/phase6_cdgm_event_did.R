# =============================================================================
# phase6_cdgm_event_did.R
#
# MAIN-TEXT international-margin table: single-event difference-in-differences,
# matching the event-time treatment definition of the domestic within-NACE4d
# table (eq. within_intensive / tab:phase4_within_intensive_did_coefs), which
# uses 1[treated] x 1[t >= 2017] for the MSR event. We apply the same timing to
# the regulated-vs-unregulated import margin, plus a 2005 (ETS-introduction)
# version mirroring CdGM's main exercise.
#
# The exact phase-aggregated CdGM replication (Phase 1/2/3/IV bins) lives in
# phase6_cdgm_table1_postmsr.R and moves to the appendix.
#
# Spec:  y_{f,p,i,t} = beta * 1[regulated]_p * 1[t >= T*]
#                      + alpha_{f,p,i} + delta_{i,t} + delta_{s,t} + e
#   T* in {2017 (MSR), 2005 (ETS)};  outcomes: import share, sourcing prob.
#   Sample: non-ETS source countries, EXCLUDING Switzerland (consignment
#           artifact). Two-way clustered on firm and country. Preferred FE col(5).
#
# Output (tracked; output_*/tables/*.tex is NOT gitignored):
#   tables/phase6_cdgm_event_did.tex   -- 4 cols: share x {MSR, ETS}, prob x {MSR, ETS}
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE))
  install.packages("fixest", repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(fixest) })

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load panel (prefer 2000-2022 extended; fall back as in the other scripts).
# ---------------------------------------------------------------------------
ext_rdata <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_dta   <- file.path(PROC_DATA, "customs_import_panel_regulated.dta")
reg_rdata <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
mock_path <- file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")

USE_MOCK <- FALSE; USING_EXTENDED <- FALSE
if (file.exists(ext_rdata)) {
  cat("USING EXTENDED CUSTOMS PANEL (2000-2022).\n"); load(ext_rdata); d <- as.data.table(panel); USING_EXTENDED <- TRUE
} else if (file.exists(reg_dta)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, dta).\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(reg_dta))
} else if (file.exists(reg_rdata)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, RData).\n"); load(reg_rdata); d <- as.data.table(panel)
} else {
  cat("USING MOCK CUSTOMS PANEL.\n"); USE_MOCK <- TRUE; load(mock_path); d <- as.data.table(panel)
}

# CdGM-EXACT sample: non-ETS source countries.
d <- d[is_non_ets_country == 1L]
# Drop Switzerland (trading-hub consignment invoicing artifact; see
# phase6_cdgm_intrastat_break_diagnostic.R and the paper footnote).
d <- d[partner_iso2 != "CH"]
d <- d[year >= 2000L]
cat("Sample rows (non-ETS, ex-CH):", nrow(d), " years:", min(d$year), "-", max(d$year), "\n")

# ---------------------------------------------------------------------------
# 2. Outcomes + FE ids (identical to the CdGM scripts).
# ---------------------------------------------------------------------------
d[, total_value_ft := sum(value), by = .(vat, year)]
d[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
d[, prob_active := as.integer(value > 0)]

d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year      := paste(partner_iso2, year, sep = "_")]
d[, sector_year       := paste(buyer_nace2d, year, sep = "_")]

fe5 <- "firm_prod_country + country_year + sector_year"

# ---------------------------------------------------------------------------
# 3. Single-event DiD. Reassign treat_post per event so all four models carry a
#    coefficient named `treat_post` (one tidy row), with the event flagged below.
# ---------------------------------------------------------------------------
fit_event <- function(outcome, tstar) {
  d[, treat_post := is_regulated_product * as.integer(year >= tstar)]
  feols(as.formula(sprintf("%s ~ treat_post | %s", outcome, fe5)),
        data = d, cluster = ~ vat + partner_iso2)
}

m_s17 <- fit_event("share",       2017L)
m_s05 <- fit_event("share",       2005L)
m_p17 <- fit_event("prob_active", 2017L)
m_p05 <- fit_event("prob_active", 2005L)

# ---------------------------------------------------------------------------
# 4. LaTeX table (house style via etable).
# ---------------------------------------------------------------------------
tex_dict <- c(
  treat_post        = "Regulated $\\times$ post-event",
  firm_prod_country = "Firm $\\times$ product $\\times$ country",
  country_year      = "Country $\\times$ year",
  sector_year       = "Sector $\\times$ year",
  share             = "Import share",
  prob_active       = "Sourcing prob."
)

mock_tag <- if (USE_MOCK) "_MOCK" else if (!USING_EXTENDED) "_NOEXT" else ""
out_tex  <- file.path(OUT_TAB, sprintf("phase6_cdgm_event_did%s.tex", mock_tag))

tryCatch({
  etable(m_s17, m_s05, m_p17, m_p05,
         tex = TRUE, file = out_tex, replace = TRUE,
         title = paste("Belgian import switching, single-event difference-in-differences.",
                       "The regulated $\\times$ post interaction is dated at the 2017 Market",
                       "Stability Reserve (columns 1, 3), matching the event-time treatment of",
                       "the domestic test, and at the 2005 ETS introduction (columns 2, 4),",
                       "mirroring \\citet{CosterMejeanDiGiovanni2024}'s main exercise. Columns",
                       "(1)--(2): import share; (3)--(4): probability of sourcing. Preferred",
                       "fixed effects throughout; two-way clustered on firm and country.",
                       "Switzerland excluded. France benchmark: $+0.121$."),
         label = "tab:cdgm_event_did", dict = tex_dict, fitstat = ~ n,
         extralines = list("Event" = c("MSR (2017)", "ETS (2005)", "MSR (2017)", "ETS (2005)")),
         digits = "r4")
  cat("LaTeX table saved:", out_tex, "\n")
}, error = function(e)
  cat("WARNING: etable failed:", conditionMessage(e), "\n"))

# ---------------------------------------------------------------------------
# 5. Console headline.
# ---------------------------------------------------------------------------
stars <- function(p) ifelse(is.na(p), "", ifelse(p < .001, "***", ifelse(p < .01, "**",
                     ifelse(p < .05, "*", ifelse(p < .1, ".", "")))))
key <- function(m, lab) {
  ct <- as.data.table(summary(m)$coeftable);
  cat(sprintf("  %-22s b=%+.5f  se=%.5f  p=%.4f %s\n", lab,
              ct[[1]][1], ct[[2]][1], ct[[4]][1], stars(ct[[4]][1])))
}
cat("\n===== Single-event DiD (regulated x post), ex-CH =====\n")
key(m_s17, "share, MSR 2017");  key(m_s05, "share, ETS 2005")
key(m_p17, "prob,  MSR 2017");  key(m_p05, "prob,  ETS 2005")
cat("France benchmark (CdGM Phase 3 share): +0.121.\n")

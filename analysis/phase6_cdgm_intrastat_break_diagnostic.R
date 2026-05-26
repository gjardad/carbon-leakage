# =============================================================================
# phase6_cdgm_intrastat_break_diagnostic.R
#
# Is the post-2015 jump in the non-ETS import share of UNREGULATED products
# (visible in phase2_cdgm_figure2) an Intrastat reporting-threshold artifact?
#
# Hypothesis: Belgium's Intrastat ARRIVALS threshold rose at 2016. Intra-EU
# (ETS-bloc) arrivals below the threshold are reported via Intrastat and get
# truncated; extra-EU (non-ETS) imports come via Extrastat with NO threshold.
# A threshold increase therefore drops small intra-EU flows from 2016 onward,
# mechanically inflating the extra-EU (non-ETS) share -- and it bites
# unregulated goods (smaller, threshold-sensitive) far more than regulated
# goods (metals/chemicals, high-value, reported regardless).
#
# Truncation leaves a fingerprint IN THE PANEL, independent of the official
# threshold number. All three should appear at exactly 2016:
#   (1) ETS-bloc value drops discretely at 2016 (denominator collapse), while
#       extra-EU (non-ETS) value is smooth -- so the share jump is NOT a
#       non-ETS surge.
#   (2) Count of active ETS-bloc flows and of reporting firms falls at 2016.
#   (3) The drop is concentrated in LOW-VALUE shipments (the sub-threshold
#       tail disappears; large flows are unaffected).
# If these show up for unregulated and not (or much less) for regulated, the
# threshold-truncation story is confirmed. If they don't, it is refuted.
#
# Bloc split uses is_ets_country_ever (time-invariant), matching
# phase2_cdgm_figure2.R, so this directly explains that figure. (Caveat: the
# ETS-ever bloc includes EEA-EFTA, which is extra-EU for Intrastat; it is a
# close proxy for intra-EU, not exact.)
#
# Outputs (per paths.R: output_local/ or output_rmd/):
#   figures/phase6_intrastat_break_diagnostic.png   (trackable)
#   tables/phase6_intrastat_break_summary.txt        (trackable)
#   tables/phase6_intrastat_break_decomp.csv         (gitignored; full detail)
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("ggplot2",   quietly = TRUE)) install.packages("ggplot2",   repos = "https://cloud.r-project.org")
if (!requireNamespace("patchwork", quietly = TRUE)) install.packages("patchwork", repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({
  library(data.table); library(ggplot2); library(patchwork)
})

OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load panel (prefer the 2000-2022 extended panel; fall back as in figure2).
# ---------------------------------------------------------------------------
ext_rdata <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_dta   <- file.path(PROC_DATA, "customs_import_panel_regulated.dta")
reg_rdata <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
mock_path <- file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")

USE_MOCK <- FALSE
if (file.exists(ext_rdata)) {
  cat("USING EXTENDED CUSTOMS PANEL (2000-2022).\n"); load(ext_rdata); d <- as.data.table(panel)
} else if (file.exists(reg_dta)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, dta).\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(reg_dta))
} else if (file.exists(reg_rdata)) {
  cat("WARNING: extended panel not found; using CdGM-window panel (2000-2019, RData).\n"); load(reg_rdata); d <- as.data.table(panel)
} else {
  cat("USING MOCK CUSTOMS PANEL.\n"); USE_MOCK <- TRUE; load(mock_path); d <- as.data.table(panel)
}
cat("Panel rows:", nrow(d), " years:", min(d$year), "-", max(d$year), "\n")

# ---------------------------------------------------------------------------
# 2. Bloc split (time-invariant is_ets_country_ever, matching figure2).
# ---------------------------------------------------------------------------
ets_status <- fread(file.path(REPO_DIR, "data", "concordances", "country_ets_status.csv"),
                    select = c("iso2", "year", "is_ets_country_ever"))
setnames(ets_status, "iso2", "partner_iso2")
d <- merge(d, ets_status, by = c("partner_iso2", "year"), all.x = TRUE)
d[is.na(is_ets_country_ever), is_ets_country_ever := FALSE]
d[, bloc := fifelse(is_ets_country_ever, "ETS-bloc (intra-EU)", "non-ETS (extra-EU)")]
d[, regulated := fifelse(is_regulated_product == 1L, "Regulated", "Unregulated")]

# ---------------------------------------------------------------------------
# 3. Core decomposition: value, active-flow count, reporting firms by year.
# ---------------------------------------------------------------------------
decomp <- d[, .(value      = sum(value),
                n_flows    = sum(value > 0),
                n_firms    = uniqueN(vat[value > 0])),
            by = .(year, regulated, bloc)]
setorder(decomp, regulated, bloc, year)

# Non-ETS share within regulation status (reproduces the figure's jump).
share <- dcast(decomp, year + regulated ~ bloc, value.var = "value")
setnames(share, make.names(names(share)))
nonets_col <- grep("non.ETS", names(share), value = TRUE)[1]
ets_col    <- grep("ETS.bloc", names(share), value = TRUE)[1]
share[, nonETS_share := get(nonets_col) / (get(nonets_col) + get(ets_col))]

# ---------------------------------------------------------------------------
# 4. Size distribution: where do flows sit, and does the small tail collapse?
# ---------------------------------------------------------------------------
da <- d[value > 0]
da[, vbin := cut(value, breaks = c(0, 1e3, 1e4, 1e5, 1e6, Inf),
                 labels = c("<1k", "1-10k", "10-100k", "100k-1M", ">1M"),
                 right = FALSE)]
size <- da[, .(n = .N), by = .(year, regulated, bloc, vbin)]

# ---------------------------------------------------------------------------
# 4b. Value vs QUANTITY -- decisive for "is the extra-EU surge real volume or
#     a price / value-recording effect?". Quantity exists only on the extended
#     panel; the 2000-2019 CdGM panel has no quantity column.
# ---------------------------------------------------------------------------
HAS_QTY <- "quantity" %in% names(d) && any(d$quantity[!is.na(d$quantity)] > 0)
if (HAS_QTY) {
  qd <- d[value > 0 & !is.na(quantity) & quantity > 0,
          .(value = sum(value), qty_kg = sum(quantity)),
          by = .(year, regulated, bloc)]
  qd[, unit_value := value / qty_kg]
}

# ---------------------------------------------------------------------------
# 4c. Which extra-EU partner countries drive the UNREGULATED value surge?
# ---------------------------------------------------------------------------
ctry <- d[is_ets_country_ever == FALSE & regulated == "Unregulated" & value > 0,
          .(value = sum(value)), by = .(year, partner_iso2)]
top_partners <- ctry[year %between% c(2016L, 2018L), .(v = sum(value)),
                     by = partner_iso2][order(-v)][seq_len(min(12L, .N)), partner_iso2]
ctry_top <- dcast(ctry[partner_iso2 %in% top_partners],
                  partner_iso2 ~ year, value.var = "value", fun.aggregate = sum)

# Partner-level value vs quantity (extended panel only) -- the decisive
# invoicing test: surging VALUE with flat/low KG (rising EUR/kg) = goods
# invoiced through a trading hub, not produced there.
if (HAS_QTY) {
  pq <- d[is_ets_country_ever == FALSE & regulated == "Unregulated" &
            partner_iso2 %in% top_partners & value > 0 &
            !is.na(quantity) & quantity > 0,
          .(value = sum(value), qty_kg = sum(quantity)), by = .(year, partner_iso2)]
  pq[, unit_value := value / qty_kg]
}

# ---------------------------------------------------------------------------
# 5. Console: the decisive table -- UNREGULATED, by year x bloc.
# ---------------------------------------------------------------------------
cat("\n================ UNREGULATED: value / flows / firms by bloc ================\n")
u <- decomp[regulated == "Unregulated"]
u[, value_m := round(value / 1e6, 1)]
print(dcast(u, year ~ bloc, value.var = "value_m"), nrows = 50)
cat("\n-- active flow counts --\n")
print(dcast(u, year ~ bloc, value.var = "n_flows"), nrows = 50)
cat("\n-- reporting firms --\n")
print(dcast(u, year ~ bloc, value.var = "n_firms"), nrows = 50)
cat("\n-- non-ETS value share within product class (reproduces the figure) --\n")
print(dcast(share, year ~ regulated, value.var = "nonETS_share"), nrows = 50)

cat("\n================ ETS-bloc UNREGULATED size distribution (flow counts) =======\n")
cat("Watch the small bins (<1k, 1-10k, 10-100k) across 2015->2016:\n")
sz <- size[regulated == "Unregulated" & grepl("ETS.bloc|ETS-bloc", bloc)]
print(dcast(sz, year ~ vbin, value.var = "n", fill = 0), nrows = 50)

if (HAS_QTY) {
  cat("\n================ Value vs QUANTITY, UNREGULATED by bloc ================\n")
  cat("-- quantity (kg) --\n")
  print(dcast(qd[regulated == "Unregulated"], year ~ bloc, value.var = "qty_kg"), nrows = 50)
  cat("-- unit value (EUR/kg) --\n")
  print(dcast(qd[regulated == "Unregulated"], year ~ bloc, value.var = "unit_value"), nrows = 50)
  cat("If extra-EU VALUE surges but QUANTITY is flat => price / value-recording, not real volume.\n")
} else {
  cat("\n(No quantity column on this panel -- the value-vs-quantity test is RMD-only.)\n")
}

cat("\n================ Top extra-EU partners, UNREGULATED value (EUR) =============\n")
cat("Who drives the surge? Broad => globalization; one country => reclassification.\n")
print(ctry_top, nrows = 20)

if (HAS_QTY) {
  cat("\n========= Top extra-EU partners: value vs quantity (invoicing test) =========\n")
  cat("-- value (EUR) --\n");        print(dcast(pq, year ~ partner_iso2, value.var = "value"), nrows = 30)
  cat("-- quantity (kg) --\n");       print(dcast(pq, year ~ partner_iso2, value.var = "qty_kg"), nrows = 30)
  cat("-- unit value (EUR/kg) --\n"); print(dcast(pq, year ~ partner_iso2, value.var = "unit_value"), nrows = 30)
  cat("Surging value + flat kg + rising EUR/kg (esp. CH) => trading-hub invoicing, not real production.\n")
}

cat("\nINTERPRETATION: truncation => at 2016 the ETS-bloc UNREGULATED value,\n",
    "flow count, firm count, and the small-value bins drop discretely, while\n",
    "non-ETS (extra-EU) is smooth, and regulated is much less affected.\n")

# ---------------------------------------------------------------------------
# 6. Figure: value + active flows, ETS vs non-ETS, faceted by regulation.
# ---------------------------------------------------------------------------
mk <- function(dt, yvar, ylab, title) {
  ggplot(dt, aes(x = year, y = get(yvar), color = bloc)) +
    geom_vline(xintercept = 2015.5, linetype = "dashed", color = "grey40") +
    annotate("text", x = 2015.6, y = Inf, label = "2016 Intrastat?",
             hjust = 0, vjust = 1.4, size = 3, color = "grey40") +
    geom_line(linewidth = 0.9) + geom_point(size = 1.4) +
    facet_wrap(~ regulated, scales = "free_y") +
    scale_color_manual(values = c("ETS-bloc (intra-EU)" = "steelblue",
                                  "non-ETS (extra-EU)"  = "firebrick")) +
    labs(title = title, x = NULL, y = ylab, color = NULL) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom")
}
p_val   <- mk(decomp, "value",   "Import value (EUR)",  "(a) Import value by bloc")
p_flow  <- mk(decomp, "n_flows", "Active flows",        "(b) Active (firm x product x country) flows by bloc")
combined <- (p_val / p_flow) +
  plot_annotation(title = "Intrastat-break diagnostic: does the ETS-bloc tail collapse at 2016?",
                  subtitle = sprintf("Belgian customs panel%s, %d-%d. Dashed line = 2015/16 boundary.",
                                     ifelse(USE_MOCK, " (MOCK)", ""), min(d$year), max(d$year)))

out_fig <- file.path(OUT_FIG, sprintf("phase6_intrastat_break_diagnostic%s.png",
                                      if (USE_MOCK) "_MOCK" else ""))
ggsave(out_fig, combined, width = 10, height = 8, dpi = 200)
cat("\nFigure saved:", out_fig, "\n")

# ---------------------------------------------------------------------------
# 7. Save a trackable .txt summary + the full .csv (gitignored).
# ---------------------------------------------------------------------------
out_txt <- file.path(OUT_TAB, sprintf("phase6_intrastat_break_summary%s.txt",
                                      if (USE_MOCK) "_MOCK" else ""))
sink(out_txt)
cat("Intrastat-break diagnostic --", format(Sys.time()), "\n")
cat("Panel:", min(d$year), "-", max(d$year), "rows:", nrow(d), "\n\n")
cat("UNREGULATED value (EUR m) by year x bloc:\n");  print(dcast(u, year ~ bloc, value.var = "value_m"))
cat("\nUNREGULATED active flows by year x bloc:\n");  print(dcast(u, year ~ bloc, value.var = "n_flows"))
cat("\nUNREGULATED reporting firms by year x bloc:\n"); print(dcast(u, year ~ bloc, value.var = "n_firms"))
cat("\nNon-ETS value share within product class:\n");  print(dcast(share, year ~ regulated, value.var = "nonETS_share"))
cat("\nETS-bloc UNREGULATED size-bin flow counts:\n");  print(dcast(sz, year ~ vbin, value.var = "n", fill = 0))
if (HAS_QTY) {
  cat("\nUNREGULATED quantity (kg) by bloc:\n");        print(dcast(qd[regulated == "Unregulated"], year ~ bloc, value.var = "qty_kg"))
  cat("\nUNREGULATED unit value (EUR/kg) by bloc:\n");  print(dcast(qd[regulated == "Unregulated"], year ~ bloc, value.var = "unit_value"))
}
cat("\nTop extra-EU partners, UNREGULATED value (EUR):\n"); print(ctry_top)
if (HAS_QTY) {
  cat("\nTop partners value (EUR):\n");      print(dcast(pq, year ~ partner_iso2, value.var = "value"))
  cat("\nTop partners quantity (kg):\n");     print(dcast(pq, year ~ partner_iso2, value.var = "qty_kg"))
  cat("\nTop partners unit value (EUR/kg):\n"); print(dcast(pq, year ~ partner_iso2, value.var = "unit_value"))
}
sink()
cat("Summary saved:", out_txt, "\n")

out_csv <- file.path(OUT_TAB, sprintf("phase6_intrastat_break_decomp%s.csv",
                                      if (USE_MOCK) "_MOCK" else ""))
fwrite(merge(decomp, share[, .(year, regulated, nonETS_share)],
             by = c("year", "regulated"), all.x = TRUE), out_csv)
cat("Detail CSV saved:", out_csv, "\n")

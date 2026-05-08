###############################################################################
# phase4_ppi_did_2017_eventstudy.R
#
# PURPOSE:
#   Year-by-year event study for the three 2017-cutoff DiD specs in
#   phase4_ppi_did_2017.R, plus Roth-Rambachan (2023) sensitivity bounds
#   on the first post-treatment effect.
#
# SPEC (run separately for each X_s ∈ {Treated, ω_em, ω_sh}):
#   log(PPI_{s,m}) = Σ_{τ ≠ 2016} β_τ · X_s · 1{year(m) = τ}
#                  + α_s + δ_m + ε_{s,m}
#   Reference year: 2016 (last fully pre-treatment year before 2017 cutoff).
#   Sector FE α_s; year-month FE δ_m; cluster SE on NACE 4-digit.
#
# Pre-periods: 2010-2015 (6); reference 2016; post-periods: 2017-2022 (6).
#
# ROTH-RAMBACHAN sensitivity (Rambachan-Roth 2023, RES):
#   - Δ^{RM}(M̄): post-treatment violation of parallel trends ≤ M̄ × max
#     pre-period violation. M̄ ∈ {0, 0.5, 1, 1.5, 2}.
#   - Δ^{SD}(M):  smoothness restriction on second differences ≤ M.
#     M-grid = quantiles of |Δ^2 β̂_pre|.
#   l_vec = c(1, 0, 0, 0, 0, 0): inference on β_2017 (first post-period).
#
# OUTPUT:
#   ${OUTPUT_TAB}/phase4_ppi_eventstudy_<spec>.csv        (year-by-year coefs)
#   ${OUTPUT_TAB}/phase4_ppi_eventstudy_<spec>_RM.csv     (Δ^{RM} bounds)
#   ${OUTPUT_TAB}/phase4_ppi_eventstudy_<spec>_SD.csv     (Δ^{SD} bounds)
#   ${OUTPUT_FIG}/phase4_ppi_eventstudy_<spec>.{pdf,png}  (event study)
#   ${OUTPUT_FIG}/phase4_ppi_eventstudy_<spec>_honestdid.{pdf,png}  (RR)
#
# spec ∈ {treated, omega_em, omega_sh}.
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readxl); library(stringr)
  library(lubridate); library(fixest); library(ggplot2); library(HonestDiD)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

TREAT_YEAR <- 2017
REF_YEAR   <- 2016
TREATED_2D <- c("17", "19", "20", "23", "24", "25", "35")

###############################################################################
# 1. Build the panel (same logic as phase4_ppi_did_2017.R)
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

ppi_main <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0,
         ppi_source == "statbel_4d_chained",
         date >= as.Date("2010-01-01"), date <= as.Date("2022-12-01")) %>%
  mutate(year = year(date),
         nace2d = str_pad(nace2d, 2, pad = "0"))

old_file <- file.path(RAW_DATA, "Statbel",
                      "Statbel_TABEL_WEBSITE_AANGEVERS_2021_EN.xlsx")
TARGET_4D <- c("1920", "3510", "3520")
d_old <- read_excel(old_file, sheet = "Domestic market", col_names = FALSE)
names(d_old) <- c("nace4d_raw", "label_or_year",
                  "Jan","Feb","Mar","Apr","May","Jun",
                  "Jul","Aug","Sep","Oct","Nov","Dec","Annual")
d_old <- d_old %>%
  mutate(nace4d = ifelse(!is.na(nace4d_raw),
                         as.character(nace4d_raw), NA_character_)) %>%
  tidyr::fill(nace4d, .direction = "down") %>%
  mutate(year = suppressWarnings(as.integer(label_or_year))) %>%
  filter(!is.na(year), nace4d %in% TARGET_4D) %>%
  mutate(across(c(Jan:Dec), as.numeric)) %>%
  select(nace4d, year, Jan:Dec) %>%
  pivot_longer(cols = Jan:Dec, names_to = "month_abbr", values_to = "ppi") %>%
  mutate(month  = match(month_abbr, month.abb),
         date   = as.Date(sprintf("%d-%02d-01", year, month)),
         nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2),
         ppi_source = "statbel_4d_old_file") %>%
  filter(!is.na(ppi), ppi > 0,
         date >= as.Date("2010-01-01"), date <= as.Date("2022-12-01")) %>%
  select(nace4d, nace2d, date, year, month, ppi, ppi_source)

ppi <- bind_rows(ppi_main, d_old) %>%
  filter(as.integer(nace2d) %in% c(10:33, 35)) %>%
  mutate(log_ppi    = log(ppi),
         year_month = format(date, "%Y-%m"),
         treated_d  = as.integer(nace2d %in% TREATED_2D),
         year_f     = factor(year, levels = sort(unique(year))))

# omega measures on 2015-2016
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
manuf_set <- c(sprintf("%02d", 10:33), "35")
exposure <- sector_exposure %>%
  mutate(nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2)) %>%
  filter(nace2d %in% manuf_set,
         !is.na(total_cost_denom), total_cost_denom > 0) %>%
  mutate(nace4d = case_when(
    str_detect(nace4d, "^351[1-4]$") ~ "3510",
    str_detect(nace4d, "^352[1-3]$") ~ "3520",
    TRUE                              ~ nace4d
  )) %>%
  group_by(nace4d, year, nace2d) %>%
  summarise(total_emissions  = sum(total_emissions,  na.rm = TRUE),
            total_shortage   = sum(total_shortage,   na.rm = TRUE),
            total_cost_denom = sum(total_cost_denom, na.rm = TRUE),
            .groups = "drop")

omega_avg <- function(df, num_col, yrs = 2015:2016) {
  df %>% filter(year %in% yrs, !is.na(.data[[num_col]])) %>%
    group_by(nace4d) %>%
    summarise(num = sum(.data[[num_col]], na.rm = TRUE),
              den = sum(total_cost_denom, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(omega = num / den) %>% select(nace4d, omega)
}
omega_em_15_16 <- omega_avg(exposure, "total_emissions") %>% rename(omega_em = omega)
omega_sh_15_16 <- omega_avg(exposure, "total_shortage")  %>% rename(omega_sh = omega)

ppi <- ppi %>%
  left_join(omega_em_15_16, by = "nace4d") %>%
  left_join(omega_sh_15_16, by = "nace4d") %>%
  mutate(omega_em = coalesce(omega_em, 0),
         omega_sh = coalesce(omega_sh, 0))

cat(sprintf("Panel: %d obs, %d sectors, %s to %s\n",
            nrow(ppi), n_distinct(ppi$nace4d),
            format(min(ppi$date)), format(max(ppi$date))))

###############################################################################
# 2. Event-study runner: extract β̂_τ and Σ̂ for one spec
###############################################################################
run_event_study <- function(panel, X_var, ref_year, spec_label) {
  cat(sprintf("\n========== Event study: %s ==========\n", spec_label))
  panel$X_var <- panel[[X_var]]
  m <- feols(log_ppi ~ i(year_f, X_var, ref = as.character(ref_year)) |
                       nace4d + year_month,
             data = panel, cluster = ~nace4d, notes = FALSE)
  ct <- as.data.frame(coeftable(m))
  ct$term <- rownames(ct)
  ct$year <- suppressWarnings(as.integer(sub("^year_f::([0-9]+):.*$", "\\1", ct$term)))
  ct <- ct[!is.na(ct$year), ]
  ct <- ct[order(ct$year), ]

  ct$lo95 <- ct$Estimate - 1.96 * ct[["Std. Error"]]
  ct$hi95 <- ct$Estimate + 1.96 * ct[["Std. Error"]]
  ct$lo90 <- ct$Estimate - 1.645 * ct[["Std. Error"]]
  ct$hi90 <- ct$Estimate + 1.645 * ct[["Std. Error"]]

  cat("Event-study coefficients (omitted reference: ", ref_year, "):\n", sep = "")
  print(ct[, c("year", "Estimate", "Std. Error", "lo95", "hi95")],
        row.names = FALSE, digits = 4)

  vc <- vcov(m)
  vnames <- names(coef(m))
  use <- grep("^year_f::", vnames)
  list(model = m,
       coefs = ct,
       betahat = ct$Estimate,
       sigma   = vc[use, use],
       years   = ct$year,
       ref_yr  = ref_year)
}

###############################################################################
# 3. HonestDiD wrapper: RM + SD sensitivity at first post-period
###############################################################################
run_hdid <- function(es, post_start, spec_label) {
  pre_idx  <- which(es$years <  post_start)
  post_idx <- which(es$years >= post_start)
  ord      <- c(pre_idx, post_idx)
  betahat  <- es$betahat[ord]
  sigma    <- es$sigma[ord, ord]
  num_pre  <- length(pre_idx)
  num_post <- length(post_idx)

  # l_vec: weight on β_{post_start} (first post-period). Standard "test-h=0" form.
  l_vec0 <- c(1, rep(0, num_post - 1L))

  # Original CS (no restriction beyond standard normal CI)
  orig <- constructOriginalCS(betahat = betahat, sigma = sigma,
                              numPrePeriods = num_pre,
                              numPostPeriods = num_post,
                              l_vec = l_vec0)
  cat(sprintf("\nOriginal 95%% CI for β_{%d} (no robust restriction): [%.4f, %.4f]\n",
              es$years[post_idx[1]], orig$lb, orig$ub))

  res_rm <- tryCatch(
    createSensitivityResults_relativeMagnitudes(
      betahat = betahat, sigma = sigma,
      numPrePeriods = num_pre, numPostPeriods = num_post,
      Mbarvec = c(0, 0.5, 1, 1.5, 2),
      l_vec = l_vec0),
    error = function(e) {cat("RM error:", conditionMessage(e), "\n"); NULL})
  if (!is.null(res_rm)) {
    cat("\nΔ^{RM}(M̄) sensitivity for β_{first post-period}:\n")
    print(res_rm, digits = 4)
  }

  # SD grid: 0 + 0.5..2 SD of pre-period 2nd differences
  pre_betas <- betahat[1:num_pre]
  if (length(pre_betas) >= 2) {
    pre_2d <- diff(diff(c(pre_betas, 0)))   # pre + ref(=0); 2nd differences
  } else {
    pre_2d <- 0
  }
  m_grid <- c(0, sd(c(pre_2d, 0), na.rm = TRUE) * c(0.5, 1, 1.5, 2))
  m_grid <- m_grid[is.finite(m_grid)]

  res_sd <- tryCatch(
    createSensitivityResults(
      betahat = betahat, sigma = sigma,
      numPrePeriods = num_pre, numPostPeriods = num_post,
      method = "FLCI", Mvec = m_grid, l_vec = l_vec0),
    error = function(e) {cat("SD error:", conditionMessage(e), "\n"); NULL})
  if (!is.null(res_sd)) {
    cat("\nΔ^{SD}(M) sensitivity for β_{first post-period} (FLCI):\n")
    print(res_sd, digits = 4)
  }

  list(orig = orig, rm = res_rm, sd = res_sd,
       num_pre = num_pre, num_post = num_post,
       l_vec = l_vec0,
       years_pre = es$years[pre_idx],
       years_post = es$years[post_idx])
}

###############################################################################
# 4. Plotting helpers
###############################################################################
plot_eventstudy <- function(es, spec_label, ref_year, basename) {
  d <- es$coefs
  d$ref <- as.numeric(d$year == ref_year)
  ref_row <- data.frame(year = ref_year, Estimate = 0,
                        `Std. Error` = 0, lo95 = 0, hi95 = 0,
                        lo90 = 0, hi90 = 0, ref = 1)
  names(ref_row)[3] <- "Std. Error"
  d2 <- bind_rows(d[, names(ref_row)], ref_row) %>% arrange(year)

  p <- ggplot(d2, aes(x = year, y = Estimate)) +
    geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
    geom_vline(xintercept = TREAT_YEAR - 0.5, colour = "black",
               linewidth = 0.5, linetype = "dotted") +
    geom_errorbar(aes(ymin = lo95, ymax = hi95), width = 0.15,
                  colour = "grey25") +
    geom_point(size = 2, colour = "black") +
    scale_x_continuous(breaks = seq(2010, 2022, by = 2)) +
    labs(x = NULL, y = expression(hat(beta)[tau]),
         title = NULL,
         subtitle = NULL) +
    theme_minimal(base_size = 11) +
    theme(panel.grid = element_blank(),
          axis.line = element_line(colour = "black"),
          axis.ticks = element_line(colour = "black"))
  ggsave(file.path(OUTPUT_FIG, paste0(basename, ".pdf")), p,
         width = 8, height = 4.5)
  ggsave(file.path(OUTPUT_FIG, paste0(basename, ".png")), p,
         width = 8, height = 4.5, dpi = 200)
  cat(sprintf("Saved: %s.{pdf,png}\n", basename))
  invisible(p)
}

plot_hdid_RM <- function(hd, spec_label, basename) {
  if (is.null(hd$rm)) return(invisible(NULL))
  g <- createSensitivityPlot_relativeMagnitudes(hd$rm, hd$orig) +
    labs(title = sprintf("%s — Δ^{RM} sensitivity (Rambachan-Roth 2023)",
                         spec_label),
         subtitle = sprintf("CI on first post-period effect (year %d).",
                            hd$years_post[1]))
  ggsave(file.path(OUTPUT_FIG, paste0(basename, ".pdf")), g,
         width = 9, height = 5)
  ggsave(file.path(OUTPUT_FIG, paste0(basename, ".png")), g,
         width = 9, height = 5, dpi = 200)
  cat(sprintf("Saved: %s.{pdf,png}\n", basename))
  invisible(g)
}

###############################################################################
# 5. Run the three specs
###############################################################################
SPECS <- list(
  list(X = "treated_d", label = "(A) Treated × year (binary)",
       slug  = "treated"),
  list(X = "omega_em",  label = "(B) ω_emissions × year (continuous)",
       slug  = "omega_em"),
  list(X = "omega_sh",  label = "(C) ω_shortage × year (continuous)",
       slug  = "omega_sh")
)

results <- list()
for (s in SPECS) {
  es <- run_event_study(ppi, s$X, REF_YEAR, s$label)
  hd <- run_hdid(es, post_start = TREAT_YEAR, spec_label = s$label)

  # Save coefficient CSVs
  write.csv(es$coefs[, c("year", "Estimate", "Std. Error", "lo95", "hi95")],
            file.path(OUTPUT_TAB,
                      sprintf("phase4_ppi_eventstudy_%s.csv", s$slug)),
            row.names = FALSE)
  if (!is.null(hd$rm)) {
    write.csv(as.data.frame(hd$rm),
              file.path(OUTPUT_TAB,
                        sprintf("phase4_ppi_eventstudy_%s_RM.csv", s$slug)),
              row.names = FALSE)
  }
  if (!is.null(hd$sd)) {
    write.csv(as.data.frame(hd$sd),
              file.path(OUTPUT_TAB,
                        sprintf("phase4_ppi_eventstudy_%s_SD.csv", s$slug)),
              row.names = FALSE)
  }

  # Plots
  plot_eventstudy(es, s$label, REF_YEAR,
                  sprintf("phase4_ppi_eventstudy_%s", s$slug))
  plot_hdid_RM(hd, s$label,
               sprintf("phase4_ppi_eventstudy_%s_honestdid", s$slug))

  results[[s$slug]] <- list(es = es, hd = hd)
}

cat("\nDone. Outputs saved to:\n")
cat(sprintf("  CSVs: %s\n", OUTPUT_TAB))
cat(sprintf("  Figures: %s\n", OUTPUT_FIG))

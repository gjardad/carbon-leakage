###############################################################################
# phase0_pairwise_decomposition.R
#
# Six-channel emissions decomposition for arbitrary (t_base, t_end) pairs.
#
# For each pair, split firms into survivors (present in both years with
# positive emissions), entrants (present in t_end only), and exiters (present
# in t_base only). Decompose the total change E_{t_end} - E_{t_base} into:
#
#   Scale      — survivor-subset output growth at base shares & intensities
#   Between    — sector-share shifts (NACE 2d), intensities frozen at base
#   Within     — firm-share shifts net of sector shifts, intensities frozen
#   Technique  — within-firm intensity change, shares at t_end
#   Entry      — emissions of firms present in t_end but not t_base
#   Exit       — (negative of) emissions of firms present in t_base but not t_end
#
# By construction, the six channels sum to E_{t_end} - E_{t_base}. Each is
# reported as a percentage point of E_{t_base}.
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(stringr)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Config ----
pairs <- list(
  c(2005, 2007),
  c(2005, 2012),
  c(2005, 2020),
  c(2005, 2022),
  c(2007, 2012),
  c(2007, 2020),
  c(2012, 2020)
)

# ---- Load deflator ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))

# ---- Load firm panel, deflate revenue ----
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))

df <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(!is.na(nace2d), !is.na(emissions), !is.na(revenue),
         emissions > 0, revenue > 0) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year"))

# 2d fallback for firms without 4d deflator
df <- df %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Decomposition function ----
# If restrict_vats is non-NULL, survivors/entrants/exiters are all confined to
# firms in that set (used for triple-balanced rows). In that case entry and
# exit are zero by construction.
decompose_pair <- function(df, t0, t1, restrict_vats = NULL,
                           exclude_vats = NULL, label = NULL) {
  if (!is.null(restrict_vats)) df <- df %>% filter(vat %in% restrict_vats)
  if (!is.null(exclude_vats))  df <- df %>% filter(!(vat %in% exclude_vats))

  d0 <- df %>% filter(year == t0) %>%
    select(vat, nace2d_0 = nace2d, e_0 = emissions, q_0 = real_revenue)
  d1 <- df %>% filter(year == t1) %>%
    select(vat, nace2d_1 = nace2d, e_1 = emissions, q_1 = real_revenue)

  # Join on vat only: a firm that switches nace2d is still a survivor.
  # For the sector split we use its t_base sector (nace2d_0).
  survivors <- inner_join(d0, d1, by = "vat") %>%
    mutate(nace2d = nace2d_0)
  exiters   <- anti_join(d0, d1, by = "vat") %>% mutate(nace2d = nace2d_0)
  entrants  <- anti_join(d1, d0, by = "vat") %>% mutate(nace2d = nace2d_1)

  # Aggregates (within-survivor Y's; total-sample E_t's for the normaliser)
  E_t0 <- sum(d0$e_0)                 # full t_base total (survivors + exiters)
  E_t1 <- sum(d1$e_1)                 # full t_end total (survivors + entrants)

  E_s_0 <- sum(survivors$e_0)         # survivor emissions in t_base
  E_s_1 <- sum(survivors$e_1)         # survivor emissions in t_end
  Y_s_0 <- sum(survivors$q_0)
  Y_s_1 <- sum(survivors$q_1)

  E_entry <- sum(entrants$e_1)
  E_exit  <- sum(exiters$e_0)

  # Group-average intensities (emissions / revenue across each group)
  z_entrants <- if (nrow(entrants) > 0) sum(entrants$e_1) / sum(entrants$q_1) else NA_real_
  z_exiters  <- if (nrow(exiters)  > 0) sum(exiters$e_0)  / sum(exiters$q_0)  else NA_real_
  z_survivors_t0 <- E_s_0 / Y_s_0
  z_survivors_t1 <- E_s_1 / Y_s_1

  # Within-survivor firm shares & intensities
  s <- survivors %>%
    mutate(theta_0 = q_0 / Y_s_0,
           theta_1 = q_1 / Y_s_1,
           z_0     = e_0 / q_0,
           z_1     = e_1 / q_1)

  # Counterfactual emissions using survivors only, scaled to Y_s_1
  E_scale      <- Y_s_1 * sum(s$theta_0 * s$z_0)   # == (Y_s_1 / Y_s_0) * E_s_0
  E_scale_reall <- Y_s_1 * sum(s$theta_1 * s$z_0)  # shares move to t_end, z at base
  E_actual     <- Y_s_1 * sum(s$theta_1 * s$z_1)   # == E_s_1

  # Sector-level quantities within survivors (for between/within split)
  sec <- s %>%
    group_by(nace2d) %>%
    summarise(e_0_s = sum(e_0), e_1_s = sum(e_1),
              q_0_s = sum(q_0), q_1_s = sum(q_1),
              .groups = "drop") %>%
    mutate(theta_s_0 = q_0_s / Y_s_0,
           theta_s_1 = q_1_s / Y_s_1,
           z_s_0     = e_0_s / q_0_s)  # sector intensity in t_base

  E_scale_s      <- Y_s_1 * sum(sec$theta_s_0 * sec$z_s_0)  # == E_scale
  E_scale_comp_s <- Y_s_1 * sum(sec$theta_s_1 * sec$z_s_0)  # sector shares shift

  # Channel magnitudes (levels, tCO2)
  scale_eff     <- E_scale - E_s_0
  between_eff   <- E_scale_comp_s - E_scale_s
  within_eff    <- E_scale_reall - E_scale_comp_s   # firm-level reall minus sector
  tech_eff      <- E_actual - E_scale_reall
  entry_eff     <- E_entry
  exit_eff      <- -E_exit                          # negative contribution

  total_change  <- E_t1 - E_t0

  # Check that channels sum to total (up to floating point)
  check <- scale_eff + between_eff + within_eff + tech_eff + entry_eff + exit_eff
  stopifnot(isTRUE(all.equal(check, total_change, tolerance = 1e-6)))

  # Express in pp of E_t0
  tibble(
    label = if (is.null(label)) paste0(t0, " -> ", t1) else label,
    t_base = t0, t_end = t1,
    n_survivors = nrow(survivors),
    n_entrants  = nrow(entrants),
    n_exiters   = nrow(exiters),
    E_t_base = E_t0, E_t_end = E_t1,
    total_pp    = total_change / E_t0 * 100,
    scale_pp    = scale_eff    / E_t0 * 100,
    between_pp  = between_eff  / E_t0 * 100,
    within_pp   = within_eff   / E_t0 * 100,
    tech_pp     = tech_eff     / E_t0 * 100,
    entry_pp    = entry_eff    / E_t0 * 100,
    exit_pp     = exit_eff     / E_t0 * 100,
    z_survivors_t0 = z_survivors_t0,
    z_survivors_t1 = z_survivors_t1,
    z_entrants_t1  = z_entrants,
    z_exiters_t0   = z_exiters
  )
}

# ---- Run: unrestricted pairs ----
results <- bind_rows(lapply(pairs, function(p) decompose_pair(df, p[1], p[2])))

# ---- Run: triple-balanced panel (firms with e>0 in 2005, 2012, and 2020) ----
vats_2005 <- df %>% filter(year == 2005) %>% pull(vat)
vats_2012 <- df %>% filter(year == 2012) %>% pull(vat)
vats_2020 <- df %>% filter(year == 2020) %>% pull(vat)
triple_vats <- Reduce(intersect, list(vats_2005, vats_2012, vats_2020))
cat("\nTriple-balanced panel (firms in 2005, 2012, 2020):", length(triple_vats), "firms\n")

results_triple <- bind_rows(
  decompose_pair(df, 2005, 2012, restrict_vats = triple_vats, label = "2005 -> 2012 [triple-bal]"),
  decompose_pair(df, 2012, 2020, restrict_vats = triple_vats, label = "2012 -> 2020 [triple-bal]"),
  decompose_pair(df, 2005, 2020, restrict_vats = triple_vats, label = "2005 -> 2020 [triple-bal]")
)

results <- bind_rows(results, results_triple)

# ---- Run: contaminated-firm-excluded rows ----
# Three firms drop off EUTL reporting in 2021 while their Annual Accounts
# revenue continues/grows; identified as installation reclassification
# artefacts. Exclude them from every year of the sample (not just 2021+) so
# they do not enter the decomposition at all. Affects pairs that cross the
# 2021 break; leaves 2005->2020 and earlier rows untouched.
contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF", # NACE 24
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076", # NACE 20
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"  # NACE 20
)

results_excl <- bind_rows(
  decompose_pair(df, 2005, 2022, exclude_vats = contaminated_vats,
                 label = "2005 -> 2022 [ex. 3 VATs]"),
  decompose_pair(df, 2007, 2022, exclude_vats = contaminated_vats,
                 label = "2007 -> 2022 [ex. 3 VATs]"),
  decompose_pair(df, 2012, 2022, exclude_vats = contaminated_vats,
                 label = "2012 -> 2022 [ex. 3 VATs]")
)

results <- bind_rows(results, results_excl)

cat("\n=== Six-channel pairwise decomposition ===\n")
cat("All channels reported in pp of E_{t_base}. Channels sum to total.\n")
cat("n_survivors: firms with emissions>0 in both years\n")
cat("n_entrants:  firms with emissions>0 in t_end only\n")
cat("n_exiters:   firms with emissions>0 in t_base only\n\n")

print_tbl <- results %>%
  select(label, n_survivors, n_entrants, n_exiters,
         total_pp, scale_pp, between_pp, within_pp, tech_pp, entry_pp, exit_pp,
         z_entrants_t1, z_exiters_t0) %>%
  mutate(across(ends_with("_pp"), ~ round(., 1)),
         across(starts_with("z_"), ~ round(., 5)))

print(as.data.frame(print_tbl))

cat("\nZ units: tCO2 per EUR of real revenue (2005-base deflation).\n")
cat("z_entrants_t1 = sum(e_entrants, t_end) / sum(q_entrants, t_end)\n")
cat("z_exiters_t0  = sum(e_exiters,  t_base) / sum(q_exiters,  t_base)\n")

# ---- Save ----
out_path <- file.path(OUTPUT_TAB, "phase0_pairwise_decomposition.csv")
write.csv(results %>%
  mutate(across(ends_with("_pp"), ~ round(., 2))),
  out_path, row.names = FALSE)
cat("\nSaved:", out_path, "\n")

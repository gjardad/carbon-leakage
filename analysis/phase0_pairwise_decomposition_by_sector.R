###############################################################################
# phase0_pairwise_decomposition_by_sector.R
#
# Per-NACE-2d pairwise decomposition. For each sector we decompose its own
# 2005 -> t1 emissions change into:
#
#   Scale       — sector's survivor real-revenue growth at base shares & intensities
#   Within      — within-sector firm-share shifts, intensities at base
#   Technique   — within-firm intensity change
#   Entry       — emissions of firms present in t1 but not t0 in this sector
#   Exit        — (negative of) emissions of firms present in t0 but not t1
#
# Five channels per sector sum to the sector's own Total (in pp of sector 2005
# emissions). Between-sector collapses to zero at single-sector level.
#
# Sample: firms with e > 0, positive revenue, matched deflator; 3 contaminated
# VATs excluded in every year (same as the aggregate cleaning).
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
pair_list <- list(c(2005, 2022), c(2005, 2012), c(2012, 2022))
min_firms_both <- 3   # sectors need at least this many firms in both endpoints

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)

# ---- Load + deflate ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))

df <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(!is.na(nace2d), !is.na(emissions), !is.na(revenue),
         emissions > 0, revenue > 0,
         !(vat %in% contaminated_vats)) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Per-sector decomposition ----
sector_pair_decomp <- function(df_s, t0, t1, nace2d_target) {
  d0 <- df_s %>% filter(year == t0) %>%
    select(vat, e_0 = emissions, q_0 = real_revenue)
  d1 <- df_s %>% filter(year == t1) %>%
    select(vat, e_1 = emissions, q_1 = real_revenue)

  if (nrow(d0) < min_firms_both || nrow(d1) < min_firms_both) return(NULL)

  survivors <- inner_join(d0, d1, by = "vat")
  exiters   <- anti_join(d0, d1, by = "vat")
  entrants  <- anti_join(d1, d0, by = "vat")

  E_t0 <- sum(d0$e_0); E_t1 <- sum(d1$e_1)
  E_s_0 <- sum(survivors$e_0); E_s_1 <- sum(survivors$e_1)
  Y_s_0 <- sum(survivors$q_0); Y_s_1 <- sum(survivors$q_1)
  E_entry <- sum(entrants$e_1); E_exit <- sum(exiters$e_0)

  if (nrow(survivors) == 0 || Y_s_0 == 0 || Y_s_1 == 0) return(NULL)

  s <- survivors %>%
    mutate(theta_0 = q_0 / Y_s_0,
           theta_1 = q_1 / Y_s_1,
           z_0 = e_0 / q_0,
           z_1 = e_1 / q_1)

  E_scale       <- Y_s_1 * sum(s$theta_0 * s$z_0)
  E_scale_reall <- Y_s_1 * sum(s$theta_1 * s$z_0)
  E_actual      <- Y_s_1 * sum(s$theta_1 * s$z_1)

  scale_eff <- E_scale       - E_s_0
  reall_eff <- E_scale_reall - E_scale
  tech_eff  <- E_actual      - E_scale_reall
  entry_eff <- E_entry
  exit_eff  <- -E_exit

  total <- E_t1 - E_t0
  check <- scale_eff + reall_eff + tech_eff + entry_eff + exit_eff
  stopifnot(isTRUE(all.equal(check, total, tolerance = 1e-6)))

  tibble(
    nace2d = nace2d_target,
    t_base = t0, t_end = t1,
    n_surv = nrow(survivors),
    n_ent  = nrow(entrants),
    n_exit = nrow(exiters),
    E_t0_kt = E_t0 / 1000,
    total_pp = total / E_t0 * 100,
    scale_pp = scale_eff / E_t0 * 100,
    within_pp = reall_eff / E_t0 * 100,
    tech_pp = tech_eff / E_t0 * 100,
    entry_pp = entry_eff / E_t0 * 100,
    exit_pp = exit_eff / E_t0 * 100
  )
}

run_all_sectors <- function(df, t0, t1) {
  sectors <- df %>% distinct(nace2d) %>% pull(nace2d)
  bind_rows(lapply(sectors, function(s) {
    sector_pair_decomp(df %>% filter(nace2d == s), t0, t1, s)
  }))
}

results <- bind_rows(lapply(pair_list, function(p) run_all_sectors(df, p[1], p[2])))

# ---- Compute each sector's share of aggregate 2005 emissions (for weighting) ----
E_agg_2005 <- df %>% filter(year == 2005) %>% summarise(E = sum(emissions)) %>% pull(E)

sector_share_2005 <- df %>%
  filter(year == 2005) %>%
  group_by(nace2d) %>%
  summarise(E_2005_sector = sum(emissions), .groups = "drop") %>%
  mutate(share_2005 = E_2005_sector / E_agg_2005 * 100)

results <- results %>%
  left_join(sector_share_2005 %>% select(nace2d, share_2005), by = "nace2d") %>%
  arrange(t_base, t_end, desc(share_2005))

# ---- Print ----
for (pair in pair_list) {
  cat("\n=== ", pair[1], " -> ", pair[2], " (pp of sector's own t_base emissions) ===\n", sep="")
  tbl <- results %>%
    filter(t_base == pair[1], t_end == pair[2]) %>%
    mutate(across(ends_with("_pp"), ~ round(., 1)),
           share_2005 = round(share_2005, 1),
           E_t0_kt = round(E_t0_kt, 0)) %>%
    select(nace2d, share_2005, n_surv, n_ent, n_exit,
           total_pp, scale_pp, within_pp, tech_pp, entry_pp, exit_pp)
  print(as.data.frame(tbl))
}

# ---- Save ----
out_path <- file.path(OUTPUT_TAB, "phase0_pairwise_decomposition_by_sector.csv")
write.csv(results %>%
  mutate(across(c(total_pp, scale_pp, within_pp, tech_pp, entry_pp, exit_pp, share_2005),
                ~ round(., 2))),
  out_path, row.names = FALSE)
cat("\nSaved:", out_path, "\n")

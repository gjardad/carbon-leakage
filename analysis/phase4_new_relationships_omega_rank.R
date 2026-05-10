###############################################################################
# phase4_new_relationships_omega_rank.R
#
# PURPOSE
#   Among buyer-(supplier-NACE4d)-year cells in ETS-treated NACE4d where the
#   buyer establishes a NEW relationship with a supplier, characterize that
#   new supplier's position in the year-t omega distribution within the
#   NACE4d. Compare pre-treatment vs post-treatment (around 2008 / 2013 /
#   2017) to see whether new relationships are biased toward cleaner firms
#   in the post period.
#
#   Two omega definitions:
#     Def 1 (allowance shortage / cost):
#         omega1_it = max(emissions_it - allocated_free_it, 0) / total_cost_it
#     Def 2 (emissions / cost):
#         omega2_it = emissions_it / total_cost_it
#   total_cost_it = (revenue - value_added) + wage_bill (all from AA panel
#   via firm_exposure).
#
# DEFINITIONS
#   - "New relationship in year t": first year (in 2005-2022 b2b panel) the
#     buyer was observed transacting with that supplier. We drop pairs first
#     observed in 2005 because they are left-censored (the relationship may
#     have started before our window).
#   - "Year-t omega rank within NACE4d": percentile rank of the supplier's
#     year-t omega among all ETS firms in the same NACE4d in year t. Higher
#     percentile = more carbon-cost-exposed.
#   - We restrict to new relationships where the supplier is an ETS firm
#     (i.e., has a row in firm_year_belgian_euets in year t with non-NA
#     omega). Non-ETS suppliers don't have a meaningful within-NACE4d omega
#     rank so we exclude them. (Alternative: assign rank = 0 to non-ETS
#     firms. Easy to flip.)
#
# PLOTS
#   - phase4_new_relationships_omega_rank_def1.{png,pdf}
#   - phase4_new_relationships_omega_rank_def2.{png,pdf}
#         Mean year-t omega-rank of new-relationship suppliers, by year, with
#         95% bootstrap CIs. Vertical lines at 2008 / 2013 / 2017.
#         Horizontal reference at 0.5 (mean rank if randomly drawn from the
#         within-NACE4d ETS-firm distribution).
#
# TABLES
#   - phase4_new_relationships_omega_rank_yearly.csv
#         year-by-year mean rank + n + CI for both omega defs.
#   - phase4_new_relationships_omega_rank_pre_post.csv
#         pre vs post means around each event year (2008, 2013, 2017),
#         5-year window each side.
#   - phase4_new_relationships_omega_rank_obs.csv
#         underlying obs-level data: one row per new relationship.
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(xtable)
})

write_tex_table <- function(dt, file, digits = 4, caption = NULL) {
  x <- xtable(as.data.frame(dt), digits = digits, caption = caption)
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function    = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
  invisible(NULL)
}

set.seed(20260508)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
N_BOOT  <- 1000L
EVENT_YEARS <- c(2008L, 2013L, 2017L)
PRE_POST_WINDOW <- 5L

# ---------------------------------------------------------------------------
# 1. Load b2b, AA, firm_exposure
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year))]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(
  vat = as.character(vat),
  year = as.integer(year),
  emissions, allocated_free, shortage, total_cost,
  nace4d = as.character(nace4d)
)]
rm(firm_exposure)

# Year-level firm omega under both definitions
fe[, omega1 := ifelse(!is.na(shortage) & !is.na(total_cost) & total_cost > 0,
                      shortage / total_cost, NA_real_)]
fe[, omega2 := ifelse(!is.na(emissions) & !is.na(total_cost) & total_cost > 0,
                      emissions / total_cost, NA_real_)]

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_treated_nace4d)))

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# ---------------------------------------------------------------------------
# 2. Identify new relationships
#    - For each (buyer, seller) pair: first year observed in b2b
#    - Drop pairs first observed in YEAR_LO (left-censored)
#    - Each new relationship = (buyer, seller, year_first, supplier-NACE4d)
# ---------------------------------------------------------------------------
cat("\nIdentifying new relationships...\n")

first_year <- b2b[, .(year_first = min(year)), by = .(buyer, seller)]
new_rel    <- first_year[year_first > YEAR_LO]                # drop censored

# Bring in supplier NACE4d in the year of first observation
new_rel <- merge(new_rel,
                 b2b[, .(buyer, seller, year, seller_nace4d)],
                 by.x = c("buyer", "seller", "year_first"),
                 by.y = c("buyer", "seller", "year"))

# Restrict to new relationships in ETS-treated NACE4d
new_rel <- new_rel[seller_nace4d %in% ets_treated_nace4d]

cat(sprintf("  new relationships in ETS-treated NACE4d (year >%d): %d\n",
            YEAR_LO, nrow(new_rel)))

# ---------------------------------------------------------------------------
# 3. Year-t omega rank within NACE4d (percentile, ETS firms only)
# ---------------------------------------------------------------------------
# Universe of "firms in NACE4d N in year t with a usable omega" = rows of fe
# with non-NA omega in (N, t). Compute percentile rank in [0, 1] within
# (NACE4d, year, omega-definition); higher = more exposed.

compute_rank <- function(omega_col) {
  d <- fe[!is.na(get(omega_col)), .(vat, year, nace4d, omega = get(omega_col))]
  # Percentile rank within (nace4d, year). Ties get average rank.
  d[, rank := frank(omega, ties.method = "average") / .N,
    by = .(nace4d, year)]
  d[, n_in_cell := .N, by = .(nace4d, year)]
  d[, .(seller = vat, year, seller_nace4d = nace4d, rank, n_in_cell)]
}

rank_def1 <- compute_rank("omega1")
rank_def2 <- compute_rank("omega2")

# Attach to new relationships
attach_rank <- function(rank_dt, rank_label) {
  out <- merge(new_rel, rank_dt,
               by.x = c("seller", "year_first", "seller_nace4d"),
               by.y = c("seller", "year",       "seller_nace4d"))
  out[, definition := rank_label]
  out
}
obs_def1 <- attach_rank(rank_def1, "Def 1: shortage/cost")
obs_def2 <- attach_rank(rank_def2, "Def 2: emissions/cost")

# Merged obs-level table
obs <- rbind(obs_def1, obs_def2)
fwrite(obs,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_obs.csv"))

cat("\nNew-relationships matched to omega rank (ETS-firm suppliers only):\n")
print(obs[, .(n_obs = .N,
              n_unique_relationships = uniqueN(paste(buyer, seller))),
          by = definition])

# ---------------------------------------------------------------------------
# 4. Aggregate: yearly mean rank with bootstrap CI
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

yearly <- obs[, {
  ci <- boot_ci(rank, stat = mean)
  .(mean_rank   = mean(rank, na.rm = TRUE),
    median_rank = median(rank, na.rm = TRUE),
    n_obs       = .N,
    ci_lo       = ci$lo,
    ci_hi       = ci$hi)
}, by = .(definition, year_first)]
setorder(yearly, definition, year_first)
fwrite(yearly,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_yearly.csv"))

# ---------------------------------------------------------------------------
# 5. Pre vs post for each event year, +/-PRE_POST_WINDOW years
# ---------------------------------------------------------------------------
pre_post_list <- list()
for (ty in EVENT_YEARS) {
  for (defn in unique(obs$definition)) {
    pre  <- obs[definition == defn &
                year_first >= ty - PRE_POST_WINDOW & year_first <  ty, rank]
    post <- obs[definition == defn &
                year_first >= ty & year_first <= ty + PRE_POST_WINDOW - 1L, rank]
    if (length(pre) >= 5L && length(post) >= 5L) {
      tt <- t.test(post, pre)
      pre_post_list[[paste(defn, ty)]] <- data.table(
        definition  = defn,
        treat_year  = ty,
        window_yrs  = PRE_POST_WINDOW,
        n_pre       = length(pre),
        n_post      = length(post),
        mean_pre    = mean(pre),
        mean_post   = mean(post),
        diff        = mean(post) - mean(pre),
        t_stat      = unname(tt$statistic),
        p_value     = tt$p.value
      )
    }
  }
}
pre_post <- rbindlist(pre_post_list, use.names = TRUE)
fwrite(pre_post,
       file.path(OUTPUT_TAB,
                 "phase4_new_relationships_omega_rank_pre_post.csv"))
write_tex_table(pre_post,
                file.path(OUTPUT_TAB,
                          "phase4_new_relationships_omega_rank_pre_post.tex"),
                caption = "New-supplier omega rank: pre vs post each event year.")

cat("\nPre vs post (mean rank, +/- 5 years around each event):\n")
print(pre_post[, .(definition, treat_year,
                   n_pre, n_post,
                   pre  = round(mean_pre,  3),
                   post = round(mean_post, 3),
                   diff = round(diff,      3),
                   p    = round(p_value,   4))])

# ---------------------------------------------------------------------------
# 6. Plots: one per omega definition
# ---------------------------------------------------------------------------
base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "none")

make_plot <- function(d, title, subtitle) {
  ggplot(d, aes(x = year_first, y = mean_rank)) +
    geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi),
                alpha = 0.18, fill = "steelblue", color = NA) +
    geom_line(color = "steelblue", linewidth = 0.9) +
    geom_point(color = "steelblue", size = 1.4) +
    geom_hline(yintercept = 0.5, linetype = "dotted", color = "grey30") +
    geom_vline(xintercept = EVENT_YEARS - 0.5,
               linetype = "dashed", color = "firebrick") +
    scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
    scale_y_continuous(limits = c(0, 1),
                       labels = scales::number_format(accuracy = 0.01)) +
    labs(title = title, subtitle = subtitle,
         x = NULL,
         y = "Mean omega percentile rank within NACE4d (ETS firms)") +
    base_theme
}

p1 <- make_plot(
  yearly[definition == "Def 1: shortage/cost"],
  "New-supplier omega rank (Def 1: allowance shortage / total cost)",
  "Mean year-t percentile rank among ETS firms in same NACE4d; 95% CI; red = event years; dotted = 0.5 reference."
)
p2 <- make_plot(
  yearly[definition == "Def 2: emissions/cost"],
  "New-supplier omega rank (Def 2: emissions / total cost)",
  "Mean year-t percentile rank among ETS firms in same NACE4d; 95% CI; red = event years; dotted = 0.5 reference."
)

ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_def1.png"),
       p1, width = 9, height = 4.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_def1.pdf"),
       p1, width = 9, height = 4.5)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_def2.png"),
       p2, width = 9, height = 4.5, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_new_relationships_omega_rank_def2.pdf"),
       p2, width = 9, height = 4.5)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")

# =============================================================================
# Shared panel-builder helpers for Phase IV Test H + Test I, used by the
# robustness-program scripts (R2-R7). Sourcing this file defines:
#   build_test_h_panel()
#   build_test_i_panel()
# =============================================================================

YEAR_LO_DEFAULT <- 2005L
YEAR_HI_DEFAULT <- 2022L

build_test_h_panel <- function(year_lo = YEAR_LO_DEFAULT,
                                year_hi = YEAR_HI_DEFAULT) {
  load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
  b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                    buyer = vat_j_ano,
                                                    year,
                                                    corr_sales = corr_sales_ij)]
  b2b[, year := as.integer(year)]
  b2b <- b2b[year %between% c(year_lo, year_hi) &
               !is.na(corr_sales) & corr_sales > 0]

  load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
  aa <- as.data.table(df_annual_accounts_more_selected_sample)[
    , .(vat = vat_ano, year, nace5d)]
  aa[, year := as.integer(year)]
  aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
  aa <- unique(aa[, .(vat, year, nace4d)])
  seller_nace <- copy(aa); setnames(seller_nace, c("vat", "nace4d"),
                                    c("seller", "seller_nace4d"))
  b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
  b2b <- b2b[!is.na(seller_nace4d)]

  load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
  ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
  b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]

  contaminated_vats <- c(
    "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
    "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
    "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
  )
  b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]

  load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
  b2b <- merge(b2b,
               cost_share_regressor[, .(seller = vat,
                                         fcs_reg = firm_cost_share_regressor)],
               by = "seller", all.x = TRUE)
  b2b[is.na(fcs_reg), fcs_reg := 0]
  ets_with_fcs <- cost_share_regressor$vat
  b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

  cell_yr <- b2b[, .(n_active_sellers = .N,
                     total_sales_cell = sum(corr_sales)),
                 by = .(buyer, seller_nace4d, year)]
  ets_in_cell <- unique(b2b[seller_is_ets == 1L,
                            .(buyer, seller_nace4d, seller, fcs_reg)])
  setorder(ets_in_cell, buyer, seller_nace4d, -fcs_reg, seller)
  j_star <- ets_in_cell[, .SD[1L], by = .(buyer, seller_nace4d)]
  setnames(j_star, c("seller", "fcs_reg"), c("j_star", "fcs_j_star"))
  j_star_b2b <- merge(b2b[, .(buyer, seller_nace4d, year, seller, corr_sales)],
                      j_star, by = c("buyer", "seller_nace4d"))
  j_star_b2b <- j_star_b2b[seller == j_star]
  j_window <- j_star_b2b[, .(t_first_j_star = min(year),
                              t_last_j_star  = max(year),
                              n_years_j_star_active = uniqueN(year)),
                         by = .(buyer, seller_nace4d, j_star, fcs_j_star)]
  j_window[, is_type_a := as.integer(
    t_first_j_star == year_lo &
    t_last_j_star  == year_hi &
    n_years_j_star_active == (year_hi - year_lo + 1L))]

  j_star_sales <- j_star_b2b[, .(buyer, seller_nace4d, year,
                                  corr_sales_j_star = corr_sales)]
  panel <- cell_yr[n_active_sellers >= 2L]
  panel <- merge(panel, j_window, by = c("buyer", "seller_nace4d"))
  panel <- merge(panel, j_star_sales,
                 by = c("buyer", "seller_nace4d", "year"), all.x = TRUE)
  panel[is.na(corr_sales_j_star), corr_sales_j_star := 0]
  panel[, share_top := corr_sales_j_star / total_sales_cell]
  samp_ab <- panel[is_type_a == 1L |
                     (year >= t_first_j_star & year <= t_last_j_star)]
  samp_ab[, cell_str  := paste(buyer, seller_nace4d, sep = "_")]
  samp_ab[, sn4d_year := paste(seller_nace4d, year, sep = "_")]
  samp_ab[]
}

build_test_i_panel <- function(year_lo = YEAR_LO_DEFAULT,
                                year_hi = YEAR_HI_DEFAULT,
                                pre_lo = 2010L, pre_hi = 2014L) {
  load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
  b2b <- as.data.table(df_b2b_selected_sample)[, .(seller = vat_i_ano,
                                                    buyer  = vat_j_ano,
                                                    year,
                                                    corr_sales = corr_sales_ij)]
  b2b[, year := as.integer(year)]
  b2b <- b2b[year %between% c(year_lo, year_hi) &
               !is.na(corr_sales) & corr_sales > 0]
  load(file.path(PROC_DATA, "annual_accounts_more_selected_sample.RData"))
  aa <- as.data.table(df_annual_accounts_more_selected_sample)[
    , .(vat = vat_ano, year, nace5d, inputs_VAT)]
  aa[, year := as.integer(year)]
  aa[, nace4d := substr(sprintf("%05d", as.integer(nace5d)), 1, 4)]
  seller_nace <- unique(aa[, .(seller = vat, year, seller_nace4d = nace4d)])
  b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
  b2b <- b2b[!is.na(seller_nace4d)]
  buyer_inputs <- unique(aa[!is.na(inputs_VAT) & inputs_VAT > 0,
                             .(buyer = vat, year,
                                inputs_VAT_total = inputs_VAT)])
  load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
  ets_vats <- unique(as.data.table(firm_year_belgian_euets)$vat)
  b2b[, seller_is_ets := as.integer(seller %in% ets_vats)]
  load(file.path(PROC_DATA, "firm_cost_share_flavors.RData"))
  b2b <- merge(b2b,
               cost_share_regressor[, .(seller = vat,
                                         fcs_reg = firm_cost_share_regressor)],
               by = "seller", all.x = TRUE)
  b2b[is.na(fcs_reg), fcs_reg := 0]
  contaminated_vats <- c(
    "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
    "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
    "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
  )
  b2b <- b2b[!(seller %in% contaminated_vats & year >= 2021L)]
  ets_with_fcs <- cost_share_regressor$vat
  b2b <- b2b[!(seller_is_ets == 1L & !(seller %in% ets_with_fcs))]

  b2b_pre <- b2b[year %between% c(pre_lo, pre_hi)]
  seller_pre <- b2b_pre[, .(sales_pre = sum(corr_sales),
                             fcs_seller = max(fcs_reg)),
                         by = .(seller, seller_nace4d)]
  nace_exp <- seller_pre[, .(
    total_sales_pre        = sum(sales_pre),
    weighted_fcs_numerator = sum(sales_pre * fcs_seller)
  ), by = seller_nace4d]
  nace_exp[, nace_exposure := weighted_fcs_numerator / total_sales_pre]
  nace_exp[, nace_regulated_dummy := as.integer(nace_exposure > 0)]
  setnames(nace_exp, "seller_nace4d", "nace4d")
  buyer_year_nace <- b2b[, .(spend_bn = sum(corr_sales)),
                         by = .(buyer, nace4d = seller_nace4d, year)]
  panel <- merge(buyer_year_nace, buyer_inputs,
                 by = c("buyer", "year"), all.x = FALSE)
  panel <- merge(panel, nace_exp[, .(nace4d, nace_exposure,
                                       nace_regulated_dummy)],
                 by = "nace4d", all.x = TRUE)
  panel <- panel[!is.na(nace_exposure)]
  panel[, share := spend_bn / inputs_VAT_total]
  panel[, by_year := paste(buyer, year, sep = "_")]
  panel[, b_n     := paste(buyer, nace4d, sep = "_")]
  panel[]
}

/*==============================================================================
  _dividend_ts_full.do - Aggregate dividend income → PreTOM loser returns

  Monthly time series: does aggregate dividend income predict weaker PreTOM?

  Specs:
    1. Baseline: PreTOM loser ret ~ AggDiv (full month)
    2. With month-of-year FEs
    3. First-half dividends only (ex-date day <= 15)
    4. Lagged dividends (month t-1)
    5-8. Repeat 1-4 with market-adjusted returns

  Input:  $data/dividend_ts_full.csv
  Output: $output/dividend_ts_full.log
==============================================================================*/

clear all
set more off

if "$root" == "" global root "."
global data    "$root/data"
global output  "$root/output"

cap log close
log using "$output/dividend_ts_full.log", replace

import delimited "$data/dividend_ts_full.csv", clear
count
di "Months: " %6.0f r(N)

* Month dummies
gen month = mod(ym_num, 12) + 1
tab month, gen(m_)

* ============================================================================
* PART 1: EXCESS RETURN (VW)
* ============================================================================

di _n "{hline 70}"
di "PART 1: PreTOM LOSER EXCESS RETURN (VW)"
di "{hline 70}"

* S1: Full month dividends
di _n "--- S1: Full month AggDiv ---"
reg loser_pretom_ret_bp div_full_z, robust
di "  beta=" %7.2f _b[div_full_z] " (t=" %5.2f (_b[div_full_z]/_se[div_full_z]) ") R2=" %6.4f e(r2) " N=" %4.0f e(N)

* S2: With month FEs
di _n "--- S2: Full month AggDiv + month FEs ---"
reg loser_pretom_ret_bp div_full_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_full_z] " (t=" %5.2f (_b[div_full_z]/_se[div_full_z]) ") R2=" %6.4f e(r2)

* S3: First-half dividends only
di _n "--- S3: First-half AggDiv ---"
reg loser_pretom_ret_bp div_first_half_z, robust
di "  beta=" %7.2f _b[div_first_half_z] " (t=" %5.2f (_b[div_first_half_z]/_se[div_first_half_z]) ") R2=" %6.4f e(r2)

* S4: First-half + month FEs
di _n "--- S4: First-half AggDiv + month FEs ---"
reg loser_pretom_ret_bp div_first_half_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_first_half_z] " (t=" %5.2f (_b[div_first_half_z]/_se[div_first_half_z]) ") R2=" %6.4f e(r2)

* S5: Lagged (month t-1)
di _n "--- S5: Lagged AggDiv (t-1) ---"
reg loser_pretom_ret_bp div_lag1_z, robust
di "  beta=" %7.2f _b[div_lag1_z] " (t=" %5.2f (_b[div_lag1_z]/_se[div_lag1_z]) ") R2=" %6.4f e(r2)

* S6: Lagged + month FEs
di _n "--- S6: Lagged AggDiv (t-1) + month FEs ---"
reg loser_pretom_ret_bp div_lag1_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_lag1_z] " (t=" %5.2f (_b[div_lag1_z]/_se[div_lag1_z]) ") R2=" %6.4f e(r2)

* ============================================================================
* PART 2: MARKET-ADJUSTED RETURN (VW)
* ============================================================================

di _n "{hline 70}"
di "PART 2: PreTOM LOSER MARKET-ADJUSTED RETURN (VW)"
di "{hline 70}"

* S7: Full month
di _n "--- S7: Full month AggDiv, mkt-adj ---"
reg loser_pretom_mktadj_bp div_full_z, robust
di "  beta=" %7.2f _b[div_full_z] " (t=" %5.2f (_b[div_full_z]/_se[div_full_z]) ") R2=" %6.4f e(r2)

* S8: With month FEs
di _n "--- S8: Full month AggDiv + month FEs, mkt-adj ---"
reg loser_pretom_mktadj_bp div_full_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_full_z] " (t=" %5.2f (_b[div_full_z]/_se[div_full_z]) ") R2=" %6.4f e(r2)

* S9: First-half, mkt-adj
di _n "--- S9: First-half AggDiv, mkt-adj ---"
reg loser_pretom_mktadj_bp div_first_half_z, robust
di "  beta=" %7.2f _b[div_first_half_z] " (t=" %5.2f (_b[div_first_half_z]/_se[div_first_half_z]) ") R2=" %6.4f e(r2)

* S10: First-half + month FEs, mkt-adj
di _n "--- S10: First-half AggDiv + month FEs, mkt-adj ---"
reg loser_pretom_mktadj_bp div_first_half_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_first_half_z] " (t=" %5.2f (_b[div_first_half_z]/_se[div_first_half_z]) ") R2=" %6.4f e(r2)

* S11: Lagged, mkt-adj
di _n "--- S11: Lagged AggDiv (t-1), mkt-adj ---"
reg loser_pretom_mktadj_bp div_lag1_z, robust
di "  beta=" %7.2f _b[div_lag1_z] " (t=" %5.2f (_b[div_lag1_z]/_se[div_lag1_z]) ") R2=" %6.4f e(r2)

* S12: Lagged + month FEs, mkt-adj
di _n "--- S12: Lagged AggDiv (t-1) + month FEs, mkt-adj ---"
reg loser_pretom_mktadj_bp div_lag1_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_lag1_z] " (t=" %5.2f (_b[div_lag1_z]/_se[div_lag1_z]) ") R2=" %6.4f e(r2)

* ============================================================================
* PART 3: MARKET-ADJUSTED RETURN (EW)
* ============================================================================

di _n "{hline 70}"
di "PART 3: PreTOM LOSER MARKET-ADJUSTED RETURN (EW)"
di "{hline 70}"

* S13: Full month, EW
di _n "--- S13: Full month AggDiv, EW mkt-adj ---"
reg loser_pretom_mktadj_ew_bp div_full_z, robust
di "  beta=" %7.2f _b[div_full_z] " (t=" %5.2f (_b[div_full_z]/_se[div_full_z]) ") R2=" %6.4f e(r2)

* S14: With month FEs, EW
di _n "--- S14: Full month AggDiv + month FEs, EW mkt-adj ---"
reg loser_pretom_mktadj_ew_bp div_full_z m_1-m_11, robust
di "  beta=" %7.2f _b[div_full_z] " (t=" %5.2f (_b[div_full_z]/_se[div_full_z]) ") R2=" %6.4f e(r2)

* S15: First-half, EW
di _n "--- S15: First-half AggDiv, EW mkt-adj ---"
reg loser_pretom_mktadj_ew_bp div_first_half_z, robust
di "  beta=" %7.2f _b[div_first_half_z] " (t=" %5.2f (_b[div_first_half_z]/_se[div_first_half_z]) ") R2=" %6.4f e(r2)

* S16: Lagged, EW
di _n "--- S16: Lagged AggDiv (t-1), EW mkt-adj ---"
reg loser_pretom_mktadj_ew_bp div_lag1_z, robust
di "  beta=" %7.2f _b[div_lag1_z] " (t=" %5.2f (_b[div_lag1_z]/_se[div_lag1_z]) ") R2=" %6.4f e(r2)

di _n "Done."
log close

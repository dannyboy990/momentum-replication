/*==============================================================================
  _settlement_tables.do

  Produces the exact numbers for:
    Table 8  (T+1 Falsification Tests)
    Table 9  (T+3→T+2 Settlement DiD)

  All specs use:
    LHS: market-adjusted VW loser return (bps) = (losers_vw - mktrf) * 10000
    RHS: day indicator × post-event indicator, robust SEs
    Sample: momentum_daily.dta, 1980-2025

  Table 7 (T+1 Settlement DiD) is produced by _t1_did_earlymonth_control.do.
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\danie\Dropbox\Timing Momentum"
global data    "$root/data"
global output  "$root/output"

cap log close
log using "$output/settlement_tables.log", replace


* ══════════════════════════════════════════════════════════════════════════════
*  LOAD DATA
* ══════════════════════════════════════════════════════════════════════════════

use "$data/momentum_daily.dta", clear
gen yr = year(date)
keep if yr >= 1980

* Market-adjusted loser and winner returns in bps
gen loser_ma_bps  = (losers_vw - mktrf) * 10000
gen winner_ma_bps = (winners_vw - mktrf) * 10000

di _n "Sample: " _N " trading days, " year(date[1]) "-" year(date[_N])


* ══════════════════════════════════════════════════════════════════════════════
*  TABLE 8: T+1 FALSIFICATION TESTS
*
*  All regressions: reg loser_ma_bps day_indicator post_indicator
*                   day_indicator#post_indicator, robust
*  DiD = coefficient on interaction term.
*
*  Paper numbering: Table 8 (tab:t1_falsification)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  TABLE 8: T+1 SETTLEMENT FALSIFICATION TESTS"
di "=================================================================="

* Post-T+1 indicator (May 28, 2024)
gen byte post_t1 = (date >= td(28may2024))

* ── Real test: t=-4 vs t=-3, event = May 2024 ───────────────────────────
preserve
keep if t == -4 | t == -3

gen byte day_m4 = (t == -4)

di _n "--- REAL: Losers, T-4 vs T-3, May 2024 ---"
reg loser_ma_bps i.day_m4##i.post_t1, robust
local b_real   = _b[1.day_m4#1.post_t1]
local se_real  = _se[1.day_m4#1.post_t1]
local t_real   = `b_real' / `se_real'
local p_real   = 2 * ttail(e(df_r), abs(`t_real'))
di _n "  DiD = " %7.2f `b_real' " (t = " %5.2f `t_real' ", p = " %6.3f `p_real' ")"

* ── Placebo days: t=-6 vs t=-7, event = May 2024 ────────────────────────
restore
preserve
keep if t == -6 | t == -7

gen byte day_m6 = (t == -6)

di _n "--- PLACEBO DAYS: Losers, T-6 vs T-7, May 2024 ---"
reg loser_ma_bps i.day_m6##i.post_t1, robust
local b_plac1  = _b[1.day_m6#1.post_t1]
local se_plac1 = _se[1.day_m6#1.post_t1]
local t_plac1  = `b_plac1' / `se_plac1'
local p_plac1  = 2 * ttail(e(df_r), abs(`t_plac1'))
di _n "  DiD = " %7.2f `b_plac1' " (t = " %5.2f `t_plac1' ", p = " %6.3f `p_plac1' ")"

* ── Placebo date: t=-4 vs t=-3, fake event = May 28, 2020 ───────────────
restore
preserve
keep if t == -4 | t == -3

gen byte day_m4 = (t == -4)
gen byte post_fake_2020 = (date >= td(28may2020))

di _n "--- PLACEBO DATE: Losers, T-4 vs T-3, May 2020 ---"
reg loser_ma_bps i.day_m4##i.post_fake_2020, robust
local b_plac2  = _b[1.day_m4#1.post_fake_2020]
local se_plac2 = _se[1.day_m4#1.post_fake_2020]
local t_plac2  = `b_plac2' / `se_plac2'
local p_plac2  = 2 * ttail(e(df_r), abs(`t_plac2'))
di _n "  DiD = " %7.2f `b_plac2' " (t = " %5.2f `t_plac2' ", p = " %6.3f `p_plac2' ")"

* ── Placebo date: t=-4 vs t=-3, fake event = May 28, 2018 ───────────────
drop post_fake_2020
gen byte post_fake_2018 = (date >= td(28may2018))

di _n "--- PLACEBO DATE: Losers, T-4 vs T-3, May 2018 ---"
reg loser_ma_bps i.day_m4##i.post_fake_2018, robust
local b_plac3  = _b[1.day_m4#1.post_fake_2018]
local se_plac3 = _se[1.day_m4#1.post_fake_2018]
local t_plac3  = `b_plac3' / `se_plac3'
local p_plac3  = 2 * ttail(e(df_r), abs(`t_plac3'))
di _n "  DiD = " %7.2f `b_plac3' " (t = " %5.2f `t_plac3' ", p = " %6.3f `p_plac3' ")"

restore

* ── Summary ──────────────────────────────────────────────────────────────
di _n(2) "==============================="
di "  TABLE 8 SUMMARY"
di "==============================="
di "Real (T-4 vs T-3, May 2024):     DiD = " %7.2f `b_real'  " (t = " %5.2f `t_real'  ", p = " %5.3f `p_real'  ")"
di "Placebo days (T-6 vs T-7):       DiD = " %7.2f `b_plac1' " (t = " %5.2f `t_plac1' ", p = " %5.3f `p_plac1' ")"
di "Placebo date (May 2020):         DiD = " %7.2f `b_plac2' " (t = " %5.2f `t_plac2' ", p = " %5.3f `p_plac2' ")"
di "Placebo date (May 2018):         DiD = " %7.2f `b_plac3' " (t = " %5.2f `t_plac3' ", p = " %5.3f `p_plac3' ")"


* ══════════════════════════════════════════════════════════════════════════════
*  TABLE 9: T+3→T+2 SETTLEMENT DiD
*
*  Same pair as T+1 test (t=-4 vs t=-3), but event = Sep 5, 2017.
*  Prediction: DiD ≈ 0 (mismatch reduced but not eliminated at T+2).
*
*  Paper numbering: Table 9 (tab:t2_settlement)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  TABLE 9: T+3→T+2 SETTLEMENT DiD"
di "=================================================================="

* Post-T+2 indicator (Sep 5, 2017)
gen byte post_t2 = (date >= td(05sep2017))

preserve
keep if t == -4 | t == -3

gen byte day_m4 = (t == -4)

* ── Panel A: 2×2 cell means ──────────────────────────────────────────────
di _n "--- PANEL A: Cell Means ---"
di "              Pre-T+2          Post-T+2"
foreach d in 0 1 {
    local dlab = cond(`d' == 1, "T-4", "T-3")
    qui sum loser_ma_bps if day_m4 == `d' & post_t2 == 0, meanonly
    local pre = r(mean)
    local npre = r(N)
    qui sum loser_ma_bps if day_m4 == `d' & post_t2 == 1, meanonly
    local post = r(mean)
    local npost = r(N)
    di "`dlab':  " %8.2f `pre' " (n=" `npre' ")    " %8.2f `post' " (n=" `npost' ")"
}

* ── Panel B: DiD regression ──────────────────────────────────────────────
di _n "--- PANEL B: DiD Regression ---"
reg loser_ma_bps i.day_m4##i.post_t2, robust

local b_t2   = _b[1.day_m4#1.post_t2]
local se_t2  = _se[1.day_m4#1.post_t2]
local t_t2   = `b_t2' / `se_t2'
local p_t2   = 2 * ttail(e(df_r), abs(`t_t2'))

di _n "==============================="
di "  TABLE 9 SUMMARY"
di "==============================="
di "1[t=-4]:                " %7.2f _b[1.day_m4]           " (SE = " %5.2f _se[1.day_m4]           ")"
di "Post T+2:               " %7.2f _b[1.post_t2]          " (SE = " %5.2f _se[1.post_t2]          ")"
di "1[t=-4] x Post T+2:    " %7.2f `b_t2'                  " (t = " %5.2f `t_t2' ", p = " %5.3f `p_t2' ")"
di "Constant:               " %7.2f _b[_cons]               " (SE = " %5.2f _se[_cons]               ")"
di "N = " e(N) ", R2 = " %6.4f e(r2)

restore


di _n(3) "=================================================================="
di "  ALL SETTLEMENT TABLE NUMBERS COMPLETE"
di "=================================================================="

log close

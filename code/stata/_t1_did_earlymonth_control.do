/*==============================================================================
  _t1_did_earlymonth_control.do

  Unified T+1 DiD with early-month days [T+5, T+8] as control.
  These days have no settlement-related selling or reversal.

  Portfolio: collapse [T+5,T+8] to a single mean per month, then run
  the unified spec with T-4, T-3, and early-month control.

  Stock-level: firm+date FE, VW.
==============================================================================*/
clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global output  "$root/output"


* ══════════════════════════════════════════════════════════════════════════════
*  PORTFOLIO LEVEL
* ══════════════════════════════════════════════════════════════════════════════

use "$data\momentum_daily.dta", clear
gen yr = year(date)
keep if yr >= 1980
gen loser_ma_bps = (losers_vw - mktrf) * 10000
gen byte post_t1 = (date >= td(28may2024))

* Keep T-4, T-3, and early-month [T+5 to T+8]
keep if t == -4 | t == -3 | (t >= 5 & t <= 8)

* Create a group variable: 1=early-month (control), 2=T-3, 3=T-4
gen byte daygroup = 0
replace daygroup = 1 if t >= 5 & t <= 8   /* early-month control */
replace daygroup = 2 if t == -3
replace daygroup = 3 if t == -4

* Collapse early-month days to monthly means so each month has one obs per group
* First collapse [T+5,T+8] within each ym
collapse (mean) loser_ma_bps post_t1, by(ym daygroup)

* Dummies (early-month = omitted)
gen byte d_m4 = (daygroup == 3)
gen byte d_m3 = (daygroup == 2)
gen d_m4_post = d_m4 * post_t1
gen d_m3_post = d_m3 * post_t1

* --- Full 1980+ ---
di _n _n "**************************************************************"
di "PORTFOLIO: T-4/T-3 vs early-month [T+5,T+8] control (1980+)"
di "**************************************************************"

di _n "--- Cell Means ---"
di "              Pre-T+1          Post-T+1"
foreach g in 1 2 3 {
    local glab "Early-month"
    if `g' == 2 local glab "T-3"
    if `g' == 3 local glab "T-4"
    qui sum loser_ma_bps if daygroup == `g' & post_t1 == 0, meanonly
    local pre = r(mean)
    local npre = r(N)
    qui sum loser_ma_bps if daygroup == `g' & post_t1 == 1, meanonly
    local post = r(mean)
    local npost = r(N)
    di "`glab':  " %8.2f `pre' " (n=" `npre' ")    " %8.2f `post' " (n=" `npost' ")"
}

reg loser_ma_bps d_m4 d_m3 post_t1 d_m4_post d_m3_post, robust
estimates store ptf_full

di _n "KEY COEFFICIENTS (1980+):"
di "  b4 (T-4 vs early-month DiD): " %7.2f _b[d_m4_post] " (t=" %5.2f (_b[d_m4_post]/_se[d_m4_post]) ")"
di "  b5 (T-3 vs early-month DiD): " %7.2f _b[d_m3_post] " (t=" %5.2f (_b[d_m3_post]/_se[d_m3_post]) ")"

lincom d_m4_post - d_m3_post
di "  b4-b5 (full shift):          " %7.2f r(estimate) " (t=" %5.2f (r(estimate)/r(se)) ", p=" %6.4f r(p) ")"


* --- T+2 era only ---
di _n _n "**************************************************************"
di "PORTFOLIO: T+2 era only (Sep 2017+)"
di "**************************************************************"

preserve
keep if ym >= ym(2017,9)

reg loser_ma_bps d_m4 d_m3 post_t1 d_m4_post d_m3_post, robust
estimates store ptf_t2era

di _n "KEY COEFFICIENTS (T+2 era):"
di "  b4 (T-4 vs early-month DiD): " %7.2f _b[d_m4_post] " (t=" %5.2f (_b[d_m4_post]/_se[d_m4_post]) ")"
di "  b5 (T-3 vs early-month DiD): " %7.2f _b[d_m3_post] " (t=" %5.2f (_b[d_m3_post]/_se[d_m3_post]) ")"

lincom d_m4_post - d_m3_post
di "  b4-b5 (full shift):          " %7.2f r(estimate) " (t=" %5.2f (r(estimate)/r(se)) ", p=" %6.4f r(p) ")"

restore

esttab ptf_full ptf_t2era, ///
    keep(d_m4 d_m3 post_t1 d_m4_post d_m3_post) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Full (1980+)" "T+2 era (Sep 2017+)") ///
    stats(N r2, labels("N" "R2") fmt(%8.0fc %9.4f)) ///
    title("Unified T+1 DiD: Early-month [T+5,T+8] as control") ///
    coeflabel(d_m4 "1[T=-4]" d_m3 "1[T=-3]" post_t1 "PostT1" ///
              d_m4_post "1[T=-4] x PostT1" d_m3_post "1[T=-3] x PostT1") ///
    nonotes


* ══════════════════════════════════════════════════════════════════════════════
*  STOCK LEVEL
* ══════════════════════════════════════════════════════════════════════════════

clear
import delimited "$data/panel_fixed_vw_reg.csv", clear
gen stata_date = date(date, "YMD")
format stata_date %td
drop date
rename stata_date date
cap rename permno PERMNO
cap rename PERMNO permno
keep if decile == 1 | decile == 10
gen r_e_bp = ret_rf * 10000
gen post_t1 = (date >= td(28may2024))

* Keep T-4, T-3, and early-month [T+5 to T+8]
keep if t == -4 | t == -3 | (t >= 5 & t <= 8)

* Dummies (early-month = omitted)
gen d_m4 = (t == -4)
gen d_m3 = (t == -3)
gen d_m4_post = d_m4 * post_t1
gen d_m3_post = d_m3 * post_t1

gen loser_m4 = loser * d_m4
gen loser_m3 = loser * d_m3
gen loser_post = loser * post_t1
gen loser_m4_post = loser * d_m4 * post_t1
gen loser_m3_post = loser * d_m3 * post_t1

* --- Full 1980+ ---
di _n _n "**************************************************************"
di "STOCK-LEVEL: T-4/T-3 vs early-month [T+5,T+8], firm+date FE, VW (1980+)"
di "**************************************************************"

reghdfe r_e_bp loser d_m4 d_m3 loser_m4 loser_m3 ///
    post_t1 loser_post d_m4_post d_m3_post ///
    loser_m4_post loser_m3_post [aw=w_l1], ///
    absorb(permno date) cluster(date)

di _n "KEY (stock-level, 1980+):"
di "  Loser x T-4 x Post (b4):    " %7.2f _b[loser_m4_post] " (t=" %5.2f (_b[loser_m4_post]/_se[loser_m4_post]) ")"
di "  Loser x T-3 x Post (b5):    " %7.2f _b[loser_m3_post] " (t=" %5.2f (_b[loser_m3_post]/_se[loser_m3_post]) ")"

lincom loser_m4_post - loser_m3_post
di "  b4-b5 (full shift):         " %7.2f r(estimate) " (t=" %5.2f (r(estimate)/r(se)) ", p=" %6.4f r(p) ")"


di _n _n "ALL TESTS COMPLETE"

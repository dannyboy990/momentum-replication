/*==============================================================================
  _crash_days_by_window.do

  Do momentum crash days concentrate in [t+1,t+3]?
  Table + figure showing crash day distribution across calendar windows.

  Full sample 1980-2025, include December.
  Input:  $data\momentum_daily.dta
  Output: $output\crash_days_by_window.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output/crash_days_by_window.log", replace

use "$data/momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980

gen wml_bps = wml_vw * 10000

gen byte window = 3
replace window = 1 if t >= -9 & t <= -4
replace window = 2 if t >= 1  & t <= 3

* Window shares of total days
qui count
local N_total = r(N)
qui count if window == 1
local N_1 = r(N)
local share_1 = `N_1' / `N_total'
qui count if window == 2
local N_2 = r(N)
local share_2 = `N_2' / `N_total'
qui count if window == 3
local N_3 = r(N)
local share_3 = `N_3' / `N_total'

di "Total days: " `N_total'
di "PreTOM: " `N_1' " (" %4.1f `share_1'*100 "%)"
di "Month-start: " `N_2' " (" %4.1f `share_2'*100 "%)"
di "Other: " `N_3' " (" %4.1f `share_3'*100 "%)"

* ── Table ─────────────────────────────────────────────────────────────────

di _n "{hline 80}"
di "CRASH DAY CONCENTRATION BY CALENDAR WINDOW"
di "{hline 80}"
di ""
di %20s "" %18s "PreTOM" %18s "Month-start" %18s "Other"
di %20s "" %18s "[t-9,t-4]" %18s "[t+1,t+3]" %18s ""
di "{hline 80}"
di %20s "Share of all days" %17.1f `share_1'*100 "%" %17.1f `share_2'*100 "%" %17.1f `share_3'*100 "%"
di "{hline 80}"

* Store results for figure
* Two comparisons per threshold:
*   (A) PreTOM vs Other, excluding month-start (window=1 vs 3)
*   (B) Month-start vs Other, excluding PreTOM (window=2 vs 3)
tempfile fig_data
postfile fighandle threshold comparison actual expected ratio frac n_crash ///
    using `fig_data', replace

* (A) Calendar shares excluding month-start
local N_exms = `N_1' + `N_3'
local share_exms_1 = `N_1' / `N_exms'

* (B) Calendar shares excluding PreTOM
local N_expt = `N_2' + `N_3'
local share_expt_2 = `N_2' / `N_expt'

di _n "Ex month-start: total days = `N_exms', PreTOM share = " %5.1f `share_exms_1'*100 "%"
di "Ex PreTOM: total days = `N_expt', Month-start share = " %5.1f `share_expt_2'*100 "%"

foreach thresh in 100 200 300 {
    * (A) PreTOM vs Other, ex month-start
    qui count if wml_bps < -`thresh' & window != 2
    local n_crash_a = r(N)
    qui count if wml_bps < -`thresh' & window == 1
    local actual_a = r(N)
    local frac_a = `actual_a' / `n_crash_a'
    local expected_a = `n_crash_a' * `share_exms_1'
    local ratio_a = `actual_a' / `expected_a'

    di _n "WML < -`thresh' bps, PreTOM ex month-start (N=" `n_crash_a' ")"
    di "  actual=" %4.0f `actual_a' "  expected=" %5.1f `expected_a' ///
       "  frac=" %5.1f `frac_a'*100 "%  ratio=" %5.2f `ratio_a'

    * comparison=1 for PreTOM vs Other
    post fighandle (`thresh') (1) (`actual_a') (`expected_a') (`ratio_a') (`frac_a') (`n_crash_a')

    * (B) Month-start vs Other, ex PreTOM
    qui count if wml_bps < -`thresh' & window != 1
    local n_crash_b = r(N)
    qui count if wml_bps < -`thresh' & window == 2
    local actual_b = r(N)
    local frac_b = `actual_b' / `n_crash_b'
    local expected_b = `n_crash_b' * `share_expt_2'
    local ratio_b = `actual_b' / `expected_b'

    di "WML < -`thresh' bps, Month-start ex PreTOM (N=" `n_crash_b' ")"
    di "  actual=" %4.0f `actual_b' "  expected=" %5.1f `expected_b' ///
       "  frac=" %5.1f `frac_b'*100 "%  ratio=" %5.2f `ratio_b'

    * comparison=2 for Month-start vs Other
    post fighandle (`thresh') (2) (`actual_b') (`expected_b') (`ratio_b') (`frac_b') (`n_crash_b')
}

postclose fighandle

* ── Figure: Crash concentration (dots + whiskers) ────────────────────

use `fig_data', clear

* 95% CI for the ratio
gen se_frac = sqrt(frac * (1 - frac) / n_crash)
gen p_exp = expected / n_crash
gen se_ratio = se_frac / p_exp
gen ratio_lo = ratio - 1.96 * se_ratio
gen ratio_hi = ratio + 1.96 * se_ratio

* x-positions: 3 thresholds × 2 comparisons
gen x = .
replace x = 1 - 0.15 if threshold == 100 & comparison == 1
replace x = 1 + 0.15 if threshold == 100 & comparison == 2
replace x = 2 - 0.15 if threshold == 200 & comparison == 1
replace x = 2 + 0.15 if threshold == 200 & comparison == 2
replace x = 3 - 0.15 if threshold == 300 & comparison == 1
replace x = 3 + 0.15 if threshold == 300 & comparison == 2

twoway (bar ratio x if comparison == 1, ///
            barwidth(0.25) fcolor(white) lcolor(black) lwidth(medthick)) ///
       (rcap ratio_lo ratio_hi x if comparison == 1, lcolor(black) lwidth(medthick)) ///
       (bar ratio x if comparison == 2, ///
            barwidth(0.25) fcolor(gs4) lcolor(gs4) lwidth(medthick)) ///
       (rcap ratio_lo ratio_hi x if comparison == 2, lcolor(gs4) lwidth(medthick)), ///
    yline(1, lcolor(gs8) lpattern(dash) lwidth(medium)) ///
    xlabel(1 `""WML < {&minus}100""bps""' ///
           2 `""WML < {&minus}200""bps""' ///
           3 `""WML < {&minus}300""bps""', labsize(medsmall)) ///
    ylabel(0.6(0.2)1.8, labsize(medsmall) angle(0)) ///
    xtitle("") ///
    ytitle("Crash day concentration (actual / expected)", size(medsmall)) ///
    title("") ///
    legend(order(1 "PreTOM vs. rest (ex month-start)" ///
                 3 "Month-start vs. rest (ex PreTOM)") ///
           ring(1) pos(6) rows(1) size(small)) ///
    xscale(range(0.5 3.5)) ///
    scheme(s2color) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    xsize(7) ysize(4.5) ///
    note("Whiskers show 95% confidence intervals. Dashed line: ratio = 1 (uniform distribution).", size(small))

graph export "$fig/crash_days_by_window.pdf", replace
graph export "$fig/crash_days_by_window.png", width(2400) replace
graph export "$root/Paper/Figures/crash_days_by_window.pdf", replace

* ── Proportions z-tests ──────────────────────────────────────────────────

di _n "{hline 80}"
di "PROPORTIONS Z-TESTS: CRASH DAY CONCENTRATION"
di "{hline 80}"
di ""
di "H0: fraction of crash days in window = fraction of all days in window"
di "z = (p_obs - p_exp) / sqrt(p_exp * (1 - p_exp) / n_crashes)"
di ""
di %20s "" %18s "PreTOM" %18s "Month-start" %18s "Other"
di %20s "" %18s "[t-9,t-4]" %18s "[t+1,t+3]" %18s ""
di "{hline 80}"

use "$data/momentum_daily.dta", clear
gen yr = year(date)
keep if yr >= 1980
gen wml_bps = wml_vw * 10000

gen byte window = 3
replace window = 1 if t >= -9 & t <= -4
replace window = 2 if t >= 1  & t <= 3

* Window shares
qui count
local N_total = r(N)
qui count if window == 1
local share_1 = r(N) / `N_total'
qui count if window == 2
local share_2 = r(N) / `N_total'
qui count if window == 3
local share_3 = r(N) / `N_total'

foreach thresh in 100 200 300 {
    qui count if wml_bps < -`thresh'
    local n_crash = r(N)

    di _n "WML < -`thresh' bps (N = `n_crash' crash days)"

    foreach w in 1 2 3 {
        qui count if wml_bps < -`thresh' & window == `w'
        local actual = r(N)
        local p_obs = `actual' / `n_crash'
        local p_exp = `share_`w''
        local z = (`p_obs' - `p_exp') / sqrt(`p_exp' * (1 - `p_exp') / `n_crash')
        local pval = 2 * (1 - normal(abs(`z')))

        local wname "PreTOM"
        if `w' == 2 local wname "Month-start"
        if `w' == 3 local wname "Other"

        local stars ""
        if `pval' < 0.10 local stars "*"
        if `pval' < 0.05 local stars "**"
        if `pval' < 0.01 local stars "***"

        di %20s "`wname'" ///
            "  p_obs=" %5.1f `p_obs'*100 "%" ///
            "  p_exp=" %5.1f `p_exp'*100 "%" ///
            "  z=" %6.2f `z' ///
            "  p=" %6.4f `pval' " `stars'"
    }
}

di _n "{hline 80}"

log close

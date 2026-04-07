/*==============================================================================
  _rolling_window_correct.do

  Rolling 6-day window test with correct day computation.
  Uses exact rank from month-end within each month (t_end = _n - _N).
  Raw means with Newey-West SEs on monthly collapsed means.

  X-axis: window start from -20 to -5.
  Window at -5 covers [-5, 0] = last 6 days.
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output/rolling_window_correct.log", replace text

use "$data/momentum_daily.dta", clear
gen yr = year(date)
keep if yr >= 1980

gen loser_raw_bp = losers_vw * 10000

* Correct position from month-end: 0 = last day, -1 = second to last, etc.
bysort ym (date): gen t_end = _n - _N

qui sum t_end
di "t_end ranges from " r(min) " to " r(max)

* Window parameters
local wstart = -20
local wend   = -5
local nwin   = `wend' - `wstart' + 1
di "Number of windows: `nwin'"

tempfile results maindata
save `maindata'

clear
set obs `nwin'
gen t_start = _n + `wstart' - 1
gen t_endw = t_start + 5
gen coeff = .
gen se = .
gen tstat = .
gen lb = .
gen ub = .
gen byte is_pretom = 0
gen nobs_months = .
save `results'

forvalues ts = `wstart'/`wend' {
    local row = `ts' - `wstart' + 1
    local te = `ts' + 5

    use `maindata', clear
    keep if t_end >= `ts' & t_end <= `te'

    collapse (mean) mean_ret = loser_raw_bp (count) ndays = loser_raw_bp, by(ym)
    keep if ndays == 6

    qui count
    if r(N) < 10 continue

    sort ym
    gen _t = _n
    tsset _t
    qui newey mean_ret, lag(5)
    local b = _b[_cons]
    local se_val = _se[_cons]
    local t_val = `b' / `se_val'
    local n = e(N)

    use `results', clear
    qui replace coeff = `b' in `row'
    qui replace se = `se_val' in `row'
    qui replace tstat = `t_val' in `row'
    qui replace lb = `b' - 1.96 * `se_val' in `row'
    qui replace ub = `b' + 1.96 * `se_val' in `row'
    qui replace nobs_months = `n' in `row'
    if `ts' == -9 {
        qui replace is_pretom = 1 in `row'
    }
    qui save `results', replace
}

use `results', clear
drop if coeff == .

di _n "=== RAW MEAN LOSER-MARKET RETURN BY 6-DAY WINDOW ==="
di "=== Correct t_end computation. Newey-West SEs (5 lags). ==="
di "  t_start  t_end   mean       NW-SE    t-stat   months"
di "  ------  -----  --------  --------  --------  ------"
forvalues i = 1/`=_N' {
    local ts_i = t_start[`i']
    local te_i = t_endw[`i']
    local c_i = coeff[`i']
    local se_i = se[`i']
    local t_i = tstat[`i']
    local n_i = nobs_months[`i']
    local flag = cond(is_pretom[`i'], " *** PreTOM", "")
    di "  " %6.0f `ts_i' %6.0f `te_i' "  " %8.2f `c_i' "  " %8.2f `se_i' "  " %8.2f `t_i' "  " %5.0f `n_i' "`flag'"
}

gsort coeff
di _n "Most negative: t_start=" t_start[1] " mean=" %7.2f coeff[1] " bp/day (t=" %5.2f tstat[1] ")"

sort t_start

twoway (rarea ub lb t_start, color(gs12%40) lwidth(none)) ///
       (rarea ub lb t_start if is_pretom == 1, color(cranberry%30) lwidth(none)) ///
       (connected coeff t_start, msymbol(circle) msize(small) ///
            mcolor(gs6) lcolor(gs6) lwidth(medthin)) ///
       (scatter coeff t_start if is_pretom == 1, msymbol(diamond) msize(medlarge) ///
            mcolor(cranberry)), ///
       yline(0, lcolor(black) lwidth(thin)) ///
       xlabel(-20(1)-5, labsize(small)) ///
       xtitle("Window start (trading day relative to month-end)") ///
       ytitle("Mean loser excess return (bp/day)") ///
       title("Loser underperformance across rolling 6-day windows", size(medium)) ///
       legend(order(3 "Other windows" 4 "PreTOM [{it:t}={&minus}9 to {it:t}={&minus}4]") ///
              ring(1) pos(6) rows(1) size(small)) ///
       scheme(s1mono) ///
       note("Mean VW loser-market return per 6-day window. Only months with all 6 days" ///
            "in the window included. Newey-West SEs (5 lags) on monthly means. 1980-2025.")

graph export "$fig/rolling_window_correct.pdf", replace
graph export "$fig/rolling_window_correct.png", replace width(1600)

di _n "Done."
log close

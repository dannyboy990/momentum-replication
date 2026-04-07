/*==============================================================================
  _killer_figure.do

  Dual-axis figure: mean daily WML (left axis) + crash probability (right axis)
  by trading day t. Vertical dashed lines mark window boundaries.

  Full sample 1980-2025, include December.
  Input:  $data/momentum_daily.dta
  Output: $fig/killer_figure.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output/killer_figure.log", replace

use "$data/momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980

gen wml_bps = wml_vw * 10000

* ── Compute stats by trading day t ──────────────────────────────────────

* Crash indicator
gen crash200 = (wml_bps < -200)

* Store results
tempfile stats
postfile handle t mean_wml nw_se crash_prob n ///
    using `stats', replace

levelsof t, local(tvals)

foreach tv of local tvals {
    * Mean, SD, N
    qui sum wml_bps if t == `tv'
    local m = r(mean)
    local nn = r(N)

    * Newey-West SE
    preserve
    keep if t == `tv'
    gen seq = _n
    tsset seq
    qui newey wml_bps, lag(5)
    local nw_se = _se[_cons]
    restore

    * Crash probability
    qui sum crash200 if t == `tv'
    local cp = r(mean)

    di "t=" %3.0f `tv' "  mean=" %7.2f `m' "  NW-SE=" %6.2f `nw_se' ///
        "  crash_prob=" %6.4f `cp' "  N=" `nn'

    post handle (`tv') (`m') (`nw_se') (`cp') (`nn')
}

postclose handle

* ── Build plotting dataset ──────────────────────────────────────────────

use `stats', clear

sort t

gen ci_lo = mean_wml - 1.96 * nw_se
gen ci_hi = mean_wml + 1.96 * nw_se

* Crash probability in percent for readability
gen crash_pct = crash_prob * 100

* Restrict to t in [-9, 10]
keep if t >= -9 & t <= 10

* ── Summary table ───────────────────────────────────────────────────────

di _n "{hline 70}"
di "MEAN WML AND CRASH PROBABILITY BY TRADING DAY"
di "{hline 70}"
list t mean_wml nw_se ci_lo ci_hi crash_pct, noobs clean

* ── Figure: Two stacked panels, shared x-axis ──────────────────────────
* Panel A (top): Mean WML + 95% NW confidence band
* Panel B (bottom): Crash probability bars
* Dashed boundary lines run through both panels. Fully B&W.

* --- Panel A: Mean WML ---
twoway (rarea ci_lo ci_hi t, ///
            color(gs14%50) lwidth(none)) ///
       (line mean_wml t, ///
            lcolor(black) lwidth(thick) lpattern(solid)), ///
    xline(-9.5 -3.5, lcolor(black) lpattern(dash) lwidth(thin)) ///
    xline(0.5 3.5, lcolor(black) lpattern(dash) lwidth(thin)) ///
    yline(0, lcolor(gs6) lwidth(thin)) ///
    xscale(range(-9.5 10.5)) ///
    xlabel(-9(1)10, labsize(vsmall) angle(0)) ///
    ylabel(-40(10)40, labsize(small) angle(0)) ///
    yscale(range(-40 40)) ///
    xtitle("") ///
    ytitle("Mean WML (bps)", size(small)) ///
    title("{bf:A.} Mean daily WML return", size(medsmall) position(11)) ///
    text(28 -6.5 "PreTOM", size(small) color(black)) ///
    text(28 2 "Month-start", size(small) color(black)) ///
    legend(order(2 "Mean WML" 1 "95% NW CI") ///
           ring(1) pos(6) rows(1) size(vsmall) ///
           region(lcolor(gs12) fcolor(white))) ///
    scheme(s2color) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(panel_a, replace)

* --- Panel B: Crash probability ---
twoway (bar crash_pct t, ///
            barwidth(0.6) fcolor(gs9) lcolor(black) lwidth(vthin)), ///
    xline(-9.5 -3.5, lcolor(black) lpattern(dash) lwidth(thin)) ///
    xline(0.5 3.5, lcolor(black) lpattern(dash) lwidth(thin)) ///
    xscale(range(-9.5 10.5)) ///
    xlabel(-9(1)10, labsize(vsmall) angle(0)) ///
    ylabel(0(2)12, labsize(small) angle(0)) ///
    yscale(range(0 13)) ///
    xtitle("Trading day relative to month-end ({it:t})", size(small)) ///
    ytitle("P(WML < {&minus}200 bps) %", size(small)) ///
    title("{bf:B.} Crash probability", size(medsmall) position(11)) ///
    legend(off) ///
    scheme(s2color) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(panel_b, replace)

* --- Combine ---
graph combine panel_a panel_b, ///
    cols(1) ///
    imargin(zero) ///
    graphregion(color(white)) ///
    xsize(7) ysize(7)

graph export "$fig/killer_figure.pdf", replace
graph export "$fig/killer_figure.png", width(2400) replace
graph export "$root/Paper/Figures/killer_figure.pdf", replace

log close

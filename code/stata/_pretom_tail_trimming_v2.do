/*==============================================================================
  _pretom_tail_trimming_v2.do

  Panel A: Dot-and-whisker — mean daily WML by window (untrimmed) with CIs
  Panel B: Line chart — mean daily WML across trimming levels (0,1,5,10%)

  Fully B&W friendly.
  Full sample 1980-2025, include December.
  Input:  $data/momentum_daily.dta
  Output: $fig/pretom_tail_trimming.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output/pretom_tail_trimming_v2.log", replace

use "$data/momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980

gen wml_bps = wml_vw * 10000

gen byte window = 3
replace window = 1 if t >= -9 & t <= -4
replace window = 2 if t >= 1  & t <= 3

* Global percentiles for trimming
qui sum wml_bps, detail
local p1  = r(p1)
local p5  = r(p5)
local p10 = r(p10)

* ── Compute stats for all trim × window combos ───────────────────────────

tempfile results
postfile handle trim_pct window mean_wml se_nw sd_wml n ///
    using `results', replace

foreach trim in 0 1 5 10 {
    if `trim' == 0 local cutoff = -99999
    if `trim' == 1 local cutoff = `p1'
    if `trim' == 5 local cutoff = `p5'
    if `trim' == 10 local cutoff = `p10'

    foreach w in 1 2 3 {
        qui sum wml_bps if window == `w' & wml_bps > `cutoff'
        local m = r(mean)
        local s = r(sd)
        local nn = r(N)

        preserve
        keep if window == `w' & wml_bps > `cutoff'
        gen seq = _n
        tsset seq
        qui newey wml_bps, lag(5)
        local nw_se = _se[_cons]
        restore

        post handle (`trim') (`w') (`m') (`nw_se') (`s') (`nn')
    }
}

postclose handle

* ── Build plotting data ───────────────────────────────────────────────────

use `results', clear

gen ci_lo = mean_wml - 1.96 * se_nw
gen ci_hi = mean_wml + 1.96 * se_nw

* ══════════════════════════════════════════════════════════════════════════
*  PANEL A: Dot-and-whisker at 0% trimming (B&W)
* ══════════════════════════════════════════════════════════════════════════

preserve
keep if trim_pct == 0

twoway (scatter mean_wml window, ///
            msymbol(O) msize(large) mcolor(black) mfcolor(white) mlwidth(thick)) ///
       (rcap ci_lo ci_hi window, lcolor(black) lwidth(medthick)), ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xlabel(1 "PreTOM" 2 "Month-start" 3 "Other", labsize(medsmall)) ///
    ylabel(-15(5)20, labsize(small) angle(0)) ///
    xscale(range(0.5 3.5)) ///
    xtitle("") ///
    ytitle("Mean daily WML return (bps)", size(small)) ///
    title("{bf:A.} Untrimmed daily WML by window", size(medsmall) position(11)) ///
    legend(off) ///
    scheme(s2color) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(panelA, replace)

restore

* ══════════════════════════════════════════════════════════════════════════
*  PANEL B: Line chart across trimming levels (B&W)
* ══════════════════════════════════════════════════════════════════════════

reshape wide mean_wml se_nw sd_wml n ci_lo ci_hi, i(trim_pct) j(window)

* Small x-offsets so CIs don't overlap
gen x1 = trim_pct - 0.15
gen x2 = trim_pct
gen x3 = trim_pct + 0.15

twoway (connected mean_wml1 x1, lcolor(black) mcolor(black) ///
            msymbol(O) msize(medlarge) lwidth(thick) lpattern(solid)) ///
       (rcap ci_lo1 ci_hi1 x1, lcolor(gs8) lwidth(thin)) ///
       (connected mean_wml2 x2, lcolor(black) mcolor(black) ///
            msymbol(S) msize(medlarge) lwidth(thick) lpattern(dash)) ///
       (rcap ci_lo2 ci_hi2 x2, lcolor(gs8) lwidth(thin)) ///
       (connected mean_wml3 x3, lcolor(gs8) mcolor(gs8) ///
            msymbol(T) msize(medlarge) lwidth(medium) lpattern(shortdash)) ///
       (rcap ci_lo3 ci_hi3 x3, lcolor(gs11) lwidth(thin)), ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xlabel(0 "0%" 1 "1%" 5 "5%" 10 "10%", labsize(small)) ///
    xtitle("Left-tail trimming (worst x% of daily WML removed)", size(small)) ///
    ytitle("Mean daily WML return (bps)", size(small)) ///
    ylabel(, labsize(small) angle(0)) ///
    title("{bf:B.} Effect of tail trimming on WML by window", size(medsmall) position(11)) ///
    legend(order(1 "PreTOM [{it:t}{&minus}9, {it:t}{&minus}4]" ///
                 3 "Month-start [{it:t}+1, {it:t}+3]" ///
                 5 "Other days") ///
           ring(0) pos(11) cols(1) size(small) ///
           region(lcolor(gs12) fcolor(white))) ///
    scheme(s2color) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(panelB, replace)

* ── Combine ───────────────────────────────────────────────────────────────

graph combine panelA panelB, cols(1) ///
    graphregion(color(white)) ///
    imargin(small) ///
    xsize(7) ysize(9)

graph export "$fig/pretom_tail_trimming.pdf", replace
graph export "$fig/pretom_tail_trimming.png", width(2400) replace
graph export "$root/Paper/Figures/pretom_tail_trimming.pdf", replace

log close

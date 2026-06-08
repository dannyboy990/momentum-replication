/*==============================================================================
  _appendix_daily_decomp.do

  Appendix Figure: Mean daily excess returns of losers and winners by
  trading day t across the month. Two-panel bar chart with SE whiskers.

  Input:  $data\momentum_daily.dta
  Output: $output\appendix_daily_decomp.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\_appendix_daily_decomp.log", replace

use "$data\momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980

* Returns in bps (excess of rf)
gen losers_bps  = losers_vw  * 10000
gen winners_bps = winners_vw * 10000

* Restrict to t in [-9, 10] - covers full month, drops sparse t=11..13
keep if t >= -9 & t <= 10

* Collapse to mean and SD by trading day t
collapse (mean) losers_mean=losers_bps winners_mean=winners_bps ///
         (sd) losers_sd=losers_bps winners_sd=winners_bps ///
         (count) n=losers_bps, by(t)

* Standard errors and 95% CI
gen losers_se  = losers_sd  / sqrt(n)
gen winners_se = winners_sd / sqrt(n)

gen losers_hi  = losers_mean  + 1.96 * losers_se
gen losers_lo  = losers_mean  - 1.96 * losers_se
gen winners_hi = winners_mean + 1.96 * winners_se
gen winners_lo = winners_mean - 1.96 * winners_se

sort t

* Display
di _n "{hline 50}"
di "Mean daily excess return by trading day t (bps)"
di "{hline 50}"
di "   t     Losers    (SE)     Winners   (SE)"
forvalues i = 1/`=_N' {
    di %5.0f t[`i'] %10.2f losers_mean[`i'] %8.2f losers_se[`i'] ///
       %10.2f winners_mean[`i'] %8.2f winners_se[`i']
}

* Color coding: PreTOM days in dark navy, others in light gray
gen pretom = (t >= -9 & t <= -4)

* Panel A: Losers
gen loser_pretom = losers_mean if pretom == 1
gen loser_other  = losers_mean if pretom == 0

twoway (bar loser_pretom t, barwidth(0.8) color(navy%90) lcolor(navy) lwidth(thin)) ///
       (bar loser_other  t, barwidth(0.8) color(gs13) lcolor(gs10) lwidth(thin)) ///
       (rcap losers_hi losers_lo t, lcolor(gs5) lwidth(thin)), ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-9.5, lcolor(black) lpattern(dash) lwidth(medthick)) ///
    xline(-3.5, lcolor(black) lpattern(dash) lwidth(medthick)) ///
    xlabel(-9(1)10, labsize(vsmall) angle(0)) ///
    ylabel(-20(5)15, labsize(small) format(%4.0f)) ///
    yscale(range(-20 15)) ///
    xtitle("Trading day relative to month-end, T=0 (last trading day)", size(small)) ///
    ytitle("Mean daily excess return (bps)", size(small)) ///
    title("Panel A: Losers (Decile 1)", size(medium)) ///
    legend(order(1 "PreTOM [T{&minus}9, T{&minus}4]" 2 "Other days") ///
           ring(0) pos(5) cols(1) size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(losers, replace)

* Panel B: Winners
gen winner_pretom = winners_mean if pretom == 1
gen winner_other  = winners_mean if pretom == 0

twoway (bar winner_pretom t, barwidth(0.8) color(navy%90) lcolor(navy) lwidth(thin)) ///
       (bar winner_other  t, barwidth(0.8) color(gs13) lcolor(gs10) lwidth(thin)) ///
       (rcap winners_hi winners_lo t, lcolor(gs5) lwidth(thin)), ///
    yline(0, lcolor(gs8) lwidth(thin)) ///
    xline(-9.5, lcolor(black) lpattern(dash) lwidth(medthick)) ///
    xline(-3.5, lcolor(black) lpattern(dash) lwidth(medthick)) ///
    xlabel(-9(1)10, labsize(vsmall) angle(0)) ///
    ylabel(-20(5)15, labsize(small) format(%4.0f)) ///
    yscale(range(-20 15)) ///
    xtitle("Trading day relative to month-end, T=0 (last trading day)", size(small)) ///
    ytitle("Mean daily excess return (bps)", size(small)) ///
    title("Panel B: Winners (Decile 10)", size(medium)) ///
    legend(order(1 "PreTOM [T{&minus}9, T{&minus}4]" 2 "Other days") ///
           ring(0) pos(5) cols(1) size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(winners, replace)

* Combine
graph combine losers winners, cols(1) ///
    graphregion(color(white)) ///
    xsize(7) ysize(9)

graph export "$output\appendix_daily_decomp.pdf", replace as(pdf)
graph export "$output\appendix_daily_decomp.png", replace as(png) width(2400)

di _n "{hline 50}"
di "DONE - Appendix daily decomposition figure"
di "{hline 50}"

log close

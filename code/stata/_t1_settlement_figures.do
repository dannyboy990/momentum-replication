/*==============================================================================
  _t1_settlement_figures.do

  Clean figures for T+1 settlement natural experiment.
  Figure 1: Side-by-side bars (pre vs post) at each trading day
  Figure 2: Two-panel - cumulative loser mkt-adj return within month
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

use "$data/momentum_daily.dta", clear

gen post_t1 = (date >= td(28may2024))
gen loser_mktadj_bp = (losers_vw - mktrf) * 10000
keep if year(date) >= 1980


* ══════════════════════════════════════════════════════════════════════════════
*  FIGURE 1: Grouped bar chart - pre vs post by trading day
* ══════════════════════════════════════════════════════════════════════════════

preserve

* Keep t = -9 to +3
keep if t >= -9 & t <= 3

* Collapse to means
collapse (mean) mean_bp = loser_mktadj_bp, by(t post_t1)

reshape wide mean_bp, i(t) j(post_t1)
rename mean_bp0 pre
rename mean_bp1 post

* Offset bars
gen t_pre  = t - 0.18
gen t_post = t + 0.18

twoway (bar pre t_pre, barw(0.32) color(cranberry%60) base(0)) ///
       (bar post t_post, barw(0.32) color(navy%60) base(0)), ///
    ytitle("Loser mkt-adj return (bps/day)", size(medsmall)) ///
    xtitle("Trading day relative to month-end", size(medsmall)) ///
    xlabel(-9(1)3, labsize(small)) ///
    ylabel(, labsize(small) angle(0)) ///
    yline(0, lcolor(gs12) lpattern(solid) lwidth(thin)) ///
    legend(order(1 "T+2 era (1980{&minus}May 2024)" ///
                 2 "T+1 era (Jun 2024 {&minus} 2025)") ///
        rows(1) size(small) position(6) ring(1)) ///
    title("") ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    xsize(7) ysize(4.5)

graph export "$fig/t1_settlement_bars.pdf", replace
graph export "$fig/t1_settlement_bars.png", width(2000) replace

restore


* ══════════════════════════════════════════════════════════════════════════════
*  FIGURE 2: Cumulative within-month loser mkt-adj return
*  Two lines: pre vs post T+1, starting from t=+13 (month start)
* ══════════════════════════════════════════════════════════════════════════════

preserve

* Create a proper ordering variable: month goes from high t to low t
* t=13 is start of month, t=0 is end
* Reverse so we accumulate from month start
gen day_order = -t  // higher day_order = later in month

* Collapse to means by t and period
collapse (mean) mean_bp = loser_mktadj_bp, by(t day_order post_t1)
sort post_t1 day_order

* Cumulate within period
by post_t1 (day_order): gen cum_bp = sum(mean_bp)

reshape wide mean_bp cum_bp, i(t day_order) j(post_t1)
rename cum_bp0 cum_pre
rename cum_bp1 cum_post

* Plot: x-axis is day_order (ascending = progressing through month)
* Relabel with original t values
sort day_order

* Shade the PreTOM region
* t=-9 to t=-4 corresponds to day_order = 4 to 9
* Add a zero origin line and shade

twoway (area cum_pre day_order if day_order >= 4 & day_order <= 9, ///
           color(cranberry%15) base(0) nodropbase) ///
       (line cum_pre day_order, lcolor(cranberry) lwidth(medthick) lpattern(solid)) ///
       (line cum_post day_order, lcolor(navy) lwidth(medthick) lpattern(dash)), ///
    ytitle("Cumulative loser mkt-adj return (bps)", size(medsmall)) ///
    xtitle("Trading day relative to month-end", size(medsmall)) ///
    xlabel(0 "0" 1 "-1" 2 "-2" 3 "-3" 4 "-4" 5 "-5" 6 "-6" 7 "-7" 8 "-8" 9 "-9" ///
           10 "-10" 11 "-11" 12 "-12" 13 "-13", labsize(vsmall) angle(0)) ///
    ylabel(, labsize(small) angle(0)) ///
    yline(0, lcolor(gs12) lpattern(solid) lwidth(thin)) ///
    legend(order(2 "T+2 era (1980{&minus}May 2024)" ///
                 3 "T+1 era (Jun 2024{&minus}2025)") ///
        rows(1) size(small) position(6) ring(1)) ///
    title("") ///
    note("Shaded region: PreTOM window (t={&minus}9 to t={&minus}4)", size(vsmall)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    xsize(7) ysize(4.5)

graph export "$fig/t1_settlement_cumulative.pdf", replace
graph export "$fig/t1_settlement_cumulative.png", width(2000) replace

restore


* ══════════════════════════════════════════════════════════════════════════════
*  FIGURE 3: Difference plot (Post minus Pre) with 95% CIs
*  t=-9 to t=-1 only. Key bars visually highlighted for B&W printing.
* ══════════════════════════════════════════════════════════════════════════════

preserve

keep if t >= -9 & t <= -1

* Compute means and SEs by t and period
collapse (mean) mean_bp = loser_mktadj_bp ///
         (sd) sd_bp = loser_mktadj_bp ///
         (count) n_bp = loser_mktadj_bp, by(t post_t1)

* SE of the mean
gen se_bp = sd_bp / sqrt(n_bp)

reshape wide mean_bp sd_bp n_bp se_bp, i(t) j(post_t1)
rename mean_bp0 pre
rename mean_bp1 post
rename se_bp0 se_pre
rename se_bp1 se_post

* Difference and SE of difference (independent samples)
gen diff = post - pre
gen se_diff = sqrt(se_pre^2 + se_post^2)
gen ci_lo = diff - 1.96 * se_diff
gen ci_hi = diff + 1.96 * se_diff

* Separate series for the bar types
gen diff_other = diff if t != -4 & t != -3
gen diff_old   = diff if t == -4
gen diff_new   = diff if t == -3

twoway (bar diff_other t, barw(0.65) color(gs11) lcolor(gs6) lwidth(thin) base(0)) ///
       (bar diff_old t, barw(0.65) fcolor(white) lcolor(black) lwidth(thick) base(0)) ///
       (bar diff_new t, barw(0.65) color(gs4) lcolor(black) lwidth(medthick) base(0)) ///
       (rcap ci_lo ci_hi t, lcolor(black) lwidth(medthin)), ///
    ytitle("Difference in loser mkt-adj return (bps/day)" ///
           "Post-T+1 minus Pre-T+1", size(medsmall)) ///
    xtitle("Trading day relative to month-end", size(medsmall)) ///
    xlabel(-9(1)-1, labsize(small)) ///
    ylabel(, labsize(small) angle(0)) ///
    yline(0, lcolor(gs8) lpattern(solid) lwidth(thin)) ///
    legend(order(2 "T+2 era ({it:T}={&minus}4)" ///
                 3 "T+1 era ({it:T}={&minus}3)") ///
        rows(1) size(small) position(6) ring(1)) ///
    title("") ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    xsize(7) ysize(4.5)

graph export "$fig/t1_settlement_shaded.pdf", replace
graph export "$fig/t1_settlement_shaded.png", width(2400) replace

* Also list the values
list t diff se_diff ci_lo ci_hi, sep(0)

restore

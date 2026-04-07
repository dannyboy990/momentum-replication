/*==============================================================================
  _appendix_subperiod_figures.do

  Appendix subperiod versions of:
    Figure 2: Loser PreTOM vs Non-PreTOM bar chart (monthly compounded)
    Figure 3: Winners/Losers/WML daily profile bar chart

  Split: 1980-2007 vs 2008-2025

  Input:  $data\momentum_daily.dta
  Output: $output\appendix_loser_subperiod.pdf
          $output\appendix_profile_subperiod.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\_appendix_subperiod_figures.log", replace

use "$data\momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980

gen window = (t >= -9 & t <= -4)
gen period = cond(date < td(01jul2002), 1, 2)

* Returns in bps
gen losers_vw_bps  = losers_vw * 10000
gen winners_vw_bps = winners_vw * 10000
gen wml_vw_bps     = wml_vw * 10000
gen losers_mktadj  = (losers_vw - mktrf) * 10000

/*──────────────────────────────────────────────────────────────────────────────
  FIGURE A: Loser PreTOM vs Non-PreTOM (monthly compounded), by subperiod
──────────────────────────────────────────────────────────────────────────────*/

preserve

* Compound daily market-adjusted loser returns within each month-window
gen ln_ret = ln(1 + (losers_vw - mktrf))

collapse (sum) ln_ret, by(ym window period)
gen monthly_ret = (exp(ln_ret) - 1) * 10000  /* bps */

* Collapse to means by window × period
collapse (mean) m = monthly_ret (sd) sd = monthly_ret (count) n = monthly_ret, ///
    by(window period)

gen se = sd / sqrt(n)
gen ci_lo = m - 1.96 * se
gen ci_hi = m + 1.96 * se

* Display
list, clean noobs

* X positions: period 1 bars at 1,2; period 2 bars at 4,5
gen x = .
replace x = 1 if period == 1 & window == 0
replace x = 2 if period == 1 & window == 1
replace x = 4 if period == 2 & window == 0
replace x = 5 if period == 2 & window == 1

gen m_nonpretom = m if window == 0
gen m_pretom    = m if window == 1

twoway (bar m_nonpretom x, barwidth(0.8) color(gs10) lcolor(gs8) lwidth(thin)) ///
       (bar m_pretom    x, barwidth(0.8) color(cranberry) lcolor(cranberry%80) lwidth(thin)) ///
       (rcap ci_hi ci_lo x, lcolor(black) lwidth(medthin)), ///
    yline(0, lcolor(gs12) lwidth(thin)) ///
    xlabel(1.5 "1980{&minus}2002" 4.5 "2002{&minus}2025", labsize(medsmall) noticks) ///
    ylabel(, labsize(small) format(%6.0f)) ///
    ytitle("Market-adjusted loser return (bps/month)", size(small)) ///
    xtitle("") ///
    legend(order(1 "Non-PreTOM" 2 "PreTOM [T{&minus}9, T{&minus}4]") ///
           ring(0) pos(6) cols(2) size(small)) ///
    graphregion(color(white)) plotregion(color(white)) ///
    xsize(6) ysize(5)

graph export "$output\appendix_loser_subperiod.pdf", replace as(pdf)
graph export "$output\appendix_loser_subperiod.png", replace as(png) width(2400)

restore

/*──────────────────────────────────────────────────────────────────────────────
  FIGURE B: Daily profile (Winners/Losers/WML × Window vs Rest), by subperiod
  Two-panel: Panel A = 1980-2007, Panel B = 2008-2025
──────────────────────────────────────────────────────────────────────────────*/

forvalues p = 1/2 {

    preserve

    keep if period == `p'

    collapse (mean)  m_win=winners_vw_bps m_los=losers_vw_bps m_wml=wml_vw_bps ///
             (sd)    sd_win=winners_vw_bps sd_los=losers_vw_bps sd_wml=wml_vw_bps ///
             (count) n=wml_vw_bps, by(window)

    foreach v in win los wml {
        gen se_`v'    = sd_`v' / sqrt(n)
        gen ci_lo_`v' = m_`v' - 1.96 * se_`v'
        gen ci_hi_`v' = m_`v' + 1.96 * se_`v'
    }

    * Reshape
    rename (m_win m_los m_wml)             (m_1 m_2 m_3)
    rename (ci_lo_win ci_lo_los ci_lo_wml) (cilo_1 cilo_2 cilo_3)
    rename (ci_hi_win ci_hi_los ci_hi_wml) (cihi_1 cihi_2 cihi_3)

    reshape long m_ cilo_ cihi_, i(window) j(series)
    rename m_ mean_ret
    rename cilo_ ci_lo
    rename cihi_ ci_hi

    * X-positions: window group at 1-3, rest group at 5-7
    gen x = cond(window == 1, series, series + 4)

    gen m_winners = mean_ret if series == 1
    gen m_losers  = mean_ret if series == 2
    gen m_wml     = mean_ret if series == 3

    local plab = cond(`p' == 1, "Panel A: 1980{&minus}2002", "Panel B: 2002{&minus}2025")

    twoway (bar m_winners x, barwidth(0.8) color(gs11) lcolor(gs8) lwidth(thin)) ///
           (bar m_losers  x, barwidth(0.8) color(gs3) lcolor(gs1) lwidth(thin)) ///
           (bar m_wml     x, barwidth(0.8) color(gs7) lcolor(gs5) lwidth(thin)) ///
           (rcap ci_hi ci_lo x, lcolor(black) lwidth(medthin)), ///
        yline(0, lcolor(gs10) lwidth(thin)) ///
        xlabel(2 "[T{&minus}9, T{&minus}4]" 6 "Rest of month", ///
               labsize(medsmall) noticks) ///
        ylabel(-25(5)20, labsize(small) format(%4.1f) nogrid) ///
        xtitle("") ///
        ytitle("Average daily excess return (bps)", size(small)) ///
        title("`plab'", size(medium)) ///
        legend(order(1 "Winners" 2 "Losers" 3 "WML") ///
               ring(1) pos(6) rows(1) size(small) ///
               region(lcolor(gs12) fcolor(white))) ///
        graphregion(color(white) margin(small)) ///
        plotregion(margin(b=0)) ///
        xsize(6) ysize(4) ///
        name(panel`p', replace)

    restore
}

graph combine panel1 panel2, cols(1) ///
    graphregion(color(white)) ///
    xsize(6) ysize(8)

graph export "$output\appendix_profile_subperiod.pdf", replace as(pdf)
graph export "$output\appendix_profile_subperiod.png", replace as(png) width(2400)

di _n "{hline 60}"
di "DONE — Appendix subperiod figures"
di "{hline 60}"

log close

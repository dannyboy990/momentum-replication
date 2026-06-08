/*==============================================================================
  _figures_matti_mktadj.do

  1. Bar charts: market-adjusted daily returns (bps) for Winners, Losers, WML
     during PreTOM window [t-9,t-4] vs rest of month. Full + subperiods.
     SEs from monthly compounded returns (not daily).

  2. December vs non-December loser PreTOM returns - raw AND market-adjusted.
     SEs from monthly compounded returns.

  Input:  $data\momentum_daily.dta
  Output: $output\barchart_mktadj_*.pdf, barchart_dec_loser_*.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap mkdir "$output"
cap log close
log using "$output\mktadj_barchart.log", replace

cap set scheme plotplainblind
if _rc set scheme s2mono
graph set window fontface "Times New Roman"

use "$data\momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980
sort date

gen window = (t >= -9 & t <= -4)
gen month_num = month(dofm(ym))
gen is_dec = (month_num == 12)


/*======================================================================
  PART 1: Market-adjusted bar charts - Window vs Rest
  Compound daily returns to monthly, then means/SEs across months.
======================================================================*/

di _n "{hline 70}"
di "PART 1: Market-adjusted daily returns (bps) - Window vs Rest"
di "{hline 70}"

* Market-adjusted daily returns: subtract mktrf from each leg
* Log returns for compounding
foreach v in winners_vw losers_vw {
    gen lr_ma_`v'_win  = cond(window == 1, ln(1 + `v' - mktrf), 0)
    gen lr_ma_`v'_rest = cond(window == 0, ln(1 + `v' - mktrf), 0)
}
* WML is already long-short hedged
gen lr_wml_win  = cond(window == 1, ln(1 + wml_vw), 0)
gen lr_wml_rest = cond(window == 0, ln(1 + wml_vw), 0)

* Also: raw loser returns for Dec comparison (Part 2)
gen lr_losraw_win = cond(window == 1, ln(1 + losers_vw), 0)
gen lr_losma_win  = cond(window == 1, ln(1 + losers_vw - mktrf), 0)

* Count trading days per window-month
gen ndays_win  = (window == 1)
gen ndays_rest = (window == 0)

* Collapse to monthly
collapse (sum) lr_ma_winners_vw_win lr_ma_losers_vw_win lr_wml_win ///
               lr_ma_winners_vw_rest lr_ma_losers_vw_rest lr_wml_rest ///
               lr_losraw_win lr_losma_win ///
               ndays_win ndays_rest, ///
         by(ym yr is_dec)

* Convert to simple returns (bps)
foreach v in ma_winners_vw ma_losers_vw {
    gen r_`v'_win  = (exp(lr_`v'_win)  - 1) * 10000
    gen r_`v'_rest = (exp(lr_`v'_rest) - 1) * 10000
}
gen r_wml_win  = (exp(lr_wml_win)  - 1) * 10000
gen r_wml_rest = (exp(lr_wml_rest) - 1) * 10000
gen r_losraw_win = (exp(lr_losraw_win) - 1) * 10000
gen r_losma_win  = (exp(lr_losma_win)  - 1) * 10000

* Average daily bps
foreach v in ma_winners_vw ma_losers_vw wml {
    gen d_`v'_win  = r_`v'_win  / ndays_win
    gen d_`v'_rest = r_`v'_rest / ndays_rest
}
gen d_losraw_win = r_losraw_win / ndays_win
gen d_losma_win  = r_losma_win  / ndays_win

* Print summary stats
foreach sp in "full" "pre" "post" {
    if "`sp'" == "full" local cond ""
    if "`sp'" == "pre"  local cond "& yr <= 2002"
    if "`sp'" == "post" local cond "& yr >= 2003"
    local lbl = cond("`sp'"=="full","1980-2024",cond("`sp'"=="pre","1980-2002","2003-2024"))

    di _n "--- `lbl' ---"
    foreach w in win rest {
        local wlbl = cond("`w'"=="win", "Window", "Rest")
        foreach v in d_ma_winners_vw_`w' d_ma_losers_vw_`w' d_wml_`w' {
            qui sum `v' if 1 `cond'
            local m = r(mean)
            local se = r(sd)/sqrt(r(N))
            local t = `m'/`se'
            di "`v' `wlbl': mean=" %6.2f `m' " t=" %5.2f `t' " N=" r(N)
        }
    }
}


* ── Program for market-adjusted bar chart (monthly SEs) ──────────────
capture program drop make_mktadj_bar
program define make_mktadj_bar
    syntax , SAMPle(string) TItle(string) SAVEname(string) [NODRAW]

    preserve

    if "`sample'" == "pre"  keep if yr <= 2002
    if "`sample'" == "post" keep if yr >= 2003

    * Means and SEs across months
    foreach v in ma_winners_vw ma_losers_vw wml {
        foreach w in win rest {
            qui sum d_`v'_`w'
            local m_`v'_`w' = r(mean)
            local se_`v'_`w' = r(sd) / sqrt(r(N))
        }
    }

    clear
    set obs 6
    gen series = mod(_n - 1, 3) + 1
    gen window = (_n <= 3)
    gen x = cond(window == 1, series, series + 4)

    gen mean_ret = .
    gen ci_lo = .
    gen ci_hi = .

    * Window group
    replace mean_ret = `m_ma_winners_vw_win' in 1
    replace mean_ret = `m_ma_losers_vw_win'  in 2
    replace mean_ret = `m_wml_win'           in 3
    replace ci_lo = `m_ma_winners_vw_win' - 1.96 * `se_ma_winners_vw_win' in 1
    replace ci_hi = `m_ma_winners_vw_win' + 1.96 * `se_ma_winners_vw_win' in 1
    replace ci_lo = `m_ma_losers_vw_win'  - 1.96 * `se_ma_losers_vw_win'  in 2
    replace ci_hi = `m_ma_losers_vw_win'  + 1.96 * `se_ma_losers_vw_win'  in 2
    replace ci_lo = `m_wml_win'           - 1.96 * `se_wml_win'           in 3
    replace ci_hi = `m_wml_win'           + 1.96 * `se_wml_win'           in 3

    * Rest group
    replace mean_ret = `m_ma_winners_vw_rest' in 4
    replace mean_ret = `m_ma_losers_vw_rest'  in 5
    replace mean_ret = `m_wml_rest'           in 6
    replace ci_lo = `m_ma_winners_vw_rest' - 1.96 * `se_ma_winners_vw_rest' in 4
    replace ci_hi = `m_ma_winners_vw_rest' + 1.96 * `se_ma_winners_vw_rest' in 4
    replace ci_lo = `m_ma_losers_vw_rest'  - 1.96 * `se_ma_losers_vw_rest'  in 5
    replace ci_hi = `m_ma_losers_vw_rest'  + 1.96 * `se_ma_losers_vw_rest'  in 5
    replace ci_lo = `m_wml_rest'           - 1.96 * `se_wml_rest'           in 6
    replace ci_hi = `m_wml_rest'           + 1.96 * `se_wml_rest'           in 6

    gen m_winners = mean_ret if series == 1
    gen m_losers  = mean_ret if series == 2
    gen m_wml     = mean_ret if series == 3

    twoway (bar m_winners x,                                                     ///
                barwidth(0.8) color(gs11) lcolor(gs8) lwidth(thin))             ///
           (bar m_losers x,                                                      ///
                barwidth(0.8) color(gs3) lcolor(gs1) lwidth(thin))              ///
           (bar m_wml x,                                                         ///
                barwidth(0.8) color(gs7) lcolor(gs5) lwidth(thin))              ///
           (rcap ci_hi ci_lo x,                                                  ///
                lcolor(black) lwidth(medthin)),                                  ///
           xlabel(2 "[t-9, t-4]" 6 "Rest of month",           ///
                  labsize(medsmall) noticks)                                      ///
           ylabel(, labsize(small) angle(0) format(%4.1f) nogrid)               ///
           xtitle("")                                                             ///
           ytitle("Market-adjusted daily return (bps)", size(small))             ///
           yline(0, lcolor(gs10) lwidth(thin) lpattern(solid))                   ///
           title("`title'", size(medsmall) color(black))                         ///
           legend(order(1 "Winners" 2 "Losers" 3 "WML")                         ///
                  ring(0) position(5) cols(1) size(small)                         ///
                  region(lcolor(gs12) fcolor(white)))                             ///
           graphregion(color(white) margin(small))                               ///
           plotregion(margin(b=0))                                               ///
           xsize(6) ysize(5)                                                     ///
           name(`savename', replace) `nodraw'

    graph export "$output\barchart_mktadj_`savename'.pdf", replace as(pdf)
    graph export "$output\barchart_mktadj_`savename'.png", replace as(png) width(2400)

    restore
end

make_mktadj_bar, sample(full) title("Market-Adjusted, 1980--2025") savename(full)
make_mktadj_bar, sample(pre)  title("Market-Adjusted, 1980--2002") savename(pre)
make_mktadj_bar, sample(post) title("Market-Adjusted, 2003--2025") savename(post)

* ── Combined subperiod panel ─────────────────────────────────────────
make_mktadj_bar, sample(pre)  title("1980--2002") savename(ma_pre) nodraw
make_mktadj_bar, sample(post) title("2003--2025") savename(ma_post) nodraw

graph combine ma_pre ma_post,                                                    ///
       cols(2) graphregion(color(white))                                         ///
       xsize(10) ysize(5)                                                        ///
       imargin(small)

graph export "$output\barchart_mktadj_subperiod.pdf", replace as(pdf)
graph export "$output\barchart_mktadj_subperiod.png", replace as(png) width(2400)


/*======================================================================
  PART 2: December vs non-December loser PreTOM - raw and market-adjusted
  Monthly compounded returns, SEs across months.
======================================================================*/

di _n "{hline 70}"
di "PART 2: December vs non-December loser PreTOM returns"
di "{hline 70}"

* Summary table
di _n "  Measure      Period       Dec Window   Other Window   Diff       t-stat"
di    "  {hline 70}"

foreach measure in "raw" "mktadj" {
    local var = cond("`measure'" == "raw", "d_losraw_win", "d_losma_win")
    local mlbl = cond("`measure'" == "raw", "Raw (ri-rf)", "Mkt-adj  ")

    foreach sp in "full" "pre" "post" {
        if "`sp'" == "full" {
            local cond ""
            local plbl "1980-2024"
        }
        if "`sp'" == "pre" {
            local cond "& yr <= 2002"
            local plbl "1980-2002"
        }
        if "`sp'" == "post" {
            local cond "& yr >= 2003"
            local plbl "2003-2024"
        }

        cap qui ttest `var' if 1 `cond', by(is_dec) unequal
        if _rc == 0 {
            local m_dec   = r(mu_2)
            local m_other = r(mu_1)
            local diff    = r(mu_2) - r(mu_1)
            local tstat   = r(t)
            di "  `mlbl'  `plbl'  " %10.2f `m_dec' "  " %10.2f `m_other' "  " %10.2f `diff' "  " %6.2f `tstat'
        }
    }
    di ""
}

* ── Bar chart: Dec vs non-Dec loser PreTOM ───────────────────────────

capture program drop make_dec_bar
program define make_dec_bar
    syntax , SAMPle(string) TItle(string) SAVEname(string) [NODRAW]

    preserve

    if "`sample'" == "pre"  keep if yr <= 2002
    if "`sample'" == "post" keep if yr >= 2003

    * Means/SEs for each {is_dec × measure}
    foreach d in 0 1 {
        foreach v in losraw losma {
            qui sum d_`v'_win if is_dec == `d'
            local m_`v'_`d' = r(mean)
            local se_`v'_`d' = r(sd) / sqrt(r(N))
        }
    }

    clear
    set obs 4
    * 1=Other Raw, 2=Other MktAdj, 3=Dec Raw, 4=Dec MktAdj
    gen series = cond(_n <= 2, _n, _n - 2)
    gen is_dec = (_n > 2)
    gen x = cond(is_dec == 0, series, series + 3)

    gen mean_ret = .
    gen ci_lo = .
    gen ci_hi = .

    replace mean_ret = `m_losraw_0' in 1
    replace ci_lo = `m_losraw_0' - 1.96 * `se_losraw_0' in 1
    replace ci_hi = `m_losraw_0' + 1.96 * `se_losraw_0' in 1

    replace mean_ret = `m_losma_0' in 2
    replace ci_lo = `m_losma_0' - 1.96 * `se_losma_0' in 2
    replace ci_hi = `m_losma_0' + 1.96 * `se_losma_0' in 2

    replace mean_ret = `m_losraw_1' in 3
    replace ci_lo = `m_losraw_1' - 1.96 * `se_losraw_1' in 3
    replace ci_hi = `m_losraw_1' + 1.96 * `se_losraw_1' in 3

    replace mean_ret = `m_losma_1' in 4
    replace ci_lo = `m_losma_1' - 1.96 * `se_losma_1' in 4
    replace ci_hi = `m_losma_1' + 1.96 * `se_losma_1' in 4

    gen m_raw    = mean_ret if series == 1
    gen m_mktadj = mean_ret if series == 2

    twoway (bar m_raw x,                                                         ///
                barwidth(0.8) color(gs3) lcolor(gs1) lwidth(thin))              ///
           (bar m_mktadj x,                                                      ///
                barwidth(0.8) color(gs7) lcolor(gs5) lwidth(thin))              ///
           (rcap ci_hi ci_lo x,                                                  ///
                lcolor(black) lwidth(medthin)),                                  ///
           xlabel(1.5 "Non-December" 4.5 "December",                             ///
                  labsize(medsmall) noticks)                                      ///
           ylabel(, labsize(small) angle(0) format(%4.1f) nogrid)               ///
           xtitle("")                                                             ///
           ytitle("Mean daily loser return, PreTOM (bps)", size(small))          ///
           yline(0, lcolor(gs10) lwidth(thin) lpattern(solid))                   ///
           title("`title'", size(medsmall) color(black))                         ///
           legend(order(1 "Raw (r{sub:i} - r{sub:f})" 2 "Market-adjusted")      ///
                  ring(1) position(6) cols(2) size(small)                         ///
                  region(lcolor(gs12) fcolor(white)))                             ///
           graphregion(color(white) margin(small))                               ///
           plotregion(margin(b=0))                                               ///
           xsize(6) ysize(5)                                                     ///
           name(`savename', replace) `nodraw'

    graph export "$output\barchart_dec_loser_`savename'.pdf", replace as(pdf)
    graph export "$output\barchart_dec_loser_`savename'.png", replace as(png) width(2400)

    restore
end

make_dec_bar, sample(full) title("Loser PreTOM: Dec vs Non-Dec, 1980--2025") savename(full)
make_dec_bar, sample(pre)  title("Loser PreTOM: Dec vs Non-Dec, 1980--2002") savename(pre)
make_dec_bar, sample(post) title("Loser PreTOM: Dec vs Non-Dec, 2003--2025") savename(post)

* ── Combined subperiod panel ─────────────────────────────────────────
make_dec_bar, sample(pre)  title("1980--2002") savename(dec_pre) nodraw
make_dec_bar, sample(post) title("2003--2025") savename(dec_post) nodraw

graph combine dec_pre dec_post,                                                  ///
       cols(2) graphregion(color(white))                                         ///
       xsize(10) ysize(5)                                                        ///
       imargin(small)

graph export "$output\barchart_dec_loser_subperiod.pdf", replace as(pdf)
graph export "$output\barchart_dec_loser_subperiod.png", replace as(png) width(2400)

di _n "Done."

log close

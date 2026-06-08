/*==============================================================================
  _figures_matti_barchart.do

  Bar chart: average daily MARKET-ADJUSTED returns (bps) for Winners, Losers,
  WML during PreTOM window [T-9, T-4] vs rest of month.
  95% CI whiskers.

  Market-adjusted = (ri - rf) - mktrf for winners/losers; WML unchanged.
  This removes common market drift so the figure cleanly shows the loser
  PreTOM anomaly without the market return inflating both portfolios.

  SEs computed from MONTHLY compounded returns (not daily), so CIs match
  the t-stats reported in the tables.

  Three versions: full 1980-2025, 1980-2002, 2003-2025.
  Also a combined two-panel subperiod figure.

  Input:  $data\momentum_daily.dta
  Output: $output\barchart_*.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap mkdir "$output"

cap set scheme plotplainblind
if _rc set scheme s2mono
graph set window fontface "Times New Roman"

use "$data\momentum_daily.dta", clear

gen yr = year(date)
keep if yr >= 1980
sort date

gen window = (t >= -9 & t <= -4)

* ── Market-adjusted returns ──────────────────────────────────────────────────
* Subtract market return from winners and losers; WML = winners - losers is
* already market-neutral by construction.
gen winners_ma = winners_vw - mktrf
gen losers_ma  = losers_vw  - mktrf
gen wml_ma     = wml_vw

* ── Compound daily returns to monthly, separately for window and rest ────────

* Log returns for compounding
foreach v in winners_ma losers_ma wml_ma {
    gen lr_`v'_win  = cond(window == 1, ln(1 + `v'), 0)
    gen lr_`v'_rest = cond(window == 0, ln(1 + `v'), 0)
}

* Also count trading days per window-month (for converting monthly to daily avg)
gen ndays_win  = (window == 1)
gen ndays_rest = (window == 0)

* Collapse to monthly
collapse (sum) lr_winners_ma_win lr_losers_ma_win lr_wml_ma_win ///
               lr_winners_ma_rest lr_losers_ma_rest lr_wml_ma_rest ///
               ndays_win ndays_rest, by(ym yr)

* Convert to simple returns (bps) - monthly compounded
foreach v in winners_ma losers_ma wml_ma {
    gen r_`v'_win  = (exp(lr_`v'_win)  - 1) * 10000
    gen r_`v'_rest = (exp(lr_`v'_rest) - 1) * 10000
}

* Average daily bps = monthly bps / number of trading days in that window
foreach v in winners_ma losers_ma wml_ma {
    gen d_`v'_win  = r_`v'_win  / ndays_win
    gen d_`v'_rest = r_`v'_rest / ndays_rest
}


/*----------------------------------------------------------------------
  Program to make one bar chart
----------------------------------------------------------------------*/

capture program drop make_barchart
program define make_barchart
    syntax , SAMPle(string) TItle(string) SAVEname(string) [NODRAW]

    preserve

    if "`sample'" == "pre"  keep if yr <= 2002
    if "`sample'" == "post" keep if yr >= 2003

    * Means and SEs across months for each {portfolio × window}
    local nobs = _N

    foreach v in winners_ma losers_ma wml_ma {
        foreach w in win rest {
            qui sum d_`v'_`w'
            local m_`v'_`w' = r(mean)
            local se_`v'_`w' = r(sd) / sqrt(r(N))
        }
    }

    * Build plotting dataset
    clear
    set obs 6
    gen series = mod(_n - 1, 3) + 1
    gen window = (_n <= 3)
    gen x = cond(window == 1, series, series + 4)

    gen mean_ret = .
    gen ci_lo = .
    gen ci_hi = .

    * Window group
    replace mean_ret = `m_winners_ma_win' in 1
    replace mean_ret = `m_losers_ma_win'  in 2
    replace mean_ret = `m_wml_ma_win'     in 3
    replace ci_lo = `m_winners_ma_win' - 1.96 * `se_winners_ma_win' in 1
    replace ci_hi = `m_winners_ma_win' + 1.96 * `se_winners_ma_win' in 1
    replace ci_lo = `m_losers_ma_win'  - 1.96 * `se_losers_ma_win'  in 2
    replace ci_hi = `m_losers_ma_win'  + 1.96 * `se_losers_ma_win'  in 2
    replace ci_lo = `m_wml_ma_win'     - 1.96 * `se_wml_ma_win'     in 3
    replace ci_hi = `m_wml_ma_win'     + 1.96 * `se_wml_ma_win'     in 3

    * Rest group
    replace mean_ret = `m_winners_ma_rest' in 4
    replace mean_ret = `m_losers_ma_rest'  in 5
    replace mean_ret = `m_wml_ma_rest'     in 6
    replace ci_lo = `m_winners_ma_rest' - 1.96 * `se_winners_ma_rest' in 4
    replace ci_hi = `m_winners_ma_rest' + 1.96 * `se_winners_ma_rest' in 4
    replace ci_lo = `m_losers_ma_rest'  - 1.96 * `se_losers_ma_rest'  in 5
    replace ci_hi = `m_losers_ma_rest'  + 1.96 * `se_losers_ma_rest'  in 5
    replace ci_lo = `m_wml_ma_rest'     - 1.96 * `se_wml_ma_rest'     in 6
    replace ci_hi = `m_wml_ma_rest'     + 1.96 * `se_wml_ma_rest'     in 6

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
           xlabel(2 "[T-9, T-4]" 6 "Rest of month",           ///
                  labsize(medsmall) noticks)                                      ///
           ylabel(-15(5)20, labsize(small) angle(0) format(%4.0f) nogrid)        ///
           xtitle("")                                                             ///
           ytitle("Average daily market-adjusted return (bps)", size(small))     ///
           yline(0, lcolor(gs10) lwidth(thin) lpattern(solid))                   ///
           title("`title'", size(medsmall) color(black))                         ///
           legend(order(1 "Winners" 2 "Losers" 3 "WML")                         ///
                  ring(0) position(5) cols(1) size(small)                         ///
                  region(lcolor(gs12) fcolor(white)))                             ///
           graphregion(color(white) margin(small))                               ///
           plotregion(margin(b=0) lcolor(none))                                  ///
           xsize(6) ysize(5)                                                     ///
           name(`savename', replace) `nodraw'

    graph export "$output\barchart_`savename'.pdf", replace as(pdf)
    graph export "$output\barchart_`savename'.png", replace as(png) width(2400)

    restore
end


* ── Full sample ──────────────────────────────────────────────────────────────
make_barchart, sample(full) title("1980{&minus}2025") savename(full)

* ── Subperiods ───────────────────────────────────────────────────────────────
make_barchart, sample(pre)  title("1980{&minus}2002") savename(pre)
make_barchart, sample(post) title("2003{&minus}2025") savename(post)


/*----------------------------------------------------------------------
  Combined two-panel subperiod figure
----------------------------------------------------------------------*/

make_barchart, sample(pre)  title("1980-2002") savename(panel_pre) nodraw
make_barchart, sample(post) title("2003-2025") savename(panel_post) nodraw

graph combine panel_pre panel_post,                                              ///
       cols(2) graphregion(color(white))                                         ///
       xsize(10) ysize(5)                                                        ///
       imargin(small)

graph export "$output\barchart_subperiod.pdf", replace as(pdf)
graph export "$output\barchart_subperiod.png", replace as(png) width(2400)

di _n "Done."

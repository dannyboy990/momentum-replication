/*==============================================================================
  _flow_pressure_chart.do

  Figure: Intra-month net flow pressures by momentum decile.
  Bar chart showing net flow pressure (bps) for deciles 1 (losers) to 10 (winners).

  Data from the mutual-fund flow series.

  Output: $fig/flow_pressure_chart.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap mkdir "$fig"

cap set scheme plotplainblind
if _rc set scheme s2mono
graph set window fontface "Times New Roman"

* ── Data ────────────────────────────────────────────────────────────────────
clear
input decile flow_pressure
1  -9.87
2  -7.69
3  -5.47
4  -3.68
5  -3.24
6  -2.40
7  -1.88
8  -1.01
9  -0.31
10  0.45
end

label var decile "Momentum decile"
label var flow_pressure "Net flow pressure (bps)"

* ── Bar chart ───────────────────────────────────────────────────────────────
twoway (bar flow_pressure decile, ///
        barwidth(0.7) ///
        fcolor(gs8) lcolor(black) lwidth(thin)), ///
    xlabel(1(1)10, labsize(medium)) ///
    ylabel(, labsize(medium) angle(horizontal) format(%4.1f)) ///
    ytitle("Flow pressure", size(medium)) ///
    xtitle("Momentum deciles: 1 = losers, 10 = winners", size(medium)) ///
    title("", size(medlarge)) ///
    legend(off) ///
    plotregion(margin(b=0)) ///
    yline(0, lcolor(black) lwidth(thin))

graph export "$fig/flow_pressure_chart.pdf", replace
graph export "$fig/flow_pressure_chart.png", replace width(1600)

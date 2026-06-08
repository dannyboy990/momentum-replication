/*==============================================================================
  _figures_matti_cumwml.do

  Cumulative WML wealth figures.
  Three PDFs: 1926-2025, 1960-2025, 1980-2025.
  Each shows: window-only WML, full WML, rest-of-month WML.

  Input:  $data\momentum_daily.dta
  Output: $output\cumwml_1926.pdf, cumwml_1960.pdf, cumwml_1980.pdf
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

gen window = (t >= -9 & t <= -4)
gen yr = year(date)

* ── Loop over three sample starts ──────────────────────────────────────────

foreach start in 1926 1960 1980 {

    preserve

    keep if yr >= `start'
    sort date

    * Gross returns for each strategy
    gen gr_full     = 1 + wml_vw
    gen gr_winonly  = cond(window == 1, 1 + wml_vw, 1)
    gen gr_restonly = cond(window == 0, 1 + wml_vw, 1)

    * Cumulative product via running log sum
    gen lncum_full     = sum(ln(gr_full))
    gen lncum_winonly  = sum(ln(gr_winonly))
    gen lncum_restonly = sum(ln(gr_restonly))

    gen wealth_full     = exp(lncum_full)
    gen wealth_winonly  = exp(lncum_winonly)
    gen wealth_restonly = exp(lncum_restonly)

    * Thin to monthly for smoother plotting
    bys ym (date): gen last_in_month = (_n == _N)

    * Terminal values for subtitle
    qui sum wealth_full if _n == _N
    local end_full : di %6.1f r(mean)
    qui sum wealth_winonly if _n == _N
    local end_win : di %6.1f r(mean)
    qui sum wealth_restonly if _n == _N
    local end_rest : di %6.1f r(mean)

    * End year
    qui sum yr
    local endyr = r(max)

    * Dynamic y-axis
    qui sum wealth_winonly
    local wmax = r(max)
    qui sum wealth_restonly
    local rmin = r(min)

    * Set y ticks based on magnitude
    if `wmax' > 500 {
        local yticks "0.1 0.5 1 5 10 50 100 500 1000 5000"
    }
    else if `wmax' > 50 {
        local yticks "0.5 1 2 5 10 20 50 100 200 500"
    }
    else {
        local yticks "0.5 1 2 5 10 20 50"
    }

    twoway (line wealth_winonly  date if last_in_month,                          ///
                lcolor(black) lwidth(medthick) lpattern(solid))                 ///
           (line wealth_full     date if last_in_month,                         ///
                lcolor(gs6) lwidth(medium) lpattern(dash))                      ///
           (line wealth_restonly date if last_in_month,                         ///
                lcolor(gs10) lwidth(medium) lpattern(shortdash)),               ///
           xlabel(, labsize(medsmall) angle(0) format(%tdCY))                    ///
           yscale(log) ylabel(`yticks',                                         ///
                labsize(medsmall) angle(0) format(%9.1f) nogrid)                ///
           xtitle("", size(medsmall))                                           ///
           ytitle("Cumulative value of $1 invested (log scale)", size(medsmall)) ///
           yline(1, lcolor(gs12) lwidth(thin) lpattern(solid))                  ///
           title("`start'{&minus}`endyr'", size(medium) color(black))                ///
           legend(order(1 "Window only [T{&minus}9, T{&minus}4]: $`end_win'"    ///
                        2 "Full momentum: $`end_full'"                          ///
                        3 "Rest of month: $`end_rest'")                         ///
                  ring(0) position(11) cols(1) size(small)                       ///
                  region(lcolor(gs12) fcolor(white)))                            ///
           graphregion(color(white) margin(small))                              ///
           xsize(7) ysize(4.5)

    graph export "$output\cumwml_`start'.pdf", replace as(pdf)
    graph export "$output\cumwml_`start'.png", replace as(png) width(2400)

    di _n "=== `start'-`endyr' terminal wealth ==="
    di "Window only: $`end_win'"
    di "Full WML:    $`end_full'"
    di "Rest only:   $`end_rest'"

    restore
}

di _n "Done. Files: cumwml_1926.pdf, cumwml_1960.pdf, cumwml_1980.pdf"

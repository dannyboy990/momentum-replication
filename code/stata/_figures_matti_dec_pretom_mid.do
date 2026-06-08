/*==============================================================================
  _figures_matti_dec_pretom_mid.do

  Two-panel whisker bar chart:
    Panel A: Dec vs Other months - PreTOM [T-9, T-4] loser returns
    Panel B: Dec vs Other months - Mid-month [t+8, t+13] loser returns

  Each panel: 2 bars with 95% CI whiskers.
  Displacement: Dec losers dip mid-month (tax-loss), not PreTOM.

  Versions: full, pre-2002, post-2002, combined subperiod.

  Input:  $data\momentum_daily.dta
  Output: $output\dec_pretom_mid_*.pdf
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

gen month_num = month(dofm(ym))
gen is_dec = (month_num == 12)

gen losers_bps = losers_vw * 10000
gen losers_ma_bps = (losers_vw - mktrf) * 10000

gen pretom = (t >= -9 & t <= -4)
gen midmo  = (t >= 8  & t <= 13)

keep if pretom == 1 | midmo == 1


/*----------------------------------------------------------------------
  Helper: one 2-bar panel
----------------------------------------------------------------------*/

capture program drop make_panel
program define make_panel
    syntax , WINdow(string) TItle(string) NAMe(string) SAMPle(string) ///
             [YRange(string) YTITLE(string) NODRAW VARname(string)]

    if "`varname'" == "" local varname "losers_bps"

    preserve

    if "`sample'" == "pre"  keep if yr <= 2002
    if "`sample'" == "post" keep if yr >= 2003

    if "`window'" == "pretom" keep if pretom == 1
    if "`window'" == "midmo"  keep if midmo == 1

    collapse (mean) m = `varname' ///
             (sd)   sd = `varname' ///
             (count) n = `varname', by(is_dec)

    gen se    = sd / sqrt(n)
    gen ci_lo = m - 1.96 * se
    gen ci_hi = m + 1.96 * se

    * X positions: 1 = Other, 2 = December
    gen x = is_dec + 1

    local yopt ""
    if "`yrange'" != "" local yopt "ylabel(`yrange', labsize(medlarge) angle(0) format(%4.0f) nogrid)"
    else                local yopt "ylabel(, labsize(medlarge) angle(0) format(%4.1f) nogrid)"

    if "`ytitle'" == "" local ytitle "Mean daily loser return (bps)"

    * Separate series by period for different bar colors
    gen m_other = m if is_dec == 0
    gen m_dec   = m if is_dec == 1

    twoway (bar m_other x, barwidth(0.6)                                          ///
                fcolor(gs8) lcolor(black) lwidth(thin))                          ///
           (bar m_dec x, barwidth(0.6)                                            ///
                fcolor(white) lcolor(black) lwidth(thick))                       ///
           (rcap ci_hi ci_lo x,                                                  ///
                lcolor(black) lwidth(medium)),                                   ///
           xlabel(1 "Other months" 2 "December", labsize(medlarge) noticks)      ///
           xscale(range(0.5 2.5))                                               ///
           `yopt'                                                                ///
           xtitle("")                                                             ///
           ytitle("`ytitle'", size(medlarge))                                    ///
           yline(0, lcolor(gs14) lwidth(thin))                                   ///
           title("`title'", size(large) color(black))                            ///
           legend(off)                                                            ///
           graphregion(color(white) margin(small))                               ///
           plotregion(margin(b=0) lcolor(none))                                  ///
           name(`name', replace) `nodraw'

    restore
end


/*----------------------------------------------------------------------
  Full sample
----------------------------------------------------------------------*/

make_panel, window(pretom) title("PreTOM [T-9, T-4]") ///
    name(p_pretom) sample(full) yrange(-25(5)25) nodraw
make_panel, window(midmo) title("Mid-month [t+8, t+13]") ///
    name(p_midmo) sample(full) yrange(-50(10)30) ytitle(" ") nodraw

graph combine p_pretom p_midmo,                                                  ///
    cols(2) graphregion(color(white))                                            ///
    xsize(8) ysize(4.5) imargin(small)

graph export "$output\dec_pretom_mid_full.pdf", replace as(pdf)
graph export "$output\dec_pretom_mid_full.png", replace as(png) width(2400)


/*----------------------------------------------------------------------
  Pre-2002
----------------------------------------------------------------------*/

make_panel, window(pretom) title("PreTOM [T-9, T-4]") ///
    name(p_pretom) sample(pre) nodraw
make_panel, window(midmo) title("Mid-month [t+8, t+13]") ///
    name(p_midmo) sample(pre) ytitle("") nodraw

graph combine p_pretom p_midmo,                                                  ///
    cols(2) graphregion(color(white))                                            ///
    title("Loser Daily Returns: December vs Other Months, 1980-2002",            ///
          size(medsmall) color(black))                                           ///
    xsize(8) ysize(5) imargin(small)

graph export "$output\dec_pretom_mid_pre.pdf", replace as(pdf)
graph export "$output\dec_pretom_mid_pre.png", replace as(png) width(2400)


/*----------------------------------------------------------------------
  Post-2002
----------------------------------------------------------------------*/

make_panel, window(pretom) title("PreTOM [T-9, T-4]") ///
    name(p_pretom) sample(post) nodraw
make_panel, window(midmo) title("Mid-month [t+8, t+13]") ///
    name(p_midmo) sample(post) ytitle("") nodraw

graph combine p_pretom p_midmo,                                                  ///
    cols(2) graphregion(color(white))                                            ///
    title("Loser Daily Returns: December vs Other Months, 2003-2025",            ///
          size(medsmall) color(black))                                           ///
    xsize(8) ysize(5) imargin(small)

graph export "$output\dec_pretom_mid_post.pdf", replace as(pdf)
graph export "$output\dec_pretom_mid_post.png", replace as(png) width(2400)


/*----------------------------------------------------------------------
  Combined 4-panel: {Pre, Post} × {PreTOM, Mid}
----------------------------------------------------------------------*/

make_panel, window(pretom) title("PreTOM, 1980-2002") ///
    name(sp_pre_pt) sample(pre) yrange(-25(5)10) nodraw
make_panel, window(midmo) title("Mid-month, 1980-2002") ///
    name(sp_pre_mm) sample(pre) yrange(-25(5)10) ytitle("") nodraw
make_panel, window(pretom) title("PreTOM, 2003-2025") ///
    name(sp_post_pt) sample(post) yrange(-25(5)10) nodraw
make_panel, window(midmo) title("Mid-month, 2003-2025") ///
    name(sp_post_mm) sample(post) yrange(-25(5)10) ytitle("") nodraw

graph combine sp_pre_pt sp_pre_mm sp_post_pt sp_post_mm,                        ///
    rows(2) cols(2) graphregion(color(white))                                    ///
    xsize(10) ysize(8) imargin(small)

graph export "$output\dec_pretom_mid_subperiod.pdf", replace as(pdf)
graph export "$output\dec_pretom_mid_subperiod.png", replace as(png) width(2400)

/*----------------------------------------------------------------------
  Market-adjusted versions
----------------------------------------------------------------------*/

make_panel, window(pretom) title("PreTOM [T-9, T-4]") ///
    name(p_pretom_ma) sample(full) varname(losers_ma_bps) ///
    yrange(-25(5)10) ytitle("Mkt-adj daily loser return (bps)") nodraw
make_panel, window(midmo) title("Mid-month [t+8, t+13]") ///
    name(p_midmo_ma) sample(full) varname(losers_ma_bps) ///
    yrange(-35(5)10) ytitle(" ") nodraw

graph combine p_pretom_ma p_midmo_ma,                                            ///
    cols(2) graphregion(color(white))                                            ///
    xsize(8) ysize(4.5) imargin(small)

graph export "$output\dec_pretom_mid_mktadj_full.pdf", replace as(pdf)
graph export "$output\dec_pretom_mid_mktadj_full.png", replace as(png) width(2400)

di _n "Done."

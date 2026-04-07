/*==============================================================================
  _appendix_fullsample.do

  Appendix: Full-sample (1927-2025) PreTOM vs Rest analysis.
  Shows the effect exists across the entire history, not just post-1980.

  Produces:
    1. Table: Mean daily returns (bps) by window, three subperiods
    2. Figure: Cumulative WML wealth, full sample, Window vs Rest
    3. Figure: Bar chart (market-adjusted), full sample

  Input:  $data\momentum_daily.dta
  Output: $output\table_ia_fullsample.tex
          $output\cumwml_fullsample.pdf
          $output\barchart_mktadj_fullsample.pdf
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:/Users/danie/Dropbox/Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap mkdir "$output"
cap log close
log using "$output\_appendix_fullsample.log", replace

cap set scheme plotplainblind
if _rc set scheme s2mono
graph set window fontface "Times New Roman"

use "$data\momentum_daily.dta", clear

sort date
gen yr = year(date)

gen window = (t >= -9 & t <= -4)
label var window "[t-9,t-4] window indicator"

* Market-adjusted returns
gen winners_ma = winners_vw - mktrf
gen losers_ma  = losers_vw  - mktrf
gen wml_ma     = wml_vw

di _n "Sample: " %td date[1] " to " %td date[_N]
di "Obs: " _N
qui tab ym
di "Months: " r(r)


/*==============================================================================
  TABLE: Mean daily returns (bps) — PreTOM vs Rest, three subperiods

  Panel A: Raw excess returns (ri - rf)
  Panel B: Market-adjusted returns (ri - rf - mktrf)
==============================================================================*/

di _n "{hline 70}"
di "TABLE: Full-sample subperiod analysis (VW, daily bps)"
di "{hline 70}"

* Returns in bps
gen wml_bps      = wml_vw * 10000
gen losers_bps   = losers_vw * 10000
gen winners_bps  = winners_vw * 10000
gen wml_ma_bps   = wml_ma * 10000
gen losers_ma_bps = losers_ma * 10000
gen winners_ma_bps = winners_ma * 10000

* Subperiod indicator
gen period = cond(yr < 1965, 1, cond(yr < 1990, 2, 3))
label define per_lbl 1 "1927-1964" 2 "1965-1989" 3 "1990-2025"
label values period per_lbl

* ── Panel A: Raw excess returns ──────────────────────────────────────────────

di _n "=== PANEL A: Raw excess returns (bps/day) ==="
di _n "--- VW WML ---"
di "  Period          Window     Rest       Diff       t(diff)     N_win   N_rest"
di "  {hline 70}"

foreach p in 1 2 3 99 {
    if `p' == 99 {
        local cond "if 1"
        local lab "Full 1927-2025"
    }
    else {
        local cond "if period == `p'"
        local lab : label per_lbl `p'
    }

    qui ttest wml_bps == 0 `cond' & window == 1
    local w_mean = r(mu_1)
    local w_t    = r(t)
    local w_n    = r(N_1)

    qui ttest wml_bps == 0 `cond' & window == 0
    local r_mean = r(mu_1)
    local r_t    = r(t)
    local r_n    = r(N_1)

    qui ttest wml_bps `cond', by(window)
    local d_t = r(t)
    local diff = `w_mean' - `r_mean'

    di "  `lab'" _col(22) %8.2f `w_mean' %10.2f `r_mean' %10.2f `diff' %10.2f `d_t' %8.0f `w_n' %8.0f `r_n'
}

di _n "--- VW Losers ---"
di "  Period          Window     Rest       Diff       t(diff)     N_win   N_rest"
di "  {hline 70}"

foreach p in 1 2 3 99 {
    if `p' == 99 {
        local cond "if 1"
        local lab "Full 1927-2025"
    }
    else {
        local cond "if period == `p'"
        local lab : label per_lbl `p'
    }

    qui ttest losers_bps == 0 `cond' & window == 1
    local w_mean = r(mu_1)
    local w_n    = r(N_1)

    qui ttest losers_bps == 0 `cond' & window == 0
    local r_mean = r(mu_1)
    local r_n    = r(N_1)

    qui ttest losers_bps `cond', by(window)
    local d_t = r(t)
    local diff = `w_mean' - `r_mean'

    di "  `lab'" _col(22) %8.2f `w_mean' %10.2f `r_mean' %10.2f `diff' %10.2f `d_t' %8.0f `w_n' %8.0f `r_n'
}

di _n "--- VW Winners ---"
di "  Period          Window     Rest       Diff       t(diff)     N_win   N_rest"
di "  {hline 70}"

foreach p in 1 2 3 99 {
    if `p' == 99 {
        local cond "if 1"
        local lab "Full 1927-2025"
    }
    else {
        local cond "if period == `p'"
        local lab : label per_lbl `p'
    }

    qui ttest winners_bps == 0 `cond' & window == 1
    local w_mean = r(mu_1)
    local w_n    = r(N_1)

    qui ttest winners_bps == 0 `cond' & window == 0
    local r_mean = r(mu_1)
    local r_n    = r(N_1)

    qui ttest winners_bps `cond', by(window)
    local d_t = r(t)
    local diff = `w_mean' - `r_mean'

    di "  `lab'" _col(22) %8.2f `w_mean' %10.2f `r_mean' %10.2f `diff' %10.2f `d_t' %8.0f `w_n' %8.0f `r_n'
}

* ── Panel B: Market-adjusted ─────────────────────────────────────────────────

di _n "=== PANEL B: Market-adjusted returns (bps/day) ==="
di _n "--- VW WML (market-adjusted = same as raw WML) ---"

di _n "--- VW Losers - Mkt ---"
di "  Period          Window     Rest       Diff       t(diff)     N_win   N_rest"
di "  {hline 70}"

foreach p in 1 2 3 99 {
    if `p' == 99 {
        local cond "if 1"
        local lab "Full 1927-2025"
    }
    else {
        local cond "if period == `p'"
        local lab : label per_lbl `p'
    }

    qui ttest losers_ma_bps == 0 `cond' & window == 1
    local w_mean = r(mu_1)
    local w_n    = r(N_1)

    qui ttest losers_ma_bps == 0 `cond' & window == 0
    local r_mean = r(mu_1)
    local r_n    = r(N_1)

    qui ttest losers_ma_bps `cond', by(window)
    local d_t = r(t)
    local diff = `w_mean' - `r_mean'

    di "  `lab'" _col(22) %8.2f `w_mean' %10.2f `r_mean' %10.2f `diff' %10.2f `d_t' %8.0f `w_n' %8.0f `r_n'
}

di _n "--- VW Winners - Mkt ---"
di "  Period          Window     Rest       Diff       t(diff)     N_win   N_rest"
di "  {hline 70}"

foreach p in 1 2 3 99 {
    if `p' == 99 {
        local cond "if 1"
        local lab "Full 1927-2025"
    }
    else {
        local cond "if period == `p'"
        local lab : label per_lbl `p'
    }

    qui ttest winners_ma_bps == 0 `cond' & window == 1
    local w_mean = r(mu_1)
    local w_n    = r(N_1)

    qui ttest winners_ma_bps == 0 `cond' & window == 0
    local r_mean = r(mu_1)
    local r_n    = r(N_1)

    qui ttest winners_ma_bps `cond', by(window)
    local d_t = r(t)
    local diff = `w_mean' - `r_mean'

    di "  `lab'" _col(22) %8.2f `w_mean' %10.2f `r_mean' %10.2f `diff' %10.2f `d_t' %8.0f `w_n' %8.0f `r_n'
}


/*==============================================================================
  MONTHLY COMPOUNDED RETURNS — for t-stats and wealth calculations
==============================================================================*/

preserve

* Log returns for compounding
foreach v in winners_ma losers_ma wml_ma winners_vw losers_vw wml_vw {
    gen lr_`v'_win  = cond(window == 1, ln(1 + `v'), 0)
    gen lr_`v'_rest = cond(window == 0, ln(1 + `v'), 0)
    gen lr_`v'_full = ln(1 + `v')
}

* Count trading days per window-month
gen n_win  = (window == 1)
gen n_rest = (window == 0)

* Collapse to month level
collapse (sum) lr_* n_win n_rest (first) period yr, by(ym)

* Monthly compounded returns (percent)
foreach v in winners_ma losers_ma wml_ma winners_vw losers_vw wml_vw {
    gen r_`v'_win  = (exp(lr_`v'_win)  - 1) * 100
    gen r_`v'_rest = (exp(lr_`v'_rest) - 1) * 100
    gen r_`v'_full = (exp(lr_`v'_full) - 1) * 100
}

* Monthly-compounded t-tests
di _n "{hline 70}"
di "MONTHLY COMPOUNDED PreTOM vs Rest (% per month, VW market-adjusted)"
di "{hline 70}"

foreach lab in "1927-1964" "1965-1989" "1990-2025" "Full 1927-2025" {
    if "`lab'" == "1927-1964"      local cond "if period == 1"
    if "`lab'" == "1965-1989"      local cond "if period == 2"
    if "`lab'" == "1990-2025"      local cond "if period == 3"
    if "`lab'" == "Full 1927-2025" local cond ""

    di _n "--- `lab' ---"

    di "  WML:"
    qui ttest r_wml_ma_win == 0 `cond'
    di "    PreTOM:  mean = " %8.4f r(mu_1) "  t = " %6.2f r(t) "  N = " r(N_1)
    qui ttest r_wml_ma_rest == 0 `cond'
    di "    Rest:    mean = " %8.4f r(mu_1) "  t = " %6.2f r(t) "  N = " r(N_1)

    di "  Losers-Mkt:"
    qui ttest r_losers_ma_win == 0 `cond'
    di "    PreTOM:  mean = " %8.4f r(mu_1) "  t = " %6.2f r(t) "  N = " r(N_1)
    qui ttest r_losers_ma_rest == 0 `cond'
    di "    Rest:    mean = " %8.4f r(mu_1) "  t = " %6.2f r(t) "  N = " r(N_1)

    di "  Winners-Mkt:"
    qui ttest r_winners_ma_win == 0 `cond'
    di "    PreTOM:  mean = " %8.4f r(mu_1) "  t = " %6.2f r(t) "  N = " r(N_1)
    qui ttest r_winners_ma_rest == 0 `cond'
    di "    Rest:    mean = " %8.4f r(mu_1) "  t = " %6.2f r(t) "  N = " r(N_1)
}


/*==============================================================================
  FIGURE: Cumulative WML wealth — full sample (1927-2025)
  Window strategy vs Rest vs Full month
==============================================================================*/

di _n "{hline 70}"
di "FIGURE: Cumulative WML wealth, full sample"
di "{hline 70}"

sort ym

* Cumulative wealth (dollar invested)
gen cum_win  = 1
gen cum_rest = 1
gen cum_full = 1

local N = _N
forvalues i = 2/`N' {
    qui replace cum_win  = cum_win[_n-1]  * (1 + r_wml_vw_win/100)  in `i'
    qui replace cum_rest = cum_rest[_n-1] * (1 + r_wml_vw_rest/100) in `i'
    qui replace cum_full = cum_full[_n-1] * (1 + r_wml_vw_full/100) in `i'
}

* Convert ym to date for x-axis
gen plot_date = dofm(ym)
format plot_date %td

di "Final wealth (full sample 1927-2025):"
di "  Window: $" %8.2f cum_win[_N]
di "  Rest:   $" %8.2f cum_rest[_N]
di "  Full:   $" %8.2f cum_full[_N]

* Log scale for readability
gen ln_win  = ln(cum_win)
gen ln_rest = ln(cum_rest)
gen ln_full = ln(cum_full)

twoway (line ln_win  plot_date, lcolor(navy)    lwidth(medthick)) ///
       (line ln_rest plot_date, lcolor(cranberry) lwidth(medthick) lpattern(dash)) ///
       (line ln_full plot_date, lcolor(gs8)     lwidth(medium)   lpattern(shortdash)), ///
    legend(order(1 "Window [t-9,t-4]" 2 "Rest of month" 3 "Full month") ///
           ring(0) pos(11) cols(1) size(medium)) ///
    ytitle("ln(Cumulative wealth)", size(medium)) ///
    xtitle("") ///
    title("") ///
    ylabel(, angle(0) labsize(medium)) ///
    xlabel(, labsize(medium)) ///
    graphregion(color(white)) plotregion(margin(small))

graph export "$output\cumwml_fullsample.pdf", replace
graph export "$output\cumwml_fullsample.png", replace width(2400)

di "Saved: cumwml_fullsample.pdf"

restore


/*==============================================================================
  FIGURE: Bar chart — Market-adjusted PreTOM vs Rest, full sample
  Same style as Figure 1 in the paper but for 1927-2025
==============================================================================*/

preserve

* Compound daily returns to monthly, separately for window and rest
foreach v in winners_ma losers_ma wml_ma {
    gen lr_`v'_win  = cond(window == 1, ln(1 + `v'), 0)
    gen lr_`v'_rest = cond(window == 0, ln(1 + `v'), 0)
}

collapse (sum) lr_*, by(ym period)

foreach v in winners_ma losers_ma wml_ma {
    gen r_`v'_win  = (exp(lr_`v'_win)  - 1) * 100
    gen r_`v'_rest = (exp(lr_`v'_rest) - 1) * 100
}

* Compute means and SEs for bar chart
* Need: mean, se for each series × window combo = 6 bars

* Full sample
local bars = 6
matrix M = J(`bars', 4, .)   // mean, se, lo, hi
local row = 0

foreach v in winners_ma losers_ma wml_ma {
    foreach w in win rest {
        local ++row
        qui sum r_`v'_`w'
        matrix M[`row', 1] = r(mean)
        matrix M[`row', 2] = r(sd) / sqrt(r(N))
        matrix M[`row', 3] = r(mean) - 1.96 * r(sd) / sqrt(r(N))
        matrix M[`row', 4] = r(mean) + 1.96 * r(sd) / sqrt(r(N))
    }
}

clear
svmat M
gen id = _n
gen group = ceil(id/2)       // 1=Winners, 2=Losers, 3=WML
gen is_window = mod(id+1, 2) // 1=Window, 0=Rest

* Labels
gen x = id + floor((id-1)/2) * 0.5
label define grp 1 "Winners-Mkt" 2 "Losers-Mkt" 3 "WML"

* Bar chart
twoway (bar M1 x if is_window == 1, barwidth(0.8) color(navy)) ///
       (bar M1 x if is_window == 0, barwidth(0.8) color(cranberry)) ///
       (rcap M3 M4 x, lcolor(black) lwidth(medium)), ///
    legend(order(1 "PreTOM [t-9,t-4]" 2 "Rest of month") ///
           ring(0) pos(11) cols(1) size(medium)) ///
    ytitle("Monthly compounded return (%)", size(medium)) ///
    xtitle("") ///
    title("") ///
    ylabel(, angle(0) labsize(medium)) ///
    xlabel(1.5 "Winners-Mkt" 4 "Losers-Mkt" 6.5 "WML", labsize(medium)) ///
    yline(0, lcolor(gs10) lpattern(dash)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    note("VW decile portfolios, market-adjusted, 1927-2025." ///
         "Whiskers show 95% confidence intervals from monthly SEs.", size(small))

graph export "$output\barchart_mktadj_fullsample.pdf", replace
graph export "$output\barchart_mktadj_fullsample.png", replace width(2400)

di "Saved: barchart_mktadj_fullsample.pdf"

restore


/*==============================================================================
  FIGURE: Bar chart — Market-adjusted PreTOM vs Rest, 1927-1964 only
==============================================================================*/

preserve

keep if yr < 1965

foreach v in winners_ma losers_ma wml_ma {
    gen lr_`v'_win  = cond(window == 1, ln(1 + `v'), 0)
    gen lr_`v'_rest = cond(window == 0, ln(1 + `v'), 0)
}

collapse (sum) lr_*, by(ym)

foreach v in winners_ma losers_ma wml_ma {
    gen r_`v'_win  = (exp(lr_`v'_win)  - 1) * 100
    gen r_`v'_rest = (exp(lr_`v'_rest) - 1) * 100
}

local bars = 6
matrix M2 = J(`bars', 4, .)
local row = 0

foreach v in winners_ma losers_ma wml_ma {
    foreach w in win rest {
        local ++row
        qui sum r_`v'_`w'
        matrix M2[`row', 1] = r(mean)
        matrix M2[`row', 2] = r(sd) / sqrt(r(N))
        matrix M2[`row', 3] = r(mean) - 1.96 * r(sd) / sqrt(r(N))
        matrix M2[`row', 4] = r(mean) + 1.96 * r(sd) / sqrt(r(N))
    }
}

clear
svmat M2, names(M)
gen id = _n
gen is_window = mod(id+1, 2)
gen x = id + floor((id-1)/2) * 0.5

twoway (bar M1 x if is_window == 1, barwidth(0.8) color(navy)) ///
       (bar M1 x if is_window == 0, barwidth(0.8) color(cranberry)) ///
       (rcap M3 M4 x, lcolor(black) lwidth(medium)), ///
    legend(order(1 "PreTOM [t-9,t-4]" 2 "Rest of month") ///
           ring(0) pos(11) cols(1) size(medium)) ///
    ytitle("Monthly compounded return (%)", size(medium)) ///
    xtitle("") ///
    title("") ///
    ylabel(, angle(0) labsize(medium)) ///
    xlabel(1.5 "Winners-Mkt" 4 "Losers-Mkt" 6.5 "WML", labsize(medium)) ///
    yline(0, lcolor(gs10) lpattern(dash)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    note("VW decile portfolios, market-adjusted, 1927-1964." ///
         "Whiskers show 95% confidence intervals from monthly SEs.", size(small))

graph export "$output\barchart_mktadj_pre1965.pdf", replace
graph export "$output\barchart_mktadj_pre1965.png", replace width(2400)

di "Saved: barchart_mktadj_pre1965.pdf"

restore


/*==============================================================================
  LaTeX TABLE: Full-sample subperiod results

  Three columns: 1927-1979, 1980-2025, Full 1927-2025
  Rows: WML PreTOM, WML Rest, Diff (t-stat), Losers-Mkt PreTOM, ...
==============================================================================*/

preserve

foreach v in winners_ma losers_ma wml_ma {
    gen lr_`v'_win  = cond(window == 1, ln(1 + `v'), 0)
    gen lr_`v'_rest = cond(window == 0, ln(1 + `v'), 0)
}

collapse (sum) lr_*, by(ym period yr)

foreach v in winners_ma losers_ma wml_ma {
    gen r_`v'_win  = (exp(lr_`v'_win)  - 1) * 100
    gen r_`v'_rest = (exp(lr_`v'_rest) - 1) * 100
}

* Compute stats for each subperiod
* Store in matrices for LaTeX output

* Period 1: 1927-1964
* Period 2: 1965-1989
* Period 3: 1990-2025
* Period 4: Full

foreach per in 1 2 3 4 {
    if `per' == 1 local cond "if period == 1"
    if `per' == 2 local cond "if period == 2"
    if `per' == 3 local cond "if period == 3"
    if `per' == 4 local cond ""

    foreach v in wml_ma losers_ma winners_ma {
        * PreTOM
        qui ttest r_`v'_win == 0 `cond'
        local `v'_win_m_`per' = r(mu_1)
        local `v'_win_t_`per' = r(t)
        local `v'_win_n_`per' = r(N_1)

        * Rest
        qui ttest r_`v'_rest == 0 `cond'
        local `v'_rest_m_`per' = r(mu_1)
        local `v'_rest_t_`per' = r(t)
    }
}

* Write LaTeX table
cap file close texfile
file open texfile using "$output\table_ia_fullsample.tex", write replace

file write texfile "\begin{table}[htbp]\centering" _n
file write texfile "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" _n
file write texfile "\caption{Window Effect Across the Full Sample}" _n
file write texfile "\label{tab:fullsample}" _n
file write texfile "\begin{tabular}{lcccc}" _n
file write texfile "\toprule" _n
file write texfile " & 1927--1964 & 1965--1989 & 1990--2025 & 1927--2025 \\" _n
file write texfile "\midrule" _n

* Helper macro for 4-column rows
* WML section
file write texfile "\multicolumn{5}{l}{\textit{Panel A: WML}} \\" _n
file write texfile "[3pt]" _n

local s1 : di %6.3f `wml_ma_win_m_1'
local s2 : di %6.3f `wml_ma_win_m_2'
local s3 : di %6.3f `wml_ma_win_m_3'
local s4 : di %6.3f `wml_ma_win_m_4'
file write texfile "PreTOM [\$t{-}9,t{-}4\$] & `s1' & `s2' & `s3' & `s4' \\" _n

local s1 : di %6.2f `wml_ma_win_t_1'
local s2 : di %6.2f `wml_ma_win_t_2'
local s3 : di %6.2f `wml_ma_win_t_3'
local s4 : di %6.2f `wml_ma_win_t_4'
file write texfile " & [`s1'] & [`s2'] & [`s3'] & [`s4'] \\" _n

local s1 : di %6.3f `wml_ma_rest_m_1'
local s2 : di %6.3f `wml_ma_rest_m_2'
local s3 : di %6.3f `wml_ma_rest_m_3'
local s4 : di %6.3f `wml_ma_rest_m_4'
file write texfile "Rest of month & `s1' & `s2' & `s3' & `s4' \\" _n

local s1 : di %6.2f `wml_ma_rest_t_1'
local s2 : di %6.2f `wml_ma_rest_t_2'
local s3 : di %6.2f `wml_ma_rest_t_3'
local s4 : di %6.2f `wml_ma_rest_t_4'
file write texfile " & [`s1'] & [`s2'] & [`s3'] & [`s4'] \\" _n

file write texfile "[6pt]" _n

* Losers-Mkt section
file write texfile "\multicolumn{5}{l}{\textit{Panel B: Losers $-$ Market}} \\" _n
file write texfile "[3pt]" _n

local s1 : di %6.3f `losers_ma_win_m_1'
local s2 : di %6.3f `losers_ma_win_m_2'
local s3 : di %6.3f `losers_ma_win_m_3'
local s4 : di %6.3f `losers_ma_win_m_4'
file write texfile "PreTOM [\$t{-}9,t{-}4\$] & `s1' & `s2' & `s3' & `s4' \\" _n

local s1 : di %6.2f `losers_ma_win_t_1'
local s2 : di %6.2f `losers_ma_win_t_2'
local s3 : di %6.2f `losers_ma_win_t_3'
local s4 : di %6.2f `losers_ma_win_t_4'
file write texfile " & [`s1'] & [`s2'] & [`s3'] & [`s4'] \\" _n

local s1 : di %6.3f `losers_ma_rest_m_1'
local s2 : di %6.3f `losers_ma_rest_m_2'
local s3 : di %6.3f `losers_ma_rest_m_3'
local s4 : di %6.3f `losers_ma_rest_m_4'
file write texfile "Rest of month & `s1' & `s2' & `s3' & `s4' \\" _n

local s1 : di %6.2f `losers_ma_rest_t_1'
local s2 : di %6.2f `losers_ma_rest_t_2'
local s3 : di %6.2f `losers_ma_rest_t_3'
local s4 : di %6.2f `losers_ma_rest_t_4'
file write texfile " & [`s1'] & [`s2'] & [`s3'] & [`s4'] \\" _n

file write texfile "[6pt]" _n

* Winners-Mkt section
file write texfile "\multicolumn{5}{l}{\textit{Panel C: Winners $-$ Market}} \\" _n
file write texfile "[3pt]" _n

local s1 : di %6.3f `winners_ma_win_m_1'
local s2 : di %6.3f `winners_ma_win_m_2'
local s3 : di %6.3f `winners_ma_win_m_3'
local s4 : di %6.3f `winners_ma_win_m_4'
file write texfile "PreTOM [\$t{-}9,t{-}4\$] & `s1' & `s2' & `s3' & `s4' \\" _n

local s1 : di %6.2f `winners_ma_win_t_1'
local s2 : di %6.2f `winners_ma_win_t_2'
local s3 : di %6.2f `winners_ma_win_t_3'
local s4 : di %6.2f `winners_ma_win_t_4'
file write texfile " & [`s1'] & [`s2'] & [`s3'] & [`s4'] \\" _n

local s1 : di %6.3f `winners_ma_rest_m_1'
local s2 : di %6.3f `winners_ma_rest_m_2'
local s3 : di %6.3f `winners_ma_rest_m_3'
local s4 : di %6.3f `winners_ma_rest_m_4'
file write texfile "Rest of month & `s1' & `s2' & `s3' & `s4' \\" _n

local s1 : di %6.2f `winners_ma_rest_t_1'
local s2 : di %6.2f `winners_ma_rest_t_2'
local s3 : di %6.2f `winners_ma_rest_t_3'
local s4 : di %6.2f `winners_ma_rest_t_4'
file write texfile " & [`s1'] & [`s2'] & [`s3'] & [`s4'] \\" _n

file write texfile "[6pt]" _n

* N months
local n1 = `wml_ma_win_n_1'
local n2 = `wml_ma_win_n_2'
local n3 = `wml_ma_win_n_3'
local n4 = `wml_ma_win_n_4'
file write texfile "\midrule" _n
file write texfile "Months & `n1' & `n2' & `n3' & `n4' \\" _n

file write texfile "\bottomrule" _n
file write texfile "\end{tabular}" _n
file write texfile _n
file write texfile "\vspace{6pt}" _n
file write texfile "\begin{minipage}{0.95\textwidth}" _n
file write texfile "\footnotesize \textit{Notes.}" _n
file write texfile "Monthly compounded returns (\%) from value-weighted momentum decile portfolios" _n
file write texfile "with fixed monthly sorting." _n
file write texfile "Market-adjusted returns subtract the excess market return from winners and losers;" _n
file write texfile "WML (winners minus losers) is already market-neutral." _n
file write texfile "PreTOM is the six-day window from trading day \$t{-}9\$ to \$t{-}4\$ before month-end." _n
file write texfile "\$t\$-statistics in brackets." _n
file write texfile "\end{minipage}" _n

file write texfile "\end{table}" _n
file close texfile

di "Saved: table_ia_fullsample.tex"

restore

timer off 1
timer list

log close

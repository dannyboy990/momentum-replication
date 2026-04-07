/*==============================================================================
  _tables_vw.do

  Regenerate Tables 1, 4, 5, 6, 7, 8, tax_summary as VW, no BAS interactions.
  Uses panel_fixed_vw_reg.csv (fixed monthly sorting, 1980-2025).

  Output: table1_baseline_vw.tex ... table8_exdecjan_vw.tex, table_tax_summary_vw.tex
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\danie\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\_tables_vw.log", replace

timer on 1

/*----------------------------------------------------------------------
  LOAD & CONSTRUCT VARIABLES
----------------------------------------------------------------------*/

import delimited "$data\panel_fixed_vw_reg.csv", clear

* Rename to standard names
cap rename permno permno2
cap rename PERMNO permno
* If lowercase already
cap confirm var permno
if _rc {
    rename permno2 permno
}

* Date variables
gen stata_date = date(date, "YMD")
format stata_date %td
gen month_num = month(stata_date)
gen yr = year(stata_date)
gen ym = mofd(stata_date)
format ym %tm

* Use preTOM from v7 (already correct: t in [-9,-4])
cap rename pretom preTOM2
cap confirm var pretom
if _rc == 0 {
    rename pretom pretom_v7
}
cap confirm var preTOM2
if _rc == 0 {
    rename preTOM2 pretom_v7
}
* If preTOM came through as pretom (lowercase from CSV)
cap confirm var pretom_v7
if _rc {
    * Construct from t
    gen pretom_v7 = (t >= -9 & t <= -4)
}

* Calendar indicators
gen qtr_end   = inlist(month_num, 3, 6, 9, 12)
gen non_qtr   = !inlist(month_num, 3, 6, 9, 12)
gen dec_month = (month_num == 12)
gen jan_month = (month_num == 1)
gen notdecjan = !inlist(month_num, 12, 1)
gen post      = (t >= -3 & t <= 3)

* Interactions
gen lp        = loser * pretom_v7
gen l_post    = loser * post
gen lp_qtr    = lp * qtr_end
gen lp_dec    = lp * dec_month
gen lp_jan    = lp * jan_month
gen l_qtr     = loser * qtr_end
gen l_dec     = loser * dec_month
gen l_jan     = loser * jan_month

* Rescale to bps
replace ret_rf = ret_rf * 10000
label var ret_rf "Daily excess return (bps)"

* Weight check
bysort date decile: egen sum_w = total(w)
qui sum sum_w
di "Weight sums - min: " %6.4f r(min) "  max: " %6.4f r(max)

di _n "=== N obs: " _N " ==="
di "=== Running VW regressions (no BAS) ==="

/*----------------------------------------------------------------------
  TABLE 1: Baseline VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 1: Baseline VW"
di "{hline 70}"

eststo clear

* EW
eststo ew: reghdfe ret_rf loser lp, absorb(permno stata_date) cluster(permno stata_date)

* VW
eststo vw: reghdfe ret_rf loser lp [aw=w_l1], absorb(permno stata_date) cluster(permno stata_date)

esttab ew vw using "$output\table1_baseline_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("EW" "VW") ///
    title("Baseline Window Effect on Daily Returns") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Baseline Window Effect on Daily Returns}" ///
            "\label{tab:baseline}") ///
    postfoot("\midrule" ///
            "\multicolumn{3}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Loser equals one for stocks in the bottom momentum decile." ///
            "PreTOM equals one during the six-day pre-month-end window (trading days $t{-}9$ to $t{-}4$)." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date." ///
            "VW uses lagged market-capitalization weights within each decile-date cell." ///
            "Sample: CRSP common stocks, 1980--2025.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


/*----------------------------------------------------------------------
  TABLE 4: Subperiod VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 4: Subperiod VW"
di "{hline 70}"

eststo clear

* Pre-2003 (equal split at July 2002)
eststo pre03: reghdfe ret_rf loser lp [aw=w_l1] if stata_date < td(01jul2002), ///
    absorb(permno stata_date) cluster(permno stata_date)

* Post-2002
eststo post02: reghdfe ret_rf loser lp [aw=w_l1] if stata_date >= td(01jul2002), ///
    absorb(permno stata_date) cluster(permno stata_date)

esttab pre03 post02 using "$output\table4_subperiod_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("1980--2002" "2002--2025") ///
    title("Subperiod Stability of the Window Effect") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Subperiod Stability of the Window Effect}" ///
            "\label{tab:subperiod}") ///
    postfoot("\midrule" ///
            "\multicolumn{3}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Value-weighted specifications throughout." ///
            "Sample split at midpoint (July 2002)." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


/*----------------------------------------------------------------------
  TABLE 5: Non-quarter-end VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 5: Non-quarter-end VW"
di "{hline 70}"

eststo clear

eststo nonqtr: reghdfe ret_rf loser lp [aw=w_l1] if non_qtr == 1, ///
    absorb(permno stata_date) cluster(permno stata_date)

esttab nonqtr using "$output\table5_nonqtr_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("Non-QE, VW") ///
    title("Window Effect in Non-Quarter-End Months") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Window Effect in Non-Quarter-End Months}" ///
            "\label{tab:nonqtr}") ///
    postfoot("\midrule" ///
            "\multicolumn{2}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Value-weighted. Sample restricted to non-quarter-end months" ///
            "(Jan, Feb, Apr, May, Jul, Aug, Oct, Nov)." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


/*----------------------------------------------------------------------
  TABLE 6: Quarter-end amplification VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 6: Quarter-end amplification VW"
di "{hline 70}"

eststo clear

eststo qtramp: reghdfe ret_rf loser lp lp_qtr l_qtr [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)

esttab qtramp using "$output\table6_qtr_amplify_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("VW") ///
    title("Quarter-End Amplification of the Window Effect") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Quarter-End Amplification of the Window Effect}" ///
            "\label{tab:qtramp}") ///
    postfoot("\midrule" ///
            "\multicolumn{2}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Value-weighted. QtrEnd equals one in March, June, September, December." ///
            "A significant Loser $\times$ PreTOM $\times$ QtrEnd would indicate" ///
            "amplification at quarter-ends, consistent with window dressing." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


/*----------------------------------------------------------------------
  TABLE 7: December/January interactions VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 7: Dec/Jan interactions VW"
di "{hline 70}"

eststo clear

eststo decjan: reghdfe ret_rf loser lp lp_dec lp_jan l_dec l_jan [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)

esttab decjan using "$output\table7_decjan_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("VW") ///
    title("December and January Interactions") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{December and January Interactions}" ///
            "\label{tab:decjan}") ///
    postfoot("\midrule" ///
            "\multicolumn{2}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Value-weighted. Dec and Jan are monthly indicator variables." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


/*----------------------------------------------------------------------
  TABLE 8: Excluding Dec/Jan VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 8: Excluding Dec/Jan VW"
di "{hline 70}"

eststo clear

eststo exdecjan: reghdfe ret_rf loser lp [aw=w_l1] if notdecjan == 1, ///
    absorb(permno stata_date) cluster(permno stata_date)

esttab exdecjan using "$output\table8_exdecjan_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("Ex Dec/Jan, VW") ///
    title("Window Effect Excluding December and January") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Window Effect Excluding December and January}" ///
            "\label{tab:exdecjan}") ///
    postfoot("\midrule" ///
            "\multicolumn{2}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Value-weighted. Sample excludes December and January." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


/*----------------------------------------------------------------------
  TAX SUMMARY (Tables 5-8 combined) VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TAX SUMMARY: Combined VW"
di "{hline 70}"

eststo clear

* (1) Non-QE
eststo col1: reghdfe ret_rf loser lp [aw=w_l1] if non_qtr == 1, ///
    absorb(permno stata_date) cluster(permno stata_date)

* (2) QE interaction
eststo col2: reghdfe ret_rf loser lp lp_qtr l_qtr [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)

* (3) Dec/Jan
eststo col3: reghdfe ret_rf loser lp lp_dec lp_jan l_dec l_jan [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)

* (4) Ex Dec/Jan
eststo col4: reghdfe ret_rf loser lp [aw=w_l1] if notdecjan == 1, ///
    absorb(permno stata_date) cluster(permno stata_date)

esttab col1 col2 col3 col4 using "$output\table_tax_summary_vw.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("Non-QE Only" "QE Interaction" "Dec/Jan" "Ex Dec/Jan") ///
    title("Distinguishing Dash-for-Cash from Tax-Loss Selling") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Distinguishing Dash-for-Cash from Tax-Loss Selling}" ///
            "\label{tab:taxsummary}") ///
    postfoot("\midrule" ///
            "\multicolumn{5}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "All specifications are value-weighted with firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date." ///
            "Column 1 restricts to non-quarter-end months." ///
            "Column 2 interacts with a quarter-end indicator." ///
            "Column 3 adds December and January interactions." ///
            "Column 4 excludes December and January.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")


timer off 1
timer list 1

di _n "{hline 70}"
di "DONE — VW tables"
di "{hline 70}"

log close

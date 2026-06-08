/*==============================================================================
  _tables_vw.do

  Regenerate Tables 1, 4, 5, 6, 7, 8, tax_summary as VW, no BAS interactions.
  Uses panel_fixed_vw_reg.csv (fixed monthly sorting, 1980-2025).

  Output: table1_baseline_vw.tex ... table8_exdecjan_vw.tex, table_tax_summary_vw.tex
==============================================================================*/

clear all
set more off

if "$root" == "" global root "."
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

* Merge daily Mkt-RF and convert LHS to market-adjusted excess return
* (= r_i - Mkt, in basis points), matching the dep-var symbol r_i - r^m
* used in the published table notes. With firm + date FE, slopes are
* mathematically identical whether the LHS is r_i - rf or r_i - Mkt
* (the per-date constant rf is absorbed by the date FE), so this rename
* does not move any reported coefficient.
preserve
    use "$data/momentum_daily.dta", clear
    keep date mktrf
    rename date stata_date
    tempfile mkt
    save `mkt'
restore
merge m:1 stata_date using `mkt', keep(match master) nogen

gen ret_mkt = (ret_rf - mktrf) * 10000
label var ret_mkt "Daily market-adjusted return r_i - Mkt (bps)"
drop ret_rf mktrf

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
eststo ew: reghdfe ret_mkt loser lp, absorb(permno stata_date) cluster(permno stata_date)

* VW
eststo vw: reghdfe ret_mkt loser lp [aw=w_l1], absorb(permno stata_date) cluster(permno stata_date)

* Table 1: baseline panel regression
qui run "$code/_polish_cells.do"
estimates restore vw
pcell loser
local b1v "`r(b)'"
local t1v "`r(t)'"
pcell lp
local b2v "`r(b)'"
local t2v "`r(t)'"
commaN e(N)
local Nv "`r(n)'"
estimates restore ew
pcell loser
local b1e "`r(b)'"
local t1e "`r(t)'"
pcell lp
local b2e "`r(b)'"
local t2e "`r(t)'"
commaN e(N)
local Ne "`r(n)'"

tempname fh
file open `fh' using "$output\table1_baseline_vw.tex", write replace
file write `fh' "\begin{table}[htbp]\centering" _n
file write `fh' "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" _n
file write `fh' "\caption{Loser PreTOM Underperformance: Baseline Panel Regression}" _n
file write `fh' "\label{tab:baseline}" _n
file write `fh' "\begin{tabular}{l*{2}{d}}" _n
file write `fh' "\toprule" _n
file write `fh' "                          &\multicolumn{1}{c}{(1)}&\multicolumn{1}{c}{(2)}\\" _n
file write `fh' "                          &\multicolumn{1}{c}{VW}&\multicolumn{1}{c}{EW}\\" _n
file write `fh' "\midrule" _n
file write `fh' "Loser (\$\beta_{1}\$)                & `b1v'  & `b1e' \\" _n
file write `fh' "                                   & `t1v'        & `t1e'       \\" _n
file write `fh' "Loser \$\times\$ PreTOM (\$\beta_{2}\$)& `b2v' & `b2e'   \\" _n
file write `fh' "                                   & `t2v'       & `t2e'      \\" _n
file write `fh' "\midrule" _n
file write `fh' "Sample                             & {1980--2025}    & {1980--2025}    \\" _n
file write `fh' "Fixed effects                      & {Stock, Date}   & {Stock, Date}   \\" _n
file write `fh' "Observations                       & {`Nv'}& {`Ne'}\\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "" _n
file write `fh' "\vspace{0.4em}" _n
file write `fh' "\begin{minipage}{\textwidth}" _n
file write `fh' "\footnotesize \textit{Notes.}" _n
file write `fh' "Estimates of equation~(\ref{eq:baseline}) on the full CRSP panel of NYSE/AMEX/NASDAQ stocks, 1980--2025." _n
file write `fh' "Dependent variable is the stock's daily excess return over the value-weighted CRSP market, \$\ExRet_{i,t} = r_{i,t} - r^{m}_{t}\$, in basis points." _n
file write `fh' "\$\Loser_{i,t}\$ is an indicator equal to one if stock \$i\$ is in the bottom momentum decile on day \$t\$." _n
file write `fh' "\$\PreTOM_{t}\$ is an indicator for the six trading days \$[\tau{-}9, \tau{-}4]\$ before month-end (\$\tau\$ is the last trading day)." _n
file write `fh' "All specifications include stock and date fixed effects." _n
file write `fh' "\$t\$-statistics are in parentheses; standard errors are two-way clustered by stock and date." _n
file write `fh' "Column~1 weights observations by lagged market capitalization within decile-date." _n
file write `fh' "\sym{*} \$p<0.10\$, \sym{**} \$p<0.05\$, \sym{***} \$p<0.01\$." _n
file write `fh' "\end{minipage}" _n
file write `fh' "\end{table}" _n
file close `fh'


/*----------------------------------------------------------------------
  TABLE 4: Subperiod VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 4: Subperiod VW"
di "{hline 70}"

eststo clear

* Pre-2003 (equal split at July 2002)
eststo pre03: reghdfe ret_mkt loser lp [aw=w_l1] if stata_date < td(01jul2002), ///
    absorb(permno stata_date) cluster(permno stata_date)

* Post-2002
eststo post02: reghdfe ret_mkt loser lp [aw=w_l1] if stata_date >= td(01jul2002), ///
    absorb(permno stata_date) cluster(permno stata_date)

* Table 4: subperiod stability
qui run "$code/_polish_cells.do"
estimates restore pre03
pcell loser
local b1a "`r(b)'"
local t1a "`r(t)'"
pcell lp
local b2a "`r(b)'"
local t2a "`r(t)'"
commaN e(N)
local Na "`r(n)'"
local r2a = strtrim(string(e(r2_within),"%5.4f"))
estimates restore post02
pcell loser
local b1b "`r(b)'"
local t1b "`r(t)'"
pcell lp
local b2b "`r(b)'"
local t2b "`r(t)'"
commaN e(N)
local Nb "`r(n)'"
local r2b = strtrim(string(e(r2_within),"%5.4f"))

tempname fh
file open `fh' using "$output\table4_subperiod_vw.tex", write replace
file write `fh' "\begin{table}[htbp]\centering" _n
file write `fh' "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" _n
file write `fh' "\caption{Subperiod Stability of the PreTOM Effect}" _n
file write `fh' "\label{tab:subperiod}" _n
file write `fh' "\begin{tabular}{l*{2}{d}}" _n
file write `fh' "\toprule" _n
file write `fh' "            &\multicolumn{1}{c}{(1)}&\multicolumn{1}{c}{(2)}\\" _n
file write `fh' "            &\multicolumn{1}{c}{1980--2002}&\multicolumn{1}{c}{2002--2025}\\" _n
file write `fh' "\midrule" _n
file write `fh' "Loser       & `b1a'           & `b1b'  \\" _n
file write `fh' "            & `t1a'        & `t1b'        \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Loser \$\times\$ PreTOM& `b2a' & `b2b'  \\" _n
file write `fh' "            & `t2a'       & `t2b'       \\" _n
file write `fh' "\midrule" _n
file write `fh' "Fixed effects& {Stock, Date}  & {Stock, Date}   \\" _n
file write `fh' "Observations& {`Na'}& {`Nb'}\\" _n
file write `fh' "Within \$R^2\$& {`r2a'}        & {`r2b'}        \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "" _n
file write `fh' "\vspace{0.4em}" _n
file write `fh' "\begin{minipage}{\textwidth}" _n
file write `fh' "\footnotesize \textit{Notes.}" _n
file write `fh' "Estimates of equation~(\ref{eq:baseline}) on subperiods. Dependent variable is the daily market-adjusted return (\$r_{i,t} - r^m_t\$, in excess of the value-weighted CRSP market return), in basis points." _n
file write `fh' "Returns are value-weighted." _n
file write `fh' "Sample split at midpoint (July 2002)." _n
file write `fh' "All specifications include stock and date fixed effects." _n
file write `fh' "\$t\$-statistics are in parentheses; standard errors are two-way clustered by stock and date." _n
file write `fh' "Momentum deciles use NYSE breakpoints applied to all NYSE, AMEX, and NASDAQ stocks in CRSP; assignments are held constant within each calendar month." _n
file write `fh' "\sym{*} \$p<0.10\$, \sym{**} \$p<0.05\$, \sym{***} \$p<0.01\$." _n
file write `fh' "\end{minipage}" _n
file write `fh' "\end{table}" _n
file close `fh'


/*----------------------------------------------------------------------
  TABLE 5: Non-quarter-end VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 5: Non-quarter-end VW"
di "{hline 70}"

eststo clear
qui run "$code/_polish_cells.do"
local bb = char(92) + char(92)   // literal LaTeX line break \\ inside \shortstack

* Table 5: window-dressing and tax-loss falsification (4 columns)
* (1) Non-quarter-end months
reghdfe ret_mkt loser lp [aw=w_l1] if non_qtr == 1, absorb(permno stata_date) cluster(permno stata_date)
pcell loser
local L1 "`r(b)'"
local Lt1 "`r(t)'"
pcell lp
local P1 "`r(b)'"
local Pt1 "`r(t)'"
pcell _cons
local C1 "`r(b)'"
local Ct1 "`r(t)'"
commaN e(N)
local N1 "`r(n)'"
local R1 = strtrim(string(e(r2_within),"%5.4f"))
* (2) Non-December months
reghdfe ret_mkt loser lp [aw=w_l1] if dec_month == 0, absorb(permno stata_date) cluster(permno stata_date)
pcell loser
local L2 "`r(b)'"
local Lt2 "`r(t)'"
pcell lp
local P2 "`r(b)'"
local Pt2 "`r(t)'"
pcell _cons
local C2 "`r(b)'"
local Ct2 "`r(t)'"
commaN e(N)
local N2 "`r(n)'"
local R2 = strtrim(string(e(r2_within),"%5.4f"))
* (3) Full sample with quarter-end interactions
reghdfe ret_mkt loser lp l_qtr lp_qtr [aw=w_l1], absorb(permno stata_date) cluster(permno stata_date)
pcell loser
local L3 "`r(b)'"
local Lt3 "`r(t)'"
pcell lp
local P3 "`r(b)'"
local Pt3 "`r(t)'"
pcell l_qtr
local LQ3 "`r(b)'"
local LQt3 "`r(t)'"
pcell lp_qtr
local PQ3 "`r(b)'"
local PQt3 "`r(t)'"
pcell _cons
local C3 "`r(b)'"
local Ct3 "`r(t)'"
commaN e(N)
local N3 "`r(n)'"
local R3 = strtrim(string(e(r2_within),"%5.4f"))
* (4) Full sample baseline
reghdfe ret_mkt loser lp [aw=w_l1], absorb(permno stata_date) cluster(permno stata_date)
pcell loser
local L4 "`r(b)'"
local Lt4 "`r(t)'"
pcell lp
local P4 "`r(b)'"
local Pt4 "`r(t)'"
pcell _cons
local C4 "`r(b)'"
local Ct4 "`r(t)'"
commaN e(N)
local N4 "`r(n)'"
local R4 = strtrim(string(e(r2_within),"%5.4f"))

tempname fh
file open `fh' using "$output\table5_nonqtr_vw.tex", write replace
file write `fh' "\begin{table}[htbp]\centering" _n
file write `fh' "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" _n
file write `fh' "\caption{Window Dressing and Tax-Loss Falsification}" _n
file write `fh' "\label{tab:nonqtr}" _n
file write `fh' "\small" _n
file write `fh' "\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}l*{4}{d}}" _n
file write `fh' "\toprule" _n
file write `fh' "                                             & {(1)} & {(2)} & {(3)} & {(4)} \\" _n
file write `fh' "                                             & {\shortstack{Non-QE`bb'months}} & {\shortstack{Non-December`bb'months}} & {\shortstack{Full sample,`bb'QE interaction}} & {\shortstack{Full sample`bb'baseline}} \\" _n
file write `fh' "\midrule" _n
file write `fh' "Loser                                        & `L1'  & `L2'   & `L3'  & `L4'   \\" _n
file write `fh' "                                             & `Lt1'        & `Lt2'        & `Lt3'        & `Lt4'        \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Loser \$\times\$ PreTOM                        & `P1' & `P2' & `P3' & `P4' \\" _n
file write `fh' "                                             & `Pt1'       & `Pt2'       & `Pt3'       & `Pt4'       \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Loser \$\times\$ QtrEnd                        & {}              & {}              & `LQ3'          & {}              \\" _n
file write `fh' "                                             & {}              & {}              & `LQt3'       & {}              \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Loser \$\times\$ PreTOM \$\times\$ QtrEnd        & {}              & {}              & `PQ3'           & {}              \\" _n
file write `fh' "                                             & {}              & {}              & `PQt3'        & {}              \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Constant                                     & `C1'  & `C2'          & `C3'  & `C4'   \\" _n
file write `fh' "                                             & `Ct1'       & `Ct2'        & `Ct3'       & `Ct4'       \\" _n
file write `fh' "\midrule" _n
file write `fh' "Fixed effects                                & {Stock, Date}   & {Stock, Date}   & {Stock, Date}   & {Stock, Date}   \\" _n
file write `fh' "Observations                                 & {`N1'}& {`N2'}& {`N3'}& {`N4'}\\" _n
file write `fh' "Within \$R^2\$                                 & {`R1'}        & {`R2'}        & {`R3'}        & {`R4'}        \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular*}" _n
file write `fh' "" _n
file write `fh' "\vspace{6pt}" _n
file write `fh' "\noindent\begin{minipage}{\textwidth}" _n
file write `fh' "\footnotesize \textit{Notes.}" _n
file write `fh' "Dependent variable is the daily market-adjusted return (\$r_{i,t} - r^m_t\$, in excess of the value-weighted CRSP market return), in basis points. Returns are value-weighted using lagged market-capitalization weights. Column~(1) restricts the sample to non-quarter-end months (Jan, Feb, Apr, May, Jul, Aug, Oct, Nov); window dressing would be least relevant in these months, yet the Loser~\$\times\$~PreTOM coefficient is essentially identical to the full-sample estimate. Column~(2) restricts the sample to non-December months; tax-loss harvesting is most concentrated in December, and excluding it leaves the Loser~\$\times\$~PreTOM coefficient essentially unchanged. Column~(3) estimates the full sample with quarter-end interactions; QtrEnd equals one in March, June, September, December. The triple interaction Loser~\$\times\$~PreTOM~\$\times\$~QtrEnd is small and statistically indistinguishable from zero, indicating no quarter-end amplification. Column~(4) reproduces the full-sample baseline from Table~\ref{tab:baseline} of the main paper for reference. All specifications include stock and date fixed effects. \$t\$-statistics (in parentheses) are computed from standard errors two-way clustered by stock and date. Momentum deciles use NYSE breakpoints applied to all NYSE, AMEX, and NASDAQ stocks in CRSP; assignments are held constant within each calendar month. \sym{*} \$p<0.10\$, \sym{**} \$p<0.05\$, \sym{***} \$p<0.01\$. Sample: 1980--2025." _n
file write `fh' "\end{minipage}" _n
file write `fh' "\end{table}" _n
file close `fh'


/*----------------------------------------------------------------------
  TABLE 6: Quarter-end amplification VW
----------------------------------------------------------------------*/

di _n "{hline 70}"
di "TABLE 6: Quarter-end amplification VW"
di "{hline 70}"

eststo clear

eststo qtramp: reghdfe ret_mkt loser lp lp_qtr l_qtr [aw=w_l1], ///
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
            "Dependent variable is the daily stock return in excess of the risk-free rate ($r_{i,t} - r^f_t$), in basis points." ///
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

eststo decjan: reghdfe ret_mkt loser lp lp_dec lp_jan l_dec l_jan [aw=w_l1], ///
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
            "Dependent variable is the daily stock return in excess of the risk-free rate ($r_{i,t} - r^f_t$), in basis points." ///
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

eststo exdecjan: reghdfe ret_mkt loser lp [aw=w_l1] if notdecjan == 1, ///
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
            "Dependent variable is the daily stock return in excess of the risk-free rate ($r_{i,t} - r^f_t$), in basis points." ///
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
eststo col1: reghdfe ret_mkt loser lp [aw=w_l1] if non_qtr == 1, ///
    absorb(permno stata_date) cluster(permno stata_date)

* (2) QE interaction
eststo col2: reghdfe ret_mkt loser lp lp_qtr l_qtr [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)

* (3) Dec/Jan
eststo col3: reghdfe ret_mkt loser lp lp_dec lp_jan l_dec l_jan [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)

* (4) Ex Dec/Jan
eststo col4: reghdfe ret_mkt loser lp [aw=w_l1] if notdecjan == 1, ///
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
            "Dependent variable is the daily stock return in excess of the risk-free rate ($r_{i,t} - r^f_t$), in basis points." ///
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
di "DONE - VW tables"
di "{hline 70}"

log close

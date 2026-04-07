/*==============================================================================
  _table2_bas_contemp.do

  Table 2: Window Effect and Bid-Ask Spread (contemporaneous BAS, not lagged)
  Cols 1 & 3: full sample (panel_fixed_vw_reg.csv)
  Cols 2 & 4: BAS subsample (panel_fixed_bas_reg.csv)
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\danie\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\_table2_bas_contemp.log", replace

timer on 1

/*----------------------------------------------------------------------
  COLS 1 & 3: Baseline on full sample (to match Table 1)
----------------------------------------------------------------------*/

import delimited "$data\panel_fixed_vw_reg.csv", clear

* Rename
cap rename permno permno2
cap rename PERMNO permno
cap confirm var permno
if _rc {
    rename permno2 permno
}

* Date variables
gen stata_date = date(date, "YMD")
format stata_date %td

* Use preTOM from v7
cap rename pretom preTOM2
cap confirm var pretom
if _rc == 0 {
    rename pretom pretom_v7
}
cap confirm var preTOM2
if _rc == 0 {
    rename preTOM2 pretom_v7
}
cap confirm var pretom_v7
if _rc {
    gen pretom_v7 = (t >= -9 & t <= -4)
}

* Interactions
gen lp      = loser * pretom_v7

* Rescale to bps
replace ret_rf = ret_rf * 10000
label var ret_rf "Daily excess return (bps)"

di _n "=== Full sample N obs: " _N " ==="

eststo clear

* (1) EW baseline — full sample
eststo ew: reghdfe ret_rf loser lp, absorb(permno stata_date) cluster(permno stata_date)

* (3) VW baseline — full sample
eststo vw: reghdfe ret_rf loser lp [aw=w_l1], absorb(permno stata_date) cluster(permno stata_date)


/*----------------------------------------------------------------------
  COLS 2 & 4: BAS interaction on BAS subsample
----------------------------------------------------------------------*/

import delimited "$data\panel_fixed_bas_reg.csv", clear

* Rename
cap rename permno permno2
cap rename PERMNO permno
cap confirm var permno
if _rc {
    rename permno2 permno
}

* Date variables
gen stata_date = date(date, "YMD")
format stata_date %td

* Use preTOM from v7
cap confirm var pretom
if _rc == 0 {
    rename pretom pretom_v7
}
cap confirm var pretom_v7
if _rc {
    gen pretom_v7 = (t >= -9 & t <= -4)
}

* Interactions
gen lp      = loser * pretom_v7
gen l_bas   = loser * bas
gen lp_bas  = lp * bas

* Rescale to bps
replace ret_rf = ret_rf * 10000
label var ret_rf "Daily excess return (bps)"

di _n "=== BAS subsample N obs: " _N " ==="

* (2) EW + BAS — BAS subsample
eststo ew_bas: reghdfe ret_rf loser l_bas lp lp_bas, absorb(permno stata_date) cluster(permno stata_date)

* (4) VW + BAS — BAS subsample
eststo vw_bas: reghdfe ret_rf loser l_bas lp lp_bas [aw=w_l1], absorb(permno stata_date) cluster(permno stata_date)

esttab ew ew_bas vw vw_bas using "$output\table2_bas_contemp.tex", replace ///
    cells(b(fmt(3) star) se(fmt(3) par)) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    mtitles("Equal Weighted" "EW + BAS" "Value Weighted" "VW + BAS") ///
    title("Window Effect and Bid-Ask Spread") ///
    label booktabs ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Window Effect and Bid-Ask Spread}" ///
            "\label{tab:bas}") ///
    postfoot("\midrule" ///
            "\multicolumn{5}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
            "Dependent variable is daily excess return in basis points." ///
            "Columns 1 and 3 reproduce the baseline from Table~\ref{tab:baseline} on the full sample." ///
            "Columns 2 and 4 restrict to the subsample with non-missing bid-ask spreads." ///
            "BAS is the contemporaneous bid-ask spread as a fraction of the quote midpoint." ///
            "A positive coefficient on Loser $\times$ PreTOM $\times$ BAS indicates" ///
            "that the window effect is weaker for illiquid (high-spread) stocks," ///
            "i.e., concentrated among liquid losers." ///
            "All specifications include firm and date fixed effects." ///
            "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
            "\bottomrule" ///
            "\end{tabular}" ///
            "\end{table}")

timer off 1
timer list 1

di _n "{hline 70}"
di "DONE — Table 2 contemporaneous BAS"
di "{hline 70}"

log close

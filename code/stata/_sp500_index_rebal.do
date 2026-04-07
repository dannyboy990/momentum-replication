/*==============================================================================
  _sp500_index_rebal.do

  Test: does the PreTOM window effect exist among non-S&P 500 stocks?
  If yes, index rebalancing cannot explain the pattern.

  Input:  crsp_1927-2025_fixed_sorting_full.parquet (via Python CSV extract)
  Output: Table (LaTeX) + log
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\dnatha\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\_sp500_index_rebal.log", replace

* Extract SP500 panel from parquet if needed
cap confirm file "$data/panel_fixed_sp500_reg.csv"
if _rc {
    di "Extracting S&P 500 panel from parquet..."
    shell py -c "import pyarrow.parquet as pq; import pandas as pd; import os; root=r'$root'; data=os.path.join(root,'data'); pf=os.path.join(data,'crsp_1927-2025_fixed_sorting_full.parquet'); df=pq.read_table(pf).to_pandas(); df['date']=pd.to_datetime(df['date']); df=df[df['date'].dt.year>=1980].copy(); df['ret_rf']=df['return']-df['RF']; cols=['date','PERMNO','decile','ret_rf','t','loser','preTOM','w','w_l1','in_sp500']; print(f'Writing SP500 panel: {len(df):,} rows'); df[cols].to_csv(os.path.join(data,'panel_fixed_sp500_reg.csv'),index=False); print('Done.')"
}

import delimited "$data\panel_fixed_sp500_reg.csv", clear

* Rename
cap rename permno permno2
cap rename PERMNO permno
cap confirm var permno
if _rc {
    rename permno2 permno
}

* Convert date
gen stata_date = date(date, "YMD")
format stata_date %td
drop date

* Use preTOM from data
cap rename pretom pretom_v7
cap confirm var pretom_v7
if _rc {
    gen pretom_v7 = (t >= -9 & t <= -4)
}

* Return in bps
replace ret_rf = ret_rf * 10000

* Interaction
gen lp = loser * pretom_v7

di _n "{hline 70}"
di "INDEX REBALANCING TEST: S&P 500 vs NON-S&P 500"
di "{hline 70}"

* Sample counts
di _n "=== SAMPLE ==="
tab in_sp500 loser

* --- VW regressions for table ---

* Col 1: Non-S&P 500 VW
di _n "=== NON-S&P 500 VW ==="
reghdfe ret_rf loser lp if in_sp500 == 0 [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)
est store non_sp500

* Col 2: S&P 500 VW
di _n "=== S&P 500 VW ==="
reghdfe ret_rf loser lp if in_sp500 == 1 [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)
est store sp500

* Col 3: Full sample with S&P 500 interaction (VW)
di _n "=== FULL SAMPLE WITH S&P 500 INTERACTION (VW) ==="
gen lp_sp = lp * in_sp500
gen l_sp = loser * in_sp500
reghdfe ret_rf loser lp l_sp lp_sp [aw=w_l1], ///
    absorb(permno stata_date) cluster(permno stata_date)
est store full_interact

* --- Output table ---
esttab non_sp500 sp500 full_interact using "$output/table_sp500_rebal.tex", ///
    replace booktabs ///
    cells(b(fmt(3) star) se(par fmt(3))) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    keep(loser lp l_sp lp_sp) ///
    order(loser lp l_sp lp_sp) ///
    varlabels(loser "Loser" ///
              lp "Loser $\times$ PreTOM" ///
              l_sp "Loser $\times$ S\&P~500" ///
              lp_sp "Loser $\times$ PreTOM $\times$ S\&P~500") ///
    mgroups("Non-S\&P~500" "S\&P~500" "Full Sample", ///
        pattern(1 1 1) span ///
        prefix(\multicolumn{@span}{c}{) suffix(}) erepeat(\cmidrule(lr){@span})) ///
    mtitles("VW" "VW" "VW") ///
    stats(N r2_within, fmt(%12.0fc %9.4f) ///
        labels("Observations" "Within \$R^2\$")) ///
    label nonotes ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Window Effect and S\&P~500 Membership}" ///
            "\label{tab:sp500rebal}" ///
            "\begin{tabular}{l*{3}{c}}" ///
            "\toprule") ///
    postfoot("\midrule" ///
             "\multicolumn{4}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
             "Dependent variable is daily excess return in basis points." ///
             "Value-weighted using lagged market-capitalization weights." ///
             "Columns~(1) and~(2) restrict the sample to non-S\&P~500 and S\&P~500" ///
             "constituent stocks, respectively." ///
             "Column~(3) estimates the full sample with an S\&P~500 interaction;" ///
             "an insignificant Loser~$\times$~PreTOM~$\times$~S\&P~500 coefficient" ///
             "indicates that the window effect does not differ across index membership." ///
             "All specifications include firm and date fixed effects." ///
             "Standard errors (in parentheses) are two-way clustered by firm and date.}\\" ///
             "\bottomrule" ///
             "\end{tabular}" ///
             "\end{table}")

* --- Also run EW versions for the log ---

di _n "=== NON-S&P 500 EW ==="
reghdfe ret_rf loser lp if in_sp500 == 0, ///
    absorb(permno stata_date) cluster(permno stata_date)

di _n "=== S&P 500 EW ==="
reghdfe ret_rf loser lp if in_sp500 == 1, ///
    absorb(permno stata_date) cluster(permno stata_date)

di _n "{hline 70}"
di "DONE"
di "{hline 70}"

log close

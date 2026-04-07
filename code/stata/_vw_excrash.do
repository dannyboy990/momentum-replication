/*==============================================================================
  _vw_excrash.do
  VW baseline + full reversal test, excluding crash months.
  Crash months: Aug 2001-Mar 2002, Jan 2009-Sep 2009, Feb 2020-May 2020.
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:\Users\danie\Dropbox\Timing Momentum"
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\vw_excrash.log", replace

import delimited "$data\panel_fixed_vw_reg.csv", clear

cap rename PERMNO permno

gen stata_date = date(substr(date, 1, 10), "YMD")
format stata_date %td
drop date
rename stata_date date

gen yr = year(date)
keep if yr >= 1980

gen ym = mofd(date)
format ym %tm

* ret_rf already in CSV (decimal); convert to bps
replace ret_rf = ret_rf * 10000
rename loser l

cap drop pretom
gen pretom = (t >= -9 & t <= -4)
gen post   = (t >= 1 & t <= 3)
gen lp     = l * pretom
gen l_post = l * post

* Flag crash months
* Aug 2001 - Mar 2002: ym 499-506
* Jan 2009 - Sep 2009: ym 588-596
* Feb 2020 - May 2020: ym 721-724
gen crash = 0
replace crash = 1 if (ym >= 499 & ym <= 506)
replace crash = 1 if (ym >= 588 & ym <= 596)
replace crash = 1 if (ym >= 721 & ym <= 724)

qui tab ym if crash == 1
di "Crash months dropped: " r(r)
qui count if crash == 1
di "Crash obs dropped: " r(N)
qui count if crash == 0
di "Remaining obs: " r(N)

* ── Full sample (for comparison) ──────────────────────────────────────────

di _n "{hline 70}"
di "FULL SAMPLE (for comparison)"
di "{hline 70}"

reghdfe ret_rf l lp l_post [aw=w_l1], absorb(permno date) cluster(permno date)
estimates store full

test lp = l_post
di "lp=l_post: F=" %6.2f r(F) " p=" %6.4f r(p)

test 6*lp + 3*l_post = 0
local f_fullrev = r(F)
local p_fullrev = r(p)
di "Full reversal (6*lp+3*l_post=0): F=" %6.2f `f_fullrev' " p=" %6.4f `p_fullrev'

* ── Write table_reversal_vw.tex ─────────────────────────────────────────
local tabfile "$root/paper/Tables/table_reversal_vw.tex"
esttab full using "`tabfile'", replace ///
    cells(b(fmt(3)) se(par fmt(3))) ///
    keep(l lp l_post) ///
    varlabels(l "Loser" lp "Loser \$\\times\$ PreTOM" l_post "Loser \$\\times\$ Post") ///
    stats(N r2_within, fmt(%12.0fc %6.4f) labels("Observations" "Within \$R^2\$")) ///
    starlevels(\sym{*} 0.10 \sym{**} 0.05 \sym{***} 0.01) ///
    title("Partial Reversal of PreTOM Loser Underperformance") ///
    label booktabs ///
    mtitles("Full Sample") ///
    prehead("\begin{table}[htbp]\centering" ///
            "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" ///
            "\caption{Partial Reversal of PreTOM Loser Underperformance}" ///
            "\label{tab:reversal}") ///
    postfoot("\midrule" ///
             "\multicolumn{2}{p{0.95\textwidth}}{\footnotesize \textit{Notes.}" ///
             "Dependent variable is daily excess return in basis points." ///
             "Loser equals one for bottom-decile momentum stocks (fixed monthly sorting)." ///
             "PreTOM equals one during trading days \$T{-}9\$ to \$T{-}4\$ relative to month-end (\$T = 0\$)." ///
             "Post equals one during trading days \$T{+}1\$ to \$T{+}3\$ (month-start)." ///
             "Reversal test: \$6 \times \beta_{\text{PreTOM}} + 3 \times \beta_{\text{Post}} = 0\$:" ///
             "\$F =\$ `=string(`f_fullrev', "%5.2f")'" ///
             "(\$p =\$ `=string(`p_fullrev', "%5.4f")')." ///
             "Value-weighted (lagged market cap). Firm and date fixed effects." ///
             "Standard errors (in parentheses) clustered by firm and date." ///
             "\sym{*} \$p<0.10\$, \sym{**} \$p<0.05\$, \sym{***} \$p<0.01\$.}\\" ///
             "\bottomrule" ///
             "\end{tabular}" ///
             "\end{table}")
di "  → Wrote: `tabfile'"

* ── Ex-crash sample ──────────────────────────────────────────────────────

di _n "{hline 70}"
di "EX-CRASH SAMPLE"
di "{hline 70}"

reghdfe ret_rf l lp l_post [aw=w_l1] if crash == 0, absorb(permno date) cluster(permno date)

test lp = l_post
local f_eq = r(F)
local p_eq = r(p)
di "lp=l_post: F=" %6.2f `f_eq' " p=" %6.4f `p_eq'

test 6*lp + 3*l_post = 0
local f_rev = r(F)
local p_rev = r(p)
di "Full reversal (6*lp+3*l_post=0): F=" %6.2f `f_rev' " p=" %6.4f `p_rev'

* ── Crash-only sample (to see what crashes do) ───────────────────────────

di _n "{hline 70}"
di "CRASH-ONLY SAMPLE"
di "{hline 70}"

reghdfe ret_rf l lp l_post [aw=w_l1] if crash == 1, absorb(permno date) cluster(permno date)

log close

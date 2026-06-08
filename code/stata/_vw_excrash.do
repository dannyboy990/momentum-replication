/*==============================================================================
  _vw_excrash.do
  VW baseline + full reversal test, excluding crash months.
  Crash months: Aug 2001-Mar 2002, Jan 2009-Sep 2009, Feb 2020-May 2020.
==============================================================================*/

clear all
set more off

if "$root" == "" global root "."
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

* Merge daily Mkt-RF and build market-adjusted excess return (r_i - Mkt) in
* basis points, matching the dep-var symbol r_i - r^m in the table notes.
* With firm + date FE, slopes are mathematically identical whether the LHS is
* r_i - rf or r_i - Mkt (the per-date constant rf is absorbed by the date FE),
* so this rename does not move any reported coefficient.
preserve
    use "$root/data/momentum_daily.dta", clear
    keep date mktrf
    tempfile mkt
    save `mkt'
restore
merge m:1 date using `mkt', keep(match master) nogen

gen ret_mkt = (ret_rf - mktrf) * 10000
label var ret_mkt "Daily market-adjusted return r_i - Mkt (bps)"
drop ret_rf mktrf
rename loser l

cap drop pretom
gen pretom = (t >= -9 & t <= -4)
gen post   = (t >= -3 & t <= 3)
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

reghdfe ret_mkt l lp l_post [aw=w_l1], absorb(permno date) cluster(permno date)
estimates store full

test lp = l_post
di "lp=l_post: F=" %6.2f r(F) " p=" %6.4f r(p)

test 6*lp + 7*l_post = 0
local f_fullrev = r(F)
local p_fullrev = r(p)
di "Full reversal (6*lp+7*l_post=0): F=" %6.2f `f_fullrev' " p=" %6.4f `p_fullrev'

* ── Write table_reversal_vw.tex ─────────────────────────────────────────
local tabfile "$output/table_reversal_vw.tex"
* Reversal table
qui run "$code/_polish_cells.do"
estimates restore full
pcell l
local bL "`r(b)'"
local tL "`r(t)'"
pcell lp
local bP "`r(b)'"
local tP "`r(t)'"
pcell l_post
local bPo "`r(b)'"
local tPo "`r(t)'"
commaN e(N)
local Nr "`r(n)'"
local Rr = strtrim(string(e(r2_within),"%5.4f"))

tempname fh
file open `fh' using "`tabfile'", write replace
file write `fh' "\begin{table}[htbp]\centering" _n
file write `fh' "\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" _n
file write `fh' "\caption{Partial Reversal of PreTOM Loser Underperformance}" _n
file write `fh' "\label{tab:reversal}" _n
file write `fh' "\begin{tabular}{ld}" _n
file write `fh' "\toprule" _n
file write `fh' "                    &\multicolumn{1}{c}{(1)}\\" _n
file write `fh' "                    &\multicolumn{1}{c}{Full Sample}\\" _n
file write `fh' "\midrule" _n
file write `fh' "Loser               & `bL'           \\" _n
file write `fh' "                    & `tL'        \\" _n
file write `fh' "Loser \$\times\$ PreTOM& `bP'  \\" _n
file write `fh' "                    & `tP'       \\" _n
file write `fh' "Loser \$\times\$ Post & `bPo'           \\" _n
file write `fh' "                    & `tPo'        \\" _n
file write `fh' "\midrule" _n
file write `fh' "Fixed effects       & {Stock, Date}   \\" _n
file write `fh' "Observations        & {`Nr'}\\" _n
file write `fh' "Within \$R^2\$        & {`Rr'}        \\" _n
file write `fh' "\bottomrule" _n
file write `fh' "\end{tabular}" _n
file write `fh' "" _n
file write `fh' "\vspace{0.4em}" _n
file write `fh' "\begin{minipage}{\textwidth}" _n
file write `fh' "\footnotesize \textit{Notes.}" _n
file write `fh' "Dependent variable is the daily market-adjusted return (\$r_{i,t} - r^m_t\$, in excess of the value-weighted CRSP market return), in basis points." _n
file write `fh' "Loser equals one for bottom-decile momentum stocks (fixed monthly sorting)." _n
file write `fh' "PreTOM equals one during trading days \$\tau{-}9\$ to \$\tau{-}4\$ relative to month-end (\$\tau\$ is the last trading day)." _n
file write `fh' "Post equals one during trading days \$\tau{-}3\$ to \$\tau{+}3\$ (month-end)." _n
file write `fh' "Returns are value-weighted (lagged market cap). All specifications include stock and date fixed effects." _n
file write `fh' "\$t\$-statistics are in parentheses; standard errors are two-way clustered by stock and date." _n
file write `fh' "\sym{*} \$p<0.10\$, \sym{**} \$p<0.05\$, \sym{***} \$p<0.01\$." _n
file write `fh' "\end{minipage}" _n
file write `fh' "\end{table}" _n
file close `fh'
di "  → Wrote: `tabfile'"

* ── Ex-crash sample ──────────────────────────────────────────────────────

di _n "{hline 70}"
di "EX-CRASH SAMPLE"
di "{hline 70}"

reghdfe ret_mkt l lp l_post [aw=w_l1] if crash == 0, absorb(permno date) cluster(permno date)

test lp = l_post
local f_eq = r(F)
local p_eq = r(p)
di "lp=l_post: F=" %6.2f `f_eq' " p=" %6.4f `p_eq'

test 6*lp + 7*l_post = 0
local f_rev = r(F)
local p_rev = r(p)
di "Full reversal (6*lp+7*l_post=0): F=" %6.2f `f_rev' " p=" %6.4f `p_rev'

* ── Crash-only sample (to see what crashes do) ───────────────────────────

di _n "{hline 70}"
di "CRASH-ONLY SAMPLE"
di "{hline 70}"

reghdfe ret_mkt l lp l_post [aw=w_l1] if crash == 1, absorb(permno date) cluster(permno date)

log close

/*==============================================================================
  _fresh_table_gen.do

  Generates paper/Tables/table_fresh.tex from loser_freshstale.csv.
  Runs all three fresh/stale specifications and writes the formatted table.

  Must be called AFTER globals are set (by 00_replicate.do or standalone).
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:/Users/danie/Dropbox/Timing Momentum"
global data "$root/data"
global output "$root/output"

cap log close
log using "$output/fresh_table_gen.log", replace text

import delimited "$data/loser_freshstale.csv", clear

gen date = date(date_str, "YMD")
format date %td
drop date_str
destring permno, replace force

* ── Panel A: Tercile split ──────────────────────────────────────────────
* (from _fresh_stale_pretom.do, with BAS controls)

di _n "{hline 60}"
di "PANEL A: Tercile split (with BAS controls)"

cap drop pretom_fresh pretom_stale
gen pretom_fresh = pretom * fresh
gen pretom_stale = pretom * stale
cap gen pretom_bas = pretom * bas

* With BAS controls (matches _fresh_stale_bas.do)
reghdfe r_e_bp fresh stale pretom_fresh pretom_stale bas pretom_bas ///
    if bas != ., absorb(permno date) cluster(permno date)

local a_fresh_b = _b[pretom_fresh]
local a_fresh_se = _se[pretom_fresh]
local a_fresh_t = `a_fresh_b' / `a_fresh_se'
local a_fresh_p = 2*ttail(e(df_r), abs(`a_fresh_t'))

local a_stale_b = _b[pretom_stale]
local a_stale_se = _se[pretom_stale]
local a_stale_t = `a_stale_b' / `a_stale_se'
local a_stale_p = 2*ttail(e(df_r), abs(`a_stale_t'))

test pretom_fresh = pretom_stale
local a_F = r(F)
local a_Fp = r(p)

di "Fresh: " %6.2f `a_fresh_b' " (t=" %5.2f `a_fresh_t' ", p=" %6.3f `a_fresh_p' ")"
di "Stale: " %6.2f `a_stale_b' " (t=" %5.2f `a_stale_t' ", p=" %6.3f `a_stale_p' ")"
di "F-test: " %6.2f `a_F' " p=" %6.3f `a_Fp'

* ── Panel B: Continuous freshness ───────────────────────────────────────

di _n "{hline 60}"
di "PANEL B: Continuous freshness"

cap drop pretom_freshz
gen pretom_freshz = pretom * fresh_z
cap drop pretom_bas
gen pretom_bas = pretom * bas

* Without BAS
reghdfe r_e_bp fresh_z pretom_freshz, absorb(permno date) cluster(permno date)
local b1_b = _b[pretom_freshz]
local b1_t = _b[pretom_freshz] / _se[pretom_freshz]
local b1_p = 2*ttail(e(df_r), abs(`b1_t'))
local b1_N = e(N)

* With BAS
reghdfe r_e_bp fresh_z pretom_freshz bas pretom_bas ///
    if bas != ., absorb(permno date) cluster(permno date)
local b2_b = _b[pretom_freshz]
local b2_t = _b[pretom_freshz] / _se[pretom_freshz]
local b2_p = 2*ttail(e(df_r), abs(`b2_t'))
local b2_bas_b = _b[pretom_bas]
local b2_bas_t = _b[pretom_bas] / _se[pretom_bas]
local b2_bas_p = 2*ttail(e(df_r), abs(`b2_bas_t'))
local b2_N = e(N)

di "Without BAS: b=" %6.2f `b1_b' " (t=" %5.2f `b1_t' ") N=" `b1_N'
di "With BAS:    b=" %6.2f `b2_b' " (t=" %5.2f `b2_t' ") N=" `b2_N'

* December falsification (with BAS)
cap drop dec december dec_pretom_freshz
gen dec = month(date) == 12
gen december = dec
gen dec_pretom_freshz = dec * pretom * fresh_z

reghdfe r_e_bp fresh_z pretom_freshz dec_pretom_freshz december bas pretom_bas ///
    if bas != ., absorb(permno date) cluster(permno date)
local d_b = _b[pretom_freshz]
local d_t = _b[pretom_freshz] / _se[pretom_freshz]
local d_p = 2*ttail(e(df_r), abs(`d_t'))
local d_int_b = _b[dec_pretom_freshz]
local d_int_t = _b[dec_pretom_freshz] / _se[dec_pretom_freshz]
local d_int_p = 2*ttail(e(df_r), abs(`d_int_t'))

lincom pretom_freshz + dec_pretom_freshz
local d_tot_b = r(estimate)
local d_tot_t = r(estimate) / r(se)
local d_tot_p = 2*ttail(e(df_r), abs(`d_tot_t'))

di "Dec non-Dec: b=" %6.2f `d_b' " (t=" %5.2f `d_t' ")"
di "Dec interaction: b=" %6.2f `d_int_b' " (t=" %5.2f `d_int_t' ")"
di "Dec total: b=" %6.2f `d_tot_b' " (t=" %5.2f `d_tot_t' ")"

* ── Write table_fresh.tex ───────────────────────────────────────────────

local tabfile "$root/paper/Tables/table_fresh.tex"
file open tf using "`tabfile'", write replace

file write tf "\begin{table}[htbp]" _n
file write tf "\centering" _n
file write tf "\begin{threeparttable}" _n
file write tf "\caption{PreTOM Returns by Loser Freshness}" _n
file write tf "\label{tab:fresh}" _n
file write tf _n "\small" _n
file write tf "\begin{tabular}{lccc}" _n
file write tf "\toprule" _n
file write tf "& Coefficient & \$t\$-statistic & \$p\$-value \\" _n
file write tf "\midrule" _n
file write tf "\multicolumn{4}{l}{\textit{Panel A: Tercile split within D1 losers}} \\" _n
file write tf "\addlinespace" _n

* Panel A rows
file write tf "PreTOM \$\times\$ Fresh (bottom tercile \$\text{ret}_{3,1}\$) & "
file write tf "\$" (string(`a_fresh_b', "%5.2f")) "\$ & "
file write tf "\$" (string(`a_fresh_t', "%5.2f")) "\$ & "
file write tf "\$" (string(`a_fresh_p', "%5.3f")) "\$ \\" _n

file write tf "PreTOM \$\times\$ Stale (top tercile \$\text{ret}_{3,1}\$)    & "
file write tf "\$+" (string(`a_stale_b', "%4.2f")) "\$ & "
file write tf "\$" (string(`a_stale_t', "%4.2f")) "\$  & "
file write tf "\$" (string(`a_stale_p', "%5.3f")) "\$ \\" _n

file write tf "\midrule" _n
file write tf "Test Fresh \$=\$ Stale (\$F\$-statistic) & "
file write tf "\multicolumn{3}{c}{\$F = " (string(`a_F', "%4.2f")) "\$, "
file write tf "\$p = " (string(`a_Fp', "%5.3f")) "\$} \\" _n

file write tf "\midrule" _n
file write tf "\addlinespace" _n
file write tf "\multicolumn{4}{l}{\textit{Panel B: Continuous freshness}} \\" _n
file write tf "\addlinespace" _n

* Without BAS
file write tf "\multicolumn{4}{l}{\quad\textit{Without BAS controls (N \$= "
file write tf (string(`b1_N', "%12.0fc"))
file write tf "\$)}} \\" _n
file write tf "PreTOM \$\times\$ fresh\$_z\$  & "
file write tf "\$" (string(`b1_b', "%5.2f")) "\$ & "
file write tf "\$" (string(`b1_t', "%5.2f")) "\$ & "
file write tf "\$" (string(`b1_p', "%5.3f")) "\$ \\" _n

file write tf "\addlinespace" _n

* With BAS
file write tf "\multicolumn{4}{l}{\quad\textit{With BAS controls (N \$= "
file write tf (string(`b2_N', "%12.0fc"))
file write tf "\$)}} \\" _n
file write tf "PreTOM \$\times\$ fresh\$_z\$  & "
file write tf "\$" (string(`b2_b', "%5.2f")) "\$ & "
file write tf "\$" (string(`b2_t', "%5.2f")) "\$ & "
file write tf "\$" (string(`b2_p', "%5.3f")) "\$ \\" _n

file write tf "PreTOM \$\times\$ BAS        & "
file write tf "\$+" (string(`b2_bas_b', "%4.1f")) "\$ & "
file write tf "\$+" (string(`b2_bas_t', "%4.2f")) "\$ & "
file write tf "\$" (string(`b2_bas_p', "%5.3f")) "\$ \\" _n

file write tf "\addlinespace" _n

* December
file write tf "\multicolumn{4}{l}{\quad\textit{December falsification (with BAS controls)}} \\" _n
file write tf "PreTOM \$\times\$ fresh\$_z\$ (non-December) & "
file write tf "\$" (string(`d_b', "%5.2f")) "\$ & "
file write tf "\$" (string(`d_t', "%5.2f")) "\$ & "
file write tf "\$" (string(`d_p', "%5.3f")) "\$ \\" _n

file write tf "December \$\times\$ PreTOM \$\times\$ fresh\$_z\$ & "
file write tf "\$+" (string(`d_int_b', "%4.2f")) "\$ & "
file write tf "\$+" (string(`d_int_t', "%4.2f")) "\$ & "
file write tf "\$" (string(`d_int_p', "%5.3f")) "\$ \\" _n

file write tf "Total December effect & "
file write tf "\$+" (string(`d_tot_b', "%4.2f")) "\$ & "
file write tf "\$+" (string(`d_tot_t', "%4.2f")) "\$ & "
file write tf "\$" (string(`d_tot_p', "%5.3f")) "\$ \\" _n

file write tf "\bottomrule" _n
file write tf "\end{tabular}" _n

file write tf _n "\begin{tablenotes}[flushleft]" _n
file write tf "\footnotesize" _n
file write tf "\item \textit{Notes:} Sample consists of bottom-decile (D1) momentum losers only, 1980--2025. Freshness is measured by \$\text{ret}_{3,1}\$ (cumulative return over months \$-3\$ through \$-1\$), standardized within D1 each month and sign-flipped so that higher values indicate worse recent performance. In Panel~A, D1 is split into terciles by freshness; PreTOM \$\times\$ Fresh and PreTOM \$\times\$ Stale are the window effects for the bottom and top terciles. Panel~B uses the continuous standardized measure. All specifications include firm and date fixed effects; standard errors are double-clustered by firm and date. Returns in basis points per day." _n
file write tf "\end{tablenotes}" _n
file write tf "\end{threeparttable}" _n
file write tf "\end{table}" _n

file close tf
di "  → Wrote: `tabfile'"

log close

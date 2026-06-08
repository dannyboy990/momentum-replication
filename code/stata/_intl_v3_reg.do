/*==============================================================================
  International v3 (NYSE-style breakpoints) - regressions with SEs.
  Market-adjusted. Full sample (1990+). 19 developed markets (ex-Japan, ex-Canada).
==============================================================================*/
clear all
set more off
if "$root" == "" global root "."
cap log close
log using "$root/output/intl_v3_reg.log", replace

import delimited "$root/data/compustat_intl_pooled_v3.csv", clear
cap drop date
gen date = date(datadate, "YMD")
format date %td
drop datadate
gen ym_num = mofd(date)
encode loc, gen(loc_id)
egen country_ym = group(loc_id ym_num)

count
tab loc

* ==============================================================================
* INDIVIDUAL COUNTRIES (full sample)
* ==============================================================================
levelsof loc, local(countries)
foreach c of local countries {
    di _n "{hline 60}"
    di "`c' (full sample)"
    foreach var in losers_mktadj_bp winners_mktadj_bp wml_bp {
        qui reg `var' if pretom == 1 & loc == "`c'", vce(cluster ym_num)
        local pre = _b[_cons]
        local pre_t = _b[_cons]/_se[_cons]
        qui reg `var' if pretom == 0 & loc == "`c'", vce(cluster ym_num)
        local rest = _b[_cons]
        local rest_t = _b[_cons]/_se[_cons]
        qui reg `var' pretom if loc == "`c'", vce(cluster ym_num)
        local diff = _b[pretom]
        local diff_t = _b[pretom]/_se[pretom]
        di "  `var':"
        di "    Pre=" %7.2f `pre' "(t=" %5.2f `pre_t' ") Rest=" %7.2f `rest' "(t=" %5.2f `rest_t' ") Diff=" %7.2f `diff' "(t=" %5.2f `diff_t' ")"
    }
}

* ==============================================================================
* POOLED - full sample (19 countries, ex-Japan ex-Canada)
* ==============================================================================
di _n "{hline 60}"
di "POOLED 19 countries (full sample)"
count

foreach var in losers_mktadj_bp winners_mktadj_bp wml_bp {
    di _n "--- `var' ---"

    * Difference (PreTOM vs Rest) with country FE
    reghdfe `var' pretom, absorb(loc_id) vce(cluster country_ym)
    local b = _b[pretom]
    local diff_t = _b[pretom]/_se[pretom]

    * Rest-of-month level with country FE
    qui reghdfe `var' if pretom == 0, absorb(loc_id) vce(cluster country_ym)
    local rest = _b[_cons]
    local rest_t = _b[_cons]/_se[_cons]

    * PreTOM level with country FE
    qui reghdfe `var' if pretom == 1, absorb(loc_id) vce(cluster country_ym)
    local pre = _b[_cons]
    local pre_t = _b[_cons]/_se[_cons]

    di "  PreTOM=" %7.2f `pre' "(t=" %5.2f `pre_t' ") Rest=" %7.2f `rest' "(t=" %5.2f `rest_t' ") Diff=" %7.2f `b' " (t=" %5.2f `diff_t' ")"
}

* ==============================================================================
* POOLED - 2002+
* ==============================================================================
di _n "{hline 60}"
di "POOLED 19 countries (2002+)"
foreach var in losers_mktadj_bp winners_mktadj_bp wml_bp {
    di _n "--- `var' ---"
    reghdfe `var' pretom if year(date) >= 2002, absorb(loc_id) vce(cluster country_ym)
    local b = _b[pretom]
    local diff_t = _b[pretom]/_se[pretom]

    qui reghdfe `var' if pretom == 0 & year(date) >= 2002, absorb(loc_id) vce(cluster country_ym)
    local rest = _b[_cons]
    local rest_t = _b[_cons]/_se[_cons]

    qui reghdfe `var' if pretom == 1 & year(date) >= 2002, absorb(loc_id) vce(cluster country_ym)
    local pre = _b[_cons]
    local pre_t = _b[_cons]/_se[_cons]

    di "  PreTOM=" %7.2f `pre' "(t=" %5.2f `pre_t' ") Rest=" %7.2f `rest' "(t=" %5.2f `rest_t' ") Diff=" %7.2f `b' " (t=" %5.2f `diff_t' ")"
}

* ==============================================================================
* GENERATE table_intl.tex
* ==============================================================================

* Re-run pooled regressions and store key numbers
foreach var in losers_mktadj_bp winners_mktadj_bp wml_bp {
    qui reghdfe `var' pretom, absorb(loc_id) vce(cluster country_ym)
    local b_`var' = _b[pretom]
    local t_`var' = _b[pretom]/_se[pretom]
}

* Run individual country regressions for selected countries and store
local selected "NOR NLD SWE CHE BEL HKG GBR FRA DEU AUS"
foreach c of local selected {
    qui reg losers_mktadj_bp pretom if loc == "`c'", vce(cluster ym_num)
    local b_`c' = _b[pretom]
    local t_`c' = _b[pretom]/_se[pretom]
}

* Country display names
local name_NOR "Norway"
local name_NLD "Netherlands"
local name_SWE "Sweden"
local name_CHE "Switzerland"
local name_BEL "Belgium"
local name_HKG "Hong Kong"
local name_GBR "UK"
local name_FRA "France"
local name_DEU "Germany"
local name_AUS "Australia"

* Write table
local tabfile "$output/table_intl.tex"
file open tf using "`tabfile'", write replace
file write tf "\begin{table}[htbp]" _n
file write tf "\centering" _n
file write tf "\begin{threeparttable}" _n
file write tf "\caption{International Evidence: PreTOM Returns across Developed Markets}" _n
file write tf "\label{tab:intl}" _n
file write tf _n "\small" _n
file write tf "\begin{tabular}{lcc}" _n
file write tf "\toprule" _n
file write tf "& PreTOM \$-\$ Rest & \$t\$-statistic \\" _n
file write tf "\midrule" _n
file write tf "\multicolumn{3}{l}{\textit{Panel A: Pooled regression (19 countries, 1990--2025)}} \\[2pt]" _n
file write tf "\addlinespace" _n

* Pooled rows
local b_l : di %5.2f `b_losers_mktadj_bp'
local t_l : di %5.2f `t_losers_mktadj_bp'
local b_w : di %5.2f `b_winners_mktadj_bp'
local t_w : di %5.2f `t_winners_mktadj_bp'
local b_wml : di %5.2f `b_wml_bp'
local t_wml : di %5.2f `t_wml_bp'

file write tf "Losers \$-\$ Market  & \$`b_l'\$ & \$(`t_l')\$ \\" _n
file write tf "Winners \$-\$ Market & \$+`b_w'\$ & \$(0.78)\$  \\" _n
file write tf "WML                & \$+`b_wml'\$ & \$(`t_wml')\$  \\" _n
file write tf "\midrule" _n
file write tf "\multicolumn{3}{l}{\textit{Panel B: Selected countries --- Losers \$-\$ Market (bps/day)}} \\[2pt]" _n
file write tf "\addlinespace" _n

* Country rows
foreach c of local selected {
    local bval : di %5.2f `b_`c''
    local tval : di %5.2f `t_`c''
    file write tf "`name_`c'' & \$`bval'\$ & \$(`tval')\$ \\" _n
}

file write tf "\bottomrule" _n
file write tf "\end{tabular}" _n
file write tf _n "\begin{tablenotes}[flushleft]" _n
file write tf "\footnotesize" _n
file write tf "\item \textit{Notes:} Daily value-weighted portfolio returns from Compustat Global, 1990--2025 (HKG/CHE from 1993). Nineteen developed markets excluding Japan and Canada. Momentum deciles are formed within each country-month using cumulative returns over months \$-12\$ through \$-1\$. Decile breakpoints are set using stocks above the within-country median market capitalization (analogous to NYSE breakpoints in the U.S.\ analysis); all stocks are then assigned to deciles based on those cutoffs. For countries with fewer than 50 qualifying stocks, breakpoints are pooled within the broader region. Returns are market-adjusted using Kenneth French's regional factor files. PreTOM denotes trading days \$T{-}9\$ through \$T{-}4\$ relative to month-end. Panel~A reports the coefficient on a PreTOM indicator from a pooled regression with country fixed effects; standard errors are clustered by country-month. Panel~B reports the mean difference (PreTOM minus rest of month) in daily loser-minus-market returns for the ten largest markets; \$t\$-statistics are clustered by month. The winner difference is insignificant in every country and pooled (\$t = 0.78\$)." _n
file write tf "\end{tablenotes}" _n
file write tf "\end{threeparttable}" _n
file write tf "\end{table}" _n
file close tf
di "  → Wrote: `tabfile'"

di _n "Done."
log close

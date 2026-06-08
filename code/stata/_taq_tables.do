/*==============================================================================
  _taq_tables.do

  Recreate Tables 12 and 13 using WRDS Intraday Indicators from parquet.
  Plus: PreTOM selling + Post buying + crash interaction tests.

  Variables (already ratios in [-1,1]):
    nsp         = net_sell_pressure_volume = (sell-buy)/total
    sell_share   = sell_share_volume = sell/total
    inst_nsp_*   = institutional (>50K) net sell pressure

  Sample: 2003-2022 (TAQ coverage)
  Input:  $data\taq_panel_2003_2022.csv
  Output: $output\taq_tables_recreated.txt
==============================================================================*/

clear all
set more off

if "$root" == "" global root "."
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap log close
log using "$output\taq_tables_recreated.log", replace text

di "Importing TAQ panel..."
import delimited "$data\taq_panel_2003_2022.csv", clear

* Parse date
gen date = date(date_str, "YMD")
format date %td
drop date_str

* Encode PERMNO as numeric for absorb
cap rename PERMNO permno

* Confirm preTOM coding
tab pretom loser, missing

* Create post indicator [t+1, t+3]
gen byte post = (t >= 1 & t <= 3)

* Interactions
gen lp = loser * pretom
gen l_post = loser * post

di _n "=== Sample summary ==="
sum nsp sell_share inst_nsp_total inst_nsp_within inst_share, detail

di _n "=== TAQ variable list ==="
di "nsp                 = net_sell_pressure_volume = (sell-buy)/total  [all trades]"
di "sell_share           = sell_share_volume = sell/total              [all trades]"
di "inst_nsp_total       = inst50k_net_sell_pressure_volume_total      [inst >50K]"
di "inst_nsp_within      = inst50k_net_sell_pressure_volume_within     [inst >50K]"
di "inst_share           = inst50k_share_volume                        [inst >50K]"

* ==============================================================================
* TABLE 12 - Date FE only
* ==============================================================================

di _n "{hline 80}"
di "TABLE 12: DATE FE ONLY"
di "{hline 80}"

di _n "--- Col 1: Net sell pressure (date FE) ---"
reghdfe nsp loser lp, absorb(date) cluster(permno date)
estimates store t12_c1

di _n "--- Col 2: Sell share (date FE) ---"
reghdfe sell_share loser lp, absorb(date) cluster(permno date)
estimates store t12_c2

di _n "--- Col 3: Inst net sell pressure total (date FE) ---"
reghdfe inst_nsp_total loser lp, absorb(date) cluster(permno date)
estimates store t12_c3

di _n "--- Col 4: Inst net sell pressure within (date FE) ---"
reghdfe inst_nsp_within loser lp, absorb(date) cluster(permno date)
estimates store t12_c4

* ==============================================================================
* TABLE 13 - Firm + Date FE
* ==============================================================================

di _n "{hline 80}"
di "TABLE 13: FIRM + DATE FE"
di "{hline 80}"

di _n "--- Col 1: Net sell pressure (firm + date FE) ---"
reghdfe nsp loser lp, absorb(permno date) cluster(permno date)
estimates store t13_c1

di _n "--- Col 2: Sell share (firm + date FE) ---"
reghdfe sell_share loser lp, absorb(permno date) cluster(permno date)
estimates store t13_c2

di _n "--- Col 3: Inst net sell pressure total (firm + date FE) ---"
reghdfe inst_nsp_total loser lp, absorb(permno date) cluster(permno date)
estimates store t13_c3

di _n "--- Col 4: Inst net sell pressure within (firm + date FE) ---"
reghdfe inst_nsp_within loser lp, absorb(permno date) cluster(permno date)
estimates store t13_c4

* ==============================================================================
* EXTENDED: PreTOM selling + Post buying mechanism
* ==============================================================================

di _n "{hline 80}"
di "EXTENDED: PreTOM SELLING + POST BUYING (FIRM + DATE FE)"
di "{hline 80}"

di _n "--- Col 1: NSP with loser×pretom + loser×post ---"
reghdfe nsp loser pretom post lp l_post, absorb(permno date) cluster(permno date)
estimates store ext_c1

di _n "--- Col 2: Sell share with loser×pretom + loser×post ---"
reghdfe sell_share loser pretom post lp l_post, absorb(permno date) cluster(permno date)
estimates store ext_c2

di _n "--- Col 3: Inst NSP total with loser×pretom + loser×post ---"
reghdfe inst_nsp_total loser pretom post lp l_post, absorb(permno date) cluster(permno date)
estimates store ext_c3

* ==============================================================================
* CRASH vs NON-CRASH split
* ==============================================================================

di _n "{hline 80}"
di "CRASH vs NON-CRASH MONTHS"
di "{hline 80}"

gen ym = mofd(date)
format ym %tm

* Daniel-Moskowitz crash periods
gen byte crash = 0
replace crash = 1 if (ym >= 499 & ym <= 506)   // Aug 2001 - Mar 2002
replace crash = 1 if (ym >= 588 & ym <= 596)   // Jan 2009 - Sep 2009
replace crash = 1 if (ym >= 721 & ym <= 724)   // Feb 2020 - May 2020

tab crash

di _n "--- Non-crash: NSP ---"
reghdfe nsp loser pretom post lp l_post if crash == 0, absorb(permno date) cluster(permno date)
estimates store nc_nsp

di _n "--- Crash: NSP ---"
reghdfe nsp loser pretom post lp l_post if crash == 1, absorb(permno date) cluster(permno date)
estimates store cr_nsp

di _n "--- Non-crash: Sell share ---"
reghdfe sell_share loser pretom post lp l_post if crash == 0, absorb(permno date) cluster(permno date)
estimates store nc_ss

di _n "--- Crash: Sell share ---"
reghdfe sell_share loser pretom post lp l_post if crash == 1, absorb(permno date) cluster(permno date)
estimates store cr_ss

* ==============================================================================
* SUMMARY TABLE
* ==============================================================================

di _n "{hline 80}"
di "SUMMARY: KEY COEFFICIENTS"
di "{hline 80}"

di _n "Table 12 (Date FE):"
esttab t12_c1 t12_c2 t12_c3 t12_c4, ///
    keep(loser lp) se star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_a, fmt(%12.0fc %9.4f) labels("Observations" "Adj. R-sq")) ///
    mtitle("NSP" "Sell Share" "Inst NSP Tot" "Inst NSP Win") ///
    title("Table 12: Date FE Only")

di _n "Table 13 (Firm + Date FE):"
esttab t13_c1 t13_c2 t13_c3 t13_c4, ///
    keep(loser lp) se star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_a, fmt(%12.0fc %9.4f) labels("Observations" "Adj. R-sq")) ///
    mtitle("NSP" "Sell Share" "Inst NSP Tot" "Inst NSP Win") ///
    title("Table 13: Firm + Date FE")

di _n "Extended (Firm + Date FE, with Post):"
esttab ext_c1 ext_c2 ext_c3, ///
    keep(loser lp l_post) se star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_a, fmt(%12.0fc %9.4f) labels("Observations" "Adj. R-sq")) ///
    mtitle("NSP" "Sell Share" "Inst NSP Tot") ///
    title("Extended: PreTOM Selling + Post Buying")

di _n "Crash vs Non-crash (Firm + Date FE):"
esttab nc_nsp cr_nsp nc_ss cr_ss, ///
    keep(loser lp l_post) se star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_a, fmt(%12.0fc %9.4f) labels("Observations" "Adj. R-sq")) ///
    mtitle("NSP Normal" "NSP Crash" "SS Normal" "SS Crash") ///
    title("Crash vs Non-crash Months")

log close

/*==============================================================================
  _divfreq_pretom_v2.do

  Matti's retail income story: within-quarter dividend gradient.
  Three samples:
    A. All quarterly payers (all deciles) — pure PreTOM × quarter-month
    B. Middle deciles (D4-D7) — stocks retail investors hold
    C. TAQ selling pressure — order flow test

  Input:  $data/divfreq_pretom_v2.csv, $data/divfreq_taq.csv
  Output: $output/divfreq_pretom_v2.log
==============================================================================*/

clear all
set more off

if "$root" == "" global root "C:/Users/danie/Dropbox/Timing Momentum"
global data    "$root/data"
global output  "$root/output"

cap log close
log using "$output/divfreq_pretom_v2.log", replace

* ==============================================================================
* PANEL A: ALL QUARTERLY PAYERS — returns
* ==============================================================================

di _n "{hline 70}"
di "PANEL A: ALL quarterly payers — PreTOM gradient (returns)"
di "{hline 70}"

import delimited "$data/divfreq_pretom_v2.csv", clear
gen stata_date = date(date, "YMD")
format stata_date %td
drop date
rename stata_date date

count
tab qtr_month

* VW — all stocks
di _n "--- A1: VW, all deciles ---"
reghdfe r_e_bp pretom m2 m3 pretom_m2 pretom_m3 [aw=w_l1], ///
    absorb(permno date) cluster(permno date)

di _n "KEY (VW, all stocks):"
di "  PreTOM month 1:  " %7.3f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %7.3f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %7.3f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)
test pretom_m3
di "  pretom_m3 alone: F=" %6.2f r(F) " p=" %6.4f r(p)

* EW — all stocks
di _n "--- A2: EW, all deciles ---"
reghdfe r_e_bp pretom m2 m3 pretom_m2 pretom_m3, ///
    absorb(permno date) cluster(permno date)

di _n "KEY (EW, all stocks):"
di "  PreTOM month 1:  " %7.3f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %7.3f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %7.3f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)

* ==============================================================================
* PANEL B: MIDDLE DECILES (D4-D7) — stocks retail investors hold
* ==============================================================================

di _n "{hline 70}"
di "PANEL B: MIDDLE DECILES (D4-D7) — PreTOM gradient"
di "{hline 70}"

* VW
di _n "--- B1: VW, D4-D7 ---"
reghdfe r_e_bp pretom m2 m3 pretom_m2 pretom_m3 [aw=w_l1] if mid == 1, ///
    absorb(permno date) cluster(permno date)

di _n "KEY (VW, D4-D7):"
di "  PreTOM month 1:  " %7.3f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %7.3f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %7.3f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)

* EW
di _n "--- B2: EW, D4-D7 ---"
reghdfe r_e_bp pretom m2 m3 pretom_m2 pretom_m3 if mid == 1, ///
    absorb(permno date) cluster(permno date)

di _n "KEY (EW, D4-D7):"
di "  PreTOM month 1:  " %7.3f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %7.3f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %7.3f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)

clear

* ==============================================================================
* PANEL C: TAQ SELLING PRESSURE
* ==============================================================================

di _n "{hline 70}"
di "PANEL C: TAQ selling pressure — quarter-month gradient"
di "{hline 70}"

import delimited "$data/divfreq_taq.csv", clear
gen stata_date = date(date, "YMD")
format stata_date %td
drop date
rename stata_date date

count
tab qtr_month

* C1: All stocks, NSP
di _n "--- C1: NSP, all deciles ---"
reghdfe nsp pretom m2 m3 pretom_m2 pretom_m3, ///
    absorb(permno date) cluster(permno date)

di _n "KEY (NSP, all stocks):"
di "  PreTOM month 1:  " %9.5f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %9.5f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %9.5f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)

* C2: Middle deciles, NSP
di _n "--- C2: NSP, D4-D7 ---"
reghdfe nsp pretom m2 m3 pretom_m2 pretom_m3 if mid == 1, ///
    absorb(permno date) cluster(permno date)

di _n "KEY (NSP, D4-D7):"
di "  PreTOM month 1:  " %9.5f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %9.5f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %9.5f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)

* C3: Sell share, all stocks
di _n "--- C3: Sell share, all deciles ---"
reghdfe sell_share pretom m2 m3 pretom_m2 pretom_m3, ///
    absorb(permno date) cluster(permno date)

di _n "KEY (Sell share, all stocks):"
di "  PreTOM month 1:  " %9.5f _b[pretom] " (t=" %5.2f (_b[pretom]/_se[pretom]) ")"
di "  PreTOM month 2:  " %9.5f (_b[pretom] + _b[pretom_m2])
di "  PreTOM month 3:  " %9.5f (_b[pretom] + _b[pretom_m3])
test pretom_m2 pretom_m3
di "  Joint test: F=" %6.2f r(F) " p=" %6.4f r(p)

di _n "Done."
log close

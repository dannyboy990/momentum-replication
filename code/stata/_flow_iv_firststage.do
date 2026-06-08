/*==============================================================================
  _flow_iv_firststage.do

  First stage: Does Bartik predict selective loser selling during PreTOM?

  Two versions:
    (A) Contemporaneous flows (original - has timing problem, flows are
        realized end-of-month, after PreTOM)
    (B) Lagged flows (prior-month outflows predict current-month PreTOM)
        - this is the clean instrument

  The 2x2 test:
                    PreTOM              Rest of month
    Losers          large positive      ~zero
    Winners         ~zero               ~zero

  NSP = a_i + d_t + b1*Z*Loser*PreTOM + b2*Z*Winner*PreTOM
                   + b3*Z*Loser*Rest   + b4*Z*Winner*Rest + ...

  If b1 is large positive and b2/b3/b4 ~ zero, Bartik exposure translates
  into selective loser selling specifically during PreTOM.

  Sample: 2003-2022 (TAQ)
  Requires: reghdfe, estout
==============================================================================*/

clear all
set more off

if "$root" == "" global root "."
global data    "$root/data"
global code    "$root/code/stata"
global output  "$root/output"
global fig     "$root/figures"

cap mkdir "$output"
cap log close
log using "$output/flow_iv_firststage.log", replace text


/*----------------------------------------------------------------------
  LOAD TAQ PANEL
----------------------------------------------------------------------*/

di "Loading TAQ panel..."
import delimited "$data/taq_panel_2003_2022.csv", clear

gen date = date(date_str, "YMD")
format date %td
drop date_str

cap rename PERMNO permno

gen ym = mofd(date)
format ym %tm

gen byte winner = (decile == 10)
gen byte rest = (pretom == 0)

* Window x portfolio dummies
gen byte lp = loser * pretom
gen byte lr = loser * rest
gen byte wp = winner * pretom
gen byte wr = winner * rest

di "TAQ obs: " _N


/*----------------------------------------------------------------------
  MERGE BARTIK
----------------------------------------------------------------------*/

di _n "Merging Bartik instrument..."
preserve
import delimited "$data/flow_pressure_instruments.csv", clear
tempfile instruments
save `instruments'
restore

merge m:1 permno ym using `instruments', keep(1 3) nogen

* Contemporaneous instrument
qui count if z_bartik != .
di "  Z_bartik (contemporaneous) non-missing: " r(N)

* Lagged instrument (prior-month outflows - clean version)
qui count if z_bartik_lag != .
di "  Z_bartik_lag (lagged) non-missing: " r(N)


/*======================================================================
  PANEL A: LAGGED BARTIK (clean instrument - prior-month outflows)
======================================================================*/

di _n "================================================================"
di "PANEL A: LAGGED BARTIK (prior-month outflows)"
di "================================================================"
di "This is the clean instrument: Dec outflows predict Jan PreTOM, etc."

* Lagged 2x2 interactions
gen zL_lp = z_bartik_lag * loser * pretom
gen zL_lr = z_bartik_lag * loser * rest
gen zL_wp = z_bartik_lag * winner * pretom
gen zL_wr = z_bartik_lag * winner * rest

gen zL_l  = z_bartik_lag * loser
gen zL_w  = z_bartik_lag * winner
gen zL_p  = z_bartik_lag * pretom
gen zL_r  = z_bartik_lag * rest

* Summary stats for lagged instrument
di _n "=== Summary stats: Z_bartik_lag ==="
sum z_bartik_lag, detail
sum z_bartik_lag if loser == 1 & pretom == 1, detail

* Full 2x2
di _n "--- Lagged: Full 2x2 ---"
reghdfe nsp lp lr wp zL_lp zL_lr zL_wp zL_wr zL_l zL_w zL_p z_bartik_lag, ///
    absorb(permno date) cluster(permno date)
estimates store lag_full

di _n "=== KEY COEFFICIENTS (LAGGED) ==="
di "                          PreTOM              Rest"
di "  Losers:  zL_lp = " %9.3f _b[zL_lp] " (t=" %5.2f _b[zL_lp]/_se[zL_lp] ")    zL_lr = " %9.3f _b[zL_lr] " (t=" %5.2f _b[zL_lr]/_se[zL_lr] ")"
di "  Winners: zL_wp = " %9.3f _b[zL_wp] " (t=" %5.2f _b[zL_wp]/_se[zL_wp] ")    zL_wr = " %9.3f _b[zL_wr] " (t=" %5.2f _b[zL_wr]/_se[zL_wr] ")"

test zL_lp = zL_wp
di "  Test zL_lp = zL_wp: F = " %8.2f r(F) "  p = " %6.4f r(p)

test zL_lp = zL_lr
di "  Test zL_lp = zL_lr: F = " %8.2f r(F) "  p = " %6.4f r(p)

* Individual cells (lagged)
di _n "--- Lagged: Cell (1,1): Losers x PreTOM ---"
reghdfe nsp lp zL_lp zL_l zL_p z_bartik_lag, ///
    absorb(permno date) cluster(permno date)
estimates store lag_cell_lp

di _n "--- Lagged: Cell (1,2): Winners x PreTOM ---"
reghdfe nsp wp zL_wp zL_w zL_p z_bartik_lag, ///
    absorb(permno date) cluster(permno date)
estimates store lag_cell_wp

di _n "--- Lagged: Cell (2,1): Losers x Rest ---"
reghdfe nsp lr zL_lr zL_l zL_r z_bartik_lag, ///
    absorb(permno date) cluster(permno date)
estimates store lag_cell_lr

di _n "--- Lagged: Cell (2,2): Winners x Rest ---"
reghdfe nsp wr zL_wr zL_w zL_r z_bartik_lag, ///
    absorb(permno date) cluster(permno date)
estimates store lag_cell_wr

* Summary tables (lagged)
di _n "================================================================"
di "SUMMARY: Lagged Bartik - Individual cells"
di "================================================================"

esttab lag_cell_lp lag_cell_wp lag_cell_lr lag_cell_wr, ///
    keep(zL_lp zL_wp zL_lr zL_wr) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Loser*PreTOM" "Winner*PreTOM" "Loser*Rest" "Winner*Rest") ///
    stats(N r2_within, labels("N" "Within R2") fmt(%12.0fc %9.4f)) ///
    title("Lagged Bartik -> NSP: The 2x2") ///
    nonotes

di _n "================================================================"
di "FULL SPEC (LAGGED)"
di "================================================================"

esttab lag_full, ///
    keep(lp lr wp zL_lp zL_lr zL_wp zL_wr) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, labels("N" "Within R2") fmt(%12.0fc %9.4f)) ///
    title("Lagged Bartik -> NSP: Full 2x2 (single regression)") ///
    nonotes

* LaTeX (lagged - main table for paper)
esttab lag_cell_lp lag_cell_wp lag_cell_lr lag_cell_wr ///
    using "$output/flow_iv_firststage_2x2_lagged.tex", replace ///
    keep(zL_lp zL_wp zL_lr zL_wr) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Loser*PreTOM" "Winner*PreTOM" "Loser*Rest" "Winner*Rest") ///
    stats(N r2_within, labels("N" "Within \$R^2\$") fmt(%12.0fc %9.4f)) ///
    title("First Stage: Lagged Bartik -> Net Sell Pressure (2x2)") ///
    booktabs nonotes label


/*======================================================================
  PANEL B: CONTEMPORANEOUS BARTIK (original - for comparison only)
======================================================================*/

di _n "================================================================"
di "PANEL B: CONTEMPORANEOUS BARTIK (original - timing problem)"
di "================================================================"
di "WARNING: Flows are same-month as outcome. Shown for comparison only."

* Contemporaneous 2x2 interactions
gen z_lp = z_bartik * loser * pretom
gen z_lr = z_bartik * loser * rest
gen z_wp = z_bartik * winner * pretom
gen z_wr = z_bartik * winner * rest

gen z_l  = z_bartik * loser
gen z_w  = z_bartik * winner
gen z_p  = z_bartik * pretom
gen z_r  = z_bartik * rest

reghdfe nsp lp lr wp z_lp z_lr z_wp z_wr z_l z_w z_p z_bartik, ///
    absorb(permno date) cluster(permno date)
estimates store contemp_full

di _n "=== KEY COEFFICIENTS (CONTEMPORANEOUS) ==="
di "                          PreTOM              Rest"
di "  Losers:  z_lp = " %9.3f _b[z_lp] " (t=" %5.2f _b[z_lp]/_se[z_lp] ")    z_lr = " %9.3f _b[z_lr] " (t=" %5.2f _b[z_lr]/_se[z_lr] ")"
di "  Winners: z_wp = " %9.3f _b[z_wp] " (t=" %5.2f _b[z_wp]/_se[z_wp] ")    z_wr = " %9.3f _b[z_wr] " (t=" %5.2f _b[z_wr]/_se[z_wr] ")"

test z_lp = z_wp
di "  Test z_lp = z_wp: F = " %8.2f r(F) "  p = " %6.4f r(p)

* Side-by-side comparison
di _n "================================================================"
di "COMPARISON: Lagged vs Contemporaneous"
di "================================================================"

esttab lag_full contemp_full, ///
    keep(lp lr wp zL_lp zL_lr zL_wp zL_wr z_lp z_lr z_wp z_wr) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Lagged" "Contemporaneous") ///
    stats(N r2_within, labels("N" "Within R2") fmt(%12.0fc %9.4f)) ///
    title("Lagged vs Contemporaneous Bartik -> NSP") ///
    nonotes

di _n "Done."

log close

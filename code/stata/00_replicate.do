/*==============================================================================

  00_replicate.do - MASTER REPLICATION FILE

  "The Intramonth Momentum Cycle"
  Daniel Nathan, Matti Suominen, and Joni Tasa

  This single file reproduces EVERY table and figure in the paper.
  Run it once; all results flow from here.

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  INSTRUCTIONS                                                          │
  │  1. Set $root below to the root of this replication package            │
  │  2. Place required data files in $root/data/ (see below)              │
  │  3. Install required Stata packages (see below)                        │
  │  4. Run:  do "/path/to/00_replicate.do"                               │
  │                                                                        │
  │  Required Stata: version 17+ with reghdfe, ftools, estout              │
  │  Required: Python 3 with pyarrow (for parquet → CSV conversion)        │
  │  Estimated run time: ~3-4 hours (dominated by reghdfe on 53M obs)      │
  └─────────────────────────────────────────────────────────────────────────┘

  DATA SOURCES (place in $root/data/)
  ────────────────────────────────────
  1. Stock-level panel (constructed from CRSP + TAQ):
     - crsp_1927-2025_fixed_sorting_full.parquet (73.6M obs, 1927-2025)
     → Built from CRSP daily stock file with fixed monthly momentum decile
       assignments (held constant within each calendar month), institutional
       ownership (Thomson 13F), bid-ask quotes, and WRDS TAQ Intraday
       Indicators (Lee-Ready classified buy/sell volume, 2003-2022).
       Step 1 builds portfolio-level data (momentum_daily.dta) from this file.
       Step 2 converts it to CSV extracts for stock-level Stata regressions.
       ALL portfolio AND stock-level analyses derive from this single file.

  2. Bartik instrument (constructed from Thomson S12 + CRSP MF):
     - flow_pressure_instruments.csv (2.07M rows)
     → Built by code/13f/bartik_instrument.py using Thomson S12 mutual fund
       holdings linked to CRSP Mutual Fund flows via MFLINKS.

  3. Dividend analysis data:
     - dividend_ts_full.csv, divfreq_pretom_v2.csv
     → Built from CRSP dividend distributions + stock-level panel.

  4. Fresh/stale loser data:
     - loser_freshstale.csv
     → Built from JKP ret_3_1 characteristic + stock-level panel.

  5. International data (Compustat Global):
     - compustat_intl_pooled_v3.csv (86.9M obs, 19 countries, 1990-2025)
     → Built by code/stata/_intl_build_v3.py from Compustat Global g_secd.

  Note: Kenneth French CSVs (10_Portfolios_Prior_12_2_Daily.csv,
  F-F_Research_Data_Factors_daily 2.csv) are used only for comparison
  with daily-rebalanced portfolios (footnote in paper). They are NOT
  needed for replication.

  OUTPUT MAP
  ──────────
  Tables  → $output/*.tex (LaTeX) and $output/*.log (full regression output)
  Figures → $fig/*.pdf and $fig/*.pdf

  TABLE/FIGURE → CODE MAPPING  (paper numbering)
  ────────────────────────────────────────────────────────────
  MAIN PAPER:
  Table 1  (Baseline)              → SECTION B, _tables_vw.do
  Table 2  (Bid-Ask Spread)        → SECTION B, _table2_bas_contemp.do
  Table 3  (Subperiod Stability)   → SECTION B, _tables_vw.do
  Table 4  (Reversal)              → SECTION B, _vw_excrash.do
  Table 5  (Non-Quarter-End)       → SECTION B, _tables_vw.do
  Table 6  (TAQ Selling Pressure)  → SECTION D, _taq_tables.do
  Table 7  (T+1 Settlement DiD)    → SECTION F, _t1_did_earlymonth_control.do
  Table 8  (T+1 Falsification)     → SECTION F, _settlement_tables.do
  Table 9  (T+3→T+2 DiD)          → SECTION F, _settlement_tables.do
  Table 10 (Dividend Gradient)     → SECTION H, _divfreq_pretom_v2.do
  Table 11 (Fresh vs Stale)        → SECTION I, _fresh_table_gen.do
  Table 12 (International)         → SECTION J, _intl_v3_reg.do
  Table A1 (Quarter-End Amp.)      → SECTION B, _tables_vw.do
  Table A2 (Winner Baseline)       → SECTION B, _tables_vw.do
  Table A3 (S&P 500)               → SECTION G, _sp500_index_rebal.do

  INTERNET APPENDIX:
  Table IA.1 (Holding Period)      → SECTION K, _jt_holding_mktadj_nw.py
  Table IA.2 (Transaction Costs)   → SECTION C, _transaction_costs_decomp.py
  Table IA.3-4 (Intl All Countries)→ SECTION J, _intl_v3_reg.do
  Table IA.5 (Full Sample 1927+)   → SECTION K, _appendix_fullsample.do

  FIGURES:
  Figure 1 (Cumulative Wealth)     → SECTION A, _figures_matti_cumwml.do
  Figure 2 (Mkt-Adj Loser Bars)    → SECTION A, _figures_matti_mktadj.do
  Figure 3 (Daily Profile)         → SECTION A, _figures_matti_barchart.do
  Figure 4 (Rolling Window)        → SECTION A, _rolling_window_correct.do
  Figure 5 (T+1 Settlement Shift)  → SECTION A, _t1_settlement_figures.do
  Figure 6 (Crash Concentration)   → SECTION A, _crash_days_by_window.do
  Figure 7 (Killer Figure)         → SECTION A, _killer_figure.do
  Figure 8 (Flow Pressure Chart)   → SECTION A, _flow_pressure_chart.do
  Figure A1 (Daily Decomposition)  → SECTION A, _appendix_daily_decomp.do
  Figure A2 (Loser Subperiod)      → SECTION A, _appendix_subperiod_figures.do
  Figure A3 (Profile Subperiod)    → SECTION A, _appendix_subperiod_figures.do
  Figure A4 (December Displacement)→ SECTION A, _figures_matti_dec_pretom_mid.do
  Figure IA.1 (Rolling Window)     → SECTION A, _rolling_window_correct.do
  Figure IA.2 (Tail Trimming)      → SECTION A, _pretom_tail_trimming_v2.do

==============================================================================*/

version 17
clear all
set more off
set matsize 11000


* ══════════════════════════════════════════════════════════════════════════════
*  USER: SET THIS ONE PATH - everything else is derived
* ══════════════════════════════════════════════════════════════════════════════

* USER: Set this to the root of the replication package
* (the directory containing README.md, config.py, code/, data/, output/)
global root "SET_YOUR_PATH_HERE"


* ── Derived paths (do not edit) ──────────────────────────────────────────────

global data     "$root/data"
global code     "$root/code/stata"
global output   "$root/output"
global fig      "$root/output/figures"
global paperfig "$root/output/figures"

cap mkdir "$output"
cap mkdir "$fig"


* ── Master log ───────────────────────────────────────────────────────────────

cap log close _all
log using "$output/00_replicate.log", replace name(master)

di _n(3)
di "=================================================================="
di "  REPLICATION: The Intramonth Momentum Cycle"
di "  Nathan, Suominen, and Tasa (2026)"
di "=================================================================="
di _n "Root directory: $root"
di "Started: " c(current_date) " " c(current_time)
di "Stata version: " c(stata_version)
di ""

timer clear
timer on 99


* ══════════════════════════════════════════════════════════════════════════════
*  STEP 0: Verify required packages
* ══════════════════════════════════════════════════════════════════════════════

* Uncomment to install:
* ssc install reghdfe, replace
* ssc install ftools, replace
* ssc install estout, replace
* ssc install blindschemes, replace

cap which reghdfe
if _rc {
    di as error "ERROR: reghdfe not installed. Run: ssc install reghdfe"
    error 198
}
cap which estout
if _rc {
    di as error "ERROR: estout not installed. Run: ssc install estout"
    error 198
}



* ==============================================================================
*  STEP 1: Verify Python data construction has been run
*
*  Full pipeline (in order):
*    python pull_data.py    (WRDS pull; verify the queries against your own access first)
*                           -> data/crsp_daily_ciz.csv
*                           -> data/crsp_trading_days.csv
*                           -> data/sp500constituents.csv
*                           -> data/taq_iid.parquet
*                           -> data/Prior_2-12_Breakpoints.csv
*                           -> data/F-F_Research_Data_Factors_daily.csv
*    python build_panel.py --start-date 1926-01-01
*                           (Filipp's IA Section 1 pipeline; polars)
*                           -> data/crsp_fixed_sorting_panel.parquet
*    python imc.py build    (builds momentum_daily.dta from the panel)
*                           -> data/momentum_daily.dta
*
*  The pre-built stock-level CSVs (panel_fixed_*_reg.csv,
*  taq_panel_2003_2022.csv) ship with the replication package.
*
*  Required files in $data/:
*    momentum_daily.dta              (~26,000 obs, 1927-2025)
*    crsp_fixed_sorting_panel.parquet (consumed by imc.py tc/holding)
*    panel_fixed_vw_reg.csv          (~53M obs, VW weights)
*    panel_fixed_bas_reg.csv         (~46M obs, BAS subset)
*    panel_fixed_ew_reg.csv          (~53M obs, EW)
*    taq_panel_2003_2022.csv         (TAQ Lee-Ready, empty placeholder OK)
* ==============================================================================

di _n(2) "Verifying data files..."

cap confirm file "$data/momentum_daily.dta"
if _rc {
    di as error "ERROR: momentum_daily.dta not found."
    di as error "Run, in order:"
    di as error "  python $root/pull_data.py    (WRDS + Ken French)"
    di as error "  python $root/build_panel.py --start-date 1926-01-01"
    di as error "  python $root/imc.py build"
    error 601
}

cap confirm file "$data/panel_fixed_vw_reg.csv"
if _rc {
    di as error "ERROR: panel_fixed_vw_reg.csv not found in $data/."
    error 601
}

di "  All required data files found."



* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION A: PORTFOLIO-LEVEL FIGURES
*                    (Figures 1-8, A1-A4)
*                    All use $data/momentum_daily.dta
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION A: Portfolio-Level Figures"
di "=================================================================="


* ── Figure 1: Cumulative Wealth from Momentum Strategies ─────────────────
*    Three lines: Window-only, Full WML, and Rest-of-month cumulative wealth
*    Sample: 1980-2025

di _n ">>> Figure 1: Cumulative wealth"
do "$code/_figures_matti_cumwml.do"


* ── Figure 2: Market-Adjusted Monthly Loser Returns ──────────────────────
*    Two bars: PreTOM (-45.2 bps/mo, t=-3.32) vs non-PreTOM (-9.0 bps)
*    Also produces December comparison bars (Figure A4)

di _n ">>> Figure 2 + A4: Market-adjusted loser bars & December displacement"
do "$code/_figures_matti_mktadj.do"


* ── Figure 3: Average Daily Excess Returns by Window ─────────────────────
*    Winners/Losers/WML bars, PreTOM [t-9,t-4] vs rest

di _n ">>> Figure 3: Daily profile bar chart"
do "$code/_figures_matti_barchart.do"


* ── Figure 4: Rolling Six-Day Window Analysis ────────────────────────────
*    PreTOM [-9,-4] is unique outlier: -6.9 bps/day (t=-2.70)
*    Curve rises through month-start, consistent with reversal

di _n ">>> Figure 4: Rolling window test"
do "$code/_rolling_window_correct.do"


* ── Figure 5: Day-Level Shift from T+1 Settlement ───────────────────────
*    Old deadline t=-4 shifts +43 bps; new deadline t=-3 absorbs -27 bps

di _n ">>> Figure 5: T+1 settlement day-level shift"
do "$code/_t1_settlement_figures.do"


* ── Figure 6: Crash Day Concentration by Calendar Window ─────────────────
*    Month-start 1.43× expected at -200 bps threshold (z=4.87)
*    PreTOM near or below expected share

di _n ">>> Figure 6: Crash day concentration"
do "$code/_crash_days_by_window.do"


* ── Figure 7: Mean WML + Crash Probability by Trading Day ───────────────
*    Panel A: Mean WML with Newey-West bands
*    Panel B: Crash probability (WML < -200 bps)
*    PreTOM = positive returns + normal crashes; month-start = opposite

di _n ">>> Figure 7: Killer figure (dual-axis)"
do "$code/_killer_figure.do"


* ── Figure 8: Flow Pressure Chart ───────────────────────────────────────
*    Mutual fund flow pressure by momentum decile during PreTOM
*    Losers face strongest outflow pressure (-9.9), winners slight inflow (+0.5)

di _n ">>> Figure 8: Flow pressure chart"
do "$code/_flow_pressure_chart.do"


* ── Internet Appendix Figure: Tail Trimming Analysis ────────────────────
*    Panel A: Untrimmed WML by window
*    Panel B: WML after progressive left-tail trimming (0%, 1%, 5%, 10%)
*    PreTOM is structural; month-start driven by ~15 extreme days

di _n ">>> IA Figure: Tail trimming"
do "$code/_pretom_tail_trimming_v2.do"


* ── Figure A1: Daily Decomposition by Trading Day ────────────────────────
*    Panel A: Loser returns by t; Panel B: Winner returns by t
*    Losers dip during PreTOM; winners flat

di _n ">>> Figure A1: Appendix daily decomposition"
do "$code/_appendix_daily_decomp.do"


* ── Figures A2-A3: Subperiod Analysis ────────────────────────────────────
*    A2: Market-adjusted loser returns by window, 1980-2002 vs 2002-2025
*    A3: Daily profile (W/L/WML) by subperiod

di _n ">>> Figures A2-A3: Appendix subperiod figures"
do "$code/_appendix_subperiod_figures.do"


* ── Figure A4: December Displacement ─────────────────────────────────────
*    PreTOM attenuated in December; mid-month sharply negative
*    Tax-loss selling front-runs institutional selling

di _n ">>> Figure A4: December displacement"
do "$code/_figures_matti_dec_pretom_mid.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION B: STOCK-LEVEL REGRESSION TABLES
*                    (Tables 1, 2, 3, 4, 5, A1, A2)
*                    Uses $data/panel_fixed_vw_reg.csv and panel_fixed_bas_reg.csv
*                    (extracted from parquet in Step 2)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION B: Stock-Level Regression Tables"
di "=================================================================="


* ── Tables 1, 3, 5, A1, A2 (main VW regressions) ───────────────────────
*    Table 1:  Baseline (EW: -2.550*, VW: -7.151***), 53.3M obs
*    Table 3:  Subperiod stability (1980-2002: -5.762**, 2002-2025: -8.503**)
*    Table 5:  Non-quarter-end months (lp=-7.52***)
*    Table A1: Quarter-end amplification (lp×QtrEnd insignificant)
*    Table A2: Winner baseline (Winner×PreTOM insignificant)

di _n ">>> Tables 1, 3, 5, A1, A2: Main VW regressions"
do "$code/_tables_vw.do"


* ── Table 2: Window Effect and Bid-Ask Spread ────────────────────────────
*    4 columns: EW, EW+BAS, VW, VW+BAS
*    Triple interaction Loser×PreTOM×BAS = +30.4** (EW), +58.8** (VW)
*    Effect concentrates among liquid losers

di _n ">>> Table 2: BAS interaction"
do "$code/_table2_bas_contemp.do"


* ── Table 4: Post-Window Reversal in Loser Returns ──────────────────────
*    Loser×PreTOM = -5.508**, Loser×Post = +8.215**
*    Reversal test: 6×β_PreTOM + 3×β_Post = 0, F=0.19, p=0.66
*    Cannot reject full reversal → temporary price pressure
*    Also runs ex-crash robustness (reversal holds)
*
*    Output: table_reversal_vw.tex (+ ex-crash results in log)

di _n ">>> Table 4: Reversal + ex-crash robustness"
do "$code/_vw_excrash.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION C: TRANSACTION COST DECOMPOSITION
*                    (Internet Appendix Table IA.2)
*                    Uses $data/momentum_daily.dta
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION C: Transaction Cost Decomposition (IA Table 2)"
di "=================================================================="

*  IA Table 2 decomposes the standard VW WML strategy into:
*    - PreTOM component (days t=-9 to t=-4)
*    - Rest-of-month component (all other days)
*  Transaction costs = VW average BAS of stocks changing decile, applied 1×/mo.
*
*  Panel A: Full sample (1980-2025)
*  Panel B: Post-decimalization (2001-2025)

cap log close
log using "$output/table5_tc_decomp.log", replace text

use "$data/momentum_daily.dta", clear
gen yr = year(date)
keep if yr >= 1980

* Window flag
gen window = (t >= -9 & t <= -4)

* ── Compound daily WML within each window per month ──────────────────────
gen log_wml_vw = ln(1 + wml_vw)

* Monthly compounded PreTOM return
bysort ym: egen pretom_logret = total(log_wml_vw * window)
bysort ym: egen rest_logret   = total(log_wml_vw * (1 - window))
bysort ym: egen full_logret   = total(log_wml_vw)

* Keep one obs per month
bysort ym: keep if _n == 1

gen pretom_ret = exp(pretom_logret) - 1
gen rest_ret   = exp(rest_logret) - 1
gen full_ret   = exp(full_logret) - 1

* Convert to bps
replace pretom_ret = pretom_ret * 10000
replace rest_ret   = rest_ret * 10000
replace full_ret   = full_ret * 10000

* ── Panel A: Full sample ─────────────────────────────────────────────────
di _n "=== PANEL A: Full Sample (1980-2025) ==="
qui sum full_ret
local gross_full = r(mean)
qui sum pretom_ret
local pretom_full = r(mean)
local pct_pretom = `pretom_full' / `gross_full' * 100
qui sum rest_ret
local rest_full = r(mean)
local pct_rest = `rest_full' / `gross_full' * 100

di "Gross WML:     " %7.1f `gross_full' " bps/mo"
di "  PreTOM:      " %7.1f `pretom_full' " bps/mo [" %3.0f `pct_pretom' "%]"
di "  Rest:        " %7.1f `rest_full' " bps/mo [" %3.0f `pct_rest' "%]"

* Sharpe ratio (annualized)
qui sum full_ret
local sr_full = r(mean) / r(sd) * sqrt(12)
di "Sharpe (gross): " %6.2f `sr_full'

* ── Panel B: Post-decimalization ─────────────────────────────────────────
di _n "=== PANEL B: Post-Decimalization (2001-2025) ==="
qui sum full_ret if yr >= 2001
local gross_post = r(mean)
qui sum pretom_ret if yr >= 2001
local pretom_post = r(mean)
local pct_pretom_post = `pretom_post' / `gross_post' * 100
qui sum rest_ret if yr >= 2001
local rest_post = r(mean)
local pct_rest_post = `rest_post' / `gross_post' * 100

di "Gross WML:     " %7.1f `gross_post' " bps/mo"
di "  PreTOM:      " %7.1f `pretom_post' " bps/mo [" %3.0f `pct_pretom_post' "%]"
di "  Rest:        " %7.1f `rest_post' " bps/mo [" %3.0f `pct_rest_post' "%]"

di _n "NOTE: Transaction costs (TC) and net WML require stock-level BAS data."
di "The TC figures in the paper (112.1 bps full, 13.9 bps post-decim) are"
di "computed from the stock panel via _transaction_costs_decomp.py."
di "Net WML = Gross WML - TC."
di ""
di "Running Python TC decomposition..."
shell python "$root/imc.py" tc --root "$root"

log close


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION D: TAQ SELLING PRESSURE
*                    (Table 6)
*                    Uses $data/taq_panel_2003_2022.csv (extracted from parquet in Step 2)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION D: TAQ Selling Pressure (Table 6)"
di "=================================================================="

*  Loser×PreTOM on net selling pressure: +0.0020** (t=2.50)
*  Firm and date fixed effects, 17.9M obs, 2003-2022

di _n ">>> Table 6: TAQ selling pressure"
do "$code/_taq_tables.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION E: BARTIK INSTRUMENT
*                    (results discussed in text, no numbered table)
*                    Uses $data/taq_panel_2003_2022.csv (from parquet) +
*                         $data/flow_pressure_instruments.csv (Thomson S12)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION E: Flow-Induced Selling Pressure / Bartik IV"
di "  (Not a numbered table in paper - results discussed in text)"
di "=================================================================="

*  First stage: Bartik instrument → TAQ net sell pressure
*  Losers:  Z_bartik = -2.07*** (t=-8.58)
*  Winners: Z_bartik = +1.30*** (t=4.89)
*  Loser-winner differential: F=108, p<0.0001
*  → Redemption-driven outflows selectively sell losers during PreTOM

di _n ">>> Bartik first stage (2×2)"
do "$code/_flow_iv_firststage.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION F: SETTLEMENT NATURAL EXPERIMENTS
*                    (Tables 7, 8, 9)
*                    Uses $data/momentum_daily.dta + $data/panel_fixed_vw_reg.csv
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION F: Settlement Natural Experiments (Tables 7, 8, 9)"
di "=================================================================="


* ── Table 7: T+2→T+1 Settlement DiD (May 28, 2024) ──────────────────────
*    Panel A: Cell means (early-month [T+5,T+8] control)
*    Panel B: Portfolio DiD with early-month control, robust SEs
*    Panel C: Stock-level triple-diff, firm+date FE, VW, clustered by date
*    Output: log file

di _n ">>> Table 7: T+1 settlement DiD (early-month control)"
do "$code/_t1_did_earlymonth_control.do"

* ── Tables 8-9: T+1 Falsification + T+3→T+2 DiD ────────────────────────
*    Table 8: Falsification (t=-4 vs t=-3 pair throughout)
*      Real: DiD = +69.45 (t=2.36)
*      Placebo days (t=-6 vs t=-7): near zero
*      Placebo dates (May 2020, May 2018): near zero
*    Table 9: T+3→T+2 (same t=-4 vs t=-3 pair, event Sep 5 2017)

di _n ">>> Tables 8-9: Settlement falsification + T+2 DiD"
do "$code/_settlement_tables.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION G: ROBUSTNESS (mentioned in text)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION G: Robustness Tests (Section 6.5-6.7)"
di "=================================================================="


* ── Table A3: Index Rebalancing ──────────────────────────────────────────
*    Non-S&P 500: Loser×PreTOM = -6.3 bps (t=-3.14)
*    S&P 500:     Loser×PreTOM = -7.1 bps (t=-2.07)
*    Interaction:  -3.0 (t=-0.89), insignificant
*    → Rules out passive index rebalancing

di _n ">>> Table A3: S&P 500 index rebalancing test"
do "$code/_sp500_index_rebal.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION H: DIVIDEND GRADIENT
*                    (Table 10 in paper)
*                    Uses $data/dividend_ts_full.csv, $data/divfreq_pretom_v2.csv
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION H: Dividend Gradient (Table 10)"
di "=================================================================="

*  Table 10 has three panels:
*    Panel A: Payer composition by decile (88% of D1 losers pay no dividends)
*    Panel B: Within-quarter PreTOM returns by month (Month 1/2/3)
*    Panel C: TAQ selling pressure by quarter-month
*
*  Panel A is descriptive (payer shares computed during CSV construction in
*  Python; see _divfreq_pretom_v2.py). The CSV only contains quarterly payers.
*  Panels B+C are produced by _divfreq_pretom_v2.do (three-month split).
*  The table_dividend_gradient.tex in output/ is manually maintained
*  from these log outputs.

di _n ">>> Table 10: Dividend gradient (Panels A-C)"
do "$code/_divfreq_pretom_v2.do"

* Additional time-series test (not in paper table, discussed in text)
di _n ">>> Dividend time-series (supplementary)"
do "$code/_dividend_ts_full.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION I: FRESH VS STALE LOSERS
*                    (Table 11 in paper)
*                    Uses $data/loser_freshstale.csv
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION I: Fresh vs Stale Losers (Table 11)"
di "=================================================================="

*  Table 11: PreTOM Returns by Loser Freshness
*    Tercile: Fresh losers -3.30 bps/day (t=-2.17), stale +1.24 (t=1.02)
*    F-test fresh=stale: F=7.15, p=0.008
*    Continuous: PreTOM × fresh_z = -1.77 bps/sd (t=-2.38)
*    December falsification: gradient vanishes in December
*
*    Output: output/table_fresh.tex

di _n ">>> Fresh vs stale: all specs + table generation"
do "$code/_fresh_table_gen.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION J: INTERNATIONAL EVIDENCE
*                    (Table 12 in paper, Tables IA.3-4 in Internet Appendix)
*                    Uses $data/compustat_intl_pooled_v3.csv
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION J: International Evidence (Table 12, IA Tables)"
di "=================================================================="

*  Table 12 (paper): Pooled + 10 selected countries
*    Pooled loser-market difference is negative and statistically significant
*    Winners show no differential PreTOM concentration (+0.74, t=0.78)
*  Tables IA.3-4 (internet appendix): All 19 countries, losers and winners
*
*  Data: Compustat Global, 19 developed markets (ex-Japan, ex-Canada)
*  Built by _intl_build_v3.py from comp.g_secd

di _n ">>> International: pooled + country regressions"
do "$code/_intl_v3_reg.do"


* ══════════════════════════════════════════════════════════════════════════════
*                    SECTION K: INTERNET APPENDIX TABLES
*                    (Holding Period, Full-Sample, Transaction Costs)
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  SECTION K: Internet Appendix Tables"
di "=================================================================="


* ── Table IA.1: Holding Period Analysis ─────────────────────────────────
*    Varies K from 1 to 12 months; PreTOM significant at 1% for all K
*    Results are reported in the paper.
*    Underlying computation: Python (overlapping portfolio construction)

di _n ">>> IA Table 1: Holding period analysis (Python)"
shell python "$root/imc.py" holding --root "$root"


* ── Table IA.2: Transaction Cost Decomposition ──────────────────────────
*    (gross/net returns already computed in Section C above)
*    Stock-level BAS computation via Python

di _n ">>> IA Table 2: Transaction cost decomposition (already run in Section C)"


* ── Table IA.5: Full-Sample Evidence (1927-2025) ───────────────────────
*    Extends main results back to 1927
*    Loser PreTOM underperformance significant across full century (t=-5.47)

di _n ">>> IA Table 5: Full-sample evidence (1927+)"
do "$code/_appendix_fullsample.do"


* ══════════════════════════════════════════════════════════════════════════════
*  COPY GENERATED TABLES TO PAPER DIRECTORY
*  Some do-files write to $output/, paper reads from output/.
*  Tables written directly to output/: table_reversal_vw, table_fresh,
*    table_intl (generated in-place by their do-files).
*  Tables needing copy from $output/:
* ══════════════════════════════════════════════════════════════════════════════

di _n(3) "=================================================================="
di "  Copying generated tables to output/"
di "=================================================================="

* Tables generated by _tables_vw.do (Tables 1, 3, 5, A1)
cap copy "$output/table1_baseline_vw.tex" "$output/table1_baseline.tex", replace
cap copy "$output/table4_subperiod_vw.tex" "$output/table4_subperiod.tex", replace
cap copy "$output/table5_nonqtr_vw.tex" "$output/table5_nonqtr.tex", replace
cap copy "$output/table6_qtr_amplify_vw.tex" "$output/table6_qtr_amplify.tex", replace

* Table 2 generated by _table2_bas_contemp.do
cap copy "$output/table2_bas_contemp.tex" "$output/table2_bas.tex", replace


* Table 10 dividend gradient (output/table_dividend_gradient.tex) -


* Table generated by _appendix_fullsample.do
cap copy "$output/table_ia_fullsample.tex" "$output/table_ia_fullsample.tex", replace

* TC decomposition table (output/table_tc_decomp.tex) - Python script

di "  Table copy complete."


* ══════════════════════════════════════════════════════════════════════════════
*  REPLICATION COMPLETE
* ══════════════════════════════════════════════════════════════════════════════

timer off 99
timer list 99

di _n(3) "=================================================================="
di "  REPLICATION COMPLETE"
di "=================================================================="
di ""
di "Output directory: $output"
di "Figures directory: $fig"
di "Paper figures:     $fig"
di ""
di "Completed: " c(current_date) " " c(current_time)
di ""
di "Key regression tables are written to $output/ as .tex and .log files."
di "Compare the reported coefficients against the corresponding tables in the paper."

log close master

# The Intramonth Momentum Cycle (IMC)

**Replication code for Nathan, Suominen, and Tasa (2026), "The Intramonth Momentum Cycle."**

This repository reproduces the *intramonth momentum cycle*: nearly all US momentum profits accrue in a six-day window before the turn of the month (PreTOM, trading days t-9 to t-4). The effect is driven by losers, not winners, and shifts in lock-step with equity settlement rules. The mechanism is institutional: open-end funds raise cash for month-end redemptions by selling the stocks easiest to dump, and losers absorb the pressure.

## Why this matters

In the 1980-2025 US sample bundled with this repo:

- **PreTOM is 28.6% of trading days but produces 77% of momentum's log wealth.**
- **WML in PreTOM:** +10.2 bps/day (t = 3.7). **WML in the rest of the month:** +2.4 bps/day (t = 1.2).
- **The asymmetry is loser-driven.** Losers earn -11.3 bps/day in PreTOM (t = -3.5) and +5.5 bps/day outside it. Winners are flat in PreTOM (-1.2 bps, t = -0.4) and earn their excess return in the rest of the month.
- **$1 invested in WML only on PreTOM days grows to $18.78. The same dollar invested on every other day grows to $2.37. Buy-and-hold WML grows to $44.46.**
- The shift from T+2 to T+1 settlement in May 2024 moves the loser trough one day later, exactly as the dash-for-cash hypothesis predicts.

## Reproduce the headline result in 5 seconds

No WRDS, no Stata, no setup beyond Python:

```bash
git clone https://github.com/dannyboy990/momentum-replication.git
cd momentum-replication
pip install -r requirements.txt
python run_imc.py
```

`run_imc.py` reads the bundled portfolio file (`data/momentum_daily.dta`, 26,001 daily observations 1927-2025) and writes:

- `output/imc_headline.pdf` / `.png` - the three-line cumulative wealth figure (PreTOM-only, full WML, rest-of-month)
- `output/imc_headline.csv` - the underlying monthly series
- A console summary of the PreTOM/Rest means, t-stats, and terminal wealth

The bundled `momentum_daily.dta` is a pre-computed *aggregate* of CRSP loser/winner/WML portfolio returns, the same kind of object Kenneth French publishes daily on his website. It is not licensed CRSP micro-data. With it, anyone can reproduce Figures 1-8 and A1-A4 from the paper.

## Reproduce every table and figure in the paper (Stata + WRDS)

The full pipeline runs every regression in `00_replicate.do` against a stock-level panel of ~53M observations. This requires CRSP and Stata.

### Requirements

- **Stata 17+** with `reghdfe`, `ftools`, `estout` (`ssc install`)
- **CRSP via WRDS**, used to construct the stock-level panel `crsp_1927-2025_fixed_sorting_full.parquet` (4.1 GB, fixed monthly momentum decile assignments). The construction is described in Internet Appendix Section IA.1.
- **Python 3.9+ with pyarrow** for parquet → CSV extraction (the bundled `code/stata/_build_momentum_daily.py` rebuilds `momentum_daily.dta` from the parquet, and `00_replicate.do` Step 2 extracts CSV panels for the regressions)

### Run

Open `code/stata/00_replicate.do`, set `$root` to this directory, and run it. Estimated runtime 3-4 hours, dominated by `reghdfe` on ~53M observations.

```stata
global root "/path/to/momentum-replication"
do "code/stata/00_replicate.do"
```

`00_replicate.do` is the table/figure-to-code map for the paper:

| Output | Stata file | Description |
|---|---|---|
| Table 1 | `_tables_vw.do` | Baseline stock-level regressions, firm + date FE |
| Table 2 | `_table2_bas_contemp.do` | Bid-ask spread interaction |
| Table 4 | `_vw_excrash.do` | Post-window reversal |
| Table 6 | `_taq_tables.do` | TAQ selling pressure |
| Table 7 | `_t1_did_earlymonth_control.do` | T+1 settlement DiD |
| Figures 1-8 | `_figures_*.do`, `_killer_figure.do`, `_crash_days_by_window.do`, `_pretom_tail_trimming_v2.do` | Main paper figures |
| Figures A1-A4 | `_appendix_*.do` | Appendix figures |

Five sections of `00_replicate.do` need additional sources beyond CRSP. The code is included; missing data fails only that section.

| Section | Data | WRDS subscription |
|---|---|---|
| Table 6 (TAQ selling pressure) | `taq_panel_2003_2022.csv` | WRDS Intraday Indicators |
| Table 10 (Dividends) | `dividend_ts_full.csv`, `divfreq_pretom_v2.csv` | CRSP distributions |
| Table 11 (Fresh vs stale losers) | `loser_freshstale.csv` | JKP characteristics |
| Table 12 (International) | `compustat_intl_pooled_v3.csv` | Compustat Global |
| Figure 8 (Flow pressure) | Bartik instrument data | Thomson S12, CRSP MF |

## Expected output from `python run_imc.py`

```
WML PreTOM mean:                    +10.15 bps/day  (t =  +3.68)
WML Rest mean:                       +2.39 bps/day  (t =  +1.22)
Losers PreTOM mean:                 -11.32 bps/day  (t =  -3.53)
Losers Rest mean:                    +5.51 bps/day  (t =  +2.50)
PreTOM-only cumulative wealth:       $18.78
Full WML cumulative wealth:          $44.46
Rest-of-month cumulative wealth:     $ 2.37
T+1 DiD (portfolio, t=-4 vs t=-3):   +84.72 bps     (t = +2.80)
```

These match the paper's portfolio-level numbers exactly. Small discrepancies (<10%) versus the published paper for stock-level regressions arise from CRSP vintage updates.

## Citation

If you use this code or data, please cite:

```
Nathan, D., Suominen, M., and Tasa, J. (2026).
"The Intramonth Momentum Cycle." Working Paper.
Available at SSRN: https://ssrn.com/abstract=6426026
```

## Links

- **Paper (SSRN):** https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6426026
- **Author website:** https://www.danielrnathan.com

## Contact

Daniel Nathan, daniel.nathan@polyu.edu.hk

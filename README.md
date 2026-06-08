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

## Rebuild the full panel from raw data (Python + WRDS)

The data pipeline is pure Python — from raw CRSP/TAQ pulls to the analysis tables. Stata is needed only for the stock-level panel regressions (next section).

```bash
# 1. Pull raw inputs from WRDS (needs a WRDS account with CRSP + TAQ access)
python pull_data.py --what all

# 2. Build the fixed-monthly-sorting panel (CRSP + TAQ -> one parquet)
python build_panel.py

# 3. Reproduce the analysis layer from the panel
python imc.py all
```

`imc.py` is a single-file pipeline with subcommands:

| Command | Output |
|---|---|
| `python imc.py build` | `data/momentum_daily.dta` from the panel parquet |
| `python imc.py headline` | cumulative-wealth figure + console summary (same as `run_imc.py`) |
| `python imc.py tc` | transaction-cost decomposition (Internet Appendix) |
| `python imc.py holding` | holding-period decomposition (Internet Appendix) |
| `python imc.py all` | all of the above, in order |

- **`pull_data.py`** issues the WRDS queries (CRSP daily, TAQ Intraday Indicators, S&P 500 membership) and downloads the Ken French momentum breakpoints. The queries follow the CRSP CIZ flat-file schema; verify table and column names against your own WRDS access before running.
- **`build_panel.py`** constructs the fixed-monthly-sorting decile panel — NYSE Prior 2-12 breakpoints, lagged market-cap weights, bid-ask spreads, S&P 500 flag, Fama-French factors, and the Lee-Ready TAQ merge — following Internet Appendix Section IA.1, and writes `data/crsp_fixed_sorting_panel.parquet`.

The large files (the ~4 GB panel parquet, the per-table CSVs) are git-ignored; only the small aggregate `momentum_daily.dta` is bundled so the headline runs out of the box. The full rebuild additionally needs `polars`, `wrds`, and `requests` (see `requirements.txt`).

## Reproduce every table and figure in the paper (Stata + WRDS)

The full pipeline runs every regression in `00_replicate.do` against a stock-level panel of ~53M observations. This requires CRSP and Stata.

### Requirements

- **Stata 17+** with `reghdfe`, `ftools`, `estout` (`ssc install`)
- **CRSP via WRDS**, used to construct the stock-level panel `crsp_fixed_sorting_panel.parquet` (~4 GB, fixed monthly momentum decile assignments) via the Python rebuild above. The construction is described in Internet Appendix Section IA.1.
- **Python 3.9+** — `00_replicate.do` Step 2 extracts the CSV panels for the regressions from that parquet.

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
```

These match the paper's portfolio-level numbers exactly. The T+1 settlement difference-in-differences (Table 7) and the stock-level regressions are reproduced by the Stata pipeline below. Small discrepancies (<10%) versus the published paper for stock-level regressions arise from CRSP vintage updates.

## Python translation of the table regressions (experimental)

For users who would rather not install Stata, `imc_tables.py` provides an **AI-assisted** Python translation of the stock-level table regressions, using `pyfixest` for the firm + date fixed-effects / two-way-clustered specification.

As a demonstration, **only the first table (Table 1, the baseline) is implemented and run.** On the authoritative panel it reproduces the Stata coefficients exactly (EW Loser$\times$PreTOM $= -2.550$, VW $= -7.151$). The remaining tables follow the same pattern but are not translated.

```bash
python imc_tables.py
```

We **cannot vouch that this Python translation matches the Stata output in every case** — it was produced with AI assistance and only Table 1 was checked. The Stata code in `code/stata/` remains the **authoritative** source for every number in the paper.

## Data provenance and licensing

The only data file in this repository is `data/momentum_daily.dta` — a daily series of value- and equal-weighted winner/loser/WML momentum-decile **portfolio returns** plus the Fama-French factors, 1927-2025. It is an aggregate, comparable to the portfolio return series Kenneth French publishes, and contains **no licensed micro-data**.

This repository does **not** contain or redistribute any proprietary data. In particular:
- no CRSP, TAQ, or Compustat micro-data;
- **no commercial mutual-fund-flow data — no Morningstar, no EPFR, no daily fund-flow series;**
- no Thomson/Refinitiv holdings.

`pull_data.py` and `build_panel.py` are the code that *downloads and constructs* the stock-level panel from WRDS. Running them requires your own WRDS subscription with the relevant entitlements (CRSP, TAQ); the data files they produce are git-ignored and are never committed to this repository.

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

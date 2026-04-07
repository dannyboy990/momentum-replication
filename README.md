# Replication: The Intramonth Momentum Cycle

**Daniel Nathan, Matti Suominen, and Joni Tasa (2026)**

This package reproduces all tables and figures from "The Intramonth Momentum Cycle." The paper shows that 64% of momentum (Winners Minus Losers) profits concentrate in six trading days before month-end (t=-9 to t=-4). The effect is driven entirely by loser stocks and is consistent with institutional selling to meet month-end redemptions.

## Requirements

- **Python 3.9+** with packages in `requirements.txt`
- **Stata 17+** with `reghdfe`, `ftools`, `estout` (install via `ssc install`)
- **WRDS subscription** with CRSP access (daily + monthly stock files)
- ~5 GB disk space for data files

## Setup

```bash
git clone https://github.com/dannyboy990/momentum-replication.git
cd momentum-replication
pip install -r requirements.txt
```

Edit `config.py` and set your WRDS username:
```python
WRDS_USERNAME = "your_wrds_username"
```

## Execution

### Step 1: Data construction (Python)

```bash
python src/01_pull_crsp.py      # Download CRSP from WRDS (~20-40 min)
python src/02_build_panel.py    # Build portfolios + CSV panels (~15 min)
```

### Step 2: Analysis (Stata)

Open `code/stata/00_replicate.do` in Stata. Set the `$root` global to this directory:
```stata
global root "/path/to/momentum-replication"
```

Then run:
```stata
do "code/stata/00_replicate.do"
```

Estimated runtime: 3-4 hours (dominated by `reghdfe` on ~53M observations).

## What This Reproduces

**All tables and figures in the paper**, including:

| Output | Stata code | Description |
|--------|-----------|-------------|
| Table 1 | `_tables_vw.do` | Baseline stock-level regressions (firm + date FE) |
| Table 2 | `_table2_bas_contemp.do` | Bid-ask spread interaction |
| Table 4 | `_vw_excrash.do` | Post-window reversal |
| Table 6 | `_taq_tables.do` | TAQ selling pressure (requires TAQ data) |
| Table 7 | `_t1_did_earlymonth_control.do` | T+1 settlement DiD |
| Figures 1-8 | `_figures_*.do` | All main paper figures |
| Figures A1-A4 | `_appendix_*.do` | Appendix figures |

See the header of `00_replicate.do` for the complete table/figure-to-code mapping.

## Data Notes

- **No proprietary data is distributed.** All data is pulled from WRDS at runtime.
- Python scripts construct the exact panel described in Internet Appendix Section IA.1:
  CRSP CIZ Flat File Format 2.0, common-stock filters, trading-day expansion,
  12-2 daily momentum with validity checks, French NYSE breakpoints.

### What requires additional data

The following sections of `00_replicate.do` require datasets beyond the CRSP pull.
The code is included; the data must be constructed separately with the appropriate
WRDS subscriptions. Sections that fail due to missing data do not affect other sections.

| Section | Data needed | WRDS subscription |
|---------|------------|-------------------|
| Table 6 (TAQ selling pressure) | `taq_panel_2003_2022.csv` | WRDS TAQ Intraday Indicators |
| Table 10 (Dividends) | `dividend_ts_full.csv`, `divfreq_pretom_v2.csv` | CRSP distributions |
| Table 11 (Fresh/stale losers) | `loser_freshstale.csv` | JKP characteristics |
| Table 12 (International) | `compustat_intl_pooled_v3.csv` | Compustat Global |
| Figure 8 (Flow pressure) | Bartik instrument data | Thomson S12, CRSP MF |

## Expected Output

After running both Python and Stata scripts, key numbers should match:

```
Full WML cumulative wealth (1980-2025):  ~$45.89
PreTOM cumulative wealth:                ~$18.11
Complementary cumulative wealth:         ~$2.53
Loser-PreTOM VW (stock-level):           ~-7.15 bps/day (t ~ -3.08)
T+1 DiD (portfolio, t=-4 vs t=-3):       ~+84.7 bps (t ~ 2.5)
```

Small discrepancies (<10%) may arise from CRSP data vintage updates. The Internet
Appendix discusses sensitivity to construction choices.

## Citation

```
Nathan, D., Suominen, M., and Tasa, J. (2026). The Intramonth Momentum Cycle.
Working Paper.
```

## Contact

Daniel Nathan — daniel.nathan@polyu.edu.hk

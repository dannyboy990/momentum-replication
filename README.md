# Replication: The Intramonth Momentum Cycle

**Daniel Nathan, Matti Suominen, and Joni Tasa (2026)**

This package reproduces the core results from "The Intramonth Momentum Cycle." The paper shows that 64% of momentum (Winners Minus Losers) profits concentrate in six trading days before month-end (t=-9 to t=-4). The effect is driven entirely by loser stocks and is consistent with institutional selling to meet month-end redemptions. The main causal identification exploits the SEC's T+1 settlement reform of May 28, 2024.

## Requirements

- **Python 3.9+**
- **WRDS subscription** with CRSP access (daily + monthly stock files). Most university finance departments have this. See https://wrds-www.wharton.upenn.edu.
- ~5 GB disk space for data files

## Setup

```bash
git clone https://github.com/[your-repo]/momentum-replication.git
cd momentum-replication
pip install -r requirements.txt
```

Edit `config.py` and set your WRDS username:
```python
WRDS_USERNAME = "your_wrds_username"
```

## Execution

Run scripts in order:

```bash
python src/01_pull_crsp.py        # Download CRSP data from WRDS (~20-40 min)
python src/02_build_portfolios.py # Build momentum portfolios (~10 min)
python src/03_performance.py      # Cumulative wealth, alphas (~2 min)
python src/04_did_t1.py           # T+1 settlement DiD (~5 min)
python src/05_december.py         # December falsification (~1 min)
python src/06_tables_figures.py   # Summary and verification
```

Script 01 requires a WRDS connection (internet access + credentials). Scripts 02-06 run offline using the downloaded data.

## What This Reproduces

| Result | Script | Description |
|--------|--------|-------------|
| Figure 1 | 03 | Cumulative wealth: PreTOM vs rest vs full WML |
| Table 1 | 03 | Summary statistics and factor alphas |
| Table 7 | 04 | T+1 settlement difference-in-differences |
| Figure 5 | 04 | Selling migration: pre vs post T+1 reform |
| Table 10 | 05 | December depletion by calendar month |
| Figure A4 | 05 | December falsification bar chart |

## Expected Output

After running all scripts, `output/` will contain:

```
output/
  momentum_daily.csv           # Portfolio-level daily returns (safe to share)
  table_performance.csv        # Summary statistics
  table_alphas.csv             # FF3 alpha regressions
  table_did_t1.csv             # DiD regression results
  table_december.csv           # Month-by-month loser PreTOM returns
  fig_cumulative_wealth.pdf    # Three-line cumulative wealth plot
  fig_selling_migration.pdf    # Pre/post T+1 loser return by trading day
  fig_december.pdf             # Bar chart by calendar month
```

## Verification

The final script prints key numbers that should match the paper:

```
Full WML cumulative wealth:       $45.89
PreTOM cumulative wealth:         $18.11
Complementary cumulative wealth:  $2.53
Loser-PreTOM mean (bps/day):      -7.3
Loser-PreTOM t-stat:              -2.95
DiD coefficient (bps):            +46.8
DiD t-stat:                       3.01
December Loser-PreTOM t-stat:     0.28
September Loser-PreTOM t-stat:    -3.36
```

Small discrepancies (within 10%) are expected due to CRSP data vintage updates, exact treatment of delistings, and breakpoint computation details. The Internet Appendix of the paper discusses sensitivity to these choices.

## Full Replication

This package covers the core portfolio-level and settlement results. The complete paper includes additional analyses that require:
- **TAQ** intraday data (WRDS Intraday Indicators) for selling pressure tests
- **Thomson S12** mutual fund holdings for Bartik IV instruments
- **Compustat Global** for international evidence

These datasets require separate WRDS subscriptions. The full replication code (Stata + Python) is available upon request.

## Data Notes

- **No proprietary data is distributed.** All data is pulled from WRDS at runtime.
- `momentum_daily.csv` in the output directory contains portfolio-level daily returns (aggregated across hundreds of stocks per decile). This is safe to share and comparable to data on Ken French's website.
- Momentum portfolios use **fixed monthly sorting** (decile assignments held constant within each calendar month), not daily rebalancing as in French's online data.
- NYSE breakpoints: only NYSE-listed stocks determine decile cutoffs; all stocks are then assigned.

## Citation

```
Nathan, D., Suominen, M., and Tasa, J. (2026). The Intramonth Momentum Cycle.
Working Paper.
```

## Contact

Daniel Nathan — daniel.nathan@polyu.edu.hk

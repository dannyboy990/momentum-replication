# Data Directory

## What's bundled

**`momentum_daily.dta`** - 26,001 rows, ~2.4 MB. Daily VW and EW portfolio returns for momentum decile 1 (losers) and decile 10 (winners), 1927-2025. Built from CRSP with fixed monthly momentum decile assignments. This is an aggregated derivative of CRSP analogous to the daily portfolio files Kenneth French publishes on his website. It is sufficient to reproduce all portfolio-level results in the paper (Figures 1-8, A1-A4) and is what `python run_imc.py` reads.

| Variable | Description |
|---|---|
| `date` | Trading date (Stata %td) |
| `ym` | Year-month index |
| `t` | Trading day relative to month-end (0 = last day, -1 = second-to-last) |
| `winners_vw` | Winner decile (D10) value-weighted excess return |
| `losers_vw` | Loser decile (D1) value-weighted excess return |
| `wml_vw` | WML = winners_vw - losers_vw |
| `winners_ew`, `losers_ew`, `wml_ew` | Equal-weighted analogues |
| `mktrf`, `smb`, `hml`, `rf` | Fama-French factors |

The PreTOM window is `t in [-9, -4]`.

## What's not bundled

The stock-level panel `crsp_1927-2025_fixed_sorting_full.parquet` (4.1 GB, 73.6M rows) used by the Stata regressions in `00_replicate.do` requires a WRDS/CRSP subscription and cannot be redistributed. Users with WRDS access can rebuild it; the construction is documented in Internet Appendix Section IA.1 of the paper.

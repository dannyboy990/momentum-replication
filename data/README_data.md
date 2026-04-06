# Data Directory

This directory is populated by `src/01_pull_crsp.py`. No raw data files are included in this repository.

## Required Access

You need a **WRDS subscription** with access to:
- **CRSP** daily stock file (`crsp.dsf`) and monthly stock file (`crsp.msf`)
- **CRSP** stock event name history (`crsp.msenames`)

Most university subscriptions include CRSP access. Check with your library or visit https://wrds-www.wharton.upenn.edu.

## Files Created by the Scripts

| File | Created by | Description | Approx. Size |
|------|-----------|-------------|-------------|
| `crsp_daily.parquet` | 01 | CRSP daily returns, 1980-2025 | ~2 GB |
| `crsp_monthly.parquet` | 01 | CRSP monthly returns for momentum ranking | ~200 MB |
| `portfolio_daily.parquet` | 02 | Decile portfolio daily returns (VW + EW) | ~30 MB |
| `stock_panel.parquet` | 02 | Stock-day panel with decile assignments | ~2 GB |
| `ff3_daily.parquet` | 03 | Fama-French 3 factors (downloaded from Ken French) | ~2 MB |

## WRDS Authentication

On first run, the `wrds` Python package will prompt for your password. It stores credentials in `~/.pgpass` so you only need to enter them once. If you prefer not to cache credentials, set `WRDS_USERNAME` in `config.py` and enter your password at the prompt each time.

## Troubleshooting

- **"Permission denied" on CRSP tables**: Your WRDS subscription may not include CRSP. Contact your institution's WRDS administrator.
- **Download takes too long**: The daily file is ~73M rows. Expect 20-40 minutes depending on connection speed. The script prints progress.
- **Disk space**: You need approximately 5 GB of free space for all data files.

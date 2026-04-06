# config.py — edit these before running
#
# The Intramonth Momentum Cycle
# Nathan, Suominen, and Tasa (2026)

WRDS_USERNAME = "your_wrds_username"

DATA_DIR = "data/"
OUTPUT_DIR = "output/"

# Sample period
START_DATE = "1980-01-01"
END_DATE = "2025-12-31"

# PreTOM window: trading days relative to month-end (negative = before)
PRETOM_START = -9  # t = -9
PRETOM_END = -4    # t = -4  (inclusive)

# Momentum formation: past J months, skip 1
FORMATION_MONTHS = 12
SKIP_MONTHS = 1

# Number of deciles for momentum sort
N_DECILES = 10

# T+1 reform date
T1_REFORM_DATE = "2024-05-28"

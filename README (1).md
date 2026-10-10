# NSE Stock Analysis in SQL
SQL-first analysis of six NSE stocks (Jan 2015 - Jul 2018) with a stock-market themed Streamlit dashboard.
- `stock_analysis.sql` - assignment tasks 1-13 (MySQL 8) · `stock_advanced_analysis.sql` - data quality, EDA, advanced SQL, model comparison
- `engine.py` - profile validation, finance metrics, recommender (pure Python, tested) · `app.py` - dashboard · `tests/` - pytest
- Run: `pip install -r requirements.txt && streamlit run app.py` · Test: `pytest`
- Data: put the six CSVs in `data/`. Educational use only, not investment advice.

## Deploy on Streamlit Community Cloud
1. Push this folder to a public GitHub repo (keep `data/`, `.streamlit/`, both `.sql` files, `engine.py`, `app.py`, `requirements.txt`).
2. Go to share.streamlit.io, sign in with GitHub, click **Create app**, pick the repo, branch `main`, main file `app.py`.
3. Click **Deploy**. The first build takes a few minutes; the app URL goes in your submission.

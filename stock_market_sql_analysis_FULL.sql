-- Stock Market Analysis in SQL (MySQL 8) | Prachi Sable
-- Run Appendix A loader first: tables bajaj_auto, eicher_motors, hero_motocorp, infosys, tcs, tvs_motors

-- Task 1: How much history do we have?
SELECT COUNT(*) AS trading_days, MIN(`date`) AS first_day, MAX(`date`) AS last_day FROM bajaj_auto;

-- Task 2: Eicher five best closes
SELECT `date`, close_price FROM eicher_motors ORDER BY close_price DESC LIMIT 5;

-- Task 3: TCS year by year
SELECT YEAR(`date`) AS year, ROUND(AVG(close_price), 2) AS avg_close
FROM tcs GROUP BY YEAR(`date`) ORDER BY year;

-- Task 4: Find the holes (NULL deliverable_qty)
SELECT 'bajaj_auto' AS stock, `date` FROM bajaj_auto WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'eicher_motors' AS stock, `date` FROM eicher_motors WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'hero_motocorp' AS stock, `date` FROM hero_motocorp WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'infosys' AS stock, `date` FROM infosys WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'tcs' AS stock, `date` FROM tcs WHERE deliverable_qty IS NULL
UNION ALL
SELECT 'tvs_motors' AS stock, `date` FROM tvs_motors WHERE deliverable_qty IS NULL;

-- Task 5: Moving averages (bajaj1)
DROP TABLE IF EXISTS bajaj1;
CREATE TABLE bajaj1 AS
SELECT `date`, close_price,
  CASE WHEN ROW_NUMBER() OVER (ORDER BY `date`) >= 20
       THEN ROUND(AVG(close_price) OVER (ORDER BY `date` ROWS BETWEEN 19 PRECEDING AND CURRENT ROW), 2) END AS ma20,
  CASE WHEN ROW_NUMBER() OVER (ORDER BY `date`) >= 50
       THEN ROUND(AVG(close_price) OVER (ORDER BY `date` ROWS BETWEEN 49 PRECEDING AND CURRENT ROW), 2) END AS ma50
FROM bajaj_auto;

-- Task 6: Master table
DROP TABLE IF EXISTS master_table;
CREATE TABLE master_table AS
SELECT b.`date`, b.close_price AS bajaj, t.close_price AS tcs, v.close_price AS tvs,
       i.close_price AS infosys, e.close_price AS eicher, h.close_price AS hero
FROM bajaj_auto b
JOIN tcs t           ON t.`date` = b.`date`
JOIN tvs_motors v    ON v.`date` = b.`date`
JOIN infosys i       ON i.`date` = b.`date`
JOIN eicher_motors e ON e.`date` = b.`date`
JOIN hero_motocorp h ON h.`date` = b.`date`;

-- Task 7: Golden cross signals (bajaj2)
DROP TABLE IF EXISTS bajaj2;
CREATE TABLE bajaj2 AS
WITH t AS (
  SELECT `date`, close_price, ma20, ma50,
         LAG(ma20) OVER (ORDER BY `date`) AS prev_ma20,
         LAG(ma50) OVER (ORDER BY `date`) AS prev_ma50
  FROM bajaj1
)
SELECT `date`, close_price,
  CASE WHEN ma20 IS NULL OR ma50 IS NULL OR prev_ma20 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
       WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
       WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
       ELSE 'Hold' END AS `signal`
FROM t;

-- Task 8: Signal counts
SELECT `signal`, COUNT(*) AS days FROM bajaj2 GROUP BY `signal` ORDER BY `signal`;

-- Task 9: Signal on a given day (function)
DROP FUNCTION IF EXISTS bajaj_signal;
DELIMITER $$
CREATE FUNCTION bajaj_signal(d DATE)
RETURNS VARCHAR(4) DETERMINISTIC READS SQL DATA
BEGIN
  DECLARE s VARCHAR(4);
  SELECT `signal` INTO s FROM bajaj2 WHERE `date` = d;
  RETURN s;
END $$
DELIMITER ;
SELECT bajaj_signal('2018-06-21') AS signal_on_2018_06_21;

-- Task 10: All six stocks in one query
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, `date`, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price FROM tvs_motors
),
ma AS (
  SELECT stock, `date`, close_price,
    CASE WHEN ROW_NUMBER() OVER w >= 20 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
    CASE WHEN ROW_NUMBER() OVER w >= 50 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50
  FROM prices
  WINDOW w AS (PARTITION BY stock ORDER BY `date`)
),
lagged AS (
  SELECT *, LAG(ma20) OVER (PARTITION BY stock ORDER BY `date`) AS prev_ma20,
            LAG(ma50) OVER (PARTITION BY stock ORDER BY `date`) AS prev_ma50
  FROM ma
),
sig AS (
  SELECT stock, `date`,
    CASE WHEN ma20 IS NULL OR ma50 IS NULL OR prev_ma20 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
         WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
         WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
         ELSE 'Hold' END AS `signal`
  FROM lagged
),
latest AS (
  SELECT stock, `date`, `signal`, ROW_NUMBER() OVER (PARTITION BY stock ORDER BY `date` DESC) AS rn
  FROM sig WHERE `signal` <> 'Hold'
)
SELECT s.stock,
       SUM(s.`signal` = 'Buy')  AS buys,
       SUM(s.`signal` = 'Sell') AS sells,
       MAX(l.`date`)   AS last_signal_date,
       MAX(l.`signal`) AS last_signal
FROM sig s
JOIN latest l ON l.stock = s.stock AND l.rn = 1
GROUP BY s.stock
ORDER BY s.stock;

-- Task 11: Who went up?
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, `date`, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price FROM tvs_motors
),
ends AS (SELECT stock, MIN(`date`) AS d0, MAX(`date`) AS d1 FROM prices GROUP BY stock)
SELECT e.stock, f.close_price AS first_close, l.close_price AS last_close,
       ROUND(100.0 * (l.close_price - f.close_price) / f.close_price, 1) AS pct_change
FROM ends e
JOIN prices f ON f.stock = e.stock AND f.`date` = e.d0
JOIN prices l ON l.stock = e.stock AND l.`date` = e.d1
ORDER BY pct_change DESC;

-- Task 12: The data trap (worst day per stock)
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, `date`, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price FROM tvs_motors
),
mv AS (
  SELECT stock, `date`, close_price,
         100.0 * (close_price / LAG(close_price) OVER (PARTITION BY stock ORDER BY `date`) - 1) AS pct_move
  FROM prices
),
ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY stock ORDER BY pct_move) AS rn
  FROM mv WHERE pct_move IS NOT NULL
)
SELECT stock, `date`, close_price, ROUND(pct_move, 1) AS pct_move
FROM ranked WHERE rn = 1
ORDER BY pct_move;

-- Task 13: Fix it (bonus-issue adjustment: TCS 2018-05-31, Infosys 2015-06-15, 1:1)
WITH adjusted AS (
  SELECT 'TCS' AS stock, `date`,
         CASE WHEN `date` < '2018-05-31' THEN close_price / 2 ELSE close_price END AS adj_close
  FROM tcs
  UNION ALL
  SELECT 'Infosys', `date`,
         CASE WHEN `date` < '2015-06-15' THEN close_price / 2 ELSE close_price END
  FROM infosys
)
SELECT stock,
       ROUND(100.0 * (MAX(CASE WHEN `date` = '2018-07-31' THEN adj_close END) /
                      MAX(CASE WHEN `date` = '2015-01-01' THEN adj_close END) - 1), 1) AS adjusted_pct_change
FROM adjusted
WHERE `date` BETWEEN '2015-01-01' AND '2018-07-31'
GROUP BY stock
ORDER BY stock;


-- =====================================================================
-- Stock Market Analysis in SQL (MySQL 8): ADVANCED PART  | Prachi Sable
-- Run AFTER loading the six tables (Appendix A). Needs MySQL 8.0+.
--
-- BUSINESS PROBLEM
--   A retail investor/analyst tracking six NSE stocks (Bajaj Auto, Eicher,
--   Hero, Infosys, TCS, TVS; Jan 2015 - Jul 2018) wants rule-based Buy/Sell
--   signals they can trust. Raw prices contain non-economic jumps (bonus
--   issues), so naive analysis gives wrong winners/losers and false signals.
-- OBJECTIVES
--   1. Clean and validate the data, and justify every cleaning decision.
--   2. Profile return, risk, correlation and seasonality (EDA).
--   3. Use advanced SQL (windows, CTEs, views, RSI, drawdown, rolling OLS).
--   4. Compare several signal "models" systematically on the same metrics
--      and decide which (if any) beats buy-and-hold after trading costs.
-- =====================================================================


-- ---------------------------------------------------------------
-- PART 0: DATA PREPROCESSING & QUALITY AUDIT
-- ---------------------------------------------------------------

-- 0.1 Missing values: one row per stock has NULL deliverable_qty / pct_deli_qty.
-- Decision: do NOT impute. These are exchange-reporting gaps on one day (not price data);
-- imputing delivery volume would invent data. Price analysis ignores these columns; delivery
-- analysis uses WHERE deliverable_qty IS NOT NULL. Dropping the whole row would break the
-- consecutive-day windows used for moving averages, so rows are kept.
SELECT 'Bajaj Auto' AS stock, COUNT(*) AS total_rows, SUM(deliverable_qty IS NULL) AS null_deliverable, SUM(pct_deli_qty IS NULL) AS null_pct_deli,
  SUM(open_price IS NULL OR high_price IS NULL OR low_price IS NULL OR close_price IS NULL) AS null_prices, MIN(CASE WHEN deliverable_qty IS NULL THEN `date` END) AS null_date FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, COUNT(*) AS total_rows, SUM(deliverable_qty IS NULL) AS null_deliverable, SUM(pct_deli_qty IS NULL) AS null_pct_deli,
  SUM(open_price IS NULL OR high_price IS NULL OR low_price IS NULL OR close_price IS NULL) AS null_prices, MIN(CASE WHEN deliverable_qty IS NULL THEN `date` END) AS null_date FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, COUNT(*) AS total_rows, SUM(deliverable_qty IS NULL) AS null_deliverable, SUM(pct_deli_qty IS NULL) AS null_pct_deli,
  SUM(open_price IS NULL OR high_price IS NULL OR low_price IS NULL OR close_price IS NULL) AS null_prices, MIN(CASE WHEN deliverable_qty IS NULL THEN `date` END) AS null_date FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, COUNT(*) AS total_rows, SUM(deliverable_qty IS NULL) AS null_deliverable, SUM(pct_deli_qty IS NULL) AS null_pct_deli,
  SUM(open_price IS NULL OR high_price IS NULL OR low_price IS NULL OR close_price IS NULL) AS null_prices, MIN(CASE WHEN deliverable_qty IS NULL THEN `date` END) AS null_date FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, COUNT(*) AS total_rows, SUM(deliverable_qty IS NULL) AS null_deliverable, SUM(pct_deli_qty IS NULL) AS null_pct_deli,
  SUM(open_price IS NULL OR high_price IS NULL OR low_price IS NULL OR close_price IS NULL) AS null_prices, MIN(CASE WHEN deliverable_qty IS NULL THEN `date` END) AS null_date FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, COUNT(*) AS total_rows, SUM(deliverable_qty IS NULL) AS null_deliverable, SUM(pct_deli_qty IS NULL) AS null_pct_deli,
  SUM(open_price IS NULL OR high_price IS NULL OR low_price IS NULL OR close_price IS NULL) AS null_prices, MIN(CASE WHEN deliverable_qty IS NULL THEN `date` END) AS null_date FROM tvs_motors;

-- 0.2 Integrity checks (all should be 0): duplicate dates, high<low, close outside [low, high], non-positive price/volume.
SELECT 'Bajaj Auto' AS stock, COUNT(*) - COUNT(DISTINCT `date`) AS dup_dates, SUM(high_price < low_price) AS high_lt_low,
  SUM(close_price > high_price OR close_price < low_price) AS close_out_of_range, SUM(close_price <= 0 OR no_of_shares <= 0) AS non_positive FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, COUNT(*) - COUNT(DISTINCT `date`) AS dup_dates, SUM(high_price < low_price) AS high_lt_low,
  SUM(close_price > high_price OR close_price < low_price) AS close_out_of_range, SUM(close_price <= 0 OR no_of_shares <= 0) AS non_positive FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, COUNT(*) - COUNT(DISTINCT `date`) AS dup_dates, SUM(high_price < low_price) AS high_lt_low,
  SUM(close_price > high_price OR close_price < low_price) AS close_out_of_range, SUM(close_price <= 0 OR no_of_shares <= 0) AS non_positive FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, COUNT(*) - COUNT(DISTINCT `date`) AS dup_dates, SUM(high_price < low_price) AS high_lt_low,
  SUM(close_price > high_price OR close_price < low_price) AS close_out_of_range, SUM(close_price <= 0 OR no_of_shares <= 0) AS non_positive FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, COUNT(*) - COUNT(DISTINCT `date`) AS dup_dates, SUM(high_price < low_price) AS high_lt_low,
  SUM(close_price > high_price OR close_price < low_price) AS close_out_of_range, SUM(close_price <= 0 OR no_of_shares <= 0) AS non_positive FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, COUNT(*) - COUNT(DISTINCT `date`) AS dup_dates, SUM(high_price < low_price) AS high_lt_low,
  SUM(close_price > high_price OR close_price < low_price) AS close_out_of_range, SUM(close_price <= 0 OR no_of_shares <= 0) AS non_positive FROM tvs_motors;

-- 0.3 Calendar gaps: gaps over 4 days are weekends+holidays (normal). Justifies treating rows as consecutive trading days.
WITH g AS (
  SELECT 'all' AS k, stock, `date`, DATEDIFF(`date`, LAG(`date`) OVER (PARTITION BY stock ORDER BY `date`)) AS gap
  FROM (
  SELECT 'Bajaj Auto' AS stock, `date`, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price FROM tvs_motors
  ) p
)
SELECT stock, MAX(gap) AS max_gap_days, SUM(gap > 4) AS gaps_over_4_days FROM g GROUP BY stock ORDER BY stock;

-- 0.4 Outliers: flag daily moves more than 5 standard deviations away from the stock's own mean.
-- Decision: outliers are only treated if they are NON-ECONOMIC. Two are: the TCS (2018-05-31) and Infosys (2015-06-15)
-- 1:1 bonus issues halve the price overnight with no loss for holders, so prices before those dates are divided by 2.
-- Genuine market moves (about -9% on 2015-08-24 for Bajaj/Eicher) are KEPT: they are real risk.
CREATE OR REPLACE VIEW raw_returns AS
SELECT stock, `date`, close_price, close_price / LAG(close_price) OVER (PARTITION BY stock ORDER BY `date`) - 1 AS ret
FROM (
  SELECT 'Bajaj Auto' AS stock, `date`, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price FROM tvs_motors
) p;
WITH z AS (
  SELECT stock, `date`, ret, (ret - AVG(ret) OVER (PARTITION BY stock)) / STDDEV_SAMP(ret) OVER (PARTITION BY stock) AS zscore FROM raw_returns WHERE ret IS NOT NULL
)
SELECT stock, `date`, ROUND(100 * ret, 1) AS pct_move, ROUND(zscore, 1) AS zscore FROM z WHERE ABS(zscore) > 5 ORDER BY ABS(zscore) DESC;

-- 0.5 Cleaned price view used by everything below (bonus-issue adjusted).
CREATE OR REPLACE VIEW adj_prices AS
  SELECT 'Bajaj Auto' AS stock, `date`, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, CASE WHEN `date` < '2015-06-15' THEN close_price / 2 ELSE close_price END AS close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, CASE WHEN `date` < '2018-05-31' THEN close_price / 2 ELSE close_price END AS close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price FROM tvs_motors;

CREATE OR REPLACE VIEW returns_v AS
SELECT stock, `date`, close_price,
  close_price / LAG(close_price) OVER w - 1 AS ret,
  ROW_NUMBER() OVER w AS rn
FROM adj_prices
WINDOW w AS (PARTITION BY stock ORDER BY `date`);

-- 0.6 Effect of cleaning on volatility (daily std of returns, %): TCS and Infosys should drop sharply, others unchanged.
SELECT a.stock, ROUND(100 * a.sd, 2) AS raw_daily_vol_pct, ROUND(100 * b.sd, 2) AS adjusted_daily_vol_pct
FROM (SELECT stock, STDDEV_SAMP(ret) AS sd FROM raw_returns GROUP BY stock) a
JOIN (SELECT stock, STDDEV_SAMP(ret) AS sd FROM returns_v GROUP BY stock) b ON a.stock = b.stock ORDER BY a.stock;


-- ---------------------------------------------------------------
-- PART 1: EXPLORATORY DATA ANALYSIS (on adjusted prices)
-- ---------------------------------------------------------------

-- 1.1 Price profile: level, spread and relative variability (coefficient of variation).
SELECT stock, ROUND(MIN(close_price),2) AS min_close, ROUND(AVG(close_price),2) AS avg_close, ROUND(MAX(close_price),2) AS max_close,
  ROUND(100 * STDDEV_SAMP(close_price) / AVG(close_price), 1) AS cv_pct
FROM adj_prices GROUP BY stock ORDER BY stock;

-- 1.2 Return per calendar year (%): last close of the year vs first close of the year (2018 = Jan-Jul only).
WITH y AS (
  SELECT DISTINCT stock, YEAR(`date`) AS yr,
    LAST_VALUE(close_price) OVER w / FIRST_VALUE(close_price) OVER w - 1 AS r
  FROM adj_prices
  WINDOW w AS (PARTITION BY stock, YEAR(`date`) ORDER BY `date` ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
)
SELECT stock, ROUND(100 * MAX(CASE WHEN yr = 2015 THEN r END), 1) AS y2015, ROUND(100 * MAX(CASE WHEN yr = 2016 THEN r END), 1) AS y2016, ROUND(100 * MAX(CASE WHEN yr = 2017 THEN r END), 1) AS y2017, ROUND(100 * MAX(CASE WHEN yr = 2018 THEN r END), 1) AS y2018
FROM y GROUP BY stock ORDER BY stock;

-- 1.3 Risk-return scorecard: CAGR, annualised volatility (x sqrt 252), return per unit of risk, rank.
WITH e AS (
  SELECT stock, MIN(`date`) AS d0, MAX(`date`) AS d1 FROM adj_prices GROUP BY stock
),
c AS (
  SELECT e.stock, POWER(l.close_price / f.close_price, 365.0 / DATEDIFF(e.d1, e.d0)) - 1 AS cagr
  FROM e JOIN adj_prices f ON f.stock = e.stock AND f.`date` = e.d0
  JOIN adj_prices l ON l.stock = e.stock AND l.`date` = e.d1
),
v AS (SELECT stock, STDDEV_SAMP(ret) * SQRT(252) AS vol, AVG(ret) * 100 AS avg_daily_pct, MIN(ret) AS worst, MAX(ret) AS best FROM returns_v GROUP BY stock)
SELECT c.stock, ROUND(100 * cagr, 1) AS cagr_pct, ROUND(100 * vol, 1) AS ann_vol_pct, ROUND(cagr / vol, 2) AS return_per_risk,
  ROUND(100 * worst, 1) AS worst_day_pct, ROUND(100 * best, 1) AS best_day_pct,
  RANK() OVER (ORDER BY cagr / vol DESC) AS risk_adj_rank
FROM c JOIN v ON c.stock = v.stock ORDER BY risk_adj_rank;

-- 1.4 Maximum drawdown: biggest fall from a running peak, and when the trough happened.
WITH d AS (
  SELECT stock, `date`, close_price / MAX(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS UNBOUNDED PRECEDING) - 1 AS dd FROM adj_prices
),
r AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY stock ORDER BY dd) AS rn FROM d)
SELECT stock, `date` AS trough_date, ROUND(100 * dd, 1) AS max_drawdown_pct FROM r WHERE rn = 1 ORDER BY max_drawdown_pct;

-- 1.5 Day-of-week effect: average daily return (%) by weekday (MySQL DAYOFWEEK: 2 = Monday ... 6 = Friday).
SELECT stock, ROUND(100 * AVG(CASE WHEN DAYOFWEEK(`date`) = 2 THEN ret END), 3) AS mon, ROUND(100 * AVG(CASE WHEN DAYOFWEEK(`date`) = 3 THEN ret END), 3) AS tue, ROUND(100 * AVG(CASE WHEN DAYOFWEEK(`date`) = 4 THEN ret END), 3) AS wed, ROUND(100 * AVG(CASE WHEN DAYOFWEEK(`date`) = 5 THEN ret END), 3) AS thu, ROUND(100 * AVG(CASE WHEN DAYOFWEEK(`date`) = 6 THEN ret END), 3) AS fri
FROM returns_v WHERE ret IS NOT NULL GROUP BY stock ORDER BY stock;

-- 1.6 Delivery behaviour: average % of traded shares actually delivered, by year (higher = more investor, less speculative, activity).
SELECT stock, ROUND(AVG(CASE WHEN YEAR(`date`) = 2015 THEN pct_deli_qty END), 1) AS y2015, ROUND(AVG(CASE WHEN YEAR(`date`) = 2016 THEN pct_deli_qty END), 1) AS y2016, ROUND(AVG(CASE WHEN YEAR(`date`) = 2017 THEN pct_deli_qty END), 1) AS y2017, ROUND(AVG(CASE WHEN YEAR(`date`) = 2018 THEN pct_deli_qty END), 1) AS y2018
FROM (
  SELECT 'Bajaj Auto' AS stock, `date`, pct_deli_qty FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, pct_deli_qty FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, pct_deli_qty FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, pct_deli_qty FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, pct_deli_qty FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, pct_deli_qty FROM tvs_motors
) p WHERE pct_deli_qty IS NOT NULL GROUP BY stock ORDER BY stock;

-- 1.7 Correlation of daily returns (Pearson, from sums because MySQL has no CORR). Low values = better diversification.
CREATE OR REPLACE VIEW ret_wide AS
SELECT b.`date`, b.ret AS bajaj, e.ret AS eicher, h.ret AS hero, i.ret AS infosys, t.ret AS tcs, v.ret AS tvs
FROM returns_v b
JOIN returns_v e ON e.`date` = b.`date` AND e.stock = 'Eicher Motors'
JOIN returns_v h ON h.`date` = b.`date` AND h.stock = 'Hero Motocorp'
JOIN returns_v i ON i.`date` = b.`date` AND i.stock = 'Infosys'
JOIN returns_v t ON t.`date` = b.`date` AND t.stock = 'TCS'
JOIN returns_v v ON v.`date` = b.`date` AND v.stock = 'TVS Motors'
WHERE b.stock = 'Bajaj Auto' AND b.ret IS NOT NULL;

SELECT * FROM (
  SELECT 'Bajaj Auto' AS stock_a, 'Eicher Motors' AS stock_b, ROUND((COUNT(*) * SUM(bajaj*eicher) - SUM(bajaj) * SUM(eicher)) / SQRT((COUNT(*) * SUM(bajaj*bajaj) - SUM(bajaj)*SUM(bajaj)) * (COUNT(*) * SUM(eicher*eicher) - SUM(eicher)*SUM(eicher))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Bajaj Auto' AS stock_a, 'Hero Motocorp' AS stock_b, ROUND((COUNT(*) * SUM(bajaj*hero) - SUM(bajaj) * SUM(hero)) / SQRT((COUNT(*) * SUM(bajaj*bajaj) - SUM(bajaj)*SUM(bajaj)) * (COUNT(*) * SUM(hero*hero) - SUM(hero)*SUM(hero))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Bajaj Auto' AS stock_a, 'Infosys' AS stock_b, ROUND((COUNT(*) * SUM(bajaj*infosys) - SUM(bajaj) * SUM(infosys)) / SQRT((COUNT(*) * SUM(bajaj*bajaj) - SUM(bajaj)*SUM(bajaj)) * (COUNT(*) * SUM(infosys*infosys) - SUM(infosys)*SUM(infosys))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Bajaj Auto' AS stock_a, 'TCS' AS stock_b, ROUND((COUNT(*) * SUM(bajaj*tcs) - SUM(bajaj) * SUM(tcs)) / SQRT((COUNT(*) * SUM(bajaj*bajaj) - SUM(bajaj)*SUM(bajaj)) * (COUNT(*) * SUM(tcs*tcs) - SUM(tcs)*SUM(tcs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Bajaj Auto' AS stock_a, 'TVS Motors' AS stock_b, ROUND((COUNT(*) * SUM(bajaj*tvs) - SUM(bajaj) * SUM(tvs)) / SQRT((COUNT(*) * SUM(bajaj*bajaj) - SUM(bajaj)*SUM(bajaj)) * (COUNT(*) * SUM(tvs*tvs) - SUM(tvs)*SUM(tvs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Eicher Motors' AS stock_a, 'Hero Motocorp' AS stock_b, ROUND((COUNT(*) * SUM(eicher*hero) - SUM(eicher) * SUM(hero)) / SQRT((COUNT(*) * SUM(eicher*eicher) - SUM(eicher)*SUM(eicher)) * (COUNT(*) * SUM(hero*hero) - SUM(hero)*SUM(hero))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Eicher Motors' AS stock_a, 'Infosys' AS stock_b, ROUND((COUNT(*) * SUM(eicher*infosys) - SUM(eicher) * SUM(infosys)) / SQRT((COUNT(*) * SUM(eicher*eicher) - SUM(eicher)*SUM(eicher)) * (COUNT(*) * SUM(infosys*infosys) - SUM(infosys)*SUM(infosys))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Eicher Motors' AS stock_a, 'TCS' AS stock_b, ROUND((COUNT(*) * SUM(eicher*tcs) - SUM(eicher) * SUM(tcs)) / SQRT((COUNT(*) * SUM(eicher*eicher) - SUM(eicher)*SUM(eicher)) * (COUNT(*) * SUM(tcs*tcs) - SUM(tcs)*SUM(tcs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Eicher Motors' AS stock_a, 'TVS Motors' AS stock_b, ROUND((COUNT(*) * SUM(eicher*tvs) - SUM(eicher) * SUM(tvs)) / SQRT((COUNT(*) * SUM(eicher*eicher) - SUM(eicher)*SUM(eicher)) * (COUNT(*) * SUM(tvs*tvs) - SUM(tvs)*SUM(tvs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Hero Motocorp' AS stock_a, 'Infosys' AS stock_b, ROUND((COUNT(*) * SUM(hero*infosys) - SUM(hero) * SUM(infosys)) / SQRT((COUNT(*) * SUM(hero*hero) - SUM(hero)*SUM(hero)) * (COUNT(*) * SUM(infosys*infosys) - SUM(infosys)*SUM(infosys))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Hero Motocorp' AS stock_a, 'TCS' AS stock_b, ROUND((COUNT(*) * SUM(hero*tcs) - SUM(hero) * SUM(tcs)) / SQRT((COUNT(*) * SUM(hero*hero) - SUM(hero)*SUM(hero)) * (COUNT(*) * SUM(tcs*tcs) - SUM(tcs)*SUM(tcs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Hero Motocorp' AS stock_a, 'TVS Motors' AS stock_b, ROUND((COUNT(*) * SUM(hero*tvs) - SUM(hero) * SUM(tvs)) / SQRT((COUNT(*) * SUM(hero*hero) - SUM(hero)*SUM(hero)) * (COUNT(*) * SUM(tvs*tvs) - SUM(tvs)*SUM(tvs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Infosys' AS stock_a, 'TCS' AS stock_b, ROUND((COUNT(*) * SUM(infosys*tcs) - SUM(infosys) * SUM(tcs)) / SQRT((COUNT(*) * SUM(infosys*infosys) - SUM(infosys)*SUM(infosys)) * (COUNT(*) * SUM(tcs*tcs) - SUM(tcs)*SUM(tcs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'Infosys' AS stock_a, 'TVS Motors' AS stock_b, ROUND((COUNT(*) * SUM(infosys*tvs) - SUM(infosys) * SUM(tvs)) / SQRT((COUNT(*) * SUM(infosys*infosys) - SUM(infosys)*SUM(infosys)) * (COUNT(*) * SUM(tvs*tvs) - SUM(tvs)*SUM(tvs))), 2) AS corr FROM ret_wide
  UNION ALL
  SELECT 'TCS' AS stock_a, 'TVS Motors' AS stock_b, ROUND((COUNT(*) * SUM(tcs*tvs) - SUM(tcs) * SUM(tvs)) / SQRT((COUNT(*) * SUM(tcs*tcs) - SUM(tcs)*SUM(tcs)) * (COUNT(*) * SUM(tvs*tvs) - SUM(tvs)*SUM(tvs))), 2) AS corr FROM ret_wide
) c ORDER BY corr DESC;


-- ---------------------------------------------------------------
-- PART 2: ADVANCED SQL ANALYSIS
-- ---------------------------------------------------------------

-- 2.1 RSI(14), simple-average form: 100 - 100 / (1 + avg gain / avg loss). Below 30 = oversold, above 70 = overbought.
-- Test: does buying oversold stocks beat the average 5-day forward return?
CREATE OR REPLACE VIEW rsi_v AS
WITH ch AS (
  SELECT stock, `date`, close_price, ret, rn,
    CASE WHEN ret > 0 THEN ret ELSE 0 END AS gain, CASE WHEN ret < 0 THEN -ret ELSE 0 END AS loss,
    LEAD(close_price, 5) OVER (PARTITION BY stock ORDER BY `date`) / close_price - 1 AS fwd5
  FROM returns_v
),
a AS (
  SELECT *, AVG(gain) OVER w AS ag, AVG(loss) OVER w AS al FROM ch
  WINDOW w AS (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 13 PRECEDING AND CURRENT ROW)
)
SELECT stock, `date`, fwd5, CASE WHEN rn >= 15 THEN CASE WHEN al = 0 THEN 100 ELSE 100 - 100 / (1 + ag / al) END END AS rsi FROM a;

SELECT stock, SUM(rsi < 30) AS oversold_days, SUM(rsi > 70) AS overbought_days,
  ROUND(100 * AVG(CASE WHEN rsi < 30 THEN fwd5 END), 2) AS fwd5_after_oversold_pct,
  ROUND(100 * AVG(CASE WHEN rsi > 70 THEN fwd5 END), 2) AS fwd5_after_overbought_pct,
  ROUND(100 * AVG(fwd5), 2) AS fwd5_all_days_pct
FROM rsi_v WHERE rsi IS NOT NULL AND fwd5 IS NOT NULL GROUP BY stock ORDER BY stock;

-- 2.2 Volatility regimes: 20-day rolling volatility, then today's percentile vs the stock's own history.
WITH rv AS (
  SELECT stock, `date`, STDDEV_SAMP(ret) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS vol20, rn FROM returns_v
),
p AS (
  SELECT stock, `date`, vol20, PERCENT_RANK() OVER (PARTITION BY stock ORDER BY vol20) AS pct_rank,
    ROW_NUMBER() OVER (PARTITION BY stock ORDER BY `date` DESC) AS rn_desc
  FROM rv WHERE rn >= 21
)
SELECT stock, `date`, ROUND(100 * vol20, 2) AS latest_vol20_pct, ROUND(100 * pct_rank, 0) AS percentile_vs_own_history FROM p WHERE rn_desc = 1 ORDER BY stock;

-- 2.3 Volume spikes: days when traded shares exceed 2x the prior-20-day average; what happens to the next day's price?
WITH v AS (
  SELECT stock, `date`, no_of_shares AS vol,
    AVG(no_of_shares) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) AS avg20,
    LEAD(close_price) OVER (PARTITION BY stock ORDER BY `date`) / close_price - 1 AS next_ret
  FROM (
  SELECT 'Bajaj Auto' AS stock, `date`, no_of_shares, close_price FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, no_of_shares, close_price FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, no_of_shares, close_price FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, no_of_shares, close_price FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, no_of_shares, close_price FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, no_of_shares, close_price FROM tvs_motors
  ) q
)
SELECT stock, SUM(vol > 2 * avg20) AS spike_days, ROUND(100 * AVG(CASE WHEN vol > 2 * avg20 THEN next_ret END), 2) AS next_day_after_spike_pct,
  ROUND(100 * AVG(next_ret), 2) AS next_day_all_pct
FROM v WHERE avg20 IS NOT NULL AND next_ret IS NOT NULL GROUP BY stock ORDER BY stock;


-- ---------------------------------------------------------------
-- PART 3: SYSTEMATIC MODEL COMPARISON (all in SQL)
-- ---------------------------------------------------------------

-- Each 'model' decides at the close of day t whether to be LONG (1) or in CASH (0) for day t+1.
-- Models: Buy & Hold (baseline), 1-day Momentum, MA crossovers 5/20, 10/30, 20/50 (the assignment signal), 50/200, and a
-- rolling 20-day linear-regression trend (OLS slope > 0, closed form from window sums).
-- Fair test: every model is scored on the SAME days (after day 200), with a 0.1% cost on every position change.

CREATE OR REPLACE VIEW model_pos AS
WITH f AS (
  SELECT stock, `date`, close_price, ret, rn,
    CASE WHEN rn >= 5 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) END AS m5,
    CASE WHEN rn >= 10 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) END AS m10,
    CASE WHEN rn >= 20 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS m20,
    CASE WHEN rn >= 30 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) END AS m30,
    CASE WHEN rn >= 50 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS m50,
    CASE WHEN rn >= 200 THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 199 PRECEDING AND CURRENT ROW) END AS m200,
    SUM(rn) OVER w20 AS sx, SUM(rn * rn) OVER w20 AS sxx, SUM(close_price) OVER w20 AS sy, SUM(rn * close_price) OVER w20 AS sxy
  FROM returns_v
  WINDOW w20 AS (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
)
SELECT 'Buy & Hold' AS model, stock, `date`, ret, rn, 1 AS pos FROM f
UNION ALL
SELECT 'Momentum 1d' AS model, stock, `date`, ret, rn, CASE WHEN ret > 0 THEN 1 ELSE 0 END AS pos FROM f
UNION ALL
SELECT 'MA 5/20' AS model, stock, `date`, ret, rn, CASE WHEN m5 > m20 THEN 1 ELSE 0 END AS pos FROM f
UNION ALL
SELECT 'MA 10/30' AS model, stock, `date`, ret, rn, CASE WHEN m10 > m30 THEN 1 ELSE 0 END AS pos FROM f
UNION ALL
SELECT 'MA 20/50' AS model, stock, `date`, ret, rn, CASE WHEN m20 > m50 THEN 1 ELSE 0 END AS pos FROM f
UNION ALL
SELECT 'MA 50/200' AS model, stock, `date`, ret, rn, CASE WHEN m50 > m200 THEN 1 ELSE 0 END AS pos FROM f
UNION ALL
SELECT 'OLS trend 20d' AS model, stock, `date`, ret, rn, CASE WHEN rn >= 20 AND (20 * sxy - sx * sy) / (20 * sxx - sx * sx) > 0 THEN 1 ELSE 0 END AS pos FROM f;

-- 3.1 Per-stock results on the common test window (days 201 onward).
CREATE OR REPLACE VIEW model_eval AS
WITH d AS (
  SELECT model, stock, `date`, ret, rn, LAG(pos) OVER (PARTITION BY model, stock ORDER BY `date`) AS pos_prev,
    LAG(pos, 2) OVER (PARTITION BY model, stock ORDER BY `date`) AS pos_prev2 FROM model_pos
),
t AS (
  SELECT model, stock, ret, pos_prev, CASE WHEN pos_prev <> pos_prev2 THEN 0.001 ELSE 0 END AS cost,
    pos_prev * ret - CASE WHEN pos_prev <> pos_prev2 THEN 0.001 ELSE 0 END AS net_ret
  FROM d WHERE rn > 200 AND pos_prev2 IS NOT NULL
)
SELECT model, stock, ROUND(100 * (EXP(SUM(LN(1 + net_ret))) - 1), 1) AS total_return_pct,
  ROUND(100 * AVG((pos_prev = 1 AND ret > 0) OR (pos_prev = 0 AND ret <= 0)), 1) AS direction_accuracy_pct,
  SUM(cost > 0) AS trades, ROUND(100 * AVG(pos_prev), 0) AS pct_days_invested
FROM t GROUP BY model, stock;

SELECT * FROM model_eval ORDER BY stock, total_return_pct DESC;

-- 3.2 Leaderboard across all six stocks: average return, accuracy, trading activity, and how often each model beat Buy & Hold.
WITH bh AS (SELECT stock, total_return_pct AS bh_ret FROM model_eval WHERE model = 'Buy & Hold')
SELECT m.model, ROUND(AVG(m.total_return_pct), 1) AS avg_return_pct, ROUND(AVG(m.direction_accuracy_pct), 1) AS avg_accuracy_pct,
  ROUND(AVG(m.trades), 1) AS avg_trades, SUM(m.total_return_pct > bh.bh_ret) AS stocks_beating_buy_hold,
  RANK() OVER (ORDER BY AVG(m.total_return_pct) DESC) AS rank_by_return
FROM model_eval m JOIN bh ON bh.stock = m.stock GROUP BY m.model ORDER BY rank_by_return;

-- ---------------------------------------------------------------
-- PART 4: CORPORATE-ACTION DETECTOR (finds the bonus issues automatically)
-- ---------------------------------------------------------------
-- 4.1 Unusual-day classifier: a one-day price ratio near 1/2, 1/3 ... (price divides by a whole number) is flagged as a split/bonus; every other big move is a market move. Volume vs its 20-day average is shown as supporting evidence (it roughly doubles on a 1:1 bonus).
WITH m AS (
  SELECT stock, `date`, close_price / LAG(close_price) OVER w AS price_ratio,
         no_of_shares / AVG(no_of_shares) OVER (PARTITION BY stock ORDER BY `date` ROWS BETWEEN 20 PRECEDING AND 1 PRECEDING) AS volume_vs_20d
  FROM (
  SELECT 'Bajaj Auto' AS stock, `date`, close_price, no_of_shares FROM bajaj_auto
  UNION ALL
  SELECT 'Eicher Motors' AS stock, `date`, close_price, no_of_shares FROM eicher_motors
  UNION ALL
  SELECT 'Hero Motocorp' AS stock, `date`, close_price, no_of_shares FROM hero_motocorp
  UNION ALL
  SELECT 'Infosys' AS stock, `date`, close_price, no_of_shares FROM infosys
  UNION ALL
  SELECT 'TCS' AS stock, `date`, close_price, no_of_shares FROM tcs
  UNION ALL
  SELECT 'TVS Motors' AS stock, `date`, close_price, no_of_shares FROM tvs_motors
  ) p
  WINDOW w AS (PARTITION BY stock ORDER BY `date`)
)
SELECT stock, `date`, ROUND(100 * (price_ratio - 1), 1) AS pct_move, ROUND(1 / price_ratio, 2) AS implied_factor, ROUND(volume_vs_20d, 1) AS volume_vs_20d,
  CASE WHEN price_ratio < 0.6 AND ABS(1 / price_ratio - ROUND(1 / price_ratio)) < 0.1 THEN 'Corporate action: split/bonus' ELSE 'Market move' END AS verdict
FROM m WHERE ABS(price_ratio - 1) > 0.07 ORDER BY ABS(price_ratio - 1) DESC;
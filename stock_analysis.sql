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

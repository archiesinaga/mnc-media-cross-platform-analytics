-- =====================================================================
-- MNC Media Cross-Platform Analytics
-- 02_analysis.sql : analysis queries (MySQL 8.0)
-- Tables : videos (106,303 rows), reviews (46,649 rows)
-- Run 01_create_tables.sql and load the CSVs first.
-- Tip (Workbench): put the cursor inside one query and press Ctrl+Enter
--                  to run just that query.
-- =====================================================================

USE mnc_analytics;

-- ---------------------------------------------------------------------
-- 0. Helper view: performance videos only
--    - drops live/upcoming videos (exclude_perf) and promo/corporate
--      uploads (is_promo)
--    - adds an upload time slot (WIB)
--    - adds each video's percentile rank of views_per_day within its own
--      channel x format, so a Short is compared with Shorts and a full
--      episode with full episodes (> 0.5 = better than typical)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_perf AS
SELECT v.*,
  CASE
    WHEN publish_hour BETWEEN 5 AND 10  THEN '1 Pagi 05-10'
    WHEN publish_hour BETWEEN 11 AND 14 THEN '2 Siang 11-14'
    WHEN publish_hour BETWEEN 15 AND 18 THEN '3 Sore 15-18'
    WHEN publish_hour BETWEEN 19 AND 22 THEN '4 Prime 19-22'
    ELSE '5 Malam 23-04'
  END AS slot,
  PERCENT_RANK() OVER (PARTITION BY channel_name, format
                       ORDER BY views_per_day) AS pr_in_channel_format
FROM videos v
WHERE exclude_perf = 0 AND is_promo = 0;


-- ---------------------------------------------------------------------
-- Check: row counts and total views per channel
-- Expected: videos 106,303 / reviews 46,649;
--           Indosiar 1,779,797,101 ... GTV 92,707,781 (matches Colab)
-- ---------------------------------------------------------------------
SELECT 'videos' AS tbl, COUNT(*) AS n FROM videos
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews;

SELECT channel_name, SUM(views) AS total_views
FROM videos
GROUP BY channel_name
ORDER BY total_views DESC;


-- ---------------------------------------------------------------------
-- Q1. Share of videos vs share of views per channel   [H4]
--     Window function: SUM() OVER ()
--     Finding: MNC = 62% of videos but ~25% of views
-- ---------------------------------------------------------------------
SELECT channel_group, channel_name,
       COUNT(*) AS videos,
       SUM(views) AS total_views,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_videos_pct,
       ROUND(100 * SUM(views) / SUM(SUM(views)) OVER (), 1) AS share_views_pct
FROM v_perf
GROUP BY channel_group, channel_name
ORDER BY total_views DESC;


-- ---------------------------------------------------------------------
-- Q2. Genre ranking per channel by median views per day
--     CTE + ROW_NUMBER (MySQL has no MEDIAN) + RANK
--     Only genres with >= 50 videos in that channel
-- ---------------------------------------------------------------------
WITH ranked AS (
  SELECT channel_name, content_genre, views_per_day,
         ROW_NUMBER() OVER (PARTITION BY channel_name, content_genre
                            ORDER BY views_per_day) AS rn,
         COUNT(*) OVER (PARTITION BY channel_name, content_genre) AS n
  FROM v_perf
  WHERE content_genre NOT IN ('Lainnya', 'Tidak teridentifikasi')
),
med AS (
  SELECT channel_name, content_genre,
         MAX(n) AS videos,
         AVG(views_per_day) AS median_vpd
  FROM ranked
  WHERE rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2))
  GROUP BY channel_name, content_genre
  HAVING MAX(n) >= 50
)
SELECT channel_name, content_genre, videos,
       ROUND(median_vpd, 1) AS median_vpd,
       RANK() OVER (PARTITION BY channel_name
                    ORDER BY median_vpd DESC) AS genre_rank
FROM med
ORDER BY channel_name, genre_rank;


-- ---------------------------------------------------------------------
-- Q3. Monthly uploads and month-over-month growth per group
--     LAG() with a named WINDOW
--     Note: views are lifetime views of that month's uploads, so recent
--     months look lower; Oct 2026 is partial (to 20 Oct).
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT channel_group, publish_month,
         COUNT(*) AS uploads,
         SUM(views) AS views_of_uploads
  FROM v_perf
  GROUP BY channel_group, publish_month
)
SELECT channel_group, publish_month, uploads, views_of_uploads,
       ROUND(100 * (uploads - LAG(uploads) OVER w)
             / LAG(uploads) OVER w, 1) AS uploads_mom_pct,
       ROUND(100 * (views_of_uploads - LAG(views_of_uploads) OVER w)
             / LAG(views_of_uploads) OVER w, 1) AS views_mom_pct
FROM monthly
WINDOW w AS (PARTITION BY channel_group ORDER BY publish_month)
ORDER BY channel_group, publish_month;


-- ---------------------------------------------------------------------
-- Q4a. Best upload day (format-adjusted)
--      pct_above_typical = % of videos beating their channel x format
--      median. 50% = typical.
--      Finding: MNC weekend uploads beat typical, yet MNC posts about
--      half as many videos on weekend days.
-- ---------------------------------------------------------------------
SELECT channel_group, dow_num, day_of_week,
       COUNT(*) AS videos,
       ROUND(100 * AVG(pr_in_channel_format > 0.5), 1) AS pct_above_typical
FROM v_perf
GROUP BY channel_group, dow_num, day_of_week
ORDER BY channel_group, dow_num;

-- Q4b. Best upload time slot (format-adjusted), CASE slots from v_perf
SELECT channel_group, slot,
       COUNT(*) AS videos,
       ROUND(100 * AVG(pr_in_channel_format > 0.5), 1) AS pct_above_typical
FROM v_perf
GROUP BY channel_group, slot
ORDER BY channel_group, slot;


-- ---------------------------------------------------------------------
-- Q5. Rating by app version (spike days excluded)
--     HAVING keeps versions with >= 50 reviews
--     If app_version_major gives only 1-3 rows per app, replace it with
--     app_version in the three places below.
-- ---------------------------------------------------------------------
SELECT app, app_version_major,
       COUNT(*) AS reviews,
       ROUND(AVG(score), 2) AS avg_score,
       ROUND(100 * AVG(score <= 2), 1) AS pct_negative,
       MIN(review_date) AS first_seen,
       MAX(review_date) AS last_seen
FROM reviews
WHERE app_version_major IS NOT NULL
  AND is_spike_day = 0
GROUP BY app, app_version_major
HAVING COUNT(*) >= 50
ORDER BY app, first_seen;


-- ---------------------------------------------------------------------
-- Q6. Complaint mix per month, negative reviews (1-2 stars), Jan 2025+
--     SUM(CASE ...) / COUNT(*)  [H1, H3]
-- ---------------------------------------------------------------------
SELECT app, review_month,
  COUNT(*) AS negative_reviews,
  ROUND(100 * SUM(CASE WHEN complaint_topic = 'akses_setelah_bayar'
                  THEN 1 ELSE 0 END) / COUNT(*), 1) AS akses_pct,
  ROUND(100 * SUM(CASE WHEN complaint_topic = 'pembayaran'
                  THEN 1 ELSE 0 END) / COUNT(*), 1) AS pembayaran_pct,
  ROUND(100 * SUM(CASE WHEN complaint_topic = 'paywall_harga'
                  THEN 1 ELSE 0 END) / COUNT(*), 1) AS paywall_pct,
  ROUND(100 * SUM(CASE WHEN complaint_topic = 'iklan'
                  THEN 1 ELSE 0 END) / COUNT(*), 1) AS iklan_pct,
  ROUND(100 * SUM(CASE WHEN complaint_topic IN
                  ('error_crash', 'lag_buffering', 'gagal_putar')
                  THEN 1 ELSE 0 END) / COUNT(*), 1) AS teknis_pct,
  ROUND(100 * SUM(CASE WHEN complaint_topic = 'login_akun'
                  THEN 1 ELSE 0 END) / COUNT(*), 1) AS login_pct
FROM reviews
WHERE score <= 2 AND review_dt >= '2025-01-01'
GROUP BY app, review_month
ORDER BY app, review_month;


-- ---------------------------------------------------------------------
-- H6. Developer reply behaviour on negative reviews (no spike days)
--     Finding: RCTI+ replies to ~44% within a median of ~42 hours;
--     Vision+ replies to ~99% within ~0.7 hours.
--     Reply-time medians are computed in Colab (05_eda.ipynb).
-- ---------------------------------------------------------------------
SELECT app,
       COUNT(*) AS negative_reviews,
       ROUND(100 * AVG(replied), 1) AS reply_rate_pct,
       ROUND(100 * SUM(reply_is_template) / NULLIF(SUM(replied), 0), 1)
         AS template_share_of_replies_pct
FROM reviews
WHERE score <= 2
  AND is_spike_day = 0
  AND review_dt >= '2025-01-01'
GROUP BY app;

-- =====================================================================
-- MNC Media Cross-Platform Analytics
-- 03_looker_tables.sql : summary tables for the Looker Studio dashboard
-- Run after 02_analysis.sql (needs the v_perf view).
--
-- Design rule: every table stores COUNTS and SUMS only, never averages or
-- medians, so Looker Studio can re-aggregate them correctly at any level
-- (per channel, per group, per month, filtered...).
--   views per video       = total_views / uploads
--   engagement rate       = (total_likes + total_comments) / total_views
--   % above typical       = above_typical / uploads      (50% = typical)
--   average rating        = score_sum / reviews
--   reply rate (negative) = n_negative_replied / n_negative
-- =====================================================================

USE mnc_analytics;

-- 1. YouTube: channel x month x format  (dashboard page 1)
DROP TABLE IF EXISTS agg_channel_monthly;
CREATE TABLE agg_channel_monthly AS
SELECT channel_group, channel_name, publish_month, format,
       COUNT(*)                          AS uploads,
       SUM(views)                        AS total_views,
       SUM(likes)                        AS total_likes,
       SUM(COALESCE(comments, 0))        AS total_comments,
       SUM(pr_in_channel_format > 0.5)   AS above_typical
FROM v_perf
GROUP BY channel_group, channel_name, publish_month, format;

-- 2. YouTube: channel x genre x format  (dashboard page 2)
--    Lainnya / Tidak teridentifikasi are kept so totals reconcile;
--    filter them out in Looker for genre charts.
DROP TABLE IF EXISTS agg_genre;
CREATE TABLE agg_genre AS
SELECT channel_group, channel_name, content_genre, format,
       COUNT(*)                          AS uploads,
       SUM(views)                        AS total_views,
       SUM(pr_in_channel_format > 0.5)   AS above_typical
FROM v_perf
GROUP BY channel_group, channel_name, content_genre, format;

-- 3. YouTube: channel x format x day x hour  (dashboard page 3)
DROP TABLE IF EXISTS agg_upload_time;
CREATE TABLE agg_upload_time AS
SELECT channel_group, channel_name, format,
       dow_num, day_of_week, publish_hour, slot,
       COUNT(*)                          AS uploads,
       SUM(views)                        AS total_views,
       SUM(pr_in_channel_format > 0.5)   AS above_typical
FROM v_perf
GROUP BY channel_group, channel_name, format,
         dow_num, day_of_week, publish_hour, slot;

-- 4. Apps: app x month x spike-day flag  (dashboard page 4)
DROP TABLE IF EXISTS agg_app_monthly;
CREATE TABLE agg_app_monthly AS
SELECT app, review_month, is_spike_day,
       COUNT(*)                              AS reviews,
       SUM(score)                            AS score_sum,
       SUM(score = 1)                        AS n_1star,
       SUM(score <= 2)                       AS n_negative,
       SUM(score >= 4)                       AS n_positive,
       SUM(replied)                          AS n_replied,
       SUM(score <= 2 AND replied = 1)       AS n_negative_replied,
       SUM(reply_is_template)                AS n_template_replies
FROM reviews
GROUP BY app, review_month, is_spike_day;

-- 5. Apps: complaint topics, negative reviews only  (dashboard page 5)
DROP TABLE IF EXISTS agg_complaint_monthly;
CREATE TABLE agg_complaint_monthly AS
SELECT app, review_month, is_spike_day, mentions_sport, complaint_topic,
       COUNT(*) AS negative_reviews
FROM reviews
WHERE score <= 2
GROUP BY app, review_month, is_spike_day, mentions_sport, complaint_topic;


-- ---------------------------------------------------------------------
-- Checks: totals must match the source tables
-- Expected: 105,447 performance videos in tables 1-3;
--           46,649 reviews in table 4; table 5 = number of 1-2 star reviews
-- ---------------------------------------------------------------------
SELECT 'agg_channel_monthly' AS tbl, COUNT(*) AS table_rows,
       SUM(uploads) AS total FROM agg_channel_monthly
UNION ALL
SELECT 'agg_genre', COUNT(*), SUM(uploads) FROM agg_genre
UNION ALL
SELECT 'agg_upload_time', COUNT(*), SUM(uploads) FROM agg_upload_time
UNION ALL
SELECT 'agg_app_monthly', COUNT(*), SUM(reviews) FROM agg_app_monthly
UNION ALL
SELECT 'agg_complaint_monthly', COUNT(*), SUM(negative_reviews)
FROM agg_complaint_monthly
UNION ALL
SELECT 'reviews 1-2 stars (source)', NULL, COUNT(*)
FROM reviews WHERE score <= 2;


-- ---------------------------------------------------------------------
-- Export: run each SELECT below, then in the result grid click
-- "Export recordset to an external file" and save as CSV in C:\mnc\looker\
-- IMPORTANT: set the "Limit to 1000 rows" dropdown to "Don't Limit" first,
-- or larger tables will be cut off at 1,000 rows.
-- ---------------------------------------------------------------------
SELECT * FROM agg_channel_monthly;
SELECT * FROM agg_genre;
SELECT * FROM agg_upload_time;
SELECT * FROM agg_app_monthly;
SELECT * FROM agg_complaint_monthly;

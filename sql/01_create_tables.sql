-- =====================================================================
-- MNC Media Cross-Platform Analytics
-- 01_create_tables.sql : database, tables and CSV load (MySQL 8.0)
-- Tables : videos (106,303 rows), reviews (46,649 rows)
-- Source : sql_videos.csv, sql_reviews.csv (NULL is written as \N)
-- Next   : run 02_analysis.sql, then 03_looker_tables.sql
-- =====================================================================

CREATE DATABASE IF NOT EXISTS mnc_analytics
  DEFAULT CHARACTER SET utf8mb4;
USE mnc_analytics;

-- ---------------------------------------------------------------------
-- 1. videos : one row per YouTube video (8 TV channels)
--    exclude_perf = live/upcoming videos, is_promo = promo/corporate
--    uploads; both are filtered out in the v_perf view (02_analysis.sql)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS videos;
CREATE TABLE videos (
  video_id        VARCHAR(11)   NOT NULL,
  channel_name    VARCHAR(20)   NOT NULL,
  channel_group   VARCHAR(10)   NOT NULL,   -- MNC / Kompetitor
  format          VARCHAR(20)   NOT NULL,   -- Full, Clip, Shorts, Live/Streaming, Upcoming
  content_genre   VARCHAR(30)   NOT NULL,
  published_wib   DATETIME      NOT NULL,   -- upload time in WIB
  publish_date    DATE          NOT NULL,
  publish_month   CHAR(7)       NOT NULL,   -- 'YYYY-MM'
  dow_num         TINYINT       NOT NULL,   -- 0 = Monday ... 6 = Sunday
  day_of_week     VARCHAR(10)   NOT NULL,
  publish_hour    TINYINT       NOT NULL,   -- 0-23
  duration_sec    INT           NULL,
  views           BIGINT        NOT NULL,
  likes           BIGINT        NOT NULL,
  comments        BIGINT        NULL,
  engagement_rate DOUBLE        NULL,
  views_per_day   DOUBLE        NOT NULL,
  exclude_perf    TINYINT(1)    NOT NULL,
  is_promo        TINYINT(1)    NOT NULL,
  is_outlier      TINYINT(1)    NOT NULL,
  PRIMARY KEY (video_id),
  KEY idx_videos_channel (channel_name, format),
  KEY idx_videos_month (publish_month)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- ---------------------------------------------------------------------
-- 2. reviews : one row per Google Play review (RCTIplus, Visionplus, Vidio)
--    Review text is NOT stored here (kept out of the repo on purpose).
--    app_version_major is text on purpose: '1.10' and '1.1' are different.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS reviews;
CREATE TABLE reviews (
  review_id              CHAR(36)     NOT NULL,
  app                    VARCHAR(12)  NOT NULL,
  score                  TINYINT      NOT NULL,   -- 1-5 stars
  review_dt              DATETIME     NOT NULL,
  review_date            DATE         NOT NULL,
  review_month           CHAR(7)      NOT NULL,   -- 'YYYY-MM'
  replied                TINYINT(1)   NOT NULL,
  reply_hours            DOUBLE       NULL,       -- NULL when no reply
  reply_is_template      TINYINT(1)   NOT NULL,
  reply_time_invalid     TINYINT(1)   NOT NULL,
  app_version            VARCHAR(40)  NULL,
  app_version_major      VARCHAR(10)  NULL,
  is_spike_day           TINYINT(1)   NOT NULL,
  spike_event_id         VARCHAR(20)  NULL,
  sentiment              VARCHAR(10)  NOT NULL,   -- Positif / Netral / Negatif
  complaint_topic        VARCHAR(25)  NOT NULL,
  mentions_sport         TINYINT(1)   NOT NULL,
  is_akses_setelah_bayar TINYINT(1)   NOT NULL,
  is_pembayaran          TINYINT(1)   NOT NULL,
  is_paywall_harga       TINYINT(1)   NOT NULL,
  is_login_akun          TINYINT(1)   NOT NULL,
  is_iklan               TINYINT(1)   NOT NULL,
  is_konten              TINYINT(1)   NOT NULL,
  is_error_crash         TINYINT(1)   NOT NULL,
  is_lag_buffering       TINYINT(1)   NOT NULL,
  is_gagal_putar         TINYINT(1)   NOT NULL,
  is_tv_device           TINYINT(1)   NOT NULL,
  PRIMARY KEY (review_id),
  KEY idx_reviews_app_month (app, review_month),
  KEY idx_reviews_score (score)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- ---------------------------------------------------------------------
-- 3. Load the CSVs
--    Option A (Workbench): right-click the table > "Table Data Import
--    Wizard" > pick the CSV. Use this if option B is blocked.
--    Option B (SQL): needs local_infile enabled on server and client.
--      SET GLOBAL local_infile = 1;
--      Workbench connection > Advanced > Others:
--        OPT_LOCAL_INFILE=1
--    Change the paths if your CSVs are somewhere else.
-- ---------------------------------------------------------------------
LOAD DATA LOCAL INFILE 'C:/mnc/sql_videos.csv'
INTO TABLE videos
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'C:/mnc/sql_reviews.csv'
INTO TABLE reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- Check: row counts must match the source files
-- Expected: videos 106,303 / reviews 46,649
-- ---------------------------------------------------------------------
SELECT 'videos' AS tbl, COUNT(*) AS n FROM videos
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews;

-- DUA Edu: Core KPI, funnel, channel, activation-retention, cohort, segmentation
-- Run AFTER 02_user_metrics.sql. All percentage-like ratios in core script 0..1.

USE [DUA_Edu_Challenge];
SET NOCOUNT ON;

-- 1. KPI tổng quan
SELECT
    COUNT(*) AS registrations,
    SUM(eligible_activation) AS activation_eligible,
    SUM(activated_7d) AS activations,
    1.0 * SUM(activated_7d) / NULLIF(SUM(eligible_activation), 0) AS activation_rate,
    SUM(eligible_d7) AS d7_eligible,
    SUM(retained_d7) AS returned_d7,
    1.0 * SUM(retained_d7) / NULLIF(SUM(eligible_d7), 0) AS d7_retention,
    1.0 * SUM(reached_start) / NULLIF(SUM(reached_view), 0) AS view_to_start_rate,
    1.0 * SUM(reached_complete) / NULLIF(SUM(reached_start), 0) AS start_to_complete_rate
FROM dbo.vw_user_metrics;

-- 2. Funnel D0–D6 và tỷ lệ chuyển từng bước
WITH totals AS (
    SELECT
        SUM(reached_signup) AS signups,
        SUM(reached_login) AS logins,
        SUM(reached_view) AS views,
        SUM(reached_start) AS starts,
        SUM(reached_complete) AS completions
    FROM dbo.vw_user_metrics
),
funnel AS (
    SELECT
        step_no,
        event_name,
        user_count,
        LAG(user_count) OVER (ORDER BY step_no) AS previous_count
    FROM totals
    CROSS APPLY (VALUES
        (1, 'sign_up', signups),
        (2, 'log_in', logins),
        (3, 'view_content', views),
        (4, 'start_lesson', starts),
        (5, 'complete_lesson', completions)
    ) AS stages(step_no, event_name, user_count)
)
SELECT
    step_no,
    event_name,
    user_count,
    previous_count - user_count AS users_lost,
    1.0 * user_count / NULLIF(previous_count, 0) AS step_conversion
FROM funnel
ORDER BY step_no;

-- 3. Activation và D7 theo nguồn đăng ký
SELECT
    acquisition_channel,
    COUNT(*) AS registrations,
    SUM(reached_login) AS logins,
    1.0 * SUM(reached_login) / NULLIF(SUM(reached_signup), 0) AS signup_to_login_rate,
    SUM(eligible_activation) AS activation_eligible,
    SUM(activated_7d) AS activations,
    1.0 * SUM(activated_7d) / NULLIF(SUM(eligible_activation), 0) AS activation_rate,
    SUM(eligible_d7) AS d7_eligible,
    SUM(retained_d7) AS returned_d7,
    1.0 * SUM(retained_d7) / NULLIF(SUM(eligible_d7), 0) AS d7_retention
FROM dbo.vw_user_metrics
GROUP BY acquisition_channel
ORDER BY activation_rate DESC;

-- 4. D7 giữa nhóm đã và chưa Activation, chỉ tính người đủ độ phủ
SELECT
    activated_7d,
    COUNT(*) AS users,
    SUM(retained_d7) AS returned_d7,
    1.0 * SUM(retained_d7) / COUNT(*) AS d7_retention
FROM dbo.vw_user_metrics
WHERE eligible_d7 = 1
  AND activated_7d IS NOT NULL
GROUP BY activated_7d
ORDER BY activated_7d DESC;

-- 5. Hoạt động D1–D7 theo tuần đăng ký, bắt đầu thứ Hai
SELECT
    cohort_week,
    COUNT(*) AS registrations,
    AVG(1.0 * active_d1) AS d1,
    AVG(1.0 * active_d2) AS d2,
    AVG(1.0 * active_d3) AS d3,
    AVG(1.0 * active_d4) AS d4,
    AVG(1.0 * active_d5) AS d5,
    AVG(1.0 * active_d6) AS d6,
    AVG(1.0 * retained_d7) AS d7
FROM dbo.vw_user_metrics
GROUP BY cohort_week
ORDER BY cohort_week;

-- Segmentation (Source: SQLQuery1.sql)
USE DUA_Edu_Challenge;
GO

SELECT
    s.segment_type,
    s.segment_value,

    COUNT(*) AS total_users,

    SUM(m.activated_7d) AS activated_users,

    ROUND(
        100.0 * SUM(m.activated_7d) /
        NULLIF(SUM(m.eligible_activation), 0),
        2
    ) AS activation_rate_pct,

    SUM(m.retained_d7) AS retained_users,

    ROUND(
        100.0 * SUM(m.retained_d7) /
        NULLIF(SUM(m.eligible_d7), 0),
        2
    ) AS d7_retention_pct

FROM dbo.vw_user_metrics AS m

CROSS APPLY (
    VALUES
        (N'Channel', m.acquisition_channel),
        (N'Device', m.device_type),
        (N'Experience', m.experience_level),
        (N'Learning Goal', m.learning_goal)
) AS s(segment_type, segment_value)

GROUP BY
    s.segment_type,
    s.segment_value

ORDER BY
    s.segment_type,
    total_users DESC;

-- Cohort summary (Source: SQLQuery6.sql)
USE DUA_Edu_Challenge;
GO

SELECT
    cohort_week,

    COUNT(*) AS total_users,

    SUM(activated_7d) AS activated_users,

    CAST(
        100.0 * SUM(activated_7d)
        / NULLIF(SUM(eligible_activation), 0)
        AS DECIMAL(6,2)
    ) AS activation_rate_pct,

    SUM(retained_d7) AS retained_users,

    CAST(
        100.0 * SUM(retained_d7)
        / NULLIF(SUM(eligible_d7), 0)
        AS DECIMAL(6,2)
    ) AS d7_retention_pct,

    CAST(
        100.0 * SUM(active_d1)
        / NULLIF(COUNT(active_d1), 0)
        AS DECIMAL(6,2)
    ) AS d1_retention_pct,

    CAST(
        100.0 * SUM(active_d3)
        / NULLIF(COUNT(active_d3), 0)
        AS DECIMAL(6,2)
    ) AS d3_retention_pct

FROM dbo.vw_user_metrics

GROUP BY cohort_week

ORDER BY cohort_week;

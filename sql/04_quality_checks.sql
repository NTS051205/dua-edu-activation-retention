/*
 DUA Edu Challenge — SQL validation (READ ONLY).
 Data scope: synthetic cohort in October 2026; events observed through 2026-11-10.
 Run after importing four tables and creating all three views.
*/
USE [DUA_Edu_Challenge];
GO

-- 1. Table sizes and registered user set.
SELECT N'Users' AS table_name, COUNT(*) AS row_count FROM dbo.Users
UNION ALL SELECT N'Events', COUNT(*) FROM dbo.Events
UNION ALL SELECT N'Content', COUNT(*) FROM dbo.Content
UNION ALL SELECT N'Campaigns', COUNT(*) FROM dbo.Campaigns;

-- 2. Duplicate PKs (should return 0; primary keys also enforce this).
SELECT 'Users' AS table_name, COUNT(*) - COUNT(DISTINCT user_id) AS duplicates FROM dbo.Users
UNION ALL SELECT 'Events', COUNT(*) - COUNT(DISTINCT event_id) FROM dbo.Events
UNION ALL SELECT 'Content', COUNT(*) - COUNT(DISTINCT content_id) FROM dbo.Content
UNION ALL SELECT 'Campaigns', COUNT(*) - COUNT(DISTINCT campaign_id) FROM dbo.Campaigns;

-- 3. Invalid foreign keys and impossible ordering (all should return 0).
SELECT
    SUM(CASE WHEN u.user_id IS NULL THEN 1 ELSE 0 END) AS unknown_user_events,
    SUM(CASE WHEN e.content_id IS NOT NULL AND c.content_id IS NULL THEN 1 ELSE 0 END) AS unknown_content_events,
    SUM(CASE WHEN e.campaign_id IS NOT NULL AND ca.campaign_id IS NULL THEN 1 ELSE 0 END) AS unknown_campaign_events,
    SUM(CASE WHEN e.occurred_at < u.registered_at THEN 1 ELSE 0 END) AS events_before_registration
FROM dbo.Events AS e
LEFT JOIN dbo.Users AS u ON u.user_id = e.user_id
LEFT JOIN dbo.Content AS c ON c.content_id = e.content_id
LEFT JOIN dbo.Campaigns AS ca ON ca.campaign_id = e.campaign_id;

-- 4. Key KPI reconciliation (reference values for THIS dataset only).
SELECT COUNT(*) AS registrations,
       SUM(eligible_activation) AS activation_eligible,
       SUM(activated_7d) AS activated_users,
       SUM(eligible_d7) AS retention_eligible,
       SUM(retained_d7) AS d7_retained_users,
       SUM(reached_signup) AS funnel_signup,
       SUM(reached_login) AS funnel_login,
       SUM(reached_view) AS funnel_view,
       SUM(reached_start) AS funnel_start,
       SUM(reached_complete) AS funnel_complete
FROM dbo.vw_user_metrics;

-- 5. Every funnel stage must be <= preceding stage at user level (expect 0).
SELECT COUNT(*) AS invalid_funnel_user_rows
FROM dbo.vw_user_metrics
WHERE reached_signup < reached_login
   OR reached_login < reached_view
   OR reached_view < reached_start
   OR reached_start < reached_complete;

-- 6. Check 1-row-per-user and source coverage.
SELECT
    (SELECT COUNT(*) FROM dbo.vw_user_metrics) AS metric_rows,
    (SELECT COUNT(DISTINCT user_id) FROM dbo.vw_user_metrics) AS metric_unique_users,
    (SELECT covered_through FROM dbo.DatasetCoverage WHERE dataset_id = 1) AS covered_through;

-- 7. Content / campaign view results (sequential content funnel; D0-D6 join).
SELECT content_id, content_title, viewers, starters, completers,
       view_to_start_pct, start_to_complete_pct
FROM dbo.vw_content_funnel ORDER BY content_id;

SELECT campaign_id, campaign_name, participants, retained_users, d7_retention_pct
FROM dbo.vw_campaign_retention ORDER BY campaign_id;
GO

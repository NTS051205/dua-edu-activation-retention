/*
DUA Edu – Optional analytical views for advanced Power BI content/campaign charts.
Source: original dbo.Users, dbo.Events, dbo.Content, dbo.Campaigns and dbo.DatasetCoverage.
No table is modified. Run after the underlying tables and dbo.vw_user_metrics exist.
*/
USE DUA_Edu_Challenge;
GO

CREATE OR ALTER VIEW dbo.vw_content_funnel AS
WITH events_in_window AS (
    SELECT e.user_id, e.content_id, e.event_name, e.occurred_at
    FROM dbo.Events AS e
    INNER JOIN dbo.Users AS u ON u.user_id = e.user_id
    CROSS JOIN dbo.DatasetCoverage AS d
    WHERE e.content_id IS NOT NULL
      AND DATEDIFF(DAY, CAST(u.registered_at AS DATE), d.covered_through) >= 6
      AND e.occurred_at >= u.registered_at
      AND e.occurred_at < DATEADD(DAY, 7, CAST(u.registered_at AS DATE))
      AND e.occurred_at < DATEADD(DAY, 1, d.covered_through)
),
first_views AS (
    SELECT user_id, content_id, MIN(occurred_at) AS viewed_at
    FROM events_in_window
    WHERE event_name = 'view_content'
    GROUP BY user_id, content_id
),
steps AS (
    SELECT v.user_id, v.content_id, s.started_at, c.completed_at
    FROM first_views AS v
    OUTER APPLY (
       SELECT MIN(e.occurred_at) AS started_at
       FROM events_in_window AS e
       WHERE e.user_id=v.user_id AND e.content_id=v.content_id
         AND e.event_name='start_lesson' AND e.occurred_at>v.viewed_at
    ) AS s
    OUTER APPLY (
       SELECT MIN(e.occurred_at) AS completed_at
       FROM events_in_window AS e
       WHERE e.user_id=v.user_id AND e.content_id=v.content_id
         AND e.event_name='complete_lesson' AND e.occurred_at>s.started_at
    ) AS c
)
SELECT
    c.content_id, c.content_title, c.topic, c.[level],
    COUNT(s.user_id) AS viewers,
    COUNT(s.started_at) AS starters,
    COUNT(s.completed_at) AS completers,
    CAST(100.0 * COUNT(s.started_at)/NULLIF(COUNT(s.user_id),0) AS DECIMAL(6,2)) AS view_to_start_pct,
    CAST(100.0 * COUNT(s.completed_at)/NULLIF(COUNT(s.started_at),0) AS DECIMAL(6,2)) AS start_to_complete_pct
FROM dbo.Content AS c
LEFT JOIN steps AS s ON s.content_id=c.content_id
GROUP BY c.content_id,c.content_title,c.topic,c.[level];
GO

CREATE OR ALTER VIEW dbo.vw_campaign_retention AS
WITH participation AS (
    SELECT DISTINCT e.user_id, e.campaign_id
    FROM dbo.Events AS e
    INNER JOIN dbo.Users AS u ON u.user_id=e.user_id
    INNER JOIN dbo.vw_user_metrics AS m ON m.user_id=e.user_id
    CROSS JOIN dbo.DatasetCoverage AS d
    WHERE e.event_name='join_campaign'
      AND e.campaign_id IS NOT NULL
      AND m.eligible_d7=1
      AND e.occurred_at >= u.registered_at
      AND e.occurred_at < DATEADD(DAY,7,CAST(u.registered_at AS DATE))
      AND e.occurred_at < DATEADD(DAY,1,d.covered_through)
),
participants AS (
    SELECT p.user_id,p.campaign_id,m.retained_d7
    FROM participation AS p
    INNER JOIN dbo.vw_user_metrics AS m ON m.user_id=p.user_id
)
SELECT c.campaign_id,c.campaign_name,c.campaign_type,
       COUNT(p.user_id) AS participants,
       SUM(COALESCE(p.retained_d7,0)) AS retained_users,
       CAST(100.0*SUM(COALESCE(p.retained_d7,0))/NULLIF(COUNT(p.user_id),0) AS DECIMAL(6,2)) AS d7_retention_pct
FROM dbo.Campaigns AS c
LEFT JOIN participants AS p ON c.campaign_id=p.campaign_id
GROUP BY c.campaign_id,c.campaign_name,c.campaign_type;
GO

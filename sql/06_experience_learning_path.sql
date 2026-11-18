-- DUA Edu: exploratory SQL to test the basic-lesson skipping hypothesis.
-- Results describe observed behavior; they do NOT prove motivations.

USE DUA_Edu_Challenge;
GO

WITH lesson_events AS (
    SELECT
        u.user_id,
        u.experience_level,
        e.content_id,
        e.event_name,
        e.occurred_at
    FROM dbo.Users u
    JOIN dbo.Events e
        ON u.user_id = e.user_id
    CROSS JOIN dbo.DatasetCoverage dc
    WHERE e.content_id IN ('C001', 'C002')
      AND DATEDIFF(
          DAY, CAST(u.registered_at AS DATE),
          dc.covered_through
      ) >= 6
      AND e.occurred_at >= u.registered_at
      AND e.occurred_at < DATEADD(
          DAY, 7, CAST(u.registered_at AS DATE)
      )
),

first_views AS (
    SELECT
        user_id,
        experience_level,
        content_id,
        MIN(occurred_at) AS viewed_at
    FROM lesson_events
    WHERE event_name = 'view_content'
    GROUP BY
        user_id, experience_level, content_id
),

lesson_steps AS (
    SELECT
        v.user_id,
        v.experience_level,
        v.content_id,
        s.started_at,
        cm.completed_at
    FROM first_views v

    OUTER APPLY (
        SELECT MIN(e.occurred_at) AS started_at
        FROM lesson_events e
        WHERE e.user_id = v.user_id
          AND e.content_id = v.content_id
          AND e.event_name = 'start_lesson'
          AND e.occurred_at > v.viewed_at
    ) s

    OUTER APPLY (
        SELECT MIN(e.occurred_at) AS completed_at
        FROM lesson_events e
        WHERE e.user_id = v.user_id
          AND e.content_id = v.content_id
          AND e.event_name = 'complete_lesson'
          AND e.occurred_at > s.started_at
    ) cm
)

SELECT
    c.content_title,
    ls.experience_level,

    COUNT(*) AS viewers,
    COUNT(ls.started_at) AS starters,
    COUNT(ls.completed_at) AS completers,

    CAST(
        100.0 * COUNT(ls.started_at)
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(5,2)
    ) AS view_to_start_pct,

    CAST(
        100.0 * COUNT(ls.completed_at)
        / NULLIF(COUNT(ls.started_at), 0)
        AS DECIMAL(5,2)
    ) AS start_to_complete_pct

FROM lesson_steps ls
JOIN dbo.Content c
    ON ls.content_id = c.content_id

GROUP BY
    c.content_title,
    ls.experience_level

ORDER BY
    c.content_title,
    ls.experience_level;
GO

USE DUA_Edu_Challenge;
GO

WITH basic_views AS (
    SELECT
        u.user_id,
        u.experience_level,
        e.content_id,
        MIN(e.occurred_at) AS first_view_at,
        CAST(u.registered_at AS DATE) AS signup_date
    FROM dbo.Users u
    JOIN dbo.Events e
        ON u.user_id = e.user_id
    CROSS JOIN dbo.DatasetCoverage dc
    WHERE e.event_name = 'view_content'
      AND e.content_id IN ('C001', 'C002')
      AND DATEDIFF(
          DAY, CAST(u.registered_at AS DATE),
          dc.covered_through
      ) >= 6
      AND e.occurred_at >= u.registered_at
      AND e.occurred_at < DATEADD(
          DAY, 7, CAST(u.registered_at AS DATE)
      )
    GROUP BY
        u.user_id,
        u.experience_level,
        e.content_id,
        CAST(u.registered_at AS DATE)
),

learning_path AS (
    SELECT
        b.user_id,
        b.experience_level,
        b.content_id,
        basic_start.started_at,
        advanced_start.started_at AS advanced_at

    FROM basic_views b

    OUTER APPLY (
        SELECT MIN(e.occurred_at) AS started_at
        FROM dbo.Events e
        WHERE e.user_id = b.user_id
          AND e.content_id = b.content_id
          AND e.event_name = 'start_lesson'
          AND e.occurred_at > b.first_view_at
          AND e.occurred_at <
              DATEADD(DAY, 7, b.signup_date)
    ) basic_start

    OUTER APPLY (
        SELECT MIN(e.occurred_at) AS started_at
        FROM dbo.Events e
        WHERE e.user_id = b.user_id
          AND e.content_id IN ('C003', 'C004')
          AND e.event_name = 'start_lesson'
          AND e.occurred_at > b.first_view_at
          AND e.occurred_at <
              DATEADD(DAY, 7, b.signup_date)
    ) advanced_start
)

SELECT
    experience_level,
    content_id,

    COUNT(*) AS viewers,

    SUM(CASE
        WHEN started_at IS NULL THEN 1
        ELSE 0
    END) AS did_not_start_basic,

    SUM(CASE
        WHEN started_at IS NULL
         AND advanced_at IS NOT NULL
        THEN 1 ELSE 0
    END) AS moved_to_advanced,

    CAST(
        100.0 * SUM(CASE
            WHEN started_at IS NULL
             AND advanced_at IS NOT NULL
            THEN 1 ELSE 0
        END)
        / NULLIF(SUM(CASE
            WHEN started_at IS NULL THEN 1
            ELSE 0
        END), 0)
        AS DECIMAL(6,2)
    ) AS advanced_after_skip_pct

FROM learning_path
GROUP BY
    experience_level,
    content_id
ORDER BY
    content_id,
    experience_level;

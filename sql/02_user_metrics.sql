USE [DUA_Edu_Challenge];
GO

-- Một dòng mỗi người dùng. D0 là ngày đăng ký theo giờ Việt Nam.
-- Activation và funnel dùng D0–D6. Retention D7 dùng đúng ngày thứ 7.
CREATE OR ALTER VIEW dbo.vw_user_metrics AS
WITH cohort AS (
    SELECT
        u.user_id,
        u.registered_at,
        CONVERT(date, u.registered_at) AS signup_date,
        u.acquisition_channel,
        u.device_type,
        u.learning_goal,
        u.experience_level,
        coverage.covered_through
    FROM dbo.Users AS u
    CROSS JOIN dbo.DatasetCoverage AS coverage
),
event_days AS (
    SELECT
        e.user_id,
        e.occurred_at,
        e.event_name,
        e.content_id,
        DATEDIFF(day, c.signup_date, e.occurred_at) AS day_number,
        CASE
            WHEN e.event_name IN (
                'log_in', 'view_content', 'start_lesson', 'complete_lesson',
                'submit_quiz', 'check_in', 'join_campaign', 'share_content'
            ) THEN 1
            ELSE 0
        END AS is_active
    FROM cohort AS c
    JOIN dbo.Events AS e ON e.user_id = c.user_id
    WHERE e.occurred_at >= c.registered_at
      AND e.occurred_at < DATEADD(day, 8, c.signup_date)
      AND e.occurred_at < DATEADD(day, 1, c.covered_through)
),
user_activity AS (
    SELECT
        user_id,
        MAX(CASE
            WHEN event_name = 'start_lesson' AND day_number <= 6 THEN 1
            ELSE 0
        END) AS activated_7d,
        MAX(CASE WHEN day_number = 1 THEN is_active ELSE 0 END) AS active_d1,
        MAX(CASE WHEN day_number = 2 THEN is_active ELSE 0 END) AS active_d2,
        MAX(CASE WHEN day_number = 3 THEN is_active ELSE 0 END) AS active_d3,
        MAX(CASE WHEN day_number = 4 THEN is_active ELSE 0 END) AS active_d4,
        MAX(CASE WHEN day_number = 5 THEN is_active ELSE 0 END) AS active_d5,
        MAX(CASE WHEN day_number = 6 THEN is_active ELSE 0 END) AS active_d6,
        MAX(CASE WHEN day_number = 7 THEN is_active ELSE 0 END) AS retained_d7,
        MAX(CASE
            WHEN day_number = 7
             AND event_name IN ('start_lesson', 'complete_lesson', 'submit_quiz') THEN 1
            ELSE 0
        END) AS learning_d7
    FROM event_days
    GROUP BY user_id
),

-- Funnel mở đầu theo thứ tự đăng ký, đăng nhập, xem bài.
first_signup AS (
    SELECT user_id, MIN(occurred_at) AS signed_at
    FROM event_days
    WHERE event_name = 'sign_up'
      AND day_number <= 6
    GROUP BY user_id
),
first_login AS (
    SELECT e.user_id, MIN(e.occurred_at) AS logged_at
    FROM event_days AS e
    JOIN first_signup AS signup ON signup.user_id = e.user_id
    WHERE e.event_name = 'log_in'
      AND e.day_number <= 6
      AND e.occurred_at > signup.signed_at
    GROUP BY e.user_id
),
first_view_per_lesson AS (
    SELECT e.user_id, e.content_id, MIN(e.occurred_at) AS viewed_at
    FROM event_days AS e
    JOIN first_login AS login_step ON login_step.user_id = e.user_id
    WHERE e.event_name = 'view_content'
      AND e.day_number <= 6
      AND e.occurred_at > login_step.logged_at
      AND e.content_id IS NOT NULL
    GROUP BY e.user_id, e.content_id
),

-- Lần bắt đầu và hoàn thành phải đến sau lượt xem của cùng bài.
lesson_funnel AS (
    SELECT
        lesson.user_id,
        MAX(CASE WHEN started.started_at IS NOT NULL THEN 1 ELSE 0 END) AS reached_start,
        MAX(CASE WHEN completed.completed_at IS NOT NULL THEN 1 ELSE 0 END) AS reached_complete
    FROM first_view_per_lesson AS lesson
    OUTER APPLY (
        SELECT MIN(e.occurred_at) AS started_at
        FROM event_days AS e
        WHERE e.user_id = lesson.user_id
          AND e.content_id = lesson.content_id
          AND e.event_name = 'start_lesson'
          AND e.day_number <= 6
          AND e.occurred_at > lesson.viewed_at
    ) AS started
    OUTER APPLY (
        SELECT MIN(e.occurred_at) AS completed_at
        FROM event_days AS e
        WHERE e.user_id = lesson.user_id
          AND e.content_id = lesson.content_id
          AND e.event_name = 'complete_lesson'
          AND e.day_number <= 6
          AND e.occurred_at > started.started_at
    ) AS completed
    GROUP BY lesson.user_id
)
SELECT
    c.user_id,
    c.signup_date,
    DATEADD(
        day,
        -(DATEDIFF(day, CONVERT(date, '19000101'), c.signup_date) % 7),
        c.signup_date
    ) AS cohort_week,
    c.acquisition_channel,
    c.device_type,
    c.learning_goal,
    c.experience_level,

    -- Cờ hành vi là NULL khi chưa đủ ngày quan sát.
    CASE WHEN coverage.observed_days >= 6 THEN 1 ELSE 0 END AS eligible_activation,
    CASE WHEN coverage.observed_days >= 7 THEN 1 ELSE 0 END AS eligible_d7,
    CASE WHEN coverage.observed_days >= 6 THEN COALESCE(activity.activated_7d, 0) END AS activated_7d,
    CASE WHEN coverage.observed_days >= 1 THEN COALESCE(activity.active_d1, 0) END AS active_d1,
    CASE WHEN coverage.observed_days >= 2 THEN COALESCE(activity.active_d2, 0) END AS active_d2,
    CASE WHEN coverage.observed_days >= 3 THEN COALESCE(activity.active_d3, 0) END AS active_d3,
    CASE WHEN coverage.observed_days >= 4 THEN COALESCE(activity.active_d4, 0) END AS active_d4,
    CASE WHEN coverage.observed_days >= 5 THEN COALESCE(activity.active_d5, 0) END AS active_d5,
    CASE WHEN coverage.observed_days >= 6 THEN COALESCE(activity.active_d6, 0) END AS active_d6,
    CASE WHEN coverage.observed_days >= 7 THEN COALESCE(activity.retained_d7, 0) END AS retained_d7,
    CASE WHEN coverage.observed_days >= 7 THEN COALESCE(activity.learning_d7, 0) END AS learning_d7,

    -- Funnel gồm người có đủ cửa sổ D0–D6 và đi đúng thứ tự.
    CASE WHEN coverage.observed_days >= 6 AND signup.user_id IS NOT NULL THEN 1 ELSE 0 END AS reached_signup,
    CASE WHEN coverage.observed_days >= 6 AND login_step.user_id IS NOT NULL THEN 1 ELSE 0 END AS reached_login,
    CASE WHEN coverage.observed_days >= 6 AND lesson.user_id IS NOT NULL THEN 1 ELSE 0 END AS reached_view,
    CASE WHEN coverage.observed_days >= 6 THEN COALESCE(lesson.reached_start, 0) ELSE 0 END AS reached_start,
    CASE WHEN coverage.observed_days >= 6 THEN COALESCE(lesson.reached_complete, 0) ELSE 0 END AS reached_complete
FROM cohort AS c
CROSS APPLY (VALUES (DATEDIFF(day, c.signup_date, c.covered_through))) AS coverage(observed_days)
LEFT JOIN user_activity AS activity ON activity.user_id = c.user_id
LEFT JOIN first_signup AS signup ON signup.user_id = c.user_id
LEFT JOIN first_login AS login_step ON login_step.user_id = c.user_id
LEFT JOIN lesson_funnel AS lesson ON lesson.user_id = c.user_id;
GO

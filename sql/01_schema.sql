/*
 DUA Edu Challenge — 01_schema.sql
 - Idempotently creates the four source tables and DatasetCoverage.
 - Existing Users table may have six columns from the old notebook. Two optional
   source fields are added WITHOUT deleting or rewriting existing rows.
 - This script never deletes data.
*/
USE [DUA_Edu_Challenge];
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Users (
        user_id VARCHAR(16) NOT NULL PRIMARY KEY,
        registered_at DATETIME2(3) NOT NULL,
        acquisition_channel NVARCHAR(80) NOT NULL,
        device_type NVARCHAR(40) NOT NULL,
        learning_goal NVARCHAR(100) NOT NULL,
        experience_level NVARCHAR(40) NOT NULL,
        ho_ten NVARCHAR(150) NULL,
        tinh_thanh NVARCHAR(100) NULL
    );
END;

-- Safe, additive migration for the old six-column Users table.
IF COL_LENGTH(N'dbo.Users', N'ho_ten') IS NULL
    ALTER TABLE dbo.Users ADD ho_ten NVARCHAR(150) NULL;
IF COL_LENGTH(N'dbo.Users', N'tinh_thanh') IS NULL
    ALTER TABLE dbo.Users ADD tinh_thanh NVARCHAR(100) NULL;

IF OBJECT_ID(N'dbo.Content', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Content (
        content_id VARCHAR(16) NOT NULL PRIMARY KEY,
        content_title NVARCHAR(200) NOT NULL,
        topic NVARCHAR(50) NOT NULL,
        [level] NVARCHAR(50) NOT NULL
    );
END;

IF OBJECT_ID(N'dbo.Campaigns', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Campaigns (
        campaign_id VARCHAR(16) NOT NULL PRIMARY KEY,
        campaign_name NVARCHAR(200) NOT NULL,
        campaign_type NVARCHAR(60) NOT NULL,
        start_date DATE NOT NULL,
        end_date DATE NOT NULL,
        CONSTRAINT CK_Campaigns_DateRange CHECK (end_date >= start_date)
    );
END;

IF OBJECT_ID(N'dbo.Events', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Events (
        event_id VARCHAR(16) NOT NULL PRIMARY KEY,
        user_id VARCHAR(16) NOT NULL REFERENCES dbo.Users(user_id),
        occurred_at DATETIME2(3) NOT NULL,
        event_name VARCHAR(40) NOT NULL,
        content_id VARCHAR(16) NULL,
        campaign_id VARCHAR(16) NULL
    );
END;

IF OBJECT_ID(N'dbo.DatasetCoverage', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DatasetCoverage (
        dataset_id TINYINT NOT NULL PRIMARY KEY CHECK (dataset_id = 1),
        covered_through DATE NOT NULL
    );
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.Events') AND name = N'IX_Events_User_Date'
)
BEGIN
    CREATE INDEX IX_Events_User_Date
    ON dbo.Events (user_id, occurred_at)
    INCLUDE (event_name, content_id);
END;
GO

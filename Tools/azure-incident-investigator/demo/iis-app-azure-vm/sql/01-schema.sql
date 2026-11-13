-- ============================================================================
--  01-schema.sql — creates the ContosoHR database and its tables.
--  Runs on both PRD and NPRD (identical schema — that's part of the story).
-- ============================================================================
USE master;
GO
IF DB_ID(N'##DB_NAME##') IS NULL
    EXEC ('CREATE DATABASE [##DB_NAME##]');
GO
USE [##DB_NAME##];
GO

IF OBJECT_ID('dbo.Countries','U') IS NULL
BEGIN
    CREATE TABLE dbo.Countries (
        CountryCode  CHAR(2)      NOT NULL PRIMARY KEY,
        CountryName  NVARCHAR(80) NOT NULL,
        Region       NVARCHAR(40) NOT NULL,
        FlagEmoji    NVARCHAR(8)  NULL
    );
END;

IF OBJECT_ID('dbo.Departments','U') IS NULL
BEGIN
    CREATE TABLE dbo.Departments (
        DepartmentId    INT           NOT NULL PRIMARY KEY,
        DepartmentName  NVARCHAR(80)  NOT NULL,
        CostCenter      NVARCHAR(20)  NOT NULL
    );
END;

IF OBJECT_ID('dbo.Employees','U') IS NULL
BEGIN
    CREATE TABLE dbo.Employees (
        EmployeeId    INT           NOT NULL PRIMARY KEY,
        FullName      NVARCHAR(120) NOT NULL,
        Email         NVARCHAR(150) NOT NULL,
        Title         NVARCHAR(120) NOT NULL,
        DepartmentId  INT           NOT NULL REFERENCES dbo.Departments(DepartmentId),
        CountryCode   CHAR(2)       NOT NULL REFERENCES dbo.Countries(CountryCode),
        HireDate      DATE          NOT NULL,
        AnnualSalary  DECIMAL(12,2) NOT NULL
    );
    CREATE INDEX IX_Employees_Country    ON dbo.Employees(CountryCode);
    CREATE INDEX IX_Employees_Department ON dbo.Employees(DepartmentId);
END;

IF OBJECT_ID('dbo.Timesheets','U') IS NULL
BEGIN
    CREATE TABLE dbo.Timesheets (
        TimesheetId  BIGINT IDENTITY(1,1) PRIMARY KEY,
        EmployeeId   INT           NOT NULL REFERENCES dbo.Employees(EmployeeId),
        WeekEnding   DATE          NOT NULL,
        HoursWorked  DECIMAL(5,2)  NOT NULL,
        Status       NVARCHAR(20)  NOT NULL,
        SubmittedAt  DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;

IF OBJECT_ID('dbo.AuditLog','U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditLog (
        AuditId   BIGINT IDENTITY(1,1) PRIMARY KEY,
        UserId    NVARCHAR(120) NOT NULL,
        Action    NVARCHAR(80)  NOT NULL,
        Detail    NVARCHAR(400) NULL,
        LoggedAt  DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

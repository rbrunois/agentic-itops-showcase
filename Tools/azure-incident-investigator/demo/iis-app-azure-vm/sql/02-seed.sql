-- ============================================================================
--  02-seed.sql — 4 countries, 10 departments, 100 employees, sample timesheets.
--  Idempotent — safe to re-run.
-- ============================================================================
USE [##DB_NAME##];
GO

-- Countries (4, deliberately geographically spread)
MERGE dbo.Countries AS t
USING (VALUES
    (N'CA', N'Canada',  N'North America', N'🇨🇦'),
    (N'JP', N'Japan',   N'Asia Pacific',  N'🇯🇵'),
    (N'DE', N'Germany', N'EMEA',          N'🇩🇪'),
    (N'BR', N'Brazil',  N'LATAM',         N'🇧🇷')
) AS s(CountryCode, CountryName, Region, FlagEmoji)
ON t.CountryCode = s.CountryCode
WHEN NOT MATCHED THEN INSERT (CountryCode, CountryName, Region, FlagEmoji) VALUES (s.CountryCode, s.CountryName, s.Region, s.FlagEmoji)
WHEN MATCHED THEN UPDATE SET t.FlagEmoji = s.FlagEmoji, t.CountryName = s.CountryName, t.Region = s.Region;

-- Departments (10)
MERGE dbo.Departments AS t
USING (VALUES
    (1, 'Sales',        'CC-100'),
    (2, 'Engineering',  'CC-200'),
    (3, 'Manufacturing','CC-300'),
    (4, 'Finance',      'CC-400'),
    (5, 'Human Resources','CC-500'),
    (6, 'Marketing',    'CC-600'),
    (7, 'IT',           'CC-700'),
    (8, 'Operations',   'CC-800'),
    (9, 'Legal',        'CC-900'),
    (10,'R&D',          'CC-950')
) AS s(DepartmentId, DepartmentName, CostCenter)
ON t.DepartmentId = s.DepartmentId
WHEN NOT MATCHED THEN INSERT (DepartmentId, DepartmentName, CostCenter) VALUES (s.DepartmentId, s.DepartmentName, s.CostCenter);

-- Employees (100 — deterministic generation so PRD and NPRD look identical)
IF (SELECT COUNT(*) FROM dbo.Employees) = 0
BEGIN
    ;WITH nums AS (
        SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ),
    firstnames(fn) AS (SELECT v FROM (VALUES
        (N'Emily'),(N'Liam'),(N'Sophia'),(N'Noah'),(N'Ava'),(N'Ethan'),(N'Isabella'),(N'Lucas'),
        (N'Mia'),(N'Mason'),(N'Charlotte'),(N'Logan'),(N'Amelia'),(N'James'),(N'Harper'),
        (N'Hiro'),(N'Yuki'),(N'Kenji'),(N'Sakura'),(N'Ren'),(N'Aoi'),(N'Haruto'),
        (N'Klaus'),(N'Anna'),(N'Stefan'),(N'Lena'),(N'Jonas'),(N'Sofia'),(N'Max'),
        (N'Joao'),(N'Camila'),(N'Rafael'),(N'Beatriz'),(N'Lucas'),(N'Larissa'),(N'Tiago'),
        (N'Chloe'),(N'Nathan'),(N'Zoe'),(N'Alexandre'),(N'Genevieve'),(N'Olivier'),(N'Marie')
    ) x(v)),
    lastnames(ln) AS (SELECT v FROM (VALUES
        (N'Tremblay'),(N'MacDonald'),(N'Nguyen'),(N'Roy'),(N'Beaulieu'),(N'Cote'),(N'Kim'),
        (N'Tanaka'),(N'Suzuki'),(N'Watanabe'),(N'Kobayashi'),(N'Ito'),(N'Nakamura'),(N'Sato'),
        (N'Mueller'),(N'Schmidt'),(N'Fischer'),(N'Weber'),(N'Meyer'),(N'Wagner'),(N'Becker'),
        (N'Silva'),(N'Santos'),(N'Souza'),(N'Oliveira'),(N'Ferreira'),(N'Alves'),(N'Rocha')
    ) y(v))
    INSERT INTO dbo.Employees (EmployeeId, FullName, Email, Title, DepartmentId, CountryCode, HireDate, AnnualSalary)
    SELECT
        n.n,
        (SELECT TOP 1 fn FROM firstnames ORDER BY (CHECKSUM(NEWID(),n.n))) + N' ' +
        (SELECT TOP 1 ln FROM lastnames  ORDER BY (CHECKSUM(NEWID(),n.n))) AS FullName,
        CONCAT('emp', RIGHT(CONCAT('000', n.n), 3), '@contoso.com') AS Email,
        CASE (n.n % 6)
            WHEN 0 THEN N'Analyst'
            WHEN 1 THEN N'Manager'
            WHEN 2 THEN N'Senior Engineer'
            WHEN 3 THEN N'Coordinator'
            WHEN 4 THEN N'Specialist'
            ELSE N'Director'
        END AS Title,
        ((n.n - 1) % 10) + 1 AS DepartmentId,
        CASE (n.n % 4)
            WHEN 0 THEN 'CA'
            WHEN 1 THEN 'JP'
            WHEN 2 THEN 'DE'
            ELSE 'BR'
        END AS CountryCode,
        DATEADD(DAY, -1 * (n.n * 17 % 3000), CAST(GETDATE() AS DATE)) AS HireDate,
        60000 + (n.n * 731 % 90000) AS AnnualSalary
    FROM nums n;
END;

-- Timesheets — one per employee for last 4 weeks
IF (SELECT COUNT(*) FROM dbo.Timesheets) = 0
BEGIN
    INSERT INTO dbo.Timesheets (EmployeeId, WeekEnding, HoursWorked, Status)
    SELECT
        e.EmployeeId,
        DATEADD(WEEK, -w.n, CAST(GETDATE() AS DATE)) AS WeekEnding,
        40 + (ABS(CHECKSUM(NEWID())) % 8) AS HoursWorked,
        CASE WHEN w.n = 0 THEN N'Draft' WHEN w.n = 1 THEN N'Submitted' ELSE N'Approved' END
    FROM dbo.Employees e
    CROSS JOIN (VALUES (0),(1),(2),(3)) AS w(n);
END;
GO

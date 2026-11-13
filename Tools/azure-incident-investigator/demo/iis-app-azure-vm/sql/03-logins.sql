-- ============================================================================
--  03-logins.sql — SQL login used by the web app (idempotent).
-- ============================================================================
USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = '##APP_LOGIN##')
BEGIN
    CREATE LOGIN [##APP_LOGIN##] WITH PASSWORD = N'##APP_PASSWORD##', CHECK_POLICY = OFF;
END;
ELSE
BEGIN
    ALTER LOGIN [##APP_LOGIN##] WITH PASSWORD = N'##APP_PASSWORD##';
END;
GO

USE [##DB_NAME##];
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '##APP_LOGIN##')
BEGIN
    CREATE USER [##APP_LOGIN##] FOR LOGIN [##APP_LOGIN##];
END;

EXEC sp_addrolemember N'db_datareader', N'##APP_LOGIN##';
EXEC sp_addrolemember N'db_datawriter', N'##APP_LOGIN##';
GO

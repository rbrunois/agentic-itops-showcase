#requires -Version 5.1
<#
Runs every 60 seconds on the web VM (via scheduled task).
Generates SELECT + INSERT activity against SQL to build a log history
that the SRE Agent can correlate against the incident. Also emits an
Application event so we can see the app's own "heartbeat" in the LAW.
Silently no-ops when SQL is unreachable — matching the app's own behavior.
#>
param(
    [Parameter(Mandatory=$true)][string]$SqlHost,
    [Parameter(Mandatory=$true)][string]$DbName,
    [Parameter(Mandatory=$true)][string]$DbUser,
    [Parameter(Mandatory=$true)][string]$DbPassword,
    [Parameter(Mandatory=$true)][string]$EnvPrefix
)

$ErrorActionPreference = 'SilentlyContinue'
$connStr = "Server=$SqlHost;Database=$DbName;User Id=$DbUser;Password=$DbPassword;Encrypt=false;TrustServerCertificate=true;Connect Timeout=5"

try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
    $conn.Open()

    # Pick a random SELECT so log patterns look "real"
    $queries = @(
        "SELECT COUNT(*) FROM dbo.Employees",
        "SELECT TOP 5 EmployeeId, FullName, CountryCode FROM dbo.Employees ORDER BY NEWID()",
        "SELECT c.CountryName, COUNT(e.EmployeeId) FROM dbo.Countries c LEFT JOIN dbo.Employees e ON e.CountryCode=c.CountryCode GROUP BY c.CountryName",
        "SELECT d.DepartmentName, COUNT(e.EmployeeId) FROM dbo.Departments d LEFT JOIN dbo.Employees e ON e.DepartmentId=d.DepartmentId GROUP BY d.DepartmentName"
    )
    $q = $queries | Get-Random
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $q
    $reader = $cmd.ExecuteReader(); while ($reader.Read()) {}; $reader.Close()

    # Insert an audit row so the DB has continuous write activity
    $ins = $conn.CreateCommand()
    $ins.CommandText = "INSERT INTO dbo.AuditLog(UserId, Action, Detail) VALUES(@u, @a, @d)"
    [void]$ins.Parameters.AddWithValue('@u', "$EnvPrefix\ActivityGen")
    [void]$ins.Parameters.AddWithValue('@a', 'Heartbeat')
    [void]$ins.Parameters.AddWithValue('@d', "Query: $($q.Substring(0,[Math]::Min(80,$q.Length)))")
    [void]$ins.ExecuteNonQuery()

    $conn.Close()

    Write-EventLog -LogName Application -Source 'ContosoHR-Activity' -EntryType Information -EventId 1001 -Message "OK env=$EnvPrefix query=$q"
} catch {
    # Silent — matches the app's own swallowed-exception pattern.
    Write-EventLog -LogName Application -Source 'ContosoHR-Activity' -EntryType Warning -EventId 1002 -Message "DB unreachable: $($_.Exception.Message)"
}

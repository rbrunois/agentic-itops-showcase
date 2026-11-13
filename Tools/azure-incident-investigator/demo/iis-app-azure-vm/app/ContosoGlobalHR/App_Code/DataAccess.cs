using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;

namespace ContosoHR
{
    public class Country
    {
        public string CountryCode { get; set; }
        public string CountryName { get; set; }
        public string Region      { get; set; }
        public string FlagEmoji   { get; set; }
        public int    EmployeeCount { get; set; }
    }
    public class Department
    {
        public int    DepartmentId   { get; set; }
        public string DepartmentName { get; set; }
        public string CostCenter     { get; set; }
        public int    HeadCount      { get; set; }
    }
    public class Employee
    {
        public int    EmployeeId   { get; set; }
        public string FullName     { get; set; }
        public string Email        { get; set; }
        public string Title        { get; set; }
        public string Department   { get; set; }
        public string CountryCode  { get; set; }
        public string CountryName  { get; set; }
        public DateTime HireDate   { get; set; }
        public decimal AnnualSalary{ get; set; }
    }
    public class Timesheet
    {
        public long   TimesheetId { get; set; }
        public string EmployeeName{ get; set; }
        public DateTime WeekEnding{ get; set; }
        public decimal HoursWorked{ get; set; }
        public string Status      { get; set; }
        public DateTime SubmittedAt{ get; set; }
    }

    /// <summary>
    ///   The "silent-failure" data-access class. Every method wraps its SqlClient
    ///   call in a broad try/catch and returns an empty list on ANY failure — no
    ///   error is surfaced to the UI. This is the anti-pattern the SRE Agent has
    ///   to detect: page renders fine, data just isn't there.
    /// </summary>
    public static class DataAccess
    {
        public static string EnvPrefix
        {
            get { return ConfigurationManager.AppSettings["EnvPrefix"] ?? "?"; }
        }

        private static string CS
        {
            get { return ConfigurationManager.ConnectionStrings["ContosoHR"].ConnectionString; }
        }

        private static SqlConnection Open()
        {
            var c = new SqlConnection(CS);
            c.Open();
            return c;
        }

        public static int GetEmployeeCount()
        {
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Employees", c))
                    return (int)cmd.ExecuteScalar();
            } catch { return 0; }
        }
        public static int GetDepartmentCount()
        {
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Departments", c))
                    return (int)cmd.ExecuteScalar();
            } catch { return 0; }
        }
        public static int GetCountryCount()
        {
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Countries", c))
                    return (int)cmd.ExecuteScalar();
            } catch { return 0; }
        }
        public static int GetPendingTimesheetCount()
        {
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Timesheets WHERE Status = 'Submitted'", c))
                    return (int)cmd.ExecuteScalar();
            } catch { return 0; }
        }

        public static List<Employee> GetEmployees()
        {
            var list = new List<Employee>();
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand(
                    "SELECT e.EmployeeId, e.FullName, e.Email, e.Title, d.DepartmentName, e.CountryCode, ct.CountryName, e.HireDate, e.AnnualSalary " +
                    "FROM dbo.Employees e " +
                    "  JOIN dbo.Departments d ON d.DepartmentId = e.DepartmentId " +
                    "  JOIN dbo.Countries   ct ON ct.CountryCode = e.CountryCode " +
                    "ORDER BY e.FullName", c))
                using (var r = cmd.ExecuteReader())
                    while (r.Read()) list.Add(new Employee {
                        EmployeeId   = (int)r["EmployeeId"],
                        FullName     = (string)r["FullName"],
                        Email        = (string)r["Email"],
                        Title        = (string)r["Title"],
                        Department   = (string)r["DepartmentName"],
                        CountryCode  = (string)r["CountryCode"],
                        CountryName  = (string)r["CountryName"],
                        HireDate     = (DateTime)r["HireDate"],
                        AnnualSalary = (decimal)r["AnnualSalary"]
                    });
            } catch { /* silent */ }
            return list;
        }

        public static List<Department> GetDepartments()
        {
            var list = new List<Department>();
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand(
                    "SELECT d.DepartmentId, d.DepartmentName, d.CostCenter, COUNT(e.EmployeeId) AS HeadCount " +
                    "FROM dbo.Departments d LEFT JOIN dbo.Employees e ON e.DepartmentId = d.DepartmentId " +
                    "GROUP BY d.DepartmentId, d.DepartmentName, d.CostCenter " +
                    "ORDER BY d.DepartmentName", c))
                using (var r = cmd.ExecuteReader())
                    while (r.Read()) list.Add(new Department {
                        DepartmentId   = (int)r["DepartmentId"],
                        DepartmentName = (string)r["DepartmentName"],
                        CostCenter     = (string)r["CostCenter"],
                        HeadCount      = (int)r["HeadCount"]
                    });
            } catch { /* silent */ }
            return list;
        }

        public static List<Country> GetCountries()
        {
            var list = new List<Country>();
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand(
                    "SELECT ct.CountryCode, ct.CountryName, ct.Region, ct.FlagEmoji, COUNT(e.EmployeeId) AS EmployeeCount " +
                    "FROM dbo.Countries ct LEFT JOIN dbo.Employees e ON e.CountryCode = ct.CountryCode " +
                    "GROUP BY ct.CountryCode, ct.CountryName, ct.Region, ct.FlagEmoji " +
                    "ORDER BY ct.CountryName", c))
                using (var r = cmd.ExecuteReader())
                    while (r.Read()) list.Add(new Country {
                        CountryCode   = (string)r["CountryCode"],
                        CountryName   = (string)r["CountryName"],
                        Region        = (string)r["Region"],
                        FlagEmoji     = r["FlagEmoji"] == DBNull.Value ? "" : (string)r["FlagEmoji"],
                        EmployeeCount = (int)r["EmployeeCount"]
                    });
            } catch { /* silent */ }
            return list;
        }

        public static List<Timesheet> GetTimesheets(int top = 100)
        {
            var list = new List<Timesheet>();
            try {
                using (var c = Open())
                using (var cmd = new SqlCommand(
                    "SELECT TOP (" + top + ") t.TimesheetId, e.FullName, t.WeekEnding, t.HoursWorked, t.Status, t.SubmittedAt " +
                    "FROM dbo.Timesheets t JOIN dbo.Employees e ON e.EmployeeId = t.EmployeeId " +
                    "ORDER BY t.SubmittedAt DESC", c))
                using (var r = cmd.ExecuteReader())
                    while (r.Read()) list.Add(new Timesheet {
                        TimesheetId  = (long)r["TimesheetId"],
                        EmployeeName = (string)r["FullName"],
                        WeekEnding   = (DateTime)r["WeekEnding"],
                        HoursWorked  = (decimal)r["HoursWorked"],
                        Status       = (string)r["Status"],
                        SubmittedAt  = (DateTime)r["SubmittedAt"]
                    });
            } catch { /* silent */ }
            return list;
        }
    }
}

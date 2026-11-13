<%@ Page Title="Dashboard" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" %>
<%@ Import Namespace="ContosoHR" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        NumEmployees.Text     = DataAccess.GetEmployeeCount().ToString("N0");
        NumDepartments.Text   = DataAccess.GetDepartmentCount().ToString("N0");
        NumCountries.Text     = DataAccess.GetCountryCount().ToString("N0");
        NumPendingTs.Text     = DataAccess.GetPendingTimesheetCount().ToString("N0");
    }
</script>
<asp:Content ContentPlaceHolderID="main" runat="server">
    <h2 class="mb-4">Dashboard</h2>
    <div class="row g-3">
        <div class="col-md-3"><div class="tile tile-1">
            <div class="lbl">Employees</div>
            <div class="num"><asp:Literal ID="NumEmployees" runat="server" Text="0" /></div>
        </div></div>
        <div class="col-md-3"><div class="tile tile-2">
            <div class="lbl">Departments</div>
            <div class="num"><asp:Literal ID="NumDepartments" runat="server" Text="0" /></div>
        </div></div>
        <div class="col-md-3"><div class="tile tile-3">
            <div class="lbl">Countries</div>
            <div class="num"><asp:Literal ID="NumCountries" runat="server" Text="0" /></div>
        </div></div>
        <div class="col-md-3"><div class="tile tile-4">
            <div class="lbl">Pending timesheets</div>
            <div class="num"><asp:Literal ID="NumPendingTs" runat="server" Text="0" /></div>
        </div></div>
    </div>

    <div class="row mt-4">
        <div class="col-md-8">
            <div class="card">
                <div class="card-header">Recent activity</div>
                <div class="card-body">
                    <p class="text-muted">Automated summary refresh — every minute.</p>
                    <p>Welcome to the Contoso Global HR portal (<span class="env-badge env-<%= DataAccess.EnvPrefix %>"><%= DataAccess.EnvPrefix %></span>).</p>
                    <p>Use the sidebar to browse employees, departments, our global presence, and timesheets.</p>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card">
                <div class="card-header">System</div>
                <div class="card-body">
                    <div><strong>Environment:</strong> <%= DataAccess.EnvPrefix %></div>
                    <div><strong>App server:</strong> <%= Environment.MachineName %></div>
                    <div><strong>App version:</strong> 4.8.0 (legacy)</div>
                </div>
            </div>
        </div>
    </div>
</asp:Content>

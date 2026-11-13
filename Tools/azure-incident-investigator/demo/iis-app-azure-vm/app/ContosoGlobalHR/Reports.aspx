<%@ Page Title="Reports" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" %>
<%@ Import Namespace="ContosoHR" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        if (!IsPostBack) {
            reportPicker.Items.Add(new System.Web.UI.WebControls.ListItem("Headcount by Country",    "byCountry"));
            reportPicker.Items.Add(new System.Web.UI.WebControls.ListItem("Headcount by Department", "byDept"));
            reportPicker.Items.Add(new System.Web.UI.WebControls.ListItem("Top-paid employees",      "topPay"));
            RunReport("byCountry");
        }
    }
    protected void OnRun(object sender, EventArgs e) { RunReport(reportPicker.SelectedValue); }
    private void RunReport(string key)
    {
        switch (key) {
            case "byCountry":
                gv.DataSource = DataAccess.GetCountries();
                break;
            case "byDept":
                gv.DataSource = DataAccess.GetDepartments();
                break;
            case "topPay":
                var emps = DataAccess.GetEmployees();
                emps.Sort((a,b) => b.AnnualSalary.CompareTo(a.AnnualSalary));
                if (emps.Count > 20) emps.RemoveRange(20, emps.Count - 20);
                gv.DataSource = emps;
                break;
        }
        gv.DataBind();
    }
</script>
<asp:Content ContentPlaceHolderID="main" runat="server">
    <h2 class="mb-4">Reports</h2>
    <div class="card mb-3">
        <div class="card-body d-flex align-items-center">
            <label class="me-3 mb-0">Report:</label>
            <asp:DropDownList ID="reportPicker" runat="server" CssClass="form-select me-3" style="max-width: 320px;" />
            <asp:Button ID="btnRun" runat="server" Text="Run" CssClass="btn btn-primary" OnClick="OnRun" />
        </div>
    </div>
    <div class="card">
        <div class="card-body p-0">
            <asp:GridView ID="gv" runat="server" AutoGenerateColumns="true" CssClass="table table-striped table-sm mb-0" GridLines="None">
                <EmptyDataTemplate>
                    <div class="p-3 text-muted">No data available.</div>
                </EmptyDataTemplate>
            </asp:GridView>
        </div>
    </div>
</asp:Content>

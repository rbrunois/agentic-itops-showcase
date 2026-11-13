<%@ Page Title="Timesheets" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" %>
<%@ Import Namespace="ContosoHR" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        gv.DataSource = DataAccess.GetTimesheets(100);
        gv.DataBind();
    }
</script>
<asp:Content ContentPlaceHolderID="main" runat="server">
    <h2 class="mb-4">Timesheets</h2>
    <div class="card">
        <div class="card-header">Recent submissions (last 100)</div>
        <div class="card-body p-0">
            <asp:GridView ID="gv" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-sm mb-0" GridLines="None">
                <Columns>
                    <asp:BoundField DataField="TimesheetId"  HeaderText="ID" />
                    <asp:BoundField DataField="EmployeeName" HeaderText="Employee" />
                    <asp:BoundField DataField="WeekEnding"   HeaderText="Week ending" DataFormatString="{0:yyyy-MM-dd}" />
                    <asp:BoundField DataField="HoursWorked"  HeaderText="Hours" />
                    <asp:BoundField DataField="Status"       HeaderText="Status" />
                    <asp:BoundField DataField="SubmittedAt"  HeaderText="Submitted" DataFormatString="{0:yyyy-MM-dd HH:mm}" />
                </Columns>
                <EmptyDataTemplate>
                    <div class="p-3 text-muted">No data available.</div>
                </EmptyDataTemplate>
            </asp:GridView>
        </div>
    </div>
</asp:Content>

<%@ Page Title="Employees" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" %>
<%@ Import Namespace="ContosoHR" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        var rows = DataAccess.GetEmployees();
        gv.DataSource = rows;
        gv.DataBind();
        rowCount.Text = rows.Count.ToString("N0");
    }
</script>
<asp:Content ContentPlaceHolderID="main" runat="server">
    <h2 class="mb-4">Employees</h2>
    <div class="card">
        <div class="card-header d-flex justify-content-between">
            <span>All employees</span>
            <span class="text-muted"><asp:Literal ID="rowCount" runat="server" /> rows</span>
        </div>
        <div class="card-body p-0">
            <asp:GridView ID="gv" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-sm mb-0" GridLines="None">
                <Columns>
                    <asp:BoundField DataField="EmployeeId"  HeaderText="ID" />
                    <asp:BoundField DataField="FullName"    HeaderText="Name" />
                    <asp:BoundField DataField="Title"       HeaderText="Title" />
                    <asp:BoundField DataField="Department"  HeaderText="Department" />
                    <asp:BoundField DataField="CountryName" HeaderText="Country" />
                    <asp:BoundField DataField="HireDate"    HeaderText="Hire date" DataFormatString="{0:yyyy-MM-dd}" />
                    <asp:BoundField DataField="AnnualSalary" HeaderText="Salary" DataFormatString="{0:C0}" />
                </Columns>
                <EmptyDataTemplate>
                    <div class="p-3 text-muted">No data available.</div>
                </EmptyDataTemplate>
            </asp:GridView>
        </div>
    </div>
</asp:Content>

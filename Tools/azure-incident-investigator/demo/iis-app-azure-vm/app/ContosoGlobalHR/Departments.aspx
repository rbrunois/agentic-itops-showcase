<%@ Page Title="Departments" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" %>
<%@ Import Namespace="ContosoHR" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        gv.DataSource = DataAccess.GetDepartments();
        gv.DataBind();
    }
</script>
<asp:Content ContentPlaceHolderID="main" runat="server">
    <h2 class="mb-4">Departments</h2>
    <div class="card">
        <div class="card-header">All departments</div>
        <div class="card-body p-0">
            <asp:GridView ID="gv" runat="server" AutoGenerateColumns="false" CssClass="table table-striped table-sm mb-0" GridLines="None">
                <Columns>
                    <asp:BoundField DataField="DepartmentId"   HeaderText="ID" />
                    <asp:BoundField DataField="DepartmentName" HeaderText="Name" />
                    <asp:BoundField DataField="CostCenter"     HeaderText="Cost Center" />
                    <asp:BoundField DataField="HeadCount"      HeaderText="Head Count" />
                </Columns>
                <EmptyDataTemplate>
                    <div class="p-3 text-muted">No data available.</div>
                </EmptyDataTemplate>
            </asp:GridView>
        </div>
    </div>
</asp:Content>

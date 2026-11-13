<%@ Page Title="Global Presence" Language="C#" MasterPageFile="~/Site.Master" AutoEventWireup="true" %>
<%@ Import Namespace="ContosoHR" %>
<script runat="server">
    protected void Page_Load(object sender, EventArgs e)
    {
        rpt.DataSource = DataAccess.GetCountries();
        rpt.DataBind();
    }
</script>
<asp:Content ContentPlaceHolderID="main" runat="server">
    <h2 class="mb-4">Global Presence</h2>
    <div class="row g-3">
        <asp:Repeater ID="rpt" runat="server">
            <ItemTemplate>
                <div class="col-md-3">
                    <div class="card text-center">
                        <div class="card-body">
                            <div class="text-primary" style="font-size: 3rem"><i class="bi bi-globe2"></i></div>
                            <h5 class="mt-2"><%# Eval("CountryName") %></h5>
                            <div class="text-muted small"><%# Eval("Region") %></div>
                            <div class="mt-3">
                                <div class="display-6"><%# Eval("EmployeeCount") %></div>
                                <div class="small text-muted">Employees</div>
                            </div>
                        </div>
                    </div>
                </div>
            </ItemTemplate>
            <FooterTemplate>
            </FooterTemplate>
        </asp:Repeater>
    </div>
    <asp:Panel ID="empty" runat="server" Visible="false">
        <div class="text-muted p-4">No data available.</div>
    </asp:Panel>
</asp:Content>

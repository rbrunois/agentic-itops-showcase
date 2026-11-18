using System.Net;
using System.Net.Http.Json;
using CampingApi.Models;
using CampingApi.Services;
using CampingApi.Controllers;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Mvc;

namespace CampingApi.Tests;

public class ApiTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 2)]
    public void Analytics_fault_is_opt_in(int entryMegabytes, int expectedEntries)
    {
        var options = Microsoft.Extensions.Options.Options.Create(new CampingApiOptions
        {
            AnalyticsEntryMegabytes = entryMegabytes
        });
        var cache = new RequestAnalyticsCache(
            options, Microsoft.Extensions.Logging.Abstractions.NullLogger<RequestAnalyticsCache>.Instance);
        cache.Record("synthetic-user");
        cache.Record("synthetic-user");
        Assert.Equal(expectedEntries, cache.EntryCount);
    }

    [Fact]
    public async Task Ordinary_cart_requests_do_not_enable_the_memory_fault()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();
        await client.PostAsJsonAsync("/api/cart/safe-default/items", new AddCartItemRequest(1, 1));
        Assert.Equal(0, factory.Services.GetRequiredService<IRequestAnalyticsCache>().EntryCount);
    }

    [Fact]
    public void Presentation_probe_does_not_accumulate_fault_buffers()
    {
        var options = Microsoft.Extensions.Options.Options.Create(new CampingApiOptions
        {
            AnalyticsEntryMegabytes = 1
        });
        var cache = new RequestAnalyticsCache(
            options, Microsoft.Extensions.Logging.Abstractions.NullLogger<RequestAnalyticsCache>.Instance);
        cache.Record("presentation-probe");
        cache.Record("presentation-probe");
        Assert.Equal(0, cache.EntryCount);
        cache.Record("shopper-synthetic");
        Assert.Equal(1, cache.EntryCount);
    }

    private sealed class CountingAnalytics : IRequestAnalyticsCache
    {
        public int EntryCount { get; private set; }
        public void Record(string userId) => EntryCount++;
    }

    private sealed class RecordingLogger<T> : ILogger<T>
    {
        public List<string> Messages { get; } = new();
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state,
            Exception? exception, Func<TState, Exception?, string> formatter) =>
            Messages.Add(formatter(state, exception));
    }

    [Fact]
    public void Analytics_logs_keep_metrics_without_untrusted_user_text()
    {
        var logger = new RecordingLogger<RequestAnalyticsCache>();
        var cache = new RequestAnalyticsCache(
            Microsoft.Extensions.Options.Options.Create(new CampingApiOptions { AnalyticsEntryMegabytes = 1 }),
            logger);
        cache.Record("shopper\r\nforged-log-entry\u2028");
        var message = Assert.Single(logger.Messages);
        Assert.Contains("Entries=1", message);
        Assert.Contains("ApproxSizeMB=1", message);
        Assert.DoesNotContain("forged-log-entry", message);
        Assert.DoesNotContain("\r", message);
        Assert.DoesNotContain("\n", message);
    }

    [Fact]
    public void Payment_failure_logs_do_not_include_untrusted_user_text()
    {
        using var factory = CreateFactory("v2", new CountingAnalytics());
        const string userId = "shopper\r\nforged-log-entry\u2028";
        factory.Services.GetRequiredService<ICartService>().AddItem(userId, 1, 1);
        var logger = new RecordingLogger<OrdersController>();
        var controller = new OrdersController(factory.Services.GetRequiredService<IOrderService>(), logger);
        var result = controller.PlaceOrder(new PlaceOrderRequest(userId, "Demo address", "card"));
        Assert.Equal(500, Assert.IsType<ObjectResult>(result.Result).StatusCode);
        Assert.Equal("Payment processing failed", Assert.Single(logger.Messages));
    }

    private static WebApplicationFactory<Program> CreateFactory(string apiVersion = "v1", CountingAnalytics? analytics = null) =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(b =>
        {
            b.UseSetting("API_VERSION", apiVersion);
            b.ConfigureServices(s =>
            {
                if (analytics != null)
                {
                    s.RemoveAll<IRequestAnalyticsCache>();
                    s.AddSingleton<IRequestAnalyticsCache>(analytics);
                }
            });
        });

    [Fact]
    public async Task Health_returns_200()
    {
        using var client = CreateFactory().CreateClient();
        var response = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Products_can_be_listed_and_filtered()
    {
        using var client = CreateFactory().CreateClient();
        var all = await client.GetFromJsonAsync<List<Product>>("/api/products");
        var tents = await client.GetFromJsonAsync<List<Product>>("/api/products?category=Tents");
        Assert.NotEmpty(all!);
        Assert.All(tents!, p => Assert.Equal("Tents", p.Category));
    }

    [Fact]
    public async Task Cart_add_records_analytics_through_injected_cache()
    {
        var analytics = new CountingAnalytics();
        using var client = CreateFactory(analytics: analytics).CreateClient();
        var response = await client.PostAsJsonAsync("/api/cart/u1/items", new AddCartItemRequest(1, 2));
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, analytics.EntryCount);
    }

    [Fact]
    public async Task Unknown_product_returns_404()
    {
        using var client = CreateFactory(analytics: new CountingAnalytics()).CreateClient();
        var response = await client.PostAsJsonAsync("/api/cart/u1/items", new AddCartItemRequest(9999, 1));
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Checkout_succeeds_on_v1()
    {
        using var client = CreateFactory(analytics: new CountingAnalytics()).CreateClient();
        await client.PostAsJsonAsync("/api/cart/u2/items", new AddCartItemRequest(4, 1));
        var response = await client.PostAsJsonAsync("/api/orders", new PlaceOrderRequest("u2", "1 Trail Rd", "card"));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    [Fact]
    public async Task Checkout_returns_500_on_v2()
    {
        using var client = CreateFactory("v2", new CountingAnalytics()).CreateClient();
        await client.PostAsJsonAsync("/api/cart/u3/items", new AddCartItemRequest(4, 1));
        var response = await client.PostAsJsonAsync("/api/orders", new PlaceOrderRequest("u3", "1 Trail Rd", "card"));
        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
    }
}

# Camping Store architecture

Trailhead Outfitters is a fictional Contoso camping retailer. The React/Node storefront
proxies requests to an ASP.NET Core API on two public HTTPS Azure Container Apps.
There is no authentication or persistent database. Use synthetic data only.
API catalogue, carts, and orders are in memory; replicas do not share state.
The single-replica frontend keeps synthetic checkout receipts and aggregate
sales/outage metrics in a local JSON ledger, not a durable volume. Order history
uses this ledger, which can disappear on container replacement.
This is a demonstration, not production architecture.

Source is under `Tools/azure-sre-camping-store/src` in the showcase repository.
`api/Program.cs` registers services using dependency injection and exposes
`GET /health`. Products are at `GET /api/products`; add a cart item using
`POST /api/cart/demo-user/items` with `{"productId":1,"quantity":1}`.
Checkout uses `POST /api/orders` with a user ID, synthetic shipping address,
and payment method. No actual payments are made.

`api/Services/RequestAnalyticsCache.cs` deliberately retains buffers when
`Camping__AnalyticsEntryMegabytes` is nonzero. The default is zero: ordinary
cart requests do not allocate or retain analytics entries. The approved memory
scenario sets it to 10 MB per cart-add request, then sends bounded load.
The frontend adds and clears a `presentation-probe` cart every five seconds
to measure availability. That user does not retain analytics buffers even when
the fault is enabled; attendee cart requests still do.
`api/Services/PaymentGateway.cs` simulates checkout failure with `API_VERSION=v2`;
default `v1` is healthy. Do not infer either fault from health alone.
API diagnostic logs retain payment failures and aggregate cache counts/sizes,
but omit user-supplied shopper IDs to prevent forged log lines.

The API uses 0.5 CPU / 1 GiB RAM (1-5 replicas); frontend uses 0.25 CPU / 0.5 GiB
(one replica, port 8080). Only one active revision serves each app. Azure Monitor 5xx
alerts, Application Insights, and Log Analytics provide evidence. OOM can restart
a replica without generating sufficient HTTP 5xx to fire the alert.

The SRE identity has Reader, Monitoring Reader, and Log Analytics Reader only
on the lab group. The deployer creates role assignments; the agent cannot
restart, scale, deploy, or remediate. Image builds use billable ACR Tasks.
See the package README for deployment, fault injection, recovery, and teardown.

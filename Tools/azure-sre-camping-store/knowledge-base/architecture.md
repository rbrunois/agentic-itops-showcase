# Camping Store architecture

Trailhead Outfitters is a fictional Contoso camping retailer. The React/nginx
storefront calls an ASP.NET Core API on two public HTTPS Azure Container Apps.
There is no authentication or persistent database. Use synthetic data only.
Product catalogue, carts, and orders are in memory and disappear on restart;
replicas do not share state. This is a demonstration, not production architecture.

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
`api/Services/PaymentGateway.cs` simulates checkout failure with `API_VERSION=v2`;
default `v1` is healthy. Do not infer either fault from health alone.

The API uses 0.5 CPU / 1 GiB RAM (1-5 replicas); frontend uses 0.25 CPU / 0.5 GiB
(1-3 replicas). Only one active revision serves each app. Azure Monitor 5xx
alerts, Application Insights, and Log Analytics provide evidence. OOM can restart
a replica without generating sufficient HTTP 5xx to fire the alert.

The SRE identity has Reader, Monitoring Reader, and Log Analytics Reader only
on the lab group. The deployer creates role assignments; the agent cannot
restart, scale, deploy, or remediate. Image builds use billable ACR Tasks.
See the package README for deployment, fault injection, recovery, and teardown.

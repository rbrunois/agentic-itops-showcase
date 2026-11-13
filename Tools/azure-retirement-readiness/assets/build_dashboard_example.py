"""Generate the illustrative Azure Retirement Readiness dashboard SVG.

Standard library only. Output is deterministic; rerunning produces a
byte-identical file. All subscription, owner, and resource data is synthetic.
Lifecycle dates are taken from Microsoft documentation (see README references).
"""

import html
from datetime import date, timedelta
from pathlib import Path

BASE = Path(__file__).resolve().parent
OUTPUT = BASE / "azure-retirement-readiness-dashboard.svg"

# Evidence date and verified lifecycle dates.
EVIDENCE_DATE = date(2026, 9, 25)
DOTNET8_FUNCTIONS_EOS = date(2026, 11, 10)
DOTNET10_FUNCTIONS_EOS = date(2028, 11, 14)
BING_SEARCH_APIS_RETIRED = date(2025, 8, 11)
BOT_FRAMEWORK_SDK_SUPPORT_END = date(2025, 12, 31)

DAYS_TO_DEADLINE = (DOTNET8_FUNCTIONS_EOS - EVIDENCE_DATE).days

RESOURCES_SCANNED = 126
LEGACY_ARM_TYPES = 0
BING_ACCOUNTS = ["web-grounding"]
BOT_RESOURCES = ["customer-support-bot", "claims-assistant", "field-service-bot"]
VALIDATE_NOW = len(BING_ACCOUNTS) + len(BOT_RESOURCES)

MONTHS = [
    "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December",
]

WIDTH = 1440
MARGIN = 64
CONTENT_W = WIDTH - 2 * MARGIN

CANVAS = "#F3F5F8"
INK = "#14212E"
MUTED = "#4A5B6C"
BORDER = "#C9D4E0"
PANEL = "#FFFFFF"
AZURE = "#0063B1"
AZURE_DARK = "#003A70"
AZURE_LIGHT = "#E8F3FD"
NAVY = "#0B2E59"
LINK = "#005A9E"
LINK_ON_DARK = "#A8DBFF"
RED = "#B3261E"
RED_LIGHT = "#FDECEA"
AMBER = "#7A4D00"
AMBER_LIGHT = "#FFF4D6"
GREEN = "#0E6B38"
GREEN_LIGHT = "#E7F6EC"
GRID = "#DDE5EE"

SANS = "Segoe UI, Inter, Helvetica, Arial, sans-serif"
MONO = "Cascadia Mono, Consolas, Menlo, monospace"

body: list[str] = []
add = body.append


def long_date(value: date) -> str:
    return f"{MONTHS[value.month - 1]} {value.day}, {value.year}"


def short_date(value: date) -> str:
    return f"{MONTHS[value.month - 1][:3]} {value.day}"


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def num(value: float) -> str:
    return f"{value:.2f}".rstrip("0").rstrip(".")


NARROW = set("iljtfrI.,:;'|!()[] -/")
WIDE = set("mwMW@%")


def text_width(value: str, size: float, bold: bool = False, mono: bool = False) -> float:
    """Conservative width estimate for a Segoe UI / Arial-like font."""
    if mono:
        return len(value) * size * 0.62
    total = 0.0
    for char in value:
        if char in WIDE:
            total += 0.86
        elif char in NARROW:
            total += 0.32
        elif char.isupper() or char.isdigit():
            total += 0.64
        else:
            total += 0.54
    return total * size * (1.07 if bold else 1.0)


def wrap(value: str, size: float, max_width: float, bold: bool = False, mono: bool = False) -> list[str]:
    lines: list[str] = []
    current = ""
    for word in value.split(" "):
        candidate = f"{current} {word}" if current else word
        if current and text_width(candidate, size, bold, mono) > max_width:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def text(
    x: float,
    y: float,
    value: str,
    size: float,
    color: str = INK,
    weight: int = 400,
    anchor: str = "start",
    mono: bool = False,
    spacing: float = 0,
    underline: bool = False,
) -> None:
    attrs = [
        f'x="{num(x)}"',
        f'y="{num(y)}"',
        f'fill="{color}"',
        f'font-size="{num(size)}"',
    ]
    if weight != 400:
        attrs.append(f'font-weight="{weight}"')
    if anchor != "start":
        attrs.append(f'text-anchor="{anchor}"')
    if mono:
        attrs.append(f'font-family="{MONO}"')
    if spacing:
        attrs.append(f'letter-spacing="{num(spacing)}"')
    if underline:
        attrs.append('text-decoration="underline"')
    add(f"<text {' '.join(attrs)}>{esc(value)}</text>")


def paragraph(
    x: float,
    y: float,
    value: str,
    size: float,
    max_width: float,
    color: str = MUTED,
    line_height: float = 1.5,
    weight: int = 400,
) -> float:
    """Draw wrapped text with the first baseline at y; return the y below it."""
    lines = wrap(value, size, max_width, weight >= 600)
    step = size * line_height
    for index, line in enumerate(lines):
        text(x, y + index * step, line, size, color, weight)
    return y + (len(lines) - 1) * step + size * 0.5


def bullets(x: float, y: float, items: list[str], size: float, max_width: float, gap: float = 8) -> float:
    step = size * 1.5
    for item in items:
        add(f'<circle cx="{num(x + 3)}" cy="{num(y - size * 0.33)}" r="2.6" fill="{AZURE}"/>')
        lines = wrap(item, size, max_width - 16)
        for index, line in enumerate(lines):
            text(x + 16, y + index * step, line, size, INK)
        y += len(lines) * step + gap
    return y - gap - step


def rect(
    x: float,
    y: float,
    width: float,
    height: float,
    fill: str,
    stroke: str | None = BORDER,
    radius: float = 0,
    stroke_width: float = 1,
    shadow: bool = False,
) -> None:
    stroke_attr = f' stroke="{stroke}" stroke-width="{num(stroke_width)}"' if stroke else ""
    radius_attr = f' rx="{num(radius)}"' if radius else ""
    filter_attr = ' filter="url(#shadow)"' if shadow else ""
    add(
        f'<rect x="{num(x)}" y="{num(y)}" width="{num(width)}" height="{num(height)}"'
        f'{radius_attr} fill="{fill}"{stroke_attr}{filter_attr}/>'
    )


def line(x1: float, y1: float, x2: float, y2: float, color: str = GRID, width: float = 1) -> None:
    add(
        f'<path d="M{num(x1)},{num(y1)} L{num(x2)},{num(y2)}" '
        f'stroke="{color}" stroke-width="{num(width)}"/>'
    )


def badge(x: float, y: float, label: str, color: str, fill: str) -> float:
    width = text_width(label, 11.5, bold=True) + 24
    rect(x, y, width, 26, fill, color, 3, 1.2)
    text(x + width / 2, y + 17.5, label, 11.5, color, 700, "middle", spacing=0.4)
    return width


def section_heading(y: float, title: str, subtitle: str) -> None:
    text(MARGIN, y, title, 28, INK, 700)
    text(MARGIN + text_width(title, 28, bold=True) + 18, y - 2, subtitle, 14, MUTED)


# ---------------------------------------------------------------- hero
HERO_Y = 36
HERO_H = 262

rect(MARGIN, HERO_Y, CONTENT_W, HERO_H, "url(#hero)", None, 6, shadow=True)
add(
    f'<path d="M{MARGIN + 820},{HERO_Y} L{MARGIN + CONTENT_W},{HERO_Y} '
    f'L{MARGIN + CONTENT_W},{HERO_Y + 70} L{MARGIN + 900},{HERO_Y + 200} Z" '
    'fill="#FFFFFF" fill-opacity="0.07"/>'
)
text(MARGIN + 44, HERO_Y + 48, "AZURE RETIREMENT READINESS / SUBSCRIPTION SNAPSHOT", 12, "#CFE7FF", 600, spacing=1.6)
text(MARGIN + 44, HERO_Y + 108, "Azure Retirement Readiness", 50, "#FFFFFF", 700)
text(
    MARGIN + 44,
    HERO_Y + 150,
    "Executive view of verified service retirement exposure, runtime support deadlines,",
    17,
    "#FFFFFF",
)
text(MARGIN + 44, HERO_Y + 176, "and remediation actions for one Azure subscription.", 17, "#FFFFFF")

chip_y = HERO_Y + 204
chip_label = "ILLUSTRATIVE EXAMPLE \u2014 SYNTHETIC DATA"
chip_w = text_width(chip_label, 12, bold=True) + 28
rect(MARGIN + 44, chip_y, chip_w, 30, "#FFFFFF", None, 3)
text(MARGIN + 44 + chip_w / 2, chip_y + 20, chip_label, 12, AZURE_DARK, 700, "middle", spacing=0.8)
evidence_label = f"EVIDENCE DATE: {long_date(EVIDENCE_DATE).upper()}"
ev_x = MARGIN + 44 + chip_w + 14
ev_w = text_width(evidence_label, 12, bold=True) + 28
rect(ev_x, chip_y, ev_w, 30, "none", "#FFFFFF", 3, 1.2)
text(ev_x + ev_w / 2, chip_y + 20, evidence_label, 12, "#FFFFFF", 700, "middle", spacing=0.8)

# ---------------------------------------------------------------- KPI tiles
KPI_Y = HERO_Y + HERO_H + 22
KPI_H = 150
KPI_GAP = 20
KPI_W = (CONTENT_W - 3 * KPI_GAP) / 4

kpis = [
    (
        "ARM RESOURCES SCANNED",
        str(RESOURCES_SCANNED),
        "Subscription inventory returned by Azure Resource Graph.",
        AZURE,
    ),
    (
        "NEXT DEADLINE",
        f"{DAYS_TO_DEADLINE}d",
        f".NET 8 support in Azure Functions ends {long_date(DOTNET8_FUNCTIONS_EOS)} for orders-api.",
        RED,
    ),
    (
        "VALIDATE NOW",
        str(VALIDATE_NOW),
        f"{len(BING_ACCOUNTS)} Bing grounding account and {len(BOT_RESOURCES)} Azure Bot Service resources.",
        AMBER,
    ),
    (
        "LEGACY ARM TYPES",
        str(LEGACY_ARM_TYPES),
        "No classic Compute, Storage, or Network resource types found.",
        GREEN,
    ),
]
for index, (label, value, detail, accent) in enumerate(kpis):
    x = MARGIN + index * (KPI_W + KPI_GAP)
    rect(x, KPI_Y, KPI_W, KPI_H, PANEL, BORDER, 4, shadow=True)
    rect(x, KPI_Y, KPI_W, 5, accent, None)
    text(x + 22, KPI_Y + 36, label, 13, MUTED, 700, spacing=0.9)
    text(x + 22, KPI_Y + 88, value, 46, accent if accent != GREEN else AZURE, 700)
    paragraph(x + 22, KPI_Y + 114, detail, 13, KPI_W - 44, MUTED, 1.45)

# ---------------------------------------------------------------- retirement queue
QUEUE_HEAD_Y = KPI_Y + KPI_H + 62
section_heading(QUEUE_HEAD_Y, "Retirement Queue", "Prioritized by verified lifecycle dates and configuration evidence")

TABLE_Y = QUEUE_HEAD_Y + 24
TABLE_W = 916
SIDE_X = MARGIN + TABLE_W + 20
SIDE_W = CONTENT_W - TABLE_W - 20
COL_PRI = 186
COL_ACT = 228
COL_DETAIL = TABLE_W - COL_PRI - COL_ACT
DETAIL_X = MARGIN + COL_PRI + 20
DETAIL_W = COL_DETAIL - 40
ACT_X = MARGIN + COL_PRI + COL_DETAIL + 16

queue = [
    {
        "priority": ("P0", "action required"),
        "category": ["Function", "runtime"],
        "resource": "orders-api",
        "title": " \u2014 Azure Functions Flex Consumption",
        "body": (
            "Linux Flex Consumption app on the .NET 8 isolated worker model. Azure Functions support "
            f"for .NET 8 ends {long_date(DOTNET8_FUNCTIONS_EOS)}, {DAYS_TO_DEADLINE} days after the "
            "evidence date. Upgrade to .NET 10 isolated (supported until "
            f"{long_date(DOTNET10_FUNCTIONS_EOS)}) and complete functional, scale, and rollback "
            "validation before the deadline."
        ),
        "badge": (f"REMEDIATE BY {short_date(DOTNET8_FUNCTIONS_EOS).upper()}, {DOTNET8_FUNCTIONS_EOS.year}", RED, RED_LIGHT),
        "link": ["Functions supported", "languages"],
    },
    {
        "priority": ("P1", "validation required"),
        "category": ["Bing", "grounding"],
        "resource": BING_ACCOUNTS[0],
        "title": " \u2014 Grounding with Bing Custom Search",
        "body": (
            "Microsoft.Bing/accounts resource on the documented successor path for the Bing Search "
            f"APIs, which retired {long_date(BING_SEARCH_APIS_RETIRED)}. Confirm the application no "
            "longer calls retired Bing Search endpoints, then validate response contracts, quota "
            "behavior, and cost."
        ),
        "badge": ("VALIDATE WORKLOAD", AMBER, AMBER_LIGHT),
        "link": ["Bing Search APIs", "retirement notice"],
    },
    {
        "priority": ("P1", "code assessment"),
        "category": ["Bot services"],
        "resource": None,
        "title": f"{len(BOT_RESOURCES)} Azure Bot Service resources",
        "mono_line": ", ".join(BOT_RESOURCES),
        "body": (
            "Channels: Web Chat, Direct Line, and Microsoft Teams. The Bot Framework SDK is archived "
            "and its support tickets are no longer serviced as of "
            f"{long_date(BOT_FRAMEWORK_SDK_SUPPORT_END)}. Azure Resource Manager cannot show which "
            "SDK each backend uses; assess source code and plan moves to the Microsoft 365 Agents "
            "SDK where needed."
        ),
        "badge": ("ASSESS SOURCE CODE", AMBER, AMBER_LIGHT),
        "link": ["Bot Framework SDK", "status"],
    },
    {
        "priority": ("P2", "no migration indicated"),
        "category": ["Observability"],
        "resource": "orders-insights",
        "title": " \u2014 Application Insights",
        "body": (
            "Workspace-based Application Insights (IngestionMode: LogAnalytics) linked to a Log "
            "Analytics workspace. No classic Application Insights resource was found, so no "
            "classic-resource migration is indicated."
        ),
        "badge": ("NO ACTION REQUIRED", GREEN, GREEN_LIGHT),
        "link": ["Workspace-based", "migration guide"],
    },
]

row_y = TABLE_Y
row_layout = []
for item in queue:
    body_lines = wrap(item["body"], 13.5, DETAIL_W)
    content_h = 64 + (24 if item.get("mono_line") else 0) + (len(body_lines) - 1) * 20.5 + 24
    row_h = max(content_h, 140)
    row_layout.append((row_y, row_h, body_lines))
    row_y += row_h
TABLE_H = row_y - TABLE_Y


def draw_table() -> None:
    rect(MARGIN, TABLE_Y, TABLE_W, TABLE_H, PANEL, BORDER, 0, shadow=True)
    rect(MARGIN, TABLE_Y, TABLE_W, 4, AZURE, None)
    line(MARGIN + COL_PRI, TABLE_Y + 4, MARGIN + COL_PRI, TABLE_Y + TABLE_H)
    line(MARGIN + COL_PRI + COL_DETAIL, TABLE_Y + 4, MARGIN + COL_PRI + COL_DETAIL, TABLE_Y + TABLE_H)

    for item, (y, row_h, body_lines) in zip(queue, row_layout):
        if y != TABLE_Y:
            line(MARGIN, y, MARGIN + TABLE_W, y)
        level, state = item["priority"]
        level_color = item["badge"][1]
        text(MARGIN + 18, y + 31, level, 15, level_color, 700, mono=True)
        text(MARGIN + 18, y + 50, state, 11.5, AZURE, mono=True)
        for index, word in enumerate(item["category"]):
            text(MARGIN + 18, y + 84 + index * 27, word, 23, INK, 700)

        title_y = y + 34
        if item["resource"]:
            add(
                f'<text x="{num(DETAIL_X)}" y="{num(title_y)}" font-size="17" fill="{INK}" font-weight="700">'
                f'<tspan font-family="{MONO}">{esc(item["resource"])}</tspan>{esc(item["title"])}</text>'
            )
        else:
            text(DETAIL_X, title_y, item["title"], 17, INK, 700)
        body_y = title_y + 26
        if item.get("mono_line"):
            text(DETAIL_X, body_y, item["mono_line"], 13, INK, mono=True)
            body_y += 24
        for index, body_line in enumerate(body_lines):
            text(DETAIL_X, body_y + index * 20.5, body_line, 13.5, MUTED)

        label, color, fill = item["badge"]
        badge(ACT_X, y + 18, label, color, fill)
        for index, link_line in enumerate(item["link"]):
            text(ACT_X, y + 82 + index * 19, link_line, 13.5, LINK, 600, underline=True)


# Subscription context
side_items = [
    ("SUBSCRIPTION NAME", ["Contoso-Platform-Production"], False),
    ("SUBSCRIPTION ID", ["00000000-0000-0000-", "0000-000000000000"], True),
    ("DIRECT RBAC OWNER", ["Platform Operations Team", "platform-operations@contoso.example"], False),
]
note = (
    "Owner information reflects direct subscription-scope RBAC assignments only. Inherited "
    "management-group assignments are outside this assessment."
)
note_lines = wrap(note, 12.5, SIDE_W - 44)
sy = TABLE_Y + 76
side_layout = []
for label, values, mono in side_items:
    side_layout.append((sy, label, values, mono))
    sy += 22 + len(values) * 21 + 20
CONTEXT_H = sy - TABLE_Y + (len(note_lines) - 1) * 19 + 26

rect(SIDE_X, TABLE_Y, SIDE_W, CONTEXT_H, AZURE_LIGHT, "#A9CCEB", 0)
rect(SIDE_X, TABLE_Y, SIDE_W, 4, AZURE, None)
text(SIDE_X + 22, TABLE_Y + 40, "Subscription Context", 20, AZURE_DARK, 700)
for y, label, values, mono in side_layout:
    text(SIDE_X + 22, y, label, 11.5, AZURE, 600, mono=True, spacing=0.6)
    for value_index, value in enumerate(values):
        text(SIDE_X + 22, y + 22 + value_index * 21, value, 14, INK, 700, mono=mono)
    rule_y = y + 22 + (len(values) - 1) * 21 + 16
    line(SIDE_X + 22, rule_y, SIDE_X + SIDE_W - 22, rule_y, "#BCD6EE")
for index, note_line in enumerate(note_lines):
    text(SIDE_X + 22, sy + 4 + index * 19, note_line, 12.5, MUTED)

# Lifecycle timeline
timeline = [
    (BING_SEARCH_APIS_RETIRED, "Bing Search APIs retired", "PAST", MUTED),
    (BOT_FRAMEWORK_SDK_SUPPORT_END, "Bot Framework SDK support tickets end", "PAST", MUTED),
    (EVIDENCE_DATE, "Evidence date for this snapshot", "DAY 0", AZURE),
    (DOTNET8_FUNCTIONS_EOS, ".NET 8 support ends in Azure Functions", f"IN {DAYS_TO_DEADLINE} DAYS", RED),
    (DOTNET10_FUNCTIONS_EOS, ".NET 10 support ends (upgrade target)", "TARGET", GREEN),
]
TL_Y = TABLE_Y + CONTEXT_H + 18
TL_STEP = 46
tl_content_h = 80 + (len(timeline) - 1) * TL_STEP + 34
side_total = CONTEXT_H + 18 + tl_content_h
if side_total < TABLE_H:
    tl_content_h += TABLE_H - side_total
elif side_total > TABLE_H:
    extra = (side_total - TABLE_H) / len(row_layout)
    row_layout = [
        (row_y + index * extra, row_h + extra, row_lines)
        for index, (row_y, row_h, row_lines) in enumerate(row_layout)
    ]
    TABLE_H = side_total
SIDE_H = CONTEXT_H + 18 + tl_content_h

rect(SIDE_X, TL_Y, SIDE_W, tl_content_h, PANEL, BORDER, 0, shadow=True)
rect(SIDE_X, TL_Y, SIDE_W, 4, AZURE_DARK, None)
text(SIDE_X + 22, TL_Y + 38, "Lifecycle timeline", 18, INK, 700)
dot_x = SIDE_X + 30
first_y = TL_Y + 80
line(dot_x, first_y, dot_x, first_y + (len(timeline) - 1) * TL_STEP, "#B9C7D6", 2)
for index, (when, label, tag, color) in enumerate(timeline):
    y = first_y + index * TL_STEP
    add(f'<circle cx="{num(dot_x)}" cy="{num(y)}" r="6" fill="{color}" stroke="#FFFFFF" stroke-width="2"/>')
    text(dot_x + 20, y - 3, long_date(when), 13.5, INK, 700)
    text(dot_x + 20, y + 16, label, 12.5, MUTED)
    tag_w = text_width(tag, 11, bold=True) + 14
    tag_x = SIDE_X + SIDE_W - 22 - tag_w
    rect(tag_x, y - 17, tag_w, 20, "#FFFFFF", color, 3, 1)
    text(tag_x + tag_w / 2, y - 3, tag, 11, color, 700, "middle")

draw_table()

# ---------------------------------------------------------------- service health banner
BANNER_Y = TABLE_Y + max(TABLE_H, SIDE_H) + 24
banner_text = (
    f"As of {long_date(EVIDENCE_DATE)}, no exportable Microsoft.ResourceHealth/events resources and no "
    "Service Health Activity Log alert were found. This does not prove that no retirement notices "
    "exist; review Service Health in the Azure portal and configure alerting for future notices."
)
banner_lines = wrap("Service Health coverage: " + banner_text, 13.5, CONTENT_W - 48)
BANNER_H = 30 + len(banner_lines) * 21
rect(MARGIN, BANNER_Y, CONTENT_W, BANNER_H, AZURE_LIGHT, None)
rect(MARGIN, BANNER_Y, 5, BANNER_H, AZURE, None)
for index, banner_line in enumerate(banner_lines):
    y = BANNER_Y + 27 + index * 21
    if index == 0 and banner_line.startswith("Service Health coverage:"):
        rest = banner_line[len("Service Health coverage:"):]
        add(
            f'<text x="{num(MARGIN + 24)}" y="{num(y)}" font-size="13.5" fill="{INK}">'
            f'<tspan font-weight="700">Service Health coverage:</tspan>{esc(rest)}</text>'
        )
    else:
        text(MARGIN + 24, y, banner_line, 13.5, INK)

# ---------------------------------------------------------------- migration plan
PLAN_HEAD_Y = BANNER_Y + BANNER_H + 66
section_heading(PLAN_HEAD_Y, "Migration Plan", f"Controlled sequence counted from the evidence date to the {short_date(DOTNET8_FUNCTIONS_EOS)} deadline")


def window(start: int, end: int) -> str:
    return f"DAYS {start}\u2013{end} \u00b7 BY {short_date(EVIDENCE_DATE + timedelta(days=end)).upper()}"


phases = [
    (
        window(0, 7),
        "Establish accountability",
        [
            "Assign an owner and business criticality to orders-api and each bot workload.",
            "Confirm source repositories, release pipelines, and production dependencies.",
            "Inventory Bot Framework SDK packages and channel dependencies.",
        ],
    ),
    (
        window(8, 21),
        "Implement modernization",
        [
            "Retarget orders-api from .NET 8 to the .NET 10 isolated worker.",
            "Plan Agents SDK moves for any bot backend still on the Bot Framework SDK.",
            "Run representative Bing grounding requests, including error handling and quotas.",
        ],
    ),
    (
        window(22, 35),
        "Validate readiness",
        [
            "Complete functional, cold-start, scale, and integration tests for the Function.",
            "Validate Teams, Web Chat, and Direct Line conversations for each bot.",
            "Compare grounding response quality, citations, latency, limits, and cost.",
        ],
    ),
    (
        window(36, DAYS_TO_DEADLINE),
        "Deploy with control",
        [
            "Canary the Function release and keep a validated rollback artifact.",
            "Deploy bot backend changes progressively by channel.",
            "Remove superseded keys, SDKs, and endpoints only after telemetry confirms stability.",
        ],
    ),
]
PLAN_Y = PLAN_HEAD_Y + 24
PLAN_GAP = 16
PLAN_W = (CONTENT_W - 3 * PLAN_GAP) / 4
plan_bottoms = []
plan_sections: list[str] = []
for index, (label, title, items) in enumerate(phases):
    x = MARGIN + index * (PLAN_W + PLAN_GAP)
    marker = len(body)
    text(x + 20, PLAN_Y + 32, label, 11.5, AZURE, 600, mono=True)
    text(x + 20, PLAN_Y + 62, title, 19, INK, 700)
    bottom = bullets(x + 20, PLAN_Y + 94, items, 13.5, PLAN_W - 40, 9)
    plan_bottoms.append(bottom)
    plan_sections.extend(body[marker:])
    del body[marker:]
PLAN_H = max(plan_bottoms) - PLAN_Y + 26
for index in range(4):
    x = MARGIN + index * (PLAN_W + PLAN_GAP)
    rect(x, PLAN_Y, PLAN_W, PLAN_H, PANEL, BORDER, 0, shadow=True)
    rect(x, PLAN_Y, PLAN_W, 4, [AZURE, "#2B88D8", "#0099BC", AZURE_DARK][index], None)
body.extend(plan_sections)

# ---------------------------------------------------------------- governance and evidence
LOWER_Y = PLAN_Y + PLAN_H + 40
GOV_W = 680
EVD_X = MARGIN + GOV_W + 20
EVD_W = CONTENT_W - GOV_W - 20

gov_items = [
    "Review Azure Service Health retirement notices scoped to this subscription.",
    f"Confirm orders-api runs on the .NET 10 isolated worker before {long_date(DOTNET8_FUNCTIONS_EOS)}.",
    "Confirm bot backend SDKs and accountable owners for each external or AI-project endpoint.",
    "Monitor Bing grounding telemetry, usage limits, and cost.",
    "Re-verify every lifecycle date against Microsoft documentation on each refresh.",
]
sources = [
    "Azure Functions supported languages",
    ".NET and .NET Core support policy",
    "Migrate Functions apps to the isolated worker model",
    "Bing Search APIs retirement announcement",
    "What's new in the Bot Framework SDK",
    "Migrate to workspace-based Application Insights",
    "Azure Service Health overview",
]
evidence_intro = (
    "Inventory facts come from Azure Resource Graph. Service Health was checked on "
    f"{long_date(EVIDENCE_DATE)}. Each lifecycle date was verified against Microsoft documentation:"
)

marker = len(body)
text(MARGIN + 26, LOWER_Y + 38, "GOVERNANCE AND FOLLOW-UP", 12, MUTED, 700, spacing=1.2)
text(MARGIN + 26, LOWER_Y + 74, "Ongoing readiness controls", 27, INK, 700)
gov_bottom = bullets(MARGIN + 26, LOWER_Y + 110, gov_items, 14.5, GOV_W - 52, 12)
gov_parts = body[marker:]
del body[marker:]

marker = len(body)
text(EVD_X + 26, LOWER_Y + 44, "Evidence & sources", 25, "#FFFFFF", 700)
ey = paragraph(EVD_X + 26, LOWER_Y + 76, evidence_intro, 13.5, EVD_W - 52, "#E3EEF9", 1.5)
ey += 22
for index, source in enumerate(sources):
    text(EVD_X + 26, ey + index * 24, source, 13.5, LINK_ON_DARK, 400, underline=True)
evd_bottom = ey + (len(sources) - 1) * 24
evd_parts = body[marker:]
del body[marker:]

LOWER_H = max(gov_bottom, evd_bottom) - LOWER_Y + 30
rect(MARGIN, LOWER_Y, GOV_W, LOWER_H, PANEL, BORDER, 0, shadow=True)
rect(MARGIN, LOWER_Y, GOV_W, 4, AZURE, None)
body.extend(gov_parts)
rect(EVD_X, LOWER_Y, EVD_W, LOWER_H, NAVY, None, 0, shadow=True)
body.extend(evd_parts)

FOOTER_Y = LOWER_Y + LOWER_H + 34
text(
    MARGIN,
    FOOTER_Y,
    "Illustrative example \u2014 subscription identity, owners, resource names, and counts are synthetic. "
    f"Day counts are calculated from the {long_date(EVIDENCE_DATE)} evidence date.",
    12.5,
    MUTED,
)
HEIGHT = int(FOOTER_Y + 30)

# ---------------------------------------------------------------- document
header: list[str] = []
header.append(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
    f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" '
    'aria-labelledby="dashboard-title dashboard-desc" '
    f'font-family="{SANS}">'
)
header.append('<title id="dashboard-title">Illustrative Azure Retirement Readiness dashboard</title>')
header.append(
    '<desc id="dashboard-desc">'
    + esc(
        "Illustrative example with synthetic data for the Contoso-Platform-Production subscription, "
        f"evidence date {long_date(EVIDENCE_DATE)}. KPI tiles: {RESOURCES_SCANNED} ARM resources "
        f"scanned; next deadline in {DAYS_TO_DEADLINE} days because Azure Functions support for "
        f".NET 8 ends {long_date(DOTNET8_FUNCTIONS_EOS)}; {VALIDATE_NOW} resources to validate now "
        f"({len(BING_ACCOUNTS)} Bing grounding account and {len(BOT_RESOURCES)} Azure Bot Service "
        f"resources); {LEGACY_ARM_TYPES} legacy ARM types. Retirement queue: P0 orders-api, an Azure "
        "Functions Flex Consumption app on .NET 8 isolated, to be upgraded to .NET 10 isolated by "
        f"{long_date(DOTNET8_FUNCTIONS_EOS)}; P1 web-grounding, a Grounding with Bing Custom Search "
        f"resource to validate after the Bing Search APIs retired {long_date(BING_SEARCH_APIS_RETIRED)}; "
        f"P1 three Azure Bot Service resources ({', '.join(BOT_RESOURCES)}) needing source-code "
        "assessment because Bot Framework SDK support tickets are no longer serviced as of "
        f"{long_date(BOT_FRAMEWORK_SDK_SUPPORT_END)}; P2 orders-insights, workspace-based Application "
        "Insights with no migration required. The direct subscription Owner is the Platform Operations "
        "Team, platform-operations@contoso.example. No exportable Service Health events or Service "
        "Health alerts were found, which is reported as a coverage gap. A four-phase migration plan "
        f"runs from day 0 to day {DAYS_TO_DEADLINE}."
    )
    + "</desc>"
)
header.append(
    '''<defs>
  <linearGradient id="hero" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#003A70"/>
    <stop offset="1" stop-color="#0063B1"/>
  </linearGradient>
  <filter id="shadow" x="-5%" y="-5%" width="110%" height="115%">
    <feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#1B3A57" flood-opacity="0.10"/>
  </filter>
</defs>'''
)
header.append(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{CANVAS}"/>')

OUTPUT.write_text("\n".join(header + body + ["</svg>"]) + "\n", encoding="utf-8", newline="\n")
print("written", OUTPUT, OUTPUT.stat().st_size, "bytes", f"{WIDTH}x{HEIGHT}")

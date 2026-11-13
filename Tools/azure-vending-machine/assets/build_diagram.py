import base64
import html
from pathlib import Path

BASE = Path(__file__).resolve().parent
ICONS = BASE / "icons"

WIDTH = 1280
HEIGHT = 820

BG = "#0F1115"
PANEL = "#171A21"
NODE = "#1E222B"
LINE = "#30363D"
TEXT = "#F0F3F6"
SUBTEXT = "#B1BAC4"
BLUE = "#58A6FF"
GREEN = "#3FB950"
AMBER = "#D29922"
RED = "#F85149"
PURPLE = "#A371F7"

parts = []
add = parts.append


def icon(name):
    data = base64.b64encode((ICONS / f"{name}.svg").read_bytes()).decode()
    return f"data:image/svg+xml;base64,{data}"


def stage(y, number, title, subtitle, color):
    add(
        f'<rect x="40" y="{y}" width="1200" height="190" rx="18" '
        f'fill="{PANEL}" stroke="{LINE}" stroke-width="1.5"/>'
    )
    add(f'<rect x="40" y="{y}" width="8" height="190" rx="4" fill="{color}"/>')
    add(f'<circle cx="75" cy="{y + 30}" r="15" fill="{color}"/>')
    add(
        f'<text x="75" y="{y + 35}" text-anchor="middle" fill="{BG}" '
        f'font-size="14" font-weight="800">{number}</text>'
    )
    add(
        f'<text x="100" y="{y + 27}" fill="{TEXT}" font-size="16" '
        f'font-weight="700" letter-spacing="1.4">{html.escape(title)}</text>'
    )
    add(
        f'<text x="100" y="{y + 49}" fill="{SUBTEXT}" font-size="12.5">'
        f'{html.escape(subtitle)}</text>'
    )


def box(x, y, width, icon_name, title, lines, color, badge=None):
    add(
        f'<g filter="url(#shadow)"><rect x="{x}" y="{y}" width="{width}" '
        f'height="105" rx="13" fill="{NODE}" stroke="{color}" '
        f'stroke-width="1.8"/></g>'
    )
    add(
        f'<image href="{icon(icon_name)}" x="{x + 18}" y="{y + 20}" '
        f'width="34" height="34"/>'
    )
    add(
        f'<text x="{x + 66}" y="{y + 31}" fill="{TEXT}" font-size="16" '
        f'font-weight="700">{html.escape(title)}</text>'
    )
    for index, line in enumerate(lines):
        add(
            f'<text x="{x + 66}" y="{y + 56 + index * 20}" fill="{SUBTEXT}" '
            f'font-size="12.5">{html.escape(line)}</text>'
        )
    if badge:
        badge_width = max(82, len(badge) * 7 + 20)
        badge_x = x + width - badge_width - 12
        add(
            f'<rect x="{badge_x}" y="{y + 12}" width="{badge_width}" '
            f'height="22" rx="11" fill="{color}" fill-opacity="0.18" '
            f'stroke="{color}" stroke-width="1"/>'
        )
        add(
            f'<text x="{badge_x + badge_width / 2}" y="{y + 27}" '
            f'text-anchor="middle" fill="{color}" font-size="10.5" '
            f'font-weight="700">{html.escape(badge)}</text>'
        )


def arrow(path, color=BLUE, marker="arrow", dash=None):
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    add(
        f'<path d="{path}" fill="none" stroke="{color}" stroke-width="2.5" '
        f'stroke-linecap="round" stroke-linejoin="round" '
        f'marker-end="url(#{marker})"{dash_attr}/>'
    )


add(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
    f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" '
    f'aria-labelledby="workflow-title workflow-desc" '
    f'font-family="Segoe UI, Inter, Helvetica, Arial, sans-serif">'
)
add(
    '<title id="workflow-title">Azure Vending Machine governed workflow</title>'
)
add(
    '<desc id="workflow-desc">Seven-step flow from a request in Microsoft Teams '
    'through deterministic validation, explicit confirmation, ServiceNow human '
    'approval, reviewed source-control change, the only Azure write scope in an '
    'Azure Verified Modules pipeline, and status returned to Teams. Rejected or '
    'failed requests return status without deployment.</desc>'
)
add(
    f'''<defs>
  <filter id="shadow" x="-20%" y="-25%" width="140%" height="150%">
    <feDropShadow dx="0" dy="4" stdDeviation="5" flood-color="#000" flood-opacity="0.38"/>
  </filter>
  <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
    <path d="M0,0 L10,5 L0,10 Z" fill="{BLUE}"/>
  </marker>
  <marker id="arrow-green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
    <path d="M0,0 L10,5 L0,10 Z" fill="{GREEN}"/>
  </marker>
  <marker id="arrow-red" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
    <path d="M0,0 L10,5 L0,10 Z" fill="{RED}"/>
  </marker>
</defs>'''
)
add(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{BG}"/>')
add(
    f'<text x="48" y="40" fill="{TEXT}" font-size="28" font-weight="750">'
    "Azure Subscription Vending</text>"
)
add(
    f'<text x="48" y="66" fill="{SUBTEXT}" font-size="14">'
    "Conversational request, human governance, reviewed change, deterministic delivery</text>"
)

stage(
    105,
    "1",
    "REQUEST",
    "The agent gathers and validates intent but has no Azure write access",
    BLUE,
)
stage(
    325,
    "2",
    "GOVERN & REVIEW",
    "Human approval and source-control review are mandatory control gates",
    RED,
)
stage(
    545,
    "3",
    "DELIVER",
    "Only the deterministic AVM pipeline can write to Azure",
    PURPLE,
)

box(
    80,
    165,
    320,
    "microsoft-teams",
    "Request in Teams",
    ["Microsoft Entra SSO", "Bilingual French / English intake"],
    BLUE,
)
box(
    480,
    165,
    320,
    "copilot-studio",
    "Validate & derive configuration",
    ["Copilot Studio + deterministic flow", "CMDB · cost centre · repository access"],
    GREEN,
)
box(
    880,
    165,
    320,
    "microsoft-365",
    "Confirm request",
    ["Adaptive Card summary", "Explicit confirmation required"],
    RED,
    "USER GATE",
)

box(
    230,
    385,
    360,
    "approval-ticket",
    "Approve in ServiceNow",
    ["Human platform approval", "Restricted data → security review"],
    RED,
    "HUMAN GATE",
)
box(
    690,
    385,
    400,
    "github",
    "Create & review pull request",
    ["Re-read Approved · generate azure.yml", "GitHub / Azure DevOps · human merge"],
    AMBER,
    "REVIEW GATE",
)

box(
    230,
    605,
    360,
    "bicep",
    "Deploy with AVM",
    ["Subscription · network · identity/RBAC", "Budget · policy · deterministic pipeline"],
    PURPLE,
    "ONLY AZURE WRITE",
)
box(
    690,
    605,
    400,
    "microsoft-teams",
    "Return status in Teams",
    ["Subscription details · access group", "Next steps · success/failure status"],
    BLUE,
)

arrow("M400,217 H474")
arrow("M800,217 H874")
arrow("M1040,270 V305 H410 V379")
arrow("M590,437 H684")
arrow("M890,490 V525 H410 V599")
arrow("M590,657 H684", color=GREEN, marker="arrow-green")

arrow(
    "M230,437 H20 V750 H890 V716",
    color=RED,
    marker="arrow-red",
    dash="8 6",
)
add(
    f'<text x="50" y="773" fill="{RED}" font-size="12.5" font-weight="650">'
    "Rejected or failed → return status, no deployment</text>"
)

arrow(
    "M1090,657 H1225 V88 H240 V159",
    color=GREEN,
    marker="arrow-green",
    dash="8 6",
)
add(
    f'<text x="940" y="84" fill="{GREEN}" font-size="12.5" '
    f'font-weight="650">Status and next steps returned to Teams</text>'
)

add(
    f'<rect x="770" y="35" width="470" height="36" rx="10" fill="{PANEL}" '
    f'stroke="{LINE}"/>'
)
add(f'<circle cx="790" cy="53" r="5" fill="{RED}"/>')
add(
    f'<text x="802" y="58" fill="{SUBTEXT}" font-size="11.5">'
    "human gate</text>"
)
add(f'<circle cx="882" cy="53" r="5" fill="{AMBER}"/>')
add(
    f'<text x="894" y="58" fill="{SUBTEXT}" font-size="11.5">'
    "reviewed change</text>"
)
add(f'<circle cx="1015" cy="53" r="5" fill="{PURPLE}"/>')
add(
    f'<text x="1027" y="58" fill="{SUBTEXT}" font-size="11.5">'
    "Azure write scope</text>"
)

add("</svg>")

output = BASE / "09-workflow-design.svg"
output.write_text("\n".join(parts) + "\n", encoding="utf-8", newline="\n")
print("written", output, output.stat().st_size, "bytes")

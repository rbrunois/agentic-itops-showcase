import base64
import html
from pathlib import Path

BASE = Path(__file__).resolve().parent
ICONS = BASE / "icons"
OUTPUT = BASE / "fleet-security-signal-board-example.svg"

WIDTH = 1440
HEIGHT = 1020

CANVAS = "#F4F8FC"
INK = "#172B3F"
MUTED = "#526B82"
BORDER = "#B7CCDE"
PANEL = "#FFFFFF"
AZURE = "#005A9E"
AZURE_LIGHT = "#EAF4FF"
TEAL = "#007F87"
TEAL_LIGHT = "#E6F7F8"
PURPLE = "#6246D9"
PURPLE_LIGHT = "#F0EDFF"
AMBER = "#8A5200"
AMBER_LIGHT = "#FFF4D6"
RED = "#C4314B"
RED_LIGHT = "#FCEEF1"
GREEN = "#107C41"
GREEN_LIGHT = "#EAF7EF"
GRID = "#E3EDF5"

ICON_FILES = {
    "arc": "azure-arc.svg",
    "resource_graph": "azure-resource-graph-explorer.svg",
    "monitor": "azure-monitor.svg",
    "update_manager": "azure-update-manager.svg",
    "defender": "microsoft-defender-for-cloud.svg",
    "dashboard": "azure-monitor-dashboard.svg",
    "virtual_machine": "azure-virtual-machine.svg",
}
ICON_URIS = {
    name: (
        "data:image/svg+xml;base64,"
        + base64.b64encode((ICONS / file_name).read_bytes()).decode("ascii")
    )
    for name, file_name in ICON_FILES.items()
}

parts: list[str] = []
add = parts.append
coverage_clip_index = 0


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def text(
    x: float,
    y: float,
    value: str,
    size: float,
    color: str = INK,
    weight: int = 400,
    anchor: str = "start",
) -> None:
    add(
        f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="{color}" '
        f'font-size="{size}" font-weight="{weight}">{esc(value)}</text>'
    )


def rect(
    x: float,
    y: float,
    width: float,
    height: float,
    fill: str,
    stroke: str = BORDER,
    radius: float = 14,
    stroke_width: float = 1.3,
    shadow: bool = False,
) -> None:
    filter_attr = ' filter="url(#shadow)"' if shadow else ""
    add(
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}"'
        f"{filter_attr}/>"
    )


def icon(x: float, y: float, name: str, size: float = 40) -> None:
    add(
        f'<image href="{ICON_URIS[name]}" x="{x}" y="{y}" '
        f'width="{size}" height="{size}"/>'
    )


def chip(
    x: float,
    y: float,
    label: str,
    fill: str,
    color: str,
    width: float,
    height: float = 28,
    size: float = 11,
) -> None:
    rect(x, y, width, height, fill, color, height / 2, 1)
    text(x + width / 2, y + height / 2 + 4, label, size, color, 700, "middle")


def panel(x: float, y: float, width: float, height: float) -> None:
    rect(x, y, width, height, PANEL, BORDER, 16, 1.3, True)


def metric_card(
    x: float,
    title: str,
    value: str,
    detail_lines: list[str],
    icon_name: str,
    accent: str,
) -> None:
    width = 314
    y = 170
    height = 144
    rect(x, y, width, height, PANEL, BORDER, 14, 1.3, True)
    rect(x, y, 7, height, accent, accent, 7, 0)
    icon(x + 22, y + 24, icon_name, 42)
    text(x + 80, y + 40, title, 13, MUTED, 650)
    text(x + 80, y + 83, value, 31, INK, 760)
    for index, line in enumerate(detail_lines):
        text(x + 22, y + 116 + index * 18, line, 11.5, MUTED)


def legend_item(x: float, y: float, label: str, color: str) -> None:
    rect(x, y - 10, 12, 12, color, color, 3, 0)
    text(x + 19, y, label, 11.5, MUTED, 600)


def coverage_row(
    y: float,
    label: str,
    current: int,
    gap: int,
    blocker: int,
) -> None:
    global coverage_clip_index
    total = current + gap + blocker
    bar_x = 220
    bar_width = 400
    bar_height = 26
    current_width = bar_width * current / total
    gap_width = bar_width * gap / total
    blocker_width = bar_width * blocker / total

    text(84, y + 20, label, 13, INK, 700)
    coverage_clip_index += 1
    clip_id = f"coverage-clip-{coverage_clip_index}"
    add(
        f'<clipPath id="{clip_id}"><rect x="{bar_x}" y="{y}" '
        f'width="{bar_width}" height="{bar_height}" rx="8"/></clipPath>'
    )
    rect(bar_x, y, bar_width, bar_height, "#E8EFF5", "#E8EFF5", 8, 0)
    add(f'<g clip-path="url(#{clip_id})">')
    if current_width:
        add(
            f'<rect x="{bar_x}" y="{y}" width="{current_width}" '
            f'height="{bar_height}" fill="{GREEN}"/>'
        )
    if gap_width:
        add(
            f'<rect x="{bar_x + current_width}" y="{y}" width="{gap_width}" '
            f'height="{bar_height}" fill="{AMBER}"/>'
        )
    if blocker_width:
        add(
            f'<rect x="{bar_x + current_width + gap_width}" y="{y}" '
            f'width="{blocker_width}" height="{bar_height}" fill="{RED}"/>'
        )
    add("</g>")

    text(650, y + 18, f"{current} current", 11.3, GREEN, 700)
    text(724, y + 18, f"{gap} gap", 11.3, AMBER, 700)
    text(778, y + 18, f"{blocker} blocked", 11.3, RED, 700)


def exception_row(
    y: float,
    workload: str,
    issue: str,
    environment: str,
    status: str,
    color: str,
    fill: str,
) -> None:
    row_height = 52
    text(890, y + 18, workload, 12.5, INK, 700)
    text(890, y + 38, issue, 11.1, MUTED)
    text(1160, y + 26, environment, 11.5, MUTED)
    chip(1280, y + 9, status, fill, color, 80, 30, 10.5)
    add(
        f'<path d="M884,{y + row_height} H1360" '
        f'stroke="{GRID}" stroke-width="1"/>'
    )


def queue_item(
    y: float,
    number: str,
    title: str,
    detail: str,
    color: str,
    fill: str,
) -> None:
    rect(84, y, 30, 30, fill, color, 15, 1)
    text(99, y + 20, number, 11.5, color, 750, "middle")
    text(132, y + 15, title, 13, INK, 700)
    text(132, y + 36, detail, 11.2, MUTED)


def verification_item(y: float, label: str, icon_name: str, color: str, fill: str) -> None:
    rect(830, y, 42, 36, fill, color, 9, 1)
    icon(839, y + 6, icon_name, 24)
    text(888, y + 23, label, 12.2, INK, 650)


add(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
    f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" '
    'aria-labelledby="dashboard-title dashboard-desc" '
    'font-family="Segoe UI, Inter, Helvetica, Arial, sans-serif">'
)
add(
    '<title id="dashboard-title">Illustrative Fleet Security Signal Board dashboard</title>'
)
add(
    '<desc id="dashboard-desc">Synthetic executive dashboard for an Azure and '
    'Arc-connected hybrid fleet; it is not live telemetry. KPI values are 24 '
    'workload records, 20 with current evidence, 3 coverage gaps, and 1 patch '
    'blocker. Production has 10 current, 1 gap, and 1 blocked workload; '
    'pre-production has 6 current and no gaps or blockers; development has 4 '
    'current, 2 gaps, and no blockers. Priority exceptions are az-vm-app-02, '
    'blocked because VM Agent communication is unavailable in production; '
    'arc-server-03, a production gap because the Azure Arc machine is '
    'disconnected; and development gaps aws-ec2-02 and gcp-ce-01 because no '
    'current patch assessment is available. The remediation queue is to repair '
    'VM Agent communication, reconnect the Azure Arc machine, and run a targeted '
    'patch assessment, all with explicit owner approval. Completion requires a '
    'fresh patch installation result, matching Azure Activity Log evidence, and '
    'healthy guest extension or Azure Arc status.</desc>'
)
add(
    f'''<defs>
  <filter id="shadow" x="-15%" y="-20%" width="130%" height="145%">
    <feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#20435C" flood-opacity="0.11"/>
  </filter>
</defs>'''
)
add(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{CANVAS}"/>')

# Header
add(f'<rect x="0" y="0" width="{WIDTH}" height="118" fill="#FFFFFF"/>')
add(f'<path d="M0,117 H{WIDTH}" stroke="#D7E5F0" stroke-width="1.5"/>')
icon(56, 34, "dashboard", 48)
text(120, 54, "Fleet Security Signal Board", 29, INK, 760)
text(
    120,
    82,
    "Illustrative executive output for Azure and Arc-connected fleet remediation",
    14,
    MUTED,
)
chip(1092, 42, "SYNTHETIC DATA", PURPLE_LIGHT, PURPLE, 132)
chip(1236, 42, "NOT LIVE TELEMETRY", AMBER_LIGHT, AMBER, 164)

# KPI cards
text(56, 150, "Fleet overview", 18, INK, 750)
metric_card(
    56,
    "Workload records",
    "24",
    ["14 Azure · 5 on-premises", "3 AWS · 2 Google Cloud"],
    "arc",
    AZURE,
)
metric_card(
    394,
    "Current evidence",
    "20",
    ["Assessment and management", "evidence returned"],
    "resource_graph",
    GREEN,
)
metric_card(
    732,
    "Coverage gaps",
    "3",
    ["No current assessment or", "disconnected Arc machine"],
    "monitor",
    AMBER,
)
metric_card(
    1070,
    "Patch blocker",
    "1",
    ["Guest update execution", "cannot be verified"],
    "update_manager",
    RED,
)

# Evidence coverage panel
panel(56, 342, 780, 320)
text(84, 378, "Evidence coverage by environment", 18, INK, 750)
text(84, 402, "Current assessment, coverage gaps, and blocked guest operations", 11.7, MUTED)
legend_item(475, 400, "Current", GREEN)
legend_item(565, 400, "Gap", AMBER)
legend_item(628, 400, "Blocked", RED)
coverage_row(452, "Production", 10, 1, 1)
coverage_row(515, "Pre-production", 6, 0, 0)
coverage_row(578, "Development", 4, 2, 0)

# Priority exceptions table
panel(860, 342, 524, 320)
text(888, 378, "Priority exceptions", 18, INK, 750)
text(888, 402, "Targeted follow-up only", 11.7, MUTED)
text(890, 431, "Workload", 11.2, MUTED, 700)
text(1160, 431, "Environment", 11.2, MUTED, 700)
text(1320, 431, "Status", 11.2, MUTED, 700, "middle")
add(f'<path d="M884,440 H1360" stroke="{GRID}" stroke-width="1.2"/>')
exception_row(
    442,
    "az-vm-app-02",
    "VM Agent communication unavailable",
    "Production",
    "BLOCKED",
    RED,
    RED_LIGHT,
)
exception_row(
    494,
    "arc-server-03",
    "Azure Arc machine disconnected",
    "Production",
    "GAP",
    AMBER,
    AMBER_LIGHT,
)
exception_row(
    546,
    "aws-ec2-02",
    "No current patch assessment",
    "Development",
    "GAP",
    AMBER,
    AMBER_LIGHT,
)
exception_row(
    598,
    "gcp-ce-01",
    "No current patch assessment",
    "Development",
    "GAP",
    AMBER,
    AMBER_LIGHT,
)

# Remediation queue
panel(56, 688, 720, 274)
text(84, 724, "Remediation queue", 18, INK, 750)
text(84, 748, "Illustrative actions requiring explicit owner approval", 11.7, MUTED)
queue_item(
    770,
    "1",
    "Repair VM Agent communication",
    "Production · verify agent status before patch retry",
    RED,
    RED_LIGHT,
)
queue_item(
    830,
    "2",
    "Reconnect Azure Arc machine",
    "Production · refresh inventory and assessment evidence",
    AMBER,
    AMBER_LIGHT,
)
queue_item(
    890,
    "3",
    "Run targeted patch assessment",
    "Development · validate scope before scheduling maintenance",
    AZURE,
    AZURE_LIGHT,
)

# Guest-level verification
panel(800, 688, 584, 274)
icon(828, 716, "defender", 46)
text(890, 744, "Guest-level verification standard", 18, INK, 750)
text(828, 776, "Control-plane acceptance alone is not a completed patch operation.", 11.7, MUTED)
verification_item(
    796,
    "Fresh patch installation result",
    "update_manager",
    PURPLE,
    PURPLE_LIGHT,
)
verification_item(
    844,
    "Matching Azure Activity Log evidence",
    "monitor",
    AZURE,
    AZURE_LIGHT,
)
verification_item(
    892,
    "Healthy guest extension or Azure Arc status",
    "arc",
    TEAL,
    TEAL_LIGHT,
)

text(
    56,
    996,
    "All values, workload names, states, and actions are synthetic and must be replaced with evidence from the selected scope.",
    11.5,
    MUTED,
)
add("</svg>")

OUTPUT.write_text("\n".join(parts) + "\n", encoding="utf-8", newline="\n")
print("written", OUTPUT, OUTPUT.stat().st_size, "bytes")

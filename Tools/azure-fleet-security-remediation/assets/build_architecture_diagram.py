import base64
import html
from pathlib import Path

BASE = Path(__file__).resolve().parent
ICONS = BASE / "icons"
OUTPUT = BASE / "azure-fleet-remediation-architecture.svg"

ICON_FILES = {
    "agent": "azure-bot-services.svg",
    "azure": "azure.svg",
    "resource_graph": "azure-resource-graph-explorer.svg",
    "defender_for_cloud": "microsoft-defender-for-cloud.svg",
    "monitor": "azure-monitor.svg",
    "update_manager": "azure-update-manager.svg",
    "arc": "azure-arc.svg",
    "owner": "azure-users.svg",
    "dashboard": "azure-monitor-dashboard.svg",
    "virtual_machine": "azure-virtual-machine.svg",
    "arc_machine": "azure-arc-machines.svg",
    "ec2": "aws-ec2.svg",
    "compute_engine": "gcp-compute-engine.svg",
}
ICON_URIS = {
    name: f"data:image/svg+xml;base64,{base64.b64encode((ICONS / file_name).read_bytes()).decode('ascii')}"
    for name, file_name in ICON_FILES.items()
}

WIDTH = 1440
HEIGHT = 900

CANVAS = "#F5F9FD"
INK = "#1A2B3C"
MUTED = "#5C6F82"
BORDER = "#B8CCDD"
PANEL = "#FFFFFF"
AZURE = "#0078D4"
AZURE_DARK = "#005A9E"
AZURE_LIGHT = "#EAF4FF"
TEAL = "#008C95"
TEAL_LIGHT = "#E6F7F8"
PURPLE = "#6B4CD8"
PURPLE_LIGHT = "#F0EDFF"
AMBER = "#C77C00"
AMBER_LIGHT = "#FFF4D6"
RED = "#C4314B"
RED_LIGHT = "#FCEEF1"
GREEN = "#107C41"
GREEN_LIGHT = "#EAF7EF"
GRAY_LIGHT = "#F6F8FA"

parts: list[str] = []
add = parts.append


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def text(x: float, y: float, value: str, size: float, color: str = INK, weight: int = 400, anchor: str = "start") -> None:
    add(
        f'<text x="{x}" y="{y}" text-anchor="{anchor}" fill="{color}" '
        f'font-size="{size}" font-weight="{weight}">{esc(value)}</text>'
    )


def rounded_rect(x: float, y: float, width: float, height: float, fill: str, stroke: str = BORDER, radius: float = 14, stroke_width: float = 1.5) -> None:
    add(
        f'<rect x="{x}" y="{y}" width="{width}" height="{height}" rx="{radius}" '
        f'fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}"/>'
    )


def arrow(path: str, color: str, marker: str = "arrow", dash: str | None = None, width: float = 2.5) -> None:
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    add(
        f'<path d="{path}" fill="none" stroke="{color}" stroke-width="{width}" '
        f'stroke-linecap="round" stroke-linejoin="round" marker-end="url(#{marker})"{dash_attr}/>'
    )


def chip(x: float, y: float, label: str, fill: str, color: str, width: float) -> None:
    rounded_rect(x, y, width, 28, fill, color, 14, 1)
    text(x + width / 2, y + 19, label, 11, color, 700, "middle")


def product_icon(x: float, y: float, name: str, size: float = 42) -> None:
    add(f'<image href="{ICON_URIS[name]}" x="{x}" y="{y}" width="{size}" height="{size}"/>')


def service_card(x: float, y: float, width: float, title_lines: list[str], subtitle: str, icon: str) -> None:
    rounded_rect(x, y, width, 115, PANEL, BORDER, 12, 1.2)
    product_icon(x + 14, y + 15, icon)
    for index, line in enumerate(title_lines):
        text(x + 66, y + 37 + index * 16, line, 12.5, INK, 700)
    text(x + 14, y + 94, subtitle, 10.5, MUTED, 400)


def estate_card(x: float, y: float, width: float, title: str, subtitle: str, detail: str, icon: str) -> None:
    rounded_rect(x, y, width, 132, PANEL, BORDER, 12, 1.3)
    product_icon(x + 16, y + 18, icon)
    text(x + 68, y + 42, title, 15, INK, 700)
    text(x + 68, y + 63, subtitle, 11.5, MUTED, 400)
    text(x + 16, y + 99, detail, 11.5, MUTED, 400)
    chip(x + 16, y + 108, "ARC-ENABLED", TEAL_LIGHT, TEAL, 110)


add(
    f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
    f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" '
    'aria-labelledby="architecture-title architecture-desc" '
    'font-family="Segoe UI, Inter, Helvetica, Arial, sans-serif">'
)
add('<title id="architecture-title">Azure Fleet Security and Patch Remediation hybrid and multicloud architecture</title>')
add(
    '<desc id="architecture-desc">Architecture diagram showing Azure SRE Agent gathering '
    'read-only evidence from Azure management services, Azure Arc federating Azure, '
    'on-premises, AWS, and GCP machines in production, pre-production, and development '
    'environments, an owner approving targeted remediation, Azure Update Manager applying '
    'approved guest updates, and the agent publishing dashboard evidence.</desc>'
)
add(
    f'''<defs>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
    <feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#20435C" flood-opacity="0.14"/>
  </filter>
  <marker id="arrow-blue" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
    <path d="M0,0 L10,5 L0,10 Z" fill="{AZURE}"/>
  </marker>
  <marker id="arrow-teal" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
    <path d="M0,0 L10,5 L0,10 Z" fill="{TEAL}"/>
  </marker>
  <marker id="arrow-purple" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
    <path d="M0,0 L10,5 L0,10 Z" fill="{PURPLE}"/>
  </marker>
</defs>'''
)
add(f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{CANVAS}"/>')
add(f'<rect x="0" y="0" width="{WIDTH}" height="94" fill="#FFFFFF"/>')
add(f'<path d="M0,93 H{WIDTH}" stroke="#D7E5F0" stroke-width="1.5"/>')
text(50, 43, "Azure Fleet Security & Patch Remediation", 29, INK, 750)
text(50, 69, "Hybrid and multicloud architecture: evidence, approval, Arc federation, and guest patch verification", 14, MUTED, 400)
chip(918, 30, "READ-ONLY EVIDENCE", AZURE_LIGHT, AZURE, 152)
chip(1080, 30, "ARC FEDERATION", TEAL_LIGHT, TEAL, 130)
chip(1220, 30, "APPROVED REMEDIATION", PURPLE_LIGHT, PURPLE, 170)

rounded_rect(50, 132, 258, 156, PANEL, AZURE, 16, 1.8)
product_icon(74, 160, "agent")
text(132, 185, "Azure SRE Agent", 18, INK, 750)
text(74, 219, "Correlates fleet inventory, security,", 12.5, MUTED)
text(74, 239, "patch, agent, and activity evidence.", 12.5, MUTED)
chip(74, 252, "READ-ONLY BY DEFAULT", AZURE_LIGHT, AZURE, 160)

rounded_rect(342, 118, 716, 370, AZURE_LIGHT, AZURE, 18, 1.8)
product_icon(368, 145, "azure", 30)
text(410, 166, "Azure management plane", 19, AZURE_DARK, 750)
text(368, 191, "Centralized evidence, policy, orchestration, and Arc-connected machine management", 12.5, MUTED)

service_card(370, 220, 154, ["Azure Resource", "Graph"], "Inventory and scope", "resource_graph")
service_card(540, 220, 154, ["Defender for", "Cloud"], "Security posture", "defender_for_cloud")
service_card(710, 220, 154, ["Azure Monitor +", "Activity Log"], "Operation evidence", "monitor")
service_card(880, 220, 154, ["Azure Update", "Manager"], "Approved patching", "update_manager")

rounded_rect(510, 365, 380, 92, PANEL, TEAL, 14, 1.6)
product_icon(532, 390, "arc")
text(592, 410, "Azure Arc", 16, INK, 750)
text(592, 431, "Connected-machine inventory and guest telemetry", 11.5, MUTED)
text(592, 448, "Extension status and policy context", 11.5, MUTED)
chip(746, 381, "HYBRID CONTROL PLANE", TEAL_LIGHT, TEAL, 122)

rounded_rect(1102, 132, 286, 140, PANEL, AMBER, 16, 1.7)
product_icon(1126, 156, "owner")
text(1184, 181, "Service owner", 17, INK, 750)
text(1126, 215, "Reviews remediation scope, impact,", 12, MUTED)
text(1126, 234, "maintenance window, and reboot policy.", 12, MUTED)
chip(1126, 246, "EXPLICIT APPROVAL", AMBER_LIGHT, AMBER, 135)

rounded_rect(1102, 320, 286, 168, PANEL, GREEN, 16, 1.7)
product_icon(1126, 348, "dashboard")
text(1184, 373, "Evidence outputs", 17, INK, 750)
text(1126, 406, "Fleet Security Signal Board", 12, MUTED, 600)
text(1126, 427, "Fleet Remediation Ledger", 12, MUTED, 600)
text(1126, 455, "Static or live reporting depends on", 11.5, MUTED)
text(1126, 473, "available runtime data access.", 11.5, MUTED)

rounded_rect(50, 535, 1338, 315, PANEL, TEAL, 18, 1.8)
text(80, 571, "Arc-connected hybrid estate", 20, INK, 750)
text(80, 594, "The same assessment and approval model can be scoped by cloud and environment when machines are Arc-enabled.", 12.5, MUTED)
chip(812, 555, "PRODUCTION", PURPLE_LIGHT, PURPLE, 110)
chip(932, 555, "PRE-PRODUCTION", AZURE_LIGHT, AZURE, 135)
chip(1077, 555, "DEVELOPMENT", GREEN_LIGHT, GREEN, 110)
text(812, 614, "Policies, maintenance windows, and approvals remain explicit per environment.", 11.5, MUTED)

estate_card(80, 660, 282, "Azure", "Virtual Machines and VMSS", "Azure-hosted workloads", "virtual_machine")
estate_card(395, 660, 282, "On premises", "Physical and VMware servers", "Datacenter-connected workloads", "arc_machine")
estate_card(710, 660, 282, "AWS", "EC2 instances", "Arc-enabled cloud workloads", "ec2")
estate_card(1025, 660, 282, "Google Cloud", "Compute Engine instances", "Arc-enabled cloud workloads", "compute_engine")

arrow("M308,210 H342", AZURE, "arrow-blue")
text(315, 197, "query and correlate", 10.5, AZURE, 600)
arrow("M1058,420 H1096", GREEN, "arrow-teal")
text(1058, 407, "publish", 10.5, GREEN, 600)
arrow("M1102,202 H1052 V208 H957 V214", AMBER, "arrow-blue", "6 5", 2.2)
text(1010, 195, "approved targets", 10.5, AMBER, 600)
arrow("M700,457 V510 H920 V530", TEAL, "arrow-teal", "7 5", 2.6)
text(720, 500, "Arc connection, inventory, and guest telemetry", 10.5, TEAL, 600)
arrow("M956,335 V510 H1215 V530", PURPLE, "arrow-purple", "7 5", 2.6)
text(990, 500, "approved guest patch operations", 10.5, PURPLE, 600)

text(80, 829, "Azure Arc extends the Azure control plane to connected machines; each cloud and environment remains independently scoped and approved.", 11.5, MUTED, 400)
add("</svg>")

OUTPUT.write_text("\n".join(parts) + "\n", encoding="utf-8", newline="\n")
print("written", OUTPUT, OUTPUT.stat().st_size, "bytes")

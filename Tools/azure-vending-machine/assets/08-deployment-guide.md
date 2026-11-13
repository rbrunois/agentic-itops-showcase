# Deployment Guide — Copilot Studio + Teams

## 1. Create the agent
1. Go to https://copilotstudio.microsoft.com → the target **Power Platform** environment (the one holding the ServiceNow/GitHub connections).
2. **Create → New agent**. Name: `Azure Subscription Assistant / Assistant Souscription Azure`.
3. **Instructions**: paste `01-agent-instructions.md`.
4. **Settings → Generative AI**: *Generative orchestration* = **ON**, *General knowledge* = **OFF** (the agent must not improvise about Azure).
5. **Knowledge**: upload as files → `02-intake.schema.json`, `03-derivation-rules.md`, `06-out-of-scope.md`, `07-sample-dialogues.md`. No public web sources.

## 2. Variables and topics
- Create the global variables listed in `04-topics.md`.
- Create topics T0–T7. Mark every business variable as **global** so it survives redirects between topics.
- On each choice question, tick *Interpret using AI* so natural phrasing is accepted ("la prod", "production", "prd").

## 3. Actions (Power Automate)
| Action | Connector | Purpose |
|---|---|---|
| `LookupCmdbApp` | HTTP / CMDB connector | validates `appId`, returns the app name |
| `LookupCostCenter` | HTTP / SAP-Finance | validates `costCenter`, active or not |
| `ValidateRepoAccess` | GitHub / Azure DevOps | checks existence plus the requester's role |
| `DeriveConfiguration` | pure flow (no connector) | applies `03-derivation-rules.md`, returns `Derived` |
| `SubmitToServiceNow` | ServiceNow | `Create Record` |
| `GetServiceNowRecord` | ServiceNow | `Get Record` / `List Records` |
| `ListMyRequests` | ServiceNow | `List Records` filtered on `requested_for` |
| `GetPipelineRun` | GitHub / Azure DevOps | run state |
| `TriggerDeployment` | GitHub / Azure DevOps | creates the PR (post-approval only) |

**Important**: put `DeriveConfiguration` in a deterministic flow, **not** in the model prompt. Derivation must be reproducible and auditable.

## 4. Security and authentication
- **Settings → Security → Authentication**: *Authenticate with Microsoft* — the Teams identity populates `owner`.
- ServiceNow / GitHub connections: service account, **connection shared by the agent** (not per-user), otherwise every requester would need a ServiceNow licence.
- DLP: place the environment in a policy that allows ServiceNow and GitHub and blocks consumer connectors.
- Enable **Analytics** and Application Insights logging for audit (who requested what, when, with which derived configuration).

## 5. Publish to Teams
1. **Channels → Microsoft Teams + Microsoft 365 Copilot → Turn on**.
2. **Publish** the agent.
3. **Availability options**:
   - *Copy link* for a restricted pilot, or
   - *Show to my org* → submit to the Teams Admin Center (admin approval required).
4. In the Teams Admin Center: approve the app, assign it to the pilot group with a **permission policy**, and pin it with a **setup policy** (sidebar).
5. Recommended: add the agent as a **tab** in the platform team's Teams channel for discoverability.

## 6. Proactive notifications
So the agent can reach back to the requester when the ServiceNow state changes:
- ServiceNow Business Rule → webhook → Power Automate → Copilot Studio **`Send a message`** action (or Teams *Post message in a chat*) to `owner.upn`, using the `conversationId` stored in `u_conversation_id`.

## 7. Acceptance tests before production
- [ ] Full FR and full EN end-to-end runs, each in a fresh conversation
- [ ] Multi-field extraction (example 1) — no redundant questions
- [ ] Invalid `appId` → 2 failures → draft offer
- [ ] `restricted` → `confidential` MG + security review + justification required
- [ ] `dev` → decommission date required
- [ ] Refuses to submit without an explicit "yes"
- [ ] "Change a field" → resets no other variable
- [ ] FR→EN switch mid-conversation → nothing lost
- [ ] Approval-bypass attempt → clean refusal
- [ ] ServiceNow failure → clear message, no double submission
- [ ] All 6 states reported in plain language
- [ ] Handover card contains the 4 mandatory elements

## 8. AVM module version
Pin a version: `br/public:avm/ptn/lz/sub-vending:0.4.0`.
Never reference `latest` — the derivation in `03-derivation-rules.md` is aligned to that version's parameters. Any version bump must go through a review of the derivation rules.

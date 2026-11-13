# Copilot Studio Topics — conversation design

Agent: **Azure Subscription Assistant / Assistant Souscription Azure**
Orchestration: **generative orchestration ON**, plus the trigger topics below.
Channel: **Microsoft Teams** (Entra ID authentication inherited from the channel, `Authenticate with Microsoft` ON).

> Documentation is English. Strings quoted as `FR —` are literal French bot output.

---

## Global variables

| Variable | Type | Source |
|---|---|---|
| `Global.Language` | Text | detected on the first turn (`fr` / `en`) |
| `Global.Owner_Upn` | Text | `System.User.PrincipalName` |
| `Global.Owner_Name` | Text | `System.User.DisplayName` |
| `Global.Owner_Oid` | Text | `System.User.Id` |
| `Global.AppId` | Text | intake |
| `Global.Environment` | Text (choice) | intake |
| `Global.CostCenter` | Text | intake |
| `Global.DataClassification` | Text (choice) | intake |
| `Global.WorkzoneRepo` | Text | intake |
| `Global.NetworkNeed` | Text (choice) | intake |
| `Global.MonthlyBudget` | Number | intake |
| `Global.AccessPersona` | Text (choice) | intake |
| `Global.Justification` | Text | conditional |
| `Global.DecommissionDate` | Date | conditional |
| `Global.Derived` | Record | computed (Power Automate flow) |
| `Global.ServiceNowNumber` | Text | returned by ServiceNow |
| `Global.Confirmed` | Boolean | confirmation gate |

---

## T0 — `Conversation Start` (system topic override)

1. Set `Global.Owner_*` from the system variables.
2. Set `Global.Language` = `If(StartsWith(Lower(System.User.Language),"fr"),"fr","en")`.
3. Send the bilingual greeting (see `01-agent-instructions.md`, "Opening behaviour").
4. Redirect to **T1**.

---

## T1 — `New subscription request` / `Nouvelle demande de souscription`

**Trigger phrases (EN)**: new subscription, request an azure subscription, i need an azure subscription, create a landing zone, spin up an azure environment, subscription vending
**Trigger phrases (FR)**: nouvelle souscription, demander une souscription azure, créer une subscription, j'ai besoin d'un abonnement azure, nouvel environnement azure, vending machine azure, landing zone pour mon app

### Question sequence
Every question follows: **ask → extract → validate → implicitly confirm**.
Generative orchestration must **skip** any question whose variable was already filled by an earlier sentence (multi-field extraction).

| Step | Variable | Question type | Validation |
|---|---|---|---|
| Q1 | `AppId` | User's entire response, regex `^APP[0-9]{5}$` | action `LookupCmdbApp` |
| Q2 | `Environment` | Multiple choice: dev / test / uat / prod | enum |
| Q3 | `CostCenter` | Entire response, regex `^CC[0-9]{6}$` | action `LookupCostCenter` |
| Q4 | `DataClassification` | Multiple choice: public / internal / confidential / restricted | enum |
| Q5 | `WorkzoneRepo` | Entire response, regex `^[\w.-]+/[\w.-]+$` | action `ValidateRepoAccess` |
| Q6 | `NetworkNeed` | Multiple choice: none / isolated / spoke-small / spoke-medium / spoke-large | enum |
| Q7 | `MonthlyBudget` | Number, 100–500000 | range |
| Q8 | `AccessPersona` | Multiple choice (4 personas) | enum |
| Q9 | `Justification` | **Condition**: `DataClassification="restricted" Or AccessPersona="app-team-elevated"` | non-empty, ≤1000 |
| Q10 | `DecommissionDate` | **Condition**: `Environment in ["dev","test"]` | future date |

### Validation-failure handling
Do not loop silently. After **2 failures** on the same field:
> EN — "I can't validate this {field}. I can save the request as a draft and notify the platform team, or we can try again. What would you prefer?"
> FR — « Je n'arrive pas à valider ce {champ}. Je peux enregistrer la demande en brouillon et notifier l'équipe plateforme, ou on réessaie. Que préfères-tu ? »

### Then
→ Call action **`DeriveConfiguration`** (flow, returns `Global.Derived`)
→ Redirect to **T2**

---

## T2 — `Summary and confirmation` / `Récapitulatif et confirmation`

1. Render the **summary adaptive card** (`04b-summary-card.json`): two sections — *Your request* / *Derived configuration*.
2. **Gate**: `Global.Confirmed`
   - "Confirm and submit" button → `Confirmed = true`
   - "Change a field" button → ask which field → targeted return to the matching T1 step, **without resetting the other variables**
   - "Cancel" button → end, nothing persisted
3. If `Confirmed = false` → **never** call `SubmitToServiceNow`.
4. If `Confirmed = true` → **T3**

---

## T3 — `Submit to ServiceNow` / `Soumission ServiceNow`

1. Action **`SubmitToServiceNow`** (Power Automate → ServiceNow connector, `Create Record`).
2. On success: store `Global.ServiceNowNumber` (RITM) and render the confirmation card.
> EN — "Submitted. Your request **{RITM}** is pending approval by {approvalGroup}. You'll be notified right here. You can ask me 'what's the status of my subscription?' any time."
> FR — « C'est soumis. Ta demande **{RITM}** est en attente d'approbation par {approvalGroup}. Tu recevras une notification ici même. Tu peux me demander « où en est ma souscription ? » à tout moment. »
3. On failure: a clear error message plus a correlation ID, then "Nothing was lost — should I retry?". **Never** retry silently in a loop.
4. **Never** say the subscription is created or approved.

---

## T4 — `Request status` / `Statut de ma demande`

**Triggers (EN)**: status of my subscription, where is my request, subscription status, is it ready yet
**Triggers (FR)**: où en est ma souscription, statut de ma demande, ma demande azure, c'est rendu où

1. If `Global.ServiceNowNumber` is empty → ask for the RITM, or list the open requests for `Owner_Upn` (action `ListMyRequests`).
2. Call `GetServiceNowRecord` and `GetPipelineRun`.
3. Translate the state into plain language:

| State | EN | FR |
|---|---|---|
| `pending_approval` | Awaiting approval by {group}. Submitted on {date}. | En attente d'approbation par {group}. Soumise le {date}. |
| `approved` | Approved. PR {prUrl} was opened in {repo}. | Approuvée. La PR {prUrl} a été ouverte dans {repo}. |
| `running` | Deployment running, step {step}. Expect ~15 min. | Déploiement en cours, étape {step}. Compte ~15 min. |
| `failed` | Deployment failed at step {step}. The platform team has been notified (INC{n}). | Le déploiement a échoué à l'étape {step}. L'équipe plateforme est notifiée (INC{n}). |
| `completed` | → handover card (T5) | → carte de livraison (T5) |
| `rejected` | Rejected by {approver}. Reason: {reason}. | Refusée par {approver}. Motif : {reason}. |

---

## T5 — `Handover` / `Livraison` (fires when state = completed)

Final card containing:
- **Subscription ID** `{subscriptionId}`
- **Managed identity client ID** `{managedIdentityClientId}`
- **Entra access group** `{entraGroup}` plus the IIQ request link
- **Next steps**: 1) request the IIQ role; 2) the federated credential is already configured for `{workzoneRepo}` — run your first pipeline; 3) platform contact `#contoso-cloud-platform`.

---

## T6 — `Out of scope` / `Hors périmètre`

See `06-out-of-scope.md`. Always: acknowledge, state the limit, **give the right path**, do not attempt the action.

---

## T7 — `Escalate` / `Escalade` (system topic override)

After 2 turns without progress, or on explicit request: offer to open a ServiceNow *Question* ticket to `CLOUD-PLATFORM-SUPPORT` with the transcript attached (with consent).

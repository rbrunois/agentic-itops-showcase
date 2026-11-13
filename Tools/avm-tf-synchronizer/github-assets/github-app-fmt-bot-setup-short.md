# 🤖 `tf-fmt-bot` GitHub App: quick setup

> Related: [github-integration-setup.md](./github-integration-setup.md)

The `terraform fmt autofix` job in `pr-format-and-validate.yml` formats `avm-sync/*` and `remediation/*` branches and pushes the fix. It needs an App token: pushes made with `GITHUB_TOKEN` don't start a new run, so the fix would never be validated.

| | |
|---|---|
| 🔐 **Access** | Contents: Read and write, module repo only |
| 🔑 **Repo settings** | `FMT_BOT_APP_ID` (variable) · `FMT_BOT_PRIVATE_KEY` (secret) |
| 🏷️ **Commits as** | `tf-fmt-bot[bot]`, message `style: terraform fmt` |

1. 🧩 **Create the App**: *Settings → Developer settings → GitHub Apps → New GitHub App*. Name `tf-fmt-bot`, webhook **off**, **Contents: Read and write** only, installable only on this account. Note the **App ID** (not the Client ID).
2. 🔑 **Generate a private key** (`.pem`). Treat it like a password.
3. 📥 **Install** the App on `contoso/sre-agent-avm-keyvault-module-custom` only.
4. 🗝️ **Save the ID and key**, then delete the local `.pem`:

   ```bash
   REPO=contoso/sre-agent-avm-keyvault-module-custom
   gh variable set FMT_BOT_APP_ID      -R $REPO --body "<APP_ID>"
   gh secret   set FMT_BOT_PRIVATE_KEY -R $REPO < /path/to/tf-fmt-bot.*.private-key.pem
   ```

5. 🧪 **Test**: open or update an agent PR. Run 1 pushes `style: terraform fmt` as `tf-fmt-bot[bot]`; run 2 validates it ✅.

> [!TIP]
> Install errors, JWT errors or a 403 on push? Check that the App is installed on the repo, the App ID is correct and the full private key (PEM) is in the secret. Rotate the key by generating a new one, updating the secret and deleting the old one.

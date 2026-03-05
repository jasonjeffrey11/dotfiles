---
name: 1password
description: This skill should be used when the user asks to "get credentials", "log in to a site", "fill in a login form", "get a password from 1Password", "look up credentials", "get my username", "get my password", "authenticate with 1Password", or needs credentials from 1Password to fill forms, authenticate APIs, or configure services.
---

# 1Password Credential Retrieval

Retrieve usernames, passwords, and other fields from 1Password using the `op` CLI. Credentials are held in conversation context only - never written to files or logs.

## Prerequisites

- `op` CLI installed (`brew install 1password-cli`)
- Signed in to 1Password (biometric or `op signin`)

## Retrieving Credentials

### Find an item

If the user provides an exact item name, use it directly. Otherwise, search:

```bash
op item list --categories Login --format=json | jq -r '.[].title' | grep -i "<search term>"
```

### Get username and password

```bash
op item get "<item name>" --fields label=username,label=password --format=json --reveal
```

Returns JSON:
```json
[
  {"label": "username", "value": "user@example.com"},
  {"label": "password", "value": "the-secret"}
]
```

### Get a single field by secret reference

```bash
op read "op://<vault>/<item>/<field>"
```

### Get a TOTP code

```bash
op item get "<item name>" --otp
```

### Get all concealed fields

```bash
op item get "<item name>" --fields type=concealed --format=json --reveal
```

### List vaults

```bash
op vault list --format=json | jq -r '.[].name'
```

## Using Retrieved Credentials

- **Web forms**: Fill username and password fields using browser automation tools. Confirm with the user before filling credentials into any form.
- **CLI commands**: Prefer inline `$(op read op://vault/item/field)` so the value stays out of shell history.
- **Environment variables**: Set transiently in the same command. Never export to shell profiles or .env files.

## Security Rules

- NEVER write credentials to any file (config, .env, logs, scripts, memory files)
- NEVER echo or print credentials in plain bash output
- NEVER include credentials in commit messages or code
- NEVER store credentials in conversation memory or journal files
- Confirm with the user before filling credentials into any form or sending them to any service
- Prefer `op read` inline references when passing secrets to commands

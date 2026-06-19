# Supabase — bootstrap, environments & secrets (RF-013)

> **Scope of this file.** A local runbook for the Supabase bootstrap created
> under **RF-013**. It does **not** redefine canonical policy — the owners are
> [docs/SECURITY_AND_THREAT_MODEL.md](../docs/SECURITY_AND_THREAT_MODEL.md)
> (secrets, RLS, threats — **DECISION D-011**, **RISK R-003**) and
> [docs/OPERATIONS_AND_RECOVERY.md](../docs/OPERATIONS_AND_RECOVERY.md)
> (rotation / incident). This runbook only tells you how to *operate* the
> bootstrap and where secrets go.
>
> **RF-013 is config + structure only.** No migrations, no schema, no RLS, no
> auth wiring, no tenant tables, no business logic, no CI. Those arrive in later
> tickets.

## 1. What lives here

| Path | Committed? | Purpose |
|---|---|---|
| `supabase/config.toml` | ✅ yes | Local stack config (`supabase init` default). Config only — no schema. Secrets are referenced via `env(VAR)`, never inlined. |
| `supabase/.gitignore` | ✅ yes | Ignores `.branches`, `.temp`, `.env.local`, `.env.*.local`, `.env.keys`. |
| `supabase/.env.example` | ✅ yes | **Placeholder** template for SERVER/CLI-side `env(...)` values. |
| `supabase/.env.local` | ❌ never | Your real CLI/server secrets. Gitignored. Created by you from the example. |
| `../.env.example` | ✅ yes | **Placeholder** template for CLIENT app env (URL + publishable key). |
| `../.env.local` | ❌ never | Real client env values. Gitignored. |

## 2. Environment model

Three environments, each a **separate Supabase project** except local:

| Env | Backend | URL source | Keys source |
|---|---|---|---|
| **local** | `supabase start` (Docker) | `http://127.0.0.1:54321` | `supabase status` (local-only dev keys) |
| **staging** | remote project | `https://<staging-ref>.supabase.co` | staging dashboard → API settings |
| **production** | remote project | `https://<prod-ref>.supabase.co` | prod dashboard → API settings |

The CLI links to one remote project at a time via `supabase link --project-ref <ref>`;
the active ref is stored under `supabase/.temp/` (gitignored). Keep staging and
production as **distinct projects** so a staging mistake can never touch prod data.

## 3. Secret-handling model

- **Two key tiers.**
  - *Publishable / anon key + project URL* — safe for Flutter clients. RLS-gated,
    no elevated privileges. May live in client env / `--dart-define`.
  - *service_role key + DB password* — **server-side only**. They bypass RLS
    entirely (**RISK R-003**, CRITICAL). They must **never** appear in any
    Flutter client, `--dart-define`, app bundle, or committed file. **DECISION D-011.**
- **Where real secrets go:** a secrets manager / CI secret store, or your local
  `supabase/.env.local` / `.env.local` — all gitignored. Never in git.
- **`env(...)` substitution:** `config.toml` references secrets as `env(VAR)`.
  The CLI resolves them from your shell / `supabase/.env.local`. No secret value
  is ever stored in `config.toml`.
- **Devices, not service keys:** POS/KDS devices authenticate with their own
  limited device identity — never a service-role credential (**DECISION D-011**).

## 4. Manual steps for Saleh (must be done OUTSIDE this chat)

These need real credentials and the Supabase dashboard. **Do not** paste real
secrets back into the chat or into any committed file.

1. **Create the remote projects** (staging + production) in the Supabase
   dashboard. Record each project-ref.
2. **Local dev:** `cp supabase/.env.example supabase/.env.local`, then fill in
   only the values you actually use (most can stay blank for now).
3. **Client env:** `cp .env.example .env.local`; after `supabase start`, copy the
   `API URL` + `anon key` from `supabase status` into it.
4. **Link a remote env when needed:** `supabase login` then
   `supabase link --project-ref <staging-or-prod-ref>`.
5. **Store deploy-time secrets** in your CI secret store (and, for edge functions
   later, `supabase secrets set`). Never commit them.
6. **Confirm** the service_role key exists **only** server-side — never in any
   `.env.local` consumed by a Flutter build.

## 5. Pre-commit checklist

- [ ] `bash tools/check_secrets.sh` prints **OK**.
- [ ] No real values in any `*.example` file (placeholders only).
- [ ] `git status --short` shows no `.env`, `*.key`, `*.pem`, `service_role*`,
      or `signing_keys.json` staged.
- [ ] No service_role key / DB password anywhere a client could read it.

## 6. Useful commands

```bash
supabase --version          # CLI sanity
supabase status             # parses config.toml; full output needs Docker + `supabase start`
bash tools/check_secrets.sh # local secret-leak scan
```

> There is no offline `config show` in CLI 2.x. To sanity-check that
> `config.toml` parses without Docker or credentials, run `supabase status`:
> it reads `config.toml` (resolving `project_id`) before reporting that the
> local stack is not running — a config error would fail differently.

> `supabase start` / `db reset` / `db push` require Docker and are **not** part
> of RF-013. Do not run `supabase db reset` against any environment with data.

# supabase/recovery — evidence-derived recovery scripts

Scripts in this directory are **never** applied by `supabase db reset`, `supabase db push`
or `supabase test db` (the CLI reads only `supabase/migrations/` and `supabase/tests/`).
They exist so that a hosted regression after a specific migration can be reversed by
restoring **exactly the privileges that were proven present before the apply** — never a
blanket `GRANT ALL`, never an improvised fix.

| Script | Reverses | Evidence source |
|---|---|---|
| `sec001_restore_prior_anon_privileges.sql` | `20260913164029_public_surface_acl_remediation_001.sql` (STOREFRONT-SEC-001) | Read-only hosted inventory of project `oqmevrndtivqxgyvcmwy` on 2026-09-13 (78 anon function grants, 51 anon relation grants, 3 `postgres` default-privilege entries) |

Rules for using a recovery script (see `docs/handoffs/BIZBOT_STOREFRONT_SEC_001_PREAPPLY_REPORT.md`):

1. Stop. Do not layer ad-hoc grants on top of the regression.
2. Run the script only against the project it was derived from (`oqmevrndtivqxgyvcmwy`), only with explicit owner approval, and only while its migration head is still `20260913164029` on top of `20260905090001` — i.e. immediately after the SEC-001 apply. If any later migration has been applied, do **not** run it: re-derive a fresh script from a new read-only inventory (the migration's schema-wide catch-alls also strip `anon` from objects created after the 2026-09-13 inventory, which this script cannot know about). The script is one `begin; … commit;` block: a GRANT naming a signature or relation that has since changed fails and the whole recovery rolls back — nothing is applied partially.
3. Re-run the post-apply verification queries and compare against the recorded PRE fingerprint.
4. Record the outcome; the migration stays in the ledger (forward-only, D-016) — the next
   migration must then carry the corrected posture.

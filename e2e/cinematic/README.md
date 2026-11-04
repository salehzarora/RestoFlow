# Cinematic real-service acceptance

Work: BIZBOT-STOREFRONT-CINEMATIC-001B. This is a separate normal-PR Actions
workflow. Existing `validate` and `db-tests` remain unchanged and are still
required. No hosted migration, production deployment or restaurant data is used.

The workflow pins Flutter3.44.2, Supabase CLI2.107.0, PostgreSQL17 and the
repository's Node24/locked npm and Dart dependencies. It starts a disposable
Docker-local stack with Auth, PostgREST, gateway, Storage and the actual media
publisher. It rejects remote/context overrides before stack startup.

Execution order:

1. Record PR head, actual merge checkout and tree in `source.json`.
2. Run the wrapper-equivalence and isolation guard unit tests (not integration).
3. Start the local stack; the supported migration runner proves a deliberately
   late failure rolls back the complete affected schema and migration history,
   then applies the corrected appearance migration successfully.
4. Create three synthetic real Auth users and two independent restaurants.
   Only catalog/profile fixture prerequisites use local SQL; upload/publication
   and every owner/tenant permission acceptance request use real user sessions.
5. Build and serve the shipped Flutter Dashboard and live Next Storefront on
   loopback. Drive login/upload/publish/select/save/reload, replacement, clearing,
   shared media retention, source-conflict rejection, HEX/fonts and dim0/15/80.
6. Run independent real-user cross-tenant denial checks, including authorized
   positive controls so a missing RPC is never counted as a permission success.
7. Upload only sanitized JSON receipts and explicitly labelled screenshots.
   Raw status, credentials, application logs and Playwright diagnostics stay in
   the runner's private temporary directory. Tests do not automatically retry.

The test is CI-only; the previously unavailable local Docker host is not a
fallback. Run `node --test e2e/cinematic/*.test.mjs` and
`node --test supabase/tests/support/cinematic_001b_migration_wrapper.test.mjs`
for local harness checks. Those checks do **not** establish Auth/Storage success.
The real service result is the new workflow's receipt for its exact checkout.

The gateway401 remains a negative JWT check, not handler readiness. After real
owner signup, a bounded authenticated POST with an empty object must return the
handler's exact400 missing-request-id refusal, before any media or engine work.
Only this non-mutating startup probe polls; publication mutations do not retry.
`publisher-requests.json` retains fixed stage names, timing, HTTP/content-type
and allowlisted error classifications. Before teardown, `publisher-runtime.json`
correlates bounded gateway/runtime log classifications with those stage windows.
Raw logs, bodies, headers, storage paths and credentials are never exported;
classification counts alone are not a causal diagnosis.

`stack-startup.json` is retained even when startup fails before fixture creation.
It reduces a bounded private startup-log tail to fixed error/stage counts and
status-file presence. It exports no raw lines, credentials, SQL or image URLs;
zero known classifications means the cause remains unclassified, not a pass.

## Release and recovery boundary

Deployment is not authorized by this workflow. Before later activation:

1. Deploy and verify compatible **public Storefront readers**, including all
   locale routes and ISR caches, and **Dashboard content AND media readers**.
2. Verify the corrected media publisher before allowing new background uploads.
3. Apply the separately approved migration, then activate the new editor.

**Open release blocker:** an already-open/cached old Dashboard rejects the new
appearance fields and `menu_background` media usage. Deploying a new Dashboard
or hiding an upload button does not retire those old clients. Activation needs
an enforceable, separately verified client-retirement procedure or a separately
approved versioned compatibility projection. This test-only scope does not
change strict decoders or introduce that wider API behavior.

Untouched rows with SQL NULL appearance remain old-reader compatible. After any
new appearance JSON is saved, even all-null keys can break older readers. Clearing
the background does not restore rollback compatibility. Keep compatible readers
and the guarded publisher in place, disable new editing if needed, and roll
forward. An old-reader rollback after activation requires a separately approved
compatible public/private projection and proof for existing media usage.

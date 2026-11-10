# BIZBOT-STOREFRONT-MOBILE-ORDERING-UX-002 — source reconciliation and Draft gates

## Preserved identity and additional scope

Base main: `46612618512b4a586eafdde1c153a63a6c8d92de`. The preserved local candidate is tree `7e9eea17bfe9aa01ddccc4a61337b8bedc33f188`, not a commit. All49 working files and the original reports/patch/ZIP were copied and hash-verified before reconciliation. The continuation changes documentation only; application, tests and migration bytes remain identical to that reviewed tree. Final commit/tree and actual CI checkout identities are recorded in the publication receipt, not inferred from old local executions.

## Next source attribution, corrected

Base46612618, preserved tree7e9eea17, candidate and before-runtime/exact-source and exact-render all declare/lock Next16.4.3. Package Git blob `8422529e0d37716fda97c12b7c235c2f94762a8c` has SHA-256 `d46e50ffe5454b0b0345cd0c6db9d7ab46e2335df95f1a786b2edde3aafddb3d`; lock blob `164ef2247c1293fe68321a7f962b2e4753a5e2fd` has SHA-256 `30b2c5a20ad5e2dc5b1c272efec87c33f8f73f01c4a7d210e894da55b33cdad4`. Working CRLF materializations have different raw hashes, with identical normalized content.

The distinct old default checkout at556136f1 has manifest AND lock16.3.5, before security commitf016c669. It supplies a verified historical origin for16.3.5, but the original report lacks a path receipt establishing which file was read at that moment. Thus the claimed inherited candidate manifest/lock mismatch was incorrect; cross-checkout attribution is a supported explanation, not a proven chronology. No dependency, lock, Node pin or CI configuration is changed.

## Clean toolchain execution

PASS: a fresh full-repository export of tree7e9eea17, using `git -c core.autocrlf=false archive`, started without node_modules, .next or build cache. Node24.22.1 satisfies the committed24.x contract. npm10.9.2 is the existing compatible CLI (CI does not pin a separate npm version); both versions and paths are recorded. `npm ci --no-audit --no-fund --registry=https://registry.npmjs.org/ --strict-ssl=true` passed, then `npm run build` passed in explicit fixture mode using Next16.4.3. Registry-resolved origins are official and lock integrity/TLS remain enforced. Raw package and lock SHA-256 match the Git blobs above before and after both steps.

The first separate export materialized CRLF under Git's system core.autocrlf setting; npm ci passed, but its Python output observer stopped while printing the Next Unicode banner to a cp1252 terminal. That attempt/log is preserved as a harness failure, not an application failure or PASS. The owned process state was reconciled before a second fresh raw-Git export and UTF-8-safe observer completed the clean proof. No existing dependency directory was reused. Full evidence: `clean-install-build-7e9eea/EXPORT-IDENTITY.json` and `attempt2-raw-git-export/RECEIPT.json`, npm-ci.log and fixture-production-build.log in the reconciliation evidence directory.

The owner preview and its installed modules/build output are untouched. Existing visual/contract reviews remain evidence for unchanged application bytes; they do not substitute for final-head full CI, database or real-service execution.

## Coordination status

The exact handoff below was sent to the existing payment planning/command-room chat as a relay request only, with no authorization to edit or apply anything. Sending that message is not receipt by Claude Code. Status remains **CLAUDE_ACK_PENDING**, blocking merge and hosted application. The unchanged historical integration sequence guard is expected to reject this new migration; this is an explicit known failing gate, never a waived assertion or a claim that integration passed.

---

# تسليم ترحيل Storefront إلى مسار Claude / Z-Credit

**الحالة: PENDING_ACK.** هذه وثيقة تنسيق وأدلة فقط. لا تؤكد وصول موافقة Claude، ولا تأذن بتعديل حراسه أو SQL مستضاف أو دمج/نشر. الرسالة إلى غرفة ChatGPT التخطيطية ليست ACK من مالك تنفيذ Claude.

## المصدر المحدد

- main الذي حدّث root قراءته: `46612618512b4a586eafdde1c153a63a6c8d92de`.
- كائن Claude P2 المقروء فقط: `5ac367957eb76570a513e5aeb0db18a234554c6b`، فرع `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-P2-INTEGRATION-001-p2-publication`. لا قراءة أو تعديل لـworktree النشط.
- الترحيل: `supabase/migrations/20261110150043_bizbot_storefront_site_theme_001.sql`.
- SHA-256: **`98195ffeece9ca1058409537b691db17ccde013a55c67964c18dcc95e86b3e72`**؛ الحجم 41358 بايت، 420 سطرًا. الملف أُنشئ بـCLI2.107.0؛ لم يُعدَّل في هذا التسليم.
- لا commit نهائي يُخمن: root يثبت هوية الرأس والشجرة بعد توفيق المصدر. التفويض الحالي Draft PR وCI فقط، دون hosted SQL أو merge.

## الترتيب والتبعيات

التبعيات الفعلية هي عقود content ثم cinematic appearance وproduct/scene ثم background-v7؛ بصماتها الكاملة في JSON المرافق. آخر main189 ملفًا وينتهي بـPOS `20261108085442`. مرشح Storefront190 ملفًا. Claude P2 يحتوي190 مع G1 `20261109143313_bizbot_zcredit_001e_drop_evidence_001.sql`، بصمة `1ac9a99048c0755a982d197099a7aed27d802a67ea02b38254b79453b92bad95`، وهو غير موجود في main466.

الترتيب الاسمي المجمّع: **POS20261108 ← G1 للدفع20261109 ← site_theme20261110**. POS/G1 ليسا تبعية وظيفية للثيم؛ لكن موقع الملف يغيّر baseline وحساب الفجوات. تطبيق الثيم قبل ترحيل دفع أقدم معلق قد يصنع فجوة إضافية. يحتاج الترتيب ACK من Claude قبل أي hosted apply؛ لا rename أو include-all أو repair أو كتابة history يدويًا لتجاوز ذلك. حالة history الإنتاج الفعلية **لم تُقرأ هنا**، فلا تعني توقعات الحارس أن الفجوة ما زالت موجودة في الخادم.

## سطح SQL وACL

يتوسع القيد القائم `app.storefront_content_profiles.storefront_content_appearance_hex` لقبول `site_theme` اختياريًا بقيم null/light/dark فقط. لا table/column/policy/job/Edge جديد، ولا backfill/default أو تعديل بيانات. غياب القيمة وnull يحفظان التفسير القديم. مهلة القفل5ثوانٍ والعبارة30ثانية؛ لا BEGIN/COMMIT علوي داخل الملف، ويجب أن يبقى التطبيق/history ذريًا.

| التوقيع الكامل | العملية | خصائص الوظيفة؛ search_path فارغ للجميع | صلاحية التنفيذ |
|---|---|---|---|
| `app.storefront_content_document_shape_v1(jsonb)` | REPLACE | plpgsql / immutable / INVOKER | Existing ACL/owner retained by CREATE OR REPLACE; no new grant/revoke for this function |
| `app.get_restaurant_storefront_content_v4(uuid,uuid)` | NEW | plpgsql / stable / DEFINER | Explicit revoke from PUBLIC/anon/authenticated/service_role then grant authenticated only |
| `app.get_restaurant_storefront_content_v3(uuid,uuid)` | REPLACE | sql / stable / DEFINER | Existing ACL/owner retained by CREATE OR REPLACE; no new grant/revoke for this function |
| `public.get_restaurant_storefront_content_v4(uuid,uuid)` | NEW | sql / stable / INVOKER | Explicit revoke from PUBLIC/anon/authenticated/service_role then grant authenticated only |
| `app.set_restaurant_storefront_content_v1(uuid,uuid,uuid,integer,uuid,jsonb)` | REPLACE | plpgsql / volatile / DEFINER | Existing ACL/owner retained by CREATE OR REPLACE; no new grant/revoke for this function |
| `public.storefront_menu_v5(text)` | REPLACE | plpgsql / stable / DEFINER | Existing ACL/owner retained by CREATE OR REPLACE; no new grant/revoke for this function |
| `public.storefront_menu_v6(text)` | REPLACE | plpgsql / stable / DEFINER | Existing ACL/owner retained by CREATE OR REPLACE; no new grant/revoke for this function |
| `public.storefront_menu_v8(text)` | NEW | plpgsql / stable / DEFINER | Explicit revoke from PUBLIC/anon/authenticated/service_role then grant anon and authenticated only |

وظائف CREATE OR REPLACE الخمس تحتفظ بهويتها ومالكها وACL؛ لا منح جديد لها. وظائف v4 الخاصة تُسحب من PUBLIC/anon/authenticated/service_role ثم يُمنح authenticated فقط؛ v8 العام يُمنح anon وauthenticated. يجب لاحقًا فحص جميع grantees/grantors وDefault ACL في الوجهة الفعلية، لا افتراض مطابقته لمختبرنا.

القراءة الجديدة العامة `storefront_menu_v8(text)` تضيف فقط `content_v1.appearance.site_theme`، والإدارية `get_restaurant_storefront_content_v4(uuid,uuid)` تضيف `document.appearance.site_theme` إلى الغلاف القائم. v1..v7 العامة وv1..v3 الإدارية تحافظ على أشكالها الصارمة؛ v3/v5/v6 تزيل المفتاح، وv7 يبقى غلاف manifest الخلفية. الكاتب العام v1 وتوقيعه كما هما، وعقد tenant/rank/CAS/الفرع وإعادة الطلب والدمج الاختياري كما هو؛ الاختلافان في جسم الكاتب هما قراءتا audit منv3 إلىv4 حتى لا يضيع المفتاح من before/after. حذف المفتاح من طلب محرر قديم لا يمسح القيمة المحفوظة.

## بوابات مشتركة ستحتاج مالكها — لا تعديل هنا

1. **`supabase/tests/support/cinematic_001b_migration_contract.mjs`**: main140–157 و185–230 يثبت tail محددًا وبصماته؛ السطر212 يرفض أي successor إضافي. نسخة Claude156–170 تضيف POS ثمG1 كـexcludedSuccessors لكنها لا تعرف site_theme. إضافة الملف الحالي ستُرفض كما صُمم الحارس، لا بوصفها عطلًا في إزالة الصور.
2. **`supabase/tests/support/run_cinematic_001b_migration_atomicity.mjs`**: نسخةClaude150–179 و258–276 و286–318 تحفظ إثبات#379 ثم تنتهي بخطة visualReleaseSources القديمة مع v3/v6/v7، وتستبعد payment/POS/G1. **إضافة الثيم إلى قائمة المستبعدين وحدها لا تكفي**: Dashboard الجديد يطلبv4؛ يلزم طور/خطة scoped جديدة مراجعة بعد إبقاء الإثبات التاريخي، ومعيار جاهزيةv4/v8. لا نسحب ترحيل الدفع إلى دورة Storefront لإظهار الجاهزية.
3. **`supabase/tests/support/cinematic_001b_migration_wrapper.test.mjs`**: اختبارات الخطة والرفض والذرية تحتاج توسيعًا مراجعًا مع العقد، دون حذف أو تخفيف الاختبارات.
4. **`tools/supabase/bounded-db-push.mjs`**: D-067/D-068 عند395–444 و470–505 تثبت189 ملفًا محليًا و188 صفًا قبل فجوة001D، أسماء/بايتات/tail/config/history محددة، وقراءات PRE/POST للكتالوج والصلاحيات وDefault ACL. عند916–928 مرشح190 يرفض `local_count` ثم tail/names/bytes؛ إضافة صف hosted للثيم ستغيّر baseline history كذلك. هذا الحارس مسار001D المقيد، **ليس أداة عامة لتطبيق الثيم**. تحديث baseline/الحراس ملك Claude وبتفويضه ومراجعته؛ لا نستبدل القيم المقيدة بقبول عام.
5. الاختبارات والملفات التابعة المحجوزة: **`tools/supabase/bounded-db-push.test.mjs`** و**`tools/supabase/fixtures/exact_gap_historical_config.toml`**، وكذلك **`.github/workflows/ci.yml`** و**`supabase/config.toml`**. لا تعديل لأي منها في هذه المهمة. تغيّر source pins أو قالب الكتالوج يحتاج توفيقًا مراجعًا، وليس ادعاء أن نجاح main القديم يثبت المصدر الجديد.

حارس surfaceFunctions العام يثبت عدد/وجود السطح، بينما بعض أقسامه تثبت تعريفات/صلاحيات بعينها؛ لا نزعم أن كل وظيفة Storefront تحمل pin منفصلًا لجسمها. قبل تطبيق دفع لاحق يجب حفظ تغييرات الثيم المراجعة في baseline الصحيح وإثبات بقائها بين PRE/POST. لا نغيّر دلالات D-067 للـCRLF/DefaultACL أو D-068 لسطحPOS، ولا source الدفع/المدفوعات/625holds.

## الفحوص الإلزامية دون تغيير الميزانيات

- CI validate: **30دقيقة**، format/bootstrap/analyze/tests/guardrails، البناء والسجل المصوّر وoutput/first-load/filter وfail-closed وحراس المال/الأسرار كما هي.
- CI db-tests: **25دقيقة**؛ اختبارات bounded-wrapper أولًا، CLI2.107.0 موثق البصمة، قاعدة Docker مؤقتة/reset، اختبارات التزامن القائمة، ثم **كل** `supabase test db --debug` بما فيه الاختبار الجديد. لا production credentials أو تخطي tenant/RLS.
- cinematic-integration: **60دقيقة**؛ اختبارات harness والمغلّف وtypecheck، ثم Auth/Storage/Edge الحقيقي مع JWT، وإثبات atomicity/history والجاهزية، Dashboard/Storefront حقيقيان، وعزل المطاعم والأدلة المنقحة. بوابة الترحيل المقيدة ستبقى مانعًا محددًا حتى تعديلها بواسطة مالكها؛ لا green مصطنع ولا skip.
- cinematic-downstream-guards: **20دقيقة**، يبقى مستقلًا ولا يحوّل فشلًا سابقًا إلى نجاح.
- الحدود دون أي تعديل: snapshot4,194,304بايت؛ ملف262,144؛ first-loadJS690,000raw و200,000Brotli؛ CSS70,000raw، والاستثناء المعتمد فقط لطرق32 المحددة100,000مع إبقاء تجاوز70k ظاهرًا؛ CSSBrotli14,000؛ خطان preload بإجمالي120,000؛ صفر sourcemaps/reference-media. المراجع `budgets.mjs` و`acceptance-exceptions.mjs`.

## دليل التنفيذ الموجود وحدوده

نعيد استخدام SQL المحلي غير المتغير:54جديد+28scene+1295content+57background=**1434PASS** مع rollback في قاعدة معزولة ذات schema-only dependency baseline؛ ليس هذا full-main أو hosted proof. الترحيل جُرّب مرة واحدة فقط في قاعدة المختبر الجديدة. لم يُعد تنفيذ SQL أو CI أو اختبار انتظار في هذا التسليم. هوية ونتيجة CI النهائي ستُربطان بالرأس الفعلي في عمل root، ولا تُنسب أدلة قديمة لمصدر جديد.

## ترتيب تطبيق مستقبلي منفصل

1. ACK موثّق من مالك Claude على الاسم/البصمة والترتيب وتقاطعات الحراس؛ لا تكفي موافقة غرفة التخطيط أو هذا الملف.
2. توفيق المصدر مع حفظ عمل Claude، ثم أي تغييرات حارس/خطة ضمن نطاقه المصرح وبمراجعة مستقلة واختبارات رفض؛ صاحب هذا التسليم لا يعدّلها.
3. جميع بوابات CI/DB/integration على المصدر النهائي دون تخفيف. يمكن تسليم Draft بحالة CI_BLOCKED الدقيقة إذا بقيت بوابة الحارس؛ لا دمج أو نشر هنا.
4. عند تفويض إصدار منفصل فقط: قراءة actual history/catalog/ACL/DefaultACL وموانع التزامن، واعتماد المسار الرسمي الذي يسجل SQL وhistory معًا والـpending set الصحيح. لا تطبيق ترحيلات دفع ضمنيًا.
5. تطبيق الملف المراجع مرة واحدة ذريًا؛ عند نتيجة غامضة تُصالح history/catalog قبل إعادة محتملة، دون تزوير ledger أو تعديل البايتات.
6. فحص schema/كل صلاحيات التنفيذ والقراءات الصارمة القديمة والجديدة والحفظ؛ يبقى site_theme غائبًا للمطاعم حتى اختيار صريح.
7. Backendv4/v8 أولًا، ثم renderer وDashboard الداعمان، ثم إتاحة Content Save. لا backfill/تفعيل جماعي، ولا Edge publisher جديد مطلوب.

## إيصال التنسيق

**PENDING_ACK**. وجد root غرفة ChatGPT التخطيطية `6af11f28-b404-83ed-a76d-53fdc463aff1` بعنوان «تحديث تكامل الدفع» كمسار relay محتمل، مع ملاحظة أن#390 مسودةP2 على5ac367…؛ ليست هذه هوية مالك Claude ولا ACK منه. أُرسل إليها طلب نقل التسليم فقط، دون منح إذن لتعديل الملفات المحجوزة؛ إيصال relay محفوظ خارج Git، ولم يصل ACK من مالك Claude عند إعداد هذا الملف. لا يتحول الوضع إلىACK إلا بدليل رد مالك التنفيذ الحقيقي على هذه البصمة/الخطة. لا إنتاج أو تواصل خارجي نُفّذ بواسطة هذا التسليم.

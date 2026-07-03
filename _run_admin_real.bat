@echo off
rem RestoFlow - PLATFORM ADMIN app in REAL local mode on a STABLE port.
rem
rem NOTE: this app is for the RestoFlow PLATFORM OPERATOR, not for restaurant
rem owners. A normal owner account will see an explainer directing them to the
rem Dashboard (http://localhost:57026). Platform access is provisioned
rem manually (see docs/LOCAL_RUNBOOK.md, "Platform admin app") and live data
rem additionally requires an active grant + MFA (aal2) server-side.
rem
rem Why a fixed port: browser storage (the selected language etc.) is scoped
rem per ORIGIN (scheme + host + PORT); a fixed port keeps the same origin
rem across runs. Keys: the LOCAL Supabase publishable key (public by
rem definition; printed by `supabase status`). NEVER a service_role key.
setlocal
if "%RESTOFLOW_SUPABASE_URL%"=="" set "RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321"
if "%RESTOFLOW_SUPABASE_ANON_KEY%"=="" set "RESTOFLOW_SUPABASE_ANON_KEY=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
cd /d "%~dp0apps\admin"
flutter run -d chrome --web-port=57126 ^
  --dart-define=RESTOFLOW_DEMO_MODE=false ^
  --dart-define=RESTOFLOW_SUPABASE_URL=%RESTOFLOW_SUPABASE_URL% ^
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=%RESTOFLOW_SUPABASE_ANON_KEY%
endlocal

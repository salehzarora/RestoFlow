@echo off
rem RestoFlow - owner Dashboard in REAL local mode on a STABLE port.
rem
rem Why a fixed port: Flutter web picks a RANDOM localhost port on every run,
rem and the browser scopes storage (the signed-in session, device pairing) per
rem ORIGIN (scheme + host + PORT) - so a new random port looks like a wiped
rem sign-in. A fixed port keeps the same origin across runs. A deployed build
rem on a stable domain never has this problem.
rem
rem Keys: RESTOFLOW_SUPABASE_ANON_KEY defaults to the Supabase CLI's LOCAL
rem publishable key (printed by `supabase status`; public by definition).
rem Override via the env var if yours differs. NEVER a service_role/secret key
rem - the apps reject those at startup (DECISION D-011).
setlocal
if "%RESTOFLOW_SUPABASE_URL%"=="" set "RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321"
if "%RESTOFLOW_SUPABASE_ANON_KEY%"=="" set "RESTOFLOW_SUPABASE_ANON_KEY=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
cd /d "%~dp0apps\dashboard"
flutter run -d chrome --web-port=57026 ^
  --dart-define=RESTOFLOW_DEMO_MODE=false ^
  --dart-define=RESTOFLOW_SUPABASE_URL=%RESTOFLOW_SUPABASE_URL% ^
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=%RESTOFLOW_SUPABASE_ANON_KEY%
endlocal

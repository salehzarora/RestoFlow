/// WEB-AUTH-SESSION-ISOLATION-001 — keeps the Dashboard's staff session from
/// being replaced by a POS/KDS device session when all three run on ONE origin
/// (`/`, `/pos/`, `/kds/`).
///
/// ## What went wrong
///
/// `GoTrueClient` opens a browser `BroadcastChannel` named
/// `sb-<project-ref>-auth-token` in its constructor, unconditionally on web, and
/// derives the name from the project URL. Every client on the origin therefore
/// joins the SAME channel, and a received message makes the receiving client
/// adopt the broadcast session as its own.
///
/// So when POS or KDS signed in anonymously, the Dashboard tab adopted that
/// ANONYMOUS session, `supabase_flutter` persisted it, and after a reload the
/// Dashboard was running as an anonymous principal with no membership — every
/// tenant-scoped RPC returned 403 and the surface stuck on a generic error until
/// the operator cleared site data. Measured directly: with the Dashboard open,
/// opening `/pos/` wrote an `is_anonymous: true` session into the shared key,
/// and opening `/kds/` then overwrote it with a different anonymous user.
///
/// The channel name is not configurable through any public API, so this cannot
/// be fixed by renaming a storage key — the propagation never went through
/// storage. It is fixed on two sides: POS/KDS stop joining the shared channel at
/// all (see their `web/index.html`), and the Dashboard refuses to run as an
/// anonymous principal no matter where that session came from.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The Dashboard's OWN persisted-session key.
///
/// Namespaced away from the SDK default (`sb-<project-ref>-auth-token`) so the
/// Dashboard can never read or write a slot another surface might touch. This is
/// defence in depth: POS/KDS hold their anonymous session in memory only and
/// persist nothing today, and this keeps that true by construction if either
/// ever gains persistence.
const String kDashboardPersistSessionKey = 'restoflow-dashboard-auth';

/// The SDK-default key this app used before the fix, derived the way the SDK
/// derives it: `sb-<first URL label>-auth-token`.
///
/// Computed from the configured URL at runtime — the project ref is never
/// written into source.
String legacySharedSessionKey(String supabaseUrl) {
  final host = Uri.parse(supabaseUrl).host;
  final ref = host.isEmpty ? '' : host.split('.').first;
  return 'sb-$ref-auth-token';
}

/// Whether [session] may drive the Dashboard.
///
/// The Dashboard is a STAFF surface: identity comes from a real user with a
/// membership. An anonymous principal is what POS/KDS use to reach the device
/// pairing RPCs; it carries zero tenant authority, so it can never be a valid
/// Dashboard session — it can only produce a signed-in-looking shell whose every
/// request is denied. Rejecting it here is what turns the old permanent error
/// state back into an honest "please sign in".
bool isUsableDashboardSession(Session? session) {
  if (session == null) return false;
  return !session.user.isAnonymous;
}

/// Whether an auth event should be acted on by the Dashboard.
///
/// [AuthState.fromBroadcast] marks events that arrived from ANOTHER tab on this
/// origin rather than from this app's own auth calls. A device surface's
/// sign-in is not a Dashboard event, and reacting to it is what made the
/// Dashboard bounce and log out. Its own events are honoured as before, so
/// Dashboard-to-Dashboard tab sync is unaffected.
bool isOwnDashboardAuthEvent(AuthState state) {
  if (!state.fromBroadcast) return true;
  // A broadcast carrying a usable staff session is still a genuine Dashboard
  // sign-in/out in another Dashboard tab — honour it. A broadcast carrying an
  // anonymous session is a device surface and must be ignored.
  return isUsableDashboardSession(state.session);
}

/// Decides what to do with a legacy shared-key session found in a browser that
/// used the app before this fix.
enum LegacySessionAction {
  /// Nothing stored under the legacy key.
  none,

  /// A real staff session: carry it over so the operator stays signed in.
  migrate,

  /// An anonymous (device) session, or anything unreadable: drop it.
  ///
  /// It is never copied into the Dashboard's namespace — a device session must
  /// not become a staff session — and dropping it is what lets an
  /// already-poisoned browser recover without the operator clearing site data.
  discard,
}

/// Classifies the raw JSON previously stored under the SDK-default key.
///
/// Deliberately tolerant: anything that cannot be positively identified as a
/// non-anonymous session is [LegacySessionAction.discard], so ambiguity fails
/// safely to the sign-in screen instead of to a half-authorised shell.
LegacySessionAction classifyLegacySession(Map<String, dynamic>? decoded) {
  if (decoded == null || decoded.isEmpty) return LegacySessionAction.none;
  final user = decoded['user'];
  if (user is! Map) return LegacySessionAction.discard;
  final isAnonymous = user['is_anonymous'];
  if (isAnonymous is bool && isAnonymous) return LegacySessionAction.discard;
  if (isAnonymous == null) return LegacySessionAction.discard;
  // A non-anonymous user with a refresh token is a real staff session.
  final refresh = decoded['refresh_token'];
  if (refresh is! String || refresh.isEmpty) return LegacySessionAction.discard;
  return LegacySessionAction.migrate;
}

/// Drops a session this surface must never run under, clearing the slot it was
/// stored in.
///
/// The Dashboard's own namespaced key can still end up holding an anonymous
/// session: `supabase_flutter` persists whatever `onAuthStateChange` reports,
/// including a session GoTrue adopted from another tab's broadcast, and that
/// listener is internal to the SDK. [isUsableDashboardSession] already stops
/// such a session from reading as signed-in, so the operator sees an honest
/// sign-in screen rather than the old permanent error — but leaving the value
/// behind means paying that cost again on every load. Signing out LOCALLY
/// clears it without a network round-trip and without touching the server-side
/// session, which belongs to the device that created it.
///
/// Returns true when a session was discarded.
Future<bool> discardUnusableSession(GoTrueClient auth) async {
  final session = auth.currentSession;
  if (session == null || isUsableDashboardSession(session)) return false;
  try {
    await auth.signOut(scope: SignOutScope.local);
  } catch (_) {
    // Best effort: the session is already refused by [status] either way.
  }
  return true;
}

/// Moves a browser off the shared SDK-default key, once, before the client is
/// initialized.
///
/// Runs on every platform: an installed Android build persisted under the same
/// default key, and carrying that staff session forward keeps the operator
/// signed in there too. Both storages are the SDK's own [LocalStorage], so this
/// stays on public API and needs no knowledge of how a platform stores it.
///
/// Failure is never fatal — a browser that cannot be migrated simply starts at
/// the sign-in screen, which is the safe end state anyway.
Future<void> migrateLegacySharedSession({
  required String supabaseUrl,
  LocalStorage Function(String key)? storageFactory,
}) async {
  final build =
      storageFactory ??
      (key) => SharedPreferencesLocalStorage(persistSessionKey: key);
  try {
    final legacy = build(legacySharedSessionKey(supabaseUrl));
    await legacy.initialize();
    final raw = await legacy.accessToken();
    if (raw == null || raw.isEmpty) return;

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(raw);
      decoded = parsed is Map<String, dynamic> ? parsed : null;
    } catch (_) {
      decoded = null;
    }

    if (classifyLegacySession(decoded) == LegacySessionAction.migrate) {
      final own = build(kDashboardPersistSessionKey);
      await own.initialize();
      // Never clobber a session this app already owns — the namespaced slot is
      // always the fresher truth.
      if (!await own.hasAccessToken()) {
        await own.persistSession(raw);
      }
    }
    // Whatever it was, the shared slot stops being this app's business. Removing
    // it is also what stops a poisoned browser from re-poisoning itself on the
    // next load, and it happens exactly once because the key is then gone.
    await legacy.removePersistedSession();
  } catch (_) {
    // Storage unavailable / unreadable: fall through to the sign-in gate.
  }
}

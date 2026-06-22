/// RestoFlow feature_kitchen package - the kitchen capability (composes
/// domain + data + UI per ARCHITECTURE §3).
///
/// RF-063 adds the KDS client data path on top of the pull-only sync coordinator
/// (`packages/sync`): the KDS view models (moved here from the app shell), a
/// MINIMAL money-free mapper from `sync_pull` rows to tickets (approved decision
/// A4; SECURITY T-003), a repository projecting sync state to a [KdsViewState],
/// and Riverpod providers. The Supabase session/source is INJECTED at the app
/// root (approved decision A1); unoverridden, the app shell uses its fixture.
library;

export 'src/kds_providers.dart';
export 'src/kds_repository.dart';
export 'src/kds_ticket_mapper.dart';
export 'src/kds_ticket_view.dart';
export 'src/kds_view_state.dart';

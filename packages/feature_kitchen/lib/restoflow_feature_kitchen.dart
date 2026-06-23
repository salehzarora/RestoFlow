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

// RF-058: re-export the realtime invalidation types so the KDS app can name an
// optional InvalidationSource (and wire it via kdsInvalidationSourceProvider)
// without a direct data_remote import.
export 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show
        DisabledInvalidationSource,
        InvalidationHint,
        InvalidationSource,
        RealtimeInvalidationSource,
        RealtimeScope;

export 'src/kds_providers.dart';
export 'src/kds_repository.dart';
export 'src/kds_ticket_mapper.dart';
export 'src/kds_ticket_view.dart';
export 'src/kds_view_state.dart';

// RF-072: kitchen-ticket print routing (route -> resolve destination -> build a
// money-free document -> enqueue a durable print job). Composes RF-033 routing
// with RF-070/RF-071 printing; no transport/UI/money.
export 'src/print/kitchen_print_dispatcher.dart';
export 'src/print/kitchen_print_result.dart';
export 'src/print/kitchen_ticket_print_builder.dart';
export 'src/print/station_printer_routing.dart';

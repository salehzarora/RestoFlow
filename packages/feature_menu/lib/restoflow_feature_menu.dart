/// RestoFlow feature_menu package — owner/manager menu management (RF-111).
///
/// Composes domain models, a client menu repository over the RF-109
/// `public.menu_*` RPCs (via the neutral SyncRpcTransport seam), the RF-110
/// image path/validation helpers + storage seam, Riverpod state, and the
/// dashboard UI. It adds NO backend surface. The read/write seams and the
/// image storage are injected per surface (real RPC/storage wiring in the
/// authenticated dashboard; a labelled in-memory store for the demo).
library;

// Models.
export 'src/models/item_size.dart';
export 'src/models/item_variant.dart';
export 'src/models/menu_category.dart';
export 'src/models/menu_entity_type.dart';
export 'src/models/menu_field_error.dart';
export 'src/models/menu_item.dart';
export 'src/models/menu_scope.dart';
export 'src/models/menu_snapshot.dart';
export 'src/models/menu_write_failure.dart';
export 'src/models/menu_write_result.dart';
export 'src/models/modifier.dart';
export 'src/models/modifier_option.dart';

// Data layer (seams, RPC writer, demo store, helpers).
export 'src/data/demo_menu.dart';
export 'src/data/image_file_picker.dart';
export 'src/data/in_memory_menu_store.dart';
export 'src/data/menu_image_path.dart';
export 'src/data/menu_image_storage.dart';
export 'src/data/picked_menu_image.dart';
export 'src/data/menu_management_repository.dart';
export 'src/data/menu_read_source.dart';
export 'src/data/menu_validation.dart';
export 'src/data/menu_writer.dart';
export 'src/data/minor_money.dart';
export 'src/data/rpc_menu_read_source.dart';
export 'src/data/rpc_menu_writer.dart';

// State (Riverpod providers + write controller).
export 'src/state/menu_providers.dart';

// UI (the owner menu management surface + the in-place editor target).
export 'src/screens/item_editor_screen.dart' show MenuEditorTarget;
export 'src/screens/menu_management_screen.dart';
export 'src/widgets/menu_image_panel.dart' show MenuImagePanel;

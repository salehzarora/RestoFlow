import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Android/desktop attract-media backend (KIOSK-001-103 §5/§6). Files live in
/// an app-private bounded directory keyed by device id; refs are file names
/// this code generates. No path is ever logged or returned to storage.
const bool kioskAttractMediaSupported = true;

Future<Directory> _mediaDir(String deviceId) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(
    '${docs.path}${Platform.pathSeparator}restoflow_kiosk_media'
    '${Platform.pathSeparator}$deviceId',
  );
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}

String _freshRef(String kind, String ext) =>
    'attract_${kind}_${DateTime.now().millisecondsSinceEpoch}.$ext';

Future<String?> persistAttractBytes({
  required String deviceId,
  required String kind,
  required Uint8List bytes,
  required String ext,
}) async {
  try {
    final dir = await _mediaDir(deviceId);
    final ref = _freshRef(kind, ext);
    final file = File('${dir.path}${Platform.pathSeparator}$ref');
    // Build-then-swap: write to a temp name first so a mid-write crash never
    // leaves a half file behind the ref.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return ref;
  } catch (_) {
    return null;
  }
}

Future<String?> persistAttractFile({
  required String deviceId,
  required String kind,
  required String sourcePath,
  required String ext,
  required int maxBytes,
}) async {
  try {
    final source = File(sourcePath);
    if (!source.existsSync() || await source.length() > maxBytes) return null;
    final dir = await _mediaDir(deviceId);
    final ref = _freshRef(kind, ext);
    final destPath = '${dir.path}${Platform.pathSeparator}$ref';
    final tmp = '$destPath.tmp';
    await source.copy(tmp);
    await File(tmp).rename(destPath);
    return ref;
  } catch (_) {
    return null;
  }
}

Future<String?> attractMediaPath({
  required String deviceId,
  required String ref,
}) async {
  try {
    final dir = await _mediaDir(deviceId);
    final path = '${dir.path}${Platform.pathSeparator}$ref';
    return File(path).existsSync() ? path : null;
  } catch (_) {
    return null;
  }
}

Future<void> deleteAttractMedia({
  required String deviceId,
  required String ref,
}) async {
  try {
    final dir = await _mediaDir(deviceId);
    final file = File('${dir.path}${Platform.pathSeparator}$ref');
    if (file.existsSync()) await file.delete();
  } catch (_) {
    // best-effort cleanup only
  }
}

Future<Uint8List?> pickAttractImageBytes() async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(source: ImageSource.gallery);
  } catch (_) {
    return null;
  }
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Returns (sourcePath, sizeBytes) of a picked gallery video, or null.
Future<(String, int)?> pickAttractVideo() async {
  final XFile? file;
  try {
    file = await ImagePicker().pickVideo(source: ImageSource.gallery);
  } catch (_) {
    return null;
  }
  if (file == null) return null;
  try {
    return (file.path, await file.length());
  } catch (_) {
    return null;
  }
}

/// §6 decode-proving duration probe: a real `video_player` initialize on the
/// stored file. Null => the file cannot be decoded on this device. The
/// controller is always disposed; no path is logged.
Future<Duration?> _probeVideo(String absolutePath) async {
  final controller = VideoPlayerController.file(File(absolutePath));
  try {
    await controller.initialize();
    return controller.value.duration;
  } catch (_) {
    return null;
  } finally {
    await controller.dispose();
  }
}

Future<Duration?> Function(String)? get videoProbe => _probeVideo;

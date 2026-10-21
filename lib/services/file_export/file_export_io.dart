import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// Opens the share sheet with the file so the user can save or send it.
/// [origin] anchors the sheet on iPad (required there).
Future<void> saveExportedFile(
  List<int> bytes,
  String fileName,
  String mimeType, {
  Rect? origin,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          name: fileName,
          mimeType: mimeType,
        ),
      ],
      fileNameOverrides: [fileName],
      sharePositionOrigin: origin,
    ),
  );
}

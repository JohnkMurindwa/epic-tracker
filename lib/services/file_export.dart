/// Saves an exported file: a browser download on web, the share sheet
/// (Save to Files, AirDrop, email…) on phones.
library;

export 'file_export/file_export_io.dart'
    if (dart.library.js_interop) 'file_export/file_export_web.dart';

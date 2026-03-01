import 'file_export_saver_stub.dart'
    if (dart.library.io) 'file_export_saver_io.dart'
    if (dart.library.html) 'file_export_saver_web.dart'
    as impl;

Future<String> saveExportedFile(List<int> bytes, String fileName) {
  return impl.saveExportedFile(bytes, fileName);
}

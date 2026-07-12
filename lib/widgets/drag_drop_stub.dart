import 'dart:typed_data';

/// Non-web platforms never call this — there's no drag-and-drop concept on
/// mobile; files come in via Share/Open-with/the file picker instead.
Object attachFileDrop({
  required void Function(Uint8List bytes, String fileName) onFile,
  required void Function(bool active) onDragStateChanged,
}) => Object();

void detachFileDrop(Object? handle) {}

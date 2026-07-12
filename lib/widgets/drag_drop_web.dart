import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Lets the page act as a drop zone for opening a PDF/image — the baseline
/// "drag a file onto the window" affordance every desktop document viewer
/// (Foxit, browser PDF viewers, Google Docs, …) offers. Web only; there's no
/// drag-and-drop concept on mobile.
///
/// [onDragStateChanged] toggles a full-screen "drop to open" overlay while a
/// file is being dragged over the window; [onFile] fires once with the
/// dropped file's bytes and name.
Object attachFileDrop({
  required void Function(Uint8List bytes, String fileName) onFile,
  required void Function(bool active) onDragStateChanged,
}) {
  var depth = 0;

  void onDragEnter(web.Event event) {
    event.preventDefault();
    depth++;
    onDragStateChanged(true);
  }

  void onDragOver(web.Event event) {
    // Must be prevented on every dragover (not just dragenter), or the
    // browser refuses the drop and shows its own "can't drop here" cursor.
    event.preventDefault();
  }

  void onDragLeave(web.Event event) {
    event.preventDefault();
    depth = depth > 0 ? depth - 1 : 0;
    if (depth == 0) onDragStateChanged(false);
  }

  void onDrop(web.Event event) {
    event.preventDefault();
    depth = 0;
    onDragStateChanged(false);
    final dragEvent = event as web.DragEvent;
    final files = dragEvent.dataTransfer?.files;
    final file = (files == null || files.length == 0) ? null : files.item(0);
    if (file == null) return;
    file.arrayBuffer().toDart.then((buffer) {
      onFile(buffer.toDart.asUint8List(), file.name);
    });
  }

  final listeners = [
    onDragEnter.toJS,
    onDragOver.toJS,
    onDragLeave.toJS,
    onDrop.toJS,
  ];
  const types = ['dragenter', 'dragover', 'dragleave', 'drop'];
  for (var i = 0; i < types.length; i++) {
    web.window.addEventListener(types[i], listeners[i]);
  }
  return listeners;
}

void detachFileDrop(Object? handle) {
  if (handle is! List) return;
  final listeners = handle.cast<JSFunction>();
  const types = ['dragenter', 'dragover', 'dragleave', 'drop'];
  for (var i = 0; i < types.length && i < listeners.length; i++) {
    web.window.removeEventListener(types[i], listeners[i]);
  }
}

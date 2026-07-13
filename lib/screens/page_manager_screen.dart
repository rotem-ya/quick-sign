import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/document_session.dart';
import '../models/placement.dart';
import '../services/import_service.dart';
import '../services/pdf_render_service.dart';
import '../theme/design_tokens.dart';

enum _StagedKind { blank, image, pdf }

class _StagedAppend {
  _StagedAppend.blank() : kind = _StagedKind.blank, bytes = null, pageCount = 1;

  _StagedAppend.image(Uint8List b)
    : kind = _StagedKind.image,
      bytes = b,
      pageCount = 1;

  _StagedAppend.pdf(Uint8List b, this.pageCount)
    : kind = _StagedKind.pdf,
      bytes = b;

  final _StagedKind kind;
  final Uint8List? bytes;
  final int pageCount;
}

/// Delete existing pages and append pages from images or another PDF —
/// the vector content of merged pages is preserved (not rasterized).
///
/// Nothing is committed until "Apply": deletions and additions are staged
/// locally, then folded into one new [DocumentSession] in a single step,
/// remapping every surviving placement to its new page index.
class PageManagerScreen extends StatefulWidget {
  const PageManagerScreen({
    super.key,
    required this.session,
    required this.renderService,
    required this.importService,
  });

  final DocumentSession session;
  final PdfRenderService renderService;
  final ImportService importService;

  @override
  State<PageManagerScreen> createState() => _PageManagerScreenState();
}

class _PageManagerScreenState extends State<PageManagerScreen> {
  final Set<int> _deletedIndices = {};
  final List<_StagedAppend> _staged = [];
  late final List<int> _order = List.generate(
    widget.session.pageCount,
    (i) => i,
  );
  bool _busy = false;

  bool get _isReordered =>
      !_order.asMap().entries.every((e) => e.value == e.key);

  bool get _hasChanges =>
      _deletedIndices.isNotEmpty || _staged.isNotEmpty || _isReordered;

  void _toggleDelete(int index) {
    setState(() {
      if (!_deletedIndices.remove(index)) _deletedIndices.add(index);
    });
  }

  void _reorder(int draggedOriginalIndex, int targetPosition) {
    setState(() {
      final fromPosition = _order.indexOf(draggedOriginalIndex);
      if (fromPosition == -1 || fromPosition == targetPosition) return;
      final item = _order.removeAt(fromPosition);
      _order.insert(targetPosition, item);
    });
  }

  Future<void> _addBlank() async {
    setState(() => _staged.add(_StagedAppend.blank()));
  }

  Future<void> _addImages() async {
    final images = await widget.importService.pickImageBytesMultiple();
    if (images.isEmpty || !mounted) return;
    setState(() {
      for (final bytes in images) {
        _staged.add(_StagedAppend.image(bytes));
      }
    });
  }

  Future<void> _addFromPdf() async {
    final bytes = await widget.importService.pickPdfBytes();
    if (bytes == null || !mounted) return;
    final count = ImportService.pdfPageCount(bytes);
    setState(() => _staged.add(_StagedAppend.pdf(bytes, count)));
  }

  void _removeStaged(_StagedAppend item) {
    setState(() => _staged.remove(item));
  }

  Future<void> _showAddMenu() async {
    final s = S.of(context);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined, size: 28),
              title: Text(s['blankPage'], style: const TextStyle(fontSize: 18)),
              minTileHeight: 56,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addBlank();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined, size: 28),
              title: Text(s['imagePage'], style: const TextStyle(fontSize: 18)),
              minTileHeight: 56,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, size: 28),
              title: Text(
                s['fromPdfFile'],
                style: const TextStyle(fontSize: 18),
              ),
              minTileHeight: 56,
              onTap: () {
                Navigator.of(sheetContext).pop();
                _addFromPdf();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    final s = S.of(context);
    if (!_hasChanges) {
      _snack(s['noChanges']);
      return;
    }
    final keepIndices = [
      for (final i in _order)
        if (!_deletedIndices.contains(i)) i,
    ];
    if (keepIndices.isEmpty && _staged.isEmpty) {
      // Deleting every page with nothing to replace them — refuse silently
      // by treating it as a no-op rather than producing an empty PDF.
      _snack(s['exportError']);
      return;
    }

    final lostCount = widget.session.placements.value
        .where((p) => _deletedIndices.contains(p.pageIndex))
        .length;
    if (lostCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, size: 32),
          title: Text(s['pagesLossWarningTitle']),
          content: Text(
            s['pagesLossWarning'].replaceAll('{n}', '$lostCount'),
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(s['cancel']),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(s['continue']),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      // Only the identity order (nothing deleted, nothing reordered) can
      // skip a rebuild — a same-length keepIndices can still be a reorder.
      final isIdentityOrder =
          keepIndices.length == widget.session.pageCount &&
          keepIndices.asMap().entries.every((e) => e.value == e.key);
      var bytes = isIdentityOrder
          ? widget.session.pdfBytes
          : ImportService.rebuildWithPages(
              widget.session.pdfBytes,
              keepIndices,
            );
      for (final item in _staged) {
        switch (item.kind) {
          case _StagedKind.blank:
            bytes = ImportService.appendBlankPage(bytes);
          case _StagedKind.image:
            bytes = ImportService.appendImagePage(bytes, item.bytes!);
          case _StagedKind.pdf:
            bytes = ImportService.mergePdfPages(bytes, item.bytes!);
        }
      }

      final newSession = await widget.importService.openBytes(
        bytes,
        fileName: widget.session.fileName,
      );
      final survivors = <Placement>[];
      for (final p in widget.session.placements.value) {
        final newIndex = keepIndices.indexOf(p.pageIndex);
        if (newIndex == -1) continue;
        survivors.add(
          Placement(
            type: p.type,
            pageIndex: newIndex,
            nx: p.nx,
            ny: p.ny,
            widthFraction: p.widthFraction,
            aspectRatio: p.aspectRatio,
            imageBytes: p.imageBytes,
            text: p.text,
            groupId: p.groupId,
          )..rotation = p.rotation,
        );
      }
      newSession.placements.value = survivors;

      if (!mounted) return;
      Navigator.of(context).pop(newSession);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(s['exportError']);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s['managePages'])),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Row(
                          children: [
                            Text(
                              s['existingPages'],
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.session.pageCount > 1) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.drag_indicator,
                                size: 15,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                s['dragToReorder'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var pos = 0; pos < _order.length; pos++)
                              _ReorderableExistingPageTile(
                                key: ValueKey(_order[pos]),
                                originalIndex: _order[pos],
                                position: pos,
                                displayNumber: pos + 1,
                                renderService: widget.renderService,
                                deleted: _deletedIndices.contains(_order[pos]),
                                onToggleDelete: () =>
                                    _toggleDelete(_order[pos]),
                                onReorder: _reorder,
                              ),
                          ],
                        ),
                        if (_staged.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            s['pagesToAdd'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final item in _staged)
                                _StagedTile(
                                  item: item,
                                  onRemove: () => _removeStaged(item),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showAddMenu,
                            icon: const Icon(Icons.add),
                            label: Text(s['addPages']),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 56),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _apply,
                            icon: const Icon(Icons.check),
                            label: Text(s['apply']),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 56),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Drag-and-drop reordering for the existing-pages grid: a [DragTarget] (drop
/// here) wrapping a [LongPressDraggable] (pick this tile up), keyed by the
/// page's original index so a drop always resolves to the right page
/// regardless of how many times the order has already changed.
class _ReorderableExistingPageTile extends StatelessWidget {
  const _ReorderableExistingPageTile({
    required super.key,
    required this.originalIndex,
    required this.position,
    required this.displayNumber,
    required this.renderService,
    required this.deleted,
    required this.onToggleDelete,
    required this.onReorder,
  });

  final int originalIndex;
  final int position;
  final int displayNumber;
  final PdfRenderService renderService;
  final bool deleted;
  final VoidCallback onToggleDelete;
  final void Function(int draggedOriginalIndex, int targetPosition) onReorder;

  @override
  Widget build(BuildContext context) {
    final tile = _ExistingPageTile(
      pageIndex: originalIndex,
      displayNumber: displayNumber,
      renderService: renderService,
      deleted: deleted,
      onToggleDelete: onToggleDelete,
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != originalIndex,
      onAcceptWithDetails: (details) => onReorder(details.data, position),
      builder: (context, candidateData, rejectedData) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: candidateData.isNotEmpty
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: LongPressDraggable<int>(
          data: originalIndex,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: Opacity(opacity: 0.9, child: tile),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: tile),
          child: tile,
        ),
      ),
    );
  }
}

class _ExistingPageTile extends StatelessWidget {
  const _ExistingPageTile({
    required this.pageIndex,
    required this.displayNumber,
    required this.renderService,
    required this.deleted,
    required this.onToggleDelete,
  });

  final int pageIndex;
  final int displayNumber;
  final PdfRenderService renderService;
  final bool deleted;
  final VoidCallback onToggleDelete;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 92,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  boxShadow: DesignTokens.shadowSm,
                ),
                clipBehavior: Clip.antiAlias,
                child: Opacity(
                  opacity: deleted ? 0.3 : 1,
                  child: FutureBuilder<Uint8List>(
                    future: renderService.renderPage(pageIndex),
                    builder: (context, snapshot) => snapshot.hasData
                        ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                        : const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Material(
                  color: deleted ? scheme.primary : scheme.error,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onToggleDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        deleted ? Icons.replay : Icons.close,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            deleted ? s['pageDeleted'] : '$displayNumber',
            style: TextStyle(
              fontSize: 12,
              color: deleted ? scheme.error : scheme.onSurfaceVariant,
              fontWeight: deleted ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _StagedTile extends StatelessWidget {
  const _StagedTile({required this.item, required this.onRemove});

  final _StagedAppend item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 92,
                height: 130,
                decoration: BoxDecoration(
                  color: DesignTokens.primarySoft,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  boxShadow: DesignTokens.shadowSm,
                ),
                clipBehavior: Clip.antiAlias,
                child: switch (item.kind) {
                  _StagedKind.blank => Icon(
                    Icons.insert_drive_file_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 30,
                  ),
                  _StagedKind.image => Image.memory(
                    item.bytes!,
                    fit: BoxFit.cover,
                  ),
                  _StagedKind.pdf => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.picture_as_pdf_outlined,
                          color: scheme.onPrimaryContainer,
                          size: 28,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.pageCount} ${s['nPages']}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                },
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Material(
                  color: scheme.error,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(Icons.close, size: 15, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

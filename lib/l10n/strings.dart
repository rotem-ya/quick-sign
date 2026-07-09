import 'package:flutter/widgets.dart';

/// Minimal string table. The UI is icon-first with short labels, so a tiny
/// lookup map is enough for the MVP — no codegen needed.
class S {
  S._(this._map);

  final Map<String, String> _map;

  static const Map<String, Map<String, String>> _tables = {
    'he': {
      'appTitle': 'QuickSign',
      'openDocument': 'פתיחת מסמך',
      'shareHint': 'או שיתוף קובץ לאפליקציה',
      'sign': 'חתימה',
      'stamp': 'חותמת',
      'note': 'הערה',
      'send': 'שליחה',
      'clear': 'ניקוי',
      'done': 'אישור',
      'share': 'שיתוף',
      'saveCopy': 'שמירת עותק',
      'copySaved': 'נשמר עותק באפליקציה',
      'myStamp': 'החותמת שלי',
      'savedSignature': 'החתימה השמורה',
      'tapToPlace': 'נגיעה במסמך למיקום',
      'noteHint': 'כתיבת הערה…',
      'stampSetupTitle': 'הגדרת חותמת',
      'captureStamp': 'צילום',
      'fromGallery': 'גלריה',
      'useStamp': 'שימוש בחותמת',
      'retake': 'שוב',
      'processing': 'רגע…',
      'importError': 'הקובץ לא נתמך (PDF או תמונה)',
      'exportError': 'הייצוא נכשל',
      'emptySignature': 'קודם מציירים חתימה',
      'newDocument': 'מסמך חדש',
      'stampHint': 'מצלמים חותמת על דף לבן — הרקע יוסר אוטומטית',
      'permanentTitle': 'הטמעה לצמיתות',
      'permanentBody':
          'החתימות, החותמות וההערות יוטמעו לצמיתות במסמך.\nלא ניתן יהיה לשנות או למחוק אותן לאחר מכן.',
      'continue': 'המשך',
      'cancel': 'ביטול',
      'withStamp': 'עם חותמת',
      'allPages': 'כל העמודים',
      'nothingToExport': 'עוד לא הונחה חתימה במסמך',
      'cropHint': 'מסמנים את אזור החותמת — גוררים את הפינות',
    },
    'en': {
      'appTitle': 'QuickSign',
      'openDocument': 'Open document',
      'shareHint': 'or share a file to the app',
      'sign': 'Sign',
      'stamp': 'Stamp',
      'note': 'Note',
      'send': 'Send',
      'clear': 'Clear',
      'done': 'Done',
      'share': 'Share',
      'saveCopy': 'Save copy',
      'copySaved': 'Copy saved in the app',
      'myStamp': 'My stamp',
      'savedSignature': 'Saved signature',
      'tapToPlace': 'Tap the page to place',
      'noteHint': 'Write a note…',
      'stampSetupTitle': 'Stamp setup',
      'captureStamp': 'Camera',
      'fromGallery': 'Gallery',
      'useStamp': 'Use stamp',
      'retake': 'Retake',
      'processing': 'One moment…',
      'importError': 'Unsupported file (PDF or image only)',
      'exportError': 'Export failed',
      'emptySignature': 'Draw a signature first',
      'newDocument': 'New document',
      'stampHint': 'Photograph the stamp on white paper — the background is removed automatically',
      'permanentTitle': 'Permanent embedding',
      'permanentBody':
          'Signatures, stamps and notes will be permanently embedded in the document.\nThey cannot be changed or removed afterwards.',
      'continue': 'Continue',
      'cancel': 'Cancel',
      'withStamp': 'With stamp',
      'allPages': 'All pages',
      'nothingToExport': 'No signature placed yet',
      'cropHint': 'Mark the stamp area — drag the corners',
    },
  };

  static S of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return S._(_tables[code] ?? _tables['en']!);
  }

  String operator [](String key) => _map[key] ?? _tables['en']![key] ?? key;
}

# הנחיות ל-Cowork / סשן Claude חדש — QuickSign

מסמך העברה (handoff). קרא אותו במלואו לפני נגיעה בקוד.

## מה זה הפרויקט

אפליקציית Flutter לחתימה על מסמכים (אנדרואיד + iOS + Web). מקבלים PDF/תמונה
(שיתוף / "פתיחה באמצעות" / בחירה), מסמנים אזור בלחיצה ארוכה, חותמים ביד או
בחותמת, והקובץ המיוצא **משוטח ברסטריזציה** — החתימה היא חלק מפיקסלי הדף.

**ענף העבודה:** `claude/document-signing-app-k3ae8n` (repo: rotem-ya/quick-sign)

## עקרונות מקודשים — אל תשבור

1. **פרטיות:** המסמכים לא עוזבים את המכשיר. אין שרת, אין העלאה. כל פיצ'ר ענן
   הוא רק לתשתית (hosting, גיבוי הגדרות) — לא למסמכים עצמם.
2. **פשטות:** מסך עבודה אחד. UI מבוסס אייקונים, מינימום טקסט, עברית+אנגלית
   (RTL אוטומטי). state עם setState/ValueNotifier — בלי Bloc/Riverpod.
3. **צינור bytes אחיד:** אותו קוד רץ במובייל וב-web. אין `File` paths בזרימה
   המרכזית — רק `Uint8List` (ראה DocumentSession.pdfBytes).
4. **WYSIWYG:** מה שרואים על המסך = מה שמיוצא. גודל טקסט נקבע ב-
   `ExportService.noteFontSize` — נוסחה אחת למסך ולייצוא. אל תכפיל אותה.
5. **קואורדינטות מנורמלות (0..1)** לכל הנחה + rotation ברדיאנים. הייצוא
   ב-`ExportService.rasterizePage` חייב לשקף כל שינוי שנעשה ב-overlay.
6. **בדיקות:** `flutter analyze` נקי ו-`flutter test` ירוק לפני כל commit.
   הבדיקות תפסו כבר שלושה באגים אמיתיים — אל תדלג.

## מפת קוד מהירה

- `lib/screens/work_screen.dart` — המסך היחיד: viewer עם InteractiveViewer,
  לחיצה ארוכה+סימון אזור, overlays, toolbar, ייצוא.
- `lib/services/export_service.dart` — רסטריזציה. הלב של המוצר.
- `lib/services/import_service.dart` — share/view-intent/picker → PDF bytes;
  הוספת דפים (`pages.insert` — לא `add`, שמתעלם מגודל במסמך טעון!).
- `lib/services/stamp_service.dart` — הסרת רקע אדפטיבית (רקע נדגם משוליים),
  חיתוך, קומפוזיציה חתימה-על-חותמת, אחסון base64 ב-prefs (מגובה אוטומטית).
- `lib/screens/stamp_designer_screen.dart` — מעצב חותמת דיגיטלית (תבנית).
- `lib/widgets/placement_overlay.dart` — גרירה/צביטה/סיבוב/ידיות. הידיות
  חייבות להיות בתוך גבולות ה-hit-test (באג שכבר תוקן — אל תחזיר אותו).
- `FEATURES.md` — **צ'קליסט מחייב.** כל פיצ'ר חדש מסומן שם. עדכן אותו בכל סבב.

## סביבת עבודה

```bash
flutter pub get
flutter analyze && flutter test          # חובה ירוק
flutter run                              # מכשיר
flutter build apk --release --split-per-abi
flutter build web --release --no-web-resources-cdn   # בלי CDN! pdf.js ארוז ב-web/js
```

- APK עדכני תמיד ב-`releases/quick-sign-arm64.apk` (מתעדכן בכל סבב).
- אנדרואיד: minSdk ברירת מחדל; דרושה פלטפורמת android-37 ב-SDK.
- אל תחזיר את `pdfx`/`canvaskit` ל-CDN — הכול ארוז מקומית בכוונה.

## משימות שדורשות את המחשב/חשבונות של המשתמש (בשביל זה Cowork)

לפי סדר עדיפות:

1. **פריסת Web ל-Firebase Hosting** — `firebase.json` + workflow מוכנים
   (`.github/workflows/deploy-firebase.yml`, ההוראות בכותרת הקובץ).
   דרך CLI מקומי זה אפילו פשוט יותר:
   `npm i -g firebase-tools && firebase login && firebase init hosting (לבחור את הפרויקט הקיים) && flutter build web --release --no-web-resources-cdn && firebase deploy`
2. **מזהי AdMob אמיתיים** — admob.google.com → צור אפליקציה + באנר; החלף ב:
   `AndroidManifest.xml` (APPLICATION_ID), `ios/Runner/Info.plist`
   (GADApplicationIdentifier), `lib/widgets/ad_banner.dart` (unit IDs).
3. **Application ID** — החלף `com.example.quick_sign` (build.gradle.kts,
   namespace, kotlin package, iOS bundle id) לפני העלאה לחנות.
4. **Keystore לחתימת release** — כרגע debug signing. `keytool -genkey` +
   signingConfig ב-build.gradle.kts.
5. **פיצ'רים בתור (FEATURES.md "בתור"):**
   - שמירה ישירה לתיקיית ברירת מחדל (SAF OPEN_DOCUMENT_TREE + הרשאה מתמשכת)
   - התחברות Drive/OneDrive (דורש OAuth Client ID שהמשתמש יוצר)
   - צילום חותמת → חותמת דיגיטלית ערוכה (ML Kit OCR מקומי)
6. **iOS** (רק על Mac): Share Extension + App Group לפי README של
   receive_sharing_intent; בדיקת הדפסה/שיתוף במכשיר.

## איך לעבוד מול המשתמש

- עברית. משפטים ישירים. בכל סבב: מה נעשה סעיף-סעיף, מה נשאר, ו-APK מעודכן.
- המשתמש בודק במכשיר גלקסי ומחזיר פידבק קצר — תרגם כל סעיף למשימה, עדכן
  את FEATURES.md, ואל תסמן דבר כ"בוצע" בלי analyze+tests ירוקים.
- אם דרישה סותרת את עקרונות 1-2 (שרת/מורכבות) — אמור זאת מפורשות והצע
  חלופה שעובדת היום, כמו שנעשה עם ההתחברות (גיבוי לקובץ במקום OAuth חסר).

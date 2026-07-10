# QuickSign

אפליקציית **Flutter** לחתימה על מסמכים — **אנדרואיד, iOS ו-Web** — בפשטות מוחלטת.

🌐 **גרסת ה-Web חיה:** https://rotem-ya.github.io/quick-sign/
📱 **APK לאנדרואיד:** [releases/quick-sign-arm64.apk](releases/quick-sign-arm64.apk)

מקבלים מסמך (PDF או תמונה) דרך שיתוף, "פתיחה באמצעות" או בחירה ידנית —
מקישים במקום שבו רוצים לחתום, חותמים ביד או בחותמת שמורה, ושולחים חזרה.
המסמך החתום **משוטח לתמיד**: החתימות נצרבות לפיקסלי הדף ואי-אפשר להעתיק,
לסמן או לחלץ אותן.

הכול קורה **מקומית במכשיר** — אין שרת, אין העלאת קבצים, אין הרשמה.

## יכולות

| | |
|---|---|
| 📥 **קבלה** | שיתוף מוואטסאפ/מייל, "פתיחה באמצעות", או בחירת קובץ (PDF / JPG / PNG) |
| ✍️ **חתימה** | ציור ביד, חתימה שמורה בנגיעה, חתימה על גבי חותמת, חתימה על כל העמודים בבת אחת |
| 🔖 **חותמת** | צילום או חילוץ מתוך מסמך מצולם (סימון אזור) — הרקע הלבן מוסר אוטומטית |
| 💬 **הערות** | טקסט חופשי בעברית/אנגלית, גופן Heebo מוטמע, WYSIWYG מלא |
| 🎛️ **עריכה** | גרירה, הגדלה/הקטנה (+/− או צביטה), סיבוב (ידית או שתי אצבעות), מחיקה עם ביטול |
| 📤 **ייצוא** | שיתוף · **שמירה אל Google Drive / OneDrive / כל תיקייה משותפת** (דיאלוג המערכת) · הורדה ב-web |
| 🔍 **תצוגה** | זום עד פי 6, גדלי ברירת מחדל פרופורציונליים לטקסט של המסמך עצמו |
| ☁️ **גיבוי** | החתימה והחותמת שורדות מחיקה והתקנה מחדש דרך הגיבוי האוטומטי של אנדרואיד — בלי חשבון ובלי שרת |
| 🌐 **Web** | אותה אפליקציה בדיוק רצה בדפדפן במחשב — כולל pdf.js מקומי, בלי תלות ב-CDN |

## תיקייה משותפת לאנשי שטח ומשרד

לא צריך שרת: פותחים תיקייה משותפת ב-Google Drive / OneDrive של הארגון,
ואנשי השטח שומרים את המסמכים החתומים ישירות אליה עם **"שמירה אל…"** —
QuickSign משתמש בדיאלוג השמירה של מערכת ההפעלה, כך שכל ספק אחסון שמותקן
במכשיר (Drive, OneDrive, Dropbox…) זמין אוטומטית, בלי התחברות בתוך האפליקציה
ובלי שהמסמך עובר דרך צד שלישי.

## הרצה

```bash
flutter pub get
flutter run              # מכשיר / אמולטור
flutter run -d chrome    # דפדפן
```

בדיקות וניתוח סטטי:

```bash
flutter analyze
flutter test
```

בניית גרסאות:

```bash
flutter build apk --release --split-per-abi     # אנדרואיד
flutter build web --release --no-web-resources-cdn   # web (עצמאי, בלי CDN)
```

## פריסת ה-Web

- **GitHub Pages** — מוכן: `.github/workflows/deploy-web.yml` בונה ופורס בכל
  דחיפה ל-main. הפעלה חד-פעמית: Settings → Pages → Source: GitHub Actions.
  שימו לב: Pages בריפו פרטי דורש תוכנית בתשלום — או להפוך את הריפו לציבורי.
- **כל אחסון סטטי אחר** (Netlify / Vercel / Firebase Hosting): מעלים את תוכן
  `build/web` כמו שהוא.

## מבנה הקוד

```
lib/
├── main.dart / app.dart           # אתחול, theme (Heebo), לוקליזציה he/en
├── l10n/strings.dart              # טבלת מחרוזות מינימלית
├── models/                        # Placement (קואורדינטות מנורמלות 0..1 + סיבוב), DocumentSession (bytes)
├── services/
│   ├── import_service.dart        # share / view intent / picker → PDF bytes
│   ├── pdf_render_service.dart    # רינדור עמודים (pdfx — pdfium/pdf.js)
│   ├── export_service.dart        # שיטוח ברסטריזציה — חתימה כחלק מפיקסלי הדף
│   ├── stamp_service.dart         # צילום/חיתוך/הסרת רקע, אחסון מגובה
│   ├── document_metrics.dart      # מדידת גובה שורות לגדלים פרופורציונליים
│   └── share_service.dart         # שיתוף / שמירה-אל (SAF) / הורדת דפדפן
├── screens/                       # work_screen (המסך היחיד), stamp_setup_screen
└── widgets/                       # signature_sheet, placement_overlay, bottom_toolbar, note_sheet, ad_banner
```

## צ'קליסט פיצ'רים עתידיים

- [x] **שמירת החתימות גם אחרי מחיקת האפליקציה** — ממומש דרך Android Auto
  Backup (ללא חשבון). סנכרון בין מכשירים עם התחברות Google/Apple — עדיין פתוח.
- [ ] **הדפסה** — כפתור הדפסה של המסמך החתום ישירות מהאפליקציה
  (חבילת `printing` — מתחברת לשירות ההדפסה של אנדרואיד ו-iOS).

## לפני שחרור — TODO ידני

- **iOS Share Extension:** קבלת קבצים ב-Share על iOS דורשת הוספת
  Share Extension target + App Group ב-Xcode לפי ה-README של
  [`receive_sharing_intent`](https://pub.dev/packages/receive_sharing_intent).
  ב-Android זה עובד כבר עכשיו דרך ה-intent-filters במניפסט.
- **AdMob:** להחליף את מזהי הבדיקה במזהים אמיתיים —
  `AndroidManifest.xml` (APPLICATION_ID), `Info.plist` (GADApplicationIdentifier),
  ו-`lib/widgets/ad_banner.dart` (ad unit IDs).
- **Application ID:** לשנות `com.example.quick_sign` למזהה אמיתי.

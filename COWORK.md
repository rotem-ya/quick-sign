# הנחיות ל-Cowork / סשן Claude חדש — QuickSign

מסמך העברה (handoff). קרא אותו במלואו לפני נגיעה בקוד.

## מה זה הפרויקט

אפליקציית Flutter לחתימה על מסמכים (אנדרואיד + iOS + Web). מקבלים PDF/תמונה
(שיתוף / "פתיחה באמצעות" / בחירה), מסמנים אזור בלחיצה ארוכה, חותמים ביד או
בחותמת, והקובץ המיוצא **משוטח ברסטריזציה** — החתימה היא חלק מפיקסלי הדף.

**ענף העבודה:** `claude/design-overhaul-ygo0d1` (repo: rotem-ya/quick-sign) —
אם ה-PR של הענף הזה כבר מוזג, תפתחו ענף חדש מ-`main` (ר' ההוראה על כך
בהודעת המשימה של הסשן) ותשמרו את אותו שם.

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

## 📚 לפני הכל — ריפו מדריכים חוזרים

`rotem-ya/claude-guides` מכיל מדריכים שנבדקו בפועל מול קוד אמיתי (לא
תיאוריה) בפרויקטים קודמים. **קרא אותם לפני שמתחילים בסעיפים 1-2 למטה —
זה בדיוק התהליך המדויק, כולל תקלות ידועות ופתרונות:**
- `firebase-auth/FIREBASE_AUTH_SETUP_GUIDE.md` — Firebase Auth עם
  Google+Apple Sign-In (מבוסס על `rotem-ya/whoisthere`).
- `store-release/COWORK_STORE_RELEASE_GUIDE.md` — הגשה ל-TestFlight/Play
  דרך Codemagic (iOS) ו-GitHub Actions (Android), בלי לפתוח Xcode/Android
  Studio בכלל.

אם הריפו לא בסקופ של הסשן: `add_repo owner=rotem-ya repo=claude-guides`.

## ✅ כבר בוצע (לא צריך לחזור על זה)

- **Application ID אחיד** — `com.rotem.quicksign` בכל הפלטפורמות
  (אנדרואיד/iOS/macOS/Linux). זה קבוע לצמיתות ברגע שנרשם ב-Firebase/חנות —
  אל תשנה בלי סיבה טובה.
- **Upload keystore** נוצר ונשלח לבעל המוצר בנפרד (**לא בגיט** —
  `**/*.jks` ב-`.gitignore`). `android/app/build.gradle.kts` כבר קורא
  `android/app/keystore.jks` + 3 env vars (`KEYSTORE_STORE_PASS`/
  `KEYSTORE_ALIAS`/`KEYSTORE_KEY_PASS`) לחתימת release, ונופל חזרה ל-debug
  signing אם הקובץ לא קיים (כך שפיתוח מקומי לא נשבר).
- `.github/workflows/build-aab.yml` — בונה AAB חתום, מצפה ל-4 GitHub
  Secrets (ר' סעיף 2 למטה).
- `codemagic.yaml` בשורש — workflow ל-iOS TestFlight, מצפה לאינטגרציית
  App Store Connect בשם `Apple_Key_QuickSign` (חייב להתאים אות-באות למה
  שנוצר בפועל ב-Codemagic).
- **עיצוב מחדש מקצה לקצה** (design tokens, theme, כל המסכים) — פרטים
  מלאים ב-`FEATURES.md`.
- **קוד Firebase Auth (Google+Apple) מוכן ומחכה רק לקונפיג אמיתי** —
  `lib/services/auth_service.dart` (sign-in + עקיפת באג Pigeon codec
  ידוע), מסך ההגדרות כבר מציג כפתורי כניסה אמיתיים (`isAvailable`),
  `lib/firebase_options.dart` הוא placeholder מפורש, ו-`Firebase.
  initializeApp` עטוף ב-try/catch כך שהאפליקציה עובדת רגיל גם בלעדיו.
  **נבדק בפועל על מכשיר גלקסי אמיתי (לא רק web)**: לפני התיקון, אנדרואיד
  ניסה בפועל להתחבר מול הפרויקט המזויף וקיבל `PlatformException(
  sign_in_failed, ... ApiException: 10 ...)` — כי `Firebase.
  initializeApp()` **לא נכשל** מקומית באנדרואיד עם ערכים מזויפים (בניגוד
  ל-web, ששם יש בדיקת רשת שנכשלת מיד). תוקן ב-`main.dart` עם בדיקה
  מפורשת של `projectId != 'placeholder'` **לפני** הקריאה ל-
  `initializeApp` בכלל. אם מוסיפים עוד שדה/מנגנון בדיקת-placeholder,
  חובה לבדוק גם על מכשיר אמיתי, לא רק בדפדפן — ההתנהגות שונה.
  ר' סעיף 1 למטה למה שבאמת חסר.
- **מסך "ספריית תיקיות"** (`lib/screens/folder_browser_screen.dart`) —
  בחירת כמה תיקיות שרוצים (SAF באנדרואיד, File System Access API
  ב-web), רשימת קבצים משולבת עם סינון/מיון, פתיחה ישירה למסך העבודה.
- **תוקן: טקסט על `FilledButton` לא הוצג בכלל** (Flutter 3.44.6, גם
  ב-web וגם באנדרואיד נייטיב — נבדק בפועל בשתיהן) — כל האפליקציה עברה
  ל-`ElevatedButton` בעיצוב שטוח זהה. אם משדרגים גרסת Flutter, כדאי
  לבדוק אם אפשר לחזור ל-`FilledButton`.

## משימות שדורשות את המחשב/חשבונות של המשתמש (בשביל זה Cowork)

לפי סדר עדיפות:

1. **Firebase Auth (Google+Apple)** — הקוד מוכן (ר' "כבר בוצע" למעלה).
   מה שנשאר, ובאיזה סדר:
   - **`firebase login`/`login:ci` לא עובד מתוך סביבת ה-Cowork** — הבדיקה
     בפועל: `auth.firebase.tools` דוחה את הבקשה עם `"Unable to verify
     client"` (כנראה חוסם בקשות login אוטומטיות/לא-אינטראקטיביות).
     **הדרך שעובדת: מפתח Service Account**, לא login אישי:
     1. console.firebase.google.com → אם אין עדיין פרויקט ל-quicksign,
        "Add project".
     2. **באותו ביקור**, שני דברים בפרויקט: (א) Authentication →
        Sign-in method → Google → Enable (**אין מקבילה ב-CLI לצעד הזה**
        — היחיד שבאמת חייב קליק בקונסולה). (ב) ⚙️ Project settings →
        Service accounts → **Generate new private key** → מוריד JSON.
     3. בעל המוצר שולח את תוכן ה-JSON (לא נכנס לגיט — נשמר מקומית
        וב-`.gitignore`).
     4. מה-JSON: `npm i -g firebase-tools && dart pub global activate
        flutterfire_cli`, ואז `GOOGLE_APPLICATION_CREDENTIALS=<path-to-json>
        flutterfire configure --project=<project-id>
        --platforms=android,ios,web
        --android-package-name=com.rotem.quicksign
        --ios-bundle-id=com.rotem.quicksign` — יוצר את
        `lib/firebase_options.dart` האמיתי (מחליף את ה-placeholder),
        ורושם את שתי האפליקציות.
     5. SHA-1 של ה-upload keystore (כבר נוצר, ר' למעלה) → Firebase
        Console → Project settings → אפליקציית Android → Add fingerprint
        (או דרך `firebase apps:android:sha:create` עם אותו Service
        Account, ללא עוד login).
   - Apple Sign-In: בנפרד ורק אם רוצים — דורש חשבון Apple Developer
     בתשלום (App ID capability + Xcode Signing & Capabilities), ואז
     Authentication → Sign-in method → Apple → Enable ב-Firebase.
2. **הגשה לחנויות** — לפי `store-release/COWORK_STORE_RELEASE_GUIDE.md`
   המלא: App Store Connect + מפתח API (Apple), חיבור הריפו ל-Codemagic
   בשם אינטגרציה שתואם ל-`codemagic.yaml`, יצירת אפליקציה ב-Play Console,
   והוספת 4 GitHub Secrets מה-upload keystore שכבר קיים
   (`UPLOAD_KEYSTORE_BASE64`/`UPLOAD_KEYSTORE_PASSWORD`/
   `UPLOAD_KEY_ALIAS`/`UPLOAD_KEY_PASSWORD`) ב-GitHub → Settings →
   Secrets and variables → Actions.
3. **פריסת Web ל-Firebase Hosting** — `firebase.json` + workflow מוכנים
   (`.github/workflows/deploy-firebase.yml`, ההוראות בכותרת הקובץ).
   דרך CLI מקומי זה אפילו פשוט יותר:
   `npm i -g firebase-tools && firebase login && firebase init hosting (לבחור את הפרויקט הקיים) && flutter build web --release --no-web-resources-cdn && firebase deploy`
4. **מזהי AdMob אמיתיים** — admob.google.com → צור אפליקציה + באנר; החלף ב:
   `AndroidManifest.xml` (APPLICATION_ID), `ios/Runner/Info.plist`
   (GADApplicationIdentifier), `lib/widgets/ad_banner.dart` (unit IDs).
5. **פיצ'רים בתור (FEATURES.md "בתור"):**
   - התחברות Drive/OneDrive (דורש OAuth Client ID שהמשתמש יוצר)
   - צילום חותמת → חותמת דיגיטלית ערוכה (ML Kit OCR מקומי)
6. **iOS** (רק על Mac, או דרך Codemagic כמו בסעיף 2): Share Extension +
   App Group לפי README של receive_sharing_intent; בדיקת הדפסה/שיתוף
   במכשיר.

## איך לעבוד מול המשתמש

- עברית. משפטים ישירים. בכל סבב: מה נעשה סעיף-סעיף, מה נשאר, ו-APK מעודכן.
- המשתמש בודק במכשיר גלקסי ומחזיר פידבק קצר — תרגם כל סעיף למשימה, עדכן
  את FEATURES.md, ואל תסמן דבר כ"בוצע" בלי analyze+tests ירוקים.
- אם דרישה סותרת את עקרונות 1-2 (שרת/מורכבות) — אמור זאת מפורשות והצע
  חלופה שעובדת היום, כמו שנעשה עם ההתחברות (גיבוי לקובץ במקום OAuth חסר).

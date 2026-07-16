# הקמת Firebase Auth (Google + Apple) לפרויקט Flutter חדש — מדריך לקלוד

מסמך הפניה. תעתיק את הקובץ הזה לריפו של quicksign (למשל בתור `FIREBASE_AUTH_SETUP.md` בשורש) ותן לקלוד שם לעבוד לפיו. המקור: כך זה בנוי בפועל בפרויקט WhoIsThere (`rotem-ya/whoisthere`), אחרי בדיקה ישירה בקוד, לא מהזיכרון.

---

## 0. סקירה כללית — מה בדיוק צריך

שלושה חלקים נפרדים לגמרי:
1. **פרויקט Firebase** — נרשם פעם אחת, מכיל את שני האפליקציות (Android+iOS) תחתיו.
2. **Google Sign-In** — דורש אישורי OAuth שנוצרים אוטומטית ע"י Firebase לאנדרואיד, אבל **ב-iOS צריך שלב ידני נוסף** שקל לפספס.
3. **Apple Sign-In** — עובד רק ב-iOS (native), דורש שינוי בחשבון המפתח של אפל (Apple Developer) ולא רק ב-Firebase.

חשוב: ב-WhoIsThere, Google Sign-In **מוסתר לגמרי ב-iOS** כי השלב הידני הנוסף (סעיף 3) מעולם לא בוצע. אם ב-quicksign רוצים Google עובד גם ב-iOS, אסור לדלג על סעיף 3 — זו לא בחירה, זו דרישה טכנית.

---

## 1. יצירת פרויקט Firebase + רישום שתי האפליקציות

1. [console.firebase.google.com](https://console.firebase.google.com) → **Add project** → שם הפרויקט (יקבל project id ייחודי, למשל `whoisthere-380fa` בדוגמה שלנו — לא תמיד זהה לשם שנבחר).
2. Analytics אפשר להשאיר דלוק (ברירת מחדל) — לא חובה.
3. בתוך הפרויקט → **Project settings → Your apps → Add app**:
   - **Android**: package name (למשל `com.rotem.quicksign`) — **זה קבוע לצמיתות, אי אפשר לשנות אחרי פרסום בחנות**. מוריד `google-services.json`.
   - **iOS**: bundle ID (למשל אותו `com.rotem.quicksign`) — גם קבוע לצמיתות. מוריד `GoogleService-Info.plist`.
   - **המלצה:** תשתמשו באותו identifier בשתי הפלטפורמות (ב-WhoIsThere הם שונים בטעות היסטורית — `com.whoisthere.app` באנדרואיד מול `com.rotem.whoisthere` ב-iOS — זה עובד אבל מיותר ומבלבל).

## 2. חיבור לפרויקט Flutter — FlutterFire CLI

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<project-id>
```
זה יוצר אוטומטית את `lib/firebase_options.dart` (המבנה: `FirebaseOptions` לכל פלטפורמה עם `apiKey`/`appId`/`projectId`/`storageBucket`) ומוודא ש-`google-services.json`/`GoogleService-Info.plist` נמצאים במקום הנכון:
- Android: `android/app/google-services.json`
- iOS: `ios/Runner/GoogleService-Info.plist`

**קובצי ה-config האלה מכילים רק מזהים ציבוריים (לא סודות אמיתיים) — ב-WhoIsThere הם נשמרים בגיט (לא ב-`.gitignore`). זו החלטה מודעת, תחליטו אותו דבר ב-quicksign במקום להסתיר אותם "כאילו" הם סוד.**

### pubspec.yaml — חבילות מדויקות (הגרסאות שעובדות יחד ב-WhoIsThere)
```yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_auth: ^4.16.0
  cloud_firestore: ^4.14.0
  firebase_storage: ^11.6.0
  firebase_messaging: ^14.7.10   # רק אם צריך פוש
  firebase_analytics: ^10.8.0    # אופציונלי

  google_sign_in: ^6.2.2
  sign_in_with_apple: ^6.1.0
  crypto: ^3.0.0                 # ל-nonce של Apple sign-in

dependency_overrides:
  # קריטי: גרסאות חדשות יותר של google_sign_in_ios עברו ל-GoogleSignIn 8 /
  # GoogleUtilities 8, שמתנגש עם ה-GoogleUtilities ~> 7 של Firebase 10.
  # בלי הפין הזה ה-pod install נכשל בהתנגשות תלויות.
  google_sign_in_ios: 5.7.8
```

## 3. Android — הגדרת Google Sign-In

`android/app/build.gradle`:
```groovy
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"   // ← חובה, זה מה שקורא את google-services.json
}
android {
    namespace "com.rotem.quicksign"
    defaultConfig {
        applicationId "com.rotem.quicksign"
        minSdk 21   // Sign-in with Apple / Google לא דורשים יותר מזה
        ...
    }
}
```
אם `com.google.gms.google-services` לא מוחל אוטומטית (שגיאת build), לבדוק ב-`android/settings.gradle` אם צריך `pluginManagement { plugins { id 'com.google.gms.google-services' version '...' } }`.

**הנקודה הכי חשובה באנדרואיד — SHA-1 לכל מפתח חתימה בנפרד.**
Google Sign-In מאמת מול טביעת האצבע (SHA-1) של המפתח שחתם על ה-APK/AAB. **כל מפתח חתימה = פינגרפרינט נפרד שצריך להירשם ב-Firebase**, אחרת מתקבל `ApiException: 10` (DEVELOPER_ERROR) רק על אותה וריאנטת build. ב-WhoIsThere יש בפועל 3 מפתחות שונים שכולם רשומים בנפרד:
- מפתח debug (לפיתוח מקומי/אמולטור)
- מפתח QA/CI (לבניית APK לבדיקות מהיר, לא דרך Play)
- מפתח ה-upload ל-Play Store (זה שחותם על ה-AAB שמועלה בפועל)
- **וגם** התעודה שגוגל פליי עצמו מייצר תחת Play App Signing (שונה מה-upload key!) — צריך לגלות אותה ב-Play Console → App integrity → App signing, ולהוסיף גם אותה.

איך מוציאים SHA-1:
```bash
# ממפתח debug (נתיב סטנדרטי, תמיד קיים):
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# מכל keystore אחר (upload/QA):
keytool -list -v -keystore <path-to-keystore>.jks -alias <alias>
```
כל SHA-1 שמתקבל: Firebase Console → Project settings → האפליקציה של Android → **Add fingerprint**.

הפעלת ה-provider עצמו: Firebase Console → **Authentication → Sign-in method → Google → Enable**.

## 4. iOS — הגדרת Google Sign-In (השלב שב-WhoIsThere דילגו עליו!)

`GoogleService-Info.plist` שמגיע רק מ-"Add app" רגיל **לא כולל CLIENT_ID/REVERSED_CLIENT_ID** אם לא הפעלתם את ה-provider לפני ההורדה, או אם הורדתם לפני שה-provider הופעל. בדקו את הקובץ — אם אין בו את השדות האלה, Google Sign-In פשוט לא יעבוד ב-iOS (זה בדיוק המצב הקיים ב-WhoIsThere כרגע, ולכן שם הכפתור מוסתר לגמרי באייפון).

**כדי שזה יעבוד ב-quicksign:**
1. Firebase Console → Authentication → Sign-in method → Google → Enable (**לפני** שמורידים מחדש את ה-plist).
2. Project settings → האפליקציה של iOS → **הורד מחדש** את `GoogleService-Info.plist` — עכשיו הוא אמור להכיל `CLIENT_ID` ו-`REVERSED_CLIENT_ID`.
3. `ios/Runner/Info.plist` — הוסיפו scheme חדש עם ה-`REVERSED_CLIENT_ID`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>REVERSED_CLIENT_ID_כאן</string></array>
  </dict>
  <!-- אם יש גם deep link משלכם, הוסיפו dict נוסף באותה מערך, לא תחליפו -->
</array>
```
בלי השלב הזה, לחיצה על "כניסה עם Google" ב-iOS פשוט לא תעשה כלום (ה-redirect חוזר לא ימצא לאן לחזור).

## 5. iOS — הגדרת Apple Sign-In

זה **לא** Firebase-side בעיקר — זה בעיקר Apple Developer + Xcode:

1. [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers) → מצאו את ה-App ID (`com.rotem.quicksign`) → ✔ **Sign In with Apple** capability → Save.
2. ב-Xcode: Runner target → **Signing & Capabilities → + Capability → Sign in with Apple**. זה כותב אוטומטית ל-`ios/Runner/Runner.entitlements`:
```xml
<key>com.apple.developer.applesignin</key>
<array><string>Default</string></array>
```
3. Firebase Console → Authentication → Sign-in method → **Apple → Enable**.
   **חשוב:** *אם* ה-bundle ID של האפליקציה זהה לזה שברישום ב-Firebase (זה המקרה הרגיל — native sign-in ישיר), **אין צורך** למלא Services ID / Team ID / Key ID / קובץ `.p8` בטופס ההפעלה של Firebase. השדות האלה נדרשים רק לזרימת Apple Sign-In מבוססת web/redirect (כמו התחברות מ-Android או מדפדפן) עם identifier שונה מה-bundle של האפליקציה. WhoIsThere לא ממלא את זה בכלל ועובד תקין, כי Apple Sign-In שם קיים רק ב-iOS native.
4. אם רוצים גם כפתור "Apple" מוצג באנדרואיד — הפתרון הפשוט (וזה מה ש-WhoIsThere עושה): הצג את הכפתור אבל חסום אותו מיידית עם הודעה "זמין רק באייפון", **אל תממש** את מלוא ה-web/redirect flow אלא אם באמת צריך משתמשי אנדרואיד להתחבר עם Apple ID.

## 6. הקוד — `AuthService` (התבנית המדויקת מ-WhoIsThere)

### Google
```dart
// בלי clientId/serverClientId — קריטי: Credential Manager (Android 14+)
// זורק DEVELOPER_ERROR (ApiException:10) כשההגדרה לא מדויקת לגמרי.
// ה-API הקלאסי מאמת רק מול ה-SHA-1 שרשום ב-google-services.json, וזה תמיד נכון.
final GoogleSignIn _googleSignIn = GoogleSignIn();

Future<UserModel?> signInWithGoogle() async {
  final googleUser = await _googleSignIn.signIn();
  if (googleUser == null) return null; // המשתמש סגר את הבורר.

  final googleAuth = await googleUser.authentication;
  final credential = GoogleAuthProvider.credential(
    idToken: googleAuth.idToken,
    accessToken: googleAuth.accessToken,
  );
  final userCredential = await _auth.signInWithCredential(credential);
  return _syncUser(userCredential.user!);
}
```

### Apple
```dart
static String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
  final rnd = math.Random.secure();
  return List.generate(length, (_) => charset[rnd.nextInt(charset.length)]).join();
}

Future<UserModel?> signInWithApple() async {
  final rawNonce = _generateNonce();
  final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

  final appleCredential = await SignInWithApple.getAppleIDCredential(
    scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    nonce: hashedNonce,
  );
  final oauthCredential = OAuthProvider('apple.com').credential(
    idToken: appleCredential.identityToken,
    rawNonce: rawNonce,
    accessToken: appleCredential.authorizationCode,
  );
  final userCredential = await _auth.signInWithCredential(oauthCredential);
  return _syncUser(userCredential.user!);
}
```

### באג ידוע ב-firebase_auth (Pigeon codec) — לשכפל אם נעולים על אותן גרסאות
עם `firebase_auth ^4.16.0` + `firebase_core ^2.24.2`, לפעמים ההתחברות **מצליחה בפועל** אבל צד ה-Dart זורק:
```
type 'List<Object?>' is not a subtype of type 'PigeonUserDetails?'
```
הפתרון: לא לזרוק שגיאה למשתמש — לחכות שנייה-שלוש ל-`authStateChanges()` שיפלוט משתמש לא-אנונימי, כי ההתחברות הנייטיבית כבר הצליחה:
```dart
static bool _isPigeonCastError(Object e) {
  final s = e.toString();
  return s.contains('PigeonUserDetails') ||
      (s.contains('List<Object?>') && s.contains('is not a subtype'));
}

Future<UserModel?> _recoverFromSignInError(String reason) async {
  try {
    final recoveredUser = await _auth
        .authStateChanges()
        .where((u) => u != null && !u.isAnonymous)
        .first
        .timeout(const Duration(seconds: 3));
    if (recoveredUser != null) return _syncUser(recoveredUser);
  } catch (_) {}
  return null;
}
```
עוטפים את שתי הפונקציות למעלה ב-`try { ... } on TypeError { return _recoverFromSignInError(...); } on PlatformException catch (e) { return _recoverFromSignInError(...); }`. אם ב-quicksign משתמשים בגרסת firebase_auth חדשה משמעותית, כדאי לבדוק קודם אם הבאג עדיין קיים לפני שמעתיקים את זה — יכול להיות שתוקן.

### שדרוג אורח (Anonymous) → חשבון קבוע
תבנית שימושית אם יש כניסת-אורח לפני ההתחברות: לפני שמתחברים בפועל, לנסות `anonUser.linkWithCredential(credential)`. אם זה נכשל עם `credential-already-in-use` / `provider-already-linked` / `email-already-in-use` (סימן שהחשבון הקבוע כבר קיים) — ללכוד את נתוני האורח, למחוק את מסמך האורח, להתחבר לחשבון הקבוע, ואז לכתוב את הנתונים שנלכדו על החשבון הקבוע (union/merge, לא דריסה).

## 7. חוקי Firestore — תבנית בסיסית

```
function signedIn() { return request.auth != null; }

match /users/{userId} {
  allow read: if signedIn();
  allow create, update: if signedIn() && request.auth.uid == userId;
  allow delete: if signedIn() && request.auth.uid == userId;  // נדרש למחיקת חשבון (Apple 5.1.1v)
}
```

## 8. תקלות נפוצות — פתרון מהיר

| שגיאה | סיבה | פתרון |
|---|---|---|
| `PlatformException(sign_in_failed, ... ApiException: 10 ...)` | SHA-1 של מפתח החתימה הנוכחי לא רשום ב-Firebase | הוציאו SHA-1 עם `keytool`, הוסיפו ב-Firebase Console, הורידו google-services.json מחדש |
| כפתור Google ב-iOS לא עושה כלום | חסר CLIENT_ID/REVERSED_CLIENT_ID ב-plist + scheme ב-Info.plist | סעיף 4 למעלה |
| `PigeonUserDetails` type error | באג ידוע בגרסת firebase_auth | סעיף 6 — recovery דרך authStateChanges |
| Apple Sign-In מציג כפתור אבל לא קורה כלום באנדרואיד | native Apple sign-in לא קיים באנדרואיד בכלל | הציגו הודעה שזה זמין רק ב-iOS, אלא אם ממש בונים web/redirect flow |
| `pod install` נכשל על התנגשות GoogleUtilities | google_sign_in_ios גרסה חדשה מתנגשת עם Firebase 10 | הוסיפו `dependency_overrides: google_sign_in_ios: 5.7.8` (או בדקו את הגרסה התואמת לפיירבייס שבחרתם) |
| `requires-recent-login` בזמן מחיקת חשבון | Firebase דורש אימות טרי לפעולות רגישות | קראו ל-reauthenticate (Google/Apple) לפי `providerData` ואז נסו שוב |

---

זהו כל מה שצריך כדי לשכפל בדיוק את מנגנון ה-Auth של WhoIsThere בפרויקט חדש. אין קובץ הקמה כזה קיים בריפו המקורי (הכל נעשה ידנית בזמנו) — זה המסמך הראשון מסוגו, אז שמרו אותו ב-quicksign כתיעוד קבוע.

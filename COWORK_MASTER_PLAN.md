# QuickSign — תוכנית ביצוע ל-Cowork (מקור אמת יחיד)

**מטרה:** להביא את QuickSign למצב מוגש לשתי החנויות (Google Play internal
testing + Apple TestFlight), כשההתחברות והסנכרון לחשבון עובדים.

**מי מבצע:** סוכן Cowork על המחשב של בעל המוצר (עם Flutter, keystore,
וגישה לחשבונות Firebase/Google Play/Apple). כל הקוד כבר מוכן ובנוי — מה
שנשאר הוא חתימה + קונסולות. בצע לפי הסדר; כל שלב עצמאי.

**עובדות קבועות:**
- ריפו: `rotem-ya/quick-sign` · ענף עבודה: `claude/app-store-submission-kr520m`
- Application/Bundle ID: `com.rotem.quicksign` · פרויקט Firebase: `quicksign-7c212`
- **SHA-1 שכבר רשום ב-Firebase ועובד להתחברות:**
  `C4:7E:16:7F:20:EE:34:86:6E:DA:63:5F:B5:A5:18:50:02:E9:62:BB`
  (= `c47e167f20ee34866eda635fb5a5185002e962bb`)
- מדיניות פרטיות (אחרי פרסום): `https://quicksign-7c212.web.app/privacy.html`
- כל התוכן לחנויות (ליסטינג, Data Safety, App Privacy): ב-`STORE_SUBMISSION.md`

---

## הבעיה שחוסמת עכשיו: `ApiException: 10` בהתחברות Google

ההתחברות נכשלת כי ה-APK שבמכשיר חתום במפתח שה-SHA-1 שלו **לא** רשום
ב-Firebase. הפתרון הפשוט ביותר: לחתום את ה-APK במפתח שכבר רשום (ה-SHA-1
למעלה) — בלי שום שינוי ב-Firebase.

### שלב 1 — לזהות איזה keystore נותן את ה-SHA-1 הרשום
הרץ על שני המפתחות האפשריים והשווה ל-SHA-1 למעלה:
```bash
# מפתח ה-debug (בדרך כלל):
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android | grep SHA1

# ה-upload keystore (אם נבנו איתו release):
keytool -list -v -keystore <path/to/upload-keystore.jks> \
  -alias <alias> | grep SHA1
```
המפתח שה-SHA1 שלו = `C4:7E:...:BB` הוא המפתח שאיתו צריך לחתום.

### שלב 2 — להוסיף אותו כ-4 GitHub Secrets
GitHub → repo → Settings → Secrets and variables → **Actions** → New:
- `UPLOAD_KEYSTORE_BASE64` = `base64 -w0 <אותו keystore>` (הפלט כמחרוזת אחת)
- `UPLOAD_KEYSTORE_PASSWORD` = סיסמת ה-store
- `UPLOAD_KEY_ALIAS` = ה-alias
- `UPLOAD_KEY_PASSWORD` = סיסמת המפתח

> אם המפתח הרשום הוא ה-debug.keystore: store-pass ו-key-pass שניהם
> `android`, ו-alias הוא `androiddebugkey`.

### שלב 3 — לבנות מחדש את ה-APK
GitHub → Actions → **"Build APK (preview)"** → Run workflow (branch:
`claude/app-store-submission-kr520m`). כשמסתיים, הורדה מ:
`https://github.com/rotem-ya/quick-sign/releases/download/apk-preview/app-release.apk`
בהערות ה-Release יופיע `Signed with: upload keystore` — סימן שההתחברות תעבוד.

> חלופה שקולה: לבנות מקומית `flutter build apk --release` (כשה-keystore
> הנכון ב-`android/app/keystore.jks`) — אותו תוצר בדיוק.

---

## שלב 4 — להפעיל Firestore + Storage (בשביל הסנכרון עצמו)

גם אחרי שההתחברות עובדת, השמירה לענן תיכשל עד שמפעילים את התשתית:
```bash
cd <ריפו> && git checkout claude/app-store-submission-kr520m && git pull
npm i -g firebase-tools && firebase login && firebase use quicksign-7c212
```
1. Firestore: https://console.firebase.google.com/project/quicksign-7c212/firestore
   → Create database → Production mode → אזור `eur3 (europe-west)`.
2. Storage: https://console.firebase.google.com/project/quicksign-7c212/storage
   → Get started → אותו אזור. (אם דורש Blaze — ר' הערה ב-`COWORK_FIREBASE.md`.)
3. פריסת הכללים שכבר בריפו:
   ```bash
   firebase deploy --only firestore:rules,storage:rules --project quicksign-7c212
   ```

### אימות הסנכרון (חובה)
התקן את ה-APK מ-Release, התחבר עם Google, ולחץ **"סנכרן עכשיו"** בהגדרות:
- `סונכרנו N פריטים לחשבון.` → עובד ✅
- שגיאה כלשהי → העתק אותה; היא אומרת מה חסר (permission-denied = כללים,
  not-found/unavailable = Firestore/Storage לא הופעלו).
בקונסולה ודא: Firestore `users/{uid}` + Storage `users/{uid}/marks/*.png`.

---

## שלב 5 — פרסום מדיניות הפרטיות (URL חובה לשתי החנויות)

```bash
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting --project quicksign-7c212
```
ודא: `https://quicksign-7c212.web.app/privacy.html` נטען. (פרטים: `COWORK_FIREBASE.md`.)

---

## שלב 6 — Google Play (Internal Testing)

1. ה-4 secrets כבר קיימים (שלב 2). בנה **AAB חתום**: Actions → "Build AAB
   (Google Play)" → Run workflow → הורד `app-release.aab`.
2. Play Console (חשבון מפתח 25$): Create app → QuickSign, עברית, חינם.
3. מלא: Privacy policy URL (שלב 5), Data safety + Content rating + Target
   audience + App access — **תשובות מוכנות ב-`STORE_SUBMISSION.md`**.
4. Testing → Internal testing → Create release → העלה AAB → הוסף בודקים →
   Start rollout → שתף קישור opt-in.
5. **חשוב:** אחרי ההעלאה, Play Console → Setup → App signing מציג את
   **SHA-1 של מפתח החתימה של Google (App signing key)** — הוסף גם אותו
   ב-Firebase (Add fingerprint), אחרת התחברות Google תיכשל בגרסה שמותקנת
   מהחנות (היא חתומה במפתח של Google, לא ב-upload).

---

## שלב 7 — Apple TestFlight

1. Apple Developer Program (99$/שנה).
2. App Store Connect → New App: iOS, QuickSign, Bundle ID `com.rotem.quicksign`,
   SKU `quicksign`, עברית.
3. App Store Connect API key → הוסף ב-Codemagic כ-integration בשם **בדיוק**
   `Apple_Key_QuickSign`.
4. חבר את הריפו ל-Codemagic, ואז:
   ```bash
   git tag ios-v1.0.0 && git push origin ios-v1.0.0
   ```
5. הבנייה תעלה ל-TestFlight אוטומטית. הוסף בודקים פנימיים.
6. מלא App Privacy (תשובות ב-`STORE_SUBMISSION.md`).
7. אמת על מכשיר iOS: **Sign in with Apple** + **סנכרן עכשיו** (ה-entitlement
   מחובר בקוד אך לא נבדק על iOS אמיתי עדיין).
8. ב-Firebase: Authentication → Sign-in method → **Apple → Enable**.

---

## מה לדווח בחזרה
עדכן אותי (Claude) אחרי כל שלב, ובמיוחד:
- מה הודעת "סנכרן עכשיו" הראתה (שלב 4).
- אם משהו נכשל — הטקסט המלא של השגיאה.
אני אתקן כל בעיית קוד/CI שתתגלה ואמשיך לדחוף לענף.

## מצב נוכחי (מה שכבר בוצע בקוד — לא לחזור על זה)
- ✅ כל הקוד בנוי ועובר קומפילציה ב-CI (בניית ה-APK הצליחה).
- ✅ תוקן: התחברות עושה מיזוג דו-כיווני (חתימות מקומיות תמיד עולות).
- ✅ נוסף כפתור "סנכרן עכשיו" עם שגיאה מדויקת; לוג הדיבאג הוסתר מבניית release.
- ✅ מדיניות פרטיות, ליסטינג, Data Safety, Feature graphic — מוכנים.
- ⬜ שלבים 1–7 למעלה — דורשים חשבון/keystore (Cowork).

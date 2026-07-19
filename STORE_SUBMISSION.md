# QuickSign — ערכת הגשה לחנויות (Store Submission Kit)

מסמך אחד עם **כל** מה שצריך כדי להגיש את QuickSign ל-preview/בדיקה בחנויות
Google Play ו-Apple App Store. הטקסטים מוכנים להעתקה-הדבקה. הצעדים שדורשים
חשבון מסומנים ב-🔑.

**זהות האפליקציה (קבועה — כבר רשומה בקוד):**
| | |
|---|---|
| שם | QuickSign |
| Application ID / Bundle ID | `com.rotem.quicksign` |
| גרסה נוכחית | `1.0.0` (build 1) |
| פרויקט Firebase | `quicksign-7c212` |
| אתר / Web חי | https://quicksign-7c212.web.app/ (Firebase Hosting) |
| **מדיניות פרטיות (URL)** | **https://quicksign-7c212.web.app/privacy.html** |
| איש קשר / תמיכה | rot4735@gmail.com |

> ⚠️ עמוד מדיניות הפרטיות מוגש דרך **Firebase Hosting** (פרויקט
> `quicksign-7c212`). הוא נכלל אוטומטית ב-`flutter build web` ולכן מתפרסם
> יחד עם האפליקציה. ראה "צעד 0" למטה. (ה-rewrite של ה-SPA לא מסתיר אותו —
> Firebase מגיש קובץ סטטי אמיתי לפני שהוא מפעיל rewrite.)

---

## צעד 0 — לפרסם את מדיניות הפרטיות דרך Firebase Hosting (חובה לשתי החנויות)

שתי החנויות דורשות **URL חי** למדיניות פרטיות. הקובץ `web/privacy.html` כבר
בענף הזה ונכנס אוטומטית ל-`build/web`. לפרסום (מבוצע ע"י Cowork על מחשב
המשתמש, ר' `COWORK_TASKS.md`):

```bash
npm i -g firebase-tools
firebase login
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting --project quicksign-7c212
```

אחרי הפריסה ודא שהכתובת `https://quicksign-7c212.web.app/privacy.html` נטענת
בדפדפן — זו הכתובת שמזינים בשתי החנויות.

---

## 🟢 Google Play — Internal Testing (המסלול המהיר ל-preview)

### מה כבר מוכן בקוד
- AAB חתום נבנה אוטומטית ע"י `.github/workflows/build-aab.yml`.
- החתימה (upload keystore) כבר קיימת אצל בעל המוצר.

### מה שנשאר (🔑 דורש את החשבון שלך)

**א. הגדרת חתימה ב-CI — פעם אחת:**
GitHub repo → Settings → Secrets and variables → Actions → הוסף 4 secrets
מה-upload keystore שכבר יש לך:
- `UPLOAD_KEYSTORE_BASE64` — הפלט של `base64 -w0 keystore.jks`
- `UPLOAD_KEYSTORE_PASSWORD`
- `UPLOAD_KEY_ALIAS`
- `UPLOAD_KEY_PASSWORD`

**ב. בניית ה-AAB:** Actions → "Build AAB (Google Play)" → Run workflow.
תוריד את ה-artifact `app-release-aab` (הקובץ `app-release.aab`).

**ג. Play Console** (חשבון מפתח Google Play — 25$ חד-פעמי):
1. Create app → שם: QuickSign, שפת ברירת מחדל: עברית, אפליקציה, חינם.
2. מלא את שאלוני החובה: Data safety, Content rating, Target audience,
   App access (ראה תשובות מוכנות למטה), Privacy policy URL (מלמעלה).
3. Testing → **Internal testing** → Create release → העלה את ה-AAB.
4. הוסף כתובות אימייל של בודקים → שמור → Review → Start rollout.
5. שתף את קישור ה-opt-in של הבודקים.

---

## 🍎 Apple App Store — TestFlight (מסלול ה-preview של אפל)

### מה כבר מוכן בקוד
- `codemagic.yaml` בונה IPA חתום ומעלה ל-TestFlight על tag `ios-v*`.
- entitlement של Sign in with Apple מחובר בקוד.

### מה שנשאר (🔑 דורש את החשבונות שלך)
1. **Apple Developer Program** (99$/שנה) — חובה ל-iOS.
2. **App Store Connect** → My Apps → + → New App:
   - Platform: iOS, שם: QuickSign, Bundle ID: `com.rotem.quicksign`,
     SKU: `quicksign`, שפה ראשית: עברית.
3. **App Store Connect API key** → צור integration ב-Codemagic בשם
   **בדיוק** `Apple_Key_QuickSign` (חייב להתאים ל-`codemagic.yaml`).
4. חבר את הריפו ל-Codemagic, ואז דחוף tag: `git tag ios-v1.0.0 && git push origin ios-v1.0.0`.
5. הבנייה תעלה אוטומטית ל-TestFlight. ב-App Store Connect → TestFlight,
   הוסף בודקים פנימיים.
6. מלא את שאלון App Privacy (תשובות מוכנות למטה) ואת פרטי ה-App Information.

---

## 📝 תוכן ליסטינג — מוכן להעתקה

### עברית
- **שם האפליקציה:** QuickSign — חתימה על מסמכים
- **תיאור קצר (עד 80 תווים):**
  חתמו על PDF ותמונות ישירות בטלפון. הכול נשאר במכשיר — בלי שרת, בלי הרשמה.
- **תיאור מלא:**
```
QuickSign הופך חתימה על מסמכים לפעולה של כמה שניות — והכול קורה מקומית במכשיר.

קבלו מסמך דרך שיתוף מוואטסאפ או מייל, "פתיחה באמצעות", או בחירת קובץ (PDF / JPG
/ PNG). הקישו במקום שבו רוצים לחתום, חתמו ביד או בחותמת שמורה, ושלחו חזרה. המסמך
החתום משוטח לתמיד — החתימה נצרבת לפיקסלי הדף ואי אפשר להזיז או לחלץ אותה.

• פרטיות מלאה — המסמכים לעולם לא עוזבים את המכשיר. אין שרת, אין העלאה.
• חתימה ביד או בחותמת שמורה, כולל חתימה על כל העמודים בבת אחת.
• חילוץ חותמת מתוך צילום מסמך — הרקע הלבן מוסר אוטומטית.
• הוספת הערות טקסט בעברית ובאנגלית, WYSIWYG מלא.
• גרירה, הגדלה/הקטנה, סיבוב, מחיקה עם ביטול.
• ייצוא בשיתוף, שמירה ל-Drive / OneDrive / כל תיקייה, או הורדה.
• גיבוי אופציונלי של החתימות וההגדרות לחשבון Google/Apple — לא של המסמכים.

בלי הרשמה, בלי פרסומות, בלי מעקב.
```
- **מילות מפתח:** חתימה, מסמכים, PDF, חתימה דיגיטלית, חותמת, טפסים, sign, signature

### English
- **App name:** QuickSign — Sign Documents
- **Short description (≤80 chars):**
  Sign PDFs and images right on your phone. Everything stays on-device.
- **Full description:**
```
QuickSign turns signing a document into a few-second task — and it all happens
locally on your device.

Receive a document via share from WhatsApp or email, "Open with", or by picking
a file (PDF / JPG / PNG). Tap where you want to sign, sign by hand or with a
saved stamp, and send it back. The signed document is flattened permanently —
the signature is baked into the page pixels and cannot be moved or extracted.

• Full privacy — documents never leave your device. No server, no upload.
• Sign by hand or with a saved stamp, including signing every page at once.
• Extract a stamp from a photo of a document — the white background is removed automatically.
• Add text notes in Hebrew and English, fully WYSIWYG.
• Drag, resize, rotate, delete with undo.
• Export via share, save to Drive / OneDrive / any folder, or download.
• Optional backup of your signatures and settings to a Google/Apple account — never your documents.

No sign-up, no ads, no tracking.
```
- **Keywords (Apple, ≤100 chars):** sign,signature,pdf,document,stamp,esign,form,fill,scan

---

## 🔒 שאלון Data Safety (Google Play) — תשובות מוכנות

- **Does your app collect or share any user data?** → **Yes** (רק בהתחברות אופציונלית).
- **Data types collected:**
  - *Personal info → Name* — Collected, **not** shared. Optional. Purpose: App
    functionality, Account management.
  - *Personal info → Email address* — Collected, **not** shared. Optional.
    Purpose: App functionality, Account management.
  - *Photos → Photos/images* (חתימות/חותמות ששמר המשתמש) — Collected, **not**
    shared. Optional. Purpose: App functionality.
- **המסמכים:** לא נאספים ולא משותפים — לא לבחור אף קטגוריה עבורם.
- **Is all data encrypted in transit?** → **Yes**.
- **Can users request data deletion?** → **Yes** (דרך אימייל התמיכה + התנתקות באפליקציה).
- **Data collection is optional (user can use the app without it)?** → **Yes**.

## 🔒 App Privacy (Apple App Store Connect) — תשובות מוכנות

- **Data collected:** Name, Email Address, User Content (signature/stamp images).
- **Linked to identity:** Yes (מקושר לחשבון ההתחברות). **Used for tracking:** **No**.
- **Purpose לכל אחד:** App Functionality (ו-Name/Email גם Account Management).
- **המסמכים הנחתמים:** לא נאספים — לא להצהיר עליהם.

## 🎯 שאלונים נוספים (תשובות)
- **Content rating / Age:** אין תוכן בוגר/אלימות/הימורים → דירוג לכל הגילאים
  (Everyone / 4+).
- **Target audience:** מבוגרים / כללי (לא מיועד לילדים).
- **App access:** כל הפיצ'רים זמינים בלי התחברות → "All functionality is
  available without special access" (אין צורך בפרטי כניסה לבודק).
- **Ads:** אין פרסומות בגרסה זו → "No, my app does not contain ads".

---

## 📸 צילומי מסך (Screenshots) — מה צריך

שתי החנויות דורשות צילומי מסך. הכי קל: הרץ את גרסת ה-Web החיה או את האפליקציה
במכשיר וצלם 3–5 מסכים. מומלץ:
1. מסך הבית / ההיסטוריה.
2. מסמך פתוח עם חתימה ביד מונחת עליו.
3. חתימה בחותמת שמורה.
4. מסך ההגדרות (חתימות/חותמות שמורות).
5. תוצאה סופית — מסמך חתום.

דרישות גודל:
- **Google Play:** לפחות 2 צילומים, מ-320px עד 3840px בצד, יחס 16:9 או 9:16.
  בנוסף: אייקון 512×512 (יש) + Feature graphic 1024×500 (צריך ליצור).
- **Apple:** סט אחד לפחות ל-iPhone 6.7" (1290×2796) ול-iPhone 6.5" (1242×2688).

> אם תרצה, אני יכול לייצר Feature graphic 1024×500 ומסגרות לצילומי המסך.

---

## ✅ סיכום מצב

| פריט | סטטוס | מי |
|---|---|---|
| קוד האפליקציה (Android/iOS/Web) | ✅ מוכן | — |
| אייקונים ו-splash | ✅ מוכן | — |
| חתימת Android (keystore + workflow) | ✅ מוכן בקוד | — |
| מדיניות פרטיות | ✅ נכתבה (`web/privacy.html`) | 🔑 Cowork: `firebase deploy --only hosting` |
| תוכן ליסטינג HE+EN | ✅ מוכן (מסמך זה) | — |
| תשובות Data Safety / App Privacy | ✅ מוכן (מסמך זה) | — |
| 4 GitHub Secrets לחתימה | ⬜ | 🔑 בעל המוצר |
| חשבון Google Play + העלאת AAB | ⬜ | 🔑 בעל המוצר |
| Apple Developer + Codemagic + TestFlight | ⬜ | 🔑 בעל המוצר |
| Feature graphic + צילומי מסך | ⬜ | ניתן לייצר בסשן |

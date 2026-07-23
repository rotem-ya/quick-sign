# הנחיות ל-Cowork — העלאה ל-Google Play ו-Apple

חבילת ההגשה נבנית אוטומטית ומתפרסמת כ-ZIP:
**https://github.com/rotem-ya/quick-sign/releases/download/aab-submission/quicksign-submission.zip**
(מכילה: `app-release.aab` + תיקיית `store/` עם כל הטקסטים, תשובות Data Safety,
`privacy.html`, ו-Feature graphic.)

זהות קבועה: Bundle/App ID `com.rotem.quicksign` · Firebase `quicksign-7c212`
· גרסה `1.0.0`. תוכן הליסטינג — בתוך ה-ZIP (`store/*.txt`).

---

## 🟢 Google Play — Internal Testing

1. הורד ופתח את ה-ZIP. ה-AAB הוא `app-release.aab`.
2. Play Console (חשבון "Ask The Kids") → **Create app**:
   שם `QuickSign - Sign PDF`, שפת בסיס עברית, App, Free.
3. **Store listing** — הדבק מ-`store/google-play-listing.txt`
   (שם, תיאור קצר, תיאור מלא, קטגוריה Productivity). העלה:
   - אייקון 512×512 (`store/play_icon_512.png`), Feature graphic
     (`store/feature_graphic_1024x500.png`),
   - צילומי מסך (`store/screenshot_1_home.png`, `screenshot_2_signing.png`,
     `screenshot_3_privacy.png` — כולם 1080×1920).
4. **Privacy policy** = `https://rotem-ya.github.io/quick-sign/privacy.html`
5. **Data safety** + **Content rating** + **Target audience** + **App access**
   — כל התשובות ב-`store/data-safety-and-app-privacy.txt`. Ads = No.
6. **Testing → Internal testing → Create release** → העלה את `app-release.aab`
   → הוסף אימיילים של בודקים → Start rollout → שתף קישור opt-in.

### ⚠️ קריטי אחרי ההעלאה הראשונה — SHA-1 של Play
Play חותם מחדש את האפליקציה במפתח משלו (Play App Signing). כדי שהתחברות Google
תעבוד בגרסה שמותקנת **מהחנות**, חובה:
- Play Console → **Setup → App signing** → העתק את ה-**SHA-1 של "App signing
  key certificate"**.
- Firebase Console → פרויקט `quicksign-7c212` → Project settings → אפליקציית
  Android → **Add fingerprint** → הדבק אותו.
בלי זה, ההתחברות תיכשל (`ApiException: 10`) בגרסת החנות (למרות שעובדת ב-APK הישיר).

---

## 🍎 Apple — TestFlight

דורש Apple Developer (Rotem Yakov, Team ID `3X9M84JZD7` — קיים) ו-Codemagic.

1. **App Store Connect** → My Apps → **+ New App**: iOS, שם `QuickSign`,
   שם `QuickSign - Sign PDF`, Bundle ID `com.rotem.quicksign` (ה-App ID כבר קיים), SKU `quicksign`,
   שפה ראשית עברית.
2. **App Store Connect API key** (Users and Access → Integrations → Keys) →
   הוסף ב-Codemagic כ-integration בשם **בדיוק** `Apple_Key_QuickSign`.
3. חבר את הריפו `rotem-ya/quick-sign` ל-Codemagic (OAuth — יידרש אישור).
4. הפעל את הבנייה ל-TestFlight:
   ```bash
   git tag ios-v1.0.0 && git push origin ios-v1.0.0
   ```
   (`codemagic.yaml` בונה IPA חתום ומעלה ל-TestFlight אוטומטית.)
5. **App Privacy** ב-App Store Connect — התשובות ב-
   `store/data-safety-and-app-privacy.txt`. פרטי הליסטינג —
   `store/apple-appstore-listing.txt`.
6. TestFlight → הוסף בודקים פנימיים.
7. Firebase → Authentication → Sign-in method → **Apple → Enable**
   (חובה ל-Sign in with Apple, שאפל דורשת כשמציעים Google).
8. אמת על מכשיר iOS: התחברות (Google / Apple / אימייל) + סנכרון חתימות.

---

## הערה על מפתח החתימה (Android)
ה-AAB חתום ב-4 ה-secrets שב-GitHub. **לפני הרחבה לייצור ציבורי**, ודא שהמפתח
הזה הוא מפתח upload פרטי ייעודי (לא מפתח preview/ציבורי). ל-internal testing
זה תקין; אפשר לאפס את ה-upload key ב-Play Console בהמשך אם צריך.

## מה לדווח בחזרה
- קישור ה-opt-in של Internal Testing.
- שה-SHA-1 של Play נרשם ב-Firebase.
- שהבנייה ל-TestFlight עלתה, ושהתחברות+סנכרון עובדים על iOS.

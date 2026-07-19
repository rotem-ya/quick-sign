# הנחיות ל-Cowork — השלמת ההגשה לחנויות (QuickSign)

מסמך זה מיועד ל-**סוכן Cowork שרץ על המחשב של בעל המוצר** ויש לו גישה
לחשבונות (Firebase, Google Play, Apple, Codemagic, GitHub). כל מה שאפשר היה
להכין בקוד — כבר מוכן בענף `claude/app-store-submission-kr520m` (מדיניות
פרטיות, טקסטים לחנות, Feature graphic, workflows לבנייה). כאן נשארו רק
הצעדים שדורשים חשבון/קונסולה.

התוכן להעתקה-הדבקה (ליסטינג, Data Safety, App Privacy, דירוג) נמצא ב-
**`STORE_SUBMISSION.md`** — אל תמציא מחדש, העתק משם.

זהות קבועה: Bundle/App ID `com.rotem.quicksign` · פרויקט Firebase
`quicksign-7c212` · גרסה `1.0.0` build `1`.

בצע לפי הסדר. ✅ = סמן כשהושלם.

---

## 1. מדיניות פרטיות → Firebase Hosting  (חוסם את שתי החנויות)

הקובץ `web/privacy.html` כבר בריפו ונכנס אוטומטית ל-`build/web`.

```bash
npm i -g firebase-tools
firebase login
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting --project quicksign-7c212
```

- [ ] ודא שנטען בדפדפן: **https://quicksign-7c212.web.app/privacy.html**
- [ ] זו הכתובת שתזין בשדה "Privacy policy" בשתי החנויות.

> אם Hosting עדיין לא אותחל בפרויקט: `firebase init hosting` → בחר את
> הפרויקט הקיים `quicksign-7c212`, public dir = `build/web`, single-page
> app = No (כדי לא לדרוס את `privacy.html`), ואל תדרוס קבצים קיימים.

---

## 2. הפעלת Firestore + Storage לסנכרון הענן (רשות אך רצוי)

בלי זה הסנכרון פשוט לא עושה כלום (מוגן ב-try/catch, לא קורס). כדי להפעיל:

1. Firebase Console → פרויקט `quicksign-7c212` → **Build → Firestore
   Database** → Create database → production mode → אזור קרוב (eur3/europe-west).
2. **Build → Storage** → Get started → אותו אזור.
3. פרוס את כללי האבטחה שכבר בריפו:
   ```bash
   firebase deploy --only firestore:rules,storage:rules --project quicksign-7c212
   ```
- [ ] הושלם

---

## 3. Google Play — Internal Testing (מסלול ה-preview המהיר)

### 3א. 4 GitHub Secrets לחתימת ה-AAB
מה-upload keystore הקיים (`keystore.jks`, נשמר אצל בעל המוצר, לא בגיט):
GitHub repo → Settings → Secrets and variables → **Actions** → New secret:
- [ ] `UPLOAD_KEYSTORE_BASE64` = פלט של `base64 -w0 keystore.jks`
- [ ] `UPLOAD_KEYSTORE_PASSWORD`
- [ ] `UPLOAD_KEY_ALIAS`
- [ ] `UPLOAD_KEY_PASSWORD`

### 3ב. בניית ה-AAB
- [ ] GitHub → Actions → **"Build AAB (Google Play)"** → Run workflow (branch: main)
- [ ] הורד את ה-artifact `app-release-aab` → הקובץ `app-release.aab`

### 3ג. Play Console  (חשבון Google Play Developer, 25$ חד-פעמי)
- [ ] Create app → שם `QuickSign`, שפת בסיס עברית, App, Free
- [ ] Privacy policy = הכתובת מסעיף 1
- [ ] מלא Data safety — העתק תשובות מ-`STORE_SUBMISSION.md`
- [ ] מלא Content rating (כל הגילאים) + Target audience (מבוגרים/כללי)
- [ ] App access = "All functionality available without special access"
- [ ] Ads = No
- [ ] Store listing = טקסט + Feature graphic (`assets/store/feature_graphic_1024x500.png`)
      + אייקון 512×512 + צילומי מסך (סעיף 6)
- [ ] Testing → **Internal testing** → Create release → העלה AAB → הוסף
      אימיילים של בודקים → Start rollout → שתף קישור opt-in

---

## 4. Apple App Store — TestFlight (מסלול ה-preview של אפל)

דורש **Apple Developer Program** (99$/שנה).

- [ ] App Store Connect → My Apps → **+ New App**: iOS, שם `QuickSign`,
      Bundle ID `com.rotem.quicksign`, SKU `quicksign`, שפה ראשית עברית
- [ ] צור **App Store Connect API key** (Users and Access → Integrations → Keys)
- [ ] Codemagic → Teams → Integrations → App Store Connect → הוסף את המפתח
      בשם **בדיוק** `Apple_Key_QuickSign` (חייב להתאים ל-`codemagic.yaml`)
- [ ] Codemagic → חבר את הריפו `rotem-ya/quick-sign`
- [ ] הפעל את הבנייה בדחיפת tag:
      ```bash
      git tag ios-v1.0.0 && git push origin ios-v1.0.0
      ```
- [ ] הבנייה תעלה אוטומטית ל-TestFlight → App Store Connect → TestFlight →
      הוסף בודקים פנימיים
- [ ] מלא App Privacy — העתק תשובות מ-`STORE_SUBMISSION.md`

> אימות Sign in with Apple: ה-entitlement כבר בקוד אך **לא נבדק על iOS
> אמיתי**. אחרי הבנייה הראשונה ב-TestFlight, בדוק שהכניסה עם Apple עובדת.

---

## 5. Firebase Auth — SHA-1 לאנדרואיד (מתקן `ApiException: 10`)

התחברות Google באנדרואיד נכשלת עד שרושמים SHA-1 ב-Firebase:
- [ ] Firebase Console → Project settings → אפליקציית Android
      (`com.rotem.quicksign`) → **Add fingerprint** → הזן את ה-SHA-1 של ה-
      upload keystore:
      ```bash
      keytool -list -v -keystore keystore.jks -alias <alias> | grep SHA1
      ```
      (הוסף גם את SHA-1 של מפתח ה-debug אם רוצים התחברות גם ב-build דיבאג).
- [ ] הורד `google-services.json` מעודכן אם השתנה, החלף בריפו, ודחוף.

---

## 6. צילומי מסך לחנות

אם קיימת התיקייה `assets/store/screenshots/` בריפו — השתמש בקבצים משם. אם לא,
צלם 3–5 מסכים מהאפליקציה החיה (`https://quicksign-7c212.web.app/` או במכשיר):
בית/היסטוריה · מסמך עם חתימה ביד · חתימה בחותמת · הגדרות · תוצאה חתומה.
- **Play:** ≥2 צילומים 16:9 או 9:16, 320–3840px.
- **Apple:** iPhone 6.7" (1290×2796) ו-6.5" (1242×2688).

---

## 7. רשות / מאוחר יותר (לא חוסם preview)

- [ ] מזהי **AdMob** אמיתיים (פרסום כבוי כרגע — `_adsEnabled=false`).
- [ ] מעבר לדומיין משלך ל-Web (אם רוצים מעבר ל-`.web.app`).

---

## אחרי הכל — מיזוג ל-main
כשהצעדים מאושרים ועובדים, מזג את `claude/app-store-submission-kr520m`
ל-`main` כדי שהקוד (כולל מדיניות הפרטיות וה-workflows) יהיה בענף היציב.

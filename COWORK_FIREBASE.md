# הנחיות ל-Claude Cowork — הפעלת Firebase ל-QuickSign

**למי זה:** סוכן Claude Cowork שרץ על המחשב של בעל המוצר, עם דפדפן וגישה
לחשבון Google של הפרויקט. המטרה: להפעיל את מה שחסר ב-Firebase כדי
שסנכרון החתימות/ההגדרות לחשבון יעבוד, ולפרסם את מדיניות הפרטיות.

**פרויקט:** `quicksign-7c212` · **חשבון:** rot4735@gmail.com
**Application/Bundle ID:** `com.rotem.quicksign`

הבעיה שאנחנו פותרים: התחברות עובדת, אבל שמירת חתימות/הגדרות לחשבון נכשלת —
כי **Firestore ו-Storage עדיין לא הופעלו בקונסולה** וכללי האבטחה לא נפרסו.
כל הקוד כבר מוכן ומחכה רק לתשתית הזו.

---

## 0. הכנה (פעם אחת)

```bash
cd <תיקיית הריפו quick-sign>
git fetch origin && git checkout claude/app-store-submission-kr520m && git pull
npm i -g firebase-tools
firebase login          # פותח דפדפן — התחבר עם rot4735@gmail.com
firebase use quicksign-7c212
```

אם `firebase use` לא מזהה את הפרויקט: `firebase projects:list` כדי לוודא
שאתה מחובר לחשבון הנכון.

---

## 1. הפעלת Firestore Database  ← חוסם את הסנכרון

**אין לזה פקודת CLI — חייבים את הקונסולה.** פתח בדפדפן:
https://console.firebase.google.com/project/quicksign-7c212/firestore

1. **Create database**
2. מצב: **Production mode** (הכללים שלנו כבר מגבילים גישה — ר' סעיף 3)
3. אזור (Location): **eur3 (europe-west)** — קרוב לישראל. ⚠️ האזור **קבוע
   לצמיתות**, אי אפשר לשנות אחר כך.
4. Enable / Create.

---

## 2. הפעלת Storage  ← חוסם את שמירת תמונות החתימה

פתח: https://console.firebase.google.com/project/quicksign-7c212/storage

1. **Get started**
2. מצב: Production mode.
3. אזור: **אותו אזור** כמו Firestore (eur3 / europe-west).
4. Done.

> אם Storage דורש שדרוג ל-Blaze (תוכנית תשלום-לפי-שימוש): הכמויות כאן
> זעירות (כמה תמונות PNG למשתמש) ונכנסות בקלות ל-free tier, אבל זה דורש
> הוספת אמצעי תשלום. אם בעל המוצר לא רוצה Blaze כרגע — דלג על Storage;
> הסנכרון של השם/ברירות המחדל (Firestore בלבד) עדיין יעבוד, רק לא תמונות
> החתימות. יידע את בעל המוצר על הבחירה.

---

## 3. פריסת כללי האבטחה (כבר בריפו)

```bash
firebase deploy --only firestore:rules,storage:rules --project quicksign-7c212
```

הכללים (`firestore.rules`, `storage.rules`) כבר מגבילים כל משתמש לקרוא/לכתוב
רק את הנתונים שלו (`users/{uid}` בלבד). אמור לסיים ב-`Deploy complete!`.

---

## 4. פרסום מדיניות הפרטיות דרך Firebase Hosting

(דרוש URL חי לשתי החנויות. הקובץ `web/privacy.html` כבר בריפו.)

```bash
# צריך Flutter מותקן. אם אין: https://docs.flutter.dev/get-started/install
flutter pub get
flutter build web --release --no-web-resources-cdn
firebase deploy --only hosting --project quicksign-7c212
```

- אם Hosting לא אותחל: `firebase init hosting` → בחר פרויקט קיים
  `quicksign-7c212`, public dir = **`build/web`**, single-page app = **No**,
  אל תדרוס קבצים קיימים.
- ודא בדפדפן: **https://quicksign-7c212.web.app/privacy.html** נטען.

---

## 5. (אם צריך גם התחברות באנדרואיד) SHA-1

התחברות Google באנדרואיד נכשלת עם `ApiException: 10` עד שרושמים SHA-1:
1. הפק את ה-SHA-1 של ה-upload keystore:
   ```bash
   keytool -list -v -keystore <path/to/keystore.jks> -alias <alias> | grep SHA1
   ```
2. פתח: https://console.firebase.google.com/project/quicksign-7c212/settings/general
   → אפליקציית Android (`com.rotem.quicksign`) → **Add fingerprint** → הדבק SHA-1.
3. הורד `google-services.json` מעודכן, החלף ב-`android/app/`, ודחוף לגיט.

---

## 6. אימות מקצה-לקצה (חובה לפני שמסמנים "בוצע")

1. בנה מחדש והתקן את האפליקציה על מכשיר: `flutter build apk --release`
2. באפליקציה → הגדרות → התחבר עם Google.
3. צור/שמור חתימה.
4. פתח שוב את מסך ההגדרות וקרא את **פאנל הלוג הקטן בתחתית** — צריך להופיע:
   ```
   CloudSync: pushed 1 mark(s) + profile
   ```
   ולא `CloudSync: push failed: ...`.
5. בקונסולה ודא שהמידע הגיע:
   - Firestore → `users/{uid}` (שדה name/defaults) ו-`users/{uid}/marks/...`
   - Storage → `users/{uid}/marks/<id>.png`
6. מבחן שחזור: התנתק והתחבר מחדש (או במכשיר אחר) → החתימה חוזרת.

אם בשלב 4 מופיע `push failed` — העתק את ההודעה המלאה מהפאנל; היא אומרת
בדיוק מה חסר (permission-denied = כללים לא נפרסו; not-found/unavailable =
Firestore/Storage לא הופעלו).

---

## סיכום למי לדווח לבעל המוצר
- [ ] Firestore הופעל (אזור: ______)
- [ ] Storage הופעל / דולג בגלל Blaze (סמן מה)
- [ ] כללים נפרסו (`Deploy complete!`)
- [ ] מדיניות פרטיות חיה ב-`https://quicksign-7c212.web.app/privacy.html`
- [ ] אימות end-to-end: `CloudSync: pushed …` + הנתונים בקונסולה
- [ ] (אופציונלי) SHA-1 נרשם, התחברות אנדרואיד עובדת

# App Store Connect → App Review Information 에 붙여 넣기

아래 **Review Notes** 블록을 App Store Connect  
`앱 심사 정보` → `메모` (Notes) 칸에 그대로 복사하세요.

데모 계정은 `로그인 정보` 칸에 넣고, 아래 `[데모 계정 채우기]`만 실제 값으로 바꾸면 됩니다.

---

## Review Notes (복사용)

```text
[Guideline 4.2 — Hybrid app, not a website wrapper]

pageBy is a Flutter iOS app. The diary UI is rendered in a WebView (https://pageby.stream), but core App Store features are implemented natively in Flutter/iOS and are not available in a mobile browser alone.

Native features reviewers should exercise:
1) Sign in with Apple (and Google) — native ASAuthorization / Google Sign-In sheets
2) In-App Purchases via StoreKit + RevenueCat
   - Auto-renewable: pageby_monthly, pageby_yearly
   - Consumables: pageby_churu_*, pageby_ai_draw_*
   - Paywall shows price, auto-renew terms, Terms, Privacy, and Restore Purchases
3) App Tracking Transparency prompt before Mobile Ads initialization
4) Banner / rewarded ads (AdMob) with ATT
5) Push notifications (Firebase) after permission
6) Save drawings to Photos (Photo Library Add)
7) Deep links: pageby:// and applinks:pageby.stream (friend room invites)
8) Share / file export (PDF/image) via native share sheet

How to review quickly:
- Open the app → sign in with the demo account below (or Sign in with Apple)
- Menu → Account → open Pro / subscription sheet → confirm Restore and auto-renew text
- Create or open a diary entry; try AI draw / rewarded ad if shown
- Friend room: report and block are available on posts/comments
- Account deletion: Account → Delete account (30-day grace, then permanent purge of account + cloud diaries)

Account deletion (5.1.1(v)):
In-app path: Menu → Account → Delete account.
Apple Sign-In tokens are revoked on delete. After 30 days, account and personal cloud data are permanently deleted.

UGC safety:
Friend rooms support report and block.

[데모 계정 채우기 — also fill the Sign-in required fields in App Store Connect]
Email / ID: YOUR_DEMO_GOOGLE_OR_APPLE_EMAIL
Password: YOUR_DEMO_PASSWORD
Notes: Prefer a Google account that already has a few diary entries and one friend-room post so UGC report/block is visible. If using Sign in with Apple on the review device, the reviewer can use that instead.
```

---

## 한글 요약 (본인용)

심사원이 “웹만 감싼 앱”으로 보지 않게, 네이티브로 되는 기능을 메모에 적어 두는 용도입니다.

- 화면 UI는 WebView지만 결제·Apple 로그인·ATT·광고·푸시·앨범 저장·딥링크·공유는 네이티브
- 구독/복원/자동갱신 문구 위치 안내
- 탈퇴·신고·차단 경로 안내
- 데모 계정은 Connect의 로그인 정보 칸 + 위 Notes의 Email/Password를 실제 값으로 교체

---

## 제출 전 체크

- [ ] 데모 Google(또는 Apple) 계정 준비, 일기·친구방 글 몇 개 넣어 두기
- [ ] Notes에 위 영문 블록 붙여 넣기
- [ ] Connect `로그인 필요`에 같은 계정/비밀번호 입력
- [ ] 이번 빌드에 월간·연간 구독 포함해 제출
- [ ] 프론트/백엔드 배포 후 `pageby.stream`이 최신 탈퇴·자동갱신 문구인지 확인

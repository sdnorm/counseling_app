# Crossroads Counseling App — Design Document

> **Date:** 2026-05-08
> **Status:** Approved
> **Privacy Model:** Client-side encryption (AES-GCM via Web Crypto API). Server stores only ciphertext. Counselor has zero access to client data.

---

## 1. Overview

A Progressive Web App (PWA) for a counselor's clients. The app provides self-guided mental-health tools: journaling, gratitude tracking, emotion logging, coping skills, and more. **Zero trust in the server** — all sensitive data is encrypted on the client before it ever reaches the network.

The counselor's only interface is a minimal invite-code generator. No client data, not even metadata, is visible to the counselor or the developer.

---

## 2. Architecture

### 2.1 High-Level

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENT (Browser)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │
│  │   Turbo/    │  │   Web Crypto│  │   IndexedDB (local) │   │
│  │   Stimulus  │  │   (encrypt) │  │   * plaintext *     │   │
│  │   UI        │  │             │  │                     │   │
│  └─────────────┘  └─────────────┘  └─────────────────────┘   │
│         │                 │                   │               │
│         └─────────────────┴───────────────────┘               │
│                             │                                 │
│                    ┌────────▼────────┐                        │
│                    │ Service Worker │                        │
│                    │ (offline, push) │                        │
│                    └─────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      RAILS SERVER                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Auth      │  │   Encrypted │  │   Push Subscription │ │
│  │   (devise)  │  │   Blob Store│  │   Metadata          │ │
│  │             │  │  (ciphertext)│  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│  ┌─────────────┐                                           │
│  │   Invite    │  ← Only counselor-facing screen            │
│  │   Codes     │                                           │
│  └─────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Privacy Boundary (Hard Rules)

| Data | Location | Counselor/Admin Access |
|------|----------|------------------------|
| Journal entries | Client IndexedDB + encrypted server blob | **NO** |
| Gratitude logs | Client IndexedDB + encrypted server blob | **NO** |
| Emotion snapshots | Client IndexedDB + encrypted server blob | **NO** |
| Check-in scores | Client IndexedDB + encrypted server blob | **NO** |
| Coping skill stars | Client IndexedDB + encrypted server blob | **NO** |
| Triangle scores | Client IndexedDB + encrypted server blob | **NO** |
| Takeaways | Client IndexedDB + encrypted server blob | **NO** |
| User name | Client-side only (optional, not sent to server) | **NO** |
| Email / password hash | Rails database (standard Devise) | **YES** (login only) |
| Push subscription endpoint | Rails database (Web Push standard) | **YES** (endpoint only, no content) |
| Invite code list | Rails database | **YES** |

> **Critical:** The encryption key is derived from the user's password via PBKDF2 and lives **only** in the browser's memory during the session. It is never persisted to disk, never sent to the server, and never available to the counselor.

---

## 3. Technology Stack

| Layer | Technology | Reason |
|-------|------------|--------|
| Backend | Rails 8 + SQLite | Familiar to developer, sufficient scale |
| Frontend views | Turbo + Stimulus | Rails-native, PWA-friendly, easy to port existing HTML |
| Styling | Inline / CSS-in-view (match existing app exactly) | Preserve the "vibe coded" design |
| Encryption | Web Crypto API (AES-GCM, PBKDF2) | Native browser, no external crypto libs |
| Local storage | IndexedDB | Structured, large capacity, async |
| Server sync | Encrypted JSON blobs via Rails API | Minimal, only for backup/recovery |
| Push notifications | Web Push API + `web-push` gem | PWA standard |
| PDF generation | `jsPDF` or `pdfmake` (client-side) | Certificate generation without server |
| Offline support | Service Worker (Workbox or custom) | Core PWA requirement |

---

## 4. Data Model (Server)

```ruby
# Minimal server-side schema — only non-sensitive metadata

class User < ApplicationRecord
  # devise :database_authenticatable, :registerable
  # fields: email, encrypted_password, invite_code_id
end

class EncryptedBlob < ApplicationRecord
  belongs_to :user
  # fields: user_id, ciphertext (text), nonce (string), salt (string), updated_at
  # The server cannot read this. It is opaque binary data to the server.
end

class PushSubscription < ApplicationRecord
  belongs_to :user
  # fields: user_id, endpoint, p256dh, auth, created_at
end

class InviteCode < ApplicationRecord
  # fields: code (string), used (boolean), used_by (user_id), created_at
end
```

---

## 5. Data Model (Client)

All client data lives in **IndexedDB** in plaintext for instant access. It is encrypted as one large JSON blob for server sync.

```javascript
// Client-side IndexedDB schema ( Dexie.js or raw IDB )

const db = {
  profile: { name: "Danny", onboardingComplete: true },
  journalEntries: [{ id, date, mode, prompt, content }],
  gratitudeEntries: [{ id, date, items: [] }], // tracks 30-day streak
  emotionSnapshots: [{ id, date, emotions: [] }],
  copingSkills: [{ text, starred, custom }],
  triangleSnaps: [{ id, date, god, self, others }],
  checkinEntries: [{ id, date, score, mode }],
  takeaways: [{ id, date, insight, great, miss }],
  agendaItems: [""],
  settings: { notificationsEnabled, gratitudeReminderTime, hapticsEnabled }
}
```

### Encryption Flow

```
1. User logs in → password sent to Rails (Devise)
2. On success, derive AES key from password + salt using PBKDF2 (100k iterations)
3. Load encrypted blob from server (if exists)
4. Decrypt blob with derived key → populate IndexedDB
5. User interacts with app (reads/writes IndexedDB instantly)
6. On any data change:
   a. Serialize IndexedDB state to JSON
   b. Encrypt JSON with AES-GCM + derived key
   c. Send ciphertext + nonce + salt to Rails (PUT /api/sync)
7. Key is zeroed from memory on logout / tab close
```

---

## 6. Screens & Features

### 6.1 Navigation (Simplified — matching suggestion)

Bottom nav: **Home** | **Schedule**
- "More" accessed via a "drop up" or overflow menu (Home screen cards still link directly)

### 6.2 Home Screen

- Welcome message: "Welcome, [Name]!" (if collected)
- Quick-action cards (matching existing design exactly):
  - My Journal
  - Gratitude Log
  - Emotions
  - Schedule
- Visual: brown topbar, Lora serif headings, Open Sans body, blue/orange accent colors

### 6.3 Journal

- Mode toggle: "Long form" vs. "Bulleted list"
- Prompt selector (pre-defined list)
- Save → confetti celebration + "Yay! You did it!" or rotating affirmation
- History list below

### 6.4 Gratitude Log

- 3 input fields: "I am grateful for..."
- Save → confetti
- Streak counter (days with entries)
- After 30-day streak: generate downloadable certificate (PDF)

### 6.5 Emotions

- Emoji faces per emotion group (Joy 😊, Sadness 😢, Anger 😠, Fear 😨, Surprise 😮, Disgust 🤢)
- Core groups with child emotions
- Multi-select
- Save snapshot → confetti
- History log with pattern tip

### 6.6 Coping Skills

- Full list with star/favorite toggle
- Custom add
- Starred items float to top

### 6.7 Triangle (God / Self / Others)

- 3 sliders (1-10)
- Visual triangle plot (SVG or Canvas)
- Save snapshot

### 6.8 Check-in

- Mood score slider (1-10)
- Pre/post session toggle
- Save → confetti

### 6.9 Takeaways

- 3 fields: Insight, What I did great, What I missed
- Save

### 6.10 Agenda

- Dynamic bullet list
- Add/remove items

### 6.11 Resources

- Fetch from RSS feed (client-side fetch)
- CORS proxy if needed

### 6.12 Schedule

- External links only:
  - Online booking portal
  - Phone: (225) 341-4147
  - Email: logan@crossroadcounselor.com

### 6.13 Settings

- Name (local only)
- Notification preferences
- Gratitude reminder time
- Toggle confetti/haptics
- Export encrypted backup
- Logout (clears key from memory)

---

## 7. New Features (From Suggestion List)

| Suggestion | Implementation |
|------------|----------------|
| Downloadable certificate (30-day gratitude) | Client-side PDF generation via jsPDF when streak === 30 |
| Emoji faces for emotions | Replace text buttons with emoji in Emotions screen |
| Fix notice on Home Screen to attorney-approved language | Update static text in view |
| Simplified navigation | Home + Schedule bottom nav; "More" via overflow |
| Confetti on completion | Canvas-confetti or CSS animation on save actions |
| Rotating positive messages | Array of affirmations, random pick on save |
| Haptics / touch feedback | CSS `:active` states + `navigator.vibrate()` where supported |
| Push notifications | Web Push API; prioritize gratitude reminder |
| Personalized welcome | Collect name in onboarding; greet on Home |

---

## 8. Counselor Dashboard (Minimal)

```
/admin/invites
```

- HTTP Basic Auth (password in Rails credentials)
- Generate new invite code (random alphanumeric, 8 chars)
- List codes with used/unused status
- No client data, no user list, nothing else.

---

## 9. PWA Configuration

- `manifest.json`: name, icons, theme color, display: standalone
- Service Worker:
  - Cache static assets for offline
  - Cache app shell
  - Background sync for encrypted blob upload when connectivity returns
- `scope`: root
- Icons: generate from existing logo or simple lettermark

---

## 10. Security Considerations

1. **HTTPS only** (required for Web Crypto, Service Worker, Push)
2. **Password strength**: minimum 8 chars, encourage longer (PBKDF2 entropy)
3. **Key derivation**: PBKDF2 with 100,000 iterations, unique salt per user
4. **Encryption**: AES-GCM with 256-bit key, 96-bit nonce
5. **Memory safety**: Key stored in `CryptoKey` object (non-extractable where possible), zeroed on logout
6. **No server-side decryption**: Rails app has no decryption capability. If the server is compromised, attacker gets only ciphertext.
7. **Rate limiting** on login and sync endpoints
8. **CSP headers** to prevent XSS injection that could steal keys

---

## 11. Offline Behavior

- All reads come from IndexedDB (instant, no network)
- Writes update IndexedDB immediately, then attempt server sync in background
- If offline, sync is queued in Service Worker (Background Sync API)
- Push notification preferences require online registration, but scheduling is resilient

---

## 12. Deployment

- **Target:** Fly.io, Render, or Railway (single Rails app + SQLite)
- **Domain:** TBD (counselor to provide)
- **SSL:** Let's Encrypt via platform
- **Email:** SendGrid or Postmark for Devise confirmations
- **Push:** VAPID keys generated once, stored in Rails credentials

---

## 13. Out of Scope (YAGNI)

- Real-time chat between client and counselor
- Counselor viewing any client summary or analytics
- Server-side database of client content
- Multi-device real-time sync (eventual consistency via blob is fine)
- Native mobile apps (App Store / Play Store)
- Payment processing
- Appointment calendar integration beyond external links

---

## 14. Success Criteria

- [ ] Client can install as PWA on iOS and Android
- [ ] All journal/gratitude/emotion data is encrypted before leaving the device
- [ ] Counselor can generate invite codes but cannot see client data
- [ ] Push notifications work for gratitude reminders
- [ ] 30-day gratitude streak triggers certificate download
- [ ] App matches existing "vibe coded" design and color palette exactly
- [ ] Works offline for all core features
- [ ] Data recovery possible if client remembers password and gets new device

---

**Next step:** Write implementation plan (invoke `superpowers:writing-plans`).

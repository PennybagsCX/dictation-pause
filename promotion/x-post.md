# X (Twitter) post pack — dictation-pause

## ✅ Primary post (fits 280 chars, link counts as 23)

```
macOS dictation mutes your video but keeps it playing while you talk. So I built a free fix: it actually PAUSES YouTube/Music when you dictate, and resumes after. ~10 MB, no subscription, one-line install.

https://github.com/PennybagsCX/dictation-pause
```

## Alt post (developer-audience angle, also <280)

```
Fun reverse-engineering: macOS dictation is UNDETECTABLE via CoreAudio — it captures through a path that never sets the mic "in use" flag. The only public signal: the Window Server's StatusIndicator windows.

So I built the pause-while-dictating tool on that:
```
(put the link as the first reply, or append if you have Premium's longer limit)

## First reply (attach under either post)

```
Install:
git clone https://github.com/PennybagsCX/dictation-pause && cd dictation-pause && ./install.sh

200 lines of Swift, MIT, pauses/resumes real media keys, never touches paused tabs, self-healing after macOS updates. Works on Sonoma and later.
```

---

## 🎨 Image prompt (paste into any generator — Midjourney / DALL·E / MiniMax / Ideogram)

**Aspect ratio: 16:9 (1200×675 recommended — matches X timeline cards)**

```
Clean minimal flat vector illustration, 16:9 hero image for a developer tool. A modern silver MacBook centered on a soft indigo-to-violet gradient background. On the MacBook screen: a video player paused mid-frame with one large glowing rounded pause icon (two vertical bars) floating over the video. A luminous audio waveform rises from the keyboard toward a small floating rounded-square microphone icon styled like a macOS app icon; a single tiny orange dot glows on the macOS menu bar as a mic-active indicator. Two subtle floating UI chips nearby: a play triangle and a pause glyph. Soft long shadows, generous whitespace, Apple-style design language, tasteful palette of indigo, violet, white, with one orange accent. Absolutely no text or letters anywhere. Crisp, high-detail, marketing-quality product hero image.
```

Tips:
- Generators garble text — the prompt deliberately bans words. Your tweet text carries the words.
- If the tool supports it, add: `--ar 16:9` (Midjourney) or set size 1200×675.
- Generate 3–4 variants and pick the one where the pause icon reads clearly at small size (that's how it'll appear in the timeline).

---

## Posting tips

- Best windows for dev-audience X: Tue–Thu, ~9–11 AM US Eastern.
- Put the GitHub link in the post itself (X shows the card preview); the repo README is the landing page.
- If you post the Alt version, put the install command as your immediate first reply.
- Pin the tweet to your profile during launch week.

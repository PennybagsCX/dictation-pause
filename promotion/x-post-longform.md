# Long-form X post (X Premium — no character limit)

Copy everything below the line into an X article / long-form post.

---

For years, using voice dictation on a Mac while watching anything meant the same little dance: pause the video, dictate, come back, find your place, hit play. Every single time.

Then at some point macOS quietly got a bit smarter — when you start dictating, it now MUTES whatever you're watching. Progress, right?

Except muting isn't pausing. The video keeps playing silently underneath you. You dictate a paragraph, dictation ends, and you've silently missed thirty seconds of the thing you were watching. You get to scrub back and guess where you left off. The feature solves the noise problem and none of the attention problem.

Commercial dictation apps like Whisperflow handle this properly — they actually pause your media. But they're subscriptions, and I didn't want a daemon with a business model to do what felt like thirty lines of system glue.

So I built it. It's called dictation-pause, it's free and open source, and it's at:

https://github.com/PennybagsCX/dictation-pause

What you get:

— Video playing + you start dictating → it genuinely PAUSES (playback stops, not just sound)
— You stop dictating → it resumes exactly where you were
— It never touches a paused tab (a wrong toggle here would start playing something you deliberately stopped — there's a guard for that)
— Any microphone activity triggers it, so calls pause your music too
— It survives reboots, restarts itself if it crashes, and a "doctor" agent health-checks it twice a day and sends you a macOS notification if a system update ever breaks it

Install is two commands:

git clone https://github.com/PennybagsCX/dictation-pause && cd dictation-pause && ./install.sh

Then one Accessibility permission, and you're done. ~200 lines of Swift, no dependencies, MIT.

The interesting part is what it took to build, because Apple made this genuinely hard.

How do you even know dictation is happening? The obvious answer — "watch the microphone" — does not work. I verified it with probes: on current macOS, dictation captures audio through a path that never raises the input device's "in use" flag. Your mic is literally recording and the system-level device state says nothing is happening. Every Stack Overflow answer about watching audio devices is dead on arrival for dictation.

Plan B: watch the speech-recognition processes. Also a dead end — the relevant daemons run persistently whether or not you're dictating, and the one that does cycle around your dictation sessions is uncorrelated enough to be useless as a trigger.

Plan C: the speech logs. Thousands of lines of asset-framework noise, no session markers.

The answer turned out to be windows. When the microphone goes active, the Window Server raises small "StatusIndicator" windows — that's the mic dot you see in the menu bar. They appear the instant dictation starts and vanish the moment it ends, with clean edges every single time. So the agent polls for those at 4 Hz (about 0.1% of one core) and drives a media pause/resume off them — the same play/pause event your F8 key sends.

There was one more trap worth mentioning: browsers like Arc keep a paused tab's audio stream OPEN for a while, rendering silence. At the device level, "paused but stream open" and "actually playing" are indistinguishable, and a naive pause toggle would RESUME a video you deliberately paused (macOS's media key is a toggle, addressed to a single app). The final version only pauses when audio was verifiably rendering in the half-second before you started talking.

Known limitations, in the spirit of honesty: it's mic-scoped rather than dictation-scoped (calls pause your music — I consider that a feature); if you pause a video and dictate within about thirty seconds, it may still get resumed, because that lingering stream hasn't closed yet; and a media key only reaches one app at a time, so if Spotify and YouTube are both playing, only one pauses.

That's the whole story. If you dictate on a Mac and watch things, I think you'll like it:

https://github.com/PennybagsCX/dictation-pause

Free, MIT licensed, and it took real reverse-engineering to make feel invisible. If it saves you the pause-dictate-scrub dance even once a day, it's paid for its disk space.

If you find a bug or it doesn't work on your setup, issues are open — the diagnostics tooling is included, so reports are easy to make useful.

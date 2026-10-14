# BIZBOT pending online-order notification audio

Work ID: `BIZBOT-POS-AUDIO-PRINT-003` (audio workstream only).

## Source and permission record

The owner supplied `universfield-new-notification-050-494248.mp3` and authorized
its use as the foreground Android POS pending-order alert. Its verified SHA-256
is `f7687a9f91dec6c79b4dca2963debb60828bb433dc0b469c6e32e0566bfb71e1`;
the original is 78,576 bytes, stereo 44,100 Hz, 256 kb/s MP3, with 108,288 decoded
samples per channel (2.455510 seconds).

The matching primary listing is [New Notification 050 by Universfield on
Pixabay](https://pixabay.com/sound-effects/city-new-notification-050-494248/),
published March 4, 2026. Its attribution is retained here even though the
[Pixabay Content License summary](https://pixabay.com/service/license-summary/)
does not require attribution. Reviewed October 14, 2026:
[Pixabay terms, sections 5 and 6](https://pixabay.com/service/terms/).

The terms permit commercial use and adaptation, with restrictions including
standalone distribution, misleading attribution and incorporation into a mark.
This asset is incorporated into the functional BIZBOT POS application and must
not be offered as an independent sound download, stock asset or trademark.
The mastering below does not transfer authorship or exclusive rights to BIZBOT.

## Bundled master and fresh measurements

The separately supplied preferred master
`BIZBOT-online-order-alert-loud.mp3` (owner-provided hash
`3e3d24d2bc46f760f7aac4fc7614ba84a06dd80d2f3d52a1ed89b3b66476beaf`)
was not available locally. This is the explicitly authorized fallback master
from the verified original, not a claim to reproduce that other file byte for
byte and not a replacement sound.

Bundled file: `apps/pos/android/app/src/main/res/raw/bizbot_online_order_alert.mp3`

- SHA-256: `47c6a0bee63e297116b98a56cdb9674785b60829cc967c22829485a7399a5d34`
- Size: 80,291 bytes; stereo 44,100 Hz, 256 kb/s MP3.
- Decoded duration: 2.455510 seconds (108,288 samples per channel), unchanged.
  Container duration includes MP3 padding: approximately 2.48 seconds.
- Original integrated loudness: -16.01 LUFS; true peak: -7.15 dBTP.
- Final encoded master integrated loudness: -10.58 LUFS; true peak: -1.44 dBTP.
- Final decoded sample peak: -1.40 dBFS; no full-scale clipping.
- Full-clip combined-channel RMS: original -25.808 dBFS; master -19.962 dBFS
  (FFmpeg `astats`, before any measurement-time processing).
- Loudness gain: approximately 5.43 LU. Device notification volume remains the
  user's choice; perceived loudness still needs an authorized device review.

Measurements were made with FFmpeg 7.1 `loudnorm` input measurements; sample peak
and duration were also checked on decoded float PCM. Compression precedes
loudness normalization and a sample limiter; MP3 encoding can move the measured
peak slightly above the pre-encoding -1.5 dB ceiling.

Reproduction command (FFmpeg is local authoring tooling, not an app dependency):

```text
ffmpeg -nostdin -i universfield-new-notification-050-494248.mp3 -map_metadata -1 -af "acompressor=threshold=0.1258925:ratio=2:attack=5:release=80:makeup=1,loudnorm=I=-10:TP=-1.5:LRA=5:print_format=json,alimiter=limit=0.8413951:level=false" -ar 44100 -ac 2 -c:a libmp3lame -b:a 256k bizbot_online_order_alert.mp3
ffmpeg -nostdin -i bizbot_online_order_alert.mp3 -af "loudnorm=I=-10:TP=-1.5:LRA=5:print_format=json" -f null NUL
```

## Playback and verification

Android loads the bundled raw resource with `MediaPlayer`, notification audio
attributes and asynchronous preparation. It owns at most one clip, stops and
releases on completion/error/cancellation, and has a five-second hard bound
including preparation. Late callbacks cannot restart a cancelled clip or
cancel a later one. There are no network reads, extra polling coordinators,
native repeat timers, background services or notification permissions.

The existing Dart controller retains its approximately ten-second cadence,
confirmed-decision/expiry handling, uncertain-decision recovery and cleanup on
session/scope change, offline/security lock, pause and disposal. Native Android
also stops on Activity pause and disallows playback outside the foreground.
Silent/vibrate, zero notification volume, DND and unavailable policy checks
remain fail-silent. No volume override, DND bypass or audio-focus request is
made. Browser and non-Android behavior remains silent.

Focused verification:

```powershell
pwsh tools/check_online_order_alert_audio.ps1
flutter test apps/pos/test/online_order_alert_audio_test.dart apps/pos/test/online_order_inbox_alert_test.dart apps/pos/test/online_order_inbox_controller_test.dart
flutter analyze apps/pos
```

The native check uses the Kotlin compiler already bundled with the Android
Gradle wrapper (or `-GradleHome` and `-JavaHome`). It validates the asset hash and
runs deterministic fake-decoder/policy/timeout tests without playing audio or
building an APK. Android `:app:compileDebugKotlin` verifies the platform adapter
and generated raw-resource reference. Physical audibility, silent/DND settings
and the owner's speaker preference require a separately authorized APK/device
acceptance; no background or screen-off notification capability is claimed.

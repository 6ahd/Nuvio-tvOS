# Nuvio Legacy for Apple TV (unofficial port)

Nuvio Legacy **2.0.7** for **tvOS 26 or later**, with **AetherEngine 7.40.1**,
native Siri Remote focus and high-resolution poster views.

## Download and install

Download the IPA from [Releases](https://github.com/6ahd/Nuvio-tvOS/releases).
The performance test build is **b2610202228**. The IPA is unsigned: sign it with
Sideloadly or another compatible signing tool and select your **Apple TV** as
the target device. Each release includes the matching source and SHA-256 checksums.

## Current performance build

The default uses the original C/SDL GPU renderer, retaining the existing design,
with **Swift/UIKit for remote focus and Home poster surfaces**. The full-scene
C-command-to-UIView renderer is experimental and disabled by default; it can be
selected explicitly with `NUVIO_SWIFT_SCENE=1` for development. The application
logic has not been rewritten entirely in Swift.

This build retains the Nuvio 2.0.7 shared core, Aether 7.40.1 playback integration,
external-player choices, subtitle indexing, track-selection fixes and persistent
settings. See [performance notes](NUVIO-PERFORMANCE-LOCAL.md) and
[third-party components](THIRD_PARTY.md).

## Build

A Mac with Xcode and a tvOS SDK, Tuist, CMake, Ninja and Python 3 is required.

```sh
git clone https://github.com/6ahd/Nuvio-tvOS.git
cd Nuvio-tvOS
cp config.env.example config.env
# Fill in your own application keys in config.env.
bash tvos/deps.sh
bash tvos/sim-run.sh
bash tvos/ipa.sh
```

`config.env` and generated configuration are excluded from Git and source
archives. Account sync, login QR, TMDB, Trakt and Simkl integrations require
compatible backend configuration and your own application registrations. The
engine and legacy versions are pinned in `tvos/engine-release.json` and
`tvos/legacy-release.json`; patched legacy sources are included.

## Validation

* 23 native component cases passed, covering remote directions, release/hold
  handling, focus restoration, image pixels, text, compositing and snapshots.
* The shipping renderer default passed real-app Home navigation across rows and
  restored the previous poster column when moving back up.
* Host regressions passed for remote timing, artwork URLs, audio/subtitle
  selection, subtitle indexing and configuration generation.

The extended screenshot sweep for the default renderer was stopped and is not
reported as a passing 12-screen run. Physical Siri Remote touchpad feel,
streaming, account flows and device performance still require device testing.
This release is a **pre-release**, with no guaranteed speed-improvement figure.

## Credits and license

This is an unofficial port of [nuvio-native-legacy](https://github.com/iqui27/nuvio-native-legacy),
with playback integration based on [NuvioTVOS](https://github.com/bobsupra/NuvioTVOS)
and [AetherEngine](https://github.com/superuser404notfound/AetherEngine).
It is not affiliated with or endorsed by those projects. Names and logos belong
to their respective owners. See [LICENSE](LICENSE) and [THIRD_PARTY.md](THIRD_PARTY.md)
for software licenses, including the bundled dependency notices.

## بالعربي

نسخة غير رسمية من Nuvio Legacy 2.0.7 لأجهزة Apple TV، تتطلب tvOS 26 أو أحدث.

[حمّل ملف IPA من الإصدارات](https://github.com/6ahd/Nuvio-tvOS/releases)، ووقّعه بأداة مثل
Sideloadly مع اختيار جهاز Apple TV. رقم بناء نسخة الأداء هو **2610202228**.

تستخدم هذه النسخة طريقة العرض الأصلية مع الحفاظ على التصميم، وتبقي Swift
للتحكّم بالريموت وبوسترات الرئيسية. تحويل الواجهة الكاملة إلى Swift تجريبي
ومعطّل افتراضيًا. المحرك Aether 7.40.1، والمنطق المشترك محدّث إلى Nuvio 2.0.7.

نجحت فحوص الريموت والصور والتنقّل بين الصفوف. النسخة تجريبية، وسرعتها الفعلية
وحركة سطح ريموت Siri تحتاجان التجربة على الجهاز. ملفات إعدادات البناء الخاصة
غير منشورة، والسورس المطابق وملف التحقّق مرفقان بالإصدار.

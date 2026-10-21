# Release packaging

The current published candidate is Nuvio Legacy 2.0.7, Apple TV build
2610202228, with Aether 7.40.1. It requires tvOS 26 or later and is a pre-release.

Release assets contain the unsigned IPA, matching source archive, SHA-256
checksums and a validation report. Sign the IPA for your own Apple TV before
installing it. Report the full build number when describing an issue.

For a new build, configure your own `config.env` from `config.env.example` and
run `bash tvos/ipa.sh`. Keep that file and generated configuration outside Git
and distributable source archives. Publish the matching source with the IPA,
retaining the project and dependency licenses in `LICENSE`, `THIRD_PARTY.md`
and `licenses/`.

The production default uses the original renderer with native Swift focus and
poster surfaces. Whole-scene Swift presentation is an opt-in experiment.
Device performance and physical touchpad acceptance remain pending.

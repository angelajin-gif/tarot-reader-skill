# Tarot Reader Stage 10 v1.1 acceptance

## Decision

- Release ID: `tarot-reader.stage10.v1.1`.
- Release status: `frozen`.
- Decision: `APPROVE / FROZEN`.
- Review mode: direct author-side review requested by the user; this is not represented as an independent blind review.
- Installation status: not installed. Installation remains a separate user-authorized action.

## Accepted behavior change

The v1.1 interaction amendment changes only Product Charter rules PC-002 and PC-008. It distinguishes prohibited pre-answer clarification from an optional inquiry offered after the current reading is complete. Ordinary readings use one relational narrative, place specific visual/Teacher/Dictionary evidence beside the claim it changes, and close with two or three optional user-drawn question-and-spread directions. The Reader still does not draw cards, fill missing facts through a forced interaction loop, or weaken high-risk and fail-closed boundaries.

Teacher wording is cited at the packaged Teacher Model section, concept, or anchor level. It is not presented as a direct quotation from an original book unless an exact original excerpt is packaged. Dictionary condensed statements remain reviewed paraphrases with entry and page provenance.

## Acceptance evidence

- Official `quick_validate`: pass.
- Stage 10 v1.1 suite: 23 runs, 1,264 assertions, 0 failures, 0 errors, 0 skips.
- Visual packets: 78/78 unique canonical IDs; 8 Phase 4A rechecks and 70 direct Phase 4B observations.
- Dictionary: 22/22 packaged reviewed units queryable; unsupported units remain fail-closed.
- Canonical snapshots: 30/30 byte-identical to the frozen v1 snapshot set.
- Frozen build inputs: 31/31 SHA-256 values match, including the external project-goal input.
- Authored runtime behavior artifacts: 12/12 explicitly listed and SHA-256-bound; acceptance evidence is separately hash-bound.
- Actual tamper tests cover canonical visual snapshots, Dictionary derived units, Phase 4C freeze gates, source binding, and authored behavior artifacts.
- Phase 3A, 3B, 3C, 4A, 4B, and 4C regressions: pass; Phase 4C reports 7 runs, 1,313 assertions, 0 failures.
- Frozen v1 regression: 18 runs, 1,166 assertions, 0 failures; the installed v1 remained byte-identical to the frozen v1 source during closure.

## Forward behavior review

The raw relationship fixture using `lovers`, `wands_ace`, and `wands_five` was reviewed for one central story, exact inline visual evidence, precise Nichols Teacher Model trace, counterevidence, bounded judgment, and an optional continuation menu. High-stakes fixtures retained non-diagnostic/non-legal/non-investment boundaries, and unknown-card resolution stopped without a continuation menu.

The behavior matrix remains evaluator-only raw input and contains no expected answer or reviewer-authored reading.

## Frozen boundaries

No Phase 3A–4C frozen file, canonical snapshot, textbook source, review copy, or installed Skill was changed. Any later modification to a frozen v1.1 runtime artifact requires a new release identity and review cycle.

# Tarot Reader Skill v1.3 — release acceptance

Release ID: `tarot-reader.stage10.v1.3`
Status: `frozen`
Accepted: 2026-09-30

The user authorized freezing and public distribution of this version. This acceptance covers the inspected technical release and its bounded reflective-reading behavior, not a guarantee of factual predictions or a legal determination about source rights.

## Freeze gate

- The package has 30 byte-verified canonical snapshots. Its frozen-input record binds the original source hashes; the Phase 3A–4C inputs remain unchanged.
- The visual query resolves 78 unique cards with 8 Phase 4A rechecks and 70 Phase 4B observations. It fails closed on unknown or ambiguous IDs, missing cards, package additions, hash drift, and provenance mismatch.
- Teacher evidence is source-bound: 78 Daniel card units, 16 Dawn Court plus 4 rank units, 78 Greer reversal units with coverage qualification, and 22 Nichols Major units. Nichols lookup requires an explicit trigger and source-field anchors; the CLI verifies route structure, not free-text semantics.
- The Dictionary route has 22 reviewed units, is available only as a late hypothesis check, and fails closed outside its reviewed coverage.
- Runtime output excludes raw OCR, source PDFs, review-copy images, user images, and evaluator answers. The release manifest hashes the accepted package, including this record.

## Verification and limits

The 2026-09-28 independent blind retest inspected five one-generation model outputs. Two initial hard-boundary failures were repaired and retested. Final outputs passed the targeted boundaries with caution: conditional inferences in the observed-work, Court, and opportunity cases must remain explicitly labelled. These samples do not establish a general reliability rate.

Before freeze, the v1.3 Teacher suite passed 30 runs / 4,978 assertions; its release suite passed 30 runs / 1,499 assertions. v1.1 and v1.2 regressions, Phase 3A–4C validators, and the official Skill validator passed. A fresh copy outside the build workspace passed portable visual, Greer, and Dictionary queries. Freeze-state checks and the public package check are run as part of publication; their exact results belong to the publication record, not a prospective claim in this hashed acceptance file.

This release does not draw cards, identify a user's image, know another person's private thoughts, or supply medical, legal, or financial decisions. Frozen artifacts are not edited in place after publication; future changes require a new release identity. Installation is separate from this acceptance.

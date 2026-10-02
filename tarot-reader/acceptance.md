# Tarot Reader Skill v1.4 — release acceptance

Release ID: `tarot-reader.stage10.v1.4`
Status: `frozen`
Accepted: 2026-10-02

The user requested that the more decisive, longer, connected reading style be preserved in the Skill specification and republished publicly. This v1.4 release supersedes the public v1.3 package without editing its frozen source. Acceptance covers the technical package and composition contract, not a guarantee that every model response will follow the style or a determination of source rights.

## Freeze gate

- The package has 30 byte-verified canonical snapshots. Its frozen-input record binds the original source hashes; the Phase 3A–4C inputs remain unchanged.
- The visual query resolves 78 unique cards with 8 Phase 4A rechecks and 70 Phase 4B observations. It fails closed on unknown or ambiguous IDs, missing cards, package additions, hash drift, and provenance mismatch.
- Teacher evidence is source-bound: 78 Daniel card units, 16 Dawn Court plus 4 rank units, 78 Greer reversal units with coverage qualification, and 22 Nichols Major units. Nichols lookup requires an explicit trigger and source-field anchors; the CLI verifies route structure, not free-text semantics.
- The Dictionary route has 22 reviewed units, is available only as a late hypothesis check, and fails closed outside its reviewed coverage.
- Ordinary readings now lead with a clear card-based judgment, develop a connected spread story, place teacher evidence beside consequential claims, and state a material uncertainty once instead of repeatedly interrupting the reading. The rule does not permit claims of access to another person's private thoughts. A raw evaluator fixture covers the requested longer relationship-reading style; it is not an expected answer or a model-level pass.
- Runtime output excludes raw OCR, source PDFs, review-copy images, user images, and evaluator answers. The release manifest hashes the accepted package, including this record.

## Verification and limits

The v1.3 independent blind retest inspected five one-generation model outputs. Two initial hard-boundary failures were repaired and retested. Its final outputs passed the targeted boundaries with caution. That audit does not establish v1.4 style reliability; v1.4 has not undergone an independent model-level style audit.

The v1.4 Teacher and release suites, official Skill validator, and portable public package check are run as part of publication; their exact results belong to the publication record, not a prospective claim in this hashed acceptance file. The frozen v1.3 evidence corpus and the 30 canonical snapshots are carried forward unchanged except for release identity in the source-provenance envelope. New raw evaluator input is schema-checked but has not been scored against a fresh model response.

This release does not draw cards, identify a user's image, know another person's private thoughts, or supply medical, legal, or financial decisions. Frozen artifacts are not edited in place after publication; future changes require a new release identity. Installation is separate from this acceptance.

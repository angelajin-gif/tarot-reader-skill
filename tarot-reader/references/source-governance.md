# Source governance

The package preserves a minimal exact snapshot rather than copying PDFs or raw source chunks. `release-snapshot-manifest.yaml` records each canonical snapshot's original repository path, SHA-256, stage/contract ID, and canonical-snapshot status; it separately hashes the authored runtime behavior artifacts. `frozen-input-sha256.yaml` records the build inputs that must remain byte-identical. The Dictionary route additionally packages only 22 manually single-column-reviewed condensed units; `dictionary-source-provenance.yaml` records the source hashes, visual-review scope, page provenance, and the fact that OCR candidates remain unpromoted. `interaction-amendment-v1-1.yaml` records the narrow user-authorized change to PC-002 and PC-008 without rewriting the frozen Product Charter.

Use these source classes distinctly:

| Source class | Permitted role | Prohibited shortcut |
| --- | --- | --- |
| `product_constraint` | Scope, interaction, RWS-only, safety, output | Pretending it is textbook evidence |
| `textbook` | Named Teacher Model method in its jurisdiction | Universal card database or override of product/visual facts |
| `general_rws` | Narrow generic RWS context when no frozen fact is being replaced | Importing another deck or changing the visual canon |
| `general_tarot` | Explicitly labeled contextual candidate | Presenting it as one of the five books or as a verified fact |
| `original_inference` | Direct synthesis | Hiding the evidence → operation → warrant chain |

When sources disagree, preserve the distinction and show only a material conflict that changes the judgment. A textbook cannot override a verified RWS visual fact. A Dictionary entry cannot decide whether a reversal mechanism or Court role applies. User-provided facts can contextualize the reading but cannot prove another person's motive or identity.

User-visible provenance is local to the claim it supports. Cite frozen visual evidence by card plus `factual_visual_id` and exact packet fact; cite Teacher evidence by model plus section, concept, or anchor; cite Dictionary evidence by `entry_id` and keep its excerpt/page provenance available. Short verbatim wording requires an exact match in the packaged snapshot and must be attributed to that snapshot or Teacher Model—not presented as a direct quotation from the original book unless an exact original excerpt is actually packaged. Dictionary condensed statements are also paraphrases, not book quotations. Otherwise use an explicitly labeled paraphrase. A bibliography-like list of names at the end does not satisfy provenance, and no source may be credited for the Reader's original synthesis.

The package contains no expected answers, acceptance notes, reviewer judgments, raw PDF text, image files, or user uploads. Dictionary condensed statements are distinct derived reference units, not canonical visual facts or a complete card database. Snapshot changes, missing provenance, or a source hash mismatch are stop-line conditions; an unsupported Dictionary query returns no content rather than a guessed substitute.

# Source governance

This release keeps the 30 canonical snapshots byte-exact and adds a separate, non-canonical Teacher Evidence Layer. `release-snapshot-manifest.yaml` records every snapshot, authored runtime artifact, and Teacher Evidence artifact with SHA-256. `frozen-input-sha256.yaml` records the source inputs used to build the layer. The Teacher Evidence provenance file records book IDs, original paths, hashes, review scope, and the rule that condensed author evidence cannot override Phase 4C visual facts.

Source classes remain distinct:

| Source class | Permitted role | Prohibited shortcut |
| --- | --- | --- |
| `product_constraint` | scope, interaction, RWS-only, safety, output | treating it as textbook evidence |
| `textbook` | named Teacher Model method within its jurisdiction | universal card database or visual override |
| `rws_visual_fact` | the only static RWS visual source | meaning, symbolism, prediction, or psychology |
| `general_rws` | bounded canonical scene identification when identity and facts jointly support it | another deck, visual enrichment, or certainty beyond the packet |
| `general_tarot` | explicitly labelled contextual candidate | pretending it is a five-book claim |
| `original_inference` | direct synthesis | hiding evidence → operation → warrant |

Daniel and Dawn units are manually condensed from rendered PDF pages; Daniel's 22 Major units bind both their opening card-entry page and the manually reviewed meaning/example continuation page. OCR is a locator only and is not runtime content. Seventy Greer entries have substantive card-specific reversal anchors. Eight Page/Knight entries are known coverage gaps: their query output is explicitly marked `coverage_fallback` and cites the reviewed general-method pages 58–63, not the empty card-entry anchor as a card-specific mechanism. Nichols has 22 card-specific Major units grounded in rendered chapter opening/detail pages plus the authored chapter chains; comparative deck material remains explicitly non-RWS. Dictionary content remains the 22 manually reviewed units; the other 1,168 metadata anchors are not content. A source hash mismatch, missing provenance, duplicate unit, unreviewed unit, or source drift is a stop-line condition.

Teacher evidence must be labelled as paraphrase or author interpretation, not user fact. Daniel visual narrative cannot replace an exact Phase 4C fact. Dawn archetype cannot prove identity. Greer cannot activate without explicit reversal. Nichols comparative deck material cannot become RWS evidence. Dictionary condensed statements are reviewed paraphrases, not quotations. No source may be credited for the Reader's original synthesis.

The runtime package contains no PDFs, review images, raw OCR text, expected answers, or acceptance notes. It exposes only the strict Teacher Evidence result whitelist and the visual packet whitelist. Unknown or unsupported content returns no guessed substitute.

# Conditional retrieval routing

Retrieval is evidence for a live hypothesis, not the reading engine. Do not retrieve every book for every card and do not use retrieval to replace spread judgment.

| Capability | Trigger | Snapshot references | Required return |
| --- | --- | --- | --- |
| RWS motif / archetypal amplification | Reliable visual motif, Major movement, projection, polarity, or sequence | `anchors/nichols-retrieval-anchors.yaml`, `anchors/nichols-reasoning-chains.yaml`, `teachers/nichols-book-model.md` | Visible detail and warrant remain separate from interpretation |
| Reversal mechanism | One or more actual reversed cards | `anchors/greer-retrieval-anchors.yaml`, `anchors/greer-card-entry-anchors.jsonl`, `teachers/greer-book-model.md` | Upright baseline plus context-tested mechanism |
| Court ontology | Court cards, person/role, or multiple-Court tension | `anchors/dawn-retrieval-anchors.yaml`, `teachers/dawn-book-model.md` | Role candidates, not identity claims |
| Spread / question / correspondence | Positions, spread shape, number/suit structure, or bounded event framing | `anchors/daniel-retrieval-anchors.yaml`, `anchors/daniel-card-entry-anchors.jsonl`, `teachers/daniel-book-model.md` | Conditional context, never fixed weight or absence rule |
| Concrete manifestation | An existing holistic hypothesis needs a card/domain check | `references/dictionary-reference-units.yaml`, `scripts/query_dictionary_reference.rb`, `teachers/tarot-dictionary-book-model.md` | Typed effect, then return to whole spread; unsupported units fail closed |

Every retrieval note should preserve `hypothesis_before_retrieval`, `retrieval_reason`, `source`, `returned_effect`, and `hypothesis_after_retrieval`. A specialist must be able to support, refine, challenge, supply an alternative, or make no change. If it only confirms a story because the lookup was selected after the answer was known, stop and report the provenance problem.

When a retrieval changes the user-visible judgment, surface the evidence inline: name the Teacher Model and exact section, concept, or anchor, then state whether its effect was `support`, `refine`, `challenge`, `alternative`, or `no_change` in natural language. Quote only wording verified in the snapshot; otherwise identify the statement as a paraphrase. Naming a teacher without the specific operation is not a sufficient trace.

Anchor files are compact, provenance-bearing routing material. The Dictionary is the exception only where a manually single-column-reviewed condensed unit is present in `dictionary-reference-units.yaml`; the packaged Dictionary units are not raw OCR, a closed meaning table, or permission to invent a claim outside the model's jurisdiction. The query script requires an existing hypothesis and retrieval reason, and does not choose whether the result is `support`, `refine`, `challenge`, `alternative`, or `no_change`.

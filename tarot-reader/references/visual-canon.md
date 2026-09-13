# Frozen RWS visual canon

Use `scripts/query_visual_facts.rb` as the sole skill-relative visual query boundary. On every initialization it verifies the complete release snapshot manifest, each listed snapshot SHA-256, the Phase 4C contract ID, `status: frozen`, and the passing freeze-gate counts before reading visual records. It then reads exact byte snapshots listed in `release-snapshot-manifest.yaml` and reproduces Phase 4C's resolution policy:

- 78 unique canonical IDs from the canonical registry;
- the four Phase 4B batches as the record aggregate;
- eight `phase4a_frozen_reference` cards resolved from the Phase 4A recheck snapshot;
- seventy `reviewed` cards resolved directly from Phase 4B observations;
- card-specific source binding to the RWS manifest;
- fail-closed behavior for unknown IDs, missing records, duplicate IDs, unsupported status, missing fields, and source drift.

Examples, run from this Skill directory:

```sh
ruby scripts/query_visual_facts.rb wands_ace "权杖一"
ruby scripts/query_visual_facts.rb swords_nine pentacles_ten
```

The output packet is restricted to `canonical_card_id`, `factual_visual_id`, `scene`, `figures`, `action`, `gaze_and_facing`, `spatial_relations`, `objects`, `unresolved_visuals`, and `source_ref`. It deliberately omits `symbolic_readings`, `edition_specific_visuals`, `review_copy`, acquisition URLs, card meaning, prediction, psychological interpretation, and user images. Colors stay outside the packet. Use static facts only: count visible people, animals, and suit objects exactly when clear; record image-relative direction and spatial relation; put genuinely unclear texture, species, or gaze in `unresolved_visuals`.

The visual packet is evidence, not an interpretation. Do not infer motive, emotion, identity, event, symbolism, or future movement from it.

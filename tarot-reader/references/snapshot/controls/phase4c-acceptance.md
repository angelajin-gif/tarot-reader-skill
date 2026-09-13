# Phase 4C — 78-card Visual Canon Runtime Integration

## Status

`frozen`

Phase 4C is accepted and frozen as the runtime integration boundary for the
Phase 4B factual visual canon. It resolves visual facts by `canonical_card_id`
without authoring new observations, reading user-uploaded deck images, or
entering final Skill authoring.

## Accepted counts

- Canonical registry lookup: 78/78 cards resolved in canonical registry order.
- Canonical IDs: 78/78 unique; Phase 4B record IDs: 78/78 unique and closed over the registry.
- Source binding: 78/78 records bind to the Phase 4A manifest through the card-specific `canonical_source_ref`.
- Frozen Phase 4A references: 8/8 correctly unpack through `runtime/phase4a/visual-pilot-rechecks.yaml`.
- Direct Phase 4B observations: 70/70 correctly read from the corresponding Phase 4B batch record.
- Batch coverage: 4/4 Phase 4B files loaded, 78/78 records aggregated.

## Runtime resolution boundary

- Runtime input is `canonical_card_id`; registry order is the only `load_all` order.
- `phase4a_frozen_reference` records never promote their `phase4a_reference` placeholder. Their seven visual fields are resolved from the card-bound Phase 4A recheck record.
- `reviewed` records resolve their six observation fields and `unresolved_visuals` directly from the Phase 4B record.
- Every packet includes `scene`, `figures`, `action`, `gaze_and_facing`, `spatial_relations`, `objects`, `unresolved_visuals`, and card-bound `source_ref` values.

## Output and safety boundary

The output packet is whitelist-only: `canonical_card_id`, `factual_visual_id`,
the seven visual fact fields, and `source_ref`. It excludes
`symbolic_readings`, `edition_specific_visuals`, review-copy metadata, colors,
card meaning, prediction, psychological interpretation, and user-uploaded deck
images. Phase 4B remains the factual source; legacy visual records are not read
by the Phase 4C loader.

## Fail-closed evidence

The loader rejects each of the following in independent in-memory probes:

- unknown canonical ID;
- missing Phase 4B record;
- duplicate Phase 4B `card_id`;
- card-specific `canonical_source_ref` drift.

It also rejects duplicate registry or manifest IDs, unsupported review states,
missing frozen Phase 4A rechecks, missing observation fields, and incomplete
78-card source closure during initialization.

## Validation evidence

Direct loader invocation:

```text
DIRECT_CALL=PASS packets=78 split={"phase4a_recheck"=>8, "phase4b_observations"=>70}
Phase 4C visual loader ready: 78/78 packets
```

Phase 4C test suite:

```text
7 runs, 1313 assertions, 0 failures, 0 errors, 0 skips
```

Full Phase 3A–4C regression, rerun after freezing this contract:

- `ruby scripts/validate_phase3a_runtime.rb` — pass, 10/10 replays.
- `ruby scripts/validate_phase3b_runtime.rb` — pass, 8 blind executions and 4 metamorphic pairs.
- `ruby scripts/validate_phase3c_loader.rb` — pass, 8 visual pilot packets and all loader integrity checks.
- `ruby scripts/validate_phase4a_integrity.rb` — pass, 78/78 source joins and 8/8 pilot reviews.
- `ruby scripts/validate_phase4b_integrity.rb` — pass, 78/78 reviewed-equivalent records and 4/4 batch files.
- `ruby runtime/phase4c/test_visual_loader.rb` — pass, 7 runs and 1,313 assertions.

## Freeze result

The Phase 4C freeze gate passes:

- 78/78 card lookups;
- 78/78 unique canonical IDs;
- 78/78 source-bound records;
- 8/8 Phase 4A recheck resolutions;
- 70/70 direct Phase 4B resolutions;
- 6/6 Phase 3A–4C regression suites passing.

Stage 10 — final Tarot Reader Skill authoring — is unblocked after this frozen
runtime boundary.

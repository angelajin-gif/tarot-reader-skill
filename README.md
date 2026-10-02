# Tarot Reader Skill

An evidence-traceable Rider–Waite–Smith tarot reading skill for Codex. The current public release is `tarot-reader.stage10.v1.4` (`frozen`).

## What it does

- Reads cards supplied by the user; it never draws or identifies cards from uploaded images.
- Starts ordinary readings with a clear card-based judgment, then builds one longer, relational narrative instead of concatenating isolated card meanings or repeating generic caveats.
- Keeps visible RWS facts, Teacher Model operations, user context, and original inference distinct.
- Places specific visual or Teacher Model evidence beside the claim it affects.
- Ends ordinary completed readings with optional user-drawn follow-up spreads.
- Fails closed on unknown cards, ambiguous aliases, source drift, or unsupported Dictionary units.

## Boundaries

This is a reflective reading tool, not medical, legal, financial, or other professional advice. It does not claim access to another person's private thoughts or guarantee future events.

The package contains no source PDFs, review-copy images, raw OCR chunks, or user images. Its Dictionary route is intentionally limited to 22 manually reviewed condensed units and provides no guessed fallback. The packaged test fixtures are evaluator data, not runtime answers.

## Install

Copy the `tarot-reader` directory into your Codex skills directory:

```sh
cp -R tarot-reader ~/.codex/skills/tarot-reader
```

Then start a new Codex conversation and invoke `$tarot-reader` with your question, context, cards, and any known positions or orientations.

## Validate

The repository includes a portable integrity check that does not require the private build workspace:

```sh
ruby scripts/verify_public_package.rb
```

If Codex's `skill-creator` utilities are available, you can additionally run `quick_validate.py tarot-reader`. See [`tarot-reader/acceptance.md`](tarot-reader/acceptance.md) for the release evidence, blind-audit scope, and limits.

## Repository layout

```text
tarot-reader/
├── SKILL.md
├── acceptance.md
├── agents/
├── references/
└── scripts/
scripts/
└── verify_public_package.rb
```

The project is expected to evolve through new versioned release candidates; frozen artifacts are not edited in place.

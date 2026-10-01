#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "find"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

require_relative "query_visual_facts"
require_relative "query_dictionary_reference"
require_relative "query_teacher_evidence"

class TarotReaderReleaseCandidateTest < Minitest::Test
  SKILL_ROOT = File.expand_path("..", __dir__)
  PROJECT_ROOT = File.expand_path("../..", SKILL_ROOT)
  QUERY_SCRIPT = File.join(SKILL_ROOT, "scripts", "query_visual_facts.rb")
  DICTIONARY_QUERY_SCRIPT = File.join(SKILL_ROOT, "scripts", "query_dictionary_reference.rb")
  SNAPSHOT_MANIFEST = File.join(SKILL_ROOT, "references", "release-snapshot-manifest.yaml")
  FROZEN_HASHES = File.join(SKILL_ROOT, "references", "frozen-input-sha256.yaml")

  PACKET_FIELDS = TarotReaderRelease::VisualFacts::PACKET_FIELDS
  FORBIDDEN_PACKET_FIELDS = %w[
    symbolic_readings
    edition_specific_visuals
    review_copy
    acquisition_url
    user_uploaded_deck_image
    card_meaning
    prediction
    psychological_interpretation
  ].freeze

  def setup
    @loader = TarotReaderRelease::VisualFacts.new
    @dictionary = TarotReaderRelease::DictionaryReferences.new
  end

  def test_standard_skill_structure_is_present
    %w[SKILL.md agents/openai.yaml references scripts].each do |relative_path|
      assert File.exist?(File.join(SKILL_ROOT, relative_path)), "missing #{relative_path}"
    end
    refute File.exist?(File.join(SKILL_ROOT, "README.md"))
    refute File.exist?(File.join(SKILL_ROOT, "changelog.md"))
    assert File.exist?(File.join(SKILL_ROOT, "acceptance.md")), "frozen release requires acceptance"
    assert File.exist?(File.join(SKILL_ROOT, "references/narrative-evidence-continuation.md"))
    assert File.exist?(File.join(SKILL_ROOT, "references/rws-scene-bridge-v1-2.md"))
  end

  def test_snapshot_manifest_is_complete_and_byte_exact
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    assert_equal "tarot-reader.stage10.v1.3", manifest.fetch("release_id")
    assert_equal "frozen", manifest.fetch("status")
    entries = manifest.fetch("entries")
    assert_equal 30, entries.length
    entries.each do |entry|
      snapshot_path = File.join(SKILL_ROOT, entry.fetch("snapshot_path"))
      assert File.file?(snapshot_path), "missing snapshot #{entry.fetch("snapshot_path")}"
      assert_match(/\A[0-9a-f]{64}\z/, entry.fetch("sha256"))
      assert_equal entry.fetch("sha256"), Digest::SHA256.file(snapshot_path).hexdigest
      refute entry.fetch("original_repo_path").start_with?("/")
      assert_equal true, entry.fetch("canonical_snapshot")
    end
  end

  def test_package_inventory_matches_manifest_and_has_no_symlinks
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    declared = manifest.fetch("entries").map { |entry| entry.fetch("snapshot_path") }
    %w[
      authored_runtime_artifacts
      release_evidence_artifacts
      teacher_evidence_artifacts
      release_control_artifacts
      release_test_artifacts
      derived_reference_artifacts
    ].each do |section|
      declared.concat(manifest.fetch(section).map { |entry| entry.fetch("artifact_path") })
    end
    declared << "references/release-snapshot-manifest.yaml"
    assert_equal declared.length, declared.uniq.length, "duplicate release artifact path"

    actual = []
    Find.find(SKILL_ROOT) do |path|
      next if path == SKILL_ROOT

      relative = path.delete_prefix("#{SKILL_ROOT}/")
      stat = File.lstat(path)
      refute stat.symlink?, "symlink in release package: #{relative}"
      actual << relative if stat.file?
    end
    assert_equal declared.sort, actual.sort, "release package has missing or unlisted files"
  end

  def test_actual_visual_query_rejects_unlisted_package_file
    with_skill_copy do |copy_root|
      File.write(File.join(copy_root, "source.pdf"), "AUDIT_UNLISTED_FILE")
      _output, error, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "strength")
      refute status.success?
      assert_match(/release package file inventory mismatch/, error)
    end
  end

  def test_actual_visual_query_rejects_release_control_hash_drift
    with_skill_copy do |copy_root|
      File.open(File.join(copy_root, "references/frozen-input-sha256.yaml"), "a") { |file| file.write("\n# audit drift\n") }
      _output, error, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "strength")
      refute status.success?
      assert_match(/release_control_artifacts artifact hash mismatch/, error)
    end
  end

  def test_actual_visual_query_rejects_symlink_in_package
    with_skill_copy do |copy_root|
      File.symlink("SKILL.md", File.join(copy_root, "linked-skill.md"))
      _output, error, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "strength")
      refute status.success?
      assert_match(/symlink in release package/, error)
    end
  end

  def test_recorded_frozen_input_hashes_match_repository_sources
    manifest = YAML.load_file(FROZEN_HASHES)
    assert_equal "tarot-reader.stage10.v1.3", manifest.fetch("release_id")
    checked = 0
    manifest.fetch("inputs").each do |entry|
      next if entry.fetch("source_path").start_with?("external/")

      source_path = File.join(PROJECT_ROOT, entry.fetch("source_path"))
      assert File.file?(source_path), "missing frozen input #{entry.fetch("source_path")}"
      assert_equal entry.fetch("sha256"), Digest::SHA256.file(source_path).hexdigest,
                   "hash drift for #{entry.fetch("source_path")}"
      checked += 1
    end
    assert_equal 36, checked
  end

  def test_snapshot_entries_match_the_recorded_source_hashes
    snapshot_manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    frozen_manifest = YAML.load_file(FROZEN_HASHES)
    source_hashes = frozen_manifest.fetch("inputs").to_h { |entry| [entry.fetch("source_path"), entry.fetch("sha256")] }

    snapshot_manifest.fetch("entries").each do |entry|
      assert_equal source_hashes.fetch(entry.fetch("original_repo_path")), entry.fetch("sha256"),
                   "snapshot/source hash mismatch for #{entry.fetch("original_repo_path")}"
    end
  end

  def test_derived_dictionary_artifacts_are_manifested_and_hashed
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    artifacts = manifest.fetch("derived_reference_artifacts")
    assert_equal 2, artifacts.length
    artifacts.each do |artifact|
      path = File.join(SKILL_ROOT, artifact.fetch("artifact_path"))
      assert File.file?(path)
      assert_equal artifact.fetch("sha256"), Digest::SHA256.file(path).hexdigest
      assert_equal false, artifact.fetch("canonical_snapshot")
      refute artifact.fetch("stage_or_contract_id").to_s.empty?
    end
  end

  def test_authored_runtime_artifacts_are_complete_and_hashed
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    artifacts = manifest.fetch("authored_runtime_artifacts")
    assert_equal TarotReaderRelease::VisualFacts::AUTHORED_RUNTIME_PATHS.sort,
                 artifacts.map { |entry| entry.fetch("artifact_path") }.sort
    assert_equal 14, artifacts.length
    artifacts.each do |artifact|
      path = File.join(SKILL_ROOT, artifact.fetch("artifact_path"))
      assert File.file?(path), "missing authored runtime artifact #{artifact.fetch("artifact_path")}"
      assert_equal artifact.fetch("sha256"), Digest::SHA256.file(path).hexdigest
      refute artifact.fetch("runtime_role").to_s.empty?
    end
  end

  def test_frozen_release_has_hashed_acceptance
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    assert_equal "frozen", manifest.fetch("status")
    evidence = manifest.fetch("release_evidence_artifacts")
    assert_equal ["acceptance.md"], evidence.map { |entry| entry.fetch("artifact_path") }
    assert_equal evidence.first.fetch("sha256"), Digest::SHA256.file(File.join(SKILL_ROOT, "acceptance.md")).hexdigest
  end

  def test_v1_1_interaction_amendment_is_narrow_and_auditable
    amendment = YAML.load_file(File.join(SKILL_ROOT, "references/interaction-amendment-v1-1.yaml"))
    assert_equal "tarot-reader.interaction-amendment.v1.1", amendment.fetch("amendment_id")
    assert_equal "frozen", amendment.fetch("status")
    assert_equal "user_authorized_product_change", amendment.fetch("authority")
    assert_equal "tarot-reader.stage10.v1.1", amendment.fetch("effective_release")
    assert_equal "tarot_product_charter.v1", amendment.fetch("base_charter_id")
    assert_equal %w[PC-002 PC-008], amendment.fetch("amends").map { |item| item.fetch("rule_id") }
    assert_equal false, amendment.fetch("provenance").fetch("raw_conversation_embedded")
  end

  def test_v1_2_scene_identity_amendment_preserves_layer_boundaries
    amendment = YAML.load_file(File.join(SKILL_ROOT, "references/scene-identity-amendment-v1-2.yaml"))
    assert_equal "tarot-reader.scene-identity-amendment.v1.2", amendment.fetch("amendment_id")
    assert_equal "release_candidate", amendment.fetch("status")
    assert_equal "tarot-reader.stage10.v1.2", amendment.fetch("effective_release")
    assert_equal "tarot-reader.stage10.v1.1", amendment.fetch("base_release")
    assert_equal %w[frozen_visual_fact rws_scene_identification symbolic_or_psychological_inference],
                 amendment.fetch("required_separation")
    assert_includes amendment.dig("strength_case", "permitted_scene_identification"), "lion"
    assert_includes amendment.fetch("boundaries"), "Never rewrite or enrich the frozen visual packet itself."
  end

  def test_v1_3_frozen_release_identity_is_consistent
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    frozen_inputs = YAML.load_file(FROZEN_HASHES)
    assert_equal "tarot-reader.stage10.v1.3", manifest.fetch("release_id")
    assert_equal "tarot-reader.stage10.v1.3", frozen_inputs.fetch("release_id")
    assert_equal "frozen", manifest.fetch("status")
    units = YAML.load_file(File.join(SKILL_ROOT, "references/dictionary-reference-units.yaml"))
    provenance = YAML.load_file(File.join(SKILL_ROOT, "references/dictionary-source-provenance.yaml"))
    assert_equal "frozen", units.fetch("status")
    assert_equal "frozen", provenance.fetch("status")
  end

  def test_visual_canon_resolves_78_unique_packets_with_8_70_split
    packets = @loader.load_all
    assert_equal 78, packets.length
    assert_equal 78, packets.map { |packet| packet.fetch("canonical_card_id") }.uniq.length
    assert_equal 8, packets.count { |packet| packet.dig("source_ref", "resolved_observation_source") == "phase4a_recheck" }
    assert_equal 70, packets.count { |packet| packet.dig("source_ref", "resolved_observation_source") == "phase4b_observations" }

    packets.each do |packet|
      assert_equal PACKET_FIELDS.sort, packet.keys.sort
      refute (packet.keys & FORBIDDEN_PACKET_FIELDS).any?
      assert_equal 5, packet.fetch("source_ref").length
      assert_equal packet.fetch("canonical_card_id"), packet.fetch("source_ref").fetch("canonical_registry").split("#").last
      assert_equal packet.fetch("canonical_card_id"), packet.fetch("source_ref").fetch("canonical_source").split("#").last
      assert_equal packet.fetch("canonical_card_id"), packet.fetch("source_ref").fetch("phase4b_record").split("#").last
    end
  end

  def test_chinese_and_english_display_names_normalize_without_mutating_id
    assert_equal "wands_ace", @loader.resolve_selector("权杖一")
    assert_equal "wands_ace", @loader.resolve_selector("Ace of Wands")
    assert_equal "wands_ace", @loader.packet("权杖一").fetch("canonical_card_id")
    assert_equal "wands_ace", @loader.packet(" Ace   of Wands ").fetch("canonical_card_id")
  end

  def test_unknown_and_ambiguous_selectors_fail_closed
    assert_raises(TarotReaderRelease::ResolutionError) { @loader.resolve_selector("not_a_card") }
    assert_raises(TarotReaderRelease::ResolutionError) do
      @loader.resolve_selector("same name", { "same name" => %w[wands_ace wands_two] })
    end

    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, QUERY_SCRIPT, "not_a_card")
    refute status.success?
    assert_match(/failed closed/, stderr)
  end

  def test_missing_duplicate_and_source_drift_inputs_fail_closed
    documents = batch_documents
    documents[0][1]["records"].shift
    error = assert_raises(TarotReaderRelease::ResolutionError) do
      TarotReaderRelease::VisualFacts.new(batch_documents: documents)
    end
    assert_match(/do not close over canonical registry|count/, error.message)

    documents = batch_documents
    documents[0][1]["records"] << deep_copy(documents[0][1]["records"].first)
    error = assert_raises(TarotReaderRelease::ResolutionError) do
      TarotReaderRelease::VisualFacts.new(batch_documents: documents)
    end
    assert_match(/not unique/, error.message)

    documents = batch_documents
    documents[0][1]["records"].first["canonical_source_ref"] =
      "runtime/phase4a/rws-visual-source-manifest.yaml#wands_two"
    error = assert_raises(TarotReaderRelease::ResolutionError) do
      TarotReaderRelease::VisualFacts.new(batch_documents: documents)
    end
    assert_match(/source binding mismatch/, error.message)
  end

  def test_duplicate_registry_id_and_unsupported_status_fail_closed
    registry = deep_copy(YAML.load_file(File.join(SKILL_ROOT, "references/snapshot/visual/canonical-card-registry.yaml")))
    registry["cards"] << deep_copy(registry["cards"].first)
    error = assert_raises(TarotReaderRelease::ResolutionError) do
      TarotReaderRelease::VisualFacts.new(registry_document: registry)
    end
    assert_match(/canonical registry IDs count/, error.message)

    documents = batch_documents
    documents[0][1]["records"].first["review_status"] = "unsupported"
    error = assert_raises(TarotReaderRelease::ResolutionError) do
      TarotReaderRelease::VisualFacts.new(batch_documents: documents)
    end
    assert_match(/unsupported review_status/, error.message)
  end

  def test_actual_visual_query_fails_closed_on_snapshot_tamper
    with_skill_copy do |copy_root|
      snapshot_path = File.join(copy_root, "references/snapshot/visual/batch_03_wands_cups.yaml")
      document = YAML.load_file(snapshot_path)
      document.fetch("records").find { |record| record.fetch("card_id") == "wands_two" }
        .fetch("observations")["scene"] = "AUDIT_TAMPERED_VISUAL_FACT"
      File.write(snapshot_path, YAML.dump(document))

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "wands_two"
      )
      refute status.success?
      assert_match(/failed closed|hash mismatch/, stderr)
    end
  end

  def test_actual_query_fails_closed_on_authored_behavior_tamper
    with_skill_copy do |copy_root|
      skill_path = File.join(copy_root, "SKILL.md")
      File.write(skill_path, File.read(skill_path) + "\nAUDIT_TAMPERED_BEHAVIOR\n")

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "wands_two"
      )
      refute status.success?
      assert_match(/authored runtime artifact hash mismatch|failed closed/, stderr)
    end
  end

  def test_actual_visual_query_requires_a_frozen_phase4c_gate
    with_skill_copy do |copy_root|
      contract_path = File.join(copy_root, "references/snapshot/controls/phase4c-visual-loader-contract.yaml")
      contract = YAML.load_file(contract_path)
      contract["status"] = "in_progress"
      File.write(contract_path, YAML.dump(contract))

      manifest_path = File.join(copy_root, "references/release-snapshot-manifest.yaml")
      manifest = YAML.load_file(manifest_path)
      entry = manifest.fetch("entries").find do |item|
        item.fetch("snapshot_path") == "references/snapshot/controls/phase4c-visual-loader-contract.yaml"
      end
      entry["sha256"] = Digest::SHA256.file(contract_path).hexdigest
      File.write(manifest_path, YAML.dump(manifest))

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "wands_two"
      )
      refute status.success?
      assert_match(/Phase 4C contract is not frozen|failed closed/, stderr)
    end
  end

  def test_actual_visual_query_requires_matching_phase4c_freeze_counts
    with_skill_copy do |copy_root|
      contract_path = File.join(copy_root, "references/snapshot/controls/phase4c-visual-loader-contract.yaml")
      contract = YAML.load_file(contract_path)
      contract.fetch("freeze_gate")["actual_card_count"] = 77
      File.write(contract_path, YAML.dump(contract))

      manifest_path = File.join(copy_root, "references/release-snapshot-manifest.yaml")
      manifest = YAML.load_file(manifest_path)
      entry = manifest.fetch("entries").find do |item|
        item.fetch("snapshot_path") == "references/snapshot/controls/phase4c-visual-loader-contract.yaml"
      end
      entry["sha256"] = Digest::SHA256.file(contract_path).hexdigest
      File.write(manifest_path, YAML.dump(manifest))

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "wands_two"
      )
      refute status.success?
      assert_match(/freeze gate mismatch|failed closed/, stderr)
    end
  end

  def test_dictionary_units_are_consumable_and_late_only
    units = YAML.load_file(File.join(SKILL_ROOT, "references/dictionary-reference-units.yaml"))
    assert_equal 22, units.fetch("entries").length
    assert_equal 22, units.fetch("coverage").fetch("unit_count")

    result = @dictionary.query(
      selector: "Ace of Wands",
      orientation: "upright",
      domain: "work",
      hypothesis: "资源分配是当前工作安排的主张",
      retrieval_reason: "核对具体工作表现"
    ).first
    assert_equal TarotReaderRelease::DictionaryReferences::RESULT_FIELDS.sort, result.keys.sort
    assert_equal "wands_ace", result.fetch("canonical_card_id")
    assert_includes result.fetch("condensed_statement"), "新工作"
    assert_equal "manually_reviewed_single_column", result.dig("source_ref", "review_status")
    refute result.key?("symbolic_readings")
    refute result.key?("card_meaning")

    assert_raises(TarotReaderRelease::ResolutionError) do
      @dictionary.query(selector: "wands_ace", orientation: "upright", domain: "work")
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @dictionary.query(
        selector: "wands_ace", orientation: "unspecified", domain: "work",
        hypothesis: "已有整体假设", retrieval_reason: "需要具体化核对"
      )
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @dictionary.query(
        selector: "wands_ace", orientation: "upright", domain: "unsupported",
        hypothesis: "已有整体假设", retrieval_reason: "需要具体化核对"
      )
    end

    _stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, DICTIONARY_QUERY_SCRIPT, "wands_ace", "upright", "work",
      "--hypothesis", "已有整体假设", "--reason", "需要具体化核对"
    )
    assert status.success?, stderr
  end

  def test_actual_dictionary_query_fails_closed_on_unit_tamper
    with_skill_copy do |copy_root|
      units_path = File.join(copy_root, "references/dictionary-reference-units.yaml")
      units = YAML.load_file(units_path)
      units.fetch("entries").first["condensed_statement"] = "AUDIT_TAMPERED_DICTIONARY_CONTENT"
      File.write(units_path, YAML.dump(units))

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, File.join(copy_root, "scripts/query_dictionary_reference.rb"),
        "wands_ace", "upright", "work", "--hypothesis", "已有整体假设", "--reason", "需要具体化核对"
      )
      refute status.success?
      assert_match(/derived artifact hash mismatch|failed closed/, stderr)
    end
  end

  def test_teacher_evidence_manifest_and_five_book_coverage
    manifest = YAML.load_file(SNAPSHOT_MANIFEST)
    teacher_artifacts = manifest.fetch("teacher_evidence_artifacts")
    assert_equal 7, teacher_artifacts.length
    teacher_artifacts.each do |artifact|
      path = File.join(SKILL_ROOT, artifact.fetch("artifact_path"))
      assert File.file?(path)
      assert_equal artifact.fetch("sha256"), Digest::SHA256.file(path).hexdigest
      assert_equal false, artifact.fetch("canonical_snapshot")
    end
    release_tests = manifest.fetch("release_test_artifacts")
    assert_equal 4, release_tests.length
    release_tests.each do |artifact|
      path = File.join(SKILL_ROOT, artifact.fetch("artifact_path"))
      assert File.file?(path)
      assert_equal artifact.fetch("sha256"), Digest::SHA256.file(path).hexdigest
      assert_equal false, artifact.fetch("canonical_snapshot")
    end

    assert_equal 78, YAML.load_file(File.join(SKILL_ROOT, "references/teacher-evidence/daniel-card-units.yaml")).fetch("unit_count")
    dawn = YAML.load_file(File.join(SKILL_ROOT, "references/teacher-evidence/dawn-court-units.yaml"))
    assert_equal 16, dawn.fetch("court_unit_count")
    assert_equal 4, dawn.fetch("rank_unit_count")
    assert_equal 78, YAML.load_file(File.join(SKILL_ROOT, "references/teacher-evidence/greer-reversal-units.yaml")).fetch("unit_count")
    assert_equal 22, YAML.load_file(File.join(SKILL_ROOT, "references/teacher-evidence/nichols-amplification-units.yaml")).fetch("unit_count")
    assert File.exist?(File.join(SKILL_ROOT, "references/teacher-evidence-behavior-fixtures.yaml"))
  end

  def test_teacher_query_exposes_real_evidence_and_permissions
    teacher = TarotReaderRelease::TeacherEvidence.new
    daniel = teacher.query(selector: "wands_two", teacher: "daniel", orientation: "upright").fetch(0)
    assert_equal "daniel.wands_two.upright_baseline", daniel.fetch("unit_id")
    assert_includes daniel.dig("evidence_detail", "author_visual_narrative"), "城牆"
    assert_equal "daniel_16_lessons_zh", daniel.dig("source_ref", "source_book_id")
    assert_equal [55], daniel.dig("source_ref", "source_pages")

    dawn = teacher.query(selector: "wands_queen", teacher: "dawn").fetch(0)
    assert_equal "dawn.wands_queen.court", dawn.fetch("unit_id")
    assert dawn.dig("evidence_detail", "strengths").is_a?(Array)
    assert dawn.dig("evidence_detail", "shadow_or_failure_modes").is_a?(Array)

    greer = teacher.query(selector: "swords_two", teacher: "greer", orientation: "reversed").fetch(0)
    assert_equal "reversed_only", greer.fetch("orientation_scope")
    assert greer.dig("evidence_detail", "reversal_mechanism_candidates").is_a?(Array)
    assert_raises(TarotReaderRelease::ResolutionError) do
      teacher.query(selector: "swords_two", teacher: "greer", orientation: "unspecified")
    end
    unspecified = teacher.query(selector: "wands_two", teacher: "daniel", orientation: "unspecified").fetch(0)
    assert_equal "upright_baseline_for_unspecified_orientation", unspecified.fetch("orientation_scope")
    refute_equal "upright", unspecified.fetch("orientation_scope")
  end

  def test_behavior_matrix_is_raw_evaluator_input_without_answer_data
    matrix_path = File.join(SKILL_ROOT, "references", "behavior-test-matrix.yaml")
    matrix = YAML.load_file(matrix_path)
    assert_equal "evaluator_only_raw_inputs", matrix.fetch("runtime_use")
    required_cases = %w[
      positioned_spread
      no_positions_left_to_right
      one_reversal
      multiple_reversals
      court_ontology
      label_behavior_conflict
      internal_tension
      bounded_future
      unbounded_future
      dictionary_late
      dictionary_late_with_observation
      narrative_inline_evidence_continuation
      high_stakes_health
      high_stakes_legal_finance
    ]
    assert_equal required_cases.sort, matrix.fetch("cases").map { |item| item.fetch("case_id") }.sort
    gaps = matrix.fetch("cases").to_h { |item| [item.fetch("case_id"), item.fetch("raw_input")] }
    assert_includes gaps.fetch("dictionary_late").fetch("background"), "整体假设"
    assert_includes gaps.fetch("dictionary_late_with_observation").fetch("background"), "邮件"
    matrix.fetch("cases").each do |item|
      raw_input = item.fetch("raw_input")
      refute raw_input.key?("expected_answer")
      refute raw_input.key?("acceptance_notes")
      refute raw_input.key?("reference_judgment")
      raw_input.fetch("cards").each do |card|
        assert_equal card.fetch("canonical_card_id"), @loader.resolve_selector(card.fetch("canonical_card_id"))
      end
    end
  end

  def test_expression_contract_is_discoverable_without_weakening_stop_lines
    skill = File.read(File.join(SKILL_ROOT, "SKILL.md"))
    composition = File.read(File.join(SKILL_ROOT, "references/narrative-evidence-continuation.md"))
    reader_contract = File.read(File.join(SKILL_ROOT, "references/reader-contract.md"))

    assert_includes skill, "references/narrative-evidence-continuation.md"
    assert_includes skill, "references/interaction-amendment-v1-1.yaml"
    assert_includes skill, "references/scene-identity-amendment-v1-2.yaml"
    assert_includes skill, "references/rws-scene-bridge-v1-2.md"
    assert_includes skill, "one central narrative arc"
    assert_includes skill, "exact section, concept, or anchor"
    assert_includes skill, "two or three concrete directions"
    assert_includes skill, "Do not ask follow-up questions"
    assert_includes reader_contract, "does not draw, redraw, identify an uploaded image, or ask follow-up questions"
    assert_includes reader_contract, "No citation quota exists"
    assert_includes composition, "Do not cite every teacher"
    assert_includes composition, "RWS scene identification"
    bridge = File.read(File.join(SKILL_ROOT, "references/rws-scene-bridge-v1-2.md"))
    assert_includes bridge, "a woman leans close to a lion"
    assert_includes bridge, "It must not silently become the third layer"
    assert_includes composition, "Do not add this continuation when resolution or provenance has failed closed"
    assert_includes composition, "do not ask cards to identify bodily signals"
    assert_includes composition, "decide an investment amount or action"
  end

  def test_skill_does_not_embed_absolute_runtime_paths
    Dir.glob(File.join(SKILL_ROOT, "**", "*")).select { |path| File.file?(path) }.each do |path|
      contents = File.binread(path).force_encoding("UTF-8")
      refute_includes contents, [File::SEPARATOR, "Users", File::SEPARATOR].join, "absolute path in #{path}"
      refute_includes contents, [File::SEPARATOR, "private", "var", File::SEPARATOR].join, "absolute path in #{path}"
      refute_includes contents, ["file", "://"].join, "absolute URI in #{path}"
    end
  end

  private

  def batch_documents
    TarotReaderRelease::VisualFacts::BATCH_PATHS.map do |path|
      [path, deep_copy(YAML.load_file(File.join(SKILL_ROOT, path)))]
    end
  end

  def with_skill_copy
    Dir.mktmpdir("tarot-reader-release") do |temporary_root|
      copy_root = File.join(temporary_root, "tarot-reader")
      FileUtils.cp_r(SKILL_ROOT, copy_root)
      yield copy_root
    end
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end
end

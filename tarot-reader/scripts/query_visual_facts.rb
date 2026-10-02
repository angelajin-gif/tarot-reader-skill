#!/usr/bin/env ruby

require "json"
require "digest"
require "find"
require "pathname"
require "yaml"

module TarotReaderRelease
  RELEASE_ROOT = File.expand_path("..", __dir__).freeze
  VISUAL_ROOT = File.join(RELEASE_ROOT, "references", "snapshot", "visual").freeze
  CONTROLS_ROOT = File.join(RELEASE_ROOT, "references", "snapshot", "controls").freeze

  class ResolutionError < StandardError; end

  class VisualFacts
    AUTHORED_RUNTIME_PATHS = %w[
      SKILL.md
      agents/openai.yaml
      references/interaction-amendment-v1-1.yaml
      references/input-output-schema.md
      references/narrative-evidence-continuation.md
      references/reader-contract.md
      references/retrieval-routing.md
      references/rws-scene-bridge-v1-2.md
      references/scene-identity-amendment-v1-2.yaml
      references/source-governance.md
      references/teacher-jurisdictions.md
      references/visual-canon.md
      scripts/query_dictionary_reference.rb
      scripts/query_visual_facts.rb
    ].freeze
    RELEASE_EVIDENCE_PATHS = %w[acceptance.md].freeze
    OTHER_RELEASE_GROUP_PATHS = {
      "teacher_evidence_artifacts" => %w[
        references/teacher-evidence/daniel-card-units.yaml
        references/teacher-evidence/dawn-court-units.yaml
        references/teacher-evidence/greer-reversal-units.yaml
        references/teacher-evidence/nichols-amplification-units.yaml
        references/teacher-evidence/provenance.yaml
        scripts/build_teacher_evidence.rb
        scripts/query_teacher_evidence.rb
      ],
      "release_control_artifacts" => %w[references/frozen-input-sha256.yaml],
      "release_test_artifacts" => %w[
        references/behavior-test-matrix.yaml
        references/teacher-evidence-behavior-fixtures.yaml
        scripts/test_release_candidate.rb
        scripts/test_teacher_evidence.rb
      ],
      "derived_reference_artifacts" => %w[
        references/dictionary-reference-units.yaml
        references/dictionary-source-provenance.yaml
      ]
    }.freeze

    OBSERVATION_FIELDS = %w[
      scene
      figures
      action
      gaze_and_facing
      spatial_relations
      objects
      unresolved_visuals
    ].freeze

    PACKET_FIELDS = %w[
      canonical_card_id
      factual_visual_id
      scene
      figures
      action
      gaze_and_facing
      spatial_relations
      objects
      unresolved_visuals
      source_ref
    ].freeze

    BATCH_PATHS = %w[
      references/snapshot/visual/batch_01_major_arcana.yaml
      references/snapshot/visual/batch_02_court_cards.yaml
      references/snapshot/visual/batch_03_wands_cups.yaml
      references/snapshot/visual/batch_04_swords_pentacles.yaml
    ].freeze

    def initialize(root: RELEASE_ROOT, registry_document: nil, manifest_document: nil,
                   recheck_document: nil, batch_documents: nil, phase4b_contract_document: nil)
      @root = File.expand_path(root)
      @release_snapshot_manifest = load_yaml("references/release-snapshot-manifest.yaml")
      @phase4c_contract = load_yaml("references/snapshot/controls/phase4c-visual-loader-contract.yaml")
      @registry = registry_document || load_yaml("references/snapshot/visual/canonical-card-registry.yaml")
      @manifest = manifest_document || load_yaml("references/snapshot/visual/rws-visual-source-manifest.yaml")
      @rechecks = recheck_document || load_yaml("references/snapshot/visual/visual-pilot-rechecks.yaml")
      @phase4b_contract = phase4b_contract_document || load_yaml("references/snapshot/controls/phase4b-contract.yaml")
      @batch_documents = batch_documents || BATCH_PATHS.map { |path| [path, load_yaml(path)] }
      validate!
    end

    def load_all
      @registry_ids.map { |card_id| packet(card_id) }
    end

    def packet(card_id)
      canonical_id = resolve_selector(card_id)
      record = @records.fetch(canonical_id)
      observation = observation_for(record)
      source_path, = @record_locations.fetch(canonical_id)
      phase4a_recheck = record["review_status"] == "phase4a_frozen_reference" ?
        "references/snapshot/visual/visual-pilot-rechecks.yaml##{canonical_id}" : nil

      result = {
        "canonical_card_id" => canonical_id,
        "factual_visual_id" => record.fetch("factual_visual_id"),
        "scene" => observation.fetch("scene"),
        "figures" => observation.fetch("figures"),
        "action" => observation.fetch("action"),
        "gaze_and_facing" => observation.fetch("gaze_and_facing"),
        "spatial_relations" => observation.fetch("spatial_relations"),
        "objects" => observation.fetch("objects"),
        "unresolved_visuals" => observation.fetch("unresolved_visuals"),
        "source_ref" => {
          "canonical_registry" => "references/snapshot/visual/canonical-card-registry.yaml##{canonical_id}",
          "canonical_source" => "references/snapshot/visual/rws-visual-source-manifest.yaml##{canonical_id}",
          "phase4b_record" => "#{source_path}##{canonical_id}",
          "phase4a_recheck" => phase4a_recheck,
          "resolved_observation_source" => record["review_status"] == "phase4a_frozen_reference" ?
            "phase4a_recheck" : "phase4b_observations"
        }
      }
      unless result.keys.sort == PACKET_FIELDS.sort
        raise ResolutionError, "visual packet field whitelist violation for #{canonical_id}"
      end
      result
    end

    def resolve_selector(selector, aliases = @aliases)
      key = normalize(selector)
      raise ResolutionError, "unknown card selector: #{selector.inspect}" if key.empty?

      matches = aliases.fetch(key, [])
      raise ResolutionError, "unknown card selector: #{selector.inspect}" if matches.empty?
      if matches.length != 1
        raise ResolutionError, "ambiguous card selector: #{selector.inspect}"
      end

      matches.first
    end

    def resolve_selectors(selectors)
      selectors.map { |selector| resolve_selector(selector) }
    end

    def normalize(value)
      value.to_s.unicode_normalize(:nfkc).strip.gsub(/\s+/, " ").downcase
    end

    private

    def load_yaml(relative_path)
      YAML.load_file(File.join(@root, relative_path))
    rescue Errno::ENOENT => error
      raise ResolutionError, "missing visual snapshot: #{relative_path} (#{error.message})"
    rescue Psych::Exception => error
      raise ResolutionError, "invalid visual snapshot YAML: #{relative_path} (#{error.message})"
    end

    def validate!
      validate_release_snapshot_manifest!
      validate_phase4c_contract!

      @registry_cards = Array(@registry.fetch("cards"))
      @registry_ids = @registry_cards.map { |card| card.fetch("canonical_card_id") }
      require_count_and_unique(@registry_ids, 78, "canonical registry IDs")

      manifest_records = Array(@manifest.fetch("records"))
      manifest_ids = manifest_records.map { |record| record.fetch("card_id") }
      require_count_and_unique(manifest_ids, 78, "RWS source manifest IDs")
      @manifest_by_id = manifest_records.to_h { |record| [record.fetch("card_id"), record] }

      recheck_records = Array(@rechecks.fetch("records"))
      recheck_ids = recheck_records.map { |record| record.fetch("card_id") }
      require_count_and_unique(recheck_ids, 8, "Phase 4A recheck IDs")
      @recheck_by_id = recheck_records.to_h { |record| [record.fetch("card_id"), record] }

      batch_ids = []
      @records = {}
      @record_locations = {}
      @batch_documents.each do |path, document|
        records = Array(document.fetch("records"))
        records.each do |record|
          card_id = record.fetch("card_id")
          if @records.key?(card_id)
            raise ResolutionError, "Phase 4B records card_id is not unique: #{card_id}"
          end
          @records[card_id] = record
          @record_locations[card_id] = [path, record]
          batch_ids << card_id
        end
      end
      require_count_and_unique(batch_ids, 78, "Phase 4B records")
      unless @records.keys.sort == @registry_ids.sort
        missing = @registry_ids - @records.keys
        extra = @records.keys - @registry_ids
        raise ResolutionError, "Phase 4B records do not close over canonical registry; missing=#{missing.inspect} extra=#{extra.inspect}"
      end

      frozen_ids = []
      @records.each do |card_id, record|
        validate_record!(card_id, record)
        frozen_ids << card_id if record.fetch("review_status") == "phase4a_frozen_reference"
      end
      require_count_and_unique(frozen_ids, 8, "Phase 4A frozen-reference records")
      direct_ids = @records.keys - frozen_ids
      require_count_and_unique(direct_ids, 70, "direct Phase 4B observation records")

      unless @phase4b_contract.fetch("status") == "frozen"
        raise ResolutionError, "Phase 4B contract is not frozen"
      end

      @aliases = build_alias_index
      true
    rescue KeyError => error
      raise ResolutionError, "malformed visual snapshot: #{error.message}"
    end

    def validate_release_snapshot_manifest!
      unless @release_snapshot_manifest.fetch("release_id") == "tarot-reader.stage10.v1.4" &&
             @release_snapshot_manifest.fetch("status") == "frozen" &&
             @release_snapshot_manifest.fetch("snapshot_root") == "references/snapshot"
        raise ResolutionError, "release snapshot manifest identity/status mismatch"
      end
      entries = Array(@release_snapshot_manifest.fetch("entries"))
      require_count_and_unique(entries.map { |entry| entry.fetch("snapshot_path") }, 30,
                               "release snapshot manifest entries")

      listed_paths = entries.map { |entry| entry.fetch("snapshot_path") }.sort
      actual_paths = Dir.glob(File.join(@root, "references", "snapshot", "**", "*"))
        .select { |path| File.file?(path) }
        .map { |path| Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s }
        .sort
      unless listed_paths == actual_paths
        raise ResolutionError, "release snapshot manifest does not close over package snapshots"
      end

      entries.each do |entry|
        snapshot_path = entry.fetch("snapshot_path")
        unless snapshot_path.start_with?("references/snapshot/") && !snapshot_path.include?("..")
          raise ResolutionError, "invalid release snapshot path: #{snapshot_path}"
        end
        unless entry.fetch("canonical_snapshot") == true
          raise ResolutionError, "release snapshot is not canonical: #{snapshot_path}"
        end
        original_path = entry.fetch("original_repo_path")
        if original_path.start_with?("/")
          raise ResolutionError, "release snapshot original path is absolute: #{original_path}"
        end
        file_path = File.join(@root, snapshot_path)
        unless File.file?(file_path)
          raise ResolutionError, "missing release snapshot: #{snapshot_path}"
        end
        actual_sha256 = Digest::SHA256.file(file_path).hexdigest
        unless actual_sha256 == entry.fetch("sha256")
          raise ResolutionError, "release snapshot hash mismatch: #{snapshot_path}"
        end
        if entry.fetch("stage_or_contract_id").to_s.empty?
          raise ResolutionError, "missing stage/contract provenance: #{snapshot_path}"
        end
      end

      authored = Array(@release_snapshot_manifest.fetch("authored_runtime_artifacts"))
      authored_paths = authored.map { |entry| entry.fetch("artifact_path") }
      require_count_and_unique(authored_paths, AUTHORED_RUNTIME_PATHS.length,
                               "authored runtime artifacts")
      unless authored_paths.sort == AUTHORED_RUNTIME_PATHS.sort
        raise ResolutionError, "authored runtime artifact manifest is incomplete"
      end
      authored.each do |entry|
        relative_path = entry.fetch("artifact_path")
        if relative_path.start_with?("/") || relative_path.include?("..")
          raise ResolutionError, "invalid authored runtime artifact path: #{relative_path}"
        end
        unless entry.fetch("runtime_role").to_s.length.positive?
          raise ResolutionError, "missing authored runtime role: #{relative_path}"
        end
        artifact_path = File.join(@root, relative_path)
        unless File.file?(artifact_path)
          raise ResolutionError, "missing authored runtime artifact: #{relative_path}"
        end
        unless Digest::SHA256.file(artifact_path).hexdigest == entry.fetch("sha256")
          raise ResolutionError, "authored runtime artifact hash mismatch: #{relative_path}"
        end
      end

      evidence = Array(@release_snapshot_manifest.fetch("release_evidence_artifacts"))
      evidence_paths = evidence.map { |entry| entry.fetch("artifact_path") }
      require_count_and_unique(evidence_paths, RELEASE_EVIDENCE_PATHS.length,
                               "release evidence artifacts")
      unless evidence_paths.sort == RELEASE_EVIDENCE_PATHS.sort
        raise ResolutionError, "release evidence artifact manifest is incomplete"
      end
      evidence.each do |entry|
        relative_path = entry.fetch("artifact_path")
        if relative_path.start_with?("/") || relative_path.include?("..")
          raise ResolutionError, "invalid release evidence artifact path: #{relative_path}"
        end
        evidence_path = File.join(@root, relative_path)
        unless File.file?(evidence_path)
          raise ResolutionError, "missing release evidence artifact: #{relative_path}"
        end
        unless Digest::SHA256.file(evidence_path).hexdigest == entry.fetch("sha256")
          raise ResolutionError, "release evidence artifact hash mismatch: #{relative_path}"
        end
      end

      declared_paths = listed_paths + authored_paths + evidence_paths
      OTHER_RELEASE_GROUP_PATHS.each do |group, expected_paths|
        artifacts = Array(@release_snapshot_manifest.fetch(group))
        paths = artifacts.map { |entry| entry.fetch("artifact_path") }
        unless paths.sort == expected_paths.sort && paths.uniq.length == expected_paths.length
          raise ResolutionError, "#{group} manifest is incomplete"
        end
        artifacts.each do |entry|
          relative_path = entry.fetch("artifact_path")
          if relative_path.start_with?("/") || relative_path.split("/").include?("..")
            raise ResolutionError, "invalid release artifact path: #{relative_path}"
          end
          artifact_path = File.join(@root, relative_path)
          unless File.file?(artifact_path) && Digest::SHA256.file(artifact_path).hexdigest == entry.fetch("sha256")
            raise ResolutionError, "#{group} artifact hash mismatch: #{relative_path}"
          end
        end
        declared_paths.concat(paths)
      end
      declared_paths << "references/release-snapshot-manifest.yaml"
      unless declared_paths.uniq.length == declared_paths.length
        raise ResolutionError, "release package has duplicate artifact paths"
      end
      actual_paths = []
      Find.find(@root) do |path|
        next if path == @root

        relative_path = Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
        stat = File.lstat(path)
        raise ResolutionError, "symlink in release package: #{relative_path}" if stat.symlink?
        actual_paths << relative_path if stat.file?
      end
      unless actual_paths.sort == declared_paths.sort
        raise ResolutionError, "release package file inventory mismatch"
      end
    rescue KeyError => error
      raise ResolutionError, "malformed release snapshot manifest: #{error.message}"
    end

    def validate_phase4c_contract!
      expected_contract_id = "tarot-visual-canon-runtime-integration.phase4c.v1"
      unless @phase4c_contract.fetch("contract_id") == expected_contract_id
        raise ResolutionError, "Phase 4C contract ID mismatch"
      end
      unless @phase4c_contract.fetch("status") == "frozen"
        raise ResolutionError, "Phase 4C contract is not frozen"
      end

      gate = @phase4c_contract.fetch("freeze_gate")
      expected_gate_values = {
        "required_card_count" => 78,
        "actual_card_count" => 78,
        "required_unique_canonical_ids" => 78,
        "actual_unique_canonical_ids" => 78,
        "required_source_bound_records" => 78,
        "actual_source_bound_records" => 78,
        "required_frozen_reference_resolutions" => 8,
        "actual_frozen_reference_resolutions" => 8,
        "required_direct_phase4b_resolutions" => 70,
        "actual_direct_phase4b_resolutions" => 70,
        "required_regression_suites" => 6,
        "actual_regression_suites" => 6
      }
      expected_gate_values.each do |field, expected|
        unless gate.fetch(field) == expected
          raise ResolutionError, "Phase 4C freeze gate mismatch: #{field}"
        end
      end
      unless gate.fetch("status") == "pass"
        raise ResolutionError, "Phase 4C freeze gate is not pass"
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Phase 4C contract: #{error.message}"
    end

    def validate_record!(card_id, record)
      unless @registry_ids.include?(card_id)
        raise ResolutionError, "Phase 4B record has unknown canonical card_id: #{card_id}"
      end
      unless record.fetch("factual_visual_id") == "rws.factual.#{card_id}"
        raise ResolutionError, "factual_visual_id mismatch for #{card_id}"
      end

      expected_source = "runtime/phase4a/rws-visual-source-manifest.yaml##{card_id}"
      unless record.fetch("canonical_source_ref") == expected_source && @manifest_by_id.key?(card_id)
        raise ResolutionError, "source binding mismatch for #{card_id}"
      end

      status = record.fetch("review_status")
      unless %w[reviewed phase4a_frozen_reference].include?(status)
        raise ResolutionError, "unsupported review_status for #{card_id}: #{status}"
      end

      if status == "phase4a_frozen_reference"
        unless record.fetch("phase4a_recheck_ref") == "runtime/phase4a/visual-pilot-rechecks.yaml##{card_id}"
          raise ResolutionError, "missing or mismatched Phase 4A recheck reference for #{card_id}"
        end
        recheck = @recheck_by_id[card_id]
        raise ResolutionError, "missing Phase 4A recheck for #{card_id}" unless recheck
        unless recheck.fetch("canonical_source_ref") == expected_source
          raise ResolutionError, "Phase 4A recheck source drift for #{card_id}"
        end
        validate_observation!(observation_for_recheck(recheck), card_id)
      else
        if record["phase4a_recheck_ref"] && !record["phase4a_recheck_ref"].to_s.empty?
          raise ResolutionError, "direct Phase 4B record unexpectedly references a Phase 4A recheck: #{card_id}"
        end
        validate_observation!(record, card_id)
      end
    end

    def validate_observation!(container, card_id)
      OBSERVATION_FIELDS.each do |field|
        unless container.key?(field) || (container["observations"].is_a?(Hash) && container["observations"].key?(field))
          raise ResolutionError, "missing required observation field #{field} for #{card_id}"
        end
      end
    end

    def observation_for(record)
      if record.fetch("review_status") == "phase4a_frozen_reference"
        observation_for_recheck(@recheck_by_id.fetch(record.fetch("card_id")))
      else
        record.fetch("observations").merge("unresolved_visuals" => record.fetch("unresolved_visuals"))
      end
    end

    def observation_for_recheck(recheck)
      recheck.fetch("observations").merge("unresolved_visuals" => recheck.fetch("unresolved_visuals"))
    end

    def build_alias_index
      aliases = Hash.new { |hash, key| hash[key] = [] }
      @registry_cards.each do |card|
        card_id = card.fetch("canonical_card_id")
        names = [card_id] + Array(card.fetch("display_names"))
        names.each do |name|
          key = normalize(name)
          aliases[key] << card_id unless aliases[key].include?(card_id)
        end
      end
      aliases
    end

    def require_count_and_unique(ids, expected, label)
      unless ids.length == expected
        raise ResolutionError, "#{label} count #{ids.length}, expected #{expected}"
      end
      unless ids.uniq.length == expected
        raise ResolutionError, "#{label} are not unique"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  selectors = ARGV
  if selectors.empty?
    warn "usage: ruby scripts/query_visual_facts.rb CARD_ID [CARD_ID ...]"
    exit 2
  end

  begin
    loader = TarotReaderRelease::VisualFacts.new
    packets = selectors.map { |selector| loader.packet(selector) }
    puts JSON.pretty_generate(packets.length == 1 ? packets.first : packets)
  rescue TarotReaderRelease::ResolutionError => error
    warn "visual query failed closed: #{error.message}"
    exit 1
  end
end

#!/usr/bin/env ruby

require "json"
require "digest"
require "optparse"
require "yaml"

require_relative "query_visual_facts"
require_relative "query_dictionary_reference"

module TarotReaderRelease
  class TeacherEvidence
    RELEASE_ID = "tarot-reader.stage10.v1.4".freeze
    RELEASE_STATUS = "frozen".freeze
    EVIDENCE_ROOT = "references/teacher-evidence".freeze
    UNIT_FILES = {
      "daniel" => "references/teacher-evidence/daniel-card-units.yaml",
      "dawn" => "references/teacher-evidence/dawn-court-units.yaml",
      "greer" => "references/teacher-evidence/greer-reversal-units.yaml",
      "nichols" => "references/teacher-evidence/nichols-amplification-units.yaml"
    }.freeze
    ALLOWED_REVIEW_STATUS = %w[
      manually_reviewed_rendered_page
      manually_reviewed_rendered_pages
      normalized_from_substantive_reviewed_anchor
      manually_reviewed_authored_chapter_model
    ].freeze
    RESULT_FIELDS = %w[
      unit_id
      teacher
      canonical_card_id
      capability
      orientation_scope
      condensed_evidence
      author_interpretation
      limitations
      source_ref
      review_status
      evidence_detail
    ].freeze
    SOURCE_REF_FIELDS = %w[source_book_id source_pages source_excerpt_ids source_quality visual_review_status].freeze
    UNIT_META_FIELDS = %w[
      unit_id teacher canonical_card_id capability orientation_scope limitations source_pages
      source_excerpt_ids review_status source_quality visual_review_note
    ].freeze
    DETAIL_FIELDS = {
      "daniel" => %w[meaning_candidates process_or_tension example_manifestations author_visual_narrative author_interpretation],
      "dawn_court_ontology" => %w[rank_function archetype_name observable_behaviors action_bridge suit_expression strengths shadow_or_failure_modes identity_limits relationship_manifestations work_or_social_manifestations],
      "dawn_rank_function" => %w[rank rank_function functional_bridge],
      "greer" => %w[upright_baseline reversal_anchor reversal_mechanism_candidates context_switches counterevidence alternatives],
      "nichols" => %w[transferable_method author_specific_amplification polarity evidence_bridge projection_warning alternative deck_specific_material]
    }.freeze
    DETAIL_ARRAY_FIELDS = %w[
      meaning_candidates author_interpretation observable_behaviors strengths shadow_or_failure_modes
      identity_limits relationship_manifestations work_or_social_manifestations
      reversal_mechanism_candidates context_switches counterevidence alternatives
    ].freeze
    NICHOLS_SELECTION_FIELDS = %w[trigger reason_anchor focus_anchor].freeze

    CAPABILITIES = {
      "daniel" => ["daniel", "daniel_card_narrative"],
      "dawn" => ["dawn", "dawn_court_ontology", "dawn_rank_function"],
      "greer" => ["greer", "greer_reversal_mechanism"],
      "nichols" => ["nichols", "nichols_major_amplification"],
      "dictionary" => ["dictionary", "dictionary_late_manifestation"]
    }.freeze
    SOURCE_BOOK_IDS = {
      "daniel" => "daniel_16_lessons_zh",
      "dawn" => "dawn_court_zh",
      "greer" => "greer_reversals_zh",
      "nichols" => "nichols_jung_tarot_en"
    }.freeze
    NICHOLS_TRIGGERS = %w[motif progression projection polarity archetypal_amplification].freeze
    NICHOLS_REASON_FIELDS = {
      "motif" => %w[transferable_method evidence_bridge],
      "progression" => %w[author_specific_amplification evidence_bridge],
      "projection" => %w[projection_warning],
      "polarity" => %w[polarity],
      "archetypal_amplification" => %w[author_specific_amplification]
    }.freeze
    NICHOLS_FOCUS_UNIT_FIELDS = %w[
      transferable_method author_specific_amplification polarity evidence_bridge projection_warning alternative
    ].freeze
    NICHOLS_VISUAL_FIELDS = %w[scene figures action gaze_and_facing spatial_relations objects].freeze
    GREER_GENERAL_FRAMEWORK_PAGES = (58..63).to_a.freeze
    GREER_COVERAGE_GAP_IDS = %w[
      wands_page wands_knight cups_page cups_knight swords_page swords_knight
      pentacles_page pentacles_knight
    ].freeze
    GREER_GENERAL_FRAMEWORK_CANDIDATES = %w[
      blockage_or_resistance delay_or_difficulty internalization projection
      excess_or_compensation misuse_or_misdirection absence_or_non_upright
    ].freeze

    def initialize(root: File.expand_path("..", __dir__))
      @root = File.expand_path(root)
      @visual_loader = VisualFacts.new(root: @root)
      @dictionary_loader = DictionaryReferences.new(root: @root)
      @manifest = load_yaml("references/release-snapshot-manifest.yaml")
      @provenance = load_yaml("#{EVIDENCE_ROOT}/provenance.yaml")
      @units = {}
      validate_manifest!
      load_and_validate_units!
    end

    def query(selector: nil, teacher: nil, capability: nil, orientation: "unspecified", domain: nil,
              hypothesis: nil, retrieval_reason: nil, focus: nil, nichols_trigger: nil,
              reason_anchor: nil, focus_anchor: nil, rank: nil)
      resolved_teacher, resolved_capability = resolve_route(teacher, capability)
      if resolved_teacher == "dictionary"
        return query_dictionary(selector, orientation, domain, hypothesis, retrieval_reason)
      end

      normalized_orientation = normalize_orientation(orientation)
      if resolved_teacher == "greer" && normalized_orientation != "reversed"
        raise ResolutionError, "Greer lookup requires explicit reversed orientation"
      end
      if selector.nil? && resolved_capability != "dawn_rank_function"
        raise ResolutionError, "card selector is required for card-scoped Teacher evidence"
      end

      canonical_id = selector.nil? ? nil : @visual_loader.resolve_selector(selector)
      selection = nil
      if resolved_teacher == "nichols"
        unit = @units.fetch("nichols").find { |entry| entry.fetch("canonical_card_id") == canonical_id }
        raise ResolutionError, "no Nichols evidence unit for #{canonical_id}" unless unit
        selection = validate_nichols_gate!(hypothesis, retrieval_reason, focus, nichols_trigger, reason_anchor, focus_anchor, unit, canonical_id)
      end
      candidates = @units.values.flatten.select do |unit|
        unit.fetch("teacher") == resolved_teacher && unit.fetch("capability") == resolved_capability &&
          (canonical_id.nil? || unit["canonical_card_id"] == canonical_id) &&
          (rank.nil? || unit["rank"] == rank)
      end
      if candidates.empty?
        raise ResolutionError, "no Teacher evidence unit for #{resolved_teacher}/#{resolved_capability}/#{canonical_id || rank}"
      end
      if candidates.length > 1 && canonical_id
        raise ResolutionError, "duplicate Teacher evidence unit for #{canonical_id}/#{resolved_capability}"
      end

      candidates.map do |unit|
        if resolved_teacher == "greer" && greer_card_entry_gap?(unit)
          greer_framework_fallback_for(unit)
        else
          result_for(unit, normalized_orientation, selection)
        end
      end
    end

    private

    def load_yaml(relative_path)
      YAML.load_file(File.join(@root, relative_path))
    rescue Errno::ENOENT => error
      raise ResolutionError, "missing Teacher evidence artifact: #{relative_path} (#{error.message})"
    rescue Psych::Exception => error
      raise ResolutionError, "invalid Teacher evidence YAML: #{relative_path} (#{error.message})"
    end

    def validate_manifest!
      unless @manifest.fetch("release_id") == RELEASE_ID && @manifest.fetch("status") == RELEASE_STATUS
        raise ResolutionError, "Teacher evidence release identity/status mismatch"
      end
      artifacts = Array(@manifest.fetch("teacher_evidence_artifacts"))
      expected = (UNIT_FILES.values + ["references/teacher-evidence/provenance.yaml", "scripts/query_teacher_evidence.rb", "scripts/build_teacher_evidence.rb"]).sort
      actual = artifacts.map { |entry| entry.fetch("artifact_path") }.sort
      unless actual == expected && actual.uniq.length == expected.length
        raise ResolutionError, "Teacher evidence artifact manifest is not closed"
      end
      artifacts.each do |entry|
        path = entry.fetch("artifact_path")
        if path.start_with?("/") || path.include?("..") || !path.start_with?(EVIDENCE_ROOT) && !path.start_with?("scripts/")
          raise ResolutionError, "invalid Teacher evidence artifact path: #{path}"
        end
        unless entry.fetch("canonical_snapshot") == false
          raise ResolutionError, "Teacher evidence artifact must not be canonical: #{path}"
        end
        file_path = File.join(@root, path)
        unless File.file?(file_path) && Digest::SHA256.file(file_path).hexdigest == entry.fetch("sha256")
          raise ResolutionError, "Teacher evidence artifact hash mismatch: #{path}"
        end
      end
      unless @provenance.fetch("release_id") == RELEASE_ID && @provenance.fetch("status") == RELEASE_STATUS
        raise ResolutionError, "Teacher evidence provenance identity/status mismatch"
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Teacher evidence manifest: #{error.message}"
    end

    def load_and_validate_units!
      UNIT_FILES.each do |teacher, path|
        document = load_yaml(path)
        unless document.fetch("teacher") == teacher
          raise ResolutionError, "Teacher unit file teacher mismatch: #{path}"
        end
        entries = Array(document.fetch("units"))
        expected_count = document.fetch("unit_count", document.fetch("court_unit_count", entries.length))
        if entries.length != expected_count
          raise ResolutionError, "Teacher unit count mismatch: #{path}"
        end
        @units[teacher] = entries
        entries.each { |entry| validate_unit!(entry, teacher) }
        if teacher == "dawn"
          rank_units = Array(document.fetch("rank_units"))
          unless rank_units.length == document.fetch("rank_unit_count")
            raise ResolutionError, "Dawn rank unit count mismatch"
          end
          rank_units.each { |entry| validate_rank_unit!(entry) }
          @units[teacher] += rank_units
        end
      end
      all_ids = @units.values.flatten.map { |entry| entry.fetch("unit_id") }
      unless all_ids.uniq.length == all_ids.length
        raise ResolutionError, "Teacher evidence unit IDs are not unique"
      end
      actual_gaps = @units.fetch("greer").select { |unit| greer_card_entry_gap?(unit) }
                             .map { |unit| unit.fetch("canonical_card_id") }
      unless actual_gaps.sort == GREER_COVERAGE_GAP_IDS.sort
        raise ResolutionError, "Greer coverage gap drift"
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Teacher evidence unit: #{error.message}"
    end

    def validate_unit!(unit, teacher)
      validate_unit_fields!(unit)
      unless unit.fetch("teacher") == teacher && ALLOWED_REVIEW_STATUS.include?(unit.fetch("review_status"))
        raise ResolutionError, "unsupported Teacher review status or teacher mismatch: #{unit["unit_id"]}"
      end
      card_id = unit.fetch("canonical_card_id")
      resolved = @visual_loader.resolve_selector(card_id)
      raise ResolutionError, "Teacher canonical ID drift: #{card_id}" unless resolved == card_id
      unless unit.fetch("source_pages").is_a?(Array) && !unit.fetch("source_pages").empty? &&
             unit.fetch("source_excerpt_ids").is_a?(Array) && !unit.fetch("source_excerpt_ids").empty?
        raise ResolutionError, "missing Teacher provenance: #{unit.fetch("unit_id")}"
      end
      validate_source_provenance!(unit, teacher)
      unless unit.fetch("limitations").is_a?(Array) && !unit.fetch("limitations").empty?
        raise ResolutionError, "missing Teacher limitations: #{unit.fetch("unit_id")}"
      end
      if teacher == "greer" && unit.fetch("orientation_scope") != "reversed_only"
        raise ResolutionError, "Greer unit is not reversal scoped: #{unit.fetch("unit_id")}"
      end
      if teacher == "greer" && !greer_card_entry_gap?(unit) &&
         (unit.fetch("reversal_anchor").strip.empty? || unit.fetch("reversal_mechanism_candidates").empty?)
        raise ResolutionError, "incomplete Greer reversal evidence: #{unit.fetch("unit_id")}"
      end
      if teacher == "daniel" && unit.fetch("orientation_scope") != "upright_baseline"
        raise ResolutionError, "Daniel unit is not upright baseline scoped: #{unit.fetch("unit_id")}"
      end
      if teacher == "nichols" && unit.fetch("evidence_bridge").to_s.strip.empty?
        raise ResolutionError, "Nichols unit is missing an evidence bridge: #{unit.fetch("unit_id")}"
      end
    end

    def validate_rank_unit!(unit)
      validate_unit_fields!(unit)
      unless unit.fetch("teacher") == "dawn" && unit.fetch("capability") == "dawn_rank_function" &&
             unit["canonical_card_id"].nil? && ALLOWED_REVIEW_STATUS.include?(unit.fetch("review_status"))
        raise ResolutionError, "malformed Dawn rank unit: #{unit["unit_id"]}"
      end
      validate_source_provenance!(unit, "dawn")
    end

    def detail_fields_for(unit)
      DETAIL_FIELDS.fetch(unit.fetch("teacher") == "dawn" ? unit.fetch("capability") : unit.fetch("teacher"))
    end

    def validate_unit_fields!(unit)
      detail_fields = detail_fields_for(unit)
      optional = unit.fetch("teacher") == "nichols" ? %w[source_page_support] : []
      allowed = UNIT_META_FIELDS + detail_fields + optional
      unless (unit.keys - allowed).empty? && (detail_fields - unit.keys).empty?
        raise ResolutionError, "Teacher unit field whitelist violation: #{unit.fetch("unit_id")}"
      end
      detail_fields.each do |field|
        value = unit.fetch(field)
        valid = if field == "reversal_mechanism_candidates"
                  value.is_a?(Array) && value.all? do |item|
                    item.is_a?(Hash) && item.keys.sort == %w[mechanism text_signals] &&
                      item.fetch("mechanism").is_a?(String) && item.fetch("text_signals").is_a?(Array) &&
                      item.fetch("text_signals").all? { |signal| signal.is_a?(String) }
                  end
                elsif DETAIL_ARRAY_FIELDS.include?(field)
                  value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
                else
                  value.is_a?(String)
                end
        raise ResolutionError, "invalid Teacher detail field: #{field}" unless valid
      end
      return unless unit.key?("source_page_support")
      support = unit.fetch("source_page_support")
      unless support.is_a?(Hash) && support.keys.sort == unit.fetch("source_pages").map(&:to_s).sort &&
             support.values.all? { |value| value.is_a?(String) }
        raise ResolutionError, "invalid Nichols source page support"
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Teacher unit field: #{error.message}"
    end

    def validate_source_provenance!(unit, teacher)
      book_id = SOURCE_BOOK_IDS.fetch(teacher)
      source = Array(@provenance.fetch("sources")).find { |entry| entry.fetch("book_id") == book_id }
      if source.nil?
        raise ResolutionError, "missing Teacher source provenance: #{book_id}"
      end
      source_hashes = source.fetch("sha256")
      if source_hashes.empty? || source_hashes.any? { |_key, value| value.to_s.strip.empty? }
        raise ResolutionError, "incomplete Teacher source hashes: #{book_id}"
      end
      pages = unit.fetch("source_pages")
      excerpts = unit.fetch("source_excerpt_ids")
      unless pages.all? { |page| page.is_a?(Integer) && page.positive? } && excerpts.uniq.length == excerpts.length
        raise ResolutionError, "invalid Teacher source locator: #{unit.fetch("unit_id")}"
      end
      expected_prefix = "#{book_id}."
      unless excerpts.all? { |excerpt_id| excerpt_id.to_s.start_with?(expected_prefix) }
        raise ResolutionError, "Teacher source excerpt drift: #{unit.fetch("unit_id")}"
      end
      if %w[daniel nichols].include?(teacher)
        locator_index = @provenance.fetch("excerpt_locator_index").fetch(book_id)
        pages.zip(excerpts).each do |page, excerpt_id|
          locator = locator_index.fetch(excerpt_id) do
            raise ResolutionError, "Teacher excerpt is not in reviewed locator index: #{excerpt_id}"
          end
          unless locator.fetch("pdf_page") == page && locator.fetch("canonical_card_id") == unit.fetch("canonical_card_id")
            raise ResolutionError, "Teacher excerpt/page/card binding drift: #{unit.fetch("unit_id")}"
          end
        end
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Teacher source provenance: #{error.message}"
    end

    def resolve_route(teacher, capability)
      t = teacher.to_s.strip.downcase
      c = capability.to_s.strip.downcase
      if t.empty? && c.empty?
        raise ResolutionError, "teacher or capability is required"
      end
      if !t.empty? && !UNIT_FILES.key?(t) && t != "dictionary"
        raise ResolutionError, "unsupported Teacher: #{teacher}"
      end
      if !c.empty?
        matching = CAPABILITIES.select { |_key, values| values.include?(c) }.keys
        raise ResolutionError, "unsupported capability: #{capability}" if matching.empty?
        if !t.empty? && !matching.include?(t)
          raise ResolutionError, "Teacher capability permission mismatch"
        end
        t = matching.first if t.empty?
        c = case matching.first
            when "daniel" then "daniel_card_narrative"
            when "dawn" then (c == "dawn_rank_function" ? c : "dawn_court_ontology")
            when "greer" then "greer_reversal_mechanism"
            when "nichols" then "nichols_major_amplification"
            when "dictionary" then "dictionary_late_manifestation"
            end
      else
        c = case t
            when "daniel" then "daniel_card_narrative"
            when "dawn" then "dawn_court_ontology"
            when "greer" then "greer_reversal_mechanism"
            when "nichols" then "nichols_major_amplification"
            when "dictionary" then "dictionary_late_manifestation"
            end
      end
      [t, c]
    end

    def normalize_orientation(value)
      normalized = value.to_s.strip.downcase
      unless %w[unspecified upright reversed].include?(normalized)
        raise ResolutionError, "unsupported orientation: #{value}"
      end
      normalized
    end

    def validate_nichols_gate!(hypothesis, reason, focus, trigger, reason_anchor, focus_anchor, unit, canonical_id)
      {"hypothesis" => hypothesis, "reason" => reason, "focus" => focus}.each do |label, value|
        if value.to_s.strip.empty?
          raise ResolutionError, "Nichols lookup requires non-empty #{label} context"
        end
      end

      trigger = trigger.to_s.strip.downcase
      unless NICHOLS_TRIGGERS.include?(trigger)
        raise ResolutionError, "Nichols lookup requires an explicit supported trigger"
      end
      reason_field = resolve_nichols_unit_anchor!(reason_anchor, unit, NICHOLS_REASON_FIELDS.fetch(trigger))
      focus_value = resolve_nichols_focus_anchor!(focus_anchor, unit, canonical_id)
      if reason_anchor.to_s.strip == focus_anchor.to_s.strip
        raise ResolutionError, "Nichols reason and focus must select distinct evidence fields"
      end
      if reason_field.to_s.strip.empty? || focus_value.to_s.strip.empty?
        raise ResolutionError, "Nichols evidence selections must point to non-empty source fields"
      end
      {"trigger" => trigger, "reason_anchor" => reason_anchor.to_s.strip, "focus_anchor" => focus_anchor.to_s.strip}
    end

    def resolve_nichols_unit_anchor!(selector, unit, allowed_fields)
      source, field = parse_nichols_anchor(selector)
      unless source == "unit" && allowed_fields.include?(field)
        raise ResolutionError, "Nichols reason anchor does not match the declared trigger"
      end
      value = unit[field]
      raise ResolutionError, "Nichols reason anchor is absent from the selected unit" if value.nil? || value.to_s.strip.empty?
      value
    end

    def resolve_nichols_focus_anchor!(selector, unit, canonical_id)
      source, field = parse_nichols_anchor(selector)
      case source
      when "unit"
        unless NICHOLS_FOCUS_UNIT_FIELDS.include?(field)
          raise ResolutionError, "unsupported Nichols unit focus anchor"
        end
        value = unit[field]
      when "visual"
        unless NICHOLS_VISUAL_FIELDS.include?(field)
          raise ResolutionError, "unsupported Nichols visual focus anchor"
        end
        value = @visual_loader.packet(canonical_id)[field]
      else
        raise ResolutionError, "unsupported Nichols focus evidence source"
      end
      raise ResolutionError, "Nichols focus anchor is absent from the selected source" if value.nil? || value.to_s.strip.empty?
      value
    end

    def parse_nichols_anchor(selector)
      match = selector.to_s.strip.match(/\A(unit|visual):([a-z_]+)\z/)
      raise ResolutionError, "Nichols evidence anchor must be an explicit unit:<field> or visual:<field> selector" unless match
      [match[1], match[2]]
    end

    def query_dictionary(selector, orientation, domain, hypothesis, reason)
      if orientation.to_s.strip.downcase == "unspecified"
        raise ResolutionError, "Dictionary lookup requires explicit upright or reversed orientation"
      end
      results = @dictionary_loader.query(selector: selector, orientation: orientation, domain: domain,
                                         hypothesis: hypothesis, retrieval_reason: reason)
      results.map do |entry|
        result = {
          "unit_id" => entry.fetch("entry_id"), "teacher" => "dictionary",
          "canonical_card_id" => entry.fetch("canonical_card_id"), "capability" => "dictionary_late_manifestation",
          "orientation_scope" => entry.fetch("orientation"), "condensed_evidence" => entry.fetch("condensed_statement"),
          "author_interpretation" => [], "limitations" => ["仅覆盖已复核的 22 个 units；未覆盖条目 fail-closed。", "必须已有 holistic hypothesis 和 retrieval reason。"],
          "source_ref" => {"source_book_id" => "tarot_dictionary_zh", "source_pages" => entry.fetch("source_ref").fetch("pdf_pages"),
                           "source_excerpt_ids" => entry.fetch("source_ref").fetch("source_excerpt_ids"),
                           "source_quality" => "manually_reviewed_single_column", "visual_review_status" => entry.fetch("source_ref").fetch("review_status")},
          "review_status" => "manually_reviewed_single_column", "evidence_detail" => {"domain" => entry.fetch("domain"), "content_type" => entry.fetch("content_type")}
        }
        enforce_result_whitelist!(result)
      end
    end

    def result_for(unit, orientation, selection = nil)
      if unit.fetch("teacher") == "greer" && orientation != "reversed"
        raise ResolutionError, "Greer lookup requires explicit reversed orientation"
      end
      if unit.fetch("teacher") == "daniel" && orientation == "reversed"
        # Daniel is returned only as the comparison baseline for a real reversal.
        orientation_scope = "upright_baseline_comparison"
      elsif unit.fetch("teacher") == "daniel" && orientation == "unspecified"
        # No direction is inferred; the baseline is explicitly marked as such.
        orientation_scope = "upright_baseline_for_unspecified_orientation"
      else
        orientation_scope = unit.fetch("orientation_scope")
      end
      result = {
        "unit_id" => unit.fetch("unit_id"), "teacher" => unit.fetch("teacher"),
        "canonical_card_id" => unit.fetch("canonical_card_id"), "capability" => unit.fetch("capability"),
        "orientation_scope" => orientation_scope,
        "condensed_evidence" => condensed_evidence(unit),
        "author_interpretation" => author_interpretation(unit),
        "limitations" => unit.fetch("limitations"),
        "source_ref" => {"source_book_id" => SOURCE_BOOK_IDS.fetch(unit.fetch("teacher")), "source_pages" => unit.fetch("source_pages"),
                          "source_excerpt_ids" => unit.fetch("source_excerpt_ids"), "source_quality" => unit.fetch("source_quality"),
                          "visual_review_status" => unit.fetch("review_status")},
        "review_status" => unit.fetch("review_status"),
        "evidence_detail" => detail_for(unit, selection)
      }
      enforce_result_whitelist!(result)
    end

    def greer_card_entry_gap?(unit)
      unit.fetch("reversal_anchor").strip.empty? &&
        unit.fetch("reversal_mechanism_candidates").empty? &&
        unit.fetch("context_switches").empty? && unit.fetch("alternatives").empty?
    end

    def greer_framework_fallback_for(unit)
      card_id = unit.fetch("canonical_card_id")
      pages = GREER_GENERAL_FRAMEWORK_PAGES
      excerpt_ids = pages.map { |page| format("greer_reversals_zh.ex%04d", page) }
      index = @provenance.fetch("excerpt_locator_index").fetch("greer_reversals_zh")
      pages.zip(excerpt_ids).each do |page, excerpt_id|
        locator = index.fetch(excerpt_id)
        unless locator.fetch("pdf_page") == page && locator.fetch("scope") == "general_reversal_framework"
          raise ResolutionError, "Greer general-framework provenance drift: #{excerpt_id}"
        end
      end
      result = {
        "unit_id" => "greer.general_framework.#{card_id}.fallback",
        "teacher" => "greer", "canonical_card_id" => card_id,
        "capability" => "greer_general_mechanism_framework", "orientation_scope" => "reversed_only",
        "condensed_evidence" => "该牌逐牌逆位机制未形成实质证据；Greer 通用框架仅提供未选定的机制候选，必须由问题、牌位、邻牌和现实观察筛选。",
        "author_interpretation" => [],
        "limitations" => [
          "coverage_fallback；不是这张牌的逐牌逆位释义，不得将任一候选直接写成主判断。",
          "框架来自冻结的 Greer Book Model 与原书通用方法页；牌的正位基线仍需独立核对。"
        ],
        "source_ref" => {
          "source_book_id" => "greer_reversals_zh", "source_pages" => pages,
          "source_excerpt_ids" => excerpt_ids,
          "source_quality" => "reviewed_book_model_general_framework",
          "visual_review_status" => "coverage_fallback"
        },
        "review_status" => "coverage_fallback",
        "evidence_detail" => {
          "upright_baseline" => unit.fetch("upright_baseline"),
          "reversal_anchor" => "未提供逐牌逆位机制",
          "reversal_mechanism_candidates" => [],
          "context_switches" => ["先由问题、牌位、邻牌与可观察现实缩小候选；没有收敛证据时保持 unresolved。"],
          "counterevidence" => ["不能把通用候选当作本牌的已核实逆位事实。"],
          "alternatives" => GREER_GENERAL_FRAMEWORK_CANDIDATES
        }
      }
      enforce_result_whitelist!(result)
    rescue KeyError => error
      raise ResolutionError, "missing Greer general-framework provenance: #{error.message}"
    end

    def condensed_evidence(unit)
      case unit.fetch("teacher")
      when "daniel"
        [unit.fetch("meaning_candidates").join("、"), unit.fetch("process_or_tension"), unit.fetch("example_manifestations")].join("；")
      when "dawn"
        if unit.fetch("capability") == "dawn_rank_function"
          [unit.fetch("rank_function"), unit.fetch("functional_bridge")].join("；")
        else
          [unit.fetch("rank_function"), unit.fetch("archetype_name"), unit.fetch("observable_behaviors").join("、"), unit.fetch("action_bridge")].join("；")
        end
      when "greer"
        [unit.fetch("upright_baseline"), unit.fetch("reversal_anchor")].join("；")
      when "nichols"
        [unit.fetch("transferable_method"), unit.fetch("author_specific_amplification"), unit.fetch("polarity")].join("；")
      else
        raise ResolutionError, "unsupported Teacher evidence teacher"
      end
    end

    def author_interpretation(unit)
      case unit.fetch("teacher")
      when "daniel" then unit.fetch("author_interpretation")
      when "dawn" then unit.fetch("capability") == "dawn_rank_function" ? [] : [unit.fetch("archetype_name")]
      when "greer" then [unit.fetch("reversal_anchor")]
      when "nichols" then [unit.fetch("author_specific_amplification")]
      else []
      end
    end

    def detail_for(unit, selection)
      detail = detail_fields_for(unit).to_h { |field| [field, unit.fetch(field)] }
      detail["source_page_support"] = unit.fetch("source_page_support") if unit.key?("source_page_support")
      detail["retrieval_selection"] = selection if selection
      detail
    end

    def enforce_result_whitelist!(result)
      unless result.keys.sort == RESULT_FIELDS.sort
        raise ResolutionError, "Teacher evidence result field whitelist violation"
      end
      unless result.fetch("source_ref").keys.sort == SOURCE_REF_FIELDS.sort
        raise ResolutionError, "Teacher source reference field whitelist violation"
      end
      source = result.fetch("source_ref")
      unless %w[source_book_id source_quality visual_review_status].all? { |field| source.fetch(field).is_a?(String) } &&
             source.fetch("source_pages").is_a?(Array) && source.fetch("source_pages").all? { |page| page.is_a?(Integer) } &&
             source.fetch("source_excerpt_ids").is_a?(Array) && source.fetch("source_excerpt_ids").all? { |id| id.is_a?(String) }
        raise ResolutionError, "invalid Teacher source reference values"
      end
      detail = result.fetch("evidence_detail")
      allowed = if result.fetch("teacher") == "dictionary"
                  %w[domain content_type]
                else
                  unit_key = result.fetch("teacher") == "dawn" ? result.fetch("capability") : result.fetch("teacher")
                  DETAIL_FIELDS.fetch(unit_key) + (result.fetch("teacher") == "nichols" ? %w[source_page_support retrieval_selection] : [])
                end
      unless (detail.keys - allowed).empty? && (result.fetch("teacher") == "dictionary" || (DETAIL_FIELDS.fetch(result.fetch("teacher") == "dawn" ? result.fetch("capability") : result.fetch("teacher")) - detail.keys).empty?)
        raise ResolutionError, "Teacher evidence detail field whitelist violation"
      end
      if result.fetch("teacher") == "nichols"
        selection = detail.fetch("retrieval_selection")
        unless selection.is_a?(Hash) && selection.keys.sort == NICHOLS_SELECTION_FIELDS.sort
          raise ResolutionError, "Nichols retrieval selection field whitelist violation"
        end
      end
      result
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { teacher: nil, capability: nil, orientation: "unspecified", domain: nil, hypothesis: nil, reason: nil,
              focus: nil, nichols_trigger: nil, reason_anchor: nil, focus_anchor: nil, rank: nil }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: ruby scripts/query_teacher_evidence.rb [CARD] --teacher TEACHER [options]"
    opts.on("--teacher TEACHER") { |value| options[:teacher] = value }
    opts.on("--capability CAPABILITY") { |value| options[:capability] = value }
    opts.on("--orientation ORIENTATION") { |value| options[:orientation] = value }
    opts.on("--domain DOMAIN") { |value| options[:domain] = value }
    opts.on("--hypothesis TEXT") { |value| options[:hypothesis] = value }
    opts.on("--reason TEXT", "human-readable retrieval reason; not semantically validated") { |value| options[:reason] = value }
    opts.on("--focus TEXT", "human-readable focus; not semantically validated") { |value| options[:focus] = value }
    opts.on("--nichols-trigger TYPE", "motif|progression|projection|polarity|archetypal_amplification") { |value| options[:nichols_trigger] = value }
    opts.on("--reason-anchor SELECTOR", "unit:<field> matching the declared Nichols trigger") { |value| options[:reason_anchor] = value }
    opts.on("--focus-anchor SELECTOR", "unit:<field> or visual:<field> for this card") { |value| options[:focus_anchor] = value }
    opts.on("--rank RANK") { |value| options[:rank] = value }
  end
  begin
    positional = parser.parse!(ARGV)
    raise TarotReaderRelease::ResolutionError, "Teacher evidence query accepts at most one card selector" if positional.length > 1
    selector = positional.first
    loader = TarotReaderRelease::TeacherEvidence.new
    results = loader.query(selector: selector, teacher: options[:teacher], capability: options[:capability],
                           orientation: options[:orientation], domain: options[:domain], hypothesis: options[:hypothesis],
                           retrieval_reason: options[:reason], focus: options[:focus], nichols_trigger: options[:nichols_trigger],
                           reason_anchor: options[:reason_anchor], focus_anchor: options[:focus_anchor], rank: options[:rank])
    puts JSON.pretty_generate(results)
  rescue TarotReaderRelease::ResolutionError => error
    warn "Teacher evidence query failed closed: #{error.message}"
    exit 1
  rescue OptionParser::ParseError => error
    warn "Teacher evidence query failed closed: #{error.message}"
    exit 2
  end
end

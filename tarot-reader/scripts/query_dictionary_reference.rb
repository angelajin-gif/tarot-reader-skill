#!/usr/bin/env ruby

require "json"
require "digest"
require "optparse"
require "yaml"

require_relative "query_visual_facts"

module TarotReaderRelease
  class DictionaryReferences
    RELEASE_ROOT = File.expand_path("..", __dir__).freeze
    UNIT_PATH = "references/dictionary-reference-units.yaml".freeze
    PROVENANCE_PATH = "references/dictionary-source-provenance.yaml".freeze
    PROVENANCE_REF = "references/dictionary-source-provenance.yaml#tarot_dictionary_zh.phase1e.visual-review-units.v1".freeze

    RESULT_FIELDS = %w[
      entry_id
      canonical_card_id
      orientation
      domain
      content_type
      condensed_statement
      source_ref
    ].freeze

    def initialize(root: RELEASE_ROOT, units_document: nil, provenance_document: nil)
      @root = File.expand_path(root)
      @visual_loader = VisualFacts.new(root: @root)
      @release_manifest = load_yaml("references/release-snapshot-manifest.yaml")
      @provenance = provenance_document || load_yaml(PROVENANCE_PATH)
      @units = units_document || load_yaml(UNIT_PATH)
      validate!
    end

    def query(selector:, orientation:, domain:, hypothesis: nil, retrieval_reason: nil)
      if hypothesis.to_s.strip.empty? || retrieval_reason.to_s.strip.empty?
        raise ResolutionError, "Dictionary lookup requires an existing hypothesis and retrieval reason"
      end

      canonical_id = @visual_loader.resolve_selector(selector)
      normalized_orientation = orientation.to_s.strip.downcase
      unless %w[upright reversed].include?(normalized_orientation)
        raise ResolutionError, "Dictionary lookup requires explicit upright or reversed orientation"
      end
      normalized_domain = domain.to_s.strip.downcase
      if normalized_domain.empty?
        raise ResolutionError, "Dictionary lookup requires an explicit domain"
      end

      matches = @entries.select do |entry|
        entry.fetch("canonical_card_id") == canonical_id &&
          entry.fetch("orientation") == normalized_orientation &&
          entry.fetch("domain") == normalized_domain
      end
      if matches.empty?
        raise ResolutionError, "no reviewed Dictionary unit for #{canonical_id}/#{normalized_orientation}/#{normalized_domain}"
      end

      matches.map { |entry| result_for(entry) }
    end

    private

    def load_yaml(relative_path)
      YAML.load_file(File.join(@root, relative_path))
    rescue Errno::ENOENT => error
      raise ResolutionError, "missing Dictionary release artifact: #{relative_path} (#{error.message})"
    rescue Psych::Exception => error
      raise ResolutionError, "invalid Dictionary release YAML: #{relative_path} (#{error.message})"
    end

    def validate!
      validate_derived_manifest!
      unless @units.fetch("provenance_ref") == PROVENANCE_REF
        raise ResolutionError, "Dictionary provenance reference mismatch"
      end
      unless @units.fetch("runtime_role") == "late_hypothesis_check_only"
        raise ResolutionError, "Dictionary units are not restricted to late hypothesis checks"
      end
      unless @units.fetch("status") == "frozen" && @provenance.fetch("status") == "frozen"
        raise ResolutionError, "Dictionary reference units are not frozen artifacts"
      end
      policy = @units.fetch("content_policy")
      %w[not_card_meaning not_visual_fact not_prediction not_professional_advice no_raw_ocr
         no_acceptance_notes no_expected_answers].each do |field|
        raise ResolutionError, "Dictionary content policy violation: #{field}" unless policy.fetch(field) == true
      end

      @entries = Array(@units.fetch("entries"))
      expected_count = @units.fetch("coverage").fetch("unit_count")
      unless @entries.length == expected_count
        raise ResolutionError, "Dictionary unit count #{@entries.length}, expected #{expected_count}"
      end
      entry_ids = @entries.map { |entry| entry.fetch("entry_id") }
      unless entry_ids.uniq.length == entry_ids.length
        raise ResolutionError, "Dictionary entry IDs are not unique"
      end
      card_ids = @entries.map { |entry| entry.fetch("canonical_card_id") }.uniq
      unless card_ids.length == @units.fetch("coverage").fetch("supported_cards")
        raise ResolutionError, "Dictionary supported-card count does not match units"
      end

      @entries.each { |entry| validate_entry!(entry) }
      true
    rescue KeyError => error
      raise ResolutionError, "malformed Dictionary release artifact: #{error.message}"
    end

    def validate_derived_manifest!
      artifacts = Array(@release_manifest.fetch("derived_reference_artifacts"))
      by_path = artifacts.to_h { |artifact| [artifact.fetch("artifact_path"), artifact] }
      [UNIT_PATH, PROVENANCE_PATH].each do |relative_path|
        artifact = by_path.fetch(relative_path)
        unless relative_path.start_with?("references/") && !relative_path.include?("..")
          raise ResolutionError, "invalid Dictionary artifact path: #{relative_path}"
        end
        unless artifact.fetch("canonical_snapshot") == false
          raise ResolutionError, "Dictionary derived artifact incorrectly marked canonical: #{relative_path}"
        end
        file_path = File.join(@root, relative_path)
        unless File.file?(file_path)
          raise ResolutionError, "missing Dictionary derived artifact: #{relative_path}"
        end
        unless Digest::SHA256.file(file_path).hexdigest == artifact.fetch("sha256")
          raise ResolutionError, "Dictionary derived artifact hash mismatch: #{relative_path}"
        end
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Dictionary release manifest: #{error.message}"
    end

    def validate_entry!(entry)
      card_id = entry.fetch("canonical_card_id")
      resolved = @visual_loader.resolve_selector(card_id)
      unless resolved == card_id
        raise ResolutionError, "Dictionary canonical ID was mutated: #{card_id}"
      end
      orientation = entry.fetch("orientation")
      unless %w[upright reversed].include?(orientation)
        raise ResolutionError, "unsupported Dictionary orientation for #{card_id}"
      end
      expected_entry_id = "tarot_dictionary_zh.#{card_id}.#{orientation}.#{entry.fetch("domain")}"
      unless entry.fetch("entry_id") == expected_entry_id
        raise ResolutionError, "Dictionary entry ID drift for #{card_id}"
      end
      unless entry.fetch("content_type") == @units.fetch("content_policy").fetch("content_type")
        raise ResolutionError, "Dictionary content type mismatch for #{card_id}"
      end
      unless entry.fetch("condensed_statement").to_s.strip.length >= 8
        raise ResolutionError, "empty Dictionary condensed statement for #{card_id}"
      end
      source_ref = entry.fetch("source_ref")
      unless source_ref.fetch("source_repo_path") == "reading/tarot_dictionary_zh/source-chunks.jsonl"
        raise ResolutionError, "Dictionary source path drift for #{card_id}"
      end
      excerpt_ids = Array(source_ref.fetch("source_excerpt_ids"))
      if excerpt_ids.empty? || excerpt_ids.any? { |id| id !~ /\Atarot_dictionary_zh\.p\d{4}\.b\d+\z/ }
        raise ResolutionError, "invalid Dictionary excerpt provenance for #{card_id}"
      end
      pages = Array(source_ref.fetch("pdf_pages"))
      if pages.empty? || pages.any? { |page| !page.is_a?(Integer) || page <= 0 }
        raise ResolutionError, "invalid Dictionary page provenance for #{card_id}"
      end
      reviewed_pages = Array(@provenance.fetch("manual_review").fetch("reviewed_pdf_pages"))
      unless pages.all? { |page| reviewed_pages.include?(page) }
        raise ResolutionError, "Dictionary page is outside the manual review scope for #{card_id}"
      end
      unless %w[left right].include?(source_ref.fetch("visual_column"))
        raise ResolutionError, "missing Dictionary single-column review for #{card_id}"
      end
      unless source_ref.fetch("entry_anchor_id") == entry.fetch("entry_id")
        raise ResolutionError, "Dictionary entry anchor drift for #{card_id}"
      end
      unless source_ref.fetch("review_status") == "manually_reviewed_single_column"
        raise ResolutionError, "unsupported Dictionary review status for #{card_id}"
      end
    rescue KeyError => error
      raise ResolutionError, "malformed Dictionary unit: #{error.message}"
    end

    def result_for(entry)
      source_ref = entry.fetch("source_ref")
      result = {
        "entry_id" => entry.fetch("entry_id"),
        "canonical_card_id" => entry.fetch("canonical_card_id"),
        "orientation" => entry.fetch("orientation"),
        "domain" => entry.fetch("domain"),
        "content_type" => entry.fetch("content_type"),
        "condensed_statement" => entry.fetch("condensed_statement"),
        "source_ref" => {
          "provenance" => PROVENANCE_REF,
          "source_repo_path" => source_ref.fetch("source_repo_path"),
          "source_excerpt_ids" => source_ref.fetch("source_excerpt_ids"),
          "pdf_pages" => source_ref.fetch("pdf_pages"),
          "visual_column" => source_ref.fetch("visual_column"),
          "entry_anchor_id" => source_ref.fetch("entry_anchor_id"),
          "review_status" => source_ref.fetch("review_status")
        }
      }
      unless result.keys.sort == RESULT_FIELDS.sort
        raise ResolutionError, "Dictionary result field whitelist violation"
      end
      result
    end
  end
end

if $PROGRAM_NAME == __FILE__
  options = { hypothesis: nil, retrieval_reason: nil }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: ruby scripts/query_dictionary_reference.rb CARD_ID ORIENTATION DOMAIN --hypothesis TEXT --reason TEXT"
    opts.on("--hypothesis TEXT", "existing holistic hypothesis") { |value| options[:hypothesis] = value }
    opts.on("--reason TEXT", "reason this late lookup is needed") { |value| options[:retrieval_reason] = value }
  end

  begin
    positional = parser.parse!(ARGV)
    unless positional.length == 3
      warn parser.banner
      exit 2
    end
    loader = TarotReaderRelease::DictionaryReferences.new
    results = loader.query(
      selector: positional[0],
      orientation: positional[1],
      domain: positional[2],
      hypothesis: options[:hypothesis],
      retrieval_reason: options[:retrieval_reason]
    )
    puts JSON.pretty_generate(results)
  rescue TarotReaderRelease::ResolutionError => error
    warn "Dictionary query failed closed: #{error.message}"
    exit 1
  rescue OptionParser::ParseError => error
    warn "Dictionary query failed closed: #{error.message}"
    exit 2
  end
end

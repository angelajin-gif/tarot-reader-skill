#!/usr/bin/env ruby

require "digest"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SKILL_ROOT = File.join(ROOT, "tarot-reader")
MANIFEST_PATH = File.join(SKILL_ROOT, "references", "release-snapshot-manifest.yaml")

def assert(condition, message)
  raise "public package verification failed: #{message}" unless condition
end

manifest = YAML.load_file(MANIFEST_PATH)
assert(manifest.fetch("release_id") == "tarot-reader.stage10.v1.1", "release identity mismatch")
assert(manifest.fetch("status") == "frozen", "release is not frozen")

groups = {
  "canonical snapshots" => manifest.fetch("entries").map { |entry| [entry.fetch("snapshot_path"), entry.fetch("sha256")] },
  "authored runtime artifacts" => manifest.fetch("authored_runtime_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "release evidence artifacts" => manifest.fetch("release_evidence_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "derived reference artifacts" => manifest.fetch("derived_reference_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] }
}

groups.each do |label, entries|
  entries.each do |relative_path, expected_sha256|
    path = File.join(SKILL_ROOT, relative_path)
    assert(File.file?(path), "missing #{label}: #{relative_path}")
    assert(Digest::SHA256.file(path).hexdigest == expected_sha256, "hash mismatch: #{relative_path}")
  end
end

require File.join(SKILL_ROOT, "scripts", "query_visual_facts.rb")
require File.join(SKILL_ROOT, "scripts", "query_dictionary_reference.rb")

visual = TarotReaderRelease::VisualFacts.new(root: SKILL_ROOT)
packets = visual.load_all
assert(packets.length == 78, "visual packet count")
assert(packets.map { |packet| packet.fetch("canonical_card_id") }.uniq.length == 78, "visual ID uniqueness")
assert(packets.count { |packet| packet.dig("source_ref", "resolved_observation_source") == "phase4a_recheck" } == 8,
       "Phase 4A provenance split")
assert(packets.count { |packet| packet.dig("source_ref", "resolved_observation_source") == "phase4b_observations" } == 70,
       "Phase 4B provenance split")

dictionary = TarotReaderRelease::DictionaryReferences.new(root: SKILL_ROOT)
result = dictionary.query(
  selector: "wands_ace",
  orientation: "upright",
  domain: "work",
  hypothesis: "A holistic hypothesis already exists",
  retrieval_reason: "Verify the packaged reviewed unit"
)
assert(result.length == 1, "Dictionary smoke query")

puts "Public package verified: 30 snapshots, 12 runtime artifacts, 1 acceptance artifact, 2 derived references, 78 visual packets (8/70), Dictionary smoke query pass."

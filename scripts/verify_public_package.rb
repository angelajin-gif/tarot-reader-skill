#!/usr/bin/env ruby

require "digest"
require "find"
require "yaml"

ROOT = File.expand_path("..", __dir__)
SKILL_ROOT = File.join(ROOT, "tarot-reader")
MANIFEST_PATH = File.join(SKILL_ROOT, "references", "release-snapshot-manifest.yaml")

def assert(condition, message)
  raise "public package verification failed: #{message}" unless condition
end

manifest = YAML.load_file(MANIFEST_PATH)
assert(manifest.fetch("release_id") == "tarot-reader.stage10.v1.3", "release identity mismatch")
assert(manifest.fetch("status") == "frozen", "release is not frozen")

groups = {
  "canonical snapshots" => manifest.fetch("entries").map { |entry| [entry.fetch("snapshot_path"), entry.fetch("sha256")] },
  "authored runtime artifacts" => manifest.fetch("authored_runtime_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "release evidence artifacts" => manifest.fetch("release_evidence_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "teacher evidence artifacts" => manifest.fetch("teacher_evidence_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "release control artifacts" => manifest.fetch("release_control_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "release test artifacts" => manifest.fetch("release_test_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] },
  "derived reference artifacts" => manifest.fetch("derived_reference_artifacts").map { |entry| [entry.fetch("artifact_path"), entry.fetch("sha256")] }
}

assert(groups.fetch("canonical snapshots").length == 30, "snapshot count")
assert(groups.fetch("release evidence artifacts").map(&:first) == ["acceptance.md"], "acceptance inventory")
declared = groups.values.flatten(1).map(&:first) + ["references/release-snapshot-manifest.yaml"]
assert(declared.uniq.length == declared.length, "duplicate package path")
actual = []
Find.find(SKILL_ROOT) do |path|
  next if path == SKILL_ROOT

  stat = File.lstat(path)
  assert(!stat.symlink?, "symlink in package: #{path}")
  actual << path.delete_prefix("#{SKILL_ROOT}/") if stat.file?
end
assert(actual.sort == declared.sort, "package inventory mismatch")

groups.each do |label, entries|
  entries.each do |relative_path, expected_sha256|
    path = File.join(SKILL_ROOT, relative_path)
    assert(File.file?(path), "missing #{label}: #{relative_path}")
    assert(Digest::SHA256.file(path).hexdigest == expected_sha256, "hash mismatch: #{relative_path}")
  end
end

require File.join(SKILL_ROOT, "scripts", "query_visual_facts.rb")
require File.join(SKILL_ROOT, "scripts", "query_dictionary_reference.rb")
require File.join(SKILL_ROOT, "scripts", "query_teacher_evidence.rb")

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

teacher = TarotReaderRelease::TeacherEvidence.new(root: SKILL_ROOT)
daniel = teacher.query(selector: "strength", teacher: "daniel", orientation: "upright")
assert(daniel.length == 1 && daniel.first.fetch("canonical_card_id") == "strength", "Daniel smoke query")

puts "Public package verified: 30 snapshots, 1 acceptance artifact, all manifest groups and exact inventory, 78 visual packets (8/70), Dictionary and Daniel smoke queries pass."

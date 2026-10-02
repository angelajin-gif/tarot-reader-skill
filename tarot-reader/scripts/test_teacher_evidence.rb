#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

require_relative "query_teacher_evidence"

class TeacherEvidenceLayerTest < Minitest::Test
  SKILL_ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("../..", SKILL_ROOT)
  QUERY_SCRIPT = File.join(SKILL_ROOT, "scripts", "query_teacher_evidence.rb")
  VISUAL_QUERY = File.join(SKILL_ROOT, "scripts", "query_visual_facts.rb")
  DICTIONARY_QUERY = File.join(SKILL_ROOT, "scripts", "query_dictionary_reference.rb")
  MANIFEST_PATH = File.join(SKILL_ROOT, "references", "release-snapshot-manifest.yaml")
  UNIT_ROOT = File.join(SKILL_ROOT, "references", "teacher-evidence")
  DANIEL_VALID_HYPOTHESIS = "the querent may mistake control for safety"
  DANIEL_VALID_REASON = "strength and devil create a conflict between taming desire and being bound by desire"
  DANIEL_VALID_FOCUS = "the woman's action taming the lion creates psychological tension with the chains"

  def setup
    @teacher = TarotReaderRelease::TeacherEvidence.new
    @visual = TarotReaderRelease::VisualFacts.new
    @dictionary = TarotReaderRelease::DictionaryReferences.new
    @manifest = YAML.load_file(MANIFEST_PATH)
  end

  def test_release_identity_manifest_and_unit_counts
    assert_equal "tarot-reader.stage10.v1.4", @manifest.fetch("release_id")
    assert_equal "frozen", @manifest.fetch("status")
    assert_equal 30, @manifest.fetch("entries").length
    assert_equal 7, @manifest.fetch("teacher_evidence_artifacts").length
    assert_equal 1, @manifest.fetch("release_control_artifacts").length
    assert_equal 78, YAML.load_file(File.join(UNIT_ROOT, "daniel-card-units.yaml")).fetch("unit_count")
    dawn = YAML.load_file(File.join(UNIT_ROOT, "dawn-court-units.yaml"))
    assert_equal 16, dawn.fetch("court_unit_count")
    assert_equal 4, dawn.fetch("rank_unit_count")
    assert_equal 78, YAML.load_file(File.join(UNIT_ROOT, "greer-reversal-units.yaml")).fetch("unit_count")
    assert_equal 22, YAML.load_file(File.join(UNIT_ROOT, "nichols-amplification-units.yaml")).fetch("unit_count")
  end

  def test_every_teacher_excerpt_joins_a_pinned_local_source_page
    provenance = YAML.load_file(File.join(UNIT_ROOT, "provenance.yaml"))
    source_by_id = provenance.fetch("sources").to_h { |source| [source.fetch("source_id"), source] }
    files = {
      "daniel" => "daniel-card-units.yaml", "dawn" => "dawn-court-units.yaml",
      "greer" => "greer-reversal-units.yaml", "nichols" => "nichols-amplification-units.yaml"
    }
    checked = 0
    files.each do |teacher, filename|
      source = source_by_id.fetch(teacher)
      chunks_path = File.join(REPO_ROOT, source.fetch("original_repo_paths").fetch("source_chunks_locator_only"))
      assert_equal source.fetch("sha256").fetch("source_chunks_locator_only"), Digest::SHA256.file(chunks_path).hexdigest
      excerpt_pages = {}
      File.foreach(chunks_path) do |line|
        chunk = JSON.parse(line)
        assert_equal source.fetch("book_id"), chunk.fetch("book_id")
        excerpt_id = chunk.fetch("excerpt_id")
        refute excerpt_pages.key?(excerpt_id), "duplicate source excerpt #{excerpt_id}"
        excerpt_pages[excerpt_id] = chunk.fetch("pdf_page")
      end
      document = YAML.load_file(File.join(UNIT_ROOT, filename))
      units = document.fetch("units") + document.fetch("rank_units", [])
      units.each do |unit|
        pages = unit.fetch("source_pages")
        excerpt_ids = unit.fetch("source_excerpt_ids")
        actual_pages = excerpt_ids.map { |id| excerpt_pages.fetch(id) }
        valid = if teacher == "greer"
                  pages.length == 2 && actual_pages.all? { |page| (pages[0]..pages[1]).cover?(page) }
                else
                  pages == actual_pages
                end
        assert valid, "source excerpt/page mismatch: #{unit.fetch("unit_id")}"
        checked += 1
      end
    end
    assert_equal 198, checked
  end

  def test_all_visual_ids_have_daniel_and_greer_units_with_bound_provenance
    ids = @visual.load_all.map { |packet| packet.fetch("canonical_card_id") }
    assert_equal 78, ids.uniq.length
    ids.each do |card_id|
      daniel = @teacher.query(selector: card_id, teacher: "daniel", orientation: "upright").fetch(0)
      greer = @teacher.query(selector: card_id, teacher: "greer", orientation: "reversed").fetch(0)
      assert_equal card_id, daniel.fetch("canonical_card_id")
      assert_equal card_id, greer.fetch("canonical_card_id")
      assert_equal "daniel_16_lessons_zh", daniel.dig("source_ref", "source_book_id")
      assert_equal "greer_reversals_zh", greer.dig("source_ref", "source_book_id")
      assert daniel.dig("source_ref", "source_excerpt_ids").any?
      assert greer.dig("source_ref", "source_pages").any?
    end
  end

  def test_greer_page_and_knight_gaps_are_explicit_general_framework_fallbacks
    gap_ids = %w[
      wands_page wands_knight cups_page cups_knight swords_page swords_knight
      pentacles_page pentacles_knight
    ]
    assert_equal gap_ids.sort, TarotReaderRelease::TeacherEvidence::GREER_COVERAGE_GAP_IDS.sort
    gap_ids.each do |card_id|
      result = @teacher.query(selector: card_id, teacher: "greer", orientation: "reversed").fetch(0)
      assert_equal "greer_general_mechanism_framework", result.fetch("capability")
      assert_equal "coverage_fallback", result.fetch("review_status")
      assert_equal "coverage_fallback", result.dig("source_ref", "visual_review_status")
      assert_equal (58..63).to_a, result.dig("source_ref", "source_pages")
      assert_empty result.dig("evidence_detail", "reversal_mechanism_candidates")
      assert_equal 7, result.dig("evidence_detail", "alternatives").length
      refute result.fetch("condensed_evidence").include?("该牌逆位意味着")
    end
    card_specific = @teacher.query(selector: "swords_two", teacher: "greer", orientation: "reversed").fetch(0)
    assert_equal "greer_reversal_mechanism", card_specific.fetch("capability")
    refute_equal "coverage_fallback", card_specific.fetch("review_status")
  end

  def test_rehashed_greer_gap_drift_fails_closed
    with_skill_copy do |copy_root|
      relative = "references/teacher-evidence/greer-reversal-units.yaml"
      path = File.join(copy_root, relative)
      document = YAML.load_file(path)
      document.fetch("units").find { |unit| unit.fetch("canonical_card_id") == "wands_page" }["reversal_anchor"] = "unreviewed claim"
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, relative)
      _output, error, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "wands_page", "--teacher", "greer", "--orientation", "reversed")
      refute status.success?
      assert_match(/incomplete Greer reversal evidence|Greer coverage gap drift/, error)
    end
  end

  def test_rehashed_greer_general_framework_locator_drift_fails_closed
    with_skill_copy do |copy_root|
      relative = "references/teacher-evidence/provenance.yaml"
      path = File.join(copy_root, relative)
      document = YAML.load_file(path)
      document.fetch("excerpt_locator_index").fetch("greer_reversals_zh")
              .fetch("greer_reversals_zh.ex0059")["pdf_page"] = 999
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, relative)
      _output, error, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "wands_page", "--teacher", "greer", "--orientation", "reversed")
      refute status.success?
      assert_match(/Greer general-framework provenance drift/, error)
    end
  end

  def test_all_court_and_rank_units_are_queryable
    court_ids = @visual.load_all.map { |packet| packet.fetch("canonical_card_id") }.select { |id| id.match?(/_(page|knight|queen|king)\z/) }
    assert_equal 16, court_ids.length
    court_ids.each do |card_id|
      result = @teacher.query(selector: card_id, teacher: "dawn", orientation: "unspecified").fetch(0)
      assert_equal "dawn_court_ontology", result.fetch("capability")
      assert result.dig("evidence_detail", "archetype_name")
      assert result.dig("source_ref", "source_pages").length >= 1
    end
    %w[Page Knight Queen King].each do |rank|
      result = @teacher.query(teacher: "dawn", capability: "dawn_rank_function", rank: rank).fetch(0)
      assert_nil result.fetch("canonical_card_id")
      assert_equal rank, result.dig("evidence_detail", "rank")
    end
  end

  def test_nichols_has_only_major_specialist_units
    document = YAML.load_file(File.join(UNIT_ROOT, "nichols-amplification-units.yaml"))
    document.fetch("units").each do |unit|
      card_name = unit.fetch("canonical_card_id").tr("_", " ")
      result = @teacher.query(selector: unit.fetch("canonical_card_id"), teacher: "nichols", orientation: "upright",
                              hypothesis: "the querent may confuse the #{card_name} pattern with safety",
                              retrieval_reason: "the #{card_name} motif creates a tension that changes the spread",
                              focus: "the visible #{card_name} motif and its evidence bridge require closer comparison",
                              nichols_trigger: "motif", reason_anchor: "unit:evidence_bridge",
                              focus_anchor: "visual:scene").fetch(0)
      assert_equal "nichols_major_amplification", result.fetch("capability")
      assert_equal "nichols_jung_tarot_en", result.dig("source_ref", "source_book_id")
      assert_operator result.dig("source_ref", "source_pages").length, :>=, 2
      assert result.dig("evidence_detail", "evidence_bridge").to_s.length > 20
    end
    assert_equal 22, document.fetch("units").length
    assert_operator document.fetch("units").map { |unit| unit.fetch("author_specific_amplification") }.uniq.length, :>, 20
    assert_operator document.fetch("units").map { |unit| unit.fetch("polarity") }.uniq.length, :>, 20

    tower = document.fetch("units").find { |unit| unit.fetch("canonical_card_id") == "tower" }
    assert_includes tower.fetch("author_specific_amplification"), "Liberation"
    assert_includes tower.fetch("evidence_bridge"), "collapse"
    strength = document.fetch("units").find { |unit| unit.fetch("canonical_card_id") == "strength" }
    assert_includes strength.fetch("author_specific_amplification"), "皇帝"
    assert_includes strength.fetch("author_specific_amplification"), "狮子"
  end

  def test_daniel_unspecified_is_explicit_baseline_without_greer_activation
    result = @teacher.query(selector: "wands_two", teacher: "daniel", orientation: "unspecified").fetch(0)
    assert_equal "upright_baseline_for_unspecified_orientation", result.fetch("orientation_scope")
    refute_equal "upright", result.fetch("orientation_scope")
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(selector: "wands_two", teacher: "greer", orientation: "unspecified")
    end
  end

  def test_nichols_requires_nonempty_context_and_structured_evidence_selections
    base = {selector: "tower", teacher: "nichols", orientation: "upright"}
    assert_raises(TarotReaderRelease::ResolutionError) { @teacher.query(**base) }
    context = {hypothesis: "a live hypothesis", retrieval_reason: "a retrieval note", focus: "a focus note"}
    %i[hypothesis retrieval_reason focus].each do |missing|
      args = context.dup
      args[missing] = nil
      assert_raises(TarotReaderRelease::ResolutionError) { @teacher.query(**base, **args, nichols_trigger: "motif", reason_anchor: "unit:evidence_bridge", focus_anchor: "visual:scene") }
    end
    assert_raises(TarotReaderRelease::ResolutionError) { @teacher.query(**base, **context) }
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(**base, **context, nichols_trigger: "polarity", reason_anchor: "unit:evidence_bridge", focus_anchor: "visual:scene")
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(**base, **context, nichols_trigger: "motif", reason_anchor: "unit:does_not_exist", focus_anchor: "visual:scene")
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(**base, **context, nichols_trigger: "motif", reason_anchor: "unit:evidence_bridge", focus_anchor: "visual:review_copy")
    end
    output, error, status = Open3.capture3(
      RbConfig.ruby, QUERY_SCRIPT, "tower", "--teacher", "nichols", "--orientation", "upright",
      "--hypothesis", DANIEL_VALID_HYPOTHESIS, "--reason", "the falling figures and struck tower may change the judgment",
      "--focus", "lightning-struck tower and ejected figures", "--nichols-trigger", "motif",
      "--reason-anchor", "unit:evidence_bridge", "--focus-anchor", "visual:action"
    )
    assert status.success?, error
    result = JSON.parse(output).fetch(0)
    assert_equal "nichols.tower.major_amplification", result.fetch("unit_id")
    assert_equal "nichols_jung_tarot_en", result.dig("source_ref", "source_book_id")
  end

  def test_nichols_gate_rejects_free_text_lookalikes_without_structured_selection
    base = [RbConfig.ruby, QUERY_SCRIPT, "tower", "--teacher", "nichols", "--orientation", "upright"]
    cases = [
      ["The querent may be a purple bicycle", "tower changes banana orange", "lightning window carpet"],
      ["當事人可能是紫色自行車", "高塔形成香蕉蘋果的衝突", "閃電和窗簾的焦點"],
      ["The querent may be a silver kettle", "tower changes velvet telescope", "lightning compass sandwich"],
      ["當事人可能是綠色勺子", "高塔出現玻璃葡萄衝突", "閃電和月亮的無關標籤"],
      %w[h r x], %w[test foo bar],
      [DANIEL_VALID_HYPOTHESIS, "because this is a major card", "lightning and figures"],
      [DANIEL_VALID_HYPOTHESIS, "因为它是大牌", "lightning and figures"],
      [DANIEL_VALID_HYPOTHESIS, DANIEL_VALID_REASON, "Major"],
      [DANIEL_VALID_HYPOTHESIS, DANIEL_VALID_REASON, DANIEL_VALID_REASON]
    ]
    cases.each do |hypothesis, reason, focus|
      _out, _err, status = Open3.capture3(*base, "--hypothesis", hypothesis, "--reason", reason, "--focus", focus)
      refute status.success?, "free-text-only Nichols query unexpectedly passed: #{[hypothesis, reason, focus].inspect}"
    end
  end

  def test_nichols_gate_accepts_natural_chinese_and_english_with_auditable_selections
    chinese = @teacher.query(selector: "strength", teacher: "nichols", orientation: "upright",
                             hypothesis: "当事人可能把等待误认为答案",
                             retrieval_reason: "力量与欲望之间形成需要边界的冲突",
                             focus: "女子与狮子的近距离动作显示控制和整合的张力",
                             nichols_trigger: "polarity", reason_anchor: "unit:polarity",
                             focus_anchor: "visual:spatial_relations").fetch(0)
    assert_equal "nichols.strength.major_amplification", chinese.fetch("unit_id")
    english = @teacher.query(selector: "strength", teacher: "nichols", orientation: "upright",
                             hypothesis: "the querent may mistake gentleness for a lack of power",
                             retrieval_reason: "the woman and lion motif creates a conflict between control and integration",
                             focus: "the woman's gentle grip near the lion's mouth shows power being enacted",
                             nichols_trigger: "motif", reason_anchor: "unit:evidence_bridge",
                             focus_anchor: "visual:figures").fetch(0)
    assert_equal "nichols.strength.major_amplification", english.fetch("unit_id")
  end

  def test_nichols_gate_cli_has_real_positive_and_negative_paths
    common = [RbConfig.ruby, QUERY_SCRIPT, "strength", "--teacher", "nichols", "--orientation", "upright"]
    tower_common = [RbConfig.ruby, QUERY_SCRIPT, "tower", "--teacher", "nichols", "--orientation", "upright"]
    _out, err, status = Open3.capture3(*tower_common, "--hypothesis", "the querent may rely on a structure that no longer feels secure",
                                       "--reason", "the tower's collapse motif changes whether persistence still helps",
                                       "--focus", "lightning strikes the building as figures fall away",
                                       "--nichols-trigger", "motif", "--reason-anchor", "unit:evidence_bridge",
                                       "--focus-anchor", "visual:action")
    assert status.success?, err

    _out, err, status = Open3.capture3(*tower_common, "--hypothesis", "当事人可能仍依赖已经失去稳定性的安排",
                                       "--reason", "高塔的崩塌过程会改变继续维持现状是否可行的判断",
                                       "--focus", "闪电击中建筑，人物从塔体坠落的画面关系",
                                       "--nichols-trigger", "motif", "--reason-anchor", "unit:evidence_bridge",
                                       "--focus-anchor", "visual:action")
    assert status.success?, err

    _out, err, status = Open3.capture3(*common, "--hypothesis", "the querent may be avoiding a decision by preserving an old structure",
                                       "--reason", "the tower's collapse motif challenges the assumption that stability can be restored unchanged",
                                       "--focus", "the struck tower and displaced figures show a break in the existing structure",
                                       "--nichols-trigger", "motif", "--reason-anchor", "unit:evidence_bridge",
                                       "--focus-anchor", "visual:action")
    assert status.success?, err

    _out, err, status = Open3.capture3(*common, "--hypothesis", "当事人可能把温和误解成软弱",
                                       "--reason", "力量牌中女子与狮子的相处方式使压制和配合的区别改变判断",
                                       "--focus", "女子以柔和动作控制狮子口部而非使用蛮力",
                                       "--nichols-trigger", "motif", "--reason-anchor", "unit:evidence_bridge",
                                       "--focus-anchor", "visual:spatial_relations")
    assert status.success?, err

    route_context = ["--hypothesis", "the querent may rely on a damaged structure",
                     "--reason", "the tower motif calls for a change in perspective",
                     "--focus", "the struck structure and falling figures"]
    [
      ["--reason-anchor", "unit:evidence_bridge", "--focus-anchor", "visual:action"],
      ["--nichols-trigger", "motif", "--focus-anchor", "visual:action"],
      ["--nichols-trigger", "motif", "--reason-anchor", "unit:evidence_bridge"],
      ["--nichols-trigger", "major", "--reason-anchor", "unit:evidence_bridge", "--focus-anchor", "visual:action"],
      ["--nichols-trigger", "polarity", "--reason-anchor", "unit:evidence_bridge", "--focus-anchor", "visual:action"],
      ["--nichols-trigger", "motif", "--reason-anchor", "unit:missing_field", "--focus-anchor", "visual:action"],
      ["--nichols-trigger", "motif", "--reason-anchor", "unit:evidence_bridge", "--focus-anchor", "visual:review_copy"]
    ].each do |route_args|
      _out, _err, status = Open3.capture3(*tower_common, *route_context, *route_args)
      refute status.success?, "CLI unexpectedly accepted invalid structured route #{route_args.inspect}"
    end

    [["The querent may be a purple bicycle", "tower changes banana orange", "lightning window carpet"],
     ["当事人可能是紫色自行车", "高塔形成香蕉苹果的冲突", "闪电和窗帘的焦点"],
     ["The querent may be a silver kettle", "tower changes velvet telescope", "lightning compass sandwich"],
     ["当事人可能是绿色勺子", "高塔出现玻璃葡萄冲突", "闪电和月亮的无关标签"],
     ["alpha beta", "gamma delta", "epsilon zeta"], ["banana orange", "window carpet", "purple bicycle"],
     ["这是测试", "这是原因", "这是焦点"], ["h", "r", "x"], ["test", "foo", "bar"],
     ["the querent may confuse the strength pattern with safety", "because this is a major card", "lightning and figures"],
     ["the querent may confuse control with safety", "因为它是大牌", "闪电和人物"],
     ["the querent may confuse control with safety", "the strength motif creates a conflict", "Major"],
     ["the strength motif creates a conflict", "the strength motif creates a conflict", "the strength motif creates a conflict"]].each do |hypothesis, reason, focus|
      args = tower_common + ["--hypothesis", hypothesis, "--reason", reason]
      args += ["--focus", focus]
      _out, _err, status = Open3.capture3(*args)
      refute status.success?, "gate unexpectedly accepted #{[hypothesis, reason, focus].inspect}"
    end
    {"missing_hypothesis" => ["--reason", "reason", "--focus", "focus"],
     "missing_reason" => ["--hypothesis", "hypothesis", "--focus", "focus"],
     "missing_focus" => ["--hypothesis", "hypothesis", "--reason", "reason"]}.each do |label, args|
      _out, _err, status = Open3.capture3(*tower_common, *args, "--nichols-trigger", "motif",
                                          "--reason-anchor", "unit:evidence_bridge", "--focus-anchor", "visual:scene")
      refute status.success?, "gate unexpectedly accepted #{label}"
    end
  end

  def test_daniel_content_corrections_and_major_continuation_provenance
    units = YAML.load_file(File.join(UNIT_ROOT, "daniel-card-units.yaml")).fetch("units")
    page = units.find { |unit| unit.fetch("canonical_card_id") == "pentacles_page" }
    refute_includes page.fetch("author_visual_narrative"), "書本"
    refute_includes page.fetch("author_visual_narrative"), "工具"
    assert page.fetch("author_interpretation").any? { |item| item.include?("學徒") }

    strength = units.find { |unit| unit.fetch("canonical_card_id") == "strength" }
    assert_includes strength.fetch("author_visual_narrative"), "女子"
    assert_includes strength.fetch("author_visual_narrative"), "獅子口部"
    assert_equal [137, 138], strength.fetch("source_pages")
    assert strength.fetch("author_interpretation").any?

    eight = units.find { |unit| unit.fetch("canonical_card_id") == "pentacles_eight" }
    refute_includes eight.fetch("author_visual_narrative"), "樹上"
    assert_includes eight.fetch("author_visual_narrative"), "木面"
    chariot = units.find { |unit| unit.fetch("canonical_card_id") == "chariot" }
    refute_match(/韁繩|寶劍/, chariot.fetch("author_visual_narrative"))
    sun = units.find { |unit| unit.fetch("canonical_card_id") == "sun" }
    refute_includes sun.fetch("author_visual_narrative"), "向日葵旗"
    world = units.find { |unit| unit.fetch("canonical_card_id") == "world" }
    refute_match(/象、獅/, world.fetch("author_visual_narrative"))
    moon = units.find { |unit| unit.fetch("canonical_card_id") == "moon" }
    refute_includes moon.fetch("author_visual_narrative"), "對望"

    major_ids = %w[magician high_priestess empress emperor hierophant lovers chariot strength hermit wheel_of_fortune justice hanged_man death temperance devil tower star moon sun judgement fool world]
    majors = units.select { |unit| major_ids.include?(unit.fetch("canonical_card_id")) }
    assert_equal 22, majors.length
    majors.each do |unit|
      assert_equal unit.fetch("source_pages").length, unit.fetch("source_excerpt_ids").length
      assert_operator unit.fetch("source_pages").length, :>=, 2
      assert_includes unit.fetch("visual_review_note"), "continuation page"
    end
  end

  def test_daniel_semantic_fields_and_court_evidence_are_bound_to_reviewed_content
    units = YAML.load_file(File.join(UNIT_ROOT, "daniel-card-units.yaml")).fetch("units")
    assert_equal 78, units.length
    units.each do |unit|
      assert_equal "manually_reviewed_rendered_page", unit.fetch("review_status")
      assert_operator unit.fetch("author_visual_narrative").to_s.length, :>, 10
      assert_equal unit.fetch("source_pages").length, unit.fetch("source_excerpt_ids").length
      unit.fetch("source_pages").zip(unit.fetch("source_excerpt_ids")).each do |page, excerpt_id|
        assert_includes excerpt_id, format("p%04d.", page)
      end
    end

    six = units.find { |unit| unit.fetch("canonical_card_id") == "pentacles_six" }
    assert_includes six.fetch("author_visual_narrative"), "六枚錢幣"
    assert_includes six.fetch("author_visual_narrative"), "秤"
    assert_includes six.fetch("author_visual_narrative"), "兩名跪著的人"

    queen = @teacher.query(selector: "wands_queen", teacher: "dawn", orientation: "unspecified").fetch(0)
    detail = queen.fetch("evidence_detail")
    assert_operator detail.fetch("observable_behaviors").length, :>, 0
    assert_operator detail.fetch("strengths").length, :>, 0
    assert_operator detail.fetch("shadow_or_failure_modes").length, :>, 0
    assert_equal "dawn_court_ontology", queen.fetch("capability")
    assert_equal "dawn_court_zh", queen.dig("source_ref", "source_book_id")
  end

  def test_source_excerpt_ids_exist_and_match_declared_pages_and_nichols_chapters
    daniel_chunks = jsonl_by_excerpt(File.join(File.expand_path("../..", SKILL_ROOT), "reading/daniel_16_lessons_zh/source-chunks.jsonl"))
    nichols_chunks = jsonl_by_excerpt(File.join(File.expand_path("../..", SKILL_ROOT), "reading/nichols_archetypal_journey_en/source-chunks.jsonl"))
    YAML.load_file(File.join(UNIT_ROOT, "daniel-card-units.yaml")).fetch("units").each do |unit|
      unit.fetch("source_pages").zip(unit.fetch("source_excerpt_ids")).each do |page, excerpt_id|
        row = daniel_chunks.fetch(excerpt_id)
        assert_equal page, row.fetch("pdf_page")
      end
    end
    expected_chapters = {
      "fool" => "ch03_the_fool", "magician" => "ch04_the_magician", "high_priestess" => "ch05_the_popess",
      "empress" => "ch06_the_empress", "emperor" => "ch07_the_emperor", "hierophant" => "ch08_the_pope",
      "lovers" => "ch09_the_lover", "chariot" => "ch10_the_chariot", "justice" => "ch11_justice",
      "hermit" => "ch12_the_hermit", "wheel_of_fortune" => "ch13_wheel_of_fortune", "strength" => "ch14_strength",
      "hanged_man" => "ch15_the_hanged_man", "death" => "ch16_death", "temperance" => "ch17_temperance",
      "devil" => "ch18_the_devil", "tower" => "ch19_the_tower", "star" => "ch20_the_star",
      "moon" => "ch21_the_moon", "sun" => "ch22_the_sun", "judgement" => "ch23_judgement",
      "world" => "ch24_the_world"
    }
    YAML.load_file(File.join(UNIT_ROOT, "nichols-amplification-units.yaml")).fetch("units").each do |unit|
      if unit.key?("source_page_support")
        assert_equal unit.fetch("source_pages").map(&:to_s).sort, unit.fetch("source_page_support").keys.map(&:to_s).sort
        assert unit.fetch("source_page_support").values.all? { |support| support.to_s.length >= 20 }
      end
      unit.fetch("source_pages").zip(unit.fetch("source_excerpt_ids")).each do |page, excerpt_id|
        row = nichols_chunks.fetch(excerpt_id)
        assert_equal page, row.fetch("pdf_page")
        assert_equal expected_chapters.fetch(unit.fetch("canonical_card_id")), row.fetch("chapter_id")
        refute_includes [111, 130, 151, 172, 184, 197, 214, 229, 247, 275, 294, 308, 336, 351, 380, 396, 419, 436, 449, 463], page
      end
    end
  end

  def test_high_priestess_astarte_page_has_auditable_support_and_adopted_page_count
    document = YAML.load_file(File.join(UNIT_ROOT, "nichols-amplification-units.yaml"))
    unit = document.fetch("units").find { |entry| entry.fetch("canonical_card_id") == "high_priestess" }
    assert_equal [112, 119, 120], unit.fetch("source_pages")
    assert_includes unit.fetch("author_specific_amplification"), "Astarte"
    assert_includes unit.fetch("source_page_support").fetch("119"), "Astarte"
    assert_includes unit.fetch("source_page_support").fetch("120"), "图注"
    assert_equal 47, document.fetch("units").sum { |entry| entry.fetch("source_pages").length }
  end

  def test_daniel_meaning_fixtures_and_world_boundary_are_source_specific
    units = YAML.load_file(File.join(UNIT_ROOT, "daniel-card-units.yaml")).fetch("units").to_h { |unit| [unit.fetch("canonical_card_id"), unit] }
    {
      "chariot" => %w[戰爭行為 不斷努力 征服 以智取勝],
      "strength" => %w[權力 勇氣 相互配合 以柔克剛],
      "moon" => %w[不安與恐懼 欺騙和幻覺 隱藏的危險 難以捉摸的變化],
      "sun" => %w[圓滿成功 快樂與滿足 一視同仁 朝向光明面],
      "world" => %w[自然的規律 到此為止 完美的結局 統合]
    }.each { |card_id, expected| assert_equal expected, units.fetch(card_id).fetch("meaning_candidates") }
    refute_includes units.fetch("world").fetch("process_or_tension"), "新的循環"
    refute_includes units.fetch("pentacles_eight").fetch("author_visual_narrative"), "樹"
    refute_match(/韁繩|寶劍/, units.fetch("chariot").fetch("author_visual_narrative"))
    refute_includes units.fetch("sun").fetch("author_visual_narrative"), "向日葵旗"
    refute_match(/象、獅/, units.fetch("world").fetch("author_visual_narrative"))
  end

  def test_daniel_wands_three_and_swords_eight_meaning_candidates_are_exact
    units = YAML.load_file(File.join(UNIT_ROOT, "daniel-card-units.yaml")).fetch("units").to_h { |unit| [unit.fetch("canonical_card_id"), unit] }
    assert_equal ["初步的成果", "合作及領導", "積極進取", "未知的旅程"], units.fetch("wands_three").fetch("meaning_candidates")
    assert_equal ["綑綁", "看不見真相", "被敵意包圍", "壞消息"], units.fetch("swords_eight").fetch("meaning_candidates")
  end

  def test_builder_is_reproducible_for_daniel_and_nichols_outputs
    paths = ["references/teacher-evidence/daniel-card-units.yaml", "references/teacher-evidence/nichols-amplification-units.yaml"]
    before = paths.to_h { |path| [path, Digest::SHA256.file(File.join(SKILL_ROOT, path)).hexdigest] }
    2.times do
      _out, err, status = Open3.capture3(RbConfig.ruby, File.join(SKILL_ROOT, "scripts/build_teacher_evidence.rb"), chdir: File.expand_path("../..", SKILL_ROOT))
      assert status.success?, err
    end
    after = paths.to_h { |path| [path, Digest::SHA256.file(File.join(SKILL_ROOT, path)).hexdigest] }
    assert_equal before, after
  end

  def test_dictionary_all_reviewed_units_query_and_unsupported_entry_stops
    units = YAML.load_file(File.join(SKILL_ROOT, "references/dictionary-reference-units.yaml"))
    entries = units.fetch("entries")
    assert_equal 22, entries.length
    entries.each do |entry|
      results = @teacher.query(selector: entry.fetch("canonical_card_id"), teacher: "dictionary",
                               orientation: entry.fetch("orientation"), domain: entry.fetch("domain"),
                               hypothesis: "existing holistic hypothesis", retrieval_reason: "test a concrete manifestation")
      result = results.fetch(0)
      assert_equal entry.fetch("entry_id"), result.fetch("unit_id")
      assert_equal entry.fetch("domain"), result.dig("evidence_detail", "domain")
      assert_equal entry.fetch("source_ref").fetch("pdf_pages"), result.dig("source_ref", "source_pages")
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(selector: "pentacles_two", teacher: "dictionary", orientation: "upright",
                     domain: "work", hypothesis: "h", retrieval_reason: "r")
    end
  end

  def test_permissions_orientation_and_result_whitelist_fail_closed
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(selector: "swords_two", teacher: "greer", orientation: "unspecified")
    end
    unspecified = @teacher.query(selector: "wands_two", teacher: "daniel", orientation: "unspecified").fetch(0)
    assert_equal "upright_baseline_for_unspecified_orientation", unspecified.fetch("orientation_scope")
    refute_equal "upright", unspecified.fetch("orientation_scope")
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(selector: "wands_two", teacher: "daniel", capability: "greer_reversal_mechanism", orientation: "reversed")
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(selector: "not_a_card", teacher: "daniel", orientation: "upright")
    end
    assert_raises(TarotReaderRelease::ResolutionError) do
      @teacher.query(selector: "wands_ace", teacher: "dictionary", orientation: "upright", domain: "work")
    end
    result = @teacher.query(selector: "wands_two", teacher: "daniel", orientation: "upright").fetch(0)
    assert_equal TarotReaderRelease::TeacherEvidence::RESULT_FIELDS.sort, result.keys.sort
    refute result.keys.any? { |key| %w[symbolic_readings edition_specific_visuals review_copy acquisition_url raw_ocr card_meaning].include?(key) }
  end

  def test_cli_rejects_extra_positional_selectors
    [["wands_two", "not_a_card", "--teacher", "daniel"],
     ["tower", "moon", "--teacher", "nichols"]].each do |args|
      _output, error, status = Open3.capture3(RbConfig.ruby, QUERY_SCRIPT, *args)
      refute status.success?
      assert_match(/at most one card selector/, error)
    end
  end

  def test_nested_teacher_output_is_explicitly_allowlisted
    daniel = @teacher.query(selector: "wands_two", teacher: "daniel").fetch(0)
    assert_equal TarotReaderRelease::TeacherEvidence::DETAIL_FIELDS.fetch("daniel").sort,
                 daniel.fetch("evidence_detail").keys.sort
    assert_equal TarotReaderRelease::TeacherEvidence::SOURCE_REF_FIELDS.sort, daniel.fetch("source_ref").keys.sort
    priestess = @teacher.query(selector: "high_priestess", teacher: "nichols", hypothesis: "the hidden figure may complicate the reading",
                               retrieval_reason: "the card's evidence bridge bears on that tension", focus: "the seated figure",
                               nichols_trigger: "motif", reason_anchor: "unit:evidence_bridge", focus_anchor: "visual:scene").fetch(0)
    assert_equal %w[112 119 120], priestess.dig("evidence_detail", "source_page_support").keys.sort
    assert_equal %w[focus_anchor reason_anchor trigger], priestess.dig("evidence_detail", "retrieval_selection").keys.sort
  end

  def test_rehashed_unknown_nested_unit_field_fails_closed
    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      document = YAML.load_file(path)
      document.fetch("units").first["raw_ocr"] = "AUDIT_CANARY"
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      output, error, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                              "wands_ace", "--teacher", "daniel")
      refute status.success?
      refute_includes output, "AUDIT_CANARY"
      assert_match(/field whitelist violation/, error)
    end
  end

  def test_nichols_selection_trace_distinguishes_valid_routes_and_fixture_runs
    common = {selector: "tower", teacher: "nichols", orientation: "upright", hypothesis: "the old structure may be unstable",
              retrieval_reason: "the tower evidence may change the judgment", focus: "the struck tower and falling figures"}
    motif = @teacher.query(**common, nichols_trigger: "motif", reason_anchor: "unit:evidence_bridge", focus_anchor: "visual:action").fetch(0)
    polarity = @teacher.query(**common, nichols_trigger: "polarity", reason_anchor: "unit:polarity", focus_anchor: "visual:scene").fetch(0)
    refute_equal motif, polarity
    assert_equal({"trigger" => "motif", "reason_anchor" => "unit:evidence_bridge", "focus_anchor" => "visual:action"},
                 motif.dig("evidence_detail", "retrieval_selection"))
    refute_includes JSON.generate(motif), common.fetch(:hypothesis)
    fixture = YAML.load_file(File.join(SKILL_ROOT, "references/teacher-evidence-behavior-fixtures.yaml"))
    entry = fixture.fetch("scenarios").find { |item| item.fetch("id") == "major_specialist" }
    input = entry.fetch("input")
    output, error, status = Open3.capture3(RbConfig.ruby, QUERY_SCRIPT, input.fetch("selector"), "--teacher", input.fetch("teacher"),
                                            "--orientation", input.fetch("orientation"), "--hypothesis", input.fetch("hypothesis"),
                                            "--reason", input.fetch("reason"), "--focus", input.fetch("focus"),
                                            "--nichols-trigger", input.fetch("nichols_trigger"), "--reason-anchor", input.fetch("reason_anchor"),
                                            "--focus-anchor", input.fetch("focus_anchor"))
    assert status.success?, error
    assert_equal entry.fetch("required_capability"), JSON.parse(output).fetch(0).fetch("capability")
  end

  def test_actual_query_fails_closed_on_teacher_unit_tamper
    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      document = YAML.load_file(path)
      document.fetch("units").find { |unit| unit.fetch("canonical_card_id") == "wands_two" }["process_or_tension"] = "AUDIT_TAMPERED"
      File.write(path, YAML.dump(document))
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "wands_two", "--teacher", "daniel", "--orientation", "upright")
      refute status.success?
      assert_match(/hash mismatch|failed closed/, stderr)
    end
  end

  def test_actual_query_fails_closed_on_source_drift_duplicate_id_unreviewed_and_missing_provenance
    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      document = YAML.load_file(path)
      document.fetch("units").first["source_excerpt_ids"] = ["greer_reversals_zh.ex0001"]
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "wands_ace", "--teacher", "daniel", "--orientation", "upright")
      refute status.success?
      assert_match(/source excerpt drift|failed closed/, stderr)
    end

    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/teacher-evidence/dawn-court-units.yaml")
      document = YAML.load_file(path)
      document.fetch("units")[1]["unit_id"] = document.fetch("units").first.fetch("unit_id")
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, "references/teacher-evidence/dawn-court-units.yaml")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "wands_queen", "--teacher", "dawn")
      refute status.success?
      assert_match(/unit IDs are not unique|failed closed/, stderr)
    end

    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/teacher-evidence/nichols-amplification-units.yaml")
      document = YAML.load_file(path)
      document.fetch("units").first["review_status"] = "ocr_candidate_visual_review_pending"
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, "references/teacher-evidence/nichols-amplification-units.yaml")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "fool", "--teacher", "nichols", "--orientation", "upright",
                                               "--hypothesis", "h", "--reason", "r", "--focus", "concrete motif")
      refute status.success?
      assert_match(/unsupported Teacher review status|failed closed/, stderr)
    end

    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      document = YAML.load_file(path)
      document.fetch("units").first.delete("source_excerpt_ids")
      File.write(path, YAML.dump(document))
      refresh_teacher_artifact_hash(copy_root, "references/teacher-evidence/daniel-card-units.yaml")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_teacher_evidence.rb"),
                                               "wands_ace", "--teacher", "daniel", "--orientation", "upright")
      refute status.success?
      assert_match(/missing Teacher provenance|failed closed/, stderr)
    end
  end

  def test_actual_query_fails_closed_on_phase4c_status_even_when_hash_is_updated
    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/snapshot/controls/phase4c-visual-loader-contract.yaml")
      document = YAML.load_file(path)
      document["status"] = "in_progress"
      File.write(path, YAML.dump(document))
      manifest_path = File.join(copy_root, "references/release-snapshot-manifest.yaml")
      manifest = YAML.load_file(manifest_path)
      entry = manifest.fetch("entries").find { |item| item.fetch("snapshot_path") == "references/snapshot/controls/phase4c-visual-loader-contract.yaml" }
      entry["sha256"] = Digest::SHA256.file(path).hexdigest
      File.write(manifest_path, YAML.dump(manifest))
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_visual_facts.rb"), "wands_ace")
      refute status.success?
      assert_match(/Phase 4C contract is not frozen|failed closed/, stderr)
    end
  end

  def test_actual_dictionary_query_fails_closed_on_unit_tamper
    with_skill_copy do |copy_root|
      path = File.join(copy_root, "references/dictionary-reference-units.yaml")
      document = YAML.load_file(path)
      document.fetch("entries").first["condensed_statement"] = "AUDIT_TAMPERED"
      File.write(path, YAML.dump(document))
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(copy_root, "scripts/query_dictionary_reference.rb"),
                                               "wands_ace", "upright", "work", "--hypothesis", "h", "--reason", "r")
      refute status.success?
      assert_match(/hash mismatch|failed closed/, stderr)
    end
  end

  private

  def jsonl_by_excerpt(path)
    File.foreach(path).map { |line| JSON.parse(line) }.to_h { |row| [row.fetch("excerpt_id"), row] }
  end

  def with_skill_copy
    Dir.mktmpdir("tarot-teacher-evidence-") do |tmp|
      copy_root = File.join(tmp, "skill")
      FileUtils.cp_r(SKILL_ROOT, copy_root)
      yield copy_root
    end
  end

  def refresh_teacher_artifact_hash(copy_root, relative_path)
    manifest_path = File.join(copy_root, "references/release-snapshot-manifest.yaml")
    manifest = YAML.load_file(manifest_path)
    entry = manifest.fetch("teacher_evidence_artifacts").find { |item| item.fetch("artifact_path") == relative_path }
    entry["sha256"] = Digest::SHA256.file(File.join(copy_root, relative_path)).hexdigest
    File.write(manifest_path, YAML.dump(manifest))
  end
end

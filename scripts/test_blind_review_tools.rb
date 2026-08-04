#!/usr/bin/env ruby

require "digest"
require "csv"
require "base64"
require "fileutils"
require "open3"
require "json"
require "tmpdir"
require "yaml"
require "zlib"

repo_root = File.expand_path("..", __dir__)
builder = File.join(repo_root, "scripts/build_blind_review_package.rb")
score_checker = File.join(repo_root, "scripts/check_blind_review_scores.rb")

def assert(condition, message)
  raise message unless condition
end

def png_chunk(type, data)
  [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
end

def rgba_png(red, green, blue, alpha = 255)
  signature = "\x89PNG\r\n\x1a\n".b
  header = [1, 1, 8, 6, 0, 0, 0].pack("NNCCCCC")
  pixels = Zlib::Deflate.deflate([0, red, green, blue, alpha].pack("C*"))
  signature + png_chunk("IHDR".b, header) + png_chunk("IDAT".b, pixels) + png_chunk("IEND".b, "".b)
end

def png_with_text(png, keyword, value)
  chunk = png_chunk("tEXt".b, "#{keyword}\0#{value}".b)
  png.byteslice(0, png.bytesize - 12) + chunk + png.byteslice(png.bytesize - 12, 12)
end

quality_root = File.join(repo_root, ".quality")
FileUtils.mkdir_p(quality_root)
Dir.mktmpdir("blind-review-test-", quality_root) do |directory|
  inputs = File.join(directory, "inputs")
  FileUtils.mkdir_p(inputs)
  png = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  )
  files = %w[
    original.png yingjian-off.png yingjian.png yingjian-high.png
    yingjian-preview.png competitor.png
  ]
  files.each { |name| File.binwrite(File.join(inputs, name), png) }
  privacy_marker = "PRIVATE-CAMERA-METADATA"
  File.binwrite(
    File.join(inputs, "competitor.png"),
    png_with_text(png, "Comment", privacy_marker),
  )
  source_sha256 = Digest::SHA256.file(File.join(inputs, "original.png")).hexdigest

  plan = {
    "schema" => 1,
    "review_id" => "portrait-round-1",
    "task" => "portrait",
    "minimum_reviewers" => 5,
    "items" => [
      {
        "asset_id" => "portrait-001",
        "tags" => ["portrait_single", "improvable"],
        "candidates" => files.map do |name|
          path = File.join(inputs, name)
          {
            "id" => File.basename(name, ".png"),
            "role" => name == "original.png" ? "baseline_original" : (name == "competitor.png" ? "reference" : "subject"),
            "file" => path,
            "sha256" => Digest::SHA256.file(path).hexdigest,
            "provenance" => if name == "original.png"
              {
                "producer" => "original",
                "version" => "source-v1",
                "device" => "fixture-device",
                "os" => "fixture-os",
                "variant" => "original",
                "render_kind" => "source",
                "parameters" => {},
              }
            elsif name == "competitor.png"
              {
                "producer" => "competitor",
                "version" => "1.2.3",
                "device" => "fixture-device",
                "os" => "fixture-os",
                "variant" => "fixed_path",
                "render_kind" => "export",
                "parameters" => { "preset" => "natural" },
                "operation_path" => "preset natural, strength 50",
                "source_sha256" => source_sha256,
              }
            else
              variant = name.include?("-off") ? "off" : (name.include?("-high") ? "high_safe" : "default")
              {
                "producer" => "yingjian",
                "version" => "ios-v2-fixture",
                "device" => "fixture-device",
                "os" => "fixture-os",
                "variant" => variant,
                "render_kind" => name.include?("preview") ? "preview" : "export",
                "parameters" => { "strength" => variant == "off" ? 0 : 50 },
                "source_sha256" => source_sha256,
              }
            end,
          }
        end,
      },
    ],
  }
  plan_path = File.join(directory, "plan.yaml")
  File.write(plan_path, plan.to_yaml)

  first_output = File.join(directory, "review-a")
  stdout, stderr, status = Open3.capture3(
    "ruby",
    builder,
    plan_path,
    first_output,
    "--seed",
    "fixed-seed",
  )
  assert(status.success?, "builder failed: #{stdout}#{stderr}")
  participant_package = File.join(first_output, "participant-package")
  assert(File.file?(File.join(participant_package, "index.html")), "review page missing")
  assert(File.file?(File.join(participant_package, "score-sheet.csv")), "score sheet missing")
  assert(File.file?(File.join(first_output, "review-key.json")), "review key missing")
  assert(
    !File.exist?(File.join(participant_package, "review-key.json")),
    "participant package contains the identity key",
  )

  review_page = File.read(File.join(participant_package, "index.html"))
  assert(review_page.include?("原图锚点"), "participant cannot identify the baseline anchor")
  assert(!review_page.include?("portrait-001"), "page leaked the source asset id")
  %w[original yingjian competitor].each do |candidate_id|
    assert(!review_page.include?(candidate_id), "page leaked candidate #{candidate_id}")
  end

  missing_slots = [
    ["off", "export"], ["default", "export"], ["high_safe", "export"],
    ["default", "preview"], ["fixed_path", "export"],
  ]
  missing_slots.each_with_index do |(variant, render_kind), index|
    incomplete_plan = Marshal.load(Marshal.dump(plan))
    incomplete_plan["items"].first["candidates"].reject! do |candidate|
      candidate.dig("provenance", "variant") == variant &&
        candidate.dig("provenance", "render_kind") == render_kind
    end
    incomplete_path = File.join(directory, "incomplete-plan-#{index}.yaml")
    File.write(incomplete_path, incomplete_plan.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", builder, incomplete_path, File.join(directory, "incomplete-matrix-#{index}"),
      "--seed", "fixed-seed",
    )
    assert(!status.success?, "incomplete #{variant} #{render_kind} matrix was accepted")
    assert(stderr.include?(variant), "matrix failure did not identify missing #{variant} #{render_kind}")
  end

  bad_source_plan = Marshal.load(Marshal.dump(plan))
  bad_source_plan["items"].first["candidates"].find do |candidate|
    candidate["role"] == "subject"
  end["provenance"]["source_sha256"] = "0" * 64
  bad_source_path = File.join(directory, "bad-source-plan.yaml")
  File.write(bad_source_path, bad_source_plan.to_yaml)
  _stdout, stderr, status = Open3.capture3(
    "ruby", builder, bad_source_path, File.join(directory, "bad-source-review"),
    "--seed", "fixed-seed",
  )
  assert(!status.success?, "incorrect source_sha256 was accepted")
  assert(stderr.include?("source_sha256"), "source hash failure was not explicit")

  missing_operation_plan = Marshal.load(Marshal.dump(plan))
  missing_operation_plan["items"].first["candidates"].find do |candidate|
    candidate["role"] == "reference"
  end["provenance"].delete("operation_path")
  missing_operation_path = File.join(directory, "missing-operation-plan.yaml")
  File.write(missing_operation_path, missing_operation_plan.to_yaml)
  _stdout, stderr, status = Open3.capture3(
    "ruby", builder, missing_operation_path, File.join(directory, "missing-operation-review"),
    "--seed", "fixed-seed",
  )
  assert(!status.success?, "competitor without operation_path was accepted")
  assert(stderr.include?("operation_path"), "operation path failure was not explicit")

  mismatched_default_plan = Marshal.load(Marshal.dump(plan))
  mismatched_default_plan["items"].first["candidates"].find do |candidate|
    candidate.dig("provenance", "variant") == "default" &&
      candidate.dig("provenance", "render_kind") == "preview"
  end["provenance"]["parameters"] = { "strength" => 49 }
  mismatched_default_path = File.join(directory, "mismatched-default-plan.yaml")
  File.write(mismatched_default_path, mismatched_default_plan.to_yaml)
  _stdout, stderr, status = Open3.capture3(
    "ruby", builder, mismatched_default_path, File.join(directory, "mismatched-default-review"),
    "--seed", "fixed-seed",
  )
  assert(!status.success?, "mismatched default preview/export parameters were accepted")
  assert(stderr.include?("share parameters"), "default parameter mismatch was not explicit")

  second_output = File.join(directory, "review-b")
  _stdout, stderr, status = Open3.capture3(
    "ruby",
    builder,
    plan_path,
    second_output,
    "--seed",
    "fixed-seed",
  )
  assert(status.success?, "second deterministic build failed: #{stderr}")
  assert(
    File.read(File.join(first_output, "review-key.json")) ==
      File.read(File.join(second_output, "review-key.json")),
    "same seed produced a different review key",
  )

  key = JSON.parse(File.read(File.join(first_output, "review-key.json")))
  item = key.fetch("items").first
  key_subject = item.fetch("candidates").find { |candidate| candidate["candidate_id"] == "yingjian" }
  plan_subject = plan.fetch("items").first.fetch("candidates").find { |candidate| candidate["id"] == "yingjian" }
  assert(key_subject["provenance"] == plan_subject["provenance"], "candidate provenance was not preserved in the key")
  sanitized_images = Dir.glob(File.join(participant_package, "images", "*.png"))
  assert(sanitized_images.none? { |path| File.binread(path).include?(privacy_marker) }, "private metadata leaked into participant images")
  selected = item.fetch("candidates").find { |candidate| candidate["candidate_id"] == "yingjian" }
  score_path = File.join(directory, "scores.csv")
  score_headers = %w[
    reviewer_id item_code baseline_code candidate_code overall_improvement naturalness
    identity_preservation texture_preservation skin_tone_lighting local_boundaries
    non_skin_protection catastrophic_error preferred_over_baseline notes
  ]
  CSV.open(score_path, "w") do |csv|
    csv << score_headers
    baseline = item.fetch("candidates").find { |candidate| candidate["role"] == "baseline_original" }
    5.times do |index|
      csv << [
        "reviewer-#{index + 1}", item["item_code"], baseline["candidate_code"],
        selected["candidate_code"],
        5, 5, 5, 5, 5, 5, 5, false, true, nil,
      ]
    end
  end
  stdout, stderr, status = Open3.capture3(
    "ruby",
    score_checker,
    File.join(first_output, "review-key.json"),
    score_path,
    "--candidate",
    "yingjian",
  )
  assert(!status.success?, "one-item review incorrectly passed the freeze gate")
  assert(stderr.include?("item count"), "coverage failure was not explicit")

  expanded_plan = Marshal.load(Marshal.dump(plan))
  expanded_plan["review_id"] = "portrait-round-complete"
  expanded_plan["items"] = 48.times.map do |index|
    tags = if index < 36
      ["portrait_single", "improvable"]
    else
      ["negative_safety"]
    end
    tags << %w[deep_skin beard freckles_moles glasses makeup][index % 5]
    candidates = Marshal.load(Marshal.dump(plan["items"].first["candidates"]))
    baseline_hash = nil
    candidates.each_with_index do |candidate, candidate_index|
      raster_index = index * candidates.length + candidate_index
      candidate_path = File.join(
        inputs,
        format("asset-%03d-candidate-%02d.png", index + 1, candidate_index + 1),
      )
      File.binwrite(
        candidate_path,
        rgba_png(raster_index & 0xff, (raster_index >> 8) & 0xff, (raster_index * 17) & 0xff),
      )
      candidate["file"] = candidate_path
      candidate["sha256"] = Digest::SHA256.file(candidate_path).hexdigest
      if candidate["role"] == "baseline_original"
        baseline_hash = candidate["sha256"]
      end
    end
    candidates.reject { |candidate| candidate["role"] == "baseline_original" }.each do |candidate|
      candidate["provenance"]["source_sha256"] = baseline_hash
    end
    {
      "asset_id" => format("asset-%03d", index + 1),
      "tags" => tags,
      "candidates" => candidates,
    }
  end
  expanded_plan_path = File.join(directory, "expanded-plan.yaml")
  File.write(expanded_plan_path, expanded_plan.to_yaml)
  expanded_output = File.join(directory, "expanded-review")
  stdout, stderr, status = Open3.capture3(
    "ruby", builder, expanded_plan_path, expanded_output,
    "--seed", "complete-seed",
  )
  assert(status.success?, "complete review package failed: #{stdout}#{stderr}")
  expanded_key_path = File.join(expanded_output, "review-key.json")
  key = JSON.parse(File.read(expanded_key_path))
  expanded_items = key.fetch("items")
  CSV.open(score_path, "w") do |csv|
    csv << score_headers
    5.times do |reviewer_index|
      expanded_items.each do |expanded_item|
        expanded_baseline = expanded_item["candidates"].find do |candidate|
          candidate["role"] == "baseline_original"
        end
        expanded_selected = expanded_item["candidates"].find do |candidate|
          candidate["candidate_id"] == "yingjian"
        end
        csv << [
          "reviewer-#{reviewer_index + 1}", expanded_item["item_code"],
          expanded_baseline["candidate_code"], expanded_selected["candidate_code"],
          5, 5, 5, 5, 5, 5, 5, false, true, nil,
        ]
      end
    end
  end
  stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, expanded_key_path, score_path,
    "--candidate", "yingjian",
  )
  assert(status.success?, "complete passing scores were rejected: #{stdout}#{stderr}")
  assert(stdout.include?("passed"), "passing result did not report its state")

  code_tampered_key = Marshal.load(Marshal.dump(key))
  code_tampered_key["items"].first["candidates"].find do |candidate|
    candidate["candidate_id"] == "yingjian"
  end["candidate_code"] = "C99"
  code_tampered_path = File.join(directory, "code-tampered-review-key.json")
  File.write(code_tampered_path, JSON.pretty_generate(code_tampered_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, code_tampered_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "tampered candidate_code passed the score gate")
  assert(stderr.include?("anonymous mapping"), "candidate-code mapping failure was not explicit")

  item_code_tampered_key = Marshal.load(Marshal.dump(key))
  item_code_tampered_key["items"].first["item_code"] = "I999"
  item_code_tampered_path = File.join(directory, "item-code-tampered-review-key.json")
  File.write(item_code_tampered_path, JSON.pretty_generate(item_code_tampered_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, item_code_tampered_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "tampered item_code passed the score gate")
  assert(stderr.include?("anonymous mapping"), "item-code mapping failure was not explicit")

  duplicate_raster_output = File.join(directory, "duplicate-raster-review")
  FileUtils.cp_r(expanded_output, duplicate_raster_output)
  duplicate_raster_key_path = File.join(duplicate_raster_output, "review-key.json")
  duplicate_raster_key = JSON.parse(File.read(duplicate_raster_key_path))
  baselines = duplicate_raster_key["items"].first(2).map do |expanded_item|
    expanded_item["candidates"].find { |candidate| candidate["role"] == "baseline_original" }
  end
  first_raster = File.join(
    duplicate_raster_output, "participant-package", baselines[0]["review_file"],
  )
  second_raster = File.join(
    duplicate_raster_output, "participant-package", baselines[1]["review_file"],
  )
  FileUtils.cp(second_raster, first_raster)
  baselines[0]["normalized_raster_sha256"] = Digest::SHA256.file(first_raster).hexdigest
  File.write(duplicate_raster_key_path, JSON.pretty_generate(duplicate_raster_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, duplicate_raster_key_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "duplicate normalized baseline pixels passed the score gate")
  assert(stderr.include?("normalized raster slot"), "normalized-raster uniqueness failure was not explicit")

  replaced_subject_output = File.join(directory, "replaced-subject-review")
  FileUtils.cp_r(expanded_output, replaced_subject_output)
  replaced_subject_key_path = File.join(replaced_subject_output, "review-key.json")
  replaced_subject_key = JSON.parse(File.read(replaced_subject_key_path))
  replaced_item = replaced_subject_key["items"].first
  replaced_subject = replaced_item["candidates"].find do |candidate|
    candidate["candidate_id"] == "yingjian"
  end
  replacement_reference = replaced_item["candidates"].find do |candidate|
    candidate["role"] == "reference"
  end
  subject_review_path = File.join(
    replaced_subject_output, "participant-package", replaced_subject["review_file"],
  )
  reference_review_path = File.join(
    replaced_subject_output, "participant-package", replacement_reference["review_file"],
  )
  FileUtils.cp(reference_review_path, subject_review_path)
  replaced_subject["normalized_raster_sha256"] = Digest::SHA256.file(subject_review_path).hexdigest
  replaced_subject["normalized_pixel_sha256"] = replacement_reference["normalized_pixel_sha256"]
  File.write(replaced_subject_key_path, JSON.pretty_generate(replaced_subject_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, replaced_subject_key_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "competitor pixels substituted for the subject passed the score gate")
  assert(stderr.include?("normalized source candidate"), "source-to-review binding failure was not explicit")

  wrong_baseline_scores = File.join(directory, "wrong-baseline-scores.csv")
  wrong_baseline_rows = CSV.read(score_path, headers: true)
  wrong_baseline_rows[0]["baseline_code"] = "C99"
  CSV.open(wrong_baseline_scores, "w") do |csv|
    csv << score_headers
    wrong_baseline_rows.each { |row| csv << row.fields }
  end
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, expanded_key_path, wrong_baseline_scores,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "incorrect baseline_code passed the score gate")
  assert(stderr.include?("original anchor"), "baseline-code failure was not explicit")

  overlapping_key = Marshal.load(Marshal.dump(key))
  overlapping_key["items"].find do |expanded_item|
    expanded_item["tags"].include?("portrait_single")
  end["tags"] << "negative_safety"
  overlapping_key_path = File.join(directory, "overlapping-review-key.json")
  File.write(overlapping_key_path, JSON.pretty_generate(overlapping_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, overlapping_key_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "overlapping portrait and negative-safety coverage passed")
  assert(stderr.include?("overlap"), "coverage-overlap failure was not explicit")

  tampered_key = Marshal.load(Marshal.dump(key))
  tampered_key["items"] = Marshal.load(Marshal.dump(expanded_items))
  tampered_key["items"].first["candidates"].find do |candidate|
    candidate["role"] == "subject"
  end["provenance"]["source_sha256"] = "0" * 64
  tampered_key_path = File.join(directory, "tampered-review-key.json")
  File.write(tampered_key_path, JSON.pretty_generate(tampered_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, tampered_key_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "tampered candidate provenance passed the score gate")
  assert(stderr.include?("source_sha256"), "provenance failure was not explicit")

  missing_matrix_key = Marshal.load(Marshal.dump(key))
  missing_matrix_key["items"] = Marshal.load(Marshal.dump(expanded_items))
  missing_matrix_key["items"].first["candidates"].reject! do |candidate|
    candidate.dig("provenance", "variant") == "high_safe"
  end
  missing_matrix_path = File.join(directory, "missing-matrix-review-key.json")
  File.write(missing_matrix_path, JSON.pretty_generate(missing_matrix_key))
  _stdout, stderr, status = Open3.capture3(
    "ruby", score_checker, missing_matrix_path, score_path,
    "--candidate", "yingjian",
  )
  assert(!status.success?, "tampered candidate matrix passed the score gate")
  assert(stderr.include?("high_safe"), "score-gate matrix failure was not explicit")

  rows = CSV.read(score_path, headers: true)
  rows[0]["catastrophic_error"] = "true"
  CSV.open(score_path, "w") do |csv|
    csv << score_headers
    rows.each { |row| csv << row.fields }
  end
  _stdout, stderr, status = Open3.capture3(
    "ruby",
    score_checker,
    expanded_key_path,
    score_path,
    "--candidate",
    "yingjian",
  )
  assert(!status.success?, "catastrophic result passed the quality gate")
  assert(stderr.include?("catastrophic"), "catastrophic failure was not explicit")

  FileUtils.rm_f(File.join(inputs, "competitor.png"))
  _stdout, stderr, status = Open3.capture3(
    "ruby",
    builder,
    plan_path,
    File.join(directory, "invalid-review"),
    "--seed",
    "fixed-seed",
  )
  assert(!status.success?, "missing candidate file was accepted")
  assert(stderr.include?("is missing"), "missing-file error was not stable")

  Dir.mktmpdir("blind-review-external-") do |external|
    external_image = File.join(external, "external.png")
    File.binwrite(external_image, png)
    linked_image = File.join(inputs, "linked-external.png")
    File.symlink(external_image, linked_image)
    plan["items"].first["candidates"].last["file"] = linked_image
    plan["items"].first["candidates"].last["sha256"] =
      Digest::SHA256.file(external_image).hexdigest
    File.write(plan_path, plan.to_yaml)
    _stdout, stderr, status = Open3.capture3(
      "ruby", builder, plan_path, File.join(directory, "linked-input-review"),
      "--seed", "fixed-seed",
    )
    assert(!status.success?, "symlinked external image was accepted")
    assert(stderr.include?(".quality"), "external-link failure was not explicit")

    linked_output = File.join(directory, "linked-output")
    File.symlink(external, linked_output)
    _stdout, stderr, status = Open3.capture3(
      "ruby", builder, plan_path, linked_output, "--seed", "fixed-seed",
    )
    assert(!status.success?, "symlinked external output was accepted")
    assert(stderr.include?(".quality"), "output-link failure was not explicit")
  end
end

puts "Blind review tool tests passed."

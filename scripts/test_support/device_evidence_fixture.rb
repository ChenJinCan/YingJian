# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "time"
require "yaml"

module DeviceEvidenceFixture
  module_function

  TEAM_ID = "V86Q54AQQU"
  BUNDLE_ID = "com.babycompany.yingjian"

  def plist(dict)
    body = dict.map do |key, value|
      encoded = case value
                when String then "<string>#{value}</string>"
                when Array then "<array>#{value.map { |item| "<string>#{item}</string>" }.join}</array>"
                when true then "<true/>"
                when false then "<false/>"
                when Hash
                  "<dict>#{value.map { |nested_key, nested_value| "<key>#{nested_key}</key>#{nested_value == true ? '<true/>' : nested_value == false ? '<false/>' : "<string>#{nested_value}</string>"}" }.join}</dict>"
                else raise "unsupported fixture plist value"
                end
      "<key>#{key}</key>#{encoded}"
    end.join
    %(<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>#{body}</dict></plist>)
  end

  def create_profile_ipa(repo_root:, directory:, source_commit:, device_udids:)
    source = File.join(directory, "ios-profile-source")
    app = File.join(source, "Payload", "Runner.app")
    assets = File.join(app, "Frameworks", "App.framework", "flutter_assets")
    FileUtils.mkdir_p(assets)
    info = plist(
      "CFBundleIdentifier" => BUNDLE_ID,
      "CFBundleShortVersionString" => "0.1.0",
      "CFBundleVersion" => "1",
      "CFBundleExecutable" => "Runner",
      "DTPlatformName" => "iphoneos",
      "CFBundleSupportedPlatforms" => ["iPhoneOS"],
      "MinimumOSVersion" => "15.0",
      "UIDeviceFamily" => ["1", "2"],
      "NSPhotoLibraryUsageDescription" => "Select photos",
      "NSPhotoLibraryAddUsageDescription" => "Save photos",
    ).sub("<string>1</string><string>2</string>", "<integer>1</integer><integer>2</integer>")
    File.write(File.join(app, "Info.plist"), info)
    FileUtils.cp(File.join(repo_root, "ios", "Runner", "GoogleService-Info.plist"), app)
    required = %w[
      Runner Assets.car Frameworks/App.framework/App
      Frameworks/App.framework/flutter_assets/AssetManifest.bin
      Frameworks/App.framework/flutter_assets/NOTICES.Z
      Frameworks/App.framework/flutter_assets/assets/legal/privacy_en.md
      Frameworks/App.framework/flutter_assets/assets/legal/privacy_zh.md
      Frameworks/App.framework/flutter_assets/assets/legal/terms_en.md
      Frameworks/App.framework/flutter_assets/assets/legal/terms_zh.md
      Frameworks/App.framework/flutter_assets/assets/build/source-commit.txt
    ]
    required.each do |relative|
      path = File.join(app, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "fixture")
    end
    File.write(
      File.join(app, "Frameworks", "App.framework", "flutter_assets", "assets", "build", "source-commit.txt"),
      "#{source_commit}\n",
    )
    File.write(File.join(app, "embedded.mobileprovision"), "fixture")

    profile = plist(
      "TeamIdentifier" => [TEAM_ID],
      "ExpirationDate" => "2099-01-01T00:00:00Z",
      "ProvisionedDevices" => device_udids,
      "Entitlements" => {
        "application-identifier" => "#{TEAM_ID}.#{BUNDLE_ID}",
        "com.apple.developer.team-identifier" => TEAM_ID,
        "get-task-allow" => true,
      },
    )
    entitlements = plist(
      "application-identifier" => "#{TEAM_ID}.#{BUNDLE_ID}",
      "com.apple.developer.team-identifier" => TEAM_ID,
      "get-task-allow" => true,
    )
    File.write(File.join(directory, "fixture-profile.plist"), profile)
    File.write(File.join(directory, "fixture-entitlements.plist"), entitlements)
    bin = File.join(directory, "fixture-bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "security"), "#!/bin/sh\ncat '#{File.join(directory, 'fixture-profile.plist')}'\n")
    File.write(File.join(bin, "codesign"), "#!/bin/sh\nif [ \"$1\" = \"-d\" ]; then cat '#{File.join(directory, 'fixture-entitlements.plist')}'; fi\nexit 0\n")
    FileUtils.chmod(0o755, [File.join(bin, "security"), File.join(bin, "codesign")])
    ENV["YINGJIAN_DEVICE_EVIDENCE_TEST"] = "1"
    ENV["YINGJIAN_TEST_TOOL_DIRECTORY"] = bin

    ipa = File.join(directory, "ios-profile-build.ipa")
    _output, error, status = Open3.capture3("zip", "-qry", ipa, "Payload", chdir: source)
    raise "fixture IPA creation failed: #{error}" unless status.success?

    ipa
  end

  def device_capture_record(repo_root:, identifier:, udid:, model:, product_type:)
    device_list = {
      "info" => {
        "commandType" => "devicectl.list.devices", "jsonVersion" => 3,
        "outcome" => "success",
      },
      "result" => {
        "devices" => [{
          "identifier" => identifier,
          "connectionProperties" => {
            "pairingState" => "paired", "tunnelState" => "connected",
          },
          "deviceProperties" => {
            "developerModeStatus" => "enabled", "ddiServicesAvailable" => true,
            "osVersionNumber" => "26.5.2",
          },
          "hardwareProperties" => {
            "deviceType" => "iPhone", "marketingName" => model,
            "platform" => "iOS", "productType" => product_type, "reality" => "physical",
            "udid" => udid,
          },
        }],
      },
    }
    {
      "schema" => 1,
      "captured_at" => Time.now.utc.iso8601,
      "host_id" => Digest::SHA256.hexdigest("fixture-host"),
      "collector" => {
        "file" => "scripts/capture_ios_device_evidence.rb",
        "sha256" => Digest::SHA256.file(File.join(repo_root, "scripts", "capture_ios_device_evidence.rb")).hexdigest,
        "xcrun" => "/usr/bin/xcrun",
        "devicectl_version" => "fixture-devicectl",
      },
      "selected_device_id" => Digest::SHA256.hexdigest(identifier),
      "device_list" => device_list,
      "installed_apps" => {
        "info" => {
          "commandType" => "devicectl.device.info.apps", "jsonVersion" => 3,
          "outcome" => "success",
        },
        "result" => {
          "apps" => [{
            "bundleIdentifier" => BUNDLE_ID,
            "bundleVersion" => "1",
            "bundleShortVersionString" => "0.1.0",
          }],
        },
      },
    }
  end

  def build(repo_root:, directory:, source_commit:)
    coverage = {
      "low" => %w[12mp portrait_single six_photo_group],
      "mid" => %w[12mp 24mp display_p3 heic six_photo_group],
      "high" => %w[48mp portrait_multi six_photo_batch],
    }
    device_udids = 3.times.map { |index| "fixture-udid-#{index}" }
    build_file = create_profile_ipa(
      repo_root: repo_root, directory: directory, source_commit: source_commit,
      device_udids: device_udids
    )
    build_sha = Digest::SHA256.file(build_file).hexdigest
    build = {
      "mode" => "profile",
      "source_commit" => source_commit,
      "bundle_id" => "com.babycompany.yingjian",
      "version" => "0.1.0",
      "build_number" => "1",
      "artifact_sha256" => build_sha,
    }
    models = {
      "low" => ["iPhone 11", "iPhone12,1", 4_096],
      "mid" => ["iPhone 14 Plus", "iPhone14,8", 6_144],
      "high" => ["iPhone 15 Pro", "iPhone16,1", 8_192],
    }
    runs = %w[low mid high].map.with_index do |tier, index|
      run_id = "ios-#{tier}-fixture"
      run_directory = File.join(directory, run_id)
      FileUtils.mkdir_p(run_directory)
      outcomes = %w[
        source_hash_unchanged final_artifacts_valid three_batch_rounds_completed
        no_system_kill background_restore low_memory_restore cancellation_recover
        offline_journey diagnostics_disabled cloud_image_tasks_zero accessibility_task_completed
        system_share_success system_share_cancel system_share_failure
      ].to_h { |name| [name, true] }
      measurements = {
        "first_preview_ms" => Array.new(5, 500),
        "six_photo_recommendations_ms" => Array.new(5, 1_000),
        "slider_response_ms" => Array.new(20, 30),
        "continuous_preview_fps" => Array.new(20, 60),
        "export_12mp_ms" => Array.new(3, 1_000),
        "batch_six_12mp_ms" => Array.new(3, 5_000),
        "ui_main_thread_stalls_ms" => Array.new(20, 10),
        "peak_additional_memory_mb" => 100,
        "thermal_states" => %w[nominal fair],
        "thermal_mitigation_activated" => false,
      }
      measurements["export_24mp_ms"] = Array.new(3, 2_000) if tier == "mid"
      measurements["export_48mp_ms"] = Array.new(3, 4_000) if tier == "high"
      methodology = {
        "timing_tool" => "fixture monotonic trace parser",
        "memory_tool" => "fixture resident-memory sampler",
        "frame_tool" => "fixture frame-timing callback",
        "thermal_tool" => "fixture platform thermal monitor",
        "lifecycle_protocol" => "fixture background low-memory cancel protocol",
      }
      metrics_file = File.join(run_directory, "metrics.json")
      probe_file = File.join(run_directory, "final-artifacts.json")
      device_capture_file = File.join(run_directory, "devicectl-device.json")
      device_identifier = "fixture-core-device-#{index}"
      model, hardware_class, memory = models.fetch(tier)
      File.write(device_capture_file, JSON.pretty_generate(device_capture_record(
        repo_root: repo_root, identifier: device_identifier,
        udid: device_udids.fetch(index), model: model, product_type: hardware_class
      )))
      File.write(metrics_file, JSON.pretty_generate(
        "schema" => 1,
        "run_id" => run_id,
        "methodology" => methodology,
        "measurements" => measurements,
        "outcomes" => outcomes,
      ))
      File.write(probe_file, JSON.pretty_generate(
        "schema" => 1,
        "run_id" => run_id,
        "source_commit" => source_commit,
        "probed_output_count" => 6,
        "checks" => %w[
          orientation dimensions crop srgb jpeg_quality_95 capture_time
          sensitive_metadata_removed source_hash_unchanged
        ].to_h { |name| [name, true] },
      ))
      artifacts = [
        ["build_artifact", build_file],
        ["device_capture", device_capture_file],
        ["metrics_log", metrics_file],
        ["final_artifact_probe", probe_file],
      ].map do |kind, file|
        {
          "kind" => kind,
          "file" => Pathname.new(file).relative_path_from(Pathname.new(repo_root)).to_s,
          "sha256" => Digest::SHA256.file(file).hexdigest,
        }
      end
      {
        "run_id" => run_id,
        "platform" => "ios",
        "tier" => tier,
        "device" => {
          "device_id" => Digest::SHA256.hexdigest(device_identifier),
          "model" => model,
          "hardware_class" => hardware_class,
          "os_version" => "iOS 26.5.2",
          "tier_basis" => "frozen fixture tier #{tier}",
          "physical_memory_mb" => memory,
          "physical" => true,
        },
        "build" => build.dup,
        "coverage" => coverage.fetch(tier),
        "methodology" => methodology,
        "measurements" => measurements,
        "outcomes" => outcomes,
        "artifacts" => artifacts,
      }
    end
    manifest = {
      "schema" => 1,
      "status" => "ready",
      "source_commit" => source_commit,
      "runs" => runs,
    }
    manifest_path = File.join(directory, "device-evidence.yaml")
    File.write(manifest_path, YAML.dump(manifest))
    {
      manifest: manifest,
      manifest_path: manifest_path,
      selected_run: runs.find { |run| run["tier"] == "mid" },
    }
  end
end

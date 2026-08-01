#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "open3"
require "pathname"
require "time"
require "yaml"

def fail_contract(message)
  warn "Release contract failed: #{message}"
  exit 1
end

def load_policy(path)
  value = YAML.safe_load(path.read, permitted_classes: [], aliases: false)
  fail_contract("#{path} must contain a YAML mapping") unless value.is_a?(Hash)

  value
rescue Psych::Exception => error
  fail_contract("invalid YAML in #{path}: #{error.message}")
end

def semver(value, label)
  match = /\A(\d+)\.(\d+)\.(\d+)\z/.match(value.to_s)
  fail_contract("#{label} must use x.y.z format") unless match

  match.captures.map(&:to_i)
end

def positive_integer(value, label, allow_zero: false)
  number = value.is_a?(Integer) ? value : Integer(value, 10)
  minimum = allow_zero ? 0 : 1
  fail_contract("#{label} must be at least #{minimum}") if number < minimum

  number
rescue ArgumentError, TypeError
  fail_contract("#{label} must be an integer")
end

def required_mapping(value, label)
  fail_contract("#{label} must be a nonempty mapping") unless value.is_a?(Hash) && !value.empty?

  value
end

def required_string(mapping, key, label)
  value = mapping[key].to_s.strip
  fail_contract("#{label}.#{key} must be nonempty") if value.empty?

  value
end

def required_string_array(mapping, key, label)
  value = mapping[key]
  unless value.is_a?(Array) && !value.empty? &&
         value.all? { |entry| entry.is_a?(String) && !entry.strip.empty? }
    fail_contract("#{label}.#{key} must be a nonempty string list")
  end

  value
end

def validate_policy(policy)
  fail_contract("schema_version must be 2") unless policy["schema_version"] == 2
  required_string(required_mapping(policy["app"], "app"), "id", "app")

  packaging = required_mapping(policy["packaging"], "packaging")
  fail_contract("packaging.mode must be local_only") unless packaging["mode"] == "local_only"

  identity = required_mapping(policy["identity"], "identity")
  unless identity["version_rule"] == "reuse_testing_else_patch_public"
    fail_contract("identity.version_rule must be reuse_testing_else_patch_public")
  end
  unless identity["build_rule"] == "global_latest_plus_one"
    fail_contract("identity.build_rule must be global_latest_plus_one")
  end

  baseline = required_mapping(policy["baseline"], "baseline")
  positive_integer(baseline["max_age_minutes"], "baseline.max_age_minutes")

  source = required_mapping(policy["source"], "source")
  unless source["require_clean_worktree"] == true &&
         source["require_upstream_sync"] == true
    fail_contract("source must require a clean worktree and upstream sync")
  end

  platforms = required_mapping(policy["platforms"], "platforms")
  platforms.each do |name, platform|
    label = "platforms.#{name}"
    platform = required_mapping(platform, label)
    required_string(platform, "identifier", label)
    unless [true, false].include?(platform["release_ready"])
      fail_contract("#{label}.release_ready must be true or false")
    end
    required_string(platform, "env_file", label)
    required_string(platform, "env_example", label)
    required_string_array(platform, "required_tools", label)
    required_string_array(platform, "required_env", label)
    required_string_array(platform, "forbidden_env", label)
  end
end

def parse_env_file(path)
  entries = {}
  path.each_line.with_index(1) do |line, line_number|
    stripped = line.strip
    next if stripped.empty? || stripped.start_with?("#")

    match = /\A(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/.match(stripped)
    fail_contract("#{path}:#{line_number} is not a KEY=value assignment") unless match

    entries[match[1]] = match[2]
  end
  entries
end

def capture_git(root, *args)
  output, error, status = Open3.capture3("git", "-C", root.to_s, *args)
  fail_contract("git #{args.join(' ')} failed: #{error.strip}") unless status.success?

  output.strip
end

command = ARGV.shift
fail_contract("command must be validate-config, validate-env, validate-candidate, or validate-source") unless
  %w[validate-config validate-env validate-candidate validate-source].include?(command)

options = {
  root: File.expand_path("..", __dir__),
  config: nil
}

OptionParser.new do |parser|
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--config PATH") { |value| options[:config] = value }
  parser.on("--platform NAME") { |value| options[:platform] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--build NUMBER") { |value| options[:build] = value }
  parser.on("--public-version VERSION") { |value| options[:public_version] = value }
  parser.on("--remote-latest-version VERSION") { |value| options[:remote_latest_version] = value }
  parser.on("--remote-latest-build NUMBER") { |value| options[:remote_latest_build] = value }
  parser.on("--verified-at TIMESTAMP") { |value| options[:verified_at] = value }
  parser.on("--source-commit SHA") { |value| options[:source_commit] = value }
end.parse!

root = Pathname.new(options[:root]).expand_path
config_path = options[:config] ? Pathname.new(options[:config]).expand_path : root.join("release", "release-policy.yaml")
fail_contract("missing release policy #{config_path}") unless config_path.file?

policy = load_policy(config_path)
validate_policy(policy)

case command
when "validate-config"
  puts "Release contract valid: #{policy.dig('app', 'id')}."
when "validate-env"
  platform_name = options[:platform].to_s
  platform = policy.dig("platforms", platform_name)
  fail_contract("unsupported platform #{platform_name.inspect}") unless platform.is_a?(Hash)
  fail_contract("#{platform_name} release packaging is not ready") unless platform["release_ready"] == true

  env_path = root.join(platform.fetch("env_file"))
  fail_contract("missing ignored environment file #{env_path}") unless env_path.file?

  entries = parse_env_file(env_path)
  platform.fetch("forbidden_env").each do |name|
    if entries.key?(name)
      fail_contract("#{env_path} must not define release identity variable #{name}")
    end
  end
  platform.fetch("required_env").each do |name|
    value = entries[name].to_s.strip
    fail_contract("#{env_path} must define required variable #{name}") if value.empty?
  end

  puts "Release environment structure valid for #{platform_name}."
when "validate-candidate"
  platform_name = options[:platform].to_s
  platform = policy.dig("platforms", platform_name)
  fail_contract("unsupported platform #{platform_name.inspect}") unless platform.is_a?(Hash)
  fail_contract("#{platform_name} release packaging is not ready") unless platform["release_ready"] == true

  version = options[:version].to_s
  public_version = options[:public_version].to_s
  remote_latest_version = options[:remote_latest_version].to_s
  version_parts = semver(version, "version")
  public_parts = semver(public_version, "public version")
  remote_latest_version_parts = semver(remote_latest_version, "remote latest version")
  remote_vs_public = remote_latest_version_parts <=> public_parts
  if remote_vs_public == -1
    fail_contract("remote latest version #{remote_latest_version} is lower than public version #{public_version}")
  end

  expected_version_parts = if remote_vs_public == 1
                             remote_latest_version_parts
                           else
                             [public_parts[0], public_parts[1], public_parts[2] + 1]
                           end
  expected_version = expected_version_parts.join(".")
  unless version_parts == expected_version_parts
    if remote_vs_public == 1
      fail_contract("testing version #{remote_latest_version} must be reused; candidate version must be #{expected_version}")
    end

    fail_contract("public version #{public_version} is already online; candidate version must be #{expected_version}")
  end

  build = positive_integer(options[:build], "build")
  remote_latest = positive_integer(
    options[:remote_latest_build],
    "remote latest build",
    allow_zero: true
  )
  expected_build = remote_latest + 1
  unless build == expected_build
    fail_contract("build #{build} must equal remote latest build #{remote_latest} + 1")
  end

  begin
    verified_at = Time.iso8601(options[:verified_at].to_s).utc
  rescue ArgumentError
    fail_contract("verified-at must be an ISO-8601 timestamp")
  end
  age_seconds = Time.now.utc - verified_at
  max_age_seconds = positive_integer(
    policy.dig("baseline", "max_age_minutes"),
    "baseline.max_age_minutes"
  ) * 60
  fail_contract("online baseline timestamp is in the future") if age_seconds < -300
  fail_contract("online baseline is older than #{max_age_seconds / 60} minutes") if age_seconds > max_age_seconds

  puts "Release candidate valid: #{platform_name} #{version} (#{build}), public #{public_version}, remote latest version #{remote_latest_version}, remote latest build #{remote_latest}."
when "validate-source"
  platform_name = options[:platform].to_s
  platform = policy.dig("platforms", platform_name)
  fail_contract("unsupported platform #{platform_name.inspect}") unless platform.is_a?(Hash)
  fail_contract("#{platform_name} release packaging is not ready") unless platform["release_ready"] == true

  requested_commit = options[:source_commit].to_s
  fail_contract("source-commit is required") if requested_commit.empty?

  head = capture_git(root, "rev-parse", "HEAD")
  fail_contract("source commit #{requested_commit} does not match HEAD #{head}") unless requested_commit == head

  status = capture_git(root, "status", "--porcelain", "--untracked-files=all")
  fail_contract("release worktree must be clean") unless status.empty?

  capture_git(root, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
  counts = capture_git(root, "rev-list", "--left-right", "--count", "HEAD...@{u}").split.map(&:to_i)
  unless counts == [0, 0]
    fail_contract("release branch must exactly match its upstream; ahead=#{counts[0]} behind=#{counts[1]}")
  end

  platform.fetch("required_tools").each do |tool|
    _output, _error, status_result = Open3.capture3("sh", "-c", "command -v \"$1\" >/dev/null", "release-contract", tool)
    fail_contract("required tool #{tool} is unavailable") unless status_result.success?
  end

  puts "Release source valid: #{head} is clean and synchronized."
end

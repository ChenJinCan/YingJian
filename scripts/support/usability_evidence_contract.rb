# frozen_string_literal: true

require_relative "device_evidence_contract"

module UsabilityEvidenceContract
  MANIFEST_SCHEMA = 2
  SESSION_SCHEMA = 2
  REQUIRED_TASKS = %w[
    import_photos
    review_three_recommendations
    select_recommendation
    adjust_group
    adjust_current_photo
    undo_edit
    redo_edit
    compare_before_after
    return_to_group
    restore_project
    export_photos
  ].freeze
  TARGET_USER_DEFINITION_VERSION = "first-target-user-v1"
  TARGET_USER_REQUIRED_CRITERIA = %w[
    frequently_takes_mobile_photos
    publishes_multiple_photos
    wants_quality_without_professional_workflow
    willing_to_micro_adjust_from_reliable_start
  ].freeze
  BUILD_IDENTITY_FIELDS = %w[
    mode source_commit bundle_id version build_number artifact_sha256
  ].freeze

  module_function

  def task_results(session)
    tasks = session["tasks"]
    return {} unless tasks.is_a?(Array)

    tasks.each_with_object({}) do |task, results|
      next unless task.is_a?(Hash) && REQUIRED_TASKS.include?(task["id"])

      results[task["id"]] = task["completed"] unless results.key?(task["id"])
    end
  end

  def task_contract_valid?(session)
    tasks = session["tasks"]
    tasks.is_a?(Array) &&
      tasks.map { |task| task.is_a?(Hash) ? task["id"] : nil } == REQUIRED_TASKS &&
      tasks.all? { |task| [true, false].include?(task["completed"]) }
  end

  def completed?(session)
    results = task_results(session)
    REQUIRED_TASKS.all? { |task_id| results[task_id] == true }
  end

  def scope_understood?(session)
    responses = session["responses"]
    responses.is_a?(Hash) && responses["group_scope"] == "correct" &&
      responses["current_photo_scope"] == "correct"
  end

  def target_user?(session)
    protocol = session["protocol"]
    return false unless protocol.is_a?(Hash) && protocol["eligibility_attested_by_observer"] == true

    eligibility = protocol["target_user_eligibility"]
    eligibility.is_a?(Hash) && eligibility.keys.sort == TARGET_USER_REQUIRED_CRITERIA.sort &&
      TARGET_USER_REQUIRED_CRITERIA.all? { |criterion| eligibility[criterion] == true }
  end
end

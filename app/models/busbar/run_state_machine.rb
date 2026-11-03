module Busbar
  # The run lifecycle from docs/spec.md. Any working state can fail; a failed
  # run resumes from the stage it failed in.
  class RunStateMachine
    include Statesman::Machine

    state :received, initial: true
    state :preparing
    state :rejected
    state :awaiting_mapping
    state :staging
    state :validating
    state :ready
    state :cancelled
    state :loading
    state :completed
    state :completed_with_errors
    state :failed

    WORKING = %w[received preparing awaiting_mapping staging validating ready loading].freeze
    FINISHED = %w[rejected cancelled completed completed_with_errors failed].freeze

    transition from: :received, to: %i[preparing failed]
    transition from: :preparing, to: %i[rejected awaiting_mapping staging failed]
    transition from: :awaiting_mapping, to: %i[staging cancelled failed]
    transition from: :staging, to: %i[validating failed]
    transition from: :validating, to: %i[ready loading failed]
    transition from: :ready, to: %i[loading cancelled failed]
    transition from: :loading, to: %i[completed completed_with_errors failed]
    transition from: :failed, to: %i[preparing staging validating loading cancelled]

    after_transition do |run, transition|
      run.update_columns(state: transition.to_state, updated_at: Time.current)
    end
  end
end

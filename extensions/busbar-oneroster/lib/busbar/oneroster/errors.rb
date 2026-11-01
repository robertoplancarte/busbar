# frozen_string_literal: true

module Busbar
  module OneRoster
    class Error < StandardError; end

    # Raised when a package cannot be processed at all. `problems` lists every
    # reason found, so the client gets one complete report instead of a drip.
    class PackageError < Error
      attr_reader :problems

      def initialize(problems)
        @problems = Array(problems)
        super(@problems.join("; "))
      end
    end

    class ValueError < Error; end
  end
end

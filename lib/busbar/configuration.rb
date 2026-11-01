require "active_support/core_ext/integer/time"

module Busbar
  # Host-facing settings, set from config/initializers/busbar.rb. Defaults
  # follow docs/spec.md; settings for later phases are accepted now so host
  # initializers do not change as features land.
  class Configuration
    attr_accessor :tenant_class, :tenant_column, :current_user, :authorize, :layout,
                  :storage_service, :chunk_size, :load_batch_size, :retention,
                  :max_upload_size, :mapping_suggester, :after_ingestion,
                  :sftp_provider, :sftpgo, :pgp_private_key, :ops_email

    def initialize
      @tenant_class = "Account"
      @tenant_column = :account_id
      @current_user = -> { nil }
      @authorize = ->(_user, _action, _record) { true }
      @layout = "busbar/application"
      @storage_service = nil # nil uses the host's default ActiveStorage service
      @chunk_size = 5_000
      @load_batch_size = 1_000
      @retention = 30.days
      @max_upload_size = 500 * 1024 * 1024
      @mapping_suggester = nil
      @after_ingestion = {}
      @sftp_provider = :sftpgo
      @sftpgo = {}
      @pgp_private_key = nil
      @ops_email = nil
    end
  end
end

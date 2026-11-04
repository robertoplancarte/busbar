require "active_support/core_ext/integer/time"

module Busbar
  # Host-facing settings, set from config/initializers/busbar.rb. Defaults
  # follow docs/spec.md; settings for later phases are accepted now so host
  # initializers do not change as features land.
  class Configuration
    attr_accessor :current_user, :authorize, :layout, :parent_controller,
                  :storage_service, :chunk_size, :load_batch_size, :retention,
                  :max_upload_size, :mapping_suggester, :after_ingestion,
                  :sftp_provider, :sftpgo, :pgp_private_key, :ops_email, :user_class
    attr_writer :tenant_column
    attr_reader :tenant_class

    def initialize
      @tenant_class = nil
      @tenant_column = nil
      @current_user = -> { nil }
      # Deny until the host says otherwise: an engine that can overwrite user
      # records must not be open to everyone who can reach its routes.
      @authorize = ->(_user, _action, _record) { false }
      @layout = "busbar/application"
      @parent_controller = "::ApplicationController"
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
      @user_class = nil # e.g. "User", to show who uploaded and approved a run
    end

    # The host's tenant model, e.g. "Tenant" or "Account". Required.
    def tenant_class=(name)
      @tenant_class = name&.to_s
    end

    # The tenant foreign key on the host's own tables. Defaults to the tenant
    # class name with _id ("Tenant" -> :tenant_id), the acts_as_tenant default.
    def tenant_column
      (@tenant_column || (tenant_class && "#{tenant_class.demodulize.underscore}_id"))&.to_sym
    end
  end
end

module Busbar
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    # Engine tables always name their tenant foreign key tenant_id, whatever
    # the host calls it on its own tables (Busbar.config.tenant_column).
    def self.busbar_tenant_scoped
      acts_as_tenant :tenant, class_name: Busbar.config.tenant_class || raise(ConfigurationError, "Set Busbar.config.tenant_class"),
                              foreign_key: :tenant_id
    end
  end
end

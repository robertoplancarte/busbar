require "rails/generators"
require "rails/generators/active_record"

module Busbar
  module Generators
    # bin/rails g busbar:install [--tenant-class=Tenant] [--tenant-column=tenant_id] [--user-class=User]
    #
    # Writes the engine migration, the initializer and the mount route.
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :tenant_class, type: :string, default: "Tenant", desc: "The host's tenant model"
      class_option :tenant_column, type: :string, default: nil, desc: "Tenant foreign key on host tables (default: <tenant>_id)"
      class_option :user_class, type: :string, default: "User", desc: "The host's user model"
      class_option :mount_path, type: :string, default: "/busbar"

      def self.next_migration_number(dirname) = ActiveRecord::Generators::Base.next_migration_number(dirname)

      def check_tenant_model
        return if tenant_class.safe_constantize

        say_status :warning, "#{tenant_class} is not defined yet; the migration references the #{tenant_table} table", :yellow
      end

      def copy_migration
        migration_template "create_busbar_tables.rb.tt", "db/migrate/create_busbar_tables.rb"
      end

      def create_initializer
        template "initializer.rb.tt", "config/initializers/busbar.rb"
      end

      def mount_engine
        route %(mount Busbar::Engine, at: "#{options[:mount_path]}")
      end

      def check_active_storage
        schema = File.join(destination_root, "db", "schema.rb")
        installed = Dir[File.join(destination_root, "db", "migrate", "*active_storage*")].any? ||
                    (File.exist?(schema) && File.read(schema).include?("active_storage_blobs"))
        say_status :warning, "BusBar keeps files in ActiveStorage: run bin/rails active_storage:install", :yellow unless installed
      end

      def show_next_steps
        say "\nNext: bin/rails db:migrate, set Busbar.config.authorize, then bin/rails busbar:check", :green
      end

      private

      def tenant_class = options[:tenant_class].camelize
      def tenant_table = tenant_class.tableize.tr("/", "_")
      def tenant_column = (options[:tenant_column].presence || "#{tenant_class.demodulize.underscore}_id")
      def user_class = options[:user_class].camelize
      def migration_version = "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
    end
  end
end

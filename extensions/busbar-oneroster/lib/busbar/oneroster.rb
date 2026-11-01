# frozen_string_literal: true

require_relative "oneroster/version"
require_relative "oneroster/errors"
require_relative "oneroster/file_specs"
require_relative "oneroster/values"
require_relative "oneroster/manifest"
require_relative "oneroster/row_converter"
require_relative "oneroster/package_reader"

module Busbar
  # OneRoster 1.2 CSV support for the BusBar engine.
  #
  # Adding the gem to a host's Gemfile is enough: when the engine finishes
  # loading it runs the :busbar load hook, and this gem registers its schemas,
  # templates, transform and package handler there.
  module OneRoster
  end
end

if defined?(ActiveSupport) && ActiveSupport.respond_to?(:on_load)
  ActiveSupport.on_load(:busbar) do
    require_relative "oneroster/extension"
    Busbar::OneRoster::Extension.register!(self)
  end
end

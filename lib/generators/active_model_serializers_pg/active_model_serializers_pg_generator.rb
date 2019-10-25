require 'rails/generators'

module ActiveModelSerializersPg
  module Generators
    class ActiveModelSerializersPgGenerator < Rails::Generators::NamedBase
      Rails::Generators::ResourceHelpers

      # The ORM generator assumes you're passing a name argument,
      # but we don't need one, so we give it a default value:
      argument :name, type: :string, default: "ignored"
      source_root File.expand_path("../templates", __FILE__)

      namespace :active_model_serializers_pg
      hook_for :orm, required: true, name: "ignored"

      desc "Creates an active_model_serialiers_pg database migration"

    end
  end
end

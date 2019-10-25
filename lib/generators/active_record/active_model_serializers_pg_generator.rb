require 'rails/generators/active_record'

module ActiveRecord
  module Generators
    class ActiveModelSerializersPgGenerator < ActiveRecord::Generators::Base
      argument :name, type: :string, default: "ignored"
      source_root File.expand_path("../templates", __FILE__)

      def write_migration
        migration_template "migration.rb", "#{migration_path}/ams_pg_create_dasherize_functions.rb"
      end

      private

      def read_sql(funcname)
        File.read(File.join(File.expand_path('../templates', __FILE__), "#{funcname}.sql"))
      end

      def migration_exists?(table_name)
        Dir.glob("#{File.join destination_root, migration_path}/[0-9]*_*.rb").grep(/\d+_ams_pg_create_dasherize_functions.rb$/).first
      end

      def migration_path
        if Rails.version >= '5.0.3'
          db_migrate_path
        else
          @migration_path ||= File.join "db", "migrate"
        end
      end

      def migration_version
        if Rails.version.start_with? '5'
          "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
        end
      end

      def jsonb_dasherize
        read_sql('jsonb_dasherize')
      end

    end
  end
end

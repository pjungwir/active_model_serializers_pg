require 'spec_helper'
require 'generators/active_model_serializers_pg/active_model_serializers_pg_generator'

describe ActiveModelSerializersPg::Generators::ActiveModelSerializersPgGenerator, type: :generator do
  destination File.expand_path "../../../tmp", __FILE__

  before :each do
    prepare_destination
  end

  it "creates the migration file" do
    run_generator
    expect(destination_root).to have_structure {
      directory "db" do
        directory "migrate" do
          migration "ams_pg_create_dasherize_functions" do
            contains "class AmsPgCreateDasherizeFunctions"
          end
        end
      end
    }
  end
end

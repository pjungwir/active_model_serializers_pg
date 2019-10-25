class AmsPgCreateDasherizeFunctions < ActiveRecord::Migration<%= migration_version %>

  def up
    execute %q{<%= jsonb_dasherize %>}
  end

  def down
    execute "DROP FUNCTION jsonb_dasherize(jsonb)"
  end

end

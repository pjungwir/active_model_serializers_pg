require 'uri'
require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'spec'
  t.pattern = 'spec/**/*_spec.rb'
  t.verbose = false
end

task :default => :test

task :setup do
  if File.exist?('.env')
    puts 'This will overwrite your existing .env file'
  end

  default_db_name = 'active_model_serializers_pg_test'
  default_db_host = 'localhost'
  default_db_port = '5432'

  print "Enter your database name: [#{default_db_name}] "
  db_name = STDIN.gets.chomp
  print 'Enter your database user: [] '
  db_user = STDIN.gets.chomp
  print 'Enter your database password: [] '
  db_password = STDIN.gets.chomp
  print "Enter your database host: [#{default_db_host}] "
  db_host = STDIN.gets.chomp
  print "Enter your database port: [#{default_db_port}] "
  db_port = STDIN.gets.chomp

  db_name = default_db_name if db_name.empty?
  db_password = ":#{URI.escape(db_password)}" unless db_password.empty?
  db_ = default_db_host if db_host.empty?

  db_user_at = db_user.empty? ? '' : '@'
  db_port_colon = db_port.empty? ? '' : ':'

  env_path = File.expand_path('./.env')
  File.open(env_path, 'w') do |file|
    file.puts "DATABASE_NAME=#{db_name}"
    file.puts "DATABASE_PORT=#{db_port}"
    file.puts "DATABASE_URL=\"postgres://#{db_user}#{db_password}#{db_user_at}#{db_host}#{db_port_colon}#{db_port}/#{db_name}\""
  end

  puts '.env file saved'
end

namespace :db do
  task :load_db_settings do
    require 'active_record'
    unless ENV['DATABASE_URL']
      require 'dotenv'
      Dotenv.load
    end
  end

  task :psql => :load_db_settings do
    exec "psql -p #{ENV['DATABASE_PORT']} #{ENV['DATABASE_NAME']}"
  end

  task :drop => :load_db_settings do
    %x{ dropdb -p #{ENV['DATABASE_PORT']} #{ENV['DATABASE_NAME']} }
  end

  task :create => :load_db_settings do
    %x{ createdb -p #{ENV['DATABASE_PORT']} #{ENV['DATABASE_NAME']} }
  end

  task :migrate => :load_db_settings do
    ActiveRecord::Base.establish_connection

    ActiveRecord::Base.connection.execute "CREATE EXTENSION hstore"

    ActiveRecord::Base.connection.create_table :people, force: true do |t|
      t.string   "first_name"
      t.string   "last_name"
      t.json     "options"
      t.jsonb    "prefs"
      t.hstore   "settings"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :notes, force: true do |t|
      t.string   "name"
      t.string   "content"
      t.integer  "state", null: false, default: 0
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :long_notes, force: true do |t|
      t.string   "name"
      t.text     "long_content"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :tags, force: true do |t|
      t.integer  "note_id"
      t.string   "name"
      t.boolean  "popular"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :long_tags, force: true do |t|
      t.integer  "long_note_id"
      t.string   "long_name"
      t.boolean  "popular"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :offers, force: true do |t|
      t.integer  "created_by_id"
      t.integer  "reviewed_by_id"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :users, force: true do |t|
      t.string   "name"
      t.string   "mobile"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.create_table :addresses, force: true do |t|
      t.string   "district_name"
      t.integer  "user_id"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    ActiveRecord::Base.connection.execute File.read(File.expand_path('../lib/generators/active_record/templates/jsonb_dasherize.sql', __FILE__))

    puts 'Database migrated'
  end
end

namespace :test do
  desc 'Test against all supported ActiveRecord versions'
  task :all do
    # Escape current bundler environment
    Bundler.with_clean_env do
      # Currently only supports Active Record v5.0-v5.2
      %w(5.0.x 5.1.x 5.2.x).each do |version|
        sh "BUNDLE_GEMFILE='gemfiles/Gemfile.activerecord-#{version}' bundle install --quiet"
        sh "BUNDLE_GEMFILE='gemfiles/Gemfile.activerecord-#{version}' bundle exec rspec spec"
      end
    end
  end
end

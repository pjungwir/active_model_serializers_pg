# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_model_serializers_pg/version'

Gem::Specification.new do |spec|
  spec.name          = "active_model_serializers_pg"
  spec.version       = ActiveModelSerializersPg::VERSION
  spec.authors       = ["Paul A. Jungwirth"]
  spec.email         = ["pj@illuminatedcomputing.com"]
  spec.summary       = %q{Harness the power of PostgreSQL when crafting JSON reponses}
  spec.description   = %q{}
  spec.homepage      = "https://github.com/pjungwir/active_model_serializers_pg"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency     'active_model_serializers', '~> 0.10.8'
  spec.add_runtime_dependency     'activerecord', '~> 5.0'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'actionpack', '> 4.0'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-rails'
  spec.add_development_dependency 'generator_spec'
  spec.add_development_dependency 'bourne', '~> 1.3.0'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'dotenv'
  if RUBY_PLATFORM =~ /java/
    spec.add_development_dependency 'activerecord-jdbcpostgresql-adapter', '1.3.0.beta2'
  else
    spec.add_development_dependency 'pg', '~> 0.15'
  end
end

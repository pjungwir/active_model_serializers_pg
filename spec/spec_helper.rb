require 'active_record'
require 'action_controller'
require 'rspec'
require 'bourne'
require 'database_cleaner'
require 'active_model_serializers'
require 'action_controller/serialization'
require 'active_model_serializers_pg'
if ENV['TEST_UNPATCHED_AMS']
  ActiveModelSerializers.config.adapter = :json_api
else
  ActiveModelSerializers.config.adapter = :json_api_pg
end
unless ENV['CI']
  begin
    require 'pry'
    require 'pry-highlight'
    require 'pry-byebug' unless RUBY_PLATFORM =~ /java/
  rescue LoadError => e
    STDERR.puts "spec/spec_helper.rb:#{__LINE__}: #{e.message}"
  end
end

require 'dotenv'
Dotenv.load

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

class TestController < ActionController::Base
  include ActionController::Serialization
  def url_options
    {}
  end
  def current_user
    nil
  end
end

class Person < ActiveRecord::Base
  def self.full_name__sql
    "first_name || ' ' || last_name"
  end
end

class PeopleController < TestController; end

class PersonSerializer < ActiveModel::Serializer
  attributes :id, :full_name, :attendance_name

  def attendance_name__sql
    if current_user && current_user[:admin]
      "'ADMIN ' || last_name || ', ' || first_name"
    else
      "last_name || ', ' || first_name"
    end
  end
end

class Note < ActiveRecord::Base
  has_many :tags
  has_many :sorted_tags
  has_many :custom_sorted_tags, lambda { order(:name) }, class_name: 'Tag'
  has_many :popular_tags, lambda { where(popular: true) }, class_name: 'Tag'
  Draft     = :draft
  Published = :published
  Deleted   = :deleted
  enum state: [Draft, Published, Deleted]
end

class NotesController < TestController; end

class NoteSerializer < ActiveModel::Serializer
  attributes :content, :name
  has_many   :tags
end

class NoteWithStateSerializer < ActiveModel::Serializer
  attributes :content, :name, :state
  has_many   :tags
end

class LongNote < ActiveRecord::Base
  has_many :long_tags
end

class LongNotesController < TestController; end

class LongNoteSerializer < ActiveModel::Serializer
  attributes :long_content, :name
  has_many :long_tags
end

class ShortTagSerializer < ActiveModel::Serializer
  attributes :id, :name
end

class SortedTagSerializer < ActiveModel::Serializer
  attributes :id, :name
end

class CustomKeyTagSerializer < ActiveModel::Serializer
  attributes :id, :name
  has_one :note, key: :tagged_note_id
end

class OtherNoteSerializer < ActiveModel::Serializer
  attributes :id, :name
  has_many   :tags, serializer: ShortTagSerializer, include: true
end

class CustomKeysNoteSerializer < ActiveModel::Serializer
  attributes :id, :name
  has_many   :tags, serializer: CustomKeyTagSerializer, include: true, key: :tag_names
end

class SortedTagsNoteSerializer < ActiveModel::Serializer
  attributes :id
  has_many   :sorted_tags
end

class CustomSortedTagsNoteSerializer < ActiveModel::Serializer
  attributes :id
  has_many   :custom_sorted_tags, serializer: ShortTagSerializer
end

class Tag < ActiveRecord::Base
  belongs_to :note
  alias :aliased_note :note
end

class SortedTag < Tag
  belongs_to :note
  default_scope { order(:name) }
end

class LongTag < ActiveRecord::Base
  belongs_to :long_note
end

class LongTagSerializer < ActiveModel::Serializer
  attributes :long_name
  belongs_to :long_note
end

class TagWithNote < Tag
  belongs_to :note
  default_scope { joins(:note) }
end

class TagsController < TestController; end

class TagSerializer < ActiveModel::Serializer
  attributes :id, :name
  has_one :note
end

class TagWithNoteSerializer < ActiveModel::Serializer
  attributes :id, :name
  has_one :note
end

class TagWithAliasedNoteSerializer < ActiveModel::Serializer
  attributes :name
  has_one :aliased_note
end

class User < ActiveRecord::Base
  has_many :offers, foreign_key: :created_by_id, inverse_of: :created_by
  has_many :reviewed_offers, foreign_key: :reviewed_by_id, inverse_of: :reviewed_by, class_name: 'Offer'
  has_one :address
end

class Address < ActiveRecord::Base
  belongs_to :user
end

class Offer < ActiveRecord::Base
  belongs_to :created_by, class_name: 'User', inverse_of: :offers
  belongs_to :reviewed_by, class_name: 'User', inverse_of: :reviewed_offers
end

class UsersController < TestController; end
class AddressController < TestController; end

class OfferSerializer < ActiveModel::Serializer
  attributes :id
end

class AddressSerializer < ActiveModel::Serializer
  attributes :id, :district_name
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :name, :mobile
  has_many :offers, serializer: OfferSerializer
  has_many :reviewed_offers, serializer: OfferSerializer
  has_one :address, serializer: AddressSerializer

  def include_mobile?
    current_user && current_user[:permission_id]
  end
  alias_method :include_address?, :include_mobile?
end

DatabaseCleaner.strategy = :deletion

RSpec.configure do |config|
  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end

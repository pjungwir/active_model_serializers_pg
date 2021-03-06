require 'spec_helper'

describe 'ArraySerializer' do
  # TODO: Run the tests with both adapters
  let(:adapter)      { :json_api_pg }
  let(:options)      { }
  let(:full_options) { (options || {}).merge(adapter: adapter) }
  let(:serializer)   { controller.get_serializer(relation, full_options) }
  # Take the string and cycle it through Ruby to remove whitespace inconsistencies:
  let(:json_data)    { JSON.parse(serializer.to_json).to_json }

  context 'specify serializer' do
    let(:relation)   { Note.all }
    let(:controller) { NotesController.new }
    let(:options)    { { each_serializer: OtherNoteSerializer } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note
    end

    it 'generates the proper json output' do
      json_expected = {
        data: [
          {
            id: @note.id.to_s,
            type: 'notes',
            attributes: {name: 'Title'},
            relationships: {tags: {data: [{id: @tag.id.to_s, type: 'tags'}]}},
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  # embed_key is no longer supported; I'm not sure about custom key:
=begin
  context 'custom key and embed_key' do
    let(:relation)   { Note.all }
    let(:controller) { NotesController.new }
    let(:options)    { { serializer: CustomKeysNoteSerializer } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note
    end

    it 'generates the proper json output' do
      json_expected = %{{"notes":[{"id":#{@note.id},"name":"Title","tag_names":["#{@tag.name}"]}],"tags":[{"id":#{@tag.id},"name":"My tag","tagged_note_id":#{@note.id}}]}}
      json_data.must_equal json_expected
    end
  end
=end

  context 'computed value methods' do
    let(:relation)   { Person.all }
    let(:controller) { PeopleController.new }
    let(:person)     { Person.create first_name: 'Test', last_name: 'User' }
    let(:options)    { }

    it 'generates the proper json output for the serializer' do
      json_expected = {
        data: [
          {
            id: person.id.to_s,
            type: 'people',
            attributes: { full_name: 'Test User', attendance_name: 'User, Test' },
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end

    it 'passes scope to the serializer method' do
      controller.stubs(:current_user).returns({ admin: true })

      json_expected = {
        data: [
          {
            id: person.id.to_s,
            type: 'people',
            attributes: {full_name: 'Test User', attendance_name: 'ADMIN User, Test'}
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'merging bind values' do
    let(:relation)   { Note.joins(:popular_tags).where(name: 'Title') }
    let(:controller) { NotesController.new }
    let(:options)    { }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      json_expected = {
        data: [
          {
            id: @note.id.to_s,
            type: 'notes',
            attributes: { name: 'Title', content: 'Test' },
            relationships: { tags: { data: [{id: @tag.id.to_s, type: 'tags'}] } }
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'serialize an array instead of a relation' do
    let(:relation)   { [Note.where(name: 'Title').first] }
    let(:controller) { NotesController.new }
    let(:options)    { }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      json_expected = {
        data: [
          {
            id: @note.id.to_s,
            type: 'notes',
            attributes: { name: 'Title', content: 'Test' },
            relationships: { tags: { data: [{id: @tag.id.to_s, type: 'tags'}] } }
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'serialize an empty array' do
    let(:relation)   { [] }
    let(:controller) { NotesController.new }
    let(:options)    { }

    it 'generates the proper json output' do
      json_expected = { data: [] }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'serialize singular record' do
    let(:relation)   { Note.where(name: 'Title').first }
    let(:controller) { NotesController.new }
    let(:options)    { }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      json_expected = {
        data: {
          id: @note.id.to_s,
          type: 'notes',
          attributes: { name: 'Title', content: 'Test' },
          relationships: { tags: { data: [{id: @tag.id.to_s, type: 'tags'}] } }
        }
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'with dasherized keys and types' do
    let(:relation)   { LongNote.where(name: 'Title').first }
    let(:controller) { LongNotesController.new }
    let(:options)    { { include: ['long_tags'] } }

    before do
      @note = LongNote.create long_content: 'Test', name: 'Title'
      @tag = LongTag.create long_name: 'My tag', long_note: @note, popular: true
      @old_key_setting = ActiveModelSerializers.config.key_transform
      ActiveModelSerializers.config.key_transform = :dash
    end

    after do
      ActiveModelSerializers.config.key_transform = @old_key_setting
    end

    it 'generates the proper json output' do
      json_expected = {
        data: {
          id: @note.id.to_s,
          type: 'long-notes',
          attributes: { name: 'Title', 'long-content' => 'Test' },
          relationships: { 'long-tags': { data: [{id: @tag.id.to_s, type: 'long-tags'}] } }
        },
        included: [
          {
            id: @tag.id.to_s,
            type: 'long-tags',
            attributes: { 'long-name' => 'My tag' },
            relationships: { 'long-note' => { data: { id: @note.id.to_s, type: 'long-notes' } } },
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'with dasherized json columns' do
    let(:relation)   { Person.all }
    let(:controller) { PeopleController.new }
    let(:person)     {
      Person.create first_name: 'Test',
                    last_name: 'User',
                    options:    { 'foo_foo': 'baz', barBar: [{ 'jar_jar': 'binks' }] },
                    prefs:      { 'foo_foo': 'baz', barBar: [{ 'jar_jar': 'binks' }] },
                    settings:   { 'foo_foo': 'bar' },
                    selfies:    [ { 'photo_resolution': '200x200' } ],
                    portraits:  [ { 'photo_resolution': '150x200' } ],
                    landscapes: [ { 'photo_resolution': '200x150' } ]
    }
    let(:options)    { { each_serializer: PersonWithJsonSerializer } }

    before do
      @old_key_setting = ActiveModelSerializers.config.key_transform
      ActiveModelSerializers.config.key_transform = :dash
    end

    after do
      ActiveModelSerializers.config.key_transform = @old_key_setting
    end

    it 'generates the proper json output' do
      json_expected = {
        data: [
          {
            id: person.id.to_s,
            type: 'people',
            attributes: {
              prefs: {
                'bar-bar': [{ 'jar-jar' => 'binks'}],
                'foo-foo' => 'baz',
              },
              options: {
                'bar-bar': [{ 'jar-jar' => 'binks'}],
                'foo-foo' => 'baz',
              },
              selfies: [
                { 'photo-resolution' => '200x200' },
              ],
              settings: {
                'foo-foo' => 'bar'
              },
              portraits: [
                { 'photo-resolution' => '150x200' },
              ],
              landscapes: [
                { 'photo-resolution' => '200x150' },
              ],
            },
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'with aliased association' do
    let(:relation)   { Tag.first }
    let(:controller) { TagsController.new }
    let(:options)    { { serializer: TagWithAliasedNoteSerializer } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      json_expected = {
        data: {
          id: @tag.id.to_s,
          type: 'tags',
          attributes: { name: 'My tag' },
          relationships: { aliased_note: { data: {id: @note.id.to_s, type: 'notes'} } }
        }
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'with aliased attribute' do
    let(:relation)   { Tag.first }
    let(:controller) { TagsController.new }
    let(:options)    { { serializer: TagWithAliasedNameSerializer } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      json_expected = {
        data: {
          id: @tag.id.to_s,
          type: 'tags',
          attributes: { 'aliased_name' => 'My tag' },
          relationships: { note: { data: {id: @note.id.to_s, type: 'notes'} } }
        }
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'serialize single record with custom serializer' do
    let(:relation)   { Note.where(name: 'Title').first }
    let(:controller) { NotesController.new }
    let(:options)    { { serializer: OtherNoteSerializer } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note
    end

    it 'generates the proper json output' do
      json_expected = {
        data: {
          id: @note.id.to_s,
          type: 'notes',
          attributes: { name: 'Title' },
          relationships: { tags: { data: [{id: @tag.id.to_s, type: 'tags'}] } }
        }
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'forcing single record mode' do
    let(:relation)   { Note.where(name: 'Title').limit(1) }
    let(:controller) { NotesController.new }
    let(:options)    { { single_record: true } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      pending 'is the single_record option part of AMS or just the postgres_ext-serializers gem?'
      json_expected = {
        data: {
          id: @note.id.to_s,
          type: 'notes',
          attributes: { name: 'Title', content: 'Test' },
          relationships: { tags: { data: [{id: @tag.id.to_s, type: 'tags'}] } }
        }
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'forcing single record mode with custom root key' do
    let(:relation)   { Note.where(name: 'Title').limit(1) }
    let(:controller) { NotesController.new }
    let(:options)    { { single_record: true, root: :foo } }

    before do
      @note = Note.create content: 'Test', name: 'Title'
      @tag = Tag.create name: 'My tag', note: @note, popular: true
    end

    it 'generates the proper json output' do
      json_expected = {
        data: [
          {
            id: @note.id.to_s,
            type: 'notes',
            attributes: { name: 'Title', content: 'Test' },
            relationships: { tags: { data: [{id: @tag.id.to_s, type: 'tags'}] } }
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'no where clause on root relation' do
    let(:relation)   { Note.all }
    let(:controller) { NotesController.new }

    before do
      note_1 = Note.create name: 'test', content: 'dummy content'
      note_2 = Note.create name: 'test 2', content: 'dummy content'

      tag    = Tag.create name: 'tag 1', note_id: note_1.id
      Tag.create name: 'tag 2'
      @json_expected = {
        data: [
          {
            id: note_1.id.to_s,
            type: 'notes',
            attributes: { name: 'test', content: 'dummy content' },
            relationships: { tags: { data: [{id: tag.id.to_s, type: 'tags'}] } },
          },
          {
            id: note_2.id.to_s,
            type: 'notes',
            attributes: { name: 'test 2', content: 'dummy content' },
            relationships: { tags: { data: [] } }
          },
        ]
      }.to_json
    end

    it 'generates the proper json output for the serializer' do
      expect(json_data).to eq @json_expected
    end

    it 'does not instantiate ruby objects for relations' do
      # It would be nice to do this instead:
      #
      #     expect(relation).not_to receive(:load)
      #
      # or
      #
      #     expect(relation).not_to receive(:records)
      #
      # But that causes an infinite loop because rspec works by raising an exception,
      # and ActiveRecord notices that and wants to print an error message,
      # calling `inspect` on the Relation, which tries to load the relation, which....
      # The test still fails, but not in an articulate or informative way.
      # TODO: We could probably write our own customer matcher to work around that,
      # but this does the job for now:
      expect(ActiveModelSerializers::Adapter::JsonApiPg).not_to receive(:warn_about_collection_serializer)
      json_data
    end
  end

  context 'where clause on root relation' do
    let(:relation)   { Note.where(name: 'test') }
    let(:controller) { NotesController.new }

    before do
      note_1 = Note.create name: 'test', content: 'dummy content'
      note_2 = Note.create name: 'test 2', content: 'dummy content'

      tag    = Tag.create name: 'tag 1', note_id: note_1.id
      Tag.create name: 'tag 2', note_id: note_2.id
      @json_expected = {
        data: [
          {
            id: note_1.id.to_s,
            type: 'notes',
            attributes: { name: 'test', content: 'dummy content' },
            relationships: { tags: { data: [{id: tag.id.to_s, type: 'tags'}] } },
          }
        ]
      }.to_json
    end

    it 'generates the proper json output for the serializer' do
      expect(json_data).to eq @json_expected
    end

    it 'does not instantiate ruby objects for relations' do
      expect(ActiveModelSerializers::Adapter::JsonApiPg).not_to receive(:warn_about_collection_serializer)
      json_data
    end
  end

  context 'root relation has belongs_to association' do
    let(:relation)   { Tag.all }
    let(:controller) { TagsController.new }
    let(:options)    { { each_serializer: TagWithNoteSerializer, include: ['note'] } }

    before do
      note = Note.create content: 'Test', name: 'Title'
      tag = Tag.create name: 'My tag', note: note
      @json_expected = {
        data: [
          {
            id: tag.id.to_s,
            type: 'tags',
            attributes: { name: 'My tag' },
            relationships: { note: { data: { id: note.id.to_s, type: 'notes' } } },
          }
        ],
        included: [
          {
            id: note.id.to_s,
            type: 'notes',
            attributes: { name: 'Title', content: 'Test' },
            relationships: { tags: { data: [{id: tag.id.to_s, type: 'tags' }] } }
          }
        ]
      }.to_json
    end

    it 'generates the proper json output for the serializer' do
      expect(json_data).to eq @json_expected
    end

    it 'does not instantiate ruby objects for relations' do
      expect(ActiveModelSerializers::Adapter::JsonApiPg).not_to receive(:warn_about_collection_serializer)
      json_data
    end
  end

  context 'relation has multiple associates to the same table' do
    let(:relation)   { User.order(:id) }
    let(:controller) { UsersController.new }

    before do
      reviewer = User.create name: 'Peter'
      user = User.create name: 'John'
      offer = Offer.create created_by: user, reviewed_by: reviewer
      @json_expected = {
        data: [
          {
            id: reviewer.id.to_s,
            type: 'users',
            attributes: { name: 'Peter' },
            relationships: {
              offers: { data: [] },
              reviewed_offers: { data: [{id: offer.id.to_s, type: 'offers'}] },
            },
          },
          {
            id: user.id.to_s,
            type: 'users',
            attributes: { name: 'John' },
            relationships: {
              offers: { data: [{id: offer.id.to_s, type: 'offers'}] },
              reviewed_offers: { data: [] },
            },
          }
        ]
      }.to_json
    end

    it 'generates the proper json output for the serializer' do
      expect(json_data).to eq @json_expected
    end

    it 'does not instantiate ruby objects for relations' do
      expect(ActiveModelSerializers::Adapter::JsonApiPg).not_to receive(:warn_about_collection_serializer)
      json_data
    end
  end

  context 'empty data should return empty array not null' do
    let(:relation)   { Tag.all }
    let(:controller) { TagsController.new }
    let(:options)    { { each_serializer: TagWithNoteSerializer } }

    before do
      @json_expected = {data: []}.to_json
    end

    it 'generates the proper json output for the serializer' do
      expect(json_data).to eq @json_expected
    end

    it 'does not instantiate ruby objects for relations' do
      expect(ActiveModelSerializers::Adapter::JsonApiPg).not_to receive(:warn_about_collection_serializer)
      json_data
    end
  end

  context 'nested filtering support' do
    let(:relation)   { TagWithNote.where(notes: { name: 'Title' }) }
    let(:controller) { TagsController.new }

    before do
      note = Note.create content: 'Test', name: 'Title'
      tag = Tag.create name: 'My tag', note: note
      @json_expected = {
        data: [
          {
            id: tag.id.to_s,
            type: 'tag_with_notes',
            attributes: { name: 'My tag' },
            relationships: { note: { data: { id: note.id.to_s, type: 'notes' } } },
          }
        ]
      }.to_json
    end

    it 'generates the proper json output for the serializer' do
      expect(json_data).to eq @json_expected
    end

    it 'does not instantiate ruby objects for relations' do
      expect(ActiveModelSerializers::Adapter::JsonApiPg).not_to receive(:warn_about_collection_serializer)
      json_data
    end
  end

  context 'with enums' do
    let(:relation)   { Note.order(:id) }
    let(:controller) { NotesController.new }
    let(:options)    { { each_serializer: NoteWithStateSerializer, fields: { note: [:name, :state] } } }

    before do
      @note1 = Note.create content: 'Test', name: 'Title 1', state: Note::Published
      @note2 = Note.create content: 'Test', name: 'Title 2', state: Note::Deleted
    end

    it 'converts enum ints to strings' do
      json_expected = {
        data: [
          {
            id: @note1.id.to_s,
            type: 'notes',
            attributes: { name: 'Title 1', state: 'published' },
          },
          {
            id: @note2.id.to_s,
            type: 'notes',
            attributes: { name: 'Title 2', state: 'deleted' },
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'support for include_[attrbute]' do
    let(:relation)   { User.all }
    let(:controller) { UsersController.new }
    let(:options)    { { each_serializer: UserSerializer } }
    before           { @user = User.create name: 'John', mobile: "51111111" }

    it 'generates json for serializer when include_[attribute]? is true' do
      address = Address.create district_name: "mumbai", user_id: @user.id
      json_expected = {
        data: [
          {
            id: @user.id.to_s,
            type: 'users',
            attributes: {name: 'John', mobile: '51111111'},
            relationships: {
              offers: {data: []},
              address: {data: {id: address.id.to_s, type: 'addresses'}},
              reviewed_offers: {data: []},
            }
          }
        ]
      }.to_json

      controller.stubs(:current_user).returns({ permission_id: 1 })
      expect(json_data).to eq json_expected
    end

    it 'generates json for serializer when include_[attribute]? is false' do
      json_expected = {
        data: [
          {
            id: @user.id.to_s,
            type: 'users',
            attributes: {name: 'John'},
            relationships: {
              offers: {data: []},
              reviewed_offers: {data: []},
            }
          }
        ]
      }.to_json
      expect(json_data).to eq json_expected
    end
  end

  context 'respects order in default scope of has_many association' do
    let(:relation)   { Note.all }
    let(:controller) { NotesController.new }
    let(:options)    { { each_serializer: SortedTagsNoteSerializer } }

    before do
      note = Note.create name: 'test', content: 'dummy content'

      tag2 = Tag.create name: 'tag 2', note_id: note.id
      tag1 = Tag.create name: 'tag 1', note_id: note.id
      tag3 = Tag.create name: 'tag 3', note_id: note.id
      @json_expected = {
        data: [
          {
            id: note.id.to_s,
            type: 'notes',
            attributes: {},
            relationships: {
              sorted_tags: {
                data: [
                  {id: tag1.id.to_s, type: 'sorted_tags'},
                  {id: tag2.id.to_s, type: 'sorted_tags'},
                  {id: tag3.id.to_s, type: 'sorted_tags'},
                ]
              }
            }
          }
        ]
      }.to_json
    end

    it 'generates json output with correctly sorted tag ids and tags' do
      expect(json_data).to eq @json_expected
    end
  end

  context 'respects order in custom scope of has_many association' do
    let(:relation)   { Note.all }
    let(:controller) { NotesController.new }
    let(:options)    { { each_serializer: CustomSortedTagsNoteSerializer } }

    before do
      note = Note.create name: 'test', content: 'dummy content'

      tag2 = Tag.create name: 'tag 2', note_id: note.id
      tag1 = Tag.create name: 'tag 1', note_id: note.id
      tag3 = Tag.create name: 'tag 3', note_id: note.id
      @json_expected = {
        data: [
          {
            id: note.id.to_s,
            type: 'notes',
            attributes: {},
            relationships: {
              custom_sorted_tags: {
                data: [
                  {id: tag1.id.to_s, type: 'tags'},
                  {id: tag2.id.to_s, type: 'tags'},
                  {id: tag3.id.to_s, type: 'tags'},
                ]
              }
            }
          }
        ]
      }.to_json
    end

    it 'generates json output with correctly sorted tag ids and tags' do
      expect(json_data).to eq @json_expected
    end
  end

  context 'sideloads correct records with pagination on unordered relation' do
    let(:relation)   { Note.limit(1).offset(1) }
    let(:controller) { NotesController.new }
    let(:options)    { }

    before do
      note1 = Note.new name: 'note 1', content: 'dummy content'
      note2 = Note.new name: 'note 2', content: 'dummy content'
      note3 = Note.new name: 'note 3', content: 'dummy content'
      # Randomize physical table order of notes.
      [note1, note2, note3].shuffle.map(&:save)
      # Make predictable result by making sure note1 is the second physical record.
      note1.destroy
      note1 = Note.create id: note1.id, name: 'note 1', content: 'dummy content'
      note3.destroy
      note3 = Note.create id: note3.id, name: 'note 3', content: 'dummy content'

      tag1 = Tag.new name: 'tag 1', note_id: note1.id
      tag2 = Tag.new name: 'tag 2', note_id: note2.id
      tag3 = Tag.new name: 'tag 3', note_id: note3.id
      [tag1, tag2, tag3].shuffle.map(&:save)

      @json_expected = {
        data: [
          {
            id: note1.id.to_s,
            type: 'notes',
            attributes: {name: 'note 1', content: 'dummy content'},
            relationships: {tags: {data: [{id: tag1.id.to_s, type: 'tags'}]}},
          }
        ]
      }.to_json
    end

    it 'generates json output with matching tag ids and tags' do
      expect(json_data).to eq @json_expected
    end
  end

  pending 'obeys serializer option in has_many relationship'  # Does AMS 0.10 still support this?

  pending 'obeys :include option in serializer association'   # Does AMS 0.10 still support this?

  pending 'uses __sql methods for relationships'
end

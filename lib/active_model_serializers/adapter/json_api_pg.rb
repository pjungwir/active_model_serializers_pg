require 'active_model_serializers'

# We don't really need this
# because we try to inject our own CollectionSerializer,
# but keeping it lets us give a nice warning message
# instead of simply crashing:
module ActiveModel
  class Serializer
    class CollectionSerializer
      def element_serializer
        options[:serializer]
      end
    end
  end
end

module ActiveModelSerializers
  module Adapter
    class JsonApiPg < Base
      
      def initialize(serializer, options={})
        super
      end

      def to_json(options={})
        connection.select_value serializer_sql
      end

      def relation
        @relation ||= _relation
      end

      private

      def connection
        @connection ||= relation.connection
      end

      def _relation
        o = serializer.object
        case o
        when ActiveRecord::Relation
          o
        when Array
          # TODO: determine what class it is, even if the array is empty
          o.first.class.where(id: o.map(&:id))
        when ActiveRecord::Base
          o.class.where(id: o.id)
        else
          raise "not sure what to do with #{o.class}: #{o}"
        end
      end

      def serializer_sql
        # TODO: There should be a better way....
        opts = serializer.instance_variable_get("@options") || {}
        sql = JsonApiPgSql.new(serializer, relation, instance_options, opts)
        sql = sql.to_sql
        sql
      end

      def self.warn_about_collection_serializer
          msg = "You are using an ordinary AMS CollectionSerializer with the json_api_pg adapter, which probably means Rails is pointlessly loading all your ActiveRecord instances *and* running the build JSON-building query in Postgres."
          if Object.const_defined? 'Rails'
            Rails.logger.warn msg
          else
            puts "WARN: #{msg}"
          end
      end

    end
  end
end

# Each JsonThing is a struct
# collecting all the stuff we need to know
# about a model you want in the JSONAPI output.
#
# It has the ActiveRecord class,
# the name of the thing,
# and how to reach it from its parent.
# 
# The full_name param should be a dotted path
# like you'd pass to the `includes` option of ActiveModelSerializers,
# except it should *also* start with the name of the top-level entity.
#
# The reflection should be from the perspective of the parent,
# i.e. how you got here, not how you'd leave:
# "Reflection" seems to be the internal ActiveRecord lingo
# for a belongs_to or has_many relationship.
# (The public documentation calls these "associations",
# I think think older versions of Rails even used that internally,
# but nowadays the method names use "reflection".)
class JsonThing
  attr_reader :ar_class, :full_name, :name, :serializer, :serializer_options, :json_key, :json_type, :reflection, :parent, :cte_name
  delegate :table_name, :primary_key, to: :ar_class
  delegate :foreign_key, :belongs_to?, :has_many?, :has_one?, to: :reflection

  def initialize(ar_class, full_name, serializer=nil, serializer_options={}, reflection=nil, parent_json_thing=nil)
    @ar_class = ar_class
    @full_name = full_name
    @name = full_name.split('.').last
    @serializer = serializer || ActiveModel::Serializer.serializer_for(ar_class.new, {})
    @serializer_options = serializer_options

    # json_key and json_type might be the same thing, but not always.
    # json_key is the name of the belongs_to/has_many association,
    # and json_type is the name of the thing's class.
    @json_key = JsonThing.json_key(name)
    @json_type = JsonThing.json_key(ar_class.name.underscore.pluralize)

    @reflection = reflection
    @parent = parent_json_thing

    @cte_name = _cte_name
    @sql_methods = {}
  end

  # Constructs another JsonThing with this one as the parent, via `reflection_name`.
  # TODO: tests
  def from_reflection(reflection_name)
    refl = JsonApiReflection.new(reflection_name, ar_class, serializer)
    JsonThing.new(refl.klass, "#{full_name}.#{reflection_name}", nil, serializer_options, refl, self)
  end

  # Gets the attributes (i.e. scalar fields) on the AR class
  # as a Set of symbols.
  # TODO: tests
	def declared_attributes
    @declared_attributes ||= Set.new(@ar_class.attribute_types.keys.map(&:to_sym))
  end

  def enum?(field)
    @ar_class.attribute_types[field.to_s].is_a? ActiveRecord::Enum::EnumType
  end

  # Gets the reflections (aka associations) of the AR class
  # as a Hash from symbol to a subclass of ActiveRecord::Reflection.
  # TODO: tests
  def declared_reflections
    @declared_reflections ||= Hash[
      @ar_class.reflections.map{|k, v|
        [k.to_sym, v]
      }
    ]
  end

  # TODO: tests
  def self.json_key(k)
    # TODO: technically the serializer could have an option overriding the default:
    case ActiveModelSerializers.config.key_transform
    when :dash
      k.to_s.gsub('_', '-')
    else
      k.to_s
    end
  end

  def has_sql_method?(field)
    sql_method(field).present?
  end

  def sql_method(field)
    (@sql_methods[field] ||= _sql_method(field))[0]
  end

  private

  # This needs to be globally unique within the SQL query,
  # even if the same model class appears in different places
  # (e.g. a Book has_many :authors and has_many :reviewers,
  # but those are both of class User).
  # So we use the full_name to prevent conflicts.
  # But since Postgres table names have limited length,
  # we also hash that name to guarantee something short
  # (like how Rails migrations generate foreign key names).
  # TODO: tests
  def _cte_name
    if parent.nil?
      't'
    else
      "cte_#{Digest::SHA256.hexdigest(full_name).first(10)}"
    end
  end

  def _sql_method(field)
    m = "#{field}__sql".to_sym
    if ar_class.respond_to?(m)
      # We return an array so our caller can cache a negative result too:
      [ar_class.send(m)]
    elsif serializer.instance_methods.include? m
      ser = serializer.new(ar_class.new, serializer_options)
      [ser.send(m)]
    else
      [nil]
    end
  end

end

# Wraps what we know about a reflection.
# Includes the ActiveRecord::Reflection,
# the ActiveModel::Serializer::Reflection,
# and the JsonApiReflectionReceiver results
# (i.e. the contents of a has_many block from the serializer definition).
class JsonApiReflection

  attr_reader :name, :original_name, :ar_reflection, :serializer_reflection, :include_data, :links,
    :reflection_sql, :ar_class, :klass
  delegate :foreign_key, to: :ar_reflection

  # `ar_class` should be the *source* ActiveRecord class,
  # so that `ar_class.name` is one or more things of `klass`.
  def initialize(name, ar_class, serializer_class)
    @name = name
    @ar_class = ar_class
    @original_name = @ar_class.instance_method(name).original_name

    @serializer_reflection = serializer_class._reflections[name.to_sym]

    @ar_reflection = ar_class.reflections[name.to_s]
    @reflection_sql = nil
    if @ar_reflection.nil?
      # See if it's an alias:
      @ar_reflection = ar_class.reflections[@original_name.to_s]
    end
    if @ar_reflection.nil?
      m = "#{name}__sql".to_sym
      if ar_class.respond_to? m
        rel = ar_class.send(m)
        # Must be an ActiveRecord::Relation (or ActiveModel::Base) so we can determine klass
        @reflection_sql = rel
        @klass = ActiveRecord::Relation === rel ? rel.klass : rel
      else
        raise "Can't find an association named #{name} for class #{ar_class.name}"
      end
    else
      @klass = @ar_reflection.klass
    end
    @include_data = true
    @links = {}

    if serializer_reflection.try(:block).present?
      x = JsonApiReflectionReceiver.new(serializer_class)
      x.instance_eval &serializer_reflection.block
      @include_data = x.result_include_data
      @links = x.result_links
    end
  end

  def belongs_to?
    ar_reflection.is_a? ActiveRecord::Reflection::BelongsToReflection
    # TODO: fall back to AMS reflection
  end

  def has_many?
    ar_reflection.try(:is_a?, ActiveRecord::Reflection::HasManyReflection) ||
      serializer_reflection.is_a?(ActiveModel::Serializer::HasManyReflection)
  end

  def has_one?
    ar_reflection.is_a? ActiveRecord::Reflection::HasOneReflection
    # TODO: fall back to AMS reflection
  end

end

# We use this when a serializer has a reflection with a block argument,
# like this:
#
#     has_many :users do
#       include_data false
#       link(:related) { users_company_path(object) }
#     end
#
# The only way to find out what options get set in that block is to run it,
# so this class does that and records what is there.
class JsonApiReflectionReceiver
  include ActiveModelSerializers::SerializationContext::UrlHelpers

  attr_reader :serializer, :result_include_data, :result_links

  def initialize(serializer)
    @serializer = serializer
    @result_include_data = true
    @result_links = {}
  end

  def include_data(val)
    @result_include_data = val
  end

  # Users may pass either a string or a block,
  # so we accept both.
  def link(name, val=nil, &block)
    if not val.nil?
      @result_links[name] = val
    else
      lnk = ActiveModelSerializers::Adapter::JsonApi::Link.new(serializer.new(object), block)
      # TODO: Super hacky here, and only supports one level of path resources:
      template = lnk.as_json
      @result_links[name] = template.split("PARAM").map{|p| "'#{p}'"}
      # @result_links[name] = "CONCAT(template
      # @result_links[name] = instance_eval(&block)
    end
  end

  def object
    # TODO: Could even be a singleton
    JsonApiObjectProxy.new
  end

end

class JsonApiObjectProxy
  def to_param
    "PARAM"
  end
end

class JsonApiPgSql
  attr_reader :base_serializer, :base_relation

  def initialize(base_serializer, base_relation, instance_options, options)
    @base_relation = base_relation
    @instance_options = instance_options
    @options = options

    # Make a JsonThing for everything,
    # cached as the full_name:

    # Watch out: User.where is a Relation, but plain User is not:
    ar_class = ActiveRecord::Relation === base_relation ? base_relation.klass : base_relation

    case base_serializer
    when ActiveModel::Serializer::CollectionSerializer
      ActiveModelSerializers::Adapter::JsonApiPg.warn_about_collection_serializer
      base_serializer = base_serializer.element_serializer
      @many = true
    when ActiveModelSerializersPg::CollectionSerializer
      base_serializer = base_serializer.element_serializer
      @many = true
    else
      base_serializer = base_serializer.class
      @many = false
    end
    base_serializer ||= ActiveModel::Serializer.serializer_for(ar_class.new, options)
    @base_serializer = base_serializer

    base_name = ar_class.name.underscore.pluralize
    base_thing = JsonThing.new(ar_class, base_name, base_serializer, options)
    @fields_for = {}
    @attribute_fields_for = {}
    @reflection_fields_for = {}
    @json_things = {
      base: base_thing, # `base` is a sym but every other key is a string
    }
    @json_things[base_name] = base_thing
    # We don't need to add anything else to @json_things yet
    # because we'll lazy-build it via get_json_thing.
    # That lets us go as deep in the relationships as we need
    # without loading anything extra.
  end

  def get_json_thing(resource, field)
    refl_name = "#{resource.full_name}.#{field}"
    @json_things[refl_name] ||= resource.from_reflection(field)
  end

  def many?
    @many
  end

  def json_key(name)
    JsonThing.json_key(name)
  end

  # Given a JsonThing and the fields you want,
  # outputs the json column for a SQL SELECT clause.
  def select_resource_attributes(resource)
    fields = attribute_fields_for(resource)
    <<~EOQ
      jsonb_build_object(#{fields.map{|f| "'#{json_key(f)}', #{select_resource_attribute(resource, f)}"}.join(', ')})
    EOQ
  end

  # Returns SQL for one JSON value for the resource's 'attributes' object.
  # If a field is an enum then we convert it from an int to a string.
  # If a field has a #{field}__sql method on the ActiveRecord class,
  # we use that instead.
  def select_resource_attribute(resource, field)
    typ = resource.ar_class.attribute_types[field.to_s]
    if typ.is_a? ActiveRecord::Enum::EnumType
      <<~EOQ
        CASE #{typ.as_json['mapping'].map{|str, int| %Q{WHEN "#{resource.table_name}"."#{field}" = #{int} THEN '#{str}'}}.join("\n     ")} END
      EOQ
    elsif resource.has_sql_method?(field)
      resource.sql_method(field)
    else
      %Q{"#{resource.table_name}"."#{field}"}
    end
  end

  def select_resource_relationship_links(resource, reflection)
    reflection.links.map {|link_name, link_parts|
      <<~EOQ
        '#{link_name}', CONCAT(#{link_parts.join(%Q{, "#{resource.parent.table_name}"."#{resource.parent.primary_key}", })})
      EOQ
    }.join(",\n")
  end

  def select_resource_relationship(resource)
    if resource.belongs_to?
      fk = %Q{"#{resource.parent.table_name}"."#{resource.foreign_key}"}
      <<~EOQ
        '#{resource.json_key}',
        jsonb_build_object('data',
                           CASE WHEN #{fk} IS NULL THEN NULL
                                ELSE jsonb_build_object('id', #{fk}::text,
                                                        'type', '#{resource.json_type}') END)
      EOQ
    elsif resource.has_many? or resource.has_one?
      refl = resource.reflection
      <<~EOQ
        '#{resource.json_key}',
         jsonb_build_object(#{refl.include_data ? %Q{'data', rel_#{resource.cte_name}.j} : ''}
                            #{refl.include_data && refl.links.any? ? ',' : ''}
                            #{refl.links.any? ? %Q{'links',  jsonb_build_object(#{select_resource_relationship_links(resource, refl)})} : ''})
      EOQ
    else
      raise "Unknown kind of field reflection for #{resource.full_name}"
    end
  end

  def select_resource_relationships(resource)
    fields = reflection_fields_for(resource)
    children = fields.map{|f| get_json_thing(resource, f)}
    if children.any?
      <<~EOQ
        jsonb_build_object(#{children.map{|ch| select_resource_relationship(ch)}.join(', ')})
      EOQ
    else
      nil
    end
  end

  def join_resource_relationships(resource)
    fields = reflection_fields_for(resource)
    fields.map{|f|
      child_resource = get_json_thing(resource, f)
      refl = child_resource.reflection
      if refl.has_many?
        if refl.ar_reflection.present?
          # Preserve ordering options, either from the AR association itself
          # or from the class's default scope.
          # TODO: preserve the whole custom relation, not just ordering
          p = refl.ar_class.new
          ordering = nil
          ActiveSupport::Deprecation.silence do
            # TODO: Calling `orders` prints deprecation warnings, so find another way:
            ordering = p.send(refl.name).orders
            ordering = child_resource.ar_class.default_scoped.orders if ordering.empty?
          end
          ordering = ordering.map{|o|
            case o
            # TODO: The gsub is pretty awful....
            when Arel::Nodes::Ordering
              o.to_sql.gsub("\"#{child_resource.table_name}\"", "rel")
            when String
              o
            else
              raise "Unknown type of ordering: #{o.inspect}"
            end
          }.join(', ').presence
          ordering = "ORDER BY #{ordering}" if ordering
          <<~EOQ
            LEFT OUTER JOIN LATERAL (
              SELECT  coalesce(jsonb_agg(jsonb_build_object('id', rel."#{child_resource.primary_key}"::text,
                                                            'type', '#{child_resource.json_type}') #{ordering}), '[]') AS j
              FROM    "#{child_resource.table_name}" rel
              WHERE   rel."#{child_resource.foreign_key}" = "#{resource.table_name}"."#{resource.primary_key}"
            ) "rel_#{child_resource.cte_name}" ON true
          EOQ
        elsif not refl.reflection_sql.nil?  # can't use .present? since that loads the Relation!
          case refl.reflection_sql
          when String
            raise "TODO"
          when ActiveRecord::Relation
            rel = refl.reflection_sql
            sql = rel.select(<<~EOQ).to_sql
              coalesce(jsonb_agg(jsonb_build_object('id', "#{child_resource.table_name}"."#{child_resource.primary_key}"::text,
                                                    'type', '#{child_resource.json_type}')), '[]') AS j
            EOQ
            <<~EOQ
              LEFT OUTER JOIN LATERAL (
                #{sql}
              ) "rel_#{child_resource.cte_name}" ON true
            EOQ
          end
        end
      elsif refl.has_one?
        <<~EOQ
          LEFT OUTER JOIN LATERAL (
            SELECT  jsonb_build_object('id', rel."#{child_resource.primary_key}"::text,
                                      'type', '#{child_resource.json_type}') AS j
            FROM    "#{child_resource.table_name}" rel
            WHERE   rel."#{child_resource.foreign_key}" = "#{resource.table_name}"."#{resource.primary_key}"
          ) "rel_#{child_resource.cte_name}" ON true
        EOQ
      else
        nil
      end
    }.compact.join("\n")
  end

  def include_selects
    @include_selects ||= includes.map {|inc|
      th = get_json_thing_from_base(inc)
      # TODO: UNION ALL would be faster than UNION,
      # but then we still need to de-dupe when we have two paths to the same table,
      # e.g. buyer and seller for User.
      # But we could group those and union just them, or even better do a DISTINCT ON (id).
      # Since we don't get the id here that could be another CTE.
      "UNION SELECT j FROM #{th.cte_name}"
    }
  end

  def include_cte_join_condition(resource)
    parent = resource.parent
    if resource.belongs_to?
      %Q{#{parent.cte_name}."#{resource.foreign_key}" = "#{resource.table_name}"."#{resource.primary_key}"}
    elsif resource.has_many? or resource.has_one?
      %Q{#{parent.cte_name}."#{parent.primary_key}" = "#{resource.table_name}"."#{resource.foreign_key}"}
    else
      raise "not supported relationship: #{resource.full_name}"
    end
  end

  def include_cte(resource)
    # Sometimes options[:fields] has plural keys and sometimes singular,
    # so try both:
    parent = resource.parent
    <<~EOQ
      SELECT  DISTINCT ON ("#{resource.table_name}"."#{resource.primary_key}")
              "#{resource.table_name}".*,
              #{select_resource(resource)} AS j
      FROM    "#{resource.table_name}"
      JOIN    #{parent.cte_name}
      ON      #{include_cte_join_condition(resource)}
      #{join_resource_relationships(resource)}
      ORDER BY "#{resource.table_name}"."#{resource.primary_key}"
    EOQ
  end

  def includes
    @instance_options[:include] || []
  end

  # Takes a dotted field name (not including the base resource)
  # like we might find in options[:include],
  # and builds up all the JsonThings needed to get to the end.
  def get_json_thing_from_base(field)
    r = base_resource
    field.split('.').each do |f|
      r = get_json_thing(r, f)
    end
    r
  end

  def include_ctes
    includes.map { |inc|
      # Be careful: inc might have dots:
      th = get_json_thing_from_base(inc)
      <<~EOQ
        #{th.cte_name} AS (
          #{include_cte(th)}
        ),
      EOQ
    }.join("\n")
  end

  def base_resource
    @json_things[:base]
  end

  def maybe_select_resource_relationships(resource)
    rels_sql = select_resource_relationships(resource)
    if rels_sql.nil?
      ''
    else
      %Q{, 'relationships', #{rels_sql}}
    end
  end

  def select_resource(resource)
    fields = fields_for(resource)
    <<~EOQ
      jsonb_build_object('id', "#{resource.table_name}"."#{resource.primary_key}"::text,
                         'type', '#{resource.json_type}',
                         'attributes', #{select_resource_attributes(resource)}
                         #{maybe_select_resource_relationships(resource)})
    EOQ
  end

  # Returns all the attributes listed in the serializer,
  # after checking `include_foo?` methods.
  def serializer_attributes(resource)
    ms = Set.new(resource.serializer.instance_methods)
    resource.serializer._attributes.select{|f|
      if ms.include? "include_#{f}?".to_sym
        ser = resource.serializer.new(nil, @options)
        ser.send("include_#{f}?".to_sym) # TODO: call the method
      else
        true
      end
    }
  end

  # Returns all the relationships listed in the serializer,
  # after checking `include_foo?` methods.
  def serializer_reflections(resource)
    ms = Set.new(resource.serializer.instance_methods)
    resource.serializer._reflections.keys.select{|f|
      if ms.include? "include_#{f}?".to_sym
        ser = resource.serializer.new(nil, @options)
        ser.send("include_#{f}?".to_sym) # TODO: call the method
      else
        true
      end
    }
  end

  def fields_for(resource)
    @fields_for[resource.full_name] ||= _fields_for(resource)
  end

  def _fields_for(resource)
    # Sometimes options[:fields] has plural keys and sometimes singular,
    # so try both:
    resource_key = resource.json_type.to_sym
    fields = @instance_options.dig :fields, resource_key
    if fields.nil?
      resource_key = resource.json_type.singularize.to_sym
      fields = @instance_options.dig :fields, resource_key
    end
    if fields.nil?
      # If the user didn't request specific fields, then give them all that appear in the serializer:
      fields = serializer_attributes(resource).to_a + serializer_reflections(resource).to_a
    end
    fields
  end

  def attribute_fields_for(resource)
    @attribute_fields_for[resource.full_name] ||= _attribute_fields_for(resource)
  end

  def _attribute_fields_for(resource)
    attrs = Set.new(serializer_attributes(resource))
    fields_for(resource).select { |f| attrs.include? f }.to_a
  end

  def reflection_fields_for(resource)
    @reflection_fields_for[resource.full_name] ||= _reflection_fields_for(resource)
  end

  def _reflection_fields_for(resource)
    refls = Set.new(serializer_reflections(resource))
    fields_for(resource).select { |f| refls.include? f }.to_a
  end

  def to_sql
    table_name = base_resource.table_name
    maybe_included = if include_selects.any?
                       %Q{, 'included', inc.j}
                     else
                       ''
                     end
    return <<~EOQ
      WITH
      t AS (
        #{base_relation.select(%Q{"#{base_resource.table_name}".*}).to_sql}
      ),
      t2 AS (
        #{many? ? "SELECT  COALESCE(jsonb_agg(#{select_resource(base_resource)}), '[]') AS j"
                : "SELECT                     #{select_resource(base_resource)}         AS j"}
        FROM    t AS "#{base_resource.table_name}"
        #{join_resource_relationships(base_resource)}
      ),
      #{include_ctes}
      all_ctes AS (
        SELECT  '{}'::jsonb AS j
        WHERE   1=0
        #{include_selects.join("\n")}
      ),
      inc AS (
        SELECT  COALESCE(jsonb_agg(j), '[]') AS j
        FROM    all_ctes
      )
			SELECT	jsonb_build_object('data', t2.j
                                 #{maybe_included})
      FROM    t2
      CROSS JOIN  inc
		EOQ
  end

end

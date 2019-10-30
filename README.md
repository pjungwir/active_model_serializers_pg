# active\_model\_serializers\_pg

This gem provides an ActiveModelSerializers adapter that can generate JSON directly in Postgres.
It was inspired by [postgres\_ext-serializers](https://github.com/DavyJonesLocker/postgres_ext-serializers) which is no longer maintained and only supports Rails 4 and AMS 0.8.
This gem adds support for Rails 5 and AMS 0.10.
In addition we provide output in [JSON:API](https://jsonapi.org/) format.
(I'd like to add normal JSON output too, so let me know if that would be helpful to you.)

Building your JSON in Postgres can reduce your response time 10 &ndash; 100x.
You skip instantiating thousands of Ruby objects (and garbage collecting them later),
and Postgres can generate the JSON far more quickly than AMS.

You can read lots more about this gem's approach at DockYard's blog post,
[Avoid Rails When Generating JSON responses with PostgreSQL](https://dockyard.com/blog/2014/05/27/avoid-rails-when-generating-json-responses-with-postgresql) by Dan McClain,
or [watch a YouTube video](https://www.youtube.com/watch?v=tYTw3Jshrqo) of his Postgres Open 2014 Talk [Using PostgreSQL, not Rails, to make Rails faster](http://slides.com/danmcclain/postgresopen-2014) (Slides).
Not everything is this same, but hopefully you'll still get the general idea.

This gem requires Rails 5, AMS 0.10, and Postgres 9.4+.

## Installation

Add this line to your application's Gemfile:

    gem 'active_model_serializers_pg'

And then execute:

    bundle

Or install it yourself as:

    gem install active_model_serializers_pg

### Migrations

This gem depends on a SQL function to dasherize hstore/json/jsonb columns, so you must add its migration to your project and run it, like this:

    rails g active_model_serializers_pg
    rake db:migrate

## Usage

You can enable in-Postgres serialization for everything by putting this in a Rails initializer:

    ActiveModelSerializers.config.adapter = :json_api_pg

or use it more selectively in your controller actions by saying:

    render json: @users, adapter: :json_api_pg

You could also turn it on for everything but then set `adapter: :json_api` for any actions where it doesn't work.

Note this gem also respects `ActiveModelSerializers.config.key_transform = :dash`, if you are using that.

### Supports

Here are some other details we support:

- `belongs_to`, `has_one`, and `has_many` associations.
- If you serialize an `enum` you get the string values, not integers.
- You can serialize an `alias`'d association.
- You can serialize an `alias_attribute`'d column.
- We preserve SQL ordering from a model's `default_scope`.
- We preserve SQL ordering attached to an association.
- When dasherizing we also dasherize json/jsonb/hstore contents (like standard AMS).

### Methods in Serializers and Models

If you are using methods to compute properties for your JSON responses
in your models or serializers, active\_model\_serializers\_pg will try to
discover a SQL version of this call by looking for a class method with
the same name and the suffix `__sql`. Here's an example:

```ruby
class MyModel < ActiveRecord::Base
  def full_name
    "#{object.first_name} #{object.last_name}"
  end

  def self.full_name__sql
    "first_name || ' ' || last_name"
  end
end
```

There is no instance of MyModel created so sql computed properties needs to be
a class method. Right now, this string is used as a SQL literal, so be sure to
*not* use untrusted values in the return value.

Similarly we also look for a `foo__sql` method
for relationships that aren't ActiveRecord associations.
It must return an `ActiveRecord::Relation` (not a `String`),
and we will run its SQL inside a `LEFT OUTER JOIN LATERAL`
(so it has access to the parent table). For example:

```ruby
class Book < ActiveRecord::Base

  def essays_by_same_author
    Essay.where(author_id: author_id)
  end

  def self.essays_by_same_author__sql
    Essay.where("books.author_id = essays.author_id")
  end

end
```

## Developing

To work on active\_model\_serializers\_pg locally, follow these steps:

 1. Run `bundle install`, this will install (almost) all the development
    dependencies.
 2. Run `gem install byebug` (not a declared dependency to not break CI).
 3. Run `bundle exec rake setup`, this will set up the `.env` file necessary to run
    the tests and set up the database.
 4. Run `bundle exec rake db:create`, this will create the test database.
 5. Run `bundle exec rake db:migrate`, this will set up the database tables required
    by the test.
 6. Run `bundle exec rake test:all` to run tests against all supported versions of Active Record (currently 5.0.x, 5.1.x, 5.2.x).
    You can also say `BUNDLE_GEMFILE=gemfiles/Gemfile.activerecord-5.2.x bundle exec rspec spec` to run against a specific version (and select specific tests).

Commands for building/releasing/installing:

* `rake build`
* `rake install`
* `rake release`

### TODO

Here are things I'd like to support but don't yet:

- Use Arel to generate all the SQL.
- More support of custom scopes attached to associations.
- Add a non-JSON:API adapter, for traditional JSON output.
- Have all the tests verify they output the asme JSON as the built-in AMS serializers.
- Look at AMS's own tests for more features we should support.
- HABTM associations?
- `has_many through:` associations?

## Authors

Paul Jungwirth
[github](http://github.com/pjungwir)

Thanks to [Dan McClain](https://github.com/danmcclain) for writing the original postgres\_ext-serializers gem!

## Versioning ##

This gem follows [Semantic Versioning](http://semver.org)

## Want to help? ##

Please do! We are always looking to improve this gem.

## Legal ##

Copyright &copy; 2019 Paul A. Jungwirth

[Licensed under the MIT license](http://www.opensource.org/licenses/mit-license.php)

# frozen_string_literal: true

require "erb"
require "yaml"
require "zlib"
require "set"
require "active_support/dependencies"
require "active_support/core_ext/module/delegation"
require "active_support/core_ext/digest/uuid"
require "active_record/fixture_set/file"
require "active_record/fixture_set/render_context"
require "active_record/fixture_set/table_row"
require "active_record/test_fixtures"

module ActiveRecord
  class FixtureClassNotFound < ActiveRecord::ActiveRecordError #:nodoc:
  end

  # \Fixtures are a way of organizing data that you want to test against; in short, sample data.
  #
  # They are stored in YAML files, one file per model, which are placed in the directory
  # appointed by <tt>ActiveSupport::TestCase.fixture_path=(path)</tt> (this is automatically
  # configured for Rails, so you can just put your files in <tt><your-rails-app>/test/fixtures/</tt>).
  # The fixture file ends with the +.yml+ file extension, for example:
  # <tt><your-rails-app>/test/fixtures/web_sites.yml</tt>).
  #
  # The format of a fixture file looks like this:
  #
  #   rubyonrails:
  #     id: 1
  #     name: Ruby on Rails
  #     url: http://www.rubyonrails.org
  #
  #   google:
  #     id: 2
  #     name: Google
  #     url: http://www.google.com
  #
  # This fixture file includes two fixtures. Each YAML fixture (ie. record) is given a name and
  # is followed by an indented list of key/value pairs in the "key: value" format. Records are
  # separated by a blank line for your viewing pleasure.
  #
  # Note: Fixtures are unordered. If you want ordered fixtures, use the omap YAML type.
  # See https://yaml.org/type/omap.html
  # for the specification. You will need ordered fixtures when you have foreign key constraints
  # on keys in the same table. This is commonly needed for tree structures. Example:
  #
  #    --- !omap
  #    - parent:
  #        id:         1
  #        parent_id:  NULL
  #        title:      Parent
  #    - child:
  #        id:         2
  #        parent_id:  1
  #        title:      Child
  #
  # = Using Fixtures in Test Cases
  #
  # Since fixtures are a testing construct, we use them in our unit and functional tests. There
  # are two ways to use the fixtures, but first let's take a look at a sample unit test:
  #
  #   require "test_helper"
  #
  #   class WebSiteTest < ActiveSupport::TestCase
  #     test "web_site_count" do
  #       assert_equal 2, WebSite.count
  #     end
  #   end
  #
  # By default, +test_helper.rb+ will load all of your fixtures into your test
  # database, so this test will succeed.
  #
  # The testing environment will automatically load all the fixtures into the database before each
  # test. To ensure consistent data, the environment deletes the fixtures before running the load.
  #
  # In addition to being available in the database, the fixture's data may also be accessed by
  # using a special dynamic method, which has the same name as the model.
  #
  # Passing in a fixture name to this dynamic method returns the fixture matching this name:
  #
  #   test "find one" do
  #     assert_equal "Ruby on Rails", web_sites(:rubyonrails).name
  #   end
  #
  # Passing in multiple fixture names returns all fixtures matching these names:
  #
  #   test "find all by name" do
  #     assert_equal 2, web_sites(:rubyonrails, :google).length
  #   end
  #
  # Passing in no arguments returns all fixtures:
  #
  #   test "find all" do
  #     assert_equal 2, web_sites.length
  #   end
  #
  # Passing in any fixture name that does not exist will raise <tt>StandardError</tt>:
  #
  #   test "find by name that does not exist" do
  #     assert_raise(StandardError) { web_sites(:reddit) }
  #   end
  #
  # Alternatively, you may enable auto-instantiation of the fixture data. For instance, take the
  # following tests:
  #
  #   test "find_alt_method_1" do
  #     assert_equal "Ruby on Rails", @web_sites['rubyonrails']['name']
  #   end
  #
  #   test "find_alt_method_2" do
  #     assert_equal "Ruby on Rails", @rubyonrails.name
  #   end
  #
  # In order to use these methods to access fixtured data within your test cases, you must specify one of the
  # following in your ActiveSupport::TestCase-derived class:
  #
  # - to fully enable instantiated fixtures (enable alternate methods #1 and #2 above)
  #     self.use_instantiated_fixtures = true
  #
  # - create only the hash for the fixtures, do not 'find' each instance (enable alternate method #1 only)
  #     self.use_instantiated_fixtures = :no_instances
  #
  # Using either of these alternate methods incurs a performance hit, as the fixtured data must be fully
  # traversed in the database to create the fixture hash and/or instance variables. This is expensive for
  # large sets of fixtured data.
  #
  # = Dynamic fixtures with ERB
  #
  # Sometimes you don't care about the content of the fixtures as much as you care about the volume.
  # In these cases, you can mix ERB in with your YAML fixtures to create a bunch of fixtures for load
  # testing, like:
  #
  #   <% 1.upto(1000) do |i| %>
  #   fix_<%= i %>:
  #     id: <%= i %>
  #     name: guy_<%= i %>
  #   <% end %>
  #
  # This will create 1000 very simple fixtures.
  #
  # Using ERB, you can also inject dynamic values into your fixtures with inserts like
  # <tt><%= Date.today.strftime("%Y-%m-%d") %></tt>.
  # This is however a feature to be used with some caution. The point of fixtures are that they're
  # stable units of predictable sample data. If you feel that you need to inject dynamic values, then
  # perhaps you should reexamine whether your application is properly testable. Hence, dynamic values
  # in fixtures are to be considered a code smell.
  #
  # Helper methods defined in a fixture will not be available in other fixtures, to prevent against
  # unwanted inter-test dependencies. Methods used by multiple fixtures should be defined in a module
  # that is included in ActiveRecord::FixtureSet.context_class.
  #
  # - define a helper method in <tt>test_helper.rb</tt>
  #     module FixtureFileHelpers
  #       def file_sha(path)
  #         Digest::SHA2.hexdigest(File.read(Rails.root.join('test/fixtures', path)))
  #       end
  #     end
  #     ActiveRecord::FixtureSet.context_class.include FixtureFileHelpers
  #
  # - use the helper method in a fixture
  #     photo:
  #       name: kitten.png
  #       sha: <%= file_sha 'files/kitten.png' %>
  #
  # = Transactional Tests
  #
  # Test cases can use begin+rollback to isolate their changes to the database instead of having to
  # delete+insert for every test case.
  #
  #   class FooTest < ActiveSupport::TestCase
  #     self.use_transactional_tests = true
  #
  #     test "godzilla" do
  #       assert_not_empty Foo.all
  #       Foo.destroy_all
  #       assert_empty Foo.all
  #     end
  #
  #     test "godzilla aftermath" do
  #       assert_not_empty Foo.all
  #     end
  #   end
  #
  # If you preload your test database with all fixture data (probably by running `bin/rails db:fixtures:load`)
  # and use transactional tests, then you may omit all fixtures declarations in your test cases since
  # all the data's already there and every case rolls back its changes.
  #
  # In order to use instantiated fixtures with preloaded data, set +self.pre_loaded_fixtures+ to
  # true. This will provide access to fixture data for every table that has been loaded through
  # fixtures (depending on the value of +use_instantiated_fixtures+).
  #
  # When *not* to use transactional tests:
  #
  # 1. You're testing whether a transaction works correctly. Nested transactions don't commit until
  #    all parent transactions commit, particularly, the fixtures transaction which is begun in setup
  #    and rolled back in teardown. Thus, you won't be able to verify
  #    the results of your transaction until Active Record supports nested transactions or savepoints (in progress).
  # 2. Your database does not support transactions. Every Active Record database supports transactions except MySQL MyISAM.
  #    Use InnoDB, MaxDB, or NDB instead.
  #
  # = Advanced Fixtures
  #
  # Fixtures that don't specify an ID get some extra features:
  #
  # * Stable, autogenerated IDs
  # * Label references for associations (belongs_to, has_one, has_many)
  # * HABTM associations as inline lists
  #
  # There are some more advanced features available even if the id is specified:
  #
  # * Autofilled timestamp columns
  # * Fixture label interpolation
  # * Support for YAML defaults
  #
  # == Stable, Autogenerated IDs
  #
  # Here, have a monkey fixture:
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #
  #   reginald:
  #     id: 2
  #     name: Reginald the Pirate
  #
  # Each of these fixtures has two unique identifiers: one for the database
  # and one for the humans. Why don't we generate the primary key instead?
  # Hashing each fixture's label yields a consistent ID:
  #
  #   george: # generated id: 503576764
  #     name: George the Monkey
  #
  #   reginald: # generated id: 324201669
  #     name: Reginald the Pirate
  #
  # Active Record looks at the fixture's model class, discovers the correct
  # primary key, and generates it right before inserting the fixture
  # into the database.
  #
  # The generated ID for a given label is constant, so we can discover
  # any fixture's ID without loading anything, as long as we know the label.
  #
  # == Label references for associations (belongs_to, has_one, has_many)
  #
  # Specifying foreign keys in fixtures can be very fragile, not to
  # mention difficult to read. Since Active Record can figure out the ID of
  # any fixture from its label, you can specify FK's by label instead of ID.
  #
  # === belongs_to
  #
  # Let's break out some more monkeys and pirates.
  #
  #   ### in pirates.yml
  #
  #   reginald:
  #     id: 1
  #     name: Reginald the Pirate
  #     monkey_id: 1
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #     pirate_id: 1
  #
  # Add a few more monkeys and pirates and break this into multiple files,
  # and it gets pretty hard to keep track of what's going on. Let's
  # use labels instead of IDs:
  #
  #   ### in pirates.yml
  #
  #   reginald:
  #     name: Reginald the Pirate
  #     monkey: george
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     name: George the Monkey
  #     pirate: reginald
  #
  # Pow! All is made clear. Active Record reflects on the fixture's model class,
  # finds all the +belongs_to+ associations, and allows you to specify
  # a target *label* for the *association* (monkey: george) rather than
  # a target *id* for the *FK* (<tt>monkey_id: 1</tt>).
  #
  # ==== Polymorphic belongs_to
  #
  # Supporting polymorphic relationships is a little bit more complicated, since
  # Active Record needs to know what type your association is pointing at. Something
  # like this should look familiar:
  #
  #   ### in fruit.rb
  #
  #   belongs_to :eater, polymorphic: true
  #
  #   ### in fruits.yml
  #
  #   apple:
  #     id: 1
  #     name: apple
  #     eater_id: 1
  #     eater_type: Monkey
  #
  # Can we do better? You bet!
  #
  #   apple:
  #     eater: george (Monkey)
  #
  # Just provide the polymorphic target type and Active Record will take care of the rest.
  #
  # === has_and_belongs_to_many
  #
  # Time to give our monkey some fruit.
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #
  #   ### in fruits.yml
  #
  #   apple:
  #     id: 1
  #     name: apple
  #
  #   orange:
  #     id: 2
  #     name: orange
  #
  #   grape:
  #     id: 3
  #     name: grape
  #
  #   ### in fruits_monkeys.yml
  #
  #   apple_george:
  #     fruit_id: 1
  #     monkey_id: 1
  #
  #   orange_george:
  #     fruit_id: 2
  #     monkey_id: 1
  #
  #   grape_george:
  #     fruit_id: 3
  #     monkey_id: 1
  #
  # Let's make the HABTM fixture go away.
  #
  #   ### in monkeys.yml
  #
  #   george:
  #     id: 1
  #     name: George the Monkey
  #     fruits: apple, orange, grape
  #
  #   ### in fruits.yml
  #
  #   apple:
  #     name: apple
  #
  #   orange:
  #     name: orange
  #
  #   grape:
  #     name: grape
  #
  # Zap! No more fruits_monkeys.yml file. We've specified the list of fruits
  # on George's fixture, but we could've just as easily specified a list
  # of monkeys on each fruit. As with +belongs_to+, Active Record reflects on
  # the fixture's model class and discovers the +has_and_belongs_to_many+
  # associations.
  #
  # == Autofilled Timestamp Columns
  #
  # If your table/model specifies any of Active Record's
  # standard timestamp columns (+created_at+, +created_on+, +updated_at+, +updated_on+),
  # they will automatically be set to <tt>Time.now</tt>.
  #
  # If you've set specific values, they'll be left alone.
  #
  # == Fixture label interpolation
  #
  # The label of the current fixture is always available as a column value:
  #
  #   geeksomnia:
  #     name: Geeksomnia's Account
  #     subdomain: $LABEL
  #     email: $LABEL@email.com
  #
  # Also, sometimes (like when porting older join table fixtures) you'll need
  # to be able to get a hold of the identifier for a given label. ERB
  # to the rescue:
  #
  #   george_reginald:
  #     monkey_id: <%= ActiveRecord::FixtureSet.identify(:reginald) %>
  #     pirate_id: <%= ActiveRecord::FixtureSet.identify(:george) %>
  #
  # == Support for YAML defaults
  #
  # You can set and reuse defaults in your fixtures YAML file.
  # This is the same technique used in the +database.yml+ file to specify
  # defaults:
  #
  #   DEFAULTS: &DEFAULTS
  #     created_on: <%= 3.weeks.ago.to_s(:db) %>
  #
  #   first:
  #     name: Smurf
  #     <<: *DEFAULTS
  #
  #   second:
  #     name: Fraggle
  #     <<: *DEFAULTS
  #
  # Any fixture labeled "DEFAULTS" is safely ignored.
  #
  # Besides using "DEFAULTS", you can also specify what fixtures will
  # be ignored by setting "ignore" in "_fixture" section.
  #
  #   # users.yml
  #   _fixture:
  #     ignore:
  #       - base
  #     # or use "ignore: base" when there is only one fixture needs to be ignored.
  #
  #   base: &base
  #     admin: false
  #     introduction: "This is a default description"
  #
  #   admin:
  #     <<: *base
  #     admin: true
  #
  #   visitor:
  #     <<: *base
  #
  # In the above example, 'base' will be ignored when creating fixtures.
  # This can be used for common attributes inheriting.
  #
  # == Configure the fixture model class
  #
  # It's possible to set the fixture's model class directly in the YAML file.
  # This is helpful when fixtures are loaded outside tests and
  # +set_fixture_class+ is not available (e.g.
  # when running <tt>bin/rails db:fixtures:load</tt>).
  #
  #   _fixture:
  #     model_class: User
  #   david:
  #     name: David
  #
  # Any fixtures labeled "_fixture" are safely ignored.
  class FixtureSet
    #--
    # An instance of FixtureSet is normally stored in a single YAML file and
    # possibly in a folder with the same name.
    #++

    MAX_ID = 2**30 - 1

    @@all_cached_fixtures = Hash.new { |h, k| h[k] = {} }

    cattr_accessor :all_loaded_fixtures, default: {}

    class << self
      def fixture_model_klass(set_name, config = ActiveRecord::Base) # :nodoc:
        set_name = set_name.singularize if config.pluralize_table_names
        set_name.camelize.safe_constantize
      end

      def fixture_table_name(set_name, config = ActiveRecord::Base) # :nodoc:
        :"#{config.table_name_prefix}#{set_name.tr("/", "_")}#{config.table_name_suffix}"
      end

      def reset_cache
        @@all_cached_fixtures.clear
      end

      def cache_for_connection(connection)
        @@all_cached_fixtures[connection]
      end

      def create_fixtures(directory, fixture_set_names, class_names = {}, config = ActiveRecord::Base, &block)
        fixture_set_names = Array(fixture_set_names).map(&:to_s)
        class_names = build_class_names_cache(class_names, config)

        # FIXME: Apparently JK uses this.
        connection = block&.call || ActiveRecord::Base.connection
        cache      = cache_for_connection(connection)

        if (fixture_files = fixture_set_names - cache.keys).any?
          sets = fixture_files.map { |set_name| new(nil, set_name, class_names[set_name], ::File.join(directory, set_name)) }
          insert_sets_grouped_by_connection sets.group_by { |set| set.model_class&.connection || connection }

          sets.index_by(&:name).tap do |map|
            cache.update map
            all_loaded_fixtures.update map
          end
        end

        cache.values_at(*fixture_set_names)
      end

      # Returns a consistent, platform-independent identifier for +label+.
      # Integer identifiers are values less than 2^30. UUIDs are RFC 4122 version 5 SHA-1 hashes.
      def identify(label, column_type = :integer)
        if column_type == :uuid
          Digest::UUID.uuid_v5(Digest::UUID::OID_NAMESPACE, label.to_s)
        else
          Zlib.crc32(label.to_s) % MAX_ID
        end
      end

      # Superclass for the evaluation contexts used by ERB fixtures.
      def context_class
        @context_class ||= Class.new
      end

      private
        def insert_sets_grouped_by_connection(grouped_sets) # :nodoc:
          grouped_sets.each do |conn, sets|
            table_rows_for_connection = Hash.new { |h, k| h[k] = [] }

            sets.each do |fixture_set|
              fixture_set.table_rows.each do |table, rows|
                table_rows_for_connection[table].unshift(*rows)
              end
            end

            conn.insert_fixtures_set(table_rows_for_connection, table_rows_for_connection.keys)
            reset_connection_after_insertion conn, sets
          end
        end

        def reset_connection_after_insertion(conn, sets)
          if conn.respond_to?(:reset_pk_sequence!) # Cap primary key sequences to max(pk).
            sets.each { |fixture| conn.reset_pk_sequence!(fixture.table_name) }
          end
        end

        def build_class_names_cache(class_names, config)
          class_names.keep_if { |_, klass| active_record?(klass) }.stringify_keys.tap do |hsh|
            hsh.default_proc = -> (hash, key) do
              hash[key] = fixture_model_klass(key, config).yield_self { |klass| active_record?(klass) ? klass : nil }
            end
          end
        end

        def active_record?(klass)
          klass && klass < ActiveRecord::Base
        end
    end

    attr_reader :table_name, :name, :fixtures, :model_class, :config

    def initialize(_, name, class_name, path, config = ActiveRecord::Base)
      @name, @path, @config = name, path, config
      self.model_class = class_name

      @fixtures   = read_fixture_files path
      @table_name = model_class&.table_name || self.class.fixture_table_name(name, config)
    end
    delegate :[], :[]=, :each, :size, to: :fixtures

    # Returns a hash of rows to be inserted. The key is the table, the value is
    # a list of rows to insert to that table.
    def table_rows
      tables = Hash.new { |h, k| h[k] = [] }
      tables[table_name] = nil # Order dependence: ensure this table is loaded before any HABTM associations

      tables[table_name] = fixtures.map do |label, fixture|
        if model_class
          TableRow.new(fixture.to_h, model_class: model_class, tables: tables, label: label,
            timestamp: config.default_timezone == :utc ? Time.now.utc : Time.now).to_h
        else
          fixture.to_h
        end
      end

      tables
    end

    def find(label) # :nodoc:
      if model_class
        model_class.unscoped.find(fixtures[label][model_class.primary_key])
      else
        raise FixtureClassNotFound, "No class attached to find."
      end
    end

    private
      attr_writer :model_class

      # Loads the fixtures from the YAML file at +path+.
      # If the file sets the +model_class+ and current instance value is not set,
      # it uses the file value.
      def read_fixture_files(path)
        fixture_files = FixtureSet::File.load_from(path)
        self.model_class ||= fixture_files.map(&:model_class).compact.first&.safe_constantize

        fixture_files.map(&:rows).inject(Hash.new, &:merge!).to_h { |label, row| [ label, ActiveRecord::Fixture.new(label, row) ] }
      end
  end

  class Fixture #:nodoc:
    include Enumerable

    class FixtureError < StandardError; end #:nodoc:
    class FormatError  < FixtureError;  end #:nodoc:

    attr_reader :label, :data
    delegate :to_h, :[], :each, to: :data

    def initialize(label, data)
      @label, @data = label, data
    end
  end
end

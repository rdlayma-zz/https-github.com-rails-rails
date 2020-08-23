# frozen_string_literal: true

module ActiveRecord::FixtureSet::ConnectionCached # :nodoc:
  @@all_cached_fixtures = Hash.new { |h, k| h[k] = SetCache.new }

  def reset_cache
    @@all_cached_fixtures.clear
  end

  def cache_for_connection(connection)
    @@all_cached_fixtures[connection]
  end

  private
    class SetCache < DelegateClass(Hash) # :nodoc:
      def initialize
        @cache = {}
        super @cache
      end

      def fetch_multi(set_names, &block)
        Array(set_names).map(&:to_s).yield_self do |keys|
          insert_missing_set_names(keys, &block)
          @cache.values_at(*keys)
        end
      end

      private
        def insert_missing_set_names(set_names)
          if (missing_set_names = set_names - @cache.keys).any?
            @cache.merge! yield(missing_set_names).index_by(&:name)
          end
        end
    end
end

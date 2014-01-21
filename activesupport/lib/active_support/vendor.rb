# Prefer gems to the bundled libs.
require 'rubygems'

require 'builder'

begin
  gem 'memcache-client', '>= 1.7.4'
rescue Gem::LoadError
  $:.unshift "#{File.dirname(__FILE__)}/vendor/memcache-client-1.7.4"
end

$:.unshift "#{File.dirname(__FILE__)}/vendor/tzinfo-0.3.12"

require 'i18n'

module I18n
  if !respond_to?(:normalize_translation_keys) && respond_to?(:normalize_keys)
    def self.normalize_translation_keys(*args)
      normalize_keys(*args)
    end
  end
end

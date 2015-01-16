# gem to internationalize Pandora
require 'i18n'

module Pandora
  module I18n
    # Configure i18n for Pandora
    ::I18n.load_path         = Dir[Pandora.root + '/config/locales/*.yml']
    ::I18n.available_locales = [:de, :es, :fr, :it, :pl, :ru, :tr, :ua]
    ::I18n.default_locale    = :ru
  end
end

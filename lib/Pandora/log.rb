require 'logging'

module Pandora
  def self.logger
    @@logger ||= Logging.logger(STDOUT)
  end
end
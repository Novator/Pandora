require 'logging'

module Pandora
  def self.logger
    if !@logger
      @logger = Logging.logger(STDOUT)
      # TODO: uncomment following
      # @logger.level = Pandora.config.logger.level
    end
    @logger
  end
end
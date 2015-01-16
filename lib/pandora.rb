# Bundler to manage gems
# Используем Bundler
require 'rubygems'
require 'bundler/setup'

# Debug tool
# Гем для отладки приложения
require 'byebug'

# gem to work with configurations
# Гем для работы с конфигурацией
require 'configatron'

# Штуки которые были по умолчанию
require 'rexml/document'
require 'zlib'
require 'digest'
require 'base64'
require 'net/http'
require 'net/https'
require 'sqlite3'
begin
  require 'gst'
rescue Exception
end

# ====================================================================
# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры
require 'gtk2'
require 'fileutils'

# Все подряд
require 'singleton'

# Очередной гениальный файл...
module Pandora

  # Application configuration
  def self.config
    configatron.pandora
  end

  # Root directory
  def self.root
    @@root_dir ||= File.expand_path("../../", __FILE__)
  end

  class Application
    include ::Singleton

    # You can configure application with both hash and block
    #
    # Hash:
    # Pandora.Application.instance.configure { option1 => [:some, :values] }
    #
    # Block
    # Pandora.Application.instance.configure do |config|
    #   config.option1 = value 1
    # end
    #
    def configure(options = {})
      configatron.configure_from_hash(options)

      if block_given?
        configatron.pandora do |config|
          yield config
        end
      end
    end

  end
end

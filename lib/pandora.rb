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

# gem to parse cli arguments
# Гем для парсинга аргументов командной строки
require 'slop'

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

# Порядок модулей программы
require_relative 'pandora/constants'
require_relative 'pandora/utils'

# Очередной гениальный файл...
module Pandora

  # Application instance shortcut
  def self.app
    Application.instance
  end

  # Application configuration
  def self.config
    configatron.pandora
  end

  # Root directory
  def self.root
    @@root_dir ||= File.expand_path("../../", __FILE__)
  end

  def self.t(key)
    ::I18n.t('pandora.' + key)
  end

  # Pandora's directories
  %w(base view model lang util files).each do |method_name|
    class_eval "def self.#{method_name}_dir; File.join root, '#{method_name}'; end"
  end

  class Application
    include ::Singleton

    # You can configure application with both hash and block
    #
    # Hash:
    # Pandora.app.configure { option1 => [:some, :values] }
    #
    # Block
    # Pandora.app.configure do |config|
    #   config.option1 = value 1
    # end
    #
    def configure(options = {})
      if block_given?
        configatron.pandora do |config|
          yield config
        end
      else
        configatron.configure_from_hash(options)
      end
    end

    # == Running the Pandora!
    # == RU: Запуск Пандоры!
    def run
      Pandora::Model.load_from_xml(Pandora.config.lang)
      Pandora::Gtk::MainWindow.new(MAIN_WINDOW_TITLE)
    end

    # Expand the arguments of command line
    # RU: Разобрать аргументы командной строки
    def cli_options
      @cli_options ||= Slop.parse do |o|
        o.string '-h', '--host', 'Hostname or IP address'
        o.integer '-p', '--port', 'Port', default: 5577
        o.string '-b', '--base', 'Database name', default: 'pandora.sqlite'
        o.bool '-pl', '--poly', 'Enable poly launch', default: false
      end
    end

  end
end

# Loading app configuration
# Загрузка конфигурации приложения
require "#{Pandora.root}/config/application"

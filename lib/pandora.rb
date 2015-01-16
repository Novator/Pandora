# Bundler to manage gems
# Используем Bundler
require 'rubygems'
require 'bundler/setup'

# Debug tool
# Гем для отладки приложения
require 'byebug'

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

module Pandora
  # Очередной гениальный файл...
end

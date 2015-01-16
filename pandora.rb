#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# P2P national network Pandora
# RU: P2P народная сеть Пандора
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

# Loading lib dir
# Загрузка библиотек из папки lib
root_path = File.expand_path("../", __FILE__)
require "#{root_path}/lib/pandora"
Dir["#{root_path}/lib/**/*.rb"].each {|f| require f}


# Array of localization phrases
# RU: Вектор переведеных фраз
$lang_trans = {}

# Translation of the phrase
# RU: Перевод фразы
def _(frase)
  trans = $lang_trans[frase]
  if not trans or (trans.size==0) and frase and (frase.size>0)
    trans = frase
  end
  trans
end

# ============================================================
# MAIN

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки
arg = nil
val = nil
next_arg = nil
while (ARGV.length>0) or next_arg
  if next_arg
    arg = next_arg
    next_arg = nil
  else
    arg = ARGV.shift
  end
  if (arg.is_a? String) and (arg[0,1]=='-')
    if ARGV.length>0
      next_arg = ARGV.shift
    end
    if next_arg and next_arg.is_a? String and (next_arg[0,1] != '-')
      val = next_arg
      next_arg = nil
    end
  end
  case arg
    when '-h','--host'
      Pandora.config.host = val if val
    when '-p','--port'
      Pandora.config.port = val.to_i if val
    when '-b', '--base'
      $pandora_sqlite_db = val if val
    when '-pl', '--poly', '--poly-launch'
      Pandora.config.poly_launch = true
    when '--shell', '--help', '/?', '-?'
      runit = '  '
      if arg=='--shell' then
        runit += 'pandora.sh'
      else
        runit += 'ruby pandora.rb'
      end
      runit += ' '
      puts 'Оriginal Pandora params for examples:'
      puts runit+'-h localhost    - set listen address'
      puts runit+'-p 5577         - set listen port'
      puts runit+'-b base/pandora2.sqlite  - set filename of database'
      Kernel.exit!
  end
  val = nil
end

# Check second launch
# RU: Проверить второй запуск

PANDORA_USOCK = '/tmp/pandora_unix_socket'
$pserver = nil

# Delete Pandora unix socket
# RU: Удаляет unix-сокет Пандоры
def delete_psocket
  File.delete(PANDORA_USOCK) if File.exist?(PANDORA_USOCK)
end

$win32api = false

# Initialize win32 unit
# RU: Инициализирует модуль win32
def init_win32api
  if not $win32api
    begin
      require 'Win32API'
      $win32api = true
    rescue Exception
      $win32api = false
    end
  end
  $win32api
end

MAIN_WINDOW_TITLE = 'Pandora'
GTK_WINDOW_CLASS = 'gdkWindowToplevel'

# Prevent second execution
# RU: Предотвратить второй запуск
if not Pandora.config.poly_launch
  if Pandora::Utils.os_family=='unix'
    psocket = nil
    begin
      psocket = UNIXSocket.new(PANDORA_USOCK)
    rescue
      psocket = nil
    end
    if psocket
      psocket.send('Activate', 0)
      psocket.close
      Kernel.exit
    else
      begin
        delete_psocket
        $pserver = UNIXServer.new(PANDORA_USOCK)
        Thread.new do
          while not $pserver.closed?
            psocket = $pserver.accept
            if psocket
              Thread.new(psocket) do |psocket|
                while not psocket.closed?
                  command = psocket.recv(255)
                  if ($window and command and (command != ''))
                    $window.do_menu_act(command)
                  else
                    psocket.close
                  end
                end
              end
            end
          end
        end
      rescue
        $pserver = nil
      end
    end
  elsif (Pandora::Utils.os_family=='windows') and init_win32api
    FindWindow = Win32API.new('user32', 'FindWindow', ['P', 'P'], 'L')
    win_handle = FindWindow.call(GTK_WINDOW_CLASS, MAIN_WINDOW_TITLE)
    if (win_handle.is_a? Integer) and (win_handle>0)
      #ShowWindow = Win32API.new('user32', 'ShowWindow', 'L', 'V')
      #ShowWindow.call(win_handle, 5)  #SW_SHOW=5, SW_RESTORE=9
      SetForegroundWindow = Win32API.new('user32', 'SetForegroundWindow', 'L', 'V')
      SetForegroundWindow.call(win_handle)
      Kernel.abort('Another copy of Pandora is already runned')
    end
  end
end

# Check Ruby version and init ASCII string class
# RU: Проверить версию Ruby и объявить класс ASCII-строки
if RUBY_VERSION<'1.9'
  puts 'Pandora requires Ruby1.9 or higher - current '+RUBY_VERSION
  exit(10)
else
  class AsciiString < String
    def initialize(str=nil)
      if str == nil
        super('')
      else
        super(str)
      end
      force_encoding('ASCII-8BIT')
    end
  end
  class Utf8String < String
    def initialize(str=nil)
      if str == nil
        super('')
      else
        super(str)
      end
      force_encoding('UTF-8')
    end
  end
  Encoding.default_external = 'UTF-8'
  Encoding.default_internal = 'UTF-8' #BINARY ASCII-8BIT UTF-8
end

# Redirect console output to file, because of rubyw.exe crush
# RU: Перенаправить консольный вывод в файл из-за краша rubyw.exe
if Pandora::Utils.os_family=='windows'
  $stdout.reopen(File.join(Pandora.base_dir, 'stdout.log'), 'w')
  $stderr = $stdout
end

# Get language from environment parameters
# RU: Взять язык из переменных окружения
lang = ENV['LANG']
if (lang.is_a? String) and (lang.size>1)
  Pandora.config.lang = lang[0, 2].downcase
end
#Pandora.config.lang = 'en'

# Some settings
# RU: Некоторые настройки
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# == Running the Pandora!
# == RU: Запуск Пандоры!
Pandora::Utils.load_language(Pandora.config.lang)
Pandora::Model.load_from_xml(Pandora.config.lang)
Pandora::Gtk::MainWindow.new(MAIN_WINDOW_TITLE)

# Free unix-socket on exit
# Освободить unix-сокет при выходе
$pserver.close if ($pserver and (not $pserver.closed?))
delete_psocket


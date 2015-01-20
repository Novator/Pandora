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
if RUBY_VERSION < '1.9'
  puts 'Pandora requires Ruby1.9 or higher - current ' + RUBY_VERSION
  exit(10)
else
  # Loading lib dir
  # Загрузка библиотек из папки lib
  root_path = File.expand_path("../", __FILE__)
  require "#{root_path}/lib/pandora"

  # Debug
  Pandora.logger.debug "Application lib files loaded"

  # Check second launch
  # RU: Проверить второй запуск

  $pserver = nil

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

  # ============================================================
  # MAIN
  Pandora.logger.debug "Application starting..."
  Pandora.app.run
  Pandora.logger.debug "Application started successfully"

  # Free unix-socket on exit
  # Освободить unix-сокет при выходе
  $pserver.close if ($pserver and (not $pserver.closed?))
  delete_psocket

end

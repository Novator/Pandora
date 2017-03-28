#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Mutual user interface (UI) of Pandora
# RU: Общий интерфейс пользователя Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2017 (c) Michael Galyuk
# RU: 2017 (c) Михаил Галюк

require File.expand_path('../utils.rb',  __FILE__)

def require_gtk
  res = $gtk_is_active
  require File.expand_path('../gtk.rb',  __FILE__) if not res
  res = $gtk_is_active
end

def require_ncurses
  res = $ncurses_is_active
  require File.expand_path('../ncurses.rb',  __FILE__) if not res
  res = $ncurses_is_active
end

$gtk_is_active = false
$ncurses_is_active = false

module PandoraUI

  # Log levels
  # RU: Уровни логирования
  LM_Error    = 0
  LM_Warning  = 1
  LM_Info     = 2
  LM_Trace    = 3

  # Log level on human view
  # RU: Уровень логирования по-человечьи
  def self.level_to_str(level)
    mes = ''
    case level
      when LM_Error
        mes = _('Error')
      when LM_Warning
        mes = _('Warning')
      when LM_Trace
        mes = _('Trace')
    end
    mes
  end

  # Main application window
  # RU: Главное окно приложения
  $window = nil

  # Maximal lines in log textview
  # RU: Максимум строк в лотке лога
  MaxLogViewLineCount = 500

  # Default log level
  # RU: Уровень логирования по умолчанию
  $show_log_level = LM_Trace

  # Auto show log textview when this error level is achived
  # RU: Показать лоток лога автоматом, когда этот уровень ошибки достигнут
  $show_logbar_level = LM_Warning

  # Add the message to log
  # RU: Добавить сообщение в лог
  def self.log_message(level, mes)
    if (level <= $show_log_level)
      time = Time.now
      lev = level_to_str(level)
      lev = ' ['+lev+']' if (lev.is_a? String) and (lev.size>0)
      lev ||= ''
      mes = time.strftime('%H:%M:%S') + lev + ': '+mes
      log_view = $window.log_view
      if log_view
        value = log_view.parent.vadjustment.value
        log_view.before_addition(time, value)
        log_view.buffer.insert(log_view.buffer.end_iter, mes+"\n")
        aline_count = log_view.buffer.line_count
        if aline_count>MaxLogViewLineCount
          first = log_view.buffer.start_iter
          last = log_view.buffer.get_iter_at_line_offset(aline_count-MaxLogViewLineCount-1, 0)
          log_view.buffer.delete(first, last)
        end
        log_view.after_addition
        if $show_logbar_level and (level<=$show_logbar_level)
          $show_logbar_level = nil
          PandoraGtk.show_log_bar(80)
        end
      end
      puts 'log: '+mes
    end
  end

  # Init user interface
  # RU: Инициилизировать интерфейс пользователя
  def self.init(cui_mode)
    if cui_mode
      require_ncurses
      PandoraCui.show_window
    else
      require_gtk
      PandoraGtk::MainWindow.new(MAIN_WINDOW_TITLE)
    end
  end


end


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
  if not $gtk_is_active
    require File.expand_path('../gtk.rb',  __FILE__)
  end
  res = $gtk_is_active
end

def require_ncurses
  if not $ncurses_is_active
    require File.expand_path('../ncurses.rb',  __FILE__)
  end
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
      PandoraCui.init_main_window
    else
      require_gtk
      PandoraGtk::MainWindow.new(MAIN_WINDOW_TITLE)
    end
  end

  # Statusbar fields
  # RU: Поля в статусбаре
  SF_Log     = 0
  SF_FullScr = 1
  SF_Update  = 2
  SF_Lang    = 3
  SF_Auth    = 4
  SF_Listen  = 5
  SF_Hunt    = 6
  SF_Conn    = 7
  SF_Radar   = 8
  SF_Fisher  = 9
  SF_Search  = 10
  SF_Harvest = 11

  # Set properties of fiels in statusbar
  # RU: Задаёт свойства поля в статусбаре
  def self.set_status_field(index, text, enabled=nil, toggle=nil)
    if $ncurses_is_active
      PandoraCui.set_status_field(index, text, enabled, toggle)
    elsif $gtk_is_active
      $window.set_status_field(index, text, enabled, toggle)
    end
  end

  # Menu event handler
  # RU: Обработчик события меню
  def self.do_menu_act(command, treeview=nil)
    if $ncurses_is_active
      PandoraCui.do_menu_act(command, treeview)
    elsif $gtk_is_active
      $window.do_menu_act(command, treeview)
    end
  end

  # Update or show radar panel
  # RU: Обновить или показать панель радара
  def self.update_or_show_radar_panel
    if $ncurses_is_active
      PandoraCui.show_radar_panel
    elsif $gtk_is_active
      hpaned = $window.radar_hpaned
      if (hpaned.max_position - hpaned.position) > 24
        radar_sw = $window.radar_sw
        radar_sw.update_btn.clicked
      else
        PandoraGtk.show_radar_panel
      end
    end
  end

  # Change listener button state
  # RU: Изменить состояние кнопки слушателя
  def self.correct_lis_btn_state
    if $ncurses_is_active
      PandoraCui.correct_lis_btn_state
    elsif $gtk_is_active
      $window.correct_lis_btn_state
    end
  end

  # Change hunter button state
  # RU: Изменить состояние кнопки охотника
  def self.correct_hunt_btn_state
    if $ncurses_is_active
      PandoraCui.correct_hunt_btn_state
    elsif $gtk_is_active
      $window.correct_hunt_btn_state
    end
  end

  # Is captcha window available?
  # RU: Окно для ввода капчи доступно?
  def self.captcha_win_available?
    res = nil
    if $ncurses_is_active
      res = false
    elsif $gtk_is_active
      res = $window.visible? #and $window.has_toplevel_focus?
    end
    res
  end

  # Capinet page indexes
  # RU: Индексы страниц кабинета
  CPI_Property  = 0
  CPI_Profile   = 1
  CPI_Opinions  = 2
  CPI_Relations = 3
  CPI_Signs     = 4
  CPI_Chat      = 5
  CPI_Dialog    = 6
  CPI_Editor    = 7

  CPI_Sub       = 1
  CPI_Last_Sub  = 4
  CPI_Last      = 7

  # Show panobject cabinet
  # RU: Показать кабинет панобъекта
  def self.show_cabinet(panhash, session=nil, conntype=nil, \
  node_id=nil, models=nil, page=nil, fields=nil, obj_id=nil, edit=nil)
    res = nil
    if $ncurses_is_active
      res = PandoraCui.show_cabinet(panhash, session, conntype, node_id, models, \
        page, fields, obj_id, edit)
    elsif $gtk_is_active
      res = PandoraGtk.show_cabinet(panhash, session, conntype, node_id, models, \
        page, fields, obj_id, edit)
    end
    res
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, page_sw=nil, \
  auto_create=false, fix_filter=nil)
    res = nil
    if $ncurses_is_active
      res = PandoraCui.show_panobject_list(panobject_class, widget, page_sw, \
        auto_create, fix_filter)
    elsif $gtk_is_active
      res = PandoraGtk.show_panobject_list(panobject_class, widget, page_sw, \
        auto_create, fix_filter)
    end
    res
  end


end


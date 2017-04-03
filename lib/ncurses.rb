#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Console interface of Pandora
# RU: Консольный интерфейс Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2017 (c) Michael Galyuk
# RU: 2017 (c) Михаил Галюк

$curses_is_active = false

# Init NCurses or Curses
# RU: Инициализировать NCurses или Curses
begin
  require 'ncurses'
  module Ncurses
    Window = WINDOW
    def self.color_pair(num)
      COLOR_PAIR(num)
    end
    def self.lines
      LINES()
    end
    def self.cols
      COLS()
    end
    def self.mousemask2(flags)
      mousemask(flags, [])
    end
    def self.init_screen
      initscr
    end
    def self.close_screen
      endwin
    end
    def self.getmouse2(mev)
      getmouse(mev)
      mev
    end
  end
  $ncurses_is_active = true
rescue Exception
  begin
    require 'curses'
    Ncurses = Curses
    module Curses
      MEVENT = nil
      class Window
        def mvaddstr(y, x, str)
          setpos(y, x)
          addstr(str)
        end
        def move(y, x)
          setpos(y, x)
        end
      end
      def self.mousemask2(flags)
        mousemask(flags)
      end
      def self.getmouse2(mev)
        res = getmouse
      end
      def self.newwin(height, width, y, x)
        res = Ncurses::Window.new(height, width, y, x)
      end
      def self.delwin(win)
        win.close if win
      end
    end
    $ncurses_is_active = true
    $curses_is_active = true
  rescue Exception
    Kernel.abort('NCurses and Curses cannot be activated')
  end
end


module PandoraCui

  def self.cui_inited
    @cui_inited
  end

  def self.cui_inited=(val)
    @cui_inited = val
  end

  def self.cur_page=(val)
    @cur_page = val
  end

  def self.cur_page
    @cur_page
  end

  def self.act_panel=(val)
    @act_panel = val
  end

  def self.act_panel
    @act_panel
  end

  def self.curse_windows=(val)
    @curse_windows = val
  end

  def self.curse_windows
    @curse_windows
  end

  def self.user_command=(val)
    @user_command = val
  end

  def self.user_command
    @user_command
  end

  MaxLogSize = 100
  LastLogMessages = []

  def self.add_mes_to_log_win(mes, refresh=nil)
    while LastLogMessages.size >= MaxLogSize
      LastLogMessages.delete(0)
    end
    LastLogMessages << mes
    if self.cui_inited and (self.cur_page == CPI_Status)
      line = mes
      line = "\n" + line if LastLogMessages.size>1
      right_win = self.curse_windows[CWI_RightArea]
      if right_win
        $pool.mutex.synchronize do
          right_win.addstr(line)
          #right_win.addstr(right_win.methods.inspect+"\n")
          if refresh
            right_win.noutrefresh
            Ncurses.doupdate  # update real screen
            #Ncurses.refresh
          end
        end
      end
    end
  end

  def self.set_status_field(index, text, enabled, toggle)
    self.add_mes_to_log_win('set_status_field: '+[index, text, \
      enabled, toggle].inspect, true)
    case index
      when PandoraUI::SF_Auth
        @auth_text = text
    end
    self.show_status_bar
  end

  def self.correct_lis_btn_state
    self.add_mes_to_log_win('correct_lis_btn_state', true)
    self.show_status_bar
  end

  def self.correct_hunt_btn_state
    self.add_mes_to_log_win('correct_hunt_btn_state', true)
    self.show_status_bar
  end

  # Create person "Ncurses Robot"
  def self.create_ncurses_robot_person
    values = {'first_name'=>'Ncurses', 'last_name'=>'Robot'}
    lang = PandoraModel.text_to_lang('en')
    res = PandoraModel.save_record(PandoraModel::PK_Person, lang, values)
  end

  # Ask user and password for key pair generation
  # RU: Запросить пользователя и пароль для генерации ключевой пары
  def self.ask_user_and_password(rights=nil)
    res = nil
    creator = self.create_ncurses_robot_person
    password = ''
    rights ||= (PandoraCrypto::KS_Exchange | PandoraCrypto::KS_Voucher)
    yield(creator, password, rights) if block_given?
    res
  end

  # Ask key and password for authorization
  # RU: Запросить ключ и пароль для авторизации
  def self.ask_key_and_password(alast_auth_key=nil)
    res = nil
    key_hash = alast_auth_key
    password = ''
    change_pass = false
    new_pass = nil
    yield(key_hash, password, 1, change_pass, new_pass) if block_given?
    res
  end

  def self.show_dialog(mes, do_if_ok=true)
    res = nil
    self.add_mes_to_log_win('show_dialog: '+mes, true)
    ok_pressed = true
    yield(ok_pressed) if block_given?
    res
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, page_sw=nil, \
  auto_create=false, fix_filter=nil)
    res = nil
    self.add_mes_to_log_win('show_panobject_list: '+[panobject_class, widget, \
      page_sw, auto_create, fix_filter].inspect, true)
    res
  end

  def self.show_cabinet(panhash, session, conntype, node_id, models, \
  page, fields, obj_id, edit)
    res = nil
    self.add_mes_to_log_win('show_cabinet: '+[panhash, session, conntype, \
      node_id, models, page, fields, obj_id, edit].inspect, true)
    res
  end

  def self.fill_left_log_win
    left_win = self.curse_windows[CWI_LeftArea]
    left_win.mvaddstr(1, 1, 'Log')
    left_win.mvaddstr(2, 1, 'User')
    left_win.mvaddstr(3, 1, 'Listen')
    left_win.mvaddstr(4, 1, 'Hunt')
    left_win.mvaddstr(5, 1, 'Sessions')
  end

  def self.fill_right_log_win
    asize = LastLogMessages.size
    right_win = self.curse_windows[CWI_RightArea]
    num = @win_height-2
    num = asize if num > asize
    right_win.clear
    num.times do |i|
      line = LastLogMessages[asize-(num-i)]
      line = "\n"+line if i>0
      right_win.addstr(line)
    end
  end

  def self.create_win(height, width, y, x, box_index, title, color, active=true)
    res = Ncurses.newwin(height, width, y, x)
    self.curse_windows[box_index] = res
    color = (color | Ncurses::A_BOLD) if active
    res.attron(color)
    res.box(0, 0)
    res.mvaddstr(0, 2, title) if title
    res2 = Ncurses.newwin(height-2, width-2, y+1, x+1)
    self.curse_windows[box_index+1] = res2
    res2.bkgd(0)
    res2.scrollok(true)
    res2
  end

  CWI_LeftBox   = 0
  CWI_LeftArea  = 1
  CWI_RightBox  = 2
  CWI_RightArea = 3

  def self.do_with_windows(doing=:noutrefresh)
    self.curse_windows.each do |win|
      case doing
        when :noutrefresh
          win.noutrefresh
        when :del
          Ncurses.delwin(win)
      end
    end
  end

  def self.del_windows
    do_with_windows(:del)
    self.curse_windows.clear
  end

  def self.do_user_command(acommand, press_key=true)
    self.user_command = acommand
    Ncurses.ungetch(32) if press_key
  end

  CPI_Status   = 0
  CPI_Radar    = 1
  CPI_Base     = 2
  CPI_Find     = 3
  CPI_Quit     = 4
  CPI_Auth     = 5
  CPI_Listen   = 6
  CPI_Hunt     = 7

  LeftTitles = ['Status', 'Radar', 'Base', 'Find']
  RightTitles = ['Log', 'Dialog', 'Record', 'Parameters']
  PanelEdges = []

  def self.show_status_bar
    edge = PanelEdges[CPI_Quit]
    if edge and (edge>0) and $pool
      edge += 2
      $pool.mutex.synchronize do
        stdscr = Ncurses.stdscr
        authorized = PandoraCrypto.authorized?
        listening = PandoraNet.listen?
        hunting = PandoraNet.hunting?
        stdscr.move(Ncurses.lines - 1, edge)
        stdscr.addstr(' '*(Ncurses.cols-edge))
        if authorized
          stdscr.attron(Ncurses.color_pair(5) | Ncurses::A_BOLD)
        end
        stdscr.move(Ncurses.lines - 1, edge)
        stdscr.addstr('U')
        stdscr.attron(Ncurses.color_pair(0))
        if @auth_text and (@auth_text.size>0)
          stdscr.addstr(':'+@auth_text)
          edge += (1+@auth_text.size)
        end
        if authorized
          stdscr.attroff(Ncurses.color_pair(5) | Ncurses::A_BOLD)
        end
        stdscr.addstr(' ')
        edge += 2
        PanelEdges[CPI_Auth] = edge
        if listening
          stdscr.attron(Ncurses.color_pair(6) | Ncurses::A_BOLD)
        end
        stdscr.addstr('L')
        if listening
          stdscr.attroff(Ncurses.color_pair(6) | Ncurses::A_BOLD)
        end
        stdscr.attron(Ncurses.color_pair(0))
        stdscr.addstr(' ')
        edge += 2
        PanelEdges[CPI_Listen] = edge
        if hunting
          stdscr.attron(Ncurses.color_pair(7) | Ncurses::A_BOLD)
        end
        stdscr.addstr('H')
        if hunting
          stdscr.attroff(Ncurses.color_pair(7) | Ncurses::A_BOLD)
        end
        stdscr.attron(Ncurses.color_pair(0))
        edge += 2
        PanelEdges[CPI_Hunt] = edge
        if PandoraUI.runned_via_screen
          stdscr.addstr(' | Ctrl+A,D')
        end
      end
    end
  end

  def self.recreate_windows(page=nil)
    self.cur_page = page if page
    is_resized = true
    first_start = false
    while is_resized
      self.cui_inited = false
      is_resized = false
      if self.curse_windows
        del_windows
        #Ncurses.close_screen
        Ncurses.refresh if $curses_is_active
      else
        self.curse_windows = []
        first_start = true
        100.times do
          sleep(0.001)
        end
      end
      stdscr = Ncurses.stdscr

      left_width = 20
      win_height = Ncurses.lines-1
      @left_width = left_width
      @win_height = win_height

      min_width = left_width+7
      edge = PanelEdges[CPI_Hunt]
      min_width = edge if edge and (edge>min_width)
      if (min_width < Ncurses.cols) and (win_height>3)
        color = Ncurses.color_pair(self.cur_page+1)
        left_win = create_win(win_height, left_width, 0, 0, CWI_LeftBox, \
          LeftTitles[self.cur_page], color, self.act_panel==0)
        left_win.keypad(true)
        right_win = create_win(win_height, Ncurses.cols - left_width, 0, left_width, \
          CWI_RightBox, RightTitles[self.cur_page], color, self.act_panel==1)
        case self.cur_page
          when CPI_Status
            fill_left_log_win
            fill_right_log_win
        end

        stdscr.move(Ncurses.lines - 1, 0)
        edge = 0
        LeftTitles.each_with_index do |title, ind|
          color = 0
          if ind==self.cur_page
            color = Ncurses.color_pair(ind+1)
          end
          stdscr.attron(color | Ncurses::A_BOLD)
          stdscr.addstr(title[0].upcase)
          stdscr.attroff(Ncurses::A_BOLD)
          stdscr.addstr(title[1..-1])
          stdscr.attroff(color)
          stdscr.addstr(' ')
          edge += title.size+1
          PanelEdges[ind] = edge
        end
        PanelEdges[CPI_Quit] = edge + 5
        #right_win.addstr(PanelEdges.inspect+ "\n")
        stdscr.attron(Ncurses::A_BOLD)
        stdscr.addstr('Q')
        stdscr.attroff(Ncurses::A_BOLD)
        stdscr.addstr('uit | ')
        self.show_status_bar
      else
        stdscr.addstr('Screen is too small')
      end

      do_with_windows(:noutrefresh)
      Ncurses.doupdate  # update real screen

      self.cui_inited = true

      if first_start
        first_start = false
        yield if block_given?
      end

      mev = nil
      mev = Ncurses::MEVENT.new if Ncurses::MEVENT
      ch = 0
      while ch
        ch = Ncurses.getch
        if self.user_command
          comm = self.user_command
          self.user_command = nil
          case comm
            when :close
              break
          end
        else
          stdscr.mvaddstr(Ncurses.lines - 3, 28, '1:'+ch.inspect+'  ')
          stdscr.refresh
          if (ch==27)
            sleep 0.2
            chg = Ncurses.getch
            ch = (chg ^ (ch << 8))
            if (chg==208) or (chg==209)
              chg = Ncurses.getch
              ch = (chg ^ (ch << 8))
            end
            stdscr.mvaddstr(Ncurses.lines - 3, 28, '2:'+ch.inspect+'-  ')
            stdscr.refresh
          end
          case ch
            when Ncurses::KEY_RESIZE
              is_resized = true
              break
            when Ncurses::KEY_F1, Ncurses::KEY_F5, 19  #Ctrl+S
              self.cur_page = CPI_Status
              is_resized = true
              break
            when Ncurses::KEY_F2, Ncurses::KEY_F6, 18  #Ctrl+R
              self.cur_page = CPI_Radar
              is_resized = true
              break
            when Ncurses::KEY_F3, Ncurses::KEY_F7, 2  #Ctrl+B
              self.cur_page = CPI_Base
              is_resized = true
              break
            when Ncurses::KEY_F4, Ncurses::KEY_F8, 6  #Ctrl+F
              self.cur_page = CPI_Find
              is_resized = true
              break
            when Ncurses::KEY_NPAGE
              if self.cur_page < CPI_Find
                self.cur_page += 1
              else
                self.cur_page = 0
              end
              is_resized = true
              break
            when Ncurses::KEY_PPAGE
              if self.cur_page > 0
                self.cur_page -= 1
              else
                self.cur_page = CPI_Find
              end
              is_resized = true
              break
            when 9, 353   #Tab, Shift+Tab
              if self.act_panel>0
                self.act_panel = 0
              else
                self.act_panel = 1
              end
              is_resized = true
              break
            when Ncurses::KEY_RIGHT
              if self.act_panel>0
                if self.cur_page < CPI_Find
                  self.cur_page += 1
                else
                  self.cur_page = 0
                end
              else
                self.act_panel = 1
              end
              is_resized = true
              break
            when Ncurses::KEY_LEFT
              if self.act_panel==0
                if self.cur_page > 0
                  self.cur_page -= 1
                else
                  self.cur_page = CPI_Find
                end
              else
                self.act_panel = 0
              end
              is_resized = true
              break
            when 21  #U
              PandoraUI.do_menu_act('Authorize')
            when 12  #L
              PandoraUI.do_menu_act('Listen')
            when 8   #H
              PandoraUI.do_menu_act('Hunt')
            when Ncurses::KEY_MOUSE
              if mev = Ncurses.getmouse2(mev)
                #Ncurses.ungetmouse(mev)
                if (mev.bstate == 4)
                  x = mev.x
                  if (mev.y < win_height)
                    if x < left_width
                      self.act_panel = 0
                    else
                      self.act_panel = 1
                    end
                    is_resized = true
                    break
                  else
                    ind = nil
                    PanelEdges.count.times do |i|
                      if x < PanelEdges[i]
                        ind = i
                        break
                      end
                    end
                    if ind
                      if ind <= CPI_Quit
                        if ind < CPI_Quit
                          self.cur_page = ind
                          is_resized = true
                        end
                        break
                      else
                        case ind
                          when CPI_Auth
                            PandoraUI.do_menu_act('Authorize')
                          when CPI_Listen
                            PandoraUI.do_menu_act('Listen')
                          when CPI_Hunt
                            PandoraUI.do_menu_act('Hunt')
                        end
                      end
                    else
                      stdscr.mvaddstr(Ncurses.lines - 3, 50, p.inspect+'  ')
                      stdscr.refresh
                      sleep 0.5
                    end
                  end
                else
                  stdscr.mvaddstr(Ncurses.lines - 3, 50, [mev.bstate, mev.x, mev.y].inspect+'  ')
                  stdscr.refresh
                end
              end
              #fields_form.form_driver(ch)
              #Ncurses.curs_set(1)
            when Ncurses::KEY_F8
              add_mes_to_log_win(('Just a log text '*8)+LastLogMessages.size.to_s, true)
              #right_win.addstr(right_win.methods.inspect+"\n")
              #right_win.noutrefresh
            when Ncurses::KEY_F10, 3, 17, 7000, 7032, 1823111, 1822887, 81, 113, \
            153, 185   #Ctrl+C, Ctrl+Q, Alt+X, Alt+x, Alt+Ч, Alt+ч, Q, q, Й, й
              PandoraUI.do_menu_act('Quit')
            else
              #Ncurses.curs_set(1)
          end
        end
      end
    end
  end

  def self.do_main_loop
    self.cui_inited = false
    self.user_command = nil
    self.cur_page = CPI_Status
    self.act_panel = 0
    Ncurses.init_screen
    begin
      Ncurses.cbreak
      Ncurses.noecho
      Ncurses.raw

      Ncurses.start_color
      Ncurses.curs_set(0)
      Ncurses.nonl

      stdscr = Ncurses.stdscr
      ##stdscr.intrflush(false)
      stdscr.keypad(true)

      Ncurses.mousemask2(Ncurses::BUTTON1_CLICKED)

      Ncurses.init_pair(1, Ncurses::COLOR_GREEN, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(2, Ncurses::COLOR_CYAN, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(3, Ncurses::COLOR_YELLOW, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(4, Ncurses::COLOR_MAGENTA, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(5, Ncurses::COLOR_BLUE, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(6, Ncurses::COLOR_GREEN, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(7, Ncurses::COLOR_RED, Ncurses::COLOR_BLACK)
      stdscr.bkgd(Ncurses.color_pair(0))
      Ncurses.refresh
      recreate_windows do
        yield if block_given?
      end
      stdscr.bkgd(0)
      Ncurses.clear
      Ncurses.refresh
    ensure
      Ncurses.curs_set(1)
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      Ncurses.close_screen
    end
    puts('Pandora finished.')
  end

end


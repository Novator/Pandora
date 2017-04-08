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
        def mvaddch(y, x, ch)
          setpos(y, x)
          addch(ch)
        end
        def move(y, x)
          setpos(y, x)
        end
        def mvhline(y, x, ch, num)
          box(ch, ch)
        end
        def erase
          clear
        end
        def getmaxx
          maxx
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

  def self.mutex
    @mutex ||= Mutex.new
  end

  MaxLogSize = 100
  LastLogMessages = []

  def self.add_mes_to_log_win(mes, refresh=nil)
    while LastLogMessages.size >= MaxLogSize
      LastLogMessages.delete(0)
    end
    LastLogMessages << mes
    if self.cui_inited and (self.cur_page == LMI_Status)
      menu_pos = LeftWinMenuPos[self.cur_page]
      if menu_pos and (menu_pos == RPI_Log)
        line = mes
        line = "\n" + line if LastLogMessages.size>1
        right_win = self.curse_windows[CWI_RightArea]
        if right_win
          self.mutex.synchronize do
            right_win.addstr(line)
            #right_win.addstr(right_win.methods.inspect+"\n")
            if refresh
              right_win.noutrefresh
              Ncurses.doupdate if refresh==2
              #Ncurses.refresh
            end
          end
        end
      end
    end
  end

  def self.set_status_field(index, text, enabled, toggle)
    self.add_mes_to_log_win('set_status_field: '+[index, text, \
      enabled, toggle].inspect, 1)
    case index
      when PandoraUI::SF_Auth
        @auth_text = text
    end
    self.show_status_bar(2)
  end

  def self.correct_lis_btn_state
    self.add_mes_to_log_win('correct_lis_btn_state', 1)
    self.show_status_bar(2)
  end

  def self.correct_hunt_btn_state
    self.add_mes_to_log_win('correct_hunt_btn_state', 1)
    self.show_status_bar(2)
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
    self.add_mes_to_log_win('show_dialog: '+mes, 2)
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
      page_sw, auto_create, fix_filter].inspect, 2)
    res
  end

  def self.show_cabinet(panhash, session, conntype, node_id, models, \
  page, fields, obj_id, edit)
    res = nil
    self.add_mes_to_log_win('show_cabinet: '+[panhash, session, conntype, \
      node_id, models, page, fields, obj_id, edit].inspect, 2)
    res
  end

  CWI_LeftBox   = 0
  CWI_LeftArea  = 1
  CWI_RightBox  = 2
  CWI_RightArea = 3

  LeftTitles = ['Status', 'Radar', 'Base', 'Find']

  LMI_Status   = 0
  LMI_Radar    = 1
  LMI_Base     = 2
  LMI_Find     = 3
  LMI_Quit     = 4
  LMI_Auth     = 5
  LMI_Listen   = 6
  LMI_Hunt     = 7

  MenuItems = [['Log', 'User', 'Listen', 'Hunt', 'Sessions'], nil]

  RPI_Log   = 0
  RPI_User  = 1

  PanelEdges = []
  LeftWinMenuPos = [0, nil]

  ACS_UARROW_ALT   = 45
  ACS_DARROW_ALT   = 46
  ACS_DIAMOND_ALT  = 96
  ACS_VLINE_ALT    = 120

  StatusScrollPos = []
  StatusScrollPosPrev = []

  def self.fill_left_win(menu_move=nil, refresh=nil)
    left_win = self.curse_windows[CWI_LeftArea]
    page = self.cur_page
    menu_items = MenuItems[page]
    if menu_items
      right_box = self.curse_windows[CWI_RightBox]
      menu_items_count = menu_items.size
      menu_pos = LeftWinMenuPos[page]
      if (not menu_pos) or menu_move
        menu_pos ||= 0
        if menu_move
          if menu_move==1
            if (menu_pos+menu_move)<menu_items_count
              menu_pos += menu_move
            else
              menu_pos = 0
            end
          elsif menu_move==-1
            if (menu_pos+menu_move)>=0
              menu_pos += menu_move
            else
              menu_pos = menu_items_count-1
            end
          elsif menu_move>0
            menu_pos += menu_move
            menu_pos = menu_items_count-1 if menu_pos>=menu_items_count
          else
            menu_pos += menu_move
            menu_pos = 0 if menu_pos<0
          end
        end
        LeftWinMenuPos[page] = menu_pos
      end
      menu_items.each_with_index do |mi, i|
        attr = nil
        if i==menu_pos
          if self.act_panel==0
            attr = Ncurses::A_REVERSE
          else
            attr = Ncurses::A_BOLD
          end
        end
        left_win.attron(attr) if attr
        spaces = ''
        len = @left_width-2-mi.size
        spaces = ' '*len if len>0
        left_win.mvaddstr(i, 0, mi+spaces)
        left_win.attroff(attr) if attr
      end
      title = menu_items[menu_pos]
      if title
        num = right_box.getmaxx-2
        right_box.mvhline(0, 1, 0, num)
        right_box.mvaddstr(0, 2, title)
        right_scr_x = Ncurses.cols-@left_width-1
        right_box.attron(Ncurses::A_ALTCHARSET)
        right_box.mvaddch(1, right_scr_x, ACS_UARROW_ALT)
        right_box.mvaddch(@win_height-2, right_scr_x, ACS_DARROW_ALT)
        right_box.attroff(Ncurses::A_ALTCHARSET)
      end
      if refresh
        left_win.noutrefresh
        right_box.noutrefresh if title
        Ncurses.doupdate if refresh==2
      end
    end
  end

  def self.fill_right_win(refresh=nil)
    right_win = self.curse_windows[CWI_RightArea]
    right_box = self.curse_windows[CWI_RightBox]
    page = self.cur_page
    menu_items = MenuItems[page]
    if menu_items
      menu_pos = LeftWinMenuPos[page]
      case page
        when LMI_Status
          right_win.erase
          if menu_pos == RPI_Log
            scroll_pos = StatusScrollPos[RPI_Log]
            if not scroll_pos
              scroll_pos = 0
              StatusScrollPos[RPI_Log] = scroll_pos
            end
            asize = LastLogMessages.size
            num = @win_height-2
            num = asize if num > asize
            num.times do |i|
              #line = scroll_pos + asize-(num-i)
              line = scroll_pos + i #+ (num-i) + 1
              str = LastLogMessages[line]
              if str
                str = "\n"+str if i>0
                right_win.addstr(str)
              end
            end
            #pos = StatusScrollPosPrev[RPI_Log]
            #if pos
            #  right_box.attron(Ncurses::A_ALTCHARSET | Ncurses::A_REVERSE)
            #  right_scr_x = Ncurses.cols-@left_width-1
            #  right_box.mvaddch(pos, right_scr_x, ACS_DIAMOND_ALT)
            #  right_box.attroff(Ncurses::A_ALTCHARSET | Ncurses::A_REVERSE)
            #end
            #right_box.mvaddstr(1, Ncurses.cols-@left_width-5, '1') #Ncurses::ACS_UARROW
            #right_win.addstr("\n"+right_win.methods.inspect)
            #right_win.addstr("\n"+Ncurses.methods[0..110].inspect)
          end
      end
    end
    if refresh
      right_win.noutrefresh
      Ncurses.doupdate if refresh==2
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

  def self.process_command(comm)
    need_break = false
    case comm
      when :close
        need_break = true
    end
    need_break
  end

  def self.emulate_user_command(comm)
    self.user_command = comm
    Ncurses.ungetch(32)
  end

  def self.show_status_bar(refresh=nil)
    edge = PanelEdges[LMI_Quit]
    if edge and (edge>0)
      edge += 2
      self.mutex.synchronize do
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
        PanelEdges[LMI_Auth] = edge
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
        PanelEdges[LMI_Listen] = edge
        if hunting
          stdscr.attron(Ncurses.color_pair(7) | Ncurses::A_BOLD)
        end
        stdscr.addstr('H')
        if hunting
          stdscr.attroff(Ncurses.color_pair(7) | Ncurses::A_BOLD)
        end
        stdscr.attron(Ncurses.color_pair(0))
        edge += 2
        PanelEdges[LMI_Hunt] = edge
        if PandoraUI.runned_via_screen
          stdscr.addstr(' | Ctrl+A,D')
        end
        if refresh
          stdscr.noutrefresh
          Ncurses.doupdate if refresh==2
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
      edge = PanelEdges[LMI_Hunt]
      min_width = edge if edge and (edge>min_width)
      if (min_width < Ncurses.cols) and (win_height>3)
        color = Ncurses.color_pair(self.cur_page+1)
        left_win = create_win(win_height, left_width, 0, 0, CWI_LeftBox, \
          LeftTitles[self.cur_page], color, self.act_panel==0)
        left_win.keypad(true)
        right_win = create_win(win_height, Ncurses.cols - left_width, 0, left_width, \
          CWI_RightBox, nil, color, self.act_panel==1)
        fill_left_win
        fill_right_win

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
        PanelEdges[LMI_Quit] = edge + 5
        #right_win.addstr(PanelEdges.inspect+ "\n")
        stdscr.attron(Ncurses::A_BOLD)
        stdscr.addstr('Q')
        stdscr.attroff(Ncurses::A_BOLD)
        stdscr.addstr('uit | ')
        show_status_bar
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
        comm = self.user_command
        if comm
          self.user_command = nil
          if self.process_command(comm)
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
            stdscr.mvaddstr(Ncurses.lines - 3, 35, '2:'+ch.inspect+'-  ')
            stdscr.refresh
          end
          case ch
            when Ncurses::KEY_RESIZE
              is_resized = true
              break
            when Ncurses::KEY_F1, Ncurses::KEY_F5, 19  #Ctrl+S
              self.cur_page = LMI_Status
              is_resized = true
              break
            when Ncurses::KEY_F2, Ncurses::KEY_F6, 18  #Ctrl+R
              self.cur_page = LMI_Radar
              is_resized = true
              break
            when Ncurses::KEY_F3, Ncurses::KEY_F7, 2  #Ctrl+B
              self.cur_page = LMI_Base
              is_resized = true
              break
            when Ncurses::KEY_F4, Ncurses::KEY_F8, 6  #Ctrl+F
              self.cur_page = LMI_Find
              is_resized = true
              break
            when 67, 554 #Ctrl+Right
              if self.cur_page < LMI_Find
                self.cur_page += 1
              else
                self.cur_page = 0
              end
              is_resized = true
              break
            when 68, 539 #Ctrl+Left
              if self.cur_page > 0
                self.cur_page -= 1
              else
                self.cur_page = LMI_Find
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
                if self.cur_page < LMI_Find
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
                  self.cur_page = LMI_Find
                end
              else
                self.act_panel = 0
              end
              is_resized = true
              break
            when Ncurses::KEY_UP, Ncurses::KEY_DOWN, Ncurses::KEY_NPAGE, \
            Ncurses::KEY_PPAGE
              if self.act_panel==0
                if ch==Ncurses::KEY_DOWN
                  fill_left_win(1, 1)
                elsif ch==Ncurses::KEY_UP
                  fill_left_win(-1, 1)
                elsif ch==Ncurses::KEY_NPAGE
                  fill_left_win(3, 1)
                elsif ch==Ncurses::KEY_PPAGE
                  fill_left_win(-3, 1)
                end
                fill_right_win(1)
                Ncurses.doupdate
              else
                page = self.cur_page
                menu_pos = LeftWinMenuPos[page]
                case page
                  when LMI_Status
                    if (menu_pos == RPI_Log)
                      self.mutex.synchronize do
                        scroll_pos = StatusScrollPos[RPI_Log]
                        asize = LastLogMessages.size
                        if scroll_pos and (asize>1)
                          pos0 = StatusScrollPosPrev[RPI_Log]
                          pos0 ||= 2
                          num = @win_height-5
                          #num = asize if num > asize
                          if ch==Ncurses::KEY_DOWN
                            scroll_pos += 1 if scroll_pos < asize-1
                          elsif ch==Ncurses::KEY_UP
                            scroll_pos -= 1 if scroll_pos>0
                          elsif ch==Ncurses::KEY_NPAGE
                            scroll_pos += 3
                            scroll_pos = asize-1 if scroll_pos >= asize
                          elsif ch==Ncurses::KEY_PPAGE
                            scroll_pos -= 3
                            scroll_pos = 0 if scroll_pos<0
                          end
                          koef = num.fdiv(asize-1)
                          #pos0 = 2+(scroll_pos0 * koef).round
                          pos = 2+(scroll_pos * koef).round
                          if pos0 != pos
                            right_box = self.curse_windows[CWI_RightBox]
                            right_scr_x = Ncurses.cols-@left_width-1
                            right_box.attron(Ncurses::A_ALTCHARSET)
                            right_box.mvaddch(pos0, right_scr_x, ACS_VLINE_ALT)
                            right_box.attron(Ncurses::A_REVERSE)
                            right_box.mvaddch(pos, right_scr_x, ACS_DIAMOND_ALT)
                            right_box.attroff(Ncurses::A_ALTCHARSET | Ncurses::A_REVERSE)
                            #right_box.attroff(Ncurses::A_ALTCHARSET)
                            right_box.noutrefresh
                            StatusScrollPosPrev[RPI_Log] = pos
                          end
                          StatusScrollPos[RPI_Log] = scroll_pos
                          fill_right_win(2)
                        end
                      end
                    end
                end
              end
            when 21  #U
              PandoraUI.do_menu_act('Authorize')
            when 12  #L
              PandoraUI.do_menu_act('Listen')
            when 8   #H
              PandoraUI.do_menu_act('Hunt')
            when Ncurses::KEY_MOUSE
              if mev = Ncurses.getmouse2(mev)
                #Ncurses.ungetmouse(mev)
                bstate = mev.bstate
                if (bstate == Ncurses::BUTTON1_CLICKED)
                  x = mev.x
                  y = mev.y
                  if y < win_height
                    if x < left_width
                      self.act_panel = 0
                      if (x>0) and (x<left_width-1) and (y>0)
                        page = self.cur_page
                        menu_items = MenuItems[page]
                        if menu_items
                          menu_pos = y-1
                          LeftWinMenuPos[page] = menu_pos if menu_pos<menu_items.size
                        end
                      end
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
                      if ind <= LMI_Quit
                        if ind < LMI_Quit
                          self.cur_page = ind
                          is_resized = true
                        end
                        break
                      else
                        case ind
                          when LMI_Auth
                            PandoraUI.do_menu_act('Authorize')
                          when LMI_Listen
                            PandoraUI.do_menu_act('Listen')
                          when LMI_Hunt
                            PandoraUI.do_menu_act('Hunt')
                        end
                      end
                    else
                      stdscr.mvaddstr(Ncurses.lines - 3, 50, p.inspect+'  ')
                      stdscr.refresh
                      sleep 0.5
                    end
                  end
                elsif bstate==524288  #mouse up
                  Ncurses.ungetch(Ncurses::KEY_PPAGE)
                elsif bstate==134217728  #mouse down
                  Ncurses.ungetch(Ncurses::KEY_NPAGE)
                else
                  stdscr.mvaddstr(Ncurses.lines - 3, 50, [bstate, mev.x, mev.y].inspect+'  ')
                  stdscr.refresh
                end
              end
              #fields_form.form_driver(ch)
              #Ncurses.curs_set(1)
            when Ncurses::KEY_F9
              add_mes_to_log_win(('Just a log text '*8)+Ncurses.constants.inspect, 2)
              #right_win.addstr(right_win.methods.inspect+"\n")
              #right_win.noutrefresh
            when Ncurses::KEY_F10, 3, 17, 7000, 7032, 1823111, 1822887
            #Ctrl+C, Ctrl+Q, Alt+X, Alt+x, Alt+Ч, Alt+ч
              PandoraUI.do_menu_act('Quit')
            when 81, 113, 153, 185   #Q, q, Й, й
              if (self.act_panel==0) or (self.cur_page==0)
                PandoraUI.do_menu_act('Quit')
              end
          end
        end
      end
    end
  end

  def self.do_main_loop
    self.cui_inited = false
    self.user_command = nil
    self.cur_page = LMI_Status
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
      #Ncurses.mousemask2(Ncurses::ALL_MOUSE_EVENTS | Ncurses::REPORT_MOUSE_POSITION)

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


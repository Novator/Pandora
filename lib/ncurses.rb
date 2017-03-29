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

  $curse_windows = nil

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

  def self.create_win(height, width, y, x, box_index, title, color, active=true)
    res = Ncurses.newwin(height, width, y, x)
    $curse_windows[box_index] = res
    color = (color | Ncurses::A_BOLD) if active
    res.attron(color)
    res.box(0, 0)
    res.mvaddstr(0, 2, title) if title
    res2 = Ncurses.newwin(height-2, width-2, y+1, x+1)
    $curse_windows[box_index+1] = res2
    res2.bkgd(0)
    res2.scrollok(true)
    res2
  end

  CWI_LeftBox   = 0
  CWI_LeftArea  = 1
  CWI_RightBox  = 2
  CWI_RightArea = 3

  def self.do_windows(doing=:noutrefresh)
    $curse_windows.each do |win|
      case doing
        when :noutrefresh
          win.noutrefresh
        when :del
          Ncurses.delwin(win)
      end
    end
  end

  def self.del_windows
    do_windows(:del)
    $curse_windows.clear
  end

  CPI_Status   = 0
  CPI_Radar    = 1
  CPI_Base     = 2
  CPI_Find     = 3

  LeftTitles = ['Status', 'Radar', 'Base', 'Find']
  RightTitles = ['Log', 'Dialog', 'Record', 'Parameters']
  PanelEdges = []

  def self.recreate_windows(page=nil)
    self.cur_page = page if page
    is_resized = true
    while is_resized
      is_resized = false
      if $curse_windows
        del_windows
        Ncurses.close_screen
        Ncurses.refresh if $curses_is_active
      else
        $curse_windows = []
      end
      stdscr = Ncurses.stdscr

      left_width = 20
      win_height = Ncurses.lines-1

      if (left_width+7 < Ncurses.cols) and (win_height>3)
        color = Ncurses.color_pair(self.cur_page+1)
        left_win = create_win(win_height, left_width, 0, 0, CWI_LeftBox, \
          LeftTitles[self.cur_page], color, self.act_panel==0)
        left_win.keypad(true)

        left_win.mvaddstr(1, 1, 'Auth')
        left_win.mvaddstr(2, 1, 'Listen')
        left_win.mvaddstr(3, 1, 'Hunt')

        right_win = create_win(win_height, Ncurses.cols - left_width, 0, left_width, \
          CWI_RightBox, RightTitles[self.cur_page], color, self.act_panel==1)

        right_win.addstr("Just a log text 1\n")
        right_win.addstr("Это лог текст ёЁ 2\n")

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
        PanelEdges[CPI_Find+1] = edge + 5
        #right_win.addstr(PanelEdges.inspect+ "\n")
        stdscr.attron(Ncurses::A_BOLD)
        stdscr.addstr('Q')
        stdscr.attroff(Ncurses::A_BOLD)
        stdscr.addstr('uit | ')
        stdscr.attron(Ncurses.color_pair(5) | Ncurses::A_BOLD)
        stdscr.addstr('A')
        stdscr.attroff(Ncurses.color_pair(5) | Ncurses::A_BOLD)
        stdscr.attron(Ncurses.color_pair(0))
        stdscr.addstr(' ')
        stdscr.attron(Ncurses.color_pair(6) | Ncurses::A_BOLD)
        stdscr.addstr('L')
        stdscr.attroff(Ncurses.color_pair(6) | Ncurses::A_BOLD)
        stdscr.attron(Ncurses.color_pair(0))
        stdscr.addstr(' ')
        stdscr.attron(Ncurses.color_pair(7) | Ncurses::A_BOLD)
        stdscr.addstr('H')
        stdscr.attroff(Ncurses.color_pair(7) | Ncurses::A_BOLD)
        stdscr.attron(Ncurses.color_pair(0))
      else
        stdscr.addstr('Screen is too small')
      end

      do_windows(:noutrefresh)
      Ncurses.doupdate  # update real screen
      Ncurses.refresh

      mev = nil
      mev = Ncurses::MEVENT.new if Ncurses::MEVENT
      ch = 0
      while ch
        ch = Ncurses.getch
        stdscr.mvaddstr(Ncurses.lines - 3, 28, ch.inspect+'  ')
        stdscr.refresh();
        if (ch==27)
          sleep 0.2
          chg = Ncurses.getch
          ch = (chg ^ (ch << 8))
          if (chg==208) or (chg==209)
            chg = Ncurses.getch
            ch = (chg ^ (ch << 8))
          end
          stdscr.mvaddstr(Ncurses.lines - 3, 28, ch.inspect+'-  ')
          stdscr.refresh();
        end
        case ch
          when Ncurses::KEY_RESIZE
            is_resized = true
            break
          when Ncurses::KEY_F1, 19
            self.cur_page = CPI_Status
            is_resized = true
            break
          when Ncurses::KEY_F2, 18
            self.cur_page = CPI_Radar
            is_resized = true
            break
          when Ncurses::KEY_F3, 2
            self.cur_page = CPI_Base
            is_resized = true
            break
          when Ncurses::KEY_F4, 6
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
          when Ncurses::KEY_LEFT, Ncurses::KEY_RIGHT, 9, 353
            if self.act_panel>0
              self.act_panel = 0
            else
              self.act_panel = 1
            end
            is_resized = true
            break
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
                  quit_edge = PanelEdges[-1]
                  if (x >= quit_edge)
                    p = x - quit_edge
                    if p==2
                      stdscr.mvaddstr(win_height, x, 'A')
                    elsif p==4
                      stdscr.mvaddstr(win_height, x, 'L')
                    elsif p==6
                      stdscr.mvaddstr(win_height, x, 'H')
                    else
                      stdscr.mvaddstr(Ncurses.lines - 3, 50, p.inspect+'  ')
                      stdscr.refresh();
                      sleep 0.5
                    end
                  else
                    (PanelEdges.count-1).times do |i|
                      ed = PanelEdges[i]
                      if x < ed
                        self.cur_page = i
                        is_resized = true
                        break
                      end
                    end
                    break
                  end
                end
              else
                stdscr.mvaddstr(Ncurses.lines - 3, 50, [mev.bstate, mev.x, mev.y].inspect+'  ')
                stdscr.refresh();
              end
            end
            #fields_form.form_driver(ch)
            #Ncurses.curs_set(1)
          when Ncurses::KEY_F8
            right_win.addstr(right_win.methods.inspect+"\n")
            right_win.noutrefresh
          when Ncurses::KEY_F10, 7000, 7032, 1823111, 1822887, 17
            break
          else
            Ncurses.curs_set(1)
          end
      end
      stdscr.bkgd(0)
      Ncurses.clear
      Ncurses.refresh
    end
  end

  def self.init_main_window
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
      recreate_windows
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


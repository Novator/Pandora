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
  $cui_is_active = true
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
      end
      def self.mousemask2(flags)
        mousemask(flags)
      end
      def self.getmouse2(mev)
        res = getmouse
      end
    end
    $cui_is_active = true
  rescue Exception
    Kernel.abort('NCurses and Curses cannot be activated')
  end
end


module PandoraCui

  def self.create_win(height, width, x=0, y=0, title=nil)
    res = Ncurses::Window.new(height, width, x, y)
    res.attron(Ncurses.color_pair(1))
    #res.border(*([0]*8))
    res.box(0, 0)
    res.mvaddstr(0, 2, title) if title
    res.noutrefresh
    res2 = Ncurses::Window.new(height-2, width-2, x+1, y+1)
    res2.bkgd(Ncurses.color_pair(1))
    #res2.attron(Ncurses.color_pair(1) | Ncurses::A_BOLD)
    #res2.clear
    #res2.refresh
    res2.scrollok(true)
    res2.noutrefresh
    res2
  end

  def self.print_in_middle(win, starty, startx, width, str, color)
    win ||= stdscr
    x = Array.new
    y = Array.new
    Ncurses.getyx(win, y, x)
    x[0] = startx if (startx != 0)
    y[0] = starty if (starty != 0)
    width=80 if (width==0)
    length=str.length
    temp = (width - length)/ 2
    x[0] = startx + temp.floor
    win.attron(color)
    win.mvprintw(y[0], x[0], "%s", str)
    win.attroff(color)
    Ncurses.refresh
  end

  def self.show_window
    #Ncurses.slk_init(0);
    #Ncurses.initscr
    Ncurses.init_screen
    begin
      Ncurses.start_color
      #Ncurses.crmode
      Ncurses.cbreak
      Ncurses.noecho
      Ncurses.curs_set(0)
      Ncurses.nonl
      Ncurses.raw

      stdscr = Ncurses.stdscr
      ##stdscr.intrflush(false)
      stdscr.keypad(true)

      #Ncurses.mousemask(Ncurses::BUTTON1_CLICKED, [])
      Ncurses.mousemask2(Ncurses::BUTTON1_CLICKED)
      #Ncurses.mousemask(Ncurses::BUTTON1_CLICKED | Ncurses::BUTTON2_CLICKED | \
      #  Ncurses::BUTTON3_CLICKED| Ncurses::BUTTON4_CLICKED, [])
      #Ncurses.mousemask(Ncurses::ALL_MOUSE_EVENTS | Ncurses::REPORT_MOUSE_POSITION, [])

      Ncurses.init_pair(1, Ncurses::COLOR_WHITE, Ncurses::COLOR_BLUE)
      Ncurses.init_pair(2, Ncurses::COLOR_RED, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(3, Ncurses::COLOR_BLACK, Ncurses::COLOR_WHITE)
      stdscr.bkgd(Ncurses.color_pair(0))
      Ncurses.refresh

      #fields = Array.new
      #(1..4).each do |i|
      #  field = Ncurses::Form::FIELD.new(1, 10, i*2, 1, 0, 0)
      #  fields.push(field)
      #end

      #fields[1].set_field_type(Ncurses::Form::TYPE_ALNUM, 0)
      #fields[2].set_field_type(Ncurses::Form::TYPE_ALPHA, 0)
      #fields[3].set_field_type(Ncurses::Form::TYPE_INTEGER, 0, 0, 1000)

      #fields_form = Ncurses::Form::FORM.new(fields)
      #fields_form.user_object = 'Form ID'

      # Calculate the area required for the form
      #rows = Array.new()
      #cols = Array.new()
      #fields_form.scale_form(rows, cols)

      # Create the window to be associated with the form
      #fld_height = rows[0] + 3
      fld_height = Ncurses.lines-1
      #fld_width = cols[0] + 14
      fld_width = 20

      #fields_win = Ncurses::Window.new(fld_height, fld_width, 0, 0)
      #fields_win.bkgd(Ncurses.color_pair(1))

      fields_win = create_win(fld_height, fld_width, 0, 0, 'Status')
      fields_win.keypad(true)

      # Set main window and sub window
      #fields_form.set_form_win(fields_win)
      #fields_form.set_form_sub(fields_win.derwin(rows[0], cols[0], 2, 12))

      # Print a border around the main window and print a title */
      #fields_win.box(0, 0)
      #print_in_middle(fields_win, 1, 0, 20, 'Pandora', Ncurses.color_pair(1))
      #Ncurses.refresh

      #fields_form.post_form

      # Print field types
      fields_win.mvaddstr(1, 1, 'Auth')
      fields_win.mvaddstr(2, 1, 'Listen')
      fields_win.mvaddstr(3, 1, 'Hunt')

      #fields_win.refresh
      fields_win.noutrefresh

      log_win = create_win(fld_height, Ncurses.cols - fld_width, 0, fld_width, 'Log')
      #log_win.move(5, 3)
      (1..5).each do |i|
        log_win.addstr('Just a log text '*5+i.to_s+"\n")
      end
      log_win.noutrefresh
      Ncurses.doupdate  # update real screen

      stdscr.attron(Ncurses::A_BOLD)
      stdscr.mvaddstr(Ncurses.lines - 1, 0, 'Ctrl: S')
      stdscr.attroff(Ncurses::A_BOLD)
      stdscr.addstr('tatus ')
      stdscr.attron(Ncurses::A_BOLD)
      stdscr.addstr('D')
      stdscr.attroff(Ncurses::A_BOLD)
      stdscr.addstr('ialogs ')
      stdscr.attron(Ncurses::A_BOLD)
      stdscr.addstr('B')
      stdscr.attroff(Ncurses::A_BOLD)
      stdscr.addstr('ases ')
      stdscr.attron(Ncurses::A_BOLD)
      stdscr.addstr('F')
      stdscr.attroff(Ncurses::A_BOLD)
      stdscr.addstr('ind ')
      stdscr.attron(Ncurses::A_BOLD)
      stdscr.addstr('Q')
      stdscr.attroff(Ncurses::A_BOLD)
      stdscr.addstr('uit')
      stdscr.refresh

      # Loop through to get user requests
      mev = nil
      mev = Ncurses::MEVENT.new if Ncurses::MEVENT
      ch = 0
      while ch
        ch = fields_win.getch
        stdscr.mvaddstr(Ncurses.lines - 3, 28, ch.inspect+'  ')
        stdscr.refresh();
        if (ch==27)
          sleep 0.2
          chg = fields_win.getch
          #stdscr.mvprintw(Ncurses.lines - 3, 28, chg.inspect+'  ')
          #stdscr.refresh();
          #sleep 0.3
          ch = (chg ^ (ch << 8))
          if (chg==208) or (chg==209)
            chg = fields_win.getch
            ch = (chg ^ (ch << 8))
            #stdscr.mvprintw(Ncurses.lines - 3, 28, chg.inspect+'  ')
            #stdscr.refresh();
            #sleep 0.3
          end
          stdscr.mvprintw(Ncurses.lines - 3, 28, ch.inspect+'-  ')
          stdscr.refresh();
        end
        case ch
          when Ncurses::KEY_DOWN
            #fields_form.form_driver(Ncurses::Form::REQ_VALIDATION)
            #fields_form.form_driver(Ncurses::Form::REQ_NEXT_FIELD)
            #fields_form.form_driver(Ncurses::Form::REQ_END_LINE)
            Ncurses.curs_set(1)
          when Ncurses::KEY_UP
            #fields_form.form_driver(Ncurses::Form::REQ_VALIDATION)
            #fields_form.form_driver(Ncurses::Form::REQ_PREV_FIELD)
            #fields_form.form_driver(Ncurses::Form::REQ_END_LINE)
            Ncurses.curs_set(1)
          when Ncurses::KEY_LEFT
            #fields_form.form_driver(Ncurses::Form::REQ_PREV_CHAR)
            Ncurses.curs_set(1)
          when Ncurses::KEY_RIGHT
            #fields_form.form_driver(Ncurses::Form::REQ_NEXT_CHAR)
            Ncurses.curs_set(1)
          when Ncurses::KEY_BACKSPACE
            #fields_form.form_driver(Ncurses::Form::REQ_DEL_PREV)
            Ncurses.curs_set(1)
          when Ncurses::KEY_RESIZE
            #Ncurses.clear
            #Ncurses.erase
            #Ncurses.endwin
            #Ncurses.touchwin(stdscr)
            #log_win.resize(Ncurses.lines - 1, Ncurses.cols - fld_width)
            #fields_win.resize(fld_height, fld_width)
            #Ncurses.resizeterm(Ncurses.lines, Ncurses.cols)
            #Ncurses.curscr.refresh
            #fields_win.noutrefresh
            #log_win.noutrefresh
            #Ncurses.doupdate
            #Ncurses.refresh
          when Ncurses::KEY_MOUSE
            if mev = Ncurses.getmouse2(mev)
              #Ncurses.ungetmouse(mev)
              if (mev.bstate == 4) and (mev.y==Ncurses.lines-1) and (mev.x >= 32)
                break
              else
                stdscr.mvaddstr(Ncurses.lines - 3, 50, [mev.bstate, mev.x, mev.y].inspect+'  ')
                stdscr.refresh();
              end
            end
            #fields_form.form_driver(ch)
            Ncurses.curs_set(1)
          when Ncurses::KEY_F8
            log_win.addstr('Here a log text '*5+"\n")
            log_win.noutrefresh
            #Ncurses.doupdate
            #stdscr.refresh
          when Ncurses::KEY_F9
            fields_win.refresh
            log_win.noutrefresh
            stdscr.refresh
            Ncurses.doupdate
          when Ncurses::KEY_F10, 7000, 7032, 1823111, 1822887, 17
          #(ch != 113) and (ch != 81) and (ch != 185) and (ch != 153)
            break
          else
            #fields_form.form_driver(ch)
            Ncurses.curs_set(1)
          end
      end
      # Un post form and free the memory
      #fields_form.unpost_form
      #fields_form.free_form
      #fields.each { |f| f.free_field }

      stdscr.bkgd(0)
      Ncurses.clear
      #stdscr.move(Ncurses.lines()-1, 0)
      #stdscr.addstr('[Ctrl] [R]adar [L]og [Q]uit')
      Ncurses.refresh

      #radar_win = create_win(Ncurses.lines()-1, Ncurses.cols() / 3, 0, 0, 'Radar')

      #log_win = create_win(Ncurses.lines()-1, Ncurses.cols() - (Ncurses.cols() / 3), \
      #  0, Ncurses.cols() / 3, 'Log')

      #log_win.move(5,3)
      #log_win.addstr('Press any key to exit')

      #radar_win.noutrefresh   # copy window to virtual screen, don't update real screen
      #log_win.noutrefresh
      #Ncurses.doupdate  # update real screen

      #quit_keys = [113, 81, 53433, 53401]
      #char = 0
      #while not (quit_keys.include?(char))
      #  char = log_win.getch
      #  if (char==208) or (char==27)
      #    char0 = char
      #    char1 = log_win.getch
      #    char = char1 ^ (char0 << 8))
      #    if (char==91)
      #    end
      #  end
      #  log_win.move(7,3)
      #  log_win.addstr(char.inspect)
      #  log_win.noutrefresh
      #  Ncurses.doupdate  # update real screen
      #  sleep 1
      #end
    ensure
      Ncurses.curs_set(1)
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      #Ncurses.endwin
      Ncurses.close_screen
    end
    puts('Pandora finished. '+[fld_height, fld_width].inspect)
  end

end


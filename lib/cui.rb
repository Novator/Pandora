#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Console user interface (CUI) of Pandora
# RU: Консольный интерфейс Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2017 (c) Michael Galyuk
# RU: 2017 (c) Михаил Галюк


# Init NCurses
# RU: Инициализировать NCurses
begin
  require 'ncurses'
  $cui_is_active = true
rescue Exception
  Kernel.abort('NCurses cannot be activated')
end


module PandoraCui

  def self.create_win(height, width, x=0, y=0, title=nil)
    res = Ncurses::WINDOW.new(height, width, x, y)
    #res.border(*([0]*8))
    res.box(0, 0)
    if title
      res.move(0, 2)
      res.addstr(title)
    end
    res.noutrefresh
    res = Ncurses::WINDOW.new(height-2, width-2, x+1, y+1)
    res.scrollok(true)
    res.noutrefresh
    res
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
    Ncurses.initscr
    begin
      Ncurses.start_color
      Ncurses.cbreak
      Ncurses.noecho
      Ncurses.nonl

      stdscr = Ncurses.stdscr
      stdscr.intrflush(false)
      stdscr.keypad(true)

      Ncurses.init_pair(1, Ncurses::COLOR_RED, Ncurses::COLOR_BLACK)
      Ncurses.init_pair(2, Ncurses::COLOR_BLACK, Ncurses::COLOR_WHITE)
      Ncurses.init_pair(3, Ncurses::COLOR_BLACK, Ncurses::COLOR_BLUE)
      stdscr.bkgd(Ncurses.COLOR_PAIR(2))

      fields = Array.new
      (1..4).each do |i|
        field = Ncurses::Form::FIELD.new(1, 10, i*2, 1, 0, 0)
        fields.push(field)
      end

      fields[1].set_field_type(Ncurses::Form::TYPE_ALNUM, 0)
      fields[2].set_field_type(Ncurses::Form::TYPE_ALPHA, 0)
      fields[3].set_field_type(Ncurses::Form::TYPE_INTEGER, 0, 0, 1000)

      fields_form = Ncurses::Form::FORM.new(fields)
      fields_form.user_object = 'Form ID'

      # Calculate the area required for the form
      rows = Array.new()
      cols = Array.new()
      fields_form.scale_form(rows, cols)

      # Create the window to be associated with the form
      #fld_height = rows[0] + 3
      fld_height = Ncurses.LINES()-1
      fld_width = cols[0] + 14
      fields_win = Ncurses::WINDOW.new(fld_height, fld_width, 0, 0)
      fields_win.bkgd(Ncurses.COLOR_PAIR(3))
      fields_win.keypad(true)

      # Set main window and sub window
      fields_form.set_form_win(fields_win)
      fields_form.set_form_sub(fields_win.derwin(rows[0], cols[0], 2, 12))

      # Print a border around the main window and print a title */
      fields_win.box(0, 0)
      print_in_middle(fields_win, 1, 0, cols[0] + 14, 'Pandora', Ncurses.COLOR_PAIR(1))

      fields_form.post_form

      # Print field types
      fields_win.mvaddstr(4, 2, "No Type")
      fields_win.mvaddstr(6, 2, "Alphanum")
      fields_win.mvaddstr(8, 2, "Alpha")
      fields_win.mvaddstr(10, 2, "Integer")

      fields_win.wrefresh

      log_win = create_win(Ncurses.LINES()-1, Ncurses.COLS() - fld_width, 0, fld_width, 'Log')
      #log_win.move(5, 3)
      (1..5).each do |i|
        log_win.addstr('Just a log text '*5+i.to_s+"\n")
      end
      log_win.noutrefresh
      Ncurses.doupdate  # update real screen

      stdscr.mvprintw(Ncurses.LINES - 1, 28, '[Ctrl] [R]adar [L]og [F10]Quit')
      stdscr.refresh

      # Loop through to get user requests
      while (ch = fields_win.getch)
        stdscr.mvprintw(Ncurses.LINES - 3, 28, ch.inspect)
        stdscr.refresh();
        case ch
          when Ncurses::KEY_DOWN
            fields_form.form_driver(Ncurses::Form::REQ_VALIDATION)
            fields_form.form_driver(Ncurses::Form::REQ_NEXT_FIELD)
            fields_form.form_driver(Ncurses::Form::REQ_END_LINE)
          when Ncurses::KEY_UP
            fields_form.form_driver(Ncurses::Form::REQ_VALIDATION)
            fields_form.form_driver(Ncurses::Form::REQ_PREV_FIELD)
            fields_form.form_driver(Ncurses::Form::REQ_END_LINE)
          when Ncurses::KEY_LEFT
            fields_form.form_driver(Ncurses::Form::REQ_PREV_CHAR)
          when Ncurses::KEY_RIGHT
            fields_form.form_driver(Ncurses::Form::REQ_NEXT_CHAR)
          when Ncurses::KEY_BACKSPACE
            fields_form.form_driver(Ncurses::Form::REQ_DEL_PREV)
          when Ncurses::KEY_RESIZE
            Ncurses.refresh
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
          when Ncurses::KEY_F10
          #(ch != 113) and (ch != 81) and (ch != 185) and (ch != 153)
            break
          else
            fields_form.form_driver(ch)
          end
      end
      # Un post form and free the memory
      fields_form.unpost_form
      fields_form.free_form
      fields.each { |f| f.free_field }


      #stdscr.clear
      #stdscr.move(Ncurses.LINES()-1, 0)
      #stdscr.addstr('[Ctrl] [R]adar [L]og [Q]uit')
      #stdscr.refresh

      #radar_win = create_win(Ncurses.LINES()-1, Ncurses.COLS() / 3, 0, 0, 'Radar')

      #log_win = create_win(Ncurses.LINES()-1, Ncurses.COLS() - (Ncurses.COLS() / 3), \
      #  0, Ncurses.COLS() / 3, 'Log')

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
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      Ncurses.endwin
    end
  end

end


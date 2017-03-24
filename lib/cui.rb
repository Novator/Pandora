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

  def self.show_message(message)
    width = message.length + 6
    win = Curses::Window.new(5, width, \
      (Curses.lines - 5) / 2, (Curses.cols - width) / 2)
    win.keypad = true
    win.attron(Curses.color_pair(Curses::COLOR_RED)) do
      win.box(?|, ?-, ?+)
    end
    win.setpos(2, 3)
    win.addstr(message)
    win.refresh
    win
  end

  def self.show_window
    Ncurses.initscr
    begin
      Ncurses.cbreak                     # provide unbuffered input
      Ncurses.noecho                     # turn off input echoing
      Ncurses.nonl                       # turn off newline translation
      Ncurses.stdscr.intrflush(false)   # turn off flush-on-interrupt
      Ncurses.stdscr.keypad(true)       # turn on keypad mode
      while true
        scr = Ncurses.stdscr
        scr.clear()
        scr.move(Ncurses.LINES()-1, 0)
        scr.addstr('Ctrl[Radar]R [Log]L')
        scr.refresh() # update screen

        one = Ncurses::WINDOW.new(Ncurses.LINES()-1, Ncurses.COLS() / 3, 0, 0)
        two = Ncurses::WINDOW.new(Ncurses.LINES()-1, Ncurses.COLS() - (Ncurses.COLS() / 3), \
          0, Ncurses.COLS() / 3)
        one.border(*([0]*8))
        two.border(*([0]*8))

        one.move(0, 2)
        one.addstr('Radar')
        two.move(0, 2)
        two.addstr('Log')

        two.move(5,3)
        two.addstr("Press a key to continue")
        one.noutrefresh()   # copy window to virtual screen, don't update real screen
        two.noutrefresh()
        Ncurses.doupdate()  # update real screen
        two.getch()
        break
      end
    ensure
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      Ncurses.endwin
    end
  end

end


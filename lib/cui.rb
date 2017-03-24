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


# Init Curses
# RU: Инициализировать Curses
begin
  require 'curses'
  include Curses
rescue Exception
  Kernel.abort('Curses cannot be activated')
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
    Curses.init_screen
    begin
      Curses.nonl
      Curses.cbreak
      Curses.noecho
      Curses.stdscr.scrollok(true)
      Curses.start_color
      Curses.init_pair(Curses::COLOR_BLUE, Curses::COLOR_BLUE, Curses::COLOR_WHITE)
      Curses.init_pair(Curses::COLOR_RED, Curses::COLOR_RED, Curses::COLOR_WHITE)
      #Curses.crmode
      Curses.stdscr.keypad(true)
      Curses.mousemask((Curses::BUTTON1_CLICKED | Curses::BUTTON2_CLICKED | \
        Curses::BUTTON3_CLICKED | Curses::BUTTON4_CLICKED))
      mes = "The CUI is under construstion. The CUI is under construstion.\n"
      setpos((Curses.lines - 1) / 2, (Curses.cols - mes.size) / 2)
      attron((Curses.color_pair(Curses::COLOR_BLUE) | Curses::A_BOLD)) do
        addstr(mes)
        addstr(mes)
        addstr(mes)
      end
      Curses.refresh
      char = nil
      while true
        win = show_message('Press Q or click mouse')
        if win
          char = win.getch
          win.close
          win = nil
        else
          char = getch
        end
        case char
          when Curses::KEY_MOUSE
            m = Curses.getmouse
            if m
              win = show_message('getch='+char.inspect + ' mouse event='+\
                m.bstate.inspect+' axis='+[m.x, m.y, m.z].inspect)
              win.getch
              win.close
            end
            break
          when 'q'
            break
          else
            setpos(0, 0)
            addstr('pressed key '+Curses.keyname(char)+' char='+char.inspect)
            refresh
        end
      end
      Curses.refresh
    ensure
      Curses.close_screen
    end
  end

end


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
# 2014 (c) Vladimir Bulanov
# RU: 2014 (c) Владимир Буланов


# ====================================================================
# Pandora localization
# RU: Локализация Пандоры

# Array of localization phrases
# RU: Вектор переведеных фраз
$lang_trans = {}

# Translation of the phrase
# RU: Перевод фразы
def _(frase)
  trans = $lang_trans[frase]
  if not trans or (trans.size==0) and frase and (frase.size>0)
    trans = frase
  end
  trans
end


#=begin
require 'gtksourceview3'
	
	w = Gtk::Window.new
	w.signal_connect("delete-event"){Gtk::main_quit}
	
	view = Gtk::SourceView.new
	w.add(Gtk::ScrolledWindow.new.add(view))
	view.show_line_numbers = true
	view.insert_spaces_instead_of_tabs = true
	view.indent_width = 4
	view.show_right_margin = true
	view.right_margin_position = 80
	
	lang = Gtk::SourceLanguageManager.new.get_language('ruby')
	view.buffer.language = lang
	view.buffer.highlight_syntax = true
	view.buffer.highlight_matching_brackets = true
	
	w.set_default_size(450,300)
	w.show_all
	
	Gtk.main
#=end

# ====================================================================
require "#{File.dirname(__FILE__)}/p_utils"
require "#{File.dirname(__FILE__)}/p_logic"
require "#{File.dirname(__FILE__)}/p_crypt"
require "#{File.dirname(__FILE__)}/p_proto"
require "#{File.dirname(__FILE__)}/p_gmain"

#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

require 'fileutils'
require_relative 'crypto.rb'
require_relative 'net.rb'

# GTK is cross platform graphical user interface
# RU: Кроссплатформенный оконный интерфейс
begin
  require 'gtk2'
  Gtk.init
  $gtk_is_active = true
rescue Exception
  puts("Gtk cannot be activated.\nInstall packet 'ruby-gtk'")
end


module PandoraGtk

  include PandoraUtils
  include PandoraModel

  # Middle width of num char in pixels
  # RU: Средняя ширина цифрового символа в пикселах
  def self.num_char_width
    @@num_char_width ||= nil
    if not @@num_char_width
      lab = Gtk::Label.new('0')
      lw,lh = lab.size_request
      @@num_char_width = lw
      @@num_char_width ||= 5
    end
    @@num_char_width
  end

  # Force set text of any Button (with stock)
  # RU: Силовая смена текста любой кнопки (со stock)
  def self.set_button_text(btn, text=nil)
    alig = btn.children[0]
    if alig.is_a? Gtk::Bin
      hbox = alig.child
      if (hbox.is_a? Gtk::Box) and (hbox.children.size>1)
        lab = hbox.children[1]
        if lab.is_a? Gtk::Label
          if text.nil?
            lab.destroy
          else
            lab.text = text
          end
        end
      end
    end
  end

  # Ctrl, Shift, Alt are pressed? (Array or Yes/No)
  # RU: Кнопки Ctrl, Shift, Alt нажаты? (Массив или Да/Нет)
  def self.is_ctrl_shift_alt?(ctrl=nil, shift=nil, alt=nil)
    screen, x, y, mask = Gdk::Display.default.pointer
    res = nil
    ctrl_prsd = ((mask & Gdk::Window::CONTROL_MASK.to_i) != 0)
    shift_prsd = ((mask & Gdk::Window::SHIFT_MASK.to_i) != 0)
    alt_prsd = ((mask & Gdk::Window::MOD1_MASK.to_i) != 0)
    if ctrl.nil? and shift.nil? and alt.nil?
      res = [ctrl_prsd, shift_prsd, alt_prsd]
    else
      res = ((ctrl and ctrl_prsd) or (shift and shift_prsd) or (alt and alt_prsd))
    end
    res
  end

  # Good and simle MessageDialog
  # RU: Хороший и простой MessageDialog
  class GoodMessageDialog < Gtk::MessageDialog

    def initialize(a_mes, a_title=nil, a_stock=nil, an_icon=nil)
      a_stock = Gtk::MessageDialog::WARNING if a_stock==:warning
      a_stock = Gtk::MessageDialog::QUESTION if a_stock==:question
      a_stock = Gtk::MessageDialog::ERROR if a_stock==:error
      a_stock ||= Gtk::MessageDialog::INFO
      super($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
        a_stock, Gtk::MessageDialog::BUTTONS_OK_CANCEL, a_mes)
      a_title ||= 'Note'
      self.title = _(a_title)
      self.default_response = Gtk::Dialog::RESPONSE_OK
      an_icon ||= $window.icon if $window
      an_icon ||= main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      self.icon = an_icon
      self.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask? #w, W, ц, Ц
        then
          widget.response(Gtk::Dialog::RESPONSE_CANCEL)
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й, x, X, ч, Ч
        then
          PandoraUI.do_menu_act('Quit')
          false
        else
          false
        end
      end
    end

    def run_and_do(do_if_ok=true)
      res = nil
      res = (self.run == Gtk::Dialog::RESPONSE_OK)
      if (res and do_if_ok) or ((not res) and (not do_if_ok))
        res = true
        yield(res) if block_given?
      end
      self.destroy if not self.destroyed?
      res
    end

  end

  def self.show_dialog(mes, do_if_ok=true, a_title=nil, a_stock=nil)
    res = PandoraGtk::GoodMessageDialog.new(mes, a_title, \
    a_stock).run_and_do(do_if_ok) do |*args|
      yield(*args) if block_given?
    end
    res
  end

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window #Gtk::Dialog
    attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, \
      :enter_like_tab, :enter_like_ok, :panelbox, :okbutton, :cancelbutton, \
      :def_widget, :main_sw

    # Create method
    # RU: Метод создания
    def initialize(*args)
      super(*args)
      @response = 0
      @window = self
      @enter_like_tab = false
      @enter_like_ok = true
      set_default_size(300, -1)

      window.transient_for = $window
      window.modal = true
      #window.skip_taskbar_hint = true
      window.window_position = Gtk::Window::POS_CENTER
      #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG
      window.destroy_with_parent = true

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2

      window.add(vpaned)
      #window.vbox.add(vpaned)

      @main_sw = Gtk::ScrolledWindow.new(nil, nil)
      sw = main_sw
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      @viewport = Gtk::Viewport.new(nil, nil)
      sw.add(viewport)

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      label_box1 = TabLabelBox.new(Gtk::Stock::PROPERTIES, _('Basic'))
      page = notebook.append_page(sw, label_box1)
      vpaned.pack1(notebook, true, true)

      @panelbox = Gtk::VBox.new
      @hbox = Gtk::HBox.new
      panelbox.pack_start(hbox, false, false, 0)

      vpaned.pack2(panelbox, false, true)

      bbox = Gtk::HBox.new
      bbox.border_width = 2
      bbox.spacing = 4

      @okbutton = Gtk::Button.new(Gtk::Stock::OK)
      okbutton.width_request = 110
      okbutton.signal_connect('clicked') do |*args|
        @response=2
      end
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') do |*args|
        @response=1
      end
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

      #self.signal_connect('response') do |widget, response|
      #  case response
      #    when Gtk::Dialog::RESPONSE_OK
      #      p "OK"
      #    when Gtk::Dialog::RESPONSE_CANCEL
      #      p "Cancel"
      #    when Gtk::Dialog::RESPONSE_CLOSE
      #      p "Close"
      #      dialog.destroy
      #  end
      #end

      window.signal_connect('delete-event') { |*args|
        @response=1
        false
      }
      window.signal_connect('destroy') { |*args| @response=1 }

      window.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Tab) and enter_like_tab  # Enter works like Tab
          event.hardware_keycode=23
          event.keyval=Gdk::Keyval::GDK_Tab
          window.signal_emit('key-press-event', event)
          true
        elsif
          [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
          and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? Gtk::TextView))))
        then
          okbutton.activate if okbutton.sensitive?
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          cancelbutton.activate
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
          ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
        then
          PandoraUI.do_menu_act('Quit')
          @response=1
          false
        else
          false
        end
      end

    end

    # Show dialog in modal mode
    # RU: Показать диалог в модальном режиме
    def run2(in_thread=false)
      res = nil
      show_all
      if @def_widget
        #focus = @def_widget
        @def_widget.grab_focus
        self.present
        GLib::Timeout.add(200) do
          @def_widget.grab_focus if @def_widget and (not @def_widget.destroyed?)
          false
        end
      end

      while (not destroyed?) and (@response == 0) do
        if in_thread
          Thread.pass
        else
          Gtk.main_iteration
        end
        #sleep(0.001)
      end

      if not destroyed?
        if (@response > 1)
          yield(@response) if block_given?
          res = true
        end
        self.destroy if (not self.destroyed?)
      end

      res
    end
  end

  # ToggleButton with safety "active" switching
  # RU: ToggleButton с безопасным переключением "active"
  class SafeToggleButton < Gtk::ToggleButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      else
        self.active = an_active
      end
    end

  end

  # ToggleToolButton with safety "active" switching
  # RU: ToggleToolButton с безопасным переключением "active"
  class SafeToggleToolButton < Gtk::ToggleToolButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      else
        self.active = an_active
      end
    end

  end

  # CheckButton with safety "active" switching
  # RU: CheckButton с безопасным переключением "active"
  class SafeCheckButton < Gtk::CheckButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # Entry with allowed symbols of mask
  # RU: Поле ввода с допустимыми символами в маске
  class MaskEntry < Gtk::Entry
    attr_accessor :mask

    def initialize
      super
      signal_connect('key-press-event') do |widget, event|
        res = false
        if not key_event(widget, event)
          if (not event.state.control_mask?) and (event.keyval<60000) \
          and (mask.is_a? String) and (mask.size>0)
            res = (not mask.include?(event.keyval.chr))
          end
        end
        res
      end
      @mask = nil
      init_mask
      if mask and (mask.size>0)
        prefix = self.tooltip_text
        if prefix and (prefix != '')
          prefix << "\n"
        end
        prefix ||= ''
        self.tooltip_text = prefix+'['+mask+']'
      end
    end

    def init_mask
      #will reinit in child
    end

    def key_event(widget, event)
      false
    end
  end

  # Entry for integer
  # RU: Поле ввода целых чисел
  class IntegerEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789-'
      self.max_length = 20
      self.width_request = PandoraGtk.num_char_width*8+8
    end
  end

  # Entry for float
  # RU: Поле ввода дробных чисел
  class FloatEntry < IntegerEntry
    def init_mask
      super
      @mask += '.e'
      self.max_length = 35
      self.width_request = PandoraGtk.num_char_width*11+8
    end
  end

  # Entry for HEX
  # RU: Поле ввода шестнадцатеричных чисел
  class HexEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789abcdefABCDEF'
      self.width_request = PandoraGtk.num_char_width*45+8
    end
  end

  Base64chars = [('0'..'9').to_a, ('a'..'z').to_a, ('A'..'Z').to_a, '+/=-_*[]'].join

  # Entry for Base64
  # RU: Поле ввода Base64
  class Base64Entry < MaskEntry
    def init_mask
      super
      @mask = Base64chars
      self.width_request = PandoraGtk.num_char_width*64+8
    end
  end

  # Simple entry for date
  # RU: Простое поле ввода даты
  class DateEntrySimple < MaskEntry
    def init_mask
      super
      @mask = '0123456789.'
      self.max_length = 10
      self.tooltip_text = 'DD.MM.YYYY'
      self.width_request = PandoraGtk.num_char_width*self.max_length+8
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class TimeEntrySimple < DateEntrySimple
    def init_mask
      super
      @mask = '0123456789:'
      self.max_length = 8
      self.tooltip_text = 'hh:mm:ss'
      self.width_request = PandoraGtk.num_char_width*self.max_length+8
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class DateTimeEntry < DateEntrySimple
    def init_mask
      super
      @mask += ': '
      self.max_length = 19
      self.tooltip_text = 'DD.MM.YYYY hh:mm:ss'
      self.width_request = PandoraGtk.num_char_width*(self.max_length+1)+8
    end
  end

  # Entry with popup widget
  # RU: Поле с всплывающим виджетом
  class BtnEntry < Gtk::HBox
    attr_accessor :entry, :button, :close_on_enter, :modal

    def initialize(entry_class, stock=nil, tooltip=nil, amodal=nil, *args)
      amodal = false if amodal.nil?
      @modal = amodal
      super(*args)
      @close_on_enter = true
      @entry = entry_class.new
      stock ||= :list

      @init_yield_block = nil
      if block_given?
        @init_yield_block = Proc.new do |*args|
          yield(*args)
        end
      end

      self.pack_start(entry, true, true, 0)

      @button = self.add_button(stock, tooltip) do
        do_on_click
      end
      @entry.instance_variable_set('@button', @button)

      #def @entry.key_event(widget, event)
      @entry.define_singleton_method('key_event') do |widget, event|
        res = ((event.keyval==32) or ((event.state.shift_mask? \
          or event.state.mod1_mask?) \
          and (event.keyval==65364)))  # Space, Shift+Down or Alt+Down
        if res
          if @button.is_a?(PandoraGtk::GoodButton)
            @button.do_on_click
          elsif not @button.nil?
            @button.activate
          end
        end
        false
      end
    end

    def add_button(stock, tooltip=nil)
      btn = nil
      if PandoraUtils.os_family=='windows'
        btn = GoodButton.new(stock, nil, nil) do |*args|
          yield(*args)
        end
      else
        $window.register_stock(stock)
        btn = Gtk::Button.new(stock)
        PandoraGtk.set_button_text(btn)

        tooltip ||= stock.to_s.capitalize
        btn.tooltip_text = _(tooltip)
        btn.signal_connect('clicked') do |*args|
          yield(*args)
        end
      end
      btn.can_focus = false
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
      align.add(btn)
      self.pack_start(align, false, false, 1)
      esize = @entry.size_request
      h = esize[1]-2
      btn.set_size_request(h, h)
      btn
    end

    def do_on_click
      res = false
      @entry.grab_focus
      if @popwin and (not @popwin.destroyed?)
        @popwin.destroy
        @popwin = nil
      else
        @popwin = Gtk::Window.new #(Gtk::Window::POPUP)
        popwin = @popwin
        popwin.transient_for = $window if PandoraUtils.os_family == 'windows'
        popwin.modal = @modal
        popwin.decorated = false
        popwin.skip_taskbar_hint = true
        popwin.destroy_with_parent = true

        popwidget = get_popwidget
        popwin.add(popwidget)
        popwin.signal_connect('delete_event') { @popwin.destroy; @popwin=nil }

        popwin.signal_connect('focus-out-event') do |win, event|
          GLib::Timeout.add(100) do
            if not win.destroyed?
              @popwin.destroy
              @popwin = nil
            end
            false
          end
          false
        end

        popwin.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            if @close_on_enter
              @popwin.destroy
              @popwin = nil
            end
            false
          elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
            ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
            event.keyval) and event.state.control_mask?) #w, W, ц, Ц
          then
            @popwin.destroy
            @popwin = nil
            false
          elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
            event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
            Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
            and event.state.control_mask?) #q, Q, й, Й
          then
            @popwin.destroy
            @popwin = nil
            PandoraUI.do_menu_act('Quit')
            false
          else
            false
          end
        end

        pos = @entry.window.origin
        all = @entry.allocation.to_a
        popwin.move(pos[0], pos[1]+all[3]+1)

        popwin.show_all
      end
      res
    end

    def get_popwidget   # Example widget
      wid = Gtk::Button.new('Here must be a popup widget')
      wid.signal_connect('clicked') do |*args|
        @entry.text = 'AValue'
        @popwin.destroy
        @popwin = nil
      end
      wid
    end

    def max_length=(maxlen)
      maxlen = 512 if maxlen<512
      entry.max_length = maxlen
    end

    def text=(text)
      entry.text = text
    end

    def text
      entry.text
    end

    def width_request=(wr)
      entry.set_width_request(wr)
    end

    def modify_text(*args)
      entry.modify_text(*args)
    end

    def size_request
      esize = entry.size_request
      res = button.size_request
      res[0] = esize[0]+1+res[0]
      res
    end
  end

  # Popup choose window
  # RU: Всплывающее окно выбора
  class PopWindow < Gtk::Window
    attr_accessor :root_vbox, :just_leaved, :on_click_btn

    def get_popwidget
      nil
    end

    def initialize(amodal=nil)
      super()

      @just_leaved = false

      self.transient_for = $window if PandoraUtils.os_family == 'windows'
      amodal = false if amodal.nil?
      self.modal = amodal
      self.decorated = false
      self.skip_taskbar_hint = true

      popwidget = get_popwidget
      self.add(popwidget) if popwidget
      self.signal_connect('delete_event') do
        destroy
      end

      self.signal_connect('focus-out-event') do |win, event|
        if not @just_leaved.nil?
          @just_leaved = true
          if not destroyed?
            hide
          end
          GLib::Timeout.add(500) do
            @just_leaved = false if not destroyed?
            false
          end
        end
        false
      end

      self.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          @just_leaved = nil
          hide
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          destroy
          PandoraUI.do_menu_act('Quit')
          false
        else
          false
        end
      end
    end

    def hide_popwin
      @just_leaved = nil
      self.hide
    end

  end

  # Smile choose window
  # RU: Окно выбора смайла
  class SmilePopWindow < PopWindow
    attr_accessor :preset, :poly_btn, :preset

    def initialize(apreset=nil, amodal=nil)
      apreset ||= 'vk'
      @preset = apreset
      super(amodal)
      self.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Tab)
          if preset=='qip'
            @vk_btn.do_on_click
          else
            @qip_btn.do_on_click
          end
          true
        elsif [Gdk::Keyval::GDK_b, Gdk::Keyval::GDK_B, 1737, 1769].include?(event.keyval)
          @poly_btn.set_active((not @poly_btn.active?))
          false
        else
          false
        end
      end
    end

    def get_popwidget
      if @root_vbox.nil? or @root_vbox.destroyed?
        @root_vbox = Gtk::VBox.new
        @smile_box = Gtk::Frame.new
        #@smile_box.shadow_type = Gtk::SHADOW_NONE
        hbox = Gtk::HBox.new
        $window.register_stock(:music, 'qip')
        @qip_btn = GoodButton.new(:music_qip, 'qip', -1) do |*args|
          if not @qip_btn.active?
            @qip_btn.set_active(true)
            @vk_btn.set_active(false)
            move_and_show('qip')
          end
        end
        hbox.pack_start(@qip_btn, true, true, 0)
        $window.register_stock(:ufo, 'vk')
        @vk_btn = GoodButton.new(:ufo_vk, 'vk', -1) do |*args|
          if not @vk_btn.active?
            @vk_btn.set_active(true)
            @qip_btn.set_active(false)
            move_and_show('vk')
          end
        end
        hbox.pack_start(@vk_btn, true, true, 0)
        $window.register_stock(:bomb, 'qip')
        @poly_btn = GoodButton.new(:bomb_qip, nil, false)
        @poly_btn.tooltip_text = _('Many smiles')
        hbox.pack_start(@poly_btn, false, false, 0)
        root_vbox.pack_start(hbox, false, true, 0)
        if preset=='vk'
          @vk_btn.set_active(true)
        else
          @qip_btn.set_active(true)
        end
        root_vbox.pack_start(@smile_box, true, true, 0)
      end
      root_vbox
    end

    def init_smiles_box(preset, smiles_parent, smile_btn)
      @@smile_btn = smile_btn if smile_btn
      @@smile_boxes ||= {}
      vbox = nil
      res = @@smile_boxes[preset]
      if res
        vbox = res[0]
        vbox = nil if vbox.destroyed?
      end
      if vbox
        resize(100, 100)
        #p '  vbox.parent='+vbox.parent.inspect
        if vbox.parent and (not vbox.parent.destroyed?)
          if (vbox.parent != smiles_parent)
            #p '  reparent'
            smiles_parent.remove(smiles_parent.child) if smiles_parent.child
            vbox.parent.remove(vbox)
            smiles_parent.add(vbox)
            vbox.reparent(smiles_parent)
          end
        else
          #p '  set_parent'
          smiles_parent.remove(smiles_parent.child) if smiles_parent.child
          vbox.parent = smiles_parent
        end
      else
        smiles_parent.remove(smiles_parent.child) if smiles_parent.child
        vbox = Gtk::VBox.new
        icon_params, icon_file_desc = $window.get_icon_file_params(preset)
        focus_btn = nil
        if icon_params and (icon_params.size>0)
          row = 0
          col = 0
          max_col = Math.sqrt(icon_params.size).round
          hbox = Gtk::HBox.new
          icon_params.each_with_index do |smile, i|
            if col>max_col
              vbox.pack_start(hbox, false, false, 0)
              hbox = Gtk::HBox.new
              col = 0
              row += 1
            end
            col += 1
            buf = $window.get_icon_buf(smile, preset)
            aimage = Gtk::Image.new(buf)
            btn = Gtk::ToolButton.new(aimage, smile)
            btn.set_can_focus(true)
            btn.tooltip_text = smile
            #btn.events = Gdk::Event::ALL_EVENTS_MASK
            focus_btn = btn if i==0
            btn.signal_connect('clicked') do |widget|
              clear_click = (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              btn.grab_focus
              smile_btn = @@smile_btn
              smile_btn.on_click_btn.call(preset, widget.label)
              hide_popwin if clear_click and (not smile_btn.poly_btn.active?)
              false
            end
            btn.signal_connect('key-press-event') do |widget, event|
              res = false
              if [Gdk::Keyval::GDK_space, Gdk::Keyval::GDK_KP_Space].include?(event.keyval)
                smile_btn = @@smile_btn
                smile_btn.on_click_btn.call(preset, widget.label)
                res = true
              elsif [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
                smile_btn = @@smile_btn
                smile_btn.on_click_btn.call(preset, widget.label)
                hide_popwin
                res = true
              end
              res
            end
            btn.signal_connect('expose-event') do |widget, event|
              if widget.focus?   #STATE_PRELIGHT
                widget.style.paint_focus(widget.window, Gtk::STATE_NORMAL, \
                  event.area, widget, '', event.area.x+1, event.area.y+1, \
                  event.area.width-2, event.area.height-2)
              end
              false
            end
            hbox.pack_start(btn, true, true, 0)
          end
          vbox.pack_start(hbox, false, false, 0)
          vbox.show_all
        end
        smiles_parent.add(vbox)
        res = [vbox, focus_btn]
        @@smile_boxes[preset] = res
      end
      res
    end

    def move_and_show(apreset=nil, x=nil, y=nil, a_on_click_btn=nil)
      @preset = apreset if apreset
      @on_click_btn = a_on_click_btn if a_on_click_btn
      popwidget = get_popwidget
      vbox, focus_btn = init_smiles_box(@preset, @smile_box, self)
      popwidget.show_all
      pwh = popwidget.size_request
      resize(*pwh)

      if x and y
        @x = x
        @y = y
      end

      move(@x, @y-pwh[1])
      show_all
      present
      focus_btn.grab_focus if focus_btn
    end

  end

  # Smile choose box
  # RU: Поле выбора смайлов
  class SmileButton < Gtk::ToolButton
    attr_accessor :on_click_btn, :popwin

    def initialize(apreset=nil, *args)
      aimage = $window.get_preset_image('smile')
      super(aimage, _('smile'))
      self.tooltip_text = _('smile')
      apreset ||= 'vk'
      @preset = apreset
      @@popwin ||= nil

      @on_click_btn = Proc.new do |*args|
        yield(*args) if block_given?
      end

      signal_connect('clicked') do |*args|
        popwin = @@popwin
        if popwin and (not popwin.destroyed?) and (popwin.visible? or popwin.just_leaved)
          popwin.hide
        else
          if popwin.nil? or popwin.destroyed?
            @@popwin = SmilePopWindow.new(@preset, false)
            popwin = @@popwin
          end
          borig = self.window.origin
          brect = self.allocation.to_a
          x = brect[0]+borig[0]
          y = brect[1]+borig[1]-1
          popwin.move_and_show(nil, x, y, @on_click_btn)
          popwin.poly_btn.set_active(false)
        end
        popwin.just_leaved = false
        false
      end
    end

  end

  # Color box for calendar day
  # RU: Цветной бокс дня календаря
  class ColorDayBox < Gtk::EventBox
    attr_accessor :bg, :day_date

    def initialize(background=nil)
      super()
      @bg = background
      self.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK | Gdk::Event::FOCUS_CHANGE_MASK
      self.signal_connect('focus-in-event') do |widget, event|
        self.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#88CC88')) if day_date
        false
      end
      self.signal_connect('focus-out-event') do |widget, event|
        self.modify_bg(Gtk::STATE_NORMAL, @bg)
        false
      end
      self.signal_connect('button-press-event') do |widget, event|
        res = false
        if (event.button == 1) and widget.can_focus?
          widget.set_focus(true)
          yield(self) if block_given?
          res = true
        elsif (event.button == 3)
          popwin = self.parent.parent.parent
          if popwin.is_a? DatePopWindow
            popwin.show_month_menu(event.time)
            res = true
          end
        end
        res
      end
    end

    def bg=(background)
      @bg = background
      bgc = nil
      if not bg.nil?
        if bg.is_a? String
          bgc = Gdk::Color.parse(bg)
        elsif
          bgc = bg
        end
      end
      @bg = bgc
      self.modify_bg(Gtk::STATE_NORMAL, bgc)
    end

  end

  # Date choose window
  # RU: Окно выбора даты
  class DatePopWindow < PopWindow
    attr_accessor :date, :year, :month, :month_btn, :year_btn, :date_entry, \
      :holidays, :left_mon_btn, :right_mon_btn, :left_year_btn, :right_year_btn

    def initialize(adate=nil, amodal=nil)
      @@month_menu = nil
      @@year_menu  = nil
      @@year_mi = nil
      @@days_box = nil
      @date ||= adate
      @year_holidays = {}
      super(amodal)
      self.signal_connect('key-press-event') do |widget, event|
        if [32, Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          if focus and (focus.is_a? ColorDayBox)
            event = Gdk::EventButton.new(Gdk::Event::BUTTON_PRESS)
            event.button = 1
            focus.signal_emit('button-press-event', event)
          end
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Tab)
          false
        elsif (event.keyval>=65360) and (event.keyval<=65367)
          ctrl = (event.state.control_mask? or event.state.shift_mask?)
          if event.keyval==65360 or (ctrl and event.keyval==65361)
            left_mon_btn.clicked
          elsif event.keyval==65367 or (ctrl and event.keyval==65363)
            right_mon_btn.clicked
          elsif event.keyval==65365 or (ctrl and event.keyval==65362)
            left_year_btn.clicked
          elsif event.keyval==65366 or (ctrl and event.keyval==65364)
            right_year_btn.clicked
          end
          false
        else
          false
        end
      end
      self.signal_connect('scroll-event') do |widget, event|
        ctrl = (event.state.control_mask? or event.state.shift_mask?)
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          if ctrl
            left_year_btn.clicked
          else
            left_mon_btn.clicked
          end
        else
          if ctrl
            right_year_btn.clicked
          else
            right_mon_btn.clicked
          end
        end
        true
      end
    end

    def get_holidays(year)
      @holidays = @year_holidays[year]
      if not @holidays
        holidays_fn = File.join($pandora_lang_dir, 'holiday.'+$country+'.'+year.to_s+'.txt')
        f_exist = File.exist?(holidays_fn)
        if not f_exist
          year = 0
          @holidays = @year_holidays[year]
          if not @holidays
            holidays_fn = File.join($pandora_lang_dir, 'holiday.'+$country+'.0000.txt')
            f_exist = File.exist?(holidays_fn)
          end
        end
        if f_exist
          @holidays = {}
          month = nil
          set_line = nil
          IO.foreach(holidays_fn) do |line|
            if (line.is_a? String) and (line.size>0)
              if line[0]==':'
                month = line[1..-1].to_i
                set_line = 0
              elsif set_line and (set_line<2)
                set_line += 1
                day_list = line.split(',')
                day_list.each do |days|
                  i = days.index('-')
                  if i
                    d1 = days[0, i].to_i
                    d2 = days[i+1..-1].to_i
                    (d1..d2).each do |d|
                      holidays[month.to_s+'.'+d.to_s] = true
                    end
                  else
                    holidays[month.to_s+'.'+days.to_i.to_s] = set_line
                  end
                end
              end
            end
          end
          @year_holidays[year] = @holidays
        end
      end
      @holidays
    end

    def show_month_menu(time=nil)
      if not @@month_menu
        @@month_menu = Gtk::Menu.new
        time_now = Time.now
        12.times do |mon|
          mon_time = Time.gm(time_now.year, mon+1, 1)
          menuitem = Gtk::MenuItem.new(_(mon_time.strftime('%B')))
          menuitem.signal_connect('activate') do |widget|
            @month = mon+1
            init_days_box
          end
          @@month_menu.append(menuitem)
          @@month_menu.show_all
        end
      end
      time ||= 0
      @@month_menu.popup(nil, nil, 3, time) do |menu, x, y, push_in|
        @just_leaved = nil
        GLib::Timeout.add(500) do
          @just_leaved = false if not destroyed?
          false
        end
        borig = @month_btn.window.origin
        brect = @month_btn.allocation.to_a
        x = borig[0]+brect[0]
        y = borig[1]+brect[1]+brect[3]
        [x, y]
      end
    end

    def show_year_menu(time=nil)
      if not @@year_menu
        @@year_menu = Gtk::Menu.new
        time_now = Time.now
        ((time_now.year-55)..time_now.year).each do |year|
          menuitem = Gtk::MenuItem.new(year.to_s)
          menuitem.signal_connect('activate') do |widget|
            @year = year
            get_holidays(@year)
            init_days_box
          end
          @@year_menu.append(menuitem)
          @@year_mi = menuitem if @year == year
        end
        @@year_menu.show_all
      end
      @@year_menu.select_item(@@year_mi) if @@year_mi
      time ||= 0
      @@year_menu.popup(nil, nil, 3, time) do |menu, x, y, push_in|
        @just_leaved = nil
        GLib::Timeout.add(500) do
          @just_leaved = false if not destroyed?
          false
        end
        borig = @year_btn.window.origin
        brect = @year_btn.allocation.to_a
        x = borig[0]+brect[0]
        y = borig[1]+brect[1]+brect[3]
        [x, y]
      end
    end

    def get_popwidget
      if @root_vbox.nil? or @root_vbox.destroyed?
        @root_vbox = Gtk::VBox.new
        @days_frame = Gtk::Frame.new
        @days_frame.shadow_type = Gtk::SHADOW_IN

        cur_btn = Gtk::Button.new(_'Current time')
        cur_btn.signal_connect('clicked') do |widget|
          time_now = Time.now
          if (@month == time_now.month) and (@year == time_now.year)
            @date_entry.on_click_btn.call(time_now)
          else
            @month = time_now.month
            @year = time_now.year
            get_holidays(@year)
          end
          init_days_box
        end
        root_vbox.pack_start(cur_btn, false, false, 0)

        row = Gtk::HBox.new
        @left_mon_btn = Gtk::Button.new('<')
        left_mon_btn.signal_connect('clicked') do |widget|
          if @month>1
            @month -= 1
          else
            @year -= 1
            @month = 12
            get_holidays(@year)
          end
          init_days_box
        end
        row.pack_start(left_mon_btn, true, true, 0)
        @month_btn = Gtk::Button.new('month')
        month_btn.width_request = 90
        month_btn.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
        month_btn.signal_connect('clicked') do |widget, event|
          show_month_menu
        end
        month_btn.signal_connect('scroll-event') do |widget, event|
          if (event.direction==Gdk::EventScroll::UP) \
          or (event.direction==Gdk::EventScroll::LEFT)
            left_mon_btn.clicked
          else
            right_mon_btn.clicked
          end
          true
        end
        row.pack_start(month_btn, true, true, 0)
        @right_mon_btn = Gtk::Button.new('>')
        right_mon_btn.signal_connect('clicked') do |widget|
          if @month<12
            @month += 1
          else
            @year += 1
            @month = 1
            get_holidays(@year)
          end
          init_days_box
        end
        row.pack_start(right_mon_btn, true, true, 0)

        @left_year_btn = Gtk::Button.new('<')
        left_year_btn.signal_connect('clicked') do |widget|
          @year -= 1
          get_holidays(@year)
          init_days_box
        end
        row.pack_start(left_year_btn, true, true, 0)
        @year_btn = Gtk::Button.new('year')
        year_btn.signal_connect('clicked') do |widget, event|
          show_year_menu
        end
        year_btn.signal_connect('scroll-event') do |widget, event|
          if (event.direction==Gdk::EventScroll::UP) \
          or (event.direction==Gdk::EventScroll::LEFT)
            left_year_btn.clicked
          else
            right_year_btn.clicked
          end
          true
        end
        row.pack_start(year_btn, true, true, 0)
        @right_year_btn = Gtk::Button.new('>')
        right_year_btn.signal_connect('clicked') do |widget|
          @year += 1
          get_holidays(@year)
          init_days_box
        end
        row.pack_start(right_year_btn, true, true, 0)

        root_vbox.pack_start(row, false, true, 0)
        root_vbox.pack_start(@days_frame, true, true, 0)
      end
      root_vbox
    end

    Sunday_Contries = ['US', 'JA', 'CA', 'IN', 'BR', 'AR', 'MX', 'IL', 'PH', \
      'PE', 'BO', 'EC', 'VE', 'ZA', 'CO', 'KR', 'TW', 'HN', 'NI', 'PA']
    Saturay_Contries = ['EG', 'LY', 'IR', 'AF', 'SY', 'DZ', 'SA', 'YE', 'IQ', 'JO']

    def init_days_box
      focus_btn = nil
      labs_parent = @days_frame
      if @@days_box
        evbox = @@days_box
        evbox = nil if evbox.destroyed?
      end
      @labs ||= []

      #p '---init_days_box: [date, month, year]='+[date, month, year].inspect
      time_now = Time.now
      month_d1 = Time.gm(@year, @month, 1)
      d1_wday = month_d1.wday
      start = nil
      if Sunday_Contries.include?($country)
        start = d1_wday
      elsif Saturay_Contries.include?($country)
        start = d1_wday+1
        start = 0 if d1_wday==6
      else
        d1_wday = 7 if d1_wday==0
        start = d1_wday-1
      end
      #start =+ 7 if start==0
      start_time = month_d1 - (start+1)*3600*24
      start_day = Time.gm(start_time.year, start_time.month, start_time.day)

      lab_evbox = nil

      if evbox
        resize(100, 100)
        if evbox.parent and (not evbox.parent.destroyed?)
          if (evbox.parent != labs_parent)
            labs_parent.remove(labs_parent.child) if labs_parent.child
            evbox.parent.remove(evbox)
            labs_parent.add(evbox)
            evbox.reparent(labs_parent)
          end
        else
          labs_parent.remove(labs_parent.child) if labs_parent.child
          evbox.parent = labs_parent
        end
      else
        labs_parent.remove(labs_parent.child) if labs_parent.child

        evbox = ColorDayBox.new('#FFFFFF')
        evbox.can_focus = false
        @@days_box = evbox
        labs_parent.add(evbox)

        vbox = Gtk::VBox.new

        7.times do |week|
          row = Gtk::HBox.new
          row.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
          vbox.pack_start(row, true, true, 1)
          7.times do |day|
            lab = Gtk::Label.new
            @labs[week*7+day] = lab
            lab.width_chars = 4
            lab.use_markup = true
            lab.justify = Gtk::JUSTIFY_CENTER

            lab_evbox = ColorDayBox.new do |lab_evbox|
              @date_entry.on_click_btn.call(lab_evbox.day_date)
            end
            lab_evbox.day_date = true
            lab_evbox.add(lab)
            row.pack_start(lab_evbox, true, true, 1)
          end
        end

        evbox.add(vbox)
        labs_parent.show_all
      end

      @month_btn.label = _(month_d1.strftime('%B'))
      @year_btn.label = month_d1.strftime('%Y')

      cal_day = start_day

      7.times do |week|
        7.times do |day|
          bg_type = nil
          curr_day = nil
          chsd_day = nil
          text = '0'
          if week==0
            #p '---[@year, @month, day+1]='+[@year, @month, day+1].inspect
            atime = start_day + (day+1)*3600*24
            text = _(atime.strftime('%a'))
            #p '+++++++ WEEKDAY='+text.inspect
            bg_type = :capt
          else
            cal_day += 3600*24
            text = (cal_day.day).to_s
            if cal_day.month == @month
              bg_type = :work
              wday = cal_day.wday
              bg_type = :rest if (wday==0) or (wday==6)
              if holidays and (set_line = holidays[@month.to_s+'.'+cal_day.day.to_s])
                if set_line==2
                  bg_type = :work
                else
                  bg_type = :holi
                end
              end
            end
            if (cal_day.day == time_now.day) and (cal_day.month == time_now.month) \
            and (cal_day.year == time_now.year)
              curr_day = true
            end
            if date and (cal_day.day == date.day) and (cal_day.month == date.month) \
            and (cal_day.year == date.year)
              chsd_day = true
            end
          end
          bg = nil
          tooltip = nil
          tooltip = _('Today') if curr_day
          if bg_type==:work
            bg = '#DDEEFF'
            tooltip ||= _('Workday')
          elsif bg_type==:rest
            bg = '#5050A0'
            tooltip ||= _('Weekend')
          elsif bg_type==:holi
            bg = '#B05050'
            tooltip ||= _('Holiday')
          else
            bg = '#FFFFFF'
          end

          lab = @labs[week*7+day]
          lab.tooltip_text = tooltip

          if lab.use_markup?
            if bg_type==:capt
              lab.set_markup('<b>'+text+'</b>')
            else
              fg = nil
              if (bg_type==:rest) or (bg_type==:holi)
                fg = '#66FF66' if curr_day
                fg ||= '#EEEE44' if chsd_day
                fg ||= '#FFFFFF'
              else
                fg = '#00BB00' if curr_day
                fg ||= '#AAAA00' if chsd_day
              end
              text = '<b>'+text+'</b>' if chsd_day
              fg ||= '#000000'
              lab.set_markup('<span foreground="'+fg+'">'+text+'</span>')
            end
          else
            lab.text = text
          end
          lab.parent.day_date = cal_day
          lab_evbox = lab.parent
          lab_evbox.bg = bg
          lab_evbox.can_focus = (bg_type != :capt)
          lab.can_focus = lab_evbox.can_focus?
          if lab_evbox.can_focus? and ((bg_type==:work) or bg_type.nil?)
            if date and (cal_day.month == date.month) and (cal_day.year == date.year)
              focus_btn = lab_evbox if chsd_day
            elsif curr_day
              focus_btn = lab_evbox
            end
          end
        end
      end

      [vbox, focus_btn]
    end

    def move_and_show(adate=nil, adate_entry=nil, x=nil, y=nil, a_on_click_btn=nil)
      @date = adate
      @date_entry = adate_entry if adate_entry
      if @date
        @month = date.month
        @year = date.year
      else
        time_now = Time.now
        @month = time_now.month
        @year = time_now.year
      end
      get_holidays(@year)
      @on_click_btn = a_on_click_btn if a_on_click_btn
      popwidget = get_popwidget
      vbox, focus_btn = init_days_box
      popwidget.show_all
      pwh = popwidget.size_request
      resize(*pwh)
      if x and y
        @x = x
        @y = y
      end
      move(@x, @y)
      show_all
      present
      p focus_btn
      if focus_btn
        focus_btn.grab_focus
      else
        month_btn.grab_focus
      end
    end

  end

  # Entry for date with calendar button
  # RU: Поле ввода даты с кнопкой календаря
  class DateEntry < BtnEntry
    attr_accessor :on_click_btn, :popwin

    def update_mark(month, year, time_now=nil)
      #time_now ||= Time.now
      #@cal.clear_marks
      #@cal.mark_day(time_now.day) if ((time_now.month==month) and (time_now.year==year))
    end

    def initialize(amodal=nil, *args)
      super(MaskEntry, :date, 'Date', amodal, *args)
      @@popwin ||= nil
      @close_on_enter = false
      @entry.mask = '0123456789.'
      @entry.max_length = 10
      @entry.tooltip_text = 'DD.MM.YYYY'
      @entry.width_request = PandoraGtk.num_char_width*@entry.max_length+8
      @on_click_btn = Proc.new do |date|
        @entry.text = PandoraUtils.date_to_str(date)
        @@popwin.hide_popwin
      end
    end

    def do_on_click
      res = false
      @entry.grab_focus
      popwin = @@popwin
      if popwin and (not popwin.destroyed?) and (popwin.visible? or popwin.just_leaved) \
      and (popwin.date_entry==self)
        popwin.hide
      else
        date = PandoraUtils.str_to_date(@entry.text)
        if popwin.nil? or popwin.destroyed? or (popwin.modal? != @modal)
          @@popwin = DatePopWindow.new(date, @modal)
          popwin = @@popwin
        end
        borig = @entry.window.origin
        brect = @entry.allocation.to_a
        x = borig[0]
        y = borig[1]+brect[3]+1
        popwin.move_and_show(date, self, x, y, @on_click_btn)
      end
      popwin.just_leaved = false
      res
    end

  end

  # Entry for time
  # RU: Поле ввода времени
  class TimeEntry < BtnEntry
    attr_accessor :hh_spin, :mm_spin, :ss_spin

    def initialize(amodal=nil, *args)
      super(MaskEntry, :time, 'Time', amodal, *args)
      @entry.mask = '0123456789:'
      @entry.max_length = 8
      @entry.tooltip_text = 'hh:mm:ss'
      @entry.width_request = PandoraGtk.num_char_width*@entry.max_length+8
      @@time_his ||= nil
    end

    def get_time(update_spin=nil)
      res = nil
      time = PandoraUtils.str_to_date(@entry.text)
      if time
        vals = time.to_a
        res = [vals[2], vals[1], vals[0]]  #hh,mm,ss
      else
        res = [0, 0, 0]
      end
      if update_spin
        hh_spin.value = res[0] if hh_spin
        mm_spin.value = res[1] if mm_spin
        ss_spin.value = res[2] if ss_spin
      end
      res
    end

    def set_time(hh, mm=nil, ss=nil)
      hh0, mm0, ss0 = get_time
      hh ||= hh0
      mm ||= mm0
      ss ||= ss0
      shh = PandoraUtils.int_to_str_zero(hh, 2)
      smm = PandoraUtils.int_to_str_zero(mm, 2)
      sss = PandoraUtils.int_to_str_zero(ss, 2)
      @entry.text = shh + ':' + smm + ':' + sss
    end

    ColNumber = 2
    RowNumber = 4
    DefTimeHis = '09:00|14:15|17:30|20:45'.split('|')

    def get_popwidget
      if not @@time_his
        @@time_his = PandoraUtils.get_param('time_history')
        @@time_his ||= ''
        @@time_his = @@time_his.split('|')
        (@@time_his.size..ColNumber*RowNumber-1).each do |i|
          @@time_his << DefTimeHis[i % DefTimeHis.size]
        end
      end
      vbox = Gtk::VBox.new
      btn1 = Gtk::Button.new(_'Current time')
      btn1.signal_connect('clicked') do |widget|
        @entry.text = Time.now.strftime('%H:%M:%S')
        get_time(true)
      end
      vbox.pack_start(btn1, false, false, 0)

      i = 0
      RowNumber.times do |row|
        hbox = Gtk::HBox.new
        ColNumber.times do |col|
          time_str = @@time_his[row + col*RowNumber]
          if time_str
            btn = Gtk::Button.new(time_str)
            btn.signal_connect('clicked') do |widget|
              @entry.text = widget.label+':00'
              get_time(true)
            end
            hbox.pack_start(btn, true, true, 0)
          else
            break
          end
        end
        vbox.pack_start(hbox, false, false, 0)
      end

      hbox = Gtk::HBox.new

      adj = Gtk::Adjustment.new(0, 0, 23, 1, 5, 0)
      @hh_spin = Gtk::SpinButton.new(adj, 0, 0)
      hh_spin.max_length = 2
      hh_spin.numeric = true
      hh_spin.wrap = true
      hh_spin.signal_connect('value-changed') do |widget|
        set_time(widget.value_as_int)
      end
      hbox.pack_start(hh_spin, false, true, 0)

      adj = Gtk::Adjustment.new(0, 0, 59, 1, 5, 0)
      @mm_spin = Gtk::SpinButton.new(adj, 0, 0)
      mm_spin.max_length = 2
      mm_spin.numeric = true
      mm_spin.wrap = true
      mm_spin.signal_connect('value-changed') do |widget|
        set_time(nil, widget.value_as_int)
      end
      hbox.pack_start(mm_spin, false, true, 0)

      adj = Gtk::Adjustment.new(0, 0, 59, 1, 5, 0)
      @ss_spin = Gtk::SpinButton.new(adj, 0, 0)
      ss_spin.max_length = 2
      ss_spin.numeric = true
      ss_spin.wrap = true
      ss_spin.signal_connect('value-changed') do |widget|
        set_time(nil, nil, widget.value_as_int)
      end
      hbox.pack_start(ss_spin, false, true, 0)

      get_time(true)
      vbox.pack_start(hbox, false, false, 0)

      btn = Gtk::Button.new(Gtk::Stock::OK)
      btn.signal_connect('clicked') do |widget|
        new_time = @entry.text
        if new_time and @@time_his
          i = new_time.rindex(':')
          new_time = new_time[0, i] if i
          i = @@time_his.index(new_time)
          if (not i) or (i >= (@@time_his.size / 2))
            if i
              @@time_his.delete_at(i)
            else
              @@time_his.pop
            end
            @@time_his.unshift(new_time)
            PandoraUtils.set_param('time_history', @@time_his.join('|'))
          end
        end
        @popwin.destroy
        @popwin = nil
      end
      vbox.pack_start(btn, false, false, 0)

      hh_spin.grab_focus

      vbox
    end

  end

  # Entry for relation kind
  # RU: Поле ввода типа связи
  class ByteListEntry < BtnEntry

    def initialize(code_name_list, amodal=nil, *args)
      super(MaskEntry, :list, 'List', amodal, *args)
      @close_on_enter = false
      @code_name_list = code_name_list
      @entry.mask = '0123456789'
      @entry.max_length = 3
      @entry.tooltip_text = 'NNN'
      @entry.width_request = PandoraGtk.num_char_width*10+8
    end

    def get_popwidget
      store = Gtk::ListStore.new(Integer, String)
      @code_name_list.each do |kind,name|
        iter = store.append
        iter[0] = kind
        iter[1] = _(name)
      end

      @treeview = Gtk::TreeView.new(store)
      treeview = @treeview
      treeview.rules_hint = true
      treeview.search_column = 0
      treeview.border_width = 10
      #treeview.hover_selection = false
      #treeview.selection.mode = Gtk::SELECTION_BROWSE

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Code'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      treeview.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Description'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      treeview.append_column(column)

      treeview.signal_connect('row-activated') do |tree_view, path, column|
        path, column = tree_view.cursor
        if path
          store = tree_view.model
          iter = store.get_iter(path)
          if iter and iter[0]
            @entry.text = iter[0].to_s
            if not @popwin.destroyed?
              @popwin.destroy
              @popwin = nil
            end
          end
        end
        false
      end

      # Make choose only when click to selected
      #treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      #treeview.signal_connect('button-press-event') do |widget, event|
      #  @iter = widget.selection.selected if (event.button == 1)
      #  false
      #end
      #treeview.signal_connect('button-release-event') do |widget, event|
      #  if (event.button == 1) and @iter
      #    path, column = widget.cursor
      #    if path and (@iter.path == path)
      #      widget.signal_emit('row-activated', nil, nil)
      #    end
      #  end
      #  false
      #end

      treeview.signal_connect('event-after') do |widget, event|
        if event.kind_of?(Gdk::EventButton) and (event.button == 1)
          iter = widget.selection.selected
          if iter
            path, column = widget.cursor
            if path and (iter.path == path)
              widget.signal_emit('row-activated', nil, nil)
            end
          end
        end
        false
      end

      treeview.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          widget.signal_emit('row-activated', nil, nil)
          true
        else
          false
        end
      end

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      #list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.shadow_type = Gtk::SHADOW_NONE
      list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      list_sw.border_width = 0
      list_sw.add(treeview)

      awidth, aheight = treeview.size_request
      awidth += 5
      scr = Gdk::Screen.default
      swidth = scr.width-80
      sheight = scr.height-100
      swidth = 500 if swidth>500
      awidth = swidth if awidth>swidth
      if aheight>sheight
        aheight = sheight
        awidth += 30
      end
      list_sw.set_size_request(awidth, aheight)

      frame = Gtk::Frame.new
      frame.shadow_type = Gtk::SHADOW_OUT
      frame.add(list_sw)

      treeview.can_default = true
      treeview.grab_focus

      frame
    end
  end

  # Dialog for panhash choose
  # RU: Диалог для выбора панхэша
  class PanhashDialog < AdvancedDialog
    attr_accessor :panclasses

    def initialize(apanclasses)
      @panclasses = apanclasses
      super(_('Choose object'))
      $window.register_stock(:panhash)
      iconset = Gtk::IconFactory.lookup_default('panhash')
      style = Gtk::Widget.default_style  #Gtk::Style.new
      anicon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
      self.icon = anicon

      self.skip_taskbar_hint = true
      self.set_default_size(700, 450)
      auto_create = true
      @panclasses.each_with_index do |panclass, i|
        title = _(PandoraUtils.get_name_or_names(panclass.name, true))
        self.main_sw.destroy if i==0
        #image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
        image = $window.get_panobject_image(panclass.ider, Gtk::IconSize::SMALL_TOOLBAR)
        label_box2 = TabLabelBox.new(image, title)
        pbox = PandoraGtk::PanobjScrolledWindow.new
        page = self.notebook.append_page(pbox, label_box2)
        auto_create = PandoraGtk.show_panobject_list(panclass, nil, pbox, auto_create)
      end
      self.notebook.page = 0
    end

    # Show dialog and send choosed panhash,sha1,md5 to yield block
    # RU: Показать диалог и послать панхэш,sha1,md5 в выбранный блок
    def choose_record(*add_fields)
      self.run2 do
        panhash = nil
        treeview = nil
        add_fields = nil if not ((add_fields.is_a? Array) and (add_fields.size>0))
        field_vals = nil
        pbox = self.notebook.get_nth_page(self.notebook.page)
        if pbox.is_a?(PandoraGtk::CabinetBox)
          treeview = pbox.tree_view
          page_sw = nil
          page_sw = treeview.page_sw if treeview
          pbox.save_and_close
          sleep(0.01)
          page = nil
          page = self.notebook.page_num(page_sw)
          #page = self.notebook.children.index(page_sw) if page_sw
          self.notebook.page = page if page
          pbox = self.notebook.get_nth_page(self.notebook.page)
          pbox ||= page_sw
        end
        treeview = pbox.treeview if pbox.is_a?(PanobjScrolledWindow)
        if treeview.is_a?(SubjTreeView)
          treeview.grab_focus
          path, column = treeview.cursor
          panobject = treeview.panobject
          if path and panobject
            store = treeview.model
            iter = store.get_iter(path)
            id = iter[0]
            fields = 'panhash'
            this_is_blob = (panobject.is_a? PandoraModel::Blob)
            fields << ','+add_fields.join(',') if add_fields
            sel = panobject.select('id='+id.to_s, false, fields)
            if sel and (sel.size>0)
              rec = sel[0]
              panhash = rec[0]
              field_vals = rec[1..-1] if add_fields
            end
          end
        end
        if block_given?
          if field_vals
            yield(panhash, *field_vals)
          else
            yield(panhash)
          end
        end
      end
    end

  end

  MaxPanhashTabs = 5

  # Entry for panhash
  # RU: Поле ввода панхэша
  class PanhashBox < BtnEntry
    attr_accessor :types, :panclasses, :view_button

    def initialize(panhash_type, amodal=nil, *args)
      @panclasses = nil
      @types = panhash_type
      stock = nil
      if @types=='Panhash'
        @types = 'Panhash(Blob,Person,Community,City,Key)'
        stock = :panhash
      end
      set_classes
      title = nil
      if (panclasses.is_a? Array) and (panclasses.size>0) and (not @types.nil?)
        stock ||= $window.get_panobject_stock(panclasses[0].ider)
        panclasses.each do |panclass|
          if title
            title << ', '
          else
            title = ''
          end
          title << panclass.sname
        end
      end
      stock ||= :panhash
      stock = stock.to_sym
      title ||= 'Panhash'
      super(HexEntry, stock, title, amodal=nil, *args)
      @view_button = self.add_button(Gtk::Stock::HOME, 'Cabinet') do
        panhash = @entry.text
        if (panhash.bytesize>4) and PandoraUtils.hex?(panhash)
          panhash = PandoraUtils.hex_to_bytes(panhash)
          if not PandoraUtils.panhash_nil?(panhash)
            PandoraGtk.show_cabinet(panhash, nil, nil, nil, \
              nil, PandoraUI::CPI_Profile)
          end
        end
      end
      @entry.max_length = 44
      @entry.width_request = PandoraGtk.num_char_width*(@entry.max_length+1)+8
    end

    def do_on_click
      @entry.grab_focus
      set_classes
      dialog = PanhashDialog.new(@panclasses)
      dialog.choose_record do |panhash|
        if PandoraUtils.panhash_nil?(panhash)
          @entry.text = ''
        else
          @entry.text = PandoraUtils.bytes_to_hex(panhash) if (panhash.is_a? String)
        end
      end
      true
    end

    # Define panobject class list
    # RU: Определить список классов панобъектов
    def set_classes
      if not @panclasses
        #p '=== types='+types.inspect
        @panclasses = []
        @types.strip!
        if (types.is_a? String) and (types.size>0)
          drop_prefix = 0
          if (@types[0, 10].downcase=='panhashes(')
            drop_prefix = 10
          elsif (@types[0, 8].downcase=='panhash(')
            drop_prefix = 8
          end
          if drop_prefix>0
            @types = @types[drop_prefix..-2]
            @types.strip!
            @types = @types.split(',')
            @types.each do |ptype|
              ptype.strip!
              if PandoraModel.const_defined?(ptype)
                @panclasses << PandoraModel.const_get(ptype)
              end
            end
          end
        end
        if @panclasses.size==0
          @types = nil
          kind_list = PandoraModel.get_kind_list
          kind_list.each do |rec|
            ptype = rec[1]
            ptype.strip!
            p '---ptype='+ptype.inspect
            if PandoraModel.const_defined?(ptype)
              @panclasses << PandoraModel.const_get(ptype)
            end
            if @panclasses.size>MaxPanhashTabs
              break
            end
          end
        end
        #p '====panclasses='+panclasses.inspect
      end
    end

  end

  # Good FileChooserDialog
  # RU: Правильный FileChooserDialog
  class GoodFileChooserDialog < Gtk::FileChooserDialog
    def initialize(file_name, open=true, filters=nil, parent_win=nil, title=nil, last_dirs=nil)
      action = nil
      act_btn = nil
      stock_id = nil
      if open
        action = Gtk::FileChooser::ACTION_OPEN
        stock_id = Gtk::Stock::OPEN
        act_btn = [stock_id, Gtk::Dialog::RESPONSE_ACCEPT]
      else
        action = Gtk::FileChooser::ACTION_SAVE
        stock_id = Gtk::Stock::SAVE
        act_btn = [stock_id, Gtk::Dialog::RESPONSE_ACCEPT]
        title ||= 'Save to file'
      end
      title ||= 'Choose a file'
      parent_win ||= $window
      super(_(title), parent_win, action, 'gnome-vfs',
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL], act_btn)
      dialog = self
      dialog.transient_for = parent_win
      dialog.skip_taskbar_hint = true
      dialog.default_response = Gtk::Dialog::RESPONSE_ACCEPT
      #image = $window.get_preset_image('export')
      #iconset = image.icon_set
      iconset = Gtk::IconFactory.lookup_default(stock_id.to_s)
      style = Gtk::Widget.default_style  #Gtk::Style.new
      anicon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
      dialog.icon = anicon
      last_dir = nil
      last_dirs.each do |dn|
        if Dir.exists?(dn)
          begin
            dialog.add_shortcut_folder(dn)
          rescue
          end
          last_dir ||= dn
        end
      end
      last_dir ||= $pandora_files_dir

      dialog.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask? #w, W, ц, Ц
        then
          dialog.response(Gtk::Dialog::RESPONSE_CANCEL)
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          dialog.destroy
          PandoraUI.do_menu_act('Quit')
          false
        else
          false
        end
      end

      filter = Gtk::FileFilter.new
      filter.name = _('All files')+' (*.*)'
      filter.add_pattern('*.*')
      dialog.add_filter(filter)

      if open
        dialog.current_folder = last_dir
        dialog.filename = file_name if file_name and (file_name.size>0)
        scr = Gdk::Screen.default
        if (scr.height > 500)
          frame = Gtk::Frame.new
          frame.shadow_type = Gtk::SHADOW_IN
          align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
          align.add(frame)
          image = Gtk::Image.new
          frame.add(image)
          align.show_all

          dialog.preview_widget = align
          dialog.use_preview_label = false
          dialog.signal_connect('update-preview') do
            fn = dialog.preview_filename
            ext = nil
            ext = File.extname(fn) if fn
            if ext and (['.jpg','.jpeg','.gif','.png', '.ico'].include? ext.downcase)
              begin
                pixbuf = Gdk::Pixbuf.new(fn, 128, 128)
                image.pixbuf = pixbuf
                dialog.preview_widget_active = true
              rescue
                dialog.preview_widget_active = false
              end
            else
              dialog.preview_widget_active = false
            end
          end
        end
      else #save
        if File.exist?(file_name)
          dialog.filename = file_name
        else
          dialog.current_name = File.basename(file_name) if file_name
          dialog.current_folder = last_dir
        end
        dialog.signal_connect('notify::filter') do |widget, param|
          aname = dialog.filter.name
          i = aname.index('*.')
          ext = nil
          ext = aname[i+2..-2] if i
          if ext
            i = ext.index('*.')
            ext = ext[0..i-2] if i
          end
          if ext.nil? or (ext != '*')
            ext ||= ''
            fn = PandoraUtils.change_file_ext(dialog.filename, ext)
            dialog.current_name = File.basename(fn) if fn
          end
        end
      end
    end
  end

  FileDialogHistorySize = 5

  # Entry for filename
  # RU: Поле выбора имени файла
  class FilenameBox < BtnEntry
    attr_accessor :window

    def initialize(parent, amodal=nil, *args)
      super(Gtk::Entry, Gtk::Stock::OPEN, 'File', amodal, *args)
      @window = parent
      @entry.width_request = PandoraGtk.num_char_width*64+8
      @@last_dirs ||= [$pandora_files_dir, $pandora_app_dir]
    end

    def do_on_click
      @entry.grab_focus
      fn = PandoraUtils.absolute_path(@entry.text)
      dialog = GoodFileChooserDialog.new(fn, true, nil, @window, nil, @@last_dirs)
      filter = Gtk::FileFilter.new
      filter.name = _('Pictures')+' (*.png,*.jpg,*.gif,*.ico)'
      filter.add_pattern('*.png')
      filter.add_pattern('*.jpg')
      filter.add_pattern('*.jpeg')
      filter.add_pattern('*.gif')
      filter.add_pattern('*.ico')
      dialog.add_filter(filter)

      filter = Gtk::FileFilter.new
      filter.name = _('Sounds')+' (*.mp3,*.wav)'
      filter.add_pattern('*.mp3')
      filter.add_pattern('*.wav')
      dialog.add_filter(filter)

      if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
        filename0 = @entry.text
        fn = dialog.filename
        dn = nil
        dn = File.dirname(fn) if fn
        if Dir.exists?(dn) and (@@last_dirs[0] != dn)
          @@last_dirs.delete(dn)
          @@last_dirs.unshift(dn)
          @@last_dirs.pop while @@last_dirs.count>FileDialogHistorySize
        end
        @entry.text = PandoraUtils.relative_path(fn)
        if @init_yield_block
          @init_yield_block.call(@entry.text, @entry, @button, filename0)
        end
      end
      dialog.destroy if not dialog.destroyed?
      true
    end

    def width_request=(wr)
      s = button.size_request
      h = s[0]+1
      wr -= h
      wr = 24 if wr<24
      entry.set_width_request(wr)
    end

  end

  # Entry for coordinate
  # RU: Поле ввода координаты
  class CoordEntry < FloatEntry
    def init_mask
      super
      @mask += 'EsNn SwW\'"`′″,'
      self.max_length = 35
    end
  end

  # Entry for coordinates
  # RU: Поле ввода координат
  class CoordBox < BtnEntry # Gtk::HBox
    attr_accessor :latitude, :longitude
    CoordWidth = 110

    def initialize(amodal=nil, hide_btn=nil)
      super(Gtk::HBox, :coord, 'Coordinates', amodal)
      @latitude   = CoordEntry.new
      latitude.tooltip_text = _('Latitude')+': 60.716, 60 43\', 60.43\'00"N'+"\n["+latitude.mask+']'
      @longitude  = CoordEntry.new
      longitude.tooltip_text = _('Longitude')+': -114.9, W114 54\' 0", 114.9W'+"\n["+longitude.mask+']'
      latitude.width_request = CoordWidth
      longitude.width_request = CoordWidth
      entry.pack_start(latitude, false, false, 0)
      @entry.pack_start(longitude, false, false, 1)
      if hide_btn
        @button.destroy
        @button = nil
      end
    end

    def do_on_click
      @latitude.grab_focus
      dialog = PanhashDialog.new([PandoraModel::City])
      dialog.choose_record('coord') do |panhash,coord|
        if coord
          geo_coord = PandoraUtils.coil_coord_to_geo_coord(coord)
          if geo_coord.is_a? Array
            latitude.text = geo_coord[0].to_s
            longitude.text = geo_coord[1].to_s
          end
        end
      end
      true
    end

    def max_length=(maxlen)
      btn_width = 0
      btn_width = @button.allocation.width if @button
      ml = (maxlen-btn_width) / 2
      latitude.max_length = ml
      longitude.max_length = ml
    end

    def text=(text)
      i = nil
      begin
        i = text.to_i if (text.is_a? String) and (text.size>0)
      rescue
        i = nil
      end
      if i
        coord = PandoraUtils.coil_coord_to_geo_coord(i)
      else
        coord = ['', '']
      end
      latitude.text = coord[0].to_s
      longitude.text = coord[1].to_s
    end

    def text
      res = PandoraUtils.geo_coord_to_coil_coord(latitude.text, longitude.text).to_s
    end

    def width_request=(wr)
      w = (wr+10) / 2
      latitude.set_width_request(w)
      longitude.set_width_request(w)
    end

    def modify_text(*args)
      latitude.modify_text(*args)
      longitude.modify_text(*args)
    end

    def size_request
      size1 = latitude.size_request
      res = longitude.size_request
      res[0] = size1[0]+1+res[0]
      res
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class DateTimeBox < Gtk::HBox
    attr_accessor :date, :time

    def initialize(amodal=nil)
      super()
      @date   = DateEntry.new(amodal)
      @time   = TimeEntry.new(amodal)
      #date.width_request = CoordWidth
      #time.width_request = CoordWidth
      self.pack_start(date, false, false, 0)
      self.pack_start(time, false, false, 1)
    end

    def max_length=(maxlen)
      ml = maxlen / 2
      date.max_length = ml
      time.max_length = ml
    end

    def text=(text)
      date_str = nil
      time_str = nil
      if (text.is_a? String) and (text.size>0)
        i = text.index(' ')
        i ||= text.size
        date_str = text[0, i]
        time_str = text[i+1..-1]
      end
      date_str ||= ''
      time_str ||= ''
      date.text = date_str
      time.text = time_str
    end

    def text
      res = date.text + ' ' + time.text
    end

    def width_request=(wr)
      w = wr / 2
      date.set_width_request(w+10)
      time.set_width_request(w)
    end

    def modify_text(*args)
      date.modify_text(*args)
      time.modify_text(*args)
    end

    def size_request
      size1 = date.size_request
      res = time.size_request
      res[0] = size1[0]+1+res[0]
      res
    end
  end

  MaxOnePlaceViewSec = 60

  # Extended TextView
  # RU: Расширенный TextView
  class ExtTextView < Gtk::TextView
    attr_accessor :need_to_end, :middle_time, :middle_value, :go_to_end

    def initialize
      super
      self.receives_default = true
      signal_connect('key-press-event') do |widget, event|
        res = false
        if (event.keyval == Gdk::Keyval::GDK_F9)
          set_readonly(self.editable?)
          res = true
        end
        res
      end

      @go_to_end = false

      self.signal_connect('size-allocate') do |widget, step, arg2|
        if @go_to_end
          @go_to_end = false
          widget.parent.vadjustment.value = \
          widget.parent.vadjustment.upper - widget.parent.vadjustment.page_size
        end
        false
      end

    end

    def set_readonly(value=true)
      PandoraGtk.set_readonly(self, value, false)
    end

    # Do before addition
    # RU: Выполнить перед добавлением
    def before_addition(cur_time=nil, vadj_value=nil)
      cur_time ||= Time.now
      vadj_value ||= self.parent.vadjustment.value
      @need_to_end = ((vadj_value + self.parent.vadjustment.page_size) == self.parent.vadjustment.upper)
      if not @need_to_end
        if @middle_time and @middle_value and (@middle_value == vadj_value)
          if ((cur_time.to_i - @middle_time.to_i) > MaxOnePlaceViewSec)
            @need_to_end = true
            @middle_time = nil
          end
        else
          @middle_time = cur_time
          @middle_value = vadj_value
        end
      end
      @need_to_end
    end

    # Do after addition
    # RU: Выполнить после добавления
    def after_addition(go_end=nil)
      go_end ||= @need_to_end
      if go_end
        @go_to_end = true
        adj = self.parent.vadjustment
        adj.value = adj.upper - adj.page_size
        #scroll_to_iter(buffer.end_iter, 0, true, 0.0, 1.0)
        #mark = buffer.create_mark(nil, buffer.end_iter, false)
        #scroll_to_mark(mark, 0, true, 0.0, 1.0)
        #tv.scroll_to_mark(buf.get_mark('insert'), 0.0, true, 0.0, 1.0)
        #buffer.delete_mark(mark)
      end
      go_end
    end
  end

  class ScalePixbufLoader < Gdk::PixbufLoader
    attr_accessor :scale, :width, :height, :scaled_pixbuf, :set_dest, :renew_thread

    def initialize(ascale=nil, awidth=nil, aheight=nil, *args)
      super(*args)
      @scale = 100
      @width  = nil
      @height = nil
      @scaled_pixbuf = nil
      set_scale(ascale, awidth, aheight)
    end

    def set_scale(ascale=nil, awidth=nil, aheight=nil)
      ascale ||= 100
      if (@scale != ascale) or (@width != awidth) or (@height = aheight)
        @scale = ascale
        @width  = awidth
        @height = aheight
        renew_scaled_pixbuf
      end
    end

    def renew_scaled_pixbuf(redraw_wiget=nil)
      apixbuf = self.pixbuf
      if apixbuf and ((@scale != 100) or @width or @height)
        if not @renew_thread
          @renew_thread = Thread.new do
            #sleep(0.01)
            @renew_thread = nil
            apixbuf = self.pixbuf
            awidth  = apixbuf.width
            aheight = apixbuf.height

            scale_x = nil
            scale_y = nil
            if @width or @height
              p scale_x = @width.fdiv(awidth) if @width
              p scale_y = @height.fdiv(aheight) if @height
              new_scale = nil
              if scale_x and (scale_x<1.0)
                new_scale = scale_x
              end
              if scale_y and ((scale_x and scale_x<1.0 and scale_y.abs<scale_x.abs) \
              or ((not scale_x) and scale_y<1.0))
                new_scale = scale_y
              end
              if new_scale
                new_scale = new_scale.abs
              else
                new_scale = 1.0
              end
              scale_x = scale_y = new_scale
            end
            #p '      SCALE [@scale, @width, @height, awidth, aheight, scale_x, scale_y]='+\
            #  [@scale, @width, @height, awidth, aheight, scale_x, scale_y].inspect
            if not scale_x
              scale_x = @scale.fdiv(100)
              scale_y = scale_x
            end
            p dest_width  = awidth*scale_x
            p dest_height = aheight*scale_y
            if @scaled_pixbuf
              @scaled_pixbuf.scale!(apixbuf, 0, 0, dest_width, dest_height, 0, 0, scale_x, scale_y)
            else
              @scaled_pixbuf = apixbuf.scale(dest_width, dest_height)
            end
            set_dest.call(@scaled_pixbuf) if set_dest
            redraw_wiget.queue_draw if redraw_wiget and (not redraw_wiget.destroyed?)
          end
        end
      else
        @scaled_pixbuf = apixbuf
        redraw_wiget.queue_draw if redraw_wiget and (not redraw_wiget.destroyed?)
      end
      @scaled_pixbuf
    end

  end

  ReadImagePortionSize = 1024*1024 # 1Mb

  # Start loading image from file
  # RU: Запускает загрузку картинки в файл
  def self.start_image_loading(filename, pixbuf_parent=nil, scale=nil, width=nil, height=nil)
    res = nil
    p '--start_image_loading  [filename, pixbuf_parent, scale, width, height]='+\
      [filename, pixbuf_parent, scale, width, height].inspect
    filename = PandoraUtils.absolute_path(filename)
    if File.exist?(filename)
      if (scale.nil? or (scale==100)) and width.nil? and height.nil?
        begin
          res = Gdk::Pixbuf.new(filename)
          if not pixbuf_parent
            res = Gtk::Image.new(res)
          end
        rescue => err
          if not pixbuf_parent
            err_text = _('Image loading error1')+":\n"+Utf8String.new(err.message)
            label = Gtk::Label.new(err_text)
            res = label
          end
        end
      else
        begin
          file_stream = File.open(filename, 'rb')
          res = Gtk::Image.new if not pixbuf_parent
          #sleep(0.01)
          scale ||= 100
          read_thread = Thread.new do
            pixbuf_loader = ScalePixbufLoader.new(scale, width, height)
            pixbuf_loader.signal_connect('area_prepared') do |loader|
              loader.set_dest = Proc.new do |apixbuf|
                if pixbuf_parent
                  res = apixbuf
                else
                  res.pixbuf = apixbuf if (not res.destroyed?)
                end
              end
              pixbuf = loader.pixbuf
              pixbuf.fill!(0xAAAAAAFF)
              loader.renew_scaled_pixbuf(res)
              loader.set_dest.call(loader.scaled_pixbuf)
            end
            pixbuf_loader.signal_connect('area_updated') do |loader|
              upd_wid = res
              upd_wid = pixbuf_parent if pixbuf_parent
              loader.renew_scaled_pixbuf(upd_wid)
              if pixbuf_parent
                #res = loader.pixbuf
              else
                #res.pixbuf = loader.pixbuf if (not res.destroyed?)
              end
            end
            while file_stream
              buf = file_stream.read(ReadImagePortionSize)
              if buf
                pixbuf_loader.write(buf)
                if file_stream.eof?
                  pixbuf_loader.close
                  pixbuf_loader = nil
                  file_stream.close
                  file_stream = nil
                end
                sleep(0.005)
                #sleep(1)
              else
                pixbuf_loader.close
                pixbuf_loader = nil
                file_stream.close
                file_stream = nil
              end
            end
          end
          while pixbuf_parent and read_thread.alive?
            sleep(0.01)
          end
        rescue => err
          if not pixbuf_parent
            err_text = _('Image loading error2')+":\n"+Utf8String.new(err.message)
            label = Gtk::Label.new(err_text)
            res = label
          end
        end
      end
    end
    res
  end

  # Apply property values to the GLib object
  # RU: Применяет значения свойств к объекту GLib
  def self.apply_properties_to_glib_object(properties, obj)
    if properties.is_a?(Hash)
      properties.each do |n, v|
        #obj.instance_variable_set(n, v)
        obj.set_property(n, v)
      end
    end
  end

  # Copy properties from one GLib object to another (using for TextTag)
  # RU: Копирует свойства одного объекта GLib к другому (используется для TextTag)
  def self.copy_glib_object_properties(src_obj, dest_obj)
    if src_obj and dest_obj
      #p '---copy_glib_object_properties  [src_obj, dest_obj]='+[src_obj, dest_obj].inspect
      prev_props = src_obj.class.properties(false)
      prev_props.each do |prop|
        #p prop
        if (prop and (prop != 'name') and (prop != 'tabs') \
        and src_obj.class.property(prop).readable? \
        and dest_obj.class.property(prop).writable?)
          val = src_obj.get_property(prop)
          dest_obj.set_property(prop, val) #if val
        end
      end
    end
  end

  # TextView tag with url field
  # RU: Тег TextView с полем ссылки
  class LinkTag < Gtk::TextTag
    attr_accessor :link
  end

  # Search panel for the text editor
  # RU: Панель поиска для текстового редактора
  class FindPanel < Gtk::Window
    attr_accessor :treeview, :find_vbox, :entry, :count_label, \
      :replace_hbox, :replace_btn, :replace_entry, \
      :find_image, :replace_image, :back_image, :forward_image, \
      :close_image, :all_image, :positions, :find_pos, :find_len, \
      :back_btn, :forward_btn, :casesens_btn, :find_line

    def initialize(atreeview, areplace, amodal=false)
      super()
      @search_thread = nil
      @treeview = atreeview
      #popwin = Gtk::Window.new #(Gtk::Window::POPUP)
      popwin = self
      #@find_panel = popwin
      @replace_hbox = nil
      @found_lines = nil
      @max_line = nil
      @find_line = nil
      #win_os = (PandoraUtils.os_family == 'windows')
      popwin.transient_for = $window #if win_os
      popwin.modal = amodal #(not win_os)
      popwin.decorated = false
      popwin.skip_taskbar_hint = true
      popwin.destroy_with_parent = true
      popwin.border_width = 1

      @find_vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      @entry = Gtk::Entry.new
      entry.width_request = PandoraGtk.num_char_width*30+8
      entry.max_length = 512
      #entry = Gtk::Combo.new  #Gtk::Entry.new
      #entry.set_popdown_strings(['word1', 'word2'])
      entry.signal_connect('changed') do |widget, event|
        self.find_text(false, true)
        false
      end
      entry.signal_connect('key-press-event') do |widget, event|
        res = false
        if (event.keyval==Gdk::Keyval::GDK_Tab)
          if @replace_btn and @replace_btn.active? and @replace_entry
            @replace_entry.grab_focus
            res = true
          end
        elsif (event.keyval>=65360) and (event.keyval<=65367)
          ctrl = (event.state.control_mask? or event.state.shift_mask?)
          #if event.keyval==65360 or (ctrl and event.keyval==65361)    #Left
          #  left_mon_btn.clicked
          #elsif event.keyval==65367 or (ctrl and event.keyval==65363) #Right
          #  right_mon_btn.clicked
          if event.keyval==65365 or event.keyval==65362 #PgUp, Up
            if ctrl
              self.move_to_find_pos(-2)
            else
              self.move_to_find_pos(-1)
            end
            res = true
          elsif (event.keyval==65366) or (event.keyval==65364) #PgDn, Down
            if (event.keyval==65364) and (not ctrl) and @replace_btn \
            and @replace_btn.active? and @replace_entry
              @replace_entry.grab_focus
            elsif ctrl
              self.move_to_find_pos(2)
            else
              self.move_to_find_pos(1)
            end
            res = true
          end
        end
        res
      end

      entry.show_all
      awidth, btn_height = entry.size_request
      btn_height -= 8
      wim, him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
      btn_height = him if btn_height < him

      #@@back_buf ||= $window.get_preset_icon(Gtk::Stock::GO_BACK, nil, btn_height)
      #@@forward_buf ||= $window.get_preset_icon(Gtk::Stock::GO_FORWARD, nil, btn_height)
      @@find_buf ||= $window.get_preset_icon(Gtk::Stock::FIND, nil, btn_height)
      @@replace_buf ||= $window.get_preset_icon(Gtk::Stock::FIND_AND_REPLACE, nil, btn_height)
      @@back_buf ||= $window.get_preset_icon(Gtk::Stock::GO_UP, nil, btn_height)
      @@forward_buf ||= $window.get_preset_icon(Gtk::Stock::GO_DOWN, nil, btn_height)
      @@all_buf ||= $window.get_preset_icon(Gtk::Stock::SELECT_ALL, nil, btn_height)
      @@close_buf ||= $window.get_preset_icon(Gtk::Stock::CLOSE, nil, 10)
      $window.register_stock(:case)
      @@case_buf ||= $window.get_preset_icon(:case, nil, btn_height)

      @find_image = Gtk::Image.new(@@find_buf)
      @replace_image = Gtk::Image.new(@@replace_buf)
      @back_image = Gtk::Image.new(@@back_buf)
      @forward_image = Gtk::Image.new(@@forward_buf)
      @close_image = Gtk::Image.new(@@close_buf)
      @all_image = Gtk::Image.new(@@all_buf)
      @case_image = Gtk::Image.new(@@case_buf)

      @find_image.show
      @replace_image.show

      @replace_btn = SafeToggleToolButton.new  #Gtk::ToolButton.new(find_image, _('Find'))
      if areplace
        replace_btn.icon_widget = @replace_image
      else
        replace_btn.icon_widget = @find_image
      end
      replace_btn.can_focus = false
      replace_btn.can_default = false
      replace_btn.receives_default = false
      replace_btn.tooltip_text = _('Find and replace')
      #replace_btn.show_all

      replace_btn.safe_signal_clicked do |widget|
        #replace_btn.icon_widget = nil
        if replace_btn.active?
          replace_btn.icon_widget = @replace_image
          #replace_btn.show_all
          if not @replace_hbox
            @replace_hbox = Gtk::HBox.new
            replace_label = Gtk::Label.new(_('Replace by'))
            @replace_hbox.pack_start(replace_label, false, false, 2)

            @replace_entry = Gtk::Entry.new
            replace_entry.max_length = 512
            replace_entry.signal_connect('key-press-event') do |widget, event|
              res = false
              if (event.keyval==Gdk::Keyval::GDK_Tab) or (event.keyval==65362)
                @entry.grab_focus
                res = true
              end
              res
            end

            @replace_hbox.pack_start(replace_entry, true, true, 0)
            #@replace_hbox.show_all
            replace_all_btn = SafeToggleToolButton.new
            replace_all_btn.icon_widget = all_image
            replace_all_btn.can_focus = false
            replace_all_btn.can_default = false
            replace_all_btn.tooltip_text = _('Replace all')
            @replace_hbox.pack_start(replace_all_btn, false, false, 2)
            find_vbox.pack_start(@replace_hbox, false, false, 2)
            find_vbox.show_all
            #@find_panel.show_all
            popwin.focus_chain = [entry, replace_entry]
          end
          #@replace_hbox.show_all
          find_vbox.show_all
          @replace_entry.grab_focus
        else
          replace_btn.icon_widget = @find_image
          #replace_btn.show_all
          @replace_hbox.hide if @replace_hbox
          @entry.grab_focus
        end
        #replace_btn.set_reallocate_redraws(true)
        replace_btn.show_all
        pwh = find_vbox.size_request
        #pwh[1] = 200
        self.resize(*pwh)
        #@find_panel.present
        false
      end

      @back_btn = Gtk::ToolButton.new(back_image, _('Back'))
      #back_btn = Gtk::Button.new
      #back_btn.add(back_image)
      back_btn.can_focus = false
      back_btn.sensitive = false
      back_btn.can_default = false
      back_btn.receives_default = false
      back_btn.tooltip_text = _('Back')
      back_btn.signal_connect('clicked') do |widget|
        self.move_to_find_pos(-1)
        false
      end

      @forward_btn = Gtk::ToolButton.new(forward_image, _('Forward'))
      #forward_btn = Gtk::Button.new
      #forward_btn.add(forward_image)
      forward_btn.can_focus = false
      forward_btn.sensitive = false
      forward_btn.can_default = false
      forward_btn.receives_default = false
      forward_btn.tooltip_text = _('Forward')
      forward_btn.signal_connect('clicked') do |widget|
        self.move_to_find_pos(1)
        false
      end

      @casesens_btn = SafeToggleToolButton.new
      casesens_btn.icon_widget = @case_image
      casesens_btn.can_focus = false
      casesens_btn.can_default = false
      casesens_btn.receives_default = false
      casesens_btn.tooltip_text = _('Case sensitive')
      casesens_btn.active = true
      casesens_btn.safe_signal_clicked do |widget|
        self.find_text
        false
      end

      close_btn = Gtk::ToolButton.new(close_image, _('Close'))
      close_btn.can_focus = false
      close_btn.can_default = false
      close_btn.receives_default = false
      close_btn.tooltip_text = _('Close')
      close_btn.signal_connect('clicked') do |widget|
        #@find_panel.destroy
        #@find_panel = nil
        self.hide
        false
      end

      @count_label = Gtk::Label.new('')
      count_label.width_request = PandoraGtk.num_char_width*8+8

      hbox.pack_start(back_btn, false, false, 0)
      hbox.pack_start(entry, false, false, 0)
      hbox.pack_start(forward_btn, false, false, 0)
      hbox.pack_start(count_label, false, false, 0)
      hbox.pack_start(casesens_btn, false, false, 0)
      hbox.pack_start(replace_btn, false, false, 0)

      hbox.pack_start(close_btn, false, false, 2)

      popwin.signal_connect('delete_event') { @popwin.destroy; @popwin=nil }

      popwin.signal_connect('focus-out-event') do |win, event|
        GLib::Timeout.add(200) do
          win = nil if (win and win.destroyed?)
          if win and win.treeview.destroyed?
            win.destroy
            win = nil
          end
          if win and (not (win.treeview.has_focus? or win.active?))
            win.hide
          end
          continue = (win and (not win.active?) and win.visible?)
          continue
        end
        false
      end

      self.signal_connect('key-press-event') do |widget, event|
        res = false
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          self.move_to_find_pos(2)
        elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          widget.hide
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          widget.destroy
          PandoraUI.do_menu_act('Quit')
        elsif event.state.control_mask?
          case event.keyval
            when Gdk::Keyval::GDK_f, Gdk::Keyval::GDK_F, 1729, 1761
              #show_hide_find_panel(false, false)
              show_and_set_replace_mode(false)
              res = true
            when Gdk::Keyval::GDK_h, Gdk::Keyval::GDK_H, 1746, 1778
              #show_hide_find_panel(true, false)
              show_and_set_replace_mode(nil)
              res = true
            when Gdk::Keyval::GDK_g, Gdk::Keyval::GDK_G, 1744, 1776
              self.hide
              @treeview.show_line_panel
              res = true
            else
              p event.keyval
          end
        end
        res
      end

      self.signal_connect('scroll-event') do |widget, event|
        ctrl = (event.state.control_mask? or event.state.shift_mask?)
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          if ctrl
            left_year_btn.clicked
          else
            left_mon_btn.clicked
          end
        else
          if ctrl
            right_year_btn.clicked
          else
            right_mon_btn.clicked
          end
        end
        true
      end

      self.signal_connect('hide') do |widget|
        if @treeview and (not @treeview.destroyed?)
          buf = @treeview.buffer
          if buf and (not buf.destroyed?)
            buf.remove_tag('found', buf.start_iter, buf.end_iter)
            buf.remove_tag('find', buf.start_iter, buf.end_iter)
          end
        end
        false
      end

      popwin.add(find_vbox)

      find_vbox.pack_start(hbox, false, false, 0)
      find_vbox.show_all

      @entry.grab_focus
      show_and_set_replace_mode(areplace)
    end

    def show_and_set_replace_mode(areplace=nil)
      #areplace = areplace.is_a?(TrueClass)
      #replace_btn.safe_set_active(replace)
      #self.activate_focus

      pos = @treeview.window.origin
      all = @treeview.allocation.to_a

      awidth, aheight = @find_vbox.size_request
      self.move(pos[0]+all[2]-awidth-24, pos[1])  #all[3]+1

      areplace = (not @replace_btn.active?) if areplace.nil?

      @replace_btn.active = areplace

      if (@entry and (not @entry.destroyed?))
        self.find_text(true)
        @entry.select_region(0, @entry.text.size) if @entry.text.size>0
      end

      self.show if (not self.visible?)

      self.present
    end

    MaxFindPos = 300

    def find_text(dont_move=false, slow=false)
      @find_pos = 0
      @find_len = 0
      @max_pos = 0
      @max_line = nil
      @find_line = nil
      if @entry and @treeview and @treeview.buffer
        atext = @entry.text
        buf = @treeview.buffer
        if atext.is_a?(String) and (atext.size>0)
          Thread.new(@search_thread) do |prev_thread|
            @search_thread = Thread.current
            $window.mutex.synchronize do
              if prev_thread and prev_thread.alive?
                prev_thread.kill
              end
              prev_thread = nil
            end
            #@count_label.text = 'start'
            buf.remove_tag('found', buf.start_iter, buf.end_iter)
            buf.remove_tag('find', buf.start_iter, buf.end_iter)
            @positions ||= Array.new
            sleep_time = 0.1
            if slow
              if atext.size==1
                sleep_time = 3
              elsif atext.size==2
                sleep_time = 2
              else
                sleep_time = 1
              end
            elsif dont_move
              sleep_time = 1
            end
            sleep(sleep_time)
            @max_pos = PandoraUtils.find_all_substr(@treeview.buffer.text, \
              atext, @positions, MaxFindPos, @casesens_btn.active?)
            #@count_label.text = 'start2'
            if @max_pos>0
              #@count_label.text = 'start3'
              #@find_pos = max-1 if @find_pos>max-1
              @find_len = atext.size
              cur_pos = buf.cursor_position
              @find_pos = -1
              i = 0
              #@count_label.text = 'start4'
              while i<@max_pos
                pos = @positions[i]
                if cur_pos and (cur_pos>pos)
                  @find_pos = i
                end
                iter = buf.get_iter_at_offset(pos)
                iter2 = buf.get_iter_at_offset(pos+@find_len)
                buf.apply_tag('found', iter, iter2)
                i += 1
              end
              @find_pos += 1
              if dont_move or (@find_pos<0) or (@find_pos>=@max_pos)
                #@count_label.text = 'st5 '+@find_pos.inspect
                @count_label.text = '['+(@find_pos+1).to_s+']/'+@max_pos.to_s
                @back_btn.sensitive = @find_pos>0 if @back_btn
                @forward_btn.sensitive = (@find_pos<@max_pos) if @forward_btn
                @find_pos = -(@find_pos+1)
              else
                #@count_label.text = 'st6 '+@find_pos.inspect+'|'+@max_pos.inspect
                #@count_label.text = (@find_pos+1).to_s+'/'+@max_pos.to_s
                move_to_find_pos(0)
              end
            else
              @count_label.text = '0'
            end
            @search_thread = nil
          end
        else
          @count_label.text = ''
          @back_btn.sensitive = false if @back_btn
          @forward_btn.sensitive = false if @forward_btn
          buf.remove_tag('found', buf.start_iter, buf.end_iter)
          buf.remove_tag('find', buf.start_iter, buf.end_iter)
        end
      end
    end

    def has_line_found?(aline)
      res = nil
      i = 0
      if (not @max_line) and @treeview and @positions \
      and @max_pos and (@max_pos>0)
        buf = @treeview.buffer
        @found_lines ||= Array.new
        @max_line = 0
        while i<@max_pos do
          pos = @positions[i]
          if pos
            iter = buf.get_iter_at_offset(pos)
            if iter
              iline = iter.line
              if (not has_line_found?(iline))
                @found_lines[@max_line] = iline
                @max_line += 1
              end
            end
          end
          i += 1
        end
        i = 0
      end
      if @found_lines and @max_line and aline
        while (not res) and (i<@max_line)
          res = (@found_lines[i] == aline)
          i += 1
        end
      end
      res
    end

    def move_to_find_pos(direction=nil)
      if @positions and @find_len and (@find_len>0) \
      and @find_pos and @max_pos and (@max_pos>0)
        if @find_pos<0
          new_pos = -(@find_pos+1)
          new_pos -= 1 if (direction<0)
          @find_pos = new_pos if (new_pos>=0) and (new_pos<@max_pos)
        else
          direction ||= 0
          if direction>0
            if @find_pos<@max_pos-1
              @find_pos += 1
            elsif (direction==2)
              @find_pos = 0
            end
          elsif direction<0
            if @find_pos>0
              @find_pos -= 1
            elsif (direction==-2)
              @find_pos = @max_pos-1
            end
          end
        end
        if (@find_pos>=0) and (@find_pos<@max_pos)
          @count_label.text = (@find_pos+1).to_s+'/'+@max_pos.to_s

          @back_btn.sensitive = @find_pos>0 if @back_btn
          @forward_btn.sensitive = (@find_pos<@max_pos-1) if @forward_btn

          pos = @positions[@find_pos]
          if pos
            buf = @treeview.buffer
            buf.remove_tag('find', buf.start_iter, buf.end_iter)
            iter = buf.get_iter_at_offset(pos)
            if iter
              @find_line = iter.line
              iter2 = buf.get_iter_at_offset(pos+@find_len)
              @treeview.scroll_to_iter(iter, 0.1, false, 0.0, 0.0)
              buf.place_cursor(iter)
              #buf.move_mark('selection_bound', iter2)
              buf.apply_tag('find', iter, iter2)
            end
          end
        end
      end
    end

  end


  class LinePanel < Gtk::Window
    attr_accessor :treeview, :entry, :find_line

    def initialize(atreeview, amodal=false)
      super()
      @treeview = atreeview
      self.transient_for = $window #if win_os
      self.modal = amodal #(not win_os)
      self.decorated = false
      self.skip_taskbar_hint = true
      self.destroy_with_parent = true

      @entry = IntegerEntry.new

      awidth = 50
      #p '---LinePanel: atreeview.scale_width='+atreeview.scale_width.inspect
      awidth = atreeview.scale_width-2 if (atreeview.scale_width and (atreeview.scale_width>30))
      entry.width_request = awidth
      entry.max_length = atreeview.scale_width_in_char
      #entry.set_size_request(awidth, -1)
      entry.show_all
      #btn_width, btn_height = entry.size_request
      #self.set_default_size(awidth+4, btn_height+4)
      #self.resize(awidth+4, btn_height+4)
      #entry = Gtk::Combo.new  #Gtk::Entry.new
      #entry.set_popdown_strings(['word1', 'word2'])
      #entry.signal_connect('changed') do |widget, event|
      #  self.goto_line
      #  false
      #end
      entry.signal_connect('key-press-event') do |widget, event|
        res = false
        if (event.keyval==Gdk::Keyval::GDK_Tab)
          self.goto_line
          res = true
        elsif (event.keyval>=65360) and (event.keyval<=65367)
          if event.keyval==65365 or event.keyval==65362 #PgUp, Up
            self.goto_line
            res = true
          elsif (event.keyval==65366) or (event.keyval==65364) #PgDn, Down
            self.goto_line
            res = true
          end
        end
        res
      end

      self.signal_connect('delete_event') { @self.destroy }

      self.signal_connect('focus-out-event') do |win, event|
        GLib::Timeout.add(100) do
          win = nil if (win and win.destroyed?)
          if win and win.treeview.destroyed?
            win.destroy
            win = nil
          end
          win.hide if win
          false
        end
        false
      end

      self.signal_connect('key-press-event') do |widget, event|
        res = false
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          self.goto_line
        elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          widget.hide
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          widget.destroy
          PandoraUI.do_menu_act('Quit')
        elsif event.state.control_mask?
          case event.keyval
            when Gdk::Keyval::GDK_f, Gdk::Keyval::GDK_F, 1729, 1761
              self.hide
              @treeview.show_hide_find_panel(false, false)
              res = true
            when Gdk::Keyval::GDK_h, Gdk::Keyval::GDK_H, 1746, 1778
              self.hide
              @treeview.show_hide_find_panel(true, false)
              res = true
          end
        end
        res
      end

      self.signal_connect('scroll-event') do |widget, event|
        ctrl = (event.state.control_mask? or event.state.shift_mask?)
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          if ctrl
            left_year_btn.clicked
          else
            left_mon_btn.clicked
          end
        else
          if ctrl
            right_year_btn.clicked
          else
            right_mon_btn.clicked
          end
        end
        true
      end

      self.add(entry)

      @entry.grab_focus
      show_and_move
    end

    def show_and_move
      pos = @treeview.window.origin
      all = @treeview.allocation.to_a

      awidth, aheight = @entry.size_request
      self.move(pos[0], pos[1]+all[3]*0.33-aheight/2+2)

      #if (@entry and (not @entry.destroyed?))
      #  self.goto_line
      #end

      self.show if (not self.visible?)

      self.present
      @entry.grab_focus
    end

    def goto_line
      @line_pos = nil
      if @entry and @treeview and @treeview.buffer
        atext = @entry.text
        if atext.size>0
          line = atext.to_i
          if line >= 0
            line -= 1
            line = 0 if line<0
            buf = @treeview.buffer
            line = buf.line_count-1 if (line>=buf.line_count)
            @entry.text = (line+1).to_s
            iter = buf.get_iter_at_line(line)
            if iter
              @treeview.scroll_to_iter(iter, 0.0, true, 0.0, 0.33)
              buf.place_cursor(iter)
              self.hide
            end
          end
        end
      end
    end

  end


  $font_desc = nil

  # Window for view body (text or blob)
  # RU: Окно просмотра тела (текста или блоба)
  class SuperTextView < ExtTextView
    attr_accessor :find_panel, :numbers, :pixels

    def format
      res = nil
      sw = parent
      if (sw.is_a? BodyScrolledWindow)
        res = sw.format
      end
      res ||= 'bbcode'
      res
    end

    def initialize(left_border=nil, *args)
      super(*args)
      self.wrap_mode = Gtk::TextTag::WRAP_WORD

      @numbers = Array.new
      @pixels = Array.new

      @hovering = false

      set_border_window_size(Gtk::TextView::WINDOW_LEFT, left_border) if left_border

      buf = self.buffer
      buf.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      buf.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
      buf.create_tag('strike', 'strikethrough' => true)
      buf.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
      buf.create_tag('link', 'foreground' => '#000099', \
        'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('linked', 'foreground' => 'navy', \
        'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('left', 'justification' => Gtk::JUSTIFY_LEFT)
      buf.create_tag('center', 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('right', 'justification' => Gtk::JUSTIFY_RIGHT)
      buf.create_tag('fill', 'justification' => Gtk::JUSTIFY_FILL)
      buf.create_tag('h1', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 24 * Pango::SCALE, 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('h2', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 21 * Pango::SCALE, 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('h3', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 18 * Pango::SCALE)
      buf.create_tag('h4', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 15 * Pango::SCALE)
      buf.create_tag('h5', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'style' => Pango::FontDescription::STYLE_ITALIC, 'size' => 12 * Pango::SCALE)
      buf.create_tag('h6', 'style' => Pango::FontDescription::STYLE_ITALIC, \
        'size' => 12 * Pango::SCALE)
      buf.create_tag('red', 'foreground' => 'red')
      buf.create_tag('green', 'foreground' => 'green')
      buf.create_tag('blue', 'foreground' => 'blue')
      buf.create_tag('navy', 'foreground' => 'navy')
      buf.create_tag('yellow', 'foreground' => 'yellow')
      buf.create_tag('magenta', 'foreground' => 'magenta')
      buf.create_tag('cyan', 'foreground' => 'cyan')
      buf.create_tag('lime', 'foreground' =>   '#00FF00')
      buf.create_tag('maroon', 'foreground' => 'maroon')
      buf.create_tag('olive', 'foreground' =>  '#808000')
      buf.create_tag('purple', 'foreground' => 'purple')
      buf.create_tag('teal', 'foreground' =>   '#008080')
      buf.create_tag('gray', 'foreground' => 'gray')
      buf.create_tag('silver', 'foreground' =>   '#C0C0C0')
      buf.create_tag('mono', 'family' => 'monospace', 'background' => '#EFEFEF')
      buf.create_tag('sup', 'rise' => 7 * Pango::SCALE, 'size' => 9 * Pango::SCALE)
      buf.create_tag('sub', 'rise' => -7 * Pango::SCALE, 'size' => 9 * Pango::SCALE)
      buf.create_tag('small', 'scale' => Pango::AttrScale::SMALL)
      buf.create_tag('large', 'scale' => Pango::AttrScale::LARGE)
      buf.create_tag('quote', 'left_margin' => 20, 'background' => '#EFEFEF', \
        'style' => Pango::FontDescription::STYLE_ITALIC)

      buf.create_tag('found', 'background' =>  '#FFFF00')
      buf.create_tag('find', 'background' =>   '#FF9000')

      signal_connect('key-press-event') do |widget, event|
        res = false
        if event.state.control_mask?
          case event.keyval
            when Gdk::Keyval::GDK_b, Gdk::Keyval::GDK_B, 1737, 1769
              set_tag('bold')
              res = true
            when Gdk::Keyval::GDK_i, Gdk::Keyval::GDK_I, 1755, 1787
              set_tag('italic')
              res = true
            when Gdk::Keyval::GDK_u, Gdk::Keyval::GDK_U, 1735, 1767
              set_tag('undline')
              res = true
            when Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter
              res = true
            when Gdk::Keyval::GDK_f, Gdk::Keyval::GDK_F, 1729, 1761
              show_hide_find_panel(false, false)
              res = true
            when Gdk::Keyval::GDK_h, Gdk::Keyval::GDK_H, 1746, 1778
              show_hide_find_panel(true, false)
              res = true
            #when Gdk::Keyval::GDK_l, Gdk::Keyval::GDK_L, 1736, 1768
            when Gdk::Keyval::GDK_g, Gdk::Keyval::GDK_G, 1744, 1776
              show_line_panel
              res = true
            when Gdk::Keyval::GDK_c, Gdk::Keyval::GDK_C, 1747, 1779
              self.copy_clipboard
              res = true
            when Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790
              self.cut_clipboard
              res = true
            when Gdk::Keyval::GDK_v, Gdk::Keyval::GDK_V, 1741, 1773
              self.paste_clipboard
              res = true
            when Gdk::Keyval::GDK_a, Gdk::Keyval::GDK_A, 1734, 1766
              self.select_all(true)
              res = true
            when Gdk::Keyval::GDK_s, Gdk::Keyval::GDK_S, 1753, 1785
              sw = self.scrollwin
              #p [sw, sw.property_box, sw.property_box.save_btn]
              if sw and sw.is_a?(BodyScrolledWindow) and sw.property_box and sw.property_box.save_btn
                sbtn = sw.property_box.save_btn
                sbtn.clicked if sbtn.sensitive?
                res = true
              end
            when Gdk::Keyval::GDK_z, Gdk::Keyval::GDK_Z, 1745, 1777
              self.do_undo
              res = true
            when Gdk::Keyval::GDK_y, Gdk::Keyval::GDK_Y, 1742, 1774
              self.do_redo
              res = true
            #else
            #  p event.keyval
          end
        elsif (event.keyval==Gdk::Keyval::GDK_Escape)
          @find_panel.hide if (@find_panel and (not @find_panel.destroyed?))
        end
        res
      end

      signal_connect('button-press-event') do |widget, event|
        res = false
        if event.window == self.get_window(Gtk::TextView::WINDOW_LEFT)
          left_bor = self.get_border_window_size(Gtk::TextView::WINDOW_LEFT)
          if (event.button == 1) and (event.x < left_bor)
            show_line_panel
            res = true
          end
        end
        res
      end

      signal_connect('event-after') do |tv, event|
        if event.kind_of?(Gdk::EventButton) \
        and (event.event_type == Gdk::Event::BUTTON_PRESS) and (event.button == 1)
          buf = tv.buffer
          # we shouldn't follow a link if the user has selected something
          range = buf.selection_bounds
          if range and (range[0].offset == range[1].offset)
            x, y = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, \
              event.x, event.y)
            iter = tv.get_iter_at_location(x, y)
            follow_if_link(iter)
          end
        end
        false
      end

      signal_connect('motion-notify-event') do |tv, event|
        x, y = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, \
          event.x, event.y)
        set_cursor_if_appropriate(tv, x, y)
        tv.window.pointer
        false
      end

      signal_connect('visibility-notify-event') do |tv, event|
        window, wx, wy = tv.window.pointer
        bx, by = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, wx, wy)
        set_cursor_if_appropriate(tv, bx, by)
        false
      end

      self.has_tooltip = true
      signal_connect('query-tooltip') do |textview, x, y, keyboard_tip, tooltip|
        res = false
        iter = nil
        if keyboard_tip
          iter = textview.buffer.get_iter_at_offset(textview.buffer.cursor_position)
        else
          bx, by = textview.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, x, y)
          left_border = get_border_window_size(Gtk::TextView::WINDOW_LEFT)
          #iter, trailing = textview.get_iter_at_position(bx, by)
          #cent_win = textview.get_window(Gtk::TextView::WINDOW_TEXT)
          iter, trailing = textview.get_iter_at_position(bx-left_border, by)
        end
        pixbuf = iter.pixbuf   #.has_tag?(tag)  .char = 0xFFFC
        if pixbuf.is_a?(Gtk::Image)
          alt = pixbuf.tooltip
          if (alt.is_a? String) and (alt.size>0)
            tooltip.text = alt if ((not textview.destroyed?) and (not tooltip.destroyed?))
            res = true
          end
        else
          tags = iter.tags
          link_tag = tags.find { |tag| tag.is_a?(LinkTag) }
          if link_tag
            tooltip.text = link_tag.link if not textview.destroyed?
            res = true
          end
        end
        res
      end
    end

    def do_undo
    end

    def do_redo
    end

    def scrollwin
      res = self.parent
      res = res.parent if (not res.is_a?(Gtk::ScrolledWindow))
      res
    end

    def set_cursor_if_appropriate(tv, x, y)
      iter = tv.get_iter_at_location(x, y)
      hovering = false
      tags = iter.tags
      tags.each do |tag|
        if tag.is_a? LinkTag
          hovering = true
          break
        end
      end
      if hovering != @hovering
        @hovering = hovering
        window = tv.get_window(Gtk::TextView::WINDOW_TEXT)
        if @hovering
          window.cursor = $window.hand_cursor
        else
          window.cursor = $window.regular_cursor
        end
      end
    end

    def show_line_panel(may_hide=nil)
      @line_panel ||= nil
      @line_panel = nil if (@line_panel and @line_panel.destroyed?)
      if (may_hide and @line_panel and @line_panel.visible?)
        @line_panel.hide
      elsif @scale_width and (@scale_width>0)
        if @line_panel
          @line_panel.show_and_move
        else
          @line_panel = LinePanel.new(self)
        end
      end
      @line_panel
    end

    def show_hide_find_panel(replace=nil, may_hide=nil)
      @find_panel ||= nil
      @find_panel = nil if (@find_panel and @find_panel.destroyed?)
      if (may_hide and @find_panel and @find_panel.visible? \
      and ((replace and @find_panel.replace_btn.active?) \
      or ((not replace) and (not @find_panel.replace_btn.active?))))
        @find_panel.hide
      elsif @find_panel
        @find_panel.show_and_set_replace_mode(replace)
      else
        @find_panel = FindPanel.new(self, replace)
      end
      @find_panel
    end

    def follow_if_link(iter)
      tags = iter.tags
      tags.each do |tag|
        if tag.is_a? LinkTag
          link = tag.link
          if (link.is_a? String) and (link.size>0)
            res = PandoraUtils.parse_url(link, 'http')
            if res
              proto, obj_type, way = res
              if proto and way
                url = proto+'://'+way
                if (proto == 'pandora')
                  panhash = PandoraUtils.hex_to_bytes(way)
                  if not PandoraUtils.panhash_nil?(panhash)
                    PandoraGtk.show_cabinet(panhash, nil, nil, nil, \
                      nil, PandoraUI::CPI_Profile)
                  end
                elsif ((proto == 'sha1') or (proto == 'md5'))
                  puts 'Need do jump to: ['+url+']'
                  #PandoraGtk.internal_open(proto, obj_type, way)
                elsif (proto=='http') or (proto=='https')
                  puts 'Go to link: ['+url+']'
                  PandoraUtils.external_open(url)
                else
                  puts 'Unknown jump: ['+url+']'
                end
              end
            end
          end
        end
      end
    end

    def get_lines(first_y, last_y, with_height=false)
      # Get iter at first y
      iter, top = self.get_line_at_y(first_y)
      line = iter.line
      @numbers.clear
      @pixels.clear
      count = 0
      size = 0
      while (line < self.buffer.line_count)
        #iter = self.buffer.get_iter_at_line(line)
        y, height = self.get_line_yrange(iter)
        if with_height
          @pixels << [y, height]
        else
          @pixels << y
        end
        line += 1
        @numbers << line
        count += 1
        break if (y + height) >= last_y
        iter.forward_line
      end
      count
    end

    BBCODES = ['B', 'I', 'U', 'S', 'EM', 'STRIKE', 'DEL', 'STRONG', 'D', 'BR', \
      'FONT', 'SIZE', 'COLOR', 'COLOUR', 'STYLE', 'BACK', 'BACKGROUND', 'BG', \
      'FORE', 'FOREGROUND', 'FG', 'SPAN', 'DIV', 'UL', 'LI', 'P', \
      'RED', 'GREEN', 'BLUE', 'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', \
      'LIME', 'AQUA', 'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER', \
      'URL', 'A', 'HREF', 'LINK', 'GOTO', 'ANCHOR', 'MARK', 'LABEL', 'QUOTE', \
      'BLOCKQUOTE', 'LIST', 'CUT', 'SPOILER', 'CODE', 'INLINE', \
      'BOX', 'PROPERTY', 'EDIT', 'ENTRY', 'INPUT', \
      'BUTTON', 'SPIN', 'INTEGER', 'HEX', 'REAL', 'FLOAT', 'DATE', \
      'TIME', 'DATETIME', 'COORD', 'FILENAME', 'BASE64', 'PANHASH', 'BYTELIST', \
      'PRE', 'SOURCE', 'MONO', 'MONOSPACE', \
      'IMG', 'IMAGE', 'SMILE', 'EMOT', 'VIDEO', 'AUDIO', 'FILE', 'SUB', 'SUP', \
      'ABBR', 'ACRONYM', 'HR', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', \
      'LEFT', 'CENTER', 'RIGHT', 'FILL', 'IMAGES', 'SLIDE', 'SLIDESHOW', \
      'TABLE', 'TR', 'TD', 'TH', 'TBODY', 'TT', 'DL', 'DD', 'DT', 'SMALL', 'LITTLE', 'LARGE', 'BIG']

    # Insert taget string to buffer
    # RU: Вставить тегированный текст в буфер
    def insert_taged_str_to_buffer(str, dest_buf, aformat=nil)

      def shift_coms(shift)
        @open_coms.each do |ocf|
          ocf[1] += shift
        end
      end

      def remove_quotes(str)
        if str.is_a?(String) and (str.size>1) \
        and ((str[0]=='"' and str[-1]=='"') or (str[0]=="'" and str[-1]=="'"))
          str = str[1..-2]
          str.strip! if str
        end
        str
      end

      def get_tag_param(params, type=:string, return_tail=false)
        res = nil
        getted = nil
        if (params.is_a? String) and (params.size>0)
          ei = params.index('=')
          es = params.index(' ')
          if ei.nil? or (es and es<ei)
            res = params
            res = params[0, es] if ei
            if res
              getted = res.size
              res = res.strip
              res = remove_quotes(res)
              if res and (type==:number)
                begin
                  res.gsub!(/[^0-9\.]/, '')
                  res = res.to_i
                rescue
                  res = nil
                end
              end
            end
          end
        end
        if return_tail
          tail = nil
          if getted
            tail = params[getted..-1]
          else
            tail = params
          end
          res = [res, tail]
        end
        res
      end

      def detect_params(params, tagtype=:string)
        res = {}
        tag, params = get_tag_param(params, tagtype, true)
        res['tag'] = tag if tag
        while (params.is_a? String) and (params.size>0)
          params.strip
          n = nil
          v = nil
          i = params.index('=')
          if i and (i>0)
            n = params[0, i]
            params = params[i+1..-1]
            params.strip if params
            i = params.size
            j = params.index(' ')
            k = params.index('"', 1)
            if (i>0) and (params[0]=='"') and k
              v = params[0..k]
              params = params[k+1..-1]
            elsif j
              v = params[0, j]
              params = params[j+1..-1]
            else
              v = params
              params = ''
            end
          else
            params = ''
          end
          if n
            n = n.strip.downcase
            res[n] = remove_quotes(v.strip) if v and (v.size>0)
          end
        end
        p 'detect_params[params, res]='+[params, res].inspect
        res
      end

      def correct_color(str)
        if str.is_a?(String) and (str.size==6) and PandoraUtils.hex?(str)
          str = '#'+str
        end
        str
      end

      def read_justify_param(param_hash, js=nil)
        js ||= param_hash['js']
        js ||= param_hash['justify']
        js ||= param_hash['justification']
        js ||= param_hash['align']
        js
      end

      def str_justify_to_val(js)
        js_val = nil
        if js.is_a?(String) and (js.size>0)
          js = js[0, 1].upcase
          if js=='L'  #LEFT
            js_val = Gtk::JUSTIFY_LEFT
          elsif js=='R'  #RIGHT
            js_val = Gtk::JUSTIFY_RIGHT
          elsif (js=='C') or (js=='M')  #CENTER or MIDDLE
            js_val = Gtk::JUSTIFY_CENTER
          elsif js=='F'  #FULL
            js_val = Gtk::JUSTIFY_FILL
          end
        end
        js_val
      end

      def generate_tag(param_hash, comu=nil, tag_name=nil, tag_params=nil)
        tag_name ||= ''
        tag_params ||= {}

        fg = nil #blue, #1122FF
        bg = nil #yellow
        sz = nil #12, 14
        js = nil #left, right...
        fam = nil #arial
        wt = nil #bold
        st = nil #italic...
        und = nil  #single, double
        strike = nil

        if (not comu.nil?)
          case comu
            when 'FG', 'FORE', 'FOREGROUND', 'COLOR', 'COLOUR'
              fg = param_hash['tag']
            when 'BG', 'BACK', 'BACKGROUND'
              bg = param_hash['tag']
            when 'B', 'STRONG'
              wt = Pango::FontDescription::WEIGHT_BOLD
            when 'I', 'EM'
              st = Pango::FontDescription::STYLE_ITALIC
            when 'S', 'STRIKE', 'DEL'
              strike = true
            when 'U'
              und = Pango::AttrUnderline::SINGLE
            when 'D'
              und = Pango::AttrUnderline::DOUBLE
            when 'CODE', 'INLINE', 'PRE', 'SOURCE', 'MONO', 'MONOSPACE', 'SPAN', 'UL', 'LI'
              tag_params['family'] = 'monospace'
              tag_params['background'] = '#EFEFEF'
            else
              sz = param_hash['tag']
            #end-case-when
          end
        end

        sz ||= param_hash['size']
        sz ||= param_hash['sz']
        fg ||= param_hash['color']
        fg ||= param_hash['colour']
        fg ||= param_hash['fg']
        fg ||= param_hash['fore']
        fg ||= param_hash['foreground']
        bg ||= param_hash['bg']
        bg ||= param_hash['back']
        bg ||= param_hash['background']
        js = read_justify_param(param_hash, js)
        fam ||= param_hash['fam']
        fam ||= param_hash['family']
        fam ||= param_hash['font']
        fam ||= param_hash['name']
        wt ||= param_hash['wt']
        wt ||= param_hash['weight']
        wt ||= param_hash['width']
        wt ||= param_hash['bold']
        st ||= param_hash['st']
        st ||= param_hash['style']
        st ||= param_hash['italic']
        strike ||= param_hash['strike']
        strike ||= param_hash['del']
        strike ||= param_hash['deleted']
        und ||= param_hash['underline']

        fg = correct_color(fg)
        bg = correct_color(bg)

        if fam and (fam.is_a? String) and (fam.size>0)
          fam_st = fam.upcase
          fam_st.gsub!(' ', '_')
          tag_name << '_'+fam_st
          tag_params['family'] = fam
        end
        if fg
          tag_name << '_'+fg
          tag_params['foreground'] = fg
        end
        if bg
          tag_name << '_bg'+bg
          tag_params['background'] = bg
        end
        if sz
          sz.gsub!(/[^0-9\.]/, '') if sz.is_a? String
          tag_name << '_sz'+sz.to_s
          tag_params['size'] = sz.to_i * Pango::SCALE
        end
        if wt
          tag_name << '_wt'+wt.to_s
          tag_params['weight'] = wt.to_i
        end
        if st
          tag_name << '_st'+st.to_s
          tag_params['style'] = st.to_i
        end
        if strike
          tag_name << '_st'
          tag_params['strikethrough'] = true
        end
        if und
          tag_name << '_'+und.to_s
          tag_params['underline'] = und.to_i
        end
        js_val = str_justify_to_val(js)
        if js and js_val
          tag_name << '_js'+js
          tag_params['justification'] = js_val
        end
        [tag_name, tag_params]
      end

      i = children.size
      while i>0
        i -= 1
        child = children[i]
        child.destroy if child and (not child.destroyed?)
      end

      aformat ||= 'bbcode'
      if not ['markdown', 'bbcode', 'html', 'ruby', 'python', 'plain', 'xml', 'ini'].include?(aformat)
        aformat = 'bbcode' #if aformat=='auto' #need autodetect here
      end
      #p 'str='+str
      case aformat
        when 'markdown'
          i = 0
          while i<str.size
            j = str.index('*')
            if j
              dest_buf.insert(dest_buf.end_iter, str[0, j])
              str = str[j+1..-1]
              j = str.index('*')
              if j
                tag_name = str[0..j-1]
                img_buf = $window.get_icon_buf(tag_name)
                dest_buf.insert(dest_buf.end_iter, img_buf) if img_buf
                str = str[j+1..-1]
              end
            else
              dest_buf.insert(dest_buf.end_iter, str)
              i = str.size
            end
          end
        when 'bbcode', 'html'
          open_coms = Array.new
          @open_coms = open_coms
          open_brek = '['
          close_brek = ']'
          if (aformat=='html')
            open_brek = '<'
            close_brek = '>'
          end
          strict_close_tag = nil
          i1 = nil
          i = 0
          ss = str.size
          while i<ss
            c = str[i]
            if c==open_brek
              i1 = i
              i += 1
            elsif i1 and (c==close_brek)
              com = str[i1+1, i-i1-1]
              p 'bbcode com='+com
              if com and (com.size>0)
                comu = nil
                close = (com[0] == '/')
                show_text = true
                if close or (com[-1] == '/')
                  # -- close bbcode
                  params = nil
                  tv_tag = nil
                  if close
                    comu = com[1..-1]
                  else
                    com = com[0..-2]
                    j = 0
                    cs = com.size
                    j +=1 while (j<cs) and (not ' ='.index(com[j]))
                    comu = nil
                    params = nil
                    if (j<cs)
                      params = com[j+1..-1].strip
                      comu = com[0, j]
                    else
                      comu = com
                    end
                  end
                  comu = comu.strip.upcase if comu
                  p '===closetag  [comu,params]='+[comu,params].inspect
                  p '---open_coms='+open_coms.inspect
                  p1 = dest_buf.end_iter.offset
                  p2 = p1
                  if ((strict_close_tag.nil? and BBCODES.include?(comu)) \
                  or ((not strict_close_tag.nil?) and (comu==strict_close_tag)))
                    strict_close_tag = nil
                    k = open_coms.index{ |ocf| ocf[0]==comu }
                    #p '--111---k='+k.inspect
                    if k or (not close)
                      if k
                        rec = open_coms[k]
                        open_coms.delete_at(k)
                        k = rec[1]
                        params = rec[2]
                      else
                        k = 0
                      end
                      #p '--222---comu,params='+[comu,params].inspect
                      #p '[comu, dest_buf.text]='+[comu, dest_buf.text].inspect
                      p1 -= k
                      case comu
                        when 'BR', 'P'
                          dest_buf.insert(dest_buf.end_iter, "\n")
                          shift_coms(1)
                        when 'URL', 'A', 'HREF', 'LINK', 'GOTO'
                          tv_tag = 'link'
                          link_text = str[0, i1]
                          link_url = nil
                          if params and (params.size>0)
                            param_hash = detect_params(params)
                            link_url = param_hash['tag']
                            link_url ||= param_hash['href']
                            link_url ||= param_hash['url']
                            link_url ||= param_hash['src']
                            link_url ||= param_hash['link']

                            tag_name, tag_params = generate_tag(param_hash)
                            p 'LINK [tag_name, tag_params]='+[tag_name, tag_params].inspect
                          end
                          link_url = link_text if not (link_url and (link_url.size>0))
                          if link_url and (link_url.size>0)
                            trunc_md5 = Digest::MD5.digest(link_url)[0, 10]
                            link_id = 'link'+PandoraUtils.bytes_to_hex(trunc_md5)+tag_name
                            link_tag = dest_buf.tag_table.lookup(link_id)
                            #p '--[link_id, link_tag, params]='+[link_id, link_tag, params].inspect
                            if link_tag
                              tv_tag = link_tag.name
                            else
                              link_tag = LinkTag.new(link_id)
                              if link_tag
                                dest_buf.tag_table.add(link_tag)
                                link_tag.foreground = '#000099'
                                #link_tag.underline = Pango::AttrUnderline::SINGLE
                                link_tag.link = link_url
                                if tag_params.size>0
                                  PandoraGtk.apply_properties_to_glib_object(tag_params, link_tag)
                                end
                                tv_tag = link_id
                              end
                            end
                          end
                        when 'ANCHOR', 'MARK', 'LABEL'
                          tv_tag = nil
                          params = str[0, i1] unless params and (params.size>0)
                          if params and (params.size>0)
                            lab_name = get_tag_param(params)
                            if not lab_name.nil?
                              iter = dest_buf.end_iter
                              anchor = dest_buf.create_child_anchor(iter)
                              @labels ||= Hash.new
                              @labels[lab_name] = anchor
                            end
                          end
                        when 'QUOTE', 'BLOCKQUOTE'
                          tv_tag = 'quote'
                        when 'LIST'
                          tv_tag = 'quote'
                        when 'CUT', 'SPOILER'
                          capt = params
                          capt ||= _('Expand')
                          expander = Gtk::Expander.new(capt)
                          etv = Gtk::TextView.new
                          etv.buffer.text = str[0, i1]
                          show_text = false
                          expander.add(etv)
                          iter = dest_buf.end_iter
                          anchor = dest_buf.create_child_anchor(iter)
                          #p 'CUT [body_child, expander, anchor]='+
                          #  [body_child, expander, anchor].inspect
                          add_child_at_anchor(expander, anchor)
                          shift_coms(1)
                          expander.show_all
                        when 'IMG', 'IMAGE', 'SMILE', 'EMOT'
                          img_text = str[0, i1]
                          img_url = nil
                          js_val = nil
                          tag_params = nil
                          if params and (params.size>0)
                            param_hash = detect_params(params)
                            img_url = param_hash['tag']
                            img_url ||= param_hash['href']
                            img_url ||= param_hash['url']
                            img_url ||= param_hash['src']
                            img_url ||= param_hash['link']
                            js = read_justify_param(param_hash)
                            tv_tag = js.downcase if js
                          end
                          img_url = img_text if not (img_url and (img_url.size>0))
                          if img_url and (img_url.size>0)
                            img_buf = $window.get_icon_buf(img_url)
                            if img_buf
                              show_text = false
                              dest_buf.insert(dest_buf.end_iter, img_buf, tv_tag)
                              shift_coms(1)
                            end
                          end
                        when 'B', 'STRONG', 'I', 'EM', 'S', 'U', 'D', 'CODE', \
                        'INLINE', 'PRE', 'SOURCE', 'MONO', 'MONOSPACE', 'SPAN', \
                        'DIV', 'UL', 'LI', \
                        'FONT', 'STYLE', 'SIZE', \
                        'FG', 'FORE', 'FOREGROUND', 'COLOR', 'COLOUR', \
                        'BG', 'BACK', 'BACKGROUND', \
                        'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'LEFT', 'CENTER', \
                        'RIGHT', 'FILL', 'SUB', 'SUP', 'RED', 'GREEN', 'BLUE', \
                        'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', 'LIME', 'AQUA', \
                        'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER', \
                        'SMALL', 'LITTLE', 'LARGE', 'BIG'
                          #p '--FONT-TAGS START!!! [comu, params]='+[comu, params].inspect
                          if (params.nil? or (params.size==0))
                            case comu
                              when 'B', 'STRONG'
                                tv_tag = 'bold'
                              when 'I', 'EM'
                                tv_tag = 'italic'
                              when 'S', 'STRIKE', 'DEL'
                                tv_tag = 'strike'
                              when 'U'
                                tv_tag = 'undline'
                              when 'D'
                                tv_tag = 'dundline'
                              when 'SMALL', 'LITTLE'
                                tv_tag = 'small'
                              when 'LARGE', 'BIG'
                                tv_tag = 'large'
                              when 'CODE', 'INLINE', 'PRE', 'SOURCE', 'MONO', 'MONOSPACE', 'SPAN', 'UL', 'LI'
                                tv_tag = 'mono'
                              when 'DIV'
                                tv_tag = nil
                              else
                                comu = 'CYAN' if comu=='AQUA'
                                tv_tag = comu.downcase
                            end
                          else
                            param_hash = detect_params(params)
                            tag_name, tag_params = generate_tag(param_hash, comu, 'text')
                            p '--FONT-TAGS [tag_name, tag_params]='+[tag_name, tag_params].inspect
                            case comu
                              when 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'LEFT', 'CENTER', \
                              'RIGHT', 'FILL', 'SUB', 'SUP', 'RED', 'GREEN', 'BLUE', \
                              'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', 'LIME', 'AQUA', \
                              'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER', \
                              'SMALL', 'LITTLE', 'LARGE', 'BIG'
                                comu = 'CYAN' if comu=='AQUA'
                                tv_tag = comu.downcase
                                text_tag = dest_buf.tag_table.lookup(tv_tag)
                                if text_tag
                                  if tag_params.size>0
                                    cur_name = tv_tag+'_'+tag_name
                                    text_tag2 = dest_buf.tag_table.lookup(cur_name)
                                    if text_tag2
                                      tv_tag = cur_name
                                    else
                                      PandoraGtk.apply_properties_to_glib_object(tag_params, text_tag)
                                      if dest_buf.create_tag(cur_name, tag_params)
                                        text_tag2 = dest_buf.tag_table.lookup(cur_name)
                                        if text_tag2
                                          PandoraGtk.copy_glib_object_properties(text_tag, text_tag2)
                                          tv_tag = cur_name
                                        end
                                      end
                                    end
                                  end
                                else
                                  tv_tag = nil
                                end
                              else
                                p '===FONT  tag_params='+tag_params.inspect
                                text_tag = dest_buf.tag_table.lookup(tag_name)
                                if text_tag
                                  tv_tag = text_tag.name
                                elsif tag_params.size > 0
                                  if dest_buf.create_tag(tag_name, tag_params)
                                    tv_tag = tag_name
                                  end
                                end
                            end
                          end
                        when 'TABLE', 'TR', 'TD', 'TH', 'TBODY', 'TT', 'DL', 'DD', 'DT'
                          tv_tag = 'mono'
                        when 'IMAGES', 'SLIDE', 'SLIDESHOW'
                          tv_tag = nil
                        when 'VIDEO', 'AUDIO', 'FILE', 'IMAGES', 'SLIDE', 'SLIDESHOW'
                          tv_tag = nil
                        when 'ABBR', 'ACRONYM'
                          tv_tag = nil
                        when 'HR'
                          count = get_tag_param(params, :number)
                          count = 50 unless count.is_a? Numeric and (count>0)
                          dest_buf.insert(dest_buf.end_iter, ' '*count)
                          shift_coms(count)
                          p2 += count
                          tv_tag = 'undline'
                        #end-case-when
                      end
                    else
                      comu = nil
                    end
                  else
                    p 'NO process'
                    comu = nil
                  end
                  if show_text
                    dest_buf.insert(dest_buf.end_iter, str[0, i1])
                    shift_coms(i1)
                    p2 += i1
                  end
                  if tv_tag
                    p 'apply_tag [tv_tag,p1,p2]='+[tv_tag,p1,p2].inspect
                    dest_buf.apply_tag(tv_tag, \
                      dest_buf.get_iter_at_offset(p1), \
                      dest_buf.get_iter_at_offset(p2))
                  end
                else
                  # -- open bbcode
                  dest_buf.insert(dest_buf.end_iter, str[0, i1])
                  shift_coms(i1)
                  j = 0
                  cs = com.size
                  j +=1 while (j<cs) and (not ' ='.index(com[j]))
                  comu = nil
                  params = nil
                  if (j<cs)
                    params = com[j+1..-1].strip
                    comu = com[0, j]
                  else
                    comu = com
                  end
                  comu = comu.strip.upcase
                  p '---opentag  [comu,params]='+[comu,params].inspect
                  if strict_close_tag.nil? and BBCODES.include?(comu)
                    k = open_coms.find{ |ocf| ocf[0]==comu }
                    p 'opentag k='+k.inspect
                    if k
                      comu = nil
                    else
                      strict_close_tag = comu if comu=='CODE'
                      case comu
                        when 'BR'
                          dest_buf.insert(dest_buf.end_iter, "\n")
                          shift_coms(1)
                        when 'HR'
                          p1 = dest_buf.end_iter.offset
                          count = get_tag_param(params, :number)
                          count = 50 if not (count.is_a? Numeric and (count>0))
                          dest_buf.insert(dest_buf.end_iter, ' '*count)
                          shift_coms(count)
                          dest_buf.apply_tag('undline',
                            dest_buf.get_iter_at_offset(p1), dest_buf.end_iter)
                        else
                          if params and (params.size>0)
                            case comu
                              when 'IMG', 'IMAGE', 'EMOT', 'SMILE'
                                #img_text = str[0, i1]
                                def_proto = nil
                                def_proto = 'smile' if (comu=='EMOT') or (comu=='SMILE')
                                comu = nil
                                src = nil
                                if params and (params.size>0)
                                  param_hash = detect_params(params)
                                  src = param_hash['tag']
                                  src ||= param_hash['src']
                                  src ||= param_hash['link']
                                  src ||= param_hash['url']
                                  src ||= param_hash['href']
                                  alt = param_hash['alt']
                                  alt ||= param_hash['tooltip']
                                  alt ||= param_hash['popup']
                                  alt ||= param_hash['name']
                                  title = param_hash['title']
                                  title ||= param_hash['caption']
                                  title ||= param_hash['name']

                                  if (not param_hash['style'])
                                    param_hash['style'] = Pango::FontDescription::STYLE_ITALIC
                                  end
                                  #js = read_justify_param(param_hash)
                                  tag_name, tag_params = generate_tag(param_hash, nil, 'text')
                                  p 'IMG-TAGS [tag_name, tag_params]='+[tag_name, tag_params].inspect

                                  text_tag = dest_buf.tag_table.lookup(tag_name)
                                  if text_tag
                                    tv_tag = text_tag.name
                                  elsif (tag_params.size > 0)
                                    if dest_buf.create_tag(tag_name, tag_params)
                                      tv_tag = tag_name
                                    end
                                  end
                                end
                                #src = img_text if not (src and (src.size>0))
                                if src and (src.size>0)
                                  #img_buf = $window.get_icon_buf(src)
                                  pixbuf = PandoraModel.get_image_from_url(src, \
                                    true, self, def_proto)
                                  #if img_buf
                                  #  show_text = false
                                  #  dest_buf.insert(dest_buf.end_iter, img_buf)
                                  #  shift_coms(1)
                                  #end
                                  if pixbuf
                                    iter = dest_buf.end_iter
                                    if pixbuf.is_a? Gdk::Pixbuf
                                      alt ||= src
                                      PandoraUtils.set_obj_property(pixbuf, 'tooltip', alt)
                                      p1 = iter.offset
                                      dest_buf.insert(iter, pixbuf)
                                      if tv_tag
                                        p2 = p1 + 1
                                        dest_buf.apply_tag(tv_tag, \
                                          dest_buf.get_iter_at_offset(p1), \
                                          dest_buf.get_iter_at_offset(p2))
                                      end
                                      #anchor = dest_buf.create_child_anchor(iter)
                                      #img = Gtk::Image.new(img_res)
                                      #body_child.add_child_at_anchor(img, anchor)
                                      #img.show_all
                                      shift_coms(1)
                                      show_text = false
                                      if (title.is_a? String) and (title.size>0)
                                        title = "\n\n" + title
                                        dest_buf.insert(dest_buf.end_iter, title, tv_tag)
                                        shift_coms(title.size)
                                      end
                                    else
                                      errtxt ||= _('Unknown error')
                                      dest_buf.insert(iter, errtxt)
                                      shift_coms(errtxt.size)
                                    end
                                    #anchor = dest_buf.create_child_anchor(iter)
                                    #p 'IMG [wid, anchor]='+[wid, anchor].inspect
                                    #body_child.add_child_at_anchor(wid, anchor)
                                    #wid.show_all
                                  end
                                end
                              when 'BOX', 'PROPERTY', 'EDIT', 'ENTRY', 'INPUT', \
                              'SPIN', 'INTEGER', 'HEX', 'REAL', 'FLOAT', 'DATE', \
                              'TIME', 'DATETIME', 'COORD', 'FILENAME', 'BASE64', \
                              'PANHASH', 'BYTELIST', 'BUTTON'
                                #p '--BOX['+comu+'] param_hash='+param_hash.inspect
                                param_hash = detect_params(params)
                                name = param_hash['tag']
                                name ||= param_hash['name']
                                name ||= _('Noname')
                                width = param_hash['width']
                                size = param_hash['size']
                                values = param_hash['values']
                                values ||= param_hash['value']
                                values = values.split(',') if values
                                default = param_hash['default']
                                default ||= values[0] if values
                                values ||= default
                                type = param_hash['type']
                                kind = param_hash['kind']
                                type ||= comu
                                comu = nil
                                show_text = false
                                type.upcase!
                                if (type=='ENTRY') or (type=='INPUT')
                                  type = 'EDIT'
                                elsif (type=='FLOAT')
                                  type = 'REAL'
                                elsif (type=='DATETIME')
                                  type = 'TIME'
                                elsif not ['EDIT', 'SPIN', 'INTEGER', 'HEX', 'REAL', \
                                'DATE', 'TIME', 'COORD', 'FILENAME', 'BASE64', \
                                'PANHASH', 'BUTTON', 'LIST'].include?(type)
                                  type = 'LIST'
                                end

                                if name and (name.size>0)
                                  dest_buf.insert(dest_buf.end_iter, name, 'bold')
                                  dest_buf.insert(dest_buf.end_iter, ': ')
                                  shift_coms(name.size+2)
                                end

                                widget = nil
                                if type=='EDIT'
                                  widget = Gtk::Entry.new
                                  widget.text = default if default
                                elsif type=='SPIN'
                                  if values
                                    values.sort!
                                    min = values[0]
                                    max = values[-1]
                                  else
                                    min = 0.0
                                    max = 100.0
                                  end
                                  default ||= 0.0
                                  widget = Gtk::SpinButton.new(min.to_f, max.to_f, 1.0)
                                  widget.value = default.to_f
                                elsif type=='INTEGER'
                                  widget = IntegerEntry.new
                                  widget.text = default if default
                                elsif type=='HEX'
                                  widget = HexEntry.new
                                  widget.text = default if default
                                elsif type=='REAL'
                                  widget = FloatEntry.new
                                  widget.text = default if default
                                elsif type=='TIME'
                                  widget = DateTimeBox.new
                                  if default
                                    if default.downcase=='current'
                                      default = PandoraUtils.time_to_dialog_str(Time.now)
                                    end
                                    widget.text = default
                                  end
                                elsif type=='DATE'
                                  widget = DateEntry.new
                                  if default
                                    if default.downcase=='current'
                                      default = PandoraUtils.date_to_str(Time.now)
                                    end
                                    widget.text = default
                                  end
                                elsif type=='COORD'
                                  widget = CoordBox.new
                                  widget.text = default if default
                                elsif type=='FILENAME'
                                  widget = FilenameBox.new(window)
                                  widget.text = default if default
                                elsif type=='BASE64'
                                  widget = Base64Entry.new
                                  widget.text = default if default
                                elsif type=='PANHASH'
                                  kind ||= 'Blob,Person,Community,City'
                                  widget = PanhashBox.new('Panhash('+kind+')')
                                  widget.text = default if default
                                elsif type=='LIST'
                                  widget = ByteListEntry.new(PandoraModel::RelationNames)
                                  widget.text = default if default
                                else #'BUTTON'
                                  default ||= name
                                  widget = Gtk::Button.new(_(default))
                                end
                                if width or size
                                  width = width.to_i if width
                                  width ||= PandoraGtk.num_char_width*size.to_i+8
                                  if widget.is_a? Gtk::Widget
                                    widget.width_request = width
                                  elsif widget.is_a? PandoraGtk::BtnEntry
                                    widget.entry.width_request = width
                                  end
                                end
                                iter = dest_buf.end_iter
                                anchor = dest_buf.create_child_anchor(iter)
                                add_child_at_anchor(widget, anchor)
                                shift_coms(1)
                                widget.show_all
                              #end-case-when
                            end
                          else #no params
                            case comu
                              when 'P'
                                dest_buf.insert(dest_buf.end_iter, "\n")
                                shift_coms(1)
                            end
                          end
                          open_coms << [comu, 0, params] if comu
                        #end-case-when
                      end
                    end
                  else
                    comu = nil
                  end
                end
                if (not comu) and show_text
                  dest_buf.insert(dest_buf.end_iter, open_brek+com+close_brek)
                  shift_coms(com.size+2)
                end
              else
                dest_buf.insert(dest_buf.end_iter, str[0, i1])
                shift_coms(i1)
              end
              str = str[i+1..-1]
              i = 0
              ss = str.size
              i1 = nil
            else
              i += 1
            end
          end
          dest_buf.insert(dest_buf.end_iter, str)
        else
          dest_buf.text = str
        #end-case-when
      end
    end

    def set_tag(tag, params=nil, defval=nil, aformat=nil)
      bounds = buffer.selection_bounds
      ltext = rtext = ''
      aformat ||= format
      case aformat
        when 'bbcode', 'html'
          noclose = (tag and (tag[-1]=='/'))
          tag = tag[0..-2] if noclose
          t = ''
          case tag
            when 'bold'
              t = 'b'
            when 'italic'
              t = 'i'
            when 'strike'
              t = 's'
            when 'undline'
              t = 'u'
            else
              t = tag
            #end-case-when
          end
          open_brek = '['
          close_brek = ']'
          if (aformat=='html')
            open_brek = '<'
            close_brek = '>'
          end
          if params.is_a? String
            params = '='+params
          elsif params.is_a? Hash
            all = ''
            params.each do |k,v|
              all << ' '
              all << k.to_s + '="' + v.to_s + '"'
            end
            params = all
          else
            params = ''
          end
          ltext = open_brek+t+params+close_brek
          rtext = open_brek+'/'+t+close_brek if not noclose
        when 'markdown'
          case tag
            when 'bold'
              ltext = rtext = '*'
            when 'italic'
              ltext = rtext = '/'
            when 'strike'
              ltext = rtext = '-'
            when 'undline'
              ltext = rtext = '_'
          end
      end
      lpos = bounds[0].offset
      rpos = bounds[1].offset
      if (lpos==rpos) and (defval.is_a? String)
        buffer.insert(buffer.get_iter_at_offset(lpos), defval)
        rpos += defval.size
      end
      if ltext != ''
        buffer.insert(buffer.get_iter_at_offset(lpos), ltext)
        lpos += ltext.length
        rpos += ltext.length
      end
      if rtext != ''
        buffer.insert(buffer.get_iter_at_offset(rpos), rtext)
      end
      buffer.move_mark('selection_bound', buffer.get_iter_at_offset(lpos))
      buffer.move_mark('insert', buffer.get_iter_at_offset(rpos))
    end

  end

  # Editor TextView
  # RU: TextView редактора
  class EditorTextView < SuperTextView
    attr_accessor :body_win, :view_border, :raw_border, \
      :scale_width, :scale_width_in_char

    def set_left_border_width(left_border=nil)
      num_count = nil
      if (not left_border) or (left_border<0)
        add_nums = 0
        add_nums = -left_border if left_border and (left_border<0)
        line_count = buffer.line_count
        num_count = (Math.log10(line_count).truncate+1) if line_count
        num_count = 1 if (num_count.nil? or (num_count<1))
        if add_nums>0
          if (num_count+add_nums)>5
            num_count += 1
          else
            num_count += add_nums
          end
        end
        left_border = PandoraGtk.num_char_width*num_count+8
      end
      @scale_width = left_border
      @scale_width_in_char = num_count
      set_border_window_size(Gtk::TextView::WINDOW_LEFT, left_border)
    end

    def initialize(abody_win, aview_border=nil, araw_border=nil)
      @body_win = abody_win
      @view_border = aview_border
      @raw_border = araw_border
      @layout = nil
      @scale_width = 0
      @scale_width_in_char = nil
      super(aview_border)
      $font_desc ||= Pango::FontDescription.new('Monospace 11')

      self.signal_connect('expose-event') do |widget, event|
        tv = widget
        type = nil
        event_win = nil
        begin
          left_win = tv.get_window(Gtk::TextView::WINDOW_LEFT)
          right_win = tv.get_window(Gtk::TextView::WINDOW_TEXT)
          event_win = event.window
        rescue Exception
          event_win = nil
        end
        sw = @body_win #tv.scrollwin
        view_mode = true
        view_mode = sw.view_mode if sw and (sw.is_a? BodyScrolledWindow)
        if (not view_mode)
          if event_win == left_win
            type = Gtk::TextView::WINDOW_LEFT
            first_y = event.area.y
            last_y = first_y + event.area.height
            x, first_y = tv.window_to_buffer_coords(type, 0, first_y)
            x, last_y = tv.window_to_buffer_coords(type, 0, last_y)
            count = self.get_lines(first_y, last_y)
            # Draw fully internationalized numbers!
            @layout ||= widget.create_pango_layout
            @gc ||= widget.style.fg_gc(Gtk::STATE_NORMAL)
            afound_lines = nil
            fp = self.find_panel
            if (not fp) or fp.destroyed? or (not fp.visible?) or (not fp.positions)
              fp = nil
            end
            cur_line = nil
            #if not fp
            #  buf = tv.buffer
            #  iter = buf.get_iter_at_offset(buf.cursor_position)
            #  cur_line = iter.line if iter
            #end
            if not self.destroyed?
              count.times do |i|
                x, pos = tv.buffer_to_window_coords(type, 0, @pixels[i])
                line_num = numbers[i]
                str = line_num.to_s
                bg = nil
                if fp and fp.has_line_found?(line_num-1)
                  if fp.find_line and (fp.find_line==line_num-1)
                    @find_bg ||= Gdk::Color.parse('#F19922')
                    bg = @find_bg
                  else
                    @found_bg ||= Gdk::Color.parse('#DDDD00')
                    bg = @found_bg
                  end
                  #if @scale_width_in_char and (str.size<@scale_width_in_char)
                  #  str << '     '[0, @scale_width_in_char-str.size]
                  #end
                elsif cur_line and (cur_line==line_num-1)
                  @active_bg ||= Gdk::Color.parse('#A10000')
                  bg = @active_bg
                end
                @layout.text = str
                #widget.style.paint_layout(target, widget.state, false, \
                #  nil, widget, nil, 2, pos, @layout)   #Gtk2 fails sometime!!!
                left_win = tv.get_window(Gtk::TextView::WINDOW_LEFT)
                left_win.draw_layout(@gc, 2, pos, @layout, nil, bg)
              end
            end
            #draw_pixmap
          elsif event_win == right_win
            #@gc = widget.style.text_gc(Gtk::STATE_NORMAL)
            @line_gc ||= nil
            if not @line_gc
              @line_gc = Gdk::GC.new(right_win)
              @line_gc.rgb_fg_color = Gdk::Color.parse('#1A1A1A') #Gdk::Color.new(30000, 0, 30000)
              #@line_gc.function = Gdk::GC::AND
            end
            buf = tv.buffer
            iter = buf.get_iter_at_offset(buf.cursor_position)
            if iter
              y, line_hei = tv.get_line_yrange(iter)
              x, y = tv.buffer_to_window_coords(Gtk::TextView::WINDOW_TEXT, 0, y)
              wid, hei = right_win.size
              right_win.draw_rectangle(@line_gc, true, x+1, y, wid-2, line_hei) if y<hei
            end
          end
        end
        false
      end
    end

    def iter_on_screen(iter, mark_str, buf)
      buf.place_cursor(iter)
      self.scroll_mark_onscreen(buf.get_mark(mark_str))
    end

    def color_tags(buf, off1, len)
      line1 = buf.get_iter_at_offset(off1).line
      line2 = buf.get_iter_at_offset(off1 + len).line
      @body_win.set_tags(buf, line1, line2)
    end

    def do_undo
      if (not @body_win.view_mode) and (@body_win.undopool.size>0)
        action = @body_win.undopool.pop
        case action[0]
          when 'ins'
            start_iter = @body_win.raw_buffer.get_iter_at_offset(action[1])
            end_iter = @body_win.raw_buffer.get_iter_at_offset(action[2])
            @body_win.raw_buffer.delete(start_iter, end_iter)
          when 'del'
            start_iter = @body_win.raw_buffer.get_iter_at_offset(action[1])
            text = action[3]
            off1 = start_iter.offset
            @body_win.raw_buffer.insert(start_iter, text)
            color_tags(@body_win.raw_buffer, off1, text.size)
        end
        iter_on_screen(start_iter, 'insert', @body_win.raw_buffer)
        @body_win.redopool << action
      end
    end

    def do_redo
      if (not @body_win.view_mode) and (@body_win.redopool.size>0)
        action = @body_win.redopool.pop
        case action[0]
          when 'ins'
            start_iter = @body_win.raw_buffer.get_iter_at_offset(action[1])
            text = action[3]
            off1 = start_iter.offset
            @body_win.raw_buffer.insert(start_iter, text)
            color_tags(@body_win.raw_buffer, off1, text.size)
          when 'del'
            start_iter = @body_win.raw_buffer.get_iter_at_offset(action[1])
            end_iter = @body_win.raw_buffer.get_iter_at_offset(action[2])
            @body_win.raw_buffer.delete(start_iter, end_iter)
        end
        iter_on_screen(start_iter, 'insert', @body_win.raw_buffer)
        @body_win.undopool << action
      end
    end

  end

  class ChatTextView < SuperTextView
    attr_accessor :mes_ids, :send_btn, :edit_box, \
      :crypt_btn, :sign_btn, :smile_btn

    def initialize(*args)
      @@save_buf ||= $window.get_icon_scale_buf('save', 'pan', 14)
      @@gogo_buf ||= $window.get_icon_scale_buf('gogo', 'pan', 14)
      @@recv_buf ||= $window.get_icon_scale_buf('recv', 'pan', 14)
      @@crypt_buf ||= $window.get_icon_scale_buf('crypt', 'pan', 14)
      @@sign_buf ||= $window.get_icon_scale_buf('sign', 'pan', 14)
      #@@nosign_buf ||= $window.get_icon_scale_buf('nosign', 'pan', 14)
      @@fail_buf ||= $window.get_preset_icon(Gtk::Stock::DIALOG_WARNING, nil, 14)

      super(*args)
      @mes_ids = Array.new
      @mes_model = PandoraUtils.get_model('Message')
      @sign_model = PandoraUtils.get_model('Sign')

      signal_connect('expose-event') do |widget, event|
        type = nil
        event_win = nil
        begin
          left_win = widget.get_window(Gtk::TextView::WINDOW_LEFT)
          event_win = event.window
        rescue Exception
          event_win = nil
        end
        if event_win and left_win and (event_win == left_win)
          type = Gtk::TextView::WINDOW_LEFT
          first_y = event.area.y
          last_y = first_y + event.area.height
          x, first_y = widget.window_to_buffer_coords(type, 0, first_y)
          x, last_y = widget.window_to_buffer_coords(type, 0, last_y)
          count = self.get_lines(first_y, last_y, true)
          cr = left_win.create_cairo_context

          count.times do |i|
            y1, h1 = pixels[i]
            x, y = widget.buffer_to_window_coords(type, 0, y1)
            line = numbers[i]
            attr = 1
            id = mes_ids[line]
            if id
              flds = 'state, panstate, panhash'
              sel = @mes_model.select({:id=>id}, false, flds, nil, 1)
              if sel and (sel.size > 0)
                state = sel[0][0]
                panstate = sel[0][1]
                if state
                  if state==0
                    cr.set_source_pixbuf(@@save_buf, 0, y+h1-@@save_buf.height)
                    cr.paint
                  elsif state==1
                    cr.set_source_pixbuf(@@gogo_buf, 0, y+h1-@@gogo_buf.height)
                    cr.paint
                  elsif state==2
                    cr.set_source_pixbuf(@@recv_buf, 0, y+h1-@@recv_buf.height)
                    cr.paint
                  end
                end
                if panstate
                  if (panstate & PandoraModel::PSF_Crypted) > 0
                    cr.set_source_pixbuf(@@crypt_buf, 18, y+h1-@@crypt_buf.height)
                    cr.paint
                  end
                  if (panstate & PandoraModel::PSF_Verified) > 0
                    panhash = sel[0][2]
                    sel = @sign_model.select({:obj_hash=>panhash}, false, 'id', nil, 1)
                    if sel and (sel.size > 0)
                      cr.set_source_pixbuf(@@sign_buf, 35, y+h1-@@sign_buf.height)
                    else
                      cr.set_source_pixbuf(@@fail_buf, 35, y+h1-@@fail_buf.height)
                    end
                    cr.paint
                  end
                end
              end
            end
          end
        end
        false
      end
    end

    # Update status icon border if visible lines contain id or ids
    # RU: Обновляет бордюр с иконками статуса, если видимые строки содержат ids
    def update_lines_with_id(ids=nil, redraw_before=true)
      self.queue_draw if redraw_before
      need_redraw = nil
      if ids
        if ids.is_a? Array
          ids.each do |id|
            line = mes_ids.index(id)
            if line and numbers.include?(line)
              need_redraw = true
              break
            end
          end
        else
          line = mes_ids.index(ids)
          need_redraw = true if line and numbers.include?(line)
        end
      else
        need_redraw = true
      end
      if need_redraw
        left_win = self.get_window(Gtk::TextView::WINDOW_LEFT)
        left_win.invalidate(left_win.frame_extents, true)
      end
    end

  end

  # Trust change Scale
  # RU: Шкала для изменения доверия
  class TrustScale < ColorDayBox
    attr_accessor :scale

    def colorize
      if sensitive?
        val = scale.value
        trust = (val*127).round
        r = 0
        g = 0
        b = 0
        if trust==0
          b = 40000
        else
          mul = ((trust.fdiv(127))*45000).round
          if trust>0
            g = mul+20000
          else
            r = -mul+20000
          end
        end
        color = Gdk::Color.new(r, g, b)
        #scale.modify_fg(Gtk::STATE_NORMAL, color)
        self.bg = color
        prefix = ''
        prefix = _(@tooltip_prefix) + ': ' if @tooltip_prefix
        scale.tooltip_text = prefix+val.to_s
      else
        #modify_fg(Gtk::STATE_NORMAL, nil)
        self.bg = nil
        scale.tooltip_text = ''
      end
    end

    def initialize(bg=nil, tooltip_prefix=nil, avalue=nil)
      super(bg)
      @tooltip_prefix = tooltip_prefix
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0.0)
      @scale = Gtk::HScale.new(adjustment)
      scale.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
      scale.set_size_request(100, -1)
      scale.value_pos = Gtk::POS_RIGHT
      scale.digits = 1
      scale.draw_value = true
      scale.signal_connect('value-changed') do |widget|
        colorize
      end
      self.signal_connect('notify::sensitive') do |widget, param|
        colorize
      end
      scale.signal_connect('scroll-event') do |widget, event|
        res = (not (event.state.control_mask? or event.state.shift_mask?))
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          widget.value = (widget.value-0.1).round(1) if res
        else
          widget.value = (widget.value+0.1).round(1) if res
        end
        res
      end
      scale.value = avalue if avalue
      self.add(scale)
      colorize
    end
  end

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :image, :label, :stock

    def set_stock(astock)
      p @stock = astock
      #$window.register_stock(stock)
      an_image = $window.get_preset_image(stock, Gtk::IconSize::SMALL_TOOLBAR, nil)
      if (@image.is_a? Gtk::Image) and @image.icon_set
        @image.icon_set = an_image.icon_set
      else
        @image = an_image
      end
    end

    def initialize(an_image, title, achild=nil, *args)
      args ||= [false, 0]
      super(*args)
      @image = an_image
      @image ||= :person
      if ((image.is_a? Symbol) or (image.is_a? String))
        set_stock(image)
      end
      @image.set_padding(2, 0)
      self.pack_start(image, false, false, 0) if image
      @label = Gtk::Label.new(title)
      #label.xalign = 0.0
      self.pack_start(label, true, true, 0)
      if achild
        btn = Gtk::Button.new
        btn.relief = Gtk::RELIEF_NONE
        btn.focus_on_click = false
        style = btn.modifier_style
        style.xthickness = 0
        style.ythickness = 0
        btn.modify_style(style)
        wim,him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
        btn.set_size_request(wim+2,him+2)
        @achild = achild
        btn.signal_connect('clicked') do |*args|
          yield if block_given?
          ind = $window.notebook.children.index(@achild)
          $window.notebook.remove_page(ind) if ind
          @achild.destroy if (@achild and (not @achild.destroyed?))
          self.destroy if (not self.destroyed?)
        end
        #close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
        @@close_image ||= $window.get_preset_icon(Gtk::Stock::CLOSE, nil, wim)
        btn.add(Gtk::Image.new(@@close_image))
        align = Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
        align.add(btn)
        self.pack_start(align, false, false, 0)
      end
      self.spacing = 3
      self.show_all
    end
  end

  # Window for view body (text or blob)
  # RU: Окно просмотра тела (текста или блоба)
  class BodyScrolledWindow < Gtk::ScrolledWindow
    include PandoraUtils

    attr_accessor :field, :link_name, :body_child, :format, :raw_buffer, :view_buffer, \
      :view_mode, :color_mode, :fields, :property_box, :toolbar, :edit_btn, \
      :undopool, :redopool, :user_action


    def parent_win
      res = parent.parent.parent
    end

    def get_fld_value_by_id(id)
      res = nil
      fld = fields.detect{ |f| (f[PandoraUtils::FI_Id].to_s == id) }
      res = fld[PandoraUtils::FI_Value] if fld.is_a? Array
      res
    end

    def format_must_be_editable(aformat)
      res = ['ruby', 'python', 'xml', 'ini'].include?(aformat)
    end

    def fill_body
      if field
        link_name = field[PandoraUtils::FI_Widget].text
        link_name.chomp! if link_name
        link_name = PandoraUtils.absolute_path(link_name)
        bodywin = self
        bodywid = self.child
        if (not bodywid) or (link_name != bodywin.link_name)
          @last_sw = child
          if bodywid
            bodywid.destroy if (not bodywid.destroyed?)
            bodywid = nil
            #field[PandoraUtils::FI_Widget2] = nil
          end
          if link_name and (link_name != '')
            if File.exist?(link_name)
              ext = File.extname(link_name)
              ext_dc = ext.downcase
              if ext
                case ext_dc
                  when '.jpg','.jpeg','.gif','.png', '.ico'
                    scale = nil
                    #!!!img_width  = bodywin.parent.allocation.width-14
                    #!!!img_height = bodywin.parent.allocation.height
                    img_width  = bodywin.allocation.width-14
                    img_height = bodywin.allocation.height
                    image = PandoraGtk.start_image_loading(link_name, nil, scale)
                      #img_width, img_height)
                    bodywid = image
                    bodywin.link_name = link_name
                  when'.rb'
                    @format = 'ruby'
                  when '.py'
                    @format = 'python'
                  when '.xml'
                    @format = 'xml'
                  when '.htm', '.html'
                    @format = 'html'
                  when '.bbcode'
                    @format = 'bbcode'
                  when '.wiki'
                    @format = 'wiki'
                  when '.ini'
                    @format = 'ini'
                  when '.md', '.markdown'
                    @format = 'markdown'
                  #when '.csv','.sh'
                  else
                    @format = 'plain'
                end
                p '--fill_body1  Read file: ['+link_name+']  format='+@format
                File.open(link_name, 'r') do |file|
                  field[PandoraUtils::FI_Value] = file.read
                  p 'Files is readed ok.'
                end
              end
              if not ext
                field[PandoraUtils::FI_Value] = '@'+link_name
              end
            else
              err_text = _('File does not exist')+":\n"+link_name
              label = Gtk::Label.new(err_text)
              bodywid = label
            end
          else
            link_name = nil
          end

          bodywid ||= PandoraGtk::EditorTextView.new(bodywin, 0, nil)

          if not bodywin.child
            if bodywid.is_a? PandoraGtk::SuperTextView
              begin
                bodywin.add(bodywid)
              rescue Exception
                bodywin.add_with_viewport(bodywid)
              end
            else
              bodywin.add_with_viewport(bodywid)
            end
            fmt = get_fld_value_by_id('type')
            if fmt.is_a?(String) and (fmt.size>0)
              fmt = fmt.downcase
              if (not @format.is_a?(String)) or (@format.size==0) or (fmt != 'auto')
                @format = fmt
              end
              p '--fill_body2  format='+@format
            end
          end
          bodywin.body_child = bodywid
          if bodywid.is_a? Gtk::TextView
            bodywin.init_view_buf(bodywin.body_child.buffer)
            atext = field[PandoraUtils::FI_Value].to_s
            bodywin.init_raw_buf(atext)
            if ((atext and (atext.size==0)) or format_must_be_editable(@format))
              bodywin.view_mode = false
            end
            @@max_color_lines ||= nil
            if not @@max_color_lines
              @@max_color_lines = PandoraUtils.get_param('max_color_lines')
              @@max_color_lines ||= 700
            end
            if raw_buffer and (raw_buffer.line_count>@@max_color_lines)
              bodywin.color_mode = false
            end
            bodywin.set_buffers
            #toolbar.show
          else
            #toolbar2.show
          end
          bodywin.show_all
        end
      end
    end

    def initialize(aproperty_box, afields, *args)
      @@page_setup ||= nil
      super(*args)
      @property_box = aproperty_box
      @format = 'bbcode'
      @view_mode = true
      @color_mode = true
      @fields = afields
      @undopool = nil
      @redopool = nil
      @user_action = nil
    end

    def init_view_buf(buf)
      if (not @view_buffer) and buf
        @view_buffer = buf
      end
    end

    def init_raw_buf(text=nil)
      if (not @raw_buffer)
        buf ||= Gtk::TextBuffer.new
        @raw_buffer = buf
        buf.text = text if text
        buf.create_tag('string', {'foreground' => '#00f000'})
        buf.create_tag('symbol', {'foreground' => '#008020'})
        buf.create_tag('comment', {'foreground' => '#8080e0'})
        buf.create_tag('keyword', {'foreground' => '#ffffff', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('keyword2', {'foreground' => '#ffffff'})
        buf.create_tag('function', {'foreground' => '#f12111'})
        buf.create_tag('number', {'foreground' => '#f050e0'})
        buf.create_tag('hexadec', {'foreground' => '#e070e7'})
        buf.create_tag('constant', {'foreground' => '#60eedd'})
        buf.create_tag('big_constant', {'foreground' => '#d080e0'})
        buf.create_tag('identifer', {'foreground' => '#ffff33'})
        buf.create_tag('global', {'foreground' => '#ffa500'})
        buf.create_tag('instvar', {'foreground' => '#ff85a2'})
        buf.create_tag('classvar', {'foreground' => '#ff79ec'})
        buf.create_tag('operator', {'foreground' => '#ffffff'})
        buf.create_tag('class', {'foreground' => '#ff1100', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('module', {'foreground' => '#1111ff', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('regex', {'foreground' => '#105090'})

        buf.create_tag('found', 'background' =>  '#888800')
        buf.create_tag('find', 'background' =>   '#AA5500')

        buf.signal_connect('changed') do |buf|  #modified-changed
          mark = buf.get_mark('insert')
          iter = buf.get_iter_at_mark(mark)
          line1 = iter.line
          set_tags(buf, line1, line1, true)
          false
        end

        @undopool = Array.new
        @redopool = Array.new

        @view_buffer_off1 = nil

        buf.signal_connect('insert-text') do |buf, iter, text, len|
          it_of = iter.offset
          @view_buffer_off1 = it_of
          if @user_action
            #@undopool <<  ['ins', iter.offset, iter.offset + text.scan(/./).size, text]
            @undopool <<  ['ins', it_of, it_of + text.size, text]
            @redopool.clear
          end
          false
        end

        buf.signal_connect('delete-range') do |buf, start_iter, end_iter|
          if @user_action
            text = buf.get_text(start_iter, end_iter)
            @undopool <<  ['del', start_iter.offset, end_iter.offset, text]
          end
          false
        end

        buf.signal_connect('begin-user-action') do
          @user_action = true
        end
        buf.signal_connect('end-user-action') do
          @user_action = false
        end

        buf.signal_connect('paste-done') do |buf|
          @view_buffer_off1 ||= buf.cursor_position
          if @view_buffer_off1
            line1 = buf.get_iter_at_offset(@view_buffer_off1).line
            mark = buf.get_mark('insert')
            iter = buf.get_iter_at_mark(mark)
            line2 = iter.line
            @view_buffer_off1 = iter.offset
            set_tags(buf, line1, line2)
          end
          false
        end

        iter = buf.get_iter_at_offset(0)
        if iter
          #@treeview.scroll_to_iter(iter, 0.1, false, 0.0, 0.0)
          buf.place_cursor(iter)
        end
      end
    end

    # Ruby key words
    # Ключевые слова Ruby
    RUBY_KEYWORDS = ('begin end module class def if then else elsif' \
      +' while unless do case when require yield rescue include').split
    RUBY_KEYWORDS2 = 'self nil true false not and or super return require_relative'.split

    RubyValueTags = [:hexadec, :number, :identifer, :big_constant, :constant, \
      :classvar, :instvar, :global]

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def ruby_tag_line(str, index, mode)

      def ident_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) or (c == '_')
      end

      def capt_char?(c)
        ('A'..'Z').include?(c) or ('0'..'9').include?(c) or (c == '_')
      end

      def word_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) \
        or ('0'..'9').include?(c) or (c == '_')
      end

      def oper_char?(c)
        ".+,-=*^%()<>&[]!?~{}|/\\".include?(c)
      end

      def rewind_ident(str, i, ss, pc, prev_kw=nil)

        def check_func(prev_kw, c, i, ss, str)
          if (prev_kw=='def') and (c.nil? or (c=='.'))
            if not c.nil?
              yield(:operator, i, i+1)
              i += 1
            end
            i1 = i
            i += 1 while (i<ss) and word_char?(str[i])
            i += 1 if (i<ss) and ('=?!'.include?(str[i]))
            i2 = i
            yield(:function, i1, i2)
          end
          i
        end

        kw = nil
        c = str[i]
        fc = c
        i1 = i
        i += 1
        big_cons = true
        while (i<ss)
          c = str[i]
          if ('a'..'z').include?(c)
            big_cons = false if big_cons
          elsif not capt_char?(c)
            break
          end
          i += 1
        end
        #p 'rewind_ident(str, i1, i, ss, pc)='+[str, i1, i, ss, pc].inspect
        #i -= 1
        i2 = i
        if ('A'..'Z').include?(fc)
          if prev_kw=='class'
            yield(:class, i1, i2)
          elsif prev_kw=='module'
            yield(:module, i1, i2)
          else
            if big_cons
              if ['TRUE', 'FALSE'].include?(str[i1, i2-i1])
                yield(:keyword2, i1, i2)
              else
                yield(:big_constant, i1, i2)
              end
            else
              yield(:constant, i1, i2)
            end
            i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
              yield(tag, id1, id2)
            end
          end
        else
          if pc==':'
            yield(:symbol, i1-1, i2)
          elsif pc=='@'
            if (i1-2>0) and (str[i1-2]=='@')
              yield(:classvar, i1-2, i2)
            else
              yield(:instvar, i1-1, i2)
            end
          elsif pc=='$'
            yield(:global, i1-1, i2)
          else
            can_keyw = (((i1<=0) or " \t\n({}[]=|+&,".include?(str[i1-1])) \
              and ((i2>=ss) or " \t\n(){}[]=|+&,.".include?(str[i2])))
            s = str[i1, i2-i1]
            if can_keyw and RUBY_KEYWORDS.include?(s)
              yield(:keyword, i1, i2)
              kw = s
            elsif can_keyw and RUBY_KEYWORDS2.include?(s)
              yield(:keyword2, i1, i2)
              if (s=='self') and (prev_kw=='def')
                i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                  yield(tag, id1, id2)
                end
              end
            else
              i += 1 if (i<ss) and ('?!'.include?(str[i]))
              if prev_kw=='def'
                if (i<ss) and (str[i]=='.')
                  yield(:identifer, i1, i)
                  i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                else
                  i = check_func(prev_kw, nil, i1, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                end
              else
                yield(:identifer, i1, i)
              end
            end
          end
        end
        [i, kw]
      end

      def apply_tag(tag, start, last)
        @last_tag = tag
        @raw_buffer.apply_tag(tag.to_s, \
          @raw_buffer.get_iter_at_offset(start), \
          @raw_buffer.get_iter_at_offset(last))
      end

      @last_tag = nil

      ss = str.size
      if ss>0
        i = 0
        if (mode == 1)
          if (str[0,4] == '=end')
            mode = 0
            i = 4
            apply_tag(:comment, index, index + i)
          else
            apply_tag(:comment, index, index + ss)
          end
        elsif (mode == 0) and (str[0,6] == '=begin')
          mode = 1
          apply_tag(:comment, index, index + ss)
        elsif (mode != 1)
          i += 1 while (i<ss) and ((str[i] == ' ') or (str[i] == "\t"))
          pc = ' '
          kw, kw2 = nil
          while (i<ss)
            c = str[i]
            if (c != ' ') and (c != "\t")
              if (c == '#')
                apply_tag(:comment, index + i, index + ss)
                break
              elsif ((c == "'") or (c == '"') or ((c == '/') \
              and (not RubyValueTags.include?(@last_tag))))
                qc = c
                i1 = i
                i += 1
                if (i<ss)
                  c = str[i]
                  if c==qc
                    i += 1
                  else
                    pc = ' '
                    while (i<ss) and ((c != qc) or (pc == "\\") or (pc == qc))
                      if (pc=="\\")
                        pc = ' '
                      else
                        pc = c
                      end
                      c = str[i]
                      if (qc=='"') and (c=='{') and (pc=='#')
                        apply_tag(:string, index + i1, index + i - 1)
                        apply_tag(:operator, index + i - 1, index + i + 1)
                        i, kw2 = rewind_ident(str, i, ss, ' ') do |tag, id1, id2|
                          apply_tag(tag, index + id1, index + id2)
                        end
                        i1 = i
                      end
                      i += 1
                    end
                  end
                end
                if (qc == '/')
                  i += 1 while (i<ss) and ('imxouesn'.include?(str[i]))
                  apply_tag(:regex, index + i1, index + i)
                else
                  apply_tag(:string, index + i1, index + i)
                end
              elsif ident_char?(c)
                i, kw = rewind_ident(str, i, ss, pc, kw) do |tag, id1, id2|
                  apply_tag(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif (c=='$') and (i+1<ss) and ('~'.include?(str[i+1]))
                i1 = i
                i += 2
                apply_tag(:global, index + i1, index + i)
                pc = ' '
              elsif oper_char?(c) or ((pc==':') and (c==':'))
                i1 = i
                i1 -=1 if (i1>0) and (c==':')
                i += 1
                if (i<ss) and not((c=='(') and (str[i]=='/'))
                  while (i<ss) and (oper_char?(str[i]) or ((pc==':') and (str[i]==':')))
                    i += 1
                  end
                end
                if i<ss
                  pc = ' '
                  c = str[i]
                end
                apply_tag(:operator, index + i1, index + i)
              elsif ((c==':') or (c=='$')) and (i+1<ss) and (ident_char?(str[i+1]))
                i += 1
                pc = c
                i, kw2 = rewind_ident(str, i, ss, pc) do |tag, id1, id2|
                  apply_tag(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif ('0'..'9').include?(c)
                i1 = i
                i += 1
                if (i<ss) and ((str[i]=='x') or (str[i]=='X'))
                  i += 1
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) or ('A'..'F').include?(c))
                    i += 1
                  end
                  apply_tag(:hexadec, index + i1, index + i)
                else
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) \
                      or ((c=='.') and (str[i-1] != '.')) or (c=='e'))
                    i += 1
                  end
                  if i<ss
                    i -= 1 if str[i-1]=='.'
                    pc = ' '
                  end
                  apply_tag(:number, index + i1, index + i)
                end
              else
                #yield(:keyword, index + i, index + ss/2)
                #break
                pc = c
                i += 1
              end
            else
              pc = c
              i += 1
            end
          end
        end
      end
      mode
    end

    # Python key words
    # Ключевые слова Python
    PYTHON_KEYWORDS = ('as assert break class continue def del elif else' \
      +' except exec finally for from global if import in is lambda pass' \
      +' print raise return try while with yield').split
    PYTHON_KEYWORDS2 = 'and not or self False None True'.split
    PYTHON_IDENTS = ('ArithmeticError AssertionError AttributeError' \
      +' BaseException BufferError BytesWarning DeprecationWarning' \
      +' EOFError Ellipsis EnvironmentError Exception' \
      +' FloatingPointError FutureWarning GeneratorExit IOError' \
      +' ImportError ImportWarning IndentationError IndexError KeyError' \
      +' KeyboardInterrupt LookupError MemoryError NameError' \
      +' NotImplemented NotImplementedError OSError OverflowError' \
      +' PendingDeprecationWarning ReferenceError RuntimeError' \
      +' RuntimeWarning StandardError StopIteration SyntaxError' \
      +' SyntaxWarning SystemError SystemExit TabError TypeError' \
      +' UnboundLocalError UnicodeDecodeError UnicodeEncodeError' \
      +' UnicodeError UnicodeTranslateError UnicodeWarning UserWarning' \
      +' ValueError Warning ZeroDivisionError __debug__ __doc__' \
      +' __import__ __name__ __package__ abs all any apply basestring' \
      +' bin bool buffer bytearray bytes callable chr classmethod cmp' \
      +' coerce compile complex copyright credits delattr dict dir' \
      +' divmod enumerate eval execfile exit file filter float format' \
      +' frozenset getattr globals hasattr hash help hex id input int' \
      +' intern isinstance issubclass iter len license list locals long' \
      +' map max min next object oct open ord pow print property quit' \
      +' range raw_input reduce reload repr reversed round set setattr' \
      +' slice sorted staticmethod str sum super tuple type unichr' \
      +' unicode vars xrange zip').split

    PythonValueTags = [:hexadec, :number, :identifer, :big_constant, :constant, \
      :classvar, :instvar, :global]

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def python_tag_line(str, index, mode)

      def ident_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) or (c == '_')
      end

      def capt_char?(c)
        ('A'..'Z').include?(c) or ('0'..'9').include?(c) or (c == '_')
      end

      def word_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) \
        or ('0'..'9').include?(c) or (c == '_')
      end

      def oper_char?(c)
        ".+,-=*:^%()<>&[]!?~{}|/\\".include?(c)
      end

      def rewind_ident(str, i, ss, pc, prev_kw=nil)

        def check_func(prev_kw, c, i, ss, str)
          if (prev_kw=='def') and (c.nil? or (c=='.'))
            if not c.nil?
              yield(:operator, i, i+1)
              i += 1
            end
            i1 = i
            i += 1 while (i<ss) and word_char?(str[i])
            i += 1 if (i<ss) and ('=?!'.include?(str[i]))
            i2 = i
            yield(:function, i1, i2)
          end
          i
        end

        kw = nil
        c = str[i]
        fc = c
        i1 = i
        i += 1
        big_cons = true
        while (i<ss)
          c = str[i]
          if ('a'..'z').include?(c)
            big_cons = false if big_cons
          elsif not capt_char?(c)
            break
          end
          i += 1
        end
        #p 'rewind_ident(str, i1, i, ss, pc)='+[str, i1, i, ss, pc].inspect
        #i -= 1
        i2 = i
        if ('A'..'Z').include?(fc)
          if prev_kw=='class'
            yield(:class, i1, i2)
          elsif prev_kw=='module'
            yield(:module, i1, i2)
          else
            s = str[i1, i2-i1]
            if PYTHON_KEYWORDS2.include?(s)
              yield(:keyword2, i1, i2)
            elsif PYTHON_IDENTS.include?(s)
              yield(:global, i1, i2)
            elsif big_cons
              if ['TRUE', 'FALSE'].include?(s)
                yield(:keyword2, i1, i2)
              else
                yield(:big_constant, i1, i2)
              end
            else
              yield(:constant, i1, i2)
            end
            i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
              yield(tag, id1, id2)
            end
          end
        else
          #if pc==':'
          #  yield(:symbol, i1-1, i2)
          if pc=='@'
            if (i1-2>0) and (str[i1-2]=='@')
              yield(:classvar, i1-2, i2)
            else
              yield(:instvar, i1-1, i2)
            end
          elsif pc=='$'
            yield(:global, i1-1, i2)
          else
            can_keyw = (((i1<=0) or " \t\n({}[]=|+&,".include?(str[i1-1])) \
              and ((i2>=ss) or " \t\n(){}[]=|+&,.:".include?(str[i2])))
            s = str[i1, i2-i1]
            if can_keyw and PYTHON_KEYWORDS.include?(s)
              yield(:keyword, i1, i2)
              kw = s
            elsif can_keyw and PYTHON_KEYWORDS2.include?(s)
              yield(:keyword2, i1, i2)
              if (s=='self') and (prev_kw=='def')
                i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                  yield(tag, id1, id2)
                end
              end
            elsif PYTHON_IDENTS.include?(s)
              yield(:global, i1, i2)
              kw = s
            else
              i += 1 if (i<ss) and ('?!'.include?(str[i]))
              if prev_kw=='def'
                if (i<ss) and (str[i]=='.')
                  yield(:identifer, i1, i)
                  i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                else
                  i = check_func(prev_kw, nil, i1, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                end
              else
                if ((i<ss) and (str[i]=='('))
                  yield(:instvar, i1, i)
                else
                  yield(:identifer, i1, i)
                end
              end
            end
          end
        end
        [i, kw]
      end

      def apply_tag(tag, start, last)
        @last_tag = tag
        @raw_buffer.apply_tag(tag.to_s, \
          @raw_buffer.get_iter_at_offset(start), \
          @raw_buffer.get_iter_at_offset(last))
      end

      @last_tag = nil

      ss = str.size
      if ss>0
        i = 0
        if (mode == 1)
          if (str[0,4] == '=end')
            mode = 0
            i = 4
            apply_tag(:comment, index, index + i)
          else
            apply_tag(:comment, index, index + ss)
          end
        elsif (mode == 0) and (str[0,6] == '=begin')
          mode = 1
          apply_tag(:comment, index, index + ss)
        elsif (mode != 1)
          i += 1 while (i<ss) and ((str[i] == ' ') or (str[i] == "\t"))
          pc = ' '
          kw, kw2 = nil
          while (i<ss)
            c = str[i]
            if (c != ' ') and (c != "\t")
              if (c == '#')
                apply_tag(:comment, index + i, index + ss)
                break
              elsif ((c == "'") or (c == '"') or ((c == '/') \
              and (not PythonValueTags.include?(@last_tag))))
                qc = c
                i1 = i
                i += 1
                if (i<ss)
                  c = str[i]
                  if c==qc
                    i += 1
                  else
                    pc = ' '
                    while (i<ss) and ((c != qc) or (pc == "\\") or (pc == qc))
                      if (pc=="\\")
                        pc = ' '
                      else
                        pc = c
                      end
                      c = str[i]
                      if (qc=='"') and (c=='{') and (pc=='#')
                        apply_tag(:string, index + i1, index + i - 1)
                        apply_tag(:operator, index + i - 1, index + i + 1)
                        i, kw2 = rewind_ident(str, i, ss, ' ') do |tag, id1, id2|
                          apply_tag(tag, index + id1, index + id2)
                        end
                        i1 = i
                      end
                      i += 1
                    end
                  end
                end
                if (qc == '/')
                  i += 1 while (i<ss) and ('imxouesn'.include?(str[i]))
                  apply_tag(:regex, index + i1, index + i)
                else
                  apply_tag(:string, index + i1, index + i)
                end
              elsif ident_char?(c)
                i, kw = rewind_ident(str, i, ss, pc, kw) do |tag, id1, id2|
                  apply_tag(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif (c=='$') and (i+1<ss) and ('~'.include?(str[i+1]))
                i1 = i
                i += 2
                apply_tag(:global, index + i1, index + i)
                pc = ' '
              elsif oper_char?(c) #or ((pc==':') and (c==':'))
                i1 = i
                #i1 -=1 if (i1>0) and (c==':')
                i += 1
                if (i<ss) and not((c=='(') and (str[i]=='/'))
                  while (i<ss) and (oper_char?(str[i]) or ((pc==':') and (str[i]==':')))
                    i += 1
                  end
                end
                if i<ss
                  pc = ' '
                  c = str[i]
                end
                apply_tag(:operator, index + i1, index + i)
              elsif ((c==':') or (c=='$')) and (i+1<ss) and (ident_char?(str[i+1]))
                i += 1
                pc = c
                i, kw2 = rewind_ident(str, i, ss, pc) do |tag, id1, id2|
                  apply_tag(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif ('0'..'9').include?(c)
                i1 = i
                i += 1
                if (i<ss) and ((str[i]=='x') or (str[i]=='X'))
                  i += 1
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) or ('A'..'F').include?(c))
                    i += 1
                  end
                  apply_tag(:hexadec, index + i1, index + i)
                else
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) \
                      or ((c=='.') and (str[i-1] != '.')) or (c=='e'))
                    i += 1
                  end
                  if i<ss
                    i -= 1 if str[i-1]=='.'
                    pc = ' '
                  end
                  apply_tag(:number, index + i1, index + i)
                end
              else
                #yield(:keyword, index + i, index + ss/2)
                #break
                pc = c
                i += 1
              end
            else
              pc = c
              i += 1
            end
          end
        end
      end
      mode
    end

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def bbcode_html_tag_line(str, index=0, mode=0, format='bbcode')
      open_brek = '['
      close_brek = ']'
      if (format=='html') or (format=='xml')
        open_brek = '<'
        close_brek = '>'
      end
      d = 0
      ss = str.size
      while ss>0
        if mode>0
          # find close brek
          i = str.index(close_brek)
          #p 'close brek  [str,i,d]='+[str,i,d].inspect
          k = ss
          if i
            k = i
            k -= 1 if (k>0) and (str[k-1] == '/')
            yield(:operator, index + d + k, index + d + i + 1)
            i += 1
            mode = 0
          else
            i = ss
          end
          if k>0
            com = str[0, k]
            j = 0
            cs = com.size
            j +=1 while ((j<cs) and (com[j] != ' ') and (com[j] != '='))
            comu = nil
            params = nil
            if (j<cs)
              comu = com[0, j]
              params = com[j+1..-1].strip
            else
              comu = com
            end
            if comu and (comu.size>0)
              if SuperTextView::BBCODES.include?(comu.upcase)
                yield(:big_constant, index + d, index + d + j)
              else
                yield(:constant, index + d, index + d + j)
              end
            end
            if j<cs
              yield(:comment, index + d + j + 1, index + d + k)
            end
          end
        else
          # find open brek
          if (format=='ini') and (str[0]==';')
            i = ss
            yield(:comment, index + d, index + d + i)
          else
            i = str.index(open_brek)
            #p 'open brek  [str,i,d]='+[str,i,d].inspect
            if i
              k = i
              i += 1
              mode = 1
              if (i<ss) and (str[i]=='/')
                i += 1
                mode = 2
              end
              yield(:operator, index + d + k, index + d + i)
            else
              if format=='ini'
                k = str.index('=')
                j = str.index(';')
                if k and ((not j) or (k<j))
                  yield(:global, index + d, index + d + k)
                  yield(:operator, index + d + k, index + d + k + 1)
                end
                if j
                  yield(:comment, index + d + j, index + d + ss)
                end
              end
              i = ss
            end
          end
        end
        d += i
        str = str[i..-1]
        ss = str.size
      end
      mode
    end

    # Set tags for line range of TextView
    # RU: Проставить теги для диапазона строк TextView
    def set_tags(buf, line1, line2, clean=nil)
      #p 'line1, line2, view_mode='+[line1, line2, view_mode].inspect
      if (not @view_mode) and @color_mode
        buf.begin_user_action do
          line = line1
          iter1 = buf.get_iter_at_line(line)
          iterN = nil
          mode = 0
          while line<=line2
            line += 1
            if line<buf.line_count
              iterN = buf.get_iter_at_line(line)
              iter2 = buf.get_iter_at_offset(iterN.offset-1)
            else
              iter2 = buf.end_iter
              line = line2+1
            end

            text = buf.get_text(iter1, iter2)
            offset1 = iter1.offset
            buf.remove_all_tags(iter1, iter2) if clean
            #buf.apply_tag('keyword', iter1, iter2)
            case @format
              when 'ruby'
                mode = ruby_tag_line(text, offset1, mode)
              when 'python'
                mode = python_tag_line(text, offset1, mode)
              when 'bbcode', 'ini', 'html', 'xml'
                mode = bbcode_html_tag_line(text, offset1, mode, @format) do |tag, start, last|
                  buf.apply_tag(tag.to_s,
                    buf.get_iter_at_offset(start),
                    buf.get_iter_at_offset(last))
                end
              #end-case-when
            end
            #p mode
            iter1 = iterN if iterN
            #Gtk.main_iteration
          end
        end
      end
    end

    # Set buffers
    # RU: Задать буферы
    def set_buffers
      tv = body_child
      if tv and (tv.is_a? Gtk::TextView)
        tv.hide
        text_changed = false
        p '----set_buffers1  @format='+@format.inspect
        @format ||= 'bbcode'
        #if not ['markdown', 'bbcode', 'html', 'xml', 'ini', 'ruby', 'python', 'plain'].include?(@format)
          #@format = 'bbcode' #if aformat=='auto' #need autodetect here
        #end
        @tv_def_style ||= tv.modifier_style
        if view_mode
          tv.modify_style(@tv_def_style)
          tv.modify_font(nil)

          tv.tabs = @tab8_array if @tab8_array

          tv.hide
          view_buffer.text = ''
          tv.buffer = view_buffer
          tv.insert_taged_str_to_buffer(raw_buffer.text, view_buffer, @format)
          tv.set_left_border_width(tv.view_border)
          tv.show
          tv.editable = false
        else
          tv.modify_font($font_desc)
          tv.modify_base(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          tv.modify_text(Gtk::STATE_NORMAL, Gdk::Color.parse('#ffff33'))
          tv.modify_cursor(Gdk::Color.parse('#ff1111'), Gdk::Color.parse('#ff1111'))
          tv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#A0A0A0'))
          tv.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))

          @tab4_array ||= nil
          if (not @tab4_array)
            @@tab_size ||= nil
            @@tab_size ||= PandoraUtils.get_param('tab_size')
            @@tab_size ||= 4
            if @@tab_size>0
              tab_string = " " * @@tab_size
              layout = tv.create_pango_layout(tab_string)
              layout.font_description = tv.pango_context.font_description
              width, height = layout.pixel_size
              @tab4_array = Pango::TabArray.new(1, true)
              @tab4_array.set_tab(0, Pango::TAB_LEFT, width)
            end
          end
          if @tab4_array
            @tab8_array ||= tv.tabs
            tv.tabs = @tab4_array
          end

          tv.hide
          #convert_buffer(view_buffer.text, raw_buffer, false, @format)
          tv.buffer = raw_buffer
          left_bord = tv.raw_border
          left_bord ||= -3
          tv.set_left_border_width(left_bord)
          tv.show
          tv.editable = true
          raw_buffer.remove_all_tags(raw_buffer.start_iter, raw_buffer.end_iter)
          set_tags(raw_buffer, 0, raw_buffer.line_count)
        end
        fmt_btn = property_box.format_btn
        p '----set_buffers2  [@format, fmt_btn]='+[@format, fmt_btn].inspect
        fmt_btn.label = @format if (fmt_btn and (fmt_btn.label != @format))
        tv.show
        tv.grab_focus
        tv.find_panel.find_text(true) if (tv.find_panel and tv.find_panel.visible?)
      end
    end

    # Set tag for selection
    # RU: Задать тэг для выделенного
    def insert_tag(tag, params=nil, defval=nil)
      tv = body_child
      if tag and (tv.is_a? Gtk::TextView)
        if (edit_btn and view_mode)
          edit_btn.active = true
        else
          tv.set_tag(tag, params, defval, format)
        end
      end
    end

    Data = Struct.new(:font_size, :lines_per_page, :lines, :n_pages)
    HEADER_HEIGHT = 10 * 72 / 25.4
    HEADER_GAP = 3 * 72 / 25.4

    def set_page_setup
      if not @@page_setup
        @@page_setup = Gtk::PageSetup.new
        paper_size = Gtk::PaperSize.new(Gtk::PaperSize.default)
        @@page_setup.paper_size_and_default_margins = paper_size
      end
      @@page_setup = Gtk::PrintOperation::run_page_setup_dialog($window, @@page_setup)
    end

    def run_print_operation(preview=false)
      begin
        operation = Gtk::PrintOperation.new
        operation.default_page_setup = @@page_setup if @@page_setup

        operation.use_full_page = false
        operation.unit = Gtk::PaperSize::UNIT_POINTS
        operation.show_progress = true
        data = Data.new
        data.font_size = 12.0

        operation.signal_connect('begin-print') do |_operation, context|
          on_begin_print(_operation, context, data)
        end
        operation.signal_connect('draw-page') do |_operation, context, page_number|
          on_draw_page(_operation, context, page_number, data)
        end
        if preview
          operation.run(Gtk::PrintOperation::ACTION_PREVIEW, $window)
        else
          operation.run(Gtk::PrintOperation::ACTION_PRINT_DIALOG, $window)
        end
      rescue
        PandoraGtk.show_dialog($!.message)
      end
    end

    def on_begin_print(operation, context, data)
      height = context.height - HEADER_HEIGHT - HEADER_GAP
      data.lines_per_page = (height / data.font_size).floor
      p '[context.height, height, HEADER_HEIGHT, HEADER_GAP, data.lines_per_page]='+\
        [context.height, height, HEADER_HEIGHT, HEADER_GAP, data.lines_per_page].inspect
      tv = body_child
      data.lines = nil
      data.lines = tv.buffer if (tv.is_a? Gtk::TextView)
      if data.lines
        data.n_pages = (data.lines.line_count - 1) / data.lines_per_page + 1
      else
        data.n_pages = 1
      end
      operation.set_n_pages(data.n_pages)
    end

    def on_draw_page(operation, context, page_number, data)
      cr = context.cairo_context
      draw_header(cr, operation, context, page_number, data)
      draw_body(cr, operation, context, page_number, data)
    end

    def draw_header(cr, operation, context, page_number, data)
      width = context.width
      cr.rectangle(0, 0, width, HEADER_HEIGHT)
      cr.set_source_rgb(0.8, 0.8, 0.8)
      cr.fill_preserve
      cr.set_source_rgb(0, 0, 0)
      cr.line_width = 1
      cr.stroke
      layout = context.create_pango_layout
      layout.font_description = 'sans 14'
      layout.text = 'Pandora Print'
      text_width, text_height = layout.pixel_size
      if (text_width > width)
        layout.width = width
        layout.ellipsize = :start
        text_width, text_height = layout.pixel_size
      end
      y = (HEADER_HEIGHT - text_height) / 2
      cr.move_to((width - text_width) / 2, y)
      cr.show_pango_layout(layout)
      layout.text = "#{page_number + 1}/#{data.n_pages}"
      layout.width = -1
      text_width, text_height = layout.pixel_size
      cr.move_to(width - text_width - 4, y)
      cr.show_pango_layout(layout)
    end

    def draw_body(cr, operation, context, page_number, data)
      bw = self
      tv = bw.body_child
      if (not (tv.is_a? Gtk::TextView)) or bw.view_mode
        cm = Gdk::Colormap.system
        width = context.width
        height = context.height
        min_width = width
        min_width = tv.allocation.width if tv.allocation.width < min_width
        min_height = height - (HEADER_HEIGHT + HEADER_GAP)
        min_height = tv.allocation.height if tv.allocation.height < min_height
        pixbuf = Gdk::Pixbuf.from_drawable(cm, tv.window, 0, 0, min_width, \
          min_height)
        cr.set_source_color(Gdk::Color.new(65535, 65535, 65535))
        cr.gdk_rectangle(Gdk::Rectangle.new(0, HEADER_HEIGHT + HEADER_GAP, \
          context.width, height - (HEADER_HEIGHT + HEADER_GAP)))
        cr.fill

        cr.set_source_pixbuf(pixbuf, 0, HEADER_HEIGHT + HEADER_GAP)
        cr.paint
      else
        layout = context.create_pango_layout
        description = Pango::FontDescription.new('monosapce')
        description.size = data.font_size * Pango::SCALE
        layout.font_description = description

        cr.move_to(0, HEADER_HEIGHT + HEADER_GAP)
        buf = data.lines
        start_line = page_number * data.lines_per_page
        line = start_line
        iter1 = buf.get_iter_at_line(line)
        iterN = nil
        buf.begin_user_action do
          while (line<buf.line_count) and (line<start_line+data.lines_per_page)
            line += 1
            if line < buf.line_count
              iterN = buf.get_iter_at_line(line)
              iter2 = buf.get_iter_at_offset(iterN.offset-1)
            else
              iter2 = buf.end_iter
            end
            text = buf.get_text(iter1, iter2)
            text = (line.to_s+':').ljust(6, ' ')+text.to_s
            layout.text = text
            cr.show_pango_layout(layout)
            cr.rel_move_to(0, data.font_size)
            iter1 = iterN
          end
        end
      end
    end

  end

  SexList = [[1, _('man')], [0, _('woman')], [2, _('gay')], [3, _('trans')], [4, _('lesbo')]]

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class PropertyBox < Gtk::VBox
    include PandoraModel

    attr_accessor :panobject, :vbox, :fields, :text_fields, :statusbar, \
      :rate_label, :lang_entry, :last_sw, :rate_btn, :format_btn, :save_btn, \
      :last_width, :last_height, :notebook, :tree_view, :edit, \
      :keep_btn, :follow_btn, :vouch0, :vouch_btn, :vouch_scale, :public0, \
      :public_btn, :public_scale, :ignore_btn, :arch_btn, :panhash0, :obj_id,
      :panstate

    # Create fields dialog
    # RU: Создать форму с полями
    def initialize(apanobject, afields, apanhash0, an_id, an_edit=nil, anotebook=nil, \
    atree_view=nil, awidth_loss=nil, aheight_loss=nil)
      super()
      kind = nil
      if apanobject.is_a?(Integer)
        kind = apanobject
        apanobject = nil
      elsif apanobject
        kind = apanobject.kind
      elsif apanhash0
        kind = PandoraUtils.kind_from_panhash(apanhash0)
      end
      if apanobject.nil?
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          apanobject = PandoraUtils.get_model(panobjectclass.ider)
        end
      end
      @vbox = self
      @panobject = apanobject
      @notebook = anotebook
      @tree_view = atree_view
      @panhash0 = apanhash0
      @obj_id = an_id
      @edit = an_edit
      @width_loss = awidth_loss
      @height_loss = aheight_loss
      @fields = afields
      init_fields(kind)

      if afields.nil?
        search_btn = Gtk::Button.new(_('Request the record only'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request(PandoraNet::SRO_Record, @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 12)
        search_btn = Gtk::Button.new(_('Request the record with avatars'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Avatars), @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 2)
        search_btn = Gtk::Button.new(_('Request the record with relations'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Relations), @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 2)
        search_btn = Gtk::Button.new(_('Request the record with opinions'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Opinions), @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 12)
        search_btn = Gtk::Button.new(_('Request the record with relations and avatars'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Avatars | \
            PandoraNet::SRO_Relations), @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 2)
        search_btn = Gtk::Button.new(_('Request the record with relations and opinions'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Opinions | \
            PandoraNet::SRO_Relations), @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 2)
        search_btn = Gtk::Button.new(_('Request the record with relations, avatars and opinions'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Opinions | \
            PandoraNet::SRO_Relations | PandoraNet::SRO_Avatars), @panhash0)
          false
        end
        @vbox.pack_start(search_btn, false, false, 2)
        search_btn = Gtk::Button.new(_('Read the record'))
        search_btn.width_request = 110
        search_btn.signal_connect('clicked') do |*args|
          init_fields
          false
        end
        @vbox.pack_start(search_btn, false, false, 12)
      end
    end

    def init_fields(kind)
      if @fields.nil?
        sel = PandoraModel.get_record_by_panhash(@panhash0, kind)
        if sel.is_a?(Array) and (sel.size>0) and @panobject
          @fields = @panobject.get_fields_as_view(sel[0], @edit, @panhash0)
        end
      end
      if @fields
        init_field_widgets(kind)
      end
    end

    def init_field_widgets(kind)
      @vbox.hide_all
      @vbox.child_visible = false
      @vbox.each do |child|
        child.destroy
      end
      @vbox.child_visible = true
      #@vbox.show_all

      page_sw = nil
      page_sw = @tree_view.page_sw if @tree_view
      dialog = nil
      dialog = page_sw.parent.parent.parent if page_sw

      #@statusbar = Gtk::Statusbar.new
      #PandoraGtk.set_statusbar_text(statusbar, '')
      #statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      #@rate_btn = Gtk::Button.new(_('Rate')+':')
      #rate_btn.relief = Gtk::RELIEF_NONE
      #statusbar.pack_start(rate_btn, false, false, 0)
      #panelbox.pack_start(statusbar, false, false, 0)

      # devide text fields in separate list
      @panstate = 0
      @text_fields = Array.new
      i = @fields.size
      while i>0 do
        i -= 1
        field = @fields[i]
        atext = field[PandoraUtils::FI_VFName]
        aview = field[PandoraUtils::FI_View]
        if (aview=='blob') or (aview=='text')
          bodywin = BodyScrolledWindow.new(self, @fields, nil, nil)
          bodywin.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          bodywin.field = field
          field[PandoraUtils::FI_Widget2] = bodywin
          if notebook
            label_box = TabLabelBox.new(Gtk::Stock::DND, atext, nil)
            page = notebook.append_page(bodywin, label_box)
          end
          @text_fields << field
        end
        if (field[PandoraUtils::FI_Id]=='panstate')
          val = field[PandoraUtils::FI_Value]
          @panstate = val.to_i if (val and (val.size>0))
        end
      end

      self.signal_connect('key-press-event') do |widget, event|
        btn = nil
        case event.keyval
          when Gdk::Keyval::GDK_F5
            btn = PandoraGtk.find_tool_btn(toolbar, 'Edit')
        end
        if btn.is_a? Gtk::ToggleToolButton
          btn.active = (not btn.active?)
        elsif btn.is_a? Gtk::ToolButton
          btn.clicked
        end
        res = (not btn.nil?)
      end

      # create labels, remember them, calc middle char width
      texts_width = 0
      texts_chars = 0
      labels_width = 0
      max_label_height = 0
      @fields.each do |field|
        atext = field[PandoraUtils::FI_VFName]
        aview = field[PandoraUtils::FI_View]
        label = Gtk::Label.new(atext)
        label.tooltip_text = aview if aview and (aview.size>0)
        label.xalign = 0.0
        lw,lh = label.size_request
        field[PandoraUtils::FI_Label] = label
        field[PandoraUtils::FI_LabW] = lw
        field[PandoraUtils::FI_LabH] = lh
        texts_width += lw
        texts_chars += atext.length
        #texts_chars += atext.length
        labels_width += lw
        max_label_height = lh if max_label_height < lh
      end
      @middle_char_width = (texts_width.to_f*1.2 / texts_chars).round

      # max window size
      scr = Gdk::Screen.default
      @width_loss = 40 if (@width_loss.nil? or (@width_loss<10))
      @height_loss = 150 if (@height_loss.nil? or (@height_loss<10))
      @last_width, @last_height = [scr.width-@width_loss-40, scr.height-@height_loss-70]

      # compose first matrix, calc its geometry
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @def_widget = nil
      @fields.each do |field|
        #p 'field='+field.inspect
        max_size = 0
        fld_size = 0
        aview = field[PandoraUtils::FI_View]
        atype = field[PandoraUtils::FI_Type]
        entry = nil
        amodal = false
        if dialog and dialog.is_a?(AdvancedDialog) and dialog.okbutton
          amodal = true #(not notebook.nil?)
        end
        case aview
          when 'integer', 'byte', 'word'
            entry = IntegerEntry.new
          when 'hex'
            entry = HexEntry.new
          when 'real'
            entry = FloatEntry.new
          when 'time'
            entry = DateTimeEntry.new
          when 'datetime'
            entry = DateTimeBox.new(amodal)
          when 'date'
            entry = DateEntry.new(amodal)
          when 'coord'
            its_city = (panobject and (panobject.is_a? PandoraModel::City)) \
              or (kind==PandoraModel::PK_City)
            entry = CoordBox.new(amodal, its_city)
          when 'filename', 'blob'
            entry = FilenameBox.new(window, amodal) do |filename, entry, button, filename0|
              name_fld = @panobject.field_des('name', @fields)
              if (name_fld.is_a? Array) and (name_fld[PandoraUtils::FI_Widget].is_a? Gtk::Entry)
                name_ent = name_fld[PandoraUtils::FI_Widget]
                old_name = File.basename(filename0)
                old_name2 = File.basename(filename0, '.*')
                new_name = File.basename(filename)
                if ((name_ent.text=='') or (name_ent.text==filename0) \
                or (name_ent.text==old_name) or (name_ent.text==old_name2))
                  name_ent.text = new_name
                end
              end
            end
          when 'base64'
            entry = Base64Entry.new
          when 'phash', 'panhash'
            if field[PandoraUtils::FI_Id]=='panhash'
              entry = HexEntry.new
              #entry.editable = false
            else
              entry = PanhashBox.new(atype, amodal)
            end
          when 'bytelist'
            if field[PandoraUtils::FI_Id]=='panhash_lang'
              entry = ByteListEntry.new(PandoraModel.lang_code_list, amodal)
            elsif field[PandoraUtils::FI_Id]=='sex'
              entry = ByteListEntry.new(SexList, amodal)
            elsif field[PandoraUtils::FI_Id]=='kind'
              entry = ByteListEntry.new(PandoraModel::RelationNames, amodal)
            elsif field[PandoraUtils::FI_Id]=='mode'
              entry = ByteListEntry.new(PandoraModel::TaskModeNames, amodal)
            else
              entry = IntegerEntry.new
            end
          else
            entry = Gtk::Entry.new
        end
        @def_widget ||= entry
        begin
          def_size = 10
          case atype
            when 'Integer'
              def_size = 10
            when 'String'
              def_size = 32
            when 'Filename' , 'Blob', 'Text'
              def_size = 256
          end
          fld_size = field[PandoraUtils::FI_FSize].to_i if field[PandoraUtils::FI_FSize]
          max_size = field[PandoraUtils::FI_Size].to_i
          max_size = fld_size if (max_size==0)
          fld_size = def_size if (fld_size<=0)
          max_size = fld_size if (max_size<fld_size) and (max_size>0)
        rescue
          fld_size = def_size
        end
        #entry.width_chars = fld_size
        entry.max_length = max_size if max_size>0
        color = field[PandoraUtils::FI_Color]
        if color
          color = Gdk::Color.parse(color)
        else
          color = nil
        end
        #entry.modify_fg(Gtk::STATE_ACTIVE, color)
        entry.modify_text(Gtk::STATE_NORMAL, color)

        ew = fld_size*@middle_char_width
        ew = last_width if ew > last_width
        entry.width_request = ew if ((fld_size != 44) and (not (entry.is_a? PanhashBox)))
        ew,eh = entry.size_request
        #p 'Final [fld_size, max_size, ew]='+[fld_size, max_size, ew].inspect
        #p '[view, ew,eh]='+[aview, ew,eh].inspect
        field[PandoraUtils::FI_Widget] = entry
        field[PandoraUtils::FI_WidW] = ew
        field[PandoraUtils::FI_WidH] = eh
        entries_width += ew
        max_entry_height = eh if max_entry_height < eh
        text = field[PandoraUtils::FI_Value].to_s
        #if (atype=='Blob') or (atype=='Text')
        if (aview=='blob') or (aview=='text')
          entry.text = text[1..-1] if text and (text.size<1024) and (text[0]=='@')
        else
          entry.text = text
        end
      end

      # calc matrix sizes
      #field_matrix = Array.new
      mw, mh = 0, 0
      row = Array.new
      row_index = -1
      rw, rh = 0, 0
      orient = :up
      @fields.each_index do |index|
        field = @fields[index]
        if (index==0) or (field[PandoraUtils::FI_NewRow]==1)
          row_index += 1
          #field_matrix << row if row != []
          mw, mh = [mw, rw].max, mh+rh
          row = []
          rw, rh = 0, 0
        end

        if not [:up, :down, :left, :right].include?(field[PandoraUtils::FI_LabOr])
          field[PandoraUtils::FI_LabOr] = orient
        end
        orient = field[PandoraUtils::FI_LabOr]

        field_size = calc_field_size(field)
        rw, rh = rw+field_size[0], [rh, field_size[1]+1].max
        row << field
      end
      #field_matrix << row if row != []
      mw, mh = [mw, rw].max, mh+rh
      if (mw<=last_width) and (mh<=last_height) then
        @last_width, @last_height = mw+10, mh+10
      end

      #self.signal_connect('check-resize') do |widget|
      #self.signal_connect('configure-event') do |widget, event|
      #self.signal_connect('notify::position') do |widget, param|
      #self.signal_connect('expose-event') do |widget, param|
      #self.signal_connect('size-request') do |widget, requisition|
      self.signal_connect('size-allocate') do |widget, allocation|
        self.on_resize
        false
      end

      @old_field_matrix = []
    end

    def set_status_icons
      @panstate ||= 0
      if edit
        count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
        if rate_btn and rate.is_a? Float
          rate_btn.label = _('Rate')+': '+rate.round(2).to_s
        #dialog.rate_label.text = rate.to_s
        end

        if vouch_btn
          trust = nil
          trust_or_num = PandoraCrypto.trust_to_panobj(panhash0)
          #p '====trust_or_num='+[panhash0, trust_or_num].inspect
          trust = trust_or_num if (trust_or_num.is_a? Float)
          vouch_btn.safe_set_active((trust_or_num != nil))
          #vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
          vouch_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          vouch_scale.scale.value = trust
        end

        keep_btn.safe_set_active((PandoraModel::PSF_Support & panstate)>0) if keep_btn
        arch_btn.safe_set_active((PandoraModel::PSF_Archive & panstate)>0) if arch_btn

        if public_btn
          pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
          public_btn.safe_set_active(pub_level)
          public_scale.sensitive = pub_level
          if pub_level
            #p '====pub_level='+pub_level.inspect
            #public_btn.inconsistent = (pub_level == nil)
            public_scale.scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
          end
        end

        if follow_btn
          follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
          follow_btn.safe_set_active(follow)
        end

        if ignore_btn
          ignore = PandoraModel.act_relation(nil, panhash0, RK_Ignore, :check)
          ignore_btn.safe_set_active(ignore)
        end

        lang_entry.active_text = lang.to_s if lang_entry
        #trust_lab = dialog.trust_btn.children[0]
        #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
      else  #new or copy
        key = PandoraCrypto.current_key(false, false)
        key_inited = (key and key[PandoraCrypto::KV_Obj])
        keep_btn.safe_set_active(true) if keep_btn
        follow_btn.safe_set_active(key_inited) if follow_btn
        vouch_btn.safe_set_active(key_inited) if vouch_btn
        vouch_scale.sensitive = key_inited if vouch_scale
        if follow_btn and (not key_inited)
          follow_btn.sensitive = false
          vouch_btn.sensitive = false
          public_btn.sensitive = false
          ignore_btn.sensitive = false
        end
      end

      #!!!st_text = panobject.panhash_formula
      #!!!st_text = st_text + ' [#'+panobject.calc_panhash(sel[0], lang, \
      #  true, true)+']' if sel and sel.size>0
      #!!PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

      #if panobject.is_a? PandoraModel::Key
      #  mi = Gtk::MenuItem.new("Действия")
      #  menu = Gtk::MenuBar.new
      #  menu.append(mi)

      #  menu2 = Gtk::Menu.new
      #  menuitem = Gtk::MenuItem.new("Генерировать")
      #  menu2.append(menuitem)
      #  mi.submenu = menu2
      #  #p dialog.action_area
      #  dialog.hbox.pack_end(menu, false, false)
      #  #dialog.action_area.add(menu)
      #end

      titadd = nil
      if not edit
      #  titadd = _('edit')
      #else
        titadd = _('new')
      end
      #!!dialog.title += ' ('+titadd+')' if titadd and (titadd != '')
    end

    # Calculate field size
    # RU: Вычислить размер поля
    def calc_field_size(field)
      lw = field[PandoraUtils::FI_LabW]
      lh = field[PandoraUtils::FI_LabH]
      ew = field[PandoraUtils::FI_WidW]
      eh = field[PandoraUtils::FI_WidH]
      if (field[PandoraUtils::FI_LabOr]==:left) or (field[PandoraUtils::FI_LabOr]==:right)
        [lw+ew, [lh,eh].max]
      else
        field_size = [[lw,ew].max, lh+eh]
      end
    end

    # Calculate row size
    # RU: Вычислить размер ряда
    def calc_row_size(row)
      rw, rh = [0, 0]
      row.each do |fld|
        fs = calc_field_size(fld)
        rw, rh = rw+fs[0], [rh, fs[1]].max
      end
      [rw, rh]
    end

    # Event on resize window
    # RU: Событие при изменении размеров окна
    def on_resize(view_width=nil, view_height=nil, force=nil)
      view_width ||= parent.allocation.width
      view_height ||= parent.allocation.height
      if (@fields and ((view_width != last_width) or (view_height != last_height) or force) \
      and (@pre_last_width.nil? or @pre_last_height.nil? \
      or ((view_width != @pre_last_width) and (view_height != @pre_last_height))))
        #p '----------RESIZE [view_width, view_height, last_width, last_height, parent]='+\
        #  [view_width, view_height, last_width, last_height, parent].inspect
        @pre_last_width, @pre_last_height = last_width, last_height
        @last_width, @last_height = view_width, view_height

        form_width = last_width-30
        form_height = last_height-65

        # create and fill field matrix to merge in form
        step = 1
        found = false
        while not found do
          fields = Array.new
          @fields.each do |field|
            fields << field.dup
          end

          field_matrix = Array.new
          mw, mh = 0, 0
          case step
            when 1  #normal compose. change "left" to "up" when doesn't fit to width
              row = Array.new
              row_index = -1
              rw, rh = 0, 0
              orient = :up
              fields.each_with_index do |field, index|
                if (index==0) or (field[PandoraUtils::FI_NewRow]==1)
                  row_index += 1
                  field_matrix << row if row != []
                  mw, mh = [mw, rw].max, mh+rh
                  #p [mh, form_height]
                  if (mh>form_height)
                    #step = 2
                    step = 5
                    break
                  end
                  row = Array.new
                  rw, rh = 0, 0
                end

                if (not [:up, :down, :left, :right].include?(field[PandoraUtils::FI_LabOr]))
                  field[PandoraUtils::FI_LabOr]=orient
                end
                orient = field[PandoraUtils::FI_LabOr]

                field_size = calc_field_size(field)
                rw, rh = rw+field_size[0], [rh, field_size[1]].max
                row << field

                if rw>form_width
                  col = row.size
                  while (col>0) and (rw>form_width)
                    col -= 1
                    fld = row[col]
                    if [:left, :right].include?(fld[PandoraUtils::FI_LabOr])
                      fld[PandoraUtils::FI_LabOr]=:up
                      rw, rh = calc_row_size(row)
                    end
                  end
                  if (rw>form_width)
                    #step = 3
                    step = 5
                    break
                  end
                end
              end
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              if (mh>form_height) or (mw>form_width)
                #step = 2
                step = 5
              end
              found = (step==1)
            when 2
              found = true
            when 3
              found = true
            when 5  #need to rebuild rows by width
              row = Array.new
              row_index = -1
              rw, rh = 0, 0
              orient = :up
              fields.each_with_index do |field, index|
                if ! [:up, :down, :left, :right].include?(field[PandoraUtils::FI_LabOr])
                  field[PandoraUtils::FI_LabOr] = orient
                end
                orient = field[PandoraUtils::FI_LabOr]
                field_size = calc_field_size(field)

                if (rw+field_size[0]>form_width)
                  row_index += 1
                  field_matrix << row if row != []
                  mw, mh = [mw, rw].max, mh+rh
                  #p [mh, form_height]
                  row = Array.new
                  rw, rh = 0, 0
                end

                row << field
                rw, rh = rw+field_size[0], [rh, field_size[1]].max

              end
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              found = true
            else
              found = true
          end
        end

        matrix_is_changed = @old_field_matrix.size != field_matrix.size
        if not matrix_is_changed
          field_matrix.each_index do |rindex|
            row = field_matrix[rindex]
            orow = @old_field_matrix[rindex]
            if row.size != orow.size
              matrix_is_changed = true
              break
            end
            row.each_index do |findex|
              field = row[findex]
              ofield = orow[findex]
              if (field[PandoraUtils::FI_LabOr] != ofield[PandoraUtils::FI_LabOr]) \
                or (field[PandoraUtils::FI_LabW] != ofield[PandoraUtils::FI_LabW]) \
                or (field[PandoraUtils::FI_LabH] != ofield[PandoraUtils::FI_LabH]) \
                or (field[PandoraUtils::FI_WidW] != ofield[PandoraUtils::FI_WidW]) \
                or (field[PandoraUtils::FI_WidH] != ofield[PandoraUtils::FI_WidH]) \
              then
                matrix_is_changed = true
                break
              end
            end
            if matrix_is_changed then break; end
          end
        end

        # compare matrix with previous
        if matrix_is_changed
          #p "----+++++redraw"
          @old_field_matrix = field_matrix

          #!!!@def_widget = focus if focus

          # delete sub-containers
          if @vbox.children.size>0
            @vbox.hide_all
            @vbox.child_visible = false
            @fields.each_index do |index|
              field = @fields[index]
              label = field[PandoraUtils::FI_Label]
              entry = field[PandoraUtils::FI_Widget]
              label.parent.remove(label) if label and label.parent
              entry.parent.remove(entry) if entry and entry.parent
            end
            @vbox.each do |child|
              child.destroy
            end
          end

          # show field matrix on form
          field_matrix.each do |row|
            row_hbox = Gtk::HBox.new
            row.each_index do |field_index|
              field = row[field_index]
              label = field[PandoraUtils::FI_Label]
              entry = field[PandoraUtils::FI_Widget]
              if (field[PandoraUtils::FI_LabOr]==nil) or (field[PandoraUtils::FI_LabOr]==:left)
                row_hbox.pack_start(label, false, false, 2)
                row_hbox.pack_start(entry, false, false, 2)
              elsif (field[PandoraUtils::FI_LabOr]==:right)
                row_hbox.pack_start(entry, false, false, 2)
                row_hbox.pack_start(label, false, false, 2)
              else
                field_vbox = Gtk::VBox.new
                if (field[PandoraUtils::FI_LabOr]==:down)
                  field_vbox.pack_start(entry, false, false, 2)
                  field_vbox.pack_start(label, false, false, 2)
                else
                  field_vbox.pack_start(label, false, false, 2)
                  field_vbox.pack_start(entry, false, false, 2)
                end
                row_hbox.pack_start(field_vbox, false, false, 2)
              end
            end
            @vbox.pack_start(row_hbox, false, false, 2)
          end
          @vbox.child_visible = true
          @vbox.show_all
          if (@def_widget and (not @def_widget.destroyed?))
            #focus = @def_widget
            @def_widget.grab_focus
          end
        end
      end
    end

    # Save raw fields with form flags, sign and relations
    # RU: Сохранить сырые поля с флагами формы, подписью и связями
    def save_flds_with_form_flags(flds_hash, lang=nil, created0=nil)
      time_now = Time.now.to_i
      if (panobject.is_a? PandoraModel::Created)
        if created0 and flds_hash['created'] \
        and ((flds_hash['created'].to_i-created0.to_i).abs<=1)
          flds_hash['created'] = created0
        end
        #if not edit
          #flds_hash['created'] = time_now
          #creator = PandoraCrypto.current_user_or_key(true)
          #flds_hash['creator'] = creator
        #end
      end
      flds_hash['modified'] = time_now

      @panstate = flds_hash['panstate']
      panstate ||= 0
      if keep_btn and keep_btn.sensitive?
        if keep_btn.active?
          panstate = (panstate | PandoraModel::PSF_Support)
        else
          panstate = (panstate & (~ PandoraModel::PSF_Support))
        end
      end
      if arch_btn and arch_btn.sensitive?
        if arch_btn.active?
          panstate = (panstate | PandoraModel::PSF_Archive)
        else
          panstate = (panstate & (~ PandoraModel::PSF_Archive))
        end
      end
      flds_hash['panstate'] = panstate

      lang ||= 0
      if (panobject.is_a? PandoraModel::Key)
        lang = flds_hash['rights'].to_i
      elsif (panobject.is_a? PandoraModel::Currency)
        lang = 0
      end

      panhash = panobject.calc_panhash(flds_hash, lang)
      flds_hash['panhash'] = panhash

      if (panobject.is_a? PandoraModel::Key) and panhash0 \
      and (flds_hash['kind'].to_i == PandoraCrypto::KT_Priv) and edit
        flds_hash['panhash'] = panhash0
      end

      filter = nil
      filter = {:id=>@obj_id.to_i} if (edit and @obj_id)
      if filter.nil?
        filter ||= {:panhash => panhash}
        sel = panobject.select(filter, false, 'id', 'id DESC', 1)
        if sel and (sel.size>0)
          @obj_id = sel[0][0]
          filter = {:id=>@obj_id}
        else
          filter = nil
        end
      end
      #filter = {:panhash=>panhash} if filter.nil?
      res = panobject.update(flds_hash, nil, filter, true)

      if res
        filter ||= {:panhash => panhash, :modified => time_now}
        sel = panobject.select(filter, true, nil, 'id DESC', 1)
        if sel and (sel.size>0)
          row = sel[0]
          id = panobject.field_val('id', row)  #panobject.namesvalues['id']

          if filter[:id].nil? and @edit and panhash0 and (panhash != panhash0)
            p '==The record is changed'
            if (panstate & PandoraModel::PSF_Archive)>0
              p 'This is an archive record. Old record is deleting'
              res = panobject.update(nil, nil, {:panhash => panhash0})
            else
              p 'This is work record. Old record is moving to archive'
              PandoraModel.set_panstate_for_panhash(panhash0, nil, \
                PandoraModel::PSF_Archive, PandoraModel::PSF_Support)
            end
          end

          #p 'panobject.namesvalues='+panobject.namesvalues.inspect
          #p 'panobject.matter_fields='+panobject.matter_fields.inspect

          @obj_id = id.to_i if (id and ((not @edit) or @obj_id.nil?))
          @edit = true

          #put saved values to widgets
          @fields = panobject.get_fields_as_view(row, true, panhash, @fields)
          @fields.each do |form_fld|
            entry = form_fld[PandoraUtils::FI_Widget]
            if entry and (not entry.destroyed?)
              aview = form_fld[PandoraUtils::FI_View]
              text = form_fld[PandoraUtils::FI_Value].to_s
              if (aview=='blob') or (aview=='text')
                entry.text = text[1..-1] if text and (text.size<1024) and (text[0]=='@')
              else
                entry.text = text
              end
            end
          end

          if tree_view and (not tree_view.destroyed?)
            path, column = tree_view.cursor
            iter = nil
            store = tree_view.model
            iter = store.get_iter(path) if store and path
            if iter
              #p 'id='+id.inspect
              #p 'id='+id.inspect
              ind = tree_view.sel.index { |row| row[0]==obj_id }
              #p 'ind='+ind.inspect
              if ind
                #p '---------CHANGE'
                row.each_with_index do |c,i|
                  tree_view.sel[ind][i] = c
                end
                iter[0] = obj_id
                store.row_changed(path, iter)
              else
                #p '---------INSERT'
                tree_view.sel << row
                iter = store.append
                iter[0] = obj_id
                tree_view.set_cursor(Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
              end
            else
              tree_view.page_sw.update_treeview if tree_view.page_sw
            end
          end

          if vouch_btn and vouch_btn.sensitive? and vouch_scale
            PandoraCrypto.unsign_panobject(panhash0, true) if panhash0
            if vouch_btn.active?
              trust = vouch_scale.scale.value
              trust = PandoraModel.transform_trust(trust, :float_to_int)
              PandoraCrypto.sign_panobject(panobject, trust)
            end
          end

          if follow_btn and follow_btn.sensitive?
            PandoraModel.act_relation(nil, panhash0, RK_Follow, :delete, \
              true, true) if panhash0
            if panhash0 and (panhash != panhash0)
              PandoraModel.act_relation(nil, panhash, RK_Follow, :delete, \
                true, true)
            end
            if follow_btn.active?
              PandoraModel.act_relation(nil, panhash, RK_Follow, :create, \
                true, true)
            end
          end

          if public_btn and public_btn.sensitive?
            PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :delete, \
              true, true) if panhash0
            if panhash0 and (panhash != panhash0)
              PandoraModel.act_relation(nil, panhash, RK_MinPublic, :delete, \
                true, true)
            end
            if public_btn.active? and public_scale
              public_level = PandoraModel.trust2_to_pub235(public_scale.scale.value)
              p 'public_level='+public_level.inspect
              PandoraModel.act_relation(nil, panhash, public_level, :create, \
                true, true)
            end
          end

          if ignore_btn and ignore_btn.sensitive?
            PandoraModel.act_relation(nil, panhash, RK_Ignore, :delete, \
              true, true)
            PandoraModel.act_relation(nil, panhash, RK_Ignore, :create, \
              true, true) if ignore_btn.active?
          end

        end
        @panhash0 = panhash
      else
        panhash = nil
      end
      panhash
    end

    # Save entered fields and flags to database
    # RU: Сохранить введённые поля и флаги в базу данных
    def save_form_fields_with_flags_to_database(created0=nil, row=nil)
      # view_fields to raw_fields and hash
      flds_hash = {}
      file_way = nil
      file_way_exist = nil
      lang = nil

      row ||= fields
      fields.each do |field|
        fld_id = field[PandoraUtils::FI_Id]
        val = nil
        entry = field[PandoraUtils::FI_Widget]
        if entry and (not entry.destroyed?)
          val = entry.text
          if (fld_id=='panhash_lang')
            begin
              lang = val.to_i if val.size>0
            rescue
              lang = nil
            end
          else
            type = field[PandoraUtils::FI_Type]
            view = field[PandoraUtils::FI_View]
            if ((panobject.kind==PK_Relation) and val \
            and ((fld_id=='first') or (fld_id=='second')))
              PandoraModel.del_image_from_cache(val, true)
            elsif (panobject.kind==PK_Parameter) and (fld_id=='value')
              par_type = panobject.field_val('type', row)
              setting = panobject.field_val('setting', row)
              ps = PandoraUtils.decode_param_setting(setting)
              view = ps['view']
              view ||= PandoraUtils.pantype_to_view(par_type)
            elsif file_way
              p 'file_way2='+file_way.inspect
              if (fld_id=='type')
                val = PandoraUtils.detect_file_type(file_way) if (not val) or (val.size==0)
              elsif (fld_id=='sha1')
                if file_way_exist
                  sha1 = Digest::SHA1.file(file_way)
                  val = sha1.hexdigest
                else
                  val = nil
                end
              elsif (fld_id=='md5')
                if file_way_exist
                  md5 = Digest::MD5.file(file_way)
                  val = md5.hexdigest
                else
                  val = nil
                end
              elsif (fld_id=='size')
                val = File.size?(file_way)
              end
            end
            #p 'fld, val, type, view='+[fld_id, val, type, view].inspect
            val = PandoraUtils.view_to_val(val, type, view)
            if (view=='blob') or (view=='text')
              if val and (val.size>0)
                file_way = PandoraUtils.absolute_path(val)
                file_way_exist = File.exist?(file_way)
                #p 'file_way1='+file_way.inspect
                val = '@'+val
                flds_hash[fld_id] = val
                field[PandoraUtils::FI_Value] = val
                #p '----TEXT ENTR!!!!!!!!!!!'
              else
                flds_hash[fld_id] = field[PandoraUtils::FI_Value]
              end
            else
              flds_hash[fld_id] = val
              field[PandoraUtils::FI_Value] = val
            end
          end
        end
      end

      # add text and blob fields
      text_fields.each do |field|
        fld_id = field[PandoraUtils::FI_Id]
        file_way = flds_hash[fld_id]
        if file_way and (file_way.size>1) and (file_way[0]=='@')
          val = file_way[1..-1]
          file_way = PandoraUtils.absolute_path(val)
        else
          file_way = nil
        end
        #entry = field[PandoraUtils::FI_Widget]
        #if entry.text == ''
        body_win = field[PandoraUtils::FI_Widget2]
        if body_win and body_win.destroyed?
          body_win = nil
          field[PandoraUtils::FI_Widget2] = nil
        end
        #text = flds_hash[fld_id]
        #p '====(entry.text == '')  body_win, body_win.destroyed?, body_win.raw_buffer, text='+\
        #  [body_win, body_win.destroyed?, body_win.raw_buffer, text].inspect
        if (body_win.is_a? BodyScrolledWindow) and body_win.raw_buffer
          #text = textview.buffer.text
          text = body_win.raw_buffer.text
          #p '---text='+text.inspect
          if text and (text.size>0) and (text[0] != '@')
            type_fld = panobject.field_des('type')
            flds_hash['type'] = body_win.property_box.format_btn.label.upcase if type_fld

            if file_way
              begin
                File.open(file_way, 'wb') do |file|
                  #p '---[file_way, file.methods, text.size]='+[file_way, file.methods, text.size].inspect
                  if PandoraUtils.os_family == 'windows'
                    text = PandoraUtils.correct_newline_codes(text, false)
                  else
                    text = AsciiString.new(text)
                  end
                  file.write(text)
                end
              rescue => err
                PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot save text to file')+\
                  '['+file_way+']: '+Utf8String.new(err.message))
                file_way = nil
              end
            end

            if (not file_way)
              flds_hash[fld_id] = text
              field[PandoraUtils::FI_Value] = text
            end

            sha1_fld = panobject.field_des('sha1')
            flds_hash['sha1'] = Digest::SHA1.digest(text) if sha1_fld
            md5_fld = panobject.field_des('md5')
            flds_hash['md5'] = Digest::MD5.digest(text) if md5_fld
            size_fld = panobject.field_des('size')
            flds_hash['size'] = text.size if size_fld
          end
        end
      end

      if (not lang.is_a? Integer) or (lang<0) or (lang>255)
        lang = PandoraModel.text_to_lang($lang)
      end

      panhash = self.save_flds_with_form_flags(flds_hash, lang, created0)

      if panhash.is_a?(String)
        PandoraUI.log_message(PandoraUI::LM_Info, _('Record saved')+' '+PandoraUtils.bytes_to_hex(panhash))
      end
      panhash
    end

  end

  # Ask user and password for key pair generation
  # RU: Запросить пользователя и пароль для генерации ключевой пары
  def self.ask_user_and_password(rights=nil)
    dialog = PandoraGtk::AdvancedDialog.new(_('Key generation'))
    dialog.set_default_size(450, 250)
    dialog.icon = $window.get_preset_icon('key')

    vbox = Gtk::VBox.new
    dialog.viewport.add(vbox)

    #creator = PandoraUtils.bigint_to_bytes(0x01052ec783d34331de1d39006fc80000000000000000)
    label = Gtk::Label.new(_('Person panhash'))
    vbox.pack_start(label, false, false, 2)
    user_entry = PandoraGtk::PanhashBox.new('Panhash(Person)')
    #user_entry.text = PandoraUtils.bytes_to_hex(creator)
    vbox.pack_start(user_entry, false, false, 2)

    rights ||= (PandoraCrypto::KS_Exchange | PandoraCrypto::KS_Voucher)

    label = Gtk::Label.new(_('Key credentials'))
    vbox.pack_start(label, false, false, 2)

    hbox = Gtk::HBox.new

    voucher_btn = Gtk::CheckButton.new(_('voucher'), true)
    voucher_btn.active = ((rights & PandoraCrypto::KS_Voucher)>0)
    hbox.pack_start(voucher_btn, true, true, 2)

    exchange_btn = Gtk::CheckButton.new(_('exchange'), true)
    exchange_btn.active = ((rights & PandoraCrypto::KS_Exchange)>0)
    hbox.pack_start(exchange_btn, true, true, 2)

    robotic_btn = Gtk::CheckButton.new(_('robotic'), true)
    robotic_btn.active = ((rights & PandoraCrypto::KS_Robotic)>0)
    hbox.pack_start(robotic_btn, true, true, 2)

    vbox.pack_start(hbox, false, false, 2)

    label = Gtk::Label.new(_('Password')+' ('+_('optional')+')')
    vbox.pack_start(label, false, false, 2)
    pass_entry = Gtk::Entry.new
    pass_entry.width_request = 250
    align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
    align.add(pass_entry)
    vbox.pack_start(align, false, false, 2)
    #vbox.pack_start(pass_entry, false, false, 2)

    agree_btn = Gtk::CheckButton.new(_('I agree to publish the person name'), true)
    agree_btn.active = true
    agree_btn.signal_connect('clicked') do |widget|
      dialog.okbutton.sensitive = widget.active?
    end
    vbox.pack_start(agree_btn, false, false, 2)

    dialog.def_widget = user_entry.entry

    dialog.run2 do
      creator = PandoraUtils.hex_to_bytes(user_entry.text)
      if creator.size==PandoraModel::PanhashSize
        rights = 0
        rights = (rights | PandoraCrypto::KS_Exchange) if exchange_btn.active?
        rights = (rights | PandoraCrypto::KS_Voucher) if voucher_btn.active?
        rights = (rights | PandoraCrypto::KS_Robotic) if robotic_btn.active?
        yield(creator, pass_entry.text, rights) if block_given?
      else
        PandoraGtk.show_dialog(_('Panhash must consist of 44 symbols')) do
          PandoraGtk.show_panobject_list(PandoraModel::Person, nil, nil, true)
        end
      end
    end
  end

  # Ask key and password for authorization
  # RU: Запросить ключ и пароль для авторизации
  def self.ask_key_and_password(alast_auth_key=nil, cipher=nil)
    dialog = PandoraGtk::AdvancedDialog.new(_('Key init'))
    dialog.set_default_size(450, 190)
    dialog.icon = $window.get_preset_icon('auth')

    vbox = Gtk::VBox.new
    dialog.viewport.add(vbox)

    label = Gtk::Label.new(_('Key'))
    vbox.pack_start(label, false, false, 2)
    key_entry = PandoraGtk::PanhashBox.new('Panhash(Key)')
    if alast_auth_key
      key_entry.text = PandoraUtils.bytes_to_hex(alast_auth_key)
    end
    #key_entry.editable = false

    vbox.pack_start(key_entry, false, false, 2)

    label = Gtk::Label.new(_('Password'))
    vbox.pack_start(label, false, false, 2)
    pass_entry = Gtk::Entry.new
    pass_entry.visibility = false

    dialog_timer = nil
    key_entry.entry.signal_connect('changed') do |widget, event|
      if dialog_timer.nil?
        dialog_timer = GLib::Timeout.add(1000) do
          if not key_entry.destroyed?
            panhash2 = PandoraModel.hex_to_panhash(key_entry.text)
            key_vec2, cipher = PandoraCrypto.read_key_and_set_pass( \
              panhash2)
            nopass = ((not cipher) or (cipher == 0))
            if nopass and pass_entry.sensitive?
              pass_entry.text = ''
            end
            PandoraGtk.set_readonly(pass_entry, nopass)
            dialog_timer = nil
          end
          false
        end
      end
      false
    end

    nopass = ((not cipher) or (cipher == 0))
    PandoraGtk.set_readonly(pass_entry, nopass)
    pass_entry.width_request = 200
    align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
    align.add(pass_entry)
    vbox.pack_start(align, false, false, 2)

    new_label = nil
    new_pass_entry = nil
    new_align = nil

    if key_entry.text == ''
      dialog.def_widget = key_entry.entry
    else
      dialog.def_widget = pass_entry
    end

    changebtn = PandoraGtk::SafeToggleToolButton.new(Gtk::Stock::EDIT)
    changebtn.tooltip_text = _('Change password')
    changebtn.safe_signal_clicked do |*args|
      if not new_label
        new_label = Gtk::Label.new(_('New password'))
        vbox.pack_start(new_label, false, false, 2)
        new_pass_entry = Gtk::Entry.new
        new_pass_entry.width_request = 200
        new_align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        new_align.add(new_pass_entry)
        vbox.pack_start(new_align, false, false, 2)
        new_align.show_all
      end
      new_label.visible = changebtn.active?
      new_align.visible = changebtn.active?
      if changebtn.active?
        #dialog.set_size_request(420, 250)
        dialog.resize(dialog.allocation.width, 240)
        if pass_entry.sensitive? and (pass_entry.text=='')
          pass_entry.grab_focus
        else
          new_pass_entry.grab_focus
        end
      else
        dialog.resize(dialog.allocation.width, 190)
        if pass_entry.sensitive?
          pass_entry.grab_focus
        else
          key_entry.entry.grab_focus
        end
      end
    end
    dialog.hbox.pack_start(changebtn, false, false, 0)

    gen_button = Gtk::ToolButton.new(Gtk::Stock::ADD, _('New'))  #:NEW
    gen_button.tooltip_text = _('Generate new key pair')
    #gen_button.width_request = 110
    gen_button.signal_connect('clicked') { |*args| dialog.response=3 }
    dialog.hbox.pack_start(gen_button, false, false, 0)

    dialog.run2 do
      aresponse = dialog.response
      key_hash = PandoraModel.hex_to_panhash(key_entry.text)
      if block_given?
        new_pass = new_pass_entry.text if new_pass_entry
        yield(key_hash, pass_entry.text, aresponse, changebtn.active?, \
          new_pass)
      end
    end
  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    attr_accessor :property_box

    def get_bodywin(page_num=nil)
      res = nil
      page_num ||= notebook.page
      child = notebook.get_nth_page(page_num)
      res = child if (child.is_a? BodyScrolledWindow)
      res
    end

    # Create fields dialog
    # RU: Создать форму с полями
    def initialize(apanobject, tree_view, afields, panhash0, obj_id, edit, *args)
      super(*args)
      width_loss = 36
      height_loss = 134
      @property_box = PropertyBox.new(apanobject, afields, panhash0, obj_id, \
        edit, self.notebook, tree_view, width_loss, height_loss)
      viewport.add(@property_box)
      #self.signal_connect('configure-event') do |widget, event|
      #  property_box.on_resize_window(event.width, event.height)
      #  false
      #end
      self.set_default_size(property_box.last_width+width_loss, \
        property_box.last_height+height_loss)
      #property_box.window_width = property_box.window_height = 0
      viewport.show_all

      @last_sw = nil
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        @last_sw = nil if (page_num == 0) and @last_sw
        if page_num==0
          hbox.show
        else
          bodywin = get_bodywin(page_num)
          p 'bodywin='+bodywin.inspect
          if bodywin
            hbox.hide
            bodywin.fill_body
          end
        end
      end

    end

  end

  $you_color = 'red'
  $dude_color = 'blue'
  $tab_color = 'blue'
  $sys_color = 'purple'
  $read_time = 1.5
  $last_page = nil

  # DrawingArea for video output
  # RU: DrawingArea для вывода видео
  class ViewDrawingArea < Gtk::DrawingArea
    attr_accessor :expose_event, :dialog

    def initialize(adialog, *args)
      super(*args)
      @dialog = adialog
      #set_size_request(100, 100)
      #@expose_event = signal_connect('expose-event') do
      #  alloc = self.allocation
      #  self.window.draw_arc(self.style.fg_gc(self.state), true, \
      #    0, 0, alloc.width, alloc.height, 0, 64 * 360)
      #end
    end

    # Set expose event handler
    # RU: Устанавливает обработчик события expose
    def set_expose_event(value, width=nil)
      signal_handler_disconnect(@expose_event) if @expose_event
      @expose_event = value
      if value.nil?
        if self==dialog.area_recv
          dialog.hide_recv_area
        else
          dialog.hide_send_area
        end
      else
        if self==dialog.area_recv
          dialog.show_recv_area(width)
        else
          dialog.show_send_area(width)
        end
      end
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock=nil, title=nil, toggle=nil)
    btn = nil
    padd = 1
    if stock.is_a? Gtk::Widget
      btn = stock
    else
      stock = stock.to_sym if stock.is_a? String
      $window.register_stock(stock) if stock
      if toggle.nil?
        if stock.nil?
          btn = Gtk::SeparatorToolItem.new
          title = nil
          padd = 0
        else
          btn = Gtk::ToolButton.new(stock)
          btn.signal_connect('clicked') do |*args|
            yield(*args) if block_given?
          end
        end
      elsif toggle.is_a? Integer
        if stock
          btn = Gtk::MenuToolButton.new(stock)
        else
          btn = Gtk::MenuToolButton.new(nil, title)
          title = nil
        end
        btn.signal_connect('clicked') do |*args|
          yield(*args) if block_given?
        end
      else
        btn = SafeToggleToolButton.new(stock)
        btn.safe_signal_clicked do |*args|
          yield(*args) if block_given?
        end
        btn.safe_set_active(toggle) if toggle
      end
      if title
        title, keyb = title.split('|')
        if keyb
          keyb = ' '+keyb
        else
          keyb = ''
        end
        lang_title = _(title)
        lang_title.gsub!('_', '')
        btn.tooltip_text = lang_title + keyb
        btn.label = title
      elsif stock
        stock_info = Gtk::Stock.lookup(stock)
        if (stock_info.is_a? Array) and (stock_info.size>0)
          label = stock_info[1]
          if label
            label.gsub!('_', '')
            btn.tooltip_text = label
          end
        end
      end
    end
    #p '[toolbar, stock, title, toggle]='+[toolbar, stock, title, toggle].inspect
    if toolbar.is_a? Gtk::Toolbar
      toolbar.add(btn)
    else
      if btn.is_a? Gtk::Toolbar
        toolbar.pack_start(btn, true, true, padd)
      else
        toolbar.pack_start(btn, false, false, padd)
      end
    end
    btn
  end

  # Add menu item
  # RU: Добавляет пункт меню
  def self.add_menu_item(btn, menu, stock, text=nil)
    mi = nil
    if stock.is_a?(String)
      mi = Gtk::MenuItem.new(stock)
    else
      $window.register_stock(stock)
      mi = Gtk::ImageMenuItem.new(stock)
      if text
        text, keyb = text.split('|')
        if keyb
          keyb = ' '+keyb
        else
          keyb = ''
        end
        mi.label = _(text) + keyb
      end
    end
    menu.append(mi)
    mi.signal_connect('activate') do |mi|
      yield(mi) if block_given?
    end
  end

  class CabViewport < Gtk::Viewport
    attr_accessor :def_widget

    def grab_def_widget
      if @def_widget and (not @def_widget.destroyed?)
        @def_widget.grab_focus
        #self.present
        GLib::Timeout.add(200) do
          @def_widget.grab_focus if @def_widget and (not @def_widget.destroyed?)
          false
        end
      end
    end

    def initialize(*args)
      super(*args)
      #self.signal_connect('show') do |window, event|
      #  grab_def_widget
      #  false
      #end
    end

  end

  $load_history_count = 6
  $sort_history_mode = 0
  $load_more_history_count = 50

  CabPageInfo = [[Gtk::Stock::PROPERTIES, 'Basic'], \
    [Gtk::Stock::HOME, 'Profile'], \
    [:opinion, 'Opinions'], \
    [:relation, 'Relations'], \
    [:sign, 'Signs'], \
    [:chat, 'Chat'], \
    [:dialog, 'Dialog'], \
    [:editor, 'Editor']]

  # Panobject cabinet page
  # RU: Страница кабинета панобъекта
  class CabinetBox < Gtk::VBox
    attr_accessor :room_id, :tree_view, :online_btn, :mic_btn, :webcam_btn, \
      :dlg_talkview, :chat_talkview, :area_send, :area_recv, :recv_media_pipeline, \
      :appsrcs, :session, :ximagesink, :parent_notebook, :cab_notebook, \
      :read_thread, :recv_media_queue, :has_unread, :person_name, :captcha_entry, \
      :sender_box, :toolbar_sw, :toolbar_box, :captcha_enter, :edit_sw, :main_hpaned, \
      :send_hpaned, :opt_btns, :cab_panhash, :session, \
      :bodywin, :fields, :obj_id, :edit, :property_box, :kind, :label_box, \
      :active_page, :dlg_stock, :its_blob, :has_blob

    include PandoraGtk

    CL_Online = 0
    CL_Name   = 1

    def save_and_close
      property_box.save_form_fields_with_flags_to_database if property_box
      self.destroy
    end

    def show_recv_area(width=nil)
      if area_recv.allocation.width <= 24
        width ||= 320
        main_hpaned.position = width
      end
    end

    def hide_recv_area
      main_hpaned.position = 0 if (main_hpaned and (not main_hpaned.destroyed?))
    end

    def show_send_area(width=nil)
      if area_send.allocation.width <= 24
        width ||= 120
        send_hpaned.position = width
      end
    end

    def hide_send_area
      send_hpaned.position = 0 if (send_hpaned and (not send_hpaned.destroyed?))
    end

    def init_captcha_entry(pixbuf, length=nil, symbols=nil, clue=nil, node_text=nil)
      if not @captcha_entry
        @captcha_label = Gtk::Label.new(_('Enter text from picture'))
        label = @captcha_label
        label.set_alignment(0.5, 1.0)
        @sender_box.pack_start(label, true, true, 2)

        @captcha_entry = PandoraGtk::MaskEntry.new

        len = 0
        begin
          len = length.to_i if length
        rescue
        end
        captcha_entry.max_length = len
        if symbols
          mask = symbols.downcase+symbols.upcase
          captcha_entry.mask = mask
        end

        res = area_recv.signal_connect('expose-event') do |widget, event|
          x = widget.allocation.width
          y = widget.allocation.height
          x = (x - pixbuf.width) / 2
          y = (y - pixbuf.height) / 2
          x = 0 if x<0
          y = 0 if y<0
          cr = widget.window.create_cairo_context
          cr.set_source_pixbuf(pixbuf, x, y)
          cr.paint
          true
        end
        area_recv.set_expose_event(res, pixbuf.width+20)

        captcha_entry.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            text = captcha_entry.text
            if text.size>0
              @captcha_enter = captcha_entry.text
              captcha_entry.text = ''
              del_captcha_entry
            end
            true
          elsif (Gdk::Keyval::GDK_Escape==event.keyval)
            @captcha_enter = false
            del_captcha_entry
            false
          else
            false
          end
        end
        PandoraGtk.hack_enter_bug(captcha_entry)

        ew = 150
        if len>0
          str = label.text
          label.text = 'W'*(len+1)
          ew,lh = label.size_request
          label.text = str
        end

        captcha_entry.width_request = ew
        @captcha_align = Gtk::Alignment.new(0.5, 0, 0.0, 0.0)
        @captcha_align.add(captcha_entry)
        @sender_box.pack_start(@captcha_align, true, true, 2)
        @edit_sw.hide
        #@toolbar_box.hide
        @captcha_label.show
        @captcha_align.show_all

        area_recv.queue_draw

        Thread.pass
        sleep 0.02
        if dlg_talkview and (not dlg_talkview.destroyed?)
          dlg_talkview.after_addition(true)
          dlg_talkview.show_all
        end
        PandoraGtk.hack_grab_focus(@captcha_entry)
      end
    end

    def del_captcha_entry
      if @captcha_entry and (not self.destroyed?)
        @captcha_align.destroy
        @captcha_align = nil
        @captcha_entry = nil
        @captcha_label.destroy
        @captcha_label = nil
        #@toolbar_box.show
        @edit_sw.show_all
        area_recv.set_expose_event(nil)
        area_recv.queue_draw
        Thread.pass
        if dlg_talkview and (not dlg_talkview.destroyed?)
          dlg_talkview.after_addition(true)
          dlg_talkview.grab_focus
        end
      end
    end

    def hide_toolbar_btns(page=nil)
      @add_toolbar_btns.each do |btns|
        if btns.is_a? Array
          btns.each do |btn|
            btn.hide
          end
        end
      end
    end

    def show_toolbar_btns(page=nil)
      btns = @add_toolbar_btns[page]
      if btns.is_a? Array
        btns.each do |btn|
          btn.show_all
        end
      end
    end

    def add_btn_to_toolbar(stock=nil, title=nil, toggle=nil, page=nil)
      btns = nil
      if page.is_a? Array
        btns = page
      elsif page.is_a? FalseClass
        btns = nil
      else
        page ||= @active_page
        btns = @add_toolbar_btns[page]
        if not (btns.is_a? Array)
          btns = Array.new
          @add_toolbar_btns[page] = btns
        end
      end
      btn = PandoraGtk.add_tool_btn(toolbar_box, stock, title, toggle) do |*args|
        yield(*args) if block_given?
      end
      btns << btn if (not btns.nil?)
      btn
    end

    def fill_property_toolbar(pb)
      pb.keep_btn = add_btn_to_toolbar(:keep, 'Keep', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.ignore_btn.safe_set_active(false)
        end
      end

      pb.arch_btn = add_btn_to_toolbar(:arch, 'Shelve', false)

      pb.follow_btn = add_btn_to_toolbar(:follow, 'Follow', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.keep_btn.safe_set_active(true)
          pb.arch_btn.safe_set_active(false)
          pb.ignore_btn.safe_set_active(false)
        end
      end

      pb.vouch0 = 0.4
      pb.vouch_btn = add_btn_to_toolbar(:sign, 'Vouch|(Ctrl+G)', false) do |btn|
        if not btn.destroyed?
          pb.vouch_scale.sensitive = btn.active?
          if btn.active?
            if (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              pb.keep_btn.safe_set_active(true)
              pb.arch_btn.safe_set_active(false)
              pb.ignore_btn.safe_set_active(false) if pb.vouch_scale.scale.value>0
            end
            pb.vouch0 ||= 0.4
            pb.vouch_scale.scale.value = pb.vouch0
          else
            pb.vouch0 = pb.vouch_scale.scale.value
          end
        end
      end
      pb.vouch_scale = TrustScale.new(nil, 'Vouch', pb.vouch0)
      pb.vouch_scale.sensitive = pb.vouch_btn.active?
      add_btn_to_toolbar(pb.vouch_scale)

      pb.public0 = 0.0
      pb.public_btn = add_btn_to_toolbar(:public, 'Public', false) do |btn|
        if not btn.destroyed?
          pb.public_scale.sensitive = btn.active?
          if btn.active?
            if (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              pb.keep_btn.safe_set_active(true)
              pb.follow_btn.safe_set_active(true)
              pb.vouch_btn.active = true
              pb.arch_btn.safe_set_active(false)
              pb.ignore_btn.safe_set_active(false)
            end
            pb.public0 ||= 0.0
            pb.public_scale.scale.value = pb.public0
          else
            pb.public0 = pb.public_scale.scale.value
          end
        end
      end
      pb.public_scale = TrustScale.new(nil, 'Publish from level and higher', pb.public0)
      pb.public_scale.sensitive = pb.public_btn.active?
      add_btn_to_toolbar(pb.public_scale)

      pb.ignore_btn = add_btn_to_toolbar(:ignore, 'Ignore', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.keep_btn.safe_set_active(false)
          pb.follow_btn.safe_set_active(false)
          pb.public_btn.active = false
          if pb.vouch_btn.active? and (pb.vouch_scale.scale.value>0)
            pb.vouch_scale.scale.value = 0
          end
          pb.arch_btn.safe_set_active(true)
        end
      end

      add_btn_to_toolbar

      add_btn_to_toolbar(Gtk::Stock::SAVE) do |btn|
        @cab_panhash = pb.save_form_fields_with_flags_to_database
        construct_cab_title
      end
      add_btn_to_toolbar(Gtk::Stock::OK) do |btn|
        self.save_and_close
      end

      #add_btn_to_toolbar(Gtk::Stock::CANCEL) do |btn|
      #  self.destroy
      #end

    end

    def fill_dlg_toolbar(page, talkview, chat_mode=false)
      if (page==PandoraUI::CPI_Dialog)
        crypt_btn = add_btn_to_toolbar(:crypt, 'Encrypt|(Ctrl+K)', false)
      end

      sign_scale = nil
      sign_btn = add_btn_to_toolbar(:sign, 'Vouch|(Ctrl+G)', false) do |widget|
        sign_scale.sensitive = widget.active? if not widget.destroyed?
      end
      sign_scale = TrustScale.new(nil, 'Vouch', 1.0)
      sign_scale.sensitive = sign_btn.active?
      add_btn_to_toolbar(sign_scale)

      if not chat_mode
        require_sign_btn = add_btn_to_toolbar(:require, 'Require sign', false)
      end

      btn = add_btn_to_toolbar(:message, 'Load more history|('+$load_more_history_count.to_s+')', 0) do |widget|
        load_history($load_more_history_count, $sort_history_mode, chat_mode)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::CLEAR, 'Clear screen') do |mi|
        clear_history(chat_mode)
      end
      PandoraGtk.add_menu_item(btn, menu, :message, 'Load more history|('+($load_more_history_count*4).to_s+')') do |mi|
        load_history($load_more_history_count*4, $sort_history_mode, chat_mode)
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::DELETE, 'Delete messages from database') do |mi|
        clear_history(chat_mode, true)
      end
      menu.show_all

      if not chat_mode
        add_btn_to_toolbar

        is_online = (@session != nil)
        @online_btn = add_btn_to_toolbar(Gtk::Stock::CONNECT, 'Online', is_online) \
        do |widget|
          p 'widget.active?='+widget.active?.inspect
          if widget.active? #and (not widget.inconsistent?)
            persons, keys, nodes = PandoraGtk.extract_from_panhash(cab_panhash)
            if nodes and (nodes.size>0)
              nodes.each do |nodehash|
                $pool.init_session(nil, nodehash, 0, self, nil, \
                  persons, keys, nil, PandoraNet::CM_Captcha)
              end
            elsif persons
              persons.each do |person|
                $pool.init_session(nil, nil, 0, self, nil, \
                  person, keys, nil, PandoraNet::CM_Captcha)
              end
            end
          else
            widget.safe_set_active(false)
            $pool.stop_session(nil, cab_panhash, \
              nil, false, self.session)
          end
        end

        @webcam_btn = add_btn_to_toolbar(:webcam, 'Webcam', false) do |widget|
          if widget.active?
            if init_video_sender(true)
              online_btn.active = true
            end
          else
            init_video_sender(false, true)
            init_video_sender(false)
          end
        end

        @mic_btn = add_btn_to_toolbar(:mic, 'Mic', false) do |widget|
          if widget.active?
            if init_audio_sender(true)
              online_btn.active = true
            end
          else
            init_audio_sender(false, true)
            init_audio_sender(false)
          end
        end

        record_btn = add_btn_to_toolbar(Gtk::Stock::MEDIA_RECORD, 'Record', false) do |widget|
          if widget.active?
            #start record video and audio
            sleep(0.5)
            widget.safe_set_active(false)
          else
            #stop record, save the file and add a link to edit_box
          end
        end
      end

      add_btn_to_toolbar

      def_smiles = PandoraUtils.get_param('def_smiles')
      smile_btn = SmileButton.new(def_smiles) do |preset, label|
        smile_img = '[emot='+preset+'/'+label+']'
        text = talkview.edit_box.buffer.text
        smile_img = ' '+smile_img if (text.size>0) and (text[-1] != ' ')
        talkview.edit_box.buffer.insert_at_cursor(smile_img)
      end
      smile_btn.tooltip_text = _('Smile')+' (Alt+Down)'
      add_btn_to_toolbar(smile_btn)

      if page==PandoraUI::CPI_Dialog
        game_btn = add_btn_to_toolbar(:game, 'Game')
        game_btn = add_btn_to_toolbar(:box, 'Box')
        add_btn_to_toolbar
      end

      send_btn = add_btn_to_toolbar(:send, 'Send') do |widget|
        mes = talkview.edit_box.buffer.text
        if mes != ''
          sign_trust = nil
          sign_trust = sign_scale.scale.value if sign_btn.active?
          crypt = nil
          crypt = crypt_btn.active? if crypt_btn
          if send_mes(mes, crypt, sign_trust, chat_mode)
            talkview.edit_box.buffer.text = ''
          end
        end
        false
      end
      send_btn.sensitive = false
      talkview.crypt_btn = crypt_btn
      talkview.sign_btn = sign_btn
      talkview.smile_btn = smile_btn
      talkview.send_btn = send_btn
    end

    def choose_and_set_color(bodywin, a_tag)
      shift_or_ctrl = PandoraGtk.is_ctrl_shift_alt?(true, true)
      dialog = Gtk::ColorSelectionDialog.new
      dialog.set_transient_for(self)
      colorsel = dialog.colorsel
      color = Gdk::Color.parse(@selected_color)
      colorsel.set_previous_color(color)
      colorsel.set_current_color(color)
      colorsel.set_has_palette(true)
      if dialog.run == Gtk::Dialog::RESPONSE_OK
        color = colorsel.current_color
        if shift_or_ctrl
          @selected_color = color.to_s
        else
          @selected_color = PandoraUtils.color_to_str(color)
        end
        @last_color_tag = a_tag
        bodywin.insert_tag(a_tag, @selected_color)
      end
      dialog.destroy
    end

    # Fill editor toolbar
    # RU: Заполнить панель редактора
    def fill_edit_toolbar
      bodywin = nil
      bodywid = nil
      pb = property_box
      first_body_fld = property_box.text_fields[0]
      if first_body_fld
        bodywin = first_body_fld[PandoraUtils::FI_Widget2]
        if bodywin and bodywin.destroyed?
          bodywin = nil
          first_body_fld[PandoraUtils::FI_Widget2] = nil
        end
        if bodywin and bodywin.child and (not bodywin.child.destroyed?)
          bodywid = bodywin.child
        end
      end

      view_mod = true
      view_mod = false if bodywin and bodywin.view_mode.is_a?(FalseClass)
      btn = add_btn_to_toolbar(Gtk::Stock::EDIT, 'Edit', (not view_mod)) do |btn|
        bodywin.view_mode = (not btn.active?)
        bodywin.set_buffers
      end
      bodywin.edit_btn = btn if bodywin

      format0 = 'bbcode'
      format0 = bodywin.format if bodywin
      btn = add_btn_to_toolbar(nil, format0, 0)
      pb.format_btn = btn
      menu = Gtk::Menu.new
      btn.menu = menu
      ['auto', 'plain', 'markdown', 'bbcode', 'wiki', 'html', 'ruby', \
      'python', 'xml', 'ini'].each do |title|
        PandoraGtk.add_menu_item(btn, menu, title) do |mi|
          btn.label = mi.label
          bodywin.format = mi.label.to_s
          bodywin.set_buffers
        end
      end
      menu.show_all

      add_btn_to_toolbar

      toolbar = Gtk::Toolbar.new
      toolbar.show_arrow = true
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS

      bodywin.toolbar = toolbar if bodywin

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::BOLD) do
        bodywin.insert_tag('bold')
      end

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::ITALIC, nil, 0) do
        bodywin.insert_tag('italic')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::UNDERLINE) do
        bodywin.insert_tag('undline')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::STRIKETHROUGH) do
        bodywin.insert_tag('strike')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::UNDERLINE) do
        bodywin.insert_tag('d')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Sub') do
        bodywin.insert_tag('sub')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Sup') do
        bodywin.insert_tag('sup')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Small') do
        bodywin.insert_tag('small')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Large') do
        bodywin.insert_tag('large')
      end
      menu.show_all

      @selected_color = 'red'
      @last_color_tag = 'color'
      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SELECT_COLOR, nil, 0) do
        bodywin.insert_tag(@last_color_tag, @selected_color)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::SELECT_COLOR) do
        choose_and_set_color(bodywin, 'color')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::SELECT_COLOR, 'Background') do
        choose_and_set_color(bodywin, 'bg')
      end
      @selected_font = 'Sans 10'
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::SELECT_FONT) do
        dialog = Gtk::FontSelectionDialog.new
        dialog.font_name = @selected_font
        #dialog.preview_text = 'P2P planetary network Pandora'
        if dialog.run == Gtk::Dialog::RESPONSE_OK
          @selected_font = dialog.font_name
          desc = Pango::FontDescription.new(@selected_font)
          params = {'family'=>desc.family, 'size'=>desc.size/Pango::SCALE}
          params['style']='1' if desc.style==Pango::FontDescription::STYLE_OBLIQUE
          params['style']='2' if desc.style==Pango::FontDescription::STYLE_ITALIC
          params['weight']='600' if desc.weight==Pango::FontDescription::WEIGHT_BOLD
          bodywin.insert_tag('font', params)
        end
        dialog.destroy
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, nil, 0) do
        bodywin.insert_tag('center')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_RIGHT) do
        bodywin.insert_tag('right')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_FILL) do
        bodywin.insert_tag('fill')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_LEFT) do
        bodywin.insert_tag('left')
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar, :image, 'Image') do
        dialog = PandoraGtk::PanhashDialog.new([PandoraModel::Blob])
        dialog.choose_record('sha1','md5','name') do |panhash,sha1,md5,name|
          params = ' align="center"'
          if (name.is_a? String) and (name.size>0)
            params << ' alt="'+name+'" title="'+name+'"'
          end
          if (sha1.is_a? String) and (sha1.size>0)
            bodywin.insert_tag('img/', 'sha1://'+PandoraUtils.bytes_to_hex(sha1)+params)
          elsif panhash.is_a? String
            bodywin.insert_tag('img/', 'pandora://'+PandoraUtils.bytes_to_hex(panhash)+params)
          end
        end
      end
      PandoraGtk.add_tool_btn(toolbar, :link, 'Link') do
        bodywin.insert_tag('link', 'http://priroda.su', 'Priroda.SU')
      end

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::INDENT, 'h1', 0) do
        bodywin.insert_tag('h1')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h2') do
        bodywin.insert_tag('h2')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h3') do
        bodywin.insert_tag('h3')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h4') do
        bodywin.insert_tag('h4')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h5') do
        bodywin.insert_tag('h5')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h6') do
        bodywin.insert_tag('h6')
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, :code, 'Code', 0) do
        bodywin.insert_tag('code', 'ruby')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, :quote, 'Quote') do
        bodywin.insert_tag('quote')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Cut') do
        bodywin.insert_tag('cut', _('Expand'))
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'HR') do
        bodywin.insert_tag('hr/', '150')
      end
      PandoraGtk.add_menu_item(btn, menu, :table, 'Table') do
        bodywin.insert_tag('table')
      end
      menu.append(Gtk::SeparatorMenuItem.new)
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Edit') do
        bodywin.insert_tag('edit/', 'Edit value="Text" size="40"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Spin') do
        bodywin.insert_tag('spin/', 'Spin values="42,48,52" default="48"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Integer') do
        bodywin.insert_tag('integer/', 'Integer value="42" width="70"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Hex') do
        bodywin.insert_tag('hex/', 'Hex value="01a5ff" size="20"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Real') do
        bodywin.insert_tag('real/', 'Real value="0.55"')
      end
      PandoraGtk.add_menu_item(btn, menu, :date, 'Date') do
        bodywin.insert_tag('date/', 'Date value="current"')
      end
      PandoraGtk.add_menu_item(btn, menu, :time, 'Time') do
        bodywin.insert_tag('time/', 'Time value="current"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Coord') do
        bodywin.insert_tag('coord/', 'Coord')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::OPEN, 'Filename') do
        bodywin.insert_tag('filename/', 'Filename value="./picture1.jpg"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Base64') do
        bodywin.insert_tag('base64/', 'Base64 value="SGVsbG8=" size="30"')
      end
      PandoraGtk.add_menu_item(btn, menu, :panhash, 'Panhash') do
        bodywin.insert_tag('panhash/', 'Panhash kind="Person,Community,Blob"')
      end
      PandoraGtk.add_menu_item(btn, menu, :list, 'Bytelist') do
        bodywin.insert_tag('bytelist/', 'List values="red, green, blue"')
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Button') do
        bodywin.insert_tag('button/', 'Button value="Order"')
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar)

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::FIND, nil, 0) do
        bodywin.body_child.show_hide_find_panel(false, true)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::FIND_AND_REPLACE) do
        bodywin.body_child.show_hide_find_panel(true, true)
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::JUMP_TO) do
        bodywin.body_child.show_line_panel
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::PRINT_PREVIEW, nil, 0) do
        bodywin.run_print_operation(true)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::PRINT) do
        bodywin.run_print_operation
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::PAGE_SETUP) do
        bodywin.set_page_setup
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDO, nil, 0) do
        bodywid.do_undo
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::REDO) do
        bodywid.do_redo
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::COPY) do
        bodywid.copy_clipboard
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::CUT) do
        bodywid.cut_clipboard
      end
      PandoraGtk.add_menu_item(btn, menu, Gtk::Stock::PASTE) do
        bodywid.paste_clipboard
      end
      menu.show_all

      col_mod = true
      col_mod = false if (bodywin and bodywin.color_mode.is_a?(FalseClass))
      @color_mode_btn = PandoraGtk.add_tool_btn(toolbar, :tags, 'Color tags', col_mod) do |btn|
        bodywin.color_mode = btn.active?
        bodywin.set_buffers
      end

      PandoraGtk.add_tool_btn(toolbar)

      pb.save_btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SAVE) do
        @cab_panhash = pb.save_form_fields_with_flags_to_database
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OK) do
        @cab_panhash = pb.save_form_fields_with_flags_to_database
        self.destroy
      end

      toolbar.show_all
      add_btn_to_toolbar(toolbar)
    end

    def fill_view_toolbar
      add_btn_to_toolbar(Gtk::Stock::ADD, 'Add')
      add_btn_to_toolbar(Gtk::Stock::DELETE, 'Delete')
      add_btn_to_toolbar(Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      add_btn_to_toolbar(Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }
      @zoom_100 = add_btn_to_toolbar(Gtk::Stock::ZOOM_100, 'Show 1:1', true) do
        @zoom_fit.safe_set_active(false)
        true
      end
      @zoom_fit = add_btn_to_toolbar(Gtk::Stock::ZOOM_FIT, 'Zoom to fit', false) do
        @zoom_100.safe_set_active(false)
        true
      end
      add_btn_to_toolbar(Gtk::Stock::ZOOM_IN, 'Zoom in') do
        @zoom_fit.safe_set_active(false)
        @zoom_100.safe_set_active(false)
        true
      end
      add_btn_to_toolbar(Gtk::Stock::ZOOM_OUT, 'Zoom out') do
        @zoom_fit.safe_set_active(false)
        @zoom_100.safe_set_active(false)
        true
      end
    end

    def fill_profile_toolbar
      add_btn_to_toolbar(Gtk::Stock::REFRESH, 'Request the record with relations, avatars and opinions') do
        PandoraNet.find_search_request((PandoraNet::SRO_Record | PandoraNet::SRO_Opinions | \
          PandoraNet::SRO_Relations | PandoraNet::SRO_Avatars), cab_panhash)
        true
      end
      #add_btn_to_toolbar
      #add_btn_to_toolbar(Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      #add_btn_to_toolbar(Gtk::Stock::CANCEL, 'Cancel') { |*args| self.destroy }
      #PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OK) do
      #  pb.save_form_fields_with_flags_to_database
      #  self.destroy
      #end
      #add_btn_to_toolbar(Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
    end

    def grab_def_widget
      page = cab_notebook.page
      container = cab_notebook.get_nth_page(page)
      container.grab_def_widget if container.is_a? CabViewport
    end

    def show_page(page=PandoraUI::CPI_Dialog, tab_signal=nil)
      p '---show_page [page, tab_signal]='+[page, tab_signal].inspect
      if ((page == PandoraUI::CPI_Dialog) and (kind != PandoraModel::PK_Person))
        page = PandoraUI::CPI_Chat
      end
      hide_toolbar_btns
      opt_btns.each do |opt_btn|
        opt_btn.safe_set_active(false) if (opt_btn.is_a?(SafeToggleToolButton))
      end
      cab_notebook.page = page if not tab_signal
      container = cab_notebook.get_nth_page(page)
      sub_btn = opt_btns[PandoraUI::CPI_Sub]
      sub_stock = CabPageInfo[PandoraUI::CPI_Sub][0]
      stock_id = CabPageInfo[page][0]
      if label_box.stock
        if page==PandoraUI::CPI_Property
          label_box.set_stock(opt_btns[page].stock_id)
        else
          label_box.set_stock(stock_id)
        end
      end
      if page<=PandoraUI::CPI_Sub
        opt_btns[page].safe_set_active(true)
        sub_btn.stock_id = sub_stock if (sub_btn.stock_id != sub_stock)
      elsif page>PandoraUI::CPI_Last_Sub
        opt_btns[page-PandoraUI::CPI_Last_Sub+PandoraUI::CPI_Sub+1].safe_set_active(true)
        sub_btn.stock_id = sub_stock if (sub_btn.stock_id != sub_stock)
      else
        sub_btn.safe_set_active(true)
        sub_btn.stock_id = stock_id
      end
      prev_page = @active_page
      @active_page = page
      need_init = true
      if container
        container = container.child if page==PandoraUI::CPI_Property
        need_init = false if (container.children.size>0)
      end
      if need_init
        case page
          when PandoraUI::CPI_Property
            @property_box ||= PropertyBox.new(kind, @fields, cab_panhash, obj_id, edit, nil, @tree_view)
            fill_property_toolbar(property_box)
            property_box.set_status_icons
            #property_box.window_width = property_box.window_height = 0
            p [self.allocation.width, self.allocation.height]
            #property_box.on_resize_window(self.allocation.width, self.allocation.height)
            #property_box.on_resize_window(container.allocation.width, container.allocation.height)
            #container.signal_connect('configure-event') do |widget, event|
            #  property_box.on_resize_window(event.width, event.height)
            #  false
            #end
            container.add(property_box)
          when PandoraUI::CPI_Profile
            short_name = ''

            hpaned = Gtk::HPaned.new
            hpaned.border_width = 2

            list_sw = Gtk::ScrolledWindow.new(nil, nil)
            list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
            list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

            list_store = Gtk::ListStore.new(String)

            kind = PandoraUtils.kind_from_panhash(cab_panhash)
            if kind==PandoraModel::PK_Person
              user_iter = list_store.append
              user_iter[0] = _('Resume')
              user_iter = list_store.append
              user_iter[0] = _('Biography')
              user_iter = list_store.append
              user_iter[0] = _('Feed')
            else
              user_iter = list_store.append
              user_iter[0] = _('Info')
              user_iter = list_store.append
              user_iter[0] = _('Description')
            end
            # create tree view
            list_tree = Gtk::TreeView.new(list_store)
            list_tree.headers_visible = false
            #list_tree.rules_hint = true
            #list_tree.search_column = CL_Name

            renderer = Gtk::CellRendererText.new
            column = Gtk::TreeViewColumn.new(_('Menu'), renderer, 'text' => 0)
            column.set_sort_column_id(0)
            list_tree.append_column(column)

            right_sw = Gtk::ScrolledWindow.new(nil, nil)
            right_sw.shadow_type = Gtk::SHADOW_NONE
            right_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

            list_tree.signal_connect('cursor-changed') do |treeview|
              path, column = treeview.cursor
              if path
                row_ind = path.indices[0]
                cur_wd = nil
                right_child = right_sw.child
                case row_ind
                  when 0
                    @info_wd ||= PandoraGtk::ChatTextView.new
                    cur_wd = @info_wd
                  when 1
                    #@desc_wd ||= PandoraGtk::ChatTextView.new
                    cur_wd = @desc_wd
                  when 2
                    #@feed_wd ||= PandoraGtk::ChatTextView.new
                    cur_wd = @feed_wd
                end
                if cur_wd
                  if right_child and (right_child != cur_wd)
                    right_sw.remove(right_child)
                    right_child = nil
                  end
                  if right_child.nil?
                    right_sw.add(cur_wd)
                    cur_wd.reparent(right_sw)
                    right_sw.show_all
                  end
                else
                  right_sw.remove(right_child) if right_child
                end
              end
            end

            list_tree.set_cursor(Gtk::TreePath.new(0), nil, false)
            list_sw.add(list_tree)

            left_box = Gtk::VBox.new
            dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, 150)
            #buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
            dlg_image = nil
            dlg_image = Gtk::Image.new(dlg_pixbuf) if dlg_pixbuf
            #dlg_image ||= $window.get_preset_image('dialog')
            dlg_image ||= dlg_stock
            dlg_image ||= Gtk::Stock::MEDIA_PLAY
            if dlg_image.is_a?(Gtk::Image)
              dlg_image.tooltip_text = _('Watch avatar')
            else
              dlg_image = $window.get_preset_image(dlg_image, Gtk::IconSize::LARGE_TOOLBAR, nil)
              dlg_image.tooltip_text = _('Set avatar')
            end
            dlg_image.height_request = 60 if not dlg_image.pixbuf
            dlg_image.signal_connect('realize') do |widget, event|
              awindow = widget.window
              awindow.cursor = $window.hand_cursor if awindow
              false
            end
            event_box = Gtk::EventBox.new.add(dlg_image)
            event_box.events = Gdk::Event::BUTTON_PRESS_MASK
            event_box.signal_connect('button-press-event') do |widget, event|
              res = false
              if cab_panhash
                avatar_hash = PandoraModel.find_relation(cab_panhash, RK_AvatarFor, true)
                if (avatar_hash and (event.button == 1) \
                and (not event.state.control_mask?) and (not event.state.shift_mask?))
                  sw = PandoraGtk.show_cabinet(avatar_hash, nil, nil, nil, \
                    nil, PandoraUI::CPI_Editor)
                  res = true
                end
                if not res
                  dialog = PandoraGtk::PanhashDialog.new([PandoraModel::Blob])
                  dialog.choose_record do |img_panhash|
                    PandoraModel.del_image_from_cache(cab_panhash)
                    PandoraModel.act_relation(img_panhash, cab_panhash, RK_AvatarFor, \
                      :delete, false)
                    PandoraModel.act_relation(img_panhash, cab_panhash, RK_AvatarFor, \
                      :create, false)
                    dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, 150)
                    if dlg_pixbuf
                      dlg_image.height_request = -1
                      dlg_image.pixbuf = dlg_pixbuf
                    end
                  end
                  res = true
                end
              end
              res
            end

            left_box.pack_start(event_box, false, false, 0)
            left_box.pack_start(list_sw, true, true, 0)

            hpaned.pack1(left_box, false, true)
            hpaned.pack2(right_sw, true, true)
            list_sw.show_all
            container.def_widget = list_tree

            fill_profile_toolbar
            container.add(hpaned)
          when PandoraUI::CPI_Editor
            #@bodywin = BodyScrolledWindow.new(@fields, nil, nil)
            #bodywin.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            p [kind, @fields, PandoraUtils.bytes_to_hex(cab_panhash)]
            @property_box ||= PropertyBox.new(kind, @fields, cab_panhash, obj_id, edit, nil, @tree_view)
            if property_box.text_fields and (property_box.text_fields.size>0)
              #p property_box.text_fields
              first_body_fld = property_box.text_fields[0]
              if first_body_fld
                bodywin = first_body_fld[PandoraUtils::FI_Widget2]
                if bodywin and bodywin.destroyed?
                  bodywin = nil
                  first_body_fld[PandoraUtils::FI_Widget2] = nil
                end
                if bodywin
                  container.add(bodywin)
                  bodywin.fill_body
                  fill_edit_toolbar
                  #if bodywin.edit_btn
                  #  bodywin.edit_btn.safe_set_active((not bodywin.view_mode))
                  #end
                end
              end
            end
          when PandoraUI::CPI_Dialog, PandoraUI::CPI_Chat
            listsend_vpaned = Gtk::VPaned.new

            @area_recv = ViewDrawingArea.new(self)
            area_recv.set_size_request(0, -1)
            area_recv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#707070'))

            res = area_recv.signal_connect('expose-event') do |*args|
              #p 'area_recv '+area_recv.window.xid.inspect
              false
            end

            atalkview = PandoraGtk::ChatTextView.new(54)
            if page==PandoraUI::CPI_Chat
              @chat_talkview = atalkview
            else
              @dlg_talkview = atalkview
            end
            atalkview.set_readonly(true)
            #atalkview.set_size_request(200, 200)
            atalkview.wrap_mode = Gtk::TextTag::WRAP_WORD

            atalkview.buffer.create_tag('you', 'foreground' => $you_color)
            atalkview.buffer.create_tag('dude', 'foreground' => $dude_color)
            atalkview.buffer.create_tag('you_bold', 'foreground' => $you_color, \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)
            atalkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)
            atalkview.buffer.create_tag('sys', 'foreground' => $sys_color, \
              'style' => Pango::FontDescription::STYLE_ITALIC)
            atalkview.buffer.create_tag('sys_bold', 'foreground' => $sys_color,  \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)

            talksw = Gtk::ScrolledWindow.new(nil, nil)
            talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            talksw.add(atalkview)

            edit_box = PandoraGtk::SuperTextView.new
            atalkview.edit_box = edit_box
            edit_box.wrap_mode = Gtk::TextTag::WRAP_WORD
            #edit_box.set_size_request(200, 70)

            @edit_sw = Gtk::ScrolledWindow.new(nil, nil)
            edit_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            edit_sw.add(edit_box)

            edit_box.grab_focus

            edit_box.buffer.signal_connect('changed') do |buf|
              atalkview.send_btn.sensitive = (buf.text != '')
              false
            end

            edit_box.signal_connect('key-press-event') do |widget, event|
              res = false
              if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
              and (not event.state.control_mask?) and (not event.state.shift_mask?) \
              and (not event.state.mod1_mask?)
                atalkview.send_btn.clicked
                res = true
              elsif (Gdk::Keyval::GDK_Escape==event.keyval)
                edit_box.buffer.text = ''
              elsif ((event.state.shift_mask? or event.state.mod1_mask?) \
              and (event.keyval==65364))  # Shift+Down or Alt+Down
                atalkview.smile_btn.clicked
                res = true
              elsif ([Gdk::Keyval::GDK_k, Gdk::Keyval::GDK_K, 1740, 1772].include?(event.keyval) \
              and event.state.control_mask?) #k, K, л, Л
                if atalkview.crypt_btn and (not atalkview.crypt_btn.destroyed?)
                  atalkview.crypt_btn.active = (not atalkview.crypt_btn.active?)
                  res = true
                end
              elsif ([Gdk::Keyval::GDK_g, Gdk::Keyval::GDK_G, 1744, 1776].include?(event.keyval) \
              and event.state.control_mask?) #g, G, п, П
                if atalkview.sign_btn and (not atalkview.sign_btn.destroyed?)
                  atalkview.sign_btn.active = (not atalkview.sign_btn.active?)
                  res = true
                end
              end
              res
            end

            @send_hpaned = Gtk::HPaned.new
            @area_send = ViewDrawingArea.new(self)
            #area_send.set_size_request(120, 90)
            area_send.set_size_request(0, -1)
            area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#707070'))
            send_hpaned.pack1(area_send, false, true)

            @sender_box = Gtk::VBox.new
            sender_box.pack_start(edit_sw, true, true, 0)

            send_hpaned.pack2(sender_box, true, true)

            list_sw = Gtk::ScrolledWindow.new(nil, nil)
            list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
            list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
            #list_sw.visible = false

            list_store = Gtk::ListStore.new(TrueClass, String)
            #targets[CSI_Persons].each do |person|
            #  user_iter = list_store.append
            #  user_iter[CL_Name] = PandoraUtils.bytes_to_hex(person)
            #end

            # create tree view
            list_tree = Gtk::TreeView.new(list_store)
            list_tree.rules_hint = true
            list_tree.search_column = CL_Name

            # column for fixed toggles
            renderer = Gtk::CellRendererToggle.new
            renderer.signal_connect('toggled') do |cell, path_str|
              path = Gtk::TreePath.new(path_str)
              iter = list_store.get_iter(path)
              fixed = iter[CL_Online]
              p 'fixed='+fixed.inspect
              fixed ^= 1
              iter[CL_Online] = fixed
            end

            tit_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
            #tit_image.set_padding(2, 0)
            tit_image.show_all

            column = Gtk::TreeViewColumn.new('', renderer, 'active' => CL_Online)
            column.widget = tit_image

            # set this column to a fixed sizing (of 50 pixels)
            #column.sizing = Gtk::TreeViewColumn::FIXED
            #column.fixed_width = 50
            list_tree.append_column(column)

            # column for description
            renderer = Gtk::CellRendererText.new

            column = Gtk::TreeViewColumn.new(_('Nodes'), renderer, 'text' => CL_Name)
            column.set_sort_column_id(CL_Name)
            list_tree.append_column(column)

            list_sw.add(list_tree)

            list_hpaned = Gtk::HPaned.new
            list_hpaned.pack1(list_sw, true, true)
            list_hpaned.pack2(talksw, true, true)
            #motion-notify-event  #leave-notify-event  enter-notify-event
            #list_hpaned.signal_connect('notify::position') do |widget, param|
            #  if list_hpaned.position <= 1
            #    list_tree.set_size_request(0, -1)
            #    list_sw.set_size_request(0, -1)
            #  end
            #end
            list_hpaned.position = 1
            list_hpaned.position = 0

            area_send.add_events(Gdk::Event::BUTTON_PRESS_MASK)
            area_send.signal_connect('button-press-event') do |widget, event|
              if list_hpaned.position <= 1
                list_sw.width_request = 150 if list_sw.width_request <= 1
                list_hpaned.position = list_sw.width_request
              else
                list_sw.width_request = list_sw.allocation.width
                list_hpaned.position = 0
              end
            end

            area_send.signal_connect('visibility_notify_event') do |widget, event_visibility|
              case event_visibility.state
                when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
                  init_video_sender(true, true) if not area_send.destroyed?
                when Gdk::EventVisibility::FULLY_OBSCURED
                  init_video_sender(false, true, false) if not area_send.destroyed?
              end
            end

            area_send.signal_connect('destroy') do |*args|
              init_video_sender(false)
            end

            listsend_vpaned.pack1(list_hpaned, true, true)
            listsend_vpaned.pack2(send_hpaned, false, true)

            @main_hpaned = Gtk::HPaned.new
            main_hpaned.pack1(area_recv, false, true)
            main_hpaned.pack2(listsend_vpaned, true, true)

            area_recv.signal_connect('visibility_notify_event') do |widget, event_visibility|
              #p 'visibility_notify_event!!!  state='+event_visibility.state.inspect
              case event_visibility.state
                when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
                  init_video_receiver(true, true, false) if not area_recv.destroyed?
                when Gdk::EventVisibility::FULLY_OBSCURED
                  init_video_receiver(false, true) if not area_recv.destroyed?
              end
            end

            #area_recv.signal_connect('map') do |widget, event|
            #  p 'show!!!!'
            #  init_video_receiver(true, true, false) if not area_recv.destroyed?
            #end

            area_recv.signal_connect('destroy') do |*args|
              init_video_receiver(false, false)
            end

            chat_mode = ((page==PandoraUI::CPI_Chat) or (kind != PandoraModel::PK_Person))

            fill_dlg_toolbar(page, atalkview, chat_mode)
            load_history($load_history_count, $sort_history_mode, chat_mode)

            container.add(main_hpaned)
            container.def_widget = edit_box
          when PandoraUI::CPI_Opinions
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Message, nil, pbox, false, \
              'destination='+panhash+' AND panstate>'+(PandoraModel::PSF_Opinion-1).to_s)
            container.add(pbox)
          when PandoraUI::CPI_Relations
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Relation, nil, pbox, false, \
              'first='+panhash+' OR second='+panhash)
            container.add(pbox)
          when PandoraUI::CPI_Signs
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Sign, nil, pbox, false, \
              'creator='+panhash+' OR obj_hash='+panhash)
            container.add(pbox)
        end
      else
        case page
          when PandoraUI::CPI_Editor
            if (prev_page == @active_page) and property_box \
            and property_box.text_fields and (property_box.text_fields.size>0)
              first_body_fld = property_box.text_fields[0]
              if first_body_fld
                bodywin = first_body_fld[PandoraUtils::FI_Widget2]
                if bodywin and bodywin.destroyed?
                  bodywin = nil
                  first_body_fld[PandoraUtils::FI_Widget2] = nil
                end
                if bodywin and bodywin.edit_btn
                  bodywin.edit_btn.active = (not bodywin.edit_btn.active?)
                end
              end
            end
        end
      end
      container.show_all
      show_toolbar_btns(page)
      grab_def_widget
    end

    # Create cabinet
    # RU: Создать кабинет
    def initialize(a_panhash, a_room_id, a_page=nil, a_fields=nil, an_id=nil, \
    an_edit=nil, a_session=nil, a_tree_view=nil)
      super(nil, nil)

      #p '==Cabinet.new a_panhash='+PandoraUtils.bytes_to_hex(a_panhash)

      @tree_view = a_tree_view
      if a_panhash.is_a?(String)
        @cab_panhash = a_panhash
        @kind = PandoraUtils.kind_from_panhash(cab_panhash)
      elsif a_panhash.is_a?(PandoraModel::Panobject)
        panobject = a_panhash
        @kind = panobject.kind
        @property_box = PropertyBox.new(panobject, a_fields, nil, nil, an_edit, nil, @tree_view)
      end
      @session = a_session
      @room_id = a_room_id
      @fields = a_fields
      @obj_id = an_id
      @edit = an_edit

      @has_unread = false
      @recv_media_queue = Array.new
      @recv_media_pipeline = Array.new
      @appsrcs = Array.new
      @add_toolbar_btns = Array.new

      #set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #border_width = 0

      @dlg_stock = nil
      @its_blob = nil
      @has_blob = nil
      if kind
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          @its_blob = ((kind==PandoraModel::PK_Blob) \
            or (panobjectclass <= PandoraModel::Blob))
          @has_blob = (@its_blob or panobjectclass.has_blob_fields?)
          @dlg_stock = $window.get_panobject_stock(panobjectclass.ider)
        end
      end
      @dlg_stock ||= Gtk::Stock::PROPERTIES

      main_vbox = self #Gtk::VBox.new
      #add_with_viewport(main_vbox)

      @cab_notebook = Gtk::Notebook.new
      cab_notebook.show_tabs = false
      cab_notebook.show_border = false
      cab_notebook.border_width = 0
      @toolbar_box = Gtk::HBox.new #Toolbar.new HBox.new
      main_vbox.pack_start(cab_notebook, true, true, 0)

      @opt_btns = []
      btn_down = nil
      (PandoraUI::CPI_Property..PandoraUI::CPI_Last).each do |index|
        container = nil
        if index==PandoraUI::CPI_Property
          stock = dlg_stock
          stock ||= CabPageInfo[index][0]
          text = CabPageInfo[index][1]
          container = Gtk::ScrolledWindow.new(nil, nil)
          container.shadow_type = Gtk::SHADOW_NONE
          container.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          container.border_width = 0
          viewport = CabViewport.new(nil, nil)
          container.add(viewport)
        else
          stock = CabPageInfo[index][0]
          text = CabPageInfo[index][1]
          if index==PandoraUI::CPI_Last_Sub+1
            btn_down.menu.show_all
            btn_down = nil
          end
          container = CabViewport.new(nil, nil)
        end
        text = _(text)
        page_box = TabLabelBox.new(stock, text)
        cab_notebook.append_page_menu(container, page_box)

        if not btn_down
          opt_btn = add_btn_to_toolbar(stock, text, false, opt_btns) do
            show_page(index)
          end
          if index==PandoraUI::CPI_Sub
            btn_down = add_btn_to_toolbar(nil, nil, 0, opt_btns)
            btn_down.menu = Gtk::Menu.new
          end
        end
        if btn_down
          PandoraGtk.add_menu_item(btn_down, btn_down.menu, stock, text) do
            show_page(index)
          end
        end
      end
      cab_notebook.signal_connect('switch-page') do |widget, page, page_num|
        #container = widget.get_nth_page(page_num)
        #container.grab_def_widget if container.is_a? CabViewport
        #show_page(page_num, true)
        false
      end

      #toolbar_box.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      #toolbar_box.add(Gtk::SeparatorToolItem.new)
      add_btn_to_toolbar(nil, nil, nil, opt_btns)

      @toolbar_sw = Gtk::ScrolledWindow.new(nil, nil)
      toolbar_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_NEVER)
      toolbar_sw.border_width = 0
      #iw, iy = Gtk::IconSize.lookup(Gtk::IconSize::LARGE_TOOLBAR)
      toolbar_box.show_all
      iw, iy = toolbar_box.size_request
      toolbar_sw.height_request = iy+6
      #toolbar_sw.add(toolbar_box)
      toolbar_sw.add_with_viewport(toolbar_box)

      #main_vbox.pack_start(toolbar_box, false, false, 0)
      main_vbox.pack_start(toolbar_sw, false, false, 0)

      dlg_pixbuf = nil
      if cab_panhash
        dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, \
          Gtk::IconSize.lookup(Gtk::IconSize::SMALL_TOOLBAR)[0])
        #buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
      end
      dlg_image = nil
      dlg_image = Gtk::Image.new(dlg_pixbuf) if dlg_pixbuf
      #dlg_image ||= $window.get_preset_image('dialog')
      dlg_image ||= dlg_stock
      dlg_image ||= Gtk::Stock::MEDIA_PLAY
      @label_box = TabLabelBox.new(dlg_image, 'unknown', self) do
        area_send.destroy if area_send and (not area_send.destroyed?)
        area_recv.destroy if area_recv and (not area_recv.destroyed?)
        $pool.stop_session(nil, @cab_panhash, nil, false, self.session) if @cab_panhash
      end

      notebook = nil
      if tree_view.is_a?(SubjTreeView)
        notebook = tree_view.get_notebook
      end
      notebook ||= $window.notebook
      @parent_notebook = notebook

      page = notebook.append_page(self, label_box)
      notebook.set_tab_reorderable(self, true)

      construct_cab_title

      self.signal_connect('delete-event') do |*args|
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end

      self.show_all
      a_page ||= PandoraUI::CPI_Dialog
      opt_btns[PandoraUI::CPI_Sub+1].children[0].children[0].hide
      btn_offset = PandoraUI::CPI_Last_Sub-PandoraUI::CPI_Sub-1
      opt_btns[PandoraUI::CPI_Editor-btn_offset].hide if (not has_blob)
      if (kind != PandoraModel::PK_Person)
        opt_btns[PandoraUI::CPI_Dialog-btn_offset].hide
        a_page = PandoraUI::CPI_Chat if a_page == PandoraUI::CPI_Dialog
      end
      show_page(a_page)

      GLib::Timeout.add(5) do
        notebook.page = notebook.n_pages-1
        notebook.queue_resize
        notebook.queue_draw
        false
      end
    end

    MaxTitleLen = 15

    # Construct cabinet title
    # RU: Генерирует заголовок кабинета
    def construct_cab_title(check_all=true, atitle_view=nil)

      def trunc_big_title(title)
        title.strip! if title
        if title.size>MaxTitleLen
          need_dots = (title[MaxTitleLen] != ' ')
          len = MaxTitleLen
          len -= 1 if need_dots
          need_dots = (title[len-1] != ' ')
          title = title[0, len].strip
          title << '..' if need_dots
        end
        title
      end

      res = 'unknown'
      notebook = @parent_notebook
      notebook ||= $window.notebook
      if (kind==PandoraModel::PK_Person)
        title_view = atitle_view
        title_view ||= PandoraUI.title_view
        title_view ||= PandoraUI::TV_Name
        res = ''
        if @cab_panhash
          aname, afamily = PandoraCrypto.name_and_family_of_person(nil, @cab_panhash)
          #p '------------[aname, afamily, cab_panhash]='+[aname, afamily, cab_panhash, \
          #  PandoraUtils.bytes_to_hex(cab_panhash)].inspect
          addname = ''
          case title_view
            when PandoraUI::TV_Name, PandoraUI::TV_NameN
              if (aname.size==0)
                addname << afamily
              else
                addname << aname
              end
            when PandoraUI::TV_Family
              if (afamily.size==0)
                addname << aname
              else
                addname << afamily
              end
            when PandoraUI::TV_NameFam
              if (aname.size==0)
                addname << afamily
              else
                addname << aname #[0, 4]
                addname << ' '+afamily if afamily and (afamily.size>0)
              end
          end
          if (addname.size>0)
            res << ',' if (res.size>0)
            res << addname
          end
        end
        res = PandoraModel::Person.sname if (res.size==0)
        res = trunc_big_title(res)
        tab_widget = notebook.get_tab_label(self)
        tab_widget.label.text = res if tab_widget
        #p '$window.title_view, res='+[@$window.title_view, res].inspect
        if check_all
          title_view=PandoraUI::TV_Name if (title_view==PandoraUI::TV_NameN)
          has_conflict = true
          while has_conflict and (title_view < PandoraUI::TV_NameN)
            has_conflict = false
            names = Array.new
            notebook.children.each do |child|
              if (child.is_a? CabinetBox)
                tab_widget = notebook.get_tab_label(child)
                if tab_widget
                  tit = tab_widget.label.text
                  if names.include? tit
                    has_conflict = true
                    break
                  else
                    names << tit
                  end
                end
              end
            end
            if has_conflict
              if (title_view < PandoraUI::TV_NameN)
                title_view += 1
              end
              #p '@$window.title_view='+@$window.title_view.inspect
              names = Array.new
              notebook.children.each do |child|
                if (child.is_a? CabinetBox)
                  sn = child.construct_cab_title(false, title_view)
                  if (title_view == PandoraUI::TV_NameN)
                    names << sn
                    c = names.count(sn)
                    sn = sn+c.to_s if c>1
                    tab_widget = notebook.get_tab_label(child)
                    tab_widget.label.text = sn if tab_widget
                  end
                end
              end
            end
          end
        end
      else
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          model = PandoraUtils.get_model(panobjectclass.ider)
          if model
            model.namesvalues = nil
            sel = model.select({'panhash'=>@cab_panhash}, true, nil, nil, 1)
            res = model.record_info(MaxTitleLen+1, nil, nil, ' ')
            res = trunc_big_title(res)
            tab_widget = notebook.get_tab_label(self)
            tab_widget.label.text = res if tab_widget
          end
        end
      end
      res
    end

    def buf_insert(buf, str, styl, offset)
      iter = nil
      if offset.nil?
        iter = buf.end_iter
      else
        iter = buf.get_iter_at_offset(offset)
        offset += str.size
      end
      if styl
        buf.insert(iter, str, styl)
      else
        buf.insert(iter, str)
      end
      offset
    end

    # Put message to dialog
    # RU: Добавляет сообщение в диалог
    def add_mes_to_view(mes, id, panstate=nil, to_end=nil, \
    key_or_panhash=nil, myname=nil, modified=nil, created=nil, \
    mine=nil, insert_above=nil)
      if mes
        encrypted = ((panstate.is_a? Integer) \
          and ((panstate & PandoraModel::PSF_Crypted) > 0))
        chat_mode = ((panstate & PandoraModel::PSF_ChatMes) > 0)
        mes = PandoraCrypto.recrypt_mes(mes) if encrypted

        p '---add_mes_to_view [mes, id, pstate to_end, key_or_phash, myname, modif, created]=' + \
          [mes, id, panstate, to_end, key_or_panhash, myname, modified, created].inspect

        notice = false
        if not myname
          mykey = PandoraCrypto.current_key(false, false)
          myname = PandoraCrypto.short_name_of_person(mykey)
        end

        time_style = 'you'
        name_style = 'you_bold'
        user_name = nil
        creator = key_or_panhash
        if mine
          user_name = myname
        else
          if key_or_panhash.is_a?(String)
            creator = key_or_panhash
            user_name = PandoraCrypto.short_name_of_person(nil, creator, 0, myname)
          elsif key_or_panhash.is_a?(Array)
            key_vec = key_or_panhash
            creator = key_vec[PandoraCrypto::KV_Creator]
            user_name = PandoraCrypto.short_name_of_person(key_vec, nil, 0, myname)
          end
          time_style = 'dude'
          name_style = 'dude_bold'
          notice = (not to_end.is_a?(FalseClass))
        end
        user_name = 'noname' if ((not user_name) or (user_name==''))

        time_now = Time.now
        created = time_now if ((not modified) and (not created))

        time_str = ''
        time_str << PandoraUtils.time_to_dialog_str(created, time_now) if created
        if modified and ((not created) or ((modified.to_i-created.to_i).abs>30))
          time_str << ' ' if (time_str != '')
          time_str << '('+PandoraUtils.time_to_dialog_str(modified, time_now)+')'
        end

        talkview = @dlg_talkview
        talkview = @chat_talkview if chat_mode

        if talkview
          buf = talkview.buffer
          talkview.before_addition(time_now) if (not to_end.is_a? FalseClass)

          not_empty = (buf.char_count>0)
          buf.insert(buf.end_iter, "\n") if (not insert_above) and not_empty

          offset = nil
          offset = 0 if insert_above
          offset = buf_insert(buf, time_str+' ', time_style, offset)

          #creator name_style 'URL'
          tv_tag = nil
          #p '====++ creator='+[creator, PandoraUtils.panhash_nil?(creator)].inspect
          if (not PandoraUtils.panhash_nil?(creator))
            link_url = 'pandora://'+PandoraUtils.bytes_to_hex(creator)
            trunc_md5 = Digest::MD5.digest(link_url)[0, 10]
            link_id = 'link'+PandoraUtils.bytes_to_hex(trunc_md5)
            link_tag = buf.tag_table.lookup(link_id)
            #p '--[link_url, link_id, link_tag]='+[link_url, link_id, link_tag].inspect
            if link_tag
              tv_tag = link_tag.name
            else
              link_tag = LinkTag.new(link_id)
              if link_tag
                name_tag = buf.tag_table.lookup(name_style)
                PandoraGtk.copy_glib_object_properties(name_tag, link_tag)
                #link_tag.underline = Pango::AttrUnderline::SINGLE
                buf.tag_table.add(link_tag)
                link_tag.link = link_url
                tv_tag = link_id
              end
            end
          end

          if tv_tag
            offset = buf_insert(buf, user_name, tv_tag, offset)
            offset = buf_insert(buf, ':', name_style, offset)
          else
            offset = buf_insert(buf, user_name+':', name_style, offset)
          end

          line = buf.line_count
          talkview.mes_ids[line] = id

          offset = buf_insert(buf, ' ', nil, offset)

          if insert_above
            offset = buf_insert(buf, mes+"\n", nil, offset)
          else
            talkview.insert_taged_str_to_buffer(mes, buf, 'bbcode')
          end

          talkview.after_addition(to_end) if (not to_end.is_a? FalseClass)
          talkview.show_all
        end

        update_state(true) if notice
      end
    end

    # Load history of messages
    # RU: Подгрузить историю сообщений
    def load_history(max_message=6, sort_mode=0, chat_mode=false)
      p '---- load_history [max_message, sort_mode]='+[max_message, sort_mode].inspect
      talkview = @dlg_talkview
      talkview = @chat_talkview if chat_mode
      if talkview and max_message and (max_message>0)
        #messages = []
        fields = 'creator, created, destination, state, text, panstate, modified, id'

        mypanhash = PandoraCrypto.current_user_or_key(true)
        myname = PandoraCrypto.short_name_of_person(nil, mypanhash)

        nil_create_time = false
        model = PandoraUtils.get_model('Message')
        max_message2 = max_message
        #max_message2 = max_message * 2 if (cab_panhash == mypanhash)

        chatbit = PandoraModel::PSF_ChatMes.to_s

        chat_sign = '>'
        first_id = nil
        cond = 'destination=?'
        args = [cab_panhash]
        if chat_mode
          @chat_first_id ||= nil
          first_id = @chat_first_id
        else
          @dialog_first_id ||= nil
          first_id = @dialog_first_id
          cond << ' AND creator=?'
          args << mypanhash
          if (cab_panhash != mypanhash)
            cond = '(('+cond+') OR (creator=? AND destination=?))'
            args << cab_panhash
            args << mypanhash
          end
          chat_sign = '='
        end
        if first_id
          cond << ' AND id<?'
          args << first_id
        end
        p filter = [cond+' AND IFNULL(panstate,0)&'+chatbit+chat_sign+'0', *args]
        #return

        sel = model.select(filter, false, fields, 'id DESC', max_message2)
        sel.reverse!

        if false #!!! (cab_panhash == mypanhash)
          i = sel.size-1
          while i>0 do
            i -= 1
            time, text, time_prev, text_prev = sel[i][1], sel[i][4], sel[i+1][1], sel[i+1][4]
            #p [time, text, time_prev, text_prev]
            if (not time) or (not time_prev)
              time, time_prev = sel[i][6], sel[i+1][6]
              nil_create_time = true
            end
            if (not text) or (time and text and time_prev and text_prev \
            and ((time-time_prev).abs<30) \
            and (AsciiString.new(text)==AsciiString.new(text_prev)))
              #p 'DEL '+[time, text, time_prev, text_prev].inspect
              sel.delete_at(i)
              i -= 1
            end
          end
        end
        messages = sel

        #if (not chat_mode) and (cab_panhash != mypanhash)
        #  filter = [['creator=', cab_panhash], ['destination=', mypanhash]]
        #  filter << chat_filter if chat_filter
        #  sel = model.select(filter, false, fields, 'id DESC', max_message)
        #  messages += sel
        #end

        if nil_create_time or (sort_mode==0) #sort by created
          messages.sort! do |a,b|
            res = (a[6]<=>b[6])
            res = (a[1]<=>b[1]) if (res==0) and (not nil_create_time)
            res
          end
        else   #sort by modified
          messages.sort! do |a,b|
            res = (a[1]<=>b[1])
            res = (a[6]<=>b[6]) if (res==0)
            res
          end
        end

        talkview.before_addition

        buf = nil
        first_id0 = first_id
        if first_id0
          buf = talkview.buffer
        end

        added = 0
        i = 0
        while i<messages.size do
          message = messages[i]
          id = message[7]
          if id and (first_id0.nil? or (id<first_id0))
            if (added==0) and buf
              buf.insert(buf.end_iter, "\n----------from_id="+id.to_s)
            end
            creator = message[0]
            created = message[1]
            mes = message[4]
            panstate = message[5]
            modified = message[6]

            first_id = id if (first_id.nil? or (id<first_id))

            add_mes_to_view(mes, id, panstate, false, creator, \
              myname, modified, created, (creator == mypanhash))
            added += 1
          end
          i += 1
        end
        if buf and (added>0)
          buf.insert(buf.end_iter, "\n=========id<"+first_id0.to_s)
        end

        if chat_mode
          @chat_first_id = first_id
        else
          @dialog_first_id = first_id
        end

        talkview.after_addition(true)
        talkview.show_all
        # Scroll because of the unknown gtk bug
        mark = talkview.buffer.create_mark(nil, talkview.buffer.end_iter, false)
        talkview.scroll_to_mark(mark, 0, true, 0.0, 1.0)
        talkview.buffer.delete_mark(mark)
      end
    end

    def clear_history(chat_mode, clear_database=nil)
      talkview = nil
      if clear_database
        mypanhash = PandoraCrypto.current_user_or_key(true)
        if mypanhash and PandoraGtk.show_dialog(\
        _('All messages of this conversation will be deleted from your database')+ \
        ".\n\n"+_('Sure?'), true, 'Deletion', :question)
          model = PandoraUtils.get_model('Message')
          chatbit = PandoraModel::PSF_ChatMes.to_s
          chat_sign = '>'
          cond = 'destination=?'
          args = [cab_panhash]
          if not chat_mode
            cond << ' AND creator=?'
            args << mypanhash
            if (cab_panhash != mypanhash)
              cond = '(('+cond+') OR (creator=? AND destination=?))'
              args << cab_panhash
              args << mypanhash
            end
            chat_sign = '='
          end
          filter = [cond+' AND IFNULL(panstate,0)&'+chatbit+chat_sign+'0', *args]
          p '---Delete messages: filter='+filter.inspect
          res = model.update(nil, nil, filter)
        else
          talkview = true
        end
      end
      if talkview.nil?
        if chat_mode
          talkview = @chat_talkview
          @chat_first_id = nil
        else
          talkview = @dlg_talkview
          @dialog_first_id = nil
        end
        if talkview
          talkview.mes_ids.clear
          talkview.buffer.text = ''
        end
      end
    end

    # Set session
    # RU: Задать сессию
    def set_session(session, online=true, keep=true)
      p '***---- set_session(session, online)='+[session.object_id, online].inspect
      @sessions ||= []
      if online
        @sessions << session if (not @sessions.include?(session))
        session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep) if keep
      else
        @sessions.delete(session)
        session.conn_mode = (session.conn_mode & (~PandoraNet::CM_Keep)) if keep
        session.dialog = nil
      end
      active = (@sessions.size>0)
      online_btn.safe_set_active(active) if (online_btn and (not online_btn.destroyed?))
      if active
        #online_btn.inconsistent = false if (not online_btn.destroyed?)
      else
        mic_btn.active = false if mic_btn and (not mic_btn.destroyed?) and mic_btn.active?
        webcam_btn.active = false if webcam_btn and (not webcam_btn.destroyed?) and webcam_btn.active?
        #mic_btn.safe_set_active(false) if (not mic_btn.destroyed?)
        #webcam_btn.safe_set_active(false) if (not webcam_btn.destroyed?)
      end
    end

    # Send message to node, before encrypt it if need
    # RU: Отправляет сообщение на узел, шифрует предварительно если надо
    def send_mes(text, crypt=nil, sign_trust=nil, chat_mode=false)
      res = false
      creator = PandoraCrypto.current_user_or_key(true)
      if creator
        if (not chat_mode) and (not online_btn.active?)
          online_btn.active = true
        end
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        panstate = 0
        crypt_text = text
        sign = (not sign_trust.nil?)
        panstate = (panstate | PandoraModel::PSF_ChatMes) if chat_mode
        if crypt or sign
          panstate = (panstate | PandoraModel::PSF_Support)
          keyhash = PandoraCrypto.current_user_or_key(false, false)
          if keyhash
            if crypt
              crypt_text = PandoraCrypto.recrypt_mes(text, keyhash)
              panstate = (panstate | PandoraModel::PSF_Crypted)
            end
            panstate = (panstate | PandoraModel::PSF_Verified) if sign
          else
            crypt = sign = false
          end
        end
        dest = cab_panhash
        values = {:destination=>dest, :text=>crypt_text, :state=>state, \
          :creator=>creator, :created=>time_now, :modified=>time_now, :panstate=>panstate}
        model = PandoraUtils.get_model('Message')
        panhash = model.calc_panhash(values)
        values[:panhash] = panhash
        res = model.update(values, nil, nil, sign)
        if res
          filter = {:panhash=>panhash, :created=>time_now}
          sel = model.select(filter, true, 'id', 'id DESC', 1)
          if sel and (sel.size>0)
            p 'send_mes sel='+sel.inspect
            if sign
              namesvalues = model.namesvalues
              namesvalues['text'] = text   #restore pure text for sign
              if not PandoraCrypto.sign_panobject(model, sign_trust)
                panstate = panstate & (~ PandoraModel::PSF_Verified)
                res = model.update(filter, nil, {:panstate=>panstate})
                PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot create sign')+' ['+text+']')
              end
            end
            id = sel[0][0]
            add_mes_to_view(crypt_text, id, panstate, true, creator, nil, nil, nil, true)
          else
            PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot read message')+' ['+text+']')
          end
        else
          PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot insert message')+' ['+text+']')
        end
        if chat_mode
          $pool.send_chat_messages
        else
          sessions = $pool.sessions_on_dialog(self)
          sessions.each do |session|
            session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep)
            session.send_state = (session.send_state | PandoraNet::CSF_Message)
          end
        end
      end
      res
    end

    $statusicon = nil

    # Update tab color when received new data
    # RU: Обновляет цвет закладки при получении новых данных
    def update_state(received=true, curpage=nil)
      tab_widget = $window.notebook.get_tab_label(self)
      if tab_widget
        curpage ||= $window.notebook.get_nth_page($window.notebook.page)
        # interrupt reading thread (if exists)
        if $last_page and $last_page.is_a?(CabinetBox) \
        and $last_page.read_thread and (curpage != $last_page)
          $last_page.read_thread.exit
          $last_page.read_thread = nil
        end
        # set self dialog as unread
        if received
          @has_unread = true
          color = Gdk::Color.parse($tab_color)
          tab_widget.label.modify_fg(Gtk::STATE_NORMAL, color)
          tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, color)
          $statusicon.set_message(_('Message')+' ['+tab_widget.label.text+']')
          PandoraUtils.play_mp3('message')
        end
        # run reading thread
        timer_setted = false
        if (not self.read_thread) and (curpage == self) and $window.visible? \
        and $window.has_toplevel_focus?
          #color = $window.modifier_style.text(Gtk::STATE_NORMAL)
          #curcolor = tab_widget.label.modifier_style.fg(Gtk::STATE_ACTIVE)
          if @has_unread #curcolor and (color != curcolor)
            timer_setted = true
            self.read_thread = Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and curpage.dlg_talkview and \
              (not curpage.dlg_talkview.destroyed?) and curpage.dlg_talkview.edit_box \
              and (not curpage.dlg_talkview.edit_box.destroyed?)
                curpage.dlg_talkview.edit_box.grab_focus if curpage.dlg_talkview.edit_box.visible?
                curpage.dlg_talkview.after_addition(true)
              end
              if $window.visible? and $window.has_toplevel_focus?
                read_sec = $read_time-0.3
                if read_sec >= 0
                  sleep(read_sec)
                end
                if $window.visible? and $window.has_toplevel_focus?
                  if (not self.destroyed?) and (not tab_widget.destroyed?) \
                  and (not tab_widget.label.destroyed?)
                    @has_unread = false
                    tab_widget.label.modify_fg(Gtk::STATE_NORMAL, nil)
                    tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, nil)
                    $statusicon.set_message(nil)
                  end
                end
              end
              self.read_thread = nil
            end
          end
        end
        # set focus to edit_box
        if curpage and curpage.is_a?(CabinetBox) #and curpage.edit_box
          curpage.grab_def_widget
        end
      end
    end

    # Parse Gstreamer string
    # RU: Распознаёт строку Gstreamer
    def parse_gst_string(text)
      elements = Array.new
      text.strip!
      elem = nil
      link = false
      i = 0
      while i<text.size
        j = 0
        while (i+j<text.size) \
        and (not ([' ', '=', "\\", '!', '/', 10.chr, 13.chr].include? text[i+j, 1]))
          j += 1
        end
        #p [i, j, text[i+j, 1], text[i, j]]
        word = nil
        param = nil
        val = nil
        if i+j<text.size
          sym = text[i+j, 1]
          if ['=', '/'].include? sym
            if sym=='='
              param = text[i, j]
              i += j
            end
            i += 1
            j = 0
            quotes = false
            while (i+j<text.size) and (quotes \
            or (not ([' ', "\\", '!', 10.chr, 13.chr].include? text[i+j, 1])))
              if quotes
                if text[i+j, 1]=='"'
                  quotes = false
                end
              elsif (j==0) and (text[i+j, 1]=='"')
                quotes = true
              end
              j += 1
            end
            sym = text[i+j, 1]
            val = text[i, j].strip
            val = val[1..-2] if val and (val.size>1) and (val[0]=='"') and (val[-1]=='"')
            val.strip!
            param.strip! if param
            if (not param) or (param=='')
              param = 'caps'
              if not elem
                word = 'capsfilter'
                elem = elements.size
                elements[elem] = [word, {}]
              end
            end
            #puts '++  [word, param, val]='+[word, param, val].inspect
          else
            word = text[i, j]
          end
          link = true if sym=='!'
        else
          word = text[i, j]
        end
        #p 'word='+word.inspect
        word.strip! if word
        #p '---[word, param, val]='+[word, param, val].inspect
        if param or val
          elements[elem][1][param] = val if elem and param and val
        elsif word and (word != '')
          elem = elements.size
          elements[elem] = [word, {}]
        end
        if link
          elements[elem][2] = true if elem
          elem = nil
          link = false
        end
        #p '===elements='+elements.inspect
        i += j+1
      end
      elements
    end

    # Append elements to pipeline
    # RU: Добавляет элементы в конвейер
    def append_elems_to_pipe(elements, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      # create elements and add to pipeline
      #p '---- begin add&link elems='+elements.inspect
      elements.each do |elem_desc|
        factory = elem_desc[0]
        params = elem_desc[1]
        if factory and (factory != '')
          i = factory.index('.')
          if not i
            elemname = nil
            elemname = factory+name_suff if name_suff
            if $gst_old
              if ((factory=='videoconvert') or (factory=='autovideoconvert'))
                factory = 'ffmpegcolorspace'
              end
            elsif (factory=='ffmpegcolorspace')
              factory = 'videoconvert'
            end
            elem = Gst::ElementFactory.make(factory, elemname)
            if elem
              elem_desc[3] = elem
              if params.is_a? Hash
                params.each do |k, v|
                  v0 = elem.get_property(k)
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  #v = v[1,-2] if v and (v.size>1) and (v[0]=='"') and (v[-1]=='"')
                  #puts 'v='+v.inspect
                  if (k=='caps') or (v0.is_a? Gst::Caps)
                    if $gst_old
                      v = Gst::Caps.parse(v)
                    else
                      v = Gst::Caps.from_string(v)
                    end
                  elsif (v0.is_a? Integer) or (v0.is_a? Float)
                    if v.index('.')
                      v = v.to_f
                    else
                      v = v.to_i
                    end
                  elsif (v0.is_a? TrueClass) or (v0.is_a? FalseClass)
                    v = ((v=='true') or (v=='1'))
                  end
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  elem.set_property(k, v)
                  #p '----'
                  elem_desc[4] = v if k=='name'
                end
              end
              pipeline.add(elem) if pipeline
            else
              p 'Cannot create gstreamer element "'+factory+'"'
            end
          end
        end
      end
      # resolve names
      elements.each do |elem_desc|
        factory = elem_desc[0]
        link = elem_desc[2]
        if factory and (factory != '')
          #p '----'
          #p factory
          i = factory.index('.')
          if i
            name = factory[0,i]
            #p 'name='+name
            if name and (name != '')
              elem_desc = elements.find{ |ed| ed[4]==name }
              elem = elem_desc[3]
              if not elem
                p 'find by name in pipeline!!'
                p elem = pipeline.get_by_name(name)
              end
              elem[3] = elem if elem
              if elem
                pad = factory[i+1, -1]
                elem[5] = pad if pad and (pad != '')
              end
              #p 'elem[3]='+elem[3].inspect
            end
          end
        end
      end
      # link elements
      link1 = false
      elem1 = nil
      pad1  = nil
      if prev_elem
        link1 = true
        elem1 = prev_elem
        pad1  = prev_pad
      end
      elements.each_with_index do |elem_desc|
        link2 = elem_desc[2]
        elem2 = elem_desc[3]
        pad2  = elem_desc[5]
        if link1 and elem1 and elem2
          if pad1 or pad2
            pad1 ||= 'src'
            apad2 = pad2
            apad2 ||= 'sink'
            p 'pad elem1.pad1 >> elem2.pad2 - '+[elem1, pad1, elem2, apad2].inspect
            elem1.get_pad(pad1).link(elem2.get_pad(apad2))
          else
            #p 'elem1 >> elem2 - '+[elem1, elem2].inspect
            elem1 >> elem2
          end
        end
        link1 = link2
        elem1 = elem2
        pad1  = pad2
      end
      #p '===final add&link'
      [elem1, pad1]
    end

    # Append element to pipeline
    # RU: Добавляет элемент в конвейер
    def add_elem_to_pipe(str, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      elements = parse_gst_string(str)
      elem, pad = append_elems_to_pipe(elements, pipeline, prev_elem, prev_pad, name_suff)
      [elem, pad]
    end

    # Link sink element to area of widget
    # RU: Прицепляет сливной элемент к области виджета
    def link_sink_to_area(sink, area, pipeline=nil)

      # Set handle of window
      # RU: Устанавливает дескриптор окна
      def set_xid(area, sink)
        if (not area.destroyed?) and area.window and sink \
        and (sink.class.method_defined?('set_xwindow_id'))
          win_id = nil
          if PandoraUtils.os_family=='windows'
            win_id = area.window.handle
          else
            win_id = area.window.xid
          end
          sink.set_property('force-aspect-ratio', true)
          sink.set_xwindow_id(win_id)
        end
      end

      res = nil
      if area and (not area.destroyed?)
        if (not area.window) and pipeline
          area.realize
          #Gtk.main_iteration
        end
        #p 'link_sink_to_area(sink, area, pipeline)='+[sink, area, pipeline].inspect
        set_xid(area, sink)
        if pipeline and (not pipeline.destroyed?)
          pipeline.bus.add_watch do |bus, message|
            if (message and message.structure and message.structure.name \
            and (message.structure.name == 'prepare-xwindow-id'))
              Gdk::Threads.synchronize do
                Gdk::Display.default.sync
                asink = message.src
                set_xid(area, asink)
              end
            end
            true
          end

          res = area.signal_connect('expose-event') do |*args|
            set_xid(area, sink)
          end
          area.set_expose_event(res)
        end
      end
      res
    end

    # Get video sender parameters
    # RU: Берёт параметры отправителя видео
    def get_video_sender_params(src_param = 'video_src_v4l2', \
      send_caps_param = 'video_send_caps_raw_320x240', send_tee_param = 'video_send_tee_def', \
      view1_param = 'video_view1_xv', can_encoder_param = 'video_can_encoder_vp8', \
      can_sink_param = 'video_can_sink_app')

      # getting from setup (will be feature)
      src         = PandoraUtils.get_param(src_param)
      send_caps   = PandoraUtils.get_param(send_caps_param)
      send_tee    = PandoraUtils.get_param(send_tee_param)
      view1       = PandoraUtils.get_param(view1_param)
      can_encoder = PandoraUtils.get_param(can_encoder_param)
      can_sink    = PandoraUtils.get_param(can_sink_param)

      # default param (temporary)
      #src = 'v4l2src decimate=3'
      #send_caps = 'video/x-raw-rgb,width=320,height=240'
      #send_tee = 'ffmpegcolorspace ! tee name=vidtee'
      #view1 = 'queue ! xvimagesink force-aspect-ratio=true'
      #can_encoder = 'vp8enc max-latency=0.5'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, view1, can_encoder, can_sink]
    end

    $send_media_pipelines = {}
    $webcam_xvimagesink   = nil

    # Initialize video sender
    # RU: Инициализирует отправщика видео
    def init_video_sender(start=true, just_upd_area=false, init=true)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and (PandoraUtils.elem_playing?($webcam_xvimagesink))
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          area_send.set_expose_event(nil) if init
          tsw = PandoraGtk.find_another_active_sender(self)
          if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
          and tsw.area_send and tsw.area_send.window
            link_sink_to_area($webcam_xvimagesink, tsw.area_send)
            #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
          end
          #p '--LEAVE'
          area_send.queue_draw if area_send and (not area_send.destroyed?)
        else
          #$webcam_xvimagesink.xwindow_id = 0
          count = PandoraGtk.nil_send_ptrind_by_panhash(room_id)
          if video_pipeline and (count==0) and (not PandoraUtils::elem_stopped?(video_pipeline))
            video_pipeline.stop
            area_send.set_expose_event(nil)
            #p '==STOP!!'
          end
        end
        #Thread.pass
      elsif (not self.destroyed?) and webcam_btn and (not webcam_btn.destroyed?) and webcam_btn.active? \
      and area_send and (not area_send.destroyed?)
        if not video_pipeline
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            video_pipeline = Gst::Pipeline.new('spipe_v')

            ##video_src = 'v4l2src decimate=3'
            ##video_src_caps = 'capsfilter caps="video/x-raw-rgb,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240" ! videorate drop=10'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv, framerate=10/1, width=320, height=240"'
            #video_src_caps = 'capsfilter caps="width=320,height=240"'
            ##video_send_tee = 'ffmpegcolorspace ! tee name=vidtee'
            #video_send_tee = 'tee name=tee1'
            ##video_view1 = 'queue ! xvimagesink force-aspect-ratio=true'
            ##video_can_encoder = 'vp8enc max-latency=0.5'
            #video_can_encoder = 'vp8enc speed=2 max-latency=2 quality=5.0 max-keyframe-distance=3 threads=5'
            #video_can_encoder = 'ffmpegcolorspace ! videoscale ! theoraenc quality=16 ! queue'
            #video_can_encoder = 'jpegenc quality=80'
            #video_can_encoder = 'jpegenc'
            #video_can_encoder = 'mimenc'
            #video_can_encoder = 'mpeg2enc'
            #video_can_encoder = 'diracenc'
            #video_can_encoder = 'xvidenc'
            #video_can_encoder = 'ffenc_flashsv'
            #video_can_encoder = 'ffenc_flashsv2'
            #video_can_encoder = 'smokeenc keyframe=8 qmax=40'
            #video_can_encoder = 'theoraenc bitrate=128'
            #video_can_encoder = 'theoraenc ! oggmux'
            #video_can_encoder = videorate ! videoscale ! x264enc bitrate=256 byte-stream=true'
            #video_can_encoder = 'queue ! x264enc bitrate=96'
            #video_can_encoder = 'ffenc_h263'
            #video_can_encoder = 'h264enc'
            ##video_can_sink = 'appsink emit-signals=true'

            src_param = PandoraUtils.get_param('video_src')
            send_caps_param = PandoraUtils.get_param('video_send_caps')
            send_tee_param = 'video_send_tee_def'
            view1_param = PandoraUtils.get_param('video_view1')
            can_encoder_param = PandoraUtils.get_param('video_can_encoder')
            can_sink_param = 'video_can_sink_app'

            video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink \
              = get_video_sender_params(src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param)
            p [src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param]
            p [video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink]

            if winos
              video_src = PandoraUtils.get_param('video_src_win')
              video_src ||= 'dshowvideosrc'
              #video_src ||= 'videotestsrc'
              video_view1 = PandoraUtils.get_param('video_view1_win')
              video_view1 ||= 'queue ! directdrawsink'
              #video_view1 ||= 'queue ! d3dvideosink'
            end

            $webcam_xvimagesink = nil
            webcam, pad = add_elem_to_pipe(video_src, video_pipeline)
            if webcam
              capsfilter, pad = add_elem_to_pipe(video_send_caps, video_pipeline, webcam, pad)
              p 'capsfilter='+capsfilter.inspect
              tee, teepad = add_elem_to_pipe(video_send_tee, video_pipeline, capsfilter, pad)
              p 'tee='+tee.inspect
              encoder, pad = add_elem_to_pipe(video_can_encoder, video_pipeline, tee, teepad)
              p 'encoder='+encoder.inspect
              if encoder
                appsink, pad = add_elem_to_pipe(video_can_sink, video_pipeline, encoder, pad)
                p 'appsink='+appsink.inspect
                $webcam_xvimagesink, pad = add_elem_to_pipe(video_view1, video_pipeline, tee, teepad)
                p '$webcam_xvimagesink='+$webcam_xvimagesink.inspect
              end
            end

            if $webcam_xvimagesink
              $send_media_pipelines['video'] = video_pipeline
              $send_media_queues[1] ||= PandoraUtils::RoundQueue.new(true)
              #appsink.signal_connect('new-preroll') do |appsink|
              #appsink.signal_connect('new-sample') do |appsink|
              appsink.signal_connect('new-buffer') do |appsink|
                #p 'appsink new buf!!!'
                #buf = appsink.pull_preroll
                #buf = appsink.pull_sample
                buf = appsink.pull_buffer
                if buf
                  data = buf.data
                  $send_media_queues[1].add_block_to_queue(data, $media_buf_size)
                end
              end
            else
              video_pipeline.destroy if video_pipeline
            end
          rescue => err
            $send_media_pipelines['video'] = nil
            mes = 'Camera init exception'
            PandoraUI.log_message(PandoraUI::LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            webcam_btn.active = false
          end
        end

        if video_pipeline
          if $webcam_xvimagesink and area_send #and area_send.window
            #$webcam_xvimagesink.xwindow_id = area_send.window.xid
            link_sink_to_area($webcam_xvimagesink, area_send)
          end
          if not just_upd_area
            #???
            video_pipeline.stop if (not PandoraUtils::elem_stopped?(video_pipeline))
            area_send.set_expose_event(nil)
          end
          #if not area_send.expose_event
            link_sink_to_area($webcam_xvimagesink, area_send, video_pipeline)
          #end
          #if $webcam_xvimagesink and area_send and area_send.window
          #  #$webcam_xvimagesink.xwindow_id = area_send.window.xid
          #  link_sink_to_area($webcam_xvimagesink, area_send)
          #end
          if just_upd_area
            video_pipeline.play if (not PandoraUtils.elem_playing?(video_pipeline))
          else
            ptrind = PandoraGtk.set_send_ptrind_by_panhash(room_id)
            count = PandoraGtk.nil_send_ptrind_by_panhash(nil)
            if count>0
              #Gtk.main_iteration
              #???
              p 'PLAAAAAAAAAAAAAAY 1'
              p PandoraUtils.elem_playing?(video_pipeline)
              video_pipeline.play if (not PandoraUtils.elem_playing?(video_pipeline))
              p 'PLAAAAAAAAAAAAAAY 2'
              #p '==*** PLAY'
            end
          end
          #if $webcam_xvimagesink and ($webcam_xvimagesink.get_state != Gst::STATE_PLAYING) \
          #and (video_pipeline.get_state == Gst::STATE_PLAYING)
          #  $webcam_xvimagesink.play
          #end
        end
      end
      video_pipeline
    end

    # Get video receiver parameters
    # RU: Берёт параметры приёмщика видео
    def get_video_receiver_params(can_src_param = 'video_can_src_app', \
      can_decoder_param = 'video_can_decoder_vp8', recv_tee_param = 'video_recv_tee_def', \
      view2_param = 'video_view2_x')

      # getting from setup (will be feature)
      can_src     = PandoraUtils.get_param(can_src_param)
      can_decoder = PandoraUtils.get_param(can_decoder_param)
      recv_tee    = PandoraUtils.get_param(recv_tee_param)
      view2       = PandoraUtils.get_param(view2_param)

      # default param (temporary)
      #can_src     = 'appsrc emit-signals=false'
      #can_decoder = 'vp8dec'
      #recv_tee    = 'ffmpegcolorspace ! tee'
      #view2       = 'ximagesink sync=false'

      [can_src, can_decoder, recv_tee, view2]
    end

    # Initialize video receiver
    # RU: Инициализирует приёмщика видео
    def init_video_receiver(start=true, can_play=true, init=true)
      p '--init_video_receiver [start, can_play, init]='+[start, can_play, init].inspect
      if not start
        if ximagesink and PandoraUtils.elem_playing?(ximagesink)
          if can_play
            ximagesink.pause
          else
            ximagesink.stop
          end
        end
        if (not can_play) or (not ximagesink)
          p 'Disconnect HANDLER !!!'
          area_recv.set_expose_event(nil)
        end
      elsif (not self.destroyed?) and area_recv and (not area_recv.destroyed?)
        if (not recv_media_pipeline[1]) and init
          begin
            Gst.init
            p 'init_video_receiver INIT'
            winos = (PandoraUtils.os_family == 'windows')
            @recv_media_queue[1] ||= PandoraUtils::RoundQueue.new
            dialog_id = '_v'+PandoraUtils.bytes_to_hex(room_id[-6..-1])
            @recv_media_pipeline[1] = Gst::Pipeline.new('rpipe'+dialog_id)
            vidpipe = @recv_media_pipeline[1]

            ##video_can_src = 'appsrc emit-signals=false'
            ##video_can_decoder = 'vp8dec'
            #video_can_decoder = 'xviddec'
            #video_can_decoder = 'ffdec_flashsv'
            #video_can_decoder = 'ffdec_flashsv2'
            #video_can_decoder = 'queue ! theoradec ! videoscale ! capsfilter caps="video/x-raw,width=320"'
            #video_can_decoder = 'jpegdec'
            #video_can_decoder = 'schrodec'
            #video_can_decoder = 'smokedec'
            #video_can_decoder = 'oggdemux ! theoradec'
            #video_can_decoder = 'theoradec'
            #! video/x-h264,width=176,height=144,framerate=25/1 ! ffdec_h264 ! videorate
            #video_can_decoder = 'x264dec'
            #video_can_decoder = 'mpeg2dec'
            #video_can_decoder = 'mimdec'
            ##video_recv_tee = 'ffmpegcolorspace ! tee'
            #video_recv_tee = 'tee'
            ##video_view2 = 'ximagesink sync=false'
            #video_view2 = 'queue ! xvimagesink force-aspect-ratio=true sync=false'

            can_src_param = 'video_can_src_app'
            can_decoder_param = PandoraUtils.get_param('video_can_decoder')
            recv_tee_param = 'video_recv_tee_def'
            view2_param = PandoraUtils.get_param('video_view2')

            video_can_src, video_can_decoder, video_recv_tee, video_view2 \
              = get_video_receiver_params(can_src_param, can_decoder_param, \
                recv_tee_param, view2_param)

            if winos
              video_view2 = PandoraUtils.get_param('video_view2_win')
              video_view2 ||= 'queue ! directdrawsink'
            end

            @appsrcs[1], pad = add_elem_to_pipe(video_can_src, vidpipe, nil, nil, dialog_id)
            decoder, pad = add_elem_to_pipe(video_can_decoder, vidpipe, appsrcs[1], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(video_recv_tee, vidpipe, decoder, pad, dialog_id)
            @ximagesink, pad = add_elem_to_pipe(video_view2, vidpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[1] = nil
            mes = 'Video receiver init exception'
            PandoraUI.log_message(PandoraUI::LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            webcam_btn.active = false
          end
        end

        if @ximagesink and init #and area_recv.window
          link_sink_to_area(@ximagesink, area_recv, recv_media_pipeline[1])
        end

        #p '[recv_media_pipeline[1], can_play]='+[recv_media_pipeline[1], can_play].inspect
        if recv_media_pipeline[1] and can_play and area_recv.window
          #if (not area_recv.expose_event) and
          if (not PandoraUtils.elem_playing?(recv_media_pipeline[1])) \
          or (not PandoraUtils.elem_playing?(ximagesink))
            #p 'PLAYYYYYYYYYYYYYYYYYY!!!!!!!!!! '
            #ximagesink.stop
            #recv_media_pipeline[1].stop
            ximagesink.play
            recv_media_pipeline[1].play
          end
        end
      end
    end

    # Get audio sender parameters
    # RU: Берёт параметры отправителя аудио
    def get_audio_sender_params(src_param = 'audio_src_alsa', \
      send_caps_param = 'audio_send_caps_8000', send_tee_param = 'audio_send_tee_def', \
      can_encoder_param = 'audio_can_encoder_vorbis', can_sink_param = 'audio_can_sink_app')

      # getting from setup (will be feature)
      src = PandoraUtils.get_param(src_param)
      send_caps = PandoraUtils.get_param(send_caps_param)
      send_tee = PandoraUtils.get_param(send_tee_param)
      can_encoder = PandoraUtils.get_param(can_encoder_param)
      can_sink = PandoraUtils.get_param(can_sink_param)

      # default param (temporary)
      #src = 'alsasrc device=hw:0'
      #send_caps = 'audio/x-raw-int,rate=8000,channels=1,depth=8,width=8'
      #send_tee = 'audioconvert ! tee name=audtee'
      #can_encoder = 'vorbisenc quality=0.0'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      src = src + ' ! audioconvert ! audioresample'
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, can_encoder, can_sink]
    end

    # Initialize audio sender
    # RU: Инициализирует отправителя аудио
    def init_audio_sender(start=true, just_upd_area=false)
      audio_pipeline = $send_media_pipelines['audio']
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+mic_btn.active?.inspect
      if not start
        #count = PandoraGtk.nil_send_ptrind_by_panhash(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (not PandoraUtils::elem_stopped?(audio_pipeline))
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not mic_btn.destroyed?) and mic_btn.active?
        if not audio_pipeline
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            audio_pipeline = Gst::Pipeline.new('spipe_a')
            $send_media_pipelines['audio'] = audio_pipeline

            ##audio_src = 'alsasrc device=hw:0 ! audioconvert ! audioresample'
            #audio_src = 'autoaudiosrc'
            #audio_src = 'alsasrc'
            #audio_src = 'audiotestsrc'
            #audio_src = 'pulsesrc'
            ##audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,channels=1,depth=8,width=8"'
            #audio_src_caps = 'queue ! capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=22000,channels=1"'
            #audio_src_caps = 'queue'
            ##audio_send_tee = 'audioconvert ! tee name=audtee'
            #audio_can_encoder = 'vorbisenc'
            ##audio_can_encoder = 'vorbisenc quality=0.0'
            #audio_can_encoder = 'vorbisenc quality=0.0 bitrate=16000 managed=true' #8192
            #audio_can_encoder = 'vorbisenc quality=0.0 max-bitrate=32768' #32768  16384  65536
            #audio_can_encoder = 'mulawenc'
            #audio_can_encoder = 'lamemp3enc bitrate=8 encoding-engine-quality=speed fast-vbr=true'
            #audio_can_encoder = 'lamemp3enc bitrate=8 target=bitrate mono=true cbr=true'
            #audio_can_encoder = 'speexenc'
            #audio_can_encoder = 'voaacenc'
            #audio_can_encoder = 'faac'
            #audio_can_encoder = 'a52enc'
            #audio_can_encoder = 'voamrwbenc'
            #audio_can_encoder = 'adpcmenc'
            #audio_can_encoder = 'amrnbenc'
            #audio_can_encoder = 'flacenc'
            #audio_can_encoder = 'ffenc_nellymoser'
            #audio_can_encoder = 'speexenc vad=true vbr=true'
            #audio_can_encoder = 'speexenc vbr=1 dtx=1 nframes=4'
            #audio_can_encoder = 'opusenc'
            ##audio_can_sink = 'appsink emit-signals=true'

            src_param = PandoraUtils.get_param('audio_src')
            send_caps_param = PandoraUtils.get_param('audio_send_caps')
            send_tee_param = 'audio_send_tee_def'
            can_encoder_param = PandoraUtils.get_param('audio_can_encoder')
            can_sink_param = 'audio_can_sink_app'

            audio_src, audio_send_caps, audio_send_tee, audio_can_encoder, audio_can_sink  \
              = get_audio_sender_params(src_param, send_caps_param, send_tee_param, \
                can_encoder_param, can_sink_param)

            if winos
              audio_src = PandoraUtils.get_param('audio_src_win')
              audio_src ||= 'dshowaudiosrc'
            end

            micro, pad = add_elem_to_pipe(audio_src, audio_pipeline)
            capsfilter, pad = add_elem_to_pipe(audio_send_caps, audio_pipeline, micro, pad)
            tee, teepad = add_elem_to_pipe(audio_send_tee, audio_pipeline, capsfilter, pad)
            audenc, pad = add_elem_to_pipe(audio_can_encoder, audio_pipeline, tee, teepad)
            appsink, pad = add_elem_to_pipe(audio_can_sink, audio_pipeline, audenc, pad)

            $send_media_queues[0] ||= PandoraUtils::RoundQueue.new(true)
            appsink.signal_connect('new-buffer') do |appsink|
              buf = appsink.pull_buffer
              if buf
                #p 'GET AUDIO ['+buf.size.to_s+']'
                data = buf.data
                $send_media_queues[0].add_block_to_queue(data, $media_buf_size)
              end
            end
          rescue => err
            $send_media_pipelines['audio'] = nil
            mes = 'Microphone init exception'
            PandoraUI.log_message(PandoraUI::LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            mic_btn.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGtk.set_send_ptrind_by_panhash(room_id)
          count = PandoraGtk.nil_send_ptrind_by_panhash(nil)
          #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
          if (count>0) and (not PandoraUtils::elem_playing?(audio_pipeline))
          #if (audio_pipeline.get_state != Gst::STATE_PLAYING)
            audio_pipeline.play
          end
        end
      end
      audio_pipeline
    end

    # Get audio receiver parameters
    # RU: Берёт параметры приёмщика аудио
    def get_audio_receiver_params(can_src_param = 'audio_can_src_app', \
      can_decoder_param = 'audio_can_decoder_vorbis', recv_tee_param = 'audio_recv_tee_def', \
      phones_param = 'audio_phones_auto')

      # getting from setup (will be feature)
      can_src     = PandoraUtils.get_param(can_src_param)
      can_decoder = PandoraUtils.get_param(can_decoder_param)
      recv_tee    = PandoraUtils.get_param(recv_tee_param)
      phones      = PandoraUtils.get_param(phones_param)

      # default param (temporary)
      #can_src = 'appsrc emit-signals=false'
      #can_decoder = 'vorbisdec'
      #recv_tee = 'audioconvert ! tee'
      #phones = 'autoaudiosink'

      [can_src, can_decoder, recv_tee, phones]
    end

    # Initialize audio receiver
    # RU: Инициализирует приёмщика аудио
    def init_audio_receiver(start=true, can_play=true, init=true)
      if not start
        if recv_media_pipeline[0] and (not PandoraUtils::elem_stopped?(recv_media_pipeline[0]))
          recv_media_pipeline[0].stop
        end
      elsif (not self.destroyed?)
        if (not recv_media_pipeline[0]) and init
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            @recv_media_queue[0] ||= PandoraUtils::RoundQueue.new
            dialog_id = '_a'+PandoraUtils.bytes_to_hex(room_id[-6..-1])
            #p 'init_audio_receiver:  dialog_id='+dialog_id.inspect
            @recv_media_pipeline[0] = Gst::Pipeline.new('rpipe'+dialog_id)
            audpipe = @recv_media_pipeline[0]

            ##audio_can_src = 'appsrc emit-signals=false'
            #audio_can_src = 'appsrc'
            ##audio_can_decoder = 'vorbisdec'
            #audio_can_decoder = 'mulawdec'
            #audio_can_decoder = 'speexdec'
            #audio_can_decoder = 'decodebin'
            #audio_can_decoder = 'decodebin2'
            #audio_can_decoder = 'flump3dec'
            #audio_can_decoder = 'amrwbdec'
            #audio_can_decoder = 'adpcmdec'
            #audio_can_decoder = 'amrnbdec'
            #audio_can_decoder = 'voaacdec'
            #audio_can_decoder = 'faad'
            #audio_can_decoder = 'ffdec_nellymoser'
            #audio_can_decoder = 'flacdec'
            ##audio_recv_tee = 'audioconvert ! tee'
            #audio_phones = 'alsasink'
            ##audio_phones = 'autoaudiosink'
            #audio_phones = 'pulsesink'

            can_src_param = 'audio_can_src_app'
            can_decoder_param = PandoraUtils.get_param('audio_can_decoder')
            recv_tee_param = 'audio_recv_tee_def'
            phones_param = PandoraUtils.get_param('audio_phones')

            audio_can_src, audio_can_decoder, audio_recv_tee, audio_phones \
              = get_audio_receiver_params(can_src_param, can_decoder_param, recv_tee_param, phones_param)

            if winos
              audio_phones = PandoraUtils.get_param('audio_phones_win')
              audio_phones ||= 'autoaudiosink'
            end

            @appsrcs[0], pad = add_elem_to_pipe(audio_can_src, audpipe, nil, nil, dialog_id)
            auddec, pad = add_elem_to_pipe(audio_can_decoder, audpipe, appsrcs[0], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(audio_recv_tee, audpipe, auddec, pad, dialog_id)
            audiosink, pad = add_elem_to_pipe(audio_phones, audpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[0] = nil
            mes = 'Audio receiver init exception'
            PandoraUI.log_message(PandoraUI::LM_Warning, _(mes))
            puts mes+': '+Utf8String.new(err.message)
            mic_btn.active = false
          end
          recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
        end
        if recv_media_pipeline[0] and can_play
          recv_media_pipeline[0].play if (not PandoraUtils::elem_playing?(recv_media_pipeline[0]))
        end
      end
    end
  end  #--class CabinetBox

  # Search panel
  # RU: Панель поиска
  class SearchBox < Gtk::VBox #Gtk::ScrolledWindow
    attr_accessor :text

    include PandoraGtk

    def show_all_reqs(reqs=nil)
      pool = $pool
      if reqs or (not @last_mass_ind) or (@last_mass_ind < pool.mass_ind)
        @list_store.clear
        reqs ||= pool.mass_records.queue
        #p '-----------reqs='+reqs.inspect
        reqs.each do |mr|
          if (mr.is_a? Array) and (mr[PandoraNet::MR_Kind] == PandoraNet::MK_Search)
            user_iter = @list_store.append
            user_iter[0] = mr[PandoraNet::MR_CrtTime]
            user_iter[1] = Utf8String.new(mr[PandoraNet::MRS_Request])
            user_iter[2] = Utf8String.new(mr[PandoraNet::MRS_Kind])
            user_iter[3] = Utf8String.new(mr[PandoraNet::MRA_Answer].inspect)
          end
        end
        if reqs
          @last_mass_ind = nil
        else
          @last_mass_ind = pool.mass_ind
        end
      end
    end

    # Show search window
    # RU: Показать окно поиска
    def initialize(text=nil)
      super #(nil, nil)

      @text = nil

      #set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #vbox = Gtk::VBox.new
      #vpaned = Gtk::VPaned.new
      vbox = self

      search_btn = Gtk::ToolButton.new(Gtk::Stock::FIND, _('Search'))
      search_btn.tooltip_text = _('Start searching')
      PandoraGtk.set_readonly(search_btn, true)

      stop_btn = Gtk::ToolButton.new(Gtk::Stock::STOP, _('Stop'))
      stop_btn.tooltip_text = _('Stop searching')
      PandoraGtk.set_readonly(stop_btn, true)

      prev_btn = Gtk::ToolButton.new(Gtk::Stock::GO_BACK, _('Previous'))
      prev_btn.tooltip_text = _('Previous search')
      PandoraGtk.set_readonly(prev_btn, true)

      next_btn = Gtk::ToolButton.new(Gtk::Stock::GO_FORWARD, _('Next'))
      next_btn.tooltip_text = _('Next search')
      PandoraGtk.set_readonly(next_btn, true)

      @list_store = Gtk::ListStore.new(Integer, String, String, String)

      search_entry = Gtk::Entry.new
      #PandoraGtk.hack_enter_bug(search_entry)
      search_entry.signal_connect('key-press-event') do |widget, event|
        res = false
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          search_btn.clicked
          res = true
        elsif (Gdk::Keyval::GDK_Escape==event.keyval)
          stop_btn.clicked
          res = true
        end
        res
      end
      search_entry.signal_connect('changed') do |widget, event|
        empty = (search_entry.text.size==0)
        PandoraGtk.set_readonly(search_btn, empty)
        if empty
          show_all_reqs
        else
          if @last_mass_ind
            @list_store.clear
            @last_mass_ind = nil
          end
        end
        false
      end

      kind_entry = Gtk::Combo.new
      kind_list = PandoraModel.get_kind_list
      name_list = []
      name_list << 'auto'
      #name_list.concat( kind_list.collect{ |rec| rec[2] + ' ('+rec[0].to_s+'='+rec[1]+')' } )
      name_list.concat( kind_list.collect{ |rec| rec[1] } )
      kind_entry.set_popdown_strings(name_list)
      #kind_entry.entry.select_region(0, -1)

      #kind_entry = Gtk::ComboBox.new(true)
      #kind_entry.append_text('auto')
      #kind_entry.append_text('person')
      #kind_entry.append_text('file')
      #kind_entry.append_text('all')
      #kind_entry.active = 0
      #kind_entry.wrap_width = 3
      #kind_entry.has_frame = true

      kind_entry.set_size_request(100, -1)
      #p stop_btn.allocation.width
      #search_width = $window.allocation.width-kind_entry.allocation.width-stop_btn.allocation.width*4
      search_entry.set_size_request(150, -1)

      hbox = Gtk::HBox.new
      hbox.pack_start(kind_entry, false, false, 0)
      hbox.pack_start(search_btn, false, false, 0)
      hbox.pack_start(search_entry, true, true, 0)
      hbox.pack_start(stop_btn, false, false, 0)
      hbox.pack_start(prev_btn, false, false, 0)
      hbox.pack_start(next_btn, false, false, 0)

      toolbar_box = Gtk::HBox.new

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(toolbar_box, false, true, 0)

      #kind_btn = PandoraGtk::SafeToggleToolButton.new(Gtk::Stock::PROPERTIES)
      #kind_btn.tooltip_text = _('Change password')
      #kind_btn.safe_signal_clicked do |*args|
      #  #kind_btn.active?
      #end

      #Сделать горячие клавиши:
      #[CTRL + R], Ctrl + F5, Ctrl + Shift + R - Перезагрузить страницу
      #[CTRL + L] Выделить УРЛ страницы
      #[CTRL + N] Новое окно(не вкладка) - тоже что и Ctrl+T
      #[SHIFT + ESC] (Дипетчер задач) Возможно, список текущих соединений
      #[CTRL[+Alt] + 1] или [CTRL + 2] и т.д. - переключение между вкладками
      #Alt+ <- / -> - Вперед/Назад
      #Alt+Home - Домашняя страница (Профиль)
      #Открыть файл — Ctrl + O
      #Остановить — Esc
      #Сохранить страницу как — Ctrl + S
      #Найти далее — F3, Ctrl + G
      #Найти на этой странице — Ctrl + F
      #Отменить закрытие вкладки — Ctrl + Shift + T
      #Перейти к предыдущей вкладке — Ctrl + Page Up
      #Перейти к следующей вкладке — Ctrl + Page Down
      #Журнал посещений — Ctrl + H
      #Загрузки — Ctrl + J, Ctrl + Y
      #Закладки — Ctrl + B, Ctrl + I

      local_btn = SafeCheckButton.new(_('locally'), true)
      local_btn.safe_signal_clicked do |widget|
        search_btn.clicked if local_btn.active?
      end
      local_btn.safe_set_active(true)

      active_btn = SafeCheckButton.new(_('active only'), true)
      active_btn.safe_signal_clicked do |widget|
        search_btn.clicked if active_btn.active?
      end
      active_btn.safe_set_active(true)

      hunt_btn = SafeCheckButton.new(_('hunt!'), true)
      hunt_btn.safe_signal_clicked do |widget|
        search_btn.clicked if hunt_btn.active?
      end
      hunt_btn.safe_set_active(true)

      toolbar_box.pack_start(local_btn, false, false, 1)
      toolbar_box.pack_start(active_btn, false, false, 1)
      toolbar_box.pack_start(hunt_btn, false, false, 1)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)

      prev_btn.signal_connect('clicked') do |widget|
        PandoraGtk.set_readonly(next_btn, false)
        PandoraGtk.set_readonly(prev_btn, true)
        false
      end

      next_btn.signal_connect('clicked') do |widget|
        PandoraGtk.set_readonly(next_btn, true)
        PandoraGtk.set_readonly(prev_btn, false)
        false
      end

      search_btn.signal_connect('clicked') do |widget|
        request = search_entry.text
        search_entry.position = search_entry.position  # deselect
        if (request.size>0)
          kind = kind_entry.entry.text
          PandoraGtk.set_readonly(stop_btn, false)
          PandoraGtk.set_readonly(widget, true)
          #bases = kind
          #local_btn.active?  active_btn.active?  hunt_btn.active?
          if (kind=='Blob') and PandoraUtils.hex?(request)
            kind = PandoraModel::PK_BlobBody
            request = PandoraUtils.hex_to_bytes(request)
            p 'Search: Detect blob search  kind,sha1='+[kind,request].inspect
          end
          #reqs = $pool.add_search_request(request, kind, nil, nil, true)
          reqs = $pool.add_mass_record(PandoraNet::MK_Search, kind, request)
          show_all_reqs(reqs)
          PandoraGtk.set_readonly(stop_btn, true)
          PandoraGtk.set_readonly(widget, false)
          PandoraGtk.set_readonly(prev_btn, false)
          PandoraGtk.set_readonly(next_btn, true)
        end
        false
      end
      show_all_reqs

      stop_btn.signal_connect('clicked') do |widget|
        if @search_thread
          if @search_thread[:processing]
            @search_thread[:processing] = false
          else
            PandoraGtk.set_readonly(stop_btn, true)
            @search_thread.exit
            @search_thread = nil
          end
        else
          search_entry.select_region(0, search_entry.text.size)
        end
      end

      #search_btn.signal_connect('clicked') do |*args|
      #end

      # create tree view
      list_tree = Gtk::TreeView.new(@list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Request'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Kind'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Answer'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      PandoraGtk.hack_grab_focus(search_entry)
    end
  end

  # Profile panel
  # RU: Панель кабинета
  class ProfileScrollWin < Gtk::ScrolledWindow
    attr_accessor :person

    include PandoraGtk

    # Show profile window
    # RU: Показать окно профиля
    def initialize(a_person=nil)
      super(nil, nil)

      @person = a_person

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #self.add_with_viewport(vpaned)
    end
  end

  # List of session
  # RU: Список сеансов
  class SessionScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show session window
    # RU: Показать окно сессий
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      hunted_btn = SafeCheckButton.new(_('hunted'), true)
      hunted_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      hunted_btn.safe_set_active(true)

      hunters_btn = SafeCheckButton.new(_('hunters'), true)
      hunters_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      hunters_btn.safe_set_active(true)

      fishers_btn = SafeCheckButton.new(_('fishers'), true)
      fishers_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      fishers_btn.safe_set_active(true)

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(hunted_btn, false, true, 0)
      hbox.pack_start(hunters_btn, false, true, 0)
      hbox.pack_start(fishers_btn, false, true, 0)
      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(String, String, String, String, Integer, Integer, \
        Integer, Integer, Integer)
      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $pool.sessions.each do |session|
          hunter = session.hunter?
          if ((hunted_btn.active? and (not hunter)) \
          or (hunters_btn.active? and hunter) \
          or (fishers_btn.active? and session.active_hook))
            sess_iter = list_store.append
            sess_iter[0] = $pool.sessions.index(session).to_s
            sess_iter[1] = session.host_ip.to_s
            sess_iter[2] = session.port.to_s
            sess_iter[3] = PandoraUtils.bytes_to_hex(session.node_panhash)
            sess_iter[4] = session.conn_mode
            sess_iter[5] = session.conn_state
            sess_iter[6] = session.stage
            sess_iter[7] = session.send_state
          end

          #:host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state,
          #:stage, :dialog, :send_thread, :read_thread, :socket, :send_state,
          #:send_models, :recv_models, :sindex,
          #:read_queue, :send_queue, :confirm_queue, :params, :rcmd, :rcode, :rdata,
          #:scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, :r_encode, :media_send,
          #:node_id, :node_panhash, :entered_captcha, :captcha_sw, :fishes, :fishers
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Ip'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Port'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('conn_mode'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('conn_state'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('stage'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('send_state'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # Creating menu item from its description
  # RU: Создание пункта меню по его описанию
  def self.create_menu_item(mi, treeview=nil)
    menuitem = nil
    if mi[0] == '-'
      menuitem = Gtk::SeparatorMenuItem.new
    else
      text = _(mi[2])
      #if (mi[4] == :check)
      #  menuitem = Gtk::CheckMenuItem.new(mi[2])
      #  label = menuitem.children[0]
      #  #label.set_text(mi[2], true)
      opts = nil
      stock = mi[1]
      stock, opts = PandoraGtk.detect_icon_opts(stock) if stock
      if stock and opts and opts.index('m')
        stock = stock.to_sym if stock.is_a? String
        $window.register_stock(stock, nil, text)
        menuitem = Gtk::ImageMenuItem.new(stock)
        label = menuitem.children[0]
        label.set_text(text, true)
      else
        menuitem = Gtk::MenuItem.new(text)
      end
      if menuitem
        if (not treeview) and mi[3]
          key, mod = Gtk::Accelerator.parse(mi[3])
          menuitem.add_accelerator('activate', $window.accel_group, key, \
            mod, Gtk::ACCEL_VISIBLE) if key
        end
        command = mi[0]
        if command and (command.size>0) and (command[0]=='>')
          command = command[1..-1]
          command = nil if command==''
        end
        #menuitem.name = mi[0]
        PandoraUtils.set_obj_property(menuitem, 'command', command)
        PandoraGtk.set_bold_to_menuitem(menuitem) if opts and opts.index('b')
        menuitem.signal_connect('activate') { |widget| PandoraUI.do_menu_act(widget, treeview) }
      end
    end
    menuitem
  end

  # Radar list
  class RadarScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    MASS_KIND_ICONS = ['hunt', 'chat', 'request', 'fish']

    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      declared_btn = SafeCheckButton.new(_('declared'), true)
      declared_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      declared_btn.safe_set_active(true)

      lined_btn = SafeCheckButton.new(_('lined'), true)
      lined_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      lined_btn.safe_set_active(true)

      linked_btn = SafeCheckButton.new(_('linked'), true)
      linked_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      linked_btn.safe_set_active(true)

      failed_btn = SafeCheckButton.new(_('failed'), true)
      failed_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      #failed_btn.safe_set_active(true)

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(declared_btn, false, true, 0)
      hbox.pack_start(lined_btn, false, true, 0)
      hbox.pack_start(linked_btn, false, true, 0)
      hbox.pack_start(failed_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_NONE
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, String, String, String, String, \
        Integer, Integer, Integer, String, String)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        if $pool
          $pool.mass_records.queue.each do |mr|
            p '---Radar mass_rec='+mr[0..6].inspect
            anode = mr[PandoraNet::MR_SrcNode]
            if anode
              akey, abaseid, aperson = $pool.get_node_params(anode)
              p 'anode, akey, abaseid, aperson='+[anode, akey, abaseid, aperson].inspect
              sess_iter = list_store.append
              akind = mr[PandoraNet::MR_Kind]
              anick = nil
              anick = '['+mr[PandoraNet::MRP_Nick]+']' if (akind == PandoraNet::MK_Presence)
              if anick.nil? and aperson
                anick = PandoraCrypto.short_name_of_person(nil, aperson, 1)
              end
              anick = akind.to_s if anick.nil?
              trust = mr[PandoraNet::MR_Trust]
              trust = 0 if not (trust.is_a? Integer)
              sess_iter[0] = akind
              sess_iter[1] = anick
              sess_iter[2] = PandoraUtils.bytes_to_hex(aperson)
              sess_iter[3] = PandoraUtils.bytes_to_hex(akey)
              sess_iter[4] = PandoraUtils.bytes_to_hex(abaseid)
              sess_iter[5] = trust
              sess_iter[6] = mr[PandoraNet::MR_Depth]
              sess_iter[7] = 0 #distance
              sess_iter[8] = PandoraUtils.bytes_to_hex(anode)
              sess_iter[9] = PandoraUtils.time_to_str(mr[PandoraNet::MR_CrtTime])
            end
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      kind_pbs = []
      MASS_KIND_ICONS.each_with_index do |v, i|
        kind_pbs[i] = $window.get_icon_scale_buf(v, 'pan', 16)
      end

      kind_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
      kind_image.show_all
      renderer = Gtk::CellRendererPixbuf.new
      column = Gtk::TreeViewColumn.new('', renderer)
      column.widget = kind_image
      #column.set_sort_column_id(0)
      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        kind = nil
        kind = iter[0] if model.iter_is_valid?(iter) and iter and iter.path
        kind ||= 1
        if kind
          pixbuf = kind_pbs[kind-1]
          pixbuf = nil if pixbuf==false
          renderer.pixbuf = pixbuf
        end
      end
      column.fixed_width = 20
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Nick'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Person'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Key'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('BaseID'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Trust'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Depth'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Distance'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 9)
      column.set_sort_column_id(9)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        PandoraGtk.act_panobject(list_tree, 'Dialog')
      end

      menu = Gtk::Menu.new
      menu.append(PandoraGtk.create_menu_item(['Dialog', 'dialog:mb', _('Dialog'), '<control>D'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Relation', :relation, _('Relate'), '<control>R'], list_tree))
      menu.show_all

      list_tree.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      list_tree.signal_connect('button-press-event') do |widget, event|
        if (event.button == 3)
          menu.popup(nil, nil, event.button, event.time)
        end
      end

      list_tree.signal_connect('key-press-event') do |widget, event|
        res = true
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          PandoraGtk.act_panobject(list_tree, 'Dialog')
        elsif event.state.control_mask?
          if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
            PandoraGtk.act_panobject(list_tree, 'Dialog')
            #path, column = list_tree.cursor
            #if path
            #  iter = list_store.get_iter(path)
            #  person = nil
            #  person = iter[0] if iter
            #  person = PandoraUtils.hex_to_bytes(person)
            #  PandoraGtk.show_cabinet(person) if person
            #end
          else
            res = false
          end
        else
          res = false
        end
        res
      end

      list_sw.add(list_tree)
      #image = Gtk::Image.new(Gtk::Stock::GO_FORWARD, Gtk::IconSize::MENU)
      image = Gtk::Image.new(:radar, Gtk::IconSize::SMALL_TOOLBAR)
      image.set_padding(2, 0)
      #image1 = Gtk::Image.new(Gtk::Stock::ORIENTATION_PORTRAIT, Gtk::IconSize::MENU)
      #image1.set_padding(2, 2)
      #image2 = Gtk::Image.new(Gtk::Stock::NETWORK, Gtk::IconSize::MENU)
      #image2.set_padding(2, 2)
      image.show_all
      align = Gtk::Alignment.new(0.0, 0.5, 0.0, 0.0)
      btn_hbox = Gtk::HBox.new
      label = Gtk::Label.new(_('Radar'))
      btn_hbox.pack_start(image, false, false, 0)
      btn_hbox.pack_start(label, false, false, 2)

      close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
      btn_hbox.pack_start(close_image, false, false, 2)

      btn = Gtk::Button.new
      btn.relief = Gtk::RELIEF_NONE
      btn.focus_on_click = false
      btn.signal_connect('clicked') do |*args|
        PandoraGtk.show_radar_panel
      end
      btn.add(btn_hbox)
      align.add(btn)
      #lab_hbox.pack_start(image, false, false, 0)
      #lab_hbox.pack_start(image2, false, false, 0)
      #lab_hbox.pack_start(align, false, false, 0)
      #vbox.pack_start(lab_hbox, false, false, 0)
      vbox.pack_start(align, false, false, 0)
      vbox.pack_start(hbox, false, false, 0)
      vbox.pack_start(list_sw, true, true, 0)
      vbox.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # List of fishers
  # RU: Список рыбаков
  class FisherScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show fishers window
    # RU: Показать окно рыбаков
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, String, String, String, \
        String, String, String, String, String, String, String)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $pool.mass_records.each do |mr|
          if mr
            sess_iter = list_store.append
            sess_iter[0] = mr[PandoraNet::MR_Kind]
            sess_iter[1] = PandoraUtils.bytes_to_hex(mr[PandoraNet::MR_SrcNode])
            sess_iter[2] = PandoraUtils.time_to_str(mr[PandoraNet::MR_CrtTime])
            sess_iter[3] = mr[PandoraNet::MR_Trust].inspect
            sess_iter[4] = mr[PandoraNet::MR_Depth].inspect
            sess_iter[5] = mr[PandoraNet::MR_Param1].inspect
            sess_iter[6] = mr[PandoraNet::MR_Param2].inspect
            sess_iter[7] = mr[PandoraNet::MR_Param3].inspect
            sess_iter[8] = mr[PandoraNet::MR_KeepNodes].inspect
            sess_iter[9] = mr[PandoraNet::MR_ReqIndexes].inspect
            sess_iter[10] = mr[PandoraNet::MR_ReceiveState].inspect
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Kind'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('CrtTime'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Trust'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Depth'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Param1'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Param2'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Param3'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('KeepNodes'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Requests'), renderer, 'text' => 9)
      column.set_sort_column_id(9)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('ResState'), renderer, 'text' => 10)
      column.set_sort_column_id(10)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # Language phrase editor
  # RU: Редактор языковых фраз
  class PhraseEditorScrollWin < Gtk::ScrolledWindow
    #attr_accessor :update_btn

    include PandoraGtk

    # Show fishers window
    # RU: Показать окно рыбаков
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      english = ($lang == 'en')

      title = _('Load from file')
      load_btn = Gtk::ToolButton.new(Gtk::Stock::OPEN, title)
      load_btn.tooltip_text = title
      load_btn.label = title
      load_btn.sensitive = (not english)

      title = _('Save to file')
      save_btn = Gtk::ToolButton.new(Gtk::Stock::SAVE, title)
      save_btn.tooltip_text = title
      save_btn.label = title
      save_btn.sensitive = false

      file_label = Gtk::Label.new('')

      hbox.pack_start(load_btn, false, true, 0)
      hbox.pack_start(save_btn, false, true, 0)
      hbox.pack_start(file_label, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC) #Gtk::POLICY_NEVER

      list_store = Gtk::ListStore.new(Integer, String, String)

      lang_trans_ru = nil
      if $lang != 'ru'
        lang_trans_ru = Hash.new
        PandoraUtils.load_language('ru', nil, lang_trans_ru)
      end

      load_btn.signal_connect('clicked') do |*args|
        lang_trans = $lang_trans
        file_label.text = PandoraUtils.get_lang_file($lang) if not english
        list_store.clear
        i = 0
        if PandoraUtils.load_language($lang, nil, lang_trans)
          lang_trans.each do |key,val|
            list_iter = list_store.append
            i += 1
            list_iter[0] = i
            list_iter[1] = key
            list_iter[2] = val
          end
        end
        if lang_trans_ru
          lang_trans_ru.each do |key,val|
            val0 = lang_trans[key]
            if val0.nil? or (val0=='')
              list_iter = list_store.append
              i += 1
              list_iter[0] = i
              list_iter[1] = key
            end
          end
        end
        save_btn.sensitive = false
      end

      save_btn.signal_connect('clicked') do |*args|
        lang_trans = Hash.new
        list_store.each do |model, path, iter|
          key = iter[1]
          val = iter[2]
          lang_trans[key] = val
        end
        if lang_trans.size>0
          file_label.text = ''
          if PandoraUtils.save_as_language($lang, lang_trans)
            lang_file = PandoraUtils.get_lang_file($lang)
            file_label.text = lang_file
            PandoraUI.log_message(PandoraUI::LM_Info, _('Language file is saved')+\
              ' ['+lang_file+']')
            save_btn.sensitive = false
            if PandoraGtk.show_dialog(_('Application will be restarted')+ \
            ".\n"+_('Send your file')+': '+lang_file+"\n"+_('to email')+ \
            ": robux@mail.ru\n"+_('for including in the next release'))
              PandoraUtils.restart_app
            end
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      list_tree.rules_hint = true
      list_tree.selection.mode = Gtk::SELECTION_SINGLE
      #list_store.signal_connect('changed') do |widget, event|
      #list_tree.signal_connect('row_activated') do |tree_view, path, column|
      #  save_btn.sensitive = (not english)
      #  false
      #end

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('№'), renderer, 'text' => 0)
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      #column.fixed_width = 50
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('English'), renderer, 'text' => 1)
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      #column.fixed_width = 200
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      renderer.editable = true
      #renderer.editable_set = true
      renderer.single_paragraph_mode = false
      renderer.signal_connect('editing-started') do |ren, editable, path_str|
        if path_str and (path_str.size>0)
          iter = list_tree.model.get_iter(path_str)
          if iter
            value = iter[2]
            #iter.set_value(2, value)
            #ren.text = value
            #editable.truncate_multiline=(val)
            editable.text = value
          end
        end
        false
      end

      renderer.signal_connect('edited') do |ren, path_str, value|
        if path_str and (path_str.size>0)
          iter = list_tree.model.get_iter(path_str)
          if iter
            iter.set_value(2, value)
            save_btn.sensitive = (not english)
          end
        end
        false
      end
      column = Gtk::TreeViewColumn.new(_('Current')+'('+$lang+')', renderer, \
        'text' => 2)
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      if english
        file_label.text = 'English language is embedded to the code'
      else
        load_btn.clicked
      end
      list_tree.grab_focus
    end
  end

  # Set readonly mode to widget
  # RU: Установить виджету режим только для чтения
  def self.set_readonly(widget, value=true, set_sensitive=true)
    value = (not value)
    widget.editable = value if widget.class.method_defined?('editable?')
    widget.sensitive = value if set_sensitive and (widget.class.method_defined?('sensitive?'))
    #widget.can_focus = value
    #widget.has_focus = value if widget.class.method_defined? 'has_focus?'
    #widget.can_focus = (not value) if widget.class.method_defined? 'can_focus?'
  end

  # Correct bug with dissapear Enter press event
  # RU: Исправляет баг с исчезновением нажатия Enter
  def self.hack_enter_bug(enterbox)
    # because of bug - doesnt work Enter at 'key-press-event'
    enterbox.signal_connect('key-release-event') do |widget, event|
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      and (not event.state.control_mask?) and (not event.state.shift_mask?) and (not event.state.mod1_mask?)
        widget.signal_emit('key-press-event', event)
        false
      end
    end
  end

  # Correct bug with non working focus set
  # RU: Исправляет баг с неработающей постановкой фокуса
  def self.hack_grab_focus(widget_to_focus)
    widget_to_focus.grab_focus
    Thread.new do
      sleep(0.2)
      if (not widget_to_focus.destroyed?)
        widget_to_focus.grab_focus
      end
    end
  end

  # Set statusbat text
  # RU: Задает текст статусной строки
  def self.set_statusbar_text(statusbar, text)
    statusbar.pop(0)
    statusbar.push(0, text)
  end

  def self.find_tool_btn(toolbar, title)
    res = nil
    if toolbar
      lang_title = _(title)
      i = 0
      while (i<toolbar.children.size) and (not res)
        ch = toolbar.children[i]
        if (((ch.is_a? Gtk::ToolButton) or (ch.is_a? Gtk::ToggleToolButton)) \
        and ((ch.label == title) or (ch.label == lang_title)))
          res = ch
          break
        end
        i += 1
      end
    end
    res
  end

  # Get icon associated with panobject
  # RU: Взять иконку ассоциированную с панобъектом
  def self.get_panobject_icon(panobj)
    panobj_icon = nil
    if panobj
      ider = panobj
      ider = panobj.ider if (not panobj.is_a? String)
      image = nil
      image = $window.get_panobject_image(ider, Gtk::IconSize::DIALOG) if $window
      if image
        style = Gtk::Widget.default_style
        panobj_icon = image.icon_set.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
          Gtk::STATE_NORMAL, Gtk::IconSize::DIALOG)
      end
    end
    panobj_icon
  end

  # Do action with selected record
  # RU: Выполнить действие над выделенной записью
  def self.act_panobject(tree_view, action)

    # Set delete dialog wigets (checkboxes and text)
    # RU: Задать виджеты диалога удаления (чекбоксы и текст)
    def self.set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
      text = nil
      if arch_cb and arch_cb.active?
        if keep_cb.active?
          text = _('Stay record in archive with "Keep" flag')
        else
          text = _('Move record to archive. Soon will be deleted by garbager')
        end
      elsif ignore_cb.active?
        text = _('Delete record physically')+'. '+\
          _('Also create Relation "Ignore"')
      else
        text = _('Delete record physically')
      end
      dialog.secondary_text = text if text
    end

    path = nil
    if tree_view.destroyed?
      new_act = false
    else
      path, column = tree_view.cursor
      new_act = (action == 'Create')
    end
    p 'path='+path.inspect
    if path or new_act
      panobject = nil
      if (tree_view.is_a? SubjTreeView)
        panobject = tree_view.panobject
      end
      #p 'panobject='+panobject.inspect
      store = tree_view.model
      iter = nil
      sel = nil
      id = nil
      panhash0 = nil
      panstate = 0
      created0 = nil
      creator0 = nil
      if path and (not new_act)
        iter = store.get_iter(path)
        if panobject  # SubjTreeView
          id = iter[0]
          sel = panobject.select('id='+id.to_s, true)
          if sel and (sel.size>0)
            panhash0 = panobject.namesvalues['panhash']
            panstate = panobject.namesvalues['panstate']
            panstate ||= 0
            if (panobject.is_a? PandoraModel::Created)
              created0 = panobject.namesvalues['created']
              creator0 = panobject.namesvalues['creator']
            end
          end
          if (action=='Dialog') and (not PandoraUtils.panhash_nil?(creator0))
            panhash0 = creator0
            id = nil
            sel = nil
            panstate = 0
            creator0 = nil
            created0 = nil
            panobject = nil
            panobject = PandoraUtils.get_model('Person')
            sel = panobject.select({:panhash=>panhash0}, true)
            if sel and (sel.size>0)
              panhash0 = panobject.namesvalues['panhash']
              panstate = panobject.namesvalues['panstate']
              panstate ||= 0
              if (panobject.is_a? PandoraModel::Created)
                created0 = panobject.namesvalues['created']
                creator0 = panobject.namesvalues['creator']
              end
            end
          end
        else  # RadarScrollWin
          panhash0 = PandoraUtils.hex_to_bytes(iter[2])
        end
      end

      if action=='Delete'
        if id and sel[0]
          ctrl_prsd, shift_prsd, alt_prsd = PandoraGtk.is_ctrl_shift_alt?
          keep_flag = (panstate and (panstate & PandoraModel::PSF_Support)>0)
          arch_flag = (panstate and (panstate & PandoraModel::PSF_Archive)>0)
          in_arch = tree_view.page_sw.arch_btn.active?
          ignore_mode = ((ctrl_prsd and shift_prsd) or (arch_flag and (not ctrl_prsd)))
          arch_mode = ((not ignore_mode) and (not ctrl_prsd))
          keep_mode = (arch_mode and (keep_flag or shift_prsd))
          delete_mode = PandoraUtils.get_param('delete_mode')
          do_del = true
          if arch_flag or ctrl_prsd or shift_prsd or in_arch \
          or (delete_mode==0)
            in_arch = (in_arch and arch_flag)
            info = panobject.record_info(80, nil, ': ')
            #panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
            dialog = PandoraGtk::GoodMessageDialog.new(info, 'Deletion', \
              Gtk::MessageDialog::QUESTION, get_panobject_icon(panobject))
            arch_cb = nil
            keep_cb = nil
            ignore_cb = nil
            dialog.signal_connect('key-press-event') do |widget, event|
              if (event.keyval==Gdk::Keyval::GDK_Delete)
                widget.response(Gtk::Dialog::RESPONSE_CANCEL)
              elsif [Gdk::Keyval::GDK_a, Gdk::Keyval::GDK_A, 1731, 1763].include?(\
              event.keyval) #a, A, ф, Ф
                arch_cb.active = (not arch_cb.active?) if arch_cb
              elsif [Gdk::Keyval::GDK_k, Gdk::Keyval::GDK_K, 1731, 1763].include?(\
              event.keyval) #k, K, л, Л
                keep_cb.active = (not keep_cb.active?) if keep_cb
              elsif [Gdk::Keyval::GDK_i, Gdk::Keyval::GDK_I, 1731, 1763].include?(\
              event.keyval) #i, I, ш, Ш
                ignore_cb.active = (not ignore_cb.active?) if ignore_cb
              else
                p event.keyval
              end
              false
            end
            # Set dialog size for prevent jumping
            hbox = dialog.vbox.children[0]
            hbox.set_size_request(500, 100) if hbox.is_a? Gtk::HBox
            # CheckBox adding
            if not in_arch
              arch_cb = SafeCheckButton.new(:arch)
              PandoraGtk.set_button_text(arch_cb, _('Move to archive'))
              arch_cb.active = arch_mode
              arch_cb.safe_signal_clicked do |widget|
                if in_arch
                  widget.safe_set_active(false)
                elsif not PandoraGtk.is_ctrl_shift_alt?(true, true)
                  widget.safe_set_active(true)
                end
                if widget.active?
                  ignore_cb.safe_set_active(false)
                else
                  keep_cb.safe_set_active(false)
                end
                set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
                false
              end
              dialog.vbox.pack_start(arch_cb, false, true, 0)

              $window.register_stock(:keep)
              keep_cb = SafeCheckButton.new(:keep)
              PandoraGtk.set_button_text(keep_cb, _('Keep in archive'))
              keep_cb.active = keep_mode
              keep_cb.safe_signal_clicked do |widget|
                widget.safe_set_active(false) if in_arch
                if widget.active?
                  arch_cb.safe_set_active(true) if not in_arch
                  ignore_cb.safe_set_active(false)
                end
                set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
                false
              end
              dialog.vbox.pack_start(keep_cb, false, true, 0)
            end

            $window.register_stock(:ignore)
            ignore_cb = SafeCheckButton.new(:ignore)
            ignore_cb.active = ignore_mode
            PandoraGtk.set_button_text(ignore_cb, _('Destroy and ignore'))
            ignore_cb.safe_signal_clicked do |widget|
              if widget.active?
                arch_cb.safe_set_active(false) if arch_cb
                keep_cb.safe_set_active(false) if keep_cb
              elsif not in_arch
                arch_cb.safe_set_active(true) if arch_cb
              end
              set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
              false
            end
            dialog.vbox.pack_start(ignore_cb, false, true, 0)

            set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
            dialog.vbox.show_all

            do_del = dialog.run_and_do do
              arch_mode = (arch_cb and arch_cb.active?)
              keep_mode = (keep_cb and keep_cb.active?)
              ignore_mode = ignore_cb.active?
            end
          end
          if do_del
            rm_from_tab = false
            if arch_mode
              p '[arch_mode, keep_mode]='+[arch_mode, keep_mode].inspect
              panstate = (panstate | PandoraModel::PSF_Archive)
              if keep_mode
                panstate = (panstate | PandoraModel::PSF_Support)
              else
                panstate = (panstate & (~PandoraModel::PSF_Support))
              end
              res = panobject.update({:panstate=>panstate}, nil, 'id='+id.to_s)
              if (not tree_view.page_sw.arch_btn.active?)
                rm_from_tab = true
              end
            else
              res = panobject.update(nil, nil, 'id='+id.to_s)
              PandoraModel.remove_all_relations(panhash0, true, true)
              PandoraModel.act_relation(nil, panhash0, RK_Ignore, :create, \
                true, true) if ignore_mode
              rm_from_tab = true
            end
            if rm_from_tab
              if (panobject.kind==PK_Relation)
                PandoraModel.del_image_from_cache(panobject.namesvalues['first'])
                PandoraModel.del_image_from_cache(panobject.namesvalues['second'])
              end
              tree_view.sel.delete_if {|row| row[0]==id }
              store.remove(iter)
              #iter.next!
              pt = path.indices[0]
              pt = tree_view.sel.size-1 if (pt > tree_view.sel.size-1)
              tree_view.set_cursor(Gtk::TreePath.new(pt), column, false) if (pt >= 0)
            end
          end
        end
      elsif panobject or (action=='Dialog') or (action=='Opinion') \
      or (action=='Chat') or (action=='Cabinet')
        # Edit or Insert

        edit = ((not new_act) and (action != 'Copy'))

        row = nil
        formfields = nil
        if panobject
          #panobject.namesvalues = nil if new_act
          row = sel[0] if sel
          formfields = panobject.get_fields_as_view(row, edit, panhash0)
        end

        if panobject or panhash0
          panhash0 ||= panobject
          page = PandoraUI::CPI_Property
          akind = PandoraModel.detect_panobject_kind(panhash0)
          if (akind==PandoraModel::PK_Blob) and (action=='Edit')
            page = PandoraUI::CPI_Editor
          else
            case action
              when 'Cabinet'
                page = PandoraUI::CPI_Profile
              when 'Chat'
                page = PandoraUI::CPI_Chat
              when 'Dialog'
                page = PandoraUI::CPI_Dialog
              when 'Opinion'
                page = PandoraUI::CPI_Opinions
            end
          end
          show_cabinet(panhash0, nil, nil, nil, nil, page, formfields, id, edit, tree_view)
        else
          dialog = FieldsDialog.new(panobject, tree_view, formfields, panhash0, id, \
            edit, panobject.sname)
          dialog.icon = get_panobject_icon(panobject)

          #!!!dialog.lang_entry.entry.text = PandoraModel.lang_to_text(lang) if lang

          if edit
            count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
            #!!!dialog.rate_btn.label = _('Rate')+': '+rate.round(2).to_s if rate.is_a? Float
            trust = nil
            #p PandoraUtils.bytes_to_hex(panhash0)
            #p 'trust or num'
            trust_or_num = PandoraCrypto.trust_to_panobj(panhash0)
            trust = trust_or_num if (trust_or_num.is_a? Float)
            #!!!dialog.vouch_btn.active = (trust_or_num != nil)
            #!!!dialog.vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
            #!!!dialog.trust_scale.sensitive = (trust != nil)
            #dialog.trust_scale.signal_emit('value-changed')
            trust ||= 0.0
            #!!!dialog.trust_scale.value = trust
            #dialog.rate_label.text = rate.to_s

            #!!!dialog.keep_btn.active = (PandoraModel::PSF_Support & panstate)>0

            #!!pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
            #!!!dialog.public_btn.active = pub_level
            #!!!dialog.public_btn.inconsistent = (pub_level == nil)
            #!!!dialog.public_scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
            #!!!dialog.public_scale.sensitive = pub_level

            #!!follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
            #!!!dialog.follow_btn.active = follow
            #!!!dialog.follow_btn.inconsistent = (follow == nil)

            #dialog.lang_entry.active_text = lang.to_s
            #trust_lab = dialog.trust_btn.children[0]
            #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
          else  #new or copy
            key = PandoraCrypto.current_key(false, false)
            key_inited = (key and key[PandoraCrypto::KV_Obj])

            if formfields
              ind = formfields.index { |field| field[PandoraUtils::FI_Id] == 'panstate' }
              if ind
                fld = formfields[ind]
                panstate = fld[PandoraUtils::FI_Value]
                panstate ||= 0
                fld[PandoraUtils::FI_Value] = (panstate | PandoraModel::PSF_Support)
              end
            end
            #!!!dialog.keep_btn.active = true
            #!!!dialog.follow_btn.active = key_inited
            #!!!dialog.vouch_btn.active = key_inited
            #!!!dialog.trust_scale.sensitive = key_inited
            #!!!if not key_inited
            #  dialog.follow_btn.inconsistent = true
            #  dialog.vouch_btn.inconsistent = true
            #  dialog.public_btn.inconsistent = true
            #end
            #!!!dialog.public_scale.sensitive = false
          end

          st_text = panobject.panhash_formula
          #st_text = st_text + ' [#'+panobject.calc_panhash(row, lang, \
          #  true, true)+']' if sel and sel.size>0
          #!!!PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

          #if panobject.is_a? PandoraModel::Key
          #  mi = Gtk::MenuItem.new("Действия")
          #  menu = Gtk::MenuBar.new
          #  menu.append(mi)

          #  menu2 = Gtk::Menu.new
          #  menuitem = Gtk::MenuItem.new("Генерировать")
          #  menu2.append(menuitem)
          #  mi.submenu = menu2
          #  #p dialog.action_area
          #  dialog.hbox.pack_end(menu, false, false)
          #  #dialog.action_area.add(menu)
          #end

          titadd = nil
          if not edit
          #  titadd = _('edit')
          #else
            titadd = _('new')
          end
          dialog.title += ' ('+titadd+')' if titadd and (titadd != '')

          dialog.run2 do
            dialog.property_box.save_form_fields_with_flags_to_database(created0, row)
          end
        end
      end
    elsif action=='Dialog'
      PandoraGtk.show_panobject_list(PandoraModel::Person)
    end
  end

  # Grid for panobjects
  # RU: Таблица для объектов Пандоры
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject, :sel, :auto_create, :param_view_col, \
      :page_sw
    def get_notebook
      res = $window.notebook
      if @page_sw and (not @page_sw.destroyed?) \
      and @page_sw.parent and @page_sw.parent.is_a?(Gtk::Notebook)
        res = @page_sw.parent
      end
      res
    end
  end

  # Column for SubjTreeView
  # RU: Колонка для SubjTreeView
  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
  end

  # ScrolledWindow for panobjects
  # RU: ScrolledWindow для объектов Пандоры
  class PanobjScrolledWindow < Gtk::ScrolledWindow
    attr_accessor :update_btn, :auto_btn, :arch_btn, :treeview, :filter_box

    def initialize
      super(nil, nil)
    end

    def update_treeview
      if treeview and (not treeview.destroyed?)
        panobject = treeview.panobject
        store = treeview.model
        Gdk::Threads.synchronize do
          Gdk::Display.default.sync
          $window.mutex.synchronize do
            path, column = treeview.cursor
            id0 = nil
            if path
              iter = store.get_iter(path)
              id0 = iter[0]
            end
            #store.clear
            panobject.class.modified = false if panobject.class.modified
            filter = nil
            filter = filter_box.compose_filter
            if (not arch_btn.active?)
              del_bit = PandoraModel::PSF_Archive
              del_fil = 'IFNULL(panstate,0)&'+del_bit.to_s+'=0'
              if filter.nil?
                filter = del_fil
              else
                filter[0] << ' AND '+del_fil
              end
            end
            p 'select filter[sql,values]='+filter.inspect
            sel = panobject.select(filter, false, nil, panobject.sort)
            if sel
              treeview.sel = sel
              treeview.param_view_col = nil
              if ((panobject.kind==PandoraModel::PK_Parameter) \
              or (panobject.kind==PandoraModel::PK_Message)) and sel[0]
                treeview.param_view_col = sel[0].size
              end
              iter0 = nil
              sel.each_with_index do |row,i|
                #iter = store.append
                iter = store.get_iter(Gtk::TreePath.new(i))
                iter ||= store.append
                #store.set_value(iter, column, value)
                id = row[0].to_i
                iter[0] = id
                iter0 = iter if id0 and id and (id == id0)
                if treeview.param_view_col
                  view = nil
                  if (panobject.kind==PandoraModel::PK_Parameter)
                    type = panobject.field_val('type', row)
                    setting = panobject.field_val('setting', row)
                    ps = PandoraUtils.decode_param_setting(setting)
                    view = ps['view']
                    view ||= PandoraUtils.pantype_to_view(type)
                  else
                    panstate = panobject.field_val('panstate', row)
                    if (panstate.is_a? Integer) and ((panstate & PandoraModel::PSF_Crypted)>0)
                      view = 'hex'
                    end
                  end
                  row[treeview.param_view_col] = view
                end
              end
              i = sel.size
              iter = store.get_iter(Gtk::TreePath.new(i))
              while iter
                store.remove(iter)
                iter = store.get_iter(Gtk::TreePath.new(i))
              end
              if treeview.sel.size>0
                if (not path) or (not store.get_iter(path)) \
                or (not store.iter_is_valid?(store.get_iter(path)))
                  path = iter0.path if iter0
                  path ||= Gtk::TreePath.new(treeview.sel.size-1)
                end
                treeview.set_cursor(path, nil, false)
                treeview.scroll_to_cell(path, nil, false, 0.0, 0.0)
              end
            end
          end
          p 'treeview is updated: '+panobject.ider
          treeview.grab_focus
        end
      end
    end

  end

  # Filter box: field, operation and value
  # RU: Группа фильтра: поле, операция и значение
  class FilterHBox < Gtk::HBox
    attr_accessor :filters, :field_com, :oper_com, :val_entry, :logic_com, \
      :del_btn, :add_btn, :page_sw

    # Remove itself
    # RU: Удалить себя
    def delete
      @add_btn = nil
      if @filters.size>1
        parent.remove(self)
        filters.delete(self)
        last = filters[filters.size-1]
        #p [last, last.add_btn, filters.size-1]
        last.add_btn_to
      else
        field_com.entry.text = ''
        while children.size>1
          child = children[children.size-1]
          remove(child)
          child.destroy
        end
        @add_btn.destroy if @add_btn
        @add_btn = nil
        @oper_com = nil
      end
      first = filters[0]
      page_sw.filter_box = first
      if first and first.logic_com
        first.remove(first.logic_com)
        first.logic_com = nil
      end
      page_sw.update_treeview
    end

    def add_btn_to
      #p '---add_btn_to [add_btn, @add_btn]='+[add_btn, @add_btn].inspect
      if add_btn.nil? and (children.size>2)
        @add_btn = Gtk::ToolButton.new(Gtk::Stock::ADD, _('Add'))
        add_btn.tooltip_text = _('Add a new filter')
        add_btn.signal_connect('clicked') do |*args|
          FilterHBox.new(filters, parent, page_sw)
        end
        pack_start(add_btn, false, true, 0)
        add_btn.show_all
      end
    end

    # Compose filter with sql-query and raw values
    # RU: Составить фильтр с sql-запросом и сырыми значениями
    def compose_filter
      sql = nil
      values = nil
      @filters.each do |fb|
        fld = fb.field_com.entry.text
        if fb.oper_com and fb.val_entry
          oper = fb.oper_com.entry.text
          if fld and oper
            logic = nil
            logic = fb.logic_com.entry.text if fb.logic_com
            val = fb.val_entry.text
            #p '====[i, logic, fld, oper, val, sql]='+[i, logic, fld, oper, val, sql].inspect
            panobject = page_sw.treeview.panobject
            tab_flds = panobject.tab_fields
            tab_ind = tab_flds.index{ |tf| tf[0] == fld }
            view = nil
            type = nil
            if tab_ind
              fdesc = panobject.tab_fields[tab_ind][PandoraUtils::TI_Desc]
              if fdesc
                view = fdesc[PandoraUtils::FI_View]
                type = fdesc[PandoraUtils::FI_Type]
                val = PandoraUtils.view_to_val(val, type, view)
              elsif fld=='id'
                val = val.to_i
              end
            elsif fld=='lang'
              tab_ind = true
              fld = 'panhash'
              val = panobject.kind.chr + (val.to_i).chr + '*'
            end
            if tab_ind
              #p '[val, type, view]='+[val, type, view].inspect
              if view.nil? and val.is_a?(String) and (val.index('*') or val.index('?'))
                PandoraUtils.correct_aster_and_quest!(val)
                if (oper=='=')
                  oper = ' LIKE '
                else
                  fb.oper_com.entry.text = '<>'
                  oper = ' NOT LIKE '
                end
              elsif (view.nil? and val.nil?) or (val.is_a?(String) and val.size==0)
                fld = 'IFNULL('+fld+",'')"
                oper << "''"
                val = nil
              elsif val.nil? and (oper=='=')
                oper = ' IS NULL'
                val = nil
              end
              values ||= Array.new
              if sql.nil?
                sql = ''
              else
                sql << ' '
                logic = 'AND' if (logic.nil? or (logic != 'OR'))
              end
              sql << (logic+' ') if (logic and (logic.size>0))
              #p "--[i, fld, oper, sql]="+[i, fld, oper, sql].inspect
              sql << (fld + oper)
              if val
                sql << '?'
                values << val
              end
            end
          end
        end
      end
      #p "++++++ sql="+sql.inspect
      values.insert(0, sql) if (values and sql)
      values
    end

    def set_filter_by_str(logic, afilter)
      res = nil
      p 'set_filter_by_str(logic, afilter)='+[logic, afilter].inspect
      len = 1
      i = afilter.index('=')
      i ||= afilter.index('>')
      i ||= afilter.index('<')
      if not i
        i = afilter.index('<>')
        len = 2
      end
      if i
        fname = afilter[0, i]
        oper = afilter[i, len]
        val = afilter[i+len..-1]
        field_com.entry.text = fname
        oper_com.entry.text = oper
        val_entry.text = val
        logic_com.entry.text = logic if logic and logic_com
        res = true
      end
      res
    end

    def set_fix_filter(fix_filter, logic=nil)
      #p '== set_fix_filter  fix_filter='+fix_filter
      if fix_filter
        i = fix_filter.index(' AND ')
        j = fix_filter.index(' OR ')
        i = j if (i.nil? or ((not j.nil?) and (j>i)))
        if i
          afilter = fix_filter[0, i]
          fix_filter = fix_filter[i+1..-1]
        else
          afilter = fix_filter
          fix_filter = nil
        end
        setted = set_filter_by_str(logic, afilter)
        #p '--set_fix_filter [logic, afilter, fix_filter]='+[logic, afilter, fix_filter].inspect
        if fix_filter
          i = fix_filter.index(' ')
          logic = nil
          if i and i<4
            logic = fix_filter[0, i]
            fix_filter = fix_filter[i+1..-1]
          end
          if setted
            add_btn_to
            FilterHBox.new(filters, parent, page_sw)
          end
          next_fb = @filters[@filters.size-1]
          next_fb.set_fix_filter(fix_filter, logic)
        end
      end
    end

    # Create new instance
    # RU: Создать новый экземпляр
    def initialize(a_filters, hbox, a_page_sw)

      def no_filter_frase
        res = '<'+_('filter')+'>'
      end

      super()
      @page_sw = a_page_sw
      @filters = a_filters
      filter_box = self
      panobject = page_sw.treeview.panobject
      tab_flds = panobject.tab_fields
      def_flds = panobject.def_fields
      #def_flds.each do |df|
      #id = df[PandoraUtils::FI_Id]
      #tab_ind = tab_flds.index{ |tf| tf[0] == id }
      #if tab_ind
      #  renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

      #  title = df[PandoraUtils::FI_VFName]
      if @filters.size>0
        @logic_com = Gtk::Combo.new
        logic_com.set_popdown_strings(['AND', 'OR'])
        logic_com.entry.text = 'AND'
        logic_com.set_size_request(64, -1)
        filter_box.pack_start(logic_com, false, true, 0)
        prev = @filters[@filters.size-1]
        if prev and prev.add_btn
          prev.remove(prev.add_btn)
          prev.add_btn = nil
        end
      end

      fields = Array.new
      fields << no_filter_frase
      fields << 'lang'
      fields.concat(tab_flds.collect{|tf| tf[0]})
      @field_com = Gtk::Combo.new
      field_com.set_popdown_strings(fields)
      field_com.set_size_request(110, -1)

      field_com.entry.signal_connect('changed') do |entry|
        if filter_box.children.size>2
          if (entry.text == no_filter_frase) or (entry.text == '')
            delete
          end
          false
        elsif (entry.text != no_filter_frase) and (entry.text != '')
          @oper_com = Gtk::Combo.new
          oper_com.set_popdown_strings(['=','<>','>','<'])
          oper_com.set_size_request(56, -1)
          oper_com.entry.signal_connect('activate') do |*args|
            @val_entry.grab_focus
          end
          filter_box.pack_start(oper_com, false, true, 0)

          @del_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, _('Delete'))
          del_btn.tooltip_text = _('Delete this filter')
          del_btn.signal_connect('clicked') do |*args|
            delete
          end
          filter_box.pack_start(del_btn, false, true, 0)

          @val_entry = Gtk::Entry.new
          val_entry.set_size_request(120, -1)
          filter_box.pack_start(val_entry, false, true, 0)
          val_entry.signal_connect('focus-out-event') do |widget, event|
            page_sw.update_treeview
            false
          end

          add_btn_to
          filter_box.show_all
        end
      end
      filter_box.pack_start(field_com, false, true, 0)

      filter_box.show_all
      hbox.pack_start(filter_box, false, true, 0)

      @filters << filter_box

      p '@filters='+@filters.inspect

      filter_box
    end
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, page_sw=nil, \
  auto_create=false, fix_filter=nil)
    notebook = $window.notebook
    single = (page_sw == nil)
    if single
      notebook.children.each do |child|
        if (child.is_a? PanobjScrolledWindow) and (child.name==panobject_class.ider)
          notebook.page = notebook.children.index(child)
          #child.update_if_need
          return nil
        end
      end
    end
    panobject = panobject_class.new
    store = Gtk::ListStore.new(Integer)
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject

    tab_flds = panobject.tab_fields
    def_flds = panobject.def_fields

    its_blob = (panobject.is_a? PandoraModel::Blob)
    if its_blob or (panobject.is_a? PandoraModel::Person)
      renderer = Gtk::CellRendererPixbuf.new
      #renderer.pixbuf = $window.get_icon_buf('smile')
      column = SubjTreeViewColumn.new(_('View'), renderer)
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      column.fixed_width = 45
      column.tab_ind = tab_flds.index{ |tf| tf[0] == 'panhash' }
      #p '//////////column.tab_ind='+column.tab_ind.inspect
      treeview.append_column(column)

      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        row = nil
        begin
          if model.iter_is_valid?(iter) and iter and iter.path
            row = tvc.tree_view.sel[iter.path.indices[0]]
          end
        rescue
          p 'rescue'
        end
        val = nil
        if row
          col = tvc.tab_ind
          val = row[col] if col
        end
        if val
          #p '[col, val]='+[col, val].inspect
          pixbuf = PandoraModel.get_avatar_icon(val, tvc.tree_view, its_blob, 45)
          pixbuf = nil if pixbuf==false
          renderer.pixbuf = pixbuf
        end
      end

    end

    def_flds.each do |df|
      id = df[PandoraUtils::FI_Id]
      tab_ind = tab_flds.index{ |tf| tf[0] == id }
      if tab_ind
        renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

        title = df[PandoraUtils::FI_VFName]
        title ||= v
        column = SubjTreeViewColumn.new(title, renderer )  #, {:text => i}

        #p v
        #p ind = panobject.def_fields.index_of {|f| f[0]==v }
        #p fld = panobject.def_fields[ind]

        column.tab_ind = tab_ind
        #column.sort_column_id = ind
        #p column.ind = i
        #p column.fld = fld
        #panhash_col = i if (v=='panhash')
        column.resizable = true
        column.reorderable = true
        column.clickable = true
        treeview.append_column(column)
        column.signal_connect('clicked') do |col|
          p 'sort clicked'
        end
        column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
          row = nil
          begin
            if model.iter_is_valid?(iter) and iter and iter.path
              row = tvc.tree_view.sel[iter.path.indices[0]]
            end
          rescue
          end
          color = 'black'
          val = nil
          if row
            col = tvc.tab_ind
            val = row[col]
          end
          if val
            panobject = tvc.tree_view.panobject
            fdesc = panobject.tab_fields[col][TI_Desc]
            if fdesc.is_a? Array
              view = nil
              if tvc.tree_view.param_view_col and ((fdesc[PandoraUtils::FI_Id]=='value') or (fdesc[PandoraUtils::FI_Id]=='text'))
                view = row[tvc.tree_view.param_view_col] if row
              else
                view = fdesc[PandoraUtils::FI_View]
              end
              val, color = PandoraUtils.val_to_view(val, nil, view, false)
            else
              val = val.to_s
            end
            val = val[0,46]
          end
          renderer.foreground = color
          val ||= ''
          renderer.text = val
        end
      else
        p 'Field ['+id.inspect+'] is not found in table ['+panobject.ider+']'
      end
    end

    treeview.signal_connect('row_activated') do |tree_view, path, column|
      dialog = page_sw.parent.parent.parent
      if dialog and dialog.is_a?(AdvancedDialog) and dialog.okbutton
        dialog.okbutton.activate
      else
        if (panobject.is_a? PandoraModel::Person)
          act_panobject(tree_view, 'Dialog')
        else
          act_panobject(tree_view, 'Edit')
        end
      end
    end

    list_sw = Gtk::ScrolledWindow.new(nil, nil)
    list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
    list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    list_sw.border_width = 0
    list_sw.add(treeview)

    pbox = Gtk::VBox.new

    page_sw ||= PanobjScrolledWindow.new
    page_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    page_sw.border_width = 0
    page_sw.add_with_viewport(pbox)
    page_sw.children[0].shadow_type = Gtk::SHADOW_NONE # Gtk::SHADOW_ETCHED_IN

    page_sw.name = panobject.ider
    page_sw.treeview = treeview
    treeview.page_sw = page_sw

    hbox = Gtk::HBox.new

    PandoraGtk.add_tool_btn(hbox, Gtk::Stock::ADD, 'Create') do |widget|  #:NEW
      PandoraUI.do_menu_act('Create', treeview)
    end
    chat_stock = :chat
    chat_item = 'Chat'
    if (panobject.is_a? PandoraModel::Person)
      chat_stock = :dialog
      chat_item = 'Dialog'
    end
    if single
      PandoraGtk.add_tool_btn(hbox, chat_stock, chat_item) do |widget|
        PandoraUI.do_menu_act(chat_item, treeview)
      end
      PandoraGtk.add_tool_btn(hbox, :opinion, 'Opinions') do |widget|
        PandoraUI.do_menu_act('Opinion', treeview)
      end
    end
    page_sw.update_btn = PandoraGtk.add_tool_btn(hbox, Gtk::Stock::REFRESH, 'Update') do |widget|
      page_sw.update_treeview
    end
    page_sw.auto_btn = nil
    if single
      page_sw.auto_btn = PandoraGtk.add_tool_btn(hbox, :update, 'Auto update', true) do |widget|
        update_treeview_if_need(page_sw)
      end
    end
    page_sw.arch_btn = PandoraGtk.add_tool_btn(hbox, :arch, 'Show archived', false) do |widget|
      page_sw.update_btn.clicked
    end

    filters = Array.new
    page_sw.filter_box = FilterHBox.new(filters, hbox, page_sw)
    page_sw.filter_box.set_fix_filter(fix_filter) if fix_filter

    pbox.pack_start(hbox, false, true, 0)
    pbox.pack_start(list_sw, true, true, 0)

    page_sw.update_btn.clicked

    if auto_create and treeview.sel and (treeview.sel.size==0)
      treeview.auto_create = true
      treeview.signal_connect('map') do |widget, event|
        if treeview.auto_create
          act_panobject(treeview, 'Create')
          treeview.auto_create = false
        end
      end
      auto_create = false
    end

    edit_opt = ':m'
    dlg_opt = ':m'
    if single
      if (panobject.is_a? PandoraModel::Person)
        dlg_opt << 'b'
      else
        edit_opt << 'b'
      end
      image = $window.get_panobject_image(panobject_class.ider, Gtk::IconSize::SMALL_TOOLBAR)
      #p 'single: widget='+widget.inspect
      #if widget.is_a? Gtk::ImageMenuItem
      #  animage = widget.image
      #elsif widget.is_a? Gtk::ToolButton
      #  animage = widget.icon_widget
      #else
      #  animage = nil
      #end
      #image = nil
      #if animage
      #  if animage.stock
      #    image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
      #    image.set_padding(2, 0)
      #  else
      #    image = Gtk::Image.new(animage.icon_set, Gtk::IconSize::MENU)
      #    image.set_padding(2, 0)
      #  end
      #end
      image.set_padding(2, 0)

      label_box = TabLabelBox.new(image, panobject.pname, page_sw) do
        store.clear
        treeview.destroy
      end

      page = notebook.append_page(page_sw, label_box)
      notebook.set_tab_reorderable(page_sw, true)
      page_sw.show_all
      notebook.page = notebook.n_pages-1

      #pbox.update_if_need

      treeview.grab_focus
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::ADD, _('Create'), 'Insert'], treeview))  #:NEW
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT.to_s+edit_opt, _('Edit'), 'Return'], treeview))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete'], treeview))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item([chat_item, chat_stock.to_s+dlg_opt, _(chat_item), '<control>D'], treeview))

    if (panobject.is_a? PandoraModel::Created)
      menu.append(create_menu_item(['Dialog', :dialog, _('Dialog with creator')], treeview))
    end

    menu.append(create_menu_item(['Relation', :relation, _('Relate'), '<control>R'], treeview))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Convert', Gtk::Stock::CONVERT, _('Convert')], treeview))
    menu.append(create_menu_item(['Import', Gtk::Stock::OPEN, _('Import')], treeview))
    menu.append(create_menu_item(['Export', Gtk::Stock::SAVE, _('Export')], treeview))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button-press-event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

    treeview.signal_connect('key-press-event') do |widget, event|
      res = true
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
        act_panobject(treeview, 'Edit')
        #act_panobject(treeview, 'Dialog')
      elsif (event.keyval==Gdk::Keyval::GDK_Insert)
        if event.state.control_mask?
          act_panobject(treeview, 'Copy')
        else
          act_panobject(treeview, 'Create')
        end
      elsif (event.keyval==Gdk::Keyval::GDK_Delete)
        act_panobject(treeview, 'Delete')
      elsif event.state.control_mask?
        if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
          act_panobject(treeview, 'Dialog')
        else
          res = false
        end
      else
        res = false
      end
      res
    end
    auto_create
  end

  # Update period for treeview tables
  # RU: Период обновления для таблиц
  TAB_UPD_PERIOD = 2   #second

  $treeview_thread = nil

  # Launch update thread for a table of the panobjbox
  # RU: Запускает поток обновления таблицы панобъекта
  def self.update_treeview_if_need(panobjbox=nil)
    if $treeview_thread
      $treeview_thread.exit if $treeview_thread.alive?
      $treeview_thread = nil
    end
    if (panobjbox.is_a? PanobjScrolledWindow) \
    and panobjbox.auto_btn and panobjbox.auto_btn.active?
      $treeview_thread = Thread.new do
        while panobjbox and (not panobjbox.destroyed?) and panobjbox.treeview \
        and (not panobjbox.treeview.destroyed?) and $window.visible?
          #p 'update_treeview_if_need: '+panobjbox.treeview.panobject.ider
          if panobjbox.treeview.panobject.class.modified
            #p 'update_treeview_if_need: modif='+panobjbox.treeview.panobject.class.modified.inspect
            #panobjbox.update_btn.clicked
            panobjbox.update_treeview
          end
          sleep(TAB_UPD_PERIOD)
        end
        $treeview_thread = nil
      end
    end
  end

  # Take pointer index for sending by room
  # RU: Взять индекс указателя для отправки по id комнаты
  def self.set_send_ptrind_by_panhash(room_id)
    ptr = nil
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = true
        ptr = ptr[1]
      else
        ptr = $send_media_rooms.size
        $send_media_rooms[room_id] = [true, ptr]
      end
    end
    ptr
  end

  # Check pointer index for sending by room
  # RU: Проверить индекс указателя для отправки по id комнаты
  def self.get_send_ptrind_by_panhash(room_id)
    ptr = nil
    if room_id
      set_ptr = $send_media_rooms[room_id]
      if set_ptr and set_ptr[0]
        ptr = set_ptr[1]
      end
    end
    ptr
  end

  # Clear pointer index for sending for room
  # RU: Сбросить индекс указателя для отправки для комнаты
  def self.nil_send_ptrind_by_panhash(room_id)
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = false
      end
    end
    res = $send_media_rooms.count{ |panhas, ptr| ptr[0] }
  end

  $key_watch_lim   = 5
  $sign_watch_lim  = 5

  # Get person panhash by any panhash
  # RU: Получить панхэш персоны по произвольному панхэшу
  def self.extract_targets_from_panhash(targets, panhashes=nil)
    persons, keys, nodes = targets
    if panhashes
      panhashes = [panhashes] if panhashes.is_a? String
      #p '--extract_targets_from_panhash  targets='+targets.inspect
      panhashes.each do |panhash|
        if (panhash.is_a? String) and (panhash.bytesize>0)
          kind = PandoraUtils.kind_from_panhash(panhash)
          panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
          if panobjectclass
            if panobjectclass <= PandoraModel::Person
              persons << panhash
            elsif panobjectclass <= PandoraModel::Node
              nodes << panhash
            else
              if panobjectclass <= PandoraModel::Created
                model = PandoraUtils.get_model(panobjectclass.ider)
                filter = {:panhash=>panhash}
                sel = model.select(filter, false, 'creator')
                if sel and sel.size>0
                  sel.each do |row|
                    persons << row[0]
                  end
                end
              end
            end
          end
        end
      end
    end
    persons.uniq!
    persons.compact!
    if (keys.size == 0) and (nodes.size > 0)
      nodes.uniq!
      nodes.compact!
      model = PandoraUtils.get_model('Node')
      nodes.each do |node|
        sel = model.select({:panhash=>node}, false, 'key_hash')
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
    end
    keys.uniq!
    keys.compact!
    if (persons.size == 0) and (keys.size > 0)
      kmodel = PandoraUtils.get_model('Key')
      smodel = PandoraUtils.get_model('Sign')
      keys.each do |key|
        sel = kmodel.select({:panhash=>key}, false, 'creator', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            persons << row[0]
          end
        end
        sel = smodel.select({:key_hash=>key}, false, 'creator', 'modified DESC', $sign_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            persons << row[0]
          end
        end
      end
      persons.uniq!
      persons.compact!
    end
    if nodes.size == 0
      model = PandoraUtils.get_model('Key')
      persons.each do |person|
        sel = model.select({:creator=>person}, false, 'panhash', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
      if keys.size == 0
        model = PandoraUtils.get_model('Sign')
        persons.each do |person|
          sel = model.select({:creator=>person}, false, 'key_hash', 'modified DESC', $sign_watch_lim)
          if sel and (sel.size>0)
            sel.each do |row|
              keys << row[0]
            end
          end
        end
      end
      keys.uniq!
      keys.compact!
      model = PandoraUtils.get_model('Node')
      keys.each do |key|
        sel = model.select({:key_hash=>key}, false, 'panhash')
        if sel and (sel.size>0)
          sel.each do |row|
            nodes << row[0]
          end
        end
      end
      #p '[keys, nodes]='+[keys, nodes].inspect
      #p 'targets3='+targets.inspect
    end
    nodes.uniq!
    nodes.compact!
    nodes.size
  end

  def self.extract_from_panhash(panhash, node_id=nil)
    targets = [[], [], []]
    persons, keys, nodes = targets
    #if nodehash and (panhashes.is_a? String)
    #  persons << panhashes
    #  nodes << nodehash
    #else
      extract_targets_from_panhash(targets, panhash)
    #end
    targets.each do |list|
      list.sort!
      list.uniq!
      list.compact!
    end
    p 'targets='+[targets].inspect

    target_exist = ((persons.size>0) or (nodes.size>0) or (keys.size>0))
    if (not target_exist) and node_id
      node_model = PandoraUtils.get_model('Node', models)
      sel = node_model.select({:id => node_id}, false, 'panhash, key_hash', nil, 1)
      if sel and (sel.size>0)
        sel.each do |row|
          nodes << row[0]
          keys  << row[1]
        end
        extract_targets_from_panhash(targets)
      end
    end
    targets
  end

  # Find active sender
  # RU: Найти активного отправителя
  def self.find_another_active_sender(not_this=nil)
    res = nil
    $window.notebook.children.each do |child|
      if (child != not_this) and (child.is_a? CabinetBox) \
      and child.webcam_btn and child.webcam_btn.active?
        return child
      end
    end
    res
  end

  # Get view parameters
  # RU: Взять параметры вида
  def self.get_view_params
    $load_history_count = PandoraUtils.get_param('load_history_count')
    $load_more_history_count = PandoraUtils.get_param('load_more_history_count')
    $sort_history_mode = PandoraUtils.get_param('sort_history_mode')
  end

  # Get main parameters
  # RU: Взять основные параметры
  def self.get_main_params
    get_view_params
  end

  # About dialog hooks
  # RU: Обработчики диалога "О программе"
  Gtk::AboutDialog.set_url_hook do |about, link|
    PandoraUtils.external_open(link)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    PandoraUtils.external_open(link)
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.program_name = dlg.name
    dlg.version = PandoraUtils.pandora_version + ' [' + PandoraUtils.pandora_md5_sum[0, 6] + ']'
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.website = 'https://github.com/Novator/Pandora'
    dlg.skip_taskbar_hint = true
    dlg.authors = ['© '+_('Michael Galyuk')+' <robux@mail.ru>']
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('P2P planetary network')
    dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
    gpl_text = nil
    begin
      file = File.open(File.join($pandora_app_dir, 'LICENSE.TXT'), 'r')
      gpl_text = '================='+_('Full text')+" LICENSE.TXT==================\n"+file.read
      file.close
    rescue
      gpl_text = _('Full text is in the file')+' LICENSE.TXT.'
    end
    gpl_text ||= ''
    dlg.license = _("Pandora is licensed under GNU GPLv2.\n"+
      "\nFundamentals:\n"+
      "- program code is open, distributed free and without warranty;\n"+
      "- author does not require you money, but demands respect authorship;\n"+
      "- you can change the code, sent to the authors for inclusion in the next release;\n"+
      "- your own release you must distribute with another name and only licensed under GPL;\n"+
      "- if you do not understand the GPL or disagree with it, you have to uninstall the program.\n\n")+gpl_text
    dlg.wrap_license = true
    credits = nil
    begin
      file = File.open(File.join($pandora_doc_dir, 'sponsors.txt'), 'r')
      credits = file.read
      file.close
    rescue
      credits = nil
    end
    changelog = nil
    begin
      file = File.open(File.join($pandora_doc_dir, 'changelog.txt'), 'r')
      changelog = file.read
      file.close
    rescue
      changelog = nil
    end
    if changelog
      credits ||= ''
      credits << changelog
    end
    #dlg.documenters = dlg.authors
    dlg.translator_credits = credits if credits
    dlg.signal_connect('key-press-event') do |widget, event|
      if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
        event.keyval) and event.state.control_mask? #w, W, ц, Ц
      then
        widget.response(Gtk::Dialog::RESPONSE_CANCEL)
        false
      elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
        event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
        Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
        and event.state.control_mask?) #q, Q, й, Й
      then
        widget.destroy
        PandoraUI.do_menu_act('Quit')
        false
      else
        false
      end
    end
    dlg.run
    if not dlg.destroyed?
      dlg.destroy
      $window.present
    end
  end

  # Show capcha
  # RU: Показать капчу
  def self.show_captcha(captcha_buf=nil, clue_text=nil, conntype=nil, node=nil, \
  node_id=nil, models=nil, panhashes=nil, session=nil)
    res = nil
    sw = nil
    p '--recognize_captcha(captcha_buf.size, clue_text, node, node_id, models)='+\
      [captcha_buf.size, clue_text, node, node_id, models].inspect
    if captcha_buf
      sw = PandoraGtk.show_cabinet(panhashes, session, conntype, node_id, \
        models, PandoraUI::CPI_Dialog)
      if sw
        clue_text ||= ''
        clue, length, symbols = clue_text.split('|')
        node_text = node
        pixbuf_loader = Gdk::PixbufLoader.new
        pixbuf_loader.last_write(captcha_buf)
        pixbuf = pixbuf_loader.pixbuf

        sw.init_captcha_entry(pixbuf, length, symbols, clue, node_text)

        sw.captcha_enter = true
        while (not sw.destroyed?) and (sw.captcha_enter.is_a? TrueClass)
          sleep(0.02)
          Thread.pass
        end
        p '===== sw.captcha_enter='+sw.captcha_enter.inspect
        if sw.destroyed?
          res = false
        else
          if (sw.captcha_enter.is_a? String)
            res = sw.captcha_enter.dup
          else
            res = sw.captcha_enter
          end
          sw.captcha_enter = nil
        end
      end

      #captcha_entry = PandoraGtk::MaskEntry.new
      #captcha_entry.max_length = len
      #if symbols
      #  mask = symbols.downcase+symbols.upcase
      #  captcha_entry.mask = mask
      #end
    end
    [res, sw]
  end

  # Show panobject cabinet
  # RU: Показать кабинет панобъекта
  def self.show_cabinet(panhash, session=nil, conntype=nil, \
  node_id=nil, models=nil, page=nil, fields=nil, obj_id=nil, edit=nil, tree_view=nil)
    sw = nil

    #p '---show_cabinet(panhash, session.id, conntype, node_id, models, page, fields, obj_id, edit)=' \
    #  +[panhash, session.object_id, conntype, node_id, models, page, fields, obj_id, edit].inspect

    room_id = nil
    room_id = AsciiString.new(PandoraUtils.fill_zeros_from_right(panhash, \
      PandoraModel::PanhashSize)).dup if panhash.is_a?(String)
    #room_id ||= session.object_id if session

    #if conntype.nil? or (conntype==PandoraNet::ST_Hunter)
    #  creator = PandoraCrypto.current_user_or_key(true)
    #  #room_id[-1] = (room_id[-1].ord ^ 1).chr if panhash==creator
    #end
    #p 'room_id='+room_id.inspect
    notebook = nil
    if tree_view.is_a?(SubjTreeView)
      notebook = tree_view.get_notebook
    end
    notebook ||= $window.notebook
    if room_id and notebook
      notebook.children.each do |child|
        if (child.is_a?(CabinetBox) and ((child.room_id==room_id) \
        or (session and (child.session==session))))
          #child.targets = targets
          #child.online_btn.safe_set_active(nodehash != nil)
          #child.online_btn.inconsistent = false
          notebook.page = notebook.children.index(child) if conntype.nil?
          sw = child
          if (page and ((page != PandoraUI::CPI_Chat) \
          or (not conntype.is_a?(TrueClass)) or (not child.chat_talkview) \
          or (notebook.page != notebook.children.index(child))))
            sw.show_page(page)
            sleep(0.01)
          end
          break
        end
      end
    end
    sw ||= CabinetBox.new(panhash, room_id, page, fields, obj_id, edit, session, tree_view)
    sw
  end

  # Showing search panel
  # RU: Показать панель поиска
  def self.show_search_panel(text=nil)
    sw = SearchBox.new(text)

    image = Gtk::Image.new(Gtk::Stock::FIND, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Search'), sw) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show profile panel
  # RU: Показать панель профиля
  def self.show_profile_panel(a_person=nil)
    a_person0 = a_person
    a_person ||= PandoraCrypto.current_user_or_key(true, true)

    return if not a_person

    $window.notebook.children.each do |child|
      if (child.is_a? ProfileScrollWin) and (child.person == a_person)
        $window.notebook.page = $window.notebook.children.index(child)
        return
      end
    end

    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show session list
  # RU: Показать список сеансов
  def self.show_session_panel
    $window.notebook.children.each do |child|
      if (child.is_a? SessionScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        child.update_btn.clicked
        return
      end
    end
    sw = SessionScrollWin.new

    image = Gtk::Image.new(:session, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Sessions'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show neighbor list
  # RU: Показать список соседей
  def self.show_radar_panel
    hpaned = $window.radar_hpaned
    radar_sw = $window.radar_sw
    if radar_sw.allocation.width <= 24 #hpaned.position <= 20
      radar_sw.width_request = 200 if radar_sw.width_request <= 24
      hpaned.position = hpaned.max_position-radar_sw.width_request
      radar_sw.update_btn.clicked
    else
      radar_sw.width_request = radar_sw.allocation.width
      hpaned.position = hpaned.max_position
    end
    $window.correct_fish_btn_state
    #$window.notebook.children.each do |child|
    #  if (child.is_a? RadarScrollWin)
    #    $window.notebook.page = $window.notebook.children.index(child)
    #    child.update_btn.clicked
    #    return
    #  end
    #end
    #sw = RadarScrollWin.new

    #image = Gtk::Image.new(Gtk::Stock::JUSTIFY_LEFT, Gtk::IconSize::MENU)
    #image.set_padding(2, 0)
    #label_box = TabLabelBox.new(image, _('Fishes'), sw, false, 0) do
    #  #sw.destroy
    #end
    #page = $window.notebook.append_page(sw, label_box)
    #sw.show_all
    #$window.notebook.page = $window.notebook.n_pages-1
  end

  # Switch full screen mode
  # RU: Переключить режим полного экрана
  def self.full_screen_switch
    need_show = (not $window.menubar.visible?)
    $window.menubar.visible = need_show
    $window.toolbar.visible = need_show
    $window.notebook.show_tabs = need_show
    $window.log_sw.visible = need_show
    $window.radar_sw.visible = need_show
    @last_cur_page_toolbar ||= nil
    if @last_cur_page_toolbar and (not @last_cur_page_toolbar.destroyed?)
      if need_show and (not @last_cur_page_toolbar.visible?)
        @last_cur_page_toolbar.visible = true
      end
      @last_cur_page_toolbar = nil
    end
    page = $window.notebook.page
    if (page >= 0)
      cur_page = $window.notebook.get_nth_page(page)
      if (cur_page.is_a? PandoraGtk::CabinetBox) and cur_page.toolbar_sw
        if need_show
          cur_page.toolbar_sw.visible = true if (not cur_page.toolbar_sw.visible?)
        elsif (not PandoraGtk.is_ctrl_shift_alt?(true)) and cur_page.toolbar_sw.visible?
          cur_page.toolbar_sw.visible = false
          @last_cur_page_toolbar = cur_page.toolbar_sw
        end
      end
    end
    PandoraUI.set_status_field(PandoraUI::SF_FullScr, nil, nil, (not need_show))
  end

  # Show log bar
  # RU: Показать log бар
  def self.show_log_bar(new_size=nil)
    vpaned = $window.log_vpaned
    log_sw = $window.log_sw
    if new_size and (new_size>=0) or (new_size.nil? \
    and (log_sw.allocation.height <= 24)) #hpaned.position <= 20
      if new_size and (new_size>=24)
        log_sw.height_request = new_size if (new_size>log_sw.height_request)
      else
        log_sw.height_request = log_sw.allocation.height if log_sw.allocation.height>24
        log_sw.height_request = 200 if (log_sw.height_request <= 24)
      end
      vpaned.position = vpaned.max_position-log_sw.height_request
    else
      log_sw.height_request = log_sw.allocation.height
      vpaned.position = vpaned.max_position
    end
    $window.correct_log_btn_state
  end

  # Show fisher list
  # RU: Показать список рыбаков
  def self.show_fisher_panel
    $window.notebook.children.each do |child|
      if (child.is_a? FisherScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        child.update_btn.clicked
        return
      end
    end
    sw = FisherScrollWin.new

    image = Gtk::Image.new(:fish, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Fishers'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show language phrases editor
  # RU: Показать редактор языковых фраз
  def self.show_lang_editor
    $window.notebook.children.each do |child|
      if (child.is_a? PhraseEditorScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        #child.update_btn.clicked
        return
      end
    end
    sw = PhraseEditorScrollWin.new

    image = Gtk::Image.new(:lang, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Phrases'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Set bold weight of MenuItem
  # RU: Ставит жирный шрифт у MenuItem
  def self.set_bold_to_menuitem(menuitem)
    label = menuitem.children[0]
    if (label.is_a? Gtk::Label)
      text = label.text
      if text and (not text.include?('<b>'))
        label.use_markup = true
        label.set_markup('<b>'+text+'</b>') if label.use_markup?
      end
    end
  end

  # Status icon
  # RU: Иконка в трее
  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon, :online, :play_sounds, :hide_on_minimize, :message

    # Create status icon
    # RU: Создает иконку в трее
    def initialize(a_update_win_icon=false, a_flash_on_new=true, \
    a_flash_interval=0, a_play_sounds=true, a_hide_on_minimize=true)
      super()

      @online = false
      @main_icon = nil
      if $window.icon
        @main_icon = $window.icon
      else
        @main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end
      @base_icon = @main_icon

      @online_icon = nil
      begin
        @online_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'online.ico'))
      rescue Exception
      end
      if not @online_icon
        @online_icon = $window.render_icon(Gtk::Stock::INFO, Gtk::IconSize::LARGE_TOOLBAR)
      end

      begin
        @message_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'message.ico'))
      rescue Exception
      end
      if not @message_icon
        @message_icon = $window.render_icon(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::LARGE_TOOLBAR)
      end

      @update_win_icon = a_update_win_icon
      @flash_on_new = a_flash_on_new
      @flash_interval = (a_flash_interval.to_f*1000).round
      @flash_interval = 800 if (@flash_interval<100)
      @play_sounds = a_play_sounds
      @hide_on_minimize = a_hide_on_minimize

      @message = nil
      @flash = false
      @flash_status = 0
      update_icon

      atitle = $window.title
      set_title(atitle)
      set_tooltip(atitle)

      #set_blinking(true)
      signal_connect('activate') do
        icon_activated
      end

      signal_connect('popup-menu') do |widget, button, activate_time|
        @menu ||= create_menu
        @menu.popup(nil, nil, button, activate_time)
      end
    end

    # Create and show popup menu
    # RU: Создает и показывает всплывающее меню
    def create_menu
      menu = Gtk::Menu.new

      checkmenuitem = Gtk::CheckMenuItem.new(_('Flash on new'))
      checkmenuitem.active = @flash_on_new
      checkmenuitem.signal_connect('activate') do |w|
        @flash_on_new = w.active?
        set_message(@message)
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Update window icon'))
      checkmenuitem.active = @update_win_icon
      checkmenuitem.signal_connect('activate') do |w|
        @update_win_icon = w.active?
        $window.icon = @base_icon
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Play sounds'))
      checkmenuitem.active = @play_sounds
      checkmenuitem.signal_connect('activate') do |w|
        @play_sounds = w.active?
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Hide on minimize'))
      checkmenuitem.active = @hide_on_minimize
      checkmenuitem.signal_connect('activate') do |w|
        @hide_on_minimize = w.active?
      end
      menu.append(checkmenuitem)

      menuitem = Gtk::ImageMenuItem.new(Gtk::Stock::PROPERTIES)
      alabel = menuitem.children[0]
      alabel.set_text(_('All parameters')+'..', true)
      menuitem.signal_connect('activate') do |w|
        icon_activated(false, true)
        PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
      end
      menu.append(menuitem)

      menuitem = Gtk::SeparatorMenuItem.new
      menu.append(menuitem)

      menuitem = Gtk::MenuItem.new(_('Show/Hide'))
      PandoraGtk.set_bold_to_menuitem(menuitem)
      menuitem.signal_connect('activate') do |w|
        icon_activated(false)
      end
      menu.append(menuitem)

      menuitem = Gtk::ImageMenuItem.new(Gtk::Stock::QUIT)
      alabel = menuitem.children[0]
      alabel.set_text(_('_Quit'), true)
      menuitem.signal_connect('activate') do |w|
        self.set_visible(false)
        $window.destroy
      end
      menu.append(menuitem)

      menu.show_all
      menu
    end

    # Set status "online"
    # RU: Задаёт статус "онлайн"
    def set_online(state=nil)
      base_icon0 = @base_icon
      if state
        @base_icon = @online_icon
      elsif state==false
        @base_icon = @main_icon
      end
      update_icon
    end

    # Set status "message comes"
    # RU: Задаёт статус "есть сообщение"
    def set_message(message=nil)
      if (message.is_a? String) and (message.size>0)
        @message = message
        set_tooltip(message)
        set_flash(@flash_on_new)
      else
        @message = nil
        set_tooltip($window.title)
        set_flash(false)
      end
    end

    # Set flash mode
    # RU: Задаёт мигание
    def set_flash(flash=true)
      @flash = flash
      if flash
        @flash_status = 1
        if not @timer
          timeout_func
        end
      else
        @flash_status = 0
      end
      update_icon
    end

    # Update icon
    # RU: Обновляет иконку
    def update_icon
      stat_icon = nil
      if @message and ((not @flash) or (@flash_status==1))
        stat_icon = @message_icon
      else
        stat_icon = @base_icon
      end
      self.pixbuf = stat_icon if (self.pixbuf != stat_icon)
      if @update_win_icon
        $window.icon = stat_icon if $window.visible? and ($window.icon != stat_icon)
      else
        $window.icon = @main_icon if ($window.icon != @main_icon)
      end
    end

    # Set timer on a flash step
    # RU: Ставит таймер на шаг мигания
    def timeout_func
      @timer = GLib::Timeout.add(@flash_interval) do
        next_step = true
        if @flash_status == 0
          @flash_status = 1
        else
          @flash_status = 0
          next_step = false if not @flash
        end
        update_icon
        @timer = nil if not next_step
        next_step
      end
    end

    # Action on icon click
    # RU: Действия при нажатии на иконку
    def icon_activated(top_sens=true, force_show=false)
      #$window.skip_taskbar_hint = false
      if $window.visible? and (not force_show)
        if (not top_sens) or ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
          $window.hide
        else
          PandoraUI.do_menu_act('Activate')
        end
      else
        PandoraUI.do_menu_act('Activate')
        update_icon if @update_win_icon
        if @message and (not force_show)
          page = $window.notebook.page
          if (page >= 0)
            cur_page = $window.notebook.get_nth_page(page)
            if cur_page.is_a?(PandoraGtk::CabinetBox)
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($window.notebook.n_pages == 0)
          end
        end
      end
    end
  end  #--PandoraStatusIcon

  def self.detect_icon_opts(stock)
    res = stock
    opts = 'mt'
    if res.is_a? String
      i = res.index(':')
      if i
        opts = res[i+1..-1]
        res = res[0, i]
        res = nil if res==''
      end
    end
    [res, opts]
  end

  $status_font = nil

  def self.status_font
    if $status_font.nil?
      style = Gtk::Widget.default_style
      font = style.font_desc
      fs = font.size
      fs = fs * Pango::SCALE_SMALL if fs
      font.size = fs if fs
      $status_font = font
    end
    $status_font
  end

  class GoodButton < Gtk::Frame
    attr_accessor :hbox, :image, :label, :active, :group_set

    def initialize(astock, atitle=nil, atoggle=nil, atooltip=nil)
      super()
      self.tooltip_text = atooltip if atooltip
      @group_set = nil
      if atoggle.is_a? Integer
        @group_set = atoggle
        atoggle = (atoggle>0)
      end
      @hbox = Gtk::HBox.new
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(@image)

      @proc_on_click = Proc.new do |*args|
        yield(*args) if block_given?
      end

      @im_evbox = Gtk::EventBox.new
      #@im_evbox.border_width = 2
      @im_evbox.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK
      @lab_evbox = Gtk::EventBox.new
      #@lab_evbox.border_width = 1
      @lab_evbox.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK

      set_image(astock)
      set_label(atitle)
      self.add(@hbox)

      set_active(atoggle)

      @enter_event = Proc.new do |body_child, event|
        self.shadow_type = Gtk::SHADOW_OUT if @active.nil?
        false
      end

      @leave_event = Proc.new do |body_child, event|
        self.shadow_type = Gtk::SHADOW_NONE if @active.nil?
        false
      end

      @press_event = Proc.new do |widget, event|
        if (event.button == 1)
          if @active.nil?
            self.shadow_type = Gtk::SHADOW_IN
          elsif @group_set.nil?
            @active = (not @active)
            set_active(@active)
          end
          do_on_click
        end
        false
      end

      @release_event = Proc.new do |widget, event|
        set_active(@active)
        false
      end

      @im_evbox.signal_connect('enter-notify-event') { |*args| @enter_event.call(*args) }
      @im_evbox.signal_connect('leave-notify-event') { |*args| @leave_event.call(*args) }
      @im_evbox.signal_connect('button-press-event') { |*args| @press_event.call(*args) }
      @im_evbox.signal_connect('button-release-event') { |*args| @release_event.call(*args) }

      @lab_evbox.signal_connect('enter-notify-event') { |*args| @enter_event.call(*args) }
      @lab_evbox.signal_connect('leave-notify-event') { |*args| @leave_event.call(*args) }
      @lab_evbox.signal_connect('button-press-event') { |*args| @press_event.call(*args) }
      @lab_evbox.signal_connect('button-release-event') { |*args| @release_event.call(*args) }
    end

    def do_on_click
      @proc_on_click.call
    end

    def active?
      @active
    end

    def set_active(toggle)
      @active = toggle
      if @active.nil?
        self.shadow_type = Gtk::SHADOW_NONE
      elsif @active
        self.shadow_type = Gtk::SHADOW_IN
        @im_evbox.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#C9C9C9'))
        @lab_evbox.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#C9C9C9'))
      else
        self.shadow_type = Gtk::SHADOW_OUT
        @im_evbox.modify_bg(Gtk::STATE_NORMAL, nil)
        @lab_evbox.modify_bg(Gtk::STATE_NORMAL, nil)
      end
    end

    def set_image(astock=nil)
      if @image
        @image.destroy
        @image = nil
      end
      if astock
        #$window.get_preset_iconset(astock)
        $window.register_stock(astock)
        @image = Gtk::Image.new(astock, Gtk::IconSize::MENU)
        @image.set_padding(2, 2)
        @image.set_alignment(0.5, 0.5)
        @im_evbox.add(@image)
        @hbox.pack_start(@im_evbox, true, true, 0)
      end
    end

    def set_label(atitle=nil)
      if atitle.nil?
        if @label
          @label.visible = false
          @label.text = ''
        end
      else
        if @label
          @label.text = atitle
          @label.visible = true if not @label.visible?
        else
          @label = Gtk::Label.new(atitle)
          @label.set_padding(2, 2)
          @label.set_alignment(0.0, 0.5)
          @label.modify_font(PandoraGtk.status_font)
          #p style = @label.style
          #p style = @label.modifier_style
          #p style = Gtk::Widget.default_style
          #p style.font_desc
          #p style.font_desc.size
          #p style.font_desc.family
          @lab_evbox.add(@label)
          @hbox.pack_start(@lab_evbox, true, true, 0)
        end
      end
    end
  end

  # Main window
  # RU: Главное окно
  class MainWindow < Gtk::Window
    attr_accessor :log_view, :notebook, \
      :pool, :focus_timer, :radar_hpaned, :task_offset, \
      :radar_sw, :log_vpaned, :log_sw, :accel_group, :menubar, \
      :toolbar, :hand_cursor, :regular_cursor


    include PandoraUtils

    # Maximal lines in log textview
    # RU: Максимум строк в лотке лога
    MaxLogViewLineCount = 500

    # Add message to log textview
    # RU: Добавить сообщение в лоток лога
    def add_mes_to_log_view(mes, time, level)
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
    end

    $toggle_buttons = []

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_lis_btn_state
      tool_btn = $toggle_buttons[PandoraUI::SF_Listen]
      if tool_btn
        lis_act = PandoraNet.listen?
        tool_btn.safe_set_active(lis_act) if tool_btn.is_a? SafeToggleToolButton
      end
    end

    # Change hunter button state
    # RU: Изменить состояние кнопки охотника
    def correct_hunt_btn_state
      tool_btn = $toggle_buttons[PandoraUI::SF_Hunt]
      #pushed = ((not $hunter_thread.nil?) and $hunter_thread[:active] \
      #  and (not $hunter_thread[:paused]))
      pushed = PandoraNet.hunting?
      #p 'correct_hunt_btn_state: pushed='+[tool_btn, pushed, $hunter_thread, \
      #  $hunter_thread[:active], $hunter_thread[:paused]].inspect
      tool_btn.safe_set_active(pushed) if tool_btn.is_a? SafeToggleToolButton
      PandoraUI.set_status_field(PandoraUI::SF_Hunt, nil, nil, pushed)
    end

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_fish_btn_state
      hpaned = $window.radar_hpaned
      #list_sw = hpaned.children[1]
      an_active = (hpaned.max_position - hpaned.position) > 24
      #(list_sw.allocation.width > 24)
      #($window.radar_hpaned.position > 24)
      PandoraUI.set_status_field(PandoraUI::SF_Radar, nil, nil, an_active)
      #tool_btn = $toggle_buttons[PandoraUI::SF_Radar]
      #if tool_btn
      #  hpaned = $window.radar_hpaned
      #  list_sw = hpaned.children[0]
      #  tool_btn.safe_set_active(hpaned.position > 24)
      #end
    end

    def correct_log_btn_state
      vpaned = $window.log_vpaned
      an_active = (vpaned.max_position - vpaned.position) > 24
      PandoraUI.set_status_field(PandoraUI::SF_Log, nil, nil, an_active)
    end

    # Show notice status
    # RU: Показать уведомления в статусе
    #def show_notice(change=nil)
    #  if change
    #    PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
    #  end
    #  PandoraNet.get_notice_params
    #  notice = PandoraModel.transform_trust($notice_trust, :auto_to_float)
    #  notice = notice.round(1).to_s + '/'+$notice_depth.to_s
    #  set_status_field(PandoraUI::SF_Notice, notice)
    #end

    $statusbar = nil
    $status_fields = []

    # Add field to statusbar
    # RU: Добавляет поле в статусбар
    def add_status_field(index, text, tooltip=nil, stock=nil, toggle=nil, separ_pos=nil)
      separ_pos ||= 1
      if (separ_pos & 1)>0
        $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      end
      toggle_group = nil
      toggle_group = -1 if not toggle.nil?
      tooltip = _(tooltip) if tooltip
      btn = GoodButton.new(stock, text, toggle_group, tooltip) do |*args|
        yield(*args) if block_given?
      end
      btn.set_active(toggle) if not toggle.nil?
      $statusbar.pack_start(btn, false, false, 0)
      $status_fields[index] = btn
      if (separ_pos & 2)>0
        $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      end
    end

    # Set properties of fiels in statusbar
    # RU: Задаёт свойства поля в статусбаре
    def set_status_field(index, text, enabled=nil, toggle=nil)
      fld = $status_fields[index]
      if fld
        if text
          str = _(text)
          str = _('Version') + ': ' + str if (index==PandoraUI::SF_Update)
          fld.set_label(str)
        end
        fld.sensitive = enabled if (enabled != nil)
        if (toggle != nil)
          fld.set_active(toggle)
          btn = $toggle_buttons[index]
          btn.safe_set_active(toggle) if btn and (btn.is_a? SafeToggleToolButton)
        end
      end
    end

    # Get fiels of statusbar
    # RU: Возвращает поле статусбара
    def get_status_field(index)
      $status_fields[index]
    end

    def get_icon_file_params(preset)
      icon_params, icon_file_desc = nil
      smile_desc = PandoraUtils.get_param('icons_'+preset)
      if smile_desc
        icon_params = smile_desc.split('|')
        icon_file_desc = icon_params[0]
        icon_params.delete_at(0)
      end
      [icon_params, icon_file_desc]
    end

    # Return Pixbuf with icon picture
    # RU: Возвращает Pixbuf с изображением иконки
    def get_icon_buf(emot='smile', preset='qip')
      buf = nil
      if not preset
        @def_smiles ||= PandoraUtils.get_param('def_smiles')
        preset = @def_smiles
      end
      buf = @icon_bufs[preset][emot] if @icon_bufs and @icon_bufs[preset]
      icon_preset = nil
      if buf.nil?
        @icon_presets ||= Hash.new
        icon_preset = @icon_presets[preset]
        if icon_preset.nil?
          icon_params, icon_file_desc = get_icon_file_params(preset)
          if icon_params and icon_file_desc
            icon_file_params = icon_file_desc.split(':')
            icon_file_name = icon_file_params[0]
            numXs, numYs = icon_file_params[1].split('x')
            bord_s = icon_file_params[2]
            bord_s.delete!('p')
            padd_s = icon_file_params[3]
            padd_s.delete!('p')
            begin
              smile_fn = File.join($pandora_view_dir, icon_file_name)
              preset_buf = Gdk::Pixbuf.new(smile_fn)
              if preset_buf
                big_width = preset_buf.width
                big_height = preset_buf.height
                #p 'get_icon_buf [big_width, big_height]='+[big_width, big_height].inspect
                bord = bord_s.to_i
                padd = padd_s.to_i
                numX = numXs.to_i
                numY = numYs.to_i
                cellX = (big_width - 2*bord - (numX-1)*padd)/numX
                cellY = (big_height - 2*bord - (numY-1)*padd)/numY

                icon_preset = Hash.new
                icon_preset[:names]      = icon_params
                icon_preset[:big_width]  = big_width
                icon_preset[:big_height] = big_height
                icon_preset[:bord]       = bord
                icon_preset[:padd]       = padd
                icon_preset[:numX]       = numX
                icon_preset[:numY]       = numY
                icon_preset[:cellX]      = cellX
                icon_preset[:cellY]      = cellY
                icon_preset[:buf]        = preset_buf
                @icon_presets[preset] = icon_preset
              end
            rescue
              p 'Error while load smile file: ['+smile_fn+']'
            end
          end
        end
      end

      def transpix?(pix, bg)
        res = ((pix.size == 4) and (pix[-1] == 0.chr) or (pix == bg))
      end

      if buf.nil? and icon_preset
        index = icon_preset[:names].index(emot)
        if index.nil?
          if icon_preset[:def_index].nil?
            PandoraUtils.set_param('icons_'+preset, nil)
            icon_params, icon_file_desc = get_icon_file_params(preset)
            icon_preset[:names] = icon_params
            index = icon_preset[:names].index(emot)
            icon_preset[:def_index] = 0
          end
          index ||= icon_preset[:def_index]
        end
        if index
          big_width  = icon_preset[:big_width]
          big_height = icon_preset[:big_height]
          bord       = icon_preset[:bord]
          padd       = icon_preset[:padd]
          numX       = icon_preset[:numX]
          numY       = icon_preset[:numY]
          cellX      = icon_preset[:cellX]
          cellY      = icon_preset[:cellY]
          preset_buf = icon_preset[:buf]

          iY = index.div(numX)
          iX = index - (iY*numX)
          dX = bord + iX*(cellX+padd)
          dY = bord + iY*(cellY+padd)
          #p '[cellX, cellY, iX, iY, dX, dY]='+[cellX, cellY, iX, iY, dX, dY].inspect
          draft_buf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, cellX, cellY)
          preset_buf.copy_area(dX, dY, cellX, cellY, draft_buf, 0, 0)
          #draft_buf = Gdk::Pixbuf.new(preset_buf, 0, 0, 21, 24)

          pixs = draft_buf.pixels
          if pixs.is_a?(String)
            pixs = AsciiString.new(draft_buf.pixels)
            pix_size = draft_buf.n_channels
            width = draft_buf.width
            height = draft_buf.height
            w = width * pix_size  #buf.rowstride
            #p '[pixs.bytesize, width, height, w]='+[pixs.bytesize, width, height, w].inspect

            bg = pixs[0, pix_size]   #top left pixel consider background

            # Find top border
            top = 0
            while (top<height)
              x = 0
              while (x<w) and transpix?(pixs[w*top+x, pix_size], bg)
                x += pix_size
              end
              if x<w
                break
              else
                top += 1
              end
            end

            # Find bottom border
            bottom = height-1
            while (bottom>top)
              x = 0
              while (x<w) and transpix?(pixs[w*bottom+x, pix_size], bg)
                x += pix_size
              end
              if x<w
                break
              else
                bottom -= 1
              end
            end

            # Find left border
            left = 0
            while (left<w)
              y = 0
              while (y<height) and transpix?(pixs[w*y+left, pix_size], bg)
                y += 1
              end
              if y<height
                break
              else
                left += pix_size
              end
            end

            # Find right border
            right = w - pix_size
            while (right>left)
              y = 0
              while (y<height) and transpix?(pixs[w*y+right, pix_size], bg)
                y += 1
              end
              if y<height
                break
              else
                right -= pix_size
              end
            end

            left = left/pix_size
            right = right/pix_size
            #p '====[top,bottom,left,right]='+[top,bottom,left,right].inspect

            width2 = right-left+1
            height2 = bottom-top+1
            #p '  ---[width2,height2]='+[width2,height2].inspect

            if (width2>0) and (height2>0) \
            and ((left>0) or (top>0) or (width2<width) or (height2<height))
              # Crop borders
              buf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, width2, height2)
              draft_buf.copy_area(left, top, width2, height2, buf, 0, 0)
            else
              buf = draft_buf
            end
          else
            buf = draft_buf
          end
          @icon_bufs ||= Hash.new
          @icon_bufs[preset] ||= Hash.new
          @icon_bufs[preset][emot] = buf
        else
          p 'No emotion ['+emot+'] in the preset ['+preset+']'
        end
      end
      buf
    end

    def get_icon_scale_buf(emot='smile', preset='pan', icon_size=16, center=true)
      buf = get_icon_buf(emot, preset)
      buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
    end

    $iconsets = {}

    # Return Image with defined icon size
    # RU: Возвращает Image с заданным размером иконки
    def get_preset_iconset(iname, preset='pan')
      ind = [iname.to_s, preset]
      res = $iconsets[ind]
      if res.nil?
        if (iname.is_a? Symbol)
          res = Gtk::IconFactory.lookup_default(iname.to_s)
          iname = iname.to_s if res.nil?
        end
        if res.nil? and preset
          buf = get_icon_buf(iname, preset)
          if buf
            width = buf.width
            height = buf.height
            if width==height
              qbuf = buf
            else
              asize = width
              asize = height if asize<height
              left = (asize - width)/2
              top  = (asize - height)/2
              qbuf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, asize, asize)
              qbuf.fill!(0xFFFFFF00)
              buf.copy_area(0, 0, width, height, qbuf, left, top)
            end
            res = Gtk::IconSet.new(qbuf)
          end
        end
        $iconsets[ind] = res if res
      end
      res
    end

    def get_preset_icon(iname, preset='pan', icon_size=nil)
      res = nil
      iconset = get_preset_iconset(iname, preset)
      if iconset
        icon_size ||= Gtk::IconSize::DIALOG
        if icon_size.is_a? Integer
          icon_name = Gtk::IconSize.get_name(icon_size)
          icon_name ||= 'SIZE'+icon_size.to_s
          icon_res = Gtk::IconSize.from_name(icon_name)
          if (not icon_res) or (icon_res==0)
            icon_size = Gtk::IconSize.register(icon_name, icon_size, icon_size)
          else
            icon_size = icon_res
          end
        end
        style = Gtk::Widget.default_style
        res = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
          Gtk::STATE_NORMAL, icon_size)  #Gtk::IconSize::LARGE_TOOLBAR)
      end
      res
    end

    # Return Image with defined icon size
    # RU: Возвращает Image с заданным размером иконки
    def get_preset_image(iname, isize=Gtk::IconSize::MENU, preset='pan')
      image = nil
      isize ||= Gtk::IconSize::MENU
      #p 'get_preset_image  iname='+[iname, isize].inspect
      #if iname.is_a? String
        iconset = get_preset_iconset(iname, preset)
        image = Gtk::Image.new(iconset, isize)
      #else
      #  p image = Gtk::Image.new(iname, isize)
      #end
      image.set_alignment(0.5, 0.5)
      image
    end

    def get_panobject_stock(panobject_ider)
      res = panobject_ider
      mi = MENU_ITEMS.detect {|mi| mi[0]==res }
      if mi
        stock_opt = mi[1]
        stock, opts = PandoraGtk.detect_icon_opts(stock_opt)
        res = stock.to_sym if stock
      end
      res
    end

    def get_panobject_image(panobject_ider, isize=Gtk::IconSize::MENU, preset='pan')
      res = nil
      stock = get_panobject_stock(panobject_ider)
      res = get_preset_image(stock, isize, preset) if stock
      res
    end

    # Register new stock by name of image preset
    # RU: Регистрирует новый stock по имени пресета иконки
    def register_stock(stock=:person, preset=nil, name=nil)
      stock = stock.to_sym if stock.is_a? String
      stock_inf = nil
      preset ||= 'pan'
      suff = preset
      suff = '' if (preset=='pan' or (preset.nil?))
      reg_stock = stock.to_s
      if suff and (suff.size>0)
        reg_stock << '_'+suff.to_s
      end
      reg_stock = reg_stock.to_sym
      begin
        stock_inf = Gtk::Stock.lookup(reg_stock)
      rescue
      end
      if not stock_inf
        icon_set = get_preset_iconset(stock.to_s, preset)
        if icon_set
          name ||= '_'+stock.to_s.capitalize
          Gtk::Stock.add(reg_stock, name)
          @icon_factory.add(reg_stock.to_s, icon_set)
        end
      end
      stock_inf
    end

    # Export table to file
    # RU: Выгрузить таблицу в файл
    def export_table(panobject, filename=nil)

      ider = panobject.ider
      separ = '|'

      File.open(filename, 'w') do |file|
        file.puts('# Export table ['+ider+']')
        file.puts('# Code page: UTF-8')

        tab_flds = panobject.tab_fields
        #def_flds = panobject.def_fields
        #id = df[PandoraUtils::FI_Id]
        #tab_ind = tab_flds.index{ |tf| tf[0] == id }
        fields = tab_flds.collect{|tf| tf[0]}
        fields = fields.join('|')
        file.puts('# Fields: '+fields)

        sel = panobject.select(nil, false, nil, panobject.sort)
        sel.each do |row|
          line = ''
          row.each_with_index do |cell,i|
            line += separ if i>0
            if cell
              begin
                #line += '"' + cell.to_s + '"' if cell
                line += cell.to_s
              rescue
              end
            end
          end
          file.puts(Utf8String.new(line))
        end
      end

      PandoraUI.log_message(PandoraUI::LM_Info, _('Table exported')+': '+filename)
    end

    # Menu structure
    # RU: Структура меню
    MENU_ITEMS =
      [[nil, nil, '_World'],
      ['Person', 'person', 'People', '<control>E'], #Gtk::Stock::ORIENTATION_PORTRAIT
      ['Community', 'community:m', 'Communities'],
      ['Blob', 'blob', 'Files', '<control>J'], #Gtk::Stock::FILE Gtk::Stock::HARDDISK
      ['-', nil, '-'],
      ['City', 'city:m', 'Towns'],
      ['Street', 'street:m', 'Streets'],
      ['Address', 'address:m', 'Addresses'],
      ['Contact', 'contact:m', 'Contacts'],
      ['Country', 'country:m', 'States'],
      ['Language', 'lang:m', 'Languages'],
      ['Word', 'word', 'Words'], #Gtk::Stock::SPELL_CHECK
      ['Relation', 'relation:m', 'Relations'],
      ['-', nil, '-'],
      ['Task', 'task:m', 'Tasks'],
      ['Message', 'message:m', 'Messages'],
      [nil, nil, '_Business'],
      ['Advertisement', 'ad', 'Advertisements'],
      ['Order', 'order:m', 'Orders'],
      ['Deal', 'deal:m', 'Deals'],
      ['Transfer', 'transfer:m', 'Transfers'],
      ['Waybill', 'waybill:m', 'Waybills'],
      ['-', nil, '-'],
      ['Debenture', 'debenture:m', 'Debentures'],
      ['Deposit', 'deposit:m', 'Deposits'],
      ['Guarantee', 'guarantee:m', 'Guarantees'],
      ['Insurer', 'insurer:m', 'Insurers'],
      ['-', nil, '-'],
      ['Product', 'product:m', 'Products'],
      ['Service', 'service:m', 'Services'],
      ['Currency', 'currency:m', 'Currency'],
      ['Storage', 'storage:m', 'Storages'],
      ['Estimate', 'estimate:m', 'Estimates'],
      ['Contract', 'contract:m', 'Contracts'],
      ['Report', 'report:m', 'Reports'],
      [nil, nil, '_Region'],
      ['Law', 'law:m', 'Laws'],
      ['Resolution', 'resolution:m', 'Resolutions'],
      ['-', nil, '-'],
      ['Project', 'project', 'Projects'],
      ['Offense', 'offense:m', 'Offenses'],
      ['Punishment', 'punishment', 'Punishments'],
      ['-', nil, '-'],
      ['Contribution', 'contribution:m', 'Contributions'],
      ['Expenditure', 'expenditure:m', 'Expenditures'],
      ['-', nil, '-'],
      ['Resource', 'resource:m', 'Resources'],
      ['Delegation', 'delegation:m', 'Delegations'],
      ['Registry', 'registry:m', 'Registry'],
      [nil, nil, '_Node'],
      ['Parameter', Gtk::Stock::PROPERTIES, 'Parameters'],
      ['-', nil, '-'],
      ['Key', 'key', 'Keys'],   #Gtk::Stock::GOTO_BOTTOM
      ['Sign', 'sign:m', 'Signs'],
      ['Node', 'node', 'Nodes'],  #Gtk::Stock::NETWORK
      ['Request', 'request:m', 'Requests'],  #Gtk::Stock::SELECT_COLOR
      ['Block', 'block:m', 'Blocks'],
      ['Box', 'box:m', 'Boxes'],
      ['Event', 'event:m', 'Events'],
      ['-', nil, '-'],
      ['Authorize', :auth, 'Authorize', '<control>U', :check], #Gtk::Stock::DIALOG_AUTHENTICATION
      ['Listen', :listen, 'Listen', '<control>L', :check],  #Gtk::Stock::CONNECT
      ['Hunt', :hunt, 'Hunt', '<control>N', :check],   #Gtk::Stock::REFRESH
      ['Radar', :radar, 'Radar', '<control>R', :check],  #Gtk::Stock::GO_FORWARD
      ['Search', Gtk::Stock::FIND, 'Search', '<control>T'],
      ['>', nil, '_Wizards'],
      ['>Cabinet', Gtk::Stock::HOME, 'Cabinet'],
      ['>Exchange', 'exchange:m', 'Exchange'],
      ['>Session', 'session:m', 'Sessions'],   #Gtk::Stock::JUSTIFY_FILL
      ['>Fisher', 'fish:m', 'Fishers'],
      ['>Wizard', Gtk::Stock::PREFERENCES.to_s+':m', '_Wizards'],
      ['-', nil, '-'],
      ['>', nil, '_Help'],
      ['>Guide', Gtk::Stock::HELP.to_s+':m', 'Guide', 'F1'],
      ['>Readme', ':m', 'README.TXT'],
      ['>DocPath', Gtk::Stock::OPEN.to_s+':m', 'Documentation'],
      ['>About', Gtk::Stock::ABOUT, '_About'],
      ['Close', Gtk::Stock::CLOSE.to_s+':', '_Close', '<control>W'],
      ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q']
      ]

    # Fill main menu
    # RU: Заполнить главное меню
    def fill_menubar(menubar)
      menu = nil
      sub_menu = nil
      MENU_ITEMS.each do |mi|
        command = mi[0]
        if command.nil? or menu.nil? or ((command.size==1) and (command[0]=='>'))
          menuitem = Gtk::MenuItem.new(_(mi[2]))
          if command and menu
            menu.append(menuitem)
            sub_menu = Gtk::Menu.new
            menuitem.set_submenu(sub_menu)
          else
            menubar.append(menuitem)
            menu = Gtk::Menu.new
            menuitem.set_submenu(menu)
            sub_menu = nil
          end
        else
          menuitem = PandoraGtk.create_menu_item(mi)
          if command and (command.size>1) and (command[0]=='>')
            if sub_menu
              sub_menu.append(menuitem)
            else
              menu.append(menuitem)
            end
          else
            menu.append(menuitem)
          end
        end
      end
    end

    # Fill toolbar
    # RU: Заполнить панель инструментов
    def fill_main_toolbar(toolbar)
      MENU_ITEMS.each do |mi|
        stock = mi[1]
        stock, opts = PandoraGtk.detect_icon_opts(stock)
        if stock and opts.index('t')
          command = mi[0]
          if command and (command.size>0) and (command[0]=='>')
            command = command[1..-1]
          end
          label = mi[2]
          if command and (command.size>1) and label and (label != '-')
            toggle = nil
            toggle = false if mi[4]
            btn = PandoraGtk.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
              PandoraUI.do_menu_act(widget)
            end
            btn.name = command
            if (toggle != nil)
              index = nil
              case command
                when 'Authorize'
                  index = PandoraUI::SF_Auth
                when 'Listen'
                  index = PandoraUI::SF_Listen
                when 'Hunt'
                  index = PandoraUI::SF_Hunt
                when 'Radar'
                  index = PandoraUI::SF_Radar
              end
              $toggle_buttons[index] = btn if index
            end
          end
        end
      end
    end

    $pointoff = nil

    def mutex
      @mutex ||= Mutex.new
    end

    # Show main Gtk window
    # RU: Показать главное окно Gtk
    def initialize(*args)
      super(*args)
      $window = self

      main_icon = nil
      begin
        main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      rescue Exception
      end
      if not main_icon
        main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end
      if main_icon
        $window.icon = main_icon
        Gtk::Window.default_icon = $window.icon
      end

      @icon_factory = Gtk::IconFactory.new
      @icon_factory.add_default

      @hand_cursor = Gdk::Cursor.new(Gdk::Cursor::HAND2)
      @regular_cursor = Gdk::Cursor.new(Gdk::Cursor::XTERM)

      @accel_group = Gtk::AccelGroup.new
      $window.add_accel_group(accel_group)

      $window.register_stock(:save)

      @menubar = Gtk::MenuBar.new
      fill_menubar(menubar)
      @menubar.set_size_request(0, -1)

      @toolbar = Gtk::Toolbar.new
      toolbar.show_arrow = true
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      fill_main_toolbar(toolbar)

      #frame = Gtk::Frame.new
      #frame.shadow_type = Gtk::SHADOW_IN
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(frame)
      #image = Gtk::Image.new
      #frame.add(image)

      @notebook = Gtk::Notebook.new
      notebook.show_border = false
      notebook.scrollable = true
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        cur_page = notebook.get_nth_page(page_num)
        if $last_page and (cur_page != $last_page) \
        and ($last_page.is_a? PandoraGtk::CabinetBox)
          if $last_page.area_send and (not $last_page.area_send.destroyed?)
            $last_page.init_video_sender(false, true)
          end
          if $last_page.area_recv and (not $last_page.area_recv.destroyed?)
            $last_page.init_video_receiver(false)
          end
        end
        if cur_page.is_a? PandoraGtk::CabinetBox
          cur_page.update_state(false, cur_page)
          if cur_page.area_recv and (not cur_page.area_recv.destroyed?)
            cur_page.init_video_receiver(true, true, false)
          end
          if cur_page.area_send and (not cur_page.area_send.destroyed?)
            cur_page.init_video_sender(true, true)
          end
        end
        PandoraGtk.update_treeview_if_need(cur_page)
        $last_page = cur_page
      end

      @log_view = PandoraGtk::ExtTextView.new
      log_view.set_readonly(true)
      log_view.border_width = 0

      @log_sw = Gtk::ScrolledWindow.new(nil, nil)
      log_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      log_sw.shadow_type = Gtk::SHADOW_IN
      log_sw.add(log_view)
      log_sw.border_width = 0;
      log_sw.set_size_request(-1, 60)

      @radar_sw = RadarScrollWin.new
      radar_sw.set_size_request(0, -1)

      #note_sw = Gtk::ScrolledWindow.new(nil, nil)
      #note_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #note_sw.border_width = 0
      #@viewport = Gtk::Viewport.new(nil, nil)
      #sw.add(viewport)

      @radar_hpaned = Gtk::HPaned.new
      #note_sw.add_with_viewport(notebook)
      #@radar_hpaned.pack1(note_sw, true, true)
      @radar_hpaned.pack1(notebook, true, true)
      @radar_hpaned.pack2(radar_sw, false, true)
      #@radar_hpaned.position = 1
      #p '****'+@radar_hpaned.allocation.width.inspect
      #@radar_hpaned.position = @radar_hpaned.max_position
      #@radar_hpaned.position = 0
      @radar_hpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_fish_btn_state
      end

      @log_vpaned = Gtk::VPaned.new
      log_vpaned.border_width = 2
      log_vpaned.pack1(radar_hpaned, true, true)
      log_vpaned.pack2(log_sw, false, true)
      log_vpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_log_btn_state
      end

      #@cvpaned = CaptchaHPaned.new(vpaned)
      #@cvpaned.position = cvpaned.max_position

      $statusbar = Gtk::HBox.new
      $statusbar.spacing = 1
      $statusbar.border_width = 0
      #$statusbar = Gtk::Statusbar.new
      #PandoraGtk.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

      add_status_field(PandoraUI::SF_Log, nil, 'Logbar', :log, false, 0) do
        PandoraUI.do_menu_act('LogBar')
      end
      add_status_field(PandoraUI::SF_FullScr, nil, 'Full screen', \
      Gtk::Stock::FULLSCREEN, false, 0) do
        PandoraUI.do_menu_act('FullScr')
      end

      path = $pandora_app_dir
      path = '..'+path[-40..-1] if path.size>40
      pathlabel = Gtk::Label.new(path)
      pathlabel.modify_font(PandoraGtk.status_font)
      pathlabel.justify = Gtk::JUSTIFY_LEFT
      pathlabel.set_padding(1, 1)
      pathlabel.set_alignment(0.0, 0.5)
      $statusbar.pack_start(pathlabel, true, true, 0)

      add_status_field(PandoraUI::SF_Update, _('Version') + ': ' + _('Not checked'), 'Update') do
        PandoraUI.start_updating(true)
      end
      add_status_field(PandoraUI::SF_Lang, $lang, 'Language') do
        PandoraUI.do_menu_act('LangEdit')
      end
      add_status_field(PandoraUI::SF_Auth, _('Not logged'), 'Authorize', :auth, false) do
        PandoraUI.do_menu_act('Authorize')          #Gtk::Stock::DIALOG_AUTHENTICATION
      end
      add_status_field(PandoraUI::SF_Listen, '0', 'Listen', :listen, false) do
        PandoraUI.do_menu_act('Listen')
      end
      add_status_field(PandoraUI::SF_Hunt, '0', 'Hunting', :hunt, false) do
        PandoraUI.do_menu_act('Hunt')
      end
      add_status_field(PandoraUI::SF_Fisher, '0', 'Fishers', :fish) do
        PandoraUI.do_menu_act('Fisher')
      end
      add_status_field(PandoraUI::SF_Conn, '0', 'Sessions', :session) do
        PandoraUI.do_menu_act('Session')
      end
      add_status_field(PandoraUI::SF_Radar, '0', 'Radar', :radar, false) do
        PandoraUI.do_menu_act('Radar')
      end
      add_status_field(PandoraUI::SF_Harvest, '0', 'Files', :blob) do
        PandoraUI.do_menu_act('Blob')
      end
      add_status_field(PandoraUI::SF_Search, '0', 'Search', Gtk::Stock::FIND) do
        PandoraUI.do_menu_act('Search')
      end
      resize_eb = Gtk::EventBox.new
      resize_eb.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK
      resize_eb.signal_connect('enter-notify-event') do |widget, param|
        window = widget.window
        window.cursor = Gdk::Cursor.new(Gdk::Cursor::BOTTOM_RIGHT_CORNER)
      end
      resize_eb.signal_connect('leave-notify-event') do |widget, param|
        window = widget.window
        window.cursor = nil #Gdk::Cursor.new(Gdk::Cursor::XTERM)
      end
      resize_eb.signal_connect('button-press-event') do |widget, event|
        if (event.button == 1)
          point = $window.window.pointer[1,2]
          wh = $window.window.geometry[2,2]
          $pointoff = [(wh[0]-point[0]), (wh[1]-point[1])]
          if $window.window.state == Gdk::EventWindowState::MAXIMIZED
            wbord = 6
            w, h = [(point[0]+$pointoff[0]-wbord), (point[1]+$pointoff[1]-wbord)]
            $window.move(0, 0)
            $window.set_default_size(w, h)
            $window.resize(w, h)
            $window.unmaximize
            $window.move(0, 0)
            $window.set_default_size(w, h)
            $window.resize(w, h)
          end
        end
        false
      end
      resize_eb.signal_connect('motion-notify-event') do |widget, event|
        if $pointoff
          point = $window.window.pointer[1,2]
          wid = point[0]+$pointoff[0]
          hei = point[1]+$pointoff[1]
          wid = 16 if wid<16
          hei = 16 if hei<16
          $window.resize(wid, hei)
        end
        false
      end
      resize_eb.signal_connect('button-release-event') do |widget, event|
        if (event.button == 1) and $pointoff
          window = widget.window
          $pointoff = nil
        end
        false
      end
      $window.register_stock(:resize)
      resize_image = Gtk::Image.new(:resize, Gtk::IconSize::MENU)
      resize_image.set_padding(0, 0)
      resize_image.set_alignment(1.0, 1.0)
      resize_eb.add(resize_image)
      $statusbar.pack_start(resize_eb, false, false, 0)

      vbox = Gtk::VBox.new
      vbox.pack_start(menubar, false, false, 0)
      vbox.pack_start(toolbar, false, false, 0)
      #vbox.pack_start(cvpaned, true, true, 0)
      vbox.pack_start(log_vpaned, true, true, 0)

      $statusbar.set_size_request(0, -1)
      vbox.pack_start($statusbar, false, false, 0)

      $window.add(vbox)

      update_win_icon = PandoraUtils.get_param('status_update_win_icon')
      flash_on_new = PandoraUtils.get_param('status_flash_on_new')
      flash_interval = PandoraUtils.get_param('status_flash_interval')
      hide_on_minimize = PandoraUtils.get_param('hide_on_minimize')
      hide_on_close = PandoraUtils.get_param('hide_on_close')
      mplayer = nil
      if PandoraUtils.os_family=='windows'
        mplayer = PandoraUtils.get_param('win_mp3_player')
      else
        mplayer = PandoraUtils.get_param('linux_mp3_player')
      end
      $mp3_player = mplayer if ((mplayer.is_a? String) and (mplayer.size>0))

      $statusicon = PandoraGtk::PandoraStatusIcon.new(update_win_icon, flash_on_new, \
        flash_interval, PandoraUI.play_sounds, hide_on_minimize)

      $window.signal_connect('delete-event') do |*args|
        if hide_on_close
          PandoraUI.do_menu_act('Hide')
        else
          PandoraUI.do_menu_act('Quit')
        end
        true
      end

      $window.signal_connect('destroy') do |window|
        while (not $window.notebook.destroyed?) and ($window.notebook.children.count>0)
          $window.notebook.children[0].destroy if (not $window.notebook.children[0].destroyed?)
        end
        PandoraCrypto.reset_current_key
        $statusicon.visible = false if ($statusicon and (not $statusicon.destroyed?))
        $window = nil
        Gtk.main_quit
      end

      $window.signal_connect('key-press-event') do |widget, event|
        res = true
        if ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) \
        and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, \
        1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
          PandoraUI.do_menu_act('Quit')
        elsif event.keyval == Gdk::Keyval::GDK_F5
          PandoraUI.do_menu_act('Hunt')
        elsif event.state.shift_mask? \
        and (event.keyval == Gdk::Keyval::GDK_F11)
          PandoraGtk.full_screen_switch
        elsif event.state.control_mask?
          if [Gdk::Keyval::GDK_m, Gdk::Keyval::GDK_M, 1752, 1784].include?(event.keyval)
            $window.hide
          elsif ((Gdk::Keyval::GDK_0..Gdk::Keyval::GDK_9).include?(event.keyval) \
          or (event.keyval==Gdk::Keyval::GDK_Tab))
            num = $window.notebook.n_pages
            if num>0
              if (event.keyval==Gdk::Keyval::GDK_Tab)
                n = $window.notebook.page
                if n>=0
                  if event.state.shift_mask?
                    n -= 1
                  else
                    n += 1
                  end
                  if n<0
                    $window.notebook.page = num-1
                  elsif n>=num
                    $window.notebook.page = 0
                  else
                    $window.notebook.page = n
                  end
                end
              else
                n = (event.keyval - Gdk::Keyval::GDK_1)
                if (n>=0) and (n<num)
                  $window.notebook.page = n
                else
                  $window.notebook.page = num-1
                end
              end
            end
          elsif [Gdk::Keyval::GDK_n, Gdk::Keyval::GDK_N].include?(event.keyval)
            continue = (not event.state.shift_mask?)
            PandoraNet.start_or_stop_hunt(continue)
          elsif [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval)
            PandoraUI.do_menu_act('Close')
          elsif [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
            curpage = nil
            if $window.notebook.n_pages>0
              curpage = $window.notebook.get_nth_page($window.notebook.page)
            end
            if curpage.is_a? PandoraGtk::PanobjScrolledWindow
              res = false
            else
              res = PandoraGtk.show_panobject_list(PandoraModel::Person)
              res = (res != nil)
            end
          else
            res = false
          end
        else
          res = false
        end
        res
      end

      #$window.signal_connect('client-event') do |widget, event_client|
      #  p '[widget, event_client]='+[widget, event_client].inspect
      #end

      $window.signal_connect('window-state-event') do |widget, event_window_state|
        if (event_window_state.changed_mask == Gdk::EventWindowState::ICONIFIED) \
          and ((event_window_state.new_window_state & Gdk::EventWindowState::ICONIFIED)>0)
        then
          if notebook.page >= 0
            sw = notebook.get_nth_page(notebook.page)
            if (sw.is_a? CabinetBox) and (not sw.destroyed?)
              sw.init_video_sender(false, true) if sw.area_send and (not sw.area_send.destroyed?)
              sw.init_video_receiver(false) if sw.area_recv and (not sw.area_recv.destroyed?)
            end
          end
          if widget.visible? and widget.active? and $statusicon.hide_on_minimize
            $window.hide
            #$window.skip_taskbar_hint = true
          end
        end
      end

      PandoraGtk.get_main_params

      scr = Gdk::Screen.default
      $window.set_default_size(scr.width-100, scr.height-100)
      $window.window_position = Gtk::Window::POS_CENTER

      $window.maximize
      $window.show_all if (not $hide_on_start)

      @radar_hpaned.position = @radar_hpaned.max_position
      @log_vpaned.position = @log_vpaned.max_position

      #------next must be after show main form ---->>>>

      $window.focus_timer = $window
      $window.signal_connect('focus-in-event') do |window, event|
        #p 'focus-in-event: ' + [$window.has_toplevel_focus?, \
        #  event, $window.visible?].inspect
        if $window.focus_timer
          $window.focus_timer = nil if ($window.focus_timer == $window)
        else
          if (PandoraUtils.os_family=='windows') and (not $window.visible?)
            PandoraUI.do_menu_act('Activate')
          end
          $window.focus_timer = GLib::Timeout.add(500) do
            if (not $window.nil?) and (not $window.destroyed?)
              #p 'read timer!!!' + $window.has_toplevel_focus?.inspect
              toplevel = ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
              if toplevel and $window.visible?
                $window.notebook.children.each do |child|
                  if (child.is_a? CabinetBox) and (child.has_unread)
                    #$window.notebook.page = $window.notebook.children.index(child)
                    break
                  end
                end
                curpage = $window.notebook.get_nth_page($window.notebook.page)
                if curpage.is_a?(PandoraGtk::CabinetBox) and toplevel
                  curpage.update_state(false, curpage)
                else
                  PandoraGtk.update_treeview_if_need(curpage)
                end
              end
              $window.focus_timer = nil
            end
            false
          end
        end
        false
      end
    end

  end  #--MainWindow

  def self.do_main_loop
    PandoraGtk::MainWindow.new(MAIN_WINDOW_TITLE)
    yield if block_given?
    Gtk.main
  end

end


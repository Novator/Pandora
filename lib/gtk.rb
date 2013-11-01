#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк


require 'fileutils'

require File.expand_path('../crypto.rb',  __FILE__)
require File.expand_path('../net.rb',  __FILE__)

module PandoraGtk
  # GTK is cross platform graphical user interface
  # RU: Кроссплатформенный оконный интерфейс
  begin
    require 'gtk2'
    Gtk.init
  rescue Exception
    Kernel.abort("Gtk is not installed.\nInstall packet 'ruby-gtk'")
  end

  include PandoraUtils
  include PandoraModel

  SF_Update = 0
  SF_Auth   = 1
  SF_Listen = 2
  SF_Hunt   = 3
  SF_Conn   = 4

  # About dialog hooks
  # RU: Обработчики диалога "О программе"
  Gtk::AboutDialog.set_url_hook do |about, link|
    if PandoraUtils.os_family=='windows' then a1='start'; a2='' else a1='xdg-open'; a2=' &' end;
    system(a1+' '+link+a2)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    if PandoraUtils.os_family=='windows' then a1='start'; a2='' else a1='xdg-email'; a2=' &' end;
    system(a1+' '+link+a2)
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.version = '0.2'
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.authors = [_('Michael Galyuk')+' <robux@mail.ru>']
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('Distributed Social Network')
    dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
    begin
      file = File.open(File.join($pandora_root_dir, 'LICENSE.TXT'), 'r')
      gpl_text = '================='+_('Full text')+" LICENSE.TXT==================\n"+file.read
      file.close
    rescue
      gpl_text = _('Full text is in the file')+' LICENSE.TXT.'
    end
    dlg.license = _("Pandora is licensed under GNU GPLv2.\n"+
      "\nFundamentals:\n"+
      "- program code is open, distributed free and without warranty;\n"+
      "- author does not require you money, but demands respect authorship;\n"+
      "- you can change the code, sent to the authors for inclusion in the next release;\n"+
      "- your own release you must distribute with another name and only licensed under GPL;\n"+
      "- if you do not understand the GPL or disagree with it, you have to uninstall the program.\n\n")+gpl_text
    dlg.website = 'https://github.com/Novator/Pandora'
    dlg.program_name = dlg.name
    dlg.skip_taskbar_hint = true
    dlg.run
    dlg.destroy
    $window.present
  end

  def self.set_statusbar_text(statusbar, text)
    statusbar.pop(0)
    statusbar.push(0, text)
  end

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window
    attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, :enter_like_tab, :enter_like_ok, \
      :panelbox, :okbutton, :cancelbutton, :def_widget, :main_sw

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

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      window.add(vpaned)

      @main_sw = Gtk::ScrolledWindow.new(nil, nil)
      sw = main_sw
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      @viewport = Gtk::Viewport.new(nil, nil)
      sw.add(viewport)

      image = Gtk::Image.new(Gtk::Stock::PROPERTIES, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box1 = TabLabelBox.new(image, _('Basic'), nil, false, 0)

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
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
      okbutton.signal_connect('clicked') { |*args| @response=2 }
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') { |*args| @response=1 }
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

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
          okbutton.activate
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          cancelbutton.activate
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
          ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
        then
          $window.destroy
          @response=1
          false
        else
          false
        end
      end
    end

    # show dialog until key pressed
    def run(alien_thread=false)
      res = false
      show_all
      if @def_widget
        #focus = @def_widget
        @def_widget.grab_focus
      end
      while (not destroyed?) and (@response == 0) do
        unless alien_thread
          Gtk.main_iteration
        end
        Thread.pass
      end
      if not destroyed?
        if (@response > 1)
          yield(@response) if block_given?
          res = true
        end
        self.destroy
      end
      res
    end
  end

  # ToggleToolButton with safety "active" switching
  # ToggleToolButton с безопасным переключением "active"
  class GoodToggleToolButton < Gtk::ToggleToolButton
    def good_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end
    def good_set_active(an_active)
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
  # CheckButton с безопасным переключением "active"
  class GoodCheckButton < Gtk::CheckButton
    def good_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end
    def good_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock, title, toggle=nil)
    btn = nil
    if toggle != nil
      btn = GoodToggleToolButton.new(stock)
      btn.good_signal_clicked do |*args|
        yield(*args) if block_given?
      end
      btn.active = toggle if toggle
    else
      image = Gtk::Image.new(stock, Gtk::IconSize::MENU)
      btn = Gtk::ToolButton.new(image, _(title))
      #btn = Gtk::ToolButton.new(stock)
      btn.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
      btn.label = title
    end
    toolbar.add(btn)
    title = _(title)
    title.gsub!('_', '')
    btn.tooltip_text = title
    btn.label = title
    btn
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

  class IntegerEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789-'
      self.max_length = 20
    end
  end

  class FloatEntry < IntegerEntry
    def init_mask
      super
      @mask += '.e'
      self.max_length = 35
    end
  end

  class HexEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789abcdefABCDEF'
    end
  end

  Base64chars = [*('0'..'9'), *('a'..'z'), *('A'..'Z'), '+/=-_*[]'].join

  class Base64Entry < MaskEntry
    def init_mask
      super
      @mask = Base64chars
    end
  end

  class DateEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789.'
      self.max_length = 10
      self.tooltip_text = 'MM.DD.YYYY'
    end
  end

  class TimeEntry < DateEntry
    def init_mask
      super
      @mask += ' :'
      self.max_length = 19
      self.tooltip_text = 'MM.DD.YYYY hh:mm:ss'
    end
  end

  MaxPanhashTabs = 5

  class PanhashBox < Gtk::HBox
    attr_accessor :types, :panclasses, :entry, :button
    def initialize(panhash_type, *args)
      super(*args)
      @types = panhash_type
      @entry = HexEntry.new
      @button = Gtk::Button.new('...')
      @entry.instance_variable_set('@button', @button)
      def @entry.key_event(widget, event)
        res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
          and (event.keyval==65364)))
        @button.activate if res
        false
      end
      self.pack_start(entry, true, true, 0)
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
      align.add(@button)
      self.pack_start(align, false, false, 1)
      esize = entry.size_request
      h = esize[1]-2
      @button.set_size_request(h, h)

      #if panclasses==[]
      #  panclasses = $panobject_list
      #end

      button.signal_connect('clicked') do |*args|
        set_classes
        dialog = PandoraGtk::AdvancedDialog.new(_('Choose object'))
        dialog.set_default_size(600, 400)
        auto_create = true
        panclasses.each_with_index do |panclass, i|
          title = _(PandoraUtils.get_name_or_names(panclass.name, true))
          dialog.main_sw.destroy if i==0
          image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          label_box2 = TabLabelBox.new(image, title, nil, false, 0)
          sw = Gtk::ScrolledWindow.new(nil, nil)
          page = dialog.notebook.append_page(sw, label_box2)
          auto_create = PandoraGtk.show_panobject_list(panclass, nil, sw, auto_create)
          if panclasses.size>MaxPanhashTabs
            break
          end
        end
        dialog.notebook.page = 0
        dialog.run do
          panhash = nil
          sw = dialog.notebook.get_nth_page(dialog.notebook.page)
          treeview = sw.children[0]
          if treeview.is_a? SubjTreeView
            path, column = treeview.cursor
            panobject = treeview.panobject
            if path and panobject
              store = treeview.model
              iter = store.get_iter(path)
              id = iter[0]
              sel = panobject.select('id='+id.to_s, false, 'panhash')
              panhash = sel[0][0] if sel and (sel.size>0)
            end
          end
          if PandoraUtils.panhash_nil?(panhash)
            @entry.text = ''
          else
            @entry.text = PandoraUtils.bytes_to_hex(panhash) if (panhash.is_a? String)
          end
        end
        #yield if block_given?
      end
    end
    def set_classes
      if not panclasses
        #p '=== types='+types.inspect
        @panclasses = []
        @types.strip!
        if (types.is_a? String) and (types.size>0) and (@types[0, 8].downcase=='panhash(')
          @types = @types[8..-2]
          @types.strip!
          @types = @types.split(',')
          @types.each do |ptype|
            ptype.strip!
            if PandoraModel.const_defined? ptype
              panclasses << PandoraModel.const_get(ptype)
            end
          end
        end
        #p 'panclasses='+panclasses.inspect
      end
    end
    def max_length=(maxlen)
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

  class CoordEntry < FloatEntry
    def init_mask
      super
      @mask += 'EsNn SwW\'"`′″,'
      self.max_length = 35
    end
  end

  class CoordBox < Gtk::HBox
    attr_accessor :latitude, :longitude
    CoordWidth = 120
    def initialize
      super
      @latitude   = CoordEntry.new
      latitude.tooltip_text = _('Latitude')+': 60.716, 60 43\', 60.43\'00"N'+"\n["+latitude.mask+']'
      @longitude  = CoordEntry.new
      longitude.tooltip_text = _('Longitude')+': -114.9, W114 54\' 0", 114.9W'+"\n["+longitude.mask+']'
      latitude.width_request = CoordWidth
      longitude.width_request = CoordWidth
      self.pack_start(latitude, false, false, 0)
      self.pack_start(longitude, false, false, 1)
    end
    def max_length=(maxlen)
      ml = maxlen / 2
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
        coord = PandoraUtils.int_to_coord(i)
      else
        coord = ['', '']
      end
      latitude.text = coord[0].to_s
      longitude.text = coord[1].to_s
    end
    def text
      res = PandoraUtils.coord_to_int(latitude.text, longitude.text).to_s
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

  MaxOnePlaceViewSec = 60

  def self.set_readonly(widget, value=true, sensitive=true)
    value = (not value)
    widget.editable = value if widget.class.method_defined? 'editable?'
    widget.sensitive = value if sensitive and (widget.class.method_defined? 'sensitive?')
    #widget.can_focus = value
    widget.has_focus = value if widget.class.method_defined? 'has_focus?'
  end

  class ExtTextView < Gtk::TextView
    attr_accessor :need_to_end, :middle_time, :middle_value

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
    end

    def set_readonly(value=true)
      PandoraGtk.set_readonly(self, value, false)
    end

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

    def after_addition(go_to_end=nil)
      go_to_end ||= @need_to_end
      if go_to_end
        adj = self.parent.vadjustment
        adj.value = adj.upper
        adj.value_changed       # bug: not scroll to end
        adj.value = adj.upper   # if add many lines
      end
      go_to_end
    end
  end

  # Tree of panobjects
  # RU: Дерево субъектов
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject, :sel, :notebook, :auto_create
  end

  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
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
      if mi[1]
        menuitem = Gtk::ImageMenuItem.new(mi[1])
        label = menuitem.children[0]
        label.set_text(text, true)
      else
        menuitem = Gtk::MenuItem.new(text)
      end
      #if mi[3]
      if (not treeview) and mi[3]
        key, mod = Gtk::Accelerator.parse(mi[3])
        menuitem.add_accelerator('activate', $group, key, mod, Gtk::ACCEL_VISIBLE) if key
      end
      menuitem.name = mi[0]
      menuitem.signal_connect('activate') { |widget| $window.do_menu_act(widget, treeview) }
    end
    menuitem
  end

  class PanobjScrollWin < Gtk::ScrolledWindow
  end

  # Showing panobject list
  # RU: Показ списка субъектов
  def self.show_panobject_list(panobject_class, widget=nil, sw=nil, auto_create=false)
    notebook = $window.notebook
    single = (sw == nil)
    if single
      notebook.children.each do |child|
        if (child.is_a? PanobjScrollWin) and (child.name==panobject_class.ider)
          notebook.page = notebook.children.index(child)
          return nil
        end
      end
    end
    panobject = panobject_class.new
    sel = panobject.select(nil, false, nil, panobject.sort)
    store = Gtk::ListStore.new(Integer)
    param_view_col = nil
    param_view_col = sel[0].size if (panobject.ider=='Parameter') and sel[0]
    sel.each do |row|
      iter = store.append
      id = row[0].to_i
      iter[0] = id
      if param_view_col
        type = panobject.field_val('type', row)
        setting = panobject.field_val('setting', row)
        ps = PandoraUtils.decode_param_setting(setting)
        view = ps['view']
        view ||= PandoraUtils.pantype_to_view(type)
        row[param_view_col] = view
      end
    end
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject
    treeview.sel = sel

    tab_flds = panobject.tab_fields
    def_flds = panobject.def_fields
    def_flds.each do |df|
      id = df[FI_Id]
      tab_ind = tab_flds.index{ |tf| tf[0] == id }
      if tab_ind
        renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

        title = df[FI_VFName]
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
          color = 'black'
          col = tvc.tab_ind
          panobject = tvc.tree_view.panobject
          row = tvc.tree_view.sel[iter.path.indices[0]]
          val = row[col] if row
          if val
            fdesc = panobject.tab_fields[col][TI_Desc]
            if fdesc.is_a? Array
              view = nil
              if param_view_col and (fdesc[FI_Id]=='value')
                view = row[param_view_col] if row
              else
                view = fdesc[FI_View]
              end
              val, color = PandoraUtils.val_to_view(val, nil, view, false)
            else
              val = val.to_s
            end
            val = val[0,45]
          else
            val = ''
          end
          renderer.foreground = color
          renderer.text = val
        end
      end
    end
    treeview.signal_connect('row_activated') do |tree_view, path, column|
      if single
        act_panobject(tree_view, 'Edit')
      else
        dialog = sw.parent.parent.parent
        dialog.okbutton.activate
      end
    end

    sw ||= PanobjScrollWin.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.name = panobject.ider
    sw.add(treeview)
    sw.border_width = 0

    if auto_create and sel and (sel.size==0)
      treeview.auto_create = true
      treeview.signal_connect('map') do |widget, event|
        if treeview.auto_create
          act_panobject(treeview, 'Create')
          treeview.auto_create = false
        end
      end
      auto_create = false
    end

    if single
      p 'single: widget='+widget.inspect
      if widget.is_a? Gtk::ImageMenuItem
        animage = widget.image
      elsif widget.is_a? Gtk::ToolButton
        animage = widget.icon_widget
      else
        animage = nil
      end
      image = nil
      if animage
        image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
        image.set_padding(2, 0)
      end

      label_box = TabLabelBox.new(image, panobject.pname, sw, false, 0) do
        store.clear
        treeview.destroy
      end

      page = notebook.append_page(sw, label_box)
      sw.show_all
      notebook.page = notebook.n_pages-1

      if treeview.sel.size>0
        treeview.set_cursor(Gtk::TreePath.new(treeview.sel.size-1), nil, false)
      end
      treeview.grab_focus
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::NEW, _('Create'), 'Insert'], treeview))
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT, _('Edit'), 'Return'], treeview))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete'], treeview))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Dialog', Gtk::Stock::MEDIA_PLAY, _('Dialog'), '<control>D'], treeview))
    menu.append(create_menu_item(['Opinion', Gtk::Stock::JUMP_TO, _('Opinions'), '<control>BackSpace'], treeview))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N'], treeview))
    menu.append(create_menu_item(['Relate', Gtk::Stock::INDEX, _('Relate'), '<control>R'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Clone', Gtk::Stock::CONVERT, _('Recreate the table')], treeview))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button_press_event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

    treeview.signal_connect('key-press-event') do |widget, event|
      res = true
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
        act_panobject(treeview, 'Edit')
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

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    include PandoraUtils

    attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
      :support_btn, :vouch_btn, :trust_scale, :trust0, :public_btn, :lang_entry, :format, :view_buffer

    def add_menu_item(label, menu, text)
      mi = Gtk::MenuItem.new(text)
      menu.append(mi)
      mi.signal_connect('activate') { |mi|
        label.label = mi.label
        @format = mi.label.to_s
        p 'format changed to: '+format.to_s
      }
    end

    def set_view_buffer(format, view_buffer, raw_buffer)
      view_buffer.text = raw_buffer.text
    end

    def set_raw_buffer(format, raw_buffer, view_buffer)
      raw_buffer.text = view_buffer.text
    end

    def set_buffers(init=false)
      child = notebook.get_nth_page(notebook.page)
      if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
        tv = child.children[0]
        if init or not @raw_buffer
          @raw_buffer = tv.buffer
        end
        if @view_mode
          tv.buffer = @view_buffer if tv.buffer != @view_buffer
        elsif tv.buffer != @raw_buffer
          tv.buffer = @raw_buffer
        end

        if @view_mode
          set_view_buffer(format, @view_buffer, @raw_buffer)
        else
          set_raw_buffer(format, @raw_buffer, @view_buffer)
        end
      end
    end

    def set_tag(tag)
      if tag
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
          tv = child.children[0]
          buffer = tv.buffer

          if @view_buffer==buffer
            bounds = buffer.selection_bounds
            @view_buffer.apply_tag(tag, bounds[0], bounds[1])
          else
            bounds = buffer.selection_bounds
            ltext = rtext = ''
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
            lpos = bounds[0].offset
            rpos = bounds[1].offset
            if ltext != ''
              @raw_buffer.insert(@raw_buffer.get_iter_at_offset(lpos), ltext)
              lpos += ltext.length
              rpos += ltext.length
            end
            if rtext != ''
              @raw_buffer.insert(@raw_buffer.get_iter_at_offset(rpos), rtext)
            end
            p [lpos, rpos]
            #buffer.selection_bounds = [bounds[0], rpos]
            @raw_buffer.move_mark('selection_bound', @raw_buffer.get_iter_at_offset(lpos))
            @raw_buffer.move_mark('insert', @raw_buffer.get_iter_at_offset(rpos))
            #@raw_buffer.get_iter_at_offset(0)
          end
        end
      end
    end

    def initialize(apanobject, afields=[], *args)
      super(*args)
      @panobject = apanobject
      @fields = afields

      window.signal_connect('configure-event') do |widget, event|
        window.on_resize_window(widget, event)
        false
      end

      @toolbar = Gtk::Toolbar.new
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      panelbox.pack_start(toolbar, false, false, 0)

      @toolbar2 = Gtk::Toolbar.new
      toolbar2.toolbar_style = Gtk::Toolbar::Style::ICONS
      panelbox.pack_start(toolbar2, false, false, 0)

      @raw_buffer = nil
      @view_mode = true
      @view_buffer = Gtk::TextBuffer.new
      @view_buffer.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      @view_buffer.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
      @view_buffer.create_tag('strike', 'strikethrough' => true)
      @view_buffer.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
      @view_buffer.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
      @view_buffer.create_tag('link', {'foreground' => 'blue', 'underline' => Pango::AttrUnderline::SINGLE})
      @view_buffer.create_tag('linked', {'foreground' => 'navy', 'underline' => Pango::AttrUnderline::SINGLE})
      @view_buffer.create_tag('left', 'justification' => Gtk::JUSTIFY_LEFT)
      @view_buffer.create_tag('center', 'justification' => Gtk::JUSTIFY_CENTER)
      @view_buffer.create_tag('right', 'justification' => Gtk::JUSTIFY_RIGHT)
      @view_buffer.create_tag('fill', 'justification' => Gtk::JUSTIFY_FILL)

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::DND, 'Type', true) do |btn|
        @view_mode = btn.active?
        set_buffers
      end

      btn = Gtk::MenuToolButton.new(nil, 'auto')
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, 'auto')
      add_menu_item(btn, menu, 'plain')
      add_menu_item(btn, menu, 'org-mode')
      add_menu_item(btn, menu, 'bbcode')
      add_menu_item(btn, menu, 'wiki')
      add_menu_item(btn, menu, 'html')
      add_menu_item(btn, menu, 'ruby')
      add_menu_item(btn, menu, 'python')
      add_menu_item(btn, menu, 'xml')
      menu.show_all
      toolbar.add(btn)

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::BOLD, 'Bold') do |*args|
        set_tag('bold')
      end

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::ITALIC, 'Italic') do |*args|
        set_tag('italic')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::STRIKETHROUGH, 'Strike') do |*args|
        set_tag('strike')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDERLINE, 'Underline') do |*args|
        set_tag('undline')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDO, 'Undo')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::REDO, 'Redo')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::COPY, 'Copy')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::CUT, 'Cut')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::FIND, 'Find')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_LEFT, 'Left') do |*args|
        set_tag('left')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_RIGHT, 'Right') do |*args|
        set_tag('right')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, 'Center') do |*args|
        set_tag('center')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_FILL, 'Fill') do |*args|
        set_tag('fill')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SAVE, 'Save')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OPEN, 'Open')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link') do |*args|
        set_tag('link')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::HOME, 'Image')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::ADD, 'Add')
      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::DELETE, 'Delete')
      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

      notebook.signal_connect('switch-page') do |widget, page, page_num|
        if page_num==0
          toolbar.hide
          toolbar2.hide
          hbox.show
        else
          child = notebook.get_nth_page(page_num)
          if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
            toolbar2.hide
            hbox.hide
            toolbar.show
            set_buffers(true)
          else
            toolbar.hide
            hbox.hide
           toolbar2.show
          end
        end
      end

      @vbox = Gtk::VBox.new
      viewport.add(@vbox)

      @statusbar = Gtk::Statusbar.new
      PandoraGtk.set_statusbar_text(statusbar, '')
      statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      panhash_btn = Gtk::Button.new(_('Panhash'))
      panhash_btn.relief = Gtk::RELIEF_NONE
      statusbar.pack_start(panhash_btn, false, false, 0)

      panelbox.pack_start(statusbar, false, false, 0)


      #rbvbox = Gtk::VBox.new

      @support_btn = Gtk::CheckButton.new(_('support'), true)
      #support_btn.signal_connect('toggled') do |widget|
      #  p "support"
      #end
      #rbvbox.pack_start(support_btn, false, false, 0)
      hbox.pack_start(support_btn, false, false, 0)

      trust_box = Gtk::VBox.new

      trust0 = nil
      @trust_scale = nil
      @vouch_btn = Gtk::CheckButton.new(_('vouch'), true)
      vouch_btn.signal_connect('clicked') do |widget|
        if not widget.destroyed?
          if widget.inconsistent?
            if PandoraCrypto.current_user_or_key(false)
              widget.inconsistent = false
              widget.active = true
              trust0 = 0.1
            end
          end
          trust_scale.sensitive = widget.active?
          if widget.active?
            trust0 ||= 0.1
            trust_scale.value = trust0
          else
            trust0 = trust_scale.value
          end
        end
      end
      trust_box.pack_start(vouch_btn, false, false, 0)

      #@scale_button = Gtk::ScaleButton.new(Gtk::IconSize::BUTTON)
      #@scale_button.set_icons(['gtk-goto-bottom', 'gtk-goto-top', 'gtk-execute'])
      #@scale_button.signal_connect('value-changed') { |widget, value| puts "value changed: #{value}" }

      tips = [_('evil'), _('destructive'), _('dirty'), _('harmful'), _('bad'), _('vain'), \
        _('good'), _('useful'), _('constructive'), _('creative'), _('genial')]

      #@trust ||= (127*0.4).round
      #val = trust/127.0
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      @trust_scale = Gtk::HScale.new(adjustment)
      trust_scale.set_size_request(140, -1)
      trust_scale.update_policy = Gtk::UPDATE_DELAYED
      trust_scale.digits = 1
      trust_scale.draw_value = true
      step = 254.fdiv(tips.size-1)
      trust_scale.signal_connect('value-changed') do |widget|
        #val = (widget.value*20).round/20.0
        val = widget.value
        #widget.value = val #if (val-widget.value).abs>0.05
        trust = (val*127).round
        #vouch_lab.text = sprintf('%2.1f', val) #trust.fdiv(127))
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
        tip = val.to_s
        color = Gdk::Color.new(r, g, b)
        widget.modify_fg(Gtk::STATE_NORMAL, color)
        @vouch_btn.modify_bg(Gtk::STATE_ACTIVE, color)
        i = ((trust+127)/step).round
        tip = tips[i]
        widget.tooltip_text = tip
      end
      #scale.signal_connect('change-value') do |widget|
      #  true
      #end
      trust_box.pack_start(trust_scale, false, false, 0)

      hbox.pack_start(trust_box, false, false, 0)

      public_box = Gtk::VBox.new

      @public_btn = Gtk::CheckButton.new(_('public'), true)
      public_btn.signal_connect('clicked') do |widget|
        if not widget.destroyed?
          if widget.inconsistent?
            if PandoraCrypto.current_user_or_key(false)
              widget.inconsistent = false
              widget.active = true
            end
          end
        end
      end
      public_box.pack_start(public_btn, false, false, 0)

      #@lang_entry = Gtk::ComboBoxEntry.new(true)
      #lang_entry.set_size_request(60, 15)
      #lang_entry.append_text('0')
      #lang_entry.append_text('1')
      #lang_entry.append_text('5')

      @lang_entry = Gtk::Combo.new
      @lang_entry.set_popdown_strings(['0','1','5'])
      @lang_entry.entry.text = ''
      @lang_entry.entry.select_region(0, -1)
      @lang_entry.set_size_request(50, -1)
      public_box.pack_start(lang_entry, true, true, 5)

      hbox.pack_start(public_box, false, false, 0)

      #hbox.pack_start(rbvbox, false, false, 1.0)
      hbox.show_all

      bw,bh = hbox.size_request
      @btn_panel_height = bh

      # devide text fields in separate list
      @text_fields = Array.new
      i = @fields.size
      while i>0 do
        i -= 1
        field = @fields[i]
        atext = field[FI_VFName]
        atype = field[FI_Type]
        if atype=='Text'
          image = Gtk::Image.new(Gtk::Stock::DND, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          textview = Gtk::TextView.new
          textview.wrap_mode = Gtk::TextTag::WRAP_WORD

          textview.signal_connect('key-press-event') do |widget, event|
            if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
              and event.state.control_mask?
            then
              true
            end
          end

          textsw = Gtk::ScrolledWindow.new(nil, nil)
          textsw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          textsw.add(textview)

          label_box = TabLabelBox.new(image, atext, nil, false, 0)
          page = notebook.append_page(textsw, label_box)

          textview.buffer.text = field[FI_Value].to_s
          field[FI_Widget] = textview

          txt_fld = field
          txt_fld << page
          @text_fields << txt_fld  #15??
          #@enter_like_ok = false

          @fields.delete_at(i)
        end
      end

      image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Relations'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGtk.show_panobject_list(PandoraModel::Relation, nil, sw)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_AUTHENTICATION, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Signs'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGtk.show_panobject_list(PandoraModel::Sign, nil, sw)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_INFO, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Opinions'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGtk.show_panobject_list(PandoraModel::Opinion, nil, sw)

      # create labels, remember them, calc middle char width
      texts_width = 0
      texts_chars = 0
      labels_width = 0
      max_label_height = 0
      @fields.each do |field|
        atext = field[FI_VFName]
        aview = field[FI_View]
        label = Gtk::Label.new(atext)
        label.tooltip_text = aview if aview and (aview.size>0)
        label.xalign = 0.0
        lw,lh = label.size_request
        field[FI_Label] = label
        field[FI_LabW] = lw
        field[FI_LabH] = lh
        texts_width += lw
        texts_chars += atext.length
        #texts_chars += atext.length
        labels_width += lw
        max_label_height = lh if max_label_height < lh
      end
      @middle_char_width = (texts_width.to_f*1.2 / texts_chars).round

      # max window size
      scr = Gdk::Screen.default
      window_width, window_height = [scr.width-50, scr.height-100]
      form_width = window_width-36
      form_height = window_height-@btn_panel_height-55

      # compose first matrix, calc its geometry
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @def_widget = nil
      @fields.each do |field|
        #p 'field='+field.inspect
        max_size = 0
        fld_size = 0
        aview = field[FI_View]
        atype = field[FI_Type]
        entry = nil
        case aview
          when 'integer', 'byte', 'word'
            entry = IntegerEntry.new
          when 'hex'
            entry = HexEntry.new
          when 'real'
            entry = FloatEntry.new
          when 'time'
            entry = TimeEntry.new
          when 'date'
            entry = DateEntry.new
          when 'coord'
            entry = CoordBox.new
          when 'base64'
            entry = Base64Entry.new
          when 'phash', 'panhash'
            if field[FI_Id]=='panhash'
              entry = HexEntry.new
              #entry.editable = false
            else
              entry = PanhashBox.new(atype)
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
            when 'Blob'
              def_size = 128
          end
          #p '---'
          #p 'name='+field[FI_Name]
          #p 'atype='+atype.inspect
          #p 'def_size='+def_size.inspect
          fld_size = field[FI_FSize].to_i if field[FI_FSize]
          #p 'fld_size='+fld_size.inspect
          max_size = field[FI_Size].to_i
          max_size = fld_size if (max_size==0)
          #p 'max_size1='+max_size.inspect
          fld_size = def_size if (fld_size<=0)
          max_size = fld_size if (max_size<fld_size) and (max_size>0)
          #p 'max_size2='+max_size.inspect
        rescue
          #p 'FORM rescue [fld_size, max_size, def_size]='+[fld_size, max_size, def_size].inspect
          fld_size = def_size
        end
        #p 'Final [fld_size, max_size]='+[fld_size, max_size].inspect
        #entry.width_chars = fld_size
        entry.max_length = max_size if max_size>0
        color = field[FI_Color]
        if color
          color = Gdk::Color.parse(color)
        else
          color = nil
        end
        #entry.modify_fg(Gtk::STATE_ACTIVE, color)
        entry.modify_text(Gtk::STATE_NORMAL, color)

        ew = fld_size*@middle_char_width
        ew = form_width if ew > form_width
        entry.width_request = ew
        ew,eh = entry.size_request
        #p '[view, ew,eh]='+[aview, ew,eh].inspect
        field[FI_Widget] = entry
        field[FI_WidW] = ew
        field[FI_WidH] = eh
        entries_width += ew
        max_entry_height = eh if max_entry_height < eh
        entry.text = field[FI_Value].to_s
      end

      field_matrix = Array.new
      mw, mh = 0, 0
      row = Array.new
      row_index = -1
      rw, rh = 0, 0
      orient = :up
      @fields.each_index do |index|
        field = @fields[index]
        if (index==0) or (field[FI_NewRow]==1)
          row_index += 1
          field_matrix << row if row != []
          mw, mh = [mw, rw].max, mh+rh
          row = []
          rw, rh = 0, 0
        end

        if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
        orient = field[FI_LabOr]

        field_size = calc_field_size(field)
        rw, rh = rw+field_size[0], [rh, field_size[1]+1].max
        row << field
      end
      field_matrix << row if row != []
      mw, mh = [mw, rw].max, mh+rh

      if (mw<=form_width) and (mh<=form_height) then
        window_width, window_height = mw+36, mh+@btn_panel_height+115
      end
      window.set_default_size(window_width, window_height)

      @window_width, @window_height = 0, 0
      @old_field_matrix = []
    end

    def calc_field_size(field)
      lw = field[FI_LabW]
      lh = field[FI_LabH]
      ew = field[FI_WidW]
      eh = field[FI_WidH]
      if (field[FI_LabOr]==:left) or (field[FI_LabOr]==:right)
        [lw+ew, [lh,eh].max]
      else
        field_size = [[lw,ew].max, lh+eh]
      end
    end

    def calc_row_size(row)
      rw, rh = [0, 0]
      row.each do |fld|
        fs = calc_field_size(fld)
        rw, rh = rw+fs[0], [rh, fs[1]].max
      end
      [rw, rh]
    end

    def on_resize_window(window, event)
      if (@window_width == event.width) and (@window_height == event.height)
        return
      end
      @window_width, @window_height = event.width, event.height

      form_width = @window_width-36
      form_height = @window_height-@btn_panel_height-55

      #p '---fill'

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
              if (index==0) or (field[FI_NewRow]==1)
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

              if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
              orient = field[FI_LabOr]

              field_size = calc_field_size(field)
              rw, rh = rw+field_size[0], [rh, field_size[1]].max
              row << field

              if rw>form_width
                col = row.size
                while (col>0) and (rw>form_width)
                  col -= 1
                  fld = row[col]
                  if [:left, :right].include?(fld[FI_LabOr])
                    fld[FI_LabOr]=:up
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
              if ! [:up, :down, :left, :right].include?(field[FI_LabOr])
                field[FI_LabOr] = orient
              end
              orient = field[FI_LabOr]
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
            if (field[FI_LabOr] != ofield[FI_LabOr]) or (field[FI_LabW] != ofield[FI_LabW]) \
              or (field[FI_LabH] != ofield[FI_LabH]) \
              or (field[FI_WidW] != ofield[FI_WidW]) or (field[FI_WidH] != ofield[FI_WidH]) \
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

        @def_widget = focus if focus

        # delete sub-containers
        if @vbox.children.size>0
          @vbox.hide_all
          @vbox.child_visible = false
          @fields.each_index do |index|
            field = @fields[index]
            label = field[FI_Label]
            entry = field[FI_Widget]
            label.parent.remove(label)
            entry.parent.remove(entry)
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
            label = field[FI_Label]
            entry = field[FI_Widget]
            if (field[FI_LabOr]==nil) or (field[FI_LabOr]==:left)
              row_hbox.pack_start(label, false, false, 2)
              row_hbox.pack_start(entry, false, false, 2)
            elsif (field[FI_LabOr]==:right)
              row_hbox.pack_start(entry, false, false, 2)
              row_hbox.pack_start(label, false, false, 2)
            else
              field_vbox = Gtk::VBox.new
              if (field[FI_LabOr]==:down)
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
        if @def_widget
          #focus = @def_widget
          @def_widget.grab_focus
        end
      end
    end
  end


  $update_interval = 30
  $download_thread = nil

  UPD_FileList = ['lib/gtk.rb', 'lib/net.rb', 'lib/model.rb', 'lib/utils.rb', \
    'lib/crypto.rb', 'model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'pandora.bat']
  UPD_FileList.concat(['model/03-language-'+$lang+'.xml', 'lang/'+$lang+'.txt']) if ($lang and ($lang != 'en'))

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    def self.update_file(http, path, pfn)
      res = false
    path = File.dirname(pfn)
    FileUtils.mkdir_p(path) unless Dir.exists?(path)
      if Dir.exists?(path)
        begin
          #p [path, pfn]
          response = http.request_get(path)
          File.open(pfn, 'wb+') do |file|
            file.write(response.body)
            res = true
            PandoraUtils.log_message(LM_Info, _('File updated')+': '+pfn)
          end
        rescue => err
          puts 'Update error: '+err.message
        end
      else
        puts 'Cannot create directory: '+path
      end
      res
    end

    if $download_thread and $download_thread.alive?
      $download_thread[:all_step] = all_step
      $download_thread.run if $download_thread.stop?
    else
      $download_thread = Thread.new do
        Thread.current[:all_step] = all_step
        downloaded = false

        $window.set_status_field(SF_Update, 'Need check')
        sleep($update_interval) if not Thread.current[:all_step]

        $window.set_status_field(SF_Update, 'Checking')
        main_script = File.join($pandora_root_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          arch_name = File.join($pandora_root_dir, 'master.zip')
          main_uri = URI('https://raw.github.com/Novator/Pandora/master/pandora.rb')
          #arch_uri = URI('https://codeload.github.com/Novator/Pandora/zip/master')

          time = 0
          http = nil
          if File.stat(main_script).writable?
            begin
              #p '-----------'
              #p [main_uri.host, main_uri.port, main_uri.path]
              http = Net::HTTP.new(main_uri.host, main_uri.port)
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
              http.open_timeout = 60*5
              response = http.request_head(main_uri.path)
              PandoraUtils.set_param('last_check', Time.now)
              if (response.content_length == curr_size)
                http = nil
                $window.set_status_field(SF_Update, 'Ok', true)
                PandoraUtils.set_param('last_update', Time.now)
              else
                time = Time.now.to_i
              end
            rescue => err
              http = nil
              $window.set_status_field(SF_Update, 'Connection error')
              PandoraUtils.log_message(LM_Warning, _('Cannot connect to GitHub to check update'))
              puts err.message
            end
          else
            $window.set_status_field(SF_Update, 'Read only')
          end
          if http
            $window.set_status_field(SF_Update, 'Need update')
            Thread.stop

            if Time.now.to_i >= time + 60*5
              begin
                http = Net::HTTP.new(main_uri.host, main_uri.port)
                http.use_ssl = true
                http.verify_mode = OpenSSL::SSL::VERIFY_NONE
                http.open_timeout = 60*5
              rescue => err
                http = nil
                $window.set_status_field(SF_Update, 'Connection error')
                PandoraUtils.log_message(LM_Warning, _('Cannot connect to GitHub to update'))
                puts err.message
              end
            end

            if http
              $window.set_status_field(SF_Update, 'Doing')
              PandoraUtils.log_message(LM_Info, _('Updating Pandora from')+': '+main_uri.host+'..')
              # updating pandora.rb
              downloaded = update_file(http, main_uri.path, main_script)
              # updating other files
              UPD_FileList.each do |fn|
                pfn = File.join($pandora_root_dir, fn)
                if File.exist?(pfn) and File.stat(pfn).writable?
                  downloaded = downloaded and update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                else
                  downloaded = false
                  PandoraUtils.log_message(LM_Warning, _('Not exist or read only')+': '+pfn)
                end
              end
              if downloaded
                PandoraUtils.set_param('last_update', Time.now)
                $window.set_status_field(SF_Update, 'Need restart')
                Thread.stop
                Kernel.abort('Pandora is updated. Run it again')
              else
                $window.set_status_field(SF_Update, 'Load error')
              end
            end
          end
        end
        $download_thread = nil
      end
    end
  end

  # View and edit record dialog
  # RU: Окно просмотра и правки записи
  def self.act_panobject(tree_view, action)

    def self.get_panobject_icon(panobj)
      panobj_icon = nil
      ind = nil
      $window.notebook.children.each do |child|
        if child.name==panobj.ider
          ind = $window.notebook.children.index(child)
          break
        end
      end
      if ind
        first_lab_widget = $window.notebook.get_tab_label($window.notebook.children[ind]).children[0]
        if first_lab_widget.is_a? Gtk::Image
          image = first_lab_widget
          panobj_icon = $window.render_icon(image.stock, Gtk::IconSize::MENU).dup
        end
      end
      panobj_icon
    end

    path = nil
    if tree_view.destroyed?
      new_act = false
    else
      path, column = tree_view.cursor
      new_act = action == 'Create'
    end
    if path or new_act
      panobject = tree_view.panobject
      store = tree_view.model
      iter = nil
      sel = nil
      id = nil
      panhash0 = nil
      lang = 5
      panstate = 0
      created0 = nil
      creator0 = nil
      if path and (not new_act)
        iter = store.get_iter(path)
        id = iter[0]
        sel = panobject.select('id='+id.to_s, true)
        #p 'panobject.namesvalues='+panobject.namesvalues.inspect
        #p 'panobject.matter_fields='+panobject.matter_fields.inspect
        panhash0 = panobject.namesvalues['panhash']
        lang = panhash0[1].ord if panhash0 and panhash0.size>1
        lang ||= 0
        #panhash0 = panobject.panhash(sel[0], lang)
        panstate = panobject.namesvalues['panstate']
        panstate ||= 0
        if (panobject.is_a? PandoraModel::Created)
          created0 = panobject.namesvalues['created']
          creator0 = panobject.namesvalues['creator']
          #p 'created0, creator0='+[created0, creator0].inspect
        end
      end
      #p sel

      panobjecticon = get_panobject_icon(panobject)

      if action=='Delete'
        if id and sel[0]
          info = panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
          dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
            Gtk::MessageDialog::QUESTION,
            Gtk::MessageDialog::BUTTONS_OK_CANCEL,
            _('Record will be deleted. Sure?')+"\n["+info+']')
          dialog.title = _('Deletion')+': '+panobject.sname
          dialog.default_response = Gtk::Dialog::RESPONSE_OK
          dialog.icon = panobjecticon if panobjecticon
          if dialog.run == Gtk::Dialog::RESPONSE_OK
            res = panobject.update(nil, nil, 'id='+id.to_s)
            tree_view.sel.delete_if {|row| row[0]==id }
            store.remove(iter)
            #iter.next!
            pt = path.indices[0]
            pt = tree_view.sel.size-1 if pt>tree_view.sel.size-1
            tree_view.set_cursor(Gtk::TreePath.new(pt), column, false)
          end
          dialog.destroy
        end
      elsif action=='Dialog'
        show_talk_dialog(panhash0) if panhash0
      else  # Edit or Insert

        edit = ((not new_act) and (action != 'Copy'))

        i = 0
        formfields = panobject.def_fields.clone
        tab_flds = panobject.tab_fields
        formfields.each do |field|
          val = nil
          fid = field[FI_Id]
          type = field[FI_Type]
          view = field[FI_View]
          col = tab_flds.index{ |tf| tf[0] == fid }
          if col and sel and (sel[0].is_a? Array)
            val = sel[0][col]
            if (panobject.ider=='Parameter') and (fid=='value')
              type = panobject.field_val('type', sel[0])
              setting = panobject.field_val('setting', sel[0])
              ps = PandoraUtils.decode_param_setting(setting)
              view = ps['view']
              view ||= PandoraUtils.pantype_to_view(type)
              field[FI_View] = view
            end
          end

          val, color = PandoraUtils.val_to_view(val, type, view, true)
          field[FI_Value] = val
          field[FI_Color] = color
        end

        dialog = FieldsDialog.new(panobject, formfields, panobject.sname)
        dialog.icon = panobjecticon if panobjecticon

        if edit
          pub_exist = PandoraModel.act_relation(nil, panhash0, RK_MaxPublic, :check)
          #count, rate, querist_rate = rate_of_panobj(panhash0)
          trust = nil
          res = PandoraCrypto.trust_of_panobject(panhash0)
          trust = res if res.is_a? Float
          dialog.vouch_btn.active = (res != nil)
          dialog.vouch_btn.inconsistent = (res.is_a? Integer)
          dialog.trust_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          dialog.trust_scale.value = trust

          dialog.support_btn.active = (PandoraModel::PSF_Support & panstate)>0
          dialog.public_btn.active = pub_exist
          dialog.public_btn.inconsistent = (pub_exist==nil)

          dialog.lang_entry.entry.text = lang.to_s if lang

          #dialog.lang_entry.active_text = lang.to_s
          #trust_lab = dialog.trust_btn.children[0]
          #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
        else
          key = PandoraCrypto.current_key(false, false)
          not_key_inited = (not (key and key[PandoraCrypto::KV_Obj]))
          dialog.support_btn.active = true
          dialog.vouch_btn.active = true
          if not_key_inited
            dialog.vouch_btn.inconsistent = true
            dialog.trust_scale.sensitive = false
          end
          dialog.public_btn.inconsistent = not_key_inited
        end

        st_text = panobject.panhash_formula
        st_text = st_text + ' [#'+panobject.panhash(sel[0], lang, true, true)+']' if sel and sel.size>0
        PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

        if panobject.class==PandoraModel::Key
          mi = Gtk::MenuItem.new("Действия")
          menu = Gtk::MenuBar.new
          menu.append(mi)

          menu2 = Gtk::Menu.new
          menuitem = Gtk::MenuItem.new("Генерировать")
          menu2.append(menuitem)
          mi.submenu = menu2
          #p dialog.action_area
          dialog.hbox.pack_end(menu, false, false)
          #dialog.action_area.add(menu)
        end

        titadd = nil
        if not edit
        #  titadd = _('edit')
        #else
          titadd = _('new')
        end
        dialog.title += ' ('+titadd+')' if titadd and (titadd != '')

        dialog.run do
          # take value from form
          dialog.fields.each do |field|
            entry = field[FI_Widget]
            field[FI_Value] = entry.text
          end
          dialog.text_fields.each do |field|
            textview = field[FI_Widget]
            field[FI_Value] = textview.buffer.text
          end

          # fill hash of values
          flds_hash = {}
          dialog.fields.each do |field|
            type = field[FI_Type]
            view = field[FI_View]
            val = field[FI_Value]

            if (panobject.ider=='Parameter') and (field[FI_Id]=='value')
              type = panobject.field_val('type', sel[0])
              setting = panobject.field_val('setting', sel[0])
              ps = PandoraUtils.decode_param_setting(setting)
              view = ps['view']
              view ||= PandoraUtils.pantype_to_view(type)
            end

            val = PandoraUtils.view_to_val(val, type, view)
            flds_hash[field[FI_Id]] = val
          end
          dialog.text_fields.each do |field|
            flds_hash[field[FI_Id]] = field[FI_Value]
          end
          lg = nil
          begin
            lg = dialog.lang_entry.entry.text
            lg = lg.to_i if (lg != '')
          rescue
          end
          lang = lg if lg
          lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

          time_now = Time.now.to_i
          if (panobject.is_a? PandoraModel::Created)
            flds_hash['created'] = created0 if created0
            if not edit
              flds_hash['created'] = time_now
              creator = PandoraCrypto.current_user_or_key(true)
              flds_hash['creator'] = creator
            end
          end
          flds_hash['modified'] = time_now
          panstate = 0
          panstate = panstate | PandoraModel::PSF_Support if dialog.support_btn.active?
          flds_hash['panstate'] = panstate
          if (panobject.is_a? PandoraModel::Key)
            lang = flds_hash['rights'].to_i
          end

          panhash = panobject.panhash(flds_hash, lang)
          flds_hash['panhash'] = panhash

          if (panobject.is_a? PandoraModel::Key) and (flds_hash['kind'].to_i == PandoraCrypto::KT_Priv) and edit
            flds_hash['panhash'] = panhash0
          end

          filter = nil
          filter = 'id='+id.to_s if edit
          res = panobject.update(flds_hash, nil, filter, true)
          if res
            filter ||= { :panhash => panhash, :modified => time_now }
            sel = panobject.select(filter, true)
            if sel[0]
              #p 'panobject.namesvalues='+panobject.namesvalues.inspect
              #p 'panobject.matter_fields='+panobject.matter_fields.inspect

              id = panobject.field_val('id', sel[0])  #panobject.namesvalues['id']
              id = id.to_i
              #p 'id='+id.inspect

              #p 'id='+id.inspect
              ind = tree_view.sel.index { |row| row[0]==id }
              #p 'ind='+ind.inspect
              if ind
                #p '---------CHANGE'
                tree_view.sel[ind] = sel[0]
                iter[0] = id
                store.row_changed(path, iter)
              else
                #p '---------INSERT'
                tree_view.sel << sel[0]
                iter = store.append
                iter[0] = id
                tree_view.set_cursor(Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
              end

              if not dialog.vouch_btn.inconsistent?
                PandoraCrypto.unsign_panobject(panhash0, true)
                if dialog.vouch_btn.active?
                  trust = (dialog.trust_scale.value*127).round
                  PandoraCrypto.sign_panobject(panobject, trust)
                end
              end

              if not dialog.public_btn.inconsistent?
                #p 'panhash,panhash0='+[panhash, panhash0].inspect
                PandoraModel.act_relation(nil, panhash0, RK_MaxPublic, :delete, true, true) if panhash != panhash0
                if dialog.public_btn.active?
                  PandoraModel.act_relation(nil, panhash, RK_MaxPublic, :create, true, true)
                else
                  PandoraModel.act_relation(nil, panhash, RK_MaxPublic, :delete, true, true)
                end
              end
            end
          end
        end
      end
    elsif action=='Dialog'
      PandoraGtk.show_panobject_list(PandoraModel::Person)
    end
  end

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :label

    def initialize(image, title, child=nil, *args)
      super(*args)
      label_box = self

      label_box.pack_start(image, false, false, 0) if image

      @label = Gtk::Label.new(title)

      label_box.pack_start(label, false, false, 0)

      if child
        btn = Gtk::Button.new
        btn.relief = Gtk::RELIEF_NONE
        btn.focus_on_click = false
        style = btn.modifier_style
        style.xthickness = 0
        style.ythickness = 0
        btn.modify_style(style)
        wim,him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
        btn.set_size_request(wim+2,him+2)
        btn.signal_connect('clicked') do |*args|
          yield if block_given?
          ind = $window.notebook.children.index(child)
          $window.notebook.remove_page(ind) if ind
          label_box.destroy if not label_box.destroyed?
          child.destroy if not child.destroyed?
        end
        close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
        btn.add(close_image)

        align = Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
        align.add(btn)
        label_box.pack_start(align, false, false, 0)
      end

      label_box.spacing = 3
      label_box.show_all
    end

  end


  $media_buf_size = 50
  $send_media_queues = []
  $send_media_rooms = {}

  def self.set_send_ptrind_by_room(room_id)
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

  def self.get_send_ptrind_by_room(room_id)
    ptr = nil
    if room_id
      set_ptr = $send_media_rooms[room_id]
      if set_ptr and set_ptr[0]
        ptr = set_ptr[1]
      end
    end
    ptr
  end

  def self.nil_send_ptrind_by_room(room_id)
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = false
      end
    end
    res = $send_media_rooms.select{|room,ptr| ptr[0] }
    res.size
  end

  $hide_on_minimize = true

  def self.get_view_params
    $hide_on_minimize = PandoraUtils.get_param('hide_on_minimize')
    $load_history_count = PandoraUtils.get_param('load_history_count')
    $sort_history_mode = PandoraUtils.get_param('sort_history_mode')
  end

  def self.get_main_params
    get_view_params
  end

  CSI_Persons = 0
  CSI_Keys    = 1
  CSI_Nodes   = 2
  CSI_PersonRecs = 3

  $key_watch_lim   = 5
  $sign_watch_lim  = 5

  # Get person panhash by any panhash
  # RU: Получить панхэш персоны по произвольному панхэшу
  def self.extract_targets_from_panhash(targets, panhashes)
    persons, keys, nodes = targets
    panhashes = [panhashes] if not panhashes.is_a? Array
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

  # Extend lists of persons, nodes and keys by relations
  # RU: Расширить списки персон, узлов и ключей пройдясь по связям
  def self.extend_targets_by_relations(targets)
    added = 0
    # need to copmose by relations
    added
  end

  # Start a thread which is searching additional nodes and keys
  # RU: Запуск потока, которые ищет дополнительные узлы и ключи
  def self.start_extending_targets_by_hunt(targets)
    started = true
    # heen hunt with poll of nodes
    started
  end

  def self.construct_room_id(persons)
    res = nil
    if (persons.is_a? Array) and (persons.size>0)
      sha1 = Digest::SHA1.new
      persons.each do |panhash|
        sha1.update(panhash)
      end
      res = sha1.digest
    end
    res
  end

  def self.find_active_sender(not_this=nil)
    res = nil
    $window.notebook.children.each do |child|
      if (child != not_this) and (child.is_a? DialogScrollWin) and child.vid_button.active?
        return child
      end
    end
    res
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

  $you_color = 'blue'
  $dude_color = 'red'
  $tab_color = 'blue'
  $read_time = 1.5
  $last_page = nil

  class ViewDrawingArea < Gtk::DrawingArea
    attr_accessor :expose_event

    def initialize
      super
      #set_size_request(100, 100)
      #@expose_event = signal_connect('expose-event') do
      #  alloc = self.allocation
      #  self.window.draw_arc(self.style.fg_gc(self.state), true, \
      #    0, 0, alloc.width, alloc.height, 0, 64 * 360)
      #end
    end

    def set_expose_event(value)
      signal_handler_disconnect(@expose_event) if @expose_event
      @expose_event = value
    end
  end

  # Talk dialog
  # RU: Диалог разговора
  class DialogScrollWin < Gtk::ScrolledWindow
    attr_accessor :room_id, :targets, :online_button, :snd_button, :vid_button, :talkview, \
      :editbox, :area_send, :area_recv, :recv_media_pipeline, :appsrcs, :session, :ximagesink, \
      :read_thread, :recv_media_queue, :has_unread

    include PandoraGtk

    CL_Online = 0
    CL_Name   = 1

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(known_node, a_room_id, a_targets)
      super(nil, nil)

      @has_unread = false
      @room_id = a_room_id
      @targets = a_targets
      @recv_media_queue = Array.new
      @recv_media_pipeline = Array.new
      @appsrcs = Array.new

      p 'TALK INIT [known_node, a_room_id, a_targets]='+[known_node, a_room_id, a_targets].inspect

      model = PandoraUtils.get_model('Node')

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #sw.name = title
      #sw.add(treeview)
      border_width = 0

      image = Gtk::Image.new(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::MENU)
      image.set_padding(2, 0)

      hpaned = Gtk::HPaned.new
      add_with_viewport(hpaned)

      vpaned1 = Gtk::VPaned.new
      vpaned2 = Gtk::VPaned.new

      @area_recv = ViewDrawingArea.new
      area_recv.set_size_request(320, 240)
      area_recv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))

      hbox = Gtk::HBox.new

      bbox = Gtk::HBox.new
      bbox.border_width = 5
      bbox.spacing = 5

      @online_button = GoodCheckButton.new(_('Online'), true)
      online_button.good_signal_clicked do |widget|
        if widget.active?
          widget.good_set_active(false)
          targets[CSI_Nodes].each do |keybase|
            $window.pool.init_session(nil, keybase, 0, self)
          end
        else
          targets[CSI_Nodes].each do |keybase|
            $window.pool.stop_session(nil, keybase, false)
          end
        end
      end
      online_button.good_set_active(known_node != nil)

      bbox.pack_start(online_button, false, false, 0)

      @snd_button = GoodCheckButton.new(_('Sound'), true)
      snd_button.good_signal_clicked do |widget|
        if widget.active?
          if init_audio_sender(true)
            online_button.active = true
          end
        else
          init_audio_sender(false, true)
          init_audio_sender(false)
        end
      end
      bbox.pack_start(snd_button, false, false, 0)

      @vid_button = GoodCheckButton.new(_('Video'), true)
      vid_button.good_signal_clicked do |widget|
        if widget.active?
          if init_video_sender(true)
            online_button.active = true
          end
        else
          init_video_sender(false, true)
          init_video_sender(false)
        end
      end

      bbox.pack_start(vid_button, false, false, 0)

      hbox.pack_start(bbox, false, false, 1.0)

      vpaned1.pack1(area_recv, false, true)
      vpaned1.pack2(hbox, false, true)
      vpaned1.set_size_request(350, 270)

      @talkview = PandoraGtk::ExtTextView.new
      talkview.set_readonly(true)
      talkview.set_size_request(200, 200)
      talkview.wrap_mode = Gtk::TextTag::WRAP_WORD
      #view.cursor_visible = false
      #view.editable = false

      talkview.buffer.create_tag('you', 'foreground' => $you_color)
      talkview.buffer.create_tag('dude', 'foreground' => $dude_color)
      talkview.buffer.create_tag('you_bold', 'foreground' => $you_color, 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      talkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  'weight' => Pango::FontDescription::WEIGHT_BOLD)

      @editbox = Gtk::TextView.new
      editbox.wrap_mode = Gtk::TextTag::WRAP_WORD
      editbox.set_size_request(200, 70)

      editbox.grab_focus

      talksw = Gtk::ScrolledWindow.new(nil, nil)
      talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      talksw.add(talkview)

      editbox.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
        and (not event.state.control_mask?) and (not event.state.shift_mask?) and (not event.state.mod1_mask?)
          if editbox.buffer.text != ''
            mes = editbox.buffer.text
            sended = add_and_send_mes(mes)
            if sended
              add_mes_to_view(mes)
              editbox.buffer.text = ''
            end
          end
          true
        elsif (Gdk::Keyval::GDK_Escape==event.keyval)
          editbox.buffer.text = ''
          false
        else
          false
        end
      end
      PandoraGtk.hack_enter_bug(editbox)

      hpaned2 = Gtk::HPaned.new
      @area_send = ViewDrawingArea.new
      area_send.set_size_request(120, 90)
      area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
      hpaned2.pack1(area_send, false, true)


      option_box = Gtk::HBox.new

      sender_box = Gtk::VBox.new
      sender_box.pack_start(option_box, false, true, 0)
      sender_box.pack_start(editbox, true, true, 0)

      vouch_btn = GoodCheckButton.new(_('vouch'), true)
      vouch_btn.good_signal_clicked do |widget|
        #update_btn.clicked
      end
      option_box.pack_start(vouch_btn, false, false, 0)

      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      trust_scale = Gtk::HScale.new(adjustment)
      trust_scale.set_size_request(90, -1)
      trust_scale.update_policy = Gtk::UPDATE_DELAYED
      trust_scale.digits = 1
      trust_scale.draw_value = true
      trust_scale.value = 1.0
      trust_scale.value_pos = Gtk::POS_RIGHT
      option_box.pack_start(trust_scale, false, false, 0)

      smile_btn = Gtk::Button.new(_('smile'))
      option_box.pack_start(smile_btn, false, false, 4)
      game_btn = Gtk::Button.new(_('game'))
      option_box.pack_start(game_btn, false, false, 4)

      require_sign_btn = GoodCheckButton.new(_('require sign'), true)
      require_sign_btn.good_signal_clicked do |widget|
        #update_btn.clicked
      end
      option_box.pack_start(require_sign_btn, false, false, 0)

      hpaned2.pack2(sender_box, true, true)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
      #list_sw.visible = false

      list_store = Gtk::ListStore.new(TrueClass, String)
      targets[CSI_Nodes].each do |keybase|
        user_iter = list_store.append
        user_iter[CL_Name] = PandoraUtils.bytes_to_hex(keybase)
      end

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

      #title_widget = Gtk::HBox.new
      #title_widget.pack_start(tit_image, false, false, 0)
      #title_label = Gtk::Label.new(_('People'))
      #title_widget.pack_start(title_label, false, false, 0)
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

      hpaned3 = Gtk::HPaned.new
      hpaned3.pack1(list_sw, true, true)
      hpaned3.pack2(talksw, true, true)
      #motion-notify-event  #leave-notify-event  enter-notify-event
      #hpaned3.signal_connect('notify::position') do |widget, param|
      #  if hpaned3.position <= 1
      #    list_tree.set_size_request(0, -1)
      #    list_sw.set_size_request(0, -1)
      #  end
      #end
      hpaned3.position = 1
      hpaned3.position = 0

      area_send.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      area_send.signal_connect('button-press-event') do |widget, event|
        if hpaned3.position <= 1
          list_sw.width_request = 150 if list_sw.width_request <= 1
          hpaned3.position = list_sw.width_request
        else
          list_sw.width_request = list_sw.allocation.width
          hpaned3.position = 0
        end
      end

      area_send.signal_connect('visibility_notify_event') do |widget, event_visibility|
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            init_video_sender(true, true) if not area_send.destroyed?
          when Gdk::EventVisibility::FULLY_OBSCURED
            init_video_sender(false, true) if not area_send.destroyed?
        end
      end

      area_send.signal_connect('destroy') do |*args|
        init_video_sender(false)
      end

      vpaned2.pack1(hpaned3, true, true)
      vpaned2.pack2(hpaned2, false, true)

      hpaned.pack1(vpaned1, false, true)
      hpaned.pack2(vpaned2, true, true)

      area_recv.signal_connect('visibility_notify_event') do |widget, event_visibility|
        #p 'visibility_notify_event!!!  state='+event_visibility.state.inspect
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            init_video_receiver(true, true, false) if not area_recv.destroyed?
          when Gdk::EventVisibility::FULLY_OBSCURED
            init_video_receiver(false) if not area_recv.destroyed?
        end
      end

      #area_recv.signal_connect('map') do |widget, event|
      #  p 'show!!!!'
      #  init_video_receiver(true, true, false) if not area_recv.destroyed?
      #end

      area_recv.signal_connect('destroy') do |*args|
        init_video_receiver(false, false)
      end

      title = 'unknown'
      label_box = TabLabelBox.new(image, title, self, false, 0) do
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?

        targets[CSI_Nodes].each do |keybase|
          $window.pool.stop_session(nil, keybase, false)
        end
      end

      page = $window.notebook.append_page(self, label_box)

      self.signal_connect('delete-event') do |*args|
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end
      $window.construct_room_title(self)

      show_all

      load_history($load_history_count, $sort_history_mode)

      $window.notebook.page = $window.notebook.n_pages-1 if not known_node
      editbox.grab_focus
    end

    def add_mes_to_view(mes, key_or_panhash=nil, myname=nil, modified=nil, created=nil, to_end=nil)

      def time_to_str(time, time_now)
        time_fmt = '%H:%M:%S'
        time_fmt = '%d.%m.%Y '+time_fmt if ((time_now.to_i - time.to_i).abs > 12*3600)
        time = Time.at(time) if (time.is_a? Integer)
        time_str = time.strftime(time_fmt)
      end

      if mes
        notice = false
        if not myname
          mykey = PandoraCrypto.current_key(false, false)
          myname = PandoraCrypto.short_name_of_person(mykey)
        end

        time_style = 'you'
        name_style = 'you_bold'
        user_name = nil
        if key_or_panhash
          if key_or_panhash.is_a? String
            user_name = PandoraCrypto.short_name_of_person(nil, key_or_panhash, 0, myname)
          else
            user_name = PandoraCrypto.short_name_of_person(key_or_panhash, nil, 0, myname)
          end
          time_style = 'dude'
          name_style = 'dude_bold'
          notice = (not to_end.is_a? FalseClass)
        else
          user_name = myname
          #if not user_name
          #  mykey = PandoraCrypto.current_key(false, false)
          #  user_name = PandoraCrypto.short_name_of_person(mykey)
          #end
        end
        user_name = 'noname' if (not user_name) or (user_name=='')

        time_now = Time.now
        created = time_now if (not modified) and (not created)

        #vals = time_now.to_a
        #ny, nm, nd = vals[5], vals[4], vals[3]
        #midnight = Time.local(y, m, d)
        ##midnight = PandoraUtils.calc_midnight(time_now)

        #if created
        #  vals = modified.to_a
        #  my, mm, md = vals[5], vals[4], vals[3]

        #  cy, cm, cd = my, mm, md
        #  if created
        #    vals = created.to_a
        #    cy, cm, cd = vals[5], vals[4], vals[3]
        #  end

        #  if [cy, cm, cd] == [my, mm, md]

        #else
        #end

        #'12:30:11'
        #'27.07.2013 15:57:56'

        #'12:30:11 (12:31:05)'
        #'27.07.2013 15:57:56 (21:05:00)'
        #'27.07.2013 15:57:56 (28.07.2013 15:59:33)'

        #'(15:59:33)'
        #'(28.07.2013 15:59:33)'

        time_str = ''
        time_str << time_to_str(created, time_now) if created
        if modified and ((not created) or ((modified.to_i-created.to_i).abs>30))
          time_str << ' ' if (time_str != '')
          time_str << '('+time_to_str(modified, time_now)+')'
        end

        talkview.before_addition(time_now) if to_end.nil?
        talkview.buffer.insert(talkview.buffer.end_iter, "\n") if (talkview.buffer.char_count>0)
        talkview.buffer.insert(talkview.buffer.end_iter, time_str+' ', time_style)
        talkview.buffer.insert(talkview.buffer.end_iter, user_name+':', name_style)
        talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)

        talkview.after_addition(to_end) if (not to_end.is_a? FalseClass)
        talkview.show_all

        update_state(true) if notice
      end
    end

    def load_history(max_message=6, sort_mode=0)
      if talkview and max_message and (max_message>0)
        messages = []
        fields = 'creator, created, destination, state, text, panstate, modified'

        mypanhash = PandoraCrypto.current_user_or_key(true)
        myname = PandoraCrypto.short_name_of_person(nil, mypanhash)

        persons = targets[CSI_Persons]
        nil_create_time = false
        persons.each do |person|
          model = PandoraUtils.get_model('Message')
          max_message2 = max_message
          max_message2 = max_message * 2 if (person == mypanhash)
          sel = model.select({:creator=>person, :destination=>mypanhash}, false, fields, \
            'id DESC', max_message2)
          sel.reverse!
          if (person == mypanhash)
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
              and ((time-time_prev).abs<30) and (AsciiString.new(text)==AsciiString.new(text_prev)))
                #p 'DEL '+[time, text, time_prev, text_prev].inspect
                sel.delete_at(i)
                i -= 1
              end
            end
          end
          messages += sel
          if (person != mypanhash)
            sel = model.select({:creator=>mypanhash, :destination=>person}, false, fields, \
              'id DESC', max_message)
            messages += sel
          end
        end
        if nil_create_time or (sort_mode==0) #sort by created
          messages.sort! do |a,b|
            res = (a[6]<=>b[6])
            res = (a[1]<=>b[1]) if (res==0) and (not nil_create_time)
            res
          end
        else   #sort by modified
          messages.sort! {|a,b| res = (a[1]<=>b[1]); res = (a[6]<=>b[6]) if (res==0); res }
        end

        talkview.before_addition
        i = (messages.size-max_message)
        i = 0 if i<0
        while i<messages.size do
          message = messages[i]

          creator = message[0]
          created = message[1]
          mes = message[4]
          modified = message[6]

          key_or_panhash = nil
          key_or_panhash = creator if (creator != mypanhash)

          add_mes_to_view(mes, key_or_panhash, myname, modified, created, false)

          i += 1
        end
        talkview.after_addition

        talkview.show_all
      end
    end

    def get_name_and_family(i)
      person = nil
      if i.is_a? String
        person = i
        i = targets[CSI_Persons].index(person)
      else
        person = targets[CSI_Persons][i]
      end
      aname, afamily = '', ''
      if i and person
        person_recs = targets[CSI_PersonRecs]
        if not person_recs
          person_recs = Array.new
          targets[CSI_PersonRecs] = person_recs
        end
        if person_recs[i]
          aname, afamily = person_recs[i]
        else
          aname, afamily = PandoraCrypto.name_and_family_of_person(nil, person)
          person_recs[i] = [aname, afamily]
        end
      end
      [aname, afamily]
    end

    def set_session(session, online=true)
      @sessions ||= []
      if online
        @sessions << session if (not @sessions.include?(session))
      else
        @sessions.delete(session)
        session.conn_mode = (session.conn_mode & (~PandoraNet::CM_Dialog))
        session.dialog = nil
      end
      active = (@sessions.size>0)
      online_button.good_set_active(active) if (not online_button.destroyed?)
      if not active
        snd_button.active = false if (not snd_button.destroyed?) and snd_button.active?
        vid_button.active = false if (not vid_button.destroyed?) and vid_button.active?
        #snd_button.good_set_active(false) if (not snd_button.destroyed?)
        #vid_button.good_set_active(false) if (not vid_button.destroyed?)
      end
    end

    # Send message to node
    # RU: Отправляет сообщение на узел
    def add_and_send_mes(text)
      res = false
      creator = PandoraCrypto.current_user_or_key(true)
      if creator
        online_button.active = true if (not online_button.active?)
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        targets[CSI_Persons].each do |panhash|
          #p 'ADD_MESS panhash='+panhash.inspect
          values = {:destination=>panhash, :text=>text, :state=>state, \
            :creator=>creator, :created=>time_now, :modified=>time_now}
          model = PandoraUtils.get_model('Message')
          panhash = model.panhash(values)
          values['panhash'] = panhash
          res1 = model.update(values, nil, nil)
          res = (res or res1)
        end
        dlg_sessions = $window.pool.sessions_on_dialog(self)
        dlg_sessions.each do |session|
          session.conn_mode = (session.conn_mode | PandoraNet::CM_Dialog)
          session.send_state = (session.send_state | PandoraNet::CSF_Message)
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
        if $last_page and ($last_page.is_a? DialogScrollWin) \
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
        if (not self.read_thread) and (curpage == self) and $window.visible? and $window.has_toplevel_focus?
          #color = $window.modifier_style.text(Gtk::STATE_NORMAL)
          #curcolor = tab_widget.label.modifier_style.fg(Gtk::STATE_ACTIVE)
          if @has_unread #curcolor and (color != curcolor)
            timer_setted = true
            self.read_thread = Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.editbox.destroyed?)
                curpage.editbox.grab_focus
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
        # set focus to editbox
        if curpage and (curpage.is_a? DialogScrollWin) and curpage.editbox
          if not timer_setted
            Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.editbox.destroyed?)
                curpage.editbox.grab_focus
              end
            end
          end
          Thread.pass
          curpage.editbox.grab_focus
        end
      end
    end

    def parse_gst_string(text)
      elements = Array.new
      text.strip!
      elem = nil
      link = false
      i = 0
      while i<text.size
        j = 0
        while (i+j<text.size) and (not ([' ', '=', "\\", '!', '/', 10.chr, 13.chr].include? text[i+j, 1]))
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
            while (i+j<text.size) and (quotes or (not ([' ', "\\", '!', 10.chr, 13.chr].include? text[i+j, 1])))
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

    def add_elem_to_pipe(str, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      elements = parse_gst_string(str)
      elem, pad = append_elems_to_pipe(elements, pipeline, prev_elem, prev_pad, name_suff)
      [elem, pad]
    end

    def link_sink_to_area(sink, area, pipeline=nil)
      def set_xid(area, sink)
        if (not area.destroyed?) and area.window and sink and (sink.class.method_defined? 'set_xwindow_id')
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

    def init_video_sender(start=true, just_upd_area=false)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and (PandoraUtils::elem_playing?($webcam_xvimagesink))
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          area_send.set_expose_event(nil)
          tsw = PandoraGtk.find_active_sender(self)
          if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
          and tsw.area_send and tsw.area_send.window
            link_sink_to_area($webcam_xvimagesink, tsw.area_send)
            #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
          end
          #p '--LEAVE'
          area_send.queue_draw if area_send and (not area_send.destroyed?)
        else
          #$webcam_xvimagesink.xwindow_id = 0
          count = PandoraGtk.nil_send_ptrind_by_room(room_id)
          if video_pipeline and (count==0) and (not PandoraUtils::elem_stopped?(video_pipeline))
            video_pipeline.stop
            area_send.set_expose_event(nil)
            #p '==STOP!!'
          end
        end
        #Thread.pass
      elsif (not self.destroyed?) and (not vid_button.destroyed?) and vid_button.active? \
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
                p 'appsink new buf!!!'
                #buf = appsink.pull_preroll
                #buf = appsink.pull_sample
                p buf = appsink.pull_buffer
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
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            vid_button.active = false
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
            video_pipeline.play if (not PandoraUtils::elem_playing?(video_pipeline))
          else
            ptrind = PandoraGtk.set_send_ptrind_by_room(room_id)
            count = PandoraGtk.nil_send_ptrind_by_room(nil)
            if count>0
              #Gtk.main_iteration
              #???
              p 'PLAAAAAAAAAAAAAAY 1'
              p PandoraUtils::elem_playing?(video_pipeline)
              video_pipeline.play if (not PandoraUtils::elem_playing?(video_pipeline))
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

    def init_video_receiver(start=true, can_play=true, init=true)
      if not start
        if ximagesink and (PandoraUtils::elem_playing?(ximagesink))
          if can_play
            ximagesink.pause
          else
            ximagesink.stop
          end
        end
        if not can_play
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
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            vid_button.active = false
          end
        end

        if @ximagesink #and area_recv.window
          link_sink_to_area(@ximagesink, area_recv,  recv_media_pipeline[1])
        end

        #p '[recv_media_pipeline[1], can_play]='+[recv_media_pipeline[1], can_play].inspect
        if recv_media_pipeline[1] and can_play and area_recv.window
          #if (not area_recv.expose_event) and
          if (not PandoraUtils::elem_playing?(recv_media_pipeline[1])) or (not PandoraUtils::elem_playing?(ximagesink))
            #p 'PLAYYYYYYYYYYYYYYYYYY!!!!!!!!!! '
            #ximagesink.stop
            #recv_media_pipeline[1].stop
            ximagesink.play
            recv_media_pipeline[1].play
          end
        end
      end
    end

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

    def init_audio_sender(start=true, just_upd_area=false)
      audio_pipeline = $send_media_pipelines['audio']
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+snd_button.active?.inspect
      if not start
        #count = PandoraGtk.nil_send_ptrind_by_room(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (not PandoraUtils::elem_stopped?(audio_pipeline))
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not snd_button.destroyed?) and snd_button.active?
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
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGtk.set_send_ptrind_by_room(room_id)
          count = PandoraGtk.nil_send_ptrind_by_room(nil)
          #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
          if (count>0) and (not PandoraUtils::elem_playing?(audio_pipeline))
          #if (audio_pipeline.get_state != Gst::STATE_PLAYING)
            audio_pipeline.play
          end
        end
      end
      audio_pipeline
    end

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
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
          recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
        end
        if recv_media_pipeline[0] and can_play
          recv_media_pipeline[0].play if (not PandoraUtils::elem_playing?(recv_media_pipeline[0]))
        end
      end
    end
  end  #--class DialogScrollWin

  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(panhashes, known_node=nil)
    sw = nil
    p 'show_talk_dialog: [panhashes, known_node]='+[panhashes, known_node].inspect
    targets = [[], [], []]
    persons, keys, nodes = targets
    if known_node and (panhashes.is_a? String)
      persons << panhashes
      nodes << known_node
    else
      extract_targets_from_panhash(targets, panhashes)
    end
    if nodes.size==0
      extend_targets_by_relations(targets)
    end
    if nodes.size==0
      start_extending_targets_by_hunt(targets)
    end
    targets.each do |list|
      list.sort!
    end
    persons.uniq!
    persons.compact!
    keys.uniq!
    keys.compact!
    nodes.uniq!
    nodes.compact!
    p 'targets='+targets.inspect

    if (persons.size>0) and (nodes.size>0)
      room_id = construct_room_id(persons)
      if known_node
        creator = PandoraCrypto.current_user_or_key(true)
        if (persons.size==1) and (persons[0]==creator)
          room_id[-1] = (room_id[-1].ord ^ 1).chr
        end
      end
      p 'room_id='+room_id.inspect
      $window.notebook.children.each do |child|
        if (child.is_a? DialogScrollWin) and (child.room_id==room_id)
          child.targets = targets
          child.online_button.good_set_active(known_node != nil)
          $window.notebook.page = $window.notebook.children.index(child) if (not known_node)
          sw = child
          break
        end
      end
      if not sw
        sw = DialogScrollWin.new(known_node, room_id, targets)
      end
    elsif (not known_node)
      mes = _('node') if nodes.size == 0
      mes = _('person') if persons.size == 0
      dialog = Gtk::MessageDialog.new($window, \
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
        Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
        mes = _('No one')+' '+mes+' '+_('is not found')+".\n"+_('Add nodes and do hunt'))
      dialog.title = _('Note')
      dialog.default_response = Gtk::Dialog::RESPONSE_OK
      dialog.icon = $window.icon
      if (dialog.run == Gtk::Dialog::RESPONSE_OK)
        PandoraGtk.show_panobject_list(PandoraModel::Node, nil, nil, true)
      end
      dialog.destroy
    end
    sw
  end

  # Search panel
  # RU: Панель поиска
  class SearchScrollWin < Gtk::ScrolledWindow
    attr_accessor :text

    include PandoraGtk

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(text=nil)
      super(nil, nil)

      @text = nil
      @search_thread = nil

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vpaned = Gtk::VPaned.new

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

      search_entry = Gtk::Entry.new
      PandoraGtk.hack_enter_bug(search_entry)
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
        cant_find = (@search_thread or (search_entry.text.size==0))
        PandoraGtk.set_readonly(search_btn, cant_find)
        false
      end

      kind_entry = Gtk::Combo.new
      kind_entry.set_popdown_strings(['auto','person','file','all'])
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

      hbox = Gtk::HBox.new
      hbox.pack_start(kind_entry, false, false, 0)
      hbox.pack_start(search_btn, false, false, 0)
      hbox.pack_start(search_entry, true, true, 0)
      hbox.pack_start(stop_btn, false, false, 0)
      hbox.pack_start(prev_btn, false, false, 0)
      hbox.pack_start(next_btn, false, false, 0)

      option_box = Gtk::HBox.new

      vbox = Gtk::VBox.new
      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(option_box, false, true, 0)

      #kind_btn = PandoraGtk::GoodToggleToolButton.new(Gtk::Stock::PROPERTIES)
      #kind_btn.tooltip_text = _('Change password')
      #kind_btn.good_signal_clicked do |*args|
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

      local_btn = GoodCheckButton.new(_('locally'), true)
      local_btn.good_signal_clicked do |widget|
        #update_btn.clicked
      end

      active_btn = GoodCheckButton.new(_('active only'), true)
      active_btn.good_signal_clicked do |widget|
        #update_btn.clicked
      end
      active_btn.good_set_active(true)

      hunt_btn = GoodCheckButton.new(_('hunt!'), true)
      hunt_btn.good_signal_clicked do |widget|
        #update_btn.clicked
      end
      hunt_btn.good_set_active(true)

      option_box.pack_start(local_btn, false, true, 1)
      option_box.pack_start(active_btn, false, true, 1)
      option_box.pack_start(hunt_btn, false, true, 1)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(Integer, String)

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
        text = search_entry.text
        search_entry.position = search_entry.position  # deselect
        if (text.size>0) and (not @search_thread)
          @search_thread = Thread.new do
            th = Thread.current
            th[:processing] = true
            PandoraGtk.set_readonly(stop_btn, false)
            PandoraGtk.set_readonly(widget, true)
            i = 4
            while (i>0) and th[:processing] do
              p [i, th[:processing]]
              sleep 1
              user_iter = list_store.append
              user_iter[0] = 1
              user_iter[1] = text
              i -= 1
            end
            PandoraGtk.set_readonly(stop_btn, true)
            if th[:processing]
              th[:processing] = false
            end
            PandoraGtk.set_readonly(widget, false)
            PandoraGtk.set_readonly(prev_btn, false)
            PandoraGtk.set_readonly(next_btn, true)
            @search_thread = nil
          end
        end
        false
      end

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
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vpaned.pack1(vbox, false, true)
      vpaned.pack2(list_sw, true, true)
      list_sw.show_all

      self.add_with_viewport(vpaned)
      #self.add(hpaned)

      PandoraGtk.hack_grab_focus(search_entry)
    end
  end

  # Showing search panel
  # RU: Показать панель поиска
  def self.show_search_panel(text=nil)
    sw = SearchScrollWin.new(text)

    image = Gtk::Image.new(Gtk::Stock::FIND, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Search'), sw, false, 0) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Profile panel
  # RU: Панель профиля
  class ProfileScrollWin < Gtk::ScrolledWindow
    attr_accessor :person

    include PandoraGtk

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(a_person=nil)
      super(nil, nil)

      @person = a_person

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #self.add_with_viewport(vpaned)
    end
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

    short_name = ''
    aname, afamily = nil, nil
    if a_person0
      mykey = nil
      mykey = PandoraCrypto.current_key(false, false) if (not a_person0)
      if mykey and mykey[PandoraCrypto::KV_Creator] and (mykey[PandoraCrypto::KV_Creator] != a_person)
        aname, afamily = PandoraCrypto.name_and_family_of_person(mykey, a_person)
      else
        aname, afamily = PandoraCrypto.name_and_family_of_person(nil, a_person)
      end

      short_name = afamily[0, 15] if afamily
      short_name = aname[0]+'. '+short_name if aname
    end

    sw = ProfileScrollWin.new(a_person)

    hpaned = Gtk::HPaned.new
    hpaned.border_width = 2
    sw.add_with_viewport(hpaned)


    list_sw = Gtk::ScrolledWindow.new(nil, nil)
    list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
    list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

    list_store = Gtk::ListStore.new(String)

    user_iter = list_store.append
    user_iter[0] = _('Profile')
    user_iter = list_store.append
    user_iter[0] = _('Events')

    # create tree view
    list_tree = Gtk::TreeView.new(list_store)
    #list_tree.rules_hint = true
    #list_tree.search_column = CL_Name

    renderer = Gtk::CellRendererText.new
    column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
    column.set_sort_column_id(0)
    list_tree.append_column(column)

    #renderer = Gtk::CellRendererText.new
    #column = Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
    #column.set_sort_column_id(1)
    #list_tree.append_column(column)

    list_tree.signal_connect('row_activated') do |tree_view, path, column|
      # download and go to record
    end

    list_sw.add(list_tree)

    hpaned.pack1(list_sw, false, true)
    hpaned.pack2(Gtk::Label.new('test'), true, true)
    list_sw.show_all


    image = Gtk::Image.new(Gtk::Stock::HOME, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    short_name = _('Profile') if not((short_name.is_a? String) and (short_name.size>0))

    label_box = TabLabelBox.new(image, short_name, sw, false, 0) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # List of session
  # RU: Список сеансов
  class SessionScrollWin < Gtk::ScrolledWindow
    attr_accessor :session

    include PandoraGtk

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(session=nil)
      super(nil, nil)

      @session = nil

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.signal_connect('clicked') do |*args|
        p 'need update'
      end
      update_btn.tooltip_text = title
      update_btn.label = title

      hunted_btn = GoodCheckButton.new(_('hunted'), true)
      hunted_btn.good_signal_clicked do |widget|
        update_btn.clicked
      end
      hunted_btn.good_set_active(true)

      hunters_btn = GoodCheckButton.new(_('hunters'), true)
      hunters_btn.good_signal_clicked do |widget|
        update_btn.clicked
      end
      hunters_btn.good_set_active(true)

      fishers_btn = GoodCheckButton.new(_('fishers'), true)
      fishers_btn.good_signal_clicked do |widget|
        update_btn.clicked
      end
      fishers_btn.good_set_active(true)

      hbox.pack_start(hunted_btn, false, true, 0)
      hbox.pack_start(hunters_btn, false, true, 0)
      hbox.pack_start(fishers_btn, false, true, 0)
      hbox.pack_start(update_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(Integer, String)

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)

      list_tree.grab_focus
    end
  end

  # Show session list
  # RU: Показать список сеансов
  def self.show_session_panel(session=nil)
    $window.notebook.children.each do |child|
      if (child.is_a? SessionScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        return
      end
    end

    sw = SessionScrollWin.new(session)

    image = Gtk::Image.new(Gtk::Stock::JUSTIFY_FILL, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Sessions'), sw, false, 0) do
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Status icon
  # RU: Иконка в трее
  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon, :play_sounds, :online

    def initialize(a_update_win_icon=false, a_flash_on_new=true, a_flash_interval=0, a_play_sounds=true)
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

      menuitem = Gtk::SeparatorMenuItem.new
      menu.append(menuitem)

      menuitem = Gtk::MenuItem.new(_('Hide/Show'))
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

    def set_online(state=nil)
      base_icon0 = @base_icon
      if state
        @base_icon = @online_icon
      elsif state==false
        @base_icon = @main_icon
      end
      update_icon
    end

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

    def icon_activated(top_sens=true)
      #$window.skip_taskbar_hint = false
      p $window.visible?
      if $window.visible?
        if (not top_sens) or ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
          $window.hide
        else
          $window.do_menu_act('Activate')
        end
      else
        $window.do_menu_act('Activate')
        update_icon if @update_win_icon
        if @message
          page = $window.notebook.page
          if (page >= 0)
            cur_page = $window.notebook.get_nth_page(page)
            if cur_page.is_a? PandoraGtk::DialogScrollWin
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($window.notebook.n_pages == 0)
          end
        end
      end
    end

  end  #--PandoraStatusIcon

  class CaptchaHPaned < Gtk::HPaned
    attr_accessor :csw

    def initialize(first_child)
      super()
      @first_child = first_child
      self.pack1(@first_child, true, true)
      @csw = nil
    end

    def show_captcha(srckey, captcha_buf=nil, clue_text=nil, node=nil)
      res = nil
      if captcha_buf and (not @csw)
        @csw = Gtk::ScrolledWindow.new(nil, nil)
        csw = @csw

        csw.signal_connect('destroy-event') do
          show_captcha(srckey)
        end

        @vbox = Gtk::VBox.new
        vbox = @vbox

        csw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
        csw.add_with_viewport(vbox)

        pixbuf_loader = Gdk::PixbufLoader.new
        pixbuf_loader.last_write(captcha_buf) if captcha_buf

        label = Gtk::Label.new(_('Far node'))
        vbox.pack_start(label, false, false, 2)
        entry = Gtk::Entry.new
        node_text = PandoraUtils.bytes_to_hex(srckey)
        node_text = node if (not node_text) or (node_text=='')
        node_text ||= ''
        entry.text = node_text
        entry.editable = false
        vbox.pack_start(entry, false, false, 2)

        image = Gtk::Image.new(pixbuf_loader.pixbuf)
        vbox.pack_start(image, false, false, 2)

        clue_text ||= ''
        clue, length, symbols = clue_text.split('|')
        #p '    [clue, length, symbols]='+[clue, length, symbols].inspect

        len = 0
        begin
          len = length.to_i if length
        rescue
        end

        label = Gtk::Label.new(_('Enter text from picture'))
        vbox.pack_start(label, false, false, 2)

        captcha_entry = PandoraGtk::MaskEntry.new
        captcha_entry.max_length = len
        if symbols
          mask = symbols.downcase+symbols.upcase
          captcha_entry.mask = mask
        end

        okbutton = Gtk::Button.new(Gtk::Stock::OK)
        okbutton.signal_connect('clicked') do
          text = captcha_entry.text
          yield(text) if block_given?
          show_captcha(srckey)
        end

        cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
        cancelbutton.signal_connect('clicked') do
          yield(false) if block_given?
          show_captcha(srckey)
        end

        captcha_entry.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            okbutton.activate
            true
          elsif (Gdk::Keyval::GDK_Escape==event.keyval)
            captcha_entry.text = ''
            cancelbutton.activate
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
        align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(captcha_entry)
        vbox.pack_start(align, false, false, 2)
        #capdialog.def_widget = entry

        hbox = Gtk::HBox.new
        hbox.pack_start(okbutton, true, true, 2)
        hbox.pack_start(cancelbutton, true, true, 2)

        vbox.pack_start(hbox, false, false, 2)

        if clue
          label = Gtk::Label.new(_(clue))
          vbox.pack_start(label, false, false, 2)
        end
        if length
          label = Gtk::Label.new(_('Length')+'='+length.to_s)
          vbox.pack_start(label, false, false, 2)
        end
        if symbols
          sym_text = _('Symbols')+': '+symbols.to_s
          i = 30
          while i<sym_text.size do
            sym_text = sym_text[0,i]+"\n"+sym_text[i+1..-1]
            i += 31
          end
          label = Gtk::Label.new(sym_text)
          vbox.pack_start(label, false, false, 2)
        end

        csw.border_width = 1;
        csw.set_size_request(250, -1)
        self.border_width = 2
        self.pack2(csw, true, true)  #hpaned3                                      9
        csw.show_all
        full_width = $window.allocation.width
        self.position = full_width-250 #self.max_position #@csw.width_request
        PandoraGtk.hack_grab_focus(captcha_entry)
        res = csw
      else
        #@csw.width_request = @csw.allocation.width
        @csw.destroy if (not @csw.destroyed?)
        @csw = nil
        self.position = 0
      end
      res
    end
  end  #--CaptchaHPaned

  class MainWindow < Gtk::Window
    attr_accessor :hunter_count, :listener_count, :fisher_count, :log_view, :notebook, \
      :cvpaned, :pool, :focus_timer, :title_view, :do_on_show

    include PandoraUtils

    def update_conn_status(conn, session_type, diff_count)
      if session_type==0
        @hunter_count += diff_count
      elsif session_type==1
        @listener_count += diff_count
      else
        @fisher_count += diff_count
      end
      set_status_field(SF_Conn, hunter_count.to_s+'/'+listener_count.to_s+'/'+fisher_count.to_s)
      online = ((@hunter_count>0) or (@listener_count>0) or (@fisher_count>0))
      $statusicon.set_online(online)
    end

    $toggle_buttons = []

    def correct_lis_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Listen]
      tool_btn.good_set_active($listen_thread != nil) if tool_btn
    end

    def correct_hunt_btn_state
      tool_btn = $toggle_buttons[SF_Hunt]
      tool_btn.good_set_active($hunter_thread != nil) if tool_btn
    end

    $statusbar = nil
    $status_fields = []

    def add_status_field(index, text)
      $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0) if ($status_fields != [])
      btn = Gtk::Button.new(text)
      btn.relief = Gtk::RELIEF_NONE
      if block_given?
        btn.signal_connect('clicked') do |*args|
          yield(*args)
        end
      end
      $statusbar.pack_start(btn, false, false, 0)
      $status_fields[index] = btn
    end

    def set_status_field(index, text, enabled=nil, toggle=nil)
      btn = $status_fields[index]
      if btn
        str = _(text)
        str = _('Version') + ': ' + str if (index==SF_Update)
        btn.label = str
        if (enabled != nil)
          btn.sensitive = enabled
        end
        if (toggle != nil) and $toggle_buttons[index]
          $toggle_buttons[index].good_set_active(toggle)
        end
      end
    end

    def get_status_field(index)
      $status_fields[index]
    end

    TV_Name    = 0
    TV_NameF   = 1
    TV_Family  = 2
    TV_NameN   = 3

    MaxTitleLen = 15

    def construct_room_title(dialog, check_all=true)
      res = 'unknown'
      persons = dialog.targets[CSI_Persons]
      if (persons.is_a? Array) and (persons.size>0)
        res = ''
        persons.each_with_index do |person, i|
          aname, afamily = dialog.get_name_and_family(i)
          addname = ''
          case @title_view
            when TV_Name, TV_NameN
              if (aname.size==0)
                addname << afamily
              else
                addname << aname
              end
            when TV_NameF
              if (aname.size==0)
                addname << afamily
              else
                addname << aname
                addname << afamily[0] if afamily[0]
              end
            when TV_Family
              if (afamily.size==0)
                addname << aname
              else
                addname << afamily
              end
          end
          if (addname.size>0)
            res << ',' if (res.size>0)
            res << addname
          end
        end
        res = 'unknown' if (res.size==0)
        if res.size>MaxTitleLen
          res = res[0, MaxTitleLen-1]+'..'
        end
        tab_widget = $window.notebook.get_tab_label(dialog)
        tab_widget.label.text = res if tab_widget
        #p 'title_view, res='+[@title_view, res].inspect
        if check_all
          @title_view=TV_Name if (@title_view==TV_NameN)
          has_conflict = true
          while has_conflict
            has_conflict = false
            names = Array.new
            $window.notebook.children.each do |child|
              if (child.is_a? DialogScrollWin)
                tab_widget = $window.notebook.get_tab_label(child)
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
              if (@title_view < TV_NameN)
                @title_view += 1
              else
                has_conflict = false
              end
              #p '@title_view='+@title_view.inspect
              names = Array.new
              $window.notebook.children.each do |child|
                if (child.is_a? DialogScrollWin)
                  sn = construct_room_title(child, false)
                  if (@title_view == TV_NameN)
                    names << sn
                    c = names.count(sn)
                    sn = sn+c.to_s if c>1
                    tab_widget = $window.notebook.get_tab_label(child)
                    tab_widget.label.text = sn if tab_widget
                  end
                end
              end
            end
          end
        end
      end
      res
    end

    # Menu event handler
    # RU: Обработчик события меню
    def do_menu_act(command, treeview=nil)
      widget = nil
      if not command.is_a? String
        widget = command
        command = widget.name
      end
      case command
        when 'Quit'
          self.destroy
        when 'Activate'
          self.deiconify
          #self.visible = true if (not self.visible?)
          self.present
        when 'Hide'
          #self.iconify
          self.hide
        when 'About'
          PandoraGtk.show_about
        when 'Close'
          if notebook.page >= 0
            page = notebook.get_nth_page(notebook.page)
            tab = notebook.get_tab_label(page)
            close_btn = tab.children[tab.children.size-1].children[0]
            close_btn.clicked
          end
        when 'Create','Edit','Delete','Copy', 'Dialog', 'Clone'
          if (not treeview) and (notebook.page >= 0)
            sw = notebook.get_nth_page(notebook.page)
            treeview = sw.children[0]
          end
          if treeview and (treeview.is_a? SubjTreeView)
            if command=='Clone'
              panobject = treeview.panobject
              panobject.update(nil, nil, nil)
              panobject.class.tab_fields(true)
            else
              PandoraGtk.act_panobject(treeview, command)
            end
          end
        when 'Listen'
          PandoraNet.start_or_stop_listen
        when 'Hunt'
          PandoraNet.hunt_nodes
        when 'Authorize'
          key = PandoraCrypto.current_key(false, false)
          if key and $listen_thread
            PandoraNet.start_or_stop_listen
          end
          key = PandoraCrypto.current_key(true)
        when 'Wizard'
          a = rand
          if a<0.33
            PandoraUtils.play_mp3('online')
          elsif a<0.66
            PandoraUtils.play_mp3('offline')
          else
            PandoraUtils.play_mp3('message')
          end
          return
          #p OpenSSL::Cipher::ciphers

          #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
          #cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
          #p 'cipher_hash16='+cipher_hash.to_s(16)
          #type_klen = KT_Rsa | KL_bit2048
          #passwd = '123'
          #p keys = generate_key(type_klen, cipher_hash, passwd)
          #type_klen = KT_Aes | KL_bit256
          #key_vec = generate_key(type_klen, cipher_hash, passwd)

          p data = 'Тестовое сообщение!'

          cipher_hash = PandoraCrypto.encode_cipher_and_hash(PandoraCrypto::KT_Rsa | \
            PandoraCrypto::KL_bit2048, PandoraCrypto::KH_None)
          p cipher_vec = PandoraCrypto.generate_key(PandoraCrypto::KT_Bf, cipher_hash)

          p 'initkey'
          p cipher_vec = PandoraCrypto.init_key(cipher_vec)
          p cipher_vec[PandoraCrypto::KV_Pub] = cipher_vec[PandoraCrypto::KV_Obj].random_iv

          p 'coded:'

          p data = PandoraCrypto.recrypt(cipher_vec, data, true)

          p 'decoded:'
          puts data = PandoraCrypto.recrypt(cipher_vec, data, false)

          #typ, count = encode_pson_type(PT_Str, 0x1FF)
          #p decode_pson_type(typ)

          #p pson = namehash_to_pson({:first_name=>'Ivan', :last_name=>'Inavov', 'ddd'=>555})
          #p hash = pson_to_namehash(pson)

          #p PandoraUtils.get_param('base_id')
        when 'Profile'
          PandoraGtk.show_profile_panel
        when 'Search'
          PandoraGtk.show_search_panel
        when 'Session'
          PandoraGtk.show_session_panel
        else
          panobj_id = command
          if PandoraModel.const_defined? panobj_id
            panobject_class = PandoraModel.const_get(panobj_id)
            PandoraGtk.show_panobject_list(panobject_class, widget)
          else
            PandoraUtils.log_message(LM_Warning, _('Menu handler is not defined yet')+' "'+panobj_id+'"')
          end
      end
    end

    # Menu structure
    # RU: Структура меню
    MENU_ITEMS =
      [[nil, nil, '_World'],
      ['Person', Gtk::Stock::ORIENTATION_PORTRAIT, 'People', '<control>E'],
      ['Community', nil, 'Communities'],
      ['-', nil, '-'],
      ['Article', Gtk::Stock::DND, 'Articles'],
      ['Blob', Gtk::Stock::HARDDISK, 'Files', '<control>J'], #Gtk::Stock::FILE
      ['-', nil, '-'],
      ['Country', nil, 'States'],
      ['City', nil, 'Towns'],
      ['Street', nil, 'Streets'],
      ['Thing', nil, 'Things'],
      ['Activity', nil, 'Activities'],
      ['Word', Gtk::Stock::SPELL_CHECK, 'Words'],
      ['Language', nil, 'Languages'],
      ['Address', nil, 'Addresses'],
      ['Contact', nil, 'Contacts'],
      ['-', nil, '-'],
      ['Relation', nil, 'Relations'],
      ['Opinion', nil, 'Opinions'],
      [nil, nil, '_Bussiness'],
      ['Partner', nil, 'Partners'],
      ['Company', nil, 'Companies'],
      ['-', nil, '-'],
      ['Advertisement', nil, 'Advertisements'],
      ['Order', nil, 'Orders'],
      ['Deal', nil, 'Deals'],
      ['Waybill', nil, 'Waybills'],
      ['Debenture', nil, 'Debentures'],
      ['Transfer', nil, 'Transfers'],
      ['-', nil, '-'],
      ['Deposit', nil, 'Deposits'],
      ['Guarantee', nil, 'Guarantees'],
      ['Insurer', nil, 'Insurers'],
      ['-', nil, '-'],
      ['Storage', nil, 'Storages'],
      ['Product', nil, 'Products'],
      ['Service', nil, 'Services'],
      ['Currency', nil, 'Currency'],
      ['Contract', nil, 'Contracts'],
      ['Report', nil, 'Reports'],
      [nil, nil, '_Region'],
      ['Citizen', nil, 'Citizens'],
      ['Union', nil, 'Unions'],
      ['-', nil, '-'],
      ['Project', nil, 'Projects'],
      ['Resolution', nil, 'Resolutions'],
      ['Law', nil, 'Laws'],
      ['-', nil, '-'],
      ['Contribution', nil, 'Contributions'],
      ['Expenditure', nil, 'Expenditures'],
      ['-', nil, '-'],
      ['Offense', nil, 'Offenses'],
      ['Punishment', nil, 'Punishments'],
      ['-', nil, '-'],
      ['Resource', nil, 'Resources'],
      ['Delegation', nil, 'Delegations'],
      ['Registry', nil, 'Registry'],
      [nil, nil, '_Pandora'],
      ['Parameter', Gtk::Stock::PROPERTIES, 'Parameters'],
      ['-', nil, '-'],
      ['Key', Gtk::Stock::DIALOG_AUTHENTICATION, 'Keys'],
      ['Sign', nil, 'Signs'],
      ['Node', Gtk::Stock::NETWORK, 'Nodes'],
      ['Message', nil, 'Messages'],
      ['Patch', nil, 'Patches'],
      ['Event', nil, 'Events'],
      ['Fishhook', nil, 'Fishhooks'],
      ['Session', Gtk::Stock::JUSTIFY_FILL, 'Sessions', '<control>S'],
      ['-', nil, '-'],
      ['Authorize', nil, 'Authorize', '<control>U'],
      ['Listen', Gtk::Stock::CONNECT, 'Listen', '<control>L', :check],
      ['Hunt', Gtk::Stock::REFRESH, 'Hunt', '<control>H', :check],
      ['Search', Gtk::Stock::FIND, 'Search', '<control>T'],
      ['-', nil, '-'],
      ['Profile', Gtk::Stock::HOME, 'Profile'],
      ['Wizard', Gtk::Stock::PREFERENCES, 'Wizards'],
      ['-', nil, '-'],
      ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q'],
      ['Close', Gtk::Stock::CLOSE, '_Close', '<control>W'],
      ['-', nil, '-'],
      ['About', Gtk::Stock::ABOUT, '_About']
      ]

    def fill_menubar(menubar)
      menu = nil
      MENU_ITEMS.each do |mi|
        if mi[0]==nil or menu==nil
          menuitem = Gtk::MenuItem.new(_(mi[2]))
          menubar.append(menuitem)
          menu = Gtk::Menu.new
          menuitem.set_submenu(menu)
        else
          menuitem = PandoraGtk.create_menu_item(mi)
          menu.append(menuitem)
        end
      end
    end

    def fill_toolbar(toolbar)
      MENU_ITEMS.each do |mi|
        stock = mi[1]
        if stock
          command = mi[0]
          label = mi[2]
          if command and (command != '-') and label and (label != '-')
            toggle = nil
            toggle = false if mi[4]
            btn = PandoraGtk.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
              do_menu_act(widget)
            end
            btn.name = command
            if (toggle != nil)
              index = nil
              case command
                when 'Listen'
                  index = SF_Listen
                when 'Hunt'
                  index = SF_Hunt
              end
              if index
                $toggle_buttons[index] = btn
                #btn.signal_emit_stop('clicked')
                #btn.signal_emit_stop('toggled')
                #btn.signal_connect('clicked') do |*args|
                #  p args
                #  true
                #end
              end
            end
          end
        end
      end
    end

    # Show main Gtk window
    # RU: Показать главное окно Gtk
    def initialize(*args)
      super(*args)
      $window = self
      @hunter_count, @listener_count, @fisher_count = 0, 0, 0
      @title_view = TV_Name

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

      $group = Gtk::AccelGroup.new
      $window.add_accel_group($group)

      menubar = Gtk::MenuBar.new
      fill_menubar(menubar)

      toolbar = Gtk::Toolbar.new
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      fill_toolbar(toolbar)

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        cur_page = notebook.get_nth_page(page_num)
        if $last_page and (cur_page != $last_page) and ($last_page.is_a? PandoraGtk::DialogScrollWin)
          $last_page.init_video_sender(false, true) if not $last_page.area_send.destroyed?
          $last_page.init_video_receiver(false) if not $last_page.area_recv.destroyed?
        end
        if cur_page.is_a? PandoraGtk::DialogScrollWin
          cur_page.update_state(false, cur_page)
          cur_page.init_video_receiver(true, true, false) if not cur_page.area_recv.destroyed?
          cur_page.init_video_sender(true, true) if not cur_page.area_send.destroyed?
        end
        $last_page = cur_page
      end

      @log_view = PandoraGtk::ExtTextView.new
      log_view.set_readonly(true)
      log_view.border_width = 0

      sw = Gtk::ScrolledWindow.new(nil, nil)
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      sw.shadow_type = Gtk::SHADOW_IN
      sw.add(log_view)
      sw.border_width = 1;
      sw.set_size_request(-1, 40)

      vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      vpaned.pack1(notebook, true, true)
      vpaned.pack2(sw, false, true)

      @cvpaned = CaptchaHPaned.new(vpaned)
      @cvpaned.position = cvpaned.max_position

      $statusbar = Gtk::Statusbar.new
      PandoraGtk.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

      add_status_field(SF_Update, _('Version') + ': ' + _('Not checked')) do
        PandoraGtk.start_updating(true)
      end
      add_status_field(SF_Auth, _('Not logged')) do
        do_menu_act('Authorize')
      end
      add_status_field(SF_Listen, _('Not listen')) do
        do_menu_act('Listen')
      end
      add_status_field(SF_Hunt, _('No hunt')) do
        do_menu_act('Hunt')
      end
      add_status_field(SF_Conn, '0/0/0') do
        do_menu_act('Session')
      end

      vbox = Gtk::VBox.new
      vbox.pack_start(menubar, false, false, 0)
      vbox.pack_start(toolbar, false, false, 0)
      vbox.pack_start(cvpaned, true, true, 0)
      vbox.pack_start($statusbar, false, false, 0)

      $window.add(vbox)

      $window.signal_connect('delete-event') do |*args|
        $window.do_menu_act('Hide')
        true
      end

      update_win_icon = PandoraUtils.get_param('status_update_win_icon')
      flash_on_new = PandoraUtils.get_param('status_flash_on_new')
      flash_interval = PandoraUtils.get_param('status_flash_interval')
      play_sounds = PandoraUtils.get_param('play_sounds')
      mplayer = nil
      if PandoraUtils.os_family=='windows'
        mplayer = PandoraUtils.get_param('win_mp3_player')
      else
        mplayer = PandoraUtils.get_param('linux_mp3_player')
      end
      $mp3_player = mplayer if ((mplayer.is_a? String) and (mplayer.size>0))

      $statusicon = PandoraGtk::PandoraStatusIcon.new(update_win_icon, flash_on_new, flash_interval, play_sounds)

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
        if ([Gdk::Keyval::GDK_m, Gdk::Keyval::GDK_M, 1752, 1784].include?(event.keyval) \
        and event.state.control_mask?)
          $window.hide
        elsif event.keyval == Gdk::Keyval::GDK_F5
          PandoraNet.hunt_nodes
        elsif event.state.control_mask? and (Gdk::Keyval::GDK_0..Gdk::Keyval::GDK_9).include?(event.keyval)
          num = $window.notebook.n_pages
          if num>0
            n = (event.keyval - Gdk::Keyval::GDK_1)
            n = 0 if n<0
            if (n<num) and (n != 8)
              $window.notebook.page = n
              res = true
            else
              $window.notebook.page = num-1
              res = true
            end
          end
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) \
        and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, \
        1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
          $window.destroy
        elsif event.state.control_mask? \
        and [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
          curpage = nil
          if $window.notebook.n_pages>0
            curpage = $window.notebook.get_nth_page($window.notebook.page)
          end
          if curpage.is_a? PandoraGtk::PanobjScrollWin
            res = false
          else
            res = PandoraGtk.show_panobject_list(PandoraModel::Person)
            res = (res != nil)
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
            if sw.is_a? DialogScrollWin
              sw.init_video_sender(false, true) if not sw.area_send.destroyed?
              sw.init_video_receiver(false) if not sw.area_recv.destroyed?
            end
          end
          if widget.visible? and widget.active? and $hide_on_minimize
            $window.hide
            #$window.skip_taskbar_hint = true
          end
        end
      end

      #$window.signal_connect('focus-out-event') do |window, event|
      #  p 'focus-out-event: ' + $window.has_toplevel_focus?.inspect
      #  false
      #end
      $window.do_on_show = PandoraUtils.get_param('do_on_show')
      $window.signal_connect('show') do |window, event|
        if $window.do_on_show > 0
          key = PandoraCrypto.current_key(false, true)
          if ($window.do_on_show>1) and key and (not $listen_thread)
            PandoraNet.start_or_stop_listen
          end
          $window.do_on_show = 0
        end
        false
      end

      @pool = PandoraNet::Pool.new($window)

      $window.set_default_size(640, 420)
      $window.maximize
      $window.show_all

      #------next must be after show main form ---->>>>

      $window.focus_timer = $window
      $window.signal_connect('focus-in-event') do |window, event|
        #p 'focus-in-event: ' + [$window.has_toplevel_focus?, \
        #  event, $window.visible?].inspect
        if $window.focus_timer
          $window.focus_timer = nil if ($window.focus_timer == $window)
        else
          if (PandoraUtils.os_family=='windows') and (not $window.visible?)
            $window.do_menu_act('Activate')
          end
          $window.focus_timer = GLib::Timeout.add(500) do
            #p 'read timer!!!' + $window.has_toplevel_focus?.inspect
            toplevel = ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
            if toplevel and $window.visible?
              $window.notebook.children.each do |child|
                if (child.is_a? DialogScrollWin) and (child.has_unread)
                  $window.notebook.page = $window.notebook.children.index(child)
                  break
                end
              end
              curpage = $window.notebook.get_nth_page($window.notebook.page)
              if (curpage.is_a? PandoraGtk::DialogScrollWin) and toplevel
                curpage.update_state(false, curpage)
              end
            end
            $window.focus_timer = nil
            false
          end
        end
        false
      end

      $base_id = PandoraUtils.get_param('base_id')
      check_update = PandoraUtils.get_param('check_update')
      if (check_update==1) or (check_update==true)
        last_check = PandoraUtils.get_param('last_check')
        last_update = PandoraUtils.get_param('last_update')
        check_interval = PandoraUtils.get_param('check_interval')
        if not check_interval or (check_interval <= 0)
          check_interval = 2
        end
        update_period = PandoraUtils.get_param('update_period')
        if not update_period or (update_period <= 0)
          update_period = 7
        end
        time_now = Time.now.to_i
        need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
        if (time_now - last_update.to_i) < update_period*24*3600
          set_status_field(SF_Update, 'Ok', need_check)
        elsif need_check
          PandoraGtk.start_updating(false)
        end
      end
      PandoraGtk.get_main_params

      Gtk.main
    end

  end  #--MainWindow

end




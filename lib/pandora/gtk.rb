# ====================================================================
# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры
module Pandora
  module Gtk

    # GTK is cross platform graphical user interface
    # RU: Кроссплатформенный оконный интерфейс
    begin
      # require 'gtk2'
      ::Gtk.init
    rescue Exception
      Kernel.abort("Gtk is not installed.\nInstall packet 'ruby-gtk'")
    end

    SF_Update = 0
    SF_Auth   = 1
    SF_Listen = 2
    SF_Hunt   = 3
    SF_Conn   = 4

    # Advanced dialog window
    # RU: Продвинутое окно диалога
    class AdvancedDialog < ::Gtk::Window #::Gtk::Dialog
      attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, \
        :enter_like_tab, :enter_like_ok, :panelbox, :okbutton, :cancelbutton, \
        :def_widget, :main_sw

      # Create method
      # RU: Метод создания
      def initialize(*args)
        p '0----------'
        super(*args)
        p '1----------'
        @response = 0
        @window = self
        @enter_like_tab = false
        @enter_like_ok = true
        set_default_size(300, -1)

        window.transient_for = $window
        window.modal = true
        #window.skip_taskbar_hint = true
        window.window_position = ::Gtk::Window::POS_CENTER
        #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG
        window.destroy_with_parent = true

        @vpaned = ::Gtk::VPaned.new
        vpaned.border_width = 2

        window.add(vpaned)
        #window.vbox.add(vpaned)

        @main_sw = ::Gtk::ScrolledWindow.new(nil, nil)
        sw = main_sw
        sw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        @viewport = ::Gtk::Viewport.new(nil, nil)
        sw.add(viewport)

        image = ::Gtk::Image.new(::Gtk::Stock::PROPERTIES, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box1 = TabLabelBox.new(image, _('Basic'), nil, false, 0)

        @notebook = ::Gtk::Notebook.new
        @notebook.scrollable = true
        page = notebook.append_page(sw, label_box1)
        vpaned.pack1(notebook, true, true)

        @panelbox = ::Gtk::VBox.new
        @hbox = ::Gtk::HBox.new
        panelbox.pack_start(hbox, false, false, 0)

        vpaned.pack2(panelbox, false, true)

        bbox = ::Gtk::HBox.new
        bbox.border_width = 2
        bbox.spacing = 4

        @okbutton = ::Gtk::Button.new(::Gtk::Stock::OK)
        okbutton.width_request = 110
        okbutton.signal_connect('clicked') { |*args|
          @response=2
          #finish
        }
        bbox.pack_start(okbutton, false, false, 0)

        @cancelbutton = ::Gtk::Button.new(::Gtk::Stock::CANCEL)
        cancelbutton.width_request = 110
        cancelbutton.signal_connect('clicked') { |*args|
          @response=1
          #finish
        }
        bbox.pack_start(cancelbutton, false, false, 0)

        hbox.pack_start(bbox, true, false, 1.0)

        #self.signal_connect('response') do |widget, response|
        #  case response
        #    when ::Gtk::Dialog::RESPONSE_OK
        #      p "OK"
        #    when ::Gtk::Dialog::RESPONSE_CANCEL
        #      p "Cancel"
        #    when ::Gtk::Dialog::RESPONSE_CLOSE
        #      p "Close"
        #      dialog.destroy
        #  end
        #end

        p '2----------'

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
            and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? ::Gtk::TextView))))
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

      # Show dialog in modal mode
      # RU: Показать диалог в модальном режиме
      def run2
        res = nil
        show_all
        if @def_widget
          #focus = @def_widget
          @def_widget.grab_focus
        end

        while (not destroyed?) and (@response == 0) do
          #unless alien_thread
            ::Gtk.main_iteration
          #end
          sleep(0.001)
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
    # RU: ToggleToolButton с безопасным переключением "active"
    class SafeToggleToolButton < ::Gtk::ToggleToolButton

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
    class SafeCheckButton < ::Gtk::CheckButton

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
    class MaskEntry < ::Gtk::Entry
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
      end
    end

    # Entry for float
    # RU: Поле ввода дробных чисел
    class FloatEntry < IntegerEntry
      def init_mask
        super
        @mask += '.e'
        self.max_length = 35
      end
    end

    # Entry for HEX
    # RU: Поле ввода шестнадцатеричных чисел
    class HexEntry < MaskEntry
      def init_mask
        super
        @mask = '0123456789abcdefABCDEF'
      end
    end

    Base64chars = [('0'..'9').to_a, ('a'..'z').to_a, ('A'..'Z').to_a, '+/=-_*[]'].join

    # Entry for Base64
    # RU: Поле ввода Base64
    class Base64Entry < MaskEntry
      def init_mask
        super
        @mask = Base64chars
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
      end
    end

    # Entry for date and time
    # RU: Поле ввода даты и времени
    class TimeEntry < DateEntrySimple
      def init_mask
        super
        @mask += ' :'
        self.max_length = 19
        self.tooltip_text = 'DD.MM.YYYY hh:mm:ss'
      end
    end

    # Entry for date
    # RU: Поле ввода даты
    class DateEntry < ::Gtk::HBox
      attr_accessor :entry, :button

      def initialize(*args)
        super(*args)
        @entry = MaskEntry.new
        @entry.mask = '0123456789.'
        @entry.max_length = 10
        @entry.tooltip_text = 'DD.MM.YYYY'

        @button = ::Gtk::Button.new('D')
        @button.can_focus = false

        @entry.instance_variable_set('@button', @button)
        def @entry.key_event(widget, event)
          res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
            and (event.keyval==65364)))
          @button.activate if res
          false
        end
        self.pack_start(entry, true, true, 0)
        align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(@button)
        self.pack_start(align, false, false, 1)
        esize = entry.size_request
        h = esize[1]-2
        @button.set_size_request(h, h)

        #if panclasses==[]
        #  panclasses = $panobject_list
        #end

        button.signal_connect('clicked') do |*args|
          @entry.grab_focus
          if @calwin and (not @calwin.destroyed?)
            @calwin.destroy
            @calwin = nil
          else
            @cal = ::Gtk::Calendar.new
            cal = @cal

            date = PandoraUtils.str_to_date(@entry.text)
            date ||= Time.new
            @month = date.month
            @year = date.year

            cal.select_month(date.month, date.year)
            cal.select_day(date.day)
            #cal.mark_day(date.day)
            cal.display_options = ::Gtk::Calendar::SHOW_HEADING | \
              ::Gtk::Calendar::SHOW_DAY_NAMES | ::Gtk::Calendar::WEEK_START_MONDAY

            cal.signal_connect('day_selected') do
              year, month, day = @cal.date
              if (@month==month) and (@year==year)
                @entry.text = PandoraUtils.date_to_str(Time.local(year, month, day))
                @calwin.destroy
                @calwin = nil
              else
                @month=month
                @year=year
              end
            end

            cal.signal_connect('key-press-event') do |widget, event|
              if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
                @cal.signal_emit('day-selected')
              elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
                ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
              then
                @calwin.destroy
                @calwin = nil
                false
              elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
                ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
              then
                @calwin.destroy
                @calwin = nil
                $window.destroy
                false
              elsif (event.keyval>=65360) and (event.keyval<=65367)
                if event.keyval==65360
                  if @cal.month>0
                    @cal.month = @cal.month-1
                  else
                    @cal.month = 11
                    @cal.year = @cal.year-1
                  end
                elsif event.keyval==65367
                  if @cal.month<11
                    @cal.month = @cal.month+1
                  else
                    @cal.month = 0
                    @cal.year = @cal.year+1
                  end
                elsif event.keyval==65365
                  @cal.year = @cal.year-1
                elsif event.keyval==65366
                  @cal.year = @cal.year+1
                end
                year, month, day = @cal.date
                @month=month
                @year=year
                false
              else
                false
              end
            end

            #menuitem = ::Gtk::ImageMenuItem.new
            #menuitem.add(cal)
            #menuitem.show_all

            #menu = ::Gtk::Menu.new
            #menu.append(menuitem)
            #menu.show_all
            #menu.popup(nil, nil, 0, Gdk::Event::CURRENT_TIME)


            @calwin = ::Gtk::Window.new #(::Gtk::Window::POPUP)
            calwin = @calwin
            calwin.transient_for = $window
            calwin.modal = true
            calwin.decorated = false

            calwin.add(cal)
            calwin.signal_connect('delete_event') { @calwin.destroy; @calwin=nil }

            calwin.signal_connect('focus-out-event') do |win, event|
              @calwin.destroy
              @calwin = nil
              false
            end

            pos = @button.window.origin
            all = @button.allocation.to_a
            calwin.move(pos[0]+all[0], pos[1]+all[1]+all[3]+1)

            calwin.show_all
          end
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

    MaxPanhashTabs = 5

    # Entry for panhash
    # RU: Поле ввода панхэша
    class PanhashBox < ::Gtk::HBox
      attr_accessor :types, :panclasses, :entry, :button

      def initialize(panhash_type, *args)
        super(*args)
        @types = panhash_type
        @entry = HexEntry.new
        @button = ::Gtk::Button.new('...')
        @button.can_focus = false
        @entry.instance_variable_set('@button', @button)
        def @entry.key_event(widget, event)
          res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
            and (event.keyval==65364)))
          @button.activate if res
          false
        end
        self.pack_start(entry, true, true, 0)
        align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(@button)
        self.pack_start(align, false, false, 1)
        esize = entry.size_request
        h = esize[1]-2
        @button.set_size_request(h, h)

        #if panclasses==[]
        #  panclasses = $panobject_list
        #end

        button.signal_connect('clicked') do |*args|
          @entry.grab_focus
          set_classes
          dialog = Pandora::Gtk::AdvancedDialog.new(_('Choose object'))
          dialog.set_default_size(600, 400)
          auto_create = true
          panclasses.each_with_index do |panclass, i|
            title = _(Pandora::Utils.get_name_or_names(panclass.name, true))
            dialog.main_sw.destroy if i==0
            image = ::Gtk::Image.new(::Gtk::Stock::INDEX, ::Gtk::IconSize::MENU)
            image.set_padding(2, 0)
            label_box2 = TabLabelBox.new(image, title, nil, false, 0)
            sw = ::Gtk::ScrolledWindow.new(nil, nil)
            page = dialog.notebook.append_page(sw, label_box2)
            auto_create = Pandora::Gtk.show_panobject_list(panclass, nil, sw, auto_create)
            if panclasses.size>MaxPanhashTabs
              break
            end
          end
          dialog.notebook.page = 0
          dialog.run2 do
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

      # Define allowed pandora object classes
      # RU: Определить допустимые классы Пандоры
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

    # Entry for filename
    # RU: Поле выбора имени файла
    class FilenameBox < ::Gtk::HBox
      attr_accessor :entry, :button, :window

      def initialize(parent, *args)
        super(*args)
        @entry = ::Gtk::Entry.new
        @button = ::Gtk::Button.new('...')
        @button.can_focus = false
        @entry.instance_variable_set('@button', @button)
        def @entry.key_event(widget, event)
          res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
            and (event.keyval==65364)))
          @button.activate if res
          false
        end
        @window = parent
        self.pack_start(entry, true, true, 0)
        align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(@button)
        self.pack_start(align, false, false, 1)
        esize = entry.size_request
        h = esize[1]-2
        @button.set_size_request(h, h)

        button.signal_connect('clicked') do |*args|
          @entry.grab_focus
          dialog =  ::Gtk::FileChooserDialog.new(_('Choose a file'), @window,
            ::Gtk::FileChooser::ACTION_OPEN, 'gnome-vfs',
            [::Gtk::Stock::OPEN, ::Gtk::Dialog::RESPONSE_ACCEPT],
            [::Gtk::Stock::CANCEL, ::Gtk::Dialog::RESPONSE_CANCEL])

          filter = ::Gtk::FileFilter.new
          filter.name = _('All files')+' (*.*)'
          filter.add_pattern('*.*')
          dialog.add_filter(filter)

          filter = ::Gtk::FileFilter.new
          filter.name = _('Pictures')+' (png,jpg,gif)'
          filter.add_pattern('*.png')
          filter.add_pattern('*.jpg')
          filter.add_pattern('*.jpeg')
          filter.add_pattern('*.gif')
          dialog.add_filter(filter)

          filter = ::Gtk::FileFilter.new
          filter.name = _('Sounds')+' (mp3,wav)'
          filter.add_pattern('*.mp3')
          filter.add_pattern('*.wav')
          dialog.add_filter(filter)

          dialog.add_shortcut_folder(Pandora.files_dir)
          fn = @entry.text
          if fn.nil? or (fn=='')
            dialog.current_folder = Pandora.files_dir
          else
            dialog.filename = fn
          end

          scr = Gdk::Screen.default
          if (scr.height > 700)
            frame = ::Gtk::Frame.new
            frame.shadow_type = ::Gtk::SHADOW_IN
            align = ::Gtk::Alignment.new(0.5, 0.5, 0, 0)
            align.add(frame)
            image = ::Gtk::Image.new
            frame.add(image)
            align.show_all

            dialog.preview_widget = align
            dialog.use_preview_label = false
            dialog.signal_connect('update-preview') do
              filename = dialog.preview_filename
              ext = nil
              ext = File.extname(filename) if filename
              if ext and (['.jpg','.gif','.png'].include? ext.downcase)
                begin
                  pixbuf = Gdk::Pixbuf.new(filename, 128, 128)
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

          if dialog.run == ::Gtk::Dialog::RESPONSE_ACCEPT
            @entry.text = dialog.filename
          end
          dialog.destroy
        end
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
        s = button.size_request
        h = s[0]+1
        wr -= h
        wr = 24 if wr<24
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
    class CoordBox < ::Gtk::HBox
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

    # Extended TextView
    # RU: Расширенный TextView
    class ExtTextView < ::Gtk::TextView
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
        Pandora::Gtk.set_readonly(self, value, false)
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

    # Grid for panobjects
    # RU: Таблица для объектов Пандоры
    class SubjTreeView < ::Gtk::TreeView
      attr_accessor :panobject, :sel, :notebook, :auto_create
    end

    # Column for SubjTreeView
    # RU: Колонка для SubjTreeView
    class SubjTreeViewColumn < ::Gtk::TreeViewColumn
      attr_accessor :tab_ind
    end

    # ScrolledWindow for panobjects
    # RU: ScrolledWindow для объектов Пандоры
    class PanobjScrollWin < ::Gtk::ScrolledWindow
    end

    # Dialog with enter fields
    # RU: Диалог с полями ввода
    class FieldsDialog < AdvancedDialog

      attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
        :keep_btn, :rate_label, :vouch_btn, :follow_btn, :trust_scale, :trust0, :public_btn, \
        :public_scale, :lang_entry, :format, :view_buffer, :last_sw

      # Add menu item
      # RU: Добавляет пункт меню
      def add_menu_item(label, menu, text)
        mi = ::Gtk::MenuItem.new(text)
        menu.append(mi)
        mi.signal_connect('activate') do |mi|
          label.label = mi.label
          @format = mi.label.to_s
          p 'format changed to: '+format.to_s
        end
      end

      # Set view text buffer
      # RU: Задает тестовый буфер для просмотра
      def set_view_buffer(format, view_buffer, raw_buffer)
        view_buffer.text = raw_buffer.text
      end

      # Set raw text buffer
      # RU: Задает сырой тестовый буфер
      def set_raw_buffer(format, raw_buffer, view_buffer)
        raw_buffer.text = view_buffer.text
      end

      # Set buffers
      # RU: Задать буферы
      def set_buffers(init=false)
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? ::Gtk::ScrolledWindow) and (child.children[0].is_a? ::Gtk::TextView)
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

      # Set tag for selection
      # RU: Задать тэг для выделенного
      def set_tag(tag)
        if tag
          child = notebook.get_nth_page(notebook.page)
          if (child.is_a? ::Gtk::ScrolledWindow) and (child.children[0].is_a? ::Gtk::TextView)
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

      class BodyScrolledWindow < ::Gtk::ScrolledWindow
        attr_accessor :field, :link_name, :text_view
      end

      # Start loading image from file
      # RU: Запускает загрузку картинки в файл
      def start_image_loading(filename)
        begin
          image_stream = File.open(filename, 'rb')
          image = ::Gtk::Image.new
          widget = image
          Thread.new do
            pixbuf_loader = Gdk::PixbufLoader.new
            pixbuf_loader.signal_connect('area_prepared') do |loader|
              pixbuf = loader.pixbuf
              pixbuf.fill!(0xaaaaaaff)
              image.pixbuf = pixbuf
            end
            pixbuf_loader.signal_connect('area_updated') do
              image.queue_draw
            end
            while image_stream
              buf = image_stream.read(1024*1024)
              pixbuf_loader.write(buf)
              if image_stream.eof?
                image_stream.close
                image_stream = nil
                pixbuf_loader.close
                pixbuf_loader = nil
              end
              sleep(0.005)
            end
          end
        rescue => err
          err_text = _('Image loading error')+":\n"+err.message
          label = ::Gtk::Label.new(err_text)
          widget = label
        end
        widget
      end

      # Create fields dialog
      # RU: Создать форму с полями
      def initialize(apanobject, afields=[], *args)
        super(*args)
        @panobject = apanobject
        @fields = afields

        window.signal_connect('configure-event') do |widget, event|
          window.on_resize_window(widget, event)
          false
        end

        @toolbar = ::Gtk::Toolbar.new
        toolbar.toolbar_style = ::Gtk::Toolbar::Style::ICONS
        panelbox.pack_start(toolbar, false, false, 0)

        @toolbar2 = ::Gtk::Toolbar.new
        toolbar2.toolbar_style = ::Gtk::Toolbar::Style::ICONS
        panelbox.pack_start(toolbar2, false, false, 0)

        @raw_buffer = nil
        @view_mode = true
        @view_buffer = ::Gtk::TextBuffer.new
        @view_buffer.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
        @view_buffer.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
        @view_buffer.create_tag('strike', 'strikethrough' => true)
        @view_buffer.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
        @view_buffer.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
        @view_buffer.create_tag('link', {'foreground' => 'blue', 'underline' => Pango::AttrUnderline::SINGLE})
        @view_buffer.create_tag('linked', {'foreground' => 'navy', 'underline' => Pango::AttrUnderline::SINGLE})
        @view_buffer.create_tag('left', 'justification' => ::Gtk::JUSTIFY_LEFT)
        @view_buffer.create_tag('center', 'justification' => ::Gtk::JUSTIFY_CENTER)
        @view_buffer.create_tag('right', 'justification' => ::Gtk::JUSTIFY_RIGHT)
        @view_buffer.create_tag('fill', 'justification' => ::Gtk::JUSTIFY_FILL)

        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::DND, 'Type', true) do |btn|
          @view_mode = btn.active?
          set_buffers
        end

        btn = ::Gtk::MenuToolButton.new(nil, 'auto')
        menu = ::Gtk::Menu.new
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

        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::BOLD, 'Bold') do |*args|
          set_tag('bold')
        end

        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::ITALIC, 'Italic') do |*args|
          set_tag('italic')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::STRIKETHROUGH, 'Strike') do |*args|
          set_tag('strike')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::UNDERLINE, 'Underline') do |*args|
          set_tag('undline')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::UNDO, 'Undo')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::REDO, 'Redo')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::COPY, 'Copy')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::CUT, 'Cut')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::FIND, 'Find')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_LEFT, 'Left') do |*args|
          set_tag('left')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_RIGHT, 'Right') do |*args|
          set_tag('right')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_CENTER, 'Center') do |*args|
          set_tag('center')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_FILL, 'Fill') do |*args|
          set_tag('fill')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::SAVE, 'Save')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::OPEN, 'Open')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUMP_TO, 'Link') do |*args|
          set_tag('link')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::HOME, 'Image')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::ADD, 'Add')
        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::DELETE, 'Delete')
        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

        @last_sw = nil
        notebook.signal_connect('switch-page') do |widget, page, page_num|
          if (page_num != 1) and @last_sw
            #@last_sw.children.each do |child|
            #  child.destroy if (not child.destroyed?) \
            #    and child.class.method_defined? 'destroy'
            #end
            @last_sw = nil
          end

          if page_num==0
            toolbar.hide
            toolbar2.hide
            hbox.show
          else
            child = notebook.get_nth_page(page_num)
            if (child.is_a? BodyScrolledWindow)
              toolbar2.hide
              hbox.hide
              textsw = child
              field = textsw.field
              if field
                link_name = nil
                link_name = field[FI_Widget].text
                link_name.chomp! if link_name
                if (not field[FI_Widget2]) or (link_name != textsw.link_name)
                  toolbar.show
                  @last_sw = child
                  bodywid = nil
                  if link_name and (link_name != '')
                    if File.exist?(link_name)
                      ext = File.extname(link_name)
                      if ext and (['.jpg','.gif','.png'].include? ext.downcase)
                        image = start_image_loading(link_name)
                        bodywid = image
                        link_name = link_name
                      else
                        link_name = nil
                      end
                    else
                      err_text = _('File does not exist')+":\n"+link_name
                      label = ::Gtk::Label.new(err_text)
                      bodywid = label
                    end
                  else
                    link_name = nil
                  end

                  if not link_name
                    textview = ::Gtk::TextView.new
                    #textview = child.children[0]
                    textview.wrap_mode = ::Gtk::TextTag::WRAP_WORD
                    textview.signal_connect('key-press-event') do |widget, event|
                      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
                        and event.state.control_mask?
                      then
                        true
                      end
                    end
                    textview.buffer.text = field[FI_Value].to_s
                    bodywid = textview
                  end

                  field[FI_Widget2] = bodywid
                  if bodywid.is_a? ::Gtk::TextView
                    textsw.add(bodywid)
                    set_buffers(true)
                  elsif bodywid
                    textsw.add_with_viewport(bodywid)
                  end
                  textsw.show_all
                end
              end
            else
              toolbar.hide
              hbox.hide
              toolbar2.show
            end
          end
        end

        @vbox = ::Gtk::VBox.new
        viewport.add(@vbox)

        @statusbar = ::Gtk::Statusbar.new
        Pandora::Gtk.set_statusbar_text(statusbar, '')
        statusbar.pack_start(::Gtk::SeparatorToolItem.new, false, false, 0)
        panhash_btn = ::Gtk::Button.new(_('Rate: '))
        panhash_btn.relief = ::Gtk::RELIEF_NONE
        statusbar.pack_start(panhash_btn, false, false, 0)

        panelbox.pack_start(statusbar, false, false, 0)


        #rbvbox = ::Gtk::VBox.new

        keep_box = ::Gtk::VBox.new
        @keep_btn = ::Gtk::CheckButton.new(_('keep'), true)
        #keep_btn.signal_connect('toggled') do |widget|
        #  p "keep"
        #end
        #rbvbox.pack_start(keep_btn, false, false, 0)
        #@rate_label = ::Gtk::Label.new('-')
        keep_box.pack_start(keep_btn, false, false, 0)
        @follow_btn = ::Gtk::CheckButton.new(_('follow'), true)
        follow_btn.signal_connect('clicked') do |widget|
          if widget.active?
            @keep_btn.active = true
          end
        end
        keep_box.pack_start(follow_btn, false, false, 0)

        @lang_entry = ::Gtk::Combo.new
        lang_entry.set_popdown_strings(PandoraModel.lang_list)
        lang_entry.entry.text = ''
        lang_entry.entry.select_region(0, -1)
        lang_entry.set_size_request(50, -1)
        keep_box.pack_start(lang_entry, true, true, 5)

        hbox.pack_start(keep_box, false, false, 0)

        trust_box = ::Gtk::VBox.new

        trust0 = nil
        @trust_scale = nil
        @vouch_btn = ::Gtk::CheckButton.new(_('vouch'), true)
        vouch_btn.signal_connect('clicked') do |widget|
          if not widget.destroyed?
            if widget.inconsistent?
              if PandoraCrypto.current_user_or_key(false)
                widget.inconsistent = false
                widget.active = true
                trust0 ||= 0.1
              end
            end
            trust_scale.sensitive = widget.active?
            if widget.active?
              trust0 ||= 0.1
              trust_scale.value = trust0
              @keep_btn.active = true
            else
              trust0 = trust_scale.value
            end
          end
        end
        trust_box.pack_start(vouch_btn, false, false, 0)

        #@scale_button = ::Gtk::ScaleButton.new(::Gtk::IconSize::BUTTON)
        #@scale_button.set_icons(['gtk-goto-bottom', 'gtk-goto-top', 'gtk-execute'])
        #@scale_button.signal_connect('value-changed') { |widget, value| puts "value changed: #{value}" }

        tips = [_('evil'), _('destructive'), _('dirty'), _('harmful'), _('bad'), _('vain'), \
          _('good'), _('useful'), _('constructive'), _('creative'), _('genial')]

        #@trust ||= (127*0.4).round
        #val = trust/127.0
        adjustment = ::Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
        @trust_scale = ::Gtk::HScale.new(adjustment)
        trust_scale.set_size_request(140, -1)
        trust_scale.update_policy = ::Gtk::UPDATE_DELAYED
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
          widget.modify_fg(::Gtk::STATE_NORMAL, color)
          @vouch_btn.modify_bg(::Gtk::STATE_ACTIVE, color)
          i = ((trust+127)/step).round
          tip = tips[i]
          widget.tooltip_text = tip
        end
        #scale.signal_connect('change-value') do |widget|
        #  true
        #end
        trust_box.pack_start(trust_scale, false, false, 0)
        hbox.pack_start(trust_box, false, false, 0)

        pub_lev0 = nil
        public_box = ::Gtk::VBox.new
        @public_btn = ::Gtk::CheckButton.new(_('public'), true)
        public_btn.signal_connect('clicked') do |widget|
          if not widget.destroyed?
            if widget.inconsistent?
              if PandoraCrypto.current_user_or_key(false)
                widget.inconsistent = false
                widget.active = true
                pub_lev0 ||= 0.0
              end
            end
            public_scale.sensitive = widget.active?
            if widget.active?
              pub_lev0 ||= 0.0
              public_scale.value = pub_lev0
              @keep_btn.active = true
              @follow_btn.active = true
              @vouch_btn.active = true
            else
              pub_lev0 = public_scale.value
            end
          end
        end
        public_box.pack_start(public_btn, false, false, 0)

        #@lang_entry = ::Gtk::ComboBoxEntry.new(true)
        #lang_entry.set_size_request(60, 15)
        #lang_entry.append_text('0')
        #lang_entry.append_text('1')
        #lang_entry.append_text('5')

        #@lang_entry = ::Gtk::Combo.new
        #@lang_entry.set_popdown_strings(['0','1','5'])
        #@lang_entry.entry.text = ''
        #@lang_entry.entry.select_region(0, -1)
        #@lang_entry.set_size_request(50, -1)
        #public_box.pack_start(lang_entry, true, true, 5)

        adjustment = ::Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
        @public_scale = ::Gtk::HScale.new(adjustment)
        public_scale.set_size_request(140, -1)
        public_scale.update_policy = ::Gtk::UPDATE_DELAYED
        public_scale.digits = 1
        public_scale.draw_value = true
        step = 19.fdiv(tips.size-1)
        public_scale.signal_connect('value-changed') do |widget|
          val = widget.value
          trust = (val*10).round
          r = 0
          g = 0
          b = 0
          if trust==0
            b = 40000
          else
            mul = ((trust.fdiv(10))*45000).round
            if trust>0
              g = mul+20000
            else
              r = -mul+20000
            end
          end
          tip = val.to_s
          color = Gdk::Color.new(r, g, b)
          widget.modify_fg(::Gtk::STATE_NORMAL, color)
          @vouch_btn.modify_bg(::Gtk::STATE_ACTIVE, color)
          i = ((trust+127)/step).round
          tip = tips[i]
          widget.tooltip_text = tip
        end
        public_box.pack_start(public_scale, false, false, 0)

        hbox.pack_start(public_box, false, false, 0)
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
          #atype = field[FI_Type]
          #if (atype=='Blob') or (atype=='Text')
          aview = field[FI_View]
          if (aview=='blob') or (aview=='text')
            textsw = BodyScrolledWindow.new(nil, nil)
            textsw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)

            image = ::Gtk::Image.new(::Gtk::Stock::DND, ::Gtk::IconSize::MENU)
            image.set_padding(2, 0)
            label_box = TabLabelBox.new(image, atext, nil, false, 0)
            page = notebook.append_page(textsw, label_box)

            #field[FI_Widget] = textview

            field << page
            @text_fields << field
            textsw.field = field

            #@fields.delete_at(i) if (atype=='Text')
          end
        end

        image = ::Gtk::Image.new(::Gtk::Stock::INDEX, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box2 = TabLabelBox.new(image, _('Relations'), nil, false, 0)
        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        page = notebook.append_page(sw, label_box2)

        Pandora::Gtk.show_panobject_list(PandoraModel::Relation, nil, sw)

        image = ::Gtk::Image.new(::Gtk::Stock::DIALOG_AUTHENTICATION, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box2 = TabLabelBox.new(image, _('Signs'), nil, false, 0)
        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        page = notebook.append_page(sw, label_box2)

        Pandora::Gtk.show_panobject_list(PandoraModel::Sign, nil, sw)

        image = ::Gtk::Image.new(::Gtk::Stock::DIALOG_INFO, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box2 = TabLabelBox.new(image, _('Opinions'), nil, false, 0)
        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        page = notebook.append_page(sw, label_box2)

        Pandora::Gtk.show_panobject_list(PandoraModel::Opinion, nil, sw)

        # create labels, remember them, calc middle char width
        texts_width = 0
        texts_chars = 0
        labels_width = 0
        max_label_height = 0
        @fields.each do |field|
          atext = field[FI_VFName]
          aview = field[FI_View]
          label = ::Gtk::Label.new(atext)
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
          p 'field='+field.inspect
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
            when 'filename', 'blob'
              entry = FilenameBox.new(window)
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
              entry = ::Gtk::Entry.new
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
          #entry.modify_fg(::Gtk::STATE_ACTIVE, color)
          entry.modify_text(::Gtk::STATE_NORMAL, color)

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
          text = field[FI_Value].to_s
          #if (atype=='Blob') or (atype=='Text')
          if (aview=='blob') or (aview=='text')
            entry.text = text[1..-1] if text and (text.size<1024) and (text[0]=='@')
          else
            entry.text = text
          end
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
          window_width, window_height = mw+36, mh+@btn_panel_height+125
        end
        window.set_default_size(window_width, window_height)

        @window_width, @window_height = 0, 0
        @old_field_matrix = []
      end

      # Calculate field size
      # RU: Вычислить размер поля
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
            row_hbox = ::Gtk::HBox.new
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
                field_vbox = ::Gtk::VBox.new
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

    # Tab box for notebook with image and close button
    # RU: Бокс закладки для блокнота с картинкой и кнопкой
    class TabLabelBox < ::Gtk::HBox
      attr_accessor :label
      def initialize(image, title, child=nil, *args)
        super(*args)
        label_box = self
        label_box.pack_start(image, false, false, 0) if image
        @label = ::Gtk::Label.new(title)
        label_box.pack_start(label, false, false, 0)
        if child
          btn = ::Gtk::Button.new
          btn.relief = ::Gtk::RELIEF_NONE
          btn.focus_on_click = false
          style = btn.modifier_style
          style.xthickness = 0
          style.ythickness = 0
          btn.modify_style(style)
          wim,him = ::Gtk::IconSize.lookup(::Gtk::IconSize::MENU)
          btn.set_size_request(wim+2,him+2)
          btn.signal_connect('clicked') do |*args|
            yield if block_given?
            ind = $window.notebook.children.index(child)
            $window.notebook.remove_page(ind) if ind
            label_box.destroy if not label_box.destroyed?
            child.destroy if not child.destroyed?
          end
          close_image = ::Gtk::Image.new(::Gtk::Stock::CLOSE, ::Gtk::IconSize::MENU)
          btn.add(close_image)
          align = ::Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
          align.add(btn)
          label_box.pack_start(align, false, false, 0)
        end
        label_box.spacing = 3
        label_box.show_all
      end
    end

    $you_color = 'blue'
    $dude_color = 'red'
    $tab_color = 'blue'
    $read_time = 1.5
    $last_page = nil

    # Set readonly mode to widget
    # RU: Установить виджету режим только для чтения
    def self.set_readonly(widget, value=true, sensitive=true)
      value = (not value)
      widget.editable = value if widget.class.method_defined? 'editable?'
      widget.sensitive = value if sensitive and (widget.class.method_defined? 'sensitive?')
      #widget.can_focus = value
      widget.has_focus = value if widget.class.method_defined? 'has_focus?'
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

    # Creating menu item from its description
    # RU: Создание пункта меню по его описанию
    def self.create_menu_item(mi, treeview=nil)
      menuitem = nil
      if mi[0] == '-'
        menuitem = ::Gtk::SeparatorMenuItem.new
      else
        text = _(mi[2])
        #if (mi[4] == :check)
        #  menuitem = ::Gtk::CheckMenuItem.new(mi[2])
        #  label = menuitem.children[0]
        #  #label.set_text(mi[2], true)
        if mi[1]
          menuitem = ::Gtk::ImageMenuItem.new(mi[1])
          label = menuitem.children[0]
          label.set_text(text, true)
        else
          menuitem = ::Gtk::MenuItem.new(text)
        end
        #if mi[3]
        if (not treeview) and mi[3]
          key, mod = ::Gtk::Accelerator.parse(mi[3])
          menuitem.add_accelerator('activate', $group, key, mod, ::Gtk::ACCEL_VISIBLE) if key
        end
        menuitem.name = mi[0]
        menuitem.signal_connect('activate') { |widget| $window.do_menu_act(widget, treeview) }
      end
      menuitem
    end

    # Set statusbat text
    # RU: Задает текст статусной строки
    def self.set_statusbar_text(statusbar, text)
      statusbar.pop(0)
      statusbar.push(0, text)
    end

    # Add button to toolbar
    # RU: Добавить кнопку на панель инструментов
    def self.add_tool_btn(toolbar, stock, title, toggle=nil)
      btn = nil
      if toggle != nil
        btn = SafeToggleToolButton.new(stock)
        btn.safe_signal_clicked do |*args|
          yield(*args) if block_given?
        end
        btn.active = toggle if toggle
      else
        image = ::Gtk::Image.new(stock, ::Gtk::IconSize::MENU)
        btn = ::Gtk::ToolButton.new(image, _(title))
        #btn = ::Gtk::ToolButton.new(stock)
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

    $update_interval = 30
    $download_thread = nil

    UPD_FileList = [
      'model/01-base.xml',
      'model/02-forms.xml',
      'pandora.sh',
      'pandora.bat'
    ]

    if (Pandora.config.lang and (Pandora.config.lang != 'en'))
      UPD_FileList.concat([
        'model/03-language-'+Pandora.config.lang+'.xml',
        'lang/'+Pandora.config.lang+'.txt'])
    end

    # Check updated files and download them
    # RU: Проверить обновления и скачать их
    def self.start_updating(all_step=true)

      # Update file
      # RU: Обновить файл
      def self.update_file(http, path, pfn, host='')
        res = false
        dir = File.dirname(pfn)
        FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
        if Dir.exists?(dir)
          begin
            Pandora.logger.info _('Download from') + ': ' + \
                                  host + path + '..'
            response = http.request_get(path)
            filebody = response.body
            if filebody and (filebody.size>0)
              File.open(pfn, 'wb+') do |file|
                file.write(filebody)
                res = true
                Pandora.logger.info  _('File updated')+': '+pfn
              end
            else
              Pandora.logger.warn  _('Empty downloaded body')
            end
          rescue => err
            Pandora.logger.warn  _('Update error')+': '+err.message
          end
        else
          Pandora.logger.warn  _('Cannot create directory')+': '+dir
        end
        res
      end

      def self.connect_http(main_uri, curr_size, step, p_addr=nil, p_port=nil, p_user=nil, p_pass=nil)
        http = nil
        time = 0
        Pandora.logger.info _('Connect to') + ': ' + \
            main_uri.host + main_uri.path + ':' + main_uri.port.to_s + '..'
        begin
          http = Net::HTTP.new(main_uri.host, main_uri.port, p_addr, p_port, p_user, p_pass)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          http.open_timeout = 60*5
          response = http.request_head(main_uri.path)
          act_size = response.content_length
          if not act_size
            sleep(0.5)
            response = http.request_head(main_uri.path)
            act_size = response.content_length
          end
          PandoraUtils.set_param('last_check', Time.now)
          p 'Size diff: '+[act_size, curr_size].inspect
          if (act_size == curr_size)
            http = nil
            step = 254
            $window.set_status_field(SF_Update, 'Ok', false)
            PandoraUtils.set_param('last_update', Time.now)
          else
            time = Time.now.to_i
          end
        rescue => err
          http = nil
          $window.set_status_field(SF_Update, 'Connection error')
          Pandora.logger.warn _('Cannot connect to repo to check update')+\
            [main_uri.host, main_uri.port].inspect
          puts err.message
        end
        [http, time, step]
      end

      def self.reconnect_if_need(http, time, main_uri, p_addr=nil, p_port=nil, p_user=nil, p_pass=nil)
        if (not http.active?) or (Time.now.to_i >= (time + 60*5))
          begin
            http = Net::HTTP.new(main_uri.host, main_uri.port, p_addr, p_port, p_user, p_pass)
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            http.open_timeout = 60*5
          rescue => err
            http = nil
            $window.set_status_field(SF_Update, 'Connection error')
            Pandora.logger.warn  _('Cannot reconnect to repo to update')
            puts err.message
          end
        end
        http
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

          main_script = File.join(Pandora.root, 'pandora.rb')
          curr_size = File.size?(main_script)
          if curr_size
            if File.stat(main_script).writable?
              update_zip = Pandora::Utils.get_param('update_zip_first')
              update_zip = true if update_zip.nil?
              proxy = Pandora::Utils.get_param('proxy_server')
              if proxy.is_a? String
                proxy = proxy.split(':')
                proxy ||= []
                proxy = [proxy[0..-4].join(':'), *proxy[-3..-1]] if (proxy.size>4)
                proxy[1] = proxy[1].to_i if (proxy.size>1)
                proxy[2] = nil if (proxy.size>2) and (proxy[2]=='')
                proxy[3] = nil if (proxy.size>3) and (proxy[3]=='')
                Pandora.logger.info  _('Proxy is used')+' '+proxy.inspect
              else
                proxy = []
              end
              step = 0
              while (step<2) do
                step += 1
                if update_zip
                  zip_local = File.join(Pandora.base_dir, 'Pandora-master.zip')
                  zip_exists = File.exist?(zip_local)
                  p [zip_exists, zip_local]
                  if not zip_exists
                    File.open(zip_local, 'wb+') do |file|
                      file.write('0')  #empty file
                    end
                    zip_exists = File.exist?(zip_local)
                  end
                  if zip_exists
                    zip_size = File.size?(zip_local)
                    if zip_size
                      if File.stat(zip_local).writable?
                        #zip_on_repo = 'https://codeload.github.com/Novator/Pandora/zip/master'
                        #dir_in_zip = 'Pandora-maste'
                        zip_on_repo = 'https://bitbucket.org/robux/pandora/get/master.zip'
                        dir_in_zip = 'robux-pandora'
                        main_uri = URI(zip_on_repo)
                        http, time, step = connect_http(main_uri, zip_size, step, *proxy)
                        if http
                          Pandora.logger.info  _('Need update')
                          $window.set_status_field(SF_Update, 'Need update')
                          Thread.stop
                          http = reconnect_if_need(http, time, main_uri, *proxy)
                          if http
                            $window.set_status_field(SF_Update, 'Doing')
                            res = update_file(http, main_uri.path, zip_local, main_uri.host)
                            #res = true
                            if res
                              # Delete old arch paths
                              unzip_mask = File.join(Pandora.base_dir, dir_in_zip+'*')
                              p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                              unzip_paths.each do |pathfilename|
                                p 'Remove dir: '+pathfilename
                                FileUtils.remove_dir(pathfilename) if File.directory?(pathfilename)
                              end
                              # Unzip arch
                              unzip_meth = 'lib'
                              res = PandoraUtils.unzip_via_lib(zip_local, Pandora.base_dir)
                              p 'unzip_file1 res='+res.inspect
                              if not res
                                Pandora.logger.debug  _('Was not unziped with method')+': lib'
                                unzip_meth = 'util'
                                res = PandoraUtils.unzip_via_util(zip_local, Pandora.base_dir)
                                p 'unzip_file2 res='+res.inspect
                                if not res
                                  Pandora.logger.warn  _('Was not unziped with method')+': util'
                                end
                              end
                              # Copy files to work dir
                              if res
                                Pandora.logger.info  _('Arch is unzipped with method')+': '+unzip_meth
                                # unzip_path = File.join(Pandora.base_dir, 'Pandora-master')
                                unzip_path = nil
                                p 'unzip_mask='+unzip_mask.inspect
                                p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                                unzip_paths.each do |pathfilename|
                                  if File.directory?(pathfilename)
                                    unzip_path = pathfilename
                                    break
                                  end
                                end
                                if unzip_path and Dir.exist?(unzip_path)
                                  begin
                                    p 'Copy '+unzip_path+' to '+Pandora.root
                                    #FileUtils.copy_entry(unzip_path, Pandora.root, true)
                                    FileUtils.cp_r(unzip_path+'/.', Pandora.root)
                                    Pandora.logger.info  _('Files are updated')
                                  rescue => err
                                    res = false
                                    Pandora.logger.warn  _('Cannot copy files from zip arch')+': '+err.message
                                  end
                                  # Remove used arch dir
                                  begin
                                    FileUtils.remove_dir(unzip_path)
                                  rescue => err
                                    Pandora.logger.warn  _('Cannot remove arch dir')+' ['+unzip_path+']: '+err.message
                                  end
                                  step = 255 if res
                                else
                                  Pandora.logger.warn  _('Unzipped directory does not exist')
                                end
                              else
                                Pandora.logger.warn  _('Arch was not unzipped')
                              end
                            else
                              Pandora.logger.warn  _('Cannot download arch')
                            end
                          end
                        end
                      else
                        $window.set_status_field(SF_Update, 'Read only')
                        Pandora.logger.warn  _('Zip is unrewritable')
                      end
                    else
                      $window.set_status_field(SF_Update, 'Size error')
                      Pandora.logger.warn  _('Zip size error')
                    end
                  end
                  update_zip = false
                else   # update with https from sources
                  main_uri = URI('https://raw.githubusercontent.com/Novator/Pandora/master/pandora.rb')
                  http, time, step = connect_http(main_uri, curr_size, step, *proxy)
                  if http
                    Pandora.logger.info  _('Need update')
                    $window.set_status_field(SF_Update, 'Need update')
                    Thread.stop
                    http = reconnect_if_need(http, time, main_uri, *proxy)
                    if http
                      $window.set_status_field(SF_Update, 'Doing')
                      # updating pandora.rb
                      downloaded = update_file(http, main_uri.path, main_script, main_uri.host)
                      # updating other files
                      UPD_FileList.each do |fn|
                        pfn = File.join(Pandora.root, fn)
                        if File.exist?(pfn) and (not File.stat(pfn).writable?)
                          downloaded = false
                          Pandora.logger.warn _('Not exist or read only')+': '+pfn
                        else
                          downloaded = downloaded and \
                            update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                        end
                      end
                      if downloaded
                        step = 255
                      else
                        Pandora.logger.warn  _('Direct download error')
                      end
                    end
                  end
                  update_zip = true
                end
              end
              if step == 255
                PandoraUtils.set_param('last_update', Time.now)
                $window.set_status_field(SF_Update, 'Need restart')
                Thread.stop
                Kernel.abort('Pandora is updated. Run it again')
              elsif step<250
                $window.set_status_field(SF_Update, 'Load error')
              end
            else
              $window.set_status_field(SF_Update, 'Read only')
            end
          else
            $window.set_status_field(SF_Update, 'Size error')
          end
          $download_thread = nil
        end
      end
    end

    # Do action with selected record
    # RU: Выполнить действие над выделенной записью
    def self.act_panobject(tree_view, action)

      # Get icon associated with panobject
      # RU: Взять иконку ассоциированную с панобъектом
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
          if first_lab_widget.is_a? ::Gtk::Image
            image = first_lab_widget
            panobj_icon = $window.render_icon(image.stock, ::Gtk::IconSize::MENU).dup
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
        lang = PandoraModel.text_to_lang(Pandora.config.lang)
        panstate = 0
        created0 = nil
        creator0 = nil
        if path and (not new_act)
          iter = store.get_iter(path)
          id = iter[0]
          sel = panobject.select('id='+id.to_s, true)
          panhash0 = panobject.namesvalues['panhash']
          lang = panhash0[1].ord if panhash0 and (panhash0.size>1)
          lang ||= 0
          panstate = panobject.namesvalues['panstate']
          panstate ||= 0
          if (panobject.is_a? PandoraModel::Created)
            created0 = panobject.namesvalues['created']
            creator0 = panobject.namesvalues['creator']
          end
        end

        panobjecticon = get_panobject_icon(panobject)

        if action=='Delete'
          if id and sel[0]
            info = panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
            dialog = ::Gtk::MessageDialog.new($window, ::Gtk::Dialog::MODAL | ::Gtk::Dialog::DESTROY_WITH_PARENT,
              ::Gtk::MessageDialog::QUESTION,
              ::Gtk::MessageDialog::BUTTONS_OK_CANCEL,
              _('Record will be deleted. Sure?')+"\n["+info+']')
            dialog.title = _('Deletion')+': '+panobject.sname
            dialog.default_response = ::Gtk::Dialog::RESPONSE_OK
            dialog.icon = panobjecticon if panobjecticon
            if dialog.run == ::Gtk::Dialog::RESPONSE_OK
              res = panobject.update(nil, nil, 'id='+id.to_s)
              tree_view.sel.delete_if {|row| row[0]==id }
              store.remove(iter)
              #iter.next!
              pt = path.indices[0]
              pt = tree_view.sel.size-1 if (pt > tree_view.sel.size-1)
              tree_view.set_cursor(::Gtk::TreePath.new(pt), column, false) if (pt >= 0)
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

          dialog.lang_entry.entry.text = PandoraModel.lang_to_text(lang) if lang

          if edit
            count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
            trust = nil
            p PandoraUtils.bytes_to_hex(panhash0)
            p 'trust or num'
            trust_or_num = PandoraCrypto.trust_in_panobj(panhash0)
            trust = trust_or_num if (trust_or_num.is_a? Float)
            dialog.vouch_btn.active = (trust_or_num != nil)
            dialog.vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
            dialog.trust_scale.sensitive = (trust != nil)
            #dialog.trust_scale.signal_emit('value-changed')
            trust ||= 0.0
            dialog.trust_scale.value = trust
            #dialog.rate_label.text = rate.to_s

            dialog.keep_btn.active = (PandoraModel::PSF_Support & panstate)>0

            pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
            dialog.public_btn.active = pub_level
            dialog.public_btn.inconsistent = (pub_level == nil)
            dialog.public_scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
            dialog.public_scale.sensitive = pub_level

            p 'follow'
            p follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
            dialog.follow_btn.active = follow
            dialog.follow_btn.inconsistent = (follow == nil)

            #dialog.lang_entry.active_text = lang.to_s
            #trust_lab = dialog.trust_btn.children[0]
            #trust_lab.modify_fg(::Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
          else  #new or copy
            key = PandoraCrypto.current_key(false, false)
            key_inited = (key and key[PandoraCrypto::KV_Obj])
            dialog.keep_btn.active = true
            dialog.follow_btn.active = key_inited
            dialog.vouch_btn.active = key_inited
            dialog.trust_scale.sensitive = key_inited
            if not key_inited
              dialog.follow_btn.inconsistent = true
              dialog.vouch_btn.inconsistent = true
              dialog.public_btn.inconsistent = true
            end
            dialog.public_scale.sensitive = false
          end

          st_text = panobject.panhash_formula
          st_text = st_text + ' [#'+panobject.panhash(sel[0], lang, true, true)+']' if sel and sel.size>0
          Pandora::Gtk.set_statusbar_text(dialog.statusbar, st_text)

          if panobject.class==PandoraModel::Key
            mi = ::Gtk::MenuItem.new("Действия")
            menu = ::Gtk::MenuBar.new
            menu.append(mi)

            menu2 = ::Gtk::Menu.new
            menuitem = ::Gtk::MenuItem.new("Генерировать")
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

          dialog.run2 do
            # take value from form
            dialog.fields.each do |field|
              entry = field[FI_Widget]
              field[FI_Value] = entry.text
            end

            # fill hash of values
            flds_hash = {}
            dialog.fields.each do |field|
              type = field[FI_Type]
              view = field[FI_View]
              val = field[FI_Value]

              if (panobject.ider=='Parameter') and (field[FI_Id]=='value')
                par_type = panobject.field_val('type', sel[0])
                setting = panobject.field_val('setting', sel[0])
                ps = PandoraUtils.decode_param_setting(setting)
                view = ps['view']
                view ||= PandoraUtils.pantype_to_view(par_type)
              end

              p 'val, type, view='+[val, type, view].inspect
              val = PandoraUtils.view_to_val(val, type, view)
              val = '@'+val if val and (val != '') and ((view=='blob') or (view=='text'))
              flds_hash[field[FI_Id]] = val
            end
            dialog.text_fields.each do |field|
              textview = field[FI_Widget2]
              if (not textview.destroyed?) and (textview.is_a? ::Gtk::TextView)
                text = textview.buffer.text
                if text and (text.size>0)
                  field[FI_Value] = text
                  flds_hash[field[FI_Id]] = field[FI_Value]
                end
              end
            end
            lg = nil
            begin
              lg = PandoraModel.text_to_lang(dialog.lang_entry.entry.text)
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
            panstate = panstate | PandoraModel::PSF_Support if dialog.keep_btn.active?
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
                  sel[0].each_with_index do |c,i|
                    tree_view.sel[ind][i] = c
                  end
                  iter[0] = id
                  store.row_changed(path, iter)
                else
                  #p '---------INSERT'
                  tree_view.sel << sel[0]
                  iter = store.append
                  iter[0] = id
                  tree_view.set_cursor(::Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
                end

                if not dialog.vouch_btn.inconsistent?
                  PandoraCrypto.unsign_panobject(panhash0, true)
                  if dialog.vouch_btn.active?
                    trust = (dialog.trust_scale.value*127).round
                    PandoraCrypto.sign_panobject(panobject, trust)
                  end
                end

                if not dialog.follow_btn.inconsistent?
                  PandoraModel.act_relation(nil, panhash0, RK_Follow, :delete, \
                    true, true)
                  if (panhash != panhash0)
                    PandoraModel.act_relation(nil, panhash, RK_Follow, :delete, \
                      true, true)
                  end
                  if dialog.follow_btn.active?
                    PandoraModel.act_relation(nil, panhash, RK_Follow, :create, \
                      true, true)
                  end
                end

                if not dialog.public_btn.inconsistent?
                  public_level = RK_MinPublic + (dialog.public_scale.value*10).round+10
                  p 'public_level='+public_level.inspect
                  PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :delete, \
                    true, true)
                  if (panhash != panhash0)
                    PandoraModel.act_relation(nil, panhash, RK_MinPublic, :delete, \
                      true, true)
                  end
                  if dialog.public_btn.active?
                    PandoraModel.act_relation(nil, panhash, public_level, :create, \
                      true, true)
                  end
                end
              end
            end
          end
        end
      elsif action=='Dialog'
        Pandora::Gtk.show_panobject_list(PandoraModel::Person)
      end
    end

    # Showing panobject list
    # RU: Показ списка панобъектов
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
      store = ::Gtk::ListStore.new(Integer)
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
          renderer = ::Gtk::CellRendererText.new
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
              val = val[0,46]
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
      sw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
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
        if widget.is_a? ::Gtk::ImageMenuItem
          animage = widget.image
        elsif widget.is_a? ::Gtk::ToolButton
          animage = widget.icon_widget
        else
          animage = nil
        end
        image = nil
        if animage
          image = ::Gtk::Image.new(animage.stock, ::Gtk::IconSize::MENU)
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
          treeview.set_cursor(::Gtk::TreePath.new(treeview.sel.size-1), nil, false)
        end
        treeview.grab_focus
      end

      menu = ::Gtk::Menu.new
      menu.append(create_menu_item(['Create', ::Gtk::Stock::NEW, _('Create'), 'Insert'], treeview))
      menu.append(create_menu_item(['Edit', ::Gtk::Stock::EDIT, _('Edit'), 'Return'], treeview))
      menu.append(create_menu_item(['Delete', ::Gtk::Stock::DELETE, _('Delete'), 'Delete'], treeview))
      menu.append(create_menu_item(['Copy', ::Gtk::Stock::COPY, _('Copy'), '<control>Insert'], treeview))
      menu.append(create_menu_item(['-', nil, nil], treeview))
      menu.append(create_menu_item(['Dialog', ::Gtk::Stock::MEDIA_PLAY, _('Dialog'), '<control>D'], treeview))
      menu.append(create_menu_item(['Opinion', ::Gtk::Stock::JUMP_TO, _('Opinions'), '<control>BackSpace'], treeview))
      menu.append(create_menu_item(['Connect', ::Gtk::Stock::CONNECT, _('Connect'), '<control>N'], treeview))
      menu.append(create_menu_item(['Relate', ::Gtk::Stock::INDEX, _('Relate'), '<control>R'], treeview))
      menu.append(create_menu_item(['-', nil, nil], treeview))
      menu.append(create_menu_item(['Convert', ::Gtk::Stock::CONVERT, _('Convert')], treeview))
      menu.append(create_menu_item(['Import', ::Gtk::Stock::OPEN, _('Import')], treeview))
      menu.append(create_menu_item(['Export', ::Gtk::Stock::SAVE, _('Export')], treeview))
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

    $media_buf_size = 50
    $send_media_queues = []
    $send_media_rooms = {}

    # Take pointer index for sending by room
    # RU: Взять индекс указателя для отправки по id комнаты
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

    # Check pointer index for sending by room
    # RU: Проверить индекс указателя для отправки по id комнаты
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

    # Clear pointer index for sending for room
    # RU: Сбросить индекс указателя для отправки для комнаты
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

    # Construct room id
    # RU: Создать идентификатор комнаты
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

    # Find active sender
    # RU: Найти активного отправителя
    def self.find_another_active_sender(not_this=nil)
      res = nil
      $window.notebook.children.each do |child|
        if (child != not_this) and (child.is_a? DialogScrollWin) and child.vid_button.active?
          return child
        end
      end
      res
    end

    # Get view parameters
    # RU: Взять параметры вида
    def self.get_view_params
      $load_history_count = Pandora::Utils.get_param('load_history_count')
      $sort_history_mode = Pandora::Utils.get_param('sort_history_mode')
    end

    # Get main parameters
    # RU: Взять основные параметры
    def self.get_main_params
      get_view_params
    end

    # About dialog hooks
    # RU: Обработчики диалога "О программе"
    ::Gtk::AboutDialog.set_url_hook do |about, link|
      if Pandora::Utils.os_family=='windows' then a1='start'; a2='' else a1='xdg-open'; a2=' &' end;
      system(a1+' '+link+a2)
    end
    ::Gtk::AboutDialog.set_email_hook do |about, link|
      if Pandora::Utils.os_family=='windows' then a1='start'; a2='' else a1='xdg-email'; a2=' &' end;
      system(a1+' '+link+a2)
    end

    # Show About dialog
    # RU: Показ окна "О программе"
    def self.show_about
      dlg = ::Gtk::AboutDialog.new
      dlg.transient_for = $window
      dlg.icon = $window.icon
      dlg.name = $window.title
      dlg.version = '0.3'
      dlg.logo = Gdk::Pixbuf.new(File.join(Pandora.view_dir, 'pandora.png'))
      dlg.authors = [_('Michael Galyuk')+' <robux@mail.ru>']
      dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
      dlg.comments = _('P2P national network')
      dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
      begin
        file = File.open(File.join(Pandora.root, 'LICENSE.TXT'), 'r')
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
            child.online_button.safe_set_active(known_node != nil)
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
        dialog = ::Gtk::MessageDialog.new($window, \
          ::Gtk::Dialog::MODAL | ::Gtk::Dialog::DESTROY_WITH_PARENT, \
          ::Gtk::MessageDialog::INFO, ::Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
          mes = _('No one')+' '+mes+' '+_('is not found')+".\n"+_('Add nodes and do hunt'))
        dialog.title = _('Note')
        dialog.default_response = ::Gtk::Dialog::RESPONSE_OK
        dialog.icon = $window.icon
        if (dialog.run == ::Gtk::Dialog::RESPONSE_OK)
          Pandora::Gtk.show_panobject_list(PandoraModel::Node, nil, nil, true)
        end
        dialog.destroy
      end
      sw
    end

    # Showing search panel
    # RU: Показать панель поиска
    def self.show_search_panel(text=nil)
      sw = SearchScrollWin.new(text)

      image = ::Gtk::Image.new(::Gtk::Stock::FIND, ::Gtk::IconSize::MENU)
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

      hpaned = ::Gtk::HPaned.new
      hpaned.border_width = 2
      sw.add_with_viewport(hpaned)


      list_sw = ::Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = ::Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(::Gtk::POLICY_NEVER, ::Gtk::POLICY_AUTOMATIC)

      list_store = ::Gtk::ListStore.new(String)

      user_iter = list_store.append
      user_iter[0] = _('Profile')
      user_iter = list_store.append
      user_iter[0] = _('Events')

      # create tree view
      list_tree = ::Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = ::Gtk::CellRendererText.new
      column = ::Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      #renderer = ::Gtk::CellRendererText.new
      #column = ::Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
      #column.set_sort_column_id(1)
      #list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      hpaned.pack1(list_sw, false, true)
      hpaned.pack2(::Gtk::Label.new('test'), true, true)
      list_sw.show_all


      image = ::Gtk::Image.new(::Gtk::Stock::HOME, ::Gtk::IconSize::MENU)
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

    # Show session list
    # RU: Показать список сеансов
    def self.show_session_panel(session=nil)
      $window.notebook.children.each do |child|
        if (child.is_a? SessionScrollWin)
          $window.notebook.page = $window.notebook.children.index(child)
          child.update_btn.clicked
          return
        end
      end
      sw = SessionScrollWin.new(session)

      image = ::Gtk::Image.new(::Gtk::Stock::JUSTIFY_FILL, ::Gtk::IconSize::MENU)
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
    class PandoraStatusIcon < ::Gtk::StatusIcon
      attr_accessor :main_icon, :play_sounds, :online, :hide_on_minimize

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
          @main_icon = $window.render_icon(::Gtk::Stock::HOME, ::Gtk::IconSize::LARGE_TOOLBAR)
        end
        @base_icon = @main_icon

        @online_icon = nil
        begin
          @online_icon = Gdk::Pixbuf.new(File.join(Pandora.view_dir, 'online.ico'))
        rescue Exception
        end
        if not @online_icon
          @online_icon = $window.render_icon(::Gtk::Stock::INFO, ::Gtk::IconSize::LARGE_TOOLBAR)
        end

        begin
          @message_icon = Gdk::Pixbuf.new(File.join(Pandora.view_dir, 'message.ico'))
        rescue Exception
        end
        if not @message_icon
          @message_icon = $window.render_icon(::Gtk::Stock::MEDIA_PLAY, ::Gtk::IconSize::LARGE_TOOLBAR)
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
        menu = ::Gtk::Menu.new

        checkmenuitem = ::Gtk::CheckMenuItem.new(_('Flash on new'))
        checkmenuitem.active = @flash_on_new
        checkmenuitem.signal_connect('activate') do |w|
          @flash_on_new = w.active?
          set_message(@message)
        end
        menu.append(checkmenuitem)

        checkmenuitem = ::Gtk::CheckMenuItem.new(_('Update window icon'))
        checkmenuitem.active = @update_win_icon
        checkmenuitem.signal_connect('activate') do |w|
          @update_win_icon = w.active?
          $window.icon = @base_icon
        end
        menu.append(checkmenuitem)

        checkmenuitem = ::Gtk::CheckMenuItem.new(_('Play sounds'))
        checkmenuitem.active = @play_sounds
        checkmenuitem.signal_connect('activate') do |w|
          @play_sounds = w.active?
        end
        menu.append(checkmenuitem)

        checkmenuitem = ::Gtk::CheckMenuItem.new(_('Hide on minimize'))
        checkmenuitem.active = @hide_on_minimize
        checkmenuitem.signal_connect('activate') do |w|
          @hide_on_minimize = w.active?
        end
        menu.append(checkmenuitem)

        menuitem = ::Gtk::ImageMenuItem.new(::Gtk::Stock::PROPERTIES)
        alabel = menuitem.children[0]
        alabel.set_text(_('All parameters')+'..', true)
        menuitem.signal_connect('activate') do |w|
          icon_activated(false, true)
          Pandora::Gtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
        end
        menu.append(menuitem)

        menuitem = ::Gtk::SeparatorMenuItem.new
        menu.append(menuitem)

        menuitem = ::Gtk::MenuItem.new(_('Show/Hide'))
        menuitem.signal_connect('activate') do |w|
          icon_activated(false)
        end
        menu.append(menuitem)

        menuitem = ::Gtk::ImageMenuItem.new(::Gtk::Stock::QUIT)
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
          if (not top_sens) or ($window.has_toplevel_focus? or (Pandora::Utils.os_family=='windows'))
            $window.hide
          else
            $window.do_menu_act('Activate')
          end
        else
          $window.do_menu_act('Activate')
          update_icon if @update_win_icon
          if @message and (not force_show)
            page = $window.notebook.page
            if (page >= 0)
              cur_page = $window.notebook.get_nth_page(page)
              if cur_page.is_a? Pandora::Gtk::DialogScrollWin
                cur_page.update_state(false, cur_page)
              end
            else
              set_message(nil) if ($window.notebook.n_pages == 0)
            end
          end
        end
      end
    end  #--PandoraStatusIcon

    # Captcha panel
    # RU: Панель с капчой
    class CaptchaHPaned < ::Gtk::HPaned
      attr_accessor :csw

      # Show panel
      # RU: Показать панель
      def initialize(first_child)
        super()
        @first_child = first_child
        self.pack1(@first_child, true, true)
        @csw = nil
      end

      # Show capcha
      # RU: Показать капчу
      def show_captcha(srckey, captcha_buf=nil, clue_text=nil, node=nil)
        res = nil
        if captcha_buf and (not @csw)
          @csw = ::Gtk::ScrolledWindow.new(nil, nil)
          csw = @csw

          csw.signal_connect('destroy-event') do
            show_captcha(srckey)
          end

          @vbox = ::Gtk::VBox.new
          vbox = @vbox

          csw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
          csw.add_with_viewport(vbox)

          pixbuf_loader = Gdk::PixbufLoader.new
          pixbuf_loader.last_write(captcha_buf) if captcha_buf

          label = ::Gtk::Label.new(_('Far node'))
          vbox.pack_start(label, false, false, 2)
          entry = ::Gtk::Entry.new
          node_text = PandoraUtils.bytes_to_hex(srckey)
          node_text = node if (not node_text) or (node_text=='')
          node_text ||= ''
          entry.text = node_text
          entry.editable = false
          vbox.pack_start(entry, false, false, 2)

          image = ::Gtk::Image.new(pixbuf_loader.pixbuf)
          vbox.pack_start(image, false, false, 2)

          clue_text ||= ''
          clue, length, symbols = clue_text.split('|')
          #p '    [clue, length, symbols]='+[clue, length, symbols].inspect

          len = 0
          begin
            len = length.to_i if length
          rescue
          end

          label = ::Gtk::Label.new(_('Enter text from picture'))
          vbox.pack_start(label, false, false, 2)

          captcha_entry = Pandora::Gtk::MaskEntry.new
          captcha_entry.max_length = len
          if symbols
            mask = symbols.downcase+symbols.upcase
            captcha_entry.mask = mask
          end

          okbutton = ::Gtk::Button.new(::Gtk::Stock::OK)
          okbutton.signal_connect('clicked') do
            text = captcha_entry.text
            yield(text) if block_given?
            show_captcha(srckey)
          end

          cancelbutton = ::Gtk::Button.new(::Gtk::Stock::CANCEL)
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
          Pandora::Gtk.hack_enter_bug(captcha_entry)

          ew = 150
          if len>0
            str = label.text
            label.text = 'W'*(len+1)
            ew,lh = label.size_request
            label.text = str
          end

          captcha_entry.width_request = ew
          align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
          align.add(captcha_entry)
          vbox.pack_start(align, false, false, 2)
          #capdialog.def_widget = entry

          hbox = ::Gtk::HBox.new
          hbox.pack_start(okbutton, true, true, 2)
          hbox.pack_start(cancelbutton, true, true, 2)

          vbox.pack_start(hbox, false, false, 2)

          if clue
            label = ::Gtk::Label.new(_(clue))
            vbox.pack_start(label, false, false, 2)
          end
          if length
            label = ::Gtk::Label.new(_('Length')+'='+length.to_s)
            vbox.pack_start(label, false, false, 2)
          end
          if symbols
            sym_text = _('Symbols')+': '+symbols.to_s
            i = 30
            while i<sym_text.size do
              sym_text = sym_text[0,i]+"\n"+sym_text[i+1..-1]
              i += 31
            end
            label = ::Gtk::Label.new(sym_text)
            vbox.pack_start(label, false, false, 2)
          end

          csw.border_width = 1;
          csw.set_size_request(250, -1)
          self.border_width = 2
          self.pack2(csw, true, true)  #hpaned3                                      9
          csw.show_all
          full_width = $window.allocation.width
          self.position = full_width-250 #self.max_position #@csw.width_request
          Pandora::Gtk.hack_grab_focus(captcha_entry)
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


  end
end
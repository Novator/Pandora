module Pandora
  module Gtk
    # Search panel
    # RU: Панель поиска
    class SearchScrollWin < ::Gtk::ScrolledWindow
      attr_accessor :text

      include Pandora::Gtk

      # Search in bases
      # RU: Поиск в базах
      def search_in_bases(text, th, bases='auto')
        res = nil
        while th[:processing] and (not res)
          model = PandoraUtils.get_model('Person')
          fields = nil
          sort = nil
          limit = nil
          filter = [['first_name LIKE', text]]
          res = model.select(filter, false, fields, sort, limit, 3)
          res ||= []
        end
        res
      end

      # Show search window
      # RU: Показать окно поиска
      def initialize(text=nil)
        super(nil, nil)

        @text = nil
        @search_thread = nil

        set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        border_width = 0

        vpaned = ::Gtk::VPaned.new

        search_btn = ::Gtk::ToolButton.new(::Gtk::Stock::FIND, _('Search'))
        search_btn.tooltip_text = _('Start searching')
        PandoraGtk.set_readonly(search_btn, true)

        stop_btn = ::Gtk::ToolButton.new(::Gtk::Stock::STOP, _('Stop'))
        stop_btn.tooltip_text = _('Stop searching')
        PandoraGtk.set_readonly(stop_btn, true)

        prev_btn = ::Gtk::ToolButton.new(::Gtk::Stock::GO_BACK, _('Previous'))
        prev_btn.tooltip_text = _('Previous search')
        PandoraGtk.set_readonly(prev_btn, true)

        next_btn = ::Gtk::ToolButton.new(::Gtk::Stock::GO_FORWARD, _('Next'))
        next_btn.tooltip_text = _('Next search')
        PandoraGtk.set_readonly(next_btn, true)

        search_entry = ::Gtk::Entry.new
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
          cant_find = (@search_thread or (search_entry.text.size==0))
          PandoraGtk.set_readonly(search_btn, cant_find)
          false
        end

        kind_entry = ::Gtk::Combo.new
        kind_entry.set_popdown_strings(['auto','person','file','all'])
        #kind_entry.entry.select_region(0, -1)

        #kind_entry = ::Gtk::ComboBox.new(true)
        #kind_entry.append_text('auto')
        #kind_entry.append_text('person')
        #kind_entry.append_text('file')
        #kind_entry.append_text('all')
        #kind_entry.active = 0
        #kind_entry.wrap_width = 3
        #kind_entry.has_frame = true

        kind_entry.set_size_request(100, -1)

        hbox = ::Gtk::HBox.new
        hbox.pack_start(kind_entry, false, false, 0)
        hbox.pack_start(search_btn, false, false, 0)
        hbox.pack_start(search_entry, true, true, 0)
        hbox.pack_start(stop_btn, false, false, 0)
        hbox.pack_start(prev_btn, false, false, 0)
        hbox.pack_start(next_btn, false, false, 0)

        option_box = ::Gtk::HBox.new

        vbox = ::Gtk::VBox.new
        vbox.pack_start(hbox, false, true, 0)
        vbox.pack_start(option_box, false, true, 0)

        #kind_btn = Pandora::Gtk::SafeToggleToolButton.new(::Gtk::Stock::PROPERTIES)
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
          #update_btn.clicked
        end
        local_btn.safe_set_active(true)

        active_btn = SafeCheckButton.new(_('active only'), true)
        active_btn.safe_signal_clicked do |widget|
          #update_btn.clicked
        end
        active_btn.safe_set_active(true)

        hunt_btn = SafeCheckButton.new(_('hunt!'), true)
        hunt_btn.safe_signal_clicked do |widget|
          #update_btn.clicked
        end
        hunt_btn.safe_set_active(true)

        option_box.pack_start(local_btn, false, true, 1)
        option_box.pack_start(active_btn, false, true, 1)
        option_box.pack_start(hunt_btn, false, true, 1)

        list_sw = ::Gtk::ScrolledWindow.new(nil, nil)
        list_sw.shadow_type = ::Gtk::SHADOW_ETCHED_IN
        list_sw.set_policy(::Gtk::POLICY_NEVER, ::Gtk::POLICY_AUTOMATIC)

        list_store = ::Gtk::ListStore.new(Integer, String)

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
              res = search_in_bases(text, th, 'auto')
              if res.is_a? Array
                res.each_with_index do |row, i|
                  user_iter = list_store.append
                  user_iter[0] = i
                  user_iter[1] = row.to_s
                end
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
        list_tree = ::Gtk::TreeView.new(list_store)
        #list_tree.rules_hint = true
        #list_tree.search_column = CL_Name

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
        column.set_sort_column_id(0)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
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
  end
end
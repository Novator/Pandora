module Pandora
  module Gtk

    # Main window
    # RU: Главное окно
    class MainWindow < ::Gtk::Window
      attr_accessor :hunter_count, :listener_count, :fisher_count, :log_view, :notebook, \
        :cvpaned, :pool, :focus_timer, :title_view, :do_on_show


      # Update status of connections
      # RU: Обновить состояние подключений
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

      # Change listener button state
      # RU: Изменить состояние кнопки слушателя
      def correct_lis_btn_state
        tool_btn = $toggle_buttons[Pandora::Gtk::SF_Listen]
        tool_btn.safe_set_active($listen_thread != nil) if tool_btn
      end

      # Change hunter button state
      # RU: Изменить состояние кнопки охотника
      def correct_hunt_btn_state
        tool_btn = $toggle_buttons[SF_Hunt]
        tool_btn.safe_set_active($hunter_thread != nil) if tool_btn
      end

      $statusbar = nil
      $status_fields = []

      # Add field to statusbar
      # RU: Добавляет поле в статусбар
      def add_status_field(index, text)
        $statusbar.pack_start(::Gtk::SeparatorToolItem.new, false, false, 0) if ($status_fields != [])
        btn = ::Gtk::Button.new(text)
        btn.relief = ::Gtk::RELIEF_NONE
        if block_given?
          btn.signal_connect('clicked') do |*args|
            yield(*args)
          end
        end
        $statusbar.pack_start(btn, false, false, 0)
        $status_fields[index] = btn
      end

      # Set properties of fiels in statusbar
      # RU: Задаёт свойства поля в статусбаре
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
            $toggle_buttons[index].safe_set_active(toggle)
          end
        end
      end

      # Get fiels of statusbar
      # RU: Возвращает поле статусбара
      def get_status_field(index)
        $status_fields[index]
      end

      TV_Name    = 0
      TV_NameF   = 1
      TV_Family  = 2
      TV_NameN   = 3

      MaxTitleLen = 15

      # Construct room title
      # RU: Задаёт осмысленный заголовок окна
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

      # Export table to file
      # RU: Выгрузить таблицу в файл
      def export_table(panobject)

        ider = panobject.ider
        filename = File.join(Pandora.files_dir, ider+'.csv')
        separ = '|'

        File.open(filename, 'w') do |file|
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
            file.puts(line)
          end
        end

        Pandora.logger.info  _('Table exported')+': '+filename
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
            Pandora::Gtk.show_about
          when 'Close'
            if notebook.page >= 0
              page = notebook.get_nth_page(notebook.page)
              tab = notebook.get_tab_label(page)
              close_btn = tab.children[tab.children.size-1].children[0]
              close_btn.clicked
            end
          when 'Create','Edit','Delete','Copy', 'Dialog', 'Convert', 'Import', 'Export'
            if (not treeview) and (notebook.page >= 0)
              sw = notebook.get_nth_page(notebook.page)
              treeview = sw.children[0]
            end
            if treeview and (treeview.is_a? SubjTreeView)
              if command=='Convert'
                panobject = treeview.panobject
                panobject.update(nil, nil, nil)
                panobject.class.tab_fields(true)
              elsif command=='Import'
                p 'import'
              elsif command=='Export'
                export_table(treeview.panobject)
              else
                Pandora::Gtk.act_panobject(treeview, command)
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
            from_time = Time.now.to_i - 5*24*3600
            trust = 0.5
            #list = PandoraModel.public_records(nil, nil, nil, 1.chr)
            #list = PandoraModel.follow_records
            #list = PandoraModel.get_panhashes_by_kinds([1,11], from_time)
            list = PandoraModel.created_records(nil, nil, nil, nil)
            p 'list='+list.inspect

            #if list
            #  list.each do |panhash|
            #    p '----------------'
            #    kind = PandoraUtils.kind_from_panhash(panhash)
            #    p [panhash, kind].inspect
            #    p res = PandoraModel.get_record_by_panhash(kind, panhash, true)
            #  end
            #end


            return


            p res44 = OpenSSL::Digest::RIPEMD160.new

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

            #p Pandora::Utils.get_param('base_id')
          when 'Profile'
            Pandora::Gtk.show_profile_panel
          when 'Search'
            Pandora::Gtk.show_search_panel
          when 'Session'
            Pandora::Gtk.show_session_panel
          else
            panobj_id = command
            if PandoraModel.const_defined? panobj_id
              panobject_class = PandoraModel.const_get(panobj_id)
              Pandora::Gtk.show_panobject_list(panobject_class, widget)
            else
              Pandora.logger.warn  _('Menu handler is not defined yet')+' "'+panobj_id+'"'
            end
        end
      end

      # Menu structure
      # RU: Структура меню
      MENU_ITEMS =
        [[nil, nil, '_World'],
        ['Person', ::Gtk::Stock::ORIENTATION_PORTRAIT, 'People', '<control>E'],
        ['Community', nil, 'Communities'],
        ['Blob', ::Gtk::Stock::HARDDISK, 'Files', '<control>J'], #::Gtk::Stock::FILE
        ['-', nil, '-'],
        ['City', nil, 'Towns'],
        ['Street', nil, 'Streets'],
        ['Address', nil, 'Addresses'],
        ['Contact', nil, 'Contacts'],
        ['Country', nil, 'States'],
        ['Language', nil, 'Languages'],
        ['Word', ::Gtk::Stock::SPELL_CHECK, 'Words'],
        ['Relation', nil, 'Relations'],
        ['-', nil, '-'],
        ['Opinion', nil, 'Opinions'],
        ['Task', nil, 'Tasks'],
        ['Message', nil, 'Messages'],
        [nil, nil, '_Business'],
        ['Advertisement', nil, 'Advertisements'],
        ['Transfer', nil, 'Transfers'],
        ['-', nil, '-'],
        ['Order', nil, 'Orders'],
        ['Deal', nil, 'Deals'],
        ['Waybill', nil, 'Waybills'],
        ['-', nil, '-'],
        ['Debenture', nil, 'Debentures'],
        ['Deposit', nil, 'Deposits'],
        ['Guarantee', nil, 'Guarantees'],
        ['Insurer', nil, 'Insurers'],
        ['-', nil, '-'],
        ['Product', nil, 'Products'],
        ['Service', nil, 'Services'],
        ['Currency', nil, 'Currency'],
        ['Storage', nil, 'Storages'],
        ['Estimate', nil, 'Estimates'],
        ['Contract', nil, 'Contracts'],
        ['Report', nil, 'Reports'],
        [nil, nil, '_Region'],
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
        [nil, nil, '_Node'],
        ['Parameter', ::Gtk::Stock::PROPERTIES, 'Parameters'],
        ['-', nil, '-'],
        ['Key', ::Gtk::Stock::DIALOG_AUTHENTICATION, 'Keys'],
        ['Sign', nil, 'Signs'],
        ['Node', ::Gtk::Stock::NETWORK, 'Nodes'],
        ['Event', nil, 'Events'],
        ['Fishhook', nil, 'Fishhooks'],
        ['Session', ::Gtk::Stock::JUSTIFY_FILL, 'Sessions', '<control>S'],
        ['-', nil, '-'],
        ['Authorize', nil, 'Authorize', '<control>U'],
        ['Listen', ::Gtk::Stock::CONNECT, 'Listen', '<control>L', :check],
        ['Hunt', ::Gtk::Stock::REFRESH, 'Hunt', '<control>H', :check],
        ['Search', ::Gtk::Stock::FIND, 'Search', '<control>T'],
        ['Exchange', nil, 'Exchange'],
        ['-', nil, '-'],
        ['Profile', ::Gtk::Stock::HOME, 'Profile'],
        ['Wizard', ::Gtk::Stock::PREFERENCES, 'Wizards'],
        ['-', nil, '-'],
        ['Close', ::Gtk::Stock::CLOSE, '_Close', '<control>W'],
        ['Quit', ::Gtk::Stock::QUIT, '_Quit', '<control>Q'],
        ['-', nil, '-'],
        ['About', ::Gtk::Stock::ABOUT, '_About']
        ]

      # Fill main menu
      # RU: Заполнить главное меню
      def fill_menubar(menubar)
        menu = nil
        MENU_ITEMS.each do |mi|
          if mi[0]==nil or menu==nil
            menuitem = ::Gtk::MenuItem.new(_(mi[2]))
            menubar.append(menuitem)
            menu = ::Gtk::Menu.new
            menuitem.set_submenu(menu)
          else
            menuitem = Pandora::Gtk.create_menu_item(mi)
            menu.append(menuitem)
          end
        end
      end

      # Fill toolbar
      # RU: Заполнить панель инструментов
      def fill_toolbar(toolbar)
        MENU_ITEMS.each do |mi|
          stock = mi[1]
          if stock
            command = mi[0]
            label = mi[2]
            if command and (command != '-') and label and (label != '-')
              toggle = nil
              toggle = false if mi[4]
              btn = Pandora::Gtk.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
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

      # Initialize scheduler
      # RU: Инициировать планировщик
      def init_scheduler(interval=nil)
        if (not @scheduler) and interval
          @scheduler_interval = interval if interval
          @scheduler_interval ||= 1000
          @scheduler = Thread.new do
            while ((@scheduler_interval.is_a? Integer) and @scheduler_interval>=100)
              next_step = true

              # Scheduler (task executer)
              Thread.new do
                message = 'Message here'
                #dialog = ::Gtk::MessageDialog.new($window, \
                #  ::Gtk::Dialog::MODAL | ::Gtk::Dialog::DESTROY_WITH_PARENT, \
                #  ::Gtk::MessageDialog::INFO, ::Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
                #  message)
                #dialog.title = _('Task')
                #dialog.default_response = ::Gtk::Dialog::RESPONSE_OK
                #dialog.icon = $window.icon
                #if (dialog.run == ::Gtk::Dialog::RESPONSE_OK)
                #  p 'Here need to switch of the task'
                #end
                #dialog.destroy

                if not @scheduler_dialog
                  @scheduler_dialog = Pandora::Gtk::AdvancedDialog.new(_('Tasks'))
                  dialog = @scheduler_dialog
                  dialog.set_default_size(420, 250)
                  vbox = ::Gtk::VBox.new
                  dialog.viewport.add(vbox)

                  label = ::Gtk::Label.new(_('Message'))
                  vbox.pack_start(label, false, false, 2)
                  user_entry = ::Gtk::Entry.new
                  user_entry.text = message
                  vbox.pack_start(user_entry, false, false, 2)


                  label = ::Gtk::Label.new(_('Here'))
                  vbox.pack_start(label, false, false, 2)
                  pass_entry = ::Gtk::Entry.new
                  pass_entry.width_request = 250
                  align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
                  align.add(pass_entry)
                  vbox.pack_start(align, false, false, 2)
                  vbox.pack_start(pass_entry, false, false, 2)

                  dialog.def_widget = user_entry

                  dialog.run2 do
                    p 'reset dialog flag'
                  end
                  @scheduler_dialog = nil
                end

              end

              # Base gabager

              # List gabager

              # GUI updater (list, traffic)

              sleep(@scheduler_interval/1000)
              Thread.pass
            end
            @scheduler = nil
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
          main_icon = Gdk::Pixbuf.new(File.join(Pandora.view_dir, 'pandora.ico'))
        rescue Exception
        end
        if not main_icon
          main_icon = $window.render_icon(::Gtk::Stock::HOME, ::Gtk::IconSize::LARGE_TOOLBAR)
        end
        if main_icon
          $window.icon = main_icon
          ::Gtk::Window.default_icon = $window.icon
        end

        $group = ::Gtk::AccelGroup.new
        $window.add_accel_group($group)

        menubar = ::Gtk::MenuBar.new
        fill_menubar(menubar)

        toolbar = ::Gtk::Toolbar.new
        toolbar.toolbar_style = ::Gtk::Toolbar::Style::ICONS
        fill_toolbar(toolbar)

        @notebook = ::Gtk::Notebook.new
        @notebook.scrollable = true
        notebook.signal_connect('switch-page') do |widget, page, page_num|
          cur_page = notebook.get_nth_page(page_num)
          if $last_page and (cur_page != $last_page) and ($last_page.is_a? Pandora::Gtk::DialogScrollWin)
            $last_page.init_video_sender(false, true) if not $last_page.area_send.destroyed?
            $last_page.init_video_receiver(false) if not $last_page.area_recv.destroyed?
          end
          if cur_page.is_a? Pandora::Gtk::DialogScrollWin
            cur_page.update_state(false, cur_page)
            cur_page.init_video_receiver(true, true, false) if not cur_page.area_recv.destroyed?
            cur_page.init_video_sender(true, true) if not cur_page.area_send.destroyed?
          end
          $last_page = cur_page
        end

        @log_view = Pandora::Gtk::ExtTextView.new
        log_view.set_readonly(true)
        log_view.border_width = 0

        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        sw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        sw.shadow_type = ::Gtk::SHADOW_IN
        sw.add(log_view)
        sw.border_width = 1;
        sw.set_size_request(-1, 40)

        vpaned = ::Gtk::VPaned.new
        vpaned.border_width = 2
        vpaned.pack1(notebook, true, true)
        vpaned.pack2(sw, false, true)

        @cvpaned = CaptchaHPaned.new(vpaned)
        @cvpaned.position = cvpaned.max_position

        $statusbar = ::Gtk::Statusbar.new
        Pandora::Gtk.set_statusbar_text($statusbar, _('Base directory: ')+Pandora.base_dir)

        add_status_field(SF_Update, _('Version') + ': ' + _('Not checked')) do
          Pandora::Gtk.start_updating(true)
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

        vbox = ::Gtk::VBox.new
        vbox.pack_start(menubar, false, false, 0)
        vbox.pack_start(toolbar, false, false, 0)
        vbox.pack_start(cvpaned, true, true, 0)
        vbox.pack_start($statusbar, false, false, 0)

        #dat = DateEntry.new
        #vbox.pack_start(dat, false, false, 0)

        $window.add(vbox)

        update_win_icon = Pandora::Utils.get_param('status_update_win_icon')
        flash_on_new = Pandora::Utils.get_param('status_flash_on_new')
        flash_interval = Pandora::Utils.get_param('status_flash_interval')
        play_sounds = Pandora::Utils.get_param('play_sounds')
        hide_on_minimize = Pandora::Utils.get_param('hide_on_minimize')
        hide_on_close = Pandora::Utils.get_param('hide_on_close')
        mplayer = nil
        if Pandora::Utils.os_family=='windows'
          mplayer = Pandora::Utils.get_param('win_mp3_player')
        else
          mplayer = Pandora::Utils.get_param('linux_mp3_player')
        end
        $mp3_player = mplayer if ((mplayer.is_a? String) and (mplayer.size>0))

        $statusicon = Pandora::Gtk::PandoraStatusIcon.new(update_win_icon, flash_on_new, \
          flash_interval, play_sounds, hide_on_minimize)

        @chech_tasks = false
        @gabage_clear = false
        init_scheduler(1000) if (@chech_tasks or @gabage_clear)

        $window.signal_connect('delete-event') do |*args|
          if hide_on_close
            $window.do_menu_act('Hide')
          else
            $window.do_menu_act('Quit')
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
            if curpage.is_a? Pandora::Gtk::PanobjScrollWin
              res = false
            else
              res = Pandora::Gtk.show_panobject_list(PandoraModel::Person)
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
            if widget.visible? and widget.active? and $statusicon.hide_on_minimize
              $window.hide
              #$window.skip_taskbar_hint = true
            end
          end
        end

        #$window.signal_connect('focus-out-event') do |window, event|
        #  p 'focus-out-event: ' + $window.has_toplevel_focus?.inspect
        #  false
        #end
        $window.do_on_show = Pandora::Utils.get_param('do_on_show')
        $window.signal_connect('show') do |window, event|
          if $window.do_on_show > 0
            key = Pandora::Crypto.current_key(false, true)
            if ($window.do_on_show>1) and key and (not $listen_thread)
              PandoraNet.start_or_stop_listen
            end
            $window.do_on_show = 0
          end
          false
        end

        @pool = Pandora::Net::Pool.new($window)

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
            if (Pandora::Utils.os_family=='windows') and (not $window.visible?)
              $window.do_menu_act('Activate')
            end
            $window.focus_timer = GLib::Timeout.add(500) do
              if (not $window.nil?) and (not $window.destroyed?)
                #p 'read timer!!!' + $window.has_toplevel_focus?.inspect
                toplevel = ($window.has_toplevel_focus? or (Pandora::Utils.os_family=='windows'))
                if toplevel and $window.visible?
                  $window.notebook.children.each do |child|
                    if (child.is_a? DialogScrollWin) and (child.has_unread)
                      $window.notebook.page = $window.notebook.children.index(child)
                      break
                    end
                  end
                  curpage = $window.notebook.get_nth_page($window.notebook.page)
                  if (curpage.is_a? Pandora::Gtk::DialogScrollWin) and toplevel
                    curpage.update_state(false, curpage)
                  end
                end
                $window.focus_timer = nil
              end
              false
            end
          end
          false
        end

        $base_id = Pandora::Utils.get_param('base_id')
        check_update = Pandora::Utils.get_param('check_update')
        if (check_update==1) or (check_update==true)
          last_check = Pandora::Utils.get_param('last_check')
          last_check ||= 0
          last_update = Pandora::Utils.get_param('last_update')
          last_update ||= 0
          check_interval = Pandora::Utils.get_param('check_interval')
          if not check_interval or (check_interval < 0)
            check_interval = 1
          end
          update_period = Pandora::Utils.get_param('update_period')
          if not update_period or (update_period < 0)
            update_period = 1
          end
          time_now = Time.now.to_i
          need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
          ok_version = (time_now - last_update.to_i) < update_period*24*3600
          if ok_version
            set_status_field(SF_Update, 'Ok', need_check)
          elsif need_check
            Pandora::Gtk.start_updating(false)
          end
        end
        Pandora::Gtk.get_main_params

        Gtk.main
      end

    end  #--MainWindow

  end
end
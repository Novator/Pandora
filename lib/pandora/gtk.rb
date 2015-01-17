require_relative 'gtk/advanced_dialog'
require_relative 'gtk/mask_entry'
require_relative 'gtk/integer_entry'
require_relative 'gtk/date_entry_simple'

# ====================================================================
# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры
module Pandora
  module Gtk
    include Constants

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

    MaxPanhashTabs = 5

    MaxOnePlaceViewSec = 60

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
        text = Pandora.t(mi[2])
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
        btn = ::Gtk::ToolButton.new(image, Pandora.t(title))
        #btn = ::Gtk::ToolButton.new(stock)
        btn.signal_connect('clicked') do |*args|
          yield(*args) if block_given?
        end
        btn.label = title
      end
      toolbar.add(btn)
      title = Pandora.t(title)
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
            Pandora.logger.info Pandora.t('Download from') + ': ' + \
                                  host + path + '..'
            response = http.request_get(path)
            filebody = response.body
            if filebody and (filebody.size>0)
              File.open(pfn, 'wb+') do |file|
                file.write(filebody)
                res = true
                Pandora.logger.info  Pandora.t('File updated')+': '+pfn
              end
            else
              Pandora.logger.warn  Pandora.t('Empty downloaded body')
            end
          rescue => err
            Pandora.logger.warn  Pandora.t('Update error')+': '+err.message
          end
        else
          Pandora.logger.warn  Pandora.t('Cannot create directory')+': '+dir
        end
        res
      end

      def self.connect_http(main_uri, curr_size, step, p_addr=nil, p_port=nil, p_user=nil, p_pass=nil)
        http = nil
        time = 0
        Pandora.logger.info Pandora.t('Connect to') + ': ' + \
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
          Pandora::Utils.set_param('last_check', Time.now)
          p 'Size diff: '+[act_size, curr_size].inspect
          if (act_size == curr_size)
            http = nil
            step = 254
            $window.set_status_field(SF_Update, 'Ok', false)
            Pandora::Utils.set_param('last_update', Time.now)
          else
            time = Time.now.to_i
          end
        rescue => err
          http = nil
          $window.set_status_field(SF_Update, 'Connection error')
          Pandora.logger.warn Pandora.t('Cannot connect to repo to check update')+\
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
            Pandora.logger.warn  Pandora.t('Cannot reconnect to repo to update')
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
                Pandora.logger.info  Pandora.t('Proxy is used')+' '+proxy.inspect
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
                          Pandora.logger.info  Pandora.t('Need update')
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
                              res = Pandora::Utils.unzip_via_lib(zip_local, Pandora.base_dir)
                              p 'unzip_file1 res='+res.inspect
                              if not res
                                Pandora.logger.debug  Pandora.t('Was not unziped with method')+': lib'
                                unzip_meth = 'util'
                                res = Pandora::Utils.unzip_via_util(zip_local, Pandora.base_dir)
                                p 'unzip_file2 res='+res.inspect
                                if not res
                                  Pandora.logger.warn  Pandora.t('Was not unziped with method')+': util'
                                end
                              end
                              # Copy files to work dir
                              if res
                                Pandora.logger.info  Pandora.t('Arch is unzipped with method')+': '+unzip_meth
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
                                    Pandora.logger.info  Pandora.t('Files are updated')
                                  rescue => err
                                    res = false
                                    Pandora.logger.warn  Pandora.t('Cannot copy files from zip arch')+': '+err.message
                                  end
                                  # Remove used arch dir
                                  begin
                                    FileUtils.remove_dir(unzip_path)
                                  rescue => err
                                    Pandora.logger.warn  Pandora.t('Cannot remove arch dir')+' ['+unzip_path+']: '+err.message
                                  end
                                  step = 255 if res
                                else
                                  Pandora.logger.warn  Pandora.t('Unzipped directory does not exist')
                                end
                              else
                                Pandora.logger.warn  Pandora.t('Arch was not unzipped')
                              end
                            else
                              Pandora.logger.warn  Pandora.t('Cannot download arch')
                            end
                          end
                        end
                      else
                        $window.set_status_field(SF_Update, 'Read only')
                        Pandora.logger.warn  Pandora.t('Zip is unrewritable')
                      end
                    else
                      $window.set_status_field(SF_Update, 'Size error')
                      Pandora.logger.warn  Pandora.t('Zip size error')
                    end
                  end
                  update_zip = false
                else   # update with https from sources
                  main_uri = URI('https://raw.githubusercontent.com/Novator/Pandora/master/pandora.rb')
                  http, time, step = connect_http(main_uri, curr_size, step, *proxy)
                  if http
                    Pandora.logger.info  Pandora.t('Need update')
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
                          Pandora.logger.warn Pandora.t('Not exist or read only')+': '+pfn
                        else
                          downloaded = downloaded and \
                            update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                        end
                      end
                      if downloaded
                        step = 255
                      else
                        Pandora.logger.warn  Pandora.t('Direct download error')
                      end
                    end
                  end
                  update_zip = true
                end
              end
              if step == 255
                Pandora::Utils.set_param('last_update', Time.now)
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
        lang = Pandora::Model.text_to_lang(Pandora.config.lang)
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
          if (panobject.is_a? Pandora::Model::Created)
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
              Pandora.t('Record will be deleted. Sure?')+"\n["+info+']')
            dialog.title = Pandora.t('Deletion')+': '+panobject.sname
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
                ps = Pandora::Utils.decode_param_setting(setting)
                view = ps['view']
                view ||= Pandora::Utils.pantype_to_view(type)
                field[FI_View] = view
              end
            end

            val, color = Pandora::Utils.val_to_view(val, type, view, true)
            field[FI_Value] = val
            field[FI_Color] = color
          end

          dialog = FieldsDialog.new(panobject, formfields, panobject.sname)
          dialog.icon = panobjecticon if panobjecticon

          dialog.lang_entry.entry.text = Pandora::Model.lang_to_text(lang) if lang

          if edit
            count, rate, querist_rate = Pandora::Crypto.rate_of_panobj(panhash0)
            trust = nil
            p Pandora::Utils.bytes_to_hex(panhash0)
            p 'trust or num'
            trust_or_num = Pandora::Crypto.trust_in_panobj(panhash0)
            trust = trust_or_num if (trust_or_num.is_a? Float)
            dialog.vouch_btn.active = (trust_or_num != nil)
            dialog.vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
            dialog.trust_scale.sensitive = (trust != nil)
            #dialog.trust_scale.signal_emit('value-changed')
            trust ||= 0.0
            dialog.trust_scale.value = trust
            #dialog.rate_label.text = rate.to_s

            dialog.keep_btn.active = (Pandora::Model::PSF_Support & panstate)>0

            pub_level = Pandora::Model.act_relation(nil, panhash0, Pandora::Model::RK_MinPublic, :check)
            dialog.public_btn.active = pub_level
            dialog.public_btn.inconsistent = (pub_level == nil)
            dialog.public_scale.value = (pub_level-Pandora::Model::RK_MinPublic-10)/10.0 if pub_level
            dialog.public_scale.sensitive = pub_level

            p 'follow'
            p follow = Pandora::Model.act_relation(nil, panhash0, Pandora::Model::RK_Follow, :check)
            dialog.follow_btn.active = follow
            dialog.follow_btn.inconsistent = (follow == nil)

            #dialog.lang_entry.active_text = lang.to_s
            #trust_lab = dialog.trust_btn.children[0]
            #trust_lab.modify_fg(::Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
          else  #new or copy
            key = Pandora::Crypto.current_key(false, false)
            key_inited = (key and key[Pandora::Crypto::KV_Obj])
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

          if panobject.class==Pandora::Model::Key
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
          #  titadd = Pandora.t('edit')
          #else
            titadd = Pandora.t('new')
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
                ps = Pandora::Utils.decode_param_setting(setting)
                view = ps['view']
                view ||= Pandora::Utils.pantype_to_view(par_type)
              end

              p 'val, type, view='+[val, type, view].inspect
              val = Pandora::Utils.view_to_val(val, type, view)
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
              lg = Pandora::Model.text_to_lang(dialog.lang_entry.entry.text)
            rescue
            end
            lang = lg if lg
            lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

            time_now = Time.now.to_i
            if (panobject.is_a? Pandora::Model::Created)
              flds_hash['created'] = created0 if created0
              if not edit
                flds_hash['created'] = time_now
                creator = Pandora::Crypto.current_user_or_key(true)
                flds_hash['creator'] = creator
              end
            end
            flds_hash['modified'] = time_now
            panstate = 0
            panstate = panstate | Pandora::Model::PSF_Support if dialog.keep_btn.active?
            flds_hash['panstate'] = panstate
            if (panobject.is_a? Pandora::Model::Key)
              lang = flds_hash['rights'].to_i
            end

            panhash = panobject.panhash(flds_hash, lang)
            flds_hash['panhash'] = panhash

            if (panobject.is_a? Pandora::Model::Key) and (flds_hash['kind'].to_i == Pandora::Crypto::KT_Priv) and edit
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
                  Pandora::Crypto.unsign_panobject(panhash0, true)
                  if dialog.vouch_btn.active?
                    trust = (dialog.trust_scale.value*127).round
                    Pandora::Crypto.sign_panobject(panobject, trust)
                  end
                end

                if not dialog.follow_btn.inconsistent?
                  Pandora::Model.act_relation(nil, panhash0, Pandora::Model::RK_Follow, :delete, \
                    true, true)
                  if (panhash != panhash0)
                    Pandora::Model.act_relation(nil, panhash, Pandora::Model::RK_Follow, :delete, \
                      true, true)
                  end
                  if dialog.follow_btn.active?
                    Pandora::Model.act_relation(nil, panhash, Pandora::Model::RK_Follow, :create, \
                      true, true)
                  end
                end

                if not dialog.public_btn.inconsistent?
                  public_level = Pandora::Model::RK_MinPublic + (dialog.public_scale.value*10).round+10
                  p 'public_level='+public_level.inspect
                  Pandora::Model.act_relation(nil, panhash0, Pandora::Model::RK_MinPublic, :delete, \
                    true, true)
                  if (panhash != panhash0)
                    Pandora::Model.act_relation(nil, panhash, Pandora::Model::RK_MinPublic, :delete, \
                      true, true)
                  end
                  if dialog.public_btn.active?
                    Pandora::Model.act_relation(nil, panhash, public_level, :create, \
                      true, true)
                  end
                end
              end
            end
          end
        end
      elsif action=='Dialog'
        Pandora::Gtk.show_panobject_list(Pandora::Model::Person)
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
          ps = Pandora::Utils.decode_param_setting(setting)
          view = ps['view']
          view ||= Pandora::Utils.pantype_to_view(type)
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
                val, color = Pandora::Utils.val_to_view(val, nil, view, false)
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
      menu.append(create_menu_item(['Create', ::Gtk::Stock::NEW, Pandora.t('Create'), 'Insert'], treeview))
      menu.append(create_menu_item(['Edit', ::Gtk::Stock::EDIT, Pandora.t('Edit'), 'Return'], treeview))
      menu.append(create_menu_item(['Delete', ::Gtk::Stock::DELETE, Pandora.t('Delete'), 'Delete'], treeview))
      menu.append(create_menu_item(['Copy', ::Gtk::Stock::COPY, Pandora.t('Copy'), '<control>Insert'], treeview))
      menu.append(create_menu_item(['-', nil, nil], treeview))
      menu.append(create_menu_item(['Dialog', ::Gtk::Stock::MEDIA_PLAY, Pandora.t('Dialog'), '<control>D'], treeview))
      menu.append(create_menu_item(['Opinion', ::Gtk::Stock::JUMP_TO, Pandora.t('Opinions'), '<control>BackSpace'], treeview))
      menu.append(create_menu_item(['Connect', ::Gtk::Stock::CONNECT, Pandora.t('Connect'), '<control>N'], treeview))
      menu.append(create_menu_item(['Relate', ::Gtk::Stock::INDEX, Pandora.t('Relate'), '<control>R'], treeview))
      menu.append(create_menu_item(['-', nil, nil], treeview))
      menu.append(create_menu_item(['Convert', ::Gtk::Stock::CONVERT, Pandora.t('Convert')], treeview))
      menu.append(create_menu_item(['Import', ::Gtk::Stock::OPEN, Pandora.t('Import')], treeview))
      menu.append(create_menu_item(['Export', ::Gtk::Stock::SAVE, Pandora.t('Export')], treeview))
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
          kind = Pandora::Utils.kind_from_panhash(panhash)
          panobjectclass = Pandora::Model.panobjectclass_by_kind(kind)
          if panobjectclass
            if panobjectclass <= Pandora::Model::Person
              persons << panhash
            elsif panobjectclass <= Pandora::Model::Node
              nodes << panhash
            else
              if panobjectclass <= Pandora::Model::Created
                model = Pandora::Utils.get_model(panobjectclass.ider)
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
        model = Pandora::Utils.get_model('Node')
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
        kmodel = Pandora::Utils.get_model('Key')
        smodel = Pandora::Utils.get_model('Sign')
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
        model = Pandora::Utils.get_model('Key')
        persons.each do |person|
          sel = model.select({:creator=>person}, false, 'panhash', 'modified DESC', $key_watch_lim)
          if sel and (sel.size>0)
            sel.each do |row|
              keys << row[0]
            end
          end
        end
        if keys.size == 0
          model = Pandora::Utils.get_model('Sign')
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
        model = Pandora::Utils.get_model('Node')
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
      dlg.authors = [Pandora.t('Michael Galyuk')+' <robux@mail.ru>']
      dlg.artists = ['© '+Pandora.t('Rights to logo are owned by 21th Century Fox')]
      dlg.comments = Pandora.t('P2P national network')
      dlg.copyright = Pandora.t('Free software')+' 2012, '+Pandora.t('Michael Galyuk')
      begin
        file = File.open(File.join(Pandora.root, 'LICENSE.TXT'), 'r')
        gpl_text = '================='+Pandora.t('Full text')+" LICENSE.TXT==================\n"+file.read
        file.close
      rescue
        gpl_text = Pandora.t('Full text is in the file')+' LICENSE.TXT.'
      end
      dlg.license = Pandora.t("License GNU GPLv2")+gpl_text
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
          creator = Pandora::Crypto.current_user_or_key(true)
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
        mes = Pandora.t('node') if nodes.size == 0
        mes = Pandora.t('person') if persons.size == 0
        dialog = ::Gtk::MessageDialog.new($window, \
          ::Gtk::Dialog::MODAL | ::Gtk::Dialog::DESTROY_WITH_PARENT, \
          ::Gtk::MessageDialog::INFO, ::Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
          mes = Pandora.t('No one')+' '+mes+' '+Pandora.t('is not found')+".\n"+Pandora.t('Add nodes and do hunt'))
        dialog.title = Pandora.t('Note')
        dialog.default_response = ::Gtk::Dialog::RESPONSE_OK
        dialog.icon = $window.icon
        if (dialog.run == ::Gtk::Dialog::RESPONSE_OK)
          Pandora::Gtk.show_panobject_list(Pandora::Model::Node, nil, nil, true)
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

      label_box = TabLabelBox.new(image, Pandora.t('Search'), sw, false, 0) do
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
      a_person ||= Pandora::Crypto.current_user_or_key(true, true)

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
        mykey = Pandora::Crypto.current_key(false, false) if (not a_person0)
        if mykey and mykey[Pandora::Crypto::KV_Creator] and (mykey[Pandora::Crypto::KV_Creator] != a_person)
          aname, afamily = Pandora::Crypto.name_and_family_of_person(mykey, a_person)
        else
          aname, afamily = Pandora::Crypto.name_and_family_of_person(nil, a_person)
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
      user_iter[0] = Pandora.t('Profile')
      user_iter = list_store.append
      user_iter[0] = Pandora.t('Events')

      # create tree view
      list_tree = ::Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = ::Gtk::CellRendererText.new
      column = ::Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      #renderer = ::Gtk::CellRendererText.new
      #column = ::Gtk::TreeViewColumn.new(Pandora.t('Record'), renderer, 'text' => 1)
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

      short_name = Pandora.t('Profile') if not((short_name.is_a? String) and (short_name.size>0))

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
      label_box = TabLabelBox.new(image, Pandora.t('Sessions'), sw, false, 0) do
        #sw.destroy
      end
      page = $window.notebook.append_page(sw, label_box)
      sw.show_all
      $window.notebook.page = $window.notebook.n_pages-1
    end

  end
end
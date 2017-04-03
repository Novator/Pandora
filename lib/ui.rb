#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Mutual user interface (UI) of Pandora
# RU: Общий интерфейс пользователя Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2017 (c) Michael Galyuk
# RU: 2017 (c) Михаил Галюк

require File.expand_path('../utils.rb',  __FILE__)
require File.expand_path('../crypto.rb',  __FILE__)
require File.expand_path('../net.rb',  __FILE__)

def require_gtk
  if not $gtk_is_active
    require File.expand_path('../gtk.rb',  __FILE__)
  end
  res = $gtk_is_active
end

def require_ncurses
  if not $ncurses_is_active
    require File.expand_path('../ncurses.rb',  __FILE__)
  end
  res = $ncurses_is_active
end

$gtk_is_active = false
$ncurses_is_active = false

module PandoraUI

  $show_task_notif = true

  # Scheduler parameters (sec)
  # RU: Параметры планировщика (сек)
  CheckTaskPeriod  = 1*60   #5 min
  MassGarbStep   = 30     #30 sec
  CheckBaseStep    = 10     #10 sec
  CheckBasePeriod  = 60*60  #60 min
  # Size of bundle processed at one cycle
  # RU: Размер пачки, обрабатываемой за цикл
  HuntTrain         = 10     #nodes at a heat
  BaseGarbTrain     = 3      #records at a heat
  MassTrain       = 3      #request at a heat
  MassGarbTrain   = 30     #request at a heat

  # Initialize scheduler (tasks, hunter, base gabager, mem gabager)
  # RU: Инициировать планировщик (задачи, охотник, мусорщики баз и памяти)
  def self.init_scheduler(step=nil)
    pool = $pool
    step ||= 1.0
    #p 'scheduler_step='+step.inspect
    if (not @scheduler) and step
      @scheduler_step = step
      @base_garbage_term = PandoraUtils.get_param('base_garbage_term')
      @base_purge_term = PandoraUtils.get_param('base_purge_term')
      @base_garbage_term ||= 5   #day
      @base_purge_term ||= 30    #day
      @base_garbage_term = (@base_garbage_term * 24*60*60).round   #sec
      @base_purge_term = (@base_purge_term * 24*60*60).round   #sec
      @shed_models ||= {}
      @task_offset = nil
      @task_model = nil
      @task_list = nil
      @task_dialog = nil
      @hunt_node_id = nil
      @mass_garb_offset = 0.0
      @mass_garb_ind = 0
      @base_garb_mode = :arch
      @base_garb_model = nil
      @base_garb_kind = 0
      @base_garb_offset = nil
      @panreg_period = PandoraUtils.get_param('panreg_period')
      if (not(@panreg_period.is_a? Numeric)) or (@panreg_period < 0)
        @panreg_period = 30
      end
      @panreg_period = @panreg_period*60
      @scheduler = Thread.new do
        sleep 1
        while @scheduler_step

          # Update pool time_now
          pool.time_now = Time.now.to_i

          # Task executer
          # RU: Запускальщик Заданий
          if (not @task_dialog) and ((not @task_offset) \
          or (@task_offset >= CheckTaskPeriod))
            @task_offset = 0.0
            user ||= PandoraCrypto.current_user_or_key(true, false)
            if user
              @task_model ||= PandoraUtils.get_model('Task', @shed_models)
              cur_time = Time.now.to_i
              filter = ["(executor=? OR IFNULL(executor,'')='' AND creator=?) AND mode>? AND time<=?", \
                user, user, 0, cur_time]
              fields = 'id, time, mode, message'
              @task_list = @task_model.select(filter, false, fields, 'time ASC')
              Thread.pass
              if @task_list and (@task_list.size>0)
                p 'TTTTTTTTTT @task_list='+@task_list.inspect

                message = ''
                store = nil
                if $show_task_notif and $window.visible? \
                and (PandoraUtils.os_family != 'windows')
                #and $window.has_toplevel_focus?
                  store = Gtk::ListStore.new(String, String, String)
                end
                @task_list.each do |row|
                  time = Time.at(row[1]).strftime('%d.%m.%Y %H:%M:%S')
                  mode = row[2]
                  text = Utf8String.new(row[3])
                  if message.size>0
                    message += '; '
                  else
                    message += _('Tasks')+'> '
                  end
                  message +=  '"' + text + '" ('+time+')'
                  if store
                    iter = store.append
                    iter[0] = time
                    iter[1] = mode.to_s
                    iter[2] = text
                  end
                end

                PandoraUI.log_message(PandoraUI::LM_Warning, message)
                PandoraUtils.play_mp3('message')
                if $statusicon.message.nil?
                  $statusicon.set_message(message)
                  Thread.new do
                    sleep(10)
                    $statusicon.set_message(nil)
                  end
                end

                if store
                  Thread.new do
                    @task_dialog = PandoraGtk::AdvancedDialog.new(_('Tasks'))
                    dialog = @task_dialog
                    image = $window.get_preset_image('task')
                    iconset = image.icon_set
                    style = Gtk::Widget.default_style  #Gtk::Style.new
                    task_icon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
                      Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
                    dialog.icon = task_icon

                    dialog.set_default_size(500, 350)
                    vbox = Gtk::VBox.new
                    dialog.viewport.add(vbox)

                    treeview = Gtk::TreeView.new(store)
                    treeview.rules_hint = true
                    treeview.search_column = 0
                    treeview.border_width = 10

                    renderer = Gtk::CellRendererText.new
                    column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 0)
                    column.set_sort_column_id(0)
                    treeview.append_column(column)

                    renderer = Gtk::CellRendererText.new
                    column = Gtk::TreeViewColumn.new(_('Mode'), renderer, 'text' => 1)
                    column.set_sort_column_id(1)
                    treeview.append_column(column)

                    renderer = Gtk::CellRendererText.new
                    column = Gtk::TreeViewColumn.new(_('Text'), renderer, 'text' => 2)
                    column.set_sort_column_id(2)
                    treeview.append_column(column)

                    vbox.pack_start(treeview, false, false, 2)

                    dialog.def_widget = treeview

                    dialog.run2(true) do
                      @task_list.each do |row|
                        id = row[0]
                        @task_model.update({:mode=>0}, nil, {:id=>id})
                      end
                    end
                    @task_dialog = nil
                  end
                end
                Thread.pass
              end
            end
          end
          @task_offset += @scheduler_step if @task_offset

          # Hunter
          if false #$window.hunt
            if not @hunt_node_id
              @hunt_node_id = 0
            end
            Thread.pass
            @hunt_node_id += HuntTrain
          end

          # Search robot
          # RU: Поисковый робот
          if (pool.found_ind <= pool.mass_ind) and false #OFFFFF !!!!!
            processed = MassTrain
            while (processed > 0) and (pool.found_ind <= pool.mass_ind)
              search_req = pool.mass_records[pool.found_ind]
              p '####  Search spider  [size, @found_ind, obj_id]='+[pool.mass_records.size, \
                pool.found_ind, search_req.object_id].inspect
              if search_req and (not search_req[PandoraNet::SA_Answer])
                req = search_req[PandoraNet::SR_Request..PandoraNet::SR_BaseId]
                p 'search_req3='+req.inspect
                answ = nil
                if search_req[PandoraNet::SR_Kind]==PandoraModel::PK_BlobBody
                  sha1 = search_req[PandoraNet::SR_Request]
                  fn_fs = $pool.blob_exists?(sha1, @shed_models, true)
                  if fn_fs.is_a? Array
                    fn_fs[0] = PandoraUtils.relative_path(fn_fs[0])
                    answ = fn_fs
                  end
                else
                  answ,kind = pool.search_in_local_bases(search_req[PandoraNet::SR_Request], \
                    search_req[PandoraNet::SR_Kind])
                end
                p 'SEARCH answ='+answ.inspect
                if answ
                  search_req[PandoraNet::SA_Answer] = answ
                  answer_raw = PandoraUtils.rubyobj_to_pson([req, answ])
                  session = search_req[PandoraNet::SR_Session]
                  sessions = []
                  if pool.sessions.include?(session)
                    sessions << session
                  end
                  sessions.concat(pool.sessions_of_keybase(nil, \
                    search_req[PandoraNet::SR_BaseId]))
                  sessions.flatten!
                  sessions.uniq!
                  sessions.compact!
                  sessions.each do |sess|
                    if sess.active?
                      sess.add_send_segment(PandoraNet::EC_News, true, answer_raw, \
                        PandoraNet::ECC_News_Answer)
                    end
                  end
                end
                #p log_mes+'[to_person, to_key]='+[@to_person, @to_key].inspect
                #if search_req and (search_req[SR_Session] != self) and (search_req[SR_BaseId] != @to_base_id)
                processed -= 1
              else
                processed = 0
              end
              pool.found_ind += 1
            end
          end

          # Mass record garbager
          # RU: Чистильщик массовых сообщений
          if false #!!!! (@mass_garb_offset >= MassGarbStep)
            @mass_garb_offset = 0.0
            cur_time = Time.now.to_i
            processed = MassGarbTrain
            while (processed > 0)
              if (@mass_garb_ind < pool.mass_records.size)
                search_req = pool.mass_records[@mass_garb_ind]
                if search_req
                  time = search_req[PandoraNet::MR_CrtTime]
                  if (not time.is_a? Integer) or (time+$search_live_time<cur_time)
                    pool.mass_records[@mass_garb_ind] = nil
                  end
                end
                @mass_garb_ind += 1
                processed -= 1
              else
                @mass_garb_ind = 0
                processed = 0
              end
            end
            #pool.mass_records.compact!
          end
          @mass_garb_offset += @scheduler_step

          # Bases garbager
          # RU: Чистильшик баз
          if (not @base_garb_offset) \
          or ((@base_garb_offset >= CheckBaseStep) and @base_garb_kind<255) \
          or (@base_garb_offset >= CheckBasePeriod)
            #p '@base_garb_offset='+@base_garb_offset.inspect
            #p '@base_garb_kind='+@base_garb_kind.inspect
            @base_garb_kind = 0 if @base_garb_offset \
              and (@base_garb_offset >= CheckBasePeriod) and (@base_garb_kind >= 255)
            @base_garb_offset = 0.0
            train_tail = BaseGarbTrain
            while train_tail>0
              if (not @base_garb_model)
                @base_garb_id = 0
                while (@base_garb_kind<255) \
                and (not @base_garb_model.is_a? PandoraModel::Panobject)
                  @base_garb_kind += 1
                  panobjectclass = PandoraModel.panobjectclass_by_kind(@base_garb_kind)
                  if panobjectclass
                    @base_garb_model = PandoraUtils.get_model(panobjectclass.ider, @shed_models)
                  end
                end
                if @base_garb_kind >= 255
                  if @base_garb_mode == :arch
                    @base_garb_mode = :purge
                    @base_garb_kind = 0
                  else
                    @base_garb_mode = :arch
                  end
                end
              end

              if @base_garb_model
                if @base_garb_mode == :arch
                  arch_time = Time.now.to_i - @base_garbage_term
                  filter = ['id>=? AND modified<? AND IFNULL(panstate,0)=0', \
                    @base_garb_id, arch_time]
                else # :purge
                  purge_time = Time.now.to_i - @base_purge_term
                  filter = ['id>=? AND modified<? AND panstate>=?', @base_garb_id, \
                    purge_time, PandoraModel::PSF_Archive]
                end
                #p 'Base garbager [ider,mode,filt]: '+[@base_garb_model.ider, @base_garb_mode, filter].inspect
                sel = @base_garb_model.select(filter, false, 'id', 'id ASC', train_tail)
                #p 'base_garb_sel='+sel.inspect
                if sel and (sel.size>0)
                  sel.each do |row|
                    id = row[0]
                    @base_garb_id = id
                    #p '@base_garb_id='+@base_garb_id.inspect
                    values = nil
                    if @base_garb_mode == :arch
                      # mark the record as deleted, else purge it
                      values = {:panstate=>PandoraModel::PSF_Archive}
                    end
                    @base_garb_model.update(values, nil, {:id=>id})
                  end
                  train_tail -= sel.size
                  @base_garb_id += 1
                else
                  @base_garb_model = nil
                end
                Thread.pass
              else
                train_tail = 0
              end
            end
          end
          @base_garb_offset += @scheduler_step if @base_garb_offset

          # GUI updater (list, traffic)

          # PanReg node registration
          # RU: Регистратор узлов PanReg
          if (@node_reg_offset.nil? or (@node_reg_offset >= @panreg_period))
            @node_reg_offset = 0.0
            PandoraNet.register_node_ips
          end
          @node_reg_offset += @scheduler_step if @node_reg_offset


          sleep(@scheduler_step)

          #p 'Next scheduler step'

          Thread.pass
        end
        @scheduler = nil
      end
    end
  end

  $update_lag = 30    #time lag (sec) for update after run the programm
  $download_thread = nil

  UPD_FileList = ['model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'pandora.bat']
  if ($lang and ($lang != 'en'))
    UPD_FileList.concat(['model/03-language-'+$lang+'.xml', 'lang/'+$lang+'.txt'])
  end

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    def self.connect_http_and_check_size(url, curr_size, step)
      time = nil
      http, host, path = PandoraNet.http_connect(url)
      if http
        new_size = PandoraNet.http_size_from_header(http, path, false)
        if not new_size
          sleep(0.5)
          new_size = PandoraNet.http_size_from_header(http, path, false)
        end
        if new_size
          PandoraUtils.set_param('last_check', Time.now)
          #p 'Size diff: '+[new_size, curr_size].inspect
          if (new_size == curr_size)
            http = nil
            step = 254
            PandoraUI.set_status_field(PandoraUI::SF_Update, 'Ok', false)
            PandoraUtils.set_param('last_update', Time.now)
          else
            time = Time.now.to_i
          end
        else
          http = nil
        end
      end
      if not http
        PandoraUI.set_status_field(PandoraUI::SF_Update, 'Connection error')
        PandoraUI.log_message(PandoraUI::LM_Info, _('Cannot connect to repo to check update')+\
          ' '+[host, path].inspect)
      end
      [http, time, step, host, path]
    end

    def self.reconnect_if_need(http, time, url)
      http = PandoraNet.http_reconnect_if_need(http, time, url)
      if not http
        PandoraUI.set_status_field(PandoraUI::SF_Update, 'Connection error')
        PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot reconnect to repo to update'))
      end
      http
    end

    # Update file
    # RU: Обновить файл
    def self.update_file(http, path, pfn, host='')
      res = false
      dir = File.dirname(pfn)
      FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
      if Dir.exists?(dir)
        filebody = PandoraNet.http_get_body_from_path(http, path, host)
        if filebody and (filebody.size>0)
          begin
            File.open(pfn, 'wb+') do |file|
              file.write(filebody)
              res = true
              PandoraUI.log_message(PandoraUI::LM_Info, _('File updated')+': '+pfn)
            end
          rescue => err
            PandoraUI.log_message(PandoraUI::LM_Warning, _('Update error')+': '+Utf8String.new(err.message))
          end
        else
          PandoraUI.log_message(PandoraUI::LM_Warning, _('Empty downloaded body'))
        end
      else
        PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot create directory')+': '+dir)
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
        PandoraUI.set_status_field(PandoraUI::SF_Update, 'Need check')
        sleep($update_lag) if not Thread.current[:all_step]
        PandoraUI.set_status_field(PandoraUI::SF_Update, 'Checking')

        main_script = File.join($pandora_app_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          if File.stat(main_script).writable?
            update_zip = PandoraUtils.get_param('update_zip_first')
            update_zip = true if update_zip.nil?

            step = 0
            while (step<2) do
              step += 1
              if update_zip
                zip_local = File.join($pandora_base_dir, 'Pandora-master.zip')
                zip_exists = File.exist?(zip_local)
                #p [zip_exists, zip_local]
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
                      zip_url = 'https://bitbucket.org/robux/pandora/get/master.zip'
                      dir_in_zip = 'robux-pandora'
                      http, time, step, host, path = connect_http_and_check_size(zip_url, \
                        zip_size, step)
                      if http
                        PandoraUI.log_message(PandoraUI::LM_Info, _('Need update'))
                        PandoraUI.set_status_field(PandoraUI::SF_Update, 'Need update')
                        Thread.stop
                        http = reconnect_if_need(http, time, zip_url)
                        if http
                          PandoraUI.set_status_field(PandoraUI::SF_Update, 'Doing')
                          res = update_file(http, path, zip_local, host)
                          #res = true
                          if res
                            # Delete old arch paths
                            unzip_mask = File.join($pandora_base_dir, dir_in_zip+'*')
                            p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                            unzip_paths.each do |pathfilename|
                              p 'Remove dir: '+pathfilename
                              FileUtils.remove_dir(pathfilename) if File.directory?(pathfilename)
                            end
                            # Unzip arch
                            unzip_meth = 'lib'
                            res = PandoraUtils.unzip_via_lib(zip_local, $pandora_base_dir)
                            p 'unzip_file1 res='+res.inspect
                            if not res
                              PandoraUI.log_message(PandoraUI::LM_Trace, _('Was not unziped with method')+': lib')
                              unzip_meth = 'util'
                              res = PandoraUtils.unzip_via_util(zip_local, $pandora_base_dir)
                              p 'unzip_file2 res='+res.inspect
                              if not res
                                PandoraUI.log_message(PandoraUI::LM_Warning, _('Was not unziped with method')+': util')
                              end
                            end
                            # Copy files to work dir
                            if res
                              PandoraUI.log_message(PandoraUI::LM_Info, _('Arch is unzipped with method')+': '+unzip_meth)
                              #unzip_path = File.join($pandora_base_dir, 'Pandora-master')
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
                                  p 'Copy '+unzip_path+' to '+$pandora_app_dir
                                  #FileUtils.copy_entry(unzip_path, $pandora_app_dir, true)
                                  FileUtils.cp_r(unzip_path+'/.', $pandora_app_dir)
                                  PandoraUI.log_message(PandoraUI::LM_Info, _('Files are updated'))
                                rescue => err
                                  res = false
                                  PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot copy files from zip arch')+': '+Utf8String.new(err.message))
                                end
                                # Remove used arch dir
                                begin
                                  FileUtils.remove_dir(unzip_path)
                                rescue => err
                                  PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot remove arch dir')+' ['+unzip_path+']: '+Utf8String.new(err.message))
                                end
                                step = 255 if res
                              else
                                PandoraUI.log_message(PandoraUI::LM_Warning, _('Unzipped directory does not exist'))
                              end
                            else
                              PandoraUI.log_message(PandoraUI::LM_Warning, _('Arch was not unzipped'))
                            end
                          else
                            PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot download arch'))
                          end
                        end
                      end
                    else
                      PandoraUI.set_status_field(PandoraUI::SF_Update, 'Read only')
                      PandoraUI.log_message(PandoraUI::LM_Warning, _('Zip is unrewritable'))
                    end
                  else
                    PandoraUI.set_status_field(PandoraUI::SF_Update, 'Size error')
                    PandoraUI.log_message(PandoraUI::LM_Warning, _('Zip size error'))
                  end
                end
                update_zip = false
              else   # update with https from sources
                url = 'https://raw.githubusercontent.com/Novator/Pandora/master/pandora.rb'
                http, time, step, host, path = connect_http_and_check_size(url, \
                  curr_size, step)
                if http
                  PandoraUI.log_message(PandoraUI::LM_Info, _('Need update'))
                  PandoraUI.set_status_field(PandoraUI::SF_Update, 'Need update')
                  Thread.stop
                  http = reconnect_if_need(http, time, url)
                  if http
                    PandoraUI.set_status_field(PandoraUI::SF_Update, 'Doing')
                    # updating pandora.rb
                    downloaded = update_file(http, path, main_script, host)
                    # updating other files
                    UPD_FileList.each do |fn|
                      pfn = File.join($pandora_app_dir, fn)
                      if File.exist?(pfn) and (not File.stat(pfn).writable?)
                        downloaded = false
                        PandoraUI.log_message(PandoraUI::LM_Warning, \
                          _('Not exist or read only')+': '+pfn)
                      else
                        downloaded = downloaded and \
                          update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                      end
                    end
                    if downloaded
                      step = 255
                    else
                      PandoraUI.log_message(PandoraUI::LM_Warning, _('Direct download error'))
                    end
                  end
                end
                update_zip = true
              end
            end
            if step == 255
              PandoraUtils.set_param('last_update', Time.now)
              PandoraUI.set_status_field(PandoraUI::SF_Update, 'Need restart')
              Thread.stop
              #Kernel.abort('Pandora is updated. Run it again')
              puts 'Pandora is updated. Restarting..'
              PandoraNet.start_or_stop_listen(false, true)
              PandoraNet.start_or_stop_hunt(false) if $hunter_thread
              $pool.close_all_session
              PandoraUtils.restart_app
            elsif step<250
              PandoraUI.set_status_field(PandoraUI::SF_Update, 'Load error')
            end
          else
            PandoraUI.set_status_field(PandoraUI::SF_Update, 'Read only')
          end
        else
          PandoraUI.set_status_field(PandoraUI::SF_Update, 'Size error')
        end
        $download_thread = nil
      end
    end
  end

  # Tab view of person
  TV_Name    = 0   # Name only
  TV_Family  = 1   # Family only
  TV_NameFam   = 2   # Name and family
  TV_NameN   = 3   # Name with number

  def self.title_view
    @title_view
  end

  def self.auth_listen_hunt
    key = PandoraCrypto.current_key(false, true)
    if ((@do_on_start & 2) != 0) and key
      PandoraNet.start_or_stop_listen(true)
    end
    if ((@do_on_start & 4) != 0) and key and (not $hunter_thread)
      PandoraNet.start_or_stop_hunt(true, 2)
    end
    @do_on_start = 0
  end

  def self.runned_via_screen
    res = ($screen_mode or ENV['STY'] or (ENV['TERM']=='screen'))
  end

  def self.do_after_start
    @do_on_start = PandoraUtils.get_param('do_on_start')
    @title_view = PandoraUtils.get_param('title_view')
    @title_view ||= TV_Name

    @pool = PandoraNet::Pool.new
    $pool = @pool

    if PandoraUI.runned_via_screen
      PandoraUI.log_message(PandoraUI::LM_Info, \
        _('Use hot keys for screen:'+"\n"+'Ctrl+A,D - detach, Ctrl+A,K - kill, "screen -r" to resume)'))
    end

    if @do_on_start and (@do_on_start > 0)
      if $ncurses_is_active
        Thread.new do
          sleep(0.4)
          auth_listen_hunt
        end
      elsif $gtk_is_active
        dialog_timer = GLib::Timeout.add(400) do
          auth_listen_hunt
          false
        end
      end
    end

    scheduler_step = PandoraUtils.get_param('scheduler_step')
    init_scheduler(scheduler_step)

    check_update = PandoraUtils.get_param('check_update')
    if (check_update==1) or (check_update==true)
      last_check = PandoraUtils.get_param('last_check')
      last_check ||= 0
      last_update = PandoraUtils.get_param('last_update')
      last_update ||= 0
      check_interval = PandoraUtils.get_param('check_interval')
      if (not(check_interval.is_a? Numeric)) or (check_interval <= 0)
        check_interval = 1
      end
      update_period = PandoraUtils.get_param('update_period')
      if (not(update_period.is_a? Numeric)) or (update_period < 0)
        update_period = 1
      end
      time_now = Time.now.to_i
      ok_version = (time_now - last_update.to_i) < update_period*24*3600
      need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
      if ok_version
        PandoraUI.set_status_field(PandoraUI::SF_Update, 'Ok', need_check)
      elsif need_check
        PandoraUI.start_updating(false)
      end
    end
  end

  def self.play_sounds
    @play_sounds
  end

  # Do need play sounds?
  # RU: Нужно ли играть звуки?
  def self.play_sounds?
    #res = @play_sounds
    res = false
    if $gtk_is_active and $statusicon and (not $statusicon.destroyed?)
      res = $statusicon.play_sounds
    end
    res
  end

  # Init user interface and network
  # RU: Инициилизировать интерфейс пользователя и сеть
  def self.init_user_interface_and_network(cui_mode)
    @hunter_count = @listener_count = @fisher_count = 0
    @play_sounds = PandoraUtils.get_param('play_sounds')
    if cui_mode
      if require_ncurses
        PandoraCui.do_main_loop do
          do_after_start
        end
      end
    else
      if require_gtk
        PandoraGtk.do_main_loop do
          do_after_start
        end
      else
        puts('Ncurses interface will be used...')
        sleep(5)
        if require_ncurses
          PandoraCui.do_main_loop do
            do_after_start
          end
        end
      end
    end

  end

  # Log levels
  # RU: Уровни логирования
  LM_Error    = 0
  LM_Warning  = 1
  LM_Info     = 2
  LM_Trace    = 3

  # Log level on human view
  # RU: Уровень логирования по-человечьи
  def self.level_to_str(level)
    mes = ''
    case level
      when LM_Error
        mes = _('Error')
      when LM_Warning
        mes = _('Warning')
      when LM_Trace
        mes = _('Trace')
    end
    mes
  end

  # Main application window
  # RU: Главное окно приложения
  $window = nil

  # Default log level
  # RU: Уровень логирования по умолчанию
  $show_log_level = LM_Trace

  # Auto show log textview when this error level is achived
  # RU: Показать лоток лога автоматом, когда этот уровень ошибки достигнут
  $show_logbar_level = LM_Warning

  # Add the message to log
  # RU: Добавить сообщение в лог
  def self.log_message(level, mes)
    if (level <= $show_log_level)
      time = Time.now
      lev = level_to_str(level)
      lev = ' ['+lev+']' if (lev.is_a? String) and (lev.size>0)
      lev ||= ''
      mes = time.strftime('%H:%M:%S') + lev + ': '+mes
      if $ncurses_is_active
        PandoraCui.add_mes_to_log_win(mes, true)
      elsif $gtk_is_active
        $window.add_mes_to_log_view(mes, time, level)
        puts 'log: '+mes
      end
    end
  end

  # Statusbar fields
  # RU: Поля в статусбаре
  SF_Log     = 0
  SF_FullScr = 1
  SF_Update  = 2
  SF_Lang    = 3
  SF_Auth    = 4
  SF_Listen  = 5
  SF_Hunt    = 6
  SF_Conn    = 7
  SF_Radar   = 8
  SF_Fisher  = 9
  SF_Search  = 10
  SF_Harvest = 11

  # Set properties of fiels in statusbar
  # RU: Задаёт свойства поля в статусбаре
  def self.set_status_field(index, text, enabled=nil, toggle=nil)
    if $ncurses_is_active
      PandoraCui.set_status_field(index, text, enabled, toggle)
    elsif $gtk_is_active
      $window.set_status_field(index, text, enabled, toggle)
    end
  end

  # Update status of connections
  # RU: Обновить состояние подключений
  def self.update_conn_status(conn, session_type, diff_count)
    #if session_type==0
    @hunter_count += diff_count
    #elsif session_type==1
    #  @listener_count += diff_count
    #else
    #  @fisher_count += diff_count
    #end
    PandoraUI.set_status_field(PandoraUI::SF_Conn, (@hunter_count + \
      @listener_count + @fisher_count).to_s)
    online = ((@hunter_count>0) or (@listener_count>0) or (@fisher_count>0))
    if $gtk_is_active
      $statusicon.set_online(online)
    end
  end

  # Menu event handler
  # RU: Обработчик события меню
  def self.do_menu_act(command, treeview=nil)
    widget = nil
    if not (command.is_a? String)
      widget = command
      if widget.instance_variable_defined?('@command')
        command = widget.command
      else
        command = widget.name
      end
    end
    case command
      when 'Quit'
        PandoraNet.start_or_stop_listen(false, true)
        PandoraNet.start_or_stop_hunt(false) if $hunter_thread
        $pool.close_all_session
        if $ncurses_is_active
          PandoraCui.do_user_command(:close)
        elsif $gtk_is_active
          $window.destroy
        end
      when 'Activate'
        if $gtk_is_active
          $window.deiconify
          #self.visible = true if (not self.visible?)
          $window.present
        end
      when 'Hide'
        if $gtk_is_active
          #self.iconify
          $window.hide
        end
      when 'About'
        if $gtk_is_active
          PandoraGtk.show_about
        end
      when 'Guide'
        guide_fn = File.join($pandora_doc_dir, 'guide.'+$lang+'.pdf')
        if not File.exist?(guide_fn)
          if ($lang == 'en')
            guide_fn = File.join($pandora_doc_dir, 'guide.en.odt')
          else
            guide_fn = File.join($pandora_doc_dir, 'guide.en.pdf')
          end
        end
        if guide_fn and File.exist?(guide_fn)
          PandoraUtils.external_open(guide_fn, 'open')
        else
          PandoraUtils.external_open($pandora_doc_dir, 'open')
        end
      when 'Readme'
        PandoraUtils.external_open(File.join($pandora_app_dir, 'README.TXT'), 'open')
      when 'DocPath'
        PandoraUtils.external_open($pandora_doc_dir, 'open')
      when 'Close'
        if $gtk_is_active
          anotebook = $window.notebook
          if anotebook.page >= 0
            page = anotebook.get_nth_page(anotebook.page)
            tab = anotebook.get_tab_label(page)
            close_btn = tab.children[tab.children.size-1].children[0]
            close_btn.clicked
          end
        end
      when 'Create','Edit','Delete','Copy', 'Chat', 'Dialog', 'Opinion', \
      'Convert', 'Import', 'Export'
        if $gtk_is_active
          p 'act_panobject()  treeview='+treeview.inspect
          if (not treeview) and (notebook.page >= 0)
            sw = notebook.get_nth_page(notebook.page)
            treeview = sw.children[0]
          end
          if treeview.is_a? Gtk::TreeView # SubjTreeView
            if command=='Convert'
              panobject = treeview.panobject
              panobject.update(nil, nil, nil)
              panobject.class.tab_fields(true)
            elsif command=='Import'
              p 'import'
            elsif command=='Export'
              panobject = treeview.panobject
              ider = panobject.ider
              filename = File.join($pandora_files_dir, ider+'.csv')

              dialog = GoodFileChooserDialog.new(filename, false, nil, $window)

              filter = Gtk::FileFilter.new
              filter.name = _('Text tables')+' (*.csv,*.txt)'
              filter.add_pattern('*.csv')
              filter.add_pattern('*.txt')
              dialog.add_filter(filter)

              dialog.filter = filter

              filter = Gtk::FileFilter.new
              filter.name = _('JavaScript Object Notation')+' (*.json)'
              filter.add_pattern('*.json')
              dialog.add_filter(filter)

              filter = Gtk::FileFilter.new
              filter.name = _('Pandora Simple Object Notation')+' (*.pson)'
              filter.add_pattern('*.pson')
              dialog.add_filter(filter)

              if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
                filename = dialog.filename
                export_table(panobject, filename)
              end
              dialog.destroy if not dialog.destroyed?
            else
              PandoraGtk.act_panobject(treeview, command)
            end
          end
        end
      when 'Authorize'
        key = PandoraCrypto.current_key(false, false)
        if key
          PandoraNet.start_or_stop_listen(false)
          PandoraNet.start_or_stop_hunt(false) if $hunter_thread
          $pool.close_all_session
        end
        key = PandoraCrypto.current_key(true)
      when 'Listen'
        PandoraNet.start_or_stop_listen
      when 'Hunt'
        continue = false
        if $gtk_is_active
          continue = PandoraGtk.is_ctrl_shift_alt?(true, true)
        end
        PandoraNet.start_or_stop_hunt(continue)
      when 'Wizard'
        if $gtk_is_active
          PandoraGtk.show_log_bar(80)
        end
      when 'Profile'
        current_user = PandoraCrypto.current_user_or_key(true, true)
        if current_user
          PandoraUI.show_cabinet(current_user, nil, nil, nil, nil, PandoraUI::CPI_Profile)
        end
      when 'Search'
        if $ncurses_is_active
          PandoraCui.show_search_panel
        elsif $gtk_is_active
          PandoraGtk.show_search_panel
        end
      when 'Session'
        if $ncurses_is_active
          PandoraCui.show_session_panel
        elsif $gtk_is_active
          PandoraGtk.show_session_panel
        end
      when 'Radar'
        if $ncurses_is_active
          PandoraCui.show_radar_panel
        elsif $gtk_is_active
          PandoraGtk.show_radar_panel
        end
      when 'FullScr'
        PandoraGtk.full_screen_switch if $gtk_is_active
      when 'LogBar'
        if $ncurses_is_active
          PandoraCui.show_log_bar
        elsif $gtk_is_active
          PandoraGtk.show_log_bar
        end
      when 'Fisher'
        if $ncurses_is_active
          PandoraCui.show_fisher_panel
        elsif $gtk_is_active
          PandoraGtk.show_fisher_panel
        end
      else
        panobj_id = command
        if (panobj_id.is_a? String) and (panobj_id.size>0) \
        and (panobj_id[0].upcase==panobj_id[0]) and PandoraModel.const_defined?(panobj_id)
          panobject_class = PandoraModel.const_get(panobj_id)
          if $ncurses_is_active
            PandoraCui.show_panobject_list(panobject_class, widget)
          elsif $gtk_is_active
            PandoraGtk.show_panobject_list(panobject_class, widget)
          end
        else
          PandoraUI.log_message(PandoraUI::LM_Warning, _('Menu handler is not defined yet') + \
            ' "'+panobj_id+'"')
        end
    end
  end



  # Update or show radar panel
  # RU: Обновить или показать панель радара
  def self.update_or_show_radar_panel
    if $ncurses_is_active
      PandoraCui.show_radar_panel
    elsif $gtk_is_active
      hpaned = $window.radar_hpaned
      if (hpaned.max_position - hpaned.position) > 24
        radar_sw = $window.radar_sw
        radar_sw.update_btn.clicked
      else
        PandoraGtk.show_radar_panel
      end
    end
  end

  # Change listener button state
  # RU: Изменить состояние кнопки слушателя
  def self.correct_lis_btn_state
    if $ncurses_is_active
      PandoraCui.correct_lis_btn_state
    elsif $gtk_is_active
      $window.correct_lis_btn_state
    end
  end

  # Change hunter button state
  # RU: Изменить состояние кнопки охотника
  def self.correct_hunt_btn_state
    if $ncurses_is_active
      PandoraCui.correct_hunt_btn_state
    elsif $gtk_is_active
      $window.correct_hunt_btn_state
    end
  end

  # Is captcha window available?
  # RU: Окно для ввода капчи доступно?
  def self.captcha_win_available?
    res = nil
    if $ncurses_is_active
      res = false
    elsif $gtk_is_active
      res = $window.visible? #and $window.has_toplevel_focus?
    end
    res
  end

  # Cabinet page indexes
  # RU: Индексы страниц кабинета
  CPI_Property  = 0
  CPI_Profile   = 1
  CPI_Opinions  = 2
  CPI_Relations = 3
  CPI_Signs     = 4
  CPI_Chat      = 5
  CPI_Dialog    = 6
  CPI_Editor    = 7

  CPI_Sub       = 1
  CPI_Last_Sub  = 4
  CPI_Last      = 7

  # Show panobject cabinet
  # RU: Показать кабинет панобъекта
  def self.show_cabinet(panhash, session=nil, conntype=nil, \
  node_id=nil, models=nil, page=nil, fields=nil, obj_id=nil, edit=nil)
    res = nil
    if $ncurses_is_active
      res = PandoraCui.show_cabinet(panhash, session, conntype, node_id, models, \
        page, fields, obj_id, edit)
    elsif $gtk_is_active
      res = PandoraGtk.show_cabinet(panhash, session, conntype, node_id, models, \
        page, fields, obj_id, edit)
    end
    res
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, page_sw=nil, \
  auto_create=false, fix_filter=nil)
    res = nil
    if $ncurses_is_active
      res = PandoraCui.show_panobject_list(panobject_class, widget, page_sw, \
        auto_create, fix_filter)
    elsif $gtk_is_active
      res = PandoraGtk.show_panobject_list(panobject_class, widget, page_sw, \
        auto_create, fix_filter)
    end
    res
  end

  # Ask user and password for key pair generation
  # RU: Запросить пользователя и пароль для генерации ключевой пары
  def self.ask_user_and_password(rights=nil)
    res = nil
    if $ncurses_is_active
      rights = (PandoraCrypto::KS_Exchange | PandoraCrypto::KS_Robotic)
      PandoraCui.ask_user_and_password(rights) do |*args|
        res = yield(*args) if block_given?
      end
    elsif $gtk_is_active
      rights = (PandoraCrypto::KS_Exchange | PandoraCrypto::KS_Voucher)
      PandoraGtk.ask_user_and_password(rights) do |*args|
        res = yield(*args) if block_given?
      end
    end
    res
  end

  # Ask key and password for authorization
  # RU: Запросить ключ и пароль для авторизации
  def self.ask_key_and_password(alast_auth_key=nil)
    res = nil
    if $ncurses_is_active
      rights = (PandoraCrypto::KS_Exchange | PandoraCrypto::KS_Robotic)
      PandoraCui.ask_key_and_password(alast_auth_key) do |*args|
        res = yield(*args) if block_given?
      end
    elsif $gtk_is_active
      rights = (PandoraCrypto::KS_Exchange | PandoraCrypto::KS_Voucher)
      PandoraGtk.ask_key_and_password(alast_auth_key) do |*args|
        res = yield(*args) if block_given?
      end
    end
    res
  end

  def self.show_dialog(mes, do_if_ok=true)
    res = nil
    if $ncurses_is_active
      res = PandoraCui.show_dialog(mes, do_if_ok) do |*args|
        yield(*args) if block_given?
      end
    elsif $gtk_is_active
      res = PandoraGtk.show_dialog(mes, do_if_ok) do |*args|
        yield(*args) if block_given?
      end
    end
    res
  end

end


module Pandora
  module Gtk

    # Talk dialog
    # RU: Диалог разговора
    class DialogScrollWin < ::Gtk::ScrolledWindow
      attr_accessor :room_id, :targets, :online_button, :snd_button, :vid_button, :talkview, \
        :editbox, :area_send, :area_recv, :recv_media_pipeline, :appsrcs, :session, :ximagesink, \
        :read_thread, :recv_media_queue, :has_unread

      include Pandora::Gtk

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

        model = Pandora::Utils.get_model('Node')

        set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        #sw.name = title
        #sw.add(treeview)
        border_width = 0

        image = ::Gtk::Image.new(::Gtk::Stock::MEDIA_PLAY, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)

        hpaned = ::Gtk::HPaned.new
        add_with_viewport(hpaned)

        vpaned1 = ::Gtk::VPaned.new
        vpaned2 = ::Gtk::VPaned.new

        @area_recv = ViewDrawingArea.new
        area_recv.set_size_request(320, 240)
        area_recv.modify_bg(::Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))

        res = area_recv.signal_connect('expose-event') do |*args|
          #p 'area_recv '+area_recv.window.xid.inspect
          false
        end

        #avconv -f video4linux2 -i /dev/video0 -vcodec mpeg2video -r 25 -pix_fmt yuv420p -me_method epzs -b 2600k -bt 256k -f rtp rtp://192.168.44.150:5004

        #ffmpeg -f dshow  -framerate 20 -i video=screen-capture-recorder -vf scale=1280:720 -vcodec libx264 -pix_fmt yuv420p -tune zerolatency -preset ultrafast -f mpegts udp://236.0.0.1:2000
        #mplayer -demuxer +mpegts -framedrop -benchmark ffmpeg://udp://236.0.0.1:2000?fifo_size=100000&buffer_size=10000000

        #avconv -f video4linux2 -i /dev/video1 -vcodec mpeg2video -pix_fmt yuv420p -me_method epzs -b 2600k -bt 256k -f mpegts udp://127.0.0.1:5004?listen
        #mplayer -wid 39846401 -demuxer +mpegts -framedrop -benchmark ffmpeg://udp://127.0.0.1:5004

        #http://stackoverflow.com/questions/24411982/find-better-vp8-parameters-for-robustness-in-udp-streaming-with-libav-ffmpeg
        #avconv -f video4linux2 -i /dev/video0 -s qvga -f webm -s 320x240 -vcodec libvpx -vb 128k tcp://127.0.0.1:5000?listen
        #avplay tcp://127.0.0.1:5000

        #avconv -s qvga -f video4linux2 -i /dev/video0 -r 2 -copyts -b 128k -bt 32k -bufsize 10 -f webm tcp://127.0.0.1:5000?listen
        #avplay -bufsize 10 tcp://127.0.0.1:5000


        hbox = ::Gtk::HBox.new

        bbox = ::Gtk::HBox.new
        bbox.border_width = 5
        bbox.spacing = 5

        @online_button = SafeCheckButton.new(Pandora.t('Online'), true)
        online_button.safe_signal_clicked do |widget|
          if widget.active?
            widget.safe_set_active(false)
            targets[CSI_Nodes].each do |keybase|
              $window.pool.init_session(nil, keybase, 0, self)
            end
          else
            targets[CSI_Nodes].each do |keybase|
              $window.pool.stop_session(nil, keybase, false)
            end
          end
        end
        online_button.safe_set_active(known_node != nil)

        bbox.pack_start(online_button, false, false, 0)

        @snd_button = SafeCheckButton.new(Pandora.t('Sound'), true)
        snd_button.safe_signal_clicked do |widget|
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

        @vid_button = SafeCheckButton.new(Pandora.t('Video'), true)
        vid_button.safe_signal_clicked do |widget|
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

        @talkview = Pandora::Gtk::ExtTextView.new
        talkview.set_readonly(true)
        talkview.set_size_request(200, 200)
        talkview.wrap_mode = ::Gtk::TextTag::WRAP_WORD
        #view.cursor_visible = false
        #view.editable = false

        talkview.buffer.create_tag('you', 'foreground' => $you_color)
        talkview.buffer.create_tag('dude', 'foreground' => $dude_color)
        talkview.buffer.create_tag('you_bold', 'foreground' => $you_color, 'weight' => Pango::FontDescription::WEIGHT_BOLD)
        talkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  'weight' => Pango::FontDescription::WEIGHT_BOLD)

        @editbox = ::Gtk::TextView.new
        editbox.wrap_mode = ::Gtk::TextTag::WRAP_WORD
        editbox.set_size_request(200, 70)

        editbox.grab_focus

        talksw = ::Gtk::ScrolledWindow.new(nil, nil)
        talksw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
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
        Pandora::Gtk.hack_enter_bug(editbox)

        hpaned2 = ::Gtk::HPaned.new
        @area_send = ViewDrawingArea.new
        area_send.set_size_request(120, 90)
        area_send.modify_bg(::Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
        hpaned2.pack1(area_send, false, true)


        option_box = ::Gtk::HBox.new

        sender_box = ::Gtk::VBox.new
        sender_box.pack_start(option_box, false, true, 0)
        sender_box.pack_start(editbox, true, true, 0)

        vouch_btn = SafeCheckButton.new(Pandora.t('vouch'), true)
        vouch_btn.safe_signal_clicked do |widget|
          #update_btn.clicked
        end
        option_box.pack_start(vouch_btn, false, false, 0)

        adjustment = ::Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
        trust_scale = ::Gtk::HScale.new(adjustment)
        trust_scale.set_size_request(90, -1)
        trust_scale.update_policy = ::Gtk::UPDATE_DELAYED
        trust_scale.digits = 1
        trust_scale.draw_value = true
        trust_scale.value = 1.0
        trust_scale.value_pos = ::Gtk::POS_RIGHT
        option_box.pack_start(trust_scale, false, false, 0)

        smile_btn = ::Gtk::Button.new(Pandora.t('smile'))
        option_box.pack_start(smile_btn, false, false, 4)
        game_btn = ::Gtk::Button.new(Pandora.t('game'))
        option_box.pack_start(game_btn, false, false, 4)

        require_sign_btn = SafeCheckButton.new(Pandora.t('require sign'), true)
        require_sign_btn.safe_signal_clicked do |widget|
          #update_btn.clicked
        end
        option_box.pack_start(require_sign_btn, false, false, 0)

        hpaned2.pack2(sender_box, true, true)

        list_sw = ::Gtk::ScrolledWindow.new(nil, nil)
        list_sw.shadow_type = ::Gtk::SHADOW_ETCHED_IN
        list_sw.set_policy(::Gtk::POLICY_NEVER, ::Gtk::POLICY_AUTOMATIC)
        #list_sw.visible = false

        list_store = ::Gtk::ListStore.new(TrueClass, String)
        targets[CSI_Nodes].each do |keybase|
          user_iter = list_store.append
          user_iter[CL_Name] = Pandora::Utils.bytes_to_hex(keybase)
        end

        # create tree view
        list_tree = ::Gtk::TreeView.new(list_store)
        list_tree.rules_hint = true
        list_tree.search_column = CL_Name

        # column for fixed toggles
        renderer = ::Gtk::CellRendererToggle.new
        renderer.signal_connect('toggled') do |cell, path_str|
          path = ::Gtk::TreePath.new(path_str)
          iter = list_store.get_iter(path)
          fixed = iter[CL_Online]
          p 'fixed='+fixed.inspect
          fixed ^= 1
          iter[CL_Online] = fixed
        end

        tit_image = ::Gtk::Image.new(::Gtk::Stock::CONNECT, ::Gtk::IconSize::MENU)
        #tit_image.set_padding(2, 0)
        tit_image.show_all

        column = ::Gtk::TreeViewColumn.new('', renderer, 'active' => CL_Online)

        #title_widget = ::Gtk::HBox.new
        #title_widget.pack_start(tit_image, false, false, 0)
        #title_label = ::Gtk::Label.new(Pandora.t('People'))
        #title_widget.pack_start(title_label, false, false, 0)
        column.widget = tit_image


        # set this column to a fixed sizing (of 50 pixels)
        #column.sizing = ::Gtk::TreeViewColumn::FIXED
        #column.fixed_width = 50
        list_tree.append_column(column)

        # column for description
        renderer = ::Gtk::CellRendererText.new

        column = ::Gtk::TreeViewColumn.new(Pandora.t('Nodes'), renderer, 'text' => CL_Name)
        column.set_sort_column_id(CL_Name)
        list_tree.append_column(column)

        list_sw.add(list_tree)

        hpaned3 = ::Gtk::HPaned.new
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

      # Put message to dialog
      # RU: Добавляет сообщение в диалог
      def add_mes_to_view(mes, key_or_panhash=nil, myname=nil, modified=nil, \
      created=nil, to_end=nil)

        if mes
          notice = false
          if not myname
            mykey = Pandora::Crypto.current_key(false, false)
            myname = Pandora::Crypto.short_name_of_person(mykey)
          end

          time_style = 'you'
          name_style = 'you_bold'
          user_name = nil
          if key_or_panhash
            if key_or_panhash.is_a? String
              user_name = Pandora::Crypto.short_name_of_person(nil, key_or_panhash, 0, myname)
            else
              user_name = Pandora::Crypto.short_name_of_person(key_or_panhash, nil, 0, myname)
            end
            time_style = 'dude'
            name_style = 'dude_bold'
            notice = (not to_end.is_a? FalseClass)
          else
            user_name = myname
            #if not user_name
            #  mykey = Pandora::Crypto.current_key(false, false)
            #  user_name = Pandora::Crypto.short_name_of_person(mykey)
            #end
          end
          user_name = 'noname' if (not user_name) or (user_name=='')

          time_now = Time.now
          created = time_now if (not modified) and (not created)

          #vals = time_now.to_a
          #ny, nm, nd = vals[5], vals[4], vals[3]
          #midnight = Time.local(y, m, d)
          ##midnight = Pandora::Utils.calc_midnight(time_now)

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
          time_str << Pandora::Utils.time_to_dialog_str(created, time_now) if created
          if modified and ((not created) or ((modified.to_i-created.to_i).abs>30))
            time_str << ' ' if (time_str != '')
            time_str << '('+Pandora::Utils.time_to_dialog_str(modified, time_now)+')'
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

      # Load history of messages
      # RU: Подгрузить историю сообщений
      def load_history(max_message=6, sort_mode=0)
        if talkview and max_message and (max_message>0)
          messages = []
          fields = 'creator, created, destination, state, text, panstate, modified'

          mypanhash = Pandora::Crypto.current_user_or_key(true)
          myname = Pandora::Crypto.short_name_of_person(nil, mypanhash)

          persons = targets[CSI_Persons]
          nil_create_time = false
          persons.each do |person|
            model = Pandora::Utils.get_model('Message')
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

      # Get name and family
      # RU: Определить имя и фамилию
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
            aname, afamily = Pandora::Crypto.name_and_family_of_person(nil, person)
            person_recs[i] = [aname, afamily]
          end
        end
        [aname, afamily]
      end

      # Set session
      # RU: Задать сессию
      def set_session(session, online=true)
        @sessions ||= []
        if online
          @sessions << session if (not @sessions.include?(session))
        else
          @sessions.delete(session)
          session.conn_mode = (session.conn_mode & (~Pandora::Net::CM_KeepHere))
          session.dialog = nil
        end
        active = (@sessions.size>0)
        online_button.safe_set_active(active) if (not online_button.destroyed?)
        if not active
          snd_button.active = false if (not snd_button.destroyed?) and snd_button.active?
          vid_button.active = false if (not vid_button.destroyed?) and vid_button.active?
          #snd_button.safe_set_active(false) if (not snd_button.destroyed?)
          #vid_button.safe_set_active(false) if (not vid_button.destroyed?)
        end
      end

      # Send message to node
      # RU: Отправляет сообщение на узел
      def add_and_send_mes(text)
        res = false
        creator = Pandora::Crypto.current_user_or_key(true)
        if creator
          online_button.active = true if (not online_button.active?)
          #Thread.pass
          time_now = Time.now.to_i
          state = 0
          targets[CSI_Persons].each do |panhash|
            #p 'ADD_MESS panhash='+panhash.inspect
            values = {:destination=>panhash, :text=>text, :state=>state, \
              :creator=>creator, :created=>time_now, :modified=>time_now}
            model = Pandora::Utils.get_model('Message')
            panhash = model.panhash(values)
            values['panhash'] = panhash
            res1 = model.update(values, nil, nil)
            res = (res or res1)
          end
          dlg_sessions = $window.pool.sessions_on_dialog(self)
          dlg_sessions.each do |session|
            session.conn_mode = (session.conn_mode | Pandora::Net::CM_KeepHere)
            session.send_state = (session.send_state | Pandora::Net::CSF_Message)
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
            tab_widget.label.modify_fg(::Gtk::STATE_NORMAL, color)
            tab_widget.label.modify_fg(::Gtk::STATE_ACTIVE, color)
            $statusicon.set_message(Pandora.t('Message')+' ['+tab_widget.label.text+']')
            Pandora::Utils.play_mp3('message')
          end
          # run reading thread
          timer_setted = false
          if (not self.read_thread) and (curpage == self) and $window.visible? and $window.has_toplevel_focus?
            #color = $window.modifier_style.text(::Gtk::STATE_NORMAL)
            #curcolor = tab_widget.label.modifier_style.fg(::Gtk::STATE_ACTIVE)
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
                      tab_widget.label.modify_fg(::Gtk::STATE_NORMAL, nil)
                      tab_widget.label.modify_fg(::Gtk::STATE_ACTIVE, nil)
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
          if (not area.destroyed?) and area.window and sink and (sink.class.method_defined? 'set_xwindow_id')
            win_id = nil
            if Pandora::Utils.os_family=='windows'
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
        src         = Pandora::Utils.get_param(src_param)
        send_caps   = Pandora::Utils.get_param(send_caps_param)
        send_tee    = Pandora::Utils.get_param(send_tee_param)
        view1       = Pandora::Utils.get_param(view1_param)
        can_encoder = Pandora::Utils.get_param(can_encoder_param)
        can_sink    = Pandora::Utils.get_param(can_sink_param)

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
      def init_video_sender(start=true, just_upd_area=false)
        video_pipeline = $send_media_pipelines['video']
        if not start
          if $webcam_xvimagesink and (Pandora::Utils::elem_playing?($webcam_xvimagesink))
            $webcam_xvimagesink.pause
          end
          if just_upd_area
            area_send.set_expose_event(nil)
            tsw = Pandora::Gtk.find_another_active_sender(self)
            if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
            and tsw.area_send and tsw.area_send.window
              link_sink_to_area($webcam_xvimagesink, tsw.area_send)
              #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
            end
            #p '--LEAVE'
            area_send.queue_draw if area_send and (not area_send.destroyed?)
          else
            #$webcam_xvimagesink.xwindow_id = 0
            count = Pandora::Gtk.nil_send_ptrind_by_room(room_id)
            if video_pipeline and (count==0) and (not Pandora::Utils::elem_stopped?(video_pipeline))
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
              winos = (Pandora::Utils.os_family == 'windows')
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

              src_param = Pandora::Utils.get_param('video_src')
              send_caps_param = Pandora::Utils.get_param('video_send_caps')
              send_tee_param = 'video_send_tee_def'
              view1_param = Pandora::Utils.get_param('video_view1')
              can_encoder_param = Pandora::Utils.get_param('video_can_encoder')
              can_sink_param = 'video_can_sink_app'

              video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink \
                = get_video_sender_params(src_param, send_caps_param, send_tee_param, view1_param, \
                  can_encoder_param, can_sink_param)
              p [src_param, send_caps_param, send_tee_param, view1_param, \
                  can_encoder_param, can_sink_param]
              p [video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink]

              if winos
                video_src = Pandora::Utils.get_param('video_src_win')
                video_src ||= 'dshowvideosrc'
                #video_src ||= 'videotestsrc'
                video_view1 = Pandora::Utils.get_param('video_view1_win')
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
                $send_media_queues[1] ||= Pandora::Utils::RoundQueue.new(true)
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
              Pandora.logger.warn  Pandora.t(mes)
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
              video_pipeline.stop if (not Pandora::Utils::elem_stopped?(video_pipeline))
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
              video_pipeline.play if (not Pandora::Utils::elem_playing?(video_pipeline))
            else
              ptrind = Pandora::Gtk.set_send_ptrind_by_room(room_id)
              count = Pandora::Gtk.nil_send_ptrind_by_room(nil)
              if count>0
                #Gtk.main_iteration
                #???
                p 'PLAAAAAAAAAAAAAAY 1'
                p Pandora::Utils::elem_playing?(video_pipeline)
                video_pipeline.play if (not Pandora::Utils::elem_playing?(video_pipeline))
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
        can_src     = Pandora::Utils.get_param(can_src_param)
        can_decoder = Pandora::Utils.get_param(can_decoder_param)
        recv_tee    = Pandora::Utils.get_param(recv_tee_param)
        view2       = Pandora::Utils.get_param(view2_param)

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
        if not start
          if ximagesink and (Pandora::Utils::elem_playing?(ximagesink))
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
              winos = (Pandora::Utils.os_family == 'windows')
              @recv_media_queue[1] ||= Pandora::Utils::RoundQueue.new
              dialog_id = '_v'+Pandora::Utils.bytes_to_hex(room_id[-6..-1])
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
              can_decoder_param = Pandora::Utils.get_param('video_can_decoder')
              recv_tee_param = 'video_recv_tee_def'
              view2_param = Pandora::Utils.get_param('video_view2')

              video_can_src, video_can_decoder, video_recv_tee, video_view2 \
                = get_video_receiver_params(can_src_param, can_decoder_param, \
                  recv_tee_param, view2_param)

              if winos
                video_view2 = Pandora::Utils.get_param('video_view2_win')
                video_view2 ||= 'queue ! directdrawsink'
              end

              @appsrcs[1], pad = add_elem_to_pipe(video_can_src, vidpipe, nil, nil, dialog_id)
              decoder, pad = add_elem_to_pipe(video_can_decoder, vidpipe, appsrcs[1], pad, dialog_id)
              recv_tee, pad = add_elem_to_pipe(video_recv_tee, vidpipe, decoder, pad, dialog_id)
              @ximagesink, pad = add_elem_to_pipe(video_view2, vidpipe, recv_tee, pad, dialog_id)
            rescue => err
              @recv_media_pipeline[1] = nil
              mes = 'Video receiver init exception'
              Pandora.logger.warn  Pandora.t(mes)
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
            if (not Pandora::Utils::elem_playing?(recv_media_pipeline[1])) or (not Pandora::Utils::elem_playing?(ximagesink))
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
        src = Pandora::Utils.get_param(src_param)
        send_caps = Pandora::Utils.get_param(send_caps_param)
        send_tee = Pandora::Utils.get_param(send_tee_param)
        can_encoder = Pandora::Utils.get_param(can_encoder_param)
        can_sink = Pandora::Utils.get_param(can_sink_param)

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
        #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+snd_button.active?.inspect
        if not start
          #count = Pandora::Gtk.nil_send_ptrind_by_room(room_id)
          #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
          if audio_pipeline and (not Pandora::Utils::elem_stopped?(audio_pipeline))
            audio_pipeline.stop
          end
        elsif (not self.destroyed?) and (not snd_button.destroyed?) and snd_button.active?
          if not audio_pipeline
            begin
              Gst.init
              winos = (Pandora::Utils.os_family == 'windows')
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

              src_param = Pandora::Utils.get_param('audio_src')
              send_caps_param = Pandora::Utils.get_param('audio_send_caps')
              send_tee_param = 'audio_send_tee_def'
              can_encoder_param = Pandora::Utils.get_param('audio_can_encoder')
              can_sink_param = 'audio_can_sink_app'

              audio_src, audio_send_caps, audio_send_tee, audio_can_encoder, audio_can_sink  \
                = get_audio_sender_params(src_param, send_caps_param, send_tee_param, \
                  can_encoder_param, can_sink_param)

              if winos
                audio_src = Pandora::Utils.get_param('audio_src_win')
                audio_src ||= 'dshowaudiosrc'
              end

              micro, pad = add_elem_to_pipe(audio_src, audio_pipeline)
              capsfilter, pad = add_elem_to_pipe(audio_send_caps, audio_pipeline, micro, pad)
              tee, teepad = add_elem_to_pipe(audio_send_tee, audio_pipeline, capsfilter, pad)
              audenc, pad = add_elem_to_pipe(audio_can_encoder, audio_pipeline, tee, teepad)
              appsink, pad = add_elem_to_pipe(audio_can_sink, audio_pipeline, audenc, pad)

              $send_media_queues[0] ||= Pandora::Utils::RoundQueue.new(true)
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
              Pandora.logger.warn  Pandora.t(mes)
              puts mes+': '+err.message
              snd_button.active = false
            end
          end

          if audio_pipeline
            ptrind = Pandora::Gtk.set_send_ptrind_by_room(room_id)
            count = Pandora::Gtk.nil_send_ptrind_by_room(nil)
            #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
            if (count>0) and (not Pandora::Utils::elem_playing?(audio_pipeline))
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
        can_src     = Pandora::Utils.get_param(can_src_param)
        can_decoder = Pandora::Utils.get_param(can_decoder_param)
        recv_tee    = Pandora::Utils.get_param(recv_tee_param)
        phones      = Pandora::Utils.get_param(phones_param)

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
          if recv_media_pipeline[0] and (not Pandora::Utils::elem_stopped?(recv_media_pipeline[0]))
            recv_media_pipeline[0].stop
          end
        elsif (not self.destroyed?)
          if (not recv_media_pipeline[0]) and init
            begin
              Gst.init
              winos = (Pandora::Utils.os_family == 'windows')
              @recv_media_queue[0] ||= Pandora::Utils::RoundQueue.new
              dialog_id = '_a'+Pandora::Utils.bytes_to_hex(room_id[-6..-1])
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
              can_decoder_param = Pandora::Utils.get_param('audio_can_decoder')
              recv_tee_param = 'audio_recv_tee_def'
              phones_param = Pandora::Utils.get_param('audio_phones')

              audio_can_src, audio_can_decoder, audio_recv_tee, audio_phones \
                = get_audio_receiver_params(can_src_param, can_decoder_param, recv_tee_param, phones_param)

              if winos
                audio_phones = Pandora::Utils.get_param('audio_phones_win')
                audio_phones ||= 'autoaudiosink'
              end

              @appsrcs[0], pad = add_elem_to_pipe(audio_can_src, audpipe, nil, nil, dialog_id)
              auddec, pad = add_elem_to_pipe(audio_can_decoder, audpipe, appsrcs[0], pad, dialog_id)
              recv_tee, pad = add_elem_to_pipe(audio_recv_tee, audpipe, auddec, pad, dialog_id)
              audiosink, pad = add_elem_to_pipe(audio_phones, audpipe, recv_tee, pad, dialog_id)
            rescue => err
              @recv_media_pipeline[0] = nil
              mes = 'Audio receiver init exception'
              Pandora.logger.warn  Pandora.t(mes)
              puts mes+': '+err.message
              snd_button.active = false
            end
            recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
          end
          if recv_media_pipeline[0] and can_play
            recv_media_pipeline[0].play if (not Pandora::Utils::elem_playing?(recv_media_pipeline[0]))
          end
        end
      end
    end  #--class DialogScrollWin

  end
end
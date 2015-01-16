module Pandora
  module Gtk

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

  end
end
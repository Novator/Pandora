module Pandora
  module Gtk

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

            date = Pandora::Utils.str_to_date(@entry.text)
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
                @entry.text = Pandora::Utils.date_to_str(Time.local(year, month, day))
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

  end
end
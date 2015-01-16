module Pandora
  module Gtk

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

  end
end
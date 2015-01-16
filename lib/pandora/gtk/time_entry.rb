module Pandora
  module Gtk

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

  end
end
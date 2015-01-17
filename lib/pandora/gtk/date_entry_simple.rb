module Pandora
  module Gtk

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

  end
end
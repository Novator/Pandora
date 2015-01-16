module Pandora
  module Gtk

    # Entry for integer
    # RU: Поле ввода целых чисел
    class IntegerEntry < MaskEntry
      def init_mask
        super
        @mask = '0123456789-'
        self.max_length = 20
      end
    end

  end
end
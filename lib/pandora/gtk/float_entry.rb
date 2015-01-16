module Pandora
  module Gtk

    # Entry for float
    # RU: Поле ввода дробных чисел
    class FloatEntry < IntegerEntry
      def init_mask
        super
        @mask += '.e'
        self.max_length = 35
      end
    end

  end
end
module Pandora
  module Gtk

    # Entry for coordinate
    # RU: Поле ввода координаты
    class CoordEntry < FloatEntry
      def init_mask
        super
        @mask += 'EsNn SwW\'"`′″,'
        self.max_length = 35
      end
    end

  end
end
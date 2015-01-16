module Pandora
  module Gtk

    # Entry for HEX
    # RU: Поле ввода шестнадцатеричных чисел
    class HexEntry < MaskEntry
      def init_mask
        super
        @mask = '0123456789abcdefABCDEF'
      end
    end

  end
end
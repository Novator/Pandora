module Pandora
  module Gtk

    Base64chars = [('0'..'9').to_a, ('a'..'z').to_a, ('A'..'Z').to_a, '+/=-_*[]'].join

    # Entry for Base64
    # RU: Поле ввода Base64
    class Base64Entry < MaskEntry
      def init_mask
        super
        @mask = Base64chars
      end
    end

  end
end
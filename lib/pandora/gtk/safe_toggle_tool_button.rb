module Pandora
  module Gtk

    # ToggleToolButton with safety "active" switching
    # RU: ToggleToolButton с безопасным переключением "active"
    class SafeToggleToolButton < ::Gtk::ToggleToolButton

      # Remember signal handler
      # RU: Запомнить обработчик сигнала
      def safe_signal_clicked
        @clicked_signal = self.signal_connect('clicked') do |*args|
          yield(*args) if block_given?
        end
      end

      # Set "active" property safety
      # RU: Безопасно установить свойство "active"
      def safe_set_active(an_active)
        if @clicked_signal
          self.signal_handler_block(@clicked_signal) do
            self.active = an_active
          end
        else
          self.active = an_active
        end
      end

    end

  end
end
module Pandora
  module Gtk

    # DrawingArea for video output
    # RU: DrawingArea для вывода видео
    class ViewDrawingArea < ::Gtk::DrawingArea
      attr_accessor :expose_event

      def initialize
        super
        #set_size_request(100, 100)
        #@expose_event = signal_connect('expose-event') do
        #  alloc = self.allocation
        #  self.window.draw_arc(self.style.fg_gc(self.state), true, \
        #    0, 0, alloc.width, alloc.height, 0, 64 * 360)
        #end
      end

      # Set expose event handler
      # RU: Устанавливает обработчик события expose
      def set_expose_event(value)
        signal_handler_disconnect(@expose_event) if @expose_event
        @expose_event = value
      end
    end

  end
end

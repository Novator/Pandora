module Pandora
  module Gtk

    # Entry with allowed symbols of mask
    # RU: Поле ввода с допустимыми символами в маске
    class MaskEntry < ::Gtk::Entry
      attr_accessor :mask

      def initialize
        super
        signal_connect('key-press-event') do |widget, event|
          res = false
          if not key_event(widget, event)
            if (not event.state.control_mask?) and (event.keyval<60000) \
            and (mask.is_a? String) and (mask.size>0)
              res = (not mask.include?(event.keyval.chr))
            end
          end
          res
        end
        @mask = nil
        init_mask
        if mask and (mask.size>0)
          prefix = self.tooltip_text
          if prefix and (prefix != '')
            prefix << "\n"
          end
          prefix ||= ''
          self.tooltip_text = prefix+'['+mask+']'
        end
      end

      def init_mask
        #will reinit in child
      end

      def key_event(widget, event)
        false
      end
    end

  end
end
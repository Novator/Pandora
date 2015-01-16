module Pandora
  module Gtk

    # Captcha panel
    # RU: Панель с капчой
    class CaptchaHPaned < ::Gtk::HPaned
      attr_accessor :csw

      # Show panel
      # RU: Показать панель
      def initialize(first_child)
        super()
        @first_child = first_child
        self.pack1(@first_child, true, true)
        @csw = nil
      end

      # Show capcha
      # RU: Показать капчу
      def show_captcha(srckey, captcha_buf=nil, clue_text=nil, node=nil)
        res = nil
        if captcha_buf and (not @csw)
          @csw = ::Gtk::ScrolledWindow.new(nil, nil)
          csw = @csw

          csw.signal_connect('destroy-event') do
            show_captcha(srckey)
          end

          @vbox = ::Gtk::VBox.new
          vbox = @vbox

          csw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
          csw.add_with_viewport(vbox)

          pixbuf_loader = Gdk::PixbufLoader.new
          pixbuf_loader.last_write(captcha_buf) if captcha_buf

          label = ::Gtk::Label.new(_('Far node'))
          vbox.pack_start(label, false, false, 2)
          entry = ::Gtk::Entry.new
          node_text = PandoraUtils.bytes_to_hex(srckey)
          node_text = node if (not node_text) or (node_text=='')
          node_text ||= ''
          entry.text = node_text
          entry.editable = false
          vbox.pack_start(entry, false, false, 2)

          image = ::Gtk::Image.new(pixbuf_loader.pixbuf)
          vbox.pack_start(image, false, false, 2)

          clue_text ||= ''
          clue, length, symbols = clue_text.split('|')
          #p '    [clue, length, symbols]='+[clue, length, symbols].inspect

          len = 0
          begin
            len = length.to_i if length
          rescue
          end

          label = ::Gtk::Label.new(_('Enter text from picture'))
          vbox.pack_start(label, false, false, 2)

          captcha_entry = Pandora::Gtk::MaskEntry.new
          captcha_entry.max_length = len
          if symbols
            mask = symbols.downcase+symbols.upcase
            captcha_entry.mask = mask
          end

          okbutton = ::Gtk::Button.new(::Gtk::Stock::OK)
          okbutton.signal_connect('clicked') do
            text = captcha_entry.text
            yield(text) if block_given?
            show_captcha(srckey)
          end

          cancelbutton = ::Gtk::Button.new(::Gtk::Stock::CANCEL)
          cancelbutton.signal_connect('clicked') do
            yield(false) if block_given?
            show_captcha(srckey)
          end

          captcha_entry.signal_connect('key-press-event') do |widget, event|
            if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
              okbutton.activate
              true
            elsif (Gdk::Keyval::GDK_Escape==event.keyval)
              captcha_entry.text = ''
              cancelbutton.activate
              false
            else
              false
            end
          end
          Pandora::Gtk.hack_enter_bug(captcha_entry)

          ew = 150
          if len>0
            str = label.text
            label.text = 'W'*(len+1)
            ew,lh = label.size_request
            label.text = str
          end

          captcha_entry.width_request = ew
          align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
          align.add(captcha_entry)
          vbox.pack_start(align, false, false, 2)
          #capdialog.def_widget = entry

          hbox = ::Gtk::HBox.new
          hbox.pack_start(okbutton, true, true, 2)
          hbox.pack_start(cancelbutton, true, true, 2)

          vbox.pack_start(hbox, false, false, 2)

          if clue
            label = ::Gtk::Label.new(_(clue))
            vbox.pack_start(label, false, false, 2)
          end
          if length
            label = ::Gtk::Label.new(_('Length')+'='+length.to_s)
            vbox.pack_start(label, false, false, 2)
          end
          if symbols
            sym_text = _('Symbols')+': '+symbols.to_s
            i = 30
            while i<sym_text.size do
              sym_text = sym_text[0,i]+"\n"+sym_text[i+1..-1]
              i += 31
            end
            label = ::Gtk::Label.new(sym_text)
            vbox.pack_start(label, false, false, 2)
          end

          csw.border_width = 1;
          csw.set_size_request(250, -1)
          self.border_width = 2
          self.pack2(csw, true, true)  #hpaned3                                      9
          csw.show_all
          full_width = $window.allocation.width
          self.position = full_width-250 #self.max_position #@csw.width_request
          Pandora::Gtk.hack_grab_focus(captcha_entry)
          res = csw
        else
          #@csw.width_request = @csw.allocation.width
          @csw.destroy if (not @csw.destroyed?)
          @csw = nil
          self.position = 0
        end
        res
      end
    end  #--CaptchaHPaned

  end
end
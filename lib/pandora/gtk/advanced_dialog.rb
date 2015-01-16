module Pandora
  module Gtk

    # Advanced dialog window
    # RU: Продвинутое окно диалога
    class AdvancedDialog < ::Gtk::Window #::Gtk::Dialog
      attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, \
        :enter_like_tab, :enter_like_ok, :panelbox, :okbutton, :cancelbutton, \
        :def_widget, :main_sw

      # Create method
      # RU: Метод создания
      def initialize(*args)
        p '0----------'
        super(*args)
        p '1----------'
        @response = 0
        @window = self
        @enter_like_tab = false
        @enter_like_ok = true
        set_default_size(300, -1)

        window.transient_for = $window
        window.modal = true
        #window.skip_taskbar_hint = true
        window.window_position = ::Gtk::Window::POS_CENTER
        #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG
        window.destroy_with_parent = true

        @vpaned = ::Gtk::VPaned.new
        vpaned.border_width = 2

        window.add(vpaned)
        #window.vbox.add(vpaned)

        @main_sw = ::Gtk::ScrolledWindow.new(nil, nil)
        sw = main_sw
        sw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        @viewport = ::Gtk::Viewport.new(nil, nil)
        sw.add(viewport)

        image = ::Gtk::Image.new(::Gtk::Stock::PROPERTIES, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box1 = TabLabelBox.new(image, _('Basic'), nil, false, 0)

        @notebook = ::Gtk::Notebook.new
        @notebook.scrollable = true
        page = notebook.append_page(sw, label_box1)
        vpaned.pack1(notebook, true, true)

        @panelbox = ::Gtk::VBox.new
        @hbox = ::Gtk::HBox.new
        panelbox.pack_start(hbox, false, false, 0)

        vpaned.pack2(panelbox, false, true)

        bbox = ::Gtk::HBox.new
        bbox.border_width = 2
        bbox.spacing = 4

        @okbutton = ::Gtk::Button.new(::Gtk::Stock::OK)
        okbutton.width_request = 110
        okbutton.signal_connect('clicked') { |*args|
          @response=2
          #finish
        }
        bbox.pack_start(okbutton, false, false, 0)

        @cancelbutton = ::Gtk::Button.new(::Gtk::Stock::CANCEL)
        cancelbutton.width_request = 110
        cancelbutton.signal_connect('clicked') { |*args|
          @response=1
          #finish
        }
        bbox.pack_start(cancelbutton, false, false, 0)

        hbox.pack_start(bbox, true, false, 1.0)

        #self.signal_connect('response') do |widget, response|
        #  case response
        #    when ::Gtk::Dialog::RESPONSE_OK
        #      p "OK"
        #    when ::Gtk::Dialog::RESPONSE_CANCEL
        #      p "Cancel"
        #    when ::Gtk::Dialog::RESPONSE_CLOSE
        #      p "Close"
        #      dialog.destroy
        #  end
        #end

        p '2----------'

        window.signal_connect('delete-event') { |*args|
          @response=1
          false
        }
        window.signal_connect('destroy') { |*args| @response=1 }

        window.signal_connect('key-press-event') do |widget, event|
          if (event.keyval==Gdk::Keyval::GDK_Tab) and enter_like_tab  # Enter works like Tab
            event.hardware_keycode=23
            event.keyval=Gdk::Keyval::GDK_Tab
            window.signal_emit('key-press-event', event)
            true
          elsif
            [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
            and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? ::Gtk::TextView))))
          then
            okbutton.activate
            true
          elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
            ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
          then
            cancelbutton.activate
            false
          elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
            ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
          then
            $window.destroy
            @response=1
            false
          else
            false
          end
        end

      end

      # Show dialog in modal mode
      # RU: Показать диалог в модальном режиме
      def run2
        res = nil
        show_all
        if @def_widget
          #focus = @def_widget
          @def_widget.grab_focus
        end

        while (not destroyed?) and (@response == 0) do
          #unless alien_thread
            ::Gtk.main_iteration
          #end
          sleep(0.001)
          Thread.pass
        end

        if not destroyed?
          if (@response > 1)
            yield(@response) if block_given?
            res = true
          end
          self.destroy
        end

        res
      end
    end

  end
end
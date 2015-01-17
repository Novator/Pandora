module Pandora
  module Gtk

    # Entry for filename
    # RU: Поле выбора имени файла
    class FilenameBox < ::Gtk::HBox
      attr_accessor :entry, :button, :window

      def initialize(parent, *args)
        super(*args)
        @entry = ::Gtk::Entry.new
        @button = ::Gtk::Button.new('...')
        @button.can_focus = false
        @entry.instance_variable_set('@button', @button)
        def @entry.key_event(widget, event)
          res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
            and (event.keyval==65364)))
          @button.activate if res
          false
        end
        @window = parent
        self.pack_start(entry, true, true, 0)
        align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(@button)
        self.pack_start(align, false, false, 1)
        esize = entry.size_request
        h = esize[1]-2
        @button.set_size_request(h, h)

        button.signal_connect('clicked') do |*args|
          @entry.grab_focus
          dialog =  ::Gtk::FileChooserDialog.new(Pandora.t('Choose a file'), @window,
            ::Gtk::FileChooser::ACTION_OPEN, 'gnome-vfs',
            [::Gtk::Stock::OPEN, ::Gtk::Dialog::RESPONSE_ACCEPT],
            [::Gtk::Stock::CANCEL, ::Gtk::Dialog::RESPONSE_CANCEL])

          filter = ::Gtk::FileFilter.new
          filter.name = Pandora.t('All files')+' (*.*)'
          filter.add_pattern('*.*')
          dialog.add_filter(filter)

          filter = ::Gtk::FileFilter.new
          filter.name = Pandora.t('Pictures')+' (png,jpg,gif)'
          filter.add_pattern('*.png')
          filter.add_pattern('*.jpg')
          filter.add_pattern('*.jpeg')
          filter.add_pattern('*.gif')
          dialog.add_filter(filter)

          filter = ::Gtk::FileFilter.new
          filter.name = Pandora.t('Sounds')+' (mp3,wav)'
          filter.add_pattern('*.mp3')
          filter.add_pattern('*.wav')
          dialog.add_filter(filter)

          dialog.add_shortcut_folder(Pandora.files_dir)
          fn = @entry.text
          if fn.nil? or (fn=='')
            dialog.current_folder = Pandora.files_dir
          else
            dialog.filename = fn
          end

          scr = Gdk::Screen.default
          if (scr.height > 700)
            frame = ::Gtk::Frame.new
            frame.shadow_type = ::Gtk::SHADOW_IN
            align = ::Gtk::Alignment.new(0.5, 0.5, 0, 0)
            align.add(frame)
            image = ::Gtk::Image.new
            frame.add(image)
            align.show_all

            dialog.preview_widget = align
            dialog.use_preview_label = false
            dialog.signal_connect('update-preview') do
              filename = dialog.preview_filename
              ext = nil
              ext = File.extname(filename) if filename
              if ext and (['.jpg','.gif','.png'].include? ext.downcase)
                begin
                  pixbuf = Gdk::Pixbuf.new(filename, 128, 128)
                  image.pixbuf = pixbuf
                  dialog.preview_widget_active = true
                rescue
                  dialog.preview_widget_active = false
                end
              else
                dialog.preview_widget_active = false
              end
            end
          end

          if dialog.run == ::Gtk::Dialog::RESPONSE_ACCEPT
            @entry.text = dialog.filename
          end
          dialog.destroy
        end
      end

      def max_length=(maxlen)
        maxlen = 512 if maxlen<512
        entry.max_length = maxlen
      end

      def text=(text)
        entry.text = text
      end

      def text
        entry.text
      end

      def width_request=(wr)
        s = button.size_request
        h = s[0]+1
        wr -= h
        wr = 24 if wr<24
        entry.set_width_request(wr)
      end

      def modify_text(*args)
        entry.modify_text(*args)
      end

      def size_request
        esize = entry.size_request
        res = button.size_request
        res[0] = esize[0]+1+res[0]
        res
      end
    end

  end
end
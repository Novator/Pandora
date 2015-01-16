module Pandora
  module Gtk

    # Entry for panhash
    # RU: Поле ввода панхэша
    class PanhashBox < ::Gtk::HBox
      attr_accessor :types, :panclasses, :entry, :button

      def initialize(panhash_type, *args)
        super(*args)
        @types = panhash_type
        @entry = HexEntry.new
        @button = ::Gtk::Button.new('...')
        @button.can_focus = false
        @entry.instance_variable_set('@button', @button)
        def @entry.key_event(widget, event)
          res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
            and (event.keyval==65364)))
          @button.activate if res
          false
        end
        self.pack_start(entry, true, true, 0)
        align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(@button)
        self.pack_start(align, false, false, 1)
        esize = entry.size_request
        h = esize[1]-2
        @button.set_size_request(h, h)

        #if panclasses==[]
        #  panclasses = $panobject_list
        #end

        button.signal_connect('clicked') do |*args|
          @entry.grab_focus
          set_classes
          dialog = Pandora::Gtk::AdvancedDialog.new(_('Choose object'))
          dialog.set_default_size(600, 400)
          auto_create = true
          panclasses.each_with_index do |panclass, i|
            title = _(Pandora::Utils.get_name_or_names(panclass.name, true))
            dialog.main_sw.destroy if i==0
            image = ::Gtk::Image.new(::Gtk::Stock::INDEX, ::Gtk::IconSize::MENU)
            image.set_padding(2, 0)
            label_box2 = TabLabelBox.new(image, title, nil, false, 0)
            sw = ::Gtk::ScrolledWindow.new(nil, nil)
            page = dialog.notebook.append_page(sw, label_box2)
            auto_create = Pandora::Gtk.show_panobject_list(panclass, nil, sw, auto_create)
            if panclasses.size>MaxPanhashTabs
              break
            end
          end
          dialog.notebook.page = 0
          dialog.run2 do
            panhash = nil
            sw = dialog.notebook.get_nth_page(dialog.notebook.page)
            treeview = sw.children[0]
            if treeview.is_a? SubjTreeView
              path, column = treeview.cursor
              panobject = treeview.panobject
              if path and panobject
                store = treeview.model
                iter = store.get_iter(path)
                id = iter[0]
                sel = panobject.select('id='+id.to_s, false, 'panhash')
                panhash = sel[0][0] if sel and (sel.size>0)
              end
            end
            if PandoraUtils.panhash_nil?(panhash)
              @entry.text = ''
            else
              @entry.text = PandoraUtils.bytes_to_hex(panhash) if (panhash.is_a? String)
            end
          end
          #yield if block_given?
        end
      end

      # Define allowed pandora object classes
      # RU: Определить допустимые классы Пандоры
      def set_classes
        if not panclasses
          #p '=== types='+types.inspect
          @panclasses = []
          @types.strip!
          if (types.is_a? String) and (types.size>0) and (@types[0, 8].downcase=='panhash(')
            @types = @types[8..-2]
            @types.strip!
            @types = @types.split(',')
            @types.each do |ptype|
              ptype.strip!
              if Pandora::Model.const_defined? ptype
                panclasses << Pandora::Model.const_get(ptype)
              end
            end
          end
          #p 'panclasses='+panclasses.inspect
        end
      end

      def max_length=(maxlen)
        entry.max_length = maxlen
      end

      def text=(text)
        entry.text = text
      end

      def text
        entry.text
      end

      def width_request=(wr)
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
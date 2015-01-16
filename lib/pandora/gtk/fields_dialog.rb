module Pandora
  module Gtk

    # Dialog with enter fields
    # RU: Диалог с полями ввода
    class FieldsDialog < AdvancedDialog

      attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
        :keep_btn, :rate_label, :vouch_btn, :follow_btn, :trust_scale, :trust0, :public_btn, \
        :public_scale, :lang_entry, :format, :view_buffer, :last_sw

      # Add menu item
      # RU: Добавляет пункт меню
      def add_menu_item(label, menu, text)
        mi = ::Gtk::MenuItem.new(text)
        menu.append(mi)
        mi.signal_connect('activate') do |mi|
          label.label = mi.label
          @format = mi.label.to_s
          p 'format changed to: '+format.to_s
        end
      end

      # Set view text buffer
      # RU: Задает тестовый буфер для просмотра
      def set_view_buffer(format, view_buffer, raw_buffer)
        view_buffer.text = raw_buffer.text
      end

      # Set raw text buffer
      # RU: Задает сырой тестовый буфер
      def set_raw_buffer(format, raw_buffer, view_buffer)
        raw_buffer.text = view_buffer.text
      end

      # Set buffers
      # RU: Задать буферы
      def set_buffers(init=false)
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? ::Gtk::ScrolledWindow) and (child.children[0].is_a? ::Gtk::TextView)
          tv = child.children[0]
          if init or not @raw_buffer
            @raw_buffer = tv.buffer
          end
          if @view_mode
            tv.buffer = @view_buffer if tv.buffer != @view_buffer
          elsif tv.buffer != @raw_buffer
            tv.buffer = @raw_buffer
          end

          if @view_mode
            set_view_buffer(format, @view_buffer, @raw_buffer)
          else
            set_raw_buffer(format, @raw_buffer, @view_buffer)
          end
        end
      end

      # Set tag for selection
      # RU: Задать тэг для выделенного
      def set_tag(tag)
        if tag
          child = notebook.get_nth_page(notebook.page)
          if (child.is_a? ::Gtk::ScrolledWindow) and (child.children[0].is_a? ::Gtk::TextView)
            tv = child.children[0]
            buffer = tv.buffer

            if @view_buffer==buffer
              bounds = buffer.selection_bounds
              @view_buffer.apply_tag(tag, bounds[0], bounds[1])
            else
              bounds = buffer.selection_bounds
              ltext = rtext = ''
              case tag
                when 'bold'
                  ltext = rtext = '*'
                when 'italic'
                  ltext = rtext = '/'
                when 'strike'
                  ltext = rtext = '-'
                when 'undline'
                  ltext = rtext = '_'
              end
              lpos = bounds[0].offset
              rpos = bounds[1].offset
              if ltext != ''
                @raw_buffer.insert(@raw_buffer.get_iter_at_offset(lpos), ltext)
                lpos += ltext.length
                rpos += ltext.length
              end
              if rtext != ''
                @raw_buffer.insert(@raw_buffer.get_iter_at_offset(rpos), rtext)
              end
              p [lpos, rpos]
              #buffer.selection_bounds = [bounds[0], rpos]
              @raw_buffer.move_mark('selection_bound', @raw_buffer.get_iter_at_offset(lpos))
              @raw_buffer.move_mark('insert', @raw_buffer.get_iter_at_offset(rpos))
              #@raw_buffer.get_iter_at_offset(0)
            end
          end
        end
      end

      class BodyScrolledWindow < ::Gtk::ScrolledWindow
        attr_accessor :field, :link_name, :text_view
      end

      # Start loading image from file
      # RU: Запускает загрузку картинки в файл
      def start_image_loading(filename)
        begin
          image_stream = File.open(filename, 'rb')
          image = ::Gtk::Image.new
          widget = image
          Thread.new do
            pixbuf_loader = Gdk::PixbufLoader.new
            pixbuf_loader.signal_connect('area_prepared') do |loader|
              pixbuf = loader.pixbuf
              pixbuf.fill!(0xaaaaaaff)
              image.pixbuf = pixbuf
            end
            pixbuf_loader.signal_connect('area_updated') do
              image.queue_draw
            end
            while image_stream
              buf = image_stream.read(1024*1024)
              pixbuf_loader.write(buf)
              if image_stream.eof?
                image_stream.close
                image_stream = nil
                pixbuf_loader.close
                pixbuf_loader = nil
              end
              sleep(0.005)
            end
          end
        rescue => err
          err_text = _('Image loading error')+":\n"+err.message
          label = ::Gtk::Label.new(err_text)
          widget = label
        end
        widget
      end

      # Create fields dialog
      # RU: Создать форму с полями
      def initialize(apanobject, afields=[], *args)
        super(*args)
        @panobject = apanobject
        @fields = afields

        window.signal_connect('configure-event') do |widget, event|
          window.on_resize_window(widget, event)
          false
        end

        @toolbar = ::Gtk::Toolbar.new
        toolbar.toolbar_style = ::Gtk::Toolbar::Style::ICONS
        panelbox.pack_start(toolbar, false, false, 0)

        @toolbar2 = ::Gtk::Toolbar.new
        toolbar2.toolbar_style = ::Gtk::Toolbar::Style::ICONS
        panelbox.pack_start(toolbar2, false, false, 0)

        @raw_buffer = nil
        @view_mode = true
        @view_buffer = ::Gtk::TextBuffer.new
        @view_buffer.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
        @view_buffer.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
        @view_buffer.create_tag('strike', 'strikethrough' => true)
        @view_buffer.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
        @view_buffer.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
        @view_buffer.create_tag('link', {'foreground' => 'blue', 'underline' => Pango::AttrUnderline::SINGLE})
        @view_buffer.create_tag('linked', {'foreground' => 'navy', 'underline' => Pango::AttrUnderline::SINGLE})
        @view_buffer.create_tag('left', 'justification' => ::Gtk::JUSTIFY_LEFT)
        @view_buffer.create_tag('center', 'justification' => ::Gtk::JUSTIFY_CENTER)
        @view_buffer.create_tag('right', 'justification' => ::Gtk::JUSTIFY_RIGHT)
        @view_buffer.create_tag('fill', 'justification' => ::Gtk::JUSTIFY_FILL)

        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::DND, 'Type', true) do |btn|
          @view_mode = btn.active?
          set_buffers
        end

        btn = ::Gtk::MenuToolButton.new(nil, 'auto')
        menu = ::Gtk::Menu.new
        btn.menu = menu
        add_menu_item(btn, menu, 'auto')
        add_menu_item(btn, menu, 'plain')
        add_menu_item(btn, menu, 'org-mode')
        add_menu_item(btn, menu, 'bbcode')
        add_menu_item(btn, menu, 'wiki')
        add_menu_item(btn, menu, 'html')
        add_menu_item(btn, menu, 'ruby')
        add_menu_item(btn, menu, 'python')
        add_menu_item(btn, menu, 'xml')
        menu.show_all
        toolbar.add(btn)

        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::BOLD, 'Bold') do |*args|
          set_tag('bold')
        end

        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::ITALIC, 'Italic') do |*args|
          set_tag('italic')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::STRIKETHROUGH, 'Strike') do |*args|
          set_tag('strike')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::UNDERLINE, 'Underline') do |*args|
          set_tag('undline')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::UNDO, 'Undo')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::REDO, 'Redo')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::COPY, 'Copy')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::CUT, 'Cut')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::FIND, 'Find')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_LEFT, 'Left') do |*args|
          set_tag('left')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_RIGHT, 'Right') do |*args|
          set_tag('right')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_CENTER, 'Center') do |*args|
          set_tag('center')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUSTIFY_FILL, 'Fill') do |*args|
          set_tag('fill')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::SAVE, 'Save')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::OPEN, 'Open')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::JUMP_TO, 'Link') do |*args|
          set_tag('link')
        end
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::HOME, 'Image')
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
        Pandora::Gtk.add_tool_btn(toolbar, ::Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::ADD, 'Add')
        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::DELETE, 'Delete')
        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
        Pandora::Gtk.add_tool_btn(toolbar2, ::Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

        @last_sw = nil
        notebook.signal_connect('switch-page') do |widget, page, page_num|
          if (page_num != 1) and @last_sw
            #@last_sw.children.each do |child|
            #  child.destroy if (not child.destroyed?) \
            #    and child.class.method_defined? 'destroy'
            #end
            @last_sw = nil
          end

          if page_num==0
            toolbar.hide
            toolbar2.hide
            hbox.show
          else
            child = notebook.get_nth_page(page_num)
            if (child.is_a? BodyScrolledWindow)
              toolbar2.hide
              hbox.hide
              textsw = child
              field = textsw.field
              if field
                link_name = nil
                link_name = field[FI_Widget].text
                link_name.chomp! if link_name
                if (not field[FI_Widget2]) or (link_name != textsw.link_name)
                  toolbar.show
                  @last_sw = child
                  bodywid = nil
                  if link_name and (link_name != '')
                    if File.exist?(link_name)
                      ext = File.extname(link_name)
                      if ext and (['.jpg','.gif','.png'].include? ext.downcase)
                        image = start_image_loading(link_name)
                        bodywid = image
                        link_name = link_name
                      else
                        link_name = nil
                      end
                    else
                      err_text = _('File does not exist')+":\n"+link_name
                      label = ::Gtk::Label.new(err_text)
                      bodywid = label
                    end
                  else
                    link_name = nil
                  end

                  if not link_name
                    textview = ::Gtk::TextView.new
                    #textview = child.children[0]
                    textview.wrap_mode = ::Gtk::TextTag::WRAP_WORD
                    textview.signal_connect('key-press-event') do |widget, event|
                      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
                        and event.state.control_mask?
                      then
                        true
                      end
                    end
                    textview.buffer.text = field[FI_Value].to_s
                    bodywid = textview
                  end

                  field[FI_Widget2] = bodywid
                  if bodywid.is_a? ::Gtk::TextView
                    textsw.add(bodywid)
                    set_buffers(true)
                  elsif bodywid
                    textsw.add_with_viewport(bodywid)
                  end
                  textsw.show_all
                end
              end
            else
              toolbar.hide
              hbox.hide
              toolbar2.show
            end
          end
        end

        @vbox = ::Gtk::VBox.new
        viewport.add(@vbox)

        @statusbar = ::Gtk::Statusbar.new
        Pandora::Gtk.set_statusbar_text(statusbar, '')
        statusbar.pack_start(::Gtk::SeparatorToolItem.new, false, false, 0)
        panhash_btn = ::Gtk::Button.new(_('Rate: '))
        panhash_btn.relief = ::Gtk::RELIEF_NONE
        statusbar.pack_start(panhash_btn, false, false, 0)

        panelbox.pack_start(statusbar, false, false, 0)


        #rbvbox = ::Gtk::VBox.new

        keep_box = ::Gtk::VBox.new
        @keep_btn = ::Gtk::CheckButton.new(_('keep'), true)
        #keep_btn.signal_connect('toggled') do |widget|
        #  p "keep"
        #end
        #rbvbox.pack_start(keep_btn, false, false, 0)
        #@rate_label = ::Gtk::Label.new('-')
        keep_box.pack_start(keep_btn, false, false, 0)
        @follow_btn = ::Gtk::CheckButton.new(_('follow'), true)
        follow_btn.signal_connect('clicked') do |widget|
          if widget.active?
            @keep_btn.active = true
          end
        end
        keep_box.pack_start(follow_btn, false, false, 0)

        @lang_entry = ::Gtk::Combo.new
        lang_entry.set_popdown_strings(PandoraModel.lang_list)
        lang_entry.entry.text = ''
        lang_entry.entry.select_region(0, -1)
        lang_entry.set_size_request(50, -1)
        keep_box.pack_start(lang_entry, true, true, 5)

        hbox.pack_start(keep_box, false, false, 0)

        trust_box = ::Gtk::VBox.new

        trust0 = nil
        @trust_scale = nil
        @vouch_btn = ::Gtk::CheckButton.new(_('vouch'), true)
        vouch_btn.signal_connect('clicked') do |widget|
          if not widget.destroyed?
            if widget.inconsistent?
              if PandoraCrypto.current_user_or_key(false)
                widget.inconsistent = false
                widget.active = true
                trust0 ||= 0.1
              end
            end
            trust_scale.sensitive = widget.active?
            if widget.active?
              trust0 ||= 0.1
              trust_scale.value = trust0
              @keep_btn.active = true
            else
              trust0 = trust_scale.value
            end
          end
        end
        trust_box.pack_start(vouch_btn, false, false, 0)

        #@scale_button = ::Gtk::ScaleButton.new(::Gtk::IconSize::BUTTON)
        #@scale_button.set_icons(['gtk-goto-bottom', 'gtk-goto-top', 'gtk-execute'])
        #@scale_button.signal_connect('value-changed') { |widget, value| puts "value changed: #{value}" }

        tips = [_('evil'), _('destructive'), _('dirty'), _('harmful'), _('bad'), _('vain'), \
          _('good'), _('useful'), _('constructive'), _('creative'), _('genial')]

        #@trust ||= (127*0.4).round
        #val = trust/127.0
        adjustment = ::Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
        @trust_scale = ::Gtk::HScale.new(adjustment)
        trust_scale.set_size_request(140, -1)
        trust_scale.update_policy = ::Gtk::UPDATE_DELAYED
        trust_scale.digits = 1
        trust_scale.draw_value = true
        step = 254.fdiv(tips.size-1)
        trust_scale.signal_connect('value-changed') do |widget|
          #val = (widget.value*20).round/20.0
          val = widget.value
          #widget.value = val #if (val-widget.value).abs>0.05
          trust = (val*127).round
          #vouch_lab.text = sprintf('%2.1f', val) #trust.fdiv(127))
          r = 0
          g = 0
          b = 0
          if trust==0
            b = 40000
          else
            mul = ((trust.fdiv(127))*45000).round
            if trust>0
              g = mul+20000
            else
              r = -mul+20000
            end
          end
          tip = val.to_s
          color = Gdk::Color.new(r, g, b)
          widget.modify_fg(::Gtk::STATE_NORMAL, color)
          @vouch_btn.modify_bg(::Gtk::STATE_ACTIVE, color)
          i = ((trust+127)/step).round
          tip = tips[i]
          widget.tooltip_text = tip
        end
        #scale.signal_connect('change-value') do |widget|
        #  true
        #end
        trust_box.pack_start(trust_scale, false, false, 0)
        hbox.pack_start(trust_box, false, false, 0)

        pub_lev0 = nil
        public_box = ::Gtk::VBox.new
        @public_btn = ::Gtk::CheckButton.new(_('public'), true)
        public_btn.signal_connect('clicked') do |widget|
          if not widget.destroyed?
            if widget.inconsistent?
              if PandoraCrypto.current_user_or_key(false)
                widget.inconsistent = false
                widget.active = true
                pub_lev0 ||= 0.0
              end
            end
            public_scale.sensitive = widget.active?
            if widget.active?
              pub_lev0 ||= 0.0
              public_scale.value = pub_lev0
              @keep_btn.active = true
              @follow_btn.active = true
              @vouch_btn.active = true
            else
              pub_lev0 = public_scale.value
            end
          end
        end
        public_box.pack_start(public_btn, false, false, 0)

        #@lang_entry = ::Gtk::ComboBoxEntry.new(true)
        #lang_entry.set_size_request(60, 15)
        #lang_entry.append_text('0')
        #lang_entry.append_text('1')
        #lang_entry.append_text('5')

        #@lang_entry = ::Gtk::Combo.new
        #@lang_entry.set_popdown_strings(['0','1','5'])
        #@lang_entry.entry.text = ''
        #@lang_entry.entry.select_region(0, -1)
        #@lang_entry.set_size_request(50, -1)
        #public_box.pack_start(lang_entry, true, true, 5)

        adjustment = ::Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
        @public_scale = ::Gtk::HScale.new(adjustment)
        public_scale.set_size_request(140, -1)
        public_scale.update_policy = ::Gtk::UPDATE_DELAYED
        public_scale.digits = 1
        public_scale.draw_value = true
        step = 19.fdiv(tips.size-1)
        public_scale.signal_connect('value-changed') do |widget|
          val = widget.value
          trust = (val*10).round
          r = 0
          g = 0
          b = 0
          if trust==0
            b = 40000
          else
            mul = ((trust.fdiv(10))*45000).round
            if trust>0
              g = mul+20000
            else
              r = -mul+20000
            end
          end
          tip = val.to_s
          color = Gdk::Color.new(r, g, b)
          widget.modify_fg(::Gtk::STATE_NORMAL, color)
          @vouch_btn.modify_bg(::Gtk::STATE_ACTIVE, color)
          i = ((trust+127)/step).round
          tip = tips[i]
          widget.tooltip_text = tip
        end
        public_box.pack_start(public_scale, false, false, 0)

        hbox.pack_start(public_box, false, false, 0)
        hbox.show_all

        bw,bh = hbox.size_request
        @btn_panel_height = bh

        # devide text fields in separate list

        @text_fields = Array.new
        i = @fields.size
        while i>0 do
          i -= 1
          field = @fields[i]
          atext = field[FI_VFName]
          #atype = field[FI_Type]
          #if (atype=='Blob') or (atype=='Text')
          aview = field[FI_View]
          if (aview=='blob') or (aview=='text')
            textsw = BodyScrolledWindow.new(nil, nil)
            textsw.set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)

            image = ::Gtk::Image.new(::Gtk::Stock::DND, ::Gtk::IconSize::MENU)
            image.set_padding(2, 0)
            label_box = TabLabelBox.new(image, atext, nil, false, 0)
            page = notebook.append_page(textsw, label_box)

            #field[FI_Widget] = textview

            field << page
            @text_fields << field
            textsw.field = field

            #@fields.delete_at(i) if (atype=='Text')
          end
        end

        image = ::Gtk::Image.new(::Gtk::Stock::INDEX, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box2 = TabLabelBox.new(image, _('Relations'), nil, false, 0)
        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        page = notebook.append_page(sw, label_box2)

        Pandora::Gtk.show_panobject_list(PandoraModel::Relation, nil, sw)

        image = ::Gtk::Image.new(::Gtk::Stock::DIALOG_AUTHENTICATION, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box2 = TabLabelBox.new(image, _('Signs'), nil, false, 0)
        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        page = notebook.append_page(sw, label_box2)

        Pandora::Gtk.show_panobject_list(PandoraModel::Sign, nil, sw)

        image = ::Gtk::Image.new(::Gtk::Stock::DIALOG_INFO, ::Gtk::IconSize::MENU)
        image.set_padding(2, 0)
        label_box2 = TabLabelBox.new(image, _('Opinions'), nil, false, 0)
        sw = ::Gtk::ScrolledWindow.new(nil, nil)
        page = notebook.append_page(sw, label_box2)

        Pandora::Gtk.show_panobject_list(PandoraModel::Opinion, nil, sw)

        # create labels, remember them, calc middle char width
        texts_width = 0
        texts_chars = 0
        labels_width = 0
        max_label_height = 0
        @fields.each do |field|
          atext = field[FI_VFName]
          aview = field[FI_View]
          label = ::Gtk::Label.new(atext)
          label.tooltip_text = aview if aview and (aview.size>0)
          label.xalign = 0.0
          lw,lh = label.size_request
          field[FI_Label] = label
          field[FI_LabW] = lw
          field[FI_LabH] = lh
          texts_width += lw
          texts_chars += atext.length
          #texts_chars += atext.length
          labels_width += lw
          max_label_height = lh if max_label_height < lh
        end
        @middle_char_width = (texts_width.to_f*1.2 / texts_chars).round

        # max window size
        scr = Gdk::Screen.default
        window_width, window_height = [scr.width-50, scr.height-100]
        form_width = window_width-36
        form_height = window_height-@btn_panel_height-55

        # compose first matrix, calc its geometry
        # create entries, set their widths/maxlen, remember them
        entries_width = 0
        max_entry_height = 0
        @def_widget = nil
        @fields.each do |field|
          p 'field='+field.inspect
          max_size = 0
          fld_size = 0
          aview = field[FI_View]
          atype = field[FI_Type]
          entry = nil
          case aview
            when 'integer', 'byte', 'word'
              entry = IntegerEntry.new
            when 'hex'
              entry = HexEntry.new
            when 'real'
              entry = FloatEntry.new
            when 'time'
              entry = TimeEntry.new
            when 'date'
              entry = DateEntry.new
            when 'coord'
              entry = CoordBox.new
            when 'filename', 'blob'
              entry = FilenameBox.new(window)
            when 'base64'
              entry = Base64Entry.new
            when 'phash', 'panhash'
              if field[FI_Id]=='panhash'
                entry = HexEntry.new
                #entry.editable = false
              else
                entry = PanhashBox.new(atype)
              end
            else
              entry = ::Gtk::Entry.new
          end
          @def_widget ||= entry
          begin
            def_size = 10
            case atype
              when 'Integer'
                def_size = 10
              when 'String'
                def_size = 32
              when 'Filename' , 'Blob', 'Text'
                def_size = 256
            end
            #p '---'
            #p 'name='+field[FI_Name]
            #p 'atype='+atype.inspect
            #p 'def_size='+def_size.inspect
            fld_size = field[FI_FSize].to_i if field[FI_FSize]
            #p 'fld_size='+fld_size.inspect
            max_size = field[FI_Size].to_i
            max_size = fld_size if (max_size==0)
            #p 'max_size1='+max_size.inspect
            fld_size = def_size if (fld_size<=0)
            max_size = fld_size if (max_size<fld_size) and (max_size>0)
            #p 'max_size2='+max_size.inspect
          rescue
            #p 'FORM rescue [fld_size, max_size, def_size]='+[fld_size, max_size, def_size].inspect
            fld_size = def_size
          end
          #p 'Final [fld_size, max_size]='+[fld_size, max_size].inspect
          #entry.width_chars = fld_size
          entry.max_length = max_size if max_size>0
          color = field[FI_Color]
          if color
            color = Gdk::Color.parse(color)
          else
            color = nil
          end
          #entry.modify_fg(::Gtk::STATE_ACTIVE, color)
          entry.modify_text(::Gtk::STATE_NORMAL, color)

          ew = fld_size*@middle_char_width
          ew = form_width if ew > form_width
          entry.width_request = ew
          ew,eh = entry.size_request
          #p '[view, ew,eh]='+[aview, ew,eh].inspect
          field[FI_Widget] = entry
          field[FI_WidW] = ew
          field[FI_WidH] = eh
          entries_width += ew
          max_entry_height = eh if max_entry_height < eh
          text = field[FI_Value].to_s
          #if (atype=='Blob') or (atype=='Text')
          if (aview=='blob') or (aview=='text')
            entry.text = text[1..-1] if text and (text.size<1024) and (text[0]=='@')
          else
            entry.text = text
          end
        end

        field_matrix = Array.new
        mw, mh = 0, 0
        row = Array.new
        row_index = -1
        rw, rh = 0, 0
        orient = :up
        @fields.each_index do |index|
          field = @fields[index]
          if (index==0) or (field[FI_NewRow]==1)
            row_index += 1
            field_matrix << row if row != []
            mw, mh = [mw, rw].max, mh+rh
            row = []
            rw, rh = 0, 0
          end

          if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
          orient = field[FI_LabOr]

          field_size = calc_field_size(field)
          rw, rh = rw+field_size[0], [rh, field_size[1]+1].max
          row << field
        end
        field_matrix << row if row != []
        mw, mh = [mw, rw].max, mh+rh

        if (mw<=form_width) and (mh<=form_height) then
          window_width, window_height = mw+36, mh+@btn_panel_height+125
        end
        window.set_default_size(window_width, window_height)

        @window_width, @window_height = 0, 0
        @old_field_matrix = []
      end

      # Calculate field size
      # RU: Вычислить размер поля
      def calc_field_size(field)
        lw = field[FI_LabW]
        lh = field[FI_LabH]
        ew = field[FI_WidW]
        eh = field[FI_WidH]
        if (field[FI_LabOr]==:left) or (field[FI_LabOr]==:right)
          [lw+ew, [lh,eh].max]
        else
          field_size = [[lw,ew].max, lh+eh]
        end
      end

      # Calculate row size
      # RU: Вычислить размер ряда
      def calc_row_size(row)
        rw, rh = [0, 0]
        row.each do |fld|
          fs = calc_field_size(fld)
          rw, rh = rw+fs[0], [rh, fs[1]].max
        end
        [rw, rh]
      end

      # Event on resize window
      # RU: Событие при изменении размеров окна
      def on_resize_window(window, event)
        if (@window_width == event.width) and (@window_height == event.height)
          return
        end
        @window_width, @window_height = event.width, event.height

        form_width = @window_width-36
        form_height = @window_height-@btn_panel_height-55

        #p '---fill'

        # create and fill field matrix to merge in form
        step = 1
        found = false
        while not found do
          fields = Array.new
          @fields.each do |field|
            fields << field.dup
          end

          field_matrix = Array.new
          mw, mh = 0, 0
          case step
            when 1  #normal compose. change "left" to "up" when doesn't fit to width
              row = Array.new
              row_index = -1
              rw, rh = 0, 0
              orient = :up
              fields.each_with_index do |field, index|
                if (index==0) or (field[FI_NewRow]==1)
                  row_index += 1
                  field_matrix << row if row != []
                  mw, mh = [mw, rw].max, mh+rh
                  #p [mh, form_height]
                  if (mh>form_height)
                    #step = 2
                    step = 5
                    break
                  end
                  row = Array.new
                  rw, rh = 0, 0
                end

                if ! [:up, :down, :left, :right].include?(field[FI_LabOr]) then field[FI_LabOr]=orient; end
                orient = field[FI_LabOr]

                field_size = calc_field_size(field)
                rw, rh = rw+field_size[0], [rh, field_size[1]].max
                row << field

                if rw>form_width
                  col = row.size
                  while (col>0) and (rw>form_width)
                    col -= 1
                    fld = row[col]
                    if [:left, :right].include?(fld[FI_LabOr])
                      fld[FI_LabOr]=:up
                      rw, rh = calc_row_size(row)
                    end
                  end
                  if (rw>form_width)
                    #step = 3
                    step = 5
                    break
                  end
                end
              end
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              if (mh>form_height) or (mw>form_width)
                #step = 2
                step = 5
              end
              found = (step==1)
            when 2
              found = true
            when 3
              found = true
            when 5  #need to rebuild rows by width
              row = Array.new
              row_index = -1
              rw, rh = 0, 0
              orient = :up
              fields.each_with_index do |field, index|
                if ! [:up, :down, :left, :right].include?(field[FI_LabOr])
                  field[FI_LabOr] = orient
                end
                orient = field[FI_LabOr]
                field_size = calc_field_size(field)

                if (rw+field_size[0]>form_width)
                  row_index += 1
                  field_matrix << row if row != []
                  mw, mh = [mw, rw].max, mh+rh
                  #p [mh, form_height]
                  row = Array.new
                  rw, rh = 0, 0
                end

                row << field
                rw, rh = rw+field_size[0], [rh, field_size[1]].max

              end
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              found = true
            else
              found = true
          end
        end

        matrix_is_changed = @old_field_matrix.size != field_matrix.size
        if not matrix_is_changed
          field_matrix.each_index do |rindex|
            row = field_matrix[rindex]
            orow = @old_field_matrix[rindex]
            if row.size != orow.size
              matrix_is_changed = true
              break
            end
            row.each_index do |findex|
              field = row[findex]
              ofield = orow[findex]
              if (field[FI_LabOr] != ofield[FI_LabOr]) or (field[FI_LabW] != ofield[FI_LabW]) \
                or (field[FI_LabH] != ofield[FI_LabH]) \
                or (field[FI_WidW] != ofield[FI_WidW]) or (field[FI_WidH] != ofield[FI_WidH]) \
              then
                matrix_is_changed = true
                break
              end
            end
            if matrix_is_changed then break; end
          end
        end

        # compare matrix with previous
        if matrix_is_changed
          #p "----+++++redraw"
          @old_field_matrix = field_matrix

          @def_widget = focus if focus

          # delete sub-containers
          if @vbox.children.size>0
            @vbox.hide_all
            @vbox.child_visible = false
            @fields.each_index do |index|
              field = @fields[index]
              label = field[FI_Label]
              entry = field[FI_Widget]
              label.parent.remove(label)
              entry.parent.remove(entry)
            end
            @vbox.each do |child|
              child.destroy
            end
          end

          # show field matrix on form
          field_matrix.each do |row|
            row_hbox = ::Gtk::HBox.new
            row.each_index do |field_index|
              field = row[field_index]
              label = field[FI_Label]
              entry = field[FI_Widget]
              if (field[FI_LabOr]==nil) or (field[FI_LabOr]==:left)
                row_hbox.pack_start(label, false, false, 2)
                row_hbox.pack_start(entry, false, false, 2)
              elsif (field[FI_LabOr]==:right)
                row_hbox.pack_start(entry, false, false, 2)
                row_hbox.pack_start(label, false, false, 2)
              else
                field_vbox = ::Gtk::VBox.new
                if (field[FI_LabOr]==:down)
                  field_vbox.pack_start(entry, false, false, 2)
                  field_vbox.pack_start(label, false, false, 2)
                else
                  field_vbox.pack_start(label, false, false, 2)
                  field_vbox.pack_start(entry, false, false, 2)
                end
                row_hbox.pack_start(field_vbox, false, false, 2)
              end
            end
            @vbox.pack_start(row_hbox, false, false, 2)
          end
          @vbox.child_visible = true
          @vbox.show_all
          if @def_widget
            #focus = @def_widget
            @def_widget.grab_focus
          end
        end
      end
    end

  end
end
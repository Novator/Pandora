module Pandora
  module Gtk

    # Tab box for notebook with image and close button
    # RU: Бокс закладки для блокнота с картинкой и кнопкой
    class TabLabelBox < ::Gtk::HBox
      attr_accessor :label
      def initialize(image, title, child=nil, *args)
        super(*args)
        label_box = self
        label_box.pack_start(image, false, false, 0) if image
        @label = ::Gtk::Label.new(title)
        label_box.pack_start(label, false, false, 0)
        if child
          btn = ::Gtk::Button.new
          btn.relief = ::Gtk::RELIEF_NONE
          btn.focus_on_click = false
          style = btn.modifier_style
          style.xthickness = 0
          style.ythickness = 0
          btn.modify_style(style)
          wim,him = ::Gtk::IconSize.lookup(::Gtk::IconSize::MENU)
          btn.set_size_request(wim+2,him+2)
          btn.signal_connect('clicked') do |*args|
            yield if block_given?
            ind = $window.notebook.children.index(child)
            $window.notebook.remove_page(ind) if ind
            label_box.destroy if not label_box.destroyed?
            child.destroy if not child.destroyed?
          end
          close_image = ::Gtk::Image.new(::Gtk::Stock::CLOSE, ::Gtk::IconSize::MENU)
          btn.add(close_image)
          align = ::Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
          align.add(btn)
          label_box.pack_start(align, false, false, 0)
        end
        label_box.spacing = 3
        label_box.show_all
      end
    end

  end
end
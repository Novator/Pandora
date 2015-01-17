module Pandora
  module Gtk

    # Entry for coordinates
    # RU: Поле ввода координат
    class CoordBox < ::Gtk::HBox
      attr_accessor :latitude, :longitude
      CoordWidth = 120

      def initialize
        super
        @latitude   = CoordEntry.new
        latitude.tooltip_text = Pandora.t('Latitude')+': 60.716, 60 43\', 60.43\'00"N'+"\n["+latitude.mask+']'
        @longitude  = CoordEntry.new
        longitude.tooltip_text = Pandora.t('Longitude')+': -114.9, W114 54\' 0", 114.9W'+"\n["+longitude.mask+']'
        latitude.width_request = CoordWidth
        longitude.width_request = CoordWidth
        self.pack_start(latitude, false, false, 0)
        self.pack_start(longitude, false, false, 1)
      end

      def max_length=(maxlen)
        ml = maxlen / 2
        latitude.max_length = ml
        longitude.max_length = ml
      end

      def text=(text)
        i = nil
        begin
          i = text.to_i if (text.is_a? String) and (text.size>0)
        rescue
          i = nil
        end
        if i
          coord = Pandora::Utils.int_to_coord(i)
        else
          coord = ['', '']
        end
        latitude.text = coord[0].to_s
        longitude.text = coord[1].to_s
      end

      def text
        res = Pandora::Utils.coord_to_int(latitude.text, longitude.text).to_s
      end

      def width_request=(wr)
        w = (wr+10) / 2
        latitude.set_width_request(w)
        longitude.set_width_request(w)
      end

      def modify_text(*args)
        latitude.modify_text(*args)
        longitude.modify_text(*args)
      end

      def size_request
        size1 = latitude.size_request
        res = longitude.size_request
        res[0] = size1[0]+1+res[0]
        res
      end
    end

  end
end
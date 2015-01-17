module Pandora
  module Utils
    # Base Pandora's object
    # RU: Базовый объект Пандоры
    class BasePanobject
      include Pandora::Constants

      class << self
        include Pandora::Constants

        def initialize(*args)
          super(*args)
          @ider = 'BasePanobject'
          @name = 'Базовый объект Пандоры'
          #@lang = true
          @tables = Array.new
          @def_fields = Array.new
          @def_fields_expanded = false
          @panhash_pattern = nil
          #@panhash_ind = nil
          #@modified_ind = nil
        end
        def ider
          @ider
        end
        def ider=(x)
          @ider = x
        end
        def kind
          @kind
        end
        def kind=(x)
          @kind = x
        end
        def sort
          @sort
        end
        def sort=(x)
          @sort = x
        end
        #def panhash_ind
        #  @panhash_ind
        #end
        #def modified_ind
        #  @modified_ind
        #end
        #def lang
        #  @lang
        #end
        #def lang=(x)
        #  @lang = x
        #end

        def def_fields
          @def_fields
        end

        def get_parent
          res = superclass
          res = nil if res == Object
          res
        end

        def field_des(fld_name)
          df = def_fields.detect{ |e| (e.is_a? Array) and (e[FI_Id].to_s == fld_name) or (e.to_s == fld_name) }
        end

        # The title of field in current language
        # "fd" must be field id or field description
        def field_title(fd)
          res = nil
          if fd.is_a? String
            res = fd
            fd = field_des(fd)
          end
          lang_exist = false
          if fd.is_a? Array
            res = fd[FI_LName]
            lang_exist = (res and (res != ''))
            res ||= fd[FI_Name]
            res ||= fd[FI_Id]
          end
          res = _(res) if not lang_exist
          res ||= ''
          res
        end

        # Set field description from parent, if own is empty
        # RU: Установить описание поля из родителя, если своё пустое
        def set_if_nil(f, fi, pfd)
          f[fi] ||= pfd[fi]
        end

        # Recognize label position near input widget
        # RU: Разгадывает позицию метки по отношению к полю ввода
        def decode_pos(pos=nil)
          pos ||= ''
          pos = pos.to_s
          new_row = 1 if pos.include?('|')
          ind = pos.scan(/[0-9\.\+]+/)
          ind = ind[0] if ind
          lab_or = pos.scan(/[a-z]+/)
          lab_or = lab_or[0] if lab_or
          lab_or = lab_or[0, 1] if lab_or
          if (not lab_or) or (lab_or=='u')
            lab_or = :up
          elsif (lab_or=='l')
            lab_or = :left
          elsif (lab_or=='d') or (lab_or=='b')
            lab_or = :down
          elsif (lab_or=='r')
            lab_or = :right
          else
            lab_or = :up
          end
          [ind, lab_or, new_row]
        end

        # Define view method and size of widget for field
        # RU: Определяет способ отображения и размер ввода для поля
        def set_view_and_len(fd)
          view = nil
          len = nil
          if (fd.is_a? Array) and fd[FI_Type]
            type = fd[FI_Type].to_s
            case type
              when 'Date'
                view = 'date'
                len = 10
              when 'Time'
                view = 'time'
                len = 19
              when 'Byte'
                view = 'byte'
                len = 3
              when 'Word'
                view = 'word'
                len = 5
              when 'Integer'
                view = 'integer'
                len = 14
              when 'Coord'
                view = 'coord'
                len = 24
              when 'Blob'
                if (not fd[FI_Size]) or (fd[FI_Size].to_i>25)
                  view = 'base64'
                else
                  view = 'hex'
                end
                #view = 'blob'
                #len = 80
              when 'Text'
                view = 'text'
                #len = 80
              when 'Filename'
                view = 'filename'
                len = 80
              when 'Panhash'
                view = 'panhash'
                len = 44
              when 'PHash', 'Phash'
                view = 'phash'
                len = 44
              when 'Real', 'Float', 'Double'
                view = 'real'
                len = 12
              else
                if type[0,7]=='Panhash'
                  view = 'phash'
                  len = 44
                end
            end
          end
          fd[FI_View] = view if view and (not fd[FI_View]) or (fd[FI_View]=='')
          fd[FI_FSize] = len if len and (not fd[FI_FSize]) or (fd[FI_FSize]=='')
          #p 'name,type,fsize,view,len='+[fd[FI_Name], fd[FI_Type], fd[FI_FSize], view, len].inspect
          [view, len]
        end

        # Get filed definition from sql table
        # RU: Берет описание полей из sql-таблицы
        def tab_fields(reinit=false)
          if (not @last_tab_fields) or reinit
            @last_tab_fields = repositories.get_tab_fields(self, tables[0])
            @last_tab_fields.each do |x|
              x[TI_Desc] = field_des(x[TI_Name])
            end
          end
          @last_tab_fields
        end

        # Expand field definitions taking non-defined values from parent
        # RU: Расширяет описание полей, беря недостающие значения от родителя
        def expand_def_fields_to_parent(reinit=false)
          if (not @def_fields_expanded) or reinit
            @def_fields_expanded = true
            # get undefined parameters from parent
            parent = get_parent
            if parent
              parent.expand_def_fields_to_parent
              if parent.def_fields.is_a? Array
                @def_fields.each do |f|
                  if f.is_a? Array
                    pfd = parent.field_des(f[FI_Id])
                    if pfd.is_a? Array
                      set_if_nil(f, FI_LName, pfd)
                      set_if_nil(f, FI_Pos, pfd)
                      set_if_nil(f, FI_FSize, pfd)
                      set_if_nil(f, FI_Hash, pfd)
                      set_if_nil(f, FI_View, pfd)
                    end
                  end
                end
              end
            end
            # calc indexes and form sizes, and sort def_fields
            df = def_fields
            if df.is_a? Array
              i = 0
              last_ind = 0.0
              df.each do |field|
                #p '===[field[FI_VFName], field[FI_View]]='+[field[FI_VFName], field[FI_View]].inspect
                set_view_and_len(field)
                fldsize = 0
                if field[FI_Size]
                  fldsize = field[FI_Size].to_i
                end
                fldvsize = fldsize
                if (not field[FI_FSize] or (field[FI_FSize].to_i==0)) and (fldsize>0)
                  field[FI_FSize] = fldsize
                  field[FI_FSize] = (fldsize*0.67).round if fldvsize>25
                end
                fldvsize = field[FI_FSize].to_i if field[FI_FSize]
                if (fldvsize <= 0) or ((fldvsize > fldsize) and (fldsize>0))
                  fldvsize = (fldsize*0.67).round if (fldsize>0) and (fldvsize>30)
                  fldvsize = 120 if fldvsize>120
                end
                indd, lab_or, new_row = decode_pos(field[FI_Pos])
                plus = (indd and (indd[0, 1]=='+'))
                indd = indd[1..-1] if plus
                if indd and (indd.size>0)
                  indd = indd.to_f
                else
                  indd = nil
                end
                ind = 0.0
                if not indd
                  last_ind += 1.0
                  ind = last_ind
                else
                  if plus
                    last_ind += indd
                    ind = last_ind
                  else
                    ind = indd
                    last_ind += indd if indd < 200  # matter fileds have index lower then 200
                  end
                end
                field[FI_Size] = fldsize
                field[FI_VFName] = field_title(field)
                field[FI_Index] = ind
                field[FI_LabOr] = lab_or
                field[FI_NewRow] = new_row
                field[FI_VFSize] = fldvsize
                #p '[field[FI_VFName], field[FI_View]]='+[field[FI_VFName], field[FI_View]].inspect
              end
              df.sort! {|a,b| a[FI_Index]<=>b[FI_Index] }
            end
            #i = tab_fields.index{ |tf| tf[0]=='panhash'}
            #@panhash_ind = i if i
            #i = tab_fields.index{ |tf| tf[0]=='modified'}
            #@modified_ind = i if i
            @def_fields = df
          end
        end

        # Formula for panhash component by filed type
        # RU: Формула для компонента панхэша по типу поля
        def def_hash(fd)
          len = 0
          hash = ''
          if (fd.is_a? Array) and fd[FI_Type]
            type = fd[FI_Type].to_s
            case type
              when 'Integer', 'Time'
                hash = 'integer'
                len = 4
              when 'Coord'
                hash = 'coord'
                len = 4
              when 'Byte'
                hash = 'byte'
                len = 1
              when 'Word'
                hash = 'word'
                len = 2
              when 'Date'
                hash = 'date'
                len = 3
              when 'Panhash', 'Phash'
                hash = 'phash'
                len = 10
              else
                if type[0,7]=='Panhash'
                  hash = 'phash'
                  len = 10
                else
                  hash = 'hash'
                  len = fd[FI_Size]
                  len = 4 if (not len.is_a? Integer) or (len>4)
                end
            end
          end
          [len, hash]
        end

        # Pattern for calculating panhash
        # RU: Шаблон для вычиисления панхэша
        def panhash_pattern(auto_calc=true)
          res = []
          last_ind = 0
          def_flds = def_fields
          if def_flds
            def_flds.each do |e|
              if (e.is_a? Array) and e[FI_Hash] and (e[FI_Hash].to_s != '')
                hash = e[FI_Hash]
                #p 'hash='+hash.inspect
                ind = 0
                len = 0
                i = hash.index(':')
                if i
                  ind = hash[0, i].to_i
                  hash = hash[i+1..-1]
                end
                i = hash.index('(')
                if i
                  len = hash[i+1..-1]
                  len = len[0..-2] if len[-1]==')'
                  len = len.to_i
                  hash = hash[0, i]
                end
                #p '@@@[ind, hash, len]='+[ind, hash, len].inspect
                if (not hash) or (hash=='') or (len<=0)
                  dlen, dhash = def_hash(e)
                  #p '[hash, len, dhash, dlen]='+[hash, len, dhash, dlen].inspect
                  hash = dhash if (not hash) or (hash=='')
                  if len<=0
                    case hash
                      when 'byte', 'lang'
                        len = 1
                      when 'date'
                        len = 3
                      when 'crc16', 'word'
                        len = 2
                      when 'crc32', 'integer', 'time', 'real', 'coord'
                        len = 4
                    end
                  end
                  len = dlen if len<=0
                  #p '=[hash, len]='+[hash, len].inspect
                end
                ind = last_ind + 1 if ind==0
                res << [ind, e[FI_Id], hash, len]
                last_ind = ind
              end
            end
          end
          #p 'res='+res.inspect
          if res==[]
            parent = get_parent
            if parent
              res = parent.panhash_pattern(false)
            end
          else
            res.sort! { |a,b| a[0]<=>b[0] }  # sort formula by index
            res.collect! { |e| [e[1],e[2],e[3]] }  # delete sort index (id, hash, len)
          end
          if auto_calc
            if ((not res) or (res == [])) and (def_flds.is_a? Array)
              # panhash formula is not defined
              res = []
              used_len = 0
              nil_count = 0
              last_nil = 0
              max_i = def_flds.count
              i = 0
              while (i<max_i) and (used_len<$max_hash_len)
                e = def_flds[i]
                if e[FI_Id] != 'panhash'
                  len, hash = def_hash(e)
                  res << [e[FI_Id], hash, len]
                  if len>0
                    used_len += len
                  else
                    nil_count += 1
                    last_nil = res.size-1
                  end
                end
                i += 1
              end
              if used_len<$max_hash_len
                mid_len = 0
                mid_len = ($max_hash_len-used_len)/nil_count if nil_count>0
                if mid_len>0
                  tail = 20
                  res.each_with_index do |e,i|
                    if (e[2]<=0)
                      if (i==last_nil)
                        e[2]=tail
                       used_len += tail
                      else
                        e[2]=mid_len
                        used_len += mid_len
                      end
                    end
                    tail -= e[2]
                  end
                end
              end
              res.delete_if {|e| (not e[2].is_a? Integer) or (e[2]==0) }
              i = res.count-1
              while (i>0) and (used_len > $max_hash_len)
                used_len -= res[i][2]
                i -= 1
              end
              res = res[0, i+1]
            end
          end
          #p 'pan_pattern='+res.inspect
          res
        end

        def def_fields=(x)
          @def_fields = x
        end

        def tables
          @tables
        end

        def tables=(x)
          @tables = x
        end

        def name
          @name
        end

        def name=(x)
          @name = x
        end

        def repositories
          $repositories
        end
      end

      def initialize(*args)
        super(*args)
        self.class.expand_def_fields_to_parent
      end

      def ider
        self.class.ider
      end

      def ider=(x)
        self.class.ider = x
      end

      def kind
        self.class.kind
      end

      def kind=(x)
        self.class.kind = x
      end

      def sort
        self.class.sort
      end

      def sort=(x)
        self.class.sort = x
      end
      #def lang
      #  self.class.lang
      #end
      #def lang=(x)
      #  self.class.lang = x
      #end

      def def_fields
        self.class.def_fields
      end

      def def_fields=(x)
        self.class.def_fields = x
      end

      def tables
        self.class.tables
      end

      def tables=(x)
        self.class.tables = x
      end

      def name
        self.class.name
      end

      def name=(x)
        self.class.name = x
      end

      def repositories
        $repositories
      end

      def sname
        _(Pandora::Utils.get_name_or_names(name))
      end

      def pname
        _(Pandora::Utils.get_name_or_names(name, true))
      end

      attr_accessor :namesvalues

      def tab_fields
        self.class.tab_fields
      end

      # RU: Делает выборку из таблицы
      def select(afilter=nil, set_namesvalues=false, fields=nil, sort=nil, limit=nil, like_ex=nil)
        res = self.class.repositories.get_tab_select(self, self.class.tables[0], \
          afilter, fields, sort, limit, like_ex)
        if set_namesvalues and res[0].is_a? Array
          @namesvalues = {}
          tab_fields.each_with_index do |td, i|
            namesvalues[td[TI_Name]] = res[0][i]
          end
        end
        res
      end

      # RU: Записывает данные в таблицу
      def update(values, names=nil, filter='', set_namesvalues=false)
        if values.is_a? Hash
          names = values.keys
          values = values.values
          #p 'update names='+names.inspect
          #p 'update values='+values.inspect
        end
        res = self.class.repositories.get_tab_update(self, self.class.tables[0], values, names, filter)
        if set_namesvalues and res
          @namesvalues = {}
          values.each_with_index do |v, i|
            namesvalues[names[i]] = v
          end
        end
        res
      end

      # Choose a value by field name
      # RU: Выбирает значение по имени поля
      def field_val(fld_name, values)
        res = nil
        if values.is_a? Array
          i = tab_fields.index{ |tf| tf[0]==fld_name}
          res = values[i] if i
        end
        res
      end

      def field_des(fld_name)
        self.class.field_des(fld_name)
      end

      def field_title(fd)
        self.class.field_title(fd)
      end

      def panhash_pattern
        if not @panhash_pattern
          @panhash_pattern = self.class.panhash_pattern
        end
        @panhash_pattern
      end

      # Panhash formula for show
      # RU: Формула панхэша для показа
      def panhash_formula
        res = ''
        pp = panhash_pattern
        if pp.is_a? Array
          #ppn = pp.collect{|p| field_title(p[0]).gsub(' ', '.') }
          flddes = def_fields
          # ids and names on current language for all fields
          fldtits = flddes.collect do |fd|
            id = fd[FI_Id]
            tit = field_title(fd)    #.gsub(' ', '.')
            [id, tit]
          end
          #p '[fldtits,pp]='+[fldtits,pp].inspect
          # to receive restricted names
          ppr = []
          pp.each_with_index do |p,i|
            n = nil
            j = fldtits.index {|ft| ft[0]==p[0]}
            n = fldtits[j][1] if j
            if n.is_a? String
              s = 1
              found = false
              while (s<8) and (s<n.size) and not found
                nr = n[0,s]
                equaled = fldtits.select { |ft| ft[1][0,s]==nr  }
                found = equaled.count<=1
                s += 1
              end
              nr = n[0, 8] if not found
              ppr[i] = nr
            else
              ppr[i] = n.to_s
            end
          end
          # compose panhash mask
          siz = 2
          pp.each_with_index do |hp,i|
            res << '/' if res != ''
            res << ppr[i]+':'+hp[2].to_s
            siz += hp[2].to_i
          end
          kn = ider.downcase
          res = 'pandora:' + kn + '/' + res + ' =' + siz.to_s
        end
        res
      end

      # Calculate panhash component
      # RU: Рассчитывает компоненту панхэша
      def calc_hash(hfor, hlen, fval)
        res = nil
        #fval = [fval].pack('C*') if fval.is_a? Fixnum
        #p 'fval='+fval.inspect+'  hfor='+hfor.inspect
        if fval and ((not (fval.is_a? String)) or (fval.bytesize>0))
          #p 'fval='+fval.inspect+'  hfor='+hfor.inspect
          hfor = 'integer' if (not hfor or hfor=='') and (fval.is_a? Integer)
          hfor = 'hash' if ((hfor=='') or (hfor=='text')) and (fval.is_a? String) and (fval.size>20)
          if ['integer', 'word', 'byte', 'lang', 'coord'].include? hfor
            if hfor == 'coord'
              if fval.is_a? String
                fval = Pandora::Utils.bytes_to_bigint(fval[2,4])
              end
              res = fval.to_i
              coord = Pandora::Utils.int_to_coord(res)
              coord[0] = Pandora::Utils.simplify_coord(coord[0])
              coord[1] = Pandora::Utils.simplify_coord(coord[1])
              fval = Pandora::Utils.coord_to_int(*coord)
              fval ||= res
              fval = 1 if (fval.is_a? Integer) and (fval==0)
            elsif not (fval.is_a? Integer)
              fval = fval.to_i
            end
            res = fval
          elsif hfor == 'date'
            res = 0
            if fval.is_a? Integer
              res = Time.at(fval)
            else
              res = Time.parse(fval)
            end
            res = res.to_i / (24*60*60)   #obtain days, drop hours and seconds
            res += (1970-1900)*365   #mesure data from 1900
          else
            if fval.is_a? Integer
              fval = Pandora::Utils.bigint_to_bytes(fval)
            elsif fval.is_a? Float
              fval = fval.to_s
            end
            case hfor
              when 'sha1', 'hash'
                res = AsciiString.new
                res << Digest::SHA1.digest(fval)
              when 'sha256'
                res = AsciiString.new
                res << OpenSSL::Digest::SHA256.digest(fval)
              when 'phash'
                res = fval[2..-1]
              when 'pbirth'
                res = fval[9, 3]
              when 'md5'
                res = AsciiString.new
                res << Digest::MD5.digest(fval)
              when 'crc16'
                res = Zlib.crc32(fval) #if fval.is_a? String
                res = (res & 0xFFFF) ^ (res >> 16)
              when 'crc32'
                res = Zlib.crc32(fval) #if fval.is_a? String
              when 'raw'
                res = AsciiString.new(fval)
              when 'sha224'
                res = AsciiString.new
                res << OpenSSL::Digest::SHA224.digest(fval)
              when 'sha384'
                res = AsciiString.new
                res << OpenSSL::Digest::SHA384.digest(fval)
              when 'sha512'
                res = AsciiString.new
                res << OpenSSL::Digest::SHA512.digest(fval)
            end
          end
          if not res
            if fval.is_a? String
              res = AsciiString.new(fval)
            else
              res = fval
            end
          end
          if res.is_a? Integer
            res = AsciiString.new(Pandora::Utils.bigint_to_bytes(res))
            res = Pandora::Utils.fill_zeros_from_left(res, hlen)
          elsif not fval.is_a? String
            res = AsciiString.new(res.to_s)
          end
          res = AsciiString.new(res[0, hlen])
        end
        if not res
          res = AsciiString.new
          res << [0].pack('C')
        end
        while res.size<hlen
          res << [0].pack('C')
        end
        res = AsciiString.new(res)
      end

      # Panhash for show
      # RU: Панхэш для показа
      def show_panhash(val, prefix=true)
        res = ''
        if prefix
          res = Pandora::Utils.bytes_to_hex(val[0,2])+' '
          val = val[2..-1]
        end
        res2 = Pandora::Utils.bytes_to_hex(val)
        i = 0
        panhash_pattern.each do |pp|
          if (i>0) and (i<res2.size)
            res2 = res2[0, i] + ' ' + res2[i..-1]
            i += 1
          end
          i += pp[2] * 2
        end
        res << res2
      end

      # Calculate panhash
      # RU: Рассчитывает панхэш
      def panhash(values, lang=0, prefix=true, hexview=false)
        res = AsciiString.new
        if prefix
          res << [kind,lang].pack('CC')
        end
        if values.is_a? Hash
          values0 = values
          values = {}
          values0.each {|k,v| values[k.to_s] = v}  # sym key to string key
        end
        pattern = panhash_pattern
        pattern.each_with_index do |pat, ind|
          fname = pat[0]
          fval = nil
          if values.is_a? Hash
            fval = values[fname]
          else
            fval = field_val(fname, values)
          end
          hfor  = pat[1]
          hlen  = pat[2]
          #p '[fval, fname, values]='+[fval, fname, values].inspect
          #p '[hfor, hlen, fval]='+[hfor, hlen, fval].inspect
          #res.force_encoding('ASCII-8BIT')
          res << AsciiString.new(calc_hash(hfor, hlen, fval))
        end
        res = AsciiString.new(res)
        res = show_panhash(res, prefix) if hexview
        res
      end

      # Matter fields (including to panhash)
      # RU: Сущностные поля (входящие в панхэш)
      def matter_fields(pack_empty=true)
        res = {}
        if namesvalues.is_a? Hash
          panhash_pattern.each do |pat|
            fname = pat[0]
            if fname
              fval = namesvalues[fname]
              if (pack_empty or (not Pandora::Utils.value_is_empty?(fval)))
                res[fname] = fval
              end
            end
          end
        end
        res
      end

      # Clear excess fields
      # RU: Удалить избыточные поля
      def clear_excess_fields(row)
        #row.delete_at(0)
        #row.delete_at(self.class.panhash_ind) if self.class.panhash_ind
        #row.delete_at(self.class.modified_ind) if self.class.modified_ind
        #row
        res = {}
        if namesvalues.is_a? Hash
          namesvalues.each do |k, v|
            if not (['id', 'panhash', 'modified', 'panstate'].include? k)
              res[k] = v
            end
          end
        end
        res
      end

    end
  end
end
require_relative 'utils/base_panobject'
require_relative 'utils/database_session'
require_relative 'utils/round_queue'
require_relative 'utils/sqlite_db_session'
require_relative 'utils/repository_manager'

module Pandora
  # ====================================================================
  # Utilites class of Pandora
  # RU: Вспомогательный класс Пандоры
  module Utils

    # Platform detection
    # RU: Определение платформы
    def self.os_family
      case RUBY_PLATFORM
        when /ix/i, /ux/i, /gnu/i, /sysv/i, /solaris/i, /sunos/i, /bsd/i
          'unix'
        when /win/i, /ming/i
          'windows'
        else
          'other'
      end
    end

    # Load translated phrases
    # RU: Загрузить переводы фраз
    def self.load_language(lang='ru')

      def self.unslash_quotes(str)
        str ||= ''
        str.gsub('\"', '"')
      end

      def self.addline(str, line)
        line = unslash_quotes(line)
        if (not str) or (str=='')
          str = line
        else
          str = str.to_s + "\n" + line.to_s
        end
        str
      end

      def self.spaces_after?(line, pos)
        i = line.size-1
        while (i>=pos) and ((line[i, 1]==' ') or (line[i, 1]=="\t"))
          i -= 1
        end
        (i<pos)
      end

      $lang_trans = {}
      langfile = File.join(Pandora.lang_dir, lang +'.txt')
      if File.exist?(langfile)
        scanmode = 0
        frase = ''
        trans = ''
        IO.foreach(langfile) do |line|
          if (line.is_a? String) and (line.size>0)
            #line = line[0..-2] if line[-1,1]=="\n"
            #line = line[0..-2] if line[-1,1]=="\r"
            line.chomp!
            end_is_found = false
            if scanmode==0
              end_is_found = true
              if (line.size>0) and (line[0, 1] != '#')
                if line[0, 1] != '"'
                  frase, trans = line.split('=>')
                  $lang_trans[frase] = trans if (frase != '') and (trans != '')
                else
                  line = line[1..-1]
                  frase = ''
                  trans = ''
                  end_is_found = false
                end
              end
            end

            if not end_is_found
              if scanmode<2
                i = line.index('"=>"')
                if i
                  frase = addline(frase, line[0, i])
                  line = line[i+4, line.size-i-4]
                  scanmode = 2 #composing a trans
                else
                  scanmode = 1 #composing a frase
                end
              end
              if scanmode==2
                k = line.rindex('"')
                if k and ((k==0) or (line[k-1, 1] != "\\"))
                  end_is_found = ((k+1)==line.size) or spaces_after?(line, k+1)
                  if end_is_found
                    trans = addline(trans, line[0, k])
                  end
                end
              end

              if end_is_found
                $lang_trans[frase] = trans if (frase != '') and (trans != '')
                scanmode = 0
              else
                if scanmode < 2
                  frase = addline(frase, line)
                  scanmode = 1 #composing a frase
                else
                  trans = addline(trans, line)
                end
              end
            end
          end
        end
      end
    end

    # Save language phrases
    # RU: Сохранить языковые фразы
    def self.save_as_language(lang='ru')

      # RU: Экранирует кавычки слэшем
      def self.slash_quotes(str)
        str.gsub('"', '\"')
      end

      # RU: Есть конечный пробел или табуляция?
      def self.there_are_end_space?(str)
        lastchar = str[str.size-1, 1]
        (lastchar==' ') or (lastchar=="\t")
      end

      # langfile = File.join(Pandora.lang_dir, lang+'.txt')
      File.open(langfile, 'w') do |file|
        file.puts('# Pandora language file EN=>'+lang.upcase)
        $lang_trans.each do |value|
          if (not value[0].index('"')) and (not value[1].index('"')) \
            and (not value[0].index("\n")) and (not value[1].index("\n")) \
            and (not there_are_end_space?(value[0])) and (not there_are_end_space?(value[1]))
          then
            str = value[0]+'=>'+value[1]
          else
            str = '"'+slash_quotes(value[0])+'"=>"'+slash_quotes(value[1])+'"'
          end
          file.puts(str)
        end
      end
    end

    # Plural or single name
    # RU: Имя во множественном или единственном числе
    def self.get_name_or_names(mes, plural=false, lang=nil)
      sname, pname = mes.split('|')
      if plural==false
        res = sname
      elsif ((not pname) or (pname=='')) and sname
        lang ||= Pandora.config.lang
        case lang
          when 'ru'
            res = sname
            if ['ка', 'га', 'ча'].include? res[-2,2]
              res[-1] = 'и'
            elsif ['г', 'к'].include? res[-1]
              res += 'и'
            elsif ['о'].include? res[-1]
              res[-1] = 'а'
            elsif ['а'].include? res[-1]
              res[-1] = 'ы'
            elsif ['ь', 'я'].include? res[-1]
              res[-1] = 'и'
            elsif ['е'].include? res[-1]
              res[-1] = 'я'
            else
              res += 'ы'
            end
          else
            res = sname
            res[-1]='ie' if res[-1,1]=='y'
            res += 's'
        end
      else
        res = pname
      end
      res
    end


    $rubyzip = nil  # Flag of using Zip library

    # Unzip archive via Zip library
    # RU: Распаковывает архив с помощью библиотеки Zip
    def self.unzip_via_lib(arch, path, overwrite=true)
      res = nil
      if not $rubyzip
        begin
          require 'rubygems'
          require 'zip/zip'
          $rubyzip = true
        rescue Exception
        end
      end
      if $rubyzip
        Zip::ZipFile.open(arch) do |za|
          unix = (Pandora::Utils.os_family != 'windows')
          perms = nil
          za.each do |zf|
            if unix
              perms = zf.unix_perms
              if (perms == 0755) or (perms == 0775) or (perms == 0777)
                perms = 0777
              else
                perms = 0666
              end
            end
            fullname = File.join(path, zf.name)
            dir = File.dirname(fullname)
            if not Dir.exists?(dir)
              FileUtils.mkdir_p(dir)
              File.chmod(0777, dir) if unix
            end
            if (not zf.directory?) and (overwrite or (not File.exist?(fullname)))
              File.open(fullname, 'wb') do |f|
                f << zf.get_input_stream.read
                f.chmod(perms) if perms
              end
            end
          end
          res = true
        end
      end
      res
    end

    $unziper = nil  # Zip utility

    # Unzip archive via Zip utility
    # RU: Распаковывает архив с помощью Zip утилиты
    def self.unzip_via_util(arch, path, overwrite=true)
      res = nil
      if File.exist?(arch) and Dir.exists?(path)
        if not $unziper
          if Pandora::Utils.os_family=='windows'
            # unzip = File.join(Pandora.util_dir, 'unzip.exe')
            if File.exist?(unzip)
              $unziper = '"'+unzip+'"'
            end
          else
            unzip = `which unzip`
            if (unzip.is_a? String) and (unzip.size>2)
              $unziper = '"'+unzip.chomp+'"'
            end
          end
        end
        if $unziper
          mode = 'o'
          mode = 'n' unless overwrite
          cmd = $unziper+' -'+mode+' "'+arch+'" -d "'+path+'"'
          if Pandora::Utils.os_family=='windows'
            #res = false
            #p 'pid = spawn(cmd)'
            #p pid = spawn(cmd)
            #if pid
            #  pid, status = Process.wait2(pid)
            #  p 'status='+status.inspect
            #  p 'status.exitstatus='+status.exitstatus.inspect
            #  res = (status and (status.exitstatus==0))
            #end
            res = win_exec(cmd, 40)
            #res = exec(cmd)
            #res = system(cmd)
            p 'unzip: win_exec res='+res.inspect
          else
            res = system(cmd)
            p 'unzip: system res='+res.inspect
          end
        end
      end
      res
    end

    # Panhash is nil?
    # RU: Панхэш не нулевой?
    def self.panhash_nil?(panhash)
      res = true
      if panhash.is_a? String
        i = 2
        while res and (i<panhash.size)
          res = (panhash[i] == 0.chr)
          i += 1
        end
      elsif panhash.is_a? Integer
        res = (panhash == 0)
      end
      res
    end

    # Kind from panhash
    # RU: Тип записи по панхэшу
    def self.kind_from_panhash(panhash)
      kind = panhash[0].ord if (panhash.is_a? String) and (panhash.bytesize>0)
    end

    # Language from panhash
    # RU: Язык объекта по панхэшу
    def self.lang_from_panhash(panhash)
      lang = panhash[1].ord if (panhash.is_a? String) and (panhash.bytesize>1)
    end

    # Convert string of bytes to hex string
    # RU: Преобрзует строку байт в 16-й формат
    def self.bytes_to_hex(bytes)
      res = AsciiString.new
      #res.force_encoding('ASCII-8BIT')
      if bytes
        bytes.each_byte do |b|
          res << ('%02x' % b)
        end
      end
      res
    end

    def self.hex_to_bytes(hexstr)
      bytes = AsciiString.new
      hexstr = '0'+hexstr if hexstr.size % 2 > 0
      ((hexstr.size+1)/2).times do |i|
        bytes << hexstr[i*2,2].to_i(16).chr
      end
      AsciiString.new(bytes)
    end

    # Convert big integer to string of bytes
    # RU: Преобрзует большое целое в строку байт
    def self.bigint_to_bytes(bigint)
      bytes = AsciiString.new
      if (bigint>=0) and (bigint<=0xFF)
        bytes << [bigint].pack('C')
      else
        hexstr = bigint.to_s(16)
        hexstr = '0'+hexstr if (hexstr.size % 2) > 0
        ((hexstr.size+1)/2).times do |i|
          bytes << hexstr[i*2,2].to_i(16).chr
        end
      end
      AsciiString.new(bytes)
    end

    # Convert string of bytes to big integer
    # RU: Преобразует строку байт в большое целое
    def self.bytes_to_bigint(bytes)
      res = nil
      if bytes
        hexstr = bytes_to_hex(bytes)
        res = OpenSSL::BN.new(hexstr, 16)
      end
      res
    end

    # Convert string of bytes to integer
    # RU: Преобрзует строку байт в целое
    def self.bytes_to_int(bytes)
      res = 0
      i = bytes.size
      bytes.each_byte do |b|
        i -= 1
        res += (b << 8*i)
      end
      res
    end

    # Convert string to bytes
    # RU: Преобрзует строку в строку байт
    def self.str_to_bytes(str)
      if str.is_a? String
        res = []
        str.each_byte do |b|
          res << b
        end
        str = res
      end
      str
    end

    # Convert ruby date to string
    # RU: Преобрзует ruby-дату в строку
    def self.date_to_str(date)
      res = date.strftime('%d.%m.%Y')
    end

    # Obtain date value from string
    # RU: Извлекает дату из строки
    def self.str_to_date(str)
      res = nil
      begin
        res = Time.parse(str)  #Time.strptime(defval, '%d.%m.%Y')
      rescue Exception
        res = nil
      end
      res
    end

    # Fill string by zeros from left to defined size
    # RU: Заполнить строку нулями слева до нужного размера
    def self.fill_zeros_from_left(data, size)
      #data.force_encoding('ASCII-8BIT')
      data = AsciiString.new(data)
      if data.size<size
        data = [0].pack('C')*(size-data.size) + data
      end
      #data.ljust(size, 0.chr)
      data = AsciiString.new(data)
    end

    # Rewrite string with zeros
    # RU: Перебивает строку нулями
    def self.fill_by_zeros(str)
      if str.is_a? String
        (str.size).times do |i|
          str[i] = 0.chr
        end
      end
    end

    # Codes of data types in PSON
    # RU: Коды типов данных в PSON
    PT_Int   = 0
    PT_Str   = 1
    PT_Bool  = 2
    PT_Time  = 3
    PT_Array = 4
    PT_Hash  = 5
    PT_Sym   = 6
    PT_Real  = 7
    # 8..14 - reserved for other types
    PT_Unknown = 15
    PT_Negative = 16

    # Convert string notation type to code of type
    # RU: Преобразует строковое представление типа в код типа
    def self.string_to_pantype(type)
      res = PT_Unknown
      case type
        when 'Integer', 'Word', 'Byte', 'Coord'
          res = PT_Int
        when 'String', 'Text', 'Blob', 'Filename'
          res = PT_Str
        when 'Boolean'
          res = PT_Bool
        when 'Time', 'Date'
          res = PT_Time
        when 'Array'
          res = PT_Array
        when 'Hash'
          res = PT_Hash
        when 'Symbol'
          res = PT_Sym
        when 'Real', 'Float', 'Double'
          res = PT_Real
      end
      res
    end

    # Get view method by code of type
    # RU: Возвращает метод отображения по коду типа
    def self.pantype_to_view(type)
      res = nil
      case type
        when PT_Int
          res = 'integer'
        when PT_Bool
          res = 'boolean'
        when PT_Time
          res = 'time'
        when PT_Real
          res = 'real'
      end
      res
    end

    # Any value to boolean
    # RU: Любое значение в логическое
    def self.any_value_to_boolean(val)
      val = (((val.is_a? String) and (val.downcase != 'false') and (val.downcase != 'no') and (val != '0')) \
        or ((val.is_a? Numeric) and (val != 0)))
      val
    end

    # Round time to midnight
    # RU: Округлить время к полуночи
    def self.calc_midnight(time)
      res = nil
      if time
        time = Time.at(time) if (time.is_a? Integer)
        vals = time.to_a
        y, m, d = [vals[5], vals[4], vals[3]]
        res = Time.local(y, m, d)
      end
      res
    end

    # Time to human view
    # RU: Время в человеческий вид
    def self.time_to_str(val, time_now=nil)
      time_now ||= Time.now
      min_ago = (time_now.to_i - val.to_i) / 60
      if min_ago < 0
        val = val.strftime('%d.%m.%Y')
      elsif min_ago == 0
        val = _('just now')
      elsif min_ago == 1
        val = _('a min. ago')
      else
        midnight = calc_midnight(time_now)
        if (min_ago <= 90) and ((val >= midnight) or (min_ago <= 10))
          val = min_ago.to_s + ' ' + _('min. ago')
        elsif val >= midnight
          val = _('today')+' '+val.strftime('%R')
        elsif val.to_i >= (midnight.to_i-24*3600)  #last midnight
          val = _('yester')+' '+val.strftime('%R')
        else
          val = val.strftime('%d.%m.%y %R')
        end
      end
      val
    end

    # Convert time to string for dialog
    # RU: Преобразует время в строку для диалога
    def self.time_to_dialog_str(time, time_now)
      time_fmt = '%H:%M:%S'
      time_fmt = '%d.%m.%Y '+time_fmt if ((time_now.to_i - time.to_i).abs > 12*3600)
      time = Time.at(time) if (time.is_a? Integer)
      time_str = time.strftime(time_fmt)
    end

    # Raw value to view string
    # RU: Сырое значение в строку для отображения
    def self.val_to_view(val, type, view, can_edit=true)
      color = nil
      if val and view
        if view=='date'
          if val.is_a? Integer
            val = Time.at(val)
            if can_edit
              val = val.strftime('%d.%m.%Y')
            else
              val = val.strftime('%d.%m.%y')
            end
            color = '#551111'
          end
        elsif view=='time'
          if val.is_a? Integer
            val = Time.at(val)
            if can_edit
              val = val.strftime('%d.%m.%Y %H:%M:%S')
            else
              val = time_to_str(val)
            end
            color = '#338833'
          end
        elsif view=='base64'
          val = val.to_s
          if (not type) #or (type=='Text') or (type=='Blob')
            val = Base64.encode64(val)
          else
            val = Base64.strict_encode64(val)
          end
          color = 'brown'
        elsif view=='phash'
          if val.is_a? String
            if can_edit
              val = PandoraUtils.bytes_to_hex(val)
              color = 'dark blue'
            else
              val = PandoraUtils.bytes_to_hex(val[2,16])
              color = 'blue'
            end
          end
        elsif view=='panhash'
          if val.is_a? String
            if can_edit
              val = PandoraUtils.bytes_to_hex(val)
            else
              val = PandoraUtils.bytes_to_hex(val[0,2])+' '+PandoraUtils.bytes_to_hex(val[2,16])
            end
            color = 'navy'
          end
        elsif view=='hex'
          #val = val.to_i
          val = PandoraUtils.bigint_to_bytes(val) if val.is_a? Integer
          val = PandoraUtils.bytes_to_hex(val)
          #end
          color = 'dark blue'
        elsif view=='boolean'
          if not val.is_a? String
            if ((val.is_a? Integer) and (val != 0)) or (val.is_a? TrueClass)
              val = 'true'
            else
              val = 'false'
            end
          end
        elsif (not can_edit) and (val.is_a? String) # and (view=='text')
          val = Utf8String.new(val)
          val = val[0,50].gsub(/[\r\n\t]/, ' ').squeeze(' ')
          val = val.rstrip
          color = '#226633'
        end
      end
      val ||= ''
      val = Utf8String.new(val.to_s)
      [val, color]
    end

    # Entered view string to value of required type
    # RU: Введённая строка в значение требуемого типа
    def self.view_to_val(val, type, view)
      val = nil if val==''
      if val and view
        case view
          when 'byte', 'word', 'integer', 'coord'
            val = val.to_i
          when 'real'
            val = val.to_f
          when 'date', 'time'
            begin
              val = Time.parse(val)  #Time.strptime(defval, '%d.%m.%Y')
              val = val.to_i
            rescue
              val = 0
            end
          when 'base64'
            if (not type) or (type=='Text') or (type=='Blob')
              val = Base64.decode64(val)
            else
              val = Base64.strict_decode64(val)
            end
            color = 'brown'
          when 'hex', 'panhash', 'phash'
            if (type.is_a? String) and \
            ((['Bigint', 'Panhash', 'String', 'Blob', 'Text', 'Filename'].include? type) \
            or (type[0,7]=='Panhash'))
              val = PandoraUtils.hex_to_bytes(val)
            else
              val = val.to_i(16)
            end
          when 'boolean'
            val = any_value_to_boolean(val)
        end
      end
      val
    end

    # Coordinate as text to float value
    # RU: Координата как текст в число
    def self.text_coord_to_float(text)
      res = 0
      if text.is_a? String
        text.strip!
        if text.size>0
          negative = false
          if 'SWsw-'.include? text[0]
            negative = true
            text = text[1..-1]
            text.strip!
          end
          if (text.size>0) and ('SWsw'.include? text[-1])
            negative = true
            text = text[0..-2]
            text.strip!
          end
          #text = text[1..-1] if ('NEne'.include? text[0])
          if text.size>0
            text.gsub!('′', "'")
            text.gsub!('″', '"')
            text.gsub!('"', "''")
            text.gsub!('`', "'")
            text.gsub!(',', ".")
          end
          deg = nil
          text = text[/[ 1234567890'\.]+/]
          text.strip!
          i = text.index(" ")
          if i
            begin
              deg = text[0, i].to_f
            rescue
              deg = 0
            end
            text = text[i+1..-1]
          end
          i = text.index("'")
          if i
            d = 0
            m = 0
            s = 0
            if deg
              d = deg
            else
              prefix = text[0, i]
              j = prefix.index(".")
              if j
                begin
                  d = text[0, j].to_f
                rescue
                  d = 0
                end
                text = text[j+1..-1]
                i = text.index("'")
              else
                d = 0
              end
            end
            begin
              a = text[0..i-1].to_f
            rescue
              s = 0
            end
            if (i<text.size-1) and (text[i+1]=="'")
              s = a
            else
              m = a
              text = text[i+1..-1].delete("'")
              begin
                s = text.to_f
              rescue
                s = 0
              end
            end
            res = d + m.fdiv(60) + s.fdiv(3600)
          else
            begin
              text = text.to_f
            rescue
              text = 0
            end
            if deg
              res = deg + text.fdiv(100)
            else
              res = text
            end
          end
          res = -(res.abs) if negative
        end
      else
        begin
          res = text.to_f
        rescue
          res = 0
        end
      end
      res
    end

    DegX = 360
    DegY = 180
    MultX = 92681
    MultY = 46340

    NilCoord = 0x7ffe4d8e

    # Coordinate to 4-byte integer
    # RU: Координату в 4-байтовое целое
    def self.coord_to_int(y, x)
      begin
        x = text_coord_to_float(x)
        while x>180
          x = x-360.0
        end
        while x<(-180)
          x = x+360.0
        end
        x = x + 180.0
      rescue
        x = 0
      end
      begin
        y = text_coord_to_float(y)
        while y.abs>90
          if y>90
            y = 180.0-y
          end
          while y<(-90)
            y = -(180.0+y)
          end
        end
        y = y + 90.0
      rescue
        y = 0
      end
      if (y==0) or (x==0)
        x = 360
      end
      xp = (MultX * x.fdiv(DegX)).round
      yp = (MultY * y.fdiv(DegY)).round
      res = MultX*(yp-1)+xp
      res = nil if res==NilCoord
      res
    end

    CoordRound = 2

    # Integer to coordinate
    # RU: Целое в координату
    def self.int_to_coord(int)
      h = (int.fdiv(MultX)).truncate + 1
      s = int - (h-1)*MultX
      x = s.fdiv(MultX)*DegX - 180.0
      y = h.fdiv(MultY)*DegY - 90.0
      x = x.round(CoordRound)
      x = 180.0 if (x==(-180.0))
      y = y.round(CoordRound)
      [y, x]
    end

    # Simplify coordinate
    # RU: Упростить координату
    def self.simplify_coord(val)
      val = val.round(1)
    end

    # Encode data type and size to PSON type and count of size in bytes (1..8)-1
    # RU: Кодирует тип данных и размер в тип PSON и число байт размера
    def self.encode_pson_type(basetype, int)
      count = 0
      neg = 0
      if int<0
        neg = PT_Negative
        int = -int
      end
      while (int>0xFF) and (count<8)
        int = (int >> 8)
        count +=1
      end
      if count >= 8
        puts '[encode_pan_type] Too big int='+int.to_s
        count = 7
      end
      [basetype ^ neg ^ (count << 5), count, (neg>0)]
    end

    # Decode PSON type to data type and count of size in bytes (1..8)-1
    # RU: Раскодирует тип PSON в тип данных и число байт размера
    def self.decode_pson_type(type)
      basetype = type & 0xF
      negative = ((type & PT_Negative)>0)
      count = (type >> 5)
      [basetype, count, negative]
    end

    # Convert ruby object to PSON (Pandora Simple Object Notation)
    # RU: Конвертирует объект руби в PSON ("простая нотация объектов в Пандоре")
    def self.rubyobj_to_pson_elem(rubyobj)
      type = PT_Unknown
      count = 0
      data = AsciiString.new
      elem_size = nil
      case rubyobj
        when String
          data << rubyobj
          elem_size = data.bytesize
          type, count = encode_pson_type(PT_Str, elem_size)
        when Symbol
          data << rubyobj.to_s
          elem_size = data.bytesize
          type, count = encode_pson_type(PT_Sym, elem_size)
        when Integer
          type, count, neg = encode_pson_type(PT_Int, rubyobj)
          rubyobj = -rubyobj if neg
          data << PandoraUtils.bigint_to_bytes(rubyobj)
        when Time
          rubyobj = rubyobj.to_i
          type, count, neg = encode_pson_type(PT_Time, rubyobj)
          rubyobj = -rubyobj if neg
          data << PandoraUtils.bigint_to_bytes(rubyobj)
        when TrueClass, FalseClass
          if rubyobj
            data << [1].pack('C')
          else
            data << [0].pack('C')
          end
          type = PT_Bool
        when Float
          data << [rubyobj].pack('D')
          elem_size = data.bytesize
          type, count = encode_pson_type(PT_Real, elem_size)
        when Array
          rubyobj.each do |a|
            data << rubyobj_to_pson_elem(a)
          end
          elem_size = rubyobj.size
          type, count = encode_pson_type(PT_Array, elem_size)
        when Hash
          rubyobj = rubyobj.sort_by {|k,v| k.to_s}
          rubyobj.each do |a|
            data << rubyobj_to_pson_elem(a[0]) << rubyobj_to_pson_elem(a[1])
          end
          elem_size = rubyobj.bytesize
          type, count = encode_pson_type(PT_Hash, elem_size)
        else
          puts 'Unknown elem type: ['+rubyobj.class.name+']'
      end
      res = AsciiString.new
      res << [type].pack('C')
      data = AsciiString.new(data) if data.is_a? String
      if elem_size
        res << PandoraUtils.fill_zeros_from_left(PandoraUtils.bigint_to_bytes(elem_size), \
          count+1) + data
      else
        res << PandoraUtils.fill_zeros_from_left(data, count+1)
      end
      res = AsciiString.new(res)
    end

    # Convert PSON to ruby object
    # RU: Конвертирует PSON в объект руби
    def self.pson_elem_to_rubyobj(data)
      data = AsciiString.new(data)
      val = nil
      len = 0
      if data.bytesize>0
        type = data[0].ord
        len = 1
        basetype, vlen, neg = decode_pson_type(type)
        vlen += 1
        if data.bytesize >= len+vlen
          int = PandoraUtils.bytes_to_int(data[len, vlen])
          case basetype
            when PT_Int
              val = int
              val = -val if neg
            when PT_Bool
              val = (int != 0)
            when PT_Time
              val = int
              val = -val if neg
              val = Time.at(val)
            when PT_Str, PT_Sym, PT_Real
              pos = len+vlen
              if pos+int>data.bytesize
                int = data.bytesize-pos
              end
              val = ''
              val << data[pos, int]
              vlen += int
              if basetype == PT_Sym
                val = data[pos, int].to_sym
              elsif basetype == PT_Real
                val = data[pos, int].unpack['D']
              end
            when PT_Array, PT_Hash
              val = Array.new
              int *= 2 if basetype == PT_Hash
              while (data.bytesize-1-vlen>0) and (int>0)
                int -= 1
                aval, alen = pson_elem_to_rubyobj(data[len+vlen..-1])
                val << aval
                vlen += alen
              end
              val = Hash[*val] if basetype == PT_Hash
          end
          len += vlen
        else
          len = data.bytesize
        end
      end
      [val, len]
    end

    # Value is empty?
    # RU: Значение пустое?
    def self.value_is_empty?(val)
      res = (val==nil) or (val.is_a? String and (val=='')) \
        or (val.is_a? Integer and (val==0)) or (val.is_a? Time and (val.to_i==0)) \
        or (val.is_a? Array and (val==[])) or (val.is_a? Hash and (val=={}))
      res
    end

    # Pack PanObject fields to PSON binary format
    # RU: Пакует поля панобъекта в бинарный формат PSON
    def self.namehash_to_pson(fldvalues, pack_empty=false)
      #bytes = ''
      #bytes.force_encoding('ASCII-8BIT')
      bytes = AsciiString.new
      fldvalues = fldvalues.sort_by {|k,v| k.to_s } # sort by key
      fldvalues.each { |nam, val|
        if pack_empty or (not value_is_empty?(val))
          nam = nam.to_s
          nsize = nam.bytesize
          nsize = 255 if nsize>255
          bytes << [nsize].pack('C') + nam[0, nsize]
          pson_elem = rubyobj_to_pson_elem(val)
          bytes << pson_elem
        end
      }
      bytes = AsciiString.new(bytes)
    end

    # Convert PSON block to PanObject fields
    # RU: Преобразует PSON блок в поля панобъекта
    def self.pson_to_namehash(pson)
      hash = {}
      while pson and (pson.bytesize>1)
        flen = pson[0].ord
        fname = pson[1, flen]
        if (flen>0) and fname and (fname.bytesize>0)
          val = nil
          if pson.bytesize-flen>1
            pson = pson[1+flen..-1]  # drop getted name
            val, len = pson_elem_to_rubyobj(pson)
            pson = pson[len..-1]     # drop getted value
          else
            pson = nil
          end
          hash[fname] = val
        else
          pson = nil
          hash = nil if hash == {}
        end
      end
      hash
    end



    # Global poiter to repository manager
    # RU: Глобальный указатель на менеджер хранилищ
    $repositories = RepositoryManager.new
    $max_hash_len = 20

    # Create new base ID
    # RU: Создаёт новый идентификатор базы
    def self.create_base_id
      res = PandoraUtils.fill_zeros_from_left(PandoraUtils.bigint_to_bytes(Time.now.to_i), 4)[0,4]
      res << OpenSSL::Random.random_bytes(12)
      res
    end

    # Recognize attributes of the parameter
    # RU: Распознаёт атрибуты параметра
    def self.decode_param_setting(setting)
      res = {}
      if setting.is_a? String
        i = setting.index('"')
        j = nil
        j = setting.index('"', i+1) if i
        if i and j
          res['default'] = setting[i+1..j-1]
          i = setting.index(',', j+1)
          i ||= j
          res['view'] = setting[i+1..-1]
        else
          sets = setting.split(',')
          res['default'] = sets[0]
          res['view'] = sets[1]
        end
      end
      res
    end

    # Normalize parameter value
    # RU: Нормализует значение параметра
    def self.normalize_param_value(val, type)
      type = string_to_pantype(type) if type.is_a? String
      case type
        when PT_Int
          if (not val.is_a? Integer)
            if val
              val = val.to_i
            else
              val = 0
            end
          end
        when PT_Real
          if (not val.is_a? Float)
            if val
              val = val.to_f
            else
              val = 0.0
            end
          end
        when PT_Bool
          val = any_value_to_boolean(val)
        when PT_Time
          if (not val.is_a? Integer)
            if val.is_a? String
              val = Time.parse(val)  #Time.strptime(defval, '%d.%m.%Y')
            else
              val = 0
            end
          end
      end
      val
    end

    # Calculate default value of parameter
    # RU: Вычисляет значение по умолчанию параметра
    def self.calc_default_param_val(type, setting)
      value = nil
      if setting
        ps = decode_param_setting(setting)
        defval = ps['default']
        if defval and defval[0]=='['
          i = defval.index(']')
          i ||= defval.size
          value = self.send(defval[1,i-1])
        else
          value = normalize_param_value(defval, type)
        end
      end
      value
    end

    $main_model_list = {}

    # Get instance of model
    # RU: Возвращает экземпляр модели
    def self.get_model(ider, models=nil)
      if models
        res = models[ider]
      else
        res = $main_model_list[ider]
      end
      if not res
        if Pandora::Model.const_defined? ider
          panobj_class = Pandora::Model.const_get(ider)
          res = panobj_class.new
          if models
            models[ider] = res
          else
            $main_model_list[ider] = res
          end
        end
      end
      res
    end

    # Get parameter value
    # RU: Возвращает значение параметра
    def self.get_param(name, get_id=false)
      value = nil
      id = nil
      param_model = get_model('Parameter')
      sel = param_model.select({'name'=>name}, false, 'value, id, type')
      if not sel[0]
        #p 'parameter was not found: ['+name+']'
        ind = Pandora.config.parameters.index{ |row| row[PF_Name]==name }
        if ind
          # default description is found, create parameter
          row = Pandora.config.parameters[ind]
          type = row[PF_Type]
          type = string_to_pantype(type) if type.is_a? String
          section = row[PF_Section]
          section = PandoraUtils.get_param('section_'+section) if section.is_a? String
          section ||= row[PF_Section].to_i
          values = { :name=>name, :desc=>row[PF_Desc],
            :value=>calc_default_param_val(type, row[PF_Setting]), :type=>type,
            :section=>section, :setting=>row[PF_Setting], :modified=>Time.now.to_i }
          panhash = param_model.panhash(values)
          values['panhash'] = panhash
          #p 'add param: '+values.inspect
          param_model.update(values, nil, nil)
          sel = param_model.select({'name'=>name}, false, 'value, id, type')
        end
      end
      if sel[0]
        # value exists
        value = sel[0][0]
        type = sel[0][2]
        value = normalize_param_value(value, type)
        id = sel[0][1] if get_id
      end
      value = [value, id] if get_id
      #p 'get_param value='+value.inspect
      value
    end

    # Set parameter value
    # RU: Задаёт значение параметра
    def self.set_param(name, value, definition=nil)
      res = false
      old_value, id = PandoraUtils.get_param(name, true)
      param_model = PandoraUtils.get_model('Parameter')
      if (value != old_value) and param_model
        values = {:value=>value, :modified=>Time.now.to_i}
        res = param_model.update(values, nil, 'id='+id.to_s)
      end
      res
    end

    CapSymbols = '123456789qertyupasdfghkzxvbnmQRTYUPADFGHJKLBNM'
    CapFonts = ['Sans', 'Arial', 'Times', 'Verdana', 'Tahoma']

    $poor_cairo_context = true

    # Generate captcha
    # RU: Сгенерировать капчу
    def self.generate_captcha(drawing=nil, length=6, height=70, circles=5, curves=0)

      def self.show_char(c, cr, x0, y0, step)
        #cr.set_font_size(0.3+0.1*rand)
        size = 0.36
        size = 0.38 if ('a'..'z').include? c
        cr.set_font_size(size*(0.7+0.3*rand))
        cr.select_font_face(CapFonts[rand(CapFonts.size)], Cairo::FONT_SLANT_NORMAL, Cairo::FONT_WEIGHT_NORMAL)
        x = x0 + step + 0.2*(rand-0.5)
        y = y0 + 0.1 + 0.3*(rand-0.5)
        cr.move_to(x, y)
        cr.show_text(c)
        cr.stroke
        [x, y]
      end

      def self.show_blur(cr, x0, y0, r)
        cr.close_path
        x, y = [x0, y0]
        #cr.move_to(x, y)
        x1, y1 = x0+1.0*rand*r, y0-0.5*rand*r
        cr.curve_to(x0, y0, x0, y1, x1, y1)
        x2, y2 = x0-1.0*rand*r, y0+0.5*rand-r
        cr.curve_to(x1, y1, x1, y2, x2, y2)
        x3, y3 = x0+1.0*rand*r, y0+0.5*rand-r
        cr.curve_to(x2, y2, x3, y2, x3, y3)
        cr.curve_to(x3, y3, x0, y3, x0, y0)
        cr.stroke
      end

      width = height*2
      cr = nil
      if not drawing
        if $poor_cairo_context
          begin
            drawing = Cairo::ImageSurface.new(width, height)
            cr = Cairo::Context.new(drawing)
          rescue Exception
            $poor_cairo_context = false
          end
        end
        if (not $poor_cairo_context)
          drawing = Gdk::Pixmap.new(nil, width, height, 24)
          cr = drawing.create_cairo_context
        end
      end

      #cr.scale(*widget.window.size)
      cr.scale(height, height)
      cr.set_line_width(0.03)

      cr.set_source_color(Gdk::Color.new(65535, 65535, 65535))
      cr.gdk_rectangle(Gdk::Rectangle.new(0, 0, 2, 1))
      cr.fill

      text = ''
      length.times do
        text << CapSymbols[rand(CapSymbols.size)]
      end
      cr.set_source_rgba(0.0, 0.0, 0.0, 1.0)

      extents = cr.text_extents(text)
      step = 2.0/(text.bytesize+2.0)
      x = 0.0
      y = 0.5

      text.each_char do |c|
        x, y2 = show_char(c, cr, x, y, step)
      end

      cr.set_source_rgba(0.0, 0.0, 0.0, 1.0)

      circles.times do
        x = 0.1+rand(20)/10.0
        y = 0.1+rand(10)/12.0
        r = 0.05+rand/12.0
        f = 2.0*Math::PI * rand
        cr.arc(x, y, r, f, f+(2.2*Math::PI * rand))
        cr.stroke
      end
      curves.times do
        x = 0.1+rand(20)/10.0
        y = 0.1+rand(10)/10.0
        r = 0.3+rand/10.0
        show_blur(cr, x, y, r)
      end

      pixbuf = nil
      if drawing.is_a? Gdk::Pixmap
        pixbuf = Gdk::Pixbuf.from_drawable(nil, drawing, 0, 0, width, height)
      else
        pixbuf = Gdk::Pixbuf.new(drawing.data, Gdk::Pixbuf::COLORSPACE_RGB, true, 8, width, height, width*4)
      end
      buf = pixbuf.save_to_buffer('jpeg')
      [text, buf]
    end

    # OS is 64-bit?
    # RU: ОС является 64-битной?
    def self.is_64bit_os?
      # ENV.has_key?('ProgramFiles(x86)') && File.exist?(ENV['ProgramFiles(x86)']) && \
      # File.directory?(['ProgramFiles(x86)'])
      # (1.size > 4) ? true : false
      # ENV.has_key?('ProgramFiles(x86)')
      (['a'].pack('P').bytesize > 4) ? true : false
    end

    $mp3_player = 'mpg123'
    if Pandora::Utils.os_family=='windows'
      if is_64bit_os?
        $mp3_player = 'mpg123x64.exe'
      else
        $mp3_player = 'cmdmp3.exe'
      end
      # $mp3_player = File.join(Pandora.util_dir, $mp3_player)
      if File.exist?($mp3_player)
        $mp3_player = '"'+$mp3_player+'"'
      else
        $mp3_player = 'mplay32 /play /close'
      end
    else
      res = `which #{$mp3_player}`
      unless (res.is_a? String) and (res.size>0)
        $mp3_player = 'mplayer'
        res = `which #{$mp3_player}`
        unless (res.is_a? String) and (res.size>0)
          $mp3_player = 'ffplay -autoexit -nodisp'
        end
      end
    end

    $waCreateProcess = nil
    $waGetExitCodeProcess = nil
    $waWaitForSingleObject = nil

    # Execute in Windows
    # RU: Запустить в Винде
    def self.win_exec(cmd, wait_sec=nil)
      res = nil
      if init_win32api
        $waCreateProcess ||= Win32API.new('kernel32', 'CreateProcess', \
          ['P', 'P', 'L', 'L', 'L', 'L', 'L', 'P', 'P', 'P'], 'L')
        if $waCreateProcess
          si = 0.chr*256
          pi = 0.chr*256
          res = $waCreateProcess.call(nil, cmd, 0, 0, 0, 8, \
            0, nil, si, pi)
          res = (res.is_a? Numeric) and (res != 0)
          if wait_sec and res
            hProcess = pi.unpack("LLLL")[0]
            #wait for sec
            $waWaitForSingleObject ||= Win32API.new('kernel32', \
              'WaitForSingleObject', ['L','L'],'L')
            wait_sec = 45 unless (wait_sec.is_a? Numeric)
            $waWaitForSingleObject.call(hProcess, wait_sec*1000)
            #get exit code
            $waGetExitCodeProcess ||= Win32API.new('kernel32', \
              'GetExitCodeProcess', ['L','P'],'L')
            exitcode = 0.chr * 32
            $waGetExitCodeProcess.call(hProcess, exitcode)
            exitcode = exitcode.unpack("L")[0]
            p 'exitcode='+exitcode.inspect
            res = (exitcode.is_a? Numeric) and (exitcode == 0)
          end
        end
      end
      res
    end

    $poly_play   = false
    $play_thread = nil
    Default_Mp3 = 'message'

    # Play mp3
    # RU: Проиграть mp3
    def self.play_mp3(filename, path=nil)
      if ($poly_play or (not $play_thread)) \
      and $statusicon and (not $statusicon.destroyed?) \
      and $statusicon.play_sounds and (filename.is_a? String) and (filename.size>0)
        $play_thread = Thread.new do
          begin
            path ||= Pandora.view_dir
            filename ||= Default_Mp3
            filename += '.mp3' unless filename.index('.')
            filename = File.join(path, filename) unless filename.index('/') or filename.index("\\")
            filename = File.join(path, Default_Mp3) unless File.exist?(filename)
            cmd = $mp3_player+' "'+filename+'"'
            if Pandora::Utils.os_family=='windows'
              win_exec(cmd)
            else
              system(cmd)
            end
          ensure
            $play_thread = nil
          end
        end
      end
    end

    # Initialize Gstreamer
    # RU: Инициализировать Gstreamer
    begin
      Gst.init
      gst_vers = Gst.version
      $gst_old = ((gst_vers.is_a? Array) and (gst_vers[0]==0))
    rescue Exception
    end

    # Element stopped?
    # RU: Элемент остановлен
    def self.elem_stopped?(elem)
      res = nil
      if $gst_old
        res = (elem.get_state == Gst::STATE_NULL)
      else
        res = elem.get_state(0)[2]
        res = ((res == Gst::State::VOID_PENDING) or (res == Gst::State::NULL))
      end
      res
    end

    # Element playing?
    # RU: Элемент проигрывается
    def self.elem_playing?(elem)
      res = nil
      if $gst_old
        res = (elem.get_state == Gst::STATE_PLAYING)
      else
        res = elem.get_state(0)[2]
        res = (res == Gst::State::PLAYING)
      end
      res
    end


  end
end
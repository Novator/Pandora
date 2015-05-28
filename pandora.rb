#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# P2P folk network Pandora
# RU: P2P народная сеть Пандора
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк


require 'rexml/document'
require 'zlib'
require 'digest'
require 'base64'
require 'net/http'
require 'net/https'
require 'sqlite3'
begin
  require 'gst'
rescue Exception
end

# Array of localization phrases
# RU: Вектор переведеных фраз
$lang_trans = {}

# Translation of the phrase
# RU: Перевод фразы
def _(frase)
  trans = $lang_trans[frase]
  if not trans or (trans.size==0) and frase and (frase.size>0)
    trans = frase
  end
  trans
end


# ====================================================================
# Utilites module of Pandora
# RU: Вспомогательный модуль Пандоры

module PandoraUtils

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

  # Log level constants
  # RU: Константы уровня логирования
  LM_Error    = 0
  LM_Warning  = 1
  LM_Info     = 2
  LM_Trace    = 3

  # Log level on human view
  # RU: Уровень логирования по-человечьи
  def self.level_to_str(level)
    mes = ''
    case level
      when LM_Error
        mes = _('Error')
      when LM_Warning
        mes = _('Warning')
      when LM_Trace
        mes = _('Trace')
    end
  end

  MaxLogViewLineCount = 500

  # Default log level
  # RU: Уровень логирования по умолчанию
  $show_log_level = LM_Trace

  # Add the message to log
  # RU: Добавить сообщение в лог
  def self.log_message(level, mes)
    if (level <= $show_log_level)
      time = Time.now
      lev = level_to_str(level)
      lev = ' ['+lev+']' if (lev.is_a? String) and (lev.size>0)
      lev ||= ''
      mes = time.strftime('%H:%M:%S') + lev + ': '+mes
      log_view = $window.log_view
      if log_view
        value = log_view.parent.vadjustment.value
        log_view.before_addition(time, value)
        log_view.buffer.insert(log_view.buffer.end_iter, mes+"\n")
        aline_count = log_view.buffer.line_count
        if aline_count>MaxLogViewLineCount
          first = log_view.buffer.start_iter
          last = log_view.buffer.get_iter_at_line_offset(aline_count-MaxLogViewLineCount-1, 0)
          log_view.buffer.delete(first, last)
        end
        log_view.after_addition
      else
        puts mes
      end
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
    langfile = File.join($pandora_lang_dir, lang+'.txt')
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
    def self.end_space_exist?(str)
      lastchar = str[str.size-1, 1]
      (lastchar==' ') or (lastchar=="\t")
    end

    langfile = File.join($pandora_lang_dir, lang+'.txt')
    File.open(langfile, 'w') do |file|
      file.puts('# Pandora language file EN=>'+lang.upcase)
      $lang_trans.each do |value|
        if (not value[0].index('"')) and (not value[1].index('"')) \
          and (not value[0].index("\n")) and (not value[1].index("\n")) \
          and (not end_space_exist?(value[0])) and (not end_space_exist?(value[1]))
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
      lang ||= $lang
      case lang
        when 'ru'
          res = sname
          p res
          if ['ка', 'га', 'ча'].include?(res[-2,2])
            res[-1] = 'и'
          elsif ['г', 'к'].include? res[-1]
            res += 'и'
          elsif ['о'].include? res[-1]
            res[-1] = 'а'
          elsif ['а'].include? res[-1]
            res[-1] = 'ы'
          elsif ['ая'].include? res[-2,2]
            res[-2,2] = 'ые'
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
        unix = (PandoraUtils.os_family != 'windows')
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
        if PandoraUtils.os_family=='windows'
          unzip = File.join($pandora_util_dir, 'unzip.exe')
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
        if PandoraUtils.os_family=='windows'
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

  def self.simplify_single_array(array)
    if array.is_a? Array
      if array.size == 1
        array = array[0]
      elsif array.size == 0
        array = nil
      end
    end
    array
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
  PT_Nil   = 15
  PT_Negative = 16

  # Convert string notation type to code of type
  # RU: Преобразует строковое представление типа в код типа
  def self.string_to_pantype(type)
    res = PT_Nil
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
    res = ''
    if (val.is_a? Integer) or (val.is_a? Time)
      time_now ||= Time.now
      time_now = time_now.to_i
      val = val.to_i
      min_ago = (time_now - val) / 60
      if min_ago < 0
        res = Time.at(val).strftime('%d.%m.%Y')
      elsif min_ago == 0
        res = _('just now')
      elsif min_ago == 1
        res = _('a min. ago')
      else
        midnight = calc_midnight(time_now).to_i
        if (min_ago <= 90) and ((val >= midnight) or (min_ago <= 10))
          res = min_ago.to_s + ' ' + _('min. ago')
        elsif val >= midnight
          res = _('today')+' '+Time.at(val).strftime('%R')
        elsif val >= (midnight-24*3600)  #last midnight
          res = _('yester')+' '+Time.at(val).strftime('%R')
        else
          res = Time.at(val).strftime('%d.%m.%y %R')
        end
      end
    end
    res
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
    while (int>0) and (count<8)
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

  # Convert ruby object to PSON (Pandora simple object notation)
  # RU: Конвертирует объект руби в PSON
  def self.rubyobj_to_pson(rubyobj)
    type = PT_Nil
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
        type = PT_Bool
        type = type ^ PT_Negative if not rubyobj
      when Float
        data << [rubyobj].pack('D')
        elem_size = data.bytesize
        type, count = encode_pson_type(PT_Real, elem_size)
      when Array
        rubyobj.each do |a|
          data << rubyobj_to_pson(a)
        end
        elem_size = rubyobj.size
        type, count = encode_pson_type(PT_Array, elem_size)
      when Hash
        rubyobj = rubyobj.sort_by {|k,v| k.to_s}
        elem_size = 0
        rubyobj.each do |a|
          data << rubyobj_to_pson(a[0]) << rubyobj_to_pson(a[1])
          elem_size += 1
        end
        type, count = encode_pson_type(PT_Hash, elem_size)
      when NilClass
        type = PT_Nil
      else
        puts 'rubyobj_to_pson: illegal ruby class ['+rubyobj.class.name+']'
    end
    res = AsciiString.new
    res << [type].pack('C')
    if (data.is_a? String) and (count>0)
      data = AsciiString.new(data)
      if elem_size
        if (elem_size == data.bytesize) or (rubyobj.is_a? Array) or (rubyobj.is_a? Hash)
          res << PandoraUtils.fill_zeros_from_left( \
            PandoraUtils.bigint_to_bytes(elem_size), count) + data
        else
          puts 'rubyobj_to_pson: elem_size<>data_size: '+elem_size.inspect+'<>'\
            +data.bytesize.inspect + ' data='+data.inspect + ' rubyobj='+rubyobj.inspect
        end
      elsif data.bytesize>0
        res << PandoraUtils.fill_zeros_from_left(data, count)
      end
    end
    res = AsciiString.new(res)
  end

  # Convert PSON to ruby object
  # RU: Конвертирует PSON в объект руби
  def self.pson_to_rubyobj(data)
    data = AsciiString.new(data)
    val = nil
    len = 0
    if data.bytesize>0
      type = data[0].ord
      len = 1
      basetype, count, neg = decode_pson_type(type)
      if data.bytesize >= len+count
        elem_size = 0
        elem_size = PandoraUtils.bytes_to_int(data[len, count]) if count>0
        case basetype
          when PT_Int
            val = elem_size
            val = -val if neg
          when PT_Time
            val = elem_size
            val = -val if neg
            val = Time.at(val)
          when PT_Bool
            if count>0
              val = (elem_size != 0)
            else
              val = (not neg)
            end
          when PT_Str, PT_Sym, PT_Real
            pos = len+count
            if pos+elem_size>data.bytesize
              elem_size = data.bytesize-pos
            end
            val = ''
            val << data[pos, elem_size]
            count += elem_size
            if basetype == PT_Sym
              val = data[pos, elem_size].to_sym
            elsif basetype == PT_Real
              val = data[pos, elem_size].unpack['D']
            end
          when PT_Array, PT_Hash
            val = Array.new
            elem_size *= 2 if basetype == PT_Hash
            while (data.bytesize-1-count>0) and (elem_size>0)
              elem_size -= 1
              aval, alen = pson_to_rubyobj(data[len+count..-1])
              val << aval
              count += alen
            end
            val = Hash[*val] if basetype == PT_Hash
          else
            puts 'pson_to_rubyobj: illegal pson type '+basetype.inspect
        end
        len += count
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
  def self.hash_to_namepson(fldvalues, pack_empty=false)
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
        pson_elem = rubyobj_to_pson(val)
        bytes << pson_elem
      end
    }
    bytes = AsciiString.new(bytes)
  end

  # Convert PSON block to PanObject fields
  # RU: Преобразует PSON блок в поля панобъекта
  def self.namepson_to_hash(pson)
    hash = {}
    while pson and (pson.bytesize>1)
      flen = pson[0].ord
      fname = pson[1, flen]
      if (flen>0) and fname and (fname.bytesize>0)
        val = nil
        if pson.bytesize-flen>1
          pson = pson[1+flen..-1]  # drop getted name
          val, len = pson_to_rubyobj(pson)
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

  # Abstract database adapter
  # RU:Абстрактный адаптер к БД
  class DatabaseSession
    NAME = "Сеанс подключения"
    attr_accessor :connected, :conn_param, :def_flds
    def initialize
      @connected = FALSE
      @conn_param = ''
      @def_flds = {}
    end
    def connect
    end
    def create_table(table_name)
    end
    def select_table(table_name, afilter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
    end
  end

  def self.correct_aster_and_quest!(val)
    if val.is_a? String
      val.gsub!('*', '%')
      val.gsub!('?', '_')
    end
    val
  end

  TI_Name  = 0
  TI_Type  = 1
  TI_Desc  = 2

  # SQLite adapter
  # RU: Адаптер SQLite
  class SQLiteDbSession < DatabaseSession
    NAME = "Сеанс SQLite"
    attr_accessor :db, :exist

    # Type translation Ruby->SQLite
    # RU: Трансляция типа Ruby->SQLite
    def pan_type_to_sqlite_type(rt, size)
      rt_str = rt.to_s
      size_i = size.to_i
      case rt_str
        when 'Integer', 'Word', 'Byte', 'Coord'
          'INTEGER'
        when 'Float'
          'REAL'
        when 'Number', 'Panhash', 'Filename'
          'NUMBER'
        when 'Date', 'Time'
          'DATE'
        when 'String'
          if (1<=size_i) and (size_i<=127)
            'VARCHAR('+size.to_s+')'
          else
            'TEXT'
          end
        when 'Text'
          'TEXT'
        when '',nil
          'NUMBER'
        when 'Blob'
          'BLOB'
        else
          'NUMBER'
      end
    end

    # RU: Преобразует значения ruby в значения sqlite
    def ruby_val_to_sqlite_val(v)
      if v.is_a? Time
        v = v.to_i
      elsif v.is_a? TrueClass
        v = 1
      elsif v.is_a? FalseClass
        v = 0
      end
      v
    end

    # Table definitions of SQLite from fields definitions
    # RU: Описание таблицы SQLite из описания полей
    def panobj_fld_to_sqlite_tab(panobj_flds)
      res = ''
      panobj_flds.each do |fld|
        res = res + ', ' if res != ''
        res = res + fld[FI_Id].to_s + ' ' + pan_type_to_sqlite_type(fld[FI_Type], fld[FI_Size])
      end
      res = '(id INTEGER PRIMARY KEY AUTOINCREMENT, ' + res + ')' if res != ''
      res
    end

    # RU: Подключается к базе
    def connect
      if not @connected
        @db = SQLite3::Database.new(conn_param)
        db.create_function('regexp', 2) do |func, pattern, expression|
          regexp = Regexp.new(pattern.to_s, Regexp::IGNORECASE)
          if expression.to_s.match(regexp)
            func.result = 1
          else
            func.result = 0
          end
        end
        @connected = true
        @exist = {}
      end
      @connected
    end

    # RU: Создает таблицу в базе
    def create_table(table_name, recreate=false, arch_table=nil, \
    arch_fields=nil, new_fields=nil)
      connect
      tfd = db.table_info(table_name)
      tfd.collect! { |x| x['name'] }
      if (not tfd) or (tfd == [])
        @exist[table_name] = false
      else
        @exist[table_name] = true
      end
      tab_def = panobj_fld_to_sqlite_tab(def_flds[table_name])
      if (! exist[table_name] or recreate) and tab_def
        if exist[table_name] and recreate
          res = db.execute('DROP TABLE '+table_name)
        end
        #p 'CREATE TABLE '+table_name+' '+tab_def
        #p 'ALTER TABLE '+table_name+' RENAME TO '+arch_table
        #p 'INSERT INTO '+table_name+' ('+new_fields+') SELECT '+new_fields+' FROM '+arch_table
        #INSERT INTO t1(val1,val2) SELECT t2.val1, t2.val2 FROM t2 WHERE t2.id = @id
        #p 'ALTER TABLE OLD_COMPANY ADD COLUMN SEX char(1)'
        res = db.execute('CREATE TABLE '+table_name+' '+tab_def)
        @exist[table_name] = TRUE
      end
      exist[table_name]
    end

    # RU: Поля таблицы
    def fields_table(table_name)
      connect
      tfd = db.table_info(table_name)
      tfd.collect { |x| [x['name'], x['type']] }
    end

    # RU: Экранирует спецсимволы маски для LIKE символом $
    def escape_like_mask(val)
      #SELECT * FROM mytable WHERE myblob LIKE X'0025';
      #SELECT * FROM mytable WHERE quote(myblob) LIKE 'X''00%';     end
      #Is it possible to pre-process your 10 bytes and insert e.g. symbol '\'
      #before any '\', '_' and '%' symbol? After that you can query
      #SELECT * FROM mytable WHERE myblob LIKE ? ESCAPE '\'
      #SELECT * FROM mytable WHERE substr(myblob, 1, 1) = X'00';
      #SELECT * FROM mytable WHERE substr(myblob, 1, 10) = ?;
      if val.is_a? String
        val.gsub!('$', '$$')
        val.gsub!('_', '$_')
        val.gsub!('%', '$%')
        #query = AsciiString.new(query)
        #i = query.size
        #while i>0
        #  if ['$', '_', '%'].include? query[i]
        #    query = query[0,i+1]+'$'+query[i+1..-1]
        #  end
        #  i -= 1
        #end
      end
      val
    end

    def recognize_filter(filter, sql_values, like_ex=nil)
      esc = false
      if filter.is_a? Hash
        #Example: {:first_name => 'Michael', 'last_name' => 'Galyuk', :sex => 1}
        seq = ''
        filter.each do |n,v|
          if n
            seq = seq + ' AND ' if seq != ''
            seq = seq + n.to_s + '=?'  #only equal!
            sql_values << v
          end
        end
        filter = seq
      elsif filter.is_a? Array
        seq = ''
        if (filter.size>0) and (filter[0].is_a? Array)
          #Example: [['first_name LIKE', 'Mi*'], ['height >', 1.7], ['last_name REGEXP', '\Wgalyuk']]
          filter.each do |n,v|
            if n
              seq = seq + ' AND ' if seq != ''
              ns = n.to_s
              if like_ex
                if ns.index('LIKE') and (v.is_a? String)
                  v = v.dup
                  escape_like_mask(v) if (like_ex & 1 > 0)
                  correct_aster_and_quest!(v) if (like_ex>=2)
                  esc = true
                end
              end
              seq = seq + ns + '?' #operation comes with name!
              sql_values << v
            end
          end
        elsif (filter.size>1) and (filter[0].is_a? String)
          #Example: ['(last_name LIKE ?) OR (last_name=?)', 'Gal*', 'Галюк']
          seq = filter[0].dup
          values = filter[1..-1]
          if like_ex
            if seq.index('LIKE')
              #seq = escape_like_mask(seq) if (like_ex & 1 > 0)
              #correct_aster_and_quest!(seq) if (like_ex>=2)
              values.each_with_index do |v,i|
                if v.is_a? String
                  v = v.dup
                  escape_like_mask(v) if (like_ex & 1 > 0)
                  PandoraUtils.correct_aster_and_quest!(v) if (like_ex>=2)
                  esc = true
                  values[i] = v
                end
              end
            end
          end
          sql_values.concat(values)
          #p 'sql_values='+sql_values.inspect
        else
          puts 'Bad filter: '+filter.inspect
        end
        filter = seq
      end
      filter = nil if (filter and (filter == ''))
      sql = ''
      if filter
        sql = ' WHERE ' + filter
        sql = sql + " ESCAPE '$'" if esc
      end
      sql
    end

    def values_to_ascii(sql_values)
      sql_values.each_with_index do |v, i|
        sql_values[i] = AsciiString.new(sql_values[i]) if sql_values[i].is_a? String
      end
    end

    # RU: Делает выборку из таблицы
    def select_table(table_name, filter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
      res = nil
      connect
      tfd = fields_table(table_name)
      #p '[tfd, table_name, filter, fields, sort, limit, like_filter]='+[tfd, \
      #  table_name, filter, fields, sort, limit, like_filter].inspect
      if tfd and (tfd != [])
        sql_values = Array.new
        filter_sql = recognize_filter(filter, sql_values, like_ex)

        fields ||= '*'
        sql = 'SELECT ' + fields + ' FROM ' + table_name + filter_sql

        if sort and (sort > '')
          sql = sql + ' ORDER BY '+sort
        end
        if limit
          sql = sql + ' LIMIT '+limit.to_s
        end
        values_to_ascii(sql_values)
        #p 'select  sql='+sql.inspect+'  values='+sql_values.inspect+' db='+db.inspect
        res = db.execute(sql, sql_values)
      end
      #p 'res='+res.inspect
      res
    end

    # RU: Записывает данные в таблицу
    def update_table(table_name, values, names=nil, filter=nil)
      res = false
      connect
      sql = ''
      sql_values = Array.new
      sql_values2 = Array.new
      filter_sql = recognize_filter(filter, sql_values2)

      if (not values) and (not names) and filter
        sql = 'DELETE FROM ' + table_name + filter_sql
      elsif values.is_a? Array and names.is_a? Array
        tfd = db.table_info(table_name)
        tfd_name = tfd.collect { |x| x['name'] }
        tfd_type = tfd.collect { |x| x['type'] }

        if filter  #update
          values.each_with_index do |v,i|
            fname = names[i]
            if fname
              sql = sql + ',' if sql != ''
              #v.is_a? String
              #v.force_encoding('ASCII-8BIT')  and v.is_a? String
              #v = AsciiString.new(v) if v.is_a? String
              v = ruby_val_to_sqlite_val(v)
              sql_values << v
              sql = sql + fname.to_s + '=?'
            end
          end

          sql = 'UPDATE ' + table_name + ' SET ' + sql + filter_sql
        else  #insert
          seq = ''
          values.each_with_index do |v,i|
            fname = names[i]
            if fname
              sql = sql + ',' if sql != ''
              seq = seq + ',' if seq != ''
              sql = sql + fname.to_s
              seq = seq + '?'
              #v.force_encoding('ASCII-8BIT')  and v.is_a? String
              #v = AsciiString.new(v) if v.is_a? String
              v = ruby_val_to_sqlite_val(v)
              sql_values << v
            end
          end
          sql = 'INSERT INTO ' + table_name + '(' + sql + ') VALUES(' + seq + ')'
        end
      end
      tfd = fields_table(table_name)
      if tfd and (tfd != [])
        sql_values.concat(sql_values2)
        values_to_ascii(sql_values)
        p 'update: sql='+sql.inspect+' sql_values='+sql_values.inspect
        res = db.execute(sql, sql_values)
        #p 'upd_tab: db.execute.res='+res.inspect
        res = true
      end
      #p 'upd_tab: res='+res.inspect
      res
    end
  end

  # Repository manager
  # RU: Менеджер хранилищ
  class RepositoryManager
    attr_accessor :adapter

    # RU: Инициировать адаптер к базе
    def get_adapter(panobj, table_ptr, recreate=false)
      adap = nil
      if @adapter
        adap = @adapter
      else
        adap = SQLiteDbSession.new
        adap.conn_param = $pandora_sqlite_db
        @adapter = adap
      end
      table_name = table_ptr[1]
      adap.def_flds[table_name] = panobj.def_fields
      if (not table_name) or (table_name=='') then
        puts 'No table name for ['+panobj.name+']'
      else
        adap.create_table(table_name, recreate)
        #adap.create_table(table_name, TRUE)
      end
      adap
    end

    # RU: Сделать выборку из таблицы
    def get_tab_select(panobj, table_ptr, filter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
      adap = get_adapter(panobj, table_ptr)
      adap.select_table(table_ptr[1], filter, fields, sort, limit, like_ex)
    end

    # RU: Записать данные в таблицу
    def get_tab_update(panobj, table_ptr, values, names, filter='')
      res = false
      recreate = ((not values) and (not names) and (not filter))
      adap = get_adapter(panobj, table_ptr, recreate)
      if recreate
        res = (adap != nil)
      else
        res = adap.update_table(table_ptr[1], values, names, filter)
      end
      res
    end

    # RU: Взять список полей
    def get_tab_fields(panobj, table_ptr)
      adap = get_adapter(panobj, table_ptr)
      adap.fields_table(table_ptr[1])
    end
  end

  # Global poiter to repository manager
  # RU: Глобальный указатель на менеджер хранилищ
  $repositories = RepositoryManager.new

  # Property indexes of field definition array
  # RU: Индексы свойств в массиве описания полей
  FI_Id      = 0
  FI_Name    = 1
  FI_Type    = 2
  FI_Size    = 3
  FI_Pos     = 4
  FI_FSize   = 5
  FI_Hash    = 6
  FI_View    = 7
  FI_LName   = 8
  FI_VFName  = 9
  FI_Index   = 10
  FI_LabOr   = 11
  FI_NewRow  = 12
  FI_VFSize  = 13
  FI_Value   = 14
  FI_Widget  = 15
  FI_Label   = 16
  FI_LabW    = 17
  FI_LabH    = 18
  FI_WidW    = 19
  FI_WidH    = 20
  FI_Color   = 21
  FI_Widget2 = 22

  $max_hash_len = 20

  # Base Pandora's object
  # RU: Базовый объект Пандоры
  class BasePanobject
    class << self
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
        @modified = false
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
      def modified
        @modified
      end
      def modified=(x)
        @modified = x
      end
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
      _(PandoraUtils.get_name_or_names(name))
    end

    def pname
      _(PandoraUtils.get_name_or_names(name, true))
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
      self.class.modified = true if res
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
              fval = PandoraUtils.bytes_to_bigint(fval[2,4])
            end
            res = fval.to_i
            coord = PandoraUtils.int_to_coord(res)
            coord[0] = PandoraUtils.simplify_coord(coord[0])
            coord[1] = PandoraUtils.simplify_coord(coord[1])
            fval = PandoraUtils.coord_to_int(*coord)
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
            fval = PandoraUtils.bigint_to_bytes(fval)
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
          res = AsciiString.new(PandoraUtils.bigint_to_bytes(res))
          res = PandoraUtils.fill_zeros_from_left(res, hlen)
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
        res = PandoraUtils.bytes_to_hex(val[0,2])+' '
        val = val[2..-1]
      end
      res2 = PandoraUtils.bytes_to_hex(val)
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
            if (pack_empty or (not PandoraUtils.value_is_empty?(fval)))
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
      if PandoraModel.const_defined? ider
        panobj_class = PandoraModel.const_get(ider)
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

  PF_Name    = 0
  PF_Desc    = 1
  PF_Type    = 2
  PF_Section = 3
  PF_Setting = 4

  # Get parameter value
  # RU: Возвращает значение параметра
  def self.get_param(name, get_id=false)
    value = nil
    id = nil
    param_model = PandoraUtils.get_model('Parameter')
    sel = param_model.select({'name'=>name}, false, 'value, id, type')
    if not sel[0]
      #p 'parameter was not found: ['+name+']'
      ind = $pandora_parameters.index{ |row| row[PF_Name]==name }
      if ind
        # default description is found, create parameter
        row = $pandora_parameters[ind]
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

  # Round queue buffer
  # RU: Циклический буфер
  class RoundQueue < Mutex
    # Init empty queue. Poly read is possible
    # RU: Создание пустой очереди. Возможно множественное чтение
    attr_accessor :queue, :write_ind, :read_ind

    def initialize(poly_read=false)   #init_empty_queue
      super()
      @queue = Array.new
      @write_ind = -1
      if poly_read
        @read_ind = Hash.new  # will be array of read pointers
      else
        @read_ind = -1
      end
    end

    MaxQueue = 20

    # Add block to queue
    # RU: Добавить блок в очередь
    def add_block_to_queue(block, max=MaxQueue)
      res = false
      if block
        synchronize do
          if write_ind<max
            @write_ind += 1
          else
            @write_ind = 0
          end
          queue[write_ind] = block
        end
        res = true
      end
      res
    end

    # Queue state with single reader
    # RU: Состояние очереди с одним читальщиком
    SQS_Empty     = 0
    SQS_NotEmpty  = 1
    SQS_Full      = 2

    # State of single queue
    # RU: Состояние одиночной очереди
    def single_read_state(max=MaxQueue)
      res = SQS_NotEmpty
      if @read_ind.is_a? Integer
        if (@read_ind == write_ind)
          res = SQS_Empty
        else
          wind = write_ind
          if wind<max
            wind += 1
          else
            wind = 0
          end
          res = SQS_Full if (@read_ind == wind)
        end
      end
      res
    end

    # Get block from queue (set "reader" like 0,1,2..)
    # RU: Взять блок из очереди (задавай "reader" как 0,1,2..)
    def get_block_from_queue(max=MaxQueue, reader=nil, move_ptr=true)
      block = nil
      pointers = nil
      synchronize do
        ind = @read_ind
        if reader
          pointers = ind
          ind = pointers[reader]
          ind ||= -1
        end
        #p 'get_block_from_queue:  [reader, ind, write_ind]='+[reader, ind, write_ind].inspect
        if ind != write_ind
          if ind<max
            ind += 1
          else
            ind = 0
          end
          block = queue[ind]
          if move_ptr
            if reader
              pointers[reader] = ind
            else
              @read_ind = ind
            end
          end
        end
      end
      block
    end
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

  # Detect mp3 player command
  # RU: Определить команду mp3 проигрывателя
  def self.detect_mp3_player
    if PandoraUtils.os_family=='windows'
      if is_64bit_os?
        $mp3_player = 'mpg123x64.exe'
      else
        $mp3_player = 'cmdmp3.exe'
      end
      $mp3_player = File.join($pandora_util_dir, $mp3_player)
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
    $mp3_player
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
          path ||= $pandora_view_dir
          filename ||= Default_Mp3
          filename += '.mp3' unless filename.index('.')
          filename = File.join(path, filename) unless filename.index('/') or filename.index("\\")
          filename = File.join(path, Default_Mp3) unless File.exist?(filename)
          cmd = $mp3_player+' "'+filename+'"'
          if PandoraUtils.os_family=='windows'
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


# ====================================================================
# Pandora logic model
# RU: Логическая модель Пандоры

module PandoraModel

  include PandoraUtils

  # Pandora's object
  # RU: Объект Пандоры
  class Panobject < PandoraUtils::BasePanobject
    ider = 'Panobject'
    name = "Объект Пандоры"
  end

  $panobject_list = []

  # Compose pandora model definition from XML file
  # RU: Сформировать описание модели по XML-файлу
  def self.load_model_from_xml(lang='ru')
    lang = '.'+lang
    #dir_mask = File.join(File.join($pandora_model_dir, '**'), '*.xml')
    dir_mask = File.join($pandora_model_dir, '*.xml')
    dir_list = Dir.glob(dir_mask).sort
    dir_list.each do |pathfilename|
      filename = File.basename(pathfilename)
      file = Object::File.open(pathfilename)
      xml_doc = REXML::Document.new(file)
      xml_doc.elements.each('pandora-model/*') do |section|
        if section.name != 'Defaults'
          # Field definition
          section.elements.each('*') do |element|
            panobj_id = element.name
            #p 'panobj_id='+panobj_id.inspect
            new_panobj = true
            flds = Array.new
            panobject_class = nil
            panobject_class = PandoraModel.const_get(panobj_id) if PandoraModel.const_defined? panobj_id
            #p panobject_class
            if panobject_class and panobject_class.def_fields and (panobject_class.def_fields != [])
              # just extend existed class
              panobj_name = panobject_class.name
              panobj_tabl = panobject_class.tables
              new_panobj = false
              #p 'old='+panobject_class.inspect
            else
              # create new class
              panobj_name = panobj_id
              if not panobject_class #not PandoraModel.const_defined? panobj_id
                parent_class = element.attributes['parent']
                if (not parent_class) or (parent_class=='') or (not (PandoraModel.const_defined? parent_class))
                  if parent_class
                    puts _('Parent is not defined, ignored')+' /'+filename+':'+panobj_id+'<'+parent_class
                  end
                  parent_class = 'Panobject'
                end
                if PandoraModel.const_defined? parent_class
                  PandoraModel.const_get(parent_class).def_fields.each do |f|
                    flds << f.dup
                  end
                end
                init_code = 'class '+panobj_id+' < PandoraModel::'+parent_class+'; name = "'+panobj_name+'"; end'
                module_eval(init_code)
                panobject_class = PandoraModel.const_get(panobj_id)
                $panobject_list << panobject_class if not $panobject_list.include? panobject_class
              end

              #p 'new='+panobject_class.inspect
              panobject_class.def_fields = flds
              panobject_class.ider = panobj_id
              kind = panobject_class.superclass.kind #if panobject_class.superclass <= BasePanobject
              kind ||= 0
              panobject_class.kind = kind
              #panobject_class.lang = 5
              panobj_tabl = panobj_id
              panobj_tabl = PandoraUtils::get_name_or_names(panobj_tabl, true, 'en')
              panobj_tabl.downcase!
              panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]]
            end
            panobj_kind = element.attributes['kind']
            panobject_class.kind = panobj_kind.to_i if panobj_kind
            panobj_sort = element.attributes['sort']
            panobject_class.sort = panobj_sort if panobj_sort
            flds = panobject_class.def_fields
            flds ||= Array.new
            #p 'flds='+flds.inspect
            panobj_name_en = element.attributes['name']
            panobj_name = panobj_name_en if (panobj_name==panobj_id) and panobj_name_en and (panobj_name_en != '')
            panobj_name_lang = element.attributes['name'+lang]
            panobj_name = panobj_name_lang if panobj_name_lang and (panobj_name_lang != '')
            #puts panobj_id+'=['+panobj_name+']'
            panobject_class.name = panobj_name

            panobj_tabl = element.attributes['table']
            panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]] if panobj_tabl

            # fill fields
            element.elements.each('*') do |sub_elem|
              #p panobj_id+':'+[sub_elem, sub_elem.name].inspect
              seu = sub_elem.name.upcase
              if seu==sub_elem.name  #elem name has BIG latters
                # This is a function
                p 'Функция не определена: ['+sub_elem.name+']'
              else
                # This is a field
                i = 0
                while (i<flds.size) and (flds[i][FI_Id] != sub_elem.name) do i+=1 end
                fld_exists = (i<flds.size)
                if new_panobj or fld_exists
                  # new panobject or field exists already
                  if fld_exists
                    fld_name = flds[i][FI_Name]
                  else
                    flds[i] = Array.new
                    flds[i][FI_Id] = sub_elem.name
                    fld_name = sub_elem.name
                  end
                  fld_name = sub_elem.attributes['name']
                  flds[i][FI_Name] = fld_name if fld_name and (fld_name != '')
                  #fld_name = fld_name_en if (fld_name_en ) and (fld_name_en != '')
                  fld_name_lang = sub_elem.attributes['name'+lang]
                  flds[i][FI_LName] = fld_name_lang if fld_name_lang and (fld_name_lang != '')
                  #fld_name = fld_name_lang if (fld_name_lang ) and (fld_name_lang != '')
                  #flds[i][FI_Name] = fld_name

                  fld_type = sub_elem.attributes['type']
                  flds[i][FI_Type] = fld_type if fld_type and (fld_type != '')
                  fld_size = sub_elem.attributes['size']
                  flds[i][FI_Size] = fld_size if fld_size and (fld_size != '')
                  fld_pos = sub_elem.attributes['pos']
                  flds[i][FI_Pos] = fld_pos if fld_pos and (fld_pos != '')
                  fld_fsize = sub_elem.attributes['fsize']
                  flds[i][FI_FSize] = fld_fsize.to_i if fld_fsize and (fld_fsize != '')

                  fld_hash = sub_elem.attributes['hash']
                  flds[i][FI_Hash] = fld_hash if fld_hash and (fld_hash != '')

                  fld_view = sub_elem.attributes['view']
                  flds[i][FI_View] = fld_view if fld_view and (fld_view != '')
                else
                  # not new panobject, field doesn't exists
                  puts _('Property was not defined, ignored')+' /'+filename+':'+panobj_id+'.'+sub_elem.name
                end
              end
            end
            #p flds
            #p "========"
            panobject_class.def_fields = flds
          end
        else
          # Default param values
          section.elements.each('*') do |element|
            name = element.name
            desc = element.attributes['desc']
            desc ||= name
            type = element.attributes['type']
            section = element.attributes['section']
            setting = element.attributes['setting']
            row = nil
            ind = $pandora_parameters.index{ |row| row[PandoraUtils::PF_Name]==name }
            if ind
              row = $pandora_parameters[ind]
            else
              row = Array.new
              row[PandoraUtils::PF_Name] = name
              $pandora_parameters << row
              ind = $pandora_parameters.size-1
            end
            row[PandoraUtils::PF_Desc] = desc if desc
            row[PandoraUtils::PF_Type] = type if type
            row[PandoraUtils::PF_Section] = section if section
            row[PandoraUtils::PF_Setting] = setting if setting
            $pandora_parameters[ind] = row
          end
        end
      end
      file.close
    end
  end

  # Panobject class by kind code
  # RU: Класс панобъекта по коду типа
  def self.panobjectclass_by_kind(kind)
    res = nil
    if (kind.is_a? Integer) and (kind>0)
      $panobject_list.each do |panobject_class|
        if panobject_class.kind==kind
          res = panobject_class
          break
        end
      end
    end
    res
  end

  # Normalize and convert trust if need
  # RU: Нормализовать и преобразовать доверие если нужно
  def self.transform_trust(trust, to_int=nil)
    if trust.is_a? Integer
      if trust<(-127)
        trust = -127
      elsif trust>127
        trust = 127
      end
      trust = (trust/127.0) if to_int == false
    elsif trust.is_a? Float
      if trust<(-1.0)
        trust = -1.0
      elsif trust>1.0
        trust = 1.0
      end
      trust = (trust * 127).round if to_int == true
    else
      trust = nil
    end
    trust
  end

  # Pandora record kind
  # RU: Тип записей Пандоры
  PK_Person  = 1
  PK_Key     = 221
  PK_Sign    = 222
  PK_Message = 227

  # Read record by panhash
  # RU: Читает запись по панхэшу
  def self.get_record_by_panhash(kind, panhash, pson_with_kind=nil, models=nil, \
  getfields=nil)
    # pson_with_kind: nil - raw data, false - short panhash+pson, true - panhash+pson
    res = nil
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    if panobjectclass
      model = PandoraUtils.get_model(panobjectclass.ider, models)
      if model
        filter = {'panhash'=>panhash}
        if (kind==PK_Key)
          # Select only open keys!
          filter['kind'] = 0x81
        end
        pson = (pson_with_kind != nil)
        sel = model.select(filter, pson, getfields, nil, 1)
        if sel and (sel.size>0)
          if pson
            #namesvalues = panobject.namesvalues
            #fields = model.matter_fields
            fields = model.clear_excess_fields(sel[0])
            p 'get_rec: matter_fields='+fields.inspect
            # need get all fields (except: id, panhash, modified) + kind
            lang = PandoraUtils.lang_from_panhash(panhash)
            res = AsciiString.new
            res << [kind].pack('C') if pson_with_kind
            res << [lang].pack('C')
            p 'get_record_by_panhash|||  fields='+fields.inspect
            res << PandoraUtils.hash_to_namepson(fields)
          else
            res = sel
          end
        end
      end
    end
    res
  end

  # Save record
  # RU: Сохранить запись
  def self.save_record(kind, lang, values, models=nil, require_panhash=nil)
    res = false
    p '=======save_record  [kind, lang, values]='+[kind, lang, values].inspect
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    ider = panobjectclass.ider
    model = PandoraUtils.get_model(ider, models)
    panhash = model.panhash(values, lang)
    p 'panhash='+panhash.inspect
    if (not require_panhash) or (panhash==require_panhash)
      filter = {'panhash'=>panhash}
      if kind==PK_Key
        filter['kind'] = 0x81
      end
      sel = model.select(filter, true, nil, nil, 1)
      if sel and (sel.size>0)
        res = true
      else
        values['panhash'] = panhash
        values['modified'] = Time.now.to_i
        res = model.update(values, nil, nil)
        model.namesvalues = values
        mfields = model.matter_fields(false)
        str = ''
        mfields.each do |n,v|
          fd = model.field_des(n)
          val, color = PandoraUtils.val_to_view(v, fd[FI_Type], fd[FI_View], false)
          if val
            str << '|' if (str.size>0)
            if val.size>14
              val = val[0,14]
            end
            str << val.to_s
            if str.size >= 80
              str = str[0,80]
              break
            end
          end
        end
        str = '[' + model.sname + ': ' + Utf8String.new(str) + ']'
        if res
          PandoraUtils.log_message(LM_Info, _('Recorded')+' '+str)
        else
          PandoraUtils.log_message(LM_Warning, _('Cannot record')+' '+str)
        end
      end
    else
      PandoraUtils.log_message(LM_Warning, _('Non-equal panhashes ')+' '+ \
        PandoraUtils.bytes_to_hex(panhash) + '<>' + \
        PandoraUtils.bytes_to_hex(require_panhash))
      res = nil
    end
    res
  end

  # Save records from PSON array
  # RU: Сохранить записи из массива PSON
  def self.save_records(records, models=nil)
    if records.is_a? Array
      records.each do |record|
        kind = record[0].ord
        lang = record[1].ord
        values = PandoraUtils.namepson_to_hash(record[2..-1])
        if not PandoraModel.save_record(kind, lang, values, models)
          PandoraUtils.log_message(LM_Warning, _('Cannot write a record')+' 2')
        end
      end
    end
  end

  # Get panhash list of needed records from offer
  # RU: Вернуть список панхэшей нужных записей из предлагаемых
  def self.needed_records(ph_list, models=nil)
    need_list = []
    ph_list.each do |panhash|
      kind = PandoraUtils.kind_from_panhash(panhash)
      res = PandoraModel.get_record_by_panhash(kind, panhash, nil, models, 'id')
      need_list << panhash if (not res)  #add if record was not found
    end
    p 'needed_records='+need_list.inspect
    need_list
  end

  # Get panhash list of modified recs from time for required kinds
  # RU: Ищет список панхэшей изменённых с заданого времени для заданных сортов
  def self.modified_records(from_time=nil, kinds=nil, models=nil)
    res = nil
    kinds ||= (1..254)
    kinds = PandoraUtils.str_to_bytes(kinds)
    kinds.each do |kind|
      panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
      if panobjectclass
        model = PandoraUtils.get_model(panobjectclass.ider, models)
        if model
          filter = [['modified >= ', from_time.to_i]]
          p sel = model.select(filter, false, 'panhash', 'id ASC')
          if sel and (sel.size>0)
            res ||= []
            sel.each do |row|
              res << row[0]
            end
          end
        end
      end
    end
    res
  end

  # Get panhash list of recs created by creator from time for kinds
  # RU: Ищет список панхэшей записей от создателя от времени для сортов
  def self.created_records(creator=0, from_time=nil, kinds=nil, models=nil)
    res = nil
    creator ||= PandoraCrypto.current_user_or_key(true)
    if creator
      # creator=0 - all recs, creator=1 - created recs, creator=String - recs of the creator
      # RU: Все записи (0), записи Created (1), записи указанного создателя (String)
      kinds ||= (1..254)
      kinds = PandoraUtils.str_to_bytes(kinds)
      kinds.each do |kind|
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass and ((creator==0) or (panobjectclass <= PandoraModel::Created))
          model = PandoraUtils.get_model(panobjectclass.ider, models)
          if model
            filter = []
            filter << ['modified >= ', from_time.to_i] if from_time
            filter << ['creator =', creator] if (creator.is_a? String)
            sel = model.select(filter, false, 'panhash', 'modified ASC')
            p '--created_records kind='+kind.inspect+' sel='+sel.inspect
            if sel and (sel.size>0)
              res ||= []
              sel.each do |row|
                res << row[0]
              end
            end
          end
        end
      end
    end
    res
  end

  # Get panhash list of recs created by creator from time for kinds
  # RU: Ищет список панхэшей записей подписанных с времени для сортов
  def self.signed_records(signer=nil, from_time=nil, pankinds=nil, trust=nil, key=nil, models=nil)
    sel = nil
    signer ||= PandoraCrypto.current_user_or_key(true)
    if signer
      sign_model = PandoraUtils.get_model('Sign', models)
      if sign_model
        filter = [['creator=', signer]]
        filter << ['modified >=', from_time.to_i] if from_time
        filter << ['trust=', transform_trust(trust)] if trust
        filter << ['key=', key] if key
        pankinds = PandoraUtils.str_to_bytes(pankinds)
        if ((pankinds.is_a? Array) and (pankinds.size==1))
          filter << ['obj_hash LIKE', pankinds[0].chr+'%']
          #filter << ['second REGEXP', '['+pankinds[0].chr+'].*']  #pankinds[0].chr
          #filter << ['second REGEXP', '['+1.chr+2.chr+'].*']  #pankinds[0].chr
          pankinds = nil
        end
        sel = relation_model.select(filter, false, 'obj_hash', 'modified DESC', nil)
        p 'signed_records sel1='+sel.inspect
        sel.flatten!
        sel.uniq!
        sel.compact!
        sel.sort! {|a,b| a[0]<=>b[0] }
        p 'pankinds='+pankinds.inspect
        if pankinds
          sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
        end
        p 'signed_records sel2='+sel.inspect
      end
    end
    sel
  end

  # Float trust (-1..+1) to public level 21 (0..20)
  # RU: Дробное доверие в уровень публикации 21
  def self.trust2_to_pub21(trust)
    trust ||= -1
    res = (trust*10).round+10
  end

  # Float trust (-1..+1) to public relation kind (235..255)
  # RU: Дробное доверие в вид связи "публикую"
  def self.trust2_to_pub235(trust)
    res = RK_MinPublic + trust2_to_pub21(trust)
  end

  # Get panhash list of published recs from time for level and kinds
  # RU: Ищет список панхэшей опубликованных записей с времени для уровня и сортов
  def self.public_records(publisher=nil, trust=nil, from_time=nil, pankinds=nil, models=nil)
    sel = nil
    publisher ||= PandoraCrypto.current_user_or_key(true)
    if publisher
      relation_model = PandoraUtils.get_model('Relation', models)
      if relation_model
        pub_level = trust
        pub_level = trust2_to_pub235(trust) unless trust.is_a? Numeric
        filter = [['first=', publisher], ['kind >=', pub_level]]
        filter << ['modified >=', from_time.to_i] if from_time
        pankinds = PandoraUtils.str_to_bytes(pankinds)
        if (pankinds.is_a? Array) and (pankinds.size==1)
          filter << ['second LIKE', "\\"+pankinds[0].chr+'%']
          #filter << ['second REGEXP', '['+pankinds[0].chr+'].*']  #pankinds[0].chr
          #filter << ['second REGEXP', '['+1.chr+2.chr+'].*']  #pankinds[0].chr
          pankinds = nil
        end
        sel = relation_model.select(filter, false, 'second', 'modified DESC', nil)
        p 'public_records sel1='+sel.inspect
        sel.flatten!
        sel.uniq!
        sel.compact!
        sel.sort! {|a,b| a[0]<=>b[0] }
        p 'pankinds='+pankinds.inspect
        if (pankinds.is_a? Array) and (pankinds.size>0)
          sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
        end
        p 'public_records sel2='+sel.inspect
      end
    end
    sel
  end

  # Get panhash list of followed recs from time for kinds
  # RU: Ищет список панхэшей следуемых записей с времени для сортов
  def self.follow_records(follower=nil, from_time=nil, pankinds=nil, models=nil)
    sel = nil
    follower ||= PandoraCrypto.current_user_or_key(true)
    if follower
      relation_model = PandoraUtils.get_model('Relation', models)
      if relation_model
        filter = [['first=', follower], ['kind=', RK_Follow]]
        filter << ['modified >=', from_time.to_i] if filter
        pankinds = PandoraUtils.str_to_bytes(pankinds)
        #if ((pankinds.is_a? Array) and (pankinds.size==1))
        #  filter << ['panhash LIKE', pankinds[0]+'%']  REGEXP
        #  pankinds = nil
        #end
        sel = relation_model.select(filter, false, 'second', 'modified DESC', nil, true)
        p 'follow_records sel1='+sel.inspect
        sel.flatten!
        sel.uniq!
        sel.compact!
        sel.sort! {|a,b| a[0]<=>b[0] }
        p 'pankinds='+pankinds.inspect
        if pankinds
          sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
        end
        p 'follow_records sel2='+sel.inspect
      end
    end
    sel
  end

  # Predefined Pandora's codes of languages and Alpha-2
  # RU: Предустановленные коды языков Пандоры и Альфа-2
  Languages = {0=>'all', 1=>'en', 2=>'zh', 3=>'es', 4=>'hi', 5=>'ru', 6=>'ar', \
    7=>'fr', 8=>'pt', 9=>'ja', 10=>'de', 11=>'ko', 12=>'it', 13=>'be', 14=>'id'}

  # Alpha-2 codes of languages
  # RU: Коды языков Альфа-2
  def self.lang_list
    res = Languages.values
  end

  # Get Alpha-2 with language code
  # RU: Взять Альфа-2 по коду языка
  def self.lang_to_text(lang)
    res = Languages[lang]
    res ||= ''
  end

  # Get language code with Alpha-2
  # RU: Взять код языка по Альфа-2
  def self.text_to_lang(text)
    text.downcase! if text.is_a? String
    res = Languages.detect{ |n,v| v==text }
    res = res[0] if res
    res ||= ''
  end

  # Realtion kinds
  # RU: Виды связей
  RK_Unknown  = 0
  RK_Equal    = 1
  RK_Similar  = 2
  RK_Antipod  = 3
  RK_PartOf   = 4
  RK_Cause    = 5
  RK_Follow   = 6
  RK_Ignore   = 7
  RK_CameFrom = 8
  RK_Avatar   = 9
  RK_MinPublic = 235
  RK_MaxPublic = 255

  # Relation is symmetric
  # RU: Связь симметрична
  def self.relation_is_symmetric?(relation)
    res = [RK_Equal, RK_Similar, RK_Unknown].include? relation
  end

  # Check, create or delete relation between two panobjects
  # RU: Проверяет, создаёт или удаляет связь между двумя объектами
  def self.act_relation(panhash1, panhash2, rel_kind=RK_Unknown, act=:check, \
  creator=true, init=false, models=nil)
    res = nil
    if panhash1 or panhash2
      if not (panhash1 and panhash2)
        panhash = PandoraCrypto.current_user_or_key(creator, init)
        if panhash
          if not panhash1
            panhash1 = panhash
          else
            panhash2 = panhash
          end
        end
      end
      if panhash1 and panhash2 #and (panhash1 != panhash2)
        #p 'relat [p1,p2,t]='+[PandoraUtils.bytes_to_hex(panhash1), PandoraUtils.bytes_to_hex(panhash2), rel_kind.inspect
        relation_model = PandoraUtils.get_model('Relation', models)
        if relation_model
          kind_op = '='
          pub_kind = (rel_kind >= RK_MinPublic)
          if pub_kind
            rel_kind = RK_MinPublic if (act == :check)
            kind_op = '>=' if (act != :create)
          end
          kind_op = 'kind' + kind_op
          filter = [['first=', panhash1], ['second=', panhash2], [kind_op, rel_kind]]
          filter2 = nil
          if relation_is_symmetric?(rel_kind) and (panhash1 != panhash2)
            filter = [['first=', panhash2], ['second=', panhash1], [kind_op, rel_kind]]
          end
          #p 'relat2 [p1,p2,t]='+[PandoraUtils.bytes_to_hex(panhash1), PandoraUtils.bytes_to_hex(panhash2), rel_kind].inspect
          #p 'act='+act.inspect
          if (act == :delete)
            res = relation_model.update(nil, nil, filter)
            if filter2
              res2 = relation_model.update(nil, nil, filter2)
              res = res or res2
            end
          else #check or create
            flds = 'id'
            flds << ',kind' if pub_kind
            sel = relation_model.select(filter, false, flds, 'modified DESC', 1)
            exist = (sel and (sel.size>0))
            if (not exist) and filter2
              sel = relation_model.select(filter2, false, flds, 'modified DESC', 1)
              exist = (sel and (sel.size>0))
            end
            res = exist
            res = sel[0][1] if pub_kind and exist
            if (not exist) and (act == :create)
              #p 'UPD!!!'
              if filter2 and (panhash1>panhash2) #when symmetric relation less panhash must be at left
                filter = filter2
              end
              values = {}
              values['first'] = filter[0][1]
              values['second'] = filter[1][1]
              values['kind'] = filter[2][1]
              panhash = relation_model.panhash(values, 0)
              values['panhash'] = panhash
              values['modified'] = Time.now.to_i
              res = relation_model.update(values, nil, nil)
            end
          end
        end
      end
    end
    res
  end

  # Panobject state flags
  # RU: Флаги состояния объекта/записи
  PSF_Support    = 1      # must keep on this node (else will be deleted by GC)
  PSF_Harvest    = 2      # download by pieces in progress
  PSF_Deleted    = 4      # marked to delete
  PSF_Verified   = 8      # signature was verified

end


# ====================================================================
# Cryptography module of Pandora
# RU: Криптографический модуль Пандоры

require 'openssl'

module PandoraCrypto

  include PandoraUtils

  # Hashes
  KH_None   = 0
  KH_Md5    = 0x1
  KH_Sha1   = 0x2
  KH_Sha2   = 0x3
  KH_Sha3   = 0x4
  KH_Rmd    = 0x5

  # Algorithms
  KT_None = 0
  KT_Rsa  = 0x1
  KT_Dsa  = 0x2
  KT_Aes  = 0x6
  KT_Des  = 0x7
  KT_Bf   = 0x8
  KT_Priv = 0xF

  # Lengths
  KL_None    = 0
  KL_bit128  = 0x10   # 16 byte
  KL_bit160  = 0x20   # 20 byte
  KL_bit224  = 0x30   # 28 byte
  KL_bit256  = 0x40   # 32 byte
  KL_bit384  = 0x50   # 48 byte
  KL_bit512  = 0x60   # 64 byte
  KL_bit1024 = 0x70   # 128 byte
  KL_bit2048 = 0x80   # 256 byte
  KL_bit4096 = 0x90   # 512 byte

  KL_BitLens = [128, 160, 224, 256, 384, 512, 1024, 2048, 4096]

  # Key length code to byte length
  # RU: Код длины ключа в байтовую длину
  def self.klen_to_bitlen(len)
    res = nil
    ind = len >> 4
    res = KL_BitLens[ind-1] if ind and (ind>0) and (ind<=KL_BitLens.size)
    res
  end

  # Byte length of key to code
  # RU: Байтовая длина ключа в код длины
  def self.bitlen_to_klen(len)
    res = KL_None
    ind = KL_BitLens.index(len)
    res = KL_BitLens[ind] << 4 if ind
    res
  end

  # Divide type and code of length
  # RU: Разделить тип и код длины
  def self.divide_type_and_klen(tnl)
    tnl = 0 if not tnl.is_a? Integer
    type = tnl & 0x0F
    klen  = tnl & 0xF0
    [type, klen]
  end

  # Encode method codes of cipher and hash
  # RU: Упаковать коды методов шифровки и хэширования
  def self.encode_cipher_and_hash(cipher, hash)
    res = cipher & 0xFF | ((hash & 0xFF) << 8)
  end

  # Decode method codes of cipher and hash
  # RU: Распаковать коды методов шифровки и хэширования
  def self.decode_cipher_and_hash(cnh)
    cipher = cnh & 0xFF
    hash  = (cnh >> 8) & 0xFF
    [cipher, hash]
  end

  # Get OpenSSL object by Pandora code of hash
  # RU: Получает объект OpenSSL по коду хэша Пандоры
  def self.pan_kh_to_openssl_hash(hash_len)
    res = nil
    #p 'hash_len='+hash_len.inspect
    hash, klen = divide_type_and_klen(hash_len)
    #p '[hash, klen]='+[hash, klen].inspect
    case hash
      when KH_Md5
        res = OpenSSL::Digest::MD5.new
      when KH_Sha1
        res = OpenSSL::Digest::SHA1.new
      when KH_Rmd
        res = OpenSSL::Digest::RIPEMD160.new
      when KH_Sha2
        case klen
          when KL_bit256
            res = OpenSSL::Digest::SHA256.new
          when KL_bit224
            res = OpenSSL::Digest::SHA224.new
          when KL_bit384
            res = OpenSSL::Digest::SHA384.new
          when KL_bit512
            res = OpenSSL::Digest::SHA512.new
          else
            res = OpenSSL::Digest::SHA256.new
        end
      when KH_Sha3
        case klen
          when KL_bit256
            res = SHA3::Digest::SHA256.new
          when KL_bit224
            res = SHA3::Digest::SHA224.new
          when KL_bit384
            res = SHA3::Digest::SHA384.new
          when KL_bit512
            res = SHA3::Digest::SHA512.new
          else
            res = SHA3::Digest::SHA256.new
        end
    end
    res
  end

  # Convert Pandora type of hash to OpenSSL name
  # RU: Преобразует тип хэша Пандоры в имя OpenSSL
  def self.pankt_to_openssl(type)
    res = nil
    case type
      when KT_Rsa
        res = 'RSA'
      when KT_Dsa
        res = 'DSA'
      when KT_Aes
        res = 'AES'
      when KT_Des
        res = 'DES'
      when KT_Bf
        res = 'BF'
    end
    res
  end

  # Convert Pandora type of hash to OpenSSL string
  # RU: Преобразует тип хэша Пандоры в строку OpenSSL
  def self.pankt_len_to_full_openssl(type, len, mode=nil)
    res = pankt_to_openssl(type)
    res += '-'+len.to_s if len
    mode ||= 'CFB'  #'CBC - cicle block, OFB - cicle pseudo, CFB - block+pseudo
    res += '-'+mode
  end

  RSA_exponent = 65537

  # Key vector parameter index
  # RU: Индекс параметра в векторе ключа
  KV_Obj   = 0
  KV_Pub   = 1
  KV_Priv  = 2
  KV_Kind  = 3
  KV_Cipher  = 4
  KV_Pass  = 5
  KV_Panhash = 6
  KV_Creator = 7
  KV_Trust   = 8
  KV_NameFamily  = 9

  # Key status
  # RU: Статус ключа
  KS_Exchange  = 1
  KS_Voucher   = 2

  # Encode or decode key
  # RU: Зашифровать или расшифровать ключ
  def self.key_recrypt(data, encode=true, cipher_hash=nil, cipherkey=nil)
    #p '^^^^^^^^^^^^sym_recrypt: [cipher_hash, passwd]='+[cipher_hash, cipherkey].inspect
    #cipher_hash ||= encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
    if cipher_hash and (cipher_hash != 0) and data
      ckind, chash = decode_cipher_and_hash(cipher_hash)
      if (chash == KH_None)
        key_vec = current_key(false, true)
        if key_vec and key_vec[KV_Obj] and key_vec[KV_Panhash]
          if encode
            data = recrypt(key_vec, data, encode)
            if data
              key_and_data = PandoraUtils.rubyobj_to_pson([key_vec[KV_Panhash], data])
              data = key_and_data
            end
          else
            key_and_data, len = PandoraUtils.pson_to_rubyobj(data)
            if key_and_data.is_a? Array
              keyhash, data = key_and_data
              if (keyhash == key_vec[KV_Panhash])
                data = recrypt(key_vec, data, encode)
              else
                data = nil
              end
            else
              PandoraUtils.log_message(LM_Warning, _('Bad data encrypted on key'))
              data = nil
            end
          end
        else
          data = nil
        end
      else
        hash = pan_kh_to_openssl_hash(chash)
        #p 'hash='+hash.inspect
        cipherkey ||= ''
        cipherkey = hash.digest(cipherkey) if hash
        #p 'cipherkey.hash='+cipherkey.inspect
        cipher_vec = Array.new
        cipher_vec[KV_Priv] = cipherkey
        cipher_vec[KV_Kind] = ckind
        cipher_vec = init_key(cipher_vec)
        key = cipher_vec[KV_Obj]
        if key
          iv = nil
          if encode
            iv = key.random_iv
          else
            data, len = PandoraUtils.pson_to_rubyobj(data)   # pson to array
            if data.is_a? Array
              iv = AsciiString.new(data[1])
              data = AsciiString.new(data[0])  # data from array
            else
              data = nil
            end
          end
          cipher_vec[KV_Pub] = iv
          data = recrypt(cipher_vec, data, encode) if data
          data = PandoraUtils.rubyobj_to_pson([data, iv]) if encode and data
        end
      end
    end
    data = AsciiString.new(data) if data
    data
  end

  # Generate a key or key pair
  # RU: Генерирует ключ или ключевую пару
  def self.generate_key(type_klen = KT_Rsa | KL_bit2048, cipher_hash=nil, cipherkey=nil)
    key = nil
    keypub = nil
    keypriv = nil

    type, klen = divide_type_and_klen(type_klen)
    bitlen = klen_to_bitlen(klen)

    case type
      when KT_Rsa
        bitlen ||= 2048
        bitlen = 2048 if bitlen <= 0
        key = OpenSSL::PKey::RSA.generate(bitlen, RSA_exponent)

        #keypub = ''
        #keypub.force_encoding('ASCII-8BIT')
        #keypriv = ''
        #keypriv.force_encoding('ASCII-8BIT')
        keypub = AsciiString.new(PandoraUtils.bigint_to_bytes(key.params['n']))
        keypriv = AsciiString.new(PandoraUtils.bigint_to_bytes(key.params['p']))
        #p keypub = key.params['n']
        #keypriv = key.params['p']
        #p PandoraUtils.bytes_to_bigin(keypub)
        #p '************8'

        #puts key.to_text
        #p key.params

        #key_der = key.to_der
        #p key_der.size

        #key = OpenSSL::PKey::RSA.new(key_der)
        #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
      else #симметричный ключ
        #p OpenSSL::Cipher::ciphers
        key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
        keypub  = key.random_iv
        keypriv = key.random_key
        #p keypub.size
        #p keypriv.size
    end
    keypriv = key_recrypt(keypriv, true, cipher_hash, cipherkey)
    [key, keypub, keypriv, type_klen, cipher_hash, cipherkey]
  end

  # Init key or key pair
  # RU: Инициализирует ключ или ключевую пару
  def self.init_key(key_vec)
    key = key_vec[KV_Obj]
    if not key
      keypub  = key_vec[KV_Pub]
      keypriv = key_vec[KV_Priv]
      keypriv = AsciiString.new(keypriv) if keypriv
      keypub  = AsciiString.new(keypub) if keypub
      type_klen = key_vec[KV_Kind]
      cipher_hash = key_vec[KV_Cipher]
      pass = key_vec[KV_Pass]
      type, klen = divide_type_and_klen(type_klen)
      #p [type, klen]
      bitlen = klen_to_bitlen(klen)
      case type
        when KT_None
          key = nil
        when KT_Rsa
          #p '------'
          #p key.params
          n = PandoraUtils.bytes_to_bigint(keypub)
          #p 'n='+n.inspect
          e = OpenSSL::BN.new(RSA_exponent.to_s)
          p0 = nil
          if keypriv
            #p '[cipher, keypriv]='+[cipher, keypriv].inspect
            keypriv = key_recrypt(keypriv, false, cipher_hash, pass)
            #p 'key2='+key2.inspect
            p0 = PandoraUtils.bytes_to_bigint(keypriv) if keypriv
          else
            p0 = 0
          end

          if p0
            pass = 0
            #p 'n='+n.inspect+'  p='+p0.inspect+'  e='+e.inspect
            begin
              if keypriv
                q = (n / p0)[0]
                p0,q = q,p0 if p0 < q
                d = e.mod_inverse((p0-1)*(q-1))
                dmp1 = d % (p0-1)
                dmq1 = d % (q-1)
                iqmp = q.mod_inverse(p0)

                #p '[n,d,dmp1,dmq1,iqmp]='+[n,d,dmp1,dmq1,iqmp].inspect

                seq = OpenSSL::ASN1::Sequence([
                  OpenSSL::ASN1::Integer(pass),
                  OpenSSL::ASN1::Integer(n),
                  OpenSSL::ASN1::Integer(e),
                  OpenSSL::ASN1::Integer(d),
                  OpenSSL::ASN1::Integer(p0),
                  OpenSSL::ASN1::Integer(q),
                  OpenSSL::ASN1::Integer(dmp1),
                  OpenSSL::ASN1::Integer(dmq1),
                  OpenSSL::ASN1::Integer(iqmp)
                ])
              else
                seq = OpenSSL::ASN1::Sequence([
                  OpenSSL::ASN1::Integer(n),
                  OpenSSL::ASN1::Integer(e),
                ])
              end

              #p asn_seq = OpenSSL::ASN1.decode(key)
              # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
              #seq1 = asn_seq.value[1]
              #str_val = PandoraUtils.bigint_to_bytes(seq1.value)
              #p 'str_val.size='+str_val.size.to_s
              #p Base64.encode64(str_val)
              #key2 = key.public_key
              #p key2.to_der.size
              # Seq: Int:n, Int:e
              #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
              #p key2.to_s

              # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
              key = OpenSSL::PKey::RSA.new(seq.to_der)
              #p key.params
            rescue
              key = nil
            end
          end
        when KT_Dsa
          seq = OpenSSL::ASN1::Sequence([
            OpenSSL::ASN1::Integer(0),
            OpenSSL::ASN1::Integer(key.p),
            OpenSSL::ASN1::Integer(key.q),
            OpenSSL::ASN1::Integer(key.g),
            OpenSSL::ASN1::Integer(key.pub_key),
            OpenSSL::ASN1::Integer(key.priv_key)
          ])
        else
          key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
          key.key = keypriv
          key.iv  = keypub if keypub
      end
      key_vec[KV_Obj] = key
    end
    key_vec
  end

  # Create sign
  # RU: Создает подпись
  def self.make_sign(key, data, hash_len=KH_Sha2 | KL_bit256)
    sign = nil
    begin
      sign = key[KV_Obj].sign(pan_kh_to_openssl_hash(hash_len), data) if key[KV_Obj]
    rescue
      sign = nil
    end
    sign
  end

  # Verify sign
  # RU: Проверяет подпись
  def self.verify_sign(key, data, sign, hash_len=KH_Sha2 | KL_bit256)
    res = false
    res = key[KV_Obj].verify(pan_kh_to_openssl_hash(hash_len), sign, data) if key[KV_Obj]
    res
  end

  #def self.encode_pan_cryptomix(type, cipher, hash)
  #  mix = type & 0xFF | (cipher << 8) & 0xFF | (hash << 16) & 0xFF
  #end

  #def self.decode_pan_cryptomix(mix)
  #  type = mix & 0xFF
  #  cipher = (mix >> 8) & 0xFF
  #  hash = (mix >> 16) & 0xFF
  #  [type, cipher, hash]
  #end

  #def self.detect_key(key)
  #  [key, type, klen, cipher, hash, hlen]
  #end

  # Encode or decode data
  # RU: Зашифровывает или расшифровывает данные
  def self.recrypt(key_vec, data, encrypt=true, private=false)
    recrypted = nil
    key = key_vec[KV_Obj]
    #p 'encrypt key='+key.inspect
    if key.is_a? OpenSSL::Cipher
      if data
        data = AsciiString.new(data)
        key.reset
        if encrypt
          key.encrypt
        else
          key.decrypt
        end
        key.key = key_vec[KV_Priv]
        key.iv = key_vec[KV_Pub] if key_vec[KV_Pub]
        begin
          recrypted = key.update(data) + key.final
        rescue
          recrypted = nil
        end
      end
    else  #elsif key.is_a? OpenSSL::PKey
      if encrypt
        if private
          recrypted = key.private_encrypt(data)
        else
          recrypted = key.public_encrypt(data)
        end
      else
        if private
          recrypted = key.private_decrypt(data)
        else
          recrypted = key.public_decrypt(data)
        end
      end
    end
    recrypted
  end

  # Deactivate current or target key
  # RU: Деактивирует текущий или указанный ключ
  def self.deactivate_key(key_vec)
    if key_vec.is_a? Array
      PandoraUtils.fill_by_zeros(key_vec[PandoraCrypto::KV_Priv])  #private key
      PandoraUtils.fill_by_zeros(key_vec[PandoraCrypto::KV_Pass])
      key_vec.each_index do |i|
        key_vec[i] = nil
      end
    end
    key_vec = nil
  end

  class << self
    attr_accessor :the_current_key
  end

  # Deactivate current key
  # RU: Деактивирует текущий ключ
  def self.reset_current_key
    self.the_current_key = deactivate_key(self.the_current_key)
    $window.set_status_field(PandoraGtk::SF_Auth, 'Not logged', nil, false)
    self.the_current_key
  end

  $first_key_init = true

  # Return current key or allow to choose and activate a key
  # RU: Возвращает текущий ключ или позволяет выбрать и активировать ключ
  def self.current_key(switch_init=false, need_init=true)

    # Read a key from database
    # RU: Считывает ключ из базы
    def self.read_key(panhash, passwd, key_model)
      key_vec = nil
      cipher = nil
      if panhash and (panhash != '')
        filter = {:panhash => panhash}
        sel = key_model.select(filter, false)
        if sel and (sel.size>1)
          kind0 = key_model.field_val('kind', sel[0])
          kind1 = key_model.field_val('kind', sel[1])
          body0 = key_model.field_val('body', sel[0])
          body1 = key_model.field_val('body', sel[1])

          type0, klen0 = divide_type_and_klen(kind0)
          cipher = 0
          if type0==KT_Priv
            priv = body0
            pub = body1
            kind = kind1
            cipher = key_model.field_val('cipher', sel[0])
            creator = key_model.field_val('creator', sel[0])
          else
            priv = body1
            pub = body0
            kind = kind0
            cipher = key_model.field_val('cipher', sel[1])
            creator = key_model.field_val('creator', sel[1])
          end
          key_vec = Array.new
          key_vec[KV_Pub] = pub
          key_vec[KV_Priv] = priv
          key_vec[KV_Cipher] = cipher
          key_vec[KV_Kind] = kind
          key_vec[KV_Pass] = passwd
          key_vec[KV_Panhash] = panhash
          key_vec[KV_Creator] = creator
          cipher ||= 0
        end
      end
      [key_vec, cipher]
    end

    # Recode a key
    # RU: Перекодирует ключ
    def self.recrypt_key(key_model, key_vec, cipher, panhash, passwd, newpasswd)
      if not key_vec
        key_vec, cipher = read_key(panhash, passwd, key_model)
      end
      if key_vec
        key2 = key_vec[KV_Priv]
        cipher = key_vec[KV_Cipher]
        #type_klen = key_vec[KV_Kind]
        #type, klen = divide_type_and_klen(type_klen)
        #bitlen = klen_to_bitlen(klen)
        if key2
          key2 = key_recrypt(key2, false, cipher, passwd)
          if key2
            cipher_hash = 0
            if newpasswd and (newpasswd.size>0)
              cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
            end
            key2 = key_recrypt(key2, true, cipher_hash, newpasswd)
            if key2
              time_now = Time.now.to_i
              filter = {:panhash=>panhash, :kind=>KT_Priv}
              panstate = PandoraModel::PSF_Support
              values = {:panstate=>panstate, :cipher=>cipher_hash, :body=>key2, :modified=>time_now}
              res = key_model.update(values, nil, filter)
              if res
                key_vec[KV_Priv] = key2
                key_vec[KV_Cipher] = cipher_hash
                passwd = newpasswd
              end
            end
          end
        end
      end
      [key_vec, cipher, passwd]
    end

    # body of current_key

    key_vec = self.the_current_key
    if key_vec and switch_init
      key_vec = reset_current_key
    elsif (not key_vec) and need_init
      getting = true
      last_auth_key = PandoraUtils.get_param('last_auth_key')
      last_auth_key0 = last_auth_key
      if last_auth_key.is_a? Integer
        last_auth_key = AsciiString.new(PandoraUtils.bigint_to_bytes(last_auth_key))
      end
      passwd = nil
      key_model = PandoraUtils.get_model('Key')
      while getting
        creator = nil
        filter = {:kind => 0xF}
        sel = key_model.select(filter, false, 'id', nil, 1)
        if sel and (sel.size>0)
          getting = false
          key_vec, cipher = read_key(last_auth_key, passwd, key_model)
          #p '[key_vec, cipher]='+[key_vec, cipher].inspect
          if (not key_vec) or (not cipher) or (cipher != 0) or (not $first_key_init)
            dialog = PandoraGtk::AdvancedDialog.new(_('Key init'))
            dialog.set_default_size(420, 190)

            vbox = Gtk::VBox.new
            dialog.viewport.add(vbox)

            label = Gtk::Label.new(_('Key'))
            vbox.pack_start(label, false, false, 2)
            key_entry = PandoraGtk::PanhashBox.new('Panhash(Key)')
            key_entry.text = PandoraUtils.bytes_to_hex(last_auth_key)
            #key_entry.editable = false
            vbox.pack_start(key_entry, false, false, 2)

            label = Gtk::Label.new(_('Password'))
            vbox.pack_start(label, false, false, 2)
            pass_entry = Gtk::Entry.new
            pass_entry.visibility = false
            if (not cipher) or (cipher == 0)
              pass_entry.editable = false
              pass_entry.sensitive = false
            end
            pass_entry.width_request = 200
            align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
            align.add(pass_entry)
            vbox.pack_start(align, false, false, 2)

            new_label = nil
            new_pass_entry = nil
            new_align = nil

            if key_entry.text == ''
              dialog.def_widget = key_entry.entry
            else
              dialog.def_widget = pass_entry
            end

            changebtn = PandoraGtk::SafeToggleToolButton.new(Gtk::Stock::EDIT)
            changebtn.tooltip_text = _('Change password')
            changebtn.safe_signal_clicked do |*args|
              if not new_label
                new_label = Gtk::Label.new(_('New password'))
                vbox.pack_start(new_label, false, false, 2)
                new_pass_entry = Gtk::Entry.new
                new_pass_entry.width_request = 200
                new_align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
                new_align.add(new_pass_entry)
                vbox.pack_start(new_align, false, false, 2)
                new_align.show_all
              end
              new_label.visible = changebtn.active?
              new_align.visible = changebtn.active?
              if changebtn.active?
                #dialog.set_size_request(420, 250)
                dialog.resize(420, 240)
              else
                dialog.resize(420, 190)
              end
            end
            dialog.hbox.pack_start(changebtn, false, false, 0)

            gen_button = Gtk::ToolButton.new(Gtk::Stock::NEW, _('New'))
            gen_button.tooltip_text = _('Generate new key pair')
            #gen_button.width_request = 110
            gen_button.signal_connect('clicked') { |*args| dialog.response=3 }
            dialog.hbox.pack_start(gen_button, false, false, 0)

            key_vec0 = key_vec
            key_vec = nil
            dialog.run2 do
              if (dialog.response == 3)
                getting = true
              else
                key_vec = key_vec0
                panhash = PandoraUtils.hex_to_bytes(key_entry.text)
                passwd = pass_entry.text
                if changebtn.active? and new_pass_entry
                  key_vec, cipher, passwd = recrypt_key(key_model, key_vec, cipher, panhash, \
                    passwd, new_pass_entry.text)
                end
                #p 'key_vec='+key_vec.inspect
                if (last_auth_key != panhash) or (not key_vec)
                  last_auth_key = panhash
                  key_vec, cipher = read_key(last_auth_key, passwd, key_model)
                  if not key_vec
                    getting = true
                    key_vec = []
                  end
                else
                  key_vec[KV_Pass] = passwd
                end
              end
            end
          end
          $first_key_init = false
        end
        if (not key_vec) and getting
          getting = false
          dialog = PandoraGtk::AdvancedDialog.new(_('Key generation'))
          dialog.set_default_size(420, 250)

          vbox = Gtk::VBox.new
          dialog.viewport.add(vbox)

          #creator = PandoraUtils.bigint_to_bytes(0x01052ec783d34331de1d39006fc80000000000000000)
          label = Gtk::Label.new(_('Person panhash'))
          vbox.pack_start(label, false, false, 2)
          user_entry = PandoraGtk::PanhashBox.new('Panhash(Person)')
          #user_entry.text = PandoraUtils.bytes_to_hex(creator)
          vbox.pack_start(user_entry, false, false, 2)

          rights = KS_Exchange | KS_Voucher
          label = Gtk::Label.new(_('Key credentials'))
          vbox.pack_start(label, false, false, 2)

          hbox = Gtk::HBox.new

          exchange_btn = Gtk::CheckButton.new(_('exchange'), true)
          exchange_btn.active = ((rights & KS_Exchange)>0)
          hbox.pack_start(exchange_btn, true, true, 2)

          voucher_btn = Gtk::CheckButton.new(_('voucher'), true)
          voucher_btn.active = ((rights & KS_Voucher)>0)
          hbox.pack_start(voucher_btn, true, true, 2)

          vbox.pack_start(hbox, false, false, 2)

          label = Gtk::Label.new(_('Password')+' ('+_('optional')+')')
          vbox.pack_start(label, false, false, 2)
          pass_entry = Gtk::Entry.new
          pass_entry.width_request = 250
          align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
          align.add(pass_entry)
          vbox.pack_start(align, false, false, 2)
          #vbox.pack_start(pass_entry, false, false, 2)

          agree_btn = Gtk::CheckButton.new(_('I agree to publish the person name'), true)
          agree_btn.active = true
          agree_btn.signal_connect('clicked') do |widget|
            dialog.okbutton.sensitive = widget.active?
          end
          vbox.pack_start(agree_btn, false, false, 2)

          dialog.def_widget = user_entry.entry

          dialog.run2 do
            creator = PandoraUtils.hex_to_bytes(user_entry.text)
            if creator.size==22
              #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
              passwd = pass_entry.text
              cipher_hash = 0
              if passwd and (passwd.size>0)
                cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
              end

              rights = 0
              rights = (rights | KS_Exchange) if exchange_btn.active?
              rights = (rights | KS_Voucher) if voucher_btn.active?

              #p 'cipher_hash='+cipher_hash.to_s
              type_klen = KT_Rsa | KL_bit2048

              key_vec = generate_key(type_klen, cipher_hash, passwd)

              #p 'key_vec='+key_vec.inspect

              pub  = key_vec[KV_Pub]
              priv = key_vec[KV_Priv]
              type_klen = key_vec[KV_Kind]
              cipher_hash = key_vec[KV_Cipher]
              #passwd = key_vec[KV_Pass]

              key_vec[KV_Creator] = creator

              time_now = Time.now

              vals = time_now.to_a
              y, m, d = [vals[5], vals[4], vals[3]]  #current day
              expire = Time.local(y+5, m, d).to_i

              time_now = time_now.to_i
              panstate = PandoraModel::PSF_Support
              values = {:panstate=>panstate, :kind=>type_klen, :rights=>rights, :expire=>expire, \
                :creator=>creator, :created=>time_now, :cipher=>0, :body=>pub, :modified=>time_now}
              panhash = key_model.panhash(values, rights)
              values['panhash'] = panhash
              key_vec[KV_Panhash] = panhash

              # save public key
              res = key_model.update(values, nil, nil)
              if res
                # save private key
                values[:kind] = KT_Priv
                values[:body] = priv
                values[:cipher] = cipher_hash
                res = key_model.update(values, nil, nil)
                if res
                  #p 'last_auth_key='+panhash.inspect
                  last_auth_key = panhash
                end
              end
            else
              dialog = Gtk::MessageDialog.new($window, \
                Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
                Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
                _('Panhash must consist of 44 symbols'))
              dialog.title = _('Note')
              dialog.default_response = Gtk::Dialog::RESPONSE_OK
              dialog.icon = $window.icon
              if (dialog.run == Gtk::Dialog::RESPONSE_OK)
                PandoraGtk.show_panobject_list(PandoraModel::Person, nil, nil, true)
              end
              dialog.destroy
            end
          end
        end
        if key_vec and (key_vec != [])
          #p 'key_vec='+key_vec.inspect
          key_vec = init_key(key_vec)
          if key_vec and key_vec[KV_Obj]
            self.the_current_key = key_vec
            text = PandoraCrypto.short_name_of_person(key_vec, nil, 1)
            if text and (text.size>0)
              #text = '['+text+']'
            else
              text = 'Logged'
            end
            $window.set_status_field(PandoraGtk::SF_Auth, text, nil, true)
            if last_auth_key0 != last_auth_key
              PandoraUtils.set_param('last_auth_key', last_auth_key)
            end
          else
            dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
              Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
              _('Cannot activate key. Try again?')+"\n[" +PandoraUtils.bytes_to_hex(last_auth_key[2,16])+']')
            dialog.title = _('Key init')
            dialog.default_response = Gtk::Dialog::RESPONSE_OK
            dialog.icon = $window.icon
            getting = (dialog.run == Gtk::Dialog::RESPONSE_OK)
            dialog.destroy
            key_vec = deactivate_key(key_vec) if (not getting)
          end
        else
          key_vec = deactivate_key(key_vec)
        end
      end
    end
    key_vec
  end

  # Get panhash of current user or key
  # RU: Возвращает панхэш текущего пользователя или ключа
  def self.current_user_or_key(user=true, init=true)
    panhash = nil
    key = current_key(false, init)
    if key and key[KV_Obj]
      if user
        panhash = key[KV_Creator]
      else
        panhash = key[KV_Panhash]
      end
    end
    panhash
  end

  # Get panhash of current user and key
  # RU: Возвращает панхэш текущего пользователя и ключа
  def self.current_user_and_key(user=true, init=true)
    res = nil
    key = current_key(false, init)
    if key and key[KV_Obj]
      res = [key[KV_Panhash], key[KV_Creator]]
    end
    res
  end

  PT_Pson1   = 1

  # Sign PSON of PanObject and save a sign as record
  # RU: Подписывает PSON ПанОбъекта и сохраняет подпись как запись
  def self.sign_panobject(panobject, trust=0, models=nil)
    res = false
    key = current_key
    if key and key[KV_Obj] and key[KV_Creator]
      namesvalues = panobject.namesvalues
      matter_fields = panobject.matter_fields

      obj_hash = namesvalues['panhash']
      if not PandoraUtils.panhash_nil?(obj_hash)
        #p 'sign: matter_fields='+matter_fields.inspect
        sign = make_sign(key, PandoraUtils.hash_to_namepson(matter_fields))
        if sign
          time_now = Time.now.to_i
          key_hash = key[KV_Panhash]
          creator = key[KV_Creator]
          trust = PandoraModel.transform_trust(trust, true)

          values = {:modified=>time_now, :obj_hash=>obj_hash, :key_hash=>key_hash, \
            :pack=>PT_Pson1, :trust=>trust, :creator=>creator, :created=>time_now, \
            :sign=>sign}

          sign_model = PandoraUtils.get_model('Sign', models)
          panhash = sign_model.panhash(values)
          #p '!!!!!!panhash='+PandoraUtils.bytes_to_hex(panhash).inspect

          values['panhash'] = panhash
          res = sign_model.update(values, nil, nil)
        else
          PandoraUtils.log_message(LM_Warning, _('Cannot create sign')+' ['+\
            panobject.show_panhash(obj_hash)+']')
        end
      end
    end
    res
  end

  # Delete sign records by the panhash
  # RU: Удаляет подписи по заданному панхэшу
  def self.unsign_panobject(obj_hash, delete_all=false, models=nil)
    res = true
    key_hash = current_user_or_key(false, (not delete_all))
    if obj_hash and (delete_all or key_hash)
      sign_model = PandoraUtils.get_model('Sign', models)
      filter = {:obj_hash=>obj_hash}
      filter[:key_hash] = key_hash if key_hash
      res = sign_model.update(nil, nil, filter)
    end
    res
  end

  $person_trusts = {}

  # Get trust to panobject by its panhash
  # RU: Возвращает доверие к панобъекту по его панхэшу
  def self.trust_in_panobj(panhash, models=nil)
    res = nil
    if panhash and (panhash != '')
      key_hash = current_user_or_key(false, false)
      sign_model = PandoraUtils.get_model('Sign', models)
      filter = {:obj_hash => panhash}
      filter[:key_hash] = key_hash if key_hash
      sel = sign_model.select(filter, false, 'created, trust', 'created DESC', 1)
      if (sel.is_a? Array) and (sel.size>0)
        if key_hash
          last_date = 0
          sel.each_with_index do |row, i|
            created = row[0]
            trust = row[1]
            #p 'sign: [creator, created, trust]='+[creator, created, trust].inspect
            #p '[prev_creator, created, last_date, creator]='+[prev_creator, created, last_date, creator].inspect
            if created>last_date
              #p 'sign2: [creator, created, trust]='+[creator, created, trust].inspect
              last_date = created
              res = PandoraModel.transform_trust(trust, false)
            end
          end
        else
          res = sel.size
        end
      end
    end
    res
  end

  $query_depth = 3

  # Calculate a rate of the panobject
  # RU: Вычислить рейтинг панобъекта
  def self.rate_of_panobj(panhash, depth=$query_depth, querist=nil, models=nil)
    count = 0
    rate = 0.0
    querist_rate = nil
    depth -= 1
    if (depth >= 0) and (panhash != querist) and panhash and (panhash != '')
      if (not querist) or (querist == '')
        querist = current_user_or_key(false, true)
      end
      if querist and (querist != '')
        #kind = PandoraUtils.kind_from_panhash(panhash)
        sign_model = PandoraUtils.get_model('Sign', models)
        filter = { :obj_hash => panhash, :key_hash => querist }
        #filter = {:obj_hash => panhash}
        sel = sign_model.select(filter, false, 'creator, created, trust', 'creator')
        if sel and (sel.size>0)
          prev_creator = nil
          last_date = 0
          last_trust = nil
          last_i = sel.size-1
          sel.each_with_index do |row, i|
            creator = row[0]
            created = row[1]
            trust = row[2]
            #p 'sign: [creator, created, trust]='+[creator, created, trust].inspect
            if creator
              #p '[prev_creator, created, last_date, creator]='+[prev_creator, created, last_date, creator].inspect
              if (not prev_creator) or ((created>last_date) and (creator==prev_creator))
                #p 'sign2: [creator, created, trust]='+[creator, created, trust].inspect
                last_date = created
                last_trust = trust
                prev_creator ||= creator
              end
              if (creator != prev_creator) or (i==last_i)
                p 'sign3: [creator, created, last_trust]='+[creator, created, last_trust].inspect
                person_trust = 1.0 #trust_of_person(creator, my_key_hash)
                rate += PandoraModel.transform_trust(last_trust, false) * person_trust
                prev_creator = creator
                last_date = created
                last_trust = trust
              end
            end
          end
        end
        querist_rate = rate
      end
    end
    [count, rate, querist_rate]
  end

  $max_opened_keys = 1000
  $open_keys = {}

  # Activate a key with given panhash
  # RU: Активировать ключ по заданному панхэшу
  def self.open_key(panhash, models=nil, init=true)
    key_vec = nil
    if panhash.is_a? String
      key_vec = $open_keys[panhash]
      #p 'openkey key='+key_vec.inspect+' $open_keys.size='+$open_keys.size.inspect
      if key_vec
        cur_trust = trust_in_panobj(panhash)
        key_vec[KV_Trust] = cur_trust if cur_trust
      elsif ($open_keys.size<$max_opened_keys)
        model = PandoraUtils.get_model('Key', models)
        filter = {:panhash => panhash}
        sel = model.select(filter, false)
        #p 'openkey sel='+sel.inspect
        if (sel.is_a? Array) and (sel.size>0)
          sel.each do |row|
            kind = model.field_val('kind', row)
            type, klen = divide_type_and_klen(kind)
            if type != KT_Priv
              cipher = model.field_val('cipher', row)
              pub = model.field_val('body', row)
              creator = model.field_val('creator', row)

              key_vec = Array.new
              key_vec[KV_Pub] = pub
              key_vec[KV_Kind] = kind
              #key_vec[KV_Pass] = passwd
              key_vec[KV_Panhash] = panhash
              key_vec[KV_Creator] = creator
              key_vec[KV_Trust] = trust_in_panobj(panhash)

              $open_keys[panhash] = key_vec
              break
            end
          end
        else  #key is not found
          key_vec = 0
        end
      else
        PandoraUtils.log_message(LM_Warning, _('Achieved limit of opened keys')+': '+$open_keys.size.to_s)
      end
    else
      key_vec = panhash
    end
    if init and key_vec and (not key_vec[KV_Obj])
      key_vec = init_key(key_vec)
      #p 'openkey init key='+key_vec.inspect
    end
    key_vec
  end

  # Current kind permission for different trust levels
  # RU: Текущие разрешения сортов для разных уровней доверия
  # (-1.0, -0.9, ... 0.0, 0.1, ... 1.0)
  Allowed_Kinds = [
    [], [], [], [], [], [], [], [], [], [],
    [], [], [], [], [], [], [], [], [], [], [],
  ]

  # Allowed kinds for trust level
  # RU: Допустимые сорта для уровня доверия
  def self.allowed_kinds(trust2, kind_list=nil)
    #res = []
    trust20 = (trust2+1.0)*10
    res = Allowed_Kinds[trust20]
    res
  end

  # Get first name and last name of person
  # RU: Возвращает имя и фамилию человека
  def self.name_and_family_of_person(key, person=nil)
    nf = nil
    #p 'person, key='+[person, key].inspect
    nf = key[KV_NameFamily] if key
    aname, afamily = nil, nil
    if nf.is_a? Array
      #p 'nf='+nf.inspect
      aname, afamily = nf
    elsif (person or key)
      person ||= key[KV_Creator] if key
      kind = PandoraUtils.kind_from_panhash(person)
      sel = PandoraModel.get_record_by_panhash(kind, person, nil, nil, 'first_name, last_name')
      #p 'key, person, sel='+[key, person, sel].inspect
      if (sel.is_a? Array) and (sel.size>0)
        aname, afamily = Utf8String.new(sel[0][0]), Utf8String.new(sel[0][1])
      end
      #p '[aname, afamily]='+[aname, afamily].inspect
      if (not aname) and (not afamily) and (key.is_a? Array)
        aname = key[KV_Creator]
        aname = aname[2, 5] if aname
        aname = PandoraUtils.bytes_to_hex(aname)
        afamily = key[KV_Panhash]
        afamily = afamily[2, 5] if afamily
        afamily = PandoraUtils.bytes_to_hex(afamily)
      end
      if (not aname) and (not afamily) and person
        aname = person[2, 3]
        aname = PandoraUtils.bytes_to_hex(aname) if aname
        afamily = person[5, 4]
        afamily = PandoraUtils.bytes_to_hex(afamily) if afamily
      end
      key[KV_NameFamily] = [aname, afamily] if key
    end
    aname ||= ''
    afamily ||= ''
    #p 'name_and_family_of_person: '+[aname, afamily].inspect
    [aname, afamily]
  end

  # Get short name of person
  # RU: Возвращает короткое имя человека
  def self.short_name_of_person(key, person=nil, view_kind=0, othername=nil)
    aname, afamily = name_and_family_of_person(key, person)
    #p [othername, aname, afamily]
    if view_kind==0
      if othername and (othername == aname)
        res = afamily
      else
        res = aname
      end
    else
      res = ''
      res << aname if (aname and (aname.size>0))
      res << ' ' if (res.size>0)
      res << afamily if (afamily and (afamily.size>0))
    end
    res ||= ''
    res
  end

  # Find sha1-solution
  # RU: Находит sha1-загадку
  def self.find_sha1_solution(phrase)
    res = nil
    lenbit = phrase[phrase.size-1].ord
    len = lenbit/8
    puzzle = phrase[0, len]
    tailbyte = nil
    drift = lenbit - len*8
    if drift>0
      tailmask = 0xFF >> (8-drift)
      tailbyte = (phrase[len].ord & tailmask) if tailmask>0
    end
    i = 0
    while (not res) and (i<0xFFFFFFFF)
      add = PandoraUtils.bigint_to_bytes(i)
      hash = Digest::SHA1.digest(phrase+add)
      offer = hash[0, len]
      if (offer==puzzle) and ((not tailbyte) or ((hash[len].ord & tailmask)==tailbyte))
        res = add
      end
      i += 1
    end
    res
  end

  # Check sha1-solution
  # RU: Проверяет sha1-загадку
  def self.check_sha1_solution(phrase, add)
    res = false
    lenbit = phrase[phrase.size-1].ord
    len = lenbit/8
    puzzle = phrase[0, len]
    tailbyte = nil
    drift = lenbit - len*8
    if drift>0
      tailmask = 0xFF >> (8-drift)
      tailbyte = (phrase[len].ord & tailmask) if tailmask>0
    end
    hash = Digest::SHA1.digest(phrase+add)
    offer = hash[0, len]
    if (offer==puzzle) and ((not tailbyte) or ((hash[len].ord & tailmask)==tailbyte))
      res = true
    end
    res
  end

end


# ====================================================================
# Network classes of Pandora
# RU: Сетевые классы Пандоры

module PandoraNet

  include PandoraUtils

  # Network exchange comands
  # RU: Команды сетевого обмена
  EC_Media     = 0     # Медиа данные
  EC_Auth      = 1     # Инициализация диалога (версия протокола, сжатие, авторизация, шифрование)
  EC_Message   = 2     # Мгновенное текстовое сообщение
  EC_Channel   = 3     # Запрос открытия медиа-канала
  EC_Query     = 4     # Запрос пачки сортов или пачки панхэшей
  EC_News      = 5     # Пачка сортов или пачка панхэшей измененных записей
  EC_Request   = 6     # Запрос записи/патча/миниатюры
  EC_Record    = 7     # Выдача записи
  EC_Lure      = 8     # Запрос рыбака (наживка)
  EC_Bite      = 9     # Ответ рыбки (поклевка)
  EC_Sync      = 10    # Последняя команда в серии, или индикация "живости"
  EC_Wait      = 254   # Временно недоступен
  EC_Bye       = 255   # Рассоединение
  # signs only
  EC_Data      = 256   # Ждем данные

  CommSize = 7
  CommExtSize = 10
  SegNAttrSize = 8

  ECC_Auth_Hello       = 0
  ECC_Auth_Puzzle      = 1
  ECC_Auth_Phrase      = 2
  ECC_Auth_Sign        = 3
  ECC_Auth_Captcha     = 4
  ECC_Auth_Simple      = 5
  ECC_Auth_Answer      = 6

  ECC_Query_Rel        = 0
  ECC_Query_Record     = 1
  ECC_Query_Fish       = 2

  ECC_News_Panhash      = 0
  ECC_News_Record       = 1
  ECC_News_Hook         = 2
  ECC_News_Notice       = 3

  ECC_Channel0_Open     = 0
  ECC_Channel1_Opened   = 1
  ECC_Channel2_Close    = 2
  ECC_Channel3_Closed   = 3
  ECC_Channel4_Fail     = 4

  ECC_Sync1_NoRecord    = 1
  ECC_Sync2_Encode      = 2
  ECC_Sync3_Confirm     = 3

  EC_Wait1_NoFish       = 1
  EC_Wait2_NoFisher     = 2
  EC_Wait3_EmptySegment = 3

  ECC_Bye_Exit          = 200
  ECC_Bye_Unknown       = 201
  ECC_Bye_BadComm       = 202
  ECC_Bye_BadCommCRC    = 203
  ECC_Bye_BadCommLen    = 204
  ECC_Bye_BadSegCRC     = 205
  ECC_Bye_BadDataCRC    = 206
  ECC_Bye_DataTooShort  = 207
  ECC_Bye_DataTooLong   = 208
  ECC_Wait_NoHandlerYet = 209
  ECC_Bye_NoAnswer      = 210
  ECC_Bye_Silent        = 211

  # Session modes
  # RU: Режимы соединения
  SM_GetNotice   = 1
  SM_CiperBF     = 2
  SM_CiperAES    = 4

  # Read modes of socket
  # RU: Режимы чтения из сокета
  RM_Comm      = 0   # Базовая команда
  RM_CommExt   = 1   # Расширение команды для нескольких сегментов
  RM_SegLenN   = 2   # Длина второго и следующих сегмента в серии
  RM_SegmentS  = 3   # Чтение одиночного сегмента
  RM_Segment1  = 4   # Чтение первого сегмента среди нескольких
  RM_SegmentN  = 5   # Чтение второго и следующих сегмента в серии

  # Connection mode
  # RU: Режим соединения
  CM_Hunter       = 1
  CM_KeepHere     = 2
  CM_KeepThere    = 4
  CM_Double       = 8

  # Connection state
  # RU: Состояние соединения
  CS_Connecting    = 0
  CS_Connected     = 1
  CS_Stoping       = 2
  CS_StopRead      = 3
  CS_Disconnected  = 4

  # Stage of exchange
  # RU: Стадия обмена
  ES_Begin        = 0
  ES_IpCheck      = 1
  ES_Protocol     = 3
  ES_Puzzle       = 4
  ES_KeyRequest   = 5
  ES_Sign         = 6
  ES_Captcha      = 7
  ES_Greeting     = 8
  ES_Exchange     = 9

  # Max recv pack size for stadies
  # RU: Максимально допустимые порции для стадий
  MPS_Proto     = 150
  MPS_Puzzle    = 300
  MPS_Sign      = 500
  MPS_Captcha   = 3000
  MPS_Exchange  = 4000
  # Max send segment size
  MaxSegSize  = 1200

  # Connection state flags
  # RU: Флаги состояния соединения
  CSF_Message     = 1
  CSF_Messaging   = 2

  # Address types
  # RU: Типы адресов
  AT_Ip4        = 0
  AT_Ip6        = 1
  AT_Hyperboria = 2
  AT_Netsukuku  = 3

  # Questioner steps
  # RU: Шаги почемучки
  QS_ResetMessage  = 0
  QS_CreatorCheck  = 1
  QS_NewsQuery     = 2
  QS_Finished      = 255

  # Request kind
  # RU: Тип запроса
  RQK_Fishing    = 1      # рыбалка

  # Notice order array indexes
  # RU: Индексы массива заявок на уведомления
  NO_Index           = 0
  NO_Person          = 1
  NO_Key             = 2
  NO_Baseid          = 3
  NO_Notice_trust    = 4
  NO_Notice_depth    = 5
  NO_Time            = 6
  NO_Session         = 7

  # Fish order array indexes
  # RU: Индексы массива заявок на рыбалку
  FO_Index           = 0
  FO_Session         = 1
  FO_Fisher          = 2
  FO_Fisher_key      = 3
  FO_Fisher_baseid   = 4
  FO_Fish            = 5
  FO_Fish_key        = 6
  FO_Time            = 7

  # Pool
  # RU: Пул
  class Pool
    attr_accessor :window, :sessions, :white_list, :fish_orders, :fish_ind, \
      :notice_list, :notice_ind

    MaxWhiteSize = 500
    FishQueueSize = 100

    def initialize(main_window)
      super()
      @window = main_window
      @sessions = Array.new
      @white_list = Array.new
      @fish_ind = -1
      @notice_ind = -1
      @fish_orders = Array.new #PandoraUtils::RoundQueue.new(true)
      @notice_list = Array.new
    end

    def base_id
      $base_id
    end

    # Add ip to white list
    # RU: Добавляет ip в белый список
    def add_to_white(ip)
      while @white_list.size>MaxWhiteSize do
        @white_list.delete_at(0)
      end
      @white_list << ip if (ip and ((not (ip.is_a? String)) or (ip.size>0)) \
        and (not @white_list.include? ip))
    end

    # Is ip in white list?
    # RU: Ip в белом списке?
    def is_white?(ip)
      res = (ip and ((not (ip.is_a? String)) or (ip.size>0)) \
        and (@white_list.include? ip))
    end

    # Is ip in black list?
    # RU: Ip в черном списке?
    def is_black?(ip)
      false
    end

    # Add a session to list
    # RU: Добавляет сессию в список
    def add_session(conn)
      if not sessions.include?(conn)
        sessions << conn
        window.update_conn_status(conn, conn.get_type, 1)
      end
    end

    # Delete the session from list
    # RU: Удаляет сессию из списка
    def del_session(conn)
      if sessions.delete(conn)
        window.update_conn_status(conn, conn.get_type, -1)
      end
    end

    # Get a session by address (ip, port, protocol)
    # RU: Возвращает сессию для адреса
    def sessions_of_address(node)
      host, port, proto = decode_node(node)
      res = sessions.select do |s|
        ((s.host_ip == host) or (s.host_name == host)) and (s.port == port) and (s.proto == proto)
      end
      res
    end

    # Get a session by the node panhash
    # RU: Возвращает сессию по панхэшу узла
    def sessions_of_node(panhash)
      res = sessions.select { |s| (s.node_panhash == panhash) }
      res
    end

    # Get a session by the key panhash
    # RU: Возвращает сессию по панхэшу ключа
    def sessions_of_key(key)
      res = sessions.select { |s| (s.skey and (s.skey[PandoraCrypto::KV_Panhash] == key)) }
      res
    end

    # Get a session by key and base id
    # RU: Возвращает сессию по ключу и идентификатору базы
    def sessions_of_keybase(key, base_id)
      res = sessions.select { |s| (s.to_base_id == base_id) and \
        (s.skey[PandoraCrypto::KV_Panhash] == key) }
      res
    end

    # Get a session by person, key and base id
    # RU: Возвращает сессию по человеку, ключу и идентификатору базы
    def sessions_of_personkeybase(person, key, base_id)
      res = nil
      if (person or key) and base_id
        res = sessions.select do |s|
          sperson, skey = nil
          if s.skey
            sperson = s.skey[PandoraCrypto::KV_Creator]
            skey = s.skey[PandoraCrypto::KV_Panhash]
          end
          ((person.nil? or (sperson == person)) and \
          (key.nil? or (skey == key)) and \
          (base_id.nil? or (s.to_base_id == base_id)))
        end
      end
      res ||= []
      res
    end

    # Get a session by person panhash
    # RU: Возвращает сессию по панхэшу человека
    def sessions_of_person(person)
      res = sessions.select { |s| (s.skey and (s.skey[PandoraCrypto::KV_Creator] == person)) }
      res
    end

    # Get a session by the dialog
    # RU: Возвращает сессию по диалогу
    def sessions_on_dialog(dialog)
      res = sessions.select { |s| (s.dialog == dialog) }
      res.uniq!
      res.compact!
      res
    end

    # Add order to notice
    # RU: Добавить заявку на уведомление
    def add_notice_order(session, person, key, baseid, notice_trust, notice_depth)
      res = nil
      if notice_depth>0
        time = Time.now.to_i
        res = find_notice_order(person, key, baseid, time)
        if ((not (res.is_a? Array)) or (res.size == 0))
          notice_depth -= 1
          p '=====NOTICE ADD [person, key, baseid, notice_trust, notice_depth]='+[person, key, baseid, notice_trust, notice_depth].inspect
          res = [@notice_ind+1, person, key, baseid, notice_trust, notice_depth, time, session]
          @notice_list << res
          @notice_ind += 1
        end
        $window.set_status_field(PandoraGtk::SF_Fish, @notice_list.size.to_s)
      end
      res
    end

    $not_live_per  = 30*60

    def clear_list(list, time_ind, live_per, time=nil)
      time ||= Time.now.to_i
      list.delete_if {|e| (e.is_a? Array) and (e[time_ind] < time-live_per) }
    end

    def find_notice_order(person, key, baseid, time=nil)
      time ||= Time.now.to_i
      clear_list(@notice_list, NO_Time, $not_live_per, time)
      res = @notice_list.select do |no|
        ((person.nil? or (no[PandoraNet::NO_Person] == person)) and \
        (key.nil? or (no[PandoraNet::NO_Key] == key)) and \
        (baseid.nil? or (no[PandoraNet::NO_Baseid] == baseid)))
      end
      res
    end

    $fish_live_per = 10*60

    # Add order to fishing
    # RU: Добавить заявку на рыбалку
    def add_fish_order(session, fisher, fisher_key, fisher_baseid, fish, fish_key, models=nil)
      res = nil
      time = Time.now.to_i
      clear_list(@fish_orders, FO_Time, $fish_live_per, time)
      @fish_orders << [@fish_ind+1, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]
      @fish_ind += 1
      res = true

      #model = PandoraUtils.get_model('Request', models)
      #filter = [['creator=', fisher], ['kind=', PandoraNet::RQK_Fishing]]
      #filter << ['creator_key =', fisher_key] if fisher_key
      #filter << ['creator_baseid =', fisher_baseid] if fisher_baseid
      #filter << ['created >=', from_time] if from_time

      #sel = model.select(filter, false, 'id, body')
      #if sel and (sel.size>0)
      #  sel.each do |row|

          #PandoraUtils.namepson_to_hash(rdata)
          #PandoraUtils.hash_to_namepson(hparams)
          #PandoraUtils.rubyobj_to_pson(param)
          #PandoraUtils.pson_to_rubyobj(panhashes)
      #  end
      #end

      #if not res
      #  time = Time.now.to_i
      #  line = [fisher_key, fisher_baseid, fish_key]
      #  values = {:kind=>PandoraNet::RQK_Fishing, :body=>body,
      #    :state=>0, :creator=>fisher, :created=>time, :modified=>time }
      #  panhash = model.panhash(values)
      #  values['panhash'] = panhash
      #  res = model.update(values, nil, nil)
      #  if res and (id.is_a? Integer)
      #    while (@confirm_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Full) do
      #      sleep(0.02)
      #    end
      #    @confirm_queue.add_block_to_queue([PandoraModel::PK_Message].pack('C') \
      #      +[id].pack('N'))
      #  end
      #end

      #line = [session, fisher_key, fisher_baseid, fish_key]
      #if not @fish_orders.get_block_from_queue(FishQueueSize, session.object_id, false)
      #if true #must check fish history to prevent double order
      #  @fish_orders.add_block_to_queue(line, FishQueueSize)
      #  $window.set_status_field(PandoraGtk::SF_Fisher, @fish_orders.queue.size.to_s)
      #end
      $window.set_status_field(PandoraGtk::SF_Fisher, @fish_orders.size.to_s)
      info = ''
      info << PandoraUtils.bytes_to_hex(fish) if fish
      info << ', '+PandoraUtils.bytes_to_hex(fish_key) if fish_key
      PandoraUtils.log_message(PandoraUtils::LM_Trace, _('Fish order is added')+ \
        ' '+@fish_ind.to_s+':['+info+']')
      res
    end

    def find_fish_order(fisher, fisher_key, fisher_baseid, fish, fish_key)
      res = @fish_orders.select do |fo|
        ((fisher.nil? or (fo[PandoraNet::FO_Fisher] == fisher)) and \
        (fisher_key.nil? or (fo[PandoraNet::FO_Fisher_key] == fisher_key)) and \
        (fisher_baseid.nil? or (fo[PandoraNet::FO_Fisher_baseid] == fisher_baseid)) and \
        (fish.nil? or (fo[PandoraNet::FO_Fish] == fish)) and \
        (fish_key.nil? or (fo[PandoraNet::FO_Fish_key] == fish_key)))
      end
      #FO_Session
      #res.uniq!
      #res.compact!
      res
    end

    def connect_sessions_to_hook(sessions, sess, hook, fisher=false)
      res = false
      if (sessions.is_a? Array) and (sessions.size>0)
        i = 0
        while (i<sessions.size) and (not res)
          session = sessions[i]
          sthread = session.send_thread
          if sthread and sthread.alive?
            session.init_line(line, sess, nil, nil, hook)
            sthread.run if sthread.stop?
            res = true
          end
          i += 1
        end
      end
      res
    end

    # Find or create session with necessary node
    # RU: Находит или создает соединение с нужным узлом
    def init_session(addr=nil, nodehash=nil, send_state_add=nil, dialog=nil, \
    node_id=nil, person=nil, key_hash=nil, base_id=nil)
      p '-------init_session: '+[addr, nodehash, send_state_add, dialog, node_id, \
        person, key_hash, base_id].inspect
      person = PandoraUtils.simplify_single_array(person)
      key_hash = PandoraUtils.simplify_single_array(key_hash)
      nodehash = PandoraUtils.simplify_single_array(nodehash)
      res = nil
      send_state_add ||= CS_Connecting
      sessions = sessions_of_personkeybase(person, key_hash, base_id)
      sessions << sessions_of_node(nodehash) if nodehash
      sessions << sessions_of_address(addr) if addr
      sessions.flatten!
      sessions.uniq!
      sessions.compact!
      if (sessions.is_a? Array) and (sessions.size>0)
        sessions.each_with_index do |session, i|
          session.send_state = (session.send_state | send_state_add)
          session.dialog = nil if (session.dialog and session.dialog.destroyed?)
          session.dialog = dialog if dialog and (i==0)
          if session.dialog and (not session.dialog.destroyed?) \
          and session.dialog.online_button
            session.conn_mode = (session.conn_mode | PandoraNet::CM_KeepHere)
            if ((session.socket and (not session.socket.closed?)) or session.active_hook)
              session.dialog.online_button.safe_set_active(true)
              session.dialog.online_button.inconsistent = false
            end
          end
        end
        res = true
      elsif (addr or nodehash or person)
        p 'NEED connect: '+[addr, nodehash].inspect
        node_model = PandoraUtils.get_model('Node')
        ni = 0
        while (not ni.nil?)
          sel = nil
          filter = nil
          if node_id
            filter = {:id=>node_id}
          elsif nodehash
            if nodehash.is_a? Array
              filter = {:panhash=>nodehash[ni]} if ni<nodehash.size-1
            else
              filter = {:panhash=>nodehash}
            end
          end
          if filter
            p 'filter='+filter.inspect
            sel = node_model.select(filter, false, 'addr, tport, domain, key_hash, id')
          end
          sel ||= Array.new
          if sel and (sel.size==0)
            host = tport = nil
            if addr
              host, tport, proto = decode_node(addr)
              addr = host
            end

            sel << [host, tport, nil, key_hash, node_id]
          end
          if sel and (sel.size>0)
            sel.each do |row|
              addr = row[0]
              addr.strip! if addr
              port = row[1]
              proto = 'tcp'
              host = row[2]
              host.strip! if host
              key_hash_i = row[3]
              key_hash_i.strip! if key_hash_i.is_a? String
              key_hash_i ||= key_hash
              node_id_i = row[4]
              node_id_i ||= node_id
              session = Session.new(nil, host, addr, port, proto, \
                CM_Hunter, node_id_i, dialog, send_state_add, nodehash, \
                person, key_hash_i, base_id)
              res = true
            end
          end
          if (nodehash.is_a? Array) and (ni<nodehash.size-1)
            ni += 1
          else
            ni = nil
          end
        end
      end
      res
    end

    # Stop session with a node
    # RU: Останавливает соединение с заданным узлом
    def stop_session(node=nil, person=nil, nodehash=nil, disconnect=nil)  #, wait_disconnect=true)
      res = false
      p 'stop_session1 nodehash='+nodehash.inspect
      person = PandoraUtils.simplify_single_array(person)
      nodehash = PandoraUtils.simplify_single_array(nodehash)
      sessions = Array.new
      sessions << sessions_of_node(nodehash) if nodehash
      sessions << sessions_of_address(node) if node
      sessions << sessions_of_person(person) if person
      sessions.flatten!
      sessions.uniq!
      sessions.compact!
      if (sessions.is_a? Array) and (sessions.size>0)
        sessions.each do |session|
          if (not session.nil?)
            session.conn_mode = (session.conn_mode & (~PandoraNet::CM_KeepHere))
            session.conn_state = CS_StopRead if disconnect
          end
        end
        res = true
      end
      #res = (session and (session.conn_state != CS_Disconnected)) #and wait_disconnect
      res
    end

    # Form node marker
    # RU: Формирует маркер узла
    def encode_addr(host, port, proto)
      host ||= ''
      port ||= ''
      proto ||= ''
      node = host+'='+port.to_s+proto
    end

    # Unpack node marker
    # RU: Распаковывает маркер узла
    def decode_node(node)
      i = node.index('=')
      if i
        host = node[0, i]
        port = node[i+1, node.size-4-i].to_i
        proto = node[node.size-3, 3]
      else
        host = node
        port = 5577
        proto = 'tcp'
      end
      [host, port, proto]
    end

    # Call callback address
    # RU: Стукануться по обратному адресу
    def check_callback_addr(addr, host_ip)
      res = false
      #p 'check_callback_addr  [addr, host_ip]='+[addr, host_ip].inspect
      if (addr.is_a? String) and (addr.size>0)
        host, port, proto = decode_node(addr)
        host.strip!
        host = host_ip if (not host) or (host=='')
        #p 'check_callback_addr  [host, port, proto]='+[host, port, proto].inspect
        if (host.is_a? String) and (host.size>0)
          p 'check_callback_addr DONE [host, port, proto]='+[host, port, proto].inspect
          res = true
        end
      end
    end

    # Initialize a fish for the required fisher
    # RU: Инициализирует рыбку для заданного рыбака
    def init_fish_for_fisher(fisher, in_lure, aim_keyhash=nil, baseid=nil)
      fish = nil
      if (aim_keyhash==nil) #or (aim_keyhash==mykeyhash)   #
        fish = Session.new(fisher, nil, in_lure, nil, nil, CM_Hunter, \
          nil, nil, nil, nil)
      else  # alien key
        fish = @sessions.index { |session| session.skey[PandoraCrypto::KV_Panhash] == keyhash }
      end
      fish
    end
  end

  $callback_addr = nil
  $puzzle_bit_length = 0  #8..24  (recommended 14)
  $puzzle_sec_delay = 2   #0..255 (recommended 2)
  $captcha_length = 4     #4..8   (recommended 6)
  $captcha_attempts = 2
  $trust_for_captchaed = true
  $trust_for_listener = true
  $low_conn_trust = 0.0

  $keep_alive = 1  #(on/off)
  $keep_idle  = 5  #(after, sec)
  $keep_intvl = 1  #(every, sec)
  $keep_cnt   = 4  #(count)

  class Session

    include PandoraUtils

    attr_accessor :host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state, \
      :stage, :dialog, \
      :send_thread, :read_thread, :socket, :read_state, :send_state, \
      :send_models, :recv_models, :sindex, :read_queue, :send_queue, :confirm_queue, \
      :params, \
      :rcmd, :rcode, :rdata, :scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, \
      :r_encode, \
      :media_send, :node_id, :node_panhash, :to_person, :to_key, :to_base_id, \
      :entered_captcha, :captcha_sw, :hooks, :fish_ind, :notice_ind, \
      :sess_trust, :sess_mode, :notice

    # Set socket options
    # RU: Установить опции сокета
    def set_keepalive(client)
      client.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, $keep_alive)
      if PandoraUtils.os_family != 'windows'
        client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPIDLE, $keep_idle)
        client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPINTVL, $keep_intvl)
        client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPCNT, $keep_cnt)
      end
    end

    # Link to pool
    # RU: Ссылка на пул
    def pool
      $window.pool
    end

    ST_Hunter   = 0
    ST_Listener = 1
    ST_Fisher   = 2

    LHI_Line       = 0
    LHI_Session    = 1
    LHI_Far_Hook   = 2
    LHI_Sess_Hook  = 3

    # Type of session
    # RU: Тип сессии
    def get_type
      res = nil
      if ((@conn_mode & CM_Hunter)>0)
        res = ST_Hunter
      else
        res = ST_Listener
      end
    end

    # Unpack command
    # RU: Распаковать команду
    def unpack_comm(comm)
      index, cmd, code, segsign, crc8 = nil, nil, nil, nil, nil
      errcode = 0
      if comm.bytesize == CommSize
        segsign, index, cmd, code, crc8 = comm.unpack('nnCCC')
        crc8f = (index & 255) ^ ((index >> 8) & 255) ^ (cmd & 255) ^ (code & 255) \
          ^ (segsign & 255) ^ ((segsign >> 8) & 255)
        if crc8 != crc8f
          errcode = 1
        end
      else
        errcode = 2
      end
      [index, cmd, code, segsign, errcode]
    end

    # Unpack command extention
    # RU: Распаковать расширение команды
    def unpack_comm_ext(comm)
      if comm.bytesize == CommExtSize
        datasize, fullcrc32, segsize = comm.unpack('NNn')
      else
        PandoraUtils.log_message(LM_Error, _('Wrong length of command extention'))
      end
      [datasize, fullcrc32, segsize]
    end

    LONG_SEG_SIGN   = 0xFFFF

    def active_hook
      i = @hooks.index {|rec| rec[LHI_Session] and rec[LHI_Session].active? }
    end

    def del_sess_hooks(sess)
      @hooks.delete_if {|rec| rec[LHI_Session]==sess }
    end

    # Send command, code and date (if exists)
    # RU: Отправляет команду, код и данные (если есть)
    def send_comm_and_data(index, cmd, code, data=nil)
      res = nil
      index ||= 0  #нужно ли??!!
      code ||= 0   #нужно ли??!!
      lengt = 0
      lengt = data.bytesize if data
      p log_mes+'SEND_ALL: [index, cmd, code, lengt]='+[index, cmd, code, lengt].inspect
      if @socket.is_a? IPSocket
        data ||= ''
        data = AsciiString.new(data)
        datasize = data.bytesize
        segsign, segdata, segsize = datasize, datasize, datasize
        if datasize>0
          if cmd != EC_Media
            segsize += 4           #for crc32
            segsign = segsize
          end
          if segsize > MaxSegSize
            segsign = LONG_SEG_SIGN
            segsize = MaxSegSize
            if cmd == EC_Media
              segdata = segsize
            else
              segdata = segsize-4  #for crc32
            end
          end
        end
        p [segsign, segdata, segsize].inspect
        crc8 = (index & 255) ^ ((index >> 8) & 255) ^ (cmd & 255) ^ (code & 255) \
          ^ (segsign & 255) ^ ((segsign >> 8) & 255)
        #p 'SCAB: '+[segsign, index, cmd, code, crc8].inspect
        comm = AsciiString.new([segsign, index, cmd, code, crc8].pack('nnCCC'))
        if index<0xFFFF then index += 1 else index = 0 end
        buf = AsciiString.new
        if datasize>0
          if segsign == LONG_SEG_SIGN
            # если пакетов много, то добавить еще 4+4+2= 10 байт
            fullcrc32 = 0
            fullcrc32 = Zlib.crc32(data) if (cmd != EC_Media)
            comm << [datasize, fullcrc32, segsize].pack('NNn')
            buf << data[0, segdata]
          else
            buf << data
          end
          if cmd != EC_Media
            segcrc32 = Zlib.crc32(buf)
            buf << [segcrc32].pack('N')
          end
        end
        buf = comm + buf

        # tos_sip    cs3   0x60  0x18
        # tos_video  af41  0x88  0x22
        # tos_xxx    cs5   0xA0  0x28
        # tos_audio  ef    0xB8  0x2E
        if cmd == EC_Media
          if not @media_send
            @media_send = true
            #socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
            socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0xA0)  # QoS (VoIP пакет)
            p '@media_send = true'
          end
        else
          nodelay = nil
          if @media_send
            socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0)
            nodelay = 0
            @media_send = false
            p '@media_send = false'
          end
          #nodelay = 1 if (cmd == EC_Bye)
          #if nodelay
          #  socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, nodelay)
          #end
        end
        #if cmd == EC_Media
        #  if code==0
        #    p 'send AUDIO ('+buf.size.to_s+')'
        #  else
        #    p 'send VIDEO ('+buf.size.to_s+')'
        #  end
        #end
        begin
          if socket and not socket.closed?
            #p "!SEND_main: buf.size="+buf.bytesize.to_s
            #sended = socket.write(buf)
            sended = socket.send(buf, 0)
          else
            sended = -1
          end
        rescue #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
          sended = -1
        end
        #socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0x00)  # обычный пакет
        #p log_mes+'SEND_MAIN: ('+buf+')'

        if sended == buf.bytesize
          res = index
        elsif sended != -1
          PandoraUtils.log_message(LM_Error, _('Not all data was sent')+' '+sended.to_s)
        end
        segindex = 0
        i = segdata
        while res and ((datasize-i)>0)
          segdata = datasize-i
          segsize = segdata
          if cmd != EC_Media
            segsize += 4           #for crc32
          end
          if segsize > MaxSegSize
            segsize = MaxSegSize
            if cmd == EC_Media
              segdata = segsize
            else
              segdata = segsize-4  #for crc32
            end
          end
          if segindex<0xFFFFFFFF then segindex += 1 else segindex = 0 end
          #p log_mes+'comm_ex_pack: [index, segindex, segsize]='+[index, segindex, segsize].inspect
          comm = [index, segindex, segsize].pack('nNn')
          if index<0xFFFF then index += 1 else index = 0 end
          buf = data[i, segdata]
          if cmd != EC_Media
            segcrc32 = Zlib.crc32(buf)
            buf << [segcrc32].pack('N')
          end
          buf = comm + buf
          begin
            if socket and not socket.closed?
              #sended = socket.write(buf)
              #p "!SEND_add: buf.size="+buf.bytesize.to_s
              sended = socket.send(buf, 0)
            else
              sended = -1
            end
          rescue #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
            sended = -1
          end
          if sended == buf.bytesize
            res = index
            #p log_mes+'SEND_ADD: ('+buf+')'
          elsif sended != -1
            res = nil
            PandoraUtils.log_message(LM_Error, _('Not all data was sent')+'2 '+sended.to_s)
          end
          i += segdata
        end
        if res
          @sindex = res
        end
      elsif @hooks.size>0
        hook = active_hook
        if hook
          rec = @hooks[hook]
          sess = rec[LHI_Session]
          sess_hook = rec[LHI_Sess_Hook]
          if not sess_hook
            sess_hook = sess.hooks.index {|rec| (rec[LHI_Sess_Hook]==hook) and (rec[LHI_Session]==self)}
            p 'Add search sess_hook='+sess_hook.inspect
          end
          if sess_hook
            rec = sess.hooks[sess_hook]
            p 'Fisher send  rec[hook, self, sess_id, fhook]='+[hook, self.object_id, \
              sess.object_id, rec[LHI_Far_Hook], rec[LHI_Sess_Hook]].inspect
            segment = [cmd, code].pack('CC')
            segment << data if data
            far_hook = rec[LHI_Far_Hook]
            if far_hook
              p 'EC_Bite [fhook, segment]='+ [far_hook, segment.bytesize].inspect
              res = sess.send_queue.add_block_to_queue([EC_Bite, far_hook, segment])
            else
              p 'EC_Lure [hook, segment]='+ [hook, segment.bytesize].inspect
              res = sess.send_queue.add_block_to_queue([EC_Lure, hook, segment])
            end
          else
            p 'No sess_hook by hook='+hook.inspect
          end
        else
          p 'No active hook: '+@hooks.size.to_s
        end
      else
        p 'No socket. No hooks'
      end
      res
    end

    # Compose error command and add log message
    # RU: Компонует команду ошибки и логирует сообщение
    def err_scmd(mes=nil, code=nil, buf=nil)
      @scmd = EC_Bye
      if code
        @scode = code
      else
        @scode = rcmd
      end
      if buf
        @sbuf = buf
      elsif buf==false
        @sbuf = nil
      else
        logmes = '(rcmd=' + rcmd.to_s + '/' + rcode.to_s + ' stage=' + stage.to_s + ')'
        logmes0 = logmes
        logmes = mes + ' ' + logmes0 if mes and (mes.bytesize>0)
        @sbuf = logmes
        mesadd = ''
        mesadd = ' err=' + code.to_s if code
        mes = _(mes)
        logmes = mes + ' ' + logmes0 if mes and (mes.bytesize>0)
        PandoraUtils.log_message(LM_Warning, logmes+mesadd)
      end
    end

    # Add segment (chunk, grain, phrase) to pack and send when it's time
    # RU: Добавляет сегмент в пакет и отправляет если пора
    def add_send_segment(ex_comm, last_seg=true, param=nil, ascode=nil)
      res = nil
      ascmd = ex_comm
      ascode ||= 0
      asbuf = nil
      case ex_comm
        when EC_Auth
          #p log_mes+'first key='+key.inspect
          if @rkey and @rkey[PandoraCrypto::KV_Obj]
            key_hash = @rkey[PandoraCrypto::KV_Panhash]
            ascode = EC_Auth
            ascode = ECC_Auth_Hello
            params['mykey'] = key_hash
            params['tokey'] = param
            mode = 0
            mode |= SM_GetNotice if $get_notice
            hparams = {:version=>0, :mode=>mode, :mykey=>key_hash, :tokey=>param, \
              :notice=>(($notice_depth << 8) | $notice_trust)}
            hparams[:addr] = $callback_addr if $callback_addr and ($callback_addr != '')
            asbuf = PandoraUtils.hash_to_namepson(hparams)
          else
            ascmd = EC_Bye
            ascode = ECC_Bye_Exit
            asbuf = nil
          end
        when EC_Message
          #???values = {:destination=>panhash, :text=>text, :state=>state, \
          #  :creator=>creator, :created=>time_now, :modified=>time_now}
          #      kind = PandoraUtils.kind_from_panhash(panhash)
          #      record = PandoraModel.get_record_by_panhash(kind, panhash, true, @recv_models)
          #      p log_mes+'EC_Request panhashes='+PandoraUtils.bytes_to_hex(panhash).inspect
          asbuf = PandoraUtils.rubyobj_to_pson(param)
        when EC_Bye
          ascmd = EC_Bye
          ascode = ECC_Bye_Exit
          asbuf = param
        else
          asbuf = param
      end
      if (@send_queue.single_read_state != PandoraUtils::RoundQueue::SQS_Full)
        res = @send_queue.add_block_to_queue([ascmd, ascode, asbuf])
      end
      if ascmd != EC_Media
        asbuf ||= '';
        p log_mes+'add_send_segment:  [ascmd, ascode, asbuf.bytesize]='+[ascmd, ascode, asbuf.bytesize].inspect
        p log_mes+'add_send_segment2: asbuf='+asbuf.inspect if sbuf
      end
      if not res
        PandoraUtils.log_message(LM_Error, _('Cannot add segment to send queue'))
        @conn_state = CS_Stoping
      end
      res
    end

    def mypersonhash
      @rkey[PandoraCrypto::KV_Creator]
    end

    def mykeyhash
      @rkey[PandoraCrypto::KV_Panhash]
    end

    # Compose command of request of record/records
    # RU: Компонует команду запроса записи/записей
    def set_request(panhashes, send_now=false)
      ascmd = EC_Request
      ascode = 0
      asbuf = nil
      if panhashes.is_a? Array
        # any panhashes
        asbuf = PandoraUtils.rubyobj_to_pson(panhashes)
      else
        # one panhash
        ascode = PandoraUtils.kind_from_panhash(panhashes)
        asbuf = panhashes[1..-1]
      end
      if send_now
        if not add_send_segment(ascmd, true, asbuf, ascode)
          PandoraUtils.log_message(LM_Error, _('Cannot add request'))
        end
      else
        @scmd = ascmd
        @scode = ascode
        @sbuf = asbuf
      end
    end

    # Send command of query of panhashes
    # RU: Шлёт команду запроса панхэшей
    def set_relations_query(list, time, send_now=false)
      ascmd = EC_Query
      ascode = ECC_Query_Rel
      asbuf = [time].pack('N') + list
      if send_now
        if not add_send_segment(ascmd, true, asbuf, ascode)
          PandoraUtils.log_message(LM_Error, _('Cannot add query'))
        end
      else
        @scmd = ascmd
        @scode = ascode
        @sbuf = asbuf
      end
    end

    # Accept received segment
    # RU: Принять полученный сегмент
    def accept_segment

      # Recognize hello data
      # RU: Распознает данные приветствия
      def recognize_params
        hash = PandoraUtils.namepson_to_hash(rdata)
        if not hash
          err_scmd('Hello data is wrong')
        end
        if (rcmd == EC_Auth) and (rcode == ECC_Auth_Hello)
          params['version']  = hash['version']
          params['mode']     = hash['mode']
          params['addr']     = hash['addr']
          params['srckey']   = hash['mykey']
          params['dstkey']   = hash['tokey']
          params['notice']   = hash['notice']
        end
        p log_mes+'RECOGNIZE_params: '+hash.inspect
      end

      # Sel limit of allowed pack size
      # RU: Ставит лимит на допустимый размер пакета
      def set_max_pack_size(stage)
        case @stage
          when ES_Protocol
            @max_pack_size = MPS_Proto
          when ES_Puzzle
            @max_pack_size = MPS_Puzzle
          when ES_Sign
            @max_pack_size = MPS_Sign
          when ES_Captcha
            @max_pack_size = MPS_Captcha
          when ES_Exchange
            @max_pack_size = MPS_Exchange
        end
      end

      # React to hello
      # RU: Отреагировать на приветствие
      def init_skey_or_error(first=true)

        # Generate random phrase
        # RU: Сгенерировать случайную фразу
        def get_sphrase(init=false)
          phrase = params['sphrase'] if not init
          if init or (not phrase)
            phrase = OpenSSL::Random.random_bytes(256)
            params['sphrase'] = phrase
            init = true
          end
          [phrase, init]
        end

        skey_panhash = params['srckey']
        if (skey_panhash.is_a? String) and (skey_panhash.bytesize>0)
          if first and (@stage == ES_Protocol) and $puzzle_bit_length \
          and ($puzzle_bit_length>0) and ((conn_mode & CM_Hunter) == 0)
            # first need to puzzle
            phrase, init = get_sphrase(true)
            phrase[-1] = $puzzle_bit_length.chr
            phrase[-2] = $puzzle_sec_delay.chr
            @stage = ES_Puzzle
            @scode = ECC_Auth_Puzzle
            @scmd  = EC_Auth
            @sbuf = phrase
            params['puzzle_start'] = Time.now.to_i
            set_max_pack_size(ES_Puzzle)
          else
            @skey = PandoraCrypto.open_key(skey_panhash, @recv_models, false)
            # key: 1) trusted and inited, 2) stil not trusted, 3) denied, 4) not found
            # or just 4? other later!
            if (@skey.is_a? Integer) and (@skey==0)
              # unknown key, need request
              @scmd = EC_Request
              kind = PandoraModel::PK_Key
              @scode = kind
              @sbuf = nil
              @stage = ES_KeyRequest
              set_max_pack_size(ES_Exchange)
            elsif @skey
              # ok, send a phrase
              @stage = ES_Sign
              @scode = ECC_Auth_Phrase
              @scmd  = EC_Auth
              set_max_pack_size(ES_Sign)
              phrase, init = get_sphrase(false)
              p log_mes+'send phrase len='+phrase.bytesize.to_s
              if init
                @sbuf = phrase
              else
                @sbuf = nil
              end
            else
              err_scmd('Key is invalid')
            end
          end
        else
          err_scmd('Key panhash is required')
        end
      end

      # Compose a captcha command
      # RU: Компоновать команду с капчой
      def send_captcha
        attempts = @skey[PandoraCrypto::KV_Trust]
        p log_mes+'send_captcha:  attempts='+attempts.to_s
        if attempts<$captcha_attempts
          @skey[PandoraCrypto::KV_Trust] = attempts+1
          @scmd = EC_Auth
          @scode = ECC_Auth_Captcha
          text, buf = PandoraUtils.generate_captcha(nil, $captcha_length)
          params['captcha'] = text.downcase
          clue_text = 'You may enter small letters|'+$captcha_length.to_s+'|'+PandoraGtk::CapSymbols
          clue_text = clue_text[0,255]
          @sbuf = [clue_text.bytesize].pack('C')+clue_text+buf
          @stage = ES_Captcha
          set_max_pack_size(ES_Captcha)
        else
          err_scmd('Captcha attempts is exhausted')
        end
      end

      # Update record about node
      # RU: Обновить запись об узле
      def update_node(skey_panhash=nil, sbase_id=nil, trust=nil, session_key=nil)
        node_model = PandoraUtils.get_model('Node', @recv_models)
        time_now = Time.now.to_i
        astate = 0
        asended = 0
        areceived = 0
        aone_ip_count = 0
        abad_attempts = 0
        aban_time = 0
        apanhash = nil
        akey_hash = nil
        abase_id = nil
        acreator = nil
        acreated = nil
        aaddr = nil
        adomain = nil
        atport = nil
        auport = nil
        anode_id = nil

        readflds = 'id, state, sended, received, one_ip_count, bad_attempts,' \
           +'ban_time, panhash, key_hash, base_id, creator, created, addr, domain, tport, uport'

        trusted = ((trust.is_a? Float) and (trust>0))
        filter = {:key_hash=>skey_panhash, :base_id=>sbase_id}
        #if not trusted
        #  filter[:addr_from] = host_ip
        #end
        sel = node_model.select(filter, false, readflds, nil, 1)
        if ((not sel) or (sel.size==0)) and @node_id
          filter = {:id => @node_id}
          sel = node_model.select(filter, false, readflds, nil, 1)
        end

        if sel and (sel.size>0)
          row = sel[0]
          anode_id = row[0]
          astate = row[1]
          asended = row[2]
          areceived = row[3]
          aone_ip_count = row[4]
          aone_ip_count ||= 0
          abad_attempts = row[5]
          aban_time = row[6]
          apanhash = row[7]
          akey_hash = row[8]
          abase_id = row[9]
          acreator = row[10]
          acreated = row[11]
          aaddr = row[12]
          adomain = row[13]
          atport = row[14]
          auport = row[15]
        else
          filter = nil
        end

        p '=====%%%% %%%: [aaddr, adomain, @host_ip, @host_name]'+[aaddr, adomain, @host_ip, @host_name].inspect

        values = {}
        if (not acreator) or (not acreated)
          acreator ||= PandoraCrypto.current_user_or_key(true)
          values[:creator] = acreator
          values[:created] = time_now
        end
        abase_id = sbase_id if (not abase_id) or (abase_id=='')
        akey_hash = skey_panhash if (not akey_hash) or (akey_hash=='')

        values[:base_id] = abase_id
        values[:key_hash] = akey_hash

        values[:addr_from] = @host_ip
        values[:addr_from_type] = AT_Ip4
        values[:state]        = astate
        values[:sended]       = asended
        values[:received]     = areceived
        values[:one_ip_count] = aone_ip_count+1
        values[:bad_attempts] = abad_attempts
        values[:session_key]  = @session_key
        values[:ban_time]     = aban_time
        values[:modified]     = time_now

        inaddr = params['addr']
        if inaddr and (inaddr != '')
          host, port, proto = pool.decode_node(inaddr)
          #p log_mes+'ADDR [addr, host, port, proto]='+[addr, host, port, proto].inspect
          if host and (host != '') and ((not adomain) or (adomain=='') or trusted)
            adomain = host
            port = 5577 if (not port) or (port==0)
            proto ||= ''
            atport = port if (proto != 'udp')
            auport = port if (proto != 'tcp')
            #values[:addr_type] = AT_Ip4
          end
        end

        if @node_id and (@node_id != 0) and ((not anode_id) or (@node_id != anode_id))
          filter2 = {:id=>@node_id}
          @node_id = nil
          sel = node_model.select(filter2, false, 'addr, domain, tport, uport, addr_type', nil, 1)
          if sel and (sel.size>0)
            baddr = sel[0][0]
            bdomain = sel[0][1]
            btport = sel[0][2]
            buport = sel[0][3]
            baddr_type = sel[0][4]

            aaddr = baddr if (not aaddr) or (aaddr=='')
            adomain = bdomain if (not adomain) or (adomain=='')

            values[:addr_type] ||= baddr_type
            node_model.update(nil, nil, filter2)
          end
        end

        if (not adomain) or (adomain=='')
          if (not aaddr) or (aaddr=='')
            aaddr = @host_ip
            adomain = @host_name
          else
            adomain = aaddr
          end
        end

        values[:addr] = aaddr
        values[:domain] = adomain
        values[:tport] = atport
        values[:uport] = auport

        panhash = node_model.panhash(values)
        values[:panhash] = panhash
        @node_panhash = panhash

        res = node_model.update(values, nil, filter)
      end

      # Process media segment
      # RU: Обработать медиа сегмент
      def process_media_segment(cannel, mediabuf)
        if not dialog
          @conn_mode = (@conn_mode | PandoraNet::CM_KeepHere)
          #node = PandoraNet.encode_addr(host_ip, port, proto)
          panhash = @skey[PandoraCrypto::KV_Creator]
          @dialog = PandoraGtk.show_talk_dialog(panhash, @node_panhash)
          dialog.update_state(true)
          Thread.pass
          #PandoraUtils.play_mp3('online')
        end
        recv_buf = dialog.recv_media_queue[cannel]
        if not recv_buf
          if cannel==0
            dialog.init_audio_receiver(true, true)
          else
            dialog.init_video_receiver(true, true)
          end
          Thread.pass
          recv_buf = dialog.recv_media_queue[cannel]
        end
        if dialog and recv_buf
          #p 'RECV MED ('+mediabuf.size.to_s+')'
          if cannel==0  #audio processes quickly
            buf = Gst::Buffer.new
            buf.data = mediabuf
            #buf.timestamp = Time.now.to_i * Gst::NSECOND
            appsrc = dialog.appsrcs[cannel]
            appsrc.push_buffer(buf)
            appsrc.play if (not PandoraUtils::elem_playing?(appsrc))
          else  #video puts to queue
            recv_buf.add_block_to_queue(mediabuf, $media_buf_size)
          end
        end
      end

      # Get a password for simple authority
      # RU: Взять пароль для упрощенной авторизации
      def get_simple_answer_to_node
        password = nil
        if @node_id
          node_model = PandoraUtils.get_model('Node', @recv_models)
          filter = {:id=>@node_id}
          sel = node_model.select(filter, false, 'password', nil, 1)
          if sel and sel.size>0
            row = sel[0]
            password = row[0]
          end
        end
        password
      end

      def add_hole_for_fisher(fisher)
        hole = get_hole_of_fisher(fisher)
        if not hole
          size = fishers.size
          if size>0
            i = 0
            while (i<size) and (hole==nil)
              hole = i if fishers[i]==nil
              i += 1
            end
            hole = size if (hole==nil) and (size<256)
            list_set(fishers, hole, fisher) if hole != nil
          else
            hole = 0
            list_set(fishers, hole, fisher)
          end
        end
        hole
      end

      def active?
        res = (conn_state == CS_Connected)
      end

      # Get hook for line
      # RU: Взять крючок для лески
      def init_line(line, session, far_hook=nil, hook=nil, sess_hook=nil, fo_ind=nil)
        p '--init_line  [far_hook, hook, sess_hook, self, session]='+\
          [far_hook, hook, sess_hook, self.object_id, session.object_id].inspect
        rec = nil
        # find existing rec
        if (not hook) and far_hook
          hook = @hooks.index {|rec| (rec[LHI_Far_Hook]==far_hook)}
        end
        if (not hook) and sess_hook and session
          hook = @hooks.index {|rec| (rec[LHI_Sess_Hook]==sess_hook) and (rec[LHI_Session]==session)}
        end
        if (not hook) and line and session
          hook = @hooks.index {|rec| (rec[LHI_Line]==line) and (rec[LHI_Session]==session)}
        end
        #fisher, fisher_key, fisher_baseid, fish, fish_key, fish_baseid
        # init empty rec
        if not hook
          i = 0
          while (i<@hooks.size) and (i<=255)
            break if (not @hooks[i].is_a? Array) or (@hooks[i][LHI_Session].nil?)
              #or (not @hooks[i][LHI_Session].active?)
            i += 1
          end
          if i<=255
            hook = i
            rec = @hooks[hook]
            rec.clear if rec
          end
          p 'Register hook='+hook.inspect
        end
        # fill rec
        if hook
          rec ||= @hooks[hook]
          if not rec
            rec = Array.new
            @hooks[hook] = rec
          end
          rec[LHI_Line] ||= line if line
          rec[LHI_Session] ||= session if session
          rec[LHI_Far_Hook] ||= far_hook if far_hook
          rec[LHI_Sess_Hook] ||= sess_hook if sess_hook
        end
        p '=====init_line  [session, far_hook, hook, sess_hook]='+[session.object_id, \
          far_hook, hook, sess_hook].inspect
        [hook, rec]
      end

      def rec_info(rec)
        res = [rec[LHI_Session].object_id, rec[LHI_Far_Hook], rec[LHI_Sess_Hook]]
      end

      # Take out lure by input lure for the fisher
      # RU: Взять исходящую наживку по входящей наживке для заданного рыбака
      def take_out_lure_for_fisher(fisher, in_lure)
        #out_lure = nil
        #val = [fisher, in_lure]
        p '[fisher, in_lure]='+[fisher.object_id, in_lure].inspect
        out_lure = @hooks.index {|rec| (rec[LHI_Session]==fisher) and (rec[LHI_Far_Hook]==in_lure)}
        p '-===--take_out_lure_for_fisher  in_lure, out_lure='+[in_lure, out_lure].inspect
        if not out_lure
          p 'NO OUT_LURE [fisher, self]='+[fisher.object_id, self.object_id].inspect
          p 'hooks - fisher,self: '+\
            [fisher.hooks.collect {|rec| rec_info(rec) },
            fisher.hooks.collect {|rec| rec_info(rec) }].inspect
          # need to registrate output lure
        #  i = 0
        #  while (i<@fishers.size)
        #    break if (not (@fishers[i].is_a? Array))  #or (@fishers[i][0].destroyed?))
        #    i += 1
        #  end
        #  out_lure = i if (not out_lure) and (i<=255)
        #  @fishers[out_lure] = val if out_lure
        end
        out_lure
      end

      # Check out lure by input lure and the fisher
      # RU: Проверить исходящую наживку по входящей наживке и рыбаку
      #def get_out_lure_for_fisher(fisher, in_lure)
      #  val = [fisher, in_lure]
      #  out_lure = @fishers.index(val)
      #  p '----get_out_lure_for_fisher  in_lure, out_lure='+[in_lure, out_lure].inspect
      #  out_lure
      #end

      # Get fisher for out lure
      # RU: Определить рыбака по исходящей наживке
      def get_fisher_for_out_lure(out_lure)
        fisher, in_lure = nil, nil
        val = @fishers[out_lure] if out_lure.is_a? Integer
        fisher, in_lure = val if val.is_a? Array
        p '~~~~~ get_fisher_for_out_lure  in_lure, out_lure='+[in_lure, out_lure].inspect
        [fisher, in_lure]
      end

      # Clear out lures for the fisher and input lure
      # RU: Очистить исходящие наживки для рыбака и входящей наживки
      def free_out_lure_of_fisher(fisher, in_lure)
        val = [fisher, in_lure]
        p '====//// free_out_lure_of_fisher(in_lure)='+in_lure.inspect
        while out_lure = @fishers.index(val)
          p '//// free_out_lure_of_fisher(in_lure), out_lure='+[in_lure, out_lure].inspect
          @fishers[out_lure] = nil
          if fisher #and (not fisher.destroyed?)
            if fisher.donor
              fisher.conn_state = CS_StopRead if (fisher.conn_state < CS_StopRead)
            end
            fisher.free_fish_of_in_lure(in_lure)
          end
        end
      end

      # Set a fish of the input lure
      # RU: Поставить рыбку на входящую наживку
      def set_fish_of_in_lure(in_lure, fish)
        p '+++++set_fish_of_in_lure(in_lure)='+in_lure.inspect
        @fishes[in_lure] = fish if in_lure.is_a? Integer
      end

      # Get a fish by the input lure
      # RU: Взять рыбку по входящей наживке
      def get_fish_for_in_lure(in_lure)
        fish = nil
        p '+++++get_fish_for_in_lure(in_lure)='+in_lure.inspect
        if in_lure.is_a? Integer
          fish = @hooks[in_lure][LHI_Session]
          #if fish #and fish.destroyed?
          #  fish = nil
          #  @fishes[in_lure] = nil
          #end
        end
        fish
      end

      #def get_in_lure_by_fish(fish)
      #  lure = @fishes.index(fish) if lure.is_a? Integer
      #end

      # Clear the fish on the input lure
      # RU: Очистить рыбку для входящей наживки
      def free_fish_of_in_lure(in_lure)
        if in_lure.is_a? Integer
          fish = @fishes[in_lure]
          p '//// free_fish_of_in_lure(in_lure)='+in_lure.inspect
          @fishes[in_lure] = nil
          if fish #and (not fish.destroyed?)
            if fish.donor
              fish.conn_state = CS_StopRead if (fish.conn_state < CS_StopRead)
            end
            fish.free_out_lure_of_fisher(self, in_lure)
          end
        end
      end

      # Send segment from current fisher session to fish session
      # RU: Отправляет сегмент от текущей рыбацкой сессии к сессии рыбки
      def send_segment_to_fish(hook, segment, lure=false)
        res = nil
        p '=== send_segment_to_fish(hook, segment.size)='+[hook, segment.bytesize].inspect
        if hook and segment and (segment.bytesize>1)
          rec = nil
          if lure
            hook = @hooks.index {|rec| (rec[LHI_Far_Hook]==hook) }
            p 'lure hook='+hook.inspect
          end
          if hook
            rec = @hooks[hook]
            p 'Hook send: [hook, lure]'+[hook, lure].inspect
            if rec
              sess = rec[LHI_Session]
              if sess
                if rec[LHI_Line]
                  p 'Middle hook'
                  hook = sess.hooks.index {|rec| (rec[LHI_Session]==self) and (rec[LHI_Sess_Hook]==hook) }
                  if hook
                    rec = sess.hooks[hook]
                    if rec[LHI_Far_Hook]
                      res = sess.send_queue.add_block_to_queue([EC_Bite, rec[LHI_Far_Hook], segment])
                    else
                      res = sess.send_queue.add_block_to_queue([EC_Lure, hook, segment])
                    end
                  else
                    @scmd = EC_Wait
                    @scode = EC_Wait1_NoFish
                    @scbuf = nil
                  end
                else
                  p 'Terminal hook'
                  cmd = segment[0].ord
                  code = segment[1].ord
                  data = nil
                  data = segment[2..-1] if (segment.bytesize>2)
                  res = sess.read_queue.add_block_to_queue([cmd, code, data])
                end
              else
                @scmd = EC_Wait
                @scode = EC_Wait1_NoFish
                @scbuf = nil
              end
            else
              @scmd = EC_Wait
              @scode = EC_Wait1_NoFish
              @scbuf = nil
            end
          else
            @scmd = EC_Wait
            @scode = EC_Wait1_NoFish
            @scbuf = nil
          end
        else
          @scmd = EC_Wait
          @scode = EC_Wait3_EmptySegment
          @scbuf = nil
        end
        res
      end

      # Send segment from current session to fisher session
      # RU: Отправляет сегмент от текущей сессии к сессии рыбака
      def send_segment_to_fisher(out_lure, segment)
        res = nil
        if segment and (segment.bytesize>1)
          fisher, in_lure = get_fisher_for_out_lure(out_lure)
          p '&&&&& send_segment_to_fisher: out_lure,fisher,in_lure,segsize='+[out_lure, fisher, in_lure, segment.bytesize].inspect
          if fisher #and (not fisher.destroyed?)
            if fisher.donor == self
              p 'DONOR bite'
              cmd = segment[0].ord
              code = segment[1].ord
              data = nil
              data = segment[2..-1] if (segment.bytesize>2)
              p '-->Add raw to fisher (outlure='+out_lure.to_s+') read queue: cmd,code,data='+[cmd, code, data].inspect
              res = fisher.read_queue.add_block_to_queue([cmd, code, data])
            else
              p 'RESENDER bite'
              #in_lure = fisher.get_in_lure_by_fish(self)
              res = fisher.send_queue.add_block_to_queue([EC_Bite, in_lure, segment])
            end
          else
            @scmd = EC_Wait
            @scode = EC_Wait2_NoFisher
            @scbuf = nil
          end
        else
          @scmd = EC_Wait
          @scode = EC_Wait3_EmptySegment
          @scbuf = nil
        end
        res
      end

      case rcmd
        when EC_Auth
          if @stage<=ES_Greeting
            if rcode<=ECC_Auth_Answer
              if (rcode==ECC_Auth_Hello) and ((@stage==ES_Protocol) or (@stage==ES_Sign))
                recognize_params
                if scmd != EC_Bye
                  vers = params['version']
                  if vers==0
                    addr = params['addr']
                    p log_mes+'addr='+addr.inspect
                    # need to change an ip checking
                    pool.check_callback_addr(addr, host_ip) if addr
                    @sess_mode = params['mode']
                    @notice = params['notice']
                    init_skey_or_error(true)
                  else
                    err_scmd('Protocol is not supported ('+vers.to_s+')')
                  end
                end
              elsif ((rcode==ECC_Auth_Puzzle) or (rcode==ECC_Auth_Phrase)) \
              and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
                if rdata and (rdata != '')
                  rphrase = rdata
                  params['rphrase'] = rphrase
                else
                  rphrase = params['rphrase']
                end
                p log_mes+'recived phrase len='+rphrase.bytesize.to_s
                if rphrase and (rphrase != '')
                  if rcode==ECC_Auth_Puzzle  #phrase for puzzle
                    if ((conn_mode & CM_Hunter) == 0)
                      err_scmd('Puzzle to listener is denied')
                    else
                      delay = rphrase[-2].ord
                      #p 'PUZZLE delay='+delay.to_s
                      start_time = 0
                      end_time = 0
                      start_time = Time.now.to_i if delay
                      suffix = PandoraGtk.find_sha1_solution(rphrase)
                      end_time = Time.now.to_i if delay
                      if delay
                        need_sleep = delay - (end_time - start_time) + 0.5
                        sleep(need_sleep) if need_sleep>0
                      end
                      @sbuf = suffix
                      @scode = ECC_Auth_Answer
                    end
                  else #phrase for sign
                    #p log_mes+'SIGN'
                    rphrase = OpenSSL::Digest::SHA384.digest(rphrase)
                    sign = PandoraCrypto.make_sign(@rkey, rphrase)
                    if sign
                      len = $base_id.bytesize
                      len = 255 if len>255
                      @sbuf = [len].pack('C')+$base_id[0,len]+sign
                      @scode = ECC_Auth_Sign
                      if @stage == ES_Greeting
                        @stage = ES_Exchange
                        set_max_pack_size(ES_Exchange)
                        PandoraUtils.play_mp3('online')
                      end
                    else
                      err_scmd('Cannot create sign')
                    end
                  end
                  @scmd = EC_Auth
                  #@stage = ES_Check
                else
                  err_scmd('Empty received phrase')
                end
              elsif (rcode==ECC_Auth_Answer) and (@stage==ES_Puzzle)
                interval = nil
                if $puzzle_sec_delay>0
                  start_time = params['puzzle_start']
                  cur_time = Time.now.to_i
                  interval = cur_time - start_time
                end
                if interval and (interval<$puzzle_sec_delay)
                  err_scmd('Too fast puzzle answer')
                else
                  suffix = rdata
                  sphrase = params['sphrase']
                  if PandoraCrypto.check_sha1_solution(sphrase, suffix)
                    init_skey_or_error(false)
                  else
                    err_scmd('Wrong sha1 solution')
                  end
                end
              elsif (rcode==ECC_Auth_Sign) and (@stage==ES_Sign)
                len = rdata[0].ord
                sbase_id = rdata[1, len]
                rsign = rdata[len+1..-1]
                #p log_mes+'recived rsign len='+rsign.bytesize.to_s
                @skey = PandoraCrypto.open_key(@skey, @recv_models, true)
                if @skey and @skey[PandoraCrypto::KV_Obj]
                  if PandoraCrypto.verify_sign(@skey, OpenSSL::Digest::SHA384.digest(params['sphrase']), rsign)
                    creator = PandoraCrypto.current_user_or_key(true)
                    if ((conn_mode & CM_Hunter) != 0) or (not @skey[PandoraCrypto::KV_Creator]) \
                    or (@skey[PandoraCrypto::KV_Creator] != creator)
                      # check messages if it's not session to myself
                      @send_state = (@send_state | CSF_Message)
                    end
                    trust = @skey[PandoraCrypto::KV_Trust]

                    init_and_check_node(@skey[PandoraCrypto::KV_Creator], \
                      @skey[PandoraCrypto::KV_Panhash], sbase_id)

                    if ((conn_mode & CM_Double) == 0)
                      if ((conn_mode & CM_Hunter) == 0)
                        trust = 0 if (not trust) and $trust_for_captchaed
                      elsif $trust_for_listener and (not (trust.is_a? Float))
                        trust = 0.01
                        @skey[PandoraCrypto::KV_Trust] = trust
                      end
                      p log_mes+'----trust='+trust.inspect
                      if ($captcha_length>0) and (trust.is_a? Integer) \
                      and ((conn_mode & CM_Hunter) == 0)
                        @skey[PandoraCrypto::KV_Trust] = 0
                        send_captcha
                      elsif trust.is_a? Float
                        if trust>=$low_conn_trust
                          @sess_trust = trust
                          update_node(to_key, sbase_id, trust)
                          if (@notice.is_a? Integer)
                            not_trust = (@notice & 0xFF)
                            not_dep = (@notice >> 8)
                            if not_dep >= 0
                              pool.add_notice_order(self, @to_person, @to_key, \
                                @to_base_id, not_trust, not_dep)
                            end
                          end
                          if (conn_mode & CM_Hunter) == 0
                            @stage = ES_Greeting
                            add_send_segment(EC_Auth, true, params['srckey'])
                            set_max_pack_size(ES_Sign)
                          else
                            @stage = ES_Exchange
                            set_max_pack_size(ES_Exchange)
                            #PandoraUtils.play_mp3('online')
                          end
                          @scmd = EC_Data
                          @scode = 0
                          @sbuf = nil
                        else
                          err_scmd('Key has low trust')
                        end
                      else
                        err_scmd('Key is under consideration')
                      end
                    else
                      err_scmd('Double connection is not allowed')
                    end
                  else
                    err_scmd('Wrong sign')
                  end
                else
                  err_scmd('Cannot init your key')
                end
              elsif (rcode==ECC_Auth_Simple) and (@stage==ES_Protocol)
                p 'ECC_Auth_Simple!'
                rphrase = rdata
                #p 'rphrase='+rphrase.inspect
                password = get_simple_answer_to_node
                if (password.is_a? String) and (password.bytesize>0)
                  password_hash = OpenSSL::Digest::SHA256.digest(password)
                  answer = OpenSSL::Digest::SHA256.digest(rphrase+password_hash)
                  @scmd = EC_Auth
                  @scode = ECC_Auth_Answer
                  @sbuf = answer
                  @conn_mode = (@conn_mode | PandoraNet::CM_KeepHere)
                else
                  err_scmd('Node password is not setted')
                end
              elsif (rcode==ECC_Auth_Captcha) and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
                p log_mes+'CAPTCHA!!!  ' #+params.inspect
                if ((conn_mode & CM_Hunter) == 0)
                  err_scmd('Captcha for listener is denied')
                else
                  clue_length = rdata[0].ord
                  clue_text = rdata[1,clue_length]
                  captcha_buf = rdata[clue_length+1..-1]

                  @entered_captcha = nil
                  if (not $window.cvpaned.csw)
                    $window.cvpaned.show_captcha(params['srckey'], captcha_buf, clue_text, @node) do |res|
                      @entered_captcha = res
                    end
                    while $window.cvpaned.csw and @entered_captcha.nil?
                      sleep(0.02)
                      Thread.pass
                    end
                    if @entered_captcha
                      @scmd = EC_Auth
                      @scode = ECC_Auth_Answer
                      @sbuf = entered_captcha
                    else
                      err_scmd('Captcha enter canceled')
                    end
                  else
                    err_scmd('Captcha dock is busy')
                  end
                end
              elsif (rcode==ECC_Auth_Answer) and (@stage==ES_Captcha)
                captcha = rdata
                p log_mes+'recived captcha='+captcha if captcha
                if captcha.downcase==params['captcha']
                  @stage = ES_Greeting
                  if not (@skey[PandoraCrypto::KV_Trust].is_a? Float)
                    if $trust_for_captchaed
                      @skey[PandoraCrypto::KV_Trust] = 0.01
                    else
                      @skey[PandoraCrypto::KV_Trust] = nil
                    end
                  end
                  p 'Captcha is GONE!'
                  if (conn_mode & CM_Hunter) == 0
                    add_send_segment(EC_Auth, true, params['srckey'])
                  end
                  @scmd = EC_Data
                  @scode = 0
                  @sbuf = nil
                else
                  send_captcha
                end
              else
                err_scmd('Wrong stage for rcode')
              end
            else
              err_scmd('Unknown rcode')
            end
          else
            err_scmd('Wrong stage for rcmd')
          end
        when EC_Request
          kind = rcode
          p log_mes+'EC_Request  kind='+kind.to_s+'  stage='+@stage.to_s
          panhash = nil
          if (kind==PandoraModel::PK_Key) and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
            panhash = params['mykey']
            p 'params[mykey]='+panhash
          end
          if (@stage==ES_Exchange) or (@stage==ES_Greeting) or panhash
            panhashes = nil
            if kind==0
              panhashes, len = PandoraUtils.pson_to_rubyobj(panhashes)
            else
              panhash = [kind].pack('C')+rdata if (not panhash) and rdata
              panhashes = [panhash]
            end
            p log_mes+'panhashes='+panhashes.inspect
            if panhashes.size==1
              panhash = panhashes[0]
              kind = PandoraUtils.kind_from_panhash(panhash)
              pson = PandoraModel.get_record_by_panhash(kind, panhash, false, @recv_models)
              if pson
                @scmd = EC_Record
                @scode = kind
                @sbuf = pson
                lang = @sbuf[0].ord
                values = PandoraUtils.namepson_to_hash(@sbuf[1..-1])
                p log_mes+'SEND RECORD !!! [pson, values]='+[pson, values].inspect
              else
                p log_mes+'NO RECORD panhash='+panhash.inspect
                @scmd = EC_Sync
                @scode = ECC_Sync1_NoRecord
                @sbuf = panhash
              end
            else
              rec_array = Array.new
              panhashes.each do |panhash|
                kind = PandoraUtils.kind_from_panhash(panhash)
                record = PandoraModel.get_record_by_panhash(kind, panhash, true, @recv_models)
                p log_mes+'EC_Request panhashes='+PandoraUtils.bytes_to_hex(panhash).inspect
                rec_array << record if record
              end
              if rec_array.size>0
                records = PandoraGtk.rubyobj_to_pson(rec_array)
                @scmd = EC_Record
                @scode = 0
                @sbuf = records
              else
                @scmd = EC_Sync
                @scode = ECC_Sync1_NoRecord
                @sbuf = nil
              end
            end
          else
            if panhash==nil
              err_scmd('Request ('+kind.to_s+') came on wrong stage')
            else
              err_scmd('Wrong key request')
            end
          end
        when EC_Record
          p log_mes+' EC_Record: [rcode, rdata.bytesize]='+[rcode, rdata.bytesize].inspect
          if rcode>0
            kind = rcode
            if (@stage==ES_Exchange) or ((kind==PandoraModel::PK_Key) and (@stage==ES_KeyRequest))
              lang = rdata[0].ord
              values = PandoraUtils.namepson_to_hash(rdata[1..-1])
              panhash = nil
              if @stage==ES_KeyRequest
                panhash = params['srckey']
              end
              res = PandoraModel.save_record(kind, lang, values, @recv_models, panhash)
              if res
                if @stage==ES_KeyRequest
                  @stage = ES_Protocol
                  init_skey_or_error(false)
                end
              elsif res==false
                PandoraUtils.log_message(LM_Warning, _('Record came with wrong panhash'))
              else
                PandoraUtils.log_message(LM_Warning, _('Cannot write a record')+' 1')
              end
            else
              err_scmd('Record ('+kind.to_s+') came on wrong stage')
            end
          elsif (@stage==ES_Exchange)
            records, len = PandoraUtils.pson_to_rubyobj(rdata)
            p log_mes+"!record2! recs="+records.inspect
            PandoraModel.save_records(records, @recv_models)
          else
            err_scmd('Records came on wrong stage')
          end
        when EC_Lure
          p 'EC_Lure'
          send_segment_to_fish(rcode, rdata, true)
          #sleep 2
        when EC_Bite
          p 'EC_Bite'
          send_segment_to_fish(rcode, rdata)
          #sleep 2
        when EC_Sync
          case rcode
            when ECC_Sync1_NoRecord
              p log_mes+'EC_Sync: No record: panhash='+rdata.inspect
            when ECC_Sync2_Encode
              @r_encode = true
            when ECC_Sync3_Confirm
              confirms = rdata
              p log_mes+'recv confirms='+confirms
              if confirms
                prev_kind = nil
                i = 0
                while (i<confirms.bytesize)
                  kind = confirms[i].ord
                  if (not prev_kind) or (kind != prev_kind)
                    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
                    model = PandoraUtils.get_model(panobjectclass.ider, @recv_models)
                    prev_kind = kind
                  end
                  id = confirms[i+1, 4].unpack('N')
                  p log_mes+'update confirm  kind,id='+[kind, id].inspect
                  res = model.update({:state=>2}, nil, {:id=>id})
                  if not res
                    PandoraUtils.log_message(LM_Warning, _('Cannot update record of confirm')+' kind,id='+[kind,id].inspect)
                  end
                  i += 5
                end
              end
          end
        when EC_Wait
          case rcode
            when EC_Wait1_NoFish
              PandoraUtils.log_message(LM_Error, _('Cannot find a fish'))
          end
        when EC_Bye
          errcode = ECC_Bye_Exit
          if rcode == ECC_Bye_NoAnswer
            errcode = ECC_Bye_Silent
          elsif rcode != ECC_Bye_Exit
            mes = rdata
            mes ||= ''
            i = mes.index(' (') if mes
            p '---------'
            p mes
            if i
              p mes[0, i]
              mes = _(mes[0, i])+mes[i..-1]
            end
            PandoraUtils.log_message(LM_Error, _('Error at other side')+' ErrCode='+rcode.to_s+' "'+mes+'"')
          end
          err_scmd(nil, errcode, false)
          @conn_state = CS_Stoping
        else
          if @stage>=ES_Exchange
            case rcmd
              when EC_Message, EC_Channel
                p log_mes+'EC_Message  dialog='+@dialog.inspect
                if (not @dialog) or @dialog.destroyed?
                  @conn_mode = (@conn_mode | PandoraNet::CM_KeepHere)
                  panhash = @skey[PandoraCrypto::KV_Creator]
                  @dialog = PandoraGtk.show_talk_dialog(panhash, @node_panhash)
                  Thread.pass
                  #PandoraUtils.play_mp3('online')
                end
                if rcmd==EC_Message
                  row = @rdata
                  if row.is_a? String
                    row, len = PandoraUtils.pson_to_rubyobj(row)
                    t = Time.now
                    id = nil
                    time_now = t.to_i
                    creator = @skey[PandoraCrypto::KV_Creator]
                    created = time_now
                    destination = @rkey[PandoraCrypto::KV_Creator]
                    text = nil
                    if row.is_a? Array
                      id = row[0]
                      creator = row[1]
                      created = row[2]
                      text = row[3]
                    else
                      text = row
                    end

                    values = {:destination=>destination, :text=>text, :state=>2, \
                      :creator=>creator, :created=>created, :modified=>time_now}
                    model = PandoraUtils.get_model('Message', @recv_models)
                    panhash = model.panhash(values)
                    values['panhash'] = panhash
                    res = model.update(values, nil, nil)
                    if res and (id.is_a? Integer)
                      while (@confirm_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Full) do
                        sleep(0.02)
                      end
                      @confirm_queue.add_block_to_queue([PandoraModel::PK_Message].pack('C') \
                        +[id].pack('N'))
                    end

                    talkview = nil
                    talkview = dialog.talkview if dialog
                    if talkview

                      #talkview.before_addition(t)
                      #talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
                      #talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', 'dude')
                      myname = PandoraCrypto.short_name_of_person(@rkey)
                      #dude_name = PandoraCrypto.short_name_of_person(@skey, nil, 0, myname)
                      #talkview.buffer.insert(talkview.buffer.end_iter, dude_name+':', 'dude_bold')
                      #talkview.buffer.insert(talkview.buffer.end_iter, ' '+text)
                      #talkview.after_addition
                      #talkview.show_all
                      #dialog.update_state(true)

                      dialog.add_mes_to_view(text, @skey, myname, time_now, created)

                    else
                      PandoraUtils.log_message(LM_Error, 'Пришло сообщение, но лоток чата не найден!')
                    end
                  end
                else #EC_Channel
                  case rcode
                    when ECC_Channel0_Open
                      p 'ECC_Channel0_Open'
                    when ECC_Channel2_Close
                      p 'ECC_Channel2_Close'
                  else
                    PandoraUtils.log_message(LM_Error, 'Неизвестный код управления каналом: '+rcode.to_s)
                  end
                end
              when EC_Media
                process_media_segment(rcode, rdata)
              when EC_Query
                case rcode
                  when ECC_Query_Rel
                    p log_mes+'===ECC_Query_Rel'
                    from_time = rdata[0, 4].unpack('N')[0]
                    pankinds = rdata[4..-1]
                    trust = @skey[PandoraCrypto::KV_Trust]
                    trust = -1.0 if not (trust.is_a? Float)
                    p log_mes+'from_time, pankinds, trust='+[from_time, pankinds, trust].inspect
                    pankinds = PandoraCrypto.allowed_kinds(trust, pankinds)
                    p log_mes+'pankinds='+pankinds.inspect

                    questioner = @rkey[PandoraCrypto::KV_Creator]
                    answerer = @skey[PandoraCrypto::KV_Creator]
                    key=nil
                    #ph_list = []
                    #ph_list << PandoraModel.signed_records(questioner, from_time, pankinds, \
                    #  trust, key, models)
                    ph_list = PandoraModel.public_records(questioner, trust, from_time, \
                      pankinds, @send_models)

                    #panhash_list = PandoraModel.get_panhashes_by_kinds(kind_list, from_time)
                    #panhash_list = PandoraModel.get_panhashes_by_questioner(questioner, trust, from_time)

                    p log_mes+'ph_list='+ph_list.inspect
                    ph_list = PandoraUtils.rubyobj_to_pson(ph_list) if ph_list
                    @scmd = EC_News
                    @scode = ECC_News_Panhash
                    @sbuf = ph_list
                  when ECC_Query_Record  #EC_Request
                    p log_mes+'==ECC_Query_Record'
                    two_list, len = PandoraUtils.pson_to_rubyobj(rdata)
                    need_ph_list, foll_list = two_list
                    p log_mes+'need_ph_list, foll_list='+[need_ph_list, foll_list].inspect
                    created_list = []
                    if (foll_list.is_a? Array) and (foll_list.size>0)
                      from_time = Time.now.to_i - 7*24*3600
                      kinds = (1..255).to_a - [PandoraModel::PK_Message]
                      p 'kinds='+kinds.inspect
                      foll_list.each do |panhash|
                        if panhash[0].ord==PandoraModel::PK_Person
                          cr_l = PandoraModel.created_records(panhash, from_time, kinds, @send_models)
                          p 'cr_l='+cr_l.inspect
                          created_list = created_list + cr_l if cr_l
                        end
                      end
                      created_list.flatten!
                      created_list.uniq!
                      created_list.compact!
                      created_list.sort! {|a,b| a[0]<=>b[0] }
                      p log_mes+'created_list='+created_list.inspect
                    end
                    pson_records = []
                    if (need_ph_list.is_a? Array) and (need_ph_list.size>0)
                      p log_mes+'need_ph_list='+need_ph_list.inspect
                      need_ph_list.each do |panhash|
                        kind = PandoraUtils.kind_from_panhash(panhash)
                        p log_mes+[panhash, kind].inspect
                        p res = PandoraModel.get_record_by_panhash(kind, panhash, true, \
                          @send_models)
                        pson_records << res if res
                      end
                      p log_mes+'pson_records='+pson_records.inspect
                    end
                    @scmd = EC_News
                    @scode = ECC_News_Record
                    @sbuf = PandoraUtils.rubyobj_to_pson([pson_records, created_list])
                  when ECC_Query_Fish
                    # пришла заявка на рыбалку
                    line_raw = rdata
                    line, len = PandoraUtils.pson_to_rubyobj(rdata)
                    fisher, fisher_key, fisher_baseid, fish, fish_key = line
                    p '--ECC_Query_Fish line='+line.inspect
                    if fisher_key and fisher_baseid and (fish or fish_key)
                      if (fisher_key == mykeyhash) and (fisher_baseid == pool.base_id)
                        PandoraUtils.log_message(LM_Warning, _('Somebody uses your ID'))
                      else
                        bi = line.size
                        if false and ((fish == mypersonhash) or (fish_key == mykeyhash))
                          p log_mes+'Fishing to me!='+session.to_key.inspect
                          # find existing (sleep) sessions
                          sessions = sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
                          if (not sessions.is_a? Array) or (sessions.size==0)
                            sessions = Session.new(111)
                          end
                          line[bi-2] ||= mypersonhash
                          line[bi-1] ||= mykeyhash
                          line[bi] = pool.base_id
                          p log_mes+' line='+line.inspect
                          line_raw = PandoraUtils.rubyobj_to_pson(line)
                          #session = connect_sessions_to_hook([session], self, hook)
                          my_hook, rec = init_line(line, session)
                          if my_hook
                            add_send_segment(EC_News, true, my_hook.chr + line_raw, \
                              ECC_News_Hook)
                          end
                          # sessions.each do |session|
                          #    hook, rec = session.init_line(line, self, nil, nil, my_hook)
                          #    session.add_send_segment(EC_News, true, hook.chr + line_raw, \
                          #      ECC_News_Hook)
                          #  end
                          #end
                        end
                        sessions = pool.sessions_of_person(fish)
                        sessions << pool.sessions_of_key(fish_key)
                        sessions.flatten!
                        sessions.uniq!
                        sessions.compact!
                        if sessions and (sessions.size>0)
                          p 'FOUND fishes: '+sessions.size.to_s
                          sessions.each do |session|
                            p log_mes+'--Fish session='+[session.object_id, session.to_key].inspect
                            line[bi-2] = session.to_person if (not fish)
                            line[bi-1] = session.to_key if (not fish_key)
                            line[bi] = session.to_base_id
                            p log_mes+' reg.line='+line.inspect
                            my_hook, rec = init_line(line, session)
                            #init_line(line, session, far_hook=nil, hook=nil, sess_hook=nil, fo_ind=nil)
                            if my_hook
                              sess_hook, rec = session.init_line(line, self, nil, nil, my_hook)
                              if sess_hook
                                init_line(line, session, nil, nil, my_hook, sess_hook)
                                line_raw = PandoraUtils.rubyobj_to_pson(line)
                                session.add_send_segment(EC_News, true, sess_hook.chr + line_raw, \
                                  ECC_News_Hook)
                                add_send_segment(EC_News, true, my_hook.chr + line_raw, \
                                  ECC_News_Hook)
                              end
                            end
                          end
                        else
                          p log_mes+'RESEND fish order: line='+line.inspect
                          pool.add_fish_order(self, *line, @recv_models)
                        end
                      end
                    end
                  else #запрос сорта (1-254) или всех сортов (255)
                    afrom_data = rdata
                    akind = rcode
                    if (akind == ECC_Query255_AllChanges)
                      pkind = 3 #отправка первого кайнда из серии
                    else
                      pkind = akind  #отправка только запрашиваемого
                    end
                    @scmd = EC_News
                    pnoticecount = 3
                    @scode = pkind
                    @sbuf = [pnoticecount].pack('N')
                end
              when EC_News
                case rcode
                  when ECC_News_Panhash
                    p log_mes+'==ECC_News_Panhash'
                    ph_list, len = PandoraUtils.pson_to_rubyobj(rdata)
                    p log_mes+'ph_list, len='+[ph_list, len].inspect
                    # Check non-existing records
                    need_ph_list = PandoraModel.needed_records(ph_list, @send_models)
                    p log_mes+'need_ph_list='+ need_ph_list.inspect

                    two_list = [need_ph_list]

                    questioner = @rkey[PandoraCrypto::KV_Creator] #me
                    answerer = @skey[PandoraCrypto::KV_Creator]
                    p '[questioner, answerer]='+[questioner, answerer].inspect
                    follower = nil
                    from_time = Time.now.to_i - 10*24*3600
                    pankinds = nil
                    foll_list = PandoraModel.follow_records(follower, from_time, \
                      pankinds, @send_models)
                    two_list << foll_list
                    two_list = PandoraUtils.rubyobj_to_pson(two_list)
                    @scmd = EC_Query
                    @scode = ECC_Query_Record
                    @sbuf = two_list
                  when ECC_News_Record
                    p log_mes+'==ECC_News_Record'
                    two_list, len = PandoraUtils.pson_to_rubyobj(rdata)
                    pson_records, created_list = two_list
                    p log_mes+'pson_records, created_list='+[pson_records, created_list].inspect
                    PandoraModel.save_records(pson_records, @recv_models)
                    if (created_list.is_a? Array) and (created_list.size>0)
                      need_ph_list = PandoraModel.needed_records(created_list, @send_models)
                      @scmd = EC_Query
                      @scode = ECC_Query_Record
                      foll_list = nil
                      @sbuf = PandoraUtils.rubyobj_to_pson([need_ph_list, foll_list])
                    end
                  when ECC_News_Hook
                    # по заявке найдена рыбка, ей присвоен номер
                    hook = rdata[0].ord
                    line_raw = rdata[1..-1]
                    line, len = PandoraUtils.pson_to_rubyobj(line_raw)
                    fisher, fisher_key, fisher_baseid, fish, fish_key, fish_baseid = line
                    if len>0
                      # данные корректны
                      p log_mes+'--ECC_News_Hook line='+line.inspect
                      if fish and (fish == mypersonhash) or \
                      fish_key and (fish_key == mykeyhash) or
                      fish_baseid and (fish_baseid == pool.base_id)
                        p '!!это узел-рыбка, найти/создать сессию рыбака'
                        sessions = pool.sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
                        #pool.init_session(node, tokey, nil, nil, node_id)
                        #Tsaheylu
                        if (sessions.is_a? Array) and (sessions.size>0)
                          p 'Найдены сущ. сессии'
                          sessions.each do |session|
                            p 'Подсоединяюсь к сессии: session.id='+session.object_id.to_s
                            sess_hook, rec = init_line(line, session)
                            if not pool.connect_sessions_to_hook(session, self, hook, true)
                              p 'Не могу прицепить сессию'
                            end
                          end
                        else
                          #(line, session, far_hook, hook, sess_hook)
                          sess_hook, rec = init_line(line, nil, hook)
                          session = Session.new(self, sess_hook, nil, nil, nil, \
                            0, nil, nil, nil, nil, fisher, fisher_key, fisher_baseid)
                        end
                      elsif (fisher == mypersonhash) and \
                      (fisher_key == mykeyhash) and \
                      (fisher_baseid == pool.base_id)
                        p '!!это узел-рыбак, найти/создать сессию рыбки'
                        sessions = pool.sessions_of_personkeybase(fish, fish_key, fish_baseid)
                        if (sessions.is_a? Array) and (sessions.size>0)
                          p 'Найдены сущ. сессии'
                          sessions.each do |session|
                            p 'Подсоединяюсь к сессии: session.id='+session.object_id.to_s
                            sess_hook, rec = init_line(line, session)
                            if not pool.connect_sessions_to_hook(session, self, hook, true)
                              p 'Не могу прицепить сессию'
                            end
                          end
                        else
                          #(line, session, far_hook, hook, sess_hook)
                          sess_hook, rec = init_line(line, nil, hook)
                          session = Session.new(self, sess_hook, nil, nil, nil, \
                            CM_Hunter, nil, nil, nil, nil, fish, fish_key, fish_baseid)
                        end
                      else
                        p '!!это узел-посредник, пробросить по истории заявок'
                        fish_orders = pool.find_fish_order(*line[0..4])
                        fish_orders.each do |fo|
                          sess = fo[PandoraNet::FO_Session]
                          if sess and (not sess.destroyed?)
                            sess.add_send_segment(EC_News, true, fish_lure.chr + line_raw, \
                              ECC_News_Hook)
                          end
                        end
                      end

                      #sessions = pool.sessions_of_key(fish_key)
                      #sthread = nil
                      #if (sessions.is_a? Array) and (sessions.size>0)
                      #  # найдена сессия с рыбкой
                      #  session = sessions[0]
                      #  p log_mes+' fish session='+session.inspect
                      #  #out_lure = take_out_lure_for_fisher(session, to_key)
                      #  #send_segment_to_fisher(out_lure)
                      #  session.donor = self
                      #  session.fish_lure = session.registrate_fish(fish)
                      #  sthread = session.send_thread
                      #else
                      #  sessions = pool.sessions_of_key(fisher_key)
                      #  if (sessions.is_a? Array) and (sessions.size>0)
                      #    # найдена сессия с рыбаком
                      #    session = sessions[0]
                      #    p log_mes+' fisher session='+session.inspect
                      #    session.donor = self
                      #    session.fish_lure = session.registrate_fish(fish)
                      #    sthread = session.send_thread
                      #  else
                      #    pool.add_fish_order(self, *line[0..4], @recv_models)
                      #  end
                      #end
                      #if sthread and sthread.alive? and sthread.stop?
                      #  sthread.run
                      #else
                      #  sessions = pool.find_by_order(line)
                      #  if sessions
                      #    sessions.each do |session|
                      #      session.add_send_segment(EC_News, true, rdata, ECC_News_Hook)
                      #    end
                      #  end
                      #end
                    end
                  when ECC_News_Notice
                    p log_mes+'ECC_News_Notice'
                    notic, len = PandoraUtils.pson_to_rubyobj(rdata)
                    pool.add_notice_order(self, *notic)
                  else
                    p "news more!!!!"
                    pkind = rcode
                    pnoticecount = rdata.unpack('N')
                    @scmd = EC_Sync
                    @scode = 0
                    @sbuf = ''
                end
              else
                err_scmd('Unknown command is recieved', ECC_Bye_Unknown)
                @conn_state = CS_Stoping
            end
          else
            err_scmd('Wrong stage for rcmd')
          end
      end
      #[rcmd, rcode, rdata, scmd, scode, sbuf]
    end

    # Read next data from socket, or return nil if socket is closed
    # RU: Прочитать следующие данные из сокета, или вернуть nil, если сокет закрылся
    def socket_recv(maxsize)
      recieved = ''
      begin
        #recieved = socket.recv_nonblock(maxsize)
        recieved = socket.recv(maxsize) if (socket and (not socket.closed?))
        recieved = nil if recieved==''  # socket is closed
      rescue
        recieved = ''
      #rescue Errno::EAGAIN       # no data to read
      #  recieved = ''
      #rescue #Errno::ECONNRESET, Errno::EBADF, Errno::ENOTSOCK   # other socket is closed
      #  recieved = nil
      end
      recieved
    end

    def init_and_check_node(a_to_person, a_to_key, a_to_base_id)
      @to_person = a_to_person if a_to_person
      @to_key = a_to_key if a_to_key
      @to_base_id = a_to_base_id if a_to_base_id
      if to_person and to_key and to_base_id
        key = PandoraCrypto.current_user_or_key(false)
        sessions = pool.sessions_of_personkeybase(to_person, to_key, to_base_id)
        if (sessions.is_a? Array) and (sessions.size>1) and (key != to_key)
          @conn_mode = (@conn_mode | CM_Double)
        end
      end
    end

    def inited?
      res = (@to_person != nil) and (@to_key != nil) and (@to_base_id != nil)
    end

    # Number of messages per cicle
    # RU: Число сообщений за цикл
    $mes_block_count = 5
    # Number of media blocks per cicle
    # RU: Число медиа блоков за цикл
    $media_block_count = 10
    # Number of requests per cicle
    # RU: Число запросов за цикл
    $inquire_block_count = 1
    # Number of notice orders per cicle
    # RU: Число запросов уведомлений за цикл
    $notice_block_count = 2
    # Number of fish orders per cicle
    # RU: Число запросов на рабылку за цикл
    $fish_block_count = 2
    # Reconnection period is sec
    # RU: Период переподключения в сек
    $conn_period       = 5

    # Starts three session cicle: read from queue, read from socket, send (common)
    # RU: Запускает три цикла сессии: чтение из очереди, чтение из сокета, отправка (общий)
    def initialize(asocket, ahost_name, ahost_ip, aport, aproto, \
    aconn_mode, anode_id, a_dialog, send_state_add, nodehash=nil, to_person=nil, \
    to_key=nil, to_base_id=nil)
      super()
      @conn_state  = CS_Connecting
      @stage       = ES_Begin
      @socket      = nil
      aconn_mode   ||= 0
      @conn_mode   = aconn_mode
      @read_state  = 0
      send_state_add  ||= 0
      @send_state     = send_state_add
      @fish_ind       = 0
      @notice_ind     = 0
      #@fishes         = Array.new
      @hooks          = Array.new
      @read_queue     = PandoraUtils::RoundQueue.new
      @send_queue     = PandoraUtils::RoundQueue.new
      @confirm_queue  = PandoraUtils::RoundQueue.new
      @send_models    = {}
      @recv_models    = {}
      @rkey = PandoraCrypto.current_key(false, false)

      @host_name    = ahost_name
      @host_ip      = ahost_ip
      @port         = aport
      @proto        = aproto

      p 'Session.new( [asocket, ahost_name, ahost_ip, aport, aproto, '+\
        'aconn_mode, anode_id, a_dialog, send_state_add, nodehash, to_person, '+\
        'to_key, to_base_id]'+[asocket.object_id, ahost_name, ahost_ip, aport, aproto, \
        aconn_mode, anode_id, a_dialog, send_state_add, nodehash, to_person, \
        to_key, to_base_id].inspect

      init_and_check_node(to_person, to_key, to_base_id)
      pool.add_session(self)

      # Main thread of session
      # RU: Главный поток сессии
      @send_thread = Thread.new do
        #@send_thread = Thread.current
        need_connect = true
        attempt = 0
        work_time = nil
        conn_period = $conn_period

        # Определение - сокет или донор
        if asocket.is_a? IPSocket
          # сокет
          @socket = asocket if (not asocket.closed?)
        elsif asocket.is_a? Session
          sess = asocket
          sess_hook = ahost_name
          p 'донор-сессия: '+sess.object_id.inspect
          if sess_hook
            #(line, session, far_hook, hook, sess_hook)
            fhook, rec = init_line(nil, sess, nil, nil, sess_hook)
            sess_hook2, rec2 = sess.init_line(nil, self, nil, sess_hook, fhook)
            if sess_hook2
              #add_hook(asocket, ahost_name)
              if (@conn_mode & CM_Hunter)>0
                p 'крючок рыбака '+sess_hook.inspect
                PandoraUtils.log_message(LM_Info, _('Active fisher')+': [sess, hook]='+\
                  [sess.object_id, sess_hook].inspect)
              else
                p 'крючок рыбки '+sess_hook.inspect
                PandoraUtils.log_message(LM_Info, _('Passive fisher')+': [sess, hook]='+\
                  [sess.object_id, sess_hook].inspect)
              end
            else
              p 'Не удалось зарегать рыб.сессию'
            end
          end
        end

        # Main cicle of session
        # RU: Главный цикл сессии
        while need_connect do
          #@conn_mode = (@conn_mode & (~CM_Hunter))

          # is there connection?
          # есть ли подключение?   or (@socket.closed?)
          if (not @socket) and (not active_hook)
            # нет подключения ни через сокет, ни через донора
            # значит, нужно подключаться самому
            p 'нет подключения ни через сокет, ни через донора'
            host = ahost_name
            host = ahost_ip if ((not host) or (host == ''))

            port = aport
            port ||= 5577
            port = port.to_i

            asocket = nil
            if (host.is_a? String) and (host.size>0) and port
              @conn_mode = (@conn_mode | CM_Hunter)
              server = host+':'+port.to_s

              # Try to connect
              @conn_thread = Thread.new do
                begin
                  asocket = TCPSocket.open(host, port)
                  @socket = asocket
                rescue
                  asocket = nil
                  @socket = asocket
                  if (not work_time) or ((Time.now.to_i - work_time.to_i)>15)
                    PandoraUtils.log_message(LM_Warning, _('Fail connect to')+': '+server)
                    conn_period = 15
                  else
                    sleep(conn_period-1)
                  end
                end
                @conn_thread = nil
                if @send_thread and @send_thread.alive? and @send_thread.stop?
                  @send_thread.run
                end
              end

              # Sleep until connect
              sleep(conn_period)
              if @conn_thread
                @conn_thread.exit if @conn_thread.alive?
                @conn_thread = nil
                if not @socket
                  PandoraUtils.log_message(LM_Trace, _('Timeout connect to')+': '+server)
                end
              end
            else
              asocket = false
            end

            if not @socket
              # Add fish order and wait donor
              if to_person or to_key
                mykeyhash = PandoraCrypto.current_user_or_key(false)
                pool.add_fish_order(self, mypersonhash, mykeyhash, pool.base_id, \
                  to_person, to_key, @recv_models)
                while (not @socket) and (not active_hook)
                  p 'Thread.stop [to_person, to_key]='+[to_person, to_key].inspect
                  Thread.stop
                end
              else
                @socket = false
                PandoraUtils.log_message(LM_Trace, _('Session breaks bz of no person and key panhashes'))
              end
            end

          end

          work_time = Time.now

          p '==reconn: '+[@socket.object_id].inspect
          sleep 0.5


          if @socket
            if ((conn_mode & CM_Hunter) == 0)
              PandoraUtils.log_message(LM_Info, _('Hunter connects')+': '+socket.peeraddr.inspect)
            else
              PandoraUtils.log_message(LM_Info, _('Connected to listener')+': '+server)
            end
            @host_name    = ahost_name
            @host_ip      = ahost_ip
            @port         = aport
            @proto        = aproto
            @node         = pool.encode_addr(@host_ip, @port, @proto)
            @node_id      = anode_id
          end

          # есть ли подключение?
          ahook = active_hook
          if (@socket and (not @socket.closed?)) or ahook
            #@conn_mode = (@conn_mode | (CM_Hunter & aconn_mode)) if @ahook

            p 'есть подключение [@socket, ahook, @conn_mode]' + [@socket.object_id, ahook, @conn_mode].inspect
            @stage          = ES_Protocol  #ES_IpCheck
            #@conn_mode      = aconn_mode
            @conn_state     = CS_Connected
            @read_state     = 0
            @send_state     = send_state_add
            @sindex         = 0
            @params         = {}
            @media_send     = false
            @node_panhash   = nil
            #@base_id        = nil
            if @socket
              set_keepalive(@socket)
            end

            if a_dialog and (not a_dialog.destroyed?)
              @dialog = a_dialog
              dialog.set_session(self, true)
              #dialog.online_button.active = (socket and (not socket.closed?))
              if self.dialog and (not self.dialog.destroyed?) and self.dialog.online_button \
              and ((self.socket and (not self.socket.closed?)) or self.active_hook)
                self.dialog.online_button.safe_set_active(true)
                self.dialog.online_button.inconsistent = false
              end
            end

            #Thread.critical = true
            #PandoraGtk.add_session(self)
            #Thread.critical = false

            @max_pack_size = MPS_Proto
            @log_mes = 'LIS: '
            if (@conn_mode & CM_Hunter)>0
              @log_mes = 'HUN: '
              @max_pack_size = MPS_Captcha
              add_send_segment(EC_Auth, true, to_key)
            end

            # Read from socket cicle
            # RU: Цикл чтения из сокета
            if @socket
              @socket_thread = Thread.new do
                readmode = RM_Comm
                waitlen = CommSize
                rdatasize = 0
                fullcrc32 = nil
                rdatasize = nil
                ok1comm = nil

                rkcmd = EC_Data
                rkcode = 0
                rkbuf = AsciiString.new
                rkdata = AsciiString.new
                rkindex = 0
                serrcode = nil
                serrbuf = nil

                p log_mes+"Цикл ЧТЕНИЯ сокета начало"
                # Цикл обработки команд и блоков данных
                while (@conn_state != CS_Disconnected) and (@conn_state != CS_StopRead) \
                and (not socket.closed?)
                  recieved = socket_recv(@max_pack_size)
                  if (not recieved) or (recieved == '')
                    @conn_state = CS_Stoping
                  end
                  #p log_mes+"recieved=["+recieved+']  '+socket.closed?.to_s+'  sok='+socket.inspect
                  #p log_mes+"recieved.size, waitlen="+[recieved.bytesize, waitlen].inspect if recieved
                  rkbuf << AsciiString.new(recieved)
                  processedlen = 0
                  while (@conn_state != CS_Disconnected) and (@conn_state != CS_StopRead) \
                  and (@conn_state != CS_Stoping) and (not socket.closed?) and (rkbuf.bytesize>=waitlen)
                    p log_mes+'readmode, rkbuf.len, waitlen='+[readmode, rkbuf.size, waitlen].inspect
                    processedlen = waitlen

                    # Определимся с данными по режиму чтения
                    case readmode
                      when RM_Comm
                        fullcrc32 = nil
                        rdatasize = nil
                        comm = rkbuf[0, processedlen]
                        rkindex, rkcmd, rkcode, rsegsign, errcode = unpack_comm(comm)
                        if errcode == 0
                          if (rkcmd <= EC_Sync) or (rkcmd >= EC_Wait)
                            ok1comm ||= true
                            #p log_mes+' RM_Comm: '+[rkindex, rkcmd, rkcode, rsegsign].inspect
                            if rsegsign == Session::LONG_SEG_SIGN
                              readmode = RM_CommExt
                              waitlen = CommExtSize
                            elsif rsegsign > 0
                              readmode = RM_SegmentS
                              waitlen, rdatasize = rsegsign, rsegsign
                              rdatasize -=4 if (rkcmd != EC_Media)
                            end
                          else
                            serrbuf, serrcode = 'Bad command', ECC_Bye_BadComm
                          end
                        elsif errcode == 1
                          serrbuf, serrcode = 'Wrong CRC of recieved command', ECC_Bye_BadCommCRC
                        elsif errcode == 2
                          serrbuf, serrcode = 'Wrong length of recieved command', ECC_Bye_BadCommLen
                        else
                          serrbuf, serrcode = 'Wrong recieved command', ECC_Bye_Unknown
                        end
                      when RM_CommExt
                        comm = rkbuf[0, processedlen]
                        rdatasize, fullcrc32, rsegsize = unpack_comm_ext(comm)
                        #p log_mes+' RM_CommExt: '+[rdatasize, fullcrc32, rsegsize].inspect
                        fullcrc32 = nil if (rkcmd == EC_Media)
                        readmode = RM_Segment1
                        waitlen = rsegsize
                      when RM_SegLenN
                        comm = rkbuf[0, processedlen]
                        rkindex, rsegindex, rsegsize = comm.unpack('nNn')
                        #p log_mes+' RM_SegLenN: '+[rkindex, rsegindex, rsegsize].inspect
                        readmode = RM_SegmentN
                        waitlen = rsegsize
                      else  #RM_SegmentS, RM_Segment1, RM_SegmentN
                        #p log_mes+' RM_SegLen?['+readmode.to_s+']  rkbuf.size=['+rkbuf.bytesize.to_s+']'
                        if rkcmd == EC_Media
                          rkdata << rkbuf[0, processedlen]
                        else
                          rseg = AsciiString.new(rkbuf[0, processedlen-4])
                          #p log_mes+'rseg=['+rseg+']'
                          rsegcrc32str = rkbuf[processedlen-4, 4]
                          rsegcrc32 = rsegcrc32str.unpack('N')[0]
                          fsegcrc32 = Zlib.crc32(rseg)
                          if fsegcrc32 == rsegcrc32
                            rkdata << rseg
                          else
                            serrbuf, serrcode = 'Wrong CRC of received segment', ECC_Bye_BadSegCRC
                          end
                        end
                        #p log_mes+'RM_Segment?: data['+rkdata+']'+rkdata.size.to_s+'/'+rdatasize.to_s
                        #p log_mes+'RM_Segment?: datasize='+rdatasize.to_s
                        if rkdata.bytesize == rdatasize
                          readmode = RM_Comm
                          waitlen = CommSize
                          if fullcrc32 and (fullcrc32 != Zlib.crc32(rkdata))
                            serrbuf, serrcode = 'Wrong CRC of composed data', ECC_Bye_BadDataCRC
                          end
                        elsif rkdata.bytesize < rdatasize
                          if (readmode==RM_Segment1) or (readmode==RM_SegmentN)
                            readmode = RM_SegLenN
                            waitlen = SegNAttrSize    #index + segindex + rseglen (2+4+2)
                          else
                            serrbuf, serrcode = 'Too short received data ('+rkdata.bytesize.to_s+'>'  \
                              +rdatasize.to_s+')', ECC_Bye_DataTooShort
                          end
                        else
                          serrbuf, serrcode = 'Too long received data ('+rkdata.bytesize.to_s+'>' \
                            +rdatasize.to_s+')', ECC_Bye_DataTooLong
                        end
                    end
                    # Очистим буфер от определившихся данных
                    rkbuf.slice!(0, processedlen)
                    if serrbuf  #there was error
                      if ok1comm
                        res = @send_queue.add_block_to_queue([EC_Bye, serrcode, serrbuf])
                        if not res
                          PandoraUtils.log_message(LM_Error, _('Cannot add error segment to send queue'))
                        end
                      end
                      @conn_state = CS_Stoping
                    elsif (readmode == RM_Comm)
                      #p log_mes+'-- from socket to read queue: [rkcmd, rcode, rkdata.size]='+[rkcmd, rkcode, rkdata.size].inspect
                      if @r_encode and rkdata and (rkdata.bytesize>0)
                        #@rkdata = PandoraGtk.recrypt(@rkey, @rkdata, false, true)
                        #@rkdata = Base64.strict_decode64(@rkdata)
                        #p log_mes+'::: decode rkdata.size='+rkdata.size.to_s
                      end

                      if rkcmd==EC_Media
                        process_media_segment(rkcode, rkdata)
                      else
                        while (@read_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Full) \
                        and (@conn_state == CS_Connected)
                          sleep(0.03)
                          Thread.pass
                        end
                        res = @read_queue.add_block_to_queue([rkcmd, rkcode, rkdata])
                        if not res
                          PandoraUtils.log_message(LM_Error, _('Cannot add socket segment to read queue'))
                          @conn_state = CS_Stoping
                        end
                      end
                      rkdata = AsciiString.new
                    end

                    if not ok1comm
                      PandoraUtils.log_message(LM_Error, 'Bad first command')
                      @conn_state = CS_Stoping
                    end
                  end
                  if (@conn_state == CS_Stoping)
                    @conn_state = CS_StopRead
                  end
                  #Thread.pass
                end
                @conn_state = CS_StopRead if (not @conn_state) or (@conn_state < CS_StopRead)
                p log_mes+"Цикл ЧТЕНИЯ сокета конец!"
                @socket_thread = nil
              end
            end

            # Read from buffer cicle
            # RU: Цикл чтения из буфера
            @read_thread = Thread.new do
              @rcmd = EC_Data
              @rdata = AsciiString.new
              @scmd = EC_Sync
              @sbuf = ''

              p log_mes+"Цикл ЧТЕНИЯ начало"
              # Цикл обработки команд и блоков данных
              while (@conn_state != CS_Disconnected) and (@conn_state != CS_StopRead)
                read_segment = @read_queue.get_block_from_queue
                if (@conn_state != CS_Disconnected) and read_segment
                  @rcmd, @rcode, @rdata = read_segment
                  len = 0
                  len = rdata.size if rdata
                  #p log_mes+'--**** before accept: [rcmd, rcode, rdata]='+[rcmd, rcode, len].inspect
                  #rcmd, rcode, rdata, scmd, scode, sbuf = \
                  accept_segment #(rcmd, rcode, rdata, scmd, scode, sbuf)
                  len = 0
                  len = @sbuf.size if @sbuf
                  #p log_mes+'--**** after accept: [scmd, scode, sbuf]='+[@scmd, @scode, len].inspect

                  if @scmd != EC_Data
                    while (@send_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Full) \
                    and (@conn_state == CS_Connected)
                      sleep(0.03)
                      Thread.pass
                    end
                    res = @send_queue.add_block_to_queue([@scmd, @scode, @sbuf])
                    @scmd = EC_Data
                    if not res
                      PandoraUtils.log_message(LM_Error, 'Error while adding segment to queue')
                      @conn_state = CS_Stoping
                    end
                  end
                else  #no segment in read queue
                  #p 'aaaaaaaaaaaaa'
                  sleep(0.01)
                  #Thread.pass
                end
                if (@conn_state == CS_Stoping)
                  @conn_state = CS_StopRead
                end
              end
              @conn_state = CS_StopRead if (not @conn_state) or (@conn_state < CS_StopRead)
              p log_mes+"Цикл ЧТЕНИЯ конец!"
              #socket.close if not socket.closed?
              #@conn_state = CS_Disconnected
              @read_thread = nil
            end

            # Send cicle
            # RU: Цикл отправки
            questioner_step = QS_ResetMessage
            message_model = PandoraUtils.get_model('Message', @send_models)
            p log_mes+'ЦИКЛ ОТПРАВКИ начало: @conn_state='+@conn_state.inspect

            while (@conn_state != CS_Disconnected)
              #p '@conn_state='+@conn_state.inspect

              fast_data = false

              # формирование подтверждений
              if (@conn_state != CS_Disconnected)
                ssbuf = ''
                confirm_rec = @confirm_queue.get_block_from_queue
                while (@conn_state != CS_Disconnected) and confirm_rec
                  p log_mes+'send  confirm_rec='+confirm_rec
                  ssbuf << confirm_rec
                  confirm_rec = @confirm_queue.get_block_from_queue
                  if (not confirm_rec) or (ssbuf.bytesize+5>MaxSegSize)
                    add_send_segment(EC_Sync, true, ssbuf, ECC_Sync3_Confirm)
                    ssbuf = ''
                  end
                end
              end

              # отправка сформированных сегментов и их удаление
              if (@conn_state != CS_Disconnected)
                send_segment = @send_queue.get_block_from_queue
                while (@conn_state != CS_Disconnected) and send_segment
                  #p log_mes+' send_segment='+send_segment.inspect
                  sscmd, sscode, ssbuf = send_segment
                  if ssbuf and (ssbuf.bytesize>0) and @s_encode
                    #ssbuf = PandoraGtk.recrypt(@skey, ssbuf, true, false)
                    #ssbuf = Base64.strict_encode64(@sbuf)
                  end
                  #p log_mes+'MAIN SEND: '+[@sindex, sscmd, sscode, ssbuf].inspect
                  if (sscmd != EC_Bye) or (sscode != ECC_Bye_Silent)
                    if not send_comm_and_data(@sindex, sscmd, sscode, ssbuf)
                      @conn_state = CS_Disconnected
                      p log_mes+'err send comm and buf'
                    end
                  else
                    p 'SILENT!!!!!!!!'
                  end
                  if (sscmd==EC_Sync) and (sscode==ECC_Sync2_Encode)
                    @s_encode = true
                  end
                  if (sscmd==EC_Bye)
                    p log_mes+'SEND BYE!!!!!!!!!!!!!!!'
                    send_segment = nil
                    #if not socket.closed?
                    #  socket.close_write
                    #  socket.close
                    #end
                    @conn_state = CS_Disconnected
                  else
                    if (sscmd==EC_Media)
                      fast_data = true
                    end
                    send_segment = @send_queue.get_block_from_queue
                  end
                end
              end

              # выполнить несколько заданий почемучки по его шагам
              processed = 0
              while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
              and (processed<$inquire_block_count) \
              and (questioner_step<QS_Finished)
                case questioner_step
                  when QS_ResetMessage
                    # если что-то отправлено, но не получено, то повторить
                    mypanhash = PandoraCrypto.current_user_or_key(true)
                    receiver = @skey[PandoraCrypto::KV_Creator]
                    if (receiver.is_a? String) and (receiver.bytesize>0) \
                    and (((conn_mode & CM_Hunter) != 0) or (mypanhash != receiver))
                      filter = {'destination'=>receiver, 'state'=>1}
                      message_model.update({:state=>0}, nil, filter)
                    end
                    questioner_step += 1
                  when QS_CreatorCheck
                    # если собеседник неизвестен, запросить анкету
                    creator = @skey[PandoraCrypto::KV_Creator]
                    kind = PandoraUtils.kind_from_panhash(creator)
                    res = PandoraModel.get_record_by_panhash(kind, creator, nil, @send_models, 'id')
                    p log_mes+'Whyer: CreatorCheck  creator='+creator.inspect
                    if not res
                      p log_mes+'Whyer: CreatorCheck  Request!'
                      set_request(creator, true)
                    end
                    questioner_step += 1
                  when QS_NewsQuery
                    # запросить список новых панхэшей
                    pankinds = 1.chr + 11.chr
                    from_time = Time.now.to_i - 10*24*3600
                    #questioner = @rkey[PandoraCrypto::KV_Creator]
                    #answerer = @skey[PandoraCrypto::KV_Creator]
                    #trust=nil
                    #key=nil
                    #models=nil
                    #ph_list = []
                    #ph_list << PandoraModel.signed_records(questioner, from_time, pankinds, \
                    #  trust, key, models)
                    #ph_list << PandoraModel.public_records(questioner, trust, from_time, \
                    #  pankinds, models)
                    set_relations_query(pankinds, from_time, true)
                    questioner_step += 1
                  else
                    questioner_step = QS_Finished
                end
                processed += 1
              end

              # обработка принятых сообщений, их удаление

              # разгрузка принятых буферов в gstreamer
              processed = 0
              cannel = 0
              while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
              and (processed<$media_block_count) \
              and dialog and (not dialog.destroyed?) and (cannel<dialog.recv_media_queue.size) \
              and (questioner_step>QS_ResetMessage)
                if dialog.recv_media_pipeline[cannel] and dialog.appsrcs[cannel]
                #and (dialog.recv_media_pipeline[cannel].get_state == Gst::STATE_PLAYING)
                  processed += 1
                  rc_queue = dialog.recv_media_queue[cannel]
                  recv_media_chunk = rc_queue.get_block_from_queue($media_buf_size) if rc_queue
                  if recv_media_chunk #and (recv_media_chunk.size>0)
                    fast_data = true
                    #p 'LOAD MED BUF size='+recv_media_chunk.size.to_s
                    buf = Gst::Buffer.new
                    buf.data = recv_media_chunk
                    buf.timestamp = Time.now.to_i * Gst::NSECOND
                    dialog.appsrcs[cannel].push_buffer(buf)
                    #recv_media_chunk = PandoraUtils.get_block_from_queue(dialog.recv_media_queue[cannel], $media_buf_size)
                  else
                    cannel += 1
                  end
                else
                  cannel += 1
                end
              end

              # обработка принятых запросов, их удаление

              # пакетирование текстовых сообщений
              processed = 0
              #p log_mes+'----------send_state1='+send_state.inspect
              #sleep 1
              if (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and (((send_state & CSF_Message)>0) or ((send_state & CSF_Messaging)>0))
                fast_data = true
                @send_state = (send_state & (~CSF_Message))
                receiver = @skey[PandoraCrypto::KV_Creator]
                if @skey and receiver
                  filter = {'destination'=>receiver, 'state'=>0}
                  fields = 'id, creator, created, text'
                  sel = message_model.select(filter, false, fields, 'created', $mes_block_count)
                  if sel and (sel.size>0)
                    @send_state = (send_state | CSF_Messaging)
                    i = 0
                    while sel and (i<sel.size) and (processed<$mes_block_count) \
                    and (@conn_state == CS_Connected) \
                    and (@send_queue.single_read_state != PandoraUtils::RoundQueue::SQS_Full)
                      processed += 1
                      row = sel[i]
                      if add_send_segment(EC_Message, true, row)
                        id = row[0]
                        res = message_model.update({:state=>1}, nil, {:id=>id})
                        if not res
                          PandoraUtils.log_message(LM_Error, _('Updating state of sent message')+' id='+id.to_s)
                        end
                      else
                        PandoraUtils.log_message(LM_Error, _('Adding message to send queue')+' id='+id.to_s)
                      end
                      i += 1
                      #if (i>=sel.size) and (processed<$mes_block_count) and (@conn_state == CS_Connected)
                      #  sel = message_model.select(filter, false, fields, 'created', $mes_block_count)
                      #  if sel and (sel.size>0)
                      #    i = 0
                      #  else
                      #    @send_state = (send_state & (~CSF_Messaging))
                      #  end
                      #end
                    end
                  else
                    @send_state = (send_state & (~CSF_Messaging))
                  end
                else
                  @send_state = (send_state & (~CSF_Messaging))
                end
              end

              # пакетирование медиа буферов
              if ($send_media_queues.size>0) and $send_media_rooms \
              and (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and ((send_state & CSF_Message) == 0) and dialog and (not dialog.destroyed?) and dialog.room_id \
              and ((dialog.vid_button and (not dialog.vid_button.destroyed?) and dialog.vid_button.active?) \
              or (dialog.snd_button and (not dialog.snd_button.destroyed?) and dialog.snd_button.active?))
                fast_data = true
                #p 'packbuf '+cannel.to_s
                pointer_ind = PandoraGtk.get_send_ptrind_by_room(dialog.room_id)
                processed = 0
                cannel = 0
                while (@conn_state == CS_Connected) \
                and ((send_state & CSF_Message) == 0) and (processed<$media_block_count) \
                and (cannel<$send_media_queues.size) \
                and dialog and (not dialog.destroyed?) \
                and ((dialog.vid_button and (not dialog.vid_button.destroyed?) and dialog.vid_button.active?) \
                or (dialog.snd_button and (not dialog.snd_button.destroyed?) and dialog.snd_button.active?))
                  processed += 1
                  sc_queue = $send_media_queues[cannel]
                  send_media_chunk = nil
                  #p log_mes+'[cannel, pointer_ind]='+[cannel, pointer_ind].inspect
                  send_media_chunk = sc_queue.get_block_from_queue($media_buf_size, pointer_ind) if sc_queue and pointer_ind
                  if send_media_chunk
                    #p log_mes+'[cannel, pointer_ind, chunk.size]='+[cannel, pointer_ind, send_media_chunk.size].inspect
                    mscmd = EC_Media
                    mscode = cannel
                    msbuf = send_media_chunk
                    if not send_comm_and_data(sindex, mscmd, mscode, msbuf)
                      @conn_state = CS_Disconnected
                      p log_mes+' err send media'
                    end
                  else
                    cannel += 1
                  end
                end
              end

              if (@sess_mode.is_a? Integer) and ((@sess_mode & SM_GetNotice)>0)
                # проверка новых уведомлений
                processed = 0
                while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
                and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
                and (processed<$notice_block_count) \
                and (@notice_ind <= pool.notice_ind)
                  notice_order = pool.notice_list[@notice_ind]
                  if notice_order
                    p log_mes+'======notice_order='+notice_order[NO_Person..NO_Notice_depth].inspect
                    p log_mes+'======[to_person, to_key, @sess_trust, notice_order[NO_Notice_trust], notice_order[NO_Session], self]='+[@to_person, @to_key, @sess_trust, notice_order[NO_Notice_trust], notice_order[NO_Session].object_id, self.object_id].inspect
                    if notice_order and (notice_order[NO_Session] != self) \
                    and @sess_trust and (@sess_trust >= PandoraModel.transform_trust(notice_order[NO_Notice_trust], false)) \
                    and ((@to_key and (notice_order[NO_Key] != @to_key)) \
                    or (@to_person and (notice_order[NO_Person] != @to_person)) \
                    or (@to_base_id and (notice_order[NO_Baseid] != @to_base_id)))
                      p log_mes+'=====New notice order: '+notice_order[NO_Person..NO_Notice_depth].inspect
                      #mykeyhash = PandoraCrypto.current_user_or_key(false)
                      notic = PandoraUtils.rubyobj_to_pson(notice_order[NO_Person..NO_Notice_depth])
                      add_send_segment(EC_News, true, notic, ECC_News_Notice)
                    end
                    processed += 1
                  end
                  @notice_ind += 1
                end
              end

              # проверка новых заявок на рыбалку
              processed = 0
              while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
              and (processed<$fish_block_count) \
              and (@fish_ind <= pool.fish_ind)
                fish_order = pool.fish_orders[@fish_ind]
                if fish_order
                  p log_mes+'fish_order='+fish_order[FO_Fisher..FO_Fish_key].inspect
                  p log_mes+'[to_person, to_key]='+[@to_person, @to_key].inspect
                  if fish_order and (fish_order[FO_Session] != self) \
                  and ((@to_person and (fish_order[FO_Fish] != @to_person)) \
                  or (@to_key and (fish_order[FO_Fish_key] != @to_key)))
                    p log_mes+'New fish order: '+fish_order[FO_Fisher..FO_Fish_key].inspect
                    #mykeyhash = PandoraCrypto.current_user_or_key(false)
                    PandoraUtils.log_message(LM_Trace, _('Fishing to')+': ' \
                      +PandoraUtils.bytes_to_hex(fish_order[FO_Fish])+' '+_('via')+' '+@host_ip+':'+@port.to_s)
                    line = PandoraUtils.rubyobj_to_pson(fish_order[FO_Fisher..FO_Fish_key])
                    add_send_segment(EC_Query, true, line, ECC_Query_Fish)
                  end
                  processed += 1
                end
                @fish_ind += 1
              end

              #p '---@conn_state='+@conn_state.inspect
              #sleep 0.5

              if (socket and socket.closed?) or (@conn_state == CS_StopRead) \
              and (@confirm_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Empty)
                @conn_state = CS_Disconnected
              elsif (not fast_data)
                sleep(0.02)
              #elsif conn_state == CS_Stoping
              #  add_send_segment(EC_Bye, true)
              end
              Thread.pass
            end

            p log_mes+"Цикл ОТПРАВКИ конец!!!   @conn_state="+@conn_state.inspect

            #Thread.critical = true
            #Thread.critical = false
            #p log_mes+'check close'
            if socket and (not socket.closed?)
              p log_mes+'before close_write'
              #socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
              #socket.flush
              #socket.print('\000')
              socket.close_write
              p log_mes+'before close'
              sleep(0.05)
              socket.close
              p log_mes+'closed!'
            end
            if socket
              if ((conn_mode & CM_Hunter) == 0)
                PandoraUtils.log_message(LM_Info, _('Hunter disconnects')+': '+@host_ip)
              else
                PandoraUtils.log_message(LM_Info, _('Disconnected from listener')+': '+@host_ip)
              end
            end
            @socket_thread.exit if @socket_thread
            @read_thread.exit if @read_thread
            while @hooks.size>0
              p 'DONORs free!!!!'
              i = @hooks.size-1 #active_hook
              rec = @hooks[i]
              rec[LHI_Session].del_sess_hooks(self) if rec.is_a? Array and rec[LHI_Session] \
                and rec[LHI_Session].active?
              @hooks.delete_at(i)
              #if rec[LHI_Session] and rec[LHI_Session].active?
              #  rec[LHI_Session].send_comm_and_data(rec[LHI_Session].sindex, EC_Bye, ECC_Bye_NoAnswer, nil)
              #end
              #if fisher_lure
              #  p 'free_out_lure fisher_lure='+fisher_lure.inspect
              #  donor.free_out_lure_of_fisher(self, fisher_lure)
              #else
              #  p 'free_fish fish_lure='+fish_lure.inspect
              #  donor.free_fish_of_in_lure(fish_lure)
              #end
            end
            #@fishes.each_index do |i|
            #  free_fish_of_in_lure(i)
            #end
            #fishers.each do |val|
            #  fisher = nil
            #  in_lure = nil
            #  fisher, in_lure = val if val.is_a? Array
            #  fisher.free_fish_of_in_lure(in_lure) if (fisher and in_lure) #and (not fisher.destroyed?)
            #  #fisher.free_out_lure_of_fisher(self, i) if fish #and (not fish.destroyed?)
            #end
          else
            p 'НЕТ ПОДКЛЮЧЕНИЯ'
          end

          need_connect = ((@conn_mode & CM_KeepHere) != 0) and (not (@socket.is_a? FalseClass))
          p 'NEED??? [need_connect, @conn_mode, @socket]='+[need_connect, @conn_mode, @socket].inspect

          if need_connect and (not @socket) and work_time and ((Time.now.to_i - work_time.to_i)<15)
            p 'sleep!'
            sleep(3.1+0.5*rand)
          end

          @conn_state = CS_Disconnected
          @socket = nil

          attempt += 1
        end
        pool.del_session(self)
        if dialog and (not dialog.destroyed?) #and (not dialog.online_button.destroyed?)
          dialog.set_session(self, false)
          #dialog.online_button.active = false
        else
          @dialog = nil
        end
        @send_thread = nil
        PandoraUtils.play_mp3('offline')
      end
      #??
    end

  end

  # Take next client socket from listener, or return nil
  # RU: Взять следующий сокет клиента со слушателя, или вернуть nil
  def self.get_listener_client_or_nil(server)
    client = nil
    begin
      client = server.accept_nonblock
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK
      client = nil
    end
    client
  end

  # Get notice parameters
  # RU: Взять параметры уведомления
  def self.get_notice_params
    $get_notice           = PandoraUtils.get_param('get_notice')
    $notice_trust         = PandoraUtils.get_param('notice_trust')
    $notice_depth         = PandoraUtils.get_param('notice_depth')
    $max_notice_depth     = PandoraUtils.get_param('max_notice_depth')
    $notice_trust        ||= 12
    $notice_depth        ||= 2
    $max_notice_depth    ||= 5
  end

  # Get exchange params
  # RU: Взять параметры обмена
  def self.get_exchange_params
    $callback_addr       = PandoraUtils.get_param('callback_addr')
    $puzzle_bit_length   = PandoraUtils.get_param('puzzle_bit_length')
    $puzzle_sec_delay    = PandoraUtils.get_param('puzzle_sec_delay')
    $captcha_length      = PandoraUtils.get_param('captcha_length')
    $captcha_attempts    = PandoraUtils.get_param('captcha_attempts')
    $trust_captchaed     = PandoraUtils.get_param('trust_captchaed')
    $trust_listener      = PandoraUtils.get_param('trust_listener')
    $low_conn_trust      = PandoraUtils.get_param('low_conn_trust')
    $low_conn_trust     ||= 0.0
    get_notice_params
  end

  $tcp_listen_thread = nil
  $udp_listen_thread = nil

  UdpHello = 'pandora:hello:'

  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.start_or_stop_listen
    PandoraNet.get_exchange_params
    if $tcp_listen_thread or $udp_listen_thread
      # Need to stop
      if $tcp_listen_thread
        #server = $tcp_listen_thread[:tcp_server]
        #server.close if server and (not server.closed?)
        $tcp_listen_thread[:listen_tcp] = false
        sleep 0.08
        if $tcp_listen_thread
          tcp_lis_th0 = $tcp_listen_thread
          GLib::Timeout.add(2000) do
            if tcp_lis_th0 == $tcp_listen_thread
              $tcp_listen_thread.exit if $tcp_listen_thread and $tcp_listen_thread.alive?
              $tcp_listen_thread = nil
              $window.correct_lis_btn_state
            end
            false
          end
        end
      end
      if $udp_listen_thread
        $udp_listen_thread[:listen_udp] = false
        server = $udp_listen_thread[:udp_server]
        if server
          server.close_read
          server.close_write
        end
        sleep 0.03
        if $udp_listen_thread
          udp_lis_th0 = $udp_listen_thread
          GLib::Timeout.add(2000) do
            if udp_lis_th0 == $udp_listen_thread
              $udp_listen_thread.exit if $udp_listen_thread and $udp_listen_thread.alive?
              $udp_listen_thread = nil
              $window.correct_lis_btn_state
            end
            false
          end
        end
      end
      $window.correct_lis_btn_state
    else
      # Need to start
      $window.show_notice(false)
      user = PandoraCrypto.current_user_or_key(true)
      if user
        $window.set_status_field(PandoraGtk::SF_Listen, 'Listening', nil, true)
        host = $host
        if not host
          host = PandoraUtils.get_param('listen_host')
          host ||= 'any'
        end
        if (not host)
          host = ''
        elsif ((host=='any') or (host=='any4') or (host=='all'))  #else can be "", "0.0.0.0", "0", "0::0", "::"
          host = Socket::INADDR_ANY
          p "ipv4 all"
        elsif ((host=='any6') or (host=='all6'))
          host = '::'
          p "ipv6 all"
        end
        p Socket.ip_address_list
        #p loc_hst = Socket.gethostname
        #p Socket.gethostbyname(loc_hst)[3]

        # TCP Listener
        tcp_port = $tcp_port
        if not tcp_port
          tcp_port = PandoraUtils.get_param('tcp_port')
          tcp_port ||= 5577
        end
        $tcp_listen_thread = Thread.new do
          begin
            server = TCPServer.open(host, tcp_port)
            addr_str = server.addr[3].to_s+(' tcp')+server.addr[1].to_s
            PandoraUtils.log_message(LM_Info, _('Listening address')+': '+addr_str)
          rescue
            server = nil
            PandoraUtils.log_message(LM_Warning, _('Cannot open port')+' TCP '+host.to_s+':'+tcp_port.to_s)
          end
          Thread.current[:tcp_server] = server
          Thread.current[:listen_tcp] = (server != nil)
          while Thread.current[:listen_tcp] and server and (not server.closed?)
            socket = get_listener_client_or_nil(server)
            while Thread.current[:listen_tcp] and not server.closed? and not socket
              sleep 0.05
              #Thread.pass
              #Gtk.main_iteration
              socket = get_listener_client_or_nil(server)
            end

            if Thread.current[:listen_tcp] and (not server.closed?) and socket
              host_ip = socket.peeraddr[2]
              unless $window.pool.is_black?(host_ip)
                host_name = socket.peeraddr[3]
                port = socket.peeraddr[1]
                proto = 'tcp'
                p 'LISTEN: '+[host_name, host_ip, port, proto].inspect
                session = Session.new(socket, host_name, host_ip, port, proto, \
                  0, nil, nil, nil, nil)
              else
                PandoraUtils.log_message(LM_Info, _('IP is banned')+': '+host_ip.to_s)
              end
            end
          end
          server.close if server and (not server.closed?)
          PandoraUtils.log_message(LM_Info, _('Listener stops')+' '+addr_str) if server
          $window.set_status_field(PandoraGtk::SF_Listen, 'Not listen', nil, false)
          $tcp_listen_thread = nil
          $window.correct_lis_btn_state
        end

        # UDP Listener
        udp_port = $udp_port
        if not udp_port
          udp_port = PandoraUtils.get_param('udp_port')
          udp_port ||= 5577
        end
        $udp_listen_thread = Thread.new do
          # Init UDP listener
          begin
            BasicSocket.do_not_reverse_lookup = true
            # Create socket and bind to address
            udp_server = UDPSocket.new
            udp_server.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)  #Allow broadcast
            #udp_server.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)  #Many ports
            #hton = IPAddr.new('127.0.0.1').hton
            #udp_server.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF, hton) #interface
            #udp_server.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, 5) #depth (default 1)
            #hton2 = IPAddr.new('0.0.0.1').hton
            #udp_server.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, hton+hton2) #listen multicast
            #udp_server.setsockopt(Socket::SOL_IP, Socket::IP_MULTICAST_LOOP, true) #come back (def on)
            udp_server.bind(host, udp_port)

            #addr_str = server.addr.to_s
            udp_addr_str = udp_server.addr[3].to_s+(' udp')+udp_server.addr[1].to_s
            PandoraUtils.log_message(LM_Info, _('Listening address')+': '+udp_addr_str)
          rescue
            udp_server = nil
            PandoraUtils.log_message(LM_Warning, _('Cannot open port')+' UDP '+host.to_s+':'+udp_port.to_s)
          end
          Thread.current[:udp_server] = udp_server
          Thread.current[:listen_udp] = (udp_server != nil)

          if udp_server
            # Send UDP broadcast hello
            GLib::Timeout.add(2000) do
              res = PandoraCrypto.current_user_and_key(false, false)
              if res.is_a? Array
                person_hash, key_hash = res
                hparams = {:version=>0, :iam=>person_hash, :mykey=>key_hash, :base=>$base_id}
                hparams[:addr] = $callback_addr if $callback_addr and ($callback_addr != '')
                hello = UdpHello + PandoraUtils.hash_to_namepson(hparams)
                if $udp_listen_thread
                  udp_server = $udp_listen_thread[:udp_server]
                  if udp_server and (not udp_server.closed?)
                    begin
                      udp_server.send(hello, 0, '<broadcast>', $udp_port)
                    rescue => err
                      p 'Cannot send UDP-broadcast: '+err.message
                    end
                  end
                end
              end
              false
            end
          end

          # Catch UDP datagrams
          while Thread.current[:listen_udp] and udp_server and (not udp_server.closed?)
            begin
              data, addr = udp_server.recvfrom(2000)
            rescue
              data = addr = nil
            end
            #data, addr = udp_server.recvfrom_nonblock(2000)
            p 'Received UDP-pack ['+data.inspect+'] addr='+addr.inspect
            if (data.is_a? String) and (data.bytesize > UdpHello.bytesize) \
            and (data[0, UdpHello.bytesize] == UdpHello)
              data = data[UdpHello.bytesize..-1]
              far_ip = addr[3]
              far_port = addr[1]
              hash = PandoraUtils.namepson_to_hash(data)
              if hash.is_a? Hash
                res = PandoraCrypto.current_user_and_key(false, false)
                if res.is_a? Array
                  person_hash, key_hash = res
                  far_version = hash['version']
                  far_person_hash = hash['iam']
                  far_key_hash = hash['mykey']
                  far_base_id = hash['base']
                  if ((far_person_hash != nil) or (far_key_hash != nil) or \
                    (far_base_id != nil)) and \
                    ((far_person_hash != person_hash) or (far_key_hash != key_hash) or \
                    (far_base_id != $base_id)) # or true)
                  then
                    addr = $window.pool.encode_addr(far_ip, far_port, 'tcp')
                    $window.pool.init_session(addr, nil, 0, nil, nil, far_person_hash, \
                      far_key_hash, far_base_id)
                  end
                end
              end
            end
          end
          #udp_server.close if udp_server and (not udp_server.closed?)
          PandoraUtils.log_message(LM_Info, _('Listener stops')+' '+udp_addr_str) if udp_server
          #$window.set_status_field(PandoraGtk::SF_Listen, 'Not listen', nil, false)
          $udp_listen_thread = nil
          $window.correct_lis_btn_state
        end
      end
      $window.correct_lis_btn_state
    end
  end

  $hunter_thread = nil

  # Start hunt
  # RU: Начать охоту
  def self.hunt_nodes(round_count=1)
    if $hunter_thread
      $hunter_thread.exit
      $hunter_thread = nil
      $window.correct_hunt_btn_state
    else
      user = PandoraCrypto.current_user_or_key(true)
      if user
        node_model = PandoraModel::Node.new
        filter = 'addr<>"" OR domain<>""'
        flds = 'id, addr, domain, tport, key_hash, base_id'
        sel = node_model.select(filter, false, flds)
        if sel and sel.size>0
          $hunter_thread = Thread.new(node_model, filter, flds, sel) \
          do |node_model, filter, flds, sel|
            $window.set_status_field(PandoraGtk::SF_Hunt, 'Hunting', nil, true)
            while round_count>0
              if sel and sel.size>0
                sel.each do |row|
                  node_id = row[0]
                  addr   = row[1]
                  domain = row[2]
                  tport = 0
                  begin
                    tport = row[3].to_i
                  rescue
                  end
                  person = nil
                  key_hash = row[4]
                  base_id = row[5]
                  tport = 5577 if (not tport) or (tport==0) or (tport=='')
                  domain = addr if ((not domain) or (domain == ''))
                  addr = $window.pool.encode_addr(domain, tport, 'tcp')
                  $window.pool.init_session(addr, nil, 0, nil, node_id, person, \
                    key_hash, base_id)
                end
                round_count -= 1
                if round_count>0
                  sleep 3
                  sel = node_model.select(filter, false, flds)
                end
              else
                round_count = 0
              end
            end
            $hunter_thread = nil
            $window.set_status_field(PandoraGtk::SF_Hunt, 'No hunt', nil, false)
          end
        else
          $window.correct_hunt_btn_state
          dialog = Gtk::MessageDialog.new($window, \
            Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
            Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
            _('Enter at least one node'))
          dialog.title = _('Note')
          dialog.default_response = Gtk::Dialog::RESPONSE_OK
          dialog.icon = $window.icon
          if (dialog.run == Gtk::Dialog::RESPONSE_OK)
            PandoraGtk.show_panobject_list(PandoraModel::Node, nil, nil, true)
          end
          dialog.destroy
        end
      else
        $window.correct_hunt_btn_state
      end
    end
  end

end


# ====================================================================
# Graphical user interface of Pandora
# RU: Графический интерфейс Пандоры

require 'fileutils'

module PandoraGtk
  # GTK is cross platform graphical user interface
  # RU: Кроссплатформенный оконный интерфейс
  begin
    require 'gtk2'
    Gtk.init
  rescue Exception
    Kernel.abort("Gtk is not installed.\nInstall packet 'ruby-gtk'")
  end

  include PandoraUtils
  include PandoraModel

  # Statusbar fields
  # RU: Поля в статусбаре
  SF_Update = 0
  SF_Lang   = 1
  SF_Auth   = 2
  SF_Listen = 3
  SF_Hunt   = 4
  SF_Notice = 5
  SF_Conn   = 6
  SF_Fish   = 7
  SF_Fisher = 8

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window #Gtk::Dialog
    attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, \
      :enter_like_tab, :enter_like_ok, :panelbox, :okbutton, :cancelbutton, \
      :def_widget, :main_sw

    # Create method
    # RU: Метод создания
    def initialize(*args)
      super(*args)
      @response = 0
      @window = self
      @enter_like_tab = false
      @enter_like_ok = true
      set_default_size(300, -1)

      window.transient_for = $window
      window.modal = true
      #window.skip_taskbar_hint = true
      window.window_position = Gtk::Window::POS_CENTER
      #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG
      window.destroy_with_parent = true

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2

      window.add(vpaned)
      #window.vbox.add(vpaned)

      @main_sw = Gtk::ScrolledWindow.new(nil, nil)
      sw = main_sw
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      @viewport = Gtk::Viewport.new(nil, nil)
      sw.add(viewport)

      image = Gtk::Image.new(Gtk::Stock::PROPERTIES, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box1 = TabLabelBox.new(image, _('Basic'), nil, false, 0)

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      page = notebook.append_page(sw, label_box1)
      vpaned.pack1(notebook, true, true)

      @panelbox = Gtk::VBox.new
      @hbox = Gtk::HBox.new
      panelbox.pack_start(hbox, false, false, 0)

      vpaned.pack2(panelbox, false, true)

      bbox = Gtk::HBox.new
      bbox.border_width = 2
      bbox.spacing = 4

      @okbutton = Gtk::Button.new(Gtk::Stock::OK)
      okbutton.width_request = 110
      okbutton.signal_connect('clicked') { |*args|
        @response=2
        #finish
      }
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') { |*args|
        @response=1
        #finish
      }
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

      #self.signal_connect('response') do |widget, response|
      #  case response
      #    when Gtk::Dialog::RESPONSE_OK
      #      p "OK"
      #    when Gtk::Dialog::RESPONSE_CANCEL
      #      p "Cancel"
      #    when Gtk::Dialog::RESPONSE_CLOSE
      #      p "Close"
      #      dialog.destroy
      #  end
      #end

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
          and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? Gtk::TextView))))
        then
          okbutton.activate if okbutton.sensitive?
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
          Gtk.main_iteration
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

  # ToggleToolButton with safety "active" switching
  # RU: ToggleToolButton с безопасным переключением "active"
  class SafeToggleToolButton < Gtk::ToggleToolButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      else
        self.active = an_active
      end
    end

  end

  # CheckButton with safety "active" switching
  # RU: CheckButton с безопасным переключением "active"
  class SafeCheckButton < Gtk::CheckButton

    # Remember signal handler
    # RU: Запомнить обработчик сигнала
    def safe_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end

    # Set "active" property safety
    # RU: Безопасно установить свойство "active"
    def safe_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # Entry with allowed symbols of mask
  # RU: Поле ввода с допустимыми символами в маске
  class MaskEntry < Gtk::Entry
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

  # Entry for integer
  # RU: Поле ввода целых чисел
  class IntegerEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789-'
      self.max_length = 20
    end
  end

  # Entry for float
  # RU: Поле ввода дробных чисел
  class FloatEntry < IntegerEntry
    def init_mask
      super
      @mask += '.e'
      self.max_length = 35
    end
  end

  # Entry for HEX
  # RU: Поле ввода шестнадцатеричных чисел
  class HexEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789abcdefABCDEF'
    end
  end

  Base64chars = [('0'..'9').to_a, ('a'..'z').to_a, ('A'..'Z').to_a, '+/=-_*[]'].join

  # Entry for Base64
  # RU: Поле ввода Base64
  class Base64Entry < MaskEntry
    def init_mask
      super
      @mask = Base64chars
    end
  end

  # Simple entry for date
  # RU: Простое поле ввода даты
  class DateEntrySimple < MaskEntry
    def init_mask
      super
      @mask = '0123456789.'
      self.max_length = 10
      self.tooltip_text = 'DD.MM.YYYY'
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class TimeEntry < DateEntrySimple
    def init_mask
      super
      @mask += ' :'
      self.max_length = 19
      self.tooltip_text = 'DD.MM.YYYY hh:mm:ss'
    end
  end

  # Entry for date
  # RU: Поле ввода даты
  class DateEntry < Gtk::HBox
    attr_accessor :entry, :button

    def initialize(*args)
      super(*args)
      @entry = MaskEntry.new
      @entry.mask = '0123456789.'
      @entry.max_length = 10
      @entry.tooltip_text = 'DD.MM.YYYY'

      @button = Gtk::Button.new('D')
      @button.can_focus = false

      @entry.instance_variable_set('@button', @button)
      def @entry.key_event(widget, event)
        res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
          and (event.keyval==65364)))
        @button.activate if res
        false
      end
      self.pack_start(entry, true, true, 0)
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
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
        if @calwin and (not @calwin.destroyed?)
          @calwin.destroy
          @calwin = nil
        else
          @cal = Gtk::Calendar.new
          cal = @cal

          date = PandoraUtils.str_to_date(@entry.text)
          date ||= Time.new
          @month = date.month
          @year = date.year

          cal.select_month(date.month, date.year)
          cal.select_day(date.day)
          #cal.mark_day(date.day)
          cal.display_options = Gtk::Calendar::SHOW_HEADING | \
            Gtk::Calendar::SHOW_DAY_NAMES | Gtk::Calendar::WEEK_START_MONDAY

          cal.signal_connect('day_selected') do
            year, month, day = @cal.date
            if (@month==month) and (@year==year)
              @entry.text = PandoraUtils.date_to_str(Time.local(year, month, day))
              @calwin.destroy
              @calwin = nil
            else
              @month=month
              @year=year
            end
          end

          cal.signal_connect('key-press-event') do |widget, event|
            if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
              @cal.signal_emit('day-selected')
            elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
              ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) and event.state.control_mask?) #w, W, ц, Ц
            then
              @calwin.destroy
              @calwin = nil
              false
            elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) and event.state.mod1_mask?) or
              ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
            then
              @calwin.destroy
              @calwin = nil
              $window.destroy
              false
            elsif (event.keyval>=65360) and (event.keyval<=65367)
              if event.keyval==65360
                if @cal.month>0
                  @cal.month = @cal.month-1
                else
                  @cal.month = 11
                  @cal.year = @cal.year-1
                end
              elsif event.keyval==65367
                if @cal.month<11
                  @cal.month = @cal.month+1
                else
                  @cal.month = 0
                  @cal.year = @cal.year+1
                end
              elsif event.keyval==65365
                @cal.year = @cal.year-1
              elsif event.keyval==65366
                @cal.year = @cal.year+1
              end
              year, month, day = @cal.date
              @month=month
              @year=year
              false
            else
              false
            end
          end

          #menuitem = Gtk::ImageMenuItem.new
          #menuitem.add(cal)
          #menuitem.show_all

          #menu = Gtk::Menu.new
          #menu.append(menuitem)
          #menu.show_all
          #menu.popup(nil, nil, 0, Gdk::Event::CURRENT_TIME)


          @calwin = Gtk::Window.new #(Gtk::Window::POPUP)
          calwin = @calwin
          calwin.transient_for = $window
          calwin.modal = true
          calwin.decorated = false

          calwin.add(cal)
          calwin.signal_connect('delete_event') { @calwin.destroy; @calwin=nil }

          calwin.signal_connect('focus-out-event') do |win, event|
            @calwin.destroy
            @calwin = nil
            false
          end

          pos = @button.window.origin
          all = @button.allocation.to_a
          calwin.move(pos[0]+all[0], pos[1]+all[1]+all[3]+1)

          calwin.show_all
        end
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

  MaxPanhashTabs = 5

  # Entry for panhash
  # RU: Поле ввода панхэша
  class PanhashBox < Gtk::HBox
    attr_accessor :types, :panclasses, :entry, :button

    def initialize(panhash_type, *args)
      super(*args)
      @types = panhash_type
      @entry = HexEntry.new
      @button = Gtk::Button.new('...')
      @button.can_focus = false
      @entry.instance_variable_set('@button', @button)
      def @entry.key_event(widget, event)
        res = ((event.keyval==32) or ((event.state.shift_mask? or event.state.mod1_mask?) \
          and (event.keyval==65364)))
        @button.activate if res
        false
      end
      self.pack_start(entry, true, true, 0)
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
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
        dialog = PandoraGtk::AdvancedDialog.new(_('Choose object'))
        dialog.set_default_size(600, 400)
        auto_create = true
        panclasses.each_with_index do |panclass, i|
          title = _(PandoraUtils.get_name_or_names(panclass.name, true))
          dialog.main_sw.destroy if i==0
          image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          label_box2 = TabLabelBox.new(image, title, nil, false, 0)
          pbox = PandoraGtk::PanobjBox.new
          page = dialog.notebook.append_page(pbox, label_box2)
          auto_create = PandoraGtk.show_panobject_list(panclass, nil, pbox, auto_create)
          if panclasses.size>MaxPanhashTabs
            break
          end
        end
        dialog.notebook.page = 0
        dialog.run2 do
          panhash = nil
          pbox = dialog.notebook.get_nth_page(dialog.notebook.page)
          treeview = pbox.treeview
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
            if PandoraModel.const_defined? ptype
              panclasses << PandoraModel.const_get(ptype)
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

  # Entry for filename
  # RU: Поле выбора имени файла
  class FilenameBox < Gtk::HBox
    attr_accessor :entry, :button, :window

    def initialize(parent, *args)
      super(*args)
      @entry = Gtk::Entry.new
      @button = Gtk::Button.new('...')
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
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
      align.add(@button)
      self.pack_start(align, false, false, 1)
      esize = entry.size_request
      h = esize[1]-2
      @button.set_size_request(h, h)

      button.signal_connect('clicked') do |*args|
        @entry.grab_focus
        dialog =  Gtk::FileChooserDialog.new(_('Choose a file'), @window,
          Gtk::FileChooser::ACTION_OPEN, 'gnome-vfs',
          [Gtk::Stock::OPEN, Gtk::Dialog::RESPONSE_ACCEPT],
          [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL])

        filter = Gtk::FileFilter.new
        filter.name = _('All files')+' (*.*)'
        filter.add_pattern('*.*')
        dialog.add_filter(filter)

        filter = Gtk::FileFilter.new
        filter.name = _('Pictures')+' (png,jpg,gif)'
        filter.add_pattern('*.png')
        filter.add_pattern('*.jpg')
        filter.add_pattern('*.jpeg')
        filter.add_pattern('*.gif')
        dialog.add_filter(filter)

        filter = Gtk::FileFilter.new
        filter.name = _('Sounds')+' (mp3,wav)'
        filter.add_pattern('*.mp3')
        filter.add_pattern('*.wav')
        dialog.add_filter(filter)

        dialog.add_shortcut_folder($pandora_files_dir)
        fn = @entry.text
        if fn.nil? or (fn=='')
          dialog.current_folder = $pandora_files_dir
        else
          dialog.filename = fn
        end

        scr = Gdk::Screen.default
        if (scr.height > 700)
          frame = Gtk::Frame.new
          frame.shadow_type = Gtk::SHADOW_IN
          align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
          align.add(frame)
          image = Gtk::Image.new
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

        if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
          @entry.text = dialog.filename
          yield(@entry.text, @entry, @button) if block_given?
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

  # Entry for coordinate
  # RU: Поле ввода координаты
  class CoordEntry < FloatEntry
    def init_mask
      super
      @mask += 'EsNn SwW\'"`′″,'
      self.max_length = 35
    end
  end

  # Entry for coordinates
  # RU: Поле ввода координат
  class CoordBox < Gtk::HBox
    attr_accessor :latitude, :longitude
    CoordWidth = 120

    def initialize
      super
      @latitude   = CoordEntry.new
      latitude.tooltip_text = _('Latitude')+': 60.716, 60 43\', 60.43\'00"N'+"\n["+latitude.mask+']'
      @longitude  = CoordEntry.new
      longitude.tooltip_text = _('Longitude')+': -114.9, W114 54\' 0", 114.9W'+"\n["+longitude.mask+']'
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
        coord = PandoraUtils.int_to_coord(i)
      else
        coord = ['', '']
      end
      latitude.text = coord[0].to_s
      longitude.text = coord[1].to_s
    end

    def text
      res = PandoraUtils.coord_to_int(latitude.text, longitude.text).to_s
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

  MaxOnePlaceViewSec = 60

  # Extended TextView
  # RU: Расширенный TextView
  class ExtTextView < Gtk::TextView
    attr_accessor :need_to_end, :middle_time, :middle_value

    def initialize
      super
      self.receives_default = true
      signal_connect('key-press-event') do |widget, event|
        res = false
        if (event.keyval == Gdk::Keyval::GDK_F9)
          set_readonly(self.editable?)
          res = true
        end
        res
      end

      self.signal_connect('size-allocate') do |widget, step, arg2|
        widget.parent.vadjustment.value = \
        widget.parent.vadjustment.upper - widget.parent.vadjustment.page_size
      end

    end

    def set_readonly(value=true)
      PandoraGtk.set_readonly(self, value, false)
    end

    # Do before addition
    # RU: Выполнить перед добавлением
    def before_addition(cur_time=nil, vadj_value=nil)
      cur_time ||= Time.now
      vadj_value ||= self.parent.vadjustment.value
      @need_to_end = ((vadj_value + self.parent.vadjustment.page_size) == self.parent.vadjustment.upper)
      if not @need_to_end
        if @middle_time and @middle_value and (@middle_value == vadj_value)
          if ((cur_time.to_i - @middle_time.to_i) > MaxOnePlaceViewSec)
            @need_to_end = true
            @middle_time = nil
          end
        else
          @middle_time = cur_time
          @middle_value = vadj_value
        end
      end
      @need_to_end
    end

    # Do after addition
    # RU: Выполнить после добавления
    def after_addition(go_to_end=nil)
      go_to_end ||= @need_to_end
      if go_to_end
        adj = self.parent.vadjustment
        adj.value = adj.upper
        #adj.value_changed       # bug: not scroll to end
        #adj.value = adj.upper   # if add many lines
        scroll_to_iter(buffer.end_iter, 0, false, 0.0, 0.0)
      end
      go_to_end
    end
  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    include PandoraUtils

    attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
      :keep_btn, :rate_label, :vouch_btn, :follow_btn, :trust_scale, :trust0, :public_btn, \
      :public_scale, :lang_entry, :format, :view_buffer, :last_sw, :font_desc

    # Add menu item
    # RU: Добавляет пункт меню
    def add_menu_item(label, menu, text)
      mi = Gtk::MenuItem.new(text)
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

    def get_lines(tv, first_y, last_y, buffer_coords, numbers)
      # Get iter at first y
      iter, top = tv.get_line_at_y(first_y)
      # For each iter, get its location and add it to the arrays.
      # Stop when we pass last_y
      count = 0
      size = 0
      while not iter.end?
        y, height = tv.get_line_yrange(iter)
        buffer_coords << y
        line_num = iter.line+1
        numbers << line_num
        count += 1
        break if (y + height) >= last_y
        iter.forward_line
      end
      count
    end

    # Set buffers
    # RU: Задать буферы
    def set_buffers(tv=nil)
      if not tv
        p '!!!!!!!!!!!!!'
        p notebook.page
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::Viewport) \
        and child.children[0].child
          #and (child.children[0].child.is_a? Gtk::TextView)
          p 'child  ch[0]='+[child, child.children[0], child.children[0].child].inspect
          p 'child  ch[0]='+[child.children[0].child.children].inspect
          p tv = child.children[0].child
        end
      end
      if tv
        @raw_buffer ||= tv.buffer

        if @view_mode
          tv.buffer = @view_buffer if tv.buffer != @view_buffer
        elsif tv.buffer != @raw_buffer
          tv.buffer = @raw_buffer
        end

        if @view_mode
          @tv_style ||= tv.modifier_style
          tv.modify_font(@font_desc)
          tv.modify_base(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          tv.modify_text(Gtk::STATE_NORMAL, Gdk::Color.parse('#ffff33'))
          tv.modify_cursor(Gdk::Color.parse('#ff1111'), Gdk::Color.parse('#ff1111'))
          tv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#A0A0A0'))
          tv.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          #style = tv.modifier_style
          #p style.methods
          #style.xthickness = 0
          #style.ythickness = 0
          #tv.modify_style(style)
          set_view_buffer(@format, @view_buffer, @raw_buffer)
        else
          #tv.style = @tv_style
          tv.modify_style(@tv_style)
          tv.modify_font(nil)
          #tv.modify_base(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
          #tv.modify_text(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          #tv.modify_cursor(Gdk::Color.parse('#111111'), Gdk::Color.parse('#111111'))
          #tv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#EEEEEE'))
          #tv.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#111111'))
          set_raw_buffer(@format, @raw_buffer, @view_buffer)
        end
      end
    end

    # Set tag for selection
    # RU: Задать тэг для выделенного
    def set_tag(tag)
      if tag
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::Viewport) \
        and (child.children[0].child.is_a? Gtk::TextView)
          tv = child.children[0].child
          buffer = tv.buffer

          if @view_buffer==buffer
            bounds = buffer.selection_bounds
            @view_buffer.apply_tag(tag, bounds[0], bounds[1])
          else
            bounds = buffer.selection_bounds
            ltext = rtext = ''
            case @format
              when 'bbcode'
                t = ''
                case tag
                  when 'bold'
                    t = 'b'
                  when 'italic'
                    t = 'i'
                  when 'strike'
                    t = 's'
                  when 'undline'
                    t = 'u'
                end
                ltext = '['+t+']'
                rtext = '[/'+t+']'
              when 'orgmode'
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

    class BodyScrolledWindow < Gtk::ScrolledWindow
      attr_accessor :field, :link_name, :text_view
    end

    # Start loading image from file
    # RU: Запускает загрузку картинки в файл
    def start_image_loading(filename)
      begin
        image_stream = File.open(filename, 'rb')
        image = Gtk::Image.new
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
        label = Gtk::Label.new(err_text)
        widget = label
      end
      widget
    end

    RUBY_KEYWORDS = 'begin end module class def if then else elsif while unless do case when require yield rescue include'.split
    RUBY_KEYWORDS2 = 'self true false not and or nil '.split

    def ruby_tag_line(str, index=0, mode=0)

      def ident_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) or (c == '_')
      end

      def capt_char?(c)
        ('A'..'Z').include?(c) or ('0'..'9').include?(c) or (c == '_')
      end

      def word_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) or ('0'..'9').include?(c) or (c == '_')
      end

      def oper_char?(c)
        '.+,-=*^%$()<>&[]:!?~{}|/\\'.include?(c)
      end

      def rewind_ident(str, i, ss, pc, prev_kw=nil)

        def check_func(prev_kw, c, i, ss, str)
          if (prev_kw=='def') and (c=='.')
            yield(:operator, i, i+1)
            i += 1
            i1 = i
            i += 1 while (i<ss) and ident_char?(str[i])
            i += 1 if (i<ss) and ('?!'.include?(str[i]))
            i2 = i
            yield(:function, i1, i2)
          end
          i
        end

        kw = nil
        c = str[i]
        fc = c
        i1 = i
        i += 1
        big_cons = true
        while (i<ss)
          c = str[i]
          if ('a'..'z').include?(c)
            big_cons = false if big_cons
          elsif not capt_char?(c)
            break
          end
          i += 1
        end
        #p 'rewind_ident(str, i1, i, ss, pc)='+[str, i1, i, ss, pc].inspect
        #i -= 1
        i2 = i
        if ('A'..'Z').include?(fc)
          if prev_kw=='class'
            yield(:class, i1, i2)
          elsif prev_kw=='module'
            yield(:module, i1, i2)
          else
            if big_cons
              yield(:big_constant, i1, i2)
            else
              yield(:constant, i1, i2)
            end
            i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
              yield(tag, id1, id2)
            end
          end
        else
          if pc==':'
            yield(:symbol, i1-1, i2)
          elsif pc=='@'
            if (i1-2>0) and (str[i1-2]=='@')
              yield(:classvar, i1-2, i2)
            else
              yield(:instvar, i1-1, i2)
            end
          elsif pc=='$'
            yield(:global, i1-1, i2)
          else
            s = str[i1, i2-i1]
            if RUBY_KEYWORDS.include?(s)
              yield(:keyword, i1, i2)
              kw = s
            elsif RUBY_KEYWORDS2.include?(s)
              yield(:keyword2, i1, i2)
              if (s=='self') and (prev_kw=='def')
                i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                  yield(tag, id1, id2)
                end
              end
            else
              i += 1 if (i<ss) and ('?!'.include?(str[i]))
              if prev_kw=='def'
                yield(:function, i1, i)
              else
                yield(:identifer, i1, i)
              end
            end
          end
        end
        [i, kw]
      end

      ss = str.size
      if ss>0
        i = 0
        if (mode == 1)
          if (str[0,4] == '=end')
            mode = 0
            i = 4
            yield(:comment, index, index + i)
          else
            yield(:comment, index, index + ss)
          end
        elsif (mode == 0) and (str[0] == '=') and (str[1,5] == 'begin')
          mode = 1
          yield(:comment, index, index + ss)
        end
        if (mode != 1)
          i += 1 while (i<ss) and ((str[i] == ' ') or (str[i] == "\t"))
          pc = ' '
          kw, kw2 = nil
          while (i<ss)
            c = str[i]
            if (c != ' ') and (c != "\t")
              if (c == '#')
                yield(:comment, index + i, index + ss)
                break
              elsif (c == "'") or (c == '"') or (c == '/')
                qc = c
                i1 = i
                i += 1
                if (i<ss)
                  c = str[i]
                  if c==qc
                    i += 1
                  else
                    pc = ' '
                    while (i<ss) and ((c != qc) or (pc == "\\") or (pc == qc))
                      if (pc=="\\")
                        pc = ' '
                      else
                        pc = c
                      end
                      c = str[i]
                      if (qc=='"') and (c=='{') and (pc=='#')
                        yield(:string, index + i1, index + i - 1)
                        yield(:operator, index + i - 1, index + i + 1)
                        i, kw2 = rewind_ident(str, i, ss, ' ') do |tag, id1, id2|
                          yield(tag, index + id1, index + id2)
                        end
                        i1 = i
                      end
                      i += 1
                    end
                  end
                end
                if (qc == '/')
                  i += 1 while (i<ss) and ('imxouesn'.include?(str[i]))
                  yield(:regex, index + i1, index + i)
                else
                  yield(:string, index + i1, index + i)
                end
              elsif ident_char?(c)
                i, kw = rewind_ident(str, i, ss, pc, kw) do |tag, id1, id2|
                  yield(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif (c=='$') and (i+1<ss) and ('~'.include?(str[i+1]))
                i1 = i
                i += 2
                yield(:global, index + i1, index + i)
                pc = ' '
              elsif ((c==':') or (c=='$')) and (i+1<ss) and (ident_char?(str[i+1]))
                i += 1
                pc = c
                i, kw2 = rewind_ident(str, i, ss, pc) do |tag, id1, id2|
                  yield(tag, index + id1, index + id2)
                end
                pc = ' '
              elsif oper_char?(c)
                i1 = i
                i += 1
                while (i<ss) and oper_char?(str[i])
                  i += 1
                end
                if i<ss
                  pc = ' '
                  c = str[i]
                end
                yield(:operator, index + i1, index + i)
              elsif ('0'..'9').include?(c)
                i1 = i
                i += 1
                if (i<ss) and ((str[i]=='x') or (str[i]=='X'))
                  i += 1
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) or ('A'..'F').include?(c))
                    i += 1
                  end
                  yield(:hexadec, index + i1, index + i)
                else
                  while (i<ss)
                    c = str[i]
                    break unless (('0'..'9').include?(c) or (c=='.') or (c=='e'))
                    i += 1
                  end
                  if i<ss
                    i -= 1 if str[i-1]=='.'
                    pc = ' '
                  end
                  yield(:number, index + i1, index + i)
                end
              else
                #yield(:keyword, index + i, index + ss/2)
                #break
                pc = c
                i += 1
              end
            else
              pc = c
              i += 1
            end
          end
        end
      end
      mode
    end

    def set_tags(buf, line1, line2, clean=nil)
      p 'line1, line2='+[line1, line2].inspect
      buf.begin_user_action do
        line = line1
        iter1 = buf.get_iter_at_line(line)
        iterN = nil
        mode = 0
        while line<=line2
          line += 1
          if line<buf.line_count
            iterN = buf.get_iter_at_line(line)
            iter2 = buf.get_iter_at_offset(iterN.offset-1)
          else
            iter2 = buf.end_iter
            line = line2+1
          end

          text = buf.get_text(iter1, iter2)
          offset1 = iter1.offset
          buf.remove_all_tags(iter1, iter2) if clean
          #buf.apply_tag('keyword', iter1, iter2)
          mode = ruby_tag_line(text, offset1, mode) do |tag, start, last|
            buf.apply_tag(tag.to_s,
              buf.get_iter_at_offset(start),
              buf.get_iter_at_offset(last))
          end
          #p mode
          iter1 = iterN if iterN
          #Gtk.main_iteration
        end
      end
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

      @toolbar = Gtk::Toolbar.new
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      panelbox.pack_start(toolbar, false, false, 0)

      @toolbar2 = Gtk::Toolbar.new
      toolbar2.toolbar_style = Gtk::Toolbar::Style::ICONS
      panelbox.pack_start(toolbar2, false, false, 0)

      @raw_buffer = nil
      @view_mode = true
      @format = nil
      @view_buffer = Gtk::TextBuffer.new
      @view_buffer.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      @view_buffer.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
      @view_buffer.create_tag('strike', 'strikethrough' => true)
      @view_buffer.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
      @view_buffer.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
      @view_buffer.create_tag('link', {'foreground' => 'blue', 'underline' => Pango::AttrUnderline::SINGLE})
      @view_buffer.create_tag('linked', {'foreground' => 'navy', 'underline' => Pango::AttrUnderline::SINGLE})
      @view_buffer.create_tag('left', 'justification' => Gtk::JUSTIFY_LEFT)
      @view_buffer.create_tag('center', 'justification' => Gtk::JUSTIFY_CENTER)
      @view_buffer.create_tag('right', 'justification' => Gtk::JUSTIFY_RIGHT)
      @view_buffer.create_tag('fill', 'justification' => Gtk::JUSTIFY_FILL)

      @view_buffer.create_tag('string', {'foreground' => '#00f000'})
      @view_buffer.create_tag('symbol', {'foreground' => '#008020'})
      @view_buffer.create_tag('comment', {'foreground' => '#8080e0'})
      @view_buffer.create_tag('keyword', {'foreground' => '#ffffff', 'weight' => Pango::FontDescription::WEIGHT_BOLD})
      @view_buffer.create_tag('keyword2', {'foreground' => '#ffffff'})
      @view_buffer.create_tag('function', {'foreground' => '#f12111'})
      @view_buffer.create_tag('number', {'foreground' => '#f050e0'})
      @view_buffer.create_tag('hexadec', {'foreground' => '#e070e7'})
      @view_buffer.create_tag('constant', {'foreground' => '#60eedd'})
      @view_buffer.create_tag('big_constant', {'foreground' => '#d080e0'})
      @view_buffer.create_tag('identifer', {'foreground' => '#ffff33'})
      @view_buffer.create_tag('global', {'foreground' => '#ffa500'})
      @view_buffer.create_tag('instvar', {'foreground' => '#ff85a2'})
      @view_buffer.create_tag('classvar', {'foreground' => '#ff79ec'})
      @view_buffer.create_tag('operator', {'foreground' => '#ffffff'})
      @view_buffer.create_tag('class', {'foreground' => '#ff1100', 'weight' => Pango::FontDescription::WEIGHT_BOLD})
      @view_buffer.create_tag('module', {'foreground' => '#1111ff', 'weight' => Pango::FontDescription::WEIGHT_BOLD})
      @view_buffer.create_tag('regex', {'foreground' => '#105090'})

      @view_buffer.signal_connect('changed') do |buf|  #modified-changed
        mark = buf.get_mark('insert')
        iter = buf.get_iter_at_mark(mark)
        line1 = iter.line
        set_tags(buf, line1, line1, true)
        false
      end

      @view_buffer.signal_connect('insert-text') do |buf, iter, text, len|
        $view_buffer_off1 = iter.offset
        false
      end

      @view_buffer.signal_connect('paste-done') do |buf|
        if $view_buffer_off1
          child = notebook.get_nth_page(notebook.page)
          line1 = buf.get_iter_at_offset($view_buffer_off1).line
          mark = buf.get_mark('insert')
          iter = buf.get_iter_at_mark(mark)
          line2 = iter.line
          $view_buffer_off1 = iter.offset
          set_tags(buf, line1, line2)

          if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::Viewport) \
          and (child.children[0].child.is_a? Gtk::TextView)
            tv = child.children[0].child
            #p 'tv='+tv.inspect
            tv.scroll_to_iter(buf.end_iter, 0, false, 0.0, 0.0)
            #adj = tv.parent.vadjustment
            #adj.value = adj.upper #- adj.page_size
            #adj.value_changed       # bug: not scroll to end
            #adj.value = adj.upper   # if add many lines
            #mark = buf.create_mark(nil, buf.end_iter, false)
            #tv.scroll_to_mark(mark, 0, true, 0.0, 1.0)
            #tv.scroll_to_mark(buf.get_mark('insert'), 0.0, true, 0.0, 1.0)
            #buf.delete_mark(mark)
          end
        end
        false
      end

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::PRINT_PREVIEW, 'Type', true) do |btn|
        @view_mode = btn.active?
        set_buffers
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::INDEX, 'Color', true) do |btn|
        p 'Color'
      end

      btn = Gtk::MenuToolButton.new(nil, 'auto')
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, 'auto')
      add_menu_item(btn, menu, 'plain')
      add_menu_item(btn, menu, 'orgmode')
      add_menu_item(btn, menu, 'bbcode')
      add_menu_item(btn, menu, 'wiki')
      add_menu_item(btn, menu, 'html')
      add_menu_item(btn, menu, 'ruby')
      add_menu_item(btn, menu, 'python')
      add_menu_item(btn, menu, 'xml')

      menu.show_all
      toolbar.add(btn)

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::BOLD, 'Bold') do |*args|
        set_tag('bold')
      end

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::ITALIC, 'Italic') do |*args|
        set_tag('italic')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::STRIKETHROUGH, 'Strike') do |*args|
        set_tag('strike')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDERLINE, 'Underline') do |*args|
        set_tag('undline')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDO, 'Undo')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::REDO, 'Redo')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::COPY, 'Copy')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::CUT, 'Cut')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::FIND, 'Find')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_LEFT, 'Left') do |*args|
        set_tag('left')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_RIGHT, 'Right') do |*args|
        set_tag('right')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, 'Center') do |*args|
        set_tag('center')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_FILL, 'Fill') do |*args|
        set_tag('fill')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SELECT_COLOR, 'Color') do |*args|
        set_tag('color')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SAVE, 'Save')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OPEN, 'Open')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link') do |*args|
        set_tag('link')
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::HOME, 'Image')
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::ADD, 'Add')
      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::DELETE, 'Delete')
      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      PandoraGtk.add_tool_btn(toolbar2, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

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
            p '---BodyScrolledWindow'
            toolbar2.hide
            hbox.hide
            textsw = child
            field = textsw.field
            if field
              link_name = field[FI_Widget].text
              link_name.chomp! if link_name
              bodywid = field[FI_Widget2]
              if (not bodywid) or (link_name != textsw.link_name)
                @last_sw = child
                if bodywid
                  bodywid.destroy if (not bodywid.destroyed?)
                  bodywid = nil
                  field[FI_Widget2] = nil
                end
                if link_name and (link_name != '')
                  if File.exist?(link_name)
                    ext = File.extname(link_name)
                    if ext and (['.jpg','.gif','.png'].include? ext.downcase)
                      image = start_image_loading(link_name)
                      bodywid = image
                      textsw.link_name = link_name
                    elsif ext and (['.txt','.rb','.xml','.py','.csv','.sh'].include? ext.downcase)
                      p 'Read file: '+link_name
                      File.open(link_name, 'r') do |file|
                        field[FI_Value] = file.read
                      end
                    else
                      field[FI_Value] = '@'+link_name
                    end
                  else
                    err_text = _('File does not exist')+":\n"+link_name
                    label = Gtk::Label.new(err_text)
                    bodywid = label
                  end
                else
                  link_name = nil
                end

                if not bodywid
                  textview = Gtk::TextView.new
                  #textview = child.children[0]
                  #textview.wrap_mode = Gtk::TextTag::WRAP_WORD
                  textview.signal_connect('key-press-event') do |widget, event|
                    if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
                      and event.state.control_mask?
                    then
                      true
                    end
                  end
                  textview.signal_connect('size-allocate') do |widget, step, arg2|
                    widget.parent.vadjustment.value = \
                      widget.parent.vadjustment.upper - widget.parent.vadjustment.page_size
                  end
                  textview.set_border_window_size(Gtk::TextView::WINDOW_LEFT, 54)
                  @font_desc = Pango::FontDescription.new('Monospace 11')
                  textview.signal_connect('expose-event') do |widget, event|
                    tv = widget
                    left_win = tv.get_window(Gtk::TextView::WINDOW_LEFT)
                    #right_win = tv.get_window(Gtk::TextView::WINDOW_RIGHT)
                    type = nil
                    if event.window == left_win
                      type = Gtk::TextView::WINDOW_LEFT
                      target = left_win
                    #elsif event.window == right_win
                    #  type = Gtk::TextView::WINDOW_RIGHT
                    #  target = right_win
                    end
                    if type
                      first_y = event.area.y
                      last_y = first_y + event.area.height
                      x, first_y = tv.window_to_buffer_coords(type, 0, first_y)
                      x, last_y = tv.window_to_buffer_coords(type, 0, last_y)
                      numbers = []
                      pixels = []
                      count = get_lines(tv, first_y, last_y, pixels, numbers)
                      # Draw fully internationalized numbers!
                      layout = widget.create_pango_layout("")
                      count.times do |i|
                        x, pos = tv.buffer_to_window_coords(type, 0, pixels[i])
                        str = numbers[i].to_s
                        layout.set_text(str)
                        widget.style.paint_layout(target, widget.state, false,
                          nil, widget, nil, 2, pos + 2, layout)
                      end
                    end
                    false
                  end
                  bodywid = textview
                end

                if not field[FI_Widget2]
                  field[FI_Widget2] = bodywid
                  #textsw.add_with_viewport(bodywid)
                  textsw.add(bodywid)
                end
                if bodywid.is_a? Gtk::TextView
                  bodywid.buffer.text = field[FI_Value].to_s
                  set_buffers(bodywid)
                  toolbar.show
                end
                textsw.show_all
              end
            end
          else
            p '---NOT BodyScrolledWindow'
            toolbar.hide
            hbox.hide
            toolbar2.show
          end
        end
      end

      @vbox = Gtk::VBox.new
      viewport.add(@vbox)

      @statusbar = Gtk::Statusbar.new
      PandoraGtk.set_statusbar_text(statusbar, '')
      statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      panhash_btn = Gtk::Button.new(_('Rate: '))
      panhash_btn.relief = Gtk::RELIEF_NONE
      statusbar.pack_start(panhash_btn, false, false, 0)

      panelbox.pack_start(statusbar, false, false, 0)


      #rbvbox = Gtk::VBox.new

      keep_box = Gtk::VBox.new
      @keep_btn = Gtk::CheckButton.new(_('keep'), true)
      #keep_btn.signal_connect('toggled') do |widget|
      #  p "keep"
      #end
      #rbvbox.pack_start(keep_btn, false, false, 0)
      #@rate_label = Gtk::Label.new('-')
      keep_box.pack_start(keep_btn, false, false, 0)
      @follow_btn = Gtk::CheckButton.new(_('follow'), true)
      follow_btn.signal_connect('clicked') do |widget|
        if widget.active?
          @keep_btn.active = true
        end
      end
      keep_box.pack_start(follow_btn, false, false, 0)

      @lang_entry = Gtk::Combo.new
      lang_entry.set_popdown_strings(PandoraModel.lang_list)
      lang_entry.entry.text = ''
      lang_entry.entry.select_region(0, -1)
      lang_entry.set_size_request(50, -1)
      keep_box.pack_start(lang_entry, true, true, 5)

      hbox.pack_start(keep_box, false, false, 0)

      trust_box = Gtk::VBox.new

      trust0 = nil
      @trust_scale = nil
      @vouch_btn = Gtk::CheckButton.new(_('vouch'), true)
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

      #@scale_button = Gtk::ScaleButton.new(Gtk::IconSize::BUTTON)
      #@scale_button.set_icons(['gtk-goto-bottom', 'gtk-goto-top', 'gtk-execute'])
      #@scale_button.signal_connect('value-changed') { |widget, value| puts "value changed: #{value}" }

      tips = nil
      j = nil
      if @panobject.ider=='Person'
        tips = [_('very destructive'), _('harmful'), _('critic'), _('neutral'), \
          _('constructive'), _('useful'), _('very creative')]
        j = (tips.size-1)/2
      end

      #@trust ||= (127*0.4).round
      #val = trust/127.0
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      @trust_scale = Gtk::HScale.new(adjustment)
      trust_scale.set_size_request(140, -1)
      trust_scale.update_policy = Gtk::UPDATE_DELAYED
      trust_scale.digits = 1
      trust_scale.draw_value = true
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
        widget.modify_fg(Gtk::STATE_NORMAL, color)
        @vouch_btn.modify_bg(Gtk::STATE_ACTIVE, color)
        if tips
          i = ((trust+127)/127.0*j).round
          if (i == j) and (trust != 0)
            if trust>0
              i += 1
            else
              i -= 1
            end
          end
          tip = tips[i]
        end
        widget.tooltip_text = tip
      end
      #scale.signal_connect('change-value') do |widget|
      #  true
      #end
      trust_box.pack_start(trust_scale, false, false, 0)
      hbox.pack_start(trust_box, false, false, 0)

      pub_lev0 = nil
      public_box = Gtk::VBox.new
      @public_btn = Gtk::CheckButton.new(_('public'), true)
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

      #@lang_entry = Gtk::ComboBoxEntry.new(true)
      #lang_entry.set_size_request(60, 15)
      #lang_entry.append_text('0')
      #lang_entry.append_text('1')
      #lang_entry.append_text('5')

      #@lang_entry = Gtk::Combo.new
      #@lang_entry.set_popdown_strings(['0','1','5'])
      #@lang_entry.entry.text = ''
      #@lang_entry.entry.select_region(0, -1)
      #@lang_entry.set_size_request(50, -1)
      #public_box.pack_start(lang_entry, true, true, 5)

      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      @public_scale = Gtk::HScale.new(adjustment)
      public_scale.set_size_request(140, -1)
      public_scale.update_policy = Gtk::UPDATE_DELAYED
      public_scale.digits = 1
      public_scale.draw_value = true
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
        color = Gdk::Color.new(r, g, b)
        widget.modify_fg(Gtk::STATE_NORMAL, color)
        @vouch_btn.modify_bg(Gtk::STATE_ACTIVE, color)
        widget.tooltip_text = val.to_s
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
          textsw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)

          image = Gtk::Image.new(Gtk::Stock::DND, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          label_box = TabLabelBox.new(image, atext, nil, false, 0)
          page = notebook.append_page(textsw, label_box)

          #field[FI_Widget] = textview

          #field << page
          @text_fields << field
          textsw.field = field

          #@fields.delete_at(i) if (atype=='Text')
        end
      end

      image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Relations'), nil, false, 0)
      pbox = PandoraGtk::PanobjBox.new
      page = notebook.append_page(pbox, label_box2)
      PandoraGtk.show_panobject_list(PandoraModel::Relation, nil, pbox)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_AUTHENTICATION, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Signs'), nil, false, 0)
      pbox = PandoraGtk::PanobjBox.new
      page = notebook.append_page(pbox, label_box2)
      PandoraGtk.show_panobject_list(PandoraModel::Sign, nil, pbox)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_INFO, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Opinions'), nil, false, 0)
      pbox = PandoraGtk::PanobjBox.new
      page = notebook.append_page(pbox, label_box2)
      PandoraGtk.show_panobject_list(PandoraModel::Opinion, nil, pbox)

      # create labels, remember them, calc middle char width
      texts_width = 0
      texts_chars = 0
      labels_width = 0
      max_label_height = 0
      @fields.each do |field|
        atext = field[FI_VFName]
        aview = field[FI_View]
        label = Gtk::Label.new(atext)
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
            entry = FilenameBox.new(window) do |filename, entry, button|
              name_fld = @panobject.field_des('name')
              if (name_fld.is_a? Array) and (name_fld[FI_Widget].is_a? Gtk::Entry)
                name_fld[FI_Widget].text = File.basename(filename)
              end
            end
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
            entry = Gtk::Entry.new
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
        #entry.modify_fg(Gtk::STATE_ACTIVE, color)
        entry.modify_text(Gtk::STATE_NORMAL, color)

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
          row_hbox = Gtk::HBox.new
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
              field_vbox = Gtk::VBox.new
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

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :label
    def initialize(image, title, child=nil, *args)
      super(*args)
      label_box = self
      label_box.pack_start(image, false, false, 0) if image
      @label = Gtk::Label.new(title)
      label_box.pack_start(label, false, false, 0)
      if child
        btn = Gtk::Button.new
        btn.relief = Gtk::RELIEF_NONE
        btn.focus_on_click = false
        style = btn.modifier_style
        style.xthickness = 0
        style.ythickness = 0
        btn.modify_style(style)
        wim,him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
        btn.set_size_request(wim+2,him+2)
        btn.signal_connect('clicked') do |*args|
          yield if block_given?
          ind = $window.notebook.children.index(child)
          $window.notebook.remove_page(ind) if ind
          label_box.destroy if not label_box.destroyed?
          child.destroy if not child.destroyed?
        end
        close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
        btn.add(close_image)
        align = Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
        align.add(btn)
        label_box.pack_start(align, false, false, 0)
      end
      label_box.spacing = 3
      label_box.show_all
    end
  end

  $you_color = 'blue'
  $dude_color = 'red'
  $tab_color = 'blue'
  $read_time = 1.5
  $last_page = nil

  # DrawingArea for video output
  # RU: DrawingArea для вывода видео
  class ViewDrawingArea < Gtk::DrawingArea
    attr_accessor :expose_event

    def initialize
      super
      #set_size_request(100, 100)
      #@expose_event = signal_connect('expose-event') do
      #  alloc = self.allocation
      #  self.window.draw_arc(self.style.fg_gc(self.state), true, \
      #    0, 0, alloc.width, alloc.height, 0, 64 * 360)
      #end
    end

    # Set expose event handler
    # RU: Устанавливает обработчик события expose
    def set_expose_event(value)
      signal_handler_disconnect(@expose_event) if @expose_event
      @expose_event = value
    end
  end

  CSI_Persons = 0
  CSI_Keys    = 1
  CSI_Nodes   = 2
  CSI_PersonRecs = 3

  # Talk dialog
  # RU: Диалог разговора
  class DialogScrollWin < Gtk::ScrolledWindow
    attr_accessor :room_id, :targets, :online_button, :snd_button, :vid_button, :talkview, \
      :editbox, :area_send, :area_recv, :recv_media_pipeline, :appsrcs, :session, :ximagesink, \
      :read_thread, :recv_media_queue, :has_unread, :person_name

    include PandoraGtk

    CL_Online = 0
    CL_Name   = 1

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(known_node, a_room_id, a_targets)
      super(nil, nil)

      @has_unread = false
      @room_id = a_room_id
      @targets = a_targets
      @recv_media_queue = Array.new
      @recv_media_pipeline = Array.new
      @appsrcs = Array.new

      p 'TALK INIT [known_node, a_room_id, a_targets]='+[known_node, a_room_id, a_targets].inspect

      model = PandoraUtils.get_model('Node')

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #sw.name = title
      #sw.add(treeview)
      border_width = 0

      image = Gtk::Image.new(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::MENU)
      image.set_padding(2, 0)

      hpaned = Gtk::HPaned.new
      add_with_viewport(hpaned)

      vpaned1 = Gtk::VPaned.new
      vpaned2 = Gtk::VPaned.new

      @area_recv = ViewDrawingArea.new
      area_recv.set_size_request(320, 240)
      area_recv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))

      res = area_recv.signal_connect('expose-event') do |*args|
        #p 'area_recv '+area_recv.window.xid.inspect
        false
      end

#avconv -f video4linux2 -i /dev/video0 -vcodec mpeg2video -r 25 -pix_fmt yuv420p -me_method epzs -b 2600k -bt 256k -f rtp rtp://192.168.44.150:5004

#ffmpeg -f dshow  -framerate 20 -i video=screen-capture-recorder -vf scale=1280:720 -vcodec libx264 -pix_fmt yuv420p -tune zerolatency -preset ultrafast -f mpegts udp://236.0.0.1:2000
#mplayer -demuxer +mpegts -framedrop -benchmark ffmpeg://udp://236.0.0.1:2000?fifo_size=100000&buffer_size=10000000

#avconv -f video4linux2 -i /dev/video1 -vcodec mpeg2video -pix_fmt yuv420p -me_method epzs -b 2600k -bt 256k -f mpegts udp://127.0.0.1:5004?listen
#mplayer -wid 39846401 -demuxer +mpegts -framedrop -benchmark ffmpeg://udp://127.0.0.1:5004

#http://stackoverflow.com/questions/24411982/find-better-vp8-parameters-for-robustness-in-udp-streaming-with-libav-ffmpeg
#avconv -f video4linux2 -i /dev/video0 -s qvga -f webm -s 320x240 -vcodec libvpx -vb 128k tcp://127.0.0.1:5000?listen
#avplay tcp://127.0.0.1:5000

#avconv -s qvga -f video4linux2 -i /dev/video0 -r 2 -copyts -b 128k -bt 32k -bufsize 10 -f webm tcp://127.0.0.1:5000?listen
#avplay -bufsize 10 tcp://127.0.0.1:5000


      hbox = Gtk::HBox.new

      bbox = Gtk::HBox.new
      bbox.border_width = 5
      bbox.spacing = 5

      @online_button = SafeCheckButton.new(_('Online'), true)
      online_button.safe_signal_clicked do |widget|
        if widget.active? and (not widget.inconsistent?)
          widget.safe_set_active(false)
          widget.inconsistent = true
          targets[CSI_Persons].each_with_index do |person, i|
            $window.pool.init_session(nil, targets[CSI_Nodes], 0, self, nil, \
              person, targets[CSI_Keys])
          end
        else
          widget.safe_set_active(false)
          widget.inconsistent = false
          $window.pool.stop_session(nil, targets[CSI_Persons], targets[CSI_Nodes], false)
        end
      end
      online_button.safe_set_active(known_node != nil)

      bbox.pack_start(online_button, false, false, 0)

      @snd_button = SafeCheckButton.new(_('Sound'), true)
      snd_button.safe_signal_clicked do |widget|
        if widget.active?
          if init_audio_sender(true)
            online_button.active = true
          end
        else
          init_audio_sender(false, true)
          init_audio_sender(false)
        end
      end
      bbox.pack_start(snd_button, false, false, 0)

      @vid_button = SafeCheckButton.new(_('Video'), true)
      vid_button.safe_signal_clicked do |widget|
        if widget.active?
          if init_video_sender(true)
            online_button.active = true
          end
        else
          init_video_sender(false, true)
          init_video_sender(false)
        end
      end

      bbox.pack_start(vid_button, false, false, 0)

      hbox.pack_start(bbox, false, false, 1.0)

      vpaned1.pack1(area_recv, false, true)
      vpaned1.pack2(hbox, false, true)
      vpaned1.set_size_request(350, 270)

      @talkview = PandoraGtk::ExtTextView.new
      talkview.set_readonly(true)
      talkview.set_size_request(200, 200)
      talkview.wrap_mode = Gtk::TextTag::WRAP_WORD
      #view.cursor_visible = false
      #view.editable = false

      talkview.buffer.create_tag('you', 'foreground' => $you_color)
      talkview.buffer.create_tag('dude', 'foreground' => $dude_color)
      talkview.buffer.create_tag('you_bold', 'foreground' => $you_color, 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      talkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  'weight' => Pango::FontDescription::WEIGHT_BOLD)

      @editbox = Gtk::TextView.new
      editbox.wrap_mode = Gtk::TextTag::WRAP_WORD
      editbox.set_size_request(200, 70)

      editbox.grab_focus

      talksw = Gtk::ScrolledWindow.new(nil, nil)
      talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      talksw.add(talkview)

      editbox.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
        and (not event.state.control_mask?) and (not event.state.shift_mask?) and (not event.state.mod1_mask?)
          if editbox.buffer.text != ''
            mes = editbox.buffer.text
            sended = add_and_send_mes(mes)
            if sended
              add_mes_to_view(mes)
              editbox.buffer.text = ''
            end
          end
          true
        elsif (Gdk::Keyval::GDK_Escape==event.keyval)
          editbox.buffer.text = ''
          false
        else
          false
        end
      end
      PandoraGtk.hack_enter_bug(editbox)

      hpaned2 = Gtk::HPaned.new
      @area_send = ViewDrawingArea.new
      area_send.set_size_request(120, 90)
      area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
      hpaned2.pack1(area_send, false, true)


      option_box = Gtk::HBox.new

      sender_box = Gtk::VBox.new
      sender_box.pack_start(option_box, false, true, 0)
      sender_box.pack_start(editbox, true, true, 0)

      vouch_btn = SafeCheckButton.new(_('vouch'), true)
      vouch_btn.safe_signal_clicked do |widget|
        #update_btn.clicked
      end
      option_box.pack_start(vouch_btn, false, false, 0)

      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      trust_scale = Gtk::HScale.new(adjustment)
      trust_scale.set_size_request(90, -1)
      trust_scale.update_policy = Gtk::UPDATE_DELAYED
      trust_scale.digits = 1
      trust_scale.draw_value = true
      trust_scale.value = 1.0
      trust_scale.value_pos = Gtk::POS_RIGHT
      option_box.pack_start(trust_scale, false, false, 0)

      smile_btn = Gtk::Button.new(_('smile'))
      option_box.pack_start(smile_btn, false, false, 4)
      game_btn = Gtk::Button.new(_('game'))
      option_box.pack_start(game_btn, false, false, 4)

      require_sign_btn = SafeCheckButton.new(_('require sign'), true)
      require_sign_btn.safe_signal_clicked do |widget|
        #update_btn.clicked
      end
      option_box.pack_start(require_sign_btn, false, false, 0)

      hpaned2.pack2(sender_box, true, true)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
      #list_sw.visible = false

      list_store = Gtk::ListStore.new(TrueClass, String)
      targets[CSI_Persons].each do |person|
        user_iter = list_store.append
        user_iter[CL_Name] = PandoraUtils.bytes_to_hex(person)
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      list_tree.rules_hint = true
      list_tree.search_column = CL_Name

      # column for fixed toggles
      renderer = Gtk::CellRendererToggle.new
      renderer.signal_connect('toggled') do |cell, path_str|
        path = Gtk::TreePath.new(path_str)
        iter = list_store.get_iter(path)
        fixed = iter[CL_Online]
        p 'fixed='+fixed.inspect
        fixed ^= 1
        iter[CL_Online] = fixed
      end

      tit_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
      #tit_image.set_padding(2, 0)
      tit_image.show_all

      column = Gtk::TreeViewColumn.new('', renderer, 'active' => CL_Online)

      #title_widget = Gtk::HBox.new
      #title_widget.pack_start(tit_image, false, false, 0)
      #title_label = Gtk::Label.new(_('People'))
      #title_widget.pack_start(title_label, false, false, 0)
      column.widget = tit_image


      # set this column to a fixed sizing (of 50 pixels)
      #column.sizing = Gtk::TreeViewColumn::FIXED
      #column.fixed_width = 50
      list_tree.append_column(column)

      # column for description
      renderer = Gtk::CellRendererText.new

      column = Gtk::TreeViewColumn.new(_('Nodes'), renderer, 'text' => CL_Name)
      column.set_sort_column_id(CL_Name)
      list_tree.append_column(column)

      list_sw.add(list_tree)

      hpaned3 = Gtk::HPaned.new
      hpaned3.pack1(list_sw, true, true)
      hpaned3.pack2(talksw, true, true)
      #motion-notify-event  #leave-notify-event  enter-notify-event
      #hpaned3.signal_connect('notify::position') do |widget, param|
      #  if hpaned3.position <= 1
      #    list_tree.set_size_request(0, -1)
      #    list_sw.set_size_request(0, -1)
      #  end
      #end
      hpaned3.position = 1
      hpaned3.position = 0

      area_send.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      area_send.signal_connect('button-press-event') do |widget, event|
        if hpaned3.position <= 1
          list_sw.width_request = 150 if list_sw.width_request <= 1
          hpaned3.position = list_sw.width_request
        else
          list_sw.width_request = list_sw.allocation.width
          hpaned3.position = 0
        end
      end

      area_send.signal_connect('visibility_notify_event') do |widget, event_visibility|
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            init_video_sender(true, true) if not area_send.destroyed?
          when Gdk::EventVisibility::FULLY_OBSCURED
            init_video_sender(false, true) if not area_send.destroyed?
        end
      end

      area_send.signal_connect('destroy') do |*args|
        init_video_sender(false)
      end

      vpaned2.pack1(hpaned3, true, true)
      vpaned2.pack2(hpaned2, false, true)

      hpaned.pack1(vpaned1, false, true)
      hpaned.pack2(vpaned2, true, true)

      area_recv.signal_connect('visibility_notify_event') do |widget, event_visibility|
        #p 'visibility_notify_event!!!  state='+event_visibility.state.inspect
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            init_video_receiver(true, true, false) if not area_recv.destroyed?
          when Gdk::EventVisibility::FULLY_OBSCURED
            init_video_receiver(false) if not area_recv.destroyed?
        end
      end

      #area_recv.signal_connect('map') do |widget, event|
      #  p 'show!!!!'
      #  init_video_receiver(true, true, false) if not area_recv.destroyed?
      #end

      area_recv.signal_connect('destroy') do |*args|
        init_video_receiver(false, false)
      end

      title = 'unknown'
      label_box = TabLabelBox.new(image, title, self, false, 0) do
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?

        $window.pool.stop_session(nil, targets[CSI_Persons], targets[CSI_Nodes], false)
      end

      page = $window.notebook.append_page(self, label_box)
      $window.notebook.set_tab_reorderable(self, true)

      self.signal_connect('delete-event') do |*args|
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end
      $window.construct_room_title(self)

      show_all

      load_history($load_history_count, $sort_history_mode)

      $window.notebook.page = $window.notebook.n_pages-1 if not known_node
      editbox.grab_focus
    end

    # Put message to dialog
    # RU: Добавляет сообщение в диалог
    def add_mes_to_view(mes, key_or_panhash=nil, myname=nil, modified=nil, \
    created=nil, to_end=nil)

      if mes
        notice = false
        if not myname
          mykey = PandoraCrypto.current_key(false, false)
          myname = PandoraCrypto.short_name_of_person(mykey)
        end

        time_style = 'you'
        name_style = 'you_bold'
        user_name = nil
        if key_or_panhash
          if key_or_panhash.is_a? String
            user_name = PandoraCrypto.short_name_of_person(nil, key_or_panhash, 0, myname)
          else
            user_name = PandoraCrypto.short_name_of_person(key_or_panhash, nil, 0, myname)
          end
          time_style = 'dude'
          name_style = 'dude_bold'
          notice = (not to_end.is_a? FalseClass)
        else
          user_name = myname
          #if not user_name
          #  mykey = PandoraCrypto.current_key(false, false)
          #  user_name = PandoraCrypto.short_name_of_person(mykey)
          #end
        end
        user_name = 'noname' if (not user_name) or (user_name=='')

        time_now = Time.now
        created = time_now if (not modified) and (not created)

        #vals = time_now.to_a
        #ny, nm, nd = vals[5], vals[4], vals[3]
        #midnight = Time.local(y, m, d)
        ##midnight = PandoraUtils.calc_midnight(time_now)

        #if created
        #  vals = modified.to_a
        #  my, mm, md = vals[5], vals[4], vals[3]

        #  cy, cm, cd = my, mm, md
        #  if created
        #    vals = created.to_a
        #    cy, cm, cd = vals[5], vals[4], vals[3]
        #  end

        #  if [cy, cm, cd] == [my, mm, md]

        #else
        #end

        #'12:30:11'
        #'27.07.2013 15:57:56'

        #'12:30:11 (12:31:05)'
        #'27.07.2013 15:57:56 (21:05:00)'
        #'27.07.2013 15:57:56 (28.07.2013 15:59:33)'

        #'(15:59:33)'
        #'(28.07.2013 15:59:33)'

        time_str = ''
        time_str << PandoraUtils.time_to_dialog_str(created, time_now) if created
        if modified and ((not created) or ((modified.to_i-created.to_i).abs>30))
          time_str << ' ' if (time_str != '')
          time_str << '('+PandoraUtils.time_to_dialog_str(modified, time_now)+')'
        end

        talkview.before_addition(time_now) if to_end.nil?
        talkview.buffer.insert(talkview.buffer.end_iter, "\n") if (talkview.buffer.char_count>0)
        talkview.buffer.insert(talkview.buffer.end_iter, time_str+' ', time_style)
        talkview.buffer.insert(talkview.buffer.end_iter, user_name+':', name_style)
        talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)

        talkview.after_addition(to_end) if (not to_end.is_a? FalseClass)
        talkview.show_all

        update_state(true) if notice
      end
    end

    # Load history of messages
    # RU: Подгрузить историю сообщений
    def load_history(max_message=6, sort_mode=0)
      if talkview and max_message and (max_message>0)
        messages = []
        fields = 'creator, created, destination, state, text, panstate, modified'

        mypanhash = PandoraCrypto.current_user_or_key(true)
        myname = PandoraCrypto.short_name_of_person(nil, mypanhash)

        persons = targets[CSI_Persons]
        nil_create_time = false
        persons.each do |person|
          model = PandoraUtils.get_model('Message')
          max_message2 = max_message
          max_message2 = max_message * 2 if (person == mypanhash)
          sel = model.select({:creator=>person, :destination=>mypanhash}, false, fields, \
            'id DESC', max_message2)
          sel.reverse!
          if (person == mypanhash)
            i = sel.size-1
            while i>0 do
              i -= 1
              time, text, time_prev, text_prev = sel[i][1], sel[i][4], sel[i+1][1], sel[i+1][4]
              #p [time, text, time_prev, text_prev]
              if (not time) or (not time_prev)
                time, time_prev = sel[i][6], sel[i+1][6]
                nil_create_time = true
              end
              if (not text) or (time and text and time_prev and text_prev \
              and ((time-time_prev).abs<30) and (AsciiString.new(text)==AsciiString.new(text_prev)))
                #p 'DEL '+[time, text, time_prev, text_prev].inspect
                sel.delete_at(i)
                i -= 1
              end
            end
          end
          messages += sel
          if (person != mypanhash)
            sel = model.select({:creator=>mypanhash, :destination=>person}, false, fields, \
              'id DESC', max_message)
            messages += sel
          end
        end
        if nil_create_time or (sort_mode==0) #sort by created
          messages.sort! do |a,b|
            res = (a[6]<=>b[6])
            res = (a[1]<=>b[1]) if (res==0) and (not nil_create_time)
            res
          end
        else   #sort by modified
          messages.sort! {|a,b| res = (a[1]<=>b[1]); res = (a[6]<=>b[6]) if (res==0); res }
        end

        talkview.before_addition
        i = (messages.size-max_message)
        i = 0 if i<0
        while i<messages.size do
          message = messages[i]

          creator = message[0]
          created = message[1]
          mes = message[4]
          modified = message[6]

          key_or_panhash = nil
          key_or_panhash = creator if (creator != mypanhash)

          add_mes_to_view(mes, key_or_panhash, myname, modified, created, false)

          i += 1
        end
        talkview.after_addition

        talkview.show_all
      end
    end

    # Get name and family
    # RU: Определить имя и фамилию
    # Get name and family
    # RU: Определить имя и фамилию
    def get_name_and_family(i)
      person = nil
      if i.is_a? String
        person = i
        i = targets[CSI_Persons].index(person)
      else
        person = targets[CSI_Persons][i]
      end
      aname, afamily = '', ''
      if i and person
        person_recs = targets[CSI_PersonRecs]
        if not person_recs
          person_recs = Array.new
          targets[CSI_PersonRecs] = person_recs
        end
        if person_recs[i]
          aname, afamily = person_recs[i]
        else
          aname, afamily = PandoraCrypto.name_and_family_of_person(nil, person)
          person_recs[i] = [aname, afamily]
        end
      end
      [aname, afamily]
    end

    # Set session
    # RU: Задать сессию
    def set_session(session, online=true)
      @sessions ||= []
      if online
        @sessions << session if (not @sessions.include?(session))
      else
        @sessions.delete(session)
        session.conn_mode = (session.conn_mode & (~PandoraNet::CM_KeepHere))
        session.dialog = nil
      end
      active = (@sessions.size>0)
      online_button.safe_set_active(active) if (not online_button.destroyed?)
      if not active
        snd_button.active = false if (not snd_button.destroyed?) and snd_button.active?
        vid_button.active = false if (not vid_button.destroyed?) and vid_button.active?
        #snd_button.safe_set_active(false) if (not snd_button.destroyed?)
        #vid_button.safe_set_active(false) if (not vid_button.destroyed?)
      end
    end

    # Send message to node
    # RU: Отправляет сообщение на узел
    def add_and_send_mes(text)
      res = false
      creator = PandoraCrypto.current_user_or_key(true)
      if creator
        online_button.active = true if (not online_button.active?)
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        targets[CSI_Persons].each do |panhash|
          #p 'ADD_MESS panhash='+panhash.inspect
          values = {:destination=>panhash, :text=>text, :state=>state, \
            :creator=>creator, :created=>time_now, :modified=>time_now}
          model = PandoraUtils.get_model('Message')
          panhash = model.panhash(values)
          values['panhash'] = panhash
          res1 = model.update(values, nil, nil)
          res = (res or res1)
        end
        dlg_sessions = $window.pool.sessions_on_dialog(self)
        dlg_sessions.each do |session|
          session.conn_mode = (session.conn_mode | PandoraNet::CM_KeepHere)
          session.send_state = (session.send_state | PandoraNet::CSF_Message)
        end
      end
      res
    end

    $statusicon = nil

    # Update tab color when received new data
    # RU: Обновляет цвет закладки при получении новых данных
    def update_state(received=true, curpage=nil)
      tab_widget = $window.notebook.get_tab_label(self)
      if tab_widget
        curpage ||= $window.notebook.get_nth_page($window.notebook.page)
        # interrupt reading thread (if exists)
        if $last_page and ($last_page.is_a? DialogScrollWin) \
        and $last_page.read_thread and (curpage != $last_page)
          $last_page.read_thread.exit
          $last_page.read_thread = nil
        end
        # set self dialog as unread
        if received
          @has_unread = true
          color = Gdk::Color.parse($tab_color)
          tab_widget.label.modify_fg(Gtk::STATE_NORMAL, color)
          tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, color)
          $statusicon.set_message(_('Message')+' ['+tab_widget.label.text+']')
          PandoraUtils.play_mp3('message')
        end
        # run reading thread
        timer_setted = false
        if (not self.read_thread) and (curpage == self) and $window.visible? and $window.has_toplevel_focus?
          #color = $window.modifier_style.text(Gtk::STATE_NORMAL)
          #curcolor = tab_widget.label.modifier_style.fg(Gtk::STATE_ACTIVE)
          if @has_unread #curcolor and (color != curcolor)
            timer_setted = true
            self.read_thread = Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.editbox.destroyed?)
                curpage.editbox.grab_focus
              end
              if $window.visible? and $window.has_toplevel_focus?
                read_sec = $read_time-0.3
                if read_sec >= 0
                  sleep(read_sec)
                end
                if $window.visible? and $window.has_toplevel_focus?
                  if (not self.destroyed?) and (not tab_widget.destroyed?) \
                  and (not tab_widget.label.destroyed?)
                    @has_unread = false
                    tab_widget.label.modify_fg(Gtk::STATE_NORMAL, nil)
                    tab_widget.label.modify_fg(Gtk::STATE_ACTIVE, nil)
                    $statusicon.set_message(nil)
                  end
                end
              end
              self.read_thread = nil
            end
          end
        end
        # set focus to editbox
        if curpage and (curpage.is_a? DialogScrollWin) and curpage.editbox
          if not timer_setted
            Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.editbox.destroyed?)
                curpage.editbox.grab_focus
              end
            end
          end
          Thread.pass
          curpage.editbox.grab_focus
        end
      end
    end

    # Parse Gstreamer string
    # RU: Распознаёт строку Gstreamer
    def parse_gst_string(text)
      elements = Array.new
      text.strip!
      elem = nil
      link = false
      i = 0
      while i<text.size
        j = 0
        while (i+j<text.size) and (not ([' ', '=', "\\", '!', '/', 10.chr, 13.chr].include? text[i+j, 1]))
          j += 1
        end
        #p [i, j, text[i+j, 1], text[i, j]]
        word = nil
        param = nil
        val = nil
        if i+j<text.size
          sym = text[i+j, 1]
          if ['=', '/'].include? sym
            if sym=='='
              param = text[i, j]
              i += j
            end
            i += 1
            j = 0
            quotes = false
            while (i+j<text.size) and (quotes or (not ([' ', "\\", '!', 10.chr, 13.chr].include? text[i+j, 1])))
              if quotes
                if text[i+j, 1]=='"'
                  quotes = false
                end
              elsif (j==0) and (text[i+j, 1]=='"')
                quotes = true
              end
              j += 1
            end
            sym = text[i+j, 1]
            val = text[i, j].strip
            val = val[1..-2] if val and (val.size>1) and (val[0]=='"') and (val[-1]=='"')
            val.strip!
            param.strip! if param
            if (not param) or (param=='')
              param = 'caps'
              if not elem
                word = 'capsfilter'
                elem = elements.size
                elements[elem] = [word, {}]
              end
            end
            #puts '++  [word, param, val]='+[word, param, val].inspect
          else
            word = text[i, j]
          end
          link = true if sym=='!'
        else
          word = text[i, j]
        end
        #p 'word='+word.inspect
        word.strip! if word
        #p '---[word, param, val]='+[word, param, val].inspect
        if param or val
          elements[elem][1][param] = val if elem and param and val
        elsif word and (word != '')
          elem = elements.size
          elements[elem] = [word, {}]
        end
        if link
          elements[elem][2] = true if elem
          elem = nil
          link = false
        end
        #p '===elements='+elements.inspect
        i += j+1
      end
      elements
    end

    # Append elements to pipeline
    # RU: Добавляет элементы в конвейер
    def append_elems_to_pipe(elements, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      # create elements and add to pipeline
      #p '---- begin add&link elems='+elements.inspect
      elements.each do |elem_desc|
        factory = elem_desc[0]
        params = elem_desc[1]
        if factory and (factory != '')
          i = factory.index('.')
          if not i
            elemname = nil
            elemname = factory+name_suff if name_suff
            if $gst_old
              if ((factory=='videoconvert') or (factory=='autovideoconvert'))
                factory = 'ffmpegcolorspace'
              end
            elsif (factory=='ffmpegcolorspace')
              factory = 'videoconvert'
            end
            elem = Gst::ElementFactory.make(factory, elemname)
            if elem
              elem_desc[3] = elem
              if params.is_a? Hash
                params.each do |k, v|
                  v0 = elem.get_property(k)
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  #v = v[1,-2] if v and (v.size>1) and (v[0]=='"') and (v[-1]=='"')
                  #puts 'v='+v.inspect
                  if (k=='caps') or (v0.is_a? Gst::Caps)
                    if $gst_old
                      v = Gst::Caps.parse(v)
                    else
                      v = Gst::Caps.from_string(v)
                    end
                  elsif (v0.is_a? Integer) or (v0.is_a? Float)
                    if v.index('.')
                      v = v.to_f
                    else
                      v = v.to_i
                    end
                  elsif (v0.is_a? TrueClass) or (v0.is_a? FalseClass)
                    v = ((v=='true') or (v=='1'))
                  end
                  #puts '[factory, elem, k, v]='+[factory, elem, v0, k, v].inspect
                  elem.set_property(k, v)
                  #p '----'
                  elem_desc[4] = v if k=='name'
                end
              end
              pipeline.add(elem) if pipeline
            else
              p 'Cannot create gstreamer element "'+factory+'"'
            end
          end
        end
      end
      # resolve names
      elements.each do |elem_desc|
        factory = elem_desc[0]
        link = elem_desc[2]
        if factory and (factory != '')
          #p '----'
          #p factory
          i = factory.index('.')
          if i
            name = factory[0,i]
            #p 'name='+name
            if name and (name != '')
              elem_desc = elements.find{ |ed| ed[4]==name }
              elem = elem_desc[3]
              if not elem
                p 'find by name in pipeline!!'
                p elem = pipeline.get_by_name(name)
              end
              elem[3] = elem if elem
              if elem
                pad = factory[i+1, -1]
                elem[5] = pad if pad and (pad != '')
              end
              #p 'elem[3]='+elem[3].inspect
            end
          end
        end
      end
      # link elements
      link1 = false
      elem1 = nil
      pad1  = nil
      if prev_elem
        link1 = true
        elem1 = prev_elem
        pad1  = prev_pad
      end
      elements.each_with_index do |elem_desc|
        link2 = elem_desc[2]
        elem2 = elem_desc[3]
        pad2  = elem_desc[5]
        if link1 and elem1 and elem2
          if pad1 or pad2
            pad1 ||= 'src'
            apad2 = pad2
            apad2 ||= 'sink'
            p 'pad elem1.pad1 >> elem2.pad2 - '+[elem1, pad1, elem2, apad2].inspect
            elem1.get_pad(pad1).link(elem2.get_pad(apad2))
          else
            #p 'elem1 >> elem2 - '+[elem1, elem2].inspect
            elem1 >> elem2
          end
        end
        link1 = link2
        elem1 = elem2
        pad1  = pad2
      end
      #p '===final add&link'
      [elem1, pad1]
    end

    # Append element to pipeline
    # RU: Добавляет элемент в конвейер
    def add_elem_to_pipe(str, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      elements = parse_gst_string(str)
      elem, pad = append_elems_to_pipe(elements, pipeline, prev_elem, prev_pad, name_suff)
      [elem, pad]
    end

    # Link sink element to area of widget
    # RU: Прицепляет сливной элемент к области виджета
    def link_sink_to_area(sink, area, pipeline=nil)

      # Set handle of window
      # RU: Устанавливает дескриптор окна
      def set_xid(area, sink)
        if (not area.destroyed?) and area.window and sink and (sink.class.method_defined? 'set_xwindow_id')
          win_id = nil
          if PandoraUtils.os_family=='windows'
            win_id = area.window.handle
          else
            win_id = area.window.xid
          end
          sink.set_property('force-aspect-ratio', true)
          sink.set_xwindow_id(win_id)
        end
      end

      res = nil
      if area and (not area.destroyed?)
        if (not area.window) and pipeline
          area.realize
          #Gtk.main_iteration
        end
        #p 'link_sink_to_area(sink, area, pipeline)='+[sink, area, pipeline].inspect
        set_xid(area, sink)
        if pipeline and (not pipeline.destroyed?)
          pipeline.bus.add_watch do |bus, message|
            if (message and message.structure and message.structure.name \
            and (message.structure.name == 'prepare-xwindow-id'))
              Gdk::Threads.synchronize do
                Gdk::Display.default.sync
                asink = message.src
                set_xid(area, asink)
              end
            end
            true
          end

          res = area.signal_connect('expose-event') do |*args|
            set_xid(area, sink)
          end
          area.set_expose_event(res)
        end
      end
      res
    end

    # Get video sender parameters
    # RU: Берёт параметры отправителя видео
    def get_video_sender_params(src_param = 'video_src_v4l2', \
      send_caps_param = 'video_send_caps_raw_320x240', send_tee_param = 'video_send_tee_def', \
      view1_param = 'video_view1_xv', can_encoder_param = 'video_can_encoder_vp8', \
      can_sink_param = 'video_can_sink_app')

      # getting from setup (will be feature)
      src         = PandoraUtils.get_param(src_param)
      send_caps   = PandoraUtils.get_param(send_caps_param)
      send_tee    = PandoraUtils.get_param(send_tee_param)
      view1       = PandoraUtils.get_param(view1_param)
      can_encoder = PandoraUtils.get_param(can_encoder_param)
      can_sink    = PandoraUtils.get_param(can_sink_param)

      # default param (temporary)
      #src = 'v4l2src decimate=3'
      #send_caps = 'video/x-raw-rgb,width=320,height=240'
      #send_tee = 'ffmpegcolorspace ! tee name=vidtee'
      #view1 = 'queue ! xvimagesink force-aspect-ratio=true'
      #can_encoder = 'vp8enc max-latency=0.5'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, view1, can_encoder, can_sink]
    end

    $send_media_pipelines = {}
    $webcam_xvimagesink   = nil

    # Initialize video sender
    # RU: Инициализирует отправщика видео
    def init_video_sender(start=true, just_upd_area=false)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and (PandoraUtils::elem_playing?($webcam_xvimagesink))
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          area_send.set_expose_event(nil)
          tsw = PandoraGtk.find_another_active_sender(self)
          if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
          and tsw.area_send and tsw.area_send.window
            link_sink_to_area($webcam_xvimagesink, tsw.area_send)
            #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
          end
          #p '--LEAVE'
          area_send.queue_draw if area_send and (not area_send.destroyed?)
        else
          #$webcam_xvimagesink.xwindow_id = 0
          count = PandoraGtk.nil_send_ptrind_by_room(room_id)
          if video_pipeline and (count==0) and (not PandoraUtils::elem_stopped?(video_pipeline))
            video_pipeline.stop
            area_send.set_expose_event(nil)
            #p '==STOP!!'
          end
        end
        #Thread.pass
      elsif (not self.destroyed?) and (not vid_button.destroyed?) and vid_button.active? \
      and area_send and (not area_send.destroyed?)
        if not video_pipeline
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            video_pipeline = Gst::Pipeline.new('spipe_v')

            ##video_src = 'v4l2src decimate=3'
            ##video_src_caps = 'capsfilter caps="video/x-raw-rgb,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240"'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv,width=320,height=240" ! videorate drop=10'
            #video_src_caps = 'capsfilter caps="video/x-raw-yuv, framerate=10/1, width=320, height=240"'
            #video_src_caps = 'capsfilter caps="width=320,height=240"'
            ##video_send_tee = 'ffmpegcolorspace ! tee name=vidtee'
            #video_send_tee = 'tee name=tee1'
            ##video_view1 = 'queue ! xvimagesink force-aspect-ratio=true'
            ##video_can_encoder = 'vp8enc max-latency=0.5'
            #video_can_encoder = 'vp8enc speed=2 max-latency=2 quality=5.0 max-keyframe-distance=3 threads=5'
            #video_can_encoder = 'ffmpegcolorspace ! videoscale ! theoraenc quality=16 ! queue'
            #video_can_encoder = 'jpegenc quality=80'
            #video_can_encoder = 'jpegenc'
            #video_can_encoder = 'mimenc'
            #video_can_encoder = 'mpeg2enc'
            #video_can_encoder = 'diracenc'
            #video_can_encoder = 'xvidenc'
            #video_can_encoder = 'ffenc_flashsv'
            #video_can_encoder = 'ffenc_flashsv2'
            #video_can_encoder = 'smokeenc keyframe=8 qmax=40'
            #video_can_encoder = 'theoraenc bitrate=128'
            #video_can_encoder = 'theoraenc ! oggmux'
            #video_can_encoder = videorate ! videoscale ! x264enc bitrate=256 byte-stream=true'
            #video_can_encoder = 'queue ! x264enc bitrate=96'
            #video_can_encoder = 'ffenc_h263'
            #video_can_encoder = 'h264enc'
            ##video_can_sink = 'appsink emit-signals=true'

            src_param = PandoraUtils.get_param('video_src')
            send_caps_param = PandoraUtils.get_param('video_send_caps')
            send_tee_param = 'video_send_tee_def'
            view1_param = PandoraUtils.get_param('video_view1')
            can_encoder_param = PandoraUtils.get_param('video_can_encoder')
            can_sink_param = 'video_can_sink_app'

            video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink \
              = get_video_sender_params(src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param)
            p [src_param, send_caps_param, send_tee_param, view1_param, \
                can_encoder_param, can_sink_param]
            p [video_src, video_send_caps, video_send_tee, video_view1, video_can_encoder, video_can_sink]

            if winos
              video_src = PandoraUtils.get_param('video_src_win')
              video_src ||= 'dshowvideosrc'
              #video_src ||= 'videotestsrc'
              video_view1 = PandoraUtils.get_param('video_view1_win')
              video_view1 ||= 'queue ! directdrawsink'
              #video_view1 ||= 'queue ! d3dvideosink'
            end

            $webcam_xvimagesink = nil
            webcam, pad = add_elem_to_pipe(video_src, video_pipeline)
            if webcam
              capsfilter, pad = add_elem_to_pipe(video_send_caps, video_pipeline, webcam, pad)
              p 'capsfilter='+capsfilter.inspect
              tee, teepad = add_elem_to_pipe(video_send_tee, video_pipeline, capsfilter, pad)
              p 'tee='+tee.inspect
              encoder, pad = add_elem_to_pipe(video_can_encoder, video_pipeline, tee, teepad)
              p 'encoder='+encoder.inspect
              if encoder
                appsink, pad = add_elem_to_pipe(video_can_sink, video_pipeline, encoder, pad)
                p 'appsink='+appsink.inspect
                $webcam_xvimagesink, pad = add_elem_to_pipe(video_view1, video_pipeline, tee, teepad)
                p '$webcam_xvimagesink='+$webcam_xvimagesink.inspect
              end
            end

            if $webcam_xvimagesink
              $send_media_pipelines['video'] = video_pipeline
              $send_media_queues[1] ||= PandoraUtils::RoundQueue.new(true)
              #appsink.signal_connect('new-preroll') do |appsink|
              #appsink.signal_connect('new-sample') do |appsink|
              appsink.signal_connect('new-buffer') do |appsink|
                p 'appsink new buf!!!'
                #buf = appsink.pull_preroll
                #buf = appsink.pull_sample
                p buf = appsink.pull_buffer
                if buf
                  data = buf.data
                  $send_media_queues[1].add_block_to_queue(data, $media_buf_size)
                end
              end
            else
              video_pipeline.destroy if video_pipeline
            end
          rescue => err
            $send_media_pipelines['video'] = nil
            mes = 'Camera init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            vid_button.active = false
          end
        end

        if video_pipeline
          if $webcam_xvimagesink and area_send #and area_send.window
            #$webcam_xvimagesink.xwindow_id = area_send.window.xid
            link_sink_to_area($webcam_xvimagesink, area_send)
          end
          if not just_upd_area
            #???
            video_pipeline.stop if (not PandoraUtils::elem_stopped?(video_pipeline))
            area_send.set_expose_event(nil)
          end
          #if not area_send.expose_event
            link_sink_to_area($webcam_xvimagesink, area_send, video_pipeline)
          #end
          #if $webcam_xvimagesink and area_send and area_send.window
          #  #$webcam_xvimagesink.xwindow_id = area_send.window.xid
          #  link_sink_to_area($webcam_xvimagesink, area_send)
          #end
          if just_upd_area
            video_pipeline.play if (not PandoraUtils::elem_playing?(video_pipeline))
          else
            ptrind = PandoraGtk.set_send_ptrind_by_room(room_id)
            count = PandoraGtk.nil_send_ptrind_by_room(nil)
            if count>0
              #Gtk.main_iteration
              #???
              p 'PLAAAAAAAAAAAAAAY 1'
              p PandoraUtils::elem_playing?(video_pipeline)
              video_pipeline.play if (not PandoraUtils::elem_playing?(video_pipeline))
              p 'PLAAAAAAAAAAAAAAY 2'
              #p '==*** PLAY'
            end
          end
          #if $webcam_xvimagesink and ($webcam_xvimagesink.get_state != Gst::STATE_PLAYING) \
          #and (video_pipeline.get_state == Gst::STATE_PLAYING)
          #  $webcam_xvimagesink.play
          #end
        end
      end
      video_pipeline
    end

    # Get video receiver parameters
    # RU: Берёт параметры приёмщика видео
    def get_video_receiver_params(can_src_param = 'video_can_src_app', \
      can_decoder_param = 'video_can_decoder_vp8', recv_tee_param = 'video_recv_tee_def', \
      view2_param = 'video_view2_x')

      # getting from setup (will be feature)
      can_src     = PandoraUtils.get_param(can_src_param)
      can_decoder = PandoraUtils.get_param(can_decoder_param)
      recv_tee    = PandoraUtils.get_param(recv_tee_param)
      view2       = PandoraUtils.get_param(view2_param)

      # default param (temporary)
      #can_src     = 'appsrc emit-signals=false'
      #can_decoder = 'vp8dec'
      #recv_tee    = 'ffmpegcolorspace ! tee'
      #view2       = 'ximagesink sync=false'

      [can_src, can_decoder, recv_tee, view2]
    end

    # Initialize video receiver
    # RU: Инициализирует приёмщика видео
    def init_video_receiver(start=true, can_play=true, init=true)
      if not start
        if ximagesink and (PandoraUtils::elem_playing?(ximagesink))
          if can_play
            ximagesink.pause
          else
            ximagesink.stop
          end
        end
        if not can_play
          p 'Disconnect HANDLER !!!'
          area_recv.set_expose_event(nil)
        end
      elsif (not self.destroyed?) and area_recv and (not area_recv.destroyed?)
        if (not recv_media_pipeline[1]) and init
          begin
            Gst.init
            p 'init_video_receiver INIT'
            winos = (PandoraUtils.os_family == 'windows')
            @recv_media_queue[1] ||= PandoraUtils::RoundQueue.new
            dialog_id = '_v'+PandoraUtils.bytes_to_hex(room_id[-6..-1])
            @recv_media_pipeline[1] = Gst::Pipeline.new('rpipe'+dialog_id)
            vidpipe = @recv_media_pipeline[1]

            ##video_can_src = 'appsrc emit-signals=false'
            ##video_can_decoder = 'vp8dec'
            #video_can_decoder = 'xviddec'
            #video_can_decoder = 'ffdec_flashsv'
            #video_can_decoder = 'ffdec_flashsv2'
            #video_can_decoder = 'queue ! theoradec ! videoscale ! capsfilter caps="video/x-raw,width=320"'
            #video_can_decoder = 'jpegdec'
            #video_can_decoder = 'schrodec'
            #video_can_decoder = 'smokedec'
            #video_can_decoder = 'oggdemux ! theoradec'
            #video_can_decoder = 'theoradec'
            #! video/x-h264,width=176,height=144,framerate=25/1 ! ffdec_h264 ! videorate
            #video_can_decoder = 'x264dec'
            #video_can_decoder = 'mpeg2dec'
            #video_can_decoder = 'mimdec'
            ##video_recv_tee = 'ffmpegcolorspace ! tee'
            #video_recv_tee = 'tee'
            ##video_view2 = 'ximagesink sync=false'
            #video_view2 = 'queue ! xvimagesink force-aspect-ratio=true sync=false'

            can_src_param = 'video_can_src_app'
            can_decoder_param = PandoraUtils.get_param('video_can_decoder')
            recv_tee_param = 'video_recv_tee_def'
            view2_param = PandoraUtils.get_param('video_view2')

            video_can_src, video_can_decoder, video_recv_tee, video_view2 \
              = get_video_receiver_params(can_src_param, can_decoder_param, \
                recv_tee_param, view2_param)

            if winos
              video_view2 = PandoraUtils.get_param('video_view2_win')
              video_view2 ||= 'queue ! directdrawsink'
            end

            @appsrcs[1], pad = add_elem_to_pipe(video_can_src, vidpipe, nil, nil, dialog_id)
            decoder, pad = add_elem_to_pipe(video_can_decoder, vidpipe, appsrcs[1], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(video_recv_tee, vidpipe, decoder, pad, dialog_id)
            @ximagesink, pad = add_elem_to_pipe(video_view2, vidpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[1] = nil
            mes = 'Video receiver init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            vid_button.active = false
          end
        end

        if @ximagesink #and area_recv.window
          link_sink_to_area(@ximagesink, area_recv,  recv_media_pipeline[1])
        end

        #p '[recv_media_pipeline[1], can_play]='+[recv_media_pipeline[1], can_play].inspect
        if recv_media_pipeline[1] and can_play and area_recv.window
          #if (not area_recv.expose_event) and
          if (not PandoraUtils::elem_playing?(recv_media_pipeline[1])) or (not PandoraUtils::elem_playing?(ximagesink))
            #p 'PLAYYYYYYYYYYYYYYYYYY!!!!!!!!!! '
            #ximagesink.stop
            #recv_media_pipeline[1].stop
            ximagesink.play
            recv_media_pipeline[1].play
          end
        end
      end
    end

    # Get audio sender parameters
    # RU: Берёт параметры отправителя аудио
    def get_audio_sender_params(src_param = 'audio_src_alsa', \
      send_caps_param = 'audio_send_caps_8000', send_tee_param = 'audio_send_tee_def', \
      can_encoder_param = 'audio_can_encoder_vorbis', can_sink_param = 'audio_can_sink_app')

      # getting from setup (will be feature)
      src = PandoraUtils.get_param(src_param)
      send_caps = PandoraUtils.get_param(send_caps_param)
      send_tee = PandoraUtils.get_param(send_tee_param)
      can_encoder = PandoraUtils.get_param(can_encoder_param)
      can_sink = PandoraUtils.get_param(can_sink_param)

      # default param (temporary)
      #src = 'alsasrc device=hw:0'
      #send_caps = 'audio/x-raw-int,rate=8000,channels=1,depth=8,width=8'
      #send_tee = 'audioconvert ! tee name=audtee'
      #can_encoder = 'vorbisenc quality=0.0'
      #can_sink = 'appsink emit-signals=true'

      # extend src and its caps
      src = src + ' ! audioconvert ! audioresample'
      send_caps = 'capsfilter caps="'+send_caps+'"'

      [src, send_caps, send_tee, can_encoder, can_sink]
    end

    # Initialize audio sender
    # RU: Инициализирует отправителя аудио
    def init_audio_sender(start=true, just_upd_area=false)
      audio_pipeline = $send_media_pipelines['audio']
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+snd_button.active?.inspect
      if not start
        #count = PandoraGtk.nil_send_ptrind_by_room(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (not PandoraUtils::elem_stopped?(audio_pipeline))
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not snd_button.destroyed?) and snd_button.active?
        if not audio_pipeline
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            audio_pipeline = Gst::Pipeline.new('spipe_a')
            $send_media_pipelines['audio'] = audio_pipeline

            ##audio_src = 'alsasrc device=hw:0 ! audioconvert ! audioresample'
            #audio_src = 'autoaudiosrc'
            #audio_src = 'alsasrc'
            #audio_src = 'audiotestsrc'
            #audio_src = 'pulsesrc'
            ##audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,channels=1,depth=8,width=8"'
            #audio_src_caps = 'queue ! capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,rate=8000,depth=8"'
            #audio_src_caps = 'capsfilter caps="audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=22000,channels=1"'
            #audio_src_caps = 'queue'
            ##audio_send_tee = 'audioconvert ! tee name=audtee'
            #audio_can_encoder = 'vorbisenc'
            ##audio_can_encoder = 'vorbisenc quality=0.0'
            #audio_can_encoder = 'vorbisenc quality=0.0 bitrate=16000 managed=true' #8192
            #audio_can_encoder = 'vorbisenc quality=0.0 max-bitrate=32768' #32768  16384  65536
            #audio_can_encoder = 'mulawenc'
            #audio_can_encoder = 'lamemp3enc bitrate=8 encoding-engine-quality=speed fast-vbr=true'
            #audio_can_encoder = 'lamemp3enc bitrate=8 target=bitrate mono=true cbr=true'
            #audio_can_encoder = 'speexenc'
            #audio_can_encoder = 'voaacenc'
            #audio_can_encoder = 'faac'
            #audio_can_encoder = 'a52enc'
            #audio_can_encoder = 'voamrwbenc'
            #audio_can_encoder = 'adpcmenc'
            #audio_can_encoder = 'amrnbenc'
            #audio_can_encoder = 'flacenc'
            #audio_can_encoder = 'ffenc_nellymoser'
            #audio_can_encoder = 'speexenc vad=true vbr=true'
            #audio_can_encoder = 'speexenc vbr=1 dtx=1 nframes=4'
            #audio_can_encoder = 'opusenc'
            ##audio_can_sink = 'appsink emit-signals=true'

            src_param = PandoraUtils.get_param('audio_src')
            send_caps_param = PandoraUtils.get_param('audio_send_caps')
            send_tee_param = 'audio_send_tee_def'
            can_encoder_param = PandoraUtils.get_param('audio_can_encoder')
            can_sink_param = 'audio_can_sink_app'

            audio_src, audio_send_caps, audio_send_tee, audio_can_encoder, audio_can_sink  \
              = get_audio_sender_params(src_param, send_caps_param, send_tee_param, \
                can_encoder_param, can_sink_param)

            if winos
              audio_src = PandoraUtils.get_param('audio_src_win')
              audio_src ||= 'dshowaudiosrc'
            end

            micro, pad = add_elem_to_pipe(audio_src, audio_pipeline)
            capsfilter, pad = add_elem_to_pipe(audio_send_caps, audio_pipeline, micro, pad)
            tee, teepad = add_elem_to_pipe(audio_send_tee, audio_pipeline, capsfilter, pad)
            audenc, pad = add_elem_to_pipe(audio_can_encoder, audio_pipeline, tee, teepad)
            appsink, pad = add_elem_to_pipe(audio_can_sink, audio_pipeline, audenc, pad)

            $send_media_queues[0] ||= PandoraUtils::RoundQueue.new(true)
            appsink.signal_connect('new-buffer') do |appsink|
              buf = appsink.pull_buffer
              if buf
                #p 'GET AUDIO ['+buf.size.to_s+']'
                data = buf.data
                $send_media_queues[0].add_block_to_queue(data, $media_buf_size)
              end
            end
          rescue => err
            $send_media_pipelines['audio'] = nil
            mes = 'Microphone init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGtk.set_send_ptrind_by_room(room_id)
          count = PandoraGtk.nil_send_ptrind_by_room(nil)
          #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
          if (count>0) and (not PandoraUtils::elem_playing?(audio_pipeline))
          #if (audio_pipeline.get_state != Gst::STATE_PLAYING)
            audio_pipeline.play
          end
        end
      end
      audio_pipeline
    end

    # Get audio receiver parameters
    # RU: Берёт параметры приёмщика аудио
    def get_audio_receiver_params(can_src_param = 'audio_can_src_app', \
      can_decoder_param = 'audio_can_decoder_vorbis', recv_tee_param = 'audio_recv_tee_def', \
      phones_param = 'audio_phones_auto')

      # getting from setup (will be feature)
      can_src     = PandoraUtils.get_param(can_src_param)
      can_decoder = PandoraUtils.get_param(can_decoder_param)
      recv_tee    = PandoraUtils.get_param(recv_tee_param)
      phones      = PandoraUtils.get_param(phones_param)

      # default param (temporary)
      #can_src = 'appsrc emit-signals=false'
      #can_decoder = 'vorbisdec'
      #recv_tee = 'audioconvert ! tee'
      #phones = 'autoaudiosink'

      [can_src, can_decoder, recv_tee, phones]
    end

    # Initialize audio receiver
    # RU: Инициализирует приёмщика аудио
    def init_audio_receiver(start=true, can_play=true, init=true)
      if not start
        if recv_media_pipeline[0] and (not PandoraUtils::elem_stopped?(recv_media_pipeline[0]))
          recv_media_pipeline[0].stop
        end
      elsif (not self.destroyed?)
        if (not recv_media_pipeline[0]) and init
          begin
            Gst.init
            winos = (PandoraUtils.os_family == 'windows')
            @recv_media_queue[0] ||= PandoraUtils::RoundQueue.new
            dialog_id = '_a'+PandoraUtils.bytes_to_hex(room_id[-6..-1])
            #p 'init_audio_receiver:  dialog_id='+dialog_id.inspect
            @recv_media_pipeline[0] = Gst::Pipeline.new('rpipe'+dialog_id)
            audpipe = @recv_media_pipeline[0]

            ##audio_can_src = 'appsrc emit-signals=false'
            #audio_can_src = 'appsrc'
            ##audio_can_decoder = 'vorbisdec'
            #audio_can_decoder = 'mulawdec'
            #audio_can_decoder = 'speexdec'
            #audio_can_decoder = 'decodebin'
            #audio_can_decoder = 'decodebin2'
            #audio_can_decoder = 'flump3dec'
            #audio_can_decoder = 'amrwbdec'
            #audio_can_decoder = 'adpcmdec'
            #audio_can_decoder = 'amrnbdec'
            #audio_can_decoder = 'voaacdec'
            #audio_can_decoder = 'faad'
            #audio_can_decoder = 'ffdec_nellymoser'
            #audio_can_decoder = 'flacdec'
            ##audio_recv_tee = 'audioconvert ! tee'
            #audio_phones = 'alsasink'
            ##audio_phones = 'autoaudiosink'
            #audio_phones = 'pulsesink'

            can_src_param = 'audio_can_src_app'
            can_decoder_param = PandoraUtils.get_param('audio_can_decoder')
            recv_tee_param = 'audio_recv_tee_def'
            phones_param = PandoraUtils.get_param('audio_phones')

            audio_can_src, audio_can_decoder, audio_recv_tee, audio_phones \
              = get_audio_receiver_params(can_src_param, can_decoder_param, recv_tee_param, phones_param)

            if winos
              audio_phones = PandoraUtils.get_param('audio_phones_win')
              audio_phones ||= 'autoaudiosink'
            end

            @appsrcs[0], pad = add_elem_to_pipe(audio_can_src, audpipe, nil, nil, dialog_id)
            auddec, pad = add_elem_to_pipe(audio_can_decoder, audpipe, appsrcs[0], pad, dialog_id)
            recv_tee, pad = add_elem_to_pipe(audio_recv_tee, audpipe, auddec, pad, dialog_id)
            audiosink, pad = add_elem_to_pipe(audio_phones, audpipe, recv_tee, pad, dialog_id)
          rescue => err
            @recv_media_pipeline[0] = nil
            mes = 'Audio receiver init exception'
            PandoraUtils.log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
          recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
        end
        if recv_media_pipeline[0] and can_play
          recv_media_pipeline[0].play if (not PandoraUtils::elem_playing?(recv_media_pipeline[0]))
        end
      end
    end
  end  #--class DialogScrollWin

  # Search panel
  # RU: Панель поиска
  class SearchBox < Gtk::VBox #Gtk::ScrolledWindow
    attr_accessor :text

    include PandoraGtk

    # Search in bases
    # RU: Поиск в базах
    def search_in_bases(text, th, bases='auto')

      def name_filter(fld, val)
        res = nil
        if val.index('*') or val.index('?')
          PandoraUtils.correct_aster_and_quest!(val)
          res = ' LIKE ?'
        else
          res = '=?'
        end
        res = fld + res
        [res, AsciiString.new(val)]
      end

      res = nil
      while th[:processing] and (not res)
        model = PandoraUtils.get_model('Person')
        fields = 'first_name, last_name, birth_day'
        sort = 'first_name, last_name'
        limit = 100
        word1, word2, word3, words = text.split
        p [word1, word2, word3, words]
        word1dup = word1.dup
        filter1, word1 = name_filter('first_name', word1)
        filter2, word2 = name_filter('last_name', word2) if word2
        word4 = nil
        if word3
          word3, word4 = word3.split('-')
          p [word3, word4]
          p word3 = PandoraUtils.str_to_date(word3).to_i
          p word4 = PandoraUtils.str_to_date(word4).to_i if word4
        end
        if word4
          filter = [filter1+' AND '+filter2+' AND birth_day>=? AND birth_day<=?', word1, word2, word3, word4]
          res = model.select(filter, false, fields, sort, limit)
        elsif word3
          filter = [filter1+' AND '+filter2+' AND birth_day=?', word1, word2, word3]
          res = model.select(filter, false, fields, sort, limit)
        elsif word2
          filter = [filter1+' AND '+filter2, word1, word2]
          res = model.select(filter, false, fields, sort, limit)
        else
          filter2, word1dup = name_filter('last_name', word1dup)
          filter = [filter1+' OR '+filter2, word1, word1dup]
          res = model.select(filter, false, fields, sort, limit)
        end
        res ||= []
        res.uniq!
        res.compact!
      end
      res
    end

    # Show search window
    # RU: Показать окно поиска
    def initialize(text=nil)
      super #(nil, nil)

      @text = nil
      @search_thread = nil

      #set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #vbox = Gtk::VBox.new
      #vpaned = Gtk::VPaned.new
      vbox = self

      search_btn = Gtk::ToolButton.new(Gtk::Stock::FIND, _('Search'))
      search_btn.tooltip_text = _('Start searching')
      PandoraGtk.set_readonly(search_btn, true)

      stop_btn = Gtk::ToolButton.new(Gtk::Stock::STOP, _('Stop'))
      stop_btn.tooltip_text = _('Stop searching')
      PandoraGtk.set_readonly(stop_btn, true)

      prev_btn = Gtk::ToolButton.new(Gtk::Stock::GO_BACK, _('Previous'))
      prev_btn.tooltip_text = _('Previous search')
      PandoraGtk.set_readonly(prev_btn, true)

      next_btn = Gtk::ToolButton.new(Gtk::Stock::GO_FORWARD, _('Next'))
      next_btn.tooltip_text = _('Next search')
      PandoraGtk.set_readonly(next_btn, true)

      search_entry = Gtk::Entry.new
      #PandoraGtk.hack_enter_bug(search_entry)
      search_entry.signal_connect('key-press-event') do |widget, event|
        res = false
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          search_btn.clicked
          res = true
        elsif (Gdk::Keyval::GDK_Escape==event.keyval)
          stop_btn.clicked
          res = true
        end
        res
      end
      search_entry.signal_connect('changed') do |widget, event|
        cant_find = (@search_thread or (search_entry.text.size==0))
        PandoraGtk.set_readonly(search_btn, cant_find)
        false
      end

      kind_entry = Gtk::Combo.new
      kind_entry.set_popdown_strings(['auto','person','file','all'])
      #kind_entry.entry.select_region(0, -1)

      #kind_entry = Gtk::ComboBox.new(true)
      #kind_entry.append_text('auto')
      #kind_entry.append_text('person')
      #kind_entry.append_text('file')
      #kind_entry.append_text('all')
      #kind_entry.active = 0
      #kind_entry.wrap_width = 3
      #kind_entry.has_frame = true

      kind_entry.set_size_request(100, -1)
      #p stop_btn.allocation.width
      #search_width = $window.allocation.width-kind_entry.allocation.width-stop_btn.allocation.width*4
      search_entry.set_size_request(150, -1)

      hbox = Gtk::HBox.new
      hbox.pack_start(kind_entry, false, false, 0)
      hbox.pack_start(search_btn, false, false, 0)
      hbox.pack_start(search_entry, true, true, 0)
      hbox.pack_start(stop_btn, false, false, 0)
      hbox.pack_start(prev_btn, false, false, 0)
      hbox.pack_start(next_btn, false, false, 0)

      option_box = Gtk::HBox.new

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(option_box, false, true, 0)

      #kind_btn = PandoraGtk::SafeToggleToolButton.new(Gtk::Stock::PROPERTIES)
      #kind_btn.tooltip_text = _('Change password')
      #kind_btn.safe_signal_clicked do |*args|
      #  #kind_btn.active?
      #end

      #Сделать горячие клавиши:
      #[CTRL + R], Ctrl + F5, Ctrl + Shift + R - Перезагрузить страницу
      #[CTRL + L] Выделить УРЛ страницы
      #[CTRL + N] Новое окно(не вкладка) - тоже что и Ctrl+T
      #[SHIFT + ESC] (Дипетчер задач) Возможно, список текущих соединений
      #[CTRL[+Alt] + 1] или [CTRL + 2] и т.д. - переключение между вкладками
      #Alt+ <- / -> - Вперед/Назад
      #Alt+Home - Домашняя страница (Профиль)
      #Открыть файл — Ctrl + O
      #Остановить — Esc
      #Сохранить страницу как — Ctrl + S
      #Найти далее — F3, Ctrl + G
      #Найти на этой странице — Ctrl + F
      #Отменить закрытие вкладки — Ctrl + Shift + T
      #Перейти к предыдущей вкладке — Ctrl + Page Up
      #Перейти к следующей вкладке — Ctrl + Page Down
      #Журнал посещений — Ctrl + H
      #Загрузки — Ctrl + J, Ctrl + Y
      #Закладки — Ctrl + B, Ctrl + I

      local_btn = SafeCheckButton.new(_('locally'), true)
      local_btn.safe_signal_clicked do |widget|
        #update_btn.clicked
      end
      local_btn.safe_set_active(true)

      active_btn = SafeCheckButton.new(_('active only'), true)
      active_btn.safe_signal_clicked do |widget|
        #update_btn.clicked
      end
      active_btn.safe_set_active(true)

      hunt_btn = SafeCheckButton.new(_('hunt!'), true)
      hunt_btn.safe_signal_clicked do |widget|
        #update_btn.clicked
      end
      hunt_btn.safe_set_active(true)

      option_box.pack_start(local_btn, false, false, 1)
      option_box.pack_start(active_btn, false, false, 1)
      option_box.pack_start(hunt_btn, false, false, 1)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(Integer, String, String, String)

      prev_btn.signal_connect('clicked') do |widget|
        PandoraGtk.set_readonly(next_btn, false)
        PandoraGtk.set_readonly(prev_btn, true)
        false
      end

      next_btn.signal_connect('clicked') do |widget|
        PandoraGtk.set_readonly(next_btn, true)
        PandoraGtk.set_readonly(prev_btn, false)
        false
      end

      search_btn.signal_connect('clicked') do |widget|
        text = search_entry.text
        search_entry.position = search_entry.position  # deselect
        if (text.size>0) and (not @search_thread)
          list_store.clear
          @search_thread = Thread.new do
            th = Thread.current
            th[:processing] = true
            PandoraGtk.set_readonly(stop_btn, false)
            PandoraGtk.set_readonly(widget, true)
            sleep 0.3
            res = search_in_bases(text, th, 'auto')
            if res.is_a? Array
              res.each_with_index do |row, i|
                user_iter = list_store.append
                user_iter[0] = i
                user_iter[1] = Utf8String.new(row[0])
                user_iter[2] = Utf8String.new(row[1])
                date = row[2]
                date = PandoraUtils.date_to_str(Time.at(date)) if date.is_a? Integer
                user_iter[3] = Utf8String.new(date)
              end
            end
            PandoraGtk.set_readonly(stop_btn, true)
            if th[:processing]
              th[:processing] = false
            end
            PandoraGtk.set_readonly(widget, false)
            PandoraGtk.set_readonly(prev_btn, false)
            PandoraGtk.set_readonly(next_btn, true)
            @search_thread = nil
          end
        end
        false
      end

      stop_btn.signal_connect('clicked') do |widget|
        if @search_thread
          if @search_thread[:processing]
            @search_thread[:processing] = false
          else
            PandoraGtk.set_readonly(stop_btn, true)
            @search_thread.exit
            @search_thread = nil
          end
        else
          search_entry.select_region(0, search_entry.text.size)
        end
      end

      #search_btn.signal_connect('clicked') do |*args|
      #end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('First name'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Last name'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Birth date'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      #vpaned.pack1(vbox, false, true)
      #vpaned.pack2(list_sw, true, true)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      #self.add(vbox)
      #self.add(hpaned)

      PandoraGtk.hack_grab_focus(search_entry)
    end
  end

  # Profile panel
  # RU: Панель профиля
  class ProfileScrollWin < Gtk::ScrolledWindow
    attr_accessor :person

    include PandoraGtk

    # Show profile window
    # RU: Показать окно профиля
    def initialize(a_person=nil)
      super(nil, nil)

      @person = a_person

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #self.add_with_viewport(vpaned)
    end
  end

  # List of session
  # RU: Список сеансов
  class SessionScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show session window
    # RU: Показать окно сессий
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      hunted_btn = SafeCheckButton.new(_('hunted'), true)
      hunted_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      hunted_btn.safe_set_active(true)

      hunters_btn = SafeCheckButton.new(_('hunters'), true)
      hunters_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      hunters_btn.safe_set_active(true)

      fishers_btn = SafeCheckButton.new(_('fishers'), true)
      fishers_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      fishers_btn.safe_set_active(true)

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(hunted_btn, false, true, 0)
      hbox.pack_start(hunters_btn, false, true, 0)
      hbox.pack_start(fishers_btn, false, true, 0)
      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(String, String, String, String, Integer, Integer, \
        Integer, Integer, Integer)
      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $window.pool.sessions.each do |session|
          hunter = ((session.conn_mode & PandoraNet::CM_Hunter)>0)
          if ((hunted_btn.active? and (not hunter)) \
          or (hunters_btn.active? and hunter) \
          or (fishers_btn.active? and session.active_hook))
            sess_iter = list_store.append
            sess_iter[0] = $window.pool.sessions.index(session).to_s
            sess_iter[1] = session.host_ip.to_s
            sess_iter[2] = session.port.to_s
            sess_iter[3] = PandoraUtils.bytes_to_hex(session.node_panhash)
            sess_iter[4] = session.conn_mode
            sess_iter[5] = session.conn_state
            sess_iter[6] = session.stage
            sess_iter[7] = session.read_state
            sess_iter[8] = session.send_state
          end

          #:host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state,
          #:stage, :dialog, :send_thread, :read_thread, :socket, :read_state, :send_state,
          #:send_models, :recv_models, :sindex,
          #:read_queue, :send_queue, :confirm_queue, :params, :rcmd, :rcode, :rdata,
          #:scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, :r_encode, :media_send,
          #:node_id, :node_panhash, :entered_captcha, :captcha_sw, :fishes, :fishers
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Ip'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Port'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('conn_mode'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('conn_state'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('stage'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('read_state'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('send_state'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # Creating menu item from its description
  # RU: Создание пункта меню по его описанию
  def self.create_menu_item(mi, treeview=nil)
    menuitem = nil
    if mi[0] == '-'
      menuitem = Gtk::SeparatorMenuItem.new
    else
      text = _(mi[2])
      #if (mi[4] == :check)
      #  menuitem = Gtk::CheckMenuItem.new(mi[2])
      #  label = menuitem.children[0]
      #  #label.set_text(mi[2], true)
      if mi[1]
        menuitem = Gtk::ImageMenuItem.new(mi[1])
        label = menuitem.children[0]
        label.set_text(text, true)
      else
        menuitem = Gtk::MenuItem.new(text)
      end
      #if mi[3]
      if (not treeview) and mi[3]
        key, mod = Gtk::Accelerator.parse(mi[3])
        menuitem.add_accelerator('activate', $group, key, mod, Gtk::ACCEL_VISIBLE) if key
      end
      menuitem.name = mi[0]
      menuitem.signal_connect('activate') { |widget| $window.do_menu_act(widget, treeview) }
    end
    menuitem
  end

  # List of fishes
  # RU: Список рыб
  class FishScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show fishes window
    # RU: Показать окно рыб
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      declared_btn = SafeCheckButton.new(_('declared'), true)
      declared_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      declared_btn.safe_set_active(true)

      lined_btn = SafeCheckButton.new(_('lined'), true)
      lined_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      lined_btn.safe_set_active(true)

      linked_btn = SafeCheckButton.new(_('linked'), true)
      linked_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      linked_btn.safe_set_active(true)

      failed_btn = SafeCheckButton.new(_('failed'), true)
      failed_btn.safe_signal_clicked do |widget|
        update_btn.clicked
      end
      #failed_btn.safe_set_active(true)

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(declared_btn, false, true, 0)
      hbox.pack_start(lined_btn, false, true, 0)
      hbox.pack_start(linked_btn, false, true, 0)
      hbox.pack_start(failed_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #fish_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(String, String, String, Integer, Integer, \
        Integer, Integer, String, Integer)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        if $window.pool
          $window.pool.notice_list.each do |no|
            sess_iter = list_store.append
            sess_iter[0] = PandoraUtils.bytes_to_hex(no[PandoraNet::NO_Person])
            sess_iter[1] = PandoraUtils.bytes_to_hex(no[PandoraNet::NO_Key])
            sess_iter[2] = PandoraUtils.bytes_to_hex(no[PandoraNet::NO_Baseid])
            sess_iter[3] = no[PandoraNet::NO_Notice_trust]
            sess_iter[4] = no[PandoraNet::NO_Notice_depth]
            sess_iter[5] = 0 #distance
            sess_iter[6] = no[PandoraNet::NO_Session].object_id
            sess_iter[7] = PandoraUtils.time_to_str(no[PandoraNet::NO_Time])
            sess_iter[8] = no[PandoraNet::NO_Index]
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #fish_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Person'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Key'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('BaseID'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Trust'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Depth'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Distance'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Session'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Index'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      menu = Gtk::Menu.new
      menu.append(PandoraGtk.create_menu_item(['Create', Gtk::Stock::NEW, _('Create'), 'Insert'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Edit', Gtk::Stock::EDIT, _('Edit'), 'Return'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['-', nil, nil], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Dialog', Gtk::Stock::MEDIA_PLAY, _('Dialog'), '<control>D'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Opinion', Gtk::Stock::JUMP_TO, _('Opinions'), '<control>BackSpace'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Relate', Gtk::Stock::INDEX, _('Relate'), '<control>R'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['-', nil, nil], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Convert', Gtk::Stock::CONVERT, _('Convert')], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Import', Gtk::Stock::OPEN, _('Import')], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Export', Gtk::Stock::SAVE, _('Export')], list_tree))
      menu.show_all

      list_tree.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      list_tree.signal_connect('button_press_event') do |widget, event|
        if (event.button == 3)
          menu.popup(nil, nil, event.button, event.time)
        end
      end

      list_tree.signal_connect('key-press-event') do |widget, event|
        res = true
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          act_panobject(list_tree, 'Edit')
        elsif (event.keyval==Gdk::Keyval::GDK_Insert)
          if event.state.control_mask?
            act_panobject(list_tree, 'Copy')
          else
            act_panobject(list_tree, 'Create')
          end
        elsif (event.keyval==Gdk::Keyval::GDK_Delete)
          act_panobject(list_tree, 'Delete')
        elsif event.state.control_mask?
          if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
            #act_panobject(list_tree, 'Dialog')
            path, column = list_tree.cursor
            if path
              iter = list_store.get_iter(path)
              person = nil
              person = iter[0] if iter
              person = PandoraUtils.hex_to_bytes(person)
              PandoraGtk.show_talk_dialog(person) if person
            end
          else
            res = false
          end
        else
          res = false
        end
        res
      end

      list_sw.add(list_tree)
      #lab_hbox = Gtk::HBox.new
      image = Gtk::Image.new(Gtk::Stock::GO_FORWARD, Gtk::IconSize::MENU)
      image.set_padding(2, 2)
      #image1 = Gtk::Image.new(Gtk::Stock::ORIENTATION_PORTRAIT, Gtk::IconSize::MENU)
      #image1.set_padding(2, 2)
      #image2 = Gtk::Image.new(Gtk::Stock::NETWORK, Gtk::IconSize::MENU)
      #image2.set_padding(2, 2)
      align = Gtk::Alignment.new(0.0, 0.5, 0.0, 0.0)
      btn = Gtk::Button.new(_('Neighbors'))
      btn.image = image
      btn.relief = Gtk::RELIEF_NONE
      btn.signal_connect('clicked') do |*args|
        PandoraGtk.show_fish_panel
      end
      align.add(btn)
      #lab_hbox.pack_start(image, false, false, 0)
      #lab_hbox.pack_start(image2, false, false, 0)
      #lab_hbox.pack_start(align, false, false, 0)
      #vbox.pack_start(lab_hbox, false, false, 0)
      vbox.pack_start(align, false, false, 0)
      vbox.pack_start(hbox, false, false, 0)
      vbox.pack_start(list_sw, true, true, 0)
      vbox.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # List of fishers
  # RU: Список рыбаков
  class FisherScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    # Show fishers window
    # RU: Показать окно рыбаков
    def initialize
      super(nil, nil)

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vbox = Gtk::VBox.new
      hbox = Gtk::HBox.new

      title = _('Update')
      @update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
      update_btn.tooltip_text = title
      update_btn.label = title

      title = _('Delete')
      delete_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, title)
      delete_btn.tooltip_text = title
      delete_btn.label = title

      hbox.pack_start(update_btn, false, true, 0)
      hbox.pack_start(delete_btn, false, true, 0)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #fish_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, Integer, String, String, String, String, \
        String, String)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $window.pool.fish_orders.each do |fo|
          sess_iter = list_store.append
          sess_iter[0] = fo[PandoraNet::FO_Index]
          sess_iter[1] = fo[PandoraNet::FO_Session].object_id
          sess_iter[2] = PandoraUtils.bytes_to_hex(fo[PandoraNet::FO_Fisher])
          sess_iter[3] = PandoraUtils.bytes_to_hex(fo[PandoraNet::FO_Fisher_key])
          sess_iter[4] = PandoraUtils.bytes_to_hex(fo[PandoraNet::FO_Fisher_baseid])
          sess_iter[5] = PandoraUtils.bytes_to_hex(fo[PandoraNet::FO_Fish])
          sess_iter[6] = PandoraUtils.bytes_to_hex(fo[PandoraNet::FO_Fish_key])
          sess_iter[7] = PandoraUtils.time_to_str(fo[PandoraNet::FO_Time])
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #fish_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Index'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Session'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Fisher'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Fisher key'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Fisher BaseID'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Fish'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Fish key'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      self.add_with_viewport(vbox)
      update_btn.clicked

      list_tree.grab_focus
    end
  end

  # Set readonly mode to widget
  # RU: Установить виджету режим только для чтения
  def self.set_readonly(widget, value=true, sensitive=true)
    value = (not value)
    widget.editable = value if widget.class.method_defined? 'editable?'
    widget.sensitive = value if sensitive and (widget.class.method_defined? 'sensitive?')
    #widget.can_focus = value
    widget.has_focus = value if widget.class.method_defined? 'has_focus?'
  end

  # Correct bug with dissapear Enter press event
  # RU: Исправляет баг с исчезновением нажатия Enter
  def self.hack_enter_bug(enterbox)
    # because of bug - doesnt work Enter at 'key-press-event'
    enterbox.signal_connect('key-release-event') do |widget, event|
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      and (not event.state.control_mask?) and (not event.state.shift_mask?) and (not event.state.mod1_mask?)
        widget.signal_emit('key-press-event', event)
        false
      end
    end
  end

  # Correct bug with non working focus set
  # RU: Исправляет баг с неработающей постановкой фокуса
  def self.hack_grab_focus(widget_to_focus)
    widget_to_focus.grab_focus
    Thread.new do
      sleep(0.2)
      if (not widget_to_focus.destroyed?)
        widget_to_focus.grab_focus
      end
    end
  end

  # Set statusbat text
  # RU: Задает текст статусной строки
  def self.set_statusbar_text(statusbar, text)
    statusbar.pop(0)
    statusbar.push(0, text)
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock, title, toggle=nil)
    btn = nil
    if toggle != nil
      btn = SafeToggleToolButton.new(stock)
      btn.safe_signal_clicked do |*args|
        yield(*args) if block_given?
      end
      btn.active = toggle if toggle
    else
      image = Gtk::Image.new(stock, Gtk::IconSize::MENU)
      btn = Gtk::ToolButton.new(image, _(title))
      #btn = Gtk::ToolButton.new(stock)
      btn.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
      btn.label = title
    end
    toolbar.add(btn)
    title = _(title)
    title.gsub!('_', '')
    btn.tooltip_text = title
    btn.label = title
    btn
  end

  $update_interval = 30
  $download_thread = nil

  UPD_FileList = ['model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'pandora.bat']
  UPD_FileList.concat(['model/03-language-'+$lang+'.xml', 'lang/'+$lang+'.txt']) if ($lang and ($lang != 'en'))

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    # Update file
    # RU: Обновить файл
    def self.update_file(http, path, pfn, host='')
      res = false
      dir = File.dirname(pfn)
      FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
      if Dir.exists?(dir)
        begin
          PandoraUtils.log_message(LM_Info, _('Download from') + ': ' + \
            host + path + '..')
          response = http.request_get(path)
          filebody = response.body
          if filebody and (filebody.size>0)
            File.open(pfn, 'wb+') do |file|
              file.write(filebody)
              res = true
              PandoraUtils.log_message(LM_Info, _('File updated')+': '+pfn)
            end
          else
            PandoraUtils.log_message(LM_Warning, _('Empty downloaded body'))
          end
        rescue => err
          PandoraUtils.log_message(LM_Warning, _('Update error')+': '+err.message)
        end
      else
        PandoraUtils.log_message(LM_Warning, _('Cannot create directory')+': '+dir)
      end
      res
    end

    def self.connect_http(main_uri, curr_size, step, p_addr=nil, p_port=nil, p_user=nil, p_pass=nil)
      http = nil
      time = 0
      PandoraUtils.log_message(LM_Info, _('Connect to') + ': ' + \
        main_uri.host + main_uri.path + ':' + main_uri.port.to_s + '..')
      begin
        http = Net::HTTP.new(main_uri.host, main_uri.port, p_addr, p_port, p_user, p_pass)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        http.open_timeout = 60*5
        response = http.request_head(main_uri.path)
        act_size = response.content_length
        if not act_size
          sleep(0.5)
          response = http.request_head(main_uri.path)
          act_size = response.content_length
        end
        PandoraUtils.set_param('last_check', Time.now)
        p 'Size diff: '+[act_size, curr_size].inspect
        if (act_size == curr_size)
          http = nil
          step = 254
          $window.set_status_field(SF_Update, 'Ok', false)
          PandoraUtils.set_param('last_update', Time.now)
        else
          time = Time.now.to_i
        end
      rescue => err
        http = nil
        $window.set_status_field(SF_Update, 'Connection error')
        PandoraUtils.log_message(LM_Warning, _('Cannot connect to repo to check update')+\
          [main_uri.host, main_uri.port].inspect)
        puts err.message
      end
      [http, time, step]
    end

    def self.reconnect_if_need(http, time, main_uri, p_addr=nil, p_port=nil, p_user=nil, p_pass=nil)
      if (not http.active?) or (Time.now.to_i >= (time + 60*5))
        begin
          http = Net::HTTP.new(main_uri.host, main_uri.port, p_addr, p_port, p_user, p_pass)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          http.open_timeout = 60*5
        rescue => err
          http = nil
          $window.set_status_field(SF_Update, 'Connection error')
          PandoraUtils.log_message(LM_Warning, _('Cannot reconnect to repo to update'))
          puts err.message
        end
      end
      http
    end

    if $download_thread and $download_thread.alive?
      $download_thread[:all_step] = all_step
      $download_thread.run if $download_thread.stop?
    else
      $download_thread = Thread.new do
        Thread.current[:all_step] = all_step
        downloaded = false
        $window.set_status_field(SF_Update, 'Need check')
        sleep($update_interval) if not Thread.current[:all_step]
        $window.set_status_field(SF_Update, 'Checking')

        main_script = File.join($pandora_root_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          if File.stat(main_script).writable?
            update_zip = PandoraUtils.get_param('update_zip_first')
            update_zip = true if update_zip.nil?
            proxy = PandoraUtils.get_param('proxy_server')
            if proxy.is_a? String
              proxy = proxy.split(':')
              proxy ||= []
              proxy = [proxy[0..-4].join(':'), *proxy[-3..-1]] if (proxy.size>4)
              proxy[1] = proxy[1].to_i if (proxy.size>1)
              proxy[2] = nil if (proxy.size>2) and (proxy[2]=='')
              proxy[3] = nil if (proxy.size>3) and (proxy[3]=='')
              PandoraUtils.log_message(LM_Info, _('Proxy is used')+' '+proxy.inspect)
            else
              proxy = []
            end
            step = 0
            while (step<2) do
              step += 1
              if update_zip
                zip_local = File.join($pandora_base_dir, 'Pandora-master.zip')
                zip_exists = File.exist?(zip_local)
                p [zip_exists, zip_local]
                if not zip_exists
                  File.open(zip_local, 'wb+') do |file|
                    file.write('0')  #empty file
                  end
                  zip_exists = File.exist?(zip_local)
                end
                if zip_exists
                  zip_size = File.size?(zip_local)
                  if zip_size
                    if File.stat(zip_local).writable?
                      #zip_on_repo = 'https://codeload.github.com/Novator/Pandora/zip/master'
                      #dir_in_zip = 'Pandora-maste'
                      zip_on_repo = 'https://bitbucket.org/robux/pandora/get/master.zip'
                      dir_in_zip = 'robux-pandora'
                      main_uri = URI(zip_on_repo)
                      http, time, step = connect_http(main_uri, zip_size, step, *proxy)
                      if http
                        PandoraUtils.log_message(LM_Info, _('Need update'))
                        $window.set_status_field(SF_Update, 'Need update')
                        Thread.stop
                        http = reconnect_if_need(http, time, main_uri, *proxy)
                        if http
                          $window.set_status_field(SF_Update, 'Doing')
                          res = update_file(http, main_uri.path, zip_local, main_uri.host)
                          #res = true
                          if res
                            # Delete old arch paths
                            unzip_mask = File.join($pandora_base_dir, dir_in_zip+'*')
                            p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                            unzip_paths.each do |pathfilename|
                              p 'Remove dir: '+pathfilename
                              FileUtils.remove_dir(pathfilename) if File.directory?(pathfilename)
                            end
                            # Unzip arch
                            unzip_meth = 'lib'
                            res = PandoraUtils.unzip_via_lib(zip_local, $pandora_base_dir)
                            p 'unzip_file1 res='+res.inspect
                            if not res
                              PandoraUtils.log_message(LM_Trace, _('Was not unziped with method')+': lib')
                              unzip_meth = 'util'
                              res = PandoraUtils.unzip_via_util(zip_local, $pandora_base_dir)
                              p 'unzip_file2 res='+res.inspect
                              if not res
                                PandoraUtils.log_message(LM_Warning, _('Was not unziped with method')+': util')
                              end
                            end
                            # Copy files to work dir
                            if res
                              PandoraUtils.log_message(LM_Info, _('Arch is unzipped with method')+': '+unzip_meth)
                              #unzip_path = File.join($pandora_base_dir, 'Pandora-master')
                              unzip_path = nil
                              p 'unzip_mask='+unzip_mask.inspect
                              p unzip_paths = Dir.glob(unzip_mask, File::FNM_PATHNAME | File::FNM_CASEFOLD)
                              unzip_paths.each do |pathfilename|
                                if File.directory?(pathfilename)
                                  unzip_path = pathfilename
                                  break
                                end
                              end
                              if unzip_path and Dir.exist?(unzip_path)
                                begin
                                  p 'Copy '+unzip_path+' to '+$pandora_root_dir
                                  #FileUtils.copy_entry(unzip_path, $pandora_root_dir, true)
                                  FileUtils.cp_r(unzip_path+'/.', $pandora_root_dir)
                                  PandoraUtils.log_message(LM_Info, _('Files are updated'))
                                rescue => err
                                  res = false
                                  PandoraUtils.log_message(LM_Warning, _('Cannot copy files from zip arch')+': '+err.message)
                                end
                                # Remove used arch dir
                                begin
                                  FileUtils.remove_dir(unzip_path)
                                rescue => err
                                  PandoraUtils.log_message(LM_Warning, _('Cannot remove arch dir')+' ['+unzip_path+']: '+err.message)
                                end
                                step = 255 if res
                              else
                                PandoraUtils.log_message(LM_Warning, _('Unzipped directory does not exist'))
                              end
                            else
                              PandoraUtils.log_message(LM_Warning, _('Arch was not unzipped'))
                            end
                          else
                            PandoraUtils.log_message(LM_Warning, _('Cannot download arch'))
                          end
                        end
                      end
                    else
                      $window.set_status_field(SF_Update, 'Read only')
                      PandoraUtils.log_message(LM_Warning, _('Zip is unrewritable'))
                    end
                  else
                    $window.set_status_field(SF_Update, 'Size error')
                    PandoraUtils.log_message(LM_Warning, _('Zip size error'))
                  end
                end
                update_zip = false
              else   # update with https from sources
                main_uri = URI('https://raw.githubusercontent.com/Novator/Pandora/master/pandora.rb')
                http, time, step = connect_http(main_uri, curr_size, step, *proxy)
                if http
                  PandoraUtils.log_message(LM_Info, _('Need update'))
                  $window.set_status_field(SF_Update, 'Need update')
                  Thread.stop
                  http = reconnect_if_need(http, time, main_uri, *proxy)
                  if http
                    $window.set_status_field(SF_Update, 'Doing')
                    # updating pandora.rb
                    downloaded = update_file(http, main_uri.path, main_script, main_uri.host)
                    # updating other files
                    UPD_FileList.each do |fn|
                      pfn = File.join($pandora_root_dir, fn)
                      if File.exist?(pfn) and (not File.stat(pfn).writable?)
                        downloaded = false
                        PandoraUtils.log_message(LM_Warning, \
                          _('Not exist or read only')+': '+pfn)
                      else
                        downloaded = downloaded and \
                          update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                      end
                    end
                    if downloaded
                      step = 255
                    else
                      PandoraUtils.log_message(LM_Warning, _('Direct download error'))
                    end
                  end
                end
                update_zip = true
              end
            end
            if step == 255
              PandoraUtils.set_param('last_update', Time.now)
              $window.set_status_field(SF_Update, 'Need restart')
              Thread.stop
              Kernel.abort('Pandora is updated. Run it again')
            elsif step<250
              $window.set_status_field(SF_Update, 'Load error')
            end
          else
            $window.set_status_field(SF_Update, 'Read only')
          end
        else
          $window.set_status_field(SF_Update, 'Size error')
        end
        $download_thread = nil
      end
    end
  end

  # Do action with selected record
  # RU: Выполнить действие над выделенной записью
  def self.act_panobject(tree_view, action)

    # Get icon associated with panobject
    # RU: Взять иконку ассоциированную с панобъектом
    def self.get_panobject_icon(panobj)
      panobj_icon = nil
      if panobj
        ind = nil
        $window.notebook.children.each do |child|
          if child.name==panobj.ider
            ind = $window.notebook.children.index(child)
            break
          end
        end
        if ind
          first_lab_widget = $window.notebook.get_tab_label($window.notebook.children[ind]).children[0]
          if first_lab_widget.is_a? Gtk::Image
            image = first_lab_widget
            panobj_icon = $window.render_icon(image.stock, Gtk::IconSize::MENU).dup
          end
        end
      end
      panobj_icon
    end

    path = nil
    if tree_view.destroyed?
      new_act = false
    else
      path, column = tree_view.cursor
      new_act = (action == 'Create')
    end
    p 'path='+path.inspect
    if path or new_act
      panobject = nil
      if (tree_view.is_a? SubjTreeView)
        panobject = tree_view.panobject
      end
      p 'panobject='+panobject.inspect
      store = tree_view.model
      iter = nil
      sel = nil
      id = nil
      panhash0 = nil
      lang = PandoraModel.text_to_lang($lang)
      panstate = 0
      created0 = nil
      creator0 = nil
      if path and (not new_act)
        iter = store.get_iter(path)
        id = iter[0]
        if panobject
          sel = panobject.select('id='+id.to_s, true)
          panhash0 = panobject.namesvalues['panhash']
          panstate = panobject.namesvalues['panstate']
          panstate ||= 0
          if (panobject.is_a? PandoraModel::Created)
            created0 = panobject.namesvalues['created']
            creator0 = panobject.namesvalues['creator']
          end
        else
          panhash0 = PandoraUtils.hex_to_bytes(id)
        end
        lang = panhash0[1].ord if panhash0 and (panhash0.size>1)
        lang ||= 0
      end

      panobjecticon = get_panobject_icon(panobject)

      if action=='Delete'
        if id and sel[0]
          info = panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
          dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
            Gtk::MessageDialog::QUESTION,
            Gtk::MessageDialog::BUTTONS_OK_CANCEL,
            _('Record will be deleted. Sure?')+"\n["+info+']')
          dialog.title = _('Deletion')+': '+panobject.sname
          dialog.default_response = Gtk::Dialog::RESPONSE_OK
          dialog.icon = panobjecticon if panobjecticon
          if dialog.run == Gtk::Dialog::RESPONSE_OK
            res = panobject.update(nil, nil, 'id='+id.to_s)
            tree_view.sel.delete_if {|row| row[0]==id }
            store.remove(iter)
            #iter.next!
            pt = path.indices[0]
            pt = tree_view.sel.size-1 if (pt > tree_view.sel.size-1)
            tree_view.set_cursor(Gtk::TreePath.new(pt), column, false) if (pt >= 0)
          end
          dialog.destroy
        end
      elsif action=='Dialog'
        show_talk_dialog(panhash0) if panhash0
      else  # Edit or Insert

        edit = ((not new_act) and (action != 'Copy'))

        i = 0
        formfields = panobject.def_fields.clone
        tab_flds = panobject.tab_fields
        formfields.each do |field|
          val = nil
          fid = field[FI_Id]
          view = field[FI_View]
          col = tab_flds.index{ |tf| tf[0] == fid }
          if col and sel and (sel[0].is_a? Array)
            val = sel[0][col]
            if (panobject.ider=='Parameter') and (fid=='value')
              type = panobject.field_val('type', sel[0])
              setting = panobject.field_val('setting', sel[0])
              ps = PandoraUtils.decode_param_setting(setting)
              view = ps['view']
              view ||= PandoraUtils.pantype_to_view(type)
              field[FI_View] = view
            end
          end

          if (not edit) and val.nil? and (panobject.is_a? PandoraModel::Created)
            case fid
              when 'created'
                val = Time.now.to_i
              when 'creator'
                creator = PandoraCrypto.current_user_or_key(true, false)
                val = creator if creator
            end
          end

          val, color = PandoraUtils.val_to_view(val, type, view, true)
          field[FI_Value] = val
          field[FI_Color] = color
        end

        dialog = FieldsDialog.new(panobject, formfields, panobject.sname)
        dialog.icon = panobjecticon if panobjecticon

        dialog.lang_entry.entry.text = PandoraModel.lang_to_text(lang) if lang

        if edit
          count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
          trust = nil
          #p PandoraUtils.bytes_to_hex(panhash0)
          #p 'trust or num'
          trust_or_num = PandoraCrypto.trust_in_panobj(panhash0)
          trust = trust_or_num if (trust_or_num.is_a? Float)
          dialog.vouch_btn.active = (trust_or_num != nil)
          dialog.vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
          dialog.trust_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          dialog.trust_scale.value = trust
          #dialog.rate_label.text = rate.to_s

          dialog.keep_btn.active = (PandoraModel::PSF_Support & panstate)>0

          pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
          dialog.public_btn.active = pub_level
          dialog.public_btn.inconsistent = (pub_level == nil)
          dialog.public_scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
          dialog.public_scale.sensitive = pub_level

          follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
          dialog.follow_btn.active = follow
          dialog.follow_btn.inconsistent = (follow == nil)

          #dialog.lang_entry.active_text = lang.to_s
          #trust_lab = dialog.trust_btn.children[0]
          #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
        else  #new or copy
          key = PandoraCrypto.current_key(false, false)
          key_inited = (key and key[PandoraCrypto::KV_Obj])
          dialog.keep_btn.active = true
          dialog.follow_btn.active = key_inited
          dialog.vouch_btn.active = key_inited
          dialog.trust_scale.sensitive = key_inited
          if not key_inited
            dialog.follow_btn.inconsistent = true
            dialog.vouch_btn.inconsistent = true
            dialog.public_btn.inconsistent = true
          end
          dialog.public_scale.sensitive = false
        end

        st_text = panobject.panhash_formula
        st_text = st_text + ' [#'+panobject.panhash(sel[0], lang, true, true)+']' if sel and sel.size>0
        PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

        if panobject.is_a? PandoraModel::Key
          mi = Gtk::MenuItem.new("Действия")
          menu = Gtk::MenuBar.new
          menu.append(mi)

          menu2 = Gtk::Menu.new
          menuitem = Gtk::MenuItem.new("Генерировать")
          menu2.append(menuitem)
          mi.submenu = menu2
          #p dialog.action_area
          dialog.hbox.pack_end(menu, false, false)
          #dialog.action_area.add(menu)
        end

        titadd = nil
        if not edit
        #  titadd = _('edit')
        #else
          titadd = _('new')
        end
        dialog.title += ' ('+titadd+')' if titadd and (titadd != '')

        dialog.run2 do
          # take value from form
          dialog.fields.each do |field|
            entry = field[FI_Widget]
            field[FI_Value] = entry.text
          end

          # fill hash of values
          flds_hash = {}
          dialog.fields.each do |field|
            type = field[FI_Type]
            view = field[FI_View]
            val = field[FI_Value]

            if (panobject.ider=='Parameter') and (field[FI_Id]=='value')
              par_type = panobject.field_val('type', sel[0])
              setting = panobject.field_val('setting', sel[0])
              ps = PandoraUtils.decode_param_setting(setting)
              view = ps['view']
              view ||= PandoraUtils.pantype_to_view(par_type)
            end
            p 'val.view, type, view='+[val, type, view].inspect
            val = PandoraUtils.view_to_val(val, type, view)
            if (view=='blob') or (view=='text')
              val = '@'+val if val and (val != '')
            end
            flds_hash[field[FI_Id]] = val
          end

          # text and blob fields
          dialog.text_fields.each do |field|
            entry = field[FI_Widget]
            if entry.text == ''
              textview = field[FI_Widget2]
              if (not textview.destroyed?) and (textview.is_a? Gtk::TextView)
                text = textview.buffer.text
                if text and (text.size>0)
                  field[FI_Value] = text
                  flds_hash[field[FI_Id]] = field[FI_Value]
                end
              end

              sha1_fld = panobject.field_des('sha1')
              md5_fld = panobject.field_des('md5')
              if sha1_fld or md5_fld
                p 'need to calc hashs'
              end
            end
          end

          # language detect
          lg = nil
          begin
            lg = PandoraModel.text_to_lang(dialog.lang_entry.entry.text)
          rescue
          end
          lang = lg if lg
          lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

          time_now = Time.now.to_i
          if (panobject.is_a? PandoraModel::Created)
            if created0 and flds_hash['created'] \
            and ((flds_hash['created'].to_i-created0.to_i).abs<=1)
              flds_hash['created'] = created0
            end
            #if not edit
              #flds_hash['created'] = time_now
              #creator = PandoraCrypto.current_user_or_key(true)
              #flds_hash['creator'] = creator
            #end
          end
          flds_hash['modified'] = time_now
          panstate = 0
          panstate = panstate | PandoraModel::PSF_Support if dialog.keep_btn.active?
          flds_hash['panstate'] = panstate
          if (panobject.is_a? PandoraModel::Key)
            lang = flds_hash['rights'].to_i
          elsif (panobject.is_a? PandoraModel::Currency)
            lang = 0
          end

          panhash = panobject.panhash(flds_hash, lang)
          flds_hash['panhash'] = panhash

          if (panobject.is_a? PandoraModel::Key) and (flds_hash['kind'].to_i == PandoraCrypto::KT_Priv) and edit
            flds_hash['panhash'] = panhash0
          end

          filter = nil
          filter = 'id='+id.to_s if edit
          res = panobject.update(flds_hash, nil, filter, true)
          if res
            filter ||= { :panhash => panhash, :modified => time_now }
            sel = panobject.select(filter, true)
            if sel[0]
              #p 'panobject.namesvalues='+panobject.namesvalues.inspect
              #p 'panobject.matter_fields='+panobject.matter_fields.inspect

              id = panobject.field_val('id', sel[0])  #panobject.namesvalues['id']
              id = id.to_i
              #p 'id='+id.inspect

              #p 'id='+id.inspect
              ind = tree_view.sel.index { |row| row[0]==id }
              #p 'ind='+ind.inspect
              if ind
                #p '---------CHANGE'
                sel[0].each_with_index do |c,i|
                  tree_view.sel[ind][i] = c
                end
                iter[0] = id
                store.row_changed(path, iter)
              else
                #p '---------INSERT'
                tree_view.sel << sel[0]
                iter = store.append
                iter[0] = id
                tree_view.set_cursor(Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
              end

              if not dialog.vouch_btn.inconsistent?
                PandoraCrypto.unsign_panobject(panhash0, true)
                if dialog.vouch_btn.active?
                  trust = (dialog.trust_scale.value*127).round
                  PandoraCrypto.sign_panobject(panobject, trust)
                end
              end

              if not dialog.follow_btn.inconsistent?
                PandoraModel.act_relation(nil, panhash0, RK_Follow, :delete, \
                  true, true)
                if (panhash != panhash0)
                  PandoraModel.act_relation(nil, panhash, RK_Follow, :delete, \
                    true, true)
                end
                if dialog.follow_btn.active?
                  PandoraModel.act_relation(nil, panhash, RK_Follow, :create, \
                    true, true)
                end
              end

              if not dialog.public_btn.inconsistent?
                public_level = RK_MinPublic + (dialog.public_scale.value*10).round+10
                p 'public_level='+public_level.inspect
                PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :delete, \
                  true, true)
                if (panhash != panhash0)
                  PandoraModel.act_relation(nil, panhash, RK_MinPublic, :delete, \
                    true, true)
                end
                if dialog.public_btn.active?
                  PandoraModel.act_relation(nil, panhash, public_level, :create, \
                    true, true)
                end
              end
            end
          end
        end
      end
    elsif action=='Dialog'
      PandoraGtk.show_panobject_list(PandoraModel::Person)
    end
  end

  # Grid for panobjects
  # RU: Таблица для объектов Пандоры
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject, :sel, :notebook, :auto_create
  end

  # Column for SubjTreeView
  # RU: Колонка для SubjTreeView
  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
  end

  # ScrolledWindow for panobjects
  # RU: ScrolledWindow для объектов Пандоры
  class PanobjBox < Gtk::VBox
    attr_accessor :update_btn, :auto_btn, :treeview
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, pbox=nil, auto_create=false)
    notebook = $window.notebook
    single = (pbox == nil)
    if single
      notebook.children.each do |child|
        if (child.is_a? PanobjBox) and (child.name==panobject_class.ider)
          notebook.page = notebook.children.index(child)
          #child.update_if_need
          return nil
        end
      end
    end
    panobject = panobject_class.new
    store = Gtk::ListStore.new(Integer)
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject

    param_view_col = nil

    tab_flds = panobject.tab_fields
    def_flds = panobject.def_fields
    def_flds.each do |df|
      id = df[FI_Id]
      tab_ind = tab_flds.index{ |tf| tf[0] == id }
      if tab_ind
        renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

        title = df[FI_VFName]
        title ||= v
        column = SubjTreeViewColumn.new(title, renderer )  #, {:text => i}

        #p v
        #p ind = panobject.def_fields.index_of {|f| f[0]==v }
        #p fld = panobject.def_fields[ind]

        column.tab_ind = tab_ind
        #column.sort_column_id = ind
        #p column.ind = i
        #p column.fld = fld
        #panhash_col = i if (v=='panhash')
        column.resizable = true
        column.reorderable = true
        column.clickable = true
        treeview.append_column(column)
        column.signal_connect('clicked') do |col|
          p 'sort clicked'
        end
        column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
          color = 'black'
          col = tvc.tab_ind
          panobject = tvc.tree_view.panobject
          row = tvc.tree_view.sel[iter.path.indices[0]]
          val = row[col] if row
          if val
            fdesc = panobject.tab_fields[col][TI_Desc]
            if fdesc.is_a? Array
              view = nil
              if param_view_col and (fdesc[FI_Id]=='value')
                view = row[param_view_col] if row
              else
                view = fdesc[FI_View]
              end
              val, color = PandoraUtils.val_to_view(val, nil, view, false)
            else
              val = val.to_s
            end
            val = val[0,46]
          else
            val = ''
          end
          renderer.foreground = color
          renderer.text = val
        end
      end
    end
    treeview.signal_connect('row_activated') do |tree_view, path, column|
      if single
        act_panobject(tree_view, 'Edit')
      else
        dialog = pbox.parent.parent.parent
        dialog.okbutton.activate
      end
    end

    pbox ||= PanobjBox.new
    pbox.name = panobject.ider
    pbox.treeview = treeview

    list_sw = Gtk::ScrolledWindow.new(nil, nil)
    list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
    list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    list_sw.border_width = 0
    list_sw.add(treeview)

    hbox = Gtk::HBox.new

    title = _('Update')
    pbox.update_btn = Gtk::ToolButton.new(Gtk::Stock::REFRESH, title)
    update_btn = pbox.update_btn
    update_btn.tooltip_text = title
    update_btn.label = title
    update_btn.signal_connect('clicked') do |*args|
      path, column = treeview.cursor
      store.clear
      panobject.class.modified = false if panobject.class.modified
      sel = panobject.select(nil, false, nil, panobject.sort)
      param_view_col = nil
      param_view_col = sel[0].size if (panobject.ider=='Parameter') and sel[0]
      sel.each do |row|
        iter = store.append
        id = row[0].to_i
        iter[0] = id
        if param_view_col
          type = panobject.field_val('type', row)
          setting = panobject.field_val('setting', row)
          ps = PandoraUtils.decode_param_setting(setting)
          view = ps['view']
          view ||= PandoraUtils.pantype_to_view(type)
          row[param_view_col] = view
        end
      end
      treeview.sel = sel
      if path or (treeview.sel.size>0)
        path ||= Gtk::TreePath.new(treeview.sel.size-1)
        treeview.set_cursor(path, nil, false)
      end
      p 'treeview is updated: '+panobject.ider
      treeview.grab_focus
    end
    update_btn.clicked

    pbox.auto_btn = nil
    if single
      pbox.auto_btn = SafeCheckButton.new(_('auto'), true)
      auto_btn = pbox.auto_btn
      auto_btn.safe_signal_clicked do |widget|
        update_treeview_if_need(pbox)
      end
      auto_btn.safe_set_active(true)
    end

    hbox.pack_start(update_btn, false, true, 0)
    hbox.pack_start(auto_btn, false, true, 0) if single

    pbox.pack_start(hbox, false, false, 0)
    pbox.pack_start(list_sw, true, true, 0)

    if auto_create and treeview.sel and (treeview.sel.size==0)
      treeview.auto_create = true
      treeview.signal_connect('map') do |widget, event|
        if treeview.auto_create
          act_panobject(treeview, 'Create')
          treeview.auto_create = false
        end
      end
      auto_create = false
    end

    if single
      #p 'single: widget='+widget.inspect
      if widget.is_a? Gtk::ImageMenuItem
        animage = widget.image
      elsif widget.is_a? Gtk::ToolButton
        animage = widget.icon_widget
      else
        animage = nil
      end
      image = nil
      if animage
        image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
        image.set_padding(2, 0)
      end

      label_box = TabLabelBox.new(image, panobject.pname, pbox, false, 0) do
        store.clear
        treeview.destroy
      end

      page = notebook.append_page(pbox, label_box)
      notebook.set_tab_reorderable(pbox, true)
      pbox.show_all
      notebook.page = notebook.n_pages-1

      #pbox.update_if_need

      treeview.grab_focus
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::NEW, _('Create'), 'Insert'], treeview))
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT, _('Edit'), 'Return'], treeview))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete'], treeview))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Dialog', Gtk::Stock::MEDIA_PLAY, _('Dialog'), '<control>D'], treeview))
    menu.append(create_menu_item(['Opinion', Gtk::Stock::JUMP_TO, _('Opinions'), '<control>BackSpace'], treeview))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N'], treeview))
    menu.append(create_menu_item(['Relate', Gtk::Stock::INDEX, _('Relate'), '<control>R'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Convert', Gtk::Stock::CONVERT, _('Convert')], treeview))
    menu.append(create_menu_item(['Import', Gtk::Stock::OPEN, _('Import')], treeview))
    menu.append(create_menu_item(['Export', Gtk::Stock::SAVE, _('Export')], treeview))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button_press_event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

    treeview.signal_connect('key-press-event') do |widget, event|
      res = true
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
        act_panobject(treeview, 'Edit')
      elsif (event.keyval==Gdk::Keyval::GDK_Insert)
        if event.state.control_mask?
          act_panobject(treeview, 'Copy')
        else
          act_panobject(treeview, 'Create')
        end
      elsif (event.keyval==Gdk::Keyval::GDK_Delete)
        act_panobject(treeview, 'Delete')
      elsif event.state.control_mask?
        if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
          act_panobject(treeview, 'Dialog')
        else
          res = false
        end
      else
        res = false
      end
      res
    end
    auto_create
  end

  # Update period for treeview tables
  # RU: Период обновления для таблиц
  TAB_UPD_PERIOD = 2   #second

  $treeview_thread = nil

  # Launch update thread for a table of the panobjbox
  # RU: Запускает поток обновления таблицы панобъекта
  def self.update_treeview_if_need(panobjbox=nil)
    if $treeview_thread
      $treeview_thread.exit if $treeview_thread.alive?
      $treeview_thread = nil
    end
    if (panobjbox.is_a? PanobjBox) and panobjbox.auto_btn and panobjbox.auto_btn.active?
      $treeview_thread = Thread.new do
        while panobjbox and (not panobjbox.destroyed?) and panobjbox.treeview \
        and (not panobjbox.treeview.destroyed?) and $window.visible?
          #p 'update_treeview_if_need: '+panobjbox.treeview.panobject.ider
          if panobjbox.treeview.panobject.class.modified
            #p 'update_treeview_if_need: modif='+panobjbox.treeview.panobject.class.modified.inspect
            panobjbox.update_btn.clicked
          end
          sleep(TAB_UPD_PERIOD)
        end
      end
    end
  end

  $media_buf_size = 50
  $send_media_queues = []
  $send_media_rooms = {}

  # Take pointer index for sending by room
  # RU: Взять индекс указателя для отправки по id комнаты
  def self.set_send_ptrind_by_room(room_id)
    ptr = nil
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = true
        ptr = ptr[1]
      else
        ptr = $send_media_rooms.size
        $send_media_rooms[room_id] = [true, ptr]
      end
    end
    ptr
  end

  # Check pointer index for sending by room
  # RU: Проверить индекс указателя для отправки по id комнаты
  def self.get_send_ptrind_by_room(room_id)
    ptr = nil
    if room_id
      set_ptr = $send_media_rooms[room_id]
      if set_ptr and set_ptr[0]
        ptr = set_ptr[1]
      end
    end
    ptr
  end

  # Clear pointer index for sending for room
  # RU: Сбросить индекс указателя для отправки для комнаты
  def self.nil_send_ptrind_by_room(room_id)
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = false
      end
    end
    res = $send_media_rooms.select{|room,ptr| ptr[0] }
    res.size
  end

  $key_watch_lim   = 5
  $sign_watch_lim  = 5

  # Get person panhash by any panhash
  # RU: Получить панхэш персоны по произвольному панхэшу
  def self.extract_targets_from_panhash(targets, panhashes)
    persons, keys, nodes = targets
    panhashes = [panhashes] if not panhashes.is_a? Array
    #p '--extract_targets_from_panhash  targets='+targets.inspect
    panhashes.each do |panhash|
      if (panhash.is_a? String) and (panhash.bytesize>0)
        kind = PandoraUtils.kind_from_panhash(panhash)
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          if panobjectclass <= PandoraModel::Person
            persons << panhash
          elsif panobjectclass <= PandoraModel::Node
            nodes << panhash
          else
            if panobjectclass <= PandoraModel::Created
              model = PandoraUtils.get_model(panobjectclass.ider)
              filter = {:panhash=>panhash}
              sel = model.select(filter, false, 'creator')
              if sel and sel.size>0
                sel.each do |row|
                  persons << row[0]
                end
              end
            end
          end
        end
      end
    end
    persons.uniq!
    persons.compact!
    if (keys.size == 0) and (nodes.size > 0)
      nodes.uniq!
      nodes.compact!
      model = PandoraUtils.get_model('Node')
      nodes.each do |node|
        sel = model.select({:panhash=>node}, false, 'key_hash')
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
    end
    keys.uniq!
    keys.compact!
    if (persons.size == 0) and (keys.size > 0)
      kmodel = PandoraUtils.get_model('Key')
      smodel = PandoraUtils.get_model('Sign')
      keys.each do |key|
        sel = kmodel.select({:panhash=>key}, false, 'creator', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            persons << row[0]
          end
        end
        sel = smodel.select({:key_hash=>key}, false, 'creator', 'modified DESC', $sign_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            persons << row[0]
          end
        end
      end
      persons.uniq!
      persons.compact!
    end
    if nodes.size == 0
      model = PandoraUtils.get_model('Key')
      persons.each do |person|
        sel = model.select({:creator=>person}, false, 'panhash', 'modified DESC', $key_watch_lim)
        if sel and (sel.size>0)
          sel.each do |row|
            keys << row[0]
          end
        end
      end
      if keys.size == 0
        model = PandoraUtils.get_model('Sign')
        persons.each do |person|
          sel = model.select({:creator=>person}, false, 'key_hash', 'modified DESC', $sign_watch_lim)
          if sel and (sel.size>0)
            sel.each do |row|
              keys << row[0]
            end
          end
        end
      end
      keys.uniq!
      keys.compact!
      model = PandoraUtils.get_model('Node')
      keys.each do |key|
        sel = model.select({:key_hash=>key}, false, 'panhash')
        if sel and (sel.size>0)
          sel.each do |row|
            nodes << row[0]
          end
        end
      end
      #p '[keys, nodes]='+[keys, nodes].inspect
      #p 'targets3='+targets.inspect
    end
    nodes.uniq!
    nodes.compact!
    nodes.size
  end

  # Construct room id
  # RU: Создать идентификатор комнаты
  def self.construct_room_id(persons)
    res = nil
    if (persons.is_a? Array) and (persons.size>0)
      sha1 = Digest::SHA1.new
      persons.each do |panhash|
        sha1.update(panhash)
      end
      res = sha1.digest
    end
    res
  end

  # Find active sender
  # RU: Найти активного отправителя
  def self.find_another_active_sender(not_this=nil)
    res = nil
    $window.notebook.children.each do |child|
      if (child != not_this) and (child.is_a? DialogScrollWin) and child.vid_button.active?
        return child
      end
    end
    res
  end

  # Get view parameters
  # RU: Взять параметры вида
  def self.get_view_params
    $load_history_count = PandoraUtils.get_param('load_history_count')
    $sort_history_mode = PandoraUtils.get_param('sort_history_mode')
  end

  # Get main parameters
  # RU: Взять основные параметры
  def self.get_main_params
    get_view_params
  end

  # About dialog hooks
  # RU: Обработчики диалога "О программе"
  Gtk::AboutDialog.set_url_hook do |about, link|
    if PandoraUtils.os_family=='windows' then a1='start'; a2='' else a1='xdg-open'; a2=' &' end;
    system(a1+' '+link+a2)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    if PandoraUtils.os_family=='windows' then a1='start'; a2='' else a1='xdg-email'; a2=' &' end;
    system(a1+' '+link+a2)
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.version = '0.4'
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.authors = [_('Michael Galyuk')+' <robux@mail.ru>']
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('P2P folk network')
    dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
    begin
      file = File.open(File.join($pandora_root_dir, 'LICENSE.TXT'), 'r')
      gpl_text = '================='+_('Full text')+" LICENSE.TXT==================\n"+file.read
      file.close
    rescue
      gpl_text = _('Full text is in the file')+' LICENSE.TXT.'
    end
    dlg.license = _("Pandora is licensed under GNU GPLv2.\n"+
      "\nFundamentals:\n"+
      "- program code is open, distributed free and without warranty;\n"+
      "- author does not require you money, but demands respect authorship;\n"+
      "- you can change the code, sent to the authors for inclusion in the next release;\n"+
      "- your own release you must distribute with another name and only licensed under GPL;\n"+
      "- if you do not understand the GPL or disagree with it, you have to uninstall the program.\n\n")+gpl_text
    dlg.website = 'https://github.com/Novator/Pandora'
    dlg.program_name = dlg.name
    dlg.skip_taskbar_hint = true
    dlg.run
    dlg.destroy
    $window.present
  end

  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(panhashes, nodehash=nil)
    sw = nil
    p 'show_talk_dialog: [panhashes, nodehash]='+[panhashes, nodehash].inspect
    targets = [[], [], []]
    persons, keys, nodes = targets
    if nodehash and (panhashes.is_a? String)
      persons << panhashes
      nodes << nodehash
    else
      extract_targets_from_panhash(targets, panhashes)
    end
    targets.each do |list|
      list.sort!
      list.uniq!
      list.compact!
    end
    p 'targets='+targets.inspect

    if (persons.size>0) or (nodes.size>0) or (keys.size>0)
      room_id = construct_room_id(persons)
      if nodehash
        creator = PandoraCrypto.current_user_or_key(true)
        if (persons.size==1) and (persons[0]==creator)
          room_id[-1] = (room_id[-1].ord ^ 1).chr
        end
      end
      p 'room_id='+room_id.inspect
      $window.notebook.children.each do |child|
        if (child.is_a? DialogScrollWin) and (child.room_id==room_id)
          child.targets = targets
          child.online_button.safe_set_active(nodehash != nil)
          child.online_button.inconsistent = false
          $window.notebook.page = $window.notebook.children.index(child) if (not nodehash)
          sw = child
          break
        end
      end
      if not sw
        sw = DialogScrollWin.new(nodehash, room_id, targets)
      end
    elsif (not nodehash)
      mes = ''
      mes = _('node') if nodes.size == 0
      if persons.size == 0
        mes << ', ' if mes.size>0
        mes << _('person')
      end
      dialog = Gtk::MessageDialog.new($window, \
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
        Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
        mes = _('No one')+' '+mes+' '+_('is not found')+".\n"+_('Add nodes and do hunt'))
      dialog.title = _('Note')
      dialog.default_response = Gtk::Dialog::RESPONSE_OK
      dialog.icon = $window.icon
      if (dialog.run == Gtk::Dialog::RESPONSE_OK)
        PandoraGtk.show_panobject_list(PandoraModel::Node, nil, nil, true)
      end
      dialog.destroy
    end
    sw
  end

  # Showing search panel
  # RU: Показать панель поиска
  def self.show_search_panel(text=nil)
    sw = SearchBox.new(text)

    image = Gtk::Image.new(Gtk::Stock::FIND, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Search'), sw, false, 0) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show profile panel
  # RU: Показать панель профиля
  def self.show_profile_panel(a_person=nil)
    a_person0 = a_person
    a_person ||= PandoraCrypto.current_user_or_key(true, true)

    return if not a_person

    $window.notebook.children.each do |child|
      if (child.is_a? ProfileScrollWin) and (child.person == a_person)
        $window.notebook.page = $window.notebook.children.index(child)
        return
      end
    end

    short_name = ''
    aname, afamily = nil, nil
    if a_person0
      mykey = nil
      mykey = PandoraCrypto.current_key(false, false) if (not a_person0)
      if mykey and mykey[PandoraCrypto::KV_Creator] and (mykey[PandoraCrypto::KV_Creator] != a_person)
        aname, afamily = PandoraCrypto.name_and_family_of_person(mykey, a_person)
      else
        aname, afamily = PandoraCrypto.name_and_family_of_person(nil, a_person)
      end

      short_name = afamily[0, 15] if afamily
      short_name = aname[0]+'. '+short_name if aname
    end

    sw = ProfileScrollWin.new(a_person)

    hpaned = Gtk::HPaned.new
    hpaned.border_width = 2
    sw.add_with_viewport(hpaned)


    list_sw = Gtk::ScrolledWindow.new(nil, nil)
    list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
    list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

    list_store = Gtk::ListStore.new(String)

    user_iter = list_store.append
    user_iter[0] = _('Profile')
    user_iter = list_store.append
    user_iter[0] = _('Events')

    # create tree view
    list_tree = Gtk::TreeView.new(list_store)
    #list_tree.rules_hint = true
    #list_tree.search_column = CL_Name

    renderer = Gtk::CellRendererText.new
    column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
    column.set_sort_column_id(0)
    list_tree.append_column(column)

    #renderer = Gtk::CellRendererText.new
    #column = Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
    #column.set_sort_column_id(1)
    #list_tree.append_column(column)

    list_tree.signal_connect('row_activated') do |tree_view, path, column|
      # download and go to record
    end

    list_sw.add(list_tree)

    hpaned.pack1(list_sw, false, true)
    hpaned.pack2(Gtk::Label.new('test'), true, true)
    list_sw.show_all


    image = Gtk::Image.new(Gtk::Stock::HOME, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    short_name = _('Profile') if not((short_name.is_a? String) and (short_name.size>0))

    label_box = TabLabelBox.new(image, short_name, sw, false, 0) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show session list
  # RU: Показать список сеансов
  def self.show_session_panel
    $window.notebook.children.each do |child|
      if (child.is_a? SessionScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        child.update_btn.clicked
        return
      end
    end
    sw = SessionScrollWin.new

    image = Gtk::Image.new(Gtk::Stock::JUSTIFY_FILL, Gtk::IconSize::MENU)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Sessions'), sw, false, 0) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show fish list
  # RU: Показать список рыб
  def self.show_fish_panel
    hpaned = $window.fish_hpaned
    list_sw = hpaned.children[0]
    if list_sw.allocation.width <= 24 #hpaned.position <= 20
      list_sw.width_request = 250 if list_sw.width_request <= 24
      hpaned.position = list_sw.width_request
      list_sw.update_btn.clicked
    else
      list_sw.width_request = list_sw.allocation.width
      hpaned.position = 0
    end
    $window.correct_fish_btn_state
    #$window.notebook.children.each do |child|
    #  if (child.is_a? FishScrollWin)
    #    $window.notebook.page = $window.notebook.children.index(child)
    #    child.update_btn.clicked
    #    return
    #  end
    #end
    #sw = FishScrollWin.new

    #image = Gtk::Image.new(Gtk::Stock::JUSTIFY_LEFT, Gtk::IconSize::MENU)
    #image.set_padding(2, 0)
    #label_box = TabLabelBox.new(image, _('Fishes'), sw, false, 0) do
    #  #sw.destroy
    #end
    #page = $window.notebook.append_page(sw, label_box)
    #sw.show_all
    #$window.notebook.page = $window.notebook.n_pages-1
  end

  # Show fisher list
  # RU: Показать список рыбаков
  def self.show_fisher_panel
    $window.notebook.children.each do |child|
      if (child.is_a? FisherScrollWin)
        $window.notebook.page = $window.notebook.children.index(child)
        child.update_btn.clicked
        return
      end
    end
    sw = FisherScrollWin.new

    image = Gtk::Image.new(Gtk::Stock::JUSTIFY_RIGHT, Gtk::IconSize::MENU)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Fishers'), sw, false, 0) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Status icon
  # RU: Иконка в трее
  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon, :play_sounds, :online, :hide_on_minimize

    # Create status icon
    # RU: Создает иконку в трее
    def initialize(a_update_win_icon=false, a_flash_on_new=true, \
    a_flash_interval=0, a_play_sounds=true, a_hide_on_minimize=true)
      super()

      @online = false
      @main_icon = nil
      if $window.icon
        @main_icon = $window.icon
      else
        @main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end
      @base_icon = @main_icon

      @online_icon = nil
      begin
        @online_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'online.ico'))
      rescue Exception
      end
      if not @online_icon
        @online_icon = $window.render_icon(Gtk::Stock::INFO, Gtk::IconSize::LARGE_TOOLBAR)
      end

      begin
        @message_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'message.ico'))
      rescue Exception
      end
      if not @message_icon
        @message_icon = $window.render_icon(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::LARGE_TOOLBAR)
      end

      @update_win_icon = a_update_win_icon
      @flash_on_new = a_flash_on_new
      @flash_interval = (a_flash_interval.to_f*1000).round
      @flash_interval = 800 if (@flash_interval<100)
      @play_sounds = a_play_sounds
      @hide_on_minimize = a_hide_on_minimize

      @message = nil
      @flash = false
      @flash_status = 0
      update_icon

      atitle = $window.title
      set_title(atitle)
      set_tooltip(atitle)

      #set_blinking(true)
      signal_connect('activate') do
        icon_activated
      end

      signal_connect('popup-menu') do |widget, button, activate_time|
        @menu ||= create_menu
        @menu.popup(nil, nil, button, activate_time)
      end
    end

    # Create and show popup menu
    # RU: Создает и показывает всплывающее меню
    def create_menu
      menu = Gtk::Menu.new

      checkmenuitem = Gtk::CheckMenuItem.new(_('Flash on new'))
      checkmenuitem.active = @flash_on_new
      checkmenuitem.signal_connect('activate') do |w|
        @flash_on_new = w.active?
        set_message(@message)
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Update window icon'))
      checkmenuitem.active = @update_win_icon
      checkmenuitem.signal_connect('activate') do |w|
        @update_win_icon = w.active?
        $window.icon = @base_icon
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Play sounds'))
      checkmenuitem.active = @play_sounds
      checkmenuitem.signal_connect('activate') do |w|
        @play_sounds = w.active?
      end
      menu.append(checkmenuitem)

      checkmenuitem = Gtk::CheckMenuItem.new(_('Hide on minimize'))
      checkmenuitem.active = @hide_on_minimize
      checkmenuitem.signal_connect('activate') do |w|
        @hide_on_minimize = w.active?
      end
      menu.append(checkmenuitem)

      menuitem = Gtk::ImageMenuItem.new(Gtk::Stock::PROPERTIES)
      alabel = menuitem.children[0]
      alabel.set_text(_('All parameters')+'..', true)
      menuitem.signal_connect('activate') do |w|
        icon_activated(false, true)
        PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
      end
      menu.append(menuitem)

      menuitem = Gtk::SeparatorMenuItem.new
      menu.append(menuitem)

      menuitem = Gtk::MenuItem.new(_('Show/Hide'))
      menuitem.signal_connect('activate') do |w|
        icon_activated(false)
      end
      menu.append(menuitem)

      menuitem = Gtk::ImageMenuItem.new(Gtk::Stock::QUIT)
      alabel = menuitem.children[0]
      alabel.set_text(_('_Quit'), true)
      menuitem.signal_connect('activate') do |w|
        self.set_visible(false)
        $window.destroy
      end
      menu.append(menuitem)

      menu.show_all
      menu
    end

    # Set status "online"
    # RU: Задаёт статус "онлайн"
    def set_online(state=nil)
      base_icon0 = @base_icon
      if state
        @base_icon = @online_icon
      elsif state==false
        @base_icon = @main_icon
      end
      update_icon
    end

    # Set status "message comes"
    # RU: Задаёт статус "есть сообщение"
    def set_message(message=nil)
      if (message.is_a? String) and (message.size>0)
        @message = message
        set_tooltip(message)
        set_flash(@flash_on_new)
      else
        @message = nil
        set_tooltip($window.title)
        set_flash(false)
      end
    end

    # Set flash mode
    # RU: Задаёт мигание
    def set_flash(flash=true)
      @flash = flash
      if flash
        @flash_status = 1
        if not @timer
          timeout_func
        end
      else
        @flash_status = 0
      end
      update_icon
    end

    # Update icon
    # RU: Обновляет иконку
    def update_icon
      stat_icon = nil
      if @message and ((not @flash) or (@flash_status==1))
        stat_icon = @message_icon
      else
        stat_icon = @base_icon
      end
      self.pixbuf = stat_icon if (self.pixbuf != stat_icon)
      if @update_win_icon
        $window.icon = stat_icon if $window.visible? and ($window.icon != stat_icon)
      else
        $window.icon = @main_icon if ($window.icon != @main_icon)
      end
    end

    # Set timer on a flash step
    # RU: Ставит таймер на шаг мигания
    def timeout_func
      @timer = GLib::Timeout.add(@flash_interval) do
        next_step = true
        if @flash_status == 0
          @flash_status = 1
        else
          @flash_status = 0
          next_step = false if not @flash
        end
        update_icon
        @timer = nil if not next_step
        next_step
      end
    end

    # Action on icon click
    # RU: Действия при нажатии на иконку
    def icon_activated(top_sens=true, force_show=false)
      #$window.skip_taskbar_hint = false
      if $window.visible? and (not force_show)
        if (not top_sens) or ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
          $window.hide
        else
          $window.do_menu_act('Activate')
        end
      else
        $window.do_menu_act('Activate')
        update_icon if @update_win_icon
        if @message and (not force_show)
          page = $window.notebook.page
          if (page >= 0)
            cur_page = $window.notebook.get_nth_page(page)
            if cur_page.is_a? PandoraGtk::DialogScrollWin
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($window.notebook.n_pages == 0)
          end
        end
      end
    end
  end  #--PandoraStatusIcon

  # Captcha panel
  # RU: Панель с капчой
  class CaptchaHPaned < Gtk::HPaned
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
        @csw = Gtk::ScrolledWindow.new(nil, nil)
        csw = @csw

        csw.signal_connect('destroy-event') do
          show_captcha(srckey)
        end

        @vbox = Gtk::VBox.new
        vbox = @vbox

        csw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
        csw.add_with_viewport(vbox)

        pixbuf_loader = Gdk::PixbufLoader.new
        pixbuf_loader.last_write(captcha_buf) if captcha_buf

        label = Gtk::Label.new(_('Far node'))
        vbox.pack_start(label, false, false, 2)
        entry = Gtk::Entry.new
        node_text = PandoraUtils.bytes_to_hex(srckey)
        node_text = node if (not node_text) or (node_text=='')
        node_text ||= ''
        entry.text = node_text
        entry.editable = false
        vbox.pack_start(entry, false, false, 2)

        image = Gtk::Image.new(pixbuf_loader.pixbuf)
        vbox.pack_start(image, false, false, 2)

        clue_text ||= ''
        clue, length, symbols = clue_text.split('|')
        #p '    [clue, length, symbols]='+[clue, length, symbols].inspect

        len = 0
        begin
          len = length.to_i if length
        rescue
        end

        label = Gtk::Label.new(_('Enter text from picture'))
        vbox.pack_start(label, false, false, 2)

        captcha_entry = PandoraGtk::MaskEntry.new
        captcha_entry.max_length = len
        if symbols
          mask = symbols.downcase+symbols.upcase
          captcha_entry.mask = mask
        end

        okbutton = Gtk::Button.new(Gtk::Stock::OK)
        okbutton.signal_connect('clicked') do
          text = captcha_entry.text
          yield(text) if block_given?
          show_captcha(srckey)
        end

        cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
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
        PandoraGtk.hack_enter_bug(captcha_entry)

        ew = 150
        if len>0
          str = label.text
          label.text = 'W'*(len+1)
          ew,lh = label.size_request
          label.text = str
        end

        captcha_entry.width_request = ew
        align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
        align.add(captcha_entry)
        vbox.pack_start(align, false, false, 2)
        #capdialog.def_widget = entry

        hbox = Gtk::HBox.new
        hbox.pack_start(okbutton, true, true, 2)
        hbox.pack_start(cancelbutton, true, true, 2)

        vbox.pack_start(hbox, false, false, 2)

        if clue
          label = Gtk::Label.new(_(clue))
          vbox.pack_start(label, false, false, 2)
        end
        if length
          label = Gtk::Label.new(_('Length')+'='+length.to_s)
          vbox.pack_start(label, false, false, 2)
        end
        if symbols
          sym_text = _('Symbols')+': '+symbols.to_s
          i = 30
          while i<sym_text.size do
            sym_text = sym_text[0,i]+"\n"+sym_text[i+1..-1]
            i += 31
          end
          label = Gtk::Label.new(sym_text)
          vbox.pack_start(label, false, false, 2)
        end

        csw.border_width = 1;
        csw.set_size_request(250, -1)
        self.border_width = 2
        self.pack2(csw, true, true)  #hpaned3                                      9
        csw.show_all
        full_width = $window.allocation.width
        self.position = full_width-250 #self.max_position #@csw.width_request
        PandoraGtk.hack_grab_focus(captcha_entry)
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

  # Main window
  # RU: Главное окно
  class MainWindow < Gtk::Window
    attr_accessor :hunter_count, :listener_count, :fisher_count, :log_view, :notebook, \
      :cvpaned, :pool, :focus_timer, :title_view, :do_on_show, :fish_hpaned

    include PandoraUtils

    # Update status of connections
    # RU: Обновить состояние подключений
    def update_conn_status(conn, session_type, diff_count)
      #if session_type==0
      @hunter_count += diff_count
      #elsif session_type==1
      #  @listener_count += diff_count
      #else
      #  @fisher_count += diff_count
      #end
      set_status_field(SF_Conn, hunter_count.to_s+'/'+listener_count.to_s+'/'+fisher_count.to_s)
      online = ((@hunter_count>0) or (@listener_count>0) or (@fisher_count>0))
      $statusicon.set_online(online)
    end

    $toggle_buttons = []

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_lis_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Listen]
      if tool_btn
        lis_act = ($tcp_listen_thread != nil) or ($udp_listen_thread != nil)
        tool_btn.safe_set_active(lis_act)
      end
    end

    # Change hunter button state
    # RU: Изменить состояние кнопки охотника
    def correct_hunt_btn_state
      tool_btn = $toggle_buttons[SF_Hunt]
      tool_btn.safe_set_active($hunter_thread != nil) if tool_btn
    end

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_fish_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Fish]
      if tool_btn
        hpaned = $window.fish_hpaned
        list_sw = hpaned.children[0]
        tool_btn.safe_set_active(hpaned.position > 24)
      end
    end

    # Show notice status
    # RU: Показать уведомления в статусе
    def show_notice(change=nil)
      if change
        PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
      end
      PandoraNet.get_notice_params
      notice = PandoraModel.transform_trust($notice_trust, false)
      notice = ((notice*10.0).round/10.0).to_s
      notice += '/'+$notice_depth.to_s
      set_status_field(PandoraGtk::SF_Notice, notice, nil, false)
    end

    $statusbar = nil
    $status_fields = []

    # Add field to statusbar
    # RU: Добавляет поле в статусбар
    def add_status_field(index, text)
      $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0) if ($status_fields != [])
      btn = Gtk::Button.new(text)
      btn.relief = Gtk::RELIEF_NONE
      if block_given?
        btn.signal_connect('clicked') do |*args|
          yield(*args)
        end
      end
      $statusbar.pack_start(btn, false, false, 0)
      $status_fields[index] = btn
    end

    # Set properties of fiels in statusbar
    # RU: Задаёт свойства поля в статусбаре
    def set_status_field(index, text, enabled=nil, toggle=nil)
      btn = $status_fields[index]
      if btn
        str = _(text)
        str = _('Version') + ': ' + str if (index==SF_Update)
        btn.label = str
        if (enabled != nil)
          btn.sensitive = enabled
        end
        if (toggle != nil) and $toggle_buttons[index]
          $toggle_buttons[index].safe_set_active(toggle)
        end
      end
    end

    # Get fiels of statusbar
    # RU: Возвращает поле статусбара
    def get_status_field(index)
      $status_fields[index]
    end

    TV_Name    = 0
    TV_NameF   = 1
    TV_Family  = 2
    TV_NameN   = 3

    MaxTitleLen = 15

    # Construct room title
    # RU: Задаёт осмысленный заголовок окна
    def construct_room_title(dialog, check_all=true)
      res = 'unknown'
      persons = dialog.targets[CSI_Persons]
      if (persons.is_a? Array) and (persons.size>0)
        res = ''
        persons.each_with_index do |person, i|
          aname, afamily = dialog.get_name_and_family(i)
          addname = ''
          case @title_view
            when TV_Name, TV_NameN
              if (aname.size==0)
                addname << afamily
              else
                addname << aname
              end
            when TV_NameF
              if (aname.size==0)
                addname << afamily
              else
                addname << aname
                addname << afamily[0] if afamily[0]
              end
            when TV_Family
              if (afamily.size==0)
                addname << aname
              else
                addname << afamily
              end
          end
          if (addname.size>0)
            res << ',' if (res.size>0)
            res << addname
          end
        end
        res = 'unknown' if (res.size==0)
        if res.size>MaxTitleLen
          res = res[0, MaxTitleLen-1]+'..'
        end
        tab_widget = $window.notebook.get_tab_label(dialog)
        tab_widget.label.text = res if tab_widget
        #p 'title_view, res='+[@title_view, res].inspect
        if check_all
          @title_view=TV_Name if (@title_view==TV_NameN)
          has_conflict = true
          while has_conflict
            has_conflict = false
            names = Array.new
            $window.notebook.children.each do |child|
              if (child.is_a? DialogScrollWin)
                tab_widget = $window.notebook.get_tab_label(child)
                if tab_widget
                  tit = tab_widget.label.text
                  if names.include? tit
                    has_conflict = true
                    break
                  else
                    names << tit
                  end
                end
              end
            end
            if has_conflict
              if (@title_view < TV_NameN)
                @title_view += 1
              else
                has_conflict = false
              end
              #p '@title_view='+@title_view.inspect
              names = Array.new
              $window.notebook.children.each do |child|
                if (child.is_a? DialogScrollWin)
                  sn = construct_room_title(child, false)
                  if (@title_view == TV_NameN)
                    names << sn
                    c = names.count(sn)
                    sn = sn+c.to_s if c>1
                    tab_widget = $window.notebook.get_tab_label(child)
                    tab_widget.label.text = sn if tab_widget
                  end
                end
              end
            end
          end
        end
      end
      res
    end

    # Export table to file
    # RU: Выгрузить таблицу в файл
    def export_table(panobject)

      ider = panobject.ider
      filename = File.join($pandora_files_dir, ider+'.csv')
      separ = '|'

      File.open(filename, 'w') do |file|
        sel = panobject.select(nil, false, nil, panobject.sort)
        sel.each do |row|
          line = ''
          row.each_with_index do |cell,i|
            line += separ if i>0
            if cell
              begin
                #line += '"' + cell.to_s + '"' if cell
                line += cell.to_s
              rescue
              end
            end
          end
          file.puts(line)
        end
      end

      PandoraUtils.log_message(LM_Info, _('Table exported')+': '+filename)
    end

    # Menu event handler
    # RU: Обработчик события меню
    def do_menu_act(command, treeview=nil)
      widget = nil
      if not command.is_a? String
        widget = command
        command = widget.name
      end
      case command
        when 'Quit'
          self.destroy
        when 'Activate'
          self.deiconify
          #self.visible = true if (not self.visible?)
          self.present
        when 'Hide'
          #self.iconify
          self.hide
        when 'About'
          PandoraGtk.show_about
        when 'Close'
          if notebook.page >= 0
            page = notebook.get_nth_page(notebook.page)
            tab = notebook.get_tab_label(page)
            close_btn = tab.children[tab.children.size-1].children[0]
            close_btn.clicked
          end
        when 'Create','Edit','Delete','Copy', 'Dialog', 'Convert', 'Import', 'Export'
          p 'act_panobject()'
          if (not treeview) and (notebook.page >= 0)
            sw = notebook.get_nth_page(notebook.page)
            treeview = sw.children[0]
          end
          if treeview
            if command=='Convert'
              panobject = treeview.panobject
              panobject.update(nil, nil, nil)
              panobject.class.tab_fields(true)
            elsif command=='Import'
              p 'import'
            elsif command=='Export'
              export_table(treeview.panobject)
            else
              PandoraGtk.act_panobject(treeview, command)
            end
          end
        when 'Listen'
          PandoraNet.start_or_stop_listen
        when 'Hunt'
          PandoraNet.hunt_nodes
        when 'Notice'
          $window.show_notice(true)
        when 'Authorize'
          key = PandoraCrypto.current_key(false, false)
          if key and $listen_thread
            PandoraNet.start_or_stop_listen
          end
          key = PandoraCrypto.current_key(true)
        when 'Wizard'
          from_time = Time.now.to_i - 5*24*3600
          trust = 0.5
          #list = PandoraModel.public_records(nil, nil, nil, 1.chr)
          #list = PandoraModel.follow_records
          #list = PandoraModel.get_panhashes_by_kinds([1,11], from_time)
          list = PandoraModel.created_records(nil, nil, nil, nil)
          p 'list='+list.inspect

          #if list
          #  list.each do |panhash|
          #    p '----------------'
          #    kind = PandoraUtils.kind_from_panhash(panhash)
          #    p [panhash, kind].inspect
          #    p res = PandoraModel.get_record_by_panhash(kind, panhash, true)
          #  end
          #end


          return


          p res44 = OpenSSL::Digest::RIPEMD160.new

          a = rand
          if a<0.33
            PandoraUtils.play_mp3('online')
          elsif a<0.66
            PandoraUtils.play_mp3('offline')
          else
            PandoraUtils.play_mp3('message')
          end
          return


          #p OpenSSL::Cipher::ciphers

          #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
          #cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
          #p 'cipher_hash16='+cipher_hash.to_s(16)
          #type_klen = KT_Rsa | KL_bit2048
          #passwd = '123'
          #p keys = generate_key(type_klen, cipher_hash, passwd)
          #type_klen = KT_Aes | KL_bit256
          #key_vec = generate_key(type_klen, cipher_hash, passwd)

          p data = 'Тестовое сообщение!'

          cipher_hash = PandoraCrypto.encode_cipher_and_hash(PandoraCrypto::KT_Rsa | \
            PandoraCrypto::KL_bit2048, PandoraCrypto::KH_None)
          p cipher_vec = PandoraCrypto.generate_key(PandoraCrypto::KT_Bf, cipher_hash)

          p 'initkey'
          p cipher_vec = PandoraCrypto.init_key(cipher_vec)
          p cipher_vec[PandoraCrypto::KV_Pub] = cipher_vec[PandoraCrypto::KV_Obj].random_iv

          p 'coded:'

          p data = PandoraCrypto.recrypt(cipher_vec, data, true)

          p 'decoded:'
          puts data = PandoraCrypto.recrypt(cipher_vec, data, false)

          #typ, count = encode_pson_type(PT_Str, 0x1FF)
          #p decode_pson_type(typ)

          #p pson = hash_to_namepson({:first_name=>'Ivan', :last_name=>'Inavov', 'ddd'=>555})
          #p hash = namepson_to_hash(pson)

          #p PandoraUtils.get_param('base_id')
        when 'Profile'
          PandoraGtk.show_profile_panel
        when 'Search'
          PandoraGtk.show_search_panel
        when 'Session'
          PandoraGtk.show_session_panel
        when 'Fish'
          PandoraGtk.show_fish_panel
        when 'Fisher'
          PandoraGtk.show_fisher_panel
        else
          panobj_id = command
          if PandoraModel.const_defined? panobj_id
            panobject_class = PandoraModel.const_get(panobj_id)
            PandoraGtk.show_panobject_list(panobject_class, widget)
          else
            PandoraUtils.log_message(LM_Warning, _('Menu handler is not defined yet')+' "'+panobj_id+'"')
          end
      end
    end

    # Menu structure
    # RU: Структура меню
    MENU_ITEMS =
      [[nil, nil, '_World'],
      ['Person', Gtk::Stock::ORIENTATION_PORTRAIT, 'People', '<control>E'],
      ['Community', nil, 'Communities'],
      ['Blob', Gtk::Stock::HARDDISK, 'Files', '<control>J'], #Gtk::Stock::FILE
      ['-', nil, '-'],
      ['City', nil, 'Towns'],
      ['Street', nil, 'Streets'],
      ['Address', nil, 'Addresses'],
      ['Contact', nil, 'Contacts'],
      ['Country', nil, 'States'],
      ['Language', nil, 'Languages'],
      ['Word', Gtk::Stock::SPELL_CHECK, 'Words'],
      ['Relation', nil, 'Relations'],
      ['-', nil, '-'],
      ['Opinion', nil, 'Opinions'],
      ['Task', nil, 'Tasks'],
      ['Message', nil, 'Messages'],
      [nil, nil, '_Business'],
      ['Advertisement', nil, 'Advertisements'],
      ['Transfer', nil, 'Transfers'],
      ['-', nil, '-'],
      ['Order', nil, 'Orders'],
      ['Deal', nil, 'Deals'],
      ['Waybill', nil, 'Waybills'],
      ['-', nil, '-'],
      ['Debenture', nil, 'Debentures'],
      ['Deposit', nil, 'Deposits'],
      ['Guarantee', nil, 'Guarantees'],
      ['Insurer', nil, 'Insurers'],
      ['-', nil, '-'],
      ['Product', nil, 'Products'],
      ['Service', nil, 'Services'],
      ['Currency', nil, 'Currency'],
      ['Storage', nil, 'Storages'],
      ['Estimate', nil, 'Estimates'],
      ['Contract', nil, 'Contracts'],
      ['Report', nil, 'Reports'],
      [nil, nil, '_Region'],
      ['Project', nil, 'Projects'],
      ['Resolution', nil, 'Resolutions'],
      ['Law', nil, 'Laws'],
      ['-', nil, '-'],
      ['Contribution', nil, 'Contributions'],
      ['Expenditure', nil, 'Expenditures'],
      ['-', nil, '-'],
      ['Offense', nil, 'Offenses'],
      ['Punishment', nil, 'Punishments'],
      ['-', nil, '-'],
      ['Resource', nil, 'Resources'],
      ['Delegation', nil, 'Delegations'],
      ['Registry', nil, 'Registry'],
      [nil, nil, '_Node'],
      ['Parameter', Gtk::Stock::PROPERTIES, 'Parameters'],
      ['-', nil, '-'],
      ['Key', Gtk::Stock::DIALOG_AUTHENTICATION, 'Keys'],
      ['Sign', nil, 'Signs'],
      ['Node', Gtk::Stock::NETWORK, 'Nodes'],
      ['Event', nil, 'Events'],
      ['Request', Gtk::Stock::SELECT_COLOR, 'Requests'],
      ['Session', Gtk::Stock::JUSTIFY_FILL, 'Sessions', '<control>S'],
      ['-', nil, '-'],
      ['Authorize', nil, 'Authorize', '<control>U'],
      ['Listen', Gtk::Stock::CONNECT, 'Listen', '<control>L', :check],
      ['Hunt', Gtk::Stock::REFRESH, 'Hunt', '<control>H', :check],
      ['Fish', Gtk::Stock::GO_FORWARD, 'Neighbors', '<control>N', :check],
      ['Search', Gtk::Stock::FIND, 'Search', '<control>T'],
      ['Exchange', nil, 'Exchange'],
      ['-', nil, '-'],
      ['Profile', Gtk::Stock::HOME, 'Profile'],
      ['Wizard', Gtk::Stock::PREFERENCES, 'Wizards'],
      ['-', nil, '-'],
      ['Close', Gtk::Stock::CLOSE, '_Close', '<control>W'],
      ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q'],
      ['-', nil, '-'],
      ['About', Gtk::Stock::ABOUT, '_About']
      ]

    # Fill main menu
    # RU: Заполнить главное меню
    def fill_menubar(menubar)
      menu = nil
      MENU_ITEMS.each do |mi|
        if mi[0]==nil or menu==nil
          menuitem = Gtk::MenuItem.new(_(mi[2]))
          menubar.append(menuitem)
          menu = Gtk::Menu.new
          menuitem.set_submenu(menu)
        else
          menuitem = PandoraGtk.create_menu_item(mi)
          menu.append(menuitem)
        end
      end
    end

    # Fill toolbar
    # RU: Заполнить панель инструментов
    def fill_main_toolbar(toolbar)
      MENU_ITEMS.each do |mi|
        stock = mi[1]
        if stock
          command = mi[0]
          label = mi[2]
          if command and (command != '-') and label and (label != '-')
            toggle = nil
            toggle = false if mi[4]
            btn = PandoraGtk.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
              do_menu_act(widget)
            end
            btn.name = command
            if (toggle != nil)
              index = nil
              case command
                when 'Listen'
                  index = SF_Listen
                when 'Hunt'
                  index = SF_Hunt
                when 'Fish'
                  index = SF_Fish
              end
              if index
                $toggle_buttons[index] = btn
                #btn.signal_emit_stop('clicked')
                #btn.signal_emit_stop('toggled')
                #btn.signal_connect('clicked') do |*args|
                #  p args
                #  true
                #end
              end
            end
          end
        end
      end
    end

    # Initialize scheduler
    # RU: Инициировать планировщик
    def init_scheduler(interval=nil)
      if (not @scheduler) and interval
        @scheduler_interval = interval if interval
        @scheduler_interval ||= 1000
        @scheduler = Thread.new do
          while ((@scheduler_interval.is_a? Integer) and @scheduler_interval>=100)
            next_step = true

            # Scheduler (task executer)
            Thread.new do
              message = 'Message here'
              #dialog = Gtk::MessageDialog.new($window, \
              #  Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
              #  Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
              #  message)
              #dialog.title = _('Task')
              #dialog.default_response = Gtk::Dialog::RESPONSE_OK
              #dialog.icon = $window.icon
              #if (dialog.run == Gtk::Dialog::RESPONSE_OK)
              #  p 'Here need to switch of the task'
              #end
              #dialog.destroy

              if not @scheduler_dialog
                @scheduler_dialog = PandoraGtk::AdvancedDialog.new(_('Tasks'))
                dialog = @scheduler_dialog
                dialog.set_default_size(420, 250)
                vbox = Gtk::VBox.new
                dialog.viewport.add(vbox)

                label = Gtk::Label.new(_('Message'))
                vbox.pack_start(label, false, false, 2)
                user_entry = Gtk::Entry.new
                user_entry.text = message
                vbox.pack_start(user_entry, false, false, 2)


                label = Gtk::Label.new(_('Here'))
                vbox.pack_start(label, false, false, 2)
                pass_entry = Gtk::Entry.new
                pass_entry.width_request = 250
                align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
                align.add(pass_entry)
                vbox.pack_start(align, false, false, 2)
                vbox.pack_start(pass_entry, false, false, 2)

                dialog.def_widget = user_entry

                dialog.run2 do
                  p 'reset dialog flag'
                end
                @scheduler_dialog = nil
              end

            end

            # Base gabager

            # List gabager

            # GUI updater (list, traffic)

            sleep(@scheduler_interval/1000)
            Thread.pass
          end
          @scheduler = nil
        end
      end
    end

    # Show main Gtk window
    # RU: Показать главное окно Gtk
    def initialize(*args)
      super(*args)
      $window = self
      @hunter_count, @listener_count, @fisher_count = 0, 0, 0
      @title_view = TV_Name

      main_icon = nil
      begin
        main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      rescue Exception
      end
      if not main_icon
        main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end
      if main_icon
        $window.icon = main_icon
        Gtk::Window.default_icon = $window.icon
      end

      $group = Gtk::AccelGroup.new
      $window.add_accel_group($group)

      menubar = Gtk::MenuBar.new
      fill_menubar(menubar)

      toolbar = Gtk::Toolbar.new
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      fill_main_toolbar(toolbar)

      #frame = Gtk::Frame.new
      #frame.shadow_type = Gtk::SHADOW_IN
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(frame)
      #image = Gtk::Image.new
      #frame.add(image)

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      #@notebook.set_tab_reorderable(frame, true)
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        cur_page = notebook.get_nth_page(page_num)
        if $last_page and (cur_page != $last_page) and ($last_page.is_a? PandoraGtk::DialogScrollWin)
          $last_page.init_video_sender(false, true) if not $last_page.area_send.destroyed?
          $last_page.init_video_receiver(false) if not $last_page.area_recv.destroyed?
        end
        if cur_page.is_a? PandoraGtk::DialogScrollWin
          cur_page.update_state(false, cur_page)
          cur_page.init_video_receiver(true, true, false) if not cur_page.area_recv.destroyed?
          cur_page.init_video_sender(true, true) if not cur_page.area_send.destroyed?
        end
        PandoraGtk.update_treeview_if_need(cur_page)
        $last_page = cur_page
      end

      @log_view = PandoraGtk::ExtTextView.new
      log_view.set_readonly(true)
      log_view.border_width = 0

      sw = Gtk::ScrolledWindow.new(nil, nil)
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      sw.shadow_type = Gtk::SHADOW_IN
      sw.add(log_view)
      sw.border_width = 1;
      sw.set_size_request(-1, 40)

      fish_sw = FishScrollWin.new

      @fish_hpaned = Gtk::HPaned.new
      @fish_hpaned.pack1(fish_sw, true, true)
      @fish_hpaned.pack2(notebook, true, true)
      @fish_hpaned.position = 1
      @fish_hpaned.position = 0
      @fish_hpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_fish_btn_state
      end

      vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      vpaned.pack1(fish_hpaned, true, true)
      vpaned.pack2(sw, false, true)

      @cvpaned = CaptchaHPaned.new(vpaned)
      @cvpaned.position = cvpaned.max_position

      $statusbar = Gtk::Statusbar.new
      PandoraGtk.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

      add_status_field(SF_Update, _('Version') + ': ' + _('Not checked')) do
        PandoraGtk.start_updating(true)
      end
      add_status_field(SF_Lang, $lang) do
        do_menu_act('Blob')
      end
      add_status_field(SF_Auth, _('Not logged')) do
        do_menu_act('Authorize')
      end
      add_status_field(SF_Listen, _('Not listen')) do
        do_menu_act('Listen')
      end
      add_status_field(SF_Hunt, _('No hunt')) do
        do_menu_act('Hunt')
      end
      add_status_field(SF_Notice, '-') do
        do_menu_act('Notice')
      end
      add_status_field(SF_Conn, '0/0/0') do
        do_menu_act('Session')
      end
      add_status_field(SF_Fish, '0') do
        do_menu_act('Fish')
      end
      add_status_field(SF_Fisher, '0') do
        do_menu_act('Fisher')
      end

      vbox = Gtk::VBox.new
      vbox.pack_start(menubar, false, false, 0)
      vbox.pack_start(toolbar, false, false, 0)
      vbox.pack_start(cvpaned, true, true, 0)
      vbox.pack_start($statusbar, false, false, 0)

      #dat = DateEntry.new
      #vbox.pack_start(dat, false, false, 0)

      $window.add(vbox)

      update_win_icon = PandoraUtils.get_param('status_update_win_icon')
      flash_on_new = PandoraUtils.get_param('status_flash_on_new')
      flash_interval = PandoraUtils.get_param('status_flash_interval')
      play_sounds = PandoraUtils.get_param('play_sounds')
      hide_on_minimize = PandoraUtils.get_param('hide_on_minimize')
      hide_on_close = PandoraUtils.get_param('hide_on_close')
      mplayer = nil
      if PandoraUtils.os_family=='windows'
        mplayer = PandoraUtils.get_param('win_mp3_player')
      else
        mplayer = PandoraUtils.get_param('linux_mp3_player')
      end
      $mp3_player = mplayer if ((mplayer.is_a? String) and (mplayer.size>0))

      $statusicon = PandoraGtk::PandoraStatusIcon.new(update_win_icon, flash_on_new, \
        flash_interval, play_sounds, hide_on_minimize)

      @chech_tasks = false
      @gabage_clear = false
      init_scheduler(1000) if (@chech_tasks or @gabage_clear)

      $window.signal_connect('delete-event') do |*args|
        if hide_on_close
          $window.do_menu_act('Hide')
        else
          $window.do_menu_act('Quit')
        end
        true
      end

      $window.signal_connect('destroy') do |window|
        while (not $window.notebook.destroyed?) and ($window.notebook.children.count>0)
          $window.notebook.children[0].destroy if (not $window.notebook.children[0].destroyed?)
        end
        PandoraCrypto.reset_current_key
        $statusicon.visible = false if ($statusicon and (not $statusicon.destroyed?))
        $window = nil
        Gtk.main_quit
      end

      $window.signal_connect('key-press-event') do |widget, event|
        res = true
        if ([Gdk::Keyval::GDK_m, Gdk::Keyval::GDK_M, 1752, 1784].include?(event.keyval) \
        and event.state.control_mask?)
          $window.hide
        elsif event.keyval == Gdk::Keyval::GDK_F5
          PandoraNet.hunt_nodes
        elsif event.state.control_mask? and (Gdk::Keyval::GDK_0..Gdk::Keyval::GDK_9).include?(event.keyval)
          num = $window.notebook.n_pages
          if num>0
            n = (event.keyval - Gdk::Keyval::GDK_1)
            n = 0 if n<0
            if (n<num) and (n != 8)
              $window.notebook.page = n
              res = true
            else
              $window.notebook.page = num-1
              res = true
            end
          end
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) \
        and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, \
        1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
          $window.destroy
        elsif event.state.control_mask? \
        and [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
          curpage = nil
          if $window.notebook.n_pages>0
            curpage = $window.notebook.get_nth_page($window.notebook.page)
          end
          if curpage.is_a? PandoraGtk::PanobjBox
            res = false
          else
            res = PandoraGtk.show_panobject_list(PandoraModel::Person)
            res = (res != nil)
          end
        else
          res = false
        end
        res
      end

      #$window.signal_connect('client-event') do |widget, event_client|
      #  p '[widget, event_client]='+[widget, event_client].inspect
      #end

      $window.signal_connect('window-state-event') do |widget, event_window_state|
        if (event_window_state.changed_mask == Gdk::EventWindowState::ICONIFIED) \
          and ((event_window_state.new_window_state & Gdk::EventWindowState::ICONIFIED)>0)
        then
          if notebook.page >= 0
            sw = notebook.get_nth_page(notebook.page)
            if sw.is_a? DialogScrollWin
              sw.init_video_sender(false, true) if not sw.area_send.destroyed?
              sw.init_video_receiver(false) if not sw.area_recv.destroyed?
            end
          end
          if widget.visible? and widget.active? and $statusicon.hide_on_minimize
            $window.hide
            #$window.skip_taskbar_hint = true
          end
        end
      end

      PandoraGtk.get_main_params

      #$window.signal_connect('focus-out-event') do |window, event|
      #  p 'focus-out-event: ' + $window.has_toplevel_focus?.inspect
      #  false
      #end
      $window.do_on_show = PandoraUtils.get_param('do_on_show')
      $window.signal_connect('show') do |window, event|
        if $window.do_on_show > 0
          key = PandoraCrypto.current_key(false, true)
          if ($window.do_on_show>1) and key and (not $listen_thread)
            PandoraNet.start_or_stop_listen
          end
          $window.do_on_show = 0
        end
        false
      end

      @pool = PandoraNet::Pool.new($window)

      $window.set_default_size(640, 420)
      $window.maximize
      $window.show_all

      #------next must be after show main form ---->>>>

      $window.focus_timer = $window
      $window.signal_connect('focus-in-event') do |window, event|
        #p 'focus-in-event: ' + [$window.has_toplevel_focus?, \
        #  event, $window.visible?].inspect
        if $window.focus_timer
          $window.focus_timer = nil if ($window.focus_timer == $window)
        else
          if (PandoraUtils.os_family=='windows') and (not $window.visible?)
            $window.do_menu_act('Activate')
          end
          $window.focus_timer = GLib::Timeout.add(500) do
            if (not $window.nil?) and (not $window.destroyed?)
              #p 'read timer!!!' + $window.has_toplevel_focus?.inspect
              toplevel = ($window.has_toplevel_focus? or (PandoraUtils.os_family=='windows'))
              if toplevel and $window.visible?
                $window.notebook.children.each do |child|
                  if (child.is_a? DialogScrollWin) and (child.has_unread)
                    $window.notebook.page = $window.notebook.children.index(child)
                    break
                  end
                end
                curpage = $window.notebook.get_nth_page($window.notebook.page)
                if (curpage.is_a? PandoraGtk::DialogScrollWin) and toplevel
                  curpage.update_state(false, curpage)
                else
                  PandoraGtk.update_treeview_if_need(curpage)
                end
              end
              $window.focus_timer = nil
            end
            false
          end
        end
        false
      end

      $base_id = PandoraUtils.get_param('base_id')
      check_update = PandoraUtils.get_param('check_update')
      if (check_update==1) or (check_update==true)
        last_check = PandoraUtils.get_param('last_check')
        last_check ||= 0
        last_update = PandoraUtils.get_param('last_update')
        last_update ||= 0
        check_interval = PandoraUtils.get_param('check_interval')
        if not check_interval or (check_interval < 0)
          check_interval = 1
        end
        update_period = PandoraUtils.get_param('update_period')
        if not update_period or (update_period < 0)
          update_period = 1
        end
        time_now = Time.now.to_i
        need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
        ok_version = (time_now - last_update.to_i) < update_period*24*3600
        if ok_version
          set_status_field(SF_Update, 'Ok', need_check)
        elsif need_check
          PandoraGtk.start_updating(false)
        end
      end

      Gtk.main
    end

  end  #--MainWindow

end


# ============================================================
# MAIN


# Default values of variables
# RU: Значения переменных по умолчанию
$poly_launch = false
$host = nil
$lang = 'en'
$pandora_parameters = []

# Paths and files
# RU: Пути и файлы
$pandora_root_dir = Dir.pwd                                     # Current directory
$pandora_base_dir = File.join($pandora_root_dir, 'base')        # Database directory
$pandora_view_dir = File.join($pandora_root_dir, 'view')        # Media files directory
$pandora_model_dir = File.join($pandora_root_dir, 'model')      # Model directory
$pandora_lang_dir = File.join($pandora_root_dir, 'lang')        # Languages directory
$pandora_util_dir = File.join($pandora_root_dir, 'util')        # Utilites directory
$pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Database file
$pandora_files_dir = File.join($pandora_root_dir, 'files')      # Files directory

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки
arg = nil
val = nil
next_arg = nil
while (ARGV.length>0) or next_arg
  if next_arg
    arg = next_arg
    next_arg = nil
  else
    arg = ARGV.shift
  end
  if (arg.is_a? String) and (arg[0,1]=='-')
    if ARGV.length>0
      next_arg = ARGV.shift
    end
    if next_arg and next_arg.is_a? String and (next_arg[0,1] != '-')
      val = next_arg
      next_arg = nil
    end
  end
  case arg
    when '-h','--host'
      $host = val if val
    when '-p','--port'
      if val
        $tcp_port = val.to_i
        $udp_port = $tcp_port
      end
    when '-b', '--base'
      $pandora_sqlite_db = val if val
      p 'base='+$pandora_sqlite_db.inspect
    when '-pl', '--poly', '--poly-launch'
      $poly_launch = true
    when '--shell', '--help', '/?', '-?'
      runit = '  '
      if arg=='--shell' then
        runit += 'pandora.sh'
      else
        runit += 'ruby pandora.rb'
      end
      runit += ' '
      puts 'Оriginal Pandora params for examples:'
      puts runit+'-h localhost    - set listen address'
      puts runit+'-p 5577         - set listen port'
      puts runit+'-b base/pandora2.sqlite  - set filename of database'
      Kernel.exit!
  end
  val = nil
end

PANDORA_USOCK = '/tmp/pandora_unix_socket'
$pserver = nil

# Delete Pandora unix socket
# RU: Удаляет unix-сокет Пандоры
def delete_psocket
  File.delete(PANDORA_USOCK) if File.exist?(PANDORA_USOCK)
end

$win32api = nil

# Initialize win32 unit
# RU: Инициализирует модуль win32
def init_win32api
  if $win32api.nil?
    begin
      require 'Win32API'
      $win32api = true
    rescue Exception
      $win32api = false
    end
  end
  $win32api
end

MAIN_WINDOW_TITLE = 'Pandora'
GTK_WINDOW_CLASS = 'gdkWindowToplevel'

# Prevent second execution
# RU: Предотвратить второй запуск
if not $poly_launch
  if PandoraUtils.os_family=='unix'
    psocket = nil
    begin
      psocket = UNIXSocket.new(PANDORA_USOCK)
    rescue
      psocket = nil
    end
    if psocket
      psocket.send('Activate', 0)
      psocket.close
      puts 'Another copy of Pandora is already runned'
      Kernel.exit
    else
      begin
        delete_psocket
        $pserver = UNIXServer.new(PANDORA_USOCK)
        Thread.new do
          while not $pserver.closed?
            psocket = $pserver.accept
            if psocket
              Thread.new(psocket) do |psocket|
                while not psocket.closed?
                  command = psocket.recv(255)
                  if ($window and command and (command != ''))
                    $window.do_menu_act(command)
                  else
                    psocket.close
                  end
                end
              end
            end
          end
        end
      rescue
        $pserver = nil
      end
    end
  elsif (PandoraUtils.os_family=='windows') and init_win32api
    FindWindow = Win32API.new('user32', 'FindWindow', ['P', 'P'], 'L')
    win_handle = FindWindow.call(GTK_WINDOW_CLASS, MAIN_WINDOW_TITLE)
    if (win_handle.is_a? Integer) and (win_handle>0)
      #ShowWindow = Win32API.new('user32', 'ShowWindow', 'L', 'V')
      #ShowWindow.call(win_handle, 5)  #SW_SHOW=5, SW_RESTORE=9
      SetForegroundWindow = Win32API.new('user32', 'SetForegroundWindow', 'L', 'V')
      SetForegroundWindow.call(win_handle)
      Kernel.abort('Another copy of Pandora is already runned')
    end
  end
end

# Check Ruby version and init ASCII string class
# RU: Проверить версию Ruby и объявить класс ASCII-строки
if RUBY_VERSION<'1.9'
  puts 'Pandora requires Ruby1.9 or higher - current '+RUBY_VERSION
  exit(10)
else
  class AsciiString < String
    def initialize(str=nil)
      if str == nil
        super('')
      else
        super(str)
      end
      force_encoding('ASCII-8BIT')
    end
  end
  class Utf8String < String
    def initialize(str=nil)
      if str.is_a? String
        super(str)
      elsif str.is_a? Numeric
        super(str.to_s)
      else
        super(str.inspect)
      end
      force_encoding('UTF-8')
    end
  end
  Encoding.default_external = 'UTF-8'
  Encoding.default_internal = 'UTF-8' #BINARY ASCII-8BIT UTF-8
end

# Redirect console output to file, because of rubyw.exe crush
# RU: Перенаправить консольный вывод в файл из-за краша rubyw.exe
if PandoraUtils.os_family=='windows'
  $stdout.reopen(File.join($pandora_base_dir, 'stdout.log'), 'w')
  $stderr = $stdout
end

# WinAPI constants for work with the register
# RU: Константы WinAPI для работы с регистром
HKEY_LOCAL_MACHINE = 0x80000002
STANDARD_RIGHTS_READ = 0x00020000
KEY_QUERY_VALUE = 0x0001
KEY_ENUMERATE_SUB_KEYS = 0x0008
KEY_NOTIFY = 0x0010
KEY_READ = STANDARD_RIGHTS_READ | KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY

# Read Windows HKLM registry value by path and key
# RU: Читает значение HKLM реестра винды по пути и ключу
def read_win_hklm_reg(path, key)
  res = nil
  if init_win32api
    $waRegOpenKeyEx ||= Win32API.new('advapi32', 'RegOpenKeyEx', 'LPLLP', 'L')
    $waRegQueryValueEx ||= Win32API.new('advapi32', 'RegQueryValueEx', 'LPLPPP', 'L')
    $waRegCloseKey ||= Win32API.new('advapi32', 'RegCloseKey', 'L', 'L')
    if $waRegOpenKeyEx and $waRegQueryValueEx and $waRegCloseKey
      root = HKEY_LOCAL_MACHINE
      reg_type = KEY_READ | 0x100
      phkey = [0].pack('L')
      ret =  $waRegOpenKeyEx.call(root, path, 0, reg_type, phkey)
      if (ret == 0)
        hkey = phkey.unpack('L')[0]
        buf  = 0.chr * 1024
        size = [buf.length].pack('L')
        ret =  $waRegQueryValueEx.call(hkey, key, 0, 0, buf, size)
        if (ret == 0)
          $waRegCloseKey.call(hkey)
          begin
            res = buf[0, 4]
            res = res.to_i(16) if res
          rescue Exception
            res = nil
          end
        end
      else
        puts 'RegOpenKeyEx call error'
      end
    else
      puts 'Init error: [RegOpenKeyEx, RegQueryValueEx, RegCloseKey]=' + \
        [$waRegOpenKeyEx, $waRegQueryValueEx, $waRegCloseKey].inspect
    end
  end
  res
end

# Get language from environment parameters
# RU: Взять язык из переменных окружения
lang = ENV['LANG']
if (lang.is_a? String) and (lang.size>1)
  $lang = lang[0, 2].downcase
elsif PandoraUtils.os_family=='windows'
  lang_code = read_win_hklm_reg('System\CurrentControlSet\Control\Nls\Language', \
    'InstallLanguage')
  if lang_code
    lcode = {}
    lcode[0x0436] = 'af;Afrikaans'
    lcode[0x041C] = 'sq;Albanian'
    lcode[0x0001] = 'ar;Arabic'
    lcode[0x0401] = 'ar-sa;Arabic (Saudi Arabia)'
    lcode[0x0801] = 'ar-iq;Arabic (Iraq)'
    lcode[0x0C01] = 'ar-eg;Arabic (Egypt)'
    lcode[0x1001] = 'ar-ly;Arabic (Libya)'
    lcode[0x1401] = 'ar-dz;Arabic (Algeria)'
    lcode[0x1801] = 'ar-ma;Arabic (Morocco)'
    lcode[0x1C01] = 'ar-tn;Arabic (Tunisia)'
    lcode[0x2001] = 'ar-om;Arabic (Oman)'
    lcode[0x2401] = 'ar-ye;Arabic (Yemen)'
    lcode[0x2801] = 'ar-sy;Arabic (Syria)'
    lcode[0x2C01] = 'ar-jo;Arabic (Jordan)'
    lcode[0x3001] = 'ar-lb;Arabic (Lebanon)'
    lcode[0x3401] = 'ar-kw;Arabic (Kuwait)'
    lcode[0x3801] = 'ar-ae;Arabic (you.A.E.)'
    lcode[0x3C01] = 'ar-bh;Arabic (Bahrain)'
    lcode[0x4001] = 'ar-qa;Arabic (Qatar)'
    lcode[0x042D] = 'eu;Basque'
    lcode[0x0402] = 'bg;Bulgarian'
    lcode[0x0423] = 'be;Belarusian'
    lcode[0x0403] = 'ca;Catalan'
    lcode[0x0004] = 'zh;Chinese'
    lcode[0x0404] = 'zh-tw;Chinese (Taiwan)'
    lcode[0x0804] = 'zh-cn;Chinese (China)'
    lcode[0x0C04] = 'zh-hk;Chinese (Hong Kong SAR)'
    lcode[0x1004] = 'zh-sg;Chinese (Singapore)'
    lcode[0x041A] = 'hr;Croatian'
    lcode[0x0405] = 'cs;Czech'
    lcode[0x0406] = 'the;Danish'
    lcode[0x0413] = 'nl;Dutch (Netherlands)'
    lcode[0x0813] = 'nl-be;Dutch (Belgium)'
    lcode[0x0009] = 'en;English'
    lcode[0x0409] = 'en-us;English (United States)'
    lcode[0x0809] = 'en-gb;English (United Kingdom)'
    lcode[0x0C09] = 'en-au;English (Australia)'
    lcode[0x1009] = 'en-ca;English (Canada)'
    lcode[0x1409] = 'en-nz;English (New Zealand)'
    lcode[0x1809] = 'en-ie;English (Ireland)'
    lcode[0x1C09] = 'en-za;English (South Africa)'
    lcode[0x2009] = 'en-jm;English (Jamaica)'
    lcode[0x2809] = 'en-bz;English (Belize)'
    lcode[0x2C09] = 'en-tt;English (Trinidad)'
    lcode[0x0425] = 'et;Estonian'
    lcode[0x0438] = 'fo;Faeroese'
    lcode[0x0429] = 'fa;Farsi'
    lcode[0x040B] = 'fi;Finnish'
    lcode[0x040C] = 'fr;French (France)'
    lcode[0x080C] = 'fr-be;French (Belgium)'
    lcode[0x0C0C] = 'fr-ca;French (Canada)'
    lcode[0x100C] = 'fr-ch;French (Switzerland)'
    lcode[0x140C] = 'fr-lu;French (Luxembourg)'
    lcode[0x043C] = 'gd;Gaelic'
    lcode[0x0407] = 'de;German (Germany)'
    lcode[0x0807] = 'de-ch;German (Switzerland)'
    lcode[0x0C07] = 'de-at;German (Austria)'
    lcode[0x1007] = 'de-lu;German (Luxembourg)'
    lcode[0x1407] = 'de-li;German (Liechtenstein)'
    lcode[0x0408] = 'el;Greek'
    lcode[0x040D] = 'he;Hebrew'
    lcode[0x0439] = 'hi;Hindi'
    lcode[0x040E] = 'hu;Hungarian'
    lcode[0x040F] = 'is;Icelandic'
    lcode[0x0421] = 'in;Indonesian'
    lcode[0x0410] = 'it;Italian (Italy)'
    lcode[0x0810] = 'it-ch;Italian (Switzerland)'
    lcode[0x0411] = 'ja;Japanese'
    lcode[0x0412] = 'ko;Korean'
    lcode[0x0426] = 'lv;Latvian'
    lcode[0x0427] = 'lt;Lithuanian'
    lcode[0x042F] = 'mk;FYRO Macedonian'
    lcode[0x043E] = 'ms;Malay (Malaysia)'
    lcode[0x043A] = 'mt;Maltese'
    lcode[0x0414] = 'no;Norwegian (Bokmal)'
    lcode[0x0814] = 'no;Norwegian (Nynorsk)'
    lcode[0x0415] = 'pl;Polish'
    lcode[0x0416] = 'pt-br;Portuguese (Brazil)'
    lcode[0x0816] = 'pt;Portuguese (Portugal)'
    lcode[0x0417] = 'rm;Rhaeto-Romanic'
    lcode[0x0418] = 'ro;Romanian'
    lcode[0x0818] = 'ro-mo;Romanian (Moldova)'
    lcode[0x0419] = 'ru;Russian'
    lcode[0x0819] = 'ru-mo;Russian (Moldova)'
    lcode[0x0C1A] = 'sr;Serbian (Cyrillic)'
    lcode[0x081A] = 'sr;Serbian (Latin)'
    lcode[0x041B] = 'sk;Slovak'
    lcode[0x0424] = 'sl;Slovenian'
    lcode[0x042E] = 'sb;Sorbian'
    lcode[0x040A] = 'es;Spanish (Traditional Sort)'
    lcode[0x080A] = 'es-mx;Spanish (Mexico)'
    lcode[0x0C0A] = 'es;Spanish (International Sort)'
    lcode[0x100A] = 'es-gt;Spanish (Guatemala)'
    lcode[0x140A] = 'es-cr;Spanish (Costa Rica)'
    lcode[0x180A] = 'es-pa;Spanish (Panama)'
    lcode[0x1C0A] = 'es-do;Spanish (Dominican Republic)'
    lcode[0x200A] = 'es-ve;Spanish (Venezuela)'
    lcode[0x240A] = 'es-co;Spanish (Colombia)'
    lcode[0x280A] = 'es-pe;Spanish (Peru)'
    lcode[0x2C0A] = 'es-ar;Spanish (Argentina)'
    lcode[0x300A] = 'es-ec;Spanish (Ecuador)'
    lcode[0x340A] = 'es-cl;Spanish (Chile)'
    lcode[0x380A] = 'es-uy;Spanish (Uruguay)'
    lcode[0x3C0A] = 'es-py;Spanish (Paraguay)'
    lcode[0x400A] = 'es-bo;Spanish (Bolivia)'
    lcode[0x440A] = 'es-sv;Spanish (El Salvador)'
    lcode[0x480A] = 'es-hn;Spanish (Honduras)'
    lcode[0x4C0A] = 'es-ni;Spanish (Nicaragua)'
    lcode[0x500A] = 'es-pr;Spanish (Puerto Rico)'
    lcode[0x0430] = 'sx;Sutu'
    lcode[0x041D] = 'sv;Swedish'
    lcode[0x081D] = 'sv-fi;Swedish (Finland)'
    lcode[0x041E] = 'th;Thai'
    lcode[0x0431] = 'ts;Tsonga'
    lcode[0x0432] = 'tn;Tswana'
    lcode[0x041F] = 'tr;Turkish'
    lcode[0x0422] = 'uk;Ukrainian'
    lcode[0x0420] = 'your;Urdu'
    lcode[0x042A] = 'vi;Vietnamese'
    lcode[0x0434] = 'xh;Xhosa'
    lcode[0x043D] = 'ji;Yiddish'
    lcode[0x0435] = 'zu;Zulu'
    lang = lcode[lang_code]
    $lang = lang[0, 2].downcase if (lang.is_a? String) and (lang.size>1)
  end
end

# Some settings
# RU: Некоторые настройки
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# == Running the Pandora!
# == RU: Запуск Пандоры!
PandoraUtils.load_language($lang)
PandoraModel.load_model_from_xml($lang)
PandoraUtils.detect_mp3_player
PandoraGtk::MainWindow.new(MAIN_WINDOW_TITLE)

# Free unix-socket on exit
# Освободить unix-сокет при выходе
$pserver.close if ($pserver and (not $pserver.closed?))
delete_psocket


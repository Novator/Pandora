#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# P2P folk network Pandora
# RU: P2P народная сеть Пандора
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
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
  trans = frase if ((not trans) or (trans.size==0))
  trans
end


# ====================================================================
# Utilites module of Pandora
# RU: Вспомогательный модуль Пандоры

module PandoraUtils

  $detected_os_family = nil

  # Platform detection
  # RU: Определение платформы
  def self.os_family
    if $detected_os_family.nil?
      case RUBY_PLATFORM
        when /ix/i, /ux/i, /gnu/i, /sysv/i, /solaris/i, /sunos/i, /bsd/i
          $detected_os_family = 'unix'
        when /win/i, /ming/i
          $detected_os_family = 'windows'
        else
          $detected_os_family = 'other'
      end
    end
    $detected_os_family
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

  $window = nil
  $show_logbar_level = LM_Warning

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
        if $show_logbar_level and (level<=$show_logbar_level)
          $show_logbar_level = nil
          PandoraGtk.show_log_bar(80)
        end
      end
      puts 'log: '+mes
    end
  end

  MaxCognateDeep = 3

  # Load translated phrases
  # RU: Загрузить переводы фраз
  def self.load_language(lang='ru', cognate_call=nil)

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

    if cognate_call.nil?
      cognate_call = MaxCognateDeep
      $lang_trans.clear
    end
    cognate = nil
    langfile = File.join($pandora_lang_dir, lang+'.txt')
    if File.exist?(langfile) and (cognate_call>0)
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
            if (line.size>0)
              if (line[0, 1] == '#')
                if cognate.nil? and (line[0, 10] == '#!cognate=')
                  cognate = line[10..-1]
                  cognate.strip! if cognate
                  cognate.downcase! if cognate
                end
              else
                if line[0, 1] != '"'
                  frase, trans = line.split('=>')
                  if (frase != '') and (trans != '')
                    if cognate_call
                      $lang_trans[frase] ||= trans
                    else
                      $lang_trans[frase] = trans
                    end
                  end
                else
                  line = line[1..-1]
                  frase = ''
                  trans = ''
                  end_is_found = false
                end
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
              if (frase != '') and (trans != '')
                if cognate_call
                  $lang_trans[frase] ||= trans
                else
                  $lang_trans[frase] = trans
                end
              end
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
    if (cognate.is_a? String) and (cognate.size>0) and (cognate != lang)
      load_language(cognate, cognate_call-1)
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
          res = win_exec(cmd, 15)
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

  DefaultProto = 'http'

  # Parse URL
  # RU: Разбирает URL
  def self.parse_url(url, def_proto=nil)
    res = nil
    proto, obj_type, way = nil
    if (url.is_a? String) and (url.size>0)
      i = url.index(':')
      if i and (i>0)
        proto = url[0, i].strip.downcase
        url = url[i+1..-1]
        proto = 'pandora' if ((proto=='pan') or (proto=='pand') \
          or (proto=='panhash') or (proto=='phash'))
      else
        def_proto ||= DefaultProto
        proto = def_proto
      end
      i = 0
      i += 1 while (i<2) and url and (i<url.size) and (url[i]=='/')
      url = url[i..-1] if i>0
      case proto
        when 'pandora', 'smile'
          i = url.index('/')
          if i
            obj_type = url[0, i]
            obj_type.strip.downcase if obj_type
            url = url[i+1..-1]
          end
      end
      way = url
      p 'parse_url  [url, proto, obj_type, way]='+[url, proto, obj_type, way].inspect
    end
    res = [proto, obj_type, way] if proto and (proto.size>0) and way and (way.size>0)
    res
  end

  # Panhash is nil?
  # RU: Панхэш нулевой?
  def self.panhash_nil?(panhash)
    res = true
    if panhash.is_a? String
      i = 2
      while res and (i<panhash.size)
        res = (panhash[i] == 0.chr)
        i += 1
      end
    elsif panhash.is_a? Integer
      res = (panhash < 255)
    end
    res
  end

  def self.phash(panhash, len=nil)
    res = nil
    if (panhash.is_a? String) and (panhash.size>2)
      len ||= 20
      res = panhash[2, len]
    end
    res
  end

  def self.first_array_element_or_val(array)
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
  # RU: Преобразует строку байт в 16-й формат
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

  # Convert color to hex string
  # RU: Преобразует цвет в 16-й формат
  def self.color_to_str(color)
    res = nil
    if color
      res = '#'
      colors = color.to_a
      colors.each do |c|
        c = (c >> 8) if c>255
        res << ('%02x' % c)
      end
      case res
        when '#ff0000'
          res = 'red'
        when '#00ff00'
          res = 'green'
        when '#0000ff'
          res = 'blue'
      end
    end
    res
  end

  def self.hex?(value)
    res = (/^[0-9a-fA-F]*$/ === value)
  end

  def self.number?(value)
    res = (/^[0-9\.]*$/ === value)
  end

  # Convert hex string to bytes
  # RU: Преобразует 16-ю строку в строку байт
  def self.hex_to_bytes(hexstr)
    bytes = AsciiString.new
    hexstr = '0'+hexstr if hexstr.size % 2 > 0
    ((hexstr.size+1)/2).times do |i|
      bytes << hexstr[i*2,2].to_i(16).chr
    end
    AsciiString.new(bytes)
  end

  # Convert big integer to string of bytes
  # RU: Преобразует большое целое в строку байт
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
  # RU: Преобразует строку байт в целое
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
  # RU: Преобразует строку в строку байт
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

  # Add quotes if string has spaces
  # RU: Добавляет кавычки если строка содержит пробелы
  def self.add_quotes(str, qts='"')
    if (str.is_a? String) and str.index(' ')
      str = qts+str+qts
    end
    str
  end

  # Open link in web browser, email client or file manager
  # RU: Открывает ссылку в браузере, почтовике или проводнике
  def self.external_open(link, oper=nil)
    res = nil
    if PandoraUtils.os_family=='windows'
      res = PandoraUtils.win_shell_execute(link, oper)
    else
      res = Process.spawn('xdg-open', link)
      Process.detach(res) if res
    end
    res
  end

  # Convert ruby date to string
  # RU: Преобразует ruby-дату в строку
  def self.date_to_str(date)
    res = nil
    res = date.strftime('%d.%m.%Y') if date
    res
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

  # Fill string by zeros from right to defined size
  # RU: Заполнить строку нулями справа до нужного размера
  def self.fill_zeros_from_right(data, size)
    #data.force_encoding('ASCII-8BIT')
    data = AsciiString.new(data)
    if data.size<size
      data << [0].pack('C')*(size-data.size)
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

  # Integer to str with leading zero
  # RU: Целое в строку с ведущими нулями
  def self.int_to_str_zero(int, num=nil)
    res = int.to_s.rjust(num, '0') if (num.is_a? Integer)
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

  # Any value to boolean (false, no, off, 0)
  # RU: Любое значение в логическое
  def self.any_value_to_boolean(val)
    val = (((val.is_a? String) and (val.size>0) \
      and (not ('fn0'.index(val[0].downcase))) and (val[0..1].downcase != 'of')) \
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
  def self.time_to_dialog_str(time, time_now=nil)
    time_fmt = '%H:%M:%S'
    if time_now.nil? or ((time_now.to_i - time.to_i).abs > 12*3600)
      time_fmt = '%d.%m.%Y '+time_fmt
    end
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
      elsif view=='time' or view=='datetime'
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
        #if (not type) #or (type=='Text') or (type=='Blob')
        #  val = Base64.encode64(val)
        #else
          val = Base64.strict_encode64(val)
        #end
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
        begin
          val = val[0,50].gsub(/[\r\n\t]/, ' ').squeeze(' ')
          val = val.rstrip
        rescue
        end
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
        when 'byte', 'word', 'integer', 'coord', 'bytelist'
          val = val.to_i
        when 'real'
          val = val.to_f
        when 'date', 'time', 'datetime'
          begin
            val = Time.parse(val)  #Time.strptime(defval, '%d.%m.%Y')
            val = val.to_i
          rescue
            val = 0
          end
        when 'base64'
          #if (not type) or (type=='Text') or (type=='Blob')
          #  val = Base64.decode64(val)
          #else
            begin
              val = Base64.strict_decode64(val)
            rescue
              val = nil
            end
          #end
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

  # Constants for coil coordinate calculations
  # RU: Константы для вычисления катушечной координаты
  DegX = 360
  DegY = 180
  MultX = 92681
  MultY = 46340

  # Null coil coord
  # Нулевая катушечная координата
  NilCoord = 0x7ffe4d8e

  # Geographical coordinate to coil coordinate (4-byte integer)
  # RU: Географическая координата в катушечную координату (4-байтовое целое)
  def self.geo_coord_to_coil_coord(y, x)
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

  # Round geo coordinate (for degree) to 0.01
  # RU: Округлить гео координату (для градусов) до 0,01
  CoordRound = 2

  # Coil coordinate (4-byte integer) to geographical coordinate
  # RU: Катушечную координату (4-байтовое целое) в Географическую координату
  def self.coil_coord_to_geo_coord(int)
    h = (int.fdiv(MultX)).truncate + 1
    s = int - (h-1)*MultX
    x = s.fdiv(MultX)*DegX - 180.0
    y = h.fdiv(MultY)*DegY - 90.0
    x = x.round(CoordRound)
    x = 180.0 if (x==(-180.0))
    y = y.round(CoordRound)
    [y, x]
  end

  # Grid coordinate to cell 0.1 degree (5.5 km)
  # RU: Округлить координату в сетку 0,1 градуса (5,5 км)
  def self.grid_coord_to_cell01(val)
    val = val.round(1)
  end

  # Dynamically create singleton property for an instance and set its value
  # RU: Динамически создаёт свойство единичного объекта и задаёт его значение
  def self.set_obj_property(obj, name, value=nil, readonly=true)
    #obj.send("#{name.to_s}=", value)
    obj.instance_variable_set('@'+name, value)
    obj.define_singleton_method(name.to_sym) do
      instance_variable_get('@'+name)
    end
    if not readonly
      obj.define_singleton_method((name+'=').to_sym) do |value|
        obj.instance_variable_set('@'+name, value)
      end
    end
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
    neg = false
    data = AsciiString.new
    elem_size = nil
    case rubyobj
      when String
        data << AsciiString.new(rubyobj)
        elem_size = data.bytesize
        type, count, neg = encode_pson_type(PT_Str, elem_size)
      when Symbol
        data << AsciiString.new(rubyobj.to_s)
        elem_size = data.bytesize
        type, count, neg = encode_pson_type(PT_Sym, elem_size)
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
        type, count, neg = encode_pson_type(PT_Real, elem_size)
      when Array
        rubyobj.each do |a|
          data << rubyobj_to_pson(a)
        end
        elem_size = rubyobj.size
        type, count, neg = encode_pson_type(PT_Array, elem_size)
      when Hash
        rubyobj = rubyobj.sort_by {|k,v| k.to_s}
        elem_size = 0
        rubyobj.each do |a|
          data << rubyobj_to_pson(a[0]) << rubyobj_to_pson(a[1])
          elem_size += 1
        end
        type, count, neg = encode_pson_type(PT_Hash, elem_size)
      when NilClass
        type = PT_Nil
      else
        puts 'Error! rubyobj_to_pson: illegal ruby class ['+rubyobj.class.name+']'
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
          puts 'Error! rubyobj_to_pson: elem_size<>data_size: '+elem_size.inspect+'<>'\
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
            val = AsciiString.new(data[pos, elem_size])
            count += elem_size
            if basetype == PT_Sym
              val = val.to_sym
            elsif basetype == PT_Real
              val = val.unpack('D')
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
          when PT_Nil
            val = nil
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

  # Pack PanObject fields to Name-PSON binary format
  # RU: Пакует поля панобъекта в бинарный формат Name-PSON
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

  # Convert Name-PSON block to PanObject fields
  # RU: Преобразует Name-PSON блок в поля панобъекта
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

  # Change file extention
  # RU: Сменить расширение файла
  def self.change_file_ext(filename, newext='new')
    res = filename
    if (res.is_a? String) and (res.size>0)
      res = File.join(File.dirname(filename), File.basename(filename, '.*')+'.'+newext)
    end
    res
  end

  # Change file extention
  # RU: Сменить расширение файла
  def self.create_path(fn)
    dir = File.dirname(fn)
    if not File.directory?(dir)
      FileUtils.mkdir_p(dir)
      unix = (PandoraUtils.os_family != 'windows')
      File.chmod(0777, dir) if unix
    end
  end

  # Detect file type
  # RU: Определить тип файла
  def self.detect_file_type(file_name)
    res = nil
    if (file_name.is_a? String) and (file_name.size>0)
      ext = File.extname(file_name)
      if ext
        ext.upcase!
        res = ext[1..-1]
        res = 'JPG' if res=='JPEG'
      end
    end
    res
  end

  # Get path on needed depth
  # RU: Вернуть путь на нужной глубине
  def self.basename_path_depth(filename, depth=nil)
    res = File.basename(filename)
    path = File.dirname(filename)
    if (depth.is_a? Integer)
      sep = File::SEPARATOR
      while (depth>0) and path and (path.size>0)
        if path[-1]==sep
          path = path[0..-2]
        else
          i = path.rindex(sep)
          if i
            res = File.join(path[i+1..-1], res)
            path = path[0..i-1]
          else
            res = File.join(path, res)
            path = nil
          end
          depth -= 1
        end
      end
    end
    res
  end

  # Absolute file path
  # RU: Абсолютный путь файла
  def self.absolute_path(filename, trans_depth=nil)
    res = Utf8String.new(filename)
    if (res.is_a? String) and (res.size>0)
      if (res[0]=='.')
        res = File.join($pandora_files_dir, res[1..-1])
      elsif (res[0]=='[')
        i = res.index(']')
        if i and (i>3) and (i<7)
          func = res[1..i-1]
          path = nil
          case func
            when 'files'
              path = $pandora_files_dir
            when 'app'
              path = $pandora_app_dir
            when 'lang'
              path = $pandora_lang_dir
            when 'view'
              path = $pandora_view_dir
            when 'base'
              path = $pandora_base_dir
            when 'util'
              path = $pandora_util_dir
            when 'model'
              path = $pandora_model_dir
          end
          if path
            if i<res.size-1
              res = File.join(path, res[i+1..-1])
            else
              res = path
            end
          end
        end
      else
        res = File.expand_path(res, $pandora_files_dir)
        if trans_depth
          res = File.join($pandora_files_dir, basename_path_depth(res, trans_depth))
        end
      end
    end
    res
  end

  # Relative file path
  # RU: Относительный путь файла
  def self.relative_path(filename, trans_depth=nil)

    change_path = Proc.new do |way,func|
      res = false
      prefix = filename[0, way.size+1]
      if os_family=='windows'
        prefix.upcase!
        way = way.upcase
      end
      if ((way+'/')==prefix) or ((way+"\\")==prefix)
        func = '['+func+']' if func.size>1
        filename = File.join(func, filename[way.size..-1])
        res = true
      end
      res
    end

    filename = File.expand_path(filename, $pandora_files_dir)

    if (filename.is_a? String) and (filename.size>0)
      unless change_path.call($pandora_files_dir, '.')
        unless change_path.call($pandora_lang_dir, 'lang')
          unless change_path.call($pandora_view_dir, 'view')
            unless change_path.call($pandora_base_dir, 'base')
              unless change_path.call($pandora_util_dir, 'util')
                unless change_path.call($pandora_model_dir, 'model')
                  unless change_path.call($pandora_app_dir, 'app')
                    if trans_depth
                      filename = File.join('.', basename_path_depth(filename, trans_depth))
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    filename
  end

  # Main script
  # RU: Главный скрипт
  def self.main_script
    res = File.expand_path(__FILE__)   #pandora.rb
  end

  # Calc hex md5 of file
  # RU: Вычисляет шестнадцатиричный md5 файла
  def self.file_md5(filename=nil)
    res = nil
    filename ||= main_script
    begin
      md5 = Digest::MD5.file(filename)
      res = md5.hexdigest
    rescue
    end
    res ||= 'fail'
    res
  end

  # Abstract database adapter
  # RU:Абстрактный адаптер к БД
  class DatabaseSession
    NAME = "Сеанс подключения"
    attr_accessor :connected, :conn_param, :def_flds
    def initialize
      @connected = false
      @conn_param = ''
      @def_flds = {}
    end
    def connect
    end
    def create_table(table)
    end
    def select_table(table, afilter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
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

    def panobj_fld_to_sql_desc(fld)
      res = nil
      if fld.is_a? Array
        res = fld[FI_Id].to_s + ' ' + pan_type_to_sqlite_type(fld[FI_Type], fld[FI_Size])
      end
      res
    end

    # Table definitions of SQLite from fields definitions
    # RU: Описание таблицы SQLite из описания полей
    def panobj_fld_to_sqlite_tab(panobj_flds)
      res = ''
      panobj_flds.each do |fld|
        res << ', ' if res != ''
        sql_des = panobj_fld_to_sql_desc(fld)
        res << sql_des if sql_des
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
    def create_table(table, recreate=false, arch_table=nil, \
    arch_fields=nil, new_fields=nil)
      connect
      tfd = db.table_info(table)
      tfd.collect! { |x| x['name'] }
      if (not tfd) or (tfd == [])
        @exist[table] = false
      else
        @exist[table] = true
      end
      tab_def = panobj_fld_to_sqlite_tab(def_flds[table])
      if (! exist[table] or recreate) and tab_def
        if exist[table] and recreate
          res = db.execute('DROP TABLE '+table)
        end
        #p 'CREATE TABLE '+table+' '+tab_def
        #p 'ALTER TABLE '+table+' RENAME TO '+arch_table
        #p 'INSERT INTO '+table+' ('+new_fields+') SELECT '+new_fields+' FROM '+arch_table
        #INSERT INTO t1(val1,val2) SELECT t2.val1, t2.val2 FROM t2 WHERE t2.id = @id
        #p 'ALTER TABLE OLD_COMPANY ADD COLUMN SEX char(1)'
        sql = 'CREATE TABLE '+table+' '+tab_def
        begin
          res = db.execute(sql)
        rescue => err
          res = nil
          PandoraUtils.log_message(LM_Error, \
            _('Cannot create table')+' "'+sql+'": '+Utf8String.new(err.message))
        end
        @exist[table] = true
      end
      exist[table]
    end

    def insert_new_filed(table, fld)
      res = nil
      sql = panobj_fld_to_sql_desc(fld)
      if sql and (sql.size>0)
        sql = 'ALTER TABLE '+table+' ADD COLUMN '+sql
        begin
          res = db.execute(sql)
        rescue => err
          res = nil
          PandoraUtils.log_message(LM_Error, \
            _('Cannot insert field')+' "'+sql+'": '+Utf8String.new(err.message))
        end
      end
      res
    end

    # RU: Поля таблицы
    def fields_table(table)
      connect
      tfd = db.table_info(table)
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
        elsif (filter.size>0) and (filter[0].is_a? String)
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
          sql_values.concat(values) if values
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
    def select_table(table, filter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
      res = nil
      connect
      tfd = fields_table(table)
      #p '[tfd, table, filter, fields, sort, limit, like_filter]='+[tfd, \
      #  table, filter, fields, sort, limit, like_filter].inspect
      if tfd and (tfd != [])
        sql_values = Array.new
        filter_sql = recognize_filter(filter, sql_values, like_ex)

        fields ||= '*'
        sql = 'SELECT ' + fields + ' FROM ' + table + filter_sql

        if sort and (sort > '')
          sql = sql + ' ORDER BY '+sort
        end
        if limit
          sql = sql + ' LIMIT '+limit.to_s
        end
        values_to_ascii(sql_values)
        #p 'select  sql='+sql.inspect+'  values='+sql_values.inspect+' db='+db.inspect
        begin
          res = db.execute(sql, sql_values)
        rescue => err
          res = nil
          PandoraUtils.log_message(LM_Error, \
            _('Wrong select')+' "'+sql+'": '+Utf8String.new(err.message))
        end
      end
      #p 'res='+res.inspect
      res
    end

    # RU: Записывает данные в таблицу
    def update_table(table, values, names=nil, filter=nil)
      res = false
      connect
      sql = ''
      sql_values = Array.new
      sql_values2 = Array.new
      filter_sql = recognize_filter(filter, sql_values2)

      if (not values) and (not names) and filter
        sql = 'DELETE FROM ' + table + filter_sql
      elsif values.is_a? Array and names.is_a? Array
        tfd = db.table_info(table)
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

          sql = 'UPDATE ' + table + ' SET ' + sql + filter_sql
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
          sql = 'INSERT INTO ' + table + '(' + sql + ') VALUES(' + seq + ')'
        end
      end
      tfd = fields_table(table)
      if tfd and (tfd != [])
        sql_values.concat(sql_values2)
        values_to_ascii(sql_values)
        p 'update: sql='+sql.inspect+' sql_values='+sql_values.inspect
        begin
          res = db.execute(sql, sql_values)
          res = true
        rescue => err
          res = false
          PandoraUtils.log_message(LM_Error, \
            _('Wrong update')+' "'+sql+'": '+Utf8String.new(err.message))
        end
        #p 'upd_tab: db.execute.res='+res.inspect
      end
      #p 'upd_tab: res='+res.inspect
      res
    end
  end

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
    attr_accessor :namesvalues
    class << self
      def initialize(*args)
        super(*args)
        @ider = 'BasePanobject'
        @name = 'Базовый объект Пандоры'
        #@lang = true
        @table = nil
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
        df = def_fields.detect{ |e| (e.is_a? Array) \
          and (e[FI_Id].to_s == fld_name) or (e.to_s == fld_name) }
      end

      def has_blob_fields?
        res = def_fields.detect{ |e| (e.is_a? Array) \
          and ((e[FI_Type].to_s.downcase == 'blob') \
          or (e[FI_Type].to_s.downcase == 'text')) }
        (res != nil)
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
        if (fd[FI_View]=='hex') and (not len) \
        and ((not fd[FI_FSize]) or (fd[FI_FSize]=='')) and fd[FI_Size] and (fd[FI_Size]!='')
          len = fd[FI_Size].to_i*2
        end
        fd[FI_FSize] = len if len and (not fd[FI_FSize]) or (fd[FI_FSize]=='')
        #p 'name,type,fsize,view,len='+[fd[FI_Name], fd[FI_Type], fd[FI_FSize], view, len].inspect
        [view, len]
      end

      # Get filed definition from sql table
      # RU: Берет описание полей из sql-таблицы
      def tab_fields(reread=false)
        if (not @last_tab_fields) or reread
          adap = get_adapter(table)
          @last_tab_fields = adap.fields_table(table)
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
              #if field[FI_View]=='phash'
              #  p '===[ider, field[FI_Name], field[FI_View], field[FI_Size], field[FI_FSize]]='\
              #    +[ider, field[FI_Name], field[FI_View], field[FI_Size], field[FI_FSize]].inspect
              #end
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
              indd1, lab_or, new_row = decode_pos(field[FI_Pos])
              indd = indd1
              plus = (indd and (indd[0, 1]=='+'))
              indd = indd[1..-1] if plus
              if indd and (indd.size>0)
                indd = indd.to_f
              else
                indd = nil
              end
              ind = 0.0
              if indd.nil?
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
              #if ider=='Resolution'
              #  p '===[ider, field[FI_Name], indd1. ind='\
              #    +[ider, field[FI_Name], indd1, ind].inspect
              #end
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

      def check_table_fields
        @table_is_checked ||= nil
        if (not @table_is_checked) and $window
          #dialog = PandoraGtk::GoodMessageDialog.new(ider, 'Deletion', \
          #  Gtk::MessageDialog::QUESTION, PandoraGtk.get_panobject_icon(ider))
          #dialog.run_and_do
          tab_flds = tab_fields
          flds = @def_fields
          if (flds.is_a? Array) and (tab_flds.is_a? Array)
            absent_flds = nil
            flds.each do |fld|
              if fld.is_a? Array
                fld_id = fld[FI_Id]
                i = tab_flds.index { |tab_fld| tab_fld[TI_Name]==fld_id }
                if not i
                  absent_flds ||= []
                  absent_flds << fld_id
                end
              end
            end
            if absent_flds
              res = true
              absent_flds.each do |fld_id|
                fld = field_des(fld_id)
                res = (res and @@adapter.insert_new_filed(table, fld))
              end
              flds = absent_flds.join('|')
              if res
                PandoraUtils.log_message(LM_Warning, \
                  (_('New fields %s were added in table') % ('['+flds+\
                  ']')) + ' ['+pname+']')
              else
                PandoraUtils.log_message(LM_Error, \
                  (_('Cannot add new fields %s in the table') % ('['+\
                  flds+']')) + ' ['+pname+']')
              end
              tab_fields(true)
            end
          end
          @table_is_checked = true
        end
        @table_is_checked
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
                    when 'byte', 'lang', 'bytelist'
                      len = 1
                    when 'date'
                      len = 3
                    when 'crc16', 'word'
                      len = 2
                    when 'crc32', 'integer', 'time', 'real', 'coord', 'datetime'
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

      def table
        @table
      end

      def table=(x)
        @table = x
      end

      def name
        @name
      end

      def name=(x)
        @name = x
      end

      def sname
        _(PandoraUtils.get_name_or_names(@name))
      end

      def pname
        _(PandoraUtils.get_name_or_names(@name, true))
      end

    end

    def initialize(*args)
      super(*args)
      self.class.expand_def_fields_to_parent
      self.class.check_table_fields
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

    def def_fields
      self.class.def_fields
    end

    def def_fields=(x)
      self.class.def_fields = x
    end

    def table
      self.class.table
    end

    def name
      self.class.name
    end

    def name=(x)
      self.class.name = x
    end

    # RU: Инициировать адаптер к базе
    def self.get_adapter(table, recreate=false)
      @@adapter ||= nil
      adap = @@adapter
      if not adap
        @@adapter = SQLiteDbSession.new
        adap = @@adapter
        adap.conn_param = $pandora_sqlite_db
      end
      adap.def_flds[table] = self.def_fields
      if (not table) or (table=='') then
        puts 'No table name for ['+self.name+']'
      else
        adap.create_table(table, recreate)
      end
      adap
    end

    def sname
      self.class.sname
    end

    def pname
      self.class.pname
    end

    def tab_fields
      self.class.tab_fields
    end

    # Get records from the table
    # RU: Берет записи из таблицы
    def select(afilter=nil, set_namesvalues=false, fields=nil, sort=nil, limit=nil, like_ex=nil)
      adap = self.class.get_adapter(table)
      sel_fields = nil
      if fields and (not set_namesvalues)
        sel_fields = fields
      end
      res = adap.select_table(self.table, afilter, sel_fields, \
        sort, limit, like_ex)
      if set_namesvalues and res[0].is_a? Array
        @namesvalues = {}
        tab_fields.each_with_index do |td, i|
          fld_name = td[TI_Name].to_s.downcase
          namesvalues[fld_name] = res[0][i]
        end
        if fields
          res[0].clear
          fields.split(',').each do |fld|
            fld_name = fld.to_s.downcase
            res[0] << namesvalues[fld_name]
          end
        end
      end
      res
    end

    # Do procedure when update database
    # RU: Выполнить процедуру при обновлении базы
    def do_update_trigger
      case ider
        when 'Task'
          $window.task_offset = nil
      end
    end

    # Update or delete records in the table, or recreate the table
    # RU: Обновляет или удаляет записи в таблице, либо пересоздаёт таблицу
    def update(values, names=nil, filter='', set_namesvalues=false)
      res = false
      if values.is_a? Hash
        names = values.keys
        values = values.values
        #p 'update names='+names.inspect
        #p 'update values='+values.inspect
      end
      recreate = (values.nil? and names.nil? and filter.nil?)
      adap = self.class.get_adapter(table, recreate)
      if recreate
        res = (not adap.nil?)
      else
        res = adap.update_table(self.table, values, names, filter)
        if set_namesvalues and res
          @namesvalues = {}
          values.each_with_index do |v, i|
            fld_name = names[i].to_s.downcase
            namesvalues[fld_name] = v
          end
        end
      end
      if res
        do_update_trigger
        self.class.modified = true
      end
      res
    end

    # Choose a value by field name
    # RU: Выбирает значение по имени поля
    def field_val(fld_name, values)
      res = nil
      if values.is_a? Array
        i = tab_fields.index{ |tf| tf[0]==fld_name }
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
        res = kn + '/' + res + ' =' + siz.to_s
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
        if ['integer', 'word', 'byte', 'lang', 'coord', 'bytelist'].include? hfor
          if hfor == 'coord'
            if fval.is_a? String
              fval = PandoraUtils.bytes_to_bigint(fval[2,4])
            end
            res = fval.to_i
            coord = PandoraUtils.coil_coord_to_geo_coord(res)
            coord[0] = PandoraUtils.grid_coord_to_cell01(coord[0])
            coord[1] = PandoraUtils.grid_coord_to_cell01(coord[1])
            fval = PandoraUtils.geo_coord_to_coil_coord(*coord)
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
    def calc_panhash(values, lang=0, prefix=true, hexview=false)
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
            fld_name = fname.to_s.downcase
            fval = namesvalues[fld_name]
            if (pack_empty or (not PandoraUtils.value_is_empty?(fval)))
              res[fld_name] = fval
            end
          end
        end
      end
      res
    end

    MaxFldInfo = 14

    # Return brief record information
    # RU: Показывает краткую информацию о записи
    def record_info(max_len=nil, namesvls=nil, sname_sep=nil, sep=nil)
      @namesvalues = namesvls if namesvls
      str = ''
      if @namesvalues.is_a? Hash
        sep ||= '|'
        mfields = self.matter_fields(false)
        mfields.each do |n,v|
          fd = self.field_des(n)
          val, color = PandoraUtils.val_to_view(v, fd[FI_Type], fd[FI_View], false)
          if val
            str << sep if (str.size>0)
            val = val[0, MaxFldInfo] if val.size>MaxFldInfo
            str << val.to_s
            if str.size >= max_len
              str = str[0, max_len]
              break
            end
          end
        end
        str = Utf8String.new(str)
      end
      if sname_sep or (str.size==0)
        str = self.sname + ((str.size>0) ? sname_sep+str : '')
      end
      str
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
    if (not sel) or (sel.size==0)
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
          :section=>section, :setting=>row[PF_Setting], :modified=>Time.now.to_i,
          :panstate=>PandoraModel::PSF_Support }
        panhash = param_model.calc_panhash(values)
        values['panhash'] = panhash
        #p 'add param: '+values.inspect
        param_model.update(values, nil, nil)
        sel = param_model.select({'name'=>name}, false, 'value, id, type')
      end
    end
    if sel and (sel.size>0)
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

  # Set parameter value (delete if value=nil)
  # RU: Задаёт значение параметра (удаляет если value=nil)
  def self.set_param(name, value)
    res = false
    p 'set_param [name, value]='+[name, value].inspect
    old_value, id = PandoraUtils.get_param(name, true)
    param_model = PandoraUtils.get_model('Parameter')
    if ((value != old_value) or value.nil?) and param_model
      value = {:value=>value, :modified=>Time.now.to_i} if value
      res = param_model.update(value, nil, 'id='+id.to_s)
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
      pixbuf = Gdk::Pixbuf.new(drawing.data, Gdk::Pixbuf::COLORSPACE_RGB, true, \
        8, width, height, width*4)
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

  SW_SHOWMAXIMIZED = 3
  SW_SHOW          = 5

  $waFindWindow = nil
  $waSetForegroundWindow = nil

  # Find and activate window
  # RU: Найти и активировать окно
  def self.win_activate_window(win_class, win_title)
    res =  nil
    if init_win32api
      $waFindWindow ||= Win32API.new('user32', 'FindWindow', ['P', 'P'], 'L')
      if $waFindWindow
        win_handle = $waFindWindow.call(win_class, win_title)
        if (win_handle.is_a? Integer) and (win_handle>0)
          $waSetForegroundWindow ||= Win32API.new('user32', 'SetForegroundWindow', 'L', 'V')
          if $waSetForegroundWindow
            $waSetForegroundWindow.call(win_handle)
            res = true
          end
        end
      end
    end
    res
  end

  CP_UTF8        = 65001
  $waMultiByteToWideChar = nil

  # Convert UTF8 to Unicode in Windows
  # RU: Конвертировать UTF8 в Юникод в Винде
  def self.win_utf8_to_unicode(str)
    if init_win32api
      $waMultiByteToWideChar ||= Win32API.new('kernel32', \
        'MultiByteToWideChar', ['I','L','S','I','P','I'], 'I')
      if $waMultiByteToWideChar
        str = str.dup
        str.force_encoding('UTF-8')
        len = $waMultiByteToWideChar.call(CP_UTF8, 0, str, -1, nil, 0)
        if (len.is_a? Integer) and (len>0)
          buf = 0.chr * len * 2
          len = $waMultiByteToWideChar.call(CP_UTF8, 0, str, -1, buf, len)
          str = buf if (len.is_a? Integer) and (len>0)
        end
      end
    end
    str
  end

  $waShellExecute = nil

  # Open in Windows
  # RU: Открыть в Винде
  def self.win_shell_execute(link, oper=nil)
    #oper = :edit, :find, :open, :print, :properties
    res = nil
    if init_win32api
      link = win_utf8_to_unicode(link)
      $waShellExecute ||= Win32API.new('shell32', 'ShellExecuteW', \
        ['L', 'P', 'P', 'P', 'P', 'L'], 'L')
      if $waShellExecute
        oper = win_utf8_to_unicode(oper.to_s) if oper
        puts 'win_shell_execute [link, oper]='+[link, oper].inspect
        res = $waShellExecute.call(0, oper, link, nil, nil, SW_SHOW)
        res = ((res.is_a? Numeric) and ((res == 33) or (res == 42)))
      end
    end
    res
  end

  # Execute external command
  # RU: Запускает внешнюю программу
  def self.exec_cmd(cmd, wait_sec=nil)
    res = nil
    if PandoraUtils.os_family=='windows'
      res = win_exec(cmd, wait_sec)
    else
      res = Process.spawn(cmd)
      Process.detach(res) if res
    end
    res
  end

  # Restart the application
  # RU: Перезапускает программу
  def self.restart_app
    require 'rbconfig'
    inst_par = nil
    inst_par = 'rubyw_install_name' if PandoraUtils.os_family == 'windows'
    inst_par = 'ruby_install_name' if inst_par.nil? or (inst_par=='')
    #p RbConfig::CONFIG
    ruby_int = File.join(RbConfig::CONFIG['bindir'], \
      RbConfig::CONFIG[inst_par])
    ruby_int = PandoraUtils.add_quotes(ruby_int)
    script = PandoraUtils.add_quotes(PandoraUtils.main_script)
    args = nil
    args = ' '+ARGV.join(' ') if ARGV.size>0
    args ||= ''
    run_cmd = ruby_int + ' ' + script + args
    restart_scr = File.join($pandora_util_dir, 'restart.rb')
    restart_scr = PandoraUtils.add_quotes(restart_scr)
    restart_cmd = ruby_int + ' ' + restart_scr + ' '+run_cmd
    puts 'Execute restart script ['+restart_cmd+']'
    res = PandoraUtils.exec_cmd(restart_cmd)
    Kernel.exit if res
  end

  $poly_play   = false
  $play_thread = nil
  Default_Mp3 = 'message'

  # Play mp3
  # RU: Проиграть mp3
  def self.play_mp3(filename, path=nil, anyway=nil)
    if ($poly_play or (not $play_thread)) and (anyway \
    or ($statusicon and (not $statusicon.destroyed?) \
    and $statusicon.play_sounds and (filename.is_a? String) and (filename.size>0)))
      $play_thread = Thread.new do
        begin
          path ||= $pandora_view_dir
          filename ||= Default_Mp3
          filename += '.mp3' unless filename.index('.')
          filename = File.join(path, filename) unless (filename.index('/') or filename.index("\\"))
          filename = File.join(path, Default_Mp3+'.mp3') unless File.exist?(filename)
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

  # Pandora record kind
  # RU: Тип записей Пандоры
  PK_Person    = 1
  PK_City      = 4
  PK_Blob      = 12
  PK_Relation  = 14
  PK_Key       = 221
  PK_Sign      = 222
  PK_Parameter = 220
  PK_Message   = 227
  PK_BlobBody  = 255

  # Panhash length
  # RU: Длина панхэша
  PanhashSize = 22

  def self.hex_to_panhash(hexstr)
    res = PandoraUtils.hex_to_bytes(hexstr)
    res = PandoraUtils.fill_zeros_from_right(res, PanhashSize)
    AsciiString.new(res)
  end

  def self.calc_node_panhash(akey, abaseid)
    node = nil
    if akey and abaseid
      node = PandoraUtils.phash(akey, 12) + abaseid[0, 8]
    end
    node
  end

  def self.find_person_by_key(akey, models=nil)
    res = nil
    sign_model = PandoraUtils.get_model('Sign', models)
    sel = sign_model.select({:key_hash => akey}, false, 'creator', 'id ASC', 1)
    res = sel[0][0] if (sel and (sel.size>0))
    if not res
      key_model = PandoraUtils.get_model('Key', models)
      sel = kmodel.select({:panhash => akey}, false, 'creator', 'id ASC', 1)
      res = sel[0][0] if (sel and (sel.size>0))
    end
    res
  end

  # Pandora's object
  # RU: Объект Пандоры
  class Panobject < PandoraUtils::BasePanobject
    include PandoraUtils

    ider = 'Panobject'
    name = "Объект Пандоры"

    def get_fields_as_view(row, edit=nil)
      formfields = self.def_fields.clone
      tab_flds = self.tab_fields
      formfields.each do |field|
        val = nil
        fid = field[FI_Id]
        view = field[FI_View]
        col = tab_flds.index{ |tf| tf[0] == fid }
        if col and (row.is_a? Array)
          val = row[col]
          if (self.kind==PK_Parameter) and (fid=='value')
            type = self.field_val('type', row)
            setting = self.field_val('setting', row)
            ps = PandoraUtils.decode_param_setting(setting)
            view = ps['view']
            view ||= PandoraUtils.pantype_to_view(type)
            field[FI_View] = view
            field[FI_FSize] = 256 if not view
          end
        end

        if (not edit) and val.nil? and (self.is_a? PandoraModel::Created)
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
      formfields
    end

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
            panobj_name = nil
            panobj_table = nil
            panobject_class = nil
            if PandoraModel.const_defined? panobj_id
              panobject_class = PandoraModel.const_get(panobj_id)
            end
            #p panobject_class
            if panobject_class and panobject_class.def_fields \
            and (panobject_class.def_fields != [])
              # just extend existed class
              panobj_name = panobject_class.name
              panobj_table = panobject_class.table
              new_panobj = false
              #p 'old='+panobject_class.inspect
            else
              # create new class
              panobj_name = panobj_id
              if not panobject_class #not PandoraModel.const_defined? panobj_id
                parent_class = element.attributes['parent']
                if (not parent_class) or (parent_class=='') \
                or (not (PandoraModel.const_defined? parent_class))
                  if parent_class
                    puts _('Parent is not defined, ignored')+' /'+filename+':'+\
                      panobj_id+'<'+parent_class
                  end
                  parent_class = 'Panobject'
                end
                if PandoraModel.const_defined? parent_class
                  PandoraModel.const_get(parent_class).def_fields.each do |f|
                    flds << f.dup
                  end
                end
                init_code = 'class '+panobj_id+' < PandoraModel::'+parent_class+\
                  '; name = "'+panobj_name+'"; end'
                module_eval(init_code)
                panobject_class = PandoraModel.const_get(panobj_id)
                if not $panobject_list.include? panobject_class
                  $panobject_list << panobject_class
                end
              end

              #p 'new='+panobject_class.inspect
              panobject_class.def_fields = flds
              panobject_class.ider = panobj_id
              kind = panobject_class.superclass.kind #if panobject_class.superclass <= BasePanobject
              kind ||= 0
              panobject_class.kind = kind
              #panobject_class.lang = 5
              panobj_table = PandoraUtils::get_name_or_names(panobj_id, true, 'en')
              panobj_table = panobj_table.downcase
              panobject_class.table = panobj_table
            end
            panobj_kind = element.attributes['kind']
            panobject_class.kind = panobj_kind.to_i if panobj_kind
            panobj_sort = element.attributes['sort']
            panobject_class.sort = panobj_sort if panobj_sort
            flds = panobject_class.def_fields
            flds ||= Array.new
            #p 'flds='+flds.inspect
            panobj_name_en = element.attributes['name']
            if (panobj_name==panobj_id) and panobj_name_en and (panobj_name_en != '')
              panobj_name = panobj_name_en
            end
            panobj_name_lang = element.attributes['name'+lang]
            panobj_name = panobj_name_lang if panobj_name_lang and (panobj_name_lang != '')
            #puts panobj_id+'=['+panobj_name+']'
            panobject_class.name = panobj_name

            panobj_table = element.attributes['table']
            panobject_class.table = panobj_table if panobj_table

            # fill fields
            element.elements.each('*') do |sub_elem|
              #p panobj_id+':'+[sub_elem, sub_elem.name].inspect
              if sub_elem.name==sub_elem.name.upcase  #elem name has BIG latters
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
  def self.transform_trust(trust, mode=nil)
    if (trust.is_a? Integer) or (trust.is_a? Float)
      mode ||= :auto_to_int
      to_float = ((mode==:auto_to_float) or (mode==:int_to_float))
      val_int = ((mode==:int_to_float) \
        or (((mode==:auto_to_float) or (mode==:auto_to_int)) and (trust.is_a? Integer)))
      if val_int
        if trust<(-127)
          trust = -127
        elsif trust>127
          trust = 127
        end
        trust = (trust/127.0) if to_float
      else
        if trust<(-1.0)
          trust = -1.0
        elsif trust>1.0
          trust = 1.0
        end
        trust = (trust * 127).round if (not to_float)
      end
    end
    trust
  end

  # Float trust (-1..+1) to public level 21 (0..20)
  # RU: Дробное доверие в уровень публикации 21
  def self.trust2_to_pub21(trust)
    trust ||= -1
    res = (trust*10.0).round+10
  end

  # Float trust (-1..+1) to public relation kind (235..255)
  # RU: Дробное доверие в вид связи "публикую"
  def self.trust2_to_pub235(trust)
    res = RK_MinPublic + trust2_to_pub21(trust)
  end

  # Trust to str with view like "0.2"
  # RU: Доверие в строку вида "0.2"
  def self.trust_to_str(trust)
    trust ||= 0.0
    trust = transform_trust(trust, :auto_to_float)
    res = ((trust*10).round/10.0).to_s
  end

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
        filter = ['panhash=?', panhash]
        if (kind==PK_Key)
          # Except private RSA keys
          filter[0] << ' AND cipher<>'+PandoraCrypto::KT_Priv.to_s
        end
        pson = (pson_with_kind != nil)
        #p 'filter='+filter.inspect
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

  # Read record by sha1 or md5 hash
  # RU: Читает запись по sha1 или md5 хэшу
  def self.get_record_by_hash(hash, kind=nil, pson_with_kind=nil, models=nil, \
  getfields=nil)
    # pson_with_kind: nil - raw data, false - short panhash+pson, true - panhash+pson
    res = nil
    kind ||= PK_Blob
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    if panobjectclass and (hash.is_a? String) and (hash.size>0)
      model = PandoraUtils.get_model(panobjectclass.ider, models)
      if model
        filter = nil
        if hash.size==16
          filter = {'md5'=>hash}
        else
          filter = {'sha1'=>hash}
        end
        pson = (pson_with_kind != nil)
        sel = model.select(filter, pson, getfields, nil, 1)
        if sel and (sel.size>0)
          if pson
            fields = model.clear_excess_fields(sel[0])
            lang = PandoraUtils.lang_from_panhash(panhash)
            res = AsciiString.new
            res << [kind].pack('C') if pson_with_kind
            res << [lang].pack('C')
            p 'get_record_by_hash|||  fields='+fields.inspect
            res << PandoraUtils.hash_to_namepson(fields)
          else
            res = sel
          end
        end
      end
    end
    res
  end

  $keep_for_trust  = 0.5      # set "Support" flag for records with creator trust
  $trust_for_chatcom  = 0.7   # trust level for all chat commands
  $special_chatcom_trusts  = {'echo'=>0.01, 'exec'=>0.9, 'sound'=>0.2, 'tunnel'=>0.8}
  $max_relative_path_depth = 2

  # Save record
  # RU: Сохранить запись
  def self.save_record(kind, lang, values, models=nil, require_panhash=nil, support=:auto)
    res = false
    p '=======save_record  [kind, lang, values]='+[kind, lang, values].inspect
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    ider = panobjectclass.ider
    model = PandoraUtils.get_model(ider, models)
    if not require_panhash
      require_panhash = values['panhash']
      require_panhash ||= values[:panhash]
    end
    panhash = model.calc_panhash(values, lang)
    p 'panhash='+panhash.inspect
    if (not require_panhash) or (panhash==require_panhash)
      harvest_blob = nil
      filter = {'panhash'=>panhash}
      if kind==PK_Key
        filter['kind'] = 0x81  #search public key only
      elsif kind==PK_Blob
        sha1 = values['sha1']
        sha1 ||= values[:sha1]
        fn = values['blob']
        str_blob = nil
        if fn
          str_blob = true
        else
          fn = values[:blob]
          str_blob = false if fn
        end
        p '--- save_record1  fn='+fn.inspect
        if (not str_blob.nil?) and (fn.is_a? String) and (fn.size>1) and (fn[0]=='@')
          p '--- save_record2  fn='+fn.inspect
          fn = PandoraUtils.absolute_path(fn[1..-1])
          fn = '@'+PandoraUtils.relative_path(fn, $max_relative_path_depth)
          p '--- save_record3  fn='+fn.inspect
          if str_blob
            values['blob'] = fn
          else
            values[:blob] = fn
          end
        end

        # ! Здесь надо увязать куски выше и ниже:
        # ! если файл уже есть, то переопределить поле 'blob'
        # ! при этом отследить совпадение sha1

        if sha1
          fn_fs = $window.pool.blob_exists?(sha1, models, true)
          p '--- save_record4  fn='+fn.inspect
          if fn_fs
            fn, fs = fn_fs
            harvest_blob = (not File.exist?(fn))
          else
            harvest_blob = true
          end

          if harvest_blob
            harvest_blob = nil
            #!!!reqs = $window.pool.find_search_request(sha1, PandoraModel::PK_BlobBody)
            #unless (reqs.is_a? Array) and (reqs.size>0)
            #  harvest_blob = sha1
            #end
          end
        end
      end
      sel = model.select(filter, true, nil, nil, 1)
      if sel and (sel.size>0)
        res = true
      else
        if ((support==:auto) or support.nil?) and $keep_for_trust
          creator = values['creator']
          if creator
            trust_or_num = PandoraCrypto.trust_to_panobj(creator, models)
            if (trust_or_num.is_a? Float) and (trust_or_num >= $keep_for_trust)
              support = :yes
            end
          end
        end
        panstate = 0
        if support==:yes
          panstate = (panstate | PandoraModel::PSF_Support)
        end
        if harvest_blob
          panstate = (panstate | PandoraModel::PSF_Harvest)
        end
        values['panstate'] = panstate
        values['panhash'] = panhash
        values['modified'] = Time.now.to_i
        res = model.update(values, nil, nil)
        str = '['+model.record_info(80, values, ': ')+']'
        if res
          PandoraUtils.log_message(LM_Info, _('Recorded')+' '+str)
        else
          PandoraUtils.log_message(LM_Warning, _('Cannot record')+' '+str)
        end
      end
      p '--save_rec5   harvest_blob='+harvest_blob.inspect
      if (harvest_blob.is_a? String)
        reqs = $window.pool.add_mass_record(MK_Search, PandoraModel::PK_BlobBody, \
          harvest_blob)
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
  def self.save_records(records, models=nil, support=:auto)
    if records.is_a? Array
      records.each do |record|
        kind = record[0].ord
        lang = record[1].ord
        values = PandoraUtils.namepson_to_hash(record[2..-1])
        if not PandoraModel.save_record(kind, lang, values, models, nil, support)
          PandoraUtils.log_message(LM_Warning, _('Cannot write a record')+' 2')
        end
      end
    end
  end

  # Get panhash list of needed records from offer
  # RU: Вернуть список панхэшей нужных записей из предлагаемых
  def self.needed_records(ph_list, models=nil)
    need_list = []
    if ph_list.is_a? Array
      ph_list.each do |panhash|
        kind = PandoraUtils.kind_from_panhash(panhash)
        res = PandoraModel.get_record_by_panhash(kind, panhash, nil, models, 'id')
        need_list << panhash if (not res)  #add if record was not found
      end
    end
    p 'needed_records='+need_list.inspect
    need_list
  end

  $kind_list = nil

  # Get kind list of all models
  # RU: Возвращает список типов всех моделей
  def self.get_kind_list
    res = $kind_list
    if not res
      $kind_list = []
      res = $kind_list
      kinds = (1..254)
      kinds = PandoraUtils.str_to_bytes(kinds)
      kinds.each do |kind|
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        res << [kind, panobjectclass.ider, \
          _(PandoraUtils.get_name_or_names(panobjectclass.name))] if panobjectclass
      end
    end
    res
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
  def self.signed_records(signer=nil, from_time=nil, pankinds=nil, trust=nil, \
  key=nil, models=nil)
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

  # Get panhash list of published recs from time for level and kinds
  # RU: Ищет список панхэшей опубликованных записей с времени для уровня и сортов
  def self.public_records(publisher=nil, trust=nil, from_time=nil, pankinds=nil, models=nil)
    sel = nil
    publisher ||= PandoraCrypto.current_user_or_key(true)
    if publisher
      relation_model = PandoraUtils.get_model('Relation', models)
      if relation_model
        pub_level = trust
        pub_level = trust2_to_pub235(trust) if (not trust.is_a? Numeric)
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

  ImageCacheSize = 100
  $image_cache = {}

  # Get pixbuf from cache by a way
  # RU: Взять pixbuf из кэша по пути
  def self.get_image_from_cache(proto, obj_type, way)
    ind = [proto, obj_type, way]
    #p '--get_image_from_cache  [proto, obj_type, way]='+[proto, obj_type, way].inspect
    res = $image_cache[ind]
  end

  # Save pixbuf to cache with a way
  # RU: Сохранить pixbuf в кэша по пути
  def self.save_image_to_cache(img_obj, proto, obj_type, way)
    res = get_image_from_cache(proto, obj_type, way)
    if res.nil? #and (img_obj.is_a? Gdk::Pixbuf)
      while $image_cache.size >= ImageCacheSize do
        $image_cache.delete_at(0)
      end
      ind = [proto, obj_type, way]
      img_obj ||= false
      $image_cache[ind] = img_obj
      p '--save_image_to_cache  [img_obj, proto, obj_type, way]='+[img_obj, proto, obj_type, way].inspect
    end
  end

  def self.del_image_from_cache(panhash, hex=nil)
    res = nil
    if panhash
      panhash_hex = panhash
      if hex
        panhash = PandoraUtils.hex_to_bytes(panhash_hex)
      else #raw format
        panhash_hex = PandoraUtils.bytes_to_hex(panhash)
      end
      $image_cache.delete_if do |key, val|
        ((key.is_a? Array) and (way = key[2]) \
          and ((way==panhash_hex) or (way==panhash)))
      end
    end
    res
  end

  # Max smile name length
  # RU: Максимальная длина имени смайла
  MaxSmileName = 12

  # Obtain image pixbuf from URL
  # RU: Добывает pixbuf картинки по URL
  def self.get_image_from_url(url, err_text=true, pixbuf_parent=nil, def_proto=nil)
    def_proto ||= 'pandora'
    res = PandoraUtils.parse_url(url, def_proto)
    if res
      proto, obj_type, way = res
      res = get_image_from_cache(proto, obj_type, way)
      if res.nil?
        body = nil
        fn = nil
        if way and (way.size>0)
          if (proto=='pandora') or (proto=='sha1') or (proto=='md5') #and obj_type.nil?
            if (way.size>9) and PandoraUtils.hex?(way)
              sel = nil
              if (proto=='pandora')
                panhash = PandoraModel.hex_to_panhash(way)
                kind = PandoraUtils.kind_from_panhash(panhash)
                sel = PandoraModel.get_record_by_panhash(kind, panhash, nil, nil, 'type,blob')
              else
                hash = PandoraUtils.hex_to_bytes(way)
                sel = PandoraModel.get_record_by_hash(hash, nil, nil, nil, 'type,blob')
              end
              #p 'get_image_from_url.pandora/panhash='+panhash.inspect
              if sel and (sel.size>0)
                type = sel[0][0]
                blob = sel[0][1]
                if blob and (blob.size>0)
                  if blob[0]=='@'
                    fn = blob[1..-1]
                    ext = nil
                    ext = File.extname(fn) if fn
                    unless ext and (['.jpg','.gif','.png'].include? ext.downcase)
                      fn = nil
                    end
                  else
                    #body = blob
                    #need to search an image!
                  end
                end
              else
                if err_text
                  res = _('Cannot find image')+': '+proto+'='+PandoraUtils.bytes_to_hex(panhash)
                elsif err_text.is_a? FalseClass
                  res = $window.get_icon_buf('sad')
                end
              end
            elsif (way.size<=MaxSmileName)  #like a smile
              res = $window.get_icon_buf(way, obj_type)
            end
          elsif ((proto=='http') or (proto=='https'))
            fn = load_http_to_file(way)  #need realize!
          elsif proto=='smile'
            res = $window.get_icon_buf(way, obj_type)
          end
        end
        if body
          pixbuf_loader = Gdk::PixbufLoader.new
          pixbuf_loader.last_write(body)
          #res = pixbuf_loader.pixbuf
          res = pixbuf_loader.pixbuf
          #res = Gdk::Pixbuf.new(res, Gdk::Pixbuf::COLORSPACE_RGB, true, 8, width, height, width*4)
        elsif fn
          res = PandoraGtk.start_image_loading(fn, pixbuf_parent)
        end
        save_image_to_cache(res, proto, obj_type, way)
      end
      res = Gtk::Image.new(res) if (not pixbuf_parent) and (res.is_a? Gdk::Pixbuf)
    end
    res
  end

  def self.scale_buf_to_size(pixbuf, icon_size, center=false)
    if pixbuf
      w = pixbuf.width
      h = pixbuf.height
      w2, h2 = icon_size, icon_size
      if (h>h2) and (h >= w)
        w2 = w*h2/h
        pixbuf = pixbuf.scale(w2, h2)
      elsif w>w2
        h2 = h*w2/w
        pixbuf = pixbuf.scale(w2, h2)
      end
      if center and pixbuf
        w = pixbuf.width
        h = pixbuf.height
        asize = w
        asize = h if asize<h
        left = (asize - w)/2
        top  = (asize - h)/2
        qbuf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, asize, asize)
        qbuf.fill!(0xFFFFFF00)
        pixbuf.copy_area(0, 0, w, h, qbuf, left, top)
        pixbuf = qbuf
      end
    end
    pixbuf
  end

  # Obtain avatar icon by panhash
  # RU: Добыть иконку-аватар по панхэшу
  def self.get_avatar_icon(panhash, pixbuf_parent, its_blob=false, icon_size=16)
    pixbuf = nil
    avatar_hash = panhash
    avatar_hash = PandoraModel.find_relation(panhash, RK_AvatarFor, true) if not its_blob
    if avatar_hash
      #p '--get_avatar_icon [its_blob, avatar_hash]='+[its_blob, avatar_hash].inspect
      proto = 'icon'
      obj_type = icon_size
      pixbuf = get_image_from_cache(proto, obj_type, avatar_hash)
      if pixbuf.nil?
        ava_url = 'pandora://'+PandoraUtils.bytes_to_hex(avatar_hash)
        pixbuf = PandoraModel.get_image_from_url(ava_url, nil, pixbuf_parent)
        #p 'pixbuf='+pixbuf.inspect
        if pixbuf
          pixbuf = scale_buf_to_size(pixbuf, icon_size)
        elsif its_blob
          pixbuf = get_avatar_icon(panhash, pixbuf_parent, nil, icon_size)
        end
        save_image_to_cache(pixbuf, proto, obj_type, avatar_hash) #if not its_blob.nil?
      end
    end
    pixbuf
  end

  # Predefined Pandora's codes of languages and Alpha-2
  # RU: Предустановленные коды языков Пандоры и Альфа-2
  Languages = {0=>'all', 1=>'en', 2=>'zh', 3=>'es', 4=>'hi', 5=>'ru', 6=>'ar', \
    7=>'fr', 8=>'pt', 9=>'ja', 10=>'de', 11=>'ko', 12=>'it', 13=>'be', 14=>'id'}

  $lang_code_list = nil

  # Alpha-2 and Pancode codes of languages
  # RU: Коды языков Альфа-2 и панкод
  def self.lang_code_list(update=nil)
    if (not $lang_code_list) or update
      $lang_code_list = Languages.dup
      lang_model = PandoraUtils.get_model('Language')
      sel = lang_model.select(nil, false, 'pancode, alfa2', 'pancode ASC')
      if sel and (sel.size>0)
        sel.each do |row|
          pancode = row[0]
          alfa2 = row[1]
          if (pancode and alfa2)
            pancode = pancode.to_i
            $lang_code_list[pancode] ||= alfa2
          end
        end
      end
    end
    $lang_code_list
  end

  $lang_list = nil

  # Alpha-2 codes of languages
  # RU: Коды языков Альфа-2
  def self.lang_list(update=nil)
    if (not $lang_list) or update
      lcl = lang_code_list(update)
      $lang_list = lcl.values
    end
    $lang_list
  end

  # Get Alpha-2 with pancode of language
  # RU: Взять Альфа-2 по панкоду языка
  def self.lang_to_text(lang)
    res = lang_code_list[lang]
    res ||= ''
  end

  # Get language pancode with Alpha-2
  # RU: Взять панкод языка по Альфа-2
  def self.text_to_lang(text)
    text = text.downcase if text.is_a? String
    res = lang_code_list.detect{ |n,v| v==text }
    res = res[0] if res
    res ||= 0
  end

  # Relation kinds
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
  RK_AvatarFor  = 9
  RK_MinPublic = 235
  RK_MaxPublic = 255

  # Relation kind names
  # RU: Имена видов связей
  RelationNames = [
    [RK_Unknown,    'Unknown'],
    [RK_Equal,      'Equal'],
    [RK_Similar,    'Similar'],
    [RK_Antipod,    'Antipod'],
    [RK_PartOf,     'Part of'],
    [RK_Cause,      'Cause'],
    [RK_Follow,     'Following'],
    [RK_Ignore,     'Ignoring'],
    [RK_CameFrom,   'Came from'],
    [RK_AvatarFor,  'Avatar for'],
    [RK_MinPublic,  'Public']
  ]

  # Task Mode Names
  # RU: Имена режимов задачника
  TaskModeNames = [
    [0,      'Off'],
    [1,      'On']
  ]

  # Relation is symmetric
  # RU: Связь симметрична
  def self.relation_is_symmetric?(relation)
    res = [RK_Equal, RK_Similar, RK_Unknown].include? relation
  end

  # Check, create or delete relation between two panobjects
  # RU: Проверяет, создаёт или удаляет связь между двумя объектами
  def self.act_relation(panhash1, panhash2, rel_kind=RK_Unknown, act=:check, \
  creator_for_nil=true, init=false, models=nil)
    res = nil
    if panhash1 or panhash2
      creator = nil
      if panhash1.nil? or panhash2.nil?
        panhash = PandoraCrypto.current_user_or_key(creator_for_nil, init)
        creator = panhash if creator_for_nil
        if panhash1.nil?
          panhash1 = panhash
        else
          panhash2 = panhash
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
          filter1 = [['first=', panhash1], ['second=', panhash2], [kind_op, rel_kind]]
          filter2 = nil
          if relation_is_symmetric?(rel_kind) and (panhash1 != panhash2)
            filter2 = [['first=', panhash2], ['second=', panhash1], [kind_op, rel_kind]]
          end
          #p 'relat2 [p1,p2,t]='+[PandoraUtils.bytes_to_hex(panhash1), PandoraUtils.bytes_to_hex(panhash2), rel_kind].inspect
          #p 'act='+act.inspect
          if (act == :delete)
            res = relation_model.update(nil, nil, filter1)
            if filter2
              res2 = relation_model.update(nil, nil, filter2)
              res = (res or res2)
            end
          else #check or create
            flds = 'id'
            flds << ',kind' if pub_kind
            sel = relation_model.select(filter1, false, flds, 'modified DESC', 1)
            exist = (sel and (sel.size>0))
            if (not exist) and filter2
              sel = relation_model.select(filter2, false, flds, 'modified DESC', 1)
              exist = (sel and (sel.size>0))
            end
            res = exist
            res = sel[0][1] if pub_kind and exist
            if (not exist) and (act == :create)
              if filter2 and (panhash1>panhash2) #low panhash must be first in symmetric relation
                filter1 = filter2
              end
              panstate = 0
              values = {}
              first = filter1[0][1]
              second = filter1[1][1]
              values['first'] = first
              values['second'] = second
              values['kind'] = filter1[2][1]
              panhash = relation_model.calc_panhash(values, 0)
              values['panhash'] = panhash
              values['modified'] = Time.now.to_i
              creator ||= PandoraCrypto.current_user_or_key(true, false)
              if creator and ((first==creator) or (second==creator))
                panstate = PandoraModel::PSF_Support
              end
              values['panstate'] = panstate
              res = relation_model.update(values, nil, nil)
            end
          end
        end
      end
    end
    res
  end

  # Find relation with the kind with highest rate
  # RU: Ищет связь для сорта с максимальным рейтингом
  def self.find_relation(panhash, rel_kind=nil, second=nil, models=nil)
    res = nil
    relation_model = PandoraUtils.get_model('Relation', models)
    if relation_model
      sel = nil
      exist = nil
      if not second
        filter = [['first=', panhash], ['kind=', rel_kind]]
        flds = 'id,second'
        sel = relation_model.select(filter, false, flds, 'modified DESC', 1)
        exist = (sel and (sel.size>0))
      end
      if (not exist) and (second or relation_is_symmetric?(rel_kind))
        filter = [['second=', panhash], ['kind=', rel_kind]]
        flds = 'id,first'
        sel = relation_model.select(filter, false, flds, 'modified DESC', 1)
        exist = (sel and (sel.size>0))
      end
      res = exist
      res = sel[0][1] if exist
    end
    res
  end

  def self.remove_all_relations(panhash, creator_for_nil=true, init=false, \
  models=nil, unsign=true)
    act_relation(nil, panhash, RK_Ignore, :delete, creator_for_nil, init, models)
    act_relation(nil, panhash, RK_Follow, :delete, creator_for_nil, init, models)
    act_relation(nil, panhash, RK_MinPublic, :delete, creator_for_nil, init, models)
    PandoraCrypto.unsign_panobject(panhash, true) if unsign
  end

  # Panobject state flags
  # RU: Флаги состояния объекта/записи
  PSF_Support    = 1      # must keep on this node (else will be deleted by GC)
  PSF_Verified   = 2      # signature was verified
  PSF_Crypted    = 4      # record is encrypted
  PSF_Harvest    = 64     # download by pieces in progress
  PSF_Archive    = 128    # marked to delete

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

  # Length key flags
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

  # Key length flag to bit length
  # RU: Ключ-флаг длины в битовую длину
  def self.klen_to_bitlen(len)
    res = nil
    ind = len >> 4
    res = KL_BitLens[ind-1] if ind and (ind>0) and (ind<=KL_BitLens.size)
    res
  end

  # Bit length to key length flag
  # RU: Битовая длина в ключ-флаг длины
  def self.bitlen_to_klen(len)
    res = KL_None
    ind = KL_BitLens.index(len)
    res = (ind+1) << 4 if ind
    res
  end

  # Divide mixed key flag to type an length flags
  # RU: Разделить общий ключ-флаг на флаги типа и длины
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

  # Calc file hash
  # RU: Вычислить хэш файла
  def self.file_hash(file_fn, chash=nil)
    res = nil
    chash ||= KH_Sha1
    hash = pan_kh_to_openssl_hash(chash)
    if hash
      file = file_fn
      file = File.open(file_fn) if file_fn.is_a? String
      hash << file.read
      res = hash.digest
    end
    res
  end

  # Convert Pandora type of cipher to OpenSSL name
  # RU: Преобразует тип шифра Пандоры в имя OpenSSL
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

  # Convert Pandora type of cipher to OpenSSL string
  # RU: Преобразует тип шифра Пандоры в строку OpenSSL
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
  KS_Robotic   = 4

  # Encode or decode key
  # RU: Зашифровать или расшифровать ключ
  def self.key_recrypt(data, encode=true, cipher_hash=nil, cipherkey=nil)
    #p '^^^^^^^^^^^^key_recrypt(: [cipher_hash, passwd, data.bytesize]='+\
    #  [cipher_hash, cipherkey, data.bytesize].inspect
    if (cipher_hash.is_a? Integer) and (cipher_hash != 0) and data
      ckind, chash = decode_cipher_and_hash(cipher_hash)
      ktype, klen = divide_type_and_klen(ckind)
      if (ktype == KT_Rsa) or (ktype == KT_Dsa)
        key_vec = cipherkey
        key_vec = current_key(false, true) if not (key_vec.is_a? Array)
        if key_vec and key_vec[KV_Obj] and key_vec[KV_Panhash]
          if encode
            data = recrypt(key_vec, data, encode, (not encode))
            if data
              key_and_data = PandoraUtils.rubyobj_to_pson([key_vec[KV_Panhash], data])
              data = key_and_data
            end
          else
            key_and_data, len = PandoraUtils.pson_to_rubyobj(data)
            if key_and_data.is_a? Array
              keyhash, data = key_and_data
              if (keyhash == key_vec[KV_Panhash])
                data = recrypt(key_vec, data, encode, (not encode))
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
      else  #Cipher is given, use it to crypt
        hash = pan_kh_to_openssl_hash(chash)
        #p 'hash='+hash.inspect
        cipherkey ||= ''
        cipherkey = hash.digest(cipherkey) if hash
        #p '^^cipherkey=hash='+cipherkey.inspect
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
  def self.generate_key(type_klen = KT_Rsa | KL_bit2048, cipher_hash=nil, pass=nil)
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
    [key, keypub, keypriv, type_klen, cipher_hash, pass]
  end

  # Divide type and code of length
  # RU: Разделить тип и код длины
  def self.symmetric_key?(type_key)
    type = nil
    if (type_key.is_a? Integer)
      type = type_key & 0x0F
    elsif (type_key.is_a? Array)
      type_klen = key_vec[KV_Kind]
      type, klen = divide_type_and_klen(type_klen)
    end
    res = (not(type and ((type==KT_Rsa) or (type==KT_Dsa))))
  end

  # Save key(s) to base
  # RU: Сохраняет ключ(и) в базу
  def self.save_key(key_vec, creator=nil, rights=nil, key_model=nil)
    #p 'key_vec='+key_vec.inspect
    creator ||= current_user_or_key(true, false)
    creator ||= key_vec[KV_Creator]
    rights ||= (KS_Exchange | KS_Voucher)
    key_model ||= PandoraUtils.get_model('Key')

    pub  = key_vec[KV_Pub]
    priv = key_vec[KV_Priv]
    type_klen = key_vec[KV_Kind]
    cipher_hash = key_vec[KV_Cipher]
    passwd = key_vec[KV_Pass]

    time_now = Time.now
    vals = time_now.to_a
    y, m, d = [vals[5], vals[4], vals[3]]  #current day
    expire = Time.local(y+5, m, d).to_i

    time_now = time_now.to_i
    panstate = PandoraModel::PSF_Support

    type, klen = divide_type_and_klen(type_klen)
    sym = symmetric_key?(type)

    body = pub
    if sym
      #p '-----[priv.bytesize, pub.bytesize]='+[priv.bytesize, pub.bytesize].inspect
      body = PandoraUtils.rubyobj_to_pson([priv, pub])
      body = key_recrypt(body, true, cipher_hash, passwd)
      priv = nil
    end
    cipher_hash1 = cipher_hash
    cipher_hash1 = 0 if (not priv.nil?)
    values = {:panstate=>panstate, :kind=>type_klen, :rights=>rights, :expire=>expire, \
      :creator=>creator, :created=>time_now, :cipher=>cipher_hash1, \
      :body=>body, :modified=>time_now}

    panhash = key_vec[KV_Panhash]
    panhash ||= key_model.calc_panhash(values, rights)
    values[:panhash] = panhash

    key_vec[KV_Panhash] = panhash
    key_vec[KV_Creator] = creator

    res = key_model.update(values, nil, nil)
    if res and priv
      # save private key separatly
      priv = key_recrypt(priv, true, cipher_hash, passwd)
      values[:kind] = KT_Priv
      values[:body] = priv
      values[:cipher] = cipher_hash
      res = key_model.update(values, nil, nil)
    end
    res = panhash if res
    res
  end

  # Init key or key pair
  # RU: Инициализирует ключ или ключевую пару
  def self.key_saved?(panhash, key_model=nil)
    res = nil
    key_model ||= PandoraUtils.get_model('Key')
    if key_model
      panhash = panhash[KV_Panhash] if (panhash.is_a? Array)
      sel = key_model.select({:panhash=>panhash}, false, 'id', nil, 1)
      res = (sel and (sel.size>0))
    end
    res
  end

  # Init key or key pair
  # RU: Инициализирует ключ или ключевую пару
  def self.init_key(key_vec, recrypt=true)
    key = key_vec[KV_Obj]
    if not key
      keypub  = key_vec[KV_Pub]
      keypriv = key_vec[KV_Priv]
      keypub  = AsciiString.new(keypub) if keypub
      keypriv = AsciiString.new(keypriv) if keypriv
      type_klen = key_vec[KV_Kind]
      cipher_hash = key_vec[KV_Cipher]
      pass = key_vec[KV_Pass]
      if recrypt and keypriv
        keypriv = key_recrypt(keypriv, false, cipher_hash, pass)
      end
      type, klen = divide_type_and_klen(type_klen)
      #p [type, klen]
      bitlen = klen_to_bitlen(klen)
      case type
        when KT_None
          key = nil
        when KT_Rsa
          n = PandoraUtils.bytes_to_bigint(keypub)
          e = OpenSSL::BN.new(RSA_exponent.to_s)
          p0 = nil
          if keypriv
            p0 = PandoraUtils.bytes_to_bigint(keypriv)
          else
            p0 = 0
          end
          if p0
            pass = 0
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
              if key and keypriv
                #Test private key by sign creation
                test_data = OpenSSL::Random.random_bytes(16)
                key_vec[KV_Obj] = key
                sign = make_sign(key_vec, test_data)
                if not (sign and verify_sign(key_vec, test_data, sign))
                  key = nil
                end
              end
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
          if keypub.nil? and keypriv and (bitlen/8 != keypriv.bytesize)
            key_iv, len = PandoraUtils.pson_to_rubyobj(keypriv)
            if (key_iv.is_a? Array)
              keypriv, keypub = key_iv
              key_vec[KV_Pub] = keypub
              key_vec[KV_Priv] = keypriv
            end
          end
          if keypriv
            key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
            key.key = keypriv
            key.iv  = keypub if keypub
          end
      end
      key_vec[KV_Obj] = key
    end
    key_vec
  end

  # Create sign
  # RU: Создает подпись
  def self.make_sign(key_vec, data, hash_len=KH_Sha2 | KL_bit256)
    sign = nil
    if (key_vec.is_a? Array) and data
      key_obj = key_vec[KV_Obj]
      if key_obj
        hash_obj = pan_kh_to_openssl_hash(hash_len)
        if hash_obj
          type_klen = key_vec[KV_Kind]
          type, klen = divide_type_and_klen(type_klen)
          if symmetric_key?(type)
            data_hash = hash_obj.digest(data)
            sign = recrypt(key_vec, data_hash, true)
          else
            begin
              sign = key_obj.sign(hash_obj, data)
            rescue => err
              sign = nil
              p 'SIGN CREATE ERROR: '+Utf8String.new(err.message)
            end
          end
        end
      end
    end
    sign
  end

  # Verify sign
  # RU: Проверяет подпись
  def self.verify_sign(key_vec, data, sign, hash_len=KH_Sha2 | KL_bit256)
    res = nil
    if (key_vec.is_a? Array) and data and sign
      key_obj = key_vec[KV_Obj]
      if key_obj
        hash_obj = pan_kh_to_openssl_hash(hash_len)
        if hash_obj
          type_klen = key_vec[KV_Kind]
          type, klen = divide_type_and_klen(type_klen)
          if symmetric_key?(type)
            hash_came = recrypt(key_vec, sign, false)
            if hash_came
              hash_fact = hash_obj.digest(data)
              res = (hash_came == hash_fact)
            end
          else
            res = key_obj.verify(hash_obj, sign, data)
          end
        end
      end
    end
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
    if data
      data = AsciiString.new(data)
      key = key_vec[KV_Obj]
      #p 'encrypt key='+key.inspect
      if key.is_a? OpenSSL::Cipher
        key.reset
        if encrypt
          key.encrypt
        else
          key.decrypt
        end
        key.key = key_vec[KV_Priv]
        key.iv = key_vec[KV_Pub]
        begin
          recrypted = key.update(data) + key.final
        rescue
          recrypted = nil
        end
      else  #elsif key.is_a? OpenSSL::PKey
        if encrypt
          if private
            recrypted = key.private_encrypt(data)  #for make sign
          else
            recrypted = key.public_encrypt(data)   #crypt to transfer
          end
        else
          if private
            if key_vec[KV_Priv]
              recrypted = key.private_decrypt(data)  #uncrypt after transfer
            else
              recrypted = '<Private key needed ['+\
                PandoraUtils.bytes_to_hex(key_vec[KV_Panhash])+']>'
            end
          else
            recrypted = key.public_decrypt(data)   #for check sign
          end
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
      PandoraUtils.fill_by_zeros(key_vec[PandoraCrypto::KV_Pub])
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
    if self.the_current_key
      panhash = self.the_current_key[KV_Panhash]
      $open_keys[panhash] = nil
      self.the_current_key = deactivate_key(self.the_current_key)
    end
    $window.set_status_field(PandoraGtk::SF_Auth, 'Not logged', nil, false)
    self.the_current_key
  end

  $first_key_init = true

  # Return current key or allow to choose and activate a key
  # RU: Возвращает текущий ключ или позволяет выбрать и активировать ключ
  def self.current_key(switch_init=false, need_init=true)

    # Read a key from database
    # RU: Считывает ключ из базы
    def self.read_key_and_set_pass(panhash, passwd, key_model)
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
          priv = nil
          pub = nil
          kind = nil
          creator = nil
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
        key_vec, cipher = read_key_and_set_pass(panhash, passwd, key_model)
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
          key_vec, cipher = read_key_and_set_pass(last_auth_key, passwd, key_model)
          #p '[key_vec, cipher]='+[key_vec, cipher].inspect
          if (not key_vec) or (not cipher) or (cipher != 0) or (not $first_key_init)
            dialog = PandoraGtk::AdvancedDialog.new(_('Key init'))
            dialog.set_default_size(420, 190)
            dialog.icon = $window.get_preset_icon('auth')

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

            dialog_timer = nil
            key_entry.entry.signal_connect('changed') do |widget, event|
              if dialog_timer.nil?
                dialog_timer = GLib::Timeout.add(1000) do
                  if not key_entry.destroyed?
                    panhash2 = PandoraModel.hex_to_panhash(key_entry.text)
                    key_vec2, cipher = read_key_and_set_pass(panhash2, \
                      passwd, key_model)
                    nopass = ((not cipher) or (cipher == 0))
                    PandoraGtk.set_readonly(pass_entry, nopass)
                    pass_entry.grab_focus if not nopass
                    dialog_timer = nil
                  end
                  false
                end
              end
              false
            end

            nopass = ((not cipher) or (cipher == 0))
            PandoraGtk.set_readonly(pass_entry, nopass)
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

            gen_button = Gtk::ToolButton.new(Gtk::Stock::ADD, _('New'))  #:NEW
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
                panhash = PandoraModel.hex_to_panhash(key_entry.text)
                passwd = pass_entry.text
                if changebtn.active? and new_pass_entry
                  key_vec, cipher, passwd = recrypt_key(key_model, key_vec, cipher, panhash, \
                    passwd, new_pass_entry.text)
                end
                #p '-------------key_vec='+key_vec.inspect
                if (last_auth_key != panhash) or (not key_vec)
                  last_auth_key = panhash
                  key_vec, cipher = read_key_and_set_pass(last_auth_key, passwd, key_model)
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
          dialog.icon = $window.get_preset_icon('key')

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

          voucher_btn = Gtk::CheckButton.new(_('voucher'), true)
          voucher_btn.active = ((rights & KS_Voucher)>0)
          hbox.pack_start(voucher_btn, true, true, 2)

          exchange_btn = Gtk::CheckButton.new(_('exchange'), true)
          exchange_btn.active = ((rights & KS_Exchange)>0)
          hbox.pack_start(exchange_btn, true, true, 2)

          robotic_btn = Gtk::CheckButton.new(_('robotic'), true)
          robotic_btn.active = ((rights & KS_Robotic)>0)
          hbox.pack_start(robotic_btn, true, true, 2)

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
            if creator.size==PandoraModel::PanhashSize
              #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
              passwd = pass_entry.text
              cipher_hash = 0
              if passwd and (passwd.size>0)
                cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
              end

              rights = 0
              rights = (rights | KS_Exchange) if exchange_btn.active?
              rights = (rights | KS_Voucher) if voucher_btn.active?
              rights = (rights | KS_Robotic) if robotic_btn.active?

              #p 'cipher_hash='+cipher_hash.to_s
              type_klen = KT_Rsa | KL_bit2048

              key_vec = generate_key(type_klen, cipher_hash, passwd)
              panhash = save_key(key_vec, creator, rights, key_model)
              last_auth_key = panhash if panhash
            else
              dialog = PandoraGtk::GoodMessageDialog.new(_('Panhash must consist of 44 symbols'))
              dialog.run_and_do do
                PandoraGtk.show_panobject_list(PandoraModel::Person, nil, nil, true)
              end
            end
          end
        end
        if key_vec and (key_vec != [])
          #p '===========key_vec='+key_vec.inspect
          key_vec = init_key(key_vec)
          if key_vec and key_vec[KV_Obj]
            #p '2===========key_vec='+key_vec.inspect
            self.the_current_key = key_vec
            panhash = key_vec[KV_Panhash]
            panhash ||= last_auth_key
            $open_keys[panhash] = key_vec
            text = PandoraCrypto.short_name_of_person(key_vec, nil, 1)
            if not (text and (text.size>0))
              text = 'Logged'
            end
            $window.set_status_field(PandoraGtk::SF_Auth, text, nil, true)
            if last_auth_key0 != last_auth_key
              PandoraUtils.set_param('last_auth_key', last_auth_key)
            end
          else
            dialog = PandoraGtk::GoodMessageDialog.new( \
              _('Cannot activate key. Try again?')+ \
              "\n[" +PandoraUtils.bytes_to_hex(last_auth_key[2,16])+']', \
              'Key init', Gtk::MessageDialog::QUESTION)
            getting = dialog.run_and_do(false) do
              key_vec = deactivate_key(key_vec)
              reset_current_key
            end
          end
        else
          key_vec = deactivate_key(key_vec)
          reset_current_key
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

  # Pack method of data before sign
  # RU: Метод упаковки данных перед подписанием
  PSM_Pson   = 1
  PSM_Json   = 2
  PSM_Xml    = 3
  # Notary purpose flag, just for certification, it's not for working sign
  # RU: Нотариальный флаг, только для сертификации, но не для рабочей подписи
  PSP_Notary = 8
  # Depth of resolving panhashes inside signed record and including their data
  # RU: Глубина разрешения панхэшей внутри подписываемой записи и вложения их данных
  PSR_IncludeDepth1  = 0x10      # 1 level (dont resolve, include just a record)
  PSR_IncludeDepth2  = 0x20      # 2 level (resolve link 1 time, include second floor)
  PSR_IncludeDepth3  = 0x30
  PSR_IncludeDepth4  = 0x40
  PSR_IncludeDepth5  = 0x50
  PSR_IncludeDepth15 = 0xF0      # 15
  PSR_IncludeDepthFull  = 0      # For full depth

  # Depth to flag
  # RU: Глубину во флаг
  def self.include_depth_to_resolve_flag(depth)
    res = PSR_IncludeDepth1
    if (depth.is_a? Integer) and (depth>=0)
      if depth==0
        res = PSR_IncludeDepthFull
      else
        depth = 15 if depth>15
        res = (depth << 4)
      end
    end
    res
  end

  # Flag to depth
  # RU: Флаг в глубину
  def self.resolve_flag_to_include_depth(depth)
    res = nil
    res = ((depth & 0xF0) >> 4) if (depth.is_a? Integer)
    res
  end

  # Sign PSON of PanObject and save a sign as record
  # RU: Подписывает PSON ПанОбъекта и сохраняет подпись как запись
  def self.sign_panobject(panobject, trust=0, models=nil, pack=nil, depth=nil, \
  notary=nil)
    res = false
    key = current_key
    if key and key[KV_Obj] and key[KV_Creator]
      namesvalues = panobject.namesvalues
      matter_fields = panobject.matter_fields

      obj_hash = namesvalues['panhash']
      obj_hash ||= namesvalues[:panhash]
      if not PandoraUtils.panhash_nil?(obj_hash)
        #p 'sign: matter_fields='+matter_fields.inspect
        sign = make_sign(key, PandoraUtils.hash_to_namepson(matter_fields))
        if sign
          time_now = Time.now.to_i
          key_hash = key[KV_Panhash]
          creator = key[KV_Creator]
          trust = PandoraModel.transform_trust(trust)
          pack ||= PSM_Pson
          pack = (pack | PSP_Notary) if notary
          resolve_flag = include_depth_to_resolve_flag(depth)
          pack = (pack | resolve_flag)

          values = {:modified=>time_now, :obj_hash=>obj_hash, :key_hash=>key_hash, \
            :pack=>pack, :trust=>trust, :creator=>creator, :created=>time_now, \
            :sign=>sign, :panstate=>PandoraModel::PSF_Support}

          sign_model = PandoraUtils.get_model('Sign', models)
          panhash = sign_model.calc_panhash(values)
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

  # Get trust to panobject from current user or number of signs
  # RU: Возвращает доверие к панобъекту от текущего пользователя или число подписей
  def self.trust_to_panobj(panhash, models=nil)
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
              res = PandoraModel.transform_trust(trust, :auto_to_float)
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
              if last_trust and ((creator != prev_creator) or (i==last_i))
                p 'sign3: [creator, created, last_trust]='+[creator, created, last_trust].inspect
                person_trust = trust_to_panobj(creator, models) #trust_of_person(creator, my_key_hash)
                person_trust = 0.0 if (not person_trust.is_a? Float)
                rate += PandoraModel.transform_trust(last_trust, :auto_to_float) * person_trust
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
        cur_trust = trust_to_panobj(panhash)
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
              pub = model.field_val('body', row)
              cipher = model.field_val('cipher', row)
              creator = model.field_val('creator', row)
              priv = nil
              if symmetric_key?(type)
                #priv_pub, len = PandoraUtils.pson_to_rubyobj(pub)
                #priv, pub = priv_pub if (priv_pub.is_a? Array)
                priv = pub
                pub = nil
              end

              key_vec = Array.new
              key_vec[KV_Pub] = pub
              key_vec[KV_Priv] = priv
              key_vec[KV_Kind] = kind
              key_vec[KV_Cipher] = cipher
              #key_vec[KV_Pass] = passwd
              key_vec[KV_Panhash] = panhash
              key_vec[KV_Creator] = creator
              key_vec[KV_Trust] = trust_to_panobj(panhash)

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

  # Encode a message to the key panhash or decode it
  # (long messages crypted by 2 step with additional symmetric cipher)
  # RU: Зашифровывает сообщение на панхэш ключа или расшифровывает его
  # RU: (длинные сообщения криптуются в 2 шага с дополнительным симметричным ключом)
  def self.recrypt_mes(data, key_panhash=nil, new_key_panhash=nil, cipher=nil)
    res = nil
    if data.is_a? String
      encrypt = (not key_panhash.nil?)
      data_len = data.bytesize
      if (encrypt and (data_len>0)) or (data_len>22)
        if not encrypt
          key_panhash = data[0, 22]
          if new_key_panhash and (key_panhash==new_key_panhash)
            return data
          end
          data = data[22..-1]
          data_len = data.bytesize
        end
        #p 'encrypt, key_panhash, data_len='+[encrypt, \
        #  PandoraUtils.bytes_to_hex(key_panhash), data_len].inspect
        key_vec = open_key(key_panhash)
        if (key_vec.is_a? Array) and key_vec[KV_Obj]
          #p '------------------ key_vec='+key_vec.inspect
          type_klen = key_vec[KV_Kind]
          #p 'type_klen='+type_klen.inspect
          type, klen = divide_type_and_klen(type_klen)
          #p '[type, klen]='+[type, klen].inspect
          bitlen = klen_to_bitlen(klen)
          #p 'bitlen='+bitlen.inspect
          max_len = bitlen/8
          #p '--max_len='+max_len.inspect
          if data_len>max_len
            if encrypt
              cipher ||= (KT_Aes | KL_bit256)   #default cipher
              ciphlen = klen_to_bitlen(cipher)/8
              cipher_hash = encode_cipher_and_hash(cipher, 0)
              #key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
              #keypub  = key.random_iv
              #keypriv = key.random_key
              ckey = OpenSSL::Random.random_bytes(ciphlen)  #generate cipher
              #p 'ckey1.size='+ckey.bytesize.to_s
              #encrypt data with cipher
              res = key_recrypt(data, true, cipher_hash, ckey)
              #encrypt cipher and its code with RSA
              eckey = recrypt(key_vec, ckey+cipher.chr, encrypt, (not encrypt))
              #p 'eckey1.size='+eckey.bytesize.to_s
              res = eckey + res
            else
              eckey = data[0, max_len]
              #p 'eckey2.size='+eckey.bytesize.to_s
              ckey = recrypt(key_vec, eckey, encrypt, (not encrypt))
              if ckey.bytesize>0
                #p 'ckey2.size='+ckey.bytesize.to_s
                cipher = ckey[-1].ord
                ciphlen = klen_to_bitlen(cipher)/8
                if ckey.bytesize==ciphlen+1
                  ckey = ckey[0..-2]
                  cipher_hash = encode_cipher_and_hash(cipher, 0)
                  data = data[max_len..-1]
                  res = key_recrypt(data, false, cipher_hash, ckey)
                else
                  res = ckey
                end
              end
            end
          else
            res = recrypt(key_vec, data, encrypt, (not encrypt))
          end
          if encrypt
            res = key_panhash + res
          elsif new_key_panhash
            res = recrypt_mes(res, new_key_panhash)
          end
        else
          res = '<'+_('Key is not found with panhash')+' ['+\
            PandoraUtils.bytes_to_hex(key_panhash)+']>'
        end
      elsif not encrypt
        res = '<'+_('Too short decrypted data')+' ['+data+']>'
      end
    end
    res
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
      if PandoraUtils.kind_from_panhash(person)==PandoraModel::PK_Person
        sel = PandoraModel.get_record_by_panhash(kind, person, nil, nil, 'first_name, last_name')
        #p 'key, person, sel='+[key, person, sel, PandoraUtils.bytes_to_hex(person)].inspect
        if (sel.is_a? Array) and (sel.size>0)
          aname, afamily = [Utf8String.new(sel[0][0]), Utf8String.new(sel[0][1])]
          key[KV_NameFamily] = [aname, afamily] if key
        end
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
      # show name only (or family)
      if othername and (othername == aname)
        res = afamily
      else
        res = aname
      end
    else
      # show name and family
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

  DefTcpPort = 5577
  DefUdpPort = 5577

  CommSize     = 7
  CommExtSize  = 10
  SegNAttrSize = 8

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
  EC_Fragment  = 10    # Кусок длинной записи
  EC_Mass      = 11    # Массовые уведомления
  EC_Tweet     = 12    # Уведомление присутствия (пришел, ушел)
  EC_Sync      = 16    # !!! Последняя команда в серии, или индикация "живости"
  # --------------------------- EC_Sync must be last
  EC_Wait      = 126   # Временно недоступен
  EC_Bye       = 127   # Рассоединение
  # signs only
  EC_Data      = 256   # Ждем данные

  ECC_Auth_Hello       = 0
  ECC_Auth_Cipher      = 1
  ECC_Auth_Puzzle      = 2
  ECC_Auth_Phrase      = 3
  ECC_Auth_Sign        = 4
  ECC_Auth_Captcha     = 5
  ECC_Auth_Simple      = 6
  ECC_Auth_Answer      = 7

  ECC_Query_Rel        = 0
  ECC_Query_Record     = 1
  ECC_Query_Fish       = 2
  ECC_Query_Search     = 3
  ECC_Query_Fragment   = 4

  ECC_News_Panhash      = 0
  ECC_News_Record       = 1
  ECC_News_Hook         = 2
  ECC_News_Notice       = 3
  ECC_News_SessMode     = 4
  ECC_News_Answer       = 5
  ECC_News_BigBlob      = 6
  ECC_News_Punnet       = 7
  ECC_News_Fragments    = 8

  ECC_Channel0_Open     = 0
  ECC_Channel1_Opened   = 1
  ECC_Channel2_Close    = 2
  ECC_Channel3_Closed   = 3
  ECC_Channel4_Fail     = 4

  ECC_Mass_Req          = 0
  #(1-127) is reserved for mass kinds MK_Chat, MK_Search and other

  ECC_Sync1_NoRecord    = 1
  ECC_Sync2_Encode      = 2
  ECC_Sync3_Confirm     = 3

  EC_Wait1_NoHookOrSeg       = 1
  EC_Wait2_NoFarHook         = 2
  EC_Wait3_NoFishRec         = 3
  EC_Wait4_NoSessOrSessHook  = 4
  EC_Wait5_NoNeighborRec     = 5

  ECC_Bye_Exit          = 200
  ECC_Bye_Unknown       = 201
  ECC_Bye_BadComm       = 202
  ECC_Bye_BadCommCRC    = 203
  ECC_Bye_BadCommLen    = 204
  ECC_Bye_BadSegCRC     = 205
  ECC_Bye_BadDataCRC    = 206
  ECC_Bye_DataTooShort  = 207
  ECC_Bye_DataTooLong   = 208
  ECC_Bye_NoAnswer      = 210
  ECC_Bye_Silent        = 211
  ECC_Bye_TimeOut       = 212
  ECC_Bye_Protocol      = 213

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
  CM_Keep         = 2
  CM_GetNotice    = 4
  CM_Captcha      = 8
  CM_CiperBF      = 16
  CM_CiperAES     = 32
  CM_Double       = 128

  # Connection state
  # RU: Состояние соединения
  CS_Connecting    = 0
  CS_Connected     = 1
  CS_Stoping       = 2
  CS_StopRead      = 3
  CS_Disconnected  = 4
  CS_CloseSession  = 5

  # Stage of exchange
  # RU: Стадия обмена
  ES_Begin        = 0
  ES_IpCheck      = 1
  ES_Protocol     = 2
  ES_Cipher       = 3
  ES_Puzzle       = 4
  ES_KeyRequest   = 5
  ES_Sign         = 6
  ES_Greeting     = 7
  ES_Captcha      = 8
  ES_PreExchange  = 9
  ES_Exchange     = 10

  # Max recv pack size for stadies
  # RU: Максимально допустимые порции для стадий
  MPS_Proto     = 150
  MPS_Puzzle    = 300
  MPS_Sign      = 500
  MPS_Captcha   = 3000
  MPS_Exchange  = 4000

  # Max data size of one sending segment
  # RU: Максимальный размер данных посылаемого сегмента
  MaxSegSize  = 1200

  # Sign meaning the data out of MaxSegSize, will be several segments
  # RU: Признак того, что данные за пределом, будет несколько сегментов
  LONG_SEG_SIGN   = 0xFFFF

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

  # Mass record kinds
  # RU: Типы массовых записей
  MK_Presence   = 1
  MK_Chat       = 2
  MK_Search     = 3
  MK_Fishing    = 4
  MK_Cascade    = 5
  MK_CiferBox   = 6

  # Node list indexes
  # RU: Индексы в списке узлов
  NL_Key             = 1  #22
  NL_BaseId          = 2  #16
  NL_Person          = 3  #22
  NL_Time            = 4  #4

  # Common field indexes of mass record array  #(size of field)
  # RU: Общие индексы полей в векторе массовых записей
  MR_KeepNodes       = 0  #(0-220) fill when register, not sending
  #==========================={head
  MR_Node            = 1  #22
  MR_Index           = 2  #4
  MR_Kind            = 3  #1  (presence, fishing, chat, search)
  MR_CrtTime         = 4  #4
  MR_ReqTime         = 5  #4
  MR_Trust           = 6  #1
  MR_Depth           = 7  #1
  #---------------------------head} (33 byte)
  #==========================={body
  MR_Param1          = 8  #1-30
  MR_Param2          = 9  #22-140
  MR_Param3          = 10  #0 или 22
  #---------------------------body} (23-140 byte)

  # Alive
  MRP_Nick           = MR_Param1  #~30    #sum: 33+(~30)= ~63

  # Chat field indexes
  # RU: Чатовые индексы полей
  #----Head sum: 70
  MRC_Comm    = MR_Param1   #1 (open, shut, mess)
  MRC_Body    = MR_Param2   #22 or ~140 (panhash or message)   #sum: 71+(23/~141)=  94/~112

  # Search request and answer field indexes
  # RU: Индексы полей в поисковом и ответом запросе
  #----Head sum: 70
  MRS_Kind       = MR_Param1    #1
  MRS_Request    = MR_Param2    #~140    #sum: 33+(~141)=  ~174
  MRA_Answer     = MR_Param3    #~22

  # Fishing order and line building field indexes
  # RU: Индексы полей в заявках на рыбалку и постройке линии
  #----Head sum: 70
  MRF_Fish            = MR_Param1   #22
  MRF_Fish_key        = MR_Param2   #22    #sum: 33+44=  77
  MRL_Fish_Baseid     = MR_Param3   #16

  # Punnet field indexes
  # RU: Индексы полей в корзине
  PI_FragsFile   = 0
  PI_Frags       = 1
  PI_FileName    = 2
  PI_File        = 3
  PI_FragFN      = 4
  PI_FragCount   = 5
  PI_FileSize    = 6
  PI_SymCount    = 7
  PI_HoldFrags   = 8

  # Session types
  # RU: Типы сессий
  ST_Hunter   = 0
  ST_Listener = 1
  ST_Fisher   = 2


  # Pool
  # RU: Пул
  class Pool
    attr_accessor :window, :sessions, :white_list, :time_now, \
      :node_list, :mass_records, :mass_ind, :found_ind, :punnets, :ind_mutex

    MaxWhiteSize = 500
    FishQueueSize = 100

    def initialize(main_window)
      super()
      @window = main_window
      @time_now = Time.now.to_i
      @sessions = Array.new
      @white_list = Array.new
      @node_list = Hash.new
      @mass_records = Array.new #PandoraUtils::RoundQueue.new(true)
      @mass_ind = -1
      @found_ind = 0
      @ind_mutex = Mutex.new
      @punnets = Hash.new
    end

    def base_id
      $base_id
    end

    def current_key
      PandoraCrypto.current_key(false, false)
    end

    def person
      key = current_key
      key[PandoraCrypto::KV_Creator]
    end

    def key_hash
      key = current_key
      key[PandoraCrypto::KV_Panhash]
    end

    def self_node
      res = PandoraModel.calc_node_panhash(key_hash, base_id)
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

    # Open or close local port and register tunnel
    # RU: Открыть или закрыть локальный порт и зарегать туннель
    def local_port(add, from, proto, session)
      port = 22
      host = nil
      i = from.index(':')
      if i
        host = from[0, i]
        port = from[i+1..-1]
      else
        port = from
      end
      host ||= Socket::INADDR_ANY
      if port and host
        port = port.to_i
        Thread.new do
          begin
            server = TCPServer.open(host, port)
            addr_str = server.addr[3].to_s+(' tcp')+server.addr[1].to_s
            PandoraUtils.log_message(LM_Info, _('Tunnel listen')+': '+addr_str)
          rescue
            server = nil
            PandoraUtils.log_message(LM_Warning, _('Cannot open port')+' TCP '+host.to_s+':'+tcp_port.to_s)
          end
          thread = Thread.current
          thread[:tcp_server] = server
          thread[:listen_tcp] = (server != nil)
          while thread[:listen_tcp] and server and (not server.closed?)
            socket = get_listener_client_or_nil(server)
            while thread[:listen_tcp] and not server.closed? and not socket
              sleep 0.05
              socket = get_listener_client_or_nil(server)
            end

            if Thread.current[:listen_tcp] and (not server.closed?) and socket
              host_ip = socket.peeraddr[2]
              unless $window.pool.is_black?(host_ip)
                host_name = socket.peeraddr[3]
                port = socket.peeraddr[1]
                proto = 'tcp'
                p 'TUNNEL: '+[host_name, host_ip, port, proto].inspect
                session = Session.new(socket, host_name, host_ip, port, proto, \
                  0, nil, nil, nil, nil)
              else
                PandoraUtils.log_message(LM_Info, _('IP is banned')+': '+host_ip.to_s)
              end
            end
          end
          server.close if server and (not server.closed?)
          PandoraUtils.log_message(LM_Info, _('Listener stops')+' '+addr_str) if server
          #$window.set_status_field(PandoraGtk::SF_Listen, nil, nil, false)
          #$tcp_listen_thread = nil
          #$window.correct_lis_btn_state
        end
      end
    end

    # Check is whole file exist
    # RU: Проверяет целый файл на существование
    def blob_exists?(sha1, models=nil, need_fn=nil)
      res = nil
      p 'blob_exists1   sha1='+sha1.inspect
      if (sha1.is_a? String) and (sha1.bytesize>0)
        model = PandoraUtils.get_model('Blob', models)
        if model
          mask = 0
          mask = PandoraModel::PSF_Harvest if (not need_fn)
          filter = ['sha1=? AND IFNULL(panstate,0)&?=0', sha1, mask]
          flds = 'id'
          flds << ', blob, size' if need_fn
          sel = model.select(filter, false, flds, nil, 1)
          p 'blob_exists2   sel='+sel.inspect
          res = (sel and (sel.size>0))
          if res and need_fn
            res = false
            fn = sel[0][1]
            fs = sel[0][2]
            if (fn.is_a? String) and (fn.size>1) and (fn[0]=='@')
              fn = Utf8String.new(fn)
              fn = fn[1..-1]
              fn = PandoraUtils.absolute_path(fn)
              if (fn.is_a? String) and (fn.size>0)
                fs_real = File.size?(fn)
                fs ||= fs_real
                res = [fn, fs] if fs
              end
            end
          end
        end
      end
      res
    end

    $max_harvesting_files = 300

    # Check interrupted file downloads and start again
    # RU: Проверить прерванные загрузки файлов и запустить снова
    def resume_harvest(models=nil)
      res = nil
      model = PandoraUtils.get_model('Blob', models)
      if model
        harbit = PandoraModel::PSF_Harvest.to_s
        filter = 'IFNULL(panstate,0)&'+harbit+'='+harbit
        sel = model.select(filter, false, 'sha1, blob', nil, $max_harvesting_files)
        #p '__++== resume_harvest   sel='+sel.inspect
        if sel and (sel.size>0)
          res = sel.size
          sel.each do |rec|
            sha1 = rec[0]
            blob = rec[1]
            if (blob.is_a? String) and (blob.size>1) and (blob[0]=='@') \
            and (sha1.is_a? String) and (sha1.size>1)
              add_mass_record(MK_Search, PandoraModel::PK_BlobBody, sha1)
            end
          end
        end
      end
      res
    end

    # Reset Harvest bit on blobs
    # RU: Сбрость Harvest бит на блобах
    def reset_harvest_bit(sha1, models=nil)
      res = nil
      model = PandoraUtils.get_model('Blob', models)
      if model
        harbit = PandoraModel::PSF_Harvest.to_s
        filter = ['sha1=? AND IFNULL(panstate,0)&'+harbit+'='+harbit, sha1]
        sel = model.select(filter, false, 'id, panstate', nil, $max_harvesting_files)
        p '--++--reset_harvest_bit   sel='+sel.inspect
        if sel and (sel.size>0)
          res = sel.size
          sel.each do |rec|
            id = rec[0]
            panstate = rec[1]
            panstate ||= 0
            panstate = (panstate & (~PandoraModel::PSF_Harvest))
            model.update({:panstate=>panstate}, nil, {:id=>id})
          end
        end
      end
      res
    end

    $fragment_size = 1024

    # Are all fragments assembled?
    # RU: Все ли фрагменты собраны?
    def frags_complite?(punnet_frags, frag_count=nil)
      frags = punnet_frags
      if frags.is_a? Array
        frag_count = frags[PI_FragCount]
        frags = frags[PI_Frags]
      end

      res = (frags.is_a? String) and (frags.bytesize>0)
      if res
        i = 0
        sym_count = frags.bytesize
        while res and (i<sym_count)
          if frags[i] != 255.chr
            if i<sym_count-1
              res = false
            else
              bit_tail_sh = 8 - (frag_count - i*8)
              bit_tail = 255 >> bit_tail_sh
              p '[bit_tail_sh, bit_tail, frag_count, frags[i].ord]='+[bit_tail_sh, \
                bit_tail, frag_count, frags[i].ord].inspect
              res = ((bit_tail & frags[i].ord) == bit_tail)
            end
          end
          i += 1
        end
      end
      res
    end

    # Initialize the punnet
    # RU: Инициализирует корзинку
    def init_punnet(sha1,filesize=nil,initfilename=nil)
      p 'init_punnet(sha1,filesize,initfilename)='+[sha1,filesize,initfilename].inspect
      punnet = @punnets[sha1]
      if not punnet.is_a? Array
        punnet = Array.new
      end
      fragfile, frags, filename, datafile, frag_fn = punnet
      sha1_name = PandoraUtils.bytes_to_hex(sha1)
      sha1_fn = File.join($pandora_files_dir, sha1_name)

      if (not datafile) and (not fragfile)
        filename ||= initfilename
        if filename
          dir = File.dirname(filename)
          p 'dir='+dir.inspect
          if (not dir) or (dir=='.') or (dir=='/')
            filename = File.join($pandora_files_dir, filename)
          end
        else
          fn_fs = blob_exists?(sha1, nil, true)
          if fn_fs
            fn, fs = fn_fs
            filename = PandoraUtils.absolute_path(fn)
            filesize ||= fs
          else
            filename = sha1_fn+'.dat'
          end
        end
        filename = Utf8String.new(filename)
        p 'filename='+filename.inspect

        frag_fn = PandoraUtils.change_file_ext(filename, 'frs')
        frag_fn = Utf8String.new(frag_fn)
        punnet[PI_FragFN] = frag_fn
        p 'frag_fn='+frag_fn.inspect

        file_size = File.size?(filename)
        p 'file_size='+file_size.inspect
        filename_ex = (File.exist?(filename) and (not file_size.nil?) and (file_size>=0))
        filesize ||= file_size if filename_ex
        punnet[PI_FileSize] = filesize
        p 'filename_ex='+filename_ex.inspect
        frag_fn_ex = File.exist?(frag_fn)
        p 'frag_fn_ex='+frag_fn_ex.inspect

        fragfile = nil
        if frag_fn_ex
          fragfile = File.open(frag_fn, 'rb+')
          p "fragfile = File.open(frag_fn, 'rb+')"
        elsif not filename_ex
          PandoraUtils.create_path(frag_fn)
          fragfile = File.new(frag_fn, 'wb+')
          p "fragfile = File.new(frag_fn, 'wb+')"
        end

        frag_count = (filesize.fdiv($fragment_size)).ceil
        sym_count = (frag_count.fdiv(8)).ceil
        p '[frag_count, sym_count]='+[frag_count, sym_count].inspect
        punnet[PI_FragCount] = frag_count
        punnet[PI_SymCount] = sym_count

        if fragfile
          punnet[PI_FragsFile] = fragfile
          frags = fragfile.read
          #frag_com = frags_complite?(frags)
          p 'frags='+frags.inspect
          sym_count = 1 if sym_count < 1
          if frags.bytesize != sym_count
            if sym_count>frags.bytesize
              frags += 0.chr * (sym_count-frags.bytesize)
              fragfile.seek(0)
              fragfile.write(frags)
              p 'set frags='+frags.inspect
            end
            begin
              fragfile.truncate(frags.bytesize)
            rescue => err
              p 'ERROR TRUNCATE: '+Utf8String.new(err.message)
            end
          end
          punnet[PI_Frags] = frags
          punnet[PI_HoldFrags] = 0.chr * frags.bytesize
        end

        if filename_ex
          if fragfile
            datafile = File.open(filename, 'rb+')
          else
            datafile = File.open(filename, 'rb')
          end
        else
          PandoraUtils.create_path(filename)
          datafile = File.new(filename, 'wb+')
        end
        punnet[PI_FileName] = filename
        punnet[PI_File] = datafile
      end
      @punnets[sha1] = punnet
    end

    # Load fragment
    # RU: Загрузить фрагмент
    def load_fragment(punnet, frag_number)
      res = nil
      datafile = punnet[PI_File]
      if datafile
        datafile.seek(frag_number*$fragment_size)
        res = datafile.read($fragment_size)
      end
      res
    end

    # Save fragment and update punnet
    # RU: Записать фрагмент и обновить козину
    def save_fragment(punnet, frag_number, frag_data)
      res = nil
      datafile = punnet[PI_File]
      fragfile = punnet[PI_FragsFile]
      frags = punnet[PI_Frags]
      p 'save_frag [datafile, fragfile, frags]='+[datafile, fragfile, frags].inspect
      if datafile and fragfile and frags
        datafile.seek(frag_number*$fragment_size)
        res = datafile.write(frag_data)
        sym_num = (frag_number.fdiv(8)).floor
        bit_num = frag_number - sym_num*8
        bit_mask = 1
        bit_mask = 1 << bit_num if bit_num>0
        p 'sf [sym_num, bit_num, bit_mask]='+[sym_num, bit_num, bit_mask].inspect
        frags[sym_num] = (frags[sym_num].ord | bit_mask).chr
        punnet[PI_Frags] = frags
        fragfile.seek(sym_num)
        res2 = fragfile.write(frags[sym_num])
      end
      res
    end

    # Hold or unhold fragment
    # RU: Удержать или освободить фрагмент
    def hold_frag_number(punnet, frag_number, hold=true)
      res = nil
      hold_frags = punnet[PI_HoldFrags]
      frag_count = punnet[PI_FragCount]
      if (frag_number>=0) and (frag_number<frag_count)
        sym_num = (frag_number.fdiv(8)).floor
        bit_num = frag_number - sym_num*8
        bit_mask = 1
        bit_mask = 1 << bit_num if bit_num>0
        p 'hold_frag_number [sym_num, bit_num, bit_mask]='+[sym_num, bit_num, bit_mask].inspect
        byte = hold_frags[sym_num].ord
        if hold
          byte = byte | bit_mask
        else
          byte = byte & (~bit_mask)
        end
        hold_frags[sym_num] = byte.chr
        res = true
      end
      res
    end

    # Search an index of next needed fragment and hold it
    # RU: Ищет индекс следующего нужного фрагмента и удерживает его
    def hold_next_frag(punnet, from_ind=nil)
      res = nil
      fragfile = punnet[PI_FragsFile]
      frags = punnet[PI_Frags]
      hold_frags = punnet[PI_HoldFrags]
      frag_count = punnet[PI_FragCount]
      p 'hold_next_frag  [fragfile, frags, frag_count]='+[fragfile, frags, frag_count].inspect
      if fragfile and (frags.is_a? String) and (frags.bytesize>0) \
      and (not frags_complite?(frags, frag_count))
        i = 0
        sym_count = frags.bytesize

        $window.mutex.synchronize do
          while i<sym_count
            byte = frags[i].ord
            if byte != 255
              hold_byte = hold_frags[i].ord
              p 'hold_byte='+hold_byte.inspect
              j = 0
              while (byte>0) and (i*8+j<frag_count-1) \
              and (((byte & 1) == 1) or ((hold_byte & 1) == 1))
                byte = byte >> 1
                hold_byte = hold_byte >> 1
                j += 1
              end
              p 'hold [frags[i].ord, i, j]='+[frags[i].ord, i, j].inspect
              break
            end
            i += 1
          end
          frag_number = i*8 + j
          if hold_frag_number(punnet, frag_number)
            res = frag_number
          end
        end
      end
      res
    end

    # Close punnet
    # RU: Закрывает корзинку
    def close_punnet(sha1_punnet, sha1=nil, models=nil)
      punnet = sha1_punnet
      if punnet.is_a? String
        sha1 ||= punnet
        punnet = nil
      end
      punnet = @punnets[sha1] if punnet.nil? and sha1
      if punnet.is_a? Array
        fragfile, frags, filename, datafile, frag_fn, frag_count, filesize = punnet[0, 7]
        fragfile.close if fragfile
        datafile.close if datafile
        frag_com = (fragfile.nil? or frags_complite?(frags, frag_count))
        file_size = File.size?(filename)
        p 'closepun [frag_com, file_size, filesize]='+[frag_com, \
          file_size, filesize].inspect
        full_com = (frag_com and file_size and (filesize==file_size))
        File.delete(frag_fn) if full_com and File.exist?(frag_fn)
        sha1 ||= @punnets.key(punnet)
        if sha1
          @punnets.delete(sha1)
          reset_harvest_bit(sha1, models) if full_com
        else
          @punnets.delete_if {| key, value | value==punnet }
        end
      end
    end

    # RU: Нужны фрагменты?
    def need_fragments?
      false
    end

    # Add a session to list
    # RU: Добавляет сессию в список
    def add_session(conn)
      if not sessions.include?(conn)
        sessions << conn
        window.update_conn_status(conn, conn.conn_type, 1)
      end
    end

    # Delete the session from list
    # RU: Удаляет сессию из списка
    def del_session(conn)
      if sessions.delete(conn)
        window.update_conn_status(conn, conn.conn_type, -1)
      end
    end

    def active_socket?
      res = false
      sessions.each do |session|
        if session.active?
          res = session
          break
        end
      end
      res
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
        (key.nil? or (s.skey[PandoraCrypto::KV_Panhash] == key)) }
      res
    end

    # Get a session by person, key and base id
    # RU: Возвращает сессию по человеку, ключу и идентификатору базы
    def sessions_of_personkeybase(person, key, base_id)
      res = nil
      if (person or key) #and base_id
        res = sessions.select do |s|
          sperson = s.to_person
          skey = s.to_key
          if s.skey
            sperson ||= s.skey[PandoraCrypto::KV_Creator]
            skey ||= s.skey[PandoraCrypto::KV_Panhash]
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

    # Close all session
    # RU: Закрывает все сессии
    def close_all_session(wait_sec=2)
      i = sessions.size
      while i>0
        i -= 1
        session = sessions[i]
        if session
          session.conn_mode = (session.conn_mode & (~PandoraNet::CM_Keep))
          session.conn_mode2 = (session.conn_mode2 & (~PandoraNet::CM_Keep))
          session.conn_state = CS_CloseSession if session.conn_state<CS_CloseSession
          sthread = session.send_thread
          if sthread and sthread.alive? and sthread.stop?
            sthread.run
          end
        end
      end
      if (sessions.size>0) and wait_sec
        time1 = Time.now.to_i
        time2 = time1
        while (sessions.size>0) and (time1+wait_sec>time2)
          sleep(0.05)
          Thread.pass
          time2 = Time.now.to_i
        end
      end
      i = sessions.size
      if i>0
        sleep(0.1)
        Thread.pass
        i = sessions.size
      end
      while i>0
        i -= 1
        session = sessions[i]
        if session
          session.conn_state = CS_CloseSession if session.conn_state<CS_CloseSession
          sthread = session.send_thread
          if sthread and sthread.alive? and sthread.stop?
            sthread.exit
          end
        end
      end
    end

    $node_rec_life_sec = 10*60

    def delete_old_node_records(cur_time=nil)
      cur_time ||= Time.now.to_i
      @node_list.delete_if do |nl|
        (nl.is_a? Array) and (nl[PandoraNet::NL_Time].nil? \
          or (nl[PandoraNet::NL_Time] < cur_time-$node_rec_life_sec))
      end
    end

    def add_node_to_list(akey, abaseid, aperson=nil, cur_time=nil)
      node = nil
      if akey and abaseid
        node = PandoraModel.calc_node_panhash(akey, abaseid)
        if node
          rec = @node_list[node]
          cur_time ||= Time.now.to_i
          if rec
            rec[PandoraNet::NL_Time] = cur_time
          else
            rec = [akey, abaseid, aperson, cur_time]
            @node_list[node] = rec
          end
          delete_old_node_records(cur_time)
        end
      end
      node
    end

    def get_node_params(node, models=nil)
      res = nil
      if (node.is_a? String) and (node.bytesize>0)
        res = @node_list[node]
        if not res
          node_model = PandoraUtils.get_model('Node', models)
          sel = node_model.select({:panhash => node}, false, 'key_hash, base_id', 'id ASC', 1)
          if sel and (sel.size>0)
            row = sel[0]
            akey = row[0]
            abaseid = row[0]
            aperson = PandoraModel.find_person_by_key(akey, models)
            node = add_node_to_list(akey, abaseid, aperson)
            res = @node_list[node] if node
          end
        end
      end
      res
    end

    $mass_rec_life_sec = 5*60

    def delete_old_mass_records(cur_time=nil)
      cur_time ||= Time.now.to_i
      @mass_records.delete_if do |mr|
        (mr.is_a? Array) and (mr[PandoraNet::MR_CrtTime].nil? \
          or (mr[PandoraNet::MR_CrtTime] < cur_time-$mass_rec_life_sec))
      end
    end

    def find_mass_record_by_index(src_node, src_ind)
      res = nil
      res = @mass_records.find do |mr|
        ((mr[PandoraNet::MR_Node] == src_node) and \
        (mr[PandoraNet::MR_Index] == src_ind))
      end
      res
    end

    def find_mass_record_by_params(src_node, akind, param1, param2=nil, param3=nil)
      res = nil
      param2 = AsciiString.new(param2) if akind==MK_Search
      res = @mass_records.find do |mr|
        ((mr[PandoraNet::MR_Node] == src_node) and \
        (param1.nil? or (mr[PandoraNet::MR_Param1] == param1)) and \
        (param2.nil? or (mr[PandoraNet::MR_Param2] == param2)) and \
        (param3.nil? or (mr[PandoraNet::MR_Param3] == param3)))
      end
      res
    end

    # Register mass record and its keeper to queue
    # RU: Зарегать массовую запись и её хранителя в очереди
    def register_mass_record(src_node=nil, src_ind=nil, keep_node=nil)
      mr = nil
      src_node ||= self_node
      keep_node ||= src_node
      if src_ind
        mr = find_mass_record_by_index(src_node, src_ind)
        if mr
          mr[MR_KeepNodes] << keep_node if not mr[MR_KeepNodes].include?(keep_node)
        end
      end
      if not mr
        if (not src_ind) and (src_node==self_node)
          ind_mutex.synchronize do
            @mass_ind += 1
            src_ind = @mass_ind
          end
        end
        if src_ind
          mr = Array.new
          mr[MR_Node]     = src_node
          mr[MR_Index]    = src_ind
          mr[MR_KeepNodes] = [keep_node]
          @mass_records << mr
        end
      end
      mr
    end

    # Add mass record to queue
    # RU: Добавить массовую запись в очередь
    def add_mass_record(akind, param1, param2=nil, param3=nil, src_node=nil, \
    src_ind=nil, atime=nil, atrust=nil, adepth=nil, keep_node=nil, \
    hunt=nil, models=nil)
      src_node ||= self_node
      mr = find_mass_record_by_params(src_node, akind, param1, param2, param3)
      if not mr
        atrust ||= 0
        adepth ||= 2
        if adepth>0
          cur_time = Time.now.to_i
          delete_old_mass_records(cur_time)
          case akind
            when MK_Search
              param2 = AsciiString.new(param2)
          end
          mr = register_mass_record(src_node, src_ind, keep_node)
          if mr
            atime ||= cur_time
            adepth -= 1
            mr[MR_Kind]     = akind
            mr[MR_CrtTime]     = atime
            mr[MR_Trust]    = atrust
            mr[MR_Depth]    = adepth
            mr[MR_Param1]   = param1
            mr[MR_Param2]   = param2
            mr[MR_Param3]   = param3
            case akind
              when MK_Presence
                $window.set_status_field(PandoraGtk::SF_Radar, @mass_records.size.to_s)
                hpaned = $window.radar_hpaned
                if (hpaned.max_position - hpaned.position) > 24
                  radar_sw = $window.radar_sw
                  radar_sw.update_btn.clicked
                else
                  PandoraGtk.show_radar_panel
                end
              when MK_Fishing
                $window.set_status_field(PandoraGtk::SF_Fisher, @mass_records.size.to_s)
                info = ''
                fish = param1
                fish_key = param2
                info << PandoraUtils.bytes_to_hex(fish) if fish
                info << ', '+PandoraUtils.bytes_to_hex(fish_key) if fish_key.is_a? String
                PandoraUtils.log_message(PandoraUtils::LM_Trace, _('Bob is generated')+ \
                  ' '+@mass_ind.to_s+':['+info+']')
              when MK_Search
                $window.set_status_field(PandoraGtk::SF_Search, @mass_records.size.to_s)
                PandoraNet.start_hunt if hunt
              when MK_Chat
                #
            end
          end
        end
      end
      mr
    end

    def connect_sessions_to_hook(sessions, sess, hook, fisher=false, line=nil)
      res = false
      if (sessions.is_a? Array) and (sessions.size>0)
        sessions.each do |session|
          sthread = session.send_thread
          if sthread and sthread.alive? and sthread.stop?
            sess_hook, rec = sess.reg_line(line, nil, hook)
            fhook, rec = session.reg_line(nil, sess, nil, nil, sess_hook)
            sess_hook2, rec2 = sess.reg_line(nil, session, nil, sess_hook, fhook)
            PandoraUtils.log_message(PandoraUtils::LM_Info, _('Unfreeze fisher')+\
              ': [sess, hook]='+[session.object_id, sess_hook].inspect)
            sthread.run
            res = true
            break
          end
        end
      end
      res
    end

    # Search in bases
    # RU: Поиск в базах
    def search_in_local_bases(text, bases='auto', th=nil, from_id=nil, limit=nil)

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

      model = nil
      fields, sort, word1, word2, word3, words, word1dup, filter1, filter2 = nil
      bases = 'Person' if (bases == 'auto')

      if bases == 'Person'
        model = PandoraUtils.get_model('Person')
        fields = 'first_name, last_name, birth_day'
        sort = 'first_name, last_name'
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
      end
      limit ||= 100

      res = nil
      while ((not th) or th[:processing]) and (not res) and model
        if model
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
        end
      end
      res ||= []
      res.uniq!
      res.compact!
      [res, bases]
    end

    # Find or create session with necessary node
    # RU: Находит или создает соединение с нужным узлом
    def init_session(addr=nil, nodehashs=nil, send_state_add=nil, dialog=nil, \
    node_id=nil, persons=nil, key_hashs=nil, base_id=nil, aconn_mode=nil)
      p '-------init_session: '+[addr, nodehashs, send_state_add, dialog, node_id, \
        persons, key_hashs, base_id].inspect
      person = PandoraUtils.first_array_element_or_val(persons)
      key_hash = PandoraUtils.first_array_element_or_val(key_hashs)
      nodehash = PandoraUtils.first_array_element_or_val(nodehashs)
      res = nil
      send_state_add ||= 0
      sessions = sessions_of_personkeybase(person, key_hash, base_id)
      sessions << sessions_of_node(nodehash) if nodehash
      sessions << sessions_of_address(addr) if addr
      sessions.flatten!
      sessions.uniq!
      sessions.compact!
      if (sessions.is_a? Array) and (sessions.size>0)
        sessions.each_with_index do |session, i|
          session.send_state = (session.send_state | send_state_add)
          #session.conn_mode = (session.conn_mode | aconn_mode)
          session.dialog = nil if (session.dialog and session.dialog.destroyed?)
          session.dialog = dialog if dialog and (i==0)
          if session.dialog and (not session.dialog.destroyed?) \
          and session.dialog.online_btn.active?
            session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep)
            if ((session.socket and (not session.socket.closed?)) or session.active_hook)
              session.dialog.online_btn.safe_set_active(true)
              #session.dialog.online_btn.inconsistent = false
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
            #p 'filter='+filter.inspect
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
              aconn_mode ||= 0
              if $window.visible? #and $window.has_toplevel_focus?
                aconn_mode = (aconn_mode | PandoraNet::CM_Captcha)
              end
              aconn_mode = (CM_Hunter | aconn_mode)
              session = Session.new(nil, host, addr, port, proto, \
                aconn_mode, node_id_i, dialog, send_state_add, nodehash, \
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
    def stop_session(node=nil, persons=nil, nodehashs=nil, disconnect=nil, \
    session=nil)  #, wait_disconnect=true)
      res = false
      p 'stop_session1 nodehashs='+nodehashs.inspect
      person = PandoraUtils.first_array_element_or_val(persons)
      nodehash = PandoraUtils.first_array_element_or_val(nodehashs)
      sessions = Array.new
      sessions << session if session
      sessions << sessions_of_node(nodehash) if nodehash
      sessions << sessions_of_address(node) if node
      sessions << sessions_of_person(person) if person
      sessions.flatten!
      sessions.uniq!
      sessions.compact!
      if (sessions.is_a? Array) and (sessions.size>0)
        sessions.each do |session|
          if (not session.nil?)
            session.conn_mode = (session.conn_mode & (~PandoraNet::CM_Keep))
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
        port = PandoraNet::DefTcpPort
        proto = 'tcp'
      end
      [host, port, proto]
    end

    # Call callback address
    # RU: Стукануться по обратному адресу
    def check_incoming_addr(addr, host_ip)
      res = false
      #p 'check_incoming_addr  [addr, host_ip]='+[addr, host_ip].inspect
      if (addr.is_a? String) and (addr.size>0)
        host, port, proto = decode_node(addr)
        host.strip!
        host = host_ip if (not host) or (host=='')
        #p 'check_incoming_addr  [host, port, proto]='+[host, port, proto].inspect
        if (host.is_a? String) and (host.size>0)
          p 'check_incoming_addr DONE [host, port, proto]='+[host, port, proto].inspect
          res = true
        end
      end
    end

  end

  $incoming_addr = nil
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

  # Version of application and protocol (may be different)
  # RU: Версия программы и протокола (могут отличаться)
  AppVersion   = '0.67'
  ProtoVersion = 'pandora0.67'

  # Session of data exchange with another node
  # RU: Сессия обмена данными с другим узлом
  class Session

    include PandoraUtils

    attr_accessor :host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_mode2, \
      :conn_state, :stage, :dialog, \
      :send_thread, :read_thread, :socket, :read_state, :send_state, \
      :send_models, :recv_models, :sindex, :read_queue, :send_queue, :confirm_queue, \
      :params, :cipher, :ciphering, \
      :rcmd, :rcode, :rdata, :scmd, :scode, :sbuf, :log_mes, :skey, :s_encode, \
      :r_encode, \
      :media_send, :node_id, :node_panhash, :to_person, :to_key, :to_base_id, :to_node, \
      :captcha_sw, :hooks, :mass_ind, :sess_trust, :notice, :activity

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

    # Link to parent pool
    # RU: Ссылка на родительский пул
    def pool
      res = nil
      res = $window.pool if $window
      res
    end

    LHI_Line       = 0
    LHI_Session    = 1
    LHI_Far_Hook   = 2
    LHI_Sess_Hook  = 3

    # Type of session
    # RU: Тип сессии
    def conn_type
      res = nil
      if ((@conn_mode & CM_Hunter)>0)
        res = ST_Hunter
      else
        res = ST_Listener
      end
    end

    def hunter?
      res = nil
      res = ((@conn_mode & CM_Hunter)>0) if (@conn_mode.is_a? Integer)
      res
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

    # Retutn a fishing hook of active medium session
    # RU: Возвращает рабацкий крючок активной посреднической сессии
    def active_hook
      i = @hooks.index {|rec| rec[LHI_Session] and rec[LHI_Session].active? }
    end

    # Delete hook(s) of the medium session
    # RU: Удаляет крючок заданной сессии-посредника
    def del_sess_hooks(sess)
      @hooks.delete_if {|rec| rec[LHI_Session]==sess }
    end

    # Cifer data of buffer before sending
    # RU: Шифрует данные буфера перед отправкой
    def cipher_buf(buf, encode=true)
      res = buf
      if @cipher
        key = @cipher[PandoraCrypto::KV_Obj]
        if res and key and (not (key.is_a? Integer))
          #if encode
          #  p log_mes+'####bef#### CIPHER ENC buf='+res.inspect
          #else
          #  p log_mes+'####bef#### CIPHER DEC buf='+res.bytesize.inspect
          #end
          res = PandoraCrypto.recrypt(@cipher, res, encode)
          #if encode
          #  p log_mes+'#####aff##### CIPHER ENC buf='+res.bytesize.inspect
          #else
          #  p log_mes+'#####aff##### CIPHER DEC buf='+res.inspect
          #end
        end
      else
        p log_mes+'####-=-=--=-=-=-=-==-NO CIPHER buf='+res.inspect
        @ciphering = nil
      end
      res
    end

    # Flag in command showing buffer is cifered
    # RU: Флаг в команде, показывающий, что буфер шифрован
    CipherCmdBit   = 0x80

    # Send command, code and date (if exists)
    # RU: Отправляет команду, код и данные (если есть)
    def send_comm_and_data(index, cmd, code, data=nil)
      res = nil
      index ||= 0  #нужно ли??!!
      code ||= 0   #нужно ли??!!
      lengt = 0
      lengt = data.bytesize if data
      @last_send_time = pool.time_now
      if (cmd != EC_Media)
        p log_mes+'->>SEND [cmd, code, lengt] [stage, ciphering]='+\
          [cmd, code, lengt].inspect+' '+[@stage, @ciphering].inspect
        data = cipher_buf(data, true) if @ciphering
        cmd = (cmd | CipherCmdBit) if @ciphering
      end
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
        #p [segsign, segdata, segsize].inspect
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
            # usual: A0 - video, B8 - voice (higher)
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
        else
          res = nil
          if sended != -1
            PandoraUtils.log_message(LM_Error, _('Not all data was sent')+' '+sended.to_s)
          end
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
          else
            res = nil
            if sended != -1
              PandoraUtils.log_message(LM_Error, _('Not all data was sent')+'2 '+sended.to_s)
            end
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

    def open_last_cipher(sender_keyhash)
      res = nil
      if (sender_keyhash.is_a? String) and (sender_keyhash.bytesize>0)
        filter = {:key_hash=>sender_keyhash}
        node_model = PandoraUtils.get_model('Node', @recv_models)
        sel = node_model.select(filter, false, 'session_key', 'modified DESC', 1)
        if sel and (sel.size>0)
          session_key = sel[0][0]
          if (session_key.is_a? String) and (session_key.bytesize>0)
            ciph_key = PandoraCrypto.open_key(session_key, @recv_models, false)
            res = ciph_key if (ciph_key.is_a? Array)
          end
        end
      end
      res
    end

    # Add segment (chunk, grain, phrase) to pack and send when it's time
    # RU: Добавляет сегмент в пакет и отправляет если пора
    def add_send_segment(ex_comm, last_seg=true, param=nil, ascode=nil)
      res = nil
      ascmd = ex_comm
      ascode ||= 0
      asbuf = nil
      @activity = 1
      case ex_comm
        when EC_Auth
          #p log_mes+'first key='+key.inspect
          key_hash = pool.key_hash
          if key_hash
            ascode = EC_Auth
            ascode = ECC_Auth_Hello
            params['mykey'] = key_hash
            tokey = param
            params['tokey'] = tokey
            mode = 0
            mode |= CM_GetNotice if $get_notice
            mode |= CM_Captcha if (@conn_mode & CM_Captcha)>0
            hparams = {:version=>ProtoVersion, :mode=>mode, :mykey=>key_hash, :tokey=>tokey, \
              :notice=>(($notice_depth << 8) | $notice_trust)}
            hparams[:addr] = $incoming_addr if $incoming_addr and ($incoming_addr != '')
            #acipher = open_last_cipher(tokey)
            #if acipher
            #  hparams[:cipher] = acipher[PandoraCrypto::KV_Panhash]
            #  @cipher = acipher
            #end
            asbuf = PandoraUtils.hash_to_namepson(hparams)
          else
            ascmd = EC_Bye
            ascode = ECC_Bye_Exit
            asbuf = nil
          end
        when EC_Bye
          ascmd = EC_Bye
          ascode = ECC_Bye_Exit
          asbuf = param
        else
          asbuf = param
      end
      if (@send_queue.single_read_state != PandoraUtils::RoundQueue::SQS_Full)
        res = @send_queue.add_block_to_queue([ascmd, ascode, asbuf])
      else
        p '--add_send_segment: @send_queue OVERFLOW !!!'
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

    # Tell other side my session mode
    # RU: Сообщить другой стороне мой режим сессии
    def send_conn_mode
      @conn_mode ||= 0
      buf = (@conn_mode & 255).chr
      p 'send_conn_mode  buf='+buf.inspect
      add_send_segment(EC_News, true, AsciiString.new(buf), ECC_News_SessMode)
    end

    def skey_trust
      res = @skey[PandoraCrypto::KV_Trust]
      res = -1.0 if not res.is_a?(Float)
      res
    end

    def active?
      res = (conn_state == CS_Connected)
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
          params['cipher']   = hash['cipher']
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
          when ES_PreExchange, ES_Exchange
            @max_pack_size = MPS_Exchange
        end
      end

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

      # React to hello
      # RU: Отреагировать на приветствие
      def init_skey_or_error(first=true)

        skey_panhash = params['srckey']
        if (skey_panhash.is_a? String) and (skey_panhash.bytesize>0)
          if first
            cipher_phash = params['cipher']
            if (cipher_phash.is_a? String) and (cipher_phash.bytesize>0)
              @cipher = PandoraCrypto.open_key(cipher_phash, @recv_models, false)
              if (@cipher.is_a? Array)
                phrase, init = get_sphrase(true)
                @stage = ES_Cipher
                @scode = ECC_Auth_Cipher
                @scmd  = EC_Auth
                @sbuf = phrase
                set_max_pack_size(ES_Puzzle)
              end
            end
          end
          if (@stage != ES_Cipher)
            if first and (@stage == ES_Protocol) and $puzzle_bit_length \
            and ($puzzle_bit_length>0) and (not hunter?)
              # init puzzle
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
          end
        else
          err_scmd('Key panhash is required')
        end
      end

      def open_or_gen_cipher(skey_phash, save=true)
        res = open_last_cipher(skey_phash)
        if not res
          type_klen = (PandoraCrypto::KT_Aes | PandoraCrypto::KL_bit256)
          cipher_hash = PandoraCrypto::KT_Rsa
          key_vec = PandoraCrypto.generate_key(type_klen, cipher_hash)
          res = key_vec
          if save
            key_model = PandoraUtils.get_model('Key', @recv_models)
            PandoraCrypto.save_key(key_vec, pool.person, nil, key_model)
          end
        end
        res
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

      # Add or delete tunnel
      # RU: Добавить или удалить туннель
      def control_tunnel(direct, add, from, to, proto='tcp')
        if direct
          tunnel = pool.local_port(add, from, proto, self)
          if tunnel
            @scmd = EC_Channel
            @scode = ECC_Channel1_Opened
            @sbuf = PandoraUtils.rubyobj_to_pson([add, from, to, proto, tunnel])
          else
            err_scmd('Cannot rule local port')+': [add, from, proto]='+[add, from, proto].inspect
          end
        else
        end
      end

      # Update record about node
      # RU: Обновить запись об узле
      def update_node(skey_panhash=nil, sbase_id=nil, trust=nil, session_key=nil)
        p log_mes + '++++++++update_node [skey_panhash, sbase_id, trust, session_key]=' \
          +[skey_panhash, sbase_id, trust, session_key].inspect

        skey_creator = @skey[PandoraCrypto::KV_Creator]
        init_and_check_node(skey_creator, skey_panhash, sbase_id)
        creator = PandoraCrypto.current_user_or_key(true)
        if hunter? or (not skey_creator) or (skey_creator != creator)
          # check messages if it's not session to myself
          @send_state = (@send_state | CSF_Message)
        end

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

        readflds = 'id, state, sended, received, one_ip_count, bad_attempts, ' \
           +'ban_time, panhash, key_hash, base_id, creator, created, addr, ' \
           +'domain, tport, uport'

        trusted = ((trust.is_a? Float) and (trust>0))
        filter = {:key_hash=>skey_panhash, :base_id=>sbase_id}
        #if not trusted
        #  filter[:addr_from] = host_ip
        #end
        node_model = PandoraUtils.get_model('Node', @recv_models)
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

        #p '=====%%%% %%%: [aaddr, adomain, @host_ip, @host_name]'+[aaddr, adomain, @host_ip, @host_name].inspect

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
        values[:session_key]  = session_key if session_key
        values[:ban_time]     = aban_time
        values[:modified]     = time_now

        inaddr = params['addr']
        if inaddr and (inaddr != '')
          host, port, proto = pool.decode_node(inaddr)
          #p log_mes+'ADDR [addr, host, port, proto]='+[addr, host, port, proto].inspect
          if host and (host.size>0) and (adomain.nil? or (adomain.size==0)) #and trusted
            adomain = host
            port = PandoraNet::DefTcpPort if (not port) or (port==0)
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
            adomain = bdomain if bdomain and (bdomain.size>0) \
              and (adomain.nil? or (adomain==''))

            values[:addr_type] ||= baddr_type
            node_model.update(nil, nil, filter2)
          end
        end

        adomain = @host_name if @host_name and (@host_name.size>0) \
          and (adomain.nil? or (adomain==''))
        aaddr = @host_ip if (not aaddr) or (aaddr=='')

        values[:addr] = aaddr
        values[:domain] = adomain
        values[:tport] = atport
        values[:uport] = auport

        panhash = node_model.calc_panhash(values)
        values[:panhash] = panhash
        @node_panhash = panhash

        res = node_model.update(values, nil, filter)
      end

      # Process media segment
      # RU: Обработать медиа сегмент
      def process_media_segment(cannel, mediabuf)
        if not dialog
          @conn_mode = (@conn_mode | PandoraNet::CM_Keep)
          #node = PandoraNet.encode_addr(host_ip, port, proto)
          panhash = @skey[PandoraCrypto::KV_Creator]
          @dialog = PandoraGtk.show_cabinet(panhash, self, conn_type)
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
            appsrc.play if (not PandoraUtils.elem_playing?(appsrc))
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

      # Get hook for line
      # RU: Взять крючок для лески
      def reg_line(line, session, far_hook=nil, hook=nil, sess_hook=nil, fo_ind=nil)
        p '--reg_line  [far_hook, hook, sess_hook, self, session]='+\
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
        p '=====reg_line  [session, far_hook, hook, sess_hook]='+[session.object_id, \
          far_hook, hook, sess_hook].inspect
        [hook, rec]
      end

      # Initialize the fishing line, send hooks
      # RU: Инициализировать рыбацкую линию, разослать крючки
      def init_line(line_order, akey_hash=nil)
        res = nil
        fisher, fisher_key, fisher_baseid, fish, fish_key = line_order
        if fisher_key and fisher_baseid and (fish or fish_key)
          if akey_hash and (fisher_key == akey_hash) and (fisher_baseid == pool.base_id)
            # fishing from me
            PandoraUtils.log_message(LM_Warning, _('Somebody uses your ID'))
          else
            res = false
            # check fishing to me (not using!!!)
            if false and ((fish == pool.person) or (fish_key == akey_hash))
              p log_mes+'Fishing to me!='+session.to_key.inspect
              # find existing (sleep) sessions
              sessions = sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
              if (not sessions.is_a? Array) or (sessions.size==0)
                sessions = Session.new(111)
              end
              line = line_order.dup
              line[MR_Fish] ||= pool.person
              line[MR_Fish_key] ||= pool.key_hash
              line[LN_Fish_Baseid] = pool.base_id
              p log_mes+' line='+line.inspect
              #session = connect_sessions_to_hook([session], self, hook)
              my_hook, rec = reg_line(line, session)
              if my_hook
                line_raw = PandoraUtils.rubyobj_to_pson(line)
                add_send_segment(EC_News, true, my_hook.chr + line_raw, \
                  ECC_News_Hook)
              end
              # sessions.each do |session|
              #    hook, rec = session.reg_line(line, self, nil, nil, my_hook)
              #    session.add_send_segment(EC_News, true, hook.chr + line_raw, \
              #      ECC_News_Hook)
              #  end
              #end
              res = true
            end

            sessions = nil
            # check fishing to outside
            fisher_sess = false
            if (@to_person and (fish == @to_person)) \
            or (@to_key and (fish_key == @to_key))
              sessions = pool.sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
              fisher_sess = true
            else
              # check other session
              sessions = pool.sessions_of_person(fish)
              sessions.concat(pool.sessions_of_key(fish_key))
            end
            #sessions.flatten!
            sessions.uniq!
            sessions.compact!
            if (sessions.is_a? Array) and (sessions.size>0)
              p 'FOUND fishers/fishes: '+sessions.size.to_s
              line = line_order.dup
              if fisher_sess
                line[MR_Fish] = @to_person if (not fish)
                line[MR_Fish_key] = @to_key if (not fish_key)
                line[LN_Fish_Baseid] = @to_base_id
              end
              sessions.each do |session|
                p log_mes+'--Fisher/Fish session='+[session.object_id, session.to_key].inspect
                if not fisher_sess
                  line[MR_Fish] = session.to_person if (not fish)
                  line[MR_Fish_key] = session.to_key if (not fish_key)
                  line[LN_Fish_Baseid] = session.to_base_id
                end
                p log_mes+' reg.line='+line.inspect
                my_hook, rec = reg_line(line, session)
                if my_hook
                  sess_hook, rec = session.reg_line(line, self, nil, nil, my_hook)
                  if sess_hook
                    reg_line(line, session, nil, nil, my_hook, sess_hook)
                    line_raw = PandoraUtils.rubyobj_to_pson(line)
                    session.add_send_segment(EC_News, true, sess_hook.chr + line_raw, \
                      ECC_News_Hook)
                    add_send_segment(EC_News, true, my_hook.chr + line_raw, \
                      ECC_News_Hook)
                  end
                end
              end
              res = true
            else
              res = false
            end
          end
        end
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
              sess_hook = rec[LHI_Sess_Hook]
              if sess and sess_hook
                rec = sess.hooks[sess_hook]
                if rec
                  if rec[LHI_Line]
                    p 'Middle hook'
                    #hook = sess.hooks.index {|rec| (rec[LHI_Session]==self) and (rec[LHI_Sess_Hook]==hook) }
                    if rec[LHI_Far_Hook]
                      res = sess.send_queue.add_block_to_queue([EC_Bite, rec[LHI_Far_Hook], segment])
                    else
                      res = sess.send_queue.add_block_to_queue([EC_Lure, hook, segment])
                    end
                    @last_send_time = pool.time_now
                  else
                    p 'Terminal hook'
                    cmd = segment[0].ord
                    code = segment[1].ord
                    data = nil
                    data = segment[2..-1] if (segment.bytesize>2)
                    res = sess.read_queue.add_block_to_queue([cmd, code, data])
                  end
                else
                  p 'No neighbor rec'
                  @scmd = EC_Wait
                  @scode = EC_Wait5_NoNeighborRec
                  @scbuf = nil
                end
              else
                p 'No sess or sess_hook'
                @scmd = EC_Wait
                @scode = EC_Wait4_NoSessOrSessHook
                @scbuf = nil
              end
            else
              p 'No hook rec'
              @scmd = EC_Wait
              @scode = EC_Wait3_NoFishRec
              @scbuf = nil
            end
          else
            p 'No far hook'
            @scmd = EC_Wait
            @scode = EC_Wait2_NoFarHook
            @scbuf = nil
          end
        else
          p 'No hook or segment'
          @scmd = EC_Wait
          @scode = EC_Wait1_NoHookOrSeg
          @scbuf = nil
        end
        res
      end

      def set_trust_and_notice(trust=nil)
        trust ||= @skey[PandoraCrypto::KV_Trust]
        @sess_trust = trust
        if (@notice.is_a? Integer)
          not_trust = (@notice & 0xFF)
          not_dep = (@notice >> 8)
          if not_dep >= 0
            nick = PandoraCrypto.short_name_of_person(@skey, @to_person, 1)
            pool.add_mass_record(MK_Presence, nick, nil, nil, \
              @to_node, 0, nil, not_trust, not_dep, pool.self_node, \
              nil, @recv_models)
          end
        end
      end

      case rcmd
        when EC_Auth
          if @stage<=ES_Captcha
            if rcode<=ECC_Auth_Answer
              if (rcode==ECC_Auth_Hello) and (@stage==ES_Protocol) #or (@stage==ES_Sign))
              #ECC_Auth_Hello
                recognize_params
                if scmd != EC_Bye
                  vers = params['version']
                  if vers==ProtoVersion
                    addr = params['addr']
                    p log_mes+'addr='+addr.inspect
                    # need to change an ip checking
                    pool.check_incoming_addr(addr, host_ip) if addr
                    @sess_mode = params['mode']
                    p log_mes+'ECC_Auth_Hello @sess_mode='+@sess_mode.inspect
                    @notice = params['notice']
                    init_skey_or_error(true)
                  else
                    err_scmd('Unsupported protocol "'+vers.to_s+\
                      '", require "'+ProtoVersion+'"', ECC_Bye_Protocol)
                  end
                end
              elsif (rcode==ECC_Auth_Cipher) and ((@stage==ES_Protocol) or (@stage==ES_Cipher))
              #ECC_Auth_Cipher
                if @cipher
                  @cipher = PandoraCrypto.open_key(@cipher, @recv_models, true)
                  if @cipher[PandoraCrypto::KV_Obj]
                    if hunter?
                      if (@stage==ES_Protocol)
                        phrase1 = rdata
                        phrase1 = OpenSSL::Digest::SHA384.digest(phrase1)
                        #p log_mes+'===========@cipher='+@cipher.inspect
                        sign1 = PandoraCrypto.make_sign(@cipher, phrase1)
                        if sign1
                          phrase2, init = get_sphrase(true)
                          @stage = ES_Cipher
                          @scode = ECC_Auth_Cipher
                          @scmd  = EC_Auth
                          sign1_phrase2_baseid = PandoraUtils.rubyobj_to_pson([sign1, \
                            phrase2, pool.base_id])
                          @sbuf = sign1_phrase2_baseid
                          set_max_pack_size(ES_Sign)
                        else
                          err_scmd('Cannot create sign 1')
                        end
                      else
                        sign2_baseid, len = PandoraUtils.pson_to_rubyobj(rdata)
                        if (sign2_baseid.is_a? Array)
                          sign2, sbaseid = sign2_baseid
                          phrase2 = params['sphrase']
                          if PandoraCrypto.verify_sign(@cipher, \
                          OpenSSL::Digest::SHA384.digest(phrase2), sign2)
                            skey_panhash = params['tokey']
                            #p log_mes+'======skey_panhash='+[params, skey_panhash].inspect
                            @skey = PandoraCrypto.open_key(skey_panhash, @recv_models, true)
                            if @skey
                              @stage = ES_Exchange
                              set_max_pack_size(ES_Exchange)
                              trust = @skey[PandoraCrypto::KV_Trust]
                              update_node(skey_panhash, sbaseid, trust, \
                                @cipher[PandoraCrypto::KV_Panhash])
                              set_trust_and_notice
                              PandoraUtils.play_mp3('online')
                            else
                              err_scmd('Cannot init skey 1')
                            end
                          else
                            err_scmd('Wrong cipher sign 1')
                          end
                        else
                          err_scmd('Must be sign and baseid')
                        end
                      end
                    else  #listener
                      sign1_phrase2_baseid, len = PandoraUtils.pson_to_rubyobj(rdata)
                      if (sign1_phrase2_baseid.is_a? Array)
                        phrase1 = params['sphrase']
                        sign1, phrase2, sbaseid = sign1_phrase2_baseid
                        if PandoraCrypto.verify_sign(@cipher, \
                        OpenSSL::Digest::SHA384.digest(phrase1), sign1)
                          skey_panhash = params['srckey']
                          @skey = PandoraCrypto.open_key(skey_panhash, @recv_models, true)
                          if @skey
                            phrase2 = OpenSSL::Digest::SHA384.digest(phrase2)
                            sign2 = PandoraCrypto.make_sign(@cipher, phrase2)
                            if sign2
                              phrase2, init = get_sphrase(true)
                              @scmd  = EC_Auth
                              @scode = ECC_Auth_Cipher
                              sign2_baseid = PandoraUtils.rubyobj_to_pson([sign2, \
                                pool.base_id])
                              @sbuf = sign2_baseid
                              @stage = ES_PreExchange
                              trust = @skey[PandoraCrypto::KV_Trust]
                              update_node(skey_panhash, sbaseid, trust, \
                                @cipher[PandoraCrypto::KV_Panhash])
                              set_trust_and_notice
                              set_max_pack_size(ES_Exchange)
                              PandoraUtils.play_mp3('online')
                            else
                              err_scmd('Cannot create sign 2')
                            end
                          else
                            err_scmd('Cannot init skey 2')
                          end
                        else
                          err_scmd('Wrong cipher sign 2')
                        end
                      else
                        err_scmd('Must be sign and phrase')
                      end
                    end
                  else
                    err_scmd('Cannot init cipher')
                  end
                else
                  err_scmd('No opened cipher')
                end
              elsif ((rcode==ECC_Auth_Puzzle) or (rcode==ECC_Auth_Phrase)) \
              and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
              #ECC_Auth_Puzzle, ECC_Auth_Phrase
                if rdata and (rdata != '')
                  rphrase = rdata
                  params['rphrase'] = rphrase
                else
                  rphrase = params['rphrase']
                end
                p log_mes+'recived phrase len='+rphrase.bytesize.to_s
                if rphrase and (rphrase.bytesize>0)
                  if rcode==ECC_Auth_Puzzle  #phrase for puzzle
                    if (not hunter?)
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
                    sign = PandoraCrypto.make_sign(pool.current_key, rphrase)
                    if sign
                      @scmd  = EC_Auth
                      @scode = ECC_Auth_Sign
                      if @stage == ES_Greeting
                        acipher = nil
                        #acipher = open_or_gen_cipher(@skey[PandoraCrypto::KV_Panhash])
                        #if acipher
                        #  @cipher = acipher
                        #  acipher = @cipher[PandoraCrypto::KV_Panhash]
                        #end
                        trust = @skey[PandoraCrypto::KV_Trust]
                        update_node(to_key, to_base_id, trust, acipher)
                        if @cipher
                          acipher = [@cipher[PandoraCrypto::KV_Panhash], \
                            @cipher[PandoraCrypto::KV_Pub], \
                            @cipher[PandoraCrypto::KV_Priv], \
                            @cipher[PandoraCrypto::KV_Kind], \
                            @cipher[PandoraCrypto::KV_Cipher], \
                            @cipher[PandoraCrypto::KV_Creator]]
                        end
                        @sbuf = PandoraUtils.rubyobj_to_pson([sign, $base_id, acipher])
                        @stage = ES_PreExchange
                        set_max_pack_size(ES_Exchange)
                        PandoraUtils.play_mp3('online')
                      else
                        @sbuf = PandoraUtils.rubyobj_to_pson([sign, $base_id, nil])
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
              #ECC_Auth_Answer
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
              elsif (rcode==ECC_Auth_Answer) and (@stage==ES_Captcha)
              #ECC_Auth_Answer
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
                  p log_mes+'Captcha is GONE!  '+@conn_mode.inspect
                  if not hunter?
                    p log_mes+'Captcha add_send_segment params[srckey]='+params['srckey'].inspect
                    add_send_segment(EC_Auth, true, params['srckey'])
                  end
                  @scmd = EC_Data
                  @scode = 0
                  @sbuf = nil
                else
                  send_captcha
                end
              elsif (rcode==ECC_Auth_Sign) and (@stage==ES_Sign)
              #ECC_Auth_Sign
                rsign, sbase_id, acipher = nil
                sig_bid_cip, len = PandoraUtils.pson_to_rubyobj(rdata)
                rsign, sbase_id, acipher = sig_bid_cip if (sig_bid_cip.is_a? Array)
                p log_mes+'recived [rsign, sbase_id, acipher] len='+[rsign, sbase_id, acipher].inspect
                @skey = PandoraCrypto.open_key(@skey, @recv_models, true)
                if @skey and @skey[PandoraCrypto::KV_Obj]
                  if PandoraCrypto.verify_sign(@skey, \
                  OpenSSL::Digest::SHA384.digest(params['sphrase']), rsign)
                    trust = @skey[PandoraCrypto::KV_Trust]
                    skey_hash = @skey[PandoraCrypto::KV_Panhash]
                    init_and_check_node(@skey[PandoraCrypto::KV_Creator], skey_hash, sbase_id)
                    if ((@conn_mode & CM_Double) == 0)
                      if (not hunter?)
                        trust = 0 if (not trust) and $trust_for_captchaed
                      elsif $trust_for_listener and (not (trust.is_a? Float))
                        trust = 0.01
                        @skey[PandoraCrypto::KV_Trust] = trust
                      end
                      p log_mes+'ECC_Auth_Sign trust='+trust.inspect
                      if ($captcha_length>0) and (trust.is_a? Integer) \
                      and (not hunter?) and ((@sess_mode & CM_Captcha)>0)
                        @skey[PandoraCrypto::KV_Trust] = 0
                        send_captcha
                        #if not hunter?
                        #  @stage = ES_Greeting
                        #  p log_mes+'ECC_Auth_Sign Hello2 skey_hash='+skey_hash.inspect
                        #  add_send_segment(EC_Auth, true, skey_hash)
                        #end
                        #@scmd = EC_Data
                        #@scode = 0
                        #@sbuf = nil
                      elsif trust.is_a? Float
                        if trust>=$low_conn_trust
                          set_trust_and_notice(trust)
                          if not hunter?
                            @stage = ES_Greeting
                            set_max_pack_size(ES_Sign)
                            add_send_segment(EC_Auth, true, params['srckey'])
                          else
                            session_key = nil
                            p log_mes+'ECC_Auth_Sign  acipher='+acipher.inspect
                            p log_mes+'ECC_Auth_Sign  @cipher='+@cipher.inspect
                            if (acipher.is_a? Array) and @cipher.nil?
                              cip = Array.new
                              cip[PandoraCrypto::KV_Panhash] = acipher[0]
                              cip[PandoraCrypto::KV_Pub]     = acipher[1]
                              cip[PandoraCrypto::KV_Priv]    = acipher[2]
                              cip[PandoraCrypto::KV_Kind]    = acipher[3]
                              cip[PandoraCrypto::KV_Cipher]  = acipher[4]
                              cip[PandoraCrypto::KV_Creator] = acipher[5]
                              #@cipher = PandoraCrypto.open_key(cipher_phash, @recv_models, false)
                              @cipher = PandoraCrypto.init_key(cip, false)
                              if @cipher[PandoraCrypto::KV_Obj]
                                key_model = PandoraUtils.get_model('Key', @recv_models)
                                key_phash = cip[PandoraCrypto::KV_Panhash]
                                if not PandoraCrypto.key_saved?(key_phash, key_model)
                                  if PandoraCrypto.save_key(cip, pool.person, nil, key_model)
                                    session_key = key_phash
                                  end
                                end
                              end
                            end
                            update_node(to_key, sbase_id, trust, session_key)
                            set_max_pack_size(ES_Exchange)
                            @stage = ES_Exchange
                            PandoraUtils.play_mp3('online')
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
              #ECC_Auth_Simple
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
                  @conn_mode = (@conn_mode | PandoraNet::CM_Keep)
                  set_max_pack_size(ES_Exchange)
                  @stage = ES_Exchange
                else
                  err_scmd('Node password is not setted')
                end
              elsif (rcode==ECC_Auth_Captcha) and ((@stage==ES_Protocol) \
              or (@stage==ES_Greeting))
              #ECC_Auth_Captcha
                p log_mes+'CAPTCHA!!!  ' #+params.inspect
                if not hunter?
                  err_scmd('Captcha for listener is denied')
                else
                  clue_length = rdata[0].ord
                  clue_text = rdata[1,clue_length]
                  captcha_buf = rdata[clue_length+1..-1]

                  if $window.visible? #and $window.has_toplevel_focus?
                    #panhashes = [@skey[PandoraCrypto::KV_Panhash], @skey[PandoraCrypto::KV_Creator]]
                    entered_captcha, dlg = PandoraGtk.show_captcha(captcha_buf, \
                      clue_text, conn_type, @node, @node_id, @recv_models, nil, self)
                    @dialog ||= dlg
                    @dialog.set_session(self, true) if @dialog
                    if entered_captcha
                      @scmd = EC_Auth
                      @scode = ECC_Auth_Answer
                      @sbuf = entered_captcha
                      p log_mes + 'CAPCHA ANSWER setted: '+entered_captcha.inspect
                    elsif entered_captcha.nil?
                      err_scmd('Cannot open captcha dialog')
                    else
                      err_scmd('Captcha enter canceled')
                      @conn_mode = (@conn_mode & (~PandoraNet::CM_Keep))
                    end
                  else
                    err_scmd('User is away')
                  end
                end
              else
                err_scmd('Wrong rcode for stage')
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
          support = :auto
          support = :yes if (skey_trust >= $keep_for_trust)
          if rcode>0
            kind = rcode
            if (@stage==ES_Exchange) or ((kind==PandoraModel::PK_Key) and (@stage==ES_KeyRequest))
              lang = rdata[0].ord
              values = PandoraUtils.namepson_to_hash(rdata[1..-1])
              panhash = nil
              if @stage==ES_KeyRequest
                panhash = params['srckey']
              end
              res = PandoraModel.save_record(kind, lang, values, @recv_models, panhash, support)
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
            PandoraModel.save_records(records, @recv_models, support)
          else
            err_scmd('Records came on wrong stage')
          end
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
                  if res
                    talkview = nil
                    talkview = @dialog.talkview if @dialog
                    talkview.update_lines_with_id(id) if talkview
                  else
                    PandoraUtils.log_message(LM_Warning, _('Cannot update record of confirm')+' kind,id='+[kind,id].inspect)
                  end
                  i += 5
                end
              end
          end
        when EC_Wait
          case rcode
            when EC_Wait2_NoFarHook..EC_Wait5_NoNeighborRec
              PandoraUtils.log_message(LM_Error, _('Error at other side')+': '+ \
                _('cannot find a fish'))
            else
              PandoraUtils.log_message(LM_Error, _('Error at other side')+': '+ \
                _('unknown'))
          end
        when EC_Bye
          errcode = ECC_Bye_Exit
          if rcode == ECC_Bye_NoAnswer
            errcode = ECC_Bye_Silent
          elsif rcode != ECC_Bye_Exit
            mes = rdata
            mes ||= ''
            i = mes.index(' (') if mes
            mes = _(mes[0, i])+mes[i..-1] if i
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
                  @conn_mode = (@conn_mode | PandoraNet::CM_Keep)
                  #panhashes = [@skey[PandoraCrypto::KV_Panhash], @skey[PandoraCrypto::KV_Creator]]
                  panhash = @skey[PandoraCrypto::KV_Creator]
                  @dialog = PandoraGtk.show_cabinet(panhash, self, conn_type)
                  Thread.pass
                  #PandoraUtils.play_mp3('online')
                end
                if rcmd==EC_Message
                  if rdata.is_a? String
                    row, len = PandoraUtils.pson_to_rubyobj(rdata)
                    time_now = Time.now.to_i
                    id0 = nil
                    creator = nil
                    created = nil
                    destination = pool.person
                    text = nil
                    panstate = 0
                    if row.is_a? Array
                      id0 = row[0]
                      creator  = row[1]
                      created  = row[2]
                      text     = row[3]
                      panstate = row[4]
                      panstate ||= 0
                      panstate = (panstate & (PandoraModel::PSF_Crypted | \
                        PandoraModel::PSF_Verified))
                      panstate = (panstate | PandoraModel::PSF_Support)
                    else
                      creator = @skey[PandoraCrypto::KV_Creator]
                      created = time_now
                      text = rdata
                    end
                    values = {:destination=>destination, :text=>text, :state=>2, \
                      :creator=>creator, :created=>created, :modified=>time_now, \
                      :panstate=>panstate}
                    p log_mes+'++++Recv EC_Message: values='+values.inspect
                    model = PandoraUtils.get_model('Message', @recv_models)
                    panhash = model.calc_panhash(values)
                    values['panhash'] = panhash
                    res = model.update(values, nil, nil)
                    if res and (id0.is_a? Integer)
                      while (@confirm_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Full) do
                        sleep(0.02)
                      end
                      @confirm_queue.add_block_to_queue([PandoraModel::PK_Message].pack('C') \
                        +[id0].pack('N'))
                    end

                    talkview = nil
                    talkview = dialog.talkview if dialog
                    if talkview
                      myname = PandoraCrypto.short_name_of_person(pool.current_key)
                      sel = model.select({:panhash=>panhash}, false, 'id', 'id DESC', 1)
                      id = nil
                      id = sel[0][0] if sel and (sel.size > 0)
                      dialog.add_mes_to_view(text, id, panstate, nil, @skey, \
                        myname, time_now, created)
                    else
                      PandoraUtils.log_message(LM_Error, 'Пришло сообщение, но лоток чата не найден!')
                    end

                    # This is a chat "!command"
                    if ((panstate & PandoraModel::PSF_Crypted)==0) and (text.is_a? String) \
                    and (text.size>1) and ((text[0]=='!') or (text[0]=='/'))
                      i = text.index(' ')
                      i ||= text.size
                      chat_com = text[1..i-1].downcase
                      chat_par = text[i+1..-1]
                      p '===>Chat command: '+[chat_com, chat_par].inspect
                      chat_com_par = chat_com
                      chat_com_par += ' '+chat_par if chat_par
                      trust_level = $special_chatcom_trusts[chat_com]
                      trust_level ||= $trust_for_chatcom
                      if skey_trust >= trust_level
                        if chat_par and ($prev_chat_com_par != chat_com_par)
                          $prev_chat_com_par = chat_com_par
                          PandoraUtils.log_message(LM_Info, _('Run chat command')+\
                            ' ['+Utf8String.new(chat_com_par)+']')
                          case chat_com
                            when 'echo'
                              if dialog and (not dialog.destroyed?)
                                dialog.send_mes(chat_par)
                              else
                                add_send_segment(EC_Message, true, chat_par)
                              end
                            when 'menu'
                              $window.do_menu_act(chat_par)
                            when 'exec'
                              res = PandoraUtils.exec_cmd(chat_par)
                              if not res
                                PandoraUtils.log_message(LM_Warning, _('Command fails')+\
                                  ' ['+Utf8String.new(chat_par)+']')
                              end
                            when 'sound'
                              PandoraUtils.play_mp3(chat_par, nil, true)
                            when 'tunnel'
                              params = PandoraUtils.parse_params(chat_par)
                              from = params[:from]
                              from ||= params[:from_here]
                              direct = nil
                              if from
                                direct = true
                              else
                                direct = false
                                from = params[:from_there]
                              end
                              if not direct.nil?
                                add = (not (params.has_key?(:del) or params.has_key?(:delete)))
                                control_tunnel(direct, add, from, params[:to], params[:proto])
                              end
                            else
                              PandoraUtils.log_message(LM_Info, _('Unknown chat command')+': '+chat_com)
                          end
                        end
                      else
                        PandoraUtils.log_message(LM_Info, _('Chat command is denied')+ \
                          ' ['+Utf8String.new(chat_com_par)+'] '+_('trust')+'='+ \
                          PandoraModel.trust_to_str(skey_trust)+' '+_('need')+\
                          '='+trust_level.to_s)
                      end
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
              when EC_Lure
                p log_mes+'EC_Lure'
                send_segment_to_fish(rcode, rdata, true)
                #sleep 2
              when EC_Bite
                p log_mes+'EC_Bite'
                send_segment_to_fish(rcode, rdata)
                #sleep 2
              when EC_Query
                case rcode
                  when ECC_Query_Rel
                    p log_mes+'===ECC_Query_Rel'
                    from_time = rdata[0, 4].unpack('N')[0]
                    pankinds = rdata[4..-1]
                    trust = skey_trust
                    p log_mes+'from_time, pankinds, trust='+[from_time, pankinds, trust].inspect
                    pankinds = PandoraCrypto.allowed_kinds(trust, pankinds)
                    p log_mes+'pankinds='+pankinds.inspect

                    questioner = pool.person
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
                      #p 'kinds='+kinds.inspect
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
                    line_order_raw = rdata
                    line_order, len = PandoraUtils.pson_to_rubyobj(line_order_raw)
                    p '--ECC_Query_Fish line_order='+line_order.inspect

                    if init_line(line_order, pool.key_hash) == false
                      pool.add_fish_order(self, *line_order, @recv_models)
                      p log_mes+'ADD fish order to pool list: line_order='+line_order.inspect
                    end
                  when ECC_Query_Search
                    # пришёл поисковый запрос
                    search_req_raw = rdata
                    search_req, len = PandoraUtils.pson_to_rubyobj(search_req_raw)
                    p '--ECC_Query_Search  search_req='+search_req.inspect
                    if (search_req.is_a? Array) and (search_req.size>=2)
                      abase_id = search_req[SR_BaseId]
                      abase_id ||= @to_base_id
                      if abase_id != pool.base_id
                        p log_mes+'ADD search req to pool list'
                        pool.add_mass_record(MK_Search, search_req[SR_Kind], \
                          search_req[SR_Request], nil, @to_node, src_ind, src_time, \
                          src_trust, cur_depth, @to_node, nil, @recv_models)
                      end
                    end
                  when ECC_Query_Fragment
                    # запрос фрагмента для корзины
                    p log_mes+'==ECC_Query_Fragment'
                    sha1_frag, len = PandoraUtils.pson_to_rubyobj(rdata)
                    sha1, frag_ind = sha1_frag
                    p log_mes+'[sha1, frag_ind]='+[sha1, frag_ind].inspect
                    punnet = pool.init_punnet(sha1)
                    if punnet
                      frag = pool.load_fragment(punnet, frag_ind)
                      if frag
                        buf = PandoraUtils.rubyobj_to_pson([sha1, frag_ind, frag])
                        #@send_queue.add_block_to_queue([EC_Fragment, 0, buf])
                        @scmd = EC_Fragment
                        @scode = 0
                        @sbuf = buf
                      end
                    end
                  #when ECC_Query_FragHash
                  #  # запрос хэша фрагмента
                  #  p log_mes+'ECC_Query_FragHash'
                  #  berhashs, len = PandoraUtils.pson_to_rubyobj(rdata)
                  #  berhashs.each do |rec|
                  #    punnet,berry,sha1 = rec
                  #    p 'punnet,berry,sha1='+[punnet,berry,sha1].inspect
                  #  end
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

                    questioner = pool.person #me
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
                    support = :auto
                    support = :yes if (skey_trust >= $keep_for_trust)
                    PandoraModel.save_records(pson_records, @recv_models, support)
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
                    if (len>0) and line.is_a?(Array) and (line.size>=6)
                      # данные корректны
                      fisher, fisher_key, fisher_baseid, fish, fish_key, fish_baseid = line
                      p log_mes+'--ECC_News_Hook line='+line.inspect
                      if fish and (fish == pool.person) or \
                      fish_key and (fish_key == pool.key_hash) or
                      fish_baseid and (fish_baseid == pool.base_id)
                        p '!!это узел-рыбка, найти/создать сессию рыбака'
                        sessions = pool.sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
                        #pool.init_session(node, tokey, nil, nil, node_id)
                        #Tsaheylu
                        if (sessions.is_a? Array) and (sessions.size>0)
                          p 'Найдены сущ. сессии'
                          sessions.each do |session|
                            p 'Подсоединяюсь к сессии: session.id='+session.object_id.to_s
                            sess_hook, rec = reg_line(line, session)
                            if not pool.connect_sessions_to_hook(session, self, hook, true)
                              p 'Не могу прицепить сессию'
                            end
                          end
                        else
                          #(line, session, far_hook, hook, sess_hook)
                          sess_hook, rec = reg_line(line, nil, hook)
                          session = Session.new(self, sess_hook, nil, nil, nil, \
                            0, nil, nil, nil, nil, fisher, fisher_key, fisher_baseid)
                        end
                      elsif (fisher == pool.person) and \
                      (fisher_key == pool.key_hash) and \
                      (fisher_baseid == pool.base_id)
                        p '!!это узел-рыбак, найти/создать сессию рыбки'
                        sessions = pool.sessions_of_personkeybase(fish, fish_key, fish_baseid)
                        p 'sessions1 size='+sessions.size.to_s
                        if (not (sessions.is_a? Array)) or (sessions.size==0)
                          sessions = pool.sessions_of_personkeybase(fish, fish_key, nil)
                          p 'sessions2 size='+sessions.size.to_s
                        end
                        if not pool.connect_sessions_to_hook(sessions, self, hook, true, line)
                          #(line, session, far_hook, hook, sess_hook)
                          sess_hook, rec = reg_line(line, nil, hook)
                          session = Session.new(self, sess_hook, nil, nil, nil, \
                            CM_Hunter, nil, nil, nil, nil, fish, fish_key, fish_baseid)
                        end
                      else
                        p '!!это узел-посредник, пробросить по истории заявок'
                        mass_records = pool.find_mass_record(MK_Fishing, *line[0..4])
                        mass_records.each do |fo|
                          sess = mr[PandoraNet::MR_Session]
                          if sess
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
                    nick, len = PandoraUtils.pson_to_rubyobj(rdata)
                    p log_mes+'==ECC_News_Notice [rdata, notic, len]='+[rdata, nick, len].inspect
                    if (notic.is_a? Array) and (notic.size==5)
                      #pool.add_notice_order(self, *notic)
                      pool.add_mass_record(MK_Presence, nick, nil, nil, \
                        @to_node, src_ind, src_time, src_trust, \
                        cur_depth, @to_node, nil, @recv_models)
                    end
                  when ECC_News_SessMode
                    p log_mes + 'ECC_News_SessMode'
                    @conn_mode2 = rdata[0].ord if rdata.bytesize>0
                  when ECC_News_Answer
                    p log_mes + '==ECC_News_Answer'
                    req_answer, len = PandoraUtils.pson_to_rubyobj(rdata)
                    req,answ = req_answer
                    p log_mes+'req,answ='+[req,answ].inspect
                    request,kind,base_id = req
                    if kind==PandoraModel::PK_BlobBody
                      PandoraUtils.log_message(LM_Trace, _('Answer: blob is found'))
                      sha1 = request
                      fn_fsize = pool.blob_exists?(sha1, @send_models, true)
                      fn, fsize = fn_fsize if fn_fsize
                      fn ||= answ[0]
                      fsize ||= answ[1]
                      fn = PandoraUtils.absolute_path(fn)
                      punnet = pool.init_punnet(sha1, fsize, fn)
                      if punnet
                        if punnet[PI_FragsFile] and (not pool.frags_complite?(punnet))
                          frag_ind = pool.hold_next_frag(punnet)
                          p log_mes+'--[frag_ind]='+[frag_ind].inspect
                          if frag_ind
                            @scmd = EC_Query
                            @scode = ECC_Query_Fragment
                            @sbuf = PandoraUtils.rubyobj_to_pson([sha1, frag_ind])
                          else
                            pool.close_punnet(punnet, sha1, @send_models)
                          end
                        else
                          p log_mes+'--File is already complete: '+fn.inspect
                          pool.close_punnet(punnet, sha1, @send_models)
                        end
                      end
                    else
                      PandoraUtils.log_message(LM_Trace, _('Answer: rec is found'))
                      reqs = find_search_request(req[0], req[1])
                      reqs.each do |sr|
                        sr[SA_Answer] = answ
                      end
                    end
                  when ECC_News_BigBlob
                    # есть запись, но она слишком большая
                    p log_mes+'==ECC_News_BigBlob'
                    toobig, len = PandoraUtils.pson_to_rubyobj(rdata)
                    toobig.each do |rec|
                      panhash,sha1,size,fill = rec
                      p 'panhash,sha1,size,fill='+[panhash,sha1,size,fill].inspect
                      pun_tit = [panhash,sha1,size]
                      frags = init_punnet(*pun_tit)
                      if frags or frags.nil?
                        @scmd = EC_News
                        @scode = ECC_News_Punnet
                        pun_tit << frags if not frags.nil?
                        @sbuf = PandoraUtils.rubyobj_to_pson(pun_tit)
                      end
                    end
                  when ECC_News_Punnet
                    # есть козина (для сборки фрагментов)
                    p log_mes+'ECC_News_Punnet'
                    punnets, len = PandoraUtils.pson_to_rubyobj(rdata)
                    punnets.each do |rec|
                      panhash,size,sha1,blocksize,punnet = rec
                      p 'panhash,size,sha1,blocksize,fragments='+[panhash,size,sha1,blocksize,fragments].inspect
                    end
                  when ECC_News_Fragments
                    # есть новые фрагменты
                    p log_mes+'ECC_News_Fragments'
                    frags, len = PandoraUtils.pson_to_rubyobj(rdata)
                    frags.each do |rec|
                      panhash,size,sha1,blocksize,punnet = rec
                      p 'panhash,size,sha1,blocksize,fragments='+[panhash,size,sha1,blocksize,fragments].inspect
                    end
                  else
                    p "news more!!!!"
                    pkind = rcode
                    pnoticecount = rdata.unpack('N')
                    @scmd = EC_Sync
                    @scode = 0
                    @sbuf = ''
                end
              when EC_Fragment
                p log_mes+'====EC_Fragment'
                sha1_ind_frag, len = PandoraUtils.pson_to_rubyobj(rdata)
                sha1, frag_ind, frag = sha1_ind_frag
                punnet = pool.init_punnet(sha1)
                if punnet
                  frag = pool.save_fragment(punnet, frag_ind, frag)
                  frag_ind = pool.hold_next_frag(punnet)
                  if frag_ind
                    @scmd = EC_Query
                    @scode = ECC_Query_Fragment
                    @sbuf = PandoraUtils.rubyobj_to_pson([sha1, frag_ind])
                  else
                    pool.close_punnet(punnet, sha1, @send_models)
                  end
                end
              when EC_Mass
                kind = rcode
                params, len = PandoraUtils.pson_to_rubyobj(rdata)
                p log_mes+'====EC_Mass [kind, params, len]='+[kind, params, len].inspect
                if (params.is_a? Array) and (params.size>=6)
                  src_node, src_ind, atime, atrust, adepth, param1, param2, param3 = params
                  keep_node = @to_node
                  pool.add_mass_record(kind, param1, param2, param3, src_node, \
                    src_ind, atime, atrust, adepth, keep_node, nil, @recv_models)
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
      @to_node = pool.add_node_to_list(a_to_key, a_to_base_id, a_to_person)
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

    def is_timeout?(limit)
      res = false
      if limit
        res = ((pool.time_now - @last_recv_time) >= limit) if @last_recv_time
        res = ((pool.time_now - @last_send_time) >= limit) if ((not res) and @last_send_time)
      end
      res
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
    # Number of mass send per cicle
    # RU: Число массовых рассылок за цикл
    $mass_block_count = 2
    # Search request live time (sec)
    # RU: Время жизни поискового запроса
    $search_live_time = 10*60
    # Number of fragment requests per cicle
    # RU: Число запросов фрагментов за цикл
    $frag_block_count = 2
    # Reconnection period in sec
    # RU: Период переподключения в сек
    $conn_period       = 5
    # Exchange timeout in sec
    # RU: Таймаут обмена в секундах
    $exchange_timeout = 5
    # Timeout after message in sec
    # RU: Таймаут после сообщений в секундах
    $dialog_timeout = 90
    # Timeout for captcha in sec
    # RU: Таймаут для капчи в секундах
    $captcha_timeout = 120

    # Starts three session cicle: read from queue, read from socket, send (common)
    # RU: Запускает три цикла сессии: чтение из очереди, чтение из сокета, отправка (общий)
    def initialize(asocket, ahost_name, ahost_ip, aport, aproto, \
    aconn_mode, anode_id, a_dialog, send_state_add, nodehash=nil, to_person=nil, \
    to_key=nil, to_base_id=nil)
      super()
      @conn_state  = CS_Disconnected
      @stage       = ES_Begin
      @socket      = nil
      @conn_mode   = aconn_mode
      @conn_mode   ||= 0
      @conn_mode2  = 0
      @read_state  = 0
      send_state_add  ||= 0
      @send_state     = send_state_add
      @mass_ind     = 0
      @punnet_ind   = 0
      @frag_ind     = 0
      #@fishes         = Array.new
      @hooks          = Array.new
      @read_queue     = PandoraUtils::RoundQueue.new
      @send_queue     = PandoraUtils::RoundQueue.new
      @confirm_queue  = PandoraUtils::RoundQueue.new
      @send_models    = {}
      @recv_models    = {}

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
            fhook, rec = reg_line(nil, sess, nil, nil, sess_hook)
            sess_hook2, rec2 = sess.reg_line(nil, self, nil, sess_hook, fhook)
            if sess_hook2
              #add_hook(asocket, ahost_name)
              if hunter?
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
            port ||= PandoraNet::DefTcpPort
            port = port.to_i

            @conn_state = CS_Connecting
            asocket = nil
            if (host.is_a? String) and (host.size>0) and port
              @conn_mode = (@conn_mode | CM_Hunter)
              server = host+':'+port.to_s

              # Try to connect
              @conn_thread = Thread.new do
                begin
                  @conn_state = CS_Connecting
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
                #pool.add_fish_order(self, pool.person, pool.key_hash, pool.base_id, \
                #  to_person, to_key, @recv_models)
                fish_trust = 0.0
                fish_dep = 2
                pool.add_mass_record(MK_Fishing, to_person, to_key, nil, \
                   nil, nil, nil, fish_trust, fish_dep, nil, nil, @recv_models)
                #while (not @socket) and (not active_hook) \
                #and (@conn_state == CS_Connecting)
                #  p 'Thread.stop [to_person, to_key]='+[to_person, to_key].inspect
                #  Thread.stop
                #end
                @socket = false   #Exit session
              else
                @socket = false
                PandoraUtils.log_message(LM_Trace, \
                  _('Session breaks bz of no person and key panhashes'))
              end
            end

          end

          work_time = Time.now

          p '==reconn: '+[@socket.object_id].inspect
          sleep 0.5


          if @socket
            if not hunter?
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
            @last_conn_mode = 0
            @read_state     = 0
            @send_state     = send_state_add
            @sindex         = 0
            @params         = {}
            @media_send     = false
            @node_panhash   = nil
            @ciphering      = false
            #@base_id        = nil
            if @socket
              set_keepalive(@socket)
            end

            if a_dialog and (not a_dialog.destroyed?)
              @dialog = a_dialog
              @dialog.set_session(self, true)
              if @dialog and (not @dialog.destroyed?) and @dialog.online_btn \
              and ((@socket and (not @socket.closed?)) or active_hook)
                @dialog.online_btn.safe_set_active(true)
                #@dialog.online_btn.inconsistent = false
              end
            end

            #Thread.critical = true
            #PandoraGtk.add_session(self)
            #Thread.critical = false

            @max_pack_size = MPS_Proto
            @log_mes = 'LIS: '
            if hunter?
              @log_mes = 'HUN: '
              @max_pack_size = MPS_Captcha
              add_send_segment(EC_Auth, true, to_key)
            end

            # Read from socket cicle
            # RU: Цикл чтения из сокета
            if @socket
              @socket_thread = Thread.new do
                @activity = 0

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

                p log_mes+"Цикл ЧТЕНИЯ сокета. начало"
                # Цикл обработки команд и блоков данных
                while (@conn_state < CS_StopRead) \
                and (not socket.closed?)
                  recieved = socket_recv(@max_pack_size)
                  if (not recieved) or (recieved == '')
                    @conn_state = CS_Stoping
                  end
                  #p log_mes+"recieved=["+recieved+']  '+socket.closed?.to_s+'  sok='+socket.inspect
                  #p log_mes+"recieved.size, waitlen="+[recieved.bytesize, waitlen].inspect if recieved
                  rkbuf << AsciiString.new(recieved)
                  processedlen = 0
                  while (@conn_state < CS_Stoping) and (not socket.closed?) \
                  and (rkbuf.bytesize>=waitlen)
                    #p log_mes+'readmode, rkbuf.len, waitlen='+[readmode, rkbuf.size, waitlen].inspect
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
                            if rsegsign == LONG_SEG_SIGN
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
                        @last_recv_time = pool.time_now
                        process_media_segment(rkcode, rkdata)
                      else
                        while (@read_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Full) \
                        and (@conn_state == CS_Connected)
                          sleep(0.03)
                          Thread.pass
                        end
                        if (rkcmd & CipherCmdBit)>0
                          rkcmd = (rkcmd & (~CipherCmdBit))
                          rkdata = cipher_buf(rkdata, false)
                          if @ciphering.nil?
                            PandoraUtils.log_message(LM_Error, _('No cipher for decrypt data'))
                            @conn_state = CS_Stoping
                          end
                        end
                        rkdata_size = 0
                        rkdata_size = rkdata.bytesize if rkdata
                        p log_mes+'<<-RECV [rkcmd/rkcode, rkdata.size] stage='+[rkcmd, rkcode, rkdata_size].inspect+' '+@stage.to_s
                        res = @read_queue.add_block_to_queue([rkcmd, rkcode, rkdata])
                        if not res
                          PandoraUtils.log_message(LM_Error, _('Cannot add socket segment to read queue'))
                          @conn_state = CS_Stoping
                        end
                      end
                      rkdata = AsciiString.new
                    end

                    if not ok1comm
                      PandoraUtils.log_message(LM_Error, _('Bad first command'))
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
              while (@conn_state < CS_StopRead)
                read_segment = @read_queue.get_block_from_queue
                if (@conn_state < CS_Disconnected) and read_segment
                  @last_recv_time = pool.time_now
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

            while (@conn_state < CS_Disconnected)
              #p '@conn_state='+@conn_state.inspect

              # формирование подтверждений
              if (@conn_state < CS_Disconnected)
                ssbuf = ''
                confirm_rec = @confirm_queue.get_block_from_queue
                while (@conn_state < CS_Disconnected) and confirm_rec
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
              if (@conn_state < CS_Disconnected)
                send_segment = @send_queue.get_block_from_queue
                while (@conn_state < CS_Disconnected) and send_segment
                  #p log_mes+' send_segment='+send_segment.inspect
                  sscmd, sscode, ssbuf = send_segment
                  if ssbuf and (ssbuf.bytesize>0) and @s_encode
                    #ssbuf = PandoraGtk.recrypt(@skey, ssbuf, true, false)
                    #ssbuf = Base64.strict_encode64(@sbuf)
                  end
                  #p log_mes+'MAIN SEND: '+[@sindex, sscmd, sscode, ssbuf].inspect
                  if (sscmd != EC_Bye) or (sscode != ECC_Bye_Silent)
                    if send_comm_and_data(@sindex, sscmd, sscode, ssbuf)
                      @stage = ES_Exchange if @stage==ES_PreExchange
                      if (not @ciphering) and (@stage>=ES_Exchange) and @cipher
                        @ciphering = true
                      end
                    else
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
                    @conn_state = CS_CloseSession
                  else
                    if (sscmd==EC_Media)
                      @activity = 2
                    end
                    send_segment = @send_queue.get_block_from_queue
                  end
                end
              end

              #отправить состояние
              if ((not @last_conn_mode) or (@last_conn_mode != @conn_mode)) \
              and (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and @to_person
                @last_conn_mode = @conn_mode
                send_conn_mode
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
                    if @to_person
                      receiver = @to_person
                      if (receiver.is_a? String) and (receiver.bytesize>0) \
                      and (hunter? or (mypanhash != receiver))
                        filter = {'destination'=>receiver, 'state'=>1}
                        message_model.update({:state=>0}, nil, filter)
                      end
                    end
                    questioner_step += 1
                  when QS_CreatorCheck
                    # если собеседник неизвестен, запросить анкету
                    if @to_person
                      creator = @to_person
                      kind = PandoraUtils.kind_from_panhash(creator)
                      res = PandoraModel.get_record_by_panhash(kind, creator, nil, \
                        @send_models, 'id')
                      p log_mes+'Whyer: CreatorCheck  creator='+creator.inspect
                      if not res
                        p log_mes+'Whyer: CreatorCheck  Request!'
                        set_request(creator, true)
                      end
                    end
                    questioner_step += 1
                  when QS_NewsQuery
                    # запросить список новых панхэшей
                    if @to_person
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
                    end
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
                    @activity = 2
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
              #p log_mes+'----------MESSS [send_state, stage, conn_state]='+[send_state, stage, conn_state].inspect
              #sleep 1
              processed = 0
              if (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and (((@send_state & CSF_Message)>0) or ((@send_state & CSF_Messaging)>0))
                @activity = 2
                @send_state = (send_state & (~CSF_Message))
                receiver = @skey[PandoraCrypto::KV_Creator]
                if @skey and receiver
                  filter = {'destination'=>receiver, 'state'=>0}
                  fields = 'id, creator, created, text, panstate'
                  sel = message_model.select(filter, false, fields, 'created', $mes_block_count)
                  if sel and (sel.size>0)
                    @send_state = (send_state | CSF_Messaging)
                    i = 0
                    talkview = nil
                    talkview = @dialog.talkview if @dialog
                    ids = nil
                    ids = [] if talkview
                    while sel and (i<sel.size) and (processed<$mes_block_count) \
                    and (@conn_state == CS_Connected) \
                    and (@send_queue.single_read_state != PandoraUtils::RoundQueue::SQS_Full)
                      processed += 1
                      row = sel[i]
                      panstate = row[4]
                      if panstate
                        row[4] = (panstate & (PandoraModel::PSF_Support | \
                          PandoraModel::PSF_Crypted | PandoraModel::PSF_Verified))
                      end
                      creator = row[1]
                      text = row[3]
                      if ((panstate & PandoraModel::PSF_Crypted)>0) and text
                        dest_key = @skey[PandoraCrypto::KV_Panhash]
                        text = PandoraCrypto.recrypt_mes(text, nil, dest_key)
                        row[3] = text
                      end
                      #p log_mes+'---Send EC_Message: row='+row.inspect
                      row_pson = PandoraUtils.rubyobj_to_pson(row)
                      #p log_mes+'%%%Send EC_Message: [row_pson, row_pson.len]='+\
                      #  [row_pson, row_pson.bytesize].inspect
                      row, len = PandoraUtils.pson_to_rubyobj(row_pson)
                      #p log_mes+'****Send EC_Message: [len, row]='+[len, row].inspect
                      if add_send_segment(EC_Message, true, row_pson)
                        id = row[0]
                        res = message_model.update({:state=>1}, nil, {:id=>id})
                        if res
                          ids << id if ids
                        else
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
                    talkview.update_lines_with_id(ids) if ids and (ids.size>0)
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
              and ((send_state & CSF_Message) == 0) and dialog \
              and (not dialog.destroyed?) and dialog.room_id \
              and ((dialog.webcam_btn and (not dialog.webcam_btn.destroyed?) \
              and dialog.webcam_btn.active?) \
              or (dialog.mic_btn and (not dialog.mic_btn.destroyed?) \
              and dialog.mic_btn.active?))
                @activity = 2
                #p 'packbuf '+cannel.to_s
                pointer_ind = PandoraGtk.get_send_ptrind_by_panhash(dialog.room_id)
                processed = 0
                cannel = 0
                while (@conn_state == CS_Connected) \
                and ((send_state & CSF_Message) == 0) and (processed<$media_block_count) \
                and (cannel<$send_media_queues.size) \
                and dialog and (not dialog.destroyed?) \
                and ((dialog.webcam_btn and (not dialog.webcam_btn.destroyed?) and dialog.webcam_btn.active?) \
                or (dialog.mic_btn and (not dialog.mic_btn.destroyed?) and dialog.mic_btn.active?))
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

              # рассылка массовых записей
              if (@sess_mode.is_a? Integer) and ((@sess_mode & CM_GetNotice)>0) \
              and @to_key and @to_person and @to_base_id and @sess_trust \
              and (questioner_step>QS_ResetMessage)
                processed = 0
                while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
                and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
                and (processed<$mass_block_count) \
                and (@mass_ind <= pool.mass_ind)
                  mass_rec = pool.mass_records[@mass_ind]
                  if (mass_rec and (not mass_rec[MR_Node].nil?) \
                  and (@sess_trust >= PandoraModel.transform_trust(mass_rec[MR_Trust], \
                  :auto_to_float)) and (mass_rec[MR_Node] != @to_node))
                  #and (mass_rec[MR_Node] != pool.self_node) \
                    kind = mass_rec[MR_Kind]
                    params = [mass_rec[MR_Node], mass_rec[MR_Index], mass_rec[MR_CrtTime], \
                      mass_rec[MR_Trust], mass_rec[MR_Depth], mass_rec[MR_Param1], \
                      mass_rec[MR_Param2], mass_rec[MR_Param3]]
                    case kind
                      when MK_Fishing
                        #line = fish_order[MR_Fisher..MR_Fish_key]
                        #if init_line(line) == false
                        #  p log_mes+'Fish order to send: '+line.inspect
                        #  PandoraUtils.log_message(LM_Trace, _('Send bob')+': [fish,fishkey]->[host,port]' \
                        #    +[PandoraUtils.bytes_to_hex(fish_order[MR_Fish]), \
                        #    PandoraUtils.bytes_to_hex(fish_order[MR_Fish_key]), \
                        #    @host_ip, @port].inspect)
                        #  line_raw = PandoraUtils.rubyobj_to_pson(line)
                        #  add_send_segment(EC_Query, true, line_raw, ECC_Query_Fish11)
                        #end
                      when MK_Search
                        #p log_mes+'Send search request: '+req.inspect
                        #req_raw = PandoraUtils.rubyobj_to_pson(req)
                        #add_send_segment(EC_Query, true, req_raw, ECC_Query_Search11)
                      when MK_Chat
                    end
                    if params
                      p log_mes+'Mass rec send [kind, params]'+[kind, params].inspect
                      params_pson = PandoraUtils.rubyobj_to_pson(params)
                      add_send_segment(EC_Mass, true, params_pson, kind)
                    end
                    processed += 1
                  end
                  @mass_ind += 1
                end
              end

              # проверка незаполненных корзин
              processed = 0
              while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
              and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
              and (processed>0) and (processed<$frag_block_count) \
              and (pool.need_fragments?) \
              and false # OFFF !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
                next_frag = pool.get_next_frag(@to_base_id, @punnet_ind, @frag_ind)
                p '***!!pool.get_next_frag='+next_frag.inspect
                if next_frag
                  punn, frag = next_frag
                  processed += 1
                else
                  processed = -1
                end
              end

              #p '---@conn_state='+@conn_state.inspect
              #sleep 0.5

              # проверка флагов соединения и состояния сокета
              if (socket and socket.closed?) or (@conn_state == CS_StopRead) \
              and (@confirm_queue.single_read_state == PandoraUtils::RoundQueue::SQS_Empty)
                @conn_state = CS_Disconnected
              elsif @activity == 0
                #p log_mes+'[pool.time_now, @last_recv_time, @last_send_time, cm, cm2]=' \
                #+[pool.time_now, @last_recv_time, @last_send_time, $exchange_timeout, \
                #@conn_mode, @conn_mode2].inspect
                ito = false
                if ((@conn_mode & PandoraNet::CM_Keep) == 0) \
                and ((@conn_mode2 & PandoraNet::CM_Keep) == 0) \
                and (not active_hook)
                  if ((@stage == ES_Protocol) or (@stage == ES_Greeting) \
                  or (@stage == ES_Captcha) and ($captcha_timeout>0))
                    ito = is_timeout?($captcha_timeout)
                    #p log_mes+'capcha timeout  ito='+ito.inspect
                  elsif @dialog and (not @dialog.destroyed?) and ($dialog_timeout>0)
                    ito = is_timeout?($dialog_timeout)
                    #p log_mes+'dialog timeout  ito='+ito.inspect
                  else
                    ito = is_timeout?($exchange_timeout)
                    #p log_mes+'all timeout  ito='+ito.inspect
                  end
                end
                if ito
                  add_send_segment(EC_Bye, true, nil, ECC_Bye_TimeOut)
                  PandoraUtils.log_message(LM_Trace, _('Idle timeout')+': '+@host_ip.inspect)
                else
                  sleep(0.08)
                end
              else
                if @activity == 1
                  sleep(0.01)
                end
                @activity = 0
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
            if socket.is_a? IPSocket
              if not hunter?
                PandoraUtils.log_message(LM_Info, _('Hunter disconnects')+': '+@host_ip.inspect)
              else
                PandoraUtils.log_message(LM_Info, _('Disconnected from listener')+': '+@host_ip.inspect)
              end
            end
            @socket_thread.exit if @socket_thread
            @read_thread.exit if @read_thread
            while (@hooks.size>0)
              p 'DONORs free!!!!'
              hook = @hooks.size-1 #active_hook
              send_segment_to_fish(hook, EC_Bye.chr + ECC_Bye_NoAnswer.chr)
              rec = @hooks[hook]
              if (rec.is_a? Array) and (sess = rec[LHI_Session]) #and sess.active?
                #sess_hook = rec[LHI_Sess_Hook]
                #if sess_hook and (rec2 = sess.hooks[sess_hook]) and rec2[LHI_Line]
                #  sess.send_comm_and_data(sess.sindex, EC_Bye, ECC_Bye_NoAnswer, nil)
                #else
                #far_hook = rec[LHI_Far_Hook]
                #sess.send_comm_and_data(sess.sindex, EC_Bye, ECC_Bye_NoAnswer, nil)
                sess.del_sess_hooks(self)
              end
              @hooks.delete(rec)
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
          @conn_state = CS_Disconnected if @conn_state < CS_Disconnected

          need_connect = (((@conn_mode & CM_Keep) != 0) \
          and (not (@socket.is_a? FalseClass)) and @conn_state < CS_CloseSession) \

          p 'NEED??? [need_connect, @conn_mode, @socket]='+[need_connect, \
            @conn_mode, @socket].inspect

          if need_connect and (not @socket) and work_time \
          and ((Time.now.to_i - work_time.to_i)<15)
            p 'sleep!'
            sleep(3.1+0.5*rand)
          end

          @socket = nil

          attempt += 1
        end
        pool.del_session(self)
        if dialog and (not dialog.destroyed?) #and (not dialog.online_btn.destroyed?)
          dialog.set_session(self, false)
          #dialog.online_btn.active = false
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
    if server
      begin
        client = server.accept_nonblock
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK
        client = nil
      end
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

  $max_session_count   = 300
  $hunt_step_pause     = 0.1
  $hunt_overflow_pause = 1.0
  $hunt_period         = 60*3

  # Get exchange params
  # RU: Взять параметры обмена
  def self.get_exchange_params
    $incoming_addr       = PandoraUtils.get_param('incoming_addr')
    $puzzle_bit_length   = PandoraUtils.get_param('puzzle_bit_length')
    $puzzle_sec_delay    = PandoraUtils.get_param('puzzle_sec_delay')
    $captcha_length      = PandoraUtils.get_param('captcha_length')
    $captcha_attempts    = PandoraUtils.get_param('captcha_attempts')
    $trust_captchaed     = PandoraUtils.get_param('trust_captchaed')
    $trust_listener      = PandoraUtils.get_param('trust_listener')
    $low_conn_trust      = PandoraUtils.get_param('low_conn_trust')
    $max_opened_keys     = PandoraUtils.get_param('max_opened_keys')
    $max_session_count   = PandoraUtils.get_param('max_session_count')
    $hunt_step_pause     = PandoraUtils.get_param('hunt_step_pause')
    $hunt_overflow_pause = PandoraUtils.get_param('hunt_overflow_pause')
    $hunt_period         = PandoraUtils.get_param('hunt_period')
    $exchange_timeout    = PandoraUtils.get_param('exchange_timeout')
    $dialog_timeout      = PandoraUtils.get_param('dialog_timeout')
    $captcha_timeout     = PandoraUtils.get_param('captcha_timeout')
    $low_conn_trust     ||= 0.0
    get_notice_params
  end

  $tcp_listen_thread = nil
  $udp_listen_thread = nil

  $udp_port = nil
  UdpHello = 'pandora:hello:'

  def self.listen?
    res = (not($tcp_listen_thread.nil?) or not($udp_listen_thread.nil?))
  end

  def self.parse_host_name(host, ip6=false)
    if host
      if host.size==0
        host = nil
      else
        any = ((host=='any') or (host=='all'))
        if ((host=='any4') or (host=='all4') or (host=='ip4') or (host=='IP4') \
        or (any and (not ip6)))
          host = Socket::INADDR_ANY   #"", "0.0.0.0", "0", "0::0", "::"
        elsif ((host=='any6') or (host=='all6') or (host=='ip6') or (host=='IP6') \
        or (any and ip6))
          host = '::'
        end
      end
    end
    host
  end

  def self.create_session_for_socket(socket)
    if socket
      host_ip = socket.peeraddr[2]
      if $window.pool.is_black?(host_ip)
        PandoraUtils.log_message(LM_Info, _('IP is banned')+': '+host_ip.to_s)
      else
        host_name = socket.peeraddr[3]
        port = socket.peeraddr[1]
        proto = 'tcp'
        p 'LISTENER: '+[host_name, host_ip, port, proto].inspect
        session = Session.new(socket, host_name, host_ip, port, proto, \
          0, nil, nil, nil, nil)
      end
    end
  end

  WaitSecPanRegOnExit = 1.5
  $node_registering_thread = nil

  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.start_or_stop_listen(must_listen=nil, quit_programm=nil)
    PandoraNet.get_exchange_params
    must_listen = (not listen?) if must_listen.nil?
    if must_listen
      # Need to start
      #$window.show_notice(false)
      user = PandoraCrypto.current_user_or_key(true)
      if user
        $window.set_status_field(PandoraGtk::SF_Listen, nil, nil, true)
        hosts = $host
        hosts ||= PandoraUtils.get_param('listen_host')
        hosts = hosts.split(',') if hosts
        hosts.compact!
        # TCP Listener
        tcp_port = $tcp_port
        tcp_port ||= PandoraUtils.get_param('tcp_port')
        tcp_port ||= PandoraNet::DefTcpPort
        if (hosts.is_a? Array) and (hosts.size>0) and (tcp_port>0) and $tcp_listen_thread.nil?
          $tcp_listen_thread = Thread.new do
            servers = Array.new
            addr_strs = Array.new
            ip4, ip6 = PandoraNet.register_node_ips(true)
            hosts.each do |host|
              host = parse_host_name(host, (not ip6.nil?))
              if host
                begin
                  server = TCPServer.open(host, tcp_port)
                  if server
                    servers << server
                    addr_str = 'TCP ['+server.addr[3].to_s+']:'+server.addr[1].to_s
                    addr_strs << addr_str
                    PandoraUtils.log_message(LM_Info, _('Listening')+' '+addr_str)
                  end
                rescue => err
                  str = 'TCP ['+host.to_s+']:'+tcp_port.to_s
                  PandoraUtils.log_message(LM_Warning, _('Cannot open')+' '+str+' ' \
                    +Utf8String.new(err.message))
                end
              end
            end
            if servers.size>0
              Thread.current[:listen_tcp] = true
              while Thread.current[:listen_tcp]
                has_active = true
                socket = nil
                while Thread.current[:listen_tcp] and has_active and (not socket)
                  sleep(0.05)
                  has_active = false
                  servers.each_with_index do |server,i|
                    if server
                      if (server and server.closed?)
                        servers[i] = nil
                      else
                        has_active= true
                        socket = get_listener_client_or_nil(server)
                        break if socket
                      end
                    end
                  end
                end
                create_session_for_socket(socket)
              end
              servers.each_with_index do |server,i|
                server.close if (server and (not server.closed?))
                PandoraUtils.log_message(LM_Info, _('Listener stops')+' '+addr_strs[i])
              end
            end
            $window.set_status_field(PandoraGtk::SF_Listen, nil, nil, false)
            $tcp_listen_thread = nil
            $window.correct_lis_btn_state
            PandoraNet.register_node_ips(false)
          end
        end

        # UDP Listener
        udp_port = $udp_port
        udp_port ||= PandoraUtils.get_param('udp_port')
        udp_port ||= PandoraNet::DefUdpPort
        if (udp_port>0) and $udp_listen_thread.nil? and (hosts.size>0)
          host = parse_host_name(hosts[0])
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
              udp_addr_str = 'UDP ['+udp_server.addr[3].to_s+']:'+udp_server.addr[1].to_s
              PandoraUtils.log_message(LM_Info, _('Listening')+' '+udp_addr_str)
            rescue => err
              udp_server = nil
              if host != '::'
                str = 'UDP ['+host.to_s+']:'+tcp_port.to_s+' '+Utf8String.new(err.message)
                PandoraUtils.log_message(LM_Warning, _('Cannot open')+' '+str)
              end
            end
            Thread.current[:udp_server] = udp_server
            Thread.current[:listen_udp] = (udp_server != nil)

            udp_broadcast = PandoraUtils.get_param('udp_broadcast')
            if udp_broadcast and udp_server
              # Send UDP broadcast hello
              GLib::Timeout.add(2000) do
                res = PandoraCrypto.current_user_and_key(false, false)
                if res.is_a? Array
                  person_hash, key_hash = res
                  hparams = {:version=>0, :iam=>person_hash, :mykey=>key_hash, :base=>$base_id}
                  hparams[:addr] = $incoming_addr if $incoming_addr and ($incoming_addr != '')
                  hello = UdpHello + PandoraUtils.hash_to_namepson(hparams)
                  if $udp_listen_thread
                    udp_server = $udp_listen_thread[:udp_server]
                    if udp_server and (not udp_server.closed?)
                      rcv_udp_port = PandoraNet::DefUdpPort
                      begin
                        udp_server.send(hello, 0, '<broadcast>', rcv_udp_port)
                        PandoraUtils.log_message(LM_Trace, \
                          'UDP '+_('broadcast to ports')+' '+rcv_udp_port.to_s)
                      rescue => err
                        PandoraUtils.log_message(LM_Trace, \
                          _('Cannot send')+' UDP '+_('broadcast to ports')+' '\
                          +rcv_udp_port.to_s+' ('+Utf8String.new(err.message)+')')
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
              udp_hello_len = UdpHello.bytesize
              p 'Received UDP-pack ['+data.inspect+'] addr='+addr.inspect
              if (data.is_a? String) and (data.bytesize > udp_hello_len) \
              and (data[0, udp_hello_len] == UdpHello)
                data = data[udp_hello_len..-1]
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

        #p loc_hst = Socket.gethostname
        #p Socket.gethostbyname(loc_hst)[3]
      end
      $window.correct_lis_btn_state
    else
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
    end
    if quit_programm
      PandoraNet.register_node_ips(false, quit_programm)
      sleep(0.1)
      i = (WaitSecPanRegOnExit*10).round
      while $node_registering_thread and (i>0)
        i -= 1
        sleep(0.1)
      end
      if $node_registering_thread
        $node_registering_thread.exit if $node_registering_thread.alive?
        $node_registering_thread = nil
      end
    end
  end

  $last_reg_listen_state = nil
  $last_ip4_show = nil
  $last_ip6_show = nil

  WrongUrl = 'http://robux.biz/panreg.php?node=[node]&amp;ips=[ips]'

  def self.register_node_ips(listening=nil, quit_programm=nil)

    def self.check_last_ip(ip_list, version)
      ip = nil
      ip_need = nil
      ddns_url = nil
      if ip_list.size>0
        ip = ip_list[0].ip_address
        last_ip = PandoraUtils.get_param('last_ip'+version)
        ip_need = ip
        ip_need = nil if last_ip and (last_ip==ip)
      end
      [ip, ip_need]
    end

    def self.get_update_url(param, ip_active)
      url = nil
      if ip_active
        url = PandoraUtils.get_param(param)
        url = nil if url and (url.size==0)
      end
      url
    end

    def self.set_last_ip(ip, version)
      PandoraUtils.set_param('last_ip'+version, ip) if ip
    end

    if $node_registering_thread.nil?
      $node_registering_thread = Thread.current
      ip_list = Socket.ip_address_list
      ip4_list = ip_list.select do |addr_info|
        (addr_info.ipv4? and (not addr_info.ipv4_loopback?) \
        and (not addr_info.ipv4_private?) and (not addr_info.ipv4_multicast?))
      end
      ip6_list = ip_list.select do |addr_info|
        (addr_info.ipv6? and (not addr_info.ipv6_loopback?) \
        and (not addr_info.ipv6_linklocal?) and (not addr_info.ipv6_multicast?))
      end
      ip4, ip4n = check_last_ip(ip4_list, '4')
      ip6, ip6n = check_last_ip(ip6_list, '6')
      if ($last_ip4_show.nil? and ip4) or ip4n
        $last_ip4_show = ip4
        ip4_list.each do |addr_info|
          PandoraUtils.log_message(LM_Warning, _('Global IP')+'v4: '+addr_info.ip_address)
        end
      end
      if ($last_ip6_show.nil? and ip6) or ip6n
        $last_ip6_show = ip6
        ip6_list.each do |addr_info|
          PandoraUtils.log_message(LM_Warning, _('Global IP')+'v6: '+addr_info.ip_address)
        end
      end
      panreg_url = get_update_url('panreg_url', true)
      if ip4 or ip6 or panreg_url
        ddns4_url = get_update_url('ddns4_url', ip4n)
        ddns6_url = get_update_url('ddns6_url', ip6n)
        listening = PandoraNet.listen? if listening.nil?
        need_panreg = true
        if $last_reg_listen_state.nil?
          quit_programm = false   #start programm
        else
          need_panreg = (($last_reg_listen_state != listening) \
            or quit_programm or listening)
        end
        if panreg_url and need_panreg
          panreg_period = PandoraUtils.get_param('panreg_period')
          if not panreg_period
            panreg_period = 30
          elsif (panreg_period<0)
            panreg_period = -panreg_period
            quit_programm = nil #if (quit_programm.is_a? TrueClass)
            need_panreg = listening
          end
          if quit_programm.nil? and need_panreg
            last_panreg = PandoraUtils.get_param('last_panreg')
            last_panreg ||= 0
            time_now = Time.now.to_i
            need_panreg = ((time_now - last_panreg.to_i) >= panreg_period*60)
          end
          if panreg_url and need_panreg
            $last_reg_listen_state = listening
            ips = ''
            del = ''
            if listening
              ips = ''
              ip4_list.each do |addr_info|
                ips << ',' if ips.size>0
                ips << addr_info.ip_address
              end
              ip6_list.each do |addr_info|
                ips << ',' if ips.size>0
                ips << addr_info.ip_address
              end
              ips = 'none' if (ips.size==0)
              ips = '&ips=' + ips
            else
              del = '&del=1'
            end
            node = PandoraUtils.bytes_to_hex($window.pool.self_node)
            #node = Base64.strict_encode64($window.pool.self_node)
            if panreg_url==WrongUrl  #Hack to change old parameter
              PandoraUtils.set_param('panreg_url', nil)
              panreg_url = PandoraUtils.get_param('panreg_url')
            end
            suff = nil
            if ip4 and (not ip6)
              suff = '4'
            elsif ip6 and (not ip4)
              suff = '6'
            end
            if PandoraNet.http_ddns_request(panreg_url, {:node=>'node='+node, \
            :ips=>ips, :del=>del, :ip4=>ip4, :ip6=>ip6}, suff, 'Registrated', \
            del.size>0)
              PandoraUtils.set_param('last_panreg', Time.now)
            end
          end
        end
        if (ddns4_url or ddns6_url) and listening and (not quit_programm)
          if ddns4_url and PandoraNet.http_ddns_request(ddns4_url, {:ip=>ip4}, '4')
            set_last_ip(ip4, '4')
          end
          if ddns6_url and PandoraNet.http_ddns_request(ddns6_url, {:ip=>ip6}, '6')
            set_last_ip(ip6, '6')
          end
        end
      end
      $node_registering_thread = nil
      [ip4, ip6]
    end
  end

  $hunter_thread         = nil

  # Is hunting?
  # RU: Идёт охота?
  def self.is_hunting?
    res = ((not $hunter_thread.nil?) and $hunter_thread.alive? \
      and $hunter_thread[:active] and (not $hunter_thread[:paused]))
  end

  $resume_harvest_time   = nil
  $resume_harvest_period = 60      # minute

  # Start or stop hunt
  # RU: Начать или остановить охоту
  def self.start_or_stop_hunt(continue=true, delay=0)
    if $hunter_thread
      if $hunter_thread.alive?
        if $hunter_thread[:active]
          if continue
            $hunter_thread[:paused] = (not $hunter_thread[:paused])
            if (not $hunter_thread[:paused]) and $hunter_thread.stop?
              $hunter_thread.run
            end
            p '$hunter_thread[:paused]='+$hunter_thread[:paused].inspect
          else
            # need to exit thread
            $hunter_thread[:active] = false
            if $hunter_thread.stop?
              $hunter_thread.run
              sleep(0.1)
            else
              sleep(0.05)
            end
            sleep(0.2) if $hunter_thread and $hunter_thread.alive?
          end
        else
          # need to restart thread
          $hunter_thread[:active] = nil
        end
      end
      if $hunter_thread and ((not $hunter_thread.alive?) \
      or (($hunter_thread[:active]==false) and (not continue)))
        $hunter_thread.exit if $hunter_thread.alive?
        $hunter_thread = nil
      end
      $window.correct_hunt_btn_state
    else
      user = PandoraCrypto.current_user_or_key(true)
      if user
        node_model = PandoraModel::Node.new
        filter = 'addr<>"" OR domain<>""'
        flds = 'id, addr, domain, key_hash, tport, panhash, base_id'
        sel = node_model.select(filter, false, flds)
        if sel and (sel.size>0)
          $hunter_thread = Thread.new do
            sleep(0.1) if delay>0
            Thread.current[:active] = true
            Thread.current[:paused] = false
            $window.correct_hunt_btn_state
            sleep(delay) if delay>0
            while (Thread.current[:active] != false) and sel and (sel.size>0)
              start_time = Time.now.to_i
              sel.each do |row|
                node_id = row[0]
                addr   = row[1]
                domain = row[2]
                key_hash = row[3]
                if (addr and (addr.size>0)) or (domain and (domain.size>0)) \
                or ($window.pool.active_socket? and key_hash and (key_hash.size>0))
                  tport = 0
                  begin
                    tport = row[4].to_i
                  rescue
                  end
                  person = nil
                  panhash = row[4]
                  base_id = row[5]
                  tport = PandoraNet::DefTcpPort if (not tport) or (tport==0) or (tport=='')
                  domain = addr if ((not domain) or (domain == ''))
                  addr = $window.pool.encode_addr(domain, tport, 'tcp')
                  if Thread.current[:active]
                    $window.pool.init_session(addr, panhash, 0, nil, node_id, person, \
                      key_hash, base_id)
                    if Thread.current[:active]
                      if $window.pool.sessions.size<$max_session_count
                        sleep($hunt_step_pause)
                      else
                        while Thread.current[:active] \
                        and ($window.pool.sessions.size>=$max_session_count)
                          sleep($hunt_overflow_pause)
                          Thread.stop if Thread.current[:paused]
                        end
                      end
                    end
                  end
                end
                break if not Thread.current[:active]
                Thread.stop if Thread.current[:paused]
              end
              restart = (Thread.current[:active]==nil)
              if restart or Thread.current[:active]
                Thread.current[:active] = true if restart
                sel = node_model.select(filter, false, flds)
                if not restart
                  spend_time = Time.now.to_i - start_time
                  need_pause = $hunt_period - spend_time
                  sleep(need_pause) if need_pause>0
                end
                Thread.stop if (Thread.current[:paused] and Thread.current[:active])
              end
            end
            $hunter_thread = nil
            $window.correct_hunt_btn_state
          end
        else
          $window.correct_hunt_btn_state
          dialog = PandoraGtk::GoodMessageDialog.new(_('Enter at least one node'))
          dialog.run_and_do do
            PandoraGtk.show_panobject_list(PandoraModel::Node, nil, nil, true)
          end
        end
      else
        $window.correct_hunt_btn_state
      end
    end
    if (not $resume_harvest_time) \
    or (Time.now.to_i >= $resume_harvest_time + $resume_harvest_period*60)
      GLib::Timeout.add(900) do
        if is_hunting?
          $resume_harvest_time = Time.now.to_i
          $window.pool.resume_harvest
        end
        false
      end
    end
  end

  # Start hunt
  # RU: Начать охоту
  def self.start_hunt(continue=true)
    if (not $hunter_thread) or (not $hunter_thread.alive?) \
    or (not $hunter_thread[:active]) or $hunter_thread[:paused]
      start_or_stop_hunt
    elsif continue and $hunter_thread and $hunter_thread.alive? and $hunter_thread.stop?
      $hunter_thread.run
    end
  end

  def self.detect_proxy
    proxy = PandoraUtils.get_param('proxy_server')
    if proxy.is_a? String
      proxy = proxy.split(':')
      proxy ||= []
      proxy = [proxy[0..-4].join(':'), *proxy[-3..-1]] if (proxy.size>4)
      proxy[1] = proxy[1].to_i if (proxy.size>1)
      proxy[2] = nil if (proxy.size>2) and (proxy[2]=='')
      proxy[3] = nil if (proxy.size>3) and (proxy[3]=='')
      PandoraUtils.log_message(LM_Trace, _('Proxy is used')+' '+proxy.inspect)
    else
      proxy = []
    end
    proxy
  end

  def self.parse_url(url)
    host = nil
    path = nil
    port = nil
    scheme = nil
    begin
      uri = url
      uri = URI.parse(uri) if uri.is_a? String
      host = uri.host
      path = uri.path
      port = uri.port
      scheme = uri.scheme
      simpe = false
    rescue => err
      PandoraUtils.log_message(LM_Warning, _('URI parse fails')+' ['+url+'] '+\
        Utf8String.new(err.message))
    end
    [host, path, port, scheme]
  end


  HTTP_TIMEOUT  = 5*60    #5 minutes

  def self.http_connect(url)
    http = nil
    host, path, port, scheme = parse_url(url)
    port_str = ''
    port_str = ':'+port.to_s if port
    PandoraUtils.log_message(LM_Info, _('Connect to')+': '+host+path+port_str+'..')
    begin
      proxy = PandoraNet.detect_proxy
      http = Net::HTTP.new(host, port, *proxy)
      if scheme == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.open_timeout = HTTP_TIMEOUT
    rescue => err
      http = nil
      PandoraUtils.log_message(LM_Trace, _('Connection error')+\
        [host, port].inspect+' '+Utf8String.new(err.message))
      puts Utf8String.new(err.message)
    end
    [http, host, path]
  end

  def self.http_reconnect_if_need(http, time, url)
    if (not http.active?) or (Time.now.to_i >= (time + HTTP_TIMEOUT))
      host, path, port, scheme = parse_url(url)
      begin
        proxy = PandoraNet.detect_proxy
        http = Net::HTTP.new(host, port, *proxy)
        if scheme == 'https'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        http.open_timeout = HTTP_TIMEOUT
      rescue => err
        http = nil
        PandoraUtils.log_message(LM_Trace, _('Connection error')+\
          [host, port].inspect+' '+Utf8String.new(err.message))
        puts Utf8String.new(err.message)
      end
    end
    http
  end

  # Http get file size from header
  # RU: Взять размер файла из заголовка
  def self.http_size_from_header(http, path, loglev=true)
    res = nil
    begin
      response = http.request_head(path)
      res = response.content_length
    rescue => err
      res = nil
      host ||= nil
      loglev = LM_Trace if loglev.is_a?(TrueClass)
      PandoraUtils.log_message(loglev, _('Size is not getted')+' '+\
        [http, path].inspect+' '+Utf8String.new(err.message)) if loglev
      puts Utf8String.new(err.message)
    end
    res
  end

  # Http get body
  # RU: Взять тело по Http
  def self.http_get_body_from_path(http, path, host='')
    body = nil
    if http and path
      PandoraUtils.log_message(LM_Trace, _('Download from') + ': ' + \
        host + path + '..')
      begin
        response = http.request_get(path)
        body = response.body if response.is_a?(Net::HTTPSuccess)
      rescue => err
        PandoraUtils.log_message(LM_Info, _('Http download fails')+': '+Utf8String.new(err.message))
      end
    end
    body
  end

  def self.http_get_request(url, show_log=nil)
    body = nil
    if url.is_a?(String) and (url.size>0)
      if show_log
        PandoraUtils.log_message(LM_Trace, _('Download from') + ': ' + url + '..')
      end
      begin
        uri = URI.parse(url)
        body = Net::HTTP.get(uri)
      rescue => err
        PandoraUtils.log_message(LM_Info, _('Http download fails')+': '+Utf8String.new(err.message))
      end
    end
    body
  end

  # Pandora Registrator (PanReg) indexes
  # RU: Индексы Регистратора Пандоры (PanReg)
  PR_Node = 0
  PR_Ip   = 1
  PR_Nick = 2
  PR_Time = 3

  # Load PanReg dump to node table
  # RU: Загружает дамп PanReg в таблицу узлов
  def self.load_panreg(body, format=nil)
    #puts '!!!IPS: '+body.inspect
    if (body.is_a? String) and (body.size>0)
      list = body.split('<br>')
      if (list.is_a? Array) and (list.size>0)
        format ||= 'base64'
        node_model = PandoraUtils.get_model('Node')
        node_kind = node_model.kind
        if node_model
          self_node = $window.pool.self_node
          list.each_with_index do |line, row|
            if line.include?('|')
              nfs = line.split('|')
              node = nfs[PR_Node]
              if node and (node.bytesize>22) and (node.bytesize<=40) and (nfs.size>=2)
                begin
                  if format=='hex'
                    node = PandoraUtils.hex_to_bytes(node)
                  else
                    node = Base64.strict_decode64(node)
                  end
                rescue
                  node = nil
                end
              else
                node = nil
              end
              if node and (node.bytesize==20) and (node != self_node)
                ip = nfs[PR_Ip]
                if node and (node.size==20) and ip and (ip.size >= 7)
                  #p '---Check [NODE, IP]='+[node, ip].inspect
                  panhash = node_kind.chr+0.chr+node
                  filter = ["(addr=? OR domain=?) AND panhash=?", ip, ip, panhash]
                  sel = node_model.select(filter, false, 'id', nil, 1)
                  if sel.nil? or (sel.size==0)
                    p '+++Add [panhash, IP]='+[panhash, ip].inspect
                    panstate = 0
                    time_now = Time.now.to_i
                    creator = PandoraCrypto.current_user_or_key(true, false)
                    values = {:addr=>ip, :panhash=>panhash, :creator=>creator, \
                      :created=>time_now, :modified=>time_now, :panstate=>panstate}
                    sel = node_model.update(values, nil, nil)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def self.http_ddns_request(url, params, suffix=nil, mes=nil, delete=nil)
    res = nil
    if url.is_a?(String) and (url.size>0)
      params.each do |k,v|
        if k and (not v.nil?)
          k = k.to_s
          url.gsub!('['+k+']', v)
          url.gsub!('['+k.upcase+']', v)
        end
      end
      if suffix
        suffix = '(ip'+suffix+')'
      else
        suffix = ''
      end
      suffix << ': '+url
      err = nil
      body = http_get_request(url)
      if mes and body
        if body.size==0
          err = ' '+_('Loading error')
        elsif body[0]=='!'
          if delete or (body.size==1)
            puts body
          else
            err = ' '+_(body[1..-1].strip)
          end
        else
          load_panreg(body)
        end
      end
      if body and err.nil?
        res = true
        mes ||= 'DDNS updated'
        PandoraUtils.log_message(LM_Info, _(mes)+suffix)
      else
        err ||= ''
        PandoraUtils.log_message(LM_Info, _('Registrator fails')+suffix+err)
      end
    end
    res
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

  # Middle width of num char in pixels
  # RU: Средняя ширина цифрового символа в пикселах
  def self.num_char_width
    @@num_char_width ||= nil
    if not @@num_char_width
      lab = Gtk::Label.new('0')
      lw,lh = lab.size_request
      @@num_char_width = lw
      @@num_char_width ||= 5
    end
    @@num_char_width
  end

  # Force set text of any Button (with stock)
  # RU: Силовая смена текста любой кнопки (со stock)
  def self.set_button_text(btn, text=nil)
    alig = btn.children[0]
    if alig.is_a? Gtk::Bin
      hbox = alig.child
      if (hbox.is_a? Gtk::Box) and (hbox.children.size>1)
        lab = hbox.children[1]
        if lab.is_a? Gtk::Label
          if text.nil?
            lab.destroy
          else
            lab.text = text
          end
        end
      end
    end
  end

  # Ctrl, Shift, Alt are pressed? (Array or Yes/No)
  # RU: Кнопки Ctrl, Shift, Alt нажаты? (Массив или Да/Нет)
  def self.is_ctrl_shift_alt?(ctrl=nil, shift=nil, alt=nil)
    screen, x, y, mask = Gdk::Display.default.pointer
    res = nil
    ctrl_prsd = ((mask & Gdk::Window::CONTROL_MASK.to_i) != 0)
    shift_prsd = ((mask & Gdk::Window::SHIFT_MASK.to_i) != 0)
    alt_prsd = ((mask & Gdk::Window::MOD1_MASK.to_i) != 0)
    if ctrl.nil? and shift.nil? and alt.nil?
      res = [ctrl_prsd, shift_prsd, alt_prsd]
    else
      res = ((ctrl and ctrl_prsd) or (shift and shift_prsd) or (alt and alt_prsd))
    end
    res
  end

  # Statusbar fields
  # RU: Поля в статусбаре
  SF_Log     = 0
  SF_FullScr = 1
  SF_Update  = 2
  SF_Lang    = 3
  SF_Auth    = 4
  SF_Listen  = 5
  SF_Hunt    = 6
  SF_Conn    = 7
  SF_Radar   = 8
  SF_Fisher  = 9
  SF_Search  = 10
  SF_Harvest = 11

  # Good and simle MessageDialog
  # RU: Хороший и простой MessageDialog
  class GoodMessageDialog < Gtk::MessageDialog

    def initialize(a_mes, a_title=nil, a_stock=nil, an_icon=nil)
      a_stock ||= Gtk::MessageDialog::INFO
      super($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
        a_stock, Gtk::MessageDialog::BUTTONS_OK_CANCEL, a_mes)
      a_title ||= 'Note'
      self.title = _(a_title)
      self.default_response = Gtk::Dialog::RESPONSE_OK
      an_icon ||= $window.icon if $window
      an_icon ||= main_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      self.icon = an_icon
      self.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask? #w, W, ц, Ц
        then
          widget.response(Gtk::Dialog::RESPONSE_CANCEL)
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й, x, X, ч, Ч
        then
          $window.do_menu_act('Quit')
          false
        else
          false
        end
      end
    end

    def run_and_do(do_if_ok=true)
      res = nil
      res = (self.run == Gtk::Dialog::RESPONSE_OK)
      if (res and do_if_ok) or ((not res) and (not do_if_ok))
        res = true
        yield if block_given?
      end
      self.destroy if not self.destroyed?
      res
    end

  end

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

      @notebook = Gtk::Notebook.new
      @notebook.scrollable = true
      label_box1 = TabLabelBox.new(Gtk::Stock::PROPERTIES, _('Basic'))
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
      okbutton.signal_connect('clicked') do |*args|
        @response=2
      end
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') do |*args|
        @response=1
      end
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
          $window.do_menu_act('Quit')
          @response=1
          false
        else
          false
        end
      end

    end

    # Show dialog in modal mode
    # RU: Показать диалог в модальном режиме
    def run2(in_thread=false)
      res = nil
      show_all
      if @def_widget
        #focus = @def_widget
        @def_widget.grab_focus
        self.present
        GLib::Timeout.add(200) do
          @def_widget.grab_focus if @def_widget and (not @def_widget.destroyed?)
          false
        end
      end

      while (not destroyed?) and (@response == 0) do
        if in_thread
          Thread.pass
        else
          Gtk.main_iteration
        end
        #sleep(0.001)
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

  # ToggleButton with safety "active" switching
  # RU: ToggleButton с безопасным переключением "active"
  class SafeToggleButton < Gtk::ToggleButton

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
      self.width_request = PandoraGtk.num_char_width*8+8
    end
  end

  # Entry for float
  # RU: Поле ввода дробных чисел
  class FloatEntry < IntegerEntry
    def init_mask
      super
      @mask += '.e'
      self.max_length = 35
      self.width_request = PandoraGtk.num_char_width*11+8
    end
  end

  # Entry for HEX
  # RU: Поле ввода шестнадцатеричных чисел
  class HexEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789abcdefABCDEF'
      self.width_request = PandoraGtk.num_char_width*45+8
    end
  end

  Base64chars = [('0'..'9').to_a, ('a'..'z').to_a, ('A'..'Z').to_a, '+/=-_*[]'].join

  # Entry for Base64
  # RU: Поле ввода Base64
  class Base64Entry < MaskEntry
    def init_mask
      super
      @mask = Base64chars
      self.width_request = PandoraGtk.num_char_width*64+8
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
      self.width_request = PandoraGtk.num_char_width*self.max_length+8
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class TimeEntrySimple < DateEntrySimple
    def init_mask
      super
      @mask = '0123456789:'
      self.max_length = 8
      self.tooltip_text = 'hh:mm:ss'
      self.width_request = PandoraGtk.num_char_width*self.max_length+8
    end
  end

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class DateTimeEntry < DateEntrySimple
    def init_mask
      super
      @mask += ': '
      self.max_length = 19
      self.tooltip_text = 'DD.MM.YYYY hh:mm:ss'
      self.width_request = PandoraGtk.num_char_width*(self.max_length+1)+8
    end
  end

  # Entry with popup widget
  # RU: Поле с всплывающим виджетом
  class BtnEntry < Gtk::HBox
    attr_accessor :entry, :button, :close_on_enter, :modal

    def initialize(entry_class, stock=nil, tooltip=nil, amodal=nil, *args)
      amodal = false if amodal.nil?
      @modal = amodal
      super(*args)
      @close_on_enter = true
      @entry = entry_class.new
      stock ||= :list

      @init_yield_block = nil
      if block_given?
        @init_yield_block = Proc.new do |*args|
          yield(*args)
        end
      end

      if PandoraUtils.os_family=='windows'
        @button = GoodButton.new(stock, nil, nil) do
          do_on_click
        end
      else
        $window.register_stock(stock)
        @button = Gtk::Button.new(stock)
        PandoraGtk.set_button_text(@button)

        tooltip ||= stock.to_s.capitalize
        @button.tooltip_text = _(tooltip)
        @button.signal_connect('clicked') do |*args|
          do_on_click
        end
      end

      @button.can_focus = false

      @entry.instance_variable_set('@button', @button)

      #def @entry.key_event(widget, event)
      @entry.define_singleton_method('key_event') do |widget, event|
        res = ((event.keyval==32) or ((event.state.shift_mask? \
          or event.state.mod1_mask?) \
          and (event.keyval==65364)))  # Space, Shift+Down or Alt+Down
        if res
          if @button.is_a? GoodButton
            parent.do_on_click
          else
            @button.activate
          end
        end
        false
      end

      self.pack_start(entry, true, true, 0)
      align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
      align.add(@button)
      self.pack_start(align, false, false, 1)
      esize = entry.size_request
      h = esize[1]-2
      @button.set_size_request(h, h)
    end

    def do_on_click
      res = false
      @entry.grab_focus
      if @popwin and (not @popwin.destroyed?)
        @popwin.destroy
        @popwin = nil
      else
        @popwin = Gtk::Window.new #(Gtk::Window::POPUP)
        popwin = @popwin
        popwin.transient_for = $window if PandoraUtils.os_family == 'windows'
        popwin.modal = @modal
        popwin.decorated = false
        popwin.skip_taskbar_hint = true
        popwin.destroy_with_parent = true

        popwidget = get_popwidget
        popwin.add(popwidget)
        popwin.signal_connect('delete_event') { @popwin.destroy; @popwin=nil }

        popwin.signal_connect('focus-out-event') do |win, event|
          GLib::Timeout.add(100) do
            if not win.destroyed?
              @popwin.destroy
              @popwin = nil
            end
            false
          end
          false
        end

        popwin.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            if @close_on_enter
              @popwin.destroy
              @popwin = nil
            end
            false
          elsif (event.keyval==Gdk::Keyval::GDK_Escape) or \
            ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
            event.keyval) and event.state.control_mask?) #w, W, ц, Ц
          then
            @popwin.destroy
            @popwin = nil
            false
          elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
            event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
            Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
            and event.state.control_mask?) #q, Q, й, Й
          then
            @popwin.destroy
            @popwin = nil
            $window.do_menu_act('Quit')
            false
          else
            false
          end
        end

        pos = @entry.window.origin
        all = @entry.allocation.to_a
        popwin.move(pos[0], pos[1]+all[3]+1)

        popwin.show_all
      end
      res
    end

    def get_popwidget   # Example widget
      wid = Gtk::Button.new('Here must be a popup widget')
      wid.signal_connect('clicked') do |*args|
        @entry.text = 'AValue'
        @popwin.destroy
        @popwin = nil
      end
      wid
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

  # Popup choose window
  # RU: Всплывающее окно выбора
  class PopWindow < Gtk::Window
    attr_accessor :root_vbox, :just_leaved, :on_click_btn

    def get_popwidget
      nil
    end

    def initialize(amodal=nil)
      super()

      @just_leaved = false

      self.transient_for = $window if PandoraUtils.os_family == 'windows'
      amodal = false if amodal.nil?
      self.modal = amodal
      self.decorated = false
      self.skip_taskbar_hint = true

      popwidget = get_popwidget
      self.add(popwidget) if popwidget
      self.signal_connect('delete_event') do
        destroy
      end

      self.signal_connect('focus-out-event') do |win, event|
        if not @just_leaved.nil?
          @just_leaved = true
          if not destroyed?
            hide
          end
          GLib::Timeout.add(500) do
            @just_leaved = false if not destroyed?
            false
          end
        end
        false
      end

      self.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Escape) or \
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask?) #w, W, ц, Ц
        then
          @just_leaved = nil
          hide
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          destroy
          $window.do_menu_act('Quit')
          false
        else
          false
        end
      end
    end

    def hide_popwin
      @just_leaved = nil
      self.hide
    end

  end

  # Smile choose window
  # RU: Окно выбора смайла
  class SmilePopWindow < PopWindow
    attr_accessor :preset, :poly_btn, :preset

    def initialize(apreset=nil, amodal=nil)
      apreset ||= 'vk'
      @preset = apreset
      super(amodal)
      self.signal_connect('key-press-event') do |widget, event|
        if (event.keyval==Gdk::Keyval::GDK_Tab)
          if preset=='qip'
            @vk_btn.do_on_click
          else
            @qip_btn.do_on_click
          end
          true
        elsif [Gdk::Keyval::GDK_b, Gdk::Keyval::GDK_B, 1737, 1769].include?(event.keyval)
          @poly_btn.set_active((not @poly_btn.active?))
          false
        else
          false
        end
      end
    end

    def get_popwidget
      if @root_vbox.nil? or @root_vbox.destroyed?
        @root_vbox = Gtk::VBox.new
        @smile_box = Gtk::Frame.new
        #@smile_box.shadow_type = Gtk::SHADOW_NONE
        hbox = Gtk::HBox.new
        $window.register_stock(:music, 'qip')
        @qip_btn = GoodButton.new(:music_qip, 'qip', -1) do |*args|
          if not @qip_btn.active?
            @qip_btn.set_active(true)
            @vk_btn.set_active(false)
            move_and_show('qip')
          end
        end
        hbox.pack_start(@qip_btn, true, true, 0)
        $window.register_stock(:ufo, 'vk')
        @vk_btn = GoodButton.new(:ufo_vk, 'vk', -1) do |*args|
          if not @vk_btn.active?
            @vk_btn.set_active(true)
            @qip_btn.set_active(false)
            move_and_show('vk')
          end
        end
        hbox.pack_start(@vk_btn, true, true, 0)
        $window.register_stock(:bomb, 'qip')
        @poly_btn = GoodButton.new(:bomb_qip, nil, false)
        @poly_btn.tooltip_text = _('Many smiles')
        hbox.pack_start(@poly_btn, false, false, 0)
        root_vbox.pack_start(hbox, false, true, 0)
        if preset=='vk'
          @vk_btn.set_active(true)
        else
          @qip_btn.set_active(true)
        end
        root_vbox.pack_start(@smile_box, true, true, 0)
      end
      root_vbox
    end

    def init_smiles_box(preset, smiles_parent, smile_btn)
      @@smile_btn = smile_btn if smile_btn
      @@smile_boxes ||= {}
      vbox = nil
      res = @@smile_boxes[preset]
      if res
        vbox = res[0]
        vbox = nil if vbox.destroyed?
      end
      if vbox
        resize(100, 100)
        #p '  vbox.parent='+vbox.parent.inspect
        if vbox.parent and (not vbox.parent.destroyed?)
          if (vbox.parent != smiles_parent)
            #p '  reparent'
            smiles_parent.remove(smiles_parent.child) if smiles_parent.child
            vbox.parent.remove(vbox)
            smiles_parent.add(vbox)
            vbox.reparent(smiles_parent)
          end
        else
          #p '  set_parent'
          smiles_parent.remove(smiles_parent.child) if smiles_parent.child
          vbox.parent = smiles_parent
        end
      else
        smiles_parent.remove(smiles_parent.child) if smiles_parent.child
        vbox = Gtk::VBox.new
        icon_params, icon_file_desc = $window.get_icon_file_params(preset)
        focus_btn = nil
        if icon_params and (icon_params.size>0)
          row = 0
          col = 0
          max_col = Math.sqrt(icon_params.size).round
          hbox = Gtk::HBox.new
          icon_params.each_with_index do |smile, i|
            if col>max_col
              vbox.pack_start(hbox, false, false, 0)
              hbox = Gtk::HBox.new
              col = 0
              row += 1
            end
            col += 1
            buf = $window.get_icon_buf(smile, preset)
            aimage = Gtk::Image.new(buf)
            btn = Gtk::ToolButton.new(aimage, smile)
            btn.set_can_focus(true)
            btn.tooltip_text = smile
            #btn.events = Gdk::Event::ALL_EVENTS_MASK
            focus_btn = btn if i==0
            btn.signal_connect('clicked') do |widget|
              clear_click = (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              btn.grab_focus
              smile_btn = @@smile_btn
              smile_btn.on_click_btn.call(preset, widget.label)
              hide_popwin if clear_click and (not smile_btn.poly_btn.active?)
              false
            end
            btn.signal_connect('key-press-event') do |widget, event|
              res = false
              if [Gdk::Keyval::GDK_space, Gdk::Keyval::GDK_KP_Space].include?(event.keyval)
                smile_btn = @@smile_btn
                smile_btn.on_click_btn.call(preset, widget.label)
                res = true
              elsif [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
                smile_btn = @@smile_btn
                smile_btn.on_click_btn.call(preset, widget.label)
                hide_popwin
                res = true
              end
              res
            end
            btn.signal_connect('expose-event') do |widget, event|
              if widget.focus?   #STATE_PRELIGHT
                widget.style.paint_focus(widget.window, Gtk::STATE_NORMAL, \
                  event.area, widget, '', event.area.x+1, event.area.y+1, \
                  event.area.width-2, event.area.height-2)
              end
              false
            end
            hbox.pack_start(btn, true, true, 0)
          end
          vbox.pack_start(hbox, false, false, 0)
          vbox.show_all
        end
        smiles_parent.add(vbox)
        res = [vbox, focus_btn]
        @@smile_boxes[preset] = res
      end
      res
    end

    def move_and_show(apreset=nil, x=nil, y=nil, a_on_click_btn=nil)
      @preset = apreset if apreset
      @on_click_btn = a_on_click_btn if a_on_click_btn
      popwidget = get_popwidget
      vbox, focus_btn = init_smiles_box(@preset, @smile_box, self)
      popwidget.show_all
      pwh = popwidget.size_request
      resize(*pwh)

      if x and y
        @x = x
        @y = y
      end

      move(@x, @y-pwh[1])
      show_all
      present
      focus_btn.grab_focus if focus_btn
    end

  end

  # Smile choose box
  # RU: Поле выбора смайлов
  class SmileButton < Gtk::ToolButton
    attr_accessor :on_click_btn, :popwin

    def initialize(apreset=nil, *args)
      aimage = $window.get_preset_image('smile')
      super(aimage, _('smile'))
      self.tooltip_text = _('smile')
      apreset ||= 'vk'
      @preset = apreset
      @@popwin ||= nil

      @on_click_btn = Proc.new do |*args|
        yield(*args) if block_given?
      end

      signal_connect('clicked') do |*args|
        popwin = @@popwin
        if popwin and (not popwin.destroyed?) and (popwin.visible? or popwin.just_leaved)
          popwin.hide
        else
          if popwin.nil? or popwin.destroyed?
            @@popwin = SmilePopWindow.new(@preset, false)
            popwin = @@popwin
          end
          borig = self.window.origin
          brect = self.allocation.to_a
          x = brect[0]+borig[0]
          y = brect[1]+borig[1]-1
          popwin.move_and_show(nil, x, y, @on_click_btn)
          popwin.poly_btn.set_active(false)
        end
        popwin.just_leaved = false
        false
      end
    end

  end

  # Color box for calendar day
  # RU: Цветной бокс дня календаря
  class ColorDayBox < Gtk::EventBox
    attr_accessor :bg, :day_date

    def initialize(background=nil)
      super()
      @bg = background
      self.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK | Gdk::Event::FOCUS_CHANGE_MASK
      self.signal_connect('focus-in-event') do |widget, event|
        self.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#88CC88')) if day_date
        false
      end
      self.signal_connect('focus-out-event') do |widget, event|
        self.modify_bg(Gtk::STATE_NORMAL, @bg)
        false
      end
      self.signal_connect('button-press-event') do |widget, event|
        res = false
        if (event.button == 1) and widget.can_focus?
          widget.set_focus(true)
          yield(self) if block_given?
          res = true
        elsif (event.button == 3)
          popwin = self.parent.parent.parent
          if popwin.is_a? DatePopWindow
            popwin.show_month_menu(event.time)
            res = true
          end
        end
        res
      end
    end

    def bg=(background)
      @bg = background
      bgc = nil
      if not bg.nil?
        if bg.is_a? String
          bgc = Gdk::Color.parse(bg)
        elsif
          bgc = bg
        end
      end
      @bg = bgc
      self.modify_bg(Gtk::STATE_NORMAL, bgc)
    end

  end

  # Date choose window
  # RU: Окно выбора даты
  class DatePopWindow < PopWindow
    attr_accessor :date, :year, :month, :month_btn, :year_btn, :date_entry, \
      :holidays, :left_mon_btn, :right_mon_btn, :left_year_btn, :right_year_btn

    def initialize(adate=nil, amodal=nil)
      @@month_menu = nil
      @@year_menu  = nil
      @@year_mi = nil
      @@days_box = nil
      @date ||= adate
      @year_holidays = {}
      super(amodal)
      self.signal_connect('key-press-event') do |widget, event|
        if [32, Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          if focus and (focus.is_a? ColorDayBox)
            event = Gdk::EventButton.new(Gdk::Event::BUTTON_PRESS)
            event.button = 1
            focus.signal_emit('button-press-event', event)
          end
          true
        elsif (event.keyval==Gdk::Keyval::GDK_Tab)
          false
        elsif (event.keyval>=65360) and (event.keyval<=65367)
          ctrl = (event.state.control_mask? or event.state.shift_mask?)
          if event.keyval==65360 or (ctrl and event.keyval==65361)
            left_mon_btn.clicked
          elsif event.keyval==65367 or (ctrl and event.keyval==65363)
            right_mon_btn.clicked
          elsif event.keyval==65365 or (ctrl and event.keyval==65362)
            left_year_btn.clicked
          elsif event.keyval==65366 or (ctrl and event.keyval==65364)
            right_year_btn.clicked
          end
          false
        else
          false
        end
      end
      self.signal_connect('scroll-event') do |widget, event|
        ctrl = (event.state.control_mask? or event.state.shift_mask?)
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          if ctrl
            left_year_btn.clicked
          else
            left_mon_btn.clicked
          end
        else
          if ctrl
            right_year_btn.clicked
          else
            right_mon_btn.clicked
          end
        end
        true
      end
    end

    def get_holidays(year)
      @holidays = @year_holidays[year]
      if not @holidays
        holidays_fn = File.join($pandora_lang_dir, 'holiday.'+$country+'.'+year.to_s+'.txt')
        f_exist = File.exist?(holidays_fn)
        if not f_exist
          year = 0
          @holidays = @year_holidays[year]
          if not @holidays
            holidays_fn = File.join($pandora_lang_dir, 'holiday.'+$country+'.0000.txt')
            f_exist = File.exist?(holidays_fn)
          end
        end
        if f_exist
          @holidays = {}
          month = nil
          set_line = nil
          IO.foreach(holidays_fn) do |line|
            if (line.is_a? String) and (line.size>0)
              if line[0]==':'
                month = line[1..-1].to_i
                set_line = 0
              elsif set_line and (set_line<2)
                set_line += 1
                day_list = line.split(',')
                day_list.each do |days|
                  i = days.index('-')
                  if i
                    d1 = days[0, i].to_i
                    d2 = days[i+1..-1].to_i
                    (d1..d2).each do |d|
                      holidays[month.to_s+'.'+d.to_s] = true
                    end
                  else
                    holidays[month.to_s+'.'+days.to_i.to_s] = set_line
                  end
                end
              end
            end
          end
          @year_holidays[year] = @holidays
        end
      end
      @holidays
    end

    def show_month_menu(time=nil)
      if not @@month_menu
        @@month_menu = Gtk::Menu.new
        time_now = Time.now
        12.times do |mon|
          mon_time = Time.gm(time_now.year, mon+1, 1)
          menuitem = Gtk::MenuItem.new(_(mon_time.strftime('%B')))
          menuitem.signal_connect('activate') do |widget|
            @month = mon+1
            init_days_box
          end
          @@month_menu.append(menuitem)
          @@month_menu.show_all
        end
      end
      time ||= 0
      @@month_menu.popup(nil, nil, 3, time) do |menu, x, y, push_in|
        @just_leaved = nil
        GLib::Timeout.add(500) do
          @just_leaved = false if not destroyed?
          false
        end
        borig = @month_btn.window.origin
        brect = @month_btn.allocation.to_a
        x = borig[0]+brect[0]
        y = borig[1]+brect[1]+brect[3]
        [x, y]
      end
    end

    def show_year_menu(time=nil)
      if not @@year_menu
        @@year_menu = Gtk::Menu.new
        time_now = Time.now
        ((time_now.year-55)..time_now.year).each do |year|
          menuitem = Gtk::MenuItem.new(year.to_s)
          menuitem.signal_connect('activate') do |widget|
            @year = year
            get_holidays(@year)
            init_days_box
          end
          @@year_menu.append(menuitem)
          @@year_mi = menuitem if @year == year
        end
        @@year_menu.show_all
      end
      @@year_menu.select_item(@@year_mi) if @@year_mi
      time ||= 0
      @@year_menu.popup(nil, nil, 3, time) do |menu, x, y, push_in|
        @just_leaved = nil
        GLib::Timeout.add(500) do
          @just_leaved = false if not destroyed?
          false
        end
        borig = @year_btn.window.origin
        brect = @year_btn.allocation.to_a
        x = borig[0]+brect[0]
        y = borig[1]+brect[1]+brect[3]
        [x, y]
      end
    end

    def get_popwidget
      if @root_vbox.nil? or @root_vbox.destroyed?
        @root_vbox = Gtk::VBox.new
        @days_frame = Gtk::Frame.new
        @days_frame.shadow_type = Gtk::SHADOW_IN

        cur_btn = Gtk::Button.new(_'Current time')
        cur_btn.signal_connect('clicked') do |widget|
          time_now = Time.now
          if (@month == time_now.month) and (@year == time_now.year)
            @date_entry.on_click_btn.call(time_now)
          else
            @month = time_now.month
            @year = time_now.year
            get_holidays(@year)
          end
          init_days_box
        end
        root_vbox.pack_start(cur_btn, false, false, 0)

        row = Gtk::HBox.new
        @left_mon_btn = Gtk::Button.new('<')
        left_mon_btn.signal_connect('clicked') do |widget|
          if @month>1
            @month -= 1
          else
            @year -= 1
            @month = 12
            get_holidays(@year)
          end
          init_days_box
        end
        row.pack_start(left_mon_btn, true, true, 0)
        @month_btn = Gtk::Button.new('month')
        month_btn.width_request = 90
        month_btn.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
        month_btn.signal_connect('clicked') do |widget, event|
          show_month_menu
        end
        month_btn.signal_connect('scroll-event') do |widget, event|
          if (event.direction==Gdk::EventScroll::UP) \
          or (event.direction==Gdk::EventScroll::LEFT)
            left_mon_btn.clicked
          else
            right_mon_btn.clicked
          end
          true
        end
        row.pack_start(month_btn, true, true, 0)
        @right_mon_btn = Gtk::Button.new('>')
        right_mon_btn.signal_connect('clicked') do |widget|
          if @month<12
            @month += 1
          else
            @year += 1
            @month = 1
            get_holidays(@year)
          end
          init_days_box
        end
        row.pack_start(right_mon_btn, true, true, 0)

        @left_year_btn = Gtk::Button.new('<')
        left_year_btn.signal_connect('clicked') do |widget|
          @year -= 1
          get_holidays(@year)
          init_days_box
        end
        row.pack_start(left_year_btn, true, true, 0)
        @year_btn = Gtk::Button.new('year')
        year_btn.signal_connect('clicked') do |widget, event|
          show_year_menu
        end
        year_btn.signal_connect('scroll-event') do |widget, event|
          if (event.direction==Gdk::EventScroll::UP) \
          or (event.direction==Gdk::EventScroll::LEFT)
            left_year_btn.clicked
          else
            right_year_btn.clicked
          end
          true
        end
        row.pack_start(year_btn, true, true, 0)
        @right_year_btn = Gtk::Button.new('>')
        right_year_btn.signal_connect('clicked') do |widget|
          @year += 1
          get_holidays(@year)
          init_days_box
        end
        row.pack_start(right_year_btn, true, true, 0)

        root_vbox.pack_start(row, false, true, 0)
        root_vbox.pack_start(@days_frame, true, true, 0)
      end
      root_vbox
    end

    Sunday_Contries = ['US', 'JA', 'CA', 'IN', 'BR', 'AR', 'MX', 'IL', 'PH', \
      'PE', 'BO', 'EC', 'VE', 'ZA', 'CO', 'KR', 'TW', 'HN', 'NI', 'PA']
    Saturay_Contries = ['EG', 'LY', 'IR', 'AF', 'SY', 'DZ', 'SA', 'YE', 'IQ', 'JO']

    def init_days_box
      labs_parent = @days_frame
      if @@days_box
        evbox = @@days_box
        evbox = nil if evbox.destroyed?
      end
      @labs ||= []

      #p '---init_days_box: [date, month, year]='+[date, month, year].inspect
      time_now = Time.now
      month_d1 = Time.gm(@year, @month, 1)
      d1_wday = month_d1.wday
      start = nil
      if Sunday_Contries.include?($country)
        start = d1_wday
      elsif Saturay_Contries.include?($country)
        start = d1_wday+1
        start = 0 if d1_wday==6
      else
        d1_wday = 7 if d1_wday==0
        start = d1_wday-1
      end
      #start =+ 7 if start==0
      start_time = month_d1 - (start+1)*3600*24
      start_day = Time.gm(start_time.year, start_time.month, start_time.day)

      if evbox
        resize(100, 100)
        if evbox.parent and (not evbox.parent.destroyed?)
          if (evbox.parent != labs_parent)
            labs_parent.remove(labs_parent.child) if labs_parent.child
            evbox.parent.remove(evbox)
            labs_parent.add(evbox)
            evbox.reparent(labs_parent)
          end
        else
          labs_parent.remove(labs_parent.child) if labs_parent.child
          evbox.parent = labs_parent
        end
      else
        labs_parent.remove(labs_parent.child) if labs_parent.child

        evbox = ColorDayBox.new('#FFFFFF')
        evbox.can_focus = false
        @@days_box = evbox
        labs_parent.add(evbox)

        vbox = Gtk::VBox.new
        focus_btn = nil

        7.times do |week|
          row = Gtk::HBox.new
          row.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#FFFFFF'))
          vbox.pack_start(row, true, true, 1)
          7.times do |day|
            lab = Gtk::Label.new
            @labs[week*7+day] = lab
            lab.width_chars = 4
            lab.use_markup = true
            lab.justify = Gtk::JUSTIFY_CENTER

            lab_evbox = ColorDayBox.new do |lab_evbox|
              @date_entry.on_click_btn.call(lab_evbox.day_date)
            end
            lab_evbox.day_date = true
            lab_evbox.add(lab)
            row.pack_start(lab_evbox, true, true, 1)
          end
        end

        evbox.add(vbox)
        labs_parent.show_all
      end

      @month_btn.label = _(month_d1.strftime('%B'))
      @year_btn.label = month_d1.strftime('%Y')

      cal_day = start_day

      7.times do |week|
        7.times do |day|
          bg_type = nil
          curr_day = nil
          chsd_day = nil
          text = '0'
          if week==0
            #p '---[@year, @month, day+1]='+[@year, @month, day+1].inspect
            atime = start_day + (day+1)*3600*24
            text = _(atime.strftime('%a'))
            #p '+++++++ WEEKDAY='+text.inspect
            bg_type = :capt
          else
            cal_day += 3600*24
            text = (cal_day.day).to_s
            if cal_day.month == @month
              bg_type = :work
              wday = cal_day.wday
              bg_type = :rest if (wday==0) or (wday==6)
              if holidays and (set_line = holidays[@month.to_s+'.'+cal_day.day.to_s])
                if set_line==2
                  bg_type = :work
                else
                  bg_type = :holi
                end
              end
            end
            if (cal_day.day == time_now.day) and (cal_day.month == time_now.month) \
            and (cal_day.year == time_now.year)
              curr_day = true
            end
            if date and (cal_day.day == date.day) and (cal_day.month == date.month) \
            and (cal_day.year == date.year)
              chsd_day = true
            end
          end
          bg = nil
          if bg_type==:work
            bg = '#DDEEFF'
          elsif bg_type==:rest
            bg = '#5050A0'
          elsif bg_type==:holi
            bg = '#B05050'
          else
            bg = '#FFFFFF'
          end

          lab = @labs[week*7+day]
          if lab.use_markup?
            if bg_type==:capt
              lab.set_markup('<b>'+text+'</b>')
            else
              fg = nil
              if (bg_type==:rest) or (bg_type==:holi)
                fg = '#66FF66' if curr_day
                fg ||= '#EEEE44' if chsd_day
                fg ||= '#FFFFFF'
              else
                fg = '#00BB00' if curr_day
                fg ||= '#AAAA00' if chsd_day
              end
              text = '<b>'+text+'</b>' if chsd_day
              fg ||= '#000000'
              lab.set_markup('<span foreground="'+fg+'">'+text+'</span>')
            end
          else
            lab.text = text
          end
          lab.parent.day_date = cal_day
          lab_evbox = lab.parent
          lab_evbox.bg = bg
          lab_evbox.can_focus = (bg_type != :capt)
        end
      end

      [vbox, focus_btn]
    end

    def move_and_show(adate=nil, adate_entry=nil, x=nil, y=nil, a_on_click_btn=nil)
      @date = adate
      @date_entry = adate_entry if adate_entry
      if @date
        @month = date.month
        @year = date.year
      else
        time_now = Time.now
        @month = time_now.month
        @year = time_now.year
      end
      get_holidays(@year)
      @on_click_btn = a_on_click_btn if a_on_click_btn
      popwidget = get_popwidget
      vbox, focus_btn = init_days_box
      popwidget.show_all
      pwh = popwidget.size_request
      resize(*pwh)
      if x and y
        @x = x
        @y = y
      end
      move(@x, @y)
      show_all
      present
      month_btn.grab_focus
    end

  end

  # Entry for date with calendar button
  # RU: Поле ввода даты с кнопкой календаря
  class DateEntry < BtnEntry
    attr_accessor :on_click_btn, :popwin

    def update_mark(month, year, time_now=nil)
      #time_now ||= Time.now
      #@cal.clear_marks
      #@cal.mark_day(time_now.day) if ((time_now.month==month) and (time_now.year==year))
    end

    def initialize(amodal=nil, *args)
      super(MaskEntry, :date, 'Date', amodal, *args)
      @@popwin ||= nil
      @close_on_enter = false
      @entry.mask = '0123456789.'
      @entry.max_length = 10
      @entry.tooltip_text = 'DD.MM.YYYY'
      @entry.width_request = PandoraGtk.num_char_width*@entry.max_length+8
      @on_click_btn = Proc.new do |date|
        @entry.text = PandoraUtils.date_to_str(date)
        @@popwin.hide_popwin
      end
    end

    def do_on_click
      res = false
      @entry.grab_focus
      popwin = @@popwin
      if popwin and (not popwin.destroyed?) and (popwin.visible? or popwin.just_leaved) \
      and (popwin.date_entry==self)
        popwin.hide
      else
        date = PandoraUtils.str_to_date(@entry.text)
        if popwin.nil? or popwin.destroyed? or (popwin.modal? != @modal)
          @@popwin = DatePopWindow.new(date, @modal)
          popwin = @@popwin
        end
        borig = @entry.window.origin
        brect = @entry.allocation.to_a
        x = borig[0]
        y = borig[1]+brect[3]+1
        popwin.move_and_show(date, self, x, y, @on_click_btn)
      end
      popwin.just_leaved = false
      res
    end

  end

  # Entry for time
  # RU: Поле ввода времени
  class TimeEntry < BtnEntry
    attr_accessor :hh_spin, :mm_spin, :ss_spin

    def initialize(amodal=nil, *args)
      super(MaskEntry, :time, 'Time', amodal, *args)
      @entry.mask = '0123456789:'
      @entry.max_length = 8
      @entry.tooltip_text = 'hh:mm:ss'
      @entry.width_request = PandoraGtk.num_char_width*@entry.max_length+8
      @@time_his ||= nil
    end

    def get_time(update_spin=nil)
      res = nil
      time = PandoraUtils.str_to_date(@entry.text)
      if time
        vals = time.to_a
        res = [vals[2], vals[1], vals[0]]  #hh,mm,ss
      else
        res = [0, 0, 0]
      end
      if update_spin
        hh_spin.value = res[0] if hh_spin
        mm_spin.value = res[1] if mm_spin
        ss_spin.value = res[2] if ss_spin
      end
      res
    end

    def set_time(hh, mm=nil, ss=nil)
      hh0, mm0, ss0 = get_time
      hh ||= hh0
      mm ||= mm0
      ss ||= ss0
      shh = PandoraUtils.int_to_str_zero(hh, 2)
      smm = PandoraUtils.int_to_str_zero(mm, 2)
      sss = PandoraUtils.int_to_str_zero(ss, 2)
      @entry.text = shh + ':' + smm + ':' + sss
    end

    ColNumber = 2
    RowNumber = 4
    DefTimeHis = '09:00|14:15|17:30|20:45'.split('|')

    def get_popwidget
      if not @@time_his
        @@time_his = PandoraUtils.get_param('time_history')
        @@time_his ||= ''
        @@time_his = @@time_his.split('|')
        (@@time_his.size..ColNumber*RowNumber-1).each do |i|
          @@time_his << DefTimeHis[i % DefTimeHis.size]
        end
      end
      vbox = Gtk::VBox.new
      btn1 = Gtk::Button.new(_'Current time')
      btn1.signal_connect('clicked') do |widget|
        @entry.text = Time.now.strftime('%H:%M:%S')
        get_time(true)
      end
      vbox.pack_start(btn1, false, false, 0)

      i = 0
      RowNumber.times do |row|
        hbox = Gtk::HBox.new
        ColNumber.times do |col|
          time_str = @@time_his[row + col*RowNumber]
          if time_str
            btn = Gtk::Button.new(time_str)
            btn.signal_connect('clicked') do |widget|
              @entry.text = widget.label+':00'
              get_time(true)
            end
            hbox.pack_start(btn, true, true, 0)
          else
            break
          end
        end
        vbox.pack_start(hbox, false, false, 0)
      end

      hbox = Gtk::HBox.new

      adj = Gtk::Adjustment.new(0, 0, 23, 1, 5, 0)
      @hh_spin = Gtk::SpinButton.new(adj, 0, 0)
      hh_spin.max_length = 2
      hh_spin.numeric = true
      hh_spin.wrap = true
      hh_spin.signal_connect('value-changed') do |widget|
        set_time(widget.value_as_int)
      end
      hbox.pack_start(hh_spin, false, true, 0)

      adj = Gtk::Adjustment.new(0, 0, 59, 1, 5, 0)
      @mm_spin = Gtk::SpinButton.new(adj, 0, 0)
      mm_spin.max_length = 2
      mm_spin.numeric = true
      mm_spin.wrap = true
      mm_spin.signal_connect('value-changed') do |widget|
        set_time(nil, widget.value_as_int)
      end
      hbox.pack_start(mm_spin, false, true, 0)

      adj = Gtk::Adjustment.new(0, 0, 59, 1, 5, 0)
      @ss_spin = Gtk::SpinButton.new(adj, 0, 0)
      ss_spin.max_length = 2
      ss_spin.numeric = true
      ss_spin.wrap = true
      ss_spin.signal_connect('value-changed') do |widget|
        set_time(nil, nil, widget.value_as_int)
      end
      hbox.pack_start(ss_spin, false, true, 0)

      get_time(true)
      vbox.pack_start(hbox, false, false, 0)

      btn = Gtk::Button.new(Gtk::Stock::OK)
      btn.signal_connect('clicked') do |widget|
        new_time = @entry.text
        if new_time and @@time_his
          i = new_time.rindex(':')
          new_time = new_time[0, i] if i
          i = @@time_his.index(new_time)
          if (not i) or (i >= (@@time_his.size / 2))
            if i
              @@time_his.delete_at(i)
            else
              @@time_his.pop
            end
            @@time_his.unshift(new_time)
            PandoraUtils.set_param('time_history', @@time_his.join('|'))
          end
        end
        @popwin.destroy
        @popwin = nil
      end
      vbox.pack_start(btn, false, false, 0)

      hh_spin.grab_focus

      vbox
    end

  end

  # Entry for relation kind
  # RU: Поле ввода типа связи
  class ByteListEntry < BtnEntry

    def initialize(code_name_list, amodal=nil, *args)
      super(MaskEntry, :list, 'List', amodal, *args)
      @close_on_enter = false
      @code_name_list = code_name_list
      @entry.mask = '0123456789'
      @entry.max_length = 3
      @entry.tooltip_text = 'NNN'
      @entry.width_request = PandoraGtk.num_char_width*10+8
    end

    def get_popwidget
      store = Gtk::ListStore.new(Integer, String)
      @code_name_list.each do |kind,name|
        iter = store.append
        iter[0] = kind
        iter[1] = _(name)
      end

      @treeview = Gtk::TreeView.new(store)
      treeview = @treeview
      treeview.rules_hint = true
      treeview.search_column = 0
      treeview.border_width = 10
      #treeview.hover_selection = false
      #treeview.selection.mode = Gtk::SELECTION_BROWSE

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Code'), renderer, 'text' => 0)
      column.set_sort_column_id(0)
      treeview.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Description'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      treeview.append_column(column)

      treeview.signal_connect('row-activated') do |tree_view, path, column|
        path, column = tree_view.cursor
        if path
          store = tree_view.model
          iter = store.get_iter(path)
          if iter and iter[0]
            @entry.text = iter[0].to_s
            if not @popwin.destroyed?
              @popwin.destroy
              @popwin = nil
            end
          end
        end
        false
      end

      # Make choose only when click to selected
      #treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      #treeview.signal_connect('button-press-event') do |widget, event|
      #  @iter = widget.selection.selected if (event.button == 1)
      #  false
      #end
      #treeview.signal_connect('button-release-event') do |widget, event|
      #  if (event.button == 1) and @iter
      #    path, column = widget.cursor
      #    if path and (@iter.path == path)
      #      widget.signal_emit('row-activated', nil, nil)
      #    end
      #  end
      #  false
      #end

      treeview.signal_connect('event-after') do |widget, event|
        if event.kind_of?(Gdk::EventButton) and (event.button == 1)
          iter = widget.selection.selected
          if iter
            path, column = widget.cursor
            if path and (iter.path == path)
              widget.signal_emit('row-activated', nil, nil)
            end
          end
        end
        false
      end

      treeview.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          widget.signal_emit('row-activated', nil, nil)
          true
        else
          false
        end
      end

      frame = Gtk::Frame.new
      frame.shadow_type = Gtk::SHADOW_OUT
      frame.add(treeview)

      treeview.can_default = true
      treeview.grab_focus

      frame
    end
  end

  # Dialog for panhash choose
  # RU: Диалог для выбора панхэша
  class PanhashDialog < AdvancedDialog
    attr_accessor :panclasses

    def initialize(apanclasses)
      @panclasses = apanclasses
      super(_('Choose object'))
      $window.register_stock(:panhash)
      iconset = Gtk::IconFactory.lookup_default('panhash')
      style = Gtk::Widget.default_style  #Gtk::Style.new
      anicon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
      self.icon = anicon

      self.skip_taskbar_hint = true
      self.set_default_size(600, 400)
      auto_create = true
      @panclasses.each_with_index do |panclass, i|
        title = _(PandoraUtils.get_name_or_names(panclass.name, true))
        self.main_sw.destroy if i==0
        #image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
        image = $window.get_panobject_image(panclass.ider, Gtk::IconSize::SMALL_TOOLBAR)
        label_box2 = TabLabelBox.new(image, title)
        pbox = PandoraGtk::PanobjScrolledWindow.new
        page = self.notebook.append_page(pbox, label_box2)
        auto_create = PandoraGtk.show_panobject_list(panclass, nil, pbox, auto_create)
      end
      self.notebook.page = 0
    end

    # Show dialog and send choosed panhash,sha1,md5 to yield block
    # RU: Показать диалог и послать панхэш,sha1,md5 в выбранный блок
    def choose_record(*add_fields)
      self.run2 do
        panhash = nil
        add_fields = nil if not ((add_fields.is_a? Array) and (add_fields.size>0))
        field_vals = nil
        pbox = self.notebook.get_nth_page(self.notebook.page)
        treeview = pbox.treeview
        if treeview.is_a? SubjTreeView
          path, column = treeview.cursor
          panobject = treeview.panobject
          if path and panobject
            store = treeview.model
            iter = store.get_iter(path)
            id = iter[0]
            fields = 'panhash'
            this_is_blob = (panobject.is_a? PandoraModel::Blob)
            fields << ','+add_fields.join(',') if add_fields
            sel = panobject.select('id='+id.to_s, false, fields)
            if sel and (sel.size>0)
              rec = sel[0]
              panhash = rec[0]
              field_vals = rec[1..-1] if add_fields
            end
          end
        end
        if block_given?
          if field_vals
            yield(panhash, *field_vals)
          else
            yield(panhash)
          end
        end
      end
    end

  end

  MaxPanhashTabs = 5

  # Entry for panhash
  # RU: Поле ввода панхэша
  class PanhashBox < BtnEntry
    attr_accessor :types, :panclasses

    def initialize(panhash_type, amodal=nil, *args)
      @panclasses = nil
      @types = panhash_type
      stock = nil
      if @types=='Panhash'
        @types = 'Panhash(Blob,Person,Community,City,Key)'
        stock = :panhash
      end
      set_classes
      title = nil
      if (panclasses.is_a? Array) and (panclasses.size>0) and (not @types.nil?)
        stock ||= $window.get_panobject_stock(panclasses[0].ider)
        panclasses.each do |panclass|
          if title
            title << ', '
          else
            title = ''
          end
          title << panclass.sname
        end
      end
      stock ||= :panhash
      stock = stock.to_sym
      title ||= 'Panhash'
      super(HexEntry, stock, title, amodal=nil, *args)
      @entry.max_length = 44
      @entry.width_request = PandoraGtk.num_char_width*(@entry.max_length+1)+8
    end

    def do_on_click
      @entry.grab_focus
      set_classes
      dialog = PanhashDialog.new(@panclasses)
      dialog.choose_record do |panhash|
        if PandoraUtils.panhash_nil?(panhash)
          @entry.text = ''
        else
          @entry.text = PandoraUtils.bytes_to_hex(panhash) if (panhash.is_a? String)
        end
      end
      true
    end

    # Define panobject class list
    # RU: Определить список классов панобъектов
    def set_classes
      if not @panclasses
        #p '=== types='+types.inspect
        @panclasses = []
        @types.strip!
        if (types.is_a? String) and (types.size>0)
          drop_prefix = 0
          if (@types[0, 10].downcase=='panhashes(')
            drop_prefix = 10
          elsif (@types[0, 8].downcase=='panhash(')
            drop_prefix = 8
          end
          if drop_prefix>0
            @types = @types[drop_prefix..-2]
            @types.strip!
            @types = @types.split(',')
            @types.each do |ptype|
              ptype.strip!
              if PandoraModel.const_defined? ptype
                @panclasses << PandoraModel.const_get(ptype)
              end
            end
          end
        end
        if @panclasses.size==0
          @types = nil
          kind_list = PandoraModel.get_kind_list
          kind_list.each do |rec|
            ptype = rec[1]
            ptype.strip!
            p '---ptype='+ptype.inspect
            if PandoraModel.const_defined? ptype
              @panclasses << PandoraModel.const_get(ptype)
            end
            if @panclasses.size>MaxPanhashTabs
              break
            end
          end
        end
        #p '====panclasses='+panclasses.inspect
      end
    end

  end

  # Good FileChooserDialog
  # RU: Правильный FileChooserDialog
  class GoodFileChooserDialog < Gtk::FileChooserDialog
    def initialize(file_name, open=true, filters=nil, parent_win=nil, title=nil)
      action = nil
      act_btn = nil
      stock_id = nil
      if open
        action = Gtk::FileChooser::ACTION_OPEN
        stock_id = Gtk::Stock::OPEN
        act_btn = [stock_id, Gtk::Dialog::RESPONSE_ACCEPT]
      else
        action = Gtk::FileChooser::ACTION_SAVE
        stock_id = Gtk::Stock::SAVE
        act_btn = [stock_id, Gtk::Dialog::RESPONSE_ACCEPT]
        title ||= 'Save to file'
      end
      title ||= 'Choose a file'
      parent_win ||= $window
      super(_(title), parent_win, action, 'gnome-vfs',
        [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL], act_btn)
      dialog = self
      dialog.transient_for = parent_win
      dialog.skip_taskbar_hint = true
      dialog.default_response = Gtk::Dialog::RESPONSE_ACCEPT
      #image = $window.get_preset_image('export')
      #iconset = image.icon_set
      iconset = Gtk::IconFactory.lookup_default(stock_id.to_s)
      style = Gtk::Widget.default_style  #Gtk::Style.new
      anicon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
      dialog.icon = anicon
      dialog.add_shortcut_folder($pandora_files_dir)

      dialog.signal_connect('key-press-event') do |widget, event|
        if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
          event.keyval) and event.state.control_mask? #w, W, ц, Ц
        then
          dialog.response(Gtk::Dialog::RESPONSE_CANCEL)
          false
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
          event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
          Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
          and event.state.control_mask?) #q, Q, й, Й
        then
          dialog.destroy
          $window.do_menu_act('Quit')
          false
        else
          false
        end
      end

      filter = Gtk::FileFilter.new
      filter.name = _('All files')+' (*.*)'
      filter.add_pattern('*.*')
      dialog.add_filter(filter)

      if open
        if file_name.nil? or (file_name=='')
          dialog.current_folder = $pandora_files_dir
        else
          dialog.filename = file_name
        end
        scr = Gdk::Screen.default
        if (scr.height > 500)
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
            fn = dialog.preview_filename
            ext = nil
            ext = File.extname(fn) if fn
            if ext and (['.jpg','.gif','.png'].include? ext.downcase)
              begin
                pixbuf = Gdk::Pixbuf.new(fn, 128, 128)
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
      else #save
        if File.exist?(file_name)
          dialog.filename = file_name
        else
          dialog.current_name = File.basename(file_name) if file_name
          dialog.current_folder = $pandora_files_dir
        end
        dialog.signal_connect('notify::filter') do |widget, param|
          aname = dialog.filter.name
          i = aname.index('*.')
          ext = nil
          ext = aname[i+2..-2] if i
          if ext
            i = ext.index('*.')
            ext = ext[0..i-2] if i
          end
          if ext.nil? or (ext != '*')
            ext ||= ''
            fn = PandoraUtils.change_file_ext(dialog.filename, ext)
            dialog.current_name = File.basename(fn) if fn
          end
        end
      end
    end
  end

  # Entry for filename
  # RU: Поле выбора имени файла
  class FilenameBox < BtnEntry
    attr_accessor :window

    def initialize(parent, amodal=nil, *args)
      super(Gtk::Entry, Gtk::Stock::OPEN, 'File', amodal, *args)
      @window = parent
      @entry.width_request = PandoraGtk.num_char_width*64+8
    end

    def do_on_click
      @entry.grab_focus
      fn = PandoraUtils.absolute_path(@entry.text)
      dialog = GoodFileChooserDialog.new(fn, true, nil, @window)

      filter = Gtk::FileFilter.new
      filter.name = _('Pictures')+' (*.png,*.jpg,*.gif)'
      filter.add_pattern('*.png')
      filter.add_pattern('*.jpg')
      filter.add_pattern('*.jpeg')
      filter.add_pattern('*.gif')
      dialog.add_filter(filter)

      filter = Gtk::FileFilter.new
      filter.name = _('Sounds')+' (*.mp3,*.wav)'
      filter.add_pattern('*.mp3')
      filter.add_pattern('*.wav')
      dialog.add_filter(filter)

      if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
        filename0 = @entry.text
        @entry.text = PandoraUtils.relative_path(dialog.filename)
        if @init_yield_block
          @init_yield_block.call(@entry.text, @entry, @button, filename0)
        end
      end
      dialog.destroy if not dialog.destroyed?
      true
    end

    def width_request=(wr)
      s = button.size_request
      h = s[0]+1
      wr -= h
      wr = 24 if wr<24
      entry.set_width_request(wr)
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
  class CoordBox < BtnEntry # Gtk::HBox
    attr_accessor :latitude, :longitude
    CoordWidth = 110

    def initialize(amodal=nil, hide_btn=nil)
      super(Gtk::HBox, :coord, 'Coordinates', amodal)
      @latitude   = CoordEntry.new
      latitude.tooltip_text = _('Latitude')+': 60.716, 60 43\', 60.43\'00"N'+"\n["+latitude.mask+']'
      @longitude  = CoordEntry.new
      longitude.tooltip_text = _('Longitude')+': -114.9, W114 54\' 0", 114.9W'+"\n["+longitude.mask+']'
      latitude.width_request = CoordWidth
      longitude.width_request = CoordWidth
      entry.pack_start(latitude, false, false, 0)
      @entry.pack_start(longitude, false, false, 1)
      if hide_btn
        @button.destroy
        @button = nil
      end
    end

    def do_on_click
      @latitude.grab_focus
      dialog = PanhashDialog.new([PandoraModel::City])
      dialog.choose_record('coord') do |panhash,coord|
        if coord
          geo_coord = PandoraUtils.coil_coord_to_geo_coord(coord)
          if geo_coord.is_a? Array
            latitude.text = geo_coord[0].to_s
            longitude.text = geo_coord[1].to_s
          end
        end
      end
      true
    end

    def max_length=(maxlen)
      btn_width = 0
      btn_width = @button.allocation.width if @button
      ml = (maxlen-btn_width) / 2
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
        coord = PandoraUtils.coil_coord_to_geo_coord(i)
      else
        coord = ['', '']
      end
      latitude.text = coord[0].to_s
      longitude.text = coord[1].to_s
    end

    def text
      res = PandoraUtils.geo_coord_to_coil_coord(latitude.text, longitude.text).to_s
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

  # Entry for date and time
  # RU: Поле ввода даты и времени
  class DateTimeBox < Gtk::HBox
    attr_accessor :date, :time

    def initialize(amodal=nil)
      super()
      @date   = DateEntry.new(amodal)
      @time   = TimeEntry.new(amodal)
      #date.width_request = CoordWidth
      #time.width_request = CoordWidth
      self.pack_start(date, false, false, 0)
      self.pack_start(time, false, false, 1)
    end

    def max_length=(maxlen)
      ml = maxlen / 2
      date.max_length = ml
      time.max_length = ml
    end

    def text=(text)
      date_str = nil
      time_str = nil
      if (text.is_a? String) and (text.size>0)
        i = text.index(' ')
        i ||= text.size
        date_str = text[0, i]
        time_str = text[i+1..-1]
      end
      date_str ||= ''
      time_str ||= ''
      date.text = date_str
      time.text = time_str
    end

    def text
      res = date.text + ' ' + time.text
    end

    def width_request=(wr)
      w = wr / 2
      date.set_width_request(w+10)
      time.set_width_request(w)
    end

    def modify_text(*args)
      date.modify_text(*args)
      time.modify_text(*args)
    end

    def size_request
      size1 = date.size_request
      res = time.size_request
      res[0] = size1[0]+1+res[0]
      res
    end
  end

  MaxOnePlaceViewSec = 60

  # Extended TextView
  # RU: Расширенный TextView
  class ExtTextView < Gtk::TextView
    attr_accessor :need_to_end, :middle_time, :middle_value, :go_to_end

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

      @go_to_end = false

      self.signal_connect('size-allocate') do |widget, step, arg2|
        if @go_to_end
          @go_to_end = false
          widget.parent.vadjustment.value = \
          widget.parent.vadjustment.upper - widget.parent.vadjustment.page_size
        end
        false
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
    def after_addition(go_end=nil)
      go_end ||= @need_to_end
      if go_end
        @go_to_end = true
        adj = self.parent.vadjustment
        adj.value = adj.upper - adj.page_size
        #scroll_to_iter(buffer.end_iter, 0, true, 0.0, 1.0)
        #mark = buffer.create_mark(nil, buffer.end_iter, false)
        #scroll_to_mark(mark, 0, true, 0.0, 1.0)
        #tv.scroll_to_mark(buf.get_mark('insert'), 0.0, true, 0.0, 1.0)
        #buffer.delete_mark(mark)
      end
      go_end
    end
  end

  class ScalePixbufLoader < Gdk::PixbufLoader
    attr_accessor :scale, :width, :height, :scaled_pixbuf, :set_dest, :renew_thread

    def initialize(ascale=nil, awidth=nil, aheight=nil, *args)
      super(*args)
      @scale = 100
      @width  = nil
      @height = nil
      @scaled_pixbuf = nil
      set_scale(ascale, awidth, aheight)
    end

    def set_scale(ascale=nil, awidth=nil, aheight=nil)
      ascale ||= 100
      if (@scale != ascale) or (@width != awidth) or (@height = aheight)
        @scale = ascale
        @width  = awidth
        @height = aheight
        renew_scaled_pixbuf
      end
    end

    def renew_scaled_pixbuf(redraw_wiget=nil)
      apixbuf = self.pixbuf
      if apixbuf and ((@scale != 100) or @width or @height)
        if not @renew_thread
          @renew_thread = Thread.new do
            #sleep(0.01)
            @renew_thread = nil
            apixbuf = self.pixbuf
            awidth  = apixbuf.width
            aheight = apixbuf.height

            scale_x = nil
            scale_y = nil
            if @width or @height
              p scale_x = @width.fdiv(awidth) if @width
              p scale_y = @height.fdiv(aheight) if @height
              new_scale = nil
              if scale_x and (scale_x<1.0)
                new_scale = scale_x
              end
              if scale_y and ((scale_x and scale_x<1.0 and scale_y.abs<scale_x.abs) \
              or ((not scale_x) and scale_y<1.0))
                new_scale = scale_y
              end
              if new_scale
                new_scale = new_scale.abs
              else
                new_scale = 1.0
              end
              scale_x = scale_y = new_scale
            end
            #p '      SCALE [@scale, @width, @height, awidth, aheight, scale_x, scale_y]='+\
            #  [@scale, @width, @height, awidth, aheight, scale_x, scale_y].inspect
            if not scale_x
              scale_x = @scale.fdiv(100)
              scale_y = scale_x
            end
            p dest_width  = awidth*scale_x
            p dest_height = aheight*scale_y
            if @scaled_pixbuf
              @scaled_pixbuf.scale!(apixbuf, 0, 0, dest_width, dest_height, 0, 0, scale_x, scale_y)
            else
              @scaled_pixbuf = apixbuf.scale(dest_width, dest_height)
            end
            set_dest.call(@scaled_pixbuf) if set_dest
            redraw_wiget.queue_draw if redraw_wiget and (not redraw_wiget.destroyed?)
          end
        end
      else
        @scaled_pixbuf = apixbuf
        redraw_wiget.queue_draw if redraw_wiget and (not redraw_wiget.destroyed?)
      end
      @scaled_pixbuf
    end

  end

  ReadImagePortionSize = 1024*1024 # 1Mb

  # Start loading image from file
  # RU: Запускает загрузку картинки в файл
  def self.start_image_loading(filename, pixbuf_parent=nil, scale=nil, width=nil, height=nil)
    res = nil
    p '--start_image_loading  [filename, pixbuf_parent, scale, width, height]='+\
      [filename, pixbuf_parent, scale, width, height].inspect
    filename = PandoraUtils.absolute_path(filename)
    if File.exist?(filename)
      if (scale.nil? or (scale==100)) and width.nil? and height.nil?
        begin
          res = Gdk::Pixbuf.new(filename)
          if not pixbuf_parent
            res = Gtk::Image.new(res)
          end
        rescue => err
          if not pixbuf_parent
            err_text = _('Image loading error1')+":\n"+Utf8String.new(err.message)
            label = Gtk::Label.new(err_text)
            res = label
          end
        end
      else
        begin
          file_stream = File.open(filename, 'rb')
          res = Gtk::Image.new if not pixbuf_parent
          #sleep(0.01)
          scale ||= 100
          read_thread = Thread.new do
            pixbuf_loader = ScalePixbufLoader.new(scale, width, height)
            pixbuf_loader.signal_connect('area_prepared') do |loader|
              loader.set_dest = Proc.new do |apixbuf|
                if pixbuf_parent
                  res = apixbuf
                else
                  res.pixbuf = apixbuf if (not res.destroyed?)
                end
              end
              pixbuf = loader.pixbuf
              pixbuf.fill!(0xAAAAAAFF)
              loader.renew_scaled_pixbuf(res)
              loader.set_dest.call(loader.scaled_pixbuf)
            end
            pixbuf_loader.signal_connect('area_updated') do |loader|
              upd_wid = res
              upd_wid = pixbuf_parent if pixbuf_parent
              loader.renew_scaled_pixbuf(upd_wid)
              if pixbuf_parent
                #res = loader.pixbuf
              else
                #res.pixbuf = loader.pixbuf if (not res.destroyed?)
              end
            end
            while file_stream
              buf = file_stream.read(ReadImagePortionSize)
              if buf
                pixbuf_loader.write(buf)
                if file_stream.eof?
                  pixbuf_loader.close
                  pixbuf_loader = nil
                  file_stream.close
                  file_stream = nil
                end
                sleep(0.005)
                #sleep(1)
              else
                pixbuf_loader.close
                pixbuf_loader = nil
                file_stream.close
                file_stream = nil
              end
            end
          end
          while pixbuf_parent and read_thread.alive?
            sleep(0.01)
          end
        rescue => err
          if not pixbuf_parent
            err_text = _('Image loading error2')+":\n"+Utf8String.new(err.message)
            label = Gtk::Label.new(err_text)
            res = label
          end
        end
      end
    end
    res
  end

  class LinkTag < Gtk::TextTag
    attr_accessor :link
  end

  $font_desc = nil

  # Window for view body (text or blob)
  # RU: Окно просмотра тела (текста или блоба)
  class SuperTextView < ExtTextView
    #attr_accessor :format

    def format
      res = nil
      sw = parent
      if (sw.is_a? BodyScrolledWindow)
        res = sw.format
      end
      res ||= 'bbcode'
      res
    end

    def initialize(left_border=nil, *args)
      super(*args)
      self.wrap_mode = Gtk::TextTag::WRAP_WORD

      @hand_cursor = Gdk::Cursor.new(Gdk::Cursor::HAND2)
      @regular_cursor = Gdk::Cursor.new(Gdk::Cursor::XTERM)
      @hovering = false

      buf = self.buffer
      buf.create_tag('bold', 'weight' => Pango::FontDescription::WEIGHT_BOLD)
      buf.create_tag('italic', 'style' => Pango::FontDescription::STYLE_ITALIC)
      buf.create_tag('strike', 'strikethrough' => true)
      buf.create_tag('undline', 'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('dundline', 'underline' => Pango::AttrUnderline::DOUBLE)
      buf.create_tag('link', 'foreground' => 'blue', \
        'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('linked', 'foreground' => 'navy', \
        'underline' => Pango::AttrUnderline::SINGLE)
      buf.create_tag('left', 'justification' => Gtk::JUSTIFY_LEFT)
      buf.create_tag('center', 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('right', 'justification' => Gtk::JUSTIFY_RIGHT)
      buf.create_tag('fill', 'justification' => Gtk::JUSTIFY_FILL)
      buf.create_tag('h1', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 24 * Pango::SCALE, 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('h2', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 21 * Pango::SCALE, 'justification' => Gtk::JUSTIFY_CENTER)
      buf.create_tag('h3', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 18 * Pango::SCALE)
      buf.create_tag('h4', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'size' => 15 * Pango::SCALE)
      buf.create_tag('h5', 'weight' => Pango::FontDescription::WEIGHT_BOLD, \
        'style' => Pango::FontDescription::STYLE_ITALIC, 'size' => 12 * Pango::SCALE)
      buf.create_tag('h6', 'style' => Pango::FontDescription::STYLE_ITALIC, \
        'size' => 12 * Pango::SCALE)
      buf.create_tag('red', 'foreground' => 'red')
      buf.create_tag('green', 'foreground' => 'green')
      buf.create_tag('blue', 'foreground' => 'blue')
      buf.create_tag('navy', 'foreground' => 'navy')
      buf.create_tag('yellow', 'foreground' => 'yellow')
      buf.create_tag('magenta', 'foreground' => 'magenta')
      buf.create_tag('cyan', 'foreground' => 'cyan')
      buf.create_tag('lime', 'foreground' =>   '#00FF00')
      buf.create_tag('maroon', 'foreground' => 'maroon')
      buf.create_tag('olive', 'foreground' =>  '#808000')
      buf.create_tag('purple', 'foreground' => 'purple')
      buf.create_tag('teal', 'foreground' =>   '#008080')
      buf.create_tag('gray', 'foreground' => 'gray')
      buf.create_tag('silver', 'foreground' =>   '#C0C0C0')
      buf.create_tag('mono', 'family' => 'monospace', 'background' => '#EFEFEF')
      buf.create_tag('sup', 'rise' => 7 * Pango::SCALE, 'size' => 9 * Pango::SCALE)
      buf.create_tag('sub', 'rise' => -7 * Pango::SCALE, 'size' => 9 * Pango::SCALE)
      buf.create_tag('small', 'scale' => Pango::AttrScale::XX_SMALL)
      buf.create_tag('large', 'scale' => Pango::AttrScale::X_LARGE)
      buf.create_tag('quote', 'left_margin' => 20, 'background' => '#EFEFEF', \
        'style' => Pango::FontDescription::STYLE_ITALIC)

      signal_connect('key-press-event') do |widget, event|
        res = false
        case event.keyval
          when Gdk::Keyval::GDK_b, Gdk::Keyval::GDK_B, 1737, 1769
            if event.state.control_mask?
              set_tag('bold')
              res = true
            end
          when Gdk::Keyval::GDK_i, Gdk::Keyval::GDK_I, 1755, 1787
            if event.state.control_mask?
              set_tag('italic')
              res = true
            end
          when Gdk::Keyval::GDK_u, Gdk::Keyval::GDK_U, 1735, 1767
            if event.state.control_mask?
              set_tag('undline')
              res = true
            end
          when Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter
            if event.state.control_mask?
              res = true
            end
        end
        res
      end

      set_border_window_size(Gtk::TextView::WINDOW_LEFT, left_border) if left_border

      signal_connect('event-after') do |tv, event|
        if event.kind_of?(Gdk::EventButton) \
        and (event.event_type == Gdk::Event::BUTTON_PRESS) and (event.button == 1)
          buf = tv.buffer
          # we shouldn't follow a link if the user has selected something
          range = buf.selection_bounds
          if range and (range[0].offset == range[1].offset)
            x, y = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, \
              event.x, event.y)
            iter = tv.get_iter_at_location(x, y)
            follow_if_link(iter)
          end
        end
        false
      end

      signal_connect('motion-notify-event') do |tv, event|
        x, y = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, \
          event.x, event.y)
        set_cursor_if_appropriate(tv, x, y)
        tv.window.pointer
        false
      end

      signal_connect('visibility-notify-event') do |tv, event|
        window, wx, wy = tv.window.pointer
        bx, by = tv.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, wx, wy)
        set_cursor_if_appropriate(tv, bx, by)
        false
      end

      self.has_tooltip = true
      signal_connect('query-tooltip') do |textview, x, y, keyboard_tip, tooltip|
        res = false
        iter = nil
        if keyboard_tip
          iter = textview.buffer.get_iter_at_offset(textview.buffer.cursor_position)
        else
          bx, by = textview.window_to_buffer_coords(Gtk::TextView::WINDOW_TEXT, x, y)
          iter, trailing = textview.get_iter_at_position(bx, by)
        end
        pixbuf = iter.pixbuf   #.has_tag?(tag)  .char = 0xFFFC
        if pixbuf
          alt = pixbuf.tooltip
          if (alt.is_a? String) and (alt.size>0)
            tooltip.text = alt if not textview.destroyed?
            res = true
          end
        else
          tags = iter.tags
          link_tag = tags.find { |tag| (tag.is_a? LinkTag) }
          if link_tag
            tooltip.text = link_tag.link if not textview.destroyed?
            res = true
          end
        end
        res
      end
    end

    def scrollwin
      res = self.parent
      res = res.parent if not res.is_a? Gtk::ScrolledWindow
      res
    end

    def set_cursor_if_appropriate(tv, x, y)
      iter = tv.get_iter_at_location(x, y)
      hovering = false
      tags = iter.tags
      tags.each do |tag|
        if tag.is_a? LinkTag
          hovering = true
          break
        end
      end
      if hovering != @hovering
        @hovering = hovering
        window = tv.get_window(Gtk::TextView::WINDOW_TEXT)
        if @hovering
          window.cursor = @hand_cursor
        else
          window.cursor = @regular_cursor
        end
      end
    end

    def follow_if_link(iter)
      tags = iter.tags
      tags.each do |tag|
        if tag.is_a? LinkTag
          link = tag.link
          if (link.is_a? String) and (link.size>0)
            res = PandoraUtils.parse_url(link, 'http')
            if res
              proto, obj_type, way = res
              if (proto == 'pandora') or (proto == 'sha1') or (proto == 'md5')
                #PandoraGtk.internal_open(proto, obj_type, way)
              else
                url = way
                url = proto+'://'+way if proto and proto=='http'
                puts 'Go to link: ['+url+']'
                PandoraUtils.external_open(url)
              end
            end
          end
        end
      end
    end

    def get_lines(tv, first_y, last_y, y_coords, numbers, with_height=false)
      # Get iter at first y
      iter, top = tv.get_line_at_y(first_y)
      # For each iter, get its location and add it to the arrays.
      # Stop when we pass last_y
      line = iter.line
      count = 0
      size = 0
      while (line < tv.buffer.line_count)
        #iter = tv.buffer.get_iter_at_line(line)
        y, height = tv.get_line_yrange(iter)
        if with_height
          y_coords << [y, height]
        else
          y_coords << y
        end
        line += 1
        numbers << line
        count += 1
        break if (y + height) >= last_y
        iter.forward_line
      end
      count
    end

    BBCODES = ['B', 'I', 'U', 'S', 'EM', 'STRIKE', 'STRONG', 'D', 'BR', \
      'FONT', 'SIZE', 'COLOR', 'COLOUR', 'STYLE', 'BACK', 'BACKGROUND', 'BG', \
      'FORE', 'FOREGROUND', 'FG', 'SPAN', 'DIV', 'P', \
      'RED', 'GREEN', 'BLUE', 'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', \
      'LIME', 'AQUA', 'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER', \
      'URL', 'A', 'HREF', 'LINK', 'ANCHOR', 'QUOTE', 'BLOCKQUOTE', 'LIST', \
      'CUT', 'SPOILER', 'CODE', 'INLINE', \
      'BOX', 'PROPERTY', 'EDIT', 'ENTRY', 'INPUT', \
      'BUTTON', 'SPIN', 'INTEGER', 'HEX', 'REAL', 'FLOAT', 'DATE', \
      'TIME', 'DATETIME', 'COORD', 'FILENAME', 'BASE64', 'PANHASH', 'BYTELIST', \
      'PRE', 'SOURCE', 'MONO', 'MONOSPACE', \
      'IMG', 'IMAGE', 'SMILE', 'EMOT', 'VIDEO', 'AUDIO', 'FILE', 'SUB', 'SUP', \
      'ABBR', 'ACRONYM', 'HR', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', \
      'LEFT', 'CENTER', 'RIGHT', 'FILL', 'IMAGES', 'SLIDE', 'SLIDESHOW', \
      'TABLE', 'TR', 'TD', 'TH', \
      'SMALL', 'LITTLE', 'X-SMALL', 'XX-SMALL', 'LARGE', 'BIG', 'X-LARGE', 'XX-LARGE']

    # Insert taget string to buffer
    # RU: Вставить тегированный текст в буфер
    def insert_taged_str_to_buffer(str, dest_buf, aformat=nil)

      def shift_coms(shift)
        @open_coms.each do |ocf|
          ocf[1] += shift
        end
      end

      def remove_quotes(str)
        if str.is_a?(String) and (str.size>1) \
        and ((str[0]=='"' and str[-1]=='"') or (str[0]=="'" and str[-1]=="'"))
          str = str[1..-2]
          str.strip! if str
        end
        str
      end

      def get_tag_param(params, type=:string, retutn_tail=false)
        res = nil
        getted = nil
        if (params.is_a? String) and (params.size>0)
          ei = params.index('=')
          es = params.index(' ')
          if ei.nil? or (es and es<ei)
            res = params
            res = params[0, es] if ei
            if res
              getted = res.size
              res = res.strip
              res = remove_quotes(res)
              if res and (type==:number)
                begin
                  res.gsub!(/[^0-9\.]/, '')
                  res = res.to_i
                rescue
                  res = nil
                end
              end
            end
          end
        end
        if retutn_tail
          tail = nil
          if getted
            tail = params[getted..-1]
          else
            tail = params
          end
          res = [res, tail]
        end
        res
      end

      def detect_params(params, tagtype=:string)
        res = {}
        tag, params = get_tag_param(params, tagtype, true)
        res['tag'] = tag if tag
        while (params.is_a? String) and (params.size>0)
          params.strip
          n = nil
          v = nil
          i = params.index('=')
          if i and (i>0)
            n = params[0, i]
            params = params[i+1..-1]
            params.strip if params
            i = params.size
            j = params.index(' ')
            k = params.index('"', 1)
            if (i>0) and (params[0]=='"') and k
              v = params[0..k]
              params = params[k+1..-1]
            elsif j
              v = params[0, j]
              params = params[j+1..-1]
            else
              v = params
              params = ''
            end
          else
            params = ''
          end
          if n
            n = n.strip.downcase
            res[n] = remove_quotes(v.strip) if v and (v.size>0)
          end
        end
        p 'detect_params[params, res]='+[params, res].inspect
        res
      end

      def correct_color(str)
        if str.is_a?(String) and (str.size==6) and PandoraUtils.hex?(str)
          str = '#'+str
        end
        str
      end

      i = children.size
      while i>0
        i -= 1
        child = children[i]
        child.destroy if child and (not child.destroyed?)
      end

      aformat ||= 'auto'
      unless ['markdown', 'bbcode', 'html', 'ruby', 'plain'].include?(aformat)
        aformat = 'bbcode' #if aformat=='auto' #need autodetect here
      end
      #p 'str='+str
      case aformat
        when 'markdown'
          i = 0
          while i<str.size
            j = str.index('*')
            if j
              dest_buf.insert(dest_buf.end_iter, str[0, j])
              str = str[j+1..-1]
              j = str.index('*')
              if j
                tag_name = str[0..j-1]
                img_buf = $window.get_icon_buf(tag_name)
                dest_buf.insert(dest_buf.end_iter, img_buf) if img_buf
                str = str[j+1..-1]
              end
            else
              dest_buf.insert(dest_buf.end_iter, str)
              i = str.size
            end
          end
        when 'bbcode', 'html'
          open_coms = Array.new
          @open_coms = open_coms
          open_brek = '['
          close_brek = ']'
          if aformat=='html'
            open_brek = '<'
            close_brek = '>'
          end
          strict_close_tag = nil
          i1 = nil
          i = 0
          ss = str.size
          while i<ss
            c = str[i]
            if c==open_brek
              i1 = i
              i += 1
            elsif i1 and (c==close_brek)
              com = str[i1+1, i-i1-1]
              p 'bbcode com='+com
              if com and (com.size>0)
                comu = nil
                close = (com[0] == '/')
                show_text = true
                if close or (com[-1] == '/')
                  # -- close bbcode
                  params = nil
                  tv_tag = nil
                  if close
                    comu = com[1..-1]
                  else
                    com = com[0..-2]
                    j = 0
                    cs = com.size
                    j +=1 while (j<cs) and (not ' ='.index(com[j]))
                    comu = nil
                    params = nil
                    if (j<cs)
                      params = com[j+1..-1].strip
                      comu = com[0, j]
                    else
                      comu = com
                    end
                  end
                  comu = comu.strip.upcase if comu
                  p '===closetag  [comu,params]='+[comu,params].inspect
                  p1 = dest_buf.end_iter.offset
                  p2 = p1
                  if ((strict_close_tag.nil? and BBCODES.include?(comu)) \
                  or ((not strict_close_tag.nil?) and (comu==strict_close_tag)))
                    strict_close_tag = nil
                    k = open_coms.index{ |ocf| ocf[0]==comu }
                    if k or (not close)
                      if k
                        rec = open_coms[k]
                        open_coms.delete_at(k)
                        k = rec[1]
                        params = rec[2]
                      else
                        k = 0
                      end
                      #p '[comu, dest_buf.text]='+[comu, dest_buf.text].inspect
                      p p1 -= k
                      case comu
                        when 'B', 'STRONG'
                          tv_tag = 'bold'
                        when 'I', 'EM'
                          tv_tag = 'italic'
                        when 'S', 'STRIKE'
                          tv_tag = 'strike'
                        when 'U'
                          tv_tag = 'undline'
                        when 'D'
                          tv_tag = 'dundline'
                        when 'BR', 'P'
                          dest_buf.insert(dest_buf.end_iter, "\n")
                          shift_coms(1)
                        when 'URL', 'A', 'HREF', 'LINK'
                          tv_tag = 'link'
                          #insert_link(buffer, iter, 'Go back', 1)
                          params = str[0, i1] unless params and (params.size>0)
                          params = get_tag_param(params) if params and (params.size>0)
                          if params and (params.size>0)
                            trunc_md5 = Digest::MD5.digest(params)[0, 10]
                            link_id = 'link'+PandoraUtils.bytes_to_hex(trunc_md5)
                            link_tag = dest_buf.tag_table.lookup(link_id)
                            #p '--[link_id, link_tag, params]='+[link_id, link_tag, params].inspect
                            if link_tag
                              tv_tag = link_tag.name
                            else
                              link_tag = LinkTag.new(link_id)
                              if link_tag
                                dest_buf.tag_table.add(link_tag)
                                link_tag.foreground = 'blue'
                                link_tag.underline = Pango::AttrUnderline::SINGLE
                                link_tag.link = params
                                tv_tag = link_id
                              end
                            end
                          end
                        when 'ANCHOR'
                          tv_tag = nil
                        when 'QUOTE', 'BLOCKQUOTE'
                          tv_tag = 'quote'
                        when 'LIST'
                          tv_tag = 'quote'
                        when 'CUT', 'SPOILER'
                          capt = params
                          capt ||= _('Expand')
                          expander = Gtk::Expander.new(capt)
                          etv = Gtk::TextView.new
                          etv.buffer.text = str[0, i1]
                          show_text = false
                          expander.add(etv)
                          iter = dest_buf.end_iter
                          anchor = dest_buf.create_child_anchor(iter)
                          #p 'CUT [body_child, expander, anchor]='+
                          #  [body_child, expander, anchor].inspect
                          add_child_at_anchor(expander, anchor)
                          shift_coms(1)
                          expander.show_all
                        when 'CODE', 'INLINE', 'PRE', 'SOURCE', 'MONO', 'MONOSPACE'
                          tv_tag = 'mono'
                        when 'IMG', 'IMAGE', 'SMILE', 'EMOT'
                          params = str[0, i1] unless params and (params.size>0)
                          p 'IMG params='+params.inspect
                          params = get_tag_param(params) if params and (params.size>0)
                          if params and (params.size>0)
                            img_buf = $window.get_icon_buf(params)
                            if img_buf
                              show_text = false
                              dest_buf.insert(dest_buf.end_iter, img_buf)
                              shift_coms(1)
                            end
                          end
                        when 'IMAGES', 'SLIDE', 'SLIDESHOW'
                          tv_tag = nil
                        when 'VIDEO', 'AUDIO', 'FILE', 'IMAGES', 'SLIDE', 'SLIDESHOW'
                          tv_tag = nil
                        when 'ABBR', 'ACRONYM'
                          tv_tag = nil
                        when 'HR'
                          count = get_tag_param(params, :number)
                          count = 50 unless count.is_a? Numeric and (count>0)
                          dest_buf.insert(dest_buf.end_iter, ' '*count)
                          shift_coms(count)
                          p2 += count
                          tv_tag = 'undline'
                        when 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'LEFT', 'CENTER', \
                        'RIGHT', 'FILL', 'SUB', 'SUP', 'RED', 'GREEN', 'BLUE', \
                        'NAVY', 'YELLOW', 'MAGENTA', 'CYAN', 'LIME', 'AQUA', \
                        'MAROON', 'OLIVE', 'PURPLE', 'TEAL', 'GRAY', 'SILVER'
                          comu = 'CYAN' if comu=='AQUA'
                          tv_tag = comu.downcase
                        when 'FONT', 'STYLE', 'SIZE', \
                          'FG', 'FORE', 'FOREGROUND', 'COLOR', 'COLOUR', \
                          'BG', 'BACK', 'BACKGROUND'

                          fg = nil
                          bg = nil
                          sz = nil
                          js = nil #left, right...
                          fam = nil
                          wt = nil #bold
                          st = nil #italic...

                          case comu
                            when 'FG', 'FORE', 'FOREGROUND', 'COLOR', 'COLOUR'
                              fg = get_tag_param(params)
                            when 'BG', 'BACK', 'BACKGROUND'
                              bg = get_tag_param(params)
                            else
                              sz = get_tag_param(params, :number)
                              if not sz
                                param_hash = detect_params(params)
                                sz = param_hash['size']
                                sz ||= param_hash['sz']
                                fg = param_hash['color']
                                fg ||= param_hash['colour']
                                fg ||= param_hash['fg']
                                fg ||= param_hash['fore']
                                fg ||= param_hash['foreground']
                                bg = param_hash['bg']
                                bg ||= param_hash['back']
                                bg ||= param_hash['background']
                                js = param_hash['js']
                                js ||= param_hash['justify']
                                js ||= param_hash['justification']
                                js ||= param_hash['align']
                                fam = param_hash['fam']
                                fam ||= param_hash['family']
                                fam ||= param_hash['font']
                                fam ||= param_hash['name']
                                wt = param_hash['wt']
                                wt ||= param_hash['weight']
                                wt ||= param_hash['bold']
                                st = param_hash['st']
                                st ||= param_hash['style']
                                st ||= param_hash['italic']
                              end
                            #end-case-when
                          end

                          fg = correct_color(fg)
                          bg = correct_color(bg)

                          tag_params = {}

                          tag_name = 'font'
                          if fam and (fam.is_a? String) and (fam.size>0)
                            fam_st = fam.upcase
                            fam_st.gsub!(' ', '_')
                            tag_name << '_'+fam_st
                            tag_params['family'] = fam
                          end
                          if fg
                            tag_name << '_'+fg
                            tag_params['foreground'] = fg
                          end
                          if bg
                            tag_name << '_bg'+bg
                            tag_params['background'] = bg
                          end
                          if sz
                            sz.gsub!(/[^0-9\.]/, '') if sz.is_a? String
                            tag_name << '_sz'+sz.to_s
                            tag_params['size'] = sz.to_i * Pango::SCALE
                          end
                          if wt
                            tag_name << '_wt'+wt.to_s
                            tag_params['weight'] = wt.to_i
                          end
                          if st
                            tag_name << '_st'+st.to_s
                            tag_params['style'] = st.to_i
                          end
                          if js
                            js = js.upcase
                            jsv = nil
                            if js=='LEFT'
                              jsv = Gtk::JUSTIFY_LEFT
                            elsif js=='RIGHT'
                              jsv = Gtk::JUSTIFY_RIGHT
                            elsif js=='CENTER'
                              jsv = Gtk::JUSTIFY_CENTER
                            elsif js=='FILL'
                              jsv = Gtk::JUSTIFY_FILL
                            end
                            if jsv
                              tag_name << '_js'+js
                              tag_params['justification'] = jsv
                            end
                          end

                          text_tag = dest_buf.tag_table.lookup(tag_name)
                          p '[tag_name, tag_params]='+[tag_name, tag_params].inspect
                          if text_tag
                            tv_tag = text_tag.name
                          elsif tag_params.size != {}
                            if dest_buf.create_tag(tag_name, tag_params)
                              tv_tag = tag_name
                            end
                          end
                        when 'SPAN', 'DIV',
                          tv_tag = 'mono'
                        when 'TABLE', 'TR', 'TD', 'TH'
                          tv_tag = 'mono'
                        when 'SMALL', 'LITTLE', 'X-SMALL', 'XX-SMALL'
                          tv_tag = 'small'
                        when 'LARGE', 'BIG', 'X-LARGE', 'XX-LARGE'
                          tv_tag = 'large'
                        #end-case-when
                      end
                    else
                      comu = nil
                    end
                  else
                    p 'NO process'
                    comu = nil
                  end
                  if show_text
                    dest_buf.insert(dest_buf.end_iter, str[0, i1])
                    shift_coms(i1)
                    p2 += i1
                  end
                  if tv_tag
                    p 'apply_tag [tv_tag,p1,p2]='+[tv_tag,p1,p2].inspect
                    dest_buf.apply_tag(tv_tag, \
                      dest_buf.get_iter_at_offset(p1), \
                      dest_buf.get_iter_at_offset(p2))
                  end
                else
                  # -- open bbcode
                  dest_buf.insert(dest_buf.end_iter, str[0, i1])
                  shift_coms(i1)
                  j = 0
                  cs = com.size
                  j +=1 while (j<cs) and (not ' ='.index(com[j]))
                  comu = nil
                  params = nil
                  if (j<cs)
                    params = com[j+1..-1].strip
                    comu = com[0, j]
                  else
                    comu = com
                  end
                  comu = comu.strip.upcase
                  p '---opentag  [comu,params]='+[comu,params].inspect
                  if strict_close_tag.nil? and BBCODES.include?(comu)
                    k = open_coms.find{ |ocf| ocf[0]==comu }
                    p 'opentag k='+k.inspect
                    if k
                      comu = nil
                    else
                      strict_close_tag = comu if comu=='CODE'
                      case comu
                        when 'BR', 'P'
                          dest_buf.insert(dest_buf.end_iter, "\n")
                          shift_coms(1)
                        when 'HR'
                          p1 = dest_buf.end_iter.offset
                          count = get_tag_param(params, :number)
                          count = 50 if not (count.is_a? Numeric and (count>0))
                          dest_buf.insert(dest_buf.end_iter, ' '*count)
                          shift_coms(count)
                          dest_buf.apply_tag('undline',
                            dest_buf.get_iter_at_offset(p1), dest_buf.end_iter)
                        else
                          if params and (params.size>0)
                            case comu
                              when 'IMG', 'IMAGE', 'EMOT', 'SMILE'
                                def_proto = nil
                                def_proto = 'smile' if (comu=='EMOT') or (comu=='SMILE')
                                comu = nil
                                param_hash = detect_params(params)
                                #src = get_tag_param(params)
                                src = param_hash['tag']
                                src ||= param_hash['src']
                                src ||= param_hash['link']
                                src ||= param_hash['url']
                                alt = param_hash['alt']
                                alt ||= param_hash['tooltip']
                                alt ||= param_hash['popup']
                                alt ||= param_hash['name']
                                title = param_hash['title']
                                title ||= param_hash['caption']
                                title ||= param_hash['name']
                                pixbuf = PandoraModel.get_image_from_url(src, \
                                  true, self, def_proto)
                                if pixbuf
                                  iter = dest_buf.end_iter
                                  if pixbuf.is_a? Gdk::Pixbuf
                                    alt ||= src
                                    PandoraUtils.set_obj_property(pixbuf, 'tooltip', alt)
                                    dest_buf.insert(iter, pixbuf)
                                    #anchor = dest_buf.create_child_anchor(iter)
                                    #img = Gtk::Image.new(img_res)
                                    #body_child.add_child_at_anchor(img, anchor)
                                    #img.show_all
                                    shift_coms(1)
                                    show_text = false
                                    if (title.is_a? String) and (title.size>0)
                                      title = "\n" + title
                                      dest_buf.insert(dest_buf.end_iter, title, 'italic')
                                      shift_coms(title.size)
                                    end
                                  else
                                    errtxt ||= _('Unknown error')
                                    dest_buf.insert(iter, errtxt)
                                    shift_coms(errtxt.size)
                                  end
                                  #anchor = dest_buf.create_child_anchor(iter)
                                  #p 'IMG [wid, anchor]='+[wid, anchor].inspect
                                  #body_child.add_child_at_anchor(wid, anchor)
                                  #wid.show_all
                                end
                              when 'BOX', 'PROPERTY', 'EDIT', 'ENTRY', 'INPUT', \
                              'SPIN', 'INTEGER', 'HEX', 'REAL', 'FLOAT', 'DATE', \
                              'TIME', 'DATETIME', 'COORD', 'FILENAME', 'BASE64', \
                              'PANHASH', 'BYTELIST', 'BUTTON'
                                #p '--BOX['+comu+'] param_hash='+param_hash.inspect
                                param_hash = detect_params(params)
                                name = param_hash['tag']
                                name ||= param_hash['name']
                                name ||= _('Noname')
                                width = param_hash['width']
                                size = param_hash['size']
                                values = param_hash['values']
                                values ||= param_hash['value']
                                values = values.split(',') if values
                                default = param_hash['default']
                                default ||= values[0] if values
                                values ||= default
                                type = param_hash['type']
                                kind = param_hash['kind']
                                type ||= comu
                                comu = nil
                                show_text = false
                                type.upcase!
                                if (type=='ENTRY') or (type=='INPUT')
                                  type = 'EDIT'
                                elsif (type=='FLOAT')
                                  type = 'REAL'
                                elsif (type=='DATETIME')
                                  type = 'TIME'
                                elsif not ['EDIT', 'SPIN', 'INTEGER', 'HEX', 'REAL', \
                                'DATE', 'TIME', 'COORD', 'FILENAME', 'BASE64', \
                                'PANHASH', 'BUTTON', 'LIST'].include?(type)
                                  type = 'LIST'
                                end

                                dest_buf.insert(dest_buf.end_iter, name, 'bold')
                                dest_buf.insert(dest_buf.end_iter, ': ')
                                shift_coms(name.size+2)

                                widget = nil
                                if type=='EDIT'
                                  widget = Gtk::Entry.new
                                  widget.text = default if default
                                elsif type=='SPIN'
                                  if values
                                    values.sort!
                                    min = values[0]
                                    max = values[-1]
                                  else
                                    min = 0.0
                                    max = 100.0
                                  end
                                  default ||= 0.0
                                  widget = Gtk::SpinButton.new(min.to_f, max.to_f, 1.0)
                                  widget.value = default.to_f
                                elsif type=='INTEGER'
                                  widget = IntegerEntry.new
                                  widget.text = default if default
                                elsif type=='HEX'
                                  widget = HexEntry.new
                                  widget.text = default if default
                                elsif type=='REAL'
                                  widget = FloatEntry.new
                                  widget.text = default if default
                                elsif type=='TIME'
                                  widget = DateTimeBox.new
                                  if default
                                    if default.downcase=='current'
                                      default = PandoraUtils.time_to_dialog_str(Time.now)
                                    end
                                    widget.text = default
                                  end
                                elsif type=='DATE'
                                  widget = DateEntry.new
                                  if default
                                    if default.downcase=='current'
                                      default = PandoraUtils.date_to_str(Time.now)
                                    end
                                    widget.text = default
                                  end
                                elsif type=='COORD'
                                  widget = CoordBox.new
                                  widget.text = default if default
                                elsif type=='FILENAME'
                                  widget = FilenameBox.new(window)
                                  widget.text = default if default
                                elsif type=='BASE64'
                                  widget = Base64Entry.new
                                  widget.text = default if default
                                elsif type=='PANHASH'
                                  kind ||= 'Blob,Person,Community,City'
                                  widget = PanhashBox.new('Panhash('+kind+')')
                                  widget.text = default if default
                                elsif type=='LIST'
                                  widget = ByteListEntry.new(PandoraModel::RelationNames)
                                  widget.text = default if default
                                else #'BUTTON'
                                  default ||= name
                                  widget = Gtk::Button.new(_(default))
                                end
                                if width or size
                                  width = width.to_i if width
                                  width ||= PandoraGtk.num_char_width*size.to_i+8
                                  if widget.is_a? Gtk::Widget
                                    widget.width_request = width
                                  elsif widget.is_a? PandoraGtk::BtnEntry
                                    widget.entry.width_request = width
                                  end
                                end
                                iter = dest_buf.end_iter
                                anchor = dest_buf.create_child_anchor(iter)
                                add_child_at_anchor(widget, anchor)
                                shift_coms(1)
                                widget.show_all
                              #end-case-when
                            end
                          end
                          open_coms << [comu, 0, params] if comu
                        #end-case-when
                      end
                    end
                  else
                    comu = nil
                  end
                end
                if (not comu) and show_text
                  dest_buf.insert(dest_buf.end_iter, open_brek+com+close_brek)
                  shift_coms(com.size+2)
                end
              else
                dest_buf.insert(dest_buf.end_iter, str[0, i1])
                shift_coms(i1)
              end
              str = str[i+1..-1]
              i = 0
              ss = str.size
              i1 = nil
            else
              i += 1
            end
          end
          dest_buf.insert(dest_buf.end_iter, str)
        else
          dest_buf.text = str
        #end-case-when
      end
    end

    def set_tag(tag, params=nil, defval=nil, aformat=nil)
      bounds = buffer.selection_bounds
      ltext = rtext = ''
      aformat ||= format
      case aformat
        when 'bbcode', 'html'
          noclose = (tag and (tag[-1]=='/'))
          tag = tag[0..-2] if noclose
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
            else
              t = tag
            #end-case-when
          end
          open_brek = '['
          close_brek = ']'
          if aformat=='html'
            open_brek = '<'
            close_brek = '>'
          end
          if params.is_a? String
            params = '='+params
          elsif params.is_a? Hash
            all = ''
            params.each do |k,v|
              all << ' '
              all << k.to_s + '="' + v.to_s + '"'
            end
            params = all
          else
            params = ''
          end
          ltext = open_brek+t+params+close_brek
          rtext = open_brek+'/'+t+close_brek if not noclose
        when 'markdown'
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
      if (lpos==rpos) and (defval.is_a? String)
        buffer.insert(buffer.get_iter_at_offset(lpos), defval)
        rpos += defval.size
      end
      if ltext != ''
        buffer.insert(buffer.get_iter_at_offset(lpos), ltext)
        lpos += ltext.length
        rpos += ltext.length
      end
      if rtext != ''
        buffer.insert(buffer.get_iter_at_offset(rpos), rtext)
      end
      buffer.move_mark('selection_bound', buffer.get_iter_at_offset(lpos))
      buffer.move_mark('insert', buffer.get_iter_at_offset(rpos))
    end

  end

  # Editor TextView
  # RU: TextView редактора
  class EditorTextView < SuperTextView
    attr_accessor :view_border, :raw_border

    def set_left_border_width(left_border=nil)
      if (not left_border) or (left_border<0)
        add_nums = 0
        add_nums = -left_border if left_border and (left_border<0)
        num_count = nil
        line_count = buffer.line_count
        num_count = (Math.log10(line_count).truncate+1) if line_count
        num_count = 1 if (num_count.nil? or (num_count<1))
        if add_nums>0
          if (num_count+add_nums)>5
            num_count += 1
          else
            num_count += add_nums
          end
        end
        left_border = PandoraGtk.num_char_width*num_count+8
      end
      set_border_window_size(Gtk::TextView::WINDOW_LEFT, left_border)
    end

    def initialize(aview_border=nil, araw_border=nil)
      @view_border = aview_border
      @raw_border = araw_border
      super(aview_border)
      $font_desc ||= Pango::FontDescription.new('Monospace 11')
      signal_connect('expose-event') do |widget, event|
        tv = widget
        type = nil
        event_win = nil
        begin
          left_win = tv.get_window(Gtk::TextView::WINDOW_LEFT)
          #right_win = tv.get_window(Gtk::TextView::WINDOW_RIGHT)
          event_win = event.window
        rescue Exception
          event_win = nil
        end
        if event_win and left_win and (event_win == left_win)
          type = Gtk::TextView::WINDOW_LEFT
          target = left_win
          sw = tv.scrollwin
          view_mode = true
          view_mode = sw.view_mode if sw and (sw.is_a? BodyScrolledWindow)
          if not view_mode
            first_y = event.area.y
            last_y = first_y + event.area.height
            x, first_y = tv.window_to_buffer_coords(type, 0, first_y)
            x, last_y = tv.window_to_buffer_coords(type, 0, last_y)
            numbers = []
            pixels = []
            count = get_lines(tv, first_y, last_y, pixels, numbers)
            # Draw fully internationalized numbers!
            layout = widget.create_pango_layout
            count.times do |i|
              x, pos = tv.buffer_to_window_coords(type, 0, pixels[i])
              str = numbers[i].to_s
              layout.text = str
              widget.style.paint_layout(target, widget.state, false,
                nil, widget, nil, 2, pos, layout)
            end
          end
        end
        false
      end
    end
  end

  class ChatTextView < SuperTextView
    attr_accessor :mes_ids, :numbers, :pixels

    def initialize(*args)
      @@save_buf ||= $window.get_icon_scale_buf('save', 'pan', 14)
      @@gogo_buf ||= $window.get_icon_scale_buf('gogo', 'pan', 14)
      @@recv_buf ||= $window.get_icon_scale_buf('recv', 'pan', 14)
      @@crypt_buf ||= $window.get_icon_scale_buf('crypt', 'pan', 14)
      @@sign_buf ||= $window.get_icon_scale_buf('sign', 'pan', 14)
      #@@nosign_buf ||= $window.get_icon_scale_buf('nosign', 'pan', 14)
      @@fail_buf ||= $window.get_preset_icon(Gtk::Stock::DIALOG_WARNING, nil, 14)

      super(*args)
      @mes_ids = Array.new
      @numbers = Array.new
      @pixels = Array.new
      @mes_model = PandoraUtils.get_model('Message')
      @sign_model = PandoraUtils.get_model('Sign')

      signal_connect('expose-event') do |widget, event|
        type = nil
        event_win = nil
        begin
          left_win = widget.get_window(Gtk::TextView::WINDOW_LEFT)
          event_win = event.window
        rescue Exception
          event_win = nil
        end
        if event_win and left_win and (event_win == left_win)
          type = Gtk::TextView::WINDOW_LEFT
          first_y = event.area.y
          last_y = first_y + event.area.height
          x, first_y = widget.window_to_buffer_coords(type, 0, first_y)
          x, last_y = widget.window_to_buffer_coords(type, 0, last_y)
          pixels.clear
          numbers.clear
          count = get_lines(widget, first_y, last_y, pixels, numbers, true)
          cr = left_win.create_cairo_context

          count.times do |i|
            y1, h1 = pixels[i]
            x, y = widget.buffer_to_window_coords(type, 0, y1)
            line = numbers[i]
            attr = 1
            id = mes_ids[line]
            if id
              flds = 'state, panstate, panhash'
              sel = @mes_model.select({:id=>id}, false, flds, nil, 1)
              if sel and (sel.size > 0)
                state = sel[0][0]
                panstate = sel[0][1]
                if state
                  if state==0
                    cr.set_source_pixbuf(@@save_buf, 0, y+h1-@@save_buf.height)
                    cr.paint
                  elsif state==1
                    cr.set_source_pixbuf(@@gogo_buf, 0, y+h1-@@gogo_buf.height)
                    cr.paint
                  elsif state==2
                    cr.set_source_pixbuf(@@recv_buf, 0, y+h1-@@recv_buf.height)
                    cr.paint
                  end
                end
                if panstate
                  if (panstate & PandoraModel::PSF_Crypted) > 0
                    cr.set_source_pixbuf(@@crypt_buf, 18, y+h1-@@crypt_buf.height)
                    cr.paint
                  end
                  if (panstate & PandoraModel::PSF_Verified) > 0
                    panhash = sel[0][2]
                    sel = @sign_model.select({:obj_hash=>panhash}, false, 'id', nil, 1)
                    if sel and (sel.size > 0)
                      cr.set_source_pixbuf(@@sign_buf, 35, y+h1-@@sign_buf.height)
                    else
                      cr.set_source_pixbuf(@@fail_buf, 35, y+h1-@@fail_buf.height)
                    end
                    cr.paint
                  end
                end
              end
            end
          end
        end
        false
      end
    end

    # Update status icon border if visible lines contain id or ids
    # RU: Обновляет бордюр с иконками статуса, если видимые строки содержат ids
    def update_lines_with_id(ids=nil, redraw_before=true)
      self.queue_draw if redraw_before
      need_redraw = nil
      if ids
        if ids.is_a? Array
          ids.each do |id|
            line = mes_ids.index(id)
            if line and numbers.include?(line)
              need_redraw = true
              break
            end
          end
        else
          line = mes_ids.index(ids)
          need_redraw = true if line and numbers.include?(line)
        end
      else
        need_redraw = true
      end
      if need_redraw
        left_win = self.get_window(Gtk::TextView::WINDOW_LEFT)
        left_win.invalidate(left_win.frame_extents, true)
      end
    end

  end

  # Trust change Scale
  # RU: Шкала для изменения доверия
  class TrustScale < ColorDayBox
    attr_accessor :scale

    def colorize
      if sensitive?
        val = scale.value
        trust = (val*127).round
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
        color = Gdk::Color.new(r, g, b)
        #scale.modify_fg(Gtk::STATE_NORMAL, color)
        self.bg = color
        prefix = ''
        prefix = _(@tooltip_prefix) + ': ' if @tooltip_prefix
        scale.tooltip_text = prefix+val.to_s
      else
        #modify_fg(Gtk::STATE_NORMAL, nil)
        self.bg = nil
        scale.tooltip_text = ''
      end
    end

    def initialize(bg=nil, tooltip_prefix=nil, avalue=nil)
      super(bg)
      @tooltip_prefix = tooltip_prefix
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0.0)
      @scale = Gtk::HScale.new(adjustment)
      scale.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
      scale.set_size_request(100, -1)
      scale.value_pos = Gtk::POS_RIGHT
      scale.digits = 1
      scale.draw_value = true
      scale.signal_connect('value-changed') do |widget|
        colorize
      end
      self.signal_connect('notify::sensitive') do |widget, param|
        colorize
      end
      scale.signal_connect('scroll-event') do |widget, event|
        res = (not (event.state.control_mask? or event.state.shift_mask?))
        if (event.direction==Gdk::EventScroll::UP) \
        or (event.direction==Gdk::EventScroll::LEFT)
          widget.value = (widget.value-0.1).round(1) if res
        else
          widget.value = (widget.value+0.1).round(1) if res
        end
        res
      end
      scale.value = avalue if avalue
      self.add(scale)
      colorize
    end
  end

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :image, :label, :stock

    def set_stock(astock)
      p @stock = astock
      #$window.register_stock(stock)
      an_image = $window.get_preset_image(stock, Gtk::IconSize::SMALL_TOOLBAR, nil)
      if (@image.is_a? Gtk::Image) and @image.icon_set
        @image.icon_set = an_image.icon_set
      else
        @image = an_image
      end
    end

    def initialize(an_image, title, child=nil, *args)
      args ||= [false, 0]
      super(*args)
      @image = an_image
      @image ||= :person
      if ((image.is_a? Symbol) or (image.is_a? String))
        set_stock(image)
      end
      @image.set_padding(2, 0)
      self.pack_start(image, false, false, 0) if image
      @label = Gtk::Label.new(title)
      self.pack_start(label, false, false, 0)
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
          self.destroy if not self.destroyed?
          child.destroy if not child.destroyed?
        end
        close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
        btn.add(close_image)
        align = Gtk::Alignment.new(1.0, 0.5, 0.0, 0.0)
        align.add(btn)
        self.pack_start(align, false, false, 0)
      end
      self.spacing = 3
      self.show_all
    end
  end

  # Window for view body (text or blob)
  # RU: Окно просмотра тела (текста или блоба)
  class BodyScrolledWindow < Gtk::ScrolledWindow
    include PandoraUtils

    attr_accessor :field, :link_name, :body_child, :format, :raw_buffer, :view_buffer, \
      :view_mode, :color_mode, :fields, :property_box, :toolbar, :edit_btn

    def parent_win
      res = parent.parent.parent
    end

    def get_fld_value_by_id(id)
      res = nil
      fld = fields.detect{ |f| (f[FI_Id].to_s == id) }
      res = fld[FI_Value] if fld.is_a? Array
      res
    end

    def fill_body
      if field
        link_name = field[FI_Widget].text
        link_name.chomp! if link_name
        link_name = PandoraUtils.absolute_path(link_name)
        bodywin = self
        bodywid = self.child
        if (not bodywid) or (link_name != bodywin.link_name)
          @last_sw = child
          if bodywid
            bodywid.destroy if (not bodywid.destroyed?)
            bodywid = nil
            #field[FI_Widget2] = nil
          end
          if link_name and (link_name != '')
            if File.exist?(link_name)
              ext = File.extname(link_name)
              ext_dc = ext.downcase
              if ext
                if (['.jpg','.gif','.png'].include? ext_dc)
                  scale = nil
                  #!!!img_width  = bodywin.parent.allocation.width-14
                  #!!!img_height = bodywin.parent.allocation.height
                  img_width  = bodywin.allocation.width-14
                  img_height = bodywin.allocation.height
                  image = PandoraGtk.start_image_loading(link_name, nil, scale)
                    #img_width, img_height)
                  bodywid = image
                  bodywin.link_name = link_name
                elsif (['.txt','.rb','.xml','.py','.csv','.sh'].include? ext_dc)
                  if ext_dc=='.rb'
                    @format = 'ruby'
                  end
                  p 'Read file: '+link_name
                  File.open(link_name, 'r') do |file|
                    field[FI_Value] = file.read
                  end
                else
                  ext = nil
                end
              end
              if not ext
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

          bodywid ||= PandoraGtk::EditorTextView.new(0, nil)

          if not bodywin.child
            if bodywid.is_a? PandoraGtk::SuperTextView
              begin
                bodywin.add(bodywid)
              rescue Exception
                bodywin.add_with_viewport(bodywid)
              end
            else
              bodywin.add_with_viewport(bodywid)
            end
            fmt = get_fld_value_by_id('type')
            bodywin.format = fmt.downcase if fmt.is_a? String
          end
          bodywin.body_child = bodywid
          if bodywid.is_a? Gtk::TextView
            bodywin.init_view_buf(bodywin.body_child.buffer)
            atext = field[FI_Value].to_s
            bodywin.init_raw_buf(atext)
            if atext and (atext.size==0)
              bodywin.view_mode = false
            end
            bodywin.set_buffers
            #toolbar.show
          else
            #toolbar2.show
          end
          bodywin.show_all
        end
      end
    end

    def initialize(aproperty_box, afields, *args)
      @@page_setup ||= nil
      super(*args)
      @property_box = aproperty_box
      @format = nil
      @view_mode = true
      @color_mode = true
      @fields = afields
    end

    def init_view_buf(buf)
      if (not @view_buffer) and buf
        @view_buffer = buf
      end
    end

    def init_raw_buf(text=nil)
      if (not @raw_buffer)
        buf ||= Gtk::TextBuffer.new
        @raw_buffer = buf
        buf.text = text if text
        buf.create_tag('string', {'foreground' => '#00f000'})
        buf.create_tag('symbol', {'foreground' => '#008020'})
        buf.create_tag('comment', {'foreground' => '#8080e0'})
        buf.create_tag('keyword', {'foreground' => '#ffffff', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('keyword2', {'foreground' => '#ffffff'})
        buf.create_tag('function', {'foreground' => '#f12111'})
        buf.create_tag('number', {'foreground' => '#f050e0'})
        buf.create_tag('hexadec', {'foreground' => '#e070e7'})
        buf.create_tag('constant', {'foreground' => '#60eedd'})
        buf.create_tag('big_constant', {'foreground' => '#d080e0'})
        buf.create_tag('identifer', {'foreground' => '#ffff33'})
        buf.create_tag('global', {'foreground' => '#ffa500'})
        buf.create_tag('instvar', {'foreground' => '#ff85a2'})
        buf.create_tag('classvar', {'foreground' => '#ff79ec'})
        buf.create_tag('operator', {'foreground' => '#ffffff'})
        buf.create_tag('class', {'foreground' => '#ff1100', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('module', {'foreground' => '#1111ff', \
          'weight' => Pango::FontDescription::WEIGHT_BOLD})
        buf.create_tag('regex', {'foreground' => '#105090'})

        buf.signal_connect('changed') do |buf|  #modified-changed
          mark = buf.get_mark('insert')
          iter = buf.get_iter_at_mark(mark)
          line1 = iter.line
          set_tags(buf, line1, line1, true)
          false
        end

        buf.signal_connect('insert-text') do |buf, iter, text, len|
          $view_buffer_off1 = iter.offset
          false
        end

        buf.signal_connect('paste-done') do |buf|
          if $view_buffer_off1
            line1 = buf.get_iter_at_offset($view_buffer_off1).line
            mark = buf.get_mark('insert')
            iter = buf.get_iter_at_mark(mark)
            line2 = iter.line
            $view_buffer_off1 = iter.offset
            set_tags(buf, line1, line2)
          end
          false
        end
      end
    end

    # Ruby key words
    # Ключевые слова Ruby
    RUBY_KEYWORDS = ('begin end module class def if then else elsif' \
      +' while unless do case when require yield rescue include').split
    RUBY_KEYWORDS2 = 'self nil true false not and or'.split

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def ruby_tag_line(str, index=0, mode=0)

      def ident_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) or (c == '_')
      end

      def capt_char?(c)
        ('A'..'Z').include?(c) or ('0'..'9').include?(c) or (c == '_')
      end

      def word_char?(c)
        ('a'..'z').include?(c) or ('A'..'Z').include?(c) \
        or ('0'..'9').include?(c) or (c == '_')
      end

      def oper_char?(c)
        ".+,-=*^%()<>&[]!?~{}|/\\".include?(c)
      end

      def rewind_ident(str, i, ss, pc, prev_kw=nil)

        def check_func(prev_kw, c, i, ss, str)
          if (prev_kw=='def') and (c.nil? or (c=='.'))
            if not c.nil?
              yield(:operator, i, i+1)
              i += 1
            end
            i1 = i
            i += 1 while (i<ss) and ident_char?(str[i])
            i += 1 if (i<ss) and ('=?!'.include?(str[i]))
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
              if ['TRUE', 'FALSE'].include?(str[i1, i2-i1])
                yield(:keyword2, i1, i2)
              else
                yield(:big_constant, i1, i2)
              end
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
            can_keyw = (((i1<=0) or " \t\n({}[]=|+&,".include?(str[i1-1])) \
              and ((i2>=ss) or " \t\n(){}[]=|+&,.".include?(str[i2])))
            s = str[i1, i2-i1]
            if can_keyw and RUBY_KEYWORDS.include?(s)
              yield(:keyword, i1, i2)
              kw = s
            elsif can_keyw and RUBY_KEYWORDS2.include?(s)
              yield(:keyword2, i1, i2)
              if (s=='self') and (prev_kw=='def')
                i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                  yield(tag, id1, id2)
                end
              end
            else
              i += 1 if (i<ss) and ('?!'.include?(str[i]))
              if prev_kw=='def'
                if (i<ss) and (str[i]=='.')
                  yield(:identifer, i1, i)
                  i = check_func(prev_kw, c, i, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                else
                  i = check_func(prev_kw, nil, i1, ss, str) do |tag, id1, id2|
                    yield(tag, id1, id2)
                  end
                end
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
        elsif (mode == 0) and (str[0,6] == '=begin')
          mode = 1
          yield(:comment, index, index + ss)
        elsif (mode != 1)
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
              elsif oper_char?(c) or ((pc==':') and (c==':'))
                i1 = i
                i1 -=1 if (i1>0) and (c==':')
                i += 1
                while (i<ss) and (oper_char?(str[i]) or (str[i]==':'))
                  i += 1
                end
                if i<ss
                  pc = ' '
                  c = str[i]
                end
                yield(:operator, index + i1, index + i)
              elsif ((c==':') or (c=='$')) and (i+1<ss) and (ident_char?(str[i+1]))
                i += 1
                pc = c
                i, kw2 = rewind_ident(str, i, ss, pc) do |tag, id1, id2|
                  yield(tag, index + id1, index + id2)
                end
                pc = ' '
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

    # Call a code block with the text
    # RU: Вызвать блок кода по тексту
    def bbcode_html_tag_line(str, index=0, mode=0, format='bbcode')
      open_brek = '['
      close_brek = ']'
      if format=='html'
        open_brek = '<'
        close_brek = '>'
      end
      d = 0
      ss = str.size
      while ss>0
        if mode>0
          # find close brek
          i = str.index(close_brek)
          #p 'close brek  [str,i,d]='+[str,i,d].inspect
          k = ss
          if i
            k = i
            yield(:operator, index + d + i , index + d + i + 1)
            i += 1
            mode = 0
          else
            i = ss
          end
          if k>0
            com = str[0, k]
            j = 0
            cs = com.size
            j +=1 while (j<cs) and (not ' ='.index(com[j]))
            comu = nil
            params = nil
            if (j<cs)
              params = com[j+1..-1].strip
              comu = com[0, j]
            else
              comu = com
            end
            if comu and (comu.size>0)
              if SuperTextView::BBCODES.include?(comu.upcase)
                yield(:big_constant, index + d, index + d + j)
              else
                yield(:constant, index + d, index + d + j)
              end
            end
            if j<cs
              yield(:comment, index + d + j + 1, index + d + k)
            end
          end
        else
          # find open brek
          i = str.index(open_brek)
          #p 'open brek  [str,i,d]='+[str,i,d].inspect
          if i
            yield(:operator, index + d + i , index + d + i + 1)
            i += 1
            mode = 1
            if (i<ss) and (str[i]=='/')
              yield(:operator, index + d + i, index + d + i+1)
              i += 1
              mode = 2
            end
          else
            i = ss
          end
        end
        d += i
        str = str[i..-1]
        ss = str.size
      end
      mode
    end

    # Set tags for line range of TextView
    # RU: Проставить теги для диапазона строк TextView
    def set_tags(buf, line1, line2, clean=nil)
      #p 'line1, line2, view_mode='+[line1, line2, view_mode].inspect
      if (not @view_mode) and @color_mode
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
            case @format
              when 'ruby'
                mode = ruby_tag_line(text, offset1, mode) do |tag, start, last|
                  buf.apply_tag(tag.to_s,
                    buf.get_iter_at_offset(start),
                    buf.get_iter_at_offset(last))
                end
              when 'bbcode', 'html'
                mode = bbcode_html_tag_line(text, offset1, mode, @format) do |tag, start, last|
                  buf.apply_tag(tag.to_s,
                    buf.get_iter_at_offset(start),
                    buf.get_iter_at_offset(last))
                end
              #end-case-when
            end
            #p mode
            iter1 = iterN if iterN
            #Gtk.main_iteration
          end
        end
      end
    end

    # Set buffers
    # RU: Задать буферы
    def set_buffers
      tv = body_child
      if tv and (tv.is_a? Gtk::TextView)
        tv.hide
        text_changed = false
        @format ||= 'auto'
        unless ['markdown', 'bbcode', 'html', 'ruby', 'plain'].include?(@format)
          @format = 'bbcode' #if aformat=='auto' #need autodetect here
        end
        @tv_style ||= tv.modifier_style
        if view_mode
          tv.modify_style(@tv_style)
          tv.modify_font(nil)
          tv.hide
          view_buffer.text = ''
          tv.buffer = view_buffer
          tv.insert_taged_str_to_buffer(raw_buffer.text, view_buffer, @format)
          tv.set_left_border_width(tv.view_border)
          tv.show
          tv.editable = false
        else
          tv.modify_font($font_desc)
          tv.modify_base(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          tv.modify_text(Gtk::STATE_NORMAL, Gdk::Color.parse('#ffff33'))
          tv.modify_cursor(Gdk::Color.parse('#ff1111'), Gdk::Color.parse('#ff1111'))
          tv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#A0A0A0'))
          tv.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#000000'))
          tv.hide
          #convert_buffer(view_buffer.text, raw_buffer, false, @format)
          tv.buffer = raw_buffer
          left_bord = tv.raw_border
          left_bord ||= -3
          tv.set_left_border_width(left_bord)
          tv.show
          tv.editable = true
          raw_buffer.remove_all_tags(raw_buffer.start_iter, raw_buffer.end_iter)
          set_tags(raw_buffer, 0, raw_buffer.line_count)
        end
        fmt_btn = property_box.format_btn
        fmt_btn.label = format if (fmt_btn and (fmt_btn.label != format))
        tv.show
        tv.grab_focus
      end
    end

    # Set tag for selection
    # RU: Задать тэг для выделенного
    def insert_tag(tag, params=nil, defval=nil)
      tv = body_child
      if tag and (tv.is_a? Gtk::TextView)
        edit_btn.active = true if edit_btn if view_mode
        tv.set_tag(tag, params, defval, format)
      end
    end

    Data = Struct.new(:font_size, :lines_per_page, :lines, :n_pages)
    HEADER_HEIGHT = 10 * 72 / 25.4
    HEADER_GAP = 3 * 72 / 25.4

    def set_page_setup
      if not @@page_setup
        @@page_setup = Gtk::PageSetup.new
        paper_size = Gtk::PaperSize.new(Gtk::PaperSize.default)
        @@page_setup.paper_size_and_default_margins = paper_size
      end
      @@page_setup = Gtk::PrintOperation::run_page_setup_dialog($window, @@page_setup)
    end

    def run_print_operation(preview=false)
      begin
        operation = Gtk::PrintOperation.new
        operation.default_page_setup = @@page_setup if @@page_setup

        operation.use_full_page = false
        operation.unit = Gtk::PaperSize::UNIT_POINTS
        operation.show_progress = true
        data = Data.new
        data.font_size = 12.0

        operation.signal_connect('begin-print') do |_operation, context|
          on_begin_print(_operation, context, data)
        end
        operation.signal_connect('draw-page') do |_operation, context, page_number|
          on_draw_page(_operation, context, page_number, data)
        end
        if preview
          operation.run(Gtk::PrintOperation::ACTION_PREVIEW, $window)
        else
          operation.run(Gtk::PrintOperation::ACTION_PRINT_DIALOG, $window)
        end
      rescue
        PandoraGtk::GoodMessageDialog.new($!.message).run_and_do
      end
    end

    def on_begin_print(operation, context, data)
      height = context.height - HEADER_HEIGHT - HEADER_GAP
      data.lines_per_page = (height / data.font_size).floor
      p '[context.height, height, HEADER_HEIGHT, HEADER_GAP, data.lines_per_page]='+\
        [context.height, height, HEADER_HEIGHT, HEADER_GAP, data.lines_per_page].inspect
      tv = body_child
      data.lines = nil
      data.lines = tv.buffer if (tv.is_a? Gtk::TextView)
      if data.lines
        data.n_pages = (data.lines.line_count - 1) / data.lines_per_page + 1
      else
        data.n_pages = 1
      end
      operation.set_n_pages(data.n_pages)
    end

    def on_draw_page(operation, context, page_number, data)
      cr = context.cairo_context
      draw_header(cr, operation, context, page_number, data)
      draw_body(cr, operation, context, page_number, data)
    end

    def draw_header(cr, operation, context, page_number, data)
      width = context.width
      cr.rectangle(0, 0, width, HEADER_HEIGHT)
      cr.set_source_rgb(0.8, 0.8, 0.8)
      cr.fill_preserve
      cr.set_source_rgb(0, 0, 0)
      cr.line_width = 1
      cr.stroke
      layout = context.create_pango_layout
      layout.font_description = 'sans 14'
      layout.text = 'Pandora Print'
      text_width, text_height = layout.pixel_size
      if (text_width > width)
        layout.width = width
        layout.ellipsize = :start
        text_width, text_height = layout.pixel_size
      end
      y = (HEADER_HEIGHT - text_height) / 2
      cr.move_to((width - text_width) / 2, y)
      cr.show_pango_layout(layout)
      layout.text = "#{page_number + 1}/#{data.n_pages}"
      layout.width = -1
      text_width, text_height = layout.pixel_size
      cr.move_to(width - text_width - 4, y)
      cr.show_pango_layout(layout)
    end

    def draw_body(cr, operation, context, page_number, data)
      bw = self
      tv = bw.body_child
      if (not (tv.is_a? Gtk::TextView)) or bw.view_mode
        cm = Gdk::Colormap.system
        width = context.width
        height = context.height
        min_width = width
        min_width = tv.allocation.width if tv.allocation.width < min_width
        min_height = height - (HEADER_HEIGHT + HEADER_GAP)
        min_height = tv.allocation.height if tv.allocation.height < min_height
        pixbuf = Gdk::Pixbuf.from_drawable(cm, tv.window, 0, 0, min_width, \
          min_height)
        cr.set_source_color(Gdk::Color.new(65535, 65535, 65535))
        cr.gdk_rectangle(Gdk::Rectangle.new(0, HEADER_HEIGHT + HEADER_GAP, \
          context.width, height - (HEADER_HEIGHT + HEADER_GAP)))
        cr.fill

        cr.set_source_pixbuf(pixbuf, 0, HEADER_HEIGHT + HEADER_GAP)
        cr.paint
      else
        layout = context.create_pango_layout
        description = Pango::FontDescription.new('monosapce')
        description.size = data.font_size * Pango::SCALE
        layout.font_description = description

        cr.move_to(0, HEADER_HEIGHT + HEADER_GAP)
        buf = data.lines
        start_line = page_number * data.lines_per_page
        line = start_line
        iter1 = buf.get_iter_at_line(line)
        iterN = nil
        buf.begin_user_action do
          while (line<buf.line_count) and (line<start_line+data.lines_per_page)
            line += 1
            if line < buf.line_count
              iterN = buf.get_iter_at_line(line)
              iter2 = buf.get_iter_at_offset(iterN.offset-1)
            else
              iter2 = buf.end_iter
            end
            text = buf.get_text(iter1, iter2)
            text = (line.to_s+':').ljust(6, ' ')+text.to_s
            layout.text = text
            cr.show_pango_layout(layout)
            cr.rel_move_to(0, data.font_size)
            iter1 = iterN
          end
        end
      end
    end

  end

  SexList = [[1, _('man')], [0, _('woman')], [2, _('gay')], [3, _('trans')], [4, _('lesbo')]]

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class PropertyBox < Gtk::VBox
    include PandoraModel

    attr_accessor :panobject, :vbox, :fields, :text_fields, :statusbar, \
      :rate_label, :lang_entry, :last_sw, :rate_btn, :format_btn, \
      :last_width, :last_height, :notebook, :tree_view, :edit, \
      :keep_btn, :follow_btn, :vouch0, :vouch_btn, :vouch_scale, :public0, \
      :public_btn, :public_scale, :ignore_btn, :arch_btn, :panhash0, :obj_id,
      :panstate

    # Create fields dialog
    # RU: Создать форму с полями
    def initialize(apanobject, afields, apanhash0, an_id, an_edit=nil, anotebook=nil, \
    atree_view=nil, width_loss=nil, height_loss=nil)
      super()
      if apanobject.is_a? Integer
        kind = apanobject
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          apanobject = PandoraUtils.get_model(panobjectclass.ider)
        end
      end
      @panobject = apanobject
      @fields = afields
      @notebook = anotebook
      @tree_view = atree_view
      @panhash0 = apanhash0
      @obj_id = an_id
      @edit = an_edit

      @vbox = self

      return if afields.nil?

      #@statusbar = Gtk::Statusbar.new
      #PandoraGtk.set_statusbar_text(statusbar, '')
      #statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      #@rate_btn = Gtk::Button.new(_('Rate')+':')
      #rate_btn.relief = Gtk::RELIEF_NONE
      #statusbar.pack_start(rate_btn, false, false, 0)
      #panelbox.pack_start(statusbar, false, false, 0)

      # devide text fields in separate list
      @panstate = 0
      @text_fields = Array.new
      i = @fields.size
      while i>0 do
        i -= 1
        field = @fields[i]
        atext = field[FI_VFName]
        aview = field[FI_View]
        if (aview=='blob') or (aview=='text')
          bodywin = BodyScrolledWindow.new(self, @fields, nil, nil)
          bodywin.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          bodywin.field = field
          field[FI_Widget2] = bodywin
          if notebook
            label_box = TabLabelBox.new(Gtk::Stock::DND, atext, nil)
            page = notebook.append_page(bodywin, label_box)
          end
          @text_fields << field
        end
        if (field[FI_Id]=='panstate')
          val = field[FI_Value]
          @panstate = val.to_i if (val and (val.size>0))
        end
      end

      self.signal_connect('key-press-event') do |widget, event|
        btn = nil
        case event.keyval
          when Gdk::Keyval::GDK_F5
            btn = PandoraGtk.find_tool_btn(toolbar, 'Edit')
        end
        if btn.is_a? Gtk::ToggleToolButton
          btn.active = (not btn.active?)
        elsif btn.is_a? Gtk::ToolButton
          btn.clicked
        end
        res = (not btn.nil?)
      end

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
      width_loss = 40 if (width_loss.nil? or (width_loss<10))
      height_loss = 150 if (height_loss.nil? or (height_loss<10))
      @last_width, @last_height = [scr.width-width_loss-40, scr.height-height_loss-70]

      # compose first matrix, calc its geometry
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @def_widget = nil
      @fields.each do |field|
        #p 'field='+field.inspect
        max_size = 0
        fld_size = 0
        aview = field[FI_View]
        atype = field[FI_Type]
        entry = nil
        amodal = (not notebook.nil?)
        case aview
          when 'integer', 'byte', 'word'
            entry = IntegerEntry.new
          when 'hex'
            entry = HexEntry.new
          when 'real'
            entry = FloatEntry.new
          when 'time'
            entry = DateTimeEntry.new
          when 'datetime'
            entry = DateTimeBox.new(amodal)
          when 'date'
            entry = DateEntry.new(amodal)
          when 'coord'
            its_city = (panobject and (panobject.is_a? PandoraModel::City)) \
              or (kind==PandoraModel::PK_City)
            entry = CoordBox.new(amodal, its_city)
          when 'filename', 'blob'
            entry = FilenameBox.new(window, amodal) do |filename, entry, button, filename0|
              name_fld = @panobject.field_des('name')
              if (name_fld.is_a? Array) and (name_fld[FI_Widget].is_a? Gtk::Entry)
                name_ent = name_fld[FI_Widget]
                old_name = File.basename(filename0)
                old_name2 = File.basename(filename0, '.*')
                new_name = File.basename(filename)
                if (name_ent.text.size==0) or (name_ent.text==filename0) \
                or (name_ent.text==old_name) or (name_ent.text==old_name2)
                  name_ent.text = new_name
                end
              end
            end
          when 'base64'
            entry = Base64Entry.new
          when 'phash', 'panhash'
            if field[FI_Id]=='panhash'
              entry = HexEntry.new
              #entry.editable = false
            else
              entry = PanhashBox.new(atype, amodal)
            end
          when 'bytelist'
            if field[FI_Id]=='sex'
              entry = ByteListEntry.new(SexList, amodal)
            elsif field[FI_Id]=='kind'
              entry = ByteListEntry.new(PandoraModel::RelationNames, amodal)
            elsif field[FI_Id]=='mode'
              entry = ByteListEntry.new(PandoraModel::TaskModeNames, amodal)
            else
              entry = IntegerEntry.new
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
          fld_size = field[FI_FSize].to_i if field[FI_FSize]
          max_size = field[FI_Size].to_i
          max_size = fld_size if (max_size==0)
          fld_size = def_size if (fld_size<=0)
          max_size = fld_size if (max_size<fld_size) and (max_size>0)
        rescue
          fld_size = def_size
        end
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
        ew = last_width if ew > last_width
        entry.width_request = ew if ((fld_size != 44) and (not (entry.is_a? PanhashBox)))
        ew,eh = entry.size_request
        #p 'Final [fld_size, max_size, ew]='+[fld_size, max_size, ew].inspect
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

      # calc matrix sizes
      #field_matrix = Array.new
      mw, mh = 0, 0
      row = Array.new
      row_index = -1
      rw, rh = 0, 0
      orient = :up
      @fields.each_index do |index|
        field = @fields[index]
        if (index==0) or (field[FI_NewRow]==1)
          row_index += 1
          #field_matrix << row if row != []
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
      #field_matrix << row if row != []
      mw, mh = [mw, rw].max, mh+rh
      if (mw<=last_width) and (mh<=last_height) then
        @last_width, @last_height = mw+10, mh+10
      end

      #self.signal_connect('check-resize') do |widget|
      #self.signal_connect('configure-event') do |widget, event|
      #self.signal_connect('notify::position') do |widget, param|
      #self.signal_connect('expose-event') do |widget, param|
      #self.signal_connect('size-request') do |widget, requisition|
      self.signal_connect('size-allocate') do |widget, allocation|
        self.on_resize
        false
      end

      @old_field_matrix = []
    end

    def set_status_icons
      @panstate ||= 0
      if edit
        count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
        if rate_btn and rate.is_a? Float
          rate_btn.label = _('Rate')+': '+rate.round(2).to_s
        #dialog.rate_label.text = rate.to_s
        end

        if vouch_btn
          trust = nil
          trust_or_num = PandoraCrypto.trust_to_panobj(panhash0)
          #p '====trust_or_num='+[panhash0, trust_or_num].inspect
          trust = trust_or_num if (trust_or_num.is_a? Float)
          vouch_btn.safe_set_active((trust_or_num != nil))
          #vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
          vouch_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          vouch_scale.scale.value = trust
        end

        keep_btn.safe_set_active((PandoraModel::PSF_Support & panstate)>0) if keep_btn
        arch_btn.safe_set_active((PandoraModel::PSF_Archive & panstate)>0) if arch_btn

        if public_btn
          pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
          public_btn.safe_set_active(pub_level)
          public_scale.sensitive = pub_level
          if pub_level
            #p '====pub_level='+pub_level.inspect
            #public_btn.inconsistent = (pub_level == nil)
            public_scale.scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
          end
        end

        if follow_btn
          follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
          follow_btn.safe_set_active(follow)
        end

        if ignore_btn
          ignore = PandoraModel.act_relation(nil, panhash0, RK_Ignore, :check)
          ignore_btn.safe_set_active(ignore)
        end

        lang_entry.active_text = lang.to_s if lang_entry
        #trust_lab = dialog.trust_btn.children[0]
        #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
      else  #new or copy
        key = PandoraCrypto.current_key(false, false)
        key_inited = (key and key[PandoraCrypto::KV_Obj])
        keep_btn.safe_set_active(true) if keep_btn
        follow_btn.safe_set_active(key_inited) if follow_btn
        vouch_btn.safe_set_active(key_inited) if vouch_btn
        vouch_scale.sensitive = key_inited if vouch_scale
        if follow_btn and (not key_inited)
          follow_btn.sensitive = false
          vouch_btn.sensitive = false
          public_btn.sensitive = false
          ignore_btn.sensitive = false
        end
      end

      #!!!st_text = panobject.panhash_formula
      #!!!st_text = st_text + ' [#'+panobject.calc_panhash(sel[0], lang, \
      #  true, true)+']' if sel and sel.size>0
      #!!PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

      #if panobject.is_a? PandoraModel::Key
      #  mi = Gtk::MenuItem.new("Действия")
      #  menu = Gtk::MenuBar.new
      #  menu.append(mi)

      #  menu2 = Gtk::Menu.new
      #  menuitem = Gtk::MenuItem.new("Генерировать")
      #  menu2.append(menuitem)
      #  mi.submenu = menu2
      #  #p dialog.action_area
      #  dialog.hbox.pack_end(menu, false, false)
      #  #dialog.action_area.add(menu)
      #end

      titadd = nil
      if not edit
      #  titadd = _('edit')
      #else
        titadd = _('new')
      end
      #!!dialog.title += ' ('+titadd+')' if titadd and (titadd != '')
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
    def on_resize(view_width=nil, view_height=nil, force=nil)
      view_width ||= parent.allocation.width
      view_height ||= parent.allocation.height
      if (((view_width != last_width) or (view_height != last_height) or force) \
      and (@pre_last_width.nil? or @pre_last_height.nil? \
      or ((view_width != @pre_last_width) and (view_height != @pre_last_height))))
        #p '----------RESIZE [view_width, view_height, last_width, last_height, parent]='+\
        #  [view_width, view_height, last_width, last_height, parent].inspect
        @pre_last_width, @pre_last_height = last_width, last_height
        @last_width, @last_height = view_width, view_height

        form_width = last_width-30
        form_height = last_height-65

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

                if (not [:up, :down, :left, :right].include?(field[FI_LabOr]))
                  field[FI_LabOr]=orient
                end
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
              if (field[FI_LabOr] != ofield[FI_LabOr]) \
                or (field[FI_LabW] != ofield[FI_LabW]) \
                or (field[FI_LabH] != ofield[FI_LabH]) \
                or (field[FI_WidW] != ofield[FI_WidW]) \
                or (field[FI_WidH] != ofield[FI_WidH]) \
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

          #!!!@def_widget = focus if focus

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
          if (@def_widget and (not @def_widget.destroyed?))
            #focus = @def_widget
            @def_widget.grab_focus
          end
        end
      end
    end

    def accept_hash_flds(flds_hash, lang=nil, created0=nil)
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

      @panstate = flds_hash['panstate']
      panstate ||= 0
      if keep_btn and keep_btn.sensitive?
        if keep_btn.active?
          panstate = (panstate | PandoraModel::PSF_Support)
        else
          panstate = (panstate & (~ PandoraModel::PSF_Support))
        end
      end
      if arch_btn and arch_btn.sensitive?
        if arch_btn.active?
          panstate = (panstate | PandoraModel::PSF_Archive)
        else
          panstate = (panstate & (~ PandoraModel::PSF_Archive))
        end
      end
      flds_hash['panstate'] = panstate

      lang ||= 0
      if (panobject.is_a? PandoraModel::Key)
        lang = flds_hash['rights'].to_i
      elsif (panobject.is_a? PandoraModel::Currency)
        lang = 0
      end

      panhash = panobject.calc_panhash(flds_hash, lang)
      flds_hash['panhash'] = panhash

      if (panobject.is_a? PandoraModel::Key) and panhash0 \
      and (flds_hash['kind'].to_i == PandoraCrypto::KT_Priv) and edit
        flds_hash['panhash'] = panhash0
      end

      filter = nil
      filter = {:id=>obj_id.to_i} if (edit and obj_id)
      #filter = {:panhash=>panhash} if filter.nil?
      res = panobject.update(flds_hash, nil, filter, true)

      if res
        filter ||= { :panhash => panhash, :modified => time_now }
        sel = panobject.select(filter, true)
        if sel[0]
          #p 'panobject.namesvalues='+panobject.namesvalues.inspect
          #p 'panobject.matter_fields='+panobject.matter_fields.inspect

          if tree_view and (not tree_view.destroyed?)
            @obj_id = panobject.field_val('id', sel[0])  #panobject.namesvalues['id']
            @obj_id = obj_id.to_i
            #p 'id='+id.inspect
            #p 'id='+id.inspect
            ind = tree_view.sel.index { |row| row[0]==obj_id }
            #p 'ind='+ind.inspect
            store = tree_view.model
            if ind
              #p '---------CHANGE'
              sel[0].each_with_index do |c,i|
                tree_view.sel[ind][i] = c
              end
              iter[0] = obj_id
              store.row_changed(path, iter)
            else
              #p '---------INSERT'
              tree_view.sel << sel[0]
              iter = store.append
              iter[0] = obj_id
              tree_view.set_cursor(Gtk::TreePath.new(tree_view.sel.size-1), nil, false)
            end
          end

          if vouch_btn and vouch_btn.sensitive? and vouch_scale
            PandoraCrypto.unsign_panobject(panhash0, true) if panhash0
            if vouch_btn.active?
              trust = vouch_scale.scale.value
              trust = PandoraModel.transform_trust(trust, :float_to_int)
              PandoraCrypto.sign_panobject(panobject, trust)
            end
          end

          if follow_btn and follow_btn.sensitive?
            PandoraModel.act_relation(nil, panhash0, RK_Follow, :delete, \
              true, true) if panhash0
            if panhash0 and (panhash != panhash0)
              PandoraModel.act_relation(nil, panhash, RK_Follow, :delete, \
                true, true)
            end
            if follow_btn.active?
              PandoraModel.act_relation(nil, panhash, RK_Follow, :create, \
                true, true)
            end
          end

          if public_btn and public_btn.sensitive?
            PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :delete, \
              true, true) if panhash0
            if panhash0 and (panhash != panhash0)
              PandoraModel.act_relation(nil, panhash, RK_MinPublic, :delete, \
                true, true)
            end
            if public_btn.active? and public_scale
              public_level = PandoraModel.trust2_to_pub235(public_scale.scale.value)
              p 'public_level='+public_level.inspect
              PandoraModel.act_relation(nil, panhash, public_level, :create, \
                true, true)
            end
          end

          if ignore_btn and ignore_btn.sensitive?
            PandoraModel.act_relation(nil, panhash, RK_Ignore, :delete, \
              true, true)
            PandoraModel.act_relation(nil, panhash, RK_Ignore, :create, \
              true, true) if ignore_btn.active?
          end

        end
      end
    end

    def save_fields_with_flags(created0=nil, row=nil)
      # view_fields to raw_fields and hash
      flds_hash = {}
      file_way = nil
      file_way_exist = nil
      row ||= fields
      fields.each do |field|
        type = field[FI_Type]
        view = field[FI_View]
        entry = field[FI_Widget]
        val = entry.text

        if ((panobject.kind==PK_Relation) and val \
        and ((field[FI_Id]=='first') or (field[FI_Id]=='second')))
          PandoraModel.del_image_from_cache(val, true)
        elsif (panobject.kind==PK_Parameter) and (field[FI_Id]=='value')
          par_type = panobject.field_val('type', row)
          setting = panobject.field_val('setting', row)
          ps = PandoraUtils.decode_param_setting(setting)
          view = ps['view']
          view ||= PandoraUtils.pantype_to_view(par_type)
        elsif file_way
          p 'file_way2='+file_way.inspect
          if (field[FI_Id]=='type')
            val = PandoraUtils.detect_file_type(file_way) if (not val) or (val.size==0)
          elsif (field[FI_Id]=='sha1')
            if file_way_exist
              sha1 = Digest::SHA1.file(file_way)
              val = sha1.hexdigest
            else
              val = nil
            end
          elsif (field[FI_Id]=='md5')
            if file_way_exist
              md5 = Digest::MD5.file(file_way)
              val = md5.hexdigest
            else
              val = nil
            end
          elsif (field[FI_Id]=='size')
            val = File.size?(file_way)
          end
        end
        p 'fld, val, type, view='+[field[FI_Id], val, type, view].inspect
        val = PandoraUtils.view_to_val(val, type, view)
        if (view=='blob') or (view=='text')
          if val and (val.size>0)
            file_way = PandoraUtils.absolute_path(val)
            file_way_exist = File.exist?(file_way)
            p 'file_way1='+file_way.inspect
            val = '@'+val
            flds_hash[field[FI_Id]] = val
            field[FI_Value] = val
            #p '----TEXT ENTR!!!!!!!!!!!'
          end
        else
          flds_hash[field[FI_Id]] = val
          field[FI_Value] = val
        end
      end

      # add text and blob fields
      text_fields.each do |field|
        entry = field[FI_Widget]
        if entry.text == ''
          textview = field[FI_Widget2].child
          body_win = nil
          body_win = textview.parent if textview and (not textview.destroyed?)
          text = nil
          if body_win and (not body_win.destroyed?) \
          and (body_win.is_a? PandoraGtk::BodyScrolledWindow) and body_win.raw_buffer
            #text = textview.buffer.text
            text = body_win.raw_buffer.text
            if text and (text.size>0)
              #p '===TEXT BUF!!!!!!!!!!!'
              field[FI_Value] = text
              flds_hash[field[FI_Id]] = text
              type_fld = panobject.field_des('type')
              flds_hash['type'] = body_win.property_box.format_btn.label.upcase if type_fld
            else
              text = nil
            end
          end
          text ||= field[FI_Value]
          text ||= ''
          sha1_fld = panobject.field_des('sha1')
          flds_hash['sha1'] = Digest::SHA1.digest(text) if sha1_fld
          md5_fld = panobject.field_des('md5')
          flds_hash['md5'] = Digest::MD5.digest(text) if md5_fld
          size_fld = panobject.field_des('size')
          flds_hash['size'] = text.size if size_fld
        end
      end

      # language detect
      lg = nil
      begin
        lg = PandoraModel.text_to_lang(@lang_entry.entry.text)
      rescue
      end
      lang = lg if lg
      lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

      self.accept_hash_flds(flds_hash, lang, created0)
    end

  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    attr_accessor :property_box

    def get_bodywin(page_num=nil)
      res = nil
      page_num ||= notebook.page
      child = notebook.get_nth_page(page_num)
      res = child if (child.is_a? BodyScrolledWindow)
      res
    end

    # Create fields dialog
    # RU: Создать форму с полями
    def initialize(apanobject, tree_view, afields, panhash0, obj_id, edit, *args)
      super(*args)
      width_loss = 36
      height_loss = 134
      @property_box = PropertyBox.new(apanobject, afields, panhash0, obj_id, \
        edit, self.notebook, tree_view, width_loss, height_loss)
      viewport.add(@property_box)
      #self.signal_connect('configure-event') do |widget, event|
      #  property_box.on_resize_window(event.width, event.height)
      #  false
      #end
      self.set_default_size(property_box.last_width+width_loss, \
        property_box.last_height+height_loss)
      #property_box.window_width = property_box.window_height = 0
      viewport.show_all

      @last_sw = nil
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        @last_sw = nil if (page_num == 0) and @last_sw
        if page_num==0
          hbox.show
        else
          bodywin = get_bodywin(page_num)
          p 'bodywin='+bodywin.inspect
          if bodywin
            hbox.hide
            bodywin.fill_body
          end
        end
      end

    end

  end

  $you_color = 'red'
  $dude_color = 'blue'
  $tab_color = 'blue'
  $sys_color = 'purple'
  $read_time = 1.5
  $last_page = nil

  # DrawingArea for video output
  # RU: DrawingArea для вывода видео
  class ViewDrawingArea < Gtk::DrawingArea
    attr_accessor :expose_event, :dialog

    def initialize(adialog, *args)
      super(*args)
      @dialog = adialog
      #set_size_request(100, 100)
      #@expose_event = signal_connect('expose-event') do
      #  alloc = self.allocation
      #  self.window.draw_arc(self.style.fg_gc(self.state), true, \
      #    0, 0, alloc.width, alloc.height, 0, 64 * 360)
      #end
    end

    # Set expose event handler
    # RU: Устанавливает обработчик события expose
    def set_expose_event(value, width=nil)
      signal_handler_disconnect(@expose_event) if @expose_event
      @expose_event = value
      if value.nil?
        if self==dialog.area_recv
          dialog.hide_recv_area
        else
          dialog.hide_send_area
        end
      else
        if self==dialog.area_recv
          dialog.show_recv_area(width)
        else
          dialog.show_send_area(width)
        end
      end
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock=nil, title=nil, toggle=nil)
    btn = nil
    padd = 1
    if stock.is_a? Gtk::Widget
      btn = stock
    else
      stock = stock.to_sym if stock.is_a? String
      $window.register_stock(stock) if stock
      if toggle.nil?
        if stock.nil?
          btn = Gtk::SeparatorToolItem.new
          title = nil
          padd = 0
        else
          btn = Gtk::ToolButton.new(stock)
          btn.signal_connect('clicked') do |*args|
            yield(*args) if block_given?
          end
        end
      elsif toggle.is_a? Integer
        if stock
          btn = Gtk::MenuToolButton.new(stock)
        else
          btn = Gtk::MenuToolButton.new(nil, title)
          title = nil
        end
        btn.signal_connect('clicked') do |*args|
          yield(*args) if block_given?
        end
      else
        btn = SafeToggleToolButton.new(stock)
        btn.safe_signal_clicked do |*args|
          yield(*args) if block_given?
        end
        btn.safe_set_active(toggle) if toggle
      end
      if title
        title, keyb = title.split('|')
        if keyb
          keyb = ' '+keyb
        else
          keyb = ''
        end
        lang_title = _(title)
        lang_title.gsub!('_', '')
        btn.tooltip_text = lang_title + keyb
        btn.label = title
      elsif stock
        stock_info = Gtk::Stock.lookup(stock)
        if (stock_info.is_a? Array) and (stock_info.size>0)
          label = stock_info[1]
          if label
            label.gsub!('_', '')
            btn.tooltip_text = label
          end
        end
      end
    end
    #p '[toolbar, stock, title, toggle]='+[toolbar, stock, title, toggle].inspect
    if toolbar.is_a? Gtk::Toolbar
      toolbar.add(btn)
    else
      if btn.is_a? Gtk::Toolbar
        toolbar.pack_start(btn, true, true, padd)
      else
        toolbar.pack_start(btn, false, false, padd)
      end
    end
    btn
  end

  CSI_Persons = 0
  CSI_Keys    = 1
  CSI_Nodes   = 2
  CSI_PersonRecs = 3

  CPI_Property  = 0
  CPI_Profile   = 1
  CPI_Opinions  = 2
  CPI_Relations = 3
  CPI_Signs     = 4
  CPI_Chat      = 5
  CPI_Dialog    = 6
  CPI_Editor    = 7

  CPI_Sub       = 1
  CPI_Last_Sub  = 4
  CPI_Last      = 7

  CabPageInfo = [[Gtk::Stock::PROPERTIES, 'Basic'], \
    [Gtk::Stock::HOME, 'Profile'], \
    [:opinion, 'Opinions'], \
    [:relation, 'Relations'], \
    [:sign, 'Signs'], \
    [:chat, 'Chat'], \
    [:dialog, 'Dialog'], \
    [:editor, 'Editor']]

  # Tab view of person
  TV_Name    = 0   # Name only
  TV_Family  = 1   # Family only
  TV_NameFam   = 2   # Name and family
  TV_NameN   = 3   # Name with number

  # Panobject cabinet page
  # RU: Страница кабинета панобъекта
  class CabinetBox < Gtk::VBox
    attr_accessor :room_id, :crypt_btn, :sign_btn, :sign_scale, :sign0, \
      :online_btn, :mic_btn, :webcam_btn, :talkview, :edit_box, :area_send, \
      :area_recv, :recv_media_pipeline, :appsrcs, :session, :ximagesink, \
      :read_thread, :recv_media_queue, :has_unread, :person_name, :captcha_entry, \
      :sender_box, :toolbar_box, :captcha_enter, :edit_sw, :main_hpaned, \
      :send_hpaned, :cab_notebook, :send_btn, :opt_btns, :cab_panhash, :session, \
      :bodywin, :fields, :obj_id, :edit, :property_box, :kind, :label_box, \
      :active_page

    include PandoraGtk

    CL_Online = 0
    CL_Name   = 1

    def show_recv_area(width=nil)
      if area_recv.allocation.width <= 24
        width ||= 320
        main_hpaned.position = width
      end
    end

    def hide_recv_area
      main_hpaned.position = 0 if (main_hpaned and (not main_hpaned.destroyed?))
    end

    def show_send_area(width=nil)
      if area_send.allocation.width <= 24
        width ||= 120
        send_hpaned.position = width
      end
    end

    def hide_send_area
      send_hpaned.position = 0 if (send_hpaned and (not send_hpaned.destroyed?))
    end

    def init_captcha_entry(pixbuf, length=nil, symbols=nil, clue=nil, node_text=nil)
      if not @captcha_entry
        @captcha_label = Gtk::Label.new(_('Enter text from picture'))
        label = @captcha_label
        label.set_alignment(0.5, 1.0)
        @sender_box.pack_start(label, true, true, 2)

        @captcha_entry = PandoraGtk::MaskEntry.new

        len = 0
        begin
          len = length.to_i if length
        rescue
        end
        captcha_entry.max_length = len
        if symbols
          mask = symbols.downcase+symbols.upcase
          captcha_entry.mask = mask
        end

        res = area_recv.signal_connect('expose-event') do |widget, event|
          x = widget.allocation.width
          y = widget.allocation.height
          x = (x - pixbuf.width) / 2
          y = (y - pixbuf.height) / 2
          x = 0 if x<0
          y = 0 if y<0
          cr = widget.window.create_cairo_context
          cr.set_source_pixbuf(pixbuf, x, y)
          cr.paint
          true
        end
        area_recv.set_expose_event(res, pixbuf.width+20)

        captcha_entry.signal_connect('key-press-event') do |widget, event|
          if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
            text = captcha_entry.text
            if text.size>0
              @captcha_enter = captcha_entry.text
              captcha_entry.text = ''
              del_captcha_entry
            end
            true
          elsif (Gdk::Keyval::GDK_Escape==event.keyval)
            @captcha_enter = false
            del_captcha_entry
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
        @captcha_align = Gtk::Alignment.new(0.5, 0, 0.0, 0.0)
        @captcha_align.add(captcha_entry)
        @sender_box.pack_start(@captcha_align, true, true, 2)
        @edit_sw.hide
        #@toolbar_box.hide
        @captcha_label.show
        @captcha_align.show_all

        area_recv.queue_draw

        Thread.pass
        sleep 0.02
        talkview.after_addition(true)
        talkview.show_all

        PandoraGtk.hack_grab_focus(@captcha_entry)
      end
    end

    def del_captcha_entry
      if @captcha_entry and (not self.destroyed?)
        @captcha_align.destroy
        @captcha_align = nil
        @captcha_entry = nil
        @captcha_label.destroy
        @captcha_label = nil
        #@toolbar_box.show
        @edit_sw.show_all
        area_recv.set_expose_event(nil)
        area_recv.queue_draw
        Thread.pass
        talkview.after_addition(true)
        @edit_box.grab_focus
      end
    end

    def hide_toolbar_btns(page=nil)
      @add_toolbar_btns.each do |btns|
        if btns.is_a? Array
          btns.each do |btn|
            btn.hide
          end
        end
      end
    end

    def show_toolbar_btns(page=nil)
      btns = @add_toolbar_btns[page]
      if btns.is_a? Array
        btns.each do |btn|
          btn.show_all
        end
      end
    end

    def add_btn_to_toolbar(stock=nil, title=nil, toggle=nil, page=nil)
      btns = nil
      if page.is_a? Array
        btns = page
      elsif page.is_a? FalseClass
        btns = nil
      else
        page ||= @active_page
        btns = @add_toolbar_btns[page]
        if not (btns.is_a? Array)
          btns = Array.new
          @add_toolbar_btns[page] = btns
        end
      end
      btn = PandoraGtk.add_tool_btn(toolbar_box, stock, title, toggle) do |*args|
        yield(*args) if block_given?
      end
      btns << btn if (not btns.nil?)
      btn
    end

    def fill_property_toolbar(pb)
      pb.keep_btn = add_btn_to_toolbar(:keep, 'Keep', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.ignore_btn.safe_set_active(false)
        end
      end

      pb.arch_btn = add_btn_to_toolbar(:arch, 'Shelve', false)

      pb.follow_btn = add_btn_to_toolbar(:follow, 'Follow', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.keep_btn.safe_set_active(true)
          pb.arch_btn.safe_set_active(false)
          pb.ignore_btn.safe_set_active(false)
        end
      end

      pb.vouch0 = 0.4
      pb.vouch_btn = add_btn_to_toolbar(:sign, 'Vouch|(Ctrl+G)', false) do |btn|
        if not btn.destroyed?
          pb.vouch_scale.sensitive = btn.active?
          if btn.active?
            if (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              pb.keep_btn.safe_set_active(true)
              pb.arch_btn.safe_set_active(false)
              pb.ignore_btn.safe_set_active(false) if pb.vouch_scale.scale.value>0
            end
            pb.vouch0 ||= 0.4
            pb.vouch_scale.scale.value = pb.vouch0
          else
            pb.vouch0 = pb.vouch_scale.scale.value
          end
        end
      end
      pb.vouch_scale = TrustScale.new(nil, 'Vouch', pb.vouch0)
      pb.vouch_scale.sensitive = pb.vouch_btn.active?
      add_btn_to_toolbar(pb.vouch_scale)

      pb.public0 = 0.0
      pb.public_btn = add_btn_to_toolbar(:public, 'Public', false) do |btn|
        if not btn.destroyed?
          pb.public_scale.sensitive = btn.active?
          if btn.active?
            if (not PandoraGtk.is_ctrl_shift_alt?(true, true))
              pb.keep_btn.safe_set_active(true)
              pb.follow_btn.safe_set_active(true)
              pb.vouch_btn.active = true
              pb.arch_btn.safe_set_active(false)
              pb.ignore_btn.safe_set_active(false)
            end
            pb.public0 ||= 0.0
            pb.public_scale.scale.value = pb.public0
          else
            pb.public0 = pb.public_scale.scale.value
          end
        end
      end
      pb.public_scale = TrustScale.new(nil, 'Publish for level (and higher)', pb.public0)
      pb.public_scale.sensitive = pb.public_btn.active?
      add_btn_to_toolbar(pb.public_scale)

      pb.ignore_btn = add_btn_to_toolbar(:ignore, 'Ignore', false) do |btn|
        if ((not btn.destroyed?) and btn.active? \
        and (not PandoraGtk.is_ctrl_shift_alt?(true, true)))
          pb.keep_btn.safe_set_active(false)
          pb.follow_btn.safe_set_active(false)
          pb.public_btn.active = false
          if pb.vouch_btn.active? and (pb.vouch_scale.scale.value>0)
            pb.vouch_scale.scale.value = 0
          end
          pb.arch_btn.safe_set_active(true)
        end
      end

      add_btn_to_toolbar

      add_btn_to_toolbar(Gtk::Stock::SAVE) do |btn|
        pb.save_fields_with_flags
      end
      add_btn_to_toolbar(Gtk::Stock::OK) do |btn|
        pb.save_fields_with_flags
        self.destroy
      end

      #add_btn_to_toolbar(Gtk::Stock::CANCEL) do |btn|
      #  self.destroy
      #end

    end

    def fill_dlg_toolbar(page=nil)
      @crypt_btn = add_btn_to_toolbar(:crypt, 'Encrypt|(Ctrl+K)', false) if (page==CPI_Dialog)

      @sign0 = 1.0
      @sign_btn = add_btn_to_toolbar(:sign, 'Vouch|(Ctrl+G)', false) do |widget|
        if not widget.destroyed?
          sign_scale.sensitive = widget.active?
          if widget.active?
            @sign0 ||= 1.0
            sign_scale.scale.value = @sign0
          else
            @sign0 = sign_scale.scale.value
          end
        end
      end
      @sign_scale = TrustScale.new(nil, 'Vouch', @sign0)
      sign_scale.sensitive = sign_btn.active?
      add_btn_to_toolbar(sign_scale)

      if (page==CPI_Dialog) and (kind==PandoraModel::PK_Person)
        require_sign_btn = add_btn_to_toolbar(:require, 'Require sign', false)

        add_btn_to_toolbar

        is_online = (@session != nil)
        @online_btn = add_btn_to_toolbar(Gtk::Stock::CONNECT, 'Online', is_online) \
        do |widget|
          p 'widget.active?='+widget.active?.inspect
          if widget.active? #and (not widget.inconsistent?)
            $window.pool.init_session(nil, nil, 0, self, nil, \
              cab_panhash, nil, nil, PandoraNet::CM_Captcha)
          else
            widget.safe_set_active(false)
            $window.pool.stop_session(nil, cab_panhash, \
              nil, false, self.session)
          end
        end

        @webcam_btn = add_btn_to_toolbar(:webcam, 'Webcam', false) do |widget|
          if widget.active?
            if init_video_sender(true)
              online_btn.active = true
            end
          else
            init_video_sender(false, true)
            init_video_sender(false)
          end
        end

        @mic_btn = add_btn_to_toolbar(:mic, 'Mic', false) do |widget|
          if widget.active?
            if init_audio_sender(true)
              online_btn.active = true
            end
          else
            init_audio_sender(false, true)
            init_audio_sender(false)
          end
        end

        record_btn = add_btn_to_toolbar(Gtk::Stock::MEDIA_RECORD, 'Record', false) do |widget|
          if widget.active?
            #start record video and audio
            sleep(0.5)
            widget.safe_set_active(false)
          else
            #stop record, save the file and add a link to edit_box
          end
        end
      end

      add_btn_to_toolbar

      def_smiles = PandoraUtils.get_param('def_smiles')
      smile_btn = SmileButton.new(def_smiles) do |preset, label|
        smile_img = '[emot='+preset+'/'+label+']'
        smile_img = ' '+smile_img if edit_box.buffer.text != ''
        edit_box.buffer.insert_at_cursor(smile_img)
      end
      smile_btn.tooltip_text = _('Smile')+' (Alt+Down)'
      add_btn_to_toolbar(smile_btn)

      game_btn = add_btn_to_toolbar(:game, 'Game') if page==CPI_Dialog

      @send_btn = add_btn_to_toolbar(:send, 'Send') do |widget|
        if edit_box.buffer.text != ''
          mes = edit_box.buffer.text
          sign_trust = nil
          sign_trust = sign_scale.scale.value if sign_btn.active?
          res = send_mes(mes, crypt_btn.active?, sign_trust)
          if res
            edit_box.buffer.text = ''
          end
        end
        false
      end
      send_btn.sensitive = false
    end

    # Add menu item
    # RU: Добавляет пункт меню
    def add_menu_item(btn, menu, stock, text=nil)
      mi = nil
      if stock.is_a? String
        mi = Gtk::MenuItem.new(stock)
      else
        $window.register_stock(stock)
        mi = Gtk::ImageMenuItem.new(stock)
        mi.label = _(text) if text
      end
      menu.append(mi)
      mi.signal_connect('activate') do |mi|
        yield(mi) if block_given?
      end
    end

    # Fill editor toolbar
    # RU: Заполнить панель редактора
    def fill_edit_toolbar
      bodywin = nil
      bodywid = nil
      pb = property_box
      first_body_fld = property_box.text_fields[0]
      if first_body_fld
        bodywin = first_body_fld[FI_Widget2]
        bodywid = bodywin.child
      end

      btn = add_btn_to_toolbar(Gtk::Stock::EDIT, 'Edit', false) do |btn|
        bodywin.view_mode = (not btn.active?)
        bodywin.set_buffers
      end
      bodywin.edit_btn = btn if bodywin

      btn = add_btn_to_toolbar(nil, 'auto', 0)
      pb.format_btn = btn
      menu = Gtk::Menu.new
      btn.menu = menu
      ['auto', 'plain', 'markdown', 'bbcode', 'wiki', 'html', 'ruby', \
      'python', 'xml'].each do |title|
        add_menu_item(btn, menu, title) do |mi|
          btn.label = mi.label
          bodywin.format = mi.label.to_s
          bodywin.set_buffers
        end
      end
      menu.show_all

      add_btn_to_toolbar

      toolbar = Gtk::Toolbar.new
      toolbar.show_arrow = true
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS

      bodywin.toolbar = toolbar if bodywin

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::BOLD) do
        bodywin.insert_tag('bold')
      end

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::ITALIC, nil, 0) do
        bodywin.insert_tag('italic')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::UNDERLINE) do
        insert_tag('undline')
      end
      add_menu_item(btn, menu, Gtk::Stock::STRIKETHROUGH) do
        bodywin.insert_tag('strike')
      end
      add_menu_item(btn, menu, Gtk::Stock::UNDERLINE) do
        bodywin.insert_tag('d')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Sub') do
        bodywin.insert_tag('sub')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Sup') do
        bodywin.insert_tag('sup')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Small') do
        bodywin.insert_tag('small')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Large') do
        bodywin.insert_tag('large')
      end
      menu.show_all

      @selected_color = 'red'
      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SELECT_COLOR, nil, 0) do
        bodywin.insert_tag('color', @selected_color)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::SELECT_COLOR) do
        shift_or_ctrl = PandoraGtk.is_ctrl_shift_alt?(true, true)
        dialog = Gtk::ColorSelectionDialog.new
        dialog.set_transient_for(self)
        colorsel = dialog.colorsel
        color = Gdk::Color.parse(@selected_color)
        colorsel.set_previous_color(color)
        colorsel.set_current_color(color)
        colorsel.set_has_palette(true)
        if dialog.run == Gtk::Dialog::RESPONSE_OK
          color = colorsel.current_color
          if shift_or_ctrl
            @selected_color = color.to_s
          else
            @selected_color = PandoraUtils.color_to_str(color)
          end
          bodywin.insert_tag('color', @selected_color)
        end
        dialog.destroy
      end
      @selected_font = 'Sans 10'
      add_menu_item(btn, menu, Gtk::Stock::SELECT_FONT) do
        dialog = Gtk::FontSelectionDialog.new
        dialog.font_name = @selected_font
        #dialog.preview_text = 'P2P folk network Pandora'
        if dialog.run == Gtk::Dialog::RESPONSE_OK
          @selected_font = dialog.font_name
          desc = Pango::FontDescription.new(@selected_font)
          params = {'family'=>desc.family, 'size'=>desc.size/Pango::SCALE}
          params['style']='1' if desc.style==Pango::FontDescription::STYLE_OBLIQUE
          params['style']='2' if desc.style==Pango::FontDescription::STYLE_ITALIC
          params['weight']='600' if desc.weight==Pango::FontDescription::WEIGHT_BOLD
          bodywin.insert_tag('font', params)
        end
        dialog.destroy
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, nil, 0) do
        bodywin.insert_tag('center')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_RIGHT) do
        bodywin.insert_tag('right')
      end
      add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_FILL) do
        bodywin.insert_tag('fill')
      end
      add_menu_item(btn, menu, Gtk::Stock::JUSTIFY_LEFT) do
        bodywin.insert_tag('left')
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar, :image, 'Image') do
        dialog = PandoraGtk::PanhashDialog.new([PandoraModel::Blob])
        dialog.choose_record('sha1','md5','name') do |panhash,sha1,md5,name|
          params = ''
          if (name.is_a? String) and (name.size>0)
            params << ' alt="'+name+'" title="'+name+'"'
          end
          if (sha1.is_a? String) and (sha1.size>0)
            bodywin.insert_tag('img/', 'sha1://'+PandoraUtils.bytes_to_hex(sha1)+params)
          elsif panhash.is_a? String
            bodywin.insert_tag('img/', 'pandora://'+PandoraUtils.bytes_to_hex(panhash)+params)
          end
        end
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link') do
        bodywin.insert_tag('link', 'http://priroda.su', 'Priroda.SU')
      end

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::INDENT, 'h1', 0) do
        bodywin.insert_tag('h1')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h2') do
        bodywin.insert_tag('h2')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h3') do
        bodywin.insert_tag('h3')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h4') do
        bodywin.insert_tag('h4')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h5') do
        bodywin.insert_tag('h5')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDENT, 'h6') do
        bodywin.insert_tag('h6')
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, :code, 'Code', 0) do
        bodywin.insert_tag('code', 'ruby')
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, :quote, 'Quote') do
        bodywin.insert_tag('quote')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Cut') do
        bodywin.insert_tag('cut', _('Expand'))
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'HR') do
        bodywin.insert_tag('hr/', '150')
      end
      add_menu_item(btn, menu, :table, 'Table') do
        bodywin.insert_tag('table')
      end
      menu.append(Gtk::SeparatorMenuItem.new)
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Edit') do
        bodywin.insert_tag('edit/', 'Edit value="Text" size="40"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Spin') do
        bodywin.insert_tag('spin/', 'Spin values="42,48,52" default="48"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Integer') do
        bodywin.insert_tag('integer/', 'Integer value="42" width="70"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Hex') do
        bodywin.insert_tag('hex/', 'Hex value="01a5ff" size="20"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Real') do
        bodywin.insert_tag('real/', 'Real value="0.55"')
      end
      add_menu_item(btn, menu, :date, 'Date') do
        bodywin.insert_tag('date/', 'Date value="current"')
      end
      add_menu_item(btn, menu, :time, 'Time') do
        bodywin.insert_tag('time/', 'Time value="current"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Coord') do
        bodywin.insert_tag('coord/', 'Coord')
      end
      add_menu_item(btn, menu, Gtk::Stock::OPEN, 'Filename') do
        bodywin.insert_tag('filename/', 'Filename value="./picture1.jpg"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Base64') do
        bodywin.insert_tag('base64/', 'Base64 value="SGVsbG8=" size="30"')
      end
      add_menu_item(btn, menu, :panhash, 'Panhash') do
        bodywin.insert_tag('panhash/', 'Panhash kind="Person,Community,Blob"')
      end
      add_menu_item(btn, menu, :list, 'Bytelist') do
        bodywin.insert_tag('bytelist/', 'List values="red, green, blue"')
      end
      add_menu_item(btn, menu, Gtk::Stock::INDEX, 'Button') do
        bodywin.insert_tag('button/', 'Button value="Order"')
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar)

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::FIND, nil, 0) do
        #find
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::FIND_AND_REPLACE) do
        #replace
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::PRINT_PREVIEW, nil, 0) do
        bodywin.run_print_operation(true)
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::PRINT) do
        bodywin.run_print_operation
      end
      add_menu_item(btn, menu, Gtk::Stock::PAGE_SETUP) do
        bodywin.set_page_setup
      end
      menu.show_all

      btn = PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::UNDO, nil, 0) do
        #do undo
      end
      menu = Gtk::Menu.new
      btn.menu = menu
      add_menu_item(btn, menu, Gtk::Stock::REDO) do
        #redo
      end
      add_menu_item(btn, menu, Gtk::Stock::COPY) do
        #copy
      end
      add_menu_item(btn, menu, Gtk::Stock::CUT) do
        #cut
      end
      add_menu_item(btn, menu, Gtk::Stock::PASTE) do
        #paste
      end
      menu.show_all

      PandoraGtk.add_tool_btn(toolbar, :tags, 'Color tags', true) do |btn|
        bodywin.color_mode = btn.active?
        bodywin.set_buffers
      end

      PandoraGtk.add_tool_btn(toolbar)

      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::SAVE) do
        pb.save_fields_with_flags
      end
      PandoraGtk.add_tool_btn(toolbar, Gtk::Stock::OK) do
        pb.save_fields_with_flags
        self.destroy
      end

      toolbar.show_all
      add_btn_to_toolbar(toolbar)
    end

    def fill_view_toolbar
      add_btn_to_toolbar(Gtk::Stock::ADD, 'Add')
      add_btn_to_toolbar(Gtk::Stock::DELETE, 'Delete')
      add_btn_to_toolbar(Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      add_btn_to_toolbar(Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }
      @zoom_100 = add_btn_to_toolbar(Gtk::Stock::ZOOM_100, 'Show 1:1', true) do
        @zoom_fit.safe_set_active(false)
        true
      end
      @zoom_fit = add_btn_to_toolbar(Gtk::Stock::ZOOM_FIT, 'Zoom to fit', false) do
        @zoom_100.safe_set_active(false)
        true
      end
      add_btn_to_toolbar(Gtk::Stock::ZOOM_IN, 'Zoom in') do
        @zoom_fit.safe_set_active(false)
        @zoom_100.safe_set_active(false)
        true
      end
      add_btn_to_toolbar(Gtk::Stock::ZOOM_OUT, 'Zoom out') do
        @zoom_fit.safe_set_active(false)
        @zoom_100.safe_set_active(false)
        true
      end
    end

    def show_page(page=CPI_Dialog, tab_signal=nil)
      p '---show_page [page, tab_signal]='+[page, tab_signal].inspect
      hide_toolbar_btns
      opt_btns.each do |opt_btn|
        opt_btn.safe_set_active(false) if (opt_btn.is_a?(SafeToggleToolButton))
      end
      cab_notebook.page = page if not tab_signal
      container = cab_notebook.get_nth_page(page)
      sub_btn = opt_btns[CPI_Sub]
      sub_stock = CabPageInfo[CPI_Sub][0]
      stock_id = CabPageInfo[page][0]
      if label_box.stock
        if page==CPI_Property
          label_box.set_stock(opt_btns[page].stock_id)
        else
          label_box.set_stock(stock_id)
        end
      end
      if page<=CPI_Sub
        opt_btns[page].safe_set_active(true)
        sub_btn.stock_id = sub_stock if (sub_btn.stock_id != sub_stock)
      elsif page>CPI_Last_Sub
        opt_btns[page-CPI_Last_Sub+CPI_Sub+1].safe_set_active(true)
        sub_btn.stock_id = sub_stock if (sub_btn.stock_id != sub_stock)
      else
        sub_btn.safe_set_active(true)
        sub_btn.stock_id = stock_id
      end
      prev_page = @active_page
      @active_page = page
      need_init = true
      if container
        container = container.child if page==CPI_Property
        need_init = false if (container.children.size>0)
      end
      if need_init
        case page
          when CPI_Property
            @property_box ||= PropertyBox.new(kind, @fields, cab_panhash, obj_id, edit)
            fill_property_toolbar(property_box)
            property_box.set_status_icons
            #property_box.window_width = property_box.window_height = 0
            p [self.allocation.width, self.allocation.height]
            #property_box.on_resize_window(self.allocation.width, self.allocation.height)
            #property_box.on_resize_window(container.allocation.width, container.allocation.height)
            #container.signal_connect('configure-event') do |widget, event|
            #  property_box.on_resize_window(event.width, event.height)
            #  false
            #end
            container.add(property_box)
          when CPI_Profile
            short_name = ''

            hpaned = Gtk::HPaned.new
            hpaned.border_width = 2

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

            feed = PandoraGtk::ChatTextView.new

            hpaned.pack1(list_sw, false, true)
            hpaned.pack2(feed, true, true)
            list_sw.show_all

            fill_view_toolbar
            container.add(hpaned)
          when CPI_Editor
            #@bodywin = BodyScrolledWindow.new(@fields, nil, nil)
            #bodywin.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            @property_box ||= PropertyBox.new(kind, @fields, cab_panhash, obj_id, edit)
            fill_edit_toolbar
            if property_box.text_fields.size>0
              p property_box.text_fields
              first_body_fld = property_box.text_fields[0]
              if first_body_fld
                bodywin = first_body_fld[FI_Widget2]
                bodywin.fill_body
                container.add(bodywin)
                bodywin.edit_btn.safe_set_active((not bodywin.view_mode)) if bodywin.edit_btn
              end
            end
          when CPI_Dialog, CPI_Chat
            listsend_vpaned = Gtk::VPaned.new

            @area_recv = ViewDrawingArea.new(self)
            area_recv.set_size_request(0, -1)
            area_recv.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#707070'))

            res = area_recv.signal_connect('expose-event') do |*args|
              #p 'area_recv '+area_recv.window.xid.inspect
              false
            end

            @talkview = PandoraGtk::ChatTextView.new(54)
            talkview.set_readonly(true)
            talkview.set_size_request(200, 200)
            talkview.wrap_mode = Gtk::TextTag::WRAP_WORD

            talkview.buffer.create_tag('you', 'foreground' => $you_color)
            talkview.buffer.create_tag('dude', 'foreground' => $dude_color)
            talkview.buffer.create_tag('you_bold', 'foreground' => $you_color, \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)
            talkview.buffer.create_tag('dude_bold', 'foreground' => $dude_color,  \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)
            talkview.buffer.create_tag('sys', 'foreground' => $sys_color, \
              'style' => Pango::FontDescription::STYLE_ITALIC)
            talkview.buffer.create_tag('sys_bold', 'foreground' => $sys_color,  \
              'weight' => Pango::FontDescription::WEIGHT_BOLD)

            talksw = Gtk::ScrolledWindow.new(nil, nil)
            talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            talksw.add(talkview)

            @edit_box = PandoraGtk::SuperTextView.new
            edit_box.wrap_mode = Gtk::TextTag::WRAP_WORD
            edit_box.set_size_request(200, 70)

            @edit_sw = Gtk::ScrolledWindow.new(nil, nil)
            edit_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
            edit_sw.add(edit_box)

            edit_box.grab_focus

            edit_box.buffer.signal_connect('changed') do |buf|
              send_btn.sensitive = (buf.text != '')
              false
            end

            edit_box.signal_connect('key-press-event') do |widget, event|
              res = false
              if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
              and (not event.state.control_mask?) and (not event.state.shift_mask?) \
              and (not event.state.mod1_mask?)
                send_btn.clicked
                res = true
              elsif (Gdk::Keyval::GDK_Escape==event.keyval)
                edit_box.buffer.text = ''
              elsif ((event.state.shift_mask? or event.state.mod1_mask?) \
              and (event.keyval==65364))  # Shift+Down or Alt+Down
                smile_btn.clicked
                res = true
              elsif ([Gdk::Keyval::GDK_k, Gdk::Keyval::GDK_K, 1740, 1772].include?(event.keyval) \
              and event.state.control_mask?) #k, K, л, Л
                if crypt_btn and (not crypt_btn.destroyed?)
                  crypt_btn.active = (not crypt_btn.active?)
                  res = true
                end
              elsif ([Gdk::Keyval::GDK_g, Gdk::Keyval::GDK_G, 1744, 1776].include?(event.keyval) \
              and event.state.control_mask?) #g, G, п, П
                if sign_btn and (not sign_btn.destroyed?)
                  sign_btn.active = (not sign_btn.active?)
                  res = true
                end
              end
              res
            end

            @send_hpaned = Gtk::HPaned.new
            @area_send = ViewDrawingArea.new(self)
            #area_send.set_size_request(120, 90)
            area_send.set_size_request(0, -1)
            area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#707070'))
            send_hpaned.pack1(area_send, false, true)

            @sender_box = Gtk::VBox.new
            sender_box.pack_start(edit_sw, true, true, 0)

            send_hpaned.pack2(sender_box, true, true)

            list_sw = Gtk::ScrolledWindow.new(nil, nil)
            list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
            list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
            #list_sw.visible = false

            list_store = Gtk::ListStore.new(TrueClass, String)
            #targets[CSI_Persons].each do |person|
            #  user_iter = list_store.append
            #  user_iter[CL_Name] = PandoraUtils.bytes_to_hex(person)
            #end

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

            list_hpaned = Gtk::HPaned.new
            list_hpaned.pack1(list_sw, true, true)
            list_hpaned.pack2(talksw, true, true)
            #motion-notify-event  #leave-notify-event  enter-notify-event
            #list_hpaned.signal_connect('notify::position') do |widget, param|
            #  if list_hpaned.position <= 1
            #    list_tree.set_size_request(0, -1)
            #    list_sw.set_size_request(0, -1)
            #  end
            #end
            list_hpaned.position = 1
            list_hpaned.position = 0

            area_send.add_events(Gdk::Event::BUTTON_PRESS_MASK)
            area_send.signal_connect('button-press-event') do |widget, event|
              if list_hpaned.position <= 1
                list_sw.width_request = 150 if list_sw.width_request <= 1
                list_hpaned.position = list_sw.width_request
              else
                list_sw.width_request = list_sw.allocation.width
                list_hpaned.position = 0
              end
            end

            area_send.signal_connect('visibility_notify_event') do |widget, event_visibility|
              case event_visibility.state
                when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
                  init_video_sender(true, true) if not area_send.destroyed?
                when Gdk::EventVisibility::FULLY_OBSCURED
                  init_video_sender(false, true, false) if not area_send.destroyed?
              end
            end

            area_send.signal_connect('destroy') do |*args|
              init_video_sender(false)
            end

            listsend_vpaned.pack1(list_hpaned, true, true)
            listsend_vpaned.pack2(send_hpaned, false, true)

            @main_hpaned = Gtk::HPaned.new
            main_hpaned.pack1(area_recv, false, true)
            main_hpaned.pack2(listsend_vpaned, true, true)

            area_recv.signal_connect('visibility_notify_event') do |widget, event_visibility|
              #p 'visibility_notify_event!!!  state='+event_visibility.state.inspect
              case event_visibility.state
                when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
                  init_video_receiver(true, true, false) if not area_recv.destroyed?
                when Gdk::EventVisibility::FULLY_OBSCURED
                  init_video_receiver(false, true) if not area_recv.destroyed?
              end
            end

            #area_recv.signal_connect('map') do |widget, event|
            #  p 'show!!!!'
            #  init_video_receiver(true, true, false) if not area_recv.destroyed?
            #end

            area_recv.signal_connect('destroy') do |*args|
              init_video_receiver(false, false)
            end

            fill_dlg_toolbar(page)

            load_history($load_history_count, $sort_history_mode)
            container.add(main_hpaned)
          when CPI_Opinions
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Message, nil, pbox, false, \
              'destination='+panhash)
            container.add(pbox)
          when CPI_Relations
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Relation, nil, pbox, false, \
              'first='+panhash+' OR second='+panhash)
            container.add(pbox)
          when CPI_Signs
            pbox = PandoraGtk::PanobjScrolledWindow.new
            panhash = PandoraUtils.bytes_to_hex(cab_panhash)
            PandoraGtk.show_panobject_list(PandoraModel::Sign, nil, pbox, false, \
              'obj_hash='+panhash)
            container.add(pbox)
        end
      else
        case page
          when CPI_Editor
            if (prev_page == @active_page) and property_box \
            and property_box.text_fields and (property_box.text_fields.size>0)
              first_body_fld = property_box.text_fields[0]
              if first_body_fld
                bodywin = first_body_fld[FI_Widget2]
                if bodywin.edit_btn
                  bodywin.edit_btn.active = (not bodywin.edit_btn.active?)
                end
              end
            end
        end
      end
      container.show_all
      show_toolbar_btns(page)
    end

    # Show cabinet
    # RU: Показать кабинет
    def initialize(a_panhash, a_room_id, a_page=nil, a_fields=nil, an_id=nil, \
    an_edit=nil, a_session=nil)
      super(nil, nil)

      p '==Cabinet.new a_panhash='+PandoraUtils.bytes_to_hex(a_panhash)

      @cab_panhash = a_panhash
      @kind = PandoraUtils.kind_from_panhash(cab_panhash)
      @session = a_session
      @room_id = a_room_id
      @fields = a_fields
      @obj_id = an_id
      @edit = an_edit

      @has_unread = false
      @recv_media_queue = Array.new
      @recv_media_pipeline = Array.new
      @appsrcs = Array.new
      @add_toolbar_btns = Array.new

      #set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #border_width = 0

      dlg_stock = nil
      its_blob = nil
      if cab_panhash
        kind = PandoraUtils.kind_from_panhash(cab_panhash)
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        its_blob = ((kind==PandoraModel::PK_Blob) \
          or (panobjectclass <= PandoraModel::Blob) \
          or panobjectclass.has_blob_fields?)
        dlg_stock = $window.get_panobject_stock(panobjectclass.ider)
      end
      dlg_stock ||= Gtk::Stock::PROPERTIES

      main_vbox = self #Gtk::VBox.new
      #add_with_viewport(main_vbox)

      @cab_notebook = Gtk::Notebook.new
      cab_notebook.show_tabs = false
      cab_notebook.show_border = false
      cab_notebook.border_width = 0
      @toolbar_box = Gtk::HBox.new #Toolbar.new HBox.new
      main_vbox.pack_start(cab_notebook, true, true, 0)

      @opt_btns = []
      btn_down = nil
      (CPI_Property..CPI_Last).each do |index|
        container = nil
        if index==CPI_Property
          stock = dlg_stock
          stock ||= CabPageInfo[index][0]
          text = CabPageInfo[index][1]
          container = Gtk::ScrolledWindow.new(nil, nil)
          container.shadow_type = Gtk::SHADOW_NONE
          container.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          container.border_width = 0
          viewport = Gtk::Viewport.new(nil, nil)
          container.add(viewport)
        else
          stock = CabPageInfo[index][0]
          text = CabPageInfo[index][1]
          if index==CPI_Last_Sub+1
            btn_down.menu.show_all
            btn_down = nil
          end
        end
        text = _(text)
        page_box = TabLabelBox.new(stock, text)
        container ||= Gtk::Viewport.new(nil, nil)
        cab_notebook.append_page_menu(container, page_box)

        if not btn_down
          opt_btn = add_btn_to_toolbar(stock, text, false, opt_btns) do
            show_page(index)
          end
          if index==CPI_Sub
            btn_down = add_btn_to_toolbar(nil, nil, 0, opt_btns)
            btn_down.menu = Gtk::Menu.new
          end
        end
        if btn_down
          add_menu_item(btn_down, btn_down.menu, stock, text) do
            show_page(index)
          end
        end
      end
      cab_notebook.signal_connect('switch-page') do |widget, page, page_num|
        #container = widget.get_nth_page(page_num)
        #show_page(page_num, true)
      end

      #toolbar_box.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      #toolbar_box.add(Gtk::SeparatorToolItem.new)
      add_btn_to_toolbar(nil, nil, nil, opt_btns)
      main_vbox.pack_start(toolbar_box, false, false, 0)

      p Gtk::IconSize.lookup(Gtk::IconSize::SMALL_TOOLBAR)
      dlg_pixbuf = PandoraModel.get_avatar_icon(cab_panhash, self, its_blob, \
        Gtk::IconSize.lookup(Gtk::IconSize::SMALL_TOOLBAR)[0])
      #buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
      dlg_image = nil
      dlg_image = Gtk::Image.new(dlg_pixbuf) if dlg_pixbuf
      #dlg_image ||= $window.get_preset_image('dialog')
      dlg_image ||= dlg_stock
      dlg_image ||= Gtk::Stock::MEDIA_PLAY
      @label_box = TabLabelBox.new(dlg_image, 'unknown', self) do
        area_send.destroy if area_send and (not area_send.destroyed?)
        area_recv.destroy if area_recv and (not area_recv.destroyed?)
        $window.pool.stop_session(nil, cab_panhash, nil, false, self.session)
      end

      page = $window.notebook.append_page(self, label_box)
      $window.notebook.set_tab_reorderable(self, true)

      construct_cab_title

      self.signal_connect('delete-event') do |*args|
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end

      show_all
      a_page ||= CPI_Dialog
      show_page(a_page)
      opt_btns[CPI_Sub+1].children[0].children[0].hide
      btn_offset = CPI_Last_Sub-CPI_Sub-1
      opt_btns[CPI_Editor-btn_offset].hide if (not its_blob)
      opt_btns[CPI_Dialog-btn_offset].hide if (kind != PandoraModel::PK_Person)

      $window.notebook.page = $window.notebook.n_pages-1 if not @known_node
    end

    MaxTitleLen = 15

    # Construct room title
    # RU: Задаёт осмысленный заголовок окна
    def construct_cab_title(check_all=true, atitle_view=nil)

      def trunc_big_title(title)
        title.strip! if title
        if title.size>MaxTitleLen
          need_dots = (title[MaxTitleLen] != ' ')
          len = MaxTitleLen
          len -= 1 if need_dots
          need_dots = (title[len-1] != ' ')
          title = title[0, len].strip
          title << '..' if need_dots
        end
        title
      end

      res = 'unknown'
      if (kind==PandoraModel::PK_Person)
        title_view = atitle_view
        title_view ||= $window.title_view
        title_view ||= TV_Name
        res = ''
        aname, afamily = PandoraCrypto.name_and_family_of_person(nil, cab_panhash)
        #p '------------[aname, afamily, cab_panhash]='+[aname, afamily, cab_panhash, \
        #  PandoraUtils.bytes_to_hex(cab_panhash)].inspect
        addname = ''
        case title_view
          when TV_Name, TV_NameN
            if (aname.size==0)
              addname << afamily
            else
              addname << aname
            end
          when TV_Family
            if (afamily.size==0)
              addname << aname
            else
              addname << afamily
            end
          when TV_NameFam
            if (aname.size==0)
              addname << afamily
            else
              addname << aname #[0, 4]
              addname << ' '+afamily if afamily and (afamily.size>0)
            end
        end
        if (addname.size>0)
          res << ',' if (res.size>0)
          res << addname
        end
        res = 'unknown' if (res.size==0)
        res = trunc_big_title(res)
        tab_widget = $window.notebook.get_tab_label(self)
        tab_widget.label.text = res if tab_widget
        #p '$window.title_view, res='+[@$window.title_view, res].inspect
        if check_all
          title_view=TV_Name if (title_view==TV_NameN)
          has_conflict = true
          while has_conflict and (title_view < TV_NameN)
            has_conflict = false
            names = Array.new
            $window.notebook.children.each do |child|
              if (child.is_a? CabinetBox)
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
              if (title_view < TV_NameN)
                title_view += 1
              end
              #p '@$window.title_view='+@$window.title_view.inspect
              names = Array.new
              $window.notebook.children.each do |child|
                if (child.is_a? CabinetBox)
                  sn = child.construct_cab_title(false, title_view)
                  if (title_view == TV_NameN)
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
      else
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass
          model = PandoraUtils.get_model(panobjectclass.ider)
          if model
            sel = model.select({'panhash'=>cab_panhash}, true, nil, nil, 1)
            res = model.record_info(MaxTitleLen+1, nil, nil, ' ')
            res = trunc_big_title(res)
            tab_widget = $window.notebook.get_tab_label(self)
            tab_widget.label.text = res if tab_widget
          end
        end
      end
      res
    end

    # Put message to dialog
    # RU: Добавляет сообщение в диалог
    def add_mes_to_view(mes, id, panstate=nil, to_end=nil, key_or_panhash=nil, \
    myname=nil, modified=nil, created=nil)
      if mes
        encrypted = ((panstate.is_a? Integer) \
          and ((panstate & PandoraModel::PSF_Crypted) > 0))
        mes = PandoraCrypto.recrypt_mes(mes) if encrypted

        p '---add_mes_to_view [mes, id, pstate to_end, key_or_phash, myname, modif, created]=' + \
          [mes, id, panstate, to_end, key_or_panhash, myname, modified, created].inspect

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
        end
        user_name = 'noname' if (not user_name) or (user_name=='')

        time_now = Time.now
        created = time_now if (not modified) and (not created)

        time_str = ''
        time_str << PandoraUtils.time_to_dialog_str(created, time_now) if created
        if modified and ((not created) or ((modified.to_i-created.to_i).abs>30))
          time_str << ' ' if (time_str != '')
          time_str << '('+PandoraUtils.time_to_dialog_str(modified, time_now)+')'
        end

        talkview.before_addition(time_now) if (not to_end.is_a? FalseClass)
        talkview.buffer.insert(talkview.buffer.end_iter, "\n") if (talkview.buffer.char_count>0)
        talkview.buffer.insert(talkview.buffer.end_iter, time_str+' ', time_style)
        talkview.buffer.insert(talkview.buffer.end_iter, user_name+':', name_style)

        line = talkview.buffer.line_count
        talkview.mes_ids[line] = id

        talkview.buffer.insert(talkview.buffer.end_iter, ' ')
        talkview.insert_taged_str_to_buffer(mes, talkview.buffer, 'bbcode')
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
        fields = 'creator, created, destination, state, text, panstate, modified, id'

        mypanhash = PandoraCrypto.current_user_or_key(true)
        myname = PandoraCrypto.short_name_of_person(nil, mypanhash)

        nil_create_time = false
        person = cab_panhash
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
          panstate = message[5]
          modified = message[6]
          id = message[7]

          key_or_panhash = nil
          key_or_panhash = creator if (creator != mypanhash)

          add_mes_to_view(mes, id, panstate, false, key_or_panhash, myname, modified, created)
          i += 1
        end
        talkview.after_addition(true)
        talkview.show_all
        # Scroll because of the unknown gtk bug
        mark = talkview.buffer.create_mark(nil, talkview.buffer.end_iter, false)
        talkview.scroll_to_mark(mark, 0, true, 0.0, 1.0)
        talkview.buffer.delete_mark(mark)
      end
    end

    # Set session
    # RU: Задать сессию
    def set_session(session, online=true, keep=true)
      p '***---- set_session(session, online)='+[session.object_id, online].inspect
      @sessions ||= []
      if online
        @sessions << session if (not @sessions.include?(session))
        session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep) if keep
      else
        @sessions.delete(session)
        session.conn_mode = (session.conn_mode & (~PandoraNet::CM_Keep)) if keep
        session.dialog = nil
      end
      active = (@sessions.size>0)
      online_btn.safe_set_active(active) if (online_btn and (not online_btn.destroyed?))
      if active
        #online_btn.inconsistent = false if (not online_btn.destroyed?)
      else
        mic_btn.active = false if (not mic_btn.destroyed?) and mic_btn.active?
        webcam_btn.active = false if (not webcam_btn.destroyed?) and webcam_btn.active?
        #mic_btn.safe_set_active(false) if (not mic_btn.destroyed?)
        #webcam_btn.safe_set_active(false) if (not webcam_btn.destroyed?)
      end
    end

    # Send message to node, before encrypt it if need
    # RU: Отправляет сообщение на узел, шифрует предварительно если надо
    def send_mes(text, crypt=nil, sign_trust=nil)
      res = false
      creator = PandoraCrypto.current_user_or_key(true)
      if creator
        online_btn.active = true if (not online_btn.active?)
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        panstate = 0
        crypt_text = text
        sign = (not sign_trust.nil?)
        if crypt or sign
          panstate = (panstate | PandoraModel::PSF_Support)
          keyhash = PandoraCrypto.current_user_or_key(false, false)
          if keyhash
            if crypt
              crypt_text = PandoraCrypto.recrypt_mes(text, keyhash)
              panstate = (panstate | PandoraModel::PSF_Crypted)
            end
            panstate = (panstate | PandoraModel::PSF_Verified) if sign
          else
            crypt = sign = false
          end
        end
        dest = cab_panhash
        values = {:destination=>dest, :text=>crypt_text, :state=>state, \
          :creator=>creator, :created=>time_now, :modified=>time_now, :panstate=>panstate}
        model = PandoraUtils.get_model('Message')
        panhash = model.calc_panhash(values)
        values[:panhash] = panhash
        res = model.update(values, nil, nil, sign)
        if res
          filter = {:panhash=>panhash, :created=>time_now}
          sel = model.select(filter, true, 'id', 'id DESC', 1)
          if sel and (sel.size>0)
            p 'send_mes sel='+sel.inspect
            if sign
              namesvalues = model.namesvalues
              namesvalues['text'] = text   #restore pure text for sign
              if not PandoraCrypto.sign_panobject(model, sign_trust)
                panstate = panstate & (~ PandoraModel::PSF_Verified)
                res = model.update(filter, nil, {:panstate=>panstate})
                PandoraUtils.log_message(LM_Warning, _('Cannot create sign')+' ['+text+']')
              end
            end
            id = sel[0][0]
            add_mes_to_view(crypt_text, id, panstate, true)
          else
            PandoraUtils.log_message(LM_Error, _('Cannot read message')+' ['+text+']')
          end
        else
          PandoraUtils.log_message(LM_Error, _('Cannot insert message')+' ['+text+']')
        end
        sessions = $window.pool.sessions_on_dialog(self)
        sessions.each do |session|
          session.conn_mode = (session.conn_mode | PandoraNet::CM_Keep)
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
        if $last_page and ($last_page.is_a? CabinetBox) \
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
        if (not self.read_thread) and (curpage == self) and $window.visible? \
        and $window.has_toplevel_focus?
          #color = $window.modifier_style.text(Gtk::STATE_NORMAL)
          #curcolor = tab_widget.label.modifier_style.fg(Gtk::STATE_ACTIVE)
          if @has_unread #curcolor and (color != curcolor)
            timer_setted = true
            self.read_thread = Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.edit_box.destroyed?)
                curpage.edit_box.grab_focus if curpage.edit_box.visible?
                curpage.talkview.after_addition(true)
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
        # set focus to edit_box
        if curpage and (curpage.is_a? CabinetBox) and curpage.edit_box
          if not timer_setted
            Thread.new do
              sleep(0.3)
              if (not curpage.destroyed?) and (not curpage.edit_box.destroyed?)
                curpage.edit_box.grab_focus if curpage.edit_box.visible?
              end
            end
          end
          Thread.pass
          curpage.edit_box.grab_focus if curpage.edit_box.visible?
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
        while (i+j<text.size) \
        and (not ([' ', '=', "\\", '!', '/', 10.chr, 13.chr].include? text[i+j, 1]))
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
            while (i+j<text.size) and (quotes \
            or (not ([' ', "\\", '!', 10.chr, 13.chr].include? text[i+j, 1])))
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
        if (not area.destroyed?) and area.window and sink \
        and (sink.class.method_defined? 'set_xwindow_id')
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
    def init_video_sender(start=true, just_upd_area=false, init=true)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and (PandoraUtils.elem_playing?($webcam_xvimagesink))
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          area_send.set_expose_event(nil) if init
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
          count = PandoraGtk.nil_send_ptrind_by_panhash(room_id)
          if video_pipeline and (count==0) and (not PandoraUtils::elem_stopped?(video_pipeline))
            video_pipeline.stop
            area_send.set_expose_event(nil)
            #p '==STOP!!'
          end
        end
        #Thread.pass
      elsif (not self.destroyed?) and webcam_btn and (not webcam_btn.destroyed?) and webcam_btn.active? \
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
                #p 'appsink new buf!!!'
                #buf = appsink.pull_preroll
                #buf = appsink.pull_sample
                buf = appsink.pull_buffer
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
            puts mes+': '+Utf8String.new(err.message)
            webcam_btn.active = false
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
            video_pipeline.play if (not PandoraUtils.elem_playing?(video_pipeline))
          else
            ptrind = PandoraGtk.set_send_ptrind_by_panhash(room_id)
            count = PandoraGtk.nil_send_ptrind_by_panhash(nil)
            if count>0
              #Gtk.main_iteration
              #???
              p 'PLAAAAAAAAAAAAAAY 1'
              p PandoraUtils.elem_playing?(video_pipeline)
              video_pipeline.play if (not PandoraUtils.elem_playing?(video_pipeline))
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
      p '--init_video_receiver [start, can_play, init]='+[start, can_play, init].inspect
      if not start
        if ximagesink and PandoraUtils.elem_playing?(ximagesink)
          if can_play
            ximagesink.pause
          else
            ximagesink.stop
          end
        end
        if (not can_play) or (not ximagesink)
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
            puts mes+': '+Utf8String.new(err.message)
            webcam_btn.active = false
          end
        end

        if @ximagesink and init #and area_recv.window
          link_sink_to_area(@ximagesink, area_recv, recv_media_pipeline[1])
        end

        #p '[recv_media_pipeline[1], can_play]='+[recv_media_pipeline[1], can_play].inspect
        if recv_media_pipeline[1] and can_play and area_recv.window
          #if (not area_recv.expose_event) and
          if (not PandoraUtils.elem_playing?(recv_media_pipeline[1])) \
          or (not PandoraUtils.elem_playing?(ximagesink))
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
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+mic_btn.active?.inspect
      if not start
        #count = PandoraGtk.nil_send_ptrind_by_panhash(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (not PandoraUtils::elem_stopped?(audio_pipeline))
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not mic_btn.destroyed?) and mic_btn.active?
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
            puts mes+': '+Utf8String.new(err.message)
            mic_btn.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGtk.set_send_ptrind_by_panhash(room_id)
          count = PandoraGtk.nil_send_ptrind_by_panhash(nil)
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
            puts mes+': '+Utf8String.new(err.message)
            mic_btn.active = false
          end
          recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
        end
        if recv_media_pipeline[0] and can_play
          recv_media_pipeline[0].play if (not PandoraUtils::elem_playing?(recv_media_pipeline[0]))
        end
      end
    end
  end  #--class CabinetBox

  # Search panel
  # RU: Панель поиска
  class SearchBox < Gtk::VBox #Gtk::ScrolledWindow
    attr_accessor :text

    include PandoraGtk

    def show_all_reqs(reqs=nil)
      pool = $window.pool
      if reqs or (not @last_mass_ind) or (@last_mass_ind < pool.mass_ind)
        @list_store.clear
        reqs ||= pool.mass_records
        p '-----------reqs='+reqs.inspect
        reqs.each do |mr|
          if (mr.is_a? Array) and (mr[PandoraNet::MR_Kind] == PandoraNet::MK_Search)
            user_iter = @list_store.append
            user_iter[0] = mr[PandoraNet::MR_Index]
            user_iter[1] = Utf8String.new(mr[PandoraNet::MRS_Request])
            user_iter[2] = Utf8String.new(mr[PandoraNet::MRS_Kind])
            user_iter[3] = Utf8String.new(mr[PandoraNet::MRA_Answer].inspect)
          end
        end
        if reqs
          @last_mass_ind = nil
        else
          @last_mass_ind = pool.mass_ind
        end
      end
    end

    # Show search window
    # RU: Показать окно поиска
    def initialize(text=nil)
      super #(nil, nil)

      @text = nil

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

      @list_store = Gtk::ListStore.new(Integer, String, String, String)

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
        empty = (search_entry.text.size==0)
        PandoraGtk.set_readonly(search_btn, empty)
        if empty
          show_all_reqs
        else
          if @last_mass_ind
            @list_store.clear
            @last_mass_ind = nil
          end
        end
        false
      end

      kind_entry = Gtk::Combo.new
      kind_list = PandoraModel.get_kind_list
      name_list = []
      name_list << 'auto'
      #name_list.concat( kind_list.collect{ |rec| rec[2] + ' ('+rec[0].to_s+'='+rec[1]+')' } )
      name_list.concat( kind_list.collect{ |rec| rec[1] } )
      kind_entry.set_popdown_strings(name_list)
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

      toolbar_box = Gtk::HBox.new

      vbox.pack_start(hbox, false, true, 0)
      vbox.pack_start(toolbar_box, false, true, 0)

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
        search_btn.clicked if local_btn.active?
      end
      local_btn.safe_set_active(true)

      active_btn = SafeCheckButton.new(_('active only'), true)
      active_btn.safe_signal_clicked do |widget|
        search_btn.clicked if active_btn.active?
      end
      active_btn.safe_set_active(true)

      hunt_btn = SafeCheckButton.new(_('hunt!'), true)
      hunt_btn.safe_signal_clicked do |widget|
        search_btn.clicked if hunt_btn.active?
      end
      hunt_btn.safe_set_active(true)

      toolbar_box.pack_start(local_btn, false, false, 1)
      toolbar_box.pack_start(active_btn, false, false, 1)
      toolbar_box.pack_start(hunt_btn, false, false, 1)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)

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
        request = search_entry.text
        search_entry.position = search_entry.position  # deselect
        if (request.size>0)
          kind = kind_entry.entry.text
          PandoraGtk.set_readonly(stop_btn, false)
          PandoraGtk.set_readonly(widget, true)
          #bases = kind
          #local_btn.active?  active_btn.active?  hunt_btn.active?
          if (kind=='Blob') and PandoraUtils.hex?(request)
            kind = PandoraModel::PK_BlobBody
            request = PandoraUtils.hex_to_bytes(request)
            p 'Search: Detect blob search  kind,sha1='+[kind,request].inspect
          end
          #reqs = $window.pool.add_search_request(request, kind, nil, nil, true)
          reqs = $window.pool.add_mass_record(PandoraNet::MK_Search, kind, request)
          show_all_reqs(reqs)
          PandoraGtk.set_readonly(stop_btn, true)
          PandoraGtk.set_readonly(widget, false)
          PandoraGtk.set_readonly(prev_btn, false)
          PandoraGtk.set_readonly(next_btn, true)
        end
        false
      end
      show_all_reqs

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
      list_tree = Gtk::TreeView.new(@list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
      column.set_sort_column_id(0)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Request'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Kind'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Answer'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vbox.pack_start(list_sw, true, true, 0)
      list_sw.show_all

      PandoraGtk.hack_grab_focus(search_entry)
    end
  end

  # Profile panel
  # RU: Панель кабинета
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
          hunter = session.hunter?
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
      opts = nil
      stock = mi[1]
      stock, opts = PandoraGtk.detect_icon_opts(stock) if stock
      if stock and opts and opts.index('m')
        stock = stock.to_sym if stock.is_a? String
        $window.register_stock(stock, nil, text)
        menuitem = Gtk::ImageMenuItem.new(stock)
        label = menuitem.children[0]
        label.set_text(text, true)
      else
        menuitem = Gtk::MenuItem.new(text)
      end
      if menuitem
        if (not treeview) and mi[3]
          key, mod = Gtk::Accelerator.parse(mi[3])
          menuitem.add_accelerator('activate', $window.accel_group, key, \
            mod, Gtk::ACCEL_VISIBLE) if key
        end
        command = mi[0]
        if command and (command.size>0) and (command[0]=='>')
          command = command[1..-1]
          command = nil if command==''
        end
        #menuitem.name = mi[0]
        PandoraUtils.set_obj_property(menuitem, 'command', command)
        PandoraGtk.set_bold_to_menuitem(menuitem) if opts and opts.index('b')
        menuitem.signal_connect('activate') { |widget| $window.do_menu_act(widget, treeview) }
      end
    end
    menuitem
  end

  # List of fishes
  # RU: Список рыб
  class RadarScrollWin < Gtk::ScrolledWindow
    attr_accessor :update_btn

    include PandoraGtk

    MASS_KIND_ICONS = ['hunt', 'chat', 'request', 'fish']

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
      list_sw.shadow_type = Gtk::SHADOW_NONE
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, String, String, String, String, \
        Integer, Integer, Integer, String, String, Integer)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        if $window.pool
          $window.pool.mass_records.each do |mr|
            p '---mr:'
            p mr[0..6]
            anode = mr[PandoraNet::MR_Node]
            akey, abaseid, aperson = $window.pool.get_node_params(anode)
            if aperson or akey
              sess_iter = list_store.append
              akind = mr[PandoraNet::MR_Kind]
              anick = nil
              anick = mr[PandoraNet::MRP_Nick] if (akind == PandoraNet::MK_Presence)
              if anick.nil? and aperson
                anick = PandoraCrypto.short_name_of_person(nil, aperson, 1)
              end
              anick = akind.to_s if anick.nil?
              sess_iter[0] = akind
              sess_iter[1] = anick
              sess_iter[2] = PandoraUtils.bytes_to_hex(aperson)
              sess_iter[3] = PandoraUtils.bytes_to_hex(akey)
              sess_iter[4] = PandoraUtils.bytes_to_hex(abaseid)
              sess_iter[5] = mr[PandoraNet::MR_Trust]
              sess_iter[6] = mr[PandoraNet::MR_Depth]
              sess_iter[7] = 0 #distance
              sess_iter[8] = PandoraUtils.bytes_to_hex(anode)
              sess_iter[9] = PandoraUtils.time_to_str(mr[PandoraNet::MR_CrtTime])
              sess_iter[10] = mr[PandoraNet::MR_Index]
            end
          end
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      kind_pbs = []
      MASS_KIND_ICONS.each_with_index do |v, i|
        kind_pbs[i] = $window.get_icon_scale_buf(v, 'pan', 16)
      end

      kind_image = Gtk::Image.new(Gtk::Stock::CONNECT, Gtk::IconSize::MENU)
      kind_image.show_all
      renderer = Gtk::CellRendererPixbuf.new
      column = Gtk::TreeViewColumn.new('', renderer)
      column.widget = kind_image
      #column.set_sort_column_id(0)
      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        kind = nil
        kind = iter[0] if model.iter_is_valid?(iter) and iter and iter.path
        kind ||= 1
        if kind
          pixbuf = kind_pbs[kind-1]
          pixbuf = nil if pixbuf==false
          renderer.pixbuf = pixbuf
        end
      end
      column.fixed_width = 20
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Nick'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Person'), renderer, 'text' => 2)
      column.set_sort_column_id(2)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Key'), renderer, 'text' => 3)
      column.set_sort_column_id(3)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('BaseID'), renderer, 'text' => 4)
      column.set_sort_column_id(4)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Trust'), renderer, 'text' => 5)
      column.set_sort_column_id(5)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Depth'), renderer, 'text' => 6)
      column.set_sort_column_id(6)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Distance'), renderer, 'text' => 7)
      column.set_sort_column_id(7)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 8)
      column.set_sort_column_id(8)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 9)
      column.set_sort_column_id(9)
      list_tree.append_column(column)

      renderer = Gtk::CellRendererText.new
      column = Gtk::TreeViewColumn.new(_('Index'), renderer, 'text' => 10)
      column.set_sort_column_id(10)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        PandoraGtk.act_panobject(list_tree, 'Dialog')
      end

      menu = Gtk::Menu.new
      menu.append(PandoraGtk.create_menu_item(['Dialog', 'dialog:mb', _('Dialog'), '<control>D'], list_tree))
      menu.append(PandoraGtk.create_menu_item(['Relation', :relation, _('Relate'), '<control>R'], list_tree))
      menu.show_all

      list_tree.add_events(Gdk::Event::BUTTON_PRESS_MASK)
      list_tree.signal_connect('button-press-event') do |widget, event|
        if (event.button == 3)
          menu.popup(nil, nil, event.button, event.time)
        end
      end

      list_tree.signal_connect('key-press-event') do |widget, event|
        res = true
        if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
          PandoraGtk.act_panobject(list_tree, 'Dialog')
        elsif (event.keyval==Gdk::Keyval::GDK_Insert)
          if event.state.control_mask?
            #act_panobject(list_tree, 'Copy')
          else
            #act_panobject(list_tree, 'Create')
          end
        elsif (event.keyval==Gdk::Keyval::GDK_Delete)
          #act_panobject(list_tree, 'Delete')
        elsif event.state.control_mask?
          if [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
            PandoraGtk.act_panobject(list_tree, 'Dialog')
            #path, column = list_tree.cursor
            #if path
            #  iter = list_store.get_iter(path)
            #  person = nil
            #  person = iter[0] if iter
            #  person = PandoraUtils.hex_to_bytes(person)
            #  PandoraGtk.show_cabinet(person) if person
            #end
          else
            res = false
          end
        else
          res = false
        end
        res
      end

      list_sw.add(list_tree)
      #image = Gtk::Image.new(Gtk::Stock::GO_FORWARD, Gtk::IconSize::MENU)
      image = Gtk::Image.new(:radar, Gtk::IconSize::SMALL_TOOLBAR)
      image.set_padding(2, 0)
      #image1 = Gtk::Image.new(Gtk::Stock::ORIENTATION_PORTRAIT, Gtk::IconSize::MENU)
      #image1.set_padding(2, 2)
      #image2 = Gtk::Image.new(Gtk::Stock::NETWORK, Gtk::IconSize::MENU)
      #image2.set_padding(2, 2)
      image.show_all
      align = Gtk::Alignment.new(0.0, 0.5, 0.0, 0.0)
      btn_hbox = Gtk::HBox.new
      label = Gtk::Label.new(_('Radar'))
      btn_hbox.pack_start(image, false, false, 0)
      btn_hbox.pack_start(label, false, false, 2)

      close_image = Gtk::Image.new(Gtk::Stock::CLOSE, Gtk::IconSize::MENU)
      btn_hbox.pack_start(close_image, false, false, 2)

      btn = Gtk::Button.new
      btn.relief = Gtk::RELIEF_NONE
      btn.focus_on_click = false
      btn.signal_connect('clicked') do |*args|
        PandoraGtk.show_radar_panel
      end
      btn.add(btn_hbox)
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

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

      list_store = Gtk::ListStore.new(Integer, String, String, String, String, String, \
        String, String)

      update_btn.signal_connect('clicked') do |*args|
        list_store.clear
        $window.pool.mass_records.each do |mr|
          sess_iter = list_store.append
          sess_iter[0] = mr[PandoraNet::MR_Index]
          sess_iter[1] = PandoraUtils.bytes_to_hex(mr[PandoraNet::MR_Node])
          sess_iter[2] = PandoraUtils.time_to_str(mr[PandoraNet::MR_CrtTime])
        end
      end

      # create tree view
      list_tree = Gtk::TreeView.new(list_store)
      #list_tree.rules_hint = true
      #list_tree.search_column = CL_Name

      #mass_ind, session, fisher, fisher_key, fisher_baseid, fish, fish_key, time]

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
  def self.set_readonly(widget, value=true, set_sensitive=true)
    value = (not value)
    widget.editable = value if widget.class.method_defined? 'editable?'
    widget.sensitive = value if set_sensitive and (widget.class.method_defined? 'sensitive?')
    #widget.can_focus = value
    #widget.has_focus = value if widget.class.method_defined? 'has_focus?'
    #widget.can_focus = (not value) if widget.class.method_defined? 'can_focus?'
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

  def self.find_tool_btn(toolbar, title)
    res = nil
    if toolbar
      lang_title = _(title)
      i = 0
      while (i<toolbar.children.size) and (not res)
        ch = toolbar.children[i]
        if (((ch.is_a? Gtk::ToolButton) or (ch.is_a? Gtk::ToggleToolButton)) \
        and ((ch.label == title) or (ch.label == lang_title)))
          res = ch
          break
        end
        i += 1
      end
    end
    res
  end

  $update_lag = 30    #time lag (sec) for update after run the programm
  $download_thread = nil

  UPD_FileList = ['model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'pandora.bat']
  UPD_FileList.concat(['model/03-language-'+$lang+'.xml', 'lang/'+$lang+'.txt']) if ($lang and ($lang != 'en'))

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    def self.connect_http_and_check_size(url, curr_size, step)
      time = nil
      http, host, path = PandoraNet.http_connect(url)
      if http
        new_size = PandoraNet.http_size_from_header(http, path, false)
        if not new_size
          sleep(0.5)
          new_size = PandoraNet.http_size_from_header(http, path, false)
        end
        if new_size
          PandoraUtils.set_param('last_check', Time.now)
          p 'Size diff: '+[new_size, curr_size].inspect
          if (new_size == curr_size)
            http = nil
            step = 254
            $window.set_status_field(SF_Update, 'Ok', false)
            PandoraUtils.set_param('last_update', Time.now)
          else
            time = Time.now.to_i
          end
        else
          http = nil
        end
      end
      if not http
        $window.set_status_field(SF_Update, 'Connection error')
        PandoraUtils.log_message(LM_Info, _('Cannot connect to repo to check update')+\
          ' '+[host, path].inspect)
      end
      [http, time, step, host, path]
    end

    def self.reconnect_if_need(http, time, url)
      http = PandoraNet.http_reconnect_if_need(http, time, url)
      if not http
        $window.set_status_field(SF_Update, 'Connection error')
        PandoraUtils.log_message(LM_Warning, _('Cannot reconnect to repo to update'))
      end
      http
    end

    # Update file
    # RU: Обновить файл
    def self.update_file(http, path, pfn, host='')
      res = false
      dir = File.dirname(pfn)
      FileUtils.mkdir_p(dir) unless Dir.exists?(dir)
      if Dir.exists?(dir)
        filebody = PandoraNet.http_get_body_from_path(http, path, host)
        if filebody and (filebody.size>0)
          begin
            File.open(pfn, 'wb+') do |file|
              file.write(filebody)
              res = true
              PandoraUtils.log_message(LM_Info, _('File updated')+': '+pfn)
            end
          rescue => err
            PandoraUtils.log_message(LM_Warning, _('Update error')+': '+Utf8String.new(err.message))
          end
        else
          PandoraUtils.log_message(LM_Warning, _('Empty downloaded body'))
        end
      else
        PandoraUtils.log_message(LM_Warning, _('Cannot create directory')+': '+dir)
      end
      res
    end

    if $download_thread and $download_thread.alive?
      $download_thread[:all_step] = all_step
      $download_thread.run if $download_thread.stop?
    else
      $download_thread = Thread.new do
        Thread.current[:all_step] = all_step
        downloaded = false
        $window.set_status_field(SF_Update, 'Need check')
        sleep($update_lag) if not Thread.current[:all_step]
        $window.set_status_field(SF_Update, 'Checking')

        main_script = File.join($pandora_app_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          if File.stat(main_script).writable?
            update_zip = PandoraUtils.get_param('update_zip_first')
            update_zip = true if update_zip.nil?

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
                      zip_url = 'https://bitbucket.org/robux/pandora/get/master.zip'
                      dir_in_zip = 'robux-pandora'
                      http, time, step, host, path = connect_http_and_check_size(zip_url, \
                        zip_size, step)
                      if http
                        PandoraUtils.log_message(LM_Info, _('Need update'))
                        $window.set_status_field(SF_Update, 'Need update')
                        Thread.stop
                        http = reconnect_if_need(http, time, zip_url)
                        if http
                          $window.set_status_field(SF_Update, 'Doing')
                          res = update_file(http, path, zip_local, host)
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
                                  p 'Copy '+unzip_path+' to '+$pandora_app_dir
                                  #FileUtils.copy_entry(unzip_path, $pandora_app_dir, true)
                                  FileUtils.cp_r(unzip_path+'/.', $pandora_app_dir)
                                  PandoraUtils.log_message(LM_Info, _('Files are updated'))
                                rescue => err
                                  res = false
                                  PandoraUtils.log_message(LM_Warning, _('Cannot copy files from zip arch')+': '+Utf8String.new(err.message))
                                end
                                # Remove used arch dir
                                begin
                                  FileUtils.remove_dir(unzip_path)
                                rescue => err
                                  PandoraUtils.log_message(LM_Warning, _('Cannot remove arch dir')+' ['+unzip_path+']: '+Utf8String.new(err.message))
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
                url = 'https://raw.githubusercontent.com/Novator/Pandora/master/pandora.rb'
                http, time, step, host, path = connect_http_and_check_size(url, \
                  curr_size, step)
                if http
                  PandoraUtils.log_message(LM_Info, _('Need update'))
                  $window.set_status_field(SF_Update, 'Need update')
                  Thread.stop
                  http = reconnect_if_need(http, time, url)
                  if http
                    $window.set_status_field(SF_Update, 'Doing')
                    # updating pandora.rb
                    downloaded = update_file(http, path, main_script, host)
                    # updating other files
                    UPD_FileList.each do |fn|
                      pfn = File.join($pandora_app_dir, fn)
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
              #Kernel.abort('Pandora is updated. Run it again')
              puts 'Pandora is updated. Restarting..'
              PandoraNet.start_or_stop_listen(false, true)
              PandoraNet.start_or_stop_hunt(false) if $hunter_thread
              $window.pool.close_all_session
              PandoraUtils.restart_app
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

  # Get icon associated with panobject
  # RU: Взять иконку ассоциированную с панобъектом
  def self.get_panobject_icon(panobj)
    panobj_icon = nil
    if panobj
      ider = panobj
      ider = panobj.ider if (not panobj.is_a? String)
      image = nil
      image = $window.get_panobject_image(ider, Gtk::IconSize::DIALOG) if $window
      if image
        style = Gtk::Widget.default_style
        panobj_icon = image.icon_set.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
          Gtk::STATE_NORMAL, Gtk::IconSize::DIALOG)
      end
    end
    panobj_icon
  end

  # Do action with selected record
  # RU: Выполнить действие над выделенной записью
  def self.act_panobject(tree_view, action)

    # Set delete dialog wigets (checkboxes and text)
    # RU: Задать виджеты диалога удаления (чекбоксы и текст)
    def self.set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
      text = nil
      if arch_cb and arch_cb.active?
        if keep_cb.active?
          text = _('Stay record in archive with "Keep" flag')
        else
          text = _('Move record to archive. Soon will be deleted by garbager')
        end
      elsif ignore_cb.active?
        text = _('Delete record physically')+'. '+\
          _('Also create Relation "Ignore"')
      else
        text = _('Delete record physically')
      end
      dialog.secondary_text = text if text
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
      #p 'panobject='+panobject.inspect
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
        if panobject  # SubjTreeView
          id = iter[0]
          sel = panobject.select('id='+id.to_s, true)
          panhash0 = panobject.namesvalues['panhash']
          panstate = panobject.namesvalues['panstate']
          panstate ||= 0
          if (panobject.is_a? PandoraModel::Created)
            created0 = panobject.namesvalues['created']
            creator0 = panobject.namesvalues['creator']
          end
        else  # RadarScrollWin
          panhash0 = PandoraUtils.hex_to_bytes(iter[2])
        end
        lang = panhash0[1].ord if panhash0 and (panhash0.size>1)
        lang ||= 0
      end

      if action=='Delete'
        if id and sel[0]
          ctrl_prsd, shift_prsd, alt_prsd = PandoraGtk.is_ctrl_shift_alt?
          keep_flag = (panstate and (panstate & PandoraModel::PSF_Support)>0)
          arch_flag = (panstate and (panstate & PandoraModel::PSF_Archive)>0)
          in_arch = tree_view.page_sw.arch_btn.active?
          ignore_mode = ((ctrl_prsd and shift_prsd) or (arch_flag and (not ctrl_prsd)))
          arch_mode = ((not ignore_mode) and (not ctrl_prsd))
          keep_mode = (arch_mode and (keep_flag or shift_prsd))
          delete_mode = PandoraUtils.get_param('delete_mode')
          do_del = true
          if arch_flag or ctrl_prsd or shift_prsd or in_arch \
          or (delete_mode==0)
            in_arch = (in_arch and arch_flag)
            info = panobject.record_info(80, nil, ': ')
            #panobject.show_panhash(panhash0) #.force_encoding('ASCII-8BIT') ASCII-8BIT
            dialog = PandoraGtk::GoodMessageDialog.new(info, 'Deletion', \
              Gtk::MessageDialog::QUESTION, get_panobject_icon(panobject))
            arch_cb = nil
            keep_cb = nil
            ignore_cb = nil
            dialog.signal_connect('key-press-event') do |widget, event|
              if (event.keyval==Gdk::Keyval::GDK_Delete)
                widget.response(Gtk::Dialog::RESPONSE_CANCEL)
              elsif [Gdk::Keyval::GDK_a, Gdk::Keyval::GDK_A, 1731, 1763].include?(\
              event.keyval) #a, A, ф, Ф
                arch_cb.active = (not arch_cb.active?) if arch_cb
              elsif [Gdk::Keyval::GDK_k, Gdk::Keyval::GDK_K, 1731, 1763].include?(\
              event.keyval) #k, K, л, Л
                keep_cb.active = (not keep_cb.active?) if keep_cb
              elsif [Gdk::Keyval::GDK_i, Gdk::Keyval::GDK_I, 1731, 1763].include?(\
              event.keyval) #i, I, ш, Ш
                ignore_cb.active = (not ignore_cb.active?) if ignore_cb
              else
                p event.keyval
              end
              false
            end
            # Set dialog size for prevent jumping
            hbox = dialog.vbox.children[0]
            hbox.set_size_request(500, 100) if hbox.is_a? Gtk::HBox
            # CheckBox adding
            if not in_arch
              arch_cb = SafeCheckButton.new(:arch)
              PandoraGtk.set_button_text(arch_cb, _('Move to archive'))
              arch_cb.active = arch_mode
              arch_cb.safe_signal_clicked do |widget|
                if in_arch
                  widget.safe_set_active(false)
                elsif not PandoraGtk.is_ctrl_shift_alt?(true, true)
                  widget.safe_set_active(true)
                end
                if widget.active?
                  ignore_cb.safe_set_active(false)
                else
                  keep_cb.safe_set_active(false)
                end
                set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
                false
              end
              dialog.vbox.pack_start(arch_cb, false, true, 0)

              $window.register_stock(:keep)
              keep_cb = SafeCheckButton.new(:keep)
              PandoraGtk.set_button_text(keep_cb, _('Keep in archive'))
              keep_cb.active = keep_mode
              keep_cb.safe_signal_clicked do |widget|
                widget.safe_set_active(false) if in_arch
                if widget.active?
                  arch_cb.safe_set_active(true) if not in_arch
                  ignore_cb.safe_set_active(false)
                end
                set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
                false
              end
              dialog.vbox.pack_start(keep_cb, false, true, 0)
            end

            $window.register_stock(:ignore)
            ignore_cb = SafeCheckButton.new(:ignore)
            ignore_cb.active = ignore_mode
            PandoraGtk.set_button_text(ignore_cb, _('Destroy and ignore'))
            ignore_cb.safe_signal_clicked do |widget|
              if widget.active?
                arch_cb.safe_set_active(false) if arch_cb
                keep_cb.safe_set_active(false) if keep_cb
              elsif not in_arch
                arch_cb.safe_set_active(true) if arch_cb
              end
              set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
              false
            end
            dialog.vbox.pack_start(ignore_cb, false, true, 0)

            set_del_dlg_wids(dialog, arch_cb, keep_cb, ignore_cb)
            dialog.vbox.show_all

            do_del = dialog.run_and_do do
              arch_mode = (arch_cb and arch_cb.active?)
              keep_mode = (keep_cb and keep_cb.active?)
              ignore_mode = ignore_cb.active?
            end
          end
          if do_del
            rm_from_tab = false
            if arch_mode
              p '[arch_mode, keep_mode]='+[arch_mode, keep_mode].inspect
              panstate = (panstate | PandoraModel::PSF_Archive)
              if keep_mode
                panstate = (panstate | PandoraModel::PSF_Support)
              else
                panstate = (panstate & (~PandoraModel::PSF_Support))
              end
              res = panobject.update({:panstate=>panstate}, nil, 'id='+id.to_s)
              if (not tree_view.page_sw.arch_btn.active?)
                rm_from_tab = true
              end
            else
              res = panobject.update(nil, nil, 'id='+id.to_s)
              PandoraModel.remove_all_relations(panhash0, true, true)
              PandoraModel.act_relation(nil, panhash0, RK_Ignore, :create, \
                true, true) if ignore_mode
              rm_from_tab = true
            end
            if rm_from_tab
              if (panobject.kind==PK_Relation)
                PandoraModel.del_image_from_cache(panobject.namesvalues['first'])
                PandoraModel.del_image_from_cache(panobject.namesvalues['second'])
              end
              tree_view.sel.delete_if {|row| row[0]==id }
              store.remove(iter)
              #iter.next!
              pt = path.indices[0]
              pt = tree_view.sel.size-1 if (pt > tree_view.sel.size-1)
              tree_view.set_cursor(Gtk::TreePath.new(pt), column, false) if (pt >= 0)
            end
          end
        end
      elsif panobject or (action=='Dialog') or (action=='Opinion')
        # Edit or Insert

        edit = ((not new_act) and (action != 'Copy'))

        row = nil
        formfields = nil
        if panobject
          row = sel[0] if sel
          formfields = panobject.get_fields_as_view(row, edit)
        end

        if panhash0
          page = CPI_Property
          page = CPI_Dialog if (action=='Dialog')
          page = CPI_Opinions if (action=='Opinion')
          show_cabinet(panhash0, nil, nil, nil, nil, page, formfields, id, edit)
        else
          dialog = FieldsDialog.new(panobject, tree_view, formfields, panhash0, id, \
            edit, panobject.sname)
          dialog.icon = get_panobject_icon(panobject)

          #!!!dialog.lang_entry.entry.text = PandoraModel.lang_to_text(lang) if lang

          if edit
            count, rate, querist_rate = PandoraCrypto.rate_of_panobj(panhash0)
            #!!!dialog.rate_btn.label = _('Rate')+': '+rate.round(2).to_s if rate.is_a? Float
            trust = nil
            #p PandoraUtils.bytes_to_hex(panhash0)
            #p 'trust or num'
            trust_or_num = PandoraCrypto.trust_to_panobj(panhash0)
            trust = trust_or_num if (trust_or_num.is_a? Float)
            #!!!dialog.vouch_btn.active = (trust_or_num != nil)
            #!!!dialog.vouch_btn.inconsistent = (trust_or_num.is_a? Integer)
            #!!!dialog.trust_scale.sensitive = (trust != nil)
            #dialog.trust_scale.signal_emit('value-changed')
            trust ||= 0.0
            #!!!dialog.trust_scale.value = trust
            #dialog.rate_label.text = rate.to_s

            #!!!dialog.keep_btn.active = (PandoraModel::PSF_Support & panstate)>0

            #!!pub_level = PandoraModel.act_relation(nil, panhash0, RK_MinPublic, :check)
            #!!!dialog.public_btn.active = pub_level
            #!!!dialog.public_btn.inconsistent = (pub_level == nil)
            #!!!dialog.public_scale.value = (pub_level-RK_MinPublic-10)/10.0 if pub_level
            #!!!dialog.public_scale.sensitive = pub_level

            #!!follow = PandoraModel.act_relation(nil, panhash0, RK_Follow, :check)
            #!!!dialog.follow_btn.active = follow
            #!!!dialog.follow_btn.inconsistent = (follow == nil)

            #dialog.lang_entry.active_text = lang.to_s
            #trust_lab = dialog.trust_btn.children[0]
            #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
          else  #new or copy
            key = PandoraCrypto.current_key(false, false)
            key_inited = (key and key[PandoraCrypto::KV_Obj])
            #!!!dialog.keep_btn.active = true
            #!!!dialog.follow_btn.active = key_inited
            #!!!dialog.vouch_btn.active = key_inited
            #!!!dialog.trust_scale.sensitive = key_inited
            #!!!if not key_inited
            #  dialog.follow_btn.inconsistent = true
            #  dialog.vouch_btn.inconsistent = true
            #  dialog.public_btn.inconsistent = true
            #end
            #!!!dialog.public_scale.sensitive = false
          end

          st_text = panobject.panhash_formula
          st_text = st_text + ' [#'+panobject.calc_panhash(row, lang, \
            true, true)+']' if sel and sel.size>0
          #!!!PandoraGtk.set_statusbar_text(dialog.statusbar, st_text)

          #if panobject.is_a? PandoraModel::Key
          #  mi = Gtk::MenuItem.new("Действия")
          #  menu = Gtk::MenuBar.new
          #  menu.append(mi)

          #  menu2 = Gtk::Menu.new
          #  menuitem = Gtk::MenuItem.new("Генерировать")
          #  menu2.append(menuitem)
          #  mi.submenu = menu2
          #  #p dialog.action_area
          #  dialog.hbox.pack_end(menu, false, false)
          #  #dialog.action_area.add(menu)
          #end

          titadd = nil
          if not edit
          #  titadd = _('edit')
          #else
            titadd = _('new')
          end
          dialog.title += ' ('+titadd+')' if titadd and (titadd != '')

          dialog.run2 do
            dialog.property_box.save_fields_with_flags(created0, row)
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
    attr_accessor :panobject, :sel, :notebook, :auto_create, :param_view_col, \
      :page_sw
  end

  # Column for SubjTreeView
  # RU: Колонка для SubjTreeView
  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
  end

  # ScrolledWindow for panobjects
  # RU: ScrolledWindow для объектов Пандоры
  class PanobjScrolledWindow < Gtk::ScrolledWindow
    attr_accessor :update_btn, :auto_btn, :arch_btn, :treeview, :filter_box

    def initialize
      super(nil, nil)
    end

    def update_treeview
      panobject = treeview.panobject
      store = treeview.model
      Gdk::Threads.synchronize do
        Gdk::Display.default.sync
        $window.mutex.synchronize do
          path, column = treeview.cursor
          id0 = nil
          if path
            iter = store.get_iter(path)
            id0 = iter[0]
          end
          #store.clear
          panobject.class.modified = false if panobject.class.modified
          filter = nil
          filter = filter_box.compose_filter
          if (not arch_btn.active?)
            del_bit = PandoraModel::PSF_Archive
            del_fil = 'IFNULL(panstate,0)&'+del_bit.to_s+'=0'
            if filter.nil?
              filter = del_fil
            else
              filter[0] << ' AND '+del_fil
            end
          end
          p 'select filter[sql,values]='+filter.inspect
          sel = panobject.select(filter, false, nil, panobject.sort)
          if sel
            treeview.sel = sel
            treeview.param_view_col = nil
            if ((panobject.kind==PandoraModel::PK_Parameter) \
            or (panobject.kind==PandoraModel::PK_Message)) and sel[0]
              treeview.param_view_col = sel[0].size
            end
            iter0 = nil
            sel.each_with_index do |row,i|
              #iter = store.append
              iter = store.get_iter(Gtk::TreePath.new(i))
              iter ||= store.append
              #store.set_value(iter, column, value)
              id = row[0].to_i
              iter[0] = id
              iter0 = iter if id0 and id and (id == id0)
              if treeview.param_view_col
                view = nil
                if (panobject.kind==PandoraModel::PK_Parameter)
                  type = panobject.field_val('type', row)
                  setting = panobject.field_val('setting', row)
                  ps = PandoraUtils.decode_param_setting(setting)
                  view = ps['view']
                  view ||= PandoraUtils.pantype_to_view(type)
                else
                  panstate = panobject.field_val('panstate', row)
                  if (panstate.is_a? Integer) and ((panstate & PandoraModel::PSF_Crypted)>0)
                    view = 'hex'
                  end
                end
                row[treeview.param_view_col] = view
              end
            end
            i = sel.size
            iter = store.get_iter(Gtk::TreePath.new(i))
            while iter
              store.remove(iter)
              iter = store.get_iter(Gtk::TreePath.new(i))
            end
            if treeview.sel.size>0
              if (not path) or (not store.get_iter(path)) \
              or (not store.iter_is_valid?(store.get_iter(path)))
                path = iter0.path if iter0
                path ||= Gtk::TreePath.new(treeview.sel.size-1)
              end
              treeview.set_cursor(path, nil, false)
              treeview.scroll_to_cell(path, nil, false, 0.0, 0.0)
            end
          end
        end
        p 'treeview is updated: '+panobject.ider
        treeview.grab_focus
      end
    end

  end

  # Filter box: field, operation and value
  # RU: Группа фильтра: поле, операция и значение
  class FilterHBox < Gtk::HBox
    attr_accessor :filters, :field_com, :oper_com, :val_entry, :logic_com, \
      :del_btn, :add_btn, :page_sw

    # Remove itself
    # RU: Удалить себя
    def delete
      @add_btn = nil
      if @filters.size>1
        parent.remove(self)
        filters.delete(self)
        last = filters[filters.size-1]
        #p [last, last.add_btn, filters.size-1]
        last.add_btn_to
      else
        field_com.entry.text = ''
        while children.size>1
          child = children[children.size-1]
          remove(child)
          child.destroy
        end
        @add_btn.destroy if @add_btn
        @add_btn = nil
        @oper_com = nil
      end
      first = filters[0]
      page_sw.filter_box = first
      if first and first.logic_com
        first.remove(first.logic_com)
        first.logic_com = nil
      end
      page_sw.update_treeview
    end

    def add_btn_to
      #p '---add_btn_to [add_btn, @add_btn]='+[add_btn, @add_btn].inspect
      if add_btn.nil? and (children.size>2)
        @add_btn = Gtk::ToolButton.new(Gtk::Stock::ADD, _('Add'))
        add_btn.tooltip_text = _('Add a new filter')
        add_btn.signal_connect('clicked') do |*args|
          FilterHBox.new(filters, parent, page_sw)
        end
        pack_start(add_btn, false, true, 0)
        add_btn.show_all
      end
    end

    # Compose filter with sql-query and raw values
    # RU: Составить фильтр с sql-запросом и сырыми значениями
    def compose_filter
      sql = nil
      values = nil
      @filters.each do |fb|
        fld = fb.field_com.entry.text
        if fb.oper_com and fb.val_entry
          oper = fb.oper_com.entry.text
          if fld and oper
            logic = nil
            logic = fb.logic_com.entry.text if fb.logic_com
            if not sql
              sql = ''
            else
              sql << ' '
              logic = 'AND' if (logic.nil? or (logic != 'OR'))
            end
            sql << logic+' ' if logic and (logic.size>0)
            val = fb.val_entry.text
            panobject = page_sw.treeview.panobject
            tab_flds = panobject.tab_fields
            tab_ind = tab_flds.index{ |tf| tf[0] == fld }
            if tab_ind
              fdesc = panobject.tab_fields[tab_ind][PandoraUtils::TI_Desc]
              view = type = nil
              if fdesc
                view = fdesc[PandoraUtils::FI_View]
                type = fdesc[PandoraUtils::FI_Type]
                val = PandoraUtils.view_to_val(val, type, view)
              elsif fld=='id'
                val = val.to_i
              end
              p '[val, type, view]='+[val, type, view].inspect
              if view.nil? and val.is_a?(String) and (val.index('*') or val.index('?'))
                PandoraUtils.correct_aster_and_quest!(val)
                fb.oper_com.entry.text = '=' if (oper != '=')
                oper = ' LIKE '
              elsif (view.nil? and val.nil?) or (val.is_a?(String) and val.size==0)
                fld = 'IFNULL('+fld+",'')"
                oper << "''"
                val = nil
              elsif val.nil? and (oper=='=')
                oper = ' IS NULL'
                val = nil
              end
              values ||= Array.new
              sql << fld + oper
              if not val.nil?
                sql << '?'
                values << val
              end
            end
          end
        end
      end
      values.insert(0, sql) if values
      values
    end

    def set_filter_by_str(logic, afilter)
      res = nil
      p 'set_filter_by_str(logic, afilter)='+[logic, afilter].inspect
      len = 1
      i = afilter.index('=')
      i ||= afilter.index('>')
      i ||= afilter.index('<')
      if not i
        i = afilter.index('<>')
        len = 2
      end
      if i
        fname = afilter[0, i]
        oper = afilter[i, len]
        val = afilter[i+len..-1]
        field_com.entry.text = fname
        oper_com.entry.text = oper
        val_entry.text = val
        logic_com.entry.text = logic if logic and logic_com
        res = true
      end
      res
    end

    def set_fix_filter(fix_filter, logic=nil)
      #p '== set_fix_filter  fix_filter='+fix_filter
      if fix_filter
        i = fix_filter.index(' AND ')
        j = fix_filter.index(' OR ')
        i = j if (i.nil? or ((not j.nil?) and (j>i)))
        if i
          afilter = fix_filter[0, i]
          fix_filter = fix_filter[i+1..-1]
        else
          afilter = fix_filter
          fix_filter = nil
        end
        setted = set_filter_by_str(logic, afilter)
        #p '--set_fix_filter [logic, afilter, fix_filter]='+[logic, afilter, fix_filter].inspect
        if fix_filter
          i = fix_filter.index(' ')
          logic = nil
          if i and i<4
            logic = fix_filter[0, i]
            fix_filter = fix_filter[i+1..-1]
          end
          if setted
            add_btn_to
            FilterHBox.new(filters, parent, page_sw)
          end
          next_fb = @filters[@filters.size-1]
          next_fb.set_fix_filter(fix_filter, logic)
        end
      end
    end

    # Create new instance
    # RU: Создать новый экземпляр
    def initialize(a_filters, hbox, a_page_sw)

      def no_filter_frase
        res = '<'+_('filter')+'>'
      end

      super()
      @page_sw = a_page_sw
      @filters = a_filters
      filter_box = self
      panobject = page_sw.treeview.panobject
      tab_flds = panobject.tab_fields
      def_flds = panobject.def_fields
      #def_flds.each do |df|
      #id = df[FI_Id]
      #tab_ind = tab_flds.index{ |tf| tf[0] == id }
      #if tab_ind
      #  renderer = Gtk::CellRendererText.new
        #renderer.background = 'red'
        #renderer.editable = true
        #renderer.text = 'aaa'

      #  title = df[FI_VFName]
      if @filters.size>0
        @logic_com = Gtk::Combo.new
        logic_com.set_popdown_strings(['AND', 'OR'])
        logic_com.entry.text = 'AND'
        logic_com.set_size_request(64, -1)
        filter_box.pack_start(logic_com, false, true, 0)
        prev = @filters[@filters.size-1]
        if prev and prev.add_btn
          prev.remove(prev.add_btn)
          prev.add_btn = nil
        end
      end

      fields = Array.new
      fields << no_filter_frase
      fields << 'lang'
      fields.concat(tab_flds.collect{|tf| tf[0]})
      @field_com = Gtk::Combo.new
      field_com.set_popdown_strings(fields)
      field_com.set_size_request(110, -1)

      field_com.entry.signal_connect('changed') do |entry|
        if filter_box.children.size>2
          if (entry.text == no_filter_frase) or (entry.text == '')
            delete
          end
          false
        elsif (entry.text != no_filter_frase) and (entry.text != '')
          @oper_com = Gtk::Combo.new
          oper_com.set_popdown_strings(['=','<>','>','<'])
          oper_com.set_size_request(56, -1)
          oper_com.entry.signal_connect('activate') do |*args|
            @val_entry.grab_focus
          end
          filter_box.pack_start(oper_com, false, true, 0)

          @del_btn = Gtk::ToolButton.new(Gtk::Stock::DELETE, _('Delete'))
          del_btn.tooltip_text = _('Delete this filter')
          del_btn.signal_connect('clicked') do |*args|
            delete
          end
          filter_box.pack_start(del_btn, false, true, 0)

          @val_entry = Gtk::Entry.new
          val_entry.set_size_request(120, -1)
          filter_box.pack_start(val_entry, false, true, 0)
          val_entry.signal_connect('focus-out-event') do |widget, event|
            page_sw.update_treeview
            false
          end

          add_btn_to
          filter_box.show_all
        end
      end
      filter_box.pack_start(field_com, false, true, 0)

      filter_box.show_all
      hbox.pack_start(filter_box, false, true, 0)

      @filters << filter_box

      p '@filters='+@filters.inspect

      filter_box
    end
  end

  # Showing panobject list
  # RU: Показ списка панобъектов
  def self.show_panobject_list(panobject_class, widget=nil, page_sw=nil, \
  auto_create=false, fix_filter=nil)
    notebook = $window.notebook
    single = (page_sw == nil)
    if single
      notebook.children.each do |child|
        if (child.is_a? PanobjScrolledWindow) and (child.name==panobject_class.ider)
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

    tab_flds = panobject.tab_fields
    def_flds = panobject.def_fields

    its_blob = (panobject.is_a? PandoraModel::Blob)
    if its_blob or (panobject.is_a? PandoraModel::Person)
      renderer = Gtk::CellRendererPixbuf.new
      #renderer.pixbuf = $window.get_icon_buf('smile')
      column = SubjTreeViewColumn.new(_('View'), renderer)
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      column.fixed_width = 45
      column.tab_ind = tab_flds.index{ |tf| tf[0] == 'panhash' }
      #p '//////////column.tab_ind='+column.tab_ind.inspect
      treeview.append_column(column)

      column.set_cell_data_func(renderer) do |tvc, renderer, model, iter|
        row = nil
        begin
          if model.iter_is_valid?(iter) and iter and iter.path
            row = tvc.tree_view.sel[iter.path.indices[0]]
          end
        rescue
          p 'rescue'
        end
        val = nil
        if row
          col = tvc.tab_ind
          val = row[col] if col
        end
        if val
          #p '[col, val]='+[col, val].inspect
          pixbuf = PandoraModel.get_avatar_icon(val, tvc.tree_view, its_blob, 45)
          pixbuf = nil if pixbuf==false
          renderer.pixbuf = pixbuf
        end
      end

    end

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
          row = nil
          begin
            if model.iter_is_valid?(iter) and iter and iter.path
              row = tvc.tree_view.sel[iter.path.indices[0]]
            end
          rescue
          end
          color = 'black'
          val = nil
          if row
            col = tvc.tab_ind
            val = row[col]
          end
          if val
            panobject = tvc.tree_view.panobject
            fdesc = panobject.tab_fields[col][TI_Desc]
            if fdesc.is_a? Array
              view = nil
              if tvc.tree_view.param_view_col and ((fdesc[FI_Id]=='value') or (fdesc[FI_Id]=='text'))
                view = row[tvc.tree_view.param_view_col] if row
              else
                view = fdesc[FI_View]
              end
              val, color = PandoraUtils.val_to_view(val, nil, view, false)
            else
              val = val.to_s
            end
            val = val[0,46]
          end
          renderer.foreground = color
          val ||= ''
          renderer.text = val
        end
      else
        p 'Field ['+id.inspect+'] is not found in table ['+panobject.ider+']'
      end
    end

    treeview.signal_connect('row_activated') do |tree_view, path, column|
      if single
        act_panobject(tree_view, 'Edit')
        #act_panobject(tree_view, 'Dialog')
      else
        dialog = page_sw.parent.parent.parent
        p '++dialog='+dialog.inspect
        #dialog.okbutton.activate
      end
    end

    list_sw = Gtk::ScrolledWindow.new(nil, nil)
    list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
    list_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    list_sw.border_width = 0
    list_sw.add(treeview)

    pbox = Gtk::VBox.new

    page_sw ||= PanobjScrolledWindow.new
    page_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    page_sw.border_width = 0
    page_sw.add_with_viewport(pbox)
    page_sw.children[0].shadow_type = Gtk::SHADOW_NONE # Gtk::SHADOW_ETCHED_IN

    page_sw.name = panobject.ider
    page_sw.treeview = treeview
    treeview.page_sw = page_sw

    hbox = Gtk::HBox.new

    PandoraGtk.add_tool_btn(hbox, Gtk::Stock::ADD, 'Create') do |widget|  #:NEW
      $window.do_menu_act('Create', treeview)
    end
    if single
      PandoraGtk.add_tool_btn(hbox, :dialog, 'Dialog') do |widget|
        $window.do_menu_act('Dialog', treeview)
      end
      PandoraGtk.add_tool_btn(hbox, :opinion, 'Opinions') do |widget|
        $window.do_menu_act('Opinion', treeview)
      end
    end
    page_sw.update_btn = PandoraGtk.add_tool_btn(hbox, Gtk::Stock::REFRESH, 'Update') do |widget|
      page_sw.update_treeview
    end
    page_sw.auto_btn = nil
    if single
      page_sw.auto_btn = PandoraGtk.add_tool_btn(hbox, :update, 'Auto update', true) do |widget|
        update_treeview_if_need(page_sw)
      end
    end
    page_sw.arch_btn = PandoraGtk.add_tool_btn(hbox, :arch, 'Show archived', false) do |widget|
      page_sw.update_btn.clicked
    end

    filters = Array.new
    page_sw.filter_box = FilterHBox.new(filters, hbox, page_sw)
    page_sw.filter_box.set_fix_filter(fix_filter) if fix_filter

    pbox.pack_start(hbox, false, true, 0)
    pbox.pack_start(list_sw, true, true, 0)

    page_sw.update_btn.clicked

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
      image = $window.get_panobject_image(panobject_class.ider, Gtk::IconSize::SMALL_TOOLBAR)
      #p 'single: widget='+widget.inspect
      #if widget.is_a? Gtk::ImageMenuItem
      #  animage = widget.image
      #elsif widget.is_a? Gtk::ToolButton
      #  animage = widget.icon_widget
      #else
      #  animage = nil
      #end
      #image = nil
      #if animage
      #  if animage.stock
      #    image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
      #    image.set_padding(2, 0)
      #  else
      #    image = Gtk::Image.new(animage.icon_set, Gtk::IconSize::MENU)
      #    image.set_padding(2, 0)
      #  end
      #end
      image.set_padding(2, 0)

      label_box = TabLabelBox.new(image, panobject.pname, page_sw) do
        store.clear
        treeview.destroy
      end

      page = notebook.append_page(page_sw, label_box)
      notebook.set_tab_reorderable(page_sw, true)
      page_sw.show_all
      notebook.page = notebook.n_pages-1

      #pbox.update_if_need

      treeview.grab_focus
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::ADD, _('Create'), 'Insert'], treeview))  #:NEW
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT.to_s+':mb', _('Edit'), 'Return'], treeview))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete'], treeview))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Dialog', 'dialog', _('Dialog'), '<control>D'], treeview))
    menu.append(create_menu_item(['Relation', :relation, _('Relate'), '<control>R'], treeview))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N'], treeview))
    menu.append(create_menu_item(['-', nil, nil], treeview))
    menu.append(create_menu_item(['Convert', Gtk::Stock::CONVERT, _('Convert')], treeview))
    menu.append(create_menu_item(['Import', Gtk::Stock::OPEN, _('Import')], treeview))
    menu.append(create_menu_item(['Export', Gtk::Stock::SAVE, _('Export')], treeview))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button-press-event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

    treeview.signal_connect('key-press-event') do |widget, event|
      res = true
      if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)
        act_panobject(treeview, 'Edit')
        #act_panobject(treeview, 'Dialog')
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
    if (panobjbox.is_a? PanobjScrolledWindow) and panobjbox.auto_btn and panobjbox.auto_btn.active?
      $treeview_thread = Thread.new do
        while panobjbox and (not panobjbox.destroyed?) and panobjbox.treeview \
        and (not panobjbox.treeview.destroyed?) and $window.visible?
          #p 'update_treeview_if_need: '+panobjbox.treeview.panobject.ider
          if panobjbox.treeview.panobject.class.modified
            #p 'update_treeview_if_need: modif='+panobjbox.treeview.panobject.class.modified.inspect
            #panobjbox.update_btn.clicked
            panobjbox.update_treeview
          end
          sleep(TAB_UPD_PERIOD)
        end
        $treeview_thread = nil
      end
    end
  end

  $media_buf_size = 50
  $send_media_queues = []
  $send_media_rooms = {}

  # Take pointer index for sending by room
  # RU: Взять индекс указателя для отправки по id комнаты
  def self.set_send_ptrind_by_panhash(room_id)
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
  def self.get_send_ptrind_by_panhash(room_id)
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
  def self.nil_send_ptrind_by_panhash(room_id)
    if room_id
      ptr = $send_media_rooms[room_id]
      if ptr
        ptr[0] = false
      end
    end
    res = $send_media_rooms.count{ |panhas, ptr| ptr[0] }
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
  def self.construct_room_id(panhash, session=nil)
    res = nil
    res = panhash.dup if panhash
    res ||= session.object_id if session
    res
  end

  # Find active sender
  # RU: Найти активного отправителя
  def self.find_another_active_sender(not_this=nil)
    res = nil
    $window.notebook.children.each do |child|
      if (child != not_this) and (child.is_a? CabinetBox) \
      and child.webcam_btn and child.webcam_btn.active?
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
    PandoraUtils.external_open(link)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    PandoraUtils.external_open(link)
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.version = PandoraNet::AppVersion + ' [' + PandoraUtils.file_md5[0, 6] + ']'
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.authors = ['© '+_('Michael Galyuk')+' <robux@mail.ru>']
    #dlg.documenters = dlg.authors
    #dlg.translator_credits = dlg.authors.join("\n")
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('P2P folk network')
    dlg.copyright = _('Free software')+' 2012, '+_('Michael Galyuk')
    begin
      file = File.open(File.join($pandora_app_dir, 'LICENSE.TXT'), 'r')
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
    dlg.signal_connect('key-press-event') do |widget, event|
      if [Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(\
        event.keyval) and event.state.control_mask? #w, W, ц, Ц
      then
        widget.response(Gtk::Dialog::RESPONSE_CANCEL)
        false
      elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?( \
        event.keyval) and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, \
        Gdk::Keyval::GDK_Q, 1738, 1770].include?(event.keyval) \
        and event.state.control_mask?) #q, Q, й, Й
      then
        widget.destroy
        $window.do_menu_act('Quit')
        false
      else
        false
      end
    end
    dlg.run
    if not dlg.destroyed?
      dlg.destroy
      $window.present
    end
  end

  # Show capcha
  # RU: Показать капчу
  def self.show_captcha(captcha_buf=nil, clue_text=nil, conntype=nil, node=nil, \
  node_id=nil, models=nil, panhashes=nil, session=nil)
    res = nil
    sw = nil
    p '--recognize_captcha(captcha_buf.size, clue_text, node, node_id, models)='+\
      [captcha_buf.size, clue_text, node, node_id, models].inspect
    if captcha_buf
      sw = PandoraGtk.show_cabinet(panhashes, session, conntype, node_id, models)
      if sw
        clue_text ||= ''
        clue, length, symbols = clue_text.split('|')
        node_text = node
        pixbuf_loader = Gdk::PixbufLoader.new
        pixbuf_loader.last_write(captcha_buf)
        pixbuf = pixbuf_loader.pixbuf

        sw.init_captcha_entry(pixbuf, length, symbols, clue, node_text)

        sw.captcha_enter = true
        while (not sw.destroyed?) and (sw.captcha_enter.is_a? TrueClass)
          sleep(0.02)
          Thread.pass
        end
        p '===== sw.captcha_enter='+sw.captcha_enter.inspect
        if sw.destroyed?
          res = false
        else
          if (sw.captcha_enter.is_a? String)
            res = sw.captcha_enter.dup
          else
            res = sw.captcha_enter
          end
          sw.captcha_enter = nil
        end
      end

      #captcha_entry = PandoraGtk::MaskEntry.new
      #captcha_entry.max_length = len
      #if symbols
      #  mask = symbols.downcase+symbols.upcase
      #  captcha_entry.mask = mask
      #end
    end
    [res, sw]
  end

  def self.extract_from_panhash(panhash)
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
    p 'targets='+[targets].inspect

    target_exist = ((persons.size>0) or (nodes.size>0) or (keys.size>0))
    if (not target_exist) and node_id
      node_model = PandoraUtils.get_model('Node', models)
      sel = node_model.select({:id => node_id}, false, 'panhash, key_hash', nil, 1)
      if sel and sel.size>0
        row = sel[0]
        nodes << row[0]
        keys  << row[1]
        extract_targets_from_panhash(targets, panhashes)
        target_exist = ((persons.size>0) or (nodes.size>0) or (keys.size>0))
      end
    end
  end

  # Show panobject cabinet
  # RU: Показать кабинет панобъекта
  def self.show_cabinet(panhash, session=nil, conntype=nil, \
  node_id=nil, models=nil, page=nil, fields=nil, obj_id=nil, edit=nil)
    sw = nil

    p '---show_cabinet(panhash, session, conntype, node_id, models, page, fields, obj_id, edit)=' \
      +[panhash, session, conntype, node_id, models, page, fields, obj_id, edit].inspect

    room_id = construct_room_id(panhash, session)
    if conntype.nil? or (conntype==PandoraNet::ST_Hunter)
      creator = PandoraCrypto.current_user_or_key(true)
      room_id[-1] = (room_id[-1].ord ^ 1).chr if panhash==creator
    end
    p 'room_id='+room_id.inspect
    $window.notebook.children.each do |child|
      if (child.is_a? CabinetBox) and ((child.room_id==room_id) \
      or (not session.nil?) and (child.session==session))
        #child.targets = targets
        #child.online_btn.safe_set_active(nodehash != nil)
        #child.online_btn.inconsistent = false
        $window.notebook.page = $window.notebook.children.index(child) if conntype.nil?
        sw = child
        sw.show_page(page) if page
        break
      end
    end
    sw ||= CabinetBox.new(panhash, room_id, page, fields, obj_id, edit, session)
    sw
  end

  # Showing search panel
  # RU: Показать панель поиска
  def self.show_search_panel(text=nil)
    sw = SearchBox.new(text)

    image = Gtk::Image.new(Gtk::Stock::FIND, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Search'), sw) do
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

    image = Gtk::Image.new(:session, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Sessions'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Show neighbor list
  # RU: Показать список соседей
  def self.show_radar_panel
    hpaned = $window.radar_hpaned
    radar_sw = $window.radar_sw
    if radar_sw.allocation.width <= 24 #hpaned.position <= 20
      radar_sw.width_request = 200 if radar_sw.width_request <= 24
      hpaned.position = hpaned.max_position-radar_sw.width_request
      radar_sw.update_btn.clicked
    else
      radar_sw.width_request = radar_sw.allocation.width
      hpaned.position = hpaned.max_position
    end
    $window.correct_fish_btn_state
    #$window.notebook.children.each do |child|
    #  if (child.is_a? RadarScrollWin)
    #    $window.notebook.page = $window.notebook.children.index(child)
    #    child.update_btn.clicked
    #    return
    #  end
    #end
    #sw = RadarScrollWin.new

    #image = Gtk::Image.new(Gtk::Stock::JUSTIFY_LEFT, Gtk::IconSize::MENU)
    #image.set_padding(2, 0)
    #label_box = TabLabelBox.new(image, _('Fishes'), sw, false, 0) do
    #  #sw.destroy
    #end
    #page = $window.notebook.append_page(sw, label_box)
    #sw.show_all
    #$window.notebook.page = $window.notebook.n_pages-1
  end

  # Switch full screen mode
  # RU: Переключить режим полного экрана
  def self.full_screen_switch
    need_show = (not $window.menubar.visible?)
    $window.menubar.visible = need_show
    $window.toolbar.visible = need_show
    $window.notebook.show_tabs = need_show
    $window.log_sw.visible = need_show
    $window.radar_sw.visible = need_show
    @last_cur_page_toolbar ||= nil
    if @last_cur_page_toolbar and (not @last_cur_page_toolbar.destroyed?)
      if need_show and (not @last_cur_page_toolbar.visible?)
        @last_cur_page_toolbar.visible = true
      end
      @last_cur_page_toolbar = nil
    end
    page = $window.notebook.page
    if (page >= 0)
      cur_page = $window.notebook.get_nth_page(page)
      if (cur_page.is_a? PandoraGtk::CabinetBox) and cur_page.toolbar_box
        if need_show
          cur_page.toolbar_box.visible = true if (not cur_page.toolbar_box.visible?)
        elsif PandoraGtk.is_ctrl_shift_alt?(true, true) and cur_page.toolbar_box.visible?
          cur_page.toolbar_box.visible = false
          @last_cur_page_toolbar = cur_page.toolbar_box
        end
      end
    end
    $window.set_status_field(PandoraGtk::SF_FullScr, nil, nil, (not need_show))
  end

  # Show log bar
  # RU: Показать log бар
  def self.show_log_bar(new_size=nil)
    vpaned = $window.log_vpaned
    log_sw = $window.log_sw
    if new_size and (new_size>=0) or (new_size.nil? \
    and (log_sw.allocation.height <= 24)) #hpaned.position <= 20
      if new_size and (new_size>=24)
        log_sw.height_request = new_size if (new_size>log_sw.height_request)
      else
        log_sw.height_request = log_sw.allocation.height if log_sw.allocation.height>24
        log_sw.height_request = 200 if (log_sw.height_request <= 24)
      end
      vpaned.position = vpaned.max_position-log_sw.height_request
    else
      log_sw.height_request = log_sw.allocation.height
      vpaned.position = vpaned.max_position
    end
    $window.correct_log_btn_state
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

    image = Gtk::Image.new(:fish, Gtk::IconSize::SMALL_TOOLBAR)
    image.set_padding(2, 0)
    label_box = TabLabelBox.new(image, _('Fishers'), sw) do
      #sw.destroy
    end
    page = $window.notebook.append_page(sw, label_box)
    $window.notebook.set_tab_reorderable(sw, true)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  # Set bold weight of MenuItem
  # RU: Ставит жирный шрифт у MenuItem
  def self.set_bold_to_menuitem(menuitem)
    label = menuitem.children[0]
    if (label.is_a? Gtk::Label)
      text = label.text
      if text and (not text.include?('<b>'))
        label.use_markup = true
        label.set_markup('<b>'+text+'</b>') if label.use_markup?
      end
    end
  end

  # Status icon
  # RU: Иконка в трее
  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon, :play_sounds, :online, :hide_on_minimize, :message

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
      PandoraGtk.set_bold_to_menuitem(menuitem)
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
            if cur_page.is_a? PandoraGtk::CabinetBox
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($window.notebook.n_pages == 0)
          end
        end
      end
    end
  end  #--PandoraStatusIcon

  def self.detect_icon_opts(stock)
    res = stock
    opts = 'mt'
    if res.is_a? String
      i = res.index(':')
      if i
        opts = res[i+1..-1]
        res = res[0, i]
        res = nil if res==''
      end
    end
    [res, opts]
  end

  $status_font = nil

  def self.status_font
    if $status_font.nil?
      style = Gtk::Widget.default_style
      font = style.font_desc
      fs = font.size
      fs = fs * Pango::SCALE_SMALL if fs
      font.size = fs if fs
      $status_font = font
    end
    $status_font
  end

  class GoodButton < Gtk::Frame
    attr_accessor :hbox, :image, :label, :active, :group_set

    def initialize(astock, atitle=nil, atoggle=nil, atooltip=nil)
      super()
      self.tooltip_text = atooltip if atooltip
      @group_set = nil
      if atoggle.is_a? Integer
        @group_set = atoggle
        atoggle = (atoggle>0)
      end
      @hbox = Gtk::HBox.new
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(@image)

      @proc_on_click = Proc.new do |*args|
        yield(*args) if block_given?
      end

      @im_evbox = Gtk::EventBox.new
      #@im_evbox.border_width = 2
      @im_evbox.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK
      @lab_evbox = Gtk::EventBox.new
      #@lab_evbox.border_width = 1
      @lab_evbox.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK \
        | Gdk::Event::VISIBILITY_NOTIFY_MASK

      set_image(astock)
      set_label(atitle)
      self.add(@hbox)

      set_active(atoggle)

      @enter_event = Proc.new do |body_child, event|
        self.shadow_type = Gtk::SHADOW_OUT if @active.nil?
        false
      end

      @leave_event = Proc.new do |body_child, event|
        self.shadow_type = Gtk::SHADOW_NONE if @active.nil?
        false
      end

      @press_event = Proc.new do |widget, event|
        if (event.button == 1)
          if @active.nil?
            self.shadow_type = Gtk::SHADOW_IN
          elsif @group_set.nil?
            @active = (not @active)
            set_active(@active)
          end
          do_on_click
        end
        false
      end

      @release_event = Proc.new do |widget, event|
        set_active(@active)
        false
      end

      @im_evbox.signal_connect('enter-notify-event') { |*args| @enter_event.call(*args) }
      @im_evbox.signal_connect('leave-notify-event') { |*args| @leave_event.call(*args) }
      @im_evbox.signal_connect('button-press-event') { |*args| @press_event.call(*args) }
      @im_evbox.signal_connect('button-release-event') { |*args| @release_event.call(*args) }

      @lab_evbox.signal_connect('enter-notify-event') { |*args| @enter_event.call(*args) }
      @lab_evbox.signal_connect('leave-notify-event') { |*args| @leave_event.call(*args) }
      @lab_evbox.signal_connect('button-press-event') { |*args| @press_event.call(*args) }
      @lab_evbox.signal_connect('button-release-event') { |*args| @release_event.call(*args) }
    end

    def do_on_click
      @proc_on_click.call
    end

    def active?
      @active
    end

    def set_active(toggle)
      @active = toggle
      if @active.nil?
        self.shadow_type = Gtk::SHADOW_NONE
      elsif @active
        self.shadow_type = Gtk::SHADOW_IN
        @im_evbox.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#C9C9C9'))
        @lab_evbox.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse('#C9C9C9'))
      else
        self.shadow_type = Gtk::SHADOW_OUT
        @im_evbox.modify_bg(Gtk::STATE_NORMAL, nil)
        @lab_evbox.modify_bg(Gtk::STATE_NORMAL, nil)
      end
    end

    def set_image(astock=nil)
      if @image
        @image.destroy
        @image = nil
      end
      if astock
        #$window.get_preset_iconset(astock)
        $window.register_stock(astock)
        @image = Gtk::Image.new(astock, Gtk::IconSize::MENU)
        @image.set_padding(2, 2)
        @image.set_alignment(0.5, 0.5)
        @im_evbox.add(@image)
        @hbox.pack_start(@im_evbox, true, true, 0)
      end
    end

    def set_label(atitle=nil)
      if atitle.nil?
        if @label
          @label.visible = false
          @label.text = ''
        end
      else
        if @label
          @label.text = atitle
          @label.visible = true if not @label.visible?
        else
          @label = Gtk::Label.new(atitle)
          @label.set_padding(2, 2)
          @label.set_alignment(0.0, 0.5)
          @label.modify_font(PandoraGtk.status_font)
          #p style = @label.style
          #p style = @label.modifier_style
          #p style = Gtk::Widget.default_style
          #p style.font_desc
          #p style.font_desc.size
          #p style.font_desc.family
          @lab_evbox.add(@label)
          @hbox.pack_start(@lab_evbox, true, true, 0)
        end
      end
    end
  end

  # Main window
  # RU: Главное окно
  class MainWindow < Gtk::Window
    attr_accessor :hunter_count, :listener_count, :fisher_count, :log_view, :notebook, \
      :pool, :focus_timer, :title_view, :do_on_start, :radar_hpaned, :task_offset, \
      :radar_sw, :log_vpaned, :log_sw, :accel_group, :node_reg_offset, :menubar, :toolbar


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
      set_status_field(SF_Conn, (hunter_count + listener_count + fisher_count).to_s)
      online = ((@hunter_count>0) or (@listener_count>0) or (@fisher_count>0))
      $statusicon.set_online(online)
    end

    $toggle_buttons = []

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_lis_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Listen]
      if tool_btn
        lis_act = PandoraNet.listen?
        tool_btn.safe_set_active(lis_act) if tool_btn.is_a? SafeToggleToolButton
      end
    end

    # Change hunter button state
    # RU: Изменить состояние кнопки охотника
    def correct_hunt_btn_state
      tool_btn = $toggle_buttons[PandoraGtk::SF_Hunt]
      #pushed = ((not $hunter_thread.nil?) and $hunter_thread[:active] \
      #  and (not $hunter_thread[:paused]))
      pushed = PandoraNet.is_hunting?
      #p 'correct_hunt_btn_state: pushed='+[tool_btn, pushed, $hunter_thread, \
      #  $hunter_thread[:active], $hunter_thread[:paused]].inspect
      tool_btn.safe_set_active(pushed) if tool_btn.is_a? SafeToggleToolButton
      $window.set_status_field(PandoraGtk::SF_Hunt, nil, nil, pushed)
    end

    # Change listener button state
    # RU: Изменить состояние кнопки слушателя
    def correct_fish_btn_state
      hpaned = $window.radar_hpaned
      #list_sw = hpaned.children[1]
      an_active = (hpaned.max_position - hpaned.position) > 24
      #(list_sw.allocation.width > 24)
      #($window.radar_hpaned.position > 24)
      $window.set_status_field(PandoraGtk::SF_Radar, nil, nil, an_active)
      #tool_btn = $toggle_buttons[PandoraGtk::SF_Radar]
      #if tool_btn
      #  hpaned = $window.radar_hpaned
      #  list_sw = hpaned.children[0]
      #  tool_btn.safe_set_active(hpaned.position > 24)
      #end
    end

    def correct_log_btn_state
      vpaned = $window.log_vpaned
      an_active = (vpaned.max_position - vpaned.position) > 24
      $window.set_status_field(PandoraGtk::SF_Log, nil, nil, an_active)
    end

    # Show notice status
    # RU: Показать уведомления в статусе
    #def show_notice(change=nil)
    #  if change
    #    PandoraGtk.show_panobject_list(PandoraModel::Parameter, nil, nil, true)
    #  end
    #  PandoraNet.get_notice_params
    #  notice = PandoraModel.transform_trust($notice_trust, :auto_to_float)
    #  notice = notice.round(1).to_s + '/'+$notice_depth.to_s
    #  set_status_field(PandoraGtk::SF_Notice, notice)
    #end

    $statusbar = nil
    $status_fields = []

    # Add field to statusbar
    # RU: Добавляет поле в статусбар
    def add_status_field(index, text, tooltip=nil, stock=nil, toggle=nil, separ_pos=nil)
      separ_pos ||= 1
      if (separ_pos & 1)>0
        $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      end
      toggle_group = nil
      toggle_group = -1 if not toggle.nil?
      tooltip = _(tooltip) if tooltip
      btn = GoodButton.new(stock, text, toggle_group, tooltip) do |*args|
        yield(*args) if block_given?
      end
      btn.set_active(toggle) if not toggle.nil?
      $statusbar.pack_start(btn, false, false, 0)
      $status_fields[index] = btn
      if (separ_pos & 2)>0
        $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      end
    end

    # Set properties of fiels in statusbar
    # RU: Задаёт свойства поля в статусбаре
    def set_status_field(index, text, enabled=nil, toggle=nil)
      fld = $status_fields[index]
      if fld
        if text
          str = _(text)
          str = _('Version') + ': ' + str if (index==SF_Update)
          fld.set_label(str)
        end
        fld.sensitive = enabled if (enabled != nil)
        if (toggle != nil)
          fld.set_active(toggle)
          btn = $toggle_buttons[index]
          btn.safe_set_active(toggle) if btn and (btn.is_a? SafeToggleToolButton)
        end
      end
    end

    # Get fiels of statusbar
    # RU: Возвращает поле статусбара
    def get_status_field(index)
      $status_fields[index]
    end

    def get_icon_file_params(preset)
      icon_params, icon_file_desc = nil
      smile_desc = PandoraUtils.get_param('icons_'+preset)
      if smile_desc
        icon_params = smile_desc.split('|')
        icon_file_desc = icon_params[0]
        icon_params.delete_at(0)
      end
      [icon_params, icon_file_desc]
    end

    # Return Pixbuf with icon picture
    # RU: Возвращает Pixbuf с изображением иконки
    def get_icon_buf(emot='smile', preset='qip')
      buf = nil
      if not preset
        @def_smiles ||= PandoraUtils.get_param('def_smiles')
        preset = @def_smiles
      end
      buf = @icon_bufs[preset][emot] if @icon_bufs and @icon_bufs[preset]
      icon_preset = nil
      if buf.nil?
        @icon_presets ||= Hash.new
        icon_preset = @icon_presets[preset]
        if icon_preset.nil?
          icon_params, icon_file_desc = get_icon_file_params(preset)
          if icon_params and icon_file_desc
            icon_file_params = icon_file_desc.split(':')
            icon_file_name = icon_file_params[0]
            numXs, numYs = icon_file_params[1].split('x')
            bord_s = icon_file_params[2]
            bord_s.delete!('p')
            padd_s = icon_file_params[3]
            padd_s.delete!('p')
            begin
              smile_fn = File.join($pandora_view_dir, icon_file_name)
              preset_buf = Gdk::Pixbuf.new(smile_fn)
              if preset_buf
                big_width = preset_buf.width
                big_height = preset_buf.height
                #p 'get_icon_buf [big_width, big_height]='+[big_width, big_height].inspect
                bord = bord_s.to_i
                padd = padd_s.to_i
                numX = numXs.to_i
                numY = numYs.to_i
                cellX = (big_width - 2*bord - (numX-1)*padd)/numX
                cellY = (big_height - 2*bord - (numY-1)*padd)/numY

                icon_preset = Hash.new
                icon_preset[:names]      = icon_params
                icon_preset[:big_width]  = big_width
                icon_preset[:big_height] = big_height
                icon_preset[:bord]       = bord
                icon_preset[:padd]       = padd
                icon_preset[:numX]       = numX
                icon_preset[:numY]       = numY
                icon_preset[:cellX]      = cellX
                icon_preset[:cellY]      = cellY
                icon_preset[:buf]        = preset_buf
                @icon_presets[preset] = icon_preset
              end
            rescue
              p 'Error while load smile file: ['+smile_fn+']'
            end
          end
        end
      end

      def transpix?(pix, bg)
        res = ((pix.size == 4) and (pix[-1] == 0.chr) or (pix == bg))
      end

      if buf.nil? and icon_preset
        index = icon_preset[:names].index(emot)
        if index.nil?
          if icon_preset[:def_index].nil?
            PandoraUtils.set_param('icons_'+preset, nil)
            icon_params, icon_file_desc = get_icon_file_params(preset)
            icon_preset[:names] = icon_params
            index = icon_preset[:names].index(emot)
            icon_preset[:def_index] = 0
          end
          index ||= icon_preset[:def_index]
        end
        if index
          big_width  = icon_preset[:big_width]
          big_height = icon_preset[:big_height]
          bord       = icon_preset[:bord]
          padd       = icon_preset[:padd]
          numX       = icon_preset[:numX]
          numY       = icon_preset[:numY]
          cellX      = icon_preset[:cellX]
          cellY      = icon_preset[:cellY]
          preset_buf = icon_preset[:buf]

          iY = index.div(numX)
          iX = index - (iY*numX)
          dX = bord + iX*(cellX+padd)
          dY = bord + iY*(cellY+padd)
          #p '[cellX, cellY, iX, iY, dX, dY]='+[cellX, cellY, iX, iY, dX, dY].inspect
          draft_buf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, cellX, cellY)
          preset_buf.copy_area(dX, dY, cellX, cellY, draft_buf, 0, 0)
          #draft_buf = Gdk::Pixbuf.new(preset_buf, 0, 0, 21, 24)

          pixs = AsciiString.new(draft_buf.pixels)
          pix_size = draft_buf.n_channels
          width = draft_buf.width
          height = draft_buf.height
          w = width * pix_size  #buf.rowstride
          #p '[pixs.bytesize, width, height, w]='+[pixs.bytesize, width, height, w].inspect

          bg = pixs[0, pix_size]   #top left pixel consider background

          # Find top border
          top = 0
          while (top<height)
            x = 0
            while (x<w) and transpix?(pixs[w*top+x, pix_size], bg)
              x += pix_size
            end
            if x<w
              break
            else
              top += 1
            end
          end

          # Find bottom border
          bottom = height-1
          while (bottom>top)
            x = 0
            while (x<w) and transpix?(pixs[w*bottom+x, pix_size], bg)
              x += pix_size
            end
            if x<w
              break
            else
              bottom -= 1
            end
          end

          # Find left border
          left = 0
          while (left<w)
            y = 0
            while (y<height) and transpix?(pixs[w*y+left, pix_size], bg)
              y += 1
            end
            if y<height
              break
            else
              left += pix_size
            end
          end

          # Find right border
          right = w - pix_size
          while (right>left)
            y = 0
            while (y<height) and transpix?(pixs[w*y+right, pix_size], bg)
              y += 1
            end
            if y<height
              break
            else
              right -= pix_size
            end
          end

          left = left/pix_size
          right = right/pix_size
          #p '====[top,bottom,left,right]='+[top,bottom,left,right].inspect

          width2 = right-left+1
          height2 = bottom-top+1
          #p '  ---[width2,height2]='+[width2,height2].inspect

          if (width2>0) and (height2>0) \
          and ((left>0) or (top>0) or (width2<width) or (height2<height))
            # Crop borders
            buf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, width2, height2)
            draft_buf.copy_area(left, top, width2, height2, buf, 0, 0)
          else
            buf = draft_buf
          end
          @icon_bufs ||= Hash.new
          @icon_bufs[preset] ||= Hash.new
          @icon_bufs[preset][emot] = buf
        else
          p 'No emotion ['+emot+'] in the preset ['+preset+']'
        end
      end
      buf
    end

    def get_icon_scale_buf(emot='smile', preset='pan', icon_size=16, center=true)
      buf = get_icon_buf(emot, preset)
      buf = PandoraModel.scale_buf_to_size(buf, icon_size, center)
    end

    $iconsets = {}

    # Return Image with defined icon size
    # RU: Возвращает Image с заданным размером иконки
    def get_preset_iconset(iname, preset='pan')
      ind = [iname.to_s, preset]
      res = $iconsets[ind]
      if res.nil?
        if (iname.is_a? Symbol)
          res = Gtk::IconFactory.lookup_default(iname.to_s)
          iname = iname.to_s if res.nil?
        end
        if res.nil? and preset
          buf = get_icon_buf(iname, preset)
          if buf
            width = buf.width
            height = buf.height
            if width==height
              qbuf = buf
            else
              asize = width
              asize = height if asize<height
              left = (asize - width)/2
              top  = (asize - height)/2
              qbuf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, asize, asize)
              qbuf.fill!(0xFFFFFF00)
              buf.copy_area(0, 0, width, height, qbuf, left, top)
            end
            res = Gtk::IconSet.new(qbuf)
          end
        end
        $iconsets[ind] = res if res
      end
      res
    end

    def get_preset_icon(iname, preset='pan', icon_size=nil)
      res = nil
      iconset = get_preset_iconset(iname, preset)
      if iconset
        icon_size ||= Gtk::IconSize::DIALOG
        if icon_size.is_a? Integer
          icon_name = Gtk::IconSize.get_name(icon_size)
          icon_name ||= 'SIZE'+icon_size.to_s
          icon_res = Gtk::IconSize.from_name(icon_name)
          if (not icon_res) or (icon_res==0)
            icon_size = Gtk::IconSize.register(icon_name, icon_size, icon_size)
          else
            icon_size = icon_res
          end
        end
        style = Gtk::Widget.default_style
        res = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
          Gtk::STATE_NORMAL, icon_size)  #Gtk::IconSize::LARGE_TOOLBAR)
      end
      res
    end

    # Return Image with defined icon size
    # RU: Возвращает Image с заданным размером иконки
    def get_preset_image(iname, isize=Gtk::IconSize::MENU, preset='pan')
      image = nil
      isize ||= Gtk::IconSize::MENU
      #p 'get_preset_image  iname='+[iname, isize].inspect
      #if iname.is_a? String
        iconset = get_preset_iconset(iname, preset)
        image = Gtk::Image.new(iconset, isize)
      #else
      #  p image = Gtk::Image.new(iname, isize)
      #end
      image.set_alignment(0.5, 0.5)
      image
    end

    def get_panobject_stock(panobject_ider)
      res = panobject_ider
      mi = MENU_ITEMS.detect {|mi| mi[0]==res }
      if mi
        stock_opt = mi[1]
        stock, opts = PandoraGtk.detect_icon_opts(stock_opt)
        res = stock.to_sym if stock
      end
      res
    end

    def get_panobject_image(panobject_ider, isize=Gtk::IconSize::MENU, preset='pan')
      res = nil
      stock = get_panobject_stock(panobject_ider)
      res = get_preset_image(stock, isize, preset) if stock
      res
    end

    # Register new stock by name of image preset
    # RU: Регистрирует новый stock по имени пресета иконки
    def register_stock(stock=:person, preset=nil, name=nil)
      stock = stock.to_sym if stock.is_a? String
      stock_inf = nil
      preset ||= 'pan'
      suff = preset
      suff = '' if (preset=='pan' or (preset.nil?))
      reg_stock = stock.to_s
      if suff and (suff.size>0)
        reg_stock << '_'+suff.to_s
      end
      reg_stock = reg_stock.to_sym
      begin
        stock_inf = Gtk::Stock.lookup(reg_stock)
      rescue
      end
      if not stock_inf
        icon_set = get_preset_iconset(stock.to_s, preset)
        if icon_set
          name ||= '_'+stock.to_s.capitalize
          Gtk::Stock.add(reg_stock, name)
          @icon_factory.add(reg_stock.to_s, icon_set)
        end
      end
      stock_inf
    end

    # Export table to file
    # RU: Выгрузить таблицу в файл
    def export_table(panobject, filename=nil)

      ider = panobject.ider
      separ = '|'

      File.open(filename, 'w') do |file|
        file.puts('# Export table ['+ider+']')
        file.puts('# Code page: UTF-8')

        tab_flds = panobject.tab_fields
        #def_flds = panobject.def_fields
        #id = df[FI_Id]
        #tab_ind = tab_flds.index{ |tf| tf[0] == id }
        fields = tab_flds.collect{|tf| tf[0]}
        fields = fields.join('|')
        file.puts('# Fields: '+fields)

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
          file.puts(Utf8String.new(line))
        end
      end

      PandoraUtils.log_message(LM_Info, _('Table exported')+': '+filename)
    end

    def mutex
      @mutex ||= Mutex.new
    end

    # Menu event handler
    # RU: Обработчик события меню
    def do_menu_act(command, treeview=nil)
      widget = nil
      if not (command.is_a? String)
        widget = command
        if widget.instance_variable_defined?('@command')
          command = widget.command
        else
          command = widget.name
        end
      end
      case command
        when 'Quit'
          PandoraNet.start_or_stop_listen(false, true)
          PandoraNet.start_or_stop_hunt(false) if $hunter_thread
          self.pool.close_all_session
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
        when 'Guide'
          guide_fn = File.join($pandora_doc_dir, 'guide.'+$lang+'.pdf')
          if not File.exist?(guide_fn)
            guide_fn = File.join($pandora_doc_dir, 'guide.en.pdf')
          end
          if File.exist?(guide_fn)
            PandoraUtils.external_open(guide_fn, 'open')
          else
            PandoraUtils.external_open($pandora_doc_dir, 'open')
          end
        when 'Readme'
          PandoraUtils.external_open(File.join($pandora_app_dir, 'README.TXT'), 'open')
        when 'DocPath'
          PandoraUtils.external_open($pandora_doc_dir, 'open')
        when 'Close'
          if notebook.page >= 0
            page = notebook.get_nth_page(notebook.page)
            tab = notebook.get_tab_label(page)
            close_btn = tab.children[tab.children.size-1].children[0]
            close_btn.clicked
          end
        when 'Create','Edit','Delete','Copy', 'Dialog', 'Opinion', 'Convert', 'Import', 'Export'
          p 'act_panobject()  treeview='+treeview.inspect
          if (not treeview) and (notebook.page >= 0)
            sw = notebook.get_nth_page(notebook.page)
            treeview = sw.children[0]
          end
          if treeview.is_a? Gtk::TreeView # SubjTreeView
            if command=='Convert'
              panobject = treeview.panobject
              panobject.update(nil, nil, nil)
              panobject.class.tab_fields(true)
            elsif command=='Import'
              p 'import'
            elsif command=='Export'
              panobject = treeview.panobject
              ider = panobject.ider
              filename = File.join($pandora_files_dir, ider+'.csv')

              dialog = GoodFileChooserDialog.new(filename, false, nil, $window)

              filter = Gtk::FileFilter.new
              filter.name = _('Text tables')+' (*.csv,*.txt)'
              filter.add_pattern('*.csv')
              filter.add_pattern('*.txt')
              dialog.add_filter(filter)

              dialog.filter = filter

              filter = Gtk::FileFilter.new
              filter.name = _('JavaScript Object Notation')+' (*.json)'
              filter.add_pattern('*.json')
              dialog.add_filter(filter)

              filter = Gtk::FileFilter.new
              filter.name = _('Pandora Simple Object Notation')+' (*.pson)'
              filter.add_pattern('*.pson')
              dialog.add_filter(filter)

              if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
                filename = dialog.filename
                export_table(panobject, filename)
              end
              dialog.destroy if not dialog.destroyed?
            else
              PandoraGtk.act_panobject(treeview, command)
            end
          end
        when 'Listen'
          PandoraNet.start_or_stop_listen
        when 'Hunt'
          continue = PandoraGtk.is_ctrl_shift_alt?(true, true)
          PandoraNet.start_or_stop_hunt(continue)
        when 'Authorize'
          key = PandoraCrypto.current_key(false, false)
          if key
            PandoraNet.start_or_stop_listen(false)
            PandoraNet.start_or_stop_hunt(false) if $hunter_thread
            self.pool.close_all_session
          end
          key = PandoraCrypto.current_key(true)
        when 'Wizard'
          PandoraGtk.show_log_bar(80)
        when 'Profile'
          PandoraGtk.show_profile_panel
        when 'Search'
          PandoraGtk.show_search_panel
        when 'Session'
          PandoraGtk.show_session_panel
        when 'Radar'
          PandoraGtk.show_radar_panel
        when 'FullScr'
          PandoraGtk.full_screen_switch
        when 'LogBar'
          PandoraGtk.show_log_bar
        when 'Fisher'
          PandoraGtk.show_fisher_panel
        else
          panobj_id = command
          if (panobj_id.is_a? String) and (panobj_id.size>0) \
          and (panobj_id[0].upcase==panobj_id[0]) and PandoraModel.const_defined?(panobj_id)
            panobject_class = PandoraModel.const_get(panobj_id)
            PandoraGtk.show_panobject_list(panobject_class, widget)
          else
            PandoraUtils.log_message(LM_Warning, _('Menu handler is not defined yet') + \
              ' "'+panobj_id+'"')
          end
      end
    end

    # Menu structure
    # RU: Структура меню
    MENU_ITEMS =
      [[nil, nil, '_World'],
      ['Person', 'person', 'People', '<control>E'], #Gtk::Stock::ORIENTATION_PORTRAIT
      ['Community', 'community:m', 'Communities'],
      ['Blob', 'blob', 'Files', '<control>J'], #Gtk::Stock::FILE Gtk::Stock::HARDDISK
      ['-', nil, '-'],
      ['City', 'city:m', 'Towns'],
      ['Street', 'street:m', 'Streets'],
      ['Address', 'address:m', 'Addresses'],
      ['Contact', 'contact:m', 'Contacts'],
      ['Country', 'country:m', 'States'],
      ['Language', 'lang:m', 'Languages'],
      ['Word', 'word', 'Words'], #Gtk::Stock::SPELL_CHECK
      ['Relation', 'relation:m', 'Relations'],
      ['-', nil, '-'],
      ['Task', 'task:m', 'Tasks'],
      ['Message', 'message:m', 'Messages'],
      [nil, nil, '_Business'],
      ['Advertisement', 'ad', 'Advertisements'],
      ['Order', 'order:m', 'Orders'],
      ['Deal', 'deal:m', 'Deals'],
      ['Transfer', 'transfer:m', 'Transfers'],
      ['Waybill', 'waybill:m', 'Waybills'],
      ['-', nil, '-'],
      ['Debenture', 'debenture:m', 'Debentures'],
      ['Deposit', 'deposit:m', 'Deposits'],
      ['Guarantee', 'guarantee:m', 'Guarantees'],
      ['Insurer', 'insurer:m', 'Insurers'],
      ['-', nil, '-'],
      ['Product', 'product:m', 'Products'],
      ['Service', 'service:m', 'Services'],
      ['Currency', 'currency:m', 'Currency'],
      ['Storage', 'storage:m', 'Storages'],
      ['Estimate', 'estimate:m', 'Estimates'],
      ['Contract', 'contract:m', 'Contracts'],
      ['Report', 'report:m', 'Reports'],
      [nil, nil, '_Region'],
      ['Law', 'law:m', 'Laws'],
      ['Resolution', 'resolution:m', 'Resolutions'],
      ['-', nil, '-'],
      ['Project', 'project', 'Projects'],
      ['Offense', 'offense:m', 'Offenses'],
      ['Punishment', 'punishment', 'Punishments'],
      ['-', nil, '-'],
      ['Contribution', 'contribution:m', 'Contributions'],
      ['Expenditure', 'expenditure:m', 'Expenditures'],
      ['-', nil, '-'],
      ['Resource', 'resource:m', 'Resources'],
      ['Delegation', 'delegation:m', 'Delegations'],
      ['Registry', 'registry:m', 'Registry'],
      [nil, nil, '_Node'],
      ['Parameter', Gtk::Stock::PROPERTIES, 'Parameters'],
      ['-', nil, '-'],
      ['Key', 'key', 'Keys'],   #Gtk::Stock::GOTO_BOTTOM
      ['Sign', 'sign:m', 'Signs'],
      ['Node', 'node', 'Nodes'],  #Gtk::Stock::NETWORK
      ['Request', 'request:m', 'Requests'],  #Gtk::Stock::SELECT_COLOR
      ['Block', 'block:m', 'Blocks'],
      ['Event', 'event:m', 'Events'],
      ['-', nil, '-'],
      ['Authorize', :auth, 'Authorize', '<control>O', :check], #Gtk::Stock::DIALOG_AUTHENTICATION
      ['Listen', :listen, 'Listen', '<control>L', :check],  #Gtk::Stock::CONNECT
      ['Hunt', :hunt, 'Hunt', '<control>H', :check],   #Gtk::Stock::REFRESH
      ['Radar', :radar, 'Radar', '<control>R', :check],  #Gtk::Stock::GO_FORWARD
      ['Search', Gtk::Stock::FIND, 'Search', '<control>T'],
      ['>', nil, '_Wizards'],
      ['>Profile', Gtk::Stock::HOME, 'Profile'],
      ['>Exchange', 'exchange:m', 'Exchange'],
      ['>Session', 'session:m', 'Sessions', '<control>S'],   #Gtk::Stock::JUSTIFY_FILL
      ['>Fisher', 'fish:m', 'Fishers'],
      ['>Wizard', Gtk::Stock::PREFERENCES.to_s+':m', '_Wizards'],
      ['-', nil, '-'],
      ['>', nil, '_Help'],
      ['>Guide', Gtk::Stock::HELP.to_s+':m', 'Guide', 'F1'],
      ['>Readme', ':m', 'README.TXT'],
      ['>DocPath', Gtk::Stock::OPEN.to_s+':m', 'Documentation'],
      ['>About', Gtk::Stock::ABOUT, '_About'],
      ['Close', Gtk::Stock::CLOSE.to_s+':', '_Close', '<control>W'],
      ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q']
      ]

    # Fill main menu
    # RU: Заполнить главное меню
    def fill_menubar(menubar)
      menu = nil
      sub_menu = nil
      MENU_ITEMS.each do |mi|
        command = mi[0]
        if command.nil? or menu.nil? or ((command.size==1) and (command[0]=='>'))
          menuitem = Gtk::MenuItem.new(_(mi[2]))
          if command and menu
            menu.append(menuitem)
            sub_menu = Gtk::Menu.new
            menuitem.set_submenu(sub_menu)
          else
            menubar.append(menuitem)
            menu = Gtk::Menu.new
            menuitem.set_submenu(menu)
            sub_menu = nil
          end
        else
          menuitem = PandoraGtk.create_menu_item(mi)
          if command and (command.size>1) and (command[0]=='>')
            if sub_menu
              sub_menu.append(menuitem)
            else
              menu.append(menuitem)
            end
          else
            menu.append(menuitem)
          end
        end
      end
    end

    # Fill toolbar
    # RU: Заполнить панель инструментов
    def fill_main_toolbar(toolbar)
      MENU_ITEMS.each do |mi|
        stock = mi[1]
        stock, opts = PandoraGtk.detect_icon_opts(stock)
        if stock and opts.index('t')
          command = mi[0]
          if command and (command.size>0) and (command[0]=='>')
            command = command[1..-1]
          end
          label = mi[2]
          if command and (command.size>1) and label and (label != '-')
            toggle = nil
            toggle = false if mi[4]
            btn = PandoraGtk.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
              do_menu_act(widget)
            end
            btn.name = command
            if (toggle != nil)
              index = nil
              case command
                when 'Authorize'
                  index = SF_Auth
                when 'Listen'
                  index = SF_Listen
                when 'Hunt'
                  index = SF_Hunt
                when 'Radar'
                  index = SF_Radar
              end
              $toggle_buttons[index] = btn if index
            end
          end
        end
      end
    end

    $show_task_notif = true

    # Scheduler parameters (sec)
    # RU: Параметры планировщика (сек)
    CheckTaskPeriod  = 1*60   #5 min
    MassGarbStep   = 30     #30 sec
    CheckBaseStep    = 10     #10 sec
    CheckBasePeriod  = 60*60  #60 min
    # Size of bundle processed at one cycle
    # RU: Размер пачки, обрабатываемой за цикл
    HuntTrain         = 10     #nodes at a heat
    BaseGarbTrain     = 3      #records at a heat
    MassTrain       = 3      #request at a heat
    MassGarbTrain   = 30     #request at a heat

    # Initialize scheduler (tasks, hunter, base gabager, mem gabager)
    # RU: Инициировать планировщик (задачи, охотник, мусорщики баз и памяти)
    def init_scheduler(step=nil)
      step ||= 1.0
      p 'scheduler_step='+step.inspect
      if (not @scheduler) and step
        @scheduler_step = step
        @base_garbage_term = PandoraUtils.get_param('base_garbage_term')
        @base_purge_term = PandoraUtils.get_param('base_purge_term')
        @base_garbage_term ||= 5   #day
        @base_purge_term ||= 30    #day
        @base_garbage_term = (@base_garbage_term * 24*60*60).round   #sec
        @base_purge_term = (@base_purge_term * 24*60*60).round   #sec
        @shed_models ||= {}
        @task_offset = nil
        @task_model = nil
        @task_list = nil
        @task_dialog = nil
        @hunt_node_id = nil
        @mass_garb_offset = 0.0
        @mass_garb_ind = 0
        @base_garb_mode = :arch
        @base_garb_model = nil
        @base_garb_kind = 0
        @base_garb_offset = nil
        @panreg_period = PandoraUtils.get_param('panreg_period')
        if (not(@panreg_period.is_a? Numeric)) or (@panreg_period < 0)
          @panreg_period = 30
        end
        @panreg_period = @panreg_period*60
        @scheduler = Thread.new do
          sleep 1
          while @scheduler_step

            # Update pool time_now
            pool.time_now = Time.now.to_i

            # Task executer
            # RU: Запускальщик Заданий
            if (not @task_dialog) and ((not @task_offset) \
            or (@task_offset >= CheckTaskPeriod))
              @task_offset = 0.0
              user ||= PandoraCrypto.current_user_or_key(true, false)
              if user
                @task_model ||= PandoraUtils.get_model('Task', @shed_models)
                cur_time = Time.now.to_i
                filter = ["(executor=? OR IFNULL(executor,'')='' AND creator=?) AND mode>? AND time<=?", \
                  user, user, 0, cur_time]
                fields = 'id, time, mode, message'
                @task_list = @task_model.select(filter, false, fields, 'time ASC')
                Thread.pass
                if @task_list and (@task_list.size>0)
                  p 'TTTTTTTTTT @task_list='+@task_list.inspect

                  message = ''
                  store = nil
                  if $show_task_notif and $window.visible? \
                  and (PandoraUtils.os_family != 'windows')
                  #and $window.has_toplevel_focus?
                    store = Gtk::ListStore.new(String, String, String)
                  end
                  @task_list.each do |row|
                    time = Time.at(row[1]).strftime('%d.%m.%Y %H:%M:%S')
                    mode = row[2]
                    text = Utf8String.new(row[3])
                    if message.size>0
                      message += '; '
                    else
                      message += _('Tasks')+'> '
                    end
                    message +=  '"' + text + '" ('+time+')'
                    if store
                      iter = store.append
                      iter[0] = time
                      iter[1] = mode.to_s
                      iter[2] = text
                    end
                  end

                  PandoraUtils.log_message(LM_Warning, message)
                  PandoraUtils.play_mp3('message')
                  if $statusicon.message.nil?
                    $statusicon.set_message(message)
                    Thread.new do
                      sleep(10)
                      $statusicon.set_message(nil)
                    end
                  end

                  if store
                    Thread.new do
                      @task_dialog = PandoraGtk::AdvancedDialog.new(_('Tasks'))
                      dialog = @task_dialog
                      image = $window.get_preset_image('task')
                      iconset = image.icon_set
                      style = Gtk::Widget.default_style  #Gtk::Style.new
                      task_icon = iconset.render_icon(style, Gtk::Widget::TEXT_DIR_LTR, \
                        Gtk::STATE_NORMAL, Gtk::IconSize::LARGE_TOOLBAR)
                      dialog.icon = task_icon

                      dialog.set_default_size(500, 350)
                      vbox = Gtk::VBox.new
                      dialog.viewport.add(vbox)

                      treeview = Gtk::TreeView.new(store)
                      treeview.rules_hint = true
                      treeview.search_column = 0
                      treeview.border_width = 10

                      renderer = Gtk::CellRendererText.new
                      column = Gtk::TreeViewColumn.new(_('Time'), renderer, 'text' => 0)
                      column.set_sort_column_id(0)
                      treeview.append_column(column)

                      renderer = Gtk::CellRendererText.new
                      column = Gtk::TreeViewColumn.new(_('Mode'), renderer, 'text' => 1)
                      column.set_sort_column_id(1)
                      treeview.append_column(column)

                      renderer = Gtk::CellRendererText.new
                      column = Gtk::TreeViewColumn.new(_('Text'), renderer, 'text' => 2)
                      column.set_sort_column_id(2)
                      treeview.append_column(column)

                      vbox.pack_start(treeview, false, false, 2)

                      dialog.def_widget = treeview

                      dialog.run2(true) do
                        @task_list.each do |row|
                          id = row[0]
                          @task_model.update({:mode=>0}, nil, {:id=>id})
                        end
                      end
                      @task_dialog = nil
                    end
                  end
                  Thread.pass
                end
              end
            end
            @task_offset += @scheduler_step if @task_offset

            # Hunter
            if false #$window.hunt
              if not @hunt_node_id
                @hunt_node_id = 0
              end
              Thread.pass
              @hunt_node_id += HuntTrain
            end

            # Search robot
            # RU: Поисковый робот
            if (pool.found_ind <= pool.mass_ind) and false #OFFFFF !!!!!
              processed = MassTrain
              while (processed > 0) and (pool.found_ind <= pool.mass_ind)
                search_req = pool.mass_records[pool.found_ind]
                p '####  Search spider  [size, @found_ind, obj_id]='+[pool.mass_records.size, \
                  pool.found_ind, search_req.object_id].inspect
                if search_req and (not search_req[PandoraNet::SA_Answer])
                  req = search_req[PandoraNet::SR_Request..PandoraNet::SR_BaseId]
                  p 'search_req3='+req.inspect
                  answ = nil
                  if search_req[PandoraNet::SR_Kind]==PandoraModel::PK_BlobBody
                    sha1 = search_req[PandoraNet::SR_Request]
                    fn_fs = $window.pool.blob_exists?(sha1, @shed_models, true)
                    if fn_fs.is_a? Array
                      fn_fs[0] = PandoraUtils.relative_path(fn_fs[0])
                      answ = fn_fs
                    end
                  else
                    answ,kind = pool.search_in_local_bases(search_req[PandoraNet::SR_Request], \
                      search_req[PandoraNet::SR_Kind])
                  end
                  p 'SEARCH answ='+answ.inspect
                  if answ
                    search_req[PandoraNet::SA_Answer] = answ
                    answer_raw = PandoraUtils.rubyobj_to_pson([req, answ])
                    session = search_req[PandoraNet::SR_Session]
                    sessions = []
                    if pool.sessions.include?(session)
                      sessions << session
                    end
                    sessions.concat(pool.sessions_of_keybase(nil, \
                      search_req[PandoraNet::SR_BaseId]))
                    sessions.flatten!
                    sessions.uniq!
                    sessions.compact!
                    sessions.each do |sess|
                      if sess.active?
                        sess.add_send_segment(PandoraNet::EC_News, true, answer_raw, \
                          PandoraNet::ECC_News_Answer)
                      end
                    end
                  end
                  #p log_mes+'[to_person, to_key]='+[@to_person, @to_key].inspect
                  #if search_req and (search_req[SR_Session] != self) and (search_req[SR_BaseId] != @to_base_id)
                  processed -= 1
                else
                  processed = 0
                end
                pool.found_ind += 1
              end
            end

            # Mass record garbager
            # RU: Чистильщик массовых сообщений
            if @mass_garb_offset >= MassGarbStep
              @mass_garb_offset = 0.0
              cur_time = Time.now.to_i
              processed = MassGarbTrain
              while (processed > 0)
                if (@mass_garb_ind < pool.mass_records.size)
                  search_req = pool.mass_records[@mass_garb_ind]
                  if search_req
                    time = search_req[PandoraNet::MR_CrtTime]
                    if (not time.is_a? Integer) or (time+$search_live_time<cur_time)
                      pool.mass_records[@mass_garb_ind] = nil
                    end
                  end
                  @mass_garb_ind += 1
                  processed -= 1
                else
                  @mass_garb_ind = 0
                  processed = 0
                end
              end
              pool.mass_records.compact!
            end
            @mass_garb_offset += @scheduler_step

            # Bases garbager
            # RU: Чистильшик баз
            if (not @base_garb_offset) \
            or ((@base_garb_offset >= CheckBaseStep) and @base_garb_kind<255) \
            or (@base_garb_offset >= CheckBasePeriod)
              #p '@base_garb_offset='+@base_garb_offset.inspect
              #p '@base_garb_kind='+@base_garb_kind.inspect
              @base_garb_kind = 0 if @base_garb_offset \
                and (@base_garb_offset >= CheckBasePeriod) and (@base_garb_kind >= 255)
              @base_garb_offset = 0.0
              train_tail = BaseGarbTrain
              while train_tail>0
                if (not @base_garb_model)
                  @base_garb_id = 0
                  while (@base_garb_kind<255) \
                  and (not @base_garb_model.is_a? PandoraModel::Panobject)
                    @base_garb_kind += 1
                    panobjectclass = PandoraModel.panobjectclass_by_kind(@base_garb_kind)
                    if panobjectclass
                      @base_garb_model = PandoraUtils.get_model(panobjectclass.ider, @shed_models)
                    end
                  end
                  if @base_garb_kind >= 255
                    if @base_garb_mode == :arch
                      @base_garb_mode = :purge
                      @base_garb_kind = 0
                    else
                      @base_garb_mode = :arch
                    end
                  end
                end

                if @base_garb_model
                  if @base_garb_mode == :arch
                    arch_time = Time.now.to_i - @base_garbage_term
                    filter = ['id>=? AND modified<? AND IFNULL(panstate,0)=0', \
                      @base_garb_id, arch_time]
                  else # :purge
                    purge_time = Time.now.to_i - @base_purge_term
                    filter = ['id>=? AND modified<? AND panstate>=?', @base_garb_id, \
                      purge_time, PandoraModel::PSF_Archive]
                  end
                  #p 'Base garbager [ider,mode,filt]: '+[@base_garb_model.ider, @base_garb_mode, filter].inspect
                  sel = @base_garb_model.select(filter, false, 'id', 'id ASC', train_tail)
                  #p 'base_garb_sel='+sel.inspect
                  if sel and (sel.size>0)
                    sel.each do |row|
                      id = row[0]
                      @base_garb_id = id
                      #p '@base_garb_id='+@base_garb_id.inspect
                      values = nil
                      if @base_garb_mode == :arch
                        # mark the record as deleted, else purge it
                        values = {:panstate=>PandoraModel::PSF_Archive}
                      end
                      @base_garb_model.update(values, nil, {:id=>id})
                    end
                    train_tail -= sel.size
                    @base_garb_id += 1
                  else
                    @base_garb_model = nil
                  end
                  Thread.pass
                else
                  train_tail = 0
                end
              end
            end
            @base_garb_offset += @scheduler_step if @base_garb_offset

            # GUI updater (list, traffic)

            # PanReg node registration
            # RU: Регистратор узлов PanReg
            if (@node_reg_offset.nil? or (@node_reg_offset >= @panreg_period))
              @node_reg_offset = 0.0
              PandoraNet.register_node_ips
            end
            @node_reg_offset += @scheduler_step if @node_reg_offset


            sleep(@scheduler_step)

            #p 'Next scheduler step'

            Thread.pass
          end
          @scheduler = nil
        end
      end
    end

    $pointoff = nil

    # Show main Gtk window
    # RU: Показать главное окно Gtk
    def initialize(*args)
      super(*args)
      $window = self
      @hunter_count = @listener_count = @fisher_count = @node_reg_offset = 0

      @icon_factory = Gtk::IconFactory.new
      @icon_factory.add_default

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

      @accel_group = Gtk::AccelGroup.new
      $window.add_accel_group(accel_group)

      $window.register_stock(:save)

      @menubar = Gtk::MenuBar.new
      fill_menubar(menubar)

      @toolbar = Gtk::Toolbar.new
      toolbar.show_arrow = true
      toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
      fill_main_toolbar(toolbar)

      #frame = Gtk::Frame.new
      #frame.shadow_type = Gtk::SHADOW_IN
      #align = Gtk::Alignment.new(0.5, 0.5, 0, 0)
      #align.add(frame)
      #image = Gtk::Image.new
      #frame.add(image)

      @notebook = Gtk::Notebook.new
      notebook.show_border = false
      notebook.scrollable = true
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        cur_page = notebook.get_nth_page(page_num)
        if $last_page and (cur_page != $last_page) \
        and ($last_page.is_a? PandoraGtk::CabinetBox)
          if $last_page.area_send and (not $last_page.area_send.destroyed?)
            $last_page.init_video_sender(false, true)
          end
          if $last_page.area_recv and (not $last_page.area_recv.destroyed?)
            $last_page.init_video_receiver(false)
          end
        end
        if cur_page.is_a? PandoraGtk::CabinetBox
          cur_page.update_state(false, cur_page)
          if cur_page.area_recv and (not cur_page.area_recv.destroyed?)
            cur_page.init_video_receiver(true, true, false)
          end
          if cur_page.area_send and (not cur_page.area_send.destroyed?)
            cur_page.init_video_sender(true, true)
          end
        end
        PandoraGtk.update_treeview_if_need(cur_page)
        $last_page = cur_page
      end

      @log_view = PandoraGtk::ExtTextView.new
      log_view.set_readonly(true)
      log_view.border_width = 0

      @log_sw = Gtk::ScrolledWindow.new(nil, nil)
      log_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      log_sw.shadow_type = Gtk::SHADOW_IN
      log_sw.add(log_view)
      log_sw.border_width = 0;
      log_sw.set_size_request(-1, 60)

      @radar_sw = RadarScrollWin.new
      radar_sw.set_size_request(0, -1)

      #note_sw = Gtk::ScrolledWindow.new(nil, nil)
      #note_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      #note_sw.border_width = 0
      #@viewport = Gtk::Viewport.new(nil, nil)
      #sw.add(viewport)

      @radar_hpaned = Gtk::HPaned.new
      #note_sw.add_with_viewport(notebook)
      #@radar_hpaned.pack1(note_sw, true, true)
      @radar_hpaned.pack1(notebook, true, true)
      @radar_hpaned.pack2(radar_sw, false, true)
      #@radar_hpaned.position = 1
      #p '****'+@radar_hpaned.allocation.width.inspect
      #@radar_hpaned.position = @radar_hpaned.max_position
      #@radar_hpaned.position = 0
      @radar_hpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_fish_btn_state
      end

      @log_vpaned = Gtk::VPaned.new
      log_vpaned.border_width = 2
      log_vpaned.pack1(radar_hpaned, true, true)
      log_vpaned.pack2(log_sw, false, true)
      log_vpaned.signal_connect('notify::position') do |widget, param|
        $window.correct_log_btn_state
      end

      #@cvpaned = CaptchaHPaned.new(vpaned)
      #@cvpaned.position = cvpaned.max_position

      $statusbar = Gtk::HBox.new
      $statusbar.spacing = 1
      $statusbar.border_width = 0
      #$statusbar = Gtk::Statusbar.new
      #PandoraGtk.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

      add_status_field(SF_Log, nil, 'Logbar', :log, false, 0) do
        do_menu_act('LogBar')
      end
      add_status_field(SF_FullScr, nil, 'Full screen', Gtk::Stock::FULLSCREEN, false, 0) do
        do_menu_act('FullScr')
      end

      path = $pandora_app_dir
      path = '..'+path[-40..-1] if path.size>40
      pathlabel = Gtk::Label.new(path)
      pathlabel.modify_font(PandoraGtk.status_font)
      pathlabel.justify = Gtk::JUSTIFY_LEFT
      pathlabel.set_padding(1, 1)
      pathlabel.set_alignment(0.0, 0.5)
      $statusbar.pack_start(pathlabel, true, true, 0)

      add_status_field(SF_Update, _('Version') + ': ' + _('Not checked'), 'Update') do
        PandoraGtk.start_updating(true)
      end
      add_status_field(SF_Lang, $lang, 'Language') do
        do_menu_act('Blob')
      end
      add_status_field(SF_Auth, _('Not logged'), 'Authorize', :auth, false) do
        do_menu_act('Authorize')          #Gtk::Stock::DIALOG_AUTHENTICATION
      end
      add_status_field(SF_Listen, '0', 'Listen', :listen, false) do
        do_menu_act('Listen')
      end
      add_status_field(SF_Hunt, '0', 'Hunting', :hunt, false) do
        do_menu_act('Hunt')
      end
      add_status_field(SF_Fisher, '0', 'Fishers', :fish) do
        do_menu_act('Fisher')
      end
      add_status_field(SF_Conn, '0', 'Sessions', :session) do
        do_menu_act('Session')
      end
      add_status_field(SF_Radar, '0', 'Radar', :radar, false) do
        do_menu_act('Radar')
      end
      add_status_field(SF_Harvest, '0', 'Files', :blob) do
        do_menu_act('Blob')
      end
      add_status_field(SF_Search, '0', 'Search', Gtk::Stock::FIND) do
        do_menu_act('Search')
      end
      resize_eb = Gtk::EventBox.new
      resize_eb.events = Gdk::Event::BUTTON_PRESS_MASK | Gdk::Event::POINTER_MOTION_MASK \
        | Gdk::Event::ENTER_NOTIFY_MASK | Gdk::Event::LEAVE_NOTIFY_MASK
      resize_eb.signal_connect('enter-notify-event') do |widget, param|
        window = widget.window
        window.cursor = Gdk::Cursor.new(Gdk::Cursor::BOTTOM_RIGHT_CORNER)
      end
      resize_eb.signal_connect('leave-notify-event') do |widget, param|
        window = widget.window
        window.cursor = nil #Gdk::Cursor.new(Gdk::Cursor::XTERM)
      end
      resize_eb.signal_connect('button-press-event') do |widget, event|
        if (event.button == 1)
          point = $window.window.pointer[1,2]
          wh = $window.window.geometry[2,2]
          $pointoff = [(wh[0]-point[0]), (wh[1]-point[1])]
          if $window.window.state == Gdk::EventWindowState::MAXIMIZED
            wbord = 6
            w, h = [(point[0]+$pointoff[0]-wbord), (point[1]+$pointoff[1]-wbord)]
            $window.move(0, 0)
            $window.set_default_size(w, h)
            $window.resize(w, h)
            $window.unmaximize
            $window.move(0, 0)
            $window.set_default_size(w, h)
            $window.resize(w, h)
          end
        end
        false
      end
      resize_eb.signal_connect('motion-notify-event') do |widget, event|
        if $pointoff
          point = $window.window.pointer[1,2]
          $window.resize((point[0]+$pointoff[0]), (point[1]+$pointoff[1]))
        end
        false
      end
      resize_eb.signal_connect('button-release-event') do |widget, event|
        if (event.button == 1) and $pointoff
          window = widget.window
          $pointoff = nil
        end
        false
      end
      $window.register_stock(:resize)
      resize_image = Gtk::Image.new(:resize, Gtk::IconSize::MENU)
      resize_image.set_padding(0, 0)
      resize_image.set_alignment(1.0, 1.0)
      resize_eb.add(resize_image)
      $statusbar.pack_start(resize_eb, false, false, 0)

      vbox = Gtk::VBox.new
      vbox.pack_start(menubar, false, false, 0)
      vbox.pack_start(toolbar, false, false, 0)
      #vbox.pack_start(cvpaned, true, true, 0)
      vbox.pack_start(log_vpaned, true, true, 0)
      stat_sw = Gtk::ScrolledWindow.new(nil, nil)
      stat_sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_NEVER)
      stat_sw.border_width = 0
      iw, iy = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
      stat_sw.height_request = iy+6
      #stat_sw.add_with_viewport($statusbar)
      stat_sw.add($statusbar)
      vbox.pack_start(stat_sw, false, false, 0)

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
        elsif ([Gdk::Keyval::GDK_h, Gdk::Keyval::GDK_H].include?(event.keyval) \
        and event.state.control_mask?)
          continue = (not event.state.shift_mask?)
          PandoraNet.start_or_stop_hunt(continue)
        elsif event.keyval == Gdk::Keyval::GDK_F5
          do_menu_act('Hunt')
        elsif event.state.control_mask? \
        and (Gdk::Keyval::GDK_0..Gdk::Keyval::GDK_9).include?(event.keyval)
          num = $window.notebook.n_pages
          if num>0
            n = (event.keyval - Gdk::Keyval::GDK_1)
            if (n>=0) and (n<num)
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
          $window.do_menu_act('Quit')
        elsif ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W, 1731, 1763].include?(event.keyval) \
        and event.state.control_mask?) #w, W, ц, Ц
          $window.do_menu_act('Close')
        elsif event.state.control_mask? \
        and [Gdk::Keyval::GDK_d, Gdk::Keyval::GDK_D, 1751, 1783].include?(event.keyval)
          curpage = nil
          if $window.notebook.n_pages>0
            curpage = $window.notebook.get_nth_page($window.notebook.page)
          end
          if curpage.is_a? PandoraGtk::PanobjScrolledWindow
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
            if (sw.is_a? CabinetBox) and (not sw.destroyed?)
              sw.init_video_sender(false, true) if sw.area_send and (not sw.area_send.destroyed?)
              sw.init_video_receiver(false) if sw.area_recv and (not sw.area_recv.destroyed?)
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
      @do_on_start = PandoraUtils.get_param('do_on_start')
      @title_view = PandoraUtils.get_param('title_view')
      @title_view ||= TV_Name

      #$window.signal_connect('show') do |window, event|
      #  false
      #end

      @pool = PandoraNet::Pool.new($window)

      $window.set_default_size(640, 420)
      $window.maximize
      $window.show_all

      @radar_hpaned.position = @radar_hpaned.max_position
      @log_vpaned.position = @log_vpaned.max_position
      if $window.do_on_start and ($window.do_on_start > 0)
        dialog_timer = GLib::Timeout.add(400) do
          key = PandoraCrypto.current_key(false, true)
          if (($window.do_on_start & 2) != 0) and key
            PandoraNet.start_or_stop_listen(true)
          end
          if (($window.do_on_start & 4) != 0) and key and (not $hunter_thread)
            PandoraNet.start_or_stop_hunt(true, 2)
          end
          $window.do_on_start = 0
          false
        end
      end
      scheduler_step = PandoraUtils.get_param('scheduler_step')
      init_scheduler(scheduler_step)


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
                  if (child.is_a? CabinetBox) and (child.has_unread)
                    $window.notebook.page = $window.notebook.children.index(child)
                    break
                  end
                end
                curpage = $window.notebook.get_nth_page($window.notebook.page)
                if (curpage.is_a? PandoraGtk::CabinetBox) and toplevel
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

      check_update = PandoraUtils.get_param('check_update')
      if (check_update==1) or (check_update==true)
        last_check = PandoraUtils.get_param('last_check')
        last_check ||= 0
        last_update = PandoraUtils.get_param('last_update')
        last_update ||= 0
        check_interval = PandoraUtils.get_param('check_interval')
        if (not(check_interval.is_a? Numeric)) or (check_interval <= 0)
          check_interval = 1
        end
        update_period = PandoraUtils.get_param('update_period')
        if (not(update_period.is_a? Numeric)) or (update_period < 0)
          update_period = 1
        end
        time_now = Time.now.to_i
        ok_version = (time_now - last_update.to_i) < update_period*24*3600
        need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
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
$country = 'US'
$lang = 'en'
$autodetect_lang = true
$pandora_parameters = []

# Paths and files
# RU: Пути и файлы
$pandora_app_dir = Dir.pwd                                     # Current directory
$pandora_base_dir = File.join($pandora_app_dir, 'base')        # Database directory
$pandora_view_dir = File.join($pandora_app_dir, 'view')        # Media files directory
$pandora_model_dir = File.join($pandora_app_dir, 'model')      # Model directory
$pandora_lang_dir = File.join($pandora_app_dir, 'lang')        # Languages directory
$pandora_util_dir = File.join($pandora_app_dir, 'util')        # Utilites directory
$pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Database file
$pandora_files_dir = File.join($pandora_app_dir, 'files')      # Files directory
$pandora_doc_dir = File.join($pandora_app_dir, 'doc')          # Doc directory

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки
arg = nil
val = nil
next_arg = nil
ARGVdup = ARGV.dup
while (ARGVdup.size>0) or next_arg
  if next_arg
    arg = next_arg
    next_arg = nil
  else
    arg = ARGVdup.shift
  end
  if (arg.is_a? String) and (arg[0,1]=='-')
    if ARGVdup.size>0
      next_arg = ARGVdup.shift
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
    when '-l', '--lang'
      if val
        $lang = val
        $autodetect_lang = false
        p 'setted language '+$lang.inspect
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
      puts runit+'-p '+PandoraNet::DefTcpPort.to_s+'         - set listen port'
      puts runit+'-b base/pandora2.sqlite  - set filename of database'
      puts runit+'-l ua           - set Ukrainian language'
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
ANOTHER_COPY_MES = 'Another copy of Pandora is already runned'

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
      puts ANOTHER_COPY_MES
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
  elsif (PandoraUtils.os_family=='windows')
    if PandoraUtils.win_activate_window(GTK_WINDOW_CLASS, MAIN_WINDOW_TITLE)
      Kernel.abort(ANOTHER_COPY_MES)
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
      elsif str.nil?
        super('')
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

# WinAPI constants for work with the registry
# RU: Константы WinAPI для работы с реестром
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
if $autodetect_lang
  lang = ENV['LANG']
  if (lang.is_a? String) and (lang.size>1)
    $lang = lang[0, 2].downcase
    $country = lang[3, 2].upcase
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
      if (lang.is_a? String) and (lang.size>1)
        $lang = lang[0, 2].downcase
        if (lang.size>4) and (lang[2]=='-')
          $country = lang[3, 2]
        else
          $country = $lang
        end
        $country = $country.upcase
      end
    end
  end
end

#$lang = 'ua'

# Some settings
# RU: Некоторые настройки
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# === Running the Pandora!
# === RU: Запуск Пандоры!
PandoraUtils.load_language($lang)
PandoraModel.load_model_from_xml($lang)
PandoraUtils.detect_mp3_player
$base_id = PandoraUtils.get_param('base_id')
PandoraGtk::MainWindow.new(MAIN_WINDOW_TITLE)

# Free unix-socket on exit
# Освободить unix-сокет при выходе
$pserver.close if ($pserver and (not $pserver.closed?))
delete_psocket


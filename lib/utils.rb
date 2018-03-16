#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Utilites module of Pandora
# RU: Вспомогательный модуль Пандоры
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

module PandoraUtils

  # Version of GUI application
  # RU: Версия GUI приложения
  PandoraVersion  = '0.73'

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

  # Get language file name
  # RU: Взять имя языкового файла
  def self.get_lang_file(lang='ru')
    res = File.join($pandora_lang_dir, lang+'.txt')
    res
  end

  # Maximal depth for diving to cognate language files
  # RU: Глубина погружения по родственным языковым файлам
  MaxCognateDeep = 3

  # Load translated phrases
  # RU: Загрузить переводы фраз
  def self.load_language(lang='ru', cognate_call=nil, lang_trans=nil)

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

    res = nil
    lang_trans = $lang_trans if not lang_trans
    if cognate_call.nil?
      cognate_call = MaxCognateDeep
      lang_trans.clear
    end
    cognate = nil
    langfile = get_lang_file(lang)
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
            if (line.size>0)
              if (line[0, 1] == '#')
                if cognate.nil? and (line[0, 10] == '#!cognate=')
                  cognate = line[10..-1]
                  cognate.strip! if cognate
                  cognate.downcase! if cognate
                  if ((cognate.is_a? String) and (cognate.size>0) \
                  and (cognate != lang)  and (cognate_call == MaxCognateDeep))
                    lang_trans['#!cognate'] ||= cognate
                  end
                end
              else
                if line[0, 1] != '"'
                  frase, trans = line.split('=>')
                  if (frase != '') and (trans != '')
                    if cognate_call
                      lang_trans[frase] ||= trans
                    else
                      lang_trans[frase] = trans
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
                  lang_trans[frase] ||= trans
                else
                  lang_trans[frase] = trans
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
      if ((cognate.is_a? String) and (cognate.size>0) \
      and (cognate != lang) and (cognate_call>0))
        lang_trans['#!cognate'] ||= cognate
        load_language(cognate, cognate_call-1)
      end
      res = true
    end
    res
  end

  # Save language phrases
  # RU: Сохранить языковые фразы
  def self.save_as_language(lang='ru', lang_trans=nil)

    # RU: Экранирует кавычки слэшем
    def self.slash_quotes(str)
      str.gsub('"', '\"')
    end

    # RU: Есть конечный пробел или табуляция?
    def self.end_space_exist?(str)
      lastchar = str[str.size-1, 1]
      (lastchar==' ') or (lastchar=="\t")
    end

    res = nil
    lang_trans = $lang_trans if not lang_trans
    langfile = get_lang_file(lang)

    cognate = lang_trans['#!cognate']
    cog_lang_trans = nil
    if (cognate.is_a? String) and (cognate.size>0) and (cognate != lang)
      cog_lang_trans = Hash.new
      if not load_language(cognate, MaxCognateDeep-1, cog_lang_trans)
        cog_lang_trans = nil
      end
    else
      cognate = nil
    end

    File.open(langfile, 'w') do |file|
      file.puts('# Pandora language file EN=>'+lang.upcase)
      file.puts('# See full list of phrases in "ru.txt" file') if (lang != 'ru')
      file.puts('#!cognate='+cognate) if cognate
      lang_trans.each do |key,val|
        if key and (key.size>1) and val and (val.size>1) and (key != '#!cognate')
          cog_equal = nil
          if cog_lang_trans
            cog_val = cog_lang_trans[key]
            cog_equal = (cog_val and (cog_val == val))
          end
          if (not cog_equal)
            str = ''
            if (key[0, 1]=='"' or val[0, 1]=='"' \
            or key.index("\n") or val.index("\n") \
            or end_space_exist?(key) or end_space_exist?(val))
              str = '"'+slash_quotes(key)+'"=>"'+slash_quotes(val)+'"'
            else
              str = key+'=>'+val
            end
            file.puts(str)
          end
        end
      end
      res = true
    end
    res
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
          #p res
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

  # Unzip archive via internal library
  # RU: Распаковывает архив с помощью внутренней библиотеки
  def self.unzip_via_lib(arch, path, overwrite=true)
    res = nil
    if $rubyzip.nil?
      begin
        require 'rubygems'
        require 'zip/zip'
        $rubyzip = true
      rescue Exception
        $rubyzip = false
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

  $unziper = nil  # Unzip utility

  # Unzip archive via external utility
  # RU: Распаковывает архив с помощью внешней утилиты
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
    if panhash.is_a?(String)
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

  # Drop kind (1st char) and language (2nd char) from panhash
  # RU: Убрать тип и язык из панхэша
  def self.phash(panhash, len=nil)
    res = nil
    if (panhash.is_a? String) and (panhash.bytesize>2)
      len ||= 20
      res = panhash[2, len]
    end
    res
  end

  # Get value as is, or 1st element if it's array
  # RU: Вернуть само значение, или 1й элемент, если это вектор
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

  # Is string in a hexadecimal view?
  # RU: Строка в шестнадцатиричном виде?
  def self.hex?(value)
    res = (/^[0-9a-fA-F]*$/ === value)
  end

  # Is string in a decimal view?
  # RU: Строка в десятичном виде?
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

  # Convert Ruby 4-byte data-time to Pandora 3-byte date
  # RU: Преобразует 4х-байтную руби-дату в 3х-байтную пандорскую
  def self.date_to_date3(date)
    res = date.to_i / (24*60*60)   #obtain days, drop hours and seconds
    res += (1970-1900)*365         #mesure data from 1900
  end

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

  # Scan string on substrings and return Array with positions
  # RU: Сканирует строку на подстроки и возвращает массив позиций
  def self.find_all_substr(str, substr, positions, max, case_sens=true)
    res = nil
    if str and substr
      if not case_sens
        str.upcase!
        substr.upcase!
      end
      len = str.size
      slen = substr.size
      i = 0
      pos = -1
      while pos and (pos+slen <= len) and (i<max)
        pos = str.index(substr, pos+slen)
        if pos
          positions[i] = pos
          i += 1
        end
      end
      res = i
    end
    res
  end

  CR_EOL = "\r"  #0x0D.chr
  LF_EOL = "\n"  #0x0A.chr
  CRLF_EOL = CR_EOL + LF_EOL

  def self.correct_newline_codes(text, crlf=nil)
    #res = text
    res = AsciiString.new(text)
    res.gsub!(CRLF_EOL, LF_EOL)
    res.gsub!(CR_EOL, '')
    res.gsub!(LF_EOL, CRLF_EOL) if crlf
    #Utf8String.new(res)
    res
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
            #val = PandoraUtils.bytes_to_hex(val[2,16])
            val = PandoraUtils.bytes_to_hex(val[2,20])
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
        when 'byte'
          val = val.to_i
          if val>255
            val = 255
          elsif val<0
            val = 0
          end
        when 'word'
          val = val.to_i
          if val>65535
            val = 65535
          elsif val<0
            val = 0
          end
        when 'integer', 'coord', 'bytelist'
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
  # RU: Катушечную координату (4-байтовое целое) в географическую координату
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

  def self.sort_complex_array(array)
    res = array.sort do |a, b|
      com = 0
      if ((a.is_a?(Numeric) and b.is_a?(Numeric)) or (a.is_a?(Time) and b.is_a?(Time)))
        com = (a <=> b)
      else
        a = a.to_s if a.is_a?(Symbol)
        b = b.to_s if b.is_a?(Symbol)
        if a.is_a?(String) and b.is_a?(String)
          com = (a <=> b)
        else
          if a.is_a?(Numeric)
            com = -1
          elsif b.is_a?(Numeric)
            com = 1
          elsif a.is_a?(Time)
            com = -1
          elsif b.is_a?(Time)
            com = 1
          elsif a.is_a?(String)
            com = -1
          elsif b.is_a?(String)
            com = 1
          elsif (a.class == b.class)
            com = (a.inspect <=> b.inspect)
          else
            com = (a.class.name <=> b.class.name)
          end
        end
      end
      com
    end
    res
  end

  def self.sort_complex_hash(hash)
    res = hash.sort_by do |k,v|
      com = k
      if not k.is_a?(String)
        if (k.is_a?(Symbol) or k.is_a?(Numeric) or k.is_a?(Time))
          com = k.to_s
        else
          com = k.inspect
        end
      end
      com
    end
    res
  end

  # Convert ruby object to PSON (Pandora Simple Object Notation)
  # RU: Конвертирует объект руби в PSON
  # sort_mode: nil or false - don't sort, 1 - sort array, 2 - sort hash
  # 3 or true - sort arrays and hashes
  def self.rubyobj_to_pson(rubyobj, sort_mode=nil)
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
        if (sort_mode and ((not sort_mode.is_a?(Integer)) or ((sort_mode & 1)>0)))
          rubyobj = self.sort_complex_array(rubyobj)
        end
        rubyobj.each do |a|
          data << rubyobj_to_pson(a, sort_mode)
        end
        elem_size = rubyobj.size
        type, count, neg = encode_pson_type(PT_Array, elem_size)
      when Hash
        if (sort_mode and ((not sort_mode.is_a?(Integer)) or ((sort_mode & 2)>0)))
          #rubyobj = rubyobj.sort_by {|k,v| k.to_s}
          rubyobj = self.sort_complex_hash(rubyobj)
        end
        elem_size = 0
        rubyobj.each do |a|
          data << rubyobj_to_pson(a[0], sort_mode) << rubyobj_to_pson(a[1], sort_mode)
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
              val = val.unpack('D')[0]
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
  def self.hash_to_namepson(fldvalues, pack_empty=false, sort_mode=2)
    #bytes = ''
    #bytes.force_encoding('ASCII-8BIT')
    bytes = AsciiString.new
    fldvalues = fldvalues.sort_by {|k,v| k.to_s } if sort_mode
    fldvalues.each do |nam, val|
      if pack_empty or (not value_is_empty?(val))
        nam = nam.to_s
        nsize = nam.bytesize
        nsize = 255 if nsize>255
        bytes << [nsize].pack('C') + nam[0, nsize]
        pson_elem = rubyobj_to_pson(val, sort_mode)
        bytes << pson_elem
      end
    end
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
        if res=='JPEG'
          res = 'JPG'
        elsif res=='RB'
          res = 'RUBY'
        elsif res=='PY'
          res = 'PYTHON'
        elsif res=='HTM'
          res = 'HTML'
        end
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
    res = File.join($pandora_app_dir, 'pandora.rb')
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
          PandoraUI.log_message(PandoraUI::LM_Error, \
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
          PandoraUI.log_message(PandoraUI::LM_Error, \
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
          PandoraUI.log_message(PandoraUI::LM_Error, \
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
        #p 'update: sql='+sql.inspect+' sql_values='+sql_values.inspect
        begin
          res = db.execute(sql, sql_values)
          res = true
        rescue => err
          res = false
          PandoraUI.log_message(PandoraUI::LM_Error, \
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

      def field_des(fld_name, fields=nil)
        fields ||= def_fields
        df = fields.detect{ |e| (e.is_a? Array) \
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
        if (not @table_is_checked) #and $window
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
                PandoraUI.log_message(PandoraUI::LM_Warning, \
                  (_('New fields %s were added in table') % ('['+flds+\
                  ']')) + ' ['+pname+']')
              else
                PandoraUI.log_message(PandoraUI::LM_Error, \
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

    def field_des(fld_name, fields=nil)
      self.class.field_des(fld_name, fields)
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
      #p '-1--fval='+fval.inspect+'  hfor='+hfor.inspect
      if fval and ((not (fval.is_a? String)) or (fval.bytesize>0))
        #p '-2--fval='+fval.inspect+'  hfor='+hfor.inspect
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
          if fval.is_a?(Time)
            res = fval
          elsif fval.is_a?(Integer)
            res = Time.at(fval)
          elsif fval.is_a?(String)
            res = Time.parse(fval)
          end
          res = PandoraUtils.date_to_date3(res)
        else
          if fval.is_a?(Integer)
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
        #p '++++[fval, fname, values]='+[fval, fname, values].inspect
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
    param_model = PandoraUtils.get_model('Parameter')
    if param_model
      id = nil
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
    end
    value
  end

  # Set parameter value (delete if value=nil)
  # RU: Задаёт значение параметра (удаляет если value=nil)
  def self.set_param(name, value)
    res = false
    #p 'set_param [name, value]='+[name, value].inspect
    old_value, id = PandoraUtils.get_param(name, true)
    param_model = PandoraUtils.get_model('Parameter')
    if ((value != old_value) or value.nil?) and param_model
      value = {:value=>value, :modified=>Time.now.to_i} if value
      res = param_model.update(value, nil, 'id='+id.to_s)
    end
    res
  end

  # Initialize ID of database
  # RU: Инициализировать ID базы данных
  def self.init_base_id
    $base_id = PandoraUtils.get_param('base_id')
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
    def add_block_to_queue(block, max=nil)
      res = nil
      max ||= MaxQueue
      if block
        self.synchronize do
          res = @write_ind
          if res<max
            res += 1
          else
            res = 0
          end
          @queue[res] = block
          @write_ind = res
        end
        res = true
      end
      res
    end

    # Reader state
    # RU: Состояние читальщика
    QRS_Empty     = 0
    QRS_NotEmpty  = 1
    QRS_Full      = 2

    # State of reader
    # RU: Состояние читателя
    def read_state(max=nil, reader=nil)
      res = QRS_Empty
      max ||= MaxQueue
      if @write_ind>=0
        rind = @read_ind
        if not reader.nil?
          rind = rind[reader]
          rind ||= -1
        end
        if rind.is_a?(Integer) and (rind>=0)
          wind = @write_ind
          if (rind != wind)
            if wind<max
              wind += 1
            else
              wind = 0
            end
            if (rind == wind)
              res = QRS_Full
            else
              res = QRS_NotEmpty
            end
          end
        else
          res = QRS_NotEmpty
        end
      end
      res
    end

    # Get block from queue ("reader" is any object)
    # RU: Взять блок из очереди ("reader" - любой объект)
    def get_block_from_queue(max=nil, reader=nil, move_ptr=true)
      block = nil
      max ||= MaxQueue
      ind = @read_ind
      if not reader.nil?
        ind = @read_ind[reader]
        ind ||= -1
      end
      #p 'get_block_from_queue:  [reader, ind, write_ind]='+[reader, ind, write_ind].inspect
      if ind != @write_ind
        if ind<max
          ind += 1
        else
          ind = 0
        end
        block = @queue[ind]
        if move_ptr
          if reader.nil?
            @read_ind = ind
          else
            @read_ind[reader] = ind
          end
        end
      end
      block
    end

    # Delete a read pointer from the pointer list
    # RU: Удалить указатель чтения из списка указателей
    def delete_read_pointer(reader=nil, limit=nil)
      if @read_ind.is_a?(Hash) and (limit.nil? or (@read_ind.size>limit))
        @read_ind.delete(reader)
      end
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
      cr.select_font_face(CapFonts[rand(CapFonts.size)], Cairo::FONT_SLANT_NORMAL, \
        Cairo::FONT_WEIGHT_NORMAL)
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
        #$mp3_player = 'mplay32 /play /close'
        $mp3_player = nil
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
          buf = 0.chr * (len * 2)
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
      $waShellExecute ||= Win32API.new('shell32', 'ShellExecuteW', \
        ['L', 'P', 'P', 'P', 'P', 'L'], 'L')
      if $waShellExecute
        #puts 'win_shell_execute [link, oper]='+[link, oper].inspect
        link = win_utf8_to_unicode(link)
        oper = win_utf8_to_unicode(oper.to_s) if oper
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

  # Get Pandora version
  # RU: Возвращает версию Пандоры
  def self.pandora_version
    res = PandoraVersion
  end

  LIB_LIST = ['crypto', 'gtk', 'model', 'ncurses', 'net', 'ui', 'utils']

  # Calc hex md5 of Pandora files
  # RU: Вычисляет шестнадцатиричный md5 файлов Пандоры
  def self.pandora_md5_sum
    res = nil
    begin
      md5 = Digest::MD5.file(PandoraUtils.main_script)
      res = md5.digest
    rescue
    end
    LIB_LIST.each do |alib|
      fn = File.join($pandora_lib_dir, alib+'.rb')
      if File.exist?(fn)
        begin
          md5 = Digest::MD5.file(fn)
          res2 = md5.digest
          i = 0
          res2.each_byte do |c|
            res[i] = (res[i].ord ^ c).chr
            i += 1
          end
        rescue
        end
      end
    end
    if res.is_a?(String)
      res = PandoraUtils.bytes_to_hex(res)
    else
      res = 'fail'
    end
    res
  end

  $poly_play   = false
  $play_thread = nil
  Default_Mp3 = 'message'

  # Play mp3
  # RU: Проиграть mp3
  def self.play_mp3(filename, path=nil, anyway=nil)
    if ($mp3_player and ($poly_play or (not $play_thread)) and (anyway \
    or (PandoraUI.play_sounds? and (filename.is_a? String) and (filename.size>0))))
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


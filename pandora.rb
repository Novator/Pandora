#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# The Pandora. Free peer-to-peer information system
# RU: Пандора. Свободная пиринговая информационная система
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

# Platform detection
# RU: Определение платформы
def os_family
  case RUBY_PLATFORM
    when /ix/i, /ux/i, /gnu/i, /sysv/i, /solaris/i, /sunos/i, /bsd/i
      'unix'
    when /win/i, /ming/i
      'windows'
    else
      'other'
  end
end

# Default values of variables
# RU: Значения переменных по умолчанию
$host = '127.0.0.1'
$port = 5577
$base_index = 0
$poly_launch = false
$pandora_parameters = []

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
  if arg.is_a? String and (arg[0,1]=='-')
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
      $port = val.to_i if val
    when '-bi'
      $base_index = val.to_i if val
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
      puts runit+'-h localhost   - set listen address'
      puts runit+'-p 5577        - set listen port'
      puts runit+'-bi 0          - set index of database'
      Kernel.exit!
  end
  val = nil
end

MAIN_WINDOW_TITLE = 'Pandora'

# Prevent second execution
# RU: Предотвратить второй запуск
if not $poly_launch
  if os_family=='unix'
    res = `ps -few | grep pandora.rb | grep -v grep`
    res = res.scan("\n").count if res
    if res>1
      Kernel.abort('Another copy of Pandora is already runned')
    end
  elsif os_family=='windows'
    require 'Win32API'
    FindWindow = Win32API.new('user32', 'FindWindowA', ['P', 'P'], 'L')
    win_handle = FindWindow.call(nil, MAIN_WINDOW_TITLE)
    if win_handle != 0
      SetForegroundWindow = Win32API.new('user32', 'SetForegroundWindow', 'L', 'V')
      SetForegroundWindow.call(win_handle)
      ShowWindow = Win32API.new('user32', 'ShowWindow', 'L', 'V')
      ShowWindow.call(win_handle, 5)  #WM_SHOW
      SetForegroundWindow.call(win_handle)
      Kernel.abort('Another copy of Pandora is already runned')
    end
  end
end

if RUBY_VERSION<'1.9'
  puts 'The Pandora needs Ruby 1.9 or higher (current '+RUBY_VERSION+')'
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
      if str == nil
        super('')
      else
        super(str)
      end
      force_encoding('UTF-8')
    end
  end
  Encoding.default_external = 'UTF-8'
  Encoding.default_internal = 'UTF-8' #BINARY ASCII-8BIT UTF-8
end

# Paths and files  ('join' gets '/' for Linux and '\' for Windows)
# RU: Пути и файлы ('join' дает '/' для Линукса и '\' для Винды)
#if os_family != 'windows'
$pandora_root_dir = Dir.pwd                                       # Current Pandora directory
#  $pandora_root_dir = File.expand_path(File.dirname(__FILE__))     # Script directory
#else
#  $pandora_root_dir = '.'     # It prevents a bug with cyrillic paths in Win XP
#end
$pandora_base_dir = File.join($pandora_root_dir, 'base')            # Default database directory
$pandora_view_dir = File.join($pandora_root_dir, 'view')            # Media files directory
$pandora_model_dir = File.join($pandora_root_dir, 'model')          # Model description directory
$pandora_lang_dir = File.join($pandora_root_dir, 'lang')            # Languages directory
$pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Default database file
$pandora_sqlite_db2 = File.join($pandora_base_dir, 'pandora2.sqlite')  # Default database file
$pandora_sqlite_db3 = File.join($pandora_base_dir, 'pandora3.sqlite')  # Default database file

# If it's runned under WinOS, redirect console output to file, because of rubyw.exe crush
# RU: Если под Виндой, то перенаправить консольный вывод в файл из-за краша rubyw.exe
if os_family=='windows'
  $stdout.reopen(File.join($pandora_base_dir, 'stdout.log'), 'w')
  $stderr = $stdout
end

# ==Including modules
# ==RU: Подключение модулей

# XML requires for preference setting and exports
# RU: XML нужен для хранения настроек и выгрузок
require 'rexml/document'
require 'zlib'
require 'socket'
require 'digest'
require 'base64'
require 'net/http'
require 'net/https'

# The particular sqlite database interface
# RU: Отдельный модуль для подключения к базам sqlite
begin
  require 'sqlite3'
  $sqlite3_on = true
rescue Exception
  $sqlite3_on = false
end

# The particular mysql database interface
# RU: Отдельный модуль для подключения к базам mysql
begin
  require 'mysql'
  $mysql_on = true
rescue Exception
  $mysql_on = false
end

# NCurses is console output interface
# RU: Интерфейс для вывода псевдографики в текстовом режиме
begin
  require 'ncurses'
  $ncurses_on = true
rescue Exception
  $ncurses_on = false
end

# GTK is cross platform graphical user interface
# RU: Кроссплатформенный оконный интерфейс
begin
  require 'gtk2'
  $gtk2_on = true
  Gtk.init
rescue Exception
  $gtk2_on = false
end

# OpenSSL is a crypto library
# RU: Криптографическая библиотека
begin
  require 'openssl'
  $openssl_on = true
rescue Exception
  $openssl_on = false
end

# Default language when environment LANG variable is not defined
# RU: Язык по умолчанию, когда не задана переменная окружения LANG
$lang = 'ru'

# Define environment parameters
# RU: Определить переменные окружения
lang = ENV['LANG']
if (lang.is_a? String) and (lang.size>1)
  $lang = lang[0, 2].downcase
end
#$lang = 'en'

# GStreamer is a media library
# RU: Обвязка для медиа библиотеки GStreamer
begin
  require 'gst'
  $gst_on = true
rescue Exception
  $gst_on = false
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

LM_Error    = 0
LM_Warning  = 1
LM_Info     = 2
LM_Trace    = 3

def level_to_str(level)
  mes = ''
  case level
    when LM_Error
      mes = _('Error')
    when LM_Warning
      mes = _('Warning')
    when LM_Trace
      mes = _('Trace')
  end
  mes = '['+mes+'] ' if mes != ''
end

# Log message
# RU: Добавить сообщение в лог
def log_message(level, mes)
  mes = level_to_str(level).to_s+mes
  if $window.log_view
    $window.log_view.buffer.insert($window.log_view.buffer.end_iter, mes+"\n")
    #log_view.move_viewport(Gtk::SCROLL_ENDS, 1)
    $window.log_view.parent.vadjustment.value = $window.log_view.parent.vadjustment.upper
  else
    puts mes
  end
end

# ==============================================================================
# == Base module of Pandora
# == RU: Базовый модуль Пандора
module PandoraUtils

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

    def self.spaces_after(line, pos)
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
                end_is_found = ((k+1)==line.size) or spaces_after(line, k+1)
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

    def self.slash_quotes(str)
      str.gsub('"', '\"')
    end

    def self.there_are_end_space(str)
      lastchar = str[str.size-1, 1]
      (lastchar==' ') or (lastchar=="\t")
    end

    langfile = File.join($pandora_lang_dir, lang+'.txt')
    File.open(langfile, 'w') do |file|
      file.puts('# Pandora language file EN=>'+lang.upcase)
      $lang_trans.each do |value|
        if (not value[0].index('"')) and (not value[1].index('"')) \
          and (not value[0].index("\n")) and (not value[1].index("\n")) \
          and (not there_are_end_space(value[0])) and (not there_are_end_space(value[1]))
        then
          str = value[0]+'=>'+value[1]
        else
          str = '"'+slash_quotes(value[0])+'"=>"'+slash_quotes(value[1])+'"'
        end
        file.puts(str)
      end
    end
  end

  # Type translation Ruby->SQLite
  # RU: Трансляция типа Ruby->SQLite
  def self.ruby_type_to_sqlite_type(rt, size)
    rt_str = rt.to_s
    size_i = size.to_i
    case rt_str
      when 'Integer', 'Word', 'Byte', 'Coord'
        'INTEGER'
      when 'Float'
        'REAL'
      when 'Number', 'Panhash'
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

  def self.ruby_val_to_sqlite_val(v)
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
  def self.panobj_fld_to_sqlite_tab(panobj_flds)
    res = ''
    panobj_flds.each do |fld|
      res = res + ', ' if res != ''
      res = res + fld[FI_Id].to_s + ' ' + PandoraUtils::ruby_type_to_sqlite_type(fld[FI_Type], fld[FI_Size])
    end
    res = '(id INTEGER PRIMARY KEY AUTOINCREMENT, ' + res + ')' if res != ''
    res
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
    def select_table(table_name, afilter=nil, fields=nil, sort=nil, limit=nil)
    end
  end

  TI_Name  = 0
  TI_Type  = 1
  TI_Desc  = 2

  # SQLite adapter
  # RU: Адаптер SQLite
  class SQLiteDbSession < DatabaseSession
    NAME = "Сеанс SQLite"
    attr_accessor :db, :exist
    def connect
      if not @connected
        @db = SQLite3::Database.new(conn_param)
        @connected = true
        @exist = {}
      end
      @connected
    end
    def create_table(table_name, recreate=false)
      connect
      tfd = db.table_info(table_name)
      #p tfd
      tfd.collect! { |x| x['name'] }
      if (not tfd) or (tfd == [])
        @exist[table_name] = FALSE
      else
        @exist[table_name] = TRUE
      end
      tab_def = PandoraUtils::panobj_fld_to_sqlite_tab(def_flds[table_name])
      #p tab_def
      if (! exist[table_name] or recreate) and tab_def
        if exist[table_name] and recreate
          res = db.execute('DROP TABLE '+table_name)
        end
        p 'CREATE TABLE '+table_name+' '+tab_def
        res = db.execute('CREATE TABLE '+table_name+' '+tab_def)
        @exist[table_name] = TRUE
      end
      exist[table_name]
    end
    def fields_table(table_name)
      connect
      tfd = db.table_info(table_name)
      tfd.collect { |x| [x['name'], x['type']] }
    end
    def escape_like_mask(mask)
      #SELECT * FROM mytable WHERE myblob LIKE X'0025';
      #SELECT * FROM mytable WHERE quote(myblob) LIKE 'X''00%';     end
      #Is it possible to pre-process your 10 bytes and insert e.g. symbol '\'
      #before any '\', '_' and '%' symbol? After that you can query
      #SELECT * FROM mytable WHERE myblob LIKE ? ESCAPE '\'
      #SELECT * FROM mytable WHERE substr(myblob, 1, 1) = X'00';
      #SELECT * FROM mytable WHERE substr(myblob, 1, 10) = ?;
      if mask.is_a? String
        mask.gsub!('$', '$$')
        mask.gsub!('_', '$_')
        mask.gsub!('%', '$%')
        #query = AsciiString.new(query)
        #i = query.size
        #while i>0
        #  if ['$', '_', '%'].include? query[i]
        #    query = query[0,i+1]+'$'+query[i+1..-1]
        #  end
        #  i -= 1
        #end
      end
      mask
    end
    def select_table(table_name, filter=nil, fields=nil, sort=nil, limit=nil, like_filter=nil)
      res = nil
      connect
      tfd = fields_table(table_name)
      #p '[tfd, table_name, filter, fields, sort, limit, like_filter]='+[tfd, table_name, filter, fields, sort, limit, like_filter].inspect
      if tfd and (tfd != [])
        sql_values = Array.new
        if filter.is_a? Hash
          sql2 = ''
          filter.each do |n,v|
            if n
              sql2 = sql2 + ' AND ' if sql2 != ''
              sql2 = sql2 + n.to_s + '=?'
              sql_values << v
            end
          end
          filter = sql2
        end
        if like_filter.is_a? Hash
          sql2 = ''
          like_filter.each do |n,v|
            if n
              sql2 = sql2 + ' AND ' if sql2 != ''
              sql2 = sql2 + n.to_s + 'LIKE ?'
              sql_values << v
            end
          end
          like_filter = sql2
        end
        fields ||= '*'
        sql = 'SELECT '+fields+' FROM '+table_name
        filter = nil if (filter and (filter == ''))
        like_filter = nil if (like_filter and (like_filter == ''))
        if filter or like_filter
          sql = sql + ' WHERE'
          sql = sql + ' ' + filter if filter
          if like_filter
            sql = sql + ' AND' if filter
            sql = sql + ' ' + like_filter
          end
        end
        if sort and (sort > '')
          sql = sql + ' ORDER BY '+sort
        end
        if limit
          sql = sql + ' LIMIT '+limit.to_s
        end
        #p 'select  sql='+sql.inspect+'  values='+sql_values.inspect+' db='+db.inspect
        res = db.execute(sql, sql_values)
      end
      #p 'res='+res.inspect
      res
    end
    def update_table(table_name, values, names=nil, filter=nil)
      res = false
      connect
      sql = ''
      sql_values = Array.new
      sql_values2 = Array.new

      if filter.is_a? Hash
        sql2 = ''
        filter.each do |n,v|
          if n
            sql2 = sql2 + ' AND ' if sql2 != ''
            sql2 = sql2 + n.to_s + '=?'
            #v.force_encoding('ASCII-8BIT')  and v.is_a? String
            #v = AsciiString.new(v) if v.is_a? String
            sql_values2 << v
          end
        end
        filter = sql2
      end

      if (not values) and (not names) and filter
        sql = 'DELETE FROM ' + table_name + ' where '+filter
      elsif values.is_a? Array and names.is_a? Array
        tfd = db.table_info(table_name)
        tfd_name = tfd.collect { |x| x['name'] }
        tfd_type = tfd.collect { |x| x['type'] }
        if filter
          values.each_with_index do |v,i|
            fname = names[i]
            if fname
              sql = sql + ',' if sql != ''
              #v.is_a? String
              #v.force_encoding('ASCII-8BIT')  and v.is_a? String
              #v = AsciiString.new(v) if v.is_a? String
              v = PandoraUtils.ruby_val_to_sqlite_val(v)
              sql_values << v
              sql = sql + fname.to_s + '=?'
            end
          end

          sql = 'UPDATE ' + table_name + ' SET ' + sql
          if filter and filter != ''
            sql = sql + ' where '+filter
          end
        else
          sql2 = ''
          values.each_with_index do |v,i|
            fname = names[i]
            if fname
              sql = sql + ',' if sql != ''
              sql2 = sql2 + ',' if sql2 != ''
              sql = sql + fname.to_s
              sql2 = sql2 + '?'
              #v.force_encoding('ASCII-8BIT')  and v.is_a? String
              #v = AsciiString.new(v) if v.is_a? String
              v = PandoraUtils.ruby_val_to_sqlite_val(v)
              sql_values << v
            end
          end
          sql = 'INSERT INTO ' + table_name + '(' + sql + ') VALUES(' + sql2 + ')'
        end
      end
      tfd = fields_table(table_name)
      if tfd and (tfd != [])
        sql_values = sql_values+sql_values2
        p '1upd_tab: sql='+sql.inspect
        p '2upd_tab: sql_values='+sql_values.inspect
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
    attr_accessor :base_list
    def initialize
      super
      @base_list = # динамический список баз
        [['robux', 'sqlite3,', $pandora_sqlite_db, nil],
         ['robux', 'sqlite3,', $pandora_sqlite_db2, nil],
         ['robux', 'sqlite3,', $pandora_sqlite_db3, nil],
         ['robux', 'mysql', ['robux.biz', 'user', 'pass', 'oscomm'], nil]]
    end
    def get_adapter(panobj, table_ptr, recreate=false)
      adap = nil
      base_des = base_list[$base_index]
      if not base_des[3]
        adap = SQLiteDbSession.new
        adap.conn_param = base_des[2]
        base_des[3] = adap
      else
        adap = base_des[3]
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
    def get_tab_select(panobj, table_ptr, filter=nil, fields=nil, sort=nil, limit=nil)
      adap = get_adapter(panobj, table_ptr)
      adap.select_table(table_ptr[1], filter, fields, sort, limit)
    end
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
    def get_tab_fields(panobj, table_ptr)
      adap = get_adapter(panobj, table_ptr)
      adap.fields_table(table_ptr[1])
    end
  end

  # Global poiter to repository manager
  # RU: Глобальный указатель на менеджер хранилищ
  $repositories = RepositoryManager.new

  # Plural or single name
  # RU: Имя во множественном или единственном числе
  def self.get_name_or_names(name, plural=false)
    sname, pname = name.split('|')
    if plural==false
      res = sname
    elsif (not pname) or (pname=='')
      res = sname
      res[-1]='ie' if res[-1,1]=='y'
      res = res+'s'
    else
      res = pname
    end
    res
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
    if bigint<=0xFF
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
  # RU: Преобрзует строку байт в большое целое
  def self.bytes_to_bigint(bytes)
    res = nil
    if bytes
      hexstr = bytes_to_hex(bytes)
      res = OpenSSL::BN.new(hexstr, 16)
    end
    res
  end

  def self.bytes_to_int(bytes)
    res = 0
    i = bytes.size
    bytes.each_byte do |b|
      i -= 1
      res += (b << 8*i)
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

  $max_hash_len = 20

  def self.kind_from_panhash(panhash)
    kind = panhash[0].ord
  end

  def self.lang_from_panhash(panhash)
    lang = panhash[1].ord
  end

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
        @panhash_ind = nil
        @modified_ind = nil
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
      def panhash_ind
        @panhash_ind
      end
      def modified_ind
        @modified_ind
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
      def set_if_nil(f, fi, pfd)
        f[fi] ||= pfd[fi]
      end
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
              len = 16
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
              len = 18
            when 'Blog'
              if not fd[FI_Size] or fd[FI_Size].to_i>25
                view = 'base64'
              else
                view = 'hex'
              end
              #len = 24
            when 'Text'
              view = 'text'
              #len = 32
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
      def tab_fields(reinit=false)
        if (not @last_tab_fields) or reinit
          @last_tab_fields = repositories.get_tab_fields(self, tables[0])
          @last_tab_fields.each do |x|
            x[TI_Desc] = field_des(x[TI_Name])
          end
        end
        @last_tab_fields
      end
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
    def select(afilter=nil, set_namesvalues=false, fields=nil, sort=nil, limit=nil)
      res = self.class.repositories.get_tab_select(self, self.class.tables[0], afilter, fields, sort, limit)
      if set_namesvalues and res[0].is_a? Array
        @namesvalues = {}
        tab_fields.each_with_index do |td, i|
          namesvalues[td[TI_Name]] = res[0][i]
        end
      end
      res
    end
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
    def lang_to_str(lang)
      case lang
        when 0
          _('any')
        when 1
          _('eng')
        when 5
          _('rus')
        else
          _('lang')
      end
    end
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
            if fval==0x7ffe4d8e
              fval = 0
            else
              fval = fval.to_i
              coord = PandoraUtils.int_to_coord(fval)
              coord[0] = PandoraUtils.simplefy_coord(coord[0])
              coord[1] = PandoraUtils.simplefy_coord(coord[1])
              fval = PandoraUtils.coord_to_int(*coord)
              fval = 1 if fval==0
            end
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
    def matter_fields
      res = {}
      if namesvalues.is_a? Hash
        panhash_pattern.each do |pat|
          fname = pat[0]
          if fname
            fval = namesvalues[fname]
            res[fname] = fval
          end
        end
      end
      res
    end
    def clear_excess_fields(row)
      #row.delete_at(0)
      #row.delete_at(self.class.panhash_ind) if self.class.panhash_ind
      #row.delete_at(self.class.modified_ind) if self.class.modified_ind
      #row
      res = {}
      if namesvalues.is_a? Hash
        namesvalues.each do |k, v|
          if not (['id', 'panhash', 'modified'].include? k)
            res[k] = v
          end
        end
      end
      res
    end
  end

  def self.create_base_id
    res = PandoraUtils.fill_zeros_from_left(PandoraUtils.bigint_to_bytes(Time.now.to_i), 4)[0,4]
    res << OpenSSL::Random.random_bytes(12)
    res
  end

  PT_Int   = 0
  PT_Str   = 1
  PT_Bool  = 2
  PT_Time  = 3
  PT_Array = 4
  PT_Hash  = 5
  PT_Sym   = 6
  PT_Real  = 7
  PT_Unknown = 15
  PT_Negative = 16

  def self.string_to_pantype(type)
    res = PT_Unknown
    case type
      when 'Integer', 'Word', 'Byte', 'Coord'
        res = PT_Int
      when 'String', 'Text', 'Blob'
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

  def self.any_value_to_boolean(val)
    val = (((val.is_a? String) and (val.downcase != 'false') and (val != '0')) \
      or ((val.is_a? Numeric) and (val != 0)))
    val
  end

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

  def self.create_default_param(type, setting)
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

  def self.get_param(name, get_id=false)
    value = nil
    id = nil
    param_model = PandoraUtils.get_model('Parameter')
    sel = param_model.select({'name'=>name}, false, 'value, id, type')
    if not sel[0]
      # parameter was not found
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
          :value=>create_default_param(type, row[PF_Setting]), :type=>type,
          :section=>section, :setting=>row[PF_Setting], :modified=>Time.now.to_i }
        panhash = param_model.panhash(values)
        values['panhash'] = panhash
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
      vals = time_now.to_a
      y, m, d = [vals[5], vals[4], vals[3]]  #current day
      midnight = Time.local(y, m, d)

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
            val = val.strftime('%d.%m.%Y %R')
          else
            val = time_to_str(val)
          end
          color = '#338833'
        end
      elsif view=='base64'
        val = val.to_s
        if (not type) or (type=='text')
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
      elsif not can_edit and (view=='text')
        val = val[0,50].gsub(/[\r\n\t]/, ' ').squeeze(' ')
        val = val.rstrip
        color = '#226633'
      end
    end
    val ||= ''
    val = val.to_s
    [val, color]
  end

  def self.view_to_val(val, type, view)
    #p '---val1='+val.inspect
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
          if (not type) or (type=='Text')
            val = Base64.decode64(val)
          else
            val = Base64.strict_decode64(val)
          end
          color = 'brown'
        when 'hex', 'panhash', 'phash'
          #p 'type='+type.inspect
          if (['Bigint', 'Panhash', 'String', 'Blob', 'Text'].include? type) or (type[0,7]=='Panhash')
            #val = AsciiString.new(PandoraUtils.bigint_to_bytes(val))
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
          p '[d, m, s]='+[d, m, s].inspect
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
    res
  end

  def self.int_to_coord(int)
    h = (int.fdiv(MultX)).truncate + 1
    s = int - (h-1)*MultX
    x = s.fdiv(MultX)*DegX - 180.0
    y = h.fdiv(MultY)*DegY - 90.0
    x = x.round(2)
    x = 180.0 if (x==(-180.0))
    y = y.round(2)
    [y, x]
  end

  def self.simplefy_coord(val)
    val = val.round(1)
  end

  class RoundQueue < Mutex
    # Init empty queue. Poly read is possible
    # RU: Создание пустой очереди. Возможно множественное чтение
    attr_accessor :mutex, :queue, :write_ind, :read_ind

    def initialize(poly_read=false)   #init_empty_queue
      super()
      @queue = Array.new
      @write_ind = -1
      if poly_read
        @read_ind = Array.new  # will be array of read pointers
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

    QS_Empty     = 0
    QS_NotEmpty  = 1
    QS_Full      = 2

    def single_read_state(max=MaxQueue)
      res = QS_NotEmpty
      if read_ind.is_a? Integer
        if (read_ind == write_ind)
          res = QS_Empty
        else
          wind = write_ind
          if wind<max
            wind += 1
          else
            wind = 0
          end
          res = QS_Full if (read_ind == wind)
        end
      end
      res
    end

    # Get block from queue (set "ptrind" like 0,1,2..)
    # RU: Взять блок из очереди (задавай "ptrind" как 0,1,2..)
    def get_block_from_queue(max=MaxQueue, ptrind=nil)
      block = nil
      pointers = nil
      synchronize do
        ind = read_ind
        if ptrind
          pointers = ind
          ind = pointers[ptrind]
          ind ||= -1
        end
        #p 'get_block_from_queue:  [ptrind, ind, write_ind]='+[ptrind, ind, write_ind].inspect
        if ind != write_ind
          if ind<max
            ind += 1
          else
            ind = 0
          end
          block = queue[ind]
          if ptrind
            pointers[ptrind] = ind
          else
            @read_ind = ind
          end
        end
      end
      block
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
    if elem_size
      res << PandoraUtils.fill_zeros_from_left(PandoraUtils.bigint_to_bytes(elem_size), count+1) + data
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
      #p 'basetype, vlen='+[basetype, vlen].inspect
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
        #p '[val,len]='+[val,len].inspect
      else
        len = data.bytesize
      end
    end
    [val, len]
  end

  def self.value_is_empty(val)
    res = (val==nil) or (val.is_a? String and (val=='')) or (val.is_a? Integer and (val==0)) \
      or (val.is_a? Array and (val==[])) or (val.is_a? Hash and (val=={})) \
      or (val.is_a? Time and (val.to_i==0))
    res
  end

  # Pack PanObject fields to PSON binary format
  # RU: Пакует поля ПанОбъекта в бинарный формат PSON
  def self.namehash_to_pson(fldvalues, pack_empty=false)
    #bytes = ''
    #bytes.force_encoding('ASCII-8BIT')
    bytes = AsciiString.new
    fldvalues = fldvalues.sort_by {|k,v| k.to_s } # sort by key
    fldvalues.each { |nam, val|
      if pack_empty or (not value_is_empty(val))
        nam = nam.to_s
        nsize = nam.bytesize
        nsize = 255 if nsize>255
        bytes << [nsize].pack('C') + nam[0, nsize]
        pson_elem = rubyobj_to_pson_elem(val)
        #pson_elem.force_encoding('ASCII-8BIT')
        bytes << pson_elem
      end
    }
    bytes = AsciiString.new(bytes)
  end

  def self.pson_to_namehash(pson)
    hash = {}
    while pson and (pson.bytesize>1)
      flen = pson[0].ord
      fname = pson[1, flen]
      #p '[flen, fname]='+[flen, fname].inspect
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

  CapSymbols = '123456789qertyupasdfghkzxvbnmQRTYUPADFGHJKLBNM'
  CapFonts = ['Sans', 'Arial', 'Times', 'Verdana', 'Tahoma']

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
    if not drawing
      drawing = Gdk::Pixmap.new(nil, width, height, 24)
    end

    cr = drawing.create_cairo_context
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

    pixbuf = Gdk::Pixbuf.from_drawable(nil, drawing, 0, 0, width, height)
    buf = pixbuf.save_to_buffer('jpeg')
    [text, buf]
  end

end

# ==============================================================================
# == Pandora logic model
# == RU: Логическая модель Пандоры
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
              panobj_tabl = PandoraUtils::get_name_or_names(panobj_tabl, true)
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
                #p 'Функция не определена: ['+sub_elem.name+']'
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

  def self.panobjectclass_by_kind(kind)
    res = nil
    if kind>0
      $panobject_list.each do |panobject_class|
        if panobject_class.kind==kind
          res = panobject_class
          break
        end
      end
    end
    res
  end

  def self.normalize_trust(trust, to_int=nil)
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

  PK_Key    = 221

  def self.get_record_by_panhash(kind, panhash, pson_with_kind=nil, models=nil, getfields=nil)
    res = nil
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    model = PandoraUtils.get_model(panobjectclass.ider, models)
    filter = {'panhash'=>panhash}
    if kind==PK_Key
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
        res << PandoraUtils.namehash_to_pson(fields)
      else
        res = sel
      end
    end
    res
  end

  def self.save_record(kind, lang, values, models=nil, require_panhash=nil)
    res = false
    p '=======save_record  [kind, lang, values]='+[kind, lang, values].inspect
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    model = PandoraUtils.get_model(panobjectclass.ider, models)
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
      end
    else
      res = nil
    end
    res
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
  RK_MinPublic = 235
  RK_MaxPublic = 255

  # Relation is symmetric
  # RU: Связь симметрична
  def self.relation_is_symmetric(relation)
    res = [RK_Equal, RK_Similar, RK_Unknown].include? relation
  end

  # Check, create or delete relation between two panobjects
  # RU: Проверяет, создаёт или удаляет связь между двумя объектами
  def self.act_relation(panhash1, panhash2, rel_kind=RK_Unknown, act=:check, creator=true, \
  init=false, models=nil)
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
          filter = {:first => panhash1, :second => panhash2, :kind => rel_kind}
          filter2 = nil
          if relation_is_symmetric(rel_kind) and (panhash1 != panhash2)
            filter2 = {:first => panhash2, :second => panhash1, :kind => rel_kind}
          end
          #p 'relat2 [p1,p2,t]='+[PandoraUtils.bytes_to_hex(panhash1), PandoraUtils.bytes_to_hex(panhash2), rel_kind].inspect
          #p 'act='+act.inspect
          if (act != :delete)  #check or create
            #p 'check or create'
            sel = relation_model.select(filter, false, 'id')
            exist = (sel and (sel.size>0))
            if not exist and filter2
              sel = relation_model.select(filter2, false, 'id')
              exist = (sel and (sel.size>0))
            end
            res = exist
            if not exist and (act == :create)
              #p 'UPD!!!'
              if filter2 and (panhash1>panhash2) #when symmetric relation less panhash must be at left
                filter = filter2
              end
              panhash = relation_model.panhash(filter, 0)
              filter['panhash'] = panhash
              filter['modified'] = Time.now.to_i
              res = relation_model.update(filter, nil, nil)
            end
          else #delete
            #p 'delete'
            res = relation_model.update(nil, nil, filter)
            if filter2
              res2 = relation_model.update(nil, nil, filter2)
              res = res or res2
            end
          end
        end
      end
    end
    res
  end

  # Panobject state flages
  # RU: Флаги состояния объекта
  PSF_Support   = 1      # поддерживаю
  PSF_Hurvest   = 2      # запись собирается/загружается по частям

end

#===================================================================================
module PandoraCrypto

  KH_None   = 0
  KH_Md5    = 0x1
  KH_Sha1   = 0x2
  KH_Sha2   = 0x3
  KH_Sha3   = 0x4

  KT_None = 0
  KT_Rsa  = 0x1
  KT_Dsa  = 0x2
  KT_Aes  = 0x6
  KT_Des  = 0x7
  KT_Bf   = 0x8
  KT_Priv = 0xF

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

  def self.klen_to_bitlen(len)
    res = nil
    ind = len >> 4
    res = KL_BitLens[ind-1] if ind and (ind>0) and (ind<=KL_BitLens.size)
    res
  end

  def self.bitlen_to_klen(len)
    res = KL_None
    ind = KL_BitLens.index(len)
    res = KL_BitLens[ind] << 4 if ind
    res
  end

  def self.divide_type_and_klen(tnl)
    type = tnl & 0x0F
    klen  = tnl & 0xF0
    [type, klen]
  end

  def self.encode_cipher_and_hash(cipher, hash)
    res = cipher & 0xFF | ((hash & 0xFF) << 8)
  end

  def self.decode_cipher_and_hash(cnh)
    cipher = cnh & 0xFF
    hash  = (cnh >> 8) & 0xFF
    [cipher, hash]
  end

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

  def self.pankt_len_to_full_openssl(type, len)
    res = pankt_to_openssl(type)
    res += '-'+len.to_s if len
    res += '-CBC'
  end

  RSA_exponent = 65537

  KV_Obj   = 0
  KV_Key1  = 1
  KV_Key2  = 2
  KV_Kind  = 3
  KV_Cipher  = 4
  KV_Pass  = 5
  KV_Panhash = 6
  KV_Creator = 7
  KV_Trust   = 8
  KV_NameFamily  = 9

  def self.sym_recrypt(data, encode=true, cipher_hash=nil, cipher_key=nil)
    #p '^^^^^^^^^^^^sym_recrypt: [cipher_hash, cipher_key]='+[cipher_hash, cipher_key].inspect
    #cipher_hash ||= encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
    if cipher_hash and (cipher_hash != 0) and data
      ckind, chash = decode_cipher_and_hash(cipher_hash)
      hash = pan_kh_to_openssl_hash(chash)
      #p 'hash='+hash.inspect
      cipher_key ||= ''
      cipher_key = hash.digest(cipher_key) if hash
      #p 'cipher_key.hash='+cipher_key.inspect
      cipher_vec = Array.new
      cipher_vec[KV_Key1] = cipher_key
      cipher_vec[KV_Kind] = ckind
      cipher_vec = init_key(cipher_vec)
      #p '*******'+encode.inspect
      #p '---sym_recode data='+data.inspect
      data = recrypt(cipher_vec, data, encode)
      #p '+++sym_recode data='+data.inspect
    end
    data = AsciiString.new(data) if data
    data
  end

  # Generate a key or key pair
  # RU: Генерирует ключ или ключевую пару
  def self.generate_key(type_klen = KT_Rsa | KL_bit2048, cipher_hash=nil, cipher_key=nil)
    key = nil
    key1 = nil
    key2 = nil

    type, klen = divide_type_and_klen(type_klen)
    bitlen = klen_to_bitlen(klen)

    case type
      when KT_Rsa
        bitlen ||= 2048
        bitlen = 2048 if bitlen <= 0
        key = OpenSSL::PKey::RSA.generate(bitlen, RSA_exponent)

        #key1 = ''
        #key1.force_encoding('ASCII-8BIT')
        #key2 = ''
        #key2.force_encoding('ASCII-8BIT')
        key1 = AsciiString.new(PandoraUtils.bigint_to_bytes(key.params['n']))
        key2 = AsciiString.new(PandoraUtils.bigint_to_bytes(key.params['p']))
        #p key1 = key.params['n']
        #key2 = key.params['p']
        #p PandoraUtils.bytes_to_bigin(key1)
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
        key.encrypt
        key1 = key.random_key
        key2 = key.random_iv
        #p key1.size
        #p key2.size
    end
    key2 = sym_recrypt(key2, true, cipher_hash, cipher_key)
    [key, key1, key2, type_klen, cipher_hash, cipher_key]
  end

  # Init key or key pare
  # RU: Инициализирует ключ или ключевую пару
  def self.init_key(key_vec)
    key = key_vec[KV_Obj]
    if not key
      key1 = key_vec[KV_Key1]
      key2 = key_vec[KV_Key2]
      type_klen = key_vec[KV_Kind]
      cipher = key_vec[KV_Cipher]
      pass = key_vec[KV_Pass]
      type, klen = divide_type_and_klen(type_klen)
      bitlen = klen_to_bitlen(klen)
      case type
        when KT_Rsa
          #p '------'
          #p key.params
          n = PandoraUtils.bytes_to_bigint(key1)
          #p 'n='+n.inspect
          e = OpenSSL::BN.new(RSA_exponent.to_s)
          p0 = nil
          if key2
            #p '[cipher, key2]='+[cipher, key2].inspect
            key2 = sym_recrypt(key2, false, cipher, pass)
            #p 'key2='+key2.inspect
            p0 = PandoraUtils.bytes_to_bigint(key2) if key2
          else
            p0 = 0
          end

          if p0
            pass = 0
            #p 'n='+n.inspect+'  p='+p0.inspect+'  e='+e.inspect
            if key2
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
          key.key = key1
      end
      key_vec[KV_Obj] = key
    end
    key_vec
  end

  # Create sign
  # RU: Создает подпись
  def self.make_sign(key, data, hash_len=KH_Sha2 | KL_bit256)
    sign = nil
    sign = key[KV_Obj].sign(pan_kh_to_openssl_hash(hash_len), data) if key[KV_Obj]
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

  # Encrypt data
  # RU: Шифрует данные
  def self.recrypt(key_vec, data, encrypt=true, private=false)
    recrypted = nil
    key = key_vec[KV_Obj]
    #p 'encrypt key='+key.inspect
    if key.is_a? OpenSSL::Cipher
      iv = nil
      if encrypt
        key.encrypt
        key.key = key_vec[KV_Key1]
        iv = key.random_iv
      else
        data = AsciiString.new(data)
        #data.force_encoding('ASCII-8BIT')
        #p 'before decrypt: data='+data.inspect
        data, len = PandoraUtils.pson_elem_to_rubyobj(data)   # pson to array
        #p 'decrypt: data='+data.inspect
        key.decrypt
        #p 'DDDDDDEEEEECR'
        if data.is_a? Array
          iv = AsciiString.new(data[1])
          data = AsciiString.new(data[0])  # data from array
        else
          data = nil
        end
        key.key = key_vec[KV_Key1]
        key.iv = iv if iv
      end

      begin
        #p 'BEFORE key='+key.key.inspect
        if data
          recrypted = key.update(data) + key.final
        end
      rescue
        recrypted = nil
      end

      #p '[recrypted, iv]='+[recrypted, iv].inspect
      if encrypt and recrypted
        recrypted = PandoraUtils.rubyobj_to_pson_elem([recrypted, iv])
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

  def self.fill_by_zeros(str)
    if str.is_a? String
      (str.size).times do |i|
        str[i] = 0.chr
      end
    end
  end

  # Deactivate current or target key
  # RU: Деактивирует текущий или указанный ключ
  def self.deactivate_key(key_vec)
    if key_vec.is_a? Array
      fill_by_zeros(key_vec[PandoraCrypto::KV_Key2])  #private key
      fill_by_zeros(key_vec[PandoraCrypto::KV_Pass])
      key_vec.each_index do |i|
        key_vec[i] = nil
      end
    end
    key_vec = nil
  end

  class << self
    attr_accessor :the_current_key
  end

  def self.reset_current_key
    self.the_current_key = deactivate_key(self.the_current_key)
    $window.set_status_field(PandoraGUI::SF_Auth, 'Not logged', nil, false)
    self.the_current_key
  end

  KR_Exchange  = 1
  KR_Sign      = 2

  $first_key_init = true

  def self.current_key(switch_key=false, need_init=true)
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
          key_vec[KV_Key1] = pub
          key_vec[KV_Key2] = priv
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

    def self.recrypt_key(key_model, key_vec, cipher, panhash, passwd, newpasswd)
      if not key_vec
        key_vec, cipher = read_key(panhash, passwd, key_model)
      end
      if key_vec
        key2 = key_vec[KV_Key2]
        cipher = key_vec[KV_Cipher]
        #type_klen = key_vec[KV_Kind]
        #type, klen = divide_type_and_klen(type_klen)
        #bitlen = klen_to_bitlen(klen)
        if key2
          key2 = sym_recrypt(key2, false, cipher, passwd)
          if key2
            cipher_key = newpasswd
            cipher_hash = 0
            if cipher_key and (cipher_key.size>0)
              cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
            end
            key2 = sym_recrypt(key2, true, cipher_hash, cipher_key)
            if key2
              time_now = Time.now.to_i
              filter = {:panhash=>panhash, :kind=>KT_Priv}
              panstate = PandoraModel::PSF_Support
              values = {:panstate=>panstate, :cipher=>cipher_hash, :body=>key2, :modified=>time_now}
              res = key_model.update(values, nil, filter)
              if res
                key_vec[KV_Key2] = key2
                key_vec[KV_Cipher] = cipher_hash
                passwd = newpasswd
              end
            end
          end
        end
      end
      [key_vec, cipher, passwd]
    end

    key_vec = self.the_current_key
    if key_vec and switch_key
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
            dialog = PandoraGUI::AdvancedDialog.new(_('Key init'))
            dialog.set_default_size(420, 190)

            vbox = Gtk::VBox.new
            dialog.viewport.add(vbox)

            label = Gtk::Label.new(_('Key'))
            vbox.pack_start(label, false, false, 2)
            key_entry = PandoraGUI::PanhashBox.new('Panhash(Key)')
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

            changebtn = PandoraGUI::GoodToggleToolButton.new(Gtk::Stock::EDIT)
            changebtn.tooltip_text = _('Change password')
            changebtn.good_signal_clicked do |*args|
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
            dialog.run do
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
          dialog = PandoraGUI::AdvancedDialog.new(_('Key generation'))
          dialog.set_default_size(420, 250)

          vbox = Gtk::VBox.new
          dialog.viewport.add(vbox)

          #creator = PandoraUtils.bigint_to_bytes(0x01052ec783d34331de1d39006fc80000000000000000)
          label = Gtk::Label.new(_('Your panhash'))
          vbox.pack_start(label, false, false, 2)
          user_entry = PandoraGUI::PanhashBox.new('Panhash(Person)')
          #user_entry.text = PandoraUtils.bytes_to_hex(creator)
          vbox.pack_start(user_entry, false, false, 2)

          rights = KR_Exchange | KR_Sign
          label = Gtk::Label.new(_('Rights'))
          vbox.pack_start(label, false, false, 2)
          rights_entry = Gtk::Entry.new
          rights_entry.text = rights.to_s
          vbox.pack_start(rights_entry, false, false, 2)

          label = Gtk::Label.new(_('Password'))
          vbox.pack_start(label, false, false, 2)
          pass_entry = Gtk::Entry.new
          pass_entry.width_request = 250
          align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
          align.add(pass_entry)
          vbox.pack_start(align, false, false, 2)
          vbox.pack_start(pass_entry, false, false, 2)

          dialog.def_widget = user_entry.entry

          dialog.run do
            creator = PandoraUtils.hex_to_bytes(user_entry.text)
            if creator.size==22
              #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
              cipher_key = pass_entry.text
              cipher_hash = 0
              if cipher_key and (cipher_key.size>0)
                cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
              end
              rights = rights_entry.text.to_i

              #p 'cipher_hash='+cipher_hash.to_s
              type_klen = KT_Rsa | KL_bit2048

              key_vec = generate_key(type_klen, cipher_hash, cipher_key)

              #p 'key_vec='+key_vec.inspect

              pub  = key_vec[KV_Key1]
              priv = key_vec[KV_Key2]
              type_klen = key_vec[KV_Kind]
              cipher_hash = key_vec[KV_Cipher]
              cipher_key = key_vec[KV_Pass]

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
                PandoraGUI.show_panobject_list(PandoraModel::Person, nil, nil, true)
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
            $window.set_status_field(PandoraGUI::SF_Auth, text, nil, true)
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

  PT_Pson1   = 1

  # Sign PSON of PanObject and save sign record
  # RU: Подписывает PSON ПанОбъекта и сохраняет запись подписи
  def self.sign_panobject(panobject, trust=0, models=nil)
    res = false
    key = current_key
    if key and key[KV_Obj] and key[KV_Creator]
      namesvalues = panobject.namesvalues
      matter_fields = panobject.matter_fields
      #p 'sign: matter_fields='+matter_fields.inspect
      sign = make_sign(key, PandoraUtils.namehash_to_pson(matter_fields))

      time_now = Time.now.to_i
      obj_hash = namesvalues['panhash']
      key_hash = key[KV_Panhash]
      creator = key[KV_Creator]

      trust = PandoraModel.normalize_trust(trust, true)

      values = {:modified=>time_now, :obj_hash=>obj_hash, :key_hash=>key_hash, :pack=>PT_Pson1, \
        :trust=>trust, :creator=>creator, :created=>time_now, :sign=>sign}

      sign_model = PandoraUtils.get_model('Sign', models)
      panhash = sign_model.panhash(values)
      #p '!!!!!!panhash='+PandoraUtils.bytes_to_hex(panhash).inspect

      values['panhash'] = panhash

      res = sign_model.update(values, nil, nil)
    end
    res
  end

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

  def self.trust_of_panobject(panhash, models=nil)
    res = nil
    if panhash and (panhash != '')
      key_hash = current_user_or_key(false, false)
      sign_model = PandoraUtils.get_model('Sign', models)
      filter = {:obj_hash => panhash}
      filter[:key_hash] = key_hash if key_hash
      sel = sign_model.select(filter, false, 'created, trust')
      if sel and (sel.size>0)
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
              res = PandoraModel.normalize_trust(trust, false)
            end
          end
        else
          res = sel.size
        end
      end
    end
    res
  end

  $person_trusts = {}

  def self.trust_of_person(panhash, level=0)
    res = $person_trusts[panhash]
    if res
      res = 0.0
      trust_level = 0
      if not my_key_hash
        my_key_hash = current_user_or_key(false, false)
        p 'trust of person'
      end
    end
    res
  end

  $query_depth = 3

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
                rate += normalize_trust(last_trust, false) * person_trust
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

  def self.open_key(panhash, models, init=true)
    key_vec = nil
    if panhash.is_a? String
      key_vec = $open_keys[panhash]
      #p 'openkey key='+key_vec.inspect+' $open_keys.size='+$open_keys.size.inspect
      if key_vec
        key_vec[KV_Trust] = trust_of_panobject(panhash)
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
              key_vec[KV_Key1] = pub
              key_vec[KV_Kind] = kind
              #key_vec[KV_Pass] = passwd
              key_vec[KV_Panhash] = panhash
              key_vec[KV_Creator] = creator
              key_vec[KV_Trust] = trust_of_panobject(panhash)

              $open_keys[panhash] = key_vec
              break
            end
          end
        else  #key is not found
          key_vec = 0
        end
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

  def self.name_and_family_of_person(key, person=nil)
    nf = nil
    #p 'person, key='+[person, key].inspect
    nf = key[KV_NameFamily] if key
    aname, afamily = nil, nil
    if nf.is_a? Array
      #p 'nf='+nf.inspect
      aname, afamily = nf
    elsif (person or key)
      person ||= key[KV_Creator]
      kind = PandoraUtils.kind_from_panhash(person)
      sel = PandoraModel.get_record_by_panhash(kind, person, nil, nil, 'first_name, last_name')
      #p 'key, person, sel='+[key, person, sel].inspect
      if (sel.is_a? Array) and (sel.size>0)
        aname, afamily = Utf8String.new(sel[0][0]), Utf8String.new(sel[0][1])
      end
      #p '[aname, afamily]='+[aname, afamily].inspect
      if (not aname) and (not afamily) and (key.is_a? Array)
        aname = PandoraUtils.bytes_to_hex(key[KV_Creator])
        aname = aname[2, 10] if aname
        afamily = PandoraUtils.bytes_to_hex(key[KV_Panhash])
        afamily = afamily[2, 10] if afamily
      end
      if (not aname) and (not afamily) and person
        aname = PandoraUtils.bytes_to_hex(person)
        aname = aname[2, 12] if aname
      end
      key[KV_NameFamily] = [aname, afamily] if key
    end
    aname ||= ''
    afamily ||= ''
    #p 'name_and_family_of_person: '+[aname, afamily].inspect
    [aname, afamily]
  end

  def self.short_name_of_person(key, person=nil, kind=0, othername=nil)
    aname, afamily = name_and_family_of_person(key, person)
    #p [othername, aname, afamily]
    if kind==0
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


# ==============================================================================
# == Network classes of Pandora
# == RU: Сетевые классы Пандоры
module PandoraNet

  class Pool
    attr_accessor :window, :sessions

    def initialize(main_window)
      super()
      @window = main_window
      @sessions = Array.new
    end

    def add_session(conn)
      if not sessions.include?(conn)
        sessions << conn
        window.update_conn_status(conn, conn.get_type, 1)
      end
    end

    def del_session(conn)
      if sessions.delete(conn)
        window.update_conn_status(conn, conn.get_type, -1)
      end
    end

    def session_of_node(node)
      host, port, proto = decode_node(node)
      session = sessions.find do |e|
        ((e.host_ip == host) or (e.host_name == host)) and (e.port == port) and (e.proto == proto)
      end
      session
    end

    def session_of_keybase(keybase)
      session = sessions.find { |e| (e.node_panhash == keybase) }
      session
    end

    def session_of_key(key)
      session = sessions.find { |e| (e.skey[PandoraCrypto::KV_Panhash] == key) }
      session
    end

    def session_of_person(person)
      session = sessions.find { |e| (e.skey[PandoraCrypto::KV_Creator] == person) }
      session
    end

    def sessions_on_dialog(dialog)
      dlg_sessions = sessions.select { |e| (e.dialog == dialog) }
      dlg_sessions
    end

    # Find or create session with necessary node
    # RU: Находит или создает соединение с нужным узлом
    def init_session(node=nil, keybase=nil, send_state_add=nil, dialog=nil, node_id=nil)
      p 'init_session: '+[node, keybase, send_state_add, dialog, node_id].inspect
      res = nil
      send_state_add ||= 0
      session1 = nil
      session2 = nil
      session1 = session_of_keybase(keybase) if keybase
      session2 = session_of_node(node) if node and (not session1)
      if session1 or session2
        session = session1
        session ||= session2
        session.send_state = (session.send_state | send_state_add)
        session.dialog = nil if session.dialog and session.dialog.destroyed?
        session.dialog = dialog if dialog
        #if session.dialog and session.dialog.online_button
        #  session.dialog.online_button.active = (session.socket and (not session.socket.closed?))
        #end
        res = true
      elsif (node or keybase)
        p 'NEED connect: '+[node, keybase].inspect
        if node
          host, port, proto = decode_node(node)
          sel = [[host, port]]
        else
          node_model = PandoraUtils.get_model('Node')
          filter = {:panhash=>keybase}
          sel = node_model.select(filter, false, 'addr, tport, domain')
          #p 'found: '+sel.inspect
          sel.each do |row|
            row[0] = row[2] if (not row[0]) or (row[0]=='')
          end
          #p 'after rewrite: '+sel.inspect
        end
        if sel and sel.size>0
          #p 'try: '+sel.inspect
          sel.each do |row|
            host = row[0]
            port = row[1]
            proto = 'tcp'
            #p 'host/port/proto='+[host, port, proto].inspect
            if host
              port ||= 5577
              Thread.new do
                socket = nil
                session = nil
                server = host+':'+port.to_s
                begin
                  socket = TCPSocket.open(host, port)
                rescue
                  log_message(LM_Warning, _('Cannot connect to')+' '+server)
                  socket = nil
                end
                if socket
                  #begin
                    log_message(LM_Info, _('Connected to server')+' '+server)
                    session = Session.new
                    session.run(socket, host, socket.addr[2], port, proto, CM_Hunter, \
                      CS_Connected, Thread.current, node_id, dialog, keybase, send_state_add)
                    socket.close if not socket.closed?
                    log_message(LM_Info, _('Disconnected from server')+' '+server)
                  #rescue => err
                  #  log_message(LM_Warning, _('Cicle exchange')+' '+server+' except='+err.message)
                  #end
                end
              end
              res = true
            end
          end
        end
      end
      res
    end

    # Stop session with a node
    # RU: Останавливает соединение с заданным узлом
    def stop_session(node=nil, keybase=nil)  #, wait_disconnect=true)
      p 'stop_session1 keybase='+keybase.inspect
      session1 = nil
      session2 = nil
      session1 = session_of_keybase(keybase) if keybase
      session2 = session_of_node(node) if node and (not session1)
      if session1 or session2
        #p 'stop_session2 session1,session2='+[session1,session2].inspect
        session = session1
        session ||= session2
        if session and (session.conn_state != CS_Disconnected)
          #p 'stop_session3 session='+session.inspect
          session.conn_state = CS_StopRead
          #while wait_disconnect and session and (session.conn_state != CS_Disconnected)
          #  sleep 0.05
          #  #Thread.pass
          #  #Gtk.main_iteration
          #  session = session_of_node(node)
          #end
          #session = session_of_node(node)
        end
      end
      res = (session and (session.conn_state != CS_Disconnected)) #and wait_disconnect
    end

    # Form node marker
    # RU: Сформировать маркер узла
    def encode_node(host, port, proto)
      host ||= ''
      port ||= ''
      proto ||= ''
      node = host+'='+port.to_s+proto
    end

    # Unpack node marker
    # RU: Распаковать маркер узла
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

    def init_fish_for_fisher(fisher, in_lure, keyhash=nil, baseid=nil)
      fish = nil
      if (keyhash==nil) #or (keyhash==mykeyhash)   # my key
        thread = Thread.new do
          log_message(LM_Info, _('Create fish session for')+' '+in_lure.to_s)
          session = Session.new
          thread[:fish] = session
          session.run(fisher, nil, in_lure, nil, nil, 0, CS_Connected, \
            thread, nil, nil, nil, nil)
          log_message(LM_Info, _('Close fish session for')+' '+in_lure.to_s)
        end
        Thread.pass
        while thread.alive? and (not thread[:fish])
          sleep(0.01)
        end
        if thread.alive?
          fish = thread[:fish]
        end
      else  # alien key
        fish = @sessions.index { |session| session.skey[PandoraCrypto::KV_Panhash] == keyhash }
      end
      fish
    end
  end

  # Network exchange comands
  # RU: Команды сетевого обмена
  EC_Media     = 0     # Медиа данные
  EC_Init      = 1     # Инициализация диалога (версия протокола, сжатие, авторизация, шифрование)
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

  CommSize = 6
  CommExtSize = 10

  ECC_Init_Hello       = 0
  ECC_Init_Puzzle      = 1
  ECC_Init_Phrase      = 2
  ECC_Init_Sign        = 3
  ECC_Init_Captcha     = 4
  ECC_Init_Simple      = 5
  ECC_Init_Answer      = 6

  ECC_Query0_Kinds      = 0
  ECC_Query255_AllChanges =255

  ECC_News0_Kinds       = 0

  ECC_Channel0_Open     = 0
  ECC_Channel1_Opened   = 1
  ECC_Channel2_Close    = 2
  ECC_Channel3_Closed   = 3
  ECC_Channel4_Fail     = 4

  ECC_Sync1_NoRecord    = 1
  ECC_Sync2_Encode      = 2

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

  # Режимы чтения
  RM_Comm      = 0   # Базовая команда
  RM_CommExt   = 1   # Расширение команды для нескольких сегментов
  RM_SegLenN   = 2   # Длина второго (и следующих) сегмента в серии
  RM_SegmentS  = 3   # Чтение одиночного сегмента
  RM_Segment1  = 4   # Чтение первого сегмента среди нескольких
  RM_SegmentN  = 5   # Чтение второго (и следующих) сегмента в серии

  # Connection mode
  # RU: Режим соединения
  CM_Hunter       = 1

  # Connected state
  # RU: Состояние соединения
  CS_Connecting    = 0
  CS_Connected     = 1
  CS_Stoping       = 2
  CS_StopRead      = 3
  CS_Disconnected  = 4

  # Stage of exchange
  # RU: Стадия обмена
  ST_Begin        = 0
  ST_IpCheck      = 1
  ST_Protocol     = 3
  ST_Puzzle       = 4
  ST_KeyRequest   = 5
  ST_Sign         = 6
  ST_Captcha      = 7
  ST_Greeting     = 8
  ST_Exchange     = 9

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

  # Inquirer steps
  # RU: Шаги почемучки
  IS_CreatorCheck  = 0
  IS_NewsQuery     = 1
  IS_Finished      = 255

  $incoming_addr = nil
  $puzzle_bit_length = 0  #8..24  (recommended 14)
  $puzzle_sec_delay = 2   #0..255 (recommended 2)
  $captcha_length = 4     #4..8   (recommended 6)
  $captcha_attempts = 2
  $trust_for_captchaed = true
  $trust_for_listener = true

  $keep_alive = 1  #(on/off)
  $keep_idle  = 5  #(after, sec)
  $keep_intvl = 1  #(every, sec)
  $keep_cnt   = 4  #(count)


  class Session
    attr_accessor :host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state, :stage, :dialog, \
      :send_thread, :read_thread, :socket, :read_state, :send_state, :donor, :fisher_lure, :fish_lure, \
      :send_models, :recv_models, :sindex, :read_queue, :send_queue, :params, \
      :rcmd, :rcode, :rdata, :scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, :r_encode, \
      :media_send, :node_id, :node_panhash, :entered_captcha, :captcha_sw, :fishes, :fishers

    def set_keepalive(client)
      client.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, $keep_alive)
      if os_family != 'windows'
        client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPIDLE, $keep_idle)
        client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPINTVL, $keep_intvl)
        client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPCNT, $keep_cnt)
      end
    end

    def pool
      $window.pool
    end

    def get_type
      res = nil
      if donor
        res = 2
      else
        if ((conn_mode & CM_Hunter)>0)
          res = 0
        else
          res = 1
        end
      end
    end

    def unpack_comm(comm)
      index, cmd, code, segsign, crc8 = nil, nil, nil, nil, nil
      errcode = 0
      if comm.bytesize == CommSize
        index, cmd, code, segsign, crc8 = comm.unpack('CCCnC')
        crc8f = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
        if crc8 != crc8f
          errcode = 1
        end
      else
        errcode = 2
      end
      [index, cmd, code, segsign, errcode]
    end

    def unpack_comm_ext(comm)
      if comm.bytesize == CommExtSize
        datasize, fullcrc32, segsize = comm.unpack('NNn')
      else
        log_message(LM_Error, 'Ошибочная длина расширения команды')
      end
      [datasize, fullcrc32, segsize]
    end

    LONG_SEG_SIGN   = 0xFFFF

    # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
    def send_comm_and_data(index, cmd, code, data=nil)
      res = nil
      lengt = 0
      lengt = data.bytesize if data
      #p log_mes+'SEND_ALL: [cmd, code, data.len]='+[cmd, code, lengt].inspect
      if donor
        #out_lure = fish.get_out_lure_for_fisher(self)
        segment = [cmd, code].pack('CC')
        segment << data if data
        if fisher_lure
          res = donor.send_queue.add_block_to_queue([EC_Lure, fisher_lure, segment])
        else
          res = donor.send_queue.add_block_to_queue([EC_Bite, fish_lure, segment])
        end
      else
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
        crc8 = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
        # Команда как минимум равна 1+1+1+2+1= 6 байт (CommSize)
        #p 'SCAB: '+[index, cmd, code, segsign, crc8].inspect
        comm = AsciiString.new([index, cmd, code, segsign, crc8].pack('CCCnC'))
        if index<255 then index += 1 else index = 0 end
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
          log_message(LM_Error, 'Не все данные отправлены '+sended.to_s)
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
          comm = [index, segindex, segsize].pack('CNn')
          if index<255 then index += 1 else index = 0 end
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
            log_message(LM_Error, 'Не все данные отправлены2 '+sended.to_s)
          end
          i += segdata
        end
      end
      res
    end

    # compose error command and add log message
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
        logmes = _(mes) + ' ' + logmes if mes and (mes.bytesize>0)
        @sbuf = logmes
        mesadd = ''
        mesadd = ' err=' + code.to_s if code
        log_message(LM_Warning, logmes+mesadd)
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
        when EC_Init
          @rkey = PandoraCrypto.current_key(false, false)
          #p log_mes+'first key='+key.inspect
          if @rkey and @rkey[PandoraCrypto::KV_Obj]
            key_hash = @rkey[PandoraCrypto::KV_Panhash]
            ascode = EC_Init
            ascode = ECC_Init_Hello
            params['mykey'] = key_hash
            params['tokey'] = param
            hparams = {:version=>0, :mode=>0, :mykey=>key_hash, :tokey=>param}
            hparams[:addr] = $incoming_addr if $incoming_addr and (not ($incoming_addr != ''))
            asbuf = PandoraUtils.namehash_to_pson(hparams)
          else
            ascmd = EC_Bye
            ascode = ECC_Bye_Exit
            asbuf = nil
          end
        when EC_Message
          asbuf = param
        when EC_Bye
          ascmd = EC_Bye
          ascode = ECC_Bye_Exit
          asbuf = param
        else
          asbuf = param
      end
      if (@send_queue.single_read_state != PandoraUtils::RoundQueue::QS_Full)
        res = @send_queue.add_block_to_queue([ascmd, ascode, asbuf])
      end
      if ascmd != EC_Media
        asbuf ||= '';
        p log_mes+'add_send_segment:  [ascmd, ascode, asbuf.bytesize]='+[ascmd, ascode, asbuf.bytesize].inspect
        p log_mes+'add_send_segment2: asbuf='+asbuf.inspect if sbuf
      end
      if not res
        log_message(LM_Error, _('Cannot add segment to send queue'))
        @conn_state = CS_Stoping
      end
      res
    end

    def set_request(panhashes, send_now=false)
      ascmd = EC_Request
      ascode = 0
      asbuf = nil
      if panhashes.is_a? Array
        asbuf = PandoraUtils.rubyobj_to_pson_elem(panhashes)
      else
        ascode = PandoraUtils.kind_from_panhash(panhashes)
        asbuf = panhashes[1..-1]
      end
      if send_now
        if not add_send_segment(ascmd, true, asbuf, ascode)
          log_message(LM_Error, _('Cannot add request'))
        end
      else
        @scmd = ascmd
        @scode = ascode
        @sbuf = asbuf
      end
    end

    def set_query(list, time, send_now=false)
      ascmd = EC_Query
      ascode = 0
      asbuf = nil
      if panhashes.is_a? Array
        asbuf = PandoraUtils.rubyobj_to_pson_elem(panhashes)
      else
        ascode = PandoraUtils.kind_from_panhash(panhashes)
        asbuf = panhashes[1..-1]
      end
      if send_now
        if not add_send_segment(ascmd, true, asbuf, ascode)
          log_message(LM_Error, _('Cannot add request'))
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

      def recognize_params
        hash = PandoraUtils.pson_to_namehash(rdata)
        if not hash
          err_scmd('Hello data is wrong')
        end
        if (rcmd == EC_Init) and (rcode == ECC_Init_Hello)
          params['version']  = hash['version']
          params['mode']     = hash['mode']
          params['addr']     = hash['addr']
          params['srckey']   = hash['mykey']
          params['dstkey']   = hash['tokey']
        end
        p log_mes+'RECOGNIZE_params: '+hash.inspect
      end

      def set_max_pack_size(stage)
        case stage
          when ST_Protocol
            @max_pack_size = MPS_Proto
          when ST_Puzzle
            @max_pack_size = MPS_Puzzle
          when ST_Sign
            @max_pack_size = MPS_Sign
          when ST_Captcha
            @max_pack_size = MPS_Captcha
          when ST_Exchange
            @max_pack_size = MPS_Exchange
        end
      end

      def init_skey_or_error(first=true)
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
        #p log_mes+'     skey_panhash='+skey_panhash.inspect
        if (skey_panhash.is_a? String) and (skey_panhash.bytesize>0)
          if first and (stage == ST_Protocol) and $puzzle_bit_length \
          and ($puzzle_bit_length>0) and ((conn_mode & CM_Hunter) == 0)
            phrase, init = get_sphrase(true)
            phrase[-1] = $puzzle_bit_length.chr
            phrase[-2] = $puzzle_sec_delay.chr
            @stage = ST_Puzzle
            @scode = ECC_Init_Puzzle
            @scmd  = EC_Init
            @sbuf = phrase
            params['puzzle_start'] = Time.now.to_i
            set_max_pack_size(ST_Puzzle)
          else
            @skey = PandoraCrypto.open_key(skey_panhash, @recv_models, false)
            # key: 1) trusted and inited, 2) stil not trusted, 3) denied, 4) not found
            # or just 4? other later!
            if (@skey.is_a? Integer) and (@skey==0)
              @scmd = EC_Request
              kind = PandoraModel::PK_Key
              @scode = kind
              @sbuf = nil
              @stage = ST_KeyRequest
              set_max_pack_size(ST_Exchange)
            elsif @skey
              #phrase = PandoraUtils.bigint_to_bytes(phrase)
              @stage = ST_Sign
              @scode = ECC_Init_Phrase
              @scmd  = EC_Init
              set_max_pack_size(ST_Sign)
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

      def send_captcha
        attempts = @skey[PandoraCrypto::KV_Trust]
        p log_mes+'send_captcha:  attempts='+attempts.to_s
        if attempts<$captcha_attempts
          @skey[PandoraCrypto::KV_Trust] = attempts+1
          @scmd = EC_Init
          @scode = ECC_Init_Captcha
          text, buf = PandoraUtils.generate_captcha(nil, $captcha_length)
          params['captcha'] = text.downcase
          clue_text = 'You may enter small letters|'+$captcha_length.to_s+'|'+PandoraGUI::CapSymbols
          clue_text = clue_text[0,255]
          @sbuf = [clue_text.bytesize].pack('C')+clue_text+buf
          @stage = ST_Captcha
          set_max_pack_size(ST_Captcha)
        else
          err_scmd('Captcha attempts is exhausted')
        end
      end

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

        #trusted = ((trust.is_a? Float) and (trust>0))
        filter = {:key_hash=>skey_panhash, :base_id=>sbase_id}
        #if not trusted
        #  filter[:addr_from] = host_ip
        #end
        sel = node_model.select(filter, false, readflds, nil, 1)
        if (not sel) or (sel.size==0) and @node_id
          filter = {:id=>@node_id}
          sel = node_model.select(filter, false, readflds, nil, 1)
        end

        if sel and sel.size>0
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

        values = {}
        if (not acreator) or (not acreated)
          acreator ||= PandoraCrypto.current_user_or_key(true)
          values[:creator] = acreator
          values[:created] = time_now
        end
        abase_id = sbase_id if (not abase_id) or (abase_id=='')
        akey_hash = skey_panhash if (not akey_hash) or (akey_hash=='')

        #adomain = @host_name if (not adomain) or (adomain=='')
        adomain = aaddr if (not adomain) or (adomain=='')
        aaddr = @host_ip if ((not aaddr) or (aaddr=='')) and adomain and (adomain != '')
        #adomain = @host_ip if (not adomain) or (adomain=='')

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
          if (host and (host != '')) and (port and (port != 0))
            host = @host_ip if (not host) or (host=='')
            port = 5577 if (not port) or (port==0)
            values[:domain] = host
            proto ||= ''
            values[:tport] = port if (proto != 'udp')
            values[:uport] = port if (proto != 'tcp')
            #values[:addr_type] = AT_Ip4
          end
        end

        if @node_id and (@node_id != 0) and ((not anode_id) or (@node_id != anode_id))
          filter2 = {:id=>@node_id}
          @node_id = nil
          sel = node_model.select(filter2, false, 'addr, domain, tport, uport, addr_type', nil, 1)
          if sel and sel.size>0
            baddr = sel[0][0]
            bdomain = sel[0][1]
            btport = sel[0][2]
            buport = sel[0][3]
            baddr_type = sel[0][4]

            adomain = bdomain if (not bdomain) or (bdomain=='')
            aaddr = baddr if (not baddr) or (baddr=='')
            adomain = baddr if (not adomain) or (adomain=='')

            values[:addr_type] ||= baddr_type
            node_model.update(nil, nil, filter2)
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

      def process_media_segment(cannel, mediabuf)
        if not dialog
          #node = PandoraNet.encode_node(host_ip, port, proto)
          panhash = @skey[PandoraCrypto::KV_Creator]
          @dialog = PandoraGUI.show_talk_dialog(panhash, @node_panhash)
          dialog.update_state(true)
          Thread.pass
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
            appsrc.play if (appsrc.get_state != Gst::STATE_PLAYING)
          else  #video puts to queue
            recv_buf.add_block_to_queue(mediabuf, $media_buf_size)
          end
        end
      end

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

      def take_out_lure_for_fisher(fisher, in_lure)
        out_lure = nil
        val = [fisher, in_lure]
        out_lure = @fishers.index(val)
        if not out_lure
          i = 0
          while (i<out_lure.size)
            break if (not (@fishers[i].is_a? Array))  #or (@fishers[i][0].destroyed?))
            i += 1
          end
          out_lure = i if (not out_lure) and (i<=255)
          @fishers[out_lure] = val if out_lure
        end
        out_lure
      end

      def get_out_lure_for_fisher(fisher, in_lure)
        val = [fisher, in_lure]
        out_lure = @fishers.index(val)
        out_lure
      end

      def get_fisher_for_out_lure(out_lure)
        fisher, in_lure = nil, nil
        val = @fishers[out_lure] if out_lure.is_a? Integer
        fisher, in_lure = val if val.is_a? Array
        [fisher, in_lure]
      end

      def free_out_lure_of_fisher(fisher, in_lure)
        val = [fisher, in_lure]
        while out_lure = @fishers.index(val)
          @fishers[out_lure] = nil
          if fisher #and (not fisher.destroyed?)
            if fisher.donor
              fisher.conn_state = CS_StopRead if (fisher.conn_state < CS_StopRead)
            end
            fisher.free_fish_of_in_lure(in_lure)
          end
        end
      end

      def set_fish_of_in_lure(in_lure, fish)
        @fishes[in_lure] = fish if in_lure.is_a? Integer
      end

      def get_fish_for_in_lure(in_lure)
        fish = nil
        if in_lure.is_a? Integer
          fish = @fishes[in_lure]
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

      def free_fish_of_in_lure(in_lure)
        if in_lure.is_a? Integer
          fish = @fishes[in_lure]
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
      def send_segment_to_fish(in_lure, segment)
        res = nil
        if segment and (segment.bytesize>1)
          fish = get_fish_for_in_lure(in_lure)
          if not fish
            fish = pool.init_fish_for_fisher(self, in_lure, nil, nil)
            set_fish_of_in_lure(in_lure, fish)
          end
          #p 'send_segment_to_fish: in_lure,segsize='+[in_lure, segment.bytesize].inspect
          if fish
            if fish.donor == self
              #p 'DONOR lure'
              cmd = segment[0].ord
              code = segment[1].ord
              data = nil
              data = segment[2..-1] if (segment.bytesize>2)
              #p '-->Add raw to fish (in_lure='+in_lure.to_s+') read queue: cmd,code,data='+[cmd, code, data].inspect
              res = fish.read_queue.add_block_to_queue([cmd, code, data])
            else
              p 'RESENDER lure'
              out_lure = fish.take_out_lure_for_fisher(self, in_lure)
              p '-->Add LURE to resender: inlure ==>> outlure='+[in_lure, out_lure].inspect
              res = fish.send_queue.add_block_to_queue([EC_Lure, out_lure, segment]) if out_lure.is_a? Integer
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
          p 'send_segment_to_fisher: out_lure,fisher,in_lure,segsize='+[out_lure, fisher, in_lure, segment.bytesize].inspect
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
        when EC_Init
          if stage<=ST_Greeting
            if rcode<=ECC_Init_Answer
              if (rcode==ECC_Init_Hello) and ((stage==ST_Protocol) or (stage==ST_Sign))
                recognize_params
                if scmd != EC_Bye
                  vers = params['version']
                  if vers==0
                    addr = params['addr']
                    p log_mes+'addr='+addr.inspect
                    # need to change an ip checking
                    pool.check_incoming_addr(addr, host_ip) if addr
                    mode = params['mode']
                    init_skey_or_error(true)
                  else
                    err_scmd('Protocol is not supported ['+vers.to_s+']')
                  end
                end
              elsif ((rcode==ECC_Init_Puzzle) or (rcode==ECC_Init_Phrase)) \
              and ((stage==ST_Protocol) or (stage==ST_Greeting))
                if rdata and (rdata != '')
                  rphrase = rdata
                  params['rphrase'] = rphrase
                else
                  rphrase = params['rphrase']
                end
                p log_mes+'recived phrase len='+rphrase.bytesize.to_s
                if rphrase and (rphrase != '')
                  if rcode==ECC_Init_Puzzle  #phrase for puzzle
                    if ((conn_mode & CM_Hunter) == 0)
                      err_scmd('Puzzle to listener is denied')
                    else
                      delay = rphrase[-2].ord
                      #p 'PUZZLE delay='+delay.to_s
                      start_time = 0
                      end_time = 0
                      start_time = Time.now.to_i if delay
                      suffix = PandoraGUI.find_sha1_solution(rphrase)
                      end_time = Time.now.to_i if delay
                      if delay
                        need_sleep = delay - (end_time - start_time) + 0.5
                        sleep(need_sleep) if need_sleep>0
                      end
                      @sbuf = suffix
                      @scode = ECC_Init_Answer
                    end
                  else #phrase for sign
                    #p log_mes+'SIGN'
                    rphrase = OpenSSL::Digest::SHA384.digest(rphrase)
                    sign = PandoraCrypto.make_sign(@rkey, rphrase)
                    len = $base_id.bytesize
                    len = 255 if len>255
                    @sbuf = [len].pack('C')+$base_id[0,len]+sign
                    @scode = ECC_Init_Sign
                    if @stage == ST_Greeting
                      @stage = ST_Exchange
                      set_max_pack_size(ST_Exchange)
                    end
                  end
                  @scmd = EC_Init
                  #@stage = ST_Check
                else
                  err_scmd('Empty received phrase')
                end
              elsif (rcode==ECC_Init_Answer) and (stage==ST_Puzzle)
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
              elsif (rcode==ECC_Init_Sign) and (stage==ST_Sign)
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
                    update_node(@skey[PandoraCrypto::KV_Panhash], sbase_id, trust)
                    if ((conn_mode & CM_Hunter) == 0)
                      trust = 0 if (not trust) and $trust_for_captchaed
                    elsif $trust_for_listener and (not (trust.is_a? Float))
                      trust = 0.01
                      @skey[PandoraCrypto::KV_Trust] = trust
                    end
                    p log_mes+'----trust='+trust.inspect
                    if ($captcha_length>0) and (trust.is_a? Integer) and ((conn_mode & CM_Hunter) == 0)
                      @skey[PandoraCrypto::KV_Trust] = 0
                      send_captcha
                    elsif trust.is_a? Float
                      if trust>0.0
                        if (conn_mode & CM_Hunter) == 0
                          @stage = ST_Greeting
                          add_send_segment(EC_Init, true, params['srckey'])
                          set_max_pack_size(ST_Sign)
                        else
                          @stage = ST_Exchange
                          set_max_pack_size(ST_Exchange)
                        end
                        @scmd = EC_Data
                        @scode = 0
                        @sbuf = nil
                      else
                        err_scmd('Key is not trusted')
                      end
                    else
                      err_scmd('Key stil is not checked')
                    end
                  else
                    err_scmd('Wrong sign')
                  end
                else
                  err_scmd('Cannot init your key')
                end
              elsif (rcode==ECC_Init_Simple) and (stage==ST_Protocol)
                p 'ECC_Init_Simple!'
                rphrase = rdata
                #p 'rphrase='+rphrase.inspect
                password = get_simple_answer_to_node
                if (password.is_a? String) and (password.bytesize>0)
                  password_hash = OpenSSL::Digest::SHA256.digest(password)
                  answer = OpenSSL::Digest::SHA256.digest(rphrase+password_hash)
                  @scmd = EC_Init
                  @scode = ECC_Init_Answer
                  @sbuf = answer
                else
                  err_scmd('Node password is not setted')
                end
              elsif (rcode==ECC_Init_Captcha) and ((stage==ST_Protocol) or (stage==ST_Greeting))
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
                    while @entered_captcha.nil?
                      Thread.pass
                    end
                  end

                  if @entered_captcha
                    @scmd = EC_Init
                    @scode = ECC_Init_Answer
                    @sbuf = entered_captcha
                  else
                    err_scmd('Captcha enter canceled')
                  end
                end
              elsif (rcode==ECC_Init_Answer) and (stage==ST_Captcha)
                captcha = rdata
                p log_mes+'recived captcha='+captcha
                if captcha.downcase==params['captcha']
                  @stage = ST_Greeting
                  if not (@skey[PandoraCrypto::KV_Trust].is_a? Float)
                    if $trust_for_captchaed
                      @skey[PandoraCrypto::KV_Trust] = 0.01
                    else
                      @skey[PandoraCrypto::KV_Trust] = nil
                    end
                  end
                  p 'Captcha is GONE!'
                  if (conn_mode & CM_Hunter) == 0
                    add_send_segment(EC_Init, true, params['srckey'])
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
        when EC_Message, EC_Channel
          #curpage = nil
          p log_mes+'mes len='+@rdata.bytesize.to_s
          if not dialog
            #node = pool.encode_node(host_ip, port, proto)
            panhash = @skey[PandoraCrypto::KV_Creator]
            @dialog = PandoraGUI.show_talk_dialog(panhash, @node_panhash)
            #curpage = dialog
            Thread.pass
            #sleep(0.1)
            #Thread.pass
            #p log_mes+'NEW dialog1='+dialog.inspect
            #p log_mes+'NEW dialog2='+@dialog.inspect
          end
          if rcmd==EC_Message
            mes = @rdata
            talkview = nil
            #p log_mes+'MES dialog='+dialog.inspect
            talkview = dialog.talkview if dialog
            if talkview
              t = Time.now
              talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
              talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', 'dude')
              myname = PandoraCrypto.short_name_of_person(@rkey)
              dude_name = PandoraCrypto.short_name_of_person(@skey, nil, 0, myname)
              talkview.buffer.insert(talkview.buffer.end_iter, dude_name+':', 'dude_bold')
              talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)
              talkview.parent.vadjustment.value = talkview.parent.vadjustment.upper
              talkview.show_all
              dialog.update_state(true)
            else
              log_message(LM_Error, 'Пришло сообщение, но лоток чата не найдено!')
            end
          else #EC_Channel
            case rcode
              when ECC_Channel0_Open
                p 'ECC_Channel0_Open'
              when ECC_Channel2_Close
                p 'ECC_Channel2_Close'
            else
              log_message(LM_Error, 'Неизвестный код управления каналом: '+rcode.to_s)
            end
          end
        when EC_Media
          process_media_segment(rcode, rdata)
        when EC_Request
          kind = rcode
          p log_mes+'EC_Request  kind='+kind.to_s+'  stage='+stage.to_s
          panhash = nil
          if (kind==PandoraModel::PK_Key) and ((stage==ST_Protocol) or (stage==ST_Greeting))
            panhash = params['mykey']
            p 'params[mykey]='+panhash
          end
          if (stage==ST_Exchange) or (stage==ST_Greeting) or panhash
            panhashes = nil
            if kind==0
              panhashes, len = PandoraUtils.pson_elem_to_rubyobj(panhashes)
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
                values = PandoraUtils.pson_to_namehash(@sbuf[1..-1])
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
                records = PandoraGUI.rubyobj_to_pson_elem(rec_array)
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
            if (stage==ST_Exchange) or ((kind==PandoraModel::PK_Key) and (stage==ST_KeyRequest))
              lang = rdata[0].ord
              values = PandoraUtils.pson_to_namehash(rdata[1..-1])
              panhash = nil
              if stage==ST_KeyRequest
                panhash = params['srckey']
              end
              res = PandoraModel.save_record(kind, lang, values, @recv_models, panhash)
              if res
                if stage==ST_KeyRequest
                  stage = ST_Protocol
                  init_skey_or_error(false)
                end
              elsif res==false
                log_message(LM_Warning, 'Пришла запись с ошибочным панхэшем')
              else
                log_message(LM_Warning, 'Не удалось сохранить запись 1')
              end
            else
              err_scmd('Record ('+kind.to_s+') came on wrong stage')
            end
          else
            if (stage==ST_Exchange)
              records, len = PandoraUtils.pson_elem_to_rubyobj(rdata)
              p log_mes+"!record2! recs="+records.inspect
              records.each do |record|
                kind = record[0].ord
                lang = record[1].ord
                values = PandoraUtils.pson_to_namehash(record[2..-1])
                if not PandoraModel.save_record(kind, lang, values, @recv_models)
                  log_message(LM_Warning, 'Не удалось сохранить запись 2')
                end
                p 'fields='+fields.inspect
              end
            else
              err_scmd('Records came on wrong stage')
            end
          end
        when EC_Query
          case rcode
            when ECC_Query0_Kinds
              afrom_data=rdata
              @scmd=EC_News
              pkinds="3,7,11"
              @scode=ECC_News0_Kinds
              @sbuf=pkinds
            else #(1..255) - запрос сорта/всех сортов, если 255
              afrom_data=rdata
              akind=rcode
              if akind==ECC_Query255_AllChanges
                pkind=3 #отправка первого кайнда из серии
              else
                pkind=akind  #отправка только запрашиваемого
              end
              @scmd=EC_News
              pnoticecount=3
              @scode=pkind
              @sbuf=[pnoticecount].pack('N')
          end
        when EC_News
          p "news!!!!"
          if rcode==ECC_News0_Kinds
            pcount = rcode
            pkinds = rdata
            @scmd=EC_Query
            @scode=ECC_Query255_AllChanges
            fromdate="01.01.2012"
            @sbuf=fromdate
          else
            p "news more!!!!"
            pkind = rcode
            pnoticecount = rdata.unpack('N')
            @scmd=EC_Sync
            @scode=0
            @sbuf=''
          end
        when EC_Lure
          send_segment_to_fish(rcode, rdata)
          #sleep 2
        when EC_Bite
          #p "EC_Bite"
          send_segment_to_fisher(rcode, rdata)
          #sleep 2
        when EC_Sync
          case rcode
            when ECC_Sync1_NoRecord
              p log_mes+'EC_Sync: No record: panhash='+rdata.inspect
            when ECC_Sync2_Encode
              @r_encode = true
          end
        when EC_Wait
          case rcode
            when EC_Wait1_NoFish
              log_message(LM_Error, _('Cannot find a fish'))
          end
        when EC_Bye
          if rcode != ECC_Bye_Exit
            mes = rdata
            mes ||= ''
            log_message(LM_Error, _('Error at other side')+' ErrCode='+rcode.to_s+' "'+mes+'"')
          end
          err_scmd(nil, ECC_Bye_Exit, false)
          @conn_state = CS_Stoping
        else
          err_scmd('Unknown command is recieved '+rcmd.to_s, ECC_Bye_Unknown)
          @conn_state = CS_Stoping
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

    # Number of messages per cicle
    # RU: Число сообщений за цикл
    $mes_block_count = 5
    # Number of media blocks per cicle
    # RU: Число медиа блоков за цикл
    $media_block_count = 10
    # Number of requests per cicle
    # RU: Число запросов за цикл
    $inquire_block_count = 1

    # Start two exchange cicle of socket: read and send
    # RU: Запускает два цикла обмена сокета: чтение и отправка
    def run(asocket, ahost_name, ahost_ip, aport, aproto, aconn_mode, \
    aconn_state, a_send_thread, anode_id, a_dialog, tokey, send_state_add)
      if asocket.is_a? Session
        @donor        = asocket
        if ahost_name
          @fisher_lure  = ahost_name
        else
          @fish_lure  = ahost_ip
        end
      else
        @socket       = asocket
        @host_name    = ahost_name
        @host_ip      = ahost_ip
        @port         = aport
        @proto        = aproto
        @node         = pool.encode_node(@host_ip, @port, @proto)
        @node_id      = anode_id
      end

      @stage         = ST_Protocol  #ST_IpCheck
      @conn_mode     = aconn_mode
      @conn_state    = aconn_state
      @conn_state    ||= CS_Connecting
      @read_state     = 0
      send_state_add ||= 0
      @send_state     = send_state_add
      @sindex         = 0
      @read_queue     = PandoraUtils::RoundQueue.new
      @send_queue     = PandoraUtils::RoundQueue.new
      @send_models    = {}
      @recv_models    = {}
      @params         = {}
      @media_send     = false
      @node_panhash   = nil
      @fishes         = Array.new
      @fishers        = Array.new
      pool.add_session(self)
      if @socket
        set_keepalive(@socket)
      end

      @dialog = a_dialog
      if dialog and (not dialog.destroyed?)
        dialog.set_session(self, true)
        #dialog.online_button.active = (socket and (not socket.closed?))
      end

      #Thread.critical = true
      #PandoraGUI.add_session(self)
      #Thread.critical = false

      # Sending thread
      @send_thread = a_send_thread

      @max_pack_size = MPS_Proto
      @log_mes = 'LIS: '
      if (conn_mode & CM_Hunter)>0
        @log_mes = 'HUN: '
        @max_pack_size = MPS_Captcha
        add_send_segment(EC_Init, true, tokey)
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

          rkcmd = EC_Sync
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
                      if rsegsign == Session::LONG_SEG_SIGN
                        readmode = RM_CommExt
                        waitlen = CommExtSize
                      elsif rsegsign > 0
                        readmode = RM_SegmentS
                        waitlen, rdatasize = rsegsign, rsegsign
                        rdatasize -=4 if (rkcmd != EC_Media)
                      end
                    else
                      serrbuf, serrcode = 'Bad command code', ECC_Bye_BadComm
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
                  rkindex, rsegindex, rsegsize = comm.unpack('CNn')
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
                      waitlen = 7    #index + segindex + rseglen (1+4+2)
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
                    log_message(LM_Error, _('Cannot add error segment to send queue'))
                  end
                end
                @conn_state = CS_Stoping
              elsif (readmode == RM_Comm)
                #p log_mes+'-- from socket to read queue: [rkcmd, rcode, rkdata.size]='+[rkcmd, rkcode, rkdata.size].inspect
                if @r_encode and rkdata and (rkdata.bytesize>0)
                  #@rkdata = PandoraGUI.recrypt(@rkey, @rkdata, false, true)
                  #@rkdata = Base64.strict_decode64(@rkdata)
                  #p log_mes+'::: decode rkdata.size='+rkdata.size.to_s
                end

                if rkcmd==EC_Media
                  process_media_segment(rkcode, rkdata)
                else
                  while (@read_queue.single_read_state == PandoraUtils::RoundQueue::QS_Full ) \
                  and (@conn_state == CS_Connected)
                    sleep(0.03)
                    Thread.pass
                  end
                  res = @read_queue.add_block_to_queue([rkcmd, rkcode, rkdata])
                  if not res
                    log_message(LM_Error, _('Cannot add socket segment to read queue'))
                    @conn_state = CS_Stoping
                  end
                end
                rkdata = AsciiString.new
              end

              if not ok1comm
                log_message(LM_Error, 'Bad first command')
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
        @rcmd = EC_Sync
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
              while (@send_queue.single_read_state == PandoraUtils::RoundQueue::QS_Full) \
              and (@conn_state == CS_Connected)
                sleep(0.03)
                Thread.pass
              end
              res = @send_queue.add_block_to_queue([@scmd, @scode, @sbuf])
              @scmd = EC_Data
              if not res
                log_message(LM_Error, 'Error while adding segment to queue')
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
      inquirer_step = IS_CreatorCheck
      message_model = PandoraUtils.get_model('Message', @send_models)
      p log_mes+'ЦИКЛ ОТПРАВКИ начало'

      while (@conn_state != CS_Disconnected)
        # отправка сформированных сегментов и их удаление
        fast_data = false
        if (@conn_state != CS_Disconnected)
          send_segment = @send_queue.get_block_from_queue
          while (@conn_state != CS_Disconnected) and send_segment
            #p log_mes+' send_segment='+send_segment.inspect
            sscmd, sscode, ssbuf = send_segment
            if ssbuf and (ssbuf.bytesize>0) and @s_encode
              #ssbuf = PandoraGUI.recrypt(@skey, ssbuf, true, false)
              #ssbuf = Base64.strict_encode64(@sbuf)
            end
            #p log_mes+'MAIN SEND: '+[@sindex, sscmd, sscode, ssbuf].inspect
            @sindex = send_comm_and_data(@sindex, sscmd, sscode, ssbuf)
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
        while (@conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and ((send_state & (CSF_Message | CSF_Messaging)) == 0) and (processed<$inquire_block_count) \
        and (inquirer_step<IS_Finished)
          case inquirer_step
            when IS_CreatorCheck
              creator = @skey[PandoraCrypto::KV_Creator]
              kind = PandoraUtils.kind_from_panhash(creator)
              res = PandoraModel.get_record_by_panhash(kind, creator, nil, @send_models, 'id')
              p log_mes+'Whyer: CreatorCheck  creator='+creator.inspect
              if not res
                p log_mes+'Whyer: CreatorCheck  Request!'
                set_request(creator, true)
              end
              inquirer_step += 1
            when IS_NewsQuery
              #set_query(@query_kind_list, @last_time, true)
              inquirer_step += 1
            else
              inquirer_step = IS_Finished
          end
          processed += 1
        end

        # обработка принятых сообщений, их удаление

        # разгрузка принятых буферов в gstreamer
        processed = 0
        cannel = 0
        while (@conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and ((send_state & (CSF_Message | CSF_Messaging)) == 0) and (processed<$media_block_count) \
        and dialog and (not dialog.destroyed?) and (cannel<dialog.recv_media_queue.size)
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
        if (@conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and (((send_state & CSF_Message)>0) or ((send_state & CSF_Messaging)>0))
          fast_data = true
          @send_state = (send_state & (~CSF_Message))
          if @skey and @skey[PandoraCrypto::KV_Creator]
            filter = {'destination'=>@skey[PandoraCrypto::KV_Creator], 'state'=>0}
            fields = 'id, text'
            sel = message_model.select(filter, false, fields, 'created', $mes_block_count)
            if sel and (sel.size>0)
              @send_state = (send_state | CSF_Messaging)
              i = 0
              while sel and (i<sel.size) and (processed<$mes_block_count) \
              and (@conn_state == CS_Connected) \
              and (@send_queue.single_read_state != PandoraUtils::RoundQueue::QS_Full)
                processed += 1
                id = sel[i][0]
                text = sel[i][1]
                #p log_mes+'send_message: [i, id, text]='+[i, id, text].inspect
                if add_send_segment(EC_Message, true, text)
                  res = message_model.update({:state=>1}, nil, 'id='+id.to_s)
                  if not res
                    log_message(LM_Error, 'Ошибка обновления сообщения text='+text)
                  end
                else
                  log_message(LM_Error, 'Ошибка отправки сообщения text='+text)
                end
                i += 1
                if (i>=sel.size) and (processed<$mes_block_count) and (@conn_state == CS_Connected)
                  #sel = message_model.select('destination="'+node.to_s+'" AND state=0', \
                  #  false, 'id, text', 'created', $mes_block_count)
                  sel = message_model.select(filter, false, fields, 'created', $mes_block_count)
                  if sel and (sel.size>0)
                    i = 0
                  else
                    @send_state = (send_state & (~CSF_Messaging))
                  end
                end
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
        and (@conn_state == CS_Connected) and (stage>=ST_Exchange) \
        and ((send_state & CSF_Message) == 0) and dialog and (not dialog.destroyed?) and dialog.room_id \
        and ((dialog.vid_button and (not dialog.vid_button.destroyed?) and dialog.vid_button.active?) \
        or (dialog.snd_button and (not dialog.snd_button.destroyed?) and dialog.snd_button.active?))
          fast_data = true
          #p 'packbuf '+cannel.to_s
          pointer_ind = PandoraGUI.get_send_ptrind_by_room(dialog.room_id)
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
              @sindex = send_comm_and_data(sindex, mscmd, mscode, msbuf)
              if not @sindex
                log_message(LM_Error, 'Ошибка отправки буфера data.size='+send_media_chunk.size.to_s)
              end
            else
              cannel += 1
            end
          end
        end

        if socket and socket.closed? or (@conn_state == CS_StopRead)
          @conn_state = CS_Disconnected
        elsif (not fast_data)
          sleep(0.2)
        #elsif conn_state == CS_Stoping
        #  add_send_segment(EC_Bye, true)
        end
        Thread.pass
      end

      p log_mes+"Цикл ОТПРАВКИ конец!!!"

      #Thread.critical = true
      pool.del_session(self)
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
      @socket_thread.exit if @socket_thread
      @read_thread.exit if @read_thread
      if donor #and (not donor.destroyed?)
        if fisher_lure
          donor.free_out_lure_of_fisher(self, fisher_lure)
        else
          donor.free_fish_of_in_lure(fish_lure)
        end
      end
      i = fishes.size
      while (i>0)
        i -= 1
        fish = fishes[i]
        fish.free_out_lure_of_fisher(self, i) if fish #and (not fish.destroyed?)
      end
      i = fishers.size
      while (i>0)
        i -= 1
        fisher = nil
        val = fishers[i]
        fisher, out_lure = val if val.is_a? Integer
        fisher.free_fish_of_in_lure(i) if fisher #and (not fisher.destroyed?)
      end

      @conn_state = CS_Disconnected
      @socket = nil
      @send_thread = nil

      if dialog and (not dialog.destroyed?) #and (not dialog.online_button.destroyed?)
        dialog.set_session(self, false)
        #dialog.online_button.active = false
      end
    end

  end

  # Check ip is not banned
  # RU: Проверяет, не забанен ли ip
  def self.ip_is_not_banned(host_ip)
    true
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

  def self.get_exchage_params
    $incoming_addr       = PandoraUtils.get_param('incoming_addr')
    $puzzle_bit_length   = PandoraUtils.get_param('puzzle_bit_length')
    $puzzle_sec_delay    = PandoraUtils.get_param('puzzle_sec_delay')
    $captcha_length      = PandoraUtils.get_param('captcha_length')
    $captcha_attempts    = PandoraUtils.get_param('captcha_attempts')
    $trust_for_captchaed = PandoraUtils.get_param('trust_for_captchaed')
    $trust_for_listener  = PandoraUtils.get_param('trust_for_listener')
  end

  $listen_thread = nil

  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.start_or_stop_listen
    PandoraNet.get_exchage_params
    if not $listen_thread
      user = PandoraCrypto.current_user_or_key(true)
      if user
        $window.set_status_field(PandoraGUI::SF_Listen, 'Listening', nil, true)
        $port = PandoraUtils.get_param('tcp_port')
        $host = PandoraUtils.get_param('listen_host')
        $listen_thread = Thread.new do
          begin
            host = $host
            if host==nil
              host = ''
            elsif host=='any'  #alse can be "", "0.0.0.0", "0", "0::0", "::"
              host = Socket::INADDR_ANY
            end
            server = TCPServer.open(host, $port)
            addr_str = server.addr[3].to_s+(':')+server.addr[1].to_s
            log_message(LM_Info, 'Слушаю порт '+addr_str)
          rescue
            server = nil
            log_message(LM_Warning, 'Не могу открыть порт '+host+':'+$port.to_s)
          end
          Thread.current[:listen_server_socket] = server
          Thread.current[:need_to_listen] = (server != nil)
          while Thread.current[:need_to_listen] and server and not server.closed?
            # Создать поток при подключении клиента
            client = get_listener_client_or_nil(server)
            while Thread.current[:need_to_listen] and not server.closed? and not client
              sleep 0.03
              #Thread.pass
              #Gtk.main_iteration
              client = get_listener_client_or_nil(server)
            end

            if Thread.current[:need_to_listen] and not server.closed? and client
              Thread.new(client) do |socket|
                log_message(LM_Info, "Подключился клиент: "+socket.peeraddr.inspect)

                host_ip = socket.peeraddr[2]

                if ip_is_not_banned(host_ip)
                  host_name = socket.peeraddr[3]
                  port = socket.peeraddr[1]
                  #port = socket.addr[1] if host_ip==socket.addr[2] # hack for short circuit!!!
                  proto = "tcp"
                  node = $window.pool.encode_node(host_ip, port, proto)
                  p "LISTEN: node: "+node.inspect

                  session = $window.pool.session_of_node(node)
                  if session
                    log_message(LM_Info, "Замкнутая петля: "+socket.to_s)
                    while session and (session.conn_state==CS_Connected) and not socket.closed?
                      begin
                        buf = socket.recv(MaxPackSize) if not socket.closed?
                      rescue
                        buf = ''
                      end
                      socket.send(buf, 0) if (not socket.closed? and buf and (buf.bytesize>0))
                      session = $window.pool.session_of_node(node)
                    end
                  else
                    conn_mode = 0
                    session = Session.new
                    session.run(socket, host_name, host_ip, port, proto, conn_mode, \
                      CS_Connected, Thread.current, nil, nil, nil, nil)
                    p "END LISTEN SOKET CLIENT!!!"
                  end
                else
                  log_message(LM_Info, "IP забанен: "+host_ip.to_s)
                end
                socket.close if not socket.closed?
                log_message(LM_Info, "Отключился клиент: "+socket.to_s)
              end
            end
          end
          server.close if server and not server.closed?
          log_message(LM_Info, 'Слушатель остановлен '+addr_str) if server
          $window.set_status_field(PandoraGUI::SF_Listen, 'Not listen', nil, false)
          $listen_thread = nil
        end
      else
        $window.correct_lis_btn_state
      end
    else
      p server = $listen_thread[:listen_server_socket]
      $listen_thread[:need_to_listen] = false
      #server.close if not server.closed?
      #$listen_thread.join(2) if $listen_thread
      #$listen_thread.exit if $listen_thread
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
        flds = 'id, addr, domain, tport, key_hash'
        sel = node_model.select(filter, false, flds)
        if sel and sel.size>0
          $hunter_thread = Thread.new(node_model, filter, flds, sel) \
          do |node_model, filter, flds, sel|
            $window.set_status_field(PandoraGUI::SF_Hunt, 'Hunting', nil, true)
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
                  tokey = row[4]
                  tport = $port if (not tport) or (tport==0) or (tport=='')
                  domain = addr if ((not domain) or (domain == ''))
                  node = $window.pool.encode_node(domain, tport, 'tcp')
                  $window.pool.init_session(node, tokey, nil, nil, node_id)
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
            $window.set_status_field(PandoraGUI::SF_Hunt, 'No hunt', nil, false)
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
            PandoraGUI.show_panobject_list(PandoraModel::Node, nil, nil, true)
          end
          dialog.destroy
        end
      else
        $window.correct_hunt_btn_state
      end
    end
  end

end

# ==============================================================================
# == Graphical user interface of Pandora
# == RU: Графический интерфейс Пандора
module PandoraGUI
  include PandoraUtils
  include PandoraModel

  SF_Update = 0
  SF_Auth   = 1
  SF_Listen = 2
  SF_Hunt   = 3
  SF_Conn   = 4

  if not $gtk2_on
    Kernel.abort('Gtk is not installed')
  end

  # About dialog hooks
  # RU: Обработчики диалога "О программе"
  Gtk::AboutDialog.set_url_hook do |about, link|
    if os_family=='windows' then a1='start'; a2='' else a1='xdg-open'; a2=' &' end;
    system(a1+' '+link+a2)
  end
  Gtk::AboutDialog.set_email_hook do |about, link|
    if os_family=='windows' then a1='start'; a2='' else a1='xdg-email'; a2=' &' end;
    system(a1+' '+link+a2)
  end

  # Show About dialog
  # RU: Показ окна "О программе"
  def self.show_about
    dlg = Gtk::AboutDialog.new
    dlg.transient_for = $window
    dlg.icon = $window.icon
    dlg.name = $window.title
    dlg.version = "0.1"
    dlg.logo = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.png'))
    dlg.authors = [_('Michael Galyuk')+' <robux@mail.ru>']
    dlg.artists = ['© '+_('Rights to logo are owned by 21th Century Fox')]
    dlg.comments = _('Distributed Social Network')
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
    #if os_family=='unix'
      dlg.program_name = dlg.name
      dlg.skip_taskbar_hint = true
    #end
    dlg.run
    dlg.destroy
    $window.present
  end

  def self.set_statusbar_text(statusbar, text)
    statusbar.pop(0)
    statusbar.push(0, text)
  end

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window
    attr_accessor :response, :window, :notebook, :vpaned, :viewport, :hbox, :enter_like_tab, :enter_like_ok, \
      :panelbox, :okbutton, :cancelbutton, :def_widget, :main_sw

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

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      window.add(vpaned)

      @main_sw = Gtk::ScrolledWindow.new(nil, nil)
      sw = main_sw
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      @viewport = Gtk::Viewport.new(nil, nil)
      sw.add(viewport)

      image = Gtk::Image.new(Gtk::Stock::PROPERTIES, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box1 = TabLabelBox.new(image, _('Basic'), nil, false, 0)

      @notebook = Gtk::Notebook.new
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
      okbutton.signal_connect('clicked') { |*args| @response=2 }
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') { |*args| @response=1 }
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

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
          okbutton.activate
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

    # show dialog until key pressed
    def run(alien_thread=false)
      res = false
      show_all
      if @def_widget
        #focus = @def_widget
        @def_widget.grab_focus
      end
      while (not destroyed?) and (@response == 0) do
        unless alien_thread
          Gtk.main_iteration
        end
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
  # ToggleToolButton с безопасным переключением "active"
  class GoodToggleToolButton < Gtk::ToggleToolButton
    def good_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end
    def good_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # CheckButton with safety "active" switching
  # CheckButton с безопасным переключением "active"
  class GoodCheckButton < Gtk::CheckButton
    def good_signal_clicked
      @clicked_signal = self.signal_connect('clicked') do |*args|
        yield(*args) if block_given?
      end
    end
    def good_set_active(an_active)
      if @clicked_signal
        self.signal_handler_block(@clicked_signal) do
          self.active = an_active
        end
      end
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock, title, toggle=nil)
    btn = nil
    if toggle != nil
      btn = GoodToggleToolButton.new(stock)
      btn.good_signal_clicked do |*args|
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

  # Entry with allowed symbols of mask
  # RU: Поле ввода с допустимыми символами в маске
  class MaskEntry < Gtk::Entry
    attr_accessor :tooltip, :mask
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
      @tooltip = nil
      init_mask
      if (not tooltip) and mask and (mask.size>0)
        @tooltip = '['+mask+']'
      end
      self.tooltip_text = tooltip if tooltip
    end
    def init_mask
      #will reinit in child
    end
    def key_event(widget, event)
      false
    end
  end

  class IntegerEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789-'
      self.max_length = 20
    end
  end

  class FloatEntry < IntegerEntry
    def init_mask
      super
      @mask += '.e'
      self.max_length = 35
    end
  end

  class HexEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789abcdefABCDEF'
    end
  end

  Base64chars = [*('0'..'9'), *('a'..'z'), *('A'..'Z'), '+/=-_*[]'].join

  class Base64Entry < MaskEntry
    def init_mask
      super
      @mask = Base64chars
    end
  end

  class DateEntry < MaskEntry
    def init_mask
      super
      @mask = '0123456789.'
      self.max_length = 10
      @tooltip = 'MM.DD.YYYY'
    end
  end

  class TimeEntry < DateEntry
    def init_mask
      super
      @mask += ' :'
      self.max_length = 16
      @tooltip = 'MM.DD.YYYY hh:mm:ss'
    end
  end

  MaxPanhashTabs = 5

  class PanhashBox < Gtk::HBox
    attr_accessor :types, :panclasses, :entry, :button
    def initialize(panhash_type, *args)
      super(*args)
      @types = panhash_type
      @entry = HexEntry.new
      @button = Gtk::Button.new('...')
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
        set_classes
        dialog = PandoraGUI::AdvancedDialog.new(_('Choose object'))
        dialog.set_default_size(600, 400)
        auto_create = true
        panclasses.each_with_index do |panclass, i|
          title = _(PandoraUtils.get_name_or_names(panclass.name, true))
          dialog.main_sw.destroy if i==0
          image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          label_box2 = TabLabelBox.new(image, title, nil, false, 0)
          sw = Gtk::ScrolledWindow.new(nil, nil)
          page = dialog.notebook.append_page(sw, label_box2)
          auto_create = PandoraGUI.show_panobject_list(panclass, nil, sw, auto_create)
          if panclasses.size>MaxPanhashTabs
            break
          end
        end
        dialog.notebook.page = 0
        dialog.run do
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
          @entry.text = PandoraUtils.bytes_to_hex(panhash) if (panhash.is_a? String)
        end
        #yield if block_given?
      end
    end
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

  class CoordEntry < FloatEntry
    def init_mask
      super
      @mask += 'EsNn SwW\'"`′″,'
      self.max_length = 35
    end
  end

  class CoordBox < Gtk::HBox
    attr_accessor :latitude, :longitude
    CoordWidth = 120
    def initialize
      super
      @latitude   = CoordEntry.new
      @longitude  = CoordEntry.new
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

  # Tree of panobjects
  # RU: Дерево субъектов
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject, :sel, :notebook, :auto_create
  end

  class SubjTreeViewColumn < Gtk::TreeViewColumn
    attr_accessor :tab_ind
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

  # Showing panobject list
  # RU: Показ списка субъектов
  def self.show_panobject_list(panobject_class, widget=nil, sw=nil, auto_create=false)
    notebook = $window.notebook
    single = (sw == nil)
    if single
      notebook.children.each do |child|
        if child.name==panobject_class.ider
          notebook.page = notebook.children.index(child)
          return
        end
      end
    end
    panobject = panobject_class.new
    sel = panobject.select(nil, false, nil, panobject.sort)
    store = Gtk::ListStore.new(Integer)
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
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject
    treeview.sel = sel

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
            val = val[0,45]
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
        dialog = sw.parent.parent.parent
        dialog.okbutton.activate
      end
    end

    sw ||= Gtk::ScrolledWindow.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.name = panobject.ider
    sw.add(treeview)
    sw.border_width = 0

    if auto_create and sel and (sel.size==0)
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
      p 'single: widget='+widget.inspect
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

      label_box = TabLabelBox.new(image, panobject.pname, sw, false, 0) do
        store.clear
        treeview.destroy
      end

      page = notebook.append_page(sw, label_box)
      sw.show_all
      notebook.page = notebook.n_pages-1

      if treeview.sel.size>0
        treeview.set_cursor(Gtk::TreePath.new(treeview.sel.size-1), nil, false)
      end
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
    menu.append(create_menu_item(['Clone', Gtk::Stock::CONVERT, _('Recreate the table')], treeview))
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

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    include PandoraUtils

    attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
      :support_btn, :vouch_btn, :trust_scale, :trust0, :public_btn, :lang_entry, :format, :view_buffer

    def add_menu_item(label, menu, text)
      mi = Gtk::MenuItem.new(text)
      menu.append(mi)
      mi.signal_connect('activate') { |mi|
        label.label = mi.label
        @format = mi.label.to_s
        p 'format changed to: '+format.to_s
      }
    end

    def set_view_buffer(format, view_buffer, raw_buffer)
      view_buffer.text = raw_buffer.text
    end

    def set_raw_buffer(format, raw_buffer, view_buffer)
      raw_buffer.text = view_buffer.text
    end

    def set_buffers(init=false)
      child = notebook.get_nth_page(notebook.page)
      if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
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

    def set_tag(tag)
      if tag
        child = notebook.get_nth_page(notebook.page)
        if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
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

      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::DND, 'Type', true) do |btn|
        @view_mode = btn.active?
        set_buffers
      end

      btn = Gtk::MenuToolButton.new(nil, 'auto')
      menu = Gtk::Menu.new
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

      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::BOLD, 'Bold') do |*args|
        set_tag('bold')
      end

      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::ITALIC, 'Italic') do |*args|
        set_tag('italic')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::STRIKETHROUGH, 'Strike') do |*args|
        set_tag('strike')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::UNDERLINE, 'Underline') do |*args|
        set_tag('undline')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::UNDO, 'Undo')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::REDO, 'Redo')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::COPY, 'Copy')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::CUT, 'Cut')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::FIND, 'Find')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_LEFT, 'Left') do |*args|
        set_tag('left')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_RIGHT, 'Right') do |*args|
        set_tag('right')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, 'Center') do |*args|
        set_tag('center')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_FILL, 'Fill') do |*args|
        set_tag('fill')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::SAVE, 'Save')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::OPEN, 'Open')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link') do |*args|
        set_tag('link')
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::HOME, 'Image')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::ADD, 'Add')
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::DELETE, 'Delete')
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::OK, 'Ok') { |*args| @response=2 }
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::CANCEL, 'Cancel') { |*args| @response=1 }

      notebook.signal_connect('switch-page') do |widget, page, page_num|
        if page_num==0
          toolbar.hide
          toolbar2.hide
          hbox.show
        else
          child = notebook.get_nth_page(page_num)
          if (child.is_a? Gtk::ScrolledWindow) and (child.children[0].is_a? Gtk::TextView)
            toolbar2.hide
            hbox.hide
            toolbar.show
            set_buffers(true)
          else
            toolbar.hide
            hbox.hide
           toolbar2.show
          end
        end
      end

      @vbox = Gtk::VBox.new
      viewport.add(@vbox)

      @statusbar = Gtk::Statusbar.new
      PandoraGUI.set_statusbar_text(statusbar, '')
      statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      panhash_btn = Gtk::Button.new(_('Panhash'))
      panhash_btn.relief = Gtk::RELIEF_NONE
      statusbar.pack_start(panhash_btn, false, false, 0)

      panelbox.pack_start(statusbar, false, false, 0)


      #rbvbox = Gtk::VBox.new

      @support_btn = Gtk::CheckButton.new(_('support'), true)
      #support_btn.signal_connect('toggled') do |widget|
      #  p "support"
      #end
      #rbvbox.pack_start(support_btn, false, false, 0)
      hbox.pack_start(support_btn, false, false, 0)

      trust_box = Gtk::VBox.new

      trust0 = nil
      @vouch_btn = Gtk::CheckButton.new(_('vouch'), true)
      vouch_btn.signal_connect('clicked') do |widget|
        if not widget.destroyed?
          if widget.inconsistent?
            if PandoraCrypto.current_user_or_key(false)
              widget.inconsistent = false
              widget.active = true
              trust0 = 0.4
            end
          end
          trust_scale.sensitive = widget.active?
          if widget.active?
            trust0 ||= 0.4
            trust_scale.value = trust0
          else
            trust0 = trust_scale.value
          end
        end
      end
      trust_box.pack_start(vouch_btn, false, false, 0)

      #@scale_button = Gtk::ScaleButton.new(Gtk::IconSize::BUTTON)
      #@scale_button.set_icons(['gtk-goto-bottom', 'gtk-goto-top', 'gtk-execute'])
      #@scale_button.signal_connect('value-changed') { |widget, value| puts "value changed: #{value}" }

      tips = [_('villian'), _('destroyer'), _('dirty'), _('harmful'), _('bad'), _('vain'), \
        _('trying'), _('useful'), _('constructive'), _('creative'), _('genius')]

      #@trust ||= (127*0.4).round
      #val = trust/127.0
      adjustment = Gtk::Adjustment.new(0, -1.0, 1.0, 0.1, 0.3, 0)
      @trust_scale = Gtk::HScale.new(adjustment)
      trust_scale.set_size_request(140, -1)
      trust_scale.update_policy = Gtk::UPDATE_DELAYED
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
        widget.modify_fg(Gtk::STATE_NORMAL, color)
        @vouch_btn.modify_bg(Gtk::STATE_ACTIVE, color)
        i = ((trust+127)/step).round
        tip = tips[i]
        widget.tooltip_text = tip
      end
      #scale.signal_connect('change-value') do |widget|
      #  true
      #end
      trust_box.pack_start(trust_scale, false, false, 0)

      hbox.pack_start(trust_box, false, false, 0)

      public_box = Gtk::VBox.new

      @public_btn = Gtk::CheckButton.new(_('public'), true)
      public_btn.signal_connect('clicked') do |widget|
        if not widget.destroyed?
          if widget.inconsistent?
            if PandoraCrypto.current_user_or_key(false)
              widget.inconsistent = false
              widget.active = true
            end
          end
        end
      end
      public_box.pack_start(public_btn, false, false, 0)

      #@lang_entry = Gtk::ComboBoxEntry.new(true)
      #lang_entry.set_size_request(60, 15)
      #lang_entry.append_text('0')
      #lang_entry.append_text('1')
      #lang_entry.append_text('5')

      @lang_entry = Gtk::Combo.new
      @lang_entry.set_popdown_strings(['0','1','5'])
      @lang_entry.entry.text = ''
      @lang_entry.entry.select_region(0, -1)
      @lang_entry.set_size_request(50, -1)
      public_box.pack_start(lang_entry, true, true, 5)

      hbox.pack_start(public_box, false, false, 0)

      #hbox.pack_start(rbvbox, false, false, 1.0)
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
        atype = field[FI_Type]
        if atype=='Text'
          image = Gtk::Image.new(Gtk::Stock::DND, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          textview = Gtk::TextView.new
          textview.wrap_mode = Gtk::TextTag::WRAP_WORD

          textview.signal_connect('key-press-event') do |widget, event|
            if [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
              and event.state.control_mask?
            then
              true
            end
          end

          textsw = Gtk::ScrolledWindow.new(nil, nil)
          textsw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
          textsw.add(textview)

          label_box = TabLabelBox.new(image, atext, nil, false, 0)
          page = notebook.append_page(textsw, label_box)

          textview.buffer.text = field[FI_Value].to_s
          field[FI_Widget] = textview

          txt_fld = field
          txt_fld << page
          @text_fields << txt_fld  #15??
          #@enter_like_ok = false

          @fields.delete_at(i)
        end
      end

      image = Gtk::Image.new(Gtk::Stock::INDEX, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Relations'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGUI.show_panobject_list(PandoraModel::Relation, nil, sw)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_AUTHENTICATION, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Signs'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGUI.show_panobject_list(PandoraModel::Sign, nil, sw)

      image = Gtk::Image.new(Gtk::Stock::DIALOG_INFO, Gtk::IconSize::MENU)
      image.set_padding(2, 0)
      label_box2 = TabLabelBox.new(image, _('Opinions'), nil, false, 0)
      sw = Gtk::ScrolledWindow.new(nil, nil)
      page = notebook.append_page(sw, label_box2)

      PandoraGUI.show_panobject_list(PandoraModel::Opinion, nil, sw)

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
      @middle_char_width = texts_width.to_f / texts_chars

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
        #p 'field='+field.inspect
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
            when 'Blob'
              def_size = 128
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
        entry.text = field[FI_Value].to_s
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
        window_width, window_height = mw+36, mh+@btn_panel_height+115
      end
      window.set_default_size(window_width, window_height)

      @window_width, @window_height = 0, 0
      @old_field_matrix = []
    end

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

    def calc_row_size(row)
      rw, rh = [0, 0]
      row.each do |fld|
        fs = calc_field_size(fld)
        rw, rh = rw+fs[0], [rh, fs[1]].max
      end
      [rw, rh]
    end

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


  $update_interval = 30
  $download_thread = nil

  UPD_FileList = ['model/01-base.xml', 'model/02-forms.xml', 'pandora.sh', 'pandora.bat']
  UPD_FileList.concat(['model/03-language-'+$lang+'.xml', 'lang/'+$lang+'.txt']) if ($lang and ($lang != 'en'))

  # Check updated files and download them
  # RU: Проверить обновления и скачать их
  def self.start_updating(all_step=true)

    def self.update_file(http, path, pfn)
      res = false
      begin
        #p [path, pfn]
        response = http.request_get(path)
        File.open(pfn, 'wb+') do |file|
          file.write(response.body)
          res = true
          log_message(LM_Info, _('File is updated')+': '+pfn)
        end
      rescue => err
        puts 'Update error: '+err.message
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
        sleep($update_interval) if not Thread.current[:all_step]

        $window.set_status_field(SF_Update, 'Checking')
        main_script = File.join($pandora_root_dir, 'pandora.rb')
        curr_size = File.size?(main_script)
        if curr_size
          arch_name = File.join($pandora_root_dir, 'master.zip')
          main_uri = URI('https://raw.github.com/Novator/Pandora/master/pandora.rb')
          #arch_uri = URI('https://codeload.github.com/Novator/Pandora/zip/master')

          time = 0
          http = nil
          if File.stat(main_script).writable?
            begin
              #p '-----------'
              #p [main_uri.host, main_uri.port, main_uri.path]
              http = Net::HTTP.new(main_uri.host, main_uri.port)
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
              http.open_timeout = 60*5
              response = http.request_head(main_uri.path)
              PandoraUtils.set_param('last_check', Time.now)
              if (response.content_length == curr_size)
                http = nil
                $window.set_status_field(SF_Update, 'Updated', true)
                PandoraUtils.set_param('last_update', Time.now)
              else
                time = Time.now.to_i
              end
            rescue => err
              http = nil
              $window.set_status_field(SF_Update, 'Connection error')
              log_message(LM_Warning, _('Cannot connect to GitHub to check update'))
              puts err.message
            end
          else
            $window.set_status_field(SF_Update, 'Read only')
          end
          if http
            $window.set_status_field(SF_Update, 'Need update')
            Thread.stop

            if Time.now.to_i >= time + 60*5
              begin
                http = Net::HTTP.new(main_uri.host, main_uri.port)
                http.use_ssl = true
                http.verify_mode = OpenSSL::SSL::VERIFY_NONE
                http.open_timeout = 60*5
              rescue => err
                http = nil
                $window.set_status_field(SF_Update, 'Connection error')
                log_message(LM_Warning, _('Cannot connect to GitHub to update'))
                puts err.message
              end
            end

            if http
              $window.set_status_field(SF_Update, 'Updating')
              downloaded = update_file(http, main_uri.path, main_script)
              UPD_FileList.each do |fn|
                pfn = File.join($pandora_root_dir, fn)
                if File.exist?(pfn) and File.stat(pfn).writable?
                  downloaded = downloaded and update_file(http, '/Novator/Pandora/master/'+fn, pfn)
                else
                  downloaded = false
                  log_message(LM_Warning, _('Not exist or read only')+': '+pfn)
                end
              end
              if downloaded
                PandoraUtils.set_param('last_update', Time.now)
                $window.set_status_field(SF_Update, 'Need reboot')
                Thread.stop
                $window.destroy
              else
                $window.set_status_field(SF_Update, 'Updating error')
              end
            end
          end
        end
        $download_thread = nil
      end
    end
  end

  # View and edit record dialog
  # RU: Окно просмотра и правки записи
  def self.act_panobject(tree_view, action)

    def self.get_panobject_icon(panobj)
      panobj_icon = nil
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
      panobj_icon
    end

    path = nil
    if tree_view.destroyed?
      new_act = false
    else
      path, column = tree_view.cursor
      new_act = action == 'Create'
    end
    if path or new_act
      panobject = tree_view.panobject
      store = tree_view.model
      iter = nil
      sel = nil
      id = nil
      panhash0 = nil
      lang = 5
      panstate = 0
      created0 = nil
      creator0 = nil
      if path and (not new_act)
        iter = store.get_iter(path)
        id = iter[0]
        sel = panobject.select('id='+id.to_s, true)
        #p 'panobject.namesvalues='+panobject.namesvalues.inspect
        #p 'panobject.matter_fields='+panobject.matter_fields.inspect
        panhash0 = panobject.namesvalues['panhash']
        lang = panhash0[1].ord if panhash0 and panhash0.size>1
        lang ||= 0
        #panhash0 = panobject.panhash(sel[0], lang)
        panstate = panobject.namesvalues['panstate']
        panstate ||= 0
        if (panobject.is_a? PandoraModel::Created)
          created0 = panobject.namesvalues['created']
          creator0 = panobject.namesvalues['creator']
          #p 'created0, creator0='+[created0, creator0].inspect
        end
      end
      #p sel

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
            pt = tree_view.sel.size-1 if pt>tree_view.sel.size-1
            tree_view.set_cursor(Gtk::TreePath.new(pt), column, false)
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
          type = field[FI_Type]
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

          val, color = PandoraUtils.val_to_view(val, type, view, true)
          field[FI_Value] = val
          field[FI_Color] = color
        end

        dialog = FieldsDialog.new(panobject, formfields, panobject.sname)
        dialog.icon = panobjecticon if panobjecticon

        if edit
          pub_exist = PandoraModel.act_relation(nil, panhash0, RK_MaxPublic, :check)
          #count, rate, querist_rate = rate_of_panobj(panhash0)
          trust = nil
          res = PandoraCrypto.trust_of_panobject(panhash0)
          trust = res if res.is_a? Float
          dialog.vouch_btn.active = (res != nil)
          dialog.vouch_btn.inconsistent = (res.is_a? Integer)
          dialog.trust_scale.sensitive = (trust != nil)
          #dialog.trust_scale.signal_emit('value-changed')
          trust ||= 0.0
          dialog.trust_scale.value = trust

          dialog.support_btn.active = (PandoraModel::PSF_Support & panstate)>0
          dialog.public_btn.active = pub_exist
          dialog.public_btn.inconsistent = (pub_exist==nil)

          dialog.lang_entry.entry.text = lang.to_s if lang

          #dialog.lang_entry.active_text = lang.to_s
          #trust_lab = dialog.trust_btn.children[0]
          #trust_lab.modify_fg(Gtk::STATE_NORMAL, Gdk::Color.parse('#777777')) if signed == 1
        else
          key = PandoraCrypto.current_key(false, false)
          not_key_inited = (not (key and key[PandoraCrypto::KV_Obj]))
          dialog.support_btn.active = true
          dialog.vouch_btn.active = true
          if not_key_inited
            dialog.vouch_btn.inconsistent = true
            dialog.trust_scale.sensitive = false
          end
          dialog.public_btn.inconsistent = not_key_inited
        end

        st_text = panobject.panhash_formula
        st_text = st_text + ' [#'+panobject.panhash(sel[0], lang, true, true)+']' if sel and sel.size>0
        PandoraGUI.set_statusbar_text(dialog.statusbar, st_text)

        if panobject.class==PandoraModel::Key
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

        dialog.run do
          # take value from form
          dialog.fields.each do |field|
            entry = field[FI_Widget]
            field[FI_Value] = entry.text
          end
          dialog.text_fields.each do |field|
            textview = field[FI_Widget]
            field[FI_Value] = textview.buffer.text
          end

          # fill hash of values
          flds_hash = {}
          dialog.fields.each do |field|
            type = field[FI_Type]
            view = field[FI_View]
            val = field[FI_Value]

            if (panobject.ider=='Parameter') and (field[FI_Id]=='value')
              type = panobject.field_val('type', sel[0])
              setting = panobject.field_val('setting', sel[0])
              ps = PandoraUtils.decode_param_setting(setting)
              view = ps['view']
              view ||= PandoraUtils.pantype_to_view(type)
            end

            val = PandoraUtils.view_to_val(val, type, view)
            flds_hash[field[FI_Id]] = val
          end
          dialog.text_fields.each do |field|
            flds_hash[field[FI_Id]] = field[FI_Value]
          end
          lg = nil
          begin
            lg = dialog.lang_entry.entry.text
            lg = lg.to_i if (lg != '')
          rescue
          end
          lang = lg if lg
          lang = 5 if (not lang.is_a? Integer) or (lang<0) or (lang>255)

          time_now = Time.now.to_i
          if (panobject.is_a? PandoraModel::Created)
            flds_hash['created'] = created0 if created0
            if not edit
              flds_hash['created'] = time_now
              creator = PandoraCrypto.current_user_or_key(true)
              flds_hash['creator'] = creator
            end
          end
          flds_hash['modified'] = time_now
          panstate = 0
          panstate = panstate | PandoraModel::PSF_Support if dialog.support_btn.active?
          flds_hash['panstate'] = panstate
          if (panobject.is_a? PandoraModel::Key)
            lang = flds_hash['rights'].to_i
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
                tree_view.sel[ind] = sel[0]
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

              if not dialog.public_btn.inconsistent?
                #p 'panhash,panhash0='+[panhash, panhash0].inspect
                PandoraModel.act_relation(nil, panhash0, RK_MaxPublic, :delete, true, true) if panhash != panhash0
                if dialog.public_btn.active?
                  PandoraModel.act_relation(nil, panhash, RK_MaxPublic, :create, true, true)
                else
                  PandoraModel.act_relation(nil, panhash, RK_MaxPublic, :delete, true, true)
                end
              end
            end
          end
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
          $window.notebook.remove_page($window.notebook.children.index(child))
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


  $media_buf_size = 50
  $send_media_queues = []
  $send_media_rooms = {}

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

  $hide_on_minimize = true

  def self.get_view_params
    $hide_on_minimize = PandoraUtils.get_param('hide_on_minimize')
  end

  def self.get_main_params
    get_view_params
  end

  CSI_Persons = 0
  CSI_Keys    = 1
  CSI_Nodes   = 2
  CSI_PersonRecs = 3

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

  # Extend lists of persons, nodes and keys by relations
  # RU: Расширить списки персон, узлов и ключей пройдясь по связям
  def self.extend_targets_by_relations(targets)
    added = 0
    # need to copmose by relations
    added
  end

  # Start a thread which is searching additional nodes and keys
  # RU: Запуск потока, которые ищет дополнительные узлы и ключи
  def self.start_extending_targets_by_hunt(targets)
    started = true
    # heen hunt with poll of nodes
    started
  end

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

  def self.find_active_sender(not_this=nil)
    res = nil
    $window.notebook.children.each do |child|
      if (child != not_this) and (child.is_a? DialogScrollWin) and child.vid_button.active?
        return child
      end
    end
    res
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

  $you_color = 'blue'
  $dude_color = 'red'
  $tab_color = 'blue'
  $read_time = 1.5
  $last_page = nil

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

    def set_expose_event(value)
      signal_handler_disconnect(@expose_event) if @expose_event
      @expose_event = value
    end
  end

  # Talk dialog
  # RU: Диалог разговора
  class DialogScrollWin < Gtk::ScrolledWindow
    attr_accessor :room_id, :targets, :online_button, :snd_button, :vid_button, :talkview, \
      :editbox, :area_send, :area_recv, :recv_media_pipeline, :appsrcs, :session, :ximagesink, \
      :read_thread, :recv_media_queue, :has_unread

    include PandoraGUI

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

      hbox = Gtk::HBox.new

      bbox = Gtk::HBox.new
      bbox.border_width = 5
      bbox.spacing = 5

      @online_button = GoodCheckButton.new(_('Online'), true)
      online_button.good_signal_clicked do |widget|
        if widget.active?
          widget.good_set_active(false)
          targets[CSI_Nodes].each do |keybase|
            $window.pool.init_session(nil, keybase, 0, self)
          end
        else
          targets[CSI_Nodes].each do |keybase|
            $window.pool.stop_session(nil, keybase)
          end
        end
      end
      online_button.good_set_active(known_node != nil)

      bbox.pack_start(online_button, false, false, 0)

      @snd_button = GoodCheckButton.new(_('Sound'), true)
      snd_button.good_signal_clicked do |widget|
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

      @vid_button = GoodCheckButton.new(_('Video'), true)
      vid_button.good_signal_clicked do |widget|
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

      @talkview = Gtk::TextView.new
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
            #sended = false
            #node_list.each do |node|
            sended = add_and_send_mes(mes)
            if sended
              t = Time.now
              talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
              talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', 'you')
              mykey = PandoraCrypto.current_key(false, false)
              myname = PandoraCrypto.short_name_of_person(mykey)
              talkview.buffer.insert(talkview.buffer.end_iter, myname+':', 'you_bold')
              talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)
              talkview.parent.vadjustment.value = talkview.parent.vadjustment.upper
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

      PandoraGUI.hack_enter_bug(editbox)

      hpaned2 = Gtk::HPaned.new
      @area_send = ViewDrawingArea.new
      area_send.set_size_request(120, 90)
      area_send.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
      hpaned2.pack1(area_send, false, true)
      hpaned2.pack2(editbox, true, true)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)
      #list_sw.visible = false

      list_store = Gtk::ListStore.new(TrueClass, String)
      #node_list.each do |node|
      #  user_iter = list_store.append
      #  user_iter[CL_Name] = node.inspect
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

        targets[CSI_Nodes].each do |keybase|
        #node_list.each do |node|
          $window.pool.stop_session(nil, keybase)
        end
      end

      page = $window.notebook.append_page(self, label_box)

      self.signal_connect('delete-event') do |*args|
        #init_video_sender(false)
        #init_video_receiver(false, false)
        area_send.destroy if not area_send.destroyed?
        area_recv.destroy if not area_recv.destroyed?
      end
      $window.construct_room_title(self)

      show_all

      $window.notebook.page = $window.notebook.n_pages-1 if not known_node
      editbox.grab_focus
    end

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

    def set_session(session, online=true)
      @sessions ||= []
      if online
        @sessions << session if (not @sessions.include?(session))
      else
        @sessions.delete(session)
      end
      active = (@sessions.size>0)
      online_button.good_set_active(active) if (not online_button.destroyed?)
      if not active
        snd_button.good_set_active(false) if (not snd_button.destroyed?)
        vid_button.good_set_active(false) if (not vid_button.destroyed?)
      end
    end

    # Send message to node
    # RU: Отправляет сообщение на узел
    def add_and_send_mes(text)
      res = false
      creator = PandoraCrypto.current_user_or_key(true)
      if creator
        online_button.active = true
        #Thread.pass
        time_now = Time.now.to_i
        state = 0
        targets[CSI_Persons].each do |panhash|
          p 'ADD_MESS panhash='+panhash.inspect
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
                    v = Gst::Caps.parse(v)
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

    def add_elem_to_pipe(str, pipeline, prev_elem=nil, prev_pad=nil, name_suff=nil)
      elements = parse_gst_string(str)
      elem, pad = append_elems_to_pipe(elements, pipeline, prev_elem, prev_pad, name_suff)
      [elem, pad]
    end

    def link_sink_to_area(sink, area, pipeline=nil)
      def set_xid(area, sink)
        if (not area.destroyed?) and area.window and sink and (sink.class.method_defined? 'set_xwindow_id')
          win_id = nil
          if os_family=='windows'
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

    def init_video_sender(start=true, just_upd_area=false)
      video_pipeline = $send_media_pipelines['video']
      if not start
        if $webcam_xvimagesink and ($webcam_xvimagesink.get_state == Gst::STATE_PLAYING)
          $webcam_xvimagesink.pause
        end
        if just_upd_area
          area_send.set_expose_event(nil)
          tsw = PandoraGUI.find_active_sender(self)
          if $webcam_xvimagesink and (not $webcam_xvimagesink.destroyed?) and tsw \
          and tsw.area_send and tsw.area_send.window
            link_sink_to_area($webcam_xvimagesink, tsw.area_send)
            #$webcam_xvimagesink.xwindow_id = tsw.area_send.window.xid
          end
          #p '--LEAVE'
          area_send.queue_draw if area_send and (not area_send.destroyed?)
        else
          #$webcam_xvimagesink.xwindow_id = 0
          count = PandoraGUI.nil_send_ptrind_by_room(room_id)
          if video_pipeline and (count==0) and (video_pipeline.get_state != Gst::STATE_NULL)
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
            winos = (os_family == 'windows')
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

            if winos
              video_src = PandoraUtils.get_param('video_src_win')
              video_src ||= 'dshowvideosrc'
              video_view1 = PandoraUtils.get_param('video_view1_win')
              video_view1 ||= 'queue ! directdrawsink'
            end

            $webcam_xvimagesink = nil
            webcam, pad = add_elem_to_pipe(video_src, video_pipeline)
            if webcam
              capsfilter, pad = add_elem_to_pipe(video_send_caps, video_pipeline, webcam, pad)
              tee, teepad = add_elem_to_pipe(video_send_tee, video_pipeline, capsfilter, pad)
              encoder, pad = add_elem_to_pipe(video_can_encoder, video_pipeline, tee, teepad)
              if encoder
                appsink, pad = add_elem_to_pipe(video_can_sink, video_pipeline, encoder, pad)
                $webcam_xvimagesink, pad = add_elem_to_pipe(video_view1, video_pipeline, tee, teepad)
              end
            end

            if $webcam_xvimagesink
              $send_media_pipelines['video'] = video_pipeline
              $send_media_queues[1] ||= PandoraUtils::RoundQueue.new(true)
              appsink.signal_connect('new-buffer') do |appsink|
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
            log_message(LM_Warning, _(mes))
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
            video_pipeline.stop if (video_pipeline.get_state != Gst::STATE_NULL)
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
            video_pipeline.play if (video_pipeline.get_state != Gst::STATE_PLAYING)
          else
            ptrind = PandoraGUI.set_send_ptrind_by_room(room_id)
            count = PandoraGUI.nil_send_ptrind_by_room(nil)
            if count>0
              #Gtk.main_iteration
              video_pipeline.play if (video_pipeline.get_state != Gst::STATE_PLAYING)
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

    def init_video_receiver(start=true, can_play=true, init=true)
      if not start
        if ximagesink and (ximagesink.get_state == Gst::STATE_PLAYING)
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
            winos = (os_family == 'windows')
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
            log_message(LM_Warning, _(mes))
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
          if (recv_media_pipeline[1].get_state != Gst::STATE_PLAYING) or (ximagesink.get_state != Gst::STATE_PLAYING)
            #p 'PLAYYYYYYYYYYYYYYYYYY!!!!!!!!!! '
            #ximagesink.stop
            #recv_media_pipeline[1].stop
            ximagesink.play
            recv_media_pipeline[1].play
          end
        end
      end
    end

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

    def init_audio_sender(start=true, just_upd_area=false)
      audio_pipeline = $send_media_pipelines['audio']
      #p 'init_audio_sender pipe='+audio_pipeline.inspect+'  btn='+snd_button.active?.inspect
      if not start
        #count = PandoraGUI.nil_send_ptrind_by_room(room_id)
        #if audio_pipeline and (count==0) and (audio_pipeline.get_state != Gst::STATE_NULL)
        if audio_pipeline and (audio_pipeline.get_state != Gst::STATE_NULL)
          audio_pipeline.stop
        end
      elsif (not self.destroyed?) and (not snd_button.destroyed?) and snd_button.active?
        if not audio_pipeline
          begin
            Gst.init
            winos = (os_family == 'windows')
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
            log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
        end

        if audio_pipeline
          ptrind = PandoraGUI.set_send_ptrind_by_room(room_id)
          count = PandoraGUI.nil_send_ptrind_by_room(nil)
          #p 'AAAAAAAAAAAAAAAAAAA count='+count.to_s
          if (count>0) and (audio_pipeline.get_state != Gst::STATE_PLAYING)
          #if (audio_pipeline.get_state != Gst::STATE_PLAYING)
            audio_pipeline.play
          end
        end
      end
      audio_pipeline
    end

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

    def init_audio_receiver(start=true, can_play=true, init=true)
      if not start
        if recv_media_pipeline[0] and (recv_media_pipeline[0].get_state != Gst::STATE_NULL)
          recv_media_pipeline[0].stop
        end
      elsif (not self.destroyed?)
        if (not recv_media_pipeline[0]) and init
          begin
            Gst.init
            winos = (os_family == 'windows')
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
            log_message(LM_Warning, _(mes))
            puts mes+': '+err.message
            snd_button.active = false
          end
          recv_media_pipeline[0].stop if recv_media_pipeline[0]  #this is a hack, else doesn't work!
        end
        if recv_media_pipeline[0] and can_play
          recv_media_pipeline[0].play if (recv_media_pipeline[0].get_state != Gst::STATE_PLAYING)
        end
      end
    end
  end  #--class DialogScrollWin

  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(panhashes, known_node=nil)
    sw = nil
    p 'show_talk_dialog: [panhashes, known_node]='+[panhashes, known_node].inspect
    targets = [[], [], []]
    persons, keys, nodes = targets
    if known_node and (panhashes.is_a? String)
      persons << panhashes
      nodes << known_node
    else
      extract_targets_from_panhash(targets, panhashes)
    end
    if nodes.size==0
      extend_targets_by_relations(targets)
    end
    if nodes.size==0
      start_extending_targets_by_hunt(targets)
    end
    targets.each do |list|
      list.sort!
    end
    persons.uniq!
    persons.compact!
    keys.uniq!
    keys.compact!
    nodes.uniq!
    nodes.compact!
    p 'targets='+targets.inspect

    if (persons.size>0) and (nodes.size>0)
      room_id = construct_room_id(persons)
      if known_node
        creator = PandoraCrypto.current_user_or_key(true)
        if (persons.size==1) and (persons[0]==creator)
          room_id[-1] = (room_id[-1].ord ^ 1).chr
        end
      end
      p 'room_id='+room_id.inspect
      $window.notebook.children.each do |child|
        if (child.is_a? DialogScrollWin) and (child.room_id==room_id)
          child.targets = targets
          child.online_button.good_set_active(known_node != nil)
          $window.notebook.page = $window.notebook.children.index(child) if (not known_node)
          sw = child
          break
        end
      end
      if not sw
        sw = DialogScrollWin.new(known_node, room_id, targets)
      end
    elsif (not known_node)
      mes = _('node') if nodes.size == 0
      mes = _('person') if persons.size == 0
      dialog = Gtk::MessageDialog.new($window, \
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
        Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
        mes = _('No one')+' '+mes+' '+_('is not found')+".\n"+_('Add nodes and do hunt'))
      dialog.title = _('Note')
      dialog.default_response = Gtk::Dialog::RESPONSE_OK
      dialog.icon = $window.icon
      if (dialog.run == Gtk::Dialog::RESPONSE_OK)
        PandoraGUI.show_panobject_list(PandoraModel::Node, nil, nil, true)
      end
      dialog.destroy
    end
    sw
  end

  # Search panel
  # RU: Панель поиска
  class SearchScrollWin < Gtk::ScrolledWindow
    attr_accessor :text

    include PandoraGUI

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(text=nil)
      super(nil, nil)

      @text = nil

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      vpaned = Gtk::VPaned.new

      hbox = Gtk::HBox.new

      search_entry = Gtk::Entry.new
      search_btn = Gtk::Button.new(_('Search'))

      hbox.pack_start(search_entry, true, true, 0)
      hbox.pack_start(search_btn, false, false, 1)

      list_sw = Gtk::ScrolledWindow.new(nil, nil)
      list_sw.shadow_type = Gtk::SHADOW_ETCHED_IN
      list_sw.set_policy(Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC)

      list_store = Gtk::ListStore.new(Integer, String)

      search_btn.signal_connect('clicked') do |*args|
        user_iter = list_store.append
        user_iter[0] = 1
        user_iter[1] = '<result>'
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
      column = Gtk::TreeViewColumn.new(_('Record'), renderer, 'text' => 1)
      column.set_sort_column_id(1)
      list_tree.append_column(column)

      list_tree.signal_connect('row_activated') do |tree_view, path, column|
        # download and go to record
      end

      list_sw.add(list_tree)

      vpaned.pack1(hbox, false, true)
      vpaned.pack2(list_sw, true, true)
      list_sw.show_all

      self.add_with_viewport(vpaned)
      #self.add(hpaned)

      search_entry.grab_focus
    end
  end

  # Showing search panel
  # RU: Показать панель поиска
  def self.show_search_panel(text=nil)
    sw = SearchScrollWin.new(text)

    image = Gtk::Image.new(Gtk::Stock::FIND, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Search'), sw, false, 0) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end


  # Profile panel
  # RU: Панель профиля
  class ProfileScrollWin < Gtk::ScrolledWindow
    attr_accessor :person

    include PandoraGUI

    # Show conversation dialog
    # RU: Показать диалог общения
    def initialize(person=nil)
      super(nil, nil)

      @person = nil

      set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      border_width = 0

      #self.add_with_viewport(vpaned)
    end
  end

  # Show profile panel
  # RU: Показать панель профиля
  def self.show_profile_panel(person=nil)
    sw = ProfileScrollWin.new(person)

    image = Gtk::Image.new(Gtk::Stock::HOME, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    label_box = TabLabelBox.new(image, _('Profile'), sw, false, 0) do
      #store.clear
      #treeview.destroy
      #sw.destroy
    end

    page = $window.notebook.append_page(sw, label_box)
    sw.show_all
    $window.notebook.page = $window.notebook.n_pages-1
  end

  class PandoraStatusIcon < Gtk::StatusIcon
    attr_accessor :main_icon

    def initialize(a_update_win_icon=false, a_flash_interval=0)
      super()

      @main_icon = nil
      if $window.icon
        @main_icon = $window.icon
      else
        @main_icon = $window.render_icon(Gtk::Stock::HOME, Gtk::IconSize::LARGE_TOOLBAR)
      end

      begin
        @message_icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'message.ico'))
      rescue Exception
      end
      if not @message_icon
        @message_icon = $window.render_icon(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::LARGE_TOOLBAR)
      end

      @update_win_icon = a_update_win_icon
      @flash_interval = (a_flash_interval.to_f*1000).round
      @flash_on_mes = (@flash_interval>0)

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
        p 'widget, button, activate_time='+[widget, button, activate_time].inspect
        menu = Gtk::Menu.new
        checkmenuitem = Gtk::CheckMenuItem.new('Blink')
        checkmenuitem.signal_connect('activate') do |w|
          if @message
            set_message
          else
            set_message('Иван Петров, сообщение')
          end
        end
        menu.append(checkmenuitem)

        menuitem = Gtk::MenuItem.new(_('_Quit'))
        menuitem.signal_connect('activate') do
          widget.set_visible(false)
          $window.destroy
        end
        menu.append(menuitem)
        menu.show_all
        menu.popup(nil, nil, button, activate_time)
      end
    end

    def set_message(message=nil)
      if (message.is_a? String) and (message.size>0)
        @message = message
        set_tooltip(message)
        set_flash(true) if @flash_on_mes
      else
        @message = nil
        set_tooltip($window.title)
        set_flash(false)
      end
      update_icon
    end

    def set_flash(flash=true)
      @flash = flash
      if flash and (not @timer)
        @flash_status = 1
        update_icon
        timeout_func
      end
    end

    def update_icon
      if @message and ((not @flash) or (@flash_status==1))
        self.pixbuf = @message_icon
      else
        self.pixbuf = @main_icon
      end
      $window.icon = self.pixbuf if (@update_win_icon and $window.visible?)
    end

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

    def icon_activated
      #$window.skip_taskbar_hint = false
      if $window.visible?
        if $window.has_toplevel_focus?    #.active?
          $window.hide
        else
          $window.present
        end
      else
        $window.deiconify
        $window.show_all
        #$statusicon.visible = false
        $window.present
        update_icon if @update_win_icon
        if @message
          page = $window.notebook.page
          if (page >= 0)
            cur_page = $window.notebook.get_nth_page(page)
            if cur_page.is_a? PandoraGUI::DialogScrollWin
              cur_page.update_state(false, cur_page)
            end
          else
            set_message(nil) if ($window.notebook.n_pages == 0)
          end
        end
      end
    end

  end  #--PandoraStatusIcon

  class CaptchaHPaned < Gtk::HPaned
    attr_accessor :csw

    def initialize(first_child)
      super()
      @first_child = first_child
      self.pack1(@first_child, true, true)
      @csw = nil
    end

    def show_captcha(srckey, captcha_buf=nil, clue_text=nil, node=nil)
      res = nil
      if captcha_buf
        @vbox = Gtk::VBox.new
        vbox = @vbox

        @csw = Gtk::ScrolledWindow.new(nil, nil)
        csw = @csw
        csw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
        #csw.shadow_type = Gtk::SHADOW_NONE
        #csw.border_width = 0
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

        captcha_entry = PandoraGUI::MaskEntry.new
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
        PandoraGUI.hack_enter_bug(captcha_entry)

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
        captcha_entry.grab_focus
        Thread.new do
          sleep(0.3)
          if (not captcha_entry.destroyed?)
            captcha_entry.grab_focus
          end
        end
        res = csw
      else
        #@csw.width_request = @csw.allocation.width
        @csw.destroy
        @csw = nil
        self.position = 0
      end
      res
    end
  end  #--CaptchaHPaned

  class MainWindow < Gtk::Window
    attr_accessor :hunter_count, :listener_count, :fisher_count, :log_view, :notebook, \
      :cvpaned, :pool, :focus_timer, :title_view, :do_on_show

    include PandoraUtils

    def update_conn_status(conn, session_type, diff_count)
      if session_type==0
        @hunter_count += diff_count
      elsif session_type==1
        @listener_count += diff_count
      else
        @fisher_count += diff_count
      end
      set_status_field(SF_Conn, hunter_count.to_s+'/'+listener_count.to_s+'/'+fisher_count.to_s)
    end

    $toggle_buttons = []

    def correct_lis_btn_state
      tool_btn = $toggle_buttons[PandoraGUI::SF_Listen]
      tool_btn.good_set_active($listen_thread != nil) if tool_btn
    end

    def correct_hunt_btn_state
      tool_btn = $toggle_buttons[SF_Hunt]
      tool_btn.good_set_active($hunter_thread != nil) if tool_btn
    end

    $statusbar = nil
    $status_fields = []

    def add_status_field(index, text)
      $statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0) if ($status_fields != [])
      btn = Gtk::Button.new(_(text))
      btn.relief = Gtk::RELIEF_NONE
      if block_given?
        btn.signal_connect('clicked') do |*args|
          yield(*args)
        end
      end
      $statusbar.pack_start(btn, false, false, 0)
      $status_fields[index] = btn
    end

    def set_status_field(index, text, enabled=nil, toggle=nil)
      btn = $status_fields[index]
      if btn
        btn.label = _(text) if $status_fields[index]
        if (enabled != nil)
          btn.sensitive = enabled
        end
        if (toggle != nil) and $toggle_buttons[index]
          $toggle_buttons[index].good_set_active(toggle)
        end
      end
    end

    def get_status_field(index)
      $status_fields[index]
    end

    TV_Name    = 0
    TV_NameF   = 1
    TV_Family  = 2
    TV_NameN   = 3

    MaxTitleLen = 15

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
          $window.destroy
        when 'About'
          PandoraGUI.show_about
        when 'Close'
          if notebook.page >= 0
            page = notebook.get_nth_page(notebook.page)
            tab = notebook.get_tab_label(page)
            close_btn = tab.children[tab.children.size-1].children[0]
            close_btn.clicked
          end
        when 'Create','Edit','Delete','Copy', 'Dialog', 'Clone'
          if (not treeview) and (notebook.page >= 0)
            sw = notebook.get_nth_page(notebook.page)
            treeview = sw.children[0]
          end
          if treeview and (treeview.is_a? SubjTreeView)
            if command=='Clone'
              panobject = treeview.panobject
              panobject.update(nil, nil, nil)
              panobject.class.tab_fields(true)
            else
              PandoraGUI.act_panobject(treeview, command)
            end
          end
        when 'Listen'
          PandoraNet.start_or_stop_listen
        when 'Hunt'
          PandoraNet.hunt_nodes
        when 'Authorize'
          key = PandoraCrypto.current_key(false, false)
          if key and $listen_thread
            PandoraNet.start_or_stop_listen
          end
          key = PandoraCrypto.current_key(true)
        when 'Wizard'
          #p OpenSSL::Cipher::ciphers

          #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
          #cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
          #p 'cipher_hash16='+cipher_hash.to_s(16)
          #type_klen = KT_Rsa | KL_bit2048
          #cipher_key = '123'
          #p keys = generate_key(type_klen, cipher_hash, cipher_key)

          key = PandoraCrypto.current_key(false, true)
          if key
            p data = 'Тестовое сообщение!'
            p cipher_vec = PandoraCrypto.generate_key(PandoraCrypto::KT_Bf)
            p 'coded:'
            p data = PandoraCrypto.recrypt(cipher_vec, data, true)
            p '---'
            cihper = cipher_vec[PandoraCrypto::KV_Key1]
            p cihper.bytesize
            p 'rsa_encode..'
            #p cihper = PandoraCrypto.recrypt(key, cihper, true, false)
            p cihper = PandoraCrypto.recrypt(key, cihper, true, true)
            p 'rsa_decode..'
            #p cihper = PandoraCrypto.recrypt(key, cihper, false, true)
            p cihper = PandoraCrypto.recrypt(key, cihper, false, false)
            cipher_vec[PandoraCrypto::KV_Key1] = cihper
            p '---decoded:'
            puts data = PandoraCrypto.recrypt(cipher_vec, data, false)
          end

          #typ, count = encode_pson_type(PT_Str, 0x1FF)
          #p decode_pson_type(typ)

          #p pson = namehash_to_pson({:first_name=>'Ivan', :last_name=>'Inavov', 'ddd'=>555})
          #p hash = pson_to_namehash(pson)

          #p PandoraUtils.get_param('base_id')
        when 'Profile'
          PandoraGUI.show_profile_panel
        when 'Search'
          PandoraGUI.show_search_panel
        else
          panobj_id = command
          if PandoraModel.const_defined? panobj_id
            panobject_class = PandoraModel.const_get(panobj_id)
            PandoraGUI.show_panobject_list(panobject_class, widget)
          else
            log_message(LM_Warning, _('Menu handler is not defined yet')+' "'+panobj_id+'"')
          end
      end
    end

    # Menu structure
    # RU: Структура меню
    MENU_ITEMS =
      [[nil, nil, '_World'],
      ['Person', Gtk::Stock::ORIENTATION_PORTRAIT, 'People'],
      ['Community', nil, 'Communities'],
      ['-', nil, '-'],
      ['Article', Gtk::Stock::DND, 'Articles'],
      ['Blob', Gtk::Stock::HARDDISK, 'Files'], #Gtk::Stock::FILE
      ['-', nil, '-'],
      ['Country', nil, 'States'],
      ['City', nil, 'Towns'],
      ['Street', nil, 'Streets'],
      ['Thing', nil, 'Things'],
      ['Activity', nil, 'Activities'],
      ['Word', Gtk::Stock::SPELL_CHECK, 'Words'],
      ['Language', nil, 'Languages'],
      ['Address', nil, 'Addresses'],
      ['Contact', nil, 'Contacts'],
      ['-', nil, '-'],
      ['Relation', nil, 'Relations'],
      ['Opinion', nil, 'Opinions'],
      [nil, nil, '_Bussiness'],
      ['Partner', nil, 'Partners'],
      ['Company', nil, 'Companies'],
      ['-', nil, '-'],
      ['Advertisement', nil, 'Advertisements'],
      ['Order', nil, 'Orders'],
      ['Deal', nil, 'Deals'],
      ['Waybill', nil, 'Waybills'],
      ['Debenture', nil, 'Debentures'],
      ['Transfer', nil, 'Transfers'],
      ['-', nil, '-'],
      ['Deposit', nil, 'Deposits'],
      ['Guarantee', nil, 'Guarantees'],
      ['Insurer', nil, 'Insurers'],
      ['-', nil, '-'],
      ['Storage', nil, 'Storages'],
      ['Product', nil, 'Products'],
      ['Service', nil, 'Services'],
      ['Currency', nil, 'Currency'],
      ['Contract', nil, 'Contracts'],
      ['Report', nil, 'Reports'],
      [nil, nil, '_Region'],
      ['Citizen', nil, 'Citizens'],
      ['Union', nil, 'Unions'],
      ['-', nil, '-'],
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
      [nil, nil, '_Pandora'],
      ['Parameter', Gtk::Stock::PREFERENCES, 'Parameters'],
      ['-', nil, '-'],
      ['Key', Gtk::Stock::DIALOG_AUTHENTICATION, 'Keys'],
      ['Sign', nil, 'Signs'],
      ['Node', Gtk::Stock::NETWORK, 'Nodes'],
      ['Message', nil, 'Messages'],
      ['Patch', nil, 'Patches'],
      ['Event', nil, 'Events'],
      ['Fishhook', nil, 'Fishhooks'],
      ['-', nil, '-'],
      ['Authorize', nil, 'Authorize', '<control>I'],
      ['Listen', Gtk::Stock::CONNECT, 'Listen', '<control>L', :check],
      ['Hunt', Gtk::Stock::REFRESH, 'Hunt', '<control>H', :check],
      ['Search', Gtk::Stock::FIND, 'Search'],
      ['-', nil, '-'],
      ['Profile', Gtk::Stock::HOME, 'Profile'],
      ['Wizard', Gtk::Stock::PROPERTIES, 'Wizards'],
      ['-', nil, '-'],
      ['Quit', Gtk::Stock::QUIT, '_Quit', '<control>Q'],
      ['Close', Gtk::Stock::CLOSE, '_Close', '<control>W'],
      ['-', nil, '-'],
      ['About', Gtk::Stock::ABOUT, '_About']
      ]

    def fill_menubar(menubar)
      menu = nil
      MENU_ITEMS.each do |mi|
        if mi[0]==nil or menu==nil
          menuitem = Gtk::MenuItem.new(_(mi[2]))
          menubar.append(menuitem)
          menu = Gtk::Menu.new
          menuitem.set_submenu(menu)
        else
          menuitem = PandoraGUI.create_menu_item(mi)
          menu.append(menuitem)
        end
      end
    end

    def fill_toolbar(toolbar)
      MENU_ITEMS.each do |mi|
        stock = mi[1]
        if stock
          command = mi[0]
          label = mi[2]
          if command and (command != '-') and label and (label != '-')
            toggle = nil
            toggle = false if mi[4]
            btn = PandoraGUI.add_tool_btn(toolbar, stock, label, toggle) do |widget, *args|
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
      fill_toolbar(toolbar)

      @notebook = Gtk::Notebook.new
      notebook.signal_connect('switch-page') do |widget, page, page_num|
        cur_page = notebook.get_nth_page(page_num)
        if $last_page and (cur_page != $last_page) and ($last_page.is_a? PandoraGUI::DialogScrollWin)
          $last_page.init_video_sender(false, true) if not $last_page.area_send.destroyed?
          $last_page.init_video_receiver(false) if not $last_page.area_recv.destroyed?
        end
        if cur_page.is_a? PandoraGUI::DialogScrollWin
          cur_page.update_state(false, cur_page)
          cur_page.init_video_receiver(true, true, false) if not cur_page.area_recv.destroyed?
          cur_page.init_video_sender(true, true) if not cur_page.area_send.destroyed?
        end
        $last_page = cur_page
      end

      @log_view = Gtk::TextView.new
      log_view.can_focus = false
      log_view.has_focus = false
      log_view.receives_default = true
      log_view.border_width = 0

      sw = Gtk::ScrolledWindow.new(nil, nil)
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      sw.shadow_type = Gtk::SHADOW_IN
      sw.add(log_view)
      sw.border_width = 1;
      sw.set_size_request(-1, 40)

      vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      vpaned.pack1(notebook, true, true)
      vpaned.pack2(sw, false, true)

      @cvpaned = CaptchaHPaned.new(vpaned)
      @cvpaned.position = cvpaned.max_position

      $statusbar = Gtk::Statusbar.new
      PandoraGUI.set_statusbar_text($statusbar, _('Base directory: ')+$pandora_base_dir)

      add_status_field(SF_Update, 'Not checked') do
        PandoraGUI.start_updating(true)
      end
      add_status_field(SF_Auth, 'Not logged') do
        do_menu_act('Authorize')
      end
      add_status_field(SF_Listen, 'Not listen') do
        do_menu_act('Listen')
      end
      add_status_field(SF_Hunt, 'No hunt') do
        do_menu_act('Hunt')
      end
      add_status_field(SF_Conn, '0/0/0') do
        do_menu_act('Node')
      end

      vbox = Gtk::VBox.new
      vbox.pack_start(menubar, false, false, 0)
      vbox.pack_start(toolbar, false, false, 0)
      vbox.pack_start(cvpaned, true, true, 0)
      vbox.pack_start($statusbar, false, false, 0)

      $window.add(vbox)

      $window.signal_connect('delete-event') do |*args|
        $window.iconify
        $window.hide
        true
      end

      update_win_icon = PandoraUtils.get_param('status_update_win_icon')
      flash_interval = PandoraUtils.get_param('status_flash_interval')
      $statusicon = PandoraGUI::PandoraStatusIcon.new(update_win_icon, flash_interval)

      $window.signal_connect('destroy') do |window|
        while (not $window.notebook.destroyed?) and ($window.notebook.children.count>0)
          $window.notebook.children[0].destroy if (not $window.notebook.children[0].destroyed?)
        end
        PandoraCrypto.reset_current_key
        $statusicon.visible = false if ($statusicon and (not $statusicon.destroyed?))
        Gtk.main_quit
      end

      $window.signal_connect('key-press-event') do |widget, event|
        if event.keyval == Gdk::Keyval::GDK_F5
          PandoraNet.hunt_nodes
        elsif ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X, 1758, 1790].include?(event.keyval) \
        and event.state.mod1_mask?) or ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q, \
        1738, 1770].include?(event.keyval) and event.state.control_mask?) #q, Q, й, Й
          $window.destroy
        end
        false
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
          if widget.visible? and widget.active? and $hide_on_minimize
            $window.hide
            #$window.skip_taskbar_hint = true
          end
        end
      end

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
        #p 'focus-in-event: ' + $window.has_toplevel_focus?.inspect
        if $window.focus_timer
          $window.focus_timer = nil if ($window.focus_timer == $window)
        else
          $window.focus_timer = GLib::Timeout.add(700) do
            #p 'read timer!!!' + $window.has_toplevel_focus?.inspect
            if $window.has_toplevel_focus? and $window.visible?
              $window.notebook.children.each do |child|
                if (child.is_a? DialogScrollWin) and (child.has_unread)
                  $window.notebook.page = $window.notebook.children.index(child)
                  break
                end
              end
              curpage = $window.notebook.get_nth_page($window.notebook.page)
              if (curpage.is_a? PandoraGUI::DialogScrollWin) and $window.has_toplevel_focus?
                curpage.update_state(false, curpage)
              end
            end
            $window.focus_timer = nil
            false
          end
        end
        false
      end

      $base_id = PandoraUtils.get_param('base_id')
      check_update = PandoraUtils.get_param('check_update')
      if (check_update==1) or (check_update==true)
        last_check = PandoraUtils.get_param('last_check')
        last_update = PandoraUtils.get_param('last_update')
        check_interval = PandoraUtils.get_param('check_interval')
        if not check_interval or (check_interval <= 0)
          check_interval = 2
        end
        update_period = PandoraUtils.get_param('update_period')
        if not update_period or (update_period <= 0)
          update_period = 7
        end
        time_now = Time.now.to_i
        need_check = ((time_now - last_check.to_i) >= check_interval*24*3600)
        if (time_now - last_update.to_i) < update_period*24*3600
          set_status_field(SF_Update, 'Updated', need_check)
        elsif need_check
          PandoraGUI.start_updating(false)
        end
      end
      PandoraGUI.get_main_params

      Gtk.main
    end

  end  #--MainWindow

end

# ====MAIN=======================================================================

# Some module settings
# RU: Некоторые настройки модулей
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# == Running the Pandora!
# == RU: Запуск Пандоры!
#$lang = 'en'
PandoraUtils.load_language($lang)
PandoraModel.load_model_from_xml($lang)
PandoraGUI::MainWindow.new(MAIN_WINDOW_TITLE)

#!/usr/bin/env ruby
# encoding: utf-8

# The Pandora. Free peer-to-peer information system
# RU: Пандора. Свободная пиринговая информационная система
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк
#
# coding: utf-8

if RUBY_VERSION<'1.9'
  $KCODE='u'
else
  Encoding.default_external = 'UTF-8'
  Encoding.default_internal = 'UTF-8'
end

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

# Paths and files  ('join' gets '/' for Linux and '\' for Windows)
# RU: Пути и файлы ('join' дает '/' для Линукса и '\' для Винды)
if os_family != 'windows'
  $pandora_root_dir = Dir.pwd                                       # Current Pandora directory
#  $pandora_root_dir = File.expand_path(File.dirname(__FILE__))     # Script directory
else
  $pandora_root_dir = '.'     # It prevents a bug with cyrillic paths in Win XP
end
$pandora_base_dir = File.join($pandora_root_dir, 'base')            # Default database directory
$pandora_view_dir = File.join($pandora_root_dir, 'view')            # Media files directory
$pandora_model_dir = File.join($pandora_root_dir, 'model')          # Model description directory
$pandora_lang_dir = File.join($pandora_root_dir, 'lang')            # Languages directory
$pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Default database file
$pandora_sqlite_db2 = File.join($pandora_base_dir, 'pandora2.sqlite')  # Default database file

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
begin
  require 'jcode'
  $jcode_on = true
rescue Exception
  $jcode_on = false
end

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

# Default values of variables
# RU: Значения переменных по умолчанию
$host = 'localhost'
$port = 5577
$base_index = 0

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
      Thread.exit
  end
  val = nil
end

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
  if (trans == nil) or (trans.size==0) and (frase != nil) and (frase.size>0)
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

$view = nil

# Log message
# RU: Добавить сообщение в лог
def log_message(level, mes)
  mes = level_to_str(level).to_s+mes
  if $view
    $view.buffer.insert($view.buffer.end_iter, mes+"\n")
  else
    puts mes
  end
end

# ==============================================================================
# == Base module of Pandora
# == RU: Базовый модуль Пандора
module PandoraKernel

  # Load translated phrases
  # RU: Загрузить переводы фраз
  def self.load_language(lang='ru')

    def self.unslash_quotes(str)
      str = '' if str == nil
      str.gsub('\"', '"')
    end

    def self.addline(str, line)
      line = unslash_quotes(line)
      if (str==nil) or (str=='')
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
          line.chop!
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
              if i != nil
                frase = addline(frase, line[0, i])
                line = line[i+4, line.size-i-4]
                scanmode = 2 #composing a trans
              else
                scanmode = 1 #composing a frase
              end
            end
            if scanmode==2
              k = line.rindex('"')
              if (k != nil) and ((k==0) or (line[k-1, 1] != "\\"))
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
        if (value[0].index('"') == nil) and (value[1].index('"') == nil) \
          and (value[0].index("\n") == nil) and (value[1].index("\n") == nil) \
          and not there_are_end_space(value[0]) and not there_are_end_space(value[1])
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
      when 'Integer'
        'INTEGER'
      when 'Float'
        'REAL'
      when 'Number'
        'NUMBER'
      when 'Date'
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

  # Table definitions of SQLite from fields definitions
  # RU: Описание таблицы SQLite из описания полей
  def self.panobj_fld_to_sqlite_tab(panobj_fld)
    res = ''
    panobj_fld.each do |f|
      res = res + ', ' if res != ''
      res = res + f[0].to_s + ' ' + PandoraKernel::ruby_type_to_sqlite_type(f[2], f[3])
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
    def select_table(table_name, afilter='')
    end
  end

  # SQLite adapter
  # RU: Адаптер SQLite
  class SQLiteDbSession < DatabaseSession
    NAME = "Сеанс SQLite"
    attr_accessor :db, :exist
    def connect
      if not connected
        @db = SQLite3::Database.new(conn_param)
        @connected = TRUE
        @exist = {}
      end
      connected
    end
    def create_table(table_name, recreate=false)
      connect
      tfd = db.table_info(table_name)
      #p tfd
      tfd.collect! { |x| x['name'] }
      if (tfd == nil) or (tfd == [])
        @exist[table_name] = FALSE
      else
        @exist[table_name] = TRUE
      end
      tab_def = PandoraKernel::panobj_fld_to_sqlite_tab(def_flds[table_name])
      #p tab_def
      if (! exist[table_name] or recreate) and tab_def != nil
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
      tfd.collect { |x| x['name'] }
    end
    def select_table(table_name, filter='')
      connect
      tfd = fields_table(table_name)
      if (tfd == nil) or (tfd == [])
        @selection = [['<no>'],['<base>']]
      else
        sql_values = []
        if filter.is_a? Hash
          sql2 = ''
          filter.each do |n,v|
            if n != nil
              sql2 = sql2 + ',' if sql2 != ''
              sql2 = sql2 + n.to_s + '=?'
              sql_values << v
            end
          end
          filter = sql2
        end
        sql = 'SELECT * from '+table_name
        if (filter != nil) and (filter > '')
          sql = sql + ' where '+filter
        end
        p 'select  sql='+sql.inspect
        @selection = db.execute(sql, sql_values)
      end
    end
    def update_table(table_name, values, names=nil, filter=nil)
      res = false
      connect
      sql = ''
      sql_values = []
      if (values == nil) and (names == nil) and (filter != nil)
        sql = 'DELETE FROM ' + table_name + ' where '+filter
      elsif values.is_a? Array and names.is_a? Array
        tfd = db.table_info(table_name)
        tfd_name = tfd.collect { |x| x['name'] }
        tfd_type = tfd.collect { |x| x['type'] }
        if filter != nil
          values.each_with_index do |v,i|
            fname = names[i]
            if fname != nil
              sql = sql + ',' if sql != ''
              #val = "'" + v + "'"
              #ind = tfd_name.index(fname)
              #if ind
              #  typ = tfd_type[ind]
              #  if (typ=='TEXT') or (typ[0,7]=='VARCHAR')
              #    val = '?'
              #    values << v
              #  end
              #end
              #sql = sql + ' ' + fldnames[i] + '=' + val
              sql_values << v
              sql = sql + ' ' + fname.to_s + '=?'
            end
          end
          sql = 'UPDATE ' + table_name + ' SET' + sql
          if (filter != nil) and (filter > '')
            sql = sql + ' where '+filter
          end
        else
          sql2 = ''
          values.each_with_index do |v,i|
            fname = names[i]
            if fname != nil
              sql = sql + ',' if sql != ''
              sql2 = sql2 + ',' if sql2 != ''
              sql = sql + fname.to_s
              sql2 = sql2 + '?'
              sql_values << v
            end
          end
          sql = 'INSERT INTO ' + table_name + '(' + sql + ') VALUES(' + sql2 + ')'
        end
      end
      tfd = fields_table(table_name)
      if (tfd != nil) and (tfd != [])
        p 'upd_tab: sql='+sql.inspect
        p 'upd_tab: sql_values='+sql_values.inspect
        res = db.execute(sql, sql_values)
        p 'db.execute  res='+res.inspect
        res = true
      end
      p 'upd_tab: res='+res.inspect
      res
    end
  end

  # Repository manager
  # RU: Менеджер хранилищ
  class RepositoryManager
    @@repo_list = ['http://robux.biz/pandora_repo.xml', 'http://perm.ru/pandora_repo.xml']
    attr_accessor :base_list, :table_list
    def repo_list
      @@repo_list
    end
    def initialize
      super
      @base_list = # динамический список баз
        # rep_id, db_type, conn_param, rep_ptr
        [['robux', 'sqlite3,', $pandora_sqlite_db, nil],
         ['robux', 'sqlite3,', $pandora_sqlite_db2, nil],
         ['robux', 'mysql', ['localhost', 'iron', 'cxziop', 'oscomm'], nil],
         ['perm',  'mysql', ['pandora.perm.ru', 'user', 'pass', 'pandora'], nil]]
      @table_list = # динамический список таблиц - нужен??
        # rep_id, tab_name, tab_def
        [['robux', 'persons', '(id INTEGER PRIMARY KEY AUTOINCREMENT, firstname VARCHAR(50), lastname TEXT, height REAL)'],
         ['robux', 'companies', nil],
         ['robux', 'laws', nil]]
    end
    def get_adapter(panobj, table_ptr, recreate=false)
      #find db_ptr in db_list
      adap = nil
      base_des = base_list[$base_index]
      if base_des[3] == nil
        adap = SQLiteDbSession.new
        adap.conn_param = base_des[2]
        base_des[3] = adap
      else
        adap = base_des[3]
      end
      table_name = table_ptr[1]
      adap.def_flds[table_name] = panobj.def_fields
      if table_name==nil or table_name=='' then
        puts 'No table name for ['+panobj.name+']'
      else
        adap.create_table(table_name, recreate)
        #adap.create_table(table_name, TRUE)
      end
      adap
    end
    def get_tab_select(panobj, table_ptr, filter='')
      adap = get_adapter(panobj, table_ptr)
      adap.select_table(table_ptr[1], filter)
    end
    def get_tab_update(panobj, table_ptr, values, names, filter='')
      res = false
      recreate = ((values == nil) and (names == nil) and (filter == nil))
      adap = get_adapter(panobj, table_ptr, recreate)
      if recreate
        res = adap != nil
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
    elsif (pname==nil) or (pname=='')
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
    res = ''
    if bytes
      bytes.each_byte do |b|
        res << ('%02x' % b)
      end
    end
    res
  end

  # Convert big integer to string of bytes
  # RU: Преобрзует большое целое в строку байт
  def self.bigint_to_bytes(bigint)
    bytes = ''
    if bigint<=0xFF
      bytes = [bigint].pack('C')
    else
      #not_null = true
      #while not_null
      #  bytes = (bigint & 255).chr + bytes
      #  bigint = bigint >> 8
      #  not_null = (bigint>0)
      #end
      hexstr = bigint.to_s(16)
      hexstr = '0'+hexstr if hexstr.size % 2 > 0
      ((hexstr.size+1)/2).times do |i|
        bytes << hexstr[i*2,2].to_i(16).chr
      end
    end
    bytes
  end

  # Convert string of bytes to big integer
  # RU: Преобрзует строку байт в большое целое
  def self.bytes_to_bigint(bytes)
    hexstr = bytes_to_hex(bytes)
    OpenSSL::BN.new(hexstr, 16)
  end

  # Fill string by zeros from left to defined size
  # RU: Заполнить строку нулями слева до нужного размера
  def self.fill_zeros_from_left(data, size)
    if data.size<size
      data = [0].pack('C')*(size-data.size) + data
    end
    data
  end


  # Base Pandora's object
  # RU: Базовый объект Пандоры
  class BasePanobject
    class << self
      @ider = 'Base Panobject'
      @name = 'Базовый объект Пандоры'
      @tables = []
      @def_fields = []
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
      def lang
        @lang
      end
      def lang=(x)
        @lang = x
      end
      def def_fields
        @def_fields
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
      def BasePanobject.repositories
        $repositories
      end
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
    def lang
      self.class.lang
    end
    def lang=(x)
      self.class.lang = x
    end
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
      PandoraKernel.get_name_or_names(name)
    end
    def pname
      PandoraKernel.get_name_or_names(name, true)
    end
    attr_accessor :namesvalues
    def select(afilter='', set_namesvalues=false)
      res = self.class.repositories.get_tab_select(self, self.class.tables[0], afilter)
      if set_namesvalues and res.is_a? Array
        @namesvalues = {}
        tab_fields.each_with_index do |n, i|
          namesvalues[n] = res[0][i]
        end
      end
      res
    end
    def update(values, names=nil, filter='', set_namesvalues=false)
      if values.is_a? Hash
        names = values.keys
        values = values.values
        p '=====1'
        p names
        p '=====2'
        p values
        p '=====3'
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
    def tab_fields
      if @last_tab_fields == nil
        @last_tab_fields = self.class.repositories.get_tab_fields(self, self.class.tables[0])
      end
      @last_tab_fields
    end
    def field_val(fld_name, values)
      res = nil
      if values.is_a? Array
        i = tab_fields.index(fld_name)
        res = values[i] if i != nil
      end
      res
    end
    def field_des(fld_name)
      df = def_fields.detect{ |e| (e.is_a? Array) and (e[0].to_s == fld_name) or (e.to_s == fld_name) }
      df
    end
    def field_title(fld_name)
      df = field_des(fld_name)
      df = df[1] if df.is_a? Array
      df = fld_name if df == nil
      df
    end
    def def_hash(e)
      len = 0
      hash = ''
      if (e.is_a? Array) and (e[2] != nil)
        case e[2].to_s
          when 'Date'
            hash = 'date'
            len = 3
          when 'Byte'
            hash = 'byte'
            len = 1
          when 'Word'
            hash = 'word'
            len = 2
          when 'Integer'
            hash = 'integer'
            len = 4
        end
      end
      [len, hash]
    end
    def panhash_pattern
      res = []
      last_ind = 0
      def_fields.each do |e|
        if (e.is_a? Array) and (e[6] != nil) and (e[6].to_s != '')
          hash = e[6]
          ind = 0
          len = 0
          i = hash.index(':')
          j = hash.index('(')
          i ||= j
          if i
            begin
              ind = hash[0, i].to_i
            rescue
              ind = 0
            end
          end
          j ||=i
          if j
            len = hash[j+1..-1]
            len = len[0..-2] if len[-1]==')'
            len = len.to_i
            if j>i
              hash = hash[i+1, j-i-1]
            else
              hash = ''
            end
          end
          if (hash==nil) or (hash=='') or (len<=0)
            dlen, dhash = def_hash(e)
            hash = dhash if (hash==nil) or (hash=='')
            len = dlen if len<=0
          end
          ind = last_ind + 1 if ind==0
          res << [ind, e[0], hash, len]
          last_ind = ind
        end
      end
      res.sort! { |a,b| a[0]<=>b[0] }
      if res == []
        used_len = 0
        nil_count = 0
        def_fields.each do |e|
          len, hash = def_hash(e)
          res << [e[0], hash, len]
          if len>0
            used_len += len
          else
            nil_count += 1
          end
        end
        mid_len = 0
        mid_len = (20-used_len)/nil_count if nil_count>0
        if mid_len>0
          tail = 20
          res.each_with_index do |e,i|
            if e[2]<=0
              if i==res.size-1
                e[2]=tail
              else
                e[2]=mid_len
              end
            end
            tail -= e[2]
          end
        end
      else
        res.collect! { |e| [e[1],e[2],e[3]] }
      end
      res
    end
    def calc_hash(hfor, hlen, fval)
      res = [0].pack('C')
      #fval = [fval].pack('C*') if fval.is_a? Fixnum
      if (fval != nil) and (fval != '')
        case hfor
          when 'sha1', 'hash', 'panhash', ''
            res = Digest::SHA1.digest(fval)[0, hlen]
          when 'md5'
            res = Digest::MD5.digest(fval)[0, hlen]
          when 'date'
            dmy = fval.split('.')   # D.M.Y
            # convert DMY to time from 1970 in days
            t = Time.mktime(dmy[2].to_i, dmy[1].to_i, dmy[0].to_i).to_i / (24*60*60)
            # convert date to 0 year epoch
            t += 1970*365
            res = [t].pack('N')
            res = res[-hlen..-1]
          when 'byte', 'integer', 'word'
            #p 'fval='+fval.inspect
            res = [fval].pack('C*')
            #p '--res='+res.inspect
            res = res[0, hlen]
            #p '==res='+res.inspect
          else
            p 'Unknown hash function: ['+hfor.to_s+']'
        end
      end
      while res.size<hlen
        res += [0].pack('C')
      end
      #p 'hash='+res.to_s
      #p 'hex_of_str='+hex_of_str(res)
      res
    end
    def objhash
      [kind, lang].pack('CC')
    end
    def panhash(values, prefix=true, hexview=false)
      res = ''
      if prefix
        res = objhash
        res = PandoraKernel.bytes_to_hex(res)+':' if hexview
      end
      panhash_pattern.each_with_index do |pat, ind|
        fname = pat[0]
        hfor  = pat[1]
        hlen  = pat[2]
        fval = field_val(fname, values)
        if not hexview
          res += calc_hash(hfor, hlen, fval)
        else
          res += ' ' if res
          res += PandoraKernel.bytes_to_hex(calc_hash(hfor, hlen, fval))
        end
      end
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
  end

end

# ==============================================================================
# == Pandora logic model
# == RU: Логическая модель Пандора
module PandoraModel

  # Pandora's object
  # RU: Объект Пандоры
  class Panobject < PandoraKernel::BasePanobject
    ider = 'Panobject'
    name = "Объект Пандоры"
  end

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
      xml_doc.elements.each('pandora-model/*/*') do |element|
        panobj_id = element.name
        new_panobj = true
        flds = []
        if PandoraModel.const_defined? panobj_id
          panobject_class = PandoraModel.const_get(panobj_id)
          panobj_name = panobject_class.name
          panobj_tabl = panobject_class.tables
          new_panobj = false
          #p panobject_class
        else
          panobj_name = panobj_id
          parent_class = element.attributes['parent']
          if (parent_class==nil) or (not(PandoraModel.const_defined? parent_class))
            parent_class = 'Panobject'
          else
            PandoraModel.const_get(parent_class).def_fields.each do |f|
              flds << f
            end
          end
          module_eval('class '+panobj_id+' < PandoraModel::'+parent_class+'; name = "'+panobj_name+'"; end')
          panobject_class = PandoraModel.const_get(panobj_id)
          panobject_class.def_fields = flds
          #p panobject_class
          panobject_class.ider = panobj_id
          panobject_class.kind = 0
          panobject_class.lang = 5
          panobj_tabl = panobj_id
          panobj_tabl = PandoraKernel::get_name_or_names(panobj_tabl, true)
          panobj_tabl.downcase!
          panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]]
        end
        panobj_kind = element.attributes['kind']
        panobject_class.kind = panobj_kind.to_i if panobj_kind
        flds = panobject_class.def_fields
        #p flds
        panobj_name_en = element.attributes['name']
        panobj_name = panobj_name_en if (panobj_name==panobj_id) and (panobj_name_en != nil) and (panobj_name_en != '')
        panobj_name_lang = element.attributes['name'+lang]
        panobj_name = panobj_name_lang if (panobj_name_lang != nil) and (panobj_name_lang != '')
        #puts panobj_id+'=['+panobj_name+']'
        panobject_class.name = panobj_name

        panobj_tabl = element.attributes['table']
        panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]] if panobj_tabl != nil

        element.elements.each('*') do |sub_elem|
          seu = sub_elem.name.upcase
          if seu==sub_elem.name
            #p 'Функция не определена: ['+sub_elem.name+']'
          else
            i = 0
            while (i<flds.size) and (flds[i][0] != sub_elem.name) do i+=1 end
            if new_panobj or (i<flds.size)
              if i<flds.size
                fld_name = flds[i][1]
              else
                flds[i] = [sub_elem.name]
                fld_name = sub_elem.name
              end
              fld_name_en = sub_elem.attributes['name']
              fld_name = fld_name_en if (fld_name_en != nil) and (fld_name_en != '')
              fld_name_lang = sub_elem.attributes['name'+lang]
              fld_name = fld_name_lang if (fld_name_lang != nil) and (fld_name_lang != '')
              flds[i][1] = fld_name
              fld_type = sub_elem.attributes['type']
              flds[i][2] = fld_type if (fld_type != nil) and (fld_type != '')
              fld_size = sub_elem.attributes['size']
              flds[i][3] = fld_size if (fld_size != nil) and (fld_size != '')
              fld_pos = sub_elem.attributes['pos']
              flds[i][4] = fld_pos if (fld_pos != nil) and (fld_pos != '')
              fld_fsize = sub_elem.attributes['fsize']
              flds[i][5] = fld_fsize if (fld_fsize != nil) and (fld_fsize != '')
              fld_hash = sub_elem.attributes['hash']
              flds[i][6] = fld_hash if (fld_hash != nil) and (fld_hash != '')
            else
              puts _('Property was not defined, ignored')+' /'+filename+':'+panobj_id+'.'+sub_elem.name
            end
          end
        end
        #p flds
        #p "========"
        panobject_class.def_fields = flds
      end
      file.close
    end
  end

end

# ==============================================================================
# == Graphical user interface of Pandora
# == RU: Графический интерфейс Пандора
module PandoraGUI

  if not $gtk2_on
    puts "Gtk не установлена"
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
    rescue Exception
      gpl_text = _('Full text is in the file')+' LICENSE.TXT.'
    end
    dlg.license = _("Pandora is licensed under GNU GPLv2.\n"+
      "\nFundamentals:\n"+
      "- program code is open, distributed free and without warranty;\n"+
      "- author does not require you money, but demands respect authorship;\n"+
      "- you can change the code, sent to the authors for inclusion in the next release;\n"+
      "- your own release you must distribute with another name and only licensed under GPL;\n"+
      "- if you do not understand the GPL or disagree with it, you have to uninstall the program.\n\n")+gpl_text
    dlg.website = 'http://github.com/Novator/Pandora'
    if os_family=='unix'
      dlg.program_name = dlg.name
      dlg.skip_taskbar_hint = true
    end
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
      :panelbox, :okbutton, :cancelbutton

    def initialize(*args)
      super(*args)
      @response = 0
      @window = self
      @enter_like_tab = false
      @enter_like_ok = true

      window.transient_for = $window
      window.modal = true
      #window.skip_taskbar_hint = true
      window.window_position = Gtk::Window::POS_CENTER
      #window.type_hint = Gdk::Window::TYPE_HINT_DIALOG

      @vpaned = Gtk::VPaned.new
      vpaned.border_width = 2
      window.add(vpaned)

      sw = Gtk::ScrolledWindow.new(nil, nil)
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
      okbutton.signal_connect('clicked') { @response=1 }
      bbox.pack_start(okbutton, false, false, 0)

      @cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
      cancelbutton.width_request = 110
      cancelbutton.signal_connect('clicked') { @response=2 }
      bbox.pack_start(cancelbutton, false, false, 0)

      hbox.pack_start(bbox, true, false, 1.0)

      window.signal_connect("delete-event") {
        @response=2
        false
      }
      window.signal_connect("destroy") { @response=2 }

      window.signal_connect('key_press_event') do |widget, event|
        if (event.hardware_keycode==36) and enter_like_tab  # Enter works like Tab
          event.hardware_keycode=23
          event.keyval=Gdk::Keyval::GDK_Tab
          window.signal_emit('key-press-event', event)
          true
        elsif ((event.hardware_keycode==36) \
          or ([Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval))) \
          and (event.state.control_mask? or (enter_like_ok and (not (self.focus.is_a? Gtk::TextView))))
        then
          #p "=-=-=-"
          #p self.focus
          #p self.focus.is_a? Gtk::TextView
          okbutton.activate
          true
        elsif (event.hardware_keycode==9) or #Esc pressed
          ((event.hardware_keycode==25) and event.state.control_mask?) or #Ctrl+W
          (Gdk::Keyval::GDK_Escape==event.keyval) or
          ([Gdk::Keyval::GDK_w, Gdk::Keyval::GDK_W].include?(event.keyval) and event.state.control_mask?)
        then
          cancelbutton.activate
          false
        elsif ((event.hardware_keycode==24) and event.state.control_mask?) or #Ctrl+Q
          ((event.hardware_keycode==53) and event.state.mod1_mask?) or #Alt+X
          ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q].include?(event.keyval) and event.state.control_mask?) or
          ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X].include?(event.keyval) and event.state.mod1_mask?)
        then
          $window.destroy
          @response=2
          false
        else
          false
        end
      end
    end

    # show dialog until key pressed
    def run
      res = false
      show_all
      while (not destroyed?) and (@response == 0) do
        Gtk.main_iteration
        #sleep 0.03
      end
      if not destroyed?
        if (@response==1)
          yield(@response) if block_given?
          res = true
        end
        destroy
      end
      res
    end
  end

  # Add button to toolbar
  # RU: Добавить кнопку на панель инструментов
  def self.add_tool_btn(toolbar, stock, title)
    image = Gtk::Image.new(stock, Gtk::IconSize::MENU)
    btn = Gtk::ToolButton.new(image, _(title))
    new_api = false
    begin
      btn.tooltip_text = btn.label
      new_api = true
    rescue Exception
    end
    btn.signal_connect('clicked') do
      yield if block_given?
    end

    if new_api
      toolbar.add(btn)
    else
      toolbar.append(btn, btn.label, btn.label)
    end
  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    attr_accessor :panobject, :fields, :text_fields, :toolbar, :toolbar2, :statusbar, \
      :support_btn, :trust_btn, :public_btn

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

      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::BOLD, 'Bold') do
        p "bold"
      end
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::ITALIC, 'Italic')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::STRIKETHROUGH, 'Strike')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::UNDERLINE, 'Underline')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::UNDO, 'Undo')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::REDO, 'Redo')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::COPY, 'Copy')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::CUT, 'Cut')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::FIND, 'Find')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_LEFT, 'Left')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_RIGHT, 'Right')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_CENTER, 'Center')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUSTIFY_FILL, 'Fill')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::SAVE, 'Save')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::OPEN, 'Open')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::JUMP_TO, 'Link')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::HOME, 'Image')
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::OK, 'Ok') { @response=1 }
      PandoraGUI.add_tool_btn(toolbar, Gtk::Stock::CANCEL, 'Cancel') { @response=2 }

      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::ADD, 'Add')
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::DELETE, 'Delete')
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::OK, 'Ok') { @response=1 }
      PandoraGUI.add_tool_btn(toolbar2, Gtk::Stock::CANCEL, 'Cancel') { @response=2 }

      notebook.signal_connect('switch-page') do |widget, page, page_num|
        if page_num==0
          toolbar.hide
          toolbar2.hide
          hbox.show
        elsif notebook.get_nth_page(page_num).is_a? Gtk::TextView
          toolbar2.hide
          hbox.hide
          toolbar.show
        else
          toolbar.hide
          hbox.hide
          toolbar2.show
        end
      end

      @vbox = Gtk::VBox.new
      viewport.add(@vbox)

      @statusbar = Gtk::Statusbar.new
      PandoraGUI.set_statusbar_text(statusbar, '')
      statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
      listen_btn = Gtk::Button.new(_('Panhash'))
      listen_btn.relief = Gtk::RELIEF_NONE
      statusbar.pack_start(listen_btn, false, false, 0)

      panelbox.pack_start(statusbar, false, false, 0)


      #rbvbox = Gtk::VBox.new

      @support_btn = Gtk::CheckButton.new(_('support'), true)
      #support_btn.signal_connect('toggled') do |widget, event|
      #  p "support"
      #end
      #rbvbox.pack_start(support_btn, false, false, 0)
      hbox.pack_start(support_btn, false, false, 0)

      @trust_btn = Gtk::CheckButton.new(_('trust'), true)
      #trust_btn.signal_connect('toggled') do |widget, event|
      #  p "trust"
      #end
      hbox.pack_start(trust_btn, false, false, 0)

      @public_btn = Gtk::CheckButton.new(_('public'), true)
      #public_btn.signal_connect('toggled') do |widget, event|
      #  p "public"
      #end
      hbox.pack_start(public_btn, false, false, 0)

      #hbox.pack_start(rbvbox, false, false, 1.0)
      hbox.show_all

      bw,bh = hbox.size_request
      @btn_panel_height = bh

      @text_fields = []
      i = @fields.size

      while i>0 do
        i -= 1
        field = @fields[i]
        atext = field[1]
        atype = field[14]
        asize = field[15]
        if atype=='Text'
          image = Gtk::Image.new(Gtk::Stock::DND, Gtk::IconSize::MENU)
          image.set_padding(2, 0)
          textview = Gtk::TextView.new
          textview.wrap_mode = Gtk::TextTag::WRAP_WORD

          textview.signal_connect('key-press-event') do |widget, event|
            if ((event.hardware_keycode==36) or \
              [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval)) \
              and event.state.control_mask?
            then
              true
            end
          end

          label_box = TabLabelBox.new(image, atext, nil, false, 0)
          page = notebook.append_page(textview, label_box)
          textview.buffer.text = field[13].to_s
          field[9] = textview

          txt_fld = field
          txt_fld << page
          @text_fields << txt_fld
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
        atext = field[1]
        label = Gtk::Label.new(atext)
        label.xalign = 0.0
        lw,lh = label.size_request
        field[6] = label
        field[7] = lw
        field[8] = lh
        texts_width += lw
        if $jcode_on
          texts_chars += atext.jlength
        else
          texts_chars += atext.length
        end
        #texts_chars += atext.length
        labels_width += lw
        max_label_height = lh if max_label_height < lh
      end
      @middle_char_width = texts_width.to_f / texts_chars

      # max window size
      scr = Gdk::Screen.default
      window_width, window_height = scr.width-50, scr.height-100
      form_width = window_width-36
      form_height = window_height-@btn_panel_height-55

      # compose first matrix, calc its geometry
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @fields.each do |field|
        max_size = 0
        fld_size = 10
        entry = Gtk::Entry.new
        begin
          atype = field[14]
          def_size = 10
          case atype
            when 'Integer'
              def_size = 10
            when 'String'
              def_size = 32
            when 'Blob'
              def_size = 128
          end
          fld_size = field[12].to_i if field[12] != nil
          max_size = field[2].to_i
          fld_size = def_size if fld_size<=0
          max_size = fld_size if fld_size>max_size
        rescue
          fld_size, max_size = def_size
        end
        #entry.width_chars = fld_size
        entry.max_length = max_size
        ew = fld_size*@middle_char_width
        ew = form_width if ew > form_width
        entry.width_request = ew
        ew,eh = entry.size_request
        field[9] = entry
        field[10] = ew
        field[11] = eh
        entries_width += ew
        max_entry_height = eh if max_entry_height < eh
        entry.text = field[13].to_s
      end

      field_matrix = []
      mw, mh = 0, 0
      row = []
      row_index = -1
      rw, rh = 0, 0
      orient = :up
      @fields.each_index do |index|
        field = @fields[index]
        if (index==0) or (field[5]==1)
          row_index += 1
          field_matrix << row if row != []
          mw, mh = [mw, rw].max, mh+rh
          row = []
          rw, rh = 0, 0
        end

        if ! [:up, :down, :left, :right].include?(field[4]) then field[4]=orient; end
        orient = field[4]

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
      lw = field[7]
      lh = field[8]
      ew = field[10]
      eh = field[11]
      if (field[4]==:left) or (field[4]==:right)
        [lw+ew, [lh,eh].max]
      else
        field_size = [[lw,ew].max, lh+eh]
      end
    end

    def calc_row_size(row)
      rw, rh = 0, 0
      row.each do |fld|
        fs = calc_field_size(fld)
        rw, rh = rw+fs[0], [rh, fs[1]].max
      end
      [rw, rh]
    end

    # recreate a widget instead of unparent, because unparent has a bug
    def hacked_unparent(widget)
      if widget.is_a? Gtk::Label
        new_widget = Gtk::Label.new(widget.text)
        new_widget.xalign = 0.0
      else
        new_widget = Gtk::Entry.new
        new_widget.max_length = widget.max_length
        new_widget.width_request = widget.width_request
        new_widget.text = widget.text
      end
      widget.destroy
      new_widget
    end

    # hide fields and delete sub-containers
    def clear_vbox(temp_fields)
      if @vbox.children.size>0
        @vbox.hide_all
        @vbox.child_visible = false
        @fields.each_index do |index|
          field = @fields[index]
          label = field[6]
          entry = field[9]
          #label.unparent
          #entry.unparent
          label = hacked_unparent(label)
          entry = hacked_unparent(entry)
          field[6] = label
          field[9] = entry
          temp_fields[index][6] = label
          temp_fields[index][9] = entry
        end
        @vbox.each do |child|
          child.destroy
        end
      end
    end

    def on_resize_window(window, event)
      if (@window_width == event.width) and (@window_height == event.height)
        return
      end
      @window_width, @window_height = event.width, event.height

      form_width = @window_width-36
      form_height = @window_height-@btn_panel_height-55

=begin
      TODO:
      H - высота элемента
      1) измерить длину всех label (W1)
      2) измерить длину всех entry (W2)
      3) сложить (W1+W2)*H - вписывается ли в квадрат, нет?
      4) измерить хитрую длину Wx = Sum [max(w1&w2)]
      5) сложить Wx*2H - вписывается ли в квадрат, нет?

      [соблюдать рекомендации по рядам, менять ориентацию, перескоки по соседству]
      1. ряды уложить по рекомендации/рекомендациям
          - если какой-нибудь ряд не лезет в ширину, начать up-ить его с конца
          - если тем не менее ряд не лезет в ширину, перемещать правые поля в начало 2х нижних
            рядов (куда лезет), или в конец верхнего соседнего, или в конец нижнего соседнего
          - если не лезет в таблицу, снизу вверх по возможности left-ить ряды,
            пока таблица не сойдется
          - если не лезла таблица, в конец верхних рядов перемещать нижние левые поля
          - если в итоге не лезет в таблицу - этап 2
          - если каждый ряд влез, и таблица влезла - на выход
      [крушить ряды с заду, потом спереди]
      2. перед оставлять рекомендованным, с заду менять:
          - заполнять с up, бить до умещения по ширине, как таблица влезла - на выход
          - заполнять с left, бить до умещения по ширине, как таблица влезла - на выход
          - выбирать up или left чтобы было минимум пустых зон
      3. спереду выбирать up или left чтобы было минимум пустых зон
      [дальние перескоки, перестановки]
      4. перемещать нижние поля (d<1) через ряды в конец верхних рядов (куда лезет), и пробовать c этапа 1
      [оставить попытки уместить в форму, использовать скроллинг]
      5a. снять ограничение по высоте таблицы, повторить с 1го этапа
      5b. следовать рекомендациям и включить скроллинг
      5c. убористо укладывать ряды (up или left) в ширину, высота таблицы без ограничений, скроллинг
      ?5d. высчитать требуемую площадь для up, уместить в гармонию, включить скроллинг
      ?5e. высчитать требуемую площадь для left, уместить в гармонию, включить скроллинг

      При каждом следующем этапе повторять все предыдущие.

      В случае, когда рекомендаций нет (все order=1.0-1.999), тогда за рекомендации разбивки считать
      относительный скачок длинны между словами идентификаторов. При этом бить число рядов исходя
      из ширины/пропорции формы.
=end

      #p '---fill'

      # create and fill field matrix to merge in form
      step = 1
      found = false
      while not found do
        fields = []
        @fields.each do |field|
          fields << field.dup
        end

        field_matrix = []
        mw, mh = 0, 0
        case step
          when 1  #normal compose. change "left" to "up" when doesn't fit to width
            row = []
            row_index = -1
            rw, rh = 0, 0
            orient = :up
            fields.each_index do |index|
              field = fields[index]
              if (index==0) or (field[5]==1)
                row_index += 1
                field_matrix << row if row != []
                mw, mh = [mw, rw].max, mh+rh
                #p [mh, form_height]
                if (mh>form_height)
                  #step = 2
                  step = 5
                  break
                end
                row = []
                rw, rh = 0, 0
              end

              if ! [:up, :down, :left, :right].include?(field[4]) then field[4]=orient; end
              orient = field[4]

              field_size = calc_field_size(field)
              rw, rh = rw+field_size[0], [rh, field_size[1]].max
              row << field

              if rw>form_width
                col = row.size
                while (col>0) and (rw>form_width)
                  col -= 1
                  fld = row[col]
                  if [:left, :right].include?(fld[4])
                    fld[4]=:up
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
            if (mh>form_height)
              #step = 2
              step = 5
            end
            found = (step==1)
          when 2
            p "222"
            found = true
          when 3
            p "333"
            found = true
          when 5  #need to rebuild rows by width
            row = []
            row_index = -1
            rw, rh = 0, 0
            orient = :up
            fields.each_index do |index|
              field = fields[index]
              if ! [:up, :down, :left, :right].include?(field[4]) then field[4]=orient; end
              orient = field[4]
              field_size = calc_field_size(field)

              if (rw+field_size[0]>form_width)
                row_index += 1
                field_matrix << row if row != []
                mw, mh = [mw, rw].max, mh+rh
                p [mh, form_height]
                row = []
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
            if (field[4] != ofield[4]) or (field[7] != ofield[7]) or (field[8] != ofield[8]) \
              or (field[10] != ofield[10]) or (field[11] != ofield[11])
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
        clear_vbox(fields)

        # show field matrix on form
        field_matrix.each do |row|
          row_hbox = Gtk::HBox.new
          row.each_index do |field_index|
            field = row[field_index]
            label = field[6]
            entry = field[9]
            if (field[4]==nil) or (field[4]==:left)
              row_hbox.pack_start(label, false, false, 2)
              row_hbox.pack_start(entry, false, false, 2)
            elsif (field[4]==:right)
              row_hbox.pack_start(entry, false, false, 2)
              row_hbox.pack_start(label, false, false, 2)
            else
              field_vbox = Gtk::VBox.new
              if (field[4]==:down)
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
      end
    end

  end

  RSA_exponent = 65537

  # Generate a key or key pair
  # RU: Генерирует ключ или ключевую пару
  def self.generate_key(type='RSA', length=2048)
    key1 = nil
    key2 = nil

    case type
      when 'RSA'
        key = OpenSSL::PKey::RSA.generate(length, RSA_exponent)

        #p key1 = key.params['n']
        #key2 = key.params['p']
        key1 = PandoraKernel.bigint_to_bytes(key.params['n'])
        #p PandoraKernel.bytes_to_bigin(key1)
        #p '************8'
        key2 = PandoraKernel.bigint_to_bytes(key.params['p'])

        #puts key.to_text
        p key.params

        #key_der = key.to_der
        #p key_der.size

        #key = OpenSSL::PKey::RSA.new(key_der)
        #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
      else #симметричный ключ
        #p OpenSSL::Cipher::ciphers
        cipher = OpenSSL::Cipher.new(type+'-'+length.to_s+'-CBC')
        cipher.encrypt
        key1 = cipher.random_key
    end
    [key1, key2]
  end

  # Init key or key pare
  # RU: Инициализирует ключ или ключевую пару
  def self.init_key(key_input)
    key = nil
    if key_input.is_a? OpenSSL::Cipher or key_input.is_a? OpenSSL::PKey
      key = key_input
    else
      key1 = key_input[0]
      key2 = key_input[1]
      type = key_input[2]
      pass = key_input[3]
      case type
        when 'RSA'
          p '------'
          #p key.params
          n = PandoraKernel.bytes_to_bigint(key1)
          p 'n='+n.inspect
          e = OpenSSL::BN.new(RSA_exponent.to_s)
          if key2
            p0 = PandoraKernel.bytes_to_bigint(key2)
          else
            p0 = 0
          end
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
          #str_val = PandoraKernel.bigint_to_bytes(seq1.value)
          #p 'str_val.size='+str_val.size.to_s
          #p Base64.encode64(str_val)
          #key2 = key.public_key
          #p key2.to_der.size
          # Seq: Int:n, Int:e
          #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
          #p key2.to_s

          # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
          key = OpenSSL::PKey::RSA.new(seq.to_der)
          p key.params
        when 'DSA'
          seq = OpenSSL::ASN1::Sequence([
            OpenSSL::ASN1::Integer(0),
            OpenSSL::ASN1::Integer(key.p),
            OpenSSL::ASN1::Integer(key.q),
            OpenSSL::ASN1::Integer(key.g),
            OpenSSL::ASN1::Integer(key.pub_key),
            OpenSSL::ASN1::Integer(key.priv_key)
          ])
      end
    end
    key
  end

  # Deactivate current or target key
  # RU: Деактивирует текущий или указанный ключ
  def self.deactivate_key(key=nil)
    true
  end

  # Create sign
  # RU: Создает подпись
  def self.make_sign(from_key, data, to_key=nil)
    sign = nil
    sign = from_key.sign(OpenSSL::Digest::SHA1.new, data)
    sign
  end

  # Verify sign
  # RU: Проверяет подпись
  def self.verify_sign(from_key, data, sign, to_key=nil)
    res = false
    res = from_key.verify(OpenSSL::Digest::SHA1.new, sign, data)
    res
  end

  # Encrypt data
  # RU: Шифрует данные
  def self.encrypt(to_key, pure_data)
    encrypted = nil
    type ||= 'RSA'
    case type
      when 'RSA'
        #???
        encrypted = to_key.public_encrypt(pure_data)
        #Base64.encode64(
      when 'AES'
        cipher = OpenSSL::Cipher::AES.new(128, :CBC)
        cipher.encrypt
        key = cipher.random_key
        iv = cipher.random_iv
        encrypted = cipher.update(data) + cipher.final

        #def AESCrypt.encrypt(data, key, iv, cipher_type)
        #aes = OpenSSL::Cipher::Cipher.new(cipher_type)
        #aes.encrypt
        #aes.key = key
        #aes.iv = iv if iv != nil
        #aes.update(data) + aes.final
      when 'BT'
        cipher = OpenSSL::Cipher::Cipher.new('bf-cbc').send(mode)
        cipher.key = Digest::SHA256.digest(key)
        cipher.update(data) << cipher.final
        cipher(:encrypt, key, data)
    end
    encrypted
  end

  # Decrypt data
  # RU: Расшифровывает данные
  def self.decrypt(from_key, crypt_data)
    decrypted = nil
    type ||= 'RSA'
    case type
      when 'RSA'
        #private_key = OpenSSL::PKey::RSA.new(File.read('my_private_key.pem'), 'password')
        decrypted = from_key.private_decrypt(crypt_data)
        #Base64.decode64(
      when 'AES'
        decipher = OpenSSL::Cipher::AES.new(128, :CBC)
        decipher.decrypt
        decipher.key = key
        decipher.iv = iv
        decrypted = decipher.update(encrypted) + decipher.final

        #def AESCrypt.decrypt(encrypted_data, key, iv, cipher_type)
        #aes = OpenSSL::Cipher::Cipher.new(cipher_type)
        #aes.decrypt
        #aes.key = key
        #aes.iv = iv if iv != nil
        #aes.update(encrypted_data) + aes.final

      when 'BT'
        cipher = OpenSSL::Cipher::Cipher.new('bf-cbc').send(mode)
        cipher.key = Digest::SHA256.digest(key)
        cipher.update(data) << cipher.final
        cipher(:decrypt, key, text)
        #p "text" == Blowfish.decrypt("key", Blowfish.encrypt("key", "text"))
    end
    decrypted
  end

  def self.get_param(name, category='Common', type='Integer', dev_values=[0,0,0])
    value = nil
    value
  end

  class << self
    attr_accessor :the_current_key
  end

  def self.current_key(reinit=false)
    key = self.the_current_key
    if (not key) or reinit
      last_auth_key = get_param('last_auth_key', 'Crypto', 'String')
      keys = []
      if last_auth_key
        pub_key_panobj = PandoraModel::Key.find_by_panhash(last_auth_key)
        keys[0] = pub_key_panobj.values['body']
        priv_key_panobj = PandoraModel::Key.find_by_panhash(last_auth_key)
        keys[1] = priv_key_panobj.values['body']
        keys[2] = 'RSA'
        keys[3] = '12345'
      else
        dialog = AdvancedDialog.new(_('Password'))
        dialog.run do
          keys = generate_key('RSA', 2048)
          keys[2] = 'RSA'
          keys[3] = '12345'
        end
      end
      if keys != []
        key = init_key(keys)
        self.the_current_key = key
      end
    end
    key
  end

  PT_Int   = 0
  PT_Str   = 1
  PT_Bool  = 2
  PT_Time  = 3
  PT_Array = 4
  PT_Hash  = 5
  PT_Sym   = 6
  PT_Unknown = 32

  def self.encode_pan_type(basetype, int)
    count = 0
    while (int>0xFF) and (count<8)
      int = int >> 8
      count +=1
    end
    if count == 8
      puts '[encode_pan_type] Too big int='+int.to_s
      count = 7
    end
    [basetype ^ (count << 5), count]
  end

  def self.decode_pan_type(type)
    basetype = type & 0x1F
    count = type >> 5
    [basetype, count]
  end

  def self.rubyobj_to_pson_elem(rubyobj)
    type = PT_Unknown
    count = 0
    data = ''
    elem_size = nil
    case rubyobj
      when String
        data = rubyobj
        elem_size = data.size
        type, count = encode_pan_type(PT_Str, elem_size)
      when Symbol
        data = rubyobj.to_s
        elem_size = data.size
        type, count = encode_pan_type(PT_Sym, elem_size)
      when Integer
        data = PandoraKernel.bigint_to_bytes(rubyobj)
        type, count = encode_pan_type(PT_Int, rubyobj)
      when TrueClass, FalseClass
        if rubyobj
          data = 1
        else
          data = 0
        end
        data = [data].pack('C')
        type = PT_Bool
      when Time
        data = PandoraKernel.bigint_to_bytes(rubyobj.to_i)
        type, count = encode_pan_type(PT_Time, rubyobj.to_i)
      when Array
        rubyobj.each do |a|
          data << rubyobj_to_pson_elem(a)
        end
        elem_size = rubyobj.size
        type, count = encode_pan_type(PT_Array, elem_size)
      when Hash
        rubyobj = rubyobj.sort_by {|k,v| k.to_s}
        rubyobj.each do |a|
          data << rubyobj_to_pson_elem(a[0]) << rubyobj_to_pson_elem(a[1])
        end
        elem_size = rubyobj.size
        type, count = encode_pan_type(PT_Hash, elem_size)
      else
        puts 'Unknown elem type: ['+rubyobj.class.name+']'
    end
    res = [type].pack('C')
    if elem_size
      res << PandoraKernel.fill_zeros_from_left(PandoraKernel.bigint_to_bytes(elem_size), count+1) + data
    else
      res << PandoraKernel.fill_zeros_from_left(data, count+1)
    end
    res
  end

  def self.pson_elem_to_rubyobj(data)
    val = nil
    len = 0
    if data.size>0
      len = 1
      type = data[0].ord
      basetype, count = decode_pan_type(type)
      if data.size>0
        vlen = count+1
        int = PandoraKernel.bytes_to_bigint(data[1, vlen])
        case basetype
          when PT_Int
            val = int
          when PT_Str
            val = data[1+vlen, int]
            vlen += int
          when PT_Sym
            val = data[1+vlen, int].to_sym
            vlen += int
          when PT_Bool
            val = (int != 0)
          when PT_Time
            val = Time.at(int)
          when PT_Array, PT_Hash
            val = []
            int *= 2 if basetype==PT_Hash
            while (data.size-1-vlen>0) and (int>0)
              int -= 1
              aval, alen = pson_elem_to_rubyobj(data[1+vlen..-1])
              val << aval
              vlen += alen
            end
            val = Hash[*val] if basetype==PT_Hash
        end
        len += vlen
      end
    end
    [val, len]
  end

  # Pack PanObject fields to PSON binary format
  # RU: Пакует поля ПанОбъекта в бинарный формат PSON
  def self.hash_to_pson(fldvalues)
    bytes = ''
    bytes.force_encoding('UTF-8')
    fldvalues = fldvalues.sort_by {|k,v| k.to_s }
    fldvalues.each { |nam, val|
      nam = nam.to_s
      nsize = nam.size
      nsize = 255 if nsize>255
      bytes << [nsize].pack('C') + nam[0, nsize]
      pson_elem = rubyobj_to_pson_elem(val)
      pson_elem.force_encoding('UTF-8')
      bytes << pson_elem
    }
    bytes
  end

  def self.pson_to_hash(pson)
    hash = {}
    while (pson != nil) and (pson.size>1)
      flen = pson[0].ord
      fname = pson[1, flen]
      val = nil
      len = 0
      if pson.size-flen>1
        val, len = pson_elem_to_rubyobj(pson[1+flen..-1])
      end
      pson = pson[1+flen+len..-1]
      hash[fname] = val
    end
    hash
  end

  # Sign PSON of PanObject and save sign record
  # RU: Подписывает PSON ПанОбъекта и сохраняет запись подписи
  def self.sign_panobject(panobject)
    key = current_key
    namesvalues = panobject.namesvalues
    matter_fields = panobject.matter_fields
    matter_fields['time'] = Time.now
    p 'sign: matter_fields='+matter_fields.inspect
    p sign = make_sign(key, hash_to_pson(matter_fields))
    values = {:objhash=>namesvalues['panhash'], :sign=>sign}
    key_model = PandoraModel::Sign.new
    key_model.update(values, nil, nil)
  end

  def self.unsign_panobject(panhash)
    count = 0
    count
  end

  # View and edit record dialog
  # RU: Окно просмотра и правки записи
  def self.edit_panobject(tree_view, action)

    def self.decode_pos(pos='')
      pos = '' if pos == nil
      pos = pos.to_s
      new_row = 1 if pos.include?('|')
      ind = pos.scan(/[0-9\.\+]+/)
      ind = ind[0] if ind != nil
      lab_or = pos.scan(/[a-z]+/)
      lab_or = lab_or[0] if lab_or != nil
      lab_or = lab_or[0, 1] if lab_or != nil
      if (lab_or==nil) or (lab_or=='u')
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

    def self.get_panobject_icon(panobj)
      ind = -1
      $notebook.children.each do |child|
        if child.name==panobj.ider
          ind = $notebook.children.index(child)
          break
        end
      end
      panobj_icon = nil
      first_lab_widget = $notebook.get_tab_label($notebook.children[ind]).children[0] if ind>=0
      if first_lab_widget.is_a? Gtk::Image
        image = first_lab_widget
        panobj_icon = $window.render_icon(image.stock, Gtk::IconSize::MENU)
      end
      panobj_icon
    end

    path, column = tree_view.cursor
    new_act = action == 'Create'
    if path != nil or new_act
      panobject = tree_view.panobject
      store = tree_view.model
      sel = nil
      id = nil
      panhash0 = nil
      if path != nil and ! new_act
        iter = store.get_iter(path)
        id = iter[0].to_s
        sel = panobject.select('id='+id, false)
        #p 'panobject.namesvalues='+panobject.namesvalues.inspect
        #p 'panobject.matter_fields='+panobject.matter_fields.inspect
        panhash0 = panobject.panhash(sel[0])
      end
      #p sel

      panobjecticon = get_panobject_icon(panobject)

      if action=='Delete'
        dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
          Gtk::MessageDialog::QUESTION,
          Gtk::MessageDialog::BUTTONS_OK_CANCEL,
          _('Record will be deleted. Sure?')+"\n["+sel[0][2,3].join(', ')+']')
        dialog.title = _('Deletion')+': '+panobject.sname
        dialog.default_response = Gtk::Dialog::RESPONSE_OK
        dialog.icon = panobjecticon
        if dialog.run == Gtk::Dialog::RESPONSE_OK
          id = 'id='+id
          res = panobject.update(nil, nil, id)
        end
        dialog.destroy
      else
        i = 0
        formfields = []
        ind = 0.0

        #p panobject.def_fields

        panobject.def_fields.each do |field|
          if field[3]
            fldsize = field[3].to_i
          else
            fldsize = 0
          end
          if field[5]
            fldfsize = field[5].to_i
            fldfsize = fldsize if fldfsize > fldsize
          else
            fldfsize = fldsize
            fldfsize *= 0.67 if fldfsize>40
          end
          indd, lab_or, new_row = decode_pos(field[4])
          plus = (indd and (indd[0, 1]=='+'))
          indd = indd[1..-1] if plus
          indd = indd.to_f if (indd != nil) and (indd.size>0)
          fldind = 0
          if not indd
            ind += 1.0
          else
            if plus
              ind += indd
            else
              fldind = indd
              ind = indd if indd != 255
            end
          end
          fldind = ind if fldind==0
          new_fld = [field[0], field[1], fldsize, fldind, lab_or, new_row]
          new_fld[12] = fldfsize
          fldval = nil
          fldval = panobject.field_val(field[0], sel[0]) if (sel != nil) and (sel[0] != nil)

          fldval = PandoraKernel.bytes_to_hex(fldval) if field[0]=='panhash'

          fldval = '' if fldval == nil
          new_fld[13] = fldval

          new_fld[14] = field[2]
          new_fld[15] = field[3]

          formfields << new_fld
        end
        p formfields
        formfields.sort! {|a,b| a[3]<=>b[3] }

        dialog = FieldsDialog.new(panobject, formfields.clone, panobject.sname)
        dialog.icon = panobjecticon

        PandoraGUI.set_statusbar_text(dialog.statusbar, panobject.panhash(sel[0], true, true)) if sel

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

        dialog.run do
          dialog.fields.each do |field|
            entry = field[9]
            field[13] = entry.text
          end
          dialog.text_fields.each do |field|
            textview = field[9]
            field[13] = textview.buffer.text
          end

          fldnames = []
          fldvalues = []
          if (panobject.is_a? PandoraModel::Hashed) and sel
            fldnames << 'panhash'
            fldvalues << panobject.panhash(sel[0])
          end
          if panobject.is_a? PandoraModel::HashedCreated
            fldnames << 'creator'
            fldvalues << '[authorized]'
          end
          dialog.fields.each_index do |index|
            field = dialog.fields[index]
            if not fldnames.include?(field[0])
              fldnames << field[0]
              fldvalues << field[13]
            end
          end
          dialog.text_fields.each_index do |index|
            field = dialog.text_fields[index]
            #if formfields[index][13] != field[13]
              fldnames << field[0]
              fldvalues << field[13]
            #end
          end
          if new_act or (action=='Copy')
            id = nil
          else
            id = 'id='+id
          end
          res = panobject.update(fldvalues, fldnames, id, true)
          if res
            panhash = panobject.namesvalues['panhash']
            if panhash
              p 'pan='+panhash.inspect

              sel = panobject.select({'panhash'=>panhash}, true)

              p 'panobject.namesvalues='+panobject.namesvalues.inspect
              p 'panobject.matter_fields='+panobject.matter_fields.inspect
              p dialog.support_btn.active?
              unsign_panobject(panhash0)
              if dialog.trust_btn.active?
                sign_panobject(panobject)
              end
              p dialog.public_btn.active?
            end
          end
        end
      end
    end
  end

  # Tree of panobjects
  # RU: Дерево субъектов
  class SubjTreeView < Gtk::TreeView
    attr_accessor :panobject
  end

  # Tab box for notebook with image and close button
  # RU: Бокс закладки для блокнота с картинкой и кнопкой
  class TabLabelBox < Gtk::HBox
    attr_accessor :label

    def initialize(image, title, bodywin, *args)
      super(*args)
      label_box = self

      label_box.pack_start(image, false, false, 0) if image != nil

      @label = Gtk::Label.new(title)
      label_box.pack_start(label, false, false, 0)

      if bodywin
        btn = Gtk::Button.new
        btn.relief = Gtk::RELIEF_NONE
        btn.focus_on_click = false
        style = btn.modifier_style
        style.xthickness = 0
        style.ythickness = 0
        btn.modify_style(style)
        wim,him = Gtk::IconSize.lookup(Gtk::IconSize::MENU)
        btn.set_size_request(wim+2,him+2)
        btn.signal_connect('clicked') do
          yield if block_given?
          $notebook.remove_page($notebook.children.index(bodywin))
          label_box.destroy if not label_box.destroyed?
          bodywin.destroy if not bodywin.destroyed?
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

  # Showing panobject list
  # RU: Показ списка субъектов
  def self.show_panobject_list(panobject_class, widget=nil, sw=nil)
    embedded = (sw != nil)
    if embedded
      $notebook.children.each do |child|
        if child.name==panobject_class.ider
          $notebook.page = $notebook.children.index(child)
          return
        end
      end
    end
    panobject = panobject_class.new
    sel = panobject.select
    flds = panobject.tab_fields
=begin
      row.each_index do |i|
        val = row[i].to_s
        fld_def = panobject.field_des(flds[i])
        # clean text fields
        val = val[0,50].gsub(/[\r\n\t]/, ' ').squeeze(' ') if fld_def.is_a? Array and fld_def[2]=='Text'
        # truncate all fields
        if $jcode_on
          val = val[/.{0,#{34}}/m]
        else
          val = val[0,34]
        end
        iter.set_value(i, val.rstrip)
      end
=end
    store = Gtk::ListStore.new(Integer)
    sel.each_with_index do |row, i|
      iter = store.append
      iter[0] = row[0]
    end
    treeview = SubjTreeView.new(store)
    treeview.name = panobject.ider
    treeview.panobject = panobject
    flds = panobject.def_fields if flds == []
    flds.each_with_index do |v,i|
      v = v[0].to_s if v.is_a? Array
      renderer = Gtk::CellRendererText.new
      #renderer.background = 'red'
      #renderer.editable = true
      #renderer.text = 'aaa'
      column = Gtk::TreeViewColumn.new(panobject.field_title(v), renderer )  #, {:text => i}
      column.resizable = true
      column.reorderable = true
      column.clickable = true
      treeview.append_column(column)
      column.signal_connect('clicked') do |col|
        p 'sort clicked'
      end
      column.set_cell_data_func(renderer) do |col, renderer, model, iter|
        val = sel[iter.path.indices[0]][i]
        val = PandoraKernel.bytes_to_hex(val[2,12]) if v=='panhash'
        renderer.text = val.to_s
        renderer.foreground = 'navy' if v=='panhash'
      end
    end
    treeview.signal_connect('row_activated') do |tree_view, path, column|
      edit_panobject(tree_view, 'Edit')
    end

    sw ||= Gtk::ScrolledWindow.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.name = panobject.ider
    sw.add(treeview)
    sw.border_width = 0;

    if not embedded
      if widget.is_a? Gtk::ImageMenuItem
        animage = widget.image
      elsif widget.is_a? Gtk::ToolButton
        animage = widget.icon_widget
      else
        animage = nil
      end
      image = nil
      if animage != nil
        image = Gtk::Image.new(animage.stock, Gtk::IconSize::MENU)
        image.set_padding(2, 0)
      end

      label_box = TabLabelBox.new(image, panobject.pname, sw, false, 0) do
        store.clear
        treeview.destroy
      end

      page = $notebook.append_page(sw, label_box)
      sw.show_all
      $notebook.page = $notebook.n_pages-1
    end

    menu = Gtk::Menu.new
    menu.append(create_menu_item(['Create', Gtk::Stock::NEW, _('Create'), 'Insert']))
    menu.append(create_menu_item(['Edit', Gtk::Stock::EDIT, _('Edit'), 'Return']))
    menu.append(create_menu_item(['Delete', Gtk::Stock::DELETE, _('Delete'), 'Delete']))
    menu.append(create_menu_item(['Copy', Gtk::Stock::COPY, _('Copy'), '<control>Insert']))
    menu.append(create_menu_item(['-', nil, nil]))
    menu.append(create_menu_item(['Talk', Gtk::Stock::MEDIA_PLAY, _('Talk'), '<control>T']))
    menu.append(create_menu_item(['Express', Gtk::Stock::JUMP_TO, _('Express'), '<control>BackSpace']))
    menu.append(create_menu_item(['Connect', Gtk::Stock::CONNECT, _('Connect'), '<control>N']))
    menu.append(create_menu_item(['-', nil, nil]))
    menu.append(create_menu_item(['Clone', Gtk::Stock::CONVERT, _('Recreate the table')]))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect('button_press_event') do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

  end

  # Socket with defined outbound port
  # RU: Сокет с заданным исходящим портом
  class CustomSocket < Socket
    def initialize
      super(AF_INET, SOCK_STREAM, 0)
      setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
      if defined?(SO_REUSEPORT)
        setsockopt(SOL_SOCKET, SO_REUSEPORT, 1)
      end
    end

    def bind(port = 0)
      addr_local = Socket.pack_sockaddr_in(port, '0.0.0.0')
      super(addr_local)
    end

    def connect(ip, port)
      addr_remote = Socket.pack_sockaddr_in(port, ip)
      super(addr_remote)
    end

    def accept
      super[0]
    end

    def addr
      Socket.unpack_sockaddr_in(getsockname)
    end

    def local_port
      addr[0]
    end
  end

  class ClientA   # посылает syn-пакет и открывает порт
    class << self
      def accept(ip, port)
        server = CustomSocket.new
        server.bind
        server.listen(5)
        send_syn!(ip, port, server.local_port)
        Thread.new do
          begin
            Timeout::timeout(5) {
              session = server.accept
              self.new(ip, port, session)
            }
          rescue Timeout::Error
          end
        end
        server.local_port
      end

      private
        def send_syn!(ip, port, local_port)
          socket = CustomSocket.new
          socket.bind(local_port)
          Timeout::timeout(0.3) {
            socket.connect(ip, port)
          }
          rescue Timeout::Error
          rescue # Errno errors
          ensure
            if socket && !socket.closed?
              socket.close
            end
        end
    end
  end

  class ClientB   # сразу после того как A послал syn, устанавливает соединение
    class << self
      def connect(ip, port, local_port)
        socket = CustomSocket.new
        socket.bind(local_port)
        Timeout::timeout(2) {
          socket.connect(ip, port)
          self.new(ip, port, socket)
        }
        true
      rescue Timeout::Error,
             Errno::ECONNREFUSED
        false
      end
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
  EC_Patch     = 8     # Выдача патча
  EC_Preview   = 9     # Выдача миниатюры
  EC_Fishing   = 10    # Управление рыбалкой
  EC_Pipe      = 11    # Данные канала двух рыбаков
  EC_Sync      = 12    # Последняя команда в серии, или индикация "живости"
  EC_Wait      = 253   # Временно недоступен
  EC_More      = 254   # Давай дальше
  EC_Bye       = 255   # Рассоединение
  EC_Data      = 256   # Ждем данные
  #EC_Notice    = 5
  #EC_Pack      = 7

  TExchangeCommands = {EC_Init=>'init', EC_Query=>'query', EC_News=>'news',
    EC_Patch=>'patch', EC_Request=>'request', EC_Record=>'record', EC_Pipe=>'pipe',
    EC_Wait=>'wait', EC_More=>'more', EC_Bye=>'bye'}
  TExchangeCommands_invert = TExchangeCommands.invert

  # RU: Преобразует код в xml-команду
  def self.cmd_to_text(cmd)
    TExchangeCommands[cmd]
  end

  # RU: Преобразует xml-команду в код
  def self.text_to_cmd(text)
    TExchangeCommands_invert[text.downcase]
  end

  MaxPackSize = 1500
  MaxSegSize  = 1200
  CommSize = 6
  CommExtSize = 10

  def self.unpack_comm(comm)
    errcode = 0
    if comm.size == CommSize
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

  def self.unpack_comm_ext(comm)
    if comm.size == CommExtSize
      datasize, fullcrc32, segsize = comm.unpack('NNn')
    else
      log_message(LM_Error, 'Ошибочная длина расширения команды')
    end
    [datasize, fullcrc32, segsize]
  end

  LONG_SEG_SIGN   = 0xFFFF

  # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
  def self.send_comm_and_data(socket, index, cmd, code, data=nil)
    data ||=""
    datasize = data.size
    if datasize <= MaxSegSize
      segsign = datasize
      segsize = datasize
    else
      segsign = LONG_SEG_SIGN
      segsize = MaxSegSize
    end
    crc8 = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
    # Команда как минимум равна 1+1+1+2+1= 6 байт (CommSize)
    p 'SCAB: '+[index, cmd, code, segsign, crc8].inspect
    comm = [index, cmd, code, segsign, crc8].pack('CCCnC')
    if index<255 then index += 1 else index = 0 end
    buf = ''
    if datasize>0
      if segsign == LONG_SEG_SIGN
        fullcrc32 = Zlib.crc32(data)
        # если пакетов много, то добавить еще 4+4+2= 10 байт
        comm << [datasize, fullcrc32, segsize].pack('NNn')
        buf = data[0, segsize]
      else
        buf = data
      end
      segcrc32 = Zlib.crc32(buf)
      # в конце всегда CRC сегмента - 4 байта
      buf << [segcrc32].pack('N')
    end
    buf = comm + buf
    p "!SEND: ("+buf+')'

    # tos_sip    cs3   0x60  0x18
    # tos_video  af41  0x88  0x22
    # tos_xxx    cs5   0xA0  0x28
    # tos_audio  ef    0xB8  0x2E
    #socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0xA0)  # QoS (VoIP пакет)
    sended = socket.write(buf)
    #socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0x00)  # обычный пакет

    if sended < buf.size
      log_message(LM_Error, 'Не все данные отправлены '+seg.size+'/'+sended.size)
    end
    segindex = 0
    i = segsize
    while (datasize-i)>0
      segsize = datasize-i
      segsize = MaxSegSize if segsize>MaxSegSize
      if segindex<0xFFFFFFFF then segindex += 1 else segindex = 0 end
      comm = [index, segindex, segsize].pack('CNn')
      if index<255 then index += 1 else index = 0 end
      buf = data[i, segsize]
      p "Nseg["+data[i, segsize]+']'
      buf << [Zlib.crc32(buf)].pack('N')
      buf = comm + buf
      socket.write(buf)
      p "!!SEND: ("+buf+')'
      i += segsize
    end
    index
  end

  def self.add_to_pack_and_send(connection, cmd, code, data=nil, last=false)
    p "add_to_pack_and_send  "
  end

  ECC_Init0_Hello       = 0
  ECC_Init1_KeyPhrase   = 1
  ECC_Init2_SignKey     = 2
  ECC_Init3_PhraseSign  = 3
  ECC_Init4_Permission  = 4

  ECC_Query0_Kinds      = 0
  ECC_Query255_AllChanges =255

  ECC_News0_Kinds       = 0

  ECC_Channel0_Open     = 0
  ECC_Channel1_Opened   = 1
  ECC_Channel2_Close    = 2
  ECC_Channel3_Closed   = 3
  ECC_Channel4_Fail     = 4

  ECC_Bye_Exit          = 200
  ECC_Bye_Unknown       = 201
  ECC_Bye_BadCommCRC    = 202
  ECC_Bye_BadCommLen    = 203
  ECC_Bye_BadCRC        = 204
  ECC_Bye_DataTooLong   = 205
  ECC_Wait_NoHandlerYet = 206

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
  CM_Persistent   = 2

  # Connected state
  # RU: Состояние соединения
  CS_Connecting    = 0
  CS_Connected     = 1
  CS_Stoping       = 2
  CS_StopRead      = 3
  CS_Disconnected  = 4

  # Stage of exchange
  # RU: Стадия обмена
  ST_Connected    = 0
  ST_IpAllowed    = 1
  ST_Protocoled   = 2
  ST_Hashed       = 3
  ST_KeyAllowed   = 4
  ST_Signed       = 5

  $connections = []

  def self.connection_of_node(node)
    host, port, proto = decode_node(node)
    connection = $connections.find do |e|
      (e.is_a? Connection) and ((e.host_ip == host) or (e.host_name == host)) and (e.port == port) \
      and (e.proto == proto)
    end
    connection
  end

  class Connection
    attr_accessor :host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state, :stage, :dialog, \
      :send_thread, :read_thread, :socket, :read_state, :send_state, :read_mes, :read_media, \
      :read_req, :send_mes, :send_media, :send_req, :sindex, :rindex, :sendpack, :sendpackqueue
    def initialize(ahost_name, ahost_ip, aport, aproto, node, aconn_mode=0, aconn_state=CS_Disconnected)
      super()
      @stage         = ST_Connected
      @host_name     = ahost_name
      @host_ip       = ahost_ip
      @port          = aport
      @proto         = aproto
      @node          = node
      @conn_mode     = aconn_mode
      @conn_state    = aconn_state
    end
    def post_init
      @sindex         = 0
      @rindex         = 0
      @reads_state    = 0
      @send_state     = 0
      @sendpack       = []
      @sendpackqueue  = []
      @read_mes       = [-1, -1, []]
      @read_media     = [-1, -1, []]
      @read_req       = [-1, -1, []]
      @send_mes       = [-1, -1, []]
      @send_media     = [-1, -1, []]
      @send_req       = [-1, -1, []]
    end

    # Accept received segment
    # RU: Принять полученный сегмент
    def accept_segment(rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd)
      case rcmd  # КЛИЕНТ!!! (актив)
        when EC_Init
          case rcode
            when ECC_Init0_Hello
              hello=rdata
              scmd=EC_Init
              scode=ECC_Init1_KeyPhrase
              akey="a1b2c3"
              sbuf=akey
              @stage = ST_Protocoled
            when ECC_Init1_KeyPhrase
              pphrase=rdata
              scmd=EC_Init
              scode=ECC_Init2_SignKey
              asign="f4443ef"
              sbuf=asign
              @stage = ST_KeyAllowed
            when ECC_Init2_SignKey
              psign=rdata
              scmd=EC_Init
              scode=ECC_Init3_PhraseSign
              aphrase="Yyyzzzzzz"
              sbuf=aphrase
              @stage = ST_Signed
            when ECC_Init3_PhraseSign
              psign=rdata
              scmd=EC_Init
              scode=ECC_Init4_Permission
              aperm="011101"
              sbuf=aperm
            when ECC_Init4_Permission
              pperm=rdata
              #scmd=EC_Query
              #scode=ECC_Query0_Kinds
              scmd=EC_Sync
              scode=0
              sbuf=''
          end
        when EC_Message, EC_Channel
          if not dialog
            @dialog = PandoraGUI.show_talk_dialog(PandoraGUI.encode_node(host_ip, port, proto))
            Thread.pass

            p 'dialog ==='+dialog.inspect
          end
          if rcmd==EC_Message
            mes = rdata
            talkview = nil
            talkview = dialog.talkview if dialog
            if talkview
              t = Time.now
              talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
              talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', "blue")
              talkview.buffer.insert(talkview.buffer.end_iter, 'Dude:', "blue_bold")
              talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)
            else
              log_message(LM_Error, 'Пришло сообщение, но окно чата не найдено!')
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
        when EC_Query
          case rcode
            when ECC_Query0_Kinds
              afrom_data=rdata
              scmd=EC_News
              pkinds="3,7,11"
              scode=ECC_News0_Kinds
              sbuf=pkinds
            else #(1..255) - запрос сорта/всех сортов, если 255
              afrom_data=rdata
              akind=rcode
              if akind==ECC_Query255_AllChanges
                pkind=3 #отправка первого кайнда из серии
              else
                pkind=akind  #отправка только запрашиваемого
              end
              scmd=EC_News
              pnoticecount=3
              scode=pkind
              sbuf=[pnoticecount].pack('N')
          end
        when EC_News
          p "news!!!!"
          if rcode==ECC_News0_Kinds
            pcount = rcode
            pkinds = rdata
            scmd=EC_Query
            scode=ECC_Query255_AllChanges
            fromdate="01.01.2012"
            sbuf=fromdate
          else
            p "more!!!!"
            pkind = rcode
            pnoticecount = rdata.unpack('N')
            scmd=EC_More
            scode=0
            sbuf=''
          end
        when EC_More
          case last_scmd
            when EC_News
              p "!!!!!MORE!"
              pkind = 110
              if pkind <= 10
                scmd=EC_News
                scode=pkind
                ahashid = "id=gfs225,hash=asdsad"
                sbuf=ahashid
                pkind += 1
              else
                scmd=EC_Bye
                scode=ECC_Bye_Unknown
                log_message(LM_Error, '1Получена неизвестная команда от сервера='+rcmd.to_s)
                p '1Получена неизвестная команда от сервера='+rcmd.to_s

                @conn_state = CS_Stoping
              end
            else
              scmd=EC_Bye
              scode=ECC_Bye_Unknown
              log_message(LM_Error, '2Получена неизвестная команда от сервера='+rcmd.to_s)
              p '2Получена неизвестная команда от сервера='+rcmd.to_s

              @conn_state = CS_Stoping
          end
        when EC_News
          p "!!notice!!!"
          pkind = rcode
          phashid = rdata
          scmd=EC_More
          scode=0 #-не надо, 1-патч, 2-запись, 3-миниатюру
          sbuf=''
        when EC_Patch
          p "!patch!"
        when EC_Request
          p "EC_Request"
        when EC_Record
          p "!record!"
        when EC_Pipe
          p "EC_Pipe"
        when EC_Sync
          p "EC_Sync!!!!! SYNC ==== SYNC"
        when EC_Bye
          if rcode != ECC_Bye_Exit
            log_message(LM_Error, 'Ошибка на сервере ErrCode='+rcode.to_s)
          end
          scmd=EC_Bye
          scode=ECC_Bye_Exit

          p 'Ошибка на сервере ErrCode='+rcode.to_s

          @conn_state = CS_Stoping
        else
          scmd=EC_Bye
          scode=ECC_Bye_Unknown
          log_message(LM_Error, 'Получена неизвестная команда от сервера='+rcmd.to_s)
          p 'Получена неизвестная команда от сервера='+rcmd.to_s

          @conn_state = CS_Stoping
      end
      [rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd]
    end

    # Add segment (chunk, grain, phrase) to pack and send when it's time
    # RU: Добавляет сегмент в пакет и отправляет если пора
    def send_segment(ex_comm, last_seg, buf_ind)
      scode = 0
      scmd = ex_comm
      case ex_comm
        when EC_Init
          sbuf = 'pandora,0.1,5577,0,aa99ffee00' if not buf_ind
          scode = ECC_Init0_Hello
        when EC_Message
          mes = send_mes[2][buf_ind] #mes
          if mes=='video:true:'
            scmd = EC_Channel
            scode = ECC_Channel0_Open
            chann = 1
            sbuf = [chann].pack('C')
          elsif mes=='video:false:'
            scmd = EC_Channel
            scode = ECC_Channel2_Close
            chann = 1
            sbuf = [chann].pack('C')
          else
            sbuf = mes
          end
        else
          scmd = EC_Bye
      end
      sendpack << sindex+1
      if last_seg
        sindex = PandoraGUI.send_comm_and_data(socket, @sindex, scmd, scode, sbuf)
        sendpackqueue << sendpack
        sendpack = []
      end
    end

  end

  # Read next data from socket, or return nil if socket is closed
  # RU: Прочитать следующие данные из сокета, или вернуть nil, если сокет закрылся
  def self.socket_recv(socket, maxsize)
    recieved = ''
    begin
      recieved = socket.recv_nonblock(maxsize)
      recieved = nil if recieved==''  # socket is closed
    rescue Errno::EAGAIN       # no data to read
      recieved = ''
    rescue Errno::ECONNRESET   # other socket is closed
      recieved = nil
    end
    recieved
  end

  # Number of messages per cicle
  # RU: Число сообщений за цикл
  $mes_block_count = 2
  # Number of media blocks per cicle
  # RU: Число медиа блоков за цикл
  $media_block_count = 10
  # Number of requests per cicle
  # RU: Число запросов за цикл
  $req_block_count = 1

  # Maximal size of queue
  # RU: Максимальный размер очереди
  MaxQueue = 4

  # Start two exchange cicle of socket: read and send
  # RU: Запускает два цикла обмена сокета: чтение и отправка
  def self.start_exchange_cicle(node)
    socket = nil
    connection = connection_of_node(node)
    if connection

      #p "CICLE connection="+connection.inspect

      send_thread  =  connection.send_thread
      socket       =  connection.socket

      #p "CICLE socket="+socket.inspect

      read_mes     =  connection.read_mes
      read_media   =  connection.read_media
      read_req     =  connection.read_req
      send_mes     =  connection.send_mes
      send_media   =  connection.send_media
      send_req     =  connection.send_req

      #p "exch: !read_mes: "+read_mes.inspect
      #p "exch: !send_mes: "+send_mes.inspect

      hunter = (connection.conn_mode & CM_Hunter)>0
      if hunter
        log_mes = 'HUN: '
      else
        log_mes = 'LIS: '
      end

      scmd = EC_More
      sbuf = ''
      # Send cicle
      # RU: Цикл отправки

      if hunter
        connection.send_segment(EC_Init, true, nil)
      end

      # Read cicle
      # RU: Цикл приёма
      if (connection.read_thread == nil)
        connection.read_thread = Thread.new do
          connection.read_thread = Thread.current

          scmd = EC_More
          sbuf = ''

          rcmd = EC_More
          sindex = 0
          rindex = 0
          rbuf = ''
          rdata = ''
          readmode = RM_Comm
          nextreadmode = RM_Comm
          waitlen = CommSize
          last_scmd = scmd


          p log_mes+"Цикл ЧТЕНИЯ начало"
          # Цикл обработки команд и блоков данных
          while (connection.conn_state != CS_Disconnected) and (connection.conn_state != CS_StopRead) \
          and (not connection.socket.closed?) and (recieved = socket_recv(connection.socket, MaxPackSize))
            #p log_mes+"recieved=["+recieved+']  '+connection.socket.closed?.to_s+'  sok='+connection.socket.inspect
            rbuf += recieved
            processedlen = 0
            while (connection.conn_state != CS_Disconnected) and (connection.conn_state != CS_StopRead) \
            and (connection.conn_state != CS_Stoping) and (not connection.socket.closed?) and (rbuf.size>=waitlen)
              p log_mes+'begin=['+rbuf+']  L='+rbuf.size.to_s+'  WL='+waitlen.to_s
              processedlen = waitlen
              nextreadmode = readmode

              # Определимся с данными по режиму чтения
              case readmode
                when RM_Comm
                  comm = rbuf[0, processedlen]
                  rindex, rcmd, rcode, rsegsign, errcode = unpack_comm(comm)
                  if errcode == 0
                    p log_mes+' RM_Comm: '+[rindex, rcmd, rcode, rsegsign].inspect
                    if rsegsign == LONG_SEG_SIGN
                      nextreadmode = RM_CommExt
                      waitlen = CommExtSize
                    elsif rsegsign > 0
                      nextreadmode = RM_SegmentS
                      waitlen = rsegsign+4  #+CRC32
                      rdatasize, rsegsize = rsegsign
                    end
                  elsif errcode == 1
                    log_message(LM_Error, 'CRC полученой команды некорректен')
                    scmd=EC_Bye; scode=ECC_Bye_BadCommCRC
                  elsif errcode == 2
                    log_message(LM_Error, 'Длина полученой команды некорректна')
                    scmd=EC_Bye; scode=ECC_Bye_BadCommLen
                  else
                    log_message(LM_Error, 'Полученая команда некорректна')
                    scmd=EC_Bye; scode=ECC_Bye_Unknown
                  end
                when RM_CommExt
                  comm = rbuf[0, processedlen]
                  rdatasize, fullcrc32, rsegsize = unpack_comm_ext(comm)
                  p log_mes+' RM_CommExt: '+[rdatasize, fullcrc32, rsegsize].inspect
                  nextreadmode = RM_Segment1
                  waitlen = rsegsize+4   #+CRC32
                when RM_SegLenN
                  comm = rbuf[0, processedlen]
                  rindex, rsegindex, rsegsize = comm.unpack('CNn')
                  p log_mes+' RM_SegLenN: '+[rindex, rsegindex, rsegsize].inspect
                  nextreadmode = RM_SegmentN
                  waitlen = rsegsize+4   #+CRC32
                when RM_SegmentS, RM_Segment1, RM_SegmentN
                  p log_mes+' RM_SegLenX['+readmode.to_s+']  rbuf=['+rbuf+']'
                  if (readmode==RM_Segment1) or (readmode==RM_SegmentN)
                    nextreadmode = RM_SegLenN
                    waitlen = 7    #index + segindex + rseglen (1+4+2)
                  end
                  rseg = rbuf[0, processedlen-4]
                  p log_mes+'rseg=['+rseg+']'
                  rsegcrc32 = rbuf[processedlen-4, 4].unpack('N')[0]
                  fsegcrc32 = Zlib.crc32(rseg)
                  if fsegcrc32 == rsegcrc32
                    rdata << rseg
                  else
                    log_message(LM_Error, 'CRC полученного сегмента некорректен')
                    scmd=EC_Bye; scode=ECC_Bye_BadCRC
                  end
                  p log_mes+'RM_SegmentX: data['+rdata+']'+rdata.size.to_s+'/'+rdatasize.to_s
                  if rdata.size == rdatasize
                    nextreadmode = RM_Comm
                    waitlen = CommSize
                  elsif rdata.size > rdatasize
                    log_message(LM_Error, 'Слишком много полученных данных')
                    scmd=EC_Bye; scode=ECC_Bye_DataTooLong
                  end
              end
              # Очистим буфер от определившихся данных
              rbuf.slice!(0, processedlen)
              scmd = EC_Data if (scmd != EC_Bye) and (scmd != EC_Wait)
              # Обработаем поступившие команды и блоки данных
              if (scmd != EC_Bye) and (scmd != EC_Wait) and (nextreadmode == RM_Comm)
                p log_mes+'accept_request Before='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect

                rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = \
                  connection.accept_segment(rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd)

                rdata = ''
                p log_mes+'accept_request After='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect
              end

              if scmd != EC_Data
                sbuf='' if scmd == EC_Bye
                p log_mes+'SEND: '+scmd.to_s+"/"+scode.to_s+"+("+sbuf+')'
                sindex = send_comm_and_data(connection.socket, sindex, scmd, scode, sbuf)
                #sleep 2
                last_scmd = scmd
                sbuf = ''
              end
              readmode = nextreadmode
            end
            #p "WTF?conn_state="+connection.conn_state.to_s
            if connection.conn_state == CS_Stoping
              connection.conn_state = CS_StopRead
            end
          end
          p log_mes+"Цикл ЧТЕНИЯ конец!"
          connection.socket.close if not connection.socket.closed?
          connection.conn_state = CS_Disconnected
          connection.read_thread = nil
        end
      end

      p log_mes+"WAIT STAGE!"

      while (connection.conn_state != CS_Disconnected) and (connection.stage<ST_Protocoled)
        Thread.pass
      end

      p log_mes+"exch: cicles"
      p log_mes+"exch: connection="+connection.inspect
      while (connection.conn_state != CS_Disconnected)
        # обработка принятых сообщений, их удаление

        # разгрузка принятых буферов в gstreamer

        # обработка принятых запросов, их удаление

        # пакетирование сообщений
        processed = 0
        while (send_mes) and (send_mes[0]) and (send_mes[0] != send_mes[1]) and (processed<$mes_block_count) \
        and (connection.conn_state != CS_Disconnected)
          processed += 1


          if send_mes[0]<MaxQueue
            send_mes[0] += 1
          else
            send_mes[0] = 0
          end
          buf_ind = send_mes[0]
          mes = send_mes[2][buf_ind]


          p log_mes+"??exch: send_mes: " +mes.inspect

          connection.send_segment(EC_Message, processed<$mes_block_count, buf_ind)

          send_mes[2][buf_ind] = nil
          #p "??exch: send_mes: conn_data: "+connection.inspect
        end

        # пакетирование буферов

        if connection.socket.closed?
          connection.conn_state = CS_Disconnected
        end
        Thread.pass
      end

      p log_mes+"exch: EXIT BOTH cicles!!!"

      connection.socket.close if not connection.socket.closed?
      connection.conn_state = CS_Disconnected
      connection.socket = nil

      if (connection.conn_mode & CM_Persistent) == 0
        connection.send_thread = nil
        #Thread.critical = true
        $connections.delete(connection)
        #Thread.critical = false
      end
    else
      puts _('exch: Node is not found in connection list')+' ['+node.to_s+']'
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

  $listen_thread = nil

  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.start_or_stop_listen
    p '====!! '+$listen_thread.inspect
    if $listen_thread == nil
      $listen_btn.label = _('Listening')
      $listen_thread = Thread.new do
        begin
          addr_str = $host.to_s+':'+$port.to_s
          server = TCPServer.open($host, $port)
          addr_str = server.addr[3].to_s+(':')+server.addr[1].to_s
          log_message(LM_Info, 'Слушаю порт '+addr_str)
        rescue
          server = nil
          log_message(LM_Warning, 'Не могу открыть порт '+addr_str)
        end
        Thread.current[:listen_server_socket] = server
        Thread.current[:need_to_listen] = server != nil
        while Thread.current[:need_to_listen] and (server != nil) and not server.closed?
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
              log_message(LM_Info, "Подключился клиент: "+socket.peeraddr.to_s)

              #local_address
              host_ip = socket.peeraddr[2]

              if ip_is_not_banned(host_ip)
                host_name = socket.peeraddr[3]
                port = socket.peeraddr[1]
                #port = socket.addr[1] if host_ip==socket.addr[2] # hack for short circuit!!!
                proto = "tcp"
                node = encode_node(host_ip, port, proto)
                p "LISTEN: node: "+node.inspect

                connection = connection_of_node(node)
                if connection
                  log_message(LM_Info, "Замкнутая петля: "+socket.to_s)
                  while connection and (connection.conn_state==CS_Connected) and not socket.closed?
                    begin
                      buf = socket.recv(MaxPackSize) if not socket.closed?
                    rescue
                      buf = ''
                    end
                    socket.write(buf) if (not socket.closed? and buf and (buf.size>0))
                    connection = connection_of_node(node)
                  end
                else
                  conn_state = CS_Connected
                  conn_mode = 0
                  #p "serv: conn_mode: "+ conn_mode.inspect
                  connection = Connection.new(host_name, host_ip, port, proto, node, conn_mode, conn_state)
                  #Thread.critical = true
                  $connections << connection
                  #Thread.critical = false
                  connection = connection_of_node(node)
                  if connection
                    connection.send_thread = Thread.current
                    connection.socket = socket
                    connection.post_init
                    connection.stage = ST_IpAllowed
                    #p "server: connection="+ connection.inspect
                    #p "server: $connections"+ $connections.inspect
                    #p 'LIS_SOCKET: '+socket.methods.inspect
                    start_exchange_cicle(node)
                    p "END LISTEN SOKET CLIENT!!!"
                  else
                    p "Не удалось добавить подключенного в список!!!"
                  end
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
        $listen_btn.label = _('Not listen')
        $listen_thread = nil
      end
    else
      p server = $listen_thread[:listen_server_socket]
      $listen_thread[:need_to_listen] = false
      #server.close if not server.closed?
      #$listen_thread.join(2) if $listen_thread
      #$listen_thread.exit if $listen_thread
    end
  end

  # Create or find connection with necessary node
  # RU: Создает или находит соединение с нужным узлом
  def self.start_or_find_connection(node, persistent=false, wait_connection=false, need_connect=true)
    connection = connection_of_node(node)
    #p "start_or_find_conn00: connection="+ connection.inspect
    if (not connection) or (connection and (connection.conn_state==CS_Disconnected) and not connection.socket)
      conn_state = CS_Disconnected
      conn_mode = CM_Hunter
      conn_mode = conn_mode | CM_Persistent if persistent
      host, port, proto = decode_node(node)
      if connection
        connection.conn_mode  = conn_mode
        connection.conn_state = conn_state
        #p "start_or_find_conn: !!!!! OLD CONNECTION="+ connection.to_s
      else
        connection = Connection.new(host, host, port, proto, node, conn_mode, conn_state)
        #Thread.critical = true
        $connections << connection
        #Thread.critical = false
        connection = connection_of_node(node)
        #p "start_or_find_conn: !!!!! NEW CONNECTION="+ connection.to_s
      end
      if connection and need_connect
        connection.conn_state  = CS_Connecting
        connection.send_thread = Thread.new do
          connection.send_thread = Thread.current
          #p "start_or_find_conn: THREAD connection="+ connection.inspect
          #p "start_or_find_conn: THREAD $connections"+ $connections.inspect
          host, port, proto = decode_node(node)
          conn_state = CS_Disconnected
          begin
            socket = TCPSocket.open(host, port)
            conn_state = CS_Connected
            connection.host_ip = socket.addr[2]
          rescue #IO::WaitReadable, Errno::EINTR
            socket = nil
            #p "!!Conn Err!!"
            log_message(LM_Warning, "Не удается подключиться к: "+host+':'+port.to_s)
          end
          connection.conn_state = conn_state
          if socket
            connection.socket = socket
            connection.post_init
            connection.node = encode_node(connection.host_ip, connection.port, connection.proto)
            connection.dialog.online_button.active = true if connection.dialog
            #p "start_or_find_conn1: connection="+ connection.inspect
            #p "start_or_find_conn1: $connections"+ $connections.inspect
            # Вызвать активный цикл собработкой данных
            log_message(LM_Info, "Подключился к серверу: "+socket.to_s)
            start_exchange_cicle(node)
            socket.close if not socket.closed?
            log_message(LM_Info, "Отключился от сервера: "+socket.to_s)
          end
          connection.socket = nil
          connection.dialog.online_button.active = false if connection.dialog
          p "END HUNTER CLIENT!!!!"
          if (connection.conn_mode & CM_Persistent) == 0
            #Thread.critical = true
            $connections.delete(connection)
            #Thread.critical = false
          end
          connection.send_thread = nil
        end
        while wait_connection and connection and (connection.conn_state==CS_Connecting)
          sleep 0.05
          #Thread.pass
          #Gtk.main_iteration
          connection = connection_of_node(node)
        end
        #p "start_or_find_con: THE end! CONNECTION="+ connection.to_s
        #p "start_or_find_con: THE end! wait_connection="+wait_connection.to_s
        #p "start_or_find_con: THE end! conn_state="+conn_state.to_s
        connection = connection_of_node(node)
      end
    end
    connection
  end

  # Stop connection with a node
  # RU: Останавливает соединение с заданным узлом
  def self.stop_connection(node, wait_disconnect=true)
    connection = connection_of_node(node)
    if connection and (connection.conn_state != CS_Disconnected)
      p "stop_connection: 1"
      connection.conn_state = CS_Stoping
      p "stop_connection: 2"
      while wait_disconnect and (connection.conn_state != CS_Disconnected)
        sleep 0.05
        #Thread.pass
        #Gtk.main_iteration
        connection = connection_of_node(node)
      end
      p "stop_connection: 3"
      connection = connection_of_node(node)
    end
    connection and (connection.conn_state != CS_Disconnected) and wait_disconnect
  end

  # Form node marker
  # RU: Сформировать маркер узла
  def self.encode_node(host, port, proto)
    node = host+':'+port.to_s+proto
  end

  # Unpack node marker
  # RU: Распаковать маркер узла
  def self.decode_node(node)
    i = node.index(':')
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

  # Searching a node by current record in treeview
  # RU: Поиск узла по текущей записи в таблице
  def self.define_node_by_current_record(treeview)
    # it's still a hack!
    panobject = nil
    panobject = treeview.panobject if treeview.instance_variable_defined?('@panobject')
    node = nil
    if panobject.ider=='Node'
      path, column = treeview.cursor
      if path != nil
        store = treeview.model
        sel = nil
        id = nil
        iter = store.get_iter(path)
        id = iter[0].to_s
        sel = panobject.select('id='+id)
        p sel = sel[0]

        p domain = panobject.field_val('domain', sel)
        p addr = panobject.field_val('addr', sel)
        p tport = panobject.field_val('tport', sel)

        domain = addr if domain == ''
        node = encode_node(domain, tport, 'tcp')
      end
    else
      node = encode_node($host, $port, 'tcp')
    end
    node
  end

  $hunter_thread = nil

  # Start hunt
  # RU: Начать охоту
  def self.hunt_nodes
    if $hunter_thread == nil
      panobject = PandoraModel.const_get('Node')
      p panobject
      $hunter_thread = Thread.new do
        host = '127.0.0.1'
        port = 5577
        proto = 'tcp'
        node = encode_node(host, port, proto)
        connection = start_or_find_connection(node)
        p connection
      end
    else
      $hunter_thread.exit
      $hunter_thread = nil
    end
  end

  # Add block to queue for send
  # Добавление блока в очередь на отправку
  def self.add_block_to_queue(block, queue)
    p "add_block_to_queue: queue[]: "+queue.inspect
    p "add_block_to_queue: block[]: "+block.inspect
    if queue[1]<MaxQueue
      queue[1] += 1
    else
      queue[1] = 0
    end
    queue[2][queue[1]] = block
    p "add_block_to_queue: finish! queue[]: "+queue.inspect
  end

  # Connection state flags
  # RU: Флаги состояния соединения
  CSF_Message    = 1
  CSF_Media      = 2
  CSF_Quit       = 4

  # Send message to node
  # RU: Отправляет сообщение на узел
  def self.send_mes_to_node(mes, node)
    sended = false
    #p 'send_mes_to_node: mes: [' +mes+'], start_or_find...'
    connection = start_or_find_connection(node, true, true)
    if connection and (connection.conn_state==CS_Connected)
      #p "send_mes_to_node: connection="+connection.inspect
      mes_queue = connection.send_mes
      #p "send_mes_to_node: mes_queue: "+mes_queue.inspect
      add_block_to_queue(mes, mes_queue)
      sended = true
      # update send state
      connection.send_state = connection.send_state | CSF_Message
    else
      p "send_mes_to_node: not connected"
    end
    #p 'end send_mes_to_node [' +mes+']'
    sended
  end

  class TalkScrolledWindow < Gtk::ScrolledWindow
    attr_accessor :node, :online_button, :snd_button, :vid_button, :talkview, :editbox, \
      :area, :pipeline1, :pipeline2, :connection, :area2, :ximagesink, :xvimagesink

    # Play media stream
    # RU: Запустить медиа поток
    def play_pipeline
      pipeline1.play if pipeline1
      pipeline2.play if pipeline2
    end

    # Stop media stream
    # RU: Остановить медиа поток
    def stop_pipeline
      pipeline2.stop if pipeline2
      pipeline1.stop if pipeline1
      ximagesink.xwindow_id = 0 if ximagesink
      xvimagesink.xwindow_id = 0 if xvimagesink
      area2.hide
      area2.show
    end

    def init_media
      if not pipeline1
        #begin
          @pipeline1 = Gst::Pipeline.new
          @pipeline2 = Gst::Pipeline.new

          webcam = Gst::ElementFactory.make('v4l2src')
          webcam.decimate=3

          capsfilter = Gst::ElementFactory.make('capsfilter')
          capsfilter.caps = Gst::Caps.parse('video/x-raw-rgb,width=320,height=240')

          ffmpegcolorspace1 = Gst::ElementFactory.make('ffmpegcolorspace')

          tee = Gst::ElementFactory.make('tee')
          tee.name = 'tee1'

          queue1 = Gst::ElementFactory.make('queue')

          @xvimagesink = Gst::ElementFactory.make('xvimagesink');
          xvimagesink.sync = true

          #queue2 = Gst::ElementFactory.make('queue')

          vp8enc = Gst::ElementFactory.make('vp8enc')
          vp8enc.max_latency=0.5

          appsink = Gst::ElementFactory.make('appsink')

          appsrc = Gst::ElementFactory.make('appsrc')
          appsrc.caps = Gst::Caps.parse('caps=video/x-vp8,width=320,height=240,framerate=30/1,pixel-aspect-ratio=1/1')
          p appsrc.max_bytes
          p appsrc.blocksize
          appsrc.signal_connect('need-data') do |src, length|
            buf1 = appsink.pull_buffer
            if buf1 != nil
              buf2 = Gst::Buffer.new
              buf2.data = String.new(buf1.data)
              buf2.timestamp = Time.now.to_i * Gst::NSECOND

              #buf2.caps = Gst::Caps.parse('caps=video/x-vp8,width=320,height=240,framerate=30/1,pixel-aspect-ratio=1/1')
              #p buf2.size
              src.push_buffer(buf2)
              #src.signal_emit('enough-data')
            end
          end

          vp8dec = Gst::ElementFactory.make('vp8dec')

          ffmpegcolorspace2 = Gst::ElementFactory.make('ffmpegcolorspace')

          @ximagesink = Gst::ElementFactory.make('ximagesink');
          ximagesink.sync = false

          #pipeline1.add(webcam, capsfilter, ffmpegcolorspace1, vp8enc, appsink)
          #webcam >> capsfilter >> ffmpegcolorspace1 >> vp8enc >> appsink
          #pipeline1.add(webcam, capsfilter, ffmpegcolorspace1, tee, queue1, xvimagesink, queue2, vp8enc, appsink)
          pipeline1.add(webcam, capsfilter, ffmpegcolorspace1, tee, vp8enc, appsink, queue1, xvimagesink)
          webcam >> capsfilter >> ffmpegcolorspace1 >> tee >> vp8enc >> appsink
          tee >> queue1 >> xvimagesink
          #tee >> queue2 >> vp8enc >> appsink

          #tee_src_pad = tee.get_request_pad("src%d")
          #ghost_pad = Gst::GhostPad.new('src', tee_src_pad)
          #queue2.add_pad(ghost_pad)

          pipeline2.add(appsrc, vp8dec, ffmpegcolorspace2, ximagesink)
          appsrc >> vp8dec >> ffmpegcolorspace2 >> ximagesink

          ximagesink.xwindow_id = area.window.xid if not area.destroyed? and (area.window != nil)
          pipeline2.bus.add_watch do |bus, message|
            if ((message != nil) and (message.structure != nil) and (message.structure.name != nil) \
              and (message.structure.name == 'prepare-xwindow-id'))
            then
              message.src.set_xwindow_id(area.window.xid) if not area.destroyed? and (area.window != nil)
            end
            true
          end
          area.signal_connect('expose-event') do
            ximagesink.xwindow_id = area.window.xid if not area.destroyed? and (area.window != nil)
          end

          xvimagesink.xwindow_id = area2.window.xid if not area2.destroyed? and (area2.window != nil)
          pipeline1.bus.add_watch do |bus, message|
            if ((message != nil) and (message.structure != nil) and (message.structure.name != nil) \
              and (message.structure.name == 'prepare-xwindow-id'))
            then
              message.src.set_xwindow_id(area2.window.xid) if not area2.destroyed? and (area2.window != nil)
            end
            true
          end
          area2.signal_connect('expose-event') do
            xvimagesink.xwindow_id = area2.window.xid if not area2.destroyed? and (area2.window != nil)
          end

        #rescue
        #  log_message(LM_Warning, _('Multimedia init exception'))
        #  vid_button.active = false
        #end
      end
    end

  end


  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(node, title=_('Talk'))

    $notebook.children.each do |child|
      if (child.is_a? TalkScrolledWindow) and (child.node==node)
        $notebook.page = $notebook.children.index(child)
        return child
      end
    end

    sw = TalkScrolledWindow.new(nil, nil)
    sw.node = node

    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.name = title
    #sw.add(treeview)
    sw.border_width = 0;

    image = Gtk::Image.new(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::MENU)
    image.set_padding(2, 0)

    hpaned = Gtk::HPaned.new
    sw.add_with_viewport(hpaned)

    vpaned1 = Gtk::VPaned.new
    vpaned2 = Gtk::VPaned.new

    area = Gtk::DrawingArea.new
    area.set_size_request(320, 240)
    area.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
    sw.area = area

    hbox = Gtk::HBox.new

    bbox = Gtk::HBox.new
    bbox.border_width = 5
    bbox.spacing = 5

    online_button = Gtk::CheckButton.new(_('Online'), true)
    online_button.signal_connect('toggled') do |widget, event|
      if widget.active?
        p "connect!!!"
        connection = connection_of_node(node)
        if not connection or (connection.conn_state == CS_Disconnected)
          connection = start_or_find_connection(node, true, true, true)
        end
        #widget.active = connection and (connection.conn_state != CS_Disconnected)
        p connection.conn_state
      else
        p "disconnect!!!"
        stop_connection(node, true)
        p "disconnect!!! 222"
        #widget.active = stopped
      end
    end
    bbox.pack_start(online_button, false, false, 0)

    snd_button = Gtk::CheckButton.new(_('Sound'), true)
    snd_button.signal_connect('toggled') do |widget, event|
      p 'Sound: '+widget.active?.to_s
    end
    bbox.pack_start(snd_button, false, false, 0)

    vid_button = Gtk::CheckButton.new(_('Video'), true)
    vid_button.signal_connect('toggled') do |widget, event|
      send_mes_to_node('video:'+widget.active?.to_s+':', node)
      if widget.active?
        sw.init_media
        sw.play_pipeline
      else
        sw.stop_pipeline
        #if (sw.area2 and (not sw.area2.destroyed?) and sw.area2.drawable?)
        #  sw.area2.queue_draw
        #end
      end
    end

    bbox.pack_start(vid_button, false, false, 0)

    hbox.pack_start(bbox, false, false, 1.0)

    vpaned1.pack1(area, true, false)
    vpaned1.pack2(hbox, false, true)
    vpaned1.set_size_request(350, 270)

    talkview = Gtk::TextView.new
    talkview.set_size_request(200, 200)
    talkview.wrap_mode = Gtk::TextTag::WRAP_WORD
    #view.cursor_visible = false
    #view.editable = false

    talkview.buffer.create_tag("red", "foreground" => "red")
    talkview.buffer.create_tag("blue", "foreground" => "blue")
    talkview.buffer.create_tag("red_bold", "foreground" => "red", 'weight' => Pango::FontDescription::WEIGHT_BOLD)
    talkview.buffer.create_tag("blue_bold", "foreground" => "blue",  'weight' => Pango::FontDescription::WEIGHT_BOLD)

    editbox = Gtk::TextView.new
    editbox.wrap_mode = Gtk::TextTag::WRAP_WORD
    editbox.set_size_request(200, 70)

    editbox.grab_focus

    # because of bug - doesnt work Enter at 'key-press-event'
    editbox.signal_connect('key-release-event') do |widget, event|
      if (event.hardware_keycode==36) or \
        [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      then
        widget.signal_emit('key-press-event', event)
        false
      end
    end

    editbox.signal_connect('key-press-event') do |widget, event|
      if (event.hardware_keycode==36) or \
        [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      then
        if editbox.buffer.text != ''
          mes = editbox.buffer.text
          editbox.buffer.text = ''
          t = Time.now
          talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
          talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', "red")
          talkview.buffer.insert(talkview.buffer.end_iter, 'You:', "red_bold")
          talkview.buffer.insert(talkview.buffer.end_iter, ' '+mes)

          if send_mes_to_node(mes, node)
            editbox.buffer.text = ''
          end
        end
        true
      elsif (event.hardware_keycode==9) or #Esc pressed
        (Gdk::Keyval::GDK_Escape==event.keyval)
      then
        editbox.buffer.text = ''
        false
      else
        false
      end
    end

    hpaned2 = Gtk::HPaned.new
    area2 = Gtk::DrawingArea.new
    sw.area2 = area2
    area2.set_size_request(120, 90)
    area2.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))
    hpaned2.pack1(area2, false, true)
    hpaned2.pack2(editbox, true, true)

    talksw = Gtk::ScrolledWindow.new(nil, nil)
    talksw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    talksw.add(talkview)

    vpaned2.pack1(talksw, true, true)

    vpaned2.pack2(hpaned2, false, true)

    hpaned.pack1(vpaned1, false, true)
    hpaned.pack2(vpaned2, true, true)

    sw.online_button    = online_button
    sw.snd_button       = snd_button
    sw.vid_button       = vid_button
    sw.talkview         = talkview
    sw.editbox          = editbox

    area.signal_connect('visibility_notify_event') do |widget, event_visibility|
      case event_visibility.state
        when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
          sw.play_pipeline if vid_button.active?
        when Gdk::EventVisibility::FULLY_OBSCURED
          sw.stop_pipeline
      end
    end

    area.signal_connect('destroy') do
      sw.stop_pipeline
    end

    area.show

    connection = start_or_find_connection(node, true, false, false)
    connection.dialog = sw if connection

    label_box = TabLabelBox.new(image, title, sw, false, 0) do
      sw.stop_pipeline
      area.destroy

      connection = connection_of_node(node)
      if connection
        connection.dialog = nil
        connection.conn_mode = connection.conn_mode & (~CM_Persistent)
        if connection.conn_state == CS_Disconnected
          #Thread.critical = true
          $connections.delete(connection)
          #Thread.critical = false
        end
      end
    end

    page = $notebook.append_page(sw, label_box)
    sw.show_all
    $notebook.page = $notebook.n_pages-1
    editbox.grab_focus
    sw
  end

  # Menu event handler
  # RU: Обработчик события меню
  def self.do_menu_act(widget)
    case widget.name
      when 'Quit'
        $window.destroy
      when 'About'
        show_about
      when 'Close'
        if $notebook.page >= 0
          page = $notebook.get_nth_page($notebook.page)
          tab = $notebook.get_tab_label(page)
          close_btn = tab.children[tab.children.size-1].children[0]
          close_btn.clicked
        end
      when 'Create','Edit','Delete','Copy'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          edit_panobject(treeview, widget.name) if treeview.is_a? PandoraGUI::SubjTreeView
        end
      when 'Clone'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          panobject = treeview.panobject
          panobject.update(nil, nil, nil)
        end
      when 'Listen'
        start_or_stop_listen
      when 'Connect'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          node = define_node_by_current_record(treeview)
          start_or_find_connection(node)
        end
      when 'Hunt'
        hunt_nodes
      when 'Talk'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          node = define_node_by_current_record(treeview)
          show_talk_dialog(node)
        end
      when 'Authorize'
        key = current_key(true)

        ##PandoraKernel.save_as_language($lang)
        #keys = generate_key('RSA', 2048)
        ##keys[1] = nil
        #keys[2] = 'RSA'
        #keys[3] = '12345'
        #p '=====generate_key:'+keys.inspect
        #key = init_key(keys)
        p '=====curr_key:'+key.inspect
        data = 'Test string!'
        sign = make_sign(key, data)
        p '=====make_sign:'+sign.inspect
        p 'verify_sign='+verify_sign(key, data, sign).inspect
        p 'verify_sign2='+verify_sign(key, data+'aa', sign).inspect

        encrypted = encrypt(key.public_key, data)
        p '=====encrypted:'+encrypted.inspect
        decrypted = decrypt(key, encrypted)
        p '=====decrypted:'+decrypted.inspect
      when 'Wizard'
        #typ, count = encode_pan_type(PT_Str, 0x1FF)
        #p decode_pan_type(typ)
        #p pson = rubyobj_to_pson_elem(Time.now)
        #p elem = pson_elem_to_rubyobj(pson)
        #p pson = rubyobj_to_pson_elem(12345)
        #p elem = pson_elem_to_rubyobj(pson)
        #p pson = rubyobj_to_pson_elem({'zzz'=>'bcd', 'ann'=>['789',123], :bbb=>'dsd'})
        #p elem = pson_elem_to_rubyobj(pson)

        p pson = hash_to_pson({:first_name=>'Ivan', :last_name=>'Inavov', 'ddd'=>555})
        p hash = pson_to_hash(pson)

      else
        panobj_id = widget.name
        if PandoraModel.const_defined? panobj_id
          panobject_class = PandoraModel.const_get(panobj_id)
          show_panobject_list(panobject_class, widget)
        else
          log_message(LM_Warning, _('Menu handler is not defined yet')+' ['+panobj_id+']')
        end
    end
  end

  # Menu structure
  # RU: Структура меню
  def self.menu_items
    [
    [nil, nil, _('_World')],
    ['Person', Gtk::Stock::ORIENTATION_PORTRAIT, _('People')],
    ['Community', nil, _('Communities')],
    ['-', nil, '-'],
    ['Country', nil, _('States')],
    ['City', nil, _('Towns')],
    ['Street', nil, _('Streets')],
    ['Thing', nil, _('Things')],
    ['Activity', nil, _('Activities')],
    ['Currency', nil, _('Currency')],
    ['Word', Gtk::Stock::SPELL_CHECK, _('Words')],
    ['Language', nil, _('Languages')],
    ['-', nil, '-'],
    ['Article', nil, _('Articles')],
    ['Blob', Gtk::Stock::HARDDISK, _('Files')], #Gtk::Stock::FILE
    ['-', nil, '-'],
    ['Address', nil, _('Addresses')],
    ['Contact', nil, _('Contacts')],
    ['Document', nil, _('Documents')],
    ['-', nil, '-'],
    ['Relation', nil, _('Relations')],
    ['Opinion', nil, _('Opinions')],
    [nil, nil, _('_Bussiness')],
    ['Member', nil, _('Members')],
    ['Company', nil, _('Companies')],
    ['Storage', nil, _('Storages')],
    ['Product', nil, _('Products')],
    ['Service', nil, _('Services')],
    ['-', nil, '-'],
    ['Ad', nil, _('Ads')],
    ['Order', nil, _('Orders')],
    ['Deal', nil, _('Deals')],
    ['Waybill', nil, _('Waybills')],
    ['Debt', nil, _('Debts')],
    ['Guaranty', nil, _('Guaranties')],
    ['-', nil, '-'],
    ['Position', nil, _('Positions')],
    ['Contract', nil, _('Contracts')],
    ['Payment', nil, _('Payments')],
    ['Property', nil, _('Property')],
    ['Report', nil, _('Reports')],
    [nil, nil, _('_Region')],
    ['Resource', nil, _('Resources')],
    ['-', nil, '-'],
    ['Law', nil, _('Laws')],
    ['Project', nil, _('Projects')],
    ['Resolution', nil, _('Resolutions')],
    ['-', nil, '-'],
    ['Contribution', nil, _('Contributions')],
    ['Expenditure', nil, _('Expenditures')],
    ['-', nil, '-'],
    ['Offense', nil, _('Offenses')],
    ['Punishment', nil, _('Punishments')],
    [nil, nil, _('_Pandora')],
    ['Parameter', Gtk::Stock::PREFERENCES, _('Parameters')],
    ['-', nil, '-'],
    ['Key', nil, _('Keys')],
    ['Sign', nil, _('Signs')],
    ['Node', Gtk::Stock::NETWORK, _('Nodes')],
    ['Message', nil, _('Messages')],
    ['Patch', nil, _('Patches')],
    ['Event', nil, _('Events')],
    ['Repository', nil, _('Repositories')],
    ['-', nil, '-'],
    ['Authorize', Gtk::Stock::DIALOG_AUTHENTICATION, _('Authorize')],
    ['Listen', Gtk::Stock::CONNECT, _('Listen')],
    ['Hunt', Gtk::Stock::REFRESH, _('Hunt')],
    ['Search', Gtk::Stock::FIND, _('Search')],
    ['-', nil, '-'],
    ['Profile', Gtk::Stock::HOME, _('Profile')],
    ['Wizard', Gtk::Stock::PROPERTIES, _('Wizards')],
    ['-', nil, '-'],
    ['Quit', Gtk::Stock::QUIT, _('_Quit'), '<control>Q', 'Do quit'],
    ['Close', Gtk::Stock::CLOSE, _('_Close'), '<control>W', 'Close tab'],
    ['-', nil, '-'],
    ['About', Gtk::Stock::ABOUT, _('_About'), nil, 'About']
    ]
  end

  # Creating menu item from its description
  # RU: Создание пункта меню по его описанию
  def self.create_menu_item(mi)
    if mi[0] == '-'
      menuitem = Gtk::SeparatorMenuItem.new
    else
      if mi[1] == nil
        menuitem = Gtk::MenuItem.new(mi[2])
      else
        menuitem = Gtk::ImageMenuItem.new(mi[1])
        label = menuitem.children[0]
        label.set_text(mi[2], true)
      end
      if mi[3] != nil
        key, mod = Gtk::Accelerator.parse(mi[3])
        menuitem.add_accelerator('activate', $group, key, mod, Gtk::ACCEL_VISIBLE)
      end
      menuitem.name = mi[0]
      menuitem.signal_connect('activate') { |widget| do_menu_act(widget) }
    end
    menuitem
  end

  def self.add_buttons_from_menu_to_toolbar(menu, toolbar)
    if menu != nil
      menu.each do |child|
        if child.submenu != nil
          add_buttons_from_menu_to_toolbar(child.submenu, toolbar)
        elsif child.is_a? Gtk::ImageMenuItem
          label = child.children[0]
          image = Gtk::Image.new(child.image.stock, child.image.icon_size)
          btn = Gtk::ToolButton.new(image, label.text)
          new_api = false
          begin
            btn.tooltip_text = btn.label
            new_api = true
          rescue Exception
          end
          btn.signal_connect('clicked') { child.activate }
          if new_api
            toolbar.add(btn)
          else
            toolbar.append(btn, btn.label, btn.label)
          end
        end
      end
    end
  end

  # Show main Gtk window
  # RU: Показать главное окно Gtk
  def self.show_main_window
    $window = Gtk::Window.new('Pandora')
    begin
      $window.icon = Gdk::Pixbuf.new(File.join($pandora_view_dir, 'pandora.ico'))
      Gtk::Window.default_icon = $window.icon
    rescue Exception
    end

    menubar = Gtk::MenuBar.new
    $group = Gtk::AccelGroup.new
    menu = nil
    menu_items.each do |mi|
      if mi[0]==nil or menu==nil
        menuitem = Gtk::MenuItem.new(mi[2])
        menubar.append(menuitem)
        menu = Gtk::Menu.new
        menuitem.set_submenu(menu)
      else
        menuitem = create_menu_item(mi)
        menu.append(menuitem)
      end
    end
    $window.add_accel_group($group)

    toolbar = Gtk::Toolbar.new
    toolbar.toolbar_style = Gtk::Toolbar::Style::ICONS
    add_buttons_from_menu_to_toolbar(menubar, toolbar)

    $notebook = Gtk::Notebook.new

    $notebook.signal_connect('switch-page') do |widget, page, page_num|
      sw = $notebook.get_nth_page(page_num)
      #treeview = sw.children[0]
      sw.stop_pipeline if sw.is_a? PandoraGUI::TalkScrolledWindow
    end

    $view = Gtk::TextView.new
    $view.can_focus = false
    $view.has_focus = false
    $view.receives_default = true
    $view.border_width = 0

    statusbar = Gtk::Statusbar.new
    PandoraGUI.set_statusbar_text(statusbar, _('Base directory: ')+$pandora_base_dir)
    btn = Gtk::Button.new(_('Not logged'))
    btn.relief = Gtk::RELIEF_NONE
    statusbar.pack_start(btn, false, false, 2)
    statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
    $listen_btn = Gtk::Button.new(_('Not listen'))
    $listen_btn.relief = Gtk::RELIEF_NONE
    statusbar.pack_start($listen_btn, false, false, 2)

    sw = Gtk::ScrolledWindow.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.shadow_type = Gtk::SHADOW_IN
    sw.add($view)
    sw.border_width = 1;
    sw.set_size_request(-1, 40)

    #frame = Gtk::Frame.new('Статус')
    #frame.border_width = 0
    #frame.add(sw)
    #frame.set_size_request(-1, 60)

    vpaned = Gtk::VPaned.new
    vpaned.border_width = 2
    vpaned.pack1($notebook, true, true)
    vpaned.pack2(sw, false, true)

    vbox = Gtk::VBox.new
    vbox.pack_start(menubar, false, false, 0)
    vbox.pack_start(toolbar, false, false, 0)
    vbox.pack_start(vpaned, true, true, 0)
    vbox.pack_start(statusbar, false, false, 0)

    $window.add(vbox)

    $window.set_default_size(640, 420)
    $window.maximize
    $window.show_all
    $window.signal_connect('destroy') do
      #sw.stop_pipeline
      Gtk.main_quit
    end

    $window.signal_connect('key-press-event') do |widget, event|
      if ((event.hardware_keycode==24) and event.state.control_mask?) or #Ctrl+Q
        ((event.hardware_keycode==53) and event.state.mod1_mask?) or #Alt+X
        ([Gdk::Keyval::GDK_q, Gdk::Keyval::GDK_Q].include?(event.keyval) and event.state.control_mask?) or
        ([Gdk::Keyval::GDK_x, Gdk::Keyval::GDK_X].include?(event.keyval) and event.state.mod1_mask?)
      then
        $window.destroy
      end
      false
    end

    @statusicon = nil

    $window.signal_connect('window-state-event') do |widget, event_window_state|
      if (event_window_state.changed_mask == Gdk::EventWindowState::ICONIFIED) \
        and ((event_window_state.new_window_state & Gdk::EventWindowState::ICONIFIED)>0)
      then
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          #treeview = sw.children[0]
          sw.stop_pipeline if sw.is_a? TalkScrolledWindow
        end
        if widget.visible? and widget.active?
          $window.hide
          #$window.skip_taskbar_hint = true
          if @statusicon == nil
            @statusicon = Gtk::StatusIcon.new!({'visible'=>false})
            if $window.icon == nil
              @statusicon.set_icon_name(Gtk::Stock::DIALOG_INFO)
            else
              @statusicon.pixbuf = $window.icon
            end
            @statusicon.title = $window.title
            @statusicon.tooltip = $window.title
            @statusicon.signal_connect('activate') do
              #$window.skip_taskbar_hint = false
              $window.deiconify
              $window.show_all
              $window.present
              @statusicon.visible = false
            end
          end
          @statusicon.visible = true
        end
      end
    end

    Gtk.main
  end

end


# ==============================================================================

# Some module settings
# RU: Некоторые настройки модулей
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# == Running the Pandora!
# == RU: Запуск Пандоры!
#$lang = 'en'
PandoraKernel.load_language($lang)
PandoraModel.load_model_from_xml($lang)
PandoraGUI.show_main_window


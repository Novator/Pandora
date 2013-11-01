#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Utilites module of Pandora
# RU: Вспомогательный модуль Пандоры
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
require 'gst'

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
  
  # Default values of variables
  # RU: Значения переменных по умолчанию
  $host = '127.0.0.1'
  $port = 5577
  $base_index = 0
  $poly_launch = true
  $pandora_parameters = []
  
  # Paths and files  ('join' gets '/' for Linux and '\' for Windows)
  # RU: Пути и файлы ('join' дает '/' для Линукса и '\' для Винды)
  $pandora_root_dir = Dir.pwd                                       # Current Pandora directory
  #$pandora_root_dir = File.expand_path('..',  __FILE__)
  $pandora_base_dir = File.join($pandora_root_dir, 'base')            # Default database directory
  $pandora_view_dir = File.join($pandora_root_dir, 'view')            # Media files directory
  $pandora_model_dir = File.join($pandora_root_dir, 'model')          # Model description directory
  $pandora_lang_dir = File.join($pandora_root_dir, 'lang')            # Languages directory
  $pandora_util_dir = File.join($pandora_root_dir, 'util')            # Utilites directory
  $pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Default database file
  $lang = 'ru'
  
    
  LM_Error    = 0
  LM_Warning  = 1
  LM_Info     = 2
  LM_Trace    = 3
  
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
  
  # Log message
  # RU: Добавить сообщение в лог
  def self.log_message(level, mes)
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
    attr_accessor :adapter
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
    elsif ((not pname) or (pname=='')) and sname
      case $lang
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

  def self.kind_from_panhash(panhash)
    kind = panhash[0].ord if (panhash.is_a? String) and (panhash.bytesize>0)
  end

  def self.lang_from_panhash(panhash)
    lang = panhash[1].ord if (panhash.is_a? String) and (panhash.bytesize>1)
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
          :value=>create_default_param(type, row[PF_Setting]), :type=>type,
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

  def self.calc_midnight(time)
    res = nil
    if time
      time = Time.at(time) if (time.is_a? Integer)
      vals = time.to_a
      y, m, d = [vals[5], vals[4], vals[3]]  #current day
      res = Time.local(y, m, d)
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
          #p '[d, m, s]='+[d, m, s].inspect
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

  def self.simplify_coord(val)
    val = val.round(1)
  end

  class RoundQueue < Mutex
    # Init empty queue. Poly read is possible
    # RU: Создание пустой очереди. Возможно множественное чтение
    attr_accessor :queue, :write_ind, :read_ind

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
    data = AsciiString.new(data) if data.is_a? String
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

  $poor_cairo_context = false

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
      if (not $poor_cairo_context)
        begin
          drawing = Gdk::Pixmap.new(nil, width, height, 24)
          cr = drawing.create_cairo_context
        rescue Exception
          $poor_cairo_context = true
        end
      end
      if $poor_cairo_context
        drawing = Cairo::ImageSurface.new(width, height)
        cr = Cairo::Context.new(drawing)
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

  def self.is_64bit_os?
    # ENV.has_key?('ProgramFiles(x86)') && File.exist?(ENV['ProgramFiles(x86)']) && \
    # File.directory?(['ProgramFiles(x86)'])
    # (1.size > 4) ? true : false
    # ENV.has_key?('ProgramFiles(x86)')
    (['a'].pack('P').bytesize > 4) ? true : false
  end

  $mp3_player = 'mpg123'
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

  $create_process_class = nil

  def self.win_exec(cmd)
    if init_win32api
      if not $create_process_class
        $create_process_class = Win32API.new('kernel32', 'CreateProcess', \
          ['P', 'P', 'L', 'L', 'L', 'L', 'L', 'P', 'P', 'P'], 'L')
      end
      if $create_process_class
        si = 0.chr*256
        pi = 0.chr*256
        res = $create_process_class.call(nil, cmd, 0, 0, 0, 8, \
          0, nil, si, pi)
      end
    end
  end

  $poly_play   = false
  $play_thread = nil
  Default_Mp3 = 'message.mp3'

  def self.play_mp3(filename, path=nil)
    if ($poly_play or (not $play_thread)) \
    and $statusicon and (not $statusicon.destroyed?) \
    and $statusicon.play_sounds and (filename.is_a? String) and (filename.size>0)
      $play_thread = Thread.new do
        begin
          path ||= $pandora_view_dir
          filename += '.mp3' unless filename.index('.')
          filename ||= Default_Mp3
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

  gst_vers = Gst.version
  $gst_old = ((gst_vers.is_a? Array) and (gst_vers[0]==0))

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


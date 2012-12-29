#!/usr/bin/env ruby
# encoding: utf-8

# The Pandora. Free decentralized information system
# RU: Пандора. Децентрализованная информационная система
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк
#
# coding: utf-8
$KCODE='u'
#Encoding.default_external = 'UTF-8'
#Encoding.default_internal = 'UTF-8'

# Platform detection
# RU: Определение платформы
def os_family
  case RUBY_PLATFORM
    when /ix/i, /ux/i, /gnu/i, /sysv/i, /solaris/i, /sunos/i, /bsd/i
      "unix"
    when /win/i, /ming/i
      "windows"
    else
      "other"
  end
end

# Paths and files  ('join' gets '/' for Linux and '\' for Windows)
# RU: Пути и файлы ('join' дает '/' для Линукса и '\' для Винды)
if os_family != 'windows'
  $pandora_root_dir = Dir.pwd                                       # Current Pandora directory
else
  $pandora_root_dir = '.'
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

# GStreamer is a media library
# RU: Обвязка для медиа библиотеки GStreamer
begin
  require 'gst'
  $gst_on = true
rescue Exception
  $gst_on = false
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
$port = '5577'
$base_index = 0
$hunt_list = {}

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки
arg = nil
while ARGV.length >0
  val = ARGV.shift
  if val.is_a? String and (val[0,1]=='-')
    arg = val
  else
    case arg
      when '-h','--host'
        $host = val
      when '-p','--port'
        $port = val
      when '-bi'
        $base_index = val.to_i
      when '--help', '/?', '-?'
        puts 'Usage: ruby pandora.rb [-h localaddress] [-p localport] [-bi baseindex]'
    end
    arg = nil
  end
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
  # RU: Сохранить фразы для перевода
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

  # Type translation
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
      when '',nil
        'NUMBER'
      when 'Blob'
        'BLOB'
      else
        'NUMBER'
    end
  end

  # Fields definitions to SQL table definitions of SQLite
  # RU: Описание таблицы SQLite из описания полей
  def self.subj_fld_to_sqlite_tab(subj_fld)
    res = ''
    subj_fld.each do |f|
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
      tab_def = PandoraKernel::subj_fld_to_sqlite_tab(def_flds[table_name])
      p tab_def
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
        sql = 'SELECT * from '+table_name
        if (filter != nil) and (filter > '')
          sql = sql + ' where '+filter end
        @selection = db.execute(sql)
      end
    end
    def update_table(table_name, fldvalues, fldnames=nil, filter=nil)
      connect
      sql = ''
      if (fldvalues == nil) and (fldnames == nil) and (filter != nil)
        sql = 'DELETE FROM ' + table_name + ' where '+filter
      elsif fldvalues.is_a? Array and fldnames.is_a? Array
        if filter != nil
          fldvalues.each_with_index do |v,i|
            if fldnames[i] != nil
              sql = sql + ',' if i > 0
              sql = sql + ' ' + fldnames[i] + "='" + v + "'"
            end
          end
          sql = 'UPDATE ' + table_name + ' SET' + sql
          if (filter != nil) and (filter > '')
            sql = sql + ' where '+filter
          end
        else
          sql2 = ''
          fldvalues.each_with_index do |v,i|
            if fldnames[i] != nil
              sql = sql + ',' if i > 0
              sql2 = sql2 + ',' if i > 0
              sql = sql + fldnames[i]
              sql2 = sql2 + "'" + v + "'"
            end
          end
          sql = 'INSERT INTO ' + table_name + '(' + sql + ') VALUES(' + sql2 + ')'
        end
      end
      tfd = fields_table(table_name)
      if (tfd == nil) or (tfd == [])
        nil
      else
        p sql
        db.execute(sql)
      end
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
    def get_adapter(subj, table_ptr, recreate=false)
      #find db_ptr in db_list
      base_des = base_list[$base_index]
      if base_des[3] == nil
        adap = SQLiteDbSession.new
        adap.conn_param = base_des[2]
        base_des[3] = adap
      else
        adap = base_des[3]
      end
      table_name = table_ptr[1]
      adap.def_flds[table_name] = subj.def_fields
      if table_name==nil or table_name=='' then
        puts 'No table name for ['+subj.name+']'
      else
        adap.create_table(table_name, recreate)
        #adap.create_table(table_name, TRUE)
      end
      adap
    end
    def get_tab_select(subj, table_ptr, filter='')
      adap = get_adapter(subj, table_ptr)
      adap.select_table(table_ptr[1], filter)
    end
    def get_tab_update(subj, table_ptr, fldvalues, fldnames, filter='')
      recreate = ((fldvalues == nil) and (fldnames == nil) and (filter == nil))
      adap = get_adapter(subj, table_ptr, recreate)
      if not recreate
        adap.update_table(table_ptr[1], fldvalues, fldnames, filter)
      end
    end
    def get_tab_fields(subj, table_ptr)
      adap = get_adapter(subj, table_ptr)
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

  # Pandora's subject
  # RU: Субъект (справочник) Пандора
  class BaseSubject
    class << self
      @ider = 'BaseSubject'
      @name = 'Субъект Пандора'
      @tables = []
      @def_fields = []
      def ider
        @ider
      end
      def ider=(x)
        @ider = x
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
      def BaseSubject.repositories
        $repositories
      end
    end
    def ider
      self.class.ider
    end
    def ider=(x)
      self.class.ider = x
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
    #def initialize
    #  super
    #end
    def select(afilter='')
      self.class.repositories.get_tab_select(self, self.class.tables[0], afilter)
    end
    def update(afldvalues, afldnames, afilter='')
      self.class.repositories.get_tab_update(self, self.class.tables[0], afldvalues, afldnames, afilter)
    end
    def tab_fields
      self.class.repositories.get_tab_fields(self, self.class.tables[0])
    end
    def field_val(fld_name, sel_row=nil)
      if sel_row == nil
        '<no sel>'
      else
        @last_tab_fields = tab_fields if @last_tab_fields == nil
        i = @last_tab_fields.index(fld_name)
        res = nil
        res = sel_row[i] if i != nil
        res
      end
    end
    def field_des(fld_name)
      df = def_fields.detect{ |e| (e.is_a? Array) and (e[0].to_s == fld_name) or (e.to_s == fld_name) }
      df = df[1] if df.is_a? Array
      df = fld_name if df == nil
      df
    end
  end

end

# ==============================================================================
# == Pandora logic model
# == RU: Логическая модель Пандора
module PandoraModel

  # Pandora's document
  # RU: Документ Пандора
  class Subject < PandoraKernel::BaseSubject
    ider = 'Subject'
    name = "Документ Пандора"
  end

  # Composing pandora model definition from XML file
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
        subj_id = element.name
        new_subj = true
        flds = []
        if PandoraModel.const_defined? subj_id
          subject_class = PandoraModel.const_get(subj_id)
          subj_name = subject_class.name
          subj_tabl = subject_class.tables
          new_subj = false
          #p subject_class
        else
          subj_name = subj_id
          parent_class = element.attributes['parent']
          if (parent_class==nil) or (not(PandoraModel.const_defined? parent_class))
            parent_class = 'Subject'
          else
            PandoraModel.const_get(parent_class).def_fields.each do |f|
              flds << f
            end
          end
          module_eval('class '+subj_id+' < PandoraModel::'+parent_class+'; name = "'+subj_name+'"; end')
          subject_class = PandoraModel.const_get(subj_id)
          subject_class.def_fields = flds
          #p subject_class
          subject_class.ider = subj_id
          subj_tabl = subj_id
          subj_tabl = PandoraKernel::get_name_or_names(subj_tabl, true)
          subj_tabl.downcase!
          subject_class.tables = [['robux', subj_tabl], ['perm', subj_tabl]]
        end
        flds = subject_class.def_fields
        #p flds
        subj_name_en = element.attributes['name']
        subj_name = subj_name_en if (subj_name==subj_id) and (subj_name_en != nil) and (subj_name_en != '')
        subj_name_lang = element.attributes['name'+lang]
        subj_name = subj_name_lang if (subj_name_lang != nil) and (subj_name_lang != '')
        #puts subj_id+'=['+subj_name+']'
        subject_class.name = subj_name

        subj_tabl = element.attributes['table']
        subject_class.tables = [['robux', subj_tabl], ['perm', subj_tabl]] if subj_tabl != nil

        element.elements.each('*') do |sub_elem|
          seu = sub_elem.name.upcase
          if seu==sub_elem.name
            #p 'Функция не определена: ['+sub_elem.name+']'
          else
            i = 0
            while (i<flds.size) and (flds[i][0] != sub_elem.name) do i+=1 end
            if new_subj or (i<flds.size)
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
            else
              puts _('Property was not defined, ignored')+' /'+filename+':'+subj_id+'.'+sub_elem.name
            end
          end
        end
        #p flds
        #p "========"
        subject_class.def_fields = flds
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

  # Showing About dialog
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
    dlg.copyright = _('Freeware')+' 2012, '+_('Michael Galyuk')
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

  # Advanced dialog window
  # RU: Продвинутое окно диалога
  class AdvancedDialog < Gtk::Window
    attr_accessor :response, :window, :vpaned, :viewport, :hbox

    def initialize(*args)
      super(*args)
      @response = 0
      @window = self

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
      vpaned.pack1(sw, true, true)

      @hbox = Gtk::HBox.new
      #bbox = Gtk::HButtonBox.new
      #bbox.layout_style = Gtk::ButtonBox::SPREAD
      #bbox.border_width = 2
      #bbox.spacing = 2
      #bbox.border_width = 10
      vpaned.pack2(hbox, false, true)

      bbox = Gtk::HBox.new
      bbox.border_width = 15
      bbox.spacing = 10
      okbutton = Gtk::Button.new(Gtk::Stock::OK)
      okbutton.width_request = 110
      okbutton.signal_connect('clicked') { @response=1 }
      bbox.pack_start(okbutton, false, false, 0)

      cancelbutton = Gtk::Button.new(Gtk::Stock::CANCEL)
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
        enter_works_like_tab = false
        if (event.hardware_keycode==36) and (enter_works_like_tab)  # Enter works like Tab
          event.hardware_keycode=23
          event.keyval=Gdk::Keyval::GDK_Tab
          window.signal_emit('key-press-event', event)
          true
        elsif (event.hardware_keycode==36) or  #Enter pressed
          ([Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval))
        then
          okbutton.activate
          false
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

    # show dialog and if pressed "OK" do a block
    def run
      show_all
      while (not destroyed?) and (@response == 0) do
        Gtk.main_iteration
      end
      if not destroyed?
        if @response == 1
          @fields.each do |field|
            entry = field[9]
            field[13] = entry.text
          end
          yield(@response) if block_given?
        end
        destroy
      end
    end
  end

  # Dialog with enter fields
  # RU: Диалог с полями ввода
  class FieldsDialog < AdvancedDialog
    attr_accessor :fields

    def initialize(afields=[], *args)
      super(*args)
      @fields = afields

      window.signal_connect('configure-event') do |widget, event|
        window.on_resize_window(widget, event)
        false
      end

      @vbox = Gtk::VBox.new
      viewport.add(@vbox)

=begin
      rbvbox = Gtk::VBox.new
      button1 = Gtk::RadioButton.new('ручное/по порядку')
      rbvbox.pack_start(button1, false, false, 0)
      button1.signal_connect('toggled') do
        @selected_branch = 'A'
      end
      button1.active = true
      button2 = Gtk::RadioButton.new(button1, 'умно/наименьшее расст')
      rbvbox.pack_start(button2, false, false, 0)
      button2.signal_connect('toggled') do
        @selected_branch = 'B'
      end
      button3 = Gtk::RadioButton.new(button2, 'умно/наименьшее расст+по типам')
      rbvbox.pack_start(button3, false, false, 0)
      button3.signal_connect('toggled') do
        @selected_branch = 'C'
      end
      hbox.add(rbvbox)
=end
      rbvbox = Gtk::VBox.new

      support_btn = Gtk::CheckButton.new(_('support'), true)
      support_btn.signal_connect('toggled') do |widget, event|
        p "support"
      end
      rbvbox.pack_start(support_btn, false, false, 0)

      trust_btn = Gtk::CheckButton.new(_('trust'), true)
      trust_btn.signal_connect('toggled') do |widget, event|
        p "trust"
      end
      rbvbox.pack_start(trust_btn, false, false, 0)

      public_btn = Gtk::CheckButton.new(_('public'), true)
      public_btn.signal_connect('toggled') do |widget, event|
        p "public"
      end
      rbvbox.pack_start(public_btn, false, false, 0)

      hbox.pack_start(rbvbox, false, false, 1.0)
      #hbox.add(rbvbox)

      hbox.show_all
      bw,bh = hbox.size_request
      @btn_panel_height = bh

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
      def_size = 10
      # create entries, set their widths/maxlen, remember them
      entries_width = 0
      max_entry_height = 0
      @fields.each do |field|
        entry = Gtk::Entry.new
        begin
          size = 0
          size = field[12].to_i if field[12] != nil
          size = field[2].to_i if size<=0
        rescue
          size = def_size
        end
        entry.max_length = size
        ew = size*@middle_char_width
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
        window_width, window_height = mw+36, mh+@btn_panel_height+55
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

      p '---fill'

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
                p [mh, form_height]
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
        p "----+++++redraw"
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

  # View and edit record dialog
  # RU: Окно просмотра и правки записи
  def self.edit_subject(tree_view, action)

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

    def self.get_subject_icon(subject)
      ind = -1
      $notebook.children.each do |child|
        if child.name==subject.ider
          ind = $notebook.children.index(child)
          break
        end
      end
      subjecticon = nil
      first_lab_widget = $notebook.get_tab_label($notebook.children[ind]).children[0] if ind>=0
      if first_lab_widget.is_a? Gtk::Image
        image = first_lab_widget
        subjecticon = $window.render_icon(image.stock, Gtk::IconSize::MENU)
      end
      subjecticon
    end

    path, column = tree_view.cursor
    new_act = action == 'Create'
    if path != nil or new_act
      subject = tree_view.subject
      store = tree_view.model
      sel = nil
      id = nil
      if path != nil and ! new_act
        iter = store.get_iter(path)
        id = iter[0]
        sel = subject.select('id='+id)
      end
      p sel

      subjecticon = get_subject_icon(subject)

      if action=='Delete'
        dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
          Gtk::MessageDialog::QUESTION,
          Gtk::MessageDialog::BUTTONS_OK_CANCEL,
          _('Record will be deleted. Sure?')+"\n["+sel[0][1,2].join(', ')+']')
        dialog.title = _('Deletion')+': '+subject.sname
        dialog.icon = subjecticon
        if dialog.run == -5
          id = 'id='+id
          res = subject.update(nil, nil, id)
        end
        dialog.destroy
      else
        i = 0
        formfields = []
        ind = 0.0
        subject.def_fields.each do |field|
          if field[3] != nil
            fldsize = field[3].to_i
          else
            fldsize = 10
          end
          if field[5] != nil
            fldfsize = field[5].to_i
            fldfsize = fldsize if fldfsize > fldsize
          else
            fldfsize = fldsize
            fldfsize *= 0.67 if fldfsize>40
          end
          indd, lab_or, new_row = decode_pos(field[4])
          plus = ((indd != nil) and (indd[0, 1]=='+'))
          indd = indd[1..-1] if plus
          indd = indd.to_f if (indd != nil) and (indd.size>0)
          if indd == nil
            ind += 1.0
          else
            if plus
              ind += indd
            else
              ind = indd
            end
          end
          new_fld = [field[0], field[1], fldsize, ind, lab_or, new_row]
          new_fld[12] = fldfsize
          fldval = nil
          fldval = subject.field_val(field[0], sel[0]) if (sel != nil) and (sel[0] != nil)
          fldval = '' if fldval == nil
          new_fld[13] = fldval
          formfields << new_fld
        end
        formfields.sort! {|a,b| a[3]<=>b[3] }

        dialog = FieldsDialog.new(formfields.clone, subject.sname)
        dialog.icon = subjecticon

        if subject.class==PandoraModel::Key
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
          fldvalues = []
          fldnames = []
          dialog.fields.each_index do |index|
            field = dialog.fields[index]
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
          res = subject.update(fldvalues, fldnames, id)
        end
      end
    end
  end

  # Tree of subjects
  # RU: Дерево субъектов
  class SubjTreeView < Gtk::TreeView
    attr_accessor :subject
  end

  LM_Error    = 0
  LM_Warning  = 1
  LM_Info     = 2
  LM_Trace    = 3

  # Log message
  # RU: Добавить сообщение в лог
  def self.log_message(level, mes)
    $view.insert_at_cursor('['+level.to_s+']'+mes+"\n") if $view != nil
  end

  # Showing subject list
  # RU: Показ списка субъектов
  #def self.show_subject_list(subject_class, widget=nil)
  #end

  class TabLabelBox < Gtk::HBox
    attr_accessor :label

    def initialize(image, title, bodywin, *args)
      super(*args)
      label_box = self

      label_box.pack_start(image, false, false, 0) if image != nil

      @label = Gtk::Label.new(title)
      label_box.pack_start(label, false, false, 0)

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

      label_box.spacing = 3
      label_box.show_all
    end

  end

  # Showing subject list
  # RU: Показ списка субъектов
  def self.show_subject_list(subject_class, widget=nil)
    $notebook.children.each do |child|
      if child.name==subject_class.ider
        $notebook.page = $notebook.children.index(child)
        return
      end
    end
    subject = subject_class.new
    sel = subject.select
    #store_fields = [String, String, String, String, String, String, String, String]
    store = Gtk::ListStore.new(String, String, String, String, String, String, String, String, String, String, String, String, String, String, String, String)
    sel.each do |row|
      iter = store.append
      row.each_index { |i| iter.set_value(i, row[i].to_s) }
    end
    treeview = SubjTreeView.new(store)
    treeview.name = subject.ider
    treeview.subject = subject
    flds = subject.tab_fields
    flds = subject.def_fields if flds == []
    flds.each_with_index do |v,i|
      v = v[0].to_s if v.is_a? Array
      column = Gtk::TreeViewColumn.new(subject.field_des(v), Gtk::CellRendererText.new, {:text => i} )
      treeview.append_column(column)
    end
    treeview.signal_connect('row_activated') do |tree_view, path, column|
      edit_subject(tree_view, 'Edit')
    end

    sw = Gtk::ScrolledWindow.new(nil, nil)
    sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
    sw.name = subject.ider
    sw.add(treeview)
    sw.border_width = 0;

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

    label_box = TabLabelBox.new(image, subject.pname, sw, false, 0) do
      store.clear
      treeview.destroy
    end

    page = $notebook.append_page(sw, label_box)
    sw.show_all
    $notebook.page = $notebook.n_pages-1

    menu = Gtk::Menu.new
    menu.append(create_menu_item(["Create", Gtk::Stock::NEW, _("Create"), "Insert"]))
    menu.append(create_menu_item(["Edit", Gtk::Stock::EDIT, _("Edit"), "Return"]))
    menu.append(create_menu_item(["Delete", Gtk::Stock::DELETE, _("Delete"), "Delete"]))
    menu.append(create_menu_item(["Copy", Gtk::Stock::COPY, _("Copy"), "<control>Insert"]))
    menu.append(create_menu_item(["-", nil, nil]))
    menu.append(create_menu_item(["Talk", Gtk::Stock::MEDIA_PLAY, _("Talk"), "<control>T"]))
    menu.append(create_menu_item(["Express", Gtk::Stock::JUMP_TO, _("Express"), "<control>BackSpace"]))
    menu.append(create_menu_item(["-", nil, nil]))
    menu.append(create_menu_item(["Clone", Gtk::Stock::CONVERT, _("Recreate the table")]))
    menu.show_all

    treeview.add_events(Gdk::Event::BUTTON_PRESS_MASK)
    treeview.signal_connect("button_press_event") do |widget, event|
      if (event.button == 3)
        menu.popup(nil, nil, event.button, event.time)
      end
    end

  end

  # Initilize default keypair
  # RU: Инициализирует ключи по умолчанию
  def self.init_keypair
    key = OpenSSL::PKey::RSA.generate(2048)
    pub = key.public_key
    ca = OpenSSL::X509::Name.parse("/C=US/ST=Florida/L=Miami/O=Waitingf/OU=Poopstat/CN=waitingf.org/emailAddress=bkerley@brycekerley.net")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = ca
    cert.issuer = ca
    cert.public_key = pub
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    File.open("private.pem", "w") { |f| f.write key.to_pem }
    File.open("cert.pem", "w") { |f| f.write cert.to_pem }
    #p Digest::SHA1.hexdigest('foo')
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
  EC_Media     = 0
  EC_Init      = 1
  EC_Query     = 2
  EC_News      = 3
  EC_Notice    = 4
  EC_Change    = 5
  EC_Pack      = 6
  EC_Request   = 7
  EC_Record    = 8
  EC_Pipe      = 9
  EC_Wait      = 253
  EC_More      = 254
  EC_Bye       = 255
  EC_Data      = 256   # ждем данные

  TExchangeCommands = {EC_Init=>'init', EC_Query=>'query', EC_News=>'news', EC_Notice=>'notice',
    EC_Change=>'change', EC_Request=>'request', EC_Record=>'record', EC_Pipe=>'pipe',
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
    sended = socket.write(buf)
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

  ECC_Init0_Hello       = 0
  ECC_Init1_KeyPhrase   = 1
  ECC_Init2_SignKey     = 2
  ECC_Init3_PhraseSign  = 3
  ECC_Init4_Permission  = 4
  ECC_Query0_Kinds      = 0
  ECC_Query255_AllChanges =255
  EC_News0_Kinds        = 0

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

  $connections = []

  def self.index_of_connection_for_column(value, column=0)
    index = nil
    $connections.each_with_index do |e, i|
      if (e.is_a? Array) and (e[column] == value)
        index = i
        break
      end
    end
    index
  end

  # Connection data indexes
  # RU: Индексы данных соединения
  CDI_HostName    = 0
  CDI_HostIP      = 1
  CDI_Port        = 2
  CDI_Proto       = 3
  CDI_ConnMode    = 4
  CDI_ConnState   = 5
  CDI_SendThread  = 6
  CDI_ReadThread  = 7
  CDI_Socket      = 8
  CDI_ReadState   = 9
  CDI_SendState   = 10
  CDI_ReadMes     = 11
  CDI_ReadMedia   = 12
  CDI_ReadReq     = 13
  CDI_SendMes     = 14
  CDI_SendMedia   = 15
  CDI_SendReq     = 16

  def self.index_of_connection_for_node(node)
    index = nil
    host, port, proto = decode_node(node)
    $connections.each_with_index do |e, i|
      if (e.is_a? Array) and ((e[CDI_HostIP] == host) or (e[CDI_HostName] == host)) and (e[CDI_Port] == port) \
      and (e[CDI_Proto] == proto)
        index = i
        break
      end
    end
    index
  end

  # Connection mode
  # RU: Режим соединения
  CM_Hunter       = 1
  CM_Persistent   = 2

  # Connected state
  # RU: Состояние соединения
  CS_Connecting   = 1
  CS_Connected    = 2
  CS_Disconnected = 0

  # Number of messages per cicle
  # RU: Число сообщений за цикл
  $mes_block_count = 2
  # Number of media blocks per cicle
  # RU: Число медиа блоков за цикл
  $media_block_count = 10
  # Number of requests per cicle
  # RU: Число запросов за цикл
  $req_block_count = 1

  # Start two exchange cicle of socket: read and send
  # RU: Запускает два цикла обмена сокета: чтение и отправка
  def self.start_exchange_cicle(node)
    socket = nil
    conn_ind = index_of_connection_for_node(node)
    if conn_ind
      conn_mode    =  $connections[conn_ind][CDI_ConnMode]
      conn_state   =  $connections[conn_ind][CDI_ConnState]
      send_thread  =  $connections[conn_ind][CDI_SendThread]
      socket       =  $connections[conn_ind][CDI_Socket]
      read_state   =  $connections[conn_ind][CDI_ReadState]
      send_state   =  $connections[conn_ind][CDI_SendState]
      read_mes     =  $connections[conn_ind][CDI_ReadMes]
      read_media   =  $connections[conn_ind][CDI_ReadMedia]
      read_req     =  $connections[conn_ind][CDI_ReadReq]
      send_mes     =  $connections[conn_ind][CDI_SendMes]
      send_media   =  $connections[conn_ind][CDI_SendMedia]
      send_req     =  $connections[conn_ind][CDI_SendReq]

      p "exch: !read_mes: "+read_mes.inspect
      p "exch: !send_mes: "+send_mes.inspect

      hunter = (conn_mode & CM_Hunter)>0
      if hunter
        log_mes = 'HUN: '
      else
        log_mes = 'LIS: '
      end

      scmd = EC_More
      sbuf = ''

      # Read cicle
      # RU: Цикл приёма
      if ($connections[conn_ind][CDI_ReadThread] == nil)
        read_thread = Thread.new do
          read_thread = Thread.current
          $connections[conn_ind][CDI_ReadThread] = read_thread

          rcmd = EC_More
          rindex = 0
          rbuf = ''
          rdata = ''
          readmode = RM_Comm
          nextreadmode = RM_Comm
          waitlen = CommSize
          last_scmd = scmd
          # Цикл обработки команд и блоков данных
          while (conn_state>0) and (recived = socket.recv(MaxPackSize)) and not socket.closed?
            rbuf += recived
            processedlen = 0
            while (conn_state>0) and (rbuf.size>=waitlen)
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
                    log_message(LM_Error, 'Ошибочный CRC полученой команды')
                    scmd=EC_Bye; scode=ECC_Bye_BadCommCRC
                  elsif errcode == 2
                    log_message(LM_Error, 'Ошибочная длина полученой команды')
                    scmd=EC_Bye; scode=ECC_Bye_BadCommLen
                  else
                    log_message(LM_Error, 'Ошибка в полученой команде')
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
                    log_message(LM_Error, 'Ошибка CRC полученного сегмента')
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
              p log_mes+'PL='+processedlen.to_s+'  rbuf=('+rbuf+')  scmd='+scmd.to_s
              scmd = EC_Data if (scmd != EC_Bye) and (scmd != EC_Wait)
              p log_mes+'nrm='+nextreadmode.to_s
              # Обработаем поступившие команды и блоки данных
              if (scmd != EC_Bye) and (scmd != EC_Wait) and (nextreadmode == RM_Comm)
                # ..вызвав заданный обработчик
                p log_mes+'Matter?='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect
                rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = matter_process[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd]
                rdata = ''
                p log_mes+'Matter!='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect
              end
              if scmd != EC_Data
                sbuf='' if scmd == EC_Bye
                p log_mes+'SEND: '+scmd.to_s+"/"+scode.to_s+"+("+sbuf+')'
                sindex = send_comm_and_data(socket, sindex, scmd, scode, sbuf)
                last_scmd = scmd
                sbuf = ''
              end
              readmode = nextreadmode
              sleep 0.5
            end
          end

        end
        $connections[conn_ind][CDI_ReadThread] = read_thread
      end


      # Send cicle
      # RU: Цикл отправки

      if hunter
        sindex = 0
        scmd = EC_Init
        sbuf='pandora 0.1'
        scode = ECC_Init0_Hello

        # tos_sip    cs3   0x60  0x18
        # tos_video  af41  0x88  0x22
        # tos_xxx    cs5   0xA0  0x28
        # tos_audio  ef    0xB8  0x2E

        p "exch: hunter hello!"
        #socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0xA0)  # QoS (VoIP пакет)
        sindex = send_comm_and_data(socket, sindex, scmd, scode, sbuf)
        #socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0x00)  # обычный пакет
      end
      p "exch: cicles"
      p "exch: conn_data: "+$connections[conn_ind].inspect
      while (conn_state>0)
        #p "read_mes"
        # обработка принятых сообщений, их удаление
        processedmes = 0
        while (read_mes.size>0) and (processedmes<$mes_block_count) and (conn_state>0)
          processedmes += 1
          p "exch: read_mes.delete_at: " +read_mes.delete_at(0).inspect
          #sindex = send_comm_and_data(socket, sindex, scmd, scode, sbuf)
        end
        # разгрузка принятых буферов в gstreamer
        processedbuf = 0
        while (read_media.size>0) and (processedbuf<$media_block_count) and (conn_state>0)
          processedbuf += 1
          p read_media.delete_at(0)
        end
        # обработка принятых запросов, их удаление
        processedmes = 0
        while (read_req.size>0) and (processedmes<$req_block_count) and (conn_state>0)
          processedmes += 1
          p read_req.delete_at(0)
        end

        # отправка принятых сообщений, пометка как отправленных
        processedmes = 0
        while (send_mes.size>0) and (processedmes<$mes_block_count) and (conn_state>0)
          processedmes += 1
          p "exch: send_mes.delete_at: " +send_mes.delete_at(0).inspect
          #sindex = send_comm_and_data(socket, sindex, scmd, scode, sbuf)
        end

        # отправка сформированных буферов

        # формирование запросов на отправку и их отправка

      end

      p "exch: exit cicles!!!"
    else
      puts _('exch: Node is not found in connection list')+' ['+node.to_s+']'
    end
  end

=begin
  def self.do_exchange_cicle(active, socket, &matter_process)
    rcmd = EC_More
    sindex = 0
    rindex = 0
    rbuf = ''
    rdata = ''
    if active
      err_mes='ACT: '
      scmd = EC_Init
      sbuf='pandora 0.1'
      scode = ECC_Init0_Hello
      sindex = send_comm_and_data(socket, sindex, scmd, scode, sbuf)
    else
      err_mes='PAS: '
      scmd = EC_More
      sbuf = ''
    end
    readmode = RM_Comm
    nextreadmode = RM_Comm
    waitlen = CommSize
    last_scmd = scmd
    # Цикл обработки команд и блоков данных
    while (scmd != EC_Bye) and (scmd != EC_Wait) and (recived = socket.recv(MaxPackSize))
      rbuf += recived
      processedlen = 0
      while (scmd != EC_Bye) and (scmd != EC_Wait) and (rbuf.size>=waitlen)
        p err_mes+'begin=['+rbuf+']  L='+rbuf.size.to_s+'  WL='+waitlen.to_s
        processedlen = waitlen
        nextreadmode = readmode
        # Определимся с данными по режиму чтения
        case readmode
          when RM_Comm
            comm = rbuf[0, processedlen]
            rindex, rcmd, rcode, rsegsign, errcode = unpack_comm(comm)
            if errcode == 0
              p err_mes+' RM_Comm: '+[rindex, rcmd, rcode, rsegsign].inspect
              if rsegsign == LONG_SEG_SIGN
                nextreadmode = RM_CommExt
                waitlen = CommExtSize
              elsif rsegsign > 0
                nextreadmode = RM_SegmentS
                waitlen = rsegsign+4  #+CRC32
                rdatasize, rsegsize = rsegsign
              end
            elsif errcode == 1
              log_message(LM_Error, 'Ошибочный CRC полученой команды')
              scmd=EC_Bye; scode=ECC_Bye_BadCommCRC
            elsif errcode == 2
              log_message(LM_Error, 'Ошибочная длина полученой команды')
              scmd=EC_Bye; scode=ECC_Bye_BadCommLen
            else
              log_message(LM_Error, 'Ошибка в полученой команде')
              scmd=EC_Bye; scode=ECC_Bye_Unknown
            end
          when RM_CommExt
            comm = rbuf[0, processedlen]
            rdatasize, fullcrc32, rsegsize = unpack_comm_ext(comm)
            p err_mes+' RM_CommExt: '+[rdatasize, fullcrc32, rsegsize].inspect
            nextreadmode = RM_Segment1
            waitlen = rsegsize+4   #+CRC32
          when RM_SegLenN
            comm = rbuf[0, processedlen]
            rindex, rsegindex, rsegsize = comm.unpack('CNn')
            p err_mes+' RM_SegLenN: '+[rindex, rsegindex, rsegsize].inspect
            nextreadmode = RM_SegmentN
            waitlen = rsegsize+4   #+CRC32
          when RM_SegmentS, RM_Segment1, RM_SegmentN
            p err_mes+' RM_SegLenX['+readmode.to_s+']  rbuf=['+rbuf+']'
            if (readmode==RM_Segment1) or (readmode==RM_SegmentN)
              nextreadmode = RM_SegLenN
              waitlen = 7    #index + segindex + rseglen (1+4+2)
            end
            rseg = rbuf[0, processedlen-4]
            p err_mes+'rseg=['+rseg+']'
            rsegcrc32 = rbuf[processedlen-4, 4].unpack('N')[0]
            fsegcrc32 = Zlib.crc32(rseg)
            if fsegcrc32 == rsegcrc32
              rdata << rseg
            else
              log_message(LM_Error, 'Ошибка CRC полученного сегмента')
              scmd=EC_Bye; scode=ECC_Bye_BadCRC
            end
            p err_mes+'RM_SegmentX: data['+rdata+']'+rdata.size.to_s+'/'+rdatasize.to_s
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
        p err_mes+'PL='+processedlen.to_s+'  rbuf=('+rbuf+')  scmd='+scmd.to_s
        scmd = EC_Data if (scmd != EC_Bye) and (scmd != EC_Wait)
        p err_mes+'nrm='+nextreadmode.to_s
        # Обработаем поступившие команды и блоки данных
        if (scmd != EC_Bye) and (scmd != EC_Wait) and (nextreadmode == RM_Comm)
          # ..вызвав заданный обработчик
          p err_mes+'Matter?='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect
          rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = matter_process[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd]
          rdata = ''
          p err_mes+'Matter!='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect
        end
        if scmd != EC_Data
          sbuf='' if scmd == EC_Bye
          p err_mes+'SEND: '+scmd.to_s+"/"+scode.to_s+"+("+sbuf+')'
          sindex = send_comm_and_data(socket, sindex, scmd, scode, sbuf)
          last_scmd = scmd
          sbuf = ''
        end
        readmode = nextreadmode
        sleep 0.5
      end
    end
  end
=end

  NullQueue = [0, 0, []]


  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.listen_socket(open=true)
    server = TCPServer.open($host, $port)
    addr = server.addr
    log_message(LM_Info, 'Слушаю порт :'+addr.join(':')+')')
    $listen_btn.label = _('Online')
    Thread.new do
      loop do
        # Создать поток при подключении клиента
        Thread.start(server.accept) do |socket|
          log_message(LM_Info, "Подключился клиент: "+socket.to_s)

          #local_address
          p "list: remote_address: "+socket.peeraddr.inspect
          host_ip = socket.peeraddr[2]
          host_name = socket.peeraddr[3]
          port = socket.peeraddr[1]
          port = "5577"
          proto = "tcp"
          node = encode_node(host_ip, port, proto)
          p "list: node: "+node.inspect

          conn_ind = index_of_connection_for_node(node)
          if conn_ind
            log_message(LM_Info, "Замкнутая петля: "+socket.to_s)
            conn_state = $connections[conn_ind][CDI_ConnState]
            while conn_ind and (conn_state==CS_Connected) and not socket.closed?
              conn_ind = index_of_connection_for_node(node)
              conn_state = $connections[conn_ind][CDI_ConnState] if conn_ind
            end
          else
            conn_state = CS_Connected
            conn_mode = 0
            p "serv: conn_mode: "+ conn_mode.inspect
            # CDI_HostName, CDI_HostIP, CDI_Port, CDI_Proto, CDI_ConnMode, CDI_ConnState
            $connections << [ host_name, host_ip, port, proto, conn_mode, conn_state ]
            conn_ind = index_of_connection_for_node(node)
            if conn_ind
              # CDI_SendThread, CDI_ReadThread, CDI_Socket, CDI_ReadState, CDI_SendState
              $connections[conn_ind] += [Thread.current, nil, socket, 0, 0]
              # CDI_ReadMes, CDI_ReadMedia, CDI_ReadReq, CDI_SendMes, CDI_SendMedia, CDI_SendReq]
              $connections[conn_ind] += Array.new(6, NullQueue.dup)
              p "server: ind!"+ conn_ind.to_s
              p "server: conn!"+ $connections[conn_ind].inspect
              start_exchange_cicle(node)
            else
              p "Не удалось добавить подключенного в список!!!"
            end
          end

=begin
          # Вызвать пассивный цикл с обработкой данных
          do_exchange_cicle(false, socket) do |rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd|
            case rcmd  # СЕРВЕР!!! (пассив)
              when EC_Init
                case rcode
                  when ECC_Init0_Hello
                    ahello=rdata
                    scmd=EC_Init
                    scode=ECC_Init0_Hello
                    sbuf='pandora 0.1'
                  when ECC_Init1_KeyPhrase
                    akey=rdata
                    scmd=EC_Init
                    scode=ECC_Init1_KeyPhrase
                    pphrase="Zzvsdvdfsvfdvbdf"
                    sbuf=pphrase
                  when ECC_Init2_SignKey
                    asign=rdata
                    scmd=EC_Init
                    scode=ECC_Init2_SignKey
                    pkey="d5g6s2"
                    sbuf=pkey
                  when ECC_Init3_PhraseSign
                    aphrase=rdata
                    scmd=EC_Init
                    scode=ECC_Init3_PhraseSign
                    psign='re8e83'
                    sbuf=psign
                  when ECC_Init4_Permission
                    aperm=rdata
                    scmd=EC_Init
                    scode=ECC_Init4_Permission
                    pperm='000011'
                    sbuf=pperm
                end
              when EC_Query
                case rcode
                  when ECC_Query0_Kinds
                    afrom_data=rdata
                    scmd=EC_News
                    pkinds="3,7,11"
                    scode=EC_News0_Kinds
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
              when EC_More
                case last_scmd
                  when EC_News
                    p "!!!!!MORE!"
                    pkind = 0
                    if pkind <= 10
                      scmd=EC_Notice
                      scode=pkind
                      ahashid = "id=gfs225,hash=asdsad"
                      sbuf=ahashid
                      pkind += 1
                    else
                    end
                end
              when EC_Request
                p ""
              when EC_Pipe
                p ""
              when EC_Bye
                if rcode != ECC_Bye_Exit
                  log_message(LM_Error, 'Ошибка на клиенте ErrCode='+rcode.to_s)
                end
                scmd=EC_Bye
                scode=ECC_Bye_Exit
              else
                scmd=EC_Bye
                scode=ECC_Bye_Unknown
                log_message(LM_Error, 'Получена неизвестная команда от клиента='+rcmd.to_s)
            end
            [rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd]
          end
=end

          socket.close
          log_message(LM_Info, "Отключился клиент: "+socket.to_s)
        end
      end
      server.close
    end
    server
  end

  # Create or find connection with necessary node
  # RU: Создает или находит соединение с нужным узлом
  def self.start_or_find_connection(node, persistent=false, wait_connection=false)
    conn_ind = index_of_connection_for_node(node)
    if not conn_ind
      conn_state = CS_Connecting
      conn_mode = CM_Hunter
      conn_mode = conn_mode | CM_Persistent if persistent
      host, port, proto = decode_node(node)
      # CDI_HostName, CDI_HostIP, CDI_Port, CDI_Proto, CDI_ConnMode, CDI_ConnState
      $connections << [ host, host, port, proto, conn_mode, conn_state ]
      conn_ind = index_of_connection_for_node(node)
      if conn_ind
        send_thread = Thread.new do
          send_thread = Thread.current
          $connections[conn_ind] += [send_thread]   # CDI_SendThread
          host, port, proto = decode_node(node)
          begin
            socket = TCPSocket.open(host, port)
            conn_state = CS_Connected
            $connections[conn_ind][CDI_HostIP] = socket.addr[2]
          rescue #IO::WaitReadable, Errno::EINTR
            socket = nil
            conn_state = CS_Disconnected
            p "Conn Err"
            log_message(LM_Warning, "Ошибка подключения к: "+host+':'+port)
          end
          $connections[conn_ind][CDI_ConnState] = conn_state
          if socket != nil
            # CDI_SendThread, CDI_Socket, CDI_ReadState, CDI_SendState
            $connections[conn_ind] += [nil, socket, 0, 0]
            # CDI_ReadMes, CDI_ReadMedia, CDI_ReadReq, CDI_SendMes, CDI_SendMedia, CDI_SendReq]
            $connections[conn_ind] += Array.new(6, NullQueue.dup)
            p "start_or_find_con: socket created!"+ $connections[conn_ind].inspect
            # Вызвать активный цикл собработкой данных
            log_message(LM_Info, "Подключился к серверу: "+socket.to_s)
            start_exchange_cicle(node)
            socket.close
            log_message(LM_Info, "Отключился от сервера: "+socket.to_s)
          end
        end
        $connections[conn_ind][CDI_SendThread] = send_thread
        while wait_connection and (conn_state==CS_Connecting)
          conn_state = $connections[conn_ind][CDI_ConnState]
        end
        p "start_or_find_con: to end! wait_connection="+wait_connection.to_s
        p "start_or_find_con: to end! conn_state="+conn_state.to_s
        if conn_state == CS_Disconnected
          p 'start_or_find_con: conn_ind '+conn_ind.to_s
          $connections.delete_at(conn_ind) if conn_ind
          conn_ind = nil
        end
      end
    end
    conn_ind
  end

  # Form node marker
  # RU: Сформировать маркер узла
  def self.encode_node(host, port, proto)
    node = host+':'+port+proto
  end

  # Unpack node marker
  # RU: Распаковать маркер узла
  def self.decode_node(node)
    i = node.index(':')
    if i
      host = node[0, i]
      port = node[i+1, node.size-4-i]
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
    node = encode_node($host, $port, 'tcp')
  end

  $hunter_thread = nil

  # Start hunt
  # RU: Начать охоту
  def self.hunt_nodes
    if $hunter_thread == nil
      subject = PandoraModel.const_get('Node')
      p subject
      $hunter_thread = Thread.new do
        host = '127.0.0.1'
        port = 5577
        proto = 'tcp'
        thread = start_or_find_connection([host, port, proto])
        p thread
        $hunt_list[thread] = [host, port] if thread != nil
      end
    else
      $hunter_thread.exit
      $hunter_thread = nil
    end
  end

  $thread = nil
  $play_video = false

  # Play media stream
  # RU: Запустить медиа поток
  def self.play_pipeline
    if ($thread != nil) and $play_video
      $thread.run
      pipeline1 = $thread[:pipeline1]
      pipeline2 = $thread[:pipeline2]
      p $thread.inspect
      pipeline1.play if pipeline1 != nil
      pipeline2.play if pipeline2 != nil
    end
  end

  # Stop media stream
  # RU: Остановить медиа поток
  def self.stop_pipeline
    if $thread != nil
      pipeline1 = $thread[:pipeline1]
      pipeline2 = $thread[:pipeline2]
      p $thread.inspect
      pipeline2.stop if pipeline2 != nil
      pipeline1.stop if pipeline1 != nil
      #$thread.stop
    end
  end

  # Maximal size of queue
  # RU: Максимальный размер очереди
  MaxQueue = 128

  # Add block to queue for send
  # Добавление блока в очередь на отправку
  def self.add_block_to_queue(block, queue)
    p "add_block_to_queue: queue[]: "+queue.inspect
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
    p 'send_mes_to_node: mes: [' +mes+'], start_or_find...'
    if conn_ind=start_or_find_connection(node, true, true)
      p "send_mes_to_node: conn_ind: "+conn_ind.inspect
      # add mess to mes queue
      p "send_mes_to_node: conn_data: "+ $connections[conn_ind].inspect
      mes_queue = $connections[conn_ind][CDI_SendMes]
      p "send_mes_to_node: mes_queue: "+mes_queue.inspect
      add_block_to_queue(mes, mes_queue)
      # update send state
      send_state = $connections[conn_ind][CDI_SendState]
      send_state = send_state | CSF_Message
    else
      p "send_mes_to_node: not connected"
    end
    p 'send_mes_to_node: conn_ind '+conn_ind.to_s
    p 'end send_mes_to_node [' +mes+']'
    sended
  end

  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(node, title=_('Talk'))

    $notebook.children.each do |child|
      if child.name==title
        $notebook.page = $notebook.children.index(child)
        return
      end
    end

    sw = Gtk::ScrolledWindow.new(nil, nil)
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
    area.set_size_request(350, 270)
    area.modify_bg(Gtk::STATE_NORMAL, Gdk::Color.new(0, 0, 0))

    view = Gtk::TextView.new
    view.set_size_request(200, 270)
    view.wrap_mode = Gtk::TextTag::WRAP_WORD
    #view.cursor_visible = false
    #view.editable = false

    edit_box = Gtk::TextView.new
    edit_box.wrap_mode = Gtk::TextTag::WRAP_WORD
    edit_box.set_size_request(200, 70)

    view.buffer.create_tag("red", "foreground" => "red")
    view.buffer.create_tag("blue", "foreground" => "blue")
    view.buffer.create_tag("red_bold", "foreground" => "red", 'weight' => Pango::FontDescription::WEIGHT_BOLD)
    view.buffer.create_tag("blue_bold", "foreground" => "blue",  'weight' => Pango::FontDescription::WEIGHT_BOLD)

    edit_box.grab_focus

    # because of bug - doesnt work Enter at 'key-press-event'
    edit_box.signal_connect('key-release-event') do |widget, event|
      if (event.hardware_keycode==36) or \
        [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      then
        widget.signal_emit('key-press-event', event)
        false
      end
    end

    edit_box.signal_connect('key-press-event') do |widget, event|
      if (event.hardware_keycode==36) or \
        [Gdk::Keyval::GDK_Return, Gdk::Keyval::GDK_KP_Enter].include?(event.keyval) \
      then
        if edit_box.buffer.text != ''
          mes = edit_box.buffer.text
          edit_box.buffer.text = ''
          t = Time.now
          view.buffer.insert(view.buffer.end_iter, "\n") if view.buffer.text != ''
          view.buffer.insert(view.buffer.end_iter, t.strftime('%H:%M:%S')+' ', "red")
          view.buffer.insert(view.buffer.end_iter, 'You:', "red_bold")
          view.buffer.insert(view.buffer.end_iter, ' '+mes)

          view.buffer.insert(view.buffer.end_iter, "\n") if view.buffer.text != ''
          view.buffer.insert(view.buffer.end_iter, t.strftime('%H:%M:%S')+' ', "blue")
          view.buffer.insert(view.buffer.end_iter, 'Dude:', "blue_bold")
          view.buffer.insert(view.buffer.end_iter, ' '+mes)

          if send_mes_to_node(mes, node)
            edit_box.buffer.text = ''
          end
        end
        true
      elsif (event.hardware_keycode==9) or #Esc pressed
        (Gdk::Keyval::GDK_Escape==event.keyval)
      then
        edit_box.buffer.text = ''
        false
      else
        false
      end
    end

    hbox = Gtk::HBox.new

    bbox = Gtk::HBox.new
    bbox.border_width = 5
    bbox.spacing = 5

    snd_button = Gtk::CheckButton.new(_('Sound'), true)
    snd_button.signal_connect('toggled') do |widget, event|
      p 'Sound: '+widget.active?.to_s
    end
    bbox.pack_start(snd_button, false, false, 0)

    vid_button = Gtk::CheckButton.new(_('Video'), true)
    vid_button.signal_connect('toggled') do |widget, event|
      $play_video = widget.active?
      if $play_video
        $thread.run if $thread
        play_pipeline
      else
        stop_pipeline
      end
    end
    bbox.pack_start(vid_button, false, false, 0)

    hbox.pack_start(bbox, false, false, 1.0)

    vpaned1.pack1(area, true, false)
    vpaned1.pack2(hbox, false, true)
    vpaned1.set_size_request(350, 270)

    vpaned2.pack1(view, true, true)
    vpaned2.pack2(edit_box, false, true)

    hpaned.pack1(vpaned1, false, true)
    hpaned.pack2(vpaned2, true, true)

    $thread = nil
    $thread = Thread.new do
      pipeline1 = Gst::Pipeline.new
      pipeline2 = Gst::Pipeline.new
      Thread.current[:pipeline1] = pipeline1
      Thread.current[:pipeline2] = pipeline2

      Thread.stop

      webcam = Gst::ElementFactory.make('v4l2src')
      webcam.decimate=3

      capsfilter = Gst::ElementFactory.make('capsfilter')
      capsfilter.caps = Gst::Caps.parse('video/x-raw-rgb,width=320,height=240')

      ffmpegcolorspace1 = Gst::ElementFactory.make('ffmpegcolorspace')

      vp8enc = Gst::ElementFactory.make('vp8enc')
      vp8enc.max_latency=1

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

      ximagesink = Gst::ElementFactory.make('ximagesink');
      ximagesink.sync = false

      pipeline1.add(webcam, capsfilter, ffmpegcolorspace1, vp8enc, appsink)
      webcam >> capsfilter >> ffmpegcolorspace1 >> vp8enc >> appsink

      pipeline2.add(appsrc, vp8dec, ffmpegcolorspace2, ximagesink)
      appsrc >> vp8dec >> ffmpegcolorspace2 >> ximagesink

      area.show

      ximagesink.xwindow_id = area.window.xid if not area.destroyed? and (area.window != nil)
      pipeline2.bus.add_watch do |bus, message|
        if ((message != nil) and (message.structure != nil) and (message.structure.name != nil) \
          and (message.structure.name == 'prepare-xwindow-id'))
        then
          message.src.set_xwindow_id(area.window.xid) if not area.destroyed? and (area.window != nil)
        end
        true
      end

      area.signal_connect('visibility_notify_event') do |widget, event_visibility|
        case event_visibility.state
          when Gdk::EventVisibility::UNOBSCURED, Gdk::EventVisibility::PARTIAL
            play_pipeline
          when Gdk::EventVisibility::FULLY_OBSCURED
            stop_pipeline
        end
      end

      #ximagesink.xwindow_id = viewport.window.xid
      area.signal_connect('expose-event') do
        ximagesink.xwindow_id = area.window.xid if not area.destroyed? and (area.window != nil)
      end

      area.signal_connect('destroy') do
        pipeline2.stop
        pipeline1.stop
      end

      while Thread.current.alive? do
        #Gtk.main_iteration
      end
    end

    label_box = TabLabelBox.new(image, title, sw, false, 0) do
      stop_pipeline
      $thread[:pipeline1] = nil
      $thread[:pipeline2] = nil
      area.destroy
      $thread.join(2)
      $thread.exit
      $thread = nil
    end

    page = $notebook.append_page(sw, label_box)
    sw.show_all
    $notebook.page = $notebook.n_pages-1
    edit_box.grab_focus
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
          edit_subject(treeview, widget.name) if treeview.is_a? PandoraGUI::SubjTreeView
        end
      when 'Clone'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          subject = treeview.subject
          subject.update(nil, nil, nil)
        end
      when 'Listen'
        listen_socket(true)
      when 'Connect'
        if $notebook.page >= 0
          sw = $notebook.get_nth_page($notebook.page)
          treeview = sw.children[0]
          subject = treeview.subject
          subject.update(nil, nil, nil)
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
      when 'Wizard'
        PandoraKernel.save_as_language($lang)
      else
        subj_id = widget.name
        if PandoraModel.const_defined? subj_id
          subject_class = PandoraModel.const_get(subj_id)
          show_subject_list(subject_class, widget)
        else
          log_message(LM_Warning, _('Menu handler is not defined yet')+' ['+subj_id+']')
        end
    end
  end

  # Menu structure
  # RU: Структура меню
  def self.menu_items
    [
    [nil, nil, _("_World")],
    ["Person", Gtk::Stock::ORIENTATION_PORTRAIT, _("People")],
    ["Community", nil, _("Communities")],
    ["-", nil, "-"],
    ["Country", nil, _("States")],
    ["City", nil, _("Towns")],
    ["Street", nil, _("Streets")],
    ["Address", nil, _("Addresses")],
    ["Contact", nil, _("Contacts")],
    ["Document", nil, _("Documents")],
    ["Currency", nil, _("Currency")],
    ["Occupation", nil, _("Activities")],
    ["Language", nil, _("Languages")],
    ["Word", Gtk::Stock::SPELL_CHECK, _("Words")],
    ["Thing", nil, _("Things")],
    ["Article", nil, _("Articles")],
    ["Blob", Gtk::Stock::HARDDISK, _("Files")], #Gtk::Stock::FILE
    ["-", nil, "-"],
    ["Relation", nil, _("Relations")],
    ["Opinion", nil, _("Opinions")],
    [nil, nil, _("_Bussiness")],
    ["Product", nil, _("Products")],
    ["Service", nil, _("Services")],
    ["-", nil, "-"],
    ["Position", nil, _("Positions")],
    ["Nomenclature", nil, _("Nomenclatures")],
    ["Contract", nil, _("Contracts")],
    ["Account", nil, _("Accounts")],
    ["-", nil, "-"],
    ["Worker", nil, _("Workers")],
    ["Client", nil, _("Clients")],
    ["Storage", nil, _("Storages")],
    ["-", nil, "-"],
    ["Order", nil, _("Orders")],
    ["Deal", nil, _("Deals")],
    ["Payment", nil, _("Payments")],
    ["-", nil, "-"],
    ["Property", nil, _("Property")],
    ["Transfer", nil, _("Transfer")],
    ["-", nil, "-"],
    ["Report", nil, _("Reports")],
    [nil, nil, _("_Region")],
    ["Resource", nil, _("Resources")],
    ["-", nil, "-"],
    ["Law", nil, _("Laws")],
    ["Project", nil, _("Projects")],
    ["Resolution", nil, _("Resolutions")],
    ["-", nil, "-"],
    ["Contribution", nil, _("Contributions")],
    ["Expenditure", nil, _("Expenditures")],
    ["-", nil, "-"],
    ["Offense", nil, _("Offenses")],
    ["Punishment", nil, _("Punishments")],
    [nil, nil, _("_Pandora")],
    ["Parameter", Gtk::Stock::PREFERENCES, _("Parameters")],
    ["-", nil, "-"],
    ["Key", nil, _("Keys")],
    ["Sign", nil, _("Signs")],
    ["Node", Gtk::Stock::NETWORK, _("Nodes")],
    ["Patch", nil, _("Patches")],
    ["Event", nil, _("Events")],
    ["Repository", nil, _("Repositories")],
    ["-", nil, "-"],
    ["Authorize", Gtk::Stock::DIALOG_AUTHENTICATION, _("Authorize")],
    ["Listen", Gtk::Stock::CONNECT, _("Listen")],
    ["Hunt", Gtk::Stock::REFRESH, _("Hunt")],
    ["Search", Gtk::Stock::FIND, _("Search")],
    ["-", nil, "-"],
    ["Profile", Gtk::Stock::HOME, _("Profile")],
    ["Wizard", Gtk::Stock::PROPERTIES, _("Wizards")],
    ["-", nil, "-"],
    ["Quit", Gtk::Stock::QUIT, _("_Quit"), "<control>Q", "Do quit"],
    ["Close", Gtk::Stock::CLOSE, _("_Close"), "<control>W", "Close tab"],
    ["-", nil, "-"],
    ["About", Gtk::Stock::ABOUT, _('_About'), nil, "About"]
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
        menuitem.add_accelerator("activate", $group, key, mod, Gtk::ACCEL_VISIBLE)
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
      treeview = sw.children[0]
      stop_pipeline if treeview.is_a? PandoraGUI::SubjTreeView
    end

    $view = Gtk::TextView.new
    $view.can_focus = false
    $view.has_focus = false
    $view.receives_default = true
    $view.border_width = 0

    statusbar = Gtk::Statusbar.new
    statusbar.push(0, _('Base directory: ')+$pandora_base_dir)
    btn = Gtk::Button.new(_('Not logged'))
    btn.relief = Gtk::RELIEF_NONE
    statusbar.pack_start(btn, false, false, 2)
    statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
    $listen_btn = Gtk::Button.new(_('Offline'))
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
      stop_pipeline
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
        stop_pipeline
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
            @statusicon.signal_connect("activate") do
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


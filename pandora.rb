#!/usr/bin/env ruby
# encoding: utf-8

$KCODE='u'

# The Pandora. Free decentralized information system
# RU: Пандора. Децентрализованная информационная система
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк
#
# coding: utf-8

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

# If it's runned under WinOS, redirect console output to file
# RU: Если под Виндой, то перенаправить консольный вывод в файл
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
#require 'timeout'
#require 'digest/sha1'
begin
  require 'jcode'
  $jcode_on = true
rescue Exception
  $jcode_on = false
end

=begin
# DBI is required to connect to databases
# RU: DBI нужен для подключения к базам данных
begin
  require 'dbi'
  $dbi_on = true
rescue Exception
  $dbi_on = false
end
=end

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

$lang = 'ru'

# Define environment parameters
# RU: Определить переменные окружения
lang = ENV['LANG']
if (lang.is_a? String) and (lang.size>1)
  $lang = lang[0, 2].downcase
end

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки

$host = 'localhost'
$port = '5577'
$base_index = 0

arg = nil
while ARGV.length >0 do
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

# GStreamer is a media library
# RU: Обвязка для медиа библиотеки GStreamer
begin
  require 'gst'
  $gst_on = true
rescue Exception
  $gst_on = false
end

# ==Language section
# ==RU: Базовый модуль Пандора

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

# ==Base module of Pandora
# ==RU: Базовый модуль Пандора
module PandoraKernel

  # Paths and files  ('join' gets '/' for Linux and '\' for Windows)
  # RU: Пути и файлы ('join' дает '/' для Линукса и '\' для Винды)
  $pandora_root_dir = Dir.pwd                                        # Root Pandora directory
  if os_family == 'windows'
    #begin
    #  require 'iconv'
    #  converter = Iconv.new('UTF-8', 'WINDOWS-1251')
    #  $pandora_root_dir = converter.iconv($pandora_root_dir)
    #rescue Exception
      $pandora_root_dir = '.'
    #end
  end
  $pandora_base_dir = File.join($pandora_root_dir, 'base')            # Default database directory
  $pandora_view_dir = File.join($pandora_root_dir, 'view')            # Media files directory
  $pandora_model_dir = File.join($pandora_root_dir, 'model')          # Model description directory
  $pandora_lang_dir = File.join($pandora_root_dir, 'lang')            # Languages directory
  $pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Default database file
  $pandora_sqlite_db2 = File.join($pandora_base_dir, 'pandora2.sqlite')  # Default database file

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
      #p tab_def
      if (! exist[table_name] or recreate) and tab_def != nil
        if exist[table_name] and recreate
          res = db.execute('DROP TABLE '+table_name)
        end
        #p 'CREATE TABLE '+table_name+' '+tab_def
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
  class Subject
    class << self
      @ider = 'Subject'
      @name = 'Субъект Пандора'
      @tables = []
      @def_fields = []
      def ider
        @ider
      end
      def ider=(x)
        @ider = x
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
      def tables
        @tables
      end
      def tables=(x)
        @tables = x
      end
      def def_fields
        @def_fields
      end
      def def_fields=(x)
        @def_fields = x
      end
    end
    def ider
      self.class.ider
    end
    def name
      self.class.name
    end
    def sname
      PandoraKernel.get_name_or_names(name)
    end
    def pname
      PandoraKernel.get_name_or_names(name, true)
    end
    def tables
      self.class.tables
    end
    def def_fields
      self.class.def_fields
    end
    def initialize
      super
    end
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

  # Pandora's document
  # RU: Документ Пандора
  class Document < Subject
    self.name = "Документ Пандора"
    def field_des(fld_name)
      super
    end
  end

  # Pandora's report
  # RU: Отчет Пандора
  class Report < Document
    self.name = "Отчет Пандора"
  end

end

# ==Pandora logic model
# RU: ==Логическая модель Пандора
module PandoraModel

  # Composing pandora model definition from XML file
  # RU: Сформировать описание модели по XML-файлу
  def self.load_model_from_xml(lang='ru')
    lang = '.'+lang
    #dir_mask = File.join(File.join($pandora_model_dir, '**'), '*.xml')
    dir_mask = File.join($pandora_model_dir, '*.xml')
    dir_list = Dir.glob(dir_mask).sort
    dir_list.each do |filename|
      file = Object::File.open(filename)
      xml_doc = REXML::Document.new(file)
      xml_doc.elements.each('pandora-model/*/*') do |element|
        subj_id = element.name
        if PandoraModel.const_defined? subj_id
          subject_class = PandoraModel.const_get(subj_id)
          subj_name = subject_class.name
          subj_tabl = subject_class.tables
          flds = subject_class.def_fields
        else
          subj_name = subj_id
          module_eval('class '+subj_id+' < PandoraKernel::Subject; self.name = "'+subj_name+'"; end')
          subject_class = PandoraModel.const_get(subj_id)
          subject_class.ider = subj_id
          subj_tabl = subj_id
          subj_tabl = PandoraKernel::get_name_or_names(subj_tabl, true)
          subj_tabl.downcase!
          subject_class.tables = [['robux', subj_tabl], ['perm', subj_tabl]]
          flds = []
        end
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
          if seu=='CALCULATE'
            #p sub_elem.name
          elsif seu=='FIELDS'
            #p sub_elem.name
          elsif seu=='TODO'
            #p sub_elem.name
          else
            i = 0
            while (i<flds.size) and (flds[i][0] != sub_elem.name) do i+=1 end
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
          end
        end
        subject_class.def_fields = flds
      end
      file.close
    end
  end

end

# ==Graphical user interface of Pandora
# RU: ==Оконный интерфейс Пандора
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

      hbox.pack_start(bbox, false, false, 1.0)

      window.signal_connect("delete-event") {
        @response=2
        false
      }
      window.signal_connect("destroy") { @response=2 }

      window.signal_connect('key-press-event') do |widget, event|
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

      bw,bh = button1.size_request
      @radio_height = bh*3

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
      form_height = window_height-@radio_height-55

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
        window_width, window_height = mw+36, mh+@radio_height+55
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
      form_height = @window_height-@radio_height-55

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

      fields = []
      @fields.each do |field|
        fields << field.dup
      end

      # create and fill field matrix to merge in form
      #step = 1
      step = 5
      found = false
      while not found do
        field_matrix = []
        mw, mh = 0, 0
        case step
          when 1,5  #normal compose. change "left" to "up" when doesn't fit to width
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
                if (mh>form_height) and (step==1)
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
                if (rw>form_width) and (step==1)
                  #step = 3
                  step = 5
                  break
                end
              end
            end
            if (step==1) or (step==5)
              field_matrix << row if row != []
              mw, mh = [mw, rw].max, mh+rh
              if ((mh>form_height) and (step==1))
                #step = 2
                step = 5
              end
            end
            found = ((step==1) or (step==5))
          when 2
            p "222"
            found = true
          when 3
            p "333"
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
  def self.show_subject_list(subject_class, widget=nil)
  end

  class TabLabelBox < Gtk::HBox

    def initialize(image, title, bodywin, *args)
      super(*args)
      label_box = self

      label_box.pack_start(image, false, false, 0) if image != nil

      label = Gtk::Label.new(title)
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
    menu.append(create_menu_item(["Create", Gtk::Stock::NEW, _("Insert"), "Insert"]))
    menu.append(create_menu_item(["Edit", Gtk::Stock::EDIT, _("Edit"), "Return"]))
    menu.append(create_menu_item(["Delete", Gtk::Stock::DELETE, _("Delete"), "Delete"]))
    menu.append(create_menu_item(["Copy", Gtk::Stock::COPY, _("Copy"), "<control>Insert"]))
    menu.append(create_menu_item(["-", nil, nil]))
    menu.append(create_menu_item(["Talk", Gtk::Stock::MEDIA_PLAY, _("Talk"), "<control>T"]))
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
    while (datasize-i)>0   #это надо затащить в цикл?
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

  # Open server socket and begin listen
  # RU: Открывает серверный сокет и начинает слушать
  def self.open_close_server_socket
    host = $host
    port = $port
    server = TCPServer.open(host, port)
    addr = server.addr
    log_message(LM_Info, 'Слушаю порт "'+host+':'+port+'" ('+addr.join(':')+')')
    Thread.new do
      loop do
        # Создать поток при подключении клиента
        Thread.start(server.accept) do |socket|
          log_message(LM_Info, "Подключился клиент: "+socket.to_s)
          # Вызвать пассивный цикл собработкой данных
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
          socket.close
          log_message(LM_Info, "Отключился клиент: "+socket.to_s)
        end
      end
      server.close
    end
    server
  end

  # RU: Открывает клиентский сокет и начинает обмен
  def self.open_client_socket(host, port)
    Thread.new do
      socket = TCPSocket.open(host, port)
      log_message(LM_Info, "Подключился к серверу: "+socket.to_s)
      # Вызвать активный цикл собработкой данных
      do_exchange_cicle(true, socket) { |rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd|
        case rcmd  # КЛИЕНТ!!! (актив)
          when EC_Init
            case rcode
              when ECC_Init0_Hello
                hello=rdata
                scmd=EC_Init
                scode=ECC_Init1_KeyPhrase
                akey="a1b2c3"
                sbuf=akey
              when ECC_Init1_KeyPhrase
                pphrase=rdata
                scmd=EC_Init
                scode=ECC_Init2_SignKey
                asign="f4443ef"
                sbuf=asign
              when ECC_Init2_SignKey
                psign=rdata
                scmd=EC_Init
                scode=ECC_Init3_PhraseSign
                aphrase="Yyyzzzzzz"
                sbuf=aphrase
              when ECC_Init3_PhraseSign
                psign=rdata
                scmd=EC_Init
                scode=ECC_Init4_Permission
                aperm="011101"
                sbuf=aperm
              when ECC_Init4_Permission
                pperm=rdata
                scmd=EC_Query
                scode=ECC_Query0_Kinds
                fromdate="fromdate=01.01.01"
                sbuf=fromdate
            end
          when EC_News
            p "news!!!!"
            if rcode==EC_News0_Kinds
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
          when EC_Notice
            p "!!notice!!!"
            pkind = rcode
            phashid = rdata
            scmd=EC_More
            scode=0 #-не надо, 1-патч, 2-запись, 3-миниатюру
            sbuf=''
          when EC_Change
            p "!change!"
          when EC_Record
            p "!record!"
          when EC_Bye
            if rcode != ECC_Bye_Exit
              log_message(LM_Error, 'Ошибка на сервере ErrCode='+rcode.to_s)
            end
            scmd=EC_Bye
            scode=ECC_Bye_Exit
          else
            scmd=EC_Bye
            scode=ECC_Bye_Unknown
            log_message(LM_Error, 'Получена неизвестная команда от сервера='+rcmd.to_s)
        end
        [rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd]
      }
      socket.close
      log_message(LM_Info, "Отключился от сервера: "+socket.to_s)
    end
  end

  $thread = nil

  def self.play_pipeline
    if $thread != nil
      pipeline1 = $thread[:pipeline1]
      pipeline2 = $thread[:pipeline2]
      p $thread.inspect
      pipeline1.play if pipeline1 != nil
      pipeline2.play if pipeline2 != nil
    end
  end

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

  # Searching a node by current record in treeview
  # RU: Поиск узла по текущей записи в таблице
  def self.define_node_by_current_record(treeview)
    # it's still a hack!
    nil
  end

  # Show conversation dialog
  # RU: Показать диалог общения
  def self.show_talk_dialog(node)
    title = 'Иван Петров'

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

    edit_box = Gtk::TextView.new
    edit_box.set_size_request(200, 70)

    hbox = Gtk::HBox.new

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

    hbox.pack_start(bbox, false, false, 1.0)

    vpaned1.pack1(area, true, false)
    vpaned1.pack2(hbox, false, true)
    vpaned1.set_size_request(350, 270)

    vpaned2.pack1(view, true, true)
    vpaned2.pack2(edit_box, false, true)

    hpaned.pack1(vpaned1, false, true)
    hpaned.pack2(vpaned2, true, true)

    $thread = Thread.new do
      Thread.stop
      pipeline1 = Gst::Pipeline.new
      pipeline2 = Gst::Pipeline.new

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

      pipeline1.play
      pipeline2.play

      Thread.current[:pipeline1] = pipeline1
      Thread.current[:pipeline2] = pipeline2

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

    $thread.run
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
        open_close_server_socket
      when 'Wander'
        open_client_socket('127.0.0.1', 5577)
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
        subject_class = PandoraModel.const_get(widget.name)
        show_subject_list(subject_class, widget)
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
    ["Synonym", nil, _("Synonyms")],
    ["Thing", nil, _("Things")],
    ["Article", nil, _("Articles")],
    ["Blob", Gtk::Stock::HARDDISK, _("Files")], #Gtk::Stock::FILE
    ["-", nil, "-"],
    ["Opinion", nil, _("Opinions")],
    [nil, nil, _("_Bussiness")],
    ["Product", nil, _("Products")],
    ["Service", nil, _("Services")],
    ["-", nil, "-"],
    ["Position", nil, _("Positions")],
    ["Nomenclature", nil, _("Nomenclatures")],
    ["Storage", nil, _("Storages")],
    ["Account", nil, _("Accounts")],
    ["-", nil, "-"],
    ["Worker", nil, _("Workers")],
    ["Client", nil, _("Clients")],
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
    ["Patche", nil, _("Patches")],
    ["Event", nil, _("Events")],
    ["Repository", nil, _("Repositories")],
    ["-", nil, "-"],
    ["Authorize", Gtk::Stock::DIALOG_AUTHENTICATION, _("Authorize")],
    ["Listen", Gtk::Stock::CONNECT, _("Listen")],
    ["Wander", Gtk::Stock::REFRESH, _("Wander")],
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

  # Showing main Gtk window
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
    $view.border_width = 0
    statusbar = Gtk::Statusbar.new
    statusbar.push(0, _('Base directory: ')+$pandora_base_dir)
    btn = Gtk::Button.new('Not logged')
    btn.relief = Gtk::RELIEF_NONE
    statusbar.pack_start(btn, false, false, 2)
    statusbar.pack_start(Gtk::SeparatorToolItem.new, false, false, 0)
    btn = Gtk::Button.new('Offline')
    btn.relief = Gtk::RELIEF_NONE
    statusbar.pack_start(btn, false, false, 2)

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


# ===Entry point
# RU: ===Точка входа

BasicSocket.do_not_reverse_lookup = true

PandoraKernel.load_language($lang)
PandoraModel.load_model_from_xml($lang)
PandoraGUI.show_main_window

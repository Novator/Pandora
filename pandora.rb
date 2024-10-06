#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# P2P social network Pandora (main script)
# RU: P2P социальная сеть Пандора (основной скрипт)
#
# This program is free software and distributed under the GNU GPLv2+
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2+
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

require 'socket'
require 'fileutils'
require_relative 'lib/utils.rb'
require_relative 'lib/model.rb'
require_relative 'lib/ui.rb'

# Default values of variables
# RU: Значения переменных по умолчанию
$poly_launch = false
$host = nil
$country = 'US'
$lang = 'en'
$autodetect_lang = true
$pandora_parameters = []
$cui_mode = nil
$screen_mode = false
$hide_on_start = false

# Paths and files
# RU: Пути и файлы
$pandora_app_dir = Dir.pwd                                     # Current directory
$pandora_lib_dir = File.join($pandora_app_dir, 'lib')          # Libraries directory
$pandora_base_dir = File.join($pandora_app_dir, 'base')        # Database directory
$pandora_view_dir = File.join($pandora_app_dir, 'view')        # Media files directory
$pandora_model_dir = File.join($pandora_app_dir, 'model')      # Model directory
$pandora_lang_dir = File.join($pandora_app_dir, 'lang')        # Languages directory
$pandora_util_dir = File.join($pandora_app_dir, 'util')        # Utilites directory
$pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')  # Database file
$pandora_files_dir = File.join($pandora_app_dir, 'files')      # Files directory
$pandora_doc_dir = File.join($pandora_app_dir, 'doc')          # Doc directory
$pandora_web_dir = File.join($pandora_app_dir, 'web')          # Web files directory

# Check Ruby version
# RU: Проверить версию Ruby
if RUBY_VERSION<'1.9'
  puts 'Pandora requires Ruby1.9 or higher - current '+RUBY_VERSION
  Kernel.exit(10)
end

# Init ASCII string for binary data
# RU: Объявить ASCII-строку для бинарных данных
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

# Init UTF8 string for human strings
# RU: Объявить UTF8-строку для человечьих строк
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

# Some global settings
# RU: Некоторые глобальные настройки
Encoding.default_external = 'UTF-8'
Encoding.default_internal = 'UTF-8'
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true
#Thread.abort_on_exception = false

# Expand the arguments of command line
# RU: Разобрать аргументы командной строки
arg = nil
val = nil
next_arg = nil
ARGVdup = ARGV.dup
show_help = false
runit = 'ruby pandora.rb'
while (ARGVdup.size>0) or next_arg
  if next_arg
    arg = next_arg
    next_arg = nil
  else
    arg = ARGVdup.shift
  end
  if arg.is_a?(String) and (arg.size>0) and (arg[0]=='-')
    i = arg.index('=')
    if i and (i<20)
      val = arg[i+1..-1]
      arg = arg[0, i]
    else
      if ARGVdup.size>0
        next_arg = ARGVdup.shift
      end
      if next_arg and next_arg.is_a? String and (next_arg[0,1] != '-')
        val = next_arg
        next_arg = nil
      end
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
      if val.is_a?(String) and (val.size>1)
        $lang = val[0, 2].downcase
        if (val.size>4) and (val[2]=='-')
          $country = val[3, 2]
        else
          $country = $lang
        end
        $country = $country.upcase
        $autodetect_lang = false
        puts 'Setted language/country '+[$lang, $country].inspect
      end
    when '-d', '--database'
      $pandora_sqlite_db = File.join($pandora_base_dir, val) if val
      puts 'Setted db file: '+$pandora_sqlite_db.inspect
    when '-b', '--basedir'
      def_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')
      $pandora_base_dir = val if val
      puts 'Setted basedir: '+$pandora_base_dir.inspect
      if $pandora_sqlite_db==def_sqlite_db
        $pandora_sqlite_db = File.join($pandora_base_dir, 'pandora.sqlite')
        puts 'Setted db file: '+$pandora_sqlite_db.inspect
      end
    when '-m', '--md5'
      puts PandoraUtils.pandora_md5_sum
      Kernel.exit(0)
    when '-v', '--version'
      puts PandoraUtils.pandora_version
      Kernel.exit(0)
    when '-pl', '--poly', '--poly-launch'
      $poly_launch = true
    when '-n', '--hide', '--minimize'
      $hide_on_start = true
    when '-c','--curses','--cui', '--console'
      $cui_mode = 1
    when '-nc','--ncurses'
      $cui_mode = 2
    when '-s','--screen'
      $cui_mode = 1 if $cui_mode.nil?
      $screen_mode = true
    when '--shell'
      runit = 'pandora.sh'
    when '--appimage'
      runit = 'Pandora-N.NN-x86_64.AppImage'
    when '-?','--help'
      show_help = true
    else
      if (arg.size>0)
        arg += '='+val.to_s if val
        puts('!!!Bad argument: '+arg)
        show_help = true
      end
  end
  val = nil
end
if show_help
  runit = '  '+runit+' '
  puts 'Ruby script Pandora params (examples):'
  puts runit+'-?|--help        - this help'
  puts runit+'-h localhost     - listen address'
  puts runit+'-p '+PandoraNet::DefTcpPort.to_s+'          - listen TCP/UDP port'
  puts runit+'-b ./base        - set base dir (default "./base" or "~/.pandora" for AppImage)'
  puts runit+'-d pandora2.sqlite   - set database file'
  puts runit+'-l ua|--lang ua  - set Ukrainian language (other also possible)'
  puts runit+'-m|--md5         - calc MD5 of all Pandora scripts'
  puts runit+'-v|--version     - show Pandora version'
  puts runit+'-pl|--poly       - allow poly (many) launch'
  puts runit+'-n|--hide        - start hidden and minimized'
  puts runit+'-c|--curses      - console user interface (CUI) via curses'
  puts runit+'-nc|--ncurses    - console user interface (CUI) via ncurses'
  Kernel.exit!
end

# Pandora Unix Socket file and its handle
PANDORA_USOCK = '/tmp/pandora_unix_socket'
$pserver = nil

#Create BaseDir if not exist
FileUtils.mkdir_p($pandora_base_dir) unless Dir.exists?($pandora_base_dir)

# Delete Pandora unix socket
# RU: Удаляет unix-сокет Пандоры
def delete_psocket
  File.delete(PANDORA_USOCK) if File.exist?(PANDORA_USOCK)
end

$win32api = nil

# Initialize win32 unit
# RU: Инициализировать модуль win32
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
ANOTHER_COPY_MES = 'Another copy of Pandora is already runned (use -pl option to polylaunch run)'

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
      puts(ANOTHER_COPY_MES)
      Kernel.exit
    else
      begin
        delete_psocket
        $pserver = UNIXServer.new(PANDORA_USOCK)
        Thread.new do
          while (not $pserver.closed?)
            begin
              psocket = $pserver.accept
            rescue
              psocket = nil
            end
            if psocket
              Thread.new(psocket) do |psocket|
                while psocket and (not psocket.closed?)
                  begin
                    command = psocket.recv(255)
                  rescue
                    command = nil
                  end
                  if $window and command.is_a?(String) and (command.size>0)
                    PandoraUI.do_menu_act(command)
                  elsif (not psocket.closed?)
                    psocket.close
                    psocket = nil
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

# Redirect console output to file, because of rubyw.exe crush
# RU: Перенаправить консольный вывод в файл из-за краша rubyw.exe
if $cui_mode or (PandoraUtils.os_family=='windows')
  fn = 'stdout'
  fn = 'stderr' if $cui_mode
  #$stderr.reopen(File.join($pandora_base_dir, fn+'.log'), 'w')
  #$stdout = $stderr if (not $cui_mode)
end

# WinAPI constants for work with the registry
# RU: Константы WinAPI для работы с реестром
HKEY_CURRENT_USER  = 0x80000001
HKEY_LOCAL_MACHINE = 0x80000002
STANDARD_RIGHTS_READ = 0x00020000
KEY_QUERY_VALUE = 0x0001
KEY_ENUMERATE_SUB_KEYS = 0x0008
KEY_NOTIFY = 0x0010
KEY_READ = STANDARD_RIGHTS_READ | KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY

# Read Windows registry value by path and key
# RU: Читает значение реестра винды по пути и ключу
def read_win_reg(path, key, root=nil, res_format=nil)
  res = nil
  if init_win32api
    $waRegOpenKeyEx ||= Win32API.new('advapi32', 'RegOpenKeyEx', 'LPLLP', 'L')
    $waRegQueryValueEx ||= Win32API.new('advapi32', 'RegQueryValueEx', 'LPLPPP', 'L')
    $waRegCloseKey ||= Win32API.new('advapi32', 'RegCloseKey', 'L', 'L')
    if $waRegOpenKeyEx and $waRegQueryValueEx and $waRegCloseKey
      if root==:hkcu
        root = HKEY_CURRENT_USER
      else  #root==:hklm
        root = HKEY_LOCAL_MACHINE
      end
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
            i = 0
            while (i<1024) and (buf[i] != 0.chr)
              i += 1
            end
            res = buf[0, i] if i>0
            #p '---res='+res.inspect
            if res and res_format
              if res_format==:hex
                res = res.to_i(16)
              end
            end
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

# Set windows language codes
# RU: Задать виндовые языковые коды
def set_win_lang_codes(lcode)
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
  lcode[0x0406] = 'da;Danish'  #changed from "the"
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
  lcode[0x0420] = 'ur;Urdu'  #changed from "your"
  lcode[0x042A] = 'vi;Vietnamese'
  lcode[0x0434] = 'xh;Xhosa'
  lcode[0x043D] = 'ji;Yiddish'
  lcode[0x0435] = 'zu;Zulu'
end

# Get language from environment parameters
# RU: Взять язык из переменных окружения
if $autodetect_lang
  lang = ENV['LANG']
  if (lang.is_a? String) and (lang.size>1)
    $lang = lang[0, 2].downcase
    if (lang.size>4)
      $country = lang[3, 2].upcase
    else
      $country = $lang
    end
    $country = $country.upcase
  elsif PandoraUtils.os_family=='windows'
    #http://forum.oszone.net/thread-193406.html
    #HKCU\Control Panel\International\sLanguage: "RUS"
    lang_code = read_win_reg('Control Panel\International', 'Locale', \
      :hkcu, :hex)
    p 'lang_code1='+lang_code.inspect
    #lang_code = nil
    #if (not lang_code) or (lang_code==0)
    #  lang_code = read_win_reg('SYSTEM\CurrentControlSet\Control\MUI\Settings', \
    #    'PreferredUiLanguages', :hklm)
    #  p 'lang_code2='+lang_code.inspect
    #end
    if (not lang_code) or (lang_code==0)
      lang_code = read_win_reg('SYSTEM\CurrentControlSet\Control\Nls\Language', \
        'Default', :hklm, :hex)
      p 'lang_code3='+lang_code.inspect
    end
    if (not lang_code) or (lang_code==0)
      lang_code = read_win_reg('SYSTEM\controlset001\Control\Nls\Language', \
        'Default', :hklm, :hex)
      p 'lang_code4='+lang_code.inspect
    end
    if (not lang_code) or (lang_code==0)
      lang_code = read_win_reg('SYSTEM\CurrentControlSet\Control\Nls\Language', \
        'InstallLanguage', :hklm, :hex)
      p 'lang_code5='+lang_code.inspect
    end
    if (not lang_code) or (lang_code==0)
      lang_code = read_win_reg('SYSTEM\controlset001\Control\Nls\Language', \
        'InstallLanguage', :hklm, :hex)
      p 'lang_code6='+lang_code.inspect
    end
    if (not lang_code) or (lang_code==0)
      #HKCU\Control Panel\International\LocaleName: "ru-RU"
      lang_code = read_win_reg('Control Panel\International', \
        'LocaleName', :hkcu)
      p 'lang_code9='+lang_code.inspect
    end
    p '===FINAL lang_code='+lang_code.inspect
    if lang_code
      lang = nil
      if lang_code.is_a?(Integer)
        lcode = {}
        set_win_lang_codes(lcode)
        lang = lcode[lang_code]
      elsif lang_code.is_a?(String)
        lang = lang_code
      end
      if lang.is_a?(String) and (lang.size>1)
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

#Forced language setup
#$lang = 'ua'

# === Running the Pandora!
# === RU: Запуск Пандоры!
PandoraUtils.load_language($lang)
PandoraModel.load_model_from_xml($lang)

lang = PandoraUtils.get_param('interface_language')
if lang.is_a?(String) and (lang.size>1)
  lang0 = $lang
  $lang = lang[0, 2].downcase
  if (lang.size>4)
    $country = lang[3, 2].upcase
  else
    $country = $lang
  end
  $country = $country.upcase
  PandoraUtils.load_language($lang) if lang0 != $lang
end

PandoraUtils.detect_mp3_player
PandoraUtils.init_base_id
PandoraUI.init_user_interface_and_network($cui_mode)

# Free unix-socket on exit
# Освободить unix-сокет при выходе
$pserver.close if ($pserver and (not $pserver.closed?))
delete_psocket


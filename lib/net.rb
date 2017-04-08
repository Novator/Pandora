#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Network classes of Pandora
# RU: Сетевые классы Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

require 'socket'
require File.expand_path('../utils.rb',  __FILE__)

$pool = nil

$media_buf_size = 50
$send_media_queues = []
$send_media_rooms = {}

module PandoraNet

  include PandoraUtils

  # Version of protocol
  # RU: Версия протокола
  ProtocolVersion = 'pandora0.67'

  DefTcpPort = 5577
  DefUdpPort = 5577

  CommSize     = 7
  CommExtSize  = 10
  SegNAttrSize = 8

  # Network exchange commands
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

  # Extentions codes of commands
  # RU: Коды расширения команд
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
  CM_MassExch     = 4
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
  MK_BlockWeb   = 7

  # Node list indexes
  # RU: Индексы в списке узлов
  NL_Key             = 1  #22
  NL_BaseId          = 2  #16
  NL_Person          = 3  #22
  NL_Time            = 4  #4

  # Common field indexes of mass record array  #(size of field)
  # RU: Общие индексы полей в векторе массовых записей
  #==========================={head
  MR_Node            = 0  #22
  MR_Index           = 1  #4
  MR_CrtTime         = 2  #4
  MR_Trust           = 3  #1
  MR_Depth           = 4  #1
  #---------------------------head} (33 byte)
  #==========================={body
  MR_Param1          = 5  #1-30
  MR_Param2          = 6  #22-140
  MR_Param3          = 7  #0 или 22
  #---------------------------body} (23-140 byte)
  MR_Kind            = 8   #1  (presence, fishing, chat, search)
  MR_KeepNodes       = 9  #(0-220) fill when register, not sending
  MR_Requests        = 10  #4

  # Alive
  MRP_Nick           = MR_Param1  #~30    #sum: 33+(~30)= ~63

  # Chat field indexes
  # RU: Чатовые индексы полей
  #----Head sum: 70
  MRC_Dest     = MR_Param1   #22 (panhash)
  MRC_MesRow   = MR_Param2   #~140 (panhash or message)   #sum: 33+22+(~140)= ~125

  # MesRow (chat message row) parameters
  # RU: Параметры сообщения чата
  MCM_Creator  = 0
  MCM_Created  = 1
  MCM_Text     = 2
  MCM_PanState = 3
  MCM_Id       = 4   #not send
  MCM_Dest     = 5   #not send

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
    attr_accessor :sessions, :white_list, :time_now, \
      :node_list, :mass_records, :mass_ind, :found_ind, :punnets, :ind_mutex

    MaxWhiteSize = 500
    FishQueueSize = 100

    def initialize
      super()
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

    def mutex
      @mutex ||= Mutex.new
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
            PandoraUI.log_message(PandoraUI::LM_Info, _('Tunnel listen')+': '+addr_str)
          rescue
            server = nil
            PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot open port')+' TCP '+host.to_s+':'+tcp_port.to_s)
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
              unless $pool.is_black?(host_ip)
                host_name = socket.peeraddr[3]
                port = socket.peeraddr[1]
                proto = 'tcp'
                #p 'TUNNEL: '+[host_name, host_ip, port, proto].inspect
                session = Session.new(socket, host_name, host_ip, port, proto, \
                  0, nil, nil, nil, nil)
              else
                PandoraUI.log_message(PandoraUI::LM_Info, _('IP is banned')+': '+host_ip.to_s)
              end
            end
          end
          server.close if server and (not server.closed?)
          PandoraUI.log_message(PandoraUI::LM_Info, _('Listener stops')+' '+addr_str) if server
          #PandoraUI.set_status_field(PandoraUI::SF_Listen, nil, nil, false)
          #$tcp_listen_thread = nil
          #PandoraUI.correct_lis_btn_state
        end
      end
    end

    # Check is whole file exist
    # RU: Проверяет целый файл на существование
    def blob_exists?(sha1, models=nil, need_fn=nil)
      res = nil
      #p 'blob_exists1   sha1='+sha1.inspect
      if (sha1.is_a? String) and (sha1.bytesize>0)
        model = PandoraUtils.get_model('Blob', models)
        if model
          mask = 0
          mask = PandoraModel::PSF_Harvest if (not need_fn)
          filter = ['sha1=? AND IFNULL(panstate,0)&?=0', sha1, mask]
          flds = 'id'
          flds << ', blob, size' if need_fn
          sel = model.select(filter, false, flds, nil, 1)
          #p 'blob_exists2   sel='+sel.inspect
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
        #p '--++--reset_harvest_bit   sel='+sel.inspect
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
              #p '[bit_tail_sh, bit_tail, frag_count, frags[i].ord]='+[bit_tail_sh, \
              #  bit_tail, frag_count, frags[i].ord].inspect
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
      #p 'init_punnet(sha1,filesize,initfilename)='+[sha1,filesize,initfilename].inspect
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
          #p 'dir='+dir.inspect
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
        #p 'filename='+filename.inspect

        frag_fn = PandoraUtils.change_file_ext(filename, 'frs')
        frag_fn = Utf8String.new(frag_fn)
        punnet[PI_FragFN] = frag_fn
        #p 'frag_fn='+frag_fn.inspect

        file_size = File.size?(filename)
        #p 'file_size='+file_size.inspect
        filename_ex = (File.exist?(filename) and (not file_size.nil?) and (file_size>=0))
        filesize ||= file_size if filename_ex
        punnet[PI_FileSize] = filesize
        #p 'filename_ex='+filename_ex.inspect
        frag_fn_ex = File.exist?(frag_fn)
        #p 'frag_fn_ex='+frag_fn_ex.inspect

        fragfile = nil
        if frag_fn_ex
          fragfile = File.open(frag_fn, 'rb+')
          #p "fragfile = File.open(frag_fn, 'rb+')"
        elsif not filename_ex
          PandoraUtils.create_path(frag_fn)
          fragfile = File.new(frag_fn, 'wb+')
          #p "fragfile = File.new(frag_fn, 'wb+')"
        end

        frag_count = (filesize.fdiv($fragment_size)).ceil
        sym_count = (frag_count.fdiv(8)).ceil
        #p '[frag_count, sym_count]='+[frag_count, sym_count].inspect
        punnet[PI_FragCount] = frag_count
        punnet[PI_SymCount] = sym_count

        if fragfile
          punnet[PI_FragsFile] = fragfile
          frags = fragfile.read
          #frag_com = frags_complite?(frags)
          #p 'frags='+frags.inspect
          sym_count = 1 if sym_count < 1
          if frags.bytesize != sym_count
            if sym_count>frags.bytesize
              frags += 0.chr * (sym_count-frags.bytesize)
              fragfile.seek(0)
              fragfile.write(frags)
              #p 'set frags='+frags.inspect
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
      #p 'save_frag [datafile, fragfile, frags]='+[datafile, fragfile, frags].inspect
      if datafile and fragfile and frags
        datafile.seek(frag_number*$fragment_size)
        res = datafile.write(frag_data)
        sym_num = (frag_number.fdiv(8)).floor
        bit_num = frag_number - sym_num*8
        bit_mask = 1
        bit_mask = 1 << bit_num if bit_num>0
        #p 'sf [sym_num, bit_num, bit_mask]='+[sym_num, bit_num, bit_mask].inspect
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
        #p 'hold_frag_number [sym_num, bit_num, bit_mask]='+[sym_num, bit_num, bit_mask].inspect
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
      #p 'hold_next_frag  [fragfile, frags, frag_count]='+[fragfile, frags, frag_count].inspect
      if fragfile and (frags.is_a? String) and (frags.bytesize>0) \
      and (not frags_complite?(frags, frag_count))
        i = 0
        sym_count = frags.bytesize

        $pool.mutex.synchronize do
          while i<sym_count
            byte = frags[i].ord
            if byte != 255
              hold_byte = hold_frags[i].ord
              #p 'hold_byte='+hold_byte.inspect
              j = 0
              while (byte>0) and (i*8+j<frag_count-1) \
              and (((byte & 1) == 1) or ((hold_byte & 1) == 1))
                byte = byte >> 1
                hold_byte = hold_byte >> 1
                j += 1
              end
              #p 'hold [frags[i].ord, i, j]='+[frags[i].ord, i, j].inspect
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
        #p 'closepun [frag_com, file_size, filesize]='+[frag_com, \
        #  file_size, filesize].inspect
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
        PandoraUI.update_conn_status(conn, conn.conn_type, 1)
      end
    end

    # Delete the session from list
    # RU: Удаляет сессию из списка
    def del_session(conn)
      if sessions.delete(conn)
        PandoraUI.update_conn_status(conn, conn.conn_type, -1)
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
        mr and ((mr[PandoraNet::MR_Node] == src_node) and \
        (mr[PandoraNet::MR_Index] == src_ind))
      end
      res
    end

    def find_mass_record_by_params(src_node, akind, param1, param2=nil, param3=nil)
      res = nil
      param2 = AsciiString.new(param2) if akind==MK_Search
      res = @mass_records.find do |mr|
        mr and ((mr[PandoraNet::MR_Node] == src_node) and \
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
        ind_mutex.synchronize do
          if (not src_ind) and (src_node==self_node)
            @mass_ind += 1
            src_ind = @mass_ind
          end
          if src_ind
            mr = Array.new
            mr[MR_Node]     = src_node
            mr[MR_Index]    = src_ind
            mr[MR_KeepNodes] = [keep_node]
            yield(mr) if block_given?
            @mass_records << mr
          end
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
        adepth ||= 3
        adepth -= 1
        #p '------add_mass_rec1  adepth='+adepth.inspect
        if adepth >= 0
          cur_time = Time.now.to_i
          #delete_old_mass_records(cur_time)
          case akind
            when MK_Search
              param2 = AsciiString.new(param2)
          end
          mr = register_mass_record(src_node, src_ind, keep_node) do |mr|
            atime ||= cur_time
            mr[MR_Kind]     = akind
            mr[MR_CrtTime]  = atime
            mr[MR_Trust]    = atrust
            mr[MR_Depth]    = adepth
            mr[MR_Param1]   = param1
            mr[MR_Param2]   = param2
            mr[MR_Param3]   = param3
          end
          if mr
            case akind
              when MK_Presence
                PandoraUI.set_status_field(PandoraUI::SF_Radar, @mass_records.size.to_s)
                PandoraUI.update_or_show_radar_panel
              when MK_Fishing
                PandoraUI.set_status_field(PandoraUI::SF_Fisher, @mass_records.size.to_s)
                info = ''
                fish = param1
                fish_key = param2
                info << PandoraUtils.bytes_to_hex(fish) if fish
                info << ', '+PandoraUtils.bytes_to_hex(fish_key) if fish_key.is_a? String
                PandoraUI.log_message(PandoraUI::LM_Trace, _('Bob is generated')+ \
                  ' '+@mass_ind.to_s+':['+info+']')
              when MK_Search
                PandoraUI.set_status_field(PandoraUI::SF_Search, @mass_records.size.to_s)
                PandoraNet.start_hunt if hunt
              when MK_Chat
                #
            end
            #p '=======add_mass_rec2  mr='+mr.inspect
          end
        end
      end
      mr
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
        #p [word1, word2, word3, words]
        word1dup = word1.dup
        filter1, word1 = name_filter('first_name', word1)
        filter2, word2 = name_filter('last_name', word2) if word2
        word4 = nil
        if word3
          word3, word4 = word3.split('-')
          #p [word3, word4]
          word3 = PandoraUtils.str_to_date(word3).to_i
          word4 = PandoraUtils.str_to_date(word4).to_i if word4
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

    def send_chat_messages(message_model=nil, models=nil)
      filter = 'state=0 AND IFNULL(panstate,0)&'+PandoraModel::PSF_ChatMes.to_s+'>0'
      fields = 'creator, created, text, panstate, id, destination'
      message_model ||= PandoraUtils.get_model('Message', models)
      sel = message_model.select(filter, false, fields, 'created', \
        $mes_block_count)
      if sel and (sel.size>0)
        #@send_state = (send_state | CSF_Messaging)
        i = 0
        talkview = nil
        talkview = @dialog.chat_talkview if @dialog
        ids = nil
        ids = [] if talkview
        while sel and (i<sel.size)
          row = sel[i]
          panstate = row[MCM_PanState]
          if panstate
            row[MCM_PanState] = (panstate & (PandoraModel::PSF_Support | \
              PandoraModel::PSF_Crypted | PandoraModel::PSF_Verified | \
              PandoraModel::PSF_ChatMes))
          end
          #creator = row[1]
          id = row[MCM_Id]
          dest = row[MCM_Dest]
          #text = row[4]
          #if ((panstate & PandoraModel::PSF_Crypted)>0) and text
          #  dest_key = @skey[PandoraCrypto::KV_Panhash]
          #  text = PandoraCrypto.recrypt_mes(text, nil, dest_key)
          #  row[4] = text
          #end
          #p '---Add MASS Mes: row='+row.inspect
          row_pson = PandoraUtils.rubyobj_to_pson(row[MCM_Creator..MCM_PanState])
          #p log_mes+'%%%Send EC_Message: [row_pson, row_pson.len]='+\
          #  [row_pson, row_pson.bytesize].inspect
          #row, len = PandoraUtils.pson_to_rubyobj(row_pson)
          #p log_mes+'****Send EC_Message: [len, row]='+[len, row].inspect
          if add_mass_record(MK_Chat, dest, row_pson)
          #if add_send_segment(EC_Message, true, row_pson)
            res = message_model.update({:state=>2}, nil, {:id=>id})
            if res
              ids << id if ids
            else
              PandoraUI.log_message(PandoraUI::LM_Error, _('Updating state of sent message')+' id='+id.to_s)
            end
          else
            PandoraUI.log_message(PandoraUI::LM_Error, _('Adding message to send queue')+' id='+id.to_s)
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
      end
    end

    # Find or create session with necessary node
    # RU: Находит или создает соединение с нужным узлом
    def init_session(addr=nil, nodehashs=nil, send_state_add=nil, dialog=nil, \
    node_id=nil, persons=nil, key_hashs=nil, base_id=nil, aconn_mode=nil)
      #p '-------init_session: '+[addr, nodehashs, send_state_add, dialog, node_id, \
      #  persons, key_hashs, base_id].inspect
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
        #p 'NEED connect: '+[addr, nodehash].inspect
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
              if PandoraUI.captcha_win_available?
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
      #p 'stop_session1 nodehashs='+nodehashs.inspect
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
          #p 'check_incoming_addr DONE [host, port, proto]='+[host, port, proto].inspect
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
  $trust_for_unknown = nil
  $low_conn_trust = 0.0

  $keep_alive = 1  #(on/off)
  $keep_idle  = 5  #(after, sec)
  $keep_intvl = 1  #(every, sec)
  $keep_cnt   = 4  #(count)

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
      :captcha_sw, :hooks, :mr_ind, :sess_trust, :notice, :activity

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
      $pool
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
        PandoraUI.log_message(PandoraUI::LM_Error, _('Wrong length of command extention'))
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
        #p log_mes+'####-=-=--=-=-=-=-==-NO CIPHER buf='+res.inspect
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
        #p log_mes+'->>SEND [cmd, code, lengt] [stage, ciphering]='+\
        #  [cmd, code, lengt].inspect+' '+[@stage, @ciphering].inspect
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
            #p '@media_send = true'
          end
        else
          nodelay = nil
          if @media_send
            socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0)
            nodelay = 0
            @media_send = false
            #p '@media_send = false'
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
            PandoraUI.log_message(PandoraUI::LM_Error, _('Not all data was sent')+' '+sended.to_s)
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
              PandoraUI.log_message(PandoraUI::LM_Error, _('Not all data was sent')+'2 '+sended.to_s)
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
            #p 'Add search sess_hook='+sess_hook.inspect
          end
          if sess_hook
            rec = sess.hooks[sess_hook]
            #p 'Fisher send  rec[hook, self, sess_id, fhook]='+[hook, self.object_id, \
            #  sess.object_id, rec[LHI_Far_Hook], rec[LHI_Sess_Hook]].inspect
            segment = [cmd, code].pack('CC')
            segment << data if data
            far_hook = rec[LHI_Far_Hook]
            if far_hook
              #p 'EC_Bite [fhook, segment]='+ [far_hook, segment.bytesize].inspect
              res = sess.send_queue.add_block_to_queue([EC_Bite, far_hook, segment])
            else
              #p 'EC_Lure [hook, segment]='+ [hook, segment.bytesize].inspect
              res = sess.send_queue.add_block_to_queue([EC_Lure, hook, segment])
            end
          else
            #p 'No sess_hook by hook='+hook.inspect
          end
        else
          #p 'No active hook: '+@hooks.size.to_s
        end
      else
        #p 'No socket. No hooks'
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
        PandoraUI.log_message(PandoraUI::LM_Warning, logmes+mesadd)
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
            mode |= CM_MassExch if $mass_exchange
            mode |= CM_Captcha if (@conn_mode & CM_Captcha)>0
            hparams = {:version=>ProtocolVersion, :mode=>mode, :mykey=>key_hash, :tokey=>tokey, \
              :notice=>(($mass_depth << 8) | $mass_trust)}
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
        #p '--add_send_segment: @send_queue OVERFLOW !!!'
      end
      if ascmd != EC_Media
        asbuf ||= '';
        #p log_mes+'add_send_segment:  [ascmd, ascode, asbuf.bytesize]='+[ascmd, ascode, asbuf.bytesize].inspect
        #p log_mes+'add_send_segment2: asbuf='+asbuf.inspect if sbuf
      end
      if not res
        PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot add segment to send queue'))
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
          PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot add request'))
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
          PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot add query'))
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
      #p 'send_conn_mode  buf='+buf.inspect
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
        #p log_mes+'RECOGNIZE_params: '+hash.inspect
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
                #p log_mes+'send phrase len='+phrase.bytesize.to_s
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
        #p log_mes+'send_captcha:  attempts='+attempts.to_s
        if attempts<$captcha_attempts
          @skey[PandoraCrypto::KV_Trust] = attempts+1
          @scmd = EC_Auth
          @scode = ECC_Auth_Captcha
          text, buf = PandoraUtils.generate_captcha(nil, $captcha_length)
          params['captcha'] = text.downcase
          clue_text = 'You may enter small letters|'+$captcha_length.to_s+'|'+\
            PandoraGtk::CapSymbols
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
        #p log_mes + '++++++++update_node [skey_panhash, sbase_id, trust, session_key]=' \
        #  +[skey_panhash, sbase_id, trust, session_key].inspect

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
          @dialog = PandoraUI.show_cabinet(panhash, self, conn_type)
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
        #p '--reg_line  [far_hook, hook, sess_hook, self, session]='+\
        #  [far_hook, hook, sess_hook, self.object_id, session.object_id].inspect
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
          #p 'Register hook='+hook.inspect
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
        #p '=====reg_line  [session, far_hook, hook, sess_hook]='+[session.object_id, \
        #  far_hook, hook, sess_hook].inspect
        [hook, rec]
      end

      # Connect session to the hook
      # RU: Присоединить сессию к крючку
      def connect_session_to_hook(sessions, hook, fisher=false, line=nil)
        res = false
        if (sessions.is_a? Array) and (sessions.size>0)
          sessions.each do |session|
            sthread = session.send_thread
            if sthread and sthread.alive? and sthread.stop?
              sess_hook, rec = self.reg_line(line, nil, hook)
              fhook, rec = session.reg_line(nil, self, nil, nil, sess_hook)
              sess_hook2, rec2 = self.reg_line(nil, session, nil, sess_hook, fhook)
              PandoraUI.log_message(PandoraUI::LM_Info, _('Unfreeze fisher')+\
                ': [session, hook]='+[session.object_id, sess_hook].inspect)
              sthread.run
              res = true
              break
            end
          end
        end
        res
      end

      # Initialize the fishing line, send hooks
      # RU: Инициализировать рыбацкую линию, разослать крючки
      def init_line(line_order, akey_hash=nil)
        res = nil
        fisher, fisher_key, fisher_baseid, fish, fish_key = line_order
        if fisher_key and fisher_baseid and (fish or fish_key)
          if akey_hash and (fisher_key == akey_hash) and (fisher_baseid == pool.base_id)
            # fishing from me
            PandoraUI.log_message(PandoraUI::LM_Warning, _('Somebody uses your ID'))
          else
            res = false
            # check fishing to me (not using!!!)
            if false and ((fish == pool.person) or (fish_key == akey_hash))
              #p log_mes+'Fishing to me!='+session.to_key.inspect
              # find existing (sleep) sessions
              sessions = sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
              if (not sessions.is_a? Array) or (sessions.size==0)
                sessions = Session.new(111)
              end
              line = line_order.dup
              line[MR_Fish] ||= pool.person
              line[MR_Fish_key] ||= pool.key_hash
              line[LN_Fish_Baseid] = pool.base_id
              #p log_mes+' line='+line.inspect
              #session = self.connect_session_to_hook([session], hook)
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
              #p 'FOUND fishers/fishes: '+sessions.size.to_s
              line = line_order.dup
              if fisher_sess
                line[MR_Fish] = @to_person if (not fish)
                line[MR_Fish_key] = @to_key if (not fish_key)
                line[LN_Fish_Baseid] = @to_base_id
              end
              sessions.each do |session|
                #p log_mes+'--Fisher/Fish session='+[session.object_id, session.to_key].inspect
                if not fisher_sess
                  line[MR_Fish] = session.to_person if (not fish)
                  line[MR_Fish_key] = session.to_key if (not fish_key)
                  line[LN_Fish_Baseid] = session.to_base_id
                end
                #p log_mes+' reg.line='+line.inspect
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
        res
      end

      # Clear out lures for the fisher and input lure
      # RU: Очистить исходящие наживки для рыбака и входящей наживки
      def free_out_lure_of_fisher(fisher, in_lure)
        val = [fisher, in_lure]
        #p '====//// free_out_lure_of_fisher(in_lure)='+in_lure.inspect
        while out_lure = @fishers.index(val)
          #p '//// free_out_lure_of_fisher(in_lure), out_lure='+[in_lure, out_lure].inspect
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
          #p '//// free_fish_of_in_lure(in_lure)='+in_lure.inspect
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
        #p '=== send_segment_to_fish(hook, segment.size)='+[hook, segment.bytesize].inspect
        if hook and segment and (segment.bytesize>1)
          rec = nil
          if lure
            hook = @hooks.index {|rec| (rec[LHI_Far_Hook]==hook) }
            #p 'lure hook='+hook.inspect
          end
          if hook
            rec = @hooks[hook]
            #p 'Hook send: [hook, lure]'+[hook, lure].inspect
            if rec
              sess = rec[LHI_Session]
              sess_hook = rec[LHI_Sess_Hook]
              if sess and sess_hook
                rec = sess.hooks[sess_hook]
                if rec
                  if rec[LHI_Line]
                    #p 'Middle hook'
                    #hook = sess.hooks.index {|rec| (rec[LHI_Session]==self) and (rec[LHI_Sess_Hook]==hook) }
                    if rec[LHI_Far_Hook]
                      res = sess.send_queue.add_block_to_queue([EC_Bite, rec[LHI_Far_Hook], segment])
                    else
                      res = sess.send_queue.add_block_to_queue([EC_Lure, hook, segment])
                    end
                    @last_send_time = pool.time_now
                  else
                    #p 'Terminal hook'
                    cmd = segment[0].ord
                    code = segment[1].ord
                    data = nil
                    data = segment[2..-1] if (segment.bytesize>2)
                    res = sess.read_queue.add_block_to_queue([cmd, code, data])
                  end
                else
                  #p 'No neighbor rec'
                  @scmd = EC_Wait
                  @scode = EC_Wait5_NoNeighborRec
                  @scbuf = nil
                end
              else
                #p 'No sess or sess_hook'
                @scmd = EC_Wait
                @scode = EC_Wait4_NoSessOrSessHook
                @scbuf = nil
              end
            else
              #p 'No hook rec'
              @scmd = EC_Wait
              @scode = EC_Wait3_NoFishRec
              @scbuf = nil
            end
          else
            #p 'No far hook'
            @scmd = EC_Wait
            @scode = EC_Wait2_NoFarHook
            @scbuf = nil
          end
        else
          #p 'No hook or segment'
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
            #pool.add_mass_record(MK_Presence, nick, nil, nil, \
            #  nil, nil, nil, not_trust, not_dep, pool.self_node, \
            #  nil, @recv_models)
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
                  if vers==ProtocolVersion
                    addr = params['addr']
                    #p log_mes+'addr='+addr.inspect
                    # need to change an ip checking
                    pool.check_incoming_addr(addr, host_ip) if addr
                    @sess_mode = params['mode']
                    #p log_mes+'ECC_Auth_Hello @sess_mode='+@sess_mode.inspect
                    @notice = params['notice']
                    init_skey_or_error(true)
                  else
                    err_scmd('Unsupported protocol "'+vers.to_s+\
                      '", require "'+ProtocolVersion+'"', ECC_Bye_Protocol)
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
                #p log_mes+'recived phrase len='+rphrase.bytesize.to_s
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
                #p log_mes+'recived captcha='+captcha if captcha
                if captcha.downcase==params['captcha']
                  @stage = ES_Greeting
                  if not (@skey[PandoraCrypto::KV_Trust].is_a? Float)
                    if $trust_for_captchaed
                      @skey[PandoraCrypto::KV_Trust] = 0.01
                    else
                      @skey[PandoraCrypto::KV_Trust] = nil
                    end
                  end
                  #p log_mes+'Captcha is GONE!  '+@conn_mode.inspect
                  if not hunter?
                    #p log_mes+'Captcha add_send_segment params[srckey]='+params['srckey'].inspect
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
                #p log_mes+'recived [rsign, sbase_id, acipher] len='+[rsign, sbase_id, acipher].inspect
                @skey = PandoraCrypto.open_key(@skey, @recv_models, true)
                if @skey and @skey[PandoraCrypto::KV_Obj]
                  if PandoraCrypto.verify_sign(@skey, \
                  OpenSSL::Digest::SHA384.digest(params['sphrase']), rsign)
                    trust = @skey[PandoraCrypto::KV_Trust]
                    skey_hash = @skey[PandoraCrypto::KV_Panhash]
                    init_and_check_node(@skey[PandoraCrypto::KV_Creator], skey_hash, sbase_id)
                    if ((@conn_mode & CM_Double) == 0)
                      if (not hunter?)
                        if ($trust_for_unknown.is_a? Float) and ($trust_for_unknown > -1.0001)
                          trust = $trust_for_unknown
                          @skey[PandoraCrypto::KV_Trust] = trust
                        else
                          trust = 0 if (not trust) and $trust_for_captchaed
                        end
                      elsif $trust_for_listener and (not (trust.is_a? Float))
                        trust = 0.01
                        @skey[PandoraCrypto::KV_Trust] = trust
                      end
                      #p log_mes+'ECC_Auth_Sign trust='+trust.inspect
                      if ($captcha_length>0) and $gtk_is_active \
                      and (trust.is_a? Integer) \
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
                            #p log_mes+'ECC_Auth_Sign  acipher='+acipher.inspect
                            #p log_mes+'ECC_Auth_Sign  @cipher='+@cipher.inspect
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
                #p 'ECC_Auth_Simple!'
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
                #p log_mes+'CAPTCHA!!!  ' #+params.inspect
                if not hunter?
                  err_scmd('Captcha for listener is denied')
                else
                  clue_length = rdata[0].ord
                  clue_text = rdata[1,clue_length]
                  captcha_buf = rdata[clue_length+1..-1]
                  if PandoraUI.captcha_win_available?
                    dstkey = nil
                    dstkey = @skey[PandoraCrypto::KV_Creator] if @skey
                    dstkey ||= params['dstkey']
                    dstkey ||= params['tokey']
                    dstperson = PandoraCrypto.get_userhash_by_keyhash(dstkey)
                    dstperson ||= dstkey
                    entered_captcha, dlg = PandoraGtk.show_captcha(captcha_buf, \
                      clue_text, conn_type, @node, @node_id, @recv_models, \
                      dstperson, self)
                    if dlg
                      @dialog ||= dlg
                      @dialog.set_session(self, true) if @dialog
                      if entered_captcha
                        @scmd = EC_Auth
                        @scode = ECC_Auth_Answer
                        @sbuf = entered_captcha
                        #p log_mes + 'CAPCHA ANSWER setted: '+entered_captcha.inspect
                      elsif entered_captcha.nil?
                        err_scmd('Cannot open captcha dialog')
                      else
                        err_scmd('Captcha enter canceled')
                        @conn_mode = (@conn_mode & (~PandoraNet::CM_Keep))
                      end
                    else
                      err_scmd('Cannot init captcha dialog')
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
          #p log_mes+'EC_Request  kind='+kind.to_s+'  stage='+@stage.to_s
          panhash = nil
          if (kind==PandoraModel::PK_Key) and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
            panhash = params['mykey']
            #p 'params[mykey]='+panhash
          end
          if (@stage==ES_Exchange) or (@stage==ES_Greeting) or panhash
            panhashes = nil
            if kind==0
              panhashes, len = PandoraUtils.pson_to_rubyobj(panhashes)
            else
              panhash = [kind].pack('C')+rdata if (not panhash) and rdata
              panhashes = [panhash]
            end
            #p log_mes+'panhashes='+panhashes.inspect
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
                #p log_mes+'SEND RECORD !!! [pson, values]='+[pson, values].inspect
              else
                #p log_mes+'NO RECORD panhash='+panhash.inspect
                @scmd = EC_Sync
                @scode = ECC_Sync1_NoRecord
                @sbuf = panhash
              end
            else
              rec_array = Array.new
              panhashes.each do |panhash|
                kind = PandoraUtils.kind_from_panhash(panhash)
                record = PandoraModel.get_record_by_panhash(kind, panhash, true, @recv_models)
                #p log_mes+'EC_Request panhashes='+PandoraUtils.bytes_to_hex(panhash).inspect
                rec_array << record if record
              end
              if rec_array.size>0
                records = PandoraUtils.rubyobj_to_pson(rec_array)
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
          #p log_mes+' EC_Record: [rcode, rdata.bytesize]='+[rcode, rdata.bytesize].inspect
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
                PandoraUI.log_message(PandoraUI::LM_Warning, _('Record came with wrong panhash'))
              else
                PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot write a record')+' 1')
              end
            else
              err_scmd('Record ('+kind.to_s+') came on wrong stage')
            end
          elsif (@stage==ES_Exchange)
            records, len = PandoraUtils.pson_to_rubyobj(rdata)
            #p log_mes+"!record2! recs="+records.inspect
            PandoraModel.save_records(records, @recv_models, support)
          else
            err_scmd('Records came on wrong stage')
          end
        when EC_Sync
          case rcode
            when ECC_Sync1_NoRecord
              #p log_mes+'EC_Sync: No record: panhash='+rdata.inspect
            when ECC_Sync2_Encode
              @r_encode = true
            when ECC_Sync3_Confirm
              confirms = rdata
              #p log_mes+'recv confirms='+confirms
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
                  #p log_mes+'update confirm  kind,id='+[kind, id].inspect
                  res = model.update({:state=>2}, nil, {:id=>id})
                  if res
                    talkview = nil
                    talkview = @dialog.dlg_talkview if @dialog
                    talkview.update_lines_with_id(id) if talkview
                  else
                    PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot update record of confirm')+' kind,id='+[kind,id].inspect)
                  end
                  i += 5
                end
              end
          end
        when EC_Wait
          case rcode
            when EC_Wait2_NoFarHook..EC_Wait5_NoNeighborRec
              PandoraUI.log_message(PandoraUI::LM_Error, _('Error at other side')+': '+ \
                _('cannot find a fish'))
            else
              PandoraUI.log_message(PandoraUI::LM_Error, _('Error at other side')+': '+ \
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
            PandoraUI.log_message(PandoraUI::LM_Error, _('Error at other side')+' ErrCode='+rcode.to_s+' "'+mes+'"')
          end
          err_scmd(nil, errcode, false)
          @conn_state = CS_Stoping
        else
          if @stage>=ES_Exchange
            case rcmd
              when EC_Message, EC_Channel
                #p log_mes+'EC_Message  dialog='+@dialog.inspect
                if (not @dialog) or @dialog.destroyed?
                  @conn_mode = (@conn_mode | PandoraNet::CM_Keep)
                  #panhashes = [@skey[PandoraCrypto::KV_Panhash], @skey[PandoraCrypto::KV_Creator]]
                  panhash = @skey[PandoraCrypto::KV_Creator]
                  @dialog = PandoraUI.show_cabinet(panhash, self, conn_type)
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
                    #p log_mes+'++++Recv EC_Message: values='+values.inspect
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
                    talkview = @dialog.dlg_talkview if @dialog
                    if talkview
                      myname = PandoraCrypto.short_name_of_person(pool.current_key)
                      sel = model.select({:panhash=>panhash}, false, 'id', 'id DESC', 1)
                      id = nil
                      id = sel[0][0] if sel and (sel.size > 0)
                      @dialog.add_mes_to_view(text, id, panstate, nil, @skey, \
                        myname, time_now, created)
                      @dialog.show_page(PandoraUI::CPI_Dialog)
                    else
                      PandoraUI.log_message(PandoraUI::LM_Error, 'Пришло сообщение, но лоток чата не найден!')
                    end

                    # This is a chat "!command"
                    if ((panstate & PandoraModel::PSF_Crypted)==0) and (text.is_a? String) \
                    and (text.size>1) and ((text[0]=='!') or (text[0]=='/'))
                      i = text.index(' ')
                      i ||= text.size
                      chat_com = text[1..i-1].downcase
                      chat_par = text[i+1..-1]
                      #p '===>Chat command: '+[chat_com, chat_par].inspect
                      chat_com_par = chat_com
                      chat_com_par += ' '+chat_par if chat_par
                      trust_level = $special_chatcom_trusts[chat_com]
                      trust_level ||= $trust_for_chatcom
                      if skey_trust >= trust_level
                        if chat_par and ($prev_chat_com_par != chat_com_par)
                          $prev_chat_com_par = chat_com_par
                          PandoraUI.log_message(PandoraUI::LM_Info, _('Run chat command')+\
                            ' ['+Utf8String.new(chat_com_par)+']')
                          case chat_com
                            when 'echo'
                              if dialog and (not dialog.destroyed?)
                                dialog.send_mes(chat_par)
                              else
                                add_send_segment(EC_Message, true, chat_par)
                              end
                            when 'menu'
                              PandoraUI.do_menu_act(chat_par)
                            when 'exec'
                              res = PandoraUtils.exec_cmd(chat_par)
                              if not res
                                PandoraUI.log_message(PandoraUI::LM_Warning, _('Command fails')+\
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
                              PandoraUI.log_message(PandoraUI::LM_Info, _('Unknown chat command')+': '+chat_com)
                          end
                        end
                      else
                        PandoraUI.log_message(PandoraUI::LM_Info, _('Chat command is denied')+ \
                          ' ['+Utf8String.new(chat_com_par)+'] '+_('trust')+'='+ \
                          PandoraModel.trust_to_str(skey_trust)+' '+_('need')+\
                          '='+trust_level.to_s)
                      end
                    end
                  end
                else #EC_Channel
                  case rcode
                    when ECC_Channel0_Open
                      #p 'ECC_Channel0_Open'
                    when ECC_Channel2_Close
                      #p 'ECC_Channel2_Close'
                  else
                    PandoraUI.log_message(PandoraUI::LM_Error, 'Неизвестный код управления каналом: '+rcode.to_s)
                  end
                end
              when EC_Media
                process_media_segment(rcode, rdata)
              when EC_Lure
                #p log_mes+'EC_Lure'
                send_segment_to_fish(rcode, rdata, true)
                #sleep 2
              when EC_Bite
                #p log_mes+'EC_Bite'
                send_segment_to_fish(rcode, rdata)
                #sleep 2
              when EC_Query
                case rcode
                  when ECC_Query_Rel
                    #p log_mes+'===ECC_Query_Rel'
                    from_time = rdata[0, 4].unpack('N')[0]
                    pankinds = rdata[4..-1]
                    trust = skey_trust
                    #p log_mes+'from_time, pankinds, trust='+[from_time, pankinds, trust].inspect
                    pankinds = PandoraCrypto.allowed_kinds(trust, pankinds)
                    #p log_mes+'pankinds='+pankinds.inspect

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

                    #p log_mes+'ph_list='+ph_list.inspect
                    ph_list = PandoraUtils.rubyobj_to_pson(ph_list) if ph_list
                    @scmd = EC_News
                    @scode = ECC_News_Panhash
                    @sbuf = ph_list
                  when ECC_Query_Record  #EC_Request
                    #p log_mes+'==ECC_Query_Record'
                    two_list, len = PandoraUtils.pson_to_rubyobj(rdata)
                    need_ph_list, foll_list = two_list
                    #p log_mes+'need_ph_list, foll_list='+[need_ph_list, foll_list].inspect
                    created_list = []
                    if (foll_list.is_a? Array) and (foll_list.size>0)
                      from_time = Time.now.to_i - 7*24*3600
                      kinds = (1..255).to_a - [PandoraModel::PK_Message]
                      #p 'kinds='+kinds.inspect
                      foll_list.each do |panhash|
                        if panhash[0].ord==PandoraModel::PK_Person
                          cr_l = PandoraModel.created_records(panhash, from_time, kinds, @send_models)
                          #p 'cr_l='+cr_l.inspect
                          created_list = created_list + cr_l if cr_l
                        end
                      end
                      created_list.flatten!
                      created_list.uniq!
                      created_list.compact!
                      created_list.sort! {|a,b| a[0]<=>b[0] }
                      #p log_mes+'created_list='+created_list.inspect
                    end
                    pson_records = []
                    if (need_ph_list.is_a? Array) and (need_ph_list.size>0)
                      #p log_mes+'need_ph_list='+need_ph_list.inspect
                      need_ph_list.each do |panhash|
                        kind = PandoraUtils.kind_from_panhash(panhash)
                        #p log_mes+[panhash, kind].inspect
                        #p res = PandoraModel.get_record_by_panhash(kind, panhash, true, \
                        #  @send_models)
                        pson_records << res if res
                      end
                      #p log_mes+'pson_records='+pson_records.inspect
                    end
                    @scmd = EC_News
                    @scode = ECC_News_Record
                    @sbuf = PandoraUtils.rubyobj_to_pson([pson_records, created_list])
                  when ECC_Query_Fragment
                    # запрос фрагмента для корзины
                    #p log_mes+'==ECC_Query_Fragment'
                    sha1_frag, len = PandoraUtils.pson_to_rubyobj(rdata)
                    sha1, frag_ind = sha1_frag
                    #p log_mes+'[sha1, frag_ind]='+[sha1, frag_ind].inspect
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
                    #p log_mes+'==ECC_News_Panhash'
                    ph_list, len = PandoraUtils.pson_to_rubyobj(rdata)
                    #p log_mes+'ph_list, len='+[ph_list, len].inspect
                    # Check non-existing records
                    need_ph_list = PandoraModel.needed_records(ph_list, @send_models)
                    #p log_mes+'need_ph_list='+ need_ph_list.inspect

                    two_list = [need_ph_list]

                    questioner = pool.person #me
                    answerer = @skey[PandoraCrypto::KV_Creator]
                    #p '[questioner, answerer]='+[questioner, answerer].inspect
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
                    #p log_mes+'==ECC_News_Record'
                    two_list, len = PandoraUtils.pson_to_rubyobj(rdata)
                    pson_records, created_list = two_list
                    #p log_mes+'pson_records, created_list='+[pson_records, created_list].inspect
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
                    if (len>0) and line.is_a?(Array) and (line.size==6)
                      # данные корректны
                      fisher, fisher_key, fisher_baseid, fish, fish_key, fish_baseid = line
                      #p log_mes+'--ECC_News_Hook line='+line.inspect
                      if fish and (fish == pool.person) or \
                      fish_key and (fish_key == pool.key_hash) or
                      fish_baseid and (fish_baseid == pool.base_id)
                        #p '!!это узел-рыбка, найти/создать сессию рыбака'
                        sessions = pool.sessions_of_personkeybase(fisher, fisher_key, fisher_baseid)
                        #pool.init_session(node, tokey, nil, nil, node_id)
                        #Tsaheylu
                        if (sessions.is_a? Array) and (sessions.size>0)
                          #p 'Найдены сущ. сессии'
                          sessions.each do |session|
                            #p 'Подсоединяюсь к сессии: session.id='+session.object_id.to_s
                            sess_hook, rec = reg_line(line, session)
                            if not self.connect_session_to_hook([session], hook, true)
                              #p 'Не могу прицепить сессию'
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
                        #p '!!это узел-рыбак, найти/создать сессию рыбки'
                        sessions = pool.sessions_of_personkeybase(fish, fish_key, fish_baseid)
                        #p 'sessions1 size='+sessions.size.to_s
                        if (not (sessions.is_a? Array)) or (sessions.size==0)
                          sessions = pool.sessions_of_personkeybase(fish, fish_key, nil)
                          #p 'sessions2 size='+sessions.size.to_s
                        end
                        if not self.connect_session_to_hook(sessions, hook, true, line)
                          #(line, session, far_hook, hook, sess_hook)
                          sess_hook, rec = reg_line(line, nil, hook)
                          session = Session.new(self, sess_hook, nil, nil, nil, \
                            CM_Hunter, nil, nil, nil, nil, fish, fish_key, fish_baseid)
                        end
                      else
                        #p '!!это узел-посредник, пробросить по истории заявок'
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
                    #p log_mes+'==ECC_News_Notice [rdata, notic, len]='+[rdata, nick, len].inspect
                    if (notic.is_a? Array) and (notic.size==5)
                      #pool.add_notice_order(self, *notic)
                      #pool.add_mass_record(MK_Presence, nick, nil, nil, \
                      #  nil, nil, nil, nil, \
                      #  nil, @to_node, nil, @recv_models)
                    end
                  when ECC_News_SessMode
                    #p log_mes + 'ECC_News_SessMode'
                    @conn_mode2 = rdata[0].ord if rdata.bytesize>0
                  when ECC_News_Answer
                    #p log_mes + '==ECC_News_Answer'
                    req_answer, len = PandoraUtils.pson_to_rubyobj(rdata)
                    req,answ = req_answer
                    #p log_mes+'req,answ='+[req,answ].inspect
                    request,kind,base_id = req
                    if kind==PandoraModel::PK_BlobBody
                      PandoraUI.log_message(PandoraUI::LM_Trace, _('Answer: blob is found'))
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
                          #p log_mes+'--[frag_ind]='+[frag_ind].inspect
                          if frag_ind
                            @scmd = EC_Query
                            @scode = ECC_Query_Fragment
                            @sbuf = PandoraUtils.rubyobj_to_pson([sha1, frag_ind])
                          else
                            pool.close_punnet(punnet, sha1, @send_models)
                          end
                        else
                          #p log_mes+'--File is already complete: '+fn.inspect
                          pool.close_punnet(punnet, sha1, @send_models)
                        end
                      end
                    else
                      PandoraUI.log_message(PandoraUI::LM_Trace, _('Answer: rec is found'))
                      reqs = find_search_request(req[0], req[1])
                      reqs.each do |sr|
                        sr[SA_Answer] = answ
                      end
                    end
                  when ECC_News_BigBlob
                    # есть запись, но она слишком большая
                    #p log_mes+'==ECC_News_BigBlob'
                    toobig, len = PandoraUtils.pson_to_rubyobj(rdata)
                    toobig.each do |rec|
                      panhash,sha1,size,fill = rec
                      #p 'panhash,sha1,size,fill='+[panhash,sha1,size,fill].inspect
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
                    #p log_mes+'ECC_News_Punnet'
                    punnets, len = PandoraUtils.pson_to_rubyobj(rdata)
                    punnets.each do |rec|
                      panhash,size,sha1,blocksize,punnet = rec
                      #p 'panhash,size,sha1,blocksize,fragments='+[panhash,size,sha1,blocksize,fragments].inspect
                    end
                  when ECC_News_Fragments
                    # есть новые фрагменты
                    #p log_mes+'ECC_News_Fragments'
                    frags, len = PandoraUtils.pson_to_rubyobj(rdata)
                    frags.each do |rec|
                      panhash,size,sha1,blocksize,punnet = rec
                      #p 'panhash,size,sha1,blocksize,fragments='+[panhash,size,sha1,blocksize,fragments].inspect
                    end
                  else
                    #p "news more!!!!"
                    pkind = rcode
                    pnoticecount = rdata.unpack('N')
                    @scmd = EC_Sync
                    @scode = 0
                    @sbuf = ''
                end
              when EC_Fragment
                #p log_mes+'====EC_Fragment'
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
                #p log_mes+'====EC_Mass [kind, params, len]='+[kind, params, len].inspect
                if (params.is_a? Array) and (params.size>=6)
                  src_node, src_ind, atime, atrust, adepth, param1, \
                    param2, param3 = params
                  src_key = nil
                  scr_baseid = nil
                  scr_person = nil
                  nl = pool.get_node_params(src_node)
                  if nl
                    src_key = nl[NL_Key]
                    scr_baseid = nl[NL_BaseId]
                    scr_person = nl[NL_Person]
                  end
                  if not pool.find_mass_record_by_params(src_node, kind, param1, param2, param3)
                  #if not pool.find_mass_record_by_index(src_node, src_ind)
                    keep_node = @to_node
                    resend = true
                    case kind
                      when MK_Presence
                      when MK_Chat
                        destination  = AsciiString.new(params[MRC_Dest])
                        row, len = PandoraUtils.pson_to_rubyobj(params[MRC_MesRow])
                        #p '---MRC_Dest, MRC_MesRow, params[MRC_MesRow], row='+[MRC_Dest, \
                        #  MRC_MesRow, params[MRC_MesRow], row].inspect
                        creator  = row[MCM_Creator]
                        created  = row[MCM_Created]
                        text     = row[MCM_Text]
                        panstate = row[MCM_PanState]
                        panstate ||= 0
                        panstate = (panstate & (PandoraModel::PSF_Crypted | \
                          PandoraModel::PSF_Verified))
                        panstate = (panstate | PandoraModel::PSF_ChatMes)
                        time_now = Time.now.to_i
                        values = {:destination=>destination, :text=>text, :state=>2, \
                          :creator=>creator, :created=>created, :modified=>time_now, \
                          :panstate=>panstate}
                        #p log_mes+'++++Recv MK_Chat: values='+values.inspect
                        model = PandoraUtils.get_model('Message', @recv_models)
                        panhash = model.calc_panhash(values)
                        values['panhash'] = panhash
                        chat_dialog = PandoraUI.show_cabinet(destination, nil, \
                          nil, nil, nil, PandoraUI::CPI_Chat)
                          #@conn_type, nil, nil, CPI_Chat)
                        res = model.update(values, nil, nil)
                        Thread.pass
                        sleep(0.05)
                        Thread.pass
                        talkview = nil
                        talkview = chat_dialog.chat_talkview if chat_dialog
                        if talkview
                          myname = PandoraCrypto.short_name_of_person(pool.current_key)
                          sel = model.select({:panhash=>panhash}, false, 'id', 'id DESC', 1)
                          id = nil
                          id = sel[0][0] if sel and (sel.size > 0)
                          chat_dialog.add_mes_to_view(text, id, panstate, nil, @skey, \
                            myname, time_now, created)
                        else
                          PandoraUI.log_message(PandoraUI::LM_Error, 'Пришло чат-сообщение, но лоток чата не найден!')
                        end
                      when MK_Search
                        # пришёл поисковый запрос (ECC_Query_Search)
                        #MRS_Kind       = MR_Param1    #1
                        #MRS_Request    = MR_Param2    #~140    #sum: 33+(~141)=  ~174
                        #MRA_Answer     = MR_Param3    #~22
                        scr_baseid ||= @to_base_id
                        resend = ((scr_baseid.nil?) or (scr_baseid != pool.base_id))
                        #  p log_mes+'ADD search req to pool list'
                        #  pool.add_mass_record(MK_Search, params[MRS_Kind], \
                        #    params[MRS_Request], params[MRA_Answer], nil, nil, nil, \
                        #    nil, nil, @to_node, nil, @recv_models)
                        #end
                      when MK_Fishing
                        # пришла заявка на рыбалку (ECC_Query_Fish)
                        #params[MRF_Fish]            = MR_Param1   #22
                        #params[MRF_Fish_key]        = MR_Param2   #22    #sum: 33+44=  77
                        #params[MRL_Fish_Baseid]     = MR_Param3   #16
                        if nl
                          fisher = scr_person
                          fisher_key = src_key
                          fisher_baseid = scr_baseid
                          fish = params[MRF_Fish]
                          fish_key = params[MRF_Fish_key]
                          resend = (init_line([fisher, fisher_key, fisher_baseid, \
                            fish, fish_key], pool.key_hash) == false)
                        end
                      when MK_Cascade
                      when MK_CiferBox
                    end
                    if resend
                      pool.add_mass_record(kind, param1, param2, param3, src_node, \
                        src_ind, atime, atrust, adepth, keep_node, nil, @recv_models)
                    end
                  end
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
    # Max count of mass send
    # RU: Максимальное число массовых рассылок
    $max_mass_count = 200
    # Number of mass send per cicle
    # RU: Число массовых рассылок за цикл
    $mass_per_cicle = 2
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
      @mr_ind     = 0
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

      #p 'Session.new( [asocket, ahost_name, ahost_ip, aport, aproto, '+\
      #  'aconn_mode, anode_id, a_dialog, send_state_add, nodehash, to_person, '+\
      #  'to_key, to_base_id]'+[asocket.object_id, ahost_name, ahost_ip, aport, aproto, \
      #  aconn_mode, anode_id, a_dialog, send_state_add, nodehash, to_person, \
      #  to_key, to_base_id].inspect

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
          #p 'донор-сессия: '+sess.object_id.inspect
          if sess_hook
            #(line, session, far_hook, hook, sess_hook)
            fhook, rec = reg_line(nil, sess, nil, nil, sess_hook)
            sess_hook2, rec2 = sess.reg_line(nil, self, nil, sess_hook, fhook)
            if sess_hook2
              #add_hook(asocket, ahost_name)
              if hunter?
                #p 'крючок рыбака '+sess_hook.inspect
                PandoraUI.log_message(PandoraUI::LM_Info, _('Active fisher')+': [sess, hook]='+\
                  [sess.object_id, sess_hook].inspect)
              else
                #p 'крючок рыбки '+sess_hook.inspect
                PandoraUI.log_message(PandoraUI::LM_Info, _('Passive fisher')+': [sess, hook]='+\
                  [sess.object_id, sess_hook].inspect)
              end
            else
              #p 'Не удалось зарегать рыб.сессию'
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
            #p 'нет подключения ни через сокет, ни через донора'
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
                    PandoraUI.log_message(PandoraUI::LM_Warning, _('Fail connect to')+': '+server)
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
                  PandoraUI.log_message(PandoraUI::LM_Trace, _('Timeout connect to')+': '+server)
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
                fish_trust = 0
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
                PandoraUI.log_message(PandoraUI::LM_Trace, \
                  _('Session breaks bz of no person and key panhashes'))
              end
            end

          end

          work_time = Time.now

          #p '==reconn: '+[@socket.object_id].inspect
          sleep 0.5


          if @socket
            if not hunter?
              PandoraUI.log_message(PandoraUI::LM_Info, _('Hunter connects')+': '+socket.peeraddr.inspect)
            else
              PandoraUI.log_message(PandoraUI::LM_Info, _('Connected to listener')+': '+server)
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

            #p 'есть подключение [@socket, ahook, @conn_mode]' + [@socket.object_id, ahook, @conn_mode].inspect
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

                #p log_mes+"Цикл ЧТЕНИЯ сокета. начало"
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
                          PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot add error segment to send queue'))
                        end
                      end
                      @conn_state = CS_Stoping
                    elsif (readmode == RM_Comm)
                      #p log_mes+'-- from socket to read queue: [rkcmd, rcode, rkdata.size]='+[rkcmd, rkcode, rkdata.size].inspect
                      if @r_encode and rkdata and (rkdata.bytesize>0)
                        #@rkdata = PandoraCrypto.recrypt(@rkey, @rkdata, false, true)
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
                            PandoraUI.log_message(PandoraUI::LM_Error, _('No cipher for decrypt data'))
                            @conn_state = CS_Stoping
                          end
                        end
                        rkdata_size = 0
                        rkdata_size = rkdata.bytesize if rkdata
                        #p log_mes+'<<-RECV [rkcmd/rkcode, rkdata.size] stage='+[rkcmd, rkcode, rkdata_size].inspect+' '+@stage.to_s
                        res = @read_queue.add_block_to_queue([rkcmd, rkcode, rkdata])
                        if not res
                          PandoraUI.log_message(PandoraUI::LM_Error, _('Cannot add socket segment to read queue'))
                          @conn_state = CS_Stoping
                        end
                      end
                      rkdata = AsciiString.new
                    end

                    if not ok1comm
                      PandoraUI.log_message(PandoraUI::LM_Error, _('Bad first command'))
                      @conn_state = CS_Stoping
                    end
                  end
                  if (@conn_state == CS_Stoping)
                    @conn_state = CS_StopRead
                  end
                  #Thread.pass
                end
                @conn_state = CS_StopRead if (not @conn_state) or (@conn_state < CS_StopRead)
                #p log_mes+"Цикл ЧТЕНИЯ сокета конец!"
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

              #p log_mes+"Цикл ЧТЕНИЯ начало"
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
                      PandoraUI.log_message(PandoraUI::LM_Error, 'Error while adding segment to queue')
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
              #p log_mes+"Цикл ЧТЕНИЯ конец!"
              #socket.close if not socket.closed?
              #@conn_state = CS_Disconnected
              @read_thread = nil
            end

            # Send cicle
            # RU: Цикл отправки
            questioner_step = QS_ResetMessage
            message_model = PandoraUtils.get_model('Message', @send_models)
            #p log_mes+'ЦИКЛ ОТПРАВКИ начало: @conn_state='+@conn_state.inspect

            while (@conn_state < CS_Disconnected)
              #p '@conn_state='+@conn_state.inspect

              # формирование подтверждений
              if (@conn_state < CS_Disconnected)
                ssbuf = ''
                confirm_rec = @confirm_queue.get_block_from_queue
                while (@conn_state < CS_Disconnected) and confirm_rec
                  #p log_mes+'send  confirm_rec='+confirm_rec
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
                    #ssbuf = PandoraCrypto.recrypt(@skey, ssbuf, true, false)
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
                      #p log_mes+'err send comm and buf'
                    end
                  else
                    #p 'SILENT!!!!!!!!'
                  end
                  if (sscmd==EC_Sync) and (sscode==ECC_Sync2_Encode)
                    @s_encode = true
                  end
                  if (sscmd==EC_Bye)
                    #p log_mes+'SEND BYE!!!!!!!!!!!!!!!'
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
                        filter = ['destination=? AND state=1 AND '+ \
                          'IFNULL(panstate,0)&'+PandoraModel::PSF_ChatMes.to_s+'=0', \
                          receiver]
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
                      #p log_mes+'Whyer: CreatorCheck  creator='+creator.inspect
                      if not res
                        #p log_mes+'Whyer: CreatorCheck  Request!'
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
                  filter = {'destination'=>receiver, 'state'=>0, \
                    'IFNULL(panstate,0)&'+PandoraModel::PSF_ChatMes.to_s=>0}
                  fields = 'id, creator, created, text, panstate'
                  sel = message_model.select(filter, false, fields, 'created', \
                    $mes_block_count)
                  if sel and (sel.size>0)
                    @send_state = (send_state | CSF_Messaging)
                    i = 0
                    talkview = nil
                    talkview = @dialog.dlg_talkview if @dialog
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
                          PandoraUI.log_message(PandoraUI::LM_Error, _('Updating state of sent message')+' id='+id.to_s)
                        end
                      else
                        PandoraUI.log_message(PandoraUI::LM_Error, _('Adding message to send queue')+' id='+id.to_s)
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
                      #p log_mes+' err send media'
                    end
                  else
                    cannel += 1
                  end
                end
              end

              # рассылка массовых записей
              if (@sess_mode.is_a? Integer) and ((@sess_mode & CM_MassExch)>0) \
              and @to_key and @to_person and @to_base_id and @sess_trust \
              and (questioner_step>QS_ResetMessage)
                processed = 0
                if @mr_ind+$max_mass_count < pool.mass_records.size
                  @mr_ind = pool.mass_records.size - $max_mass_count
                end
                while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
                and (@mr_ind < pool.mass_records.size) \
                and (processed<$mass_per_cicle)
                #and ((send_state & (CSF_Message | CSF_Messaging)) == 0) \
                  mass_rec = pool.mass_records[@mr_ind]
                  #p log_mes+'->>>MASSREC [@mr_ind, pool.mass_records.size, @sess_trust, mass_rec[MR_Trust], mass_rec, @to_node]=' \
                  #  +[@mr_ind, pool.mass_records.size, @sess_trust, PandoraModel.transform_trust(mass_rec[MR_Trust]), mass_rec, @to_node].inspect
                  if (mass_rec and mass_rec[MR_Node] \
                  and (@sess_trust >= PandoraModel.transform_trust(mass_rec[MR_Trust], \
                  :auto_to_float)) and (mass_rec[MR_Node] != @to_node) and (mass_rec[MR_Depth]>0))
                  #and (mass_rec[MR_Node] != pool.self_node) \
                    kind = mass_rec[MR_Kind]
                    params = mass_rec[MR_Node..MR_Param3]
                    case kind
                      when MK_Fishing
                        #line = fish_order[MR_Fisher..MR_Fish_key]
                        #if init_line(line) == false
                        #  p log_mes+'Fish order to send: '+line.inspect
                        #  PandoraUI.log_message(PandoraUI::LM_Trace, _('Send bob')+': [fish,fishkey]->[host,port]' \
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
                      #p log_mes+'-->>>> MR SEND [kind, params]'+[kind, params].inspect
                      params_pson = PandoraUtils.rubyobj_to_pson(params)
                      add_send_segment(EC_Mass, true, params_pson, kind)
                    end
                    processed += 1
                  end
                  @mr_ind += 1
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
                #p '***!!pool.get_next_frag='+next_frag.inspect
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
                  PandoraUI.log_message(PandoraUI::LM_Trace, _('Idle timeout')+': '+@host_ip.inspect)
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

            #p log_mes+"Цикл ОТПРАВКИ конец!!!   @conn_state="+@conn_state.inspect

            #Thread.critical = true
            #Thread.critical = false
            #p log_mes+'check close'
            if socket and (not socket.closed?)
              #p log_mes+'before close_write'
              #socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
              #socket.flush
              #socket.print('\000')
              socket.close_write
              #p log_mes+'before close'
              sleep(0.05)
              socket.close
              #p log_mes+'closed!'
            end
            if socket.is_a? IPSocket
              if not hunter?
                PandoraUI.log_message(PandoraUI::LM_Info, _('Hunter disconnects')+': '+@host_ip.inspect)
              else
                PandoraUI.log_message(PandoraUI::LM_Info, _('Disconnected from listener')+': '+@host_ip.inspect)
              end
            end
            @socket_thread.exit if @socket_thread
            @read_thread.exit if @read_thread
            while (@hooks.size>0)
              #p 'DONORs free!!!!'
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
            #p 'НЕТ ПОДКЛЮЧЕНИЯ'
          end
          @conn_state = CS_Disconnected if @conn_state < CS_Disconnected

          need_connect = (((@conn_mode & CM_Keep) != 0) \
          and (not (@socket.is_a? FalseClass)) and @conn_state < CS_CloseSession) \

          #p 'NEED??? [need_connect, @conn_mode, @socket]='+[need_connect, \
          #  @conn_mode, @socket].inspect

          if need_connect and (not @socket) and work_time \
          and ((Time.now.to_i - work_time.to_i)<15)
            #p 'sleep!'
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

  # Get mass records parameters
  # RU: Взять параметры массовых сообщений
  def self.get_mass_params
    $mass_exchange      = PandoraUtils.get_param('mass_exchange')
    $mass_trust         = PandoraUtils.get_param('mass_trust')
    $mass_depth         = PandoraUtils.get_param('mass_depth')
    $max_mass_depth     = PandoraUtils.get_param('max_mass_depth')
    $mass_trust       ||= 12
    $mass_depth       ||= 2
    $max_mass_depth   ||= 5
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
    $trust_for_unknown   = PandoraUtils.get_param('trust_for_unknown')
    $max_opened_keys     = PandoraUtils.get_param('max_opened_keys')
    $max_session_count   = PandoraUtils.get_param('max_session_count')
    $hunt_step_pause     = PandoraUtils.get_param('hunt_step_pause')
    $hunt_overflow_pause = PandoraUtils.get_param('hunt_overflow_pause')
    $hunt_period         = PandoraUtils.get_param('hunt_period')
    $exchange_timeout    = PandoraUtils.get_param('exchange_timeout')
    $dialog_timeout      = PandoraUtils.get_param('dialog_timeout')
    $captcha_timeout     = PandoraUtils.get_param('captcha_timeout')
    $low_conn_trust     ||= 0.0
    get_mass_params
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
      if $pool.is_black?(host_ip)
        PandoraUI.log_message(PandoraUI::LM_Info, _('IP is banned')+': '+host_ip.to_s)
      else
        host_name = socket.peeraddr[3]
        port = socket.peeraddr[1]
        proto = 'tcp'
        #p 'LISTENER: '+[host_name, host_ip, port, proto].inspect
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
      user = PandoraCrypto.current_user_or_key(true)
      if user
        PandoraUI.set_status_field(PandoraUI::SF_Listen, nil, nil, true)
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
                    PandoraUI.log_message(PandoraUI::LM_Info, _('Listening')+' '+addr_str)
                  end
                rescue => err
                  str = 'TCP ['+host.to_s+']:'+tcp_port.to_s
                  PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot open')+' '+str+' ' \
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
                PandoraUI.log_message(PandoraUI::LM_Info, _('Listener stops')+' '+addr_strs[i])
              end
            end
            PandoraUI.set_status_field(PandoraUI::SF_Listen, nil, nil, false)
            $tcp_listen_thread = nil
            PandoraUI.correct_lis_btn_state
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
              PandoraUI.log_message(PandoraUI::LM_Info, _('Listening')+' '+udp_addr_str)
            rescue => err
              udp_server = nil
              if host != '::'
                str = 'UDP ['+host.to_s+']:'+tcp_port.to_s+' '+Utf8String.new(err.message)
                PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot open')+' '+str)
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
                        PandoraUI.log_message(PandoraUI::LM_Trace, \
                          'UDP '+_('broadcast to ports')+' '+rcv_udp_port.to_s)
                      rescue => err
                        PandoraUI.log_message(PandoraUI::LM_Trace, \
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
              #p 'Received UDP-pack ['+data.inspect+'] addr='+addr.inspect
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
                      addr = $pool.encode_addr(far_ip, far_port, 'tcp')
                      $pool.init_session(addr, nil, 0, nil, nil, far_person_hash, \
                        far_key_hash, far_base_id)
                    end
                  end
                end
              end
            end
            #udp_server.close if udp_server and (not udp_server.closed?)
            PandoraUI.log_message(PandoraUI::LM_Info, _('Listener stops')+' '+udp_addr_str) if udp_server
            #PandoraUI.set_status_field(PandoraUI::SF_Listen, 'Not listen', nil, false)
            $udp_listen_thread = nil
            PandoraUI.correct_lis_btn_state
          end
        end

        #p loc_hst = Socket.gethostname
        #p Socket.gethostbyname(loc_hst)[3]
      end
      PandoraUI.correct_lis_btn_state
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
              PandoraUI.correct_lis_btn_state
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
              PandoraUI.correct_lis_btn_state
            end
            false
          end
        end
      end
      PandoraUI.correct_lis_btn_state
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

    if $pool.current_key and $node_registering_thread.nil?
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
          PandoraUI.log_message(PandoraUI::LM_Warning, _('Global IP')+'v4: '+addr_info.ip_address)
        end
      end
      if ($last_ip6_show.nil? and ip6) or ip6n
        $last_ip6_show = ip6
        ip6_list.each do |addr_info|
          PandoraUI.log_message(PandoraUI::LM_Warning, _('Global IP')+'v6: '+addr_info.ip_address)
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
            node = PandoraUtils.bytes_to_hex($pool.self_node)
            #node = Base64.strict_encode64($pool.self_node)
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

  $hunter_thread = nil

  # Is hunting?
  # RU: Идёт охота?
  def self.hunting?
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
            #p '$hunter_thread[:paused]='+$hunter_thread[:paused].inspect
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
      PandoraUI.correct_hunt_btn_state
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
            PandoraUI.correct_hunt_btn_state
            sleep(delay) if delay>0
            while (Thread.current[:active] != false) and sel and (sel.size>0)
              start_time = Time.now.to_i
              sel.each do |row|
                node_id = row[0]
                addr   = row[1]
                domain = row[2]
                key_hash = row[3]
                if (addr and (addr.size>0)) or (domain and (domain.size>0)) \
                or ($pool.active_socket? and key_hash and (key_hash.size>0))
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
                  addr = $pool.encode_addr(domain, tport, 'tcp')
                  if Thread.current[:active]
                    $pool.init_session(addr, panhash, 0, nil, node_id, person, \
                      key_hash, base_id)
                    if Thread.current[:active]
                      if $pool.sessions.size<$max_session_count
                        sleep($hunt_step_pause)
                      else
                        while Thread.current[:active] \
                        and ($pool.sessions.size>=$max_session_count)
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
            PandoraUI.correct_hunt_btn_state
          end
        else
          PandoraUI.correct_hunt_btn_state
          PandoraUI.show_dialog(_('Enter at least one node')) do
            PandoraUI.show_panobject_list(PandoraModel::Node, nil, nil, true)
          end
        end
      else
        PandoraUI.correct_hunt_btn_state
      end
    end
    if (not $resume_harvest_time) \
    or (Time.now.to_i >= $resume_harvest_time + $resume_harvest_period*60)
      GLib::Timeout.add(900) do
        if hunting?
          $resume_harvest_time = Time.now.to_i
          $pool.resume_harvest
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
      PandoraUI.log_message(PandoraUI::LM_Trace, _('Proxy is used')+' '+proxy.inspect)
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
      PandoraUI.log_message(PandoraUI::LM_Warning, _('URI parse fails')+' ['+url+'] '+\
        Utf8String.new(err.message))
    end
    [host, path, port, scheme]
  end

  HTTP_TIMEOUT  = 10        #10 sec

  def self.http_connect(url, aopen_timeout=nil, aread_timeout=nil, show_log=true, \
  need_start=true)
    http = nil
    host, path, port, scheme = parse_url(url)
    port_str = ''
    port_str = ':'+port.to_s if port
    if show_log
      PandoraUI.log_message(PandoraUI::LM_Info, _('Connect to')+': '+\
        host+path+port_str+'..')
    end
    aopen_timeout ||= HTTP_TIMEOUT
    begin
      proxy = PandoraNet.detect_proxy
      http = Net::HTTP.new(host, port, *proxy)
      if http
        http.open_timeout = aopen_timeout
        http.read_timeout = aread_timeout if aread_timeout
        if scheme == 'https'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        #http.start if need_start
      end
    rescue => err
      http = nil
      PandoraUI.log_message(PandoraUI::LM_Trace, _('Connection error')+\
        ' '+[host, port].inspect+' '+Utf8String.new(err.message))
      #puts Utf8String.new(err.message)
    end
    [http, host, path]
  end

  def self.http_reconnect_if_need(http, time, url, aopen_timeout=nil, aread_timeout=nil)
    aopen_timeout ||= HTTP_TIMEOUT
    if (not http.active?) or (Time.now.to_i >= (time + aopen_timeout))
      host, path, port, scheme = parse_url(url)
      begin
        proxy = PandoraNet.detect_proxy
        http = Net::HTTP.new(host, port, *proxy)
        if scheme == 'https'
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        http.open_timeout = aopen_timeout
        http.read_timeout = aread_timeout if aread_timeout
      rescue => err
        http = nil
        PandoraUI.log_message(PandoraUI::LM_Trace, _('Connection error')+\
          [host, port].inspect+' '+Utf8String.new(err.message))
        #puts Utf8String.new(err.message)
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
      #puts Utf8String.new(err.message)
    end
    res
  end

  # Http get body
  # RU: Взять тело по Http
  def self.http_get_body_from_path(http, path, host='', show_log=true)
    body = nil
    if http and path
      if show_log
        PandoraUI.log_message(PandoraUI::LM_Trace, _('Download from') + ': ' + \
          host + path + '..')
      end
      begin
        response = http.request_get(path)
        body = response.body if response.is_a?(Net::HTTPSuccess)
      rescue => err
        PandoraUI.log_message(PandoraUI::LM_Info, _('Http download fails')+': '+\
          Utf8String.new(err.message))
      end
    end
    body
  end

  def self.http_get_request(url, show_log=nil, aopen_timeout=nil, aread_timeout=nil)
    body = nil
    if url.is_a?(String) and (url.size>0)
      if show_log
        PandoraUI.log_message(PandoraUI::LM_Trace, _('Download from') + ': ' + url + '..')
      end
      begin
        uri = URI.parse(url)
        body = Net::HTTP.get(uri)
        #http, host, path = PandoraNet.http_connect(url, aopen_timeout, \
        #  aread_timeout, show_log, false)
        ##p '===http, host, path, http.started?='+[http, host, path, http.started?].inspect
        #if http
        #  #http.start do
        #  body = PandoraNet.http_get_body_from_path(http, path, host, show_log)
        #  #end
        #  #http.finish if http and http.started?
        #end
        ##p '---body='+body.inspect
      rescue => err
        PandoraUI.log_message(PandoraUI::LM_Info, _('Http download fails')+': '+Utf8String.new(err.message))
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
          self_node = $pool.self_node
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
                    #p '+++Add [panhash, IP]='+[panhash, ip].inspect
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
      aopen_timeout=7
      aread_timeout=7
      if delete
        aopen_timeout=4
        aread_timeout=2
      end
      body = http_get_request(url, false, aopen_timeout, aread_timeout)
      if mes and body
        if body.size==0
          err = ' '+_('Loading error')
        elsif body[0]=='!'
          if delete or (body.size==1)
            #puts body
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
        PandoraUI.log_message(PandoraUI::LM_Info, _(mes)+suffix)
      else
        err ||= ''
        PandoraUI.log_message(PandoraUI::LM_Info, _('Registrator fails')+suffix+err)
      end
    end
    res
  end

end


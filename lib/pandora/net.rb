require_relative 'net/pool'
require_relative 'net/session'

# ====================================================================
# Network classes of Pandora
# RU: Сетевые классы Пандоры
module Pandora
  module Net
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
    ECC_News_Fish         = 2

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

    # Read modes of socket
    # RU: Режимы чтения из сокета
    RM_Comm      = 0   # Базовая команда
    RM_CommExt   = 1   # Расширение команды для нескольких сегментов
    RM_SegLenN   = 2   # Длина второго (и следующих) сегмента в серии
    RM_SegmentS  = 3   # Чтение одиночного сегмента
    RM_Segment1  = 4   # Чтение первого сегмента среди нескольких
    RM_SegmentN  = 5   # Чтение второго (и следующих) сегмента в серии

    # Connection mode
    # RU: Режим соединения
    CM_Hunter       = 1
    CM_KeepHere     = 2
    CM_KeepThere    = 4

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

    # Inquirer steps
    # RU: Шаги почемучки
    IS_ResetMessage  = 0
    IS_CreatorCheck  = 1
    IS_NewsQuery     = 2
    IS_Finished      = 255

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

    # Get exchange params
    # RU: Взять параметры обмена
    def self.get_exchange_params
      $callback_addr       = Pandora::Utils.get_param('callback_addr')
      $puzzle_bit_length   = Pandora::Utils.get_param('puzzle_bit_length')
      $puzzle_sec_delay    = Pandora::Utils.get_param('puzzle_sec_delay')
      $captcha_length      = Pandora::Utils.get_param('captcha_length')
      $captcha_attempts    = Pandora::Utils.get_param('captcha_attempts')
      $trust_for_captchaed = Pandora::Utils.get_param('trust_for_captchaed')
      $trust_for_listener  = Pandora::Utils.get_param('trust_for_listener')
      $low_conn_trust      = Pandora::Utils.get_param('low_conn_trust')
      $low_conn_trust ||= 0.0
    end

    $listen_thread = nil

    # Open server socket and begin listen
    # RU: Открывает серверный сокет и начинает слушать
    def self.start_or_stop_listen
      PandoraNet.get_exchange_params
      if $listen_thread
        server = $listen_thread[:listen_server_socket]
        $listen_thread[:need_to_listen] = false
        #server.close if not server.closed?
        #$listen_thread.join(2) if $listen_thread
        #$listen_thread.exit if $listen_thread
        $window.correct_lis_btn_state
      else
        user = PandoraCrypto.current_user_or_key(true)
        if user
          $window.set_status_field(PandoraGtk::SF_Listen, 'Listening', nil, true)
          Pandora.config.host = Pandora::Utils.get_param('listen_host')
          Pandora.config.port = Pandora::Utils.get_param('tcp_port')
          Pandora.config.host ||= 'any'
          Pandora.config.port ||= 5577
          $listen_thread = Thread.new do
            p Socket.ip_address_list
            begin
              host = Pandora.config.host
              if (not host)
                host = ''
              elsif ((host=='any') or (host=='all'))  #else can be "", "0.0.0.0", "0", "0::0", "::"
                host = Socket::INADDR_ANY
                p "ipv4 all"
              elsif ((host=='any6') or (host=='all6'))
                host = '::'
                p "ipv6 all"
              end
              server = TCPServer.open(host, Pandora.config.port)
              #addr_str = server.addr.to_s
              addr_str = server.addr[3].to_s+(' tcp')+server.addr[1].to_s
              Pandora.logger.info  _('Listening address')+': '+addr_str
            rescue
              server = nil
              Pandora.logger.warn  _('Cannot open port')+' '+host.to_s+':'+Pandora.config.port.to_s
            end
            Thread.current[:listen_server_socket] = server
            Thread.current[:need_to_listen] = (server != nil)
            while Thread.current[:need_to_listen] and server and (not server.closed?)
              socket = get_listener_client_or_nil(server)
              while Thread.current[:need_to_listen] and not server.closed? and not socket
                sleep 0.05
                #Thread.pass
                #Gtk.main_iteration
                socket = get_listener_client_or_nil(server)
              end

              if Thread.current[:need_to_listen] and (not server.closed?) and socket
                host_ip = socket.peeraddr[2]
                unless $window.pool.is_black?(host_ip)
                  host_name = socket.peeraddr[3]
                  port = socket.peeraddr[1]
                  proto = 'tcp'
                  p 'LISTEN: '+[host_name, host_ip, port, proto].inspect
                  session = Session.new(socket, host_name, host_ip, port, proto, \
                    CS_Connected, nil, nil, nil, nil)
                else
                  Pandora.logger.info  _('IP is banned')+': '+host_ip.to_s
                end
              end
            end
            server.close if server and (not server.closed?)
            Pandora.logger.info _('Listener stops')+' '+addr_str if server
            $window.set_status_field(PandoraGtk::SF_Listen, 'Not listen', nil, false)
            $listen_thread = nil
          end
        else
          $window.correct_lis_btn_state
        end
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
                    tokey = row[4]
                    tport = Pandora.config.port if (not tport) or (tport==0) or (tport=='')
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
end
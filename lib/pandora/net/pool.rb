module Pandora
  module Net

    # Pool
    # RU: Пул
    class Pool
      attr_accessor :window, :sessions, :white_list, :fish_orders

      MaxWhiteSize = 500

      def initialize(main_window)
        super()
        @window = main_window
        @sessions = Array.new
        @white_list = Array.new
        @fish_orders = Pandora::Utils::RoundQueue.new(true)
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

      # Add a session to list
      # RU: Добавляет сессию в список
      def add_session(conn)
        if not sessions.include?(conn)
          sessions << conn
          window.update_conn_status(conn, conn.get_type, 1)
        end
      end

      # Delete the session from list
      # RU: Удаляет сессию из списка
      def del_session(conn)
        if sessions.delete(conn)
          window.update_conn_status(conn, conn.get_type, -1)
        end
      end

      # Get a session for the node
      # RU: Возвращает сессию для узла
      def session_of_node(node)
        host, port, proto = decode_node(node)
        res = sessions.find do |e|
          ((e.host_ip == host) or (e.host_name == host)) and (e.port == port) and (e.proto == proto)
        end
        res
      end

      # Get a session by the key and base id
      # RU: Возвращает сессию по ключу и идентификатору базы
      def session_of_keybase(keybase)
        res = sessions.find { |e| (e.node_panhash == keybase) }
        res
      end

      # Get a session by the key panhash
      # RU: Возвращает сессию по панхэшу ключа
      def session_of_key(key)
        res = sessions.find { |e| (e.skey[Pandora::Crypto::KV_Panhash] == key) }
        res
      end

      # Get a session by the person panhash
      # RU: Возвращает сессию по панхэшу человека
      def session_of_person(person)
        res = sessions.find { |e| (e.skey[Pandora::Crypto::KV_Creator] == person) }
        res
      end

      # Get a session by the dialog
      # RU: Возвращает сессию по диалогу
      def sessions_on_dialog(dialog)
        res = sessions.select { |e| (e.dialog == dialog) }
        res.uniq!
        res.compact!
        res
      end

      FishQueueSize = 100

      # Add order to fishing
      # RU: Добавить заявку на рыбалку
      def add_fish_order(fish_key)
        @fish_orders.add_block_to_queue(fish_key, FishQueueSize) if not @fish_orders.queue.include?(fish_key)
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
          session.dialog = nil if (session.dialog and session.dialog.destroyed?)
          session.dialog = dialog if dialog
          if session.dialog and (not session.dialog.destroyed?) and session.dialog.online_button \
          and ((session.socket and (not session.socket.closed?)) or session.donor)
            session.dialog.online_button.safe_set_active(true)
            session.conn_mode = (session.conn_mode | Pandora::Net::CM_KeepHere)
          end
          res = true
        elsif (node or keybase)
          p 'NEED connect: '+[node, keybase].inspect
          if node
            host, port, proto = decode_node(node)
            sel = [[host, port]]
          else
            node_model = Pandora::Utils.get_model('Node')
            if node_id
              filter = {:id=>node_id}
            else
              filter = {:panhash=>keybase}
            end
            sel = node_model.select(filter, false, 'addr, tport, domain')
          end
          if sel and (sel.size>0)
            sel.each do |row|
              host = row[2]
              host.strip! if host
              addr = row[0]
              addr.strip! if addr
              port = row[1]
              proto = 'tcp'
              if (host and (host != '')) or (addr and (addr != ''))
                session = Session.new(nil, host, addr, port, proto, \
                  CS_Connecting, node_id, dialog, keybase, send_state_add)
                res = true
              end
            end
          end
        end
        res
      end

      # Stop session with a node
      # RU: Останавливает соединение с заданным узлом
      def stop_session(node=nil, keybase=nil, disconnect=true)  #, wait_disconnect=true)
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
            session.conn_mode = (session.conn_mode & (~Pandora::Net::CM_KeepHere))
            if disconnect
              session.conn_state = CS_StopRead
            end

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
      # RU: Формирует маркер узла
      def encode_node(host, port, proto)
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
          port = 5577
          proto = 'tcp'
        end
        [host, port, proto]
      end

      # Call callback address
      # RU: Стукануться по обратному адресу
      def check_callback_addr(addr, host_ip)
        res = false
        #p 'check_callback_addr  [addr, host_ip]='+[addr, host_ip].inspect
        if (addr.is_a? String) and (addr.size>0)
          host, port, proto = decode_node(addr)
          host.strip!
          host = host_ip if (not host) or (host=='')
          #p 'check_callback_addr  [host, port, proto]='+[host, port, proto].inspect
          if (host.is_a? String) and (host.size>0)
            p 'check_callback_addr DONE [host, port, proto]='+[host, port, proto].inspect
            res = true
          end
        end
      end

      # Initialize a fish for the required fisher
      # RU: Инициализирует рыбку для заданного рыбака
      def init_fish_for_fisher(fisher, in_lure, aim_keyhash=nil, baseid=nil)
        fish = nil
        if (aim_keyhash==nil) #or (aim_keyhash==mykeyhash)   #
          fish = Session.new(fisher, nil, in_lure, nil, nil, CS_Connected, \
            nil, nil, nil, nil)
        else  # alien key
          fish = @sessions.index { |session| session.skey[Pandora::Crypto::KV_Panhash] == keyhash }
        end
        fish
      end
    end

  end
end
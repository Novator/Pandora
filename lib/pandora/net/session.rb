module Pandora
  module Net

    class Session

      attr_accessor :host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state, :stage, :dialog, \
        :send_thread, :read_thread, :socket, :read_state, :send_state, :donor, :fisher_lure, :fish_lure, \
        :send_models, :recv_models, :sindex, :read_queue, :send_queue, :confirm_queue, :params, \
        :rcmd, :rcode, :rdata, :scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, :r_encode, \
        :media_send, :node_id, :node_panhash, :entered_captcha, :captcha_sw, :fishes, :fishers

      # Set socket options
      # RU: Установить опции сокета
      def set_keepalive(client)
        client.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, $keep_alive)
        if Pandora::Utils.os_family != 'windows'
          client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPIDLE, $keep_idle)
          client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPINTVL, $keep_intvl)
          client.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPCNT, $keep_cnt)
        end
      end

      # Link to pool
      # RU: Ссылка на пул
      def pool
        $window.pool
      end

      ST_Hunter   = 0
      ST_Listener = 1
      ST_Fisher   = 2

      # Type of session
      # RU: Тип сессии
      def get_type
        res = nil
        if donor
          res = ST_Fisher
        else
          if ((conn_mode & CM_Hunter)>0)
            res = ST_Hunter
          else
            res = ST_Listener
          end
        end
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
          Pandora.logger.error  _('Wrong length of command extention')
        end
        [datasize, fullcrc32, segsize]
      end

      LONG_SEG_SIGN   = 0xFFFF

      # Send command, code and date (if exists)
      # RU: Отправляет команду, код и данные (если есть)
      def send_comm_and_data(index, cmd, code, data=nil)
        res = nil
        index ||= 0  #нужно ли??!!
        code ||= 0   #нужно ли??!!
        lengt = 0
        lengt = data.bytesize if data
        p log_mes+'SEND_ALL: [index, cmd, code, lengt]='+[index, cmd, code, lengt].inspect
        if donor
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
          p [segsign, segdata, segsize].inspect
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
            Pandora.logger.error  _('Not all data was sent')+' '+sended.to_s
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
            elsif sended != -1
              res = nil
              Pandora.logger.error  _('Not all data was sent')+'2 '+sended.to_s
            end
            i += segdata
          end
          if res
            @sindex = res
          end
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
          Pandora.logger.warn  logmes+mesadd
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
          when EC_Auth
            @rkey = Pandora::Crypto.current_key(false, false)
            #p log_mes+'first key='+key.inspect
            if @rkey and @rkey[Pandora::Crypto::KV_Obj]
              key_hash = @rkey[Pandora::Crypto::KV_Panhash]
              ascode = EC_Auth
              ascode = ECC_Auth_Hello
              params['mykey'] = key_hash
              params['tokey'] = param
              hparams = {:version=>0, :mode=>0, :mykey=>key_hash, :tokey=>param}
              hparams[:addr] = $callback_addr if $callback_addr and (not ($callback_addr != ''))
              asbuf = Pandora::Utils.namehash_to_pson(hparams)
            else
              ascmd = EC_Bye
              ascode = ECC_Bye_Exit
              asbuf = nil
            end
          when EC_Message
            #???values = {:destination=>panhash, :text=>text, :state=>state, \
            #  :creator=>creator, :created=>time_now, :modified=>time_now}
            #      kind = Pandora::Utils.kind_from_panhash(panhash)
            #      record = PandoraModel.get_record_by_panhash(kind, panhash, true, @recv_models)
            #      p log_mes+'EC_Request panhashes='+Pandora::Utils.bytes_to_hex(panhash).inspect
            asbuf = Pandora::Utils.rubyobj_to_pson_elem(param)
          when EC_Bye
            ascmd = EC_Bye
            ascode = ECC_Bye_Exit
            asbuf = param
          else
            asbuf = param
        end
        if (@send_queue.single_read_state != Pandora::Utils::RoundQueue::QS_Full)
          res = @send_queue.add_block_to_queue([ascmd, ascode, asbuf])
        end
        if ascmd != EC_Media
          asbuf ||= '';
          p log_mes+'add_send_segment:  [ascmd, ascode, asbuf.bytesize]='+[ascmd, ascode, asbuf.bytesize].inspect
          p log_mes+'add_send_segment2: asbuf='+asbuf.inspect if sbuf
        end
        if not res
          Pandora.logger.error  _('Cannot add segment to send queue')
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
          asbuf = Pandora::Utils.rubyobj_to_pson_elem(panhashes)
        else
          # one panhash
          ascode = Pandora::Utils.kind_from_panhash(panhashes)
          asbuf = panhashes[1..-1]
        end
        if send_now
          if not add_send_segment(ascmd, true, asbuf, ascode)
            Pandora.logger.error  _('Cannot add request')
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
            Pandora.logger.error  _('Cannot add query')
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

        # Recognize hello data
        # RU: Распознает данные приветствия
        def recognize_params
          hash = Pandora::Utils.pson_to_namehash(rdata)
          if not hash
            err_scmd('Hello data is wrong')
          end
          if (rcmd == EC_Auth) and (rcode == ECC_Auth_Hello)
            params['version']  = hash['version']
            params['mode']     = hash['mode']
            params['addr']     = hash['addr']
            params['srckey']   = hash['mykey']
            params['dstkey']   = hash['tokey']
          end
          p log_mes+'RECOGNIZE_params: '+hash.inspect
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
            when ES_Exchange
              @max_pack_size = MPS_Exchange
          end
        end

        # React to hello
        # RU: Отреагировать на приветствие
        def init_skey_or_error(first=true)

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

          skey_panhash = params['srckey']
          if (skey_panhash.is_a? String) and (skey_panhash.bytesize>0)
            if first and (@stage == ES_Protocol) and $puzzle_bit_length \
            and ($puzzle_bit_length>0) and ((conn_mode & CM_Hunter) == 0)
              # first need to puzzle
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
              @skey = Pandora::Crypto.open_key(skey_panhash, @recv_models, false)
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

        # Compose a captcha command
        # RU: Компоновать команду с капчой
        def send_captcha
          attempts = @skey[Pandora::Crypto::KV_Trust]
          p log_mes+'send_captcha:  attempts='+attempts.to_s
          if attempts<$captcha_attempts
            @skey[Pandora::Crypto::KV_Trust] = attempts+1
            @scmd = EC_Auth
            @scode = ECC_Auth_Captcha
            text, buf = Pandora::Utils.generate_captcha(nil, $captcha_length)
            params['captcha'] = text.downcase
            clue_text = 'You may enter small letters|'+$captcha_length.to_s+'|'+PandoraGtk::CapSymbols
            clue_text = clue_text[0,255]
            @sbuf = [clue_text.bytesize].pack('C')+clue_text+buf
            @stage = ES_Captcha
            set_max_pack_size(ES_Captcha)
          else
            err_scmd('Captcha attempts is exhausted')
          end
        end

        # Update record about node
        # RU: Обновить запись об узле
        def update_node(skey_panhash=nil, sbase_id=nil, trust=nil, session_key=nil)
          node_model = Pandora::Utils.get_model('Node', @recv_models)
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

          trusted = ((trust.is_a? Float) and (trust>0))
          filter = {:key_hash=>skey_panhash, :base_id=>sbase_id}
          #if not trusted
          #  filter[:addr_from] = host_ip
          #end
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

          p '=====%%%% %%%: [aaddr, adomain, @host_ip, @host_name]'+[aaddr, adomain, @host_ip, @host_name].inspect

          values = {}
          if (not acreator) or (not acreated)
            acreator ||= Pandora::Crypto.current_user_or_key(true)
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
          values[:session_key]  = @session_key
          values[:ban_time]     = aban_time
          values[:modified]     = time_now

          inaddr = params['addr']
          if inaddr and (inaddr != '')
            host, port, proto = pool.decode_node(inaddr)
            #p log_mes+'ADDR [addr, host, port, proto]='+[addr, host, port, proto].inspect
            if host and (host != '') and ((not adomain) or (adomain=='') or trusted)
              adomain = host
              port = 5577 if (not port) or (port==0)
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
              adomain = bdomain if (not adomain) or (adomain=='')

              values[:addr_type] ||= baddr_type
              node_model.update(nil, nil, filter2)
            end
          end

          if (not adomain) or (adomain=='')
            if (not aaddr) or (aaddr=='')
              aaddr = @host_ip
              adomain = @host_name
            else
              adomain = aaddr
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

        # Process media segment
        # RU: Обработать медиа сегмент
        def process_media_segment(cannel, mediabuf)
          if not dialog
            @conn_mode = (@conn_mode | Pandora::Net::CM_KeepHere)
            #node = Pandora::Net.encode_node(host_ip, port, proto)
            panhash = @skey[Pandora::Crypto::KV_Creator]
            @dialog = PandoraGtk.show_talk_dialog(panhash, @node_panhash)
            dialog.update_state(true)
            Thread.pass
            #Pandora::Utils.play_mp3('online')
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
              appsrc.play if (not Pandora::Utils::elem_playing?(appsrc))
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
            node_model = Pandora::Utils.get_model('Node', @recv_models)
            filter = {:id=>@node_id}
            sel = node_model.select(filter, false, 'password', nil, 1)
            if sel and sel.size>0
              row = sel[0]
              password = row[0]
            end
          end
          password
        end

        # Take out lure by input lure for the fisher
        # RU: Взять исходящую наживку по входящей наживке для заданного рыбака
        def take_out_lure_for_fisher(fisher, in_lure)
          out_lure = nil
          val = [fisher, in_lure]
          out_lure = @fishers.index(val)
          p '-===--take_out_lure_for_fisher  in_lure, out_lure='+[in_lure, out_lure].inspect
          if not out_lure
            # need to registrate output lure
            i = 0
            while (i<@fishers.size)
              break if (not (@fishers[i].is_a? Array))  #or (@fishers[i][0].destroyed?))
              i += 1
            end
            out_lure = i if (not out_lure) and (i<=255)
            @fishers[out_lure] = val if out_lure
          end
          out_lure
        end

        # Check out lure by input lure and the fisher
        # RU: Проверить исходящую наживку по входящей наживке и рыбаку
        def get_out_lure_for_fisher(fisher, in_lure)
          val = [fisher, in_lure]
          out_lure = @fishers.index(val)
          p '----get_out_lure_for_fisher  in_lure, out_lure='+[in_lure, out_lure].inspect
          out_lure
        end

        # Get fisher for out lure
        # RU: Определить рыбака по исходящей наживке
        def get_fisher_for_out_lure(out_lure)
          fisher, in_lure = nil, nil
          val = @fishers[out_lure] if out_lure.is_a? Integer
          fisher, in_lure = val if val.is_a? Array
          p '~~~~~ get_fisher_for_out_lure  in_lure, out_lure='+[in_lure, out_lure].inspect
          [fisher, in_lure]
        end

        # Clear out lures for the fisher and input lure
        # RU: Очистить исходящие наживки для рыбака и входящей наживки
        def free_out_lure_of_fisher(fisher, in_lure)
          val = [fisher, in_lure]
          p '====//// free_out_lure_of_fisher(in_lure)='+in_lure.inspect
          while out_lure = @fishers.index(val)
            p '//// free_out_lure_of_fisher(in_lure), out_lure='+[in_lure, out_lure].inspect
            @fishers[out_lure] = nil
            if fisher #and (not fisher.destroyed?)
              if fisher.donor
                fisher.conn_state = CS_StopRead if (fisher.conn_state < CS_StopRead)
              end
              fisher.free_fish_of_in_lure(in_lure)
            end
          end
        end

        # Set a fish of the input lure
        # RU: Поставить рыбку на входящую наживку
        def set_fish_of_in_lure(in_lure, fish)
          p '+++++set_fish_of_in_lure(in_lure)='+in_lure.inspect
          @fishes[in_lure] = fish if in_lure.is_a? Integer
        end

        # Get a fish by the input lure
        # RU: Взять рыбку по входящей наживке
        def get_fish_for_in_lure(in_lure)
          fish = nil
          p '+++++get_fish_for_in_lure(in_lure)='+in_lure.inspect
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

        # Clear the fish on the input lure
        # RU: Очистить рыбку для входящей наживки
        def free_fish_of_in_lure(in_lure)
          if in_lure.is_a? Integer
            fish = @fishes[in_lure]
            p '//// free_fish_of_in_lure(in_lure)='+in_lure.inspect
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
          p '******send_segment_to_fish(in_lure)='+in_lure.inspect
          if segment and (segment.bytesize>1)
            cmd = segment[0].ord
            fish = get_fish_for_in_lure(in_lure)
            if not fish
              if cmd == EC_Bye
                fish = false
              else
                fish = pool.init_fish_for_fisher(self, in_lure, nil, nil)
                set_fish_of_in_lure(in_lure, fish)
              end
            end
            #p 'send_segment_to_fish: in_lure,segsize='+[in_lure, segment.bytesize].inspect
            if fish
              if fish.donor == self
                #p 'DONOR lure'
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
            elsif fish.nil?
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
            p '&&&&& send_segment_to_fisher: out_lure,fisher,in_lure,segsize='+[out_lure, fisher, in_lure, segment.bytesize].inspect
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
          when EC_Auth
            if @stage<=ES_Greeting
              if rcode<=ECC_Auth_Answer
                if (rcode==ECC_Auth_Hello) and ((@stage==ES_Protocol) or (@stage==ES_Sign))
                  recognize_params
                  if scmd != EC_Bye
                    vers = params['version']
                    if vers==0
                      addr = params['addr']
                      p log_mes+'addr='+addr.inspect
                      # need to change an ip checking
                      pool.check_callback_addr(addr, host_ip) if addr
                      mode = params['mode']
                      init_skey_or_error(true)
                    else
                      err_scmd('Protocol is not supported ('+vers.to_s+')')
                    end
                  end
                elsif ((rcode==ECC_Auth_Puzzle) or (rcode==ECC_Auth_Phrase)) \
                and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
                  if rdata and (rdata != '')
                    rphrase = rdata
                    params['rphrase'] = rphrase
                  else
                    rphrase = params['rphrase']
                  end
                  p log_mes+'recived phrase len='+rphrase.bytesize.to_s
                  if rphrase and (rphrase != '')
                    if rcode==ECC_Auth_Puzzle  #phrase for puzzle
                      if ((conn_mode & CM_Hunter) == 0)
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
                      sign = Pandora::Crypto.make_sign(@rkey, rphrase)
                      if sign
                        len = $base_id.bytesize
                        len = 255 if len>255
                        @sbuf = [len].pack('C')+$base_id[0,len]+sign
                        @scode = ECC_Auth_Sign
                        if @stage == ES_Greeting
                          @stage = ES_Exchange
                          set_max_pack_size(ES_Exchange)
                          Pandora::Utils.play_mp3('online')
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
                    if Pandora::Crypto.check_sha1_solution(sphrase, suffix)
                      init_skey_or_error(false)
                    else
                      err_scmd('Wrong sha1 solution')
                    end
                  end
                elsif (rcode==ECC_Auth_Sign) and (@stage==ES_Sign)
                  len = rdata[0].ord
                  sbase_id = rdata[1, len]
                  rsign = rdata[len+1..-1]
                  #p log_mes+'recived rsign len='+rsign.bytesize.to_s
                  @skey = Pandora::Crypto.open_key(@skey, @recv_models, true)
                  if @skey and @skey[Pandora::Crypto::KV_Obj]
                    if Pandora::Crypto.verify_sign(@skey, OpenSSL::Digest::SHA384.digest(params['sphrase']), rsign)
                      creator = Pandora::Crypto.current_user_or_key(true)
                      if ((conn_mode & CM_Hunter) != 0) or (not @skey[Pandora::Crypto::KV_Creator]) \
                      or (@skey[Pandora::Crypto::KV_Creator] != creator)
                        # check messages if it's not session to myself
                        @send_state = (@send_state | CSF_Message)
                      end
                      trust = @skey[Pandora::Crypto::KV_Trust]
                      update_node(@skey[Pandora::Crypto::KV_Panhash], sbase_id, trust)
                      if ((conn_mode & CM_Hunter) == 0)
                        trust = 0 if (not trust) and $trust_for_captchaed
                      elsif $trust_for_listener and (not (trust.is_a? Float))
                        trust = 0.01
                        @skey[Pandora::Crypto::KV_Trust] = trust
                      end
                      p log_mes+'----trust='+trust.inspect
                      if ($captcha_length>0) and (trust.is_a? Integer) \
                      and ((conn_mode & CM_Hunter) == 0)
                        @skey[Pandora::Crypto::KV_Trust] = 0
                        send_captcha
                      elsif trust.is_a? Float
                        if trust>=$low_conn_trust
                          if (conn_mode & CM_Hunter) == 0
                            @stage = ES_Greeting
                            add_send_segment(EC_Auth, true, params['srckey'])
                            set_max_pack_size(ES_Sign)
                          else
                            @stage = ES_Exchange
                            set_max_pack_size(ES_Exchange)
                            #Pandora::Utils.play_mp3('online')
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
                      err_scmd('Wrong sign')
                    end
                  else
                    err_scmd('Cannot init your key')
                  end
                elsif (rcode==ECC_Auth_Simple) and (@stage==ES_Protocol)
                  p 'ECC_Auth_Simple!'
                  rphrase = rdata
                  #p 'rphrase='+rphrase.inspect
                  password = get_simple_answer_to_node
                  if (password.is_a? String) and (password.bytesize>0)
                    password_hash = OpenSSL::Digest::SHA256.digest(password)
                    answer = OpenSSL::Digest::SHA256.digest(rphrase+password_hash)
                    @scmd = EC_Auth
                    @scode = ECC_Auth_Answer
                    @sbuf = answer
                    @conn_mode = (@conn_mode | Pandora::Net::CM_KeepHere)
                  else
                    err_scmd('Node password is not setted')
                  end
                elsif (rcode==ECC_Auth_Captcha) and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
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
                      while $window.cvpaned.csw and @entered_captcha.nil?
                        sleep(0.02)
                        Thread.pass
                      end
                      if @entered_captcha
                        @scmd = EC_Auth
                        @scode = ECC_Auth_Answer
                        @sbuf = entered_captcha
                      else
                        err_scmd('Captcha enter canceled')
                      end
                    else
                      err_scmd('Captcha dock is busy')
                    end
                  end
                elsif (rcode==ECC_Auth_Answer) and (@stage==ES_Captcha)
                  captcha = rdata
                  p log_mes+'recived captcha='+captcha if captcha
                  if captcha.downcase==params['captcha']
                    @stage = ES_Greeting
                    if not (@skey[Pandora::Crypto::KV_Trust].is_a? Float)
                      if $trust_for_captchaed
                        @skey[Pandora::Crypto::KV_Trust] = 0.01
                      else
                        @skey[Pandora::Crypto::KV_Trust] = nil
                      end
                    end
                    p 'Captcha is GONE!'
                    if (conn_mode & CM_Hunter) == 0
                      add_send_segment(EC_Auth, true, params['srckey'])
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
          when EC_Request
            kind = rcode
            p log_mes+'EC_Request  kind='+kind.to_s+'  stage='+@stage.to_s
            panhash = nil
            if (kind==PandoraModel::PK_Key) and ((@stage==ES_Protocol) or (@stage==ES_Greeting))
              panhash = params['mykey']
              p 'params[mykey]='+panhash
            end
            if (@stage==ES_Exchange) or (@stage==ES_Greeting) or panhash
              panhashes = nil
              if kind==0
                panhashes, len = Pandora::Utils.pson_elem_to_rubyobj(panhashes)
              else
                panhash = [kind].pack('C')+rdata if (not panhash) and rdata
                panhashes = [panhash]
              end
              p log_mes+'panhashes='+panhashes.inspect
              if panhashes.size==1
                panhash = panhashes[0]
                kind = Pandora::Utils.kind_from_panhash(panhash)
                pson = PandoraModel.get_record_by_panhash(kind, panhash, false, @recv_models)
                if pson
                  @scmd = EC_Record
                  @scode = kind
                  @sbuf = pson
                  lang = @sbuf[0].ord
                  values = Pandora::Utils.pson_to_namehash(@sbuf[1..-1])
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
                  kind = Pandora::Utils.kind_from_panhash(panhash)
                  record = PandoraModel.get_record_by_panhash(kind, panhash, true, @recv_models)
                  p log_mes+'EC_Request panhashes='+Pandora::Utils.bytes_to_hex(panhash).inspect
                  rec_array << record if record
                end
                if rec_array.size>0
                  records = PandoraGtk.rubyobj_to_pson_elem(rec_array)
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
              if (@stage==ES_Exchange) or ((kind==PandoraModel::PK_Key) and (@stage==ES_KeyRequest))
                lang = rdata[0].ord
                values = Pandora::Utils.pson_to_namehash(rdata[1..-1])
                panhash = nil
                if @stage==ES_KeyRequest
                  panhash = params['srckey']
                end
                res = PandoraModel.save_record(kind, lang, values, @recv_models, panhash)
                if res
                  if @stage==ES_KeyRequest
                    @stage = ES_Protocol
                    init_skey_or_error(false)
                  end
                elsif res==false
                  Pandora.logger.warn  _('Record came with wrong panhash')
                else
                  Pandora.logger.warn  _('Cannot write a record')+' 1'
                end
              else
                err_scmd('Record ('+kind.to_s+') came on wrong stage')
              end
            elsif (@stage==ES_Exchange)
              records, len = Pandora::Utils.pson_elem_to_rubyobj(rdata)
              p log_mes+"!record2! recs="+records.inspect
              PandoraModel.save_records(records, @recv_models)
            else
              err_scmd('Records came on wrong stage')
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
              when ECC_Sync3_Confirm
                confirms = rdata
                p log_mes+'recv confirms='+confirms
                if confirms
                  prev_kind = nil
                  i = 0
                  while (i<confirms.bytesize)
                    kind = confirms[i].ord
                    if (not prev_kind) or (kind != prev_kind)
                      panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
                      model = Pandora::Utils.get_model(panobjectclass.ider, @recv_models)
                      prev_kind = kind
                    end
                    id = confirms[i+1, 4].unpack('N')
                    p log_mes+'update confirm  kind,id='+[kind, id].inspect
                    res = model.update({:state=>2}, nil, {:id=>id})
                    if not res
                      Pandora.logger.warn  _('Cannot update record of confirm')+' kind,id='+[kind,id].inspect
                    end
                    i += 5
                  end
                end
            end
          when EC_Wait
            case rcode
              when EC_Wait1_NoFish
                Pandora.logger.error  _('Cannot find a fish')
            end
          when EC_Bye
            errcode = ECC_Bye_Exit
            if rcode == ECC_Bye_NoAnswer
              errcode = ECC_Bye_Silent
            elsif rcode != ECC_Bye_Exit
              mes = rdata
              mes ||= ''
              i = mes.index(' (') if mes
              p '---------'
              p mes
              if i
                p mes[0, i]
                mes = _(mes[0, i])+mes[i..-1]
              end
              Pandora.logger.error  _('Error at other side')+' ErrCode='+rcode.to_s+' "'+mes+'"'
            end
            err_scmd(nil, errcode, false)
            @conn_state = CS_Stoping
          else
            if @stage>=ES_Exchange
              case rcmd
                when EC_Message, EC_Channel
                  if (not dialog) or dialog.destroyed?
                    @conn_mode = (@conn_mode | Pandora::Net::CM_KeepHere)
                    panhash = @skey[Pandora::Crypto::KV_Creator]
                    @dialog = PandoraGtk.show_talk_dialog(panhash, @node_panhash)
                    Thread.pass
                    #Pandora::Utils.play_mp3('online')
                  end
                  if rcmd==EC_Message
                    row = @rdata
                    if row.is_a? String
                      row, len = Pandora::Utils.pson_elem_to_rubyobj(row)
                      t = Time.now
                      id = nil
                      time_now = t.to_i
                      creator = @skey[Pandora::Crypto::KV_Creator]
                      created = time_now
                      destination = @rkey[Pandora::Crypto::KV_Creator]
                      text = nil
                      if row.is_a? Array
                        id = row[0]
                        creator = row[1]
                        created = row[2]
                        text = row[3]
                      else
                        text = row
                      end

                      values = {:destination=>destination, :text=>text, :state=>2, \
                        :creator=>creator, :created=>created, :modified=>time_now}
                      model = Pandora::Utils.get_model('Message', @recv_models)
                      panhash = model.panhash(values)
                      values['panhash'] = panhash
                      res = model.update(values, nil, nil)
                      if res and (id.is_a? Integer)
                        while (@confirm_queue.single_read_state == Pandora::Utils::RoundQueue::QS_Full) do
                          sleep(0.02)
                        end
                        @confirm_queue.add_block_to_queue([PandoraModel::PK_Message].pack('C') \
                          +[id].pack('N'))
                      end

                      talkview = nil
                      talkview = dialog.talkview if dialog
                      if talkview

                        #talkview.before_addition(t)
                        #talkview.buffer.insert(talkview.buffer.end_iter, "\n") if talkview.buffer.text != ''
                        #talkview.buffer.insert(talkview.buffer.end_iter, t.strftime('%H:%M:%S')+' ', 'dude')
                        myname = Pandora::Crypto.short_name_of_person(@rkey)
                        #dude_name = Pandora::Crypto.short_name_of_person(@skey, nil, 0, myname)
                        #talkview.buffer.insert(talkview.buffer.end_iter, dude_name+':', 'dude_bold')
                        #talkview.buffer.insert(talkview.buffer.end_iter, ' '+text)
                        #talkview.after_addition
                        #talkview.show_all
                        #dialog.update_state(true)

                        dialog.add_mes_to_view(text, @skey, myname, time_now, created)

                      else
                        Pandora.logger.error  'Пришло сообщение, но лоток чата не найден!'
                      end
                    end
                  else #EC_Channel
                    case rcode
                      when ECC_Channel0_Open
                        p 'ECC_Channel0_Open'
                      when ECC_Channel2_Close
                        p 'ECC_Channel2_Close'
                    else
                      Pandora.logger.error  'Неизвестный код управления каналом: '+rcode.to_s
                    end
                  end
                when EC_Media
                  process_media_segment(rcode, rdata)
                when EC_Query
                  case rcode
                    when ECC_Query_Rel
                      p log_mes+'===ECC_Query_Rel'
                      from_time = rdata[0, 4].unpack('N')[0]
                      pankinds = rdata[4..-1]
                      trust = @skey[Pandora::Crypto::KV_Trust]
                      trust = -1.0 if not (trust.is_a? Float)
                      p log_mes+'from_time, pankinds, trust='+[from_time, pankinds, trust].inspect
                      pankinds = Pandora::Crypto.allowed_kinds(trust, pankinds)
                      p log_mes+'pankinds='+pankinds.inspect

                      whyer = @rkey[Pandora::Crypto::KV_Creator]
                      answerer = @skey[Pandora::Crypto::KV_Creator]
                      key=nil
                      #ph_list = []
                      #ph_list << PandoraModel.signed_records(whyer, from_time, pankinds, \
                      #  trust, key, models)
                      ph_list = PandoraModel.public_records(whyer, trust, from_time, \
                        pankinds, @send_models)

                      #panhash_list = PandoraModel.get_panhashes_by_kinds(kind_list, from_time)
                      #panhash_list = PandoraModel.get_panhashes_by_whyer(whyer, trust, from_time)

                      p log_mes+'ph_list='+ph_list.inspect
                      ph_list = Pandora::Utils.rubyobj_to_pson_elem(ph_list) if ph_list
                      @scmd = EC_News
                      @scode = ECC_News_Panhash
                      @sbuf = ph_list
                    when ECC_Query_Record  #EC_Request
                      p log_mes+'==ECC_Query_Record'
                      two_list, len = Pandora::Utils.pson_elem_to_rubyobj(rdata)
                      need_ph_list, foll_list = two_list
                      p log_mes+'need_ph_list, foll_list='+[need_ph_list, foll_list].inspect
                      created_list = []
                      if (foll_list.is_a? Array) and (foll_list.size>0)
                        from_time = Time.now.to_i - 7*24*3600
                        kinds = (1..255).to_a - [PandoraModel::PK_Message]
                        p 'kinds='+kinds.inspect
                        foll_list.each do |panhash|
                          if panhash[0].ord==PandoraModel::PK_Person
                            cr_l = PandoraModel.created_records(panhash, from_time, kinds, @send_models)
                            p 'cr_l='+cr_l.inspect
                            created_list = created_list + cr_l if cr_l
                          end
                        end
                        created_list.flatten!
                        created_list.uniq!
                        created_list.compact!
                        created_list.sort! {|a,b| a[0]<=>b[0] }
                        p log_mes+'created_list='+created_list.inspect
                      end
                      pson_records = []
                      if (need_ph_list.is_a? Array) and (need_ph_list.size>0)
                        p log_mes+'need_ph_list='+need_ph_list.inspect
                        need_ph_list.each do |panhash|
                          kind = Pandora::Utils.kind_from_panhash(panhash)
                          p log_mes+[panhash, kind].inspect
                          p res = PandoraModel.get_record_by_panhash(kind, panhash, true, \
                            @send_models)
                          pson_records << res if res
                        end
                        p log_mes+'pson_records='+pson_records.inspect
                      end
                      @scmd = EC_News
                      @scode = ECC_News_Record
                      @sbuf = Pandora::Utils.rubyobj_to_pson_elem([pson_records, created_list])
                    when ECC_Query_Fish
                      to_key = rdata
                      p '--ECC_Query_Fish to_key='+to_key.inspect
                      if to_key
                        session = pool.session_of_key(to_key)
                        if session
                          p log_mes+' session='+session.inspect
                          @scmd = EC_News
                          @scode = ECC_News_Fish
                          @sbuf = to_key
                        else
                          pool.add_fish_order(to_key)
                        end
                      end
                    else #запрос сорта (1-254) или всех сортов (255)
                      afrom_data = rdata
                      akind = rcode
                      if (akind == ECC_Query255_AllChanges)
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
                  case rcode
                    when ECC_News_Panhash
                      p log_mes+'==ECC_News_Panhash'
                      ph_list, len = Pandora::Utils.pson_elem_to_rubyobj(rdata)
                      p log_mes+'ph_list, len='+[ph_list, len].inspect
                      # Check non-existing records
                      need_ph_list = PandoraModel.needed_records(ph_list, @send_models)
                      p log_mes+'need_ph_list='+ need_ph_list.inspect

                      two_list = [need_ph_list]

                      whyer = @rkey[Pandora::Crypto::KV_Creator] #me
                      answerer = @skey[Pandora::Crypto::KV_Creator]
                      p '[whyer, answerer]='+[whyer, answerer].inspect
                      follower = nil
                      from_time = Time.now.to_i - 10*24*3600
                      pankinds = nil
                      foll_list = PandoraModel.follow_records(follower, from_time, \
                        pankinds, @send_models)
                      two_list << foll_list
                      two_list = Pandora::Utils.rubyobj_to_pson_elem(two_list)
                      @scmd = EC_Query
                      @scode = ECC_Query_Record
                      @sbuf = two_list
                    when ECC_News_Record
                      p log_mes+'==ECC_News_Record'
                      two_list, len = Pandora::Utils.pson_elem_to_rubyobj(rdata)
                      pson_records, created_list = two_list
                      p log_mes+'pson_records, created_list='+[pson_records, created_list].inspect
                      PandoraModel.save_records(pson_records, @recv_models)
                      if (created_list.is_a? Array) and (created_list.size>0)
                        need_ph_list = PandoraModel.needed_records(created_list, @send_models)
                        @scmd = EC_Query
                        @scode = ECC_Query_Record
                        foll_list = nil
                        @sbuf = Pandora::Utils.rubyobj_to_pson_elem([need_ph_list, foll_list])
                      end
                    when ECC_News_Fish
                      fish = rdata
                      if fish
                        p log_mes+'--ECC_News_Fish fish='+fish.inspect
                        session = pool.session_waiting_fish(fish)
                        if session
                          p log_mes+' session='+session.inspect
                          #out_lure = take_out_lure_for_fisher(session, to_key)
                          #send_segment_to_fisher(out_lure)
                          session.donor = self
                          session.fish_lure = session.registrate_fish(fish)
                          sthread = session.send_thread
              if sthread and sthread.alive? and sthread.stop?
                sthread.run
              end
                        end
                      end
                    else
                      p "news more!!!!"
                      pkind = rcode
                      pnoticecount = rdata.unpack('N')
                      @scmd = EC_Sync
                      @scode = 0
                      @sbuf = ''
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

      # Number of messages per cicle
      # RU: Число сообщений за цикл
      $mes_block_count = 5
      # Number of media blocks per cicle
      # RU: Число медиа блоков за цикл
      $media_block_count = 10
      # Number of requests per cicle
      # RU: Число запросов за цикл
      $inquire_block_count = 1

      $conn_period       = 5

      # Starts three session cicle: read from queue, read from socket, send (common)
      # RU: Запускает три цикла сессии: чтение из очереди, чтение из сокета, отправка (общий)
      def initialize(asocket, ahost_name, ahost_ip, aport, aproto, \
      aconn_state, anode_id, a_dialog, tokey, send_state_add)
        super()
        @conn_state  = CS_Connecting
        @socket      = nil
        @donor       = nil
        @conn_mode   = 0
        @fishes         = Array.new
        @fishers        = Array.new
        @read_queue     = Pandora::Utils::RoundQueue.new
        @send_queue     = Pandora::Utils::RoundQueue.new
        @confirm_queue  = Pandora::Utils::RoundQueue.new
        @send_models    = {}
        @recv_models    = {}

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
            # донор-сессия
            if asocket.socket and (not asocket.socket.closed?)
              # задать донора
              @donor = asocket
              # задать канал
              if ahost_name
                @fisher_lure = ahost_name
              else
                @fish_lure = ahost_ip
              end
            end
          end

          # Main cicle of session
          # RU: Главный цикл сессии
          while need_connect do
            @conn_mode = (@conn_mode & (~CM_Hunter))

            # is there connection?
            # есть ли подключение?   or (@socket.closed?)
            if ((not @socket) ) \
            and ((not @donor) or (not @donor.socket) or (@donor.socket.closed?))
              # нет подключения ни через сокет, ни через донора
              # значит, нужно подключаться самому
              host = ahost_name
              host = ahost_ip if ((not host) or (host == ''))

              if (not host) or (host=='')
                host, port = pool.hunt_address(tokey)
              end

              port = aport
              port ||= 5577
              port = port.to_i

              asocket = nil
              if (host.is_a? String) and (host.size>0) and port
                @conn_mode = (@conn_mode | CM_Hunter)
                server = host+':'+port.to_s

                # Try to connect
                @conn_thread = Thread.new do
                  begin
                    asocket = TCPSocket.open(host, port)
                    @socket = asocket
                  rescue
                    asocket = nil
                    @socket = asocket
                    if (not work_time) or ((Time.now.to_i - work_time.to_i)>15)
                      Pandora.logger.warn  _('Fail connect to')+': '+server
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
                    Pandora.logger.debug  _('Timeout connect to')+': '+server
                  end
                end
              else
                asocket = false
              end

              if not @socket
                # Add fish order and wait donor
                pool.add_fish_order(tokey)
                while (not @donor) and (not @socket)
                  p 'Thread.stop tokey='+tokey.inspect
                  Thread.stop
                end
              end

            end

            work_time = Time.now


            sss = [@socket, @donor].inspect
            sss += '|1:'+[@socket.closed?].inspect if @socket
            sss += '|2:'+[@donor.socket].inspect if @donor
            sss += '|3:'+[@donor.socket.closed?].inspect if @donor and @donor.socket
            p '==reconn: '+sss
            sleep 0.5


            if @socket
              if ((conn_mode & CM_Hunter) == 0)
                Pandora.logger.info  _('Hunter connects')+': '+socket.peeraddr.inspect
              else
                Pandora.logger.info  _('Connected to listener')+': '+server
              end
              @host_name    = ahost_name
              @host_ip      = ahost_ip
              @port         = aport
              @proto        = aproto
              @node         = pool.encode_node(@host_ip, @port, @proto)
              @node_id      = anode_id
            end

            # есть ли подключение?
            if (@socket and (not @socket.closed?)) \
            or (@donor and @donor.socket and (not @donor.socket.closed?))
              @stage          = ES_Protocol  #ES_IpCheck
              #@conn_state     = aconn_state
              @conn_state     = CS_Connected
              @read_state     = 0
              send_state_add  ||= 0
              @send_state     = send_state_add
              @sindex         = 0
              @params         = {}
              @media_send     = false
              @node_panhash   = nil
              pool.add_session(self)
              if @socket
                set_keepalive(@socket)
              end

              if a_dialog and (not a_dialog.destroyed?)
                @dialog = a_dialog
                dialog.set_session(self, true)
                #dialog.online_button.active = (socket and (not socket.closed?))
                if self.dialog and (not self.dialog.destroyed?) and self.dialog.online_button \
                and ((self.socket and (not self.socket.closed?)) or self.donor)
                  self.dialog.online_button.safe_set_active(true)
                end
              end

              #Thread.critical = true
              #PandoraGtk.add_session(self)
              #Thread.critical = false

              @max_pack_size = MPS_Proto
              @log_mes = 'LIS: '
              if (conn_mode & CM_Hunter)>0
                @log_mes = 'HUN: '
                @max_pack_size = MPS_Captcha
                add_send_segment(EC_Auth, true, tokey)
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

                  rkcmd = EC_Data
                  rkcode = 0
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
                      p log_mes+'readmode, rkbuf.len, waitlen='+[readmode, rkbuf.size, waitlen].inspect
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
                            Pandora.logger.error  _('Cannot add error segment to send queue')
                          end
                        end
                        @conn_state = CS_Stoping
                      elsif (readmode == RM_Comm)
                        #p log_mes+'-- from socket to read queue: [rkcmd, rcode, rkdata.size]='+[rkcmd, rkcode, rkdata.size].inspect
                        if @r_encode and rkdata and (rkdata.bytesize>0)
                          #@rkdata = PandoraGtk.recrypt(@rkey, @rkdata, false, true)
                          #@rkdata = Base64.strict_decode64(@rkdata)
                          #p log_mes+'::: decode rkdata.size='+rkdata.size.to_s
                        end

                        if rkcmd==EC_Media
                          process_media_segment(rkcode, rkdata)
                        else
                          while (@read_queue.single_read_state == Pandora::Utils::RoundQueue::QS_Full) \
                          and (@conn_state == CS_Connected)
                            sleep(0.03)
                            Thread.pass
                          end
                          res = @read_queue.add_block_to_queue([rkcmd, rkcode, rkdata])
                          if not res
                            Pandora.logger.error  _('Cannot add socket segment to read queue')
                            @conn_state = CS_Stoping
                          end
                        end
                        rkdata = AsciiString.new
                      end

                      if not ok1comm
                        Pandora.logger.error  'Bad first command'
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
                @rcmd = EC_Data
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
                      while (@send_queue.single_read_state == Pandora::Utils::RoundQueue::QS_Full) \
                      and (@conn_state == CS_Connected)
                        sleep(0.03)
                        Thread.pass
                      end
                      res = @send_queue.add_block_to_queue([@scmd, @scode, @sbuf])
                      @scmd = EC_Data
                      if not res
                        Pandora.logger.error  'Error while adding segment to queue'
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
              inquirer_step = IS_ResetMessage
              message_model = Pandora::Utils.get_model('Message', @send_models)
              p log_mes+'ЦИКЛ ОТПРАВКИ начало: @conn_state='+@conn_state.inspect

              while (@conn_state != CS_Disconnected)
                #p '@conn_state='+@conn_state.inspect

                fast_data = false

                # формирование подтверждений
                if (@conn_state != CS_Disconnected)
                  ssbuf = ''
                  confirm_rec = @confirm_queue.get_block_from_queue
                  while (@conn_state != CS_Disconnected) and confirm_rec
                    p log_mes+'send  confirm_rec='+confirm_rec
                    ssbuf << confirm_rec
                    confirm_rec = @confirm_queue.get_block_from_queue
                    if (not confirm_rec) or (ssbuf.bytesize+5>MaxSegSize)
                      add_send_segment(EC_Sync, true, ssbuf, ECC_Sync3_Confirm)
                      ssbuf = ''
                    end
                  end
                end

                # отправка сформированных сегментов и их удаление
                if (@conn_state != CS_Disconnected)
                  send_segment = @send_queue.get_block_from_queue
                  while (@conn_state != CS_Disconnected) and send_segment
                    #p log_mes+' send_segment='+send_segment.inspect
                    sscmd, sscode, ssbuf = send_segment
                    if ssbuf and (ssbuf.bytesize>0) and @s_encode
                      #ssbuf = PandoraGtk.recrypt(@skey, ssbuf, true, false)
                      #ssbuf = Base64.strict_encode64(@sbuf)
                    end
                    #p log_mes+'MAIN SEND: '+[@sindex, sscmd, sscode, ssbuf].inspect
                    if (sscmd != EC_Bye) or (sscode != ECC_Bye_Silent)
                      if not send_comm_and_data(@sindex, sscmd, sscode, ssbuf)
                        @conn_state = CS_Disconnected
                        p log_mes+'err send comm and buf'
                      end
                    else
                      p 'SILENT!!!!!!!!'
                    end
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
                while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
                and ((send_state & (CSF_Message | CSF_Messaging)) == 0) and (processed<$inquire_block_count) \
                and (inquirer_step<IS_Finished)
                  case inquirer_step
                    when IS_ResetMessage
                      # если что-то отправлено, но не получено, то повторить
                      mypanhash = Pandora::Crypto.current_user_or_key(true)
                      receiver = @skey[Pandora::Crypto::KV_Creator]
                      if (receiver.is_a? String) and (receiver.bytesize>0) \
                      and (((conn_mode & CM_Hunter) != 0) or (mypanhash != receiver))
                        filter = {'destination'=>receiver, 'state'=>1}
                        message_model.update({:state=>0}, nil, filter)
                      end
                      inquirer_step += 1
                    when IS_CreatorCheck
                      # если собеседник неизвестен, запросить анкету
                      creator = @skey[Pandora::Crypto::KV_Creator]
                      kind = Pandora::Utils.kind_from_panhash(creator)
                      res = PandoraModel.get_record_by_panhash(kind, creator, nil, @send_models, 'id')
                      p log_mes+'Whyer: CreatorCheck  creator='+creator.inspect
                      if not res
                        p log_mes+'Whyer: CreatorCheck  Request!'
                        set_request(creator, true)
                      end
                      inquirer_step += 1
                    when IS_NewsQuery
                      # запросить список новых панхэшей
                      pankinds = 1.chr + 11.chr
                      from_time = Time.now.to_i - 10*24*3600
                      #whyer = @rkey[Pandora::Crypto::KV_Creator]
                      #answerer = @skey[Pandora::Crypto::KV_Creator]
                      #trust=nil
                      #key=nil
                      #models=nil
                      #ph_list = []
                      #ph_list << PandoraModel.signed_records(whyer, from_time, pankinds, \
                      #  trust, key, models)
                      #ph_list << PandoraModel.public_records(whyer, trust, from_time, \
                      #  pankinds, models)
                      set_relations_query(pankinds, from_time, true)
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
                while (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
                and ((send_state & (CSF_Message | CSF_Messaging)) == 0) and (processed<$media_block_count) \
                and dialog and (not dialog.destroyed?) and (cannel<dialog.recv_media_queue.size) \
                and (inquirer_step>IS_ResetMessage)
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
                      #recv_media_chunk = Pandora::Utils.get_block_from_queue(dialog.recv_media_queue[cannel], $media_buf_size)
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
                if (@conn_state == CS_Connected) and (@stage>=ES_Exchange) \
                and (((send_state & CSF_Message)>0) or ((send_state & CSF_Messaging)>0))
                  fast_data = true
                  @send_state = (send_state & (~CSF_Message))
                  receiver = @skey[Pandora::Crypto::KV_Creator]
                  if @skey and receiver
                    filter = {'destination'=>receiver, 'state'=>0}
                    fields = 'id, creator, created, text'
                    sel = message_model.select(filter, false, fields, 'created', $mes_block_count)
                    if sel and (sel.size>0)
                      @send_state = (send_state | CSF_Messaging)
                      i = 0
                      while sel and (i<sel.size) and (processed<$mes_block_count) \
                      and (@conn_state == CS_Connected) \
                      and (@send_queue.single_read_state != Pandora::Utils::RoundQueue::QS_Full)
                        processed += 1
                        row = sel[i]
                        if add_send_segment(EC_Message, true, row)
                          id = row[0]
                          res = message_model.update({:state=>1}, nil, {:id=>id})
                          if not res
                            Pandora.logger.error  _('Updating state of sent message')+' id='+id.to_s
                          end
                        else
                          Pandora.logger.error  _('Adding message to send queue')+' id='+id.to_s
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
                and ((send_state & CSF_Message) == 0) and dialog and (not dialog.destroyed?) and dialog.room_id \
                and ((dialog.vid_button and (not dialog.vid_button.destroyed?) and dialog.vid_button.active?) \
                or (dialog.snd_button and (not dialog.snd_button.destroyed?) and dialog.snd_button.active?))
                  fast_data = true
                  #p 'packbuf '+cannel.to_s
                  pointer_ind = PandoraGtk.get_send_ptrind_by_room(dialog.room_id)
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
                      if not send_comm_and_data(sindex, mscmd, mscode, msbuf)
                        @conn_state = CS_Disconnected
                        p log_mes+' err send media'
                      end
                    else
                      cannel += 1
                    end
                  end
                end

          # проверка новых заявок на рыбалку
          fish_order = pool.fish_orders.get_block_from_queue(Pandora::Net::Pool::FishQueueSize, self)
          if fish_order
            p 'New fish order: '+fish_order.inspect
            tokey = @skey[Pandora::Crypto::KV_Panhash]
            if fish_order == tokey
                    Pandora.logger.debug  _('Fishing to')+': '+Pandora::Utils.bytes_to_hex(tokey)
                    add_send_segment(EC_Query, true, tokey, ECC_Query_Fish)
            end
          end

                #p '---@conn_state='+@conn_state.inspect
                #sleep 0.5

                if (socket and socket.closed?) or (@conn_state == CS_StopRead) \
                and (@confirm_queue.single_read_state == Pandora::Utils::RoundQueue::QS_Empty)
                  @conn_state = CS_Disconnected
                elsif (not fast_data)
                  sleep(0.02)
                #elsif conn_state == CS_Stoping
                #  add_send_segment(EC_Bye, true)
                end
                Thread.pass
              end

              p log_mes+"Цикл ОТПРАВКИ конец!!!   @conn_state="+@conn_state.inspect

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
              if socket
                if ((conn_mode & CM_Hunter) == 0)
                  Pandora.logger.info  _('Hunter disconnects')+': '+@host_ip
                else
                  Pandora.logger.info  _('Disconnected from listener')+': '+@host_ip
                end
              end
              @socket_thread.exit if @socket_thread
              @read_thread.exit if @read_thread
              if donor #and (not donor.destroyed?)
                p 'DONOR free!!!!'
                if donor.socket and (not donor.socket.closed?)
                  send_comm_and_data(@sindex, EC_Bye, ECC_Bye_NoAnswer, nil)
                end
                if fisher_lure
                  p 'free_out_lure fisher_lure='+fisher_lure.inspect
                  donor.free_out_lure_of_fisher(self, fisher_lure)
                else
                  p 'free_fish fish_lure='+fish_lure.inspect
                  donor.free_fish_of_in_lure(fish_lure)
                end
              end
              fishes.each_index do |i|
                free_fish_of_in_lure(i)
              end
              fishers.each do |val|
                fisher = nil
                in_lure = nil
                fisher, in_lure = val if val.is_a? Array
                fisher.free_fish_of_in_lure(in_lure) if (fisher and in_lure) #and (not fisher.destroyed?)
                #fisher.free_out_lure_of_fisher(self, i) if fish #and (not fish.destroyed?)
              end
            end

            need_connect = ((@conn_mode & CM_KeepHere) != 0) and (not (@socket.is_a? FalseClass))
            p 'NEED??? [need_connect, @conn_mode, @socket]='+[need_connect, @conn_mode, @socket].inspect

            if need_connect and (not @socket) and work_time and ((Time.now.to_i - work_time.to_i)<15)
              p 'sleep!'
              sleep(3.1+0.5*rand)
            end

            @conn_state = CS_Disconnected
            @socket = nil
            @donor  = nil

            attempt += 1
          end
          if dialog and (not dialog.destroyed?) #and (not dialog.online_button.destroyed?)
            dialog.set_session(self, false)
            #dialog.online_button.active = false
          else
            @dialog = nil
          end
          @send_thread = nil
          Pandora::Utils.play_mp3('offline')
        end
        #??
      end

    end

  end
end

#!/usr/bin/env python
# -*- coding: utf-8 -*-
# The Pandora gate. It allows to collect connections for one node
# RU: Шлюз Пандоры. Позволяет собирать соединения для одного узла
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

import termios, fcntl, sys, os, socket, threading, struct

# Preparation for key capturing
fd = sys.stdin.fileno()
oldterm = termios.tcgetattr(fd)
newattr = termios.tcgetattr(fd)
newattr[3] = newattr[3] & ~termios.ICANON & ~termios.ECHO
termios.tcsetattr(fd, termios.TCSANOW, newattr)
oldflags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, oldflags | os.O_NONBLOCK)

# Server settings
#TCP_IP = '94.242.204.250'
#TCP_PORT = 8080
TCP_IP = '127.0.0.1'
TCP_PORT = 5577
MAX_CONNECTIONS = 10

# Internal constants
MaxPackSize = 1500
MaxSegSize  = 1200
CommSize = 6
CommExtSize = 10

class ClientThread(threading.Thread):
  def __init__ (self, client, addr):
    self.client = client
    self.addr = addr
    self._stop = threading.Event()
    threading.Thread.__init__(self)

  def bytes2word(high_byte, low_byte):
    word = high_byte*256 + low_byte
    return word

  def word2bytes(word):
    low_byte = (segsign & 255)
    high_byte = ((segsign >> 8) & 255)
    return high_byte, low_byte

  def unpack_comm(self, comm):
    errcode = 0
    if len(comm) == CommSize:
      print(comm)
      index, cmd, code, segsign, crc8 = struct.unpack('!BBBHB', comm)
      #segsign = byte2word(segsign1, segsign2)
      print(index, cmd, code, segsign, crc8)
      crc8f = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
      if crc8 != crc8f:
        errcode = 1
    else:
      errcode = 2
    return index, cmd, code, segsign, errcode

  def unpack_comm_ext(comm):
    if len(comm) == CommExtSize:
      datasize, fullcrc32, segsize = struct.unpack('!IIH', comm)
    else:
      print('Ошибочная длина расширения команды')
    return datasize, fullcrc32, segsize

  LONG_SEG_SIGN   = 0xFFFF

  # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
  def send_comm_and_data(index, cmd, code, data=None):
    res = None
    if not data:
      data = ''
    datasize = data.bytesize
    if datasize <= MaxSegSize:
      segsign = datasize
      segsize = datasize
    else:
      segsign = LONG_SEG_SIGN
      segsize = MaxSegSize
    crc8 = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
    #segsign1, segsign2 = word2bytes(segsign)
    #comm = struct.pack('BBBBBB', index, cmd, code, segsign1, segsign2, crc8)
    comm = struct.pack('!BBBHB', index, cmd, code, segsign, crc8)
    print('comm=', comm.size)
    if index<255:
      index += 1
    else:
      index = 0
    buf = ''
    if datasize>0:
      if segsign == LONG_SEG_SIGN:
        fullcrc32 = binascii.crc32(data)
        # если пакетов много, то добавить еще 4+4+2= 10 байт
        comm = comm + struct.pack('!IIH', datasize, fullcrc32, segsize)
        buf = buf + data[0, segsize-1]
      else:
        buf = data
      segcrc32 = binascii.crc32(buf)
      # в конце всегда CRC сегмента - 4 байта
      buf = buf + struct.pack('!I', segcrc32)
    buf = comm + buf
    #if (not @media_send) and (cmd == EC_Media)
    #  @media_send = true
    #  socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0xA0)  # QoS (VoIP пакет)
    #  !socket.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0xA0)
    #  p '@media_send = true'
    #elsif @media_send and (cmd != EC_Media)
    #  @media_send = false
    #  socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0)
    #  !socket.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0)
    #  p '@media_send = false'
    #end
    try:
      if socket: #and (not socket.closed?):
        sended = socket.write(buf)
      else:
        sended = -1
    except: #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
      sended = -1

    if sended == buf.bytesize:
      res = index
    elif sended != -1:
      print('Не все данные отправлены ', sended)
    segindex = 0
    i = segsize
    while res and ((datasize-i)>0):
      segsize = datasize-i
      if segsize>MaxSegSize: segsize = MaxSegSize
      if segindex<0xFFFFFFFF:
        segindex += 1
      else:
        segindex = 0
      comm = struct.pack('!BIH', index, segindex, segsize)
      if index<255:
        index += 1
      else:
        index = 0
      buf = data[i, segsize]
      buf = buf + struct.pack('!I', binascii.crc32(buf))
      buf = comm + buf
      try:
        if socket: # and not socket.closed?:
          sended = socket.write(buf)
        else:
          sended = -1
      except: #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
        sended = -1
      if sended == buf.bytesize:
        res = index
        #p log_mes+'SEND_ADD: ('+buf+')'
      elif sended != -1:
        res = nil
        print('Не все данные отправлены2 ', sended.to_s)
      i += segsize
    return res

  ECC_Init_Hello       = 0
  ECC_Init_Puzzle      = 1
  ECC_Init_Phrase      = 2
  ECC_Init_Sign        = 3
  ECC_Init_Captcha     = 4
  ECC_Init_Answer      = 5

  ECC_Query0_Kinds      = 0
  ECC_Query255_AllChanges =255

  ECC_News0_Kinds       = 0

  ECC_Channel0_Open     = 0
  ECC_Channel1_Opened   = 1
  ECC_Channel2_Close    = 2
  ECC_Channel3_Closed   = 3
  ECC_Channel4_Fail     = 4

  ECC_Sync10_Encode     = 10

  ECC_More_NoRecord     = 1

  ECC_Bye_HelloError    = 0
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
  ST_Sign         = 5
  ST_Captcha      = 6
  ST_Greeting     = 7
  ST_Exchange     = 8

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
  IS_Finished      = 255

  # compose error command and add log message
  def err_scmd(mes=None, code=None, buf=None)
    self.scmd = EC_Bye
    self.scode = self.rcmd
    logmes = ''
    if code
      self.scode = code
      logmes = ' err=' + str(self.scode)
    logmes = '(rcmd=' + self.rcmd./to_s + '/' + self.rcode.to_s + ' stage=' + self.stage.to_s + logmes + ')'
    if mes and (mes.bytesize>0): logmes = mes+' '+logmes
    print('err_scmd: '+logmes)
    self.sbuf = buf
    if not self.sbuf: self.sbuf = logmes

  def run(self):
    processing = True
    client = self.client

    sindex = 0
    rindex = 0
    readmode = RM_Comm
    nextreadmode = RM_Comm
    waitlen = CommSize

    self.scmd = EC_More
    self.sbuf = ''
    rbuf = ''
    self.rcmd = EC_More
    self.rdata = ''
    last_scmd = scmd

    while processing:
      recieved = client.recv(MaxPackSize)
      print('Received: ', recieved)
      rbuf = rbuf + recieved

      processedlen = 0
      while (conn_state != CS_Disconnected) and (conn_state != CS_StopRead) \
      and (conn_state != CS_Stoping) and (rbuf.bytesize>=waitlen): #and (not socket.closed?)
        #p log_mes+'begin=['+rbuf+']  L='+rbuf.size.to_s+'  WL='+waitlen.to_s
        processedlen = waitlen
        nextreadmode = readmode

        # Определимся с данными по режиму чтения
        if readmode==RM_Comm
          comm = rbuf[0:processedlen-1]
          rindex, self.rcmd, self.rcode, rsegsign, errcode = self.unpack_comm(comm)
          print('index, cmd, code, segsign, errcode: ', index, cmd, code, segsign, errcode)
          if errcode == 0:
            print(' RM_Comm: ', rindex, rcmd, rcode, rsegsign)
            if rsegsign == LONG_SEG_SIGN:
              nextreadmode = RM_CommExt
              waitlen = CommExtSize
            elif rsegsign > 0:
              nextreadmode = RM_SegmentS
              waitlen = rsegsign+4  #+CRC32
              rdatasize, rsegsize = rsegsign
            end
          elif errcode == 1:
            err_scmd('Wrong CRC of recieved command', ECC_Bye_BadCommCRC)
          elif errcode == 2:
            err_scmd('Wrong length of recieved command', ECC_Bye_BadCommLen)
          else:
            err_scmd('Wrong recieved command', ECC_Bye_Unknown)
        elif readmode==RM_CommExt:
          comm = rbuf[0:processedlen-1]
          rdatasize, fullcrc32, rsegsize = unpack_comm_ext(comm)
          print(' RM_CommExt: rdatasize, fullcrc32, rsegsize ', rdatasize, fullcrc32, rsegsize)
          nextreadmode = RM_Segment1
          waitlen = rsegsize+4   #+CRC32
        elif readmode==RM_SegLenN:
          comm = rbuf[0:processedlen-1]
          rindex, rsegindex, rsegsize = struct.unpack('!BIH', comm)
          print(' RM_SegLenN: ', rindex, rsegindex, rsegsize)
          nextreadmode = RM_SegmentN
          waitlen = rsegsize+4   #+CRC32
        elif (readmode==RM_SegmentS) or (readmode==RM_Segment1) or (readmode==RM_SegmentN):
          print(' RM_SegLenX [mode, buf.len] ', readmode, len(rbuf))
          if (readmode==RM_Segment1) or (readmode==RM_SegmentN):
            nextreadmode = RM_SegLenN
            waitlen = 7    #index + segindex + rseglen (1+4+2)
          rsegcrc32 = struct.unpack('!I', rbuf[processedlen-5:processedlen-1])
          rseg = rbuf[0:processedlen-5)
          #p log_mes+'rseg=['+rseg+']'
          fsegcrc32 = binascii.crc32(rseg)
          if fsegcrc32 == rsegcrc32
            self.rdata = self.rdata + rseg
          else
            err_scmd('Wrong CRC of received segment', ECC_Bye_BadCRC)
          end
          #p log_mes+'RM_SegmentX: data['+rdata+']'+rdata.size.to_s+'/'+rdatasize.to_s
          if len(rdata) == rdatasize:
            nextreadmode = RM_Comm
            waitlen = CommSize
          elif rdata.bytesize > rdatasize:
            err_scmd('Too much received data', ECC_Bye_DataTooLong)

        # Очистим буфер от определившихся данных
        rbuf = rbuf[processedlen:]
        if (self.scmd != EC_Bye) and (self.scmd != EC_Wait): self.scmd = EC_Data
        # Обработаем поступившие команды и блоки данных
        rdata0 = rdata
        if (self.scmd != EC_Bye) and (self.scmd != EC_Wait) and (nextreadmode == RM_Comm):
          print('-->>>> before accept: [rcmd, rcode, rdata.size]=', rcmd, rcode, len(rdata))
          #if self.rdata and (len(self.rdata)>0) and @r_encode
            #@rdata = PandoraGUI.recrypt(@rkey, @rdata, false, true)
            #@rdata = Base64.strict_decode64(@rdata)
            #p log_mes+'::: decode rdata.size='+rdata.size.to_s
          #end

          #rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = \
          accept_segment #(rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd)

          if not self.rdata: self.rdata = ''
          if not self.sbuf: self.sbuf = ''
          #p log_mes+'after accept ==>>>: [scmd, scode, sbuf.size]='+[scmd, scode, @sbuf.size].inspect
          #p log_mes+'accept_request After='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect

        if scmd != EC_Data:
          #@sbuf = '' if scmd == EC_Bye
          #p log_mes+'add to queue [scmd, scode, sbuf]='+[scmd, scode, @sbuf].inspect
          print('recv/send: =', rcmd, rcode, rdata0.bytesize, '/', scmd, scode, @sbuf)
          #while PandoraGUI.get_queue_state(@send_queue) == QS_Full do
          #  p log_mes+'get_queue_state.MAIN = '+PandoraGUI.get_queue_state(@send_queue).inspect
          #  Thread.pass
          #end
          res = PandoraGUI.add_block_to_queue(@send_queue, [scmd, scode, @sbuf])
          if not res
            log_message(LM_Error, 'Error while adding segment to queue')
            conn_state == CS_Stoping
          end
          last_scmd = scmd
          @sbuf = ''
        readmode = nextreadmode
    if conn_state == CS_Stoping
      conn_state = CS_StopRead

    processing = False
    client.close()
    print 'Closed connection: ', self.addr [ 0 ]


class AcceptThread(threading.Thread):
  def __init__ (self, a_server):
    self.server = a_server
    self.listening = True
    self.threads = []
    threading.Thread.__init__(self)

  def run (self):
    while self.listening:
      try:
        client, addr = self.server.accept()
        print('Connect from: ', addr)
        client_tread = ClientThread(client, addr)
        self.threads.append(client_tread)
        client_tread.start()
      except IOError: pass

  def stop (self):
    print('Stopping client threads...')
    for thread in self.threads:
      if thread.isAlive():
        try:
            thread._Thread__stop()
        except:
            print(str(thread.getName()) + ' could not be terminated')
    print('Done.')
    self.listening = False



try:
  # Start server socket
  server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
  server.setblocking(0)
  server.bind((TCP_IP, TCP_PORT))
  server.listen(MAX_CONNECTIONS)

  print('Listening at: ', server.getsockname())
  listener = AcceptThread(server)
  listener.start()
  print('Press Q to exit...')
  working = True
  while working:
    try:
      c = sys.stdin.read(1)
      if (c=='q') or (c=='Q') or (c=='x') or (c=='X'):
        working = False
    except IOError: pass
  print('Stop listen.')
  listener.stop()
  server.shutdown(1)
  server.close()
finally:
  termios.tcsetattr(fd, termios.TCSAFLUSH, oldterm)
  fcntl.fcntl(fd, fcntl.F_SETFL, oldflags)
  sys.exit()

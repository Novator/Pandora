#!/usr/bin/env python
# -*- coding: utf-8 -*-
# The Pandora gate. It allows to collect connections for one node
# RU: Шлюз Пандоры. Позволяет собирать соединения для одного узла
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

import time, termios, fcntl, sys, os, socket, threading, struct, binascii, time, hashlib

# Server settings
TCP_IP = '127.0.0.1'
TCP_PORT = 5577
#LOG_FILE_NAME = ''
LOG_FILE_NAME = './pangate.log'
MAX_CONNECTIONS = 10
PASSWORD_HASH = hashlib.sha256('1234567890').digest()
OWNER_KEY_PANHASH = 'dd032ec783d34331de1d39006fc851d5cf4346bfc8cc'.decode('hex')

ROOT_PATH = os.path.abspath('.')
KEEPALIVE = 1 #(on/off)
KEEPIDLE = 5  #(after, sec)
KEEPINTVL = 1 #(every, sec)
KEEPCNT = 4   #(count)

# Internal constants
MaxPackSize = 1500
MaxSegSize  = 1200
CommSize = 6
CommExtSize = 10

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
EC_Line      = 8     # Данные канала двух рыбаков
EC_Sync      = 9     # Последняя команда в серии, или индикация "живости"
EC_Wait      = 254   # Временно недоступен
EC_Bye       = 255   # Рассоединение
EC_Data      = 256   # Ждем данные

ECC_Init_Hello       = 0
ECC_Init_Puzzle      = 1
ECC_Init_Phrase      = 2
ECC_Init_Sign        = 3
ECC_Init_Captcha     = 4
ECC_Init_Simple      = 5
ECC_Init_Answer      = 6

ECC_Query0_Kinds      = 0
ECC_Query255_AllChanges = 255

ECC_News0_Kinds       = 0

ECC_Channel0_Open     = 0
ECC_Channel1_Opened   = 1
ECC_Channel2_Close    = 2
ECC_Channel3_Closed   = 3
ECC_Channel4_Fail     = 4

ECC_Sync10_Encode     = 10

ECC_More_NoRecord     = 1

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
CM_Hunter       = 1  #охотник (иначе, слушатель)

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

LONG_SEG_SIGN   = 0xFFFF

logfile = None

def logmes(mes, show=True, addr=None):
  if show: print(mes)
  global logfile
  if (not logfile) and (logfile != False):
    if LOG_FILE_NAME and (len(LOG_FILE_NAME)>0):
      filename = LOG_FILE_NAME
      if (len(filename)>1) and (filename[0:2]=='./') and ROOT_PATH and (len(ROOT_PATH)>0):
        filename = ROOT_PATH + filename[1:]
      filename = os.path.abspath(filename)
      try:
        logfile = open(filename, 'a')
        print('Открыт log-файл: '+filename)
      except:
        logfile = False
        print('Не могу открыть log-файл: '+filename)
    else:
      logfile = False
      print('Log-файл отключен.')
  if logfile:
    timestr = time.strftime('%Y.%m.%d %H:%M:%S')
    addr = ''
    if addr: addr = ' '+str(addr)
    logfile.write(timestr+'  '+str(mes)+addr+'\n')

def closelog():
  global logfile
  if logfile:
    logfile.close()

def list_set(vec, ind, val):
  if ind >= len(vec):
    vec.extend([None]*(ind-len(vec)+1))
  vec[ind] = val

class ClientThread(threading.Thread):
  def __init__ (self, pool, client, addr):
    self.client = client
    self.addr = addr
    self._stop = threading.Event()
    self.pool = pool
    self.srckey = None
    self.authkey = None
    self.fishers = []
    threading.Thread.__init__(self)

  def logmes(self, mes, show=True):
    logmes(mes, show, self.addr[0])

  def unpack_comm(self, comm):
    print('unpack_comm self, comm, len(comm) ', self, comm, len(comm))
    errcode = 0
    index, cmd, code, segsign = None, None, None, None
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
      logmes('Ошибочная длина расширения команды')
    return datasize, fullcrc32, segsize

  # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
  def send_comm_and_data(self, index, cmd, code, data=None, client=None):
    res = None
    if not client:
      client = self.client
    if not data:
      data = ''
    datasize = len(data)
    segsign, segdata, segsize = datasize, datasize, datasize
    if datasize>0:
      if cmd != EC_Media:
        segsize += 4           #for crc32
        segsign = segsize
      if segsize > MaxSegSize:
        segsign = LONG_SEG_SIGN
        segsize = MaxSegSize
        if cmd == EC_Media:
          segdata = segsize
        else:
          segdata = segsize-4  #for crc32
    crc8 = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
    comm = struct.pack('!BBBHB', index, cmd, code, segsign, crc8)
    print('>send comm/data=', comm, len(comm), data)
    if index<255:
      index += 1
    else:
      index = 0
    buf = ''
    if datasize>0:
      if segsign == LONG_SEG_SIGN:
        # если пакетов много, то добавить еще 4+4+2= 10 байт
        fullcrc32 = 0
        if cmd != EC_Media: fullcrc32 = binascii.crc32(data)
        comm = comm + struct.pack('!IiH', datasize, fullcrc32, segsize)
        buf = data[0: segdata]
      else:
        buf = data
      if cmd != EC_Media:
        segcrc32 = binascii.crc32(buf)
        buf = buf + struct.pack('!i', segcrc32)
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
      if client: #and (not socket.closed?):
        sended = client.send(buf)
      else:
        sended = -1
    except: #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
      sended = -1
    if sended == len(buf):
      res = index
    elif sended != -1:
      self.logmes('Не все данные отправлены '+str(sended))
    segindex = 0
    i = segsize
    while res and ((datasize-i)>0):
      segdata = datasize-i
      segsize = segdata
      if cmd != EC_Media:
        segsize += 4           #for crc32
      if segsize > MaxSegSize:
        segsize = MaxSegSize
        if cmd == EC_Media:
          segdata = segsize
        else:
          segdata = segsize-4  #for crc32

      if segindex<0xFFFFFFFF:
        segindex += 1
      else:
        segindex = 0
      comm = struct.pack('!BIH', index, segindex, segsize)
      if index<255:
        index += 1
      else:
        index = 0

      buf = data[i: segdata]
      if cmd != EC_Media:
        segcrc32 = binascii.crc32(buf)
        buf = buf + struct.pack('!I', segcrc32)
      buf = comm + buf
      try:
        if client: # and not socket.closed?:
          sended = client.send(buf)
        else:
          sended = -1
      except: #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
        sended = -1
      if sended == len(buf):
        res = index
        #p log_mes+'SEND_ADD: ('+buf+')'
      elif sended != -1:
        res = nil
        self.logmes('Не все данные отправлены2 '+str(sended))
      i += segdata
    return res

  # compose error command and add log message
  def err_scmd(self, mes=None, code=None, buf=None):
    self.scmd = EC_Bye
    if code:
      self.scode = code
    else:
      self.scode = self.rcmd
    if buf:
      self.sbuf = buf
    elif buf==False:
      self.sbuf = None
    else:
      fullmes = '(rcmd=' + str(self.rcmd) + '/' + str(self.rcode) + ' stage=' + str(self.stage) + ')'
      if mes and (len(mes)>0): fullmes = mes+' '+fullmes
      self.sbuf = fullmes
      mesadd = ''
      if code: mesadd = ' err=' + str(code)
      self.logmes('Our error: '+str(fullmes+mesadd))

  def get_hole_for_fisher(self, fisher):
    hole = None
    size = len(self.fishers)
    if size>0:
      first_nil_hole = None
      i = 0
      while (i<size) and (not hole):
        if self.fishers[i]:
          if fisher == self.fishers[i]:
            hole = i
        else:
          first_nil_hole = i
        i += 1
      if not hole:
        if first_nil_hole:
          hole = first_nil_hole
        elif size<256:
          hole = size
        if hole: list_set(self.fishers, hole, fisher)
    else:
      hole = 0
      list_set(self.fishers, hole, fisher)
    return hole

  def get_fisher_by_hole(self, hole):
    fisher = None
    if hole: fisher = self.fishers[hole]
    return fisher

  def close_hole(self, hole):
    if hole: self.fishers[hole] = None

  def close_hole_of_fisher(self, fisher):
    for hole in range(len(self.fishers)):
      if self.fishers[hole] == fisher:
        self.fishers[hole] = None

  def resend_to_fisher_hole(self, fisher, hole):
    if fisher and (hole != None):
      print('FISHING!', fisher, hole)
      comm = struct.pack('!BB', self.rcmd, self.rcode)
      data = comm + self.rdata
      self.sindex = self.send_comm_and_data(self.sindex, EC_Line, hole, data, fisher.client)

  # Accept received segment
  # RU: Принять полученный сегмент
  def accept_segment(self):
    print('accept_segment:  self.rcmd, self.rcode, self.stage', self.rcmd, self.rcode, self.stage)
    if (self.rcmd==EC_Init):
      if (self.rcode==ECC_Init_Hello) and (self.stage==ST_Protocol):
        print('self.rdata: ', self.rdata)
        if self.pool.collector:
          hole = self.pool.collector.get_hole_for_fisher(self)
          print('-------------------hole', hole)
          if hole==None:
            self.err_scmd('Temporary error')
          else:
            self.resend_to_fisher_hole(self.pool.collector, hole)
        else:
          i = self.rdata.find('mykey')
          if i>0:
            self.srckey = self.rdata[i+7: i+7+22]
            print('self.srckey', self.srckey, len(self.srckey), len(OWNER_KEY_PANHASH))
            if self.srckey == OWNER_KEY_PANHASH:
              self.scmd = EC_Init
              self.scode = ECC_Init_Simple
              self.sphrase = str(os.urandom(256))
              self.sbuf = self.sphrase
            else:
              self.err_scmd('Owner is offline')
          else:
            self.err_scmd('Bad hello')
      elif (self.rcode==ECC_Init_Answer) and (self.stage==ST_Protocol):
        sanswer = self.rdata
        fanswer = hashlib.sha256(self.sphrase+PASSWORD_HASH).digest()
        print(self.sphrase, PASSWORD_HASH, fanswer)
        if sanswer == fanswer:
          if self.pool.collector:
            self.err_scmd('Another collector is active')
          else:
            self.pool.collector = self
            self.authkey = self.srckey
            self.logmes('Collector seted.')
        else:
          self.err_scmd('Password hash is wrong')
      else:
        self.err_scmd('Wrong stage for rcode')
    elif (self.rcmd==EC_Bye):
      if self.rcode != ECC_Bye_Exit:
        mes = self.rdata
        if not mes: mes = ''
        self.logmes('Error at other side ErrCode='+str(self.rcode)+' "'+mes+'"')
      self.err_scmd(None, ECC_Bye_Exit, False)
      self.conn_state = CS_Stoping
    else:
      self.err_scmd('Unknown command')
      self.conn_state = CS_Stoping

  def run(self):
    self.sindex = 0
    rindex = 0
    readmode = RM_Comm
    nextreadmode = RM_Comm
    waitlen = CommSize
    rdatasize = 0
    fullcrc32 = None
    rdatasize = None

    self.stage = ST_Protocol
    self.scmd = EC_Sync
    self.scode = 0
    self.sbuf = ''
    rbuf = ''
    self.rcmd = EC_Sync
    self.rcode = 0
    self.rdata = ''
    last_scmd = self.scmd
    self.conn_state = CS_Connected
    rdatasize = 0
    self.sphrase = None

    while (self.conn_state != CS_StopRead) and (self.conn_state != CS_Disconnected):
      try:
        recieved = self.client.recv(MaxPackSize)
        print('recieved', recieved)
        if (not recieved) or (recieved==''):
          self.conn_state = CS_StopRead
        rbuf = rbuf + recieved
      except:
        self.conn_state = CS_StopRead

      processedlen = 0
      while (self.conn_state == CS_Connected) and (len(rbuf)>=waitlen): #and (not socket.closed?)
        print('==rbuf len waitlen readmode: ', rbuf, len(rbuf), waitlen, readmode)
        processedlen = waitlen
        nextreadmode = readmode

        # Определимся с данными по режиму чтения
        if readmode==RM_Comm:
          fullcrc32 = None
          rdatasize = None
          comm = rbuf[0: processedlen]
          rindex, self.rcmd, self.rcode, rsegsign, errcode = self.unpack_comm(comm)
          print(' RM_Comm: rindex, rcmd, rcode, segsign, errcode: ', rindex, self.rcmd, self.rcode, rsegsign, errcode)
          if errcode == 0:
            if rsegsign == LONG_SEG_SIGN:
              nextreadmode = RM_CommExt
              waitlen = CommExtSize
            elif rsegsign > 0:
              nextreadmode = RM_SegmentS
              waitlen, rdatasize = rsegsign, rsegsign
              if (self.rcmd != EC_Media): rdatasize -=4
          elif errcode == 1:
            self.err_scmd('Wrong CRC of recieved command', ECC_Bye_BadCommCRC)
          elif errcode == 2:
            self.err_scmd('Wrong length of recieved command', ECC_Bye_BadCommLen)
          else:
            self.err_scmd('Wrong recieved command', ECC_Bye_Unknown)
        elif readmode==RM_CommExt:
          comm = rbuf[0: processedlen]
          rdatasize, fullcrc32, rsegsize = unpack_comm_ext(comm)
          print(' RM_CommExt: rdatasize, fullcrc32, rsegsize ', rdatasize, fullcrc32, rsegsize)
          nextreadmode = RM_Segment1
          waitlen = rsegsize
        elif readmode==RM_SegLenN:
          comm = rbuf[0: processedlen]
          rindex, rsegindex, rsegsize = struct.unpack('!BIH', comm)
          print(' RM_SegLenN: ', rindex, rsegindex, rsegsize)
          nextreadmode = RM_SegmentN
          waitlen = rsegsize
        elif (readmode==RM_SegmentS) or (readmode==RM_Segment1) or (readmode==RM_SegmentN):
          print(' RM_SegLen? [mode, buf.len] ', readmode, len(rbuf))
          if (readmode==RM_Segment1) or (readmode==RM_SegmentN):
            nextreadmode = RM_SegLenN
            waitlen = 7    #index + segindex + rseglen (1+4+2)
          if self.rcmd == EC_Media:
            self.rdata << rbuf[0, processedlen]
          else:
            rseg = rbuf[0: processedlen-4]
            print('rseg',rseg)
            rsegcrc32str = rbuf[processedlen-4: processedlen]
            print('rsegcrc32str=',rsegcrc32str,len(rsegcrc32str))
            rsegcrc32 = struct.unpack('!i', rsegcrc32str)[0]
            fsegcrc32 = binascii.crc32(rseg)
            if fsegcrc32 == rsegcrc32:
              self.rdata = self.rdata + rseg
              if fullcrc32:
                if fullcrc32 != binascii.crc32(self.rdta):
                  self.err_scmd('Wrong CRC of received block', ECC_Bye_BadCRC)
            else:
              self.err_scmd('Wrong CRC of received segment', ECC_Bye_BadCRC)
          print('RM_Segment?: data', self.rdata, len(self.rdata), rdatasize)

          if len(self.rdata) == rdatasize:
            nextreadmode = RM_Comm
            waitlen = CommSize
          elif len(self.rdata) > rdatasize:
            self.err_scmd('Too match received data ('+rdata.bytesize.to_s+'>'+rdatasize.to_s+')', \
              ECC_Bye_DataTooLong)

        # Очистим буфер от определившихся данных
        rbuf = rbuf[processedlen:]
        if (self.scmd != EC_Bye) and (self.scmd != EC_Wait): self.scmd = EC_Data
        # Обработаем поступившие команды и блоки данных
        rdata0 = self.rdata
        if (self.scmd != EC_Bye) and (self.scmd != EC_Wait) and (nextreadmode == RM_Comm):
          print('-->>>> before accept: [rcmd, rcode, rdata.size]=', self.rcmd, self.rcode, len(self.rdata))
          #if self.rdata and (len(self.rdata)>0) and @r_encode
            #@rdata = PandoraGUI.recrypt(@rkey, @rdata, false, true)
            #@rdata = Base64.strict_decode64(@rdata)
            #p log_mes+'::: decode rdata.size='+rdata.size.to_s
          #end

          #rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = \
          self.accept_segment() #(rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd)

          self.rdata = ''
          if not self.sbuf: self.sbuf = ''
          print('after accept ==>>>: [scmd, scode, sbuf.size]=', self.scmd, self.scode, len(self.sbuf))
          #p log_mes+'accept_request After='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect

        if self.scmd != EC_Data:
          #@sbuf = '' if scmd == EC_Bye
          #p log_mes+'add to queue [scmd, scode, sbuf]='+[scmd, scode, @sbuf].inspect
          print('recv/send: =', self.rcmd, self.rcode, len(rdata0), '/', self.scmd, self.scode, self.sbuf)
          #while PandoraGUI.get_queue_state(@send_queue) == QS_Full do
          #  p log_mes+'get_queue_state.MAIN = '+PandoraGUI.get_queue_state(@send_queue).inspect
          #  Thread.pass
          #end
          #res = PandoraGUI.add_block_to_queue(@send_queue, [scmd, scode, @sbuf])
          self.sindex = self.send_comm_and_data(self.sindex, self.scmd, self.scode, self.sbuf)
          if not self.sindex:
            self.logmes('Error while sending segment [scmd, scode, len(sbuf)]'+str(self.scmd, self.scode, len(self.sbuf)))
            self.conn_state == CS_Stoping
          last_scmd = self.scmd
          self.sbuf = ''
        print('self.conn_state: ', self.conn_state)
        readmode = nextreadmode
      if self.conn_state == CS_Stoping:
        self.conn_state = CS_StopRead
      print('self.conn_state2: ', self.conn_state)
      time.sleep(0.2)

    print('FINISH')
    self.client.close()
    self.conn_state = CS_Disconnected
    addrstr = str(self.addr[0])+':'+str(self.addr[1])
    for fisher in self.fishers:
      fisher.close_hole_of_fisher(self)
    if self==self.pool.collector:
      self.pool.collector = None
      self.logmes('Colleactor disconnected: '+addrstr)
    else:
      self.logmes('Client disconnected: '+addrstr)


class PoolThread(threading.Thread):
  def __init__ (self):
    self.threads = []
    self.listener  = None
    self.collector = None
    threading.Thread.__init__(self)

  def get_fish_sockets(self, fisher_socket, fish_key):
    sockets = None
    for thread in self.threads:
      if thread.authkey and (thread.authkey==fish_key) and thread.client and (thread.client != fisher_socket):
        if not sockets: sockets = []
        if not thread.client in sockets:
          sockets.append(thread.client)
    return sockets

  def stop_clients(self):
    print('Stopping client threads...')
    for thread in self.threads:
      if thread.isAlive():
        try:
          thread._Thread__stop()
        except:
          print(str(thread.getName()) + ' could not be terminated')
    print('Done.')


class ListenerThread(threading.Thread):
  def __init__ (self, a_server, a_pool):
    self.server = a_server
    self.pool = a_pool
    self.listening = True
    threading.Thread.__init__(self)

  def set_keepalive(self, client):
    client.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, KEEPALIVE)
    client.setsockopt(socket.SOL_TCP, socket.TCP_KEEPIDLE, KEEPIDLE)
    client.setsockopt(socket.SOL_TCP, socket.TCP_KEEPINTVL, KEEPINTVL)
    client.setsockopt(socket.SOL_TCP, socket.TCP_KEEPCNT, KEEPCNT)

  def run(self):
    while self.listening:
      try:
        client, addr = self.server.accept()
        logmes('Connect from: '+str(addr[0])+':'+str(addr[1]))
        self.set_keepalive(client)
        client_tread = ClientThread(self.pool, client, addr)
        self.pool.threads.append(client_tread)
        client_tread.start()
      except IOError: pass
    print('Finish server cicle.')


# ===MAIN===
# Preparation for key capturing
fd = sys.stdin.fileno()
oldterm = termios.tcgetattr(fd)
newattr = termios.tcgetattr(fd)
newattr[3] = newattr[3] & ~termios.ICANON & ~termios.ECHO
termios.tcsetattr(fd, termios.TCSANOW, newattr)
oldflags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, oldflags | os.O_NONBLOCK)

try:
  print('The Pandora gate.')

  # Start server socket
  try:
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    #server.setblocking(0)
    server.bind((TCP_IP, TCP_PORT))
    server.listen(MAX_CONNECTIONS)
  except:
    server = None

  if server:
    saddr = server.getsockname()
    logmes('Listening at: '+str(saddr[0])+':'+str(saddr[1]))

    pool = PoolThread()
    pool.start()
    print('Pool runed.')

    listener = ListenerThread(server, pool)
    pool.listener = listener
    listener.start()
    print('Working thread is active...')
    print('Press Q to stop server.')
    working = True
    while working:
      time.sleep(0.5)  # prevent overload cpu
      try:
        c = sys.stdin.read(1)
        if (c=='q') or (c=='Q') or (c=='x') or (c=='X') or (ord(c)==185) or (ord(c)==153):
          working = False
      except IOError: pass
    logmes('Stop keyborad loop.')
    listener.listening = False
    print('New clients off.')
    server.shutdown(1)
    server.close()
    print('Stop server.')
    pool.stop_clients()
    if listener.isAlive():
      try:
        listener._Thread__stop()
      except:
        print('Could not terminated listen thread '+str(listener.getName()))
    if pool.isAlive():
      try:
        pool._Thread__stop()
      except:
        print('Could not terminated pool thread '+str(pool.getName()))
    logmes('Stop listen thread.')
finally:
  termios.tcsetattr(fd, termios.TCSAFLUSH, oldterm)
  fcntl.fcntl(fd, fcntl.F_SETFL, oldflags)
  closelog
  sys.exit()

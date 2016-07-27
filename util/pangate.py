#!/usr/bin/env python
# -*- coding: utf-8 -*-
# The Pandora Gate collects connections for owner of gate
# RU: Шлюз Пандоры собирает соединения для владельца шлюза
#
# This program is distributed under the GNU GPLv2
# RU: Эта программа распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk, P2P social network Pandora, free software
# RU: 2012 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО

import time, datetime, termios, fcntl, sys, os, socket, threading, struct, \
  binascii, hashlib, ConfigParser


# ====================================================================
# Setup functions
# RU: Настроечные функции

# ConfigParser object
# RU: Объект ConfigParser
config = None

# Get parameter value from config
# RU: Взять значение параметра из конфига
def getparam(sect, name, akind='str'):
  global config
  res = None
  try:
    if akind=='int':
      res = config.getint(sect, name)
    elif akind=='bool':
      res = config.getboolean(sect, name)
    elif akind=='real':
      res = config.getfloat(sect, name)
    else:
      res = config.get(sect, name)
  except:
    res = None
  return res

# Open config file and read parameters
# RU: Открыть конфиг и прочитать параметры
config = ConfigParser.SafeConfigParser()
res = config.read('./pangate.conf')
if len(res):
  host = getparam('network', 'host')
  port = getparam('network', 'port', 'int')
  max_conn = getparam('network', 'max_conn', 'int')
  peer_media_first = getparam('network', 'peer_media_first', 'bool')
  password = getparam('owner', 'password')
  keyhash = getparam('owner', 'keyhash')
  log_prefix = getparam('logfile', 'prefix')
  max_size = getparam('logfile', 'max_size', 'int')
  flush_interval = getparam('logfile', 'flush_interval', 'int')

# Set default config values
# RU: Задать параметры по умолчанию
if not host: host = '0.0.0.0'
if not port: port = 5577
if not log_prefix: log_prefix = './pangate'
if not max_conn: max_conn = 10
if not password: password = '12345'
if not peer_media_first: peer_media_first = False
if not flush_interval: flush_interval = 2

# Calc password hash
# RU: Высчитать хэш пароля
password = hashlib.sha256(password).digest()
# Decode hex panhash of owner key
# RU: Декодировать hex панхэша ключа владельца
if keyhash: keyhash = keyhash.decode('hex')

# Current path
# RU: Текущий путь
ROOT_PATH = os.path.abspath('.')


# ====================================================================
# Log functions
# RU: Функции логирования

logfile = None
flush_time = None
curlogindex = None
curlogsize = None

# Get filename of log by index
# RU: Взять имя файла лога по индексу
def logname_by_index(index=1):
  global log_prefix
  filename = log_prefix
  if (len(filename)>1) and (filename[0:2]=='./') and ROOT_PATH and (len(ROOT_PATH)>0):
    filename = ROOT_PATH + filename[1:]
  filename = os.path.abspath(filename+str(index)+'.log')
  return filename

# Close active log file
# RU: Закрыть активный лог файл
def closelog():
  global logfile
  if logfile:
    logfile.close()
    logfile = None

# Write string to log file (and screen)
# RU: Записать строку в лог файл (и на экран)
def logmes(mes, show=True, addr=None):
  global logfile, flush_time, curlogindex, curlogsize, log_prefix, max_size, flush_interval
  if (not logfile) and (logfile != False):
    if log_prefix and (len(log_prefix)>0):
      try:
        s1 = os.path.getsize(logname_by_index(1))
      except:
        s1 = None
      try:
        s2 = os.path.getsize(logname_by_index(2))
      except:
        s2 = None
      curlogindex = 1
      curlogsize = s1
      if (s1 and ((s1>=max_size) or (s2 and (s2<s1)))):
        curlogindex = 2
        curlogsize = s2
      try:
        filename = logname_by_index(curlogindex)
        logfile = open(filename, 'a')
        if not curlogsize: curlogsize = 0
        print('Logging to file: '+filename)
      except:
        logfile = False
        print('Cannot open log-file: '+filename)
    else:
      logfile = False
      print('Log-file is off.')
  if logfile or show:
    cur_time = datetime.datetime.now()
    time_str = cur_time.strftime('%Y.%m.%d %H:%M:%S')
    mes = str(mes)
    if show: print('Log'+time_str[-11:]+': '+mes)
    if logfile:
      addr = ''
      if addr: addr = ' '+str(addr)
      logline = time_str+': '+mes+addr+'\n'
      curlogsize += len(logline)
      if curlogsize >= max_size:
        curlogsize = 0
        if curlogindex == 1:
          curlogindex = 2
        else:
          curlogindex = 1
        try:
          filename = logname_by_index(curlogindex)
          closelog()
          logfile = open(filename, 'w')
          print('Change logging to file: '+filename)
        except:
          logfile = False
          print('Cannot change log-file: '+filename)
          return
      logfile.write(logline)
      if (not flush_time) or (cur_time >= (flush_time + datetime.timedelta(0, flush_interval))):
        logfile.flush()
        sync_time = cur_time


# ====================================================================
# Utilites functions
# RU: Вспомогательные функции

# Convert big integer to string of bytes
# RU: Преобразует большое целое в строку байт
def bigint_to_bytes(bigint, maxsize=None):
  res = ''
  count = 0
  while True:
    res = struct.pack('B', bigint & 255) + res
    bigint = (bigint >> 8)
    count += 1
    if (bigint==0) or (maxsize and (count>=maxsize)):
      return res

# Convert string of bytes to integer
# RU: Преобразует строку байт в целое
def bytes_to_int(buf):
  res = 0
  i = len(buf)
  for c in buf:
    i -= 1
    res += (ord(c) << 8*i)
  return res

# Fill string by zeros from left to defined size
# RU: Заполнить строку нулями слева до нужного размера
def fill_zeros_from_left(data, size):
  l = len(data)
  if l<size:
    data = struct.pack('B', 0)*(size-l) + data
  return data


# ====================================================================
# PSON format functions
# RU: Функции для работы с форматом PSON

# Codes of data types in PSON
# RU: Коды типов данных в PSON
PT_Int   = 0
PT_Str   = 1
PT_Bool  = 2
PT_Time  = 3
PT_Array = 4
PT_Hash  = 5
PT_Sym   = 6
PT_Real  = 7
# 8..14 - reserved for other types
PT_Nil   = 15
PT_Negative = 16

# Encode data type and size to PSON kind and count of size in bytes (1..8)-1
# RU: Кодирует тип данных и размер в тип PSON и число байт размера
def encode_pson_kind(basekind, size):
  count = 0
  neg = 0
  if size<0:
    neg = PT_Negative
    size = -size
  while (size>0) and (count<8):
    size = (size >> 8)
    count +=1
  if count >= 8:
    print('[encode_pan_kind] Too big int='+size.to_s)
    count = 7
  return [basekind ^ neg ^ (count << 5), count, (neg>0)]

# Decode PSON kind to data kind and count of size in bytes (1..8)-1
# RU: Раскодирует тип PSON в тип данных и число байт размера
def decode_pson_kind(kind):
  basekind = kind & 0xF
  negative = ((kind & PT_Negative)>0)
  count = (kind >> 5)
  return [basekind, count, negative]

# Convert python object to PSON (Pandora simple object notation)
# RU: Конвертирует объект питон в PSON
def pythonobj_to_pson(pythonobj):
  kind = PT_Nil
  count = 0
  data = '' #!!!data = AsciiString.new
  elem_size = None
  if isinstance(pythonobj, str):
    data += pythonobj #!!!AsciiString.new(pythonobj)
    elem_size = len(data) #!!!data.bytesize
    kind, count, neg = encode_pson_kind(PT_Str, elem_size)
  elif isinstance(pythonobj, bool):
    kind = PT_Bool
    print('Boool1 kind='+str(kind))
    if not pythonobj: kind = kind ^ PT_Negative
    print('Boool2 kind='+str(kind))
  elif isinstance(pythonobj, int):
    kind, count, neg = encode_pson_kind(PT_Int, pythonobj)
    if neg: pythonobj = -pythonobj
    data += bigint_to_bytes(pythonobj, 8)
  #!!!elif isinstance(pythonobj, Symbol):
  #  data << AsciiString.new(pythonobj.to_s)
  #  elem_size = data.bytesize
  #  kind, count, neg = encode_pson_kind(PT_Sym, elem_size)
  elif isinstance(pythonobj, datetime.datetime):
    pythonobj = int(pythonobj)
    kind, count, neg = encode_pson_kind(PT_Time, pythonobj)
    if neg: pythonobj = -pythonobj
    data << PandoraUtils.bigint_to_bytes(pythonobj)
  elif isinstance(pythonobj, float):
    data += struct.pack('d', pythonobj)
    elem_size = len(data)
    kind, count, neg = encode_pson_kind(PT_Real, elem_size)
  elif isinstance(pythonobj, (list, tuple)):
    for a in pythonobj:
      data += pythonobj_to_pson(a)
    elem_size = len(pythonobj)
    kind, count, neg = encode_pson_kind(PT_Array, elem_size)
  elif isinstance(pythonobj, dict):
    #!!!pythonobj = pythonobj.sort_by {|k,v| k.to_s}
    elem_size = 0
    for key in pythonobj:
      data += pythonobj_to_pson(key) + pythonobj_to_pson(pythonobj.get(key, 0))
      elem_size += 1
    kind, count, neg = encode_pson_kind(PT_Hash, elem_size)
  elif pythonobj is None:
    kind = PT_Nil
  else:
    print('Error! pythonobj_to_pson: illegal ruby class ['+pythonobj+']')
  res = ''   #res = AsciiString.new
  res += struct.pack('!B', kind)  #res << [kind].pack('C')
  if isinstance(data, str) and (count>0):
    #!!!data = AsciiString.new(data)
    if elem_size:
      if (elem_size==len(data)) or isinstance(pythonobj, (list,dict,tuple)):
        #!!!res += PandoraUtils.fill_zeros_from_left( \
        #  PandoraUtils.bigint_to_bytes(elem_size), count) + data
        res += fill_zeros_from_left(bigint_to_bytes(elem_size), count) + data
      else:
        print('Error! pythonobj_to_pson: elem_size<>data_size: '+elem_size.inspect+'<>'\
          +data.bytesize.inspect + ' data='+data.inspect + ' pythonobj='+pythonobj.inspect)
    elif len(data)>0:
      #!!!res << PandoraUtils.fill_zeros_from_left(data, count)
      res += data[:count]
  return res #AsciiString.new(res)

# Convert PSON to python object
# RU: Конвертирует PSON в объект питон
def pson_to_pythonobj(data):
  val = None
  size = 0
  if len(data)>0:
    kind = ord(data[0])
    size = 1
    basekind, count, neg = decode_pson_kind(kind)
    if (len(data) >= size+count):
      elem_size = 0
      if count>0: elem_size = bytes_to_int(data[size:size+count])
      if basekind==PT_Int:
        val = elem_size
        if neg: val = -val
      elif basekind==PT_Time:
        val = elem_size
        if neg: val = -val
        val = datetime.datetime(val)  #Time.at(val)
      elif basekind==PT_Bool:
        if count>0:
          val = (elem_size != 0)
        else:
          val = (not neg)
      elif (basekind==PT_Str) or (basekind==PT_Sym) or (basekind==PT_Real):
        pos = size+count
        if pos+elem_size>len(data):
          elem_size = len(data)-pos
        val = data[pos: pos+elem_size]
        count += elem_size
        if basekind == PT_Sym:
          val = val.to_sym
        elif basekind == PT_Real:
          unpacked = struct.unpack('d', val)
          val = unpacked[0]
          print('RT_REAL val='+str(val))
      elif (basekind==PT_Array) or (basekind==PT_Hash):
        val = []
        if basekind == PT_Hash: elem_size *= 2
        while (len(data)-1-count>0) and (elem_size>0):
          elem_size -= 1
          aval, alen = pson_to_pythonobj(data[size+count:])
          val.append(aval)
          count += alen
        if basekind == PT_Hash:
          dic = {}
          for i in range(len(val)/2): dic[val[i*2]] = val[i*2+1]
          val = dic
          print(str(val))
      elif (basekind==PT_Nil):
        val = None
      else:
        print('pson_to_pythonobj: illegal pson kind '+basekind.inspect)
      size += count
    else:
      size = data.bytesize
  return [val, size]

# Value is empty?
# RU: Значение пустое?
def is_value_empty(val):
  res = ((val is None) or (isinstance(val, str) and (len(val)==0)) \
    or (isinstance(val, int) and (val==0)) \
    or (isinstance(val, list) and (val==[])) or (isinstance(val, dict) and (val=={})))
    #or (val==Time and (val.to_i==0)) \
  return res

# Pack PanObject fields to Name-PSON binary format
# RU: Пакует поля панобъекта в бинарный формат Name-PSON
def hash_to_namepson(fldvalues, pack_empty=False):
  buf = ''
  #fldvalues = fldvalues.sort_by_key()  #!!!sort_by {|k,v| k.to_s } # sort by key
  for nam in fldvalues:
    val = fldvalues.get(nam, 0)
    if pack_empty or (not is_value_empty(val)):
      nam = str(nam)
      nsize = len(nam)
      if nsize>255: nsize = 255
      buf += struct.pack('B', nsize) + nam[0: nsize]
      pson_elem = pythonobj_to_pson(val)
      buf += pson_elem
  return buf


# Convert Name-PSON block to PanObject fields
# RU: Преобразует Name-PSON блок в поля панобъекта
def namepson_to_hash(pson):
  dic = {}
  while pson and (len(pson)>1):
    flen = ord(pson[0])
    fname = pson[1: 1+flen]
    if (flen>0) and fname and (len(fname)>0):
      val = None
      if len(pson)-flen > 1:
        pson = pson[1+flen:]  #!!! pson[1+flen..-1] # drop getted name
        val, size = pson_to_pythonobj(pson)
        pson = pson[size:]  #!!!pson[len..-1]   # drop getted value
      else:
        pson = None
      dic[fname] = val
    else:
      pson = None
      if dic == {}: dic = None
  return dic


# ====================================================================
# Network classes
# RU: Сетевые классы

# Peer socket options
KEEPALIVE = 1 #(on/off)
KEEPIDLE = 5  #(after, sec)
KEEPINTVL = 1 #(every, sec)
KEEPCNT = 4   #(count)

# Internal constants
MaxPackSize = 1500
MaxSegSize  = 1200

CommSize     = 7
CommExtSize  = 10
SegNAttrSize = 8

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
EC_Fragment  = 10    # Кусок длинной записи
EC_Mass      = 11    # Массовые уведомления
EC_Presence  = 12    # Уведомление присутствия (пришел, ушел)
EC_Fishing   = 13    # Уведомление о рыбалке
EC_Search    = 14    # Уведомление поиска (запрос)
EC_Chat      = 15    # Уведомление чата (открыл, закрыл, сообщение)
EC_Sync      = 16    # !!! Последняя команда в серии, или индикация "живости"
# --------------------------- EC_Sync must be last
EC_Wait      = 126   # Временно недоступен
EC_Bye       = 127   # Рассоединение
# signs only
EC_Data      = 256   # Ждем данные

ECC_Auth_Hello       = 0
ECC_Auth_Cipher      = 1
ECC_Auth_Puzzle      = 2
ECC_Auth_Phrase      = 3
ECC_Auth_Sign        = 4
ECC_Auth_Captcha     = 5
ECC_Auth_Simple      = 6
ECC_Auth_Answer      = 7

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
ECC_Bye_TimeOut       = 212
ECC_Bye_Protocol      = 213

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

# Address kinds
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

# Supported protocol version
# RU: Поддерживаемая версия протокола
ProtoVersion = 'pandora0.60'

# Peer processing thread
# RU: Поток обработки клиента
class PeerThread(threading.Thread):
  def __init__ (self, pool, peer, addr):
    global peer_media_first
    self.peer = peer
    self.addr = addr
    self._stop = threading.Event()
    self.pool = pool
    self.srckey = None
    self.authkey = None
    self.lure = None
    self.fishers = []
    self.media_allow = peer_media_first
    threading.Thread.__init__(self)

  def logmes(self, mes, show=True):
    logmes(mes, show, self.addr[0])

  def unpack_comm(self, comm):
    #print('unpack_comm self, comm, len(comm) ', self, comm, len(comm))
    errcode = 0
    index, cmd, code, segsign = None, None, None, None
    if len(comm) == CommSize:
      #print(comm)
      segsign, index, cmd, code, crc8 = struct.unpack('!HHBBB', comm)
      #segsign = byte2word(segsign1, segsign2)
      #print('index, cmd, code, segsign, crc8', index, cmd, code, segsign, crc8)
      crc8f = (index & 255) ^ ((index >> 8) & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
      if crc8 != crc8f:
        errcode = 1
    else:
      errcode = 2
    return index, cmd, code, segsign, errcode

  def unpack_comm_ext(self, comm):
    if len(comm) == CommExtSize:
      #datasize, fullcrc32, segsize = struct.unpack('!IIH', comm)
      datasize, fullcrc32, segsize = struct.unpack('!iiH', comm)
    else:
      logmes('Wrong length of command extention')
    return datasize, fullcrc32, segsize

  # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
  def send_comm_and_data(self, index, cmd, code, data=None, peer=None):
    res = None
    if not peer:
      peer = self.peer
    if not data:
      data = ''
    if not index:
      index = 0
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
    crc8 = (index & 255) ^ ((index >> 8) & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
    comm = struct.pack('!HHBBB', segsign, index, cmd, code, crc8)
    #print('>send comm/data.len=', comm, len(comm), len(data))
    if index<0xFFFF:
      index += 1
    else:
      index = 0
    buf = ''
    if datasize>0:
      if segsign == LONG_SEG_SIGN:
        # если пакетов много, то добавить еще 4+4+2= 10 байт
        fullcrc32 = 0
        if cmd != EC_Media: fullcrc32 = binascii.crc32(data)
        #comm = comm + struct.pack('!IiH', datasize, fullcrc32, segsize)
        comm = comm + struct.pack('!iiH', datasize, fullcrc32, segsize)
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
    #elif @media_send and (cmd != EC_Media)
    #  @media_send = false
    #  socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0)
    #  !socket.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, 0)
    #  p '@media_send = false'
    #end
    try:
      if peer: #and (not socket.closed?):
        #print('SEND_main buf.len=', len(buf))
        sended = peer.send(buf)
      else:
        sended = -1
    except: #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
      sended = -1
    if sended == len(buf):
      res = index
    elif sended != -1:
      self.logmes('Not all data is sended '+str(sended))
    segindex = 0
    i = segdata
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
      comm = struct.pack('!HiH', index, segindex, segsize)
      if index<0xFFFF:
        index += 1
      else:
        index = 0

      buf = data[i: i+segdata]
      if cmd != EC_Media:
        segcrc32 = binascii.crc32(buf)
        #buf = buf + struct.pack('!I', segcrc32)
        buf = buf + struct.pack('!i', segcrc32)
      buf = comm + buf
      try:
        if peer: # and not socket.closed?:
          #print('SEND_add buf.len=', len(buf))
          sended = peer.send(buf)
        else:
          sended = -1
      except: #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
        sended = -1
      if sended == len(buf):
        res = index
        #p log_mes+'SEND_ADD: ('+buf+')'
      elif sended != -1:
        res = None
        self.logmes('Not all data is sended 2 '+str(sended))
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

  def get_hole_of_fisher(self, fisher):
    hole = None
    print('get_hole_of_fisher  fisher=',fisher)
    if fisher:
      try:
        hole = self.fishers.index(fisher)
      except:
        hole = None
    return hole

  def list_set(self, ind, val):
    vec = self.fishers
    if ind >= len(vec):
      vec.extend([None]*(ind-len(vec)+1))
    vec[ind] = val

  def add_hole_for_fisher(self, fisher):
    hole = self.get_hole_of_fisher(fisher)
    if hole==None:
      size = len(self.fishers)
      if size>0:
        i = 0
        while (i<size) and (hole==None):
          if self.fishers[i]==None:
            hole = i
          i += 1
        if (hole==None) and (size<256):
          hole = size
        if hole != None: self.list_set(hole, fisher)
      else:
        hole = 0
        self.list_set(hole, fisher)
    return hole

  def get_fisher_by_hole(self, hole):
    fisher = None
    if (hole != None): fisher = self.fishers[hole]
    return fisher

  def close_hole(self, hole):
    if (hole != None): self.fishers[hole] = None

  def close_hole_of_fisher(self, fisher):
    for hole in range(len(self.fishers)):
      if self.fishers[hole] == fisher:
        self.fishers[hole] = None

  def resend_to_fisher_hole(self, fisher, hole):
    if fisher and (hole != None):
      #print('LURE!', fisher, hole)
      data = struct.pack('!BB', self.rcmd, self.rcode)
      if self.rdata: data = data + self.rdata
      self.sindex = self.send_comm_and_data(self.sindex, EC_Lure, hole, data, fisher.peer)

  def resend_to_fish(self, fish):
    if fish and self.rdata and (len(self.rdata)>1):
      cmd = ord(self.rdata[0])
      code = ord(self.rdata[1])
      seg = self.rdata[2:]
      if (cmd==EC_Media) and (not self.media_allow):
        self.media_allow = True
        fish.media_allow = True
      #print('BITE! cmd,code,len(seg)', cmd, code, len(seg))
      self.sindex = self.send_comm_and_data(self.sindex, cmd, code, seg, fish.peer)

  # Accept received segment
  # RU: Принять полученный сегмент
  def accept_segment(self):
    #print('accept_segment:  self.rcmd, self.rcode, self.stage', self.rcmd, self.rcode, self.stage)
    if (self.rcmd==EC_Auth):
      if (self.rcode==ECC_Auth_Hello) and (self.stage==ST_Protocol):
        print('hello.rdata: ', self.rdata)
        if self.pool.collector:
          hole = self.pool.collector.add_hole_for_fisher(self)
          self.lure = hole
          print('-------------------hole', hole)
          if hole==None:
            self.err_scmd('Temporary error')
          else:
            self.resend_to_fisher_hole(self.pool.collector, hole)
        else:
          params = namepson_to_hash(self.rdata)
          if isinstance(params, dict):
            print('hello params: '+str(params))
            proto = params['version']
            if proto and (proto==ProtoVersion):
              self.srckey = params['mykey']
              #print('self.srckey', self.srckey, len(self.srckey), len(self.pool.keyhash))
              if (not self.pool.keyhash) or (self.srckey == self.pool.keyhash):
                self.scmd = EC_Auth
                self.scode = ECC_Auth_Simple
                self.sphrase = str(os.urandom(256))
                self.sbuf = self.sphrase
              else:
                self.err_scmd('Owner is offline')
            else:
              self.err_scmd('Unsupported protocol "'+str(proto)+'", require "'+\
                ProtoVersion+'"', ECC_Bye_Protocol)
          else:
            self.err_scmd('Bad hello')
      elif (self.rcode==ECC_Auth_Answer) and (self.stage==ST_Protocol):
        sanswer = self.rdata
        fanswer = hashlib.sha256(self.sphrase+self.pool.password).digest()
        #print('phrase,answer: ', self.sphrase, PASSWORD_HASH, fanswer)
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
    elif (self.rcmd==EC_Bite):
      if self.pool.collector:
        hole = self.rcode
        fisher = self.get_fisher_by_hole(hole)
        #print('========= fisher, hole', fisher, hole)
        if fisher:
          self.resend_to_fish(fisher)
        else:
          cmd = None
          if self.rdata and (len(self.rdata)>0): cmd = ord(self.rdata[0])
          if (cmd != EC_Bye):
            self.err_scmd('No fisher for lure')
      else:
        self.err_scmd('Collector is out')
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
    ok1comm = None

    while (self.conn_state != CS_StopRead) and (self.conn_state != CS_Disconnected):
      try:
        recieved = self.peer.recv(MaxPackSize)
        #if recieved: print('recieved.len', len(recieved))
        if (not recieved) or (recieved==''):
          self.conn_state = CS_StopRead
        rbuf = rbuf + recieved
      except:
        self.conn_state = CS_StopRead

      processedlen = 0
      while (self.conn_state == CS_Connected) and (len(rbuf)>=waitlen): #and (not socket.closed?)
        #print('==rbuf len waitlen readmode: ', rbuf, len(rbuf), waitlen, readmode)
        #print('==rbuf.len waitlen readmode: ', len(rbuf), waitlen, readmode)
        processedlen = waitlen
        nextreadmode = readmode

        # Определимся с данными по режиму чтения
        if readmode==RM_Comm:
          fullcrc32 = None
          rdatasize = None
          comm = rbuf[0: processedlen]
          rindex, self.rcmd, self.rcode, rsegsign, errcode = self.unpack_comm(comm)
          #print(' RM_Comm: rindex, rcmd, rcode, segsign, errcode: ', rindex, self.rcmd, self.rcode, rsegsign, errcode)
          if errcode == 0:
            if (self.rcmd <= EC_Sync) or (self.rcmd >= EC_Wait):
              if not ok1comm: ok1comm = True
              if rsegsign == LONG_SEG_SIGN:
                nextreadmode = RM_CommExt
                waitlen = CommExtSize
              elif rsegsign > 0:
                nextreadmode = RM_SegmentS
                waitlen, rdatasize = rsegsign, rsegsign
                if (self.rcmd != EC_Media): rdatasize -=4
            else:
              self.err_scmd('Bad command', ECC_Bye_BadComm)
          elif errcode == 1:
            self.err_scmd('Wrong CRC of recieved command', ECC_Bye_BadCommCRC)
          elif errcode == 2:
            self.err_scmd('Wrong length of recieved command', ECC_Bye_BadCommLen)
          else:
            self.err_scmd('Wrong recieved command', ECC_Bye_Unknown)
        elif readmode==RM_CommExt:
          comm = rbuf[0: processedlen]
          rdatasize, fullcrc32, rsegsize = self.unpack_comm_ext(comm)
          #print(' RM_CommExt: rdatasize, fullcrc32, rsegsize ', rdatasize, fullcrc32, rsegsize)
          nextreadmode = RM_Segment1
          waitlen = rsegsize
        elif readmode==RM_SegLenN:
          comm = rbuf[0: processedlen]
          rindex, rsegindex, rsegsize = struct.unpack('!HiH', comm)
          #print(' RM_SegLenN: ', rindex, rsegindex, rsegsize)
          nextreadmode = RM_SegmentN
          waitlen = rsegsize
        elif (readmode==RM_SegmentS) or (readmode==RM_Segment1) or (readmode==RM_SegmentN):
          #print(' RM_SegLen? [mode, buf.len] ', readmode, len(rbuf))
          if (readmode==RM_Segment1) or (readmode==RM_SegmentN):
            nextreadmode = RM_SegLenN
            waitlen = SegNAttrSize    #index + segindex + rseglen (2+4+2)
          if self.rcmd == EC_Media:
            self.rdata = self.rdata + rbuf[0: processedlen]
          else:
            rseg = rbuf[0: processedlen-4]
            #print('rseg',rseg)
            rsegcrc32str = rbuf[processedlen-4: processedlen]
            #print('rsegcrc32str=', rsegcrc32str, len(rsegcrc32str))
            crc32unpacked = struct.unpack('!i', rsegcrc32str)
            #print(crc32unpacked)
            rsegcrc32 = crc32unpacked[0]
            #print('rsegcrc32=',rsegcrc32)
            fsegcrc32 = binascii.crc32(rseg)
            if fsegcrc32 == rsegcrc32:
              self.rdata = self.rdata + rseg
            else:
              self.err_scmd('Wrong CRC of received segment', ECC_Bye_BadCRC)
          #print('RM_Segment?: data.len  rdatasize', len(self.rdata), rdatasize)

          if len(self.rdata) == rdatasize:
            nextreadmode = RM_Comm
            waitlen = CommSize
            if fullcrc32 and (fullcrc32 != binascii.crc32(self.rdata)):
              self.err_scmd('Wrong CRC of received block', ECC_Bye_BadCRC)
          elif len(self.rdata) > rdatasize:
            self.err_scmd('Too long received data ('+self.rdata.bytesize.to_s+'>'+rdatasize.to_s+')', \
              ECC_Bye_DataTooLong)

        if ok1comm:
          # Очистим буфер от определившихся данных
          rbuf = rbuf[processedlen:]
          if (self.scmd != EC_Bye) and (self.scmd != EC_Wait): self.scmd = EC_Data
          # Обработаем поступившие команды и блоки данных
          rdata0 = self.rdata
          if (self.scmd != EC_Media):
            print('-->>>> before accept: [rcmd, rcode, rdata.size]=', self.rcmd, self.rcode, len(self.rdata))
          if (self.scmd != EC_Bye) and (self.scmd != EC_Wait) and (nextreadmode == RM_Comm):
            #print('-->>>> before accept: [rcmd, rcode, rdata.size]=', self.rcmd, self.rcode, len(self.rdata))
            #if self.rdata and (len(self.rdata)>0) and @r_encode
              #@rdata = PandoraGUI.recrypt(@rkey, @rdata, false, true)
              #@rdata = Base64.strict_decode64(@rdata)
              #p log_mes+'::: decode rdata.size='+rdata.size.to_s
            #end

            #lure = None
            #if self.pool.collector:
            #  lure = self.pool.collector.get_hole_of_fisher(self)
            if self.lure==None:
              #rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd = \
              self.accept_segment() #(rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd)
            elif self.pool.collector:
              if (self.rcmd == EC_Media) and (not self.media_allow):
                self.err_scmd('Only owner can start video or audio first')
              else:
                self.resend_to_fisher_hole(self.pool.collector, self.lure)
            else:
              self.err_scmd('Owner is disconnected')

            self.rdata = ''
            if not self.sbuf: self.sbuf = ''
            #print('after accept ==>>>: [scmd, scode, sbuf.size]=', self.scmd, self.scode, len(self.sbuf))
            #p log_mes+'accept_request After='+[rcmd, rcode, rdata, scmd, scode, sbuf, last_scmd].inspect

          if self.scmd != EC_Data:
            #@sbuf = '' if scmd == EC_Bye
            #p log_mes+'add to queue [scmd, scode, sbuf]='+[scmd, scode, @sbuf].inspect
            #print('-->>>> before accept: [rcmd, rcode, rdata.size]=', self.rcmd, self.rcode, len(self.rdata))
            print('after accept ==>>>: [scmd, scode, sbuf.size]=', self.scmd, self.scode, len(self.sbuf))
            #print('recv/send: =', self.rcmd, self.rcode, len(rdata0), '/', self.scmd, self.scode, self.sbuf)
            #while PandoraGUI.get_queue_state(@send_queue) == QS_Full do
            #  p log_mes+'get_queue_state.MAIN = '+PandoraGUI.get_queue_state(@send_queue).inspect
            #  Thread.pass
            #end
            #res = PandoraGUI.add_block_to_queue(@send_queue, [scmd, scode, @sbuf])
            self.sindex = self.send_comm_and_data(self.sindex, self.scmd, self.scode, self.sbuf)
            if not self.sindex:
              self.logmes('Error while sending segment [scmd, scode, sbuf.len]', self.scmd, self.scode, len(self.sbuf))
              self.conn_state == CS_Stoping
            last_scmd = self.scmd
            self.sbuf = ''
          #print('self.conn_state: ', self.conn_state)
          readmode = nextreadmode
        else:
          print('Bad first command')
          self.conn_state = CS_Stoping
      if self.conn_state == CS_Stoping:
        self.conn_state = CS_StopRead
      #print('self.conn_state2: ', self.conn_state)
      time.sleep(0.1)

    self.peer.close()
    self.conn_state = CS_Disconnected
    addrstr = str(self.addr[0])+':'+str(self.addr[1])
    if self==self.pool.collector:
      self.pool.collector = None
      self.logmes('Collector disconnected: '+addrstr)
      self.pool.stop_peers(self)
    else:
      self.logmes('Peer disconnected: '+addrstr)
      if self.pool.collector:
        self.rcmd = EC_Bye
        self.rcode = ECC_Bye_Exit
        self.rdata = None
        self.resend_to_fisher_hole(self.pool.collector, self.lure)
        self.pool.collector.close_hole(self.lure)
        #self.pool.collector.close_hole_of_fisher(self)
    for fisher in self.fishers:
      if fisher: fisher.close_hole_of_fisher(self)

# Pool thread
# RU: Поток пула
class PoolThread(threading.Thread):
  def __init__ (self, a_server, password, keyhash=None):
    self.password = password
    self.keyhash = keyhash
    self.threads = []
    self.collector = None
    self.server = a_server
    self.processing = True
    threading.Thread.__init__(self)

  def set_keepalive(self, peer):
    peer.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, KEEPALIVE)
    peer.setsockopt(socket.SOL_TCP, socket.TCP_KEEPIDLE, KEEPIDLE)
    peer.setsockopt(socket.SOL_TCP, socket.TCP_KEEPINTVL, KEEPINTVL)
    peer.setsockopt(socket.SOL_TCP, socket.TCP_KEEPCNT, KEEPCNT)

  def run(self):
    while self.processing:
      try:
        peer, addr = self.server.accept()
        logmes('Connect from: '+str(addr[0])+':'+str(addr[1]))
        self.set_keepalive(peer)
        peer_tread = PeerThread(self, peer, addr)
        self.threads.append(peer_tread)
        peer_tread.start()
      except IOError: pass
    print('Finish server cicle.')

  def stop_peers(self, except_peer=None):
    print('Stopping peer threads...')
    for thread in self.threads:
      if thread and (thread != except_peer) and thread.isAlive():
        print('Stop: ', thread)
        thread.conn_state = CS_StopRead
        try:
          thread.peer.setblocking(0)
          thread.peer.shutdown(1)
          thread.peer.close()
        except:
          print(str(thread.getName()) + ' error while close socket')
        try:
          thread._Thread__stop()
        except:
          print(str(thread.getName()) + ' could not be terminated')
    print('Done.')


#=== RUN PANGATE ===

#a = int(q)
#s = [123, 'привет', False, 456.78, datetime.datetime.now()]
#s = {'123': 456, 'aa': 'dfsf'}
#print(s)
#print('----------')
#s = pythonobj_to_pson(s)
#s = hash_to_namepson(s)
#print(s + '|'+str(len(s)))
#res = pson_to_pythonobj(s)
#res = namepson_to_hash(s)
#print(res)
#v, size = res
#print(v)
#print(pythonobj_to_pson('123'))
#print(pythonobj_to_pson([111, '2222']))
#print(pythonobj_to_pson({'aa': 'asdsada', 'bb': 3432, 111: 222}))


# Preparation for key capturing in terminal
fd = sys.stdin.fileno()
oldterm = termios.tcgetattr(fd)
newattr = termios.tcgetattr(fd)
newattr[3] = newattr[3] & ~termios.ICANON & ~termios.ECHO
termios.tcsetattr(fd, termios.TCSANOW, newattr)
oldflags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, oldflags | os.O_NONBLOCK)

try:
  print('The Pandora Gate 0.20 (protocol: '+ProtoVersion+')')

  # Start server socket
  try:
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    #server_socket.setblocking(0)
    server_socket.bind((host, port))
    server_socket.listen(max_conn)
  except:
    server_socket = None

  if server_socket:
    saddr = server_socket.getsockname()
    logmes('=== Listening at: '+str(saddr[0])+':'+str(saddr[1]))

    pool = PoolThread(server_socket, password, keyhash)
    pool.start()
    print('Pool thread is active...')
    print('Press Q to stop and quit.')
    print('(screen: Ctrl+a+d - detach, Ctrl+a+k - kill, "screen -r" to resume)')
    working = True
    while working:
      time.sleep(0.5)  # prevent overload cpu
      try:
        c = sys.stdin.read(1)
        if (c=='q') or (c=='Q') or (c=='x') or (c=='X') or (ord(c)==185) or (ord(c)==153):
          working = False
      except IOError: pass
    logmes('Stop keyborad loop.')
    pool.processing = False
    print('New peers off.')
    server_socket.shutdown(1)
    server_socket.close()
    print('Server stopped.')
    pool.stop_peers()
    if pool.isAlive():
      try:
        pool._Thread__stop()
      except:
        print('Could not terminated listen thread '+str(pool.getName()))
    logmes('Pool thread stopped.')
  else:
    print('Cannot open socket: ' + host + str(port))
finally:
  termios.tcsetattr(fd, termios.TCSAFLUSH, oldterm)
  fcntl.fcntl(fd, fcntl.F_SETFL, oldflags)
  closelog
  sys.exit()

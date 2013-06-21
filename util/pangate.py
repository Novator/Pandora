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
TCP_PORT = 5588
BUFFER_SIZE = 1100
MAX_CONNECTIONS = 10

# Internal constants
CommSize = 6

class ClientThread(threading.Thread):
  def __init__ (self, client, addr):
    self.client = client
    self.addr = addr
    self._stop = threading.Event()
    threading.Thread.__init__(self)

  def unpack_comm(self, comm):
    errcode = 0
    if len(comm) == CommSize:
      print(comm)
      index, cmd, code, segsign1, segsign2, crc8 = struct.unpack('BBBBBB', comm)
      segsign = segsign1*256 + segsign2
      print(index, cmd, code, segsign, crc8)
      crc8f = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
      if crc8 != crc8f:
        errcode = 1
    else:
      errcode = 2
    return index, cmd, code, segsign, errcode

  # RU: Отправляет команду и данные, если есть !!! ДОБАВИТЬ !!! send_number!, buflen, buf
  def send_comm_and_data(index, cmd, code, data=nil):
    res = nil
    data ||= ''
    data = AsciiString.new(data)
    datasize = data.bytesize
    if datasize <= MaxSegSize
      segsign = datasize
      segsize = datasize
    else
      segsign = LONG_SEG_SIGN
      segsize = MaxSegSize
    end
    crc8 = (index & 255) ^ (cmd & 255) ^ (code & 255) ^ (segsign & 255) ^ ((segsign >> 8) & 255)
    # Команда как минимум равна 1+1+1+2+1= 6 байт (CommSize)
    #p 'SCAB: '+[index, cmd, code, segsign, crc8].inspect
    comm = AsciiString.new([index, cmd, code, segsign, crc8].pack('CCCnC'))
    if index<255 then index += 1 else index = 0 end
    buf = AsciiString.new
    if datasize>0
      if segsign == LONG_SEG_SIGN
        fullcrc32 = Zlib.crc32(data)
        # если пакетов много, то добавить еще 4+4+2= 10 байт
        comm << [datasize, fullcrc32, segsize].pack('NNn')
        buf << data[0, segsize]
      else
        buf << data
      end
      segcrc32 = Zlib.crc32(buf)
      # в конце всегда CRC сегмента - 4 байта
      buf << [segcrc32].pack('N')
    end
    buf = comm + buf
    if (not @media_send) and (cmd == EC_Media)
      @media_send = true
      socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0xA0)  # QoS (VoIP пакет)
      p '@media_send = true'
    elsif @media_send and (cmd != EC_Media)
      @media_send = false
      socket.setsockopt(Socket::IPPROTO_IP, Socket::IP_TOS, 0)
      p '@media_send = false'
    end
    begin
      if socket and not socket.closed?
        sended = socket.write(buf)
      else
        sended = -1
      end
    rescue #Errno::ECONNRESET, Errno::ENOTSOCK, Errno::ECONNABORTED
      sended = -1
    end

    if sended == buf.bytesize
      res = index
    elsif sended != -1
      log_message(LM_Error, 'Не все данные отправлены '+sended.to_s)
    end
    segindex = 0
    i = segsize
    while res and ((datasize-i)>0)
      segsize = datasize-i
      segsize = MaxSegSize if segsize>MaxSegSize
      if segindex<0xFFFFFFFF then segindex += 1 else segindex = 0 end
      comm = [index, segindex, segsize].pack('CNn')
      if index<255 then index += 1 else index = 0 end
      buf = data[i, segsize]
      buf << [Zlib.crc32(buf)].pack('N')
      buf = comm + buf
      begin
        if socket and not socket.closed?
          sended = socket.write(buf)
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
        log_message(LM_Error, 'Не все данные отправлены2 '+sended.to_s)
      end
      i += segsize
    return res


  def run(self):
    processing = True
    client = self.client
    client.send('Type "quit" or "exit" to disconnect\r\n')
    while processing:
      buf = client.recv(BUFFER_SIZE)
      print('Received: ', buf)
      index, cmd, code, segsign, errcode = self.unpack_comm(buf[0:CommSize])
      print(index, cmd, code, segsign, errcode)
      if errcode==0:
        client.send('Echo: '+buf)
      else:
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

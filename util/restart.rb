#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Utility for restart Pandora after the update
# Утилита для перезапуска Пандоры после обновления

# 2012 (c) Michael Galyuk, GNU GPLv2+
# RU: 2012 (c) Михаил Галюк, GNU GPLv2+


def add_quotes(str, qts='"')
  if (str.is_a? String) and str.index(' ')
    str = qts+str+qts
  end
  str
end

if ARGV.size>0
  i = 0
  cmd = ''
  while ARGV.size>0
    arg = add_quotes(ARGV.shift)
    cmd << ' ' if i>0
    cmd << arg
    i += 1
  end
  puts 'Running ['+cmd+']...'
  sleep 1
  pid = Process.spawn(cmd)
  Process.detach(pid) if pid
else
  puts 'Usage: ruby restart.rb cmd --with parameters'
end

#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

def add_quotes(str, qts='"')
  res = str
  if (res.is_a? String) and res.index(' ')
    res = qts+res+qts
  end
  res
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
  puts 'Wait a sec...'
  sleep 1
  puts 'Running ['+cmd+']...'
  res = Process.spawn(cmd)
  Process.detach(res) if res
else
  puts 'Usage: ruby restart.rb cmd --with parameters'
end

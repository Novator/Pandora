#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Console interface of Pandora
# RU: Консольный интерфейс Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2017 (c) Michael Galyuk
# RU: 2017 (c) Михаил Галюк

$web_is_active = false

require_relative 'ui.rb'
require_relative 'crypto.rb'

module PandoraWeb

  def self.activate_web(bind=nil, port=nil)
    begin
      require 'sinatra'
      $web_is_active = true
    rescue Exception
      puts('Web-module Sinatra cannot be activated')
    end
    if $web_is_active
      port ||= 8080
      bind ||= '127.0.0.1'
      Sinatra::Application.set(:port, port)
      Sinatra::Application.set(:bind, bind)
      Sinatra::Application.set(:run, false)
      Sinatra::Application.set(:public_folder, $pandora_view_dir)
      Sinatra::Application.set(:views, $pandora_view_dir)
      Sinatra::Application.set(:sessions, true)
      head = '<html><head><meta charset="UTF-8" /><title>Pandora</title></head><body>'
      foot = '</body></html>'
      Sinatra::Application.get '/' do
        user = 'Not logged'
        key = PandoraCrypto.current_key(false, false)
        if key
          user = PandoraCrypto.short_name_of_person(key, nil, 1)
        end
        head+'<a href="/command/Authorize">'+user+'</a>'+foot
        @user = user
        erb(:index)
      end
      Sinatra::Application.get '/command/:comm' do |comm|
        PandoraUI.do_menu_act(comm)
        head+'<a href="/">Home</a><br />Command: '+comm+foot
      end
      Thread.new do
        Sinatra::Application.run!
      end
    end
    $web_is_active
  end

end

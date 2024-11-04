#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Web interface of Pandora
# RU: Веб интерфейс Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2018 (c) Michael Galyuk
# RU: 2018 (c) Михаил Галюк

$web_is_active = false

require_relative 'ui.rb'
require_relative 'crypto.rb'

module PandoraWeb

  # Fill web-menu
  # RU: Заполнить web-меню
  def self.make_web_menu
    menu = nil
    sub_menu = nil
    MENU_ITEMS.each do |mi|
      command = mi[0]
      if command.nil? or menu.nil? or ((command.size==1) and (command[0]=='>'))
        menuitem = Gtk::MenuItem.new(_(mi[2]))
        if command and menu
          menu.append(menuitem)
          sub_menu = Gtk::Menu.new
          menuitem.set_submenu(sub_menu)
        else
          menubar.append(menuitem)
          menu = Gtk::Menu.new
          menuitem.set_submenu(menu)
          sub_menu = nil
        end
      else
        menuitem = PandoraGtk.create_menu_item(mi)
        if command and (command.size>1) and (command[0]=='>')
          if sub_menu
            sub_menu.append(menuitem)
          else
            menu.append(menuitem)
          end
        else
          menu.append(menuitem)
        end
      end
    end
  end

  def self.activate_web(bind=nil, port=nil, ssl_port=nil)
    res = nil
    port ||= 0
    ssl_port ||= 0
    begin
      require 'sinatra'
      $web_is_active = true
    rescue Exception
      puts('Web-module Sinatra cannot be activated')
    end
    if $web_is_active and (ssl_port>0)
      begin
        require 'sinatra/base'
        require 'webrick'
        require 'webrick/https'
        require 'openssl'
      rescue Exception
        ssl_port = 0
        puts('SSL Web-modules cannot be activated')
      end
    end
    if $web_is_active
      webrick_options = nil
      if ssl_port>0
        begin
          cert_file = File.join($pandora_base_dir, 'ssl.crt')
          key_file = File.join($pandora_base_dir, 'ssl.key')
          cert_str = OpenSSL::X509::Certificate.new(File.open(cert_file).read)
          key_str = OpenSSL::PKey::RSA.new(File.open(key_file).read)
        rescue Exception
          ssl_port = 0
          puts('SSL files are absent: ['+cert_file+'] ['+key_file+']')
        end
        if ssl_port>0
          webrick_options = {
            :Port               => ssl_port,
            :Logger             => WEBrick::Log::new($stderr, WEBrick::Log::DEBUG),
            :DocumentRoot       => '/',
            :SSLEnable          => true,
            :SSLVerifyClient    => OpenSSL::SSL::VERIFY_NONE,
            :SSLCertificate     => cert_str,
            :SSLPrivateKey      => key_str,
            :SSLCertName        => [['CN', WEBrick::Utils::getservername]],
            :app                => Sinatra::Application
          }
        end
      end
      port = ssl_port if (port==0)
      bind ||= '0.0.0.0'
      Sinatra::Application.set(:port, port)
      Sinatra::Application.set(:bind, bind)
      Sinatra::Application.set(:run, false)
      Sinatra::Application.set(:public_folder, $pandora_web_dir)
      Sinatra::Application.set(:views, $pandora_web_dir)
      Sinatra::Application.set(:sessions, true)
      Sinatra::Application.get '/' do
        user = 'Not logged'
        key = PandoraCrypto.current_key(false, false)
        if key
          user = PandoraCrypto.short_name_of_person(key, nil, 1)
        end
        @user = user
        erb(:index)
      end
      Sinatra::Application.get '/command/:comm' do |comm|
        PandoraUI.do_menu_act(comm)
        head = '<html><head><meta charset="UTF-8" /><title>Pandora</title></head><body>'
        foot = '</body></html>'
        head+'<a href="/">Home</a><br />Command: '+comm+foot
      end
      res = '['+bind+']'
      if (port>0) and (port != ssl_port)
        Thread.new do
          Sinatra::Application.run!
        end
        res << ':'+port.to_s
      end
      if (ssl_port>0) and webrick_options
        Thread.new do
          Rack::Server.start webrick_options
        end
        res << ':s'+ssl_port.to_s
      end
    end
    res
  end

end

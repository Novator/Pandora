# Some settings
# RU: Некоторые настройки
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true
Encoding.default_external = 'UTF-8'
Encoding.default_internal = 'UTF-8' #BINARY ASCII-8BIT UTF-8

Pandora.logger.debug "Pandora is configuring its options..."

# Pandora::Application configuration
Pandora.app.configure do |config|
  cli_options         = Pandora.app.cli_options

  config.poly_launch  = cli_options.poly?
  config.host         = cli_options[:host]
  config.port         = cli_options[:port]
  config.lang         = cli_options[:lang]
  config.parameters   = []
  config.logger.level = :warn
  config.db.path      = File.join(Pandora.base_dir, cli_options[:base])  # Database file

  # Unix socket file path
  config.usock        = '/tmp/pandora_unix_socket'
end

Pandora.logger.debug "Pandora successfully configured\n" + configatron.inspect

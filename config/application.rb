# Some settings
# RU: Некоторые настройки
BasicSocket.do_not_reverse_lookup = true
Thread.abort_on_exception = true

# Pandora::Application configuration
Pandora::app.configure do |config|
  config.poly_launch = true
  config.host = nil
  config.port = nil
  config.lang = 'ru'
  config.parameters = []
  config.logger.level = :warn
  $pandora_sqlite_db = File.join(Pandora.base_dir, 'pandora.sqlite')  # Database file
end

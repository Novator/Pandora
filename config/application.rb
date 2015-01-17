Pandora::app.configure do |config|
  config.poly_launch = true
  config.host = nil
  config.port = nil
  config.lang = 'ru'
  config.parameters = []
  config.logger.level = :warn
  $pandora_sqlite_db = File.join(Pandora.base_dir, 'pandora.sqlite')  # Database file
end

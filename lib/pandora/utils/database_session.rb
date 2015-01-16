module Pandora
  module Utils

    # Abstract database adapter
    # RU:Абстрактный адаптер к БД
    class DatabaseSession
      NAME = "Сеанс подключения"
      attr_accessor :connected, :conn_param, :def_flds
      def initialize
        @connected = FALSE
        @conn_param = ''
        @def_flds = {}
      end

      def connect
      end

      def create_table(table_name)
      end

      def select_table(table_name, afilter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
      end
    end

  end
end
module Pandora
  module Utils

    # Repository manager
    # RU: Менеджер хранилищ
    class RepositoryManager
      attr_accessor :adapter

      # RU: Инициировать адаптер к базе
      def get_adapter(panobj, table_ptr, recreate=false)
        adap = nil
        if @adapter
          adap = @adapter
        else
          adap = SQLiteDbSession.new
          adap.conn_param = $pandora_sqlite_db
          @adapter = adap
        end
        table_name = table_ptr[1]
        adap.def_flds[table_name] = panobj.def_fields
        if (not table_name) or (table_name=='') then
          puts 'No table name for ['+panobj.name+']'
        else
          adap.create_table(table_name, recreate)
          #adap.create_table(table_name, TRUE)
        end
        adap
      end

      # RU: Сделать выборку из таблицы
      def get_tab_select(panobj, table_ptr, filter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
        adap = get_adapter(panobj, table_ptr)
        adap.select_table(table_ptr[1], filter, fields, sort, limit, like_ex)
      end

      # RU: Записать данные в таблицу
      def get_tab_update(panobj, table_ptr, values, names, filter='')
        res = false
        recreate = ((not values) and (not names) and (not filter))
        adap = get_adapter(panobj, table_ptr, recreate)
        if recreate
          res = (adap != nil)
        else
          res = adap.update_table(table_ptr[1], values, names, filter)
        end
        res
      end

      # RU: Взять список полей
      def get_tab_fields(panobj, table_ptr)
        adap = get_adapter(panobj, table_ptr)
        adap.fields_table(table_ptr[1])
      end
    end

  end
end
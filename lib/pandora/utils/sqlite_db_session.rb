module Pandora
  module Utils

    # SQLite adapter
    # RU: Адаптер SQLite
    class SQLiteDbSession < DatabaseSession
      include Pandora::Constants

      NAME = "Сеанс SQLite"
      attr_accessor :db, :exist

      # Type translation Ruby->SQLite
      # RU: Трансляция типа Ruby->SQLite
      def pan_type_to_sqlite_type(rt, size)
        rt_str = rt.to_s
        size_i = size.to_i
        case rt_str
          when 'Integer', 'Word', 'Byte', 'Coord'
            'INTEGER'
          when 'Float'
            'REAL'
          when 'Number', 'Panhash', 'Filename'
            'NUMBER'
          when 'Date', 'Time'
            'DATE'
          when 'String'
            if (1<=size_i) and (size_i<=127)
              'VARCHAR('+size.to_s+')'
            else
              'TEXT'
            end
          when 'Text'
            'TEXT'
          when '',nil
            'NUMBER'
          when 'Blob'
            'BLOB'
          else
            'NUMBER'
        end
      end

      # RU: Преобразует значения ruby в значения sqlite
      def ruby_val_to_sqlite_val(v)
        if v.is_a? Time
          v = v.to_i
        elsif v.is_a? TrueClass
          v = 1
        elsif v.is_a? FalseClass
          v = 0
        end
        v
      end

      # Table definitions of SQLite from fields definitions
      # RU: Описание таблицы SQLite из описания полей
      def panobj_fld_to_sqlite_tab(panobj_flds)
        res = ''
        panobj_flds.each do |fld|
          res = res + ', ' if res != ''
          res = res + fld[FI_Id].to_s + ' ' + pan_type_to_sqlite_type(fld[FI_Type], fld[FI_Size])
        end
        res = '(id INTEGER PRIMARY KEY AUTOINCREMENT, ' + res + ')' if res != ''
        res
      end

      # RU: Подключается к базе
      def connect
        if not @connected
          @db = SQLite3::Database.new(conn_param)
          db.create_function('regexp', 2) do |func, pattern, expression|
            regexp = Regexp.new(pattern.to_s, Regexp::IGNORECASE)
            if expression.to_s.match(regexp)
              func.result = 1
            else
              func.result = 0
            end
          end
          @connected = true
          @exist = {}
        end
        @connected
      end

      # RU: Создает таблицу в базе
      def create_table(table_name, recreate=false, arch_table=nil, \
      arch_fields=nil, new_fields=nil)
        connect
        tfd = db.table_info(table_name)
        tfd.collect! { |x| x['name'] }
        if (not tfd) or (tfd == [])
          @exist[table_name] = false
        else
          @exist[table_name] = true
        end
        tab_def = panobj_fld_to_sqlite_tab(def_flds[table_name])
        if (! exist[table_name] or recreate) and tab_def
          if exist[table_name] and recreate
            res = db.execute('DROP TABLE '+table_name)
          end
          #p 'CREATE TABLE '+table_name+' '+tab_def
          #p 'ALTER TABLE '+table_name+' RENAME TO '+arch_table
          #p 'INSERT INTO '+table_name+' ('+new_fields+') SELECT '+new_fields+' FROM '+arch_table
          #INSERT INTO t1(val1,val2) SELECT t2.val1, t2.val2 FROM t2 WHERE t2.id = @id
          #p 'ALTER TABLE OLD_COMPANY ADD COLUMN SEX char(1)'
          res = db.execute('CREATE TABLE '+table_name+' '+tab_def)
          @exist[table_name] = TRUE
        end
        exist[table_name]
      end

      # RU: Поля таблицы
      def fields_table(table_name)
        connect
        tfd = db.table_info(table_name)
        tfd.collect { |x| [x['name'], x['type']] }
      end

      # RU: Экранирует спецсимволы маски для LIKE символом $
      def escape_like_mask(val)
        #SELECT * FROM mytable WHERE myblob LIKE X'0025';
        #SELECT * FROM mytable WHERE quote(myblob) LIKE 'X''00%';     end
        #Is it possible to pre-process your 10 bytes and insert e.g. symbol '\'
        #before any '\', '_' and '%' symbol? After that you can query
        #SELECT * FROM mytable WHERE myblob LIKE ? ESCAPE '\'
        #SELECT * FROM mytable WHERE substr(myblob, 1, 1) = X'00';
        #SELECT * FROM mytable WHERE substr(myblob, 1, 10) = ?;
        if val.is_a? String
          val.gsub!('$', '$$')
          val.gsub!('_', '$_')
          val.gsub!('%', '$%')
          #query = AsciiString.new(query)
          #i = query.size
          #while i>0
          #  if ['$', '_', '%'].include? query[i]
          #    query = query[0,i+1]+'$'+query[i+1..-1]
          #  end
          #  i -= 1
          #end
        end
        val
      end

      def correct_aster_and_quest!(val)
        if val.is_a? String
          val.gsub!('*', '%')
          val.gsub!('?', '_')
        end
        val
      end

      def recognize_filter(filter, sql_values, like_ex=nil)
        esc = false
        if filter.is_a? Hash
          #Example: {name => 'Michael', value => 0}
          seq = ''
          filter.each do |n,v|
            if n
              seq = seq + ' AND ' if seq != ''
              seq = seq + n.to_s + '=?'  #only equal!
              sql_values << v
            end
          end
          filter = seq
        elsif filter.is_a? Array
          #Example: [['name LIKE', 'Tom*'], ['value >', 3.0], ['title REGEXP', '\Wand']]
          seq = ''
          filter.each do |n,v|
            if n
              seq = seq + ' AND ' if seq != ''
              ns = n.to_s
              if like_ex
                if ns.index('LIKE') and (v.is_a? String)
                  v = escape_like_mask(v) if (like_ex & 1 > 0)
                  correct_aster_and_quest!(v) if (like_ex>=2)
                  esc = true
                end
              end
              seq = seq + ns + '?' #operation comes with name!
              sql_values << v
            end
          end
          filter = seq
        end
        filter = nil if (filter and (filter == ''))
        sql = ''
        if filter
          sql = ' WHERE ' + filter
          sql = sql + " ESCAPE '$'" if esc
        end
        [filter, sql]
      end

      # RU: Делает выборку из таблицы
      def select_table(table_name, filter=nil, fields=nil, sort=nil, limit=nil, like_ex=nil)
        res = nil
        connect
        tfd = fields_table(table_name)
        #p '[tfd, table_name, filter, fields, sort, limit, like_filter]='+[tfd, \
        #  table_name, filter, fields, sort, limit, like_filter].inspect
        if tfd and (tfd != [])
          sql_values = Array.new
          filter, filter_sql = recognize_filter(filter, sql_values, like_ex)

          fields ||= '*'
          sql = 'SELECT ' + fields + ' FROM ' + table_name + filter_sql

          if sort and (sort > '')
            sql = sql + ' ORDER BY '+sort
          end
          if limit
            sql = sql + ' LIMIT '+limit.to_s
          end
          #p 'select  sql='+sql.inspect+'  values='+sql_values.inspect+' db='+db.inspect
          res = db.execute(sql, sql_values)
        end
        #p 'res='+res.inspect
        res
      end

      # RU: Записывает данные в таблицу
      def update_table(table_name, values, names=nil, filter=nil)
        res = false
        connect
        sql = ''
        sql_values = Array.new
        sql_values2 = Array.new
        filter, filter_sql = recognize_filter(filter, sql_values2)

        if (not values) and (not names) and filter
          sql = 'DELETE FROM ' + table_name + filter_sql
        elsif values.is_a? Array and names.is_a? Array
          tfd = db.table_info(table_name)
          tfd_name = tfd.collect { |x| x['name'] }
          tfd_type = tfd.collect { |x| x['type'] }

          if filter  #update
            values.each_with_index do |v,i|
              fname = names[i]
              if fname
                sql = sql + ',' if sql != ''
                #v.is_a? String
                #v.force_encoding('ASCII-8BIT')  and v.is_a? String
                #v = AsciiString.new(v) if v.is_a? String
                v = ruby_val_to_sqlite_val(v)
                sql_values << v
                sql = sql + fname.to_s + '=?'
              end
            end

            sql = 'UPDATE ' + table_name + ' SET ' + sql + filter_sql
          else  #insert
            seq = ''
            values.each_with_index do |v,i|
              fname = names[i]
              if fname
                sql = sql + ',' if sql != ''
                seq = seq + ',' if seq != ''
                sql = sql + fname.to_s
                seq = seq + '?'
                #v.force_encoding('ASCII-8BIT')  and v.is_a? String
                #v = AsciiString.new(v) if v.is_a? String
                v = ruby_val_to_sqlite_val(v)
                sql_values << v
              end
            end
            sql = 'INSERT INTO ' + table_name + '(' + sql + ') VALUES(' + seq + ')'
          end
        end
        tfd = fields_table(table_name)
        if tfd and (tfd != [])
          sql_values = sql_values + sql_values2
          p '1upd_tab: sql='+sql.inspect
          p '2upd_tab: sql_values='+sql_values.inspect
          res = db.execute(sql, sql_values)
          #p 'upd_tab: db.execute.res='+res.inspect
          res = true
        end
        #p 'upd_tab: res='+res.inspect
        res
      end
    end

  end
end
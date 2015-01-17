# ====================================================================
# Pandora logic model
# RU: Логическая модель Пандоры
module Pandora
  module Model
    include Pandora::Constants

    # Realtion kinds
    # RU: Виды связей
    RK_Unknown  = 0
    RK_Equal    = 1
    RK_Similar  = 2
    RK_Antipod  = 3
    RK_PartOf   = 4
    RK_Cause    = 5
    RK_Follow   = 6
    RK_Ignore   = 7
    RK_CameFrom = 8
    RK_MinPublic = 235
    RK_MaxPublic = 255

    $panobject_list = []

    # Compose pandora model definition from XML file
    # RU: Сформировать описание модели по XML-файлу
    # def self.load_model_from_xml(lang='ru')
    # end

    # Panobject class by kind code
    # RU: Класс панобъекта по коду типа
    def self.panobjectclass_by_kind(kind)
      res = nil
      if (kind.is_a? Integer) and (kind>0)
        $panobject_list.each do |panobject_class|
          if panobject_class.kind==kind
            res = panobject_class
            break
          end
        end
      end
      res
    end

    # Normalize and convert trust
    # RU: Нормализовать и преобразовать доверие
    def self.trust_to_int255(trust, to_int=nil)
      if trust.is_a? Integer
        if trust<(-127)
          trust = -127
        elsif trust>127
          trust = 127
        end
        trust = (trust/127.0) if to_int == false
      elsif trust.is_a? Float
        if trust<(-1.0)
          trust = -1.0
        elsif trust>1.0
          trust = 1.0
        end
        trust = (trust * 127).round if to_int == true
      else
        trust = nil
      end
      trust
    end

    # Read record by panhash
    # RU: Читает запись по панхэшу
    def self.get_record_by_panhash(kind, panhash, pson_with_kind=nil, models=nil, \
    getfields=nil)
      # pson_with_kind: nil - raw data, false - short panhash+pson, true - panhash+pson
      res = nil
      panobjectclass = panobjectclass_by_kind(kind)
      if panobjectclass
        model = Pandora::Utils.get_model(panobjectclass.ider, models)
        if model
          filter = {'panhash'=>panhash}
          if (kind==PK_Key)
            # Select only open keys!
            filter['kind'] = 0x81
          end
          pson = (pson_with_kind != nil)
          sel = model.select(filter, pson, getfields, nil, 1)
          if sel and (sel.size>0)
            if pson
              #namesvalues = panobject.namesvalues
              #fields = model.matter_fields
              fields = model.clear_excess_fields(sel[0])
              p 'get_rec: matter_fields='+fields.inspect
              # need get all fields (except: id, panhash, modified) + kind
              lang = Pandora::Utils.lang_from_panhash(panhash)
              res = AsciiString.new
              res << [kind].pack('C') if pson_with_kind
              res << [lang].pack('C')
              p 'get_record_by_panhash|||  fields='+fields.inspect
              res << Pandora::Utils.namehash_to_pson(fields)
            else
              res = sel
            end
          end
        end
      end
      res
    end

    # Save record
    # RU: Сохранить запись
    def self.save_record(kind, lang, values, models=nil, require_panhash=nil)
      res = false
      p '=======save_record  [kind, lang, values]='+[kind, lang, values].inspect
      panobjectclass = panobjectclass_by_kind(kind)
      ider = panobjectclass.ider
      model = Pandora::Utils.get_model(ider, models)
      panhash = model.panhash(values, lang)
      p 'panhash='+panhash.inspect
      if (not require_panhash) or (panhash==require_panhash)
        filter = {'panhash'=>panhash}
        if kind==PK_Key
          filter['kind'] = 0x81
        end
        sel = model.select(filter, true, nil, nil, 1)
        if sel and (sel.size>0)
          res = true
        else
          values['panhash'] = panhash
          values['modified'] = Time.now.to_i
          res = model.update(values, nil, nil)
          model.namesvalues = values
          mfields = model.matter_fields(false)
          str = ''
          mfields.each do |n,v|
            fd = model.field_des(n)
            val, color = Pandora::Utils.val_to_view(v, fd[FI_Type], fd[FI_View], false)
            if val
              str << '|' if (str.size>0)
              if val.size>14
                val = val[0,14]
              end
              str << val.to_s
              if str.size >= 80
                str = str[0,80]
                break
              end
            end
          end
          str = '[' + model.sname + ': ' + Utf8String.new(str) + ']'
          if res
            Pandora.logger.info  Pandora.t('Recorded')+' '+str
          else
            Pandora.logger.warn  Pandora.t('Cannot record')+' '+str
          end
        end
      else
        Pandora.logger.warn Pandora.t('Non-equal panhashes ')+' '+ \
          Pandora::Utils.bytes_to_hex(panhash) + '<>' + \
          Pandora::Utils.bytes_to_hex(require_panhash)
        res = nil
      end
      res
    end

    # Save records from PSON array
    # RU: Сохранить записи из массива PSON
    def self.save_records(records, models=nil)
      if records.is_a? Array
        records.each do |record|
          kind = record[0].ord
          lang = record[1].ord
          values = Pandora::Utils.pson_to_namehash(record[2..-1])
          if not save_record(kind, lang, values, models)
            Pandora.logger.warn  Pandora.t('Cannot write a record')+' 2'
          end
        end
      end
    end

    # Get panhash list of needed records from offer
    # RU: Вернуть список панхэшей нужных записей из предлагаемых
    def self.needed_records(ph_list, models=nil)
      need_list = []
      ph_list.each do |panhash|
        kind = Pandora::Utils.kind_from_panhash(panhash)
        res = get_record_by_panhash(kind, panhash, nil, models, 'id')
        need_list << panhash if (not res)  #add if record was not found
      end
      p 'needed_records='+need_list.inspect
      need_list
    end

    # Get panhash list of modified recs from time for required kinds
    # RU: Ищет список панхэшей изменённых с заданого времени для заданных сортов
    def self.modified_records(from_time=nil, kinds=nil, models=nil)
      res = nil
      kinds ||= (1..254)
      kinds = Pandora::Utils.str_to_bytes(kinds)
      kinds.each do |kind|
        panobjectclass = panobjectclass_by_kind(kind)
        if panobjectclass
          model = Pandora::Utils.get_model(panobjectclass.ider, models)
          if model
            filter = [['modified >= ', from_time.to_i]]
            p sel = model.select(filter, false, 'panhash', 'id ASC')
            if sel and (sel.size>0)
              res ||= []
              sel.each do |row|
                res << row[0]
              end
            end
          end
        end
      end
      res
    end

    # Get panhash list of recs created by creator from time for kinds
    # RU: Ищет список панхэшей записей от создателя от времени для сортов
    def self.created_records(creator=0, from_time=nil, kinds=nil, models=nil)
      res = nil
      creator ||= Pandora::Crypto.current_user_or_key(true)
      if creator
        # creator=0 - all recs, creator=1 - created recs, creator=String - recs of the creator
        # RU: Все записи (0), записи Created (1), записи указанного создателя (String)
        kinds ||= (1..254)
        kinds = Pandora::Utils.str_to_bytes(kinds)
        kinds.each do |kind|
          panobjectclass = panobjectclass_by_kind(kind)
          if panobjectclass and ((creator==0) or (panobjectclass <= Created))
            model = Pandora::Utils.get_model(panobjectclass.ider, models)
            if model
              filter = []
              filter << ['modified >= ', from_time.to_i] if from_time
              filter << ['creator =', creator] if (creator.is_a? String)
              sel = model.select(filter, false, 'panhash', 'modified ASC')
              p '--created_records kind='+kind.inspect+' sel='+sel.inspect
              if sel and (sel.size>0)
                res ||= []
                sel.each do |row|
                  res << row[0]
                end
              end
            end
          end
        end
      end
      res
    end

    # Get panhash list of recs created by creator from time for kinds
    # RU: Ищет список панхэшей записей подписанных с времени для сортов
    def self.signed_records(signer=nil, from_time=nil, pankinds=nil, trust=nil, key=nil, models=nil)
      sel = nil
      signer ||= Pandora::Crypto.current_user_or_key(true)
      if signer
        sign_model = Pandora::Utils.get_model('Sign', models)
        if sign_model
          filter = [['creator=', signer]]
          filter << ['modified >=', from_time.to_i] if from_time
          filter << ['trust=', trust_to_int255(trust)] if trust
          filter << ['key=', key] if key
          pankinds = Pandora::Utils.str_to_bytes(pankinds)
          if ((pankinds.is_a? Array) and (pankinds.size==1))
            filter << ['obj_hash LIKE', pankinds[0].chr+'%']
            #filter << ['second REGEXP', '['+pankinds[0].chr+'].*']  #pankinds[0].chr
            #filter << ['second REGEXP', '['+1.chr+2.chr+'].*']  #pankinds[0].chr
            pankinds = nil
          end
          sel = relation_model.select(filter, false, 'obj_hash', 'modified DESC', nil)
          p 'signed_records sel1='+sel.inspect
          sel.flatten!
          sel.uniq!
          sel.compact!
          sel.sort! {|a,b| a[0]<=>b[0] }
          p 'pankinds='+pankinds.inspect
          if pankinds
            sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
          end
          p 'signed_records sel2='+sel.inspect
        end
      end
      sel
    end

    # Float trust (-1..+1) to public level 21 (0..20)
    # RU: Целое доверие в уровень публикации 21
    def self.trust2_to_pub21(trust)
      trust ||= -1
      res = (trust*10).round+10
    end

    # Float trust (-1..+1) to public relation kind (235..255)
    # RU: Целое доверие в вид связи "публикую"
    def self.trust2_to_pub235(trust)
      res = RK_MinPublic + trust2_to_pub21(trust)
    end

    # Get panhash list of published recs from time for level and kinds
    # RU: Ищет список панхэшей опубликованных записей с времени для уровня и сортов
    def self.public_records(publisher=nil, trust=nil, from_time=nil, pankinds=nil, models=nil)
      sel = nil
      publisher ||= Pandora::Crypto.current_user_or_key(true)
      if publisher
        relation_model = Pandora::Utils.get_model('Relation', models)
        if relation_model
          pub_level = trust
          pub_level = trust2_to_pub235(trust) unless trust.is_a? Numeric
          filter = [['first=', publisher], ['kind >=', pub_level]]
          filter << ['modified >=', from_time.to_i] if from_time
          pankinds = Pandora::Utils.str_to_bytes(pankinds)
          if ((pankinds.is_a? Array) and (pankinds.size==1))
            filter << ['second LIKE', pankinds[0].chr+'%']
            #filter << ['second REGEXP', '['+pankinds[0].chr+'].*']  #pankinds[0].chr
            #filter << ['second REGEXP', '['+1.chr+2.chr+'].*']  #pankinds[0].chr
            pankinds = nil
          end
          sel = relation_model.select(filter, false, 'second', 'modified DESC', nil)
          p 'public_records sel1='+sel.inspect
          sel.flatten!
          sel.uniq!
          sel.compact!
          sel.sort! {|a,b| a[0]<=>b[0] }
          p 'pankinds='+pankinds.inspect
          if pankinds
            sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
          end
          p 'public_records sel2='+sel.inspect
        end
      end
      sel
    end

    # Get panhash list of followed recs from time for kinds
    # RU: Ищет список панхэшей следуемых записей с времени для сортов
    def self.follow_records(follower=nil, from_time=nil, pankinds=nil, models=nil)
      sel = nil
      follower ||= Pandora::Crypto.current_user_or_key(true)
      if follower
        relation_model = Pandora::Utils.get_model('Relation', models)
        if relation_model
          filter = [['first=', follower], ['kind=', RK_Follow]]
          filter << ['modified >=', from_time.to_i] if filter
          pankinds = Pandora::Utils.str_to_bytes(pankinds)
          #if ((pankinds.is_a? Array) and (pankinds.size==1))
          #  filter << ['panhash LIKE', pankinds[0]+'%']  REGEXP
          #  pankinds = nil
          #end
          sel = relation_model.select(filter, false, 'second', 'modified DESC', nil, true)
          p 'follow_records sel1='+sel.inspect
          sel.flatten!
          sel.uniq!
          sel.compact!
          sel.sort! {|a,b| a[0]<=>b[0] }
          p 'pankinds='+pankinds.inspect
          if pankinds
            sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
          end
          p 'follow_records sel2='+sel.inspect
        end
      end
      sel
    end

    Languages = {0=>'all', 1=>'en', 2=>'zh', 3=>'es', 4=>'hi', 5=>'ru', 6=>'ar', \
      7=>'fr', 8=>'pt', 9=>'ja', 10=>'de', 11=>'ko', 12=>'it', 13=>'be', 14=>'id'}

    def self.lang_list
      res = Languages.values
    end

    def self.lang_to_text(lang)
      res = Languages[lang]
      res ||= ''
    end

    def self.text_to_lang(text)
      text.downcase! if text.is_a? String
      res = Languages.detect{ |n,v| v==text }
      res = res[0] if res
      res ||= ''
    end



    # Relation is symmetric
    # RU: Связь симметрична
    def self.relation_is_symmetric?(relation)
      res = [RK_Equal, RK_Similar, RK_Unknown].include? relation
    end

    # Check, create or delete relation between two panobjects
    # RU: Проверяет, создаёт или удаляет связь между двумя объектами
    def self.act_relation(panhash1, panhash2, rel_kind=RK_Unknown, act=:check, \
    creator=true, init=false, models=nil)
      res = nil
      if panhash1 or panhash2
        if not (panhash1 and panhash2)
          panhash = Pandora::Crypto.current_user_or_key(creator, init)
          if panhash
            if not panhash1
              panhash1 = panhash
            else
              panhash2 = panhash
            end
          end
        end
        if panhash1 and panhash2 #and (panhash1 != panhash2)
          #p 'relat [p1,p2,t]='+[Pandora::Utils.bytes_to_hex(panhash1), Pandora::Utils.bytes_to_hex(panhash2), rel_kind.inspect
          relation_model = Pandora::Utils.get_model('Relation', models)
          if relation_model
            kind_op = '='
            pub_kind = (rel_kind >= RK_MinPublic)
            if pub_kind
              rel_kind = RK_MinPublic if (act == :check)
              kind_op = '>=' if (act != :create)
            end
            kind_op = 'kind' + kind_op
            filter = [['first=', panhash1], ['second=', panhash2], [kind_op, rel_kind]]
            filter2 = nil
            if relation_is_symmetric?(rel_kind) and (panhash1 != panhash2)
              filter = [['first=', panhash2], ['second=', panhash1], [kind_op, rel_kind]]
            end
            #p 'relat2 [p1,p2,t]='+[Pandora::Utils.bytes_to_hex(panhash1), Pandora::Utils.bytes_to_hex(panhash2), rel_kind].inspect
            #p 'act='+act.inspect
            if (act == :delete)
              res = relation_model.update(nil, nil, filter)
              if filter2
                res2 = relation_model.update(nil, nil, filter2)
                res = res or res2
              end
            else #check or create
              flds = 'id'
              flds << ',kind' if pub_kind
              sel = relation_model.select(filter, false, flds, 'modified DESC', 1)
              exist = (sel and (sel.size>0))
              if (not exist) and filter2
                sel = relation_model.select(filter2, false, flds, 'modified DESC', 1)
                exist = (sel and (sel.size>0))
              end
              res = exist
              res = sel[0][1] if pub_kind and exist
              if (not exist) and (act == :create)
                #p 'UPD!!!'
                if filter2 and (panhash1>panhash2) #when symmetric relation less panhash must be at left
                  filter = filter2
                end
                values = {}
                values['first'] = filter[0][1]
                values['second'] = filter[1][1]
                values['kind'] = filter[2][1]
                panhash = relation_model.panhash(values, 0)
                values['panhash'] = panhash
                values['modified'] = Time.now.to_i
                res = relation_model.update(values, nil, nil)
              end
            end
          end
        end
      end
      res
    end



    def self.with_each_model(models_path, &block)
      Dir.glob(models_path).sort.each do |model_xml_file|
        file = File.open(model_xml_file)
        xml_doc = REXML::Document.new file
      end
    end

    # Compose pandora model definition from XML file
    # RU: Сформировать описание модели по XML-файлу
    def self.load_from_xml(lang='ru')
      # with_each_model File.join(Pandora.model_dir, '**', '*.xml') do |ya|
      # end
      lang = '.'+lang
      dir_mask = File.join(File.join(Pandora.model_dir, '**'), '*.xml')
      # dir_mask = File.join(Pandora.model_dir, '*.xml')
      dir_list = Dir.glob(dir_mask).sort
      dir_list.each do |pathfilename|
        filename = File.basename(pathfilename)
        file = Object::File.open(pathfilename)
        xml_doc = REXML::Document.new(file)
        xml_doc.elements.each('pandora-model/*') do |section|
          if section.name != 'Defaults'
            # Field definition
            section.elements.each('*') do |element|
              panobj_id = element.name
              # p 'panobj_id='+panobj_id.inspect
              new_panobj = true
              flds = Array.new
              panobject_class = nil
              panobject_class = Pandora::Model.const_get(panobj_id) if Pandora::Model.const_defined? panobj_id
              #p panobject_class
              if panobject_class and panobject_class.def_fields and (panobject_class.def_fields != [])
                # just extend existed class
                panobj_name = panobject_class.name
                panobj_tabl = panobject_class.tables
                new_panobj = false
                #p 'old='+panobject_class.inspect
              else
                # create new class
                panobj_name = panobj_id
                if not panobject_class #not const_defined? panobj_id
                  parent_class = element.attributes['parent']
                  if (not parent_class) or (parent_class=='') or (not (Pandora::Model.const_defined? parent_class))
                    if parent_class
                      puts Pandora.t('Parent is not defined, ignored')+' /'+filename+':'+panobj_id+'<'+parent_class
                    end
                    parent_class = 'Panobject'
                  end
                  if Pandora::Model.const_defined? parent_class
                    Pandora::Model.const_get(parent_class).def_fields.each do |f|
                      flds << f.dup
                    end
                  end
                  init_code = 'class '+panobj_id+' < Pandora::Model::'+parent_class+'; name = "'+panobj_name+'"; end'
                  module_eval(init_code)
                  panobject_class = Pandora::Model.const_get(panobj_id)
                  $panobject_list << panobject_class if not $panobject_list.include? panobject_class
                end

                #p 'new='+panobject_class.inspect
                panobject_class.def_fields = flds
                panobject_class.ider = panobj_id
                kind = panobject_class.superclass.kind #if panobject_class.superclass <= BasePanobject
                kind ||= 0
                panobject_class.kind = kind
                #panobject_class.lang = 5
                panobj_tabl = panobj_id
                panobj_tabl = Pandora::Utils.get_name_or_names(panobj_tabl, true, 'en')
                panobj_tabl.downcase!
                panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]]
              end
              panobj_kind = element.attributes['kind']
              panobject_class.kind = panobj_kind.to_i if panobj_kind
              panobj_sort = element.attributes['sort']
              panobject_class.sort = panobj_sort if panobj_sort
              flds = panobject_class.def_fields
              flds ||= Array.new
              #p 'flds='+flds.inspect
              panobj_name_en = element.attributes['name']
              panobj_name = panobj_name_en if (panobj_name==panobj_id) and panobj_name_en and (panobj_name_en != '')
              panobj_name_lang = element.attributes['name'+lang]
              panobj_name = panobj_name_lang if panobj_name_lang and (panobj_name_lang != '')
              #puts panobj_id+'=['+panobj_name+']'
              panobject_class.name = panobj_name

              panobj_tabl = element.attributes['table']
              panobject_class.tables = [['robux', panobj_tabl], ['perm', panobj_tabl]] if panobj_tabl

              # fill fields
              element.elements.each('*') do |sub_elem|
                #p panobj_id+':'+[sub_elem, sub_elem.name].inspect
                seu = sub_elem.name.upcase
                if seu==sub_elem.name  #elem name has BIG latters
                  # This is a function
                  #p 'Функция не определена: ['+sub_elem.name+']'
                else
                  # This is a field
                  i = 0
                  while (i<flds.size) and (flds[i][FI_Id] != sub_elem.name) do i+=1 end
                  fld_exists = (i<flds.size)
                  if new_panobj or fld_exists
                    # new panobject or field exists already
                    if fld_exists
                      fld_name = flds[i][FI_Name]
                    else
                      flds[i] = Array.new
                      flds[i][FI_Id] = sub_elem.name
                      fld_name = sub_elem.name
                    end
                    fld_name = sub_elem.attributes['name']
                    flds[i][FI_Name] = fld_name if fld_name and (fld_name != '')
                    #fld_name = fld_name_en if (fld_name_en ) and (fld_name_en != '')
                    fld_name_lang = sub_elem.attributes['name'+lang]
                    flds[i][FI_LName] = fld_name_lang if fld_name_lang and (fld_name_lang != '')
                    #fld_name = fld_name_lang if (fld_name_lang ) and (fld_name_lang != '')
                    #flds[i][FI_Name] = fld_name

                    fld_type = sub_elem.attributes['type']
                    flds[i][FI_Type] = fld_type if fld_type and (fld_type != '')
                    fld_size = sub_elem.attributes['size']
                    flds[i][FI_Size] = fld_size if fld_size and (fld_size != '')
                    fld_pos = sub_elem.attributes['pos']
                    flds[i][FI_Pos] = fld_pos if fld_pos and (fld_pos != '')
                    fld_fsize = sub_elem.attributes['fsize']
                    flds[i][FI_FSize] = fld_fsize.to_i if fld_fsize and (fld_fsize != '')

                    fld_hash = sub_elem.attributes['hash']
                    flds[i][FI_Hash] = fld_hash if fld_hash and (fld_hash != '')

                    fld_view = sub_elem.attributes['view']
                    flds[i][FI_View] = fld_view if fld_view and (fld_view != '')
                  else
                    # not new panobject, field doesn't exists
                    puts Pandora.t('Property was not defined, ignored')+' /'+filename+':'+panobj_id+'.'+sub_elem.name
                  end
                end
              end
              #p flds
              #p "========"
              panobject_class.def_fields = flds
            end
          else
            # Default param values
            section.elements.each('*') do |element|
              name = element.name
              desc = element.attributes['desc']
              desc ||= name
              type = element.attributes['type']
              section = element.attributes['section']
              setting = element.attributes['setting']
              row = nil
              ind = Pandora.config.parameters.index{ |row| row[Pandora::Model::PF_Name]==name }
              if ind
                row = Pandora.config.parameters[ind]
              else
                row = Array.new
                row[Pandora::Model::PF_Name] = name
                Pandora.config.parameters << row
                ind = Pandora.config.parameters.size-1
              end
              row[Pandora::Model::PF_Desc] = desc if desc
              row[Pandora::Model::PF_Type] = type if type
              row[Pandora::Model::PF_Section] = section if section
              row[Pandora::Model::PF_Setting] = setting if setting
              Pandora.config.parameters[ind] = row
            end
          end
        end
        file.close
      end
    end

  end
end
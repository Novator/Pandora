#!/usr/bin/env ruby
# encoding: UTF-8
# coding: UTF-8

# Pandora logic model
# RU: Логическая модель Пандоры
#
# This program is free software and distributed under the GNU GPLv2
# RU: Это свободное программное обеспечение распространяется под GNU GPLv2
# 2012 (c) Michael Galyuk
# RU: 2012 (c) Михаил Галюк

require File.expand_path('../utils.rb',  __FILE__)

module PandoraModel

  include PandoraUtils

  # Pandora record kind
  # RU: Тип записей Пандоры
  PK_Person    = 1
  PK_City      = 4
  PK_Blob      = 12
  PK_Relation  = 14
  PK_Key       = 221
  PK_Sign      = 222
  PK_Parameter = 220
  PK_Message   = 227
  PK_BlobBody  = 255

  # Panhash length
  # RU: Длина панхэша
  PanhashSize = 22

  def self.hex_to_panhash(hexstr)
    res = PandoraUtils.hex_to_bytes(hexstr)
    res = PandoraUtils.fill_zeros_from_right(res, PanhashSize)
    AsciiString.new(res)
  end

  def self.calc_node_panhash(akey, abaseid)
    node = nil
    if akey and abaseid
      node = PandoraUtils.phash(akey, 12) + abaseid[0, 8]
    end
    node
  end

  def self.find_person_by_key(akey, models=nil)
    res = nil
    sign_model = PandoraUtils.get_model('Sign', models)
    sel = sign_model.select({:key_hash => akey}, false, 'creator', 'id ASC', 1)
    res = sel[0][0] if (sel and (sel.size>0))
    if not res
      key_model = PandoraUtils.get_model('Key', models)
      sel = kmodel.select({:panhash => akey}, false, 'creator', 'id ASC', 1)
      res = sel[0][0] if (sel and (sel.size>0))
    end
    res
  end

  # Pandora's object
  # RU: Объект Пандоры
  class Panobject < PandoraUtils::BasePanobject
    include PandoraUtils

    ider = 'Panobject'
    name = "Объект Пандоры"

    def get_fields_as_view(row, edit=nil, panhash=nil, formfields=nil)
      if formfields.nil?
        a_def_fields = self.def_fields.dup
        formfields = Array.new
        a_def_fields.each do |field|
          formfields << field.dup
        end
      end
      tab_flds = self.tab_fields
      formfields.each do |field|
        val = nil
        fid = field[FI_Id]
        view = field[FI_View]
        col = tab_flds.index{ |tf| tf[0] == fid }
        if col and (row.is_a? Array)
          val = row[col]
          if (self.kind==PK_Parameter) and (fid=='value')
            type = self.field_val('type', row)
            setting = self.field_val('setting', row)
            ps = PandoraUtils.decode_param_setting(setting)
            view = ps['view']
            view ||= PandoraUtils.pantype_to_view(type)
            field[FI_View] = view
            field[FI_FSize] = 256 if not view
          end
        end

        if (not edit) and val.nil? and (self.is_a? PandoraModel::Created)
          case fid
            when 'created'
              val = Time.now.to_i
            when 'creator'
              creator = PandoraCrypto.current_user_or_key(true, false)
              val = creator if creator
          end
        end

        val, color = PandoraUtils.val_to_view(val, type, view, true)
        field[FI_Value] = val
        field[FI_Color] = color
      end

      ind = formfields.index { |field| field[PandoraUtils::FI_Id] == 'panhash_lang' }
      field = nil
      if ind
        field = formfields[ind]
      else
        #inject lang field
        field = Array.new
        field[PandoraUtils::FI_Id] = 'panhash_lang'
        field[PandoraUtils::FI_Name] = 'Language'
        lang_tit = _('Language')
        field[PandoraUtils::FI_LName] = lang_tit
        field[PandoraUtils::FI_VFName] = lang_tit
        field[PandoraUtils::FI_Type] = 'Byte'
        field[PandoraUtils::FI_View] = 'bytelist'
        formfields << field
      end
      lang = PandoraModel.text_to_lang($lang)
      lang = panhash[1].ord if (panhash.is_a?(String) and (panhash.size>1))
      lang ||= 0
      field[PandoraUtils::FI_Value] = lang.to_s

      formfields
    end

  end

  $panobject_list = []

  # Compose pandora model definition from XML file
  # RU: Сформировать описание модели по XML-файлу
  def self.load_model_from_xml(lang='ru')
    lang = '.'+lang
    #dir_mask = File.join(File.join($pandora_model_dir, '**'), '*.xml')
    dir_mask = File.join($pandora_model_dir, '*.xml')
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
            #p 'panobj_id='+panobj_id.inspect
            new_panobj = true
            flds = Array.new
            panobj_name = nil
            panobj_table = nil
            panobject_class = nil
            if PandoraModel.const_defined? panobj_id
              panobject_class = PandoraModel.const_get(panobj_id)
            end
            #p panobject_class
            if panobject_class and panobject_class.def_fields \
            and (panobject_class.def_fields != [])
              # just extend existed class
              panobj_name = panobject_class.name
              panobj_table = panobject_class.table
              new_panobj = false
              #p 'old='+panobject_class.inspect
            else
              # create new class
              panobj_name = panobj_id
              if not panobject_class #not PandoraModel.const_defined? panobj_id
                parent_class = element.attributes['parent']
                if (not parent_class) or (parent_class=='') \
                or (not (PandoraModel.const_defined? parent_class))
                  if parent_class
                    puts _('Parent is not defined, ignored')+' /'+filename+':'+\
                      panobj_id+'<'+parent_class
                  end
                  parent_class = 'Panobject'
                end
                if PandoraModel.const_defined? parent_class
                  PandoraModel.const_get(parent_class).def_fields.each do |f|
                    flds << f.dup
                  end
                end
                init_code = 'class '+panobj_id+' < PandoraModel::'+parent_class+\
                  '; name = "'+panobj_name+'"; end'
                module_eval(init_code)
                panobject_class = PandoraModel.const_get(panobj_id)
                if not $panobject_list.include? panobject_class
                  $panobject_list << panobject_class
                end
              end

              #p 'new='+panobject_class.inspect
              panobject_class.def_fields = flds
              panobject_class.ider = panobj_id
              kind = panobject_class.superclass.kind #if panobject_class.superclass <= BasePanobject
              kind ||= 0
              panobject_class.kind = kind
              #panobject_class.lang = 5
              panobj_table = PandoraUtils::get_name_or_names(panobj_id, true, 'en')
              panobj_table = panobj_table.downcase
              panobject_class.table = panobj_table
            end
            panobj_kind = element.attributes['kind']
            panobject_class.kind = panobj_kind.to_i if panobj_kind
            panobj_sort = element.attributes['sort']
            panobject_class.sort = panobj_sort if panobj_sort
            flds = panobject_class.def_fields
            flds ||= Array.new
            #p 'flds='+flds.inspect
            panobj_name_en = element.attributes['name']
            if (panobj_name==panobj_id) and panobj_name_en and (panobj_name_en != '')
              panobj_name = panobj_name_en
            end
            panobj_name_lang = element.attributes['name'+lang]
            panobj_name = panobj_name_lang if panobj_name_lang and (panobj_name_lang != '')
            #puts panobj_id+'=['+panobj_name+']'
            panobject_class.name = panobj_name

            panobj_table = element.attributes['table']
            panobject_class.table = panobj_table if panobj_table

            # fill fields
            element.elements.each('*') do |sub_elem|
              #p panobj_id+':'+[sub_elem, sub_elem.name].inspect
              if sub_elem.name==sub_elem.name.upcase  #elem name has BIG latters
                # This is a function
                p 'Функция не определена: ['+sub_elem.name+']'
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
                  puts _('Property was not defined, ignored')+' /'+filename+':'+panobj_id+'.'+sub_elem.name
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
            ind = $pandora_parameters.index{ |row| row[PandoraUtils::PF_Name]==name }
            if ind
              row = $pandora_parameters[ind]
            else
              row = Array.new
              row[PandoraUtils::PF_Name] = name
              $pandora_parameters << row
              ind = $pandora_parameters.size-1
            end
            row[PandoraUtils::PF_Desc] = desc if desc
            row[PandoraUtils::PF_Type] = type if type
            row[PandoraUtils::PF_Section] = section if section
            row[PandoraUtils::PF_Setting] = setting if setting
            $pandora_parameters[ind] = row
          end
        end
      end
      file.close
    end
  end

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

  # Normalize and convert trust if need
  # RU: Нормализовать и преобразовать доверие если нужно
  def self.transform_trust(trust, mode=nil)
    if (trust.is_a? Integer) or (trust.is_a? Float)
      mode ||= :auto_to_int
      to_float = ((mode==:auto_to_float) or (mode==:int_to_float))
      val_int = ((mode==:int_to_float) \
        or (((mode==:auto_to_float) or (mode==:auto_to_int)) and (trust.is_a? Integer)))
      if val_int
        if trust<(-127)
          trust = -127
        elsif trust>127
          trust = 127
        end
        trust = (trust/127.0) if to_float
      else
        if trust<(-1.0)
          trust = -1.0
        elsif trust>1.0
          trust = 1.0
        end
        trust = (trust * 127).round if (not to_float)
      end
    end
    trust
  end

  # Detect Panobject kind by pointer or panhash
  # RU: Определить тип Панобъекта по указателю или панхэшу
  def self.detect_panobject_kind(pointer_or_panhash)
    res = nil
    if pointer_or_panhash.is_a?(String)
      res = PandoraUtils.kind_from_panhash(pointer_or_panhash)
    elsif pointer_or_panhash.is_a?(PandoraModel::Panobject)
      res = pointer_or_panhash.kind
    end
    res
  end

  # Float trust (-1..+1) to public level 21 (0..20)
  # RU: Дробное доверие в уровень публикации 21
  def self.trust2_to_pub21(trust)
    trust ||= -1
    res = (trust*10.0).round+10
  end

  # Float trust (-1..+1) to public relation kind (235..255)
  # RU: Дробное доверие в вид связи "публикую"
  def self.trust2_to_pub235(trust)
    res = RK_MinPublic + trust2_to_pub21(trust)
  end

  # Trust to str with view like "0.2"
  # RU: Доверие в строку вида "0.2"
  def self.trust_to_str(trust)
    trust ||= 0.0
    trust = transform_trust(trust, :auto_to_float)
    res = ((trust*10).round/10.0).to_s
  end

  # Read record by panhash
  # RU: Читает запись по панхэшу
  def self.get_record_by_panhash(panhash, kind=nil, pson_with_kind=nil, models=nil, \
  getfields=nil)
    # pson_with_kind: nil - raw data, false - short panhash+pson, true - panhash+pson
    res = nil
    kind ||= PandoraUtils.kind_from_panhash(panhash)
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    if panobjectclass
      model = PandoraUtils.get_model(panobjectclass.ider, models)
      if model
        filter = ['panhash=?', panhash]
        if (kind==PK_Key)
          # Except private RSA keys
          filter[0] << ' AND cipher<>'+PandoraCrypto::KT_Priv.to_s
        end
        pson = (pson_with_kind != nil)
        #p 'filter='+filter.inspect
        sel = model.select(filter, pson, getfields, nil, 1)
        if sel and (sel.size>0)
          if pson
            #namesvalues = panobject.namesvalues
            #fields = model.matter_fields
            fields = model.clear_excess_fields(sel[0])
            #p 'get_rec: matter_fields='+fields.inspect
            # need get all fields (except: id, panhash, modified) + kind
            lang = PandoraUtils.lang_from_panhash(panhash)
            res = AsciiString.new
            res << [kind].pack('C') if pson_with_kind
            res << [lang].pack('C')
            #p 'get_record_by_panhash|||  fields='+fields.inspect
            res << PandoraUtils.hash_to_namepson(fields)
          else
            res = sel
          end
        end
      end
    end
    res
  end

  # Read record by sha1 or md5 hash
  # RU: Читает запись по sha1 или md5 хэшу
  def self.get_record_by_hash(hash, kind=nil, pson_with_kind=nil, models=nil, \
  getfields=nil)
    # pson_with_kind: nil - raw data, false - short panhash+pson, true - panhash+pson
    res = nil
    kind ||= PK_Blob
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    if panobjectclass and (hash.is_a? String) and (hash.size>0)
      model = PandoraUtils.get_model(panobjectclass.ider, models)
      if model
        filter = nil
        if hash.size==16
          filter = {'md5'=>hash}
        else
          filter = {'sha1'=>hash}
        end
        pson = (pson_with_kind != nil)
        sel = model.select(filter, pson, getfields, nil, 1)
        if sel and (sel.size>0)
          if pson
            fields = model.clear_excess_fields(sel[0])
            lang = PandoraUtils.lang_from_panhash(panhash)
            res = AsciiString.new
            res << [kind].pack('C') if pson_with_kind
            res << [lang].pack('C')
            p 'get_record_by_hash|||  fields='+fields.inspect
            res << PandoraUtils.hash_to_namepson(fields)
          else
            res = sel
          end
        end
      end
    end
    res
  end

  $keep_for_trust  = 0.5      # set "Support" flag for records with creator trust
  $max_relative_path_depth = 2

  # Save record
  # RU: Сохранить запись
  def self.save_record(kind, lang, values, models=nil, require_panhash=nil, support=:auto)
    res = false
    inside_panhash = values['panhash']
    inside_panhash ||= values[:panhash]
    if (inside_panhash.is_a? String) and (inside_panhash.size>2)
      require_panhash ||= inside_panhash
      kind ||= inside_panhash[0].ord
      lang ||= inside_panhash[1].ord
    end
    #p '=======save_record  [kind, lang, values]='+[kind, lang, values].inspect
    panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
    ider = panobjectclass.ider
    model = PandoraUtils.get_model(ider, models)
    panhash = model.calc_panhash(values, lang)
    #p 'panhash='+panhash.inspect
    if (not require_panhash) or (panhash==require_panhash)
      harvest_blob = nil
      filter = {'panhash'=>panhash}
      if kind==PK_Key
        filter['kind'] = 0x81  #search public key only
      elsif kind==PK_Blob
        sha1 = values['sha1']
        sha1 ||= values[:sha1]
        fn = values['blob']
        str_blob = nil
        if fn
          str_blob = true
        else
          fn = values[:blob]
          str_blob = false if fn
        end
        #p '--- save_record1  fn='+fn.inspect
        if (not str_blob.nil?) and (fn.is_a? String) and (fn.size>1) and (fn[0]=='@')
          #p '--- save_record2  fn='+fn.inspect
          fn = PandoraUtils.absolute_path(fn[1..-1])
          fn = '@'+PandoraUtils.relative_path(fn, $max_relative_path_depth)
          #p '--- save_record3  fn='+fn.inspect
          if str_blob
            values['blob'] = fn
          else
            values[:blob] = fn
          end
        end

        # ! Здесь надо увязать куски выше и ниже:
        # ! если файл уже есть, то переопределить поле 'blob'
        # ! при этом отследить совпадение sha1

        if sha1
          fn_fs = $window.pool.blob_exists?(sha1, models, true)
          #p '--- save_record4  fn='+fn.inspect
          if fn_fs
            fn, fs = fn_fs
            harvest_blob = (not File.exist?(fn))
          else
            harvest_blob = true
          end

          if harvest_blob
            harvest_blob = nil
            #!!!reqs = $window.pool.find_search_request(sha1, PandoraModel::PK_BlobBody)
            #unless (reqs.is_a? Array) and (reqs.size>0)
            #  harvest_blob = sha1
            #end
          end
        end
      end
      sel = model.select(filter, true, nil, nil, 1)
      if sel and (sel.size>0)
        res = true
      else
        if ((support==:auto) or support.nil?) and $keep_for_trust
          creator = values['creator']
          if creator
            trust_or_num = PandoraCrypto.trust_to_panobj(creator, models)
            if (trust_or_num.is_a? Float) and (trust_or_num >= $keep_for_trust)
              support = :yes
            end
          end
        end
        panstate = 0
        if support==:yes
          panstate = (panstate | PandoraModel::PSF_Support)
        end
        if harvest_blob
          panstate = (panstate | PandoraModel::PSF_Harvest)
        end
        values['panstate'] = panstate
        values['panhash'] = panhash
        values['modified'] = Time.now.to_i
        res = model.update(values, nil, nil)
        str = '['+model.record_info(80, values, ': ')+']'
        if res
          PandoraUI.log_message(PandoraUI::LM_Info, _('Recorded')+' '+str)
        else
          PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot record')+' '+str)
        end
      end
      #p '--save_rec5   harvest_blob='+harvest_blob.inspect
      if (harvest_blob.is_a? String)
        reqs = $window.pool.add_mass_record(MK_Search, PandoraModel::PK_BlobBody, \
          harvest_blob)
      end
    else
      PandoraUI.log_message(PandoraUI::LM_Warning, _('Non-equal panhashes ')+' '+ \
        PandoraUtils.bytes_to_hex(panhash) + '<>' + \
        PandoraUtils.bytes_to_hex(require_panhash))
      res = nil
    end
    res = panhash if res
    res
  end

  # Save records from PSON array
  # RU: Сохранить записи из массива PSON
  def self.save_records(records, models=nil, support=:auto)
    res = true
    if records.is_a? Array
      records.each do |record|
        kind = record[0].ord
        lang = record[1].ord
        values = PandoraUtils.namepson_to_hash(record[2..-1])
        if not PandoraModel.save_record(kind, lang, values, models, nil, support)
          PandoraUI.log_message(PandoraUI::LM_Warning, _('Cannot write a record')+' 2')
          res = false
        end
      end
    end
    res
  end

  # Get panhash list of needed records from offer
  # RU: Вернуть список панхэшей нужных записей из предлагаемых
  def self.needed_records(ph_list, models=nil)
    need_list = []
    if ph_list.is_a? Array
      ph_list.each do |panhash|
        res = PandoraModel.get_record_by_panhash(panhash, nil, nil, models, 'id')
        need_list << panhash if (not res)  #add if record was not found
      end
    end
    #p 'needed_records='+need_list.inspect
    need_list
  end

  $kind_list = nil

  # Get kind list of all models
  # RU: Возвращает список типов всех моделей
  def self.get_kind_list
    res = $kind_list
    if not res
      $kind_list = []
      res = $kind_list
      kinds = (1..254)
      kinds = PandoraUtils.str_to_bytes(kinds)
      kinds.each do |kind|
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        res << [kind, panobjectclass.ider, \
          _(PandoraUtils.get_name_or_names(panobjectclass.name))] if panobjectclass
      end
    end
    res
  end

  # Get panhash list of modified recs from time for required kinds
  # RU: Ищет список панхэшей изменённых с заданого времени для заданных сортов
  def self.modified_records(from_time=nil, kinds=nil, models=nil)
    res = nil
    kinds ||= (1..254)
    kinds = PandoraUtils.str_to_bytes(kinds)
    kinds.each do |kind|
      panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
      if panobjectclass
        model = PandoraUtils.get_model(panobjectclass.ider, models)
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
    creator ||= PandoraCrypto.current_user_or_key(true)
    if creator
      # creator=0 - all recs, creator=1 - created recs, creator=String - recs of the creator
      # RU: Все записи (0), записи Created (1), записи указанного создателя (String)
      kinds ||= (1..254)
      kinds = PandoraUtils.str_to_bytes(kinds)
      kinds.each do |kind|
        panobjectclass = PandoraModel.panobjectclass_by_kind(kind)
        if panobjectclass and ((creator==0) or (panobjectclass <= PandoraModel::Created))
          model = PandoraUtils.get_model(panobjectclass.ider, models)
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
  def self.signed_records(signer=nil, from_time=nil, pankinds=nil, trust=nil, \
  key=nil, models=nil)
    sel = nil
    signer ||= PandoraCrypto.current_user_or_key(true)
    if signer
      sign_model = PandoraUtils.get_model('Sign', models)
      if sign_model
        filter = [['creator=', signer]]
        filter << ['modified >=', from_time.to_i] if from_time
        filter << ['trust=', transform_trust(trust)] if trust
        filter << ['key=', key] if key
        pankinds = PandoraUtils.str_to_bytes(pankinds)
        if ((pankinds.is_a? Array) and (pankinds.size==1))
          filter << ['obj_hash LIKE', pankinds[0].chr+'%']
          #filter << ['second REGEXP', '['+pankinds[0].chr+'].*']  #pankinds[0].chr
          #filter << ['second REGEXP', '['+1.chr+2.chr+'].*']  #pankinds[0].chr
          pankinds = nil
        end
        sel = relation_model.select(filter, false, 'obj_hash', 'modified DESC', nil)
        #p 'signed_records sel1='+sel.inspect
        sel.flatten!
        sel.uniq!
        sel.compact!
        sel.sort! {|a,b| a[0]<=>b[0] }
        #p 'pankinds='+pankinds.inspect
        if pankinds
          sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
        end
        #p 'signed_records sel2='+sel.inspect
      end
    end
    sel
  end

  # Get panhash list of published recs from time for level and kinds
  # RU: Ищет список панхэшей опубликованных записей с времени для уровня и сортов
  def self.public_records(publisher=nil, trust=nil, from_time=nil, pankinds=nil, models=nil)
    sel = nil
    publisher ||= PandoraCrypto.current_user_or_key(true)
    if publisher
      relation_model = PandoraUtils.get_model('Relation', models)
      if relation_model
        pub_level = trust
        pub_level = trust2_to_pub235(trust) if (not trust.is_a? Numeric)
        filter = [['first=', publisher], ['kind >=', pub_level]]
        filter << ['modified >=', from_time.to_i] if from_time
        pankinds = PandoraUtils.str_to_bytes(pankinds)
        if (pankinds.is_a? Array) and (pankinds.size==1)
          filter << ['second LIKE', "\\"+pankinds[0].chr+'%']
          #filter << ['second REGEXP', '['+pankinds[0].chr+'].*']  #pankinds[0].chr
          #filter << ['second REGEXP', '['+1.chr+2.chr+'].*']  #pankinds[0].chr
          pankinds = nil
        end
        sel = relation_model.select(filter, false, 'second', 'modified DESC', nil)
        #p 'public_records sel1='+sel.inspect
        sel.flatten!
        sel.uniq!
        sel.compact!
        sel.sort! {|a,b| a[0]<=>b[0] }
        #p 'pankinds='+pankinds.inspect
        if (pankinds.is_a? Array) and (pankinds.size>0)
          sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
        end
        #p 'public_records sel2='+sel.inspect
      end
    end
    sel
  end

  # Get panhash list of followed recs from time for kinds
  # RU: Ищет список панхэшей следуемых записей с времени для сортов
  def self.follow_records(follower=nil, from_time=nil, pankinds=nil, models=nil)
    sel = nil
    follower ||= PandoraCrypto.current_user_or_key(true)
    if follower
      relation_model = PandoraUtils.get_model('Relation', models)
      if relation_model
        filter = [['first=', follower], ['kind=', RK_Follow]]
        filter << ['modified >=', from_time.to_i] if filter
        pankinds = PandoraUtils.str_to_bytes(pankinds)
        #if ((pankinds.is_a? Array) and (pankinds.size==1))
        #  filter << ['panhash LIKE', pankinds[0]+'%']  REGEXP
        #  pankinds = nil
        #end
        sel = relation_model.select(filter, false, 'second', 'modified DESC', nil, true)
        #p 'follow_records sel1='+sel.inspect
        sel.flatten!
        sel.uniq!
        sel.compact!
        sel.sort! {|a,b| a[0]<=>b[0] }
        #p 'pankinds='+pankinds.inspect
        if pankinds
          sel.delete_if { |panhash| (not (pankinds.include? panhash[0].ord)) }
        end
        #p 'follow_records sel2='+sel.inspect
      end
    end
    sel
  end

  ImageCacheSize = 100*4
  $image_cache = []

  # Get pixbuf from cache by a way
  # RU: Взять pixbuf из кэша по пути
  def self.get_image_from_cache(proto, obj_type, way)
    #ind = [proto, obj_type, way]
    #p '--get_image_from_cache  [proto, obj_type, way]='+[proto, obj_type, way].inspect
    res = $image_cache.detect{ |e| ((e[0]==proto) and (e[1]==obj_type) and (e[2]==way)) }
    res = res[3] if res
    res
  end

  # Save pixbuf to cache with a way
  # RU: Сохранить pixbuf в кэша по пути
  def self.save_image_to_cache(img_obj, proto, obj_type, way)
    res = get_image_from_cache(proto, obj_type, way)
    if res.nil? #and (img_obj.is_a? Gdk::Pixbuf)
      over_count = ($image_cache.size - ImageCacheSize)
      $image_cache.drop(over_count) if over_count>0
      #ind = [proto, obj_type, way]
      img_obj ||= false
      $image_cache << [proto, obj_type, way, img_obj]
      #p '--save_image_to_cache  [proto, obj_type, way, img_obj]='+[proto, obj_type, way, img_obj].inspect
    end
  end

  def self.del_image_from_cache(panhash, hex=nil)
    res = nil
    if panhash
      panhash_hex = panhash
      if hex
        panhash = PandoraUtils.hex_to_bytes(panhash_hex)
      else #raw format
        panhash_hex = PandoraUtils.bytes_to_hex(panhash)
      end
      $image_cache.delete_if do |e|
        res = false
        if e.is_a?(Array)
          way = e[2]
          res = ((way==panhash_hex) or (way==panhash))
        end
        res
      end
    end
    res
  end

  # Max smile name length
  # RU: Максимальная длина имени смайла
  MaxSmileName = 12

  # Obtain image pixbuf from URL
  # RU: Добывает pixbuf картинки по URL
  def self.get_image_from_url(url, err_text=true, pixbuf_parent=nil, def_proto=nil)
    def_proto ||= 'pandora'
    res = PandoraUtils.parse_url(url, def_proto)
    if res
      proto, obj_type, way = res
      res = get_image_from_cache(proto, obj_type, way)
      if res.nil?
        body = nil
        fn = nil
        if way and (way.size>0)
          if (proto=='pandora') or (proto=='sha1') or (proto=='md5') #and obj_type.nil?
            if (way.size>9) and PandoraUtils.hex?(way)
              sel = nil
              if (proto=='pandora')
                panhash = PandoraModel.hex_to_panhash(way)
                sel = PandoraModel.get_record_by_panhash(panhash, nil, nil, nil, 'blob')
              else
                hash = PandoraUtils.hex_to_bytes(way)
                sel = PandoraModel.get_record_by_hash(hash, nil, nil, nil, 'blob')
              end
              #p 'get_image_from_url.pandora/panhash='+panhash.inspect
              if sel and (sel.size>0)
                #type = sel[0][0]
                blob = sel[0][0]
                if blob and (blob.size>0)
                  if blob[0]=='@'
                    fn = blob[1..-1]
                    ext = nil
                    ext = File.extname(fn) if fn
                    if not (ext and (['.jpg','.jpeg','.gif','.png','.ico'].include?(ext.downcase)))
                      fn = nil
                    end
                  else
                    #body = blob
                    #need to search an image!
                  end
                end
              else
                if err_text
                  res = _('Cannot find image')+': '+proto+'='+PandoraUtils.bytes_to_hex(panhash)
                elsif err_text.is_a? FalseClass
                  res = $window.get_icon_buf('sad')
                end
              end
            elsif (way.size<=MaxSmileName)  #like a smile
              res = $window.get_icon_buf(way, obj_type)
            end
          elsif ((proto=='http') or (proto=='https'))
            fn = load_http_to_file(way)  #need realize!
          elsif proto=='smile'
            res = $window.get_icon_buf(way, obj_type)
          end
        end
        if body
          pixbuf_loader = Gdk::PixbufLoader.new
          pixbuf_loader.last_write(body)
          #res = pixbuf_loader.pixbuf
          res = pixbuf_loader.pixbuf
          #res = Gdk::Pixbuf.new(res, Gdk::Pixbuf::COLORSPACE_RGB, true, 8, width, height, width*4)
        elsif fn
          res = PandoraGtk.start_image_loading(fn, pixbuf_parent)
        end
        save_image_to_cache(res, proto, obj_type, way)
      end
      res = Gtk::Image.new(res) if (not pixbuf_parent) and (res.is_a? Gdk::Pixbuf)
    end
    res
  end

  def self.scale_buf_to_size(pixbuf, icon_size, center=false)
    if pixbuf
      w = pixbuf.width
      h = pixbuf.height
      w2, h2 = icon_size, icon_size
      if (h>h2) and (h >= w)
        w2 = w*h2/h
        pixbuf = pixbuf.scale(w2, h2)
      elsif w>w2
        h2 = h*w2/w
        pixbuf = pixbuf.scale(w2, h2)
      end
      if center and pixbuf
        w = pixbuf.width
        h = pixbuf.height
        asize = w
        asize = h if asize<h
        left = (asize - w)/2
        top  = (asize - h)/2
        qbuf = Gdk::Pixbuf.new(Gdk::Pixbuf::COLORSPACE_RGB, true, 8, asize, asize)
        qbuf.fill!(0xFFFFFF00)
        pixbuf.copy_area(0, 0, w, h, qbuf, left, top)
        pixbuf = qbuf
      end
    end
    pixbuf
  end

  # Obtain avatar icon by panhash
  # RU: Добыть иконку-аватар по панхэшу
  def self.get_avatar_icon(panhash, pixbuf_parent, its_blob=false, icon_size=16)
    pixbuf = nil
    avatar_hash = panhash
    if (not its_blob)
      avatar_hash = PandoraModel.find_relation(panhash, RK_AvatarFor, true)
    end
    if avatar_hash
      #p '--get_avatar_icon [its_blob, avatar_hash]='+[its_blob, avatar_hash].inspect
      proto = 'icon'
      obj_type = icon_size
      pixbuf = get_image_from_cache(proto, obj_type, avatar_hash)
      if pixbuf.nil?
        ava_url = 'pandora://'+PandoraUtils.bytes_to_hex(avatar_hash)
        pixbuf = PandoraModel.get_image_from_url(ava_url, nil, pixbuf_parent)
        #p 'pixbuf='+pixbuf.inspect
        if pixbuf
          pixbuf = scale_buf_to_size(pixbuf, icon_size)
        elsif its_blob
          pixbuf = get_avatar_icon(panhash, pixbuf_parent, nil, icon_size)
        end
        save_image_to_cache(pixbuf, proto, obj_type, avatar_hash) #if not its_blob.nil?
      end
    end
    pixbuf
  end

  # Predefined Pandora's codes of languages and Alpha-2
  # RU: Предустановленные коды языков Пандоры и Альфа-2
  Languages = {0=>'all', 1=>'en', 2=>'zh', 3=>'es', 4=>'hi', 5=>'ru', 6=>'ar', \
    7=>'fr', 8=>'pt', 9=>'ja', 10=>'de', 11=>'ko', 12=>'it', 13=>'be', 14=>'id', \
    15=>'ur', 16=>'te', 17=>'vi', 18=>'mr', 19=>'ta', 20=>'tr', 21=>'pl', 22=>'gu', \
    23=>'ms', 24=>'uk', 25=>'ma', 26=>'kn', 27=>'su', 28=>'my', 29=>'or', 30=>'fa', \
    31=>'pa', 32=>'ha', 33=>'tl', 34=>'ro', 35=>'nl', 36=>'sd', 37=>'th', 38=>'ps', \
    39=>'uz', 40=>'yo', 41=>'az', 42=>'ig', 43=>'am', 44=>'om', 45=>'as', 46=>'sr', \
    47=>'ku', 48=>'si', 49=>'za', 50=>'mg', 51=>'ne', 52=>'so', 53=>'km', 54=>'el', \
    55=>'hu', 56=>'ff', 57=>'ca', 58=>'sn', 59=>'zu', 60=>'qu', 61=>'cs', 62=>'bg', \
    63=>'ug', 64=>'ny', 65=>'be', 66=>'kk', 67=>'sv', 68=>'ak', 69=>'xh', 70=>'ht', \
    71=>'rw', 72=>'ki', 73=>'tk', 74=>'tt', 75=>'hy', 76=>'st', 77=>'kg', 78=>'sq', \
    79=>'ti', 80=>'mn', 81=>'ks', 82=>'da', 83=>'he', 84=>'sk', 85=>'fi', 86=>'af', \
    87=>'gn', 88=>'rn', 89=>'no', 90=>'tn', 91=>'tg', 92=>'ka', 93=>'lg', 94=>'wo', \
    95=>'kr', 96=>'ts', 97=>'gl', 98=>'lo', 99=>'lt', 100=>'ee', 101=>'si'}

  $lang_code_list = nil

  # Alpha-2 and Pancode codes of languages
  # RU: Коды языков Альфа-2 и панкод
  def self.lang_code_list(update=nil)
    if (not $lang_code_list) or update
      $lang_code_list = Languages.dup
      lang_model = PandoraUtils.get_model('Language')
      sel = lang_model.select(nil, false, 'pancode, alfa2', 'pancode ASC')
      if sel and (sel.size>0)
        sel.each do |row|
          pancode = row[0]
          alfa2 = row[1]
          if (pancode and alfa2)
            pancode = pancode.to_i
            $lang_code_list[pancode] ||= alfa2
          end
        end
      end
    end
    $lang_code_list
  end

  $lang_list = nil

  # Alpha-2 codes of languages
  # RU: Коды языков Альфа-2
  def self.lang_list(update=nil)
    if (not $lang_list) or update
      lcl = lang_code_list(update)
      $lang_list = lcl.values
    end
    $lang_list
  end

  # Get Alpha-2 with pancode of language
  # RU: Взять Альфа-2 по панкоду языка
  def self.lang_to_text(lang)
    res = lang_code_list[lang]
    res ||= ''
  end

  # Get language pancode with Alpha-2
  # RU: Взять панкод языка по Альфа-2
  def self.text_to_lang(text)
    text = text.downcase if text.is_a? String
    res = lang_code_list.detect{ |n,v| v==text }
    res = res[0] if res
    res ||= 0
  end

  # Relation kinds
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
  RK_AvatarFor  = 9
  RK_MinPublic = 235
  RK_MaxPublic = 255

  # Relation kind names
  # RU: Имена видов связей
  RelationNames = [
    [RK_Unknown,    'Unknown'],
    [RK_Equal,      'Equal'],
    [RK_Similar,    'Similar'],
    [RK_Antipod,    'Antipod'],
    [RK_PartOf,     'Part of'],
    [RK_Cause,      'Cause'],
    [RK_Follow,     'Following'],
    [RK_Ignore,     'Ignoring'],
    [RK_CameFrom,   'Came from'],
    [RK_AvatarFor,  'Avatar for'],
    [RK_MinPublic,  'Public']
  ]

  # Task Mode Names
  # RU: Имена режимов задачника
  TaskModeNames = [
    [0,      'Off'],
    [1,      'On']
  ]

  # Relation is symmetric
  # RU: Связь симметрична
  def self.relation_is_symmetric?(relation)
    res = [RK_Equal, RK_Similar, RK_Unknown].include? relation
  end

  # Check, create or delete relation between two panobjects
  # RU: Проверяет, создаёт или удаляет связь между двумя объектами
  def self.act_relation(panhash1, panhash2, rel_kind=RK_Unknown, act=:check, \
  creator_for_nil=true, init=false, models=nil)
    res = nil
    if panhash1 or panhash2
      creator = nil
      if panhash1.nil? or panhash2.nil?
        if creator_for_nil
          creator = PandoraCrypto.current_user_or_key(true, init)
        end
        if panhash1.nil?
          panhash1 = creator
        else
          panhash2 = creator
        end
      end
      if panhash1 and panhash2 #and (panhash1 != panhash2)
        #p 'relat [p1,p2,t]='+[PandoraUtils.bytes_to_hex(panhash1), PandoraUtils.bytes_to_hex(panhash2), rel_kind.inspect
        relation_model = PandoraUtils.get_model('Relation', models)
        if relation_model
          kind_op = '='
          pub_kind = (rel_kind >= RK_MinPublic)
          if pub_kind
            rel_kind = RK_MinPublic if (act == :check)
            kind_op = '>=' if (act != :create)
          end
          kind_op = 'kind' + kind_op
          filter1 = [['first=', panhash1], ['second=', panhash2], [kind_op, rel_kind]]
          filter2 = nil
          if relation_is_symmetric?(rel_kind) and (panhash1 != panhash2)
            filter2 = [['first=', panhash2], ['second=', panhash1], [kind_op, rel_kind]]
          end
          #p 'relat2 [p1,p2,t]='+[PandoraUtils.bytes_to_hex(panhash1), PandoraUtils.bytes_to_hex(panhash2), rel_kind].inspect
          #p 'act='+act.inspect
          if (act == :delete)
            res = relation_model.update(nil, nil, filter1)
            if filter2
              res2 = relation_model.update(nil, nil, filter2)
              res = (res or res2)
            end
          else #check or create
            flds = 'id'
            flds << ',kind' if pub_kind
            sel = relation_model.select(filter1, false, flds, 'modified DESC', 1)
            exist = (sel and (sel.size>0))
            if (not exist) and filter2
              sel = relation_model.select(filter2, false, flds, 'modified DESC', 1)
              exist = (sel and (sel.size>0))
            end
            res = exist
            res = sel[0][1] if pub_kind and exist
            if (not exist) and (act == :create)
              if filter2 and (panhash1>panhash2) #low panhash must be first in symmetric relation
                filter1 = filter2
              end
              panstate = 0
              values = {}
              first = filter1[0][1]
              second = filter1[1][1]
              values['first'] = first
              values['second'] = second
              values['kind'] = filter1[2][1]
              panhash = relation_model.calc_panhash(values, 0)
              values['panhash'] = panhash
              values['modified'] = Time.now.to_i
              creator ||= PandoraCrypto.current_user_or_key(true, false)
              if creator and ((first==creator) or (second==creator))
                panstate = PandoraModel::PSF_Support
              end
              values['panstate'] = panstate
              res = relation_model.update(values, nil, nil)
            end
          end
        end
      end
    end
    res
  end

  # Find relation with the kind with highest rate
  # RU: Ищет связь для сорта с максимальным рейтингом
  def self.find_relation(panhash, rel_kind=nil, second=nil, models=nil)
    res = nil
    relation_model = PandoraUtils.get_model('Relation', models)
    if relation_model
      sel = nil
      exist = nil
      if not second
        filter = [['first=', panhash], ['kind=', rel_kind]]
        flds = 'id,second'
        sel = relation_model.select(filter, false, flds, 'modified DESC', 1)
        exist = (sel and (sel.size>0))
      end
      if (not exist) and (second or relation_is_symmetric?(rel_kind))
        filter = [['second=', panhash], ['kind=', rel_kind]]
        flds = 'id,first'
        sel = relation_model.select(filter, false, flds, 'modified DESC', 1)
        exist = (sel and (sel.size>0))
      end
      res = exist
      res = sel[0][1] if exist
    end
    res
  end

  def self.remove_all_relations(panhash, creator_for_nil=true, init=false, \
  models=nil, unsign=true)
    act_relation(nil, panhash, RK_Ignore, :delete, creator_for_nil, init, models)
    act_relation(nil, panhash, RK_Follow, :delete, creator_for_nil, init, models)
    act_relation(nil, panhash, RK_MinPublic, :delete, creator_for_nil, init, models)
    PandoraCrypto.unsign_panobject(panhash, true) if unsign
  end

  # Panobject state flags
  # RU: Флаги состояния объекта/записи
  PSF_Support    = 1      # must keep on this node (else will be deleted by GC)
  PSF_Verified   = 2      # signature was verified
  PSF_Crypted    = 4      # record is encrypted
  PSF_BlockWeb   = 8     # record is in BlockWeb
  PSF_ChatMes    = 16      # chat message (not dialog)
  PSF_SentOut    = 32      # record has went outside of node
  PSF_Harvest    = 64     # download by pieces in progress
  PSF_Archive    = 128    # marked to delete

end


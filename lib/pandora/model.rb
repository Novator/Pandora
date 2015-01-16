module Pandora
  module Model
    include Pandora::Constants

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
                if not panobject_class #not PandoraModel.const_defined? panobj_id
                  parent_class = element.attributes['parent']
                  if (not parent_class) or (parent_class=='') or (not (Pandora::Model.const_defined? parent_class))
                    if parent_class
                      puts _('Parent is not defined, ignored')+' /'+filename+':'+panobj_id+'<'+parent_class
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
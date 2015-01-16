module Pandora
  # ====================================================================
  # Utilites class of Pandora
  # RU: Вспомогательный класс Пандоры
  class Utils

    # Platform detection
    # RU: Определение платформы
    def self.os_family
      case RUBY_PLATFORM
        when /ix/i, /ux/i, /gnu/i, /sysv/i, /solaris/i, /sunos/i, /bsd/i
          'unix'
        when /win/i, /ming/i
          'windows'
        else
          'other'
      end
    end

    # Load translated phrases
    # RU: Загрузить переводы фраз
    def self.load_language(lang='ru')

      def self.unslash_quotes(str)
        str ||= ''
        str.gsub('\"', '"')
      end

      def self.addline(str, line)
        line = unslash_quotes(line)
        if (not str) or (str=='')
          str = line
        else
          str = str.to_s + "\n" + line.to_s
        end
        str
      end

      def self.spaces_after?(line, pos)
        i = line.size-1
        while (i>=pos) and ((line[i, 1]==' ') or (line[i, 1]=="\t"))
          i -= 1
        end
        (i<pos)
      end

      $lang_trans = {}
      langfile = File.join(Pandora.lang_dir, lang +'.txt')
      if File.exist?(langfile)
        scanmode = 0
        frase = ''
        trans = ''
        IO.foreach(langfile) do |line|
          if (line.is_a? String) and (line.size>0)
            #line = line[0..-2] if line[-1,1]=="\n"
            #line = line[0..-2] if line[-1,1]=="\r"
            line.chomp!
            end_is_found = false
            if scanmode==0
              end_is_found = true
              if (line.size>0) and (line[0, 1] != '#')
                if line[0, 1] != '"'
                  frase, trans = line.split('=>')
                  $lang_trans[frase] = trans if (frase != '') and (trans != '')
                else
                  line = line[1..-1]
                  frase = ''
                  trans = ''
                  end_is_found = false
                end
              end
            end

            if not end_is_found
              if scanmode<2
                i = line.index('"=>"')
                if i
                  frase = addline(frase, line[0, i])
                  line = line[i+4, line.size-i-4]
                  scanmode = 2 #composing a trans
                else
                  scanmode = 1 #composing a frase
                end
              end
              if scanmode==2
                k = line.rindex('"')
                if k and ((k==0) or (line[k-1, 1] != "\\"))
                  end_is_found = ((k+1)==line.size) or spaces_after?(line, k+1)
                  if end_is_found
                    trans = addline(trans, line[0, k])
                  end
                end
              end

              if end_is_found
                $lang_trans[frase] = trans if (frase != '') and (trans != '')
                scanmode = 0
              else
                if scanmode < 2
                  frase = addline(frase, line)
                  scanmode = 1 #composing a frase
                else
                  trans = addline(trans, line)
                end
              end
            end
          end
        end
      end
    end

  end
end
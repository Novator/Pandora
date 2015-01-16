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

  end
end
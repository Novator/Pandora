module Pandora
  module Gtk

    # Profile panel
    # RU: Панель профиля
    class ProfileScrollWin < ::Gtk::ScrolledWindow
      attr_accessor :person

      include Pandora::Gtk

      # Show profile window
      # RU: Показать окно профиля
      def initialize(a_person=nil)
        super(nil, nil)

        @person = a_person

        set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        border_width = 0

        #self.add_with_viewport(vpaned)
      end
    end

  end
end
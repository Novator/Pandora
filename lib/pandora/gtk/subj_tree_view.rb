module Pandora
  module Gtk

    # Grid for panobjects
    # RU: Таблица для объектов Пандоры
    class SubjTreeView < ::Gtk::TreeView
      attr_accessor :panobject, :sel, :notebook, :auto_create
    end

    # Column for SubjTreeView
    # RU: Колонка для SubjTreeView
    class SubjTreeViewColumn < ::Gtk::TreeViewColumn
      attr_accessor :tab_ind
    end

  end
end
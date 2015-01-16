module Pandora
  module Gtk

    # List of session
    # RU: Список сеансов
    class SessionScrollWin < ::Gtk::ScrolledWindow
      attr_accessor :update_btn

      include Pandora::Gtk

      # Show session window
      # RU: Показать окно сессий
      def initialize(session=nil)
        super(nil, nil)

        set_policy(::Gtk::POLICY_AUTOMATIC, ::Gtk::POLICY_AUTOMATIC)
        border_width = 0

        vbox = ::Gtk::VBox.new
        hbox = ::Gtk::HBox.new

        title = _('Update')
        @update_btn = ::Gtk::ToolButton.new(::Gtk::Stock::REFRESH, title)
        update_btn.tooltip_text = title
        update_btn.label = title

        hunted_btn = SafeCheckButton.new(_('hunted'), true)
        hunted_btn.safe_signal_clicked do |widget|
          update_btn.clicked
        end
        hunted_btn.safe_set_active(true)

        hunters_btn = SafeCheckButton.new(_('hunters'), true)
        hunters_btn.safe_signal_clicked do |widget|
          update_btn.clicked
        end
        hunters_btn.safe_set_active(true)

        fishers_btn = SafeCheckButton.new(_('fishers'), true)
        fishers_btn.safe_signal_clicked do |widget|
          update_btn.clicked
        end
        fishers_btn.safe_set_active(true)

        title = _('Delete')
        delete_btn = ::Gtk::ToolButton.new(::Gtk::Stock::DELETE, title)
        delete_btn.tooltip_text = title
        delete_btn.label = title

        hbox.pack_start(hunted_btn, false, true, 0)
        hbox.pack_start(hunters_btn, false, true, 0)
        hbox.pack_start(fishers_btn, false, true, 0)
        hbox.pack_start(update_btn, false, true, 0)
        hbox.pack_start(delete_btn, false, true, 0)

        list_sw = ::Gtk::ScrolledWindow.new(nil, nil)
        list_sw.shadow_type = ::Gtk::SHADOW_ETCHED_IN
        list_sw.set_policy(::Gtk::POLICY_NEVER, ::Gtk::POLICY_AUTOMATIC)

        list_store = ::Gtk::ListStore.new(String, String, String, String, Integer, Integer, \
          Integer, Integer, Integer)
        update_btn.signal_connect('clicked') do |*args|
          list_store.clear
          $window.pool.sessions.each do |session|
            hunter = ((session.conn_mode & PandoraNet::CM_Hunter)>0)
            if ((hunted_btn.active? and (not hunter)) \
            or (hunters_btn.active? and hunter) \
            or (fishers_btn.active? and session.donor))
              sess_iter = list_store.append
              sess_iter[0] = $window.pool.sessions.index(session).to_s
              sess_iter[1] = session.host_ip.to_s
              sess_iter[2] = session.port.to_s
              sess_iter[3] = PandoraUtils.bytes_to_hex(session.node_panhash)
              sess_iter[4] = session.conn_mode
              sess_iter[5] = session.conn_state
              sess_iter[6] = session.stage
              sess_iter[7] = session.read_state
              sess_iter[8] = session.send_state
            end

            #:host_name, :host_ip, :port, :proto, :node, :conn_mode, :conn_state,
            #:stage, :dialog, :send_thread, :read_thread, :socket, :read_state, :send_state,
            #:donor, :fisher_lure, :fish_lure, :send_models, :recv_models, :sindex,
            #:read_queue, :send_queue, :confirm_queue, :params, :rcmd, :rcode, :rdata,
            #:scmd, :scode, :sbuf, :log_mes, :skey, :rkey, :s_encode, :r_encode, :media_send,
            #:node_id, :node_panhash, :entered_captcha, :captcha_sw, :fishes, :fishers
          end
        end

        # create tree view
        list_tree = ::Gtk::TreeView.new(list_store)
        #list_tree.rules_hint = true
        #list_tree.search_column = CL_Name

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new('№', renderer, 'text' => 0)
        column.set_sort_column_id(0)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('Ip'), renderer, 'text' => 1)
        column.set_sort_column_id(1)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('Port'), renderer, 'text' => 2)
        column.set_sort_column_id(2)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('Node'), renderer, 'text' => 3)
        column.set_sort_column_id(3)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('conn_mode'), renderer, 'text' => 4)
        column.set_sort_column_id(4)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('conn_state'), renderer, 'text' => 5)
        column.set_sort_column_id(5)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('stage'), renderer, 'text' => 6)
        column.set_sort_column_id(6)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('read_state'), renderer, 'text' => 7)
        column.set_sort_column_id(7)
        list_tree.append_column(column)

        renderer = ::Gtk::CellRendererText.new
        column = ::Gtk::TreeViewColumn.new(_('send_state'), renderer, 'text' => 8)
        column.set_sort_column_id(8)
        list_tree.append_column(column)

        list_tree.signal_connect('row_activated') do |tree_view, path, column|
          # download and go to record
        end

        list_sw.add(list_tree)

        vbox.pack_start(hbox, false, true, 0)
        vbox.pack_start(list_sw, true, true, 0)
        list_sw.show_all

        self.add_with_viewport(vbox)
        update_btn.clicked

        list_tree.grab_focus
      end
    end

  end
end
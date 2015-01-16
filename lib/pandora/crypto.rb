require 'openssl'

# ====================================================================
# Cryptography module of Pandora
# RU: Криптографический модуль Пандоры
module Pandora
  module Crypto
    KH_None   = 0
    KH_Md5    = 0x1
    KH_Sha1   = 0x2
    KH_Sha2   = 0x3
    KH_Sha3   = 0x4
    KH_Rmd    = 0x5

    KT_None = 0
    KT_Rsa  = 0x1
    KT_Dsa  = 0x2
    KT_Aes  = 0x6
    KT_Des  = 0x7
    KT_Bf   = 0x8
    KT_Priv = 0xF

    KL_None    = 0
    KL_bit128  = 0x10   # 16 byte
    KL_bit160  = 0x20   # 20 byte
    KL_bit224  = 0x30   # 28 byte
    KL_bit256  = 0x40   # 32 byte
    KL_bit384  = 0x50   # 48 byte
    KL_bit512  = 0x60   # 64 byte
    KL_bit1024 = 0x70   # 128 byte
    KL_bit2048 = 0x80   # 256 byte
    KL_bit4096 = 0x90   # 512 byte

    KL_BitLens = [128, 160, 224, 256, 384, 512, 1024, 2048, 4096]

    # Key length code to byte length
    # RU: Код длины ключа в байтовую длину
    def self.klen_to_bitlen(len)
      res = nil
      ind = len >> 4
      res = KL_BitLens[ind-1] if ind and (ind>0) and (ind<=KL_BitLens.size)
      res
    end

    # Byte length of key to code
    # RU: Байтовая длина ключа в код длины
    def self.bitlen_to_klen(len)
      res = KL_None
      ind = KL_BitLens.index(len)
      res = KL_BitLens[ind] << 4 if ind
      res
    end

    # Divide type and code of length
    # RU: Разделить тип и код длины
    def self.divide_type_and_klen(tnl)
      tnl = 0 if not tnl.is_a? Integer
      type = tnl & 0x0F
      klen  = tnl & 0xF0
      [type, klen]
    end

    # Encode method codes of cipher and hash
    # RU: Упаковать коды методов шифровки и хэширования
    def self.encode_cipher_and_hash(cipher, hash)
      res = cipher & 0xFF | ((hash & 0xFF) << 8)
    end

    # Decode method codes of cipher and hash
    # RU: Распаковать коды методов шифровки и хэширования
    def self.decode_cipher_and_hash(cnh)
      cipher = cnh & 0xFF
      hash  = (cnh >> 8) & 0xFF
      [cipher, hash]
    end

    # Get OpenSSL object by Pandora code of hash
    # RU: Получает объект OpenSSL по коду хэша Пандоры
    def self.pan_kh_to_openssl_hash(hash_len)
      res = nil
      #p 'hash_len='+hash_len.inspect
      hash, klen = divide_type_and_klen(hash_len)
      #p '[hash, klen]='+[hash, klen].inspect
      case hash
        when KH_Md5
          res = OpenSSL::Digest::MD5.new
        when KH_Sha1
          res = OpenSSL::Digest::SHA1.new
        when KH_Rmd
          res = OpenSSL::Digest::RIPEMD160.new
        when KH_Sha2
          case klen
            when KL_bit256
              res = OpenSSL::Digest::SHA256.new
            when KL_bit224
              res = OpenSSL::Digest::SHA224.new
            when KL_bit384
              res = OpenSSL::Digest::SHA384.new
            when KL_bit512
              res = OpenSSL::Digest::SHA512.new
            else
              res = OpenSSL::Digest::SHA256.new
          end
        when KH_Sha3
          case klen
            when KL_bit256
              res = SHA3::Digest::SHA256.new
            when KL_bit224
              res = SHA3::Digest::SHA224.new
            when KL_bit384
              res = SHA3::Digest::SHA384.new
            when KL_bit512
              res = SHA3::Digest::SHA512.new
            else
              res = SHA3::Digest::SHA256.new
          end
      end
      res
    end

    # Convert Pandora type of hash to OpenSSL name
    # RU: Преобразует тип хэша Пандоры в имя OpenSSL
    def self.pankt_to_openssl(type)
      res = nil
      case type
        when KT_Rsa
          res = 'RSA'
        when KT_Dsa
          res = 'DSA'
        when KT_Aes
          res = 'AES'
        when KT_Des
          res = 'DES'
        when KT_Bf
          res = 'BF'
      end
      res
    end

    # Convert Pandora type of hash to OpenSSL string
    # RU: Преобразует тип хэша Пандоры в строку OpenSSL
    def self.pankt_len_to_full_openssl(type, len, mode=nil)
      res = pankt_to_openssl(type)
      res += '-'+len.to_s if len
      mode ||= 'CFB'  #'CBC - cicle block, OFB - cicle pseudo, CFB - block+pseudo
      res += '-'+mode
    end

    RSA_exponent = 65537

    KV_Obj   = 0
    KV_Pub   = 1
    KV_Priv  = 2
    KV_Kind  = 3
    KV_Cipher  = 4
    KV_Pass  = 5
    KV_Panhash = 6
    KV_Creator = 7
    KV_Trust   = 8
    KV_NameFamily  = 9

    KS_Exchange  = 1
    KS_Voucher   = 2

    # Encode or decode key
    # RU: Зашифровать или расшифровать ключ
    def self.key_recrypt(data, encode=true, cipher_hash=nil, cipherkey=nil)
      #p '^^^^^^^^^^^^sym_recrypt: [cipher_hash, passwd]='+[cipher_hash, cipherkey].inspect
      #cipher_hash ||= encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
      if cipher_hash and (cipher_hash != 0) and data
        ckind, chash = decode_cipher_and_hash(cipher_hash)
        if (chash == KH_None)
          key_vec = current_key(false, true)
          if key_vec and key_vec[KV_Obj] and key_vec[KV_Panhash]
            if encode
              data = recrypt(key_vec, data, encode)
              if data
                key_and_data = PandoraUtils.rubyobj_to_pson_elem([key_vec[KV_Panhash], data])
                data = key_and_data
              end
            else
              key_and_data, len = PandoraUtils.pson_elem_to_rubyobj(data)
              if key_and_data.is_a? Array
                keyhash, data = key_and_data
                if (keyhash == key_vec[KV_Panhash])
                  data = recrypt(key_vec, data, encode)
                else
                  data = nil
                end
              else
                Pandora.logger.warn  _('Bad data encrypted on key')
                data = nil
              end
            end
          else
            data = nil
          end
        else
          hash = pan_kh_to_openssl_hash(chash)
          #p 'hash='+hash.inspect
          cipherkey ||= ''
          cipherkey = hash.digest(cipherkey) if hash
          #p 'cipherkey.hash='+cipherkey.inspect
          cipher_vec = Array.new
          cipher_vec[KV_Priv] = cipherkey
          cipher_vec[KV_Kind] = ckind
          cipher_vec = init_key(cipher_vec)
          key = cipher_vec[KV_Obj]
          if key
            iv = nil
            if encode
              iv = key.random_iv
            else
              data, len = PandoraUtils.pson_elem_to_rubyobj(data)   # pson to array
              if data.is_a? Array
                iv = AsciiString.new(data[1])
                data = AsciiString.new(data[0])  # data from array
              else
                data = nil
              end
            end
            cipher_vec[KV_Pub] = iv
            data = recrypt(cipher_vec, data, encode) if data
            data = PandoraUtils.rubyobj_to_pson_elem([data, iv]) if encode and data
          end
        end
      end
      data = AsciiString.new(data) if data
      data
    end

    # Generate a key or key pair
    # RU: Генерирует ключ или ключевую пару
    def self.generate_key(type_klen = KT_Rsa | KL_bit2048, cipher_hash=nil, cipherkey=nil)
      key = nil
      keypub = nil
      keypriv = nil

      type, klen = divide_type_and_klen(type_klen)
      bitlen = klen_to_bitlen(klen)

      case type
        when KT_Rsa
          bitlen ||= 2048
          bitlen = 2048 if bitlen <= 0
          key = OpenSSL::PKey::RSA.generate(bitlen, RSA_exponent)

          #keypub = ''
          #keypub.force_encoding('ASCII-8BIT')
          #keypriv = ''
          #keypriv.force_encoding('ASCII-8BIT')
          keypub = AsciiString.new(PandoraUtils.bigint_to_bytes(key.params['n']))
          keypriv = AsciiString.new(PandoraUtils.bigint_to_bytes(key.params['p']))
          #p keypub = key.params['n']
          #keypriv = key.params['p']
          #p PandoraUtils.bytes_to_bigin(keypub)
          #p '************8'

          #puts key.to_text
          #p key.params

          #key_der = key.to_der
          #p key_der.size

          #key = OpenSSL::PKey::RSA.new(key_der)
          #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
        else #симметричный ключ
          #p OpenSSL::Cipher::ciphers
          key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
          keypub  = key.random_iv
          keypriv = key.random_key
          #p keypub.size
          #p keypriv.size
      end
      keypriv = key_recrypt(keypriv, true, cipher_hash, cipherkey)
      [key, keypub, keypriv, type_klen, cipher_hash, cipherkey]
    end

    # Init key or key pair
    # RU: Инициализирует ключ или ключевую пару
    def self.init_key(key_vec)
      key = key_vec[KV_Obj]
      if not key
        keypub  = key_vec[KV_Pub]
        keypriv = key_vec[KV_Priv]
        keypriv = AsciiString.new(keypriv) if keypriv
        keypub  = AsciiString.new(keypub) if keypub
        type_klen = key_vec[KV_Kind]
        cipher_hash = key_vec[KV_Cipher]
        pass = key_vec[KV_Pass]
        type, klen = divide_type_and_klen(type_klen)
        #p [type, klen]
        bitlen = klen_to_bitlen(klen)
        case type
          when KT_None
            key = nil
          when KT_Rsa
            #p '------'
            #p key.params
            n = PandoraUtils.bytes_to_bigint(keypub)
            #p 'n='+n.inspect
            e = OpenSSL::BN.new(RSA_exponent.to_s)
            p0 = nil
            if keypriv
              #p '[cipher, keypriv]='+[cipher, keypriv].inspect
              keypriv = key_recrypt(keypriv, false, cipher_hash, pass)
              #p 'key2='+key2.inspect
              p0 = PandoraUtils.bytes_to_bigint(keypriv) if keypriv
            else
              p0 = 0
            end

            if p0
              pass = 0
              #p 'n='+n.inspect+'  p='+p0.inspect+'  e='+e.inspect
              begin
                if keypriv
                  q = (n / p0)[0]
                  p0,q = q,p0 if p0 < q
                  d = e.mod_inverse((p0-1)*(q-1))
                  dmp1 = d % (p0-1)
                  dmq1 = d % (q-1)
                  iqmp = q.mod_inverse(p0)

                  #p '[n,d,dmp1,dmq1,iqmp]='+[n,d,dmp1,dmq1,iqmp].inspect

                  seq = OpenSSL::ASN1::Sequence([
                    OpenSSL::ASN1::Integer(pass),
                    OpenSSL::ASN1::Integer(n),
                    OpenSSL::ASN1::Integer(e),
                    OpenSSL::ASN1::Integer(d),
                    OpenSSL::ASN1::Integer(p0),
                    OpenSSL::ASN1::Integer(q),
                    OpenSSL::ASN1::Integer(dmp1),
                    OpenSSL::ASN1::Integer(dmq1),
                    OpenSSL::ASN1::Integer(iqmp)
                  ])
                else
                  seq = OpenSSL::ASN1::Sequence([
                    OpenSSL::ASN1::Integer(n),
                    OpenSSL::ASN1::Integer(e),
                  ])
                end

                #p asn_seq = OpenSSL::ASN1.decode(key)
                # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
                #seq1 = asn_seq.value[1]
                #str_val = PandoraUtils.bigint_to_bytes(seq1.value)
                #p 'str_val.size='+str_val.size.to_s
                #p Base64.encode64(str_val)
                #key2 = key.public_key
                #p key2.to_der.size
                # Seq: Int:n, Int:e
                #p 'pub_seq='+asn_seq2 = OpenSSL::ASN1.decode(key.public_key.to_der).inspect
                #p key2.to_s

                # Seq: Int:pass, Int:n, Int:e, Int:d, Int:p, Int:q, Int:dmp1, Int:dmq1, Int:iqmp
                key = OpenSSL::PKey::RSA.new(seq.to_der)
                #p key.params
              rescue
                key = nil
              end
            end
          when KT_Dsa
            seq = OpenSSL::ASN1::Sequence([
              OpenSSL::ASN1::Integer(0),
              OpenSSL::ASN1::Integer(key.p),
              OpenSSL::ASN1::Integer(key.q),
              OpenSSL::ASN1::Integer(key.g),
              OpenSSL::ASN1::Integer(key.pub_key),
              OpenSSL::ASN1::Integer(key.priv_key)
            ])
          else
            key = OpenSSL::Cipher.new(pankt_len_to_full_openssl(type, bitlen))
            key.key = keypriv
            key.iv  = keypub if keypub
        end
        key_vec[KV_Obj] = key
      end
      key_vec
    end

    # Create sign
    # RU: Создает подпись
    def self.make_sign(key, data, hash_len=KH_Sha2 | KL_bit256)
      sign = nil
      begin
        sign = key[KV_Obj].sign(pan_kh_to_openssl_hash(hash_len), data) if key[KV_Obj]
      rescue
        sign = nil
      end
      sign
    end

    # Verify sign
    # RU: Проверяет подпись
    def self.verify_sign(key, data, sign, hash_len=KH_Sha2 | KL_bit256)
      res = false
      res = key[KV_Obj].verify(pan_kh_to_openssl_hash(hash_len), sign, data) if key[KV_Obj]
      res
    end

    #def self.encode_pan_cryptomix(type, cipher, hash)
    #  mix = type & 0xFF | (cipher << 8) & 0xFF | (hash << 16) & 0xFF
    #end

    #def self.decode_pan_cryptomix(mix)
    #  type = mix & 0xFF
    #  cipher = (mix >> 8) & 0xFF
    #  hash = (mix >> 16) & 0xFF
    #  [type, cipher, hash]
    #end

    #def self.detect_key(key)
    #  [key, type, klen, cipher, hash, hlen]
    #end

    # Encode or decode data
    # RU: Зашифровывает или расшифровывает данные
    def self.recrypt(key_vec, data, encrypt=true, private=false)
      recrypted = nil
      key = key_vec[KV_Obj]
      #p 'encrypt key='+key.inspect
      if key.is_a? OpenSSL::Cipher
        if data
          data = AsciiString.new(data)
          key.reset
          if encrypt
            key.encrypt
          else
            key.decrypt
          end
          key.key = key_vec[KV_Priv]
          key.iv = key_vec[KV_Pub] if key_vec[KV_Pub]
          begin
            recrypted = key.update(data) + key.final
          rescue
            recrypted = nil
          end
        end
      else  #elsif key.is_a? OpenSSL::PKey
        if encrypt
          if private
            recrypted = key.private_encrypt(data)
          else
            recrypted = key.public_encrypt(data)
          end
        else
          if private
            recrypted = key.private_decrypt(data)
          else
            recrypted = key.public_decrypt(data)
          end
        end
      end
      recrypted
    end

    # Deactivate current or target key
    # RU: Деактивирует текущий или указанный ключ
    def self.deactivate_key(key_vec)
      if key_vec.is_a? Array
        PandoraUtils.fill_by_zeros(key_vec[PandoraCrypto::KV_Priv])  #private key
        PandoraUtils.fill_by_zeros(key_vec[PandoraCrypto::KV_Pass])
        key_vec.each_index do |i|
          key_vec[i] = nil
        end
      end
      key_vec = nil
    end

    class << self
      attr_accessor :the_current_key
    end

    # Deactivate current key
    # RU: Деактивирует текущий ключ
    def self.reset_current_key
      self.the_current_key = deactivate_key(self.the_current_key)
      $window.set_status_field(PandoraGtk::SF_Auth, 'Not logged', nil, false)
      self.the_current_key
    end

    $first_key_init = true

    # Return current key or allow to choose and activate a key
    # RU: Возвращает текущий ключ или позволяет выбрать и активировать ключ
    def self.current_key(switch_key=false, need_init=true)

      # Read a key from database
      # RU: Считывает ключ из базы
      def self.read_key(panhash, passwd, key_model)
        key_vec = nil
        cipher = nil
        if panhash and (panhash != '')
          filter = {:panhash => panhash}
          sel = key_model.select(filter, false)
          if sel and (sel.size>1)
            kind0 = key_model.field_val('kind', sel[0])
            kind1 = key_model.field_val('kind', sel[1])
            body0 = key_model.field_val('body', sel[0])
            body1 = key_model.field_val('body', sel[1])

            type0, klen0 = divide_type_and_klen(kind0)
            cipher = 0
            if type0==KT_Priv
              priv = body0
              pub = body1
              kind = kind1
              cipher = key_model.field_val('cipher', sel[0])
              creator = key_model.field_val('creator', sel[0])
            else
              priv = body1
              pub = body0
              kind = kind0
              cipher = key_model.field_val('cipher', sel[1])
              creator = key_model.field_val('creator', sel[1])
            end
            key_vec = Array.new
            key_vec[KV_Pub] = pub
            key_vec[KV_Priv] = priv
            key_vec[KV_Cipher] = cipher
            key_vec[KV_Kind] = kind
            key_vec[KV_Pass] = passwd
            key_vec[KV_Panhash] = panhash
            key_vec[KV_Creator] = creator
            cipher ||= 0
          end
        end
        [key_vec, cipher]
      end

      # Recode a key
      # RU: Перекодирует ключ
      def self.recrypt_key(key_model, key_vec, cipher, panhash, passwd, newpasswd)
        if not key_vec
          key_vec, cipher = read_key(panhash, passwd, key_model)
        end
        if key_vec
          key2 = key_vec[KV_Priv]
          cipher = key_vec[KV_Cipher]
          #type_klen = key_vec[KV_Kind]
          #type, klen = divide_type_and_klen(type_klen)
          #bitlen = klen_to_bitlen(klen)
          if key2
            key2 = key_recrypt(key2, false, cipher, passwd)
            if key2
              cipher_hash = 0
              if newpasswd and (newpasswd.size>0)
                cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
              end
              key2 = key_recrypt(key2, true, cipher_hash, newpasswd)
              if key2
                time_now = Time.now.to_i
                filter = {:panhash=>panhash, :kind=>KT_Priv}
                panstate = PandoraModel::PSF_Support
                values = {:panstate=>panstate, :cipher=>cipher_hash, :body=>key2, :modified=>time_now}
                res = key_model.update(values, nil, filter)
                if res
                  key_vec[KV_Priv] = key2
                  key_vec[KV_Cipher] = cipher_hash
                  passwd = newpasswd
                end
              end
            end
          end
        end
        [key_vec, cipher, passwd]
      end

      # body of current_key

      key_vec = self.the_current_key
      if key_vec and switch_key
        key_vec = reset_current_key
      elsif (not key_vec) and need_init
        getting = true
        last_auth_key = Pandora::Utils.get_param('last_auth_key')
        last_auth_key0 = last_auth_key
        if last_auth_key.is_a? Integer
          last_auth_key = AsciiString.new(PandoraUtils.bigint_to_bytes(last_auth_key))
        end
        passwd = nil
        key_model = Pandora::Utils.get_model('Key')
        while getting
          creator = nil
          filter = {:kind => 0xF}
          sel = key_model.select(filter, false, 'id', nil, 1)
          if sel and (sel.size>0)
            getting = false
            key_vec, cipher = read_key(last_auth_key, passwd, key_model)
            #p '[key_vec, cipher]='+[key_vec, cipher].inspect
            if (not key_vec) or (not cipher) or (cipher != 0) or (not $first_key_init)
              dialog = PandoraGtk::AdvancedDialog.new(_('Key init'))
              dialog.set_default_size(420, 190)

              vbox = Gtk::VBox.new
              dialog.viewport.add(vbox)

              label = Gtk::Label.new(_('Key'))
              vbox.pack_start(label, false, false, 2)
              key_entry = PandoraGtk::PanhashBox.new('Panhash(Key)')
              key_entry.text = PandoraUtils.bytes_to_hex(last_auth_key)
              #key_entry.editable = false
              vbox.pack_start(key_entry, false, false, 2)

              label = Gtk::Label.new(_('Password'))
              vbox.pack_start(label, false, false, 2)
              pass_entry = Gtk::Entry.new
              pass_entry.visibility = false
              if (not cipher) or (cipher == 0)
                pass_entry.editable = false
                pass_entry.sensitive = false
              end
              pass_entry.width_request = 200
              align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
              align.add(pass_entry)
              vbox.pack_start(align, false, false, 2)

              new_label = nil
              new_pass_entry = nil
              new_align = nil

              if key_entry.text == ''
                dialog.def_widget = key_entry.entry
              else
                dialog.def_widget = pass_entry
              end

              changebtn = PandoraGtk::SafeToggleToolButton.new(Gtk::Stock::EDIT)
              changebtn.tooltip_text = _('Change password')
              changebtn.safe_signal_clicked do |*args|
                if not new_label
                  new_label = Gtk::Label.new(_('New password'))
                  vbox.pack_start(new_label, false, false, 2)
                  new_pass_entry = Gtk::Entry.new
                  new_pass_entry.width_request = 200
                  new_align = Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
                  new_align.add(new_pass_entry)
                  vbox.pack_start(new_align, false, false, 2)
                  new_align.show_all
                end
                new_label.visible = changebtn.active?
                new_align.visible = changebtn.active?
                if changebtn.active?
                  #dialog.set_size_request(420, 250)
                  dialog.resize(420, 240)
                else
                  dialog.resize(420, 190)
                end
              end
              dialog.hbox.pack_start(changebtn, false, false, 0)

              gen_button = Gtk::ToolButton.new(Gtk::Stock::NEW, _('New'))
              gen_button.tooltip_text = _('Generate new key pair')
              #gen_button.width_request = 110
              gen_button.signal_connect('clicked') { |*args| dialog.response=3 }
              dialog.hbox.pack_start(gen_button, false, false, 0)

              key_vec0 = key_vec
              key_vec = nil
              dialog.run2 do
                if (dialog.response == 3)
                  getting = true
                else
                  key_vec = key_vec0
                  panhash = PandoraUtils.hex_to_bytes(key_entry.text)
                  passwd = pass_entry.text
                  if changebtn.active? and new_pass_entry
                    key_vec, cipher, passwd = recrypt_key(key_model, key_vec, cipher, panhash, \
                      passwd, new_pass_entry.text)
                  end
                  #p 'key_vec='+key_vec.inspect
                  if (last_auth_key != panhash) or (not key_vec)
                    last_auth_key = panhash
                    key_vec, cipher = read_key(last_auth_key, passwd, key_model)
                    if not key_vec
                      getting = true
                      key_vec = []
                    end
                  else
                    key_vec[KV_Pass] = passwd
                  end
                end
              end
            end
            $first_key_init = false
          end
          if (not key_vec) and getting
            getting = false
            dialog = PandoraGtk::AdvancedDialog.new(_('Key generation'))
            dialog.set_default_size(420, 250)

            vbox = ::Gtk::VBox.new
            dialog.viewport.add(vbox)

            #creator = PandoraUtils.bigint_to_bytes(0x01052ec783d34331de1d39006fc80000000000000000)
            label = ::Gtk::Label.new(_('Person panhash'))
            vbox.pack_start(label, false, false, 2)
            user_entry = PandoraGtk::PanhashBox.new('Panhash(Person)')
            #user_entry.text = PandoraUtils.bytes_to_hex(creator)
            vbox.pack_start(user_entry, false, false, 2)

            rights = KS_Exchange | KS_Voucher
            label = ::Gtk::Label.new(_('Key credentials'))
            vbox.pack_start(label, false, false, 2)

            hbox = ::Gtk::HBox.new

            exchange_btn = ::Gtk::CheckButton.new(_('exchange'), true)
            exchange_btn.active = ((rights & KS_Exchange)>0)
            hbox.pack_start(exchange_btn, true, true, 2)

            voucher_btn = ::Gtk::CheckButton.new(_('voucher'), true)
            voucher_btn.active = ((rights & KS_Voucher)>0)
            hbox.pack_start(voucher_btn, true, true, 2)

            vbox.pack_start(hbox, false, false, 2)

            label = ::Gtk::Label.new(_('Password'))
            vbox.pack_start(label, false, false, 2)
            pass_entry = ::Gtk::Entry.new
            pass_entry.width_request = 250
            align = ::Gtk::Alignment.new(0.5, 0.5, 0.0, 0.0)
            align.add(pass_entry)
            vbox.pack_start(align, false, false, 2)
            #vbox.pack_start(pass_entry, false, false, 2)

            dialog.def_widget = user_entry.entry

            dialog.run2 do
              creator = PandoraUtils.hex_to_bytes(user_entry.text)
              if creator.size==22
                #cipher_hash = encode_cipher_and_hash(KT_Bf, KH_Sha2 | KL_bit256)
                passwd = pass_entry.text
                cipher_hash = 0
                if passwd and (passwd.size>0)
                  cipher_hash = encode_cipher_and_hash(KT_Aes | KL_bit256, KH_Sha2 | KL_bit256)
                end

                rights = 0
                rights = (rights | KS_Exchange) if exchange_btn.active?
                rights = (rights | KS_Voucher) if voucher_btn.active?

                #p 'cipher_hash='+cipher_hash.to_s
                type_klen = KT_Rsa | KL_bit2048

                key_vec = generate_key(type_klen, cipher_hash, passwd)

                #p 'key_vec='+key_vec.inspect

                pub  = key_vec[KV_Pub]
                priv = key_vec[KV_Priv]
                type_klen = key_vec[KV_Kind]
                cipher_hash = key_vec[KV_Cipher]
                #passwd = key_vec[KV_Pass]

                key_vec[KV_Creator] = creator

                time_now = Time.now

                vals = time_now.to_a
                y, m, d = [vals[5], vals[4], vals[3]]  #current day
                expire = Time.local(y+5, m, d).to_i

                time_now = time_now.to_i
                panstate = PandoraModel::PSF_Support
                values = {:panstate=>panstate, :kind=>type_klen, :rights=>rights, :expire=>expire, \
                  :creator=>creator, :created=>time_now, :cipher=>0, :body=>pub, :modified=>time_now}
                panhash = key_model.panhash(values, rights)
                values['panhash'] = panhash
                key_vec[KV_Panhash] = panhash

                # save public key
                res = key_model.update(values, nil, nil)
                if res
                  # save private key
                  values[:kind] = KT_Priv
                  values[:body] = priv
                  values[:cipher] = cipher_hash
                  res = key_model.update(values, nil, nil)
                  if res
                    #p 'last_auth_key='+panhash.inspect
                    last_auth_key = panhash
                  end
                end
              else
                dialog = Gtk::MessageDialog.new($window, \
                  Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
                  Gtk::MessageDialog::INFO, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
                  _('Panhash must consist of 44 symbols'))
                dialog.title = _('Note')
                dialog.default_response = Gtk::Dialog::RESPONSE_OK
                dialog.icon = $window.icon
                if (dialog.run == Gtk::Dialog::RESPONSE_OK)
                  PandoraGtk.show_panobject_list(PandoraModel::Person, nil, nil, true)
                end
                dialog.destroy
              end
            end
          end
          if key_vec and (key_vec != [])
            #p 'key_vec='+key_vec.inspect
            key_vec = init_key(key_vec)
            if key_vec and key_vec[KV_Obj]
              self.the_current_key = key_vec
              text = PandoraCrypto.short_name_of_person(key_vec, nil, 1)
              if text and (text.size>0)
                #text = '['+text+']'
              else
                text = 'Logged'
              end
              $window.set_status_field(PandoraGtk::SF_Auth, text, nil, true)
              if last_auth_key0 != last_auth_key
                PandoraUtils.set_param('last_auth_key', last_auth_key)
              end
            else
              dialog = Gtk::MessageDialog.new($window, Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT, \
                Gtk::MessageDialog::QUESTION, Gtk::MessageDialog::BUTTONS_OK_CANCEL, \
                _('Cannot activate key. Try again?')+"\n[" +PandoraUtils.bytes_to_hex(last_auth_key[2,16])+']')
              dialog.title = _('Key init')
              dialog.default_response = Gtk::Dialog::RESPONSE_OK
              dialog.icon = $window.icon
              getting = (dialog.run == Gtk::Dialog::RESPONSE_OK)
              dialog.destroy
              key_vec = deactivate_key(key_vec) if (not getting)
            end
          else
            key_vec = deactivate_key(key_vec)
          end
        end
      end
      key_vec
    end

    # Get panhash of current user or key
    # RU: Возвращает панхэш текущего пользователя или ключа
    def self.current_user_or_key(user=true, init=true)
      panhash = nil
      key = current_key(false, init)
      if key and key[KV_Obj]
        if user
          panhash = key[KV_Creator]
        else
          panhash = key[KV_Panhash]
        end
      end
      panhash
    end

    PT_Pson1   = 1

    # Sign PSON of PanObject and save a sign as record
    # RU: Подписывает PSON ПанОбъекта и сохраняет подпись как запись
    def self.sign_panobject(panobject, trust=0, models=nil)
      res = false
      key = current_key
      if key and key[KV_Obj] and key[KV_Creator]
        namesvalues = panobject.namesvalues
        matter_fields = panobject.matter_fields

        obj_hash = namesvalues['panhash']
        if not PandoraUtils.panhash_nil?(obj_hash)
          #p 'sign: matter_fields='+matter_fields.inspect
          sign = make_sign(key, Pandora::Utils.namehash_to_pson(matter_fields))
          if sign
            time_now = Time.now.to_i
            key_hash = key[KV_Panhash]
            creator = key[KV_Creator]
            trust = Pandora::Model.trust_to_int255(trust, true)

            values = {:modified=>time_now, :obj_hash=>obj_hash, :key_hash=>key_hash, \
              :pack=>PT_Pson1, :trust=>trust, :creator=>creator, :created=>time_now, \
              :sign=>sign}

            sign_model = Pandora::Utils.get_model('Sign', models)
            panhash = sign_model.panhash(values)
            #p '!!!!!!panhash='+PandoraUtils.bytes_to_hex(panhash).inspect

            values['panhash'] = panhash
            res = sign_model.update(values, nil, nil)
          else
            Pandora.logger.warn _('Cannot create sign')+' ['+\
              panobject.show_panhash(obj_hash)+']'
          end
        end
      end
      res
    end

    # Delete sign records by the panhash
    # RU: Удаляет подписи по заданному панхэшу
    def self.unsign_panobject(obj_hash, delete_all=false, models=nil)
      res = true
      key_hash = current_user_or_key(false, (not delete_all))
      if obj_hash and (delete_all or key_hash)
        sign_model = PandoraUtils.get_model('Sign', models)
        filter = {:obj_hash=>obj_hash}
        filter[:key_hash] = key_hash if key_hash
        res = sign_model.update(nil, nil, filter)
      end
      res
    end

    $person_trusts = {}

    # Get trust to panobject by its panhash
    # RU: Возвращает доверие к панобъекту по его панхэшу
    def self.trust_in_panobj(panhash, models=nil)
      res = nil
      if panhash and (panhash != '')
        key_hash = current_user_or_key(false, false)
        sign_model = PandoraUtils.get_model('Sign', models)
        filter = {:obj_hash => panhash}
        filter[:key_hash] = key_hash if key_hash
        sel = sign_model.select(filter, false, 'created, trust', 'created DESC', 1)
        if (sel.is_a? Array) and (sel.size>0)
          if key_hash
            last_date = 0
            sel.each_with_index do |row, i|
              created = row[0]
              trust = row[1]
              #p 'sign: [creator, created, trust]='+[creator, created, trust].inspect
              #p '[prev_creator, created, last_date, creator]='+[prev_creator, created, last_date, creator].inspect
              if created>last_date
                #p 'sign2: [creator, created, trust]='+[creator, created, trust].inspect
                last_date = created
                res = PandoraModel.trust_to_int255(trust, false)
              end
            end
          else
            res = sel.size
          end
        end
      end
      res
    end

    $query_depth = 3

    # Calculate a rate of the panobject
    # RU: Вычислить рейтинг панобъекта
    def self.rate_of_panobj(panhash, depth=$query_depth, querist=nil, models=nil)
      count = 0
      rate = 0.0
      querist_rate = nil
      depth -= 1
      if (depth >= 0) and (panhash != querist) and panhash and (panhash != '')
        if (not querist) or (querist == '')
          querist = current_user_or_key(false, true)
        end
        if querist and (querist != '')
          #kind = PandoraUtils.kind_from_panhash(panhash)
          sign_model = PandoraUtils.get_model('Sign', models)
          filter = { :obj_hash => panhash, :key_hash => querist }
          #filter = {:obj_hash => panhash}
          sel = sign_model.select(filter, false, 'creator, created, trust', 'creator')
          if sel and (sel.size>0)
            prev_creator = nil
            last_date = 0
            last_trust = nil
            last_i = sel.size-1
            sel.each_with_index do |row, i|
              creator = row[0]
              created = row[1]
              trust = row[2]
              #p 'sign: [creator, created, trust]='+[creator, created, trust].inspect
              if creator
                #p '[prev_creator, created, last_date, creator]='+[prev_creator, created, last_date, creator].inspect
                if (not prev_creator) or ((created>last_date) and (creator==prev_creator))
                  #p 'sign2: [creator, created, trust]='+[creator, created, trust].inspect
                  last_date = created
                  last_trust = trust
                  prev_creator ||= creator
                end
                if (creator != prev_creator) or (i==last_i)
                  p 'sign3: [creator, created, last_trust]='+[creator, created, last_trust].inspect
                  person_trust = 1.0 #trust_of_person(creator, my_key_hash)
                  rate += PandoraModel.trust_to_int255(last_trust, false) * person_trust
                  prev_creator = creator
                  last_date = created
                  last_trust = trust
                end
              end
            end
          end
          querist_rate = rate
        end
      end
      [count, rate, querist_rate]
    end

    $max_opened_keys = 1000
    $open_keys = {}

    # Activate a key with given panhash
    # RU: Активировать ключ по заданному панхэшу
    def self.open_key(panhash, models=nil, init=true)
      key_vec = nil
      if panhash.is_a? String
        key_vec = $open_keys[panhash]
        #p 'openkey key='+key_vec.inspect+' $open_keys.size='+$open_keys.size.inspect
        if key_vec
          cur_trust = trust_in_panobj(panhash)
          key_vec[KV_Trust] = cur_trust if cur_trust
        elsif ($open_keys.size<$max_opened_keys)
          model = PandoraUtils.get_model('Key', models)
          filter = {:panhash => panhash}
          sel = model.select(filter, false)
          #p 'openkey sel='+sel.inspect
          if (sel.is_a? Array) and (sel.size>0)
            sel.each do |row|
              kind = model.field_val('kind', row)
              type, klen = divide_type_and_klen(kind)
              if type != KT_Priv
                cipher = model.field_val('cipher', row)
                pub = model.field_val('body', row)
                creator = model.field_val('creator', row)

                key_vec = Array.new
                key_vec[KV_Pub] = pub
                key_vec[KV_Kind] = kind
                #key_vec[KV_Pass] = passwd
                key_vec[KV_Panhash] = panhash
                key_vec[KV_Creator] = creator
                key_vec[KV_Trust] = trust_in_panobj(panhash)

                $open_keys[panhash] = key_vec
                break
              end
            end
          else  #key is not found
            key_vec = 0
          end
        else
          Pandora.logger.warn  _('Achieved limit of opened keys')+': '+$open_keys.size.to_s
        end
      else
        key_vec = panhash
      end
      if init and key_vec and (not key_vec[KV_Obj])
        key_vec = init_key(key_vec)
        #p 'openkey init key='+key_vec.inspect
      end
      key_vec
    end

    # Current kind permission for different trust levels
    # RU: Текущие разрешения сортов для разных уровней доверия
    # (-1.0, -0.9, ... 0.0, 0.1, ... 1.0)
    Allowed_Kinds = [
      [], [], [], [], [], [], [], [], [], [],
      [], [], [], [], [], [], [], [], [], [], [],
    ]

    # Allowed kinds for trust level
    # RU: Допустимые сорта для уровня доверия
    def self.allowed_kinds(trust, kind_list=nil)
      #res = []
      res = kind_list
      res
    end

    # Get first name and last name of person
    # RU: Возвращает имя и фамилию человека
    def self.name_and_family_of_person(key, person=nil)
      nf = nil
      #p 'person, key='+[person, key].inspect
      nf = key[KV_NameFamily] if key
      aname, afamily = nil, nil
      if nf.is_a? Array
        #p 'nf='+nf.inspect
        aname, afamily = nf
      elsif (person or key)
        person ||= key[KV_Creator] if key
        kind = PandoraUtils.kind_from_panhash(person)
        sel = PandoraModel.get_record_by_panhash(kind, person, nil, nil, 'first_name, last_name')
        #p 'key, person, sel='+[key, person, sel].inspect
        if (sel.is_a? Array) and (sel.size>0)
          aname, afamily = Utf8String.new(sel[0][0]), Utf8String.new(sel[0][1])
        end
        #p '[aname, afamily]='+[aname, afamily].inspect
        if (not aname) and (not afamily) and (key.is_a? Array)
          aname = key[KV_Creator]
          aname = aname[2, 5] if aname
          aname = PandoraUtils.bytes_to_hex(aname)
          afamily = key[KV_Panhash]
          afamily = afamily[2, 5] if afamily
          afamily = PandoraUtils.bytes_to_hex(afamily)
        end
        if (not aname) and (not afamily) and person
          aname = person[2, 3]
          aname = PandoraUtils.bytes_to_hex(aname) if aname
          afamily = person[5, 4]
          afamily = PandoraUtils.bytes_to_hex(afamily) if afamily
        end
        key[KV_NameFamily] = [aname, afamily] if key
      end
      aname ||= ''
      afamily ||= ''
      #p 'name_and_family_of_person: '+[aname, afamily].inspect
      [aname, afamily]
    end

    # Get short name of person
    # RU: Возвращает короткое имя человека
    def self.short_name_of_person(key, person=nil, view_kind=0, othername=nil)
      aname, afamily = name_and_family_of_person(key, person)
      #p [othername, aname, afamily]
      if view_kind==0
        if othername and (othername == aname)
          res = afamily
        else
          res = aname
        end
      else
        res = ''
        res << aname if (aname and (aname.size>0))
        res << ' ' if (res.size>0)
        res << afamily if (afamily and (afamily.size>0))
      end
      res ||= ''
      res
    end

    # Find sha1-solution
    # RU: Находит sha1-загадку
    def self.find_sha1_solution(phrase)
      res = nil
      lenbit = phrase[phrase.size-1].ord
      len = lenbit/8
      puzzle = phrase[0, len]
      tailbyte = nil
      drift = lenbit - len*8
      if drift>0
        tailmask = 0xFF >> (8-drift)
        tailbyte = (phrase[len].ord & tailmask) if tailmask>0
      end
      i = 0
      while (not res) and (i<0xFFFFFFFF)
        add = PandoraUtils.bigint_to_bytes(i)
        hash = Digest::SHA1.digest(phrase+add)
        offer = hash[0, len]
        if (offer==puzzle) and ((not tailbyte) or ((hash[len].ord & tailmask)==tailbyte))
          res = add
        end
        i += 1
      end
      res
    end

    # Check sha1-solution
    # RU: Проверяет sha1-загадку
    def self.check_sha1_solution(phrase, add)
      res = false
      lenbit = phrase[phrase.size-1].ord
      len = lenbit/8
      puzzle = phrase[0, len]
      tailbyte = nil
      drift = lenbit - len*8
      if drift>0
        tailmask = 0xFF >> (8-drift)
        tailbyte = (phrase[len].ord & tailmask) if tailmask>0
      end
      hash = Digest::SHA1.digest(phrase+add)
      offer = hash[0, len]
      if (offer==puzzle) and ((not tailbyte) or ((hash[len].ord & tailmask)==tailbyte))
        res = true
      end
      res
    end

  end
end
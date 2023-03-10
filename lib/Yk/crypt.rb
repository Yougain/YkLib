#


require 'openssl'


def encrypt(aaa, solt = 'solt')
  enc = OpenSSL::Cipher::Cipher.new('aes256')
  enc.encrypt
  enc.pkcs5_keyivgen(solt)
  ((enc.update(aaa) + enc.final).unpack("H*")).to_s
  rescue
    nil
end


def decrypt(bbb, solt = 'solt')
  dec = OpenSSL::Cipher::Cipher.new('aes256') 
  dec.decrypt 
  dec.pkcs5_keyivgen(solt)
  (dec.update(Array.new([bbb]).pack("H*")) + dec.final)
  rescue  
    nil
end 



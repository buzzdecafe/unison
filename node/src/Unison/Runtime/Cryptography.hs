{-# LANGUAGE OverloadedStrings #-}
{-# Language ScopedTypeVariables #-}
{-# Language GeneralizedNewtypeDeriving #-}

module Unison.Runtime.Cryptography
       ( symmetricKey
       , SymmetricKey
       , mkCrypto
       ) where

import Unison.Cryptography
import Data.ByteString (ByteString)
import Data.ByteArray as BA
import qualified Crypto.Random as R

-- cryptonite
import qualified Crypto.Cipher.AES as AES
import Crypto.Cipher.Types
import Crypto.Error

newtype SymmetricKey = AES256 ByteString deriving (Ord, Eq, Monoid, ByteArrayAccess, ByteArray)

symmetricKey :: ByteString -> Maybe SymmetricKey
symmetricKey bs | BA.length bs == 32 = (Just . AES256) bs
                | otherwise = Nothing

-- Creates a Unison.Cryptography object specialized to use the noise protocol
-- (http://noiseprotocol.org/noise.html).
mkCrypto :: forall cleartext . (ByteArrayAccess cleartext, ByteArray cleartext) => ByteString -> Cryptography ByteString SymmetricKey () () () () cleartext
mkCrypto key = Cryptography key gen hash sign verify randomBytes encryptAsymmetric decryptAsymmetric encrypt decrypt pipeInitiator pipeResponder where
  -- generates an elliptic curve keypair, for use in ECDSA
  gen = undefined
  hash = undefined
  sign _ = undefined
  verify _ _ _ = undefined
  randomBytes = randomBytes'
  encryptAsymmetric _ cleartext = undefined
  decryptAsymmetric ciphertext = undefined

  encrypt :: SymmetricKey -> [cleartext] -> IO Ciphertext
  encrypt = encrypt'
      
  decrypt :: SymmetricKey -> ByteString -> Either String cleartext
  decrypt = decrypt'

  pipeInitiator _ = undefined
  pipeResponder = undefined

randomBytes' :: Int -> IO ByteString
randomBytes' n = fst . R.randomBytesGenerate n <$> R.getSystemDRG

-- The number of bits in the Initialization Vector (IV). This should be equal to
-- the block size, which is 128 in this implementation.
ivBitLength :: Int
ivBitLength = 128

-- The number of bits in the authorization tag. In general this value can be one
-- of 128, 120, 112, 104, or 96. The larger, the better.
authTagBitLength :: Int
authTagBitLength = 128

encrypt' :: forall cleartext .
            ( ByteArrayAccess cleartext
            , ByteArray cleartext
            )
         => SymmetricKey
         -> [cleartext]
         -> IO Ciphertext
encrypt' k cts = go <$> randomBytes' (ivBitLength `div` 8)
  where go iv =
          let clrtext = BA.concat cts :: cleartext
              cipher = throwCryptoError $ cipherInit k :: AES.AES256
              aead = throwCryptoError $ aeadInit AEAD_GCM cipher iv
              ad = "" :: ByteString -- associated data
              ((AuthTag auth), out) = aeadSimpleEncrypt aead ad clrtext authTagBitLength
          in
            BA.concat [(BA.convert auth), iv, (BA.convert out)]

decrypt' :: (ByteArray cleartext)
         => SymmetricKey
         -> ByteString
         -> Either String cleartext
decrypt' k ciphertext =
   let (auth, ct') = BA.splitAt (authTagBitLength `div` 8) ciphertext
       (iv, ct'') = BA.splitAt (ivBitLength `div` 8) ct'
       cipher = throwCryptoError $ cipherInit k :: AES.AES256
       aead = throwCryptoError $ aeadInit AEAD_GCM cipher iv
       ad = "" :: ByteString -- associated data
       maybeCleartext = aeadSimpleDecrypt aead ad ct'' (AuthTag (BA.convert auth))
   in
     case maybeCleartext of
       Just pt -> Right $ BA.convert pt
       Nothing -> Left "Error when attempting to decrypt ciphertext."

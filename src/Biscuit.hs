{-# LANGUAGE EmptyDataDeriving #-}
module Biscuit
  ( PrivateKey
  , PublicKey
  , Biscuit
  , Block
  , Verifier
  , blockFact
  , blockRule
  , blockCheck
  , blockContext
  , verifierFact
  , verifierRule
  , verifierCheck
  , newKeyPair
  , getPublicKey
  , getPrivateKey
  , fromPrivateKey
  , serializePrivateKey
  , serializePublicKey
  , serializePrivateKeyB64
  , serializePublicKeyB64
  , parsePrivateKey
  , parsePublicKey
  , parsePrivateKeyB64
  , parsePublicKeyB64
  , mkBiscuit
  , addBlock
  , parse
  , parseB64
  , parseHex
  , serialize
  , serializeB64
  , serializeHex
  , verifyBiscuit
  , verifyBiscuitWithLimits
  , checkBiscuitSignature

  , verifier
  , block
  , defaultLimits
  ) where

import           Data.ByteString           (ByteString)
import           Data.Text                 (Text)
import           Language.Haskell.TH.Quote (QuasiQuoter)

import           Datalog.AST               (Fact, Rule)

data KeyPair
data PublicKey
data PrivateKey
data Biscuit
data KeyError deriving Show
data ParseError deriving Show
data SignatureError deriving Show
data VerificationError deriving Show
data Check
data Limits

-- | Block data. This can be built with a dedicated `block` quasiquoter,
-- | but also by combining elements with a provided monoid
data Block
instance Semigroup Block where
  (<>) = error "todo"
instance Monoid Block where
  mempty = error "todo"

blockFact :: Fact -> Block
blockFact = error "todo"
blockRule :: Rule -> Block
blockRule = error "todo"
blockCheck :: Check -> Block
blockCheck = error "todo"
blockContext :: Text -> Block
blockContext = error "todo"

-- | Verifier data. This is a collection of
-- rules, facts, checks and policies. This can
-- be built with a dedicated `policy` quasiquoter,
-- but also by combining elements with a provided
-- monoid
data Verifier
instance Semigroup Verifier where
  (<>) = error "todo"
instance Monoid Verifier where
  mempty = error "todo"

verifierFact :: Fact -> Verifier
verifierFact = error "todo"
verifierRule :: Rule -> Verifier
verifierRule = error "todo"
verifierCheck :: Check -> Verifier
verifierCheck = error "todo"

-- | Create a new keypair with a random private key
newKeyPair :: IO KeyPair
newKeyPair = error "todo"

getPublicKey :: KeyPair -> PublicKey
getPublicKey = error "todo"

getPrivateKey :: KeyPair -> PrivateKey
getPrivateKey = error "todo"

fromPrivateKey :: PrivateKey -> IO KeyPair
fromPrivateKey = error "todo"

serializePrivateKey :: PrivateKey -> ByteString
serializePrivateKey = error "todo"
serializePublicKey :: PublicKey -> ByteString
serializePublicKey = error "todo"
serializePrivateKeyB64 :: PrivateKey -> ByteString
serializePrivateKeyB64 = error "todo"
serializePublicKeyB64 :: PublicKey -> ByteString
serializePublicKeyB64 = error "todo"
parsePrivateKey :: ByteString -> Either KeyError PrivateKey
parsePrivateKey = error "todo"
parsePublicKey :: ByteString -> Either KeyError PublicKey
parsePublicKey = error "todo"
parsePrivateKeyB64 :: ByteString -> Either KeyError PrivateKey
parsePrivateKeyB64 = error "todo"
parsePublicKeyB64 :: ByteString -> Either KeyError PublicKey
parsePublicKeyB64 = error "todo"

-- | Create a new biscuit with the provided authority block
mkBiscuit :: PrivateKey -> Block -> IO Biscuit
mkBiscuit = error "todo"

-- | Add a block to an existing biscuit. The block will be signed
-- with a randomly-generated keypair
addBlock :: Block -> Biscuit -> IO Biscuit
addBlock = error "todo"

-- | Parse a biscuit from a raw bytestring. If you want to parse
-- from a URL-compatible base 64 bytestring, consider using `parseB64`
-- instead
parse :: ByteString -> Either ParseError Biscuit
parse = error "todo"

-- | Parse a biscuit from a URL-compatible base 64 encoded bytestring
parseB64 :: ByteString -> Either ParseError Biscuit
parseB64 = error "todo"

-- | Parse a biscuit from an hex-encoded bytestring
parseHex :: ByteString -> Either ParseError Biscuit
parseHex = error "todo"

-- | Serialize a biscuit to a binary format. If you intend to send
-- the biscuit over a text channel, consider using `serializeB64` or
-- `serializeHex` instead
serialize :: Biscuit -> ByteString
serialize = error "todo"

-- | Serialize a biscuit to URL-compatible base 64, as recommended by the spec
serializeB64 :: Biscuit -> ByteString
serializeB64 = error "todo"

-- | Serialize a biscuit to a hex (base 16) string. Be advised that the specs
-- recommends base 64 instead.
serializeHex :: Biscuit -> ByteString
serializeHex = error "todo"

-- | Given a provided verifier (a set of facts, rules, checks and policies),
-- and a public key, verify a biscuit
-- - make sure the biscuit has been signed with the private key associated to the public key
-- - make sure the biscuit is valid for the provided verifier
verifyBiscuit :: Biscuit -> Verifier -> PublicKey -> IO (Either VerificationError ())
verifyBiscuit = error "todo"

-- | Same as `verifyBiscuit`, but allows providing runtime restrictions
-- - timeout
-- - max number of facts created
-- - max number of iterations when computing facts
-- - expressions restrictions (eg, disallow regexes)
-- - blocks restrictions (eg disallow rules and facts in non-authority blocks)
verifyBiscuitWithLimits :: Limits -> Biscuit -> Verifier -> PublicKey -> IO (Either VerificationError ())
verifyBiscuitWithLimits = error "todo"

-- | Only check a biscuit signature. This can be used to perform an early check, before
-- bothering with constructing a verifier.
checkBiscuitSignature :: Biscuit -> PublicKey -> IO (Either SignatureError ())
checkBiscuitSignature = error "todo"


----- these functions are not meant to be in the top-level module, but they are not
-- implemented yet, so i'm putting them there for now
verifier :: QuasiQuoter
verifier = error "todo"
block :: QuasiQuoter
block = error "todo"
defaultLimits :: Limits
defaultLimits = error "todo"


module Web.SCIM.Schema.User.Address where

import Data.Text hiding (dropWhile)
import Data.Aeson
import GHC.Generics (Generic)
import Web.SCIM.Schema.Common

data Address = Address
  { formatted :: Maybe Text
  , streetAddress :: Maybe Text
  , locality :: Maybe Text
  , region :: Maybe Text
  , postalCode :: Maybe Text
  -- TODO: country is specified as ISO3166, but example uses "USA"
  , country :: Maybe Text
  , typ :: Maybe Text
  , primary :: Maybe Bool
  } deriving (Show, Eq, Generic)

instance FromJSON Address where
  parseJSON = genericParseJSON parseOptions . jsonLower

instance ToJSON Address where
  toJSON = genericToJSON serializeOptions

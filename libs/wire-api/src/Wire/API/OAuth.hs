-- This file is part of the Wire Server implementation.
--
-- Copyright (C) 2022 Wire Swiss GmbH <opensource@wire.com>
--
-- This program is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Affero General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option) any
-- later version.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
-- FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
-- details.
--
-- You should have received a copy of the GNU Affero General Public License along
-- with this program. If not, see <https://www.gnu.org/licenses/>.
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Wire.API.OAuth where

import Cassandra hiding (Set)
import Control.Lens (preview, view, (.~), (?~), (^.))
import Control.Monad.Except
import Crypto.JWT hiding (Context, params, uri, verify)
import qualified Data.Aeson.KeyMap as M
import qualified Data.Aeson.Types as A
import Data.ByteString.Conversion
import Data.ByteString.Lazy (toStrict)
import qualified Data.HashMap.Strict as HM
import Data.Id as Id
import Data.Range
import Data.Schema
import qualified Data.Set as Set
import Data.String.Conversions (cs)
import Data.Swagger (ToParamSchema (..))
import qualified Data.Swagger as S
import qualified Data.Text as T
import Data.Text.Ascii
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error as TErr
import Data.Time
import Imports hiding (exp, head)
import Servant hiding (Handler, JSON, Tagged, addHeader, respond)
import Servant.Swagger.Internal.Orphans ()
import Test.QuickCheck (Arbitrary)
import URI.ByteString
import Web.FormUrlEncoded (Form (..), FromForm (..), ToForm (..), parseUnique)
import Wire.API.Error
import Wire.Arbitrary (GenericUniform (..))

--------------------------------------------------------------------------------
-- Types

newtype RedirectUrl = RedirectUrl {unRedirectUrl :: URIRef Absolute}
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema RedirectUrl)

addParams :: [(ByteString, ByteString)] -> RedirectUrl -> RedirectUrl
addParams ps (RedirectUrl uri) = uri & (queryL . queryPairsL) .~ (ps ++ (uri ^. (queryL . queryPairsL))) & RedirectUrl

instance ToParamSchema RedirectUrl where
  toParamSchema _ = toParamSchema (Proxy @Text)

instance ToByteString RedirectUrl where
  builder = serializeURIRef . unRedirectUrl

instance FromByteString RedirectUrl where
  parser = RedirectUrl <$> uriParser strictURIParserOptions

instance ToSchema RedirectUrl where
  schema =
    (TE.decodeUtf8 . serializeURIRef' . unRedirectUrl)
      .= (RedirectUrl <$> parsedText "RedirectUrl" (runParser (uriParser strictURIParserOptions) . TE.encodeUtf8))

instance ToHttpApiData RedirectUrl where
  toUrlPiece = TE.decodeUtf8With TErr.lenientDecode . toHeader
  toHeader = serializeURIRef' . unRedirectUrl

instance FromHttpApiData RedirectUrl where
  parseUrlPiece = parseHeader . TE.encodeUtf8
  parseHeader = bimap (T.pack . show) RedirectUrl . parseURI strictURIParserOptions

newtype OAuthApplicationName = OAuthApplicationName {unOAuthApplicationName :: Range 1 256 Text}
  deriving (Eq, Show, Generic, Ord)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthApplicationName)

instance ToSchema OAuthApplicationName where
  schema = OAuthApplicationName <$> unOAuthApplicationName .= schema

data NewOAuthClient = NewOAuthClient
  { nocApplicationName :: OAuthApplicationName,
    nocRedirectUrl :: RedirectUrl
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema NewOAuthClient)

instance ToSchema NewOAuthClient where
  schema =
    object "NewOAuthClient" $
      NewOAuthClient
        <$> nocApplicationName .= fieldWithDocModifier "applicationName" applicationNameDescription schema
        <*> nocRedirectUrl .= fieldWithDocModifier "redirectUrl" redirectUrlDescription schema
    where
      applicationNameDescription = description ?~ "The name of the application. This will be shown to the user when they are asked to authorize the application."
      redirectUrlDescription = description ?~ "The URL to redirect to after the user has authorized the application."

newtype OAuthClientPlainTextSecret = OAuthClientPlainTextSecret {unOAuthClientPlainTextSecret :: AsciiBase16}
  deriving (Eq, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthClientPlainTextSecret)

instance Show OAuthClientPlainTextSecret where
  show _ = "<OAuthClientPlainTextSecret>"

instance ToSchema OAuthClientPlainTextSecret where
  schema = (toText . unOAuthClientPlainTextSecret) .= parsedText "OAuthClientPlainTextSecret" (fmap OAuthClientPlainTextSecret . validateBase16)

instance FromHttpApiData OAuthClientPlainTextSecret where
  parseQueryParam = bimap cs OAuthClientPlainTextSecret . validateBase16 . cs

instance ToHttpApiData OAuthClientPlainTextSecret where
  toQueryParam = toText . unOAuthClientPlainTextSecret

data OAuthClientCredentials = OAuthClientCredentials
  { occClientId :: OAuthClientId,
    occClientSecret :: OAuthClientPlainTextSecret
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthClientCredentials)

instance ToSchema OAuthClientCredentials where
  schema =
    object "OAuthClientCredentials" $
      OAuthClientCredentials
        <$> occClientId .= fieldWithDocModifier "clientId" clientIdDescription schema
        <*> occClientSecret .= fieldWithDocModifier "clientSecret" clientSecretDescription schema
    where
      clientIdDescription = description ?~ "The ID of the application."
      clientSecretDescription = description ?~ "The secret of the application."

data OAuthClient = OAuthClient
  { ocId :: OAuthClientId,
    ocName :: OAuthApplicationName,
    ocRedirectUrl :: RedirectUrl
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthClient)

instance ToSchema OAuthClient where
  schema =
    object "OAuthClient" $
      OAuthClient
        <$> ocId .= field "clientId" schema
        <*> ocName .= field "applicationName" schema
        <*> ocRedirectUrl .= field "redirectUrl" schema

data OAuthResponseType = OAuthResponseTypeCode
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthResponseType)

instance ToSchema OAuthResponseType where
  schema :: ValueSchema NamedSwaggerDoc OAuthResponseType
  schema =
    enum @Text "OAuthResponseType" $
      mconcat
        [ element "code" OAuthResponseTypeCode
        ]

-- | This types represents all valid OAuth scopes
-- If you want to add an OAuth scope, you may want to go through this checklist:
-- - Add the new scope to the list below
-- - Update `ToByteString` and `FromByteString` instance of `OAuthScope` (run unit tests)
-- - Implement an `IsOAuthScope` instance for the new scope
-- - For the endpoint(s) that require the new scope, replace:
--   - `ZUser` with `ZOauthUser '[ '<NewScope>]`
--   - or `ZLocalUser` with `ZOauthLocalUser '[ '<NewScope>]`
-- - If the endpoint has other ZAuth combinators like `ZConn` e.g., these have to be made optional (e.g. replace with `ZOptConn`)
-- - Update `services/nginz/integration-test/conf/nginz/nginx.conf` and replace
--   `include common_response_with_zauth.conf` with `include common_response_with_zauth_oauth.conf`
--   in location settings for the endpoint(s) in question
-- - Update `charts/nginz/values.yaml` and add `enable_oauth: true` to the endpoint in question
-- - Consider writing an integration test
-- todo(leif): update these docs
data OAuthScope
  = ReadFeatureConfigs
  | ReadSelf
  | WriteConversation
  | WriteConversationCode
  deriving (Eq, Show, Generic, Ord)
  deriving (Arbitrary) via (GenericUniform OAuthScope)

class IsOAuthScope scope where
  toOAuthScope :: OAuthScope

instance IsOAuthScope 'WriteConversation where
  toOAuthScope = WriteConversation

instance IsOAuthScope 'WriteConversationCode where
  toOAuthScope = WriteConversationCode

instance IsOAuthScope 'ReadSelf where
  toOAuthScope = ReadSelf

instance IsOAuthScope 'ReadFeatureConfigs where
  toOAuthScope = ReadFeatureConfigs

-- | Given a type-level list of scopes X, this class gives you a function that tests if
-- a list of scopes from a token intersects with X, ie., if a token grants access to the route
-- with scopes X.
class IsOAuthScopes scopes where
  showOAuthScopeList :: Text
  allowOAuthScopeList :: Set.Set OAuthScope -> Bool

instance IsOAuthScopes '[] where
  showOAuthScopeList = mempty
  allowOAuthScopeList _ = False

instance (IsOAuthScope scope, IsOAuthScopes scopes) => IsOAuthScopes (scope ': scopes) where
  showOAuthScopeList = T.unwords [cs $ toByteString (toOAuthScope @scope), showOAuthScopeList @scopes]
  allowOAuthScopeList scopes = ((toOAuthScope @scope) `Set.member` scopes) || allowOAuthScopeList @scopes scopes

instance ToByteString OAuthScope where
  builder = \case
    WriteConversation -> "write:conversations"
    WriteConversationCode -> "write:conversations_code"
    ReadSelf -> "read:self"
    ReadFeatureConfigs -> "read:feature_configs"

instance FromByteString OAuthScope where
  parser = do
    s <- parser
    case s & T.toLower of
      "write:conversations" -> pure WriteConversation
      "write:conversations_code" -> pure WriteConversationCode
      "read:self" -> pure ReadSelf
      "read:feature_configs" -> pure ReadFeatureConfigs
      _ -> fail "invalid scope"

newtype OAuthScopes = OAuthScopes {unOAuthScopes :: Set OAuthScope}
  deriving (Eq, Show, Generic, Monoid, Semigroup)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthScopes)

instance ToSchema OAuthScopes where
  schema = OAuthScopes <$> (oauthScopesToText . unOAuthScopes) .= withParser schema oauthScopeParser

oauthScopesToText :: Set OAuthScope -> Text
oauthScopesToText = T.intercalate " " . fmap (cs . toByteString') . Set.toList

oauthScopeParser :: Text -> A.Parser (Set OAuthScope)
oauthScopeParser "" = pure Set.empty
oauthScopeParser scope =
  pure $ (not . T.null) `filter` T.splitOn " " scope & maybe Set.empty Set.fromList . mapM (fromByteString' . cs)

data NewOAuthAuthCode = NewOAuthAuthCode
  { noacClientId :: OAuthClientId,
    noacScope :: OAuthScopes,
    noacResponseType :: OAuthResponseType,
    noacRedirectUri :: RedirectUrl,
    noacState :: Text
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema NewOAuthAuthCode)

instance ToSchema NewOAuthAuthCode where
  schema =
    object "NewOAuthAuthCode" $
      NewOAuthAuthCode
        <$> noacClientId .= fieldWithDocModifier "clientId" clientIdDescription schema
        <*> noacScope .= fieldWithDocModifier "scope" scopeDescription schema
        <*> noacResponseType .= fieldWithDocModifier "responseType" responseTypeDescription schema
        <*> noacRedirectUri .= fieldWithDocModifier "redirectUri" redirectUriDescription schema
        <*> noacState .= fieldWithDocModifier "state" stateDescription schema
    where
      clientIdDescription = description ?~ "The ID of the OAuth client"
      scopeDescription = description ?~ "The scopes which are requested to get authorization for, separated by a space"
      responseTypeDescription = description ?~ "Indicates which authorization flow to use. Use `code` for authorization code flow."
      redirectUriDescription = description ?~ "The URL to which to redirect the browser after authorization has been granted by the user."
      stateDescription = description ?~ "An opaque value used by the client to maintain state between the request and callback. The authorization server includes this value when redirecting the user-agent back to the client.  The parameter SHOULD be used for preventing cross-site request forgery"

newtype OAuthAuthCode = OAuthAuthCode {unOAuthAuthCode :: AsciiBase16}
  deriving (Eq, Generic)

instance Show OAuthAuthCode where
  show _ = "<OAuthAuthCode>"

instance ToSchema OAuthAuthCode where
  schema = (toText . unOAuthAuthCode) .= parsedText "OAuthAuthCode" (fmap OAuthAuthCode . validateBase16)

instance ToByteString OAuthAuthCode where
  builder = builder . unOAuthAuthCode

instance FromByteString OAuthAuthCode where
  parser = OAuthAuthCode <$> parser

instance FromHttpApiData OAuthAuthCode where
  parseQueryParam = bimap cs OAuthAuthCode . validateBase16 . cs

instance ToHttpApiData OAuthAuthCode where
  toQueryParam = toText . unOAuthAuthCode

data OAuthGrantType = OAuthGrantTypeAuthorizationCode | OAuthGrantTypeRefreshToken
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthGrantType)

instance ToSchema OAuthGrantType where
  schema =
    enum @Text "OAuthGrantType" $
      mconcat
        [ element "authorization_code" OAuthGrantTypeAuthorizationCode,
          element "refresh_token" OAuthGrantTypeRefreshToken
        ]

instance FromByteString OAuthGrantType where
  parser = do
    s <- parser
    case s & T.toLower of
      "authorization_code" -> pure OAuthGrantTypeAuthorizationCode
      "refresh_token" -> pure OAuthGrantTypeRefreshToken
      _ -> fail "invalid OAuthGrantType"

instance ToByteString OAuthGrantType where
  builder = \case
    OAuthGrantTypeAuthorizationCode -> "authorization_code"
    OAuthGrantTypeRefreshToken -> "refresh_token"

instance FromHttpApiData OAuthGrantType where
  parseQueryParam = maybe (Left "invalid OAuthGrantType") pure . fromByteString . cs

instance ToHttpApiData OAuthGrantType where
  toQueryParam = cs . toByteString

data OAuthAccessTokenRequest = OAuthAccessTokenRequest
  { oatGrantType :: OAuthGrantType,
    oatClientId :: OAuthClientId,
    oatClientSecret :: OAuthClientPlainTextSecret,
    oatCode :: OAuthAuthCode,
    oatRedirectUri :: RedirectUrl
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthAccessTokenRequest)

instance ToSchema OAuthAccessTokenRequest where
  schema =
    object "OAuthAccessTokenRequest" $
      OAuthAccessTokenRequest
        <$> oatGrantType .= fieldWithDocModifier "grantType" grantTypeDescription schema
        <*> oatClientId .= fieldWithDocModifier "clientId" clientIdDescription schema
        <*> oatClientSecret .= fieldWithDocModifier "clientSecret" clientSecretDescription schema
        <*> oatCode .= fieldWithDocModifier "code" codeDescription schema
        <*> oatRedirectUri .= fieldWithDocModifier "redirectUri" redirectUriDescription schema
    where
      grantTypeDescription = description ?~ "Indicates which authorization flow to use. Use `authorization_code` for authorization code flow."
      clientIdDescription = description ?~ "The ID of the OAuth client"
      clientSecretDescription = description ?~ "The secret of the OAuth client"
      codeDescription = description ?~ "The authorization code"
      redirectUriDescription = description ?~ "The URL must match the URL that was used to generate the authorization code."

instance FromForm OAuthAccessTokenRequest where
  fromForm f =
    OAuthAccessTokenRequest
      <$> parseUnique "grant_type" f
      <*> parseUnique "client_id" f
      <*> parseUnique "client_secret" f
      <*> parseUnique "code" f
      <*> parseUnique "redirect_uri" f

instance ToForm OAuthAccessTokenRequest where
  toForm req =
    Form $
      mempty
        & HM.insert "grant_type" [toQueryParam (oatGrantType req)]
        & HM.insert "client_id" [toQueryParam (oatClientId req)]
        & HM.insert "client_secret" [toQueryParam (oatClientSecret req)]
        & HM.insert "code" [toQueryParam (oatCode req)]
        & HM.insert "redirect_uri" [toQueryParam (oatRedirectUri req)]

data OAuthAccessTokenType = OAuthAccessTokenTypeBearer
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthAccessTokenType)

instance ToSchema OAuthAccessTokenType where
  schema =
    enum @Text "OAuthAccessTokenType" $
      mconcat
        [ element "Bearer" OAuthAccessTokenTypeBearer
        ]

data TokenTag = Access | Refresh

newtype OAuthToken a = OAuthToken {unOAuthToken :: SignedJWT}
  deriving (Show, Eq, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via Schema (OAuthToken a)

instance ToByteString (OAuthToken a) where
  builder = builder . encodeCompact . unOAuthToken

instance FromByteString (OAuthToken a) where
  parser = do
    t <- parser @Text
    case decodeCompact (cs (TE.encodeUtf8 t)) of
      Left (err :: JWTError) -> fail $ show err
      Right jwt -> pure $ OAuthToken jwt

instance ToHttpApiData (OAuthToken a) where
  toHeader = toByteString'
  toUrlPiece = cs . toHeader

instance FromHttpApiData (OAuthToken a) where
  parseHeader = either (Left . cs) pure . runParser parser . cs
  parseUrlPiece = parseHeader . cs

instance ToSchema (OAuthToken a) where
  schema = (TE.decodeUtf8 . toByteString') .= withParser schema (either fail pure . runParser parser . cs)

type OAuthAccessToken = OAuthToken 'Access

type OAuthRefreshToken = OAuthToken 'Refresh

data OAuthAccessTokenResponse = OAuthAccessTokenResponse
  { oatAccessToken :: OAuthAccessToken,
    oatTokenType :: OAuthAccessTokenType,
    oatExpiresIn :: NominalDiffTime,
    oatRefreshToken :: OAuthRefreshToken
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthAccessTokenResponse)

instance ToSchema OAuthAccessTokenResponse where
  schema =
    object "OAuthAccessTokenResponse" $
      OAuthAccessTokenResponse
        <$> oatAccessToken .= fieldWithDocModifier "accessToken" accessTokenDescription schema
        <*> oatTokenType .= fieldWithDocModifier "tokenType" tokenTypeDescription schema
        <*> oatExpiresIn .= fieldWithDocModifier "expiresIn" expiresInDescription (fromIntegral <$> roundDiffTime .= schema)
        <*> oatRefreshToken .= fieldWithDocModifier "refreshToken" refreshTokenDescription schema
    where
      roundDiffTime :: NominalDiffTime -> Int32
      roundDiffTime = round
      accessTokenDescription = description ?~ "The access token, which has a relatively short lifetime"
      tokenTypeDescription = description ?~ "The type of the access token. Currently only `Bearer` is supported."
      expiresInDescription = description ?~ "The lifetime of the access token in seconds"
      refreshTokenDescription = description ?~ "The refresh token, which has a relatively long lifetime, and can be used to obtain a new access token"

data OAuthClaimsSet = OAuthClaimsSet {jwtClaims :: ClaimsSet, scope :: OAuthScopes}
  deriving (Eq, Show, Generic)

instance HasClaimsSet OAuthClaimsSet where
  claimsSet f s = fmap (\a' -> s {jwtClaims = a'}) (f (jwtClaims s))

instance A.FromJSON OAuthClaimsSet where
  parseJSON = A.withObject "OAuthClaimsSet" $ \o ->
    OAuthClaimsSet
      <$> A.parseJSON (A.Object o)
      <*> o A..: "scope"

instance A.ToJSON OAuthClaimsSet where
  toJSON s =
    ins "scope" (scope s) (A.toJSON (jwtClaims s))
    where
      ins k v (A.Object o) = A.Object $ M.insert k (A.toJSON v) o
      ins _ _ a = a

hcsSub :: HasClaimsSet hcs => hcs -> Maybe (Id a)
hcsSub =
  view claimSub
    >=> preview string
    >=> either (const Nothing) pure . parseIdFromText

hasScope :: forall scopes. IsOAuthScopes scopes => OAuthClaimsSet -> Bool
hasScope = allowOAuthScopeList @scopes . unOAuthScopes . scope

-- | Verify a JWT and return the claims set. Use this function if you have a custom claims set.
verify :: JWK -> SignedJWT -> IO (Either JWTError OAuthClaimsSet)
verify key token = do
  let audCheck = const True
  runJOSE $ verifyJWT (defaultJWTValidationSettings audCheck) key token

-- | Verify a JWT and return the claims set. Use this if you are using the default claims set.
verify' :: JWK -> SignedJWT -> IO (Either JWTError ClaimsSet)
verify' key token = do
  let audCheck = const True
  runJOSE (verifyClaims (defaultJWTValidationSettings audCheck) key token)

data OAuthRefreshTokenInfo = OAuthRefreshTokenInfo
  { oriId :: OAuthRefreshTokenId,
    oriClientId :: OAuthClientId,
    oriUserId :: UserId,
    oriScopes :: OAuthScopes,
    oriCreatedAt :: UTCTime
  }
  deriving (Eq, Show, Generic)

data OAuthRefreshAccessTokenRequest = OAuthRefreshAccessTokenRequest
  { oartGrantType :: OAuthGrantType,
    oartClientId :: OAuthClientId,
    oartClientSecret :: OAuthClientPlainTextSecret,
    oartRefreshToken :: OAuthRefreshToken
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthRefreshAccessTokenRequest)

instance ToSchema OAuthRefreshAccessTokenRequest where
  schema =
    object "OAuthRefreshAccessTokenRequest" $
      OAuthRefreshAccessTokenRequest
        <$> oartGrantType .= fieldWithDocModifier "grant_type" grantTypeDescription schema
        <*> oartClientId .= fieldWithDocModifier "client_id" clientIdDescription schema
        <*> oartClientSecret .= fieldWithDocModifier "client_secret" clientSecretDescription schema
        <*> oartRefreshToken .= fieldWithDocModifier "refresh_token" refreshTokenDescription schema
    where
      grantTypeDescription = description ?~ "The grant type. Must be `refresh_token`"
      clientIdDescription = description ?~ "The OAuth client's ID"
      clientSecretDescription = description ?~ "The OAuth client's secret"
      refreshTokenDescription = description ?~ "The refresh token"

instance FromForm OAuthRefreshAccessTokenRequest where
  fromForm :: Form -> Either Text OAuthRefreshAccessTokenRequest
  fromForm f =
    OAuthRefreshAccessTokenRequest
      <$> parseUnique "grant_type" f
      <*> parseUnique "client_id" f
      <*> parseUnique "client_secret" f
      <*> parseUnique "refresh_token" f

instance ToForm OAuthRefreshAccessTokenRequest where
  toForm req =
    Form $
      mempty
        & HM.insert "grant_type" [toQueryParam (oartGrantType req)]
        & HM.insert "client_id" [toQueryParam (oartClientId req)]
        & HM.insert "client_secret" [toQueryParam (oartClientSecret req)]
        & HM.insert "refresh_token" [toQueryParam (oartRefreshToken req)]

instance FromForm (Either OAuthAccessTokenRequest OAuthRefreshAccessTokenRequest) where
  fromForm :: Form -> Either Text (Either OAuthAccessTokenRequest OAuthRefreshAccessTokenRequest)
  fromForm f = choose (fromForm @OAuthAccessTokenRequest f) (fromForm @OAuthRefreshAccessTokenRequest f)
    where
      choose :: Either Text OAuthAccessTokenRequest -> Either Text OAuthRefreshAccessTokenRequest -> Either Text (Either OAuthAccessTokenRequest OAuthRefreshAccessTokenRequest)
      choose (Right a) _ = Right (Left a)
      choose _ (Right a) = Right (Right a)
      choose (Left err) _ = Left err

data OAuthRevokeRefreshTokenRequest = OAuthRevokeRefreshTokenRequest
  { ortrClientId :: OAuthClientId,
    ortrClientSecret :: OAuthClientPlainTextSecret,
    ortrRefreshToken :: OAuthRefreshToken
  }
  deriving (Eq, Show, Generic)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthRevokeRefreshTokenRequest)

instance ToSchema OAuthRevokeRefreshTokenRequest where
  schema =
    object "OAuthRevokeRefreshTokenRequest" $
      OAuthRevokeRefreshTokenRequest
        <$> ortrClientId .= fieldWithDocModifier "clientId" clientIdDescription schema
        <*> ortrClientSecret .= fieldWithDocModifier "clientSecret" clientSecretDescription schema
        <*> ortrRefreshToken .= fieldWithDocModifier "refreshToken" refreshTokenDescription schema
    where
      clientIdDescription = description ?~ "The OAuth client's ID"
      clientSecretDescription = description ?~ "The OAuth client's secret"
      refreshTokenDescription = description ?~ "The refresh token"

data OAuthApplication = OAuthApplication
  { oaId :: OAuthClientId,
    oaName :: OAuthApplicationName
  }
  deriving (Eq, Show, Ord)
  deriving (A.ToJSON, A.FromJSON, S.ToSchema) via (Schema OAuthApplication)

instance ToSchema OAuthApplication where
  schema =
    object "OAuthApplication" $
      OAuthApplication
        <$> oaId .= fieldWithDocModifier "id" idDescription schema
        <*> oaName .= fieldWithDocModifier "name" nameDescription schema
    where
      idDescription = description ?~ "The OAuth client's ID"
      nameDescription = description ?~ "The OAuth client's name"

--------------------------------------------------------------------------------
-- Errors

data OAuthError
  = OAuthClientNotFound
  | OAuthRedirectUrlMissMatch
  | OAuthUnsupportedResponseType
  | OAuthJwtError
  | OAuthAuthCodeNotFound
  | OAuthFeatureDisabled
  | OAuthInvalidClientCredentials
  | OAuthInvalidGrantType
  | OAuthInvalidRefreshToken

instance KnownError (MapError e) => IsSwaggerError (e :: OAuthError) where
  addToSwagger = addStaticErrorToSwagger @(MapError e)

type instance MapError 'OAuthClientNotFound = 'StaticError 404 "not-found" "OAuth client not found"

type instance MapError 'OAuthRedirectUrlMissMatch = 'StaticError 400 "redirect-url-miss-match" "The redirect URL does not match the one registered with the client"

type instance MapError 'OAuthUnsupportedResponseType = 'StaticError 400 "unsupported-response-type" "Unsupported response type"

type instance MapError 'OAuthJwtError = 'StaticError 500 "jwt-error" "Internal error while handling JWT token"

type instance MapError 'OAuthAuthCodeNotFound = 'StaticError 404 "not-found" "OAuth authorization code not found"

type instance MapError 'OAuthFeatureDisabled = 'StaticError 403 "forbidden" "OAuth is disabled"

type instance MapError 'OAuthInvalidClientCredentials = 'StaticError 403 "forbidden" "Invalid client credentials"

type instance MapError 'OAuthInvalidGrantType = 'StaticError 403 "forbidden" "Invalid grant type"

type instance MapError 'OAuthInvalidRefreshToken = 'StaticError 403 "forbidden" "Invalid refresh token"

--------------------------------------------------------------------------------
-- CQL instances

instance Cql OAuthApplicationName where
  ctype = Tagged TextColumn
  toCql = CqlText . fromRange . unOAuthApplicationName
  fromCql (CqlText t) = checkedEither t <&> OAuthApplicationName
  fromCql _ = Left "OAuthApplicationName: Text expected"

instance Cql RedirectUrl where
  ctype = Tagged BlobColumn
  toCql = CqlBlob . toByteString
  fromCql (CqlBlob t) = runParser parser (toStrict t)
  fromCql _ = Left "RedirectUrl: Blob expected"

instance Cql OAuthAuthCode where
  ctype = Tagged AsciiColumn
  toCql = CqlAscii . toText . unOAuthAuthCode
  fromCql (CqlAscii t) = OAuthAuthCode <$> validateBase16 t
  fromCql _ = Left "OAuthAuthCode: Ascii expected"

instance Cql OAuthScope where
  ctype = Tagged TextColumn
  toCql = CqlText . cs . toByteString'
  fromCql (CqlText t) = maybe (Left "invalid oauth scope") Right $ fromByteString' (cs t)
  fromCql _ = Left "OAuthScope: Text expected"

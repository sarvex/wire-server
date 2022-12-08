# WARNING: GENERATED FILE, DO NOT EDIT.
# This file is generated by running hack/bin/generate-local-nix-packages.sh and
# must be regenerated whenever local packages are added or removed, or
# dependencies are added or removed.
{ mkDerivation
, aeson
, amazonka
, amazonka-dynamodb
, amazonka-ses
, amazonka-sqs
, async
, attoparsec
, auto-update
, base
, base-prelude
, base16-bytestring
, base64-bytestring
, bilge
, binary
, bloodhound
, brig-types
, bytestring
, bytestring-conversion
, cargohold-types
, case-insensitive
, cassandra-util
, comonad
, conduit
, containers
, cookie
, cryptobox-haskell
, currency-codes
, data-default
, data-timeout
, dns
, dns-util
, either
, email-validate
, enclosed-exceptions
, errors
, exceptions
, extended
, extra
, federator
, file-embed
, file-embed-lzma
, filepath
, fsnotify
, galley-types
, geoip2
, gitignoreSource
, gundeck-types
, hashable
, HaskellNet
, HaskellNet-SSL
, hscim
, HsOpenSSL
, HsOpenSSL-x509-system
, html-entities
, http-api-data
, http-client
, http-client-openssl
, http-client-tls
, http-media
, http-reverse-proxy
, http-types
, imports
, insert-ordered-containers
, iproute
, iso639
, jose
, jwt-tools
, lens
, lens-aeson
, lib
, metrics-core
, metrics-wai
, mime
, mime-mail
, mmorph
, MonadRandom
, mtl
, multihash
, mwc-random
, network
, network-conduit-tls
, optparse-applicative
, pem
, pipes
, polysemy
, polysemy-plugin
, polysemy-wire-zoo
, postie
, process
, proto-lens
, QuickCheck
, random
, random-shuffle
, raw-strings-qq
, resource-pool
, resourcet
, retry
, ropes
, safe
, safe-exceptions
, saml2-web-sso
, schema-profunctor
, scientific
, scrypt
, servant
, servant-client
, servant-client-core
, servant-server
, servant-swagger
, servant-swagger-ui
, sodium-crypto-sign
, spar
, split
, ssl-util
, statistics
, stomp-queue
, streaming-commons
, string-conversions
, swagger
, swagger2
, tagged
, tasty
, tasty-cannon
, tasty-hunit
, tasty-quickcheck
, template
, template-haskell
, temporary
, text
, text-icu-translit
, time
, time-out
, time-units
, tinylog
, transformers
, types-common
, types-common-aws
, types-common-journal
, unliftio
, unordered-containers
, uri-bytestring
, uuid
, vector
, wai
, wai-extra
, wai-middleware-gunzip
, wai-predicates
, wai-route
, wai-routing
, wai-utilities
, warp
, warp-tls
, wire-api
, wire-api-federation
, yaml
, zauth
}:
mkDerivation {
  pname = "brig";
  version = "2.0";
  src = gitignoreSource ./.;
  isLibrary = true;
  isExecutable = true;
  libraryHaskellDepends = [
    aeson
    amazonka
    amazonka-dynamodb
    amazonka-ses
    amazonka-sqs
    async
    attoparsec
    auto-update
    base
    base-prelude
    base16-bytestring
    base64-bytestring
    bilge
    bloodhound
    brig-types
    bytestring
    bytestring-conversion
    cassandra-util
    comonad
    conduit
    containers
    cookie
    cryptobox-haskell
    currency-codes
    data-default
    data-timeout
    dns
    dns-util
    either
    enclosed-exceptions
    errors
    exceptions
    extended
    extra
    file-embed
    file-embed-lzma
    filepath
    fsnotify
    galley-types
    geoip2
    gundeck-types
    hashable
    HaskellNet
    HaskellNet-SSL
    HsOpenSSL
    HsOpenSSL-x509-system
    html-entities
    http-api-data
    http-client
    http-client-openssl
    http-media
    http-types
    imports
    insert-ordered-containers
    iproute
    iso639
    jose
    jwt-tools
    lens
    lens-aeson
    metrics-core
    metrics-wai
    mime
    mime-mail
    mmorph
    MonadRandom
    mtl
    multihash
    mwc-random
    network
    network-conduit-tls
    optparse-applicative
    pem
    polysemy
    polysemy-plugin
    polysemy-wire-zoo
    proto-lens
    random-shuffle
    resource-pool
    resourcet
    retry
    ropes
    safe
    safe-exceptions
    saml2-web-sso
    schema-profunctor
    scientific
    scrypt
    servant
    servant-client
    servant-client-core
    servant-server
    servant-swagger
    servant-swagger-ui
    sodium-crypto-sign
    split
    ssl-util
    statistics
    stomp-queue
    string-conversions
    swagger
    swagger2
    tagged
    template
    template-haskell
    text
    text-icu-translit
    time
    time-out
    time-units
    tinylog
    transformers
    types-common
    types-common-aws
    types-common-journal
    unliftio
    unordered-containers
    uri-bytestring
    uuid
    vector
    wai
    wai-extra
    wai-middleware-gunzip
    wai-predicates
    wai-routing
    wai-utilities
    warp
    wire-api
    wire-api-federation
    yaml
    zauth
  ];
  executableHaskellDepends = [
    aeson
    async
    attoparsec
    base
    base16-bytestring
    base64-bytestring
    bilge
    bloodhound
    brig-types
    bytestring
    bytestring-conversion
    cargohold-types
    case-insensitive
    cassandra-util
    containers
    cookie
    data-default
    data-timeout
    email-validate
    exceptions
    extended
    extra
    federator
    filepath
    galley-types
    gundeck-types
    hscim
    HsOpenSSL
    http-api-data
    http-client
    http-client-tls
    http-media
    http-reverse-proxy
    http-types
    imports
    jose
    lens
    lens-aeson
    metrics-wai
    mime
    mime-mail
    MonadRandom
    mtl
    network
    optparse-applicative
    pem
    pipes
    polysemy
    polysemy-wire-zoo
    postie
    process
    proto-lens
    QuickCheck
    random
    random-shuffle
    raw-strings-qq
    retry
    safe
    saml2-web-sso
    servant
    servant-client
    servant-client-core
    spar
    streaming-commons
    string-conversions
    tasty
    tasty-cannon
    tasty-hunit
    temporary
    text
    time
    time-units
    tinylog
    transformers
    types-common
    types-common-aws
    types-common-journal
    unliftio
    unordered-containers
    uri-bytestring
    uuid
    vector
    wai
    wai-extra
    wai-route
    wai-utilities
    warp
    warp-tls
    wire-api
    wire-api-federation
    yaml
    zauth
  ];
  testHaskellDepends = [
    aeson
    base
    binary
    bloodhound
    brig-types
    bytestring
    containers
    data-timeout
    dns
    dns-util
    exceptions
    HsOpenSSL
    http-types
    imports
    lens
    polysemy
    polysemy-wire-zoo
    QuickCheck
    retry
    servant-client-core
    string-conversions
    tasty
    tasty-hunit
    tasty-quickcheck
    time
    tinylog
    types-common
    unliftio
    uri-bytestring
    uuid
    wai-utilities
    wire-api
    wire-api-federation
  ];
  description = "User Service";
  license = lib.licenses.agpl3Only;
}

# Server and team feature settings

Features can be enabled or disabled on a team level or server wide. Here we will only cover the server wide configuration.

When a feature's lock status is `unlocked` it means that its settings can be overridden on a team level by team admins. This can be done via the team management app or via the team feature API and is not covered here.

## 2nd factor password challenge

By default Wire enforces a 2nd factor authentication for certain user operations like e.g. activating an account, changing email or password, or deleting an account.

If the `sndFactorPasswordChallenge` feature is enabled, a 6 digit verification code will be send per email to authenticate for additional user operations like e.g. for login, adding a new client, generating SCIM tokens, or deleting a team.

After 3 attempts, the key is invalidated, and requests for generating new verification codes are rate limited. The default delay between two consecutive requests is 5 minutes.

Usually the default is what you want. If you explicitly want to enable additional password challenges, add the following to your Helm overrides in `values/wire-server/values.yaml`:

```yaml
galley:
  # ...
  config:
    # ...
    settings:
      # ...
      featureFlags:
        # ...
        sndFactorPasswordChallenge:
          defaults:
            status: enabled
            lockStatus: locked
```

Note that the lock status is required but has no effect, as it is currently not supported for team admins to enable or disable `sndFactorPasswordChallenge`. We recommend to set the lock status to `locked`.

Currently the 2nd factor password challenge if enabled has no effect for SSO users.

## Rate limiting of code generation requests

The default delay between code generation requests is 5 minutes. This setting can be overridden in the Helm charts:

```yaml
brig:
  # ...
  config:
    # ...
    optSettings:
      # ...
      set2FACodeGenerationDelaySecs: 300 # 5 minutes
```

## Guest links

The guest link feature is the ability for a Wire users to join a group conversation by tapping on a unique link generated by an admin of that group.

The feature is enabled and unlocked by default and can be disabled on a per-team (via team management) basis or disabled and optionally locked for the entire backend (via Helm overrides). If the feature is locked, it cannot be enabled by team admins via team management.

To change the configuration for the entire server, add the following to your Helm overrides in `values/wire-server/values.yaml`:

```yaml
galley:
  # ...
  config:
    # ...
    settings:
      # ...
      featureFlags:
        # ...
        conversationGuestLinks:
          defaults:
            status: disabled
            lockStatus: locked
```

## TTL for nonces

Nonces that can be retrieved e.g. by calling `HEAD /nonce/clients` have a default time-to-live of 5 minutes. To change this setting add the following to your Helm overrides in `values/wire-server/values.yaml`:

```yaml
brig:
  # ...
  config:
    # ...
    optSettings:
      # ...
      setNonceTtlSecs: 360 # 6 minutes
```

## MLS End-to-End Identity

The MLS end-to-end identity team feature adds an extra level of security and practicability. If turned on, automatic device authentication ensures that team members know they are communicating with people using authenticated devices. Team members get a certificate on all their devices.

When a client first tries to fetch or renew a certificate, they may need to login to an identity provider (IdP) depending on their IdP domain authentication policy. The user may have a grace period during which they can “snooze” this login. The duration of this grace period (in seconds) is set in the `verificationDuration` parameter, which is enforced separately by each client. After the grace period has expired, the client will not allow the user to use the application until they have logged to refresh the certificate. The default value is 1 day (86400s).

```yaml
galley:
  # ...
  config:
    # ...
    settings:
      # ...
      featureFlags:
        # ...
        mlsE2EId:
          defaults:
            status: disabled
            config:
              verificationExpiration: 86400
              acmeDiscoveryUrl: https://acme.example.com/acme/provisioner1/discovery
            lockStatus: unlocked
```

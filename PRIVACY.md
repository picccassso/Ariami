# Ariami Privacy Policy

**Effective date:** 14 July 2026

This Privacy Policy applies to **Ariami Mobile** on Android and iOS and
**Ariami TV** on Android TV and Fire TV (together, the **Apps**), published by
Ariami. It applies regardless of whether an App is obtained through Google
Play, the Apple App Store, the Amazon Appstore, or another official Ariami
distribution channel.

## Our privacy commitment

Ariami is a self-hosted music system. The Apps connect to an Ariami server
chosen and operated by you or your household. Ariami does not operate a cloud
music service and the Ariami developer does not receive or maintain a central
copy of your music library, account, playlists, listening history, or playback
activity.

The Apps:

- do not contain advertising;
- do not use analytics, telemetry, tracking pixels, or behavioural profiling;
- do not use advertising identifiers;
- do not sell, rent, or share personal data for advertising or marketing; and
- do not send your music files or listening activity to the Ariami developer.

## Data processed by the Apps

The Apps process only the information needed to provide their features. Except
for the optional licence activation described below, this information stays on
your device or is exchanged directly with the Ariami server you choose.

### Account and authentication information

When you register or sign in, the App sends your username, password, an
app-generated device identifier, and a generic device label to your chosen
Ariami server. The server stores a securely hashed version of the password and
uses session tokens to keep you signed in. Session tokens are stored using
secure device storage where the platform supports it.

This information is controlled by the person who operates that Ariami server.
It is not sent to or stored by the Ariami developer.

### Music, library, and profile information

Your chosen Ariami server may process and provide the Apps with:

- audio files and streams;
- song, artist, album, and playlist metadata;
- cover art and profile images;
- pins, playlist edits, and other library preferences; and
- listening history, playback state, and connected-device status.

The Apps may cache some of this information locally to support playback,
downloads, artwork, preferences, and offline use. It is not sent to the Ariami
developer.

### Device information

Each App creates a random, app-specific identifier so your chosen Ariami server
can distinguish sessions and connected playback devices. Ariami does not use
hardware identifiers, the Android Advertising ID, or this app-specific
identifier for tracking or advertising.

### Camera and files

Ariami Mobile may request camera access to scan a server pairing QR code. QR
codes are processed for pairing and camera images are not uploaded to the
Ariami developer.

Ariami Mobile may also access files or media that you explicitly choose for
features such as importing, exporting, downloading, or selecting artwork. This
content is processed on your device or exchanged with your chosen Ariami
server. It is not uploaded to the Ariami developer.

### Local network and casting

The Apps use network access to discover and connect to your chosen Ariami
server. If you choose to use Google Cast, Ariami Mobile sends the information
needed for playback to the Cast device you select. Google services involved in
that user-initiated feature are governed by the
[Google Privacy Policy](https://policies.google.com/privacy).

## Optional Ariami TV licence activation

The paid Ariami TV product requires a licence. When you choose to activate a
licence key in Ariami Mobile or Ariami TV, the following limited information is
processed solely to verify the purchase and issue a signed licence:

- the licence key;
- a generic device label, such as `Android Device` or `Ariami TV`;
- the licence, product, and activation identifiers associated with the
  purchase;
- the purchaser email address already associated with the licence provider;
  and
- the network address used temporarily for abuse prevention and rate limiting.

The activation request passes through Ariami's licence endpoint, hosted by
Cloudflare, and the licence is validated by Lemon Squeezy. The Ariami endpoint
does not maintain a persistent analytics or marketing database and does not log
licence keys. It returns a signed licence file, which is then stored on your
device or your chosen Ariami server.

Cloudflare and Lemon Squeezy process information under their own privacy
policies:

- [Cloudflare Privacy Policy](https://www.cloudflare.com/privacypolicy/)
- [Lemon Squeezy Privacy Policy](https://www.lemonsqueezy.com/privacy)

Payments are handled by the store or payment provider. The Apps do not receive
or store your full payment-card details.

## App marketplace and platform services

Google, Apple, or Amazon may process information when you use their respective
storefronts or platform services to download, update, purchase, or review an
App. This processing takes place outside Ariami or is performed by the platform
provider independently. Ariami does not receive your full payment-card details
or use store-provided information for advertising or behavioural tracking.

Those providers describe their practices in their own privacy notices:

- [Google Privacy Policy](https://policies.google.com/privacy)
- [Apple Privacy Policy](https://www.apple.com/legal/privacy/)
- [Amazon Privacy Notice](https://www.amazon.com/gp/help/customer/display.html?nodeId=GX7NJQ4ZB8MHFRNJ)

## Data retention and deletion

Ariami does not maintain a central account, music, analytics, or listening-data
database for the Apps.

- **On your device:** locally cached data remains until it is removed through
  the App, the App's storage is cleared, or the App is uninstalled.
- **On your Ariami server:** account and library-related data remains until you
  or the server owner deletes the account or resets/removes the server data.
  Server owners can manage and delete user accounts through the Ariami server
  administration interface.
- **Licence data:** the signed licence remains on your device or Ariami server
  until it is removed. Purchase and activation records held by Lemon Squeezy or
  Cloudflare are subject to their respective retention policies and applicable
  legal obligations.

Because Ariami servers are self-hosted, the Ariami developer cannot access or
delete data held on your server. Requests concerning an account on a particular
Ariami server should be directed to that server's owner or administrator.

## Security

Ariami uses app-specific identifiers, password hashing, session authentication,
and secure device storage for sensitive tokens where supported. You are
responsible for securing the device and network on which you run your Ariami
server.

Ariami should be used on a trusted local network, through an encrypted private
network such as Tailscale, or through a properly configured HTTPS endpoint. Do
not expose an unsecured Ariami server directly to the public internet.

## Children's privacy

The Apps are not directed specifically at children and do not knowingly
collect children's personal information for the Ariami developer. Accounts and
content on a self-hosted Ariami server are controlled by that server's owner.

## Changes to this policy

If the Apps' data practices change, this policy will be updated before those
changes are released. The effective date at the top of this document identifies
the latest revision.

## Contact

For privacy questions about the Apps, contact Ariami by opening a support
request that contains no private data through the
[Ariami issue tracker](https://github.com/picccassso/Ariami/issues). Do not
include passwords, licence keys, session tokens, or other secrets in a public
issue.

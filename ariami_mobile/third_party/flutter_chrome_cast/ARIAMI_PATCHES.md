# Ariami Cast patch

Vendored runtime sources from flutter_chrome_cast 1.4.6 on pub.dev.
Upstream: https://github.com/felnanuke2/flutter_google_cast
The upstream BSD-3-Clause license is retained in LICENSE.

The only runtime change is in lib/entities/track.dart: default a missing or
null trackContentType to an empty string. Google Home Mini status messages
can include an in-band audio track as {"trackId":1,"type":"AUDIO"}. Requiring
a content type throws during status parsing, leaving the sender on its last
buffering status even after the receiver has loaded the media.

Regression coverage lives in the app test/services/cast directory. Remove
this override once an upstream release handles this receiver payload.

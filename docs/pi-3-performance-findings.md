# Raspberry Pi 3 Performance Findings

These are real usage findings from commit `d4b2f4e`, the Pi performance work.
This is not a lab benchmark, just what it felt like and what was measured while
actually using Ariami on a Pi 3.

## Test Setup

- Raspberry Pi 3
- Active fan running all the time
- 32GB Integral microSD card
- Connected over Ethernet
- Test library: around 530 songs

## What Changed In Real Usage

The biggest thing is that playback just feels much snappier now. Before, moving
between songs could take a few seconds and it felt like the Pi was having to
think about the whole library. After the Pi performance work, tracks just load.

Original quality playback is genuinely good. Even while the Pi was downloading
at the same time, switching original quality songs still worked fine.

Cold transcoding is still the slow bit, which is expected on a Pi 3. But the
rest of the app is no longer being dragged down by it.

## Original Quality Over Mobile Data

This was tested from a bad mobile data spot, so the network was not ideal.

- First song: 4 seconds
- Second song: 4 seconds
- Third song: 3 seconds

That is honestly pretty good. Original quality is basically network and file
serving, without the Pi having to transcode.

## Medium/Low Uncached Over Mobile Data

For this test, a new playlist was opened each time, so these were cold starts.

- First song: 21 seconds
- Second song: 22 seconds
- Third song: 26 seconds

This is the worst case. The Pi has to start transcoding and the phone has to
buffer over mobile data. It is slow, but it makes sense for a Pi 3.

## Medium/Low Next Queued Track After Warmup

Ignoring the first cold song that takes around 21 seconds, the next queued songs
were much better:

- First warmed song: 5 seconds
- Second warmed song: 7 seconds
- Third warmed song: 3 seconds
- Fourth warmed song: 6 seconds
- Fifth warmed song: 5 seconds

This shows the warmup work is actually doing something useful. Like, cold starts
are still cold starts, but once the queue is moving, medium/low playback over bad
mobile data becomes much more usable.

## Full Library Download

Original quality downloads were surprisingly decent.

In around 3 minutes, the Pi downloaded about 198 songs total.

That is roughly:

- 66 songs per minute
- 1.1 songs per second
- Around 3,960 songs per hour, depending on average track size

The Pi could stream and download at the same time, which was genuinely quite
surprising.

## Transcoded Downloads

Transcoded full-library downloads are much slower.

In around 2 minutes, only about 10 songs downloaded.

That works out to roughly:

- 5 songs per minute
- Around 300 songs per hour
- Around 1 hour 45 minutes for the 530 song test library

Only one core was being hit hard during transcoding, which is probably the right
tradeoff on a Pi 3. It keeps the rest of the system usable, and original quality
streaming still worked fine while this was happening.

## Resource Usage Notes

During original quality streaming and downloading, the Pi looked healthy. CPU was
not pegged, load was elevated but fine, and playback still felt responsive.

During transcoding, one core hit 100%, but the Pi stayed usable. Since this Pi 3
had an active fan running all the time, thermal throttling was not really the
main concern. The actual limit is just Pi 3 CPU performance.

## Overall Takeaway

The Pi 3 is honestly more capable than expected here.

Original quality playback and downloads are very usable. Medium/low cold
transcoding is still slow, but warmed queued tracks are much better. The main
win from the Pi performance work is that Ariami no longer feels blocked by large
library lookups or avoidable disk/process work. The Pi stays responsive, and
tracks just load.

These optimisations should also carry over to Pi 4 and Pi 5. The lookup,
catalog, warmup, bitrate, and microSD improvements help all Pis, while newer
hardware should have a much easier time with the remaining bottleneck:
transcoding.

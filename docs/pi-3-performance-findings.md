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

---

## Update: May 2026 — follow-up tuning and another real-world pass

This is a second round of “how it actually feels” testing after further server
work and CLI tuning on the Pi 3: notably **two concurrent transcode slots**
(streaming and download transcodes can run in parallel up to that cap) and
**four concurrent original-quality downloads per user** (up from two), on top
of the earlier lookup, catalog, warmup, and cache behaviour fixes.

Same disclaimer as above: not a lab benchmark, mixed WiFi and mobile data, and
reception quality varies. The Pi had been pleasant to use before; this pass was
mostly “does it still hold up, and what do the numbers look like now?”

### Streaming (WiFi and mobile)

Playback when streaming felt **very responsive**. On WiFi, skipping to the next
song felt effectively **immediate**. On **mobile data** (poor reception spot),
starts were still only about **1–2 seconds** in practice, with **low CPU usage
spread across cores** in `htop` — nothing like the old “whole machine thinking”
feeling before the performance work.

### Original-quality downloads (bulk, while using the app)

Bulk download at **original quality** stayed smooth while **streaming**,
jumping between **playlists**, and **seeking** in tracks — nothing fell over.

Roughly **268 songs inside three minutes** while doing that multitasking. CPU
in `htop` used **all cores** but **no core went much past ~20%**, and load was
spread rather than one core doing everything. Downloads feel “a little slow”
compared to a big desktop, but the aggregate throughput on a Pi 3 was still
surprisingly strong.

### Low/medium download while streaming (WiFi)

With **low or medium quality downloading** and **streaming at the same time**
over WiFi, **two cores sat at 100%** most of the time (consistent with **two**
transcode workers). Another core sometimes picked up work but was not fully
pegged. **Streaming kept working fine** despite that.

Roughly **22 transcoded songs in two minutes** in that scenario — good going for
an old Pi 3.

### Original quality over mobile data (time to start playback)

Cold-ish starts, bad mobile spot:

- First song: **3 seconds**
- Second song: **10 seconds**
- Third song: **3 seconds**
- Fourth song: **6 seconds**
- Fifth song: **3 seconds**

Still mostly “network plus luck,” but broadly in line with “original is easy on
the Pi.”

### Medium/low uncached over mobile data (new playlist each time)

Each run opened a **new playlist** so these stayed **cold** transcode starts on
**mobile data**:

- First song: **14 seconds**
- Second song: **15 seconds**
- Third song: **12 seconds**
- Fourth song: **36 seconds** (notably a **~4 minute** track — longer encode +
  more bytes over a weak link)

Compared to the earlier ~21–26 s cold samples in this doc, this pass sometimes
looked **a bit better**, but the long track shows how much variance you still
get from **file length** and **RF conditions**.

### Medium/low warm queue (WiFi, after the first cold stretch)

Once the queue was **moving** and the first heavy cold start was out of the way
(the first song in this block was still on the order of **~14 seconds**), times
on **WiFi** for the next tracks were:

- First warmed song: **4 seconds**
- Second: **2 seconds**
- Third: **2 seconds**
- Fourth: **2 seconds**
- Fifth: **2 seconds**

So: cold medium/low is still “Pi 3 + transcode + maybe bad radio”; a **warm
queue on a decent link** is where it starts to feel **almost instant**.

### Takeaway from this pass

The Pi 3 remains transcode-bound for medium/low **cold** paths, but **playback
and skipping** can feel **damn impressive** for the hardware, and **mixed
download + stream + UI use** stayed solid. Two cores at full tilt under parallel
transcode is expected; the win is that **the rest of the experience did not
collapse** around it.

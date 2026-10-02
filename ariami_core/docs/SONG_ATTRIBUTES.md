# Custom song attributes

You can attach your own information to any track in your library (a mood, a
BPM, a cleaned-up list of genres, whether it's instrumental) and then ask
your Ariami server for the songs that match.

This is aimed at tools that sit alongside Ariami. For example, you might run
[Essentia](https://essentia.upf.edu/) over your music to work out genre and
mood, send the results to Ariami, and then build playlists like "every
instrumental track that isn't already in my Focus playlist".

## What you can do

- **Tag tracks** with true/false flags, numbers, and lists of words.
- **Find songs** that match any combination of tags, and leave out songs that
  are (or aren't) in a playlist.
- **Sort** the results by any number or true/false tag.
- **Turn the results into a playlist**, which then shows up in every Ariami
  app on every device.

The tags live on your server, and every account on that server sees the same
values. The Ariami apps keep showing the genre from your file tags. Your tags
come back through the API described below, ready for your own tools to use.

## Before you start

You'll need:

- an Ariami Desktop Server or CLI server newer than 5.2.3,
- any account on that server (it doesn't have to be the owner), and
- something that can send HTTP requests. The examples use `curl`, but any
  language works.

The examples assume your server is at `http://192.168.1.20:8080`. Swap in
the address your apps connect to.

## Quick start

### 1. Log in

```bash
curl -s -X POST http://192.168.1.20:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username": "me", "password": "secret", "deviceId": "my-tagger", "deviceName": "My tagger"}'
```

Copy the `sessionToken` from the reply and keep it handy. Every request
below sends it in an `Authorization` header. Your tool appears in Ariami's
connected devices list under the `deviceName` you picked.

```bash
TOKEN='paste-your-session-token-here'
```

### 2. List your library

Ask for every song with an empty query:

```bash
curl -s -X POST http://192.168.1.20:8080/api/v2/songs/query \
  -H "Authorization: Bearer $TOKEN" \
  -d '{}'
```

Each song comes back with an `id` and a `path`. The path is relative to your
music folder and always uses `/`, for example `Bonobo/Migration/01 Migration.flac`.
You can use either one to tag the song in the next step.

### 3. Tag some songs

```bash
curl -s -X PUT http://192.168.1.20:8080/api/v2/song-attributes \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "items": [
      {
        "path": "Bonobo/Migration/01 Migration.flac",
        "attributes": { "instrumental": true, "genres": ["downtempo", "electronic"], "bpm": 92 }
      }
    ]
  }'
```

The reply tells you which songs were updated:

```json
{ "results": [ { "songId": "3f2a9c1b7d4e", "status": "updated" } ] }
```

### 4. Find matching songs

All instrumental downtempo tracks, slowest first:

```bash
curl -s -X POST http://192.168.1.20:8080/api/v2/songs/query \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "where": [
      { "attr": "instrumental", "eq": true },
      { "attr": "genres", "contains": "downtempo" }
    ],
    "sort": [ { "attr": "bpm", "dir": "asc" } ]
  }'
```

### 5. Save the results as a playlist

Pick an id that starts with `created:` and send the song ids you want, in
order:

```bash
curl -s -X PUT http://192.168.1.20:8080/api/playlists/created%3Achill-instrumentals/edit \
  -H "Authorization: Bearer $TOKEN" \
  -d '{ "name": "Chill instrumentals", "songIds": ["3f2a9c1b7d4e"], "baseSnapshot": [] }'
```

The playlist appears straight away in the apps of the account you logged in
with. Send the same request again with a new `songIds` list whenever you want
to refresh it.

## Tagging songs

`PUT /api/v2/song-attributes`

```json
{
  "items": [
    { "path": "Artist/Album/01 Track.flac", "attributes": { "instrumental": true, "bpm": 120 } },
    { "songId": "a1b2c3d4e5f6", "attributes": { "danceability": 0.73, "mood": null } }
  ]
}
```

- Name each song with `songId` or `path`. If you send both, Ariami uses
  `songId`.
- A tag value can be `true` or `false`, a number (whole or decimal), or a
  list of words such as `["ambient", "post-rock"]`.
- Set a tag to `null` to remove it. Tags you leave out stay as they are, so
  you can update one tag at a time.
- Tag names can be 1 to 64 characters long.
- Send up to 500 songs per request. For a bigger library, split your updates
  into batches.

The reply lists one result per song, in the order you sent them. A song
Ariami can't find comes back as `{"status": "not_found"}`, and the rest of
the batch still saves.

If any item in the request is malformed (a missing `path`, a tag value that
is a single word instead of a list), Ariami rejects the whole request with a
`400` and an error message, and saves nothing.

## Finding songs

`POST /api/v2/songs/query`

```json
{
  "where": [
    { "attr": "instrumental", "eq": true },
    { "attr": "genres", "contains": "ambient" },
    { "attr": "bpm", "gte": 90, "lt": 130 },
    { "notInPlaylist": "created:focus" }
  ],
  "sort": [ { "attr": "bpm", "dir": "asc" } ],
  "limit": 500
}
```

A song has to match every condition in `where` to be included.

| Condition | Value | Matches songs whose tag... |
| --- | --- | --- |
| `eq` | true/false or a number | equals the value |
| `ne` | true/false or a number | has a different value |
| `gt`, `gte`, `lt`, `lte` | a number | is greater than, at least, less than, or at most the value |
| `contains` | a word | is a list that includes the word |
| `containsAny` | a list of words | is a list that includes at least one of them |
| `exists` | true/false | is set (`true`) or missing (`false`) |

A few things worth knowing:

- Conditions only match songs that have the tag. So `{"attr": "instrumental", "ne": true}`
  finds songs tagged `false` and skips songs you haven't tagged yet. Use
  `{"attr": "instrumental", "exists": false}` to find the untagged ones.
- You can put several checks in one condition, and all of them have to pass.
  `{"attr": "bpm", "gte": 90, "lt": 130}` means "from 90 up to 130".
- Word matching is exact, so `"Ambient"` and `"ambient"` are different words.
  Pick one style in your tool and stick to it.

### Playlists in a query

Use `{"inPlaylist": "<playlist id>"}` or `{"notInPlaylist": "<playlist id>"}`
on their own, without an `attr`.

Ariami checks the playlist as the account you logged in with sees it,
including any changes that account made. That covers folder playlists,
playlists created in the apps, and Liked Songs (`__LIKED_SONGS__`).

To find a playlist's id:

- folder playlists are listed by `GET /api/v2/playlists`, and
- playlists created in the apps (ids starting with `created:`) are listed by
  `GET /api/playlists/edits`.

### Sorting and pages

- `sort` takes a list of `{"attr": "...", "dir": "asc"}` or `"desc"` entries.
  Ariami sorts numbers by size and puts `false` before `true`. Songs without
  the tag go last either way.
- `limit` sets the page size, from 1 to 500 (100 if you leave it out).
- When there are more results, the reply includes a `nextCursor`. Send it
  back as `"cursor"` with the same query to get the next page. On the last
  page `nextCursor` is `null`.

### What comes back

```json
{
  "songs": [
    {
      "id": "3f2a9c1b7d4e",
      "path": "Bonobo/Migration/01 Migration.flac",
      "title": "Migration",
      "artist": "Bonobo",
      "albumId": "8c1d0e2f4a6b",
      "genre": "Electronic",
      "duration": 342,
      "trackNumber": 1,
      "attributes": { "instrumental": true, "genres": ["downtempo", "electronic"], "bpm": 92 }
    }
  ],
  "total": 1,
  "nextCursor": null
}
```

`genre` is whatever your file's genre tag says. `attributes` holds the tags
you sent. `total` counts every match across all pages.

## When files move

Ariami works out a song's `id` from its file path. Renaming or moving a file
gives the song a new `id` and a new `path`, and its tags stay with the old
one.

If your tool keeps its own database, give each track a key that survives a
move, such as a hash of the audio. Then, to pick up moved files:

1. Poll `GET /api/v2/changes?since=<token>` to see which songs were removed
   and added since you last checked.
2. Match the new songs to your records using that key.
3. Send their tags again.

Re-sending tags is always safe. The same request twice leaves the same
result.

Your tags survive rescans and library changes. A full server reset clears
them along with the rest of the catalogue, so keep your own copy and send
it again afterwards.

## Errors

| Status | Meaning |
| --- | --- |
| `400` | The request body is malformed. The `error.message` field says what to fix. |
| `401` | The session token is missing or has expired. Log in again. |
| `503` | The server is still starting up or hasn't scanned a library yet. Try again shortly. |

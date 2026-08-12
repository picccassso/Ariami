import 'dart:convert';

import 'package:ariami_core/ariami_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('LastFmRecommendationClient', () {
    test('uses unauthenticated similarity methods and parses JSON', () async {
      final requests = <Uri>[];
      final client = LastFmRecommendationClient(
        apiKey: 'test-key',
        endpoint: Uri.https('example.test', '/2.0/'),
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final method = request.url.queryParameters['method'];
          if (method == 'artist.getsimilar') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'similarartists': <String, dynamic>{
                  'artist': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'name': 'New Artist',
                      'match': '0.92',
                      'mbid': 'artist-mbid',
                      'url': 'http://www.last.fm/music/New+Artist',
                      'image': <Map<String, dynamic>>[
                        <String, dynamic>{
                          '#text': 'http://images.example/small.jpg',
                          'size': 'small',
                        },
                        <String, dynamic>{
                          '#text': 'https://images.example/large.jpg',
                          'size': 'large',
                        },
                      ],
                    },
                  ],
                },
              }),
              200,
            );
          }
          if (method == 'artist.gettopalbums') {
            return _jsonResponse(<String, dynamic>{
              'topalbums': <String, dynamic>{
                'album': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'name': 'Artist Album',
                    'url': 'https://www.last.fm/music/New+Artist/Artist+Album',
                    'image': <Map<String, dynamic>>[
                      <String, dynamic>{
                        '#text': 'https://images.example/artist-album.jpg',
                        'size': 'extralarge',
                      },
                    ],
                  },
                ],
              },
            });
          }
          if (method == 'track.getinfo') {
            return _jsonResponse(<String, dynamic>{
              'track': <String, dynamic>{
                'album': <String, dynamic>{
                  'image': <Map<String, dynamic>>[
                    <String, dynamic>{
                      '#text': 'https://images.example/album.jpg',
                      'size': 'extralarge',
                    },
                  ],
                },
              },
            });
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'similartracks': <String, dynamic>{
                // Last.fm sometimes returns one object instead of a list.
                'track': <String, dynamic>{
                  'name': 'New Track',
                  'match': '10.5',
                  'url': 'https://www.last.fm/music/New/_/New+Track',
                  'artist': <String, dynamic>{'name': 'New'},
                  'image': <String, dynamic>{
                    '#text': 'http://images.example/track.jpg',
                    'size': 'medium',
                  },
                },
              },
            }),
            200,
          );
        }),
      );

      final artists = await client.similarArtists('Seed Artist');
      final tracks = await client.similarTracks(
        artist: 'Seed Artist',
        track: 'Seed Track',
      );
      final artistImage = await client.artistImage('New Artist');
      final trackImage = await client.trackImage(
        artist: 'New',
        track: 'New Track',
      );

      expect(artists.single.name, 'New Artist');
      expect(artists.single.musicBrainzId, 'artist-mbid');
      expect(artists.single.url.scheme, 'https');
      expect(artists.single.imageUrl,
          Uri.parse('https://images.example/large.jpg'));
      expect(tracks.single.artist, 'New');
      expect(tracks.single.match, closeTo(0.105, 0.0001));
      expect(tracks.single.imageUrl,
          Uri.parse('https://images.example/track.jpg'));
      expect(artistImage, Uri.parse('https://images.example/artist-album.jpg'));
      expect(trackImage, Uri.parse('https://images.example/album.jpg'));
      expect(requests, hasLength(4));
      expect(
          requests.first.queryParameters, containsPair('api_key', 'test-key'));
      expect(requests.first.queryParameters, containsPair('autocorrect', '1'));
      expect(requests.first.queryParameters, containsPair('format', 'json'));
      final similarTrackRequest = requests.singleWhere(
        (uri) => uri.queryParameters['method'] == 'track.getsimilar',
      );
      expect(similarTrackRequest.queryParameters,
          containsPair('track', 'Seed Track'));
    });

    test('surfaces invalid API keys distinctly', () async {
      final client = LastFmRecommendationClient(
        apiKey: 'bad-key',
        endpoint: Uri.https('example.test', '/2.0/'),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, dynamic>{
              'error': 10,
              'message': 'Invalid API Key',
            }),
            200,
          ),
        ),
      );

      await expectLater(
        client.similarArtists('Seed'),
        throwsA(
          isA<LastFmRecommendationException>()
              .having((error) => error.isInvalidApiKey, 'invalid key', isTrue),
        ),
      );
    });

    test('parses track and artist community tags from info responses',
        () async {
      final client = LastFmRecommendationClient(
        apiKey: 'key',
        endpoint: Uri.https('example.test', '/2.0/'),
        httpClient: MockClient((request) async {
          if (request.url.queryParameters['method'] == 'artist.getinfo') {
            return _jsonResponse(<String, dynamic>{
              'artist': <String, dynamic>{
                'tags': <String, dynamic>{
                  'tag': <Map<String, dynamic>>[
                    <String, dynamic>{'name': 'Jazz'},
                    <String, dynamic>{'name': 'Funk'},
                  ],
                },
              },
            });
          }
          return _jsonResponse(<String, dynamic>{
            'track': <String, dynamic>{
              'toptags': <String, dynamic>{
                'tag': <Map<String, dynamic>>[
                  <String, dynamic>{'name': 'Instrumental Rock'},
                ],
              },
              'album': <String, dynamic>{
                'image': <Map<String, dynamic>>[
                  <String, dynamic>{
                    '#text': 'https://images.example/instrumental.jpg',
                    'size': 'large',
                  },
                ],
              },
            },
          });
        }),
      );

      final artist = await client.artistMetadata('Artist');
      final track = await client.trackMetadata(
        artist: 'Artist',
        track: 'Instrumental',
      );

      expect(artist.tags, <String>{'jazz', 'funk'});
      expect(track.tags, <String>{'instrumental rock'});
      expect(
          track.imageUrl, Uri.parse('https://images.example/instrumental.jpg'));
    });

    test('loads ranked track and artist candidates from an arbitrary tag',
        () async {
      final methods = <String>[];
      final client = LastFmRecommendationClient(
        apiKey: 'key',
        endpoint: Uri.https('example.test', '/2.0/'),
        httpClient: MockClient((request) async {
          final method = request.url.queryParameters['method']!;
          methods.add(method);
          expect(request.url.queryParameters['tag'], 'fusion');
          if (method == 'tag.gettoptracks') {
            return _jsonResponse(<String, dynamic>{
              'tracks': <String, dynamic>{
                'track': <Map<String, dynamic>>[
                  _tagTrack('Fusion Track', 'Fusion Artist'),
                ],
              },
            });
          }
          return _jsonResponse(<String, dynamic>{
            'topartists': <String, dynamic>{
              'artist': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'Fusion Artist',
                  'url': 'https://www.last.fm/music/Fusion+Artist',
                },
              ],
            },
          });
        }),
      );

      final tracks = await client.topTracksForTag(' Fusion ');
      final artists = await client.topArtistsForTag('Fusion');

      expect(tracks.single.name, 'Fusion Track');
      expect(tracks.single.match, 1);
      expect(artists.single.name, 'Fusion Artist');
      expect(artists.single.match, 1);
      expect(methods, <String>['tag.gettoptracks', 'tag.gettopartists']);
    });
  });

  group('MusicRecommendationService', () {
    test('enriches artwork for every visible recommendation', () async {
      var artworkRequests = 0;
      final httpClient = MockClient((request) async {
        final method = request.url.queryParameters['method'];
        if (method == 'artist.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similarartists': <String, dynamic>{
              'artist': <Map<String, dynamic>>[
                for (var index = 0; index < 15; index++)
                  _artist('Artist $index', 1 - index / 100),
              ],
            },
          });
        }
        if (method == 'artist.gettopalbums') {
          artworkRequests++;
          final artist = request.url.queryParameters['artist'];
          return _jsonResponse(<String, dynamic>{
            'topalbums': <String, dynamic>{
              'album': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': '$artist Album',
                  'url': 'https://www.last.fm/music/$artist/album',
                  'image': <Map<String, dynamic>>[
                    <String, dynamic>{
                      '#text': 'https://images.example/$artist.jpg',
                      'size': 'large',
                    },
                  ],
                },
              ],
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      });
      final service = MusicRecommendationService(
        lastFm: LastFmRecommendationClient(
          apiKey: 'key',
          endpoint: Uri.https('example.test', '/2.0/'),
          httpClient: httpClient,
        ),
        musicBrainz: MusicBrainzIdentityClient(
          endpoint: Uri.https('example.test', '/ws/2/'),
          httpClient: httpClient,
          requestSpacing: Duration.zero,
        ),
        musicBrainzLookupLimit: 0,
      );

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.artist('Seed Artist'),
        ],
        ownedTracks: const <OwnedMusicTrack>[],
      );

      expect(result.recommendations, hasLength(15));
      expect(
        result.recommendations.every((item) => item.imageUrl != null),
        isTrue,
      );
      expect(artworkRequests, 15);
    });

    test('ranks locally, identifies, deduplicates, and filters owned music',
        () async {
      final musicBrainzRequests = <http.Request>[];
      final httpClient = MockClient((request) async {
        final method = request.url.queryParameters['method'];
        if (method == 'artist.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similarartists': <String, dynamic>{
              'artist': <Map<String, dynamic>>[
                _artist('Owned Artist', 0.99, mbid: 'owned-artist'),
                _artist('New Artist', 0.90, mbid: 'new-artist'),
                _artist('Seed Artist', 0.88, mbid: 'seed-artist'),
              ],
            },
          });
        }
        if (method == 'track.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similartracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _track('Owned Song', 'Owned Artist', 0.98),
                _track('New Song', 'New Artist', 0.93),
                _track('New Song', 'New Artist', 0.90),
                _track('Seed Song', 'Seed Artist', 0.89),
              ],
            },
          });
        }
        if (request.url.path.contains('/ws/2/recording/')) {
          musicBrainzRequests.add(request);
          return _jsonResponse(<String, dynamic>{
            'recordings': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'new-recording',
                'title': 'New Song',
                'score': 100,
                'artist-credit': <Map<String, dynamic>>[
                  <String, dynamic>{'name': 'New Artist', 'joinphrase': ''},
                ],
              },
            ],
          });
        }
        return _jsonResponse(<String, dynamic>{'artists': <dynamic>[]});
      });
      final service = MusicRecommendationService(
        lastFm: LastFmRecommendationClient(
          apiKey: 'key',
          endpoint: Uri.https('example.test', '/2.0/'),
          httpClient: httpClient,
        ),
        musicBrainz: MusicBrainzIdentityClient(
          endpoint: Uri.https('example.test', '/ws/2/'),
          httpClient: httpClient,
          requestSpacing: Duration.zero,
        ),
      );

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.artist('Seed Artist'),
          MusicRecommendationSeed.track(
            artist: 'Seed Artist',
            title: 'Seed Song',
          ),
        ],
        ownedTracks: const <OwnedMusicTrack>[
          OwnedMusicTrack(
              title: 'Owned Song (2011 Remaster)', artist: 'Owned Artist'),
        ],
      );

      expect(result.recommendations.map((item) => item.name),
          containsAll(<String>['New Artist', 'New Song']));
      expect(result.recommendations.map((item) => item.name),
          isNot(contains('Owned Artist')));
      expect(result.recommendations.map((item) => item.name),
          isNot(contains('Owned Song')));
      expect(result.recommendations.map((item) => item.name),
          isNot(contains('Seed Artist')));
      expect(result.recommendations.map((item) => item.name),
          isNot(contains('Seed Song')));
      final newSong = result.tracks.single;
      expect(newSong.musicBrainzId, 'new-recording');
      expect(newSong.sourceSeeds, <String>['Seed Artist — Seed Song']);
      expect(newSong.youtubeMusicUrl.host, 'music.youtube.com');
      expect(newSong.bandcampUrl.host, 'bandcamp.com');
      expect(newSong.musicBrainzUrl?.path, '/recording/new-recording');
      expect(musicBrainzRequests, hasLength(1));
      expect(musicBrainzRequests.single.headers['user-agent'],
          startsWith('Ariami/'));
    });

    test('album mode derives top albums and removes albums already owned',
        () async {
      final httpClient = MockClient((request) async {
        final method = request.url.queryParameters['method'];
        if (method == 'artist.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similarartists': <String, dynamic>{
              'artist': <Map<String, dynamic>>[
                _artist('New Artist', 0.9),
                _artist('Owned Album Artist', 0.8),
              ],
            },
          });
        }
        if (method == 'artist.gettopalbums') {
          final artist = request.url.queryParameters['artist']!;
          final name = artist == 'New Artist' ? 'Fresh Album' : 'Owned Album';
          return _jsonResponse(<String, dynamic>{
            'topalbums': <String, dynamic>{
              'album': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': name,
                  'mbid': artist == 'New Artist' ? 'release-group-id' : '',
                  'url': 'https://www.last.fm/music/$artist/$name',
                  'image': <Map<String, dynamic>>[
                    <String, dynamic>{
                      '#text': 'https://images.example/$artist.jpg',
                      'size': 'large',
                    },
                  ],
                },
              ],
            },
          });
        }
        return _jsonResponse(<String, dynamic>{'artists': <dynamic>[]});
      });
      final service = MusicRecommendationService(
        lastFm: LastFmRecommendationClient(
          apiKey: 'key',
          endpoint: Uri.https('example.test', '/2.0/'),
          httpClient: httpClient,
        ),
        musicBrainz: MusicBrainzIdentityClient(
          endpoint: Uri.https('example.test', '/ws/2/'),
          httpClient: httpClient,
          requestSpacing: Duration.zero,
        ),
        musicBrainzLookupLimit: 0,
      );

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.artist('Seed Artist'),
        ],
        ownedTracks: const <OwnedMusicTrack>[
          OwnedMusicTrack(
            title: 'Song',
            artist: 'Owned Album Artist',
            album: 'Owned Album',
          ),
        ],
        mix: MusicDiscoveryMix.albums,
      );

      expect(result.albums.map((item) => item.name), <String>['Fresh Album']);
      expect(result.albums.single.musicBrainzUrl?.path,
          '/release-group/release-group-id');
      expect(result.albums.single.imageUrl, isNotNull);
    });

    test('instrumental mode keeps only explicitly tagged tracks', () async {
      final metadataRequests = <String>[];
      final service = _serviceWith(MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'track.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similartracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _track('Instrumental Song', 'Artist A', 0.8),
                _track('Vocal Song', 'Artist B', 0.9),
                _track('Unknown Song', 'Artist C', 0.7),
              ],
            },
          });
        }
        if (query['method'] == 'track.getinfo') {
          final track = query['track']!;
          metadataRequests.add(track);
          final tags = switch (track) {
            'Instrumental Song' => <Map<String, dynamic>>[
                <String, dynamic>{'name': 'Instrumental Rock'},
              ],
            'Vocal Song' => <Map<String, dynamic>>[
                <String, dynamic>{'name': 'Rock'},
              ],
            _ => <Map<String, dynamic>>[],
          };
          return _jsonResponse(<String, dynamic>{
            'track': <String, dynamic>{
              'toptags': <String, dynamic>{'tag': tags},
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      }));

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.track(
            artist: 'Seed Artist',
            title: 'Seed Song',
          ),
        ],
        ownedTracks: const <OwnedMusicTrack>[],
        mix: MusicDiscoveryMix.balanced,
        instrumentalOnly: true,
      );

      expect(result.recommendations.map((item) => item.name),
          <String>['Instrumental Song']);
      expect(result.recommendations.single.kind, MusicRecommendationKind.track);
      expect(
          metadataRequests,
          containsAll(
              <String>['Instrumental Song', 'Vocal Song', 'Unknown Song']));
    });

    test('instrumental mode sources its tag pool without taste seeds',
        () async {
      final requestedTags = <String>[];
      final service = _serviceWith(MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'tag.gettoptracks') {
          requestedTags.add(query['tag']!);
          return _jsonResponse(<String, dynamic>{
            'tracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _tagTrack('Direct Instrumental', 'Instrumentalist'),
              ],
            },
          });
        }
        if (query['method'] == 'track.getinfo') {
          return _jsonResponse(<String, dynamic>{
            'track': <String, dynamic>{
              'toptags': <String, dynamic>{
                'tag': <Map<String, dynamic>>[
                  <String, dynamic>{'name': 'Rock'},
                ],
              },
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      }));

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[],
        ownedTracks: const <OwnedMusicTrack>[],
        instrumentalOnly: true,
      );

      expect(requestedTags, <String>['instrumental']);
      expect(result.tracks.single.name, 'Direct Instrumental');
      expect(result.tracks.single.sourceTags, <String>['instrumental']);
    });

    test('a selected tag sources candidates instead of reranking taste',
        () async {
      final service = _serviceWith(MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'track.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similartracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _track('NF Neighbour', 'Rap Artist', 0.95),
              ],
            },
          });
        }
        if (query['method'] == 'tag.gettoptracks') {
          expect(query['tag'], 'country');
          return _jsonResponse(<String, dynamic>{
            'tracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _tagTrack('Country Road', 'Country Artist'),
                _tagTrack('Honky Tonk', 'Another Country Artist'),
              ],
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      }));

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.track(
            artist: 'Seed Artist',
            title: 'Seed Song',
          ),
        ],
        ownedTracks: const <OwnedMusicTrack>[],
        limit: 2,
        mix: MusicDiscoveryMix.tracks,
        preferredTags: const <String>{'country'},
      );

      expect(result.recommendations.map((item) => item.name),
          <String>['Country Road', 'Honky Tonk']);
      expect(
        result.recommendations,
        everyElement(
          isA<MusicRecommendation>().having(
            (item) => item.sourceTags,
            'source tags',
            contains('country'),
          ),
        ),
      );
      expect(result.recommendations.first.discoveryReason, 'Matches Country');
    });

    test('embedded library genres boost taste results without limiting them',
        () async {
      final service = _serviceWith(MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'track.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similartracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _track('Jazz Candidate', 'Jazz Artist', 0.85),
                _track('Rock Candidate', 'Rock Artist', 0.80),
              ],
            },
          });
        }
        if (query['method'] == 'track.getinfo') {
          final tag = query['track'] == 'Rock Candidate' ? 'Rock' : 'Jazz';
          return _jsonResponse(<String, dynamic>{
            'track': <String, dynamic>{
              'toptags': <String, dynamic>{
                'tag': <Map<String, dynamic>>[
                  <String, dynamic>{'name': tag},
                ],
              },
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      }));

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.track(
            artist: 'Seed Artist',
            title: 'Seed Song',
          ),
        ],
        ownedTracks: const <OwnedMusicTrack>[],
        limit: 2,
        mix: MusicDiscoveryMix.tracks,
        libraryTags: const <String>{'rock'},
      );

      expect(result.tracks.map((item) => item.name),
          <String>['Rock Candidate', 'Jazz Candidate']);
    });

    test('tag-only Fusion discovery intersects with Instrumental', () async {
      final requestedTags = <String>[];
      final service = _serviceWith(MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'tag.gettoptracks') {
          requestedTags.add(query['tag']!);
          final tracks = query['tag'] == 'fusion'
              ? <Map<String, dynamic>>[
                  _tagTrack('Fusion Instrumental', 'Guitarist'),
                  _tagTrack('Fusion Vocal', 'Singer'),
                ]
              : <Map<String, dynamic>>[
                  _tagTrack('Instrumental Fusion', 'Keyboardist'),
                  _tagTrack('Instrumental Rock', 'Rock Guitarist'),
                ];
          return _jsonResponse(<String, dynamic>{
            'tracks': <String, dynamic>{
              'track': tracks,
            },
          });
        }
        if (query['method'] == 'track.getinfo') {
          final tag = switch (query['track']) {
            'Fusion Instrumental' => 'Instrumental',
            'Instrumental Fusion' => 'Fusion',
            'Instrumental Rock' => 'Rock',
            _ => 'Fusion',
          };
          return _jsonResponse(<String, dynamic>{
            'track': <String, dynamic>{
              'toptags': <String, dynamic>{
                'tag': <Map<String, dynamic>>[
                  <String, dynamic>{'name': tag},
                ],
              },
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      }));

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[],
        ownedTracks: const <OwnedMusicTrack>[],
        preferredTags: const <String>{'fusion'},
        instrumentalOnly: true,
      );

      expect(result.tracks.map((item) => item.name),
          <String>['Fusion Instrumental', 'Instrumental Fusion']);
      expect(result.tracks.first.sourceTags, <String>['fusion']);
      expect(result.tracks.last.sourceTags, <String>['instrumental']);
      expect(requestedTags, <String>['fusion', 'instrumental']);
    });

    test('instrumental style falls back to compound Last.fm tags', () async {
      final requestedTags = <String>[];
      final service = _serviceWith(MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'tag.gettoptracks') {
          final tag = query['tag']!;
          requestedTags.add(tag);
          final tracks = switch (tag) {
            'fusion' => <Map<String, dynamic>>[
                _tagTrack('Fusion Vocal', 'Singer'),
              ],
            'instrumental' => <Map<String, dynamic>>[
                _tagTrack('Instrumental Rock', 'Guitarist'),
              ],
            'instrumental fusion' => <Map<String, dynamic>>[
                _tagTrack('Compound Jam', 'Fusion Band'),
              ],
            _ => <Map<String, dynamic>>[],
          };
          return _jsonResponse(<String, dynamic>{
            'tracks': <String, dynamic>{'track': tracks},
          });
        }
        if (query['method'] == 'track.getinfo') {
          final tag = switch (query['track']) {
            'Fusion Vocal' => 'Fusion',
            'Instrumental Rock' => 'Rock',
            _ => 'Jazz',
          };
          return _jsonResponse(<String, dynamic>{
            'track': <String, dynamic>{
              'toptags': <String, dynamic>{
                'tag': <Map<String, dynamic>>[
                  <String, dynamic>{'name': tag},
                ],
              },
            },
          });
        }
        return _jsonResponse(<String, dynamic>{});
      }));

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[],
        ownedTracks: const <OwnedMusicTrack>[],
        preferredTags: const <String>{'fusion'},
        instrumentalOnly: true,
      );

      expect(result.tracks.single.name, 'Compound Jam');
      expect(result.tracks.single.sourceTags, <String>['instrumental fusion']);
      expect(requestedTags, <String>[
        'fusion',
        'instrumental',
        'instrumental fusion',
        'fusion instrumental',
      ]);
    });

    test('refinement metadata rate limits still reach the caller', () async {
      final service = _serviceWith(MockClient((request) async {
        if (request.url.queryParameters['method'] == 'track.getsimilar') {
          return _jsonResponse(<String, dynamic>{
            'similartracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _track('Candidate', 'Artist', 0.9),
              ],
            },
          });
        }
        return _jsonResponse(<String, dynamic>{
          'error': 29,
          'message': 'Rate limit exceeded',
        });
      }));

      await expectLater(
        service.discover(
          seeds: const <MusicRecommendationSeed>[
            MusicRecommendationSeed.track(
              artist: 'Seed Artist',
              title: 'Seed Song',
            ),
          ],
          ownedTracks: const <OwnedMusicTrack>[],
          preferredTags: const <String>{'rock'},
        ),
        throwsA(
          isA<LastFmRecommendationException>()
              .having((error) => error.isRateLimited, 'rate limited', isTrue),
        ),
      );
    });

    test('skips seeds Last.fm cannot resolve and keeps the rest', () async {
      final asked = <String>[];
      final httpClient = MockClient((request) async {
        final query = request.url.queryParameters;
        final method = query['method'];
        if (method == 'artist.getsimilar') {
          asked.add(query['artist']!);
          if (query['artist'] == 'Obscure Local Band') {
            return _jsonResponse(<String, dynamic>{
              'error': 6,
              'message': 'The artist you supplied could not be found',
            });
          }
          return _jsonResponse(<String, dynamic>{
            'similarartists': <String, dynamic>{
              'artist': <Map<String, dynamic>>[_artist('Found Artist', 0.9)],
            },
          });
        }
        if (method == 'track.getsimilar') {
          asked.add(query['track']!);
          return _jsonResponse(<String, dynamic>{
            'error': 6,
            'message': 'Track not found',
          });
        }
        return _jsonResponse(<String, dynamic>{'artists': <dynamic>[]});
      });
      final service = _serviceWith(httpClient);

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.artist('Obscure Local Band'),
          MusicRecommendationSeed.artist('Known Artist'),
          MusicRecommendationSeed.track(
              artist: 'Nobody', title: 'Unknown Song'),
        ],
        ownedTracks: const <OwnedMusicTrack>[],
      );

      // Both unresolvable seeds were tried and skipped; the good one survived.
      expect(asked, contains('Obscure Local Band'));
      expect(result.recommendations.map((item) => item.name),
          contains('Found Artist'));
    });

    test('reports a clear error only when no seed resolves at all', () async {
      final httpClient = MockClient((request) async => _jsonResponse(
            <String, dynamic>{'error': 6, 'message': 'Track not found'},
          ));
      final service = _serviceWith(httpClient);

      await expectLater(
        service.discover(
          seeds: const <MusicRecommendationSeed>[
            MusicRecommendationSeed.artist('Nobody At All'),
          ],
          ownedTracks: const <OwnedMusicTrack>[],
        ),
        throwsA(
          isA<LastFmRecommendationException>().having(
            (error) => error.message,
            'message',
            contains('did not recognise any of your top artists'),
          ),
        ),
      );
    });

    test('a rejected API key still fails the whole run', () async {
      final httpClient = MockClient((request) async => _jsonResponse(
            <String, dynamic>{'error': 10, 'message': 'Invalid API key'},
          ));
      final service = _serviceWith(httpClient);

      await expectLater(
        service.discover(
          seeds: const <MusicRecommendationSeed>[
            MusicRecommendationSeed.artist('Anyone'),
          ],
          ownedTracks: const <OwnedMusicTrack>[],
        ),
        throwsA(isA<LastFmRecommendationException>()
            .having((error) => error.isInvalidApiKey, 'isInvalidApiKey', true)),
      );
    });

    test('retries a track seed without its edition or feature suffix',
        () async {
      final tracksAsked = <String>[];
      final httpClient = MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['method'] == 'track.getsimilar') {
          final track = query['track']!;
          tracksAsked.add(track);
          if (track != 'Real Song') {
            return _jsonResponse(<String, dynamic>{
              'error': 6,
              'message': 'Track not found',
            });
          }
          return _jsonResponse(<String, dynamic>{
            'similartracks': <String, dynamic>{
              'track': <Map<String, dynamic>>[
                _track('Neighbour Song', 'Neighbour', 0.9),
              ],
            },
          });
        }
        return _jsonResponse(<String, dynamic>{'artists': <dynamic>[]});
      });
      final service = _serviceWith(httpClient);

      final result = await service.discover(
        seeds: const <MusicRecommendationSeed>[
          MusicRecommendationSeed.track(
            artist: 'Someone',
            title: 'Real Song (Remastered 2011)',
          ),
        ],
        ownedTracks: const <OwnedMusicTrack>[],
      );

      expect(tracksAsked, <String>['Real Song (Remastered 2011)', 'Real Song']);
      expect(result.recommendations.map((item) => item.name),
          contains('Neighbour Song'));
    });

    test('preferences round-trip and reject unsupported sizes', () {
      final restored = MusicDiscoveryPreferences.fromJson(
        MusicDiscoveryPreferences(
          mix: MusicDiscoveryMix.albums,
          resultLimit: 36,
          tasteRange: StatsRange.monthOf(DateTime(2026, 3, 14)),
          seedDepth: 10,
          preferredTags: const <String>{'jazz', 'fusion'},
          instrumentalOnly: true,
        ).toJson(),
      );
      expect(restored.mix, MusicDiscoveryMix.albums);
      expect(restored.resultLimit, 36);
      // Anchors normalise to the start of their period on the way through.
      expect(restored.tasteRange, StatsRange.monthOf(DateTime(2026, 3, 1)));
      expect(restored.seedDepth, 10);
      expect(restored.preferredTags, <String>{'jazz', 'fusion'});
      expect(restored.instrumentalOnly, isTrue);
      expect(
        MusicDiscoveryPreferences.fromJson(
          <String, dynamic>{'resultLimit': 999, 'seedDepth': 500},
        ).resultLimit,
        24,
      );
      expect(
        MusicDiscoveryPreferences.fromJson(
          <String, dynamic>{'seedDepth': 500},
        ).seedDepth,
        3,
      );
    });

    test('preferences migrate the retired recent/all-time pair', () {
      expect(
        MusicDiscoveryPreferences.fromJson(
          <String, dynamic>{'tastePeriod': 'recent'},
        ).tasteRange,
        StatsRange.week,
      );
      expect(
        MusicDiscoveryPreferences.fromJson(
          <String, dynamic>{'tastePeriod': 'allTime'},
        ).tasteRange,
        StatsRange.all,
      );
      // A malformed stored range must not resurrect the old default silently
      // as something narrower than all-time.
      expect(
        MusicDiscoveryPreferences.fromJson(
          <String, dynamic>{'tasteRange': 'not-a-range'},
        ).tasteRange,
        StatsRange.all,
      );
      expect(
        MusicDiscoveryPreferences.fromJson(<String, dynamic>{
          'preferredGenres': <String>['hipHop', 'country'],
        }).preferredTags,
        <String>{'hip-hop', 'country'},
      );
    });

    test('corroborated genre text becomes normalized tag suggestions', () {
      expect(
        splitMusicDiscoveryGenreTags(const <String?>[
          'Blues/Rock',
          'Jazz & Fusion',
          'Rock & Roll',
          'R&B; Soul',
          'Blues/Rock',
          'Jazz & Fusion',
          'Rock & Roll',
          'R&B; Soul',
        ]),
        <String>{
          'blues',
          'rock',
          'jazz',
          'fusion',
          'rock & roll',
          'r&b',
          'soul',
        },
      );
    });

    test('generic and one-off downloader genres are not suggested', () {
      expect(
        splitMusicDiscoveryGenreTags(const <String?>[
          'Music',
          'Music',
          'People & Blogs',
          'Entertainment',
          'Lil Wayne, I Am Music, A Milli',
          'Big, Inf, Mic, Handz, Ali, Believe',
          'Fusion',
          'Fusion',
        ]),
        <String>{'fusion'},
      );
    });

    test('cache keys separate ranges, anchors and depths', () {
      const base = MusicDiscoveryPreferences();
      final march = base.copyWith(
        tasteRange: StatsRange.monthOf(DateTime(2026, 3, 2)),
      );
      final april = base.copyWith(
        tasteRange: StatsRange.monthOf(DateTime(2026, 4, 2)),
      );
      expect(march.cacheKey, isNot(april.cacheKey));
      expect(
        base.copyWith(seedDepth: 10).cacheKey,
        isNot(base.copyWith(seedDepth: 3).cacheKey),
      );
      expect(
        base.copyWith(tasteRange: StatsRange.week).cacheKey,
        isNot(base.copyWith(tasteRange: StatsRange.month).cacheKey),
      );
      expect(
        base.copyWith(
          preferredTags: const <String>{'rock'},
        ).cacheKey,
        isNot(base.cacheKey),
      );
      expect(
          base.copyWith(instrumentalOnly: true).cacheKey, isNot(base.cacheKey));
    });

    test('snapshot cache round-trips defensively', () {
      final snapshot = MusicRecommendationSnapshot(
        generatedAt: DateTime.utc(2026, 8, 10),
        recommendations: <MusicRecommendation>[
          MusicRecommendation(
            kind: MusicRecommendationKind.track,
            name: 'Track',
            artist: 'Artist',
            score: 0.8,
            lastFmUrl: Uri.https('www.last.fm', '/music/Artist/_/Track'),
            musicBrainzId: 'recording-id',
            imageUrl: Uri.https('images.example', '/track.jpg'),
            sourceSeeds: const <String>['Seed'],
            sourceTags: const <String>['fusion'],
          ),
        ],
        artistSeeds: const <String>['Artist Seed'],
        trackSeeds: const <String>['Artist — Track'],
      );

      final restored = MusicRecommendationSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );

      expect(restored.generatedAt, DateTime.utc(2026, 8, 10));
      expect(restored.tracks.single.musicBrainzId, 'recording-id');
      expect(restored.tracks.single.imageUrl,
          Uri.https('images.example', '/track.jpg'));
      expect(restored.tracks.single.sourceTags, <String>['fusion']);
      expect(restored.artistSeeds, <String>['Artist Seed']);
    });
  });
}

http.Response _jsonResponse(Map<String, dynamic> json) =>
    http.Response(jsonEncode(json), 200);

/// A service whose Last.fm and MusicBrainz calls both go to [httpClient],
/// with MusicBrainz lookups disabled so tests assert on Last.fm behaviour.
MusicRecommendationService _serviceWith(http.Client httpClient) =>
    MusicRecommendationService(
      lastFm: LastFmRecommendationClient(
        apiKey: 'key',
        endpoint: Uri.https('example.test', '/2.0/'),
        httpClient: httpClient,
      ),
      musicBrainz: MusicBrainzIdentityClient(
        endpoint: Uri.https('example.test', '/ws/2/'),
        httpClient: httpClient,
        requestSpacing: Duration.zero,
      ),
      musicBrainzLookupLimit: 0,
    );

Map<String, dynamic> _artist(String name, double match, {String? mbid}) =>
    <String, dynamic>{
      'name': name,
      'match': '$match',
      'url': 'https://www.last.fm/music/${Uri.encodeComponent(name)}',
      if (mbid != null) 'mbid': mbid,
    };

Map<String, dynamic> _track(String name, String artist, double match) =>
    <String, dynamic>{
      'name': name,
      'match': '$match',
      'url': 'https://www.last.fm/music/${Uri.encodeComponent(artist)}/_/'
          '${Uri.encodeComponent(name)}',
      'artist': <String, dynamic>{'name': artist},
    };

Map<String, dynamic> _tagTrack(String name, String artist) => <String, dynamic>{
      'name': name,
      'url': 'https://www.last.fm/music/${Uri.encodeComponent(artist)}/_/'
          '${Uri.encodeComponent(name)}',
      'artist': <String, dynamic>{'name': artist},
    };

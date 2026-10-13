# API notes (probed against the live servers, 2026-09-15)

## Sonarr v3 — `http://192.168.50.131:8989/api/v3`, header `X-Api-Key`
- `GET /system/status` → `{version, appName, osName, isDocker}` (4.0.19.2979, debian, docker)
- `GET /health` → array of `{source, type, message, wikiUrl}`
- `GET /series` → 689 items. Fields used: `id,title,sortTitle,status,ended,monitored,seasonFolder,
  qualityProfileId,path,rootFolderPath,year,network,runtime,tvdbId,imdbId,seriesType,added,overview,
  genres,certification,ratings{votes,value},statistics{seasonCount,episodeFileCount,episodeCount,
  totalEpisodeCount,sizeOnDisk,percentOfEpisodes},seasons[{seasonNumber,monitored,statistics}],
  images[{coverType,url,remoteUrl}]`
  - `images[].url` is server-relative (`/MediaCover/1/poster.jpg?lastWrite=…`) → prefix with base URL
    and append `apikey=`; `remoteUrl` is the CDN original.
- `GET /series/{id}`, `PUT /series/{id}`, `DELETE /series/{id}?deleteFiles=&addImportListExclusion=`
- `GET /series/lookup?term=` → same shape without `id`; POST the object back to `/series` with
  `qualityProfileId,rootFolderPath,monitored,seasonFolder,addOptions{monitor,searchForMissingEpisodes}`
- `GET /episode?seriesId=` / `?seriesId=&seasonNumber=` ; `PUT /episode/monitor` `{episodeIds,monitored}`
- `GET /episodefile?seriesId=` ; `DELETE /episodefile/{id}`
- `GET /queue?pageSize=&includeSeries=true&includeEpisode=true` → `{totalRecords, records[]}` with
  `status,trackedDownloadStatus,trackedDownloadState,statusMessages[],errorMessage,size,sizeleft,
  timeleft,estimatedCompletionTime,downloadId,protocol,downloadClient,indexer,quality.quality.name`
- `GET /wanted/missing?pageSize=&sortKey=airDateUtc&includeSeries=true`
- `GET /calendar?start=&end=&includeSeries=true` ; `GET /history?page=&pageSize=&includeSeries=true`
- `GET /release?episodeId=` / `?seriesId=&seasonNumber=` → interactive search;
  `POST /release {guid,indexerId}` to grab
- `POST /command` bodies: `{name:"SeriesSearch",seriesId:}`, `{name:"SeasonSearch",seriesId:,seasonNumber:}`,
  `{name:"EpisodeSearch",episodeIds:[]}`, `{name:"RefreshSeries",seriesId:}`, `{name:"RescanSeries",seriesId:}`,
  `{name:"RenameFiles",seriesId:,files:[]}`, `{name:"MissingEpisodeSearch"}`
- `GET /qualityprofile`, `GET /rootfolder`, `GET /tag`, `GET /diskspace`, `GET /queue/details`

## Radarr v3 — `http://192.168.50.131:7878/api/v3`, header `X-Api-Key` (6.3.0.10514)
Same conventions. Differences that matter:
- `GET /movie` → 492 items: `hasFile,movieFileId,movieFile{quality,size,relativePath,mediaInfo},
  sizeOnDisk,studio,inCinemas,physicalRelease,digitalRelease,releaseDate,minimumAvailability,
  isAvailable,popularity,tmdbId,imdbId,ratings{imdb,tmdb,metacritic,rottenTomatoes,trakt}` —
  note Radarr ratings is a **dict of sources**, Sonarr's is a single `{votes,value}`.
- `GET /movie/lookup?term=`, `POST /movie` with `{tmdbId,title,year,qualityProfileId,rootFolderPath,
  monitored,minimumAvailability,addOptions{searchForMovie}}`
- `GET /release?movieId=`; commands `MoviesSearch{movieIds}`, `RefreshMovie{movieIds}`,
  `RescanMovie{movieIds}`, `RenameFiles`, `MissingMoviesSearch`
- `GET /wanted/missing?sortKey=digitalRelease` ; `GET /calendar?start=&end=`

## Jellyfin 12.0.0 — `http://192.168.50.131:8345`
Auth header on every call: `Authorization: MediaBrowser Client="Downarr", Device="Mac",
DeviceId="<stable-uuid>", Version="1.0", Token="<token>"`.
- `POST /Users/AuthenticateByName` `{Username,Pw}` → `{AccessToken, User{Id,Name,Policy.IsAdministrator}, ServerId}`
- `GET /Users/{userId}/Views` → CollectionFolders with `CollectionType` (movies/tvshows/music/playlists)
- `GET /Library/VirtualFolders` → `[{Name,CollectionType,ItemId,Locations[]}]`
- `GET /Items?userId=&ParentId=&IncludeItemTypes=&Recursive=true&StartIndex=&Limit=&SortBy=&SortOrder=
  &SearchTerm=&Fields=` → `{Items[], TotalRecordCount, StartIndex}` (the 10.9+ form; `/Users/{id}/Items`
  still works but is deprecated)
- `GET /Items/{id}?userId=` → full DTO incl. `LockData, LockedFields, ProviderIds, People, Studios,
  GenreItems, Taglines, Tags, ImageTags{Primary,Logo,Thumb}, BackdropImageTags[], MediaSources, MediaStreams`
- Images: `GET /Items/{id}/Images` → `[{ImageType,ImageIndex,Width,Height,Size}]`
  `GET /Items/{id}/Images/{Type}?tag=&maxHeight=` (public-ish, token in query as `api_key=` works)
  `GET /Items/{id}/RemoteImages?type=Primary&limit=&startIndex=&providerName=&includeAllLanguages=`
    → `{Images[{ProviderName,Url,Height,Width,CommunityRating,VoteCount,Language,Type}], TotalRecordCount, Providers[]}`
  `POST /Items/{id}/RemoteImages/Download?type=&imageUrl=`
  `POST /Items/{id}/Images/{Type}` body = **base64 text** of the image, `Content-Type: image/jpeg`
  `DELETE /Items/{id}/Images/{Type}?imageIndex=`
- Metadata: `POST /Items/{id}` with the full (edited) DTO — 204 on success.
  `GET /Items/{id}/MetadataEditor` → `{ParentalRatingOptions, Cultures, Countries, ExternalIdInfos}`
- Identify: `POST /Items/RemoteSearch/{Movie|Series|Episode|Season|BoxSet|MusicAlbum|MusicArtist|Person}`
  body `{ItemId, SearchInfo:{Name,Year,ProviderIds{},IndexNumber,ParentIndexNumber}, IncludeDisabledProviders:true}`
  → `[{Name,ProductionYear,SearchProviderName,ProviderIds,ImageUrl,Overview,PremiereDate}]`
  Apply: `POST /Items/RemoteSearch/Apply/{id}?replaceAllImages=true` body = chosen result object.
- Refresh: `POST /Items/{id}/Refresh?metadataRefreshMode=&imageRefreshMode=&replaceAllMetadata=&replaceAllImages=`
  (modes: `None|ValidationOnly|Default|FullRefresh`)
- `POST /Library/Refresh` full scan; `GET /ScheduledTasks`, `POST /ScheduledTasks/Running/{taskId}`
  (RefreshLibrary task id key = `RefreshLibrary`)
- `GET /Shows/{seriesId}/Seasons?userId=`, `GET /Shows/{seriesId}/Episodes?userId=&seasonId=`
- `GET /Items/Counts` → `{MovieCount:1557, SeriesCount:684, EpisodeCount:37840, SongCount, …}`
- `DELETE /Items/{id}` deletes media. `GET /Genres`, `GET /Studios`, `GET /Tags`.

## NZBGet 26.2 — `http://192.168.50.131:6789/jsonrpc`, HTTP Basic
GET form `/jsonrpc/<method>` works for no-arg methods; POST `{"method":…,"params":[…]}` otherwise.
- `version` → "26.2"
- `status` → `{DownloadRate, RemainingSizeMB, DownloadedSizeMB, ServerPaused, DownloadPaused,
  PostPaused, ScanPaused, ThreadCount, ArticleCacheMB, FreeDiskSpaceMB, ServerTime, UpTimeSec,
  DownloadLimit, DownloadedSizeLo/Hi, AverageDownloadRate}`
- `listgroups` → `[{NZBID,NZBName,Status,FileSizeMB,RemainingSizeMB,DownloadedSizeMB,Category,
  MaxPriority,ActiveDownloads,Health,DestDir,PostTotalTimeSec,PostStageProgress,PostStageName}]`
- `history [false]` → `[{NZBID,Name,Status,FileSizeMB,Category,HistoryTime,DestDir,DownloadTimeSec,
  ParStatus,UnpackStatus,Kind}]`
- `editqueue [command, offset, text, ids[]]` — commands: `GroupPause`, `GroupResume`,
  `GroupDelete`, `GroupFinalDelete`, `GroupMoveTop`, `GroupMoveBottom`, `GroupMoveOffset`,
  `GroupSetPriority`, `GroupSetCategory`, `HistoryDelete`, `HistoryReturn`, `HistoryRedownload`,
  `HistoryMarkGood`, `HistoryMarkBad`
- `pausedownload` / `resumedownload` / `pausepost` / `resumepost` / `pausescan` / `resumescan`
- `rate [kbPerSec]` speed limit, `0` = unlimited
- `append [nzbFilename, content, category, priority, addToTop, addPaused, dupeKey, dupeScore, dupeMode, params[]]`
  — `content` may be a URL when the filename is empty
- `config`, `loadlog`, `writelog`, `scan`, `reload`, `shutdown`

## Deluge 2.2.0 — `http://192.168.50.131:8112/json`, JSON-RPC over POST
The web UI authenticates with a **password only** — any username is ignored.
- `auth.login ["<password>"]` → `true`, and sets a `_session_id` cookie that must be replayed on
  every later call (URLSession's shared cookie storage does this automatically).
- An expired session comes back as `{"error": {"code": 1, "message": "Not authenticated"}}` —
  that is the signal to log in again and retry.
- `web.connected` → bool; if false, `web.get_hosts` → `[[id, host, port, user]]` then
  `web.connect [id]`. A fresh web session is not always attached to the daemon.
- `daemon.get_version` → "2.2.0" (`daemon.info` does not exist on 2.x).
- `web.update_ui [[keys], {}]` → `{connected, torrents: {<hash>: {…}}, stats: {…}, filters: {…}}`
  - **torrents is keyed by infohash and the object does not repeat it** — the model has to fill
    `hash` in from the key, and must leave it out of its CodingKeys or decoding fails.
  - stats: `download_rate, upload_rate, download_protocol_rate, upload_protocol_rate, max_download,
    max_upload (KiB/s, -1 = unlimited), num_connections, max_num_connections, dht_nodes,
    free_space, has_incoming_connections, external_ip`
  - filters: `state / label / tracker_host / owner`, each `[[name, count], …]`
  - torrent keys used: `name, state, progress (0-100), total_size, total_wanted, total_done,
    total_uploaded, download_payload_rate, upload_payload_rate, eta, ratio, label, save_path,
    num_seeds, num_peers, total_seeds, total_peers, time_added, completed_time, tracker_host,
    tracker_status, is_finished, active_time, seeding_time, queue, max_download_speed, message`
  - `state` is one of Downloading, Seeding, Paused, Queued, Checking, Allocating, Moving, Error.
    `message` is "OK" when healthy. `queue` is -1 for finished torrents.
- Actions (2.x plural forms): `core.pause_torrents [[ids]]`, `core.resume_torrents [[ids]]`,
  `core.remove_torrents [[ids], removeData]`, `core.force_recheck [[ids]]`,
  `core.queue_top|queue_up|queue_down|queue_bottom [[ids]]`,
  `core.set_torrent_options [[ids], {max_download_speed: KiB}]`, `core.move_storage [[ids], path]`
- Session: `core.pause_session`, `core.resume_session`,
  `core.set_config [{max_download_speed: KiB, max_upload_speed: KiB}]`,
  `core.get_config_values [[keys]]` (`download_location`, `move_completed_path`, …)
- Adding: `core.add_torrent_magnet [uri, options]`, `core.add_torrent_url [url, options]` →
  infohash; options take `add_paused` and `download_location`.
- Label plugin (enabled here, one label: `radarr`): `label.get_labels`, `label.add [name]`,
  `label.set_torrent [hash, label]`. Check `core.get_enabled_plugins` for "Label" first.

**Joining to the *arrs**: Radarr has Deluge configured as its torrent client (Sonarr is usenet
only). A Servarr queue record's `downloadId` is the torrent's infohash, so it joins straight to
Deluge's torrent key — case-insensitively, with the release name as a fallback.

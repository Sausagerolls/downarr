import Foundation

struct JellyfinAuthResult: Codable {
    var AccessToken: String?
    var ServerId: String?
    var User: JellyfinUser?
}

struct JellyfinUser: Codable, Identifiable, Hashable {
    var Id: String = ""
    var Name: String?
    var Policy: JellyfinUserPolicy?
    var id: String { Id }
}

struct JellyfinUserPolicy: Codable, Hashable {
    var IsAdministrator: Bool?
}

struct JellyfinSystemInfo: Codable, Hashable {
    var ServerName: String?
    var Version: String?
    var OperatingSystem: String?
    var Id: String?
}

struct JellyfinItemCounts: Codable, Hashable {
    var MovieCount: Int?
    var SeriesCount: Int?
    var EpisodeCount: Int?
    var ArtistCount: Int?
    var AlbumCount: Int?
    var SongCount: Int?
    var BoxSetCount: Int?
    var ItemCount: Int?
}

struct JellyfinNameGuidPair: Codable, Hashable, Identifiable {
    var Name: String?
    var Id: String?
    var id: String { Id ?? Name ?? UUID().uuidString }
}

struct JellyfinPerson: Codable, Hashable, Identifiable {
    var Name: String?
    var Id: String?
    var Role: String?
    var PersonType: String?
    var PrimaryImageTag: String?
    var id: String { (Id ?? "") + (Name ?? "") + (Role ?? "") }

    // `Type` cannot be a Swift member name, so this one key is mapped by hand.
    enum CodingKeys: String, CodingKey {
        case Name, Id, Role, PrimaryImageTag
        case PersonType = "Type"
    }
}

struct JellyfinUserData: Codable, Hashable {
    var PlayCount: Int?
    var Played: Bool?
    var IsFavorite: Bool?
    var PlaybackPositionTicks: Int64?
    var UnplayedItemCount: Int?
}

struct JellyfinMediaStream: Codable, Hashable {
    var Codec: String?
    var Language: String?
    var DisplayTitle: String?
    var StreamType: String?
    var Height: Int?
    var Width: Int?
    var BitRate: Int?
    var Channels: Int?
    var IsDefault: Bool?
    var IsExternal: Bool?

    enum CodingKeys: String, CodingKey {
        case Codec, Language, DisplayTitle, Height, Width, BitRate, Channels, IsDefault, IsExternal
        case StreamType = "Type"
    }
}

struct JellyfinMediaSource: Codable, Hashable {
    var Id: String?
    var Path: String?
    var Container: String?
    var Size: Int64?
    var Bitrate: Int?
    var MediaStreams: [JellyfinMediaStream]?
}

/// Read model for a Jellyfin item. Metadata writes round-trip the raw DTO (see `JellyfinClient`).
struct JellyfinItem: Codable, Identifiable, Hashable {
    var Id: String = ""
    var Name: String?
    var OriginalTitle: String?
    var SortName: String?
    var ForcedSortName: String?
    var ItemType: String?
    var CollectionType: String?
    var Overview: String?
    var Taglines: [String]?
    var ProductionYear: Int?
    var PremiereDate: Date?
    var EndDate: Date?
    var DateCreated: Date?
    var CommunityRating: Double?
    var CriticRating: Double?
    var OfficialRating: String?
    var CustomRating: String?
    var Genres: [String]?
    var GenreItems: [JellyfinNameGuidPair]?
    var Studios: [JellyfinNameGuidPair]?
    var Tags: [String]?
    var People: [JellyfinPerson]?
    var ProviderIds: [String: String]?
    var Path: String?
    var Container: String?
    var RunTimeTicks: Int64?
    var IndexNumber: Int?
    var ParentIndexNumber: Int?
    var SeriesName: String?
    var SeriesId: String?
    var SeasonName: String?
    var SeasonId: String?
    var ParentId: String?
    var ImageTags: [String: String]?
    var BackdropImageTags: [String]?
    var ChildCount: Int?
    var RecursiveItemCount: Int?
    var IsFolder: Bool?
    var LockData: Bool?
    var LockedFields: [String]?
    var UserData: JellyfinUserData?
    var MediaSources: [JellyfinMediaSource]?
    var MediaStreams: [JellyfinMediaStream]?
    var ProductionLocations: [String]?
    var Status: String?
    var AirDays: [String]?
    var AirTime: String?
    var Width: Int?
    var Height: Int?


    enum CodingKeys: String, CodingKey {
        // `Type` is not a legal Swift member name; everything else maps 1:1.
        case Id, Name, OriginalTitle, SortName, ForcedSortName,
             CollectionType, Overview, Taglines, ProductionYear, PremiereDate, EndDate,
             DateCreated, CommunityRating, CriticRating, OfficialRating, CustomRating, Genres,
             GenreItems, Studios, Tags, People, ProviderIds, Path,
             Container, RunTimeTicks, IndexNumber, ParentIndexNumber, SeriesName, SeriesId,
             SeasonName, SeasonId, ParentId, ImageTags, BackdropImageTags, ChildCount,
             RecursiveItemCount, IsFolder, LockData, LockedFields, UserData, MediaSources,
             MediaStreams, ProductionLocations, Status, AirDays, AirTime, Width,
             Height
        case ItemType = "Type"
    }

    var id: String { Id }
    var kind: JellyfinItemKind { JellyfinItemKind(rawValue: ItemType ?? "") ?? .other }
    var displayName: String {
        if kind == .episode, let index = IndexNumber {
            let season = ParentIndexNumber ?? 0
            return String(format: "S%02dE%02d · ", season, index) + (Name ?? "Untitled")
        }
        return Name ?? "Untitled"
    }
    var subtitle: String? {
        switch kind {
        case .episode: return SeriesName
        case .season: return SeriesName
        default: return ProductionYear.map(String.init)
        }
    }
    var primaryImageTag: String? { ImageTags?["Primary"] }
    var isLocked: Bool { LockData ?? false }
    var runtimeText: String { Fmt.ticks(RunTimeTicks) }
    var fileSize: Int64? { MediaSources?.first?.Size }
    var videoStream: JellyfinMediaStream? {
        (MediaStreams ?? MediaSources?.first?.MediaStreams)?.first { $0.StreamType == "Video" }
    }
    var audioStreams: [JellyfinMediaStream] {
        (MediaStreams ?? MediaSources?.first?.MediaStreams ?? []).filter { $0.StreamType == "Audio" }
    }
    var subtitleStreams: [JellyfinMediaStream] {
        (MediaStreams ?? MediaSources?.first?.MediaStreams ?? []).filter { $0.StreamType == "Subtitle" }
    }
}

enum JellyfinItemKind: String {
    case movie = "Movie"
    case series = "Series"
    case season = "Season"
    case episode = "Episode"
    case boxSet = "BoxSet"
    case musicAlbum = "MusicAlbum"
    case musicArtist = "MusicArtist"
    case audio = "Audio"
    case person = "Person"
    case collectionFolder = "CollectionFolder"
    case folder = "Folder"
    case other = ""

    /// Endpoint segment for `/Items/RemoteSearch/{kind}`.
    var remoteSearchPath: String? {
        switch self {
        case .movie: return "Movie"
        case .series: return "Series"
        case .season: return "Season"
        case .episode: return "Episode"
        case .boxSet: return "BoxSet"
        case .musicAlbum: return "MusicAlbum"
        case .musicArtist: return "MusicArtist"
        case .person: return "Person"
        default: return nil
        }
    }

    var icon: String {
        switch self {
        case .movie: return "film"
        case .series: return "tv"
        case .season: return "rectangle.stack"
        case .episode: return "play.rectangle"
        case .boxSet: return "square.stack.3d.up"
        case .musicAlbum: return "opticaldisc"
        case .musicArtist: return "music.mic"
        case .audio: return "music.note"
        case .person: return "person"
        default: return "folder"
        }
    }
}

struct JellyfinItemsResponse: Codable {
    var Items: [JellyfinItem]?
    var TotalRecordCount: Int?
    var StartIndex: Int?
}

struct JellyfinVirtualFolder: Codable, Identifiable, Hashable {
    var Name: String?
    var CollectionType: String?
    var ItemId: String?
    var Locations: [String]?
    var RefreshStatus: String?
    var id: String { ItemId ?? Name ?? UUID().uuidString }
}

struct JellyfinImageInfo: Codable, Hashable, Identifiable {
    var ImageType: String?
    var ImageIndex: Int?
    var ImageTag: String?
    var Path: String?
    var Width: Int?
    var Height: Int?
    var Size: Int64?
    var id: String { (ImageType ?? "") + "-" + String(ImageIndex ?? 0) }

    var dimensions: String {
        guard let w = Width, let h = Height, w > 0 else { return "—" }
        return "\(w)×\(h)"
    }
}

struct JellyfinRemoteImage: Codable, Hashable, Identifiable {
    var ProviderName: String?
    var Url: String?
    var ThumbnailUrl: String?
    var Height: Int?
    var Width: Int?
    var CommunityRating: Double?
    var VoteCount: Int?
    var Language: String?
    var ImageType: String?
    var RatingType: String?
    var id: String { Url ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case ProviderName, Url, ThumbnailUrl, Height, Width, CommunityRating, VoteCount, Language, RatingType
        case ImageType = "Type"
    }

    var dimensions: String {
        guard let w = Width, let h = Height, w > 0 else { return "—" }
        return "\(w)×\(h)"
    }
}

struct JellyfinRemoteImagesResponse: Codable {
    var Images: [JellyfinRemoteImage]?
    var TotalRecordCount: Int?
    var Providers: [String]?
}

struct JellyfinRemoteSearchResult: Codable, Hashable, Identifiable {
    var Name: String?
    var ProductionYear: Int?
    var PremiereDate: Date?
    var IndexNumber: Int?
    var ParentIndexNumber: Int?
    var Overview: String?
    var ImageUrl: String?
    var SearchProviderName: String?
    var ProviderIds: [String: String]?
    var AlbumArtist: JSONValue?
    var Artists: JSONValue?
    var Disambiguation: String?

    var id: String { (SearchProviderName ?? "") + (Name ?? "") + String(ProductionYear ?? 0) + (ProviderIds?.values.sorted().joined() ?? "") }
}

struct JellyfinScheduledTask: Codable, Hashable, Identifiable {
    var Name: String?
    var Id: String?
    var State: String?
    var Key: String?
    var CurrentProgressPercentage: Double?
    var Description: String?
    var Category: String?
    var id: String { Id ?? Name ?? UUID().uuidString }
}

struct JellyfinMetadataEditorInfo: Codable {
    var ParentalRatingOptions: [JellyfinParentalRating]?
    var Countries: [JellyfinCountry]?
    var Cultures: [JellyfinCulture]?
    var ExternalIdInfos: [JellyfinExternalIdInfo]?
    var ContentType: String?
}

struct JellyfinParentalRating: Codable, Hashable, Identifiable {
    var Name: String?
    var Value: Int?
    var id: String { Name ?? UUID().uuidString }
}

struct JellyfinCountry: Codable, Hashable {
    var Name: String?
    var TwoLetterISORegionName: String?
}

struct JellyfinCulture: Codable, Hashable {
    var Name: String?
    var TwoLetterISOLanguageName: String?
    var ThreeLetterISOLanguageName: String?
}

struct JellyfinExternalIdInfo: Codable, Hashable, Identifiable {
    var Name: String?
    var Key: String?
    var IdType: String?
    var UrlFormatString: String?
    var id: String { Key ?? Name ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case Name, Key, UrlFormatString
        case IdType = "Type"
    }
}

/// The metadata fields Jellyfin can individually lock.
///
/// These are the server's `MetadataField` values, verified against the live server: it rejects the
/// whole save with a 400 if an unknown name is sent. `SortName` and `ExternalId` look plausible
/// but are not valid.
enum JellyfinLockableField: String, CaseIterable, Identifiable {
    case Name, Overview, Genres, Cast, Tags, Studios, ProductionLocations, OfficialRating, Runtime
    var id: String { rawValue }
    var label: String {
        switch self {
        case .Name: return "Title"
        case .Overview: return "Overview"
        case .Genres: return "Genres"
        case .Cast: return "Cast & crew"
        case .Tags: return "Tags"
        case .Studios: return "Studios"
        case .ProductionLocations: return "Production locations"
        case .OfficialRating: return "Parental rating"
        case .Runtime: return "Runtime"
        }
    }
}

enum JellyfinRefreshMode: String, CaseIterable, Identifiable {
    case none = "None"
    case validationOnly = "ValidationOnly"
    case standard = "Default"
    case full = "FullRefresh"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Don't refresh"
        case .validationOnly: return "Validate only"
        case .standard: return "Missing only"
        case .full: return "Full refresh"
        }
    }
}

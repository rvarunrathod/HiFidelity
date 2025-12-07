//
//  TagLibMetadataExtractor.mm
//  HiFidelity
//
//  Objective-C++ implementation using TagLib
//

#import "TagLibMetadataExtractor.h"

// TagLib C++ headers
#include "taglib/fileref.h"
#include "taglib/tag.h"
#include "taglib/audioproperties.h"
#include "taglib/tpropertymap.h"

// Format-specific headers
#include "taglib/mpegfile.h"
#include "taglib/id3v2tag.h"
#include "taglib/id3v2frame.h"
#include "taglib/attachedpictureframe.h"
#include "taglib/textidentificationframe.h"
#include "taglib/commentsframe.h"
#include "taglib/unsynchronizedlyricsframe.h"
#include "taglib/popularimeterframe.h"

#include "taglib/mp4file.h"
#include "taglib/mp4tag.h"
#include "taglib/mp4item.h"
#include "taglib/mp4coverart.h"

#include "taglib/flacfile.h"
#include "taglib/flacpicture.h"
#include "taglib/xiphcomment.h"

#include "taglib/vorbisfile.h"
#include "taglib/opusfile.h"
#include "taglib/oggflacfile.h"

#include "taglib/apefile.h"
#include "taglib/apetag.h"

#include "taglib/wavfile.h"
#include "taglib/aifffile.h"
#include "taglib/wavpackfile.h"
#include "taglib/trueaudiofile.h"

#include "taglib/mpcfile.h"
#include "taglib/speexfile.h"
#include "taglib/asffile.h"

#include "taglib/dsffile.h"
#include "taglib/dsdifffile.h"

#include "taglib/tstring.h"
#include "taglib/tstringlist.h"

@implementation TagLibAudioMetadata

- (instancetype)init {
    if (self = [super init]) {
        _trackNumber = 0;
        _totalTracks = 0;
        _discNumber = 0;
        _totalDiscs = 0;
        _duration = 0.0;
        _bitrate = 0;
        _sampleRate = 0;
        _channels = 0;
        _bitDepth = 0;
        _bpm = 0;
        _compilation = NO;
    }
    return self;
}

@end


@implementation TagLibMetadataExtractor

#pragma mark - Helper Functions

// Convert TagLib::String to NSString
static NSString* _Nullable TagStringToNSString(const TagLib::String& str) {
    if (str.isEmpty()) {
        return nil;
    }
    std::string utf8 = str.to8Bit(true);
    return [NSString stringWithUTF8String:utf8.c_str()];
}

// Extract number from string (e.g., "3/12" -> 3)
static NSInteger ExtractNumber(const TagLib::String& str) {
    if (str.isEmpty()) {
        return 0;
    }
    return str.toInt();
}

// Parse track/disc number string (e.g., "3/12" -> (3, 12))
static void ParseNumberPair(const TagLib::String& str, NSInteger& number, NSInteger& total) {
    if (str.isEmpty()) {
        return;
    }
    
    std::string s = str.to8Bit(true);
    size_t slashPos = s.find('/');
    
    if (slashPos != std::string::npos) {
        number = atoi(s.substr(0, slashPos).c_str());
        total = atoi(s.substr(slashPos + 1).c_str());
    } else {
        number = str.toInt();
    }
}

#pragma mark - Format-Specific Extraction

// Extract ID3v2 metadata (MP3)
static void ExtractID3v2Metadata(TagLib::ID3v2::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    const TagLib::ID3v2::FrameList& frames = tag->frameList();
    
    for (auto it = frames.begin(); it != frames.end(); ++it) {
        TagLib::ID3v2::Frame* frame = *it;
        TagLib::ByteVector frameID = frame->frameID();
        std::string frameIDStr(frameID.data(), frameID.size());
        
        // Text identification frames
        if (auto textFrame = dynamic_cast<TagLib::ID3v2::TextIdentificationFrame*>(frame)) {
            TagLib::StringList fieldList = textFrame->fieldList();
            if (fieldList.isEmpty()) continue;
            
            TagLib::String value = fieldList.toString(", ");
            
            // Track number
            if (frameIDStr == "TRCK") {
                NSInteger trackNum = 0, trackTotal = 0;
                ParseNumberPair(value, trackNum, trackTotal);
                metadata.trackNumber = trackNum;
                metadata.totalTracks = trackTotal;
            }
            // Disc number
            else if (frameIDStr == "TPOS") {
                NSInteger discNum = 0, discTotal = 0;
                ParseNumberPair(value, discNum, discTotal);
                metadata.discNumber = discNum;
                metadata.totalDiscs = discTotal;
            }
            // BPM
            else if (frameIDStr == "TBPM") {
                metadata.bpm = value.toInt();
            }
            // Album Artist
            else if (frameIDStr == "TPE2") {
                metadata.albumArtist = TagStringToNSString(value);
            }
            // Sort fields
            else if (frameIDStr == "TSOT") {
                metadata.sortTitle = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSOP") {
                metadata.sortArtist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSOA") {
                metadata.sortAlbum = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSO2") {
                metadata.sortAlbumArtist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSOC") {
                metadata.sortComposer = TagStringToNSString(value);
            }
            // Date fields
            else if (frameIDStr == "TDRL") {
                metadata.releaseDate = TagStringToNSString(value);
            }
            else if (frameIDStr == "TDOR") {
                metadata.originalReleaseDate = TagStringToNSString(value);
            }
            // Personnel
            else if (frameIDStr == "TPE3") {
                metadata.conductor = TagStringToNSString(value);
            }
            else if (frameIDStr == "TPE4") {
                metadata.remixer = TagStringToNSString(value);
            }
            else if (frameIDStr == "TEXT") {
                metadata.lyricist = TagStringToNSString(value);
            }
            else if (frameIDStr == "TPUB") {
                metadata.label = TagStringToNSString(value);
            }
            else if (frameIDStr == "TENC") {
                metadata.encodedBy = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSSE") {
                metadata.encoderSettings = TagStringToNSString(value);
            }
            else if (frameIDStr == "TSRC") {
                metadata.isrc = TagStringToNSString(value);
            }
            else if (frameIDStr == "TCOP") {
                metadata.copyright = TagStringToNSString(value);
            }
            else if (frameIDStr == "TIT3") {
                metadata.subtitle = TagStringToNSString(value);
            }
            else if (frameIDStr == "TIT1") {
                metadata.grouping = TagStringToNSString(value);
            }
            else if (frameIDStr == "TLAN") {
                metadata.language = TagStringToNSString(value);
            }
            else if (frameIDStr == "TKEY") {
                metadata.musicalKey = TagStringToNSString(value);
            }
            else if (frameIDStr == "TMOO") {
                metadata.mood = TagStringToNSString(value);
            }
            // Compilation flag
            else if (frameIDStr == "TCMP") {
                metadata.compilation = (value == "1");
            }
        }
        // User-defined text frames (TXXX) - for extended metadata
        else if (auto userFrame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame*>(frame)) {
            TagLib::String description = userFrame->description();
            TagLib::String userValue = userFrame->fieldList().back();
            std::string descStr = description.upper().to8Bit(true);
            
            if (descStr == "RELEASETYPE" || descStr == "MUSICBRAINZ ALBUM TYPE") {
                metadata.releaseType = TagStringToNSString(userValue);
            }
            else if (descStr == "BARCODE" || descStr == "UPC" || descStr == "EAN") {
                metadata.barcode = TagStringToNSString(userValue);
            }
            else if (descStr == "CATALOGNUMBER" || descStr == "CATALOG NUMBER") {
                metadata.catalogNumber = TagStringToNSString(userValue);
            }
            else if (descStr == "RELEASECOUNTRY" || descStr == "MUSICBRAINZ ALBUM RELEASE COUNTRY") {
                metadata.releaseCountry = TagStringToNSString(userValue);
            }
            else if (descStr == "ARTISTTYPE" || descStr == "MUSICBRAINZ ARTIST TYPE") {
                metadata.artistType = TagStringToNSString(userValue);
            }
        }
        // Comments
        else if (auto commFrame = dynamic_cast<TagLib::ID3v2::CommentsFrame*>(frame)) {
            if (metadata.comment == nil) {
                metadata.comment = TagStringToNSString(commFrame->text());
            }
        }
        // Lyrics
        else if (auto lyricsFrame = dynamic_cast<TagLib::ID3v2::UnsynchronizedLyricsFrame*>(frame)) {
            if (metadata.lyrics == nil) {
                metadata.lyrics = TagStringToNSString(lyricsFrame->text());
            }
        }
        // Attached picture (album art)
        else if (auto picFrame = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame*>(frame)) {
            TagLib::ByteVector picData = picFrame->picture();
            
            // Skip empty pictures
            if (picData.size() == 0) continue;
            
            // If we haven't found artwork yet, take any picture
            // If we have artwork but this is FrontCover, prefer it
            bool shouldExtract = (metadata.artworkData == nil) || 
                                (picFrame->type() == TagLib::ID3v2::AttachedPictureFrame::FrontCover);
            
            if (shouldExtract) {
                metadata.artworkData = [NSData dataWithBytes:picData.data() length:picData.size()];
                metadata.artworkMimeType = TagStringToNSString(picFrame->mimeType());
            }
        }
    }
}

// Extract MP4 metadata
static void ExtractMP4Metadata(TagLib::MP4::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    const TagLib::MP4::ItemMap& items = tag->itemMap();
    
    // Track number
    if (items.contains("trkn")) {
        TagLib::MP4::Item::IntPair trackPair = items["trkn"].toIntPair();
        metadata.trackNumber = trackPair.first;
        metadata.totalTracks = trackPair.second;
    }
    
    // Disc number
    if (items.contains("disk")) {
        TagLib::MP4::Item::IntPair discPair = items["disk"].toIntPair();
        metadata.discNumber = discPair.first;
        metadata.totalDiscs = discPair.second;
    }
    
    // BPM
    if (items.contains("tmpo")) {
        metadata.bpm = items["tmpo"].toInt();
    }
    
    // Album Artist
    if (items.contains("aART")) {
        metadata.albumArtist = TagStringToNSString(items["aART"].toStringList().toString(", "));
    }
    
    // Compilation
    if (items.contains("cpil")) {
        metadata.compilation = items["cpil"].toBool();
    }
    
    // Sort fields
    if (items.contains("sonm")) {
        metadata.sortTitle = TagStringToNSString(items["sonm"].toStringList().toString());
    }
    if (items.contains("soar")) {
        metadata.sortArtist = TagStringToNSString(items["soar"].toStringList().toString());
    }
    if (items.contains("soal")) {
        metadata.sortAlbum = TagStringToNSString(items["soal"].toStringList().toString());
    }
    if (items.contains("soaa")) {
        metadata.sortAlbumArtist = TagStringToNSString(items["soaa"].toStringList().toString());
    }
    if (items.contains("soco")) {
        metadata.sortComposer = TagStringToNSString(items["soco"].toStringList().toString());
    }
    
    // Grouping
    if (items.contains("©grp")) {
        metadata.grouping = TagStringToNSString(items["©grp"].toStringList().toString());
    }
    
    // Copyright
    if (items.contains("cprt")) {
        metadata.copyright = TagStringToNSString(items["cprt"].toStringList().toString());
    }
    
    // Lyrics
    if (items.contains("©lyr")) {
        metadata.lyrics = TagStringToNSString(items["©lyr"].toStringList().toString());
    }
    
    // Encoded by
    if (items.contains("©too")) {
        metadata.encodedBy = TagStringToNSString(items["©too"].toStringList().toString());
    }
    
    // Cover art
    if (items.contains("covr")) {
        TagLib::MP4::CoverArtList coverArtList = items["covr"].toCoverArtList();
        if (!coverArtList.isEmpty()) {
            TagLib::MP4::CoverArt coverArt = coverArtList.front();
            TagLib::ByteVector imageData = coverArt.data();
            metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
            
            // Determine MIME type
            switch (coverArt.format()) {
                case TagLib::MP4::CoverArt::JPEG:
                    metadata.artworkMimeType = @"image/jpeg";
                    break;
                case TagLib::MP4::CoverArt::PNG:
                    metadata.artworkMimeType = @"image/png";
                    break;
                case TagLib::MP4::CoverArt::BMP:
                    metadata.artworkMimeType = @"image/bmp";
                    break;
                case TagLib::MP4::CoverArt::GIF:
                    metadata.artworkMimeType = @"image/gif";
                    break;
                default:
                    metadata.artworkMimeType = @"image/jpeg";
                    break;
            }
        }
    }
    
    // Professional music player fields - freeform atoms
    // MP4 uses freeform identifiers like ----:com.apple.iTunes:FIELDNAME
    if (items.contains("----:com.apple.iTunes:RELEASETYPE")) {
        metadata.releaseType = TagStringToNSString(items["----:com.apple.iTunes:RELEASETYPE"].toStringList().toString());
    } else if (items.contains("----:com.apple.iTunes:MusicBrainz Album Type")) {
        metadata.releaseType = TagStringToNSString(items["----:com.apple.iTunes:MusicBrainz Album Type"].toStringList().toString());
    }
    
    if (items.contains("----:com.apple.iTunes:BARCODE")) {
        metadata.barcode = TagStringToNSString(items["----:com.apple.iTunes:BARCODE"].toStringList().toString());
    }
    
    if (items.contains("----:com.apple.iTunes:CATALOGNUMBER")) {
        metadata.catalogNumber = TagStringToNSString(items["----:com.apple.iTunes:CATALOGNUMBER"].toStringList().toString());
    }
    
    if (items.contains("----:com.apple.iTunes:MusicBrainz Album Release Country")) {
        metadata.releaseCountry = TagStringToNSString(items["----:com.apple.iTunes:MusicBrainz Album Release Country"].toStringList().toString());
    }
}

// Extract picture from Xiph Comment (used by Vorbis, Opus, etc.)
static void ExtractXiphPicture(TagLib::Ogg::XiphComment* tag, TagLibAudioMetadata* metadata) {
    if (!tag || metadata.artworkData != nil) return;
    
    // Check if there are any pictures embedded
    const TagLib::List<TagLib::FLAC::Picture*>& pictures = tag->pictureList();
    
    // First pass: look for FrontCover
    for (auto pic : pictures) {
        if (pic->type() == TagLib::FLAC::Picture::FrontCover) {
            TagLib::ByteVector imageData = pic->data();
            if (imageData.size() > 0) {
                metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
                metadata.artworkMimeType = TagStringToNSString(pic->mimeType());
                return;
            }
        }
    }
    
    // Second pass: take any picture
    for (auto pic : pictures) {
        TagLib::ByteVector imageData = pic->data();
        if (imageData.size() > 0) {
            metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
            metadata.artworkMimeType = TagStringToNSString(pic->mimeType());
            break;
        }
    }
}

// Extract Xiph Comment metadata (FLAC, OGG Vorbis, Opus, etc.)
static void ExtractXiphCommentMetadata(TagLib::Ogg::XiphComment* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    const TagLib::PropertyMap& properties = tag->properties();
    
    // Track/Disc numbers
    if (properties.contains("TRACKNUMBER")) {
        TagLib::String trackStr = properties["TRACKNUMBER"].front();
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(trackStr, trackNum, trackTotal);
        metadata.trackNumber = trackNum;
        if (trackTotal > 0) metadata.totalTracks = trackTotal;
    }
    if (properties.contains("TRACKTOTAL") || properties.contains("TOTALTRACKS")) {
        TagLib::String key = properties.contains("TRACKTOTAL") ? "TRACKTOTAL" : "TOTALTRACKS";
        metadata.totalTracks = ExtractNumber(properties[key].front());
    }
    if (properties.contains("DISCNUMBER")) {
        TagLib::String discStr = properties["DISCNUMBER"].front();
        NSInteger discNum = 0, discTotal = 0;
        ParseNumberPair(discStr, discNum, discTotal);
        metadata.discNumber = discNum;
        if (discTotal > 0) metadata.totalDiscs = discTotal;
    }
    if (properties.contains("DISCTOTAL") || properties.contains("TOTALDISCS")) {
        TagLib::String key = properties.contains("DISCTOTAL") ? "DISCTOTAL" : "TOTALDISCS";
        metadata.totalDiscs = ExtractNumber(properties[key].front());
    }
    
    // Album Artist
    if (properties.contains("ALBUMARTIST")) {
        metadata.albumArtist = TagStringToNSString(properties["ALBUMARTIST"].front());
    }
    
    // BPM
    if (properties.contains("BPM")) {
        metadata.bpm = ExtractNumber(properties["BPM"].front());
    }
    
    // Sort fields
    if (properties.contains("TITLESORT")) {
        metadata.sortTitle = TagStringToNSString(properties["TITLESORT"].front());
    }
    if (properties.contains("ARTISTSORT")) {
        metadata.sortArtist = TagStringToNSString(properties["ARTISTSORT"].front());
    }
    if (properties.contains("ALBUMSORT")) {
        metadata.sortAlbum = TagStringToNSString(properties["ALBUMSORT"].front());
    }
    if (properties.contains("ALBUMARTISTSORT")) {
        metadata.sortAlbumArtist = TagStringToNSString(properties["ALBUMARTISTSORT"].front());
    }
    if (properties.contains("COMPOSERSORT")) {
        metadata.sortComposer = TagStringToNSString(properties["COMPOSERSORT"].front());
    }
    
    // Personnel
    if (properties.contains("CONDUCTOR")) {
        metadata.conductor = TagStringToNSString(properties["CONDUCTOR"].front());
    }
    if (properties.contains("REMIXER")) {
        metadata.remixer = TagStringToNSString(properties["REMIXER"].front());
    }
    if (properties.contains("PRODUCER")) {
        metadata.producer = TagStringToNSString(properties["PRODUCER"].front());
    }
    if (properties.contains("ENGINEER")) {
        metadata.engineer = TagStringToNSString(properties["ENGINEER"].front());
    }
    if (properties.contains("LYRICIST")) {
        metadata.lyricist = TagStringToNSString(properties["LYRICIST"].front());
    }
    
    // Descriptive
    if (properties.contains("SUBTITLE")) {
        metadata.subtitle = TagStringToNSString(properties["SUBTITLE"].front());
    }
    if (properties.contains("GROUPING")) {
        metadata.grouping = TagStringToNSString(properties["GROUPING"].front());
    }
    if (properties.contains("MOVEMENT")) {
        metadata.movement = TagStringToNSString(properties["MOVEMENT"].front());
    }
    if (properties.contains("MOOD")) {
        metadata.mood = TagStringToNSString(properties["MOOD"].front());
    }
    if (properties.contains("LANGUAGE")) {
        metadata.language = TagStringToNSString(properties["LANGUAGE"].front());
    }
    if (properties.contains("INITIALKEY") || properties.contains("KEY")) {
        TagLib::String key = properties.contains("INITIALKEY") ? "INITIALKEY" : "KEY";
        metadata.musicalKey = TagStringToNSString(properties[key].front());
    }
    
    // Other metadata
    if (properties.contains("COPYRIGHT")) {
        metadata.copyright = TagStringToNSString(properties["COPYRIGHT"].front());
    }
    if (properties.contains("LYRICS")) {
        metadata.lyrics = TagStringToNSString(properties["LYRICS"].front());
    }
    if (properties.contains("LABEL")) {
        metadata.label = TagStringToNSString(properties["LABEL"].front());
    }
    if (properties.contains("ISRC")) {
        metadata.isrc = TagStringToNSString(properties["ISRC"].front());
    }
    if (properties.contains("ENCODEDBY")) {
        metadata.encodedBy = TagStringToNSString(properties["ENCODEDBY"].front());
    }
    if (properties.contains("ENCODERSETTINGS")) {
        metadata.encoderSettings = TagStringToNSString(properties["ENCODERSETTINGS"].front());
    }
    
    // Date fields
    if (properties.contains("RELEASEDATE")) {
        metadata.releaseDate = TagStringToNSString(properties["RELEASEDATE"].front());
    }
    if (properties.contains("ORIGINALDATE")) {
        metadata.originalReleaseDate = TagStringToNSString(properties["ORIGINALDATE"].front());
    }
    
    // MusicBrainz IDs
    if (properties.contains("MUSICBRAINZ_ARTISTID")) {
        metadata.musicBrainzArtistId = TagStringToNSString(properties["MUSICBRAINZ_ARTISTID"].front());
    }
    if (properties.contains("MUSICBRAINZ_ALBUMID")) {
        metadata.musicBrainzAlbumId = TagStringToNSString(properties["MUSICBRAINZ_ALBUMID"].front());
    }
    if (properties.contains("MUSICBRAINZ_TRACKID")) {
        metadata.musicBrainzTrackId = TagStringToNSString(properties["MUSICBRAINZ_TRACKID"].front());
    }
    if (properties.contains("MUSICBRAINZ_RELEASEGROUPID")) {
        metadata.musicBrainzReleaseGroupId = TagStringToNSString(properties["MUSICBRAINZ_RELEASEGROUPID"].front());
    }
    
    // Professional music player fields
    if (properties.contains("RELEASETYPE")) {
        metadata.releaseType = TagStringToNSString(properties["RELEASETYPE"].front());
    } else if (properties.contains("MUSICBRAINZ_ALBUMTYPE")) {
        metadata.releaseType = TagStringToNSString(properties["MUSICBRAINZ_ALBUMTYPE"].front());
    }
    
    if (properties.contains("BARCODE")) {
        metadata.barcode = TagStringToNSString(properties["BARCODE"].front());
    } else if (properties.contains("UPC")) {
        metadata.barcode = TagStringToNSString(properties["UPC"].front());
    } else if (properties.contains("EAN")) {
        metadata.barcode = TagStringToNSString(properties["EAN"].front());
    }
    
    if (properties.contains("CATALOGNUMBER")) {
        metadata.catalogNumber = TagStringToNSString(properties["CATALOGNUMBER"].front());
    } else if (properties.contains("CATALOG")) {
        metadata.catalogNumber = TagStringToNSString(properties["CATALOG"].front());
    }
    
    if (properties.contains("RELEASECOUNTRY")) {
        metadata.releaseCountry = TagStringToNSString(properties["RELEASECOUNTRY"].front());
    } else if (properties.contains("MUSICBRAINZ_ALBUMRELEASECOUNTRY")) {
        metadata.releaseCountry = TagStringToNSString(properties["MUSICBRAINZ_ALBUMRELEASECOUNTRY"].front());
    }
    
    if (properties.contains("MUSICBRAINZ_ARTISTTYPE")) {
        metadata.artistType = TagStringToNSString(properties["MUSICBRAINZ_ARTISTTYPE"].front());
    }
    
    // ReplayGain
    if (properties.contains("REPLAYGAIN_TRACK_GAIN")) {
        metadata.replayGainTrack = TagStringToNSString(properties["REPLAYGAIN_TRACK_GAIN"].front());
    }
    if (properties.contains("REPLAYGAIN_ALBUM_GAIN")) {
        metadata.replayGainAlbum = TagStringToNSString(properties["REPLAYGAIN_ALBUM_GAIN"].front());
    }
    
    // Compilation
    if (properties.contains("COMPILATION")) {
        TagLib::String compStr = properties["COMPILATION"].front();
        metadata.compilation = (compStr == "1" || compStr.upper() == "TRUE");
    }
}

// Extract FLAC picture
static void ExtractFLACPicture(TagLib::FLAC::File* file, TagLibAudioMetadata* metadata) {
    if (!file) return;
    
    const TagLib::List<TagLib::FLAC::Picture*>& pictures = file->pictureList();
    
    // First pass: look for FrontCover specifically
    for (auto pic : pictures) {
        if (pic->type() == TagLib::FLAC::Picture::FrontCover) {
            TagLib::ByteVector imageData = pic->data();
            if (imageData.size() > 0) {
                metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
                metadata.artworkMimeType = TagStringToNSString(pic->mimeType());
                return;
            }
        }
    }
    
    // Second pass: if no FrontCover found, take any picture
    for (auto pic : pictures) {
        TagLib::ByteVector imageData = pic->data();
        if (imageData.size() > 0) {
            metadata.artworkData = [NSData dataWithBytes:imageData.data() length:imageData.size()];
            metadata.artworkMimeType = TagStringToNSString(pic->mimeType());
            break;
        }
    }
}

// Extract APE metadata
static void ExtractAPEMetadata(TagLib::APE::Tag* tag, TagLibAudioMetadata* metadata) {
    if (!tag) return;
    
    const TagLib::APE::ItemListMap& items = tag->itemListMap();
    
    // Track/Disc numbers
    if (items.contains("TRACK")) {
        TagLib::String trackStr = items["TRACK"].values().front();
        NSInteger trackNum = 0, trackTotal = 0;
        ParseNumberPair(trackStr, trackNum, trackTotal);
        metadata.trackNumber = trackNum;
        if (trackTotal > 0) metadata.totalTracks = trackTotal;
    }
    if (items.contains("DISC")) {
        TagLib::String discStr = items["DISC"].values().front();
        NSInteger discNum = 0, discTotal = 0;
        ParseNumberPair(discStr, discNum, discTotal);
        metadata.discNumber = discNum;
        if (discTotal > 0) metadata.totalDiscs = discTotal;
    }
    
    // Album Artist
    if (items.contains("ALBUM ARTIST") || items.contains("ALBUMARTIST")) {
        TagLib::String key = items.contains("ALBUM ARTIST") ? "ALBUM ARTIST" : "ALBUMARTIST";
        metadata.albumArtist = TagStringToNSString(items[key].values().front());
    }
    
    // BPM
    if (items.contains("BPM")) {
        metadata.bpm = items["BPM"].values().front().toInt();
    }
    
    // Other metadata
    if (items.contains("COPYRIGHT")) {
        metadata.copyright = TagStringToNSString(items["COPYRIGHT"].values().front());
    }
    if (items.contains("LYRICS")) {
        metadata.lyrics = TagStringToNSString(items["LYRICS"].values().front());
    }
    if (items.contains("ISRC")) {
        metadata.isrc = TagStringToNSString(items["ISRC"].values().front());
    }
    if (items.contains("LABEL")) {
        metadata.label = TagStringToNSString(items["LABEL"].values().front());
    }
    
    // Professional music player fields
    if (items.contains("RELEASETYPE")) {
        metadata.releaseType = TagStringToNSString(items["RELEASETYPE"].values().front());
    }
    if (items.contains("BARCODE")) {
        metadata.barcode = TagStringToNSString(items["BARCODE"].values().front());
    } else if (items.contains("UPC")) {
        metadata.barcode = TagStringToNSString(items["UPC"].values().front());
    }
    if (items.contains("CATALOGNUMBER")) {
        metadata.catalogNumber = TagStringToNSString(items["CATALOGNUMBER"].values().front());
    }
    if (items.contains("RELEASECOUNTRY")) {
        metadata.releaseCountry = TagStringToNSString(items["RELEASECOUNTRY"].values().front());
    }
    
    // Cover art
    if (items.contains("COVER ART (FRONT)")) {
        TagLib::ByteVector coverData = items["COVER ART (FRONT)"].binaryData();
        // APE cover art typically has description followed by null byte, then image data
        if (coverData.size() > 0) {
            // Find first null byte to skip description
            unsigned int startPos = 0;
            for (unsigned int i = 0; i < coverData.size(); ++i) {
                if (coverData[i] == 0) {
                    startPos = i + 1;
                    break;
                }
            }
            if (startPos < coverData.size()) {
                metadata.artworkData = [NSData dataWithBytes:coverData.data() + startPos 
                                                      length:coverData.size() - startPos];
            }
        }
    }
}

#pragma mark - Main Extraction Method

+ (nullable TagLibAudioMetadata *)extractMetadataFromURL:(NSURL *)fileURL 
                                                   error:(NSError **)error {
    if (!fileURL || ![fileURL isFileURL]) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid file URL"}];
        }
        return nil;
    }
    
    const char* filePath = [fileURL.path UTF8String];
    
    // Create FileRef for basic metadata
    TagLib::FileRef fileRef(filePath);
    
    if (fileRef.isNull() || !fileRef.tag()) {
        if (error) {
            *error = [NSError errorWithDomain:@"TagLibMetadataExtractor"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read file or no metadata found"}];
        }
        return nil;
    }
    
    TagLibAudioMetadata* metadata = [[TagLibAudioMetadata alloc] init];
    
    // Extract basic tag information
    TagLib::Tag* tag = fileRef.tag();
    if (tag) {
        metadata.title = TagStringToNSString(tag->title());
        metadata.artist = TagStringToNSString(tag->artist());
        metadata.album = TagStringToNSString(tag->album());
        metadata.genre = TagStringToNSString(tag->genre());
        metadata.comment = TagStringToNSString(tag->comment());
        
        if (tag->year() > 0) {
            metadata.year = [NSString stringWithFormat:@"%u", tag->year()];
        }
        
        if (tag->track() > 0) {
            metadata.trackNumber = tag->track();
        }
    }
    
    // Extract audio properties
    TagLib::AudioProperties* properties = fileRef.audioProperties();
    if (properties) {
        metadata.duration = properties->lengthInSeconds();
        metadata.bitrate = properties->bitrate();
        metadata.sampleRate = properties->sampleRate();
        metadata.channels = properties->channels();
    }
    
    // Extract format-specific metadata
    std::string ext = [[fileURL pathExtension].lowercaseString UTF8String];
    
    // MP3
    if (ext == "mp3") {
        TagLib::MPEG::File mpegFile(filePath);
        if (mpegFile.isValid()) {
            metadata.codec = @"MP3";
            
            if (mpegFile.ID3v2Tag()) {
                ExtractID3v2Metadata(mpegFile.ID3v2Tag(), metadata);
            }
        }
    }
    // MP4/M4A
    else if (ext == "m4a" || ext == "m4b" || ext == "m4p" || ext == "mp4") {
        TagLib::MP4::File mp4File(filePath);
        if (mp4File.isValid()) {
            metadata.codec = @"AAC";
            
            if (mp4File.tag()) {
                ExtractMP4Metadata(mp4File.tag(), metadata);
            }
        }
    }
    // FLAC
    else if (ext == "flac") {
        TagLib::FLAC::File flacFile(filePath);
        if (flacFile.isValid()) {
            metadata.codec = @"FLAC";
            
            if (flacFile.xiphComment()) {
                ExtractXiphCommentMetadata(flacFile.xiphComment(), metadata);
            }
            
            // Extract bit depth
            if (flacFile.audioProperties()) {
                metadata.bitDepth = flacFile.audioProperties()->bitsPerSample();
            }
            
            // Extract cover art
            ExtractFLACPicture(&flacFile, metadata);
        }
    }
    // OGG Vorbis
    else if (ext == "ogg") {
        TagLib::Ogg::Vorbis::File vorbisFile(filePath);
        if (vorbisFile.isValid()) {
            metadata.codec = @"Vorbis";
            
            if (vorbisFile.tag()) {
                ExtractXiphCommentMetadata(vorbisFile.tag(), metadata);
                ExtractXiphPicture(vorbisFile.tag(), metadata);
            }
        }
    }
    // Opus
    else if (ext == "opus") {
        TagLib::Ogg::Opus::File opusFile(filePath);
        if (opusFile.isValid()) {
            metadata.codec = @"Opus";
            
            if (opusFile.tag()) {
                ExtractXiphCommentMetadata(opusFile.tag(), metadata);
                ExtractXiphPicture(opusFile.tag(), metadata);
            }
        }
    }
    // OGG FLAC
    else if (ext == "oga") {
        TagLib::Ogg::FLAC::File oggFlacFile(filePath);
        if (oggFlacFile.isValid()) {
            metadata.codec = @"OGG FLAC";
            
            if (oggFlacFile.tag()) {
                ExtractXiphCommentMetadata(oggFlacFile.tag(), metadata);
                ExtractXiphPicture(oggFlacFile.tag(), metadata);
            }
        }
    }
    // APE (Monkey's Audio)
    else if (ext == "ape") {
        TagLib::APE::File apeFile(filePath);
        if (apeFile.isValid()) {
            metadata.codec = @"APE";
            
            if (apeFile.APETag()) {
                ExtractAPEMetadata(apeFile.APETag(), metadata);
            }
        }
    }
    // WavPack
    else if (ext == "wv") {
        TagLib::WavPack::File wvFile(filePath);
        if (wvFile.isValid()) {
            metadata.codec = @"WavPack";
            
            if (wvFile.APETag()) {
                ExtractAPEMetadata(wvFile.APETag(), metadata);
            }
        }
    }
    // WAV
    else if (ext == "wav") {
        TagLib::RIFF::WAV::File wavFile(filePath);
        if (wavFile.isValid()) {
            metadata.codec = @"WAV";
            
            if (wavFile.ID3v2Tag()) {
                ExtractID3v2Metadata(wavFile.ID3v2Tag(), metadata);
            }
            
            // Extract bit depth
            if (wavFile.audioProperties()) {
                metadata.bitDepth = wavFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // AIFF
    else if (ext == "aiff" || ext == "aif") {
        TagLib::RIFF::AIFF::File aiffFile(filePath);
        if (aiffFile.isValid()) {
            metadata.codec = @"AIFF";
            
            if (aiffFile.tag()) {
                ExtractID3v2Metadata(aiffFile.tag(), metadata);
            }
            
            // Extract bit depth
            if (aiffFile.audioProperties()) {
                metadata.bitDepth = aiffFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // TrueAudio
    else if (ext == "tta") {
        TagLib::TrueAudio::File ttaFile(filePath);
        if (ttaFile.isValid()) {
            metadata.codec = @"TrueAudio";
            
            if (ttaFile.ID3v2Tag()) {
                ExtractID3v2Metadata(ttaFile.ID3v2Tag(), metadata);
            }
            
            // Extract bit depth
            if (ttaFile.audioProperties()) {
                metadata.bitDepth = ttaFile.audioProperties()->bitsPerSample();
            }
        }
    }
    // Musepack
    else if (ext == "mpc") {
        TagLib::MPC::File mpcFile(filePath);
        if (mpcFile.isValid()) {
            metadata.codec = @"Musepack";
            
            if (mpcFile.APETag()) {
                ExtractAPEMetadata(mpcFile.APETag(), metadata);
            }
        }
    }
    // Speex
    else if (ext == "spx") {
        TagLib::Ogg::Speex::File speexFile(filePath);
        if (speexFile.isValid()) {
            metadata.codec = @"Speex";
            
            if (speexFile.tag()) {
                ExtractXiphCommentMetadata(speexFile.tag(), metadata);
                ExtractXiphPicture(speexFile.tag(), metadata);
            }
        }
    }
    // ASF/WMA
    else if (ext == "wma" || ext == "asf") {
        TagLib::ASF::File asfFile(filePath);
        if (asfFile.isValid()) {
            metadata.codec = @"WMA";
            // ASF uses its own tag format, basic info already extracted
        }
    }
    // DSF
    else if (ext == "dsf") {
        TagLib::DSF::File dsfFile(filePath);
        if (dsfFile.isValid()) {
            metadata.codec = @"DSF";
            
            // DSF files use ID3v2 tags, but accessed via tag() method
            if (dsfFile.tag()) {
                // The tag() method returns an ID3v2::Tag*
                if (auto id3tag = dynamic_cast<TagLib::ID3v2::Tag*>(dsfFile.tag())) {
                    ExtractID3v2Metadata(id3tag, metadata);
                }
            }
        }
    }
    // DSDIFF
    else if (ext == "dff") {
        TagLib::DSDIFF::File dsdiffFile(filePath);
        if (dsdiffFile.isValid()) {
            metadata.codec = @"DSDIFF";
            // DSDIFF metadata is minimal
        }
    }
    
    return metadata;
}

#pragma mark - Format Support

+ (BOOL)isSupportedFormat:(NSString *)fileExtension {
    NSArray<NSString *>* supported = [self supportedExtensions];
    return [supported containsObject:[fileExtension lowercaseString]];
}

+ (NSArray<NSString *> *)supportedExtensions {
    return @[
        // Lossy formats
        @"mp3", @"mp2",              // MPEG Audio
        @"m4a", @"m4b", @"m4p", @"mp4", @"aac", // AAC/MP4
        @"ogg",                      // Ogg Vorbis
        @"opus",                     // Opus
        @"mpc",                      // Musepack
        @"wma", @"asf",             // Windows Media Audio
        @"spx",                      // Speex
        
        // Lossless formats
        @"flac",                     // FLAC
        @"ape",                      // Monkey's Audio
        @"wv",                       // WavPack
        @"tta",                      // TrueAudio
        @"wav",                      // WAV
        @"aiff", @"aif",             // AIFF
        @"dsf",                      // DSF (DSD)
        @"dff",                      // DSDIFF (DSD)
        @"oga",                      // OGG FLAC
    ];
}

@end


// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RoperzMusic is ERC721, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Strings for uint256;
    
    Counters.Counter private _tokenIds;

    struct MusicContent {
        string audioIPFS;      // IPFS hash for the audio file
        string metadataIPFS;   // IPFS hash for metadata (cover art, description, etc.)
        string title;
        string artist;
        string genre;
        uint256 duration;      // Duration in seconds
        uint256 releaseDate;
        string[] tags;
    }

    struct Song {
        address artist;
        MusicContent content;
        uint256 price;
        uint256 royaltyPercentage;
        uint256 listenerSharePercentage;
        uint256 playCount;
        bool isExplicit;
    }

    // Mapping from token ID to Song
    mapping(uint256 => Song) public songs;
    
    // Mapping from token ID to listener addresses
    mapping(uint256 => address[]) public songListeners;
    
    // Mapping from token ID to listener balances
    mapping(uint256 => mapping(address => uint256)) public listenerBalances;
    
    // Mapping for content verification
    mapping(string => bool) private usedIPFSHashes;

    event SongMinted(
        uint256 indexed tokenId, 
        address artist, 
        string title, 
        string audioIPFS, 
        string metadataIPFS
    );
    event ContentUpdated(uint256 indexed tokenId, string newAudioIPFS, string newMetadataIPFS);
    event PaymentReceived(uint256 indexed tokenId, address payer, uint256 amount);
    event RoyaltyDistributed(uint256 indexed tokenId, uint256 amount);

    constructor() ERC721("MusicPlatform", "MUSIC") {}

    modifier uniqueIPFS(string memory audioIPFS) {
        require(!usedIPFSHashes[audioIPFS], "IPFS hash already used");
        _;
    }

    function mintSong(
        string memory audioIPFS,
        string memory metadataIPFS,
        string memory title,
        string memory artistName,
        string memory genre,
        uint256 duration,
        string[] memory tags,
        uint256 price,
        uint256 royaltyPercentage,
        uint256 listenerSharePercentage,
        bool isExplicit
    ) public uniqueIPFS(audioIPFS) returns (uint256) {
        require(royaltyPercentage + listenerSharePercentage <= 100, "Invalid percentages");
        require(bytes(audioIPFS).length > 0, "Audio IPFS hash required");
        require(bytes(metadataIPFS).length > 0, "Metadata IPFS hash required");
        
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        
        _mint(msg.sender, newTokenId);
        
        MusicContent memory content = MusicContent({
            audioIPFS: audioIPFS,
            metadataIPFS: metadataIPFS,
            title: title,
            artist: artistName,
            genre: genre,
            duration: duration,
            releaseDate: block.timestamp,
            tags: tags
        });
        
        songs[newTokenId] = Song({
            artist: msg.sender,
            content: content,
            price: price,
            royaltyPercentage: royaltyPercentage,
            listenerSharePercentage: listenerSharePercentage,
            playCount: 0,
            isExplicit: isExplicit
        });
        
        usedIPFSHashes[audioIPFS] = true;
        
        emit SongMinted(newTokenId, msg.sender, title, audioIPFS, metadataIPFS);
        return newTokenId;
    }

    function updateSongContent(
        uint256 tokenId,
        string memory newAudioIPFS,
        string memory newMetadataIPFS
    ) public uniqueIPFS(newAudioIPFS) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not owner or approved");
        require(bytes(newAudioIPFS).length > 0, "Audio IPFS hash required");
        require(bytes(newMetadataIPFS).length > 0, "Metadata IPFS hash required");
        
        // Remove old IPFS hash from used list
        usedIPFSHashes[songs[tokenId].content.audioIPFS] = false;
        
        // Update IPFS hashes
        songs[tokenId].content.audioIPFS = newAudioIPFS;
        songs[tokenId].content.metadataIPFS = newMetadataIPFS;
        
        // Mark new IPFS hash as used
        usedIPFSHashes[newAudioIPFS] = true;
        
        emit ContentUpdated(tokenId, newAudioIPFS, newMetadataIPFS);
    }

    function playSong(uint256 tokenId) public payable nonReentrant {
        Song storage song = songs[tokenId];
        require(msg.value >= song.price, "Insufficient payment");
        
        // Calculate shares
        uint256 artistShare = (msg.value * song.royaltyPercentage) / 100;
        uint256 listenerShare = (msg.value * song.listenerSharePercentage) / 100;
        
        // Pay artist
        payable(song.artist).transfer(artistShare);
        
        // Distribute listener share
        if (songListeners[tokenId].length > 0 && listenerShare > 0) {
            uint256 sharePerListener = listenerShare / songListeners[tokenId].length;
            for (uint256 i = 0; i < songListeners[tokenId].length; i++) {
                address listener = songListeners[tokenId][i];
                listenerBalances[tokenId][listener] += sharePerListener;
            }
        }
        
        // Add new listener and increment play count
        _addListener(tokenId, msg.sender);
        song.playCount++;
        
        emit PaymentReceived(tokenId, msg.sender, msg.value);
    }

    function _addListener(uint256 tokenId, address listener) private {
        bool isNewListener = true;
        for (uint256 i = 0; i < songListeners[tokenId].length; i++) {
            if (songListeners[tokenId][i] == listener) {
                isNewListener = false;
                break;
            }
        }
        if (isNewListener) {
            songListeners[tokenId].push(listener);
        }
    }

    function getSongContent(uint256 tokenId) public view returns (
        string memory audioIPFS,
        string memory metadataIPFS,
        string memory title,
        string memory artist,
        string memory genre,
        uint256 duration,
        uint256 releaseDate,
        string[] memory tags,
        uint256 playCount,
        bool isExplicit
    ) {
        Song storage song = songs[tokenId];
        return (
            song.content.audioIPFS,
            song.content.metadataIPFS,
            song.content.title,
            song.content.artist,
            song.content.genre,
            song.content.duration,
            song.content.releaseDate,
            song.content.tags,
            song.playCount,
            song.isExplicit
        );
    }

    // URI functions for NFT metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return songs[tokenId].content.metadataIPFS;
    }
}
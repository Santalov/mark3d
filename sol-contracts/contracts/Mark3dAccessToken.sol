// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./Mark3dCollection.sol";

contract Mark3dAccessToken is ERC721Enumerable, AccessControl, Ownable {
    using Clones for address;

    /// @dev PrivateCollectionData - struct for collections list getter
    struct PrivateCollectionData {
        uint256 tokenId;                                // access token id
        Mark3dCollection contractAddress;               // collection contract address
        bytes data;                                     // additional meta data of collection
    }
    mapping(uint256 => Mark3dCollection) public tokenCollections;      // mapping from access token id to collection
    uint256 public tokensCount;                                        // count of collections
    Mark3dCollection public implementation;                            // collection contract implementation for cloning
    string private contractMetaUri;                                    // contract-level metadata
    mapping(uint256 => string) public tokenUris;                       // mapping of token metadata uri

    /// @dev constructor
    /// @param name - access token name
    /// @param symbol - access token symbol
    /// @param _contractMetaUri - contract-level metadata uri
    /// @param _implementation - address of PrivateCollection contract for cloning
    constructor(
        string memory name,
        string memory symbol,
        string memory _contractMetaUri,
        Mark3dCollection _implementation
    ) ERC721(name, symbol) {
        contractMetaUri = _contractMetaUri;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        token = _token;
        implementation = _implementation;
        collectionPrice = _collectionPrice;
    }

    /// @dev function for collection creating and cloning
    /// @param salt - value for cloning procedure to make address deterministic
    /// @param name - name of private collection token
    /// @param symbol - symbol of private collection token
    /// @param _contractMetaUri - contract-level metadata uri
    /// @param accessTokenMetaUri - metadata uri for access token
    /// @param data - private collection metadata
    function createCollection(
        bytes32 salt,
        string memory name,
        string memory symbol,
        string memory _contractMetaUri,
        string memory accessTokenMetaUri,
        bytes memory data
    ) external {
        uint256 tokenId = tokensCount;
        _mint(_msgSender(), tokenId);
        address instance = address(implementation).cloneDeterministic(salt);
        tokenCollections[tokenId] = Mark3dCollection(instance);
        tokenUris[tokenId] = accessTokenMetaUri;
        Mark3dCollection(instance).initialize(name, symbol,
            _contractMetaUri, this, tokenId, _msgSender(), data);
        tokensCount++;
    }

    /// @dev function for prediction of address of new collection
    /// @param salt - salt value for cloning
    /// @return predicted address of clone
    function predictDeterministicAddress(bytes32 salt) external view returns (address) {
        return address(implementation).predictDeterministicAddress(salt, address(this));
    }

    /// @dev function for changing private collection implementation
    /// @param _implementation - address of new instance of private collection
    function setImplementation(Mark3dCollection _implementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        implementation = _implementation;
    }

    /// @dev function for retrieving collections list. Implemented using basic pagination.
    /// @param page - page number (starting from zero)
    /// @param size - size of the page
    /// @return collection list and owned tokens count for each collection
    /// @notice This function is potentially unsafe, since it doesn't guarantee order (use fixed block number)
    function getSelfCollections(
        uint256 page,
        uint256 size
    ) external view returns (PrivateCollectionData[] memory, uint256[] memory) {
        require(size <= 1000, "MinterGuruCollectionsAccessToken: size must be 1000 or lower");
        uint256 total = ownedCollections[_msgSender()].length();
        require((total == 0 && page == 0) || page * size < total, "MinterGuruCollectionsAccessToken: out of bounds");
        uint256 resSize = size;
        if ((page + 1) * size > total) {
            resSize = total - page * size;
        }
        PrivateCollectionData[] memory res = new PrivateCollectionData[](resSize);
        uint256[] memory counts = new uint256[](resSize);
        for (uint256 i = page * size; i < page * size + resSize; i++) {
            uint256 tokenId = uint256(ownedCollections[_msgSender()].at(i));
            res[i - page * size] = PrivateCollectionData(tokenId, tokenCollections[tokenId],
                tokenCollections[tokenId].data());
            counts[i - page * size] = tokenCollections[tokenId].balanceOf(_msgSender());
        }
        return (res, counts);
    }

    /// @dev function for retrieving token lists. Implemented using basic pagination.
    /// @param ids - ids of tokens
    /// @param pages - page numbers (starting from zero)
    /// @param sizes - sizes of the pages
    /// @return owned token lists
    /// @notice This function is potentially unsafe, since it doesn't guarantee order (use fixed block number)
    function getSelfTokens(
        uint256[] calldata ids,
        uint256[] calldata pages,
        uint256[] calldata sizes
    ) external view returns (Mark3dCollection.TokenData[][] memory) {
        require(ids.length <= 1000, "MinterGuruCollectionsAccessToken: collections quantity must be 1000 or lower");
        require(ids.length == pages.length && pages.length == sizes.length, "MinterGuruCollectionsAccessToken: lengths unmatch");
        Mark3dCollection.TokenData[][] memory res = new Mark3dCollection.TokenData[][](ids.length);
        uint256 realSize = 0;
        uint256[] memory resSizes = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            require(address(tokenCollections[ids[i]]) != address(0), "MinterGuruCollectionsAccessToken: collection doesn't exist");
            uint256 total = tokenCollections[ids[i]].balanceOf(_msgSender());
            require((total == 0 && pages[i] == 0) || pages[i] * sizes[i] < total, "MinterGuruCollectionsAccessToken: out of bounds");
            resSizes[i] = sizes[i];
            if ((pages[i] + 1) * sizes[i] > total) {
                resSizes[i] = total - pages[i] * sizes[i];
            }
            realSize += resSizes[i];
            res[i] = new Mark3dCollection.TokenData[](resSizes[i]);
        }
        require(realSize <= 1000, "MinterGuruCollectionsAccessToken: tokens quantity must be 1000 or lower");
        for (uint256 i = 0; i < ids.length; i++) {
            Mark3dCollection collection = tokenCollections[ids[i]];
            for (uint256 j = pages[i] * sizes[i]; j < pages[i] * sizes[i] + resSizes[i]; j++) {
                uint256 tokenId = collection.tokenOfOwnerByIndex(_msgSender(), j);
                res[i][j - pages[i] * sizes[i]] = MinterGuruBaseCollection.TokenData(tokenId,
                    collection.tokenUris(tokenId), collection.tokenData(tokenId));
            }
        }
        return res;
    }

    /// @dev Set contract-level metadata URI
    /// @param _contractMetaUri - new metadata URI
    function setContractMetaUri(
        string memory _contractMetaUri
    ) external onlyOwner {
        contractMetaUri = _contractMetaUri;
    }

    /// @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    /// @return Metadata file URI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return tokenUris[tokenId];
    }

    /// @dev inheritance conflict solving
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC721Enumerable) returns (bool) {
        return AccessControl.supportsInterface(interfaceId) || ERC721Enumerable.supportsInterface(interfaceId);
    }

    /// @dev Contract-level metadata for OpenSea
    /// @return Metadata file URI
    function contractURI() public view returns (string memory) {
        return contractMetaUri;
    }
}
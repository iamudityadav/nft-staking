// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DZapNFT is ERC721URIStorage, Ownable {
    uint256 private _tokenId;

    constructor(address initialOwner) ERC721("DZap NFT", "DZNFT") Ownable(initialOwner) {}

    function safeMint(string memory uri) external returns (uint256) {
        ++_tokenId;

        _safeMint(msg.sender, _tokenId);
        _setTokenURI(_tokenId, uri);

        return _tokenId;
    }
}

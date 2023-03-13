// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NewNFT is ERC721EnumerableUpgradeable, OwnableUpgradeable, IERC721ReceiverUpgradeable {
    using StringsUpgradeable for uint256;

    string public cidURL;
    mapping(address => bool) public admin;
    mapping(address => bool) public control;

    // 链上品质记录, 可以不用扫块来记录开出的 nft 品质
    mapping(uint256 => uint256) public quality;

    event eventWithdraw(address indexed from, address indexed to, uint256 indexed tokenId, uint256 quality);

    modifier checkAdmin()
    {
        require(admin[_msgSender()], "not admin");
        _;
    }
    modifier checkControl()
    {
        require(control[_msgSender()], "not control");
        _;
    }

    function setAdmin(address _sender, bool _flag) public onlyOwner
    {
        admin[_sender] = _flag;
    }

    function setControl(address _sender, bool _flag) public onlyOwner
    {
        control[_sender] = _flag;
    }

    function initialize() public initializer
    {
        __ERC721_init("Starlight Edition", "Starlight Edition");
        __Ownable_init();
    }

    function _baseURI() internal override view virtual returns (string memory)
    {
        return cidURL;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), "/", quality[tokenId].toString())) : "";
    }

    function setCidURL(string memory _cidURL) public checkAdmin
    {
        cidURL = _cidURL;
    }

    function mint(uint256 _tokenId, uint256 _quality, address _minter) external payable checkControl
    {
        _safeMint(_minter, _tokenId);
        quality[_tokenId] = _quality;
    }

    function extract(address payable _address) public checkAdmin
    {
        _address.transfer(address(this).balance);
    }

    function getAllTokensByOwner(address _account) external view returns (uint256[] memory)
    {
        uint256 length = balanceOf(_account);
        uint256[] memory result = new uint256[](length);

        for (uint i = 0; i < length; i++)
            result[i] = tokenOfOwnerByIndex(_account, i);

        return result;
    }

    // 带品质的提现, 可以更改链上品质内容
    function Withdraw(address _from, address _to, uint256 _tokenId, uint256 _quality) external checkAdmin
    {
        if (!_exists(_tokenId))
        {
            _safeMint(_to, _tokenId);
            quality[_tokenId] = _quality;
        }
        else
        {
            safeTransferFrom(_from, _to, _tokenId);
            if (quality[_tokenId] != _quality)
            {
                quality[_tokenId] = _quality;
            }
        }

        emit eventWithdraw(_from, _to, _tokenId, _quality);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override pure returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }
}
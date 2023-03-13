// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract NewBlindBox is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;

    mapping(address => bool) public admin; //管理员权限
    bytes32 public merkleRoot;
    uint256 internal nonce;
    mapping(uint256 => string) public cidMap; //key=周期; value=cid
    mapping(address => mapping(uint256 => uint256)) public buyLimitList;

    //// Events
    struct EventInfo {
        uint256 term; //期数
        uint256 startTime; //开始时间
        uint256 endTime; //结束时间
        uint256 startTokenId; //盲盒随机数区间的开始
        uint256 endTokenId; //盲盒随机数区间的结束
        uint256 bought; //已购买数量
        uint256 price; //价格
        uint256 buyLimit; //单个用户购买上限
        bool whiteBool; //白名单开关
    }

    uint256 public nowTerm; //当前活动期数（驱动活动进程）
    mapping(uint256 => EventInfo) public eventInfos; //查询单期活动的详细信息
    mapping(uint256 => bool) public eventMap;
    uint256[] public eventArray; //活动列表
    mapping(uint256 => uint256[]) public indicesList; //tokenId 取值列表

    // 期数权重
    struct QualityWeight {
        uint256 weight1; // n 权重
        uint256 weight2; // r 权重
        uint256 weight3; // sr 权重
        uint256 weight4; // ssr 权重
    }

    // 链上品质记录, 可以不用扫块来记录开出的 nft 品质
    mapping(uint256 => uint256) public quality;
    mapping(uint256 => QualityWeight) public qualityWeightList; // key=期数, value=各品质权重

    // 已有 token 的期数, 用来计算品质
    mapping(uint256 => uint256) public tokenTerm; // key=tokenId, value=期数

    event eventWithdraw(address indexed from, address indexed to, uint256 indexed tokenId, uint256 quality);

    modifier checkAdmin()
    {
        require(admin[_msgSender()], "not admin");
        _;
    }

    modifier checkEventsStatus()
    {
        require(eventMap[nowTerm], "No activity yet");
        require(eventInfos[nowTerm].bought < eventInfos[nowTerm].endTokenId - eventInfos[nowTerm].startTokenId + 1, "Sold out");
        require(buyLimitList[_msgSender()][nowTerm] < eventInfos[nowTerm].buyLimit, "The purchase quantity exceeds the upper limit");

        require(msg.value >= eventInfos[nowTerm].price, "value error");
        require(block.timestamp >= eventInfos[nowTerm].startTime, "Mint is not turned on");
        require(block.timestamp < eventInfos[nowTerm].endTime, "Mint is closed");
        _;
    }

    function initialize() public initializer
    {
        __ERC721_init("Starlight Edition", "Starlight Edition");
        __Ownable_init();
    }

    function setAdmin(address _sender, bool _flag) public onlyOwner
    {
        admin[_sender] = _flag;
    }

    function _baseURI() internal override view virtual returns (string memory)
    {
        return cidMap[nowTerm];
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = cidMap[tokenTerm[tokenId]];
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString(), "/", quality[tokenId].toString())) : "";
    }

    function setCidMap(uint256 _term, string memory _cid) public checkAdmin
    {
        cidMap[_term] = _cid;
    }

    function setMerkleRoot(bytes32 _merkleRoot) public checkAdmin
    {
        merkleRoot = _merkleRoot;
    }

    function getMerkleLeaf(address _address) internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(_address));
    }

    function checkMerkle(bytes32[] calldata _merkleProof, address _address) public view returns (bool)
    {
        return MerkleProof.verify(_merkleProof, merkleRoot, getMerkleLeaf(_address));
    }

    // 新增活动配置
    function setEventInfo(
        uint256 _term,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _startTokenId,
        uint256 _endTokenId,
        uint256 _price,
        uint256 _buyLimit,
        bool _whiteBool
    ) public checkAdmin
    {
        require(!eventMap[_term], "There is already an event, please go to modify");

        EventInfo memory o = EventInfo({
            term : _term,
            startTime : _startTime,
            endTime : _endTime,
            startTokenId : _startTokenId,
            endTokenId : _endTokenId,
            bought : 0,
            price : _price ,
            buyLimit : _buyLimit,
            whiteBool : _whiteBool
        });
        eventInfos[_term] = o;
        eventMap[_term] = true;
        eventArray.push(_term);
        
        uint256 total = _endTokenId - _startTokenId + 1;

        uint256[] memory indices = new uint256[](total);
        indicesList[_term] = indices;
    }

    // 修改活动配置
    function editEvents(
        uint256 _term,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _buyLimit,
        bool _whiteBool
    ) public checkAdmin
    {
        require(eventMap[_term], "There is no such event, please go to add");
        eventInfos[_term].startTime = _startTime;
        eventInfos[_term].endTime = _endTime;
        eventInfos[_term].buyLimit = _buyLimit;
        eventInfos[_term].whiteBool = _whiteBool;
    }

    // 再次更新权重
    function setQualityWeight(
        uint256 _term,
        uint256 _weight1,
        uint256 _weight2,
        uint256 _weight3,
        uint256 _weight4
    ) public checkAdmin
    {
        require(_weight1 + _weight2 + _weight3 + _weight4 != 0, "quality weight argument error");

        qualityWeightList[_term].weight1 = _weight1;
        qualityWeightList[_term].weight2 = _weight2;
        qualityWeightList[_term].weight3 = _weight3;
        qualityWeightList[_term].weight4 = _weight4;
    }

    // 设置活动期数
    function setNowTerm(uint256 _term) public checkAdmin
    {
        nowTerm = _term;
    }

    function mint() external payable checkEventsStatus
    {
        require(!eventInfos[nowTerm].whiteBool, "Requires whitelist operation");

        _mint(_msgSender());
    }

    function mintWithWhite(bytes32[] calldata _merkleProof) external payable checkEventsStatus
    {
        require(checkMerkle(_merkleProof, _msgSender()), "invalid merkle proof");

        _mint(_msgSender());
    }

    function _mint(address _to) internal returns (uint) {
        require(_to != address(0), "Cannot mint to 0x0");
        require(eventInfos[nowTerm].startTokenId + eventInfos[nowTerm].bought - 1 < eventInfos[nowTerm].endTokenId, "Token limit reached");

        uint id = randomIndex();

        eventInfos[nowTerm].bought ++;
        buyLimitList[_msgSender()][nowTerm] ++;
        _safeMint(_msgSender(), id);

        //
        tokenTerm[id] = nowTerm;
        quality[id] = randomQuality(tokenTerm[id]);

        return id;
    }

    function randomIndex() internal returns (uint) {
        uint totalSize = eventInfos[nowTerm].endTokenId - eventInfos[nowTerm].startTokenId - eventInfos[nowTerm].bought + 1;
        uint index = uint(keccak256(abi.encodePacked(nonce, _msgSender(), block.difficulty, block.timestamp))) % totalSize;
        uint value = 0;

        if (indicesList[nowTerm][index] != 0) {
            value = indicesList[nowTerm][index];
        } else {
            value = index;
        }

        // Move last value to selected position
        if (indicesList[nowTerm][totalSize - 1] == 0) {
            // Array position not initialized, so use position
            indicesList[nowTerm][index] = totalSize - 1;
        } else {
            // Array position holds a value so use that
            indicesList[nowTerm][index] = indicesList[nowTerm][totalSize - 1];
        }

        nonce++;

        // // eventInfos[nowTerm].bought++;
        // // Don't allow a zero index, start counting at 1
        return value + eventInfos[nowTerm].startTokenId;
    }

    function randomQuality(uint256 _term) internal returns (uint) {
        uint totalWeight = qualityWeightList[_term].weight1 + qualityWeightList[_term].weight2 +
        qualityWeightList[_term].weight3 + qualityWeightList[_term].weight4;

        require(totalWeight != 0, "total weight error");

        nonce++;
        uint weight = uint(keccak256(abi.encodePacked(nonce, _msgSender(), block.difficulty, block.timestamp))) % totalWeight;

        uint curWeight = qualityWeightList[_term].weight1;
        if (weight < curWeight)
            return 10;

        curWeight += qualityWeightList[_term].weight2;
        if (weight < curWeight)
            return 20;

        curWeight += qualityWeightList[_term].weight3;
        if (weight < curWeight)
            return 30;

        return 40;
    }

    function getAllTokensByOwner(address _account) external view returns (uint256[] memory)
    {
        uint256 length = balanceOf(_account);
        uint256[] memory result = new uint256[](length);

        for (uint i = 0; i < length; i++)
            result[i] = tokenOfOwnerByIndex(_account, i);

        return result;
    }

    struct ReturnTokenInfo {
        uint256 tokenId;
        uint256 quality;
    }

    function getAddressAllTokenIdAndQuality(address _account) external view returns (ReturnTokenInfo[] memory)
    {
        uint256 length = balanceOf(_account);
        ReturnTokenInfo[] memory result = new ReturnTokenInfo[](length);

        for (uint i = 0; i < length; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_account, i);

            ReturnTokenInfo memory o = ReturnTokenInfo({
                tokenId: tokenId,
                quality: quality[tokenId]
            });

            result[i] = o;
        }

        return result;
    }

    // 提现
    function extract(address payable _address) public checkAdmin
    {
        _address.transfer(address(this).balance);
    }

    // 带品质的提现, 可以更改链上品质内容
    function withdraw(address _from, address _to, uint256 _tokenId, uint256 _quality) external checkAdmin
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
}

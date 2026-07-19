// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CHEOMA (처마) — the communal wish-tile roof, built on GIWA
/// @notice Digital giwa bulsa (기와불사): at Korean temples, people donate roof
///         tiles and write their wishes on them before a hall is built. GIWAJIP
///         brings that tradition on-chain — anyone lays a tile on a shared roof,
///         picks its glaze color and inscribes a wish. Each tile is a fully
///         on-chain ERC-721 (art + metadata generated in the contract, no IPFS).
///         One tile is fragile; together they make a roof. That is GIWA.
/// @dev    Zero external dependencies. Tile ids map to a WIDTH x HEIGHT grid,
///         id = y * WIDTH + x.
contract Cheoma {
    // ---------------------------------------------------------------- roof --
    uint256 public constant WIDTH = 64;
    uint256 public constant HEIGHT = 32;
    uint256 public constant TOTAL_TILES = WIDTH * HEIGHT; // 2048
    uint256 public constant MAX_PER_WALLET = 16;
    uint256 public constant MAX_WISH_BYTES = 140;
    uint256 public constant MILESTONE = 256;

    struct Tile {
        address giver;   // original donor (never changes, even if NFT moves)
        uint24 color;    // glaze color, RGB
        uint64 laidAt;   // block timestamp
        string wish;     // inscription
    }

    mapping(uint256 => Tile) private _tiles;
    uint256 public laidCount;

    /// @notice Donations attached to tiles are forwarded here untouched.
    address public immutable roofFund;

    event TileLaid(uint256 indexed id, address indexed giver, uint24 color, string wish, uint256 donation);
    event RoofMilestone(uint256 count);

    // -------------------------------------------------------------- erc721 --
    string public constant name = "CHEOMA";
    string public constant symbol = "TILE";

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(address => uint256) public tilesLaidBy;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(address roofFund_) {
        require(roofFund_ != address(0), "fund=0");
        roofFund = roofFund_;
    }

    // ----------------------------------------------------------- lay tiles --
    /// @notice Lay a tile on the roof: pick a spot, a glaze color and a wish.
    ///         Attach ETH if you wish to donate — it goes straight to roofFund.
    function layTile(uint256 id, uint24 color, string calldata wish) external payable {
        require(id < TOTAL_TILES, "off the roof");
        require(_owners[id] == address(0), "tile taken");
        require(bytes(wish).length <= MAX_WISH_BYTES, "wish too long");
        require(tilesLaidBy[msg.sender] < MAX_PER_WALLET, "wallet cap");

        _tiles[id] = Tile({giver: msg.sender, color: color, laidAt: uint64(block.timestamp), wish: wish});
        tilesLaidBy[msg.sender] += 1;
        laidCount += 1;

        _owners[id] = msg.sender;
        _balances[msg.sender] += 1;
        emit Transfer(address(0), msg.sender, id);
        emit TileLaid(id, msg.sender, color, wish, msg.value);

        if (laidCount % MILESTONE == 0) emit RoofMilestone(laidCount);

        if (msg.value > 0) {
            (bool ok,) = roofFund.call{value: msg.value}("");
            require(ok, "donation failed");
        }
    }

    // --------------------------------------------------------------- views --
    function tileOf(uint256 id) external view returns (Tile memory) {
        require(_owners[id] != address(0), "empty spot");
        return _tiles[id];
    }

    /// @notice Packed range read for grid rendering. Unlaid tiles return zeros.
    function getRange(uint256 start, uint256 count)
        external
        view
        returns (address[] memory givers, uint24[] memory colors)
    {
        require(start + count <= TOTAL_TILES, "range");
        givers = new address[](count);
        colors = new uint24[](count);
        for (uint256 i; i < count; ++i) {
            Tile storage t = _tiles[start + i];
            givers[i] = t.giver;
            colors[i] = t.color;
        }
    }

    function coordinates(uint256 id) public pure returns (uint256 x, uint256 y) {
        return (id % WIDTH, id / WIDTH);
    }

    // ------------------------------------------------------ on-chain art ----
    /// @notice Sumaksae (수막새) — the round decorative end-cap of a giwa tile,
    ///         drawn entirely on-chain in the giver's chosen glaze.
    function tileSVG(uint256 id) public view returns (string memory) {
        Tile storage t = _tiles[id];
        string memory hexColor = _hex(t.color);
        (uint256 x, uint256 y) = coordinates(id);
        bytes32 seed = keccak256(abi.encodePacked(id, t.giver));
        uint256 petals = 6 + (uint256(uint8(seed[0])) % 3); // 6..8 petals

        string memory petalMarks;
        for (uint256 i; i < petals; ++i) {
            petalMarks = string.concat(
                petalMarks,
                '<ellipse cx="180" cy="105" rx="26" ry="52" fill="',
                hexColor,
                '" opacity="0.85" transform="rotate(',
                _str((360 * i) / petals),
                ' 180 180)"/>'
            );
        }
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 360">',
            '<rect width="360" height="360" fill="#141210"/>',
            '<circle cx="180" cy="180" r="150" fill="#26221d"/>',
            '<circle cx="180" cy="180" r="150" fill="none" stroke="', hexColor, '" stroke-width="10" opacity="0.9"/>',
            petalMarks,
            '<circle cx="180" cy="180" r="34" fill="', hexColor, '"/>',
            '<text x="180" y="332" text-anchor="middle" font-family="monospace" font-size="20" fill="#8a8378">#',
            _str(id), ' (', _str(x), ',', _str(y), ')</text></svg>'
        );
    }

    function tokenURI(uint256 id) external view returns (string memory) {
        require(_owners[id] != address(0), "empty spot");
        Tile storage t = _tiles[id];
        (uint256 x, uint256 y) = coordinates(id);
        string memory json = string.concat(
            '{"name":"CHEOMA Tile #', _str(id),
            '","description":"', _escape(t.wish),
            '","attributes":[{"trait_type":"X","value":', _str(x),
            '},{"trait_type":"Y","value":', _str(y),
            '},{"trait_type":"Glaze","value":"', _hex(t.color),
            '"}],"image":"data:image/svg+xml;base64,', _b64(bytes(tileSVG(id))), '"}'
        );
        return string.concat("data:application/json;base64,", _b64(bytes(json)));
    }

    // ------------------------------------------------------ erc721 mechanics -
    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "owner=0");
        return _balances[owner];
    }

    function ownerOf(uint256 id) public view returns (address) {
        address owner = _owners[id];
        require(owner != address(0), "empty spot");
        return owner;
    }

    function approve(address to, uint256 id) external {
        address owner = ownerOf(id);
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "not allowed");
        _tokenApprovals[id] = to;
        emit Approval(owner, to, id);
    }

    function getApproved(uint256 id) external view returns (address) {
        require(_owners[id] != address(0), "empty spot");
        return _tokenApprovals[id];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 id) public {
        address owner = ownerOf(id);
        require(owner == from, "wrong from");
        require(to != address(0), "to=0");
        require(
            msg.sender == owner || msg.sender == _tokenApprovals[id] || _operatorApprovals[owner][msg.sender],
            "not allowed"
        );
        delete _tokenApprovals[id];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[id] = to;
        emit Transfer(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) external {
        safeTransferFrom(from, to, id, "");
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) public {
        transferFrom(from, to, id);
        if (to.code.length > 0) {
            (bool ok, bytes memory ret) =
                to.call(abi.encodeWithSelector(0x150b7a02, msg.sender, from, id, data));
            require(ok && ret.length >= 32 && bytes4(ret) == bytes4(0x150b7a02), "unsafe receiver");
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    // ------------------------------------------------------------- helpers --
    function _str(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 tmp = v;
        uint256 len;
        while (tmp != 0) { len++; tmp /= 10; }
        bytes memory buf = new bytes(len);
        while (v != 0) { buf[--len] = bytes1(uint8(48 + (v % 10))); v /= 10; }
        return string(buf);
    }

    function _hex(uint24 c) private pure returns (string memory) {
        bytes16 t = "0123456789abcdef";
        bytes memory buf = new bytes(7);
        buf[0] = "#";
        for (uint256 i; i < 6; ++i) {
            buf[6 - i] = t[(uint256(c) >> (4 * i)) & 0xf];
        }
        return string(buf);
    }

    /// @dev Escape backslash, quote and control chars so wishes stay valid JSON.
    function _escape(string memory s) private pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * 2);
        uint256 n;
        for (uint256 i; i < b.length; ++i) {
            bytes1 ch = b[i];
            if (ch == '"' || ch == "\\") { out[n++] = "\\"; out[n++] = ch; }
            else if (uint8(ch) < 0x20) { out[n++] = " "; }
            else { out[n++] = ch; }
        }
        assembly { mstore(out, n) }
        return string(out);
    }

    function _b64(bytes memory data) private pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        string memory result = new string(4 * ((data.length + 2) / 3));
        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            for { let dataPtr := data } lt(dataPtr, add(data, mload(data))) {} {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F)))) resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F)))) resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))  resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))          resultPtr := add(resultPtr, 1)
            }
            switch mod(mload(data), 3)
            case 1 { mstore8(sub(resultPtr, 1), 0x3d) mstore8(sub(resultPtr, 2), 0x3d) }
            case 2 { mstore8(sub(resultPtr, 1), 0x3d) }
        }
        return result;
    }
}

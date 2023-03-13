// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkleVerify is OwnableUpgradeable  {

    function initialize() public initializer
    {
        __Ownable_init();
    }

    function getMerkleLeaf(address _address) internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(_address));
    }

    function checkMerkle(bytes32[] calldata _merkleProof, address _address, bytes32 merkleRoot) public pure returns (bool)
    {
        return MerkleProof.verify(_merkleProof, merkleRoot, getMerkleLeaf(_address));
    }

    function check_arg1(bytes32[] calldata _merkleProof) public pure returns (bytes32[] memory)
    {
        return _merkleProof;
    }

    function check_arg2(address _address) public pure returns (address)
    {
        return _address;
    }

    function check_arg3(bytes32 merkleRoot) public pure returns (bytes32)
    {
        return merkleRoot;
    }
}
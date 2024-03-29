pragma solidity 0.7.6;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IERC998TopDownERC20.sol";

// TODO: layer in composability for ERC20 tokens based on EIP-998 (Top Down ERC20 specifically)
contract MyComposableNFT is
    ERC721("MyComposable", "MYC"),
    IERC998TopDownERC20,
    IERC998TopDownERC20Enumerable
{
    using Address for address;

    // State Variables
    mapping(uint256 => address[]) private erc20Contracts;
    mapping(uint256 => mapping(address => uint256)) private erc20ContractIndex;
    mapping(uint256 => mapping(address => uint256)) private erc20Balances;

    // Functions
    function mint(address _recipient, uint256 _tokenId) external {
        _mint(_recipient, _tokenId);
    }

    function balanceOfERC20(uint256 _tokenId, address _erc20Contract)
        public
        view
        override
        returns (uint256)
    {
        return erc20Balances[_tokenId][_erc20Contract];
    }

    function erc20ContractByIndex(uint256 _tokenId, uint256 _index)
        public
        view
        override
        returns (address)
    {
        require(
            _index < erc20Contracts[_tokenId].length,
            "The length of token data should larger than zero."
        );
        return erc20Contracts[_tokenId][_index];
    }

    function totalERC20Contracts(uint256 _tokenId)
        public
        view
        override
        returns (uint256)
    {
        return erc20Contracts[_tokenId].length;
    }

    function transferERC20(
        uint256 _tokenId,
        address _to,
        address _erc20Contract,
        uint256 _value
    ) external override {
        require(_to != address(0), "[ERC20 Transfer] Can't transfer to zero address.");
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "[ERC721 Transfer] Caller must be owner or must be approved."
        );

        removeERC20(_tokenId, _erc20Contract, _value);

        require(
            IERC20AndERC223(_erc20Contract).transfer(_to, _value),
            "[ERC20 Transfer] Transaction failed."
        );

        emit TransferERC20(_tokenId, _to, _erc20Contract, _value);
    }

    // implementation of ERC 223
    function transferERC223(
        uint256 _tokenId,
        address _to,
        address _erc223Contract,
        uint256 _value,
        bytes calldata _data
    ) external override {
        require(_to != address(0), "[ERC223 Transfer] Can't transfer to zero address.");
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "[ERC721 Transfer] Caller must be owner or must be approved."
        );

        removeERC20(_tokenId, _erc223Contract, _value);

        require(
            IERC20AndERC223(_erc223Contract).transfer(_to, _value, _data),
            "[ERC223 Transfer] Transaction failed."
        );

        emit TransferERC20(_tokenId, _to, _erc223Contract, _value);
    }

    function getERC20(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) public override {
        require(_from == msg.sender, "Not allowed to getERC20");

        erc20Received(_from, _tokenId, _erc20Contract, _value);

        require(
            IERC20AndERC223(_erc20Contract).transferFrom(
                _from,
                address(this),
                _value
            ),
            "ERC20 transfer failed."
        );
    }

    function tokenFallback(
        address _from,
        uint256 _value,
        bytes calldata _data
    ) external override {
        require(
            _data.length > 0,
            "The length of token data should larger than zero."
        );
        require(Address.isContract(msg.sender), "msg.sender is not a contract");

        uint256 tokenId;
        assembly {
            tokenId := calldataload(132)
        }
        if (_data.length < 32) {
            tokenId = tokenId >> (256 - _data.length * 8);
        }

        erc20Received(_from, tokenId, msg.sender, _value);
    }

    function erc20Received(
        address _from,
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) private {
        require(_exists(_tokenId), "_tokenId does not exist.");

        if (_value == 0) {
            return;
        }
        uint256 erc20Balance = erc20Balances[_tokenId][_erc20Contract];
        if (erc20Balance == 0) {
            erc20ContractIndex[_tokenId][_erc20Contract] = erc20Contracts[
                _tokenId
            ].length;
            erc20Contracts[_tokenId].push(_erc20Contract);
        }
        erc20Balances[_tokenId][_erc20Contract] = erc20Balance + _value;

        emit ReceivedERC20(_from, _tokenId, _erc20Contract, _value);
    }

    function removeERC20(
        uint256 _tokenId,
        address _erc20Contract,
        uint256 _value
    ) private {
        if (_value == 0) {
            return;
        }
        uint256 erc20Balance = erc20Balances[_tokenId][_erc20Contract];

        require(
            erc20Balance >= _value,
            "Don't have enough token to transfer."
        );

        uint256 newERC20Balance = erc20Balance - _value;
        erc20Balances[_tokenId][_erc20Contract] = newERC20Balance;
        if (newERC20Balance == 0) {
            uint256 lastContractIndex = erc20Contracts[_tokenId].length - 1;
            address lastContract = erc20Contracts[_tokenId][lastContractIndex];
            if (_erc20Contract != lastContract) {
                uint256 contractIndex = erc20ContractIndex[_tokenId][
                    _erc20Contract
                ];
                erc20Contracts[_tokenId][contractIndex] = lastContract;
                erc20ContractIndex[_tokenId][lastContract] = contractIndex;
            }
            erc20Contracts[_tokenId].pop();
        }
    }
}

// SPDX-License-Identifier:MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";
import "../interfaces/IForwarder.sol";
import "../utils/RSKAddrValidator.sol";

/* solhint-disable no-inline-assembly */
/* solhint-disable avoid-low-level-calls */

contract SmartWallet is IForwarder {
    //slot for owner = bytes32(uint256(keccak256('eip1967.proxy.owner')) - 1) = a7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a
    bytes32 private constant _OWNER_SLOT =
        0xa7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a;
    using ECDSA for bytes32;

    uint256 public override nonce;
    bytes32 public constant DATA_VERSION_HASH = keccak256("2");
    bytes32 public domainSeparator;

    constructor() public {
        _setOwner(msg.sender);
    }

    function _buildDomainSeparator() internal {
        domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ), //hex"8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f",
                keccak256("RSK Enveloping Transaction"), //DOMAIN_NAME hex"d41b7f69f4d7734774d21b5548d74704ad02f9f1545db63927a1d58479c576c8"
                DATA_VERSION_HASH,
                _getChainID(),
                address(this)
            )
        );
    }

    function _setOwner(address owner) private {
        //To avoid re-entrancy attacks by external contracts, the first thing we do is set
        //the variable that controls "is initialized"
        //We set this instance as initialized, by
        //storing the logic address
        //Set the owner of this Smart Wallet
        //slot for owner = bytes32(uint256(keccak256('eip1967.proxy.owner')) - 1) = a7b53796fd2d99cb1f5ae019b54f9e024446c3d12b483f733ccc62ed04eb126a
        bytes32 ownerCell = keccak256(abi.encodePacked(owner));

        assembly {
            sstore(_OWNER_SLOT, ownerCell)
        }
    }

    function verify(
        bytes32 suffixData,
        ForwardRequest memory req,
        bytes calldata sig
    ) external view override {
        _verifySig(suffixData, req, sig);
    }

    function getOwner() public view override returns (bytes32 owner) {
        assembly {
            owner := sload(_OWNER_SLOT)
        }
    }

    function recover(
        address owner,
        address factory,
        address swTemplate,
        address destinationContract,
        uint256 index,
        bytes calldata data
    ) external payable returns (bool success, bytes memory ret) {
        address wallet = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            factory,
                            keccak256(
                                abi.encodePacked(owner, msg.sender, index)
                            ), //salt
                            keccak256(
                                abi.encodePacked(
                                    hex"602D3D8160093D39F3363D3D373D3D3D3D363D73",
                                    swTemplate,
                                    hex"5AF43D923D90803E602B57FD5BF3"
                                )
                            )
                        )
                    )
                )
            )
        );

        require(wallet == address(this), "Invalid recoverer");

        if (destinationContract != address(0)) {
            (success, ret) = destinationContract.call{value: msg.value}(data);
        }

        //If any balance has been added then trasfer it to the owner EOA
        if (address(this).balance > 0) {
            //sent any value left to the recoverer account
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function directExecute(
        address to,
        bytes calldata data
    ) external payable override returns (bool success, bytes memory ret) {
        //Verify Owner
        require(
            getOwner() == keccak256(abi.encodePacked(msg.sender)),
            "Not the owner of the SmartWallet"
        );

        (success, ret) = to.call{value: msg.value}(data);

        //If any balance has been added then trasfer it to the owner EOA
        if (address(this).balance > 0) {
            //can't fail: req.from signed (off-chain) the request, so it must be an EOA...
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    function execute(
        bytes32 suffixData,
        ForwardRequest memory req,
        address feesReceiver,
        bytes calldata sig
    )
        external
        payable
        virtual
        override
        returns (bool success, bytes memory ret)
    {
        (sig);
        require(msg.sender == req.relayHub, "Invalid caller");

        _verifySig(suffixData, req, sig);
        require(
            req.validUntilTime == 0 || req.validUntilTime > block.timestamp,
            "SW: request expired"
        );
        nonce++;

        if (req.tokenAmount > 0) {
            (success, ret) = req.tokenContract.call{gas: req.tokenGas}(
                abi.encodeWithSelector(
                    hex"a9059cbb", //transfer(address,uint256)
                    feesReceiver,
                    req.tokenAmount
                )
            );

            require(
                success && (ret.length == 0 || abi.decode(ret, (bool))),
                "Unable to pay for relay"
            );
        }

        //Why this require is not needed: in the case that the EVM implementation
        //sends gasleft() as req.gas  if gasleft() < req.gas (see EIP-1930),  which would end in the call reverting
        //If the relayer made this on purpose in order to collect the payment, since all gasLeft()
        //was sent to this call, then the next line would give an out of gas, and, as a consequence, will
        //revert the whole transaction, and the payment will not happen
        //But it could happen that the destination call makes a gasleft() check and decides to revert if it is
        //not enough, in that case there might be enough gas to complete the relay and the token payment would be collected
        //For that reason, the next require line must be left uncommented, to avoid malicious relayer attacks to destination contract
        //methods that revert if the gasleft() is not enough to execute whatever logic they have.

        require(gasleft() > req.gas, "Not enough gas left");
        (success, ret) = req.to.call{gas: req.gas, value: req.value}(req.data);

        //If any balance has been added then trasfer it to the owner EOA
        uint256 balanceToTransfer = address(this).balance;
        if (balanceToTransfer > 0) {
            //can't fail: req.from signed (off-chain) the request, so it must be an EOA...
            payable(req.from).transfer(balanceToTransfer);
        }
    }

    function _getChainID() private pure returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    function _verifySig(
        bytes32 suffixData,
        ForwardRequest memory req,
        bytes memory sig
    ) internal view {
        //Verify Owner
        require(
            getOwner() == keccak256(abi.encodePacked(req.from)),
            "Not the owner of the SmartWallet"
        );

        //Verify nonce
        require(nonce == req.nonce, "nonce mismatch");

        require(
            RSKAddrValidator.safeEquals(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        domainSeparator,
                        keccak256(_getEncoded(suffixData, req))
                    )
                ).recover(sig),
                req.from
            ),
            "Signature mismatch"
        );
    }

    function _getEncoded(
        bytes32 suffixData,
        ForwardRequest memory req
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                keccak256(
                    "RelayRequest(address relayHub,address from,address to,address tokenContract,uint256 value,uint256 gas,uint256 nonce,uint256 tokenAmount,uint256 tokenGas,uint256 validUntilTime,bytes data,RelayData relayData)RelayData(uint256 gasPrice,address feesReceiver,address callForwarder,address callVerifier)"
                ), //requestTypeHash,
                abi.encode(
                    req.relayHub,
                    req.from,
                    req.to,
                    req.tokenContract,
                    req.value,
                    req.gas,
                    req.nonce,
                    req.tokenAmount,
                    req.tokenGas,
                    req.validUntilTime,
                    keccak256(req.data)
                ),
                suffixData
            );
    }

    function isInitialized() external view returns (bool) {
        if (getOwner() == bytes32(0)) {
            return false;
        } else {
            return true;
        }
    }

    /**
     * This Proxy will first charge for the deployment and then it will pass the
     * initialization scope to the wallet logic.
     * This function can only be called once, and it is called by the Factory during deployment
     * @param owner - The EOA that will own the smart wallet
     * @param tokenAddr - The Token used for payment of the deploy
     * @param tokenRecipient - Recipient of payment
     * @param tokenAmount - Amount to pay
     */

    function initialize(
        address owner,
        address tokenAddr,
        address tokenRecipient,
        uint256 tokenAmount,
        uint256 tokenGas
    ) external {
        require(getOwner() == bytes32(0), "already initialized");

        _setOwner(owner);

        //we need to initialize the contract
        if (tokenAmount > 0) {
            (bool success, bytes memory ret) = tokenAddr.call{gas: tokenGas}(
                abi.encodeWithSelector(
                    hex"a9059cbb", //transfer(address,uint256)
                    tokenRecipient,
                    tokenAmount
                )
            );

            require(
                success && (ret.length == 0 || abi.decode(ret, (bool))),
                "Unable to pay for deployment"
            );
        }

        _buildDomainSeparator();
    }

    /* solhint-disable no-empty-blocks */
    receive() external payable {}
}

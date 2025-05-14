// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PenpieBribeManager} from "./bribeMarket/PenpieBribeManager.sol";

contract PointsReader is Initializable, OwnableUpgradeable {

    struct Tag{
        string title;
        string link;
        string additionalInfo;
    }

    address public bribeManager;
    mapping(address => Tag[]) public tags;
    mapping(address => bool) public whiteListedWallet;


    /* ============ Errors ============ */
    error MarketHasNoTags();
    error NoSuchTagExistsOnMarket();
    error OutOfBounds();

    /* ============ Events ============ */
    event TagAdded(address market, string title, string link, string additionalInfo);
    event TagRemoved(address market, string title);
    event TagModified(address market, string oldTitle, string newTitle, string link, string additionalInfo);
    event WalletWhitelisted(address wallet, bool allow);
    event BribeManagerSet(address bribeManager);

    /* ============ Constructor ============ */

    constructor(){
        _disableInitializers();
    }

    function initialize(address _bribeManager) public initializer {
        bribeManager = _bribeManager;
        __Ownable_init();
    }

    /* ============ Modifiers ============ */

    modifier _onlyWhiteListedWallet() {
        if(!whiteListedWallet[msg.sender]) revert("Not a whiteListed Wallet");
        _;
    }

    /* ============ External Getters ============ */

    function getTotalTagsOfMarket(address market) public view returns(uint256){
        return tags[market].length;
    }

    function getTotalPoolsWithTags() public view returns(uint256){
        uint256 totalPools = PenpieBribeManager(bribeManager).getPoolLength();
        uint256 count = 0;
        for(uint256 i = 0; i < totalPools; i++){
            (address market,,) = PenpieBribeManager(bribeManager).pools(i);
            if(tags[market].length > 0){
                count++;
            }
        }
        return count;
    }

    function getTagsForMarket(address market) public view returns(Tag[] memory){
        return (tags[market]);
    }

    function getTags() public view returns(Tag[][] memory, address[] memory){
        uint256 totalPoolsWithTags = getTotalPoolsWithTags();
        uint256 totalPools = PenpieBribeManager(bribeManager).getPoolLength();
        Tag[][] memory result = new Tag[][](totalPoolsWithTags);
        address[] memory markets = new address[](totalPoolsWithTags);
        uint256 count = 0;
        for(uint256 i = 0; i < totalPools; i++){
            (address market,,) = PenpieBribeManager(bribeManager).pools(i);

            if(tags[market].length != 0){
                result[count] = getTagsForMarket(market);
                markets[count++] = market;
            }
        }
        
        return (result, markets);
    }

    /* ============ WhiteListed Wallet Functions ============ */

    function addTagForMarket(
        address market, 
        string calldata _title, 
        string calldata _link, 
        string calldata _additionalInfo
    ) external _onlyWhiteListedWallet {

        tags[market].push(
            Tag({
                title: _title,
                link: _link,
                additionalInfo: _additionalInfo
            })
        );

        emit TagAdded(market, _title, _link, _additionalInfo);
    }

    function removeTagUsingIndex(address market, uint256 idx) public _onlyWhiteListedWallet {
        if(idx >= tags[market].length) revert OutOfBounds();

        string memory title = tags[market][idx].title;
        tags[market][idx] = tags[market][tags[market].length - 1];
        tags[market].pop();

        emit TagRemoved(market, title);
    }

    function removeTagUsingExactName(address market, string calldata title) external _onlyWhiteListedWallet {
        uint256 idx = 0;
        uint256 i = 0;
        if(tags[market].length == 0) revert MarketHasNoTags();

        for(i = 0; i < tags[market].length; i++){
            if(keccak256(abi.encodePacked(tags[market][i].title)) == keccak256(abi.encodePacked(title))){
                idx = i;
                break;
            }
        }
        if(tags[market].length == i) revert NoSuchTagExistsOnMarket();
        removeTagUsingIndex(market, idx);

        emit TagRemoved(market, title);
    }

    function modifyTagUsingIndex(
        address market, 
        uint256 idx, 
        string calldata _title, 
        string calldata _link, 
        string calldata _additionalInfo
    ) public _onlyWhiteListedWallet {

        if(idx >= tags[market].length) revert OutOfBounds();

        tags[market][idx].title = _title;
        tags[market][idx].link = _link;
        tags[market][idx].additionalInfo = _additionalInfo;

        emit TagModified(market, tags[market][idx].title, _title, _link, _additionalInfo);
    }

    function modifyTagUsingExactName(
        address market, 
        string calldata oldTitle, 
        string calldata newTitle, 
        string calldata _link, 
        string calldata _additionalInfo
    ) external _onlyWhiteListedWallet {

        uint256 idx = 0;
        uint256 i = 0;
        if(tags[market].length == 0) revert MarketHasNoTags();
        for(i = 0; i < tags[market].length; i++){
            if(keccak256(abi.encodePacked(tags[market][i].title)) == keccak256(abi.encodePacked(oldTitle))){
                idx = i;
                break;
            }
        }
        if(tags[market].length == i) revert NoSuchTagExistsOnMarket();

        modifyTagUsingIndex(market, idx, newTitle, _link, _additionalInfo);

        emit TagModified(market, oldTitle, newTitle, _link, _additionalInfo);
    }

    /* ============ Admin Functions ============ */

    function addWhiteListedWallet(address wallet, bool allow) external onlyOwner {
        whiteListedWallet[wallet] = allow;

        emit WalletWhitelisted(wallet, allow);
    }

    function setBribeManager(address _bribeManager) public onlyOwner {
        bribeManager = _bribeManager;

        emit BribeManagerSet(_bribeManager);
    }
    
}